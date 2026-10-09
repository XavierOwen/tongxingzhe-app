\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0117_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0117.example.test', 'owner'
);

SELECT count(*) AS current_context_count
FROM app_data.list_personal_project_contexts(
  'https://synthetic-0117.example.test', 'owner'
)
WHERE is_current;

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

INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name,
  phone, email, status, created_by_app_user_id, created_at,
  anonymized_at, anonymization_reason
) VALUES
  ('00000000-0117-4000-8000-000000000001',
   (SELECT workspace_id FROM fixture_0117_context), 'person',
   '0117 activation source A', '+1 312 555 0117', 'a-0117@example.test',
   'active', (SELECT app_user_id FROM fixture_0117_context),
   transaction_timestamp(), NULL, NULL),
  ('00000000-0117-4000-8000-000000000002',
   (SELECT workspace_id FROM fixture_0117_context), 'person',
   '0117 activation source B', '+1 312 555 0117', 'b-0117@example.test',
   'active', (SELECT app_user_id FROM fixture_0117_context),
   transaction_timestamp(), NULL, NULL);

INSERT INTO app_data.promotion_target_assignments (
  assignment_id, promotion_target_id, app_user_id,
  assigned_by_app_user_id, assigned_at, ended_at, end_reason
) VALUES
  ('00000000-0117-4000-8000-000000000101',
   '00000000-0117-4000-8000-000000000001',
   (SELECT app_user_id FROM fixture_0117_context),
   (SELECT app_user_id FROM fixture_0117_context), transaction_timestamp(),
   NULL, NULL),
  ('00000000-0117-4000-8000-000000000102',
   '00000000-0117-4000-8000-000000000002',
   (SELECT app_user_id FROM fixture_0117_context),
   (SELECT app_user_id FROM fixture_0117_context), transaction_timestamp(),
   NULL, NULL);

CREATE TEMP TABLE fixture_0117_preview ON COMMIT DROP AS
SELECT preview.preview_id, context_row.app_user_id, context_row.project_id,
       context_row.workspace_id
FROM fixture_0117_context AS context_row
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://synthetic-0117.example.test', 'owner', context_row.project_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002'
) AS preview;

WITH expired_time AS MATERIALIZED (
  SELECT clock_timestamp() - interval '16 minutes' AS previewed_at_utc
)
INSERT INTO app_private.personal_target_pair_preview_receipts (
  preview_id, actor_app_user_id, workspace_id,
  first_target_id, second_target_id,
  first_profile_revision, second_profile_revision,
  first_assignment_id, second_assignment_id,
  first_retention_due_at_utc, second_retention_due_at_utc,
  merge_deadline_at_utc, phone_match, email_match,
  previewed_at_utc, expires_at_utc
)
SELECT
  '00000000-0117-4000-8000-000000000004',
  receipt.actor_app_user_id, receipt.workspace_id,
  receipt.first_target_id, receipt.second_target_id,
  receipt.first_profile_revision, receipt.second_profile_revision,
  receipt.first_assignment_id, receipt.second_assignment_id,
  receipt.first_retention_due_at_utc, receipt.second_retention_due_at_utc,
  receipt.merge_deadline_at_utc, receipt.phone_match, receipt.email_match,
  expired_time.previewed_at_utc,
  expired_time.previewed_at_utc + interval '15 minutes'
FROM app_private.personal_target_pair_preview_receipts AS receipt
CROSS JOIN expired_time
WHERE receipt.preview_id = (SELECT preview_id FROM fixture_0117_preview);

CREATE TEMP TABLE fixture_0117_before_expired_receipt ON COMMIT DROP AS
SELECT fence.epoch,
  (SELECT count(*) FROM app_private.personal_target_merge_generations_v1)
    AS generation_count,
  (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1)
    AS member_count,
  (SELECT count(*) FROM app_private.personal_target_merge_activation_requests_v1)
    AS request_count,
  (SELECT count(*) FROM app_private.personal_target_merge_activation_audit_v1)
    AS audit_count
FROM app_private.personal_target_merge_generation_fence_v1 AS fence;

SELECT pg_temp.expect_failure('42501',
  $$SELECT app_private.activate_personal_target_merge_generation_v2(
    (SELECT app_user_id FROM fixture_0117_context),
    (SELECT project_id FROM fixture_0117_context),
    '00000000-0117-4000-8000-000000000203',
    '00000000-0117-4000-8000-000000000004',
    '00000000-0117-4000-8000-000000000001',
    '00000000-0117-4000-8000-000000000001',
    '00000000-0117-4000-8000-000000000002',
    '00000000-0117-4000-8000-000000000001'
  )$$
);

