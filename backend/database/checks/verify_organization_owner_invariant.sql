\set ON_ERROR_STOP on

-- Structural contract for Slice 7D7.  Behavioural and lock-order examples
-- live in the rollback fixture and the independent-session concurrency check.
DO $check$
DECLARE
  app_users_table regclass := to_regclass('app_data.app_users');
  workspaces_table regclass := to_regclass('app_data.workspaces');
  memberships_table regclass := to_regclass(
    'app_data.organization_memberships'
  );
  assignments_table regclass := to_regclass(
    'app_data.organization_owner_assignments'
  );
  membership_validator regprocedure := to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  governance_lock regprocedure := to_regprocedure(
    'app_private.lock_organization_governance_v1(uuid)'
  );
  governance_fence regprocedure := to_regprocedure(
    'app_private.lock_organization_governance_for_mutation_v1()'
  );
  require_owner regprocedure := to_regprocedure(
    'app_private.require_organization_active_owner_v1(uuid)'
  );
  enforce_owner regprocedure := to_regprocedure(
    'app_private.enforce_organization_active_owner_v1()'
  );
  trusted_owner oid;
  runtime_role oid;
  function_row record;
  expected_trigger record;
  trigger_row record;
  membership_definition text;
  governance_definition text;
  require_definition text;
