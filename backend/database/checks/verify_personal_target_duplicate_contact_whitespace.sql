\set ON_ERROR_STOP on

DO $check$
DECLARE
  helper pg_proc%ROWTYPE;
  trusted_owner oid;
BEGIN
  SELECT * INTO STRICT helper FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.personal_target_duplicate_contact_signal_v1(text)'::regprocedure;
  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure;
  IF helper.proowner <> trusted_owner OR helper.prosecdef
    OR helper.provolatile <> 'i' OR helper.proparallel <> 's'
    OR helper.prorettype <> 'text'::regtype OR helper.prosqlbody IS NULL
    OR helper.proconfig IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(helper.proacl) acl
      WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE')
    OR pg_catalog.has_function_privilege('tongxingzhe_runtime', helper.oid, 'EXECUTE')
  THEN
    RAISE EXCEPTION 'duplicate contact signal helper contract drifted';
  END IF;
END
$check$;
