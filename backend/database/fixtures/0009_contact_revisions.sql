-- synthetic fixture：证明更正、作废、版本冲突、权限和指标口径原子一致。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE revision_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-revision.supabase.co/auth/v1',
  'synthetic-revision-owner'
);

CREATE TEMP TABLE revision_other_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-revision.supabase.co/auth/v1',
  'synthetic-revision-other'
);

CREATE TEMP TABLE revision_submit_result AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM revision_owner_context),
  'synthetic-revision-submit-command',
  1,
  'contact.submit.v1',
  'synthetic-device-1',
  'synthetic-revision-contact',
  0,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_owner_context),
    'projectId', (SELECT project_id FROM revision_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM revision_owner_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object(
        'questionId', 'follow_up_consent',
        'state', 'answered',
        'type', 'boolean',
        'value', false
      )
    )
  )
);

CREATE TEMP TABLE revision_revise_result AS
SELECT *
FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM revision_owner_context),
  'synthetic-revision-revise-command',
  1,
  'contact.revise.v1',
  'synthetic-device-1',
  'synthetic-revision-contact',
  1,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_owner_context),
    'projectId', (SELECT project_id FROM revision_owner_context),
    'reason', 'Correct occurrence date and reach count',
    'occurredAtUtc', '2030-02-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 3,
    'interestLevel', 4,
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

CREATE TEMP TABLE revision_duplicate_result AS
SELECT *
FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM revision_owner_context),
  'synthetic-revision-revise-command',
  1,
  'contact.revise.v1',
  'synthetic-device-1',
  'synthetic-revision-contact',
  1,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_owner_context),
    'projectId', (SELECT project_id FROM revision_owner_context),
    'reason', 'Replay must return the original result'
  )
);

CREATE TEMP TABLE revision_stale_result AS
SELECT *
FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM revision_owner_context),
  'synthetic-revision-stale-command',
  1,
  'contact.revise.v1',
  'synthetic-device-1',
  'synthetic-revision-contact',
  1,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_owner_context),
    'projectId', (SELECT project_id FROM revision_owner_context),
    'reason', 'Stale editor',
    'occurredAtUtc', '2030-02-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 9,
    'interestLevel', 1,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE revision_forbidden_result AS
SELECT *
FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM revision_other_context),
  'synthetic-revision-forbidden-command',
  1,
  'contact.revise.v1',
  'synthetic-device-2',
  'synthetic-revision-contact',
  2,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_other_context),
    'projectId', (SELECT project_id FROM revision_other_context),
    'reason', 'Unauthorized change',
    'occurredAtUtc', '2030-02-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 9,
    'interestLevel', 1,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE revision_january_metrics AS
SELECT *
FROM app_data.read_personal_contact_summary(
  (SELECT app_user_id FROM revision_owner_context),
  (SELECT workspace_id FROM revision_owner_context),
  (SELECT project_id FROM revision_owner_context),
  '2030-01-01T00:00:00Z',
  '2030-02-01T00:00:00Z'
);

CREATE TEMP TABLE revision_february_metrics AS
SELECT *
FROM app_data.read_personal_contact_summary(
  (SELECT app_user_id FROM revision_owner_context),
  (SELECT workspace_id FROM revision_owner_context),
  (SELECT project_id FROM revision_owner_context),
  '2030-02-01T00:00:00Z',
  '2030-03-01T00:00:00Z'
);

CREATE TEMP TABLE revision_void_result AS
SELECT *
FROM app_data.apply_contact_void(
  (SELECT app_user_id FROM revision_owner_context),
  'synthetic-revision-void-command',
  1,
  'contact.void.v1',
  'synthetic-device-1',
  'synthetic-revision-contact',
  2,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_owner_context),
    'projectId', (SELECT project_id FROM revision_owner_context),
    'reason', 'Duplicate contact'
  )
);

CREATE TEMP TABLE revision_void_duplicate_result AS
SELECT *
FROM app_data.apply_contact_void(
  (SELECT app_user_id FROM revision_owner_context),
  'synthetic-revision-void-command',
  1,
  'contact.void.v1',
  'synthetic-device-1',
  'synthetic-revision-contact',
  2,
  jsonb_build_object(
    'contactId', 'synthetic-revision-contact',
    'workspaceId', (SELECT workspace_id FROM revision_owner_context),
    'projectId', (SELECT project_id FROM revision_owner_context),
    'reason', 'Replay'
  )
);

CREATE TEMP TABLE revision_after_void_metrics AS
SELECT *
FROM app_data.read_personal_contact_summary(
  (SELECT app_user_id FROM revision_owner_context),
  (SELECT workspace_id FROM revision_owner_context),
  (SELECT project_id FROM revision_owner_context),
  '2030-02-01T00:00:00Z',
  '2030-03-01T00:00:00Z'
);

