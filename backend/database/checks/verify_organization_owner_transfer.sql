\set ON_ERROR_STOP on

DO $check$
DECLARE
  claims_table regclass := to_regclass(
    'app_private.organization_owner_transfer_request_claims'
  );
  tombstones_table regclass := to_regclass(
    'app_private.organization_owner_transfer_request_tombstones'
  );
  audit_table regclass := to_regclass(
    'app_private.organization_owner_transfer_audit_events'
  );
  membership_validator regprocedure := to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_writer regprocedure := to_regprocedure(
    'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'
  );
  runtime_bridge regprocedure := to_regprocedure(
    'app_data.transfer_organization_owner_for_identity_v1(text,text,uuid,uuid,uuid)'
  );
  claim_guard regprocedure := to_regprocedure(
    'app_private.protect_organization_owner_transfer_request_claim_v1()'
  );
  tombstone_guard regprocedure := to_regprocedure(
    'app_private.protect_organization_owner_transfer_request_tombstone_v1()'
  );
  audit_guard regprocedure := to_regprocedure(
    'app_private.protect_organization_owner_transfer_audit_event_v1()'
  );
  trusted_owner oid;
  runtime_role oid;
  expected_names text[];
  expected_types text[];
  expected_not_null boolean[];
  actual_names text[];
  actual_types text[];
  actual_not_null boolean[];
  actual_result_names text[];
  actual_result_types text[];
  function_oid oid;
  function_row record;
  private_definition text;
  bridge_definition text;
