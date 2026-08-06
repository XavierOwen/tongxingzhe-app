-- 0009_contact_revisions.sql
--
-- 把接触更正和作废保存为追加 revision。客户端只能提交带 base revision 的
-- 命令；服务端在同一事务中校验归属、追加历史、更新当前投影并写入同步、
-- 审计和分析事件。

ALTER TABLE app_data.contact_revisions
  ADD COLUMN revision_kind text NOT NULL DEFAULT 'submitted',
  ADD COLUMN reason text;

-- 早期合成夹具曾直接插入 revision 2。升级时给这些证据一个明确类型和原因，
-- 不删除也不改写其 snapshot。
UPDATE app_data.contact_revisions
SET revision_kind = 'corrected',
    reason = 'Legacy revision imported during schema upgrade'
WHERE revision_number > 1;

ALTER TABLE app_data.contact_revisions
  ADD CONSTRAINT contact_revisions_kind_valid CHECK (
    revision_kind IN ('submitted', 'corrected', 'voided')
  ),
  ADD CONSTRAINT contact_revisions_reason_valid CHECK (
    (
      revision_number = 1
      AND revision_kind = 'submitted'
      AND reason IS NULL
    )
    OR
    (
      revision_number > 1
      AND revision_kind IN ('corrected', 'voided')
      AND reason IS NOT NULL
      AND length(btrim(reason)) > 0
    )
  );

ALTER TABLE app_data.contact_audit_events
  DROP CONSTRAINT contact_audit_events_event_type_check,
  ADD COLUMN revision_number integer NOT NULL DEFAULT 1
    CHECK (revision_number > 0),
  ADD CONSTRAINT contact_audit_events_event_type_check CHECK (
    event_type IN ('contact.submitted', 'contact.revised', 'contact.voided')
  );

ALTER TABLE app_data.warehouse_outbox
  DROP CONSTRAINT warehouse_outbox_event_type_check,
  DROP CONSTRAINT warehouse_outbox_contact_id_event_type_key,
  ADD COLUMN revision_number integer NOT NULL DEFAULT 1
    CHECK (revision_number > 0),
  ADD CONSTRAINT warehouse_outbox_event_type_check CHECK (
    event_type IN ('contact.submitted', 'contact.revised', 'contact.voided')
  ),
  ADD CONSTRAINT warehouse_outbox_contact_event_revision_key UNIQUE (
    contact_id,
    event_type,
    revision_number
  );

