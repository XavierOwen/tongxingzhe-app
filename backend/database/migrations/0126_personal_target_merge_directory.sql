CREATE FUNCTION app_private.read_authorized_personal_merge_directory_v1(
  trusted_issuer text,
  trusted_subject text,
  trusted_project_id uuid,
  requested_after_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  directory jsonb;
  inserted_count bigint;
  expected_count bigint;
BEGIN
  WITH context AS MATERIALIZED (
    SELECT app_data.read_personal_merge_projection_context_v1(
      trusted_issuer, trusted_subject, trusted_project_id
    ) AS document
  ),
  eligible AS MATERIALIZED (
    SELECT generation.generation_id, generation.target_type,
      choice.retained_target_id, members.target_ids, sources.review_due_at
    FROM context
    JOIN app_private.personal_target_merge_generations_v1 AS generation
      ON generation.workspace_id = (context.document ->> 'workspace_id')::uuid
      AND generation.created_by_app_user_id = (context.document ->> 'app_user_id')::uuid
    CROSS JOIN LATERAL (
      SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) AS target_ids,
        count(*) AS member_count,
        bool_and(member.workspace_id = generation.workspace_id
          AND member.target_type = generation.target_type) AS context_matches
      FROM app_private.personal_target_merge_generation_members_v1 AS member
      WHERE member.generation_id = generation.generation_id
    ) AS members
    CROSS JOIN LATERAL (
      SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) AS target_ids,
        count(*) AS member_count,
        bool_and(member.workspace_id = generation.workspace_id
          AND member.target_type = generation.target_type) AS context_matches
      FROM app_private.personal_target_merge_active_members_v1 AS member
      WHERE member.generation_id = generation.generation_id
    ) AS active_members
    CROSS JOIN LATERAL (
      SELECT count(*) AS member_count, min(retention.review_due_at) AS review_due_at,
        bool_and(retention.review_due_at > statement_timestamp()) AS not_due
      FROM app_data.promotion_targets AS target
      CROSS JOIN LATERAL (
        SELECT app_data.promotion_target_review_due_at(target.promotion_target_id) AS review_due_at
      ) AS retention
      WHERE target.promotion_target_id = ANY(members.target_ids)
        AND target.workspace_id = generation.workspace_id
        AND target.target_type = generation.target_type AND target.status = 'active'
        AND EXISTS (SELECT 1 FROM app_data.promotion_target_assignments AS assignment
          WHERE assignment.promotion_target_id = target.promotion_target_id
            AND assignment.app_user_id = (context.document ->> 'app_user_id')::uuid
            AND assignment.ended_at IS NULL)
    ) AS sources
    JOIN app_private.personal_target_merge_activation_requests_v1 AS choice
      ON choice.generation_id = generation.generation_id
      AND choice.actor_app_user_id = (context.document ->> 'app_user_id')::uuid
      AND choice.workspace_id = generation.workspace_id
      AND choice.retained_target_id = ANY(members.target_ids)
      AND choice.display_name_source_target_id = ANY(members.target_ids)
      AND choice.phone_source_target_id = ANY(members.target_ids)
      AND choice.email_source_target_id = ANY(members.target_ids)
    WHERE (requested_after_generation_id IS NULL OR generation.generation_id > requested_after_generation_id)
      AND members.member_count = 2 AND members.context_matches
      AND active_members.member_count = 2 AND active_members.context_matches
      AND active_members.target_ids = members.target_ids
      AND sources.member_count = 2 AND sources.not_due
      AND (SELECT count(*) FROM app_private.personal_target_merge_activation_requests_v1 AS activation
        WHERE activation.generation_id = generation.generation_id) = 1
      AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS event
        WHERE event.generation_id = generation.generation_id)
    ORDER BY generation.generation_id
    LIMIT 21
  ),
  page AS MATERIALIZED (
    SELECT * FROM eligible ORDER BY generation_id LIMIT 20
  ),
  inserted_access_events AS (
    INSERT INTO app_data.promotion_target_access_events (
      event_id, workspace_id, promotion_target_id, actor_app_user_id, action, occurred_at
    )
    SELECT gen_random_uuid(), (context.document ->> 'workspace_id')::uuid,
      member.target_id, (context.document ->> 'app_user_id')::uuid, 'viewed', statement_timestamp()
    FROM context CROSS JOIN page
    CROSS JOIN LATERAL unnest(page.target_ids) AS member(target_id)
    RETURNING event_id
  )
  SELECT jsonb_build_object(
    'workspace_id', (context.document ->> 'workspace_id')::uuid,
    'project_id', trusted_project_id,
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'generation_id', page.generation_id, 'target_type', page.target_type,
      'retained_target_id', page.retained_target_id, 'member_target_ids', page.target_ids,
      'review_due_at_utc', to_char(page.review_due_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ) ORDER BY page.generation_id) FROM page), '[]'::jsonb),
    'next_cursor', CASE WHEN (SELECT count(*) FROM eligible) > 20
      THEN (SELECT generation_id FROM page ORDER BY generation_id DESC LIMIT 1) END
  ), access_count.inserted_count, (SELECT 2 * count(*) FROM page)
  INTO directory, inserted_count, expected_count
  FROM context
  CROSS JOIN (SELECT count(*) AS inserted_count FROM inserted_access_events) AS access_count;

  IF inserted_count IS DISTINCT FROM expected_count THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal merge directory member view audit is incomplete';
  END IF;
  RETURN directory;
END
$function$;

CREATE FUNCTION app_data.read_personal_merge_directory_v1(
  trusted_issuer text,
  trusted_subject text,
  trusted_project_id uuid,
  requested_after_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RETURN app_private.read_authorized_personal_merge_directory_v1(
    trusted_issuer, trusted_subject, trusted_project_id, requested_after_generation_id
  );
END
$function$;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid) OWNER TO %I',trusted_owner);
  EXECUTE format('ALTER FUNCTION app_data.read_personal_merge_directory_v1(text,text,uuid,uuid) OWNER TO %I',trusted_owner);
END
$owner$;

REVOKE ALL ON FUNCTION
  app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid),
  app_data.read_personal_merge_directory_v1(text,text,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION app_data.read_personal_merge_directory_v1(text,text,uuid,uuid)
  TO tongxingzhe_runtime;
