\set ON_ERROR_STOP on

BEGIN;

DO $fixture$
DECLARE
  manager_context record;
  intruder_context record;
  source_version_id uuid;
  candidate_version_id uuid;
  third_version_id uuid;
  draft_document jsonb;
  publication_document jsonb;
  decision_event jsonb;
  replay_event jsonb;
  revocation_event jsonb;
  catalog jsonb;
  metric_id uuid := '33333333-3333-4333-8333-333333333333';
  source_questions jsonb := $json$
  [{
    "question_id": "interest",
    "position": 1,
    "prompt": "目前的兴趣程度",
    "type": "single_choice",
    "required": true,
    "allow_unknown": true,
    "allow_refused": true,
    "allow_not_applicable": false,
    "options": [
      {"option_id": "low", "position": 1, "label": "较低"},
      {"option_id": "high", "position": 2, "label": "较高"}
    ]
  }]
  $json$::jsonb;
  candidate_questions jsonb := $json$
  [{
    "question_id": "interest-v2",
    "position": 1,
    "prompt": "目前的兴趣程度（修订措辞）",
    "type": "single_choice",
    "required": true,
    "allow_unknown": true,
    "allow_refused": true,
    "allow_not_applicable": false,
    "options": [
      {"option_id": "low", "position": 1, "label": "较低"},
      {"option_id": "high", "position": 2, "label": "较高"}
    ]
  }]
  $json$::jsonb;
  third_questions jsonb := $json$
  [{
    "question_id": "interest-v3",
    "position": 1,
    "prompt": "未来三个月的兴趣程度",
    "type": "single_choice",
    "required": true,
    "allow_unknown": true,
    "allow_refused": true,
    "allow_not_applicable": false,
    "options": [
      {"option_id": "low", "position": 1, "label": "较低"},
      {"option_id": "high", "position": 2, "label": "较高"}
    ]
  }]
  $json$::jsonb;
