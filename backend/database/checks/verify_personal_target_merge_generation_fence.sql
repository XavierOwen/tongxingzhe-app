\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  runtime_role oid;
  table_name text;
  table_oid regclass;
  trigger_count integer;
  function_name text;
  function_oid regprocedure;
BEGIN
  SELECT procedure_row.proowner INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT role_row.oid INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  FOREACH table_name IN ARRAY ARRAY[
    'personal_target_merge_generation_fence_v1',
    'personal_target_merge_generations_v1',
    'personal_target_merge_generation_members_v1',
    'personal_target_merge_active_members_v1'
  ] LOOP
    table_oid := pg_catalog.to_regclass('app_private.' || table_name);
    IF table_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation_row
      WHERE relation_row.oid = table_oid
        AND relation_row.relowner = trusted_owner
    ) OR has_table_privilege(
      'public', table_oid,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) OR has_table_privilege(
      runtime_role, table_oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) THEN
      RAISE EXCEPTION 'merge generation private table boundary drifted: %', table_name;
    END IF;
  END LOOP;

  FOREACH function_name IN ARRAY ARRAY[
    'app_private.reject_personal_target_merge_history_mutation_v1()',
    'app_private.resolve_personal_target_merge_generation_v1(uuid,uuid,text)',
    'app_private.bind_personal_target_merge_generation_v1()',
    'app_private.reject_personal_target_merge_generation_change_v1()',
    'app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid)'
  ] LOOP
    function_oid := pg_catalog.to_regprocedure(function_name);
    IF function_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid = function_oid
        AND procedure_row.proowner = trusted_owner
    ) OR has_function_privilege('public', function_oid, 'EXECUTE')
      OR has_function_privilege(runtime_role, function_oid, 'EXECUTE')
    THEN
      RAISE EXCEPTION 'merge generation private function boundary drifted: %',
        function_name;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid IN (
      'app_private.personal_target_merge_generation_fence_v1'::regclass,
      'app_private.personal_target_merge_generations_v1'::regclass,
      'app_private.personal_target_merge_generation_members_v1'::regclass,
      'app_private.personal_target_merge_active_members_v1'::regclass
    ) AND attribute_row.attnum > 0 AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'target_type_value', 'display_name', 'phone', 'email', 'name',
        'phone_number', 'email_address', 'payload', 'snapshot', 'raw_value',
        'content_hash', 'field_hash', 'request_hash'
      )
  ) THEN
    RAISE EXCEPTION 'merge generation ledger contains target values or PII';
  END IF;

  IF to_regclass('app_data.contact_target_links') IS NULL
    OR to_regclass('app_data.promotion_target_project_relationships') IS NULL
    OR to_regclass('app_data.promotion_target_relationship_revisions') IS NULL
  THEN
    RAISE EXCEPTION 'merge generation fact tables are missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'app_data.contact_target_links'::regclass
      AND attname = 'merge_generation_id' AND NOT attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'app_data.promotion_target_project_relationships'::regclass
      AND attname = 'merge_generation_id' AND NOT attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = 'app_data.promotion_target_relationship_revisions'::regclass
      AND attname = 'merge_generation_id' AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'merge generation fact bindings are missing';
  END IF;

  SELECT count(*) INTO trigger_count
  FROM pg_catalog.pg_trigger AS trigger_row
  WHERE NOT trigger_row.tgisinternal AND (
    (trigger_row.tgrelid =
      'app_private.personal_target_merge_generations_v1'::regclass
      AND trigger_row.tgname = 'personal_target_merge_generations_immutable')
    OR (trigger_row.tgrelid =
      'app_private.personal_target_merge_generation_members_v1'::regclass
      AND trigger_row.tgname = 'personal_target_merge_generation_members_immutable')
    OR (trigger_row.tgrelid = 'app_data.contact_target_links'::regclass
      AND trigger_row.tgname = 'contact_target_links_bind_merge_generation')
    OR (trigger_row.tgrelid =
      'app_data.promotion_target_project_relationships'::regclass
      AND trigger_row.tgname =
        'promotion_target_project_relationships_bind_merge_generation')
    OR (trigger_row.tgrelid =
      'app_data.promotion_target_relationship_revisions'::regclass
      AND trigger_row.tgname =
        'promotion_target_relationship_revisions_bind_merge_generation')
    OR (trigger_row.tgrelid = 'app_data.contact_target_links'::regclass
      AND trigger_row.tgname = 'contact_target_links_merge_generation_immutable')
    OR (trigger_row.tgrelid =
      'app_data.promotion_target_project_relationships'::regclass
      AND trigger_row.tgname = 'pt_rel_merge_gen_immutable')
    OR (trigger_row.tgrelid =
      'app_data.promotion_target_relationship_revisions'::regclass
      AND trigger_row.tgname = 'ptr_rev_merge_gen_immutable')
  );
  IF trigger_count <> 8 THEN
    RAISE EXCEPTION 'merge generation binding/immutability triggers missing: %',
      trigger_count;
  END IF;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0114_personal_target_merge_generation_fence') <> 1
  THEN
    RAISE EXCEPTION '0114 migration was not recorded once';
  END IF;
END
$check$;
