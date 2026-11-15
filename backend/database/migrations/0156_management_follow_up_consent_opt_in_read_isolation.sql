-- Advisory locks cannot refresh the authorization facts in an older transaction snapshot.
DO $isolation$
DECLARE
  original pg_proc%ROWTYPE;
  prelude text := $prelude$      MESSAGE = 'invalid management follow-up consent opt-in read';
  END IF;

$prelude$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'management follow-up consent opt-in read requires read committed';
  END IF;

$guard$;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, prelude, '')) <> length(prelude)
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0156 opt-in read isolation anchor unavailable';
  END IF;
  EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), prelude, prelude || guard);
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = replace(original.prosrc, prelude, prelude || guard)
  ) THEN RAISE EXCEPTION '0156 opt-in read isolation changed metadata or unrelated implementation'; END IF;
END
$isolation$;
