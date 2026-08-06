-- 0022_personal_action_reminders.sql
--
-- 每个私人项目可保存一个可选的每日当地钟点。提醒计划在设备间同步，
-- 但系统通知是否启用仍只保存在各设备本地，不能由服务端替设备开启。

CREATE TABLE app_data.personal_action_reminders (
  reminder_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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

CREATE TABLE app_data.personal_action_reminder_versions (
  reminder_id uuid NOT NULL
    REFERENCES app_data.personal_action_reminders (reminder_id)
    ON DELETE RESTRICT,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  expected_revision integer NOT NULL CHECK (expected_revision >= 0),
  local_minute_of_day integer CHECK (local_minute_of_day BETWEEN 0 AND 1439),
  requested_at_utc timestamptz NOT NULL,
  mutation_id text NOT NULL CHECK (
    length(btrim(mutation_id)) BETWEEN 1 AND 120
  ),
  PRIMARY KEY (reminder_id, revision_number),
  UNIQUE (reminder_id, mutation_id)
);

REVOKE ALL PRIVILEGES
  ON app_data.personal_action_reminders,
     app_data.personal_action_reminder_versions
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.reject_personal_action_reminder_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'personal action reminder versions are append-only';
END
$function$;

CREATE TRIGGER personal_action_reminder_versions_immutable
BEFORE UPDATE OR DELETE ON app_data.personal_action_reminder_versions
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_personal_action_reminder_version_mutation();

CREATE FUNCTION app_data.personal_action_reminder_document(
  requested_reminder_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'reminder_id', reminder.reminder_id,
    'revision', reminder.current_revision,
    'local_minute_of_day', version_row.local_minute_of_day,
    'updated_at_utc', version_row.requested_at_utc
  )
  FROM app_data.personal_action_reminders AS reminder
  JOIN app_data.personal_action_reminder_versions AS version_row
    ON version_row.reminder_id = reminder.reminder_id
   AND version_row.revision_number = reminder.current_revision
  WHERE reminder.reminder_id = requested_reminder_id;
$function$;

CREATE FUNCTION app_data.read_personal_action_reminder(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  requested_reminder_id uuid;
BEGIN
  IF NOT app_data.personal_action_plan_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal action reminder scope is forbidden';
  END IF;

  SELECT reminder.reminder_id INTO requested_reminder_id
  FROM app_data.personal_action_reminders AS reminder
  WHERE reminder.app_user_id = trusted_app_user_id
    AND reminder.workspace_id = trusted_workspace_id
    AND reminder.project_id = trusted_project_id;

  RETURN app_data.personal_action_reminder_document(requested_reminder_id);
END
$function$;

CREATE FUNCTION app_data.save_personal_action_reminder(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_expected_revision integer,
  requested_local_minute_of_day integer,
  requested_mutation_id text,
  trusted_requested_at_utc timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_mutation_id text := btrim(requested_mutation_id);
  reminder_row app_data.personal_action_reminders%ROWTYPE;
  replay_version app_data.personal_action_reminder_versions%ROWTYPE;
  next_revision integer;
  result_document jsonb;
BEGIN
  IF requested_expected_revision IS NULL
    OR requested_expected_revision < 0
    OR requested_local_minute_of_day IS NOT NULL
      AND requested_local_minute_of_day NOT BETWEEN 0 AND 1439
    OR requested_mutation_id IS NULL
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
    OR trusted_requested_at_utc IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal action reminder request';
  END IF;
  IF NOT app_data.personal_action_plan_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal action reminder scope is forbidden';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      trusted_app_user_id::text || ':' || trusted_workspace_id::text
        || ':' || trusted_project_id::text || ':reminder',
      0
    )
  );

  SELECT reminder.* INTO reminder_row
  FROM app_data.personal_action_reminders AS reminder
  WHERE reminder.app_user_id = trusted_app_user_id
    AND reminder.workspace_id = trusted_workspace_id
    AND reminder.project_id = trusted_project_id
  FOR UPDATE;

  IF reminder_row.reminder_id IS NOT NULL THEN
    SELECT version_row.* INTO replay_version
    FROM app_data.personal_action_reminder_versions AS version_row
    WHERE version_row.reminder_id = reminder_row.reminder_id
      AND version_row.mutation_id = normalized_mutation_id;
    IF replay_version.reminder_id IS NOT NULL THEN
      IF replay_version.expected_revision <> requested_expected_revision
        OR replay_version.local_minute_of_day IS DISTINCT FROM
          requested_local_minute_of_day
      THEN
        RAISE EXCEPTION USING
          ERRCODE = '22023',
          MESSAGE = 'personal action reminder replay changed payload';
      END IF;
      result_document := app_data.personal_action_reminder_document(
        reminder_row.reminder_id
      );
      RETURN result_document || jsonb_build_object(
        'duplicate', true,
        'accepted_revision', replay_version.revision_number
      );
    END IF;
  END IF;

  IF reminder_row.reminder_id IS NULL THEN
    IF requested_expected_revision <> 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = '40001',
        MESSAGE = 'personal action reminder revision conflict';
    END IF;
    INSERT INTO app_data.personal_action_reminders (
      app_user_id,
      workspace_id,
      project_id
    ) VALUES (
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id
    ) RETURNING * INTO reminder_row;
  ELSIF reminder_row.current_revision <> requested_expected_revision THEN
    RAISE EXCEPTION USING
      ERRCODE = '40001',
      MESSAGE = 'personal action reminder revision conflict';
  END IF;

  next_revision := reminder_row.current_revision + 1;
  INSERT INTO app_data.personal_action_reminder_versions (
    reminder_id,
    revision_number,
    expected_revision,
    local_minute_of_day,
    requested_at_utc,
    mutation_id
  ) VALUES (
    reminder_row.reminder_id,
    next_revision,
    requested_expected_revision,
    requested_local_minute_of_day,
    trusted_requested_at_utc,
    normalized_mutation_id
  );
  UPDATE app_data.personal_action_reminders
  SET current_revision = next_revision,
      updated_at = trusted_requested_at_utc
  WHERE reminder_id = reminder_row.reminder_id;

  result_document := app_data.personal_action_reminder_document(
    reminder_row.reminder_id
  );
  RETURN result_document || jsonb_build_object(
    'duplicate', false,
    'accepted_revision', next_revision
  );
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.reject_personal_action_reminder_version_mutation(),
  app_data.personal_action_reminder_document(uuid)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL ON FUNCTION
  app_data.read_personal_action_reminder(uuid, uuid, uuid),
  app_data.save_personal_action_reminder(
    uuid, uuid, uuid, integer, integer, text, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.read_personal_action_reminder(uuid, uuid, uuid),
  app_data.save_personal_action_reminder(
    uuid, uuid, uuid, integer, integer, text, timestamptz
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.personal_action_reminders IS
  'Private synced reminder schedule; device notification opt-in is local.';
COMMENT ON COLUMN
  app_data.personal_action_reminder_versions.local_minute_of_day IS
  'Optional daily wall-clock minute, interpreted in each reminder device zone.';
