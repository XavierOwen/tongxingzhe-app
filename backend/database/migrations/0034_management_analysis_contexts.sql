-- 0034_management_analysis_contexts.sql
--
-- 独立保存管理分析的导航上下文。保存完整授权证据可防止成员退出后以
-- 新 membership 或 grant 重新加入时，旧选择被静默复活。

CREATE TABLE app_data.management_analysis_current_contexts (
  app_user_id uuid PRIMARY KEY
    REFERENCES app_data.app_users (app_user_id) ON DELETE CASCADE,
  organization_workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  organization_membership_id uuid NOT NULL
    REFERENCES app_data.organization_memberships (
      organization_membership_id
    ) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  project_membership_id uuid NOT NULL
    REFERENCES app_data.project_memberships (project_membership_id)
    ON DELETE RESTRICT,
  capability_grant_id uuid NOT NULL
    REFERENCES app_data.management_report_capability_grants (
      capability_grant_id
    ) ON DELETE RESTRICT,
  selected_at_utc timestamp with time zone NOT NULL,
  CHECK (isfinite(selected_at_utc))
);

CREATE INDEX management_analysis_current_contexts_project
ON app_data.management_analysis_current_contexts (project_id);

REVOKE ALL PRIVILEGES ON TABLE
  app_data.management_analysis_current_contexts
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.validate_management_analysis_current_context_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.app_users AS app_user
    JOIN app_data.organization_memberships AS organization_membership
      ON organization_membership.app_user_id = app_user.app_user_id
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id =
        organization_membership.organization_workspace_id
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.organization_membership_id =
        organization_membership.organization_membership_id
    JOIN app_data.projects AS project_row
      ON project_row.project_id = project_membership.project_id
     AND project_row.workspace_id = workspace_row.workspace_id
    JOIN app_data.management_report_capability_grants AS capability_grant
      ON capability_grant.project_membership_id =
        project_membership.project_membership_id
    WHERE app_user.app_user_id = NEW.app_user_id
      AND app_user.status = 'active'
      AND workspace_row.workspace_id = NEW.organization_workspace_id
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
      AND organization_membership.organization_membership_id =
        NEW.organization_membership_id
      AND project_row.project_id = NEW.project_id
      AND project_row.status = 'active'
      AND project_membership.project_membership_id =
        NEW.project_membership_id
      AND capability_grant.capability_grant_id = NEW.capability_grant_id
      AND capability_grant.capability_id = 'view_anonymous_analytics'
      AND tstzrange(
        organization_membership.active_from_utc,
        organization_membership.inactive_from_utc,
        '[)'
      ) @> NEW.selected_at_utc
      AND tstzrange(
        project_membership.active_from_utc,
        project_membership.inactive_from_utc,
        '[)'
      ) @> NEW.selected_at_utc
      AND tstzrange(
        capability_grant.active_from_utc,
        capability_grant.inactive_from_utc,
        '[)'
      ) @> NEW.selected_at_utc
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management analysis current context evidence';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER management_analysis_current_contexts_validate
BEFORE INSERT OR UPDATE
ON app_data.management_analysis_current_contexts
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_analysis_current_context_v1();

