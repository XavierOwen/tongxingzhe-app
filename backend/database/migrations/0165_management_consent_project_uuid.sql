DO $uuid$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  old_expression text := '[89ab][0-9]{3}';
  new_expression text := '[89ab][0-9a-f]{3}';
  changed_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, old_expression, ''))
      <> length(old_expression) THEN
    RAISE EXCEPTION '0165 consent project UUID anchor unavailable';
  END IF;
  changed_source := replace(original.prosrc, old_expression, new_expression);
  EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, changed_source);
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = changed_source
  ) THEN
    RAISE EXCEPTION '0165 changed consent validator metadata or unrelated implementation';
  END IF;
END
$uuid$;
