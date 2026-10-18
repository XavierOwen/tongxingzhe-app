-- A failed pair stays atomic without stopping unrelated expiry units.
CREATE TABLE app_private.personal_target_expiry_dispatch_requests_v1 (
  actor_app_user_id uuid NOT NULL REFERENCES app_data.app_users (app_user_id),
  request_id uuid NOT NULL,
  workspace_id uuid NOT NULL REFERENCES app_data.workspaces (workspace_id),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  selected_at_utc timestamptz NOT NULL CHECK (isfinite(selected_at_utc)),
  completed_at_utc timestamptz NOT NULL CHECK (isfinite(completed_at_utc) AND completed_at_utc >= selected_at_utc),
  unit_count integer NOT NULL CHECK (unit_count >= 0),
  expired_count integer NOT NULL CHECK (expired_count >= 0),
  skipped_count integer NOT NULL CHECK (skipped_count >= 0),
  failed_count integer NOT NULL CHECK (failed_count >= 0),
  PRIMARY KEY (actor_app_user_id, request_id),
  CHECK (unit_count = expired_count + skipped_count + failed_count)
);

CREATE TABLE app_private.personal_target_expiry_dispatch_units_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  unit_ordinal integer NOT NULL CHECK (unit_ordinal > 0),
  promotion_target_id uuid REFERENCES app_data.promotion_targets (promotion_target_id),
  generation_id uuid REFERENCES app_private.personal_target_merge_generations_v1 (generation_id),
  child_request_id uuid NOT NULL,
  outcome text NOT NULL CHECK (outcome IN ('expired', 'skipped', 'failed')),
  failure_code text,
  failure_sqlstate text,
  processed_at_utc timestamptz CHECK (isfinite(processed_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id, unit_ordinal),
  CONSTRAINT pted_unit_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_target_expiry_dispatch_requests_v1 (actor_app_user_id, request_id),
  UNIQUE (actor_app_user_id, request_id, promotion_target_id),
  UNIQUE (actor_app_user_id, request_id, generation_id),
  UNIQUE (actor_app_user_id, child_request_id),
  CHECK ((promotion_target_id IS NULL) <> (generation_id IS NULL)),
  CHECK (
    (outcome = 'expired' AND failure_code IS NULL AND failure_sqlstate IS NULL AND processed_at_utc IS NOT NULL)
    OR (outcome = 'skipped' AND failure_code IS NOT NULL
      AND failure_code IN ('not_due', 'unit_unavailable', 'assignment_unavailable', 'topology_changed')
      AND failure_sqlstate IS NULL AND processed_at_utc IS NULL)
    OR (outcome = 'failed' AND failure_code IS NOT NULL AND failure_sqlstate IS NOT NULL
      AND failure_code IN ('request_conflict', 'integrity_failure')
      AND (failure_sqlstate ~ '^23[0-9A-Z]{3}$' OR failure_sqlstate = '55000')
      AND processed_at_utc IS NULL)
  )
);

