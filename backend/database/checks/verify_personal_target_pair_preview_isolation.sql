\set ON_ERROR_STOP on
DO $check$
DECLARE
  preview regprocedure := 'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure;
  body text;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target pair preview requires read committed';
  END IF;
$guard$;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0149_personal_target_pair_preview_isolation') THEN
    RAISE EXCEPTION '0149 pair preview isolation migration is missing';
  END IF;
  SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = preview;
  IF position(E'BEGIN\n' || guard || E'  RETURN QUERY\n  WITH facts AS MATERIALIZED (\n' IN body) <> 2
    OR length(body) - length(replace(body, guard, '')) <> length(guard)
    OR has_function_privilege('public', preview, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', preview, 'EXECUTE') THEN
    RAISE EXCEPTION '0149 pair preview isolation order or private ACL drift';
  END IF;
END
$check$;
