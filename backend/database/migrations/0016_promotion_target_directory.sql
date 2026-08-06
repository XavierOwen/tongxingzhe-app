-- 0016_promotion_target_directory.sql
--
-- 推广对象资料保持在 workspace 级对象表中。接触仍可独立匿名存在；本迁移
-- 不建立接触关联，也不把 PII 放入同步队列、日志或第二份 request document。

CREATE TABLE app_data.promotion_targets (
  promotion_target_id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  target_type text NOT NULL CHECK (target_type IN ('person', 'institution')),
  display_name text NOT NULL CHECK (
    length(btrim(display_name)) BETWEEN 1 AND 200
  ),
  phone text CHECK (
    phone IS NULL OR length(btrim(phone)) BETWEEN 1 AND 80
  ),
  email text CHECK (
    email IS NULL OR length(btrim(email)) BETWEEN 1 AND 320
  ),
  status text NOT NULL DEFAULT 'active' CHECK (
    status IN ('active', 'anonymized')
  ),
  created_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX promotion_targets_workspace_created
  ON app_data.promotion_targets (workspace_id, created_at DESC)
  WHERE status = 'active';

CREATE TABLE app_data.promotion_target_assignments (
  assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  assigned_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  assigned_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  end_reason text,
  CHECK (
    (ended_at IS NULL AND end_reason IS NULL)
    OR
    (ended_at IS NOT NULL
      AND length(btrim(end_reason)) BETWEEN 1 AND 500)
  )
);

CREATE UNIQUE INDEX promotion_target_one_active_assignment
  ON app_data.promotion_target_assignments (
    promotion_target_id,
    app_user_id
  ) WHERE ended_at IS NULL;

CREATE INDEX promotion_target_assignments_user_active
  ON app_data.promotion_target_assignments (app_user_id, promotion_target_id)
  WHERE ended_at IS NULL;

CREATE TABLE app_data.promotion_target_creation_requests (
  actor_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  request_id text NOT NULL CHECK (
    length(btrim(request_id)) BETWEEN 1 AND 120
  ),
  promotion_target_id uuid NOT NULL UNIQUE
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (actor_app_user_id, request_id)
);

CREATE TABLE app_data.promotion_target_access_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  promotion_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  actor_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  action text NOT NULL CHECK (action IN ('created', 'viewed')),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX promotion_target_access_target_time
  ON app_data.promotion_target_access_events (
    promotion_target_id,
    occurred_at DESC
  );

REVOKE ALL PRIVILEGES
  ON app_data.promotion_targets,
     app_data.promotion_target_assignments,
     app_data.promotion_target_creation_requests,
     app_data.promotion_target_access_events
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.reject_promotion_target_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'promotion target audit is append-only';
END
$function$;

CREATE TRIGGER promotion_target_creation_requests_immutable
BEFORE UPDATE OR DELETE ON app_data.promotion_target_creation_requests
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_audit_mutation();

CREATE TRIGGER promotion_target_access_events_immutable
BEFORE UPDATE OR DELETE ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_data.promotion_target_context_authorized(
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
     AND project_row.project_id = trusted_project_id
     AND project_row.status = 'active'
    JOIN app_data.app_users AS user_row
      ON user_row.app_user_id = trusted_app_user_id
     AND user_row.status = 'active'
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
  );
$function$;

CREATE FUNCTION app_data.promotion_target_document(
  requested_target_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'target_id', target_row.promotion_target_id,
    'target_type', target_row.target_type,
    'display_name', target_row.display_name,
    'phone', target_row.phone,
    'email', target_row.email,
    'created_at', target_row.created_at
  )
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = requested_target_id
    AND target_row.status = 'active';
$function$;

CREATE FUNCTION app_data.list_assigned_promotion_targets(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (target jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target access is forbidden';
  END IF;

  INSERT INTO app_data.promotion_target_access_events (
    workspace_id,
    promotion_target_id,
    actor_app_user_id,
    action
  )
  SELECT
    trusted_workspace_id,
    target_row.promotion_target_id,
    trusted_app_user_id,
    'viewed'
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active';

  RETURN QUERY
  SELECT app_data.promotion_target_document(target_row.promotion_target_id)
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active'
  ORDER BY target_row.created_at DESC, target_row.promotion_target_id;
END
$function$;

CREATE FUNCTION app_data.create_promotion_target(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_target_type text,
  requested_display_name text,
  requested_phone text,
  requested_email text,
  requested_request_id text
)
RETURNS TABLE (target jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_name text := btrim(requested_display_name);
  normalized_phone text := CASE
    WHEN requested_phone IS NULL THEN NULL
    ELSE btrim(requested_phone)
  END;
  normalized_email text := CASE
    WHEN requested_email IS NULL THEN NULL
    ELSE btrim(requested_email)
  END;
  normalized_request_id text := btrim(requested_request_id);
  replay_target app_data.promotion_targets%ROWTYPE;
  new_target_id uuid := gen_random_uuid();
BEGIN
  IF trusted_app_user_id IS NULL
    OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL
    OR requested_target_type IS NULL
    OR requested_target_type NOT IN ('person', 'institution')
    OR requested_display_name IS NULL
    OR length(normalized_name) NOT BETWEEN 1 AND 200
    OR (normalized_phone IS NOT NULL
      AND length(normalized_phone) NOT BETWEEN 1 AND 80)
    OR (normalized_email IS NOT NULL
      AND length(normalized_email) NOT BETWEEN 1 AND 320)
    OR requested_request_id IS NULL
    OR length(normalized_request_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid promotion target';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      trusted_app_user_id::text || ':' || normalized_request_id,
      0
    )
  );

  SELECT target_row.* INTO replay_target
  FROM app_data.promotion_target_creation_requests AS request_row
  JOIN app_data.promotion_targets AS target_row
    ON target_row.promotion_target_id = request_row.promotion_target_id
  WHERE request_row.actor_app_user_id = trusted_app_user_id
    AND request_row.request_id = normalized_request_id;
  IF FOUND THEN
    IF replay_target.workspace_id <> trusted_workspace_id
      OR replay_target.target_type <> requested_target_type
      OR replay_target.display_name <> normalized_name
      OR replay_target.phone IS DISTINCT FROM normalized_phone
      OR replay_target.email IS DISTINCT FROM normalized_email
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'promotion target request conflict';
    END IF;
    RETURN QUERY SELECT app_data.promotion_target_document(
      replay_target.promotion_target_id
    );
    RETURN;
  END IF;

  INSERT INTO app_data.promotion_targets (
    promotion_target_id,
    workspace_id,
    target_type,
    display_name,
    phone,
    email,
    created_by_app_user_id
  ) VALUES (
    new_target_id,
    trusted_workspace_id,
    requested_target_type,
    normalized_name,
    normalized_phone,
    normalized_email,
    trusted_app_user_id
  );

  INSERT INTO app_data.promotion_target_assignments (
    promotion_target_id,
    app_user_id,
    assigned_by_app_user_id
  ) VALUES (
    new_target_id,
    trusted_app_user_id,
    trusted_app_user_id
  );

  INSERT INTO app_data.promotion_target_creation_requests (
    actor_app_user_id,
    request_id,
    promotion_target_id
  ) VALUES (
    trusted_app_user_id,
    normalized_request_id,
    new_target_id
  );

  INSERT INTO app_data.promotion_target_access_events (
    workspace_id,
    promotion_target_id,
    actor_app_user_id,
    action
  ) VALUES (
    trusted_workspace_id,
    new_target_id,
    trusted_app_user_id,
    'created'
  );

  RETURN QUERY SELECT app_data.promotion_target_document(
    new_target_id
  );
END
$function$;

-- 个人空间所有者拥有按需创建对象和查看本人当前分配对象的能力。组织成员
-- 能力仍由 Slice 7 的成员关系表决定，不能从此个人所有权规则推断。
CREATE OR REPLACE FUNCTION app_data.list_personal_project_contexts(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (
  app_user_id uuid,
  workspace_id uuid,
  workspace_kind text,
  workspace_name text,
  project_id uuid,
  project_name text,
  questionnaire_version_id uuid,
  questionnaire_version_number integer,
  capabilities text[],
  is_current boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  resolved_project_id uuid;
BEGIN
  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = identity_row.app_user_id
   AND user_row.status = 'active'
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject;
  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'trusted identity is not mapped to an active app user';
  END IF;
  SELECT workspace_row.workspace_id INTO STRICT resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = resolved_app_user_id
    AND workspace_row.deleted_at IS NULL;
  SELECT current_row.project_id INTO resolved_project_id
  FROM app_data.user_current_projects AS current_row
  JOIN app_data.projects AS project_row
    ON project_row.project_id = current_row.project_id
   AND project_row.workspace_id = resolved_workspace_id
   AND project_row.status = 'active'
  WHERE current_row.app_user_id = resolved_app_user_id;
  IF resolved_project_id IS NULL THEN
    SELECT project_row.project_id INTO STRICT resolved_project_id
    FROM app_data.projects AS project_row
    WHERE project_row.workspace_id = resolved_workspace_id
      AND project_row.is_personal_default
      AND project_row.status = 'active';
    INSERT INTO app_data.user_current_projects (app_user_id, project_id)
    VALUES (resolved_app_user_id, resolved_project_id)
    ON CONFLICT ON CONSTRAINT user_current_projects_pkey DO UPDATE
      SET project_id = EXCLUDED.project_id,
          updated_at = clock_timestamp();
  END IF;
  RETURN QUERY
  SELECT
    resolved_app_user_id,
    workspace_row.workspace_id,
    workspace_row.workspace_kind,
    workspace_row.display_name,
    project_row.project_id,
    project_row.display_name,
    version_row.questionnaire_version_id,
    version_row.version_number,
    ARRAY[
      'record_contact',
      'manage_analysis_definitions',
      'create_target',
      'view_assigned_target_pii'
    ]::text[],
    project_row.project_id = resolved_project_id
  FROM app_data.workspaces AS workspace_row
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
   AND project_row.status = 'active'
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.project_id = project_row.project_id
   AND version_row.is_current
   AND version_row.status = 'published'
  WHERE workspace_row.workspace_id = resolved_workspace_id
  ORDER BY
    (project_row.project_id = resolved_project_id) DESC,
    project_row.is_personal_default DESC,
    project_row.created_at,
    project_row.project_id;
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.reject_promotion_target_audit_mutation(),
  app_data.promotion_target_context_authorized(uuid, uuid, uuid),
  app_data.promotion_target_document(uuid)
  FROM PUBLIC;

REVOKE ALL ON FUNCTION
  app_data.list_assigned_promotion_targets(uuid, uuid, uuid),
  app_data.create_promotion_target(
    uuid, uuid, uuid, text, text, text, text, text
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.list_assigned_promotion_targets(uuid, uuid, uuid),
  app_data.create_promotion_target(
    uuid, uuid, uuid, text, text, text, text, text
  )
  TO tongxingzhe_runtime;
