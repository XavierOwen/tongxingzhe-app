\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6BD.  The
-- companion fixture owns the synthetic source tree, original provenance,
-- complete grid and privacy cases; this check deliberately runs without
-- relying on fixture rows.
DO $check$
DECLARE
  reader_oid oid;
  maintenance_oid oid;
  function_name regprocedure;
  function_row record;
  function_definition text;
  function_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  function_result text;
  table_name text;
  column_name text;
  table_privilege text;
  cell_count integer;
  cell_orders integer[];
  canonical_document jsonb;
  old_channel_rejected boolean := false;
  current_city_rejected boolean := false;
  expected_reader_role constant text :=
    'tongxingzhe_management_original_region_report_reader';
  canonicalizer regprocedure := to_regprocedure(
    'app_private.canonicalize_management_original_region_report_request_v1(jsonb)'
  );
  original_attribution regprocedure := to_regprocedure(
    'app_private.resolve_management_original_region_attribution_v1(uuid)'
  );
  protector regprocedure := to_regprocedure(
    'app_private.protect_management_original_region_contact_session_grid_v1(jsonb,jsonb)'
  );
  executor regprocedure := to_regprocedure(
    'app_private.execute_management_original_region_contact_session_report_v1(uuid,text,timestamp with time zone)'
  );
