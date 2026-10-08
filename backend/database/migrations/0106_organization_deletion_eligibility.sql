-- Slice 7DG: current-owner observation for the first deletion request entry.
-- POST must reauthorize after locks; these rows grant no durable authority.
CREATE FUNCTION app_data.list_organization_deletion_eligible_for_identity_v1(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (organization_workspace_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE directory_row record;
BEGIN
  IF trusted_issuer IS NULL
    OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL
    OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization deletion eligibility identity';
  END IF;

  -- The LEFT JOIN preserves an active identity's empty result in this same
  -- snapshot; it avoids a second identity lookup after an empty directory.
  FOR directory_row IN
    WITH observation AS MATERIALIZED (
      SELECT clock_timestamp() AS observed_at_utc
    )
    SELECT eligible.workspace_id
    FROM observation
    JOIN app_data.external_identities AS identity_row
      ON identity_row.issuer = trusted_issuer
        AND identity_row.subject = trusted_subject
    JOIN app_data.app_users AS actor
      ON actor.app_user_id = identity_row.app_user_id
        AND actor.status = 'active'
    LEFT JOIN LATERAL (
      SELECT workspace.workspace_id
      FROM app_data.organization_memberships AS membership
      JOIN app_data.workspaces AS workspace
        ON workspace.workspace_id = membership.organization_workspace_id
          AND workspace.workspace_kind = 'organization'
          AND workspace.deleted_at IS NULL
      LEFT JOIN app_private.organization_deletion_current AS attempt
        ON attempt.organization_workspace_id = workspace.workspace_id
      WHERE membership.app_user_id = actor.app_user_id
        AND tstzrange(membership.active_from_utc, membership.inactive_from_utc, '[)')
          @> observation.observed_at_utc
        AND (attempt.organization_workspace_id IS NULL OR attempt.status = 'restored')
        AND EXISTS (
          SELECT 1 FROM app_data.organization_owner_assignments AS owner_assignment
          WHERE owner_assignment.organization_membership_id = membership.organization_membership_id
            AND tstzrange(owner_assignment.active_from_utc, owner_assignment.inactive_from_utc, '[)')
              @> observation.observed_at_utc
        )
    ) AS eligible ON true
    ORDER BY eligible.workspace_id
  LOOP
    IF directory_row.workspace_id IS NOT NULL THEN
      organization_workspace_id := directory_row.workspace_id;
      RETURN NEXT;
    END IF;
  END LOOP;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion eligibility forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.list_organization_deletion_eligible_for_identity_v1(text, text)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.list_organization_deletion_eligible_for_identity_v1(text, text)
  TO tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_data.list_organization_deletion_eligible_for_identity_v1(text,text) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION app_data.list_organization_deletion_eligible_for_identity_v1(text, text)
IS 'Read-only exact-identity current-owner observation of organization UUIDs eligible for a first deletion request; request submission must reauthorize after locks.';
