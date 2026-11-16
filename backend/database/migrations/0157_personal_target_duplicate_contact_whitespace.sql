-- Bound SQL body keeps duplicate comparisons inline without changing stored PII.
CREATE FUNCTION app_private.personal_target_duplicate_contact_signal_v1(requested_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
RETURN NULLIF(pg_catalog.btrim(requested_value,
  U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'), '');

REVOKE ALL ON FUNCTION app_private.personal_target_duplicate_contact_signal_v1(text)
  FROM PUBLIC, tongxingzhe_runtime;

DO $signals$
DECLARE
  original pg_proc%ROWTYPE;
  replacement record;
  definition text;
  changed_source text;
  expected_count integer;
  trusted_owner oid;
BEGIN
  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.personal_target_duplicate_contact_signal_v1(text) OWNER TO %I',
    pg_catalog.pg_get_userbyid(trusted_owner));

  FOR original IN
    SELECT * FROM pg_catalog.pg_proc WHERE oid IN (
      'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure,
      'app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamptz)'::regprocedure,
      'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure
    )
  LOOP
    IF original.proowner <> trusted_owner THEN
      RAISE EXCEPTION '0157 duplicate comparison owners differ: %', original.oid::regprocedure;
    END IF;
    changed_source := original.prosrc;
    IF original.oid = 'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure THEN
      FOR replacement IN
        SELECT * FROM (VALUES
          ($old$row_item.value->>'phone'$old$, 4),
          ($old$row_item.value->>'email'$old$, 4),
          ($old$other_item.value->>'phone'$old$, 1),
          ($old$other_item.value->>'email'$old$, 1),
          ($old$target_row.phone$old$, 1),
          ($old$target_row.email$old$, 1)
        ) AS signals(old_expression, occurrences)
      LOOP
        IF length(original.prosrc) - length(replace(original.prosrc, replacement.old_expression, ''))
            <> length(replacement.old_expression) * replacement.occurrences THEN
          RAISE EXCEPTION '0157 CSV duplicate signal anchor unavailable: %', replacement.old_expression;
        END IF;
        changed_source := replace(changed_source, replacement.old_expression,
          'app_private.personal_target_duplicate_contact_signal_v1(' || replacement.old_expression || ')');
      END LOOP;
    ELSE
      expected_count := CASE WHEN original.oid =
        'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure THEN 2 ELSE 1 END;
      FOR replacement IN
        SELECT * FROM (VALUES
          ('first_target.phone'), ('second_target.phone'),
          ('first_target.email'), ('second_target.email')
        ) AS signals(expression)
      LOOP
        definition := 'NULLIF(btrim(' || replacement.expression || '), '''')';
        IF length(original.prosrc) - length(replace(original.prosrc, definition, ''))
            <> length(definition) * expected_count THEN
          RAISE EXCEPTION '0157 pair duplicate signal anchor unavailable: %', replacement.expression;
        END IF;
        changed_source := replace(changed_source, definition,
          'app_private.personal_target_duplicate_contact_signal_v1(' || replacement.expression || ')');
      END LOOP;
    END IF;
    EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, changed_source);
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc changed
      WHERE changed.oid = original.oid
        AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
        AND changed.prosrc = changed_source
    ) THEN
      RAISE EXCEPTION '0157 changed metadata or unrelated duplicate comparison implementation: %',
        original.oid::regprocedure;
    END IF;
  END LOOP;
END
$signals$;
