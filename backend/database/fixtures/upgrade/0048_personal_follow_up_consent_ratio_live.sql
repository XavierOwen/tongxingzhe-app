\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE consent_ratio_upgrade_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-consent-ratio-upgrade.example/auth/v1',
  '7cq-owner'
);

CREATE TEMP TABLE consent_ratio_upgrade_targets AS
SELECT request.consent_state,
       (created.target->>'target_id')::uuid AS target_id
FROM (VALUES
  ('yes', '7cq-target-yes'),
  ('no', '7cq-target-no'),
  ('unknown', '7cq-target-unknown')
) AS request(consent_state, request_id)
CROSS JOIN LATERAL app_data.create_promotion_target(
  (SELECT app_user_id FROM consent_ratio_upgrade_context),
  (SELECT workspace_id FROM consent_ratio_upgrade_context),
  (SELECT project_id FROM consent_ratio_upgrade_context),
  'person', '7CQ 合成对象 ' || request.consent_state,
  NULL, NULL, request.request_id
) AS created;

CREATE TEMP TABLE consent_ratio_upgrade_submit AS
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM consent_ratio_upgrade_context),
  '7cq-contact-submit', 1, 'contact.submit.v1', '7cq-device',
  '7cq-contact', 0,
  jsonb_build_object(
    'contactId', '7cq-contact',
    'workspaceId', (SELECT workspace_id FROM consent_ratio_upgrade_context),
    'projectId', (SELECT project_id FROM consent_ratio_upgrade_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM consent_ratio_upgrade_context),
    'occurredAtUtc', '2026-08-01T18:00:00.000Z',
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
        'responseLevel', 2,
        'followUpConsent', consent_state,
        'institutionRepresentativeConfirmed', false,
        'confirmStageZero', true
      ) ORDER BY consent_state)
      FROM consent_ratio_upgrade_targets
    )
  )
);

CREATE TEMP TABLE consent_ratio_upgrade_config AS
SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
  'https://synthetic-consent-ratio-upgrade.example/auth/v1',
  '7cq-owner',
  (SELECT project_id FROM consent_ratio_upgrade_context),
  'follow_up_consent_ratio@1',
  'e4900000-0000-4000-8000-000000000071'::uuid,
  0,
  true
) AS configuration;

RESET ROLE;

DO $check$
BEGIN
  IF (SELECT count(*) FROM consent_ratio_upgrade_targets) <> 3
    OR (SELECT result_code FROM consent_ratio_upgrade_submit)
      IS DISTINCT FROM 'accepted'
    OR (SELECT count(*) FROM app_data.contacts
        WHERE contact_id = '7cq-contact'
          AND current_revision = 1
          AND lifecycle_status = 'active'
          AND occurred_at_utc = '2026-08-01T18:00:00Z') <> 1
    OR (SELECT count(*) FROM app_data.contact_revisions
        WHERE contact_id = '7cq-contact' AND revision_number = 1) <> 1
    OR (SELECT count(*) FROM app_data.contact_target_links
        WHERE contact_id = '7cq-contact' AND revision_number = 1) <> 3
    OR (SELECT array_agg(follow_up_consent ORDER BY follow_up_consent)
        FROM app_data.contact_target_links
        WHERE contact_id = '7cq-contact' AND revision_number = 1)
      IS DISTINCT FROM ARRAY['no', 'unknown', 'yes']::text[]
    OR (SELECT configuration->>'version_number'
        FROM consent_ratio_upgrade_config) IS DISTINCT FROM '1'
    OR (SELECT configuration->>'enabled'
        FROM consent_ratio_upgrade_config) IS DISTINCT FROM 'true'
    OR (SELECT count(*)
        FROM app_private.project_follow_up_consent_opt_in_versions
        WHERE project_id = (SELECT project_id FROM consent_ratio_upgrade_context)
          AND version_number = 1 AND enabled) <> 1
    OR NOT EXISTS (
      SELECT 1 FROM app_data.contacts AS contact_row
      JOIN app_private.project_follow_up_consent_opt_in_versions AS opt_in
        ON opt_in.project_id = contact_row.project_id
      WHERE contact_row.contact_id = '7cq-contact'
        AND contact_row.first_submitted_at_utc < opt_in.recorded_at_utc
    )
  THEN
    RAISE EXCEPTION '0048 old contact, links or later opt-in writer drift';
  END IF;
END
$check$;

COMMIT;
