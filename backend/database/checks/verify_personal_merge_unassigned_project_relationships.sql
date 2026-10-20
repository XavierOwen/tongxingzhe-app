\set ON_ERROR_STOP on
DO $check$
DECLARE
  stage regprocedure := 'app_private.stage_unassigned_personal_merge_project_relationship_v1(uuid,uuid,uuid,uuid,uuid,integer,text,text,text,text)'::regprocedure;
  plan regprocedure := 'app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  trusted_owner oid; candidate regprocedure; relation regclass;
  columns text[]; types oid[]; nullable text[]; code text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0136_personal_merge_unassigned_project_relationships') <> 1
  THEN RAISE EXCEPTION '0136 pending project relationship migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF has_schema_privilege('public', 'app_private', 'USAGE')
    OR has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
  THEN RAISE EXCEPTION '0136 cannot open private schema'; END IF;
  FOREACH candidate IN ARRAY ARRAY[stage, plan,
    'app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure,
    'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure,
    'app_private.purge_personal_merge_unassigned_project_relationships_v1()'::regprocedure] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = candidate AND proowner = trusted_owner
        AND prosecdef AND proconfig = ARRAY['search_path=pg_catalog']::text[]
        AND provolatile = CASE WHEN candidate = plan THEN 's'::"char" ELSE 'v'::"char" END)
      OR has_function_privilege('public', candidate, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', candidate, 'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
        WHERE p.oid = candidate AND acl.grantee <> p.proowner)
    THEN RAISE EXCEPTION '0136 function owner, security or ACL drift: %', candidate; END IF;
  END LOOP;
  IF pg_get_function_result(stage) IS DISTINCT FROM 'TABLE(unassigned_project_relationship_contract_id text, pending_fact_id uuid, staged_at_utc timestamp with time zone)'
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = plan AND NOT proretset AND prorettype = 'jsonb'::regtype)
    OR EXISTS (SELECT 1 FROM pg_proc WHERE oid IN (
      'app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure,
      'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure,
      'app_private.purge_personal_merge_unassigned_project_relationships_v1()'::regprocedure)
      AND (proretset OR prorettype <> 'trigger'::regtype))
  THEN RAISE EXCEPTION '0136 typed stage, metadata plan or trigger result drift'; END IF;

  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_merge_unassigned_project_relationship_requests_v1'::regclass,
    'app_data.personal_merge_unassigned_project_relationship_facts_v1'::regclass,
    'app_private.personal_merge_unassigned_project_relationship_purges_v1'::regclass] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = relation AND relkind = 'r' AND relowner = trusted_owner)
      OR has_table_privilege('public', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR has_table_privilege('tongxingzhe_runtime', relation, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      OR EXISTS (SELECT 1 FROM pg_class c
        CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
        WHERE c.oid = relation AND acl.grantee <> c.relowner)
    THEN RAISE EXCEPTION '0136 table owner or ACL drift: %', relation; END IF;
    CASE relation
      WHEN 'app_private.personal_merge_unassigned_project_relationship_requests_v1'::regclass THEN
        columns := ARRAY['pending_fact_id','actor_app_user_id','workspace_id','project_id','generation_id','target_type','request_id','staged_at_utc'];
        types := ARRAY['uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'uuid'::regtype,'text'::regtype,'uuid'::regtype,'timestamptz'::regtype];
        nullable := ARRAY[]::text[];
      WHEN 'app_data.personal_merge_unassigned_project_relationship_facts_v1'::regclass THEN
        columns := ARRAY['pending_fact_id','new_stage','new_lifecycle_status','follow_up_note','reason_code','reason_detail'];
        types := ARRAY['uuid'::regtype,'int4'::regtype,'text'::regtype,'text'::regtype,'text'::regtype,'text'::regtype];
        nullable := ARRAY['follow_up_note','reason_detail'];
      ELSE
        columns := ARRAY['pending_fact_id','generation_id','purged_at_utc'];
        types := ARRAY['uuid'::regtype,'uuid'::regtype,'timestamptz'::regtype];
        nullable := ARRAY[]::text[];
    END CASE;
    IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped) IS DISTINCT FROM columns
      OR (SELECT array_agg(atttypid ORDER BY attnum) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped) IS DISTINCT FROM types
      OR (SELECT coalesce(array_agg(attname::text ORDER BY attnum), ARRAY[]::text[]) FROM pg_attribute
        WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped AND NOT attnotnull) IS DISTINCT FROM nullable
      OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = relation AND contype = 'p'
        AND conkey = ARRAY[1]::smallint[] AND NOT condeferrable AND convalidated)
      OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = relation AND NOT tgisinternal AND tgenabled = 'O' AND tgtype = 27
        AND tgfoid = CASE WHEN relation = 'app_data.personal_merge_unassigned_project_relationship_facts_v1'::regclass
          THEN 'app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure
          ELSE 'app_private.reject_personal_target_merge_history_mutation_v1()'::regprocedure END) <> 1
    THEN RAISE EXCEPTION '0136 typed column allowlist, key or immutable guard drift: %', relation; END IF;
  END LOOP;
  IF EXISTS (
    WITH expected(name, child, source_keys, parent, target_keys) AS (VALUES
      ('pmupr_request_actor_fk','app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[2],'app_data.app_users',ARRAY[1]),
      ('pmupr_request_workspace_fk','app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[3],'app_data.workspaces',ARRAY[1]),
      ('pmupr_request_project_fk','app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[4],'app_data.projects',ARRAY[1]),
      ('pmupr_request_generation_fk','app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[5],'app_private.personal_target_merge_generations_v1',ARRAY[1]),
      ('pmupr_payload_request_fk','app_data.personal_merge_unassigned_project_relationship_facts_v1',ARRAY[1],'app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[1]),
      ('pmupr_purge_generation_fk','app_private.personal_merge_unassigned_project_relationship_purges_v1',ARRAY[2],'app_private.personal_target_merge_end_events_v1',ARRAY[1]),
      ('pmupr_purge_request_fk','app_private.personal_merge_unassigned_project_relationship_purges_v1',ARRAY[1,2],'app_private.personal_merge_unassigned_project_relationship_requests_v1',ARRAY[1,5])
    ) SELECT 1 FROM expected e LEFT JOIN pg_constraint c ON c.conname = e.name AND c.conrelid = to_regclass(e.child)
      AND c.confrelid = to_regclass(e.parent) AND c.conkey = e.source_keys::smallint[] AND c.confkey = e.target_keys::smallint[]
      AND c.contype = 'f' AND c.confdeltype = 'r' AND c.confupdtype = 'a'
      AND NOT c.condeferrable AND NOT c.condeferred AND c.convalidated
    WHERE c.oid IS NULL
  ) OR (SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND conrelid IN (
    'app_private.personal_merge_unassigned_project_relationship_requests_v1'::regclass,
    'app_data.personal_merge_unassigned_project_relationship_facts_v1'::regclass,
    'app_private.personal_merge_unassigned_project_relationship_purges_v1'::regclass)) <> 7
    OR (SELECT count(*) FROM pg_constraint WHERE conrelid = 'app_private.personal_merge_unassigned_project_relationship_requests_v1'::regclass
      AND contype = 'u' AND conkey IN (ARRAY[2,7]::smallint[], ARRAY[1,5]::smallint[]) AND NOT condeferrable AND convalidated) <> 2
    OR (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'app_private.personal_target_merge_end_events_v1'::regclass
      AND NOT tgisinternal AND tgenabled = 'O'
      AND ((tgfoid = 'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure AND tgtype = 7)
        OR (tgfoid = 'app_private.purge_personal_merge_unassigned_project_relationships_v1()'::regprocedure AND tgtype = 5
          AND position('WHEN ((new.reason = ''retention_expired''::text)) EXECUTE FUNCTION '
            IN pg_get_triggerdef(oid)) > 0))) <> 2
  THEN RAISE EXCEPTION '0136 named immediate foreign keys, request uniqueness or expiry hooks drift'; END IF;

  SELECT lower(regexp_replace(prosrc, '--[^\n]*', '', 'g')) INTO code FROM pg_proc WHERE oid = plan;
  code := regexp_replace(code, '''(''''|[^''])*''', '''''', 'g');
  IF code ~ '\m(insert|update|delete|execute|call|truncate|create|alter|drop|grant|new_stage|new_lifecycle_status|follow_up_note|reason_code|reason_detail)\M|pg_advisory|acquire_personal_target_merge_generation_fence'
    OR (SELECT count(*) FROM regexp_matches(code, 'read_known_source_personal_merge_split_plan_v1\s*\(', 'g')) <> 1
  THEN RAISE EXCEPTION '0136 plan must read metadata without values, hashes, writes or locks'; END IF;
END
$check$;
