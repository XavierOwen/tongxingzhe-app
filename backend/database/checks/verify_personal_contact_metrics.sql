DO $check$
DECLARE
  summary_is_security_definer boolean;
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_contact_summary(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute personal contact summary';
  END IF;

  SELECT procedure_row.prosecdef
    INTO STRICT summary_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'read_personal_contact_summary';

  IF NOT summary_is_security_definer THEN
    RAISE EXCEPTION 'personal contact summary is not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0006_personal_contact_metrics'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal contact metric migration was not recorded once';
  END IF;
END
$check$;
