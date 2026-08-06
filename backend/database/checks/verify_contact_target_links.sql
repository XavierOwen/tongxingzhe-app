\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_data.promotion_target_project_relationships') IS NULL
    OR to_regclass('app_data.contact_target_links') IS NULL
  THEN
    RAISE EXCEPTION 'contact target link tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.apply_contact_submit_v3(uuid,text,integer,text,text,text,integer,jsonb)'
  ) IS NULL OR to_regprocedure(
    'app_data.apply_contact_revise_v3(uuid,text,integer,text,text,text,integer,jsonb)'
  ) IS NULL OR to_regprocedure(
    'app_data.apply_contact_conflict_resolution_v3(uuid,text,integer,text,text,text,integer,jsonb)'
  ) IS NULL OR to_regprocedure(
    'app_data.apply_contact_void_v3(uuid,text,integer,text,text,text,integer,jsonb)'
  ) IS NULL OR to_regprocedure(
    'app_data.apply_draft_upsert_v3(uuid,text,integer,text,text,text,integer,jsonb)'
  ) IS NULL OR to_regprocedure(
    'app_data.replay_processed_contact_target_command(uuid,text)'
  ) IS NULL OR to_regprocedure(
    'app_data.finalize_contact_target_warehouse(text,integer)'
  ) IS NULL THEN
    RAISE EXCEPTION 'contact target link functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.apply_contact_submit_v3(uuid,text,integer,text,text,text,integer,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.replay_processed_contact_target_command(uuid,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.finalize_contact_target_warehouse(text,integer)',
    'EXECUTE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contact_target_links',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_project_relationships',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime contact target boundary is unsafe';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name IN (
        'contact_target_links',
        'promotion_target_project_relationships'
      )
      AND column_name IN ('display_name', 'phone', 'email')
  ) THEN
    RAISE EXCEPTION 'contact target facts duplicate target PII';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0017_contact_target_links'
  ) <> 1 THEN
    RAISE EXCEPTION 'contact target migration was not recorded once';
  END IF;
END
$check$;
