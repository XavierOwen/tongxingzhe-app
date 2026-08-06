\set ON_ERROR_STOP on

BEGIN;

DO $fixture$
DECLARE
  manager_context record;
  intruder_context record;
  created_draft jsonb;
  updated_draft jsonb;
  first_publication jsonb;
  duplicate_publication jsonb;
  repeated_publication jsonb;
  second_draft jsonb;
  second_publication jsonb;
  blank_draft jsonb;
  first_version_id uuid;
  published_version_id uuid;
  second_published_version_id uuid;
  candidate_questions jsonb := $json$
  [
    {
      "question_id": "consent",
      "position": 1,
      "prompt": "愿意继续了解吗？",
      "type": "boolean",
      "required": true,
      "allow_unknown": false,
      "allow_refused": true,
      "allow_not_applicable": false
    },
    {
      "question_id": "note",
      "position": 2,
      "prompt": "补充说明",
      "type": "short_text",
      "required": false,
      "allow_unknown": false,
      "allow_refused": true,
      "allow_not_applicable": true,
      "maximum_length": 120,
      "display_rule": {
        "match": "all",
        "conditions": [
          {
            "source_question_id": "consent",
            "operator": "equals",
            "operand": true
          }
        ]
      }
    },
    {
      "question_id": "topic",
      "position": 3,
      "prompt": "主题",
      "type": "single_choice",
      "required": false,
      "allow_unknown": true,
      "allow_refused": true,
      "allow_not_applicable": true,
      "options": [
        {"option_id": "life", "position": 1, "label": "人生"},
        {"option_id": "faith", "position": 2, "label": "信仰"}
      ]
    }
  ]
  $json$::jsonb;
