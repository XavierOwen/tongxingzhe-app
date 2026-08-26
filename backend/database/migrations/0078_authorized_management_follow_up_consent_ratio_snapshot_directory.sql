-- 0078_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
--
-- Slice 6BU exposes a bounded metadata-only directory for the 0075
-- follow-up consent-ratio snapshot lineage.  The directory has its own
-- immutable, value-free audit and rechecks the complete consent provenance.
-- It deliberately adds no app_data identity bridge; a later runtime slice
-- must provide that boundary without opening app_private.

CREATE TABLE
  app_private.management_follow_up_consent_snapshot_directory_access_events (
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
  accessed_at_utc timestamp with time zone NOT NULL,
  result_status text NOT NULL CHECK (result_status = 'completed'),
  returned_snapshot_count integer NOT NULL CHECK (
    returned_snapshot_count BETWEEN 0 AND 20
  ),
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(accessed_at_utc)),
  CHECK (authorization_reference_at_utc = accessed_at_utc)
);

CREATE INDEX management_follow_up_consent_snapshot_directory_idx
ON app_private.management_follow_up_consent_snapshot_directory_access_events (
  project_id,
  accessed_at_utc DESC,
  access_event_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_follow_up_consent_snapshot_directory_access_events
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

CREATE TRIGGER management_follow_up_consent_snapshot_directory_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_follow_up_consent_snapshot_directory_access_events
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.validate_management_follow_up_consent_snapshot_directory_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
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
      AND project_membership.project_membership_id = NEW.project_membership_id
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
      MESSAGE =
        'invalid follow-up consent snapshot directory authorization';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_follow_up_consent_snapshot_directory_validate
BEFORE INSERT
ON app_private.management_follow_up_consent_snapshot_directory_access_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_follow_up_consent_snapshot_directory_v1();

CREATE FUNCTION
  app_private.list_authorized_management_follow_up_consent_snapshots_v1(
    requested_app_user_id uuid,
    requested_project_id uuid
  )
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_evidence jsonb;
  authorization_reference_at_utc_value timestamp with time zone;
  directory_access_event_id uuid;
  snapshot_directory jsonb;
  returned_snapshot_count_value integer;
BEGIN
  IF requested_app_user_id IS NULL OR requested_project_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid follow-up consent snapshot directory request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'view_anonymous_analytics'
    );
  authorization_reference_at_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'snapshot_id', directory_row.snapshot_id,
          'report_id', directory_row.report_id,
          'report_version', directory_row.report_version,
          'reporting_time_zone', directory_row.reporting_time_zone,
          'data_cutoff_utc', to_char(
            directory_row.data_cutoff_utc AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
          ),
          'released_at_utc', to_char(
            directory_row.released_at_utc AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
          )
        ) ORDER BY
          directory_row.data_cutoff_utc DESC,
          directory_row.released_at_utc DESC,
          directory_row.snapshot_id DESC
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  INTO snapshot_directory, returned_snapshot_count_value
  FROM (
    SELECT
      snapshot.snapshot_id,
      snapshot.report_id,
      snapshot.report_version,
      snapshot.reporting_time_zone,
      snapshot.data_cutoff_utc,
      snapshot.released_at_utc
    FROM app_private.management_report_snapshots AS snapshot
    JOIN app_private.management_follow_up_consent_report_release_attempts
      AS attempt
      ON attempt.released_snapshot_id = snapshot.snapshot_id
      AND attempt.release_request_id = snapshot.release_request_id
      AND attempt.requested_by_app_user_id =
        snapshot.created_by_app_user_id
      AND attempt.project_id = snapshot.project_id
      AND attempt.capability_id = 'release_management_reports'
      AND attempt.report_id = snapshot.report_id
      AND attempt.report_version = snapshot.report_version
      AND attempt.query_fingerprint = snapshot.query_fingerprint
      AND attempt.release_lineage_id = snapshot.release_lineage_id
      AND attempt.result_status IN ('approved_baseline', 'approved')
      AND attempt.reason_codes = '[]'::jsonb
      AND attempt.reporting_time_zone = snapshot.reporting_time_zone
      AND attempt.data_cutoff_utc = snapshot.data_cutoff_utc
      AND attempt.source_change_sequence = snapshot.source_change_sequence
      AND attempt.compared_snapshot_id IS NOT DISTINCT FROM
        snapshot.previous_snapshot_id
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
    JOIN app_private.management_report_release_request_claims AS claim
      ON claim.release_request_id = attempt.release_request_id
      AND claim.release_family_id =
        'follow_up_consent_ratio_management_report_snapshot_release'
    WHERE snapshot.project_id = requested_project_id
      AND snapshot.report_id =
        'contact_target_follow_up_consent_ratio_two_periods'
      AND snapshot.report_version = 1
      AND snapshot.release_lineage_id =
        'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
      AND snapshot.query_fingerprint =
        'management-report:contact_target_follow_up_consent_ratio_two_periods:v1'
    ORDER BY
      snapshot.data_cutoff_utc DESC,
      snapshot.released_at_utc DESC,
      snapshot.snapshot_id DESC
    LIMIT 20
  ) AS directory_row;

  directory_access_event_id = gen_random_uuid();
  INSERT INTO
    app_private.management_follow_up_consent_snapshot_directory_access_events (
      access_event_id,
      requested_by_app_user_id,
      organization_workspace_id,
      organization_membership_id,
      project_membership_id,
      capability_grant_id,
      capability_id,
      authorization_reference_at_utc,
      project_id,
      accessed_at_utc,
      result_status,
      returned_snapshot_count
    ) VALUES (
      directory_access_event_id,
      requested_app_user_id,
      (authorization_evidence->>'organization_workspace_id')::uuid,
      (authorization_evidence->>'organization_membership_id')::uuid,
      (authorization_evidence->>'project_membership_id')::uuid,
      (authorization_evidence->>'capability_grant_id')::uuid,
      authorization_evidence->>'capability_id',
      authorization_reference_at_utc_value,
      requested_project_id,
      authorization_reference_at_utc_value,
      'completed',
      returned_snapshot_count_value
    );

  RETURN jsonb_build_object(
    'access_contract_id',
      'authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1',
    'access_event_id', directory_access_event_id,
    'project_id', requested_project_id,
    'snapshots', snapshot_directory
  );
END
$function$;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(class_row.relowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_class AS class_row
  WHERE class_row.oid = 'app_private.management_report_snapshots'::regclass;

  EXECUTE format(
    'ALTER TABLE app_private.management_follow_up_consent_snapshot_directory_access_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.validate_management_follow_up_consent_snapshot_directory_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_follow_up_consent_snapshot_directory_v1(),
  app_private.list_authorized_management_follow_up_consent_snapshots_v1(
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
    tongxingzhe_management_report_snapshot_lifecycle_writer,
    tongxingzhe_management_follow_up_consent_config_writer,
    tongxingzhe_management_follow_up_consent_ratio_reader,
    tongxingzhe_management_consent_ratio_snapshot_release_writer;

COMMENT ON TABLE
  app_private.management_follow_up_consent_snapshot_directory_access_events
IS 'Immutable minimal audit for one authorized follow-up consent-ratio snapshot directory read; it stores no snapshot identifiers, report metadata, report values, source, contributor, target, contact or PII.';

COMMENT ON FUNCTION
  app_private.list_authorized_management_follow_up_consent_snapshots_v1(
    uuid,
    uuid
  )
IS 'Reauthorizes and lists at most twenty trusted follow-up consent-ratio snapshot metadata records while committing one value-free directory audit.';
