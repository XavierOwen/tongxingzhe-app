\set ON_ERROR_STOP on

-- Structural, contract and least-privilege checks for Slice 6AX. Behavioural
-- authorized-read cases belong to the companion fixture; this check keeps the
-- private function, audit table and 6AW provenance boundary explicit.
DO $check$
DECLARE
  snapshots_table_oid oid;
  audit_table_oid oid;
  attempts_table_oid oid;
  snapshot_owner text;
  audit_owner text;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  role_name text;
BEGIN
  SELECT class_row.oid
  INTO snapshots_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_report_snapshots'
    AND class_row.relkind IN ('r', 'p');

  SELECT class_row.oid
  INTO audit_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname =
      'management_interest_report_snapshot_access_events'
    AND class_row.relkind IN ('r', 'p');

  SELECT class_row.oid
  INTO attempts_table_oid
  FROM pg_catalog.pg_class AS class_row
  JOIN pg_catalog.pg_namespace AS schema_row
    ON schema_row.oid = class_row.relnamespace
  WHERE schema_row.nspname = 'app_private'
    AND class_row.relname = 'management_interest_report_release_attempts'
    AND class_row.relkind IN ('r', 'p');

  IF snapshots_table_oid IS NULL
    OR audit_table_oid IS NULL
    OR attempts_table_oid IS NULL
  THEN
    RAISE EXCEPTION
      'authorized interest snapshot read tables are incomplete';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO snapshot_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = snapshots_table_oid;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO audit_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = audit_table_oid;

  IF snapshot_owner IS DISTINCT FROM audit_owner THEN
    RAISE EXCEPTION
      'interest snapshot access audit owner does not match snapshot owner';
  END IF;

  IF snapshot_owner = ANY (ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer'
  ]::text[]) THEN
    RAISE EXCEPTION
      'interest snapshot access owner is an externally scoped role: %',
      snapshot_owner;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = snapshots_table_oid
      AND class_row.relrowsecurity
  ) THEN
    RAISE EXCEPTION
      'shared management snapshot row security is not enabled';
  END IF;

  -- The access audit is value-free by construction. Keep both a required
  -- metadata allow-list and a sensitive-column deny-list in the structural
  -- contract so a future migration cannot silently add report values.
  FOREACH role_name IN ARRAY ARRAY[
    'access_event_id',
    'requested_by_app_user_id',
    'organization_workspace_id',
    'organization_membership_id',
    'project_membership_id',
    'capability_grant_id',
    'capability_id',
    'authorization_reference_at_utc',
    'project_id',
    'requested_snapshot_id',
    'resolved_snapshot_id',
    'interest_release_request_id',
    'report_id',
    'report_version',
    'query_fingerprint',
    'release_lineage_id',
    'reporting_time_zone',
    'data_cutoff_utc',
    'source_change_sequence',
    'accessed_at_utc',
    'result_status',
    'reason_code'
  ]::text[]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = audit_table_oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND attribute_row.attname = role_name
    ) THEN
      RAISE EXCEPTION
        'interest snapshot access audit column is missing: %', role_name;
    END IF;
  END LOOP;

  IF (
    SELECT array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum)
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
  ) IS DISTINCT FROM ARRAY[
    'access_event_id',
    'requested_by_app_user_id',
    'organization_workspace_id',
    'organization_membership_id',
    'project_membership_id',
    'capability_grant_id',
    'capability_id',
    'authorization_reference_at_utc',
    'project_id',
    'requested_snapshot_id',
    'resolved_snapshot_id',
    'interest_release_request_id',
    'report_id',
    'report_version',
    'query_fingerprint',
    'release_lineage_id',
    'reporting_time_zone',
    'data_cutoff_utc',
    'source_change_sequence',
    'accessed_at_utc',
    'result_status',
    'reason_code'
  ]::text[] THEN
    RAISE EXCEPTION
      'interest snapshot access audit column set is not value-free metadata';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'protected_report',
        'cells',
        'value_count',
        'contact_id',
        'contributor_id',
        'contributor_key',
        'place_name',
        'raw_answer',
        'pii'
      )
  ) THEN
    RAISE EXCEPTION
      'interest snapshot access audit contains protected report values';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = audit_table_oid
      AND index_row.indexrelid =
        'app_private.management_interest_snapshot_access_events_project_idx'::regclass
  ) THEN
    RAISE EXCEPTION 'interest snapshot access audit index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table_oid
      AND constraint_row.confrelid =
        'app_data.management_report_capability_grants'::regclass
      AND constraint_row.contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table_oid
      AND constraint_row.confrelid = snapshots_table_oid
      AND constraint_row.contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table_oid
      AND constraint_row.confrelid = attempts_table_oid
      AND constraint_row.contype = 'f'
  ) THEN
    RAISE EXCEPTION 'interest snapshot access audit lineage foreign keys are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table_oid
      AND trigger_row.tgname =
        'management_interest_snapshot_access_events_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table_oid
      AND trigger_row.tgname =
        'management_interest_snapshot_access_events_validate'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'interest snapshot access audit triggers are incomplete';
  END IF;

  -- No database role outside the private function owner may read or write the
  -- audit. In particular, 0061's source reader and 0062's release writer are
  -- intentionally not authorized readers.
  FOREACH role_name IN ARRAY ARRAY[
    'public',
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer'
  ]::text[]
  LOOP
    IF has_table_privilege(
        role_name,
        audit_table_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      ) THEN
      RAISE EXCEPTION
        'forbidden role can access interest snapshot audit: %', role_name;
    END IF;
  END LOOP;

  IF has_table_privilege(
      'tongxingzhe_management_interest_report_reader',
      snapshots_table_oid,
      'SELECT'
    )
  THEN
    RAISE EXCEPTION
      '6AV interest report reader received direct snapshot access';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_interest_snapshot_access_insert_v1()'
    ),
    to_regprocedure(
      'app_private.read_authorized_management_interest_report_snapshot_v1(uuid,uuid,uuid)'
    )
  ]::regprocedure[]
  LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'authorized interest snapshot read function is missing';
    END IF;

    SELECT
      pg_catalog.pg_get_userbyid(procedure_row.proowner),
      procedure_row.proconfig,
      procedure_row.provolatile,
      procedure_row.prosecdef,
      pg_catalog.pg_get_functiondef(procedure_row.oid)
    INTO
      function_owner,
      function_config,
      function_volatility,
      function_security_definer,
      function_definition
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = function_name;

    IF function_owner IS DISTINCT FROM snapshot_owner
      OR NOT function_security_definer
      OR function_volatility <> 'v'
      OR function_definition IS NULL
    THEN
      RAISE EXCEPTION
        'authorized interest snapshot function owner/security is incorrect: %',
        function_name;
    END IF;

    IF function_name = to_regprocedure(
        'app_private.validate_management_interest_snapshot_access_insert_v1()'
      )
    THEN
      IF function_config IS DISTINCT FROM ARRAY[
        'search_path=pg_catalog, app_private, app_data'
      ]::text[]
      OR function_definition NOT ILIKE
        '%view_anonymous_analytics%'
      OR function_definition NOT ILIKE
        '%management_interest_report_release_attempts%'
      OR function_definition NOT ILIKE
        '%management_report_release_request_claims%'
      OR function_definition NOT ILIKE
        '%interest_management_report_snapshot_release%'
      OR function_definition NOT ILIKE
        '%attempt.release_request_id = stored_snapshot.release_request_id%'
      OR function_definition NOT ILIKE
        '%validate_management_interest_report_document_v1%'
      THEN
        RAISE EXCEPTION
          'interest snapshot access insert validator contract is incomplete';
      END IF;
    ELSE
      IF function_config IS DISTINCT FROM ARRAY[
        'search_path=pg_catalog, app_private'
      ]::text[]
      OR function_definition NOT ILIKE
        '%resolve_management_report_authorization_v1%'
      OR function_definition NOT ILIKE
        '%view_anonymous_analytics%'
      OR function_definition NOT ILIKE
        '%management_interest_report_release_attempts%'
      OR function_definition NOT ILIKE
        '%management_report_release_request_claims%'
      OR function_definition NOT ILIKE
        '%interest_management_report_snapshot_release%'
      OR function_definition NOT ILIKE
        '%source_change_sequence%'
      OR function_definition NOT ILIKE
        '%previous_snapshot_id%'
      OR function_definition NOT ILIKE
        '%validate_management_interest_report_document_v1%'
      OR function_definition NOT ILIKE '%protected_report%'
      OR function_definition NOT ILIKE '%untrusted_provenance%'
      THEN
        RAISE EXCEPTION
          'authorized interest snapshot read contract is incomplete';
      END IF;
    END IF;

    FOREACH role_name IN ARRAY ARRAY[
      'public',
      'tongxingzhe_runtime',
      'tongxingzhe_region_publisher',
      'tongxingzhe_region_mapping_writer',
      'tongxingzhe_contact_provenance_writer',
      'tongxingzhe_region_attribution_reader',
      'tongxingzhe_management_region_report_reader',
      'tongxingzhe_management_interest_report_reader',
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'tongxingzhe_management_interest_snapshot_release_writer'
    ]::text[]
    LOOP
      IF has_function_privilege(role_name, function_name, 'EXECUTE') THEN
        RAISE EXCEPTION
          'forbidden role can execute interest snapshot read function: % / %',
          role_name,
          function_name;
      END IF;
    END LOOP;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0063_authorized_management_interest_report_snapshot_read'
  ) <> 1 THEN
    RAISE EXCEPTION
      'authorized interest snapshot read migration was not recorded once';
  END IF;
END
$check$;
