\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regprocedure(
    'app_private.execute_management_contact_session_report_v1(uuid,text,integer,text,timestamp with time zone)'
  ) IS NULL THEN
    RAISE EXCEPTION 'private management report execution is missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.execute_management_contact_session_report_v1(uuid,text,integer,text,timestamp with time zone)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass management report authorization';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0026_management_report_execution'
  ) <> 1 THEN
    RAISE EXCEPTION 'management report execution migration was not recorded once';
  END IF;
END
$check$;
