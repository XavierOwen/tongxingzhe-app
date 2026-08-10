-- 0024_management_report_contract.sql
--
-- 注册首个固定管理报告，并把客户端请求缩减为报告 ID 与版本。项目、时区、
-- 截止时间和执行身份只能由后续授权后的服务端流程提供。当前函数仍留在
-- app_private，不授予 runtime 使用权，也不构成管理查询端点。

CREATE TABLE app_private.management_report_definitions (
  report_id text NOT NULL
    CHECK (report_id ~ '^[a-z][a-z0-9_]{0,79}$'),
  report_version integer NOT NULL CHECK (report_version > 0),
  metric_id text NOT NULL CHECK (metric_id ~ '^[a-z][a-z0-9_]{0,79}$'),
  metric_version integer NOT NULL CHECK (metric_version > 0),
  dimension_key text NOT NULL
    CHECK (dimension_key ~ '^[a-z][a-z0-9_]{0,79}$'),
  period_grain text NOT NULL CHECK (period_grain IN ('week')),
  comparison_period_count integer NOT NULL
    CHECK (comparison_period_count = 2),
  privacy_policy text NOT NULL
    CHECK (privacy_policy ~ '^[a-z][a-z0-9_]{0,119}$'),
  required_capability text NOT NULL
    CHECK (required_capability ~ '^[a-z][a-z0-9_]{0,79}$'),
  query_fingerprint text NOT NULL
    CHECK (length(query_fingerprint) BETWEEN 1 AND 200),
  PRIMARY KEY (report_id, report_version),
  UNIQUE (query_fingerprint)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_definitions
  FROM PUBLIC, tongxingzhe_runtime;

INSERT INTO app_private.management_report_definitions (
  report_id,
  report_version,
  metric_id,
  metric_version,
  dimension_key,
  period_grain,
  comparison_period_count,
  privacy_policy,
  required_capability,
  query_fingerprint
) VALUES (
  'contact_sessions_by_channel_two_periods',
  1,
  'contact_sessions',
  1,
  'channel',
  'week',
  2,
  'management_contact_session_privacy_v1',
  'view_anonymous_analytics',
  'management-report:contact_sessions_by_channel_two_periods:v1'
);

CREATE FUNCTION app_private.reject_management_report_definition_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'versioned management report definitions are immutable';
END
$function$;

CREATE TRIGGER management_report_definitions_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_definitions
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_definition_mutation();

CREATE FUNCTION app_private.canonicalize_management_report_request_v1(
  requested_request jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  definition app_private.management_report_definitions%ROWTYPE;
BEGIN
  IF requested_request IS NULL
    OR jsonb_typeof(requested_request) <> 'object'
    OR requested_request <> jsonb_build_object(
      'report_id', 'contact_sessions_by_channel_two_periods',
      'report_version', 1
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report request';
  END IF;

  SELECT * INTO STRICT definition
  FROM app_private.management_report_definitions
  WHERE report_id = requested_request->>'report_id'
    AND report_version = (requested_request->>'report_version')::integer;

  RETURN jsonb_build_object(
    'report_id', definition.report_id,
    'report_version', definition.report_version,
    'metric_id', definition.metric_id,
    'metric_version', definition.metric_version,
    'dimension', definition.dimension_key,
    'period_grain', definition.period_grain,
    'comparison_period_count', definition.comparison_period_count,
    'privacy_policy', definition.privacy_policy,
    'required_capability', definition.required_capability,
    'query_fingerprint', definition.query_fingerprint
  );
EXCEPTION WHEN no_data_found THEN
  RAISE EXCEPTION USING
    ERRCODE = '22023',
    MESSAGE = 'invalid management report request';
END
$function$;

CREATE FUNCTION app_private.build_management_report_audit_envelope_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_report_id text,
  requested_report_version integer,
  requested_at timestamp with time zone,
  requested_result_status text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  registered_fingerprint text;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_at IS NULL
    OR NOT isfinite(requested_at)
    OR requested_result_status IS NULL
    OR requested_result_status NOT IN ('completed', 'forbidden', 'failed')
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report audit envelope';
  END IF;

  SELECT query_fingerprint INTO STRICT registered_fingerprint
  FROM app_private.management_report_definitions
  WHERE report_id = requested_report_id
    AND report_version = requested_report_version;

  RETURN jsonb_build_object(
    'app_user_id', requested_app_user_id,
    'project_id', requested_project_id,
    'report_id', requested_report_id,
    'report_version', requested_report_version,
    'query_fingerprint', registered_fingerprint,
    'requested_at_utc', to_char(
      requested_at AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'result_status', requested_result_status
  );
EXCEPTION WHEN no_data_found THEN
  RAISE EXCEPTION USING
    ERRCODE = '22023',
    MESSAGE = 'invalid management report audit envelope';
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.reject_management_report_definition_mutation(),
  app_private.canonicalize_management_report_request_v1(jsonb),
  app_private.build_management_report_audit_envelope_v1(
    uuid,
    uuid,
    text,
    integer,
    timestamp with time zone,
    text
  )
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON TABLE app_private.management_report_definitions
IS 'Immutable registry for bounded management report shapes; unavailable to runtime until the authorization seam exists.';

COMMENT ON FUNCTION
  app_private.canonicalize_management_report_request_v1(jsonb)
IS 'Canonicalizes only registered fixed management report requests; performs no authorization or execution.';
