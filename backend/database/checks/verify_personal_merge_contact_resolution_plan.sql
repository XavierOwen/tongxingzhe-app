\set ON_ERROR_STOP on
DO $check$
DECLARE
  planner regprocedure := 'app_private.plan_unassigned_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
  expected_owner oid;
  code text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version LIKE '0129_%') <> 1
  THEN RAISE EXCEPTION '0129 resolution-plan migration is missing'; END IF;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
  WHERE oid = 'app_private.read_personal_merge_unassigned_contact_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = planner AND proowner = expected_owner
      AND prosecdef AND provolatile = 's' AND prorettype = 'jsonb'::regtype AND NOT proretset
      AND proconfig = ARRAY['search_path=pg_catalog, app_data, app_private']::text[])
    OR has_function_privilege('public',planner,'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',planner,'EXECUTE')
    OR has_schema_privilege('tongxingzhe_runtime','app_private','USAGE')
    OR EXISTS (SELECT 1 FROM pg_proc f CROSS JOIN LATERAL aclexplode(f.proacl) a
      WHERE f.oid = planner AND a.grantee <> f.proowner)
  THEN RAISE EXCEPTION '0129 private planner signature, owner, search path or ACL drift'; END IF;
  SELECT lower(regexp_replace(prosrc,'--[^\n]*','','g')) INTO code FROM pg_proc WHERE oid = planner;
  code := regexp_replace(code,'''(''''|[^''])*''','''''','g');
  IF code ~ '\m(insert|update|delete|execute|call|truncate|create|alter|drop|grant)\M|pg_advisory|acquire_personal_target_merge_generation_fence|for\s+(update|share)|confirm_unassigned|end_known_source'
    OR (SELECT count(*) FROM regexp_matches(code,'read_personal_merge_unassigned_contact_plan_v1\s*\(','g')) <> 1
  THEN RAISE EXCEPTION '0129 planner must delegate 0127 once and remain readonly without a fence or confirmation'; END IF;
END
$check$;
