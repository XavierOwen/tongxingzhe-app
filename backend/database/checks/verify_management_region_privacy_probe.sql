\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regprocedure(
    'app_private.assess_management_region_privacy_v1(jsonb)'
  ) IS NULL THEN
    RAISE EXCEPTION 'management region privacy probe is missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.assess_management_region_privacy_v1(jsonb)',
    'EXECUTE'
  ) OR has_schema_privilege(
    'tongxingzhe_runtime', 'app_private', 'USAGE'
  ) THEN
    RAISE EXCEPTION 'runtime can execute the private region privacy probe';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0037_management_region_privacy_probe'
  ) <> 1 THEN
    RAISE EXCEPTION 'management region privacy probe migration is not unique';
  END IF;
END
$check$;