DO $expired_receipt$
DECLARE
  before_row record;
BEGIN
  SELECT * INTO STRICT before_row FROM fixture_0117_before_expired_receipt;
  IF before_row.epoch IS DISTINCT FROM (
      SELECT epoch FROM app_private.personal_target_merge_generation_fence_v1
    ) OR before_row.generation_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_generations_v1
    ) OR before_row.member_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1
    ) OR before_row.request_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_activation_requests_v1
    ) OR before_row.audit_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_activation_audit_v1
    ) THEN
    RAISE EXCEPTION 'expired receipt left activation side effects';
  END IF;
END
$expired_receipt$;

CREATE TEMP TABLE fixture_0117_before_invalid_selector ON COMMIT DROP AS
SELECT fence.epoch,
  (SELECT count(*) FROM app_private.personal_target_merge_generations_v1)
    AS generation_count,
  (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1)
    AS member_count,
  (SELECT count(*) FROM app_private.personal_target_merge_activation_requests_v1)
    AS request_count,
  (SELECT count(*) FROM app_private.personal_target_merge_activation_audit_v1)
    AS audit_count
FROM app_private.personal_target_merge_generation_fence_v1 AS fence;

SELECT pg_temp.expect_failure('42501', format(
  'SELECT app_private.activate_personal_target_merge_generation_v2(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
  preview.app_user_id, preview.project_id,
  '00000000-0117-4000-8000-000000000202', preview.preview_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002',
  '00000000-0117-4000-8000-000000000003'
))
FROM fixture_0117_preview AS preview;

DO $invalid_selector$
DECLARE
  before_row record;
BEGIN
  SELECT * INTO STRICT before_row FROM fixture_0117_before_invalid_selector;
  IF before_row.epoch IS DISTINCT FROM (
      SELECT epoch FROM app_private.personal_target_merge_generation_fence_v1
    ) OR before_row.generation_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_generations_v1
    ) OR before_row.member_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1
    ) OR before_row.request_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_activation_requests_v1
    ) OR before_row.audit_count <> (
      SELECT count(*) FROM app_private.personal_target_merge_activation_audit_v1
    ) THEN
    RAISE EXCEPTION 'non-receipt selector left activation side effects';
  END IF;
END
$invalid_selector$;

CREATE TEMP TABLE fixture_0117_activation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  preview.app_user_id,
  preview.project_id,
  '00000000-0117-4000-8000-000000000201',
  preview.preview_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002',
  '00000000-0117-4000-8000-000000000001'
) AS generation_id
FROM fixture_0117_preview AS preview;

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0117_context);
SELECT pg_temp.expect_failure('42501', format(
  'SELECT app_private.activate_personal_target_merge_generation_v2(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
  preview.app_user_id, preview.project_id,
  '00000000-0117-4000-8000-000000000201', preview.preview_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002',
  '00000000-0117-4000-8000-000000000001'
))
FROM fixture_0117_preview AS preview;
UPDATE app_data.app_users
SET status = 'active'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0117_context);

CREATE TEMP TABLE fixture_0117_after_first ON COMMIT DROP AS
SELECT fence.epoch,
  (SELECT count(*) FROM app_private.personal_target_merge_generations_v1
    WHERE generation_id IN (SELECT generation_id FROM fixture_0117_activation))
      AS generation_count,
  (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1
    WHERE generation_id IN (SELECT generation_id FROM fixture_0117_activation))
      AS member_count,
  (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1
    WHERE generation_id IN (SELECT generation_id FROM fixture_0117_activation))
      AS active_member_count,
  (SELECT count(*) FROM app_private.personal_target_merge_activation_requests_v1
    WHERE actor_app_user_id = (SELECT app_user_id FROM fixture_0117_context)
      AND request_id = '00000000-0117-4000-8000-000000000201') AS request_count,
  (SELECT count(*) FROM app_private.personal_target_merge_activation_audit_v1
    WHERE actor_app_user_id = (SELECT app_user_id FROM fixture_0117_context)
      AND request_id = '00000000-0117-4000-8000-000000000201') AS audit_count
FROM app_private.personal_target_merge_generation_fence_v1 AS fence;

SELECT pg_temp.expect_failure('23505', format(
  'SELECT app_private.activate_personal_target_merge_generation_v2(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
  preview.app_user_id, preview.project_id,
  '00000000-0117-4000-8000-000000000202', preview.preview_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002',
  '00000000-0117-4000-8000-000000000001'
))
FROM fixture_0117_preview AS preview;

