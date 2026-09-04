-- Revalidate current ownership after lock waits without changing receipt time.
-- CREATE OR REPLACE preserves the existing function owner, OID and ACL.
CREATE OR REPLACE FUNCTION app_private.transfer_organization_owner_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid,
  requested_organization_workspace_id uuid,
  requested_target_organization_membership_id uuid
)
RETURNS TABLE (
  owner_transfer_contract_id text,
  organization_workspace_id uuid,
  previous_owner_assignment_id uuid,
  organization_owner_assignment_id uuid,
  effective_at_utc timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  claim_row app_private.organization_owner_transfer_request_claims%ROWTYPE;
  target_membership_row app_data.organization_memberships%ROWTYPE;
  actor_membership_row app_data.organization_memberships%ROWTYPE;
  actor_owner_assignment_row
    app_data.organization_owner_assignments%ROWTYPE;
  claim_found boolean;
  target_found boolean;
  workspace_found boolean;
  actor_status text;
  target_status text;
  workspace_kind text;
  workspace_deleted_at timestamp with time zone;
  target_workspace_id uuid;
  target_app_user_id uuid;
  actor_membership_found boolean;
  actor_assignment_found boolean;
  target_is_owner boolean;
  effective_time timestamp with time zone;
  authorization_time timestamp with time zone;
  locked_app_user_id uuid;
  governance_workspace_id uuid;
  membership_lock_row record;
  new_owner_assignment_id uuid;
  audit_event_id uuid;
BEGIN
  IF requested_request_id IS NULL
    OR requested_organization_workspace_id IS NULL
    OR requested_target_organization_membership_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization owner transfer request';
  END IF;

  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  -- The request lock is the sole serialization point for live claims and
  -- transfer tombstones.  Creation uses a different prefix and table family.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-owner-transfer-request:' || requested_request_id::text,
      0
    )
  );

  PERFORM 1
  FROM app_private.organization_owner_transfer_request_tombstones AS tombstone
  WHERE tombstone.claim_family = 'organization-owner-transfer:v1'
    AND tombstone.request_id = requested_request_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization owner transfer idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_owner_transfer_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR claim_row.target_organization_membership_id IS DISTINCT FROM
        requested_target_organization_membership_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization owner transfer idempotency conflict';
    END IF;

    -- Exact replay still proves that the resolved actor is an active account,
    -- but does not inspect the target or require the actor to remain owner.
    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_app_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization owner transfer idempotency conflict';
    END IF;

    SELECT claim.*
    INTO claim_row
    FROM app_private.organization_owner_transfer_request_claims AS claim
    WHERE claim.request_id = requested_request_id;

    IF NOT FOUND
      OR claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR claim_row.target_organization_membership_id IS DISTINCT FROM
        requested_target_organization_membership_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization owner transfer idempotency conflict';
    END IF;

    SELECT app_user.status
    INTO actor_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_app_user_id;

    IF actor_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization owner transfer forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-owner-transfer:v1'::text,
      claim_row.organization_workspace_id,
      claim_row.previous_owner_assignment_id,
      claim_row.organization_owner_assignment_id,
      claim_row.effective_at_utc;
    RETURN;
  END IF;

  -- Resolve the target membership only to discover the app-user and
  -- governance keys.  All authorization facts are re-read after the locks.
  SELECT membership.*
  INTO target_membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    requested_target_organization_membership_id;
  target_found := FOUND;

  IF NOT target_found THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  target_app_user_id := target_membership_row.app_user_id;
  target_workspace_id := target_membership_row.organization_workspace_id;

  -- Lock actor and target rows in one global UUID order.  Duplicates (the
  -- actor==target case) are intentionally collapsed to one row lock.
  FOR locked_app_user_id IN
    SELECT DISTINCT app_user_key
    FROM (
      VALUES (trusted_app_user_id), (target_app_user_id)
    ) AS requested_users(app_user_key)
    WHERE app_user_key IS NOT NULL
    ORDER BY app_user_key
  LOOP
    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = locked_app_user_id
    FOR UPDATE;
  END LOOP;

  -- The selector may point at another workspace; lock every discovered
  -- governance key in UUID order before taking membership advisory locks.
  FOR governance_workspace_id IN
    SELECT DISTINCT workspace_key
    FROM (
      VALUES (
        requested_organization_workspace_id
      ), (target_workspace_id)
    ) AS affected_workspaces(workspace_key)
    WHERE workspace_key IS NOT NULL
    ORDER BY workspace_key
  LOOP
    PERFORM app_private.lock_organization_governance_v1(
      governance_workspace_id
    );
  END LOOP;

  -- Reuse 0085's existing organization-membership advisory key.  Membership
  -- rows are visited in UUID order; the key itself is workspace+app-user so it
  -- matches the existing membership validator exactly.
  FOR membership_lock_row IN
    SELECT
      membership.organization_membership_id,
      membership.organization_workspace_id,
      membership.app_user_id
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_membership_id =
        requested_target_organization_membership_id
      OR (
        membership.organization_workspace_id =
          requested_organization_workspace_id
        AND membership.app_user_id = trusted_app_user_id
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

  -- A purge or another request can only become visible at the request lock;
  -- re-reading here keeps the lock-after contract explicit and defensive.
  PERFORM 1
  FROM app_private.organization_owner_transfer_request_tombstones AS tombstone
  WHERE tombstone.claim_family = 'organization-owner-transfer:v1'
    AND tombstone.request_id = requested_request_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization owner transfer idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_owner_transfer_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
      OR claim_row.target_organization_membership_id IS DISTINCT FROM
        requested_target_organization_membership_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization owner transfer idempotency conflict';
    END IF;

    SELECT app_user.status
    INTO actor_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = trusted_app_user_id;

    IF actor_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization owner transfer forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-owner-transfer:v1'::text,
      claim_row.organization_workspace_id,
      claim_row.previous_owner_assignment_id,
      claim_row.organization_owner_assignment_id,
      claim_row.effective_at_utc;
    RETURN;
  END IF;

  -- Transaction time is the immutable write timestamp, not current authority.
  -- A membership may close while this request waits for an app-user row lock.
  authorization_time := clock_timestamp();
  effective_time := transaction_timestamp();

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id;
  workspace_found := FOUND;

  IF NOT workspace_found
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  SELECT app_user.status
  INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_app_user_id;

  IF actor_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  SELECT membership.*
  INTO actor_membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_workspace_id =
      requested_organization_workspace_id
    AND membership.app_user_id = trusted_app_user_id
    AND tstzrange(
      membership.active_from_utc,
      membership.inactive_from_utc,
      '[)'
    ) @> authorization_time
  ORDER BY membership.active_from_utc DESC
  LIMIT 1;
  actor_membership_found := FOUND;

  IF NOT actor_membership_found THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
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
    ) @> authorization_time
  ORDER BY owner_assignment.active_from_utc DESC
  LIMIT 1;
  actor_assignment_found := FOUND;

  IF NOT actor_assignment_found THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  -- Re-read the target membership and account after all locks.  This is the
  -- only branch allowed to reveal target-already-owner after it is verified
  -- as an active same-organization target.
  SELECT membership.*
  INTO target_membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    requested_target_organization_membership_id;

  IF NOT FOUND
    OR target_membership_row.organization_workspace_id IS DISTINCT FROM
      requested_organization_workspace_id
    OR NOT tstzrange(
      target_membership_row.active_from_utc,
      target_membership_row.inactive_from_utc,
      '[)'
    ) @> authorization_time
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  SELECT app_user.status
  INTO target_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = target_membership_row.app_user_id;

  IF target_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM app_data.organization_owner_assignments AS owner_assignment
    WHERE owner_assignment.organization_membership_id =
        target_membership_row.organization_membership_id
      AND tstzrange(
        owner_assignment.active_from_utc,
        owner_assignment.inactive_from_utc,
        '[)'
      ) @> authorization_time
  )
  INTO target_is_owner;

  IF target_is_owner THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization owner transfer target already owner';
  END IF;

  new_owner_assignment_id := gen_random_uuid();
  audit_event_id := gen_random_uuid();

  -- The deferred 0085 invariant observes a valid owner throughout the final
  -- state: append target first, then close exactly the actor's assignment.
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    new_owner_assignment_id,
    target_membership_row.organization_membership_id,
    effective_time,
    NULL
  );

  UPDATE app_data.organization_owner_assignments AS owner_assignment
  SET inactive_from_utc = effective_time
  WHERE owner_assignment.organization_owner_assignment_id =
    actor_owner_assignment_row.organization_owner_assignment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization owner transfer forbidden';
  END IF;

  INSERT INTO app_private.organization_owner_transfer_request_claims (
    request_id,
    actor_app_user_id,
    organization_workspace_id,
    target_organization_membership_id,
    previous_owner_assignment_id,
    organization_owner_assignment_id,
    effective_at_utc
  ) VALUES (
    requested_request_id,
    trusted_app_user_id,
    requested_organization_workspace_id,
    target_membership_row.organization_membership_id,
    actor_owner_assignment_row.organization_owner_assignment_id,
    new_owner_assignment_id,
    effective_time
  );

  INSERT INTO app_private.organization_owner_transfer_audit_events (
    organization_owner_transfer_audit_event_id,
    owner_transfer_contract_id,
    request_id,
    organization_workspace_id,
    previous_owner_assignment_id,
    organization_owner_assignment_id,
    effective_at_utc
  ) VALUES (
    audit_event_id,
    'organization-owner-transfer:v1',
    requested_request_id,
    requested_organization_workspace_id,
    actor_owner_assignment_row.organization_owner_assignment_id,
    new_owner_assignment_id,
    effective_time
  );

  RETURN QUERY
  SELECT
    'organization-owner-transfer:v1'::text,
    requested_organization_workspace_id,
    actor_owner_assignment_row.organization_owner_assignment_id,
    new_owner_assignment_id,
    effective_time;
END
$function$;
