\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE public.fixture_0114_upgrade_catalog AS
SELECT
  procedure_row.oid AS function_oid,
  procedure_row.oid::regprocedure::text AS function_name,
  procedure_row.proowner AS function_owner,
  procedure_row.proacl AS function_acl,
  pg_catalog.pg_get_function_result(procedure_row.oid) AS function_result
FROM pg_catalog.pg_proc AS procedure_row
WHERE procedure_row.oid IN (
  'app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamp with time zone)'::regprocedure,
  'app_private.cleanup_personal_target_pair_preview_receipts_v1()'::regprocedure,
  'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'::regprocedure
);

CREATE TABLE public.fixture_0114_upgrade_second_target AS
SELECT target
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN LATERAL app_data.create_promotion_target(
  context_row.app_user_id,
  context_row.workspace_id,
  context_row.project_id,
  'person',
  '0113 merge generation upgrade peer',
  '+1 312 555 0113',
  'UPGRADE-0113@example.test',
  '0113-merge-generation-upgrade-peer'
) AS created;

CREATE TABLE public.fixture_0114_upgrade_contact_payload AS
SELECT jsonb_build_object(
  'contactId', 'contact-0114-upgrade-preexisting',
  'workspaceId', context_row.workspace_id,
  'projectId', context_row.project_id,
  'questionnaireVersionId', context_row.questionnaire_version_id,
  'occurredAtUtc', '2030-02-01T18:00:00.000Z',
  'occurredTimeZone', 'America/Chicago',
  'channel', 'video_call',
  'channelDetail', NULL,
  'location', jsonb_build_object('kind', 'not_applicable'),
  'reachCount', 1,
  'interestLevel', 2,
  'answers', '[]'::jsonb,
  'targetLinks', jsonb_build_array(jsonb_build_object(
    'targetId', state_row.promotion_target_id,
    'targetType', 'person',
    'responseLevel', 3,
    'followUpConsent', 'yes',
    'institutionRepresentativeConfirmed', false,
    'confirmStageZero', true
  ))
) AS payload
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0113_upgrade_state AS state_row;

CREATE TABLE public.fixture_0114_upgrade_contact_result AS
SELECT submitted.*
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0114_upgrade_contact_payload AS payload_row
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  context_row.app_user_id,
  'contact-0114-upgrade-submit',
  1,
  'contact.submit.v1',
  'upgrade-device',
  'contact-0114-upgrade-preexisting',
  0,
  payload_row.payload
) AS submitted;

CREATE TABLE public.fixture_0114_upgrade_preview AS
SELECT preview.*
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0113_upgrade_state AS first_target
CROSS JOIN public.fixture_0114_upgrade_second_target AS second_target
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://synthetic-0113-upgrade.example.test',
  'owner',
  context_row.project_id,
  first_target.promotion_target_id,
  (second_target.target->>'target_id')::uuid
) AS preview;

INSERT INTO app_private.personal_target_pair_preview_receipts (
  preview_id,
  actor_app_user_id,
  workspace_id,
  first_target_id,
  second_target_id,
  first_profile_revision,
  second_profile_revision,
  first_assignment_id,
  second_assignment_id,
  first_retention_due_at_utc,
  second_retention_due_at_utc,
  merge_deadline_at_utc,
  phone_match,
  email_match,
  previewed_at_utc,
  expires_at_utc
)
SELECT
  '00000000-0114-4000-8000-0000000000e1'::uuid,
  receipt.actor_app_user_id,
  receipt.workspace_id,
  receipt.first_target_id,
  receipt.second_target_id,
  receipt.first_profile_revision,
  receipt.second_profile_revision,
  receipt.first_assignment_id,
  receipt.second_assignment_id,
  receipt.first_retention_due_at_utc,
  receipt.second_retention_due_at_utc,
  receipt.merge_deadline_at_utc,
  receipt.phone_match,
  receipt.email_match,
  expired.previewed_at_utc,
  expired.previewed_at_utc + interval '15 minutes'
FROM app_private.personal_target_pair_preview_receipts AS receipt
JOIN public.fixture_0114_upgrade_preview AS preview_row
  ON preview_row.preview_id = receipt.preview_id
CROSS JOIN LATERAL (
  SELECT clock_timestamp() - interval '20 minutes' AS previewed_at_utc
) AS expired;

CREATE TABLE public.fixture_0114_upgrade_state AS
SELECT
  first_target.promotion_target_id AS first_target_id,
  (second_target.target->>'target_id')::uuid AS second_target_id,
  preview_row.preview_id AS live_preview_id,
  (
    SELECT jsonb_agg(to_jsonb(receipt) ORDER BY receipt.preview_id)
    FROM app_private.personal_target_pair_preview_receipts AS receipt
  ) AS receipt_documents,
  (
    SELECT to_jsonb(link_row)
    FROM app_data.contact_target_links AS link_row
    WHERE link_row.contact_id = 'contact-0114-upgrade-preexisting'
      AND link_row.revision_number = 1
      AND link_row.promotion_target_id = first_target.promotion_target_id
  ) AS contact_link_document,
  (
    SELECT to_jsonb(relationship_row)
    FROM app_data.promotion_target_project_relationships AS relationship_row
    WHERE relationship_row.promotion_target_id = first_target.promotion_target_id
      AND relationship_row.project_id = context_row.project_id
  ) AS relationship_document,
  (
    SELECT jsonb_agg(to_jsonb(revision_row)
      ORDER BY revision_row.revision_number)
    FROM app_data.promotion_target_relationship_revisions AS revision_row
    WHERE revision_row.promotion_target_id = first_target.promotion_target_id
      AND revision_row.project_id = context_row.project_id
  ) AS revision_documents
FROM public.fixture_0113_upgrade_context AS context_row
CROSS JOIN public.fixture_0113_upgrade_state AS first_target
CROSS JOIN public.fixture_0114_upgrade_second_target AS second_target
CROSS JOIN public.fixture_0114_upgrade_preview AS preview_row;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0114_upgrade_catalog) <> 3
    OR (SELECT count(*) FROM public.fixture_0114_upgrade_state) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM public.fixture_0114_upgrade_contact_result
      WHERE result_code = 'accepted'
    )
    OR (SELECT count(*)
        FROM app_private.personal_target_pair_preview_receipts) <> 2
    OR EXISTS (
      SELECT 1
      FROM public.fixture_0114_upgrade_state
      WHERE contact_link_document IS NULL
        OR relationship_document IS NULL
        OR revision_documents IS NULL
        OR jsonb_array_length(receipt_documents) <> 2
    )
  THEN
    RAISE EXCEPTION '0113 merge generation upgrade baseline drift';
  END IF;
END
$baseline$;

COMMIT;
