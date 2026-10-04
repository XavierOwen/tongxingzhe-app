\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  directory_oid oid := to_regprocedure(
    'app_data.list_organization_deletion_recovery_for_identity_v1(text,text)'
  );
  function_definition text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0101_organization_deletion_recovery_directory') <> 1 THEN
    RAISE EXCEPTION '0101 migration not recorded exactly once';
  END IF;

  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF directory_oid IS NULL
    OR pg_get_function_result(directory_oid) IS DISTINCT FROM
      'TABLE(organization_deletion_recovery_directory_contract_id text, observed_at_utc timestamp with time zone, organization_workspace_id uuid, deletion_request_id uuid, display_name text, effective_at_utc timestamp with time zone, purge_after_utc timestamp with time zone, status text)'
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = directory_oid
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog']::text[])
    OR NOT has_function_privilege('tongxingzhe_runtime', directory_oid, 'EXECUTE')
    OR has_function_privilege('public', directory_oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION '0101 typed result, trusted owner, volatility, search path, or function ACL drift';
  END IF;

  SELECT pg_get_functiondef(directory_oid) INTO STRICT function_definition;
  IF strpos(function_definition, 'clock_timestamp()') = 0
    OR strpos(function_definition, 'tstzrange') = 0
    OR strpos(function_definition, 'organization_deletion_current') = 0
    OR strpos(function_definition,
      'observation.observed_at_utc >= attempt.effective_at_utc') = 0
    OR strpos(function_definition,
      'observation.observed_at_utc < attempt.purge_after_utc') = 0
    OR strpos(function_definition, 'organization_deletion_request_claims') > 0
    OR strpos(function_definition, 'organization_deletion_restore_claims') > 0
    OR strpos(function_definition, 'FOR UPDATE') > 0
    OR strpos(function_definition, 'INSERT INTO') > 0
    OR strpos(function_definition, 'UPDATE ') > 0
    OR strpos(function_definition, 'DELETE FROM') > 0
  THEN
    RAISE EXCEPTION '0101 reader query boundary drift';
  END IF;

  IF has_table_privilege('tongxingzhe_runtime',
      'app_private.organization_deletion_current', 'SELECT')
    OR has_table_privilege('tongxingzhe_runtime',
      'app_private.organization_deletion_request_claims', 'SELECT')
    OR has_table_privilege('tongxingzhe_runtime',
      'app_private.organization_deletion_restore_claims', 'SELECT')
    OR has_table_privilege('tongxingzhe_runtime',
      'app_private.organization_deletion_audit_events', 'SELECT')
  THEN RAISE EXCEPTION '0101 runtime can read private lifecycle tables'; END IF;
END
$check$;
