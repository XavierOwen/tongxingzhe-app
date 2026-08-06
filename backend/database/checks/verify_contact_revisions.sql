DO $check$
DECLARE
  revise_is_security_definer boolean;
  void_is_security_definer boolean;
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_revise(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute contact revise';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_void(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute contact void';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_revision_command(uuid,text,integer,text,text,text,integer,jsonb,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role can execute private revision helper';
  END IF;

  SELECT procedure_row.prosecdef INTO STRICT revise_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_contact_revise';

  SELECT procedure_row.prosecdef INTO STRICT void_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_contact_void';

  IF NOT revise_is_security_definer OR NOT void_is_security_definer THEN
    RAISE EXCEPTION 'contact revision wrappers are not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0009_contact_revisions'
  ) <> 1 THEN
    RAISE EXCEPTION 'contact revision migration was not recorded exactly once';
  END IF;
END
$check$;
