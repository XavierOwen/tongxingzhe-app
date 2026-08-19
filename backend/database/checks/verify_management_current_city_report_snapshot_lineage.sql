\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6AO. Behavioural
-- document, release and idempotency cases belong to fixture 0057; the
-- independent concurrency script covers the transaction lock ordering.
DO $check$
DECLARE
  writer_oid oid;
  claims_table_oid oid;
  function_row record;
  function_name regprocedure;
  claim_function_name regprocedure;
  function_definition text;
  constraint_definition text;
  function_owner text;
  function_config text[];
  expected_function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  role_name text;
BEGIN
  SELECT role_row.oid
  INTO writer_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname =
    'tongxingzhe_management_current_city_snapshot_release_writer';
  IF writer_oid IS NULL THEN
    RAISE EXCEPTION 'current city snapshot release writer role is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname =
        'tongxingzhe_management_current_city_snapshot_release_writer'
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
    RAISE EXCEPTION
      'current city snapshot release writer is login-enabled or has members';
  END IF;

  IF to_regclass(
      'app_private.management_current_city_report_release_attempts'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'current city release attempt table is missing';
  END IF;

  SELECT class_row.oid
  INTO claims_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_release_request_claims'
    AND class_row.relkind IN ('r', 'p');

  IF claims_table_oid IS NULL THEN
    RAISE EXCEPTION 'management report release request claim ledger is missing';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_attribute AS column_row
    WHERE column_row.attrelid = claims_table_oid
      AND column_row.attnum > 0
      AND NOT column_row.attisdropped
  ) <> 2
  OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS column_row
    WHERE column_row.attrelid = claims_table_oid
      AND column_row.attnum = 1
      AND column_row.attname = 'release_request_id'
      AND column_row.atttypid = 'uuid'::regtype
      AND column_row.attnotnull
  )
  OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS column_row
    WHERE column_row.attrelid = claims_table_oid
      AND column_row.attnum = 2
      AND column_row.attname = 'release_family_id'
      AND column_row.atttypid = 'text'::regtype
      AND column_row.attnotnull
  )
  OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table_oid
      AND constraint_row.contype = 'p'
      AND constraint_row.conkey = ARRAY[1::smallint]
  )
  OR (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table_oid
      AND constraint_row.contype = 'c'
      AND constraint_row.convalidated
  ) <> 1
  THEN
    RAISE EXCEPTION
      'management report release request claim ledger must be exactly two columns with a request primary key';
  END IF;

  SELECT pg_get_constraintdef(constraint_row.oid)
  INTO constraint_definition
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.conrelid = claims_table_oid
    AND constraint_row.contype = 'c';
  IF constraint_definition IS NULL
    OR constraint_definition NOT ILIKE
      '%channel_management_report_snapshot_release%'
    OR constraint_definition NOT ILIKE
      '%current_city_management_report_snapshot_release%'
  THEN
    RAISE EXCEPTION
      'management report release request claim family constraint is too broad';
  END IF;

  claim_function_name = to_regprocedure(
    'app_private.claim_management_report_release_request_v1()'
  );
  IF claim_function_name IS NULL THEN
    RAISE EXCEPTION 'management report release request claim function is missing';
  END IF;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO
    function_definition,
    function_security_definer,
    function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = claim_function_name;
  IF NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
  THEN
    RAISE EXCEPTION
      'management report release request claim function security contract is incorrect';
  END IF;

  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer'
  ]::text[]
  LOOP
    IF has_function_privilege(role_name, claim_function_name, 'EXECUTE') THEN
      RAISE EXCEPTION
        'management report release request claim function is executable by %',
        role_name;
    END IF;
  END LOOP;
  IF has_function_privilege('public', claim_function_name, 'EXECUTE') THEN
    RAISE EXCEPTION
      'management report release request claim function is executable by PUBLIC';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
        'app_private.management_report_release_attempts'::regclass
      AND trigger_row.tgname = 'management_report_release_request_claim'
      AND NOT trigger_row.tgisinternal
      AND pg_get_triggerdef(trigger_row.oid) ILIKE
        '%BEFORE INSERT%claim_management_report_release_request_v1(''management_report_snapshot_release_v1'')%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
        'app_private.management_report_release_v2_attempts'::regclass
      AND trigger_row.tgname = 'management_report_release_v2_request_claim'
      AND NOT trigger_row.tgisinternal
      AND pg_get_triggerdef(trigger_row.oid) ILIKE
        '%BEFORE INSERT%claim_management_report_release_request_v1(''trusted_management_report_snapshot_release_v2'')%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
        'app_private.management_current_city_report_release_attempts'::regclass
      AND trigger_row.tgname = 'management_current_city_release_request_claim'
      AND NOT trigger_row.tgisinternal
      AND pg_get_triggerdef(trigger_row.oid) ILIKE
        '%BEFORE INSERT%claim_management_report_release_request_v1(''current_city_management_report_snapshot_release_v1'')%'
  ) THEN
    RAISE EXCEPTION
      'management report release request claim triggers or contract arguments are incorrect';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
        'app_private.management_report_release_request_claims'::regclass
      AND trigger_row.tgname = 'management_report_release_request_claims_immutable'
      AND NOT trigger_row.tgisinternal
      AND (trigger_row.tgtype & 1) = 1
      AND (trigger_row.tgtype & 2) = 2
      AND (trigger_row.tgtype & 8) = 8
      AND (trigger_row.tgtype & 16) = 16
      AND trigger_row.tgfoid = to_regprocedure(
        'app_private.reject_management_report_history_mutation()'
      )
  ) THEN
    RAISE EXCEPTION
      'management report release request claim ledger is mutable';
  END IF;

  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer'
  ]::text[]
  LOOP
    IF has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'SELECT'
      )
      OR has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'INSERT'
      )
      OR has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'UPDATE'
      )
      OR has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'DELETE'
      )
      OR has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'TRUNCATE'
      )
      OR has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'REFERENCES'
      )
      OR has_table_privilege(
        role_name,
        'app_private.management_report_release_request_claims',
        'TRIGGER'
      )
    THEN
      RAISE EXCEPTION
        'management report release request claim ledger has a direct privilege for %',
        role_name;
    END IF;
  END LOOP;
  IF has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'SELECT'
    )
    OR has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'INSERT'
    )
    OR has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'UPDATE'
    )
    OR has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'DELETE'
    )
    OR has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'TRUNCATE'
    )
    OR has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'REFERENCES'
    )
    OR has_table_privilege(
      'public',
      'app_private.management_report_release_request_claims',
      'TRIGGER'
    )
  THEN
    RAISE EXCEPTION
      'management report release request claim ledger is open to PUBLIC';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_current_city_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_current_city_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.validate_management_report_snapshot_insert_v2()'
    ),
    to_regprocedure(
      'app_private.validate_current_city_release_attempt_insert_v1()'
    ),
    to_regprocedure(
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)'
    ),
    to_regprocedure(
      'app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'one or more current city snapshot functions are missing';
    END IF;
  END LOOP;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_current_city_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_current_city_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name = to_regprocedure(
      'app_private.validate_management_current_city_report_document_v1(jsonb)'
    ) THEN
      expected_function_config = ARRAY[
        'search_path=pg_catalog, app_data, app_private'
      ]::text[];
    ELSIF function_name = to_regprocedure(
      'app_private.assess_management_current_city_report_pair_release_v1(jsonb,jsonb)'
    ) THEN
      expected_function_config = ARRAY[
        'search_path=pg_catalog, app_private'
      ]::text[];
    ELSE
      expected_function_config = ARRAY[
        'search_path=pg_catalog, app_private, app_data'
      ]::text[];
    END IF;

    SELECT
      pg_get_functiondef(procedure_row.oid),
      owner_role.rolname,
      procedure_row.proconfig,
      procedure_row.provolatile,
      procedure_row.prosecdef
    INTO
      function_definition,
      function_owner,
      function_config,
      function_volatility,
      function_security_definer
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = function_name;

    IF function_owner <>
      'tongxingzhe_management_current_city_snapshot_release_writer'
      OR NOT function_security_definer
      OR function_config IS DISTINCT FROM expected_function_config
    THEN
      RAISE EXCEPTION 'current city release function security contract is incorrect: %',
        function_name;
    END IF;

    IF function_name::text LIKE '%release_management_current_city%' THEN
      IF function_volatility <> 'v' THEN
        RAISE EXCEPTION 'current city release must be VOLATILE: %', function_name;
      END IF;
    ELSE
      IF function_volatility <> 's' THEN
        RAISE EXCEPTION 'current city validator/assessment must be STABLE: %',
          function_name;
      END IF;
    END IF;

    IF function_definition IS NULL THEN
      RAISE EXCEPTION 'current city function definition is unavailable: %',
        function_name;
    END IF;
  END LOOP;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO
    function_definition,
    function_security_definer,
    function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_report_snapshot_insert_v2()'
  );
  IF NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR function_definition NOT ILIKE
      '%validate_management_report_document_v1%'
    OR function_definition NOT ILIKE
      '%validate_management_current_city_report_document_v1%'
    OR function_definition NOT ILIKE '%source_change_sequence%'
  THEN
    RAISE EXCEPTION 'snapshot validator dispatcher contract is incorrect';
  END IF;

  SELECT
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO
    function_security_definer,
    function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_current_city_release_attempt_insert_v1()'
  );
  IF NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private, app_data'
    ]::text[]
  THEN
    RAISE EXCEPTION
      'current city release attempt trigger validator security contract is incorrect';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_current_city_report_document_v1(jsonb)'
  );
  IF function_definition IS NULL
    OR function_definition NOT ILIKE
      '%app_private.resolve_management_report_periods_v1%'
    OR function_definition NOT ILIKE
      '%app_private.resolve_management_current_city_target_context_v1%'
    OR function_definition NOT ILIKE '%WITH ORDINALITY%'
    OR function_definition NOT ILIKE '%element.ordinality - 1%'
    OR function_definition NOT ILIKE '%cell_order%'
  THEN
    RAISE EXCEPTION
      'current city document validator does not bind exact periods, target or physical cell order';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_current_city_release_attempt_insert_v1()'
  );
  IF function_definition NOT ILIKE
      '%jsonb_array_elements(NEW.reason_codes)%'
    OR function_definition NOT ILIKE '%DISTINCT reason.code%'
    OR function_definition NOT ILIKE
      '%release_lineage_missing_current_city_provenance%'
    OR function_definition NOT ILIKE '%release_time_zone_revision_changed%'
    OR function_definition NOT ILIKE '%release_lineage_context_changed%'
    OR function_definition NOT ILIKE '%release_target_context_unavailable%'
    OR function_definition NOT ILIKE '%release_cutoff_not_advanced%'
    OR function_definition NOT ILIKE '%release_source_watermark_regressed%'
    OR function_definition NOT ILIKE '%release_target_context_changed%'
    OR function_definition NOT ILIKE '%no_shared_period%'
    OR function_definition NOT ILIKE '%shared_cell_privacy_status_changed%'
    OR function_definition NOT ILIKE '%shared_displayed_value_changed%'
  THEN
    RAISE EXCEPTION
      'current city release attempt reason-code storage allowlist is incomplete';
  END IF;

  SELECT
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile
  INTO
    function_security_definer,
    function_config,
    function_volatility
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)'
  );
  IF NOT function_security_definer
    OR function_volatility <> 'v'
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
  THEN
    RAISE EXCEPTION
      'current city authorization wrapper security contract is incorrect';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid = 'app_private.management_report_snapshots'::regclass
      AND tgname = 'management_report_snapshots_validate_insert'
      AND NOT tgisinternal
      AND pg_get_triggerdef(oid) ILIKE
        '%validate_management_report_snapshot_insert_v2%'
  ) THEN
    RAISE EXCEPTION 'snapshot validator dispatcher trigger is missing';
  END IF;

  IF has_function_privilege(
      'public',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_region_report_reader',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_region_publisher',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_region_mapping_writer',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_contact_provenance_writer',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_region_attribution_reader',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR NOT has_function_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_private.resolve_management_current_city_release_authorization_v1(uuid,uuid)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION
      'current city authorization wrapper privilege matrix is incorrect';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.resolve_management_report_periods_v1(text,timestamp with time zone)'
    ),
    to_regprocedure(
      'app_private.resolve_management_current_city_target_context_v1(timestamp with time zone)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name IS NULL
      OR NOT has_function_privilege(
        'tongxingzhe_management_current_city_snapshot_release_writer',
        function_name,
        'EXECUTE'
      )
    THEN
      RAISE EXCEPTION
        'current city release writer lacks an exact resolver capability: %',
        function_name;
    END IF;

    IF has_function_privilege('public', function_name, 'EXECUTE') THEN
      RAISE EXCEPTION
        'exact current city resolver is executable by PUBLIC: %', function_name;
    END IF;

    FOREACH role_name IN ARRAY ARRAY[
      'tongxingzhe_runtime',
      'tongxingzhe_region_publisher',
      'tongxingzhe_region_mapping_writer',
      'tongxingzhe_contact_provenance_writer'
    ]::text[]
    LOOP
      IF has_function_privilege(role_name, function_name, 'EXECUTE') THEN
        RAISE EXCEPTION
          'exact current city resolver is executable by %: %',
          role_name,
          function_name;
      END IF;
    END LOOP;
  END LOOP;

  IF has_schema_privilege(
      'tongxingzhe_runtime', 'app_private', 'USAGE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_current_city_report_release_attempts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass current city snapshot release';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_private'
      AND table_name = 'management_current_city_report_release_attempts'
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime',
        'tongxingzhe_region_publisher',
        'tongxingzhe_region_mapping_writer',
        'tongxingzhe_contact_provenance_writer',
        'tongxingzhe_region_attribution_reader',
        'tongxingzhe_management_region_report_reader')
  ) THEN
    RAISE EXCEPTION 'current city release attempt table privilege matrix is open';
  END IF;

  IF NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_releases',
      'tree_version', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_releases',
      'lifecycle_state', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_releases',
      'published_at_utc', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_releases',
      'content_fingerprint', 'SELECT'
    )
    OR has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_releases',
      'is_current', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_versions',
      'region_id', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_versions',
      'tree_version', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_versions',
      'parent_region_id', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_versions',
      'kind', 'SELECT'
    )
    OR has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_versions',
      'canonical_name', 'SELECT'
    )
    OR has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_versions',
      'attributes', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'selection_sequence', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'selected_tree_version', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'previous_tree_version', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'selected_at_utc', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'recorded_at_utc', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'selection_source', 'SELECT'
    )
    OR NOT has_column_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_data.canonical_region_tree_current_selections',
      'content_fingerprint', 'SELECT'
    )
  THEN
    RAISE EXCEPTION
      'current city release writer column-level region read contract is incorrect';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_current_city_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_current_city_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_region_publisher', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_region_mapping_writer', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_contact_provenance_writer', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_region_attribution_reader', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_management_region_report_reader', function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'current city release function has an over-broad EXECUTE grant: %',
        function_name;
    END IF;
    IF NOT has_function_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      function_name,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'release writer lacks current city function execution: %',
        function_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid =
        'app_private.management_current_city_report_release_attempts'::regclass
      AND tgname = 'management_current_city_release_attempts_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger
    WHERE tgrelid =
        'app_private.management_current_city_report_release_attempts'::regclass
      AND tgname = 'management_current_city_release_attempts_validate_insert'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'current city release attempt history is not protected';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid =
        'app_private.management_current_city_report_release_attempts'::regclass
      AND confrelid =
        'app_private.management_report_snapshots'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid =
        'app_private.management_current_city_report_release_attempts'::regclass
      AND confrelid =
        'app_private.project_reporting_time_zone_versions'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'current city release lineage foreign keys are incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = to_regprocedure(
      'app_private.validate_management_report_document_v1(jsonb)'
    )
      AND pg_get_functiondef(procedure_row.oid) ILIKE
        '%contact_sessions_by_current_city_two_periods%'
  ) THEN
    RAISE EXCEPTION 'historical channel validator was widened for current city';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0057_management_current_city_report_snapshot_lineage'
  ) <> 1 THEN
    RAISE EXCEPTION 'current city snapshot lineage migration was not recorded once';
  END IF;
END
$check$;
