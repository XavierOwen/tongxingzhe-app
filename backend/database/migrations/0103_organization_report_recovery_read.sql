-- Slice 7CX preserves reads of already-published management reports during
-- the organization recovery window. The shared resolver stays strict; only
-- the five report family directory/detail functions use this narrow reader.

CREATE FUNCTION app_private.resolve_management_report_recovery_read_authorization_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_capability_id text,
  requested_reference_at_utc timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_record record;
  authorization_workspace_id uuid;
  reference_at_utc timestamptz;
  workspace_kind text;
  workspace_deleted_at timestamptz;
  lifecycle_attempt app_private.organization_deletion_current%ROWTYPE;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_capability_id IS DISTINCT FROM 'view_anonymous_analytics'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid management report recovery read authorization request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'management report recovery read unavailable';
  END IF;

  SELECT project_row.workspace_id INTO authorization_workspace_id
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = requested_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  -- Match the lifecycle writers' governance -> workspace lock order. KEY SHARE
  -- excludes 0100's workspace FOR UPDATE while allowing concurrent readers.
  PERFORM app_private.lock_organization_governance_v1(
    authorization_workspace_id
  );
  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.workspaces AS workspace
  WHERE workspace.workspace_id = authorization_workspace_id
  FOR KEY SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  -- Keep the same hierarchy order as the existing resolver and mutation
  -- triggers. Holding these locks through the access audit serializes reads
  -- with membership, project membership, and capability revocation.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'organization-membership:' || authorization_workspace_id::text
      || ':' || requested_app_user_id::text,
    0
  ));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'project-membership:' || requested_project_id::text
      || ':' || requested_app_user_id::text,
    0
  ));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:' || requested_project_id::text
      || ':' || requested_app_user_id::text
      || ':' || requested_capability_id,
    0
  ));

  reference_at_utc := COALESCE(
    requested_reference_at_utc,
    clock_timestamp()
  );
  SELECT attempt.* INTO lifecycle_attempt
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id = authorization_workspace_id;

  IF workspace_kind IS DISTINCT FROM 'organization'
    OR NOT (
      (workspace_deleted_at IS NULL AND (
        NOT FOUND OR lifecycle_attempt.status = 'restored'
      ))
      OR (
        workspace_deleted_at IS NOT NULL
        AND FOUND
        AND lifecycle_attempt.status = 'deletion_pending'
        AND lifecycle_attempt.organization_workspace_id = authorization_workspace_id
        AND workspace_deleted_at = lifecycle_attempt.effective_at_utc
        AND reference_at_utc >= lifecycle_attempt.effective_at_utc
        AND reference_at_utc < lifecycle_attempt.purge_after_utc
      )
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  SELECT
    workspace_row.workspace_id,
    organization_membership.organization_membership_id,
    project_membership.project_membership_id,
    capability_grant.capability_grant_id,
    capability_grant.active_from_utc AS capability_active_from_utc,
    capability_grant.inactive_from_utc AS capability_inactive_from_utc
  INTO authorization_record
  FROM app_data.app_users AS app_user
  JOIN app_data.organization_memberships AS organization_membership
    ON organization_membership.app_user_id = app_user.app_user_id
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.workspace_id =
      organization_membership.organization_workspace_id
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
  JOIN app_data.project_memberships AS project_membership
    ON project_membership.organization_membership_id =
      organization_membership.organization_membership_id
   AND project_membership.project_id = project_row.project_id
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.project_membership_id =
      project_membership.project_membership_id
  WHERE app_user.app_user_id = requested_app_user_id
    AND app_user.status = 'active'
    AND workspace_row.workspace_id = authorization_workspace_id
    AND workspace_row.workspace_kind = 'organization'
    AND project_row.project_id = requested_project_id
    AND project_row.status = 'active'
    AND tstzrange(
      organization_membership.active_from_utc,
      organization_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND tstzrange(
      project_membership.active_from_utc,
      project_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND capability_grant.capability_id = requested_capability_id
    AND tstzrange(
      capability_grant.active_from_utc,
      capability_grant.inactive_from_utc,
      '[)'
    ) @> reference_at_utc;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  RETURN jsonb_build_object(
    'authorization_contract_id', 'management_report_authorization_v1',
    'app_user_id', requested_app_user_id,
    'organization_workspace_id', authorization_record.workspace_id,
    'project_id', requested_project_id,
    'organization_membership_id', authorization_record.organization_membership_id,
    'project_membership_id', authorization_record.project_membership_id,
    'capability_grant_id', authorization_record.capability_grant_id,
    'capability_id', requested_capability_id,
    'capability_active_from_utc', to_char(
      authorization_record.capability_active_from_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'capability_inactive_from_utc', CASE
      WHEN authorization_record.capability_inactive_from_utc IS NULL THEN NULL
      ELSE to_char(
        authorization_record.capability_inactive_from_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    END,
    'reference_at_utc', to_char(
      reference_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.resolve_management_report_recovery_read_authorization_v1(
    uuid, uuid, text, timestamptz
  )
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
  target record;
  function_definition text;
  updated_definition text;
  reader_count integer := 0;
  validator_count integer := 0;
  validator_name text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER FUNCTION app_private.resolve_management_report_recovery_read_authorization_v1(uuid,uuid,text,timestamptz) OWNER TO %I',
    trusted_owner
  );

  -- These are exactly the five existing directory/detail reader pairs.
  FOR target IN
    SELECT function_row.oid
    FROM pg_catalog.pg_proc AS function_row
    WHERE function_row.pronamespace = 'app_private'::regnamespace
      AND function_row.proname IN (
        'list_authorized_management_report_snapshots_v1',
        'read_authorized_management_report_snapshot_v1',
        'list_authorized_management_current_city_report_snapshots_v1',
        'read_authorized_management_current_city_report_snapshot_v1',
        'list_authorized_management_interest_report_snapshots_v1',
        'read_authorized_management_interest_report_snapshot_v1',
        'list_authorized_management_original_region_report_snapshots_v1',
        'read_authorized_management_original_region_report_snapshot_v1',
        'list_authorized_management_follow_up_consent_snapshots_v1',
        'read_authorized_management_follow_up_consent_report_snapshot_v1'
      )
      AND function_row.prosrc LIKE
        '%resolve_management_report_authorization_v1%'
  LOOP
    function_definition := pg_catalog.pg_get_functiondef(target.oid);
    updated_definition := replace(
      function_definition,
      'resolve_management_report_authorization_v1(',
      'resolve_management_report_recovery_read_authorization_v1('
    );
    IF updated_definition = function_definition THEN
      RAISE EXCEPTION 'expected strict resolver call in report reader %',
        target.oid::regprocedure;
    END IF;
    EXECUTE updated_definition;
    reader_count := reader_count + 1;
  END LOOP;
  IF reader_count <> 10 THEN
    RAISE EXCEPTION 'expected 10 report directory/detail readers, changed %',
      reader_count;
  END IF;

  -- Each access-audit validator rechecks the same lifecycle and authorization
  -- at the reader's recorded reference time before accepting the audit row.
  FOREACH validator_name IN ARRAY ARRAY[
    'validate_management_report_snapshot_access_insert_v1',
    'validate_management_report_snapshot_directory_access_v1',
    'validate_current_city_snapshot_access_insert_v1',
    'validate_management_current_city_snapshot_directory_access_v1',
    'validate_management_interest_snapshot_access_insert_v1',
    'validate_management_interest_snapshot_directory_access_v1',
    'validate_management_original_region_snapshot_access_insert_v1',
    'validate_original_region_snapshot_directory_access_v1',
    'validate_management_follow_up_consent_snapshot_access_insert_v1',
    'validate_management_follow_up_consent_snapshot_directory_v1'
  ] LOOP
    SELECT function_row.oid INTO STRICT target
    FROM pg_catalog.pg_proc AS function_row
    WHERE function_row.pronamespace = 'app_private'::regnamespace
      AND function_row.proname = validator_name
      AND function_row.pronargs = 0;
    function_definition := pg_catalog.pg_get_functiondef(target.oid);
    updated_definition := replace(
      function_definition,
      E'BEGIN\n  IF NOT EXISTS (',
      E'BEGIN\n  PERFORM app_private.resolve_management_report_recovery_read_authorization_v1(NEW.requested_by_app_user_id, NEW.project_id, NEW.capability_id, NEW.authorization_reference_at_utc);\n  IF NOT EXISTS ('
    );
    updated_definition := replace(
      updated_definition,
      'workspace_row.deleted_at IS NULL',
      'TRUE'
    );
    IF updated_definition = function_definition THEN
      RAISE EXCEPTION 'could not install recovery authorization in validator %',
        validator_name;
    END IF;
    EXECUTE updated_definition;
    validator_count := validator_count + 1;
  END LOOP;
  IF validator_count <> 10 THEN
    RAISE EXCEPTION 'expected 10 report access validators, changed %',
      validator_count;
  END IF;
END
$owner$;

COMMENT ON FUNCTION
  app_private.resolve_management_report_recovery_read_authorization_v1(
    uuid, uuid, text, timestamptz
  )
IS 'Narrow authorization for existing published report directory/detail reads; admits only active organizations or the exact live deletion_pending lifecycle tuple and records the same value-free access audit.';
