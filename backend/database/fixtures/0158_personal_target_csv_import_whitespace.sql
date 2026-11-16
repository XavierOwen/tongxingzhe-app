\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE fixture_0158_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0158.example.test', 'owner');
CREATE TEMP TABLE fixture_0158_first_rows ON COMMIT DROP AS
SELECT jsonb_build_array(jsonb_build_object('target_type','person','display_name','0158 valid name',
  'phone',E'\t','email',U&'\00A0')) AS rows;
CREATE TEMP TABLE fixture_0158_first_preview ON COMMIT DROP AS
SELECT * FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
  (SELECT rows FROM fixture_0158_first_rows));
CREATE TEMP TABLE fixture_0158_first_confirmation ON COMMIT DROP AS
SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
  (SELECT preview_id FROM fixture_0158_first_preview), '00000000-0158-6000-8000-000000000001',
  (SELECT rows FROM fixture_0158_first_rows), '["create"]'::jsonb);

RESET ROLE;

DO $empty_optional_fields$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0158_first_confirmation result
    JOIN app_data.promotion_targets target ON target.promotion_target_id=(result.created_targets->0->>'target_id')::uuid
    WHERE result.outcome='confirmed' AND result.created_count=1
      AND target.display_name='0158 valid name' AND target.phone IS NULL AND target.email IS NULL) THEN
    RAISE EXCEPTION '0158 normal CSV confirmation did not store whitespace-only phone and email as NULL';
  END IF;
END
$empty_optional_fields$;

DO $version_and_fingerprint$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_private.personal_target_csv_import_previews preview
    JOIN fixture_0158_first_preview original USING (preview_id)
    JOIN app_private.personal_target_csv_import_request_claims claim USING (preview_id)
    WHERE preview.normalization_version=2 AND claim.rows_fingerprint=preview.rows_fingerprint
      AND preview.rows_fingerprint=app_private.personal_target_csv_import_fingerprint_v1(preview.preview_id,
        '[{"target_type":"person","display_name":"0158 valid name","phone":null,"email":null}]'::jsonb)) THEN
    RAISE EXCEPTION '0158 new preview did not bind version 2 canonical rows to its completed claim';
  END IF;
END
$version_and_fingerprint$;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE fixture_0158_whitespace ON COMMIT DROP AS
SELECT U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF' AS edge;
CREATE TEMP TABLE fixture_0158_invalid_rows ON COMMIT DROP AS
SELECT 'blank_name'::text AS case_name, edge AS display_name, NULL::text AS phone, NULL::text AS email
FROM fixture_0158_whitespace;
INSERT INTO fixture_0158_invalid_rows VALUES
  ('long_name', repeat('N',201), NULL, NULL),
  ('long_phone', '0158 long phone', repeat('P',81), NULL),
  ('long_email', '0158 long email', NULL, repeat('E',321));

DO $invalid_normalized_values$
DECLARE
  item record;
  rejected boolean;
BEGIN
  FOR item IN SELECT * FROM fixture_0158_invalid_rows LOOP
    rejected := false;
    BEGIN
      PERFORM 1 FROM app_data.preview_personal_target_csv_import_v1(
        'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
        jsonb_build_array(jsonb_build_object('target_type','person','display_name',item.display_name,'phone',item.phone,'email',item.email)));
    EXCEPTION WHEN SQLSTATE '22023' THEN
      rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION '0158 preview accepted invalid normalized %', item.case_name; END IF;
  END LOOP;
END
$invalid_normalized_values$;

CREATE TEMP TABLE fixture_0158_preserved_rows ON COMMIT DROP AS
SELECT jsonb_build_array(
  jsonb_build_object('target_type','person','display_name',repeat(edge,10) || repeat('N',200) || repeat(edge,10),
    'phone',repeat(edge,10) || repeat('P',80) || repeat(edge,10),'email',repeat(edge,10) || repeat('E',320) || repeat(edge,10)),
  jsonb_build_object('target_type','person','display_name',edge || E'First\tMiddle  Last' || edge,
    'phone',edge || E'+1\tAb-15 58' || edge,'email',edge || E'MiX\tIn Side@EXAMPLE.test' || edge)
) AS rows FROM fixture_0158_whitespace;
CREATE TEMP TABLE fixture_0158_preserved_preview ON COMMIT DROP AS
SELECT * FROM app_data.preview_personal_target_csv_import_v1(
  'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
  (SELECT rows FROM fixture_0158_preserved_rows));
