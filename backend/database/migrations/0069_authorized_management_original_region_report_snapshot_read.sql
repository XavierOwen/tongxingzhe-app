-- 0069_authorized_management_original_region_report_snapshot_read.sql
--
-- Slice 6BH exposes one private, explicitly authorized read for the 6BG
-- original-region snapshot lineage.  It has its own value-free access ledger
-- and verifies the 0068 claim, attempt, snapshot and source tuple again in
-- the same transaction.  It deliberately adds no role, runtime bridge or
-- second RLS policy: the ledger and functions belong to the shared snapshot
-- owner, while PUBLIC, runtime and every report reader/release writer remain
-- denied direct access.

CREATE TABLE app_private.management_original_region_report_snapshot_access_events (
  access_event_id uuid PRIMARY KEY,
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
    capability_id = 'view_anonymous_analytics'
  ),
  authorization_reference_at_utc timestamp with time zone NOT NULL,
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  requested_snapshot_id uuid NOT NULL,
  resolved_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  original_region_release_request_id uuid NULL
    REFERENCES app_private.management_original_region_report_release_attempts (
      release_request_id
    ),
  report_id text NULL,
  report_version integer NULL CHECK (
    report_version IS NULL OR report_version > 0
  ),
  query_fingerprint text NULL,
  release_lineage_id text NULL,
  reporting_time_zone text NULL,
  data_cutoff_utc timestamp with time zone NULL,
  source_tree_version text NULL CHECK (
    source_tree_version IS NULL
    OR length(btrim(source_tree_version)) BETWEEN 1 AND 200
  ),
  source_content_fingerprint text NULL CHECK (
    source_content_fingerprint IS NULL
    OR source_content_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  source_change_sequence bigint NULL CHECK (
    source_change_sequence IS NULL OR source_change_sequence >= 0
  ),
  accessed_at_utc timestamp with time zone NOT NULL,
  result_status text NOT NULL CHECK (
    result_status IN ('completed', 'not_found', 'untrusted_provenance')
  ),
  reason_code text NULL CHECK (
    reason_code IS NULL
    OR reason_code IN (
      'snapshot_not_available',
      'snapshot_provenance_untrusted'
    )
  ),
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(accessed_at_utc)),
  CHECK (
    data_cutoff_utc IS NULL OR isfinite(data_cutoff_utc)
  ),
  CHECK (authorization_reference_at_utc = accessed_at_utc),
  CHECK (
    (
      result_status = 'completed'
      AND reason_code IS NULL
      AND resolved_snapshot_id IS NOT NULL
      AND resolved_snapshot_id = requested_snapshot_id
      AND original_region_release_request_id IS NOT NULL
      AND report_id =
        'contact_sessions_by_original_region_two_periods'
      AND report_version = 1
      AND query_fingerprint =
        'management-report:contact_sessions_by_original_region_two_periods:v1'
      AND release_lineage_id =
        'management-original-region-report:contact_sessions_by_original_region_two_periods'
      AND reporting_time_zone IS NOT NULL
      AND data_cutoff_utc IS NOT NULL
      AND source_tree_version IS NOT NULL
      AND source_content_fingerprint IS NOT NULL
      AND source_change_sequence IS NOT NULL
    )
    OR (
      result_status = 'not_found'
      AND reason_code = 'snapshot_not_available'
      AND resolved_snapshot_id IS NULL
      AND original_region_release_request_id IS NULL
      AND report_id IS NULL
      AND report_version IS NULL
      AND query_fingerprint IS NULL
      AND release_lineage_id IS NULL
      AND reporting_time_zone IS NULL
      AND data_cutoff_utc IS NULL
      AND source_tree_version IS NULL
      AND source_content_fingerprint IS NULL
      AND source_change_sequence IS NULL
    )
    OR (
      result_status = 'untrusted_provenance'
      AND reason_code = 'snapshot_provenance_untrusted'
      AND resolved_snapshot_id IS NOT NULL
      AND resolved_snapshot_id = requested_snapshot_id
      AND original_region_release_request_id IS NULL
      AND report_id IS NOT NULL
      AND report_version IS NOT NULL
      AND query_fingerprint IS NOT NULL
      AND release_lineage_id IS NOT NULL
      AND reporting_time_zone IS NOT NULL
      AND data_cutoff_utc IS NOT NULL
      AND source_tree_version IS NULL
      AND source_content_fingerprint IS NULL
      AND source_change_sequence IS NULL
    )
  )
);

