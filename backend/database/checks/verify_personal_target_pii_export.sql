\set ON_ERROR_STOP on

DO $check$
DECLARE
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.personal_target_pii_export_events'
  );
  private_writer regprocedure := pg_catalog.to_regprocedure(
    'app_private.prepare_personal_target_pii_export_v1(uuid,uuid,timestamp with time zone)'
  );
  runtime_bridge regprocedure := pg_catalog.to_regprocedure(
    'app_data.prepare_personal_target_pii_export_v1(text,text,uuid,timestamp with time zone)'
  );
  context_function regprocedure := pg_catalog.to_regprocedure(
    'app_data.list_personal_project_contexts(text,text)'
  );
  trusted_owner oid;
  runtime_role oid;
  actual_names text[];
  actual_types text[];
  expected_names text[] := ARRAY[
    'export_event_id', 'actor_app_user_id', 'workspace_id',
    'export_contract_id', 'authentication_method',
    'authenticated_at_utc', 'result', 'target_count', 'byte_count',
    'prepared_at_utc'
  ]::text[];
  expected_types text[] := ARRAY[
    'uuid', 'uuid', 'uuid', 'text', 'text', 'timestamp with time zone',
    'text', 'integer', 'integer', 'timestamp with time zone'
  ]::text[];
  function_oid oid;
BEGIN
  IF audit_table IS NULL OR private_writer IS NULL OR runtime_bridge IS NULL
    OR context_function IS NULL
  THEN
    RAISE EXCEPTION 'personal target PII export objects are incomplete';
  END IF;

  SELECT procedure_row.proowner INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT role_row.oid INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  SELECT
    array_agg(attribute_row.attname ORDER BY attribute_row.attnum),
    array_agg(pg_catalog.format_type(attribute_row.atttypid, NULL)
      ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = audit_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;
  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
  THEN
    RAISE EXCEPTION 'personal target PII export audit columns drifted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid = audit_table
      AND relation_row.relowner <> trusted_owner
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'f'
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = audit_table
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'project_id', 'promotion_target_id', 'target_id', 'display_name',
        'phone', 'email', 'payload', 'file_bytes', 'content_hash',
        'field_hash', 'target_hash'
      )
  ) THEN
    RAISE EXCEPTION 'personal target PII export audit contains forbidden data';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table
      AND trigger_row.tgname = 'personal_target_pii_export_events_immutable'
      AND NOT trigger_row.tgisinternal
      AND trigger_row.tgenabled = 'O'
      AND (trigger_row.tgtype & 26) = 26
      AND trigger_row.tgfoid = pg_catalog.to_regprocedure(
        'app_private.reject_personal_target_pii_export_mutation_v1()'
      )
  ) THEN
    RAISE EXCEPTION 'personal target PII export audit immutability is missing';
  END IF;

  FOR function_oid IN SELECT unnest(ARRAY[
    private_writer,
    runtime_bridge,
    'app_private.reject_personal_target_pii_export_mutation_v1()'::regprocedure
  ]::oid[])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid = function_oid
        AND procedure_row.proowner = trusted_owner
    ) THEN
      RAISE EXCEPTION 'personal target PII export function owner drifted';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid IN (private_writer, runtime_bridge)
      AND (
        procedure_row.prorettype <> 'bytea'::regtype
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, app_data']::text[]
      )
  ) OR NOT (
    SELECT procedure_row.prosecdef FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = runtime_bridge
  ) OR (
    SELECT procedure_row.prosecdef FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = private_writer
  ) THEN
    RAISE EXCEPTION 'personal target PII export function boundary drifted';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', runtime_bridge, 'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', private_writer, 'EXECUTE'
    )
    OR pg_catalog.has_schema_privilege(
      'tongxingzhe_runtime', 'app_private', 'USAGE'
    )
    OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime', audit_table, 'SELECT,INSERT,UPDATE,DELETE'
    )
  THEN
    RAISE EXCEPTION 'personal target PII export runtime ACL is too broad or incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
      procedure_row.proacl,
      pg_catalog.acldefault('f', procedure_row.proowner)
    )) AS privilege_row
    WHERE procedure_row.oid IN (private_writer, runtime_bridge,
      'app_private.reject_personal_target_pii_export_mutation_v1()'::regprocedure)
      AND privilege_row.grantee IN (0, runtime_role)
      AND (privilege_row.grantee = 0 OR procedure_row.oid <> runtime_bridge)
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
      relation_row.relacl,
      pg_catalog.acldefault('r', relation_row.relowner)
    )) AS privilege_row
    WHERE relation_row.oid = audit_table
      AND privilege_row.grantee IN (0, runtime_role)
  ) THEN
    RAISE EXCEPTION 'personal target PII export exposes private objects';
  END IF;

  IF position(
      '''export_target_pii''' IN pg_catalog.pg_get_functiondef(context_function)
    ) = 0
  THEN
    RAISE EXCEPTION 'personal project context omits export capability';
  END IF;

  IF (
    SELECT count(*) FROM app_migrations.schema_migrations
    WHERE version = '0112_personal_target_pii_export'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal target PII export migration was not recorded once';
  END IF;
END
$check$;
