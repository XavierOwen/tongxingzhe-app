\set ON_ERROR_STOP on

-- Structural and least-privilege contract for the 6BK original-region
-- snapshot directory. Behavioural cases belong to the rollback fixture; this
-- check must also pass on a restored database without fixture rows.
DO $check$
DECLARE
  private_directory regprocedure := to_regprocedure(
    'app_private.list_authorized_management_original_region_report_snapshots_v1(uuid,uuid)'
  );
  runtime_bridge regprocedure := to_regprocedure(
    'app_data.list_authorized_management_original_region_report_snapshots_v1(text,text,uuid)'
  );
  validation_trigger regprocedure := to_regprocedure(
    'app_private.validate_original_region_snapshot_directory_access_v1()'
  );
  private_source text;
  bridge_source text;
  forbidden_role text;
  audit_table_oid oid;
  snapshot_owner text;
  audit_owner text;
  private_owner text;
  bridge_owner text;
BEGIN
  IF private_directory IS NULL
    OR runtime_bridge IS NULL
    OR validation_trigger IS NULL
    OR to_regclass(
      'app_private.management_original_region_snapshot_directory_access_events'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'original-region snapshot directory is incomplete';
  END IF;

  audit_table_oid =
    'app_private.management_original_region_snapshot_directory_access_events'::regclass;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT snapshot_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = 'app_private.management_report_snapshots'::regclass;

  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT audit_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = audit_table_oid;

  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT private_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT bridge_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = runtime_bridge;

  IF snapshot_owner IS DISTINCT FROM audit_owner
    OR snapshot_owner IS DISTINCT FROM private_owner
    OR snapshot_owner IS DISTINCT FROM bridge_owner
  THEN
    RAISE EXCEPTION
      'original-region snapshot directory owner boundary is inconsistent';
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
    'tongxingzhe_management_report_snapshot_lifecycle_writer'
  ]::text[]) THEN
    RAISE EXCEPTION
      'original-region snapshot directory owner is externally scoped: %',
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
      'original-region snapshot directory audit columns are not value-free metadata';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_table_oid
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'snapshot_id', 'report_id', 'report_version', 'query_fingerprint',
        'release_lineage_id', 'source_tree_version',
        'source_content_fingerprint', 'source_change_sequence',
        'protected_report', 'cells', 'value_count', 'privacy_status',
        'contact_id', 'contributor_id', 'contributor_key', 'source_id',
        'place_name', 'canonical_name', 'latitude', 'longitude', 'geometry',
        'email', 'phone', 'token', 'pii'
      )
  ) THEN
    RAISE EXCEPTION 'original-region snapshot directory audit contains values';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS function_row
    WHERE function_row.oid IN (private_directory, validation_trigger)
      AND function_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
  ) THEN
    RAISE EXCEPTION 'original-region snapshot directory search path is open';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS function_row
    WHERE function_row.oid IN (private_directory, validation_trigger)
      AND (
        NOT function_row.prosecdef
        OR function_row.provolatile <> 'v'
      )
  ) THEN
    RAISE EXCEPTION
      'original-region private directory functions are not protected';
  END IF;

  IF (
    SELECT NOT function_row.prosecdef
      OR function_row.provolatile <> 'v'
    FROM pg_proc AS function_row
    WHERE function_row.oid = runtime_bridge
  ) OR (
    SELECT function_row.proconfig IS DISTINCT FROM
      ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc AS function_row
    WHERE function_row.oid = runtime_bridge
  ) THEN
    RAISE EXCEPTION 'original-region snapshot directory bridge is not protected';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      runtime_bridge,
      'EXECUTE'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name =
          'list_authorized_management_original_region_report_snapshots_v1'
        AND grantee = 'PUBLIC'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_private'
        AND routine_name =
          'list_authorized_management_original_region_report_snapshots_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION
      'original-region snapshot directory public/private ACL is incorrect';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      private_directory,
      'EXECUTE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      validation_trigger,
      'EXECUTE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_original_region_snapshot_directory_access_events',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_original_region_report_release_attempts',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_request_claims',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.app_users',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.external_identities',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION
      'runtime received original-region snapshot directory access';
  END IF;

  FOREACH forbidden_role IN ARRAY ARRAY[
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
    'tongxingzhe_management_report_snapshot_lifecycle_writer'
  ] LOOP
    IF has_function_privilege(forbidden_role, runtime_bridge, 'EXECUTE')
      OR has_function_privilege(forbidden_role, private_directory, 'EXECUTE')
      OR has_function_privilege(forbidden_role, validation_trigger, 'EXECUTE')
      OR has_table_privilege(
        forbidden_role,
        'app_private.management_original_region_snapshot_directory_access_events',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION
        'forbidden role can access original-region snapshot directory: %',
        forbidden_role;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS bridge_function
    JOIN pg_proc AS private_function
      ON private_function.oid = private_directory
    WHERE bridge_function.oid = runtime_bridge
      AND bridge_function.proowner <> private_function.proowner
  ) OR EXISTS (
    SELECT 1
    FROM pg_proc AS bridge_function
    JOIN pg_roles AS owner_role
      ON owner_role.oid = bridge_function.proowner
    WHERE bridge_function.oid = runtime_bridge
      AND owner_role.rolname IN (
        'tongxingzhe_runtime',
        'tongxingzhe_region_publisher',
        'tongxingzhe_region_mapping_writer',
        'tongxingzhe_contact_provenance_writer',
        'tongxingzhe_management_region_report_reader',
        'tongxingzhe_management_original_region_report_reader',
        'tongxingzhe_management_interest_report_reader',
        'tongxingzhe_management_current_city_snapshot_release_writer',
        'tongxingzhe_management_interest_snapshot_release_writer',
        'tongxingzhe_management_original_region_snapshot_release_writer',
        'tongxingzhe_management_report_snapshot_lifecycle_writer'
      )
  ) THEN
    RAISE EXCEPTION
      'original-region snapshot directory bridge owner is unsafe';
  END IF;

  SELECT function_row.prosrc
  INTO private_source
  FROM pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  SELECT function_row.prosrc
  INTO bridge_source
  FROM pg_proc AS function_row
  WHERE function_row.oid = runtime_bridge;

  IF bridge_source !~* $$RETURN[[:space:]]+app_private[.]list_authorized_management_original_region_report_snapshots_v1[[:space:]]*[(]$$
    OR (
      SELECT count(*)
      FROM regexp_matches(bridge_source, 'app_private[.]', 'gi')
    ) <> 1
    OR bridge_source ~* 'list_authorized_management_report_snapshots_v1|read_authorized_management_report_snapshot_v1|read_authorized_management_current_city_report_snapshot_v1|read_authorized_management_interest_report_snapshot_v1|bootstrap_personal_context|session_context|create_personal_project_context'
    OR bridge_source ~* 'btrim[[:space:]]*[(][[:space:]]*identity_row[.](issuer|subject)'
    OR bridge_source NOT ILIKE '%length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048%'
    OR bridge_source NOT ILIKE '%length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512%'
    OR bridge_source NOT ILIKE '%identity_row.issuer = trusted_issuer%'
    OR bridge_source NOT ILIKE '%identity_row.subject = trusted_subject%'
    OR bridge_source NOT ILIKE '%app_user.status = ''active''%'
    OR bridge_source NOT ILIKE '%ERRCODE = ''22023''%'
    OR bridge_source NOT ILIKE '%ERRCODE = ''42501''%'
    OR private_source ~* 'list_authorized_management_report_snapshots_v1|read_authorized_management_report_snapshot_v1|read_authorized_management_current_city_report_snapshot_v1|read_authorized_management_interest_report_snapshot_v1'
    OR private_source !~* 'resolve_management_report_authorization_v1'
  THEN
    RAISE EXCEPTION
      'original-region snapshot directory does not use its narrow bridge';
  END IF;

  -- Keep a later edit from broadening the directory to another report family,
  -- untrusted provenance, or an unbounded/unstable ordering.
  IF private_source !~ $$contact_sessions_by_original_region_two_periods$$
    OR private_source !~ $$management-report:contact_sessions_by_original_region_two_periods:v1$$
    OR private_source !~ $$management-original-region-report:contact_sessions_by_original_region_two_periods$$
    OR private_source !~ $$original_region_management_report_snapshot_release$$
    OR private_source !~ $$approved_baseline$$
    OR private_source !~ $$approved$$
    OR private_source !~ $$report_version[[:space:]]*=[[:space:]]*1$$
    OR private_source !~ $$reason_codes[[:space:]]*=[[:space:]]*'\[\]'::jsonb$$
    OR private_source !~ $$reporting_time_zone[[:space:]]*=[[:space:]]*snapshot[.]reporting_time_zone$$
    OR private_source !~ $$data_cutoff_utc[[:space:]]*=[[:space:]]*snapshot[.]data_cutoff_utc$$
    OR private_source !~ $$compared_snapshot_id[[:space:]]+IS[[:space:]]+NOT[[:space:]]+DISTINCT[[:space:]]+FROM[[:space:]]+snapshot[.]previous_snapshot_id$$
    OR private_source !~ $$attempt[.]release_request_id[[:space:]]*=[[:space:]]*snapshot[.]release_request_id$$
    OR private_source !~ $$attempt[.]requested_by_app_user_id[[:space:]]*=[[:space:]]*snapshot[.]created_by_app_user_id$$
    OR private_source !~ $$attempt[.]capability_id[[:space:]]*=.*release_management_reports$$
    OR private_source !~ $$attempt[.]source_change_sequence[[:space:]]*=[[:space:]]*snapshot[.]source_change_sequence$$
    OR private_source !~ $$attempt[.]source_tree_version[[:space:]]*=[[:space:]]*$$
    OR private_source !~ $$attempt[.]source_content_fingerprint[[:space:]]*=[[:space:]]*$$
    OR private_source !~ $$project_reporting_time_zone_versions$$
    OR private_source !~ $$LIMIT[[:space:]]+20$$
    OR private_source !~ $$data_cutoff_utc[[:space:]]+DESC$$
    OR private_source !~ $$released_at_utc[[:space:]]+DESC$$
    OR private_source !~ $$snapshot_id[[:space:]]+DESC$$
    OR private_source ~* 'jsonb_build_object[[:space:]]*[(][[:space:]]*''protected_report'''
    OR private_source ~* 'jsonb_build_object[[:space:]]*[(][[:space:]]*''cells'''
  THEN
    RAISE EXCEPTION
      'original-region snapshot directory fixed provenance, privacy, bound, or order contract is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table_oid
      AND trigger_row.tgname =
        'management_original_region_snapshot_directory_access_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table_oid
      AND trigger_row.tgname =
        'management_original_region_snapshot_directory_access_validate'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION
      'original-region snapshot directory audit triggers are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname =
        'management_original_region_snapshot_directory_idx'
  ) THEN
    RAISE EXCEPTION
      'original-region snapshot directory audit index is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_private'
      AND table_name =
      'management_original_region_snapshot_directory_access_events'
      AND grantee IN (
        'PUBLIC',
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
        'tongxingzhe_management_report_snapshot_lifecycle_writer'
      )
  ) THEN
    RAISE EXCEPTION
      'original-region snapshot directory audit privilege matrix is open';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = audit_table_oid
      AND confrelid = 'app_data.management_report_capability_grants'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = audit_table_oid
      AND confrelid = 'app_data.projects'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION
      'original-region snapshot directory audit foreign keys are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0071_authorized_management_original_region_report_snapshot_directory'
  ) <> 1 THEN
    RAISE EXCEPTION
      'original-region snapshot directory migration was not recorded once';
  END IF;
END
$check$;