BEGIN
  IF claims_table IS NULL
    OR tombstones_table IS NULL
    OR audit_table IS NULL
    OR membership_validator IS NULL
    OR private_writer IS NULL
    OR runtime_bridge IS NULL
    OR claim_guard IS NULL
    OR tombstone_guard IS NULL
    OR audit_guard IS NULL
  THEN
    RAISE EXCEPTION 'organization owner transfer objects are incomplete';
  END IF;

  SELECT procedure_row.proowner
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = membership_validator;

  SELECT role_row.oid
  INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  IF trusted_owner = runtime_role THEN
    RAISE EXCEPTION 'organization owner transfer owner cannot be runtime';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0086_organization_owner_transfer'
  ) <> 1
  THEN
    RAISE EXCEPTION 'organization owner transfer migration was not recorded once';
  END IF;

  expected_names := ARRAY[
    'request_id',
    'actor_app_user_id',
    'organization_workspace_id',
    'target_organization_membership_id',
    'previous_owner_assignment_id',
    'organization_owner_assignment_id',
    'effective_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid',
    'uuid',
    'uuid',
    'uuid',
    'uuid',
    'uuid',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[
    true, false, true, true, true, true, true
  ]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(
        attribute_row.atttypid,
        attribute_row.atttypmod
      ) ORDER BY attribute_row.attnum
    ),
    array_agg(attribute_row.attnotnull ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = claims_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;

  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION 'organization owner transfer claim columns drifted';
  END IF;

  expected_names := ARRAY['claim_family', 'request_id']::text[];
  expected_types := ARRAY['text', 'uuid']::text[];
  expected_not_null := ARRAY[true, true]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(
        attribute_row.atttypid,
        attribute_row.atttypmod
      ) ORDER BY attribute_row.attnum
    ),
    array_agg(attribute_row.attnotnull ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = tombstones_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;

  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION 'organization owner transfer tombstone columns drifted';
  END IF;

  expected_names := ARRAY[
    'organization_owner_transfer_audit_event_id',
    'owner_transfer_contract_id',
    'request_id',
    'organization_workspace_id',
    'previous_owner_assignment_id',
    'organization_owner_assignment_id',
    'effective_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'uuid',
    'uuid',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[
    true, true, true, true, true, true, true
  ]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(
        attribute_row.atttypid,
        attribute_row.atttypmod
      ) ORDER BY attribute_row.attnum
    ),
    array_agg(attribute_row.attnotnull ORDER BY attribute_row.attnum)
  INTO actual_names, actual_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = audit_table
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;

  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION 'organization owner transfer audit is not value-free';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'request_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'actor_app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confrelid = 'app_data.app_users'::regclass
        AND constraint_row.confdeltype = 'n'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*effective_at_utc'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
        AND constraint_row.conkey <> ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'actor_app_user_id'
          )
        ]::smallint[]
    )
  THEN
    RAISE EXCEPTION 'organization owner transfer claim constraints drifted';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = tombstones_table
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = tombstones_table
              AND attribute_row.attname = 'claim_family'
          ),
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = tombstones_table
              AND attribute_row.attname = 'request_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = tombstones_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization-owner-transfer:v1'
    )
  THEN
    RAISE EXCEPTION 'organization owner transfer tombstone constraints drifted';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'p'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'u'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = audit_table
              AND attribute_row.attname = 'request_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization-owner-transfer:v1'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*effective_at_utc'
    )
  THEN
    RAISE EXCEPTION 'organization owner transfer audit constraints drifted';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = claims_table
        AND trigger_row.tgname =
          'organization_owner_transfer_request_claims_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = claim_guard
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~*
          'BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = tombstones_table
        AND trigger_row.tgname =
          'organization_owner_transfer_request_tombstones_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = tombstone_guard
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~*
          'BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = audit_table
        AND trigger_row.tgname =
          'organization_owner_transfer_audit_events_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = audit_guard
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~*
          'BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
  THEN
    RAISE EXCEPTION 'organization owner transfer history guards are incomplete';
  END IF;

  IF pg_catalog.pg_get_function_identity_arguments(private_writer)
      IS DISTINCT FROM
      'trusted_app_user_id uuid, requested_request_id uuid, requested_organization_workspace_id uuid, requested_target_organization_membership_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(runtime_bridge)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_request_id uuid, requested_organization_workspace_id uuid, requested_target_organization_membership_id uuid'
  THEN
    RAISE EXCEPTION 'organization owner transfer function signatures drifted';
  END IF;

  FOR function_oid IN
    SELECT unnest(ARRAY[private_writer, runtime_bridge]::oid[])
  LOOP
    SELECT
      array_agg(argument_row.argument_name ORDER BY argument_row.ordinality),
      array_agg(
        pg_catalog.format_type(argument_row.argument_type, NULL)
        ORDER BY argument_row.ordinality
      )
    INTO actual_result_names, actual_result_types
    FROM pg_catalog.pg_proc AS procedure_row
    CROSS JOIN LATERAL unnest(
      procedure_row.proallargtypes,
      procedure_row.proargmodes,
      procedure_row.proargnames
    ) WITH ORDINALITY AS argument_row(
      argument_type,
      argument_mode,
      argument_name,
      ordinality
    )
    WHERE procedure_row.oid = function_oid
      AND argument_row.argument_mode = 't';

    IF actual_result_names IS DISTINCT FROM ARRAY[
        'owner_transfer_contract_id',
        'organization_workspace_id',
        'previous_owner_assignment_id',
        'organization_owner_assignment_id',
        'effective_at_utc'
      ]::text[]
      OR actual_result_types IS DISTINCT FROM ARRAY[
        'text',
        'uuid',
        'uuid',
        'uuid',
        'timestamp with time zone'
      ]::text[]
    THEN
      RAISE EXCEPTION 'organization owner transfer result row drifted';
    END IF;
  END LOOP;

  FOR function_row IN
    SELECT procedure_row.oid,
           procedure_row.proowner,
           procedure_row.prosecdef,
           procedure_row.provolatile,
           procedure_row.proconfig
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid IN (
      private_writer,
      runtime_bridge,
      claim_guard,
      tombstone_guard,
      audit_guard
    )
  LOOP
    IF function_row.proowner <> trusted_owner
      OR NOT function_row.prosecdef
      OR function_row.provolatile <> 'v'
      OR function_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
    THEN
      RAISE EXCEPTION
        'organization owner transfer function security drifted: %',
        function_row.oid;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (
      claims_table,
      tombstones_table,
      audit_table
    )
      AND relation_row.relowner <> trusted_owner
  ) THEN
    RAISE EXCEPTION 'organization owner transfer relation owner drifted';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(private_writer)
  INTO private_definition;
  SELECT pg_catalog.pg_get_functiondef(runtime_bridge)
  INTO bridge_definition;

  IF private_definition NOT LIKE '%organization-owner-transfer-request:%'
    OR private_definition NOT LIKE
      '%app_private.lock_organization_governance_v1%'
    OR private_definition NOT LIKE '%organization-membership:%'
    OR private_definition NOT LIKE '%transaction_timestamp()%'
    OR private_definition NOT LIKE
      '%invalid organization owner transfer request%'
    OR private_definition NOT LIKE
      '%organization owner transfer forbidden%'
    OR private_definition NOT LIKE
      '%organization owner transfer idempotency conflict%'
    OR private_definition NOT LIKE
      '%organization owner transfer target already owner%'
    OR private_definition ILIKE '%eligibility%'
  THEN
    RAISE EXCEPTION 'organization owner transfer writer contract drifted';
  END IF;

  IF bridge_definition NOT LIKE
      '%invalid organization owner transfer identity%'
    OR bridge_definition NOT LIKE '%organization owner transfer forbidden%'
    OR bridge_definition NOT LIKE
      '%app_private.transfer_organization_owner_v1%'
    OR bridge_definition ILIKE '%eligibility%'
  THEN
    RAISE EXCEPTION 'organization owner transfer identity bridge drifted';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime', runtime_bridge, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime', private_writer, 'EXECUTE'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(
          procedure_row.proacl,
          pg_catalog.acldefault('f', procedure_row.proowner)
        )
      ) AS privilege_row
      WHERE procedure_row.oid IN (
        private_writer,
        runtime_bridge,
        claim_guard,
        tombstone_guard,
        audit_guard
      )
        AND privilege_row.privilege_type = 'EXECUTE'
        AND (
          privilege_row.grantee = 0
          OR privilege_row.grantee = runtime_role
            AND procedure_row.oid <> runtime_bridge
        )
    )
  THEN
    RAISE EXCEPTION 'organization owner transfer function ACL is open';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime', claims_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', tombstones_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', audit_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(
          relation_row.relacl,
          pg_catalog.acldefault('r', relation_row.relowner)
        )
      ) AS privilege_row
      WHERE relation_row.oid IN (
        claims_table,
        tombstones_table,
        audit_table
      )
        AND privilege_row.grantee IN (0, runtime_role)
    )
  THEN
    RAISE EXCEPTION 'organization owner transfer storage ACL is open';
  END IF;
END
$check$;
