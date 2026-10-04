\set ON_ERROR_STOP on

DO $check$
DECLARE
  recovery_reader_function text :=
    'app_private.resolve_management_report_recovery_read_authorization_v1(uuid,uuid,text,timestamp with time zone)';
  strict_resolver_source text;
  recovery_reader_callers integer;
BEGIN
  IF to_regprocedure(recovery_reader_function) IS NULL THEN
    RAISE EXCEPTION '0103 narrow report recovery resolver is missing';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege('tongxingzhe_runtime', recovery_reader_function, 'EXECUTE')
    OR EXISTS (
      SELECT 1 FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_private'
        AND routine_name = 'resolve_management_report_recovery_read_authorization_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION '0103 recovery authorization helper is runtime-accessible';
  END IF;

  SELECT count(*) INTO recovery_reader_callers
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.pronamespace = 'app_private'::regnamespace
    AND function_row.prosrc LIKE
      '%resolve_management_report_recovery_read_authorization_v1%';
  IF recovery_reader_callers <> 20 THEN
    RAISE EXCEPTION '0103 recovery resolver must be confined to 10 readers and 10 validators; found % callers',
      recovery_reader_callers;
  END IF;

  SELECT function_row.prosrc INTO STRICT strict_resolver_source
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.resolve_management_report_authorization_v1(uuid,uuid,text)'::regprocedure;
  IF strict_resolver_source NOT LIKE '%workspace_row.deleted_at IS NULL%'
    OR strict_resolver_source LIKE '%organization_deletion_current%'
  THEN
    RAISE EXCEPTION '0103 widened the shared strict management report resolver';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      'app_data.read_authorized_management_report_snapshot_v1(text,text,uuid,uuid)',
      'EXECUTE'
    )
    OR NOT has_function_privilege(
      'tongxingzhe_runtime',
      'app_data.list_authorized_management_report_snapshots_v1(text,text,uuid)',
      'EXECUTE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshot_access_events',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION '0103 changed the existing narrow runtime report bridge';
  END IF;

  IF (
    SELECT count(*) FROM app_migrations.schema_migrations
    WHERE version = '0103_organization_report_recovery_read'
  ) <> 1 THEN
    RAISE EXCEPTION '0103 report recovery read migration was not recorded once';
  END IF;
END
$check$;
