-- Each authorized projection must see project changes committed before its query.
DO $isolation$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  validation_tail text := $validation$      MESSAGE = 'invalid authorized known-source personal target merge projection request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'authorized personal target merge projection requires read committed';
  END IF;
$guard$;
  expected_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, validation_tail, '')) <> length(validation_tail)
    OR position(validation_tail || '  -- Personal ownership derives both PII-view and merge-management capabilities, as in 0113.' IN original.prosrc) = 0
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0151 authorized projection isolation anchor unavailable';
  END IF;
  expected_source := replace(original.prosrc, validation_tail, validation_tail || guard);
  EXECUTE replace(pg_get_functiondef(original.oid), validation_tail, validation_tail || guard);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = expected_source) THEN
    RAISE EXCEPTION '0151 authorized projection metadata or body drift';
  END IF;
END
$isolation$;
