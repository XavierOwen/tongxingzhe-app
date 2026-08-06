-- 0005_regions_and_private_draft_sync.sql
--
-- 保存带版本的严格区域树，并让未提交草稿只在同一 app_user_id 的设备间同步。
-- 草稿变化进入运行时 change feed，但不进入审计事实或分析仓库。

CREATE TABLE app_data.canonical_region_versions (
  region_id text NOT NULL CHECK (length(btrim(region_id)) > 0),
  tree_version text NOT NULL CHECK (length(btrim(tree_version)) > 0),
  parent_region_id text,
  canonical_name text NOT NULL CHECK (length(btrim(canonical_name)) > 0),
  kind text NOT NULL CHECK (
    kind IN (
      'country',
      'admin_area',
      'city',
      'district',
      'neighborhood',
      'street',
      'institution',
      'venue',
      'other'
    )
  ),
  attributes jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(attributes) = 'array'),
  PRIMARY KEY (region_id, tree_version),
  FOREIGN KEY (parent_region_id, tree_version)
    REFERENCES app_data.canonical_region_versions (region_id, tree_version)
    ON DELETE RESTRICT,
  CHECK (parent_region_id IS NULL OR parent_region_id <> region_id)
);

ALTER TABLE app_data.contacts
  ADD COLUMN region_tree_version text;

CREATE TABLE app_data.contact_region_assignments (
  contact_id text PRIMARY KEY
    REFERENCES app_data.contacts (contact_id) ON DELETE RESTRICT,
  region_id text NOT NULL,
  tree_version text NOT NULL,
  FOREIGN KEY (region_id, tree_version)
    REFERENCES app_data.canonical_region_versions (region_id, tree_version)
    ON DELETE RESTRICT
);

CREATE TABLE app_data.contact_drafts (
  draft_id text NOT NULL CHECK (length(btrim(draft_id)) > 0),
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  questionnaire_version_id uuid NOT NULL
    REFERENCES app_data.questionnaire_versions (questionnaire_version_id)
    ON DELETE RESTRICT,
  created_at_utc timestamptz NOT NULL,
  updated_at_utc timestamptz NOT NULL,
  deleted_at_utc timestamptz,
  current_revision integer NOT NULL CHECK (current_revision > 0),
  source_device_id text NOT NULL CHECK (length(btrim(source_device_id)) > 0),
  content jsonb NOT NULL CHECK (jsonb_typeof(content) = 'object'),
  PRIMARY KEY (app_user_id, draft_id),
  CHECK (updated_at_utc >= created_at_utc),
  CHECK (deleted_at_utc IS NULL OR deleted_at_utc >= created_at_utc)
);

CREATE INDEX contact_drafts_private_project
  ON app_data.contact_drafts (app_user_id, workspace_id, project_id)
  WHERE deleted_at_utc IS NULL;

ALTER TABLE app_data.change_feed
  DROP CONSTRAINT change_feed_change_type_check;

ALTER TABLE app_data.change_feed
  ADD CONSTRAINT change_feed_change_type_check CHECK (
    change_type IN (
      'contact.submitted',
      'contact.revised',
      'contact.voided',
      'draft.upserted',
      'draft.deleted'
    )
  ),
  ADD COLUMN change_payload jsonb,
  ADD CONSTRAINT change_feed_payload_shape CHECK (
    change_payload IS NULL OR jsonb_typeof(change_payload) = 'object'
  );

REVOKE ALL PRIVILEGES
  ON app_data.canonical_region_versions,
     app_data.contact_region_assignments,
     app_data.contact_drafts
  FROM tongxingzhe_runtime;

CREATE OR REPLACE FUNCTION app_data.reject_region_cycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NEW.parent_region_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    WITH RECURSIVE ancestors AS (
      SELECT region_row.region_id, region_row.parent_region_id
      FROM app_data.canonical_region_versions AS region_row
      WHERE region_row.region_id = NEW.parent_region_id
        AND region_row.tree_version = NEW.tree_version
      UNION
      SELECT parent_row.region_id, parent_row.parent_region_id
      FROM app_data.canonical_region_versions AS parent_row
      JOIN ancestors AS child_row
        ON parent_row.region_id = child_row.parent_region_id
      WHERE parent_row.tree_version = NEW.tree_version
    )
    SELECT 1
    FROM ancestors
    WHERE region_id = NEW.region_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'canonical region tree cannot contain a cycle';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER canonical_region_cycle_guard
