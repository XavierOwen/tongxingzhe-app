-- Slice 7CU: private organization deletion and restoration core.
-- A row records the current attempt.  Expiry is derived from the database
-- clock; this migration does not perform purge or expose a runtime bridge.

DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1 FROM app_data.workspaces
    WHERE workspace_kind = 'organization' AND deleted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization deletion lifecycle provenance unavailable';
  END IF;
END
$preflight$;

CREATE TABLE app_private.organization_deletion_current (
  organization_workspace_id uuid PRIMARY KEY,
  deletion_request_id uuid NOT NULL,
  effective_at_utc timestamptz NOT NULL,
  purge_after_utc timestamptz NOT NULL,
  status text NOT NULL,
  restored_at_utc timestamptz,
  CONSTRAINT organization_deletion_current_state_check CHECK (
    (status = 'deletion_pending' AND restored_at_utc IS NULL)
    OR (status = 'restored' AND restored_at_utc IS NOT NULL)
  ),
  CONSTRAINT organization_deletion_current_time_check CHECK (
    isfinite(effective_at_utc) AND isfinite(purge_after_utc)
    AND purge_after_utc = effective_at_utc + interval '720 hours'
    AND (restored_at_utc IS NULL OR (
      isfinite(restored_at_utc)
      AND restored_at_utc >= effective_at_utc
      AND restored_at_utc < purge_after_utc
    ))
  )
);

CREATE TABLE app_private.organization_deletion_request_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  organization_workspace_id uuid NOT NULL,
  deletion_request_id uuid NOT NULL,
  effective_at_utc timestamptz NOT NULL,
  purge_after_utc timestamptz NOT NULL,
  CONSTRAINT organization_deletion_request_claim_time_check CHECK (
    isfinite(effective_at_utc) AND isfinite(purge_after_utc)
    AND purge_after_utc = effective_at_utc + interval '720 hours'
  ),
  CONSTRAINT organization_deletion_request_claim_attempt_check CHECK (
    request_id = deletion_request_id
  )
);

CREATE TABLE app_private.organization_deletion_restore_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  organization_workspace_id uuid NOT NULL,
  deletion_request_id uuid NOT NULL,
  restored_at_utc timestamptz NOT NULL,
  CONSTRAINT organization_deletion_restore_claim_time_check CHECK (
    isfinite(restored_at_utc)
  )
);

