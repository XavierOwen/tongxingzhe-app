\set ON_ERROR_STOP on
DO $check$
DECLARE
  trusted_owner oid;
  relation regclass;
  candidate regprocedure;
  columns text[];
  expected_columns text[];
  expected_types oid[];
  expected_nullable text[];
  foreign_keys integer;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0133_account_deletion_recovery_core') <> 1
  THEN RAISE EXCEPTION '0133 account deletion migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_schema_privilege('public', 'app_private', 'USAGE')
  THEN RAISE EXCEPTION '0133 account deletion cannot open the private schema'; END IF;

  FOREACH candidate IN ARRAY ARRAY[
    'app_private.protect_account_deletion_claim_v1()'::regprocedure,
    'app_private.request_account_deletion_v1(uuid,uuid)'::regprocedure,
    'app_private.restore_account_v1(uuid,uuid,uuid)'::regprocedure
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate
        AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
        AND proconfig = ARRAY['search_path=pg_catalog']::text[])
      OR has_function_privilege('public', candidate, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', candidate, 'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
        WHERE p.oid = candidate AND acl.grantee <> p.proowner)
    THEN RAISE EXCEPTION '0133 private function owner, security or ACL drift: %', candidate; END IF;
  END LOOP;
  IF pg_get_function_result('app_private.request_account_deletion_v1(uuid,uuid)'::regprocedure)
      IS DISTINCT FROM 'TABLE(account_deletion_contract_id text, deletion_request_id uuid, effective_at_utc timestamp with time zone, purge_after_utc timestamp with time zone)'
    OR pg_get_function_result('app_private.restore_account_v1(uuid,uuid,uuid)'::regprocedure)
      IS DISTINCT FROM 'TABLE(account_deletion_restore_contract_id text, deletion_request_id uuid, restored_at_utc timestamp with time zone)'
    OR pg_get_function_result('app_private.protect_account_deletion_claim_v1()'::regprocedure)
      IS DISTINCT FROM 'trigger'
  THEN RAISE EXCEPTION '0133 account deletion typed receipt drift'; END IF;

  FOREACH relation IN ARRAY ARRAY[
    'app_private.account_deletion_current'::regclass,
    'app_private.account_deletion_request_claims'::regclass,
    'app_private.account_deletion_restore_claims'::regclass,
    'app_private.account_deletion_audit_events'::regclass
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation
        AND relkind = 'r' AND relowner = trusted_owner)
      OR has_table_privilege('public', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class c
        CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
        WHERE c.oid = relation AND acl.grantee <> c.relowner)
    THEN RAISE EXCEPTION '0133 private table owner or ACL drift: %', relation; END IF;
    CASE relation
      WHEN 'app_private.account_deletion_current'::regclass THEN
        expected_columns := ARRAY['app_user_id', 'deletion_request_id', 'effective_at_utc', 'purge_after_utc', 'status', 'restored_at_utc'];
        expected_types := ARRAY['uuid'::regtype, 'uuid'::regtype, 'timestamptz'::regtype, 'timestamptz'::regtype, 'text'::regtype, 'timestamptz'::regtype];
        expected_nullable := ARRAY['restored_at_utc'];
        foreign_keys := 2;
      WHEN 'app_private.account_deletion_request_claims'::regclass THEN
        expected_columns := ARRAY['request_id', 'actor_app_user_id', 'deletion_request_id', 'effective_at_utc', 'purge_after_utc'];
        expected_types := ARRAY['uuid'::regtype, 'uuid'::regtype, 'uuid'::regtype, 'timestamptz'::regtype, 'timestamptz'::regtype];
        expected_nullable := ARRAY['actor_app_user_id'];
        foreign_keys := 1;
      WHEN 'app_private.account_deletion_restore_claims'::regclass THEN
        expected_columns := ARRAY['request_id', 'actor_app_user_id', 'deletion_request_id', 'restored_at_utc'];
        expected_types := ARRAY['uuid'::regtype, 'uuid'::regtype, 'uuid'::regtype, 'timestamptz'::regtype];
        expected_nullable := ARRAY['actor_app_user_id'];
        foreign_keys := 2;
      ELSE
        expected_columns := ARRAY['audit_event_id', 'operation', 'request_id', 'deletion_request_id', 'occurred_at_utc'];
        expected_types := ARRAY['uuid'::regtype, 'text'::regtype, 'uuid'::regtype, 'uuid'::regtype, 'timestamptz'::regtype];
        expected_nullable := ARRAY[]::text[];
        foreign_keys := 0;
    END CASE;
    SELECT array_agg(attname::text ORDER BY attnum) INTO columns FROM pg_attribute
      WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped;
    IF columns IS DISTINCT FROM expected_columns
      OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped) IS DISTINCT FROM expected_types
      OR (SELECT coalesce(array_agg(attname::text ORDER BY attnum), ARRAY[]::text[]) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped AND NOT attnotnull)
        IS DISTINCT FROM expected_nullable
      OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = relation AND contype = 'p'
        AND conkey = ARRAY[1]::smallint[] AND NOT condeferrable AND convalidated)
      OR (SELECT count(*) FROM pg_constraint WHERE conrelid = relation AND contype = 'f') <> foreign_keys
      OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = relation AND contype = 'f'
        AND (condeferrable OR condeferred OR NOT convalidated
          OR confrelid NOT IN ('app_data.app_users'::regclass, 'app_private.account_deletion_request_claims'::regclass)))
    THEN RAISE EXCEPTION '0133 typed metadata, primary key or immediate FK drift: %', relation; END IF;
  END LOOP;

  IF (SELECT count(*) FROM pg_constraint WHERE contype = 'f'
      AND conrelid = 'app_private.account_deletion_current'::regclass
      AND confrelid = 'app_data.app_users'::regclass AND conkey = ARRAY[1]::smallint[]
      AND confkey = ARRAY[1]::smallint[] AND confdeltype = 'c') <> 1
    OR (SELECT count(*) FROM pg_constraint WHERE contype = 'f'
      AND conrelid IN ('app_private.account_deletion_request_claims'::regclass,
        'app_private.account_deletion_restore_claims'::regclass)
      AND confrelid = 'app_data.app_users'::regclass AND conkey = ARRAY[2]::smallint[]
      AND confkey = ARRAY[1]::smallint[] AND confdeltype = 'n') <> 2
    OR (SELECT count(*) FROM pg_constraint WHERE contype = 'f'
      AND conrelid IN ('app_private.account_deletion_current'::regclass,
        'app_private.account_deletion_restore_claims'::regclass)
      AND confrelid = 'app_private.account_deletion_request_claims'::regclass
      AND conkey = ARRAY[CASE WHEN conrelid = 'app_private.account_deletion_current'::regclass THEN 2 ELSE 3 END]::smallint[]
      AND confkey = ARRAY[1]::smallint[] AND confdeltype IN ('a', 'r')) <> 2
  THEN RAISE EXCEPTION '0133 account deletion lifecycle FK actions drift'; END IF;

  FOREACH relation IN ARRAY ARRAY[
    'app_private.account_deletion_request_claims'::regclass,
    'app_private.account_deletion_restore_claims'::regclass,
    'app_private.account_deletion_audit_events'::regclass
  ] LOOP
    IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = relation AND NOT tgisinternal
        AND tgenabled = 'O' AND tgtype = 27
        AND tgfoid = CASE WHEN relation = 'app_private.account_deletion_audit_events'::regclass
          THEN 'app_data.reject_promotion_target_audit_mutation()'::regprocedure
          ELSE 'app_private.protect_account_deletion_claim_v1()'::regprocedure END) <> 1
    THEN RAISE EXCEPTION '0133 account deletion history is mutable: %', relation; END IF;
  END LOOP;
END
$check$;
