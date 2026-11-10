-- A staged-contact replay must recheck current authorization after waiting.
DO $isolation$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  validation_tail text := $validation$    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid unassigned contact request';
  END IF;

$validation$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'unassigned contact staging requires read committed';
  END IF;
$guard$;
  expected_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, validation_tail, '')) <> length(validation_tail)
    OR position(validation_tail || '  PERFORM pg_advisory_xact_lock(hashtextextended(' IN original.prosrc) = 0
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0150 unassigned contact staging isolation anchor unavailable';
  END IF;
  expected_source := replace(original.prosrc, validation_tail, validation_tail || guard);
  EXECUTE replace(pg_get_functiondef(original.oid), validation_tail, validation_tail || guard);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = expected_source) THEN
    RAISE EXCEPTION '0150 unassigned contact staging metadata or body drift';
  END IF;
END
$isolation$;
