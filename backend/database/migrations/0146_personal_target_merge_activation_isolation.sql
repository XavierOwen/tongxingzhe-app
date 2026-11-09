-- Activation must see authorization changes committed while the request waits.
DO $isolation$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  validation_tail text := $validation$      MESSAGE = 'invalid personal target merge activation request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target merge generation activation requires read committed';
  END IF;
$guard$;
  expected_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.activate_personal_target_merge_generation_v2(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, validation_tail, '')) <> length(validation_tail)
    OR position(validation_tail || '  SELECT workspace_row.workspace_id INTO trusted_workspace_id' IN original.prosrc) = 0
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0146 v2 activation isolation anchor unavailable';
  END IF;
  expected_source := replace(original.prosrc, validation_tail, validation_tail || guard);
  EXECUTE replace(pg_get_functiondef(original.oid), validation_tail, validation_tail || guard);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = expected_source) THEN
    RAISE EXCEPTION '0146 v2 activation metadata or body drift';
  END IF;
END
$isolation$;
