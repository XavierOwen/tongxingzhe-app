-- synthetic fixture：证明接触提交、幂等、审计和分析 Outbox 原子一致。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE sync_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-sync.supabase.co/auth/v1',
  'synthetic-sync-subject'
);

CREATE TEMP TABLE first_result AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM sync_context),
  'synthetic-command-1',
  1,
  'contact.submit.v1',
  'synthetic-device-1',
  'synthetic-contact-1',
  0,
  jsonb_build_object(
    'contactId', 'synthetic-contact-1',
    'workspaceId', (SELECT workspace_id FROM sync_context),
    'projectId', (SELECT project_id FROM sync_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM sync_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 2,
    'interestLevel', 3,
    'answers', jsonb_build_array(
      jsonb_build_object(
        'questionId', 'follow_up_consent',
        'state', 'answered',
        'type', 'boolean',
        'value', true
      )
    )
  )
);

CREATE TEMP TABLE duplicate_result AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM sync_context),
  'synthetic-command-1',
  1,
  'contact.submit.v1',
  'synthetic-device-1',
  'synthetic-contact-1',
  0,
  jsonb_build_object(
    'contactId', 'synthetic-contact-1',
    'workspaceId', (SELECT workspace_id FROM sync_context),
    'projectId', (SELECT project_id FROM sync_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM sync_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 2,
    'interestLevel', 3,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE pull_result AS
SELECT *
FROM app_data.pull_contact_changes(
  (SELECT app_user_id FROM sync_context),
  (SELECT workspace_id FROM sync_context),
  (SELECT project_id FROM sync_context),
  NULL,
  100
);

CREATE TEMP TABLE pull_after_result AS
SELECT *
FROM app_data.pull_contact_changes(
  (SELECT app_user_id FROM sync_context),
  (SELECT workspace_id FROM sync_context),
  (SELECT project_id FROM sync_context),
  (SELECT server_cursor FROM pull_result),
  100
);

DO $runtime_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM first_result
    WHERE result_code = 'accepted'
      AND server_cursor IS NOT NULL
      AND failure_code IS NULL
  ) THEN
    RAISE EXCEPTION 'first contact command was not accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM duplicate_result AS duplicate_row
    JOIN first_result AS first_row
      USING (server_cursor)
    WHERE duplicate_row.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'duplicate command did not return the original cursor';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pull_result
    WHERE change_type = 'contact.submitted'
      AND revision_number = 1
      AND contact_payload->>'contactId' = 'synthetic-contact-1'
      AND contact_payload->>'firstSubmittedAtUtc' IS NOT NULL
      AND contact_payload->'answers'->0->>'questionId' =
        'follow_up_consent'
  ) THEN
    RAISE EXCEPTION 'pull did not return the complete contact snapshot';
  END IF;

  IF EXISTS (SELECT 1 FROM pull_after_result) THEN
    RAISE EXCEPTION 'pull cursor replayed an acknowledged change';
  END IF;

  BEGIN
    PERFORM 1 FROM app_data.contacts;
    RAISE EXCEPTION 'runtime role read contact table directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_data.pull_contact_changes(
      (SELECT app_user_id FROM sync_context),
      (SELECT workspace_id FROM sync_context),
      (SELECT project_id FROM sync_context),
      'not-a-real-cursor',
      100
    );
    RAISE EXCEPTION 'invalid pull cursor was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;
END
$runtime_check$;

RESET ROLE;

DO $owner_check$
BEGIN
  IF (
    SELECT count(*)
    FROM app_data.contacts
    WHERE contact_id = 'synthetic-contact-1'
  ) <> 1 THEN
    RAISE EXCEPTION 'idempotent replay changed contact count';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.contact_revisions
    WHERE contact_id = 'synthetic-contact-1'
  ) <> 1 THEN
    RAISE EXCEPTION 'contact revision was not atomic';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.contact_answers
    WHERE contact_id = 'synthetic-contact-1'
      AND question_id = 'follow_up_consent'
      AND boolean_value
  ) <> 1 THEN
    RAISE EXCEPTION 'typed answer was not stored';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.processed_commands
    WHERE command_id = 'synthetic-command-1'
      AND result_code = 'accepted'
  ) <> 1 THEN
    RAISE EXCEPTION 'processed command was not idempotent';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.change_feed
    WHERE aggregate_id = 'synthetic-contact-1'
  ) <> 1 THEN
    RAISE EXCEPTION 'change feed was not atomic';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.contact_audit_events
    WHERE contact_id = 'synthetic-contact-1'
  ) <> 1 THEN
    RAISE EXCEPTION 'audit event was not atomic';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.warehouse_outbox
    WHERE contact_id = 'synthetic-contact-1'
      AND NOT (analytics_payload ? 'location')
      AND NOT (analytics_payload ? 'app_user_id')
  ) <> 1 THEN
    RAISE EXCEPTION 'warehouse payload contains an unapproved field';
  END IF;
END
$owner_check$;

ROLLBACK;
