-- 0093_organization_shareable_join_application_submit.sql
--
-- Slice 7AI creates the approval-ready application records but exposes only
-- submission. Approval, membership writes, and lifecycle writers stay closed.

CREATE TABLE app_private.organization_shareable_join_application_request_claims (
  application_id uuid PRIMARY KEY,
  link_id uuid NOT NULL,
  organization_workspace_id uuid NOT NULL,
  applicant_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE SET NULL,
  submitted_at_utc timestamptz NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  approved_at_utc timestamptz,
  approved_organization_membership_id uuid,
  CONSTRAINT organization_shareable_join_application_claims_applicant_link
    UNIQUE (link_id, applicant_app_user_id),
  CONSTRAINT organization_shareable_join_application_claims_finite
    CHECK (
      isfinite(submitted_at_utc)
      AND isfinite(expires_at_utc)
      AND (approved_at_utc IS NULL OR isfinite(approved_at_utc))
    ),
  CONSTRAINT organization_shareable_join_application_claims_expiry
    CHECK (expires_at_utc = submitted_at_utc + interval '168 hours'),
  CONSTRAINT organization_shareable_join_application_claims_approval
    CHECK (
      (
        approved_at_utc IS NULL
        AND approved_organization_membership_id IS NULL
      )
      OR (
        approved_at_utc IS NOT NULL
        AND approved_organization_membership_id IS NOT NULL
      )
    )
);

CREATE TABLE app_private.organization_shareable_join_application_request_tombstones (
  claim_family text NOT NULL,
  application_id uuid NOT NULL,
  CONSTRAINT organization_shareable_join_application_tombstones_pkey
    PRIMARY KEY (claim_family, application_id),
  CONSTRAINT organization_shareable_join_application_tombstones_family
    CHECK (claim_family = 'organization-shareable-join-application:v1')
);

