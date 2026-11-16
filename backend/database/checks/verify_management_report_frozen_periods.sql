\set ON_ERROR_STOP on
DO $check$
DECLARE item record; validator pg_proc%ROWTYPE; expected_owner oid;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('validate_management_interest_report_document_v1','release_management_interest_report_snapshot_v1','void',ARRAY['search_path=pg_catalog, app_data, app_private']),
    ('validate_management_current_city_report_document_v1','release_management_current_city_report_snapshot_v1','void',ARRAY['search_path=pg_catalog, app_data, app_private']),
    ('validate_management_original_region_report_document_v1','release_management_original_region_report_snapshot_v1','void',ARRAY['search_path=pg_catalog, app_data, app_private']),
    ('validate_management_follow_up_consent_ratio_report_document_v1','release_management_follow_up_consent_ratio_report_snapshot_v1','jsonb',ARRAY['search_path=pg_catalog, app_private'])
  ) AS validators(function_name,release_name,result_type,config) LOOP
    SELECT * INTO STRICT validator FROM pg_proc WHERE oid=('app_private.'||item.function_name||'(jsonb)')::regprocedure;
    SELECT proowner INTO STRICT expected_owner FROM pg_proc WHERE oid=('app_private.'||item.release_name||'(uuid,uuid,uuid,text,integer)')::regprocedure;
    IF validator.proowner<>expected_owner OR NOT validator.prosecdef OR validator.provolatile<>'s' OR validator.proretset
      OR validator.prorettype<>item.result_type::regtype OR validator.proconfig IS DISTINCT FROM item.config
      OR has_function_privilege('tongxingzhe_runtime',validator.oid,'EXECUTE')
      OR EXISTS(SELECT 1 FROM aclexplode(coalesce(validator.proacl,acldefault('f',validator.proowner))) acl WHERE acl.grantee=0) THEN
      RAISE EXCEPTION '0164 existing document validator owner, metadata, or private privileges drift: %',item.function_name;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0164_management_report_frozen_periods')<>1 THEN
    RAISE EXCEPTION '0164 frozen report periods migration was not recorded once';
  END IF;
END
$check$;
SELECT 'four frozen-period document validator signatures and private privileges: passed' AS result;
