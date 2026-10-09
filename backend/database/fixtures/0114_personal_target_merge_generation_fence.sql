\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0114_owner AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0114-merge.example.test', 'owner'
);
CREATE TEMP TABLE fixture_0114_other AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0114-merge.example.test', 'other-owner'
);
GRANT SELECT ON fixture_0114_owner, fixture_0114_other TO tongxingzhe_runtime;

CREATE FUNCTION pg_temp.fixture_0114_links(
  first_id uuid, second_id uuid, include_second boolean,
  first_enters_project boolean, second_enters_project boolean, spoof_id uuid
) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_array(
    jsonb_build_object(
      'targetId', first_id, 'targetType', 'person', 'responseLevel', 2,
      'followUpConsent', 'yes',
      'institutionRepresentativeConfirmed', false,
      'confirmStageZero', first_enters_project,
      'mergeGenerationId', spoof_id
    )
  ) || CASE WHEN include_second THEN jsonb_build_array(jsonb_build_object(
    'targetId', second_id, 'targetType', 'person', 'responseLevel', 1,
    'followUpConsent', 'unknown',
    'institutionRepresentativeConfirmed', false,
    'confirmStageZero', second_enters_project,
    'mergeGenerationId', spoof_id
  )) ELSE '[]'::jsonb END
$function$;

CREATE FUNCTION pg_temp.fixture_0114_contact_payload(
  contact_id text, workspace_id uuid, project_id uuid,
  questionnaire_version_id uuid, target_links jsonb,
  reason_value text, reach_count_value integer
) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'contactId', contact_id,
    'workspaceId', workspace_id,
    'projectId', project_id,
    'questionnaireVersionId', questionnaire_version_id,
    'reason', reason_value,
    'occurredAtUtc', '2030-03-01T12:00:00Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', reach_count_value,
    'interestLevel', 2,
    'answers', '[]'::jsonb,
    'targetLinks', target_links
  )
$function$;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0114_target_a AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner),
  'person', '0114 merge target A', '+1 312 555 0114', 'same@example.test',
  '0114-target-a'
);
CREATE TEMP TABLE fixture_0114_target_b AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner),
  'person', '0114 merge target B', '+1 312 555 0114', 'same@example.test',
  '0114-target-b'
);
CREATE TEMP TABLE fixture_0114_target_c AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner),
  'person', '0114 incomplete target', NULL, NULL, '0114-target-c'
);
CREATE TEMP TABLE fixture_0114_target_d AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner),
  'person', '0114 cross-workspace target', NULL, NULL, '0114-target-d'
);
GRANT SELECT ON fixture_0114_target_a, fixture_0114_target_b,
  fixture_0114_target_c, fixture_0114_target_d TO tongxingzhe_runtime;

CREATE TEMP TABLE fixture_0114_no_active_submit AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-no-active-submit',
  1, 'contact.submit.v1', '0114-device-a', '0114-no-active-contact', 0,
  pg_temp.fixture_0114_contact_payload(
    '0114-no-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      false, true, false, '00000000-0114-4000-8000-000000000099'
    ), 'submit', 1
  )
);

CREATE TEMP TABLE fixture_0114_no_active_revision AS
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-no-active-revise',
  1, 'contact.revise.v1', '0114-device-a', '0114-no-active-contact', 1,
  pg_temp.fixture_0114_contact_payload(
    '0114-no-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      false, false, false, NULL
    ), 'accepted revision', 2
  )
);

CREATE TEMP TABLE fixture_0114_no_active_conflict AS
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-no-active-conflict',
  1, 'contact.revise.v1', '0114-device-b', '0114-no-active-contact', 1,
  pg_temp.fixture_0114_contact_payload(
    '0114-no-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      false, false, false, NULL
    ), 'conflicting revision', 3
  )
);

