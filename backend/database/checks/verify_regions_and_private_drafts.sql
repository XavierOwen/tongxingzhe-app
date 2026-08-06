DO $check$
DECLARE
  runtime_can_access_tables boolean;
  upsert_is_security_definer boolean;
  delete_is_security_definer boolean;
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
      ('canonical_region_versions'),
      ('contact_region_assignments'),
      ('contact_drafts')
  ) AS protected_table(table_name);

  IF runtime_can_access_tables THEN
    RAISE EXCEPTION 'runtime role can access region or private draft tables';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_draft_upsert(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_draft_delete(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.pull_sync_changes(uuid,uuid,uuid,text,integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role lacks a controlled draft sync function';
  END IF;

  SELECT procedure_row.prosecdef
    INTO STRICT upsert_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_draft_upsert';

  SELECT procedure_row.prosecdef
    INTO STRICT delete_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'apply_draft_delete';

  SELECT procedure_row.prosecdef
    INTO STRICT pull_is_security_definer
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname = 'app_data'
    AND procedure_row.proname = 'pull_sync_changes';

  IF NOT upsert_is_security_definer
    OR NOT delete_is_security_definer
    OR NOT pull_is_security_definer
  THEN
    RAISE EXCEPTION 'a draft sync function is not SECURITY DEFINER';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.reject_region_cycle()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role can call the region trigger function';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0005_regions_and_private_draft_sync'
  ) <> 1 THEN
    RAISE EXCEPTION 'region and private draft migration was not recorded once';
  END IF;
END
$check$;
