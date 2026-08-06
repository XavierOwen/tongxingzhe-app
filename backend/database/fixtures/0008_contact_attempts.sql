-- synthetic fixture：证明尝试独立同步，后来回应新建接触且不改写原尝试。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE attempt_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-attempt.supabase.co/auth/v1',
  'synthetic-attempt-subject'
);

CREATE TEMP TABLE attempt_result AS
SELECT *
FROM app_data.apply_contact_attempt_submit(
  (SELECT app_user_id FROM attempt_context),
  'synthetic-attempt-command-1',
  1,
  'contact.attempt.submit.v1',
  'synthetic-device-1',
  'synthetic-attempt-1',
  0,
  jsonb_build_object(
    'attemptId', 'synthetic-attempt-1',
    'workspaceId', (SELECT workspace_id FROM attempt_context),
    'projectId', (SELECT project_id FROM attempt_context),
    'occurredAtUtc', '2030-01-08T17:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL
  )
);

CREATE TEMP TABLE duplicate_attempt_result AS
SELECT *
FROM app_data.apply_contact_attempt_submit(
  (SELECT app_user_id FROM attempt_context),
  'synthetic-attempt-command-1',
  1,
  'contact.attempt.submit.v1',
  'synthetic-device-1',
  'synthetic-attempt-1',
  0,
  jsonb_build_object(
    'attemptId', 'synthetic-attempt-1',
    'workspaceId', (SELECT workspace_id FROM attempt_context),
    'projectId', (SELECT project_id FROM attempt_context),
    'occurredAtUtc', '2030-01-08T17:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL
  )
);

CREATE TEMP TABLE response_contact_result AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM attempt_context),
  'synthetic-response-command-1',
  1,
  'contact.submit.v1',
  'synthetic-device-1',
  'synthetic-response-contact-1',
  0,
  jsonb_build_object(
    'contactId', 'synthetic-response-contact-1',
    'workspaceId', (SELECT workspace_id FROM attempt_context),
    'projectId', (SELECT project_id FROM attempt_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM attempt_context),
    'sourceAttemptId', 'synthetic-attempt-1',
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE attempt_pull_result AS
SELECT *
FROM app_data.pull_sync_changes(
  (SELECT app_user_id FROM attempt_context),
  (SELECT workspace_id FROM attempt_context),
  (SELECT project_id FROM attempt_context),
  NULL,
  100
);

DO $runtime_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM attempt_result
    WHERE result_code = 'accepted' AND server_cursor IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'contact attempt was not accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM duplicate_attempt_result AS duplicate_row
    JOIN attempt_result AS first_row USING (server_cursor)
    WHERE duplicate_row.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'contact attempt replay was not idempotent';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM response_contact_result
    WHERE result_code = 'accepted' AND server_cursor IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'response contact was not accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM attempt_pull_result
    WHERE change_type = 'contact.attempt.submitted'
      AND revision_number = 1
      AND typed_payload->>'attemptId' = 'synthetic-attempt-1'
      AND NOT (typed_payload ? 'reachCount')
      AND NOT (typed_payload ? 'interestLevel')
      AND NOT (typed_payload ? 'answers')
  ) THEN
    RAISE EXCEPTION 'attempt pull payload changed the metric boundary';
  END IF;

  BEGIN
    PERFORM 1 FROM app_data.contact_attempts;
    RAISE EXCEPTION 'runtime role read contact attempts directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$runtime_check$;

RESET ROLE;

DO $owner_check$
BEGIN
  IF (
    SELECT count(*) FROM app_data.contact_attempts
    WHERE attempt_id = 'synthetic-attempt-1'
      AND linked_contact_id = 'synthetic-response-contact-1'
  ) <> 1 THEN
    RAISE EXCEPTION 'response contact did not link the original attempt';
  END IF;

  IF (
    SELECT count(*) FROM app_data.contacts
    WHERE contact_id = 'synthetic-response-contact-1'
      AND reach_count = 1
  ) <> 1 THEN
    RAISE EXCEPTION 'response did not create an independent contact';
  END IF;

  IF EXISTS (
    SELECT 1 FROM app_data.warehouse_outbox
    WHERE contact_id = 'synthetic-attempt-1'
  ) THEN
    RAISE EXCEPTION 'contact attempt entered the analytics warehouse outbox';
  END IF;
END
$owner_check$;

ROLLBACK;
