-- 0029_project_reporting_time_zone.sql
--
-- 保存项目报告 IANA 时区的不可变版本。当前切片只提供私有配置与解析
-- 合同；成员授权和无时区参数的报告发布入口仍属于后续工作。

CREATE TABLE app_private.project_reporting_time_zone_versions (
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  version_number integer NOT NULL CHECK (version_number > 0),
  expected_version integer NOT NULL CHECK (expected_version >= 0),
  change_request_id uuid NOT NULL UNIQUE,
  requested_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id),
  reporting_time_zone text NOT NULL CHECK (
    length(btrim(reporting_time_zone)) BETWEEN 1 AND 100
  ),
  period_boundary_id text NOT NULL CHECK (
    period_boundary_id = 'iso_week_monday_v1'
  ),
  effective_from_utc timestamp with time zone NOT NULL,
  requested_at_utc timestamp with time zone NOT NULL,
  PRIMARY KEY (project_id, version_number),
  UNIQUE (project_id, effective_from_utc),
  CHECK (isfinite(effective_from_utc)),
  CHECK (isfinite(requested_at_utc)),
  CHECK (requested_at_utc <= effective_from_utc)
);

CREATE INDEX project_reporting_time_zone_versions_effective
ON app_private.project_reporting_time_zone_versions (
  project_id,
  effective_from_utc DESC,
  version_number DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.project_reporting_time_zone_versions
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.reject_project_reporting_time_zone_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'project reporting time zone history is immutable';
END
$function$;

CREATE TRIGGER project_reporting_time_zone_versions_immutable
BEFORE UPDATE OR DELETE
ON app_private.project_reporting_time_zone_versions
FOR EACH ROW
EXECUTE FUNCTION
  app_private.reject_project_reporting_time_zone_mutation_v1();

CREATE FUNCTION app_private.project_reporting_time_zone_version_document_v1(
  requested_project_id uuid,
  requested_version_number integer
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $function$
  SELECT jsonb_build_object(
    'configuration_contract_id',
      'project_reporting_time_zone_configuration_v1',
    'change_request_id', version_row.change_request_id,
    'project_id', version_row.project_id,
    'version_number', version_row.version_number,
    'expected_version', version_row.expected_version,
    'requested_by_app_user_id', version_row.requested_by_app_user_id,
    'reporting_time_zone', version_row.reporting_time_zone,
    'period_boundary_id', version_row.period_boundary_id,
    'effective_from_utc', to_char(
      version_row.effective_from_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'requested_at_utc', to_char(
      version_row.requested_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  )
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.version_number = requested_version_number;
$function$;

CREATE FUNCTION app_private.read_project_reporting_time_zone_v1(
  requested_project_id uuid,
  reference_at_utc timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  current_version_number integer;
  pending_version_number integer;
BEGIN
  IF requested_project_id IS NULL
    OR reference_at_utc IS NULL
    OR NOT isfinite(reference_at_utc)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project reporting time zone read';
  END IF;

  SELECT version_row.version_number INTO current_version_number
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.effective_from_utc <= reference_at_utc
  ORDER BY
    version_row.effective_from_utc DESC,
    version_row.version_number DESC
  LIMIT 1;

  SELECT version_row.version_number INTO pending_version_number
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.effective_from_utc > reference_at_utc
  ORDER BY
    version_row.effective_from_utc,
    version_row.version_number
  LIMIT 1;

  IF current_version_number IS NULL AND pending_version_number IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'project reporting time zone is not configured';
  END IF;

  RETURN jsonb_build_object(
    'state_contract_id', 'project_reporting_time_zone_state_v1',
    'project_id', requested_project_id,
    'reference_at_utc', to_char(
      reference_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'current', app_private.project_reporting_time_zone_version_document_v1(
      requested_project_id,
      current_version_number
    ),
    'pending', app_private.project_reporting_time_zone_version_document_v1(
      requested_project_id,
      pending_version_number
    )
  );
END
$function$;

CREATE FUNCTION app_private.project_reporting_time_zone_change_boundary_v1(
  requested_at_utc timestamp with time zone,
  current_reporting_time_zone text
)
RETURNS timestamp with time zone
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
BEGIN
  RETURN (
    (
      date_trunc(
        'week',
        requested_at_utc AT TIME ZONE current_reporting_time_zone
      ) + interval '7 days'
    ) AT TIME ZONE current_reporting_time_zone
  );
END
$function$;

CREATE FUNCTION app_private.validate_project_reporting_time_zone_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  previous_version
    app_private.project_reporting_time_zone_versions%ROWTYPE;
  expected_effective_from_utc timestamp with time zone;
BEGIN
  IF app_private.management_report_time_zone_valid_v1(
      NEW.reporting_time_zone
    ) IS NOT TRUE
    OR NEW.period_boundary_id <> 'iso_week_monday_v1'
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.projects AS project_row
      JOIN app_data.workspaces AS workspace_row
        ON workspace_row.workspace_id = project_row.workspace_id
      WHERE project_row.project_id = NEW.project_id
        AND project_row.status = 'active'
        AND workspace_row.workspace_kind = 'organization'
        AND workspace_row.deleted_at IS NULL
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.app_users AS app_user
      WHERE app_user.app_user_id = NEW.requested_by_app_user_id
        AND app_user.status = 'active'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project reporting time zone version';
  END IF;

  IF NEW.version_number = 1 THEN
    IF NEW.expected_version <> 0
      OR NEW.effective_from_utc <> NEW.requested_at_utc
      OR EXISTS (
        SELECT 1
        FROM app_private.project_reporting_time_zone_versions AS version_row
        WHERE version_row.project_id = NEW.project_id
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid initial project reporting time zone version';
    END IF;
    RETURN NEW;
  END IF;

  SELECT version_row.* INTO previous_version
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = NEW.project_id
    AND version_row.version_number = NEW.version_number - 1;

  IF NOT FOUND
    OR NEW.expected_version <> previous_version.version_number
    OR NEW.requested_at_utc < previous_version.requested_at_utc
    OR NEW.requested_at_utc < previous_version.effective_from_utc
    OR NEW.reporting_time_zone = previous_version.reporting_time_zone
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project reporting time zone version chain';
  END IF;

  expected_effective_from_utc =
    app_private.project_reporting_time_zone_change_boundary_v1(
      NEW.requested_at_utc,
      previous_version.reporting_time_zone
    );
  IF NEW.effective_from_utc <> expected_effective_from_utc
    OR NEW.effective_from_utc <= previous_version.effective_from_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project reporting time zone effective boundary';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER project_reporting_time_zone_versions_validate_insert
BEFORE INSERT
ON app_private.project_reporting_time_zone_versions
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_project_reporting_time_zone_insert_v1();

CREATE FUNCTION app_private.configure_project_reporting_time_zone_v1(
  requested_change_request_id uuid,
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_expected_version integer,
  requested_reporting_time_zone text,
  requested_at_utc timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  normalized_time_zone text := btrim(requested_reporting_time_zone);
  replay_version
    app_private.project_reporting_time_zone_versions%ROWTYPE;
  latest_version
    app_private.project_reporting_time_zone_versions%ROWTYPE;
  next_version_number integer;
  effective_from_utc_value timestamp with time zone;
BEGIN
  IF requested_change_request_id IS NULL
    OR requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_expected_version IS NULL
    OR requested_expected_version < 0
    OR requested_reporting_time_zone IS NULL
    OR requested_at_utc IS NULL
    OR NOT isfinite(requested_at_utc)
    OR app_private.management_report_time_zone_valid_v1(
      normalized_time_zone
    ) IS NOT TRUE
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project reporting time zone request';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-reporting-time-zone-change-request:'
        || requested_change_request_id::text,
      0
    )
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-reporting-time-zone:' || requested_project_id::text,
      0
    )
  );

  SELECT version_row.* INTO replay_version
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.change_request_id = requested_change_request_id;

  IF FOUND THEN
    IF replay_version.requested_by_app_user_id <> requested_app_user_id
      OR replay_version.project_id <> requested_project_id
      OR replay_version.expected_version <> requested_expected_version
      OR replay_version.reporting_time_zone <> normalized_time_zone
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'project reporting time zone idempotency conflict';
    END IF;

    RETURN app_private.project_reporting_time_zone_version_document_v1(
      replay_version.project_id,
      replay_version.version_number
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.projects AS project_row
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id = project_row.workspace_id
    WHERE project_row.project_id = requested_project_id
      AND project_row.status = 'active'
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = requested_app_user_id
      AND app_user.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'project reporting time zone scope is forbidden';
  END IF;

  SELECT version_row.* INTO latest_version
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = requested_project_id
  ORDER BY version_row.version_number DESC
  LIMIT 1;

  IF NOT FOUND THEN
    IF requested_expected_version <> 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'project reporting time zone version conflict';
    END IF;
    next_version_number = 1;
    effective_from_utc_value = requested_at_utc;
  ELSE
    IF latest_version.version_number <> requested_expected_version THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'project reporting time zone version conflict';
    END IF;
    IF requested_at_utc < latest_version.requested_at_utc THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'project reporting time zone request is out of order';
    END IF;
    IF latest_version.effective_from_utc > requested_at_utc THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'project reporting time zone already has a pending change';
    END IF;
    IF latest_version.reporting_time_zone = normalized_time_zone THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'project reporting time zone is unchanged';
    END IF;

    next_version_number = latest_version.version_number + 1;
    effective_from_utc_value =
      app_private.project_reporting_time_zone_change_boundary_v1(
        requested_at_utc,
        latest_version.reporting_time_zone
      );
  END IF;

  INSERT INTO app_private.project_reporting_time_zone_versions (
    project_id,
    version_number,
    expected_version,
    change_request_id,
    requested_by_app_user_id,
    reporting_time_zone,
    period_boundary_id,
    effective_from_utc,
    requested_at_utc
  ) VALUES (
    requested_project_id,
    next_version_number,
    requested_expected_version,
    requested_change_request_id,
    requested_app_user_id,
    normalized_time_zone,
    'iso_week_monday_v1',
    effective_from_utc_value,
    requested_at_utc
  );

  RETURN app_private.project_reporting_time_zone_version_document_v1(
    requested_project_id,
    next_version_number
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.reject_project_reporting_time_zone_mutation_v1(),
  app_private.project_reporting_time_zone_version_document_v1(uuid, integer),
  app_private.read_project_reporting_time_zone_v1(
    uuid,
    timestamp with time zone
  ),
  app_private.project_reporting_time_zone_change_boundary_v1(
    timestamp with time zone,
    text
  ),
  app_private.validate_project_reporting_time_zone_insert_v1(),
  app_private.configure_project_reporting_time_zone_v1(
    uuid,
    uuid,
    uuid,
    integer,
    text,
    timestamp with time zone
  )
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON TABLE app_private.project_reporting_time_zone_versions
IS 'Append-only trusted IANA time zone versions for organization project management reports.';

COMMENT ON FUNCTION app_private.configure_project_reporting_time_zone_v1(
  uuid,
  uuid,
  uuid,
  integer,
  text,
  timestamp with time zone
)
IS 'Appends a private reporting time zone version without performing membership authorization.';