SELECT pg_temp.expect_failure('23505', format(
  'SELECT app_private.activate_personal_target_merge_generation_v2(%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid,%L::uuid)',
  preview.app_user_id, preview.project_id,
  '00000000-0117-4000-8000-000000000201', preview.preview_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002',
  '00000000-0117-4000-8000-000000000002'
))
FROM fixture_0117_preview AS preview;

SELECT pg_temp.expect_failure('55000', $$
  UPDATE app_private.personal_target_merge_activation_requests_v1
  SET activated_at_utc = activated_at_utc
  WHERE request_id = '00000000-0117-4000-8000-000000000201'
$$);
SELECT pg_temp.expect_failure('55000', $$
  DELETE FROM app_private.personal_target_merge_activation_requests_v1
  WHERE request_id = '00000000-0117-4000-8000-000000000201'
$$);
SELECT pg_temp.expect_failure('55000', $$
  UPDATE app_private.personal_target_merge_activation_audit_v1
  SET outcome = outcome
  WHERE request_id = '00000000-0117-4000-8000-000000000201'
$$);
SELECT pg_temp.expect_failure('55000', $$
  DELETE FROM app_private.personal_target_merge_activation_audit_v1
  WHERE request_id = '00000000-0117-4000-8000-000000000201'
$$);

DELETE FROM app_private.personal_target_pair_preview_receipts
WHERE preview_id = (SELECT preview_id FROM fixture_0117_preview);

CREATE TEMP TABLE fixture_0117_replay ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  preview.app_user_id,
  preview.project_id,
  '00000000-0117-4000-8000-000000000201',
  preview.preview_id,
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000001',
  '00000000-0117-4000-8000-000000000002',
  '00000000-0117-4000-8000-000000000001'
) AS generation_id
FROM fixture_0117_preview AS preview;

DO $assertions$
DECLARE
  first_generation_id uuid;
  replay_generation_id uuid;
  before_epoch bigint;
  after_epoch bigint;
  generation_count bigint;
  member_count bigint;
  active_member_count bigint;
  request_row app_private.personal_target_merge_activation_requests_v1%ROWTYPE;
BEGIN
  SELECT generation_id INTO STRICT first_generation_id FROM fixture_0117_activation;
  SELECT generation_id INTO STRICT replay_generation_id FROM fixture_0117_replay;
  SELECT snapshot.epoch, snapshot.generation_count,
         snapshot.member_count, snapshot.active_member_count
    INTO STRICT before_epoch, generation_count, member_count, active_member_count
  FROM fixture_0117_after_first AS snapshot;
  SELECT epoch INTO STRICT after_epoch
  FROM app_private.personal_target_merge_generation_fence_v1;
  SELECT * INTO STRICT request_row
  FROM app_private.personal_target_merge_activation_requests_v1
  WHERE actor_app_user_id = (SELECT app_user_id FROM fixture_0117_context)
    AND request_id = '00000000-0117-4000-8000-000000000201';

  IF first_generation_id IS DISTINCT FROM replay_generation_id
    OR before_epoch IS DISTINCT FROM after_epoch
    OR generation_count <> 1 OR member_count <> 2 OR active_member_count <> 2
    OR (SELECT request_count FROM fixture_0117_after_first) <> 1
    OR (SELECT audit_count FROM fixture_0117_after_first) <> 1
    OR request_row.workspace_id <>
      (SELECT workspace_id FROM fixture_0117_context)
    OR request_row.preview_id <>
      (SELECT preview_id FROM fixture_0117_preview)
    OR request_row.retained_target_id <>
      '00000000-0117-4000-8000-000000000001'::uuid
    OR request_row.display_name_source_target_id <>
      '00000000-0117-4000-8000-000000000001'::uuid
    OR request_row.phone_source_target_id <>
      '00000000-0117-4000-8000-000000000002'::uuid
    OR request_row.email_source_target_id <>
      '00000000-0117-4000-8000-000000000001'::uuid
    OR request_row.generation_id IS DISTINCT FROM first_generation_id
    OR request_row.activated_at_utc IS NULL
    OR EXISTS (
      SELECT 1 FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id = request_row.preview_id
    )
    OR (SELECT count(*)
      FROM app_private.personal_target_merge_activation_requests_v1
      WHERE actor_app_user_id = request_row.actor_app_user_id
        AND request_id = request_row.request_id) <> 1
    OR (SELECT count(*)
      FROM app_private.personal_target_merge_activation_audit_v1
      WHERE actor_app_user_id = request_row.actor_app_user_id
        AND request_id = request_row.request_id) <> 1
  THEN
    RAISE EXCEPTION '0117 activation or exact replay contract drifted';
  END IF;
END
$assertions$;

ROLLBACK;
