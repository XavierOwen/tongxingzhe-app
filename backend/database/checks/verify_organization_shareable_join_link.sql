\set ON_ERROR_STOP on

DO $check$
DECLARE
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_link_request_claims'
  );
  tombstones_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_link_request_tombstones'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_link_audit_events'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_create regprocedure := pg_catalog.to_regprocedure(
    'app_private.create_organization_shareable_join_link_v1(uuid,uuid,uuid)'
  );
  bridge_create regprocedure := pg_catalog.to_regprocedure(
    'app_data.create_organization_shareable_join_link_for_identity_v1(text,text,uuid,uuid)'
  );
  bridge_preview regprocedure := pg_catalog.to_regprocedure(
    'app_data.preview_organization_shareable_join_link_for_identity_v1(text,text,uuid)'
  );
  claim_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_shareable_join_link_claim_v1()'
  );
  tombstone_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_shareable_join_link_tombstone_v1()'
  );
  audit_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_shareable_join_link_audit_event_v1()'
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
  private_definition text;
  create_definition text;
  preview_definition text;
  claim_guard_definition text;
  tombstone_guard_definition text;
  audit_guard_definition text;
BEGIN
  IF claims_table IS NULL
    OR tombstones_table IS NULL
    OR audit_table IS NULL
    OR membership_validator IS NULL
    OR private_create IS NULL
    OR bridge_create IS NULL
    OR bridge_preview IS NULL
    OR claim_guard IS NULL
    OR tombstone_guard IS NULL
    OR audit_guard IS NULL
  THEN
    RAISE EXCEPTION
      'organization shareable join link objects are incomplete';
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
    RAISE EXCEPTION
      'organization shareable join link owner cannot be runtime';
  END IF;

  expected_names := ARRAY[
    'link_id',
    'organization_workspace_id',
    'creator_app_user_id',
    'issued_at_utc',
    'expires_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid',
    'uuid',
    'uuid',
    'timestamp with time zone',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[true, true, false, true, true]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod)
      ORDER BY attribute_row.attnum
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
    RAISE EXCEPTION
      'organization shareable join link claim columns drifted';
  END IF;

  expected_names := ARRAY['claim_family', 'link_id']::text[];
  expected_types := ARRAY['text', 'uuid']::text[];
  expected_not_null := ARRAY[true, true]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod)
      ORDER BY attribute_row.attnum
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
    RAISE EXCEPTION
      'organization shareable join link tombstone columns drifted';
  END IF;

  expected_names := ARRAY[
    'organization_shareable_join_link_audit_event_id',
    'organization_shareable_join_link_contract_id',
    'link_id',
    'organization_workspace_id',
    'event_kind',
    'issued_at_utc',
    'expires_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'text',
    'timestamp with time zone',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[true, true, true, true, true, true, true]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod)
      ORDER BY attribute_row.attnum
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
    RAISE EXCEPTION
      'organization shareable join link audit columns are not value-free';
  END IF;

  -- Claims have one selector key, one unlinkable creator FK, and no workspace FK.
  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table
  ) <> 4
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'link_id'
          )
        ]::smallint[]
    ) <> 1
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'creator_app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confrelid = 'app_data.app_users'::regclass
        AND constraint_row.confkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = 'app_data.app_users'::regclass
              AND attribute_row.attname = 'app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confdeltype = 'n'
    ) <> 1
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
              AND attribute_row.attname = 'creator_app_user_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*issued_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*expires_at_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'expires_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'issued_at_utc'
        AND (
          pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
            '168[[:space:]]*hours'
          OR pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
            '7[[:space:]]*days'
          OR pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
            '168:00:00'
        )
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link claim constraints drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = tombstones_table
  ) <> 2
    OR NOT EXISTS (
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
              AND attribute_row.attname = 'link_id'
          )
        ]::smallint[]
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = tombstones_table
        AND constraint_row.contype = 'f'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = tombstones_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization-shareable-join-link:v1'
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link tombstone constraints drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
  ) <> 6
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = audit_table
              AND attribute_row.attname =
                'organization_shareable_join_link_audit_event_id'
          )
        ]::smallint[]
    ) <> 1
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
              AND attribute_row.attname = 'link_id'
          ),
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = audit_table
              AND attribute_row.attname = 'event_kind'
          )
        ]::smallint[]
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'f'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization_shareable_join_link_contract_id'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization-shareable-join-link:v1'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'event_kind'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'link_created'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*issued_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*expires_at_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'expires_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'issued_at_utc'
        AND (
          pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
            '168[[:space:]]*hours'
          OR pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
            '7[[:space:]]*days'
          OR pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
            '168:00:00'
        )
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link audit constraints drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid IN (claims_table, tombstones_table, audit_table)
      AND NOT trigger_row.tgisinternal
  ) <> 3
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = claims_table
        AND trigger_row.tgname =
          'organization_shareable_join_link_claims_immutable'
        AND trigger_row.tgfoid = claim_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
        AND NOT trigger_row.tgisinternal
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = tombstones_table
        AND trigger_row.tgname =
          'organization_shareable_join_link_tombstones_immutable'
        AND trigger_row.tgfoid = tombstone_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
        AND NOT trigger_row.tgisinternal
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = audit_table
        AND trigger_row.tgname =
          'organization_shareable_join_link_audit_events_immutable'
        AND trigger_row.tgfoid = audit_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
        AND NOT trigger_row.tgisinternal
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link guards or triggers are incomplete';
  END IF;

  IF pg_catalog.pg_get_function_identity_arguments(private_create)
      IS DISTINCT FROM
      'trusted_actor_app_user_id uuid, requested_link_id uuid, requested_organization_workspace_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(bridge_create)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_link_id uuid, requested_organization_workspace_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(bridge_preview)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_link_id uuid'
  THEN
    RAISE EXCEPTION
      'organization shareable join link function signatures drifted';
  END IF;

  FOR function_oid IN
    SELECT unnest(ARRAY[private_create, bridge_create]::oid[])
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
        'organization_shareable_join_link_contract_id',
        'link_id',
        'organization_workspace_id',
        'issued_at_utc',
        'expires_at_utc'
      ]::text[]
      OR actual_result_types IS DISTINCT FROM ARRAY[
        'text',
        'uuid',
        'uuid',
        'timestamp with time zone',
        'timestamp with time zone'
      ]::text[]
    THEN
      RAISE EXCEPTION
        'organization shareable join link create result row drifted';
    END IF;
  END LOOP;

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
  WHERE procedure_row.oid = bridge_preview
    AND argument_row.argument_mode = 't';

  IF actual_result_names IS DISTINCT FROM ARRAY[
      'organization_shareable_join_link_preview_contract_id',
      'link_id',
      'organization_name',
      'expires_at_utc'
    ]::text[]
    OR actual_result_types IS DISTINCT FROM ARRAY[
      'text',
      'uuid',
      'text',
      'timestamp with time zone'
    ]::text[]
  THEN
    RAISE EXCEPTION
      'organization shareable join link preview result row drifted';
  END IF;

  -- Every object reuses one non-runtime owner and every function is hardened.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (claims_table, tombstones_table, audit_table)
      AND relation_row.relowner <> trusted_owner
  )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid IN (
          private_create,
          bridge_create,
          bridge_preview,
          claim_guard,
          tombstone_guard,
          audit_guard
        )
        AND procedure_row.proowner <> trusted_owner
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      JOIN pg_catalog.pg_language AS language_row
        ON language_row.oid = procedure_row.prolang
      WHERE procedure_row.oid IN (
          private_create,
          bridge_create,
          bridge_preview,
          claim_guard,
          tombstone_guard,
          audit_guard
        )
        AND (
          NOT procedure_row.prosecdef
          OR procedure_row.provolatile <> 'v'
          OR procedure_row.proconfig IS DISTINCT FROM
            ARRAY['search_path=pg_catalog']::text[]
          OR language_row.lanname <> 'plpgsql'
          OR octet_length(procedure_row.proname) > 63
        )
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid IN (private_create, bridge_create, bridge_preview)
        AND NOT procedure_row.proretset
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid IN (claim_guard, tombstone_guard, audit_guard)
        AND procedure_row.prorettype <> 'trigger'::regtype
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link owner or function boundary drifted';
  END IF;

  -- Runtime has exactly the two app_data bridges; PUBLIC has no callable seam.
  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', bridge_create, 'EXECUTE'
    )
    OR NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', bridge_preview, 'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', private_create, 'EXECUTE'
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
          private_create,
          bridge_create,
          bridge_preview,
          claim_guard,
          tombstone_guard,
          audit_guard
        )
        AND (
          privilege_row.grantee = 0
          OR privilege_row.grantee NOT IN (trusted_owner, runtime_role)
          OR privilege_row.privilege_type <> 'EXECUTE'
          OR (
            privilege_row.grantee = runtime_role
            AND procedure_row.oid NOT IN (bridge_create, bridge_preview)
          )
        )
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link function ACL is not minimal';
  END IF;

  IF pg_catalog.has_schema_privilege(
      'tongxingzhe_runtime', 'app_private', 'USAGE'
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
          audit_table,
          'app_data.external_identities'::regclass,
          'app_data.app_users'::regclass,
          'app_data.workspaces'::regclass,
          'app_data.organization_memberships'::regclass,
          'app_data.organization_owner_assignments'::regclass
        )
        AND privilege_row.grantee IN (0, runtime_role)
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join link storage or source rows are exposed';
  END IF;

  private_definition := pg_catalog.pg_get_functiondef(private_create);
  create_definition := pg_catalog.pg_get_functiondef(bridge_create);
  preview_definition := pg_catalog.pg_get_functiondef(bridge_preview);
  claim_guard_definition := pg_catalog.pg_get_functiondef(claim_guard);
  tombstone_guard_definition := pg_catalog.pg_get_functiondef(tombstone_guard);
  audit_guard_definition := pg_catalog.pg_get_functiondef(audit_guard);

  IF claim_guard_definition !~
      'OLD\.creator_app_user_id IS NOT NULL'
    OR claim_guard_definition !~
      'NEW\.creator_app_user_id IS NULL'
    OR claim_guard_definition !~
      'organization shareable join link request claim cannot be deleted'
    OR claim_guard_definition !~
      'organization shareable join link request claim is immutable'
    OR tombstone_guard_definition !~
      'organization shareable join link request tombstone is immutable'
    OR audit_guard_definition !~
      'organization shareable join link audit is append-only'
  THEN
    RAISE EXCEPTION
      'organization shareable join link immutability boundary drifted';
  END IF;

  -- One post-lock wall clock drives first authorization, claim, audit, and receipt.
  IF (
    char_length(private_definition)
      - char_length(replace(private_definition, 'clock_timestamp()', ''))
  ) / char_length('clock_timestamp()') <> 1
    OR private_definition ~* 'transaction_timestamp[[:space:]]*[(]'
    OR private_definition ~* 'statement_timestamp[[:space:]]*[(]'
    OR private_definition ~* 'current_timestamp'
    OR private_definition ~* '\mnow[[:space:]]*[(]'
    OR strpos(private_definition,
        'organization-shareable-join-link-request:') = 0
    OR strpos(private_definition, 'FOR UPDATE') = 0
    OR strpos(private_definition,
        'app_private.lock_organization_governance_v1') = 0
    OR strpos(private_definition, 'organization-membership:') = 0
    OR NOT (
      strpos(private_definition,
        'organization-shareable-join-link-request:')
        < strpos(private_definition, 'FOR UPDATE')
      AND strpos(private_definition, 'FOR UPDATE')
        < strpos(private_definition,
          'app_private.lock_organization_governance_v1')
      AND strpos(private_definition,
        'app_private.lock_organization_governance_v1')
        < strpos(private_definition, 'organization-membership:')
      AND strpos(private_definition, 'organization-membership:')
        < strpos(private_definition, 'INTO actor_owner_periods')
      AND strpos(private_definition, 'INTO actor_owner_periods')
        < strpos(private_definition, 'clock_timestamp()')
      AND strpos(private_definition, 'clock_timestamp()')
        < strpos(
          private_definition,
          'INSERT INTO app_private.organization_shareable_join_link_request_claims'
        )
    )
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'organization_shareable_join_link_request_claims',
          ''
        ))
    ) / char_length(
      'organization_shareable_join_link_request_claims'
    ) < 3
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'organization_shareable_join_link_request_tombstones',
          ''
        ))
    ) / char_length(
      'organization_shareable_join_link_request_tombstones'
    ) < 2
    OR private_definition !~ 'organization-shareable-join-link:v1'
    OR private_definition !~ 'invalid organization shareable join request'
    OR private_definition !~ 'organization shareable join forbidden'
    OR private_definition !~
      'organization shareable join idempotency conflict'
    OR private_definition !~ 'app_data\.organization_owner_assignments'
    OR private_definition !~ 'app_data\.organization_memberships'
    OR private_definition !~
      'app_private\.organization_shareable_join_link_audit_events'
  THEN
    RAISE EXCEPTION
      'organization shareable join link create boundary drifted';
  END IF;

  -- Identity validation may inspect trimmed emptiness, but lookup stays exact.
  IF create_definition !~ 'invalid organization shareable join identity'
    OR create_definition !~ 'organization shareable join forbidden'
    OR create_definition !~ 'identity_row\.issuer = trusted_issuer'
    OR create_definition !~ 'identity_row\.subject = trusted_subject'
    OR create_definition !~ 'app_user\.status = ''active'''
    OR create_definition !~
      'app_private\.create_organization_shareable_join_link_v1'
    OR create_definition ~* 'btrim[[:space:]]*[(]identity_row\.'
    OR create_definition ~*
      '\m(insert|update|delete|merge|truncate|pg_advisory_xact_lock)\M'
  THEN
    RAISE EXCEPTION
      'organization shareable join link create bridge drifted';
  END IF;

  -- Preview is one read-only observation and remains valid after creator unlink.
  IF (
    char_length(preview_definition)
      - char_length(replace(preview_definition, 'clock_timestamp()', ''))
  ) / char_length('clock_timestamp()') <> 1
    OR (
      char_length(lower(preview_definition))
        - char_length(replace(lower(preview_definition), 'return query', ''))
    ) / char_length('return query') <> 1
    OR preview_definition !~
      'organization-shareable-join-link-preview:v1'
    OR preview_definition !~ 'invalid organization shareable join identity'
    OR preview_definition !~ 'invalid organization shareable join request'
    OR preview_definition !~ 'organization shareable join forbidden'
    OR preview_definition !~
      'app_private\.organization_shareable_join_link_request_claims'
    OR preview_definition !~ 'app_data\.external_identities'
    OR preview_definition !~ 'app_data\.app_users'
    OR preview_definition !~ 'app_data\.workspaces'
    OR preview_definition !~ 'identity_row\.issuer = trusted_issuer'
    OR preview_definition !~ 'identity_row\.subject = trusted_subject'
    OR preview_definition ~* 'creator_app_user_id[[:space:]]+IS[[:space:]]+NOT[[:space:]]+NULL'
    OR preview_definition ~*
      '\m(insert|update|delete|merge|truncate)\M'
    OR preview_definition ~*
      'pg_advisory|FOR[[:space:]]+UPDATE|lock_organization'
    OR preview_definition ~*
      'organization_shareable_join_(application|link_request_tombstones|link_audit_events)'
    OR preview_definition ~*
      'app_data\.(organization_memberships|organization_owner_assignments|project_memberships)'
  THEN
    RAISE EXCEPTION
      'organization shareable join link preview boundary drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0092_organization_shareable_join_link'
  ) <> 1
  THEN
    RAISE EXCEPTION
      'organization shareable join link migration was not recorded once';
  END IF;
END
$check$;