CREATE TABLE app_private.organization_shareable_join_application_audit_events (
  organization_shareable_join_application_audit_event_id uuid PRIMARY KEY,
  organization_shareable_join_application_contract_id text NOT NULL,
  application_id uuid NOT NULL,
  link_id uuid NOT NULL,
  organization_workspace_id uuid NOT NULL,
  event_kind text NOT NULL,
  organization_membership_id uuid,
  occurred_at_utc timestamptz NOT NULL,
  CONSTRAINT organization_shareable_join_application_audit_contract
    CHECK (
      organization_shareable_join_application_contract_id =
        'organization-shareable-join-application:v1'
    ),
  CONSTRAINT organization_shareable_join_application_audit_event_kind
    CHECK (event_kind IN ('application_submitted', 'application_approved')),
  CONSTRAINT organization_shareable_join_application_audit_membership
    CHECK (
      (
        event_kind = 'application_submitted'
        AND organization_membership_id IS NULL
      )
      OR (
        event_kind = 'application_approved'
        AND organization_membership_id IS NOT NULL
      )
    ),
  CONSTRAINT organization_shareable_join_application_audit_finite
    CHECK (isfinite(occurred_at_utc)),
  CONSTRAINT organization_shareable_join_application_audit_event_key
    UNIQUE (application_id, event_kind)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_shareable_join_application_request_claims,
  app_private.organization_shareable_join_application_request_tombstones,
  app_private.organization_shareable_join_application_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION
  app_private.protect_organization_shareable_join_application_claim_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  identity_unlinked boolean := false;
  approval_changed boolean := false;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE =
        'organization shareable join application request claim cannot be deleted';
  END IF;

  IF OLD.application_id IS DISTINCT FROM NEW.application_id
    OR OLD.link_id IS DISTINCT FROM NEW.link_id
    OR OLD.organization_workspace_id IS DISTINCT FROM
      NEW.organization_workspace_id
    OR OLD.submitted_at_utc IS DISTINCT FROM NEW.submitted_at_utc
    OR OLD.expires_at_utc IS DISTINCT FROM NEW.expires_at_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE =
        'organization shareable join application request claim is immutable';
  END IF;

  IF OLD.applicant_app_user_id IS DISTINCT FROM NEW.applicant_app_user_id THEN
    IF NOT (
      OLD.applicant_app_user_id IS NOT NULL
      AND NEW.applicant_app_user_id IS NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE =
          'organization shareable join application request claim is immutable';
    END IF;
    identity_unlinked := true;
  END IF;

  IF OLD.approved_at_utc IS DISTINCT FROM NEW.approved_at_utc
    OR OLD.approved_organization_membership_id IS DISTINCT FROM
      NEW.approved_organization_membership_id
  THEN
    IF NOT (
      OLD.approved_at_utc IS NULL
      AND OLD.approved_organization_membership_id IS NULL
      AND NEW.approved_at_utc IS NOT NULL
      AND NEW.approved_organization_membership_id IS NOT NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE =
          'organization shareable join application request claim is immutable';
    END IF;
    approval_changed := true;
  END IF;

  IF identity_unlinked AND approval_changed THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE =
        'organization shareable join application request claim is immutable';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_shareable_join_application_claims_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_shareable_join_application_request_claims
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_shareable_join_application_claim_v1();

CREATE FUNCTION
  app_private.protect_organization_shareable_join_application_tombstone_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE =
      'organization shareable join application request tombstone is immutable';
END
$function$;

CREATE TRIGGER organization_shareable_join_application_tombstones_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_shareable_join_application_request_tombstones
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_shareable_join_application_tombstone_v1();

CREATE FUNCTION
  app_private.protect_organization_shareable_join_application_audit_event_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization shareable join application audit is append-only';
END
$function$;

CREATE TRIGGER organization_shareable_join_application_audit_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_shareable_join_application_audit_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_shareable_join_application_audit_event_v1();

CREATE FUNCTION app_private.submit_organization_shareable_join_application_v1(
  trusted_actor_app_user_id uuid,
  requested_application_id uuid,
  requested_link_id uuid
)
RETURNS TABLE (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  link_id uuid,
  organization_workspace_id uuid,
  submitted_at_utc timestamptz,
  expires_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  application_row
    app_private.organization_shareable_join_application_request_claims%ROWTYPE;
  link_row
    app_private.organization_shareable_join_link_request_claims%ROWTYPE;
  applicant_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  applicant_membership_periods tstzrange[];
  application_found boolean;
  link_found boolean;
  link_tombstone_found boolean;
  submission_time timestamptz;
  expires_time timestamptz;
BEGIN
  IF requested_application_id IS NULL OR requested_link_id IS NULL THEN
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

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-shareable-join-application-request:'
        || requested_application_id::text,
      0
    )
  );

  -- Replay and first submission both lock the exact applicant row before
  -- classifying history. This is the reduced replay lock sequence too.
  SELECT app_user.status
  INTO applicant_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_actor_app_user_id
  FOR UPDATE;

  IF applicant_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  PERFORM 1
  FROM app_private.organization_shareable_join_application_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family =
      'organization-shareable-join-application:v1'
    AND tombstone.application_id = requested_application_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization shareable join idempotency conflict';
  END IF;

  SELECT claim.*
  INTO application_row
  FROM app_private.organization_shareable_join_application_request_claims
    AS claim
  WHERE claim.application_id = requested_application_id;
  application_found := FOUND;

  IF application_found THEN
    IF application_row.applicant_app_user_id IS NULL
      OR application_row.applicant_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization shareable join forbidden';
    END IF;

    IF application_row.link_id IS DISTINCT FROM requested_link_id THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization shareable join idempotency conflict';
    END IF;

    RETURN QUERY
    SELECT
      'organization-shareable-join-application:v1'::text,
      application_row.application_id,
      application_row.link_id,
      application_row.organization_workspace_id,
      application_row.submitted_at_utc,
      application_row.expires_at_utc;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_application_request_claims
      AS claim
    WHERE claim.link_id = requested_link_id
      AND claim.applicant_app_user_id = trusted_actor_app_user_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization shareable join idempotency conflict';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_link_request_tombstones
      AS tombstone
    WHERE tombstone.claim_family = 'organization-shareable-join-link:v1'
      AND tombstone.link_id = requested_link_id
  )
  INTO link_tombstone_found;

  SELECT claim.*
  INTO link_row
  FROM app_private.organization_shareable_join_link_request_claims AS claim
  WHERE claim.link_id = requested_link_id;
  link_found := FOUND;

  IF link_tombstone_found OR NOT link_found THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  PERFORM app_private.lock_organization_governance_v1(
    link_row.organization_workspace_id
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || link_row.organization_workspace_id::text
        || ':' || trusted_actor_app_user_id::text,
      0
    )
  );

  -- Materialize all history and eligibility facts after the complete lock set.
  -- Only the later wall-clock read decides expiry and current membership.
  SELECT app_user.status
  INTO applicant_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_actor_app_user_id;

  IF applicant_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  PERFORM 1
  FROM app_private.organization_shareable_join_application_request_tombstones
    AS tombstone
  WHERE tombstone.claim_family =
      'organization-shareable-join-application:v1'
    AND tombstone.application_id = requested_application_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization shareable join idempotency conflict';
  END IF;

  SELECT claim.*
  INTO application_row
  FROM app_private.organization_shareable_join_application_request_claims
    AS claim
  WHERE claim.application_id = requested_application_id;
  application_found := FOUND;

  IF application_found THEN
    IF application_row.applicant_app_user_id IS NULL
      OR application_row.applicant_app_user_id IS DISTINCT FROM
        trusted_actor_app_user_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization shareable join forbidden';
    END IF;

    IF application_row.link_id IS DISTINCT FROM requested_link_id THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization shareable join idempotency conflict';
    END IF;

    RETURN QUERY
    SELECT
      'organization-shareable-join-application:v1'::text,
      application_row.application_id,
      application_row.link_id,
      application_row.organization_workspace_id,
      application_row.submitted_at_utc,
      application_row.expires_at_utc;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_application_request_claims
      AS claim
    WHERE claim.link_id = requested_link_id
      AND claim.applicant_app_user_id = trusted_actor_app_user_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization shareable join idempotency conflict';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_link_request_tombstones
      AS tombstone
    WHERE tombstone.claim_family = 'organization-shareable-join-link:v1'
      AND tombstone.link_id = requested_link_id
  )
  INTO link_tombstone_found;

  SELECT claim.*
  INTO link_row
  FROM app_private.organization_shareable_join_link_request_claims AS claim
  WHERE claim.link_id = requested_link_id;
  link_found := FOUND;

  IF link_found THEN
    SELECT workspace.workspace_kind, workspace.deleted_at
    INTO workspace_kind, workspace_deleted_at
    FROM app_data.workspaces AS workspace
    WHERE workspace.workspace_id = link_row.organization_workspace_id;

    SELECT array_agg(
      tstzrange(
        membership.active_from_utc,
        membership.inactive_from_utc,
        '[)'
      )
    )
    INTO applicant_membership_periods
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_workspace_id =
        link_row.organization_workspace_id
      AND membership.app_user_id = trusted_actor_app_user_id;
  END IF;

  submission_time := clock_timestamp();
  expires_time := submission_time + interval '168 hours';

  IF applicant_status IS DISTINCT FROM 'active'
    OR link_tombstone_found
    OR NOT link_found
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
    OR submission_time >= link_row.expires_at_utc
    OR COALESCE(
      submission_time <@ ANY (applicant_membership_periods),
      false
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  INSERT INTO app_private.organization_shareable_join_application_request_claims (
    application_id,
    link_id,
    organization_workspace_id,
    applicant_app_user_id,
    submitted_at_utc,
    expires_at_utc,
    approved_at_utc,
    approved_organization_membership_id
  ) VALUES (
    requested_application_id,
    requested_link_id,
    link_row.organization_workspace_id,
    trusted_actor_app_user_id,
    submission_time,
    expires_time,
    NULL,
    NULL
  );

  INSERT INTO app_private.organization_shareable_join_application_audit_events (
    organization_shareable_join_application_audit_event_id,
    organization_shareable_join_application_contract_id,
    application_id,
    link_id,
    organization_workspace_id,
    event_kind,
    organization_membership_id,
    occurred_at_utc
  ) VALUES (
    gen_random_uuid(),
    'organization-shareable-join-application:v1',
    requested_application_id,
    requested_link_id,
    link_row.organization_workspace_id,
    'application_submitted',
    NULL,
    submission_time
  );

  RETURN QUERY
  SELECT
    'organization-shareable-join-application:v1'::text,
    requested_application_id,
    requested_link_id,
    link_row.organization_workspace_id,
    submission_time,
    expires_time;
END
$function$;

CREATE FUNCTION
  app_data.submit_organization_shareable_join_application_for_identity_v1(
    trusted_issuer text,
    trusted_subject text,
    requested_application_id uuid,
    requested_link_id uuid
  )
RETURNS TABLE (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  link_id uuid,
  organization_workspace_id uuid,
  submitted_at_utc timestamptz,
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
    result.organization_shareable_join_application_contract_id,
    result.application_id,
    result.link_id,
    result.organization_workspace_id,
    result.submitted_at_utc,
    result.expires_at_utc
  FROM app_private.submit_organization_shareable_join_application_v1(
    resolved_app_user_id,
    requested_application_id,
    requested_link_id
  ) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_shareable_join_application_claim_v1(),
  app_private.protect_organization_shareable_join_application_tombstone_v1(),
  app_private.protect_organization_shareable_join_application_audit_event_v1(),
  app_private.submit_organization_shareable_join_application_v1(
    uuid, uuid, uuid
  ),
  app_data.submit_organization_shareable_join_application_for_identity_v1(
    text, text, uuid, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.submit_organization_shareable_join_application_for_identity_v1(
    text, text, uuid, uuid
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
    'ALTER TABLE app_private.organization_shareable_join_application_request_claims OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_shareable_join_application_request_tombstones OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_shareable_join_application_audit_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_shareable_join_application_claim_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_shareable_join_application_tombstone_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_shareable_join_application_audit_event_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.submit_organization_shareable_join_application_v1(uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.submit_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON TABLE
  app_private.organization_shareable_join_application_request_claims
IS 'Approval-ready shareable join applications with an exact submit receipt and unlinkable applicant.';

COMMENT ON TABLE
  app_private.organization_shareable_join_application_request_tombstones
IS 'Value-free terminal tombstones for the shareable join-application family.';

COMMENT ON TABLE
  app_private.organization_shareable_join_application_audit_events
IS 'Append-only, value-free shareable join-application success audit events.';

COMMENT ON FUNCTION
  app_private.submit_organization_shareable_join_application_v1(
    uuid, uuid, uuid
  )
IS 'Submits one 168-hour application for an exact active non-member, or returns its exact replay receipt.';

COMMENT ON FUNCTION
  app_data.submit_organization_shareable_join_application_for_identity_v1(
    text, text, uuid, uuid
  )
IS 'Maps one exact active external identity to the private shareable join-application submit writer.';
