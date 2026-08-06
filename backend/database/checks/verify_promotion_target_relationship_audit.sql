\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass(
    'app_data.promotion_target_relationship_revisions'
  ) IS NULL OR to_regclass(
    'app_data.promotion_target_relationship_conflicts'
  ) IS NULL OR to_regclass(
    'app_data.promotion_target_relationship_conflict_resolutions'
  ) IS NULL OR to_regclass(
    'app_data.promotion_target_stage_aliases'
  ) IS NULL THEN
    RAISE EXCEPTION 'promotion target relationship audit tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.update_promotion_target_relationship(uuid,uuid,uuid,uuid,integer,integer,text,text,text,text,text,uuid)'
  ) IS NULL OR to_regprocedure(
    'app_data.configure_promotion_target_stage_aliases(uuid,uuid,uuid,jsonb)'
  ) IS NULL OR to_regprocedure(
    'app_data.promotion_target_relationship_document(uuid,uuid,boolean)'
  ) IS NULL THEN
    RAISE EXCEPTION 'promotion target relationship functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.update_promotion_target_relationship(uuid,uuid,uuid,uuid,integer,integer,text,text,text,text,text,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.configure_promotion_target_stage_aliases(uuid,uuid,uuid,jsonb)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_relationship_document(uuid,uuid,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime relationship function boundary is unsafe';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_relationship_revisions',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_relationship_conflicts',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_relationship_conflict_resolutions',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_stage_aliases',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass relationship functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_relationship_revisions'::regclass
      AND tgname = 'promotion_target_relationship_revisions_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_relationship_conflicts'::regclass
      AND tgname = 'promotion_target_relationship_conflicts_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_project_relationships'::regclass
      AND tgname = 'promotion_target_relationship_initial_revision'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'relationship history trigger protection is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name IN (
        'promotion_target_project_relationships',
        'promotion_target_relationship_revisions',
        'promotion_target_stage_aliases'
      )
      AND column_name IN (
        'display_stage',
        'display_name_target',
        'phone',
        'email',
        'private_reflection'
      )
  ) THEN
    RAISE EXCEPTION 'relationship storage contains derived scale or unrelated PII';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0018_promotion_target_relationship_audit'
  ) <> 1 THEN
    RAISE EXCEPTION 'relationship audit migration was not recorded once';
  END IF;
END
$check$;
