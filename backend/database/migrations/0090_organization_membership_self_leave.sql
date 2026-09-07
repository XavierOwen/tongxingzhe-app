-- 0090_organization_membership_self_leave.sql
--
-- A bare organization member may end only their current membership.  The
-- request family owns its replay receipt, terminal tombstone, and audit row.

CREATE TABLE app_private.organization_membership_self_leave_request_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE SET NULL,
  organization_workspace_id uuid NOT NULL,
  organization_membership_id uuid NOT NULL,
  effective_at_utc timestamp with time zone NOT NULL,
  CONSTRAINT organization_membership_self_leave_claims_effective_finite
    CHECK (isfinite(effective_at_utc))
);

CREATE TABLE app_private.organization_membership_self_leave_request_tombstones (
  claim_family text NOT NULL,
  request_id uuid NOT NULL,
  CONSTRAINT organization_membership_self_leave_tombstones_pkey
    PRIMARY KEY (claim_family, request_id),
  CONSTRAINT organization_membership_self_leave_tombstones_family
    CHECK (claim_family = 'organization-membership-self-leave:v1')
);

CREATE TABLE app_private.organization_membership_self_leave_audit_events (
  organization_membership_self_leave_audit_event_id uuid PRIMARY KEY,
  membership_self_leave_contract_id text NOT NULL,
  request_id uuid NOT NULL UNIQUE,
  organization_workspace_id uuid NOT NULL,
  organization_membership_id uuid NOT NULL,
  effective_at_utc timestamp with time zone NOT NULL,
  CONSTRAINT organization_membership_self_leave_audit_contract
    CHECK (
      membership_self_leave_contract_id =
        'organization-membership-self-leave:v1'
    ),
  CONSTRAINT organization_membership_self_leave_audit_effective_finite
    CHECK (isfinite(effective_at_utc))
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_membership_self_leave_request_claims,
  app_private.organization_membership_self_leave_request_tombstones,
  app_private.organization_membership_self_leave_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION
  app_private.protect_organization_membership_self_leave_request_claim_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization membership self-leave request claim cannot be deleted';
  END IF;

  IF OLD.request_id IS DISTINCT FROM NEW.request_id
    OR OLD.organization_workspace_id IS DISTINCT FROM
      NEW.organization_workspace_id
    OR OLD.organization_membership_id IS DISTINCT FROM
      NEW.organization_membership_id
    OR OLD.effective_at_utc IS DISTINCT FROM NEW.effective_at_utc
    OR NOT (
      OLD.actor_app_user_id IS NOT NULL
      AND NEW.actor_app_user_id IS NULL
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization membership self-leave request claim is immutable';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_membership_self_leave_claims_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_membership_self_leave_request_claims
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_membership_self_leave_request_claim_v1();

CREATE FUNCTION
  app_private.protect_organization_membership_self_leave_request_tombstone_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization membership self-leave request tombstone is immutable';
END
$function$;

CREATE TRIGGER organization_membership_self_leave_tombstones_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_membership_self_leave_request_tombstones
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_membership_self_leave_request_tombstone_v1();

CREATE FUNCTION
  app_private.protect_organization_membership_self_leave_audit_event_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization membership self-leave audit is append-only';
END
$function$;

CREATE TRIGGER organization_membership_self_leave_audit_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_membership_self_leave_audit_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_membership_self_leave_audit_event_v1();

CREATE FUNCTION app_private.leave_organization_membership_v1(
  resolved_actor_app_user_id uuid,
  requested_request_id uuid,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  membership_self_leave_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  effective_at_utc timestamp with time zone
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  claim_row
    app_private.organization_membership_self_leave_request_claims%ROWTYPE;
  membership_row app_data.organization_memberships%ROWTYPE;
  actor_status text;
  workspace_kind text;
  workspace_deleted_at timestamp with time zone;
  claim_found boolean;
  effective_time timestamp with time zone;
  audit_event_id uuid;
BEGIN
  IF requested_request_id IS NULL
    OR requested_organization_workspace_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization membership self-leave request';
  END IF;

  IF resolved_actor_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership-self-leave-request:'
        || requested_request_id::text,
      0
    )
  );

  PERFORM 1
  FROM app_private.organization_membership_self_leave_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family = 'organization-membership-self-leave:v1'
    AND tombstone.request_id = requested_request_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization membership self-leave idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_membership_self_leave_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM
        resolved_actor_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization membership self-leave idempotency conflict';
    END IF;

    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = resolved_actor_app_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization membership self-leave idempotency conflict';
    END IF;

    SELECT claim.*
    INTO claim_row
    FROM app_private.organization_membership_self_leave_request_claims AS claim
    WHERE claim.request_id = requested_request_id;

    IF NOT FOUND
      OR claim_row.actor_app_user_id IS DISTINCT FROM
        resolved_actor_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization membership self-leave idempotency conflict';
    END IF;

    SELECT app_user.status
    INTO actor_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = resolved_actor_app_user_id;

    IF actor_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization membership self-leave forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-membership-self-leave:v1'::text,
      claim_row.organization_workspace_id,
      claim_row.organization_membership_id,
      claim_row.effective_at_utc;
    RETURN;
  END IF;

  -- First execution has one fixed lock order: request, actor, governance,
  -- then the membership key shared with the append-only membership guards.
  PERFORM 1
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = resolved_actor_app_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  PERFORM app_private.lock_organization_governance_v1(
    requested_organization_workspace_id
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || requested_organization_workspace_id::text
        || ':' || resolved_actor_app_user_id::text,
      0
    )
  );

  -- A same-request caller may have committed while this transaction waited.
  PERFORM 1
  FROM app_private.organization_membership_self_leave_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family = 'organization-membership-self-leave:v1'
    AND tombstone.request_id = requested_request_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization membership self-leave idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_membership_self_leave_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.actor_app_user_id IS DISTINCT FROM
        resolved_actor_app_user_id
      OR claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization membership self-leave idempotency conflict';
    END IF;

    SELECT app_user.status
    INTO actor_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = resolved_actor_app_user_id;

    IF actor_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization membership self-leave forbidden';
    END IF;

    RETURN QUERY
    SELECT
      'organization-membership-self-leave:v1'::text,
      claim_row.organization_workspace_id,
      claim_row.organization_membership_id,
      claim_row.effective_at_utc;
    RETURN;
  END IF;

  -- This single post-lock wall-clock value authorizes and timestamps every
  -- mutation.  A transaction start time must not survive an earlier lock wait.
  effective_time := clock_timestamp();

  SELECT app_user.status
  INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = resolved_actor_app_user_id;

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id;

  IF actor_status IS DISTINCT FROM 'active'
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  SELECT membership.*
  INTO membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_workspace_id =
      requested_organization_workspace_id
    AND membership.app_user_id = resolved_actor_app_user_id
    AND tstzrange(
      membership.active_from_utc,
      membership.inactive_from_utc,
      '[)'
    ) @> effective_time
  ORDER BY membership.active_from_utc DESC
  LIMIT 1;

  IF NOT FOUND OR membership_row.inactive_from_utc IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  IF EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments AS owner_assignment
      WHERE owner_assignment.organization_membership_id =
          membership_row.organization_membership_id
        AND (
          owner_assignment.inactive_from_utc IS NULL
          OR owner_assignment.inactive_from_utc > effective_time
        )
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.project_memberships AS project_membership
      WHERE project_membership.organization_membership_id =
        membership_row.organization_membership_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS target_assignment
      JOIN app_data.promotion_targets AS target
        ON target.promotion_target_id = target_assignment.promotion_target_id
      WHERE target_assignment.app_user_id = resolved_actor_app_user_id
        AND target.workspace_id = requested_organization_workspace_id
        AND target_assignment.ended_at IS NULL
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  UPDATE app_data.organization_memberships AS membership
  SET inactive_from_utc = effective_time
  WHERE membership.organization_membership_id =
      membership_row.organization_membership_id
    AND membership.inactive_from_utc IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  INSERT INTO app_private.organization_membership_self_leave_request_claims (
    request_id,
    actor_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    effective_at_utc
  ) VALUES (
    requested_request_id,
    resolved_actor_app_user_id,
    requested_organization_workspace_id,
    membership_row.organization_membership_id,
    effective_time
  );

  audit_event_id := gen_random_uuid();

  INSERT INTO app_private.organization_membership_self_leave_audit_events (
    organization_membership_self_leave_audit_event_id,
    membership_self_leave_contract_id,
    request_id,
    organization_workspace_id,
    organization_membership_id,
    effective_at_utc
  ) VALUES (
    audit_event_id,
    'organization-membership-self-leave:v1',
    requested_request_id,
    requested_organization_workspace_id,
    membership_row.organization_membership_id,
    effective_time
  );

  RETURN QUERY
  SELECT
    'organization-membership-self-leave:v1'::text,
    requested_organization_workspace_id,
    membership_row.organization_membership_id,
    effective_time;
