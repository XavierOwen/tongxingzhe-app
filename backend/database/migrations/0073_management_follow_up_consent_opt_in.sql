-- 0073_management_follow_up_consent_opt_in.sql
--
-- Slice 6BO fixes the organization-project opt-in contract for the future
-- follow_up_consent_ratio@1 management metric.  It stores only configuration
-- metadata and authorization provenance.  It does not calculate a ratio,
-- read contact facts, create a report, or add a runtime bridge.

DO $configuration_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname =
      'tongxingzhe_management_follow_up_consent_config_writer'
  ) THEN
    CREATE ROLE tongxingzhe_management_follow_up_consent_config_writer
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$configuration_role$;

ALTER ROLE tongxingzhe_management_follow_up_consent_config_writer
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

CREATE TABLE app_private.management_follow_up_consent_opt_in_versions (
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  metric_id text NOT NULL CHECK (
    metric_id = 'follow_up_consent_ratio@1'
  ),
  version_number integer NOT NULL CHECK (version_number > 0),
  expected_version integer NOT NULL CHECK (expected_version >= 0),
  enabled boolean NOT NULL,
  requested_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  organization_workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  organization_membership_id uuid NOT NULL
    REFERENCES app_data.organization_memberships (
      organization_membership_id
    ) ON DELETE RESTRICT,
  project_membership_id uuid NOT NULL
    REFERENCES app_data.project_memberships (project_membership_id)
    ON DELETE RESTRICT,
  capability_grant_id uuid NOT NULL
    REFERENCES app_data.management_report_capability_grants (
      capability_grant_id
    ) ON DELETE RESTRICT,
  capability_id text NOT NULL CHECK (
    capability_id = 'release_management_reports'
  ),
  authorization_reference_at_utc timestamptz NOT NULL,
  request_id uuid NOT NULL,
  recorded_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (project_id, version_number),
  CHECK (expected_version = version_number - 1),
  CHECK (isfinite(authorization_reference_at_utc)),
  CHECK (isfinite(recorded_at_utc)),
  CHECK (authorization_reference_at_utc <= recorded_at_utc)
);

CREATE UNIQUE INDEX management_follow_up_consent_opt_in_versions_request_idx
ON app_private.management_follow_up_consent_opt_in_versions (request_id);

CREATE INDEX management_follow_up_consent_opt_in_versions_latest_idx
ON app_private.management_follow_up_consent_opt_in_versions (
  project_id,
  version_number DESC
);

ALTER TABLE app_private.management_follow_up_consent_opt_in_versions
  ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_private.management_follow_up_consent_opt_in_versions
  FORCE ROW LEVEL SECURITY;

CREATE POLICY management_follow_up_consent_opt_in_config_writer_scope
ON app_private.management_follow_up_consent_opt_in_versions
FOR ALL
TO tongxingzhe_management_follow_up_consent_config_writer
USING (true)
WITH CHECK (true);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_follow_up_consent_opt_in_versions
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer;

CREATE FUNCTION app_private.reject_management_follow_up_consent_opt_in_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'management follow-up consent opt-in history is immutable';
END
$function$;

CREATE TRIGGER management_follow_up_consent_opt_in_versions_immutable
BEFORE UPDATE OR DELETE
ON app_private.management_follow_up_consent_opt_in_versions
FOR EACH ROW
EXECUTE FUNCTION
  app_private.reject_management_follow_up_consent_opt_in_mutation_v1();

