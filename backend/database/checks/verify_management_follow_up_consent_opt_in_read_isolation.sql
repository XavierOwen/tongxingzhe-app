\set ON_ERROR_STOP on
DO $check$
DECLARE
  function_row pg_proc%ROWTYPE;
  prelude text := $prelude$      MESSAGE = 'invalid management follow-up consent opt-in read';
  END IF;

$prelude$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'management follow-up consent opt-in read requires read committed';
  END IF;

$guard$;
BEGIN
  SELECT * INTO STRICT function_row FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)'::regprocedure;
  IF position(prelude || guard || '  PERFORM app_private.resolve_management_report_authorization_v1(' IN function_row.prosrc) = 0
    OR length(function_row.prosrc) - length(replace(function_row.prosrc, guard, '')) <> length(guard)
    OR function_row.proowner <> 'tongxingzhe_management_follow_up_consent_config_writer'::regrole
    OR NOT function_row.prosecdef OR function_row.provolatile <> 'v'
    OR function_row.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, app_data']::text[]
    OR function_row.prolang <> (SELECT oid FROM pg_catalog.pg_language WHERE lanname = 'plpgsql')
    OR EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
        function_row.proacl, pg_catalog.acldefault('f', function_row.proowner)
      )) acl WHERE acl.grantee <> function_row.proowner
    )
  THEN RAISE EXCEPTION 'opt-in read isolation order, function metadata or ACL drifted'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0156_management_follow_up_consent_opt_in_read_isolation') <> 1
  THEN RAISE EXCEPTION '0156 opt-in read isolation migration was not recorded once'; END IF;
END
$check$;
SELECT 'private management follow-up consent opt-in read isolation: passed' AS result;
