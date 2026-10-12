-- Expiry ends the generation and erases both members in one transaction.
ALTER TABLE app_private.personal_target_merge_end_events_v1
  DROP CONSTRAINT personal_target_merge_end_events_v1_operation_check,
  DROP CONSTRAINT personal_target_merge_end_events_v1_reason_check,
  ADD CONSTRAINT personal_target_merge_end_operation_reason CHECK (
    (operation = 'personal_target_known_source_merge_end'
      AND reason = 'known_source_split')
    OR
    (operation = 'personal_target_known_source_merge_expire'
      AND reason = 'retention_expired')
  );

-- Keep the existing writer identity/ACL and all its validation; only distinguish
-- its receipt from the new expiry operation sharing the same event ledger.
DO $replay_operation$
DECLARE
  function_row pg_proc%ROWTYPE;
  definition text;
  old_guard text := 'IF replay_row.workspace_id <> trusted_workspace_id';
  new_guard text := E'IF replay_row.operation <> ''personal_target_known_source_merge_end''\n'
    '      OR replay_row.reason <> ''known_source_split''\n'
    '      OR replay_row.workspace_id <> trusted_workspace_id';
BEGIN
  SELECT * INTO STRICT function_row FROM pg_proc
  WHERE oid = 'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure;
  definition := pg_get_functiondef(function_row.oid);
  IF length(definition) - length(replace(definition, old_guard, ''))
    <> length(old_guard)
  THEN
    RAISE EXCEPTION '0120 known-source end replay guard unavailable';
  END IF;
  EXECUTE replace(definition, old_guard, new_guard);
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc AS replaced
    WHERE replaced.oid = function_row.oid
      AND replaced.proowner = function_row.proowner
      AND replaced.proacl IS NOT DISTINCT FROM function_row.proacl
      AND replaced.prosecdef = function_row.prosecdef
      AND replaced.provolatile = function_row.provolatile
      AND replaced.proconfig IS NOT DISTINCT FROM function_row.proconfig
  ) THEN
    RAISE EXCEPTION '0120 known-source end writer identity/security/ACL drift';
  END IF;
END
$replay_operation$;

