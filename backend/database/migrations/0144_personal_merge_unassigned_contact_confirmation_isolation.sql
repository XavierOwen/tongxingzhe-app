-- A transaction-wide snapshot cannot recheck current authorization after waiting.
DO $isolation$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  parent_lock text := $parent$  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));$parent$;
  isolation_guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'pending contact confirmation requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT original FROM pg_proc
    WHERE oid = 'app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
  definition := pg_get_functiondef(original.oid);
  IF length(definition) - length(replace(definition, parent_lock, '')) <> length(parent_lock)
    OR position(isolation_guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0144 single-contact confirmation isolation anchor unavailable';
  END IF;
  EXECUTE replace(definition, parent_lock, isolation_guard || parent_lock);
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND replace(changed.prosrc, isolation_guard, '') = original.prosrc) THEN
    RAISE EXCEPTION '0144 single-contact confirmation metadata or implementation drift';
  END IF;
END
$isolation$;
