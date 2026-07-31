-- 任何条件不成立都抛出异常，让 CI 明确失败。
DO $check$
DECLARE
  runtime_role pg_catalog.pg_roles%ROWTYPE;
BEGIN
  SELECT *
  INTO STRICT runtime_role
  FROM pg_catalog.pg_roles
  WHERE rolname = 'tongxingzhe_runtime';

  IF runtime_role.rolcanlogin
    OR runtime_role.rolsuper
    OR runtime_role.rolcreatedb
    OR runtime_role.rolcreaterole
    OR runtime_role.rolreplication
    OR runtime_role.rolbypassrls
  THEN
    RAISE EXCEPTION 'tongxingzhe_runtime has elevated role attributes';
  END IF;

  IF NOT has_schema_privilege('tongxingzhe_runtime', 'app_data', 'USAGE') THEN
    RAISE EXCEPTION 'runtime role cannot use app_data';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_data', 'CREATE') THEN
    RAISE EXCEPTION 'runtime role can create objects in app_data';
  END IF;

  IF has_schema_privilege(
    'tongxingzhe_runtime',
    'app_migrations',
    'USAGE'
  ) THEN
    RAISE EXCEPTION 'runtime role can inspect migration history';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'public', 'CREATE') THEN
    RAISE EXCEPTION 'runtime role can create objects in public';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0001_bootstrap'
  ) <> 1 THEN
    RAISE EXCEPTION 'bootstrap migration was not recorded exactly once';
  END IF;
END
$check$;
