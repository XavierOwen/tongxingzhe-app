-- 0008_contact_attempts.sql
--
-- 接触尝试是未获回应的直接联络。它与接触事实分表保存，没有触达人数、兴趣、
-- 问卷或 warehouse 事件。后来发生的接触可以关联尝试，但不能改写尝试。

CREATE TABLE app_data.contact_attempts (
  attempt_id text PRIMARY KEY CHECK (length(btrim(attempt_id)) > 0),
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  occurred_at_utc timestamptz NOT NULL,
  occurred_time_zone text NOT NULL
    CHECK (length(btrim(occurred_time_zone)) > 0),
  first_submitted_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  channel text NOT NULL CHECK (
    channel IN (
      'face_to_face',
      'voice_call',
      'video_call',
      'instant_text',
      'asynchronous_message',
      'mixed',
      'other_direct'
    )
  ),
  channel_detail text,
  linked_contact_id text UNIQUE
    REFERENCES app_data.contacts (contact_id) ON DELETE RESTRICT,
  CONSTRAINT contact_attempts_channel_detail_valid CHECK (
    channel <> 'other_direct'
    OR (channel_detail IS NOT NULL AND length(btrim(channel_detail)) > 0)
  )
);

CREATE INDEX contact_attempts_personal_period
  ON app_data.contact_attempts (
    app_user_id,
    workspace_id,
    project_id,
    occurred_at_utc
  );

ALTER TABLE app_data.change_feed
  DROP CONSTRAINT change_feed_change_type_check;

ALTER TABLE app_data.change_feed
  ADD CONSTRAINT change_feed_change_type_check CHECK (
    change_type IN (
      'contact.submitted',
      'contact.revised',
      'contact.voided',
      'contact.attempt.submitted',
      'draft.upserted',
      'draft.deleted'
    )
  );

REVOKE ALL PRIVILEGES
  ON app_data.contact_attempts
  FROM tongxingzhe_runtime;