CREATE FUNCTION app_private.validate_management_follow_up_consent_opt_in_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  latest_version_number integer;
BEGIN
  IF NEW.metric_id IS DISTINCT FROM 'follow_up_consent_ratio@1'
    OR NEW.capability_id IS DISTINCT FROM 'release_management_reports'
    OR NEW.version_number <= 0
    OR NEW.expected_version < 0
    OR NEW.expected_version <> NEW.version_number - 1
    OR NEW.request_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent opt-in version';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-follow-up-consent-opt-in:' || NEW.project_id::text,
      0
    )
  );

  IF NOT EXISTS (
    SELECT 1
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
    WHERE app_user.app_user_id = NEW.requested_by_app_user_id
      AND app_user.status = 'active'
      AND workspace_row.workspace_id = NEW.organization_workspace_id
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = NEW.project_id
      AND project_row.status = 'active'
      AND organization_membership.organization_membership_id =
        NEW.organization_membership_id
      AND project_membership.project_membership_id =
        NEW.project_membership_id
      AND capability_grant.capability_grant_id = NEW.capability_grant_id
      AND capability_grant.capability_id = 'release_management_reports'
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
      ERRCODE = '42501',
      MESSAGE = 'management follow-up consent opt-in provenance is forbidden';
  END IF;

  SELECT max(version_row.version_number)
  INTO latest_version_number
  FROM app_private.management_follow_up_consent_opt_in_versions
    AS version_row
  WHERE version_row.project_id = NEW.project_id;

  IF NEW.version_number <> coalesce(latest_version_number, 0) + 1
    OR NEW.expected_version <> coalesce(latest_version_number, 0)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent opt-in version chain';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_follow_up_consent_opt_in_versions_validate
BEFORE INSERT
ON app_private.management_follow_up_consent_opt_in_versions
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_follow_up_consent_opt_in_v1();

-- Project archive/status changes use the same lock as configuration writes.
-- This trigger only serializes a status transition; it does not grant the
-- configuration owner any UPDATE privilege on app_data.projects.
CREATE FUNCTION app_private.lock_management_follow_up_consent_opt_in_project_status_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_actor_id uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    -- Match the resolver's hierarchy order before taking the project-wide
    -- configuration lock. A transaction that changes project status and then
    -- revokes a member cannot otherwise hold these locks in reverse order from
    -- a concurrent configure/read call.
    FOR authorization_actor_id IN
      SELECT DISTINCT organization_membership.app_user_id
      FROM app_data.project_memberships AS project_membership
      JOIN app_data.organization_memberships AS organization_membership
        ON organization_membership.organization_membership_id =
          project_membership.organization_membership_id
      WHERE project_membership.project_id = NEW.project_id
      ORDER BY organization_membership.app_user_id
    LOOP
      PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          'organization-membership:' || NEW.workspace_id::text
            || ':' || authorization_actor_id::text,
          0
        )
      );
      PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          'project-membership:' || NEW.project_id::text
            || ':' || authorization_actor_id::text,
          0
        )
      );
      PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
          'management-report-capability:' || NEW.project_id::text
            || ':' || authorization_actor_id::text
            || ':release_management_reports',
          0
        )
      );
    END LOOP;

    PERFORM pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'management-follow-up-consent-opt-in:' || NEW.project_id::text,
        0
      )
    );
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER management_follow_up_consent_opt_in_project_status_lock
BEFORE UPDATE OF status
ON app_data.projects
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION
  app_private.lock_management_follow_up_consent_opt_in_project_status_v1();

