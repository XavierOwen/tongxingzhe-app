-- 0032_authorized_management_report_snapshot_read.sql
--
-- 在同一私有事务中确认查看能力、读取一份可信的受保护快照，并追加不含
-- 报告格值的访问审计。当前仍不向 runtime 或 HTTP 开放。

CREATE TABLE app_private.management_report_snapshot_access_events (
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
  report_id text NULL,
  report_version integer NULL CHECK (
    report_version IS NULL OR report_version > 0
  ),
  query_fingerprint text NULL,
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
  CHECK (authorization_reference_at_utc = accessed_at_utc),
  CHECK (
    (
      result_status = 'completed'
      AND reason_code IS NULL
      AND resolved_snapshot_id = requested_snapshot_id
      AND report_id IS NOT NULL
      AND report_version IS NOT NULL
      AND query_fingerprint IS NOT NULL
    )
    OR (
      result_status = 'not_found'
      AND reason_code = 'snapshot_not_available'
      AND resolved_snapshot_id IS NULL
      AND report_id IS NULL
      AND report_version IS NULL
      AND query_fingerprint IS NULL
    )
    OR (
      result_status = 'untrusted_provenance'
      AND reason_code = 'snapshot_provenance_untrusted'
      AND resolved_snapshot_id = requested_snapshot_id
      AND report_id IS NOT NULL
      AND report_version IS NOT NULL
      AND query_fingerprint IS NOT NULL
    )
  )
);

CREATE INDEX management_report_snapshot_access_events_project_idx
ON app_private.management_report_snapshot_access_events (
  project_id,
  accessed_at_utc DESC,
  access_event_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_snapshot_access_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER management_report_snapshot_access_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_snapshot_access_events
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.validate_management_report_snapshot_access_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  has_trusted_provenance boolean;
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
      MESSAGE = 'invalid management report snapshot access authorization';
  END IF;

  IF NEW.result_status = 'not_found' THEN
    IF EXISTS (
      SELECT 1
      FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = NEW.requested_snapshot_id
        AND snapshot.project_id = NEW.project_id
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid missing management report snapshot access';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = NEW.resolved_snapshot_id
      AND snapshot.snapshot_id = NEW.requested_snapshot_id
      AND snapshot.project_id = NEW.project_id
      AND snapshot.report_id = NEW.report_id
      AND snapshot.report_version = NEW.report_version
      AND snapshot.query_fingerprint = NEW.query_fingerprint
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot access lineage';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts AS attempt
    WHERE attempt.released_snapshot_id = NEW.resolved_snapshot_id
      AND attempt.project_id = NEW.project_id
      AND attempt.report_id = NEW.report_id
      AND attempt.report_version = NEW.report_version
      AND attempt.query_fingerprint = NEW.query_fingerprint
      AND attempt.result_status IN ('approved_baseline', 'approved')
  ) INTO has_trusted_provenance;

  IF (NEW.result_status = 'completed') <> has_trusted_provenance THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot access provenance';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_snapshot_access_events_validate_insert
BEFORE INSERT
ON app_private.management_report_snapshot_access_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_snapshot_access_insert_v1();

CREATE FUNCTION app_private.read_authorized_management_report_snapshot_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_snapshot_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  stored_snapshot app_private.management_report_snapshots%ROWTYPE;
  authorization_evidence jsonb;
  access_event_id_value uuid;
  authorization_reference_at_utc_value timestamp with time zone;
  result_status_value text;
  reason_code_value text;
  has_trusted_provenance boolean;
  access_result jsonb;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_snapshot_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid authorized management report snapshot request';
  END IF;

  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'view_anonymous_analytics'
    );
  authorization_reference_at_utc_value =
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT snapshot.* INTO stored_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_snapshot_id
    AND snapshot.project_id = requested_project_id;

  IF NOT FOUND THEN
    result_status_value = 'not_found';
    reason_code_value = 'snapshot_not_available';
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM app_private.management_report_release_v2_attempts AS attempt
      WHERE attempt.released_snapshot_id = stored_snapshot.snapshot_id
        AND attempt.project_id = stored_snapshot.project_id
        AND attempt.report_id = stored_snapshot.report_id
        AND attempt.report_version = stored_snapshot.report_version
        AND attempt.query_fingerprint = stored_snapshot.query_fingerprint
        AND attempt.result_status IN ('approved_baseline', 'approved')
    ) INTO has_trusted_provenance;

    IF has_trusted_provenance THEN
      result_status_value = 'completed';
    ELSE
      result_status_value = 'untrusted_provenance';
      reason_code_value = 'snapshot_provenance_untrusted';
    END IF;
  END IF;

  access_event_id_value = gen_random_uuid();

  INSERT INTO app_private.management_report_snapshot_access_events (
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
    report_id,
    report_version,
    query_fingerprint,
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
    authorization_reference_at_utc_value,
    result_status_value,
    reason_code_value
  );

  access_result = jsonb_build_object(
    'access_contract_id',
      'authorized_management_report_snapshot_read_v1',
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

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_report_snapshot_access_insert_v1(),
  app_private.read_authorized_management_report_snapshot_v1(
    uuid,
    uuid,
    uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON TABLE app_private.management_report_snapshot_access_events
IS 'Immutable minimal audit for authorized attempts to read one protected management report snapshot.';

COMMENT ON FUNCTION
  app_private.read_authorized_management_report_snapshot_v1(uuid, uuid, uuid)
IS 'Authorizes one private protected snapshot read, accepts only trusted v2 provenance, and records a value-free access event.';
