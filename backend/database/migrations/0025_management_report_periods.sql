-- 0025_management_report_periods.sql
--
-- 固定管理报告使用项目可信 IANA 时区，并取数据截止点之前最近两个完整
-- ISO 周。每个当地周一午夜分别转换为 UTC，因此夏令时周不是固定 168 小时。
-- 当前函数继续留在 app_private，不开放管理查询或时区配置写入。

ALTER TABLE app_private.management_report_definitions
ADD COLUMN period_boundary_id text NOT NULL
  DEFAULT 'iso_week_monday_v1'
  CHECK (period_boundary_id ~ '^[a-z][a-z0-9_]{0,119}$');

ALTER TABLE app_private.management_report_definitions
ALTER COLUMN period_boundary_id DROP DEFAULT;

CREATE FUNCTION app_private.management_report_time_zone_valid_v1(
  requested_time_zone text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $function$
  SELECT requested_time_zone = 'UTC'
    OR (
      position('/' IN requested_time_zone) > 0
      AND requested_time_zone NOT LIKE 'posix/%'
      AND requested_time_zone NOT LIKE 'right/%'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS time_zone_row
        WHERE time_zone_row.name = requested_time_zone
      )
    );
$function$;

CREATE FUNCTION app_private.resolve_management_report_periods_v1(
  requested_reporting_time_zone text,
  requested_data_cutoff_utc timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  current_until_local date;
  current_start_local date;
  previous_start_local date;
  previous_start_utc timestamp with time zone;
  current_start_utc timestamp with time zone;
  current_until_utc timestamp with time zone;
BEGIN
  IF requested_data_cutoff_utc IS NULL
    OR NOT isfinite(requested_data_cutoff_utc)
    OR app_private.management_report_time_zone_valid_v1(
      requested_reporting_time_zone
    ) IS NOT TRUE
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report period context';
  END IF;

  current_until_local =
    (requested_data_cutoff_utc AT TIME ZONE
      requested_reporting_time_zone)::date
    - (
      extract(
        isodow FROM requested_data_cutoff_utc AT TIME ZONE
          requested_reporting_time_zone
      )::integer
      - 1
    );
  current_start_local = current_until_local - 7;
  previous_start_local = current_until_local - 14;

  previous_start_utc = previous_start_local::timestamp
    AT TIME ZONE requested_reporting_time_zone;
  current_start_utc = current_start_local::timestamp
    AT TIME ZONE requested_reporting_time_zone;
  current_until_utc = current_until_local::timestamp
    AT TIME ZONE requested_reporting_time_zone;

  IF previous_start_utc >= current_start_utc
    OR current_start_utc >= current_until_utc
    OR current_until_utc > requested_data_cutoff_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report period context';
  END IF;

  RETURN jsonb_build_object(
    'period_boundary_id', 'iso_week_monday_v1',
    'reporting_time_zone', requested_reporting_time_zone,
    'data_cutoff_utc', to_char(
      requested_data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'previous_period', jsonb_build_object(
      'start_utc', to_char(
        previous_start_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'until_utc', to_char(
        current_start_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    ),
    'current_period', jsonb_build_object(
      'start_utc', to_char(
        current_start_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'until_utc', to_char(
        current_until_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    )
  );
END
$function$;

CREATE OR REPLACE FUNCTION
  app_private.canonicalize_management_report_request_v1(
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
    'period_boundary_id', definition.period_boundary_id,
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

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.management_report_time_zone_valid_v1(text),
  app_private.resolve_management_report_periods_v1(
    text,
    timestamp with time zone
  ),
  app_private.canonicalize_management_report_request_v1(jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_private.resolve_management_report_periods_v1(
    text,
    timestamp with time zone
  )
IS 'Resolves two complete ISO weeks from trusted report time-zone and cutoff context; performs no authorization or aggregation.';