CREATE TABLE app_private.organization_deletion_audit_events (
  audit_event_id uuid PRIMARY KEY,
  operation text NOT NULL,
  request_id uuid NOT NULL,
  organization_workspace_id uuid NOT NULL,
  deletion_request_id uuid NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  CONSTRAINT organization_deletion_audit_operation_check CHECK (
    operation IN ('organization-deletion-request:v1', 'organization-deletion-restore:v1')
  ),
  CONSTRAINT organization_deletion_audit_time_check CHECK (isfinite(occurred_at_utc)),
  CONSTRAINT organization_deletion_audit_request_unique UNIQUE (operation, request_id)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_deletion_current,
  app_private.organization_deletion_request_claims,
  app_private.organization_deletion_restore_claims,
  app_private.organization_deletion_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_organization_deletion_claim_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization deletion claim cannot be deleted';
  END IF;
  IF OLD.actor_app_user_id IS NULL
    OR NEW.actor_app_user_id IS NOT NULL
    OR to_jsonb(OLD) - 'actor_app_user_id'
      IS DISTINCT FROM to_jsonb(NEW) - 'actor_app_user_id'
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization deletion claim is immutable';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_deletion_request_claims_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_deletion_request_claims
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_deletion_claim_v1();

CREATE TRIGGER organization_deletion_restore_claims_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_deletion_restore_claims
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_deletion_claim_v1();

CREATE FUNCTION app_private.protect_organization_deletion_audit_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '55000',
    MESSAGE = 'organization deletion audit is append-only';
END
$function$;

CREATE TRIGGER organization_deletion_audit_events_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_deletion_audit_events
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_deletion_audit_v1();

CREATE FUNCTION app_private.request_organization_deletion_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  organization_deletion_contract_id text,
  organization_workspace_id uuid,
  deletion_request_id uuid,
  effective_at_utc timestamptz,
  purge_after_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  actor_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  claim_row app_private.organization_deletion_request_claims%ROWTYPE;
  attempt_row app_private.organization_deletion_current%ROWTYPE;
  reference_time timestamptz;
BEGIN
  IF requested_request_id IS NULL OR requested_organization_workspace_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization deletion request';
  END IF;
  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion forbidden';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization deletion unavailable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'organization-deletion-request:' || requested_request_id::text, 0
  ));

  SELECT app_user.status INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_app_user_id
  FOR UPDATE;

  PERFORM app_private.lock_organization_governance_v1(
    requested_organization_workspace_id
  );

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id
  FOR UPDATE;

  SELECT claim.* INTO claim_row
  FROM app_private.organization_deletion_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  IF FOUND THEN
    SELECT attempt.* INTO attempt_row
    FROM app_private.organization_deletion_current AS attempt
    WHERE attempt.organization_workspace_id = requested_organization_workspace_id;
    IF claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR workspace_kind IS DISTINCT FROM 'organization'
      OR claim_row.deletion_request_id IS DISTINCT FROM requested_request_id
      OR attempt_row.deletion_request_id IS DISTINCT FROM requested_request_id
      OR attempt_row.status IS DISTINCT FROM 'deletion_pending'
      OR workspace_deleted_at IS DISTINCT FROM claim_row.effective_at_utc
      OR clock_timestamp() >= claim_row.purge_after_utc
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'organization deletion idempotency conflict';
    END IF;
    RETURN QUERY SELECT 'organization-deletion-request:v1'::text,
      claim_row.organization_workspace_id, claim_row.deletion_request_id,
      claim_row.effective_at_utc, claim_row.purge_after_utc;
    RETURN;
  END IF;

  IF workspace_kind IS DISTINCT FROM 'organization' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion forbidden';
  END IF;
  IF actor_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion forbidden';
  END IF;

  -- The governance lock excludes membership and owner changes.  Read current
  -- authority after the last waiting lock, using the same database clock as
  -- the effective time and deadline.
  reference_time := clock_timestamp();
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS membership
    JOIN app_data.organization_owner_assignments AS owner_assignment
      ON owner_assignment.organization_membership_id =
        membership.organization_membership_id
    WHERE membership.organization_workspace_id = requested_organization_workspace_id
      AND membership.app_user_id = trusted_app_user_id
      AND tstzrange(membership.active_from_utc, membership.inactive_from_utc, '[)')
        @> reference_time
      AND tstzrange(owner_assignment.active_from_utc,
        owner_assignment.inactive_from_utc, '[)') @> reference_time
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion forbidden';
  END IF;

  SELECT attempt.* INTO attempt_row
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id = requested_organization_workspace_id;
  IF attempt_row.status = 'deletion_pending' THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'organization deletion idempotency conflict';
  END IF;
  IF workspace_deleted_at IS NOT NULL
    OR (attempt_row.status IS NOT NULL AND attempt_row.status <> 'restored')
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization deletion unavailable';
  END IF;

  UPDATE app_data.workspaces AS workspace
  SET deleted_at = reference_time
  WHERE workspace.workspace_id = requested_organization_workspace_id;

  INSERT INTO app_private.organization_deletion_current (
    organization_workspace_id, deletion_request_id, effective_at_utc,
    purge_after_utc, status, restored_at_utc
  ) VALUES (
    requested_organization_workspace_id, requested_request_id, reference_time,
    reference_time + interval '720 hours', 'deletion_pending', NULL
  ) ON CONFLICT ON CONSTRAINT organization_deletion_current_pkey DO UPDATE SET
    deletion_request_id = EXCLUDED.deletion_request_id,
    effective_at_utc = EXCLUDED.effective_at_utc,
    purge_after_utc = EXCLUDED.purge_after_utc,
    status = EXCLUDED.status,
    restored_at_utc = NULL;

  INSERT INTO app_private.organization_deletion_request_claims (
    request_id, actor_app_user_id, organization_workspace_id,
    deletion_request_id, effective_at_utc, purge_after_utc
  ) VALUES (
    requested_request_id, trusted_app_user_id,
    requested_organization_workspace_id, requested_request_id,
    reference_time, reference_time + interval '720 hours'
  );

  INSERT INTO app_private.organization_deletion_audit_events (
    audit_event_id, operation, request_id, organization_workspace_id,
    deletion_request_id, occurred_at_utc
  ) VALUES (
    gen_random_uuid(), 'organization-deletion-request:v1',
    requested_request_id, requested_organization_workspace_id,
    requested_request_id, reference_time
  );

  RETURN QUERY SELECT 'organization-deletion-request:v1'::text,
    requested_organization_workspace_id, requested_request_id,
    reference_time, reference_time + interval '720 hours';
END
$function$;

