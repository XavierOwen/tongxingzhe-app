\set ON_ERROR_STOP on
DO $check$
DECLARE
  writer regprocedure := 'app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  body text;
  validation_tail text := $validation$      MESSAGE = 'invalid personal target assignment end request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target assignment end requires read committed';
  END IF;
$guard$;
  guard_position integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0147_personal_target_assignment_end_isolation') THEN
    RAISE EXCEPTION '0147 assignment end isolation migration is missing';
  END IF;
  SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = writer;
  guard_position := position(guard IN body);
  IF guard_position = 0
    OR length(body) - length(replace(body, guard, '')) <> length(guard)
    OR position(validation_tail || guard || '  IF NOT app_data.promotion_target_context_authorized(' IN body) = 0
    OR position('  IF NOT app_data.promotion_target_context_authorized(' IN body) <> guard_position + length(guard)
    OR position('acquire_personal_target_merge_generation_fence_v1' IN body) <= guard_position
    OR position('SELECT event_row.* INTO replay_row' IN body) <= guard_position
    OR has_function_privilege('public', writer, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', writer, 'EXECUTE') THEN
    RAISE EXCEPTION '0147 assignment end isolation order or private ACL drift';
  END IF;
END
$check$;
