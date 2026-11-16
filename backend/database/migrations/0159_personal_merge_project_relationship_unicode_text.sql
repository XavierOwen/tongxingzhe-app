-- Reject new blank Unicode text while preserving exact replay of existing payloads.
DO $unicode_text$
DECLARE
  original pg_proc%ROWTYPE;
  anchor text := $anchor$  pending_id := gen_random_uuid();$anchor$;
  guard text := $guard$  IF EXISTS (
    SELECT 1 FROM (VALUES (requested_follow_up_note), (requested_reason_detail)) AS field(value)
    WHERE field.value IS NOT NULL AND pg_catalog.btrim(field.value,
      U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF') = ''
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid unassigned project relationship request';
  END IF;

$guard$;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.stage_unassigned_personal_merge_project_relationship_v1(uuid,uuid,uuid,uuid,uuid,integer,text,text,text,text)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, anchor, '')) <> length(anchor)
    OR position(guard IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0159 unassigned project relationship Unicode text anchor unavailable';
  END IF;
  EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), anchor, guard || anchor);
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND changed.prosrc = replace(original.prosrc, anchor, guard || anchor)
  ) THEN RAISE EXCEPTION '0159 unassigned project relationship Unicode text changed metadata or unrelated implementation'; END IF;
END
$unicode_text$;
