DO $check$
DECLARE
  summary_is_security_definer boolean;
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_interest_ordinal_summary(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute personal interest ordinal summary';
  END IF;

  IF has_function_privilege(
    'public',
    'app_data.read_personal_interest_ordinal_summary(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC can execute personal interest ordinal summary';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contacts',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime role can read contact rows directly';
  END IF;

  SELECT procedure_row.prosecdef
    INTO STRICT summary_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'read_personal_interest_ordinal_summary';

  IF NOT summary_is_security_definer THEN
    RAISE EXCEPTION 'personal interest ordinal summary is not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0041_personal_interest_ordinal_summary'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal interest ordinal summary migration was not recorded once';
  END IF;
END
$check$;