CREATE TRIGGER personal_target_expiry_dispatch_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_expiry_dispatch_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_data.reject_promotion_target_audit_mutation();
CREATE TRIGGER personal_target_expiry_dispatch_units_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_expiry_dispatch_units_v1
FOR EACH ROW EXECUTE FUNCTION app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_private.personal_target_expiry_dispatch_receipt_valid_v1(
  trusted_app_user_id uuid, requested_request_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  SELECT coalesce((SELECT receipt.unit_count = counts.total
      AND receipt.expired_count = counts.expired
      AND receipt.skipped_count = counts.skipped
      AND receipt.failed_count = counts.failed
      AND (counts.total = 0 OR (counts.first_ordinal = 1 AND counts.last_ordinal = counts.total))
      AND NOT EXISTS (
        SELECT 1 FROM app_private.personal_target_expiry_dispatch_units_v1 unit
        WHERE unit.actor_app_user_id = receipt.actor_app_user_id AND unit.request_id = receipt.request_id
          AND (unit.child_request_id <> md5('personal-target-expiry-v1:' || receipt.actor_app_user_id::text
              || ':' || receipt.request_id::text || ':'
              || CASE WHEN unit.generation_id IS NULL THEN 'target' ELSE 'generation' END
              || ':' || coalesce(unit.generation_id, unit.promotion_target_id)::text)::uuid
            OR (unit.outcome = 'expired' AND (
              CASE WHEN unit.generation_id IS NULL THEN NOT EXISTS (
                SELECT 1 FROM app_data.promotion_target_retention_events event
                WHERE event.actor_app_user_id = receipt.actor_app_user_id
                  AND event.mutation_id = 'owner-expiry-v1:' || unit.child_request_id::text
                  AND event.workspace_id = receipt.workspace_id AND event.promotion_target_id = unit.promotion_target_id
                  AND event.event_type = 'anonymized' AND event.reason = 'retention_expired'
                  AND event.occurred_at = unit.processed_at_utc)
              ELSE NOT EXISTS (
                SELECT 1 FROM app_private.personal_target_merge_end_events_v1 event
                WHERE event.actor_app_user_id = receipt.actor_app_user_id AND event.request_id = unit.child_request_id
                  AND event.workspace_id = receipt.workspace_id AND event.project_id = receipt.project_id
                  AND event.generation_id = unit.generation_id AND event.outcome = 'ended' AND event.target_count = 2
                  AND event.operation = 'personal_target_known_source_merge_expire' AND event.reason = 'retention_expired'
                  AND event.ended_at_utc = unit.processed_at_utc)
                OR (SELECT count(*) FROM app_private.personal_target_merge_generation_members_v1 member
                  WHERE member.generation_id = unit.generation_id) <> 2
                OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 member
                  WHERE member.generation_id = unit.generation_id)
                OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
                  JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING (pending_fact_id)
                  WHERE pending.generation_id = unit.generation_id)
              END
              OR EXISTS (
                SELECT 1 FROM app_data.promotion_targets target
                WHERE (target.promotion_target_id = unit.promotion_target_id OR EXISTS (
                    SELECT 1 FROM app_private.personal_target_merge_generation_members_v1 member
                    WHERE member.generation_id = unit.generation_id AND member.promotion_target_id = target.promotion_target_id))
                  AND (target.workspace_id <> receipt.workspace_id OR target.status <> 'anonymized'
                    OR target.phone IS NOT NULL OR target.email IS NOT NULL OR target.display_name <> '已匿名化对象'
                    OR target.anonymized_at IS DISTINCT FROM unit.processed_at_utc OR target.anonymization_reason <> 'retention_expired'
                    OR EXISTS (SELECT 1 FROM app_data.promotion_target_assignments assignment
                      WHERE assignment.promotion_target_id = target.promotion_target_id AND assignment.ended_at IS NULL)
                    OR (unit.generation_id IS NOT NULL AND NOT EXISTS (
                      SELECT 1 FROM app_data.promotion_target_retention_events event
                      WHERE event.actor_app_user_id = receipt.actor_app_user_id
                        AND event.mutation_id = 'merge-expired:' || unit.child_request_id::text || ':' || target.promotion_target_id::text
                        AND event.workspace_id = receipt.workspace_id AND event.promotion_target_id = target.promotion_target_id
                        AND event.event_type = 'anonymized' AND event.reason = 'retention_expired'
                        AND event.occurred_at = unit.processed_at_utc)))
              )
            )))
      )
    FROM app_private.personal_target_expiry_dispatch_requests_v1 receipt
    CROSS JOIN LATERAL (
      SELECT count(*) total, count(*) FILTER (WHERE unit.outcome = 'expired') expired,
        count(*) FILTER (WHERE unit.outcome = 'skipped') skipped, count(*) FILTER (WHERE unit.outcome = 'failed') failed,
        min(unit.unit_ordinal) first_ordinal, max(unit.unit_ordinal) last_ordinal
      FROM app_private.personal_target_expiry_dispatch_units_v1 unit
      WHERE unit.actor_app_user_id = receipt.actor_app_user_id AND unit.request_id = receipt.request_id
    ) counts
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id), false);
$function$;

