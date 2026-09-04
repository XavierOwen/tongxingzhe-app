-- 0087_organization_directed_account_invitation.sql
--
-- Slice 7P adds the database-only directed invitation and acceptance seams
-- fixed by Slice 7O.  The invitation family is independent from organization
-- creation and owner transfer, and acceptance only creates organization
-- membership.

CREATE TABLE app_private.organization_directed_account_invitation_request_claims (
  invitation_id uuid PRIMARY KEY,
  organization_workspace_id uuid NOT NULL,
  inviter_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE SET NULL,
  target_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE SET NULL,
  issued_at_utc timestamptz NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  accepted_at_utc timestamptz,
  accepted_organization_membership_id uuid,
  CONSTRAINT organization_directed_invitation_claims_finite
    CHECK (
      isfinite(issued_at_utc)
      AND isfinite(expires_at_utc)
      AND (
        accepted_at_utc IS NULL
        OR isfinite(accepted_at_utc)
      )
    ),
  CONSTRAINT organization_directed_invitation_claims_expiry
    CHECK (expires_at_utc = issued_at_utc + interval '168 hours'),
  CONSTRAINT organization_directed_invitation_claims_acceptance
    CHECK (
      (accepted_at_utc IS NULL AND accepted_organization_membership_id IS NULL)
      OR (
        accepted_at_utc IS NOT NULL
        AND accepted_organization_membership_id IS NOT NULL
      )
    )
);

CREATE TABLE app_private.organization_directed_account_invitation_request_tombstones (
  claim_family text NOT NULL,
  invitation_id uuid NOT NULL,
  CONSTRAINT organization_directed_invitation_tombstones_pkey
    PRIMARY KEY (claim_family, invitation_id),
  CONSTRAINT organization_directed_invitation_tombstones_family
    CHECK (claim_family = 'organization-directed-account-invitation:v1')
);

