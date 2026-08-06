\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass(
    'app_data.promotion_target_institution_relationships'
  ) IS NULL OR to_regclass(
    'app_data.promotion_target_institution_relation_revisions'
  ) IS NULL THEN
    RAISE EXCEPTION 'person-to-institution relationship tables are missing';
  END IF;

  IF to_regprocedure(
    'app_data.list_assigned_target_institution_relationships(uuid,uuid,uuid)'
  ) IS NULL OR to_regprocedure(
    'app_data.create_target_institution_relationship(uuid,uuid,uuid,uuid,uuid,text,text,text)'
  ) IS NULL OR to_regprocedure(
    'app_data.end_target_institution_relationship(uuid,uuid,uuid,uuid,integer,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'person-to-institution relationship functions are missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.list_assigned_target_institution_relationships(uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.create_target_institution_relationship(uuid,uuid,uuid,uuid,uuid,text,text,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.end_target_institution_relationship(uuid,uuid,uuid,uuid,integer,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_institution_relation_document(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime person-to-institution function boundary is unsafe';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_institution_relationships',
    'SELECT,INSERT,UPDATE,DELETE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.promotion_target_institution_relation_revisions',
    'SELECT,INSERT,UPDATE,DELETE'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass person-to-institution functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_data'
      AND indexname =
        'promotion_target_one_active_institution_relation_kind'
      AND indexdef ILIKE '%WHERE (ended_at IS NULL)%'
  ) THEN
    RAISE EXCEPTION 'active relationship uniqueness is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_institution_relationships'::regclass
      AND tgname = 'promotion_target_institution_relation_valid'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid =
      'app_data.promotion_target_institution_relation_revisions'::regclass
      AND tgname =
        'promotion_target_institution_relation_revisions_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'person-to-institution history protection is missing';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name IN (
        'promotion_target_institution_relationships',
        'promotion_target_institution_relation_revisions'
      )
      AND column_name IN (
        'display_name',
        'phone',
        'email',
        'project_id',
        'contact_id',
        'relationship_stage'
      )
  ) THEN
    RAISE EXCEPTION 'institution relationship mixes PII, project, or contact facts';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0019_person_institution_relationships'
  ) <> 1 THEN
    RAISE EXCEPTION 'person-to-institution migration was not recorded once';
  END IF;
END
$check$;