BEGIN
  SELECT role_row.oid
    INTO reader_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = expected_reader_role;

  IF reader_oid IS NULL THEN
    RAISE EXCEPTION 'original region report reader role is missing';
  END IF;

  SELECT role_row.oid
    INTO maintenance_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = current_user;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = expected_reader_role
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
      'original region report reader is login-enabled or has members';
  END IF;

  IF canonicalizer IS NULL OR original_attribution IS NULL
    OR protector IS NULL OR executor IS NULL
  THEN
    RAISE EXCEPTION 'original region report function set is incomplete';
  END IF;

  FOR function_name IN
    SELECT unnest(ARRAY[canonicalizer, protector, executor])
  LOOP
    SELECT
      pg_catalog.pg_get_functiondef(procedure_row.oid),
      procedure_row.prosecdef,
      procedure_row.proconfig,
      procedure_row.provolatile,
      pg_catalog.pg_get_function_result(procedure_row.oid),
      owner_role.rolname
    INTO
      function_definition,
      function_security_definer,
      function_config,
      function_volatility,
      function_result,
      function_owner
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = function_name;

    IF function_definition IS NULL
      OR NOT function_security_definer
      OR function_owner <> expected_reader_role
    THEN
      RAISE EXCEPTION
        'original region function is not reader-owned SECURITY DEFINER: %',
        function_name;
    END IF;

    IF function_name = canonicalizer THEN
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
        OR function_result <> 'jsonb'
      THEN
        RAISE EXCEPTION 'original region canonicalizer contract is incorrect';
      END IF;
    ELSIF function_name = protector THEN
      IF function_volatility <> 'i'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog'
        ]::text[]
      THEN
        RAISE EXCEPTION 'original region protector contract is incorrect';
      END IF;
    ELSE
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_data, app_private'
        ]::text[]
        OR function_result <> 'jsonb'
      THEN
        RAISE EXCEPTION 'original region executor contract is incorrect';
      END IF;
    END IF;
  END LOOP;

  SELECT
    pg_catalog.pg_get_functiondef(procedure_row.oid),
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile,
    owner_role.rolname
  INTO
    function_definition,
    function_security_definer,
    function_config,
    function_volatility,
    function_owner
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = original_attribution;

  IF NOT function_security_definer
    OR function_owner <> 'tongxingzhe_region_attribution_reader'
    OR function_volatility <> 's'
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_data, app_private'
    ]::text[]
    OR function_definition NOT ILIKE
      '%resolve_management_region_attribution_v1%'
    OR function_definition NOT ILIKE '%original%'
    OR function_definition NOT ILIKE '%NULL%'
    OR function_definition ILIKE '%resolve_canonical_region_version_mapping_v1%'
  THEN
    RAISE EXCEPTION
      'original attribution wrapper does not hard-code the 6AL original seam';
  END IF;

  IF NOT has_function_privilege(
    expected_reader_role, original_attribution, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'original report reader cannot execute its attribution wrapper';
  END IF;

  IF has_function_privilege('public', original_attribution, 'EXECUTE')
    OR has_function_privilege(
      'tongxingzhe_runtime', original_attribution, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_region_report_reader',
      original_attribution,
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_interest_report_reader',
      original_attribution,
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_region_publisher', original_attribution, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_region_mapping_writer', original_attribution, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_contact_provenance_writer',
      original_attribution,
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'original attribution wrapper has an over-broad grant';
  END IF;

  FOR function_row IN
    SELECT
      exploded.grantee,
      coalesce(grantee_role.rolname, 'PUBLIC') AS grantee_name
    FROM aclexplode(
      COALESCE(
        (
          SELECT procedure_row.proacl
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = original_attribution
        ),
        acldefault('f', (
          SELECT procedure_row.proowner
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = original_attribution
        ))
      )
    ) AS exploded
    LEFT JOIN pg_catalog.pg_roles AS grantee_role
      ON grantee_role.oid = exploded.grantee
    WHERE exploded.privilege_type = 'EXECUTE'
  LOOP
    IF function_row.grantee_name NOT IN (
      expected_reader_role,
      'tongxingzhe_region_attribution_reader',
      current_user
    ) THEN
      RAISE EXCEPTION 'unexpected original attribution wrapper grant: %',
        function_row.grantee_name;
    END IF;
  END LOOP;

  canonical_document =
    app_private.canonicalize_management_original_region_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_original_region_two_periods',
        'report_version', 1
      )
    );

  IF canonical_document->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_original_region_two_periods'
    OR canonical_document->>'report_version' IS DISTINCT FROM '1'
    OR canonical_document->>'dimension' IS DISTINCT FROM 'original_region'
    OR canonical_document->>'view_mode' IS DISTINCT FROM 'original'
    OR canonical_document->>'region_granularity' IS DISTINCT FROM 'city'
    OR canonical_document->>'comparison_period_count' IS DISTINCT FROM '2'
    OR canonical_document->>'period_boundary_id'
      IS DISTINCT FROM 'iso_week_monday_v1'
    OR canonical_document->>'privacy_policy'
      IS DISTINCT FROM 'management_original_region_contact_session_privacy_v1'
    OR canonical_document->>'required_capability'
      IS DISTINCT FROM 'view_anonymous_analytics'
    OR canonical_document->>'query_fingerprint'
      IS DISTINCT FROM
        'management-report:contact_sessions_by_original_region_two_periods:v1'
  THEN
    RAISE EXCEPTION 'original region canonical document is incorrect: %',
      canonical_document;
  END IF;

  FOR function_name IN
    SELECT unnest(ARRAY[canonicalizer])
  LOOP
    BEGIN
      PERFORM app_private.canonicalize_management_original_region_report_request_v1(
        jsonb_build_object(
          'report_id', 'contact_sessions_by_original_region_two_periods',
          'report_version', 1,
          'city_ids', jsonb_build_array('forbidden-client-scope')
        )
      );
      RAISE EXCEPTION 'original region canonicalizer accepted a free scope';
    EXCEPTION WHEN invalid_parameter_value THEN
      NULL;
    END;
  END LOOP;

  BEGIN
    PERFORM app_private.canonicalize_management_original_region_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_original_region_two_periods',
        'report_version', 1,
        'target_tree_version', 'forbidden-current-tree'
      )
    );
    RAISE EXCEPTION 'original region canonicalizer accepted a target tree';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_original_region_two_periods',
        'report_version', 1
      )
    );
    RAISE EXCEPTION 'legacy channel canonicalizer accepted original region';
  EXCEPTION WHEN invalid_parameter_value THEN
    old_channel_rejected := true;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_current_city_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_original_region_two_periods',
        'report_version', 1
      )
    );
    RAISE EXCEPTION 'current-city canonicalizer accepted original region';
  EXCEPTION WHEN invalid_parameter_value THEN
    current_city_rejected := true;
  END;

  IF NOT old_channel_rejected OR NOT current_city_rejected THEN
    RAISE EXCEPTION 'cross-family canonicalizer isolation is incomplete';
  END IF;

  SELECT count(*), array_agg(cell_order ORDER BY cell_order)
    INTO cell_count, cell_orders
  FROM app_private.protect_management_original_region_contact_session_grid_v1(
    jsonb_build_array('original-city-z', 'original-city-a'),
    '[]'::jsonb
  );

  IF cell_count <> 4 OR cell_orders IS DISTINCT FROM ARRAY[0, 1, 2, 3] THEN
    RAISE EXCEPTION 'original region protector does not emit a stable grid: % %',
      cell_count, cell_orders;
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_report_definitions AS definition
    WHERE definition.report_id =
        'contact_sessions_by_original_region_two_periods'
      AND definition.report_version = 1
      AND definition.metric_id = 'contact_sessions'
      AND definition.metric_version = 1
      AND definition.dimension_key = 'original_region'
      AND definition.period_grain = 'week'
      AND definition.comparison_period_count = 2
      AND definition.period_boundary_id = 'iso_week_monday_v1'
      AND definition.privacy_policy =
        'management_original_region_contact_session_privacy_v1'
      AND definition.required_capability = 'view_anonymous_analytics'
      AND definition.query_fingerprint =
        'management-report:contact_sessions_by_original_region_two_periods:v1'
  ) <> 1 THEN
    RAISE EXCEPTION 'original region report definition is incorrect';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(procedure_row.oid)
    INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = executor;

  -- Original history must be exact source evidence.  A future edit must not
  -- silently turn this report into a current projection or mapping report.
  FOREACH table_name IN ARRAY ARRAY[
    'resolve_management_original_region_attribution_v1',
    'original',
    'source_tree_version',
    'source_content_fingerprint',
    'original_exact_source',
    'contact_location_provenance',
    'canonical_region_versions',
    'resolve_management_report_periods_v1',
    'change_feed',
    'protect_management_original_region_contact_session_grid_v1',
    'canonical_name',
    'place_name',
    'latitude',
    'longitude',
    'geometry'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || table_name || '%' THEN
      RAISE EXCEPTION 'original region executor omits contract element: %',
        table_name;
    END IF;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'resolve_canonical_region_version_mapping_v1',
    'resolve_management_current_city_attribution_v1',
    'resolve_management_current_city_target_context_v1',
    'canonical_region_version_mappings',
    'contact_region_assignments',
    'current_selections',
    'target_context'
  ]
  LOOP
    IF function_definition ILIKE '%' || table_name || '%' THEN
      RAISE EXCEPTION 'original region executor has forbidden dependency/field: %',
        table_name;
    END IF;
  END LOOP;

  SELECT pg_catalog.pg_get_functiondef(procedure_row.oid)
    INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = canonicalizer;
  IF function_definition NOT ILIKE '%management_report_definitions%'
    OR function_definition NOT ILIKE
      '%contact_sessions_by_original_region_two_periods%'
    OR function_definition NOT ILIKE '%view_mode%'
    OR function_definition NOT ILIKE '%original%'
  THEN
    RAISE EXCEPTION 'original region canonicalizer does not pin its definition';
  END IF;

  -- The dedicated report reader may execute the private seam.  Runtime,
  -- other report readers, region roles and PUBLIC must not gain a shortcut.
  FOREACH function_name IN ARRAY ARRAY[canonicalizer, protector, executor]
  LOOP
    IF NOT has_function_privilege(
      expected_reader_role, function_name, 'EXECUTE'
    ) OR NOT has_function_privilege(current_user, function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'original region function execution grant is incomplete: %',
        function_name;
    END IF;

    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
      OR has_function_privilege(
        'tongxingzhe_management_region_report_reader', function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_interest_report_reader', function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_region_publisher', function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_region_mapping_writer', function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_contact_provenance_writer', function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_region_attribution_reader', function_name, 'EXECUTE'
      )
    THEN
      RAISE EXCEPTION
        'original region function has an over-broad EXECUTE grant: %',
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
        AND function_row.grantee <> maintenance_oid
      THEN
        RAISE EXCEPTION 'unexpected original region EXECUTE grant: %',
          function_row.grantee;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'app_private.management_report_definitions',
    'app_data.projects',
    'app_data.workspaces',
    'app_data.contacts',
    'app_data.contact_region_assignments',
    'app_data.contact_location_provenance',
    'app_data.canonical_region_boundaries',
    'app_data.canonical_region_tree_current_selections',
    'app_data.canonical_region_tree_releases',
    'app_data.canonical_region_version_mappings',
    'app_data.canonical_region_versions',
    'app_data.change_feed'
  ]
  LOOP
    IF has_table_privilege(expected_reader_role, table_name, 'SELECT') THEN
      RAISE EXCEPTION 'original region reader has table-level SELECT on %',
        table_name;
    END IF;
    FOREACH table_privilege IN ARRAY ARRAY[
      'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
    ]
    LOOP
      IF has_table_privilege(expected_reader_role, table_name, table_privilege)
      THEN
        RAISE EXCEPTION 'original region reader has % privilege on %',
          table_privilege, table_name;
      END IF;
    END LOOP;
    FOREACH table_privilege IN ARRAY ARRAY[
      'INSERT', 'UPDATE', 'REFERENCES'
    ]
    LOOP
      IF has_any_column_privilege(
        expected_reader_role, table_name, table_privilege
      ) THEN
        RAISE EXCEPTION 'original region reader has column % privilege on %',
          table_privilege, table_name;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'app_data.contact_region_assignments',
    'app_data.canonical_region_boundaries',
    'app_data.canonical_region_tree_current_selections',
    'app_data.canonical_region_version_mappings'
  ]
  LOOP
    IF has_any_column_privilege(
      expected_reader_role, table_name, 'SELECT'
    ) THEN
      RAISE EXCEPTION 'original reader can read forbidden table columns: %',
        table_name;
    END IF;
  END LOOP;

  FOREACH column_name IN ARRAY ARRAY[
    'project_id',
    'workspace_id',
    'status'
  ]
  LOOP
    IF NOT has_column_privilege(
      expected_reader_role, 'app_data.projects', column_name, 'SELECT'
    ) THEN
      RAISE EXCEPTION 'original region reader lacks project SELECT: %',
        column_name;
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
      expected_reader_role, 'app_data.contacts', column_name, 'SELECT'
    ) THEN
      RAISE EXCEPTION 'original region reader lacks contact SELECT: %',
        column_name;
    END IF;
  END LOOP;

  FOREACH column_name IN ARRAY ARRAY[
    'channel',
    'channel_detail',
    'place_name',
    'latitude',
    'longitude',
    'location_accuracy_meters',
    'location_kind',
    'smallest_region_id',
    'region_tree_version',
    'reach_count',
    'interest_level'
  ]
  LOOP
    IF has_column_privilege(
      expected_reader_role,
      'app_data.contacts',
      column_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'original reader can read sensitive contact field: %',
        column_name;
    END IF;
  END LOOP;

  FOREACH column_name IN ARRAY ARRAY[
    'canonical_name',
    'attributes'
  ]
  LOOP
    IF has_column_privilege(
      expected_reader_role,
      'app_data.canonical_region_versions',
      column_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'original reader can read region display metadata: %',
        column_name;
    END IF;
  END LOOP;

  FOREACH column_name IN ARRAY ARRAY[
    'revision_kind',
    'location_kind',
    'evidence_kind',
    'place_name',
    'latitude',
    'longitude',
    'accuracy_meters',
    'smallest_region_id',
    'region_tree_version',
    'region_tree_content_fingerprint',
    'resolver_contract_version',
    'recorded_at_utc'
  ]
  LOOP
    IF has_column_privilege(
      expected_reader_role,
      'app_data.contact_location_provenance',
      column_name,
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'original reader can read sensitive provenance field: %',
        column_name;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0066_management_original_region_report'
  ) <> 1 THEN
    RAISE EXCEPTION 'original region report migration was not recorded once';
  END IF;
END
$check$;
