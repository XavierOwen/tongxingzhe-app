-- 0003_contact_sync.sql
--
-- 保存匿名接触、首个 revision、答案、幂等结果和 change feed。Flutter 不能
-- 直接访问这些表，只能调用自有 Backend；runtime role 只能执行受控函数。

CREATE TABLE app_data.contacts (
  contact_id text PRIMARY KEY,
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  questionnaire_version_id uuid NOT NULL
    REFERENCES app_data.questionnaire_versions (questionnaire_version_id)
    ON DELETE RESTRICT,
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
  location_kind text NOT NULL CHECK (
    location_kind IN ('resolved', 'pending_resolution', 'not_applicable')
  ),
  place_name text,
  smallest_region_id text,
  latitude double precision,
  longitude double precision,
  location_accuracy_meters double precision,
  reach_count integer NOT NULL CHECK (reach_count > 0),
  interest_level integer NOT NULL CHECK (interest_level BETWEEN 0 AND 4),
  current_revision integer NOT NULL DEFAULT 1 CHECK (current_revision > 0),
  lifecycle_status text NOT NULL DEFAULT 'active'
    CHECK (lifecycle_status IN ('active', 'voided')),
  CONSTRAINT contacts_channel_detail_valid CHECK (
    channel <> 'other_direct'
    OR (channel_detail IS NOT NULL AND length(btrim(channel_detail)) > 0)
  ),
  CONSTRAINT contacts_location_shape_valid CHECK (
    (
      location_kind = 'resolved'
      AND place_name IS NOT NULL
      AND length(btrim(place_name)) > 0
      AND smallest_region_id IS NOT NULL
      AND length(btrim(smallest_region_id)) > 0
      AND latitude IS NULL
      AND longitude IS NULL
      AND location_accuracy_meters IS NULL
    )
    OR
    (
      location_kind = 'pending_resolution'
      AND place_name IS NULL
      AND smallest_region_id IS NULL
      AND latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
      AND (
        location_accuracy_meters IS NULL
        OR location_accuracy_meters >= 0
      )
    )
    OR
    (
      location_kind = 'not_applicable'
      AND place_name IS NULL
      AND smallest_region_id IS NULL
      AND latitude IS NULL
      AND longitude IS NULL
      AND location_accuracy_meters IS NULL
      AND channel <> 'face_to_face'
    )
  )
);

CREATE INDEX contacts_personal_period
  ON app_data.contacts (
    app_user_id,
    workspace_id,
    project_id,
    occurred_at_utc
  )
  WHERE lifecycle_status = 'active';

CREATE TABLE app_data.contact_revisions (
  contact_id text NOT NULL
    REFERENCES app_data.contacts (contact_id) ON DELETE RESTRICT,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  revised_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  revised_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot) = 'object'),
  PRIMARY KEY (contact_id, revision_number)
);

CREATE TABLE app_data.contact_answers (
  contact_id text NOT NULL,
  revision_number integer NOT NULL,
  question_id text NOT NULL CHECK (length(btrim(question_id)) > 0),
  answer_state text NOT NULL CHECK (
    answer_state IN (
      'answered',
      'unknown',
      'refused',
      'not_applicable',
      'unanswered'
    )
  ),
  answer_type text NOT NULL CHECK (answer_type = 'boolean'),
  boolean_value boolean,
  PRIMARY KEY (contact_id, revision_number, question_id),
  FOREIGN KEY (contact_id, revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number)
    ON DELETE RESTRICT,
  CONSTRAINT contact_answers_boolean_shape_valid CHECK (
    (answer_state = 'answered' AND boolean_value IS NOT NULL)
    OR
    (answer_state <> 'answered' AND boolean_value IS NULL)
  )
);

