-- 0004_personal_project_contexts.sql
--
-- 记录本人明确选择的个人项目，并提供列出、创建和选择个人项目的受控函数。

CREATE TABLE app_data.user_current_projects (
  app_user_id uuid PRIMARY KEY
    REFERENCES app_data.app_users (app_user_id) ON DELETE CASCADE,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX user_current_projects_project
  ON app_data.user_current_projects (project_id);

INSERT INTO app_data.user_current_projects (app_user_id, project_id)
SELECT
  workspace_row.personal_owner_app_user_id,
  project_row.project_id
FROM app_data.workspaces AS workspace_row
JOIN app_data.projects AS project_row
  ON project_row.workspace_id = workspace_row.workspace_id
WHERE workspace_row.workspace_kind = 'personal'
  AND workspace_row.deleted_at IS NULL
  AND project_row.is_personal_default
  AND project_row.status = 'active'
ON CONFLICT (app_user_id) DO NOTHING;

REVOKE ALL PRIVILEGES
  ON app_data.user_current_projects
  FROM tongxingzhe_runtime;

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
  SELECT identity_row.app_user_id
    INTO resolved_app_user_id
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

  SELECT workspace_row.workspace_id
    INTO STRICT resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = resolved_app_user_id
    AND workspace_row.deleted_at IS NULL;

  SELECT current_row.project_id
    INTO resolved_project_id
  FROM app_data.user_current_projects AS current_row
  JOIN app_data.projects AS project_row
    ON project_row.project_id = current_row.project_id
   AND project_row.workspace_id = resolved_workspace_id
   AND project_row.status = 'active'
  WHERE current_row.app_user_id = resolved_app_user_id;

  IF resolved_project_id IS NULL THEN
    SELECT project_row.project_id
      INTO STRICT resolved_project_id
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
    ARRAY['record_contact']::text[],
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

CREATE OR REPLACE FUNCTION app_data.select_personal_project_context(
  trusted_issuer text,
  trusted_subject text,
  selected_project_id uuid
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
  capabilities text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  SELECT context_row.app_user_id
    INTO resolved_app_user_id
  FROM app_data.list_personal_project_contexts(
    trusted_issuer,
    trusted_subject
  ) AS context_row
  WHERE context_row.project_id = selected_project_id;

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'selected project is not available to this app user';
  END IF;

  INSERT INTO app_data.user_current_projects (app_user_id, project_id)
  VALUES (resolved_app_user_id, selected_project_id)
  ON CONFLICT ON CONSTRAINT user_current_projects_pkey DO UPDATE
    SET project_id = EXCLUDED.project_id,
        updated_at = clock_timestamp();

  RETURN QUERY
  SELECT
    context_row.app_user_id,
    context_row.workspace_id,
    context_row.workspace_kind,
    context_row.workspace_name,
    context_row.project_id,
    context_row.project_name,
    context_row.questionnaire_version_id,
    context_row.questionnaire_version_number,
    context_row.capabilities
  FROM app_data.list_personal_project_contexts(
    trusted_issuer,
    trusted_subject
  ) AS context_row
  WHERE context_row.is_current;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.create_personal_project_context(
  trusted_issuer text,
  trusted_subject text,
  requested_display_name text
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
  capabilities text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_name text := btrim(requested_display_name);
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  created_project_id uuid;
BEGIN
  IF length(normalized_name) NOT BETWEEN 1 AND 120 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'project display name must contain 1 to 120 characters';
  END IF;

  SELECT
    context_row.app_user_id,
    context_row.workspace_id
    INTO STRICT resolved_app_user_id, resolved_workspace_id
  FROM app_data.list_personal_project_contexts(
    trusted_issuer,
    trusted_subject
  ) AS context_row
  WHERE context_row.is_current;

  INSERT INTO app_data.projects (workspace_id, display_name)
  VALUES (resolved_workspace_id, normalized_name)
  RETURNING projects.project_id INTO created_project_id;

  INSERT INTO app_data.questionnaire_versions (
    project_id,
    version_number,
    status,
    is_current
  )
  VALUES (created_project_id, 1, 'published', true);

  INSERT INTO app_data.user_current_projects (app_user_id, project_id)
  VALUES (resolved_app_user_id, created_project_id)
  ON CONFLICT ON CONSTRAINT user_current_projects_pkey DO UPDATE
    SET project_id = EXCLUDED.project_id,
        updated_at = clock_timestamp();

  RETURN QUERY
  SELECT
    context_row.app_user_id,
    context_row.workspace_id,
    context_row.workspace_kind,
    context_row.workspace_name,
    context_row.project_id,
    context_row.project_name,
    context_row.questionnaire_version_id,
    context_row.questionnaire_version_number,
    context_row.capabilities
  FROM app_data.list_personal_project_contexts(
    trusted_issuer,
    trusted_subject
  ) AS context_row
  WHERE context_row.is_current;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.list_personal_project_contexts(text, text),
     app_data.select_personal_project_context(text, text, uuid),
     app_data.create_personal_project_context(text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.list_personal_project_contexts(text, text),
     app_data.select_personal_project_context(text, text, uuid),
     app_data.create_personal_project_context(text, text, text)
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.list_personal_project_contexts(text, text) IS
  'Lists active personal projects after trusted identity verification.';
COMMENT ON FUNCTION app_data.select_personal_project_context(text, text, uuid) IS
  'Selects one personal project without accepting a client app_user_id.';
COMMENT ON FUNCTION app_data.create_personal_project_context(text, text, text) IS
  'Creates and selects one personal project with questionnaire version 1.';
