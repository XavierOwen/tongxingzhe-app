\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_data.personal_action_plans') IS NULL
    OR to_regclass('app_data.personal_action_plan_versions') IS NULL
  THEN
    RAISE EXCEPTION 'personal action plan tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.read_personal_action_plan(uuid,uuid,uuid,timestamptz)'
  ) IS NULL OR to_regprocedure(
    'app_data.save_personal_action_plan(uuid,uuid,uuid,integer,integer,text,integer,text,timestamptz)'
  ) IS NULL THEN
    RAISE EXCEPTION 'personal action plan functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_action_plan(uuid,uuid,uuid,timestamptz)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.save_personal_action_plan(uuid,uuid,uuid,integer,integer,text,integer,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.personal_action_plan_document(uuid,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime personal action plan function boundary is unsafe';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.personal_action_plans',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.personal_action_plan_versions',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass private plan functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'app_data.personal_action_plan_versions'::regclass
      AND tgname = 'personal_action_plan_versions_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'personal action plan version history is mutable';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0021_personal_action_plans'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal action plan migration was not recorded once';
  END IF;
END
$check$;
