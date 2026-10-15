-- Reauthorize the original identity and audit both returned sources atomically.

CREATE FUNCTION app_private.read_authorized_known_source_personal_merge_projection_v1(
  trusted_issuer text,
  trusted_subject text,
  trusted_project_id uuid,
  requested_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  projection jsonb;
  inserted_count bigint;
BEGIN
  IF trusted_issuer IS NULL OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
    OR trusted_project_id IS NULL OR requested_generation_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid authorized known-source personal target merge projection request';
  END IF;

  -- Personal ownership derives both PII-view and merge-management capabilities, as in 0113.
  WITH context AS MATERIALIZED (
    SELECT actor.app_user_id, workspace_row.workspace_id
    FROM app_data.external_identities AS identity_row
    JOIN app_data.app_users AS actor
      ON actor.app_user_id = identity_row.app_user_id
      AND actor.status = 'active'
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.personal_owner_app_user_id = actor.app_user_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.deleted_at IS NULL
    JOIN app_data.user_current_projects AS current_project
      ON current_project.app_user_id = actor.app_user_id
      AND current_project.project_id = trusted_project_id
    JOIN app_data.projects AS project_row
      ON project_row.project_id = current_project.project_id
      AND project_row.workspace_id = workspace_row.workspace_id
      AND project_row.status = 'active'
    WHERE identity_row.issuer = trusted_issuer
      AND identity_row.subject = trusted_subject
  ),
  projected AS MATERIALIZED (
    SELECT context.app_user_id, context.workspace_id,
      app_private.read_known_source_personal_target_merge_projection_v1(
        context.app_user_id, context.workspace_id,
        trusted_project_id, requested_generation_id
      ) AS document
    FROM context
  ),
  inserted_access_events AS (
    INSERT INTO app_data.promotion_target_access_events (
      event_id, workspace_id, promotion_target_id, actor_app_user_id, action, occurred_at
    )
    SELECT gen_random_uuid(), projected.workspace_id,
      (source.document ->> 'target_id')::uuid, projected.app_user_id,
      'viewed', statement_timestamp()
    FROM projected
    CROSS JOIN LATERAL jsonb_array_elements(projected.document -> 'sources') AS source(document)
    RETURNING event_id
  )
  SELECT projected.document, access_count.inserted_count
  INTO projection, inserted_count
  FROM projected
  CROSS JOIN (SELECT count(*) AS inserted_count FROM inserted_access_events) AS access_count;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'authorized known-source personal target merge projection is forbidden';
  END IF;
  IF inserted_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge source view audit is incomplete';
  END IF;
  RETURN projection;
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_proc
  WHERE oid = 'app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
