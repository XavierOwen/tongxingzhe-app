-- 0031_trusted_management_report_release.sql
--
-- 在同一私有事务中组合管理报告发布能力、可信项目报告时区 revision 和
-- 既有受保护快照发布。调用方不能提交时区、数据截止时间或授权证据。

CREATE TABLE app_private.management_report_release_v2_attempts (
  release_request_id uuid PRIMARY KEY,
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
  reporting_time_zone_version_number integer NOT NULL
    CHECK (reporting_time_zone_version_number > 0),
  reporting_time_zone text NOT NULL,
  reporting_time_zone_effective_from_utc
    timestamp with time zone NOT NULL,
  data_cutoff_utc timestamp with time zone NOT NULL,
  release_lineage_id text NOT NULL,
  report_id text NOT NULL,
  report_version integer NOT NULL CHECK (report_version > 0),
  query_fingerprint text NOT NULL,
  compared_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  released_snapshot_id uuid NULL UNIQUE
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  delegated_release_request_id uuid NULL UNIQUE
    REFERENCES app_private.management_report_release_attempts (
      release_request_id
    ),
  result_status text NOT NULL CHECK (
    result_status IN ('approved_baseline', 'approved', 'blocked')
  ),
  reason_codes jsonb NOT NULL CHECK (jsonb_typeof(reason_codes) = 'array'),
  result_document jsonb NOT NULL
    CHECK (jsonb_typeof(result_document) = 'object'),
  FOREIGN KEY (
    project_id,
    reporting_time_zone_version_number
  ) REFERENCES app_private.project_reporting_time_zone_versions (
    project_id,
    version_number
  ),
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(reporting_time_zone_effective_from_utc)),
  CHECK (isfinite(data_cutoff_utc)),
  CHECK (authorization_reference_at_utc = data_cutoff_utc),
  CHECK (reporting_time_zone_effective_from_utc <= data_cutoff_utc),
  CHECK (
    (
      delegated_release_request_id = release_request_id
      AND (
        (
          result_status = 'approved_baseline'
          AND compared_snapshot_id IS NULL
          AND released_snapshot_id IS NOT NULL
          AND reason_codes = '[]'::jsonb
        )
        OR (
          result_status = 'approved'
          AND compared_snapshot_id IS NOT NULL
          AND released_snapshot_id IS NOT NULL
          AND reason_codes = '[]'::jsonb
        )
        OR (
          result_status = 'blocked'
          AND compared_snapshot_id IS NOT NULL
          AND released_snapshot_id IS NULL
          AND jsonb_array_length(reason_codes) > 0
        )
      )
    )
    OR (
      delegated_release_request_id IS NULL
      AND result_status = 'blocked'
      AND compared_snapshot_id IS NOT NULL
      AND released_snapshot_id IS NULL
      AND jsonb_array_length(reason_codes) = 1
      AND reason_codes->>0 IN (
        'release_lineage_missing_v2_provenance',
        'release_time_zone_revision_changed',
        'release_lineage_context_changed'
      )
    )
  )
);

