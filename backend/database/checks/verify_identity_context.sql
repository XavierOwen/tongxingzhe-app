DO $check$
DECLARE
  runtime_can_mutate boolean;
  bootstrap_is_security_definer boolean;
BEGIN
  SELECT bool_or(
    has_table_privilege(
      'tongxingzhe_runtime',
      format('app_data.%I', table_name),
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  )
  INTO runtime_can_mutate
  FROM (
    VALUES
      ('app_users'),
      ('external_identities'),
      ('workspaces'),
      ('projects'),
      ('questionnaire_versions')
  ) AS protected_table(table_name);

  IF runtime_can_mutate THEN
    RAISE EXCEPTION 'runtime role can access protected context tables directly';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.bootstrap_personal_context(text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute context bootstrap';
  END IF;

  SELECT procedure_row.prosecdef
    INTO STRICT bootstrap_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'bootstrap_personal_context';

  IF NOT bootstrap_is_security_definer THEN
    RAISE EXCEPTION 'context bootstrap is not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0002_identity_context'
  ) <> 1 THEN
    RAISE EXCEPTION 'identity context migration was not recorded exactly once';
  END IF;
END
$check$;
