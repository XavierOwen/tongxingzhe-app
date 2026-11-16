\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE fixture_0157_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0157.example.test', 'owner');

DO $current_project$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_data.list_personal_project_contexts('https://synthetic-0157.example.test', 'owner') context
    WHERE context.is_current AND context.project_id=(SELECT project_id FROM fixture_0157_context)) THEN
    RAISE EXCEPTION '0157 personal current project setup differs';
  END IF;
END
$current_project$;

CREATE TEMP TABLE fixture_0157_csv_cases (
  case_name text PRIMARY KEY,
  first_phone text,
  second_phone text,
  first_email text,
  second_email text,
  expected_hints integer[]
) ON COMMIT DROP;
INSERT INTO fixture_0157_csv_cases VALUES
  ('phone_tab', E'\t+1-555-0157\t', '+1-555-0157', NULL, NULL, ARRAY[1,2]),
  ('phone_newline', E'\r\n+1-555-0157\n', '+1-555-0157', NULL, NULL, ARRAY[1,2]),
  ('phone_nbsp', U&'\00A0+1-555-0157\00A0', '+1-555-0157', NULL, NULL, ARRAY[1,2]),
  ('email_tab', NULL, NULL, E'\tCase@Example.test\t', 'case@example.TEST', ARRAY[1,2]),
  ('email_newline', NULL, NULL, E'\nCase@Example.test\r\n', 'case@example.TEST', ARRAY[1,2]),
  ('email_nbsp', NULL, NULL, U&'\00A0Case@Example.test\00A0', 'case@example.TEST', ARRAY[1,2]),
  ('phone_internal_space', '+1 555-0157', '+1555-0157', NULL, NULL, ARRAY[]::integer[]),
  ('phone_internal_tab', E'+1\t555-0157', '+1555-0157', NULL, NULL, ARRAY[]::integer[]),
  ('phone_case', 'CALL-0157', 'call-0157', NULL, NULL, ARRAY[]::integer[]),
  ('phone_punctuation', '+1-555-0157', '+15550157', NULL, NULL, ARRAY[]::integer[]);

CREATE TEMP TABLE fixture_0157_whitespace ON COMMIT DROP AS
SELECT U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF' AS edge;
INSERT INTO fixture_0157_csv_cases
SELECT 'all_unicode_edges', edge || '+1-555-0157' || edge, '+1-555-0157',
  edge || 'Case@Example.test' || edge, 'case@example.TEST', ARRAY[1,2]
FROM fixture_0157_whitespace;
INSERT INTO fixture_0157_csv_cases
SELECT 'empty_signals', edge, edge, edge, edge, ARRAY[]::integer[]
FROM fixture_0157_whitespace;

DO $csv_same_file$
DECLARE
  item record;
  actual_hints integer[];
BEGIN
  FOR item IN SELECT * FROM fixture_0157_csv_cases ORDER BY case_name LOOP
    SELECT preview.hinted_rows INTO STRICT actual_hints
    FROM app_data.preview_personal_target_csv_import_v1(
      'https://synthetic-0157.example.test', 'owner', (SELECT project_id FROM fixture_0157_context),
      jsonb_build_array(
        jsonb_build_object('target_type','person','display_name','0157 first','phone',item.first_phone,'email',item.first_email),
        jsonb_build_object('target_type','person','display_name','0157 second','phone',item.second_phone,'email',item.second_email)
      )
    ) AS preview;
    IF actual_hints IS DISTINCT FROM item.expected_hints THEN
      RAISE EXCEPTION '0157 same-file %: expected hints %, got %', item.case_name, item.expected_hints, actual_hints;
    END IF;
  END LOOP;
END
$csv_same_file$;

CREATE TEMP TABLE fixture_0157_targets ON COMMIT DROP AS
SELECT 'padded'::text AS kind, created.target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0157_context), (SELECT workspace_id FROM fixture_0157_context),
  (SELECT project_id FROM fixture_0157_context), 'person', '0157 padded raw values',
  U&'\0009\00A0+1-555-0158\FEFF', U&'\000ACase0157@Example.test\00A0\FEFF', '0157-padded'
) AS created;
DO $csv_existing$
DECLARE actual_hints integer[];
BEGIN
  SELECT preview.hinted_rows INTO STRICT actual_hints
  FROM app_data.preview_personal_target_csv_import_v1(
    'https://synthetic-0157.example.test', 'owner', (SELECT project_id FROM fixture_0157_context),
    jsonb_build_array(
      jsonb_build_object('target_type','person','display_name','0157 existing phone','phone','+1-555-0158','email',NULL),
      jsonb_build_object('target_type','person','display_name','0157 existing email','phone',NULL,'email','case0157@example.test')
    )
  ) AS preview;
  IF actual_hints IS DISTINCT FROM ARRAY[1,2] THEN
    RAISE EXCEPTION '0157 existing padded target: expected hints {1,2}, got %', actual_hints;
  END IF;
