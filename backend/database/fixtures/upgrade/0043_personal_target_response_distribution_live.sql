\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_upgrade_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response-upgrade.example/auth/v1',
  '7cp-owner'
);

CREATE TEMP TABLE target_response_upgrade_targets AS
SELECT request.target_key, (created.target->>'target_id')::uuid AS target_id
FROM (VALUES
  ('zero', '7CP 合成对象 0', '7cp-target-zero', NULL::text, NULL::text),
  ('four', '7CP 合成对象 4', '7cp-target-four', '312-555-0144', '7cp-four@example.test'),
  ('null', '7CP 合成对象未填写', '7cp-target-null', NULL, NULL)
) AS request(target_key, display_name, request_id, phone, email)
CROSS JOIN LATERAL app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_upgrade_context),
  (SELECT workspace_id FROM target_response_upgrade_context),
  (SELECT project_id FROM target_response_upgrade_context),
  'person', request.display_name, request.phone, request.email,
  request.request_id
) AS created;

CREATE TEMP TABLE target_response_upgrade_submit AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM target_response_upgrade_context),
  '7cp-contact-submit', 1, 'contact.submit.v1', '7cp-device',
  '7cp-contact', 0,
  jsonb_build_object(
    'contactId', '7cp-contact',
    'workspaceId', (SELECT workspace_id FROM target_response_upgrade_context),
    'projectId', (SELECT project_id FROM target_response_upgrade_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM target_response_upgrade_context),
    'occurredAtUtc', '2030-02-01T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 3,
    'interestLevel', 2,
    'answers', '[]'::jsonb,
    'targetLinks', (
      SELECT jsonb_agg(jsonb_build_object(
        'targetId', target_id,
        'targetType', 'person',
        'responseLevel', CASE target_key
          WHEN 'zero' THEN 0 WHEN 'four' THEN 4 ELSE NULL END,
        'followUpConsent', 'unknown',
        'institutionRepresentativeConfirmed', false,
        'confirmStageZero', true
      ) ORDER BY target_key)
      FROM target_response_upgrade_targets
    )
  )
);

CREATE TEMP TABLE target_response_upgrade_retention AS
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM target_response_upgrade_context),
  (SELECT workspace_id FROM target_response_upgrade_context),
  (SELECT project_id FROM target_response_upgrade_context),
  (SELECT target_id FROM target_response_upgrade_targets
   WHERE target_key = 'four'),
  'anonymize', 'withdrawal', '7cp-target-four-anonymize'
);

RESET ROLE;

DO $check$
BEGIN
  IF (SELECT count(*) FROM target_response_upgrade_targets) <> 3
    OR (SELECT result_code FROM target_response_upgrade_submit)
      IS DISTINCT FROM 'accepted'
    OR (SELECT count(*) FROM app_data.contacts
        WHERE contact_id = '7cp-contact'
          AND current_revision = 1 AND lifecycle_status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '7cp-contact' AND revision_number = 1) <> 3
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '7cp-contact' AND revision_number = 1
          AND response_level = 0) <> 1
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '7cp-contact' AND revision_number = 1
          AND response_level = 4) <> 1
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '7cp-contact' AND revision_number = 1
          AND response_level IS NULL) <> 1
    OR NOT EXISTS (
      SELECT 1 FROM app_data.contact_target_links
      WHERE contact_id = '7cp-contact' AND revision_number = 1
        AND promotion_target_id = (
          SELECT target_id FROM target_response_upgrade_targets
          WHERE target_key = 'four')
        AND response_level = 4
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_data.contact_target_links
      WHERE contact_id = '7cp-contact' AND revision_number = 1
        AND promotion_target_id = (
          SELECT target_id FROM target_response_upgrade_targets
          WHERE target_key = 'null')
        AND response_level IS NULL
    )
    OR (SELECT result->>'status' FROM target_response_upgrade_retention)
      IS DISTINCT FROM 'anonymized'
    OR NOT EXISTS (
      SELECT 1 FROM app_data.promotion_targets
      WHERE promotion_target_id = (
        SELECT target_id FROM target_response_upgrade_targets
        WHERE target_key = 'four')
        AND status = 'anonymized' AND display_name = '已匿名化对象'
        AND phone IS NULL AND email IS NULL
    )
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events
        WHERE mutation_id = '7cp-target-four-anonymize'
          AND event_type = 'anonymized') <> 1
  THEN
    RAISE EXCEPTION '0043 target response writer or retention history drift';
  END IF;
END
$check$;

COMMIT;
