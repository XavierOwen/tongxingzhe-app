-- A new preview must use the current statement snapshot for assignment eligibility.
DO $isolation$
DECLARE
  original pg_catalog.pg_proc%ROWTYPE;
  begin_marker text := E'BEGIN\n';
  query_marker text := $query$  RETURN QUERY
  WITH facts AS MATERIALIZED (
$query$;
  guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target pair preview requires read committed';
  END IF;
$guard$;
  entry_anchor text := begin_marker || query_marker;
  expected_entry text := begin_marker || guard || query_marker;
  expected_source text;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
    WHERE oid = 'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure;
  IF position(entry_anchor IN original.prosrc) <> 2
    OR length(original.prosrc) - length(replace(original.prosrc, entry_anchor, '')) <> length(entry_anchor)
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0149 pair preview isolation anchor unavailable';
  END IF;
  expected_source := replace(original.prosrc, entry_anchor, expected_entry);
  EXECUTE replace(pg_get_functiondef(original.oid), entry_anchor, expected_entry);
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = expected_source) THEN
    RAISE EXCEPTION '0149 pair preview metadata or body drift';
  END IF;
END
$isolation$;