END
$csv_existing$;

INSERT INTO fixture_0157_targets
SELECT 'plain', created.target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0157_context), (SELECT workspace_id FROM fixture_0157_context),
  (SELECT project_id FROM fixture_0157_context), 'person', '0157 plain values',
  '+1-555-0158', 'case0157@example.TEST', '0157-plain'
) AS created;
INSERT INTO fixture_0157_targets
SELECT 'blank-first', created.target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0157_context), (SELECT workspace_id FROM fixture_0157_context),
  (SELECT project_id FROM fixture_0157_context), 'person', '0157 blank first',
  (SELECT edge FROM fixture_0157_whitespace), (SELECT edge FROM fixture_0157_whitespace), '0157-blank-first'
) AS created;
INSERT INTO fixture_0157_targets
SELECT 'blank-second', created.target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0157_context), (SELECT workspace_id FROM fixture_0157_context),
  (SELECT project_id FROM fixture_0157_context), 'person', '0157 blank second',
  (SELECT edge FROM fixture_0157_whitespace), (SELECT edge FROM fixture_0157_whitespace), '0157-blank-second'
) AS created;

RESET ROLE;

CREATE TEMP TABLE fixture_0157_raw_targets ON COMMIT DROP AS
SELECT target.* FROM app_data.promotion_targets target
WHERE target.workspace_id = (SELECT workspace_id FROM fixture_0157_context);

CREATE TEMP TABLE fixture_0157_pair ON COMMIT DROP AS
SELECT * FROM app_data.preview_personal_target_pair_v1(
  'https://synthetic-0157.example.test', 'owner', (SELECT project_id FROM fixture_0157_context),
  (SELECT (target->>'target_id')::uuid FROM fixture_0157_targets WHERE kind='padded'),
  (SELECT (target->>'target_id')::uuid FROM fixture_0157_targets WHERE kind='plain')
);

DO $pair_and_raw_values$
DECLARE
  validated jsonb;
  blank_pair_rejected boolean := false;
BEGIN
  IF (SELECT count(*) FROM fixture_0157_pair WHERE phone_match AND email_match) <> 1 THEN
    RAISE EXCEPTION '0157 padded pair did not preserve both duplicate signals';
  END IF;
  SELECT to_jsonb(receipt) INTO STRICT validated
  FROM app_private.validate_personal_target_pair_preview_v1(
    (SELECT app_user_id FROM fixture_0157_context), (SELECT project_id FROM fixture_0157_context),
    (SELECT preview_id FROM fixture_0157_pair), clock_timestamp()
  ) receipt;
  IF validated IS DISTINCT FROM (SELECT to_jsonb(receipt)
    FROM app_private.personal_target_pair_preview_receipts receipt
    WHERE receipt.preview_id=(SELECT preview_id FROM fixture_0157_pair)) THEN
    RAISE EXCEPTION '0157 private pair receipt validator changed the exact receipt';
  END IF;
  BEGIN
    PERFORM 1 FROM app_data.preview_personal_target_pair_v1(
      'https://synthetic-0157.example.test', 'owner', (SELECT project_id FROM fixture_0157_context),
      (SELECT (target->>'target_id')::uuid FROM fixture_0157_targets WHERE kind='blank-first'),
      (SELECT (target->>'target_id')::uuid FROM fixture_0157_targets WHERE kind='blank-second')
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    blank_pair_rejected := true;
  END;
  IF NOT blank_pair_rejected THEN
    RAISE EXCEPTION '0157 whitespace-only pair produced a duplicate signal';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM fixture_0157_raw_targets
    WHERE phone=U&'\0009\00A0+1-555-0158\FEFF' AND email=U&'\000ACase0157@Example.test\00A0\FEFF')
    OR EXISTS (SELECT 1 FROM fixture_0157_raw_targets original
      FULL JOIN app_data.promotion_targets current USING (promotion_target_id)
      WHERE coalesce(original.workspace_id,current.workspace_id)=(SELECT workspace_id FROM fixture_0157_context)
        AND to_jsonb(original) IS DISTINCT FROM to_jsonb(current)) THEN
    RAISE EXCEPTION '0157 duplicate comparisons changed raw target values';
  END IF;
END
$pair_and_raw_values$;

ROLLBACK;