CREATE TEMP TABLE fixture_0114_no_active_conflict_read AS
SELECT * FROM app_data.read_contact_revision_conflict(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner), '0114-no-active-conflict'
);
CREATE TEMP TABLE fixture_0114_no_active_resolution AS
SELECT * FROM app_data.apply_contact_conflict_resolution_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-no-active-resolve',
  1, 'contact.resolve.v1', '0114-device-b', '0114-no-active-contact', 2,
  pg_temp.fixture_0114_contact_payload(
    '0114-no-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      false, false, false, NULL
    ), 'resolve conflict', 3
  ) || jsonb_build_object(
    'conflictId', (SELECT conflict_payload->>'conflictId'
                  FROM fixture_0114_no_active_conflict_read)
  )
);
CREATE TEMP TABLE fixture_0114_no_active_void AS
SELECT * FROM app_data.apply_contact_void_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-no-active-void',
  1, 'contact.void.v1', '0114-device-a', '0114-no-active-contact', 3,
  jsonb_build_object(
    'contactId', '0114-no-active-contact',
    'workspaceId', (SELECT workspace_id FROM fixture_0114_owner),
    'projectId', (SELECT project_id FROM fixture_0114_owner),
    'reason', 'synthetic void'
  )
);
CREATE TEMP TABLE fixture_0114_no_active_relationship_update AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner),
  (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
  1, 1, 'active', NULL, 'progress_update', NULL,
  '0114-no-active-relationship-update', NULL
);
RESET ROLE;

DO $no_active$
DECLARE
  first_target uuid := (SELECT (target->>'target_id')::uuid
                        FROM fixture_0114_target_a);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0114_no_active_submit
      WHERE result_code = 'accepted' AND server_cursor IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_no_active_revision
      WHERE result_code = 'accepted' AND server_cursor IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_no_active_conflict
      WHERE result_code = 'conflict'
        AND failure_code = 'contact_revision_conflict')
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_no_active_resolution
      WHERE result_code = 'accepted' AND server_cursor IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_no_active_void
      WHERE result_code = 'accepted' AND server_cursor IS NOT NULL)
    OR (SELECT result->>'status'
        FROM fixture_0114_no_active_relationship_update) <> 'accepted'
    OR (SELECT current_revision FROM app_data.contacts
        WHERE contact_id = '0114-no-active-contact') <> 4
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '0114-no-active-contact') <> 4
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links
        WHERE contact_id = '0114-no-active-contact'
          AND merge_generation_id IS NOT NULL)
    OR (SELECT count(*) FROM app_data.promotion_target_project_relationships
        WHERE promotion_target_id = first_target) <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id = first_target) <> 2
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships
        WHERE promotion_target_id = first_target
          AND merge_generation_id IS NOT NULL)
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id = first_target
          AND merge_generation_id IS NOT NULL)
  THEN
    RAISE EXCEPTION 'no-active contact or relationship behavior changed';
  END IF;
END
$no_active$;

