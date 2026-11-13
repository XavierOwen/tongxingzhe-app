-- Opt-in provenance must retain microseconds independently of report JSON formatting.
DO $precision$
DECLARE
  original pg_proc%ROWTYPE;
  old_expression text := $old$authorization_reference_at_utc :=
    (authorization_evidence->>'reference_at_utc')::timestamptz;$old$;
  new_expression text := $new$authorization_reference_at_utc :=
    pg_catalog.clock_timestamp();$new$;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, old_expression, ''))
      <> length(old_expression)
    OR position(new_expression IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0154 opt-in authorization precision anchor unavailable';
  END IF;
  EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), old_expression, new_expression);
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = replace(original.prosrc, old_expression, new_expression)
  ) THEN
    RAISE EXCEPTION '0154 opt-in precision changed metadata or unrelated implementation';
  END IF;
END
$precision$;
