-- Assignment end must see authorization changes committed while it waits.
DO $isolation$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  validation_tail text := $validation$      MESSAGE = 'invalid personal target assignment end request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target assignment end requires read committed';
  END IF;
$guard$;
  expected_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, validation_tail, '')) <> length(validation_tail)
    OR position(validation_tail || '  IF NOT app_data.promotion_target_context_authorized(' IN original.prosrc) = 0
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0147 assignment end isolation anchor unavailable';
  END IF;
  expected_source := replace(original.prosrc, validation_tail, validation_tail || guard);
  EXECUTE replace(pg_get_functiondef(original.oid), validation_tail, validation_tail || guard);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = expected_source) THEN
    RAISE EXCEPTION '0147 assignment end metadata or body drift';
  END IF;
END
$isolation$;