BEFORE INSERT OR UPDATE OF parent_region_id, tree_version
ON app_data.canonical_region_versions
FOR EACH ROW
EXECUTE FUNCTION app_data.reject_region_cycle();

CREATE OR REPLACE FUNCTION app_data.capture_contact_region_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  location_value jsonb := NEW.snapshot->'location';
  region_id_value text;
  tree_version_value text;
BEGIN
  IF location_value->>'kind' IS DISTINCT FROM 'resolved' THEN
    UPDATE app_data.contacts
    SET region_tree_version = NULL
    WHERE contact_id = NEW.contact_id;
    DELETE FROM app_data.contact_region_assignments
    WHERE contact_id = NEW.contact_id;
    RETURN NEW;
  END IF;
  region_id_value := location_value->>'smallestRegionId';
  tree_version_value := location_value->>'regionTreeVersion';
  IF region_id_value IS NULL OR tree_version_value IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'resolved contact requires a region tree version';
  END IF;
  IF NOT EXISTS (
    WITH RECURSIVE ancestors AS (
      SELECT region_row.region_id, region_row.parent_region_id,
        region_row.kind
      FROM app_data.canonical_region_versions AS region_row
      WHERE region_row.region_id = region_id_value
        AND region_row.tree_version = tree_version_value
      UNION
      SELECT parent_row.region_id, parent_row.parent_region_id,
        parent_row.kind
      FROM app_data.canonical_region_versions AS parent_row
      JOIN ancestors AS child_row
        ON parent_row.region_id = child_row.parent_region_id
      WHERE parent_row.tree_version = tree_version_value
    )
    SELECT 1
    FROM ancestors
    WHERE kind = 'city'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'resolved contact region requires a city ancestor';
  END IF;
  UPDATE app_data.contacts
  SET region_tree_version = tree_version_value
  WHERE contact_id = NEW.contact_id;
  INSERT INTO app_data.contact_region_assignments (
    contact_id,
    region_id,
    tree_version
  ) VALUES (
    NEW.contact_id,
    region_id_value,
    tree_version_value
  )
  ON CONFLICT (contact_id) DO UPDATE
  SET region_id = EXCLUDED.region_id,
      tree_version = EXCLUDED.tree_version;
  RETURN NEW;
END
$function$;

CREATE TRIGGER contact_revision_region_assignment
AFTER INSERT ON app_data.contact_revisions
FOR EACH ROW
EXECUTE FUNCTION app_data.capture_contact_region_assignment();

CREATE OR REPLACE FUNCTION app_data.apply_draft_upsert(
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
  payload_draft_id text;
  payload_workspace_id uuid;
  payload_project_id uuid;
  payload_questionnaire_version_id uuid;
  existing_revision integer;
  existing_workspace_id uuid;
  existing_project_id uuid;
  existing_questionnaire_version_id uuid;
  accepted_revision integer;
  accepted_cursor uuid;
  feed_payload jsonb;
BEGIN
  IF trusted_app_user_id IS NULL
    OR length(btrim(client_command_id)) = 0
    OR length(btrim(client_device_id)) = 0
    OR length(btrim(client_aggregate_id)) = 0
    OR client_protocol_version <> 1
    OR client_command_type <> 'draft.upsert.v1'
    OR client_base_revision < 0
    OR jsonb_typeof(typed_payload) <> 'object'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid draft envelope';
  END IF;

  IF typed_payload ? 'appUserId' OR typed_payload ? 'app_user_id' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'client draft payload must not contain app user identity';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(trusted_app_user_id::text || ':' || client_command_id, 0)
  );

  SELECT processed.result_code, processed.server_cursor, processed.failure_code
    INTO existing_result_code, existing_server_cursor, existing_failure_code
  FROM app_data.processed_commands AS processed
  WHERE processed.app_user_id = trusted_app_user_id
    AND processed.command_id = client_command_id;
  IF FOUND THEN
    RETURN QUERY SELECT
      CASE WHEN existing_result_code = 'accepted' THEN 'duplicate'
        ELSE existing_result_code END,
      existing_server_cursor::text,
      existing_failure_code;
    RETURN;
  END IF;

  payload_draft_id := typed_payload->>'draftId';
  payload_workspace_id := (typed_payload->>'workspaceId')::uuid;
  payload_project_id := (typed_payload->>'projectId')::uuid;
  payload_questionnaire_version_id :=
    (typed_payload->>'questionnaireVersionId')::uuid;
  IF payload_draft_id IS NULL OR payload_draft_id <> client_aggregate_id THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'draft IDs differ';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    JOIN app_data.questionnaire_versions AS version_row
      ON version_row.project_id = project_row.project_id
    WHERE workspace_row.workspace_id = payload_workspace_id
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = payload_project_id
      AND project_row.status = 'active'
      AND version_row.questionnaire_version_id =
        payload_questionnaire_version_id
      AND version_row.status = 'published'
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
    hashtextextended(trusted_app_user_id::text || ':draft:' || payload_draft_id, 0)
  );
  SELECT current_revision, workspace_id, project_id, questionnaire_version_id
    INTO existing_revision, existing_workspace_id, existing_project_id,
      existing_questionnaire_version_id
  FROM app_data.contact_drafts
  WHERE draft_id = payload_draft_id
    AND app_user_id = trusted_app_user_id
  FOR UPDATE;

  IF FOUND AND (
    existing_workspace_id IS DISTINCT FROM payload_workspace_id
    OR existing_project_id IS DISTINCT FROM payload_project_id
    OR existing_questionnaire_version_id IS DISTINCT FROM
      payload_questionnaire_version_id
  ) THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'draft_scope_conflict'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'draft_scope_conflict';
    RETURN;
  END IF;

  IF (FOUND AND existing_revision <> client_base_revision)
    OR (NOT FOUND AND client_base_revision <> 0)
  THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'draft_revision_conflict'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'draft_revision_conflict';
    RETURN;
  END IF;

  accepted_revision := client_base_revision + 1;
  INSERT INTO app_data.contact_drafts (
    draft_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, created_at_utc, updated_at_utc,
    current_revision, source_device_id, content
  ) VALUES (
    payload_draft_id, trusted_app_user_id, payload_workspace_id,
    payload_project_id, payload_questionnaire_version_id,
    (typed_payload->>'createdAtUtc')::timestamptz,
    (typed_payload->>'updatedAtUtc')::timestamptz,
    accepted_revision, client_device_id, typed_payload
  )
  ON CONFLICT (app_user_id, draft_id) DO UPDATE
  SET updated_at_utc = EXCLUDED.updated_at_utc,
      deleted_at_utc = NULL,
      questionnaire_version_id = EXCLUDED.questionnaire_version_id,
      current_revision = EXCLUDED.current_revision,
      source_device_id = EXCLUDED.source_device_id,
      content = EXCLUDED.content;

  accepted_cursor := gen_random_uuid();
  feed_payload := typed_payload || jsonb_build_object(
    'serverRevision', accepted_revision,
    'sourceDeviceId', client_device_id
  );
  INSERT INTO app_data.change_feed (
    cursor_token, app_user_id, workspace_id, project_id, aggregate_id,
    revision_number, change_type, change_payload
  ) VALUES (
    accepted_cursor, trusted_app_user_id, payload_workspace_id,
    payload_project_id, payload_draft_id, accepted_revision,
    'draft.upserted', feed_payload
  );
  INSERT INTO app_data.processed_commands (
    app_user_id, command_id, protocol_version, command_type, device_id,
    aggregate_id, result_code, server_cursor
  ) VALUES (
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    'accepted', accepted_cursor
  );
  RETURN QUERY SELECT 'accepted', accepted_cursor::text, NULL::text;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.apply_draft_delete(
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
  payload_draft_id text;
  payload_workspace_id uuid;
  payload_project_id uuid;
  existing_revision integer;
  existing_workspace_id uuid;
  existing_project_id uuid;
  accepted_revision integer;
  accepted_cursor uuid;
BEGIN
  IF trusted_app_user_id IS NULL
    OR length(btrim(client_command_id)) = 0
    OR length(btrim(client_device_id)) = 0
    OR length(btrim(client_aggregate_id)) = 0
    OR client_protocol_version <> 1
    OR client_command_type <> 'draft.delete.v1'
    OR client_base_revision < 0
    OR jsonb_typeof(typed_payload) <> 'object'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid draft delete';
  END IF;

  IF typed_payload ? 'appUserId' OR typed_payload ? 'app_user_id' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'client draft payload must not contain app user identity';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(trusted_app_user_id::text || ':' || client_command_id, 0)
  );
  SELECT processed.result_code, processed.server_cursor, processed.failure_code
    INTO existing_result_code, existing_server_cursor, existing_failure_code
  FROM app_data.processed_commands AS processed
  WHERE processed.app_user_id = trusted_app_user_id
    AND processed.command_id = client_command_id;
  IF FOUND THEN
    RETURN QUERY SELECT
      CASE WHEN existing_result_code = 'accepted' THEN 'duplicate'
        ELSE existing_result_code END,
      existing_server_cursor::text,
      existing_failure_code;
    RETURN;
  END IF;

  payload_draft_id := typed_payload->>'draftId';
  payload_workspace_id := (typed_payload->>'workspaceId')::uuid;
  payload_project_id := (typed_payload->>'projectId')::uuid;
  IF payload_draft_id IS NULL OR payload_draft_id <> client_aggregate_id THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'draft IDs differ';
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
    hashtextextended(trusted_app_user_id::text || ':draft:' || payload_draft_id, 0)
  );
  SELECT current_revision, workspace_id, project_id
    INTO existing_revision, existing_workspace_id, existing_project_id
  FROM app_data.contact_drafts
  WHERE draft_id = payload_draft_id
    AND app_user_id = trusted_app_user_id
  FOR UPDATE;
  IF FOUND AND (
    existing_workspace_id IS DISTINCT FROM payload_workspace_id
    OR existing_project_id IS DISTINCT FROM payload_project_id
  ) THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'draft_scope_conflict'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'draft_scope_conflict';
    RETURN;
  END IF;
  IF NOT FOUND OR existing_revision <> client_base_revision THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', 'draft_revision_conflict'
    );
    RETURN QUERY SELECT 'conflict', NULL::text, 'draft_revision_conflict';
    RETURN;
  END IF;

  accepted_revision := client_base_revision + 1;
  UPDATE app_data.contact_drafts
  SET current_revision = accepted_revision,
      source_device_id = client_device_id,
      updated_at_utc = GREATEST(clock_timestamp(), created_at_utc),
      deleted_at_utc = GREATEST(clock_timestamp(), created_at_utc)
  WHERE draft_id = payload_draft_id
    AND app_user_id = trusted_app_user_id;
  accepted_cursor := gen_random_uuid();
  INSERT INTO app_data.change_feed (
    cursor_token, app_user_id, workspace_id, project_id, aggregate_id,
    revision_number, change_type, change_payload
  ) VALUES (
    accepted_cursor, trusted_app_user_id, payload_workspace_id,
    payload_project_id, payload_draft_id, accepted_revision, 'draft.deleted',
    jsonb_build_object(
      'draftId', payload_draft_id,
      'workspaceId', payload_workspace_id,
      'projectId', payload_project_id,
      'serverRevision', accepted_revision,
      'sourceDeviceId', client_device_id
    )
  );
  INSERT INTO app_data.processed_commands (
    app_user_id, command_id, protocol_version, command_type, device_id,
    aggregate_id, result_code, server_cursor
  ) VALUES (
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    'accepted', accepted_cursor
  );
  RETURN QUERY SELECT 'accepted', accepted_cursor::text, NULL::text;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.pull_sync_changes(
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
  typed_payload jsonb
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
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid sync pull';
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
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'sync scope forbidden';
  END IF;
  IF client_after_cursor IS NOT NULL THEN
    SELECT change_sequence INTO after_sequence
    FROM app_data.change_feed
    WHERE cursor_token::text = client_after_cursor
      AND app_user_id = trusted_app_user_id
      AND workspace_id = trusted_workspace_id
      AND project_id = trusted_project_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid sync cursor';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    feed.cursor_token::text,
    feed.change_type,
    feed.revision_number,
    COALESCE(
      feed.change_payload,
      revision_row.snapshot || jsonb_build_object(
        'firstSubmittedAtUtc', contact_row.first_submitted_at_utc
      )
    )
  FROM app_data.change_feed AS feed
  LEFT JOIN app_data.contacts AS contact_row
    ON contact_row.contact_id = feed.aggregate_id
  LEFT JOIN app_data.contact_revisions AS revision_row
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
  ON FUNCTION app_data.reject_region_cycle(),
     app_data.capture_contact_region_assignment(),
     app_data.apply_draft_upsert(uuid, text, integer, text, text, text, integer, jsonb),
     app_data.apply_draft_delete(uuid, text, integer, text, text, text, integer, jsonb),
     app_data.pull_sync_changes(uuid, uuid, uuid, text, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.apply_draft_upsert(uuid, text, integer, text, text, text, integer, jsonb),
     app_data.apply_draft_delete(uuid, text, integer, text, text, text, integer, jsonb),
     app_data.pull_sync_changes(uuid, uuid, uuid, text, integer)
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.contact_drafts IS
  'Private unfinished contact state; never used for contact analytics.';
COMMENT ON FUNCTION app_data.pull_sync_changes(uuid, uuid, uuid, text, integer)
  IS 'Backend-only contact and private-draft feed for one trusted scope.';