CREATE OR REPLACE FUNCTION app_data.apply_contact_revision_command(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb,
  requested_kind text
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
  reason_value text;
  current_contact app_data.contacts%ROWTYPE;
  previous_snapshot jsonb;
  revision_snapshot jsonb;
  accepted_revision integer;
  accepted_cursor uuid;
  revised_at timestamptz := clock_timestamp();
  change_type_value text;
BEGIN
  IF trusted_app_user_id IS NULL
    OR client_command_id IS NULL
    OR length(btrim(client_command_id)) = 0
    OR client_device_id IS NULL
    OR length(btrim(client_device_id)) = 0
    OR client_aggregate_id IS NULL
    OR length(btrim(client_aggregate_id)) = 0
    OR client_protocol_version <> 1
    OR client_base_revision < 1
    OR jsonb_typeof(typed_payload) <> 'object'
    OR requested_kind NOT IN ('corrected', 'voided')
    OR (
      requested_kind = 'corrected'
      AND client_command_type <> 'contact.revise.v1'
    )
    OR (
      requested_kind = 'voided'
      AND client_command_type <> 'contact.void.v1'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid contact revision envelope';
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
  reason_value := NULLIF(btrim(typed_payload->>'reason'), '');

  IF payload_contact_id IS NULL
    OR payload_contact_id <> client_aggregate_id
    OR payload_workspace_id IS NULL
    OR payload_project_id IS NULL
    OR reason_value IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid contact revision payload';
  END IF;

  IF requested_kind = 'corrected'
    AND (
      jsonb_typeof(typed_payload->'location') <> 'object'
      OR jsonb_typeof(typed_payload->'answers') <> 'array'
      OR NULLIF(typed_payload->>'occurredAtUtc', '') IS NULL
      OR NULLIF(typed_payload->>'occurredTimeZone', '') IS NULL
      OR NULLIF(typed_payload->>'channel', '') IS NULL
      OR NULLIF(typed_payload->>'reachCount', '') IS NULL
      OR NULLIF(typed_payload->>'interestLevel', '') IS NULL
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'corrected contact requires a complete snapshot';
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
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'forbidden', 'project_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'project_forbidden';
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('contact:' || payload_contact_id, 0)
  );
  SELECT * INTO current_contact
  FROM app_data.contacts AS contact_row
  WHERE contact_row.contact_id = payload_contact_id
  FOR UPDATE;

  IF NOT FOUND
    OR current_contact.app_user_id <> trusted_app_user_id
    OR current_contact.workspace_id <> payload_workspace_id
    OR current_contact.project_id <> payload_project_id
  THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'forbidden', 'contact_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'contact_forbidden';
    RETURN;
  END IF;

  IF current_contact.lifecycle_status = 'voided' THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'contact_already_voided'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'contact_already_voided';
    RETURN;
  END IF;

  IF current_contact.current_revision <> client_base_revision THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'contact_revision_conflict'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'contact_revision_conflict';
    RETURN;
  END IF;

  accepted_revision := client_base_revision + 1;
  IF requested_kind = 'corrected' THEN
    revision_snapshot := typed_payload || jsonb_build_object(
      'questionnaireVersionId', current_contact.questionnaire_version_id,
      'firstSubmittedAtUtc', current_contact.first_submitted_at_utc,
      'revisionKind', 'corrected',
      'revisedAtUtc', revised_at
    );
  ELSE
    SELECT revision_row.snapshot INTO previous_snapshot
    FROM app_data.contact_revisions AS revision_row
    WHERE revision_row.contact_id = payload_contact_id
      AND revision_row.revision_number = client_base_revision;
    revision_snapshot := previous_snapshot || jsonb_build_object(
      'reason', reason_value,
      'firstSubmittedAtUtc', current_contact.first_submitted_at_utc,
      'revisionKind', 'voided',
      'revisedAtUtc', revised_at
    );
  END IF;

  INSERT INTO app_data.contact_revisions (
    contact_id,
    revision_number,
    revision_kind,
    revised_by_app_user_id,
    revised_at_utc,
    reason,
    snapshot
  ) VALUES (
    payload_contact_id,
    accepted_revision,
    requested_kind,
    trusted_app_user_id,
    revised_at,
    reason_value,
    revision_snapshot
  );

  IF requested_kind = 'corrected' THEN
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
      accepted_revision,
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

    UPDATE app_data.contacts
    SET occurred_at_utc = (typed_payload->>'occurredAtUtc')::timestamptz,
        occurred_time_zone = typed_payload->>'occurredTimeZone',
        channel = typed_payload->>'channel',
        channel_detail = NULLIF(typed_payload->>'channelDetail', ''),
        location_kind = typed_payload->'location'->>'kind',
        place_name = NULLIF(typed_payload->'location'->>'placeName', ''),
        smallest_region_id = NULLIF(
          typed_payload->'location'->>'smallestRegionId',
          ''
        ),
        latitude = (
          typed_payload->'location'->>'latitude'
        )::double precision,
        longitude = (
          typed_payload->'location'->>'longitude'
        )::double precision,
        location_accuracy_meters = (
          typed_payload->'location'->>'accuracyMeters'
        )::double precision,
        reach_count = (typed_payload->>'reachCount')::integer,
        interest_level = (typed_payload->>'interestLevel')::integer,
        current_revision = accepted_revision
    WHERE contact_id = payload_contact_id;
    change_type_value := 'contact.revised';
  ELSE
    INSERT INTO app_data.contact_answers (
      contact_id,
      revision_number,
      question_id,
      answer_state,
      answer_type,
      boolean_value
    )
    SELECT
      answer_row.contact_id,
      accepted_revision,
      answer_row.question_id,
      answer_row.answer_state,
      answer_row.answer_type,
      answer_row.boolean_value
    FROM app_data.contact_answers AS answer_row
    WHERE answer_row.contact_id = payload_contact_id
      AND answer_row.revision_number = client_base_revision;

    UPDATE app_data.contacts
    SET current_revision = accepted_revision,
        lifecycle_status = 'voided'
    WHERE contact_id = payload_contact_id;
    change_type_value := 'contact.voided';
  END IF;

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
    payload_contact_id,
    accepted_revision,
    change_type_value,
    revision_snapshot
  );

  INSERT INTO app_data.processed_commands (
    app_user_id, command_id, protocol_version, command_type, device_id,
    aggregate_id, result_code, server_cursor
  ) VALUES (
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    'accepted', accepted_cursor
  );

  INSERT INTO app_data.contact_audit_events (
    app_user_id,
    command_id,
    contact_id,
    revision_number,
    event_type
  ) VALUES (
    trusted_app_user_id,
    client_command_id,
    payload_contact_id,
    accepted_revision,
    change_type_value
  );

  INSERT INTO app_data.warehouse_outbox (
    contact_id,
    project_id,
    revision_number,
    event_type,
    analytics_payload
  ) VALUES (
    payload_contact_id,
    payload_project_id,
    accepted_revision,
    change_type_value,
    revision_snapshot || jsonb_build_object(
      'contact_id', payload_contact_id,
      'project_id', payload_project_id,
      'revision_number', accepted_revision,
      'lifecycle_status', CASE
        WHEN requested_kind = 'voided' THEN 'voided'
        ELSE 'active'
      END
    )
  );

  RETURN QUERY SELECT 'accepted', accepted_cursor::text, NULL::text;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.apply_contact_revise(
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
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT *
  FROM app_data.apply_contact_revision_command(
    trusted_app_user_id,
    client_command_id,
    client_protocol_version,
    client_command_type,
    client_device_id,
    client_aggregate_id,
    client_base_revision,
    typed_payload,
    'corrected'
  );
$function$;

CREATE OR REPLACE FUNCTION app_data.apply_contact_void(
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
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT *
  FROM app_data.apply_contact_revision_command(
    trusted_app_user_id,
    client_command_id,
    client_protocol_version,
    client_command_type,
    client_device_id,
    client_aggregate_id,
    client_base_revision,
    typed_payload,
    'voided'
  );
$function$;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_revision_command(
    uuid, text, integer, text, text, text, integer, jsonb, text
  )
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_revise(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_void(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.apply_contact_revise(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.apply_contact_void(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.apply_contact_revise(
  uuid, text, integer, text, text, text, integer, jsonb
) IS
  'Backend-only idempotent append-only correction for one owned contact.';

COMMENT ON FUNCTION app_data.apply_contact_void(
  uuid, text, integer, text, text, text, integer, jsonb
) IS
  'Backend-only idempotent append-only void for one owned contact.';
