\set ON_ERROR_STOP on

DO $check$
DECLARE
  protected_function text;
BEGIN
  IF to_regclass(
      'app_private.management_report_snapshot_access_events'
    ) IS NULL
    OR to_regprocedure(
      'app_private.read_authorized_management_report_snapshot_v1(uuid,uuid,uuid)'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'authorized management report snapshot read contract is incomplete';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshot_access_events',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION 'runtime can access management report snapshot reads';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_private'
      AND table_name = 'management_report_snapshot_access_events'
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime')
  ) THEN
    RAISE EXCEPTION 'management report access table privilege matrix is open';
  END IF;

  FOREACH protected_function IN ARRAY ARRAY[
    'app_private.read_authorized_management_report_snapshot_v1(uuid,uuid,uuid)',
    'app_private.validate_management_report_snapshot_access_insert_v1()'
  ] LOOP
    IF to_regprocedure(protected_function) IS NULL
      OR has_function_privilege(
        'tongxingzhe_runtime',
        protected_function,
        'EXECUTE'
      )
    THEN
      RAISE EXCEPTION 'management report access function is open or missing: %',
        protected_function;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.routine_privileges
    WHERE specific_schema = 'app_private'
      AND routine_name IN (
        'read_authorized_management_report_snapshot_v1',
        'validate_management_report_snapshot_access_insert_v1'
      )
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime')
  ) THEN
    RAISE EXCEPTION 'management report access function privilege matrix is open';
  END IF;

  IF (
    SELECT function_row.provolatile
    FROM pg_proc AS function_row
    WHERE function_row.oid =
      'app_private.read_authorized_management_report_snapshot_v1(uuid,uuid,uuid)'::regprocedure
  ) <> 'v' THEN
    RAISE EXCEPTION 'authorized snapshot read must append access history';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.management_report_snapshot_access_events'::regclass
      AND tgname = 'management_report_snapshot_access_events_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.management_report_snapshot_access_events'::regclass
      AND tgname =
        'management_report_snapshot_access_events_validate_insert'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'management report access history is not protected';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname =
        'management_report_snapshot_access_events_project_idx'
  ) THEN
    RAISE EXCEPTION 'management report access history index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_report_snapshot_access_events'::regclass
      AND confrelid =
        'app_data.management_report_capability_grants'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_report_snapshot_access_events'::regclass
      AND confrelid =
        'app_private.management_report_snapshots'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'management report access lineage foreign keys are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0032_authorized_management_report_snapshot_read'
  ) <> 1 THEN
    RAISE EXCEPTION 'authorized snapshot read migration was not recorded once';
  END IF;
END
$check$;
