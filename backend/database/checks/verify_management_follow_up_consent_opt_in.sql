\set ON_ERROR_STOP on

-- Slice 6BO structural contract.
--
-- This check deliberately names the private seams. 6BO has no runtime bridge:
-- a trusted management service consumes the private functions, while runtime,
-- PUBLIC, and report-family roles must not receive a direct path to this
-- configuration history.

DO $check$
DECLARE
  configuration_table regclass := to_regclass(
    'app_private.management_follow_up_consent_opt_in_versions'
  );
  configure_function regprocedure := to_regprocedure(
    'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'
  );
  read_function regprocedure := to_regprocedure(
    'app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)'
  );
  configure_definition text;
  read_definition text;
  validator_definition text;
  mutation_definition text;
  project_lock_definition text;
  project_lock_owner text;
  project_lock_security_definer boolean;
  project_lock_search_path text;
  configure_result text;
  read_result text;
  configuration_owner text;
  configuration_owner_oid oid;
  configure_owner text;
  read_owner text;
  configuration_rls boolean;
  configuration_force_rls boolean;
  configure_security_definer boolean;
  read_security_definer boolean;
  configure_volatility "char";
  read_volatility "char";
  configure_search_path text;
  read_search_path text;
  role_name text;
  private_function regprocedure;
  private_functions regprocedure[] := ARRAY[
    'app_private.reject_management_follow_up_consent_opt_in_mutation_v1()'::regprocedure,
    'app_private.validate_management_follow_up_consent_opt_in_v1()'::regprocedure,
    'app_private.lock_management_follow_up_consent_opt_in_project_status_v1()'::regprocedure,
    'app_private.management_follow_up_consent_opt_in_document_v1(uuid,integer)'::regprocedure,
    'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'::regprocedure,
    'app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)'::regprocedure
  ];
  forbidden_roles text[] := ARRAY[
    'public',
    'tongxingzhe_runtime',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer'
  ];
