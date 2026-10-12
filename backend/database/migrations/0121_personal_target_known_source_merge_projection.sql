-- Read the selected original profiles and current source facts in one snapshot.

CREATE FUNCTION app_private.read_known_source_personal_target_merge_projection_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  read_gate text;
  projection jsonb;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL OR requested_generation_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid known-source personal target merge projection request';
  END IF;

  -- STABLE document helpers share this command's snapshot with its gates.
  WITH context AS MATERIALIZED (
    SELECT workspace_row.workspace_id
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
    JOIN app_data.user_current_projects AS current_project
      ON current_project.app_user_id = trusted_app_user_id
      AND current_project.project_id = project_row.project_id
    JOIN app_data.app_users AS actor
      ON actor.app_user_id = trusted_app_user_id
      AND actor.status = 'active'
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
  ),
  generation AS MATERIALIZED (
    SELECT generation_row.*
    FROM app_private.personal_target_merge_generations_v1 AS generation_row
    JOIN context ON context.workspace_id = generation_row.workspace_id
    WHERE generation_row.generation_id = requested_generation_id
      AND generation_row.created_by_app_user_id = trusted_app_user_id
  ),
  members AS MATERIALIZED (
    SELECT
      array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) AS target_ids,
      count(*) AS member_count,
      bool_and(member.workspace_id = generation.workspace_id
        AND member.target_type = generation.target_type) AS context_matches
    FROM generation
    JOIN app_private.personal_target_merge_generation_members_v1 AS member
      ON member.generation_id = generation.generation_id
  ),
  active_members AS MATERIALIZED (
    SELECT
      array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) AS target_ids,
      count(*) AS member_count,
      bool_and(member.workspace_id = generation.workspace_id
        AND member.target_type = generation.target_type) AS context_matches
    FROM generation
    JOIN app_private.personal_target_merge_active_members_v1 AS member
      ON member.generation_id = generation.generation_id
  ),
  choices AS MATERIALIZED (
    SELECT activation.*
    FROM generation
    JOIN app_private.personal_target_merge_activation_requests_v1 AS activation
      ON activation.generation_id = generation.generation_id
  ),
  source_targets AS MATERIALIZED (
    SELECT target.*, app_data.promotion_target_review_due_at(
      target.promotion_target_id
    ) AS review_due_at
    FROM generation
    CROSS JOIN members
    JOIN app_data.promotion_targets AS target
      ON target.promotion_target_id = ANY(members.target_ids)
      AND target.workspace_id = generation.workspace_id
      AND target.target_type = generation.target_type
      AND target.status = 'active'
    WHERE EXISTS (
      SELECT 1 FROM app_data.promotion_target_assignments AS assignment
      WHERE assignment.promotion_target_id = target.promotion_target_id
        AND assignment.app_user_id = trusted_app_user_id
        AND assignment.ended_at IS NULL
    )
  ),
  gate AS MATERIALIZED (
    SELECT CASE
      WHEN NOT EXISTS (SELECT 1 FROM generation)
        OR EXISTS (
          SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS event
          WHERE event.generation_id = requested_generation_id
        ) THEN 'forbidden'
      WHEN members.member_count <> 2 OR NOT coalesce(members.context_matches, false)
        OR active_members.member_count <> 2
        OR NOT coalesce(active_members.context_matches, false)
        OR active_members.target_ids IS DISTINCT FROM members.target_ids
        THEN 'incomplete'
      WHEN (SELECT count(*) FROM source_targets) <> 2
        OR NOT coalesce((
          SELECT bool_and(source.review_due_at > statement_timestamp())
          FROM source_targets AS source
        ), false) THEN 'forbidden'
      WHEN (SELECT count(*) FROM choices) <> 1
        OR NOT coalesce((
          SELECT bool_and(
            choice.actor_app_user_id = trusted_app_user_id
            AND choice.workspace_id = trusted_workspace_id
            AND choice.retained_target_id = ANY(members.target_ids)
            AND choice.display_name_source_target_id = ANY(members.target_ids)
            AND choice.phone_source_target_id = ANY(members.target_ids)
            AND choice.email_source_target_id = ANY(members.target_ids)
          ) FROM choices AS choice
        ), false) THEN 'incomplete'
      ELSE 'ready'
    END AS status
    FROM members CROSS JOIN active_members
  )
  SELECT gate.status, CASE WHEN gate.status = 'ready' THEN (
    SELECT jsonb_build_object(
      'generation_id', generation.generation_id,
      'workspace_id', trusted_workspace_id,
      'project_id', trusted_project_id,
      'target_type', generation.target_type,
      'retained_target_id', choice.retained_target_id,
      'display_name', (SELECT source.display_name FROM source_targets AS source
        WHERE source.promotion_target_id = choice.display_name_source_target_id),
      'phone', (SELECT source.phone FROM source_targets AS source
        WHERE source.promotion_target_id = choice.phone_source_target_id),
      'email', (SELECT source.email FROM source_targets AS source
        WHERE source.promotion_target_id = choice.email_source_target_id),
      'display_name_source_target_id', choice.display_name_source_target_id,
      'phone_source_target_id', choice.phone_source_target_id,
      'email_source_target_id', choice.email_source_target_id,
      'review_due_at_utc', (SELECT to_char(min(source.review_due_at) AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM source_targets AS source),
      'sources', (
        SELECT jsonb_agg(jsonb_build_object(
          'target_id', source.promotion_target_id,
          'profile', app_data.promotion_target_document(source.promotion_target_id),
          'review_due_at_utc', to_char(source.review_due_at AT TIME ZONE 'UTC',
            'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'project_relationship', app_data.promotion_target_relationship_document(
            source.promotion_target_id, trusted_project_id, false
          ),
          'contact_links', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
              'contact_id', link.contact_id,
              'revision_number', link.revision_number,
              'promotion_target_id', link.promotion_target_id,
              'response_level', link.response_level,
              'follow_up_consent', link.follow_up_consent,
              'institution_representative_confirmed', link.institution_representative_confirmed,
              'confirmed_project_entry', link.confirmed_project_entry,
              'merge_generation_id', link.merge_generation_id
            ) ORDER BY contact.occurred_at_utc DESC, link.contact_id, link.revision_number)
            FROM app_data.contacts AS contact
            JOIN app_data.contact_target_links AS link
              ON link.contact_id = contact.contact_id
              AND link.revision_number = contact.current_revision
            WHERE link.promotion_target_id = source.promotion_target_id
              AND contact.app_user_id = trusted_app_user_id
              AND contact.workspace_id = trusted_workspace_id
              AND contact.project_id = trusted_project_id
              AND contact.lifecycle_status = 'active'
          ), '[]'::jsonb),
          'institution_relationships', coalesce((
            SELECT jsonb_agg(
              app_data.promotion_target_institution_relation_document(
                relation.relationship_id
              ) - 'history'
              ORDER BY (relation.ended_at IS NULL) DESC,
                relation.started_at DESC, relation.relationship_id
            )
            FROM app_data.promotion_target_institution_relationships AS relation
            JOIN app_data.promotion_targets AS person
              ON person.promotion_target_id = relation.person_target_id
              AND person.workspace_id = trusted_workspace_id
              AND person.target_type = 'person'
              AND person.status = 'active'
            JOIN app_data.promotion_targets AS institution
              ON institution.promotion_target_id = relation.institution_target_id
              AND institution.workspace_id = trusted_workspace_id
              AND institution.target_type = 'institution'
              AND institution.status = 'active'
            JOIN app_data.promotion_target_assignments AS person_assignment
              ON person_assignment.promotion_target_id = person.promotion_target_id
              AND person_assignment.app_user_id = trusted_app_user_id
              AND person_assignment.ended_at IS NULL
            JOIN app_data.promotion_target_assignments AS institution_assignment
              ON institution_assignment.promotion_target_id = institution.promotion_target_id
              AND institution_assignment.app_user_id = trusted_app_user_id
              AND institution_assignment.ended_at IS NULL
            WHERE relation.workspace_id = trusted_workspace_id
              AND (relation.person_target_id = source.promotion_target_id
                OR relation.institution_target_id = source.promotion_target_id)
          ), '[]'::jsonb)
        ) ORDER BY source.promotion_target_id)
        FROM source_targets AS source
      )
    )
    FROM generation CROSS JOIN choices AS choice
  ) END
  INTO read_gate, projection
  FROM gate;

  IF read_gate = 'forbidden' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge projection is forbidden';
  END IF;
  IF read_gate <> 'ready' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation or field selection is incomplete';
  END IF;
  RETURN projection;
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
