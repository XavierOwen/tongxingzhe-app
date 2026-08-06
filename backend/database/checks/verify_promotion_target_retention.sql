\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass(
    'app_data.promotion_target_retention_policies'
  ) IS NULL OR to_regclass(
    'app_data.promotion_target_retention_events'
  ) IS NULL THEN
    RAISE EXCEPTION 'promotion target retention tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)'
  ) IS NULL OR to_regprocedure(
    'app_data.list_promotion_target_retention_tasks(uuid,uuid,uuid)'
  ) IS NULL OR to_regprocedure(
    'app_data.configure_promotion_target_retention_policy(uuid,uuid,uuid,integer)'
  ) IS NULL OR to_regprocedure(
    'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)'
  ) IS NULL THEN
    RAISE EXCEPTION 'promotion target retention functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_promotion_target_retention_action(uuid,uuid,uuid,uuid,text,text,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.list_promotion_target_retention_tasks(uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.configure_promotion_target_retention_policy(uuid,uuid,uuid,integer)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime promotion target retention boundary is unsafe';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_retention_policies',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_retention_events',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass promotion target retention functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_retention_events'::regclass
      AND tgname = 'promotion_target_retention_events_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name = 'promotion_targets'
      AND column_name = 'anonymized_at'
  ) THEN
    RAISE EXCEPTION 'retention audit or anonymization shape is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name = 'promotion_target_retention_events'
      AND column_name IN ('display_name', 'phone', 'email', 'follow_up_note')
  ) THEN
    RAISE EXCEPTION 'retention audit contains target PII';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0020_promotion_target_retention'
  ) <> 1 THEN
    RAISE EXCEPTION 'promotion target retention migration was not recorded once';
  END IF;
END
$check$;
