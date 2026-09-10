-- 0092_organization_shareable_join_link.sql
--
-- Slice 7AH implements only shareable-link creation and preview. Application,
-- approval, deletion, recovery, and purge writers remain separate deliveries.

CREATE TABLE app_private.organization_shareable_join_link_request_claims (
  link_id uuid PRIMARY KEY,
  organization_workspace_id uuid NOT NULL,
  creator_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE SET NULL,
  issued_at_utc timestamptz NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  CONSTRAINT organization_shareable_join_link_claims_finite
    CHECK (isfinite(issued_at_utc) AND isfinite(expires_at_utc)),
  CONSTRAINT organization_shareable_join_link_claims_expiry
    CHECK (expires_at_utc = issued_at_utc + interval '168 hours')
);

CREATE TABLE app_private.organization_shareable_join_link_request_tombstones (
  claim_family text NOT NULL,
  link_id uuid NOT NULL,
  CONSTRAINT organization_shareable_join_link_tombstones_pkey
    PRIMARY KEY (claim_family, link_id),
  CONSTRAINT organization_shareable_join_link_tombstones_family
    CHECK (claim_family = 'organization-shareable-join-link:v1')
);

CREATE TABLE app_private.organization_shareable_join_link_audit_events (
  organization_shareable_join_link_audit_event_id uuid PRIMARY KEY,
  organization_shareable_join_link_contract_id text NOT NULL,
  link_id uuid NOT NULL,
  organization_workspace_id uuid NOT NULL,
  event_kind text NOT NULL,
  issued_at_utc timestamptz NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  CONSTRAINT organization_shareable_join_link_audit_contract
    CHECK (
      organization_shareable_join_link_contract_id =
        'organization-shareable-join-link:v1'
    ),
  CONSTRAINT organization_shareable_join_link_audit_event_kind
    CHECK (event_kind = 'link_created'),
  CONSTRAINT organization_shareable_join_link_audit_finite
    CHECK (isfinite(issued_at_utc) AND isfinite(expires_at_utc)),
  CONSTRAINT organization_shareable_join_link_audit_expiry
    CHECK (expires_at_utc = issued_at_utc + interval '168 hours'),
  CONSTRAINT organization_shareable_join_link_audit_event_key
    UNIQUE (link_id, event_kind)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_shareable_join_link_request_claims,
  app_private.organization_shareable_join_link_request_tombstones,
  app_private.organization_shareable_join_link_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_organization_shareable_join_link_claim_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE =
        'organization shareable join link request claim cannot be deleted';
  END IF;

  IF OLD.link_id IS DISTINCT FROM NEW.link_id
    OR OLD.organization_workspace_id IS DISTINCT FROM
      NEW.organization_workspace_id
    OR OLD.issued_at_utc IS DISTINCT FROM NEW.issued_at_utc
    OR OLD.expires_at_utc IS DISTINCT FROM NEW.expires_at_utc
    OR (
      OLD.creator_app_user_id IS DISTINCT FROM NEW.creator_app_user_id
      AND NOT (
        OLD.creator_app_user_id IS NOT NULL
        AND NEW.creator_app_user_id IS NULL
      )
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization shareable join link request claim is immutable';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_shareable_join_link_claims_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_shareable_join_link_request_claims
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_shareable_join_link_claim_v1();

CREATE FUNCTION
  app_private.protect_organization_shareable_join_link_tombstone_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization shareable join link request tombstone is immutable';
END
$function$;

CREATE TRIGGER organization_shareable_join_link_tombstones_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_shareable_join_link_request_tombstones
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_shareable_join_link_tombstone_v1();

CREATE FUNCTION
  app_private.protect_organization_shareable_join_link_audit_event_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization shareable join link audit is append-only';
END
$function$;

CREATE TRIGGER organization_shareable_join_link_audit_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_shareable_join_link_audit_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_shareable_join_link_audit_event_v1();

CREATE FUNCTION app_private.create_organization_shareable_join_link_v1(
  trusted_actor_app_user_id uuid,
  requested_link_id uuid,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  organization_shareable_join_link_contract_id text,
  link_id uuid,
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
    app_private.organization_shareable_join_link_request_claims%ROWTYPE;
  actor_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  actor_owner_periods tstzrange[];
  claim_found boolean;
  issued_time timestamptz;
  expires_time timestamptz;
BEGIN
  IF requested_link_id IS NULL
    OR requested_organization_workspace_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization shareable join request';
  END IF;

  IF trusted_actor_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-shareable-join-link-request:' || requested_link_id::text,
      0
    )
  );

  -- Both replay and first execution next lock the trusted creator row.
  SELECT app_user.status
  INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_actor_app_user_id
  FOR UPDATE;

  IF actor_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  PERFORM 1
  FROM app_private.organization_shareable_join_link_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family = 'organization-shareable-join-link:v1'
    AND tombstone.link_id = requested_link_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization shareable join idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_shareable_join_link_request_claims AS claim
  WHERE claim.link_id = requested_link_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.creator_app_user_id IS NULL
      OR claim_row.creator_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization shareable join forbidden';
    END IF;

    IF claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization shareable join idempotency conflict';
    END IF;

    RETURN QUERY
    SELECT
      'organization-shareable-join-link:v1'::text,
      claim_row.link_id,
      claim_row.organization_workspace_id,
      claim_row.issued_at_utc,
      claim_row.expires_at_utc;
    RETURN;
  END IF;

  PERFORM app_private.lock_organization_governance_v1(
    requested_organization_workspace_id
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || requested_organization_workspace_id::text
        || ':' || trusted_actor_app_user_id::text,
      0
    )
  );

  -- Re-read request and authorization facts after the full first-write lock set.
  PERFORM 1
  FROM app_private.organization_shareable_join_link_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family = 'organization-shareable-join-link:v1'
    AND tombstone.link_id = requested_link_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization shareable join idempotency conflict';
  END IF;

  SELECT claim.*
  INTO claim_row
  FROM app_private.organization_shareable_join_link_request_claims AS claim
  WHERE claim.link_id = requested_link_id;
  claim_found := FOUND;

  IF claim_found THEN
    IF claim_row.creator_app_user_id IS NULL
      OR claim_row.creator_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization shareable join forbidden';
    END IF;

    IF claim_row.organization_workspace_id IS DISTINCT FROM
        requested_organization_workspace_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization shareable join idempotency conflict';
    END IF;

    RETURN QUERY
    SELECT
      'organization-shareable-join-link:v1'::text,
      claim_row.link_id,
      claim_row.organization_workspace_id,
      claim_row.issued_at_utc,
      claim_row.expires_at_utc;
    RETURN;
  END IF;

  SELECT app_user.status
  INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_actor_app_user_id;

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id;

  SELECT array_agg(
    tstzrange(
      membership.active_from_utc,
      membership.inactive_from_utc,
      '[)'
    ) * tstzrange(
      owner_assignment.active_from_utc,
      owner_assignment.inactive_from_utc,
      '[)'
    )
  )
  INTO actor_owner_periods
  FROM app_data.organization_memberships AS membership
  JOIN app_data.organization_owner_assignments AS owner_assignment
    ON owner_assignment.organization_membership_id =
      membership.organization_membership_id
  WHERE membership.organization_workspace_id =
      requested_organization_workspace_id
    AND membership.app_user_id = trusted_actor_app_user_id
    AND tstzrange(
      membership.active_from_utc,
      membership.inactive_from_utc,
      '[)'
    ) && tstzrange(
      owner_assignment.active_from_utc,
      owner_assignment.inactive_from_utc,
      '[)'
    );

  issued_time := clock_timestamp();
  expires_time := issued_time + interval '168 hours';

  IF actor_status IS DISTINCT FROM 'active'
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
    OR NOT COALESCE(issued_time <@ ANY (actor_owner_periods), false)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  INSERT INTO app_private.organization_shareable_join_link_request_claims (
    link_id,
    organization_workspace_id,
    creator_app_user_id,
    issued_at_utc,
    expires_at_utc
  ) VALUES (
    requested_link_id,
    requested_organization_workspace_id,
    trusted_actor_app_user_id,
    issued_time,
    expires_time
  );

  INSERT INTO app_private.organization_shareable_join_link_audit_events (
    organization_shareable_join_link_audit_event_id,
    organization_shareable_join_link_contract_id,
    link_id,
    organization_workspace_id,
    event_kind,
    issued_at_utc,
    expires_at_utc
  ) VALUES (
    gen_random_uuid(),
    'organization-shareable-join-link:v1',
    requested_link_id,
    requested_organization_workspace_id,
    'link_created',
    issued_time,
    expires_time
  );

  RETURN QUERY
  SELECT
    'organization-shareable-join-link:v1'::text,
    requested_link_id,
    requested_organization_workspace_id,
    issued_time,
    expires_time;
