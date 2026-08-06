-- synthetic fixture：证明三路自动合并、显式冲突、授权读取和幂等解决。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE conflict_owner_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-conflict.supabase.co/auth/v1',
  'synthetic-conflict-owner'
);

CREATE TEMP TABLE conflict_other_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-conflict.supabase.co/auth/v1',
  'synthetic-conflict-other'
);

CREATE TEMP TABLE auto_submit AS
SELECT * FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM conflict_owner_context),
  'auto-submit', 1, 'contact.submit.v1', 'device-a',
  'auto-contact', 0,
  jsonb_build_object(
    'contactId', 'auto-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM conflict_owner_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE auto_device_a AS
SELECT * FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM conflict_owner_context),
  'auto-device-a', 1, 'contact.revise.v1', 'device-a',
  'auto-contact', 1,
  jsonb_build_object(
    'contactId', 'auto-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Device A corrected reach',
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 2,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE auto_device_b AS
SELECT * FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM conflict_owner_context),
  'auto-device-b', 1, 'contact.revise.v1', 'device-b',
  'auto-contact', 1,
  jsonb_build_object(
    'contactId', 'auto-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Device B corrected interest',
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 4,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE same_submit AS
SELECT * FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM conflict_owner_context),
  'same-submit', 1, 'contact.submit.v1', 'device-a',
  'same-contact', 0,
  jsonb_build_object(
    'contactId', 'same-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM conflict_owner_context),
    'occurredAtUtc', '2030-01-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE same_device_a AS
SELECT * FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM conflict_owner_context),
  'same-device-a', 1, 'contact.revise.v1', 'device-a',
  'same-contact', 1,
  jsonb_build_object(
    'contactId', 'same-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Device A corrected reach',
    'occurredAtUtc', '2030-01-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 2,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE same_device_b AS
SELECT * FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM conflict_owner_context),
  'same-device-b', 1, 'contact.revise.v1', 'device-b',
  'same-contact', 1,
  jsonb_build_object(
    'contactId', 'same-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Device B corrected reach',
    'occurredAtUtc', '2030-01-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 3,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE same_conflict AS
SELECT * FROM app_data.read_contact_revision_conflict(
  (SELECT app_user_id FROM conflict_owner_context),
  (SELECT workspace_id FROM conflict_owner_context),
  (SELECT project_id FROM conflict_owner_context),
  'same-device-b'
);

CREATE TEMP TABLE same_conflict_replay AS
SELECT * FROM app_data.apply_contact_revise(
  (SELECT app_user_id FROM conflict_owner_context),
  'same-device-b', 1, 'contact.revise.v1', 'device-b',
  'same-contact', 1,
  jsonb_build_object(
    'contactId', 'same-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Replay',
    'occurredAtUtc', '2030-01-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 9,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE same_resolution AS
SELECT * FROM app_data.apply_contact_conflict_resolution(
  (SELECT app_user_id FROM conflict_owner_context),
  'same-resolution', 1, 'contact.resolve.v1', 'device-b',
  'same-contact', 2,
  jsonb_build_object(
    'conflictId', (SELECT conflict_payload->>'conflictId' FROM same_conflict),
    'contactId', 'same-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Resolve with the device B value',
    'occurredAtUtc', '2030-01-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 3,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE same_resolution_replay AS
SELECT * FROM app_data.apply_contact_conflict_resolution(
  (SELECT app_user_id FROM conflict_owner_context),
  'same-resolution', 1, 'contact.resolve.v1', 'device-b',
  'same-contact', 2,
  jsonb_build_object(
    'conflictId', (SELECT conflict_payload->>'conflictId' FROM same_conflict),
    'contactId', 'same-contact',
    'workspaceId', (SELECT workspace_id FROM conflict_owner_context),
    'projectId', (SELECT project_id FROM conflict_owner_context),
    'reason', 'Replay',
    'occurredAtUtc', '2030-01-09T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 4,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE forbidden_conflict_read AS
SELECT * FROM app_data.read_contact_revision_conflict(
  (SELECT app_user_id FROM conflict_other_context),
  (SELECT workspace_id FROM conflict_other_context),
  (SELECT project_id FROM conflict_other_context),
  'same-device-b'
);

DO $runtime_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auto_device_b WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM same_device_b
    WHERE result_code = 'conflict'
      AND failure_code = 'contact_revision_conflict'
  ) OR NOT EXISTS (
    SELECT 1 FROM same_conflict
    WHERE conflict_payload->'conflictingFields' = '["reachCount"]'::jsonb
      AND conflict_payload->'currentSnapshot'->>'reachCount' = '2'
      AND conflict_payload->'proposedSnapshot'->>'reachCount' = '3'
      AND NOT conflict_payload ? 'appUserId'
  ) THEN
    RAISE EXCEPTION 'cross-device merge or conflict contract failed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM same_conflict_replay
    WHERE result_code = 'conflict'
  ) OR NOT EXISTS (
    SELECT 1
    FROM same_resolution_replay AS replay_row
    JOIN same_resolution AS accepted_row USING (server_cursor)
    WHERE replay_row.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'conflict or resolution replay was not idempotent';
  END IF;

  IF EXISTS (SELECT 1 FROM forbidden_conflict_read) THEN
    RAISE EXCEPTION 'conflict detail crossed its trusted scope';
  END IF;

  BEGIN
    PERFORM 1 FROM app_data.contact_revision_conflicts;
    RAISE EXCEPTION 'runtime role read conflict storage directly';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END
$runtime_check$;

RESET ROLE;

DO $owner_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id = 'auto-contact'
      AND current_revision = 3
      AND reach_count = 2
      AND interest_level = 4
  ) OR (
    SELECT count(*) FROM app_data.contact_revisions
    WHERE contact_id = 'auto-contact'
  ) <> 3 THEN
    RAISE EXCEPTION 'different-field edits did not append an automatic merge';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id = 'same-contact'
      AND current_revision = 3
      AND reach_count = 3
  ) OR (
    SELECT count(*) FROM app_data.contact_revisions
    WHERE contact_id = 'same-contact'
  ) <> 3 OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_revision_conflicts
    WHERE command_id = 'same-device-b'
      AND status = 'resolved'
      AND resolution_command_id = 'same-resolution'
      AND resolution_revision = 3
  ) THEN
    RAISE EXCEPTION 'explicit resolution did not preserve and append history';
  END IF;
END
$owner_check$;

ROLLBACK;
