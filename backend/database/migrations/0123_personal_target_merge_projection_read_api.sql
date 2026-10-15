CREATE FUNCTION app_data.read_personal_merge_projection_context_v1(
  trusted_issuer text,
  trusted_subject text,
  trusted_project_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE context_document jsonb;
BEGIN
  IF trusted_issuer IS NULL OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512 OR trusted_project_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid personal merge projection context request';
  END IF;

  -- Personal ownership derives these capabilities independently of management-analysis navigation.
  SELECT jsonb_build_object(
    'app_user_id', actor.app_user_id,
    'workspace_id', workspace_row.workspace_id,
    'workspace_kind', 'personal',
    'project_id', project_row.project_id,
    'capabilities', jsonb_build_array('view_assigned_target_pii','manage_assigned_target_merges')
  ) INTO context_document
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS actor
    ON actor.app_user_id = identity_row.app_user_id AND actor.status = 'active'
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.personal_owner_app_user_id = actor.app_user_id
    AND workspace_row.workspace_kind = 'personal' AND workspace_row.deleted_at IS NULL
  JOIN app_data.user_current_projects AS current_project
    ON current_project.app_user_id = actor.app_user_id
    AND current_project.project_id = trusted_project_id
  JOIN app_data.projects AS project_row
    ON project_row.project_id = current_project.project_id
    AND project_row.workspace_id = workspace_row.workspace_id AND project_row.status = 'active'
  WHERE identity_row.issuer = trusted_issuer AND identity_row.subject = trusted_subject;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal merge projection context is forbidden';
  END IF;
  RETURN context_document;
END
$function$;

CREATE FUNCTION app_data.read_personal_known_source_merge_projection_v1(
  trusted_issuer text,
  trusted_subject text,
  trusted_project_id uuid,
  requested_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RETURN app_private.read_authorized_known_source_personal_merge_projection_v1(
    trusted_issuer, trusted_subject, trusted_project_id, requested_generation_id
  );
END
$function$;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_data.read_personal_merge_projection_context_v1(text,text,uuid) OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_data.read_personal_known_source_merge_projection_v1(text,text,uuid,uuid) OWNER TO %I', trusted_owner);
END
$owner$;

REVOKE ALL ON FUNCTION
  app_data.read_personal_merge_projection_context_v1(text,text,uuid),
  app_data.read_personal_known_source_merge_projection_v1(text,text,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.read_personal_merge_projection_context_v1(text,text,uuid),
  app_data.read_personal_known_source_merge_projection_v1(text,text,uuid,uuid)
  TO tongxingzhe_runtime;