CREATE TABLE app_data.change_feed (
  change_sequence bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cursor_token uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  aggregate_id text NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  change_type text NOT NULL CHECK (
    change_type IN ('contact.submitted', 'contact.revised', 'contact.voided')
  ),
  created_at_utc timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX change_feed_scope_sequence
  ON app_data.change_feed (
    app_user_id,
    workspace_id,
    project_id,
    change_sequence
  );

CREATE TABLE app_data.processed_commands (
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  command_id text NOT NULL CHECK (length(btrim(command_id)) > 0),
  protocol_version integer NOT NULL CHECK (protocol_version > 0),
  command_type text NOT NULL CHECK (length(btrim(command_type)) > 0),
  device_id text NOT NULL CHECK (length(btrim(device_id)) > 0),
  aggregate_id text NOT NULL CHECK (length(btrim(aggregate_id)) > 0),
  result_code text NOT NULL CHECK (
    result_code IN ('accepted', 'conflict', 'rejected', 'forbidden')
  ),
  server_cursor uuid,
  failure_code text,
  processed_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (app_user_id, command_id),
  CONSTRAINT processed_commands_result_shape_valid CHECK (
    (result_code = 'accepted' AND server_cursor IS NOT NULL
      AND failure_code IS NULL)
    OR
    (result_code <> 'accepted' AND server_cursor IS NULL
      AND failure_code IS NOT NULL AND length(btrim(failure_code)) > 0)
  )
);

CREATE TABLE app_data.contact_audit_events (
  audit_event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  command_id text NOT NULL,
  contact_id text NOT NULL,
  event_type text NOT NULL CHECK (event_type = 'contact.submitted'),
  created_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (app_user_id, command_id, event_type)
);

CREATE TABLE app_data.warehouse_outbox (
  warehouse_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id text NOT NULL,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  event_type text NOT NULL CHECK (event_type = 'contact.submitted'),
  analytics_payload jsonb NOT NULL
    CHECK (jsonb_typeof(analytics_payload) = 'object'),
  created_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  published_at_utc timestamptz,
  UNIQUE (contact_id, event_type)
);

REVOKE ALL PRIVILEGES
  ON app_data.contacts,
     app_data.contact_revisions,
     app_data.contact_answers,
     app_data.change_feed,
     app_data.processed_commands,
     app_data.contact_audit_events,
     app_data.warehouse_outbox
  FROM tongxingzhe_runtime;

REVOKE ALL PRIVILEGES
  ON SEQUENCE app_data.change_feed_change_sequence_seq,
     app_data.contact_audit_events_audit_event_id_seq
  FROM tongxingzhe_runtime;

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
  existing_result_code text;
  existing_server_cursor uuid;
  existing_failure_code text;
  payload_contact_id text;
  payload_workspace_id uuid;
  payload_project_id uuid;
  payload_questionnaire_version_id uuid;
  payload_location jsonb;
  accepted_cursor uuid;
BEGIN
  IF trusted_app_user_id IS NULL
    OR length(btrim(client_command_id)) = 0
    OR length(btrim(client_device_id)) = 0
    OR length(btrim(client_aggregate_id)) = 0
    OR client_protocol_version <> 1
    OR client_command_type <> 'contact.submit.v1'
    OR client_base_revision <> 0
    OR jsonb_typeof(typed_payload) <> 'object'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid contact submit envelope';
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

  payload_contact_id := typed_payload->>'contactId';
  payload_workspace_id := (typed_payload->>'workspaceId')::uuid;
  payload_project_id := (typed_payload->>'projectId')::uuid;
  payload_questionnaire_version_id :=
    (typed_payload->>'questionnaireVersionId')::uuid;
  payload_location := typed_payload->'location';

  IF payload_contact_id IS NULL
    OR payload_contact_id <> client_aggregate_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'contact and aggregate IDs differ';
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

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.questionnaire_versions AS version_row
    WHERE version_row.questionnaire_version_id =
      payload_questionnaire_version_id
      AND version_row.project_id = payload_project_id
      AND version_row.status = 'published'
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
      'rejected',
      'questionnaire_version_invalid'
    );
    RETURN QUERY
    SELECT 'rejected', NULL::text, 'questionnaire_version_invalid';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.contacts AS contact_row
    WHERE contact_row.contact_id = payload_contact_id
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

  INSERT INTO app_data.contacts (
    contact_id,
    app_user_id,
    workspace_id,
    project_id,
    questionnaire_version_id,
    occurred_at_utc,
    occurred_time_zone,
    channel,
    channel_detail,
    location_kind,
    place_name,
    smallest_region_id,
    latitude,
    longitude,
    location_accuracy_meters,
    reach_count,
    interest_level
  ) VALUES (
    payload_contact_id,
    trusted_app_user_id,
    payload_workspace_id,
    payload_project_id,
    payload_questionnaire_version_id,
    (typed_payload->>'occurredAtUtc')::timestamptz,
    typed_payload->>'occurredTimeZone',
    typed_payload->>'channel',
    NULLIF(typed_payload->>'channelDetail', ''),
    payload_location->>'kind',
    NULLIF(payload_location->>'placeName', ''),
    NULLIF(payload_location->>'smallestRegionId', ''),
    (payload_location->>'latitude')::double precision,
    (payload_location->>'longitude')::double precision,
    (payload_location->>'accuracyMeters')::double precision,
    (typed_payload->>'reachCount')::integer,
    (typed_payload->>'interestLevel')::integer
  );

  INSERT INTO app_data.contact_revisions (
    contact_id,
    revision_number,
    revised_by_app_user_id,
    snapshot
  ) VALUES (
    payload_contact_id,
    1,
    trusted_app_user_id,
    typed_payload
  );

  INSERT INTO app_data.contact_answers (
    contact_id,
    revision_number,
    question_id,
    answer_state,
    answer_type,
    boolean_value
  )
  SELECT
    payload_contact_id,
    1,
    answer_row.answer->>'questionId',
    answer_row.answer->>'state',
    answer_row.answer->>'type',
    CASE
      WHEN answer_row.answer->>'state' = 'answered'
        THEN (answer_row.answer->>'value')::boolean
      ELSE NULL
    END
  FROM jsonb_array_elements(typed_payload->'answers')
    AS answer_row(answer);

  accepted_cursor := gen_random_uuid();
  INSERT INTO app_data.change_feed (
    cursor_token,
    app_user_id,
    workspace_id,
    project_id,
    aggregate_id,
    revision_number,
    change_type
  ) VALUES (
    accepted_cursor,
    trusted_app_user_id,
    payload_workspace_id,
    payload_project_id,
    payload_contact_id,
    1,
    'contact.submitted'
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

  INSERT INTO app_data.contact_audit_events (
    app_user_id,
    command_id,
    contact_id,
    event_type
  ) VALUES (
    trusted_app_user_id,
    client_command_id,
    payload_contact_id,
    'contact.submitted'
  );

  INSERT INTO app_data.warehouse_outbox (
    contact_id,
    project_id,
    event_type,
    analytics_payload
  ) VALUES (
    payload_contact_id,
    payload_project_id,
    'contact.submitted',
    jsonb_build_object(
      'contact_id', payload_contact_id,
      'project_id', payload_project_id,
      'occurred_at_utc', typed_payload->>'occurredAtUtc',
      'channel', typed_payload->>'channel',
      'reach_count', (typed_payload->>'reachCount')::integer,
      'interest_level', (typed_payload->>'interestLevel')::integer
    )
  );

  RETURN QUERY SELECT 'accepted', accepted_cursor::text, NULL::text;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_submit(
    uuid,
    text,
    integer,
    text,
    text,
    text,
    integer,
    jsonb
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.apply_contact_submit(
    uuid,
    text,
    integer,
    text,
    text,
    text,
    integer,
    jsonb
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.apply_contact_submit(
  uuid,
  text,
  integer,
  text,
  text,
  text,
  integer,
  jsonb
) IS
  'Backend-only idempotent contact submission after JWT and context checks.';

CREATE OR REPLACE FUNCTION app_data.pull_contact_changes(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  client_after_cursor text,
  batch_limit integer
)
RETURNS TABLE (
  server_cursor text,
  change_type text,
  revision_number integer,
  contact_payload jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  after_sequence bigint := 0;
BEGIN
  IF trusted_app_user_id IS NULL
    OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL
    OR batch_limit < 1
    OR batch_limit > 100
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid contact pull scope or limit';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'contact pull scope is forbidden';
  END IF;

  IF client_after_cursor IS NOT NULL THEN
    SELECT feed.change_sequence
      INTO after_sequence
    FROM app_data.change_feed AS feed
    WHERE feed.cursor_token::text = client_after_cursor
      AND feed.app_user_id = trusted_app_user_id
      AND feed.workspace_id = trusted_workspace_id
      AND feed.project_id = trusted_project_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'sync cursor does not belong to the trusted scope';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    feed.cursor_token::text,
    feed.change_type,
    feed.revision_number,
    revision_row.snapshot || jsonb_build_object(
      'firstSubmittedAtUtc', contact_row.first_submitted_at_utc
    )
  FROM app_data.change_feed AS feed
  JOIN app_data.contacts AS contact_row
    ON contact_row.contact_id = feed.aggregate_id
  JOIN app_data.contact_revisions AS revision_row
    ON revision_row.contact_id = feed.aggregate_id
    AND revision_row.revision_number = feed.revision_number
  WHERE feed.app_user_id = trusted_app_user_id
    AND feed.workspace_id = trusted_workspace_id
    AND feed.project_id = trusted_project_id
    AND feed.change_sequence > after_sequence
  ORDER BY feed.change_sequence
  LIMIT batch_limit;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.pull_contact_changes(
    uuid,
    uuid,
    uuid,
    text,
    integer
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.pull_contact_changes(
    uuid,
    uuid,
    uuid,
    text,
    integer
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.pull_contact_changes(
  uuid,
  uuid,
  uuid,
  text,
  integer
) IS
  'Backend-only ordered change feed for one trusted personal scope.';
