-- 验证 6R 区域树发布生命周期、内容冻结和 runtime 最小权限。
DO $check$
DECLARE
  protected_table text;
BEGIN
  IF to_regclass('app_data.canonical_region_tree_releases') IS NULL
    OR to_regclass('app_data.canonical_region_tree_current_selections') IS NULL
    OR to_regclass('app_data.canonical_region_boundaries') IS NULL
  THEN
    RAISE EXCEPTION 'frozen canonical region release objects are missing';
  END IF;

  IF to_regprocedure(
    'app_private.publish_canonical_region_tree_v1(text,boolean)'
  ) IS NULL THEN
    RAISE EXCEPTION 'canonical region publish function is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = to_regprocedure(
      'app_private.publish_canonical_region_tree_v1(text,boolean)'
    )
      AND namespace_row.nspname = 'app_private'
      AND procedure_row.prosecdef
      AND owner_role.rolname = 'tongxingzhe_region_publisher'
  ) THEN
    RAISE EXCEPTION 'canonical region publisher owner is not restore-safe';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_attribute
    WHERE attrelid = 'app_data.canonical_region_tree_releases'::regclass
      AND attname IN ('lifecycle_state', 'content_fingerprint')
      AND NOT attisdropped
  ) <> 2 THEN
    RAISE EXCEPTION 'release lifecycle or content fingerprint columns are missing';
  END IF;

  FOREACH protected_table IN ARRAY ARRAY[
    'canonical_region_versions',
    'canonical_region_boundaries',
    'canonical_region_tree_releases',
    'canonical_region_tree_current_selections'
  ]
  LOOP
    IF has_table_privilege(
      'tongxingzhe_runtime',
      format('app_data.%I', protected_table),
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) THEN
      RAISE EXCEPTION 'runtime role can access frozen region object: %',
        protected_table;
    END IF;
  END LOOP;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.publish_canonical_region_tree_v1(text,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role can publish canonical region trees';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.canonical_region_tree_content_fingerprint_v1(text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role can compute private region fingerprints';
  END IF;

  IF has_sequence_privilege(
    'tongxingzhe_runtime',
    'app_data.canonical_region_tree_current_selections_selection_sequence_seq',
    'USAGE,SELECT,UPDATE'
  ) THEN
    RAISE EXCEPTION 'runtime role can access region selection sequence';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS publisher_role
      ON publisher_role.oid = membership.roleid
    WHERE publisher_role.rolname = 'tongxingzhe_region_publisher'
  ) THEN
    RAISE EXCEPTION 'region publisher role must not have members';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_region_publisher'
      AND NOT rolcanlogin
      AND NOT rolsuper
      AND NOT rolcreatedb
      AND NOT rolcreaterole
      AND NOT rolinherit
      AND NOT rolreplication
      AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION 'region publisher role is missing or over-privileged';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0038_freeze_published_canonical_region_trees'
  ) <> 1 THEN
    RAISE EXCEPTION 'frozen canonical region migration was not recorded once';
  END IF;
END
$check$;
