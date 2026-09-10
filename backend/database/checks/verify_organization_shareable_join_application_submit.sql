\set ON_ERROR_STOP on

DO $check$
DECLARE
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_application_request_claims'
  );
  tombstones_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_application_request_tombstones'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.organization_shareable_join_application_audit_events'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_submit regprocedure := pg_catalog.to_regprocedure(
    'app_private.submit_organization_shareable_join_application_v1(uuid,uuid,uuid)'
  );
  bridge_submit regprocedure := pg_catalog.to_regprocedure(
    'app_data.submit_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)'
  );
  claim_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_shareable_join_application_claim_v1()'
  );
  tombstone_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_shareable_join_application_tombstone_v1()'
  );
  audit_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_shareable_join_application_audit_event_v1()'
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
  bridge_definition text;
  claim_guard_definition text;
  tombstone_guard_definition text;
  audit_guard_definition text;
BEGIN
  IF claims_table IS NULL
    OR tombstones_table IS NULL
    OR audit_table IS NULL
    OR membership_validator IS NULL
    OR private_submit IS NULL
    OR bridge_submit IS NULL
    OR claim_guard IS NULL
    OR tombstone_guard IS NULL
    OR audit_guard IS NULL
  THEN
    RAISE EXCEPTION
      'organization shareable join application submit objects are incomplete';
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
      'organization shareable join application owner cannot be runtime';
  END IF;

  expected_names := ARRAY[
    'application_id',
    'link_id',
    'organization_workspace_id',
    'applicant_app_user_id',
    'submitted_at_utc',
    'expires_at_utc',
    'approved_at_utc',
    'approved_organization_membership_id'
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
    true, true, true, false, true, true, false, false
  ]::boolean[];

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
      'organization shareable join application claim columns drifted';
  END IF;

  expected_names := ARRAY['claim_family', 'application_id']::text[];
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
      'organization shareable join application tombstone columns drifted';
  END IF;

  expected_names := ARRAY[
    'organization_shareable_join_application_audit_event_id',
    'organization_shareable_join_application_contract_id',
    'application_id',
    'link_id',
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
    'uuid',
    'text',
    'uuid',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[
    true, true, true, true, true, true, false, true
  ]::boolean[];

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
      'organization shareable join application audit columns are not value-free';
  END IF;

  -- The claim has only its applicant FK. Link, workspace, and future
  -- membership values stay opaque so account and organization purge can work.
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
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'application_id'
          )
        ]::smallint[]
    ) <> 1
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'u'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'link_id'
          ),
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = claims_table
              AND attribute_row.attname = 'applicant_app_user_id'
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
              AND attribute_row.attname = 'applicant_app_user_id'
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
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
    ) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*submitted_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*expires_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'isfinite[[:space:]]*[(][[:space:]]*approved_at_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'expires_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'submitted_at_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          '(168[[:space:]]*hours|7[[:space:]]*days|168:00:00)'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'approved_at_utc IS NULL'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'approved_organization_membership_id IS NULL'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'approved_at_utc IS NOT NULL'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'approved_organization_membership_id IS NOT NULL'
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application claim constraints drifted';
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
              AND attribute_row.attname = 'application_id'
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
          'organization-shareable-join-application:v1'
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application tombstone constraints drifted';
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
                'organization_shareable_join_application_audit_event_id'
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
              AND attribute_row.attname = 'application_id'
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
          'organization_shareable_join_application_contract_id'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization-shareable-join-application:v1'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'application_submitted'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'application_approved'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_table
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization_membership_id IS NULL'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~*
          'organization_membership_id IS NOT NULL'
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
      'organization shareable join application audit constraints drifted';
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
          'organization_shareable_join_application_claims_immutable'
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
          'organization_shareable_join_application_tombstones_immutable'
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
          'organization_shareable_join_application_audit_events_immutable'
        AND trigger_row.tgfoid = audit_guard
        AND trigger_row.tgtype = 27
        AND trigger_row.tgenabled = 'O'
        AND NOT trigger_row.tgisinternal
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application guards are incomplete';
  END IF;

  IF pg_catalog.pg_get_function_identity_arguments(private_submit)
      IS DISTINCT FROM
      'trusted_actor_app_user_id uuid, requested_application_id uuid, requested_link_id uuid'
    OR pg_catalog.pg_get_function_identity_arguments(bridge_submit)
      IS DISTINCT FROM
      'trusted_issuer text, trusted_subject text, requested_application_id uuid, requested_link_id uuid'
  THEN
    RAISE EXCEPTION
      'organization shareable join application submit signatures drifted';
  END IF;

  FOR function_oid IN
    SELECT unnest(ARRAY[private_submit, bridge_submit]::oid[])
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
        'organization_shareable_join_application_contract_id',
        'application_id',
        'link_id',
        'organization_workspace_id',
        'submitted_at_utc',
        'expires_at_utc'
      ]::text[]
      OR actual_result_types IS DISTINCT FROM ARRAY[
        'text',
        'uuid',
        'uuid',
        'uuid',
        'timestamp with time zone',
        'timestamp with time zone'
      ]::text[]
    THEN
      RAISE EXCEPTION
        'organization shareable join application submit result row drifted';
    END IF;
  END LOOP;

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
          private_submit,
          bridge_submit,
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
          private_submit,
          bridge_submit,
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
      WHERE procedure_row.oid IN (private_submit, bridge_submit)
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
      'organization shareable join application owner or boundary drifted';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', bridge_submit, 'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', private_submit, 'EXECUTE'
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
          private_submit,
          bridge_submit,
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
            AND procedure_row.oid <> bridge_submit
          )
        )
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application function ACL is not minimal';
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
          'app_private.organization_shareable_join_link_request_claims'::regclass,
          'app_private.organization_shareable_join_link_request_tombstones'::regclass,
          'app_data.external_identities'::regclass,
          'app_data.app_users'::regclass,
          'app_data.workspaces'::regclass,
          'app_data.organization_memberships'::regclass
        )
        AND privilege_row.grantee IN (0, runtime_role)
    )
  THEN
    RAISE EXCEPTION
      'organization shareable join application storage or facts are exposed';
  END IF;

  private_definition := pg_catalog.pg_get_functiondef(private_submit);
  bridge_definition := pg_catalog.pg_get_functiondef(bridge_submit);
  claim_guard_definition := pg_catalog.pg_get_functiondef(claim_guard);
  tombstone_guard_definition := pg_catalog.pg_get_functiondef(tombstone_guard);
  audit_guard_definition := pg_catalog.pg_get_functiondef(audit_guard);

  IF claim_guard_definition !~
      'OLD\.applicant_app_user_id IS NOT NULL'
    OR claim_guard_definition !~
      'NEW\.applicant_app_user_id IS NULL'
    OR claim_guard_definition !~
      'OLD\.approved_at_utc IS NULL'
    OR claim_guard_definition !~
      'OLD\.approved_organization_membership_id IS NULL'
    OR claim_guard_definition !~
      'NEW\.approved_at_utc IS NOT NULL'
    OR claim_guard_definition !~
      'NEW\.approved_organization_membership_id IS NOT NULL'
    OR claim_guard_definition !~ 'identity_unlinked AND approval_changed'
    OR claim_guard_definition !~
      'organization shareable join application request claim cannot be deleted'
    OR claim_guard_definition !~
      'organization shareable join application request claim is immutable'
    OR tombstone_guard_definition !~
      'organization shareable join application request tombstone is immutable'
    OR audit_guard_definition !~
      'organization shareable join application audit is append-only'
  THEN
    RAISE EXCEPTION
      'organization shareable join application guard boundary drifted';
  END IF;

  -- History is classified before current link eligibility. The one post-lock
  -- wall clock then drives eligibility, claim, audit, and the exact receipt.
  IF (
    char_length(private_definition)
      - char_length(replace(private_definition, 'clock_timestamp()', ''))
  ) / char_length('clock_timestamp()') <> 1
    OR private_definition ~*
      '(transaction_timestamp|statement_timestamp|current_timestamp)[[:space:]]*[(]?'
    OR private_definition ~* '\mnow[[:space:]]*[(]'
    OR strpos(private_definition,
        'organization-shareable-join-link-request:') = 0
    OR strpos(private_definition,
        'organization-shareable-join-application-request:') = 0
    OR strpos(private_definition, 'FOR UPDATE') = 0
    OR strpos(private_definition,
        'app_private.lock_organization_governance_v1') = 0
    OR strpos(private_definition, 'organization-membership:') = 0
    OR NOT (
      strpos(private_definition,
        'organization-shareable-join-link-request:')
        < strpos(private_definition,
          'organization-shareable-join-application-request:')
      AND strpos(private_definition,
        'organization-shareable-join-application-request:')
        < strpos(private_definition, 'FOR UPDATE')
      AND strpos(private_definition, 'FOR UPDATE')
        < strpos(
          private_definition,
          'applicant_status IS DISTINCT FROM ''active'''
        )
      AND strpos(
          private_definition,
          'applicant_status IS DISTINCT FROM ''active'''
        ) < strpos(
          private_definition,
          'FROM app_private.organization_shareable_join_application_request_tombstones'
        )
      AND strpos(private_definition, 'FOR UPDATE')
        < strpos(private_definition,
          'app_private.lock_organization_governance_v1')
      AND strpos(private_definition,
        'app_private.lock_organization_governance_v1')
        < strpos(private_definition, 'organization-membership:')
      AND strpos(private_definition, 'organization-membership:')
        < strpos(private_definition, 'INTO applicant_membership_periods')
      AND strpos(private_definition, 'INTO applicant_membership_periods')
        < strpos(private_definition, 'clock_timestamp()')
      AND strpos(private_definition, 'clock_timestamp()')
        < strpos(
          private_definition,
          'INSERT INTO app_private.organization_shareable_join_application_request_claims'
        )
      AND strpos(
          private_definition,
          'INSERT INTO app_private.organization_shareable_join_application_request_claims'
        ) < strpos(
          private_definition,
          'INSERT INTO app_private.organization_shareable_join_application_audit_events'
        )
    )
    OR strpos(
      private_definition,
      'FROM app_private.organization_shareable_join_application_request_tombstones'
    ) > strpos(
      private_definition,
      'FROM app_private.organization_shareable_join_link_request_claims'
    )
    OR strpos(
      private_definition,
      'FROM app_private.organization_shareable_join_link_request_tombstones'
    ) > strpos(
      private_definition,
      'FROM app_private.organization_shareable_join_link_request_claims'
    )
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'organization_shareable_join_application_request_claims',
          ''
        ))
    ) / char_length(
      'organization_shareable_join_application_request_claims'
    ) < 6
    OR (
      char_length(private_definition)
        - char_length(replace(
          private_definition,
          'organization_shareable_join_application_request_tombstones',
          ''
        ))
    ) / char_length(
      'organization_shareable_join_application_request_tombstones'
    ) < 2
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
    OR private_definition !~ 'link_tombstone_found OR NOT link_found'
    OR private_definition !~ 'organization-shareable-join-application:v1'
    OR private_definition !~ 'invalid organization shareable join request'
    OR private_definition !~ 'organization shareable join forbidden'
    OR private_definition !~
      'organization shareable join idempotency conflict'
    OR private_definition !~ 'app_data\.organization_memberships'
    OR private_definition !~ 'app_data\.workspaces'
    OR private_definition !~
      'app_private\.organization_shareable_join_application_audit_events'
    OR private_definition ~*
      '(insert[[:space:]]+into|update|delete[[:space:]]+from|merge[[:space:]]+into|truncate)[[:space:]]+app_data\.organization_memberships'
    OR private_definition ~*
      'app_data\.(organization_owner_assignments|project_memberships)'
    OR private_definition ~*
      'approved_(at_utc|organization_membership_id)[[:space:]]*='
  THEN
    RAISE EXCEPTION
      'organization shareable join application submit boundary drifted';
  END IF;

  IF bridge_definition !~ 'invalid organization shareable join identity'
    OR bridge_definition !~ 'organization shareable join forbidden'
    OR bridge_definition !~ 'identity_row\.issuer = trusted_issuer'
    OR bridge_definition !~ 'identity_row\.subject = trusted_subject'
    OR bridge_definition !~ 'app_user\.status = ''active'''
    OR bridge_definition !~
      'app_private\.submit_organization_shareable_join_application_v1'
    OR bridge_definition ~* 'btrim[[:space:]]*[(]identity_row\.'
    OR bridge_definition ~*
      '\m(insert|update|delete|merge|truncate|pg_advisory_xact_lock)\M'
  THEN
    RAISE EXCEPTION
      'organization shareable join application identity bridge drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0093_organization_shareable_join_application_submit'
  ) <> 1
  THEN
    RAISE EXCEPTION
      'organization shareable join application migration was not recorded once';
  END IF;
END
$check$;
