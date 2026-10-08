\set ON_ERROR_STOP on

DO $check$
DECLARE
  previews_table regclass := pg_catalog.to_regclass(
    'app_private.personal_target_csv_import_previews'
  );
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.personal_target_csv_import_request_claims'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.personal_target_csv_import_audit_events'
  );
  preview_bridge regprocedure := pg_catalog.to_regprocedure(
    'app_data.preview_personal_target_csv_import_v1(text,text,uuid,jsonb)'
  );
  confirm_bridge regprocedure := pg_catalog.to_regprocedure(
    'app_data.confirm_personal_target_csv_import_v1(text,text,uuid,uuid,uuid,jsonb,jsonb)'
  );
  trusted_owner oid;
  runtime_role oid;
  function_oid oid;
  actual_names text[];
  actual_types text[];
  expected_names text[];
  expected_types text[];
  preview_checks text[];
  claim_checks text[];
  audit_checks text[];
BEGIN
  IF previews_table IS NULL OR claims_table IS NULL OR audit_table IS NULL
    OR preview_bridge IS NULL OR confirm_bridge IS NULL
  THEN
    RAISE EXCEPTION 'personal target CSV import objects are incomplete';
  END IF;

  SELECT procedure_row.proowner
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT role_row.oid
  INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (previews_table, claims_table, audit_table)
      AND relation_row.relowner <> trusted_owner
  ) THEN
    RAISE EXCEPTION 'personal target CSV import table owner drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS column_row
    WHERE column_row.attrelid IN (previews_table, claims_table, audit_table)
      AND column_row.attnum > 0
      AND NOT column_row.attisdropped
      AND column_row.attname IN (
        'target_type', 'display_name', 'phone', 'email', 'row_values',
        'canonical_rows', 'source_filename', 'csv_bytes'
      )
  ) THEN
    RAISE EXCEPTION 'personal target CSV import private rows contain PII fields';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid IN (previews_table, claims_table, audit_table)
      AND constraint_row.contype = 'f'
  ) THEN
    RAISE EXCEPTION 'personal target CSV import private rows reference shared roots';
  END IF;

  SELECT array_agg(pg_catalog.pg_get_constraintdef(oid))
  INTO preview_checks
  FROM pg_catalog.pg_constraint
  WHERE conrelid = previews_table AND contype = 'c';
  SELECT array_agg(pg_catalog.pg_get_constraintdef(oid))
  INTO claim_checks
  FROM pg_catalog.pg_constraint
  WHERE conrelid = claims_table AND contype = 'c';
  SELECT array_agg(pg_catalog.pg_get_constraintdef(oid))
  INTO audit_checks
  FROM pg_catalog.pg_constraint
  WHERE conrelid = audit_table AND contype = 'c';
  IF cardinality(preview_checks) < 5
    OR cardinality(claim_checks) < 6
    OR cardinality(audit_checks) < 8
    OR array_to_string(preview_checks, ' ') NOT LIKE '%row_count%500%'
    OR array_to_string(preview_checks, ' ') NOT LIKE '%expires_at_utc%previewed_at_utc%15%'
    OR array_to_string(claim_checks, ' ') NOT LIKE '%outcome%confirmed%stale_preview%'
    OR array_to_string(audit_checks, ' ') NOT LIKE '%source_kind%csv%'
    OR array_to_string(audit_checks, ' ') NOT LIKE '%phase%preview%confirm%'
  THEN
    RAISE EXCEPTION 'personal target CSV import key constraints are incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      (previews_table, 'personal_target_csv_import_previews_immutable'),
      (claims_table, 'personal_target_csv_import_request_claims_immutable'),
      (audit_table, 'personal_target_csv_import_audit_events_immutable')
    ) AS expected(relation_oid, trigger_name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = expected.relation_oid
        AND trigger_row.tgname = expected.trigger_name
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgenabled = 'O'
        AND (trigger_row.tgtype & 26) = 26
        AND trigger_row.tgfoid = pg_catalog.to_regprocedure(
          'app_private.reject_personal_target_csv_import_mutation_v1()'
        )
    )
  ) THEN
    RAISE EXCEPTION 'personal target CSV import immutable triggers are missing';
  END IF;

  FOR function_oid IN
    SELECT unnest(ARRAY[
      preview_bridge,
      confirm_bridge,
      'app_private.reject_personal_target_csv_import_mutation_v1()'::regprocedure,
      'app_private.canonical_personal_target_csv_import_rows_v1(jsonb)'::regprocedure,
      'app_private.personal_target_csv_import_fingerprint_v1(uuid,jsonb)'::regprocedure,
      'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure,
      'app_private.resolve_personal_target_csv_import_context_v1(text,text,uuid)'::regprocedure,
      'app_private.personal_target_csv_import_actions_v1(jsonb,integer[],integer)'::regprocedure
    ]::oid[])
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid = function_oid
        AND procedure_row.proowner = trusted_owner
    ) THEN
      RAISE EXCEPTION 'personal target CSV import function owner drifted';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE (
      procedure_row.oid IN (preview_bridge, confirm_bridge)
      AND (
        NOT procedure_row.prosecdef
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, app_data']::text[]
      )
    ) OR (
      procedure_row.oid =
        'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure
      AND (
        NOT procedure_row.prosecdef
        OR procedure_row.provolatile <> 's'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, app_data']::text[]
      )
    ) OR (
      procedure_row.oid =
        'app_private.resolve_personal_target_csv_import_context_v1(text,text,uuid)'::regprocedure
      AND (
        procedure_row.prosecdef
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, app_data']::text[]
      )
    ) OR (
      procedure_row.oid IN (
        'app_private.canonical_personal_target_csv_import_rows_v1(jsonb)'::regprocedure,
        'app_private.personal_target_csv_import_fingerprint_v1(uuid,jsonb)'::regprocedure,
        'app_private.personal_target_csv_import_actions_v1(jsonb,integer[],integer)'::regprocedure
      ) AND (
        procedure_row.prosecdef
        OR procedure_row.provolatile <> 'i'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
      )
    ) OR (
      procedure_row.oid =
        'app_private.reject_personal_target_csv_import_mutation_v1()'::regprocedure
      AND (
        procedure_row.prosecdef
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
      )
    )
  ) THEN
    RAISE EXCEPTION 'personal target CSV import function boundary drifted';
  END IF;

  FOR function_oid IN
    SELECT unnest(ARRAY[preview_bridge, confirm_bridge]::oid[])
  LOOP
    SELECT
      array_agg(argument_row.argument_name ORDER BY argument_row.ordinality),
      array_agg(
        pg_catalog.format_type(argument_row.argument_type, NULL)
        ORDER BY argument_row.ordinality
      )
    INTO actual_names, actual_types
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL unnest(
      procedure_row.proallargtypes,
      procedure_row.proargmodes,
      procedure_row.proargnames
    ) WITH ORDINALITY AS argument_row(
      argument_type, argument_mode, argument_name, ordinality
    )
    WHERE procedure_row.oid = function_oid
      AND argument_row.argument_mode = 't';

    IF function_oid = preview_bridge THEN
      expected_names := ARRAY[
        'contract_id', 'preview_id', 'row_count', 'hinted_rows',
        'previewed_at_utc', 'expires_at_utc'
      ]::text[];
      expected_types := ARRAY[
        'text', 'uuid', 'integer', 'integer[]',
        'timestamp with time zone', 'timestamp with time zone'
      ]::text[];
    ELSE
      expected_names := ARRAY[
        'contract_id', 'preview_id', 'request_id', 'outcome', 'row_count',
        'hint_count', 'created_count', 'created_targets', 'completed_at_utc'
      ]::text[];
      expected_types := ARRAY[
        'text', 'uuid', 'uuid', 'text', 'integer', 'integer', 'integer',
        'jsonb', 'timestamp with time zone'
      ]::text[];
    END IF;

    IF actual_names IS DISTINCT FROM expected_names
      OR actual_types IS DISTINCT FROM expected_types
    THEN
      RAISE EXCEPTION 'personal target CSV import result fields drifted';
    END IF;
  END LOOP;

  IF pg_catalog.has_function_privilege('tongxingzhe_runtime', preview_bridge, 'EXECUTE') = false
    OR pg_catalog.has_function_privilege('tongxingzhe_runtime', confirm_bridge, 'EXECUTE') = false
    OR pg_catalog.has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime', previews_table, 'SELECT,INSERT,UPDATE,DELETE'
    ) OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime', claims_table, 'SELECT,INSERT,UPDATE,DELETE'
    ) OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime', audit_table, 'SELECT,INSERT,UPDATE,DELETE'
    )
  THEN
    RAISE EXCEPTION 'personal target CSV import runtime ACL is too broad or incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(
        procedure_row.proacl,
        pg_catalog.acldefault('f', procedure_row.proowner)
      )
    ) AS privilege_row
    WHERE procedure_row.oid IN (
        preview_bridge, confirm_bridge,
        'app_private.reject_personal_target_csv_import_mutation_v1()'::regprocedure,
        'app_private.canonical_personal_target_csv_import_rows_v1(jsonb)'::regprocedure,
        'app_private.personal_target_csv_import_fingerprint_v1(uuid,jsonb)'::regprocedure,
        'app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb)'::regprocedure,
        'app_private.resolve_personal_target_csv_import_context_v1(text,text,uuid)'::regprocedure,
        'app_private.personal_target_csv_import_actions_v1(jsonb,integer[],integer)'::regprocedure
      )
      AND privilege_row.grantee IN (0, runtime_role)
      AND (
        privilege_row.grantee = 0
        OR procedure_row.oid NOT IN (preview_bridge, confirm_bridge)
        OR privilege_row.privilege_type <> 'EXECUTE'
      )
  ) THEN
    RAISE EXCEPTION 'personal target CSV import functions expose PUBLIC or private helpers';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(
        relation_row.relacl,
        pg_catalog.acldefault('r', relation_row.relowner)
      )
    ) AS privilege_row
    WHERE relation_row.oid IN (previews_table, claims_table, audit_table)
      AND privilege_row.grantee IN (0, runtime_role)
  ) THEN
    RAISE EXCEPTION 'personal target CSV import private tables are exposed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(
        procedure_row.proacl,
        pg_catalog.acldefault('f', procedure_row.proowner)
      )
    ) AS privilege_row
    WHERE procedure_row.oid IN (preview_bridge, confirm_bridge)
      AND privilege_row.grantee = 0
  ) THEN
    RAISE EXCEPTION 'personal target CSV import bridges are executable by PUBLIC';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0111_personal_target_csv_import'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal target CSV import migration was not recorded once';
  END IF;
END
$check$;
