-- Preserve the canonical UUID/version/variant contract; all suffixes are hex.
DO $uuid_rule$
DECLARE
  function_row pg_proc%ROWTYPE;
  definition text;
  old_pattern text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9]{3}-[89ab][0-9]{3}-[0-9a-f]{12}$';
  new_pattern text := '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
BEGIN
  SELECT * INTO STRICT function_row FROM pg_proc
  WHERE oid='app_private.validate_management_original_region_report_document_v1(jsonb)'::regprocedure;
  definition := pg_get_functiondef(function_row.oid);
  IF length(definition)-length(replace(definition,old_pattern,'')) <> length(old_pattern) THEN
    RAISE EXCEPTION '0110 original-region project UUID rule unavailable';
  END IF;
  EXECUTE replace(definition,old_pattern,new_pattern);
  IF NOT EXISTS (SELECT 1 FROM pg_proc replaced WHERE replaced.oid=function_row.oid
      AND replaced.proowner=function_row.proowner AND replaced.proacl IS NOT DISTINCT FROM function_row.proacl
      AND replaced.prosecdef=function_row.prosecdef AND replaced.provolatile=function_row.provolatile
      AND replaced.proconfig IS NOT DISTINCT FROM function_row.proconfig) THEN
    RAISE EXCEPTION '0110 original-region validator owner/security/ACL drift';
  END IF;
END
$uuid_rule$;
