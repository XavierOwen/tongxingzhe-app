\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  function_oid oid;
  function_signature text;
  function_definition text;
  table_name text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0104_organization_deletion_identity_bridges') <> 1 THEN
    RAISE EXCEPTION '0104 migration not recorded exactly once';
  END IF;

  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  FOREACH function_signature IN ARRAY ARRAY[
    'app_data.request_organization_deletion_for_identity_v1(text,text,uuid,uuid)',
    'app_data.restore_organization_for_identity_v1(text,text,uuid,uuid,uuid)'
  ] LOOP
    function_oid := to_regprocedure(function_signature);
    IF function_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure
      WHERE procedure.oid = function_oid AND procedure.proowner = trusted_owner
        AND procedure.prosecdef AND procedure.provolatile = 'v'
        AND procedure.proconfig = ARRAY['search_path=pg_catalog']::text[]
    ) OR NOT has_function_privilege('tongxingzhe_runtime', function_oid, 'EXECUTE')
      OR has_function_privilege('public', function_oid, 'EXECUTE')
    THEN
      RAISE EXCEPTION '0104 bridge owner, security, search path, or ACL drift: %',
        function_signature;
    END IF;

    SELECT pg_catalog.pg_get_functiondef(function_oid)
    INTO STRICT function_definition;
    IF strpos(function_definition, 'trusted_issuer') = 0
      OR strpos(function_definition, 'trusted_subject') = 0
      OR strpos(function_definition, 'identity_row.issuer = trusted_issuer') = 0
      OR strpos(function_definition, 'identity_row.subject = trusted_subject') = 0
      OR strpos(function_definition, 'app_user.status = ''active''') = 0
    THEN
      RAISE EXCEPTION '0104 exact active identity resolution drift: %',
        function_signature;
    END IF;
  END LOOP;

  IF pg_get_function_result(
      'app_data.request_organization_deletion_for_identity_v1(text,text,uuid,uuid)'::regprocedure
    ) IS DISTINCT FROM
      'TABLE(organization_deletion_contract_id text, organization_workspace_id uuid, deletion_request_id uuid, effective_at_utc timestamp with time zone, purge_after_utc timestamp with time zone)'
    OR pg_get_function_result(
      'app_data.restore_organization_for_identity_v1(text,text,uuid,uuid,uuid)'::regprocedure
    ) IS DISTINCT FROM
      'TABLE(organization_deletion_restore_contract_id text, organization_workspace_id uuid, deletion_request_id uuid, restored_at_utc timestamp with time zone)'
  THEN
    RAISE EXCEPTION '0104 typed receipt drift';
  END IF;

  FOREACH function_signature IN ARRAY ARRAY[
    'app_private.request_organization_deletion_v1(uuid,uuid,uuid)',
    'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)'
  ] LOOP
    function_oid := to_regprocedure(function_signature);
    IF function_oid IS NULL
      OR has_function_privilege('tongxingzhe_runtime', function_oid, 'EXECUTE')
      OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS procedure
        CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(
          procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))) AS acl
        WHERE procedure.oid = function_oid AND acl.grantee = 0
      )
    THEN
      RAISE EXCEPTION '0104 private writer exposed to runtime or PUBLIC: %',
        function_signature;
    END IF;
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'organization_deletion_current', 'organization_deletion_request_claims',
    'organization_deletion_restore_claims', 'organization_deletion_audit_events'
  ] LOOP
    IF has_table_privilege('tongxingzhe_runtime',
        'app_private.' || table_name, 'SELECT')
      OR has_table_privilege('tongxingzhe_runtime',
        'app_private.' || table_name, 'INSERT')
      OR has_table_privilege('tongxingzhe_runtime',
        'app_private.' || table_name, 'UPDATE')
      OR has_table_privilege('tongxingzhe_runtime',
        'app_private.' || table_name, 'DELETE')
      OR has_table_privilege('tongxingzhe_runtime',
        'app_private.' || table_name, 'TRUNCATE')
    THEN
      RAISE EXCEPTION '0104 runtime can access private lifecycle table: %', table_name;
    END IF;
  END LOOP;

  SELECT pg_catalog.pg_get_functiondef(
    'app_private.request_organization_deletion_v1(uuid,uuid,uuid)'::regprocedure
  ) INTO STRICT function_definition;
  IF strpos(function_definition, 'lock_organization_governance_v1') = 0
    OR strpos(function_definition, 'reference_time := clock_timestamp()') = 0
  THEN
    RAISE EXCEPTION '0104 deletion writer lock-after contract drift';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(
    'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)'::regprocedure
  ) INTO STRICT function_definition;
  IF strpos(function_definition, 'lock_organization_governance_v1') = 0
    OR strpos(function_definition, 'reference_time < attempt_row.effective_at_utc') = 0
    OR strpos(function_definition, 'reference_time >= attempt_row.purge_after_utc') = 0
  THEN
    RAISE EXCEPTION '0104 restoration writer lock-after or time-boundary contract drift';
  END IF;
END
$check$;
