\set ON_ERROR_STOP on

DO $check$
DECLARE
  configuration_table regclass := to_regclass(
    'app_private.project_follow_up_consent_opt_in_versions'
  );
  configure_bridge regprocedure := to_regprocedure(
    'app_data.configure_project_follow_up_consent_opt_in_v1(text,text,uuid,text,uuid,integer,boolean)'
  );
  read_bridge regprocedure := to_regprocedure(
    'app_data.read_project_follow_up_consent_opt_in_v1(text,text,uuid,text)'
  );
  configure_definition text;
  read_definition text;
  helper_definition text;
  validate_insert_definition text;
  private_configure_definition text;
  private_read_definition text;
  configure_result text;
  read_result text;
  configure_owner text;
  read_owner text;
  configure_is_security_definer boolean;
  read_is_security_definer boolean;
  configure_search_path text;
  read_search_path text;
  configure_search_path_count integer;
  read_search_path_count integer;
BEGIN
  IF configuration_table IS NULL THEN
    RAISE EXCEPTION 'project follow-up consent opt-in versions table is missing';
  END IF;

  IF configure_bridge IS NULL OR read_bridge IS NULL THEN
    RAISE EXCEPTION 'project follow-up consent opt-in runtime bridge is missing';
  END IF;

  IF to_regprocedure(
      'app_private.configure_project_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.read_project_follow_up_consent_opt_in_v1(uuid,uuid,text)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.resolve_project_follow_up_consent_opt_in_actor_v1(text,text,uuid)'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'project follow-up consent opt-in private seam is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    configure_bridge,
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    read_bridge,
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime cannot execute project opt-in bridges';
  END IF;

  IF has_function_privilege('public', configure_bridge, 'EXECUTE')
    OR has_function_privilege('public', read_bridge, 'EXECUTE')
  THEN
    RAISE EXCEPTION 'PUBLIC can execute project opt-in bridges';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      configuration_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.configure_project_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.read_project_follow_up_consent_opt_in_v1(uuid,uuid,text)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass project opt-in private seam';
  END IF;

  SELECT
    pg_get_function_result(procedure_row.oid),
    pg_get_functiondef(procedure_row.oid),
    owner_role.rolname,
    procedure_row.prosecdef,
    (
      SELECT count(*)::integer
      FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
    ),
    (
      SELECT config_row.setting
      FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
      LIMIT 1
    )
  INTO configure_result,
    configure_definition,
    configure_owner,
    configure_is_security_definer,
    configure_search_path_count,
    configure_search_path
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = configure_bridge;

  SELECT
    pg_get_function_result(procedure_row.oid),
    pg_get_functiondef(procedure_row.oid),
    owner_role.rolname,
    procedure_row.prosecdef,
    (
      SELECT count(*)::integer
      FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
    ),
    (
      SELECT config_row.setting
      FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
      LIMIT 1
    )
  INTO read_result,
    read_definition,
    read_owner,
    read_is_security_definer,
    read_search_path_count,
    read_search_path
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = read_bridge;

  SELECT pg_get_functiondef(to_regprocedure(
    'app_private.resolve_project_follow_up_consent_opt_in_actor_v1(text,text,uuid)'
  )) INTO helper_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'app_private.validate_project_follow_up_consent_opt_in_insert_v1()'
  )) INTO validate_insert_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'app_private.configure_project_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)'
  )) INTO private_configure_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'app_private.read_project_follow_up_consent_opt_in_v1(uuid,uuid,text)'
  )) INTO private_read_definition;

  IF configure_result IS DISTINCT FROM 'jsonb'
    OR read_result IS DISTINCT FROM 'jsonb'
  THEN
    RAISE EXCEPTION 'project opt-in bridge result contract drifted: %, %',
      configure_result, read_result;
  END IF;

  IF configure_owner = 'tongxingzhe_runtime'
    OR read_owner = 'tongxingzhe_runtime'
    OR NOT configure_is_security_definer
    OR NOT read_is_security_definer
    OR configure_search_path_count <> 1
    OR read_search_path_count <> 1
    OR replace(configure_search_path, ' ', '') <>
      'search_path=pg_catalog,app_data'
    OR replace(read_search_path, ' ', '') <>
      'search_path=pg_catalog,app_data'
  THEN
    RAISE EXCEPTION 'project opt-in runtime bridges have an open security boundary';
  END IF;

  IF configure_definition !~* 'resolve_project_follow_up_consent_opt_in_actor_v1'
    OR read_definition !~* 'resolve_project_follow_up_consent_opt_in_actor_v1'
    OR configure_definition !~* 'configure_project_follow_up_consent_opt_in_v1'
    OR read_definition !~* 'read_project_follow_up_consent_opt_in_v1'
  THEN
    RAISE EXCEPTION 'project opt-in bridge does not delegate to private implementation';
  END IF;

  IF helper_definition !~* 'external_identities'
    OR helper_definition !~* 'workspace_kind = ''personal'''
    OR helper_definition !~* 'personal_owner_app_user_id'
    OR helper_definition !~* 'status = ''active'''
    OR helper_definition !~* 'deleted_at IS NULL'
    OR helper_definition !~* 'FOR SHARE'
  THEN
    RAISE EXCEPTION 'project opt-in identity helper does not lock and reauthorize personal scope';
  END IF;

  IF validate_insert_definition !~* 'actor_app_user_id'
    OR validate_insert_definition !~* 'workspace_kind = ''personal'''
    OR validate_insert_definition !~* 'status = ''active'''
    OR validate_insert_definition !~* 'deleted_at IS NULL'
    OR validate_insert_definition !~* 'latest_version_number'
    OR validate_insert_definition !~* 'version chain'
  THEN
    RAISE EXCEPTION 'project opt-in insert trigger does not enforce scope and version chain';
  END IF;

  IF configure_definition !~* 'resolve_project_follow_up_consent_opt_in_actor_v1'
    OR configure_definition !~* 'configure_project_follow_up_consent_opt_in_v1'
    OR position(
      'pg_advisory_xact_lock' IN configure_definition
    ) = 0
    OR position(
      'resolve_project_follow_up_consent_opt_in_actor_v1' IN configure_definition
    ) <= position('pg_advisory_xact_lock' IN configure_definition)
    OR position(
      'app_private.configure_project_follow_up_consent_opt_in_v1' IN configure_definition
    ) <= position('pg_advisory_xact_lock' IN configure_definition)
    OR private_configure_definition !~* 'clock_timestamp'
    OR private_configure_definition !~* 'pg_advisory_xact_lock'
    OR private_configure_definition !~* 'expected_version'
    OR private_configure_definition !~* 'idempotency conflict'
    OR private_configure_definition ~* 'recorded_at_utc[[:space:]]+timestamp.*requested'
  THEN
    RAISE EXCEPTION 'project opt-in configure does not enforce audited append semantics';
  END IF;

  IF read_definition !~* 'resolve_project_follow_up_consent_opt_in_actor_v1'
    OR read_definition !~* 'read_project_follow_up_consent_opt_in_v1'
    OR private_read_definition !~* 'not_enabled'
    OR private_read_definition !~* 'configuration'
    OR private_read_definition ~* 'numerator|denominator|coverage|excluded_count'
  THEN
    RAISE EXCEPTION 'project opt-in read leaks metric values or loses not_enabled state';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = configuration_table
      AND trigger_row.tgname =
        'project_follow_up_consent_opt_in_versions_immutable'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'project opt-in versions are not protected as immutable history';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = configuration_table
      AND trigger_row.tgname =
        'project_follow_up_consent_opt_in_versions_validate_insert'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'project opt-in versions lack insert validation trigger';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = configuration_table
      AND pg_get_constraintdef(constraint_row.oid) ~* 'expected_version.*version_number'
  ) THEN
    RAISE EXCEPTION 'project opt-in expected version chain constraint is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = configuration_table
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%follow_up_consent_ratio@1%'
  ) THEN
    RAISE EXCEPTION 'project opt-in metric id is not fixed to follow_up_consent_ratio@1';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0048_project_follow_up_consent_opt_in'
  ) <> 1 THEN
    RAISE EXCEPTION 'project follow-up consent opt-in migration was not recorded once';
  END IF;
END
$check$;
