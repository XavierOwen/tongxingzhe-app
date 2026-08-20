\set ON_ERROR_STOP on

DO $check$
DECLARE
  bridge regprocedure := to_regprocedure(
    'app_data.read_authorized_management_current_city_report_snapshot_v1(text,text,uuid,uuid)'
  );
  forbidden_role text;
BEGIN
  IF bridge IS NULL THEN
    RAISE EXCEPTION 'runtime current-city snapshot bridge is incomplete';
  END IF;

  IF (
    SELECT NOT function_row.prosecdef
      OR function_row.provolatile <> 'v'
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime current-city snapshot bridge is not protected';
  END IF;

  IF (
    SELECT function_row.proconfig IS DISTINCT FROM
      ARRAY['search_path=pg_catalog']::text[]
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) THEN
    RAISE EXCEPTION 'runtime current-city snapshot bridge search path is open';
  END IF;

  IF NOT has_function_privilege('tongxingzhe_runtime', bridge, 'EXECUTE')
    OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name =
          'read_authorized_management_current_city_report_snapshot_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION 'runtime current-city snapshot bridge ACL is incorrect';
  END IF;

  FOREACH forbidden_role IN ARRAY ARRAY[
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer'
  ] LOOP
    IF has_function_privilege(forbidden_role, bridge, 'EXECUTE') THEN
      RAISE EXCEPTION
        'forbidden role can execute current-city snapshot bridge: %',
        forbidden_role;
    END IF;
  END LOOP;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.read_authorized_management_current_city_report_snapshot_v1(uuid,uuid,uuid)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.read_authorized_management_report_snapshot_v1(uuid,uuid,uuid)',
      'EXECUTE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_current_city_report_snapshot_access_events',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_current_city_report_release_attempts',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_request_claims',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshot_access_events',
      'SELECT'
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
    RAISE EXCEPTION 'runtime received private current-city snapshot access';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS bridge_function
    JOIN pg_proc AS private_function
      ON private_function.oid =
        'app_private.read_authorized_management_current_city_report_snapshot_v1(uuid,uuid,uuid)'::regprocedure
    WHERE bridge_function.oid = bridge
      AND bridge_function.proowner <> private_function.proowner
  ) OR EXISTS (
    SELECT 1
    FROM pg_proc AS bridge_function
    JOIN pg_roles AS owner_role
      ON owner_role.oid = bridge_function.proowner
    WHERE bridge_function.oid = bridge
      AND owner_role.rolname IN (
        'tongxingzhe_runtime',
        'tongxingzhe_region_publisher',
        'tongxingzhe_region_mapping_writer',
        'tongxingzhe_contact_provenance_writer',
        'tongxingzhe_region_attribution_reader',
        'tongxingzhe_management_region_report_reader',
        'tongxingzhe_management_current_city_snapshot_release_writer'
      )
  ) THEN
    RAISE EXCEPTION 'runtime current-city bridge owner is outside the migration owner boundary';
  END IF;

  IF (
    SELECT function_row.prosrc
    FROM pg_proc AS function_row
    WHERE function_row.oid = bridge
  ) ~* 'app_private[.]read_authorized_management_report_snapshot_v1[[:space:]]*[(]'
    OR (
      SELECT function_row.prosrc
      FROM pg_proc AS function_row
      WHERE function_row.oid = bridge
    ) !~* 'RETURN[[:space:]]+app_private[.]read_authorized_management_current_city_report_snapshot_v1[[:space:]]*[(]'
    OR (
      SELECT function_row.prosrc
      FROM pg_proc AS function_row
      WHERE function_row.oid = bridge
    ) ~* 'bootstrap_personal_context|session_context|create_personal_project_context'
  THEN
    RAISE EXCEPTION 'runtime bridge does not call only the current-city read';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0059_runtime_authorized_management_current_city_report_snapshot_read'
  ) <> 1 THEN
    RAISE EXCEPTION 'runtime current-city snapshot bridge migration was not recorded once';
  END IF;
END
$check$;
