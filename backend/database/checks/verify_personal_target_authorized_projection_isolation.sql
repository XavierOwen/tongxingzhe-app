\set ON_ERROR_STOP on
DO $check$
DECLARE
  reader regprocedure := 'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  bridge regprocedure := 'app_data.read_personal_known_source_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  body text;
  validation_tail text := $validation$      MESSAGE = 'invalid authorized known-source personal target merge projection request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'authorized personal target merge projection requires read committed';
  END IF;
$guard$;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0151_personal_target_authorized_projection_isolation') THEN
    RAISE EXCEPTION '0151 authorized projection isolation migration is missing';
  END IF;
  SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = reader;
  IF position(validation_tail || guard || '  -- Personal ownership derives both PII-view and merge-management capabilities, as in 0113.' IN body) = 0
    OR length(body) - length(replace(body, guard, '')) <> length(guard)
    OR position('  WITH context AS MATERIALIZED (' IN body) <= position(guard IN body)
    OR has_function_privilege('public', reader, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', reader, 'EXECUTE')
    OR has_function_privilege('public', bridge, 'EXECUTE')
    OR NOT has_function_privilege('tongxingzhe_runtime', bridge, 'EXECUTE') THEN
    RAISE EXCEPTION '0151 authorized projection isolation order or existing ACL drift';
  END IF;
END
$check$;
