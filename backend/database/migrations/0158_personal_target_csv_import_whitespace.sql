-- Version preview normalization so completed imports retain their original fingerprints.
ALTER TABLE app_private.personal_target_csv_import_previews
  ADD COLUMN normalization_version smallint NOT NULL DEFAULT 1
    CHECK (normalization_version IN (1, 2));

CREATE FUNCTION app_private.canonical_personal_target_csv_import_rows_v2(
  requested_rows jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  row_value jsonb;
  target_type_value text;
  display_name_value text;
  phone_value text;
  email_value text;
  normalized_rows jsonb := '[]'::jsonb;
  row_count_value integer;
BEGIN
  IF requested_rows IS NULL OR jsonb_typeof(requested_rows) <> 'array' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import rows';
  END IF;

  row_count_value := jsonb_array_length(requested_rows);
  IF row_count_value > 500 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import rows';
  END IF;

  FOR row_value IN SELECT value FROM jsonb_array_elements(requested_rows)
  LOOP
    IF jsonb_typeof(row_value) <> 'object'
      OR row_value - ARRAY[
        'target_type', 'display_name', 'phone', 'email'
      ] <> '{}'::jsonb
      OR NOT row_value ?& ARRAY[
        'target_type', 'display_name', 'phone', 'email'
      ]
      OR jsonb_typeof(row_value->'target_type') <> 'string'
      OR jsonb_typeof(row_value->'display_name') <> 'string'
      OR jsonb_typeof(row_value->'phone') NOT IN ('string', 'null')
      OR jsonb_typeof(row_value->'email') NOT IN ('string', 'null')
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid personal target CSV import rows';
    END IF;

    target_type_value := row_value->>'target_type';
    display_name_value := coalesce(app_private.personal_target_duplicate_contact_signal_v1(row_value->>'display_name'), '');
    phone_value := app_private.personal_target_duplicate_contact_signal_v1(row_value->>'phone');
    email_value := app_private.personal_target_duplicate_contact_signal_v1(row_value->>'email');
    IF target_type_value NOT IN ('person', 'institution')
      OR length(display_name_value) NOT BETWEEN 1 AND 200
      OR (phone_value IS NOT NULL AND length(phone_value) NOT BETWEEN 1 AND 80)
      OR (email_value IS NOT NULL AND length(email_value) NOT BETWEEN 1 AND 320)
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid personal target CSV import rows';
    END IF;

    normalized_rows := normalized_rows || jsonb_build_array(
      jsonb_build_object(
        'target_type', target_type_value,
        'display_name', display_name_value,
        'phone', phone_value,
        'email', email_value
      )
    );
  END LOOP;

  RETURN normalized_rows;
END
$function$;

REVOKE ALL ON FUNCTION app_private.canonical_personal_target_csv_import_rows_v2(jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $normalization$
DECLARE
  original pg_proc%ROWTYPE;
  replacement record;
  changed_source text;
  trusted_owner oid;
BEGIN
  SELECT * INTO STRICT original FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.canonical_personal_target_csv_import_rows_v1(jsonb)'::regprocedure;
  trusted_owner := original.proowner;
  EXECUTE format('ALTER FUNCTION app_private.canonical_personal_target_csv_import_rows_v2(jsonb) OWNER TO %I',
    pg_catalog.pg_get_userbyid(trusted_owner));
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc created
    WHERE created.oid = 'app_private.canonical_personal_target_csv_import_rows_v2(jsonb)'::regprocedure
      AND to_jsonb(created) - ARRAY['oid', 'proname', 'prosrc']
        = to_jsonb(original) - ARRAY['oid', 'proname', 'prosrc']
  ) THEN
    RAISE EXCEPTION '0158 CSV normalization v2 metadata differs from v1';
  END IF;

  FOR original IN
    SELECT * FROM pg_catalog.pg_proc WHERE oid IN (
      'app_data.preview_personal_target_csv_import_v1(text,text,uuid,jsonb)'::regprocedure,
      'app_data.confirm_personal_target_csv_import_v1(text,text,uuid,uuid,uuid,jsonb,jsonb)'::regprocedure
    )
  LOOP
    IF original.proowner <> trusted_owner THEN
      RAISE EXCEPTION '0158 CSV normalization owners differ: %', original.oid::regprocedure;
    END IF;
    changed_source := original.prosrc;
    FOR replacement IN
      SELECT signals.old_expression, signals.new_expression FROM (VALUES
      ('preview', $old$app_private.canonical_personal_target_csv_import_rows_v1($old$, $new$app_private.canonical_personal_target_csv_import_rows_v2($new$),
      ('preview', $old$rows_fingerprint, row_count, hinted_rows, previewed_at_utc, expires_at_utc
  ) VALUES ($old$, $new$rows_fingerprint, row_count, hinted_rows, previewed_at_utc, expires_at_utc,
    normalization_version
  ) VALUES ($new$),
      ('preview', $old$    resolved_expires_at
  );$old$, $new$    resolved_expires_at,
    2
  );$new$),
      ('confirm', $old$  replay_hinted_rows integer[];$old$, $new$  replay_hinted_rows integer[];
  replay_normalization_version smallint;$new$),
      ('confirm', $old$    SELECT preview.hinted_rows
    INTO STRICT replay_hinted_rows$old$, $new$    SELECT preview.hinted_rows, preview.normalization_version
    INTO STRICT replay_hinted_rows, replay_normalization_version$new$),
      ('confirm', $old$      normalized_rows := app_private.canonical_personal_target_csv_import_rows_v1(
        requested_rows
      );$old$, $new$      normalized_rows := CASE replay_normalization_version
        WHEN 1 THEN app_private.canonical_personal_target_csv_import_rows_v1(requested_rows)
        WHEN 2 THEN app_private.canonical_personal_target_csv_import_rows_v2(requested_rows)
      END;$new$),
      ('confirm', $old$    normalized_rows := app_private.canonical_personal_target_csv_import_rows_v1(
      requested_rows
    );$old$, $new$    normalized_rows := CASE preview_row.normalization_version
      WHEN 1 THEN app_private.canonical_personal_target_csv_import_rows_v1(requested_rows)
      WHEN 2 THEN app_private.canonical_personal_target_csv_import_rows_v2(requested_rows)
    END;$new$),
      ('confirm', $old$    OR current_hinted_rows <> preview_row.hinted_rows
  THEN$old$, $new$    OR current_hinted_rows <> preview_row.hinted_rows
    OR (preview_row.normalization_version = 1 AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(normalized_rows) AS row_item(value)
      WHERE row_item.value->>'display_name' IS DISTINCT FROM coalesce(
          app_private.personal_target_duplicate_contact_signal_v1(row_item.value->>'display_name'), '')
        OR row_item.value->>'phone' IS DISTINCT FROM
          app_private.personal_target_duplicate_contact_signal_v1(row_item.value->>'phone')
        OR row_item.value->>'email' IS DISTINCT FROM
          app_private.personal_target_duplicate_contact_signal_v1(row_item.value->>'email')
    ))
  THEN$new$)
      ) AS signals(function_kind, old_expression, new_expression)
      WHERE signals.function_kind = CASE WHEN original.oid =
        'app_data.preview_personal_target_csv_import_v1(text,text,uuid,jsonb)'::regprocedure
        THEN 'preview' ELSE 'confirm' END
    LOOP
      IF length(original.prosrc) - length(replace(original.prosrc, replacement.old_expression, ''))
          <> length(replacement.old_expression) THEN
        RAISE EXCEPTION '0158 CSV normalization anchor unavailable: %', original.oid::regprocedure;
      END IF;
      changed_source := replace(changed_source, replacement.old_expression, replacement.new_expression);
    END LOOP;
    EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, changed_source);
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc changed
      WHERE changed.oid = original.oid
        AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
        AND changed.prosrc = changed_source
    ) THEN
      RAISE EXCEPTION '0158 changed metadata or unrelated CSV implementation: %', original.oid::regprocedure;
    END IF;
  END LOOP;
END
$normalization$;
