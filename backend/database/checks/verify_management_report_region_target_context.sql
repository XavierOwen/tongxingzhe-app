\set ON_ERROR_STOP on

-- Structural and privilege contract for Slice 6AM.  Behavioural cutoff,
-- baseline and publication-boundary cases belong to the 0055 synthetic fixture.
DO $check$
DECLARE
  target_context_function regprocedure := to_regprocedure(
    'app_private.resolve_management_report_region_target_context_v1(timestamp with time zone)'
  );
  reader_oid oid;
  maintenance_oid oid;
  function_definition text;
  function_owner text;
  function_proconfig text[];
  function_provolatile "char";
  function_return_type regtype;
  function_prosecdef boolean;
  function_row record;
  table_privilege text;
BEGIN
  IF target_context_function IS NULL THEN
    RAISE EXCEPTION
      'management region target context resolver is missing';
  END IF;

  SELECT role_row.oid
  INTO reader_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_region_attribution_reader';
  IF reader_oid IS NULL THEN
    RAISE EXCEPTION 'region attribution reader role is missing';
  END IF;

  SELECT role_row.oid
  INTO maintenance_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = current_user;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile,
    procedure_row.prorettype::regtype,
    owner_role.rolname
  INTO
    function_definition,
    function_prosecdef,
    function_proconfig,
    function_provolatile,
    function_return_type,
    function_owner
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = target_context_function;

  IF function_definition IS NULL
    OR NOT function_prosecdef
    OR function_owner <> 'tongxingzhe_region_attribution_reader'
  THEN
    RAISE EXCEPTION
      'region target context resolver is not reader-owned SECURITY DEFINER';
  END IF;

  IF function_proconfig IS DISTINCT FROM ARRAY[
    'search_path=pg_catalog, app_data, app_private'
  ]::text[] THEN
    RAISE EXCEPTION
      'region target context resolver search_path is not fixed: %',
      function_proconfig;
  END IF;

  IF function_provolatile <> 'v'
    OR function_return_type IS DISTINCT FROM 'jsonb'::regtype
  THEN
    RAISE EXCEPTION
      'region target context resolver is not a VOLATILE jsonb function';
  END IF;

  FOREACH table_privilege IN ARRAY ARRAY[
    'canonical_region_tree_current_selections',
    'canonical_region_tree_releases'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || table_privilege || '%' THEN
      RAISE EXCEPTION
        'region target context resolver does not read %', table_privilege;
    END IF;
  END LOOP;

  IF function_definition NOT ILIKE '%canonical-region-tree-publication:v1%'
    OR function_definition NOT ILIKE '%pg_advisory_xact_lock%'
    OR function_definition NOT ILIKE '%target_context_contract_id%'
    OR function_definition NOT ILIKE '%management-region-target-context:v1%'
    OR function_definition NOT ILIKE '%selection_history_unavailable%'
    OR function_definition NOT ILIKE '%publication_selection%'
    OR function_definition NOT ILIKE '%migration_baseline_observation%'
    OR function_definition NOT ILIKE '%target_tree_version%'
    OR function_definition NOT ILIKE '%target_content_fingerprint%'
    OR function_definition NOT ILIKE '%selection_sequence%'
    OR function_definition NOT ILIKE '%selection_source%'
    OR function_definition NOT ILIKE '%selection_evidence_at_utc%'
    OR function_definition NOT ILIKE '%tree_published_at_utc%'
    OR function_definition NOT ILIKE '%release.lifecycle_state%'
    OR function_definition NOT ILIKE '%release.published_at_utc%'
    OR function_definition NOT ILIKE '%release.content_fingerprint%'
  THEN
    RAISE EXCEPTION
      'region target context resolver output or publication contract is incomplete';
  END IF;

  -- The target choice is history-based.  A mutable projection or a direct
  -- data mutation would make the private context unsuitable for replay.
  IF function_definition ILIKE '%is_current%'
    OR function_definition ILIKE '%SELECT release.*%'
    OR function_definition ~* '\m(INSERT|UPDATE|DELETE|TRUNCATE)\M'
  THEN
    RAISE EXCEPTION
      'region target context resolver reads mutable state or mutates data';
  END IF;

  IF NOT has_table_privilege(
    'tongxingzhe_region_attribution_reader',
    'app_data.canonical_region_tree_current_selections',
    'SELECT'
  ) THEN
    RAISE EXCEPTION
      'reader lacks selection-history SELECT privilege';
  END IF;

  FOREACH table_privilege IN ARRAY ARRAY[
    'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ]
  LOOP
    IF has_table_privilege(
      'tongxingzhe_region_attribution_reader',
      'app_data.canonical_region_tree_current_selections',
      table_privilege
    ) THEN
      RAISE EXCEPTION
        'reader has % privilege on selection history', table_privilege;
    END IF;
  END LOOP;

  FOREACH table_privilege IN ARRAY ARRAY[
    'INSERT', 'UPDATE', 'REFERENCES'
  ]
  LOOP
    IF has_any_column_privilege(
      'tongxingzhe_region_attribution_reader',
      'app_data.canonical_region_tree_current_selections',
      table_privilege
    ) THEN
      RAISE EXCEPTION
        'reader has column % privilege on selection history', table_privilege;
    END IF;
  END LOOP;

  IF NOT has_function_privilege(
    'tongxingzhe_region_attribution_reader',
    target_context_function,
    'EXECUTE'
  ) OR NOT has_function_privilege(
    current_user,
    target_context_function,
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'region target context resolver execution grant is incomplete';
  END IF;

  IF has_function_privilege('tongxingzhe_runtime', target_context_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_region_publisher', target_context_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_region_mapping_writer', target_context_function, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_contact_provenance_writer', target_context_function, 'EXECUTE')
    OR has_function_privilege('public', target_context_function, 'EXECUTE')
  THEN
    RAISE EXCEPTION
      'region target context resolver has an over-broad EXECUTE grant';
  END IF;

  FOR function_row IN
    SELECT exploded.grantee, exploded.privilege_type
    FROM aclexplode(
      COALESCE(
        (
          SELECT procedure_row.proacl
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = target_context_function
        ),
        acldefault('f', (
          SELECT procedure_row.proowner
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = target_context_function
        ))
      )
    ) AS exploded
    WHERE exploded.privilege_type = 'EXECUTE'
  LOOP
    IF function_row.grantee = 0
      OR function_row.grantee <> reader_oid
      AND function_row.grantee <> maintenance_oid
    THEN
      RAISE EXCEPTION
        'unexpected target context resolver EXECUTE grant: %',
        function_row.grantee;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    WHERE membership.roleid = reader_oid
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.oid = reader_oid
      AND (
        role_row.rolcanlogin
        OR role_row.rolsuper
        OR role_row.rolcreatedb
        OR role_row.rolcreaterole
        OR role_row.rolinherit
        OR role_row.rolreplication
        OR role_row.rolbypassrls
      )
  ) THEN
    RAISE EXCEPTION
      'region attribution reader role is login-enabled or has members';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0055_management_report_region_target_context'
  ) <> 1 THEN
    RAISE EXCEPTION
      'management region target context migration was not recorded once';
  END IF;
END
$check$;
