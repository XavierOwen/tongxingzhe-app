\set ON_ERROR_STOP on

DO $check$
DECLARE
  bridge regprocedure := to_regprocedure(
    'app_data.export_authorized_management_report_snapshot_v1(text,text,uuid,uuid)'
  );
  private_export regprocedure := to_regprocedure(
    'app_private.export_authorized_management_report_snapshot_v1(uuid,uuid,uuid)'
  );
  audit_table regclass := to_regclass(
    'app_private.management_report_snapshot_export_events'
  );
BEGIN
  IF audit_table IS NULL OR private_export IS NULL OR bridge IS NULL THEN
    RAISE EXCEPTION 'management report snapshot export schema is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint AS constraint_row
    WHERE constraint_row.conrelid =
      'app_data.management_report_capability_grants'::regclass
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%export_management_reports%'
  ) THEN
    RAISE EXCEPTION 'export management report capability is not allowlisted';
  END IF;

  IF (
    SELECT NOT function_row.prosecdef
      OR function_row.provolatile <> 'v'
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime management report snapshot export bridge is not protected';
  END IF;

  IF (
    SELECT function_row.proconfig IS DISTINCT FROM
      ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime management report snapshot export bridge search path is open';
  END IF;

  IF NOT has_function_privilege('tongxingzhe_runtime', bridge, 'EXECUTE')
    OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name =
          'export_authorized_management_report_snapshot_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION 'runtime management report snapshot export bridge ACL is incorrect';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      private_export,
      'EXECUTE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      audit_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION 'runtime received general management report export access';
  END IF;

  IF pg_get_functiondef(private_export) LIKE
      '%read_authorized_management_report_snapshot_v1%'
    OR pg_get_functiondef(private_export) LIKE
      '%management_report_snapshot_access_events%'
  THEN
    RAISE EXCEPTION 'snapshot export reuses the ordinary read audit boundary';
  END IF;

  IF pg_get_functiondef(private_export) NOT LIKE
      '%contact_sessions_by_channel_two_periods%'
  THEN
    RAISE EXCEPTION 'snapshot export report allowlist is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_private'
      AND table_name = 'management_report_snapshot_export_events'
      AND column_name IN (
        'protected_report',
        'export_document',
        'cells',
        'query_fingerprint',
        'contributor_count',
        'location',
        'pii'
      )
  ) THEN
    RAISE EXCEPTION 'export audit stores report values or source details';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = audit_table
      AND tgname = 'management_report_snapshot_export_events_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = audit_table
      AND tgname = 'management_report_snapshot_export_events_validate_insert'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'management report export audit triggers are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0052_management_report_snapshot_export'
  ) <> 1 THEN
    RAISE EXCEPTION 'management report snapshot export migration was not recorded once';
  END IF;
END
$check$;
