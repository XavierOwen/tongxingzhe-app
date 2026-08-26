\set ON_ERROR_STOP on

-- Structural and least-privilege checks for the Slice 6BP private candidate.
-- Behavioural source and privacy cases belong to the 0074 fixture.
DO $check$
DECLARE
  candidate_role_oid oid;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_result text;
  function_search_path text[];
  function_volatility "char";
  function_security_definer boolean;
  expected_volatility "char";
  expected_search_path text[];
  definition_count integer;
  canonical_document jsonb;
  configuration_position integer;
  not_enabled_position integer;
  contacts_position integer;
  links_position integer;
  role_name text;
  source_table regclass;
  allowed_columns text[];
  column_name text;
  canonicalizer regprocedure := to_regprocedure(
    'app_private.canonicalize_management_follow_up_consent_ratio_request_v1(jsonb)'
  );
  opt_in_helper regprocedure := to_regprocedure(
    'app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(uuid,uuid,text)'
  );
  protector regprocedure := to_regprocedure(
    'app_private.protect_management_follow_up_consent_ratio_periods_v1(jsonb)'
  );
  executor regprocedure := to_regprocedure(
    'app_private.execute_management_follow_up_consent_ratio_report_v1(uuid,uuid,text,timestamp with time zone)'
  );
BEGIN
  SELECT role_row.oid
  INTO candidate_role_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname =
    'tongxingzhe_management_follow_up_consent_ratio_reader';

  IF candidate_role_oid IS NULL
    OR canonicalizer IS NULL
    OR opt_in_helper IS NULL
    OR protector IS NULL
    OR executor IS NULL
  THEN
    RAISE EXCEPTION
      'management follow-up consent ratio candidate seam is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.oid = candidate_role_oid
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
    WHERE membership.roleid = candidate_role_oid
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent ratio reader is not closed';
  END IF;

  SELECT
    owner_role.rolname,
    pg_get_function_result(procedure_row.oid),
    procedure_row.proconfig,
    procedure_row.provolatile,
    procedure_row.prosecdef
  INTO
    function_owner,
    function_result,
    function_search_path,
    function_volatility,
    function_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = opt_in_helper;

  IF function_owner <>
      'tongxingzhe_management_follow_up_consent_config_writer'
    OR function_result <> 'jsonb'
    OR function_search_path IS DISTINCT FROM
      ARRAY['search_path=pg_catalog, app_private']::text[]
    OR function_volatility <> 'v'
    OR NOT function_security_definer
    OR has_function_privilege('public', opt_in_helper, 'EXECUTE')
    OR NOT has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      opt_in_helper,
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION
      'management follow-up consent ratio opt-in helper contract drifted';
  END IF;

  FOR function_name IN
    SELECT unnest(ARRAY[canonicalizer, protector, executor])
  LOOP
    SELECT
      pg_get_functiondef(procedure_row.oid),
      owner_role.rolname,
      pg_get_function_result(procedure_row.oid),
      procedure_row.proconfig,
      procedure_row.provolatile,
      procedure_row.prosecdef
    INTO
      function_definition,
      function_owner,
      function_result,
      function_search_path,
      function_volatility,
      function_security_definer
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = function_name;

    IF function_name = canonicalizer THEN
      expected_volatility := 's';
      expected_search_path :=
        ARRAY['search_path=pg_catalog, app_private']::text[];
    ELSIF function_name = protector THEN
      expected_volatility := 'i';
      expected_search_path := ARRAY['search_path=pg_catalog']::text[];
    ELSE
      expected_volatility := 'v';
      expected_search_path :=
        ARRAY['search_path=pg_catalog, app_data, app_private']::text[];
    END IF;

    IF function_owner <>
        'tongxingzhe_management_follow_up_consent_ratio_reader'
      OR function_result <> 'jsonb'
      OR NOT function_security_definer
      OR function_volatility <> expected_volatility
      OR function_search_path IS DISTINCT FROM expected_search_path
    THEN
      RAISE EXCEPTION
        'management follow-up consent ratio function contract drifted: %',
        function_name;
    END IF;

    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR NOT has_function_privilege(
        'tongxingzhe_management_follow_up_consent_ratio_reader',
        function_name,
        'EXECUTE'
      )
    THEN
      RAISE EXCEPTION
        'management follow-up consent ratio function ACL is unsafe: %',
        function_name;
    END IF;
  END LOOP;

  SELECT count(*)
  INTO definition_count
  FROM app_private.management_report_definitions AS definition
  WHERE definition.report_id =
      'contact_target_follow_up_consent_ratio_two_periods'
    AND definition.report_version = 1
    AND definition.metric_id = 'follow_up_consent_ratio'
    AND definition.metric_version = 1
    AND definition.dimension_key = 'consent_state'
    AND definition.period_grain = 'week'
    AND definition.comparison_period_count = 2
    AND definition.period_boundary_id = 'iso_week_monday_v1'
    AND definition.privacy_policy =
      'management_follow_up_consent_ratio_privacy_v1'
    AND definition.required_capability = 'release_management_reports'
    AND definition.query_fingerprint =
      'management-report:contact_target_follow_up_consent_ratio_two_periods:v1';
  IF definition_count <> 1 THEN
    RAISE EXCEPTION
      'management follow-up consent ratio definition is not fixed once';
  END IF;

  canonical_document :=
    app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
      jsonb_build_object(
        'report_id',
          'contact_target_follow_up_consent_ratio_two_periods',
        'report_version', 1
      )
    );
  IF canonical_document <> jsonb_build_object(
    'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
    'report_version', 1,
    'metric_id', 'follow_up_consent_ratio',
    'metric_version', 1,
    'statistical_unit', 'contact_target_link',
    'dimension', 'consent_state',
    'period_grain', 'week',
    'comparison_period_count', 2,
    'period_boundary_id', 'iso_week_monday_v1',
    'privacy_policy', 'management_follow_up_consent_ratio_privacy_v1',
    'required_capability', 'release_management_reports',
    'query_fingerprint',
      'management-report:contact_target_follow_up_consent_ratio_two_periods:v1'
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent ratio canonical document drifted';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = protector;
  FOREACH role_name IN ARRAY ARRAY[
    'period_key',
    'consent_state',
    'contributor_key',
    'unit_count',
    'previous',
    'current',
    'yes',
    'no',
    'unanswered',
    'refused',
    'not_applicable',
    'unit_count >= 10',
    'contributor_count >= 3',
    'max_contribution',
    'percentage_basis_points',
    'privacy_status',
    'suppressed',
    '9007199254740991',
    'count(*) > 1'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || role_name || '%' THEN
      RAISE EXCEPTION
        'management follow-up consent ratio privacy policy omits %',
        role_name;
    END IF;
  END LOOP;
  IF function_definition NOT ILIKE '%item - ARRAY%'
    OR function_definition NOT ILIKE '%jsonb_typeof%'
  THEN
    RAISE EXCEPTION
      'management follow-up consent ratio privacy input is not strict';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = executor;
  configuration_position := position(
    'read_management_follow_up_consent_opt_in_for_candidate_v1'
      IN lower(function_definition)
  );
  not_enabled_position := position(
    '''status'', ''not_enabled''' IN lower(function_definition)
  );
  contacts_position := position(
    'app_data.contacts' IN lower(function_definition)
  );
  links_position := position(
    'app_data.contact_target_links' IN lower(function_definition)
  );
  FOREACH role_name IN ARRAY ARRAY[
    'resolve_management_report_periods_v1',
    'contact_target_follow_up_consent_ratio_two_periods',
    'management_follow_up_consent_ratio_candidate_v1',
    'backend_accepted_active_contact_target_links_current_revision',
    'current_revision',
    'first_submitted_at_utc',
    'lifecycle_status',
    'occurred_at_utc',
    'follow_up_consent',
    'protect_management_follow_up_consent_ratio_periods_v1'
  ]
  LOOP
    IF function_definition NOT ILIKE '%' || role_name || '%' THEN
      RAISE EXCEPTION
        'management follow-up consent ratio executor omits %',
        role_name;
    END IF;
  END LOOP;
  IF configuration_position = 0
    OR not_enabled_position = 0
    OR contacts_position = 0
    OR links_position = 0
    OR configuration_position >= not_enabled_position
    OR not_enabled_position >= contacts_position
    OR contacts_position >= links_position
    OR function_definition ILIKE '%recorded_at_utc%'
    OR function_definition ILIKE '%promotion_targets%'
    OR function_definition ILIKE '%questionnaire_answers%'
  THEN
    RAISE EXCEPTION
      'management follow-up consent ratio executor scope or short circuit drifted';
  END IF;

  IF NOT has_schema_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_data',
      'USAGE'
    )
    OR NOT has_schema_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private',
      'USAGE'
    )
    OR NOT has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      opt_in_helper,
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)',
      'EXECUTE'
    )
    OR NOT has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private.resolve_management_report_periods_v1(text,timestamp with time zone)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)',
      'EXECUTE'
    )
    OR has_table_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private.management_follow_up_consent_opt_in_versions',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION
      'management follow-up consent ratio supporting ACL is unsafe';
  END IF;

  FOR source_table, allowed_columns IN
    SELECT *
    FROM (
      VALUES
        (
          'app_private.management_report_definitions'::regclass,
          ARRAY[
            'report_id',
            'report_version',
            'metric_id',
            'metric_version',
            'dimension_key',
            'period_grain',
            'comparison_period_count',
            'period_boundary_id',
            'privacy_policy',
            'required_capability',
            'query_fingerprint'
          ]::text[]
        ),
        (
          'app_data.app_users'::regclass,
          ARRAY['app_user_id', 'status']::text[]
        ),
        (
          'app_data.workspaces'::regclass,
          ARRAY['workspace_id', 'workspace_kind', 'deleted_at']::text[]
        ),
        (
          'app_data.projects'::regclass,
          ARRAY['project_id', 'workspace_id', 'status']::text[]
        ),
        (
          'app_data.organization_memberships'::regclass,
          ARRAY[
            'organization_membership_id',
            'organization_workspace_id',
            'app_user_id',
            'active_from_utc',
            'inactive_from_utc'
          ]::text[]
        ),
        (
          'app_data.project_memberships'::regclass,
          ARRAY[
            'project_membership_id',
            'organization_membership_id',
            'project_id',
            'active_from_utc',
            'inactive_from_utc'
          ]::text[]
        ),
        (
          'app_data.management_report_capability_grants'::regclass,
          ARRAY[
            'capability_grant_id',
            'project_membership_id',
            'capability_id',
            'active_from_utc',
            'inactive_from_utc'
          ]::text[]
        ),
        (
          'app_data.contacts'::regclass,
          ARRAY[
            'contact_id',
            'app_user_id',
            'workspace_id',
            'project_id',
            'occurred_at_utc',
            'first_submitted_at_utc',
            'lifecycle_status',
            'current_revision'
          ]::text[]
        ),
        (
          'app_data.contact_target_links'::regclass,
          ARRAY[
            'contact_id',
            'revision_number',
            'follow_up_consent'
          ]::text[]
        )
    ) AS expected(table_name, columns)
  LOOP
    IF has_table_privilege(
        'tongxingzhe_management_follow_up_consent_ratio_reader',
        source_table,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION
        'management follow-up consent ratio reader has table privilege on %',
        source_table;
    END IF;

    FOR column_name IN
      SELECT attribute.attname
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = source_table
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    LOOP
      IF has_column_privilege(
          'tongxingzhe_management_follow_up_consent_ratio_reader',
          source_table,
          column_name,
          'SELECT'
        ) IS DISTINCT FROM (column_name = ANY(allowed_columns))
      THEN
        RAISE EXCEPTION
          'management follow-up consent ratio column ACL drifted: %.%',
          source_table,
          column_name;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer'
  ]
  LOOP
    IF has_function_privilege(role_name, canonicalizer, 'EXECUTE')
      OR has_function_privilege(role_name, executor, 'EXECUTE')
      OR has_function_privilege(role_name, protector, 'EXECUTE')
      OR (
        role_name <>
          'tongxingzhe_management_follow_up_consent_config_writer'
        AND has_function_privilege(role_name, opt_in_helper, 'EXECUTE')
      )
      OR (
        role_name = 'tongxingzhe_runtime'
        AND has_schema_privilege(role_name, 'app_private', 'USAGE')
      )
    THEN
      RAISE EXCEPTION
        'management follow-up consent ratio private contract leaked to %',
        role_name;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0074_management_follow_up_consent_ratio'
  ) <> 1 THEN
    RAISE EXCEPTION
      'management follow-up consent ratio migration was not recorded once';
  END IF;
END
$check$;
