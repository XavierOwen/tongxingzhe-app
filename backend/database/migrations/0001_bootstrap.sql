-- 0001_bootstrap.sql
--
-- 建立 Backend 专用 schema 与最小权限 runtime role。
-- App 数据不放进 Supabase 默认暴露的 public schema，Flutter 也不会持有这个
-- role 的数据库凭据；只有自有 HTTPS Backend 的运行身份可以继承它。

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_runtime'
  ) THEN
    CREATE ROLE tongxingzhe_runtime
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$migration$;

-- 即使 role 已存在，也重新收紧这些可变属性，避免环境漂移。
ALTER ROLE tongxingzhe_runtime
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

-- public 是 Supabase Data API 的默认暴露面；正式业务表只进入 app_data。
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS app_data;
REVOKE ALL ON SCHEMA app_data FROM PUBLIC;
GRANT USAGE ON SCHEMA app_data TO tongxingzhe_runtime;

-- app_data 中的新表仍需 Backend 读写，但 runtime 不可建表或改 schema。
-- 这些 default privilege 只影响由当前 migration owner 以后创建的对象。
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO tongxingzhe_runtime;

ALTER DEFAULT PRIVILEGES IN SCHEMA app_data
  GRANT USAGE, SELECT ON SEQUENCES TO tongxingzhe_runtime;

ALTER ROLE tongxingzhe_runtime SET search_path = app_data, pg_catalog;
