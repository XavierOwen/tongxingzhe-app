\set ON_ERROR_STOP on

-- Structural and least-privilege checks for Slice 6BN.  The rollback fixture
-- proves the public declaration and lifecycle seams.  This check keeps the
-- original-region relation independent from the 6BE channel ledger and makes
-- the value-free boundary observable to future migrations.
DO $check$
DECLARE
  replacements_table_oid oid;
  snapshots_table_oid oid;
  table_owner text;
  function_name regprocedure;
  function_definition text;
  function_config text[];
  function_owner text;
  function_security_definer boolean;
  function_volatility "char";
  role_name text;
  required_column record;
  provenance_function regprocedure;
  trusted_function regprocedure;
BEGIN
  SELECT class_row.oid, pg_get_userbyid(class_row.relowner)
  INTO replacements_table_oid, table_owner
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname =
      'management_original_region_report_snapshot_replacements'
    AND class_row.relkind IN ('r', 'p');

  IF replacements_table_oid IS NULL THEN
    RAISE EXCEPTION
      'original-region snapshot replacement table is missing';
  END IF;

  SELECT class_row.oid
  INTO snapshots_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_snapshots'
    AND class_row.relkind IN ('r', 'p');
  IF snapshots_table_oid IS NULL THEN
    RAISE EXCEPTION 'management report snapshot source table is missing';
  END IF;

  IF NOT (
      SELECT class_row.relrowsecurity
      FROM pg_catalog.pg_class AS class_row
      WHERE class_row.oid = snapshots_table_oid
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_policy AS policy_row
      JOIN pg_catalog.pg_roles AS policy_role
        ON policy_role.oid = ANY (policy_row.polroles)
      WHERE policy_row.polrelid = snapshots_table_oid
        AND policy_row.polname =
          'management_original_region_snapshot_replacement_read_scope'
        AND policy_row.polcmd = 'r'
        AND policy_role.rolname =
          'tongxingzhe_management_report_snapshot_lifecycle_writer'
        AND pg_catalog.pg_get_expr(
          policy_row.polqual,
          policy_row.polrelid
        ) ILIKE '%contact_sessions_by_original_region_two_periods%'
        AND pg_catalog.pg_get_expr(
          policy_row.polqual,
          policy_row.polrelid
        ) ILIKE '%management-original-region-report:%'
    )
  THEN
    RAISE EXCEPTION
      'original-region snapshot replacement RLS scope is incomplete';
  END IF;

  IF table_owner IS DISTINCT FROM
      'tongxingzhe_management_report_snapshot_lifecycle_writer'
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_roles AS role_row
      WHERE role_row.rolname = table_owner
        AND (
          role_row.rolcanlogin
          OR role_row.rolsuper
          OR role_row.rolcreatedb
          OR role_row.rolcreaterole
          OR role_row.rolinherit
          OR role_row.rolreplication
          OR role_row.rolbypassrls
        )
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_auth_members AS membership
      JOIN pg_catalog.pg_roles AS role_row
        ON role_row.oid = membership.roleid
      WHERE role_row.rolname = table_owner
    )
  THEN
    RAISE EXCEPTION
      'original-region replacement owner must be a closed NOLOGIN role: %',
      table_owner;
  END IF;

  -- This is an identity/provenance ledger only.  Protected report values,
  -- source rows and location details remain in the immutable snapshot.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS column_row
    WHERE column_row.attrelid = replacements_table_oid
      AND column_row.attnum > 0
      AND NOT column_row.attisdropped
      AND column_row.attname IN (
        'protected_report', 'result_report', 'cells', 'value_count',
        'contributor', 'contributor_id', 'contact_id', 'place_name',
        'latitude', 'longitude', 'geometry', 'source_change_sequence',
        'source_contact_id'
      )
  ) THEN
    RAISE EXCEPTION
      'original-region replacement table stores report values or source data';
  END IF;

  FOR required_column IN
    SELECT *
    FROM (
      VALUES
        ('replacement_request_id'::text, 'uuid'::text, true),
        ('requested_by_app_user_id'::text, 'uuid'::text, true),
        ('organization_workspace_id'::text, 'uuid'::text, true),
        ('organization_membership_id'::text, 'uuid'::text, true),
        ('project_membership_id'::text, 'uuid'::text, true),
        ('capability_grant_id'::text, 'uuid'::text, true),
        ('capability_id'::text, 'text'::text, true),
        ('authorization_reference_at_utc'::text,
          'timestamp with time zone'::text, true),
        ('project_id'::text, 'uuid'::text, true),
        ('release_lineage_id'::text, 'text'::text, true),
        ('report_id'::text, 'text'::text, true),
        ('report_version'::text, 'integer'::text, true),
        ('superseded_snapshot_id'::text, 'uuid'::text, true),
        ('replacement_snapshot_id'::text, 'uuid'::text, true),
        ('replacement_reason_code'::text, 'text'::text, true),
        ('declared_at_utc'::text, 'timestamp with time zone'::text, true),
        ('result_document'::text, 'jsonb'::text, true)
    ) AS expected(column_name, column_type, required_not_null)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS column_row
      WHERE column_row.attrelid = replacements_table_oid
        AND column_row.attname = required_column.column_name
        AND column_row.atttypid::regtype::text = required_column.column_type
        AND column_row.attnotnull = required_column.required_not_null
        AND column_row.attnum > 0
        AND NOT column_row.attisdropped
    ) THEN
      RAISE EXCEPTION
        'original-region replacement column contract is incomplete: %',
        required_column.column_name;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_attribute AS column_row
    WHERE column_row.attrelid = replacements_table_oid
      AND column_row.attnum > 0
      AND NOT column_row.attisdropped
  ) <> 17 THEN
    RAISE EXCEPTION
      'original-region replacement table must contain exactly seventeen audit columns';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = replacements_table_oid
      AND constraint_row.contype = 'p'
      AND constraint_row.conkey = ARRAY[1::smallint]
  ) THEN
    RAISE EXCEPTION 'original-region replacement request primary key is incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = replacements_table_oid
      AND constraint_row.contype = 'u'
      AND (
        constraint_row.conkey = ARRAY[13::smallint]
        OR constraint_row.conkey = ARRAY[14::smallint]
      )
  ) <> 2 THEN
    RAISE EXCEPTION
      'original-region replacement snapshot uniqueness is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = replacements_table_oid
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = snapshots_table_oid
      AND constraint_row.conkey = ARRAY[
        (SELECT attnum FROM pg_catalog.pg_attribute
         WHERE attrelid = replacements_table_oid
           AND attname = 'superseded_snapshot_id')::smallint
      ]
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = replacements_table_oid
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = snapshots_table_oid
      AND constraint_row.conkey = ARRAY[
        (SELECT attnum FROM pg_catalog.pg_attribute
         WHERE attrelid = replacements_table_oid
           AND attname = 'replacement_snapshot_id')::smallint
      ]
  ) THEN
    RAISE EXCEPTION
      'original-region replacement snapshot foreign keys are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = replacements_table_oid
      AND constraint_row.contype = 'c'
      AND pg_get_constraintdef(constraint_row.oid) ILIKE
        '%superseded_snapshot_id%replacement_snapshot_id%'
  ) THEN
    RAISE EXCEPTION
      'original-region replacement table lacks the no-self-link invariant';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = replacements_table_oid
      AND NOT trigger_row.tgisinternal
      AND (trigger_row.tgtype & 1) = 1
      AND (trigger_row.tgtype & 2) = 2
      AND (trigger_row.tgtype & 8) = 8
      AND (trigger_row.tgtype & 16) = 16
      AND trigger_row.tgfoid = to_regprocedure(
        'app_private.reject_management_report_history_mutation()'
      )
  ) THEN
    RAISE EXCEPTION 'original-region replacement history is not immutable';
  END IF;

  function_name = to_regprocedure(
    'app_private.validate_management_original_region_snapshot_replacement_v1()'
  );
  IF function_name IS NULL THEN
    RAISE EXCEPTION 'original-region replacement insert validator is missing';
  END IF;
  SELECT
    pg_get_userbyid(procedure_row.proowner),
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile,
    pg_get_functiondef(procedure_row.oid)
  INTO
    function_owner,
    function_security_definer,
    function_config,
    function_volatility,
    function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = function_name;
  IF function_owner IS DISTINCT FROM table_owner
    OR NOT function_security_definer
    OR function_volatility <> 'v'
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private, app_data'
    ]::text[]
    OR function_definition NOT ILIKE '%source_tree_version%'
    OR function_definition NOT ILIKE '%source_content_fingerprint%'
    OR function_definition NOT ILIKE '%protected_report%'
    OR function_definition NOT ILIKE '%result_document%'
  THEN
    RAISE EXCEPTION
      'original-region replacement validator security/provenance contract is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = replacements_table_oid
      AND trigger_row.tgname =
        'management_original_region_snapshot_replacements_validate'
      AND NOT trigger_row.tgisinternal
      AND pg_get_triggerdef(trigger_row.oid) ILIKE
        '%validate_management_original_region_snapshot_replacement_v1%'
  ) THEN
    RAISE EXCEPTION
      'original-region replacement insert validator trigger is missing';
  END IF;

  trusted_function = to_regprocedure(
    'app_private.management_original_region_snapshot_has_trusted_provenance_v1(uuid,uuid)'
  );
  IF trusted_function IS NULL THEN
    RAISE EXCEPTION
      'original-region trusted provenance helper is missing';
  END IF;
  SELECT
    pg_get_userbyid(procedure_row.proowner),
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile,
    pg_get_functiondef(procedure_row.oid)
  INTO
    function_owner,
    function_security_definer,
    function_config,
    function_volatility,
    function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = trusted_function;
  IF function_owner IS DISTINCT FROM table_owner
    OR NOT function_security_definer
    OR function_volatility <> 's'
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR function_definition NOT ILIKE '%original_region_snapshot_replacement_provenance_v1%'
  THEN
    RAISE EXCEPTION
      'original-region trusted provenance helper contract is incomplete';
  END IF;

  provenance_function = to_regprocedure(
    'app_private.original_region_snapshot_replacement_provenance_v1(uuid,uuid)'
  );
  IF provenance_function IS NULL THEN
    RAISE EXCEPTION 'original-region replacement provenance seam is missing';
  END IF;
  SELECT
    pg_get_userbyid(procedure_row.proowner),
    procedure_row.prosecdef,
    procedure_row.proconfig,
    procedure_row.provolatile,
    pg_get_functiondef(procedure_row.oid)
  INTO
    function_owner,
    function_security_definer,
    function_config,
    function_volatility,
    function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = provenance_function;
  IF function_owner IS DISTINCT FROM
      'tongxingzhe_management_original_region_snapshot_release_writer'
    OR NOT function_security_definer
    OR function_volatility <> 's'
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR function_definition NOT ILIKE '%management_original_region_report_release_attempts%'
    OR function_definition NOT ILIKE '%original_region_management_report_snapshot_release%'
    OR function_definition NOT ILIKE '%source_tree_context%'
  THEN
    RAISE EXCEPTION
      'original-region replacement provenance seam contract is incomplete';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_original_region_snapshot_replacement_v1()'
    ),
    provenance_function,
    trusted_function
  ]::regprocedure[]
  LOOP
    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION
        'original-region replacement internal function is directly executable: %',
        function_name;
    END IF;
  END LOOP;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)'
    ),
    to_regprocedure(
      'app_private.read_management_original_region_report_snapshot_lifecycle_v1(uuid,uuid)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION
        'original-region replacement public SQL seam is missing';
    END IF;

    SELECT
      pg_get_functiondef(procedure_row.oid),
      pg_get_userbyid(procedure_row.proowner),
      procedure_row.prosecdef,
      procedure_row.proconfig,
      procedure_row.provolatile
    INTO
      function_definition,
      function_owner,
      function_security_definer,
      function_config,
      function_volatility
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = function_name;

    IF function_owner IS DISTINCT FROM table_owner
      OR NOT function_security_definer
      OR function_definition IS NULL
    THEN
      RAISE EXCEPTION
        'original-region replacement function owner/security is incorrect: %',
        function_name;
    END IF;

    IF function_name::text LIKE 'app_private.declare_%' THEN
      IF function_volatility <> 'v'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
        OR function_definition NOT ILIKE '%pg_advisory_xact_lock%'
        OR function_definition NOT ILIKE '%release_management_reports%'
        OR function_definition NOT ILIKE
          '%management-report-release-request:%'
        OR function_definition NOT ILIKE
          '%original_region_management_report_snapshot_replacement%'
        OR function_definition NOT ILIKE
          '%management_original_region_snapshot_has_trusted_provenance_v1%'
        OR function_definition NOT ILIKE
          '%validate_management_original_region_report_document_v1%'
      THEN
        RAISE EXCEPTION
          'original-region replacement declaration lock/provenance contract is incomplete';
      END IF;
    ELSE
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
        OR function_definition ILIKE '%protected_report%'
        OR function_definition ILIKE '%result_document%'
        OR function_definition ILIKE '%cells%'
        OR function_definition ILIKE '%contributor%'
        OR function_definition ILIKE '%source_tree_context%'
        OR function_definition NOT ILIKE '%replacement_snapshot_id%'
      THEN
        RAISE EXCEPTION
          'original-region replacement lifecycle query is not value-free';
      END IF;
    END IF;
  END LOOP;

  IF has_table_privilege(
      table_owner,
      'app_private.management_original_region_report_release_attempts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION
      'lifecycle owner can bypass the original-region provenance bridge';
  END IF;

  IF NOT has_table_privilege(
      table_owner,
      'app_private.management_report_release_request_claims',
      'SELECT'
    )
    OR NOT has_table_privilege(
      table_owner,
      'app_private.management_report_release_request_claims',
      'INSERT'
    )
    OR has_table_privilege(
      table_owner,
      'app_private.management_report_release_request_claims',
      'UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid =
          'app_private.management_report_release_request_claims'::regclass
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE
          '%original_region_management_report_snapshot_replacement%'
    )
  THEN
    RAISE EXCEPTION
      'original-region replacement request claim contract is incomplete';
  END IF;

  -- The relation is private.  The original-region reader and release writer
  -- are deliberately denied direct access; only the closed owner can write,
  -- and only the SECURITY DEFINER public seam can perform the contract.
  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer'
  ]::text[]
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = role_name
    ) AND (
      has_table_privilege(
        role_name,
        'app_private.management_original_region_report_snapshot_replacements',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
      OR has_function_privilege(
        role_name,
        'app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)',
        'EXECUTE'
      )
      OR has_function_privilege(
        role_name,
        'app_private.read_management_original_region_report_snapshot_lifecycle_v1(uuid,uuid)',
        'EXECUTE'
      )
    ) THEN
      RAISE EXCEPTION
        'original-region replacement contract is directly executable by %',
        role_name;
    END IF;
  END LOOP;

  IF has_table_privilege(
      'public',
      'app_private.management_original_region_report_snapshot_replacements',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_function_privilege(
      'public',
      'app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'public',
      'app_private.read_management_original_region_report_snapshot_lifecycle_v1(uuid,uuid)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'original-region replacement contract is open to PUBLIC';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0072_management_original_region_report_snapshot_replacements'
  ) <> 1 THEN
    RAISE EXCEPTION
      'original-region snapshot replacement migration was not recorded once';
  END IF;
END
$check$;
