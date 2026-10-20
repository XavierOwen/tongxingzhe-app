\set ON_ERROR_STOP on
DO $check$
DECLARE
  planner regprocedure := 'app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
  trusted_owner oid;
  code text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0137_personal_merge_project_relationship_resolution_plan') <> 1
  THEN RAISE EXCEPTION '0137 project relationship resolution plan migration is missing'; END IF;
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = planner AND proowner = trusted_owner
      AND prosecdef AND provolatile = 's' AND NOT proretset AND prorettype = 'jsonb'::regtype
      AND proconfig = ARRAY['search_path=pg_catalog']::text[])
    OR has_schema_privilege('public', 'app_private', 'USAGE')
    OR has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege('public', planner, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', planner, 'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      WHERE p.oid = planner AND acl.grantee <> p.proowner)
  THEN RAISE EXCEPTION '0137 private resolution plan result, owner, stability, security or ACL drift'; END IF;
  SELECT lower(regexp_replace(prosrc, '--[^\n]*', '', 'g')) INTO code FROM pg_proc WHERE oid = planner;
  code := regexp_replace(code, '''(''''|[^''])*''', '''''', 'g');
  IF code ~ '\m(insert|update|delete|execute|call|truncate|create|alter|drop|grant|new_stage|new_lifecycle_status|current_stage|current_lifecycle_status|current_follow_up_note|follow_up_note|reason_code|reason_detail)\M|pg_advisory|acquire_personal_target_merge_generation_fence|transaction_isolation'
    OR (SELECT count(*) FROM regexp_matches(code,
      'read_personal_merge_unassigned_project_relationship_plan_v1\s*\(', 'g')) <> 1
    OR position('personal_merge_unassigned_project_relationship_facts_v1' IN code) > 0
  THEN RAISE EXCEPTION '0137 resolution plan must delegate metadata once without payload values, writes, locks or isolation gates'; END IF;
END
$check$;
