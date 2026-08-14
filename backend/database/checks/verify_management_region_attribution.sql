\set ON_ERROR_STOP on

-- Structural and privilege contract for Slice 6AL. The following 0054
-- fixture supplies the synthetic source, release and boundary rows used for
-- behaviour checks; this file must also pass on an empty database after all
-- migrations have been applied.
DO $check$
DECLARE
  attribution_function regprocedure := to_regprocedure(
    'app_private.resolve_management_region_attribution_v1(uuid,text,text,text)'
  );
  mapping_function regprocedure := to_regprocedure(
    'app_private.resolve_canonical_region_version_mapping_v1(text,text,text,text,text)'
  );
  reader_oid oid;
  maintenance_oid oid;
  function_row record;
  function_definition text;
  function_prosecdef boolean;
  function_proconfig text[];
  function_provolatile "char";
  function_return_type regtype;
  function_owner text;
  expected_search_path text[] := ARRAY[
    'search_path=pg_catalog, app_data, app_private'
  ];
  table_name text;
  table_privilege text;
BEGIN
  IF attribution_function IS NULL OR mapping_function IS NULL THEN
    RAISE EXCEPTION 'management region attribution functions are incomplete';
  END IF;

  SELECT oid
    INTO reader_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = 'tongxingzhe_region_attribution_reader';
  IF reader_oid IS NULL THEN
    RAISE EXCEPTION 'region attribution reader role is missing';
  END IF;

  SELECT oid
    INTO maintenance_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = current_user;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile,
    procedure_row.prorettype::regtype,
    owner_role.rolname
    INTO function_definition, function_prosecdef,
         function_proconfig, function_provolatile,
         function_return_type, function_owner
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = attribution_function;

  IF function_definition IS NULL OR NOT function_prosecdef
    OR function_owner <> 'tongxingzhe_region_attribution_reader'
  THEN
    RAISE EXCEPTION
      'attribution resolver is not reader-owned SECURITY DEFINER';
  END IF;

  IF function_proconfig IS DISTINCT FROM expected_search_path THEN
    RAISE EXCEPTION 'attribution resolver search_path is not fixed: %',
      function_proconfig;
  END IF;

  IF function_provolatile <> 's'
    OR function_return_type IS DISTINCT FROM 'jsonb'::regtype
  THEN
    RAISE EXCEPTION
      'attribution resolver is not a STABLE jsonb function';
  END IF;

  -- The resolver may read only the immutable source/release evidence and the
  -- explicit mapping contract. It must never consult the mutable current
  -- selection or expose a generic report/query surface.
  FOREACH table_name IN ARRAY ARRAY[
    'contact_location_provenance',
    'canonical_region_tree_releases',
    'canonical_region_versions',
    'canonical_region_boundaries'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || table_name || '%' THEN
      RAISE EXCEPTION 'attribution resolver does not read %', table_name;
    END IF;
  END LOOP;
  IF function_definition NOT ILIKE '%resolve_canonical_region_version_mapping_v1%'
  THEN
    RAISE EXCEPTION 'attribution resolver does not use the explicit 6AK mapping';
  END IF;
  IF function_definition ILIKE '%current_selections%'
    OR function_definition ILIKE '%is_current%'
    OR function_definition ILIKE '%SELECT * INTO target_release%'
  THEN
    RAISE EXCEPTION
      'attribution resolver reads mutable current selection state';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_region_attribution_reader',
    mapping_function,
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'reader cannot execute the explicit mapping resolver';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'app_data.contact_location_provenance',
    'app_data.canonical_region_tree_releases',
    'app_data.canonical_region_versions',
    'app_data.canonical_region_boundaries'
  ]
  LOOP
    IF NOT has_table_privilege(
      'tongxingzhe_region_attribution_reader', table_name, 'SELECT'
    ) THEN
      RAISE EXCEPTION 'reader lacks SELECT on %', table_name;
    END IF;
    FOREACH table_privilege IN ARRAY ARRAY[
      'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
    ]
    LOOP
      IF has_table_privilege(
        'tongxingzhe_region_attribution_reader',
        table_name,
        table_privilege
      ) THEN
        RAISE EXCEPTION 'reader has % access to %',
          table_privilege, table_name;
      END IF;
    END LOOP;
    FOREACH table_privilege IN ARRAY ARRAY[
      'INSERT', 'UPDATE', 'REFERENCES'
    ]
    LOOP
      IF has_any_column_privilege(
        'tongxingzhe_region_attribution_reader',
        table_name,
        table_privilege
      ) THEN
        RAISE EXCEPTION 'reader has column % access to %',
          table_privilege, table_name;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH table_privilege IN ARRAY ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ]
  LOOP
    IF has_table_privilege(
      'tongxingzhe_region_attribution_reader',
      'app_data.canonical_region_version_mappings',
      table_privilege
    ) THEN
      RAISE EXCEPTION
        'reader has direct % on the 6AK mapping table', table_privilege;
    END IF;
  END LOOP;
  FOREACH table_privilege IN ARRAY ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'REFERENCES'
  ]
  LOOP
    IF has_any_column_privilege(
      'tongxingzhe_region_attribution_reader',
      'app_data.canonical_region_version_mappings',
      table_privilege
    ) THEN
      RAISE EXCEPTION
        'reader has direct column % on the 6AK mapping table', table_privilege;
    END IF;
  END LOOP;

  -- Only the no-login reader and the migration identity may execute the new
  -- private resolver. Runtime, PUBLIC and the maintenance roles remain
  -- unable to turn it into a general report or data-exfiltration bridge.
  IF NOT has_function_privilege(
    'tongxingzhe_region_attribution_reader', attribution_function, 'EXECUTE'
  ) OR NOT has_function_privilege(
    current_user, attribution_function, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'attribution resolver execution grant is incomplete';
  END IF;
  IF has_function_privilege('tongxingzhe_runtime', attribution_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_region_publisher', attribution_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_region_mapping_writer', attribution_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_contact_provenance_writer', attribution_function, 'EXECUTE')
  THEN
    RAISE EXCEPTION 'attribution resolver has an over-broad EXECUTE grant';
  END IF;

  FOR function_row IN
    SELECT exploded.grantee, exploded.privilege_type
    FROM aclexplode(
      COALESCE(
        (
          SELECT procedure_row.proacl
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = attribution_function
        ),
        acldefault('f', (
          SELECT procedure_row.proowner
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = attribution_function
        ))
      )
    ) AS exploded
    WHERE exploded.privilege_type = 'EXECUTE'
  LOOP
    IF function_row.grantee = 0
      OR function_row.grantee <> reader_oid
      AND function_row.grantee <> maintenance_oid
    THEN
      RAISE EXCEPTION 'unexpected attribution resolver EXECUTE grant: %',
        function_row.grantee;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = 'tongxingzhe_region_attribution_reader'
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
    WHERE membership.roleid = reader_oid
  ) THEN
    RAISE EXCEPTION
      'attribution reader role is login-enabled or has members';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0054_management_region_attribution'
  ) <> 1 THEN
    RAISE EXCEPTION 'management region attribution migration was not recorded once';
  END IF;
END
$check$;
