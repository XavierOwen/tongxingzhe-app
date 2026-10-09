\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0113_owner_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0113.example.test', 'owner'
);
CREATE TEMP TABLE fixture_0113_other_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0113.example.test', 'other-owner'
);

CREATE TEMP TABLE fixture_0113_previews (
  case_name text PRIMARY KEY,
  preview_id uuid,
  first_target_id uuid,
  first_target_type text,
  first_display_name text,
  first_phone text,
  first_email text,
  second_target_id uuid,
  second_target_type text,
  second_display_name text,
  second_phone text,
  second_email text,
  phone_match boolean,
  email_match boolean,
  first_retention_due_at_utc timestamptz,
  second_retention_due_at_utc timestamptz,
  merge_deadline_at_utc timestamptz,
  expiry_consequence text,
  previewed_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.expect_failure(
  expected_state text,
  statement_text text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  actual_state text;
BEGIN
  BEGIN
    EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION 'expected SQLSTATE %, got %', expected_state, actual_state;
  END IF;
END
$function$;

CREATE FUNCTION pg_temp.assert_no_preview(
  case_name text,
  issuer text,
  subject text,
  project_id uuid,
  first_target_id uuid,
  second_target_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp, app_data, app_private
AS $function$
DECLARE
  preview_count bigint;
  receipt_count bigint;
  audit_count bigint;
  access_count bigint;
  receipt_count_after bigint;
  audit_count_after bigint;
  access_count_after bigint;
BEGIN
  SELECT count(*) INTO receipt_count
  FROM app_private.personal_target_pair_preview_receipts;
  SELECT count(*) INTO audit_count
  FROM app_private.personal_target_pair_preview_audit_events;
  SELECT count(*) INTO access_count
  FROM app_data.promotion_target_access_events;

  BEGIN
    SELECT count(*) INTO preview_count
    FROM app_data.preview_personal_target_pair_v1(
      issuer, subject, project_id, first_target_id, second_target_id
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    preview_count := 0;
  END;
  SELECT count(*) INTO receipt_count_after
  FROM app_private.personal_target_pair_preview_receipts;
  SELECT count(*) INTO audit_count_after
  FROM app_private.personal_target_pair_preview_audit_events;
  SELECT count(*) INTO access_count_after
  FROM app_data.promotion_target_access_events;

  IF preview_count <> 0
    OR receipt_count <> receipt_count_after
    OR audit_count <> audit_count_after
    OR access_count <> access_count_after
  THEN
    RAISE EXCEPTION 'negative case % changed preview side effects', case_name;
  END IF;
END
$function$;

GRANT ALL ON fixture_0113_owner_context,
  fixture_0113_other_context, fixture_0113_previews TO tongxingzhe_runtime;

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '00000000-0113-4000-8000-000000000090'::uuid,
  (SELECT workspace_id FROM fixture_0113_owner_context),
  'Pair preview alternate project', 'active', false
);

INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name,
  phone, email, status, created_by_app_user_id, created_at,
  anonymized_at, anonymization_reason
) VALUES
  ('00000000-0113-4000-8000-000000000001',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PAIR_PHONE_A', '+1 312 555 0113', NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000002',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PAIR_PHONE_B', ' +1 312 555 0113 ', NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp() + interval '1 day', NULL, NULL),
  ('00000000-0113-4000-8000-000000000003',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PAIR_EMAIL_A', NULL, 'Case@Example.test', 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000004',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PAIR_EMAIL_B', NULL, ' case@example.TEST ', 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp() + interval '2 days', NULL, NULL),
  ('00000000-0113-4000-8000-000000000005',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PAIR_BOTH_A', '+1 312 555 0115', 'both@example.test', 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000006',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PAIR_BOTH_B', ' +1 312 555 0115 ', 'BOTH@example.TEST ', 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp() + interval '3 days', NULL, NULL),
  ('00000000-0113-4000-8000-000000000007',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'ANONYMIZED_PAIR_SENTINEL', NULL, NULL, 'anonymized',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp() - interval '1 day',
   transaction_timestamp(), 'withdrawal'),
  ('00000000-0113-4000-8000-000000000008',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'institution',
   'CROSS_TYPE_SENTINEL', '+1 312 555 0113', NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000009',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'UNASSIGNED_SENTINEL', '+1 312 555 0113', NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000010',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'NO_SIGNAL_SENTINEL', NULL, NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000011',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'EXPIRED_SENTINEL', '+1 312 555 0113', NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp() - interval '2 years', NULL, NULL),
  ('00000000-0113-4000-8000-000000000012',
   (SELECT workspace_id FROM fixture_0113_owner_context), 'person',
   'PROFILE_REVISION_SENTINEL', '+1 312 555 0112', 'revision@example.test', 'active',
   (SELECT app_user_id FROM fixture_0113_owner_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000013',
   (SELECT workspace_id FROM fixture_0113_other_context), 'person',
   'CROSS_WORKSPACE_SENTINEL', '+1 312 555 0113', NULL, 'active',
   (SELECT app_user_id FROM fixture_0113_other_context),
   transaction_timestamp(), NULL, NULL);

INSERT INTO app_data.promotion_target_assignments (
  assignment_id, promotion_target_id, app_user_id,
  assigned_by_app_user_id, assigned_at, ended_at, end_reason
) VALUES
  ('00000000-0113-4000-8000-000000000101', '00000000-0113-4000-8000-000000000001',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000102', '00000000-0113-4000-8000-000000000002',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000103', '00000000-0113-4000-8000-000000000003',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000104', '00000000-0113-4000-8000-000000000004',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000105', '00000000-0113-4000-8000-000000000005',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000106', '00000000-0113-4000-8000-000000000006',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000107', '00000000-0113-4000-8000-000000000007',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), transaction_timestamp(), 'target_anonymized'),
  ('00000000-0113-4000-8000-000000000108', '00000000-0113-4000-8000-000000000008',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000109', '00000000-0113-4000-8000-000000000010',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000110', '00000000-0113-4000-8000-000000000011',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000111', '00000000-0113-4000-8000-000000000012',
   (SELECT app_user_id FROM fixture_0113_owner_context), (SELECT app_user_id FROM fixture_0113_owner_context), transaction_timestamp(), NULL, NULL),
  ('00000000-0113-4000-8000-000000000113', '00000000-0113-4000-8000-000000000013',
   (SELECT app_user_id FROM fixture_0113_other_context), (SELECT app_user_id FROM fixture_0113_other_context), transaction_timestamp(), NULL, NULL);

DO $capability$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.list_personal_project_contexts(
      'https://synthetic-0113.example.test', 'owner'
    ) AS context_row
    WHERE context_row.is_current
      AND 'manage_assigned_target_merges' = ANY(context_row.capabilities)
  ) THEN
    RAISE EXCEPTION 'personal context omitted merge capability';
  END IF;
END
$capability$;

INSERT INTO fixture_0113_previews
SELECT 'phone', preview.*
FROM app_data.preview_personal_target_pair_v1(
  'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000002',
  '00000000-0113-4000-8000-000000000001'
) AS preview;
INSERT INTO fixture_0113_previews
SELECT 'email', preview.*
FROM app_data.preview_personal_target_pair_v1(
  'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000003',
  '00000000-0113-4000-8000-000000000004'
) AS preview;
INSERT INTO fixture_0113_previews
SELECT 'both', preview.*
FROM app_data.preview_personal_target_pair_v1(
  'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000006',
  '00000000-0113-4000-8000-000000000005'
) AS preview;

DO $positive$
DECLARE
  preview_row fixture_0113_previews%ROWTYPE;
  receipt_count bigint;
  audit_count bigint;
  access_count bigint;
BEGIN
  IF (SELECT count(*) FROM fixture_0113_previews) <> 3 THEN
    RAISE EXCEPTION 'expected phone, email, and both positive previews';
  END IF;
  IF EXISTS (
    SELECT 1 FROM fixture_0113_previews
    WHERE first_target_id >= second_target_id
       OR expiry_consequence <> 'anonymize_both'
       OR merge_deadline_at_utc <> LEAST(
         first_retention_due_at_utc, second_retention_due_at_utc
       )
       OR expires_at_utc <> previewed_at_utc + interval '15 minutes'
       OR first_retention_due_at_utc <= previewed_at_utc
       OR second_retention_due_at_utc <= previewed_at_utc
  ) THEN
    RAISE EXCEPTION 'preview order, deadline, or expiry contract failed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM fixture_0113_previews
    WHERE case_name = 'phone' AND phone_match AND NOT email_match
      AND first_display_name = 'PAIR_PHONE_A'
      AND first_phone = '+1 312 555 0113'
      AND first_email IS NULL
      AND second_display_name = 'PAIR_PHONE_B'
      AND second_phone = ' +1 312 555 0113 '
  ) OR NOT EXISTS (
    SELECT 1 FROM fixture_0113_previews
    WHERE case_name = 'email' AND NOT phone_match AND email_match
      AND first_email = 'Case@Example.test'
      AND second_email = ' case@example.TEST '
  ) OR NOT EXISTS (
    SELECT 1 FROM fixture_0113_previews
    WHERE case_name = 'both' AND phone_match AND email_match
  ) THEN
    RAISE EXCEPTION 'typed PII or normalized match signal was not preserved';
  END IF;
  SELECT count(*) INTO receipt_count
  FROM app_private.personal_target_pair_preview_receipts
  WHERE actor_app_user_id = (
    SELECT app_user_id FROM fixture_0113_owner_context
  );
  SELECT count(*) INTO audit_count
  FROM app_private.personal_target_pair_preview_audit_events
  WHERE actor_app_user_id = (
    SELECT app_user_id FROM fixture_0113_owner_context
  );
  SELECT count(*) INTO access_count
  FROM app_data.promotion_target_access_events
  WHERE actor_app_user_id = (
    SELECT app_user_id FROM fixture_0113_owner_context
  );
  IF receipt_count <> 3 OR audit_count <> 3 OR access_count <> 6 THEN
    RAISE EXCEPTION 'positive previews did not create 3 receipts, 3 audits, 6 access events';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM fixture_0113_previews AS preview
    LEFT JOIN app_private.personal_target_pair_preview_receipts AS receipt
      USING (preview_id)
    WHERE receipt.preview_id IS NULL
      OR receipt.actor_app_user_id <>
        (SELECT app_user_id FROM fixture_0113_owner_context)
      OR receipt.workspace_id <>
        (SELECT workspace_id FROM fixture_0113_owner_context)
      OR receipt.first_profile_revision <= 0
      OR receipt.second_profile_revision <= 0
      OR receipt.first_assignment_id IS NULL
      OR receipt.second_assignment_id IS NULL
      OR receipt.merge_deadline_at_utc <> preview.merge_deadline_at_utc
      OR receipt.phone_match <> preview.phone_match
      OR receipt.email_match <> preview.email_match
  ) THEN
    RAISE EXCEPTION 'preview receipt did not bind current facts';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.personal_target_pair_preview_audit_events AS event
    WHERE event.operation <> 'personal_target_pair_preview'
       OR event.outcome <> 'previewed'
       OR event.target_count <> 2
       OR event.match_signal_count NOT BETWEEN 1 AND 2
  ) THEN
    RAISE EXCEPTION 'preview audit event fields are invalid';
  END IF;
  IF EXISTS (
    SELECT 1 FROM fixture_0113_previews AS preview
    WHERE (SELECT count(*) FROM app_data.promotion_target_access_events AS event
      WHERE event.actor_app_user_id =
        (SELECT app_user_id FROM fixture_0113_owner_context)
        AND event.workspace_id = (SELECT workspace_id FROM fixture_0113_owner_context)
        AND event.promotion_target_id IN (preview.first_target_id, preview.second_target_id)
        AND event.action = 'viewed'
        AND event.occurred_at = preview.previewed_at_utc) < 2
  ) THEN
    RAISE EXCEPTION 'preview did not record both target accesses';
  END IF;
END
$positive$;

SELECT pg_temp.assert_no_preview('same_id', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000001');
SELECT pg_temp.assert_no_preview('cross_workspace', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000013');
SELECT pg_temp.assert_no_preview('cross_type', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000008');
SELECT pg_temp.assert_no_preview('other_actor', 'https://synthetic-0113.example.test', 'other-owner',
  (SELECT project_id FROM fixture_0113_other_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000002');
SELECT pg_temp.assert_no_preview('unassigned', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000009');
SELECT pg_temp.assert_no_preview('anonymized', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000007');
SELECT pg_temp.assert_no_preview('expired', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000011');
SELECT pg_temp.assert_no_preview('no_signal', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000010');

UPDATE app_data.user_current_projects
SET project_id = '00000000-0113-4000-8000-000000000090'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0113_owner_context);
SELECT pg_temp.assert_no_preview('current_project_drift', 'https://synthetic-0113.example.test', 'owner',
  (SELECT project_id FROM fixture_0113_owner_context),
  '00000000-0113-4000-8000-000000000001', '00000000-0113-4000-8000-000000000002');
UPDATE app_data.user_current_projects
SET project_id = (SELECT project_id FROM fixture_0113_owner_context)
WHERE app_user_id = (SELECT app_user_id FROM fixture_0113_owner_context);

DO $profile_revision$
DECLARE
  target_id uuid := '00000000-0113-4000-8000-000000000012';
  before_revision bigint;
BEGIN
  SELECT profile_revision INTO STRICT before_revision
  FROM app_data.promotion_targets WHERE promotion_target_id = target_id;
  UPDATE app_data.promotion_targets SET target_type = 'institution'
  WHERE promotion_target_id = target_id;
  IF (SELECT profile_revision FROM app_data.promotion_targets WHERE promotion_target_id = target_id) <> before_revision + 1 THEN
    RAISE EXCEPTION 'target_type update did not bump profile revision';
  END IF;
  before_revision := before_revision + 1;
  UPDATE app_data.promotion_targets SET target_type = 'person', display_name = 'PROFILE_REVISION_CHANGED'
  WHERE promotion_target_id = target_id;
  IF (SELECT profile_revision FROM app_data.promotion_targets WHERE promotion_target_id = target_id) <> before_revision + 1 THEN
    RAISE EXCEPTION 'display_name update did not bump profile revision';
  END IF;
  before_revision := before_revision + 1;
  UPDATE app_data.promotion_targets SET phone = '+1 312 555 0199'
  WHERE promotion_target_id = target_id;
  IF (SELECT profile_revision FROM app_data.promotion_targets WHERE promotion_target_id = target_id) <> before_revision + 1 THEN
    RAISE EXCEPTION 'phone update did not bump profile revision';
  END IF;
  before_revision := before_revision + 1;
  UPDATE app_data.promotion_targets SET email = 'revision.changed@example.test'
  WHERE promotion_target_id = target_id;
  IF (SELECT profile_revision FROM app_data.promotion_targets WHERE promotion_target_id = target_id) <> before_revision + 1 THEN
    RAISE EXCEPTION 'email update did not bump profile revision';
  END IF;
  before_revision := before_revision + 1;
  UPDATE app_data.promotion_targets SET created_at = created_at - interval '1 second'
  WHERE promotion_target_id = target_id;
  UPDATE app_data.promotion_targets SET profile_revision = 9000
  WHERE promotion_target_id = target_id;
  IF (SELECT profile_revision FROM app_data.promotion_targets WHERE promotion_target_id = target_id) <> before_revision THEN
    RAISE EXCEPTION 'unrelated update or direct revision tamper changed profile revision';
  END IF;
  UPDATE app_data.promotion_targets
  SET status = 'anonymized', phone = NULL, email = NULL,
      anonymized_at = transaction_timestamp(), anonymization_reason = 'withdrawal'
  WHERE promotion_target_id = target_id;
  IF (SELECT profile_revision FROM app_data.promotion_targets WHERE promotion_target_id = target_id) <> before_revision + 1 THEN
    RAISE EXCEPTION 'status update did not bump profile revision';
  END IF;
END
$profile_revision$;

DO $validator$
DECLARE
  receipt_id uuid := '00000000-0113-4000-8000-000000000301';
  actor_id uuid := (SELECT app_user_id FROM fixture_0113_owner_context);
  actor_workspace_id uuid := (SELECT workspace_id FROM fixture_0113_owner_context);
  project_id uuid := (SELECT project_id FROM fixture_0113_owner_context);
  validate_count bigint;
BEGIN
  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id,
    first_target_id, second_target_id,
    first_profile_revision, second_profile_revision,
    first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc,
    merge_deadline_at_utc, phone_match, email_match,
    previewed_at_utc, expires_at_utc
  )
  SELECT receipt_id, actor_id, actor_workspace_id,
    first_target.promotion_target_id, second_target.promotion_target_id,
    first_target.profile_revision, second_target.profile_revision,
    '00000000-0113-4000-8000-000000000101',
    '00000000-0113-4000-8000-000000000102',
    app_data.promotion_target_review_due_at(first_target.promotion_target_id),
    app_data.promotion_target_review_due_at(second_target.promotion_target_id),
    LEAST(
      app_data.promotion_target_review_due_at(first_target.promotion_target_id),
      app_data.promotion_target_review_due_at(second_target.promotion_target_id)
    ), true, false, transaction_timestamp() - interval '1 minute',
    transaction_timestamp() + interval '14 minutes'
  FROM app_data.promotion_targets AS first_target
  CROSS JOIN app_data.promotion_targets AS second_target
  WHERE first_target.promotion_target_id = '00000000-0113-4000-8000-000000000001'
    AND second_target.promotion_target_id = '00000000-0113-4000-8000-000000000002';

  SELECT count(*) INTO validate_count
  FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, receipt_id, transaction_timestamp() - interval '1 minute'
  );
  IF validate_count <> 1 THEN
    RAISE EXCEPTION 'private validator rejected a current receipt';
  END IF;
  SELECT count(*) INTO validate_count
  FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, receipt_id, transaction_timestamp() + interval '14 minutes'
  );
  IF validate_count <> 0 THEN
    RAISE EXCEPTION 'private validator accepted the half-open expiry boundary';
  END IF;
  SELECT count(*) INTO validate_count
  FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, receipt_id, transaction_timestamp() - interval '2 minutes'
  );
  IF validate_count <> 0 THEN
    RAISE EXCEPTION 'private validator accepted time before preview';
  END IF;

  UPDATE app_data.promotion_targets SET display_name = 'PROFILE_DRIFT'
  WHERE promotion_target_id = '00000000-0113-4000-8000-000000000001';
  SELECT count(*) INTO validate_count
  FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, receipt_id, transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted profile drift'; END IF;
  UPDATE app_data.promotion_targets SET display_name = 'PAIR_PHONE_A'
  WHERE promotion_target_id = '00000000-0113-4000-8000-000000000001';

  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id, first_target_id, second_target_id,
    first_profile_revision, second_profile_revision, first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc, merge_deadline_at_utc,
    phone_match, email_match, previewed_at_utc, expires_at_utc
  )
  SELECT '00000000-0113-4000-8000-000000000302', actor_id, actor_workspace_id,
    first_target.promotion_target_id, second_target.promotion_target_id,
    first_target.profile_revision, second_target.profile_revision,
    '00000000-0113-4000-8000-000000000101', '00000000-0113-4000-8000-000000000102',
    app_data.promotion_target_review_due_at(first_target.promotion_target_id),
    app_data.promotion_target_review_due_at(second_target.promotion_target_id),
    LEAST(app_data.promotion_target_review_due_at(first_target.promotion_target_id), app_data.promotion_target_review_due_at(second_target.promotion_target_id)),
    true, false, transaction_timestamp() - interval '1 minute', transaction_timestamp() + interval '14 minutes'
  FROM app_data.promotion_targets AS first_target CROSS JOIN app_data.promotion_targets AS second_target
  WHERE first_target.promotion_target_id = '00000000-0113-4000-8000-000000000001'
    AND second_target.promotion_target_id = '00000000-0113-4000-8000-000000000002';
  UPDATE app_data.promotion_target_assignments SET ended_at = transaction_timestamp(), end_reason = 'unassigned'
  WHERE assignment_id = '00000000-0113-4000-8000-000000000101';
  SELECT count(*) INTO validate_count FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, '00000000-0113-4000-8000-000000000302', transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted assignment drift'; END IF;
  UPDATE app_data.promotion_target_assignments SET ended_at = NULL, end_reason = NULL
  WHERE assignment_id = '00000000-0113-4000-8000-000000000101';

  INSERT INTO app_data.promotion_target_retention_policies (
    workspace_id, retention_months, updated_by_app_user_id
  ) VALUES (actor_workspace_id, 11, actor_id);
  SELECT count(*) INTO validate_count FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, '00000000-0113-4000-8000-000000000302', transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted retention drift'; END IF;

  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id, first_target_id, second_target_id,
    first_profile_revision, second_profile_revision, first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc, merge_deadline_at_utc,
    phone_match, email_match, previewed_at_utc, expires_at_utc
  )
  SELECT '00000000-0113-4000-8000-000000000305', actor_id, actor_workspace_id,
    first_target.promotion_target_id, second_target.promotion_target_id,
    first_target.profile_revision, second_target.profile_revision,
    '00000000-0113-4000-8000-000000000101', '00000000-0113-4000-8000-000000000102',
    app_data.promotion_target_review_due_at(first_target.promotion_target_id),
    app_data.promotion_target_review_due_at(second_target.promotion_target_id),
    LEAST(app_data.promotion_target_review_due_at(first_target.promotion_target_id), app_data.promotion_target_review_due_at(second_target.promotion_target_id)),
    true, false, transaction_timestamp() - interval '1 minute', transaction_timestamp() + interval '14 minutes'
  FROM app_data.promotion_targets AS first_target CROSS JOIN app_data.promotion_targets AS second_target
  WHERE first_target.promotion_target_id = '00000000-0113-4000-8000-000000000001'
    AND second_target.promotion_target_id = '00000000-0113-4000-8000-000000000002';

  UPDATE app_data.promotion_targets
  SET status = 'anonymized', phone = NULL, email = NULL,
      anonymized_at = transaction_timestamp(), anonymization_reason = 'withdrawal'
  WHERE promotion_target_id = '00000000-0113-4000-8000-000000000001';
  SELECT count(*) INTO validate_count FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, '00000000-0113-4000-8000-000000000305', transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted target status drift'; END IF;
  UPDATE app_data.promotion_targets
  SET status = 'active', phone = '+1 312 555 0113',
      anonymized_at = NULL, anonymization_reason = NULL
  WHERE promotion_target_id = '00000000-0113-4000-8000-000000000001';

  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id, first_target_id, second_target_id,
    first_profile_revision, second_profile_revision, first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc, merge_deadline_at_utc,
    phone_match, email_match, previewed_at_utc, expires_at_utc
  )
  SELECT '00000000-0113-4000-8000-000000000303', actor_id, actor_workspace_id,
    first_target.promotion_target_id, second_target.promotion_target_id,
    first_target.profile_revision, second_target.profile_revision,
    '00000000-0113-4000-8000-000000000101', '00000000-0113-4000-8000-000000000102',
    app_data.promotion_target_review_due_at(first_target.promotion_target_id),
    app_data.promotion_target_review_due_at(second_target.promotion_target_id),
    LEAST(app_data.promotion_target_review_due_at(first_target.promotion_target_id), app_data.promotion_target_review_due_at(second_target.promotion_target_id)),
    true, false, transaction_timestamp() - interval '1 minute', transaction_timestamp() + interval '14 minutes'
  FROM app_data.promotion_targets AS first_target CROSS JOIN app_data.promotion_targets AS second_target
  WHERE first_target.promotion_target_id = '00000000-0113-4000-8000-000000000001'
    AND second_target.promotion_target_id = '00000000-0113-4000-8000-000000000002';
  UPDATE app_data.promotion_targets SET phone = '+1 312 555 0198'
  WHERE promotion_target_id = '00000000-0113-4000-8000-000000000001';
  SELECT count(*) INTO validate_count FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, '00000000-0113-4000-8000-000000000303', transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted match signal drift'; END IF;
  UPDATE app_data.promotion_targets SET phone = '+1 312 555 0113'
  WHERE promotion_target_id = '00000000-0113-4000-8000-000000000001';

  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id, first_target_id, second_target_id,
    first_profile_revision, second_profile_revision, first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc, merge_deadline_at_utc,
    phone_match, email_match, previewed_at_utc, expires_at_utc
  )
  SELECT '00000000-0113-4000-8000-000000000304', actor_id, actor_workspace_id,
    first_target.promotion_target_id, second_target.promotion_target_id,
    first_target.profile_revision, second_target.profile_revision,
    '00000000-0113-4000-8000-000000000101', '00000000-0113-4000-8000-000000000102',
    app_data.promotion_target_review_due_at(first_target.promotion_target_id),
    app_data.promotion_target_review_due_at(second_target.promotion_target_id),
    LEAST(app_data.promotion_target_review_due_at(first_target.promotion_target_id), app_data.promotion_target_review_due_at(second_target.promotion_target_id)),
    true, false, transaction_timestamp() - interval '1 minute', transaction_timestamp() + interval '14 minutes'
  FROM app_data.promotion_targets AS first_target CROSS JOIN app_data.promotion_targets AS second_target
  WHERE first_target.promotion_target_id = '00000000-0113-4000-8000-000000000001'
    AND second_target.promotion_target_id = '00000000-0113-4000-8000-000000000002';
  UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = actor_id;
  SELECT count(*) INTO validate_count FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, project_id, '00000000-0113-4000-8000-000000000304', transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted non-active actor'; END IF;
  UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = actor_id;

  SELECT count(*) INTO validate_count FROM app_private.validate_personal_target_pair_preview_v1(
    actor_id, '00000000-0113-4000-8000-000000000090',
    '00000000-0113-4000-8000-000000000304', transaction_timestamp()
  );
  IF validate_count <> 0 THEN RAISE EXCEPTION 'validator accepted current-project drift'; END IF;
END
$validator$;

DO $cleanup$
DECLARE
  first_cleanup integer;
  second_cleanup integer;
  third_cleanup integer;
  drained_cleanup integer;
  remaining_expired bigint;
  unexpired_count bigint;
BEGIN
  LOOP
    SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1()
    INTO drained_cleanup;
    EXIT WHEN drained_cleanup = 0;
  END LOOP;

  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id, first_target_id, second_target_id,
    first_profile_revision, second_profile_revision, first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc, merge_deadline_at_utc,
    phone_match, email_match, previewed_at_utc, expires_at_utc
  )
  SELECT
    ('00000000-0113-4000-8000-' || lpad((1000 + series)::text, 12, '0'))::uuid,
    (SELECT app_user_id FROM fixture_0113_owner_context),
    (SELECT workspace_id FROM fixture_0113_owner_context),
    '00000000-0113-4000-8000-000000000001',
    '00000000-0113-4000-8000-000000000002', 1, 1,
    '00000000-0113-4000-8000-000000000101',
    '00000000-0113-4000-8000-000000000102',
    transaction_timestamp() + interval '1 year',
    transaction_timestamp() + interval '1 year',
    transaction_timestamp() + interval '1 year', true, false,
    CASE WHEN series = 105
      THEN transaction_timestamp() - interval '15 minutes'
      ELSE transaction_timestamp() - interval '2 hours'
    END,
    CASE WHEN series = 105
      THEN transaction_timestamp()
      ELSE transaction_timestamp() - interval '105 minutes'
    END
  FROM generate_series(1, 105) AS series;
  INSERT INTO app_private.personal_target_pair_preview_receipts (
    preview_id, actor_app_user_id, workspace_id, first_target_id, second_target_id,
    first_profile_revision, second_profile_revision, first_assignment_id, second_assignment_id,
    first_retention_due_at_utc, second_retention_due_at_utc, merge_deadline_at_utc,
    phone_match, email_match, previewed_at_utc, expires_at_utc
  ) VALUES (
    '00000000-0113-4000-8000-000000000299',
    (SELECT app_user_id FROM fixture_0113_owner_context),
    (SELECT workspace_id FROM fixture_0113_owner_context),
    '00000000-0113-4000-8000-000000000001',
    '00000000-0113-4000-8000-000000000002', 1, 1,
    '00000000-0113-4000-8000-000000000101',
    '00000000-0113-4000-8000-000000000102',
    transaction_timestamp() + interval '1 year',
    transaction_timestamp() + interval '1 year',
    transaction_timestamp() + interval '1 year', true, false,
    transaction_timestamp(), transaction_timestamp() + interval '15 minutes'
  );
  SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1() INTO first_cleanup;
  SELECT count(*) INTO remaining_expired
  FROM app_private.personal_target_pair_preview_receipts
  WHERE expires_at_utc <= clock_timestamp();
  SELECT count(*) INTO unexpired_count
  FROM app_private.personal_target_pair_preview_receipts
  WHERE preview_id = '00000000-0113-4000-8000-000000000299';
  SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1() INTO second_cleanup;
  SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1() INTO third_cleanup;
  IF first_cleanup <> 100 OR remaining_expired <> 5 OR second_cleanup <> 5
    OR third_cleanup <> 0 OR unexpired_count <> 1
    OR EXISTS (SELECT 1 FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id BETWEEN '00000000-0113-4000-8000-000000001001'::uuid
        AND '00000000-0113-4000-8000-000000001105'::uuid)
  THEN
    RAISE EXCEPTION 'receipt cleanup did not delete a bounded batch or preserve live receipts';
  END IF;
END
$cleanup$;

SELECT pg_temp.expect_failure('55000', $$UPDATE app_private.personal_target_pair_preview_receipts SET phone_match = false WHERE preview_id = (SELECT preview_id FROM fixture_0113_previews WHERE case_name = 'phone')$$);
SELECT pg_temp.expect_failure('55000', $$UPDATE app_private.personal_target_pair_preview_audit_events SET outcome = 'previewed' WHERE audit_event_id = (SELECT audit_event_id FROM app_private.personal_target_pair_preview_audit_events LIMIT 1)$$);
SELECT pg_temp.expect_failure('55000', $$DELETE FROM app_private.personal_target_pair_preview_audit_events WHERE audit_event_id = (SELECT audit_event_id FROM app_private.personal_target_pair_preview_audit_events LIMIT 1)$$);
SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_failure('42501', $$DELETE FROM app_private.personal_target_pair_preview_receipts WHERE preview_id = (SELECT preview_id FROM fixture_0113_previews WHERE case_name = 'phone')$$);
RESET ROLE;

ROLLBACK;
