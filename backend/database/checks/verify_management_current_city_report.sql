\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6AN.  Behavioural
-- attribution, threshold and concurrent publication cases belong to the
-- 0056 fixture and the dedicated concurrency script.
DO $check$
DECLARE
  reader_oid oid;
  release_writer_oid oid;
  maintenance_oid oid;
  function_row record;
  function_definition text;
  function_owner text;
  function_proconfig text[];
  function_provolatile "char";
  function_prosecdef boolean;
  function_result text;
  function_name regprocedure;
  table_name text;
  column_name text;
  table_privilege text;
  cell_count integer;
  first_cell_order integer;
  canonical_request jsonb;
  old_channel_rejected boolean := false;
BEGIN
  SELECT role_row.oid
  INTO reader_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_management_region_report_reader';
  IF reader_oid IS NULL THEN
    RAISE EXCEPTION 'management region report reader role is missing';
  END IF;

  SELECT role_row.oid
  INTO release_writer_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname =
      'tongxingzhe_management_current_city_snapshot_release_writer';
  IF release_writer_oid IS NULL THEN
    RAISE EXCEPTION 'management current city snapshot release writer role is missing';
  END IF;

  SELECT role_row.oid
  INTO maintenance_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = current_user;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname =
        'tongxingzhe_management_region_report_reader'
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
      'management region report reader is login-enabled or has members';
  END IF;

  FOR function_name IN
    SELECT unnest(ARRAY[
      to_regprocedure(
        'app_private.canonicalize_management_current_city_report_request_v1(jsonb)'
      ),
      to_regprocedure(
        'app_private.protect_management_current_city_contact_session_grid_v1(jsonb,jsonb)'
      ),
      to_regprocedure(
        'app_private.execute_management_current_city_contact_session_report_v1(uuid,text,timestamp with time zone)'
      ),
      to_regprocedure(
        'app_private.resolve_management_current_city_target_context_v1(timestamp with time zone)'
      ),
      to_regprocedure(
        'app_private.resolve_management_current_city_attribution_v1(uuid,text,text,text)'
      )
    ]::regprocedure[])
  LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'one or more current city report functions are missing';
    END IF;
  END LOOP;

  -- The canonicalizer, protector and executor have different volatility
  -- contracts: registry lookup, pure privacy transform, and target-bound
  -- execution respectively.
  FOR function_name IN
    SELECT unnest(ARRAY[
      to_regprocedure(
        'app_private.canonicalize_management_current_city_report_request_v1(jsonb)'
      ),
      to_regprocedure(
        'app_private.protect_management_current_city_contact_session_grid_v1(jsonb,jsonb)'
      ),
      to_regprocedure(
        'app_private.execute_management_current_city_contact_session_report_v1(uuid,text,timestamp with time zone)'
      )
    ]::regprocedure[])
  LOOP
    SELECT
      pg_get_functiondef(procedure_row.oid),
      procedure_row.prosecdef,
      procedure_row.proconfig,
      procedure_row.provolatile,
      pg_get_function_result(procedure_row.oid),
      owner_role.rolname
    INTO
      function_definition,
      function_prosecdef,
      function_proconfig,
      function_provolatile,
      function_result,
      function_owner
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = function_name;

    IF NOT function_prosecdef
      OR function_owner <> 'tongxingzhe_management_region_report_reader'
    THEN
      RAISE EXCEPTION 'current city function is not reader-owned SECURITY DEFINER: %',
        function_name;
    END IF;

    IF function_name::text LIKE '%canonicalize%' THEN
      IF function_provolatile <> 's'
        OR function_proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'current city canonicalizer contract is incorrect';
      END IF;
    ELSIF function_name::text LIKE '%protect%' THEN
      IF function_provolatile <> 'i'
        OR function_proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog'
        ]::text[]
      THEN
        RAISE EXCEPTION 'current city protector contract is incorrect';
      END IF;
    ELSE
      IF function_provolatile <> 'v'
        OR function_proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_data, app_private'
        ]::text[]
        OR function_result <> 'jsonb'
      THEN
        RAISE EXCEPTION 'current city executor contract is incorrect';
      END IF;
    END IF;

    IF function_definition IS NULL THEN
      RAISE EXCEPTION 'current city function definition is unavailable: %',
        function_name;
    END IF;
  END LOOP;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.execute_management_current_city_contact_session_report_v1(uuid,text,timestamp with time zone)'
  );

  FOREACH table_name IN ARRAY ARRAY[
    'resolve_management_current_city_target_context_v1',
    'resolve_management_current_city_attribution_v1',
    'contact_location_provenance',
    'canonical_region_versions',
    'change_feed',
    'source_change_sequence',
    'contact_sessions_by_current_city_two_periods',
    'current_revision',
    'target_context_contract_id',
    'attribution_contract_id',
    'not_reportable',
    'unmapped',
    'ambiguous',
    'period_boundary_id',
    'target_content_fingerprint',
    'target_tree_version'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || table_name || '%' THEN
      RAISE EXCEPTION 'current city executor omits contract element: %',
        table_name;
    END IF;
  END LOOP;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.canonicalize_management_current_city_report_request_v1(jsonb)'
  );
  IF function_definition NOT ILIKE '%management_report_definitions%'
    OR function_definition NOT ILIKE
      '%contact_sessions_by_current_city_two_periods%'
  THEN
    RAISE EXCEPTION 'current city canonicalizer does not read its fixed definition';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.execute_management_current_city_contact_session_report_v1(uuid,text,timestamp with time zone)'
  );

  -- The report must not widen the sensitive 6AL evidence surface or choose a
  -- mutable target projection itself.
  FOREACH table_name IN ARRAY ARRAY[
    'canonical_name',
    'display_name',
    'place_name',
    'channel_detail',
    'latitude',
    'longitude',
    'is_current'
  ]
  LOOP
    IF function_definition ILIKE '%' || table_name || '%' THEN
      RAISE EXCEPTION 'current city executor exposes forbidden field: %',
        table_name;
    END IF;
  END LOOP;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.resolve_management_current_city_target_context_v1(timestamp with time zone)'
  );
  IF function_definition NOT ILIKE
      '%resolve_management_report_region_target_context_v1%'
  THEN
    RAISE EXCEPTION 'current city target wrapper does not delegate to 6AM';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.resolve_management_current_city_attribution_v1(uuid,text,text,text)'
  );
  IF function_definition NOT ILIKE '%resolve_management_region_attribution_v1%'
  THEN
    RAISE EXCEPTION 'current city attribution wrapper does not delegate to 6AL';
  END IF;

  SELECT count(*)
  INTO cell_count
  FROM app_private.protect_management_current_city_contact_session_grid_v1(
    '["city-z","city-a"]'::jsonb,
    '[]'::jsonb
  );
  IF cell_count <> 4 THEN
    RAISE EXCEPTION 'current city protector does not emit a complete grid';
  END IF;

  SELECT min(cell_order)
  INTO first_cell_order
  FROM app_private.protect_management_current_city_contact_session_grid_v1(
    '["city-z","city-a"]'::jsonb,
    '[]'::jsonb
  );
  IF first_cell_order <> 0 THEN
    RAISE EXCEPTION 'current city protector cell ordering is not stable';
  END IF;

  BEGIN
    PERFORM app_private.canonicalize_management_current_city_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 1,
        'extra', true
      )
    );
    RAISE EXCEPTION 'current city canonicalizer accepted an extra field';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 1
      )
    );
    RAISE EXCEPTION 'legacy channel canonicalizer accepted the current city report';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    old_channel_rejected := true;
  END;
  IF NOT old_channel_rejected THEN
    RAISE EXCEPTION 'legacy channel canonicalizer did not reject current city';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_report_definitions AS definition
    WHERE definition.report_id =
        'contact_sessions_by_current_city_two_periods'
      AND definition.report_version = 1
      AND definition.metric_id = 'contact_sessions'
      AND definition.metric_version = 1
      AND definition.dimension_key = 'current_city'
      AND definition.period_grain = 'week'
      AND definition.comparison_period_count = 2
      AND definition.period_boundary_id = 'iso_week_monday_v1'
      AND definition.privacy_policy =
        'management_current_city_contact_session_privacy_v1'
      AND definition.required_capability = 'view_anonymous_analytics'
      AND definition.query_fingerprint =
        'management-report:contact_sessions_by_current_city_two_periods:v1'
  ) <> 1 THEN
    RAISE EXCEPTION 'current city report definition is incorrect';
  END IF;

  -- The report reader, the snapshot release writer and the migration identity
  -- may execute the three private report functions.  The narrow wrappers are
  -- likewise not exposed to runtime or maintenance roles.
  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.canonicalize_management_current_city_report_request_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.protect_management_current_city_contact_session_grid_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.execute_management_current_city_contact_session_report_v1(uuid,text,timestamp with time zone)'
    )
  ]::regprocedure[]
  LOOP
    IF NOT has_function_privilege(
      'tongxingzhe_management_region_report_reader', function_name, 'EXECUTE'
    ) OR NOT has_function_privilege(current_user, function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'current city function execution grant is incomplete: %',
        function_name;
    END IF;
    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_region_publisher', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_region_mapping_writer', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_contact_provenance_writer', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_region_attribution_reader', function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'current city function has an over-broad EXECUTE grant: %',
        function_name;
    END IF;
    FOR function_row IN
      SELECT exploded.grantee, exploded.privilege_type
      FROM aclexplode(
        COALESCE(
          (
            SELECT procedure_row.proacl
            FROM pg_catalog.pg_proc AS procedure_row
            WHERE procedure_row.oid = function_name
          ),
          acldefault('f', (
            SELECT procedure_row.proowner
            FROM pg_catalog.pg_proc AS procedure_row
            WHERE procedure_row.oid = function_name
          ))
        )
      ) AS exploded
      WHERE exploded.privilege_type = 'EXECUTE'
    LOOP
      IF function_row.grantee = 0
        OR function_row.grantee <> reader_oid
        AND function_row.grantee <> release_writer_oid
        AND function_row.grantee <> maintenance_oid
      THEN
        RAISE EXCEPTION 'unexpected current city EXECUTE grant: %',
          function_row.grantee;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'app_private.management_report_definitions',
    'app_data.projects',
    'app_data.workspaces',
    'app_data.contacts',
    'app_data.contact_location_provenance',
    'app_data.canonical_region_versions',
    'app_data.change_feed'
  ]
  LOOP
    FOREACH table_privilege IN ARRAY ARRAY[
      'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
    ]
    LOOP
      IF has_table_privilege(
        'tongxingzhe_management_region_report_reader',
        table_name,
        table_privilege
      ) THEN
        RAISE EXCEPTION 'reader has % privilege on %',
          table_privilege, table_name;
      END IF;
    END LOOP;
    FOREACH table_privilege IN ARRAY ARRAY[
      'INSERT', 'UPDATE', 'REFERENCES'
    ]
    LOOP
      IF has_any_column_privilege(
        'tongxingzhe_management_region_report_reader',
        table_name,
        table_privilege
      ) THEN
        RAISE EXCEPTION 'reader has column % privilege on %',
          table_privilege, table_name;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH column_name IN ARRAY ARRAY[
    'project_id',
    'workspace_id',
    'status'
  ]
  LOOP
    IF NOT has_column_privilege(
      'tongxingzhe_management_region_report_reader',
      'app_data.projects',
      column_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'reader lacks project column SELECT: %', column_name;
    END IF;
  END LOOP;

  FOREACH column_name IN ARRAY ARRAY[
    'contact_id',
    'app_user_id',
    'project_id',
    'occurred_at_utc',
    'first_submitted_at_utc',
    'current_revision',
    'lifecycle_status'
  ]
  LOOP
    IF NOT has_column_privilege(
      'tongxingzhe_management_region_report_reader',
      'app_data.contacts',
      column_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'reader lacks contact column SELECT: %', column_name;
    END IF;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'channel',
    'channel_detail',
    'place_name',
    'latitude',
    'longitude',
    'location_kind',
    'smallest_region_id',
    'region_tree_version'
  ]
  LOOP
    IF has_column_privilege(
      'tongxingzhe_management_region_report_reader',
      CASE
        WHEN table_name IN (
          'channel', 'channel_detail', 'place_name', 'latitude',
          'longitude', 'location_kind'
        ) THEN 'app_data.contacts'
        ELSE 'app_data.contact_location_provenance'
      END,
      table_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'reader can directly read sensitive location field: %',
        table_name;
    END IF;
  END LOOP;

  IF NOT has_column_privilege(
    'tongxingzhe_management_region_report_reader',
    'app_data.change_feed',
    'project_id',
    'SELECT'
  ) OR NOT has_column_privilege(
    'tongxingzhe_management_region_report_reader',
    'app_data.change_feed',
    'change_sequence',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'reader lacks source change watermark columns';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0056_management_current_city_report'
  ) <> 1 THEN
    RAISE EXCEPTION 'current city report migration was not recorded once';
  END IF;
END
$check$;
