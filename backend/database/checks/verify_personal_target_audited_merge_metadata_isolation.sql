\set ON_ERROR_STOP on
DO $check$
DECLARE
  reader record;
  body text;
  anchor text := '  WITH context AS MATERIALIZED (';
  guard text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
    WHERE version = '0152_personal_target_audited_merge_metadata_isolation') THEN
    RAISE EXCEPTION '0152 audited merge metadata isolation migration is missing';
  END IF;
  FOR reader IN SELECT * FROM (VALUES
    ('app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure,
      'app_data.read_personal_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure,
      'authorized personal merge split plan requires read committed',
      $split$      MESSAGE = 'invalid authorized known-source merge split plan request';
  END IF;

$split$),
    ('app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid)'::regprocedure,
      'app_data.read_personal_merge_directory_v1(text,text,uuid,uuid)'::regprocedure,
      'authorized personal merge directory requires read committed', E'BEGIN\n')
  ) AS readers(signature, bridge, failure_message, prelude) LOOP
    guard := format($guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = %L;
  END IF;
$guard$, reader.failure_message);
    SELECT prosrc INTO STRICT body FROM pg_catalog.pg_proc WHERE oid = reader.signature;
    IF position(reader.prelude || guard || anchor IN body) = 0
      OR length(body) - length(replace(body, guard, '')) <> length(guard)
      OR has_function_privilege('public', reader.signature, 'EXECUTE')
      OR has_function_privilege('tongxingzhe_runtime', reader.signature, 'EXECUTE')
      OR has_function_privilege('public', reader.bridge, 'EXECUTE')
      OR NOT has_function_privilege('tongxingzhe_runtime', reader.bridge, 'EXECUTE') THEN
      RAISE EXCEPTION '0152 audited merge metadata isolation order or existing ACL drift: %', reader.signature;
    END IF;
  END LOOP;
END
$check$;
