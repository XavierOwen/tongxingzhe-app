\set ON_ERROR_STOP on
DO $check$
DECLARE
  activation regprocedure :=
    'app_private.activate_personal_target_merge_generation_v2(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  body text;
  validation_tail text := $validation$      MESSAGE = 'invalid personal target merge activation request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target merge generation activation requires read committed';
  END IF;
$guard$;
  guard_position integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0146_personal_target_merge_activation_isolation') THEN
    RAISE EXCEPTION '0146 activation isolation migration is missing';
  END IF;
  SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = activation;
  guard_position := position(guard IN body);
  IF guard_position = 0
    OR length(body) - length(replace(body, guard, '')) <> length(guard)
    OR position(validation_tail || guard || '  SELECT workspace_row.workspace_id INTO trusted_workspace_id' IN body) = 0
    OR position('SELECT workspace_row.workspace_id INTO trusted_workspace_id' IN body) <= guard_position
    OR position('pg_advisory_xact_lock' IN body) <= guard_position
    OR position('SELECT request_row.* INTO replay_row' IN body) <= guard_position
    OR has_function_privilege('public', activation, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', activation, 'EXECUTE') THEN
    RAISE EXCEPTION '0146 v2 activation isolation order or private ACL drift';
  END IF;
END
$check$;