CREATE TEMP TABLE fixture_0158_preserved_confirmation ON COMMIT DROP AS
SELECT * FROM app_data.confirm_personal_target_csv_import_v1(
  'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
  (SELECT preview_id FROM fixture_0158_preserved_preview), '00000000-0158-6000-8000-000000000002',
  (SELECT rows FROM fixture_0158_preserved_rows), '["create","create"]'::jsonb);

RESET ROLE;

CREATE TEMP TABLE fixture_0158_replay_baseline ON COMMIT DROP AS
SELECT (SELECT count(*) FROM app_data.promotion_targets) AS targets,
  (SELECT count(*) FROM app_private.personal_target_csv_import_previews) AS previews,
  (SELECT count(*) FROM app_private.personal_target_csv_import_request_claims) AS claims,
  (SELECT count(*) FROM app_private.personal_target_csv_import_audit_events) AS audits,
  (SELECT rows_fingerprint FROM app_private.personal_target_csv_import_previews
    WHERE preview_id=(SELECT preview_id FROM fixture_0158_first_preview)) AS fingerprint;

DO $stored_values$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0158_preserved_confirmation result
    JOIN app_data.promotion_targets first_target ON first_target.promotion_target_id=(result.created_targets->0->>'target_id')::uuid
    JOIN app_data.promotion_targets second_target ON second_target.promotion_target_id=(result.created_targets->1->>'target_id')::uuid
    WHERE result.outcome='confirmed' AND result.created_count=2
      AND first_target.display_name=repeat('N',200) AND first_target.phone=repeat('P',80) AND first_target.email=repeat('E',320)
      AND second_target.display_name=E'First\tMiddle  Last' AND second_target.phone=E'+1\tAb-15 58'
      AND second_target.email=E'MiX\tIn Side@EXAMPLE.test') THEN
    RAISE EXCEPTION '0158 trim-before-length-check or interior character preservation differs';
  END IF;
END
$stored_values$;

SET LOCAL ROLE tongxingzhe_runtime;

DO $canonical_replay$
DECLARE
  replayed jsonb;
  rejected boolean := false;
BEGIN
  SELECT to_jsonb(result) INTO STRICT replayed FROM app_data.confirm_personal_target_csv_import_v1(
    'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
    (SELECT preview_id FROM fixture_0158_first_preview), '00000000-0158-6000-8000-000000000001',
    (SELECT jsonb_build_array(jsonb_build_object('target_type','person','display_name',edge || '0158 valid name' || edge,
      'phone',edge,'email',edge)) FROM fixture_0158_whitespace), '["create"]'::jsonb) result;
  IF replayed IS DISTINCT FROM (SELECT to_jsonb(result) FROM fixture_0158_first_confirmation result) THEN
    RAISE EXCEPTION '0158 canonical-equivalent replay changed its original result';
  END IF;
  BEGIN
    PERFORM 1 FROM app_data.confirm_personal_target_csv_import_v1(
      'https://synthetic-0158.example.test', 'owner', (SELECT project_id FROM fixture_0158_context),
      (SELECT preview_id FROM fixture_0158_first_preview), '00000000-0158-6000-8000-000000000001',
      '[{"target_type":"person","display_name":"0158 actual drift","phone":null,"email":null}]'::jsonb, '["create"]'::jsonb);
  EXCEPTION WHEN SQLSTATE '23505' THEN
    rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION '0158 completed request accepted actual payload drift'; END IF;
END
$canonical_replay$;

RESET ROLE;

DO $replay_unchanged$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0158_replay_baseline baseline
    WHERE baseline.targets=(SELECT count(*) FROM app_data.promotion_targets)
      AND baseline.previews=(SELECT count(*) FROM app_private.personal_target_csv_import_previews)
      AND baseline.claims=(SELECT count(*) FROM app_private.personal_target_csv_import_request_claims)
      AND baseline.audits=(SELECT count(*) FROM app_private.personal_target_csv_import_audit_events)
      AND baseline.fingerprint=(SELECT rows_fingerprint FROM app_private.personal_target_csv_import_previews
        WHERE preview_id=(SELECT preview_id FROM fixture_0158_first_preview))) THEN
    RAISE EXCEPTION '0158 completed replay changed rows, receipts, fingerprint, or audit count';
  END IF;
END
$replay_unchanged$;

ROLLBACK;
