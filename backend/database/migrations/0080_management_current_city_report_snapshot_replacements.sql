-- 0080_management_current_city_report_snapshot_replacements.sql
--
-- Slice 6CB records an append-only, value-free direct replacement relation
-- between two already-approved 6AO current-city snapshots. It does not
-- generate a snapshot, alter an existing snapshot, or change any read path.

-- Replacement requests share the value-free UUID ledger used by release
-- requests, but use a distinct family claim.  The common advisory-lock key
-- makes replacement and release claims mutually exclusive in both orders.
ALTER TABLE app_private.management_report_release_request_claims
  DROP CONSTRAINT management_report_release_request_claims_family_check;

ALTER TABLE app_private.management_report_release_request_claims
  ADD CONSTRAINT management_report_release_request_claims_family_check
  CHECK (release_family_id IN (
    'channel_management_report_snapshot_release',
    'current_city_management_report_snapshot_release',
    'interest_management_report_snapshot_release',
    'original_region_management_report_snapshot_release',
    'original_region_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_release',
    'current_city_management_report_snapshot_replacement'
  ));

-- The shared snapshot store remains shared storage.  This policy adds only
-- the fixed current-city family to the closed lifecycle role; the role
-- keeps its separate channel policy and gains no other report-family scope.
CREATE POLICY
  management_current_city_snapshot_replacement_read_scope
ON app_private.management_report_snapshots
FOR SELECT
TO tongxingzhe_management_report_snapshot_lifecycle_writer
USING (
  report_id = 'contact_sessions_by_current_city_two_periods'
  AND release_lineage_id =
    'management-region-report:contact_sessions_by_current_city_two_periods'
);

