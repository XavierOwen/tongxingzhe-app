-- 0091_organization_directed_account_invitation_preview.sql
--
-- A signed-in invitation target may preview one known invitation UUID before
-- accepting it.  The preview is only a current, read-only observation;
-- acceptance remains the locked writer from 0087.
-- "account" is omitted from the SQL function name to stay within PostgreSQL's
-- 63-byte identifier limit; do not restore the 64-byte spelling.

CREATE FUNCTION
  app_data.preview_organization_directed_invitation_for_identity_v1(
    trusted_issuer text,
    trusted_subject text,
    requested_invitation_id uuid
  )
RETURNS TABLE (
  organization_invitation_preview_contract_id text,
  invitation_id uuid,
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
      MESSAGE = 'invalid organization invitation identity';
  END IF;

  IF requested_invitation_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization invitation request';
  END IF;

  observation_time := clock_timestamp();

  RETURN QUERY
  SELECT
    'organization-directed-account-invitation-preview:v1'::text,
    claim.invitation_id,
    workspace.display_name,
    claim.expires_at_utc
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS target
    ON target.app_user_id = identity_row.app_user_id
    AND target.status = 'active'
  JOIN app_private.organization_directed_account_invitation_request_claims
    AS claim
    ON claim.invitation_id = requested_invitation_id
    AND claim.target_app_user_id = target.app_user_id
    AND claim.inviter_app_user_id IS NOT NULL
    AND claim.accepted_at_utc IS NULL
    AND observation_time < claim.expires_at_utc
  JOIN app_data.workspaces AS workspace
    ON workspace.workspace_id = claim.organization_workspace_id
    AND workspace.workspace_kind = 'organization'
    AND workspace.deleted_at IS NULL
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND NOT EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_workspace_id =
          claim.organization_workspace_id
        AND membership.app_user_id = target.app_user_id
        AND tstzrange(
          membership.active_from_utc,
          membership.inactive_from_utc,
          '[)'
        ) @> observation_time
    );

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization invitation forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.preview_organization_directed_invitation_for_identity_v1(
    text, text, uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.preview_organization_directed_invitation_for_identity_v1(
    text, text, uuid
  )
  TO tongxingzhe_runtime;

-- Reuse the existing trusted membership-function owner; runtime never owns
-- this SECURITY DEFINER boundary.
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
    'ALTER FUNCTION app_data.preview_organization_directed_invitation_for_identity_v1(text,text,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION
  app_data.preview_organization_directed_invitation_for_identity_v1(
    text, text, uuid
  )
IS 'Previews one known, pending directed invitation for its exact active target identity at one wall-clock observation time; returns the organization name and expiry without authorizing acceptance or writing facts.';
