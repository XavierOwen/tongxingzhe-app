\set ON_ERROR_STOP on
DO $check$
DECLARE
  confirm regprocedure := 'app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
  relation regclass;
  expected_owner oid;
  columns text[];
  candidate regprocedure;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version LIKE '0128_%') <> 1
  THEN RAISE EXCEPTION '0128 confirmation migration is missing'; END IF;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
  WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = confirm AND proowner = expected_owner
      AND prosecdef AND provolatile = 'v' AND prorettype = 'timestamptz'::regtype AND NOT proretset
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public',confirm,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',confirm,'EXECUTE')
    OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
    OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) a
      WHERE f.oid = confirm AND a.grantee <> f.proowner)
  THEN RAISE EXCEPTION '0128 private confirmation signature, owner or ACL drift'; END IF;
  FOREACH candidate IN ARRAY ARRAY[confirm,'app_private.personal_merge_contact_confirmation_proof_v1(uuid,uuid)'::regprocedure] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate AND proowner = expected_owner AND prosecdef
        AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) a WHERE f.oid = candidate AND a.grantee <> f.proowner)
    THEN RAISE EXCEPTION '0128 private helper owner or ACL drift: %',candidate; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'app_private.personal_merge_contact_confirmation_proof_v1(uuid,uuid)'::regprocedure
      AND provolatile = 's' AND prorettype = 'boolean'::regtype AND NOT proretset)
  THEN RAISE EXCEPTION '0128 proof helper must return one STABLE boolean'; END IF;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_merge_contact_confirmation_requests_v1'::regclass,
    'app_private.personal_merge_contact_applications_v1'::regclass] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation AND relowner = expected_owner AND relkind = 'r')
      OR has_table_privilege('public',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    THEN RAISE EXCEPTION '0128 metadata receipt owner or ACL drift: %',relation; END IF;
    SELECT array_agg(attname::text ORDER BY attnum) INTO columns FROM pg_attribute
    WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped;
    IF columns IS DISTINCT FROM (CASE relation
      WHEN 'app_private.personal_merge_contact_confirmation_requests_v1'::regclass THEN
        ARRAY['actor_app_user_id','request_id','workspace_id','project_id','generation_id',
          'known_fact_fingerprint','pending_fingerprint','post_known_fact_fingerprint','confirmed_at_utc']
      ELSE ARRAY['pending_fact_id','actor_app_user_id','request_id','contact_id','from_revision_number',
        'to_revision_number','source_target_id','child_command_id'] END)
      OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped
        AND atttypid IN ('json'::regtype,'jsonb'::regtype,'boolean'::regtype))
    THEN RAISE EXCEPTION '0128 private receipts must contain typed metadata only: %',relation; END IF;
    IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = relation AND NOT tgisinternal AND tgenabled = 'O'
      AND tgfoid = 'app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure) <> 1
    THEN RAISE EXCEPTION '0128 receipt history is mutable: %',relation; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app_private.personal_merge_contact_applications_v1'::regclass
      AND confrelid = 'app_data.contact_target_links'::regclass AND contype = 'f')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app_private.personal_merge_contact_applications_v1'::regclass
      AND confrelid = 'app_private.personal_merge_contact_confirmation_requests_v1'::regclass AND contype = 'f')
  THEN RAISE EXCEPTION '0128 application receipts must reference real link and request rows'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app_private.personal_merge_contact_confirmation_requests_v1'::regclass
      AND confrelid = 'app_private.personal_target_merge_end_events_v1'::regclass AND contype = 'f' AND condeferrable AND condeferred)
  THEN RAISE EXCEPTION '0128 confirmation request must end in a real terminal receipt'; END IF;
END
$check$;