CREATE TEMP TABLE fixture_0114_generation AS
SELECT '00000000-0114-4000-8000-000000000101'::uuid AS generation_id;
INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id, workspace_id, target_type, created_by_app_user_id,
  activated_at_utc
) VALUES (
  (SELECT generation_id FROM fixture_0114_generation),
  (SELECT workspace_id FROM fixture_0114_owner), 'person',
  (SELECT app_user_id FROM fixture_0114_owner), clock_timestamp()
);
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id, workspace_id, target_type, promotion_target_id
) VALUES
  ((SELECT generation_id FROM fixture_0114_generation),
   (SELECT workspace_id FROM fixture_0114_owner), 'person',
   (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a)),
  ((SELECT generation_id FROM fixture_0114_generation),
   (SELECT workspace_id FROM fixture_0114_owner), 'person',
   (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b));
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id, generation_id, workspace_id, target_type
) VALUES
  ((SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
   (SELECT generation_id FROM fixture_0114_generation),
   (SELECT workspace_id FROM fixture_0114_owner), 'person'),
  ((SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
   (SELECT generation_id FROM fixture_0114_generation),
   (SELECT workspace_id FROM fixture_0114_owner), 'person');
GRANT SELECT ON fixture_0114_generation TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0114_active_submit AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-active-submit',
  1, 'contact.submit.v1', '0114-device-a', '0114-active-contact', 0,
  pg_temp.fixture_0114_contact_payload(
    '0114-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      true, false, true, '00000000-0114-4000-8000-000000000099'
    ), 'submit', 1
  )
);
CREATE TEMP TABLE fixture_0114_active_revision AS
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-active-revise',
  1, 'contact.revise.v1', '0114-device-a', '0114-active-contact', 1,
  pg_temp.fixture_0114_contact_payload(
    '0114-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      true, false, true, NULL
    ), 'accepted revision', 2
  )
);
CREATE TEMP TABLE fixture_0114_active_conflict AS
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-active-conflict',
  1, 'contact.revise.v1', '0114-device-b', '0114-active-contact', 1,
  pg_temp.fixture_0114_contact_payload(
    '0114-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      true, false, true, NULL
    ), 'conflicting revision', 3
  )
);
CREATE TEMP TABLE fixture_0114_active_conflict_read AS
SELECT * FROM app_data.read_contact_revision_conflict(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner), '0114-active-conflict'
);
CREATE TEMP TABLE fixture_0114_active_resolution AS
SELECT * FROM app_data.apply_contact_conflict_resolution_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-active-resolve',
  1, 'contact.resolve.v1', '0114-device-b', '0114-active-contact', 2,
  pg_temp.fixture_0114_contact_payload(
    '0114-active-contact',
    (SELECT workspace_id FROM fixture_0114_owner),
    (SELECT project_id FROM fixture_0114_owner),
    (SELECT questionnaire_version_id FROM fixture_0114_owner),
    pg_temp.fixture_0114_links(
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
      (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b),
      true, false, true, NULL
    ), 'resolve conflict', 3
  ) || jsonb_build_object(
    'conflictId', (SELECT conflict_payload->>'conflictId'
                  FROM fixture_0114_active_conflict_read)
  )
);
CREATE TEMP TABLE fixture_0114_active_void AS
SELECT * FROM app_data.apply_contact_void_v3(
  (SELECT app_user_id FROM fixture_0114_owner), '0114-active-void',
  1, 'contact.void.v1', '0114-device-a', '0114-active-contact', 3,
  jsonb_build_object(
    'contactId', '0114-active-contact',
    'workspaceId', (SELECT workspace_id FROM fixture_0114_owner),
    'projectId', (SELECT project_id FROM fixture_0114_owner),
    'reason', 'synthetic void'
  )
);
CREATE TEMP TABLE fixture_0114_active_relationship_update AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM fixture_0114_owner),
  (SELECT workspace_id FROM fixture_0114_owner),
  (SELECT project_id FROM fixture_0114_owner),
  (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a),
  2, 2, 'active', NULL, 'progress_update', NULL,
  '0114-active-relationship-update', NULL
);
RESET ROLE;

DO $active_facts$
DECLARE
  generation uuid := (SELECT generation_id FROM fixture_0114_generation);
  target_a uuid := (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a);
  target_b uuid := (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_b);
BEGIN
  IF (SELECT count(*) FROM app_private.personal_target_merge_generations_v1
      WHERE generation_id = generation AND workspace_id =
        (SELECT workspace_id FROM fixture_0114_owner)
        AND target_type = 'person') <> 1
    OR (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1
        WHERE generation_id = generation) <> 2
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1
        WHERE generation_id = generation) <> 2
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_active_submit
        WHERE result_code = 'accepted')
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_active_revision
        WHERE result_code = 'accepted')
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_active_conflict
        WHERE result_code = 'conflict')
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_active_resolution
        WHERE result_code = 'accepted')
    OR NOT EXISTS (SELECT 1 FROM fixture_0114_active_void
        WHERE result_code = 'accepted')
    OR (SELECT result->>'status' FROM fixture_0114_active_relationship_update)
      <> 'accepted'
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '0114-active-contact') <> 8
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links
        WHERE contact_id = '0114-active-contact'
          AND merge_generation_id IS DISTINCT FROM generation)
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links
        WHERE contact_id = '0114-active-contact'
          AND promotion_target_id NOT IN (target_a, target_b))
    OR (SELECT count(*) FROM app_data.promotion_target_project_relationships
        WHERE promotion_target_id = target_b
          AND merge_generation_id = generation) <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id = target_b
          AND merge_generation_id = generation) <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_project_relationships
        WHERE promotion_target_id = target_a
          AND merge_generation_id IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id = target_a
          AND merge_generation_id IS NULL) <> 2
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id = target_a
          AND merge_generation_id = generation) <> 1
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '0114-no-active-contact'
          AND promotion_target_id = target_a
          AND merge_generation_id IS NULL) <> 4
  THEN
    RAISE EXCEPTION 'active generation binding or pre-generation history drifted';
  END IF;
