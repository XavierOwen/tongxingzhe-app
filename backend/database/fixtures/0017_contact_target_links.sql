\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE link_owner_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-links.example.test',
  'link-owner'
);

CREATE TEMP TABLE link_intruder_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-links.example.test',
  'link-intruder'
);

CREATE TEMP TABLE link_person_one AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM link_owner_context),
  (SELECT workspace_id FROM link_owner_context),
  (SELECT project_id FROM link_owner_context),
  'person', '合成对象甲', NULL, NULL, 'link-person-one'
);

CREATE TEMP TABLE link_person_two AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM link_owner_context),
  (SELECT workspace_id FROM link_owner_context),
  (SELECT project_id FROM link_owner_context),
  'person', '合成对象乙', NULL, NULL, 'link-person-two'
);

CREATE TEMP TABLE link_institution AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM link_owner_context),
  (SELECT workspace_id FROM link_owner_context),
  (SELECT project_id FROM link_owner_context),
  'institution', '合成机构', NULL, NULL, 'link-institution'
);

CREATE TEMP TABLE link_unconfirmed AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM link_owner_context),
  (SELECT workspace_id FROM link_owner_context),
  (SELECT project_id FROM link_owner_context),
  'person', '未确认对象', NULL, NULL, 'link-unconfirmed'
);

CREATE TEMP TABLE link_intruder_target AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM link_intruder_context),
  (SELECT workspace_id FROM link_intruder_context),
  (SELECT project_id FROM link_intruder_context),
  'person', '其他空间对象', NULL, NULL, 'link-intruder-target'
);

CREATE TEMP TABLE link_submit_payload AS
SELECT jsonb_build_object(
  'contactId', 'contact-target-links',
  'workspaceId', (SELECT workspace_id FROM link_owner_context),
  'projectId', (SELECT project_id FROM link_owner_context),
  'questionnaireVersionId',
    (SELECT questionnaire_version_id FROM link_owner_context),
  'occurredAtUtc', '2030-02-01T18:00:00.000Z',
  'occurredTimeZone', 'America/Chicago',
  'channel', 'video_call',
  'channelDetail', NULL,
  'location', jsonb_build_object('kind', 'not_applicable'),
  'reachCount', 5,
  'interestLevel', 2,
  'answers', '[]'::jsonb,
  'targetLinks', jsonb_build_array(
    jsonb_build_object(
      'targetId', (SELECT target->>'target_id' FROM link_person_one),
      'targetType', 'person',
      'responseLevel', 4,
      'followUpConsent', 'yes',
      'institutionRepresentativeConfirmed', false,
      'confirmStageZero', true
    ),
    jsonb_build_object(
      'targetId', (SELECT target->>'target_id' FROM link_person_two),
      'targetType', 'person',
      'responseLevel', 0,
      'followUpConsent', 'no',
      'institutionRepresentativeConfirmed', false,
      'confirmStageZero', true
    ),
    jsonb_build_object(
      'targetId', (SELECT target->>'target_id' FROM link_institution),
      'targetType', 'institution',
      'responseLevel', 3,
      'followUpConsent', 'unknown',
      'institutionRepresentativeConfirmed', true,
      'confirmStageZero', true
    )
  )
) AS payload;

CREATE TEMP TABLE link_submit_result AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-links-submit', 1, 'contact.submit.v1', 'device-a',
  'contact-target-links', 0,
  (SELECT payload FROM link_submit_payload)
);

CREATE TEMP TABLE link_replay_result AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-links-submit', 1, 'contact.submit.v1', 'device-a',
  'contact-target-links', 0,
  (SELECT payload FROM link_submit_payload)
);

CREATE TEMP TABLE link_unconfirmed_result AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-unconfirmed', 1, 'contact.submit.v1', 'device-a',
  'contact-target-unconfirmed', 0,
  (SELECT payload FROM link_submit_payload)
    || jsonb_build_object(
      'contactId', 'contact-target-unconfirmed',
      'targetLinks', jsonb_build_array(jsonb_build_object(
        'targetId', (SELECT target->>'target_id' FROM link_unconfirmed),
        'targetType', 'person',
        'responseLevel', NULL,
        'followUpConsent', 'unknown',
        'institutionRepresentativeConfirmed', false,
        'confirmStageZero', false
      ))
    )
);

