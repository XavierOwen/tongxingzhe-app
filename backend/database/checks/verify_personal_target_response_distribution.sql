\set ON_ERROR_STOP on

DO $check$
DECLARE
  distribution_bridge regprocedure := to_regprocedure(
    'app_data.read_personal_target_response_distribution(uuid,uuid,uuid,timestamptz,timestamptz)'
  );
  result_contract text;
  function_definition text;
BEGIN
  IF distribution_bridge IS NULL THEN
    RAISE EXCEPTION 'personal target response distribution function is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_target_response_distribution(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute personal target response distribution';
  END IF;

  IF has_function_privilege(
    'public',
    'app_data.read_personal_target_response_distribution(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC can execute personal target response distribution';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contacts',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contact_target_links',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_targets',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime role can read target response source rows directly';
  END IF;

  IF (
    SELECT NOT procedure_row.prosecdef
      OR (
        SELECT count(*)
        FROM unnest(coalesce(
          procedure_row.proconfig, ARRAY[]::text[]
        )) AS config_row(setting)
        WHERE config_row.setting ILIKE 'search_path=%'
      ) <> 1
      OR NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(
          procedure_row.proconfig, ARRAY[]::text[]
        )) AS config_row(setting)
        WHERE replace(config_row.setting, ' ', '') =
          'search_path=pg_catalog,app_data'
      )
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = distribution_bridge
  ) THEN
    RAISE EXCEPTION 'personal target response distribution security boundary is open';
  END IF;

  SELECT pg_get_function_result(distribution_bridge)
    INTO result_contract;
  IF result_contract IS DISTINCT FROM
    'TABLE(response_level integer, numerator bigint, denominator bigint, unanswered_count bigint)'
  THEN
    RAISE EXCEPTION
      'personal target response distribution return contract drifted: %',
      result_contract;
  END IF;

  SELECT pg_get_functiondef(distribution_bridge)
    INTO function_definition;
  IF function_definition ~* 'promotion_target_assignments|promotion_targets' THEN
    RAISE EXCEPTION
      'personal target response distribution must not authorize through target PII tables';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0044_personal_target_response_distribution'
  ) <> 1 THEN
    RAISE EXCEPTION
      'personal target response distribution migration was not recorded once';
  END IF;
END
$check$;
