-- synthetic fixture：证明八题型、五状态、授权读取、服务端复验和作废复制。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE questionnaire_owner_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-questionnaire.supabase.co/auth/v1',
  'synthetic-questionnaire-owner'
);

CREATE TEMP TABLE questionnaire_other_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-questionnaire.supabase.co/auth/v1',
  'synthetic-questionnaire-other'
);

RESET ROLE;

INSERT INTO app_data.questionnaire_questions (
  questionnaire_version_id, question_id, position, prompt, question_type,
  is_required, allow_unknown, allow_refused, allow_not_applicable,
  minimum_selections, maximum_selections, number_kind, unit,
  minimum, maximum, maximum_length
) VALUES
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'consent', 1, '是否同意后续联系？', 'boolean',
    true, false, true, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'interest', 2, '最感兴趣的主题', 'single_choice',
    true, true, true, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'readiness', 3, '参与意愿', 'ordinal_choice',
    true, true, true, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'topics', 4, '希望了解的主题', 'multi_choice',
    false, true, true, true, 1, 2, NULL, NULL, NULL, NULL, NULL),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'household', 5, '家庭人数', 'number',
    false, true, true, true, NULL, NULL, 'integer', '人', 1, 20, NULL),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'date', 6, '希望参加的日期', 'date',
    false, true, true, true, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'short_note', 7, '一句话备注', 'short_text',
    false, true, true, true, NULL, NULL, NULL, NULL, NULL, NULL, 40),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'long_note', 8, '详细备注', 'long_text',
    false, true, true, true, NULL, NULL, NULL, NULL, NULL, NULL, 2000);

INSERT INTO app_data.questionnaire_options (
  questionnaire_version_id, question_id, option_id, position, label
) VALUES
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'interest', 'community', 1, '社区'),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'interest', 'study', 2, '学习'),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'readiness', 'low', 1, '低'),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'readiness', 'high', 2, '高'),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'topics', 'events', 1, '活动'),
  ((SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'topics', 'courses', 2, '课程');

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE questionnaire_read AS
SELECT * FROM app_data.read_published_questionnaire(
  (SELECT app_user_id FROM questionnaire_owner_context),
  (SELECT workspace_id FROM questionnaire_owner_context),
  (SELECT project_id FROM questionnaire_owner_context),
  (SELECT questionnaire_version_id FROM questionnaire_owner_context)
);

CREATE TEMP TABLE questionnaire_forbidden_read AS
SELECT * FROM app_data.read_published_questionnaire(
  (SELECT app_user_id FROM questionnaire_other_context),
  (SELECT workspace_id FROM questionnaire_other_context),
  (SELECT project_id FROM questionnaire_other_context),
  (SELECT questionnaire_version_id FROM questionnaire_owner_context)
);

CREATE TEMP TABLE questionnaire_submit AS
SELECT * FROM app_data.apply_contact_submit_v2(
  (SELECT app_user_id FROM questionnaire_owner_context),
  'questionnaire-submit', 1, 'contact.submit.v1', 'device-a',
  'questionnaire-contact', 0,
  jsonb_build_object(
    'contactId', 'questionnaire-contact',
    'workspaceId', (SELECT workspace_id FROM questionnaire_owner_context),
    'projectId', (SELECT project_id FROM questionnaire_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'consent', 'state', 'answered',
        'type', 'boolean', 'value', true),
      jsonb_build_object('questionId', 'interest', 'state', 'answered',
        'type', 'single_choice', 'value', 'study'),
      jsonb_build_object('questionId', 'readiness', 'state', 'answered',
        'type', 'ordinal_choice', 'value', 'high'),
      jsonb_build_object('questionId', 'topics', 'state', 'answered',
        'type', 'multi_choice', 'value', jsonb_build_array('events', 'courses')),
      jsonb_build_object('questionId', 'household', 'state', 'answered',
        'type', 'number', 'value', 4),
      jsonb_build_object('questionId', 'date', 'state', 'answered',
        'type', 'date', 'value', '2030-02-28'),
      jsonb_build_object('questionId', 'short_note', 'state', 'answered',
        'type', 'short_text', 'value', '简短备注'),
      jsonb_build_object('questionId', 'long_note', 'state', 'refused',
        'type', 'long_text', 'value', NULL)
    )
  )
);

CREATE TEMP TABLE questionnaire_invalid_submit AS
SELECT * FROM app_data.apply_contact_submit_v2(
  (SELECT app_user_id FROM questionnaire_owner_context),
  'questionnaire-invalid', 1, 'contact.submit.v1', 'device-a',
  'questionnaire-invalid-contact', 0,
  jsonb_build_object(
    'contactId', 'questionnaire-invalid-contact',
    'workspaceId', (SELECT workspace_id FROM questionnaire_owner_context),
    'projectId', (SELECT project_id FROM questionnaire_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'occurredAtUtc', '2030-01-08T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'interest', 'state', 'answered',
        'type', 'single_choice', 'value', 'missing-option'),
      jsonb_build_object('questionId', 'readiness', 'state', 'answered',
        'type', 'ordinal_choice', 'value', 'high')
    )
  )
);

CREATE TEMP TABLE questionnaire_incomplete_draft AS
SELECT * FROM app_data.apply_draft_upsert_v2(
  (SELECT app_user_id FROM questionnaire_owner_context),
  'questionnaire-draft', 1, 'draft.upsert.v1', 'device-a',
  'questionnaire-draft', 0,
  jsonb_build_object(
    'draftId', 'questionnaire-draft',
    'workspaceId', (SELECT workspace_id FROM questionnaire_owner_context),
    'projectId', (SELECT project_id FROM questionnaire_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM questionnaire_owner_context),
    'createdAtUtc', '2030-01-08T18:00:00.000Z',
    'updatedAtUtc', '2030-01-08T18:00:00.000Z',
    'answers', jsonb_build_array(
      jsonb_build_object('questionId', 'short_note', 'state', 'answered',
        'type', 'short_text', 'value', '尚未完成')
    )
  )
);

