\set ON_ERROR_STOP on
DO $check$
DECLARE
  writer regprocedure := 'app_private.unlink_due_account_history_contributions_v1(uuid,uuid)'::regprocedure;
  completion regclass := 'app_private.account_history_contribution_unlink_completions_v1'::regclass;
  trusted_owner oid;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0135_account_history_contribution_unlink') <> 1
  THEN RAISE EXCEPTION '0135 account contribution unlink migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF has_schema_privilege('public', 'app_private', 'USAGE')
    OR has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = writer
      AND proowner = trusted_owner AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog']::text[] AND proretset
      AND pg_get_function_result(oid) = 'TABLE(account_history_contribution_unlink_contract_id text, deletion_request_id uuid, unlinked_at_utc timestamp with time zone)')
    OR has_function_privilege('public', writer, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', writer, 'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      WHERE p.oid = writer AND acl.grantee <> p.proowner)
  THEN RAISE EXCEPTION '0135 private unlink function result, owner, security or ACL drift'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = completion AND relkind = 'r' AND relowner = trusted_owner)
    OR has_table_privilege('public', completion, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime', completion, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR EXISTS (SELECT 1 FROM pg_class c
      CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
      WHERE c.oid = completion AND acl.grantee <> c.relowner)
    OR (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute
      WHERE attrelid = completion AND attnum > 0 AND NOT attisdropped)
      IS DISTINCT FROM ARRAY['deletion_request_id', 'unlinked_at_utc']::text[]
    OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute
      WHERE attrelid = completion AND attnum > 0 AND NOT attisdropped)
      IS DISTINCT FROM ARRAY['uuid'::regtype, 'timestamptz'::regtype]::oid[]
    OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = completion
      AND attnum > 0 AND NOT attisdropped AND NOT attnotnull)
    OR EXISTS (SELECT 1 FROM pg_constraint WHERE contype = 'f'
      AND (conrelid = completion OR confrelid = completion))
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = completion AND contype = 'p'
      AND conkey = ARRAY[1]::smallint[] AND NOT condeferrable AND convalidated)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = completion AND contype = 'c'
      AND position('isfinite(unlinked_at_utc)' IN pg_get_constraintdef(oid)) > 0 AND convalidated)
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = completion AND NOT tgisinternal
      AND tgenabled = 'O' AND tgtype = 27
      AND tgfoid = 'app_data.reject_promotion_target_audit_mutation()'::regprocedure) <> 1
  THEN RAISE EXCEPTION '0135 completion must contain immutable private value-free metadata without foreign keys'; END IF;
END
$check$;
