\set ON_ERROR_STOP on

DO $check$
DECLARE
  protected_function text;
BEGIN
  IF to_regclass(
      'app_private.management_report_release_v2_attempts'
    ) IS NULL
    OR to_regprocedure(
      'app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'trusted management report release contract is incomplete';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_v2_attempts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION 'runtime can access trusted report release evidence';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_private'
      AND table_name = 'management_report_release_v2_attempts'
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime')
  ) THEN
    RAISE EXCEPTION 'trusted report release table privilege matrix is open';
  END IF;

  FOREACH protected_function IN ARRAY ARRAY[
    'app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)',
    'app_private.validate_management_report_release_v2_attempt_insert()'
  ] LOOP
    IF to_regprocedure(protected_function) IS NULL
      OR has_function_privilege(
        'tongxingzhe_runtime',
        protected_function,
        'EXECUTE'
      )
    THEN
      RAISE EXCEPTION 'trusted report release function is open or missing: %',
        protected_function;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.routine_privileges
    WHERE specific_schema = 'app_private'
      AND routine_name IN (
        'release_management_report_snapshot_v2',
        'validate_management_report_release_v2_attempt_insert'
      )
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime')
  ) THEN
    RAISE EXCEPTION 'trusted report release function privilege matrix is open';
  END IF;

  IF (
    SELECT function_row.provolatile
    FROM pg_proc AS function_row
    WHERE function_row.oid =
      'app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)'::regprocedure
  ) <> 'v' THEN
    RAISE EXCEPTION 'trusted report release must hold transaction locks';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.management_report_release_v2_attempts'::regclass
      AND tgname = 'management_report_release_v2_attempts_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.management_report_release_v2_attempts'::regclass
      AND tgname =
        'management_report_release_v2_attempts_validate_insert'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'trusted report release history is not protected';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname =
        'management_report_release_v2_attempts_lineage_idx'
  ) THEN
    RAISE EXCEPTION 'trusted report release lineage index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_report_release_v2_attempts'::regclass
      AND confrelid =
        'app_private.project_reporting_time_zone_versions'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_report_release_v2_attempts'::regclass
      AND confrelid =
        'app_data.management_report_capability_grants'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_report_release_v2_attempts'::regclass
      AND confrelid =
        'app_private.management_report_release_attempts'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'trusted report release lineage foreign keys are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0031_trusted_management_report_release'
  ) <> 1 THEN
    RAISE EXCEPTION 'trusted report release migration was not recorded once';
  END IF;
END
$check$;
