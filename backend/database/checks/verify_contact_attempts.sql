-- 验证接触尝试对象、权限和 migration 记录，不依赖业务 fixture。
DO $check$
BEGIN
  IF to_regclass('app_data.contact_attempts') IS NULL
    OR to_regclass('app_data.contact_attempts_personal_period') IS NULL
  THEN
    RAISE EXCEPTION 'contact attempt table or index is missing';
  END IF;

  IF to_regprocedure(
    'app_data.apply_contact_attempt_submit(uuid,text,integer,text,text,text,integer,jsonb)'
  ) IS NULL THEN
    RAISE EXCEPTION 'contact attempt function is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_attempt_submit(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_submit(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute contact attempt contracts';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_submit_without_attempt(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contact_attempts',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime role can bypass the contact attempt contract';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0008_contact_attempts'
  ) <> 1 THEN
    RAISE EXCEPTION 'contact attempt migration was not recorded once';
  END IF;
END
$check$;
