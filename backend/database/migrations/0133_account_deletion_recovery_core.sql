-- Account recovery preserves existing relationships; terminal deletion is separate.
DO $preflight$
BEGIN
  IF EXISTS (SELECT 1 FROM app_data.app_users WHERE status = 'deletion_pending') THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'account deletion lifecycle provenance unavailable';
  END IF;
END
$preflight$;

CREATE TABLE app_private.account_deletion_request_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  deletion_request_id uuid NOT NULL,
  effective_at_utc timestamptz NOT NULL,
  purge_after_utc timestamptz NOT NULL,
  CONSTRAINT account_deletion_request_cycle_check CHECK (request_id = deletion_request_id),
  CONSTRAINT account_deletion_request_time_check CHECK (
    isfinite(effective_at_utc) AND isfinite(purge_after_utc)
    AND purge_after_utc = effective_at_utc + interval '720 hours'
  )
);

CREATE TABLE app_private.account_deletion_current (
  app_user_id uuid PRIMARY KEY REFERENCES app_data.app_users(app_user_id) ON DELETE CASCADE,
  deletion_request_id uuid NOT NULL,
  effective_at_utc timestamptz NOT NULL,
  purge_after_utc timestamptz NOT NULL,
  status text NOT NULL,
  restored_at_utc timestamptz,
  CONSTRAINT account_deletion_current_request_fk FOREIGN KEY (deletion_request_id)
    REFERENCES app_private.account_deletion_request_claims(request_id),
  CONSTRAINT account_deletion_current_state_check CHECK (
    (status = 'deletion_pending' AND restored_at_utc IS NULL)
    OR (status = 'restored' AND restored_at_utc IS NOT NULL)
  ),
  CONSTRAINT account_deletion_current_time_check CHECK (
    isfinite(effective_at_utc) AND isfinite(purge_after_utc)
    AND purge_after_utc = effective_at_utc + interval '720 hours'
    AND (restored_at_utc IS NULL OR (
      isfinite(restored_at_utc) AND restored_at_utc >= effective_at_utc
      AND restored_at_utc < purge_after_utc
    ))
  )
);

CREATE TABLE app_private.account_deletion_restore_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  deletion_request_id uuid NOT NULL,
  restored_at_utc timestamptz NOT NULL CHECK (isfinite(restored_at_utc)),
  CONSTRAINT account_deletion_restore_request_fk FOREIGN KEY (deletion_request_id)
    REFERENCES app_private.account_deletion_request_claims(request_id)
);