BEGIN
  IF configuration_table IS NULL THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in versions table is missing';
  END IF;

  IF configure_function IS NULL OR read_function IS NULL THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in private functions are missing';
  END IF;

  SELECT
    pg_get_function_result(function_row.oid),
    pg_get_functiondef(function_row.oid),
    owner_role.rolname,
    function_row.prosecdef,
    function_row.provolatile,
    replace(config_row.setting, ' ', '')
  INTO configure_result,
    configure_definition,
    configure_owner,
    configure_security_definer,
    configure_volatility,
    configure_search_path
  FROM pg_catalog.pg_proc AS function_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = function_row.proowner
  LEFT JOIN LATERAL (
    SELECT config_row.setting
    FROM unnest(coalesce(function_row.proconfig, ARRAY[]::text[]))
      AS config_row(setting)
    WHERE config_row.setting ILIKE 'search_path=%'
    LIMIT 1
  ) AS config_row ON true
  WHERE function_row.oid = configure_function;

  SELECT
    pg_get_function_result(function_row.oid),
    pg_get_functiondef(function_row.oid),
    owner_role.rolname,
    function_row.prosecdef,
    function_row.provolatile,
    replace(config_row.setting, ' ', '')
  INTO read_result,
    read_definition,
    read_owner,
    read_security_definer,
    read_volatility,
    read_search_path
  FROM pg_catalog.pg_proc AS function_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = function_row.proowner
  LEFT JOIN LATERAL (
    SELECT config_row.setting
    FROM unnest(coalesce(function_row.proconfig, ARRAY[]::text[]))
      AS config_row(setting)
    WHERE config_row.setting ILIKE 'search_path=%'
    LIMIT 1
  ) AS config_row ON true
  WHERE function_row.oid = read_function;

  SELECT owner_role.rolname
       , owner_role.oid
  INTO configuration_owner
    , configuration_owner_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = class_row.relowner
  WHERE class_row.oid = configuration_table;

  SELECT class_row.relrowsecurity, class_row.relforcerowsecurity
  INTO configuration_rls, configuration_force_rls
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = configuration_table;

  SELECT pg_get_functiondef(to_regprocedure(
    'app_private.validate_management_follow_up_consent_opt_in_v1()'
  )) INTO validator_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'app_private.reject_management_follow_up_consent_opt_in_mutation_v1()'
  )) INTO mutation_definition;

  SELECT pg_get_functiondef(trigger_row.tgfoid)
  INTO project_lock_definition
  FROM pg_catalog.pg_trigger AS trigger_row
  WHERE trigger_row.tgrelid = 'app_data.projects'::regclass
    AND NOT trigger_row.tgisinternal
    AND pg_get_triggerdef(trigger_row.oid) ILIKE '%BEFORE UPDATE%'
    AND pg_get_triggerdef(trigger_row.oid) ILIKE '%status%'
    AND pg_get_functiondef(trigger_row.tgfoid) ILIKE
      '%management-follow-up-consent-opt-in:%'
  LIMIT 1;

  SELECT
    owner_role.rolname,
    function_row.prosecdef,
    replace(config_row.setting, ' ', '')
  INTO
    project_lock_owner,
    project_lock_security_definer,
    project_lock_search_path
  FROM pg_catalog.pg_proc AS function_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = function_row.proowner
  LEFT JOIN LATERAL (
    SELECT config_row.setting
    FROM unnest(coalesce(function_row.proconfig, ARRAY[]::text[]))
      AS config_row(setting)
    WHERE config_row.setting ILIKE 'search_path=%'
    LIMIT 1
  ) AS config_row ON true
  WHERE function_row.oid = to_regprocedure(
    'app_private.lock_management_follow_up_consent_opt_in_project_status_v1()'
  );

  IF configure_result IS DISTINCT FROM 'jsonb'
    OR read_result IS DISTINCT FROM 'jsonb'
  THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in result contract drifted: %, %',
      configure_result,
      read_result;
  END IF;

  IF configuration_owner IS NULL
    OR configuration_owner <> 'tongxingzhe_management_follow_up_consent_config_writer'
    OR configure_owner IS NULL
    OR configure_owner <> configuration_owner
    OR read_owner IS NULL
    OR read_owner <> configuration_owner
    OR NOT configure_security_definer
    OR NOT read_security_definer
    OR configure_volatility <> 'v'
    OR read_volatility <> 'v'
    OR configure_search_path IS DISTINCT FROM 'search_path=pg_catalog,app_data'
    OR read_search_path IS DISTINCT FROM 'search_path=pg_catalog,app_data'
  THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in functions have an open owner boundary';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.oid = configuration_owner_oid
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
    WHERE membership.roleid = configuration_owner_oid
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in owner is not a closed NOLOGIN role';
  END IF;

  IF NOT configuration_rls OR NOT configuration_force_rls THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in history must use forced RLS';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = configuration_table
      AND policy_row.polcmd = '*'
      AND configuration_owner_oid = ANY(policy_row.polroles)
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in forced-RLS owner policy is missing';
  END IF;

  IF validator_definition IS NULL OR mutation_definition IS NULL THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in history triggers are incomplete';
  END IF;

  IF project_lock_definition IS NULL
    OR project_lock_owner IS DISTINCT FROM configuration_owner
    OR NOT project_lock_security_definer
    OR project_lock_search_path IS DISTINCT FROM 'search_path=pg_catalog'
    OR project_lock_definition !~* 'pg_advisory_xact_lock'
    OR project_lock_definition !~* 'hashtextextended'
    OR project_lock_definition !~* 'organization-membership:'
    OR project_lock_definition !~* 'project-membership:'
    OR project_lock_definition !~* 'management-report-capability:'
    OR project_lock_definition !~* 'release_management_reports'
    OR project_lock_definition !~*
      'ORDER[[:space:]]+BY[[:space:]]+organization_membership[[:space:]]*\.[[:space:]]*app_user_id'
    OR project_lock_definition !~* 'management-follow-up-consent-opt-in:'
    OR project_lock_definition !~* 'NEW[[:space:]]*\.[[:space:]]*project_id'
  THEN
    RAISE EXCEPTION
      'project status updates do not preserve the authorization-to-opt-in lock order';
  END IF;

  IF validator_definition !~* 'release_management_reports'
    OR validator_definition !~* 'organization_memberships'
    OR validator_definition !~* 'project_memberships'
    OR validator_definition !~* 'management_report_capability_grants'
    OR validator_definition !~* 'workspace_kind[^;]*organization'
    OR validator_definition !~* 'active'
    OR validator_definition !~* 'deleted_at IS NULL'
    OR validator_definition !~* 'authorization_reference_at_utc'
    OR validator_definition !~* 'expected_version'
    OR validator_definition !~* 'version chain'
  THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in validator omits authorization or version invariants';
  END IF;

  IF mutation_definition !~* 'immutable' THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in history is not append-only';
  END IF;

  IF configure_definition !~* 'pg_advisory_xact_lock'
    OR configure_definition !~* 'hashtextextended'
    OR configure_definition !~* 'resolve_management_report_authorization_v1'
    OR configure_definition !~* 'clock_timestamp'
    OR configure_definition !~* 'expected_version'
    OR configure_definition !~* 'idempotency'
    OR configure_definition !~* 'management-follow-up-consent-opt-in:'
    OR configure_definition !~* 'requested[[:space:]]*_[[:space:]]*project_id'
    OR read_definition !~* 'resolve_management_report_authorization_v1'
    OR read_definition !~* 'not_enabled'
    OR read_definition !~* 'configuration'
    OR read_definition ~* 'numerator|denominator|coverage|cells|protected_report'
    OR configure_definition ~* 'contacts|contact_(answers|attempts|audit_events|drafts|location_provenance|region_assignments|revisions|target_links)|promotion_targets|protected_report|management_report_snapshots'
    OR read_definition ~* 'contacts|contact_(answers|attempts|audit_events|drafts|location_provenance|region_assignments|revisions|target_links)|promotion_targets|protected_report|management_report_snapshots'
  THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in functions omit lock, reauthorization, or value-free state';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = configuration_table
      AND trigger_row.tgname =
        'management_follow_up_consent_opt_in_versions_validate'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = configuration_table
      AND trigger_row.tgname =
        'management_follow_up_consent_opt_in_versions_immutable'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in history triggers are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = configuration_table
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%follow_up_consent_ratio@1%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = configuration_table
      AND pg_get_constraintdef(constraint_row.oid) ~* 'expected_version'
      AND pg_get_constraintdef(constraint_row.oid) ~* 'version_number'
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in metric or version constraint is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = configuration_table
      AND index_row.indisunique
      AND index_row.indexrelid::regclass::text ILIKE
        '%management_follow_up_consent_opt_in%request%'
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in request id must be unique';
  END IF;

  FOREACH role_name IN ARRAY forbidden_roles LOOP
    IF role_name IN ('public', 'tongxingzhe_runtime')
      AND has_schema_privilege(role_name, 'app_private', 'USAGE')
    THEN
      RAISE EXCEPTION
        'forbidden role can use app_private schema: %', role_name;
    END IF;

    IF has_table_privilege(
      role_name,
      configuration_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) THEN
      RAISE EXCEPTION
        'forbidden role can access opt-in history table: %', role_name;
    END IF;

    IF has_function_privilege(
      role_name,
      configure_function,
      'EXECUTE'
    ) OR has_function_privilege(
      role_name,
      read_function,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION
        'forbidden role can execute opt-in private functions: %', role_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = class_row.relnamespace
    WHERE namespace_row.nspname = 'app_data'
      AND class_row.relname IN (
        'app_users',
        'workspaces',
        'projects',
        'organization_memberships',
        'project_memberships',
        'management_report_capability_grants'
      )
      AND has_table_privilege(
        configuration_owner_oid,
        class_row.oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      coalesce(
        class_row.relacl,
        pg_catalog.acldefault('r', class_row.relowner)
      )
    ) AS privilege_row
    WHERE class_row.oid = configuration_table
      AND privilege_row.grantee <> configuration_owner_oid
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      attribute_row.attacl
    ) AS privilege_row
    WHERE attribute_row.attrelid = configuration_table
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND privilege_row.grantee <> configuration_owner_oid
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in history has a non-owner ACL';
  END IF;

  FOREACH private_function IN ARRAY private_functions LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS function_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(
          function_row.proacl,
          pg_catalog.acldefault('f', function_row.proowner)
        )
      ) AS privilege_row
      WHERE function_row.oid = private_function
        AND privilege_row.grantee <> configuration_owner_oid
    ) THEN
      RAISE EXCEPTION
        'management follow-up consent opt-in function has a non-owner ACL: %',
        private_function;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = class_row.relnamespace
    JOIN pg_catalog.pg_attribute AS attribute_row
      ON attribute_row.attrelid = class_row.oid
    WHERE namespace_row.nspname = 'app_data'
      AND class_row.relname IN (
        'app_users',
        'workspaces',
        'projects',
        'organization_memberships',
        'project_memberships',
        'management_report_capability_grants'
      )
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND has_column_privilege(
        configuration_owner_oid,
        class_row.oid,
        attribute_row.attnum,
        'SELECT'
      ) IS DISTINCT FROM CASE class_row.relname
        WHEN 'app_users' THEN attribute_row.attname IN (
          'app_user_id', 'status'
        )
        WHEN 'workspaces' THEN attribute_row.attname IN (
          'workspace_id', 'workspace_kind', 'deleted_at'
        )
        WHEN 'projects' THEN attribute_row.attname IN (
          'project_id', 'workspace_id', 'status'
        )
        WHEN 'organization_memberships' THEN attribute_row.attname IN (
          'organization_membership_id', 'organization_workspace_id',
          'app_user_id', 'active_from_utc', 'inactive_from_utc'
        )
        WHEN 'project_memberships' THEN attribute_row.attname IN (
          'project_membership_id', 'organization_membership_id', 'project_id',
          'active_from_utc', 'inactive_from_utc'
        )
        WHEN 'management_report_capability_grants' THEN
          attribute_row.attname IN (
            'capability_grant_id', 'project_membership_id', 'capability_id',
            'active_from_utc', 'inactive_from_utc'
          )
        ELSE false
      END
  ) THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in app_data column ACL drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0073_management_follow_up_consent_opt_in'
  ) <> 1 THEN
    RAISE EXCEPTION
      'management follow-up consent opt-in migration was not recorded once';
  END IF;
END
$check$;
