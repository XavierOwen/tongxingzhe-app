DO $check$
DECLARE
  runtime_can_access_tables boolean;
  submit_is_security_definer boolean;
  pull_is_security_definer boolean;
BEGIN
  SELECT bool_or(
    has_table_privilege(
      'tongxingzhe_runtime',
      format('app_data.%I', table_name),
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  )
  INTO runtime_can_access_tables
  FROM (
    VALUES
      ('contacts'),
      ('contact_revisions'),
      ('contact_answers'),
      ('change_feed'),
      ('processed_commands'),
      ('contact_audit_events'),
      ('warehouse_outbox')
  ) AS protected_table(table_name);

  IF runtime_can_access_tables THEN
    RAISE EXCEPTION 'runtime role can access contact sync tables directly';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_submit(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute contact submit';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.pull_contact_changes(uuid,uuid,uuid,text,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute contact pull';
  END IF;

  SELECT procedure_row.prosecdef
    INTO STRICT submit_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_contact_submit';

  IF NOT submit_is_security_definer THEN
    RAISE EXCEPTION 'contact submit is not SECURITY DEFINER';
  END IF;

  SELECT procedure_row.prosecdef
    INTO STRICT pull_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'pull_contact_changes';

  IF NOT pull_is_security_definer THEN
    RAISE EXCEPTION 'contact pull is not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0003_contact_sync'
  ) <> 1 THEN
    RAISE EXCEPTION 'contact sync migration was not recorded exactly once';
  END IF;
END
$check$;
