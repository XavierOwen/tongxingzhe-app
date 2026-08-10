\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regnamespace('app_private') IS NULL OR to_regprocedure(
    'app_private.protect_management_contact_session_grid_v1(jsonb)'
  ) IS NULL THEN
    RAISE EXCEPTION 'management contact session privacy function is missing';
  END IF;

  IF has_schema_privilege(
    'tongxingzhe_runtime',
    'app_private',
    'USAGE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.protect_management_contact_session_grid_v1(jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass the future management authorization seam';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0023_management_contact_session_privacy'
  ) <> 1 THEN
    RAISE EXCEPTION 'management privacy migration was not recorded once';
  END IF;
END
$check$;
