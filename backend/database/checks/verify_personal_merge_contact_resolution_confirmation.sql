\set ON_ERROR_STOP on
DO $check$
DECLARE
  confirm regprocedure := 'app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  expected_owner oid;
  candidate regprocedure;
  relation regclass;
  columns text[];
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version LIKE '0130_%') <> 1
  THEN RAISE EXCEPTION '0130 resolution confirmation migration is missing'; END IF;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
    WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
  THEN RAISE EXCEPTION '0130 cannot open private schema to runtime'; END IF;
  FOREACH candidate IN ARRAY ARRAY[confirm,
    'app_private.personal_merge_contact_resolution_proof_v1(uuid,uuid)'::regprocedure,
    'app_private.personal_merge_contact_resolution_revision_proof_v1(uuid,text,text,integer,integer,jsonb)'::regprocedure] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate AND proowner = expected_owner AND prosecdef AND NOT proretset
        AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[]
        AND provolatile = CASE WHEN candidate = confirm THEN 'v'::"char" ELSE 's'::"char" END
        AND prorettype = CASE WHEN candidate = confirm THEN 'timestamptz'::regtype ELSE 'boolean'::regtype END)
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) acl
        WHERE f.oid = candidate AND acl.grantee <> f.proowner)
    THEN RAISE EXCEPTION '0130 private function signature, owner or ACL drift: %',candidate; END IF;
  END LOOP;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_merge_contact_resolution_requests_v1'::regclass,
    'app_private.personal_merge_contact_history_applications_v1'::regclass,
    'app_private.personal_merge_contact_current_revisions_v1'::regclass,
    'app_private.personal_merge_contact_current_choices_v1'::regclass] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation AND relowner = expected_owner AND relkind = 'r')
      OR has_table_privilege('public',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class table_row CROSS JOIN LATERAL aclexplode(table_row.relacl) acl
        WHERE table_row.oid = relation AND acl.grantee <> table_row.relowner)
    THEN RAISE EXCEPTION '0130 metadata receipt owner or ACL drift: %',relation; END IF;
    SELECT array_agg(attname::text ORDER BY attnum) INTO columns FROM pg_attribute
      WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped;
    IF columns IS DISTINCT FROM (CASE relation
      WHEN 'app_private.personal_merge_contact_resolution_requests_v1'::regclass THEN
        ARRAY['actor_app_user_id','request_id','workspace_id','project_id','generation_id','known_fact_fingerprint',
          'pending_fingerprint','resolution_fingerprint','post_known_fact_fingerprint','confirmed_at_utc']
      WHEN 'app_private.personal_merge_contact_history_applications_v1'::regclass THEN
        ARRAY['pending_fact_id','actor_app_user_id','request_id','contact_id','original_revision_number',
          'from_revision_number','to_revision_number','source_target_id','child_command_id']
      WHEN 'app_private.personal_merge_contact_current_revisions_v1'::regclass THEN
        ARRAY['actor_app_user_id','request_id','contact_id','original_revision_number','from_revision_number',
          'to_revision_number','child_command_id']
      ELSE ARRAY['actor_app_user_id','request_id','contact_id','source_target_id','selected_pending_fact_id'] END)
      OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped
        AND atttypid NOT IN ('uuid'::regtype,'text'::regtype,'int4'::regtype,'timestamptz'::regtype))
    THEN RAISE EXCEPTION '0130 receipts must contain typed metadata only: %',relation; END IF;
    IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = relation AND NOT tgisinternal AND tgenabled = 'O'
      AND tgfoid = 'app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure) <> 1
    THEN RAISE EXCEPTION '0130 receipt history is mutable: %',relation; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pmcr_request_end_fk'
      AND conrelid = 'app_private.personal_merge_contact_resolution_requests_v1'::regclass
      AND confrelid = 'app_private.personal_target_merge_end_events_v1'::regclass AND contype = 'f' AND condeferrable AND condeferred)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pmcr_history_request_fk'
      AND conrelid = 'app_private.personal_merge_contact_history_applications_v1'::regclass
      AND confrelid = 'app_private.personal_merge_contact_resolution_requests_v1'::regclass AND contype = 'f' AND condeferrable AND condeferred)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pmcr_current_request_fk'
      AND conrelid = 'app_private.personal_merge_contact_current_revisions_v1'::regclass
      AND confrelid = 'app_private.personal_merge_contact_resolution_requests_v1'::regclass AND contype = 'f' AND condeferrable AND condeferred)
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'pmcr_history_link_fk'
      AND conrelid = 'app_private.personal_merge_contact_history_applications_v1'::regclass
      AND confrelid = 'app_data.contact_target_links'::regclass AND contype = 'f')
    OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'app_private.personal_merge_contact_current_choices_v1'::regclass
      AND confrelid = 'app_private.personal_merge_contact_history_applications_v1'::regclass AND contype = 'f')
  THEN RAISE EXCEPTION '0130 application, selection or terminal receipt FK drift'; END IF;
END
$check$;
