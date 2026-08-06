\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE upgrade_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://draft-upgrade.example.test',
  'owner'
);

CREATE TEMP TABLE upgrade_other_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://draft-upgrade.example.test',
  'other-owner'
);

RESET ROLE;

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  '44444444-4444-4444-8444-444444444444',
  (SELECT project_id FROM upgrade_owner_context),
  2,
  'published',
  false
);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE upgrade_source_result AS
SELECT *
FROM app_data.apply_draft_upsert_v2(
  (SELECT app_user_id FROM upgrade_owner_context),
  'upgrade-source-command', 1, 'draft.upsert.v1',
  'device-a', 'upgrade-source-draft', 0,
  jsonb_build_object(
    'draftId', 'upgrade-source-draft',
    'workspaceId', (SELECT workspace_id FROM upgrade_owner_context),
    'projectId', (SELECT project_id FROM upgrade_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM upgrade_owner_context),
    'upgradedFromDraftId', NULL,
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:15:00.000Z',
    'occurredAtUtc', NULL,
    'occurredTimeZone', NULL,
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', NULL,
    'reachCount', NULL,
    'interestLevel', NULL,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE upgrade_target_result AS
SELECT *
FROM app_data.apply_draft_upsert_v2(
  (SELECT app_user_id FROM upgrade_owner_context),
  'upgrade-target-command', 1, 'draft.upsert.v1',
  'device-a', 'upgrade-target-draft', 0,
  jsonb_build_object(
    'draftId', 'upgrade-target-draft',
    'workspaceId', (SELECT workspace_id FROM upgrade_owner_context),
    'projectId', (SELECT project_id FROM upgrade_owner_context),
    'questionnaireVersionId', '44444444-4444-4444-8444-444444444444',
    'upgradedFromDraftId', 'upgrade-source-draft',
    'createdAtUtc', '2030-01-08T18:20:00.000Z',
    'updatedAtUtc', '2030-01-08T18:20:00.000Z',
    'occurredAtUtc', NULL,
    'occurredTimeZone', NULL,
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', NULL,
    'reachCount', NULL,
    'interestLevel', NULL,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE upgrade_target_duplicate AS
SELECT *
FROM app_data.apply_draft_upsert_v2(
  (SELECT app_user_id FROM upgrade_owner_context),
  'upgrade-target-command', 1, 'draft.upsert.v1',
  'device-a', 'upgrade-target-draft', 0,
  jsonb_build_object(
    'draftId', 'upgrade-target-draft',
    'workspaceId', (SELECT workspace_id FROM upgrade_owner_context),
    'projectId', (SELECT project_id FROM upgrade_owner_context),
    'questionnaireVersionId', '44444444-4444-4444-8444-444444444444',
    'upgradedFromDraftId', 'upgrade-source-draft',
    'createdAtUtc', '2030-01-08T18:20:00.000Z',
    'updatedAtUtc', '2030-01-08T18:20:00.000Z',
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE upgrade_owner_pull AS
SELECT *
FROM app_data.pull_sync_changes(
  (SELECT app_user_id FROM upgrade_owner_context),
  (SELECT workspace_id FROM upgrade_owner_context),
  (SELECT project_id FROM upgrade_owner_context),
  NULL,
  100
);

CREATE TEMP TABLE upgrade_source_delete AS
SELECT *
FROM app_data.apply_draft_delete(
  (SELECT app_user_id FROM upgrade_owner_context),
  'upgrade-source-delete', 1, 'draft.delete.v1',
  'device-a', 'upgrade-source-draft', 1,
  jsonb_build_object(
    'draftId', 'upgrade-source-draft',
    'workspaceId', (SELECT workspace_id FROM upgrade_owner_context),
    'projectId', (SELECT project_id FROM upgrade_owner_context)
  )
);

DO $runtime_checks$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM upgrade_source_result WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM upgrade_target_result WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'source and upgraded drafts were not accepted';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM upgrade_target_duplicate AS duplicate_row
    JOIN upgrade_target_result AS first_row USING (server_cursor)
    WHERE duplicate_row.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'upgraded draft retry was not idempotent';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM upgrade_owner_pull
    WHERE change_type = 'draft.upserted'
      AND typed_payload->>'draftId' = 'upgrade-target-draft'
      AND typed_payload->>'upgradedFromDraftId' = 'upgrade-source-draft'
  ) THEN
    RAISE EXCEPTION 'cross-device feed omitted the upgrade source';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM upgrade_source_delete WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'owner could not explicitly abandon the source draft';
  END IF;

  BEGIN
    PERFORM app_data.apply_draft_upsert_v2(
      (SELECT app_user_id FROM upgrade_owner_context),
      'upgrade-self-command', 1, 'draft.upsert.v1',
      'device-a', 'upgrade-self-draft', 0,
      jsonb_build_object(
        'draftId', 'upgrade-self-draft',
        'workspaceId', (SELECT workspace_id FROM upgrade_owner_context),
        'projectId', (SELECT project_id FROM upgrade_owner_context),
        'questionnaireVersionId', '44444444-4444-4444-8444-444444444444',
        'upgradedFromDraftId', 'upgrade-self-draft',
        'createdAtUtc', '2030-01-08T19:00:00.000Z',
        'updatedAtUtc', '2030-01-08T19:00:00.000Z',
        'answers', jsonb_build_array()
      )
    );
    RAISE EXCEPTION 'self-referential draft upgrade was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.apply_draft_upsert_v2(
      (SELECT app_user_id FROM upgrade_other_context),
      'upgrade-cross-owner-command', 1, 'draft.upsert.v1',
      'device-b', 'upgrade-cross-owner-target', 0,
      jsonb_build_object(
        'draftId', 'upgrade-cross-owner-target',
        'workspaceId', (SELECT workspace_id FROM upgrade_other_context),
        'projectId', (SELECT project_id FROM upgrade_other_context),
        'questionnaireVersionId',
          (SELECT questionnaire_version_id FROM upgrade_other_context),
        'upgradedFromDraftId', 'upgrade-source-draft',
        'createdAtUtc', '2030-01-08T19:00:00.000Z',
        'updatedAtUtc', '2030-01-08T19:00:00.000Z',
        'answers', jsonb_build_array()
      )
    );
    RAISE EXCEPTION 'another owner reused the source draft relation';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.pull_sync_changes(
      (SELECT app_user_id FROM upgrade_other_context),
      (SELECT workspace_id FROM upgrade_owner_context),
      (SELECT project_id FROM upgrade_owner_context),
      NULL,
      100
    );
    RAISE EXCEPTION 'another owner pulled private upgraded drafts';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$runtime_checks$;

RESET ROLE;

DO $stored_checks$
BEGIN
  IF (
    SELECT count(*)
    FROM app_data.contact_drafts
    WHERE app_user_id = (SELECT app_user_id FROM upgrade_owner_context)
      AND draft_id IN ('upgrade-source-draft', 'upgrade-target-draft')
  ) <> 2 THEN
    RAISE EXCEPTION 'upgrade did not preserve two separate draft rows';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.contact_drafts
    WHERE app_user_id = (SELECT app_user_id FROM upgrade_owner_context)
      AND draft_id = 'upgrade-source-draft'
      AND deleted_at_utc IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.contact_drafts
    WHERE app_user_id = (SELECT app_user_id FROM upgrade_owner_context)
      AND draft_id = 'upgrade-target-draft'
      AND deleted_at_utc IS NULL
      AND upgraded_from_draft_id = 'upgrade-source-draft'
  ) THEN
    RAISE EXCEPTION 'explicit source abandonment changed the upgraded draft';
  END IF;
END
$stored_checks$;

ROLLBACK;