CREATE TABLE app_private.management_current_city_report_snapshot_replacements (
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
      'management-region-report:contact_sessions_by_current_city_two_periods'
  ),
  report_id text NOT NULL CHECK (
    report_id = 'contact_sessions_by_current_city_two_periods'
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

CREATE INDEX
  management_current_city_snapshot_replacements_project_idx
ON app_private.management_current_city_report_snapshot_replacements (
  project_id,
  release_lineage_id,
  declared_at_utc DESC,
  replacement_request_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_current_city_report_snapshot_replacements
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_follow_up_consent_config_writer,
    tongxingzhe_management_follow_up_consent_ratio_reader,
    tongxingzhe_management_consent_ratio_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer;

CREATE TRIGGER
  management_current_city_snapshot_replacements_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_current_city_report_snapshot_replacements
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

-- The existing current-city release writer owns the 0057 attempt ledger.
-- Keep that table private: the lifecycle role receives only this value-free
-- SECURITY DEFINER seam and never receives a direct attempt-table privilege.
CREATE FUNCTION
  app_private.current_city_snapshot_replacement_provenance_v1(
    requested_snapshot_id uuid,
    requested_project_id uuid
  )
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
  SELECT jsonb_build_object(
    'reporting_time_zone_version_number', attempt.reporting_time_zone_version_number,
    'reporting_time_zone', attempt.reporting_time_zone,
    'reporting_time_zone_effective_from_utc',
      attempt.reporting_time_zone_effective_from_utc,
    'data_cutoff_utc', attempt.data_cutoff_utc,
    'target_tree_version', attempt.target_tree_version,
    'target_content_fingerprint', attempt.target_content_fingerprint,
    'selection_sequence', snapshot.protected_report->'target_context'->>
      'selection_sequence',
    'selection_source', snapshot.protected_report->'target_context'->>
      'selection_source',
    'selection_evidence_at_utc', snapshot.protected_report->'target_context'->>
      'selection_evidence_at_utc',
    'tree_published_at_utc', snapshot.protected_report->'target_context'->>
      'tree_published_at_utc',
    'source_change_sequence', snapshot.source_change_sequence
  )
  FROM app_private.management_report_snapshots AS snapshot
  JOIN app_private.management_current_city_report_release_attempts AS attempt
    ON attempt.released_snapshot_id = snapshot.snapshot_id
    AND attempt.release_request_id = snapshot.release_request_id
    AND attempt.requested_by_app_user_id = snapshot.created_by_app_user_id
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
  JOIN app_private.project_reporting_time_zone_versions AS version_row
    ON version_row.project_id = attempt.project_id
    AND version_row.version_number = attempt.reporting_time_zone_version_number
    AND version_row.reporting_time_zone = attempt.reporting_time_zone
    AND version_row.effective_from_utc =
      attempt.reporting_time_zone_effective_from_utc
  WHERE snapshot.snapshot_id = requested_snapshot_id
    AND snapshot.project_id = requested_project_id
    AND snapshot.report_id =
      'contact_sessions_by_current_city_two_periods'
    AND snapshot.report_version = 1
    AND snapshot.release_lineage_id =
      'management-region-report:contact_sessions_by_current_city_two_periods'
    AND snapshot.query_fingerprint =
      'management-report:contact_sessions_by_current_city_two_periods:v1'
    AND attempt.result_status IN ('approved_baseline', 'approved')
    AND attempt.reason_codes = '[]'::jsonb
    AND attempt.target_tree_version =
      snapshot.protected_report->'target_context'->>
        'target_tree_version'
    AND attempt.target_content_fingerprint =
      snapshot.protected_report->'target_context'->>
        'target_content_fingerprint'
    AND snapshot.protected_report->'target_context'->>
      'selection_sequence' IS NOT NULL
    AND snapshot.protected_report->'target_context'->>
      'selection_source' IS NOT NULL
    AND snapshot.protected_report->'target_context'->>
      'selection_evidence_at_utc' IS NOT NULL
    AND snapshot.protected_report->'target_context'->>
      'tree_published_at_utc' IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM app_private.project_reporting_time_zone_versions AS later_version
      WHERE later_version.project_id = attempt.project_id
        AND later_version.effective_from_utc <= attempt.data_cutoff_utc
        AND (
          later_version.effective_from_utc > version_row.effective_from_utc
          OR (
            later_version.effective_from_utc = version_row.effective_from_utc
            AND later_version.version_number > version_row.version_number
          )
        )
    )
  LIMIT 1
$function$;

CREATE FUNCTION
  app_private.management_current_city_snapshot_has_trusted_provenance_v1(
    requested_snapshot_id uuid,
    requested_project_id uuid
  )
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
  /* Split the trust check across the two closed owners: the current-city
     release writer exposes attempt provenance, while the lifecycle writer
     verifies the matching value-free family claim. */
  SELECT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    JOIN app_private.management_report_release_request_claims AS claim
      ON claim.release_request_id = snapshot.release_request_id
      AND claim.release_family_id =
        'current_city_management_report_snapshot_release'
    WHERE snapshot.snapshot_id = requested_snapshot_id
      AND snapshot.project_id = requested_project_id
      AND snapshot.report_id =
        'contact_sessions_by_current_city_two_periods'
      AND snapshot.report_version = 1
      AND snapshot.release_lineage_id =
        'management-region-report:contact_sessions_by_current_city_two_periods'
      AND snapshot.query_fingerprint =
        'management-report:contact_sessions_by_current_city_two_periods:v1'
      AND snapshot.protected_report->>'project_id' =
        snapshot.project_id::text
      AND (snapshot.protected_report->>'data_cutoff_utc')::timestamptz =
        snapshot.data_cutoff_utc
      AND (snapshot.protected_report->>'source_change_sequence')::bigint =
        snapshot.source_change_sequence
      AND app_private.current_city_snapshot_replacement_provenance_v1(
        snapshot.snapshot_id,
        requested_project_id
      ) IS NOT NULL
  )
$function$;

CREATE FUNCTION
  app_private.validate_management_current_city_snapshot_replacement_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private, app_data
AS $function$
DECLARE
  superseded_snapshot app_private.management_report_snapshots%ROWTYPE;
  replacement_snapshot app_private.management_report_snapshots%ROWTYPE;
  superseded_provenance jsonb;
  replacement_provenance jsonb;
  expected_result_document jsonb;
