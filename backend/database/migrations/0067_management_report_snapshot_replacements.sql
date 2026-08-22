-- 0067_management_report_snapshot_replacements.sql
--
-- Slice 6BE records an append-only correction relationship between two
-- already published trusted-v2 channel snapshots. It does not generate a
-- report, mutate either snapshot, or change existing read and directory
-- behavior.

DO $lifecycle_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname =
      'tongxingzhe_management_report_snapshot_lifecycle_writer'
  ) THEN
    CREATE ROLE tongxingzhe_management_report_snapshot_lifecycle_writer
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$lifecycle_role$;

ALTER ROLE tongxingzhe_management_report_snapshot_lifecycle_writer
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

CREATE POLICY management_report_snapshot_lifecycle_writer_read_scope
ON app_private.management_report_snapshots
FOR SELECT
TO tongxingzhe_management_report_snapshot_lifecycle_writer
USING (
  report_id = 'contact_sessions_by_channel_two_periods'
  AND release_lineage_id =
    'management-report:contact_sessions_by_channel_two_periods'
);

CREATE TABLE app_private.management_report_snapshot_replacements (
  replacement_request_id uuid PRIMARY KEY,
  requested_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id),
  organization_workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id),
  organization_membership_id uuid NOT NULL
    REFERENCES app_data.organization_memberships (
      organization_membership_id
    ),
  project_membership_id uuid NOT NULL
    REFERENCES app_data.project_memberships (project_membership_id),
  capability_grant_id uuid NOT NULL
    REFERENCES app_data.management_report_capability_grants (
      capability_grant_id
    ),
  capability_id text NOT NULL CHECK (
    capability_id = 'release_management_reports'
  ),
  authorization_reference_at_utc timestamp with time zone NOT NULL,
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  release_lineage_id text NOT NULL CHECK (
    release_lineage_id =
      'management-report:contact_sessions_by_channel_two_periods'
  ),
  report_id text NOT NULL CHECK (
    report_id = 'contact_sessions_by_channel_two_periods'
  ),
  report_version integer NOT NULL CHECK (report_version = 1),
  superseded_snapshot_id uuid NOT NULL UNIQUE
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  replacement_snapshot_id uuid NOT NULL UNIQUE
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  replacement_reason_code text NOT NULL CHECK (
    replacement_reason_code IN (
      'late_accepted_data',
      'contact_revision',
      'contact_void'
    )
  ),
  declared_at_utc timestamp with time zone NOT NULL,
  result_document jsonb NOT NULL CHECK (
    jsonb_typeof(result_document) = 'object'
  ),
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(declared_at_utc)),
  CHECK (authorization_reference_at_utc = declared_at_utc),
  CHECK (superseded_snapshot_id <> replacement_snapshot_id)
);

CREATE INDEX management_report_snapshot_replacements_project_idx
ON app_private.management_report_snapshot_replacements (
  project_id,
  release_lineage_id,
  declared_at_utc DESC,
  replacement_request_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_snapshot_replacements
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER management_report_snapshot_replacements_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_snapshot_replacements
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
    requested_snapshot_id uuid,
    requested_project_id uuid
  )
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    JOIN app_private.management_report_release_v2_attempts AS attempt
      ON attempt.released_snapshot_id = snapshot.snapshot_id
      AND attempt.release_request_id = snapshot.release_request_id
      AND attempt.requested_by_app_user_id =
        snapshot.created_by_app_user_id
      AND attempt.project_id = snapshot.project_id
      AND attempt.capability_id = 'release_management_reports'
      AND attempt.release_lineage_id = snapshot.release_lineage_id
      AND attempt.report_id = snapshot.report_id
      AND attempt.report_version = snapshot.report_version
      AND attempt.query_fingerprint = snapshot.query_fingerprint
      AND attempt.reporting_time_zone = snapshot.reporting_time_zone
      AND attempt.data_cutoff_utc = snapshot.data_cutoff_utc
      AND attempt.compared_snapshot_id IS NOT DISTINCT FROM
        snapshot.previous_snapshot_id
      AND attempt.delegated_release_request_id =
        snapshot.release_request_id
      AND attempt.result_status IN ('approved_baseline', 'approved')
      AND attempt.reason_codes = '[]'::jsonb
    JOIN app_private.management_report_release_request_claims AS claim
      ON claim.release_request_id = attempt.release_request_id
      AND claim.release_family_id =
        'channel_management_report_snapshot_release'
    JOIN app_private.project_reporting_time_zone_versions AS version_row
      ON version_row.project_id = attempt.project_id
      AND version_row.version_number =
        attempt.reporting_time_zone_version_number
      AND version_row.reporting_time_zone = attempt.reporting_time_zone
      AND version_row.effective_from_utc =
        attempt.reporting_time_zone_effective_from_utc
    WHERE snapshot.snapshot_id = requested_snapshot_id
      AND snapshot.project_id = requested_project_id
      AND snapshot.report_id =
        'contact_sessions_by_channel_two_periods'
      AND snapshot.report_version = 1
      AND snapshot.release_lineage_id =
        'management-report:contact_sessions_by_channel_two_periods'
      AND snapshot.query_fingerprint =
        'management-report:contact_sessions_by_channel_two_periods:v1'
  )