CREATE FUNCTION app_private.management_follow_up_consent_opt_in_document_v1(
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
      'management_follow_up_consent_opt_in_configuration_v1',
    'metric_id', version_row.metric_id,
    'project_id', version_row.project_id,
    'status', CASE
      WHEN version_row.enabled THEN 'enabled'
      ELSE 'not_enabled'
    END,
    'version_number', version_row.version_number,
    'expected_version', version_row.expected_version,
    'enabled', version_row.enabled,
    'recorded_at_utc', to_char(
      version_row.recorded_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  )
  FROM app_private.management_follow_up_consent_opt_in_versions
    AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.version_number = requested_version_number;
$function$;

CREATE FUNCTION app_private.configure_management_follow_up_consent_opt_in_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_metric_id text,
  requested_request_id uuid,
  requested_expected_version integer,
  requested_enabled boolean
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  authorization_evidence jsonb;
  authorization_reference_at_utc timestamptz;
  replay_version
    app_private.management_follow_up_consent_opt_in_versions%ROWTYPE;
  latest_version
    app_private.management_follow_up_consent_opt_in_versions%ROWTYPE;
  next_version_number integer;
BEGIN
  IF trusted_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_metric_id IS DISTINCT FROM 'follow_up_consent_ratio@1'
    OR requested_request_id IS NULL
    OR requested_expected_version IS NULL
    OR requested_expected_version < 0
    OR requested_expected_version > 2147483646
    OR requested_enabled IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent opt-in request';
  END IF;

  -- The resolver takes the organization, project-membership and capability
  -- locks. Every possible wait below is followed by reauthorization.
  authorization_evidence :=
    app_private.resolve_management_report_authorization_v1(
      trusted_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-follow-up-consent-opt-in-request:'
        || requested_request_id::text,
      0
    )
  );

  authorization_evidence :=
    app_private.resolve_management_report_authorization_v1(
      trusted_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-follow-up-consent-opt-in:' || requested_project_id::text,
      0
    )
  );

  authorization_evidence :=
    app_private.resolve_management_report_authorization_v1(
      trusted_app_user_id,
      requested_project_id,
      'release_management_reports'
    );
  authorization_reference_at_utc :=
    (authorization_evidence->>'reference_at_utc')::timestamptz;

  SELECT version_row.*
  INTO replay_version
  FROM app_private.management_follow_up_consent_opt_in_versions
    AS version_row
  WHERE version_row.request_id = requested_request_id;

  IF FOUND THEN
    IF replay_version.project_id <> requested_project_id
      OR replay_version.metric_id <> requested_metric_id
      OR replay_version.requested_by_app_user_id <> trusted_app_user_id
      OR replay_version.capability_id <> 'release_management_reports'
      OR replay_version.expected_version <> requested_expected_version
      OR replay_version.enabled <> requested_enabled
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'management follow-up consent opt-in idempotency conflict';
    END IF;

    RETURN app_private.management_follow_up_consent_opt_in_document_v1(
      replay_version.project_id,
      replay_version.version_number
    );
  END IF;

  SELECT version_row.*
  INTO latest_version
  FROM app_private.management_follow_up_consent_opt_in_versions
    AS version_row
  WHERE version_row.project_id = requested_project_id
  ORDER BY version_row.version_number DESC
  LIMIT 1;

  IF NOT FOUND THEN
    IF requested_expected_version <> 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'management follow-up consent opt-in version conflict';
    END IF;
    next_version_number := 1;
  ELSE
    IF latest_version.version_number <> requested_expected_version THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'management follow-up consent opt-in version conflict';
    END IF;
    IF latest_version.version_number = 2147483647 THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'management follow-up consent opt-in version overflow';
    END IF;
    next_version_number := latest_version.version_number + 1;
  END IF;

  INSERT INTO app_private.management_follow_up_consent_opt_in_versions (
    project_id,
    metric_id,
    version_number,
    expected_version,
    enabled,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    request_id,
    recorded_at_utc
  ) VALUES (
    requested_project_id,
    requested_metric_id,
    next_version_number,
    requested_expected_version,
    requested_enabled,
    trusted_app_user_id,
    (authorization_evidence->>'organization_workspace_id')::uuid,
    (authorization_evidence->>'organization_membership_id')::uuid,
    (authorization_evidence->>'project_membership_id')::uuid,
    (authorization_evidence->>'capability_grant_id')::uuid,
    'release_management_reports',
    authorization_reference_at_utc,
    requested_request_id,
    pg_catalog.clock_timestamp()
  );

  RETURN app_private.management_follow_up_consent_opt_in_document_v1(
    requested_project_id,
    next_version_number
  );
END
$function$;

CREATE FUNCTION app_private.read_management_follow_up_consent_opt_in_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_metric_id text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  latest_version
    app_private.management_follow_up_consent_opt_in_versions%ROWTYPE;
BEGIN
  IF trusted_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_metric_id IS DISTINCT FROM 'follow_up_consent_ratio@1'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent opt-in read';
  END IF;

  PERFORM app_private.resolve_management_report_authorization_v1(
    trusted_app_user_id,
    requested_project_id,
    'release_management_reports'
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'management-follow-up-consent-opt-in:' || requested_project_id::text,
      0
    )
  );

  PERFORM app_private.resolve_management_report_authorization_v1(
    trusted_app_user_id,
    requested_project_id,
    'release_management_reports'
  );

  SELECT version_row.*
  INTO latest_version
  FROM app_private.management_follow_up_consent_opt_in_versions
    AS version_row
  WHERE version_row.project_id = requested_project_id
  ORDER BY version_row.version_number DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'state_contract_id', 'management_follow_up_consent_opt_in_state_v1',
    'metric_id', requested_metric_id,
    'project_id', requested_project_id,
    'status', CASE
      WHEN latest_version.project_id IS NULL
        OR NOT latest_version.enabled
        THEN 'not_enabled'
      ELSE 'enabled'
    END,
    'configuration', CASE
      WHEN latest_version.project_id IS NULL THEN NULL::jsonb
      ELSE app_private.management_follow_up_consent_opt_in_document_v1(
        latest_version.project_id,
        latest_version.version_number
      )
    END
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.reject_management_follow_up_consent_opt_in_mutation_v1(),
  app_private.validate_management_follow_up_consent_opt_in_v1(),
  app_private.lock_management_follow_up_consent_opt_in_project_status_v1(),
  app_private.management_follow_up_consent_opt_in_document_v1(uuid, integer),
  app_private.configure_management_follow_up_consent_opt_in_v1(
    uuid, uuid, text, uuid, integer, boolean
  ),
  app_private.read_management_follow_up_consent_opt_in_v1(uuid, uuid, text)
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.resolve_management_report_authorization_v1(uuid, uuid, text)
  FROM tongxingzhe_management_follow_up_consent_config_writer;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_follow_up_consent_config_writer;