END
$active_facts$;

DO $immutability$
DECLARE
  generation uuid := (SELECT generation_id FROM fixture_0114_generation);
  target_a uuid := (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_a);
  failed boolean;
BEGIN
  failed := false;
  BEGIN
    UPDATE app_private.personal_target_merge_generations_v1
    SET activated_at_utc = activated_at_utc + interval '1 second'
    WHERE generation_id = generation;
  EXCEPTION WHEN SQLSTATE '55000' THEN failed := true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'generation update was accepted'; END IF;

  failed := false;
  BEGIN
    DELETE FROM app_private.personal_target_merge_generation_members_v1
    WHERE generation_id = generation AND promotion_target_id = target_a;
  EXCEPTION WHEN SQLSTATE '55000' THEN failed := true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'generation member delete was accepted'; END IF;

  failed := false;
  BEGIN
    UPDATE app_data.contact_target_links
    SET merge_generation_id = NULL
    WHERE contact_id = '0114-active-contact' AND revision_number = 1
      AND promotion_target_id = target_a;
  EXCEPTION WHEN SQLSTATE '42501' THEN failed := true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'fact binding update was accepted'; END IF;
END
$immutability$;

-- Deliberately malformed private fixtures prove that incomplete and
-- cross-workspace maps fail closed inside the fact writer transaction.
RESET ROLE;
INSERT INTO app_private.personal_target_merge_generations_v1 (
  generation_id, workspace_id, target_type, created_by_app_user_id,
  activated_at_utc
) VALUES
  ('00000000-0114-4000-8000-000000000201',
   (SELECT workspace_id FROM fixture_0114_owner), 'person',
   (SELECT app_user_id FROM fixture_0114_owner), clock_timestamp()),
  ('00000000-0114-4000-8000-000000000202',
   (SELECT workspace_id FROM fixture_0114_other), 'person',
   (SELECT app_user_id FROM fixture_0114_other), clock_timestamp());
INSERT INTO app_private.personal_target_merge_generation_members_v1 (
  generation_id, workspace_id, target_type, promotion_target_id
) VALUES
  ('00000000-0114-4000-8000-000000000201',
   (SELECT workspace_id FROM fixture_0114_owner), 'person',
   (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_c)),
  ('00000000-0114-4000-8000-000000000202',
   (SELECT workspace_id FROM fixture_0114_other), 'person',
   (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_d));
INSERT INTO app_private.personal_target_merge_active_members_v1 (
  promotion_target_id, generation_id, workspace_id, target_type
) VALUES
  ((SELECT (target->>'target_id')::uuid FROM fixture_0114_target_c),
   '00000000-0114-4000-8000-000000000201',
   (SELECT workspace_id FROM fixture_0114_owner), 'person'),
  ((SELECT (target->>'target_id')::uuid FROM fixture_0114_target_d),
   '00000000-0114-4000-8000-000000000202',
   (SELECT workspace_id FROM fixture_0114_other), 'person');

