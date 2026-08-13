-- 0049_personal_follow_up_consent_ratio.sql
--
-- 读取项目明确启用的个人后续联系同意占比。公开入口重新解析可信身份，
-- 未启用时在接触事实查询之前返回独立状态；启用后才统计当前有效对象关联。

CREATE FUNCTION app_data.read_personal_follow_up_consent_ratio_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_metric_id text,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  trusted_app_user_id uuid;
  trusted_workspace_id uuid;
  latest_version
    app_private.project_follow_up_consent_opt_in_versions%ROWTYPE;
  yes_count bigint;
  no_count bigint;
  refused_count bigint;
  not_applicable_count bigint;
  unanswered_count bigint;
  denominator bigint;
  percentage_basis_points integer;
BEGIN
  IF trusted_issuer IS NULL
    OR trusted_subject IS NULL
    OR requested_project_id IS NULL
    OR requested_metric_id IS DISTINCT FROM 'follow_up_consent_ratio@1'
    OR from_utc IS NULL
    OR until_utc IS NULL
    OR NOT isfinite(from_utc)
    OR NOT isfinite(until_utc)
    OR from_utc >= until_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal follow-up consent ratio request';
  END IF;

  -- Serialize against configuration changes before reauthorizing. The actor
  -- resolver also keeps the identity, account, personal workspace, and project
  -- rows locked through the read, so a concurrent revoke cannot leave a stale
  -- authorized result.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-follow-up-consent-opt-in:' || requested_project_id::text,
      0
    )
  );

  trusted_app_user_id :=
    app_private.resolve_project_follow_up_consent_opt_in_actor_v1(
      trusted_issuer,
      trusted_subject,
      requested_project_id
    );

  SELECT project_row.workspace_id
  INTO STRICT trusted_workspace_id
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = requested_project_id;

  SELECT version_row.*
  INTO latest_version
  FROM app_private.project_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.project_id = requested_project_id
  ORDER BY version_row.version_number DESC
  LIMIT 1;

  IF NOT FOUND OR NOT latest_version.enabled THEN
    RETURN jsonb_build_object(
      'contract_id', 'personal_follow_up_consent_ratio_result_v1',
      'metric_id', requested_metric_id,
      'project_id', requested_project_id,
      'status', 'not_enabled'
    );
  END IF;

  SELECT
    count(*) FILTER (
      WHERE link_row.follow_up_consent = 'yes'
    )::bigint,
    count(*) FILTER (
      WHERE link_row.follow_up_consent = 'no'
    )::bigint,
    count(*) FILTER (
      WHERE link_row.follow_up_consent = 'refused'
    )::bigint,
    count(*) FILTER (
      WHERE link_row.follow_up_consent = 'not_applicable'
    )::bigint,
    count(*) FILTER (
      WHERE link_row.follow_up_consent = 'unknown'
    )::bigint
  INTO
    yes_count,
    no_count,
    refused_count,
    not_applicable_count,
    unanswered_count
  FROM app_data.contacts AS contact_row
  JOIN app_data.contact_target_links AS link_row
    ON link_row.contact_id = contact_row.contact_id
   AND link_row.revision_number = contact_row.current_revision
  WHERE contact_row.app_user_id = trusted_app_user_id
    AND contact_row.workspace_id = trusted_workspace_id
    AND contact_row.project_id = requested_project_id
    AND contact_row.occurred_at_utc >= from_utc
    AND contact_row.occurred_at_utc < until_utc
    AND contact_row.lifecycle_status = 'active';

  denominator := yes_count + no_count;
  percentage_basis_points := CASE
    WHEN denominator = 0 THEN NULL::integer
    ELSE floor(
      (
        yes_count::numeric * 10000
        + denominator::numeric / 2
      ) / denominator::numeric
    )::integer
  END;

  RETURN jsonb_build_object(
    'contract_id', 'personal_follow_up_consent_ratio_result_v1',
    'metric_id', requested_metric_id,
    'project_id', requested_project_id,
    'status', 'ready',
    'period', jsonb_build_object(
      'from_utc', to_char(
        from_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      ),
      'until_utc', to_char(
        until_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )
    ),
    'value', jsonb_build_object(
      'yes_count', yes_count,
      'no_count', no_count,
      'numerator', yes_count,
      'unknown_count', 0,
      'refused_count', refused_count,
      'not_applicable_count', not_applicable_count,
      'unanswered_count', unanswered_count,
      'excluded_count', 0,
      'denominator', denominator,
      'percentage_basis_points', percentage_basis_points
    )
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.read_personal_follow_up_consent_ratio_v1(
    text, text, uuid, text, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.read_personal_follow_up_consent_ratio_v1(
    text, text, uuid, text, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.read_personal_follow_up_consent_ratio_v1(
  text, text, uuid, text, timestamptz, timestamptz
) IS
  'Backend-only personal follow-up consent ratio for an explicitly enabled project. The trusted issuer and subject are reauthorized, not_enabled returns before contact facts are read, and ready results count current active contact-target links over a UTC half-open interval.';