CREATE TEMP TABLE questionnaire_base_revision AS
SELECT typed_payload AS payload
FROM app_data.pull_sync_changes(
  (SELECT app_user_id FROM questionnaire_owner_context),
  (SELECT workspace_id FROM questionnaire_owner_context),
  (SELECT project_id FROM questionnaire_owner_context),
  NULL,
  100
)
WHERE typed_payload->>'contactId' = 'questionnaire-contact'
  AND revision_number = 1;

CREATE TEMP TABLE questionnaire_answer_change AS
SELECT * FROM app_data.apply_contact_revise_v2(
  (SELECT app_user_id FROM questionnaire_owner_context),
  'questionnaire-answer-change', 1, 'contact.revise.v1', 'device-a',
  'questionnaire-contact', 1,
  jsonb_set(
    (SELECT payload FROM questionnaire_base_revision),
    '{answers,1,value}',
    '"community"'::jsonb
  ) || jsonb_build_object('reason', 'answer change')
);

-- 模拟仍停留在 revision 1 的设备：它只改核心字段，旧答案不得覆盖
-- 服务器在 revision 2 已接受的新答案。
CREATE TEMP TABLE questionnaire_disjoint_change AS
SELECT * FROM app_data.apply_contact_revise_v2(
  (SELECT app_user_id FROM questionnaire_owner_context),
  'questionnaire-disjoint-change', 1, 'contact.revise.v1', 'device-b',
  'questionnaire-contact', 1,
  (SELECT payload FROM questionnaire_base_revision) || jsonb_build_object(
    'reachCount', 2,
    'reason', 'disjoint core change'
  )
);

CREATE TEMP TABLE questionnaire_void AS
SELECT * FROM app_data.apply_contact_void_v2(
  (SELECT app_user_id FROM questionnaire_owner_context),
  'questionnaire-void', 1, 'contact.void.v1', 'device-a',
  'questionnaire-contact', 3,
  jsonb_build_object(
    'contactId', 'questionnaire-contact',
    'workspaceId', (SELECT workspace_id FROM questionnaire_owner_context),
    'projectId', (SELECT project_id FROM questionnaire_owner_context),
    'reason', 'synthetic void'
  )
);

RESET ROLE;

DO $fixture_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM questionnaire_read
    WHERE jsonb_array_length(questionnaire_definition->'questions') = 8
  ) OR EXISTS (SELECT 1 FROM questionnaire_forbidden_read) THEN
    RAISE EXCEPTION 'questionnaire definition authorization failed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM questionnaire_submit WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM questionnaire_invalid_submit
    WHERE result_code = 'rejected'
      AND failure_code IN (
        'answer_value_invalid:interest',
        'required_answer_missing:consent'
      )
  ) OR EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id = 'questionnaire-invalid-contact'
  ) THEN
    RAISE EXCEPTION 'questionnaire server validation failed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM questionnaire_incomplete_draft WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'incomplete questionnaire draft was rejected';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM questionnaire_answer_change WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM questionnaire_disjoint_change WHERE result_code = 'accepted'
  ) OR EXISTS (
    SELECT 1 FROM app_data.contact_revision_conflicts
    WHERE command_id = 'questionnaire-disjoint-change'
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contacts
    WHERE contact_id = 'questionnaire-contact'
      AND current_revision = 4
      AND reach_count = 2
  ) OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_answers
    WHERE contact_id = 'questionnaire-contact'
      AND revision_number = 3
      AND question_id = 'interest'
      AND text_value = 'community'
  ) THEN
    RAISE EXCEPTION 'typed questionnaire answers did not survive auto-merge';
  END IF;
  IF (
    SELECT count(*) FROM app_data.contact_answers
    WHERE contact_id = 'questionnaire-contact' AND revision_number = 1
  ) <> 8 OR NOT EXISTS (
    SELECT 1 FROM app_data.contact_answers
    WHERE contact_id = 'questionnaire-contact'
      AND revision_number = 1
      AND question_id = 'topics'
      AND multi_choice_values = ARRAY['events', 'courses']
  ) THEN
    RAISE EXCEPTION 'typed questionnaire answers were not stored';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM questionnaire_void WHERE result_code = 'accepted'
  ) OR (
    SELECT count(*) FROM app_data.contact_answers
    WHERE contact_id = 'questionnaire-contact' AND revision_number = 4
  ) <> 8 THEN
    RAISE EXCEPTION 'void did not preserve typed questionnaire answers';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_data.warehouse_outbox
    WHERE contact_id = 'questionnaire-contact'
      AND (
        analytics_payload ? '_questionnaireAnswersV2'
        OR analytics_payload ? 'answers'
        OR analytics_payload::text LIKE '%简短备注%'
      )
  ) OR EXISTS (
    SELECT 1 FROM app_data.contact_revisions
    WHERE contact_id = 'questionnaire-contact'
      AND snapshot ? '_questionnaireAnswersV2'
  ) OR EXISTS (
    SELECT 1 FROM app_data.change_feed
    WHERE aggregate_id = 'questionnaire-contact'
      AND change_payload ? '_questionnaireAnswersV2'
  ) THEN
    RAISE EXCEPTION 'private questionnaire compatibility data leaked';
  END IF;
END
$fixture_check$;

ROLLBACK;
