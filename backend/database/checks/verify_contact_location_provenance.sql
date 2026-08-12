-- 验证 6S 地点来源的结构、追加边界和最小权限。
-- 具体的 source shape、历史回填和并发写入由 0039 fixture 与独立脚本验证。
DO $check$
DECLARE
  provenance_table oid := to_regclass(
    'app_data.contact_location_provenance'
  );
  required_column text;
  source_pk_ok boolean;
  revision_unique_ok boolean;
  revision_fk_ok boolean;
  region_fk_ok boolean;
  check_definition text;
  source_trigger_count integer;
  revision_trigger_count integer;
  provenance_function_count integer;
  function_row record;
  sequence_row record;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_contact_provenance_writer'
      AND NOT rolcanlogin
      AND NOT rolsuper
      AND NOT rolcreatedb
      AND NOT rolcreaterole
      AND NOT rolinherit
      AND NOT rolreplication
      AND NOT rolbypassrls
  ) THEN
    RAISE EXCEPTION
      'contact provenance writer role is missing or over-privileged';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    WHERE writer_role.rolname = 'tongxingzhe_contact_provenance_writer'
  ) THEN
    RAISE EXCEPTION 'contact provenance writer role must not have members';
  END IF;

  IF provenance_table IS NULL THEN
    RAISE EXCEPTION 'contact location provenance table is missing';
  END IF;

  FOREACH required_column IN ARRAY ARRAY[
    'source_id',
    'contact_id',
    'revision_number',
    'revision_kind',
    'location_kind',
    'evidence_kind',
    'place_name',
    'latitude',
    'longitude',
    'accuracy_meters',
    'smallest_region_id',
    'region_tree_version',
    'region_tree_content_fingerprint',
    'resolver_contract_version',
    'recorded_at_utc'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute AS attribute_row
      WHERE attribute_row.attrelid = provenance_table
        AND attribute_row.attname = required_column
        AND NOT attribute_row.attisdropped
    ) THEN
      RAISE EXCEPTION 'provenance column is missing: %', required_column;
    END IF;
  END LOOP;

  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = provenance_table
      AND constraint_row.contype = 'p'
      AND (
        SELECT array_agg(
          attribute_row.attname::text ORDER BY key_row.ordinality
        )
        FROM unnest(constraint_row.conkey) WITH ORDINALITY
          AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute_row
          ON attribute_row.attrelid = constraint_row.conrelid
         AND attribute_row.attnum = key_row.attnum
      ) = ARRAY['source_id']::text[]
  ) INTO source_pk_ok;
  IF NOT source_pk_ok THEN
    RAISE EXCEPTION 'provenance source_id primary key is missing';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = provenance_table
      AND index_row.indisunique
      AND index_row.indnatts = 2
      AND (
        SELECT array_agg(
          attribute_row.attname::text ORDER BY key_row.ordinality
        )
        FROM unnest(index_row.indkey) WITH ORDINALITY
          AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute_row
          ON attribute_row.attrelid = index_row.indrelid
         AND attribute_row.attnum = key_row.attnum
      ) = ARRAY['contact_id', 'revision_number']::text[]
  ) INTO revision_unique_ok;
  IF NOT revision_unique_ok THEN
    RAISE EXCEPTION
      'provenance must have a unique contact_id plus revision_number key';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = provenance_table
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = 'app_data.contact_revisions'::regclass
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE
        '%contact_id%revision_number%'
  ) INTO revision_fk_ok;
  IF NOT revision_fk_ok THEN
    RAISE EXCEPTION
      'provenance must reference the immutable contact revision';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = provenance_table
      AND constraint_row.contype = 'f'
      AND constraint_row.confrelid = 'app_data.canonical_region_versions'::regclass
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ILIKE
        '%smallest_region_id%region_tree_version%'
  ) INTO region_fk_ok;
  IF NOT region_fk_ok THEN
    RAISE EXCEPTION
      'provenance must reference a versioned canonical region node';
  END IF;

  SELECT string_agg(
    pg_catalog.pg_get_constraintdef(constraint_row.oid), ' | '
    ORDER BY constraint_row.oid
  ) INTO check_definition
  FROM pg_catalog.pg_constraint AS constraint_row
  WHERE constraint_row.conrelid = provenance_table
    AND constraint_row.contype = 'c';

  FOREACH required_column IN ARRAY ARRAY[
    'resolved_from_coordinates',
    'resolved_region_only',
    'pending_coordinates',
    'not_applicable',
    'legacy_incomplete',
    'resolved',
    'pending_resolution',
    'not_applicable'
  ]
  LOOP
    IF coalesce(check_definition, '') NOT LIKE '%' || required_column || '%' THEN
      RAISE EXCEPTION
        'provenance shape checks do not enumerate required value: %',
        required_column;
    END IF;
  END LOOP;

  -- The source table is history. A trigger must reject both UPDATE and DELETE,
  -- including attempts made after setting an application-private GUC.
  SELECT count(*) INTO source_trigger_count
  FROM pg_catalog.pg_trigger AS trigger_row
  WHERE trigger_row.tgrelid = provenance_table
    AND NOT trigger_row.tgisinternal
    AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ILIKE '%UPDATE%'
    AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ILIKE '%DELETE%';
  IF source_trigger_count = 0 THEN
    RAISE EXCEPTION
      'provenance table has no UPDATE/DELETE append-only guard trigger';
  END IF;

  -- Accepted revisions must be captured by a trusted database seam. Do not
  -- hard-code its function name here: a forward fix may rename the helper,
  -- while its SECURITY DEFINER body still references this table.
  SELECT count(*) INTO revision_trigger_count
  FROM pg_catalog.pg_trigger AS trigger_row
  JOIN pg_catalog.pg_proc AS procedure_row
    ON procedure_row.oid = trigger_row.tgfoid
  WHERE trigger_row.tgrelid = 'app_data.contact_revisions'::regclass
    AND NOT trigger_row.tgisinternal
    AND pg_catalog.pg_get_functiondef(procedure_row.oid) ILIKE
      '%contact_location_provenance%';
  IF revision_trigger_count = 0 THEN
    RAISE EXCEPTION
      'contact revision does not have a provenance capture trigger';
  END IF;

  SELECT count(*) INTO provenance_function_count
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_namespace AS namespace_row
    ON namespace_row.oid = procedure_row.pronamespace
  WHERE namespace_row.nspname IN ('app_data', 'app_private')
    AND procedure_row.prosecdef
    AND pg_catalog.pg_get_functiondef(procedure_row.oid) ILIKE
      '%contact_location_provenance%';
  IF provenance_function_count = 0 THEN
    RAISE EXCEPTION
      'no SECURITY DEFINER provenance maintenance seam was found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE namespace_row.nspname = 'app_private'
      AND procedure_row.proname = 'capture_contact_location_provenance_v1'
      AND procedure_row.prosecdef
      AND owner_role.rolname = 'tongxingzhe_contact_provenance_writer'
  ) THEN
    RAISE EXCEPTION
      'provenance capture helper is not owned by the dedicated writer role';
  END IF;

  -- Every provenance helper must be owned by a non-runtime role, pin its
  -- search_path, and remain unavailable to the client-facing runtime role.
  FOR function_row IN
    SELECT procedure_row.oid,
           namespace_row.nspname AS namespace_name,
           procedure_row.proname,
           pg_catalog.pg_get_function_identity_arguments(procedure_row.oid)
             AS identity_arguments,
           procedure_row.proconfig,
           owner_role.rolname AS owner_name
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    JOIN pg_catalog.pg_roles AS owner_role
      ON owner_role.oid = procedure_row.proowner
    WHERE namespace_row.nspname IN ('app_data', 'app_private')
      AND procedure_row.prosecdef
      AND pg_catalog.pg_get_functiondef(procedure_row.oid) ILIKE
        '%contact_location_provenance%'
  LOOP
    IF function_row.owner_name = 'tongxingzhe_runtime' THEN
      RAISE EXCEPTION 'runtime role owns provenance helper: %.%',
        function_row.namespace_name, function_row.proname;
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM unnest(coalesce(function_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
    ) THEN
      RAISE EXCEPTION 'provenance helper has mutable search_path: %.%',
        function_row.namespace_name, function_row.proname;
    END IF;
    IF has_function_privilege(
      'tongxingzhe_runtime',
      function_row.oid,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'runtime role can execute provenance helper: %.%',
        function_row.namespace_name, function_row.proname;
    END IF;
  END LOOP;

  FOREACH required_column IN ARRAY ARRAY[
    'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
  ]
  LOOP
    IF has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.contact_location_provenance',
      required_column
    ) THEN
      RAISE EXCEPTION 'runtime role has provenance table privilege: %',
        required_column;
    END IF;
  END LOOP;

  IF NOT has_table_privilege(
    'tongxingzhe_contact_provenance_writer',
    'app_data.contact_location_provenance',
    'INSERT'
  ) OR has_table_privilege(
    'tongxingzhe_contact_provenance_writer',
    'app_data.contact_location_provenance',
    'SELECT'
  ) THEN
    RAISE EXCEPTION
      'provenance writer role does not have the intended narrow table grant';
  END IF;

  -- Identity/serial sequences must not become a side door around the table
  -- contract. Find sequences owned by a source-table column rather than
  -- assuming a generated-name convention.
  FOR sequence_row IN
    SELECT sequence_class.oid,
           sequence_namespace.nspname,
           sequence_class.relname
    FROM pg_catalog.pg_class AS sequence_class
    JOIN pg_catalog.pg_namespace AS sequence_namespace
      ON sequence_namespace.oid = sequence_class.relnamespace
    JOIN pg_catalog.pg_depend AS dependency_row
      ON dependency_row.classid = 'pg_class'::regclass
     AND dependency_row.objid = sequence_class.oid
     AND dependency_row.refobjid = provenance_table
    WHERE sequence_class.relkind = 'S'
  LOOP
    IF has_sequence_privilege(
      'tongxingzhe_runtime',
      format('%I.%I', sequence_row.nspname, sequence_row.relname),
      'USAGE,SELECT,UPDATE'
    ) THEN
      RAISE EXCEPTION 'runtime role can access provenance sequence: %.%',
        sequence_row.nspname, sequence_row.relname;
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0039_contact_location_provenance'
  ) <> 1 THEN
    RAISE EXCEPTION
      'contact location provenance migration was not recorded exactly once';
  END IF;
END
$check$;
