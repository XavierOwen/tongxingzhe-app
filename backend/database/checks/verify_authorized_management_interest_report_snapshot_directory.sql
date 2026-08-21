\set ON_ERROR_STOP on

DO $check$
DECLARE
  private_directory regprocedure := to_regprocedure(
    'app_private.list_authorized_management_interest_report_snapshots_v1(uuid,uuid)'
  );
  runtime_bridge regprocedure := to_regprocedure(
    'app_data.list_authorized_management_interest_report_snapshots_v1(text,text,uuid)'
  );
  validation_trigger regprocedure := to_regprocedure(
    'app_private.validate_management_interest_snapshot_directory_access_v1()'
  );
  private_source text;
  bridge_source text;
  forbidden_role text;
  audit_table_oid oid;
BEGIN
  IF private_directory IS NULL
    OR runtime_bridge IS NULL
    OR validation_trigger IS NULL
    OR to_regclass(
      'app_private.management_interest_report_snapshot_directory_access_events'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'interest snapshot directory is incomplete';
  END IF;

  audit_table_oid =
    'app_private.management_interest_report_snapshot_directory_access_events'::regclass;

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
      'interest snapshot directory audit columns are not value-free metadata';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS function_row
    WHERE function_row.oid IN (private_directory, validation_trigger)
      AND function_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
  ) THEN
    RAISE EXCEPTION 'interest snapshot directory search path is open';
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
    RAISE EXCEPTION 'interest snapshot directory bridge is not protected';
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
          'list_authorized_management_interest_report_snapshots_v1'
        AND grantee = 'PUBLIC'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_private'
        AND routine_name =
          'list_authorized_management_interest_report_snapshots_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION
      'interest snapshot directory public/private ACL is incorrect';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      private_directory,
      'EXECUTE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_interest_report_snapshot_directory_access_events',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_interest_report_release_attempts',
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
    RAISE EXCEPTION 'runtime received interest snapshot directory access';
  END IF;

  FOREACH forbidden_role IN ARRAY ARRAY[
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_interest_report_reader'
  ] LOOP
    IF has_function_privilege(forbidden_role, runtime_bridge, 'EXECUTE')
      OR has_function_privilege(forbidden_role, private_directory, 'EXECUTE')
      OR has_table_privilege(
        forbidden_role,
        'app_private.management_interest_report_snapshot_directory_access_events',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION
        'forbidden role can access interest snapshot directory: %',
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
        'tongxingzhe_region_attribution_reader',
        'tongxingzhe_management_region_report_reader',
        'tongxingzhe_management_current_city_snapshot_release_writer',
        'tongxingzhe_management_interest_snapshot_release_writer',
        'tongxingzhe_management_interest_report_reader'
      )
  ) THEN
    RAISE EXCEPTION 'interest snapshot directory bridge owner is unsafe';
  END IF;

  IF (
    SELECT function_row.prosrc
    FROM pg_proc AS function_row
    WHERE function_row.oid = runtime_bridge
  ) !~* 'RETURN[[:space:]]+app_private[.]list_authorized_management_interest_report_snapshots_v1[[:space:]]*[(]'
    OR (
      SELECT function_row.prosrc
      FROM pg_proc AS function_row
      WHERE function_row.oid = runtime_bridge
    ) ~* 'list_authorized_management_report_snapshots_v1|read_authorized_management_report_snapshot_v1|read_authorized_management_interest_report_snapshot_v1|bootstrap_personal_context|session_context|create_personal_project_context'
    OR (
      SELECT function_row.prosrc
      FROM pg_proc AS function_row
      WHERE function_row.oid = private_directory
    ) ~* 'list_authorized_management_report_snapshots_v1|read_authorized_management_report_snapshot_v1|read_authorized_management_interest_report_snapshot_v1'
    OR (
      SELECT function_row.prosrc
      FROM pg_proc AS function_row
      WHERE function_row.oid = private_directory
    ) !~* 'management_interest_report_release_attempts|management_report_release_request_claims'
  THEN
    RAISE EXCEPTION 'interest snapshot directory does not use its narrow bridge';
  END IF;

  SELECT function_row.prosrc
  INTO private_source
  FROM pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  SELECT function_row.prosrc
  INTO bridge_source
  FROM pg_proc AS function_row
  WHERE function_row.oid = runtime_bridge;

  -- The directory is deliberately a separate interest contract.  These
  -- checks keep a later edit from silently broadening it to another report,
  -- release family, provenance state, or unbounded ordering.
  IF private_source !~ $$contact_sessions_by_interest_level_two_periods$$
    OR private_source !~ $$management-report:contact_sessions_by_interest_level_two_periods:v1$$
    OR private_source !~ $$management-interest-report:contact_sessions_by_interest_level_two_periods$$
    OR private_source !~ $$interest_management_report_snapshot_release$$
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
    OR private_source !~ $$project_reporting_time_zone_versions$$
    OR private_source !~ $$LIMIT[[:space:]]+20$$
    OR private_source !~ $$data_cutoff_utc[[:space:]]+DESC$$
    OR private_source !~ $$released_at_utc[[:space:]]+DESC$$
    OR private_source !~ $$snapshot_id[[:space:]]+DESC$$
  THEN
    RAISE EXCEPTION
      'interest snapshot directory fixed provenance, bound, or order contract is incomplete';
  END IF;

  IF bridge_source ~* 'btrim[[:space:]]*[(][[:space:]]*identity_row[.](issuer|subject)'
    OR bridge_source ~* 'app_private[.]management_report_snapshots[[:space:]]+AS[[:space:]]+snapshot'
  THEN
    RAISE EXCEPTION 'interest snapshot directory bridge contains an unsafe alias or reader';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
        'app_private.management_interest_report_snapshot_directory_access_events'::regclass
      AND trigger_row.tgname =
        'management_interest_snapshot_directory_access_immutable'
      AND NOT trigger_row.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid =
        'app_private.management_interest_report_snapshot_directory_access_events'::regclass
      AND trigger_row.tgname =
        'management_interest_snapshot_directory_access_validate'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'interest snapshot directory audit triggers are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname =
        'management_interest_snapshot_directory_access_project_idx'
  ) THEN
    RAISE EXCEPTION 'interest snapshot directory audit index is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_private'
      AND table_name =
        'management_interest_report_snapshot_directory_access_events'
      AND grantee IN (
        'PUBLIC',
        'tongxingzhe_runtime',
        'tongxingzhe_region_publisher',
        'tongxingzhe_region_mapping_writer',
        'tongxingzhe_contact_provenance_writer',
        'tongxingzhe_region_attribution_reader',
        'tongxingzhe_management_region_report_reader',
        'tongxingzhe_management_current_city_snapshot_release_writer',
        'tongxingzhe_management_interest_snapshot_release_writer',
        'tongxingzhe_management_interest_report_reader'
      )
  ) THEN
    RAISE EXCEPTION 'interest snapshot directory audit privilege matrix is open';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_interest_report_snapshot_directory_access_events'::regclass
      AND confrelid = 'app_data.management_report_capability_grants'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_interest_report_snapshot_directory_access_events'::regclass
      AND confrelid = 'app_data.projects'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'interest snapshot directory audit foreign keys are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0065_authorized_management_interest_report_snapshot_directory'
  ) <> 1 THEN
    RAISE EXCEPTION 'interest snapshot directory migration was not recorded once';
  END IF;
END
$check$;