CREATE TEMP TABLE link_cross_workspace_result AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-cross-workspace', 1, 'contact.submit.v1', 'device-a',
  'contact-target-cross-workspace', 0,
  (SELECT payload FROM link_submit_payload)
    || jsonb_build_object(
      'contactId', 'contact-target-cross-workspace',
      'targetLinks', jsonb_build_array(jsonb_build_object(
        'targetId', (SELECT target->>'target_id' FROM link_intruder_target),
        'targetType', 'person',
        'responseLevel', NULL,
        'followUpConsent', 'unknown',
        'institutionRepresentativeConfirmed', false,
        'confirmStageZero', true
      ))
    )
);

CREATE TEMP TABLE link_bad_institution_result AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-bad-institution', 1, 'contact.submit.v1', 'device-a',
  'contact-target-bad-institution', 0,
  (SELECT payload FROM link_submit_payload)
    || jsonb_build_object(
      'contactId', 'contact-target-bad-institution',
      'targetLinks', jsonb_build_array(jsonb_build_object(
        'targetId', (SELECT target->>'target_id' FROM link_institution),
        'targetType', 'institution',
        'responseLevel', 3,
        'followUpConsent', 'unknown',
        'institutionRepresentativeConfirmed', false,
        'confirmStageZero', false
      ))
    )
);

RESET ROLE;

DO $initial_checks$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM link_submit_result WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM link_replay_result AS replay
    JOIN link_submit_result AS original USING (server_cursor)
    WHERE replay.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'contact target submission is not idempotent';
  END IF;

  IF (SELECT reach_count FROM app_data.contacts
      WHERE contact_id = 'contact-target-links') <> 5
    OR (SELECT interest_level FROM app_data.contacts
      WHERE contact_id = 'contact-target-links') <> 2
    OR (SELECT count(*) FROM app_data.contacts
      WHERE contact_id = 'contact-target-links') <> 1
    OR (SELECT count(*) FROM app_data.contact_target_links
      WHERE contact_id = 'contact-target-links'
        AND revision_number = 1) <> 3
    OR (SELECT count(*) FROM app_data.promotion_target_project_relationships
      WHERE project_id = (SELECT project_id FROM link_owner_context)
        AND current_stage = 0) <> 3
  THEN
    RAISE EXCEPTION 'session, reach, interest, links, or stage 0 diverged';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM link_unconfirmed_result
    WHERE result_code = 'rejected'
      AND failure_code = 'target_project_confirmation_required'
  ) OR NOT EXISTS (
    SELECT 1 FROM link_cross_workspace_result
    WHERE result_code = 'rejected' AND failure_code = 'target_forbidden'
  ) OR NOT EXISTS (
    SELECT 1 FROM link_bad_institution_result
    WHERE result_code = 'rejected'
      AND failure_code = 'institution_response_requires_representative'
  ) OR EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id IN (
      'contact-target-unconfirmed',
      'contact-target-cross-workspace',
      'contact-target-bad-institution'
    )
  ) THEN
    RAISE EXCEPTION 'forged target links left partial contact facts';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.list_assigned_promotion_targets(
      (SELECT app_user_id FROM link_owner_context),
      (SELECT workspace_id FROM link_owner_context),
      (SELECT project_id FROM link_owner_context)
    )
    WHERE target->>'target_id' =
      (SELECT target->>'target_id' FROM link_person_one)
      AND (target->>'has_current_project_relationship')::boolean
  ) THEN
    RAISE EXCEPTION 'target directory did not expose project relationship';
  END IF;
END
$initial_checks$;

UPDATE app_data.promotion_target_assignments
SET ended_at = clock_timestamp()
WHERE promotion_target_id = (
    SELECT (target->>'target_id')::uuid FROM link_person_one
  )
  AND app_user_id = (SELECT app_user_id FROM link_owner_context);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE link_replay_after_assignment_ended_result AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-links-submit', 1, 'contact.submit.v1', 'device-a',
  'contact-target-links', 0,
  (SELECT payload FROM link_submit_payload)
);

RESET ROLE;

DO $revoked_assignment_replay_checks$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM link_replay_after_assignment_ended_result AS replay
    JOIN link_submit_result AS original USING (server_cursor)
    WHERE replay.result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'processed command was revalidated after assignment ended';
  END IF;
END
$revoked_assignment_replay_checks$;

