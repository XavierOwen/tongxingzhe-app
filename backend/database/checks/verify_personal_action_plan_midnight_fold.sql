\set ON_ERROR_STOP on
DO $check$
DECLARE helper pg_proc%ROWTYPE; expected_owner oid; original_signature regprocedure;
BEGIN
  SELECT * INTO STRICT helper FROM pg_proc WHERE oid='app_private.personal_action_plan_local_midnight_v1(date,text)'::regprocedure;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc WHERE oid='app_data.personal_action_plan_cycle_start(timestamptz,text,integer)'::regprocedure;
  IF helper.proowner<>expected_owner OR helper.prosecdef OR helper.provolatile<>'s' OR helper.proparallel<>'s'
    OR helper.prorettype<>'timestamptz'::regtype OR helper.proretset OR helper.prosqlbody IS NULL OR helper.proconfig IS NOT NULL
    OR helper.prolang<>(SELECT oid FROM pg_language WHERE lanname='sql')
    OR has_function_privilege('tongxingzhe_runtime',helper.oid,'EXECUTE')
    OR EXISTS (SELECT 1 FROM aclexplode(coalesce(helper.proacl,acldefault('f',helper.proowner))) acl WHERE acl.grantee<>helper.proowner)
    OR EXISTS (SELECT 1 FROM pg_depend dependency JOIN pg_proc called ON called.oid=dependency.refobjid
      WHERE dependency.classid='pg_proc'::regclass AND dependency.objid=helper.oid AND dependency.refclassid='pg_proc'::regclass
        AND called.pronamespace<>'pg_catalog'::regnamespace)
  THEN RAISE EXCEPTION '0162 local-midnight helper signature, builtin dependencies, owner, or private privileges drift'; END IF;
  FOREACH original_signature IN ARRAY ARRAY['app_data.personal_action_plan_cycle_start(timestamptz,text,integer)'::regprocedure,
    'app_data.personal_action_plan_cycle_until(timestamptz,text)'::regprocedure] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=original_signature AND proowner=expected_owner AND prosecdef AND provolatile='s'
        AND prorettype='timestamptz'::regtype AND NOT proretset AND proconfig=ARRAY['search_path=pg_catalog, app_data'])
      OR has_function_privilege('tongxingzhe_runtime',original_signature,'EXECUTE')
      OR EXISTS(SELECT 1 FROM pg_proc original CROSS JOIN LATERAL aclexplode(coalesce(original.proacl,acldefault('f',original.proowner))) acl
        WHERE original.oid=original_signature AND acl.grantee<>original.proowner) THEN
      RAISE EXCEPTION '0162 original cycle helper metadata or private privileges drift: %',original_signature;
    END IF;
  END LOOP;
  IF app_private.personal_action_plan_local_midnight_v1(date '2026-11-01','America/Havana') IS DISTINCT FROM timestamptz '2026-11-01 04:00Z'
    OR app_private.personal_action_plan_local_midnight_v1(date '2010-03-05','Antarctica/Casey') IS DISTINCT FROM timestamptz '2010-03-04 13:00Z'
    OR app_private.personal_action_plan_local_midnight_v1(date '2026-03-08','America/Havana') IS DISTINCT FROM
      (timestamp '2026-03-08 00:00' AT TIME ZONE 'America/Havana') THEN
    RAISE EXCEPTION '0162 earliest exact midnight or original gap fallback differs';
  END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0162_personal_action_plan_midnight_fold')<>1 THEN
    RAISE EXCEPTION '0162 personal plan midnight fold migration was not recorded once';
  END IF;
END
$check$;
SELECT 'personal action plan earliest midnight helper and private privileges: passed' AS result;