CREATE INDEX management_original_region_snapshot_access_events_project_idx
ON app_private.management_original_region_report_snapshot_access_events (
  project_id,
  accessed_at_utc DESC,
  access_event_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_original_region_report_snapshot_access_events
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
    tongxingzhe_management_report_snapshot_lifecycle_writer;

CREATE FUNCTION
  app_private.validate_management_original_region_snapshot_access_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private, app_data
AS $function$
DECLARE
  stored_snapshot app_private.management_report_snapshots%ROWTYPE;
  has_original_region_provenance boolean := false;
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
      MESSAGE = 'invalid original-region snapshot access authorization';
  END IF;

  IF NEW.capability_id IS DISTINCT FROM 'view_anonymous_analytics' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid original-region snapshot access capability';
  END IF;

  IF NEW.result_status = 'not_found' THEN
    -- A UUID that exists in another project is deliberately indistinguishable
    -- from an unknown UUID.  A same-project row must never be mislabeled as
    -- not_found, even when its provenance is foreign or malformed.
    IF EXISTS (
      SELECT 1
      FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = NEW.requested_snapshot_id
        AND snapshot.project_id = NEW.project_id
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid missing original-region snapshot access';
    END IF;
    RETURN NEW;
  END IF;

  SELECT snapshot.*
  INTO stored_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = NEW.resolved_snapshot_id
    AND snapshot.snapshot_id = NEW.requested_snapshot_id
    AND snapshot.project_id = NEW.project_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid original-region snapshot access snapshot identity';
  END IF;

  IF NEW.report_id IS DISTINCT FROM stored_snapshot.report_id
    OR NEW.report_version IS DISTINCT FROM stored_snapshot.report_version
    OR NEW.query_fingerprint IS DISTINCT FROM stored_snapshot.query_fingerprint
    OR NEW.release_lineage_id IS DISTINCT FROM
      stored_snapshot.release_lineage_id
    OR NEW.reporting_time_zone IS DISTINCT FROM
      stored_snapshot.reporting_time_zone
    OR NEW.data_cutoff_utc IS DISTINCT FROM stored_snapshot.data_cutoff_utc
    OR (
      NEW.result_status = 'completed'
      AND (
        NEW.source_tree_version IS DISTINCT FROM
          stored_snapshot.protected_report->'source_tree_context'->>
            'source_tree_version'
        OR NEW.source_content_fingerprint IS DISTINCT FROM
          stored_snapshot.protected_report->'source_tree_context'->>
            'source_content_fingerprint'
        OR NEW.source_change_sequence IS DISTINCT FROM
          stored_snapshot.source_change_sequence
      )
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid original-region snapshot access metadata';
  END IF;

  IF NEW.result_status = 'untrusted_provenance' THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM app_private.management_original_region_report_release_attempts AS attempt
    JOIN app_private.management_report_release_request_claims AS claim
      ON claim.release_request_id = attempt.release_request_id
     AND claim.release_family_id =
       'original_region_management_report_snapshot_release'
    WHERE attempt.release_request_id = NEW.original_region_release_request_id
      AND attempt.released_snapshot_id = NEW.resolved_snapshot_id
      AND attempt.release_request_id = stored_snapshot.release_request_id
      AND attempt.requested_by_app_user_id =
        stored_snapshot.created_by_app_user_id
      AND attempt.project_id = NEW.project_id
      AND attempt.capability_id = 'release_management_reports'
      AND attempt.report_id =
        'contact_sessions_by_original_region_two_periods'
      AND attempt.report_version = 1
      AND attempt.query_fingerprint =
        'management-report:contact_sessions_by_original_region_two_periods:v1'
      AND attempt.release_lineage_id =
        'management-original-region-report:contact_sessions_by_original_region_two_periods'
      AND attempt.result_status IN ('approved_baseline', 'approved')
      AND attempt.reason_codes = '[]'::jsonb
      AND attempt.reporting_time_zone = stored_snapshot.reporting_time_zone
      AND attempt.data_cutoff_utc = stored_snapshot.data_cutoff_utc
      AND attempt.source_tree_version = NEW.source_tree_version
      AND attempt.source_content_fingerprint =
        NEW.source_content_fingerprint
      AND attempt.source_change_sequence = NEW.source_change_sequence
      AND attempt.compared_snapshot_id IS NOT DISTINCT FROM
        stored_snapshot.previous_snapshot_id
      AND EXISTS (
        SELECT 1
        FROM app_private.project_reporting_time_zone_versions AS version_row
        WHERE version_row.project_id = attempt.project_id
          AND version_row.version_number =
            attempt.reporting_time_zone_version_number
          AND version_row.reporting_time_zone = attempt.reporting_time_zone
          AND version_row.effective_from_utc =
            attempt.reporting_time_zone_effective_from_utc
          AND NOT EXISTS (
            SELECT 1
            FROM app_private.project_reporting_time_zone_versions AS later_version
            WHERE later_version.project_id = attempt.project_id
              AND later_version.effective_from_utc <= attempt.data_cutoff_utc
              AND (
                later_version.effective_from_utc >
                  version_row.effective_from_utc
                OR (
                  later_version.effective_from_utc =
                    version_row.effective_from_utc
                  AND later_version.version_number >
                    version_row.version_number
                )
              )
          )
      )
      AND stored_snapshot.report_id = attempt.report_id
      AND stored_snapshot.report_version = attempt.report_version
      AND stored_snapshot.query_fingerprint = attempt.query_fingerprint
      AND stored_snapshot.release_lineage_id = attempt.release_lineage_id
      AND stored_snapshot.data_cutoff_utc = attempt.data_cutoff_utc
      AND stored_snapshot.source_change_sequence =
        attempt.source_change_sequence
      AND stored_snapshot.protected_report->'source_tree_context'->>
        'source_tree_version' = attempt.source_tree_version
      AND stored_snapshot.protected_report->'source_tree_context'->>
        'source_content_fingerprint' = attempt.source_content_fingerprint
  ) INTO has_original_region_provenance;

  IF NOT has_original_region_provenance THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid trusted original-region snapshot access provenance';
  END IF;

  PERFORM app_private.validate_management_original_region_report_document_v1(
    stored_snapshot.protected_report
  );

  RETURN NEW;
END
$function$;

CREATE TRIGGER
  management_original_region_snapshot_access_events_validate
BEFORE INSERT
ON app_private.management_original_region_report_snapshot_access_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_original_region_snapshot_access_insert_v1();

CREATE TRIGGER
  management_original_region_snapshot_access_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_original_region_report_snapshot_access_events
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.read_authorized_management_original_region_report_snapshot_v1(
    requested_app_user_id uuid,
    requested_project_id uuid,
    requested_snapshot_id uuid
  )
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  stored_snapshot app_private.management_report_snapshots%ROWTYPE;
  original_region_attempt
    app_private.management_original_region_report_release_attempts%ROWTYPE;
  authorization_evidence jsonb;
  access_event_id_value uuid;
  authorization_reference_at_utc_value timestamp with time zone;
  result_status_value text;
  reason_code_value text;
  access_result jsonb;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_snapshot_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid authorized original-region snapshot request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'view_anonymous_analytics'
    );
  authorization_reference_at_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT snapshot.*
  INTO stored_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_snapshot_id
    AND snapshot.project_id = requested_project_id;

  IF NOT FOUND THEN
    result_status_value = 'not_found';
    reason_code_value = 'snapshot_not_available';
  ELSE
    SELECT attempt.*
    INTO original_region_attempt
    FROM app_private.management_original_region_report_release_attempts AS attempt
    JOIN app_private.management_report_release_request_claims AS claim
      ON claim.release_request_id = attempt.release_request_id
     AND claim.release_family_id =
       'original_region_management_report_snapshot_release'
    WHERE attempt.released_snapshot_id = stored_snapshot.snapshot_id
      AND attempt.release_request_id = stored_snapshot.release_request_id
      AND attempt.requested_by_app_user_id =
        stored_snapshot.created_by_app_user_id
      AND attempt.project_id = stored_snapshot.project_id
      AND attempt.capability_id = 'release_management_reports'
      AND attempt.report_id =
        'contact_sessions_by_original_region_two_periods'
      AND attempt.report_version = 1
      AND attempt.query_fingerprint =
        'management-report:contact_sessions_by_original_region_two_periods:v1'
      AND attempt.release_lineage_id =
        'management-original-region-report:contact_sessions_by_original_region_two_periods'
      AND attempt.result_status IN ('approved_baseline', 'approved')
      AND attempt.reason_codes = '[]'::jsonb
      AND attempt.reporting_time_zone = stored_snapshot.reporting_time_zone
      AND attempt.data_cutoff_utc = stored_snapshot.data_cutoff_utc
      AND attempt.source_change_sequence =
        stored_snapshot.source_change_sequence
      AND attempt.compared_snapshot_id IS NOT DISTINCT FROM
        stored_snapshot.previous_snapshot_id
      AND EXISTS (
        SELECT 1
        FROM app_private.project_reporting_time_zone_versions AS version_row
        WHERE version_row.project_id = attempt.project_id
          AND version_row.version_number =
            attempt.reporting_time_zone_version_number
          AND version_row.reporting_time_zone = attempt.reporting_time_zone
          AND version_row.effective_from_utc =
            attempt.reporting_time_zone_effective_from_utc
          AND NOT EXISTS (
            SELECT 1
            FROM app_private.project_reporting_time_zone_versions AS later_version
            WHERE later_version.project_id = attempt.project_id
              AND later_version.effective_from_utc <= attempt.data_cutoff_utc
              AND (
                later_version.effective_from_utc >
                  version_row.effective_from_utc
                OR (
                  later_version.effective_from_utc =
                    version_row.effective_from_utc
                  AND later_version.version_number >
                    version_row.version_number
                )
              )
          )
      )
      AND stored_snapshot.report_id = attempt.report_id
      AND stored_snapshot.report_version = attempt.report_version
      AND stored_snapshot.query_fingerprint = attempt.query_fingerprint
      AND stored_snapshot.release_lineage_id = attempt.release_lineage_id
      AND stored_snapshot.data_cutoff_utc = attempt.data_cutoff_utc
      AND stored_snapshot.protected_report->'source_tree_context'->>
        'source_tree_version' = attempt.source_tree_version
      AND stored_snapshot.protected_report->'source_tree_context'->>
        'source_content_fingerprint' = attempt.source_content_fingerprint
    LIMIT 1;

    IF FOUND THEN
      BEGIN
        PERFORM app_private.validate_management_original_region_report_document_v1(
          stored_snapshot.protected_report
        );
        result_status_value = 'completed';
      EXCEPTION WHEN invalid_parameter_value THEN
        result_status_value = 'untrusted_provenance';
        reason_code_value = 'snapshot_provenance_untrusted';
      END;
    ELSE
      result_status_value = 'untrusted_provenance';
      reason_code_value = 'snapshot_provenance_untrusted';
    END IF;
  END IF;

  access_event_id_value = gen_random_uuid();

  INSERT INTO app_private.management_original_region_report_snapshot_access_events (
    access_event_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    requested_snapshot_id,
    resolved_snapshot_id,
    original_region_release_request_id,
    report_id,
    report_version,
    query_fingerprint,
    release_lineage_id,
    reporting_time_zone,
    data_cutoff_utc,
    source_tree_version,
    source_content_fingerprint,
    source_change_sequence,
    accessed_at_utc,
    result_status,
    reason_code
  ) VALUES (
    access_event_id_value,
    requested_app_user_id,
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    authorization_evidence->>'capability_id',
    authorization_reference_at_utc_value,
    requested_project_id,
    requested_snapshot_id,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.snapshot_id
    END,
    CASE
      WHEN result_status_value = 'completed'
        THEN original_region_attempt.release_request_id
      ELSE NULL
    END,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.report_id
    END,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.report_version
    END,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.query_fingerprint
    END,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.release_lineage_id
    END,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.reporting_time_zone
    END,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.data_cutoff_utc
    END,
    CASE
      WHEN result_status_value = 'completed'
        THEN stored_snapshot.protected_report->'source_tree_context'->>
        'source_tree_version'
      ELSE NULL
    END,
    CASE
      WHEN result_status_value = 'completed'
        THEN stored_snapshot.protected_report->'source_tree_context'->>
        'source_content_fingerprint'
      ELSE NULL
    END,
    CASE
      WHEN result_status_value = 'completed'
        THEN stored_snapshot.source_change_sequence
      ELSE NULL
    END,
    authorization_reference_at_utc_value,
    result_status_value,
    reason_code_value
  );

  access_result = jsonb_build_object(
    'access_contract_id',
      'authorized_original_region_management_report_snapshot_read_v1',
    'access_event_id', access_event_id_value,
    'requested_snapshot_id', requested_snapshot_id,
    'resolved_snapshot_id', CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.snapshot_id
    END,
    'result_status', result_status_value,
    'reason_code', reason_code_value
  );

  IF result_status_value = 'completed' THEN
    access_result = access_result || jsonb_build_object(
      'protected_report', stored_snapshot.protected_report
    );
  END IF;

  RETURN access_result;
END
$function$;

-- Resolve the owner from the shared immutable snapshot table.  This avoids a
-- new reader role and leaves the deployment owner as the only fixture caller;
-- the private table and both functions are not directly callable by app roles.
DO $owner$
DECLARE
  snapshot_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT snapshot_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = 'app_private.management_report_snapshots'::regclass;

  EXECUTE format(
    'ALTER TABLE app_private.management_original_region_report_snapshot_access_events OWNER TO %I',
    snapshot_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.validate_management_original_region_snapshot_access_insert_v1() OWNER TO %I',
    snapshot_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.read_authorized_management_original_region_report_snapshot_v1(uuid,uuid,uuid) OWNER TO %I',
    snapshot_owner
  );
END
$owner$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_original_region_snapshot_access_insert_v1(),
  app_private.read_authorized_management_original_region_report_snapshot_v1(
    uuid,
    uuid,
    uuid
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
    tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT EXECUTE ON FUNCTION
  app_private.read_authorized_management_original_region_report_snapshot_v1(
    uuid,
    uuid,
    uuid
  )
  TO CURRENT_USER;

COMMENT ON TABLE
  app_private.management_original_region_report_snapshot_access_events
IS 'Immutable value-free audit for authorized original-region snapshot reads; it stores no report cells, source records, contributors, locations or PII.';

COMMENT ON FUNCTION
  app_private.read_authorized_management_original_region_report_snapshot_v1(
    uuid,
    uuid,
    uuid
  )
IS 'Reauthorizes one fixed original-region snapshot read and accepts only 0068 approved provenance, including its claim, attempt, snapshot and source tree tuple.';
