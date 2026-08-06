-- 0021_personal_action_plans.sql
--
-- 个人行动计划只服务于本人。计划版本只追加，周目标只统计当前有效、已经
-- 提交的接触，并按实际发生时间进入固定 IANA 时区的七天周期。

CREATE TABLE app_data.personal_action_plans (
  plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  current_revision integer NOT NULL DEFAULT 0 CHECK (current_revision >= 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (app_user_id, workspace_id, project_id)
);

CREATE TABLE app_data.personal_action_plan_versions (
  plan_id uuid NOT NULL
    REFERENCES app_data.personal_action_plans (plan_id) ON DELETE RESTRICT,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  expected_revision integer NOT NULL CHECK (expected_revision >= 0),
  weekly_contact_target integer CHECK (
    weekly_contact_target BETWEEN 1 AND 999
  ),
  statistics_time_zone text NOT NULL CHECK (
    length(btrim(statistics_time_zone)) BETWEEN 1 AND 100
  ),
  week_start_iso_day integer NOT NULL CHECK (
    week_start_iso_day BETWEEN 1 AND 7
  ),
  effective_from_utc timestamptz NOT NULL,
  requested_at_utc timestamptz NOT NULL,
  mutation_id text NOT NULL CHECK (
    length(btrim(mutation_id)) BETWEEN 1 AND 120
  ),
  PRIMARY KEY (plan_id, revision_number),
  UNIQUE (plan_id, mutation_id)
);

CREATE INDEX personal_action_plan_versions_effective
  ON app_data.personal_action_plan_versions (
    plan_id,
    effective_from_utc DESC,
    revision_number DESC
  );

REVOKE ALL PRIVILEGES
  ON app_data.personal_action_plans,
     app_data.personal_action_plan_versions
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.reject_personal_action_plan_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'personal action plan versions are append-only';
END
$function$;

CREATE TRIGGER personal_action_plan_versions_immutable
BEFORE UPDATE OR DELETE ON app_data.personal_action_plan_versions
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_personal_action_plan_version_mutation();

CREATE FUNCTION app_data.personal_action_plan_context_authorized(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
  );
$function$;

CREATE FUNCTION app_data.personal_action_plan_time_zone_valid(
  requested_time_zone text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT requested_time_zone = 'UTC'
    OR (
      position('/' IN requested_time_zone) > 0
      AND requested_time_zone NOT LIKE 'posix/%'
      AND requested_time_zone NOT LIKE 'right/%'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_timezone_names AS time_zone_row
        WHERE time_zone_row.name = requested_time_zone
      )
    );
$function$;

CREATE FUNCTION app_data.personal_action_plan_cycle_start(
  reference_at_utc timestamptz,
  statistics_time_zone text,
  week_start_iso_day integer
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT (
    (
      (reference_at_utc AT TIME ZONE statistics_time_zone)::date
      - (
        (
          extract(
            isodow FROM reference_at_utc AT TIME ZONE statistics_time_zone
          )::integer
          - week_start_iso_day
          + 7
        ) % 7
      )
    )::timestamp AT TIME ZONE statistics_time_zone
  );
$function$;

CREATE FUNCTION app_data.personal_action_plan_cycle_until(
  cycle_start_utc timestamptz,
  statistics_time_zone text
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT (
    ((cycle_start_utc AT TIME ZONE statistics_time_zone)::date + 7)::timestamp
    AT TIME ZONE statistics_time_zone
  );
$function$;

CREATE FUNCTION app_data.personal_action_plan_document(
  requested_plan_id uuid,
  reference_at_utc timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  plan_row app_data.personal_action_plans%ROWTYPE;
  current_version app_data.personal_action_plan_versions%ROWTYPE;
  pending_version app_data.personal_action_plan_versions%ROWTYPE;
  cycle_start_utc timestamptz;
  cycle_until_utc timestamptz;
  recorded_contact_sessions bigint;
  remaining_contact_sessions bigint;
BEGIN
  SELECT plan.* INTO plan_row
  FROM app_data.personal_action_plans AS plan
  WHERE plan.plan_id = requested_plan_id;
  IF plan_row.plan_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT version_row.* INTO current_version
  FROM app_data.personal_action_plan_versions AS version_row
  WHERE version_row.plan_id = requested_plan_id
    AND version_row.effective_from_utc <= reference_at_utc
  ORDER BY
    version_row.effective_from_utc DESC,
    version_row.revision_number DESC
  LIMIT 1;
  IF current_version.plan_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT version_row.* INTO pending_version
  FROM app_data.personal_action_plan_versions AS version_row
  WHERE version_row.plan_id = requested_plan_id
    AND version_row.effective_from_utc > reference_at_utc
  ORDER BY
    version_row.effective_from_utc,
    version_row.revision_number
  LIMIT 1;

  cycle_start_utc := app_data.personal_action_plan_cycle_start(
    reference_at_utc,
    current_version.statistics_time_zone,
    current_version.week_start_iso_day
  );
  cycle_until_utc := app_data.personal_action_plan_cycle_until(
    cycle_start_utc,
    current_version.statistics_time_zone
  );

  SELECT count(*) INTO recorded_contact_sessions
  FROM app_data.contacts AS contact_row
  WHERE contact_row.app_user_id = plan_row.app_user_id
    AND contact_row.workspace_id = plan_row.workspace_id
    AND contact_row.project_id = plan_row.project_id
    AND contact_row.lifecycle_status = 'active'
    AND contact_row.occurred_at_utc >= cycle_start_utc
    AND contact_row.occurred_at_utc < LEAST(
      cycle_until_utc,
      reference_at_utc
    );

  remaining_contact_sessions := CASE
    WHEN current_version.weekly_contact_target IS NULL THEN NULL
    ELSE GREATEST(
      current_version.weekly_contact_target - recorded_contact_sessions,
      0
    )
  END;

  RETURN jsonb_build_object(
    'plan_id', plan_row.plan_id,
    'revision', plan_row.current_revision,
    'current', jsonb_build_object(
      'revision', current_version.revision_number,
      'weekly_contact_target', current_version.weekly_contact_target,
      'statistics_time_zone', current_version.statistics_time_zone,
      'week_start_iso_day', current_version.week_start_iso_day,
      'effective_from_utc', current_version.effective_from_utc
    ),
    'pending', CASE
      WHEN pending_version.plan_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'revision', pending_version.revision_number,
        'weekly_contact_target', pending_version.weekly_contact_target,
        'statistics_time_zone', pending_version.statistics_time_zone,
        'week_start_iso_day', pending_version.week_start_iso_day,
        'effective_from_utc', pending_version.effective_from_utc
      )
    END,
    'progress', jsonb_build_object(
      'cycle_start_utc', cycle_start_utc,
      'cycle_until_utc', cycle_until_utc,
      'recorded_contact_sessions', recorded_contact_sessions,
      'remaining_contact_sessions', remaining_contact_sessions,
      'as_of_utc', reference_at_utc
    )
  );
END
$function$;

CREATE FUNCTION app_data.read_personal_action_plan(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  trusted_reference_at_utc timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  requested_plan_id uuid;
BEGIN
  IF trusted_reference_at_utc IS NULL
    OR NOT app_data.personal_action_plan_context_authorized(
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal action plan scope is forbidden';
  END IF;

  SELECT plan_row.plan_id INTO requested_plan_id
  FROM app_data.personal_action_plans AS plan_row
  WHERE plan_row.app_user_id = trusted_app_user_id
    AND plan_row.workspace_id = trusted_workspace_id
    AND plan_row.project_id = trusted_project_id;

  RETURN app_data.personal_action_plan_document(
    requested_plan_id,
    trusted_reference_at_utc
  );
END
$function$;

CREATE FUNCTION app_data.save_personal_action_plan(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_expected_revision integer,
  requested_weekly_contact_target integer,
  requested_statistics_time_zone text,
  requested_week_start_iso_day integer,
  requested_mutation_id text,
  trusted_requested_at_utc timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_time_zone text := btrim(requested_statistics_time_zone);
  normalized_mutation_id text := btrim(requested_mutation_id);
  plan_row app_data.personal_action_plans%ROWTYPE;
  replay_version app_data.personal_action_plan_versions%ROWTYPE;
  active_version app_data.personal_action_plan_versions%ROWTYPE;
  next_revision integer;
  effective_from_utc timestamptz;
  result_document jsonb;
BEGIN
  IF requested_expected_revision IS NULL
    OR requested_expected_revision < 0
    OR requested_statistics_time_zone IS NULL
    OR requested_week_start_iso_day IS NULL
    OR requested_week_start_iso_day NOT BETWEEN 1 AND 7
    OR requested_weekly_contact_target IS NOT NULL
      AND requested_weekly_contact_target NOT BETWEEN 1 AND 999
    OR requested_mutation_id IS NULL
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
    OR trusted_requested_at_utc IS NULL
    OR NOT app_data.personal_action_plan_time_zone_valid(normalized_time_zone)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal action plan request';
  END IF;
  IF NOT app_data.personal_action_plan_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal action plan scope is forbidden';
  END IF;

  -- The lock key contains no PII and serializes first creation for one scope.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      trusted_app_user_id::text || ':' || trusted_workspace_id::text
        || ':' || trusted_project_id::text,
      0
    )
  );

  SELECT plan.* INTO plan_row
  FROM app_data.personal_action_plans AS plan
  WHERE plan.app_user_id = trusted_app_user_id
    AND plan.workspace_id = trusted_workspace_id
    AND plan.project_id = trusted_project_id
  FOR UPDATE;

  IF plan_row.plan_id IS NOT NULL THEN
    SELECT version_row.* INTO replay_version
    FROM app_data.personal_action_plan_versions AS version_row
    WHERE version_row.plan_id = plan_row.plan_id
      AND version_row.mutation_id = normalized_mutation_id;
    IF replay_version.plan_id IS NOT NULL THEN
      IF replay_version.expected_revision <> requested_expected_revision
        OR replay_version.weekly_contact_target IS DISTINCT FROM
          requested_weekly_contact_target
        OR replay_version.statistics_time_zone <> normalized_time_zone
        OR replay_version.week_start_iso_day <>
          requested_week_start_iso_day
      THEN
        RAISE EXCEPTION USING
          ERRCODE = '22023',
          MESSAGE = 'personal action plan mutation replay changed payload';
      END IF;
      result_document := app_data.personal_action_plan_document(
        plan_row.plan_id,
        trusted_requested_at_utc
      );
      RETURN result_document || jsonb_build_object(
        'duplicate', true,
        'accepted_revision', replay_version.revision_number
      );
    END IF;
  END IF;

  IF plan_row.plan_id IS NULL THEN
    IF requested_expected_revision <> 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'personal action plan revision conflict';
    END IF;
    INSERT INTO app_data.personal_action_plans (
      app_user_id,
      workspace_id,
      project_id
    ) VALUES (
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id
    ) RETURNING * INTO plan_row;
    effective_from_utc := app_data.personal_action_plan_cycle_start(
      trusted_requested_at_utc,
      normalized_time_zone,
      requested_week_start_iso_day
    );
  ELSE
    IF plan_row.current_revision <> requested_expected_revision THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'personal action plan revision conflict';
    END IF;
    IF EXISTS (
      SELECT 1
      FROM app_data.personal_action_plan_versions AS version_row
      WHERE version_row.plan_id = plan_row.plan_id
        AND version_row.effective_from_utc > trusted_requested_at_utc
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'personal action plan already has a pending change';
    END IF;
    effective_from_utc := app_data.personal_action_plan_cycle_until(
      app_data.personal_action_plan_cycle_start(
        trusted_requested_at_utc,
        normalized_time_zone,
        requested_week_start_iso_day
      ),
      normalized_time_zone
    );
  END IF;

  next_revision := plan_row.current_revision + 1;
  INSERT INTO app_data.personal_action_plan_versions (
    plan_id,
    revision_number,
    expected_revision,
    weekly_contact_target,
    statistics_time_zone,
    week_start_iso_day,
    effective_from_utc,
    requested_at_utc,
    mutation_id
  ) VALUES (
    plan_row.plan_id,
    next_revision,
    requested_expected_revision,
    requested_weekly_contact_target,
    normalized_time_zone,
    requested_week_start_iso_day,
    effective_from_utc,
    trusted_requested_at_utc,
    normalized_mutation_id
  );
  UPDATE app_data.personal_action_plans
  SET current_revision = next_revision,
      updated_at = trusted_requested_at_utc
  WHERE plan_id = plan_row.plan_id;

  result_document := app_data.personal_action_plan_document(
    plan_row.plan_id,
    trusted_requested_at_utc
  );
  RETURN result_document || jsonb_build_object(
    'duplicate', false,
    'accepted_revision', next_revision
  );
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.reject_personal_action_plan_version_mutation(),
  app_data.personal_action_plan_context_authorized(uuid, uuid, uuid),
  app_data.personal_action_plan_time_zone_valid(text),
  app_data.personal_action_plan_cycle_start(timestamptz, text, integer),
  app_data.personal_action_plan_cycle_until(timestamptz, text),
  app_data.personal_action_plan_document(uuid, timestamptz)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL ON FUNCTION
  app_data.read_personal_action_plan(uuid, uuid, uuid, timestamptz),
  app_data.save_personal_action_plan(
    uuid, uuid, uuid, integer, integer, text, integer, text, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.read_personal_action_plan(uuid, uuid, uuid, timestamptz),
  app_data.save_personal_action_plan(
    uuid, uuid, uuid, integer, integer, text, integer, text, timestamptz
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.personal_action_plans IS
  'Private per-user project plans; no organization or manager read surface.';
COMMENT ON TABLE app_data.personal_action_plan_versions IS
  'Append-only plan versions with fixed time-zone and week-start semantics.';