CREATE FUNCTION app_private.restore_organization_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid,
  requested_organization_workspace_id uuid,
  expected_deletion_request_id uuid
)
RETURNS TABLE (
  organization_deletion_restore_contract_id text,
  organization_workspace_id uuid,
  deletion_request_id uuid,
  restored_at_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  actor_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  claim_row app_private.organization_deletion_restore_claims%ROWTYPE;
  attempt_row app_private.organization_deletion_current%ROWTYPE;
  reference_time timestamptz;
BEGIN
  IF requested_request_id IS NULL OR requested_organization_workspace_id IS NULL
    OR expected_deletion_request_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization restoration request';
  END IF;
  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization restoration forbidden';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization restoration unavailable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'organization-deletion-restore-request:' || requested_request_id::text, 0
  ));

  SELECT app_user.status INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_app_user_id
  FOR UPDATE;

  PERFORM app_private.lock_organization_governance_v1(
    requested_organization_workspace_id
  );

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id
  FOR UPDATE;

  SELECT attempt.* INTO attempt_row
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id = requested_organization_workspace_id;

  SELECT claim.* INTO claim_row
  FROM app_private.organization_deletion_restore_claims AS claim
  WHERE claim.request_id = requested_request_id;
  IF FOUND THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR workspace_kind IS DISTINCT FROM 'organization'
      OR claim_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
      OR attempt_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
      OR attempt_row.status IS DISTINCT FROM 'restored'
      OR workspace_deleted_at IS NOT NULL
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'organization restoration idempotency conflict';
    END IF;
    RETURN QUERY SELECT 'organization-deletion-restore:v1'::text,
      claim_row.organization_workspace_id, claim_row.deletion_request_id,
      claim_row.restored_at_utc;
    RETURN;
  END IF;

  IF workspace_kind IS DISTINCT FROM 'organization'
    OR actor_status IS DISTINCT FROM 'active'
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization restoration forbidden';
  END IF;

  reference_time := clock_timestamp();
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS membership
    JOIN app_data.organization_owner_assignments AS owner_assignment
      ON owner_assignment.organization_membership_id =
        membership.organization_membership_id
    WHERE membership.organization_workspace_id = requested_organization_workspace_id
      AND membership.app_user_id = trusted_app_user_id
      AND tstzrange(membership.active_from_utc, membership.inactive_from_utc, '[)')
        @> reference_time
      AND tstzrange(owner_assignment.active_from_utc,
        owner_assignment.inactive_from_utc, '[)') @> reference_time
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization restoration forbidden';
  END IF;

  IF attempt_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
    OR attempt_row.status IS DISTINCT FROM 'deletion_pending'
    OR workspace_deleted_at IS DISTINCT FROM attempt_row.effective_at_utc
    OR reference_time < attempt_row.effective_at_utc
    OR reference_time >= attempt_row.purge_after_utc
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'organization restoration idempotency conflict';
  END IF;

  UPDATE app_data.workspaces AS workspace SET deleted_at = NULL
  WHERE workspace.workspace_id = requested_organization_workspace_id;
  UPDATE app_private.organization_deletion_current AS attempt
  SET status = 'restored', restored_at_utc = reference_time
  WHERE attempt.organization_workspace_id = requested_organization_workspace_id;

  INSERT INTO app_private.organization_deletion_restore_claims (
    request_id, actor_app_user_id, organization_workspace_id,
    deletion_request_id, restored_at_utc
  ) VALUES (
    requested_request_id, trusted_app_user_id, requested_organization_workspace_id,
    expected_deletion_request_id, reference_time
  );

  INSERT INTO app_private.organization_deletion_audit_events (
    audit_event_id, operation, request_id, organization_workspace_id,
    deletion_request_id, occurred_at_utc
  ) VALUES (
    gen_random_uuid(), 'organization-deletion-restore:v1',
    requested_request_id, requested_organization_workspace_id,
    expected_deletion_request_id, reference_time
  );

  RETURN QUERY SELECT 'organization-deletion-restore:v1'::text,
    requested_organization_workspace_id, expected_deletion_request_id,
    reference_time;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_deletion_claim_v1(),
  app_private.protect_organization_deletion_audit_v1(),
  app_private.request_organization_deletion_v1(uuid,uuid,uuid),
  app_private.restore_organization_v1(uuid,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
  owned_table text;
  owned_function text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  FOREACH owned_table IN ARRAY ARRAY[
    'organization_deletion_current', 'organization_deletion_request_claims',
    'organization_deletion_restore_claims', 'organization_deletion_audit_events'
  ] LOOP
    EXECUTE format('ALTER TABLE app_private.%I OWNER TO %I',
      owned_table, trusted_owner);
  END LOOP;
  FOREACH owned_function IN ARRAY ARRAY[
    'protect_organization_deletion_claim_v1()',
    'protect_organization_deletion_audit_v1()',
    'request_organization_deletion_v1(uuid,uuid,uuid)',
    'restore_organization_v1(uuid,uuid,uuid,uuid)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION app_private.%s OWNER TO %I',
      owned_function, trusted_owner);
  END LOOP;
END
$owner$;
