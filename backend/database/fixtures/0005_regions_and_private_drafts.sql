-- synthetic fixture：证明区域树约束、私有草稿并发和用户隔离真实成立。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE draft_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-draft.supabase.co/auth/v1',
  'synthetic-draft-owner'
);

CREATE TEMP TABLE other_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-draft.supabase.co/auth/v1',
  'synthetic-other-owner'
);

CREATE TEMP TABLE draft_owner_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-draft.supabase.co/auth/v1',
  'synthetic-draft-owner',
  'Synthetic second project'
);

RESET ROLE;

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  ('us', 'synthetic-v1', NULL, 'United States', 'country'),
  ('illinois', 'synthetic-v1', 'us', 'Illinois', 'admin_area'),
  ('chicago', 'synthetic-v1', 'illinois', 'Chicago', 'city'),
  ('uchicago', 'synthetic-v1', 'chicago', 'University of Chicago', 'institution');

DO $region_check$
BEGIN
  BEGIN
    UPDATE app_data.canonical_region_versions
    SET parent_region_id = 'uchicago'
    WHERE region_id = 'illinois'
      AND tree_version = 'synthetic-v1';
    RAISE EXCEPTION 'multi-node region cycle was accepted';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;
END
$region_check$;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE first_upsert AS
SELECT *
FROM app_data.apply_draft_upsert(
  (SELECT app_user_id FROM draft_owner_context),
  'synthetic-draft-upsert-1',
  1,
  'draft.upsert.v1',
  'synthetic-device-a',
  'synthetic-draft-1',
  0,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM draft_owner_context),
    'projectId', (SELECT project_id FROM draft_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM draft_owner_context),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:30:00.000Z',
    'occurredAtUtc', NULL,
    'occurredTimeZone', NULL,
    'channel', NULL,
    'channelDetail', NULL,
    'location', NULL,
    'reachCount', NULL,
    'interestLevel', NULL,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE duplicate_upsert AS
SELECT *
FROM app_data.apply_draft_upsert(
  (SELECT app_user_id FROM draft_owner_context),
  'synthetic-draft-upsert-1', 1, 'draft.upsert.v1',
  'synthetic-device-a', 'synthetic-draft-1', 0,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM draft_owner_context),
    'projectId', (SELECT project_id FROM draft_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM draft_owner_context),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:30:00.000Z',
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE stale_upsert AS
SELECT *
FROM app_data.apply_draft_upsert(
  (SELECT app_user_id FROM draft_owner_context),
  'synthetic-draft-upsert-stale', 1, 'draft.upsert.v1',
  'synthetic-device-b', 'synthetic-draft-1', 0,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM draft_owner_context),
    'projectId', (SELECT project_id FROM draft_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM draft_owner_context),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:40:00.000Z',
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE cross_project_upsert AS
SELECT *
FROM app_data.apply_draft_upsert(
  (SELECT app_user_id FROM draft_owner_context),
  'synthetic-draft-cross-project-upsert', 1, 'draft.upsert.v1',
  'synthetic-device-b', 'synthetic-draft-1', 1,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM draft_owner_other_project),
    'projectId', (SELECT project_id FROM draft_owner_other_project),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM draft_owner_other_project),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:50:00.000Z',
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE cross_project_delete AS
SELECT *
FROM app_data.apply_draft_delete(
  (SELECT app_user_id FROM draft_owner_context),
  'synthetic-draft-cross-project-delete', 1, 'draft.delete.v1',
  'synthetic-device-b', 'synthetic-draft-1', 1,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM draft_owner_other_project),
    'projectId', (SELECT project_id FROM draft_owner_other_project)
  )
);

CREATE TEMP TABLE owner_pull AS
SELECT *
FROM app_data.pull_sync_changes(
  (SELECT app_user_id FROM draft_owner_context),
  (SELECT workspace_id FROM draft_owner_context),
  (SELECT project_id FROM draft_owner_context),
  NULL,
  100
);

CREATE TEMP TABLE other_same_id_upsert AS
SELECT *
FROM app_data.apply_draft_upsert(
  (SELECT app_user_id FROM other_owner_context),
  'synthetic-other-draft-upsert', 1, 'draft.upsert.v1',
  'synthetic-device-c', 'synthetic-draft-1', 0,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM other_owner_context),
    'projectId', (SELECT project_id FROM other_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM other_owner_context),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:45:00.000Z',
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE delete_result AS
SELECT *
FROM app_data.apply_draft_delete(
  (SELECT app_user_id FROM draft_owner_context),
  'synthetic-draft-delete-1', 1, 'draft.delete.v1',
  'synthetic-device-a', 'synthetic-draft-1', 1,
  jsonb_build_object(
    'draftId', 'synthetic-draft-1',
    'workspaceId', (SELECT workspace_id FROM draft_owner_context),
    'projectId', (SELECT project_id FROM draft_owner_context)
  )
);