$function$;

CREATE FUNCTION
  app_private.validate_management_report_snapshot_replacement_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, app_data
AS $function$
DECLARE
  superseded_snapshot app_private.management_report_snapshots%ROWTYPE;
  replacement_snapshot app_private.management_report_snapshots%ROWTYPE;
  expected_result_document jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS app_user
    JOIN app_data.organization_memberships AS organization_membership
      ON organization_membership.app_user_id = app_user.app_user_id
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id =
        organization_membership.organization_workspace_id
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.organization_membership_id =
        organization_membership.organization_membership_id
    JOIN app_data.projects AS project_row
      ON project_row.project_id = project_membership.project_id
    JOIN app_data.management_report_capability_grants AS capability_grant
      ON capability_grant.project_membership_id =
        project_membership.project_membership_id
    WHERE app_user.app_user_id = NEW.requested_by_app_user_id
      AND app_user.status = 'active'
      AND organization_membership.organization_membership_id =
        NEW.organization_membership_id
      AND organization_membership.organization_workspace_id =
        NEW.organization_workspace_id
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
      AND project_membership.project_membership_id =
        NEW.project_membership_id
      AND project_membership.project_id = NEW.project_id
      AND project_row.status = 'active'
      AND capability_grant.capability_grant_id = NEW.capability_grant_id
      AND capability_grant.capability_id = NEW.capability_id
      AND tstzrange(
        organization_membership.active_from_utc,
        organization_membership.inactive_from_utc,
        '[)'
      ) @> NEW.authorization_reference_at_utc
      AND tstzrange(
        project_membership.active_from_utc,
        project_membership.inactive_from_utc,
        '[)'
      ) @> NEW.authorization_reference_at_utc
      AND tstzrange(
        capability_grant.active_from_utc,
        capability_grant.inactive_from_utc,
        '[)'
      ) @> NEW.authorization_reference_at_utc
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report replacement authorization';
  END IF;

  SELECT snapshot.*
  INTO STRICT superseded_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = NEW.superseded_snapshot_id;

  SELECT snapshot.*
  INTO STRICT replacement_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = NEW.replacement_snapshot_id;

  IF superseded_snapshot.project_id <> NEW.project_id
    OR replacement_snapshot.project_id <> NEW.project_id
    OR superseded_snapshot.release_lineage_id <> NEW.release_lineage_id
    OR replacement_snapshot.release_lineage_id <> NEW.release_lineage_id
    OR superseded_snapshot.report_id <> NEW.report_id
    OR replacement_snapshot.report_id <> NEW.report_id
    OR superseded_snapshot.report_version <> NEW.report_version
    OR replacement_snapshot.report_version <> NEW.report_version
    OR superseded_snapshot.query_fingerprint <>
      replacement_snapshot.query_fingerprint
    OR superseded_snapshot.reporting_time_zone <>
      replacement_snapshot.reporting_time_zone
    OR superseded_snapshot.data_cutoff_utc >=
      replacement_snapshot.data_cutoff_utc
    OR superseded_snapshot.released_at_utc >=
      replacement_snapshot.released_at_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report replacement lineage is inconsistent';
  END IF;

  IF NOT app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
      superseded_snapshot.snapshot_id,
      NEW.project_id
    )
    OR NOT app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
      replacement_snapshot.snapshot_id,
      NEW.project_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report replacement provenance is untrusted';
  END IF;

  PERFORM app_private.validate_management_report_document_v1(
    superseded_snapshot.protected_report
  );
  PERFORM app_private.validate_management_report_document_v1(
    replacement_snapshot.protected_report
  );

  expected_result_document = jsonb_build_object(
    'replacement_contract_id',
      'channel_management_report_snapshot_replacement_v1',
    'replacement_request_id', NEW.replacement_request_id,
    'project_id', NEW.project_id,
    'release_lineage_id', NEW.release_lineage_id,
    'report_id', NEW.report_id,
    'report_version', NEW.report_version,
    'superseded_snapshot_id', NEW.superseded_snapshot_id,
    'replacement_snapshot_id', NEW.replacement_snapshot_id,
    'replacement_reason_code', NEW.replacement_reason_code,
    'declared_at_utc', to_char(
      NEW.declared_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'result_status', 'completed'
  );

  IF NEW.result_document <> expected_result_document THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report replacement result document';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_snapshot_replacements_validate
BEFORE INSERT
ON app_private.management_report_snapshot_replacements
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_snapshot_replacement_insert_v1();

CREATE FUNCTION app_private.declare_management_report_snapshot_replacement_v1(
  requested_replacement_request_id uuid,
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_superseded_snapshot_id uuid,
  requested_replacement_snapshot_id uuid,
  requested_replacement_reason_code text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  existing_replacement
    app_private.management_report_snapshot_replacements%ROWTYPE;
  superseded_snapshot app_private.management_report_snapshots%ROWTYPE;
  replacement_snapshot app_private.management_report_snapshots%ROWTYPE;
  authorization_evidence jsonb;
  declared_at_utc_value timestamp with time zone;
  replacement_result jsonb;
BEGIN
  IF requested_replacement_request_id IS NULL
    OR requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_superseded_snapshot_id IS NULL
    OR requested_replacement_snapshot_id IS NULL
    OR requested_superseded_snapshot_id =
      requested_replacement_snapshot_id
    OR requested_replacement_reason_code IS NULL
    OR requested_replacement_reason_code NOT IN (
      'late_accepted_data',
      'contact_revision',
      'contact_void'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report replacement request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-snapshot-replacement-request:'
        || requested_replacement_request_id::text,
      0
    )
  );

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  SELECT replacement.*
  INTO existing_replacement
  FROM app_private.management_report_snapshot_replacements AS replacement
  WHERE replacement.replacement_request_id =
    requested_replacement_request_id;

  IF FOUND THEN
    IF existing_replacement.requested_by_app_user_id <>
        requested_app_user_id
      OR existing_replacement.project_id <> requested_project_id
      OR existing_replacement.superseded_snapshot_id <>
        requested_superseded_snapshot_id
      OR existing_replacement.replacement_snapshot_id <>
        requested_replacement_snapshot_id
      OR existing_replacement.replacement_reason_code <>
        requested_replacement_reason_code
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'management report replacement idempotency conflict';
    END IF;
    RETURN existing_replacement.result_document;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_release_request_claims AS claim
    WHERE claim.release_request_id = requested_replacement_request_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'replacement request id was already used for report release';
  END IF;

  SELECT snapshot.*
  INTO superseded_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_superseded_snapshot_id
    AND snapshot.project_id = requested_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report replacement snapshot is unavailable';
  END IF;

  SELECT snapshot.*
  INTO replacement_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_replacement_snapshot_id
    AND snapshot.project_id = requested_project_id;
  IF NOT FOUND
    OR superseded_snapshot.release_lineage_id <>
      replacement_snapshot.release_lineage_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report replacement snapshot is unavailable';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-snapshot-replacement-lineage:'
        || requested_project_id::text || ':'
        || superseded_snapshot.release_lineage_id,
      0
    )
  );

  -- The lineage lock may wait behind a competing replacement. Re-resolve the
  -- authorization and all lineage state after that wait.
  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );
  declared_at_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT snapshot.*
  INTO STRICT superseded_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_superseded_snapshot_id
    AND snapshot.project_id = requested_project_id;

  SELECT snapshot.*
  INTO STRICT replacement_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_replacement_snapshot_id
    AND snapshot.project_id = requested_project_id;

  IF superseded_snapshot.report_id <>
      'contact_sessions_by_channel_two_periods'
    OR replacement_snapshot.report_id <> superseded_snapshot.report_id
    OR superseded_snapshot.report_version <> 1
    OR replacement_snapshot.report_version <>
      superseded_snapshot.report_version
    OR superseded_snapshot.release_lineage_id <>
      'management-report:contact_sessions_by_channel_two_periods'
    OR replacement_snapshot.release_lineage_id <>
      superseded_snapshot.release_lineage_id
    OR superseded_snapshot.query_fingerprint <>
      'management-report:contact_sessions_by_channel_two_periods:v1'
    OR replacement_snapshot.query_fingerprint <>
      superseded_snapshot.query_fingerprint
    OR superseded_snapshot.reporting_time_zone <>
      replacement_snapshot.reporting_time_zone
    OR superseded_snapshot.data_cutoff_utc >=
      replacement_snapshot.data_cutoff_utc
    OR superseded_snapshot.released_at_utc >=
      replacement_snapshot.released_at_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report replacement lineage is inconsistent';
  END IF;

  IF NOT app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
      requested_superseded_snapshot_id,
      requested_project_id
    )
    OR NOT app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
      requested_replacement_snapshot_id,
      requested_project_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management report replacement provenance is untrusted';
  END IF;

  PERFORM app_private.validate_management_report_document_v1(
    superseded_snapshot.protected_report
  );
  PERFORM app_private.validate_management_report_document_v1(
    replacement_snapshot.protected_report
  );

  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshot_replacements AS replacement
    WHERE replacement.superseded_snapshot_id =
      requested_superseded_snapshot_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'management report snapshot is no longer an active head';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshot_replacements AS replacement
    WHERE replacement.superseded_snapshot_id =
        requested_replacement_snapshot_id
      OR replacement.replacement_snapshot_id =
        requested_replacement_snapshot_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'replacement snapshot already belongs to a replacement chain';
  END IF;

  replacement_result = jsonb_build_object(
    'replacement_contract_id',
      'channel_management_report_snapshot_replacement_v1',
    'replacement_request_id', requested_replacement_request_id,
    'project_id', requested_project_id,
    'release_lineage_id', superseded_snapshot.release_lineage_id,
    'report_id', superseded_snapshot.report_id,
    'report_version', superseded_snapshot.report_version,
    'superseded_snapshot_id', requested_superseded_snapshot_id,
    'replacement_snapshot_id', requested_replacement_snapshot_id,
    'replacement_reason_code', requested_replacement_reason_code,
    'declared_at_utc', to_char(
      declared_at_utc_value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'result_status', 'completed'
  );

  INSERT INTO app_private.management_report_snapshot_replacements (
    replacement_request_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    release_lineage_id,
    report_id,
    report_version,
    superseded_snapshot_id,
    replacement_snapshot_id,
    replacement_reason_code,
    declared_at_utc,
    result_document
  ) VALUES (
    requested_replacement_request_id,
    requested_app_user_id,
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    authorization_evidence->>'capability_id',
    declared_at_utc_value,
    requested_project_id,
    superseded_snapshot.release_lineage_id,
    superseded_snapshot.report_id,
    superseded_snapshot.report_version,
    requested_superseded_snapshot_id,
    requested_replacement_snapshot_id,
    requested_replacement_reason_code,
    declared_at_utc_value,
    replacement_result
  );

  RETURN replacement_result;
END
$function$;

CREATE FUNCTION app_private.read_management_report_snapshot_lifecycle_v1(
  requested_project_id uuid,
  requested_snapshot_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  replacement_snapshot_id_value uuid;
BEGIN
  IF requested_project_id IS NULL OR requested_snapshot_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot lifecycle request';
  END IF;

  IF NOT app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
      requested_snapshot_id,
      requested_project_id
    )
  THEN
    RETURN jsonb_build_object(
      'lifecycle_contract_id',
        'channel_management_report_snapshot_lifecycle_v1',
      'project_id', requested_project_id,
      'snapshot_id', requested_snapshot_id,
      'lifecycle_status', 'not_found',
      'replacement_snapshot_id', NULL
    );
  END IF;

  SELECT replacement.replacement_snapshot_id
  INTO replacement_snapshot_id_value
  FROM app_private.management_report_snapshot_replacements AS replacement
  WHERE replacement.project_id = requested_project_id
    AND replacement.superseded_snapshot_id = requested_snapshot_id;

  RETURN jsonb_build_object(
    'lifecycle_contract_id',
      'channel_management_report_snapshot_lifecycle_v1',
    'project_id', requested_project_id,
    'snapshot_id', requested_snapshot_id,
    'lifecycle_status', CASE
      WHEN replacement_snapshot_id_value IS NULL THEN 'active'
      ELSE 'superseded'
    END,
    'replacement_snapshot_id', replacement_snapshot_id_value
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
    uuid, uuid
  ),
  app_private.validate_management_report_snapshot_replacement_insert_v1(),
  app_private.declare_management_report_snapshot_replacement_v1(
    uuid, uuid, uuid, uuid, uuid, text
  ),
  app_private.read_management_report_snapshot_lifecycle_v1(uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_interest_report_reader;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT SELECT ON
  app_data.app_users,
  app_data.workspaces,
  app_data.projects,
  app_data.organization_memberships,
  app_data.project_memberships,
  app_data.management_report_capability_grants,
  app_private.management_report_release_v2_attempts,
  app_private.management_report_release_request_claims,
  app_private.project_reporting_time_zone_versions
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT SELECT ON app_private.management_report_snapshots
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT SELECT, INSERT ON
  app_private.management_report_snapshot_replacements
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT EXECUTE ON FUNCTION
  app_private.resolve_management_report_authorization_v1(uuid, uuid, text),
  app_private.management_report_time_zone_valid_v1(text),
  app_private.validate_management_report_document_v1(jsonb)
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT
  tongxingzhe_management_report_snapshot_lifecycle_writer
  TO CURRENT_USER;

ALTER TABLE app_private.management_report_snapshot_replacements
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.validate_management_report_snapshot_replacement_insert_v1()
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.management_report_snapshot_has_trusted_channel_v2_provenance_v1(
    uuid, uuid
  )
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.declare_management_report_snapshot_replacement_v1(
    uuid, uuid, uuid, uuid, uuid, text
  )
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.read_management_report_snapshot_lifecycle_v1(uuid, uuid)
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;

REVOKE
  tongxingzhe_management_report_snapshot_lifecycle_writer
  FROM CURRENT_USER;

DO $lifecycle_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS lifecycle_role
      ON lifecycle_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE lifecycle_role.rolname =
      'tongxingzhe_management_report_snapshot_lifecycle_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_report_snapshot_lifecycle_writer FROM %I',
      member_name
    );
  END LOOP;
END
$lifecycle_membership$;

COMMENT ON TABLE app_private.management_report_snapshot_replacements
IS 'Immutable value-free correction links between existing trusted-v2 channel report snapshots.';

COMMENT ON FUNCTION
  app_private.declare_management_report_snapshot_replacement_v1(
    uuid, uuid, uuid, uuid, uuid, text
  )
IS 'Reauthorizes and appends one idempotent channel snapshot replacement without mutating or returning either protected report.';

COMMENT ON FUNCTION
  app_private.read_management_report_snapshot_lifecycle_v1(uuid, uuid)
IS 'Returns value-free active, superseded, or not-found lifecycle state for one trusted-v2 channel snapshot.';
