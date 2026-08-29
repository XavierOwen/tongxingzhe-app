\set ON_ERROR_STOP on

DO $check$
DECLARE
  owner_assignments regclass := to_regclass(
    'app_data.organization_owner_assignments'
  );
  request_claims regclass := to_regclass(
    'app_private.organization_creation_request_claims'
  );
  audit_events regclass := to_regclass(
    'app_private.organization_creation_audit_events'
  );
  membership_validator regprocedure := to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  private_writer regprocedure := to_regprocedure(
    'app_private.create_organization_v1(uuid,uuid,text)'
  );
  runtime_bridge regprocedure := to_regprocedure(
    'app_data.create_organization_for_identity_v1(text,text,uuid,text)'
  );
  trusted_owner oid;
  actual_column_names text[];
  actual_column_types text[];
  actual_not_null boolean[];
  actual_result_names text[];
  actual_result_types text[];
  expected_column_names text[];
  expected_column_types text[];
  expected_not_null boolean[];
  function_oid oid;
  index_definition text;
  function_arguments text;
BEGIN
  IF owner_assignments IS NULL
    OR request_claims IS NULL
    OR audit_events IS NULL
    OR membership_validator IS NULL
    OR private_writer IS NULL
    OR runtime_bridge IS NULL
  THEN
    RAISE EXCEPTION 'organization creation contract objects are incomplete';
  END IF;

  SELECT procedure_row.proowner
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = membership_validator;

  IF trusted_owner = (
      SELECT role_row.oid
      FROM pg_catalog.pg_roles AS role_row
      WHERE role_row.rolname = 'tongxingzhe_runtime'
    )
  THEN
    RAISE EXCEPTION 'organization creation owner cannot be runtime';
  END IF;

  -- Exact columns are also the PII allowlists.  In particular, the audit
  -- event has no actor, display name, email, or external identity fields.
  expected_column_names := ARRAY[
    'organization_owner_assignment_id',
    'organization_membership_id',
    'active_from_utc',
    'inactive_from_utc'
  ]::text[];
  expected_column_types := ARRAY[
    'uuid',
    'uuid',
    'timestamp with time zone',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[true, true, true, false]::boolean[];

  SELECT
    array_agg(attribute_row.attname::text ORDER BY attribute_row.attnum),
    array_agg(
      pg_catalog.format_type(
        attribute_row.atttypid,
        attribute_row.atttypmod
      ) ORDER BY attribute_row.attnum
    ),
    array_agg(attribute_row.attnotnull ORDER BY attribute_row.attnum)
  INTO actual_column_names, actual_column_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = owner_assignments
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;

  IF actual_column_names IS DISTINCT FROM expected_column_names
    OR actual_column_types IS DISTINCT FROM expected_column_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION 'organization owner assignment columns drifted';
  END IF;

  expected_column_names := ARRAY[
    'request_id',
    'actor_app_user_id',
    'canonical_display_name',
    'organization_workspace_id',
    'organization_membership_id',
    'organization_owner_assignment_id',
    'created_at_utc'
  ]::text[];
  expected_column_types := ARRAY[
    'uuid',
    'uuid',
    'text',
    'uuid',
    'uuid',
    'uuid',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[
    true,
    false,
    true,
    true,
    true,
    true,
    true
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
  INTO actual_column_names, actual_column_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = request_claims
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;

  IF actual_column_names IS DISTINCT FROM expected_column_names
    OR actual_column_types IS DISTINCT FROM expected_column_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION 'organization creation request claim columns drifted';
  END IF;

  expected_column_names := ARRAY[
    'organization_creation_audit_event_id',
    'creation_contract_id',
    'request_id',
    'organization_workspace_id',
    'organization_membership_id',
    'organization_owner_assignment_id',
    'created_at_utc'
  ]::text[];
  expected_column_types := ARRAY[
    'uuid',
    'text',
    'uuid',
    'uuid',
    'uuid',
    'uuid',
    'timestamp with time zone'
  ]::text[];
  expected_not_null := ARRAY[
    true,
    true,
    true,
    true,
    true,
    true,
    true
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
  INTO actual_column_names, actual_column_types, actual_not_null
  FROM pg_catalog.pg_attribute AS attribute_row
  WHERE attribute_row.attrelid = audit_events
    AND attribute_row.attnum > 0
    AND NOT attribute_row.attisdropped;

  IF actual_column_names IS DISTINCT FROM expected_column_names
    OR actual_column_types IS DISTINCT FROM expected_column_types
    OR actual_not_null IS DISTINCT FROM expected_not_null
  THEN
    RAISE EXCEPTION 'organization creation audit columns are not value-free';
  END IF;

  -- Keep the migration's small relational shape explicit: owner history has
  -- one containment FK, claims have one nullable actor FK, and all three
  -- tables have exactly the checks that protect finite temporal metadata.
  -- Later deferred trigger constraints have contype 't' and their own check.
  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint
    WHERE conrelid = owner_assignments
      AND contype <> 't'
  ) <> 4
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = owner_assignments
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = owner_assignments
              AND attribute_row.attname =
                'organization_owner_assignment_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = owner_assignments
        AND constraint_row.contype = 'f'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = owner_assignments
              AND attribute_row.attname = 'organization_membership_id'
          )
        ]::smallint[]
        AND constraint_row.confrelid =
          'app_data.organization_memberships'::regclass
        AND constraint_row.confkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid =
              'app_data.organization_memberships'::regclass
              AND attribute_row.attname = 'organization_membership_id'
          )
        ]::smallint[]
        AND constraint_row.confdeltype = 'r'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = owner_assignments
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'isfinite[[:space:]]*[(][[:space:]]*active_from_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = owner_assignments
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'isfinite[[:space:]]*[(][[:space:]]*inactive_from_utc'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'inactive_from_utc[[:space:]]*>[[:space:]]*active_from_utc'
    )
  THEN
    RAISE EXCEPTION 'organization owner assignment constraints drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint
    WHERE conrelid = request_claims
  ) <> 4
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = request_claims
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = request_claims
              AND attribute_row.attname = 'request_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = request_claims
        AND constraint_row.contype = 'f'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = request_claims
              AND attribute_row.attname = 'actor_app_user_id'
          )
        ]::smallint[]
        AND constraint_row.confrelid = 'app_data.app_users'::regclass
        AND constraint_row.confdeltype = 'n'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = request_claims
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'char_length[[:space:]]*[(][[:space:]]*canonical_display_name'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'char_length[[:space:]]*[(][[:space:]]*canonical_display_name[[:space:]]*[)][[:space:]]*>=[[:space:]]*1'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'char_length[[:space:]]*[(][[:space:]]*canonical_display_name[[:space:]]*[)][[:space:]]*<=[[:space:]]*120'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = request_claims
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'isfinite[[:space:]]*[(][[:space:]]*created_at_utc'
    )
  THEN
    RAISE EXCEPTION 'organization creation request claim constraints drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_constraint
    WHERE conrelid = audit_events
  ) <> 4
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_events
        AND constraint_row.contype = 'p'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = audit_events
              AND attribute_row.attname =
                'organization_creation_audit_event_id'
          )
        ]::smallint[]
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_events
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'creation_contract_id'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'organization-creation:v1'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_events
        AND constraint_row.contype = 'c'
        AND pg_catalog.pg_get_constraintdef(constraint_row.oid) ~* 'isfinite[[:space:]]*[(][[:space:]]*created_at_utc'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_row
      WHERE constraint_row.conrelid = audit_events
        AND constraint_row.contype = 'u'
        AND constraint_row.conkey = ARRAY[
          (
            SELECT attribute_row.attnum
            FROM pg_catalog.pg_attribute AS attribute_row
            WHERE attribute_row.attrelid = audit_events
              AND attribute_row.attname = 'request_id'
          )
        ]::smallint[]
    )
  THEN
    RAISE EXCEPTION 'organization creation audit constraints drifted';
  END IF;

  SELECT pg_catalog.pg_get_indexdef(index_row.indexrelid)
  INTO index_definition
  FROM pg_catalog.pg_index AS index_row
  WHERE index_row.indrelid = owner_assignments
    AND index_row.indexrelid =
      'app_data.organization_owner_assignments_membership_active_idx'::regclass
    AND NOT index_row.indisunique;

  IF index_definition IS NULL
    OR index_definition !~* 'USING[[:space:]]+btree[[:space:]]*[(][[:space:]]*organization_membership_id[[:space:]]*,[[:space:]]*active_from_utc[[:space:]]+DESC[[:space:]]*[)]'
  THEN
    RAISE EXCEPTION 'organization owner assignment lookup index drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_catalog.pg_index AS index_row
    WHERE index_row.indrelid = owner_assignments
  ) <> 2
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_index AS index_row
      WHERE index_row.indrelid = request_claims
    ) <> 1
    OR (
      SELECT count(*)
      FROM pg_catalog.pg_index AS index_row
      WHERE index_row.indrelid = audit_events
    ) <> 2
  THEN
    RAISE EXCEPTION 'organization creation indexes are incomplete';
  END IF;

  -- History and claim/audit rows are append-only.  The trigger event masks
  -- are checked as well as names so a renamed or weakened guard fails here.
  IF NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = owner_assignments
        AND trigger_row.tgname =
          'organization_owner_assignments_protect_history'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = to_regprocedure(
          'app_private.protect_organization_owner_assignment_history_v1()'
        )
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = owner_assignments
        AND trigger_row.tgname = 'organization_owner_assignments_validate'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = to_regprocedure(
          'app_private.validate_organization_owner_assignment_v1()'
        )
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'BEFORE INSERT OR UPDATE'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = request_claims
        AND trigger_row.tgname =
          'organization_creation_request_claims_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = to_regprocedure(
          'app_private.protect_organization_creation_request_claim_v1()'
        )
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
    OR NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_trigger AS trigger_row
      WHERE trigger_row.tgrelid = audit_events
        AND trigger_row.tgname =
          'organization_creation_audit_events_immutable'
        AND NOT trigger_row.tgisinternal
        AND trigger_row.tgfoid = to_regprocedure(
          'app_private.protect_organization_creation_audit_event_v1()'
        )
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'BEFORE (UPDATE OR DELETE|DELETE OR UPDATE)'
        AND pg_catalog.pg_get_triggerdef(trigger_row.oid) ~* 'FOR EACH ROW'
    )
  THEN
    RAISE EXCEPTION 'organization creation history triggers are incomplete';
  END IF;

  -- All writer/guard functions and all three relations share the existing
  -- private membership validator's owner; no new writer role is introduced.
  IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS relation_row
      WHERE relation_row.oid IN (
        owner_assignments,
        request_claims,
        audit_events
      )
        AND relation_row.relowner <> trusted_owner
    ) OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid IN (
        private_writer,
        runtime_bridge,
        to_regprocedure(
          'app_private.protect_organization_owner_assignment_history_v1()'
        ),
        to_regprocedure(
          'app_private.validate_organization_owner_assignment_v1()'
        ),
        to_regprocedure(
          'app_private.protect_organization_creation_request_claim_v1()'
        ),
        to_regprocedure(
          'app_private.protect_organization_creation_audit_event_v1()'
        )
      )
        AND procedure_row.proowner <> trusted_owner
    )
  THEN
    RAISE EXCEPTION 'organization creation owner boundary drifted';
  END IF;

  -- Trigger functions are volatile by definition, and every function has a
  -- fixed catalog-only path so SECURITY DEFINER cannot resolve attacker-
  -- controlled names.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid IN (
      private_writer,
      runtime_bridge,
      to_regprocedure(
        'app_private.protect_organization_owner_assignment_history_v1()'
      ),
      to_regprocedure(
        'app_private.validate_organization_owner_assignment_v1()'
      ),
      to_regprocedure(
        'app_private.protect_organization_creation_request_claim_v1()'
      ),
      to_regprocedure(
        'app_private.protect_organization_creation_audit_event_v1()'
      )
    )
      AND (
        NOT procedure_row.prosecdef
        OR procedure_row.provolatile <> 'v'
        OR procedure_row.proconfig IS DISTINCT FROM
          ARRAY['search_path=pg_catalog']::text[]
      )
  )
  THEN
    RAISE EXCEPTION 'organization creation functions are not protected';
  END IF;

  function_arguments :=
    pg_catalog.pg_get_function_identity_arguments(private_writer);
  IF function_arguments IS DISTINCT FROM
    'trusted_app_user_id uuid, requested_request_id uuid, requested_display_name text'
  THEN
    RAISE EXCEPTION 'private organization creation signature drifted';
  END IF;

  function_arguments :=
    pg_catalog.pg_get_function_identity_arguments(runtime_bridge);
  IF function_arguments IS DISTINCT FROM
    'trusted_issuer text, trusted_subject text, requested_request_id uuid, requested_display_name text'
  THEN
    RAISE EXCEPTION 'organization identity bridge signature drifted';
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
        'creation_contract_id',
        'organization_workspace_id',
        'organization_membership_id',
        'organization_owner_assignment_id',
        'created_at_utc'
      ]::text[]
      OR actual_result_types IS DISTINCT FROM ARRAY[
        'text',
        'uuid',
        'uuid',
        'uuid',
        'timestamp with time zone'
      ]::text[]
    THEN
      RAISE EXCEPTION 'organization creation result row drifted';
    END IF;
  END LOOP;

  -- PUBLIC has no callable seam.  runtime receives exactly the external
  -- identity bridge and cannot reach private functions or storage directly.
  IF NOT has_function_privilege(
      'tongxingzhe_runtime', runtime_bridge, 'EXECUTE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime', private_writer, 'EXECUTE'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges AS privilege_row
      WHERE privilege_row.routine_schema IN ('app_data', 'app_private')
        AND privilege_row.routine_name IN (
          'create_organization_v1',
          'create_organization_for_identity_v1',
          'protect_organization_owner_assignment_history_v1',
          'validate_organization_owner_assignment_v1',
          'protect_organization_creation_request_claim_v1',
          'protect_organization_creation_audit_event_v1'
        )
        AND privilege_row.privilege_type = 'EXECUTE'
        AND (
          privilege_row.grantee = 'PUBLIC'
          OR privilege_row.grantee = 'tongxingzhe_runtime'
            AND privilege_row.routine_name <> 'create_organization_for_identity_v1'
        )
    )
  THEN
    RAISE EXCEPTION 'organization creation function ACL is incorrect';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime', owner_assignments,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', request_claims,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', audit_events,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR EXISTS (
      SELECT 1
      FROM information_schema.table_privileges AS privilege_row
      WHERE (
          (
            privilege_row.table_schema = 'app_data'
            AND privilege_row.table_name =
              'organization_owner_assignments'
          ) OR (
            privilege_row.table_schema = 'app_private'
            AND privilege_row.table_name IN (
              'organization_creation_request_claims',
              'organization_creation_audit_events'
            )
          )
        )
        AND privilege_row.grantee IN ('PUBLIC', 'tongxingzhe_runtime')
    )
  THEN
    RAISE EXCEPTION 'organization creation storage ACL is incorrect';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0084_organization_creation'
  ) <> 1
  THEN
    RAISE EXCEPTION 'organization creation migration was not recorded once';
  END IF;
END
$check$;
