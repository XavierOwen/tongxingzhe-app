\set ON_ERROR_STOP on
DO $check$
DECLARE
  directory_oid oid := to_regprocedure(
    'app_data.list_organization_deletion_eligible_for_identity_v1(text,text)');
  trusted_owner oid;
  function_definition text;
  table_name text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0106_organization_deletion_eligibility') <> 1 THEN
    RAISE EXCEPTION '0106 migration not recorded exactly once';
  END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF directory_oid IS NULL
    OR pg_get_function_result(directory_oid) IS DISTINCT FROM
      'TABLE(organization_workspace_id uuid)'
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = directory_oid
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog']::text[])
    OR NOT has_function_privilege('tongxingzhe_runtime', directory_oid, 'EXECUTE')
    OR has_function_privilege('public', directory_oid, 'EXECUTE')
  THEN RAISE EXCEPTION '0106 typed result, trusted owner, security, or ACL drift'; END IF;

  SELECT pg_get_functiondef(directory_oid) INTO STRICT function_definition;
  IF (length(function_definition) - length(replace(function_definition, 'clock_timestamp()', '')))
      / length('clock_timestamp()') <> 1
    OR strpos(function_definition, 'observation AS MATERIALIZED') = 0
    OR strpos(function_definition, 'LEFT JOIN LATERAL') = 0
    OR strpos(function_definition, 'organization_owner_assignments') = 0
    OR strpos(function_definition, 'workspace.deleted_at IS NULL') = 0
    OR strpos(function_definition, 'attempt.status = ''restored''') = 0
    OR strpos(function_definition, 'ORDER BY eligible.workspace_id') = 0
    OR function_definition ~* '\m(INSERT|UPDATE|DELETE|LIMIT|pg_advisory_xact_lock)\M'
    OR strpos(function_definition, 'organization_deletion_request_claims') > 0
    OR strpos(function_definition, 'organization_deletion_restore_claims') > 0
    OR strpos(function_definition, 'organization_deletion_audit_events') > 0
  THEN RAISE EXCEPTION '0106 single-clock read-only observation contract drift'; END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'app_data.external_identities', 'app_data.app_users', 'app_data.workspaces',
    'app_data.organization_memberships', 'app_data.organization_owner_assignments',
    'app_private.organization_deletion_current', 'app_private.organization_deletion_request_claims',
    'app_private.organization_deletion_restore_claims', 'app_private.organization_deletion_audit_events'
  ] LOOP
    IF has_table_privilege('tongxingzhe_runtime', table_name, 'SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION '0106 runtime has direct table privileges: %', table_name;
    END IF;
  END LOOP;
END
$check$;
