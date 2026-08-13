-- 0048_project_follow_up_consent_opt_in.sql
--
-- 保存个人项目对 follow_up_consent_ratio@1 的当前启用开关。版本历史只追加，
-- runtime 只能调用 app_data 的窄包装函数；配置表和内部解析函数留在 app_private。

CREATE TABLE app_private.project_follow_up_consent_opt_in_versions (
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  metric_id text NOT NULL CHECK (
    metric_id = 'follow_up_consent_ratio@1'
  ),
  version_number integer NOT NULL CHECK (version_number > 0),
  expected_version integer NOT NULL CHECK (expected_version >= 0),
  enabled boolean NOT NULL,
  actor_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  request_id uuid NOT NULL UNIQUE,
  recorded_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (project_id, version_number),
  CHECK (expected_version = version_number - 1),
  CHECK (isfinite(recorded_at_utc))
);

CREATE INDEX project_follow_up_consent_opt_in_versions_latest
ON app_private.project_follow_up_consent_opt_in_versions (
  project_id,
  version_number DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.project_follow_up_consent_opt_in_versions
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.reject_project_follow_up_consent_opt_in_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'project follow-up consent opt-in history is immutable';
END
$function$;

CREATE TRIGGER project_follow_up_consent_opt_in_versions_immutable
BEFORE UPDATE OR DELETE
ON app_private.project_follow_up_consent_opt_in_versions
FOR EACH ROW
EXECUTE FUNCTION
  app_private.reject_project_follow_up_consent_opt_in_mutation_v1();

CREATE FUNCTION app_private.validate_project_follow_up_consent_opt_in_insert_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  latest_version_number integer;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-follow-up-consent-opt-in:' || NEW.project_id::text,
      0
    )
  );

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS app_user
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.personal_owner_app_user_id = app_user.app_user_id
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE app_user.app_user_id = NEW.actor_app_user_id
      AND app_user.status = 'active'
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = NEW.project_id
      AND project_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'project follow-up consent opt-in insert scope is forbidden';
  END IF;

  SELECT max(version_row.version_number)
  INTO latest_version_number
  FROM app_private.project_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.project_id = NEW.project_id;

  IF NEW.version_number <> coalesce(latest_version_number, 0) + 1
    OR NEW.expected_version <> coalesce(latest_version_number, 0)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project follow-up consent opt-in version chain';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER project_follow_up_consent_opt_in_versions_validate_insert
BEFORE INSERT
ON app_private.project_follow_up_consent_opt_in_versions
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_project_follow_up_consent_opt_in_insert_v1();

CREATE FUNCTION app_private.resolve_project_follow_up_consent_opt_in_actor_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR trusted_subject IS NULL
    OR requested_project_id IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project follow-up consent opt-in identity';
  END IF;

  SELECT app_user.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.personal_owner_app_user_id = app_user.app_user_id
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active'
    AND workspace_row.workspace_kind = 'personal'
    AND workspace_row.deleted_at IS NULL
    AND project_row.project_id = requested_project_id
    AND project_row.status = 'active'
  FOR SHARE OF identity_row, app_user, workspace_row, project_row;

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'project follow-up consent opt-in scope is forbidden';
  END IF;

  RETURN resolved_app_user_id;
END
$function$;

CREATE FUNCTION app_private.project_follow_up_consent_opt_in_document_v1(
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
      'project_follow_up_consent_opt_in_configuration_v1',
    'metric_id', version_row.metric_id,
    'project_id', version_row.project_id,
    'version_number', version_row.version_number,
    'expected_version', version_row.expected_version,
    'enabled', version_row.enabled,
    'actor_app_user_id', version_row.actor_app_user_id,
    'request_id', version_row.request_id,
    'recorded_at_utc', to_char(
      version_row.recorded_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )
  )
  FROM app_private.project_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.project_id = requested_project_id
    AND version_row.version_number = requested_version_number;
$function$;

CREATE FUNCTION app_private.configure_project_follow_up_consent_opt_in_v1(
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
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  replay_version
    app_private.project_follow_up_consent_opt_in_versions%ROWTYPE;
  latest_version
    app_private.project_follow_up_consent_opt_in_versions%ROWTYPE;
  next_version_number integer;
BEGIN
  IF trusted_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_metric_id IS DISTINCT FROM 'follow_up_consent_ratio@1'
    OR requested_request_id IS NULL
    OR requested_expected_version IS NULL
    OR requested_expected_version < 0
    OR requested_enabled IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project follow-up consent opt-in request';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-follow-up-consent-opt-in-request:'
        || requested_request_id::text,
      0
    )
  );

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-follow-up-consent-opt-in:' || requested_project_id::text,
      0
    )
  );

  SELECT version_row.*
  INTO replay_version
  FROM app_private.project_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.request_id = requested_request_id;

  IF FOUND THEN
    IF replay_version.project_id <> requested_project_id
      OR replay_version.metric_id <> requested_metric_id
      OR replay_version.actor_app_user_id <> trusted_app_user_id
      OR replay_version.expected_version <> requested_expected_version
      OR replay_version.enabled <> requested_enabled
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'project follow-up consent opt-in idempotency conflict';
    END IF;

    RETURN app_private.project_follow_up_consent_opt_in_document_v1(
      replay_version.project_id,
      replay_version.version_number
    );
  END IF;

  SELECT version_row.*
  INTO latest_version
  FROM app_private.project_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.project_id = requested_project_id
  ORDER BY version_row.version_number DESC
  LIMIT 1;

  IF NOT FOUND THEN
    IF requested_expected_version <> 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'project follow-up consent opt-in version conflict';
    END IF;
    next_version_number := 1;
  ELSE
    IF latest_version.version_number <> requested_expected_version THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'project follow-up consent opt-in version conflict';
    END IF;
    next_version_number := latest_version.version_number + 1;
  END IF;

  INSERT INTO app_private.project_follow_up_consent_opt_in_versions (
    project_id,
    metric_id,
    version_number,
    expected_version,
    enabled,
    actor_app_user_id,
    request_id,
    recorded_at_utc
  ) VALUES (
    requested_project_id,
    requested_metric_id,
    next_version_number,
    requested_expected_version,
    requested_enabled,
    trusted_app_user_id,
    requested_request_id,
    pg_catalog.clock_timestamp()
  );

  RETURN app_private.project_follow_up_consent_opt_in_document_v1(
    requested_project_id,
    next_version_number
  );
