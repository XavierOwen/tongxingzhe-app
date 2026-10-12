-- Record user-requested end of one personal target assignment.

CREATE TABLE app_private.personal_target_assignment_end_events_v1 (
  assignment_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  reason text NOT NULL CHECK (reason = 'user_requested'),
  ended_at_utc timestamptz NOT NULL CHECK (isfinite(ended_at_utc))
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_assignment_end_events_v1
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER personal_target_assignment_end_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.personal_target_assignment_end_events_v1
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_data.end_personal_target_assignment_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_assignment_id uuid
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  target_id uuid;
  target_row app_data.promotion_targets%ROWTYPE;
  assignment_row app_data.promotion_target_assignments%ROWTYPE;
  replay_row app_private.personal_target_assignment_end_events_v1%ROWTYPE;
  event_time timestamptz;
BEGIN
  IF trusted_app_user_id IS NULL
    OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL
    OR requested_assignment_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid personal target assignment end request';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target assignment end is forbidden';
  END IF;

  SELECT event_row.* INTO replay_row
  FROM app_private.personal_target_assignment_end_events_v1 AS event_row
  WHERE event_row.assignment_id = requested_assignment_id;
  IF FOUND THEN
    IF replay_row.actor_app_user_id <> trusted_app_user_id
      OR replay_row.workspace_id <> trusted_workspace_id
      OR replay_row.project_id <> trusted_project_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'personal target assignment end request was reused';
    END IF;
    RETURN replay_row.ended_at_utc;
  END IF;

  SELECT candidate_assignment.promotion_target_id INTO target_id
  FROM app_data.promotion_target_assignments AS candidate_assignment
  WHERE candidate_assignment.assignment_id = requested_assignment_id
    AND candidate_assignment.app_user_id = trusted_app_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target assignment end is forbidden';
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();

  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target assignment end is forbidden';
  END IF;

  SELECT candidate.* INTO target_row
  FROM app_data.promotion_targets AS candidate
  WHERE candidate.promotion_target_id = target_id
    AND candidate.workspace_id = trusted_workspace_id
    AND candidate.status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target assignment end is forbidden';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target assignment end is forbidden';
  END IF;

  SELECT event_row.* INTO replay_row
  FROM app_private.personal_target_assignment_end_events_v1 AS event_row
  WHERE event_row.assignment_id = requested_assignment_id;
  IF FOUND THEN
    IF replay_row.actor_app_user_id <> trusted_app_user_id
      OR replay_row.workspace_id <> trusted_workspace_id
      OR replay_row.project_id <> trusted_project_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'personal target assignment end request was reused';
    END IF;
    RETURN replay_row.ended_at_utc;
  END IF;

  SELECT candidate.* INTO assignment_row
  FROM app_data.promotion_target_assignments AS candidate
  WHERE candidate.assignment_id = requested_assignment_id
    AND candidate.promotion_target_id = target_row.promotion_target_id
    AND candidate.app_user_id = trusted_app_user_id
    AND candidate.ended_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target assignment end is forbidden';
  END IF;

  IF EXISTS (
      SELECT 1
      FROM app_private.personal_target_merge_active_members_v1 AS active_member
      WHERE active_member.promotion_target_id = target_row.promotion_target_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS other_assignment
      WHERE other_assignment.promotion_target_id = target_row.promotion_target_id
        AND other_assignment.assignment_id <> requested_assignment_id
        AND other_assignment.ended_at IS NULL
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge must be split before ending assignment';
  END IF;

  event_time := clock_timestamp();

  UPDATE app_data.promotion_target_assignments
  SET ended_at = event_time, end_reason = 'user_requested'
  WHERE assignment_id = requested_assignment_id;

  INSERT INTO app_private.personal_target_assignment_end_events_v1 (
    assignment_id,
    actor_app_user_id,
    workspace_id,
    project_id,
    reason,
    ended_at_utc
  ) VALUES (
    requested_assignment_id,
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    'user_requested',
    event_time
  );

  RETURN event_time;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.end_personal_target_assignment_v1(uuid, uuid, uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER TABLE app_private.personal_target_assignment_end_events_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.end_personal_target_assignment_v1(uuid,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
