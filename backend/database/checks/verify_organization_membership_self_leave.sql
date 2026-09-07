\set ON_ERROR_STOP on

DO $check$
DECLARE
  claims_table regclass := pg_catalog.to_regclass(
    'app_private.organization_membership_self_leave_request_claims'
  );
  tombstones_table regclass := pg_catalog.to_regclass(
    'app_private.organization_membership_self_leave_request_tombstones'
  );
  audit_table regclass := pg_catalog.to_regclass(
    'app_private.organization_membership_self_leave_audit_events'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_writer regprocedure := pg_catalog.to_regprocedure(
    'app_private.leave_organization_membership_v1(uuid,uuid,uuid)'
  );
  runtime_bridge regprocedure := pg_catalog.to_regprocedure(
    'app_data.leave_organization_membership_for_identity_v1(text,text,uuid,uuid)'
  );
  claim_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_membership_self_leave_request_claim_v1()'
  );
  tombstone_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_membership_self_leave_request_tombstone_v1()'
  );
  audit_guard regprocedure := pg_catalog.to_regprocedure(
    'app_private.protect_organization_membership_self_leave_audit_event_v1()'
  );
  trusted_owner oid;
  runtime_role oid;
  relation regclass;
  expected_names text[];
  expected_types text[];
  expected_not_null boolean[];
  actual_names text[];
  actual_types text[];
  actual_not_null boolean[];
  actual_input_names text[];
  actual_output_names text[];
  actual_output_types text[];
  function_definition text;
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
    RAISE EXCEPTION
      'organization membership self-leave objects are incomplete';
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
      'organization membership self-leave owner cannot be runtime';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0090_organization_membership_self_leave'
  ) <> 1 THEN
    RAISE EXCEPTION
      'organization membership self-leave migration was not recorded once';
  END IF;

  expected_names := ARRAY[
    'request_id',
    'actor_app_user_id',
    'organization_workspace_id',
    'organization_membership_id',
    'effective_at_utc'
  ];
  expected_types := ARRAY[
    'uuid', 'uuid', 'uuid', 'uuid', 'timestamp with time zone'
  ];
  expected_not_null := ARRAY[true, false, true, true, true];
  relation := claims_table;

  SELECT
    array_agg(attribute.attname::text ORDER BY attribute.attnum),
    array_agg(
      pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
      ORDER BY attribute.attnum
    ),
    array_agg(attribute.attnotnull ORDER BY attribute.attnum)
  INTO actual_names, actual_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute
  WHERE attribute.attrelid = relation
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped;

  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION
      'organization membership self-leave claim columns drifted';
  END IF;

  expected_names := ARRAY['claim_family', 'request_id'];
  expected_types := ARRAY['text', 'uuid'];
  expected_not_null := ARRAY[true, true];
  relation := tombstones_table;

  SELECT
    array_agg(attribute.attname::text ORDER BY attribute.attnum),
    array_agg(
      pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
      ORDER BY attribute.attnum
    ),
    array_agg(attribute.attnotnull ORDER BY attribute.attnum)
  INTO actual_names, actual_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute
  WHERE attribute.attrelid = relation
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped;

  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION
      'organization membership self-leave tombstone columns drifted';
  END IF;

  expected_names := ARRAY[
    'organization_membership_self_leave_audit_event_id',
    'membership_self_leave_contract_id',
    'request_id',
    'organization_workspace_id',
    'organization_membership_id',
    'effective_at_utc'
  ];
  expected_types := ARRAY[
    'uuid', 'text', 'uuid', 'uuid', 'uuid', 'timestamp with time zone'
  ];
  expected_not_null := ARRAY[true, true, true, true, true, true];
  relation := audit_table;

  SELECT
    array_agg(attribute.attname::text ORDER BY attribute.attnum),
    array_agg(
      pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
      ORDER BY attribute.attnum
    ),
    array_agg(attribute.attnotnull ORDER BY attribute.attnum)
  INTO actual_names, actual_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute
  WHERE attribute.attrelid = relation
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped;

  IF actual_names IS DISTINCT FROM expected_names
    OR actual_types IS DISTINCT FROM expected_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION
      'organization membership self-leave audit is not value-free';
  END IF;

  IF (
      SELECT count(*)
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
    ) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = constraint_row.conrelid
        AND attribute.attnum = constraint_row.conkey[1]
      WHERE constraint_row.conrelid = claims_table
        AND constraint_row.contype = 'f'
        AND constraint_row.confrelid = 'app_data.app_users'::regclass
        AND constraint_row.confdeltype = 'n'
        AND attribute.attname = 'actor_app_user_id'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid IN (tombstones_table, audit_table)
        AND constraint_row.contype = 'f'
    )
  THEN
    RAISE EXCEPTION
      'organization membership self-leave opaque-key boundary drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_trigger AS trigger_row
    WHERE trigger_row.tgrelid IN (claims_table, tombstones_table, audit_table)
      AND NOT trigger_row.tgisinternal
  ) <> 3 THEN
    RAISE EXCEPTION
      'organization membership self-leave immutability guards drifted';
  END IF;

  SELECT
    procedure_row.proargnames[1:3],
    array_agg(argument.argument_name ORDER BY argument.ordinality)
      FILTER (WHERE argument.argument_mode = 't'),
    array_agg(
      pg_catalog.format_type(argument.argument_type, NULL)
      ORDER BY argument.ordinality
    ) FILTER (WHERE argument.argument_mode = 't')
  INTO actual_input_names, actual_output_names, actual_output_types
  FROM pg_catalog.pg_proc AS procedure_row
  CROSS JOIN LATERAL unnest(
    procedure_row.proallargtypes,
    procedure_row.proargmodes,
    procedure_row.proargnames
  ) WITH ORDINALITY AS argument(
    argument_type, argument_mode, argument_name, ordinality
  )
  WHERE procedure_row.oid = private_writer
  GROUP BY procedure_row.proargnames;

  IF actual_input_names IS DISTINCT FROM ARRAY[
      'resolved_actor_app_user_id',
      'requested_request_id',
      'requested_organization_workspace_id'
    ]
    OR actual_output_names IS DISTINCT FROM ARRAY[
      'membership_self_leave_contract_id',
      'organization_workspace_id',
      'organization_membership_id',
      'effective_at_utc'
    ]
    OR actual_output_types IS DISTINCT FROM ARRAY[
      'text', 'uuid', 'uuid', 'timestamp with time zone'
    ]
  THEN
    RAISE EXCEPTION
      'organization membership self-leave private signature drifted';
  END IF;

  SELECT
    procedure_row.proargnames[1:4],
    array_agg(argument.argument_name ORDER BY argument.ordinality)
      FILTER (WHERE argument.argument_mode = 't'),
    array_agg(
      pg_catalog.format_type(argument.argument_type, NULL)
      ORDER BY argument.ordinality
    ) FILTER (WHERE argument.argument_mode = 't')
  INTO actual_input_names, actual_output_names, actual_output_types
  FROM pg_catalog.pg_proc AS procedure_row
  CROSS JOIN LATERAL unnest(
    procedure_row.proallargtypes,
    procedure_row.proargmodes,
    procedure_row.proargnames
  ) WITH ORDINALITY AS argument(
    argument_type, argument_mode, argument_name, ordinality
  )
  WHERE procedure_row.oid = runtime_bridge
  GROUP BY procedure_row.proargnames;

  IF actual_input_names IS DISTINCT FROM ARRAY[
      'trusted_issuer',
      'trusted_subject',
      'requested_request_id',
      'requested_organization_workspace_id'
    ]
    OR actual_output_names IS DISTINCT FROM ARRAY[
      'membership_self_leave_contract_id',
      'organization_workspace_id',
      'organization_membership_id',
      'effective_at_utc'
    ]
    OR actual_output_types IS DISTINCT FROM ARRAY[
      'text', 'uuid', 'uuid', 'timestamp with time zone'
    ]
  THEN
    RAISE EXCEPTION
      'organization membership self-leave bridge signature drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid IN (
        private_writer, runtime_bridge, claim_guard,
        tombstone_guard, audit_guard
      )
      AND (
        procedure_row.proowner <> trusted_owner
        OR NOT procedure_row.prosecdef
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
      )
  ) THEN
    RAISE EXCEPTION
      'organization membership self-leave function boundary drifted';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', runtime_bridge, 'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', private_writer, 'EXECUTE'
    )
    OR pg_catalog.has_function_privilege('public', runtime_bridge, 'EXECUTE')
    OR pg_catalog.has_function_privilege('public', private_writer, 'EXECUTE')
    OR EXISTS (
      SELECT 1
      FROM unnest(ARRAY[claims_table, tombstones_table, audit_table]) AS item(
        relation_oid
      )
      WHERE pg_catalog.has_table_privilege(
        'tongxingzhe_runtime', item.relation_oid,
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    )
  THEN
    RAISE EXCEPTION
      'organization membership self-leave ACL is incorrect';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(private_writer)
  INTO function_definition;

  IF (
      char_length(function_definition)
        - char_length(replace(function_definition, 'clock_timestamp()', ''))
    ) / char_length('clock_timestamp()') <> 1
    OR function_definition ~ 'transaction_timestamp\(\)'
    OR function_definition !~
      'organization-membership-self-leave-request:'
    OR function_definition !~ 'organization-membership:'
    OR function_definition !~
      'app_private\.lock_organization_governance_v1'
    OR function_definition !~ 'app_data\.organization_owner_assignments'
    OR function_definition !~ 'app_data\.project_memberships'
    OR function_definition !~ 'app_data\.promotion_target_assignments'
    OR function_definition !~ 'app_data\.promotion_targets'
    OR strpos(function_definition, 'FOR UPDATE') > strpos(
      function_definition,
      'app_private.lock_organization_governance_v1'
    )
    OR strpos(
      function_definition,
      'app_private.lock_organization_governance_v1'
    ) > strpos(function_definition, '''organization-membership:''')
    OR strpos(function_definition, '''organization-membership:''') > strpos(
      function_definition,
      'effective_time := clock_timestamp()'
    )
  THEN
    RAISE EXCEPTION
      'organization membership self-leave lock/time contract drifted';
  END IF;
END
$check$;
