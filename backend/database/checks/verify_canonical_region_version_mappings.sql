\set ON_ERROR_STOP on

-- Structural and privilege contract for Slice 6AK. This check is deliberately
-- fixture-free: the following 0053 fixture supplies all behavioural examples.
DO $check$
DECLARE
  mapping_table regclass := to_regclass(
    'app_data.canonical_region_version_mappings'
  );
  register_function regprocedure := to_regprocedure(
    'app_private.register_canonical_region_version_mapping_v1(uuid,text,text,text,text,text,text,text)'
  );
  resolver_function regprocedure := to_regprocedure(
    'app_private.resolve_canonical_region_version_mapping_v1(text,text,text,text,text)'
  );
  document_function regprocedure := to_regprocedure(
    'app_private.canonical_region_version_mapping_document_v1(uuid)'
  );
  guard_function regprocedure := to_regprocedure(
    'app_data.guard_canonical_region_version_mapping_write_v1()'
  );
  writer_oid oid;
  maintenance_oid oid;
  function_row record;
  constraint_name text;
  expected_column_count integer;
BEGIN
  IF mapping_table IS NULL
    OR register_function IS NULL
    OR resolver_function IS NULL
    OR document_function IS NULL
    OR guard_function IS NULL
  THEN
    RAISE EXCEPTION 'canonical region version mapping objects are incomplete';
  END IF;

  SELECT oid
  INTO writer_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = 'tongxingzhe_region_mapping_writer';
  IF writer_oid IS NULL THEN
    RAISE EXCEPTION 'canonical region mapping writer role is missing';
  END IF;
  SELECT oid
  INTO maintenance_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = current_user;

  -- The table is intentionally a small evidence record, with no free text,
  -- coordinates, contact data or other report/query surface.
  SELECT count(*)
  INTO expected_column_count
  FROM pg_catalog.pg_attribute
  WHERE attrelid = mapping_table
    AND attnum > 0
    AND NOT attisdropped;
  IF expected_column_count <> 11 THEN
    RAISE EXCEPTION 'mapping table has unexpected columns: %',
      expected_column_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = mapping_table
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname NOT IN (
        'mapping_id',
        'request_id',
        'source_tree_version',
        'source_region_id',
        'source_content_fingerprint',
        'target_tree_version',
        'target_region_id',
        'target_content_fingerprint',
        'evidence_contract',
        'evidence_digest',
        'recorded_at_utc'
      )
  ) THEN
    RAISE EXCEPTION 'mapping table contains an uncontracted column';
  END IF;

  -- pg_proc is queried separately so the check remains readable and catches
  -- owner, SECURITY DEFINER and fixed search_path drift for every private API.
  FOR function_row IN
    SELECT
      procedure_row.oid,
      procedure_row.prosecdef,
      procedure_row.proconfig,
      owner_role.rolname AS owner_name
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid IN (
      register_function,
      resolver_function,
      document_function
    )
  LOOP
    IF NOT function_row.prosecdef
      OR function_row.owner_name <> 'tongxingzhe_region_mapping_writer'
    THEN
      RAISE EXCEPTION 'mapping private function is not writer-owned SECURITY DEFINER: %',
        function_row.oid;
    END IF;
    IF function_row.proconfig IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM unnest(function_row.proconfig) AS setting
        WHERE setting LIKE 'search_path=pg_catalog%'
          AND setting NOT LIKE '%public%'
      )
    THEN
      RAISE EXCEPTION 'mapping private function search_path is open: %',
        function_row.oid;
    END IF;
  END LOOP;

  IF (
    SELECT proconfig
    FROM pg_catalog.pg_proc
    WHERE oid = register_function
  ) IS DISTINCT FROM
    ARRAY['search_path=pg_catalog, app_data, app_private']::text[]
  OR (
    SELECT proconfig
    FROM pg_catalog.pg_proc
    WHERE oid = resolver_function
  ) IS DISTINCT FROM
    ARRAY['search_path=pg_catalog, app_data, app_private']::text[]
  OR (
    SELECT proconfig
    FROM pg_catalog.pg_proc
    WHERE oid = document_function
  ) IS DISTINCT FROM
    ARRAY['search_path=pg_catalog, app_data']::text[]
  THEN
    RAISE EXCEPTION 'mapping private function search_path is not fixed';
  END IF;

  IF pg_get_functiondef(register_function) NOT LIKE
      '%canonical-region-version-mapping-evidence:v1%'
    OR pg_get_functiondef(register_function) NOT LIKE
      '%lifecycle_state <> ''published''%'
    OR pg_get_functiondef(register_function) NOT LIKE
      '%content_fingerprint%'
    OR pg_get_functiondef(register_function) NOT LIKE
      '%mapping is not one to one%'
  THEN
    RAISE EXCEPTION 'mapping writer does not revalidate evidence or one-to-one constraints';
  END IF;

  IF pg_get_functiondef(resolver_function) NOT LIKE '%mapping_status%'
    OR pg_get_functiondef(resolver_function) NOT LIKE '%mapped%'
    OR pg_get_functiondef(resolver_function) NOT LIKE '%unmapped%'
    OR pg_get_functiondef(resolver_function) NOT LIKE '%content_fingerprint%'
    OR pg_get_functiondef(resolver_function) ILIKE '%canonical_name%'
    OR pg_get_functiondef(resolver_function) ILIKE '%geometry%'
  THEN
    RAISE EXCEPTION 'mapping resolver is not explicit and fail-closed';
  END IF;

  IF pg_get_functiondef(guard_function) NOT LIKE
      '%current_user = ''tongxingzhe_region_mapping_writer''%'
    OR pg_get_functiondef(guard_function) NOT LIKE '%append only%'
  THEN
    RAISE EXCEPTION 'mapping append-only trigger guard is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid = mapping_table
      AND tgname = 'canonical_region_version_mapping_write_guard'
      AND NOT tgisinternal
      AND (tgtype & 1) = 1 -- ROW
      AND (tgtype & 2) = 2 -- BEFORE
      AND (tgtype & 28) = 28 -- INSERT, DELETE and UPDATE
  ) THEN
    RAISE EXCEPTION 'mapping append-only trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid = mapping_table
      AND tgname = 'canonical_region_version_mapping_truncate_guard'
      AND NOT tgisinternal
      AND (tgtype & 1) = 0 -- STATEMENT
      AND (tgtype & 2) = 2 -- BEFORE
      AND (tgtype & 32) = 32 -- TRUNCATE
  ) THEN
    RAISE EXCEPTION 'mapping truncate guard is missing';
  END IF;

  -- Named constraints are part of the one-to-one and evidence contract.
  FOREACH constraint_name IN ARRAY ARRAY[
    'canonical_region_version_mapping_distinct_versions'::text,
    'canonical_region_version_mapping_source_release_fk'::text,
    'canonical_region_version_mapping_target_release_fk'::text,
    'canonical_region_version_mapping_source_node_fk'::text,
    'canonical_region_version_mapping_target_node_fk'::text,
    'canonical_region_version_mapping_no_split'::text,
    'canonical_region_version_mapping_no_merge'::text
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = mapping_table
        AND constraint_row.conname = constraint_name
    ) THEN
      RAISE EXCEPTION 'mapping constraint is missing: %', constraint_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = mapping_table
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%source_content_fingerprint ~ ''^[0-9a-f]{64}$''%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = mapping_table
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%target_content_fingerprint ~ ''^[0-9a-f]{64}$''%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = mapping_table
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%evidence_digest ~ ''^[0-9a-f]{64}$''%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = mapping_table
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%evidence_contract = ''canonical-region-version-mapping-evidence:v1''%'
  ) THEN
    RAISE EXCEPTION 'mapping fingerprint or evidence constraints are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'app_data'
      AND column_row.table_name = 'canonical_region_version_mappings'
      AND column_row.column_name = 'recorded_at_utc'
      AND column_row.is_nullable = 'NO'
      AND column_row.column_default ILIKE '%clock_timestamp%'
  ) THEN
    RAISE EXCEPTION 'mapping recorded_at_utc is not a database timestamp';
  END IF;

  -- The table owner is the no-login writer role. The publisher and migration
  -- maintainer may execute the two private operations; runtime and PUBLIC have
  -- no general function or table access.
  IF (
    SELECT owner_role.rolname
    FROM pg_catalog.pg_class AS relation_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = relation_row.relowner
    WHERE relation_row.oid = mapping_table
  ) <> 'tongxingzhe_region_mapping_writer'
  THEN
    RAISE EXCEPTION 'mapping table owner is not the no-login writer role';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    mapping_table,
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR has_table_privilege(
    'tongxingzhe_region_publisher',
    mapping_table,
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) THEN
    RAISE EXCEPTION 'runtime or publisher can access the mapping table directly';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM aclexplode(
      COALESCE(
        (
          SELECT relation_row.relacl
          FROM pg_catalog.pg_class AS relation_row
          WHERE relation_row.oid = mapping_table
        ),
        acldefault('r', writer_oid)
      )
    ) AS exploded
    WHERE exploded.grantee = 0
      OR exploded.grantee = (
        SELECT oid FROM pg_catalog.pg_roles
        WHERE rolname = 'tongxingzhe_runtime'
      )
      OR exploded.grantee = (
        SELECT oid FROM pg_catalog.pg_roles
        WHERE rolname = 'tongxingzhe_region_publisher'
      )
  ) THEN
    RAISE EXCEPTION 'mapping table ACL exposes PUBLIC, runtime or publisher';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime', register_function, 'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime', resolver_function, 'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime', document_function, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'mapping private functions have an over-broad EXECUTE grant';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_region_publisher', register_function, 'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_region_publisher', resolver_function, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'publisher cannot execute both private mapping functions';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM aclexplode(
      COALESCE(
        (
          SELECT procedure_row.proacl
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = document_function
        ),
        acldefault('f', writer_oid)
      )
    ) AS exploded
    WHERE exploded.grantee = 0
      OR exploded.grantee = (
        SELECT oid FROM pg_catalog.pg_roles
        WHERE rolname = 'tongxingzhe_runtime'
      )
  ) THEN
    RAISE EXCEPTION 'mapping document helper is exposed to PUBLIC or runtime';
  END IF;

  FOR function_row IN
    SELECT exploded.grantee, exploded.privilege_type
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL aclexplode(
      COALESCE(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) AS exploded
    WHERE procedure_row.oid IN (register_function, resolver_function)
      AND exploded.privilege_type = 'EXECUTE'
  LOOP
    IF function_row.grantee = 0
      OR function_row.grantee <> writer_oid
        AND function_row.grantee <> maintenance_oid
        AND function_row.grantee <> (
          SELECT oid FROM pg_catalog.pg_roles
          WHERE rolname = 'tongxingzhe_region_publisher'
        )
    THEN
      RAISE EXCEPTION 'unexpected mapping function EXECUTE grant: %',
        function_row.grantee;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = 'tongxingzhe_region_mapping_writer'
      AND NOT role_row.rolcanlogin
      AND NOT role_row.rolsuper
      AND NOT role_row.rolcreatedb
      AND NOT role_row.rolcreaterole
      AND NOT role_row.rolinherit
      AND NOT role_row.rolreplication
      AND NOT role_row.rolbypassrls
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    WHERE membership.roleid = writer_oid
  ) THEN
    RAISE EXCEPTION 'mapping writer role is login-enabled or has members';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0053_canonical_region_version_mappings'
  ) <> 1 THEN
    RAISE EXCEPTION 'canonical region mapping migration was not recorded once';
  END IF;
END
$check$;
