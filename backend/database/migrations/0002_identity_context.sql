-- 0002_identity_context.sql
--
-- 保存认证商身份与内部用户的映射，并原子建立 Slice 1 所需的个人上下文。
-- Flutter 不读取这些表。Backend 验证 access token 后，才把可信的 issuer 和
-- subject 交给 bootstrap_personal_context。

CREATE TABLE app_data.app_users (
  app_user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'deletion_pending', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE app_data.external_identities (
  external_identity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  issuer text NOT NULL,
  subject text NOT NULL,
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  linked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT external_identities_issuer_subject_unique
    UNIQUE (issuer, subject),
  CONSTRAINT external_identities_issuer_valid
    CHECK (length(btrim(issuer)) BETWEEN 1 AND 2048),
  CONSTRAINT external_identities_subject_valid
    CHECK (length(btrim(subject)) BETWEEN 1 AND 512)
);

CREATE INDEX external_identities_app_user
  ON app_data.external_identities (app_user_id);

CREATE TABLE app_data.workspaces (
  workspace_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_kind text NOT NULL
    CHECK (workspace_kind IN ('personal', 'organization')),
  display_name text NOT NULL CHECK (length(btrim(display_name)) > 0),
  personal_owner_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  deleted_at timestamptz,
  CONSTRAINT workspaces_owner_matches_kind CHECK (
    (workspace_kind = 'personal' AND personal_owner_app_user_id IS NOT NULL)
    OR
    (workspace_kind = 'organization' AND personal_owner_app_user_id IS NULL)
  )
);

CREATE UNIQUE INDEX workspaces_one_active_personal_per_user
  ON app_data.workspaces (personal_owner_app_user_id)
  WHERE workspace_kind = 'personal' AND deleted_at IS NULL;

CREATE TABLE app_data.projects (
  project_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  display_name text NOT NULL CHECK (length(btrim(display_name)) > 0),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'archived')),
  is_personal_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX projects_workspace_status
  ON app_data.projects (workspace_id, status);

CREATE UNIQUE INDEX projects_one_personal_default_per_workspace
  ON app_data.projects (workspace_id)
  WHERE is_personal_default;

CREATE TABLE app_data.questionnaire_versions (
  questionnaire_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  version_number integer NOT NULL CHECK (version_number > 0),
  status text NOT NULL CHECK (status = 'published'),
  is_current boolean NOT NULL DEFAULT false,
  published_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT questionnaire_versions_project_version_unique
    UNIQUE (project_id, version_number)
);

CREATE UNIQUE INDEX questionnaire_versions_one_current_per_project
  ON app_data.questionnaire_versions (project_id)
  WHERE is_current;

-- Backend runtime 只能通过受控函数取得这一层上下文，不能枚举外部身份，
-- 直接替换映射，或把项目迁到另一个空间。
REVOKE ALL PRIVILEGES
  ON app_data.app_users,
     app_data.external_identities,
     app_data.workspaces,
     app_data.projects,
     app_data.questionnaire_versions
  FROM tongxingzhe_runtime;

CREATE OR REPLACE FUNCTION app_data.bootstrap_personal_context(
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
  capabilities text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_issuer text := trusted_issuer;
  normalized_subject text := trusted_subject;
  candidate_app_user_id uuid;
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  resolved_project_id uuid;
  resolved_questionnaire_version_id uuid;
  resolved_questionnaire_version_number integer;
BEGIN
  IF length(btrim(normalized_issuer)) NOT BETWEEN 1 AND 2048 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'trusted issuer is empty or too long';
  END IF;

  IF length(btrim(normalized_subject)) NOT BETWEEN 1 AND 512 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'trusted subject is empty or too long';
  END IF;

  SELECT identity_row.app_user_id
    INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  WHERE identity_row.issuer = normalized_issuer
    AND identity_row.subject = normalized_subject;

  IF resolved_app_user_id IS NULL THEN
    candidate_app_user_id := gen_random_uuid();

    INSERT INTO app_data.app_users (app_user_id)
    VALUES (candidate_app_user_id);

    INSERT INTO app_data.external_identities (
      issuer,
      subject,
      app_user_id
    )
    VALUES (
      normalized_issuer,
      normalized_subject,
      candidate_app_user_id
    )
    ON CONFLICT (issuer, subject) DO NOTHING
    RETURNING external_identities.app_user_id
      INTO resolved_app_user_id;

    IF resolved_app_user_id IS NULL THEN
      DELETE FROM app_data.app_users
      WHERE app_users.app_user_id = candidate_app_user_id;

      SELECT identity_row.app_user_id
        INTO STRICT resolved_app_user_id
      FROM app_data.external_identities AS identity_row
      WHERE identity_row.issuer = normalized_issuer
        AND identity_row.subject = normalized_subject;
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS user_row
    WHERE user_row.app_user_id = resolved_app_user_id
      AND user_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'mapped app user is not active';
  END IF;

  -- 同一身份的并发首启共用一个事务锁，避免创建两套个人上下文。
  PERFORM pg_advisory_xact_lock(
    hashtextextended(resolved_app_user_id::text, 0)
  );

  SELECT workspace_row.workspace_id
    INTO resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = resolved_app_user_id
    AND workspace_row.deleted_at IS NULL;

  IF resolved_workspace_id IS NULL THEN
    INSERT INTO app_data.workspaces (
      workspace_kind,
      display_name,
      personal_owner_app_user_id
    )
    VALUES ('personal', '个人空间', resolved_app_user_id)
    RETURNING workspaces.workspace_id INTO resolved_workspace_id;
  END IF;

  SELECT project_row.project_id
    INTO resolved_project_id
  FROM app_data.projects AS project_row
  WHERE project_row.workspace_id = resolved_workspace_id
    AND project_row.is_personal_default
    AND project_row.status = 'active';

  IF resolved_project_id IS NULL THEN
    INSERT INTO app_data.projects (
      workspace_id,
      display_name,
      is_personal_default
    )
    VALUES (resolved_workspace_id, '我的推广项目', true)
    RETURNING projects.project_id INTO resolved_project_id;
  END IF;

  SELECT
    version_row.questionnaire_version_id,
    version_row.version_number
    INTO
      resolved_questionnaire_version_id,
      resolved_questionnaire_version_number
  FROM app_data.questionnaire_versions AS version_row
  WHERE version_row.project_id = resolved_project_id
    AND version_row.is_current
    AND version_row.status = 'published';

  IF resolved_questionnaire_version_id IS NULL THEN
    INSERT INTO app_data.questionnaire_versions (
      project_id,
      version_number,
      status,
      is_current
    )
    VALUES (resolved_project_id, 1, 'published', true)
    RETURNING
      questionnaire_versions.questionnaire_version_id,
      questionnaire_versions.version_number
      INTO
        resolved_questionnaire_version_id,
        resolved_questionnaire_version_number;
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
    ARRAY['record_contact']::text[]
  FROM app_data.workspaces AS workspace_row
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.project_id = project_row.project_id
  WHERE workspace_row.workspace_id = resolved_workspace_id
    AND project_row.project_id = resolved_project_id
    AND version_row.questionnaire_version_id =
      resolved_questionnaire_version_id;
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.bootstrap_personal_context(text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.bootstrap_personal_context(text, text)
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.bootstrap_personal_context(text, text) IS
  'Backend-only bootstrap after JWT verification; never accepts client app_user_id.';