BEGIN
  IF app_users_table IS NULL
    OR workspaces_table IS NULL
    OR memberships_table IS NULL
    OR assignments_table IS NULL
    OR membership_validator IS NULL
    OR governance_lock IS NULL
    OR governance_fence IS NULL
    OR require_owner IS NULL
    OR enforce_owner IS NULL
  THEN
    RAISE EXCEPTION 'organization owner invariant objects are incomplete';
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
    RAISE EXCEPTION 'organization owner invariant owner cannot be runtime';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0085_organization_owner_invariant'
  ) <> 1
  THEN
    RAISE EXCEPTION 'organization owner invariant migration was not recorded once';
  END IF;

  -- The four names and argument types are the only new private API.  The
  -- return types distinguish ordinary lock/check helpers from trigger entry
  -- points without depending on implementation text.
  IF pg_catalog.pg_get_function_identity_arguments(governance_lock)
      IS DISTINCT FROM 'requested_workspace_id uuid'
    OR pg_catalog.pg_get_function_result(governance_lock) IS DISTINCT FROM
      'void'
    OR pg_catalog.pg_get_function_identity_arguments(governance_fence)
      IS DISTINCT FROM ''
    OR pg_catalog.pg_get_function_result(governance_fence) IS DISTINCT FROM
      'trigger'
    OR pg_catalog.pg_get_function_identity_arguments(require_owner)
      IS DISTINCT FROM 'requested_workspace_id uuid'
    OR pg_catalog.pg_get_function_result(require_owner) IS DISTINCT FROM
      'void'
    OR pg_catalog.pg_get_function_identity_arguments(enforce_owner)
      IS DISTINCT FROM ''
    OR pg_catalog.pg_get_function_result(enforce_owner) IS DISTINCT FROM
      'trigger'
  THEN
    RAISE EXCEPTION 'organization owner invariant function signatures drifted';
  END IF;

  FOR function_row IN
    SELECT procedure_row.oid,
           procedure_row.proowner,
           procedure_row.prosecdef,
           procedure_row.provolatile,
           procedure_row.proconfig
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid IN (
      governance_lock,
      governance_fence,
      require_owner,
      enforce_owner
    )
  LOOP
    IF function_row.proowner <> trusted_owner
      OR NOT function_row.prosecdef
      OR function_row.provolatile <> 'v'
      OR function_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
    THEN
      RAISE EXCEPTION
        'organization owner invariant function security contract drifted: %',
        function_row.oid;
    END IF;
  END LOOP;

  SELECT pg_catalog.pg_get_functiondef(governance_lock)
  INTO governance_definition;
  IF governance_definition NOT LIKE '%hashtextextended(%'
    OR governance_definition NOT LIKE '%organization-governance:%'
    OR governance_definition NOT LIKE '%pg_advisory_xact_lock%'
  THEN
    RAISE EXCEPTION 'organization governance lock helper contract drifted';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(require_owner)
  INTO require_definition;
  IF require_definition NOT LIKE '%ERRCODE = ''23514''%'
    OR require_definition NOT LIKE
      '%MESSAGE = ''organization must retain an active owner''%'
  THEN
    RAISE EXCEPTION 'organization active-owner error contract drifted';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(membership_validator)
  INTO membership_definition;
  IF position(
      'app_private.lock_organization_governance_v1'
      IN membership_definition
    ) = 0
    OR position('organization-membership:' IN membership_definition) = 0
    OR position(
      'app_private.lock_organization_governance_v1'
      IN membership_definition
    ) > position('organization-membership:' IN membership_definition)
  THEN
    RAISE EXCEPTION
      'organization membership validator lock order is not governance first';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(governance_fence)
  INTO governance_definition;
  IF governance_definition NOT LIKE
      '%app_private.lock_organization_governance_v1%'
  THEN
    RAISE EXCEPTION 'organization mutation fence bypasses governance helper';
  END IF;

  -- No public or runtime caller may invoke any of the four private entry
  -- points.  Use the catalog ACL as well as effective runtime privilege so a
  -- role grant cannot silently reopen the seam.
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
      governance_lock,
      governance_fence,
      require_owner,
      enforce_owner
    )
      AND privilege_row.privilege_type = 'EXECUTE'
      AND (
        privilege_row.grantee = 0
        OR privilege_row.grantee = runtime_role
      )
  )
    OR has_function_privilege(
      'tongxingzhe_runtime', governance_lock, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime', governance_fence, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime', require_owner, 'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime', enforce_owner, 'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'organization owner invariant function ACL is open';
  END IF;

  -- Mutation privileges are closed, but existing reader SELECT grants are
  -- intentional and are not part of this check.
  IF has_table_privilege(
      'tongxingzhe_runtime', app_users_table,
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', workspaces_table,
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', memberships_table,
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime', assignments_table,
      'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
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
        app_users_table,
        workspaces_table,
        memberships_table,
        assignments_table
      )
        AND privilege_row.grantee = 0
        AND privilege_row.privilege_type IN (
          'INSERT',
          'UPDATE',
          'DELETE',
          'TRUNCATE',
          'REFERENCES',
          'TRIGGER'
        )
    )
  THEN
    RAISE EXCEPTION 'organization owner invariant table mutation ACL is open';
  END IF;

  -- Each relation has one enabled BEFORE ROW fence.  The first three cover
  -- all row writes; app_users only needs status UPDATE because INSERT and
  -- DELETE cannot change an existing owner's status under current FKs.
  FOR expected_trigger IN
    SELECT *
    FROM (VALUES
      (
        workspaces_table,
        'workspaces_governance_fence'::name,
        28,
        false
      ),
      (
        memberships_table,
        'organization_memberships_governance_fence'::name,
        28,
        false
      ),
      (
        assignments_table,
        'organization_owner_assignments_governance_fence'::name,
        28,
        false
      ),
      (
        app_users_table,
        'app_users_governance_fence'::name,
        16,
        true
      )
    ) AS expected(relation_oid, trigger_name, event_mask, status_update)
  LOOP
    IF (
      SELECT count(*)
      FROM pg_catalog.pg_trigger
      WHERE tgrelid = expected_trigger.relation_oid
        AND tgfoid = governance_fence
        AND NOT tgisinternal
    ) <> 1
    THEN
      RAISE EXCEPTION
        'organization mutation fence count is incorrect: %',
        expected_trigger.relation_oid;
    END IF;

    SELECT trigger_catalog.tgtype,
           trigger_catalog.tgfoid,
           trigger_catalog.tgenabled,
           pg_catalog.pg_get_triggerdef(trigger_catalog.oid)
    INTO trigger_row
    FROM pg_catalog.pg_trigger AS trigger_catalog
    WHERE trigger_catalog.tgrelid = expected_trigger.relation_oid
      AND trigger_catalog.tgname = expected_trigger.trigger_name
      AND NOT trigger_catalog.tgisinternal;

    IF NOT FOUND
      OR trigger_row.tgfoid <> governance_fence
      OR trigger_row.tgenabled <> 'O'
      OR (trigger_row.tgtype & 1) <> 1
      OR (trigger_row.tgtype & 2) <> 2
      OR (trigger_row.tgtype & 28) <> expected_trigger.event_mask
      OR (
        expected_trigger.status_update
        AND trigger_row.pg_get_triggerdef NOT ILIKE '%BEFORE UPDATE OF status%'
      )
    THEN
      RAISE EXCEPTION
        'organization mutation fence trigger drifted: %',
        expected_trigger.trigger_name;
    END IF;
  END LOOP;

  -- The corresponding AFTER ROW triggers must be constraint triggers and be
  -- deferred until the final owner set is visible at transaction end.
  FOR expected_trigger IN
    SELECT *
    FROM (VALUES
      (
        workspaces_table,
        'workspaces_active_owner_invariant'::name,
        28
      ),
      (
        memberships_table,
        'organization_memberships_active_owner_invariant'::name,
        28
      ),
      (
        assignments_table,
        'organization_owner_assignments_active_owner_invariant'::name,
        28
      ),
      (
        app_users_table,
        'app_users_active_owner_invariant'::name,
        16
      )
    ) AS expected(relation_oid, trigger_name, event_mask)
  LOOP
    IF (
      SELECT count(*)
      FROM pg_catalog.pg_trigger
      WHERE tgrelid = expected_trigger.relation_oid
        AND tgfoid = enforce_owner
        AND NOT tgisinternal
    ) <> 1
    THEN
      RAISE EXCEPTION
        'organization active-owner trigger count is incorrect: %',
        expected_trigger.relation_oid;
    END IF;

    SELECT trigger_catalog.tgtype,
           trigger_catalog.tgfoid,
           trigger_catalog.tgconstraint,
           trigger_catalog.tgdeferrable,
           trigger_catalog.tginitdeferred,
           trigger_catalog.tgenabled,
           pg_catalog.pg_get_triggerdef(trigger_catalog.oid)
    INTO trigger_row
    FROM pg_catalog.pg_trigger AS trigger_catalog
    WHERE trigger_catalog.tgrelid = expected_trigger.relation_oid
      AND trigger_catalog.tgname = expected_trigger.trigger_name
      AND NOT trigger_catalog.tgisinternal;

    IF NOT FOUND
      OR trigger_row.tgfoid <> enforce_owner
      OR trigger_row.tgconstraint = 0
      OR NOT trigger_row.tgdeferrable
      OR NOT trigger_row.tginitdeferred
      OR trigger_row.tgenabled <> 'O'
      OR (trigger_row.tgtype & 1) <> 1
      OR (trigger_row.tgtype & 2) <> 0
      OR (trigger_row.tgtype & 28) <> expected_trigger.event_mask
      OR trigger_row.pg_get_triggerdef NOT ILIKE '%CONSTRAINT TRIGGER%'
      OR trigger_row.pg_get_triggerdef NOT ILIKE
        '%DEFERRABLE INITIALLY DEFERRED%'
      OR trigger_row.pg_get_triggerdef NOT ILIKE '%FOR EACH ROW%'
    THEN
      RAISE EXCEPTION
        'organization active-owner constraint trigger drifted: %',
        expected_trigger.trigger_name;
    END IF;
  END LOOP;
END
$check$;
