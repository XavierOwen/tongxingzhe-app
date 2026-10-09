\set ON_ERROR_STOP on

DO $check$
DECLARE
  receipts_table regclass := pg_catalog.to_regclass(
    'app_private.personal_target_pair_preview_receipts'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.personal_target_pair_preview_audit_events'
  );
  bump_function regprocedure := pg_catalog.to_regprocedure(
    'app_private.bump_promotion_target_profile_revision_v1()'
  );
  validator_function regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamp with time zone)'
  );
  cleanup_function regprocedure := pg_catalog.to_regprocedure(
    'app_private.cleanup_personal_target_pair_preview_receipts_v1()'
  );
  preview_function regprocedure := pg_catalog.to_regprocedure(
    'app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid)'
  );
  context_function regprocedure := pg_catalog.to_regprocedure(
    'app_data.list_personal_project_contexts(text,text)'
  );
  trusted_owner oid;
  runtime_role oid;
  actual_names text[];
  actual_types text[];
  expected_names text[];
  expected_types text[];
  function_oid oid;
  function_definition text;
  facts_position integer;
  timed_position integer;
BEGIN
  IF receipts_table IS NULL OR audit_table IS NULL
    OR bump_function IS NULL OR validator_function IS NULL
    OR cleanup_function IS NULL OR preview_function IS NULL
    OR context_function IS NULL
  THEN
    RAISE EXCEPTION 'personal target pair preview objects are incomplete';
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
  WHERE attribute_row.attrelid = receipts_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;
  expected_names := ARRAY[
    'preview_id', 'actor_app_user_id', 'workspace_id', 'first_target_id',
    'second_target_id', 'first_profile_revision', 'second_profile_revision',
    'first_assignment_id', 'second_assignment_id',
    'first_retention_due_at_utc', 'second_retention_due_at_utc',
    'merge_deadline_at_utc', 'phone_match', 'email_match',
    'previewed_at_utc', 'expires_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'bigint', 'bigint', 'uuid', 'uuid',
    'timestamp with time zone', 'timestamp with time zone',
    'timestamp with time zone', 'boolean', 'boolean',
    'timestamp with time zone', 'timestamp with time zone'
  ]::text[];
  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
  THEN
    RAISE EXCEPTION 'personal target pair preview receipt columns drifted';
  END IF;

  SELECT
    array_agg(attribute_row.attname ORDER BY attribute_row.attnum),
    array_agg(pg_catalog.format_type(attribute_row.atttypid, NULL)
      ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = audit_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;
  expected_names := ARRAY[
    'audit_event_id', 'actor_app_user_id', 'workspace_id', 'operation',
    'outcome', 'target_count', 'match_signal_count', 'occurred_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid', 'uuid', 'uuid', 'text', 'text', 'integer', 'integer',
    'timestamp with time zone'
  ]::text[];
  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
  THEN
    RAISE EXCEPTION 'personal target pair preview audit columns drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (receipts_table, audit_table)
      AND relation_row.relowner <> trusted_owner
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid IN (receipts_table, audit_table)
      AND constraint_row.contype = 'f'
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid IN (receipts_table, audit_table)
      AND attribute_row.attnum > 0
      AND NOT attribute_row.attisdropped
      AND attribute_row.attname IN (
        'target_type', 'display_name', 'phone', 'email', 'name',
        'phone_number', 'email_address', 'project_id', 'promotion_target_id',
        'target_id', 'payload', 'content_hash', 'field_hash', 'target_hash',
        'request_hash', 'error', 'error_code', 'error_message', 'failure_reason'
      )
  ) THEN
    RAISE EXCEPTION 'personal target pair preview private data boundary drifted';
  END IF;

  IF (
    SELECT count(*) FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype IN ('p', 'c')
  ) <> 12 OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'p'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%PRIMARY KEY (preview_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%first_profile_revision% > 0%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%second_profile_revision% > 0%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%first_target_id% < second_target_id%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%phone_match OR email_match%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%merge_deadline_at_utc = LEAST%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%expires_at_utc%previewed_at_utc%15%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%isfinite(first_retention_due_at_utc)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%isfinite(second_retention_due_at_utc)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%isfinite(merge_deadline_at_utc)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%isfinite(previewed_at_utc)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%isfinite(expires_at_utc)%'
  ) THEN
    RAISE EXCEPTION 'personal target pair preview receipt constraints drifted';
  END IF;
  IF (
    SELECT count(*) FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = receipts_table
  ) <> 12 THEN
    RAISE EXCEPTION 'personal target pair preview receipt has unexpected constraints';
  END IF;

  IF (
    SELECT count(*) FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype IN ('p', 'c')
  ) <> 6 OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'p'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%PRIMARY KEY (audit_event_id)%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%operation = ''personal_target_pair_preview''%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%outcome = ''previewed''%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%target_count = 2%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%match_signal_count%1%2%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%isfinite(occurred_at_utc)%'
  ) THEN
    RAISE EXCEPTION 'personal target pair preview audit constraints drifted';
  END IF;
  IF (
    SELECT count(*) FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
  ) <> 6 THEN
    RAISE EXCEPTION 'personal target pair preview audit has unexpected constraints';
  END IF;

  IF (
    SELECT count(*) FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = receipts_table
  ) <> 2 OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_row
    JOIN pg_catalog.pg_class AS index_class
      ON index_class.oid = index_row.indexrelid
    WHERE index_row.indrelid = receipts_table
      AND index_class.relname = 'personal_target_pair_preview_receipts_expiry'
      AND index_row.indisvalid
      AND NOT index_row.indisunique
      AND index_row.indnkeyatts = 2
      AND ARRAY(
        SELECT attribute_row.attname
        FROM unnest(index_row.indkey::smallint[]) WITH ORDINALITY AS key_row(attnum, ordinality)
        JOIN pg_catalog.pg_attribute AS attribute_row
          ON attribute_row.attrelid = receipts_table
         AND attribute_row.attnum = key_row.attnum
        WHERE key_row.ordinality <= index_row.indnkeyatts
        ORDER BY key_row.ordinality
      ) = ARRAY['expires_at_utc', 'preview_id']::name[]
  ) OR (
    SELECT count(*) FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = audit_table
  ) <> 1 THEN
    RAISE EXCEPTION 'personal target pair preview indexes drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = 'app_data.promotion_targets'::regclass
      AND trigger_row.tgname = 'promotion_targets_profile_revision'
      AND NOT trigger_row.tgisinternal
      AND trigger_row.tgenabled = 'O'
      AND trigger_row.tgtype = 19
      AND trigger_row.tgfoid = bump_function
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute AS attribute_row
    WHERE attribute_row.attrelid = 'app_data.promotion_targets'::regclass
      AND attribute_row.attname = 'profile_revision'
      AND attribute_row.atttypid = 'bigint'::regtype
      AND attribute_row.attnotnull
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = 'app_data.promotion_targets'::regclass
      AND constraint_row.contype = 'c'
      AND pg_catalog.pg_get_constraintdef(constraint_row.oid)
        ILIKE '%profile_revision > 0%'
  ) THEN
    RAISE EXCEPTION 'personal target pair profile revision trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = receipts_table
      AND trigger_row.tgname = 'personal_target_pair_preview_receipts_immutable'
      AND NOT trigger_row.tgisinternal
      AND trigger_row.tgenabled = 'O'
      AND trigger_row.tgtype = 19
      AND trigger_row.tgfoid = pg_catalog.to_regprocedure(
        'app_data.reject_promotion_target_audit_mutation()'
      )
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid = audit_table
      AND trigger_row.tgname = 'personal_target_pair_preview_audit_events_immutable'
      AND NOT trigger_row.tgisinternal
      AND trigger_row.tgenabled = 'O'
      AND trigger_row.tgtype = 27
      AND trigger_row.tgfoid = pg_catalog.to_regprocedure(
        'app_data.reject_promotion_target_audit_mutation()'
      )
  ) THEN
    RAISE EXCEPTION 'personal target pair preview immutability triggers drifted';
  END IF;

  FOR function_oid IN SELECT unnest(ARRAY[
    bump_function, validator_function, cleanup_function, preview_function
  ]::oid[])
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid = function_oid
        AND procedure_row.proowner = trusted_owner
    ) THEN
      RAISE EXCEPTION 'personal target pair preview function owner drifted';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = bump_function
      AND (procedure_row.prosecdef OR procedure_row.provolatile <> 'v'
        OR procedure_row.prorettype <> 'trigger'::regtype
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[])
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = validator_function
      AND (procedure_row.prosecdef OR procedure_row.provolatile <> 's'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, app_data']::text[])
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = cleanup_function
      AND (procedure_row.prosecdef OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
        OR procedure_row.prorettype <> 'integer'::regtype)
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = preview_function
      AND (NOT procedure_row.prosecdef OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog, app_data']::text[])
  ) THEN
    RAISE EXCEPTION 'personal target pair preview function boundary drifted';
  END IF;

  FOR function_oid IN SELECT unnest(ARRAY[
    validator_function, preview_function
  ]::oid[])
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

    IF function_oid = validator_function THEN
      expected_names := ARRAY[
        'preview_id', 'actor_app_user_id', 'workspace_id', 'first_target_id',
        'second_target_id', 'first_profile_revision', 'second_profile_revision',
        'first_assignment_id', 'second_assignment_id',
        'first_retention_due_at_utc', 'second_retention_due_at_utc',
        'merge_deadline_at_utc', 'phone_match', 'email_match',
        'previewed_at_utc', 'expires_at_utc'
      ]::text[];
      expected_types := ARRAY[
        'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'bigint', 'bigint', 'uuid', 'uuid',
        'timestamp with time zone', 'timestamp with time zone',
        'timestamp with time zone', 'boolean', 'boolean',
        'timestamp with time zone', 'timestamp with time zone'
      ]::text[];
    ELSE
      expected_names := ARRAY[
        'preview_id', 'first_target_id', 'first_target_type',
        'first_display_name', 'first_phone', 'first_email',
        'second_target_id', 'second_target_type', 'second_display_name',
        'second_phone', 'second_email', 'phone_match', 'email_match',
        'first_retention_due_at_utc', 'second_retention_due_at_utc',
        'merge_deadline_at_utc', 'expiry_consequence', 'previewed_at_utc',
        'expires_at_utc'
      ]::text[];
      expected_types := ARRAY[
        'uuid', 'uuid', 'text', 'text', 'text', 'text', 'uuid', 'text',
        'text', 'text', 'text', 'boolean', 'boolean',
        'timestamp with time zone', 'timestamp with time zone',
        'timestamp with time zone', 'text', 'timestamp with time zone',
        'timestamp with time zone'
      ]::text[];
    END IF;
    IF actual_names IS DISTINCT FROM expected_names
      OR actual_types IS DISTINCT FROM expected_types
    THEN
      RAISE EXCEPTION 'personal target pair preview result fields drifted';
    END IF;
  END LOOP;

  function_definition := pg_catalog.pg_get_functiondef(bump_function);
  IF function_definition NOT ILIKE '%NEW.profile_revision := OLD.profile_revision + 1%'
    OR function_definition NOT ILIKE '%NEW.profile_revision := OLD.profile_revision%'
    OR function_definition NOT ILIKE '%ROW(%'
    OR function_definition NOT ILIKE '%IS DISTINCT FROM ROW(%'
    OR function_definition NOT ILIKE '%NEW.target_type%'
    OR function_definition NOT ILIKE '%NEW.display_name%'
    OR function_definition NOT ILIKE '%NEW.phone%'
    OR function_definition NOT ILIKE '%NEW.email%'
    OR function_definition NOT ILIKE '%NEW.status%'
  THEN
    RAISE EXCEPTION 'personal target pair profile revision behavior drifted';
  END IF;

  function_definition := pg_catalog.pg_get_functiondef(preview_function);
  facts_position := pg_catalog.strpos(function_definition, 'facts AS MATERIALIZED');
  timed_position := pg_catalog.strpos(function_definition, 'timed AS MATERIALIZED');
  IF facts_position = 0 OR timed_position <= facts_position
    OR pg_catalog.strpos(
      pg_catalog.substr(function_definition, timed_position), 'FROM facts'
    ) = 0
    OR (
      pg_catalog.length(function_definition)
      - pg_catalog.length(pg_catalog.replace(
        function_definition, 'clock_timestamp()', ''
      ))
    ) / pg_catalog.length('clock_timestamp()') <> 1
    OR pg_catalog.strpos(function_definition, 'RETURN QUERY') = 0
    OR pg_catalog.strpos(
      pg_catalog.substr(
        function_definition,
        pg_catalog.strpos(function_definition, 'RETURN QUERY') + 12
      ),
      'RETURN QUERY'
    ) > 0
    OR function_definition ILIKE '%LOCK TABLE%'
    OR function_definition ILIKE '%FOR UPDATE%'
    OR function_definition ILIKE '%FOR NO KEY UPDATE%'
    OR function_definition ILIKE '%FOR SHARE%'
    OR function_definition ILIKE '%FOR KEY SHARE%'
  THEN
    RAISE EXCEPTION 'personal target pair preview must remain one lock-free timed statement';
  END IF;

  IF pg_catalog.strpos(
      pg_catalog.pg_get_functiondef(context_function),
      '''manage_assigned_target_merges'''
    ) = 0
  THEN
    RAISE EXCEPTION 'personal project context omits merge capability';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
      relation_row.relacl,
      pg_catalog.acldefault('r', relation_row.relowner)
    )) AS privilege_row
    WHERE relation_row.oid IN (receipts_table, audit_table)
      AND privilege_row.grantee IN (0, runtime_role)
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(
      procedure_row.proacl,
      pg_catalog.acldefault('f', procedure_row.proowner)
    )) AS privilege_row
    WHERE procedure_row.oid IN (
      bump_function, validator_function, cleanup_function, preview_function
    )
      AND privilege_row.grantee IN (0, runtime_role)
      AND privilege_row.privilege_type = 'EXECUTE'
  ) OR pg_catalog.has_table_privilege(
    'tongxingzhe_runtime', receipts_table, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR pg_catalog.has_table_privilege(
    'tongxingzhe_runtime', audit_table, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ) OR pg_catalog.has_function_privilege(
    'tongxingzhe_runtime', bump_function, 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'tongxingzhe_runtime', validator_function, 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'tongxingzhe_runtime', cleanup_function, 'EXECUTE'
  ) OR pg_catalog.has_function_privilege(
    'tongxingzhe_runtime', preview_function, 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'personal target pair preview private objects are exposed';
  END IF;

  IF (
    SELECT count(*) FROM app_migrations.schema_migrations
    WHERE version = '0113_personal_target_pair_preview'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal target pair preview migration was not recorded once';
  END IF;
END
$check$;