END
$function$;

CREATE FUNCTION
  app_data.create_organization_shareable_join_link_for_identity_v1(
    trusted_issuer text,
    trusted_subject text,
    requested_link_id uuid,
    requested_organization_workspace_id uuid
  )
RETURNS TABLE (
  organization_shareable_join_link_contract_id text,
  link_id uuid,
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
      MESSAGE = 'invalid organization shareable join identity';
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
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  RETURN QUERY
  SELECT
    result.organization_shareable_join_link_contract_id,
    result.link_id,
    result.organization_workspace_id,
    result.issued_at_utc,
    result.expires_at_utc
  FROM app_private.create_organization_shareable_join_link_v1(
    resolved_app_user_id,
    requested_link_id,
    requested_organization_workspace_id
  ) AS result;
END
$function$;

CREATE FUNCTION
  app_data.preview_organization_shareable_join_link_for_identity_v1(
    trusted_issuer text,
    trusted_subject text,
    requested_link_id uuid
  )
RETURNS TABLE (
  organization_shareable_join_link_preview_contract_id text,
  link_id uuid,
  organization_name text,
  expires_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  observation_time timestamptz;
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
      MESSAGE = 'invalid organization shareable join identity';
  END IF;

  IF requested_link_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization shareable join request';
  END IF;

  observation_time := clock_timestamp();

  RETURN QUERY
  SELECT
    'organization-shareable-join-link-preview:v1'::text,
    claim.link_id,
    workspace.display_name,
    claim.expires_at_utc
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS actor
    ON actor.app_user_id = identity_row.app_user_id
    AND actor.status = 'active'
  JOIN app_private.organization_shareable_join_link_request_claims AS claim
    ON claim.link_id = requested_link_id
    AND observation_time < claim.expires_at_utc
  JOIN app_data.workspaces AS workspace
    ON workspace.workspace_id = claim.organization_workspace_id
    AND workspace.workspace_kind = 'organization'
    AND workspace.deleted_at IS NULL
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_shareable_join_link_claim_v1(),
  app_private.protect_organization_shareable_join_link_tombstone_v1(),
  app_private.protect_organization_shareable_join_link_audit_event_v1(),
  app_private.create_organization_shareable_join_link_v1(uuid, uuid, uuid),
  app_data.create_organization_shareable_join_link_for_identity_v1(
    text, text, uuid, uuid
  ),
  app_data.preview_organization_shareable_join_link_for_identity_v1(
    text, text, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.create_organization_shareable_join_link_for_identity_v1(
    text, text, uuid, uuid
  ),
  app_data.preview_organization_shareable_join_link_for_identity_v1(
    text, text, uuid
  )
  TO tongxingzhe_runtime;

-- Reuse the existing trusted membership-function owner. Runtime never owns a
-- SECURITY DEFINER boundary or obtains app_private schema access.
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
    'ALTER TABLE app_private.organization_shareable_join_link_request_claims OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_shareable_join_link_request_tombstones OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_shareable_join_link_audit_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_shareable_join_link_claim_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_shareable_join_link_tombstone_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_shareable_join_link_audit_event_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.create_organization_shareable_join_link_v1(uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.create_organization_shareable_join_link_for_identity_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.preview_organization_shareable_join_link_for_identity_v1(text,text,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON TABLE app_private.organization_shareable_join_link_request_claims
IS 'Immutable shareable join-link claims with a replay receipt and unlinkable creator.';

COMMENT ON TABLE app_private.organization_shareable_join_link_request_tombstones
IS 'Value-free terminal tombstones for the shareable join-link family.';

COMMENT ON TABLE app_private.organization_shareable_join_link_audit_events
IS 'Append-only, value-free shareable join-link creation audit events.';

COMMENT ON FUNCTION app_private.create_organization_shareable_join_link_v1(
  uuid, uuid, uuid
)
IS 'Creates one 168-hour shareable join link for a current active organization owner, or returns its exact replay receipt.';

COMMENT ON FUNCTION
  app_data.create_organization_shareable_join_link_for_identity_v1(
    text, text, uuid, uuid
  )
IS 'Maps one exact active external identity to the private shareable join-link writer.';

COMMENT ON FUNCTION
  app_data.preview_organization_shareable_join_link_for_identity_v1(
    text, text, uuid
  )
IS 'Previews one known unexpired shareable join link for an exact active identity without writing or reserving eligibility.';