CREATE OR REPLACE FUNCTION app_data.apply_contact_attempt_submit(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (
  result_code text,
  server_cursor text,
  failure_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  existing_result_code text;
  existing_server_cursor uuid;
  existing_failure_code text;
  payload_attempt_id text;
  payload_workspace_id uuid;
  payload_project_id uuid;
  accepted_cursor uuid;
  submitted_at_utc timestamptz := clock_timestamp();
BEGIN
  IF trusted_app_user_id IS NULL
    OR length(btrim(client_command_id)) = 0
    OR length(btrim(client_device_id)) = 0
    OR length(btrim(client_aggregate_id)) = 0
    OR client_protocol_version <> 1
    OR client_command_type <> 'contact.attempt.submit.v1'
    OR client_base_revision <> 0
    OR jsonb_typeof(typed_payload) <> 'object'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid contact attempt envelope';
  END IF;

  IF typed_payload ? 'appUserId' OR typed_payload ? 'app_user_id' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'client payload must not contain app user identity';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      trusted_app_user_id::text || ':' || client_command_id,
      0
    )
  );

  SELECT
    processed.result_code,
    processed.server_cursor,
    processed.failure_code
    INTO
      existing_result_code,
      existing_server_cursor,
      existing_failure_code
  FROM app_data.processed_commands AS processed
  WHERE processed.app_user_id = trusted_app_user_id
    AND processed.command_id = client_command_id;

  IF FOUND THEN
    RETURN QUERY
    SELECT
      CASE
        WHEN existing_result_code = 'accepted' THEN 'duplicate'
        ELSE existing_result_code
      END,
      existing_server_cursor::text,
      existing_failure_code;
    RETURN;
  END IF;

  payload_attempt_id := typed_payload->>'attemptId';
  payload_workspace_id := (typed_payload->>'workspaceId')::uuid;
  payload_project_id := (typed_payload->>'projectId')::uuid;

  IF payload_attempt_id IS NULL
    OR payload_attempt_id <> client_aggregate_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'attempt and aggregate IDs differ';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = payload_workspace_id
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = payload_project_id
      AND project_row.status = 'active'
  ) THEN
    INSERT INTO app_data.processed_commands (
      app_user_id,
      command_id,
      protocol_version,
      command_type,
      device_id,
      aggregate_id,
      result_code,
      failure_code
    ) VALUES (
      trusted_app_user_id,
      client_command_id,
      client_protocol_version,
      client_command_type,
      client_device_id,
      client_aggregate_id,
      'forbidden',
      'project_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'project_forbidden';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.contact_attempts AS attempt_row
    WHERE attempt_row.attempt_id = payload_attempt_id
  ) THEN
    INSERT INTO app_data.processed_commands (
      app_user_id,
      command_id,
      protocol_version,
      command_type,
      device_id,
      aggregate_id,
      result_code,
      failure_code
    ) VALUES (
      trusted_app_user_id,
      client_command_id,
      client_protocol_version,
      client_command_type,
      client_device_id,
      client_aggregate_id,
      'conflict',
      'aggregate_exists'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'aggregate_exists';
    RETURN;
  END IF;

  INSERT INTO app_data.contact_attempts (
    attempt_id,
    app_user_id,
    workspace_id,
    project_id,
    occurred_at_utc,
    occurred_time_zone,
    first_submitted_at_utc,
    channel,
    channel_detail
  ) VALUES (
    payload_attempt_id,
    trusted_app_user_id,
    payload_workspace_id,
    payload_project_id,
    (typed_payload->>'occurredAtUtc')::timestamptz,
    typed_payload->>'occurredTimeZone',
    submitted_at_utc,
    typed_payload->>'channel',
    NULLIF(typed_payload->>'channelDetail', '')
  );

  accepted_cursor := gen_random_uuid();
  INSERT INTO app_data.change_feed (
    cursor_token,
    app_user_id,
    workspace_id,
    project_id,
    aggregate_id,
    revision_number,
    change_type,
    change_payload
  ) VALUES (
    accepted_cursor,
    trusted_app_user_id,
    payload_workspace_id,
    payload_project_id,
    payload_attempt_id,
    1,
    'contact.attempt.submitted',
    jsonb_build_object(
      'attemptId', payload_attempt_id,
      'workspaceId', payload_workspace_id,
      'projectId', payload_project_id,
      'occurredAtUtc', typed_payload->>'occurredAtUtc',
      'occurredTimeZone', typed_payload->>'occurredTimeZone',
      'firstSubmittedAtUtc', submitted_at_utc,
      'channel', typed_payload->>'channel',
      'channelDetail', NULLIF(typed_payload->>'channelDetail', ''),
      'linkedContactId', NULL
    )
  );

  INSERT INTO app_data.processed_commands (
    app_user_id,
    command_id,
    protocol_version,
    command_type,
    device_id,
    aggregate_id,
    result_code,
    server_cursor
  ) VALUES (
    trusted_app_user_id,
    client_command_id,
    client_protocol_version,
    client_command_type,
    client_device_id,
    client_aggregate_id,
    'accepted',
    accepted_cursor
  );

  RETURN QUERY SELECT 'accepted', accepted_cursor::text, NULL::text;
END
$function$;

ALTER FUNCTION app_data.apply_contact_submit(
  uuid,
  text,
  integer,
  text,
  text,
  text,
  integer,
  jsonb
)
RENAME TO apply_contact_submit_without_attempt;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_submit_without_attempt(
    uuid,
    text,
    integer,
    text,
    text,
    text,
    integer,
    jsonb
  )
  FROM PUBLIC, tongxingzhe_runtime;

CREATE OR REPLACE FUNCTION app_data.apply_contact_submit(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (
  result_code text,
  server_cursor text,
  failure_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  source_attempt_id text := NULLIF(typed_payload->>'sourceAttemptId', '');
  source_attempt app_data.contact_attempts%ROWTYPE;
  delegated_result record;
BEGIN
  IF source_attempt_id IS NULL THEN
    RETURN QUERY
    SELECT *
    FROM app_data.apply_contact_submit_without_attempt(
      trusted_app_user_id,
      client_command_id,
      client_protocol_version,
      client_command_type,
      client_device_id,
      client_aggregate_id,
      client_base_revision,
      typed_payload
    );
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('contact-attempt:' || source_attempt_id, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM app_data.processed_commands AS processed
    WHERE processed.app_user_id = trusted_app_user_id
      AND processed.command_id = client_command_id
  ) THEN
    RETURN QUERY
    SELECT *
    FROM app_data.apply_contact_submit_without_attempt(
      trusted_app_user_id,
      client_command_id,
      client_protocol_version,
      client_command_type,
      client_device_id,
      client_aggregate_id,
      client_base_revision,
      typed_payload
    );
    RETURN;
  END IF;

  SELECT * INTO source_attempt
  FROM app_data.contact_attempts AS attempt_row
  WHERE attempt_row.attempt_id = source_attempt_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'rejected', 'source_attempt_not_found'
    );
    RETURN QUERY SELECT 'rejected', NULL::text, 'source_attempt_not_found';
    RETURN;
  END IF;

  IF source_attempt.app_user_id <> trusted_app_user_id
    OR source_attempt.workspace_id <> (typed_payload->>'workspaceId')::uuid
    OR source_attempt.project_id <> (typed_payload->>'projectId')::uuid
  THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'forbidden', 'source_attempt_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'source_attempt_forbidden';
    RETURN;
  END IF;

  IF source_attempt.linked_contact_id IS NOT NULL THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'source_attempt_already_linked'
    );
    RETURN QUERY
    SELECT 'conflict', NULL::text, 'source_attempt_already_linked';
    RETURN;
  END IF;

  SELECT * INTO delegated_result
  FROM app_data.apply_contact_submit_without_attempt(
    trusted_app_user_id,
    client_command_id,
    client_protocol_version,
    client_command_type,
    client_device_id,
    client_aggregate_id,
    client_base_revision,
    typed_payload
  );

  IF delegated_result.result_code = 'accepted' THEN
    UPDATE app_data.contact_attempts
    SET linked_contact_id = client_aggregate_id
    WHERE attempt_id = source_attempt_id;
  END IF;

  RETURN QUERY SELECT
    delegated_result.result_code::text,
    delegated_result.server_cursor::text,
    delegated_result.failure_code::text;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_attempt_submit(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_submit(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.apply_contact_attempt_submit(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_submit(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.contact_attempts IS
  'Unanswered direct outreach; excluded from contact and warehouse metrics.';

COMMENT ON FUNCTION app_data.apply_contact_attempt_submit(
  uuid, text, integer, text, text, text, integer, jsonb
) IS
  'Backend-only idempotent contact-attempt submission for one trusted scope.';
