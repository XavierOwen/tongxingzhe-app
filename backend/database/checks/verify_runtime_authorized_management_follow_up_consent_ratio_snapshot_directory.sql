\set ON_ERROR_STOP on

-- Structural and least-privilege contract for the 6BV runtime bridge.  The
-- rollback fixture covers identity and delegated-directory behavior; this
-- check keeps the bridge's owner, ACL, search path and private boundary
-- explicit on a restored database.
DO $check$
DECLARE
  bridge regprocedure := to_regprocedure(
    'app_data.list_authorized_management_follow_up_consent_snapshots_v1(text,text,uuid)'
  );
  private_directory regprocedure := to_regprocedure(
    'app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid,uuid)'
  );
  function_definition text;
  function_owner text;
  private_owner text;
  function_config text[];
  function_volatility "char";
  function_security_definer boolean;
  forbidden_role text;
BEGIN
  IF bridge IS NULL OR private_directory IS NULL THEN
    RAISE EXCEPTION
      'runtime follow-up consent snapshot directory bridge is incomplete';
  END IF;

  SELECT
    pg_catalog.pg_get_userbyid(function_row.proowner),
    function_row.proconfig,
    function_row.provolatile,
    function_row.prosecdef,
    pg_catalog.pg_get_functiondef(function_row.oid)
  INTO
    function_owner,
    function_config,
    function_volatility,
    function_security_definer,
    function_definition
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = bridge;

  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT private_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid = private_directory;

  IF NOT function_security_definer
    OR function_volatility <> 'v'
    OR function_config IS DISTINCT FROM
      ARRAY['search_path=pg_catalog']::text[]
    OR function_owner IS DISTINCT FROM private_owner
    OR function_owner = ANY (ARRAY[
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
    ]::text[])
  THEN
    RAISE EXCEPTION
      'runtime follow-up consent snapshot directory bridge owner/security is incorrect';
  END IF;

  IF NOT has_function_privilege('tongxingzhe_runtime', bridge, 'EXECUTE')
    OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name =
          'list_authorized_management_follow_up_consent_snapshots_v1'
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION
      'runtime follow-up consent snapshot directory bridge ACL is incorrect';
  END IF;

  FOREACH forbidden_role IN ARRAY ARRAY[
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
  ] LOOP
    IF has_function_privilege(forbidden_role, bridge, 'EXECUTE') THEN
      RAISE EXCEPTION
        'forbidden role can execute runtime follow-up consent directory bridge: %',
        forbidden_role;
    END IF;
  END LOOP;

  -- Runtime crosses the boundary only through this wrapper.  It must not
  -- receive app_private usage, private-directory execution, private table
  -- access, or direct identity-table SELECT privileges.
  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege('tongxingzhe_runtime', private_directory, 'EXECUTE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_follow_up_consent_snapshot_directory_access_events',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
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

  IF function_definition IS NULL
    OR function_definition NOT ILIKE
      '%length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048%'
    OR function_definition NOT ILIKE
      '%length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512%'
    OR function_definition NOT ILIKE '%identity_row.issuer = trusted_issuer%'
    OR function_definition NOT ILIKE '%identity_row.subject = trusted_subject%'
    OR function_definition NOT ILIKE '%app_user.status = ''active''%'
    OR function_definition NOT ILIKE '%ERRCODE = ''22023''%'
    OR function_definition NOT ILIKE '%ERRCODE = ''42501''%'
    OR function_definition NOT ILIKE
      '%RETURN app_private.list_authorized_management_follow_up_consent_snapshots_v1(%'
    OR (
      SELECT count(*)
      FROM regexp_matches(function_definition, 'app_private\.', 'gi')
    ) <> 1
    OR function_definition ILIKE '%app_private.list_authorized_management_current_city%'
    OR function_definition ILIKE '%app_private.list_authorized_management_interest%'
    OR function_definition ILIKE '%app_private.list_authorized_management_original_region%'
    OR function_definition ILIKE '%app_private.read_authorized_management%'
    OR function_definition ILIKE '%bootstrap_personal_context%'
    OR function_definition ILIKE '%create_personal_project_context%'
    OR function_definition ILIKE '%identity_row.issuer = btrim%'
    OR function_definition ILIKE '%identity_row.subject = btrim%'
  THEN
    RAISE EXCEPTION
      'runtime follow-up consent snapshot directory bridge body contract is incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version =
      '0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory'
  ) <> 1 THEN
    RAISE EXCEPTION
      'runtime follow-up consent snapshot directory bridge migration was not recorded once';
  END IF;
END
$check$;
