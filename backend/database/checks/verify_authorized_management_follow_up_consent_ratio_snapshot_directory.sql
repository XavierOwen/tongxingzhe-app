\set ON_ERROR_STOP on

-- Structural and least-privilege contract for the 6BU private directory.
-- Behavioural cases belong to the rollback fixture; this check must also pass
-- on a restored database without fixture rows.  6BU intentionally does not
-- create an app_data identity bridge; that belongs to a later slice.
DO $check$
DECLARE
  private_directory regprocedure := to_regprocedure(
    'app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid,uuid)'
  );
  validation_trigger regprocedure := to_regprocedure(
    'app_private.validate_management_follow_up_consent_snapshot_directory_v1()'
  );
  private_source text;
  function_owner text;
  validation_owner text;
  snapshot_owner text;
  audit_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  audit_table_oid oid;
  role_name text;
BEGIN
  audit_table_oid = to_regclass(
    'app_private.management_follow_up_consent_snapshot_directory_access_events'
  );

  IF private_directory IS NULL
    OR validation_trigger IS NULL
    OR audit_table_oid IS NULL
  THEN
    RAISE EXCEPTION 'follow-up consent snapshot directory is incomplete';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT snapshot_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = 'app_private.management_report_snapshots'::regclass;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT audit_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = audit_table_oid;

  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT function_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  IF snapshot_owner IS DISTINCT FROM audit_owner
    OR snapshot_owner IS DISTINCT FROM function_owner
  THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory owner boundary is inconsistent';
  END IF;

  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT validation_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = validation_trigger;

  IF snapshot_owner IS DISTINCT FROM validation_owner THEN
    RAISE EXCEPTION
      'follow-up consent directory validation owner boundary is inconsistent';
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
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer',
    'tongxingzhe_management_follow_up_consent_ratio_reader',
    'tongxingzhe_management_consent_ratio_snapshot_release_writer'
  ]::text[]) THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory owner is externally scoped: %',
      snapshot_owner;
  END IF;

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
    'accessed_at_utc',
    'result_status',
    'returned_snapshot_count'
  ]::text[] THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory audit columns are not value-free metadata';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'snapshot_id', 'report_id', 'report_version', 'query_fingerprint',
        'release_lineage_id', 'source_change_sequence', 'protected_report',
        'periods', 'period_results', 'ratio', 'coverage', 'cells',
        'value_count', 'privacy_status', 'source_id', 'source_key',
        'contributor_id', 'contributor_key', 'target_id', 'contact_id',
        'external_subject', 'issuer', 'subject', 'raw_answer', 'email',
        'phone', 'token', 'pii'
      )
  ) THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory audit contains protected values';
  END IF;

  SELECT
    pg_catalog.pg_get_userbyid(function_row.proowner),
    function_row.proconfig,
    function_row.provolatile,
    function_row.prosecdef
  INTO
    function_owner,
    function_config,
    function_volatility,
    function_security_definer
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  IF function_owner IS DISTINCT FROM snapshot_owner
    OR function_config IS DISTINCT FROM ARRAY[
      'search_path=pg_catalog'
    ]::text[]
    OR function_volatility <> 'v'
    OR NOT function_security_definer
  THEN
    RAISE EXCEPTION
      'follow-up consent private directory function security is incorrect';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS function_row
    WHERE function_row.oid = validation_trigger
      AND (
        function_row.proconfig IS DISTINCT FROM ARRAY[
          'search_path=pg_catalog'
        ]::text[]
        OR function_row.provolatile <> 'v'
        OR NOT function_row.prosecdef
      )
  ) THEN
    RAISE EXCEPTION
      'follow-up consent directory validation trigger security is incorrect';
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
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer',
    'tongxingzhe_management_follow_up_consent_ratio_reader',
    'tongxingzhe_management_consent_ratio_snapshot_release_writer'
  ] LOOP
    IF has_function_privilege(role_name, private_directory, 'EXECUTE')
      OR has_function_privilege(role_name, validation_trigger, 'EXECUTE')
      OR has_table_privilege(
        role_name,
        audit_table_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION
        'forbidden role can access follow-up consent snapshot directory: %',
        role_name;
    END IF;
  END LOOP;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_follow_up_consent_report_release_attempts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_request_claims',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.app_users',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.external_identities',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION
      'runtime received direct follow-up consent directory access';
  END IF;

  SELECT function_row.prosrc
  INTO STRICT private_source
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  IF private_source !~* 'resolve_management_report_authorization_v1'
    OR private_source !~* 'view_anonymous_analytics'
    OR private_source !~* 'management_follow_up_consent_report_release_attempts'
    OR private_source !~* 'management_report_release_request_claims'
    OR private_source !~* 'follow_up_consent_ratio_management_report_snapshot_release'
    OR private_source !~* 'contact_target_follow_up_consent_ratio_two_periods'
    OR private_source !~* 'management-report:contact_target_follow_up_consent_ratio_two_periods:v1'
    OR private_source !~* 'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
    OR private_source !~* 'approved_baseline'
    OR private_source !~* 'approved'
    OR private_source !~* $$reason_codes[[:space:]]*=[[:space:]]*'\[\]'::jsonb$$
    OR private_source !~* 'report_version'
    OR private_source !~* 'attempt[.]release_request_id'
    OR private_source !~* 'attempt[.]requested_by_app_user_id'
    OR private_source !~* 'attempt[.]source_change_sequence'
    OR private_source !~* 'snapshot[.]previous_snapshot_id'
    OR private_source !~* 'project_reporting_time_zone_versions'
    OR private_source !~* 'LIMIT[[:space:]]+20'
    OR private_source !~* 'data_cutoff_utc[[:space:]]+DESC'
    OR private_source !~* 'released_at_utc[[:space:]]+DESC'
    OR private_source !~* 'snapshot_id[[:space:]]+DESC'
    OR private_source !~* 'returned_snapshot_count'
    OR private_source !~* 'result_status'
    OR private_source ~* 'list_authorized_management_report_snapshots_v1'
    OR private_source ~* 'read_authorized_management_report_snapshot_v1'
    OR private_source ~* 'current_city'
    OR private_source ~* 'interest_report'
    OR private_source ~* 'original_region'
    OR private_source ~* 'protected_report'
    OR private_source ~* 'period_results'
    OR private_source ~* 'jsonb_build_object[[:space:]]*[(][[:space:]]*''cells'''
  THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory fixed provenance, privacy, bound, or order contract is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table_oid
      AND trigger_row.tgname =
        'management_follow_up_consent_snapshot_directory_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table_oid
      AND trigger_row.tgname =
        'management_follow_up_consent_snapshot_directory_validate'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory audit triggers are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname = 'management_follow_up_consent_snapshot_directory_idx'
  ) THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory audit index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = audit_table_oid
      AND confrelid = 'app_data.management_report_capability_grants'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint
    WHERE conrelid = audit_table_oid
      AND confrelid = 'app_data.projects'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory audit foreign keys are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0078_authorized_management_follow_up_consent_ratio_snapshot_directory'
  ) <> 1 THEN
    RAISE EXCEPTION
      'follow-up consent snapshot directory migration was not recorded once';
  END IF;
END
$check$;
