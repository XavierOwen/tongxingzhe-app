\set ON_ERROR_STOP on

DO $check$
DECLARE
  private_directory regprocedure := to_regprocedure(
    'app_private.list_authorized_management_report_snapshots_v1(uuid,uuid)'
  );
  runtime_bridge regprocedure := to_regprocedure(
    'app_data.list_authorized_management_report_snapshots_v1(text,text,uuid)'
  );
  validation_trigger regprocedure := to_regprocedure(
    'app_private.validate_management_report_snapshot_directory_access_v1()'
  );
BEGIN
  IF private_directory IS NULL
    OR runtime_bridge IS NULL
    OR validation_trigger IS NULL
    OR to_regclass(
      'app_private.management_report_snapshot_directory_access_events'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'management report snapshot directory is incomplete';
  END IF;

  IF (
    SELECT NOT function_row.prosecdef OR function_row.provolatile <> 'v'
    FROM pg_proc AS function_row
    WHERE function_row.oid = runtime_bridge
  ) OR (
    SELECT function_row.proconfig IS DISTINCT FROM
      ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc AS function_row
    WHERE function_row.oid = runtime_bridge
  ) THEN
    RAISE EXCEPTION 'snapshot directory runtime bridge is not protected';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      runtime_bridge,
      'EXECUTE'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name =
          'list_authorized_management_report_snapshots_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION 'snapshot directory runtime bridge ACL is incorrect';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      private_directory,
      'EXECUTE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_v2_attempts',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshot_directory_access_events',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION 'runtime received general snapshot directory access';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
      'app_private.management_report_snapshot_directory_access_events'::regclass
      AND trigger_row.tgname =
        'management_report_snapshot_directory_access_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
      'app_private.management_report_snapshot_directory_access_events'::regclass
      AND trigger_row.tgname =
        'management_report_snapshot_directory_access_validate'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'snapshot directory audit triggers are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0035_management_report_snapshot_directory'
  ) <> 1 THEN
    RAISE EXCEPTION 'snapshot directory migration was not recorded once';
  END IF;
END
$check$;
