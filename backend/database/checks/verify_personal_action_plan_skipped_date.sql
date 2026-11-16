\set ON_ERROR_STOP on
DO $check$
DECLARE helper pg_proc%ROWTYPE; expected_owner oid;
BEGIN
  SELECT * INTO STRICT helper FROM pg_proc WHERE oid='app_private.personal_action_plan_cycle_until_v2(timestamptz,text,integer)'::regprocedure;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc WHERE oid='app_data.personal_action_plan_document(uuid,timestamptz)'::regprocedure;
  IF helper.proowner<>expected_owner OR helper.prosecdef OR helper.provolatile<>'s' OR helper.proparallel<>'s'
    OR helper.prorettype<>'timestamptz'::regtype OR helper.proretset OR helper.prosqlbody IS NULL OR helper.proconfig IS NOT NULL
    OR helper.prolang<>(SELECT oid FROM pg_language WHERE lanname='sql')
    OR has_function_privilege('tongxingzhe_runtime',helper.oid,'EXECUTE')
    OR EXISTS(SELECT 1 FROM aclexplode(coalesce(helper.proacl,acldefault('f',helper.proowner))) acl WHERE acl.grantee<>helper.proowner) THEN
    RAISE EXCEPTION '0163 configured-weekday helper metadata, owner, or private privileges drift';
  END IF;
  IF app_private.personal_action_plan_cycle_until_v2(timestamptz '2011-12-30 10:00Z','Pacific/Apia',5) IS DISTINCT FROM timestamptz '2012-01-05 10:00Z'
    OR app_private.personal_action_plan_cycle_until_v2(timestamptz '2011-12-30 10:00Z','Pacific/Apia',6) IS DISTINCT FROM timestamptz '2012-01-06 10:00Z'
    OR app_data.personal_action_plan_cycle_until(timestamptz '2011-12-30 10:00Z','Pacific/Apia') IS DISTINCT FROM timestamptz '2012-01-06 10:00Z' THEN
    RAISE EXCEPTION '0163 configured nominal weekday or preserved legacy two-argument boundary differs';
  END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0163_personal_action_plan_skipped_date')<>1 THEN
    RAISE EXCEPTION '0163 personal plan skipped-date migration was not recorded once';
  END IF;
END
$check$;
SELECT 'personal action plan configured-weekday boundary and private privileges: passed' AS result;
