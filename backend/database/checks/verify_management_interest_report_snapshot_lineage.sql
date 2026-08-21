\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6AW. Behavioural
-- document, release and idempotency cases belong to fixture 0062; the
-- independent concurrency script covers the transaction lock ordering.
DO $check$
DECLARE
  writer_oid oid;
  claims_table_oid oid;
  attempts_table_oid oid;
  snapshots_table_oid oid;
  claim_function_name regprocedure;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  constraint_definition text;
  role_name text;
BEGIN
  SELECT role_row.oid
  INTO writer_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname =
    'tongxingzhe_management_interest_snapshot_release_writer';
  IF writer_oid IS NULL THEN
    RAISE EXCEPTION 'management interest snapshot release writer role is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname =
        'tongxingzhe_management_interest_snapshot_release_writer'
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
    WHERE membership.roleid = writer_oid
  ) THEN
    RAISE EXCEPTION
      'management interest snapshot release writer is login-enabled or has members';
  END IF;

  SELECT class_row.oid
  INTO attempts_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_interest_report_release_attempts'
    AND class_row.relkind IN ('r', 'p');
  IF attempts_table_oid IS NULL THEN
    RAISE EXCEPTION 'management interest report release attempt table is missing';
  END IF;

  SELECT class_row.oid
  INTO snapshots_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_snapshots'
    AND class_row.relkind IN ('r', 'p');
  IF snapshots_table_oid IS NULL OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = snapshots_table_oid
      AND class_row.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'shared management report snapshots do not enforce writer row scope';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = snapshots_table_oid
      AND policy_row.polname =
        'management_current_city_snapshot_release_writer_scope'
      AND policy_row.polroles = ARRAY[
        'tongxingzhe_management_current_city_snapshot_release_writer'::regrole::oid
      ]
      AND pg_catalog.pg_get_expr(
        policy_row.polqual,
        policy_row.polrelid
      ) ILIKE '%contact_sessions_by_current_city_two_periods%'
      AND pg_catalog.pg_get_expr(
        policy_row.polwithcheck,
        policy_row.polrelid
      ) ILIKE '%management-region-report:%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = snapshots_table_oid
      AND policy_row.polname =
        'management_interest_snapshot_release_writer_scope'
      AND policy_row.polroles = ARRAY[
        'tongxingzhe_management_interest_snapshot_release_writer'::regrole::oid
      ]
      AND pg_catalog.pg_get_expr(
        policy_row.polqual,
        policy_row.polrelid
      ) ILIKE '%contact_sessions_by_interest_level_two_periods%'
      AND pg_catalog.pg_get_expr(
        policy_row.polwithcheck,
        policy_row.polrelid
      ) ILIKE '%management-interest-report:%'
  ) THEN
    RAISE EXCEPTION 'shared snapshot writer policies are incomplete';
  END IF;

  -- The dedicated attempt table must retain the authorization and lineage
  -- evidence, but never a candidate report document or source identities.
  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer'
  ]::text[]
  LOOP
    IF has_table_privilege(
        role_name,
        'app_private.management_interest_report_release_attempts',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      ) THEN
      RAISE EXCEPTION
        'management interest release attempt table has a direct privilege for %',
        role_name;
    END IF;
  END LOOP;
  IF has_table_privilege(
      'public',
      'app_private.management_interest_report_release_attempts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) THEN
    RAISE EXCEPTION
      'management interest release attempt table is open to PUBLIC';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_table_oid
      AND trigger_row.tgname =
        'management_interest_report_release_attempts_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_table_oid
      AND trigger_row.tgname =
        'management_interest_report_release_attempts_validate_insert'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'management interest release attempt history is not protected';
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
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table_oid
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE
        '%release_family_id%'
  ) <> 1
  OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table_oid
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE
        '%release_family_id%'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE
        '%channel_management_report_snapshot_release%'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE
        '%current_city_management_report_snapshot_release%'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE
        '%interest_management_report_snapshot_release%'
  )
  THEN
    RAISE EXCEPTION 'management report release request claim family is incomplete';
  END IF;

  IF NOT has_table_privilege(
      'tongxingzhe_management_interest_snapshot_release_writer',
      claims_table_oid,
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_management_interest_snapshot_release_writer',
      claims_table_oid,
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION
      'management interest release writer claim-ledger privileges are not minimal';
  END IF;

  claim_function_name = to_regprocedure(
    'app_private.claim_management_report_release_request_v1()'
  );
  SELECT
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO
    function_security_definer,
    function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = claim_function_name;
  IF claim_function_name IS NULL
    OR NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR has_function_privilege(
      'tongxingzhe_management_interest_snapshot_release_writer',
      claim_function_name,
      'EXECUTE'
    )
    OR has_function_privilege('public', claim_function_name, 'EXECUTE')
  THEN
    RAISE EXCEPTION
      'management report request-claim trigger security contract is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_table_oid
      AND trigger_row.tgname =
        'management_interest_report_release_request_claim'
      AND NOT trigger_row.tgisinternal
      AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ILIKE
        '%BEFORE INSERT%claim_management_report_release_request_v1(''interest_management_report_snapshot_release_v1'')%'
  ) THEN
    RAISE EXCEPTION
      'management interest request-claim trigger contract is incomplete';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_interest_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.validate_management_interest_report_release_attempt_insert_v1()'
    ),
    to_regprocedure(
      'app_private.resolve_management_interest_release_authorization_v1(uuid,uuid)'
    ),
    to_regprocedure(
      'app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'one or more management interest snapshot functions are missing';
    END IF;
  END LOOP;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_interest_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
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
        'tongxingzhe_management_interest_snapshot_release_writer'
      OR NOT function_security_definer
    THEN
      RAISE EXCEPTION
        'management interest snapshot function owner/security contract is incorrect: %',
        function_name;
    END IF;

    IF function_name = to_regprocedure(
        'app_private.validate_management_interest_report_document_v1(jsonb)'
      )
    THEN
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_data, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'management interest document validator security contract is incorrect';
      END IF;
    ELSIF function_name = to_regprocedure(
        'app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)'
      )
    THEN
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'management interest pair assessor security contract is incorrect';
      END IF;
    ELSE
      IF function_volatility <> 'v'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private, app_data'
        ]::text[]
      THEN
        RAISE EXCEPTION 'management interest release security contract is incorrect';
      END IF;
    END IF;

    IF function_definition IS NULL THEN
      RAISE EXCEPTION
        'management interest snapshot function definition is unavailable: %',
        function_name;
    END IF;
  END LOOP;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    pg_get_userbyid(procedure_row.proowner),
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO
    function_definition,
    function_owner,
    function_security_definer,
    function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_report_snapshot_insert_v2()'
  );
  IF function_owner IS DISTINCT FROM (
      SELECT pg_get_userbyid(class_row.relowner)
      FROM pg_catalog.pg_class AS class_row
      WHERE class_row.oid = snapshots_table_oid
    )
    OR NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR has_function_privilege(
      'public',
      'app_private.validate_management_report_snapshot_insert_v2()',
      'EXECUTE'
    )
    OR function_definition NOT ILIKE
      '%validate_management_interest_report_document_v1%'
  THEN
    RAISE EXCEPTION 'snapshot validator dispatcher does not cover interest reports';
  END IF;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    pg_get_userbyid(procedure_row.proowner),
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO
    function_definition,
    function_owner,
    function_security_definer,
    function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_interest_report_release_attempt_insert_v1()'
  );
  IF function_owner IS DISTINCT FROM (
      SELECT pg_get_userbyid(class_row.relowner)
      FROM pg_catalog.pg_class AS class_row
      WHERE class_row.oid = attempts_table_oid
    )
    OR NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private, app_data'
    ]::text[]
    OR has_function_privilege(
      'public',
      'app_private.validate_management_interest_report_release_attempt_insert_v1()',
      'EXECUTE'
    )
    OR function_definition NOT ILIKE '%jsonb_array_elements(NEW.reason_codes)%'
    OR function_definition NOT ILIKE '%release_cutoff_not_advanced%'
    OR function_definition NOT ILIKE '%no_shared_period%'
    OR function_definition NOT ILIKE '%shared_cell_privacy_status_changed%'
    OR function_definition NOT ILIKE '%shared_displayed_value_changed%'
  THEN
    RAISE EXCEPTION 'management interest release attempt trigger contract is incomplete';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_interest_report_document_v1(jsonb)'
  );
  FOREACH role_name IN ARRAY ARRAY[
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'statistical_unit',
    'dimension',
    'period_boundary_id',
    'privacy_policy',
    'source_scope',
    'query_fingerprint',
    'previous',
    'current',
    'interest_level',
    'cell_order',
    'privacy_status',
    'displayed',
    'suppressed'
  ]::text[]
  LOOP
    IF function_definition NOT ILIKE '%' || role_name || '%' THEN
      RAISE EXCEPTION
        'interest report validator omits fixed contract element: %', role_name;
    END IF;
  END LOOP;
  IF function_definition NOT ILIKE '%jsonb_array_elements%'
    OR function_definition NOT ILIKE '%WITH ORDINALITY%'
    OR function_definition NOT ILIKE '%cell_order%'
    OR function_definition NOT ILIKE '%suppressed%'
  THEN
    RAISE EXCEPTION
      'interest report validator does not enforce the fixed ten-cell privacy grid';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)'
  );
  IF function_definition NOT ILIKE '%shared_period_count%'
    OR function_definition NOT ILIKE '%assessed_cell_count%'
    OR function_definition NOT ILIKE '%shared_cell_privacy_status_changed%'
    OR function_definition NOT ILIKE '%shared_displayed_value_changed%'
    OR function_definition NOT ILIKE '%no_shared_period%'
  THEN
    RAISE EXCEPTION
      'interest report pair assessor does not bind shared five-cell periods';
  END IF;

  SELECT pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
  );
  IF function_definition NOT ILIKE '%execute_management_interest_distribution_report_v1%'
    OR function_definition NOT ILIKE '%management-interest-report:%'
    OR function_definition NOT ILIKE '%source_change_sequence%'
    OR function_definition NOT ILIKE '%interest_management_report_snapshot_release%'
  THEN
    RAISE EXCEPTION
      'interest release function does not derive the protected candidate and lineage';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_interest_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_interest_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
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
      OR has_function_privilege('tongxingzhe_management_interest_report_reader', function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION
        'interest snapshot function has an over-broad EXECUTE grant: %',
        function_name;
    END IF;
    IF NOT has_function_privilege(
      'tongxingzhe_management_interest_snapshot_release_writer',
      function_name,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'interest release writer lacks function execution: %',
        function_name;
    END IF;
  END LOOP;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass management interest snapshot release';
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

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0062_management_interest_report_snapshot_lineage'
  ) <> 1 THEN
    RAISE EXCEPTION 'interest snapshot lineage migration was not recorded once';
  END IF;
END
$check$;
