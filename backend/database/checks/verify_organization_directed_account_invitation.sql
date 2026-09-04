\set ON_ERROR_STOP on

DO $check$
DECLARE
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.organization_directed_account_invitation_request_claims'
  );
  tombstones_table regclass := pg_catalog.to_regclass(
    'app_private.organization_directed_account_invitation_request_tombstones'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.organization_directed_account_invitation_audit_events'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_create regprocedure := pg_catalog.to_regprocedure(
    'app_private.create_organization_directed_account_invitation_v1(uuid,uuid,uuid,uuid)'
  );
  bridge_create regprocedure := pg_catalog.to_regprocedure(
    'app_data.create_organization_directed_account_invitation_for_identity_v1(text,text,uuid,uuid,uuid)'
  );
  private_accept regprocedure := pg_catalog.to_regprocedure(
    'app_private.accept_organization_directed_account_invitation_v1(uuid,uuid)'
  );
  bridge_accept regprocedure := pg_catalog.to_regprocedure(
    'app_data.accept_organization_directed_account_invitation_for_identity_v1(text,text,uuid)'
  );
  claim_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_directed_invitation_claim_v1()'
  );
  tombstone_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_directed_invitation_tombstone_v1()'
  );
  audit_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_directed_invitation_audit_event_v1()'
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
BEGIN
  IF claims_table IS NULL
    OR tombstones_table IS NULL
    OR audit_table IS NULL
    OR membership_validator IS NULL
    OR private_create IS NULL
    OR bridge_create IS NULL
    OR private_accept IS NULL
    OR bridge_accept IS NULL
    OR claim_guard IS NULL
    OR tombstone_guard IS NULL
    OR audit_guard IS NULL
  THEN
    RAISE EXCEPTION
      'organization directed account invitation objects are incomplete';
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
      'organization directed account invitation owner cannot be runtime';
  END IF;

  expected_names := ARRAY[
    'invitation_id',
    'organization_workspace_id',
    'inviter_app_user_id',
    'target_app_user_id',
    'issued_at_utc',
    'expires_at_utc',
    'accepted_at_utc',
    'accepted_organization_membership_id'
  ]::text[];
  expected_types := ARRAY[
    'uuid',
    'uuid',
    'uuid',
    'uuid',
    'timestamp with time zone',
    'timestamp with time zone',
    'timestamp with time zone',
    'uuid'
  ]::text[];
  expected_not_null := ARRAY[
    true, true, false, false, true, true, false, false
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
    RAISE EXCEPTION
      'organization invitation claim columns drifted';
  END IF;

  expected_names := ARRAY['claim_family', 'invitation_id']::text[];
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
    RAISE EXCEPTION
      'organization invitation tombstone columns drifted';
  END IF;

  expected_names := ARRAY[
    'organization_invitation_audit_event_id',
    'organization_invitation_contract_id',
    'invitation_id',
    'organization_workspace_id',
    'event_kind',
    'organization_membership_id',
    'occurred_at_utc'
  ]::text[];
  expected_types := ARRAY[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'text',
    'uuid',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[
    true, true, true, true, true, false, true
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
    RAISE EXCEPTION
      'organization invitation audit columns are not value-free';
  END IF;

  -- The claim has one idempotency key and exactly the two nullable account
  -- references.  Workspace and membership IDs remain opaque references.
  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table
  ) <> 6
    OR (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = claims_table
      AND constraint_row.contype = 'p'
    ) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'invitation_id'
          )
        ]::smallint[]
    )
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
    ) <> 2
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
              AND attribute_row.attname = 'inviter_app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confrelid = 'app_data.app_users'::regclass
        AND constraint_row.confkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid =
              'app_data.app_users'::regclass
              AND attribute_row.attname = 'app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confdeltype = 'n'
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
              AND attribute_row.attname = 'target_app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confrelid = 'app_data.app_users'::regclass
        AND constraint_row.confkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid =
              'app_data.app_users'::regclass
              AND attribute_row.attname = 'app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confdeltype = 'n'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
        AND NOT (
          (
            constraint_row.conkey = ARRAY[
              (
                SELECT attribute_row.attnum
                FROM pg_catalog.pg_attribute AS attribute_row
                WHERE attribute_row.attrelid = claims_table
                  AND attribute_row.attname = 'inviter_app_user_id'
              )
            ]::smallint[]
            AND constraint_row.confrelid = 'app_data.app_users'::regclass
            AND constraint_row.confkey = ARRAY[
              (
                SELECT attribute_row.attnum
                FROM pg_catalog.pg_attribute AS attribute_row
                WHERE attribute_row.attrelid =
                  'app_data.app_users'::regclass
                  AND attribute_row.attname = 'app_user_id'
              )
            ]::smallint[]
            AND constraint_row.confdeltype = 'n'
          )
          OR (
            constraint_row.conkey = ARRAY[
              (
                SELECT attribute_row.attnum
                FROM pg_catalog.pg_attribute AS attribute_row
                WHERE attribute_row.attrelid = claims_table
                  AND attribute_row.attname = 'target_app_user_id'
              )
            ]::smallint[]
            AND constraint_row.confrelid = 'app_data.app_users'::regclass
            AND constraint_row.confkey = ARRAY[
              (
                SELECT attribute_row.attnum
                FROM pg_catalog.pg_attribute AS attribute_row
                WHERE attribute_row.attrelid =
                  'app_data.app_users'::regclass
                  AND attribute_row.attname = 'app_user_id'
              )
            ]::smallint[]
            AND constraint_row.confdeltype = 'n'
          )
        )
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*issued_at_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*expires_at_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*accepted_at_utc'
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
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'accepted_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'accepted_organization_membership_id'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'IS[[:space:]]+NULL'
    )
  THEN
    RAISE EXCEPTION
      'organization invitation claim constraints or foreign keys drifted';
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
              AND attribute_row.attname = 'invitation_id'
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
          'organization-directed-account-invitation:v1'
    )
  THEN
    RAISE EXCEPTION
      'organization invitation tombstone constraints drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint AS constraint_row
    WHERE constraint_row.conrelid = audit_table
  ) <> 6
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = audit_table
              AND attribute_row.attname =
                'organization_invitation_audit_event_id'
          )
        ]::smallint[]
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
              AND attribute_row.attname = 'invitation_id'
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
          'organization_invitation_contract_id'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization-directed-account-invitation:v1'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'invitation_issued'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'invitation_accepted'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization_membership_id'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'invitation_issued'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'invitation_accepted'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*occurred_at_utc'
    )
  THEN
    RAISE EXCEPTION
      'organization invitation audit constraints or allowlist drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid IN (
        claims_table,
        tombstones_table,
        audit_table
      )
      AND NOT trigger_row.tgisinternal
  ) <> 3
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = claims_table
        AND trigger_row.tgname =
          'organization_directed_invitation_claims_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = claim_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = tombstones_table
        AND trigger_row.tgname =
          'organization_directed_invitation_tombstones_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = tombstone_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = audit_table
        AND trigger_row.tgname =
          'organization_directed_invitation_audit_events_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = audit_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
    )
  THEN
    RAISE EXCEPTION
      'organization invitation history guards or triggers are incomplete';
  END IF;

  IF pg_catalog.pg_get_function_identity_arguments(private_create)
      IS DISTINCT FROM
      'trusted_actor_app_user_id uuid, requested_invitation_id uuid, requested_organization_workspace_id uuid, requested_target_app_user_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(bridge_create)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_invitation_id uuid, requested_organization_workspace_id uuid, requested_target_app_user_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(private_accept)
      IS DISTINCT FROM
      'trusted_actor_app_user_id uuid, requested_invitation_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(bridge_accept)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_invitation_id uuid'
  THEN
    RAISE EXCEPTION
      'organization invitation function signatures drifted';
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
        'organization_invitation_contract_id',
        'invitation_id',
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
        'organization invitation create result row drifted';
    END IF;
  END LOOP;

  FOR function_oid IN
    SELECT unnest(ARRAY[private_accept, bridge_accept]::oid[])
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
        'organization_invitation_contract_id',
        'invitation_id',
        'organization_workspace_id',
        'organization_membership_id',
        'accepted_at_utc'
      ]::text[]
      OR actual_result_types IS DISTINCT FROM ARRAY[
        'text',
        'uuid',
        'uuid',
        'uuid',
        'timestamp with time zone'
      ]::text[]
    THEN
      RAISE EXCEPTION
        'organization invitation accept result row drifted';
    END IF;
  END LOOP;

  -- All storage, writers, bridges, and guards use the existing trusted owner.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class AS relation_row
    WHERE relation_row.oid IN (
        claims_table,
        tombstones_table,
        audit_table
      )
      AND relation_row.relowner <> trusted_owner
  )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid IN (
          private_create,
          bridge_create,
          private_accept,
          bridge_accept,
          claim_guard,
          tombstone_guard,
          audit_guard
        )
        AND procedure_row.proowner <> trusted_owner
    )
  THEN
    RAISE EXCEPTION
      'organization invitation owner boundary drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid IN (
        private_create,
        bridge_create,
        private_accept,
        bridge_accept,
        claim_guard,
        tombstone_guard,
        audit_guard
      )
      AND (
        NOT procedure_row.prosecdef
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
      )
  )
  THEN
    RAISE EXCEPTION
      'organization invitation functions are not volatile security definers';
  END IF;

  -- PUBLIC has no callable seam; runtime has exactly the two identity bridges.
  IF NOT has_function_privilege(
      'tongxingzhe_runtime', bridge_create, 'EXECUTE'
    )
    OR NOT has_function_privilege(
      'tongxingzhe_runtime', bridge_accept, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime', private_create, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime', private_accept, 'EXECUTE'
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
          private_accept,
          bridge_accept,
          claim_guard,
          tombstone_guard,
          audit_guard
        )
        AND privilege_row.privilege_type = 'EXECUTE'
        AND (
          privilege_row.grantee = 0
          OR (
            privilege_row.grantee = runtime_role
            AND procedure_row.oid NOT IN (bridge_create, bridge_accept)
          )
        )
    )
  THEN
    RAISE EXCEPTION
      'organization invitation function ACL is not limited to two bridges';
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
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.organization_memberships'::regclass,
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION
      'organization invitation storage ACL is not closed';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0087_organization_directed_account_invitation'
  ) <> 1
  THEN
    RAISE EXCEPTION
      'organization directed account invitation migration was not recorded once';
  END IF;
END
$check$;
