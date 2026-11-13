\set ON_ERROR_STOP on

DO $check$
DECLARE
  function_row pg_proc%ROWTYPE;
  expression text := $expression$authorization_reference_at_utc :=
    pg_catalog.clock_timestamp();$expression$;
BEGIN
  SELECT * INTO STRICT function_row FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'::regprocedure;
  IF function_row.proowner <> 'tongxingzhe_management_follow_up_consent_config_writer'::regrole
    OR NOT function_row.prosecdef OR function_row.provolatile <> 'v'
    OR function_row.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, app_data']::text[]
    OR function_row.prolang <> (SELECT oid FROM pg_catalog.pg_language WHERE lanname = 'plpgsql')
    OR EXISTS (
      SELECT 1 FROM pg_catalog.aclexplode(COALESCE(
        function_row.proacl, pg_catalog.acldefault('f', function_row.proowner)
      )) acl WHERE acl.grantee <> function_row.proowner
    )
  THEN RAISE EXCEPTION 'opt-in authorization precision function metadata or ACL drifted'; END IF;
  IF length(function_row.prosrc) - length(replace(function_row.prosrc, expression, ''))
      <> length(expression)
    OR position($old$(authorization_evidence->>'reference_at_utc')::timestamptz$old$ IN function_row.prosrc) <> 0
  THEN RAISE EXCEPTION 'opt-in provenance must sample a full-precision timestamp after authorization'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0154_management_follow_up_consent_opt_in_precision') <> 1
  THEN RAISE EXCEPTION '0154 opt-in authorization precision migration was not recorded once'; END IF;
END
$check$;

SELECT 'management follow-up consent opt-in authorization precision: passed' AS result;
