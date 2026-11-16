\set ON_ERROR_STOP on
DO $check$
DECLARE f pg_proc%ROWTYPE; contact_key text; size integer;
BEGIN
  SELECT * INTO STRICT f FROM pg_proc WHERE oid='app_private.personal_merge_contact_child_key_v1(text)'::regprocedure;
  IF f.prosecdef OR f.provolatile<>'i' OR f.proconfig IS NOT NULL OR f.prosqlbody IS NULL OR f.proparallel<>'s'
    OR f.proowner<>(SELECT proowner FROM pg_proc WHERE oid='app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)'::regprocedure)
    OR has_function_privilege('tongxingzhe_runtime',f.oid,'EXECUTE')
    OR EXISTS(SELECT 1 FROM aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) acl WHERE acl.grantee=0)
  THEN RAISE EXCEPTION 'bounded private child helper metadata or PUBLIC/runtime privilege drift'; END IF;
  FOREACH size IN ARRAY ARRAY[0,64,2048,2049,2600] LOOP
    contact_key:=repeat('x',size);
    IF app_private.personal_merge_contact_child_key_v1(contact_key) IS DISTINCT FROM
      (CASE WHEN size<=2048 THEN size||':'||contact_key ELSE 'sha256-v2:'||encode(sha256(convert_to(contact_key,'UTF8')),'hex') END)
    THEN RAISE EXCEPTION 'child suffix boundary differs at % UTF8 bytes',size; END IF;
  END LOOP;
  contact_key:=repeat('汉',682)||'abc';
  IF length(contact_key)>=2048 OR octet_length(contact_key)<>2049
    OR app_private.personal_merge_contact_child_key_v1(contact_key) IS DISTINCT FROM 'sha256-v2:'||encode(sha256(convert_to(contact_key,'UTF8')),'hex')
    OR app_private.personal_merge_contact_child_key_v1(NULL) IS NOT NULL
  THEN RAISE EXCEPTION 'child key threshold must use UTF8 bytes and preserve NULL semantics'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0160_personal_merge_bounded_child_commands')<>1 THEN
    RAISE EXCEPTION '0160 bounded child command migration was not recorded once';
  END IF;
END
$check$;
SELECT 'personal merge bounded child command suffix and private privileges: passed' AS result;