END
$function$;

CREATE FUNCTION app_data.leave_organization_membership_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_request_id uuid,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  membership_self_leave_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  effective_at_utc timestamp with time zone
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
      MESSAGE = 'invalid organization membership self-leave identity';
  END IF;

  SELECT identity.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity.app_user_id
  WHERE identity.issuer = trusted_issuer
    AND identity.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization membership self-leave forbidden';
  END IF;

  RETURN QUERY
  SELECT result.membership_self_leave_contract_id,
         result.organization_workspace_id,
         result.organization_membership_id,
         result.effective_at_utc
  FROM app_private.leave_organization_membership_v1(
    resolved_app_user_id,
    requested_request_id,
    requested_organization_workspace_id
  ) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_membership_self_leave_request_claim_v1(),
  app_private.protect_organization_membership_self_leave_request_tombstone_v1(),
  app_private.protect_organization_membership_self_leave_audit_event_v1(),
  app_private.leave_organization_membership_v1(uuid, uuid, uuid),
  app_data.leave_organization_membership_for_identity_v1(
    text, text, uuid, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.leave_organization_membership_for_identity_v1(
    text, text, uuid, uuid
  )
  TO tongxingzhe_runtime;

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
    'ALTER TABLE app_private.organization_membership_self_leave_request_claims OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_membership_self_leave_request_tombstones OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_membership_self_leave_audit_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_membership_self_leave_request_claim_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_membership_self_leave_request_tombstone_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_membership_self_leave_audit_event_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.leave_organization_membership_v1(uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.leave_organization_membership_for_identity_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON TABLE app_private.organization_membership_self_leave_request_claims
IS 'Immutable organization membership self-leave claims with one replay receipt.';

COMMENT ON TABLE
  app_private.organization_membership_self_leave_request_tombstones
IS 'Value-free terminal tombstones for the organization membership self-leave request family.';

COMMENT ON TABLE app_private.organization_membership_self_leave_audit_events
IS 'Append-only, value-free organization membership self-leave success audit events.';

COMMENT ON FUNCTION app_private.leave_organization_membership_v1(
  uuid, uuid, uuid
)
IS 'Atomically ends one bare current organization membership for a resolved active actor.';

COMMENT ON FUNCTION
  app_data.leave_organization_membership_for_identity_v1(
    text, text, uuid, uuid
  )
IS 'Maps one exact active external identity to the private organization membership self-leave writer.';
