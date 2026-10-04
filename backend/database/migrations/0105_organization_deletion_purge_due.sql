-- Slice 7DE adds the private, single-workspace transition into purge_due.
-- The finalizer owns scheduling and physical removal in later slices.

ALTER TABLE app_private.organization_deletion_current
  DROP CONSTRAINT organization_deletion_current_state_check;

ALTER TABLE app_private.organization_deletion_current
  ADD CONSTRAINT organization_deletion_current_state_check CHECK (
    (status IN ('deletion_pending', 'purge_due') AND restored_at_utc IS NULL)
    OR (status = 'restored' AND restored_at_utc IS NOT NULL)
  );

CREATE FUNCTION app_private.mark_organization_deletion_purge_due_v1(
  requested_organization_workspace_id uuid
)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  workspace_kind text;
  workspace_deleted_at timestamptz;
  attempt_row app_private.organization_deletion_current%ROWTYPE;
  reference_time timestamptz;
BEGIN
  IF requested_organization_workspace_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization purge due request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization purge due unavailable';
  END IF;

  PERFORM app_private.lock_organization_governance_v1(
    requested_organization_workspace_id
  );

  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = requested_organization_workspace_id
  FOR UPDATE;

  IF workspace_kind IS DISTINCT FROM 'organization' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization purge due forbidden';
  END IF;

  SELECT attempt.* INTO attempt_row
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id = requested_organization_workspace_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization purge due unavailable';
  END IF;

  reference_time := clock_timestamp();
  IF attempt_row.purge_after_utc IS DISTINCT FROM
      attempt_row.effective_at_utc + interval '720 hours'
    OR NOT EXISTS (
      SELECT 1
      FROM app_private.organization_deletion_request_claims AS claim
      WHERE claim.request_id = attempt_row.deletion_request_id
        AND claim.deletion_request_id = attempt_row.deletion_request_id
        AND claim.organization_workspace_id = requested_organization_workspace_id
        AND claim.effective_at_utc = attempt_row.effective_at_utc
        AND claim.purge_after_utc = attempt_row.purge_after_utc
    )
  THEN
      RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization purge due unavailable';
  END IF;

  IF workspace_deleted_at IS DISTINCT FROM attempt_row.effective_at_utc
    OR attempt_row.restored_at_utc IS NOT NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization purge due unavailable';
  END IF;

  IF attempt_row.status = 'purge_due' THEN
    RETURN 'organization-deletion-purge-due:already-marked';
  END IF;
  IF attempt_row.status IS DISTINCT FROM 'deletion_pending'
    OR reference_time < attempt_row.purge_after_utc
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'organization purge due unavailable';
  END IF;

  UPDATE app_private.organization_deletion_current
  SET status = 'purge_due'
  WHERE organization_workspace_id = requested_organization_workspace_id;

  RETURN 'organization-deletion-purge-due:marked';
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.mark_organization_deletion_purge_due_v1(uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER FUNCTION app_private.mark_organization_deletion_purge_due_v1(uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION app_private.mark_organization_deletion_purge_due_v1(uuid)
IS 'Under the organization governance and row locks, mark one consistent expired deletion attempt purge_due; no scheduling or purge is performed.';
