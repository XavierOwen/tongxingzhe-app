-- 0026_management_report_execution.sql
--
-- 把固定报告定义、两个完整周、已接受有效接触和隐私完整网格组合成私有
-- 报告。按推广者聚合的贡献只存在于函数内部；输出不含身份或隐藏精确值。
-- 当前函数不做成员授权，不授予 runtime，也不是生产管理端点。

CREATE FUNCTION
  app_private.execute_management_contact_session_report_v1(
    requested_project_id uuid,
    requested_report_id text,
    requested_report_version integer,
    requested_reporting_time_zone text,
    requested_data_cutoff_utc timestamp with time zone
  )
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  canonical_request jsonb;
  report_periods jsonb;
  contribution_document jsonb;
  protected_cells jsonb;
BEGIN
  canonical_request =
    app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', requested_report_id,
        'report_version', requested_report_version
      )
    );

  IF requested_project_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM app_data.projects AS project_row
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id = project_row.workspace_id
    WHERE project_row.project_id = requested_project_id
      AND project_row.status = 'active'
      AND workspace_row.deleted_at IS NULL
      AND workspace_row.workspace_kind = 'organization'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report project';
  END IF;

  report_periods = app_private.resolve_management_report_periods_v1(
    requested_reporting_time_zone,
    requested_data_cutoff_utc
  );
  IF canonical_request->>'period_boundary_id'
    <> report_periods->>'period_boundary_id'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report period definition mismatch';
  END IF;

  WITH bounded_contacts AS (
    SELECT
      CASE
        WHEN contact_row.occurred_at_utc <
          (report_periods->'current_period'->>'start_utc')::timestamptz
          THEN 'previous'
        ELSE 'current'
      END AS period_key,
      contact_row.channel,
      contact_row.app_user_id::text AS contributor_key
    FROM app_data.contacts AS contact_row
    WHERE contact_row.project_id = requested_project_id
      AND contact_row.lifecycle_status = 'active'
      AND contact_row.first_submitted_at_utc <= requested_data_cutoff_utc
      AND contact_row.occurred_at_utc >=
        (report_periods->'previous_period'->>'start_utc')::timestamptz
      AND contact_row.occurred_at_utc <
        (report_periods->'current_period'->>'until_utc')::timestamptz
  ),
  contributions AS (
    SELECT
      bounded_contacts.period_key,
      bounded_contacts.channel,
      bounded_contacts.contributor_key,
      count(*)::bigint AS unit_count
    FROM bounded_contacts
    GROUP BY
      bounded_contacts.period_key,
      bounded_contacts.channel,
      bounded_contacts.contributor_key
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period_key', contributions.period_key,
        'channel', contributions.channel,
        'contributor_key', contributions.contributor_key,
        'unit_count', contributions.unit_count
      ) ORDER BY
        contributions.period_key,
        contributions.channel,
        contributions.contributor_key
    ),
    '[]'::jsonb
  ) INTO contribution_document
  FROM contributions;

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'category_key', protected.category_key,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  ) INTO protected_cells
  FROM app_private.protect_management_contact_session_grid_v1(
    contribution_document
  ) AS protected;

  RETURN jsonb_build_object(
    'report_id', canonical_request->'report_id',
    'report_version', canonical_request->'report_version',
    'metric_id', canonical_request->'metric_id',
    'metric_version', canonical_request->'metric_version',
    'dimension', canonical_request->'dimension',
    'query_fingerprint', canonical_request->'query_fingerprint',
    'privacy_policy', canonical_request->'privacy_policy',
    'source_scope', 'backend_accepted_contacts',
    'project_id', requested_project_id,
    'periods', report_periods,
    'cells', protected_cells
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.execute_management_contact_session_report_v1(
    uuid,
    text,
    integer,
    text,
    timestamp with time zone
  )
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_private.execute_management_contact_session_report_v1(
    uuid,
    text,
    integer,
    text,
    timestamp with time zone
  )
IS 'Builds a private fixed report from accepted active contacts and returns only the privacy-protected grid; performs no authorization.';
