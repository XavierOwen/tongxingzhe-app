\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6BQ.
-- Behavioural release, value-free blocking and rollback evidence belongs to
-- fixture 0075. The independent-session lock-order evidence belongs to the
-- 0075 concurrency script.
DO $check$
DECLARE
  expected_writer constant text :=
    'tongxingzhe_management_consent_ratio_snapshot_release_writer';
  expected_reader constant text :=
    'tongxingzhe_management_follow_up_consent_ratio_reader';
  expected_report constant text :=
    'contact_target_follow_up_consent_ratio_two_periods';
  expected_lineage constant text :=
    'management-follow-up-consent-ratio-report:' || expected_report;
  expected_query constant text :=
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1';
  expected_claim_family constant text :=
    'follow_up_consent_ratio_management_report_snapshot_release';
  writer_oid oid;
  attempts_oid oid;
  snapshots_oid oid;
  claims_oid oid;
  owner_name text;
  required_column text;
  forbidden_column text;
  table_name text;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_result text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  function_role text;
  expected_result text;
  expected_function_path text[];
  source_table_oid oid;
  source_column text;
BEGIN
  SELECT role_row.oid
  INTO writer_oid
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = expected_writer;

  IF writer_oid IS NULL THEN
    RAISE EXCEPTION '6BQ snapshot release writer role is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles AS role_row
    WHERE role_row.oid = writer_oid
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
      '6BQ snapshot release writer must be a closed NOLOGIN NOINHERIT role';
  END IF;

  SELECT class_row.oid, owner_role.rolname
  INTO attempts_oid, owner_name
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = class_row.relnamespace
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = class_row.relowner
  WHERE namespace_row.nspname = 'app_private'
    AND class_row.relname =
      'management_follow_up_consent_report_release_attempts'
    AND class_row.relkind = 'r';

  IF attempts_oid IS NULL THEN
    RAISE EXCEPTION
      '6BQ follow-up consent snapshot release attempt table is missing';
  END IF;

  IF owner_name IS DISTINCT FROM expected_writer THEN
    RAISE EXCEPTION
      '6BQ release attempt owner is not the closed release writer: %',
      owner_name;
  END IF;

  FOREACH required_column IN ARRAY ARRAY[
    'release_request_id',
    'requested_by_app_user_id',
    'organization_workspace_id',
    'organization_membership_id',
    'project_membership_id',
    'capability_grant_id',
    'capability_id',
    'authorization_reference_at_utc',
    'project_id',
    'reporting_time_zone_version_number',
    'reporting_time_zone',
    'reporting_time_zone_effective_from_utc',
    'data_cutoff_utc',
    'release_lineage_id',
    'report_id',
    'report_version',
    'query_fingerprint',
    'source_change_sequence',
    'compared_snapshot_id',
    'released_snapshot_id',
    'result_status',
    'reason_codes',
    'result_document'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS column_row
      WHERE column_row.attrelid = attempts_oid
        AND column_row.attnum > 0
        AND NOT column_row.attisdropped
        AND column_row.attname = required_column
    ) THEN
      RAISE EXCEPTION
        '6BQ release attempt table is missing column %', required_column;
    END IF;
  END LOOP;

  FOREACH forbidden_column IN ARRAY ARRAY[
    'protected_report',
    'cells',
    'period_results',
    'ratio',
    'coverage',
    'contact_id',
    'promotion_target_id',
    'target_id',
    'contributor_id',
    'contributor_key',
    'source_id',
    'raw_answer',
    'place_name',
    'latitude',
    'longitude',
    'email',
    'phone'
  ] LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS column_row
      WHERE column_row.attrelid = attempts_oid
        AND column_row.attnum > 0
        AND NOT column_row.attisdropped
        AND column_row.attname = forbidden_column
    ) THEN
      RAISE EXCEPTION
        '6BQ release attempt table stores protected/source column %',
        forbidden_column;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = attempts_oid
      AND constraint_row.contype = 'p'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%release_request_id%'
  ) THEN
    RAISE EXCEPTION '6BQ release attempt request UUID primary key is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = attempts_oid
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%' || expected_report || '%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = attempts_oid
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%' || expected_lineage || '%'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = attempts_oid
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%' || expected_query || '%'
  ) THEN
    RAISE EXCEPTION
      '6BQ release attempt table does not pin report identity and lineage';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_oid
      AND NOT trigger_row.tgisinternal
      AND (trigger_row.tgtype & 1) = 1
      AND (trigger_row.tgtype & 2) = 2
      AND (trigger_row.tgtype & 8) = 8
      AND (trigger_row.tgtype & 16) = 16
      AND trigger_row.tgfoid = to_regprocedure(
        'app_private.reject_management_report_history_mutation()'
      )
  ) THEN
    RAISE EXCEPTION '6BQ release attempt history is not immutable';
  END IF;

  IF has_table_privilege('public', attempts_oid, 'SELECT')
    OR has_table_privilege('tongxingzhe_runtime', attempts_oid, 'SELECT')
    OR has_table_privilege('public', attempts_oid, 'INSERT')
    OR has_table_privilege('tongxingzhe_runtime', attempts_oid, 'INSERT')
    OR has_table_privilege('public', attempts_oid, 'UPDATE')
    OR has_table_privilege('tongxingzhe_runtime', attempts_oid, 'UPDATE')
    OR has_table_privilege('public', attempts_oid, 'DELETE')
    OR has_table_privilege('tongxingzhe_runtime', attempts_oid, 'DELETE')
  THEN
    RAISE EXCEPTION
      '6BQ release attempt table is directly accessible by PUBLIC/runtime';
  END IF;

  SELECT class_row.oid
  INTO snapshots_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = class_row.relnamespace
  WHERE namespace_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_snapshots'
    AND class_row.relkind = 'r';

  IF snapshots_oid IS NULL THEN
    RAISE EXCEPTION '6BQ shared management snapshot table is missing';
  END IF;

  SELECT owner_role.rolname
  INTO owner_name
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = class_row.relowner
  WHERE class_row.oid = snapshots_oid;

  IF owner_name IS NULL OR owner_name = expected_writer THEN
    RAISE EXCEPTION
      '6BQ shared snapshot table must not be owned by the release writer: %',
      owner_name;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = snapshots_oid
      AND class_row.relrowsecurity
  ) THEN
    RAISE EXCEPTION '6BQ shared snapshots do not enforce row security';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policy AS policy_row
    WHERE policy_row.polrelid = snapshots_oid
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
    RAISE EXCEPTION '6BQ snapshot writer RLS scope is incomplete';
  END IF;

  -- The release writer reads authorization and release metadata directly, but
  -- never the candidate source. The reader-owned executor below is the only
  -- contact-target source seam.
  FOREACH table_name IN ARRAY ARRAY[
    'app_data.contacts',
    'app_data.contact_target_links'
  ] LOOP
    source_table_oid := to_regclass(table_name);
    IF source_table_oid IS NULL THEN
      RAISE EXCEPTION '6BQ release source/authorization table is missing: %',
        table_name;
    END IF;

    IF has_table_privilege(expected_writer, source_table_oid, 'SELECT') THEN
      RAISE EXCEPTION
        '6BQ release writer has table-level SELECT on %', table_name;
    END IF;

    SELECT attribute_row.attname
    INTO source_column
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = source_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND has_column_privilege(
        expected_writer,
        source_table_oid,
        attribute_row.attname,
        'SELECT'
      )
    LIMIT 1;
    IF source_column IS NOT NULL THEN
      RAISE EXCEPTION
        '6BQ release writer has column SELECT on %.%',
        table_name, source_column;
    END IF;
  END LOOP;

  -- Only the reader-owned bridge may invoke the 0074 candidate executor.  A
  -- direct EXECUTE grant to the release writer would bypass this source ACL
  -- boundary even if the writer has no table privileges of its own.
  function_name := to_regprocedure(
    'app_private.execute_management_follow_up_consent_ratio_report_release_v1(uuid,uuid,text,timestamp with time zone)'
  );
  IF function_name IS NULL THEN
    RAISE EXCEPTION '6BQ reader-owned candidate release bridge is missing';
  END IF;

  SELECT
    pg_catalog.pg_get_functiondef(procedure_row.oid),
    owner_role.rolname,
    procedure_row.prosecdef
  INTO function_definition, function_owner, function_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = function_name;

  IF function_owner IS DISTINCT FROM expected_reader
    OR NOT function_security_definer
    OR function_definition NOT ILIKE
      '%execute_management_follow_up_consent_ratio_report_v1%'
    OR NOT has_function_privilege(expected_writer, function_name, 'EXECUTE')
    OR has_function_privilege('public', function_name, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
  THEN
    RAISE EXCEPTION
      '6BQ candidate release bridge is not reader-owned and privately executable';
  END IF;

  function_name := to_regprocedure(
    'app_private.execute_management_follow_up_consent_ratio_report_v1(uuid,uuid,text,timestamp with time zone)'
  );
  IF function_name IS NULL THEN
    RAISE EXCEPTION '6BQ candidate executor is missing';
  END IF;

  SELECT owner_role.rolname
  INTO function_owner
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = function_name;

  IF function_owner IS DISTINCT FROM expected_reader
    OR NOT has_function_privilege(expected_reader, function_name, 'EXECUTE')
    OR has_function_privilege(expected_writer, function_name, 'EXECUTE')
    OR has_function_privilege('public', function_name, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
  THEN
    RAISE EXCEPTION
      '6BQ candidate executor is not isolated behind the reader role';
  END IF;

  SELECT class_row.oid
  INTO claims_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = class_row.relnamespace
  WHERE namespace_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_release_request_claims'
    AND class_row.relkind = 'r';

  IF claims_oid IS NULL THEN
    RAISE EXCEPTION '6BQ shared release request claim ledger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_oid
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%' || expected_claim_family || '%'
  ) THEN
    RAISE EXCEPTION '6BQ request claim family is not closed and recorded';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = attempts_oid
      AND NOT trigger_row.tgisinternal
      AND pg_catalog.pg_get_triggerdef(trigger_row.oid)
        ILIKE '%claim_management_report_release_request_v1%'
      AND pg_catalog.pg_get_triggerdef(trigger_row.oid)
        ILIKE '%follow_up_consent_ratio%'
  ) THEN
    RAISE EXCEPTION '6BQ release attempt request-claim trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = claims_oid
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
    RAISE EXCEPTION '6BQ request claim ledger is mutable';
  END IF;

  FOREACH function_role IN ARRAY ARRAY[
    'app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)',
    'app_private.assess_management_consent_ratio_report_pair_release_v1(jsonb,jsonb)',
    'app_private.validate_management_consent_ratio_report_release_attempt_v1()',
    'app_private.resolve_management_consent_ratio_report_release_auth_v1(uuid,uuid)',
    'app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
  ] LOOP
    function_name = to_regprocedure(function_role);
    IF function_name IS NULL THEN
      RAISE EXCEPTION '6BQ release function set is incomplete: %', function_role;
    END IF;

    SELECT
      pg_catalog.pg_get_functiondef(procedure_row.oid),
      owner_role.rolname,
      pg_catalog.pg_get_function_result(procedure_row.oid),
      procedure_row.proconfig,
      procedure_row.provolatile,
      procedure_row.prosecdef
    INTO
      function_definition,
      function_owner,
      function_result,
      function_config,
      function_volatility,
      function_security_definer
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE procedure_row.oid = function_name;

    expected_result := 'jsonb';
    expected_function_path := ARRAY['search_path=pg_catalog, app_private'];
    IF function_role LIKE '%release_management_follow_up_consent_ratio_report_snapshot_v1%'
    THEN
      expected_function_path := ARRAY[
        'search_path=pg_catalog, app_private, app_data'
      ];
      IF function_volatility <> 'v'
        OR function_config IS DISTINCT FROM expected_function_path
      THEN
        RAISE EXCEPTION '6BQ release function volatility/path/result drifted';
      END IF;
    ELSIF function_role LIKE '%validate_management_consent_ratio_report_release_attempt_v1%'
    THEN
      expected_result := 'trigger';
      expected_function_path := ARRAY[
        'search_path=pg_catalog, app_private'
      ];
      IF function_volatility <> 'v' THEN
        RAISE EXCEPTION '6BQ release-attempt validator must be VOLATILE';
      END IF;
    ELSIF function_role LIKE '%validate_management_follow_up_consent_ratio_report_document_v1%'
      OR function_role LIKE '%assess_management_consent_ratio_report_pair_release_v1%'
    THEN
      IF function_volatility <> 's' THEN
        RAISE EXCEPTION '6BQ document validator/assessor must be STABLE: %',
          function_role;
      END IF;
    ELSE
      IF function_volatility <> 'v' THEN
        RAISE EXCEPTION '6BQ authorization wrapper must be VOLATILE';
      END IF;
    END IF;

    IF function_config IS DISTINCT FROM expected_function_path THEN
      RAISE EXCEPTION '6BQ internal function search path drifted: %',
        function_role;
    END IF;

    IF function_owner IS DISTINCT FROM expected_writer
      OR function_result <> expected_result
      OR NOT function_security_definer
    THEN
      RAISE EXCEPTION '6BQ function owner/security/result drifted: %',
        function_role;
    END IF;

    IF has_function_privilege('public', function_name, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', function_name, 'EXECUTE')
    THEN
      RAISE EXCEPTION '6BQ private release function is executable by PUBLIC/runtime: %',
        function_role;
    END IF;
  END LOOP;

  function_name := to_regprocedure(
    'app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)'
  );
  SELECT pg_catalog.pg_get_functiondef(function_name)
  INTO function_definition;

  FOREACH required_column IN ARRAY ARRAY[
    'pg_advisory_xact_lock',
    'management-report-release-request:',
    'project-reporting-time-zone:',
    'management-follow-up-consent-ratio-report:',
    'release_management_reports',
    'contact_target_follow_up_consent_ratio_two_periods',
    'app_private.execute_management_follow_up_consent_ratio_report_v1',
    'previous_snapshot_id',
    'source_change_sequence',
    'release_cutoff_not_advanced',
    'release_time_zone_revision_changed'
  ] LOOP
    IF function_definition NOT ILIKE '%' || required_column || '%' THEN
      RAISE EXCEPTION
        '6BQ release function omits required contract token %',
        required_column;
    END IF;
  END LOOP;

  function_name := to_regprocedure(
    'app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)'
  );
  SELECT pg_catalog.pg_get_functiondef(function_name)
  INTO function_definition;
  FOREACH required_column IN ARRAY ARRAY[
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'statistical_unit',
    'period_boundary_id',
    'privacy_policy',
    'query_fingerprint',
    'period_results',
    'ratio',
    'coverage',
    'unknown_count',
    'excluded_count',
    'contact_target_link',
    'completed'
  ] LOOP
    IF function_definition NOT ILIKE '%' || required_column || '%' THEN
      RAISE EXCEPTION
        '6BQ candidate document validator omits %', required_column;
    END IF;
  END LOOP;

  function_name := to_regprocedure(
    'app_private.assess_management_consent_ratio_report_pair_release_v1(jsonb,jsonb)'
  );
  SELECT pg_catalog.pg_get_functiondef(function_name)
  INTO function_definition;
  FOREACH required_column IN ARRAY ARRAY[
    'shared_period_count',
    'no_shared_period',
    'shared_displayed_value_changed',
    'shared_privacy_status_changed'
  ] LOOP
    IF function_definition NOT ILIKE '%' || required_column || '%' THEN
      RAISE EXCEPTION '6BQ pair assessor omits %', required_column;
    END IF;
  END LOOP;

  function_name := to_regprocedure(
    'app_private.validate_management_consent_ratio_report_release_attempt_v1()'
  );
  SELECT pg_catalog.pg_get_functiondef(function_name)
  INTO function_definition;
  IF function_definition NOT ILIKE '%reason_codes%'
    OR function_definition NOT ILIKE '%result_document%'
  THEN
    RAISE EXCEPTION '6BQ release attempt validator is not value-free';
  END IF;

  function_name := to_regprocedure(
    'app_private.validate_management_report_snapshot_insert_v2()'
  );
  IF function_name IS NULL THEN
    RAISE EXCEPTION 'shared snapshot validator dispatcher is missing';
  END IF;
  SELECT pg_catalog.pg_get_functiondef(function_name)
  INTO function_definition;
  IF function_definition NOT ILIKE '%' || expected_report || '%'
    OR function_definition NOT ILIKE '%validate_management_follow_up_consent_ratio_report_document_v1%'
  THEN
    RAISE EXCEPTION
      'shared snapshot validator does not dispatch the 6BQ document';
  END IF;

  IF has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION '6BQ candidate reader can execute snapshot release';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'app_private.management_follow_up_consent_report_release_attempts',
    'app_private.management_report_snapshots',
    'app_private.management_report_release_request_claims'
  ] LOOP
    IF has_table_privilege('public', table_name, 'SELECT')
      OR has_table_privilege('tongxingzhe_runtime', table_name, 'SELECT')
    THEN
      RAISE EXCEPTION '6BQ private history table is readable by runtime: %',
        table_name;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0075_management_follow_up_consent_ratio_snapshot_lineage'
  ) <> 1 THEN
    RAISE EXCEPTION '6BQ migration was not recorded exactly once';
  END IF;
END
$check$;
