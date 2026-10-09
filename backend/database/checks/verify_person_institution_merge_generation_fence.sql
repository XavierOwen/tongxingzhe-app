\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  runtime_role oid;
  relation_table regclass := 'app_data.promotion_target_institution_relationships'::regclass;
  revision_table regclass := 'app_data.promotion_target_institution_relation_revisions'::regclass;
  function_oid regprocedure;
  function_name text;
  binding_column text;
  trigger_count integer;
BEGIN
  SELECT proowner INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT oid INTO STRICT runtime_role FROM pg_catalog.pg_roles
  WHERE rolname = 'tongxingzhe_runtime';

  FOREACH binding_column IN ARRAY ARRAY[
    'person_merge_generation_id', 'institution_merge_generation_id'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid = relation_table AND attname = binding_column
        AND NOT attisdropped AND atttypid = 'uuid'::regtype
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute
      WHERE attrelid = revision_table AND attname = binding_column
        AND NOT attisdropped AND atttypid = 'uuid'::regtype
    ) OR has_column_privilege('public', relation_table, binding_column, 'SELECT')
      OR has_column_privilege(runtime_role, relation_table, binding_column, 'SELECT')
      OR has_column_privilege('public', revision_table, binding_column, 'SELECT')
      OR has_column_privilege(runtime_role, revision_table, binding_column, 'SELECT')
    THEN
      RAISE EXCEPTION 'relationship merge binding column missing or exposed: %', binding_column;
    END IF;
  END LOOP;

  IF has_table_privilege('public', relation_table, 'INSERT,UPDATE,DELETE')
    OR has_table_privilege(runtime_role, relation_table, 'INSERT,UPDATE,DELETE')
    OR has_table_privilege('public', revision_table, 'INSERT,UPDATE,DELETE')
    OR has_table_privilege(runtime_role, revision_table, 'INSERT,UPDATE,DELETE')
  THEN
    RAISE EXCEPTION 'relationship binding tables are directly writable';
  END IF;

  FOREACH function_name IN ARRAY ARRAY[
    'app_private.acquire_personal_target_merge_generation_fence_v1()',
    'app_private.bind_personal_target_merge_generation_v1()',
    'app_private.bind_person_institution_merge_generations_v1()',
    'app_private.reject_person_institution_merge_generation_change_v1()'
  ] LOOP
    function_oid := to_regprocedure(function_name);
    IF function_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc
      WHERE oid = function_oid AND proowner = trusted_owner
    ) OR has_function_privilege('public', function_oid, 'EXECUTE')
      OR has_function_privilege(runtime_role, function_oid, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'relationship binding function boundary drifted: %', function_name;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.acquire_personal_target_merge_generation_fence_v1()'::regprocedure
      AND prosecdef AND provolatile = 'v'
      AND proconfig @> ARRAY['search_path=pg_catalog, app_private']
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc
    WHERE oid = 'app_private.bind_personal_target_merge_generation_v1()'::regprocedure
      AND prosecdef AND provolatile = 'v'
      AND proconfig @> ARRAY['search_path=pg_catalog, app_data, app_private']
  ) THEN
    RAISE EXCEPTION 'fence or generic binding function security contract drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = relation_table
      AND conname = 'pt_institution_relation_person_merge_member_fk'
      AND contype = 'f'
      AND confrelid = 'app_private.personal_target_merge_generation_members_v1'::regclass
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = relation_table
      AND conname = 'pt_institution_relation_institution_merge_member_fk'
      AND contype = 'f'
      AND confrelid = 'app_private.personal_target_merge_generation_members_v1'::regclass
  ) THEN
    RAISE EXCEPTION 'relationship endpoint generation-member constraints are missing';
  END IF;

  SELECT count(*) INTO trigger_count
  FROM pg_catalog.pg_trigger
  WHERE NOT tgisinternal AND (
    (tgrelid = relation_table AND tgname IN (
      'pt_institution_relation_bind_generations',
      'pt_institution_relation_generations_immutable'
    )) OR (tgrelid = revision_table AND tgname IN (
      'pt_institution_relation_revision_bind_generations',
      'pt_institution_relation_revision_generations_immutable'
    ))
  );
  IF trigger_count <> 4 THEN
    RAISE EXCEPTION 'relationship generation binding triggers missing: %', trigger_count;
  END IF;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0115_person_institution_merge_generation_fence') <> 1
  THEN
    RAISE EXCEPTION '0115 migration was not recorded once';
  END IF;
END
$check$;

SELECT 'person/institution merge generation fence: passed' AS result;
