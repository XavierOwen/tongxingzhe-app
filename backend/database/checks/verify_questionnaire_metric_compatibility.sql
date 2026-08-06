\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_data.questionnaire_metrics') IS NULL
    OR to_regclass(
      'app_data.questionnaire_metric_compatibility_events'
    ) IS NULL
    OR to_regclass('app_data.questionnaire_metric_members') IS NULL
  THEN
    RAISE EXCEPTION 'questionnaire metric compatibility tables are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.list_questionnaire_metric_compatibility(uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.record_questionnaire_metric_compatibility(uuid,uuid,uuid,uuid,text,text,uuid,text,uuid,text,text,text,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.revoke_questionnaire_metric_compatibility(uuid,uuid,uuid,uuid,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime cannot use questionnaire metric functions';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_metrics',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_metric_compatibility_events',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.questionnaire_metric_members',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass questionnaire metric functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_data'
      AND indexname = 'questionnaire_metric_one_revocation_per_event'
      AND indexdef LIKE '%WHERE (action = %'
  ) THEN
    RAISE EXCEPTION 'one-revocation constraint is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'app_data.questionnaire_metrics'::regclass
      AND tgname = 'questionnaire_metrics_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.questionnaire_metric_compatibility_events'::regclass
      AND tgname = 'questionnaire_metric_events_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'questionnaire metric audit immutability is missing';
  END IF;
END
$check$;
