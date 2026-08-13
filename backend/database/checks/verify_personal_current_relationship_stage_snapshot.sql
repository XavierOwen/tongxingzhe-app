\set ON_ERROR_STOP on

DO $check$
DECLARE
  snapshot_bridge regprocedure := to_regprocedure(
    'app_data.read_personal_current_relationship_stage_snapshot(uuid,uuid,uuid)'
  );
  result_contract text;
  function_definition text;
  function_owner text;
  is_security_definer boolean;
  search_path_setting_count integer;
  search_path_setting text;
BEGIN
  IF snapshot_bridge IS NULL THEN
    RAISE EXCEPTION
      'personal current relationship stage snapshot function is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_current_relationship_stage_snapshot(uuid,uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'runtime role cannot execute personal current relationship stage snapshot';
  END IF;

  IF has_function_privilege(
    'public',
    'app_data.read_personal_current_relationship_stage_snapshot(uuid,uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'PUBLIC can execute personal current relationship stage snapshot';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_targets',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_assignments',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_project_relationships',
    'SELECT'
  ) THEN
    RAISE EXCEPTION
      'runtime role can read current relationship source tables directly';
  END IF;

  SELECT
    pg_get_function_result(snapshot_bridge),
    pg_get_functiondef(snapshot_bridge),
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
      is_security_definer, search_path_setting_count, search_path_setting
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = snapshot_bridge;

  IF result_contract IS DISTINCT FROM 'TABLE(snapshot jsonb)' THEN
    RAISE EXCEPTION
      'current relationship stage snapshot return contract drifted: %',
      result_contract;
  END IF;

  IF function_owner = 'tongxingzhe_runtime' THEN
    RAISE EXCEPTION
      'current relationship stage snapshot owner is not restore-safe: %',
      function_owner;
  END IF;

  IF NOT is_security_definer
    OR search_path_setting_count <> 1
    OR replace(search_path_setting, ' ', '') <>
      'search_path=pg_catalog,app_data'
  THEN
    RAISE EXCEPTION
      'current relationship stage snapshot security boundary is open';
  END IF;

  IF function_definition ~* 'display_name|phone|email|follow_up_note'
    OR function_definition ~* 'promotion_target_document'
  THEN
    RAISE EXCEPTION
      'current relationship stage snapshot exposes target PII or notes';
  END IF;

  IF function_definition !~* 'statement_timestamp'
    OR function_definition !~* 'current_lifecycle_status = ''active'''
    OR function_definition !~* 'status = ''active'''
    OR function_definition !~* 'ended_at IS NULL'
    OR function_definition !~* 'current_revision'
    OR function_definition !~* 'source_cutoff_utc'
    OR function_definition !~* 'authorized_at_utc'
    OR function_definition !~* 'pending'
  THEN
    RAISE EXCEPTION
      'current relationship stage snapshot scope or metadata drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0047_personal_current_relationship_stage_snapshot'
  ) <> 1 THEN
    RAISE EXCEPTION
      'personal current relationship stage snapshot migration was not recorded once';
  END IF;
END
$check$;