CREATE TABLE app_private.organization_directed_account_invitation_audit_events (
  organization_invitation_audit_event_id uuid PRIMARY KEY,
  organization_invitation_contract_id text NOT NULL,
  invitation_id uuid NOT NULL,
  organization_workspace_id uuid NOT NULL,
  event_kind text NOT NULL,
  organization_membership_id uuid,
  occurred_at_utc timestamptz NOT NULL,
  CONSTRAINT organization_directed_invitation_audit_contract
    CHECK (
      organization_invitation_contract_id =
        'organization-directed-account-invitation:v1'
    ),
  CONSTRAINT organization_directed_invitation_audit_event_kind
    CHECK (event_kind IN ('invitation_issued', 'invitation_accepted')),
  CONSTRAINT organization_directed_invitation_audit_membership
    CHECK (
      (event_kind = 'invitation_issued' AND organization_membership_id IS NULL)
      OR (
        event_kind = 'invitation_accepted'
        AND organization_membership_id IS NOT NULL
      )
    ),
  CONSTRAINT organization_directed_invitation_audit_finite
    CHECK (isfinite(occurred_at_utc)),
  CONSTRAINT organization_directed_invitation_audit_event_key
    UNIQUE (invitation_id, event_kind)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_directed_account_invitation_request_claims,
  app_private.organization_directed_account_invitation_request_tombstones,
  app_private.organization_directed_account_invitation_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_organization_directed_invitation_claim_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  identity_unlinked boolean := false;
  acceptance_changed boolean := false;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization invitation request claim cannot be deleted';
  END IF;

  IF OLD.invitation_id IS DISTINCT FROM NEW.invitation_id
    OR OLD.organization_workspace_id IS DISTINCT FROM
      NEW.organization_workspace_id
    OR OLD.issued_at_utc IS DISTINCT FROM NEW.issued_at_utc
    OR OLD.expires_at_utc IS DISTINCT FROM NEW.expires_at_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization invitation request claim is immutable';
  END IF;

  IF OLD.inviter_app_user_id IS DISTINCT FROM NEW.inviter_app_user_id THEN
    IF NOT (
      OLD.inviter_app_user_id IS NOT NULL
      AND NEW.inviter_app_user_id IS NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'organization invitation request claim is immutable';
    END IF;
    identity_unlinked := true;
  END IF;

  IF OLD.target_app_user_id IS DISTINCT FROM NEW.target_app_user_id THEN
    IF NOT (
      OLD.target_app_user_id IS NOT NULL
      AND NEW.target_app_user_id IS NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'organization invitation request claim is immutable';
    END IF;
    identity_unlinked := true;
  END IF;

  IF OLD.accepted_at_utc IS DISTINCT FROM NEW.accepted_at_utc
    OR OLD.accepted_organization_membership_id IS DISTINCT FROM
      NEW.accepted_organization_membership_id
  THEN
    IF NOT (
      OLD.accepted_at_utc IS NULL
      AND OLD.accepted_organization_membership_id IS NULL
      AND NEW.accepted_at_utc IS NOT NULL
      AND NEW.accepted_organization_membership_id IS NOT NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'organization invitation request claim is immutable';
    END IF;
    acceptance_changed := true;
  END IF;

  IF identity_unlinked AND acceptance_changed THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization invitation request claim is immutable';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_directed_invitation_claims_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_directed_account_invitation_request_claims
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_directed_invitation_claim_v1();

CREATE FUNCTION app_private.protect_organization_directed_invitation_tombstone_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization invitation request tombstone is immutable';
END
$function$;

CREATE TRIGGER organization_directed_invitation_tombstones_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_directed_account_invitation_request_tombstones
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_directed_invitation_tombstone_v1();

CREATE FUNCTION app_private.protect_organization_directed_invitation_audit_event_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization invitation audit is append-only';
END
$function$;

CREATE TRIGGER organization_directed_invitation_audit_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_directed_account_invitation_audit_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_directed_invitation_audit_event_v1();

CREATE FUNCTION app_private.create_organization_directed_account_invitation_v1(
  trusted_actor_app_user_id uuid,
  requested_invitation_id uuid,
  requested_organization_workspace_id uuid,
  requested_target_app_user_id uuid
)
RETURNS TABLE (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  claim_row
    app_private.organization_directed_account_invitation_request_claims%ROWTYPE;
  claim_found boolean;
  actor_status text;
  target_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  reference_time timestamptz;
  actor_membership_row app_data.organization_memberships%ROWTYPE;
  actor_owner_assignment_row
    app_data.organization_owner_assignments%ROWTYPE;
  actor_membership_found boolean;
  actor_assignment_found boolean;
  effective_time timestamptz;
  expires_time timestamptz;
  locked_app_user_id uuid;
  membership_lock_row record;
  audit_event_id uuid;
BEGIN
  IF requested_invitation_id IS NULL
    OR requested_organization_workspace_id IS NULL
    OR requested_target_app_user_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization invitation request';
  END IF;

  IF trusted_actor_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-directed-account-invitation-request:'
        || requested_invitation_id::text,
      0
    )
  );

  PERFORM 1
  FROM app_private.organization_directed_account_invitation_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family =
      'organization-directed-account-invitation:v1'
    AND tombstone.invitation_id = requested_invitation_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization invitation idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_directed_account_invitation_request_claims
    AS claim
  WHERE claim.invitation_id = requested_invitation_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.inviter_app_user_id IS NULL
      OR claim_row.target_app_user_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    IF claim_row.inviter_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR claim_row.target_app_user_id IS DISTINCT FROM
        requested_target_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization invitation idempotency conflict';
    END IF;

    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_actor_app_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    SELECT claim.*
    INTO claim_row
    FROM app_private.organization_directed_account_invitation_request_claims
      AS claim
    WHERE claim.invitation_id = requested_invitation_id;

    IF NOT FOUND
      OR claim_row.inviter_app_user_id IS NULL
      OR claim_row.target_app_user_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    IF claim_row.inviter_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR claim_row.target_app_user_id IS DISTINCT FROM
        requested_target_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization invitation idempotency conflict';
    END IF;

    SELECT app_user.status
    INTO actor_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_actor_app_user_id;

    IF actor_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-directed-account-invitation:v1'::text,
      claim_row.invitation_id,
      claim_row.organization_workspace_id,
      claim_row.issued_at_utc,
      claim_row.expires_at_utc;
    RETURN;
  END IF;

  -- Lock inviter and target rows in one UUID order.  Unknown target UUIDs do
  -- not reveal whether an app-user row exists.
  FOR locked_app_user_id IN
    SELECT DISTINCT app_user_key
    FROM (
      VALUES
        (trusted_actor_app_user_id),
        (requested_target_app_user_id)
    ) AS requested_users(app_user_key)
    WHERE app_user_key IS NOT NULL
    ORDER BY app_user_key
  LOOP
    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = locked_app_user_id
    FOR UPDATE;
  END LOOP;

  PERFORM app_private.lock_organization_governance_v1(
    requested_organization_workspace_id
  );

  FOR membership_lock_row IN
    SELECT
      membership.organization_membership_id,
      membership.organization_workspace_id,
      membership.app_user_id
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_workspace_id =
        requested_organization_workspace_id
      AND membership.app_user_id IN (
        trusted_actor_app_user_id,
        requested_target_app_user_id
      )
    ORDER BY membership.organization_membership_id
  LOOP
    PERFORM pg_advisory_xact_lock(
      hashtextextended(
        'organization-membership:'
          || membership_lock_row.organization_workspace_id::text
          || ':' || membership_lock_row.app_user_id::text,
        0
      )
    );
  END LOOP;

  -- Re-read every request fact after the prescribed locks.  This is also the
  -- defensive path for a future purge writer that uses the same request key.
  PERFORM 1
  FROM app_private.organization_directed_account_invitation_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family =
      'organization-directed-account-invitation:v1'
    AND tombstone.invitation_id = requested_invitation_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization invitation idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_directed_account_invitation_request_claims
    AS claim
  WHERE claim.invitation_id = requested_invitation_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.inviter_app_user_id IS NULL
      OR claim_row.target_app_user_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    IF claim_row.inviter_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR claim_row.target_app_user_id IS DISTINCT FROM
        requested_target_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization invitation idempotency conflict';
    END IF;

    SELECT app_user.status
    INTO actor_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_actor_app_user_id;

    IF actor_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-directed-account-invitation:v1'::text,
      claim_row.invitation_id,
      claim_row.organization_workspace_id,
      claim_row.issued_at_utc,
      claim_row.expires_at_utc;
    RETURN;
  END IF;

  reference_time := clock_timestamp();
  effective_time := transaction_timestamp();
  expires_time := effective_time + interval '168 hours';

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id;

  IF NOT FOUND
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  SELECT app_user.status
  INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_actor_app_user_id;

  IF actor_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  SELECT app_user.status
  INTO target_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = requested_target_app_user_id;

  IF target_status IS DISTINCT FROM 'active'
    OR requested_target_app_user_id = trusted_actor_app_user_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  SELECT membership.*
  INTO actor_membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_workspace_id =
      requested_organization_workspace_id
    AND membership.app_user_id = trusted_actor_app_user_id
    AND tstzrange(
      membership.active_from_utc,
      membership.inactive_from_utc,
      '[)'
    ) @> reference_time
  ORDER BY membership.active_from_utc DESC
  LIMIT 1;
  actor_membership_found := FOUND;

  IF NOT actor_membership_found THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  SELECT owner_assignment.*
  INTO actor_owner_assignment_row
  FROM app_data.organization_owner_assignments AS owner_assignment
  WHERE owner_assignment.organization_membership_id =
      actor_membership_row.organization_membership_id
    AND tstzrange(
      owner_assignment.active_from_utc,
      owner_assignment.inactive_from_utc,
      '[)'
    ) @> reference_time
  ORDER BY owner_assignment.active_from_utc DESC
  LIMIT 1;
  actor_assignment_found := FOUND;

  IF NOT actor_assignment_found THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_workspace_id =
        requested_organization_workspace_id
      AND membership.app_user_id = requested_target_app_user_id
      AND tstzrange(
        membership.active_from_utc,
        membership.inactive_from_utc,
        '[)'
      ) @> reference_time
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  audit_event_id := gen_random_uuid();

  INSERT INTO app_private.organization_directed_account_invitation_request_claims (
    invitation_id,
    organization_workspace_id,
    inviter_app_user_id,
    target_app_user_id,
    issued_at_utc,
    expires_at_utc,
    accepted_at_utc,
    accepted_organization_membership_id
  ) VALUES (
    requested_invitation_id,
    requested_organization_workspace_id,
    trusted_actor_app_user_id,
    requested_target_app_user_id,
    effective_time,
    expires_time,
    NULL,
    NULL
  );

  INSERT INTO app_private.organization_directed_account_invitation_audit_events (
    organization_invitation_audit_event_id,
    organization_invitation_contract_id,
    invitation_id,
    organization_workspace_id,
    event_kind,
    organization_membership_id,
    occurred_at_utc
  ) VALUES (
    audit_event_id,
    'organization-directed-account-invitation:v1',
    requested_invitation_id,
    requested_organization_workspace_id,
    'invitation_issued',
    NULL,
    effective_time
  );

  RETURN QUERY
  SELECT
    'organization-directed-account-invitation:v1'::text,
    requested_invitation_id,
    requested_organization_workspace_id,
    effective_time,
    expires_time;
END
$function$;

CREATE FUNCTION app_private.accept_organization_directed_account_invitation_v1(
  trusted_actor_app_user_id uuid,
  requested_invitation_id uuid
)
RETURNS TABLE (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  claim_row
    app_private.organization_directed_account_invitation_request_claims%ROWTYPE;
  target_app_user_id uuid;
  target_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  reference_time timestamptz;
  effective_time timestamptz;
  locked_app_user_id uuid;
  membership_lock_row record;
  new_membership_id uuid;
  audit_event_id uuid;
BEGIN
  IF requested_invitation_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization invitation request';
  END IF;

  IF trusted_actor_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-directed-account-invitation-request:'
        || requested_invitation_id::text,
      0
    )
  );

  PERFORM 1
  FROM app_private.organization_directed_account_invitation_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family =
      'organization-directed-account-invitation:v1'
    AND tombstone.invitation_id = requested_invitation_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization invitation idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_directed_account_invitation_request_claims
    AS claim
  WHERE claim.invitation_id = requested_invitation_id;

  IF NOT FOUND
    OR claim_row.inviter_app_user_id IS NULL
    OR claim_row.target_app_user_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  IF claim_row.target_app_user_id IS DISTINCT FROM trusted_actor_app_user_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  -- Accepted replay only proves the exact active target identity.  It does
  -- not re-check owner, workspace recovery, or current membership.
  IF claim_row.accepted_at_utc IS NOT NULL THEN
    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_actor_app_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    SELECT app_user.status
    INTO target_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_actor_app_user_id;

    IF target_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    SELECT claim.*
    INTO claim_row
    FROM app_private.organization_directed_account_invitation_request_claims
      AS claim
    WHERE claim.invitation_id = requested_invitation_id;

    IF NOT FOUND
      OR claim_row.inviter_app_user_id IS NULL
      OR claim_row.target_app_user_id IS NULL
      OR claim_row.target_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
      OR claim_row.accepted_at_utc IS NULL
      OR claim_row.accepted_organization_membership_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-directed-account-invitation:v1'::text,
      claim_row.invitation_id,
      claim_row.organization_workspace_id,
      claim_row.accepted_organization_membership_id,
      claim_row.accepted_at_utc;
    RETURN;
  END IF;

  target_app_user_id := claim_row.target_app_user_id;

  -- The actor must equal the claim target, so this UUID set normally has one
  -- row; DISTINCT keeps the lock order explicit for malformed private calls.
  FOR locked_app_user_id IN
    SELECT DISTINCT app_user_key
    FROM (
      VALUES
        (trusted_actor_app_user_id),
        (target_app_user_id)
    ) AS requested_users(app_user_key)
    WHERE app_user_key IS NOT NULL
    ORDER BY app_user_key
  LOOP
    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = locked_app_user_id
    FOR UPDATE;
  END LOOP;

  PERFORM app_private.lock_organization_governance_v1(
    claim_row.organization_workspace_id
  );

  FOR membership_lock_row IN
    SELECT
      membership.organization_membership_id,
      membership.organization_workspace_id,
      membership.app_user_id
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_workspace_id =
        claim_row.organization_workspace_id
      AND membership.app_user_id = target_app_user_id
    ORDER BY membership.organization_membership_id
  LOOP
    PERFORM pg_advisory_xact_lock(
      hashtextextended(
        'organization-membership:'
          || membership_lock_row.organization_workspace_id::text
          || ':' || membership_lock_row.app_user_id::text,
        0
      )
    );
  END LOOP;

  -- Request and governance locks fence the claim, account and membership
  -- facts.  Re-read them before deciding whether to write.
  PERFORM 1
  FROM app_private.organization_directed_account_invitation_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family =
      'organization-directed-account-invitation:v1'
    AND tombstone.invitation_id = requested_invitation_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization invitation idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_directed_account_invitation_request_claims
    AS claim
  WHERE claim.invitation_id = requested_invitation_id;

  IF NOT FOUND
    OR claim_row.inviter_app_user_id IS NULL
    OR claim_row.target_app_user_id IS NULL
    OR claim_row.target_app_user_id IS DISTINCT FROM
      trusted_actor_app_user_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  IF claim_row.accepted_at_utc IS NOT NULL THEN
    SELECT app_user.status
    INTO target_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_actor_app_user_id;

    IF target_status IS DISTINCT FROM 'active'
      OR claim_row.accepted_organization_membership_id IS NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization invitation forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-directed-account-invitation:v1'::text,
      claim_row.invitation_id,
      claim_row.organization_workspace_id,
      claim_row.accepted_organization_membership_id,
      claim_row.accepted_at_utc;
    RETURN;
  END IF;

  -- Eligibility is evaluated after all locks with wall-clock time so a
  -- transaction waiting on the request lock cannot accept an expired claim.
  reference_time := clock_timestamp();
  effective_time := transaction_timestamp();

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = claim_row.organization_workspace_id;

  IF NOT FOUND
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  SELECT app_user.status
  INTO target_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = target_app_user_id;

  IF target_status IS DISTINCT FROM 'active'
    OR reference_time >= claim_row.expires_at_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_workspace_id =
        claim_row.organization_workspace_id
      AND membership.app_user_id = target_app_user_id
      AND tstzrange(
        membership.active_from_utc,
        membership.inactive_from_utc,
        '[)'
      ) @> reference_time
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  new_membership_id := gen_random_uuid();
  audit_event_id := gen_random_uuid();

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    new_membership_id,
    claim_row.organization_workspace_id,
    target_app_user_id,
    effective_time,
    NULL
  );

  UPDATE app_private.organization_directed_account_invitation_request_claims AS claim
  SET accepted_at_utc = effective_time,
      accepted_organization_membership_id = new_membership_id
  WHERE claim.invitation_id = requested_invitation_id
    AND claim.accepted_at_utc IS NULL
    AND claim.accepted_organization_membership_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  INSERT INTO app_private.organization_directed_account_invitation_audit_events (
    organization_invitation_audit_event_id,
    organization_invitation_contract_id,
    invitation_id,
    organization_workspace_id,
    event_kind,
    organization_membership_id,
    occurred_at_utc
  ) VALUES (
    audit_event_id,
    'organization-directed-account-invitation:v1',
    requested_invitation_id,
    claim_row.organization_workspace_id,
    'invitation_accepted',
    new_membership_id,
    effective_time
  );

  RETURN QUERY
  SELECT
    'organization-directed-account-invitation:v1'::text,
    requested_invitation_id,
    claim_row.organization_workspace_id,
    new_membership_id,
    effective_time;
END
$function$;

CREATE FUNCTION app_data.create_organization_directed_account_invitation_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_invitation_id uuid,
  requested_organization_workspace_id uuid,
  requested_target_app_user_id uuid
)
RETURNS TABLE (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL
    OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization invitation identity';
  END IF;

  -- Identity lookup is exact and only maps an existing active app user.  All
  -- authorization and lock-after checks remain in the private writer.
  SELECT identity_row.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  RETURN QUERY
  SELECT result.organization_invitation_contract_id,
         result.invitation_id,
         result.organization_workspace_id,
         result.issued_at_utc,
         result.expires_at_utc
  FROM app_private.create_organization_directed_account_invitation_v1(
    resolved_app_user_id,
    requested_invitation_id,
    requested_organization_workspace_id,
    requested_target_app_user_id
  ) AS result;
END
$function$;

CREATE FUNCTION app_data.accept_organization_directed_account_invitation_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_invitation_id uuid
)
RETURNS TABLE (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL
    OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization invitation identity';
  END IF;

  SELECT identity_row.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;

  RETURN QUERY
  SELECT result.organization_invitation_contract_id,
         result.invitation_id,
         result.organization_workspace_id,
         result.organization_membership_id,
         result.accepted_at_utc
  FROM app_private.accept_organization_directed_account_invitation_v1(
    resolved_app_user_id,
    requested_invitation_id
  ) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_directed_invitation_claim_v1(),
  app_private.protect_organization_directed_invitation_tombstone_v1(),
  app_private.protect_organization_directed_invitation_audit_event_v1(),
  app_private.create_organization_directed_account_invitation_v1(
    uuid, uuid, uuid, uuid
  ),
  app_private.accept_organization_directed_account_invitation_v1(
    uuid, uuid
  ),
  app_data.create_organization_directed_account_invitation_for_identity_v1(
    text, text, uuid, uuid, uuid
  ),
  app_data.accept_organization_directed_account_invitation_for_identity_v1(
    text, text, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.create_organization_directed_account_invitation_for_identity_v1(
    text, text, uuid, uuid, uuid
  ),
  app_data.accept_organization_directed_account_invitation_for_identity_v1(
    text, text, uuid
  )
  TO tongxingzhe_runtime;

-- Reuse the same non-runtime owner as the existing private membership
-- validator.  No new restore-time role is introduced.
DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER TABLE app_private.organization_directed_account_invitation_request_claims OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_directed_account_invitation_request_tombstones OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_directed_account_invitation_audit_events OWNER TO %I',
    trusted_owner
  );

  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_directed_invitation_claim_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_directed_invitation_tombstone_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_directed_invitation_audit_event_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.create_organization_directed_account_invitation_v1(uuid,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.accept_organization_directed_account_invitation_v1(uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.create_organization_directed_account_invitation_for_identity_v1(text,text,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.accept_organization_directed_account_invitation_for_identity_v1(text,text,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON TABLE app_private.organization_directed_account_invitation_request_claims
IS 'Immutable directed account invitation claims with one replay receipt.';

COMMENT ON TABLE app_private.organization_directed_account_invitation_request_tombstones
IS 'Value-free terminal tombstones for the directed account invitation family.';

COMMENT ON TABLE app_private.organization_directed_account_invitation_audit_events
IS 'Append-only, value-free directed account invitation success audit events.';

COMMENT ON FUNCTION app_private.create_organization_directed_account_invitation_v1(
  uuid, uuid, uuid, uuid
)
IS 'Atomically issues one directed invitation to an active account from a current organization owner.';

COMMENT ON FUNCTION app_private.accept_organization_directed_account_invitation_v1(
  uuid, uuid
)
IS 'Atomically accepts one directed invitation by creating only an organization membership.';

COMMENT ON FUNCTION
  app_data.create_organization_directed_account_invitation_for_identity_v1(
    text, text, uuid, uuid, uuid
  )
IS 'Maps one exact active external identity to the private directed invitation writer.';

COMMENT ON FUNCTION
  app_data.accept_organization_directed_account_invitation_for_identity_v1(
    text, text, uuid
  )
IS 'Maps one exact active external identity to the private invitation acceptance writer.';