SET LOCAL ROLE tongxingzhe_runtime;
DO $fail_closed$
DECLARE
  failed boolean;
  owner_id uuid := (SELECT app_user_id FROM fixture_0114_owner);
  owner_workspace uuid := (SELECT workspace_id FROM fixture_0114_owner);
  owner_project uuid := (SELECT project_id FROM fixture_0114_owner);
  questionnaire_id uuid := (SELECT questionnaire_version_id FROM fixture_0114_owner);
  target_c uuid := (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_c);
  target_d uuid := (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_d);
BEGIN
  failed := false;
  BEGIN
    PERFORM * FROM app_data.apply_contact_submit_v3(
      owner_id, '0114-incomplete-command', 1, 'contact.submit.v1',
      '0114-device-a', '0114-incomplete-contact', 0,
      pg_temp.fixture_0114_contact_payload(
        '0114-incomplete-contact', owner_workspace, owner_project,
        questionnaire_id,
        jsonb_build_array(jsonb_build_object(
          'targetId', target_c, 'targetType', 'person', 'responseLevel', 1,
          'followUpConsent', 'yes',
          'institutionRepresentativeConfirmed', false,
          'confirmStageZero', true
        )), 'incomplete generation', 1
      )
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN failed := true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'incomplete generation writer did not fail'; END IF;

  failed := false;
  BEGIN
    PERFORM * FROM app_data.apply_contact_submit_v3(
      owner_id, '0114-cross-workspace-command', 1, 'contact.submit.v1',
      '0114-device-a', '0114-cross-workspace-contact', 0,
      pg_temp.fixture_0114_contact_payload(
        '0114-cross-workspace-contact', owner_workspace, owner_project,
        questionnaire_id,
        jsonb_build_array(jsonb_build_object(
          'targetId', target_d, 'targetType', 'person', 'responseLevel', 1,
          'followUpConsent', 'yes',
          'institutionRepresentativeConfirmed', false,
          'confirmStageZero', true
        )), 'cross-workspace generation', 1
      )
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN failed := true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'cross-workspace generation writer did not fail'; END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.contact_target_links (
      contact_id, revision_number, promotion_target_id, response_level,
      follow_up_consent, institution_representative_confirmed,
      confirmed_project_entry, merge_generation_id
    ) VALUES (
      '0114-active-contact', 1, target_d, 1, 'yes', false, true,
      '00000000-0114-4000-8000-000000000202'
    );
  EXCEPTION WHEN insufficient_privilege THEN failed := true;
  END;
  IF NOT failed THEN RAISE EXCEPTION 'runtime inserted a caller-chosen binding'; END IF;
END
$fail_closed$;
RESET ROLE;

DO $no_partial$
BEGIN
  IF EXISTS (SELECT 1 FROM app_data.contacts
      WHERE contact_id IN ('0114-incomplete-contact',
                           '0114-cross-workspace-contact'))
    OR EXISTS (SELECT 1 FROM app_data.contact_revisions
      WHERE contact_id IN ('0114-incomplete-contact',
                           '0114-cross-workspace-contact'))
    OR EXISTS (SELECT 1 FROM app_data.processed_commands
      WHERE command_id IN ('0114-incomplete-command',
                           '0114-cross-workspace-command'))
    OR EXISTS (SELECT 1 FROM app_data.change_feed
      WHERE aggregate_id IN ('0114-incomplete-contact',
                             '0114-cross-workspace-contact'))
    OR EXISTS (SELECT 1 FROM app_data.contact_audit_events
      WHERE contact_id IN ('0114-incomplete-contact',
                           '0114-cross-workspace-contact'))
    OR EXISTS (SELECT 1 FROM app_data.warehouse_outbox
      WHERE contact_id IN ('0114-incomplete-contact',
                           '0114-cross-workspace-contact'))
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links
      WHERE contact_id IN ('0114-incomplete-contact',
                           '0114-cross-workspace-contact'))
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id IN (
        (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_c),
        (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_d)
      ))
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions
      WHERE promotion_target_id IN (
        (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_c),
        (SELECT (target->>'target_id')::uuid FROM fixture_0114_target_d)
      ))
  THEN
    RAISE EXCEPTION 'failed generation writer left partial facts';
  END IF;
END
$no_partial$;

ROLLBACK;
