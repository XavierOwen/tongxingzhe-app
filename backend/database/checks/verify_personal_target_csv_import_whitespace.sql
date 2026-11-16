\set ON_ERROR_STOP on

DO $check$
DECLARE
  legacy pg_proc%ROWTYPE;
  current_normalizer pg_proc%ROWTYPE;
BEGIN
  SELECT * INTO STRICT legacy FROM pg_catalog.pg_proc
  WHERE oid='app_private.canonical_personal_target_csv_import_rows_v1(jsonb)'::regprocedure;
  SELECT * INTO STRICT current_normalizer FROM pg_catalog.pg_proc
  WHERE oid='app_private.canonical_personal_target_csv_import_rows_v2(jsonb)'::regprocedure;
  IF to_jsonb(current_normalizer)-ARRAY['oid','proname','prosrc']
      IS DISTINCT FROM to_jsonb(legacy)-ARRAY['oid','proname','prosrc']
    OR pg_catalog.has_function_privilege('tongxingzhe_runtime',current_normalizer.oid,'EXECUTE')
    OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(current_normalizer.proacl) acl
      WHERE acl.grantee=0 AND acl.privilege_type='EXECUTE')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute attribute
      WHERE attribute.attrelid='app_private.personal_target_csv_import_previews'::regclass
        AND attribute.attname='normalization_version' AND NOT attribute.attisdropped
        AND attribute.atttypid='smallint'::regtype AND attribute.attnotnull)
  THEN RAISE EXCEPTION 'versioned CSV field normalization contract drifted'; END IF;
END
$check$;
