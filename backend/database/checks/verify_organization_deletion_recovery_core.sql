\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  table_name text;
  function_signature text;
  object_oid oid;
  function_definition text;
  actual_columns text[];
  expected_columns text[];
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0100_organization_deletion_recovery_core') <> 1 THEN
    RAISE EXCEPTION '0100 migration not recorded exactly once';
  END IF;

  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  FOREACH table_name IN ARRAY ARRAY[
    'organization_deletion_current', 'organization_deletion_request_claims',
    'organization_deletion_restore_claims', 'organization_deletion_audit_events'
  ] LOOP
    object_oid := to_regclass('app_private.' || table_name);
    IF object_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_class WHERE oid = object_oid AND relowner = trusted_owner
    ) OR has_table_privilege('tongxingzhe_runtime', object_oid, 'SELECT')
      OR has_table_privilege('tongxingzhe_runtime', object_oid, 'INSERT')
      OR has_table_privilege('tongxingzhe_runtime', object_oid, 'UPDATE')
      OR has_table_privilege('tongxingzhe_runtime', object_oid, 'DELETE')
      OR EXISTS (
        SELECT 1 FROM pg_class AS relation
        CROSS JOIN LATERAL aclexplode(coalesce(
          relation.relacl, acldefault('r', relation.relowner))) AS acl
        WHERE relation.oid = object_oid AND acl.grantee = 0
      )
    THEN
      RAISE EXCEPTION '0100 table owner or ACL drift: %', table_name;
    END IF;

    SELECT array_agg(attname::text ORDER BY attnum) INTO actual_columns
    FROM pg_attribute WHERE attrelid = object_oid AND attnum > 0
      AND NOT attisdropped;
    CASE table_name
      WHEN 'organization_deletion_current' THEN
        expected_columns := ARRAY['organization_workspace_id',
          'deletion_request_id', 'effective_at_utc', 'purge_after_utc',
          'status', 'restored_at_utc'];
      WHEN 'organization_deletion_request_claims' THEN
        expected_columns := ARRAY['request_id', 'actor_app_user_id',
          'organization_workspace_id', 'deletion_request_id',
          'effective_at_utc', 'purge_after_utc'];
      WHEN 'organization_deletion_restore_claims' THEN
        expected_columns := ARRAY['request_id', 'actor_app_user_id',
          'organization_workspace_id', 'deletion_request_id',
          'restored_at_utc'];
      ELSE
        expected_columns := ARRAY['audit_event_id', 'operation', 'request_id',
          'organization_workspace_id', 'deletion_request_id',
          'occurred_at_utc'];
    END CASE;
    IF actual_columns IS DISTINCT FROM expected_columns THEN
      RAISE EXCEPTION '0100 column allowlist drift: %', table_name;
    END IF;
  END LOOP;

  IF pg_get_function_result(
      'app_private.request_organization_deletion_v1(uuid,uuid,uuid)'::regprocedure
    ) IS DISTINCT FROM
      'TABLE(organization_deletion_contract_id text, organization_workspace_id uuid, deletion_request_id uuid, effective_at_utc timestamp with time zone, purge_after_utc timestamp with time zone)'
    OR pg_get_function_result(
      'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)'::regprocedure
    ) IS DISTINCT FROM
      'TABLE(organization_deletion_restore_contract_id text, organization_workspace_id uuid, deletion_request_id uuid, restored_at_utc timestamp with time zone)'
  THEN
    RAISE EXCEPTION '0100 exact typed receipt drift';
  END IF;

  FOREACH function_signature IN ARRAY ARRAY[
    'app_private.protect_organization_deletion_claim_v1()',
    'app_private.protect_organization_deletion_audit_v1()',
    'app_private.request_organization_deletion_v1(uuid,uuid,uuid)',
    'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)'
  ] LOOP
    object_oid := to_regprocedure(function_signature);
    IF object_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_proc WHERE oid = object_oid AND proowner = trusted_owner
        AND prosecdef AND provolatile = 'v'
        AND proconfig = ARRAY['search_path=pg_catalog']::text[]
    ) OR has_function_privilege('tongxingzhe_runtime', object_oid, 'EXECUTE')
      OR EXISTS (
        SELECT 1 FROM pg_proc AS procedure
        CROSS JOIN LATERAL aclexplode(coalesce(
          procedure.proacl, acldefault('f', procedure.proowner))) AS acl
        WHERE procedure.oid = object_oid AND acl.grantee = 0
      )
    THEN
      RAISE EXCEPTION '0100 function owner or ACL drift: %', function_signature;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgrelid =
      'app_private.organization_deletion_request_claims'::regclass
      AND tgname = 'organization_deletion_request_claims_immutable'
      AND tgenabled = 'O'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgrelid =
      'app_private.organization_deletion_restore_claims'::regclass
      AND tgname = 'organization_deletion_restore_claims_immutable'
      AND tgenabled = 'O'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgrelid =
      'app_private.organization_deletion_audit_events'::regclass
      AND tgname = 'organization_deletion_audit_events_immutable'
      AND tgenabled = 'O'
  ) THEN
    RAISE EXCEPTION '0100 immutable trigger drift';
  END IF;

  SELECT pg_get_functiondef(
    'app_private.request_organization_deletion_v1(uuid,uuid,uuid)'::regprocedure
  ) INTO function_definition;
  IF strpos(function_definition, 'current_setting(''transaction_isolation'')') = 0
    OR strpos(function_definition, 'lock_organization_governance_v1') = 0
    OR strpos(function_definition, 'clock_timestamp()') = 0
    OR strpos(function_definition, 'interval ''720 hours''') = 0
  THEN
    RAISE EXCEPTION '0100 deletion writer contract drift';
  END IF;

  SELECT pg_get_functiondef(
    'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)'::regprocedure
  ) INTO function_definition;
  IF strpos(function_definition, 'expected_deletion_request_id') = 0
    OR strpos(function_definition,
      'reference_time < attempt_row.effective_at_utc') = 0
    OR strpos(function_definition, 'reference_time >= attempt_row.purge_after_utc') = 0
    OR strpos(function_definition, 'lock_organization_governance_v1') = 0
  THEN
    RAISE EXCEPTION '0100 restoration writer contract drift';
  END IF;
END
$check$;
