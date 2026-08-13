-- 0043_personal_interest_subset_ratios.sql
--
-- 为个人单次兴趣提供两个非穷尽子集比例。函数只返回固定的
-- `interest_3_4_ratio` 与 `interest_0_ratio` 两行，不暴露接触明细或用户身份。
-- 两个分子共享同一个有效接触场次分母，但不要求分子相加等于分母；这与
-- 0042 的五档 exhaustive RatioMetricValue 是不同的值合同。

CREATE FUNCTION app_data.read_personal_interest_subset_ratios(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS TABLE (
  metric_id text,
  numerator bigint,
  denominator bigint,
  unknown_count bigint,
  refused_count bigint,
  not_applicable_count bigint,
  unanswered_count bigint,
  excluded_count bigint,
  percentage_basis_points integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF trusted_app_user_id IS NULL
    OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL
    OR from_utc IS NULL
    OR until_utc IS NULL
    OR from_utc >= until_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal interest subset ratios request';
  END IF;

  -- The caller supplies a trusted identity from the Backend, but the database
  -- still reauthorizes the complete personal scope at the SQL boundary.
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal interest subset ratios scope forbidden';
  END IF;

  RETURN QUERY
  WITH scoped_contacts AS (
    SELECT contact_row.interest_level
    FROM app_data.contacts AS contact_row
    WHERE contact_row.app_user_id = trusted_app_user_id
      AND contact_row.workspace_id = trusted_workspace_id
      AND contact_row.project_id = trusted_project_id
      -- timestamptz values are compared as instants; this is the UTC
      -- half-open interval [from_utc, until_utc).
      AND contact_row.occurred_at_utc >= from_utc
      AND contact_row.occurred_at_utc < until_utc
      AND contact_row.lifecycle_status = 'active'
  ),
  aggregate AS (
    SELECT
      COUNT(*)::bigint AS denominator,
      COUNT(scoped_contacts.interest_level) FILTER (
        WHERE scoped_contacts.interest_level IN (3, 4)
      )::bigint AS high_numerator,
      COUNT(scoped_contacts.interest_level) FILTER (
        WHERE scoped_contacts.interest_level = 0
      )::bigint AS zero_numerator
    FROM scoped_contacts
  ),
  metric_rows AS (
    SELECT
      1 AS metric_order,
      'interest_3_4_ratio'::text AS metric_id,
      aggregate.high_numerator AS numerator,
      aggregate.denominator
    FROM aggregate
    UNION ALL
    SELECT
      2 AS metric_order,
      'interest_0_ratio'::text AS metric_id,
      aggregate.zero_numerator AS numerator,
      aggregate.denominator
    FROM aggregate
  )
  SELECT
    metric_rows.metric_id,
    metric_rows.numerator,
    metric_rows.denominator,
    0::bigint AS unknown_count,
    0::bigint AS refused_count,
    0::bigint AS not_applicable_count,
    0::bigint AS unanswered_count,
    0::bigint AS excluded_count,
    CASE
      WHEN metric_rows.denominator = 0 THEN NULL::integer
      ELSE floor(
        (
          metric_rows.numerator::numeric * 10000
          + metric_rows.denominator::numeric / 2
        ) / metric_rows.denominator::numeric
      )::integer
    END AS percentage_basis_points
  FROM metric_rows
  ORDER BY metric_rows.metric_order;
END
$function$;

COMMENT ON FUNCTION app_data.read_personal_interest_subset_ratios(
  uuid, uuid, uuid, timestamptz, timestamptz
) IS
  'Backend-only personal 3-4 and 0 interest subset ratios over a UTC half-open interval; both rows share an active contact-session denominator, percentages are integer basis points rounded half-up, and missing/excluded fields are schema-proven zero for the current core interest fact.';

REVOKE ALL
  ON FUNCTION app_data.read_personal_interest_subset_ratios(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_interest_subset_ratios(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;
