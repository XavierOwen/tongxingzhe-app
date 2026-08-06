BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE visibility_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-visibility.supabase.co/auth/v1',
  'synthetic-visibility-owner'
);

RESET ROLE;

INSERT INTO app_data.questionnaire_questions (
  questionnaire_version_id, question_id, position, prompt, question_type,
  is_required, allow_unknown, allow_refused, allow_not_applicable,
  maximum_length, display_rule
) VALUES
  ((SELECT questionnaire_version_id FROM visibility_context),
    'consent', 1, '是否同意继续？', 'boolean',
    true, false, true, false, NULL, NULL),
  ((SELECT questionnaire_version_id FROM visibility_context),
    'detail', 2, '同意后的说明', 'short_text',
    true, true, true, true, 40,
    jsonb_build_object(
      'match', 'all',
      'conditions', jsonb_build_array(jsonb_build_object(
        'source_question_id', 'consent',
        'operator', 'equals',
        'operand', true
      ))
    ));

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE visibility_read AS
SELECT * FROM app_data.read_published_questionnaire(
  (SELECT app_user_id FROM visibility_context),
  (SELECT workspace_id FROM visibility_context),
  (SELECT project_id FROM visibility_context),
  (SELECT questionnaire_version_id FROM visibility_context)
);

CREATE TEMP TABLE hidden_marker_submit AS
SELECT * FROM app_data.apply_contact_submit_v2(
  (SELECT app_user_id FROM visibility_context),
  'visibility-marker-submit', 1, 'contact.submit.v1', 'device-a',
  'visibility-marker-contact', 0,
  jsonb_build_object(
    'contactId', 'visibility-marker-contact',
    'workspaceId', (SELECT workspace_id FROM visibility_context),
    'projectId', (SELECT project_id FROM visibility_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM visibility_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'consent', 'state', 'answered',
        'stateReason', NULL, 'type', 'boolean', 'value', false),
      jsonb_build_object('questionId', 'detail', 'state', 'not_applicable',
        'stateReason', 'rule_skipped', 'type', 'short_text', 'value', NULL)
    )
  )
);

CREATE TEMP TABLE hidden_value_submit AS
SELECT * FROM app_data.apply_contact_submit_v2(
  (SELECT app_user_id FROM visibility_context),
  'visibility-hidden-value', 1, 'contact.submit.v1', 'device-a',
  'visibility-hidden-contact', 0,
  jsonb_build_object(
    'contactId', 'visibility-hidden-contact',
    'workspaceId', (SELECT workspace_id FROM visibility_context),
    'projectId', (SELECT project_id FROM visibility_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM visibility_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'consent', 'state', 'answered',
        'stateReason', NULL, 'type', 'boolean', 'value', false),
      jsonb_build_object('questionId', 'detail', 'state', 'answered',
        'stateReason', NULL, 'type', 'short_text', 'value', '夹带答案')
    )
  )
);

CREATE TEMP TABLE visible_missing_submit AS
SELECT * FROM app_data.apply_contact_submit_v2(
  (SELECT app_user_id FROM visibility_context),
  'visibility-required-missing', 1, 'contact.submit.v1', 'device-a',
  'visibility-missing-contact', 0,
  jsonb_build_object(
    'contactId', 'visibility-missing-contact',
    'workspaceId', (SELECT workspace_id FROM visibility_context),
    'projectId', (SELECT project_id FROM visibility_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM visibility_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'consent', 'state', 'answered',
        'stateReason', NULL, 'type', 'boolean', 'value', true)
    )
  )
);

CREATE TEMP TABLE hidden_marker_missing_submit AS
SELECT * FROM app_data.apply_contact_submit_v2(
  (SELECT app_user_id FROM visibility_context),
  'visibility-marker-missing', 1, 'contact.submit.v1', 'device-a',
  'visibility-marker-missing-contact', 0,
  jsonb_build_object(
    'contactId', 'visibility-marker-missing-contact',
    'workspaceId', (SELECT workspace_id FROM visibility_context),
    'projectId', (SELECT project_id FROM visibility_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM visibility_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'consent', 'state', 'answered',
        'stateReason', NULL, 'type', 'boolean', 'value', false)
    )
  )
);

CREATE TEMP TABLE hidden_draft AS
SELECT * FROM app_data.apply_draft_upsert_v2(
  (SELECT app_user_id FROM visibility_context),
  'visibility-hidden-draft', 1, 'draft.upsert.v1', 'device-a',
  'visibility-hidden-draft', 0,
  jsonb_build_object(
    'draftId', 'visibility-hidden-draft',
    'workspaceId', (SELECT workspace_id FROM visibility_context),
    'projectId', (SELECT project_id FROM visibility_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM visibility_context),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:00:00.000Z',
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'consent', 'state', 'answered',
        'stateReason', NULL, 'type', 'boolean', 'value', false),
      jsonb_build_object('questionId', 'detail', 'state', 'answered',
        'stateReason', NULL, 'type', 'short_text', 'value', '草稿夹带')
    )
  )
);

CREATE TEMP TABLE marker_void AS
SELECT * FROM app_data.apply_contact_void_v2(
  (SELECT app_user_id FROM visibility_context),
  'visibility-marker-void', 1, 'contact.void.v1', 'device-a',
  'visibility-marker-contact', 1,
  jsonb_build_object(
    'contactId', 'visibility-marker-contact',
    'workspaceId', (SELECT workspace_id FROM visibility_context),
    'projectId', (SELECT project_id FROM visibility_context),
    'reason', 'synthetic void'
  )
);

RESET ROLE;

DO $fixture_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM visibility_read
    WHERE questionnaire_definition->'questions'->1->'display_rule'
      IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'published visibility rule was not returned';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hidden_marker_submit WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_answers
    WHERE contact_id = 'visibility-marker-contact'
      AND revision_number = 1
      AND question_id = 'detail'
      AND answer_state = 'not_applicable'
      AND answer_state_reason = 'rule_skipped'
  ) THEN
    RAISE EXCEPTION 'rule skipped answer was not stored';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hidden_value_submit
    WHERE result_code = 'rejected'
      AND failure_code = 'hidden_answer_present:detail'
  ) OR NOT EXISTS (
    SELECT 1 FROM hidden_draft
    WHERE result_code = 'rejected'
      AND failure_code = 'hidden_answer_present:detail'
  ) THEN
    RAISE EXCEPTION 'hidden answer was not rejected';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM hidden_marker_missing_submit
    WHERE result_code = 'rejected'
      AND failure_code = 'rule_skipped_answer_missing:detail'
  ) THEN
    RAISE EXCEPTION 'missing rule skipped answer was not rejected';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM visible_missing_submit
    WHERE result_code = 'rejected'
      AND failure_code = 'required_answer_missing:detail'
  ) THEN
    RAISE EXCEPTION 'visible required question was not enforced';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM marker_void WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_answers
    WHERE contact_id = 'visibility-marker-contact'
      AND revision_number = 2
      AND question_id = 'detail'
      AND answer_state_reason = 'rule_skipped'
  ) THEN
    RAISE EXCEPTION 'void did not preserve rule skipped reason';
  END IF;
END
$fixture_check$;

ROLLBACK;