CREATE FUNCTION app_data.list_management_analysis_contexts_v1(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (
  organization_workspace_id uuid,
  organization_name text,
  project_id uuid,
  project_name text,
  is_current boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
  reference_at_utc timestamp with time zone;
BEGIN
  IF trusted_issuer IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR trusted_subject IS NULL
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management analysis context identity';
  END IF;

  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management analysis context forbidden';
  END IF;

  reference_at_utc = clock_timestamp();

  RETURN QUERY
  SELECT
    workspace_row.workspace_id,
    workspace_row.display_name,
    project_row.project_id,
    project_row.display_name,
    current_context.app_user_id IS NOT NULL
  FROM app_data.organization_memberships AS organization_membership
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.workspace_id =
      organization_membership.organization_workspace_id
  JOIN app_data.project_memberships AS project_membership
    ON project_membership.organization_membership_id =
      organization_membership.organization_membership_id
  JOIN app_data.projects AS project_row
    ON project_row.project_id = project_membership.project_id
   AND project_row.workspace_id = workspace_row.workspace_id
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.project_membership_id =
      project_membership.project_membership_id
   AND capability_grant.capability_id = 'view_anonymous_analytics'
  LEFT JOIN app_data.management_analysis_current_contexts AS current_context
    ON current_context.app_user_id = resolved_app_user_id
   AND current_context.organization_workspace_id = workspace_row.workspace_id
   AND current_context.organization_membership_id =
      organization_membership.organization_membership_id
   AND current_context.project_id = project_row.project_id
   AND current_context.project_membership_id =
      project_membership.project_membership_id
   AND current_context.capability_grant_id =
      capability_grant.capability_grant_id
  WHERE organization_membership.app_user_id = resolved_app_user_id
    AND workspace_row.workspace_kind = 'organization'
    AND workspace_row.deleted_at IS NULL
    AND project_row.status = 'active'
    AND tstzrange(
      organization_membership.active_from_utc,
      organization_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND tstzrange(
      project_membership.active_from_utc,
      project_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND tstzrange(
      capability_grant.active_from_utc,
      capability_grant.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
  ORDER BY
    (current_context.app_user_id IS NOT NULL) DESC,
    workspace_row.display_name,
    project_row.display_name,
    project_row.project_id;
END
$function$;

CREATE FUNCTION app_data.select_management_analysis_context_v1(
  trusted_issuer text,
  trusted_subject text,
  selected_project_id uuid
)
RETURNS TABLE (
  organization_workspace_id uuid,
  organization_name text,
  project_id uuid,
  project_name text,
  is_current boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_record jsonb;
  resolved_app_user_id uuid;
BEGIN
  IF selected_project_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management analysis project selection';
  END IF;

  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management analysis context forbidden';
  END IF;

  authorization_record =
    app_private.resolve_management_report_authorization_v1(
      resolved_app_user_id,
      selected_project_id,
      'view_anonymous_analytics'
    );

  INSERT INTO app_data.management_analysis_current_contexts (
    app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_id,
    project_membership_id,
    capability_grant_id,
    selected_at_utc
  ) VALUES (
    resolved_app_user_id,
    (authorization_record->>'organization_workspace_id')::uuid,
    (authorization_record->>'organization_membership_id')::uuid,
    selected_project_id,
    (authorization_record->>'project_membership_id')::uuid,
    (authorization_record->>'capability_grant_id')::uuid,
    (authorization_record->>'reference_at_utc')::timestamptz
  )
  ON CONFLICT ON CONSTRAINT management_analysis_current_contexts_pkey
  DO UPDATE SET
    organization_workspace_id = EXCLUDED.organization_workspace_id,
    organization_membership_id = EXCLUDED.organization_membership_id,
    project_id = EXCLUDED.project_id,
    project_membership_id = EXCLUDED.project_membership_id,
    capability_grant_id = EXCLUDED.capability_grant_id,
    selected_at_utc = EXCLUDED.selected_at_utc;

  RETURN QUERY
  SELECT context_row.*
  FROM app_data.list_management_analysis_contexts_v1(
    trusted_issuer,
    trusted_subject
  ) AS context_row
  WHERE context_row.is_current;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management analysis context forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_analysis_current_context_v1(),
  app_data.list_management_analysis_contexts_v1(text, text),
  app_data.select_management_analysis_context_v1(text, text, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.list_management_analysis_contexts_v1(text, text),
  app_data.select_management_analysis_context_v1(text, text, uuid)
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.management_analysis_current_contexts
IS 'Navigation preferences bound to the exact organization, project, and view grant evidence used when selected.';

COMMENT ON FUNCTION
  app_data.list_management_analysis_contexts_v1(text, text)
IS 'Lists currently view-authorized organization projects without treating navigation context as an authorization token.';

COMMENT ON FUNCTION
  app_data.select_management_analysis_context_v1(text, text, uuid)
IS 'Persists exact view-authorization evidence for one management analysis navigation context.';
