\set ON_ERROR_STOP on

DO $check$
DECLARE
  ratios_bridge regprocedure := to_regprocedure(
    'app_data.read_personal_target_response_level_ratios(uuid,uuid,uuid,timestamptz,timestamptz)'
  );
  result_contract text;
  function_definition text;
  function_owner text;
  ratios_is_security_definer boolean;
  search_path_setting_count integer;
  search_path_setting text;
BEGIN
  IF ratios_bridge IS NULL THEN
    RAISE EXCEPTION 'personal target response level ratios function is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_target_response_level_ratios(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute personal target response level ratios';
  END IF;

  IF has_function_privilege(
    'public',
    'app_data.read_personal_target_response_level_ratios(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC can execute personal target response level ratios';
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
    RAISE EXCEPTION 'runtime role can read target response ratio source rows directly';
  END IF;

  SELECT
    pg_get_function_result(ratios_bridge),
    pg_get_functiondef(ratios_bridge),
    owner_role.rolname,
    procedure_row.prosecdef,
    (
      SELECT count(*)::integer
      FROM unnest(coalesce(
        procedure_row.proconfig, ARRAY[]::text[]
      )) AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
    ),
    (
      SELECT config_row.setting
      FROM unnest(coalesce(
        procedure_row.proconfig, ARRAY[]::text[]
      )) AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
      LIMIT 1
    )
    INTO result_contract, function_definition, function_owner,
      ratios_is_security_definer, search_path_setting_count,
      search_path_setting
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = ratios_bridge;

  IF result_contract IS DISTINCT FROM
    'TABLE(response_level integer, numerator bigint, denominator bigint, unanswered_count bigint, percentage_basis_points integer)'
  THEN
    RAISE EXCEPTION
      'personal target response level ratios return contract drifted: %',
      result_contract;
  END IF;

  IF function_owner = 'tongxingzhe_runtime' THEN
    RAISE EXCEPTION
      'personal target response level ratios owner is not restore-safe: %',
      function_owner;
  END IF;

  IF NOT ratios_is_security_definer
    OR search_path_setting_count <> 1
    OR replace(search_path_setting, ' ', '') <>
      'search_path=pg_catalog,app_data'
  THEN
    RAISE EXCEPTION 'personal target response level ratios security boundary is open';
  END IF;

  IF function_definition ~* 'promotion_target_assignments|promotion_targets' THEN
    RAISE EXCEPTION
      'personal target response level ratios must not authorize through target PII tables';
  END IF;

  IF function_definition !~* 'current_revision'
    OR function_definition !~* 'lifecycle_status = ''active'''
    OR function_definition !~* 'response_level IS NULL'
    OR function_definition !~* '10000'
    OR function_definition !~* 'numeric'
    OR function_definition !~* 'percentage_basis_points'
  THEN
    RAISE EXCEPTION
      'personal target response level ratios candidate scope or rounding drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0046_personal_target_response_level_ratios'
  ) <> 1 THEN
    RAISE EXCEPTION
      'personal target response level ratios migration was not recorded once';
  END IF;
END
$check$;