CREATE TABLE app_private.account_deletion_audit_events (
  audit_event_id uuid PRIMARY KEY,
  operation text NOT NULL CHECK (
    operation IN ('account-deletion-request:v1', 'account-deletion-restore:v1')
  ),
  request_id uuid NOT NULL,
  deletion_request_id uuid NOT NULL,
  occurred_at_utc timestamptz NOT NULL CHECK (isfinite(occurred_at_utc)),
  CONSTRAINT account_deletion_audit_request_unique UNIQUE (operation, request_id)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.account_deletion_current,
  app_private.account_deletion_request_claims,
  app_private.account_deletion_restore_claims,
  app_private.account_deletion_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_account_deletion_claim_v1()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account deletion claim cannot be deleted';
  END IF;
  IF OLD.actor_app_user_id IS NULL OR NEW.actor_app_user_id IS NOT NULL
    OR to_jsonb(OLD) - 'actor_app_user_id' IS DISTINCT FROM to_jsonb(NEW) - 'actor_app_user_id'
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account deletion claim is immutable';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER account_deletion_request_claims_immutable
BEFORE UPDATE OR DELETE ON app_private.account_deletion_request_claims
FOR EACH ROW EXECUTE FUNCTION app_private.protect_account_deletion_claim_v1();

CREATE TRIGGER account_deletion_restore_claims_immutable
BEFORE UPDATE OR DELETE ON app_private.account_deletion_restore_claims
FOR EACH ROW EXECUTE FUNCTION app_private.protect_account_deletion_claim_v1();

CREATE TRIGGER account_deletion_audit_events_immutable
BEFORE UPDATE OR DELETE ON app_private.account_deletion_audit_events
FOR EACH ROW EXECUTE FUNCTION app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_private.request_account_deletion_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid
)
RETURNS TABLE (
  account_deletion_contract_id text,
  deletion_request_id uuid,
  effective_at_utc timestamptz,
  purge_after_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  actor_status text;
  organization_id uuid;
  claim_row app_private.account_deletion_request_claims%ROWTYPE;
  attempt_row app_private.account_deletion_current%ROWTYPE;
  cycle_row app_private.account_deletion_request_claims%ROWTYPE;
  reference_time timestamptz;
BEGIN
  IF requested_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid account deletion request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'account deletion requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account deletion forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'account-deletion-request:' || requested_request_id::text, 0
  ));
  SELECT actor.status INTO actor_status FROM app_data.app_users AS actor
  WHERE actor.app_user_id = trusted_app_user_id FOR UPDATE;

  FOR organization_id IN
    SELECT DISTINCT membership.organization_workspace_id
    FROM app_data.organization_memberships AS membership
    WHERE membership.app_user_id = trusted_app_user_id
    ORDER BY membership.organization_workspace_id
  LOOP
    PERFORM app_private.lock_organization_governance_v1(organization_id);
  END LOOP;

  reference_time := clock_timestamp();
  SELECT claim.* INTO claim_row FROM app_private.account_deletion_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  IF claim_row.request_id IS NOT NULL AND claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account deletion idempotency conflict';
  END IF;
  SELECT attempt.* INTO attempt_row FROM app_private.account_deletion_current AS attempt
  WHERE attempt.app_user_id = trusted_app_user_id;
  IF FOUND THEN
    SELECT claim.* INTO cycle_row FROM app_private.account_deletion_request_claims AS claim
    WHERE claim.request_id = attempt_row.deletion_request_id;
    IF cycle_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR cycle_row.effective_at_utc IS DISTINCT FROM attempt_row.effective_at_utc
      OR cycle_row.purge_after_utc IS DISTINCT FROM attempt_row.purge_after_utc
      OR (actor_status = 'active' AND attempt_row.status <> 'restored')
      OR (actor_status = 'deletion_pending' AND attempt_row.status <> 'deletion_pending')
    THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account deletion unavailable';
    END IF;
  ELSIF actor_status = 'deletion_pending' THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account deletion unavailable';
  END IF;

  IF claim_row.request_id IS NOT NULL THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR actor_status IS DISTINCT FROM 'deletion_pending'
      OR attempt_row.deletion_request_id IS DISTINCT FROM requested_request_id
      OR attempt_row.status IS DISTINCT FROM 'deletion_pending'
      OR reference_time < claim_row.effective_at_utc
      OR reference_time >= claim_row.purge_after_utc
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account deletion idempotency conflict';
    END IF;
    RETURN QUERY SELECT 'account-deletion-request:v1'::text, claim_row.deletion_request_id,
      claim_row.effective_at_utc, claim_row.purge_after_utc;
    RETURN;
  END IF;

  IF actor_status = 'deletion_pending' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account deletion idempotency conflict';
  END IF;
  IF actor_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account deletion forbidden';
  END IF;

  -- Other users take this governance fence before changing status; do not lock them in reverse order.
  IF EXISTS (
    SELECT 1 FROM app_data.workspaces AS workspace
    WHERE workspace.workspace_kind = 'organization'
      AND workspace.workspace_id IN (
        SELECT membership.organization_workspace_id
        FROM app_data.organization_memberships AS membership
        WHERE membership.app_user_id = trusted_app_user_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM app_data.organization_memberships AS membership
        JOIN app_data.organization_owner_assignments AS assignment
          ON assignment.organization_membership_id = membership.organization_membership_id
        JOIN app_data.app_users AS owner_user ON owner_user.app_user_id = membership.app_user_id
        WHERE membership.organization_workspace_id = workspace.workspace_id
          AND owner_user.app_user_id <> trusted_app_user_id AND owner_user.status = 'active'
          AND tstzrange(membership.active_from_utc, membership.inactive_from_utc, '[)') @> reference_time
          AND tstzrange(assignment.active_from_utc, assignment.inactive_from_utc, '[)') @> reference_time
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account deletion forbidden';
  END IF;

  INSERT INTO app_private.account_deletion_request_claims (
    request_id, actor_app_user_id, deletion_request_id, effective_at_utc, purge_after_utc
  ) VALUES (
    requested_request_id, trusted_app_user_id, requested_request_id,
    reference_time, reference_time + interval '720 hours'
  );
  UPDATE app_data.app_users AS actor SET status = 'deletion_pending'
  WHERE actor.app_user_id = trusted_app_user_id;
  INSERT INTO app_private.account_deletion_current (
    app_user_id, deletion_request_id, effective_at_utc, purge_after_utc, status, restored_at_utc
  ) VALUES (
    trusted_app_user_id, requested_request_id, reference_time,
    reference_time + interval '720 hours', 'deletion_pending', NULL
  ) ON CONFLICT ON CONSTRAINT account_deletion_current_pkey DO UPDATE SET
    deletion_request_id = EXCLUDED.deletion_request_id,
    effective_at_utc = EXCLUDED.effective_at_utc,
    purge_after_utc = EXCLUDED.purge_after_utc,
    status = EXCLUDED.status, restored_at_utc = NULL;
  INSERT INTO app_private.account_deletion_audit_events (
    audit_event_id, operation, request_id, deletion_request_id, occurred_at_utc
  ) VALUES (
    gen_random_uuid(), 'account-deletion-request:v1', requested_request_id,
    requested_request_id, reference_time
  );
  RETURN QUERY SELECT 'account-deletion-request:v1'::text, requested_request_id,
    reference_time, reference_time + interval '720 hours';
END
$function$;

CREATE FUNCTION app_private.restore_account_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid,
  expected_deletion_request_id uuid
)
RETURNS TABLE (
  account_deletion_restore_contract_id text,
  deletion_request_id uuid,
  restored_at_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  actor_status text;
  organization_id uuid;
  claim_row app_private.account_deletion_restore_claims%ROWTYPE;
  attempt_row app_private.account_deletion_current%ROWTYPE;
  cycle_row app_private.account_deletion_request_claims%ROWTYPE;
  reference_time timestamptz;
BEGIN
  IF requested_request_id IS NULL OR expected_deletion_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid account restoration request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'account restoration requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account restoration forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'account-deletion-restore-request:' || requested_request_id::text, 0
  ));
  SELECT actor.status INTO actor_status FROM app_data.app_users AS actor
  WHERE actor.app_user_id = trusted_app_user_id FOR UPDATE;

  FOR organization_id IN
    SELECT DISTINCT membership.organization_workspace_id
    FROM app_data.organization_memberships AS membership
    WHERE membership.app_user_id = trusted_app_user_id
    ORDER BY membership.organization_workspace_id
  LOOP
    PERFORM app_private.lock_organization_governance_v1(organization_id);
  END LOOP;

  reference_time := clock_timestamp();
  SELECT claim.* INTO claim_row FROM app_private.account_deletion_restore_claims AS claim
  WHERE claim.request_id = requested_request_id;
  IF claim_row.request_id IS NOT NULL AND claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account restoration idempotency conflict';
  END IF;
  SELECT attempt.* INTO attempt_row FROM app_private.account_deletion_current AS attempt
  WHERE attempt.app_user_id = trusted_app_user_id;
  IF FOUND THEN
    SELECT claim.* INTO cycle_row FROM app_private.account_deletion_request_claims AS claim
    WHERE claim.request_id = attempt_row.deletion_request_id;
    IF cycle_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR cycle_row.effective_at_utc IS DISTINCT FROM attempt_row.effective_at_utc
      OR cycle_row.purge_after_utc IS DISTINCT FROM attempt_row.purge_after_utc
      OR (actor_status = 'active' AND attempt_row.status <> 'restored')
      OR (actor_status = 'deletion_pending' AND attempt_row.status <> 'deletion_pending')
    THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account restoration unavailable';
    END IF;
  ELSIF actor_status = 'deletion_pending' THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'account restoration unavailable';
  END IF;

  IF claim_row.request_id IS NOT NULL THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR claim_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
      OR actor_status IS DISTINCT FROM 'active'
      OR attempt_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
      OR attempt_row.status IS DISTINCT FROM 'restored'
      OR attempt_row.restored_at_utc IS DISTINCT FROM claim_row.restored_at_utc
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account restoration idempotency conflict';
    END IF;
    RETURN QUERY SELECT 'account-deletion-restore:v1'::text,
      claim_row.deletion_request_id, claim_row.restored_at_utc;
    RETURN;
  END IF;

  IF actor_status IS NULL OR actor_status = 'deleted' THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'account restoration forbidden';
  END IF;
  IF actor_status IS DISTINCT FROM 'deletion_pending'
    OR attempt_row.deletion_request_id IS DISTINCT FROM expected_deletion_request_id
    OR attempt_row.status IS DISTINCT FROM 'deletion_pending'
    OR reference_time < attempt_row.effective_at_utc OR reference_time >= attempt_row.purge_after_utc
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'account restoration idempotency conflict';
  END IF;

  UPDATE app_data.app_users AS actor SET status = 'active'
  WHERE actor.app_user_id = trusted_app_user_id;
  UPDATE app_private.account_deletion_current AS attempt
  SET status = 'restored', restored_at_utc = reference_time
  WHERE attempt.app_user_id = trusted_app_user_id;
  INSERT INTO app_private.account_deletion_restore_claims (
    request_id, actor_app_user_id, deletion_request_id, restored_at_utc
  ) VALUES (
    requested_request_id, trusted_app_user_id, expected_deletion_request_id, reference_time
  );
  INSERT INTO app_private.account_deletion_audit_events (
    audit_event_id, operation, request_id, deletion_request_id, occurred_at_utc
  ) VALUES (
    gen_random_uuid(), 'account-deletion-restore:v1', requested_request_id,
    expected_deletion_request_id, reference_time
  );
  RETURN QUERY SELECT 'account-deletion-restore:v1'::text,
    expected_deletion_request_id, reference_time;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_account_deletion_claim_v1(),
  app_private.request_account_deletion_v1(uuid,uuid),
  app_private.restore_account_v1(uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
  owned_object text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  FOREACH owned_object IN ARRAY ARRAY[
    'account_deletion_current', 'account_deletion_request_claims',
    'account_deletion_restore_claims', 'account_deletion_audit_events'
  ] LOOP
    EXECUTE format('ALTER TABLE app_private.%I OWNER TO %I', owned_object, trusted_owner);
  END LOOP;
  FOREACH owned_object IN ARRAY ARRAY[
    'protect_account_deletion_claim_v1()', 'request_account_deletion_v1(uuid,uuid)',
    'restore_account_v1(uuid,uuid,uuid)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION app_private.%s OWNER TO %I', owned_object, trusted_owner);
  END LOOP;
END
$owner$;