GRANT SELECT (app_user_id, status)
  ON app_data.app_users
  TO tongxingzhe_management_follow_up_consent_config_writer;
GRANT SELECT (workspace_id, workspace_kind, deleted_at)
  ON app_data.workspaces
  TO tongxingzhe_management_follow_up_consent_config_writer;
GRANT SELECT (project_id, workspace_id, status)
  ON app_data.projects
  TO tongxingzhe_management_follow_up_consent_config_writer;
GRANT SELECT (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  )
  ON app_data.organization_memberships
  TO tongxingzhe_management_follow_up_consent_config_writer;
GRANT SELECT (
    project_membership_id,
    organization_membership_id,
    project_id,
    active_from_utc,
    inactive_from_utc
  )
  ON app_data.project_memberships
  TO tongxingzhe_management_follow_up_consent_config_writer;
GRANT SELECT (
    capability_grant_id,
    project_membership_id,
    capability_id,
    active_from_utc,
    inactive_from_utc
  )
  ON app_data.management_report_capability_grants
  TO tongxingzhe_management_follow_up_consent_config_writer;

GRANT EXECUTE ON FUNCTION
  app_private.resolve_management_report_authorization_v1(uuid, uuid, text),
  app_private.management_follow_up_consent_opt_in_document_v1(uuid, integer),
  app_private.configure_management_follow_up_consent_opt_in_v1(
    uuid, uuid, text, uuid, integer, boolean
  ),
  app_private.read_management_follow_up_consent_opt_in_v1(uuid, uuid, text)
  TO tongxingzhe_management_follow_up_consent_config_writer;

GRANT tongxingzhe_management_follow_up_consent_config_writer TO CURRENT_USER;

ALTER TABLE app_private.management_follow_up_consent_opt_in_versions
  OWNER TO tongxingzhe_management_follow_up_consent_config_writer;
ALTER FUNCTION
  app_private.reject_management_follow_up_consent_opt_in_mutation_v1()
  OWNER TO tongxingzhe_management_follow_up_consent_config_writer;
ALTER FUNCTION
  app_private.validate_management_follow_up_consent_opt_in_v1()
  OWNER TO tongxingzhe_management_follow_up_consent_config_writer;
ALTER FUNCTION
  app_private.lock_management_follow_up_consent_opt_in_project_status_v1()
  OWNER TO tongxingzhe_management_follow_up_consent_config_writer;
ALTER FUNCTION
  app_private.management_follow_up_consent_opt_in_document_v1(uuid, integer)
  OWNER TO tongxingzhe_management_follow_up_consent_config_writer;
ALTER FUNCTION
  app_private.configure_management_follow_up_consent_opt_in_v1(
    uuid, uuid, text, uuid, integer, boolean
  ) OWNER TO tongxingzhe_management_follow_up_consent_config_writer;
ALTER FUNCTION
  app_private.read_management_follow_up_consent_opt_in_v1(uuid, uuid, text)
  OWNER TO tongxingzhe_management_follow_up_consent_config_writer;

REVOKE tongxingzhe_management_follow_up_consent_config_writer FROM CURRENT_USER;

DO $configuration_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS configuration_role
      ON configuration_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE configuration_role.rolname =
      'tongxingzhe_management_follow_up_consent_config_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_follow_up_consent_config_writer FROM %I',
      member_name
    );
  END LOOP;
END
$configuration_membership$;

COMMENT ON TABLE app_private.management_follow_up_consent_opt_in_versions
IS 'Immutable organization-project opt-in configuration and authorization provenance for follow_up_consent_ratio@1; no report values.';

COMMENT ON FUNCTION
  app_private.configure_management_follow_up_consent_opt_in_v1(
    uuid, uuid, text, uuid, integer, boolean
  )
IS 'Appends one idempotent organization-project opt-in configuration after locked release-management reauthorization.';

COMMENT ON FUNCTION
  app_private.read_management_follow_up_consent_opt_in_v1(uuid, uuid, text)
IS 'Returns only value-free organization-project opt-in state after locked release-management reauthorization.';
