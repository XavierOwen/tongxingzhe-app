\set ON_ERROR_STOP on

DO $check$
DECLARE
  bridge regprocedure := to_regprocedure(
    'app_data.release_management_report_snapshot_v1(text,text,uuid,uuid)'
  );
  private_release regprocedure := to_regprocedure(
    'app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)'
  );
BEGIN
  IF bridge IS NULL OR private_release IS NULL THEN
    RAISE EXCEPTION 'runtime trusted management report release is incomplete';
  END IF;

  IF (
    SELECT NOT function_row.prosecdef
      OR function_row.provolatile <> 'v'
      OR function_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime trusted release bridge is not protected';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      bridge,
      'EXECUTE'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name = 'release_management_report_snapshot_v1'
        AND grantee = 'PUBLIC'
    ) THEN
    RAISE EXCEPTION 'runtime trusted release bridge ACL is incorrect';
  END IF;

  -- SECURITY DEFINER 的 owner 才能触达 app_private；runtime 不能以任何
  -- 通用权限绕过 bridge 读取发布尝试、快照或底层业务事实。
  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      private_release,
      'EXECUTE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_v2_attempts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) THEN
    RAISE EXCEPTION 'runtime received general trusted report release access';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.routine_privileges
    WHERE specific_schema = 'app_data'
      AND routine_name = 'release_management_report_snapshot_v1'
      AND grantee = 'PUBLIC'
  ) THEN
    RAISE EXCEPTION 'runtime trusted release bridge is executable by PUBLIC';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0036_runtime_trusted_management_report_release'
  ) <> 1 THEN
    RAISE EXCEPTION 'runtime trusted release migration was not recorded once';
  END IF;
END
$check$;
