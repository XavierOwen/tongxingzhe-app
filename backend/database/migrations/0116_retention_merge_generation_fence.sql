-- 0116_retention_merge_generation_fence.sql

CREATE OR REPLACE FUNCTION app_data.apply_promotion_target_retention_action(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_target_id uuid,
  requested_action text,
  requested_reason text,
  requested_mutation_id text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_mutation_id text := btrim(requested_mutation_id);
  target_row app_data.promotion_targets%ROWTYPE;
  replay_row app_data.promotion_target_retention_events%ROWTYPE;
  event_time timestamptz;
  due_at timestamptz;
BEGIN
  IF requested_target_id IS NULL
    OR requested_action IS NULL
    OR requested_reason IS NULL
    OR requested_mutation_id IS NULL
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
    OR (
      requested_action = 'renew'
      AND requested_reason <> 'purpose_confirmed'
    )
    OR (
      requested_action = 'anonymize'
      AND requested_reason NOT IN ('withdrawal', 'retention_expired')
    )
    OR requested_action NOT IN ('renew', 'anonymize')
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid promotion target retention action';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'promotion target retention access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || normalized_mutation_id, 0
  ));
  SELECT event_row.* INTO replay_row
  FROM app_data.promotion_target_retention_events AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.mutation_id = normalized_mutation_id;
  IF FOUND THEN
    IF replay_row.workspace_id <> trusted_workspace_id
      OR replay_row.promotion_target_id <> requested_target_id
      OR replay_row.event_type <> (CASE requested_action
        WHEN 'renew' THEN 'renewed' ELSE 'anonymized' END)
      OR replay_row.reason <> requested_reason
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'promotion target retention mutation was reused';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'target_id', requested_target_id,
      'status', CASE WHEN replay_row.event_type = 'renewed'
        THEN 'active' ELSE 'anonymized' END,
      'duplicate', true,
      'review_due_at', replay_row.review_due_at
    );
    RETURN;
  END IF;

  IF requested_action = 'anonymize' THEN
    -- This unlocked preflight prevents unrelated callers from contending on
    -- the global fence; the locked check below remains authoritative.
    SELECT candidate.* INTO target_row
    FROM app_data.promotion_targets AS candidate
    WHERE candidate.promotion_target_id = requested_target_id
      AND candidate.workspace_id = trusted_workspace_id;
    IF NOT FOUND OR target_row.status <> 'active' OR NOT EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS assignment_row
      WHERE assignment_row.promotion_target_id = requested_target_id
        AND assignment_row.app_user_id = trusted_app_user_id
        AND assignment_row.ended_at IS NULL
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'promotion target retention access is forbidden';
    END IF;
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  IF requested_action = 'anonymize' THEN
    -- Keep anonymization's established fence-time linearization point.
    event_time := clock_timestamp();
  END IF;

  SELECT candidate.* INTO target_row
  FROM app_data.promotion_targets AS candidate
  WHERE candidate.promotion_target_id = requested_target_id
    AND candidate.workspace_id = trusted_workspace_id
  FOR UPDATE;
  IF requested_action = 'renew' THEN
    event_time := clock_timestamp();
    IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'promotion target retention access is forbidden';
    END IF;
  END IF;

  IF target_row.promotion_target_id IS NULL
    OR target_row.status <> 'active'
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS assignment_row
      WHERE assignment_row.promotion_target_id = requested_target_id
        AND assignment_row.app_user_id = trusted_app_user_id
        AND assignment_row.ended_at IS NULL
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'promotion target retention access is forbidden';
  END IF;
  due_at := app_data.promotion_target_review_due_at(requested_target_id);
  IF requested_reason = 'retention_expired' AND due_at > event_time THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'promotion target retention is not expired';
  END IF;
  IF requested_action = 'renew' AND due_at <= event_time THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'promotion target retention already expired';
  END IF;

  IF requested_action = 'renew' THEN
    INSERT INTO app_data.promotion_target_retention_events (
      workspace_id, promotion_target_id, actor_app_user_id, event_type,
      reason, occurred_at, mutation_id, review_due_at
    ) VALUES (
      trusted_workspace_id, requested_target_id, trusted_app_user_id,
      'renewed', 'purpose_confirmed', event_time, normalized_mutation_id,
      event_time + make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12))
    ) RETURNING review_due_at INTO due_at;
    RETURN QUERY SELECT jsonb_build_object(
      'target_id', requested_target_id, 'status', 'active',
      'duplicate', false, 'review_due_at', due_at
    );
    RETURN;
  END IF;

  PERFORM app_data.anonymize_promotion_target_internal(
    trusted_app_user_id, requested_target_id, requested_reason, event_time
  );
  INSERT INTO app_data.promotion_target_retention_events (
    workspace_id, promotion_target_id, actor_app_user_id, event_type,
    reason, occurred_at, mutation_id, review_due_at
  ) VALUES (
    trusted_workspace_id, requested_target_id, trusted_app_user_id,
    'anonymized', requested_reason, event_time, normalized_mutation_id, NULL
  );
  RETURN QUERY SELECT jsonb_build_object(
    'target_id', requested_target_id, 'status', 'anonymized',
    'duplicate', false, 'review_due_at', NULL
  );
END
$function$;

CREATE OR REPLACE FUNCTION app_data.configure_promotion_target_retention_policy(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_retention_months integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF requested_retention_months NOT BETWEEN 1 AND 12 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'retention months must be from 1 through 12';
  END IF;
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target retention policy is forbidden';
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target retention policy is forbidden';
  END IF;

  INSERT INTO app_data.promotion_target_retention_policies (
    workspace_id,
    retention_months,
    updated_by_app_user_id
  ) VALUES (
    trusted_workspace_id,
    requested_retention_months,
    trusted_app_user_id
  )
  ON CONFLICT (workspace_id) DO UPDATE
  SET retention_months = EXCLUDED.retention_months,
      updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
      updated_at = clock_timestamp();
  RETURN requested_retention_months;
END
$function$;
