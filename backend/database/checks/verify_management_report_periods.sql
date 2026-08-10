\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regprocedure(
    'app_private.management_report_time_zone_valid_v1(text)'
  ) IS NULL
    OR to_regprocedure(
      'app_private.resolve_management_report_periods_v1(text,timestamp with time zone)'
    ) IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute
      WHERE attrelid =
        'app_private.management_report_definitions'::regclass
        AND attname = 'period_boundary_id'
        AND attnum > 0
        AND NOT attisdropped
        AND attnotnull
    )
  THEN
    RAISE EXCEPTION 'management report period contract is missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.management_report_time_zone_valid_v1(text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.resolve_management_report_periods_v1(text,timestamp with time zone)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass management report period authorization';
  END IF;

  IF (
    SELECT period_boundary_id
    FROM app_private.management_report_definitions
    WHERE report_id = 'contact_sessions_by_channel_two_periods'
      AND report_version = 1
  ) IS DISTINCT FROM 'iso_week_monday_v1' THEN
    RAISE EXCEPTION 'fixed report has an invalid period boundary';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0025_management_report_periods'
  ) <> 1 THEN
    RAISE EXCEPTION 'management report periods migration was not recorded once';
  END IF;
END
$check$;