CREATE FUNCTION app_private.expire_known_source_personal_target_merge_generation_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid
)
RETURNS timestamptz
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  replay_row app_private.personal_target_merge_end_events_v1%ROWTYPE;
  generation_row app_private.personal_target_merge_generations_v1%ROWTYPE;
  member_target_ids uuid[];
  locked_count integer;
  pair_due_at timestamptz;
  current_fact_count bigint;
  current_fact_fingerprint text;
  expired_at_value timestamptz;
  member_target_id uuid;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL OR requested_request_id IS NULL
    OR requested_generation_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid known-source personal target merge expiry request';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    ) OR NOT EXISTS (
      SELECT 1 FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge expiry is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || requested_request_id::text, 0
  ));

  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    ) OR NOT EXISTS (
      SELECT 1 FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge expiry is forbidden';
  END IF;

  SELECT event_row.* INTO replay_row
  FROM app_private.personal_target_merge_end_events_v1 AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.request_id = requested_request_id;
  IF FOUND THEN
    IF replay_row.operation <> 'personal_target_known_source_merge_expire'
      OR replay_row.reason <> 'retention_expired'
      OR replay_row.workspace_id <> trusted_workspace_id
      OR replay_row.project_id <> trusted_project_id
      OR replay_row.generation_id <> requested_generation_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'known-source personal target merge expiry request was reused';
    END IF;
    RETURN replay_row.ended_at_utc;
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();

  IF EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS event_row
    WHERE event_row.generation_id = requested_generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505',
      MESSAGE = 'personal target merge generation has already ended';
  END IF;

  SELECT candidate.* INTO generation_row
  FROM app_private.personal_target_merge_generations_v1 AS candidate
  WHERE candidate.generation_id = requested_generation_id
    AND candidate.workspace_id = trusted_workspace_id
    AND candidate.created_by_app_user_id = trusted_app_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge expiry is forbidden';
  END IF;

  SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id)
    INTO member_target_ids
  FROM app_private.personal_target_merge_generation_members_v1 AS member
  WHERE member.generation_id = requested_generation_id;
  IF coalesce(cardinality(member_target_ids), 0) <> 2
    OR (SELECT count(*)
        FROM app_private.personal_target_merge_active_members_v1 AS active_member
        WHERE active_member.generation_id = requested_generation_id
          AND active_member.workspace_id = trusted_workspace_id
          AND active_member.target_type = generation_row.target_type
          AND active_member.promotion_target_id = ANY(member_target_ids)) <> 2
    OR (SELECT count(*)
        FROM app_private.personal_target_merge_active_members_v1 AS active_member
        WHERE active_member.generation_id = requested_generation_id) <> 2
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation is incomplete';
  END IF;

  PERFORM 1
  FROM app_data.promotion_targets AS candidate
  WHERE candidate.promotion_target_id = ANY(member_target_ids)
    AND candidate.workspace_id = trusted_workspace_id
    AND candidate.target_type = generation_row.target_type
    AND candidate.status = 'active'
  ORDER BY candidate.created_at, candidate.promotion_target_id
  FOR UPDATE;
  GET DIAGNOSTICS locked_count = ROW_COUNT;
  IF locked_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge expiry is forbidden';
  END IF;

  PERFORM 1
  FROM app_data.promotion_target_assignments AS assignment_row
  WHERE assignment_row.promotion_target_id = ANY(member_target_ids)
    AND assignment_row.app_user_id = trusted_app_user_id
    AND assignment_row.ended_at IS NULL
  ORDER BY assignment_row.promotion_target_id
  FOR UPDATE;
  GET DIAGNOSTICS locked_count = ROW_COUNT;
  IF locked_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge expiry is forbidden';
  END IF;

  expired_at_value := clock_timestamp();
  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    ) OR NOT EXISTS (
      SELECT 1 FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge expiry is forbidden';
  END IF;

  SELECT min(app_data.promotion_target_review_due_at(candidate.promotion_target_id))
    INTO pair_due_at
  FROM app_data.promotion_targets AS candidate
  WHERE candidate.promotion_target_id = ANY(member_target_ids);
  IF pair_due_at IS NULL OR pair_due_at > expired_at_value THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'personal target merge generation is not expired';
  END IF;

  SELECT manifest.fact_count, manifest.fact_fingerprint
    INTO current_fact_count, current_fact_fingerprint
  FROM app_private.personal_target_merge_known_source_manifest_v1(
    requested_generation_id
  ) AS manifest;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge fact source is inconsistent';
  END IF;

  DELETE FROM app_private.personal_target_merge_active_members_v1
  WHERE generation_id = requested_generation_id;
  GET DIAGNOSTICS locked_count = ROW_COUNT;
  IF locked_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation is incomplete';
  END IF;

  INSERT INTO app_private.personal_target_merge_end_events_v1 (
    generation_id, actor_app_user_id, workspace_id, project_id, request_id,
    operation, reason, outcome, fact_fingerprint, fact_count,
    target_count, ended_at_utc
  ) VALUES (
    requested_generation_id, trusted_app_user_id, trusted_workspace_id,
    trusted_project_id, requested_request_id,
    'personal_target_known_source_merge_expire', 'retention_expired', 'ended',
    current_fact_fingerprint, current_fact_count, 2, expired_at_value
  );

  FOREACH member_target_id IN ARRAY member_target_ids LOOP
    PERFORM app_data.anonymize_promotion_target_internal(
      trusted_app_user_id, member_target_id, 'retention_expired', expired_at_value
    );
    INSERT INTO app_data.promotion_target_retention_events (
      workspace_id, promotion_target_id, actor_app_user_id,
      event_type, reason, occurred_at, mutation_id
    ) VALUES (
      trusted_workspace_id, member_target_id, trusted_app_user_id,
      'anonymized', 'retention_expired', expired_at_value,
      'merge-expired:' || requested_request_id::text || ':' || member_target_id::text
    );
  END LOOP;

  RETURN expired_at_value;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
