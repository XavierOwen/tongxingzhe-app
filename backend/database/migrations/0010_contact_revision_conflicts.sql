-- 0010_contact_revision_conflicts.sql
--
-- 对同一 base revision 的并发更正做三路比较。不同事实组自动合并并追加
-- revision；同一事实组的分叉保存双方快照，等待有权用户提交新的解决 revision。

CREATE TABLE app_data.contact_revision_conflicts (
  conflict_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  command_id text NOT NULL,
  contact_id text NOT NULL
    REFERENCES app_data.contacts (contact_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  base_revision integer NOT NULL CHECK (base_revision > 0),
  current_revision integer NOT NULL CHECK (current_revision > base_revision),
  conflicting_fields text[] NOT NULL CHECK (
    cardinality(conflicting_fields) > 0
  ),
  base_snapshot jsonb NOT NULL CHECK (jsonb_typeof(base_snapshot) = 'object'),
  current_snapshot jsonb NOT NULL
    CHECK (jsonb_typeof(current_snapshot) = 'object'),
  proposed_snapshot jsonb NOT NULL
    CHECK (jsonb_typeof(proposed_snapshot) = 'object'),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'resolved')),
  resolution_command_id text,
  resolution_revision integer CHECK (resolution_revision > 0),
  created_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  resolved_at_utc timestamptz,
  UNIQUE (app_user_id, command_id),
  CONSTRAINT contact_revision_conflict_resolution_shape CHECK (
    (
      status = 'pending'
      AND resolution_command_id IS NULL
      AND resolution_revision IS NULL
      AND resolved_at_utc IS NULL
    )
    OR
    (
      status = 'resolved'
      AND resolution_command_id IS NOT NULL
      AND length(btrim(resolution_command_id)) > 0
      AND resolution_revision IS NOT NULL
      AND resolved_at_utc IS NOT NULL
    )
  )
);

REVOKE ALL PRIVILEGES
  ON app_data.contact_revision_conflicts
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.contact_revision_comparison_value(
  snapshot jsonb,
  field_name text
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
  SELECT CASE field_name
    WHEN 'occurredAt' THEN jsonb_build_array(
      snapshot->'occurredAtUtc', snapshot->'occurredTimeZone'
    )
    WHEN 'channel' THEN jsonb_build_array(
      snapshot->'channel', snapshot->'channelDetail'
    )
    WHEN 'location' THEN snapshot->'location'
    WHEN 'reachCount' THEN snapshot->'reachCount'
    WHEN 'interestLevel' THEN snapshot->'interestLevel'
    WHEN 'answers' THEN COALESCE(
      (
        SELECT jsonb_object_agg(
          answer->>'questionId',
          answer - 'questionId'
          ORDER BY answer->>'questionId'
        )
        FROM jsonb_array_elements(COALESCE(snapshot->'answers', '[]'::jsonb))
          AS answer_row(answer)
      ),
      '{}'::jsonb
    )
    ELSE 'null'::jsonb
  END;
$function$;

CREATE FUNCTION app_data.contact_revision_changed_fields(
  base_snapshot jsonb,
  candidate_snapshot jsonb
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
  SELECT COALESCE(array_agg(field_name ORDER BY ordinal), ARRAY[]::text[])
  FROM unnest(ARRAY[
    'occurredAt',
    'channel',
    'location',
    'reachCount',
    'interestLevel',
    'answers'
  ]) WITH ORDINALITY AS field_row(field_name, ordinal)
  WHERE app_data.contact_revision_comparison_value(
      base_snapshot,
      field_name
    ) IS DISTINCT FROM app_data.contact_revision_comparison_value(
      candidate_snapshot,
      field_name
    );
$function$;

CREATE FUNCTION app_data.merge_contact_revision_snapshots(
  current_snapshot jsonb,
  proposed_snapshot jsonb,
  proposed_changed_fields text[]
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  merged_snapshot jsonb := current_snapshot;
BEGIN
  IF 'occurredAt' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'occurredAtUtc', proposed_snapshot->'occurredAtUtc',
      'occurredTimeZone', proposed_snapshot->'occurredTimeZone'
    );
  END IF;
  IF 'channel' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'channel', proposed_snapshot->'channel',
      'channelDetail', proposed_snapshot->'channelDetail'
    );
  END IF;
  IF 'location' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'location', proposed_snapshot->'location'
    );
  END IF;
  IF 'reachCount' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'reachCount', proposed_snapshot->'reachCount'
    );
  END IF;
  IF 'interestLevel' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'interestLevel', proposed_snapshot->'interestLevel'
    );
  END IF;
  IF 'answers' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'answers', proposed_snapshot->'answers'
    );
  END IF;
  RETURN merged_snapshot;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.contact_revision_comparison_value(jsonb, text),
  app_data.contact_revision_changed_fields(jsonb, jsonb),
  app_data.merge_contact_revision_snapshots(jsonb, jsonb, text[])
  FROM PUBLIC, tongxingzhe_runtime;

