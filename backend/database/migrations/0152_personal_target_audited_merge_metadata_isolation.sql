-- Audited metadata reads must see project changes committed before their query.
DO $isolation$
DECLARE
  reader record;
  original pg_catalog.pg_proc%ROWTYPE;
  anchor text := '  WITH context AS MATERIALIZED (';
  guard text;
  expected_source text;
BEGIN
  FOR reader IN SELECT * FROM (VALUES
    ('app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure,
      'authorized personal merge split plan requires read committed',
      $split$      MESSAGE = 'invalid authorized known-source merge split plan request';
  END IF;

$split$),
    ('app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid)'::regprocedure,
      'authorized personal merge directory requires read committed', E'BEGIN\n')
  ) AS readers(signature, failure_message, prelude) LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc WHERE oid = reader.signature;
    guard := format($guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = %L;
  END IF;
$guard$, reader.failure_message);
    IF length(original.prosrc) - length(replace(original.prosrc, anchor, '')) <> length(anchor)
      OR position(reader.prelude || anchor IN original.prosrc) = 0
      OR position(guard IN original.prosrc) <> 0 THEN
      RAISE EXCEPTION '0152 audited merge metadata isolation anchor unavailable: %', reader.signature;
    END IF;
    expected_source := replace(original.prosrc, anchor, guard || anchor);
    EXECUTE replace(pg_get_functiondef(original.oid), anchor, guard || anchor);
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed
      WHERE changed.oid = original.oid
        AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
        AND changed.prosrc = expected_source) THEN
      RAISE EXCEPTION '0152 audited merge metadata function or body drift: %', reader.signature;
    END IF;
  END LOOP;
END
$isolation$;