CREATE INDEX management_report_release_v2_attempts_lineage_idx
ON app_private.management_report_release_v2_attempts (
  project_id,
  release_lineage_id,
  data_cutoff_utc DESC,
  release_request_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_release_v2_attempts
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER management_report_release_v2_attempts_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_release_v2_attempts
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.validate_management_report_release_v2_attempt_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  delegated_attempt app_private.management_report_release_attempts%ROWTYPE;
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
      MESSAGE = 'invalid trusted report release authorization lineage';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.project_reporting_time_zone_versions AS version_row
    WHERE version_row.project_id = NEW.project_id
      AND version_row.version_number =
        NEW.reporting_time_zone_version_number
      AND version_row.reporting_time_zone = NEW.reporting_time_zone
      AND version_row.effective_from_utc =
        NEW.reporting_time_zone_effective_from_utc
      AND NOT EXISTS (
        SELECT 1
        FROM app_private.project_reporting_time_zone_versions AS later_version
        WHERE later_version.project_id = NEW.project_id
          AND later_version.effective_from_utc <= NEW.data_cutoff_utc
          AND (
            later_version.effective_from_utc > version_row.effective_from_utc
            OR (
              later_version.effective_from_utc =
                version_row.effective_from_utc
              AND later_version.version_number > version_row.version_number
            )
          )
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid trusted report release time zone lineage';
  END IF;

  IF NEW.compared_snapshot_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = NEW.compared_snapshot_id
      AND snapshot.project_id = NEW.project_id
      AND snapshot.release_lineage_id = NEW.release_lineage_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid trusted report release comparison lineage';
  END IF;

  IF NEW.delegated_release_request_id IS NOT NULL THEN
    SELECT attempt.* INTO STRICT delegated_attempt
    FROM app_private.management_report_release_attempts AS attempt
    WHERE attempt.release_request_id = NEW.delegated_release_request_id;

    IF delegated_attempt.requested_by_app_user_id <>
        NEW.requested_by_app_user_id
      OR delegated_attempt.project_id <> NEW.project_id
      OR delegated_attempt.release_lineage_id <> NEW.release_lineage_id
      OR delegated_attempt.report_id <> NEW.report_id
      OR delegated_attempt.report_version <> NEW.report_version
      OR delegated_attempt.query_fingerprint <> NEW.query_fingerprint
      OR delegated_attempt.reporting_time_zone <> NEW.reporting_time_zone
      OR delegated_attempt.data_cutoff_utc <> NEW.data_cutoff_utc
      OR delegated_attempt.compared_snapshot_id IS DISTINCT FROM
        NEW.compared_snapshot_id
      OR delegated_attempt.released_snapshot_id IS DISTINCT FROM
        NEW.released_snapshot_id
      OR delegated_attempt.result_status <> NEW.result_status
      OR delegated_attempt.reason_codes <> NEW.reason_codes
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid delegated report release lineage';
    END IF;
  END IF;

  IF NEW.released_snapshot_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = NEW.released_snapshot_id
      AND snapshot.release_request_id = NEW.release_request_id
      AND snapshot.created_by_app_user_id =
        NEW.requested_by_app_user_id
      AND snapshot.project_id = NEW.project_id
      AND snapshot.release_lineage_id = NEW.release_lineage_id
      AND snapshot.report_id = NEW.report_id
      AND snapshot.report_version = NEW.report_version
      AND snapshot.query_fingerprint = NEW.query_fingerprint
      AND snapshot.reporting_time_zone = NEW.reporting_time_zone
      AND snapshot.data_cutoff_utc = NEW.data_cutoff_utc
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid trusted report release snapshot lineage';
  END IF;

  expected_result_document = jsonb_build_object(
    'release_contract_id',
      'trusted_management_report_snapshot_release_v2',
    'release_request_id', NEW.release_request_id,
    'project_id', NEW.project_id,
    'release_lineage_id', NEW.release_lineage_id,
    'report_id', NEW.report_id,
    'report_version', NEW.report_version,
    'query_fingerprint', NEW.query_fingerprint,
    'reporting_time_zone_version_number',
      NEW.reporting_time_zone_version_number,
    'reporting_time_zone', NEW.reporting_time_zone,
    'data_cutoff_utc', to_char(
      NEW.data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'compared_snapshot_id', NEW.compared_snapshot_id,
    'released_snapshot_id', NEW.released_snapshot_id,
    'result_status', NEW.result_status,
    'reason_codes', NEW.reason_codes
  );

  IF NEW.result_document <> expected_result_document THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid trusted report release result document';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_release_v2_attempts_validate_insert
BEFORE INSERT
ON app_private.management_report_release_v2_attempts
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_release_v2_attempt_insert();

CREATE FUNCTION app_private.release_management_report_snapshot_v2(
  requested_release_request_id uuid,
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_report_id text,
  requested_report_version integer
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  existing_attempt
    app_private.management_report_release_v2_attempts%ROWTYPE;
  previous_snapshot app_private.management_report_snapshots%ROWTYPE;
  previous_v2_attempt
    app_private.management_report_release_v2_attempts%ROWTYPE;
  delegated_attempt app_private.management_report_release_attempts%ROWTYPE;
  time_zone_version
    app_private.project_reporting_time_zone_versions%ROWTYPE;
  authorization_evidence jsonb;
  canonical_request jsonb;
  release_result jsonb;
  release_lineage_id_value text;
  query_fingerprint_value text;
  data_cutoff_utc_value timestamp with time zone;
  compared_snapshot_id_value uuid;
  released_snapshot_id_value uuid;
  delegated_release_request_id_value uuid;
  result_status_value text;
  reason_codes_value jsonb := '[]'::jsonb;
BEGIN
  IF requested_release_request_id IS NULL
    OR requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_report_id IS NULL
    OR requested_report_version IS NULL
    OR requested_report_version <= 0
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid trusted management report release request';
  END IF;

  -- Lock order is authorization, release request, project time zone, then
  -- report lineage. The first resolution acquires the authorization locks;
  -- they remain held until this release transaction finishes.
  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-release-request:'
        || requested_release_request_id::text,
      0
    )
  );

  -- A retry can wait on the request lock long enough for a time-bounded
  -- membership or capability to expire. Recheck before reading or returning
  -- the stored result; a new release receives one more check after later locks.
  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  SELECT attempt.* INTO existing_attempt
  FROM app_private.management_report_release_v2_attempts AS attempt
  WHERE attempt.release_request_id = requested_release_request_id;

  IF FOUND THEN
    IF existing_attempt.requested_by_app_user_id <>
        requested_app_user_id
      OR existing_attempt.project_id <> requested_project_id
      OR existing_attempt.report_id <> requested_report_id
      OR existing_attempt.report_version <> requested_report_version
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'trusted management report release idempotency conflict';
    END IF;

    RETURN existing_attempt.result_document;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_release_attempts AS attempt
    WHERE attempt.release_request_id = requested_release_request_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'trusted release request id was already used by v1';
  END IF;

  -- Serialize with time-zone configuration before choosing the cutoff and
  -- revision. Configuration uses this same transaction lock.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-reporting-time-zone:' || requested_project_id::text,
      0
    )
  );

  canonical_request =
    app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', requested_report_id,
        'report_version', requested_report_version
      )
    );
  query_fingerprint_value = canonical_request->>'query_fingerprint';
  release_lineage_id_value =
    'management-report:' || requested_report_id;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-report-release-lineage:'
        || requested_project_id::text
        || ':' || release_lineage_id_value,
      0
    )
  );

  -- Re-resolve after every lock that can wait. The returned database time is
  -- both the authorization linearization point and the trusted data cutoff.
  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'release_management_reports'
    );
  data_cutoff_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT version_row.* INTO time_zone_version
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.effective_from_utc <= data_cutoff_utc_value
  ORDER BY
    version_row.effective_from_utc DESC,
    version_row.version_number DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'project reporting time zone is not configured';
  END IF;

  SELECT snapshot.* INTO previous_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = requested_project_id
    AND snapshot.release_lineage_id = release_lineage_id_value
  ORDER BY
    snapshot.data_cutoff_utc DESC,
    snapshot.released_at_utc DESC,
    snapshot.snapshot_id DESC
  LIMIT 1;

  IF FOUND THEN
    compared_snapshot_id_value = previous_snapshot.snapshot_id;

    SELECT attempt.* INTO previous_v2_attempt
    FROM app_private.management_report_release_v2_attempts AS attempt
    WHERE attempt.released_snapshot_id = previous_snapshot.snapshot_id;

    IF NOT FOUND THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_lineage_missing_v2_provenance'
      );
    ELSIF previous_v2_attempt.reporting_time_zone_version_number <>
        time_zone_version.version_number
    THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_time_zone_revision_changed'
      );
    ELSIF previous_snapshot.report_id <> requested_report_id
      OR previous_snapshot.report_version <> requested_report_version
      OR previous_snapshot.query_fingerprint <> query_fingerprint_value
      OR previous_snapshot.reporting_time_zone <>
        time_zone_version.reporting_time_zone
      OR previous_v2_attempt.project_id <> requested_project_id
      OR previous_v2_attempt.release_lineage_id <>
        release_lineage_id_value
    THEN
      result_status_value = 'blocked';
      reason_codes_value = jsonb_build_array(
        'release_lineage_context_changed'
      );
    END IF;
  END IF;

  IF result_status_value IS NULL THEN
    PERFORM app_private.release_management_report_snapshot_v1(
      requested_release_request_id,
      requested_app_user_id,
      requested_project_id,
      requested_report_id,
      requested_report_version,
      time_zone_version.reporting_time_zone,
      data_cutoff_utc_value,
      data_cutoff_utc_value
    );

    SELECT attempt.* INTO STRICT delegated_attempt
    FROM app_private.management_report_release_attempts AS attempt
    WHERE attempt.release_request_id = requested_release_request_id;

    delegated_release_request_id_value = requested_release_request_id;
    compared_snapshot_id_value = delegated_attempt.compared_snapshot_id;
    released_snapshot_id_value = delegated_attempt.released_snapshot_id;
    result_status_value = delegated_attempt.result_status;
    reason_codes_value = delegated_attempt.reason_codes;
  END IF;

  release_result = jsonb_build_object(
    'release_contract_id',
      'trusted_management_report_snapshot_release_v2',
    'release_request_id', requested_release_request_id,
    'project_id', requested_project_id,
    'release_lineage_id', release_lineage_id_value,
    'report_id', requested_report_id,
    'report_version', requested_report_version,
    'query_fingerprint', query_fingerprint_value,
    'reporting_time_zone_version_number',
      time_zone_version.version_number,
    'reporting_time_zone', time_zone_version.reporting_time_zone,
    'data_cutoff_utc', to_char(
      data_cutoff_utc_value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'compared_snapshot_id', compared_snapshot_id_value,
    'released_snapshot_id', released_snapshot_id_value,
    'result_status', result_status_value,
    'reason_codes', reason_codes_value
  );

  INSERT INTO app_private.management_report_release_v2_attempts (
    release_request_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    reporting_time_zone_version_number,
    reporting_time_zone,
    reporting_time_zone_effective_from_utc,
    data_cutoff_utc,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    compared_snapshot_id,
    released_snapshot_id,
    delegated_release_request_id,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    requested_release_request_id,
    requested_app_user_id,
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    authorization_evidence->>'capability_id',
    (authorization_evidence->>'reference_at_utc')::timestamptz,
    requested_project_id,
    time_zone_version.version_number,
    time_zone_version.reporting_time_zone,
    time_zone_version.effective_from_utc,
    data_cutoff_utc_value,
    release_lineage_id_value,
    requested_report_id,
    requested_report_version,
    query_fingerprint_value,
    compared_snapshot_id_value,
    released_snapshot_id_value,
    delegated_release_request_id_value,
    result_status_value,
    reason_codes_value,
    release_result
  );

  RETURN release_result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_report_release_v2_attempt_insert(),
  app_private.release_management_report_snapshot_v2(
    uuid,
    uuid,
    uuid,
    text,
    integer
  )
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON TABLE app_private.management_report_release_v2_attempts
IS 'Immutable private evidence that binds a fixed report release attempt to one authorization decision and trusted reporting-time-zone revision.';

COMMENT ON FUNCTION app_private.release_management_report_snapshot_v2(
  uuid,
  uuid,
  uuid,
  text,
  integer
)
IS 'Authorizes a private fixed report release, derives its database cutoff and reporting-time-zone revision, and fails closed across untrusted or changed lineage.';