BEGIN
  SELECT * INTO manager_context
  FROM app_data.bootstrap_personal_context(
    'https://questionnaire-metrics.example.test',
    'manager'
  );
  SELECT * INTO manager_context
  FROM app_data.list_personal_project_contexts(
    'https://questionnaire-metrics.example.test',
    'manager'
  )
  WHERE is_current;
  source_version_id := manager_context.questionnaire_version_id;

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
    source_version_id,
    'interest',
    1,
    '目前的兴趣程度',
    'single_choice',
    true,
    true,
    true,
    false
  );
  INSERT INTO app_data.questionnaire_options (
    questionnaire_version_id,
    question_id,
    option_id,
    position,
    label
  ) VALUES
    (source_version_id, 'interest', 'low', 1, '较低'),
    (source_version_id, 'interest', 'high', 2, '较高');

  SELECT draft INTO draft_document
  FROM app_data.create_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    source_version_id
  );
  PERFORM app_data.update_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (draft_document->>'draft_id')::uuid,
    1,
    candidate_questions
  );
  SELECT publication INTO publication_document
  FROM app_data.publish_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (draft_document->>'draft_id')::uuid,
    2,
    'metric-candidate-v2',
    '问卷指标候选版本'
  );
  candidate_version_id := (
    publication_document->'summary'->>'questionnaire_version_id'
  )::uuid;

  SELECT draft INTO draft_document
  FROM app_data.create_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    candidate_version_id
  );
  PERFORM app_data.update_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (draft_document->>'draft_id')::uuid,
    1,
    third_questions
  );
  SELECT publication INTO publication_document
  FROM app_data.publish_questionnaire_draft(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (draft_document->>'draft_id')::uuid,
    2,
    'metric-candidate-v3',
    '时间范围改变的候选版本'
  );
  third_version_id := (
    publication_document->'summary'->>'questionnaire_version_id'
  )::uuid;

  INSERT INTO app_data.contacts (
    contact_id,
    app_user_id,
    workspace_id,
    project_id,
    questionnaire_version_id,
    occurred_at_utc,
    occurred_time_zone,
    channel,
    location_kind,
    reach_count,
    interest_level
  ) VALUES
    (
      'metric-source-contact',
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id,
      source_version_id,
      '2026-06-15T12:00:00Z',
      'UTC',
      'voice_call',
      'not_applicable',
      1,
      2
    ),
    (
      'metric-candidate-contact',
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id,
      candidate_version_id,
      '2026-07-15T12:00:00Z',
      'UTC',
      'voice_call',
      'not_applicable',
      1,
      2
    );
  INSERT INTO app_data.contact_revisions (
    contact_id,
    revision_number,
    revised_by_app_user_id,
    snapshot
  ) VALUES
    (
      'metric-source-contact',
      1,
      manager_context.app_user_id,
      '{}'::jsonb
    ),
    (
      'metric-candidate-contact',
      1,
      manager_context.app_user_id,
      '{}'::jsonb
    );
  INSERT INTO app_data.contact_answers (
    contact_id,
    revision_number,
    question_id,
    answer_state,
    answer_type,
    text_value
  ) VALUES
    (
      'metric-source-contact',
      1,
      'interest',
      'answered',
      'single_choice',
      'low'
    ),
    (
      'metric-candidate-contact',
      1,
      'interest-v2',
      'answered',
      'single_choice',
      'high'
    );

  SELECT event INTO decision_event
  FROM app_data.record_questionnaire_metric_compatibility(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    metric_id,
    '接触兴趣',
    'distribution',
    source_version_id,
    'interest',
    candidate_version_id,
    'interest-v2',
    'compatible',
    '定义、选项、时间范围和回答方式均未改变',
    'metric-compatible-v2'
  );
  SELECT event INTO replay_event
  FROM app_data.record_questionnaire_metric_compatibility(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    metric_id,
    '接触兴趣',
    'distribution',
    source_version_id,
    'interest',
    candidate_version_id,
    'interest-v2',
    'compatible',
    '定义、选项、时间范围和回答方式均未改变',
    'metric-compatible-v2'
  );
  IF decision_event->>'event_id' <> replay_event->>'event_id'
    OR decision_event->'comparison_snapshot'->'reference'
      ->'definition'->>'prompt' <> '目前的兴趣程度'
    OR decision_event->'comparison_snapshot'->'candidate'
      ->'options'->0->>'option_id' <> 'low'
    OR decision_event->'comparison_snapshot'->'reference'
      ->'time_scope'->>'kind' <> 'all_recorded_contacts'
    OR decision_event->'impact_snapshot'->>'combined_sample_count' <> '2'
    OR jsonb_array_length(
      decision_event->'impact_snapshot'->'trend_series'
    ) <> 2
    OR decision_event->'impact_snapshot'->'trend_series'->0
      ->>'period_start' <> '2026-06-01'
    OR (SELECT count(*) FROM app_data.questionnaire_metric_members
        WHERE questionnaire_metric_id = metric_id) <> 2
  THEN
    RAISE EXCEPTION 'compatible decision did not preserve its comparison';
  END IF;

  SELECT event INTO revocation_event
  FROM app_data.revoke_questionnaire_metric_compatibility(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (decision_event->>'event_id')::uuid,
    '复核发现定义的时间范围将改变',
    'metric-revoke-v2'
  );
  SELECT event INTO replay_event
  FROM app_data.revoke_questionnaire_metric_compatibility(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    (decision_event->>'event_id')::uuid,
    '复核发现定义的时间范围将改变',
    'metric-revoke-v2'
  );
  IF revocation_event->>'action' <> 'revoked'
    OR revocation_event->>'target_event_id' <>
      decision_event->>'event_id'
    OR revocation_event->>'event_id' <> replay_event->>'event_id'
    OR (SELECT count(*) FROM app_data.questionnaire_metric_members
        WHERE questionnaire_metric_id = metric_id) <> 1
  THEN
    RAISE EXCEPTION 'revocation did not split the dynamic metric';
  END IF;

  PERFORM app_data.record_questionnaire_metric_compatibility(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id,
    metric_id,
    '接触兴趣',
    'distribution',
    source_version_id,
    'interest',
    third_version_id,
    'interest-v3',
    'incompatible',
    '候选问题改为未来三个月，时间范围不同',
    'metric-incompatible-v3'
  );
  IF (SELECT count(*) FROM app_data.questionnaire_metric_members
      WHERE questionnaire_metric_id = metric_id) <> 1
    OR (SELECT count(*)
        FROM app_data.questionnaire_metric_compatibility_events
        WHERE questionnaire_metric_id = metric_id) <> 3
  THEN
    RAISE EXCEPTION 'incompatible decision changed the active metric';
  END IF;

  SELECT compatibility INTO catalog
  FROM app_data.list_questionnaire_metric_compatibility(
    manager_context.app_user_id,
    manager_context.workspace_id,
    manager_context.project_id
  );
  IF catalog->'metrics'->0->>'metric_id' <> metric_id::text
    OR jsonb_array_length(catalog->'metrics'->0->'active_members') <> 1
    OR jsonb_array_length(catalog->'events') <> 3
  THEN
    RAISE EXCEPTION 'compatibility catalog lost current or audit state';
  END IF;

  SELECT * INTO intruder_context
  FROM app_data.bootstrap_personal_context(
    'https://questionnaire-metrics.example.test',
    'intruder'
  );
  BEGIN
    PERFORM app_data.record_questionnaire_metric_compatibility(
      intruder_context.app_user_id,
      intruder_context.workspace_id,
      intruder_context.project_id,
      metric_id,
      '伪造指标',
      'distribution',
      source_version_id,
      'interest',
      third_version_id,
      'interest-v3',
      'compatible',
      '跨项目伪造',
      'metric-cross-project'
    );
    RAISE EXCEPTION 'cross-project metric decision was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.revoke_questionnaire_metric_compatibility(
      manager_context.app_user_id,
      manager_context.workspace_id,
      manager_context.project_id,
      (decision_event->>'event_id')::uuid,
      '重复撤销',
      'metric-revoke-again'
    );
    RAISE EXCEPTION 'already revoked decision was revoked again';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
