\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regprocedure(
    'app_private.assess_management_report_pair_release_v1(jsonb,jsonb)'
  ) IS NULL THEN
    RAISE EXCEPTION 'management report pair release assessment is missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.assess_management_report_pair_release_v1(jsonb,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass management report pair release review';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.validate_management_report_document_v1(jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can validate forged management report documents';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0027_management_report_pair_release'
  ) <> 1 THEN
    RAISE EXCEPTION 'management report pair release migration was not recorded once';
  END IF;
END
$check$;
