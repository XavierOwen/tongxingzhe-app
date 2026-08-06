DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name = 'questionnaire_questions'
      AND column_name = 'display_rule'
  ) OR NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name = 'contact_answers'
      AND column_name = 'answer_state_reason'
  ) THEN
    RAISE EXCEPTION 'questionnaire visibility columns are missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_visible_question_ids(uuid,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_visibility_condition_matches(uuid,jsonb,jsonb,text[])',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_answer_errors_v1(uuid,jsonb,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can execute a private visibility helper';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0012_questionnaire_visibility'
  ) <> 1 THEN
    RAISE EXCEPTION 'visibility migration was not recorded exactly once';
  END IF;
END
$check$;