BEGIN
  IF app_data.questionnaire_questions_definition_valid($json$
    [{
      "question_id": "missing-type",
      "position": 1,
      "prompt": "缺少题型",
      "required": false,
      "allow_unknown": false,
      "allow_refused": true,
      "allow_not_applicable": true
    }]
  $json$::jsonb) THEN
    RAISE EXCEPTION 'definition without a required type was accepted';
  END IF;
  IF app_data.questionnaire_questions_definition_valid($json$
    [{
      "question_id": "missing-options",
      "position": 1,
      "prompt": "缺少选项",
      "type": "single_choice",
      "required": false,
      "allow_unknown": false,
      "allow_refused": true,
      "allow_not_applicable": true
    }]
  $json$::jsonb) THEN
    RAISE EXCEPTION 'choice definition without options was accepted';
  END IF;
  IF app_data.questionnaire_questions_definition_valid($json$
    [
      {
        "question_id": "date-source",
        "position": 1,
        "prompt": "日期",
        "type": "date",
        "required": false,
        "allow_unknown": false,
        "allow_refused": true,
        "allow_not_applicable": true
      },
      {
        "question_id": "date-target",
        "position": 2,
        "prompt": "条件题",
        "type": "boolean",
        "required": false,
        "allow_unknown": false,
        "allow_refused": true,
        "allow_not_applicable": true,
        "display_rule": {
          "match": "all",
          "conditions": [{
            "source_question_id": "date-source",
            "operator": "equals",
            "operand": "2026-02-30"
          }]
        }
      }
    ]
  $json$::jsonb) THEN
    RAISE EXCEPTION 'invalid calendar date rule was accepted';
  END IF;
  IF NOT app_data.questionnaire_questions_definition_valid(
    candidate_questions
  ) THEN
    RAISE EXCEPTION 'valid controlled questionnaire definition was rejected';
  END IF;

  SELECT * INTO manager_context
  FROM app_data.bootstrap_personal_context(
    'https://questionnaire-publishing.example.test',
    'manager'
  );
  SELECT * INTO manager_context
  FROM app_data.list_personal_project_contexts(
    'https://questionnaire-publishing.example.test',
    'manager'
  )
  WHERE is_current;

  IF NOT 'manage_analysis_definitions' = ANY(manager_context.capabilities) THEN
    RAISE EXCEPTION 'personal owner did not receive questionnaire management';
  END IF;
  first_version_id := manager_context.questionnaire_version_id;

  INSERT INTO app_data.questionnaire_questions (
    questionnaire_version_id,
    question_id,
    position,
    prompt,
    question_type,
    is_required,
    allow_unknown,
    allow_refused,
    allow_not_applicable
  ) VALUES (
    first_version_id,
    'initial-consent',
    1,
    '初始问题',
    'boolean',
    true,
    false,
    true,
    false
  );

  SELECT draft INTO created_draft
  FROM app_data.create_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    first_version_id
  );

  IF created_draft->'definition'->'questions'->0->>'question_id'
      <> 'initial-consent'
    OR (SELECT count(*) FROM app_data.questionnaire_versions
        WHERE project_id = manager_context.project_id AND is_current) <> 1
  THEN
    RAISE EXCEPTION 'cloned draft changed or missed the current version';
  END IF;

  SELECT draft INTO updated_draft
  FROM app_data.update_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (created_draft->>'draft_id')::uuid,
    1,
    candidate_questions
  );
  IF (updated_draft->>'revision')::integer <> 2 THEN
    RAISE EXCEPTION 'draft revision did not advance';
  END IF;

  SELECT publication INTO first_publication
  FROM app_data.publish_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (created_draft->>'draft_id')::uuid,
    2,
    '11111111-2222-4333-8444-555555555555',
    '发布问卷设计 fixture'
  );
  published_version_id := (
    first_publication->'summary'->>'questionnaire_version_id'
  )::uuid;

  IF (first_publication->'summary'->>'version_number')::integer <> 2
    OR first_publication->'summary'->>'publication_note'
      <> '发布问卷设计 fixture'
    OR first_publication->'questionnaire'->'questions'->1
      ->'display_rule'->>'match' <> 'all'
    OR (SELECT count(*) FROM app_data.questionnaire_versions
        WHERE project_id = manager_context.project_id AND is_current) <> 1
    OR (SELECT questionnaire_version_id FROM app_data.questionnaire_versions
        WHERE project_id = manager_context.project_id AND is_current)
      <> published_version_id
  THEN
    RAISE EXCEPTION 'publication was partial or did not become current';
  END IF;

  SELECT publication INTO duplicate_publication
  FROM app_data.publish_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (created_draft->>'draft_id')::uuid,
    2,
    '11111111-2222-4333-8444-555555555555',
    '发布问卷设计 fixture'
  );
  SELECT publication INTO repeated_publication
  FROM app_data.publish_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (created_draft->>'draft_id')::uuid,
    2,
    '99999999-2222-4333-8444-555555555555',
    '网络恢复后的重复发布'
  );
  IF duplicate_publication->'summary'->>'questionnaire_version_id'
      <> published_version_id::text
    OR repeated_publication->'summary'->>'questionnaire_version_id'
      <> published_version_id::text
    OR (SELECT count(*) FROM app_data.questionnaire_versions
        WHERE project_id = manager_context.project_id) <> 2
  THEN
    RAISE EXCEPTION 'duplicate publication created another version';
  END IF;

  SELECT draft INTO blank_draft
  FROM app_data.create_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    NULL
  );
  BEGIN
    PERFORM app_data.publish_questionnaire_draft(
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id,
      (blank_draft->>'draft_id')::uuid,
      1,
      'aaaaaaaa-2222-4333-8444-555555555555',
      '空白问卷'
    );
    RAISE EXCEPTION 'empty questionnaire was published';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.questionnaire_questions (
      questionnaire_version_id,
      question_id,
      position,
      prompt,
      question_type,
      is_required,
      allow_unknown,
      allow_refused,
      allow_not_applicable
    ) VALUES (
      published_version_id,
      'late-insert',
      99,
      '发布后追加',
      'boolean',
      false,
      false,
      true,
      true
    );
    RAISE EXCEPTION 'published question was inserted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    UPDATE app_data.questionnaire_questions
    SET prompt = '被改写'
    WHERE questionnaire_version_id = published_version_id
      AND question_id = 'consent';
    RAISE EXCEPTION 'published question was updated';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_data.questionnaire_options
    WHERE questionnaire_version_id = published_version_id
      AND question_id = 'topic'
      AND option_id = 'life';
    RAISE EXCEPTION 'published option was deleted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    UPDATE app_data.questionnaire_versions
    SET publication_note = '被改写'
    WHERE questionnaire_version_id = published_version_id;
    RAISE EXCEPTION 'published metadata was updated';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  SELECT * INTO intruder_context
  FROM app_data.bootstrap_personal_context(
    'https://questionnaire-publishing.example.test',
    'intruder'
  );
  BEGIN
    PERFORM app_data.create_questionnaire_draft(
      intruder_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id,
      published_version_id
    );
    RAISE EXCEPTION 'another personal owner managed this project';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  UPDATE app_data.app_users
  SET status = 'deletion_pending'
  WHERE app_user_id = manager_context.app_user_id;
  BEGIN
    PERFORM app_data.list_questionnaire_administration(
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id
    );
    RAISE EXCEPTION 'revoked app user managed questionnaires';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  UPDATE app_data.app_users
  SET status = 'active'
  WHERE app_user_id = manager_context.app_user_id;

  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = manager_context.project_id;
  BEGIN
    PERFORM app_data.list_questionnaire_administration(
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id
    );
    RAISE EXCEPTION 'archived project allowed questionnaire management';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  UPDATE app_data.projects
  SET status = 'active'
  WHERE project_id = manager_context.project_id;

  UPDATE app_data.workspaces
  SET deleted_at = clock_timestamp()
  WHERE workspace_id = manager_context.workspace_id;
  BEGIN
    PERFORM app_data.list_questionnaire_administration(
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id
    );
    RAISE EXCEPTION 'deleted workspace allowed questionnaire management';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  UPDATE app_data.workspaces
  SET deleted_at = NULL
  WHERE workspace_id = manager_context.workspace_id;

  SELECT draft INTO second_draft
  FROM app_data.create_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    published_version_id
  );
  SELECT publication INTO second_publication
  FROM app_data.publish_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (second_draft->>'draft_id')::uuid,
    1,
    'bbbbbbbb-2222-4333-8444-555555555555',
    '复制旧设计并发布新版本'
  );
  second_published_version_id := (
    second_publication->'summary'->>'questionnaire_version_id'
  )::uuid;
  IF second_published_version_id = published_version_id
    OR (SELECT count(*) FROM app_data.questionnaire_versions
        WHERE project_id = manager_context.project_id AND is_current) <> 1
    OR (SELECT questionnaire_version_id FROM app_data.questionnaire_versions
        WHERE project_id = manager_context.project_id AND is_current)
      <> second_published_version_id
    OR (SELECT count(*) FROM app_data.questionnaire_questions
        WHERE questionnaire_version_id = published_version_id) <> 3
    OR (SELECT count(*) FROM app_data.questionnaire_questions
        WHERE questionnaire_version_id = first_version_id) <> 1
  THEN
    RAISE EXCEPTION 'serial publication changed historical definitions';
  END IF;
END
$fixture$;

ROLLBACK;
