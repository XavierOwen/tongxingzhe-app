-- 0052_management_report_snapshot_export.sql
--
-- 固定匿名管理报告 canonical JSON v1 导出。导出能力独立于查看能力，且
-- 每次请求必须同时拥有 view_anonymous_analytics 与
-- export_management_reports。审计只保存内部授权链、快照/合同元数据、
-- 请求时间、结果和事件 ID；不保存受保护报告、格值、贡献者、query 或
-- 位置/PII。runtime 只能调用一个窄 bridge。

ALTER TABLE app_data.management_report_capability_grants
  DROP CONSTRAINT management_report_capability_grants_capability_id_check;

ALTER TABLE app_data.management_report_capability_grants
  ADD CONSTRAINT management_report_capability_grants_capability_id_check
  CHECK (
    capability_id IN (
      'view_anonymous_analytics',
      'release_management_reports',
      'export_management_reports'
    )
  );

CREATE OR REPLACE FUNCTION app_private.resolve_management_report_authorization_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_capability_id text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_record record;
  authorization_workspace_id uuid;
  reference_at_utc timestamp with time zone;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_capability_id IS NULL
    OR requested_capability_id NOT IN (
      'view_anonymous_analytics',
      'release_management_reports',
      'export_management_reports'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report authorization request';
  END IF;

  SELECT project_row.workspace_id INTO authorization_workspace_id
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = requested_project_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  -- Capability and membership mutation triggers use this same lock order.
  -- Holding all locks until the export transaction commits prevents a
  -- revocation from racing between the two capability resolutions.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:' || authorization_workspace_id::text
        || ':' || requested_app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'project-membership:' || requested_project_id::text
        || ':' || requested_app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'management-report-capability:' || requested_project_id::text
        || ':' || requested_app_user_id::text
        || ':' || requested_capability_id,
      0
    )
  );

  reference_at_utc = clock_timestamp();

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
    AND workspace_row.workspace_kind = 'organization'
    AND workspace_row.deleted_at IS NULL
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
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  RETURN jsonb_build_object(
    'authorization_contract_id',
      'management_report_authorization_v1',
    'app_user_id', requested_app_user_id,
    'organization_workspace_id', authorization_record.workspace_id,
    'project_id', requested_project_id,
    'organization_membership_id',
      authorization_record.organization_membership_id,
    'project_membership_id', authorization_record.project_membership_id,
    'capability_grant_id', authorization_record.capability_grant_id,
    'capability_id', requested_capability_id,
    'capability_active_from_utc', to_char(
      authorization_record.capability_active_from_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'capability_inactive_from_utc', CASE
      WHEN authorization_record.capability_inactive_from_utc IS NULL
        THEN NULL
      ELSE to_char(
        authorization_record.capability_inactive_from_utc
          AT TIME ZONE 'UTC',
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

CREATE TABLE app_private.management_report_snapshot_export_events (
  export_event_id uuid PRIMARY KEY,
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
  view_capability_grant_id uuid NOT NULL
    REFERENCES app_data.management_report_capability_grants (
      capability_grant_id
    ),
  export_capability_grant_id uuid NOT NULL
    REFERENCES app_data.management_report_capability_grants (
      capability_grant_id
    ),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  requested_snapshot_id uuid NOT NULL,
  resolved_snapshot_id uuid NULL
    REFERENCES app_private.management_report_snapshots (snapshot_id),
  export_access_contract_id text NOT NULL CHECK (
    export_access_contract_id =
      'authorized_management_report_snapshot_export_v1'
  ),
  export_contract_id text NOT NULL CHECK (
    export_contract_id = 'management_report_snapshot_export_v1'
  ),
  export_version integer NOT NULL CHECK (export_version = 1),
  requested_at_utc timestamp with time zone NOT NULL,
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
  CHECK (isfinite(requested_at_utc)),
  CHECK (
    (
      result_status = 'completed'
      AND reason_code IS NULL
      AND resolved_snapshot_id = requested_snapshot_id
    )
    OR (
      result_status = 'not_found'
      AND reason_code = 'snapshot_not_available'
      AND resolved_snapshot_id IS NULL
    )
    OR (
      result_status = 'untrusted_provenance'
      AND reason_code = 'snapshot_provenance_untrusted'
      AND resolved_snapshot_id = requested_snapshot_id
    )
  )
);

CREATE INDEX management_report_snapshot_export_events_project_idx
ON app_private.management_report_snapshot_export_events (
  project_id,
  requested_at_utc DESC,
  export_event_id DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_snapshot_export_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER management_report_snapshot_export_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_report_snapshot_export_events
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_management_report_history_mutation();

CREATE FUNCTION
  app_private.validate_management_report_snapshot_export_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  has_trusted_provenance boolean;
BEGIN
  -- The two capability grants must belong to the same active authorization
  -- chain at the post-lock request time. This is intentionally independent
  -- from the result status: a failed snapshot lookup still records an
  -- authorized attempt.
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
    JOIN app_data.management_report_capability_grants AS view_grant
      ON view_grant.project_membership_id =
        project_membership.project_membership_id
    JOIN app_data.management_report_capability_grants AS export_grant
      ON export_grant.project_membership_id =
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
      AND view_grant.capability_grant_id = NEW.view_capability_grant_id
      AND view_grant.capability_id = 'view_anonymous_analytics'
      AND export_grant.capability_grant_id = NEW.export_capability_grant_id
      AND export_grant.capability_id = 'export_management_reports'
      AND tstzrange(
        organization_membership.active_from_utc,
        organization_membership.inactive_from_utc,
        '[)'
      ) @> NEW.requested_at_utc
      AND tstzrange(
        project_membership.active_from_utc,
        project_membership.inactive_from_utc,
        '[)'
      ) @> NEW.requested_at_utc
      AND tstzrange(
        view_grant.active_from_utc,
        view_grant.inactive_from_utc,
        '[)'
      ) @> NEW.requested_at_utc
      AND tstzrange(
        export_grant.active_from_utc,
        export_grant.inactive_from_utc,
        '[)'
      ) @> NEW.requested_at_utc
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot export authorization';
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
        MESSAGE = 'invalid missing management report snapshot export';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = NEW.resolved_snapshot_id
      AND snapshot.snapshot_id = NEW.requested_snapshot_id
      AND snapshot.project_id = NEW.project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot export lineage';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts AS attempt
    JOIN app_private.management_report_snapshots AS snapshot
      ON snapshot.snapshot_id = NEW.resolved_snapshot_id
    WHERE attempt.released_snapshot_id = NEW.resolved_snapshot_id
      AND attempt.project_id = NEW.project_id
      AND attempt.report_id = snapshot.report_id
      AND attempt.report_version = snapshot.report_version
      AND attempt.query_fingerprint = snapshot.query_fingerprint
      AND attempt.result_status IN ('approved_baseline', 'approved')
  ) INTO has_trusted_provenance;

  IF (NEW.result_status = 'completed') <> has_trusted_provenance THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report snapshot export provenance';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_report_snapshot_export_events_validate_insert
BEFORE INSERT
ON app_private.management_report_snapshot_export_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_snapshot_export_insert_v1();

CREATE FUNCTION app_private.export_authorized_management_report_snapshot_v1(
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
  view_authorization_evidence jsonb;
  export_authorization_evidence jsonb;
  export_event_id_value uuid;
  requested_at_utc_value timestamp with time zone;
  result_status_value text;
  reason_code_value text;
  has_trusted_provenance boolean;
  export_document_value jsonb;
  export_result jsonb;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_snapshot_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid authorized management report snapshot export request';
  END IF;

  -- Resolve both capabilities in this transaction. The resolver's advisory
  -- locks remain held until the event and (on success) response document are
  -- committed, so revocation linearizes before or after the whole operation.
  view_authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'view_anonymous_analytics'
    );
  export_authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      requested_app_user_id,
      requested_project_id,
      'export_management_reports'
    );
  requested_at_utc_value = GREATEST(
    (view_authorization_evidence->>'reference_at_utc')::timestamptz,
    (export_authorization_evidence->>'reference_at_utc')::timestamptz
  );

  SELECT snapshot.* INTO stored_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = requested_snapshot_id
    AND snapshot.project_id = requested_project_id;

  IF NOT FOUND THEN
    result_status_value = 'not_found';
    reason_code_value = 'snapshot_not_available';
  ELSE
    IF stored_snapshot.report_id <> 'contact_sessions_by_channel_two_periods'
      OR stored_snapshot.report_version <> 1
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'unsupported management report snapshot export contract';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM app_private.management_report_release_v2_attempts AS attempt
      JOIN app_private.management_report_snapshots AS snapshot
        ON snapshot.snapshot_id = stored_snapshot.snapshot_id
      WHERE attempt.released_snapshot_id = stored_snapshot.snapshot_id
        AND attempt.project_id = stored_snapshot.project_id
        AND attempt.report_id = snapshot.report_id
        AND attempt.report_version = snapshot.report_version
        AND attempt.query_fingerprint = snapshot.query_fingerprint
        AND attempt.result_status IN ('approved_baseline', 'approved')
    ) INTO has_trusted_provenance;

    IF has_trusted_provenance THEN
      result_status_value = 'completed';
    ELSE
      result_status_value = 'untrusted_provenance';
      reason_code_value = 'snapshot_provenance_untrusted';
    END IF;
  END IF;

  export_event_id_value = gen_random_uuid();

  INSERT INTO app_private.management_report_snapshot_export_events (
    export_event_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    view_capability_grant_id,
    export_capability_grant_id,
    project_id,
    requested_snapshot_id,
    resolved_snapshot_id,
    export_access_contract_id,
    export_contract_id,
    export_version,
    requested_at_utc,
    result_status,
    reason_code
  ) VALUES (
    export_event_id_value,
    requested_app_user_id,
    (view_authorization_evidence->>'organization_workspace_id')::uuid,
    (view_authorization_evidence->>'organization_membership_id')::uuid,
    (view_authorization_evidence->>'project_membership_id')::uuid,
    (view_authorization_evidence->>'capability_grant_id')::uuid,
    (export_authorization_evidence->>'capability_grant_id')::uuid,
    requested_project_id,
    requested_snapshot_id,
    CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.snapshot_id
    END,
    'authorized_management_report_snapshot_export_v1',
    'management_report_snapshot_export_v1',
    1,
    requested_at_utc_value,
    result_status_value,
    reason_code_value
  );

  export_result = jsonb_build_object(
    'export_access_contract_id',
      'authorized_management_report_snapshot_export_v1',
    'export_event_id', export_event_id_value,
    'requested_snapshot_id', requested_snapshot_id,
    'resolved_snapshot_id', CASE
      WHEN result_status_value = 'not_found' THEN NULL
      ELSE stored_snapshot.snapshot_id
    END,
    'result_status', result_status_value,
    'reason_code', reason_code_value
  );

  IF result_status_value = 'completed' THEN
    export_document_value = jsonb_build_object(
      'export_contract_id', 'management_report_snapshot_export_v1',
      'snapshot_id', stored_snapshot.snapshot_id,
      'released_at_utc', to_char(
        stored_snapshot.released_at_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'report', stored_snapshot.protected_report
    );
    export_result = export_result || jsonb_build_object(
      'export_document', export_document_value
    );
  END IF;

  RETURN export_result;
END
$function$;

CREATE FUNCTION app_data.export_authorized_management_report_snapshot_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_snapshot_id uuid
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
    OR requested_snapshot_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid runtime management report snapshot export request';
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
      MESSAGE = 'management report snapshot export forbidden';
  END IF;

  RETURN app_private.export_authorized_management_report_snapshot_v1(
    resolved_app_user_id,
    requested_project_id,
    requested_snapshot_id
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_report_snapshot_export_insert_v1(),
  app_private.export_authorized_management_report_snapshot_v1(
    uuid,
    uuid,
    uuid
  )
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.export_authorized_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.export_authorized_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_private.management_report_snapshot_export_events
IS 'Immutable minimal audit for authorized fixed JSON snapshot export attempts; never stores report values, query details, contributors, location, or PII.';

COMMENT ON FUNCTION
  app_private.export_authorized_management_report_snapshot_v1(uuid, uuid, uuid)
IS 'Requires view_anonymous_analytics and export_management_reports, emits one fixed protected snapshot JSON document, and records a value-free export event.';

COMMENT ON FUNCTION
  app_data.export_authorized_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
IS 'Maps one Backend-verified existing identity and performs one authorized management report snapshot export without granting runtime access to app_private.';

COMMENT ON TABLE app_data.management_report_capability_grants
IS 'Separate project grants for viewing analytics, exporting fixed reports, or releasing reports.';
