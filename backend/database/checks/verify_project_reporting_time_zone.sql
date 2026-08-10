\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass(
      'app_private.project_reporting_time_zone_versions'
    ) IS NULL
    OR to_regprocedure(
      'app_private.configure_project_reporting_time_zone_v1(uuid,uuid,uuid,integer,text,timestamp with time zone)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.read_project_reporting_time_zone_v1(uuid,timestamp with time zone)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.project_reporting_time_zone_change_boundary_v1(timestamp with time zone,text)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.validate_project_reporting_time_zone_insert_v1()'
    ) IS NULL
    OR to_regprocedure(
      'app_private.reject_project_reporting_time_zone_mutation_v1()'
    ) IS NULL
    OR to_regprocedure(
      'app_private.project_reporting_time_zone_version_document_v1(uuid,integer)'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'project reporting time zone contract is incomplete';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.project_reporting_time_zone_versions',
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.configure_project_reporting_time_zone_v1(uuid,uuid,uuid,integer,text,timestamp with time zone)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.read_project_reporting_time_zone_v1(uuid,timestamp with time zone)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.project_reporting_time_zone_change_boundary_v1(timestamp with time zone,text)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.project_reporting_time_zone_version_document_v1(uuid,integer)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.validate_project_reporting_time_zone_insert_v1()',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.reject_project_reporting_time_zone_mutation_v1()',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass project reporting time zone policy';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.project_reporting_time_zone_versions'::regclass
      AND tgname = 'project_reporting_time_zone_versions_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.project_reporting_time_zone_versions'::regclass
      AND tgname =
        'project_reporting_time_zone_versions_validate_insert'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'project reporting time zone history is not protected';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0029_project_reporting_time_zone'
  ) <> 1 THEN
    RAISE EXCEPTION 'project reporting time zone migration was not recorded once';
  END IF;
END
$check$;
