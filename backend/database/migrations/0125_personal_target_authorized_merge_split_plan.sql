CREATE FUNCTION app_private.read_authorized_known_source_merge_split_plan_v1(
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
  split_plan jsonb;
  inserted_count bigint;
BEGIN
  IF requested_generation_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid authorized known-source merge split plan request';
  END IF;

  WITH context AS MATERIALIZED (
    SELECT app_data.read_personal_merge_projection_context_v1(
      trusted_issuer, trusted_subject, trusted_project_id
    ) AS document
  ),
  planned AS MATERIALIZED (
    SELECT (context.document ->> 'app_user_id')::uuid AS app_user_id,
      (context.document ->> 'workspace_id')::uuid AS workspace_id,
      app_private.read_known_source_personal_merge_split_plan_v1(
        (context.document ->> 'app_user_id')::uuid,
        (context.document ->> 'workspace_id')::uuid,
        trusted_project_id, requested_generation_id
      ) AS document
    FROM context
  ),
  inserted_access_events AS (
    INSERT INTO app_data.promotion_target_access_events (
      event_id, workspace_id, promotion_target_id, actor_app_user_id, action, occurred_at
    )
    SELECT gen_random_uuid(), planned.workspace_id, member.target_id::uuid,
      planned.app_user_id, 'viewed', statement_timestamp()
    FROM planned
    CROSS JOIN LATERAL jsonb_array_elements_text(planned.document -> 'member_target_ids') AS member(target_id)
    RETURNING event_id
  )
  SELECT planned.document, access_count.inserted_count
  INTO split_plan, inserted_count
  FROM planned
  CROSS JOIN (SELECT count(*) AS inserted_count FROM inserted_access_events) AS access_count;

  IF inserted_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal merge split plan member view audit is incomplete';
  END IF;
  RETURN split_plan;
END
$function$;

CREATE FUNCTION app_data.read_personal_known_source_merge_split_plan_v1(
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
  RETURN app_private.read_authorized_known_source_merge_split_plan_v1(
    trusted_issuer, trusted_subject, trusted_project_id, requested_generation_id
  );
END
$function$;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid) OWNER TO %I', trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.read_personal_known_source_merge_split_plan_v1(text,text,uuid,uuid) OWNER TO %I', trusted_owner
  );
END
$owner$;

REVOKE ALL ON FUNCTION
  app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid),
  app_data.read_personal_known_source_merge_split_plan_v1(text,text,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.read_personal_known_source_merge_split_plan_v1(text,text,uuid,uuid)
  TO tongxingzhe_runtime;
