\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_data.personal_action_reminders') IS NULL
    OR to_regclass('app_data.personal_action_reminder_versions') IS NULL
  THEN
    RAISE EXCEPTION 'personal action reminder tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.read_personal_action_reminder(uuid,uuid,uuid)'
  ) IS NULL OR to_regprocedure(
    'app_data.save_personal_action_reminder(uuid,uuid,uuid,integer,integer,text,timestamptz)'
  ) IS NULL THEN
    RAISE EXCEPTION 'personal action reminder functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_action_reminder(uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.save_personal_action_reminder(uuid,uuid,uuid,integer,integer,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.personal_action_reminder_document(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime personal reminder function boundary is unsafe';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.personal_action_reminders',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.personal_action_reminder_versions',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass private reminder functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'app_data.personal_action_reminder_versions'::regclass
      AND tgname = 'personal_action_reminder_versions_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'personal action reminder history is mutable';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0022_personal_action_reminders'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal action reminder migration was not recorded once';
  END IF;
END
$check$;
