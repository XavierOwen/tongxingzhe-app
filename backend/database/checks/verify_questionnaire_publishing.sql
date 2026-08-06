\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_data.questionnaire_drafts') IS NULL
    OR to_regclass('app_data.questionnaire_publish_requests') IS NULL
  THEN
    RAISE EXCEPTION 'questionnaire publishing tables are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.list_questionnaire_administration(uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.publish_questionnaire_draft(uuid,uuid,uuid,uuid,integer,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime cannot use questionnaire administration functions';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_drafts',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_publish_requests',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass questionnaire publishing functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'app_data.questionnaire_versions'::regclass
      AND tgname = 'questionnaire_versions_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'app_data.questionnaire_questions'::regclass
      AND tgname = 'questionnaire_questions_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'app_data.questionnaire_options'::regclass
      AND tgname = 'questionnaire_options_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'published questionnaire immutability triggers are missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_data'
      AND indexname = 'questionnaire_versions_one_current_per_project'
      AND indexdef LIKE '%WHERE is_current%'
  ) THEN
    RAISE EXCEPTION 'one-current-version constraint is missing';
  END IF;
END
$check$;
