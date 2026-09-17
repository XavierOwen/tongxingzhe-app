-- Read the earliest pending applications through one current-owner snapshot.
CREATE FUNCTION app_data.list_org_join_applications_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  organization_shareable_join_application_directory_contract_id text,
  organization_workspace_id uuid,
  observed_at_utc timestamptz,
  applications jsonb
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF trusted_issuer IS NULL
    OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL
    OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization shareable join application directory identity';
  END IF;
  IF requested_organization_workspace_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization shareable join application directory request';
  END IF;

  -- Authority and pending facts share this SQL snapshot and one wall clock.
  -- ponytail: claim scan/sort grows with history; add a workspace/submitted/id
  -- pending partial index only after a measured bottleneck. LIMIT bounds output.
  RETURN QUERY
  WITH observation AS MATERIALIZED (
    SELECT clock_timestamp() AS observed_at_utc
  )
  SELECT
    'organization-shareable-join-application-directory:v1'::text,
    workspace.workspace_id,
    observation.observed_at_utc,
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'application_id', pending.application_id::text,
        'link_id', pending.link_id::text,
        'submitted_at_utc', to_char(pending.submitted_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'expires_at_utc', to_char(pending.expires_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ) ORDER BY pending.submitted_at_utc, pending.application_id)
      FROM (
        SELECT claim.application_id, claim.link_id,
          claim.submitted_at_utc, claim.expires_at_utc
        FROM app_private.organization_shareable_join_application_request_claims AS claim
        WHERE claim.organization_workspace_id = workspace.workspace_id
          AND claim.approved_at_utc IS NULL
          AND claim.approved_organization_membership_id IS NULL
          AND observation.observed_at_utc < claim.expires_at_utc
        ORDER BY claim.submitted_at_utc, claim.application_id
        LIMIT 20
      ) AS pending
    ), '[]'::jsonb)
  FROM observation
  JOIN app_data.external_identities AS identity_row
    ON identity_row.issuer = trusted_issuer AND identity_row.subject = trusted_subject
  JOIN app_data.app_users AS actor
    ON actor.app_user_id = identity_row.app_user_id AND actor.status = 'active'
  JOIN app_data.workspaces AS workspace
    ON workspace.workspace_id = requested_organization_workspace_id
      AND workspace.workspace_kind = 'organization' AND workspace.deleted_at IS NULL
  WHERE EXISTS (
    SELECT 1 FROM app_data.organization_memberships AS parent
    JOIN app_data.organization_owner_assignments AS owner_assignment
      ON owner_assignment.organization_membership_id = parent.organization_membership_id
    WHERE parent.organization_workspace_id = workspace.workspace_id
      AND parent.app_user_id = actor.app_user_id
      AND tstzrange(parent.active_from_utc, parent.inactive_from_utc, '[)') @> observation.observed_at_utc
      AND tstzrange(owner_assignment.active_from_utc, owner_assignment.inactive_from_utc, '[)') @> observation.observed_at_utc
  );
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization shareable join application directory forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.list_org_join_applications_for_identity_v1(text, text, uuid)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.list_org_join_applications_for_identity_v1(text, text, uuid)
  TO tongxingzhe_runtime;
DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_data.list_org_join_applications_for_identity_v1(text,text,uuid) OWNER TO %I', trusted_owner);
END
$owner$;
COMMENT ON FUNCTION app_data.list_org_join_applications_for_identity_v1(text, text, uuid)
IS 'One exact-identity current-owner observation of the earliest twenty unexpired pending application references; not approval eligibility or a grant.';
