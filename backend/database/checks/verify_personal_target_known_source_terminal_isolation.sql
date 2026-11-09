\set ON_ERROR_STOP on
DO $check$
DECLARE
  operation record;
  body text;
  guard text;
  guard_position integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0145_personal_target_known_source_terminal_isolation') THEN
    RAISE EXCEPTION '0145 known-source terminal isolation migration is missing';
  END IF;
  FOR operation IN SELECT * FROM (VALUES
    ('end', 'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure),
    ('expiry', 'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure)
  ) AS writers(action, function_id) LOOP
    SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = operation.function_id;
    guard := format($guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = %L;
  END IF;
$guard$, format('known-source personal target merge %s requires read committed', operation.action));
    guard_position := position(guard IN body);
    IF guard_position = 0
      OR length(body) - length(replace(body, guard, '')) <> length(guard)
      OR position('  IF NOT app_data.promotion_target_context_authorized(' IN body) <> guard_position + length(guard)
      OR position('pg_advisory_xact_lock' IN body) <= guard_position
      OR position('SELECT event_row.* INTO replay_row' IN body) <= guard_position
      OR has_function_privilege('public', operation.function_id, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', operation.function_id, 'EXECUTE') THEN
      RAISE EXCEPTION '0145 known-source % isolation order or private ACL drift', operation.action;
    END IF;
  END LOOP;
END
$check$;
