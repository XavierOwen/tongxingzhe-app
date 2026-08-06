DO $check$
DECLARE
  revise_is_security_definer boolean;
  read_is_security_definer boolean;
  resolve_is_security_definer boolean;
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_revise(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute conflict-aware contact revise';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_contact_revision_conflict(uuid,uuid,uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot read an authorized conflict';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_conflict_resolution(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute conflict resolution';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contact_revision_conflicts',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime role can read the conflict table directly';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_revise_strict(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.contact_revision_changed_fields(jsonb,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.merge_contact_revision_snapshots(jsonb,jsonb,text[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role can execute a private conflict helper';
  END IF;

  SELECT procedure_row.prosecdef INTO STRICT revise_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_contact_revise';

  SELECT procedure_row.prosecdef INTO STRICT read_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'read_contact_revision_conflict';

  SELECT procedure_row.prosecdef INTO STRICT resolve_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_contact_conflict_resolution';

  IF NOT revise_is_security_definer
    OR NOT read_is_security_definer
    OR NOT resolve_is_security_definer
  THEN
    RAISE EXCEPTION 'contact conflict entry points are not SECURITY DEFINER';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0010_contact_revision_conflicts'
  ) <> 1 THEN
    RAISE EXCEPTION 'contact conflict migration was not recorded exactly once';
  END IF;
END
$check$;