CREATE FUNCTION app_private.dispatch_assigned_personal_target_expiry_v1(
  trusted_app_user_id uuid, trusted_workspace_id uuid,
  trusted_project_id uuid, requested_request_id uuid
)
RETURNS TABLE (unit_kind text, unit_id uuid, outcome text, failure_code text,
  failure_sqlstate text, processed_at_utc timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  replay_row app_private.personal_target_expiry_dispatch_requests_v1%ROWTYPE;
  fixed_units jsonb;
  fixed_target_ids uuid[];
  child_key text;
  unit_row record;
  target_ids uuid[];
  generation_row app_private.personal_target_merge_generations_v1%ROWTYPE;
  selected_at_value timestamptz;
  completed_at_value timestamptz;
  processed_at_value timestamptz;
  outcome_value text;
  failure_code_value text;
  failure_sqlstate_value text;
  error_message text;
  due_at_value timestamptz;
  action_results jsonb;
  results jsonb := '[]'::jsonb;
  ordinal_value integer := 0;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL OR requested_request_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid personal target expiry dispatch request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target expiry dispatch requires read committed';
  END IF;
  IF NOT app_data.promotion_target_context_authorized(trusted_app_user_id, trusted_workspace_id, trusted_project_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.user_current_projects current_project
      WHERE current_project.app_user_id = trusted_app_user_id AND current_project.project_id = trusted_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal target expiry dispatch is forbidden';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));
  IF NOT app_data.promotion_target_context_authorized(trusted_app_user_id, trusted_workspace_id, trusted_project_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.user_current_projects current_project
      WHERE current_project.app_user_id = trusted_app_user_id AND current_project.project_id = trusted_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal target expiry dispatch is forbidden';
  END IF;
  SELECT receipt.* INTO replay_row FROM app_private.personal_target_expiry_dispatch_requests_v1 receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id;
  IF FOUND THEN
    IF replay_row.workspace_id <> trusted_workspace_id OR replay_row.project_id <> trusted_project_id THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'personal target expiry dispatch request was reused';
    END IF;
    IF NOT app_private.personal_target_expiry_dispatch_receipt_valid_v1(trusted_app_user_id, requested_request_id) THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch receipt is incomplete';
    END IF;
    RETURN QUERY SELECT CASE WHEN unit.generation_id IS NULL THEN 'target' ELSE 'generation' END,
      coalesce(unit.generation_id, unit.promotion_target_id), unit.outcome, unit.failure_code,
      unit.failure_sqlstate, unit.processed_at_utc
      FROM app_private.personal_target_expiry_dispatch_units_v1 unit
      WHERE unit.actor_app_user_id = trusted_app_user_id AND unit.request_id = requested_request_id ORDER BY unit.unit_ordinal;
    RETURN;
  END IF;

  selected_at_value := clock_timestamp();
  WITH candidates AS (
    SELECT DISTINCT CASE WHEN member.generation_id IS NULL THEN 'target' ELSE 'generation' END AS kind,
      coalesce(member.generation_id, target.promotion_target_id) AS id
    FROM app_data.promotion_targets target
    JOIN app_data.promotion_target_assignments assignment ON assignment.promotion_target_id = target.promotion_target_id
      AND assignment.app_user_id = trusted_app_user_id AND assignment.ended_at IS NULL
    LEFT JOIN app_private.personal_target_merge_active_members_v1 member ON member.promotion_target_id = target.promotion_target_id
    WHERE target.workspace_id = trusted_workspace_id AND target.status = 'active'
      AND app_data.promotion_target_review_due_at(target.promotion_target_id) <= selected_at_value
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('kind', candidate.kind, 'id', candidate.id,
      'child', md5('personal-target-expiry-v1:' || trusted_app_user_id::text || ':' || requested_request_id::text
        || ':' || candidate.kind || ':' || candidate.id::text)::uuid,
      'targets', CASE WHEN candidate.kind = 'target' THEN ARRAY[candidate.id] ELSE ARRAY(
        SELECT member.promotion_target_id FROM app_private.personal_target_merge_generation_members_v1 member
        WHERE member.generation_id = candidate.id ORDER BY member.promotion_target_id) END)
    ORDER BY candidate.kind COLLATE "C", candidate.id), '[]'::jsonb) INTO fixed_units FROM candidates candidate;
  SELECT coalesce(array_agg(DISTINCT item.value::uuid), ARRAY[]::uuid[]) INTO fixed_target_ids
    FROM jsonb_array_elements(fixed_units) unit CROSS JOIN LATERAL jsonb_array_elements_text(unit->'targets') item;

  -- Old automatic expiry uses retention-expired:, never these child keys.
  FOR child_key IN SELECT CASE WHEN unit.kind = 'target' THEN 'owner-expiry-v1:' || unit.child::text ELSE unit.child::text END
    FROM jsonb_to_recordset(fixed_units) AS unit(kind text, child uuid)
    ORDER BY (CASE WHEN unit.kind = 'target' THEN 'owner-expiry-v1:' || unit.child::text ELSE unit.child::text END) COLLATE "C"
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || child_key, 0));
  END LOOP;
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  PERFORM 1 FROM app_data.promotion_targets target
    WHERE target.promotion_target_id = ANY(fixed_target_ids) AND target.workspace_id = trusted_workspace_id
    ORDER BY target.created_at, target.promotion_target_id FOR UPDATE;
  PERFORM 1 FROM app_data.promotion_target_assignments assignment
    JOIN app_data.promotion_targets target USING (promotion_target_id)
    WHERE target.promotion_target_id = ANY(fixed_target_ids) AND target.workspace_id = trusted_workspace_id
      AND assignment.ended_at IS NULL
    ORDER BY assignment.promotion_target_id, assignment.assignment_id FOR UPDATE OF assignment;
  IF NOT app_data.promotion_target_context_authorized(trusted_app_user_id, trusted_workspace_id, trusted_project_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.user_current_projects current_project
      WHERE current_project.app_user_id = trusted_app_user_id AND current_project.project_id = trusted_project_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal target expiry dispatch is forbidden';
  END IF;

  FOR unit_row IN SELECT * FROM jsonb_to_recordset(fixed_units) AS unit(kind text, id uuid, child uuid, targets uuid[]) LOOP
    ordinal_value := ordinal_value + 1;
    outcome_value := NULL; failure_code_value := NULL; failure_sqlstate_value := NULL; processed_at_value := NULL;
    target_ids := unit_row.targets;
    BEGIN
      IF unit_row.kind = 'generation' THEN
        SELECT generation.* INTO generation_row FROM app_private.personal_target_merge_generations_v1 generation
          WHERE generation.generation_id = unit_row.id AND generation.workspace_id = trusted_workspace_id
            AND generation.created_by_app_user_id = trusted_app_user_id;
        IF NOT FOUND OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 event
          WHERE event.generation_id = unit_row.id) THEN
          outcome_value := 'skipped'; failure_code_value := 'unit_unavailable';
        ELSIF cardinality(target_ids) <> 2
          OR target_ids IS DISTINCT FROM ARRAY(SELECT member.promotion_target_id
            FROM app_private.personal_target_merge_generation_members_v1 member WHERE member.generation_id = unit_row.id
            ORDER BY member.promotion_target_id)
          OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1 member
            WHERE member.generation_id = unit_row.id) <> 2
          OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1 member
            WHERE member.generation_id = unit_row.id AND member.promotion_target_id = ANY(target_ids)
              AND member.workspace_id = trusted_workspace_id AND member.target_type = generation_row.target_type) <> 2
          OR (SELECT count(*) FROM app_data.promotion_targets target WHERE target.promotion_target_id = ANY(target_ids)
            AND target.workspace_id = trusted_workspace_id AND target.target_type = generation_row.target_type) <> 2 THEN
          RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch generation is incomplete';
        END IF;
      ELSIF EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 member
        WHERE member.promotion_target_id = unit_row.id) THEN
        outcome_value := 'skipped'; failure_code_value := 'topology_changed';
      END IF;
      IF outcome_value IS NULL THEN
        IF (SELECT count(*) FROM app_data.promotion_targets target WHERE target.promotion_target_id = ANY(target_ids)
          AND target.workspace_id = trusted_workspace_id AND target.status = 'active') <> cardinality(target_ids) THEN
          outcome_value := 'skipped'; failure_code_value := 'unit_unavailable';
        ELSIF (SELECT count(*) FROM app_data.promotion_target_assignments assignment
          WHERE assignment.promotion_target_id = ANY(target_ids) AND assignment.app_user_id = trusted_app_user_id
            AND assignment.ended_at IS NULL) <> cardinality(target_ids) THEN
          outcome_value := 'skipped'; failure_code_value := 'assignment_unavailable';
        ELSE
          SELECT min(app_data.promotion_target_review_due_at(target.promotion_target_id)) INTO due_at_value
            FROM app_data.promotion_targets target WHERE target.promotion_target_id = ANY(target_ids);
          IF due_at_value IS NULL THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch due is unavailable';
          ELSIF due_at_value > clock_timestamp() THEN
            outcome_value := 'skipped'; failure_code_value := 'not_due';
          END IF;
        END IF;
      END IF;
      IF outcome_value IS NULL THEN
        IF unit_row.kind = 'generation' THEN
          IF EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 event
            WHERE event.actor_app_user_id = trusted_app_user_id AND event.request_id = unit_row.child) THEN
            RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'personal target expiry dispatch child was reused';
          END IF;
          processed_at_value := app_private.expire_known_source_personal_target_merge_generation_v1(
            trusted_app_user_id, trusted_workspace_id, trusted_project_id, unit_row.child, unit_row.id);
          IF NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 event
            WHERE event.actor_app_user_id = trusted_app_user_id AND event.request_id = unit_row.child
              AND event.generation_id = unit_row.id AND event.workspace_id = trusted_workspace_id AND event.project_id = trusted_project_id
              AND event.operation = 'personal_target_known_source_merge_expire' AND event.reason = 'retention_expired'
              AND event.outcome = 'ended' AND event.target_count = 2 AND event.ended_at_utc = processed_at_value)
            OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 member WHERE member.generation_id = unit_row.id)
            OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
              JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING (pending_fact_id)
              WHERE pending.generation_id = unit_row.id)
            OR (SELECT count(*) FROM app_data.promotion_target_retention_events event
              WHERE event.actor_app_user_id = trusted_app_user_id AND event.workspace_id = trusted_workspace_id
                AND event.promotion_target_id = ANY(target_ids) AND event.event_type = 'anonymized' AND event.reason = 'retention_expired'
                AND event.occurred_at = processed_at_value
                AND event.mutation_id = 'merge-expired:' || unit_row.child::text || ':' || event.promotion_target_id::text) <> 2 THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch generation cleanup is incomplete';
          END IF;
        ELSE
          child_key := 'owner-expiry-v1:' || unit_row.child::text;
          IF EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events event
            WHERE event.actor_app_user_id = trusted_app_user_id AND event.mutation_id = child_key) THEN
            RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'personal target expiry dispatch child was reused';
          END IF;
          SELECT jsonb_agg(action.result) INTO action_results FROM app_data.apply_promotion_target_retention_action(
            trusted_app_user_id, trusted_workspace_id, trusted_project_id, unit_row.id,
            'anonymize', 'retention_expired', child_key) action;
          SELECT event.occurred_at INTO processed_at_value FROM app_data.promotion_target_retention_events event
            WHERE event.actor_app_user_id = trusted_app_user_id AND event.mutation_id = child_key
              AND event.workspace_id = trusted_workspace_id AND event.promotion_target_id = unit_row.id
              AND event.event_type = 'anonymized' AND event.reason = 'retention_expired';
          IF processed_at_value IS NULL OR action_results IS DISTINCT FROM jsonb_build_array(jsonb_build_object(
            'target_id', unit_row.id, 'status', 'anonymized', 'duplicate', false, 'review_due_at', NULL)) THEN
            RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch target receipt is incomplete';
          END IF;
        END IF;
        IF (SELECT count(*) FROM app_data.promotion_targets target WHERE target.promotion_target_id = ANY(target_ids)
          AND target.workspace_id = trusted_workspace_id AND target.status = 'anonymized' AND target.phone IS NULL AND target.email IS NULL
          AND target.display_name = '已匿名化对象' AND target.anonymized_at = processed_at_value
          AND target.anonymization_reason = 'retention_expired') <> cardinality(target_ids)
          OR EXISTS (SELECT 1 FROM app_data.promotion_target_assignments assignment
            WHERE assignment.promotion_target_id = ANY(target_ids) AND assignment.ended_at IS NULL) THEN
          RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch anonymization is incomplete';
        END IF;
        outcome_value := 'expired';
      END IF;
    EXCEPTION
      WHEN integrity_constraint_violation OR object_not_in_prerequisite_state THEN
        GET STACKED DIAGNOSTICS failure_sqlstate_value = RETURNED_SQLSTATE;
        IF failure_sqlstate_value <> '55000' AND failure_sqlstate_value NOT LIKE '23%' THEN RAISE; END IF;
        outcome_value := 'failed'; processed_at_value := NULL;
        failure_code_value := CASE WHEN failure_sqlstate_value = '23505' THEN 'request_conflict' ELSE 'integrity_failure' END;
      WHEN invalid_parameter_value THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        IF error_message NOT IN ('personal target merge generation is not expired', 'promotion target retention is not expired') THEN RAISE; END IF;
        outcome_value := 'skipped'; failure_code_value := 'not_due'; processed_at_value := NULL;
      WHEN insufficient_privilege THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        IF error_message NOT IN ('known-source personal target merge expiry is forbidden', 'promotion target retention access is forbidden')
          OR NOT app_data.promotion_target_context_authorized(trusted_app_user_id, trusted_workspace_id, trusted_project_id)
          OR NOT EXISTS (SELECT 1 FROM app_data.user_current_projects current_project
            WHERE current_project.app_user_id = trusted_app_user_id AND current_project.project_id = trusted_project_id) THEN RAISE; END IF;
        outcome_value := 'skipped'; failure_code_value := 'unit_unavailable'; processed_at_value := NULL;
    END;
    IF NOT app_data.promotion_target_context_authorized(trusted_app_user_id, trusted_workspace_id, trusted_project_id)
      OR NOT EXISTS (SELECT 1 FROM app_data.user_current_projects current_project
        WHERE current_project.app_user_id = trusted_app_user_id AND current_project.project_id = trusted_project_id) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal target expiry dispatch is forbidden';
    END IF;
    results := results || jsonb_build_array(jsonb_build_object('ordinal', ordinal_value,
      'target', CASE WHEN unit_row.kind = 'target' THEN unit_row.id END,
      'generation', CASE WHEN unit_row.kind = 'generation' THEN unit_row.id END,
      'child', unit_row.child, 'outcome', outcome_value, 'code', failure_code_value,
      'sqlstate', failure_sqlstate_value, 'processed', processed_at_value));
  END LOOP;

  completed_at_value := clock_timestamp();
  INSERT INTO app_private.personal_target_expiry_dispatch_requests_v1
    (actor_app_user_id, request_id, workspace_id, project_id, selected_at_utc, completed_at_utc,
      unit_count, expired_count, skipped_count, failed_count)
    SELECT trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id, selected_at_value, completed_at_value,
      count(*), count(*) FILTER (WHERE item->>'outcome' = 'expired'), count(*) FILTER (WHERE item->>'outcome' = 'skipped'),
      count(*) FILTER (WHERE item->>'outcome' = 'failed') FROM jsonb_array_elements(results) item;
  INSERT INTO app_private.personal_target_expiry_dispatch_units_v1
    (actor_app_user_id, request_id, unit_ordinal, promotion_target_id, generation_id, child_request_id,
      outcome, failure_code, failure_sqlstate, processed_at_utc)
    SELECT trusted_app_user_id, requested_request_id, item.ordinal, item.target, item.generation, item.child,
      item.outcome, item.code, item.sqlstate, item.processed
    FROM jsonb_to_recordset(results) AS item(ordinal integer, target uuid, generation uuid, child uuid,
      outcome text, code text, sqlstate text, processed timestamptz);
  IF NOT app_private.personal_target_expiry_dispatch_receipt_valid_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal target expiry dispatch receipt is incomplete';
  END IF;
  RETURN QUERY SELECT CASE WHEN unit.generation_id IS NULL THEN 'target' ELSE 'generation' END,
    coalesce(unit.generation_id, unit.promotion_target_id), unit.outcome, unit.failure_code,
    unit.failure_sqlstate, unit.processed_at_utc
    FROM app_private.personal_target_expiry_dispatch_units_v1 unit
    WHERE unit.actor_app_user_id = trusted_app_user_id AND unit.request_id = requested_request_id ORDER BY unit.unit_ordinal;
END
$function$;

REVOKE ALL ON TABLE app_private.personal_target_expiry_dispatch_requests_v1,
  app_private.personal_target_expiry_dispatch_units_v1 FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION app_private.personal_target_expiry_dispatch_receipt_valid_v1(uuid,uuid),
  app_private.dispatch_assigned_personal_target_expiry_v1(uuid,uuid,uuid,uuid) FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; relation regclass; candidate regprocedure;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_target_expiry_dispatch_requests_v1'::regclass,
    'app_private.personal_target_expiry_dispatch_units_v1'::regclass] LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO %I', relation, trusted_owner);
  END LOOP;
  FOREACH candidate IN ARRAY ARRAY[
    'app_private.personal_target_expiry_dispatch_receipt_valid_v1(uuid,uuid)'::regprocedure,
    'app_private.dispatch_assigned_personal_target_expiry_v1(uuid,uuid,uuid,uuid)'::regprocedure] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', candidate, trusted_owner);
  END LOOP;
END
$owner$;
