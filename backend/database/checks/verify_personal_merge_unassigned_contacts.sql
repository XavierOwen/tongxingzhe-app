\set ON_ERROR_STOP on
DO $check$
DECLARE
  stage regprocedure := 'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)'::regprocedure;
  plan regprocedure := 'app_private.read_personal_merge_unassigned_contact_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  candidate regprocedure;
  relation regclass;
  expected_owner oid;
  columns text[];
  code text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version LIKE '0127_%') <> 1
  THEN RAISE EXCEPTION '0127 unassigned contact migration is missing'; END IF;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
  WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  FOREACH candidate IN ARRAY ARRAY[stage,plan,
    'app_private.guard_personal_merge_unassigned_contact_payload_v1()'::regprocedure,
    'app_private.guard_personal_merge_unassigned_contact_end_v1()'::regprocedure,
    'app_private.purge_personal_merge_unassigned_contacts_v1()'::regprocedure] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate AND proowner = expected_owner
        AND prosecdef AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
      OR has_function_privilege('public',candidate,'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime',candidate,'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) a
        WHERE f.oid = candidate AND a.grantee <> f.proowner)
    THEN RAISE EXCEPTION '0127 private function owner, search path or ACL drift: %',candidate; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = stage AND provolatile = 'v' AND prorettype = 'uuid'::regtype AND NOT proretset)
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = plan AND provolatile = 's' AND prorettype = 'jsonb'::regtype AND NOT proretset)
    OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
  THEN RAISE EXCEPTION '0127 staging/readonly plan signature or runtime boundary drift'; END IF;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_merge_unassigned_contact_requests_v1'::regclass,
    'app_data.personal_merge_unassigned_contact_facts_v1'::regclass,
    'app_private.personal_merge_unassigned_contact_purges_v1'::regclass] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation AND relowner = expected_owner AND relkind = 'r')
      OR has_table_privilege('public',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime',relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    THEN RAISE EXCEPTION '0127 private table owner or ACL drift: %',relation; END IF;
    SELECT array_agg(attname::text ORDER BY attnum) INTO columns FROM pg_attribute
    WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped;
    IF columns IS DISTINCT FROM (CASE relation
      WHEN 'app_private.personal_merge_unassigned_contact_requests_v1'::regclass THEN
        ARRAY['pending_fact_id','actor_app_user_id','workspace_id','project_id','generation_id','contact_id',
          'revision_number','target_type','request_id','staged_at_utc']
      WHEN 'app_data.personal_merge_unassigned_contact_facts_v1'::regclass THEN
        ARRAY['pending_fact_id','response_level','follow_up_consent','institution_representative_confirmed','confirmed_project_entry']
      ELSE ARRAY['pending_fact_id','generation_id','purged_at_utc'] END)
    THEN RAISE EXCEPTION '0127 typed metadata/payload separation drift: %',relation; END IF;
    IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped
      AND atttypid IN ('json'::regtype,'jsonb'::regtype))
    THEN RAISE EXCEPTION '0127 must not introduce a generic JSON payload or ledger digest'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'app_private.personal_merge_unassigned_contact_requests_v1'::regclass
      AND NOT tgisinternal AND tgenabled = 'O'
      AND tgfoid = 'app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure) <> 1
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'app_private.personal_merge_unassigned_contact_purges_v1'::regclass
      AND NOT tgisinternal AND tgenabled = 'O'
      AND tgfoid = 'app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure) <> 1
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'app_data.personal_merge_unassigned_contact_facts_v1'::regclass
      AND NOT tgisinternal AND tgenabled = 'O'
      AND tgfoid = 'app_private.guard_personal_merge_unassigned_contact_payload_v1()'::regprocedure) <> 1
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'app_private.personal_target_merge_end_events_v1'::regclass
      AND NOT tgisinternal AND tgenabled = 'O' AND tgfoid IN (
        'app_private.guard_personal_merge_unassigned_contact_end_v1()'::regprocedure,
        'app_private.purge_personal_merge_unassigned_contacts_v1()'::regprocedure)) <> 2
  THEN RAISE EXCEPTION '0127 immutable history, payload guard or terminal hooks are missing'; END IF;
  SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO code FROM pg_proc WHERE oid = plan;
  code := regexp_replace(code,'''(''''|[^''])*''','''''','g');
  IF code ~ '\m(insert|update|delete|execute|call|truncate|create|alter|drop|grant)\M|pg_advisory|acquire_personal_target_merge_generation_fence'
    OR (SELECT count(*) FROM regexp_matches(code,'read_known_source_personal_merge_split_plan_v1\s*\(','g')) <> 1
  THEN RAISE EXCEPTION '0127 plan must delegate the known gate once and remain genuinely readonly'; END IF;
END
$check$;
