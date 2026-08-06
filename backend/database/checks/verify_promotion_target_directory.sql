\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_data.promotion_targets') IS NULL
    OR to_regclass('app_data.promotion_target_assignments') IS NULL
    OR to_regclass(
      'app_data.promotion_target_creation_requests'
    ) IS NULL
    OR to_regclass('app_data.promotion_target_access_events') IS NULL
  THEN
    RAISE EXCEPTION 'promotion target tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.list_assigned_promotion_targets(uuid,uuid,uuid)'
  ) IS NULL OR to_regprocedure(
    'app_data.create_promotion_target(uuid,uuid,uuid,text,text,text,text,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'promotion target functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.list_assigned_promotion_targets(uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.create_promotion_target(uuid,uuid,uuid,text,text,text,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime cannot use promotion target functions';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_targets',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_assignments',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_creation_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_access_events',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass promotion target functions';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name IN (
        'promotion_target_creation_requests',
        'promotion_target_access_events'
      )
      AND column_name IN ('display_name', 'phone', 'email')
  ) THEN
    RAISE EXCEPTION 'audit or idempotency tables duplicate target PII';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_creation_requests'::regclass
      AND tgname = 'promotion_target_creation_requests_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'app_data.promotion_target_access_events'::regclass
      AND tgname = 'promotion_target_access_events_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'promotion target audit immutability is missing';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0016_promotion_target_directory'
  ) <> 1 THEN
    RAISE EXCEPTION 'promotion target migration was not recorded once';
  END IF;
END
$check$;
