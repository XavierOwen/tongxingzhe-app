\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6AV.  Behavioural
-- cases and source filtering belong to the 0061 fixture.
DO $check$
DECLARE
  reader_oid oid;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_proconfig text[];
  function_provolatile "char";
  function_prosecdef boolean;
  function_result text;
  definition_count integer;
  role_name text;
  routine_name text;
  canonical_document jsonb;
BEGIN
  SELECT role_row.oid
  INTO reader_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname =
    'tongxingzhe_management_interest_report_reader';
  IF reader_oid IS NULL THEN
    RAISE EXCEPTION 'management interest report reader role is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname =
        'tongxingzhe_management_interest_report_reader'
      AND (
        role_row.rolcanlogin
        OR role_row.rolsuper
        OR role_row.rolcreatedb
        OR role_row.rolcreaterole
        OR role_row.rolinherit
        OR role_row.rolreplication
        OR role_row.rolbypassrls
      )
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    WHERE membership.roleid = reader_oid
  ) THEN
    RAISE EXCEPTION
      'management interest report reader is login-enabled or has members';
  END IF;

  FOR routine_name IN
    SELECT unnest(ARRAY[
      'app_private.canonicalize_management_interest_distribution_report_request_v1(jsonb)',
      'app_private.protect_management_interest_distribution_grid_v1(jsonb)',
      'app_private.execute_management_interest_distribution_report_v1(uuid,text,timestamp with time zone)'
    ])
  LOOP
    function_name = to_regprocedure(routine_name);
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'management interest report function is missing: %',
        routine_name;
    END IF;

    SELECT
      pg_get_functiondef(procedure_row.oid),
      owner_role.rolname,
      procedure_row.proconfig,
      procedure_row.provolatile,
      procedure_row.prosecdef,
      pg_get_function_result(procedure_row.oid)
    INTO
      function_definition,
      function_owner,
      function_proconfig,
      function_provolatile,
      function_prosecdef,
      function_result
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = function_name;

    IF function_owner <> 'tongxingzhe_management_interest_report_reader'
      OR NOT function_prosecdef
      OR (
        routine_name NOT LIKE '%protect%'
        AND function_result <> 'jsonb'
      )
      OR (
        routine_name LIKE '%protect%'
        AND function_result <>
          'TABLE(period_key text, interest_level integer, cell_order integer, value_count bigint, privacy_status text)'
      )
    THEN
      RAISE EXCEPTION 'management interest report function owner/security contract is incorrect: %',
        routine_name;
    END IF;

    IF routine_name LIKE '%canonicalize%' THEN
      IF function_provolatile <> 's'
        OR function_proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'management interest canonicalizer contract is incorrect';
      END IF;
    ELSIF routine_name LIKE '%protect%' THEN
      IF function_provolatile <> 'i'
        OR function_proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog'
        ]::text[]
      THEN
        RAISE EXCEPTION 'management interest privacy policy contract is incorrect';
      END IF;
    ELSE
      IF function_provolatile <> 's'
        OR function_proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_data, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'management interest executor contract is incorrect';
      END IF;
    END IF;

    IF function_definition IS NULL THEN
      RAISE EXCEPTION 'management interest function definition is unavailable: %',
        routine_name;
    END IF;
  END LOOP;

  SELECT count(*)
  INTO definition_count
  FROM app_private.management_report_definitions AS definition
  WHERE definition.report_id =
      'contact_sessions_by_interest_level_two_periods'
    AND definition.report_version = 1
    AND definition.metric_id = 'interest_distribution'
    AND definition.metric_version = 1
    AND definition.dimension_key = 'interest_level'
    AND definition.period_grain = 'week'
    AND definition.comparison_period_count = 2
    AND definition.period_boundary_id = 'iso_week_monday_v1'
    AND definition.privacy_policy =
      'management_interest_distribution_privacy_v1'
    AND definition.required_capability = 'view_anonymous_analytics'
    AND definition.query_fingerprint =
      'management-report:contact_sessions_by_interest_level_two_periods:v1';
  IF definition_count <> 1 THEN
    RAISE EXCEPTION 'management interest report definition is not fixed exactly once';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.canonicalize_management_interest_distribution_report_request_v1(jsonb)'
  );
  IF function_definition NOT ILIKE '%management_report_definitions%'
    OR function_definition NOT ILIKE '%requested_request <> jsonb_build_object%'
    OR function_definition NOT ILIKE '%invalid management interest distribution report request%'
  THEN
    RAISE EXCEPTION 'canonicalizer does not reject non-canonical requests';
  END IF;

  canonical_document =
    app_private.canonicalize_management_interest_distribution_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_interest_level_two_periods',
        'report_version', 1
      )
    );
  IF canonical_document <> jsonb_build_object(
    'report_id', 'contact_sessions_by_interest_level_two_periods',
    'report_version', 1,
    'metric_id', 'interest_distribution',
    'metric_version', 1,
    'statistical_unit', 'contact_session',
    'dimension', 'interest_level',
    'period_grain', 'week',
    'comparison_period_count', 2,
    'period_boundary_id', 'iso_week_monday_v1',
    'privacy_policy', 'management_interest_distribution_privacy_v1',
    'required_capability', 'view_anonymous_analytics',
    'query_fingerprint',
      'management-report:contact_sessions_by_interest_level_two_periods:v1'
  ) THEN
    RAISE EXCEPTION 'canonicalizer returned an incorrect fixed document: %',
      canonical_document;
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.protect_management_interest_distribution_grid_v1(jsonb)'
  );
  FOREACH routine_name IN ARRAY ARRAY[
    'period_key',
    'interest_level',
    'contributor_key',
    'unit_count',
    'previous',
    'current',
    '0',
    '1',
    '2',
    '3',
    '4',
    'suppressed',
    'period_can_display',
    'count(*) > 1'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || routine_name || '%' THEN
      RAISE EXCEPTION 'privacy policy omits fixed contract element: %',
        routine_name;
    END IF;
  END LOOP;
  IF function_definition NOT ILIKE '%item - ARRAY%'
    OR function_definition NOT ILIKE '%jsonb_typeof%'
    OR function_definition NOT ILIKE '%unit_count >= 10%'
    OR function_definition NOT ILIKE '%contributor_count >= 3%'
    OR function_definition NOT ILIKE '%max_contribution% * 2%'
  THEN
    RAISE EXCEPTION 'privacy policy does not fail closed on strict input or thresholds';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.execute_management_interest_distribution_report_v1(uuid,text,timestamp with time zone)'
  );
  FOREACH routine_name IN ARRAY ARRAY[
    'projects',
    'workspaces',
    'contacts',
    'project_id',
    'lifecycle_status',
    'first_submitted_at_utc',
    'interest_level',
    'previous_period',
    'current_period',
    'resolve_management_report_periods_v1',
    'protect_management_interest_distribution_grid_v1',
    'backend_accepted_active_contacts_current_revision'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || routine_name || '%' THEN
      RAISE EXCEPTION 'executor omits contract element: %', routine_name;
    END IF;
  END LOOP;
  FOREACH routine_name IN ARRAY ARRAY[
    'channel',
    'channel_detail',
    'place_name',
    'latitude',
    'longitude',
    'contact_id',
    'snapshot',
    'target',
    'person'
  ]
  LOOP
    IF function_definition ILIKE '%' || routine_name || '%' THEN
      RAISE EXCEPTION 'executor references forbidden sensitive field: %',
        routine_name;
    END IF;
  END LOOP;

  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer'
  ]
  LOOP
    IF has_function_privilege(
      role_name,
      'app_private.canonicalize_management_interest_distribution_report_request_v1(jsonb)',
      'EXECUTE'
    ) OR has_function_privilege(
      role_name,
      'app_private.protect_management_interest_distribution_grid_v1(jsonb)',
      'EXECUTE'
    ) OR has_function_privilege(
      role_name,
      'app_private.execute_management_interest_distribution_report_v1(uuid,text,timestamp with time zone)',
      'EXECUTE'
    )
    THEN
      RAISE EXCEPTION 'ordinary app role can reach private interest report: %',
        role_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) AS privilege_row
    WHERE procedure_row.oid IN (
      to_regprocedure(
        'app_private.canonicalize_management_interest_distribution_report_request_v1(jsonb)'
      ),
      to_regprocedure(
        'app_private.protect_management_interest_distribution_grid_v1(jsonb)'
      ),
      to_regprocedure(
        'app_private.execute_management_interest_distribution_report_v1(uuid,text,timestamp with time zone)'
      )
    )
      AND privilege_row.grantee = 0
      AND privilege_row.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC can reach private interest report';
  END IF;

  IF has_schema_privilege(
    'tongxingzhe_runtime',
    'app_private',
    'USAGE'
  ) THEN
    RAISE EXCEPTION
      'runtime can inspect the private interest report schema';
  END IF;

  IF has_column_privilege(
    'tongxingzhe_management_interest_report_reader',
    'app_data.contacts',
    'contact_id',
    'SELECT'
  ) OR has_column_privilege(
    'tongxingzhe_management_interest_report_reader',
    'app_data.contacts',
    'channel',
    'SELECT'
  ) OR has_column_privilege(
    'tongxingzhe_management_interest_report_reader',
    'app_data.contacts',
    'place_name',
    'SELECT'
  ) OR has_column_privilege(
    'tongxingzhe_management_interest_report_reader',
    'app_data.contacts',
    'latitude',
    'SELECT'
  ) OR has_column_privilege(
    'tongxingzhe_management_interest_report_reader',
    'app_data.contacts',
    'longitude',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'interest report reader has an unnecessary sensitive column grant';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0061_management_interest_distribution_report'
  ) <> 1 THEN
    RAISE EXCEPTION 'management interest distribution migration was not recorded once';
  END IF;
END
$check$;