CREATE TEMP TABLE owner_pull_after_delete AS
SELECT *
FROM app_data.pull_sync_changes(
  (SELECT app_user_id FROM draft_owner_context),
  (SELECT workspace_id FROM draft_owner_context),
  (SELECT project_id FROM draft_owner_context),
  (SELECT server_cursor FROM owner_pull ORDER BY server_cursor LIMIT 1),
  100
);

DO $runtime_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM first_upsert
    WHERE result_code = 'accepted' AND server_cursor IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'first draft upsert was not accepted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM duplicate_upsert AS duplicate_row
    JOIN first_upsert AS first_row USING (server_cursor)
    WHERE duplicate_row.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'draft command replay was not idempotent';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM stale_upsert
    WHERE result_code = 'conflict'
      AND failure_code = 'draft_revision_conflict'
  ) THEN
    RAISE EXCEPTION 'stale draft update did not conflict';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM cross_project_upsert
    WHERE result_code = 'conflict'
      AND failure_code = 'draft_scope_conflict'
  ) OR NOT EXISTS (
    SELECT 1 FROM cross_project_delete
    WHERE result_code = 'conflict'
      AND failure_code = 'draft_scope_conflict'
  ) THEN
    RAISE EXCEPTION 'an existing draft crossed its fixed project scope';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM owner_pull
    WHERE change_type = 'draft.upserted'
      AND revision_number = 1
      AND typed_payload->>'draftId' = 'synthetic-draft-1'
      AND NOT (typed_payload ? 'appUserId')
  ) THEN
    RAISE EXCEPTION 'private draft pull omitted or exposed identity';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM other_same_id_upsert WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'two users could not independently use the same draft ID';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM delete_result WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'draft delete was not accepted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM owner_pull_after_delete
    WHERE change_type = 'draft.deleted'
      AND revision_number = 2
      AND typed_payload->>'draftId' = 'synthetic-draft-1'
  ) THEN
    RAISE EXCEPTION 'draft delete was not returned after the pull cursor';
  END IF;
  BEGIN
    PERFORM 1 FROM app_data.contact_drafts;
    RAISE EXCEPTION 'runtime role read private draft table directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$runtime_check$;

RESET ROLE;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  channel, location_kind, place_name, smallest_region_id,
  reach_count, interest_level
) VALUES (
  'synthetic-region-revision-contact',
  (SELECT app_user_id FROM draft_owner_context),
  (SELECT workspace_id FROM draft_owner_context),
  (SELECT project_id FROM draft_owner_context),
  (SELECT questionnaire_version_id FROM draft_owner_context),
  '2030-01-08T18:00:00.000Z',
  'America/Chicago',
  'face_to_face',
  'resolved',
  'University of Chicago',
  'uchicago',
  1,
  2
);

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revised_by_app_user_id, snapshot
) VALUES (
  'synthetic-region-revision-contact',
  1,
  (SELECT app_user_id FROM draft_owner_context),
  jsonb_build_object(
    'location', jsonb_build_object(
      'kind', 'resolved',
      'smallestRegionId', 'uchicago',
      'regionTreeVersion', 'synthetic-v1'
    )
  )
);

UPDATE app_data.contacts
SET location_kind = 'pending_resolution',
    place_name = NULL,
    smallest_region_id = NULL,
    latitude = 41.7897,
    longitude = -87.5997,
    current_revision = 2
WHERE contact_id = 'synthetic-region-revision-contact';

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id,
  reason, snapshot
) VALUES (
  'synthetic-region-revision-contact',
  2,
  'corrected',
  (SELECT app_user_id FROM draft_owner_context),
  'Synthetic location correction',
  jsonb_build_object(
    'location', jsonb_build_object(
      'kind', 'pending_resolution',
      'latitude', 41.7897,
      'longitude', -87.5997
    )
  )
);

DO $owner_check$
BEGIN
  IF (
    SELECT count(*)
    FROM app_data.contact_drafts
    WHERE draft_id = 'synthetic-draft-1'
  ) <> 2 THEN
    RAISE EXCEPTION 'private draft rows were not isolated by app user';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.contact_drafts
    WHERE draft_id = 'synthetic-draft-1'
      AND app_user_id = (SELECT app_user_id FROM draft_owner_context)
      AND current_revision = 2
      AND deleted_at_utc IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'deleted draft tombstone did not retain its revision';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_data.warehouse_outbox
    WHERE contact_id = 'synthetic-draft-1'
  ) THEN
    RAISE EXCEPTION 'private draft leaked into the analytics outbox';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_data.contact_region_assignments
    WHERE contact_id = 'synthetic-region-revision-contact'
  ) OR EXISTS (
    SELECT 1
    FROM app_data.contacts
    WHERE contact_id = 'synthetic-region-revision-contact'
      AND region_tree_version IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'a non-resolved revision retained a stale region assignment';
  END IF;
END
$owner_check$;

ROLLBACK;
