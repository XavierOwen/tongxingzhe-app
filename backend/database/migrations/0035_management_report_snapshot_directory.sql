-- 0035_management_report_snapshot_directory.sql
--
-- 在同一私有事务中重新确认查看能力，列出最多二十份可信 v2 管理报告
-- 快照元数据，并记录不含快照标识或报告内容的最小目录访问审计。

CREATE TABLE app_private.management_report_snapshot_directory_access_events (
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

CREATE INDEX management_report_snapshot_directory_access_project_idx
ON app_private.management_report_snapshot_directory_access_events (
  project_id,
  accessed_at_utc DESC,
  access_event_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_snapshot_directory_access_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER management_report_snapshot_directory_access_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_snapshot_directory_access_events
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.validate_management_report_snapshot_directory_access_v1()
RETURNS trigger
LANGUAGE plpgsql
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
      MESSAGE = 'invalid management report snapshot directory authorization';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_snapshot_directory_access_validate
BEFORE INSERT
ON app_private.management_report_snapshot_directory_access_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_snapshot_directory_access_v1();

CREATE FUNCTION app_private.list_authorized_management_report_snapshots_v1(
  requested_app_user_id uuid,
  requested_project_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
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
      MESSAGE = 'invalid management report snapshot directory request';
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
    JOIN app_private.management_report_release_v2_attempts AS attempt
      ON attempt.released_snapshot_id = snapshot.snapshot_id
      AND attempt.project_id = snapshot.project_id
      AND attempt.report_id = snapshot.report_id
      AND attempt.report_version = snapshot.report_version
      AND attempt.query_fingerprint = snapshot.query_fingerprint
      AND attempt.result_status IN ('approved_baseline', 'approved')
    WHERE snapshot.project_id = requested_project_id
    ORDER BY
      snapshot.data_cutoff_utc DESC,
      snapshot.released_at_utc DESC,
      snapshot.snapshot_id DESC
    LIMIT 20
  ) AS directory_row;

  directory_access_event_id = gen_random_uuid();
  INSERT INTO
    app_private.management_report_snapshot_directory_access_events (
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
      'authorized_management_report_snapshot_directory_v1',
    'access_event_id', directory_access_event_id,
    'project_id', requested_project_id,
    'snapshots', snapshot_directory
  );
END
$function$;

CREATE FUNCTION app_data.list_authorized_management_report_snapshots_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR trusted_subject IS NULL
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
    OR requested_project_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid runtime management report snapshot directory request';
  END IF;

  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report snapshot directory access forbidden';
  END IF;

  RETURN app_private.list_authorized_management_report_snapshots_v1(
    resolved_app_user_id,
    requested_project_id
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_report_snapshot_directory_access_v1(),
  app_private.list_authorized_management_report_snapshots_v1(uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.list_authorized_management_report_snapshots_v1(
    text,
    text,
    uuid
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.list_authorized_management_report_snapshots_v1(
    text,
    text,
    uuid
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE
  app_private.management_report_snapshot_directory_access_events
IS 'Immutable minimal audit for one authorized snapshot-directory read; it stores no snapshot identifiers or report metadata.';

COMMENT ON FUNCTION
  app_private.list_authorized_management_report_snapshots_v1(uuid, uuid)
IS 'Reauthorizes and lists at most twenty trusted v2 snapshot metadata records while committing one value-free directory audit.';

COMMENT ON FUNCTION
  app_data.list_authorized_management_report_snapshots_v1(text, text, uuid)
IS 'Maps one verified existing identity and performs one bounded authorized snapshot-directory read without exposing app_private.';