UPDATE app_data.promotion_target_assignments
SET ended_at = NULL
WHERE promotion_target_id = (
    SELECT (target->>'target_id')::uuid FROM link_person_one
  )
  AND app_user_id = (SELECT app_user_id FROM link_owner_context);

CREATE TEMP TABLE link_revision_one AS
SELECT snapshot FROM app_data.contact_revisions
WHERE contact_id = 'contact-target-links' AND revision_number = 1;
GRANT SELECT ON link_revision_one TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE link_revise_result AS
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-links-revise', 1, 'contact.revise.v1', 'device-a',
  'contact-target-links', 1,
  (SELECT snapshot FROM link_revision_one)
    || jsonb_build_object(
      'reason', 'remove one link and correct another',
      'targetLinks', jsonb_build_array(
        jsonb_build_object(
          'targetId', (SELECT target->>'target_id' FROM link_person_one),
          'targetType', 'person',
          'responseLevel', 3,
          'followUpConsent', 'yes',
          'institutionRepresentativeConfirmed', false,
          'confirmStageZero', false
        ),
        jsonb_build_object(
          'targetId', (SELECT target->>'target_id' FROM link_institution),
          'targetType', 'institution',
          'responseLevel', 3,
          'followUpConsent', 'unknown',
          'institutionRepresentativeConfirmed', true,
          'confirmStageZero', false
        )
      )
    )
);

CREATE TEMP TABLE link_conflict_result AS
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM link_owner_context),
  'contact-target-links-conflict', 1, 'contact.revise.v1', 'device-b',
  'contact-target-links', 1,
  (SELECT snapshot FROM link_revision_one)
    || jsonb_build_object(
      'reason', 'concurrent target correction',
      'targetLinks', jsonb_build_array(
        jsonb_build_object(
          'targetId', (SELECT target->>'target_id' FROM link_person_one),
          'targetType', 'person',
          'responseLevel', 1,
          'followUpConsent', 'yes',
          'institutionRepresentativeConfirmed', false,
          'confirmStageZero', false
        ),
        jsonb_build_object(
          'targetId', (SELECT target->>'target_id' FROM link_person_two),
          'targetType', 'person',
          'responseLevel', 0,
          'followUpConsent', 'no',
          'institutionRepresentativeConfirmed', false,
          'confirmStageZero', false
        ),
        jsonb_build_object(
          'targetId', (SELECT target->>'target_id' FROM link_institution),
          'targetType', 'institution',
          'responseLevel', 3,
          'followUpConsent', 'unknown',
          'institutionRepresentativeConfirmed', true,
          'confirmStageZero', false
        )
      )
    )
);

RESET ROLE;

DO $revision_checks$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM link_revise_result WHERE result_code = 'accepted'
  ) OR (SELECT count(*) FROM app_data.contact_target_links
    WHERE contact_id = 'contact-target-links' AND revision_number = 1) <> 3
    OR (SELECT count(*) FROM app_data.contact_target_links
    WHERE contact_id = 'contact-target-links' AND revision_number = 2) <> 2
  THEN
    RAISE EXCEPTION 'target link revision did not preserve history';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM link_conflict_result
    WHERE result_code = 'conflict'
      AND failure_code = 'contact_revision_conflict'
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_revision_conflicts
    WHERE command_id = 'contact-target-links-conflict'
      AND conflicting_fields @> ARRAY['targetLinks']::text[]
  ) THEN
    RAISE EXCEPTION 'concurrent target link change was silently overwritten';
  END IF;

  IF EXISTS (
    SELECT 1 FROM app_data.warehouse_outbox
    WHERE contact_id = 'contact-target-links'
      AND analytics_payload::text ~*
        '(合成对象|displayName|phone|email|targetId|target_id)'
  ) THEN
    RAISE EXCEPTION 'target PII entered analytics payload';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.warehouse_outbox
    WHERE contact_id = 'contact-target-links'
      AND (
        jsonb_typeof(analytics_payload->'target_link_facts') <> 'array'
        OR jsonb_array_length(analytics_payload->'target_link_facts') <>
          CASE revision_number WHEN 1 THEN 3 WHEN 2 THEN 2 ELSE 0 END
      )
  ) THEN
    RAISE EXCEPTION 'deidentified target facts diverged from revision links';
  END IF;
END
$revision_checks$;

ROLLBACK;