-- 保留 0009 的严格实现作为受保护 helper；runtime 只能进入下面的新包装函数。
ALTER FUNCTION app_data.apply_contact_revise(
  uuid, text, integer, text, text, text, integer, jsonb
) RENAME TO apply_contact_revise_strict;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_revise_strict(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_data.apply_contact_revise(
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
  payload_contact_id text;
  payload_workspace_id uuid;
  payload_project_id uuid;
  current_contact app_data.contacts%ROWTYPE;
  base_snapshot_value jsonb;
  current_snapshot_value jsonb;
  proposed_changed_fields text[];
  server_changed_fields text[];
  overlapping_fields text[];
  merged_payload jsonb;
BEGIN
  IF trusted_app_user_id IS NULL
    OR client_command_id IS NULL
    OR length(btrim(client_command_id)) = 0
    OR client_device_id IS NULL
    OR length(btrim(client_device_id)) = 0
    OR client_aggregate_id IS NULL
    OR length(btrim(client_aggregate_id)) = 0
    OR client_protocol_version <> 1
    OR client_command_type <> 'contact.revise.v1'
    OR client_base_revision < 1
    OR jsonb_typeof(typed_payload) <> 'object'
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

  IF EXISTS (
    SELECT 1 FROM app_data.processed_commands AS processed
    WHERE processed.app_user_id = trusted_app_user_id
      AND processed.command_id = client_command_id
  ) THEN
    RETURN QUERY SELECT *
    FROM app_data.apply_contact_revise_strict(
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      client_base_revision, typed_payload
    );
    RETURN;
  END IF;

  payload_contact_id := typed_payload->>'contactId';
  payload_workspace_id := (typed_payload->>'workspaceId')::uuid;
  payload_project_id := (typed_payload->>'projectId')::uuid;

  -- 完整的 shape、归属、项目状态和 lifecycle 校验仍由 0009 严格 helper 负责。
  -- 这里只在能证明是同一有权 active contact 的 stale revise 时做三路比较。
  IF payload_contact_id IS NULL
    OR payload_contact_id <> client_aggregate_id
    OR jsonb_typeof(typed_payload->'location') <> 'object'
    OR jsonb_typeof(typed_payload->'answers') <> 'array'
  THEN
    RETURN QUERY SELECT *
    FROM app_data.apply_contact_revise_strict(
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      client_base_revision, typed_payload
    );
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
    OR current_contact.lifecycle_status <> 'active'
    OR current_contact.current_revision = client_base_revision
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.workspaces AS workspace_row
      JOIN app_data.projects AS project_row
        ON project_row.workspace_id = workspace_row.workspace_id
      WHERE workspace_row.workspace_id = payload_workspace_id
        AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
        AND workspace_row.deleted_at IS NULL
        AND project_row.project_id = payload_project_id
        AND project_row.status = 'active'
    )
  THEN
    RETURN QUERY SELECT *
    FROM app_data.apply_contact_revise_strict(
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      client_base_revision, typed_payload
    );
    RETURN;
  END IF;

  SELECT revision_row.snapshot INTO base_snapshot_value
  FROM app_data.contact_revisions AS revision_row
  WHERE revision_row.contact_id = payload_contact_id
    AND revision_row.revision_number = client_base_revision;
  SELECT revision_row.snapshot INTO current_snapshot_value
  FROM app_data.contact_revisions AS revision_row
  WHERE revision_row.contact_id = payload_contact_id
    AND revision_row.revision_number = current_contact.current_revision;

  IF base_snapshot_value IS NULL OR current_snapshot_value IS NULL THEN
    RETURN QUERY SELECT *
    FROM app_data.apply_contact_revise_strict(
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      client_base_revision, typed_payload
    );
    RETURN;
  END IF;

  proposed_changed_fields := app_data.contact_revision_changed_fields(
    base_snapshot_value,
    typed_payload
  );
  server_changed_fields := app_data.contact_revision_changed_fields(
    base_snapshot_value,
    current_snapshot_value
  );
  SELECT COALESCE(array_agg(field_name ORDER BY field_name), ARRAY[]::text[])
    INTO overlapping_fields
  FROM unnest(proposed_changed_fields) AS proposed(field_name)
  WHERE field_name = ANY(server_changed_fields);

  IF cardinality(overlapping_fields) = 0 THEN
    merged_payload := app_data.merge_contact_revision_snapshots(
      current_snapshot_value,
      typed_payload,
      proposed_changed_fields
    ) || jsonb_build_object(
      'contactId', payload_contact_id,
      'workspaceId', payload_workspace_id,
      'projectId', payload_project_id,
      'reason', typed_payload->'reason'
    );
    RETURN QUERY SELECT *
    FROM app_data.apply_contact_revise_strict(
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      current_contact.current_revision, merged_payload
    );
    RETURN;
  END IF;

  INSERT INTO app_data.contact_revision_conflicts (
    app_user_id,
    command_id,
    contact_id,
    workspace_id,
    project_id,
    base_revision,
    current_revision,
    conflicting_fields,
    base_snapshot,
    current_snapshot,
    proposed_snapshot
  ) VALUES (
    trusted_app_user_id,
    client_command_id,
    payload_contact_id,
    payload_workspace_id,
    payload_project_id,
    client_base_revision,
    current_contact.current_revision,
    overlapping_fields,
    base_snapshot_value,
    current_snapshot_value,
    typed_payload
  );

  INSERT INTO app_data.processed_commands (
    app_user_id, command_id, protocol_version, command_type, device_id,
    aggregate_id, result_code, failure_code
  ) VALUES (
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    'conflict', 'contact_revision_conflict'
  );

  RETURN QUERY
  SELECT 'conflict', NULL::text, 'contact_revision_conflict';
END
$function$;

CREATE FUNCTION app_data.read_contact_revision_conflict(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  client_command_id text
)
RETURNS TABLE (conflict_payload jsonb)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'conflictId', conflict_row.conflict_id,
    'contactId', conflict_row.contact_id,
    'baseRevision', conflict_row.base_revision,
    'currentRevision', conflict_row.current_revision,
    'conflictingFields', to_jsonb(conflict_row.conflicting_fields),
    'questionnaireVersionId',
      conflict_row.current_snapshot->'questionnaireVersionId',
    'currentRevisionKind', conflict_row.current_snapshot->'revisionKind',
    'currentRevisedAtUtc', conflict_row.current_snapshot->'revisedAtUtc',
    'currentReason', conflict_row.current_snapshot->'reason',
    'currentSnapshot', jsonb_build_object(
      'occurredAtUtc', conflict_row.current_snapshot->'occurredAtUtc',
      'occurredTimeZone', conflict_row.current_snapshot->'occurredTimeZone',
      'channel', conflict_row.current_snapshot->'channel',
      'channelDetail', conflict_row.current_snapshot->'channelDetail',
      'location', conflict_row.current_snapshot->'location',
      'reachCount', conflict_row.current_snapshot->'reachCount',
      'interestLevel', conflict_row.current_snapshot->'interestLevel',
      'answers', conflict_row.current_snapshot->'answers'
    ),
    'proposedSnapshot', jsonb_build_object(
      'occurredAtUtc', conflict_row.proposed_snapshot->'occurredAtUtc',
      'occurredTimeZone', conflict_row.proposed_snapshot->'occurredTimeZone',
      'channel', conflict_row.proposed_snapshot->'channel',
      'channelDetail', conflict_row.proposed_snapshot->'channelDetail',
      'location', conflict_row.proposed_snapshot->'location',
      'reachCount', conflict_row.proposed_snapshot->'reachCount',
      'interestLevel', conflict_row.proposed_snapshot->'interestLevel',
      'answers', conflict_row.proposed_snapshot->'answers'
    )
  )
  FROM app_data.contact_revision_conflicts AS conflict_row
  WHERE conflict_row.app_user_id = trusted_app_user_id
    AND conflict_row.workspace_id = trusted_workspace_id
    AND conflict_row.project_id = trusted_project_id
    AND conflict_row.command_id = client_command_id;
