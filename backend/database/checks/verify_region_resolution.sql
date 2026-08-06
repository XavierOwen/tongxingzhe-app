-- 验证区域解析对象、权限和 migration 记录，不依赖业务 fixture。
DO $check$
BEGIN
  IF to_regclass('app_data.canonical_region_tree_releases') IS NULL
    OR to_regclass('app_data.canonical_region_boundaries') IS NULL
    OR to_regclass('app_data.canonical_region_boundaries_geometry') IS NULL
  THEN
    RAISE EXCEPTION 'canonical region resolution tables or indexes are missing';
  END IF;

  IF to_regprocedure(
    'app_data.resolve_canonical_region(double precision,double precision)'
  ) IS NULL THEN
    RAISE EXCEPTION 'canonical region resolver is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.resolve_canonical_region(double precision,double precision)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute the region resolver';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.canonical_region_boundaries',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.canonical_region_tree_releases',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime role can read canonical region boundaries';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0007_canonical_region_resolution'
  ) <> 1 THEN
    RAISE EXCEPTION 'region resolution migration was not recorded once';
  END IF;
END
$check$;
