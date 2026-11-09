-- Legacy activation must see authorization changes committed while it waits.
DO $isolation$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  entry_anchor text := $entry$DECLARE
  created_generation_id uuid;
BEGIN
$entry$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'legacy personal target merge generation activation requires read committed';
  END IF;
$guard$;
  expected_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'::regprocedure;
  IF position(entry_anchor IN original.prosrc) <> 2
    OR length(original.prosrc) - length(replace(original.prosrc, entry_anchor, '')) <> length(entry_anchor)
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0148 legacy activation isolation anchor unavailable';
  END IF;
  expected_source := replace(original.prosrc, entry_anchor, entry_anchor || guard);
  EXECUTE replace(pg_get_functiondef(original.oid), entry_anchor, entry_anchor || guard);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = expected_source) THEN
    RAISE EXCEPTION '0148 legacy activation metadata or body drift';
  END IF;
END
$isolation$;
