\set ON_ERROR_STOP on
DO $check$
DECLARE validator pg_proc%ROWTYPE; expected_owner oid;
BEGIN
  SELECT * INTO STRICT validator FROM pg_proc WHERE oid='app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)'::regprocedure;
  SELECT proowner INTO STRICT expected_owner FROM pg_proc
    WHERE oid='app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)'::regprocedure;
  IF validator.proowner<>expected_owner OR NOT validator.prosecdef OR validator.provolatile<>'s' OR validator.proretset
    OR validator.prorettype<>'jsonb'::regtype OR validator.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, app_private']
    OR has_function_privilege('tongxingzhe_runtime',validator.oid,'EXECUTE')
    OR EXISTS(SELECT 1 FROM aclexplode(coalesce(validator.proacl,acldefault('f',validator.proowner))) acl WHERE acl.grantee=0)
    OR position('[89ab][0-9]{3}' IN validator.prosrc)<>0 OR position('[89ab][0-9a-f]{3}' IN validator.prosrc)=0 THEN
    RAISE EXCEPTION '0165 consent canonical UUID validator metadata, private privileges, or hexadecimal group drift';
  END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0165_management_consent_project_uuid')<>1 THEN
    RAISE EXCEPTION '0165 consent project UUID migration was not recorded once';
  END IF;
END
$check$;
SELECT 'consent hexadecimal UUID group and preserved private validator metadata: passed' AS result;
