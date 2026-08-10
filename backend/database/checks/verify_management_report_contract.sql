\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_private.management_report_definitions') IS NULL
    OR to_regprocedure(
      'app_private.canonicalize_management_report_request_v1(jsonb)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.build_management_report_audit_envelope_v1(uuid,uuid,text,integer,timestamp with time zone,text)'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'management report contract is missing';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_private.management_report_definitions',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.canonicalize_management_report_request_v1(jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.build_management_report_audit_envelope_v1(uuid,uuid,text,integer,timestamp with time zone,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass the future management report authorization seam';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_report_definitions
    WHERE report_id = 'contact_sessions_by_channel_two_periods'
      AND report_version = 1
      AND metric_id = 'contact_sessions'
      AND metric_version = 1
      AND dimension_key = 'channel'
      AND period_grain = 'week'
      AND comparison_period_count = 2
      AND period_boundary_id = 'iso_week_monday_v1'
      AND privacy_policy = 'management_contact_session_privacy_v1'
      AND required_capability = 'view_anonymous_analytics'
      AND query_fingerprint =
        'management-report:contact_sessions_by_channel_two_periods:v1'
  ) <> 1 THEN
    RAISE EXCEPTION 'registered management report definition is incorrect';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0024_management_report_contract'
  ) <> 1 THEN
    RAISE EXCEPTION 'management report contract migration was not recorded once';
  END IF;
END
$check$;