$function$;

CREATE FUNCTION app_data.apply_contact_conflict_resolution(
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
  conflict_uuid uuid;
  conflict_row app_data.contact_revision_conflicts%ROWTYPE;
  strict_result record;
BEGIN
  IF trusted_app_user_id IS NULL
    OR client_command_type <> 'contact.resolve.v1'
    OR client_base_revision < 1
    OR jsonb_typeof(typed_payload) <> 'object'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid contact conflict resolution envelope';
  END IF;
  conflict_uuid := (typed_payload->>'conflictId')::uuid;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      trusted_app_user_id::text || ':' || client_command_id,
      0
    )
  );
  IF EXISTS (
    SELECT 1 FROM app_data.processed_commands AS processed
    WHERE processed.app_user_id = trusted_app_user_id
      AND processed.command_id = client_command_id
  ) THEN
    RETURN QUERY SELECT *
    FROM app_data.apply_contact_revise_strict(
      trusted_app_user_id, client_command_id, client_protocol_version,
      'contact.revise.v1', client_device_id, client_aggregate_id,
      client_base_revision, typed_payload - 'conflictId'
    );
    RETURN;
  END IF;

  SELECT * INTO conflict_row
  FROM app_data.contact_revision_conflicts AS stored_conflict
  WHERE stored_conflict.conflict_id = conflict_uuid
    AND stored_conflict.app_user_id = trusted_app_user_id
    AND stored_conflict.contact_id = client_aggregate_id
    AND stored_conflict.workspace_id = (typed_payload->>'workspaceId')::uuid
    AND stored_conflict.project_id = (typed_payload->>'projectId')::uuid
  FOR UPDATE;

  IF NOT FOUND OR conflict_row.status <> 'pending' THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'forbidden', 'conflict_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'conflict_forbidden';
    RETURN;
  END IF;

  SELECT * INTO strict_result
  FROM app_data.apply_contact_revise_strict(
    trusted_app_user_id, client_command_id, client_protocol_version,
    'contact.revise.v1', client_device_id, client_aggregate_id,
    client_base_revision, typed_payload - 'conflictId'
  );

  UPDATE app_data.processed_commands
  SET command_type = client_command_type
  WHERE app_user_id = trusted_app_user_id
    AND command_id = client_command_id;

  IF strict_result.result_code = 'accepted' THEN
    UPDATE app_data.contact_revision_conflicts
    SET status = 'resolved',
        resolution_command_id = client_command_id,
        resolution_revision = client_base_revision + 1,
        resolved_at_utc = clock_timestamp()
    WHERE conflict_id = conflict_uuid;
  END IF;

  RETURN QUERY SELECT
    strict_result.result_code::text,
    strict_result.server_cursor::text,
    strict_result.failure_code::text;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.apply_contact_revise(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.read_contact_revision_conflict(uuid, uuid, uuid, text),
  app_data.apply_contact_conflict_resolution(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.apply_contact_revise(
    uuid, text, integer, text, text, text, integer, jsonb
  ),
  app_data.read_contact_revision_conflict(uuid, uuid, uuid, text),
  app_data.apply_contact_conflict_resolution(
    uuid, text, integer, text, text, text, integer, jsonb
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.contact_revision_conflicts IS
  'Authorized same-field divergence; both snapshots remain after resolution.';
COMMENT ON FUNCTION app_data.apply_contact_revise(
  uuid, text, integer, text, text, text, integer, jsonb
) IS
  'Backend-only three-way contact correction with append-only auto-merge.';
COMMENT ON FUNCTION app_data.read_contact_revision_conflict(
  uuid, uuid, uuid, text
) IS
  'Returns one conflict comparison only inside its trusted user and project scope.';
COMMENT ON FUNCTION app_data.apply_contact_conflict_resolution(
  uuid, text, integer, text, text, text, integer, jsonb
) IS
  'Appends an idempotent resolution revision and preserves conflict history.';
