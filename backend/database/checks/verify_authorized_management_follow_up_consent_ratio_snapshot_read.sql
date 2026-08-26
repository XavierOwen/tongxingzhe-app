\set ON_ERROR_STOP on

-- Structural and least-privilege contract for the 6BR private reader.  The
-- rollback fixture covers the result matrix; this check keeps its storage,
-- provenance, function and ACL boundary explicit on a restored database.
DO $check$
DECLARE
  snapshots_oid oid;
  attempts_oid oid;
  audit_oid oid;
  snapshot_owner text;
  audit_owner text;
  function_name regprocedure;
  function_definition text;
  function_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  role_name text;
  column_name text;
BEGIN
  snapshots_oid := to_regclass('app_private.management_report_snapshots');
  attempts_oid := to_regclass(
    'app_private.management_follow_up_consent_report_release_attempts'
  );
  audit_oid := to_regclass(
    'app_private.management_follow_up_consent_report_snapshot_access_events'
  );

  IF snapshots_oid IS NULL OR attempts_oid IS NULL OR audit_oid IS NULL THEN
    RAISE EXCEPTION
      'authorized follow-up consent snapshot read tables are incomplete';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT snapshot_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = snapshots_oid;
  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT audit_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = audit_oid;

  IF snapshot_owner IS DISTINCT FROM audit_owner THEN
    RAISE EXCEPTION
      'follow-up consent read audit owner does not match snapshot owner';
  END IF;

  IF snapshot_owner = ANY (ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_follow_up_consent_ratio_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer',
    'tongxingzhe_management_consent_ratio_snapshot_release_writer'
  ]::text[]) THEN
    RAISE EXCEPTION
      'follow-up consent read audit owner is externally scoped: %',
      snapshot_owner;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS class_row
    WHERE class_row.oid = snapshots_oid
      AND class_row.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'shared snapshot storage does not enforce row security';
  END IF;

  -- The access ledger is intentionally value-free.  Keep an exact allow-list
  -- so a later migration cannot add cells, ratios, source records or PII.
  FOREACH column_name IN ARRAY ARRAY[
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
    'follow_up_consent_release_request_id',
    'report_id',
    'report_version',
    'query_fingerprint',
    'release_lineage_id',
    'reporting_time_zone',
    'reporting_time_zone_version_number',
    'reporting_time_zone_effective_from_utc',
    'data_cutoff_utc',
    'previous_snapshot_id',
    'source_change_sequence',
    'accessed_at_utc',
    'result_status',
    'reason_code'
  ]::text[] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = audit_oid
        AND attribute_row.attnum > 0
        AND NOT attribute_row.attisdropped
        AND attribute_row.attname = column_name
    ) THEN
      RAISE EXCEPTION
        'follow-up consent read audit column is missing: %', column_name;
    END IF;
  END LOOP;

  IF (
    SELECT array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum)
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_oid
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
    'follow_up_consent_release_request_id',
    'report_id',
    'report_version',
    'query_fingerprint',
    'release_lineage_id',
    'reporting_time_zone',
    'reporting_time_zone_version_number',
    'reporting_time_zone_effective_from_utc',
    'data_cutoff_utc',
    'previous_snapshot_id',
    'source_change_sequence',
    'accessed_at_utc',
    'result_status',
    'reason_code'
  ]::text[] THEN
    RAISE EXCEPTION
      'follow-up consent read audit column set is not value-free metadata';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'protected_report', 'cells', 'periods', 'ratio', 'coverage',
        'value_count', 'privacy_status', 'contact_id', 'target_id',
        'contributor_id', 'contributor_key', 'raw_answer', 'email', 'phone',
        'pii'
      )
  ) THEN
    RAISE EXCEPTION
      'follow-up consent read audit contains protected values';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = audit_oid
      AND index_row.indexrelid =
        'app_private.management_consent_ratio_snapshot_access_events_project_idx'::regclass
  ) THEN
    RAISE EXCEPTION 'follow-up consent read audit index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_oid
      AND constraint_row.confrelid =
        'app_data.management_report_capability_grants'::regclass
      AND constraint_row.contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_oid
      AND constraint_row.confrelid = snapshots_oid
      AND constraint_row.contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_oid
      AND constraint_row.confrelid = attempts_oid
      AND constraint_row.contype = 'f'
  ) THEN
    RAISE EXCEPTION
      'follow-up consent read audit lineage foreign keys are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_oid
      AND trigger_row.tgname =
        'management_follow_up_consent_snapshot_access_events_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_oid
      AND trigger_row.tgname =
        'management_follow_up_consent_snapshot_access_events_validate'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION
      'follow-up consent read audit triggers are incomplete';
  END IF;

  -- Direct table access and private function execution stay closed to runtime,
  -- PUBLIC, ordinary report readers and every other release family.
  FOREACH role_name IN ARRAY ARRAY[
    'public',
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_follow_up_consent_ratio_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer',
    'tongxingzhe_management_consent_ratio_snapshot_release_writer'
  ]::text[] LOOP
    IF has_table_privilege(
        role_name, audit_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      ) THEN
      RAISE EXCEPTION
        'forbidden role can access follow-up consent read audit: %', role_name;
    END IF;
  END LOOP;

  IF has_table_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      snapshots_oid, 'SELECT'
    ) THEN
    RAISE EXCEPTION
      'follow-up consent report reader received direct snapshot access';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    to_regprocedure(
      'app_private.validate_management_follow_up_consent_snapshot_access_insert_v1()'
    ),
    to_regprocedure(
      'app_private.read_authorized_management_follow_up_consent_report_snapshot_v1(uuid,uuid,uuid)'
    )
  ]::regprocedure[] LOOP
    IF function_name IS NULL THEN
      RAISE EXCEPTION 'authorized follow-up consent snapshot read function is missing';
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
        'authorized follow-up consent function owner/security is incorrect: %',
        function_name;
    END IF;

    IF function_name = to_regprocedure(
        'app_private.validate_management_follow_up_consent_snapshot_access_insert_v1()'
      ) THEN
      IF function_config IS DISTINCT FROM ARRAY[
        'search_path=pg_catalog, app_private, app_data'
      ]::text[]
      OR function_definition NOT ILIKE '%view_anonymous_analytics%'
      OR function_definition NOT ILIKE
        '%management_follow_up_consent_report_release_attempts%'
      OR function_definition NOT ILIKE
        '%management_report_release_request_claims%'
      OR function_definition NOT ILIKE
        '%follow_up_consent_ratio_management_report_snapshot_release%'
      OR function_definition NOT ILIKE
        '%release_request_id = stored_snapshot.release_request_id%'
      OR function_definition NOT ILIKE
        '%validate_management_follow_up_consent_ratio_report_document_v1%'
      THEN
        RAISE EXCEPTION
          'follow-up consent snapshot access insert validator contract is incomplete';
      END IF;
    ELSE
      IF function_config IS DISTINCT FROM ARRAY[
        'search_path=pg_catalog, app_private'
      ]::text[]
      OR function_definition NOT ILIKE
        '%resolve_management_report_authorization_v1%'
      OR function_definition NOT ILIKE '%view_anonymous_analytics%'
      OR function_definition NOT ILIKE
        '%management_follow_up_consent_report_release_attempts%'
      OR function_definition NOT ILIKE
        '%management_report_release_request_claims%'
      OR function_definition NOT ILIKE
        '%follow_up_consent_ratio_management_report_snapshot_release%'
      OR function_definition NOT ILIKE '%source_change_sequence%'
      OR function_definition NOT ILIKE '%previous_snapshot_id%'
      OR function_definition NOT ILIKE
        '%validate_management_follow_up_consent_ratio_report_document_v1%'
      OR function_definition NOT ILIKE '%protected_report%'
      OR function_definition NOT ILIKE '%untrusted_provenance%'
      THEN
        RAISE EXCEPTION
          'authorized follow-up consent snapshot read contract is incomplete';
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
      'tongxingzhe_management_original_region_report_reader',
      'tongxingzhe_management_interest_report_reader',
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'tongxingzhe_management_interest_snapshot_release_writer',
      'tongxingzhe_management_original_region_snapshot_release_writer',
      'tongxingzhe_management_report_snapshot_lifecycle_writer',
      'tongxingzhe_management_follow_up_consent_config_writer',
      'tongxingzhe_management_consent_ratio_snapshot_release_writer'
    ]::text[] LOOP
      IF has_function_privilege(role_name, function_name, 'EXECUTE') THEN
        RAISE EXCEPTION
          'forbidden role can execute follow-up consent snapshot function: %/%',
          role_name,
          function_name;
      END IF;
    END LOOP;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0076_authorized_management_follow_up_consent_ratio_snapshot_read'
  ) <> 1 THEN
    RAISE EXCEPTION
      'authorized follow-up consent snapshot read migration was not recorded once';
  END IF;
END
$check$;
