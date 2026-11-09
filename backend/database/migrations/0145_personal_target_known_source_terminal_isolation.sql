-- Authorization must see changes committed while a request waits.
DO $isolation$
DECLARE
  operation record;
  original pg_catalog.pg_proc%ROWTYPE;
  validation_tail text;
  guard text;
  expected_source text;
BEGIN
  FOR operation IN SELECT * FROM (VALUES
    ('end', 'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure),
    ('expiry', 'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure)
  ) AS writers(action, function_id) LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc WHERE oid = operation.function_id;
    validation_tail := format(E'      MESSAGE = %L;\n  END IF;\n\n',
      format('invalid known-source personal target merge %s request', operation.action));
    guard := format($guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = %L;
  END IF;
$guard$, format('known-source personal target merge %s requires read committed', operation.action));
    IF length(original.prosrc) - length(replace(original.prosrc, validation_tail, '')) <> length(validation_tail)
      OR position(validation_tail || '  IF NOT app_data.promotion_target_context_authorized(' IN original.prosrc) = 0
      OR position(guard IN original.prosrc) <> 0 THEN
      RAISE EXCEPTION '0145 known-source % isolation anchor unavailable', operation.action;
    END IF;
    expected_source := replace(original.prosrc, validation_tail, validation_tail || guard);
    EXECUTE replace(pg_get_functiondef(original.oid), validation_tail, validation_tail || guard);
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
      WHERE changed.oid = original.oid
        AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
        AND changed.prosrc = expected_source) THEN
      RAISE EXCEPTION '0145 known-source % metadata or body drift', operation.action;
    END IF;
  END LOOP;
END
$isolation$;