CREATE TEMP TABLE revision_pull_result AS
SELECT *
FROM app_data.pull_sync_changes(
  (SELECT app_user_id FROM revision_owner_context),
  (SELECT workspace_id FROM revision_owner_context),
  (SELECT project_id FROM revision_owner_context),
  NULL,
  100
);

DO $runtime_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM revision_submit_result WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM revision_revise_result WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM revision_void_result WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'contact revision happy path was not accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM revision_duplicate_result AS duplicate_row
    JOIN revision_revise_result AS accepted_row USING (server_cursor)
    WHERE duplicate_row.result_code = 'duplicate'
  ) OR NOT EXISTS (
    SELECT 1
    FROM revision_void_duplicate_result AS duplicate_row
    JOIN revision_void_result AS accepted_row USING (server_cursor)
    WHERE duplicate_row.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'contact revision replay was not idempotent';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM revision_stale_result
    WHERE result_code = 'conflict'
      AND failure_code = 'contact_revision_conflict'
  ) THEN
    RAISE EXCEPTION 'stale contact revision was not rejected';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM revision_forbidden_result
    WHERE result_code = 'forbidden'
      AND failure_code = 'contact_forbidden'
  ) THEN
    RAISE EXCEPTION 'foreign contact revision was not forbidden';
  END IF;

  IF (SELECT contact_session_count FROM revision_january_metrics) <> 0
    OR (SELECT contact_session_count FROM revision_february_metrics) <> 1
    OR (SELECT reach_count FROM revision_february_metrics) <> 3
    OR (SELECT contact_session_count FROM revision_after_void_metrics) <> 0
  THEN
    RAISE EXCEPTION 'revision period or void metric semantics drifted';
  END IF;

  IF (
    SELECT count(*) FROM revision_pull_result
    WHERE change_type IN (
      'contact.submitted',
      'contact.revised',
      'contact.voided'
    )
  ) <> 3 OR NOT EXISTS (
    SELECT 1 FROM revision_pull_result
    WHERE change_type = 'contact.revised'
      AND revision_number = 2
      AND typed_payload->>'revisionKind' = 'corrected'
      AND typed_payload->>'reason' = 'Correct occurrence date and reach count'
  ) OR NOT EXISTS (
    SELECT 1 FROM revision_pull_result
    WHERE change_type = 'contact.voided'
      AND revision_number = 3
      AND typed_payload->>'revisionKind' = 'voided'
      AND typed_payload->>'reason' = 'Duplicate contact'
  ) THEN
    RAISE EXCEPTION 'revision change feed lost history metadata';
  END IF;

  BEGIN
    PERFORM 1 FROM app_data.contact_revisions;
    RAISE EXCEPTION 'runtime role read contact revisions directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$runtime_check$;

RESET ROLE;

DO $owner_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id = 'synthetic-revision-contact'
      AND current_revision = 3
      AND lifecycle_status = 'voided'
      AND occurred_at_utc = '2030-02-08T18:00:00Z'
      AND reach_count = 3
  ) THEN
    RAISE EXCEPTION 'current contact projection is incorrect';
  END IF;

  IF (
    SELECT count(*) FROM app_data.contact_revisions
    WHERE contact_id = 'synthetic-revision-contact'
  ) <> 3 OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_revisions
    WHERE contact_id = 'synthetic-revision-contact'
      AND revision_number = 1
      AND revision_kind = 'submitted'
      AND reason IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_revisions
    WHERE contact_id = 'synthetic-revision-contact'
      AND revision_number = 2
      AND revision_kind = 'corrected'
      AND reason = 'Correct occurrence date and reach count'
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_revisions
    WHERE contact_id = 'synthetic-revision-contact'
      AND revision_number = 3
      AND revision_kind = 'voided'
      AND reason = 'Duplicate contact'
  ) THEN
    RAISE EXCEPTION 'append-only contact history is incomplete';
  END IF;

  IF (
    SELECT count(*) FROM app_data.contact_answers
    WHERE contact_id = 'synthetic-revision-contact'
  ) <> 3 THEN
    RAISE EXCEPTION 'revision answers were not snapshotted';
  END IF;

  IF (
    SELECT count(*) FROM app_data.contact_audit_events
    WHERE contact_id = 'synthetic-revision-contact'
  ) <> 3 OR (
    SELECT count(*) FROM app_data.warehouse_outbox
    WHERE contact_id = 'synthetic-revision-contact'
  ) <> 3 THEN
    RAISE EXCEPTION 'revision audit or warehouse events are incomplete';
  END IF;
END
$owner_check$;

ROLLBACK;
