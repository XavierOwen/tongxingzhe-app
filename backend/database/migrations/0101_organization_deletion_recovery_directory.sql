-- Slice 7CV: read-only current-owner directory for recoverable organizations.
-- The writer rechecks all authority and expiry conditions when restoration is
-- submitted; this directory is an observation, not a restoration grant.

CREATE FUNCTION app_data.list_organization_deletion_recovery_for_identity_v1(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (
  organization_deletion_recovery_directory_contract_id text,
  observed_at_utc timestamptz,
  organization_workspace_id uuid,
  deletion_request_id uuid,
  display_name text,
  effective_at_utc timestamptz,
  purge_after_utc timestamptz,
  status text
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
      MESSAGE = 'invalid organization deletion recovery directory identity';
  END IF;

  -- One materialized observation time and one SQL snapshot govern every
  -- returned attempt and the owner's effective membership/assignment.
  RETURN QUERY
  WITH observation AS MATERIALIZED (
    SELECT clock_timestamp() AS observed_at_utc
  )
  SELECT
    'organization-deletion-recovery-directory:v1'::text,
    observation.observed_at_utc,
    workspace.workspace_id,
    attempt.deletion_request_id,
    workspace.display_name,
    attempt.effective_at_utc,
    attempt.purge_after_utc,
    'deletion_pending'::text
  FROM observation
  JOIN app_data.external_identities AS identity_row
    ON identity_row.issuer = trusted_issuer
      AND identity_row.subject = trusted_subject
  JOIN app_data.app_users AS actor
    ON actor.app_user_id = identity_row.app_user_id
      AND actor.status = 'active'
  JOIN app_data.organization_memberships AS membership
    ON membership.app_user_id = actor.app_user_id
  JOIN app_data.organization_owner_assignments AS owner_assignment
    ON owner_assignment.organization_membership_id = membership.organization_membership_id
  JOIN app_data.workspaces AS workspace
    ON workspace.workspace_id = membership.organization_workspace_id
      AND workspace.workspace_kind = 'organization'
  JOIN app_private.organization_deletion_current AS attempt
    ON attempt.organization_workspace_id = workspace.workspace_id
      AND attempt.status = 'deletion_pending'
      AND workspace.deleted_at = attempt.effective_at_utc
  WHERE tstzrange(membership.active_from_utc, membership.inactive_from_utc, '[)')
      @> observation.observed_at_utc
    AND tstzrange(owner_assignment.active_from_utc, owner_assignment.inactive_from_utc, '[)')
      @> observation.observed_at_utc
    AND observation.observed_at_utc >= attempt.effective_at_utc
    AND observation.observed_at_utc < attempt.purge_after_utc
  ORDER BY workspace.display_name COLLATE "C", workspace.workspace_id;

  -- An active identity with no qualifying organization is an authorized empty
  -- directory. Missing, unmapped, or inactive identities remain forbidden.
  IF NOT FOUND AND NOT EXISTS (
    SELECT 1
    FROM app_data.external_identities AS identity_row
    JOIN app_data.app_users AS actor
      ON actor.app_user_id = identity_row.app_user_id
    WHERE identity_row.issuer = trusted_issuer
      AND identity_row.subject = trusted_subject
      AND actor.status = 'active'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion recovery directory forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.list_organization_deletion_recovery_for_identity_v1(text, text)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.list_organization_deletion_recovery_for_identity_v1(text, text)
  TO tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_data.list_organization_deletion_recovery_for_identity_v1(text,text) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION app_data.list_organization_deletion_recovery_for_identity_v1(text, text)
IS 'Read-only current-owner observation of organizations inside the active 720-hour recovery window; restoration must revalidate authority and the opaque deletion request id.';
