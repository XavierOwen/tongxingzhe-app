DO $redaction$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  old_set_clause text := $old$  SET follow_up_note = NULL, reason_detail = NULL,
      requested_follow_up_note = NULL
  WHERE promotion_target_id = requested_target_id
    AND (follow_up_note IS NOT NULL OR reason_detail IS NOT NULL
      OR requested_follow_up_note IS NOT NULL);$old$;
  new_set_clause text := $new$  SET follow_up_note = NULL,
      reason_detail = CASE WHEN reason_code = 'other'
        THEN '[已匿名化]' ELSE NULL END,
      requested_follow_up_note = NULL
  WHERE promotion_target_id = requested_target_id
    AND (follow_up_note IS NOT NULL OR reason_detail IS NOT NULL
      OR requested_follow_up_note IS NOT NULL);$new$;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
  WHERE oid = 'app_data.anonymize_promotion_target_internal(uuid,uuid,text,timestamptz)'::regprocedure;
  definition := pg_catalog.pg_get_functiondef(original.oid);
  IF length(original.prosrc) - length(replace(original.prosrc, old_set_clause, '')) <> length(old_set_clause)
    OR position(new_set_clause IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0139 historical relationship redaction anchor unavailable';
  END IF;
  EXECUTE replace(definition, old_set_clause, new_set_clause);
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND replace(changed.prosrc, new_set_clause, '') = replace(original.prosrc, old_set_clause, '')
  ) THEN
    RAISE EXCEPTION '0139 relationship redaction changed metadata or unrelated implementation';
  END IF;
END
$redaction$;
