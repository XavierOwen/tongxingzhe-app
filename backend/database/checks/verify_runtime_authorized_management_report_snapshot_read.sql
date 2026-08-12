\set ON_ERROR_STOP on

DO $check$
DECLARE
  bridge regprocedure := to_regprocedure(
    'app_data.read_authorized_management_report_snapshot_v1(text,text,uuid,uuid)'
  );
BEGIN
  IF bridge IS NULL THEN
    RAISE EXCEPTION 'runtime management report snapshot bridge is incomplete';
  END IF;

  IF (
    SELECT NOT function_row.prosecdef OR function_row.provolatile <> 'v'
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime management report snapshot bridge is not protected';
  END IF;

  IF (
    SELECT function_row.proconfig IS DISTINCT FROM
      ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime management report snapshot bridge search path is open';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      bridge,
      'EXECUTE'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name =
          'read_authorized_management_report_snapshot_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION 'runtime management report snapshot bridge ACL is incorrect';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.read_authorized_management_report_snapshot_v1(uuid,uuid,uuid)',
      'EXECUTE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshot_access_events',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION 'runtime received general management report access';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0033_runtime_authorized_management_report_snapshot_read'
  ) <> 1 THEN
    RAISE EXCEPTION 'runtime management report snapshot bridge was not recorded once';
  END IF;
END
$check$;
