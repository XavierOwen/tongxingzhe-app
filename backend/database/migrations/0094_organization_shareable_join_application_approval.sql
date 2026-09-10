-- 0094_organization_shareable_join_application_approval.sql
--
-- Slice 7AJ adds only owner approval for the application records from 0093.
-- Approval creates one ordinary organization membership and no other grant.

CREATE FUNCTION app_private.approve_organization_shareable_join_application_v1(
  trusted_actor_app_user_id uuid,
  requested_application_id uuid,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  approved_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  initial_application_row
    app_private.organization_shareable_join_application_request_claims%ROWTYPE;
  application_row
    app_private.organization_shareable_join_application_request_claims%ROWTYPE;
  initial_application_found boolean;
  application_found boolean;
  application_tombstone_found boolean;
  actor_status text;
  applicant_status text;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  actor_owner_periods tstzrange[];
  applicant_membership_periods tstzrange[];
  locked_app_user_id uuid;
  approval_time timestamptz;
  new_membership_id uuid;
BEGIN
  IF requested_application_id IS NULL
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
      'organization-shareable-join-application-request:'
        || requested_application_id::text,
      0
    )
  );

  -- Read only enough application state to choose the prescribed lock set.
  -- No request classification is returned before owner authorization.
  SELECT claim.*
  INTO initial_application_row
  FROM app_private.organization_shareable_join_application_request_claims
    AS claim
  WHERE claim.application_id = requested_application_id;
  initial_application_found := FOUND;

  -- Pending first approval locks approver and applicant in UUID order.
  -- Approved replay, unknown, tombstoned, and unlinked requests lock only actor.
  FOR locked_app_user_id IN
    SELECT DISTINCT app_user_key
    FROM (
      VALUES
        (trusted_actor_app_user_id),
        (
          CASE
            WHEN initial_application_found
              AND initial_application_row.approved_at_utc IS NULL
              AND initial_application_row.approved_organization_membership_id
                IS NULL
            THEN initial_application_row.applicant_app_user_id
            ELSE NULL
          END
        )
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

  IF initial_application_found
    AND initial_application_row.approved_at_utc IS NULL
    AND initial_application_row.approved_organization_membership_id IS NULL
    AND initial_application_row.applicant_app_user_id IS NOT NULL
  THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended(
        'organization-membership:'
          || requested_organization_workspace_id::text
          || ':' || initial_application_row.applicant_app_user_id::text,
        0
      )
    );
  END IF;

  -- Materialize every classification and authorization fact after the chosen
  -- lock set. The actor owner gate is evaluated before request classification.
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

  SELECT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_application_request_tombstones
      AS tombstone
    WHERE tombstone.claim_family =
        'organization-shareable-join-application:v1'
      AND tombstone.application_id = requested_application_id
  )
  INTO application_tombstone_found;

  SELECT claim.*
  INTO application_row
  FROM app_private.organization_shareable_join_application_request_claims
    AS claim
  WHERE claim.application_id = requested_application_id;
  application_found := FOUND;

  IF application_found
    AND application_row.applicant_app_user_id IS NOT NULL
    AND application_row.approved_at_utc IS NULL
    AND application_row.approved_organization_membership_id IS NULL
  THEN
    SELECT app_user.status
    INTO applicant_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = application_row.applicant_app_user_id;

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
        requested_organization_workspace_id
      AND membership.app_user_id = application_row.applicant_app_user_id;
  END IF;

  approval_time := clock_timestamp();

  -- Owner authorization is deliberately first. Unknown, tombstoned, and
  -- cross-workspace applications are not observable to an unauthorized actor.
  IF actor_status IS DISTINCT FROM 'active'
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR NOT COALESCE(approval_time <@ ANY (actor_owner_periods), false)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  IF application_tombstone_found
    OR NOT application_found
    OR application_row.organization_workspace_id IS DISTINCT FROM
      requested_organization_workspace_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  -- Approved replay ignores recovery, applicant and membership state, and
  -- application expiry. Any current active owner may receive the old receipt.
  IF application_row.approved_at_utc IS NOT NULL
    AND application_row.approved_organization_membership_id IS NOT NULL
  THEN
    RETURN QUERY
    SELECT
      'organization-shareable-join-application:v1'::text,
      application_row.application_id,
      application_row.organization_workspace_id,
      application_row.approved_organization_membership_id,
      application_row.approved_at_utc;
    RETURN;
  END IF;

  IF workspace_deleted_at IS NOT NULL
    OR application_row.applicant_app_user_id IS NULL
    OR applicant_status IS DISTINCT FROM 'active'
    OR approval_time >= application_row.expires_at_utc
    OR COALESCE(
      approval_time <@ ANY (applicant_membership_periods),
      false
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

  new_membership_id := gen_random_uuid();

  BEGIN
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc,
      inactive_from_utc
    ) VALUES (
      new_membership_id,
      requested_organization_workspace_id,
      application_row.applicant_app_user_id,
      approval_time,
      NULL
    );
  EXCEPTION
    WHEN SQLSTATE '22023' OR SQLSTATE '23P01' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization shareable join forbidden';
  END;

  UPDATE app_private.organization_shareable_join_application_request_claims
    AS claim
  SET approved_at_utc = approval_time,
      approved_organization_membership_id = new_membership_id
  WHERE claim.application_id = requested_application_id
    AND claim.approved_at_utc IS NULL
    AND claim.approved_organization_membership_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization shareable join forbidden';
  END IF;

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
    application_row.link_id,
    requested_organization_workspace_id,
    'application_approved',
    new_membership_id,
    approval_time
  );

  RETURN QUERY
  SELECT
    'organization-shareable-join-application:v1'::text,
    requested_application_id,
    requested_organization_workspace_id,
    new_membership_id,
    approval_time;
END
$function$;

CREATE FUNCTION
  app_data.approve_organization_shareable_join_application_for_identity_v1(
    trusted_issuer text,
    trusted_subject text,
    requested_application_id uuid,
    requested_organization_workspace_id uuid
  )
RETURNS TABLE (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  approved_at_utc timestamptz
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
    result.organization_workspace_id,
    result.organization_membership_id,
    result.approved_at_utc
  FROM app_private.approve_organization_shareable_join_application_v1(
    resolved_app_user_id,
    requested_application_id,
    requested_organization_workspace_id
  ) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.approve_organization_shareable_join_application_v1(
    uuid, uuid, uuid
  ),
  app_data.approve_organization_shareable_join_application_for_identity_v1(
    text, text, uuid, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.approve_organization_shareable_join_application_for_identity_v1(
    text, text, uuid, uuid
  )
  TO tongxingzhe_runtime;

-- Reuse the existing non-runtime function owner; no table, role, or privilege
-- surface is added by this migration.
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
    'ALTER FUNCTION app_private.approve_organization_shareable_join_application_v1(uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.approve_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION
  app_private.approve_organization_shareable_join_application_v1(
    uuid, uuid, uuid
  )
IS 'Approves one pending shareable join application by atomically creating one ordinary organization membership.';

COMMENT ON FUNCTION
  app_data.approve_organization_shareable_join_application_for_identity_v1(
    text, text, uuid, uuid
  )
IS 'Maps one exact active external identity to the private shareable join-application approval writer.';
