\set ON_ERROR_STOP on

DO $check$
DECLARE
  ratio_bridge regprocedure := to_regprocedure(
    'app_data.read_personal_follow_up_consent_ratio_v1(text,text,uuid,text,timestamptz,timestamptz)'
  );
  configuration_table regclass := to_regclass(
    'app_private.project_follow_up_consent_opt_in_versions'
  );
  ratio_definition text;
  ratio_owner text;
  ratio_result text;
  ratio_is_security_definer boolean;
  ratio_search_path text;
  ratio_search_path_count integer;
  resolver_position integer;
  lock_position integer;
  configuration_query_position integer;
  not_enabled_return_position integer;
  contacts_position integer;
  links_position integer;
BEGIN
  IF ratio_bridge IS NULL OR configuration_table IS NULL THEN
    RAISE EXCEPTION 'personal follow-up consent ratio seam is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    ratio_bridge,
    'EXECUTE'
  ) OR has_function_privilege('public', ratio_bridge, 'EXECUTE') THEN
    RAISE EXCEPTION 'personal follow-up consent ratio bridge ACL is unsafe';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      configuration_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.contacts',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.contact_target_links',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.resolve_project_follow_up_consent_opt_in_actor_v1(text,text,uuid)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass personal follow-up consent ratio seam';
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
  INTO ratio_result,
    ratio_definition,
    ratio_owner,
    ratio_is_security_definer,
    ratio_search_path_count,
    ratio_search_path
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = ratio_bridge;

  IF ratio_result IS DISTINCT FROM 'jsonb'
    OR ratio_owner = 'tongxingzhe_runtime'
    OR NOT ratio_is_security_definer
    OR ratio_search_path_count <> 1
    OR replace(ratio_search_path, ' ', '') <>
      'search_path=pg_catalog,app_data'
  THEN
    RAISE EXCEPTION 'personal follow-up consent ratio bridge security contract drifted';
  END IF;

  resolver_position := position(
    'resolve_project_follow_up_consent_opt_in_actor_v1' IN ratio_definition
  );
  lock_position := position('pg_advisory_xact_lock' IN ratio_definition);
  configuration_query_position := position(
    'from app_private.project_follow_up_consent_opt_in_versions'
      IN lower(ratio_definition)
  );
  not_enabled_return_position := position(
    '''status'', ''not_enabled''' IN lower(ratio_definition)
  );
  contacts_position := position('app_data.contacts' IN ratio_definition);
  links_position := position('app_data.contact_target_links' IN ratio_definition);

  IF ratio_definition !~* 'requested_metric_id'
    OR ratio_definition !~* 'follow_up_consent_ratio@1'
    OR ratio_definition !~* 'isfinite'
    OR ratio_definition !~* 'from_utc'
    OR ratio_definition !~* 'until_utc'
    OR ratio_definition !~* 'not_enabled'
    OR ratio_definition !~* 'latest_version'
    OR ratio_definition !~* 'yes_count'
    OR ratio_definition !~* 'no_count'
    OR ratio_definition !~* 'numerator'
    OR ratio_definition !~* 'unanswered_count'
    OR ratio_definition !~* 'refused_count'
    OR ratio_definition !~* 'not_applicable_count'
    OR ratio_definition !~* 'percentage_basis_points'
    OR ratio_definition !~* 'personal_follow_up_consent_ratio_result_v1'
    OR ratio_definition !~* 'contact_target_links'
    OR ratio_definition !~* 'current_revision'
    OR ratio_definition !~* 'lifecycle_status'
    OR ratio_definition !~* 'workspace_id'
    OR resolver_position = 0
    OR lock_position = 0
    OR configuration_query_position = 0
    OR not_enabled_return_position = 0
    OR contacts_position = 0
    OR links_position = 0
    OR resolver_position <= lock_position
    OR configuration_query_position <= resolver_position
    OR not_enabled_return_position <= configuration_query_position
    OR not_enabled_return_position >= contacts_position
    OR contacts_position >= links_position
    OR ratio_definition !~* 'IF NOT FOUND OR NOT latest_version.enabled'
  THEN
    RAISE EXCEPTION 'personal follow-up consent ratio bridge does not enforce fixed metric, short circuit, scope, or current-link semantics';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = configuration_table
      AND pg_get_constraintdef(constraint_row.oid) LIKE
        '%follow_up_consent_ratio@1%'
  ) THEN
    RAISE EXCEPTION 'project opt-in metric constraint is missing';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0049_personal_follow_up_consent_ratio'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal follow-up consent ratio migration was not recorded once';
  END IF;
END
$check$;