BEGIN
  IF NEW.capability_id IS DISTINCT FROM 'release_management_reports' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid current-city replacement capability';
  END IF;

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
      MESSAGE = 'invalid current-city replacement authorization lineage';
  END IF;

  SELECT snapshot.*
  INTO STRICT superseded_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = NEW.superseded_snapshot_id
    AND snapshot.project_id = NEW.project_id;

  SELECT snapshot.*
  INTO STRICT replacement_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = NEW.replacement_snapshot_id
    AND snapshot.project_id = NEW.project_id;

  IF superseded_snapshot.report_id <>
      'contact_sessions_by_current_city_two_periods'
    OR replacement_snapshot.report_id <> superseded_snapshot.report_id
    OR superseded_snapshot.report_version <> 1
    OR replacement_snapshot.report_version <> superseded_snapshot.report_version
    OR superseded_snapshot.release_lineage_id <>
      'management-region-report:contact_sessions_by_current_city_two_periods'
    OR replacement_snapshot.release_lineage_id <>
      superseded_snapshot.release_lineage_id
    OR superseded_snapshot.query_fingerprint <>
      'management-report:contact_sessions_by_current_city_two_periods:v1'
    OR replacement_snapshot.query_fingerprint <>
      superseded_snapshot.query_fingerprint
    OR superseded_snapshot.reporting_time_zone <>
      replacement_snapshot.reporting_time_zone
    OR superseded_snapshot.data_cutoff_utc >=
      replacement_snapshot.data_cutoff_utc
    OR superseded_snapshot.released_at_utc >=
      replacement_snapshot.released_at_utc
    OR superseded_snapshot.source_change_sequence >
      replacement_snapshot.source_change_sequence
    OR superseded_snapshot.protected_report->>'privacy_policy' IS DISTINCT FROM
      replacement_snapshot.protected_report->>'privacy_policy'
    OR superseded_snapshot.protected_report->>'source_scope' IS DISTINCT FROM
      replacement_snapshot.protected_report->>'source_scope'
    OR (
      (superseded_snapshot.protected_report->'target_context') -
        'data_cutoff_utc'::text
    ) IS DISTINCT FROM (
      (replacement_snapshot.protected_report->'target_context') -
        'data_cutoff_utc'::text
    )
    OR (
      (superseded_snapshot.protected_report->'periods') -
        'data_cutoff_utc'::text
    ) IS DISTINCT FROM (
      (replacement_snapshot.protected_report->'periods') -
        'data_cutoff_utc'::text
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement lineage is inconsistent';
  END IF;

  superseded_provenance =
    app_private.current_city_snapshot_replacement_provenance_v1(
      superseded_snapshot.snapshot_id,
      NEW.project_id
    );
  replacement_provenance =
    app_private.current_city_snapshot_replacement_provenance_v1(
      replacement_snapshot.snapshot_id,
      NEW.project_id
    );

  IF superseded_provenance IS NULL OR replacement_provenance IS NULL
    OR superseded_provenance->>'reporting_time_zone_version_number' <>
      replacement_provenance->>'reporting_time_zone_version_number'
    OR superseded_provenance->>'reporting_time_zone' <>
      replacement_provenance->>'reporting_time_zone'
    OR (
      superseded_provenance->>'reporting_time_zone_effective_from_utc'
    )::timestamptz <>
      (
        replacement_provenance->>'reporting_time_zone_effective_from_utc'
      )::timestamptz
    OR superseded_provenance->>'target_tree_version' <>
      replacement_provenance->>'target_tree_version'
    OR superseded_provenance->>'target_content_fingerprint' <>
      replacement_provenance->>'target_content_fingerprint'
    OR superseded_provenance->>'selection_sequence' <>
      replacement_provenance->>'selection_sequence'
    OR superseded_provenance->>'selection_source' <>
      replacement_provenance->>'selection_source'
    OR superseded_provenance->>'selection_evidence_at_utc' <>
      replacement_provenance->>'selection_evidence_at_utc'
    OR superseded_provenance->>'tree_published_at_utc' <>
      replacement_provenance->>'tree_published_at_utc'
    OR (superseded_provenance->>'source_change_sequence')::bigint >
      (replacement_provenance->>'source_change_sequence')::bigint
    OR (superseded_provenance->>'data_cutoff_utc')::timestamptz <>
      superseded_snapshot.data_cutoff_utc
    OR (replacement_provenance->>'data_cutoff_utc')::timestamptz <>
      replacement_snapshot.data_cutoff_utc
    OR superseded_provenance->>'reporting_time_zone' <>
      superseded_snapshot.reporting_time_zone
    OR replacement_provenance->>'reporting_time_zone' <>
      replacement_snapshot.reporting_time_zone
    OR superseded_provenance->>'target_tree_version' IS DISTINCT FROM
      superseded_snapshot.protected_report->'target_context'->>
        'target_tree_version'
    OR replacement_provenance->>'target_tree_version' IS DISTINCT FROM
      replacement_snapshot.protected_report->'target_context'->>
        'target_tree_version'
    OR superseded_provenance->>'target_content_fingerprint' IS DISTINCT FROM
      superseded_snapshot.protected_report->'target_context'->>
        'target_content_fingerprint'
    OR replacement_provenance->>'target_content_fingerprint' IS DISTINCT FROM
      replacement_snapshot.protected_report->'target_context'->>
        'target_content_fingerprint'
    OR superseded_provenance->>'selection_sequence' IS DISTINCT FROM
      superseded_snapshot.protected_report->'target_context'->>
        'selection_sequence'
    OR replacement_provenance->>'selection_sequence' IS DISTINCT FROM
      replacement_snapshot.protected_report->'target_context'->>
        'selection_sequence'
    OR superseded_provenance->>'selection_source' IS DISTINCT FROM
      superseded_snapshot.protected_report->'target_context'->>
        'selection_source'
    OR replacement_provenance->>'selection_source' IS DISTINCT FROM
      replacement_snapshot.protected_report->'target_context'->>
        'selection_source'
    OR superseded_provenance->>'selection_evidence_at_utc' IS DISTINCT FROM
      superseded_snapshot.protected_report->'target_context'->>
        'selection_evidence_at_utc'
    OR replacement_provenance->>'selection_evidence_at_utc' IS DISTINCT FROM
      replacement_snapshot.protected_report->'target_context'->>
        'selection_evidence_at_utc'
    OR superseded_provenance->>'tree_published_at_utc' IS DISTINCT FROM
      superseded_snapshot.protected_report->'target_context'->>
        'tree_published_at_utc'
    OR replacement_provenance->>'tree_published_at_utc' IS DISTINCT FROM
      replacement_snapshot.protected_report->'target_context'->>
        'tree_published_at_utc'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement provenance is inconsistent';
  END IF;

  IF NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      superseded_snapshot.snapshot_id,
      NEW.project_id
    )
    OR NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      replacement_snapshot.snapshot_id,
      NEW.project_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement provenance is untrusted';
  END IF;

  PERFORM app_private.validate_management_current_city_report_document_v1(
    superseded_snapshot.protected_report
  );
  PERFORM app_private.validate_management_current_city_report_document_v1(
    replacement_snapshot.protected_report
  );

  expected_result_document = jsonb_build_object(
    'replacement_contract_id',
      'current_city_management_report_snapshot_replacement_v1',
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
      MESSAGE = 'invalid current-city replacement result document';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER
  management_current_city_snapshot_replacements_validate
BEFORE INSERT
ON app_private.management_current_city_report_snapshot_replacements
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_current_city_snapshot_replacement_v1();

CREATE FUNCTION
  app_private.declare_management_current_city_snapshot_replacement_v1(
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
    app_private.management_current_city_report_snapshot_replacements%ROWTYPE;
  superseded_snapshot app_private.management_report_snapshots%ROWTYPE;
  replacement_snapshot app_private.management_report_snapshots%ROWTYPE;
  authorization_evidence jsonb;
  claimed_request_family text;
  declared_at_utc_value timestamp with time zone;
  replacement_result jsonb;
BEGIN
  IF requested_replacement_request_id IS NULL
    OR requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_superseded_snapshot_id IS NULL
    OR requested_replacement_snapshot_id IS NULL
    OR requested_superseded_snapshot_id = requested_replacement_snapshot_id
    OR requested_replacement_reason_code IS NULL
    OR requested_replacement_reason_code NOT IN (
      'late_accepted_data',
      'contact_revision',
      'contact_void'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid current-city replacement request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-release-request:'
        || requested_replacement_request_id::text,
      0
    )
  );

  -- Authorization is consumed again after the request lock so concurrent
  -- revocation and duplicate requests have one linearization point.
  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  SELECT replacement.*
  INTO existing_replacement
  FROM app_private.management_current_city_report_snapshot_replacements
    AS replacement
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
        MESSAGE = 'current-city replacement idempotency conflict';
    END IF;
    RETURN existing_replacement.result_document;
  END IF;

  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id,
    release_family_id
  ) VALUES (
    requested_replacement_request_id,
    'current_city_management_report_snapshot_replacement'
  )
  ON CONFLICT (release_request_id) DO NOTHING;

  SELECT claim.release_family_id
  INTO STRICT claimed_request_family
  FROM app_private.management_report_release_request_claims AS claim
  WHERE claim.release_request_id = requested_replacement_request_id;

  IF claimed_request_family <>
      'current_city_management_report_snapshot_replacement'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'replacement request id was already used by another report contract';
  END IF;

  SELECT snapshot.*
  INTO superseded_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_superseded_snapshot_id
    AND snapshot.project_id = requested_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement snapshot is unavailable';
  END IF;

  SELECT snapshot.*
  INTO replacement_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_replacement_snapshot_id
    AND snapshot.project_id = requested_project_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement snapshot is unavailable';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-current-city-snapshot-replacement-lineage:'
        || requested_project_id::text || ':'
        || superseded_snapshot.release_lineage_id,
      0
    )
  );

  -- The lineage lock may wait behind a competing replacement.  Re-resolve
  -- authorization and re-read all lineage state after that wait.
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
      'contact_sessions_by_current_city_two_periods'
    OR replacement_snapshot.report_id <> superseded_snapshot.report_id
    OR superseded_snapshot.report_version <> 1
    OR replacement_snapshot.report_version <> superseded_snapshot.report_version
    OR superseded_snapshot.release_lineage_id <>
      'management-region-report:contact_sessions_by_current_city_two_periods'
    OR replacement_snapshot.release_lineage_id <>
      superseded_snapshot.release_lineage_id
    OR superseded_snapshot.query_fingerprint <>
      'management-report:contact_sessions_by_current_city_two_periods:v1'
    OR replacement_snapshot.query_fingerprint <>
      superseded_snapshot.query_fingerprint
    OR superseded_snapshot.reporting_time_zone <>
      replacement_snapshot.reporting_time_zone
    OR superseded_snapshot.data_cutoff_utc >=
      replacement_snapshot.data_cutoff_utc
    OR superseded_snapshot.released_at_utc >=
      replacement_snapshot.released_at_utc
    OR superseded_snapshot.source_change_sequence >
      replacement_snapshot.source_change_sequence
    OR superseded_snapshot.protected_report->>'privacy_policy' IS DISTINCT FROM
      replacement_snapshot.protected_report->>'privacy_policy'
    OR superseded_snapshot.protected_report->>'source_scope' IS DISTINCT FROM
      replacement_snapshot.protected_report->>'source_scope'
    OR (
      (superseded_snapshot.protected_report->'target_context') -
        'data_cutoff_utc'::text
    ) IS DISTINCT FROM (
      (replacement_snapshot.protected_report->'target_context') -
        'data_cutoff_utc'::text
    )
    OR (
      (superseded_snapshot.protected_report->'periods') -
        'data_cutoff_utc'::text
    ) IS DISTINCT FROM (
      (replacement_snapshot.protected_report->'periods') -
        'data_cutoff_utc'::text
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement lineage is inconsistent';
  END IF;

  IF NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      superseded_snapshot.snapshot_id,
      requested_project_id
    )
    OR NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      replacement_snapshot.snapshot_id,
      requested_project_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current-city replacement provenance is untrusted';
  END IF;

  PERFORM app_private.validate_management_current_city_report_document_v1(
    superseded_snapshot.protected_report
  );
  PERFORM app_private.validate_management_current_city_report_document_v1(
    replacement_snapshot.protected_report
  );

  IF EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_snapshot_replacements
      AS replacement
    WHERE replacement.superseded_snapshot_id =
      requested_superseded_snapshot_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current-city snapshot is no longer an active head';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_snapshot_replacements
      AS replacement
    WHERE replacement.superseded_snapshot_id =
        requested_replacement_snapshot_id
      OR replacement.replacement_snapshot_id =
        requested_replacement_snapshot_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'replacement snapshot already belongs to an current-city replacement chain';
  END IF;

  replacement_result = jsonb_build_object(
    'replacement_contract_id',
      'current_city_management_report_snapshot_replacement_v1',
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

  INSERT INTO app_private.management_current_city_report_snapshot_replacements (
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

CREATE FUNCTION
  app_private.read_management_current_city_report_snapshot_lifecycle_v1(
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
      MESSAGE = 'invalid current-city snapshot lifecycle request';
  END IF;

  IF NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      requested_snapshot_id,
      requested_project_id
    )
  THEN
    RETURN jsonb_build_object(
      'lifecycle_contract_id',
        'current_city_management_report_snapshot_lifecycle_v1',
      'project_id', requested_project_id,
      'snapshot_id', requested_snapshot_id,
      'lifecycle_status', 'not_found',
      'replacement_snapshot_id', NULL
    );
  END IF;

  SELECT replacement.replacement_snapshot_id
  INTO replacement_snapshot_id_value
  FROM app_private.management_current_city_report_snapshot_replacements
    AS replacement
  WHERE replacement.project_id = requested_project_id
    AND replacement.superseded_snapshot_id = requested_snapshot_id;

  RETURN jsonb_build_object(
    'lifecycle_contract_id',
      'current_city_management_report_snapshot_lifecycle_v1',
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
  app_private.current_city_snapshot_replacement_provenance_v1(uuid, uuid),
  app_private.management_current_city_snapshot_has_trusted_provenance_v1(
    uuid, uuid
  ),
  app_private.validate_management_current_city_snapshot_replacement_v1(),
  app_private.declare_management_current_city_snapshot_replacement_v1(
    uuid, uuid, uuid, uuid, uuid, text
  ),
  app_private.read_management_current_city_report_snapshot_lifecycle_v1(
    uuid, uuid
  )
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer,
    tongxingzhe_management_follow_up_consent_config_writer,
    tongxingzhe_management_follow_up_consent_ratio_reader,
    tongxingzhe_management_consent_ratio_snapshot_release_writer;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT SELECT ON
  app_data.app_users,
  app_data.workspaces,
  app_data.projects,
  app_data.organization_memberships,
  app_data.project_memberships,
  app_data.management_report_capability_grants,
  app_private.management_report_snapshots,
  app_private.project_reporting_time_zone_versions
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT SELECT, INSERT ON
  app_private.management_report_release_request_claims
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT SELECT, INSERT ON
  app_private.management_current_city_report_snapshot_replacements
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT EXECUTE ON FUNCTION
  app_private.current_city_snapshot_replacement_provenance_v1(uuid, uuid),
  app_private.validate_management_current_city_report_document_v1(jsonb)
  TO tongxingzhe_management_report_snapshot_lifecycle_writer;

ALTER FUNCTION
  app_private.current_city_snapshot_replacement_provenance_v1(uuid, uuid)
  OWNER TO tongxingzhe_management_current_city_snapshot_release_writer;

ALTER TABLE
  app_private.management_current_city_report_snapshot_replacements
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;

ALTER FUNCTION
  app_private.management_current_city_snapshot_has_trusted_provenance_v1(
    uuid, uuid
  )
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.validate_management_current_city_snapshot_replacement_v1()
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.declare_management_current_city_snapshot_replacement_v1(
    uuid, uuid, uuid, uuid, uuid, text
  )
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;
ALTER FUNCTION
  app_private.read_management_current_city_report_snapshot_lifecycle_v1(
    uuid, uuid
  )
  OWNER TO tongxingzhe_management_report_snapshot_lifecycle_writer;

COMMENT ON TABLE
  app_private.management_current_city_report_snapshot_replacements
IS 'Immutable value-free direct replacement links between existing trusted current-city report snapshots.';

COMMENT ON TABLE app_private.management_report_release_request_claims
IS 'Value-free request UUID ownership across management report release families and current-city snapshot replacement.';

COMMENT ON FUNCTION
  app_private.declare_management_current_city_snapshot_replacement_v1(
    uuid, uuid, uuid, uuid, uuid, text
  )
IS 'Reauthorizes and appends one idempotent current-city snapshot replacement without mutating or returning either protected report.';

COMMENT ON FUNCTION
  app_private.read_management_current_city_report_snapshot_lifecycle_v1(
    uuid, uuid
  )
IS 'Returns value-free active, superseded, or not-found lifecycle state for one trusted current-city snapshot.';