END
$function$;

CREATE FUNCTION app_private.read_project_follow_up_consent_opt_in_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_metric_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  latest_version
    app_private.project_follow_up_consent_opt_in_versions%ROWTYPE;
BEGIN
  IF trusted_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_metric_id IS DISTINCT FROM 'follow_up_consent_ratio@1'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project follow-up consent opt-in read';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS app_user
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.personal_owner_app_user_id = app_user.app_user_id
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE app_user.app_user_id = trusted_app_user_id
      AND app_user.status = 'active'
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = requested_project_id
      AND project_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'project follow-up consent opt-in scope is forbidden';
  END IF;

  SELECT version_row.*
  INTO latest_version
  FROM app_private.project_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.project_id = requested_project_id
  ORDER BY version_row.version_number DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'state_contract_id', 'project_follow_up_consent_opt_in_state_v1',
    'metric_id', requested_metric_id,
    'project_id', requested_project_id,
    'status', CASE
      WHEN latest_version.project_id IS NULL OR NOT latest_version.enabled
        THEN 'not_enabled'
      ELSE 'enabled'
    END,
    'configuration', CASE
      WHEN latest_version.project_id IS NULL THEN NULL::jsonb
      ELSE app_private.project_follow_up_consent_opt_in_document_v1(
        latest_version.project_id,
        latest_version.version_number
      )
    END
  );
END
$function$;

CREATE FUNCTION app_data.configure_project_follow_up_consent_opt_in_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_metric_id text,
  requested_request_id uuid,
  requested_expected_version integer,
  requested_enabled boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  trusted_app_user_id uuid;
BEGIN
  IF requested_project_id IS NULL OR requested_request_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project follow-up consent opt-in request';
  END IF;

  -- 授权必须发生在幂等请求锁和项目锁之后。解析器再锁住身份、账号、空间和
  -- 项目行，直到配置写入完成，避免等待期间发生的撤权或归档留下旧授权写入。
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-follow-up-consent-opt-in-request:'
        || requested_request_id::text,
      0
    )
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'project-follow-up-consent-opt-in:' || requested_project_id::text,
      0
    )
  );

  trusted_app_user_id := app_private.resolve_project_follow_up_consent_opt_in_actor_v1(
    trusted_issuer,
    trusted_subject,
    requested_project_id
  );

  RETURN app_private.configure_project_follow_up_consent_opt_in_v1(
    trusted_app_user_id,
    requested_project_id,
    requested_metric_id,
    requested_request_id,
    requested_expected_version,
    requested_enabled
  );
END
$function$;

CREATE FUNCTION app_data.read_project_follow_up_consent_opt_in_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_metric_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  trusted_app_user_id uuid;
BEGIN
  trusted_app_user_id := app_private.resolve_project_follow_up_consent_opt_in_actor_v1(
    trusted_issuer,
    trusted_subject,
    requested_project_id
  );

  RETURN app_private.read_project_follow_up_consent_opt_in_v1(
    trusted_app_user_id,
    requested_project_id,
    requested_metric_id
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.reject_project_follow_up_consent_opt_in_mutation_v1(),
  app_private.validate_project_follow_up_consent_opt_in_insert_v1(),
  app_private.resolve_project_follow_up_consent_opt_in_actor_v1(
    text, text, uuid
  ),
  app_private.project_follow_up_consent_opt_in_document_v1(uuid, integer),
  app_private.configure_project_follow_up_consent_opt_in_v1(
    uuid, uuid, text, uuid, integer, boolean
  ),
  app_private.read_project_follow_up_consent_opt_in_v1(
    uuid, uuid, text
  )
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.configure_project_follow_up_consent_opt_in_v1(
    text, text, uuid, text, uuid, integer, boolean
  ),
  app_data.read_project_follow_up_consent_opt_in_v1(
    text, text, uuid, text
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.configure_project_follow_up_consent_opt_in_v1(
    text, text, uuid, text, uuid, integer, boolean
  ),
  app_data.read_project_follow_up_consent_opt_in_v1(
    text, text, uuid, text
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_private.project_follow_up_consent_opt_in_versions IS
  'Append-only current opt-in versions for the personal follow_up_consent_ratio@1 metric.';

COMMENT ON FUNCTION app_data.configure_project_follow_up_consent_opt_in_v1(
  text, text, uuid, text, uuid, integer, boolean
) IS
  'Backend-only idempotent append of a personal project opt-in after trusted identity and project reauthorization.';

COMMENT ON FUNCTION app_data.read_project_follow_up_consent_opt_in_v1(
  text, text, uuid, text
) IS
  'Backend-only read of the current personal project opt-in; unconfigured and disabled states are not_enabled.';
