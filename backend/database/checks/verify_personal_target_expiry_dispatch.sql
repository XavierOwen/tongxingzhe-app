\set ON_ERROR_STOP on
DO $check$
DECLARE
  receipt regprocedure := 'app_private.personal_target_expiry_dispatch_receipt_valid_v1(uuid,uuid)'::regprocedure;
  dispatch regprocedure := 'app_private.dispatch_assigned_personal_target_expiry_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  expected_owner oid;
  candidate regprocedure;
  relation regclass;
  columns text[];
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version = '0131_personal_target_expiry_dispatch') <> 1
  THEN RAISE EXCEPTION '0131 expiry dispatch migration is missing'; END IF;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
    WHERE oid = 'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  IF has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
  THEN RAISE EXCEPTION '0131 cannot open private schema to runtime'; END IF;
  FOREACH candidate IN ARRAY ARRAY[receipt,dispatch] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate AND proowner = expected_owner AND prosecdef
        AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[]
        AND provolatile = CASE WHEN candidate = receipt THEN 's'::"char" ELSE 'v'::"char" END
        AND (CASE WHEN candidate = receipt THEN NOT proretset AND prorettype = 'boolean'::regtype
          ELSE proretset AND pg_get_function_result(candidate) = 'TABLE(unit_kind text, unit_id uuid, outcome text, failure_code text, failure_sqlstate text, processed_at_utc timestamp with time zone)' END))
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) acl
        WHERE f.oid = candidate AND acl.grantee <> f.proowner)
    THEN RAISE EXCEPTION '0131 private function signature, owner or ACL drift: %',candidate; END IF;
  END LOOP;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_target_expiry_dispatch_requests_v1'::regclass,
    'app_private.personal_target_expiry_dispatch_units_v1'::regclass] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation AND relowner = expected_owner AND relkind = 'r')
      OR has_table_privilege('public',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class table_row CROSS JOIN LATERAL aclexplode(table_row.relacl) acl
        WHERE table_row.oid = relation AND acl.grantee <> table_row.relowner)
    THEN RAISE EXCEPTION '0131 metadata receipt owner or ACL drift: %',relation; END IF;
    SELECT array_agg(attname::text ORDER BY attnum) INTO columns FROM pg_attribute
      WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped;
    IF columns IS DISTINCT FROM (CASE relation
      WHEN 'app_private.personal_target_expiry_dispatch_requests_v1'::regclass THEN
        ARRAY['actor_app_user_id','request_id','workspace_id','project_id','selected_at_utc','completed_at_utc','unit_count','expired_count','skipped_count','failed_count']
      ELSE ARRAY['actor_app_user_id','request_id','unit_ordinal','promotion_target_id','generation_id','child_request_id','outcome','failure_code','failure_sqlstate','processed_at_utc'] END)
      OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped
        AND atttypid NOT IN ('uuid'::regtype,'text'::regtype,'int4'::regtype,'timestamptz'::regtype))
    THEN RAISE EXCEPTION '0131 receipts must contain typed metadata only: %',relation; END IF;
    IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = relation AND NOT tgisinternal AND tgenabled = 'O'
      AND tgfoid = 'app_data.reject_promotion_target_audit_mutation()'::regprocedure) <> 1
    THEN RAISE EXCEPTION '0131 receipt history is mutable: %',relation; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pted_unit_request_fk'
      AND conrelid = 'app_private.personal_target_expiry_dispatch_units_v1'::regclass
      AND confrelid = 'app_private.personal_target_expiry_dispatch_requests_v1'::regclass
      AND contype = 'f' AND NOT condeferrable AND NOT condeferred)
  THEN RAISE EXCEPTION '0131 unit-to-request FK must be immediate'; END IF;
END
$check$;
