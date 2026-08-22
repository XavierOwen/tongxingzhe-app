\set ON_ERROR_STOP on

-- Structural, lineage and least-privilege checks for Slice 6BG.  The
-- rollback fixture owns document/release behaviour; the independent
-- concurrency script owns transaction ordering.  Keep this check independent
-- of fixture rows so it also runs after pg_dump/restore.
DO $check$
DECLARE
  writer_oid oid;
  attempts_oid oid;
  snapshots_oid oid;
  claims_oid oid;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  role_name text;
  column_row record;
  table_row record;
  table_oid oid;
  required_column text;
  extra_column text;
  table_privilege text;
  bridge_row record;
  expected_writer constant text :=
    'tongxingzhe_management_original_region_snapshot_release_writer';
  expected_original_reader constant text :=
    'tongxingzhe_management_original_region_report_reader';
  expected_report constant text :=
    'contact_sessions_by_original_region_two_periods';
  expected_lineage constant text :=
    'management-original-region-report:' || expected_report;
  expected_query constant text :=
    'management-report:contact_sessions_by_original_region_two_periods:v1';
BEGIN
  SELECT role_row.oid INTO writer_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = expected_writer;
  IF writer_oid IS NULL THEN
    RAISE EXCEPTION 'original region snapshot release writer role is missing';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.rolname = expected_writer
      AND (role_row.rolcanlogin OR role_row.rolsuper
        OR role_row.rolcreatedb OR role_row.rolcreaterole
        OR role_row.rolinherit OR role_row.rolreplication
        OR role_row.rolbypassrls)
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_auth_members AS membership
    WHERE membership.roleid = writer_oid
  ) THEN
    RAISE EXCEPTION 'original region snapshot writer is open or has members';
  END IF;

  SELECT class_row.oid INTO attempts_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname =
      'management_original_region_report_release_attempts'
    AND class_row.relkind IN ('r', 'p');
  IF attempts_oid IS NULL THEN
    RAISE EXCEPTION 'original region release attempt table is missing';
  END IF;

  SELECT class_row.oid INTO snapshots_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_snapshots'
    AND class_row.relkind IN ('r', 'p');
  IF snapshots_oid IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = snapshots_oid AND class_row.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'shared snapshots do not enforce writer row scope';
  END IF;

  SELECT class_row.oid INTO claims_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_release_request_claims'
    AND class_row.relkind IN ('r', 'p');
  IF claims_oid IS NULL THEN
    RAISE EXCEPTION 'management report request claim ledger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = snapshots_oid
      AND policy_row.polname =
        'management_original_region_snapshot_release_writer_scope'
      AND policy_row.polroles = ARRAY[expected_writer::regrole::oid]
      AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)
        ILIKE '%' || expected_report || '%'
      AND pg_catalog.pg_get_expr(policy_row.polqual, policy_row.polrelid)
        ILIKE '%' || expected_lineage || '%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
        ILIKE '%' || expected_report || '%'
      AND pg_catalog.pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
        ILIKE '%' || expected_lineage || '%'
  ) THEN
    RAISE EXCEPTION 'original region snapshot writer RLS policy is incomplete';
  END IF;

  -- The release-attempt validator runs as the original snapshot writer.  Its
  -- app_data reads must remain an explicit column-level allow-list.  A table
  -- grant would silently widen the validator as schemas gain new columns, so
  -- reject every table-level privilege and every column not listed here.  The
  -- contacts, provenance and change-feed source seams intentionally list no
  -- columns: this slice must not grant the release writer any direct access to
  -- them, even if a future validator implementation could use them.
  FOR table_row IN
    SELECT *
    FROM (VALUES
      ('app_data.app_users'::text,
        ARRAY['app_user_id', 'status']::text[]),
      ('app_data.organization_memberships'::text,
        ARRAY[
          'organization_membership_id', 'organization_workspace_id',
          'app_user_id', 'active_from_utc', 'inactive_from_utc'
        ]::text[]),
      ('app_data.project_memberships'::text,
        ARRAY[
          'project_membership_id', 'organization_membership_id', 'project_id',
          'active_from_utc', 'inactive_from_utc'
        ]::text[]),
      ('app_data.management_report_capability_grants'::text,
        ARRAY[
          'capability_grant_id', 'project_membership_id', 'capability_id',
          'active_from_utc', 'inactive_from_utc'
        ]::text[]),
      ('app_data.projects'::text,
        ARRAY['project_id', 'workspace_id', 'status']::text[]),
      ('app_data.workspaces'::text,
        ARRAY['workspace_id', 'workspace_kind', 'deleted_at']::text[]),
      ('app_data.contacts'::text,
        ARRAY[]::text[]),
      ('app_data.contact_location_provenance'::text,
        ARRAY[]::text[]),
      ('app_data.canonical_region_tree_releases'::text,
        ARRAY[
          'tree_version', 'lifecycle_state', 'published_at_utc',
          'content_fingerprint'
        ]::text[]),
      ('app_data.canonical_region_versions'::text,
        ARRAY['region_id', 'tree_version', 'parent_region_id', 'kind']::text[]),
      ('app_data.change_feed'::text,
        ARRAY[]::text[])
    ) AS required(table_name, required_columns)
  LOOP
    table_oid := to_regclass(table_row.table_name);
    IF table_oid IS NULL THEN
      RAISE EXCEPTION 'original region writer source table is missing: %',
        table_row.table_name;
    END IF;

    FOREACH table_privilege IN ARRAY ARRAY[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES',
      'TRIGGER'
    ]::text[]
    LOOP
      IF has_table_privilege(expected_writer, table_oid, table_privilege) THEN
        RAISE EXCEPTION
          'original region writer has table-level % on %',
          table_privilege, table_row.table_name;
      END IF;
    END LOOP;

    FOREACH required_column IN ARRAY table_row.required_columns
    LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attribute_row
        WHERE attribute_row.attrelid = table_oid
          AND attribute_row.attname = required_column
          AND attribute_row.attnum > 0
          AND NOT attribute_row.attisdropped
      ) THEN
        RAISE EXCEPTION
          'original region writer source column is missing: %.%',
          table_row.table_name, required_column;
      END IF;

      IF NOT has_column_privilege(
        expected_writer, table_oid, required_column, 'SELECT'
      ) THEN
        RAISE EXCEPTION
          'original region writer lacks column SELECT on %.%',
          table_row.table_name, required_column;
      END IF;

      IF has_column_privilege(
        expected_writer, table_oid, required_column, 'INSERT'
      ) OR has_column_privilege(
        expected_writer, table_oid, required_column, 'UPDATE'
      ) OR has_column_privilege(
        expected_writer, table_oid, required_column, 'REFERENCES'
      ) THEN
        RAISE EXCEPTION
          'original region writer has non-SELECT column privilege on %.%',
          table_row.table_name, required_column;
      END IF;
    END LOOP;

    SELECT attribute_row.attname
    INTO extra_column
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND has_column_privilege(
        expected_writer, table_oid, attribute_row.attname, 'SELECT'
      )
      AND NOT (attribute_row.attname = ANY(table_row.required_columns))
    LIMIT 1;
    IF extra_column IS NOT NULL THEN
      RAISE EXCEPTION
        'original region writer has extra column SELECT on %.%',
        table_row.table_name, extra_column;
    END IF;

    SELECT attribute_row.attname
    INTO extra_column
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND (
        has_column_privilege(
          expected_writer, table_oid, attribute_row.attname, 'INSERT'
        ) OR has_column_privilege(
          expected_writer, table_oid, attribute_row.attname, 'UPDATE'
        ) OR has_column_privilege(
          expected_writer, table_oid, attribute_row.attname, 'REFERENCES'
        )
      )
    LIMIT 1;
    IF extra_column IS NOT NULL THEN
      RAISE EXCEPTION
        'original region writer has non-SELECT column privilege on %.%',
        table_row.table_name, extra_column;
    END IF;
  END LOOP;

  -- The attempt ledger contains authorization and lineage metadata only.
  FOR column_row IN
    SELECT *
    FROM (VALUES
      ('release_request_id'::text, 'uuid'::text, true),
      ('requested_by_app_user_id'::text, 'uuid'::text, true),
      ('organization_workspace_id'::text, 'uuid'::text, true),
      ('organization_membership_id'::text, 'uuid'::text, true),
      ('project_membership_id'::text, 'uuid'::text, true),
      ('capability_grant_id'::text, 'uuid'::text, true),
      ('capability_id'::text, 'text'::text, true),
      ('authorization_reference_at_utc'::text,
        'timestamp with time zone'::text, true),
      ('project_id'::text, 'uuid'::text, true),
      ('reporting_time_zone_version_number'::text, 'integer'::text, true),
      ('reporting_time_zone'::text, 'text'::text, true),
      ('reporting_time_zone_effective_from_utc'::text,
        'timestamp with time zone'::text, true),
      ('data_cutoff_utc'::text, 'timestamp with time zone'::text, true),
      ('release_lineage_id'::text, 'text'::text, true),
      ('report_id'::text, 'text'::text, true),
      ('report_version'::text, 'integer'::text, true),
      ('query_fingerprint'::text, 'text'::text, true),
      ('source_tree_version'::text, 'text'::text, true),
      ('source_content_fingerprint'::text, 'text'::text, true),
      ('source_change_sequence'::text, 'bigint'::text, true),
      ('compared_snapshot_id'::text, 'uuid'::text, false),
      ('released_snapshot_id'::text, 'uuid'::text, false),
      ('shared_period_count'::text, 'integer'::text, true),
      ('assessed_cell_count'::text, 'integer'::text, true),
      ('result_status'::text, 'text'::text, true),
      ('reason_codes'::text, 'jsonb'::text, true),
      ('result_document'::text, 'jsonb'::text, true)
    ) AS expected(column_name, column_type, required_not_null)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = attempts_oid
        AND attribute_row.attname = column_row.column_name
        AND attribute_row.atttypid::regtype::text = column_row.column_type
        AND attribute_row.attnotnull = column_row.required_not_null
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
    ) THEN
      RAISE EXCEPTION 'original region attempt column contract is incomplete: %',
        column_row.column_name;
    END IF;
  END LOOP;

  IF (
    SELECT count(*) FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = attempts_oid
      AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
  ) <> 27 THEN
    RAISE EXCEPTION 'original region attempt table must contain 27 columns';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = attempts_oid
      AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'protected_report', 'cells', 'value_count', 'contributor',
        'contributor_id', 'contact_id', 'source_id', 'place_name',
        'latitude', 'longitude', 'geometry', 'hidden_value'
      )
  ) THEN
    RAISE EXCEPTION 'original region attempt table stores report values';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = attempts_oid
      AND constraint_row.contype = 'p'
      AND constraint_row.conkey = ARRAY[1::smallint]
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_oid
      AND trigger_row.tgname =
        'management_original_region_report_release_attempts_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_oid
      AND trigger_row.tgname =
        'original_region_report_release_attempts_validate_insert'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'original region attempt history is not protected';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_oid
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%original_region_management_report_snapshot_release%'
  ) THEN
    RAISE EXCEPTION 'request claim ledger omits original region family';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_oid
      AND trigger_row.tgname =
        'management_original_region_report_release_request_claim'
      AND NOT trigger_row.tgisinternal
      AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ILIKE
        '%claim_management_report_release_request_v1(''original_region_management_report_snapshot_release_v1'')%'
  ) THEN
    RAISE EXCEPTION 'original region request claim trigger is incomplete';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_original_region_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_original_region_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.validate_original_region_report_release_attempt_insert_v1()'
    ),
    to_regprocedure(
      'app_private.resolve_management_original_region_release_authorization_v1(uuid,uuid)'
    ),
    to_regprocedure(
      'app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'original region snapshot function set is incomplete';
    END IF;
  END LOOP;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_original_region_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_original_region_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    SELECT
      pg_catalog.pg_get_functiondef(procedure_row.oid),
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

    IF function_owner <> expected_writer OR NOT function_security_definer THEN
      RAISE EXCEPTION 'original region function owner/security is incorrect: %',
        function_name;
    END IF;

    IF function_name::text LIKE '%release_management_original_region%' THEN
      IF function_volatility <> 'v'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private, app_data'
        ]::text[]
      THEN
        RAISE EXCEPTION 'original region release security contract is incorrect';
      END IF;
    ELSIF function_name::text LIKE '%assess_management_original_region%' THEN
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'original region pair security contract is incorrect';
      END IF;
    ELSE
      IF function_volatility <> 's'
        OR function_config IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog, app_data, app_private'
        ]::text[]
      THEN
        RAISE EXCEPTION 'original region validator security contract is incorrect';
      END IF;
    END IF;
  END LOOP;

  SELECT
    pg_catalog.pg_get_functiondef(procedure_row.oid),
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO function_definition, function_security_definer, function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_report_snapshot_insert_v2()'
  );
  IF NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR function_definition NOT ILIKE
      '%validate_management_original_region_report_document_v1%'
    OR function_definition NOT ILIKE '%source_tree_version%'
    OR function_definition NOT ILIKE '%source_content_fingerprint%'
  THEN
    RAISE EXCEPTION 'shared snapshot validator omits original region dispatch';
  END IF;

  SELECT
    pg_catalog.pg_get_functiondef(procedure_row.oid),
    pg_catalog.pg_get_userbyid(procedure_row.proowner),
    procedure_row.prosecdef,
    procedure_row.proconfig
  INTO function_definition, function_owner,
    function_security_definer, function_config
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_original_region_report_release_attempt_insert_v1()'
  );
  IF function_owner <> expected_writer
    OR NOT function_security_definer
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private, app_data'
    ]::text[]
    OR function_definition NOT ILIKE '%jsonb_array_elements(NEW.reason_codes)%'
    OR function_definition NOT ILIKE '%source_tree%'
    OR function_definition NOT ILIKE '%source_change_sequence%'
  THEN
    RAISE EXCEPTION 'original region attempt trigger validator is incomplete';
  END IF;

  -- These are the only release-writer-to-reader seams.  Keep the bridge
  -- functions reader-owned and narrow: a SECURITY DEFINER bridge with a
  -- fixed search_path may delegate to the 6BD reader contract without
  -- granting the release writer direct access to its source tables.
  FOR bridge_row IN
    SELECT *
    FROM (VALUES
      (
        to_regprocedure(
          'app_private.canonicalize_original_region_report_release_request_v1(jsonb)'
        ),
        'canonicalize_management_original_region_report_request_v1'::text
      ),
      (
        to_regprocedure(
          'app_private.execute_management_original_region_contact_session_report_v1r(uuid,text,timestamp with time zone)'
        ),
        'execute_management_original_region_contact_session_report_v1'::text
      )
    ) AS expected(function_name, expected_body)
  LOOP
    IF bridge_row.function_name IS NULL THEN
      RAISE EXCEPTION 'original region reader bridge function set is incomplete';
    END IF;

    SELECT
      pg_catalog.pg_get_functiondef(procedure_row.oid),
      pg_catalog.pg_get_userbyid(procedure_row.proowner),
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
    WHERE procedure_row.oid = bridge_row.function_name;

    IF function_owner <> expected_original_reader
      OR NOT function_security_definer
      OR function_volatility <> 's'
      OR function_config IS DISTINCT FROM ARRAY[
        'search_path=pg_catalog, app_private'
      ]::text[]
      OR function_definition NOT ILIKE '%' || bridge_row.expected_body || '%'
    THEN
      RAISE EXCEPTION 'original region reader bridge security contract is incorrect: %',
        bridge_row.function_name;
    END IF;
  END LOOP;

  SELECT
    pg_catalog.pg_get_functiondef(procedure_row.oid),
    pg_catalog.pg_get_userbyid(procedure_row.proowner),
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
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.resolve_management_original_region_release_authorization_v1(uuid,uuid)'
  );
  IF function_owner IS DISTINCT FROM (
      SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
      FROM pg_catalog.pg_class AS class_row
      WHERE class_row.oid =
        'app_data.management_report_capability_grants'::regclass
    )
    OR NOT function_security_definer
    OR function_volatility <> 'v'
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog, app_private'
    ]::text[]
    OR function_definition NOT ILIKE
      '%resolve_management_report_authorization_v1%'
    OR function_definition NOT ILIKE '%release_management_reports%'
  THEN
    RAISE EXCEPTION
      'original region authorization wrapper security contract is incorrect';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_original_region_report_document_v1(jsonb)'
    ),
    to_regprocedure(
      'app_private.assess_management_original_region_report_pair_release_v1(jsonb,jsonb)'
    ),
    to_regprocedure(
      'app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
    )
  ]::regprocedure[]
  LOOP
    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
      OR has_function_privilege(
        'tongxingzhe_management_original_region_report_reader',
        function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_region_report_reader',
        function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_current_city_snapshot_release_writer',
        function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_interest_snapshot_release_writer',
        function_name, 'EXECUTE'
      )
      OR NOT has_function_privilege(expected_writer, function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'original region function privilege matrix is incorrect: %',
        function_name;
    END IF;
  END LOOP;

  FOR bridge_row IN
    SELECT *
    FROM (VALUES
      (to_regprocedure(
        'app_private.canonicalize_original_region_report_release_request_v1(jsonb)'
      )),
      (to_regprocedure(
        'app_private.execute_management_original_region_contact_session_report_v1r(uuid,text,timestamp with time zone)'
      ))
    ) AS expected(function_name)
  LOOP
    IF bridge_row.function_name IS NULL THEN
      RAISE EXCEPTION 'original region reader bridge ACL set is incomplete';
    END IF;

    -- Only the reader owner and the dedicated release writer may execute the
    -- narrow seam.  All runtime, public, cross-family reader and writer roles
    -- must remain unable to turn it into a general report bridge.
    IF has_function_privilege('public', bridge_row.function_name, 'EXECUTE')
      OR has_function_privilege(
        'tongxingzhe_runtime', bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_region_publisher', bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_region_mapping_writer', bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_contact_provenance_writer',
        bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_region_attribution_reader',
        bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_region_report_reader',
        bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_interest_report_reader',
        bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_current_city_snapshot_release_writer',
        bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_interest_snapshot_release_writer',
        bridge_row.function_name, 'EXECUTE'
      )
      OR has_function_privilege(
        'tongxingzhe_management_report_snapshot_lifecycle_writer',
        bridge_row.function_name, 'EXECUTE'
      )
      OR NOT has_function_privilege(
        expected_original_reader, bridge_row.function_name, 'EXECUTE'
      )
      OR NOT has_function_privilege(
        expected_writer, bridge_row.function_name, 'EXECUTE'
      )
    THEN
      RAISE EXCEPTION 'original region reader bridge privilege matrix is incorrect: %',
        bridge_row.function_name;
    END IF;
  END LOOP;

  function_name = to_regprocedure(
    'app_private.resolve_management_original_region_release_authorization_v1(uuid,uuid)'
  );
  IF function_name IS NULL
    OR has_function_privilege('public', function_name, 'EXECUTE')
    OR has_function_privilege(
      'tongxingzhe_runtime', function_name, 'EXECUTE'
    )
    OR has_function_privilege(
      expected_original_reader, function_name, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_region_report_reader',
      function_name, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_interest_report_reader',
      function_name, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      function_name, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_interest_snapshot_release_writer',
      function_name, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_management_report_snapshot_lifecycle_writer',
      function_name, 'EXECUTE'
    )
    OR NOT has_function_privilege(expected_writer, function_name, 'EXECUTE')
  THEN
    RAISE EXCEPTION
      'original region authorization wrapper privilege matrix is incorrect';
  END IF;

  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_report_snapshot_lifecycle_writer'
  ]::text[]
  LOOP
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = role_name)
      AND has_table_privilege(
        role_name, attempts_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION 'original region attempt table has direct privilege for %',
        role_name;
    END IF;
  END LOOP;
  IF has_table_privilege(
    'public', attempts_oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) THEN
    RAISE EXCEPTION 'original region attempt table is open to PUBLIC';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass original region snapshot release';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.validate_management_original_region_report_document_v1(jsonb)'
  );
  IF function_definition NOT ILIKE '%' || expected_report || '%'
    OR function_definition NOT ILIKE '%source_tree_context%'
    OR function_definition NOT ILIKE '%source_change_sequence%'
    OR function_definition NOT ILIKE '%cells%'
    OR function_definition NOT ILIKE '%suppressed%'
  THEN
    RAISE EXCEPTION 'original region validator does not pin its document contract';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.assess_management_original_region_report_pair_release_v1(jsonb,jsonb)'
  );
  IF function_definition NOT ILIKE '%shared_period_count%'
    OR function_definition NOT ILIKE '%assessed_cell_count%'
    OR function_definition NOT ILIKE '%source_tree%'
    OR function_definition NOT ILIKE '%no_shared_period%'
  THEN
    RAISE EXCEPTION 'original region pair assessor omits lineage invariants';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(procedure_row.oid)
  INTO function_definition
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = to_regprocedure(
    'app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
  );
  IF function_definition NOT ILIKE
      '%execute_management_original_region_contact_session_report%'
    OR function_definition NOT ILIKE '%original_region_management_report_snapshot_release%'
    OR function_definition NOT ILIKE '%source_change_sequence%'
    OR function_definition NOT ILIKE '%source_tree_version%'
    OR function_definition NOT ILIKE '%source_content_fingerprint%'
  THEN
    RAISE EXCEPTION 'original region release does not derive fixed candidate lineage';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = to_regprocedure(
      'app_private.validate_management_report_document_v1(jsonb)'
    )
      AND pg_catalog.pg_get_functiondef(procedure_row.oid) ILIKE
        '%' || expected_report || '%'
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = to_regprocedure(
      'app_private.validate_management_current_city_report_document_v1(jsonb)'
    )
      AND pg_catalog.pg_get_functiondef(procedure_row.oid) ILIKE
        '%' || expected_report || '%'
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = to_regprocedure(
      'app_private.validate_management_interest_report_document_v1(jsonb)'
    )
      AND pg_catalog.pg_get_functiondef(procedure_row.oid) ILIKE
        '%' || expected_report || '%'
  ) THEN
    RAISE EXCEPTION 'original region report widened an existing validator family';
  END IF;

  IF (
    SELECT count(*) FROM app_migrations.schema_migrations
    WHERE version = '0068_management_original_region_report_snapshot_lineage'
  ) <> 1 THEN
    RAISE EXCEPTION '0068 migration was not recorded exactly once';
  END IF;
END
$check$;
