-- 0020_promotion_target_retention.sql
--
-- 对象资料只在目的仍有效时保留。明确撤回立即匿名化；未续期的到期资料
-- 在下一次在线目录或复核读取前匿名化。接触事实与去标识统计不删除。

ALTER TABLE app_data.promotion_targets
  ADD COLUMN anonymized_at timestamptz,
  ADD COLUMN anonymization_reason text CHECK (
    anonymization_reason IN ('withdrawal', 'retention_expired')
  ),
  ADD CONSTRAINT promotion_target_anonymization_shape CHECK (
    (status = 'active'
      AND anonymized_at IS NULL
      AND anonymization_reason IS NULL)
    OR
    (status = 'anonymized'
      AND anonymized_at IS NOT NULL
      AND anonymization_reason IS NOT NULL
      AND phone IS NULL
      AND email IS NULL)
  );

CREATE TABLE app_data.promotion_target_retention_policies (
  workspace_id uuid PRIMARY KEY
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  retention_months integer NOT NULL DEFAULT 12 CHECK (
    retention_months BETWEEN 1 AND 12
  ),
  updated_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE app_data.promotion_target_retention_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  promotion_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  actor_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  event_type text NOT NULL CHECK (event_type IN ('renewed', 'anonymized')),
  reason text NOT NULL CHECK (
    reason IN ('purpose_confirmed', 'withdrawal', 'retention_expired')
  ),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  mutation_id text NOT NULL CHECK (
    length(btrim(mutation_id)) BETWEEN 1 AND 120
  ),
  review_due_at timestamptz,
  UNIQUE (actor_app_user_id, mutation_id),
  CHECK (
    (event_type = 'renewed'
      AND reason = 'purpose_confirmed'
      AND review_due_at IS NOT NULL)
    OR
    (event_type = 'anonymized'
      AND reason IN ('withdrawal', 'retention_expired')
      AND review_due_at IS NULL)
  )
);

CREATE INDEX promotion_target_retention_events_target_time
  ON app_data.promotion_target_retention_events (
    promotion_target_id,
    occurred_at DESC
  );

REVOKE ALL PRIVILEGES
  ON app_data.promotion_target_retention_policies,
     app_data.promotion_target_retention_events
  FROM tongxingzhe_runtime;

CREATE TRIGGER promotion_target_retention_events_immutable
BEFORE UPDATE OR DELETE ON app_data.promotion_target_retention_events
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_data.promotion_target_retention_reference_at(
  requested_target_id uuid
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT GREATEST(
    target_row.created_at,
    COALESCE((
      SELECT MAX(contact_row.occurred_at_utc)
      FROM app_data.contacts AS contact_row
      JOIN app_data.contact_target_links AS link_row
        ON link_row.contact_id = contact_row.contact_id
       AND link_row.revision_number = contact_row.current_revision
      WHERE link_row.promotion_target_id = requested_target_id
        AND contact_row.lifecycle_status = 'active'
    ), target_row.created_at),
    COALESCE((
      SELECT MAX(event_row.occurred_at)
      FROM app_data.promotion_target_retention_events AS event_row
      WHERE event_row.promotion_target_id = requested_target_id
        AND event_row.event_type = 'renewed'
    ), target_row.created_at)
  )
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = requested_target_id;
$function$;

CREATE FUNCTION app_data.promotion_target_review_due_at(
  requested_target_id uuid
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT app_data.promotion_target_retention_reference_at(
      target_row.promotion_target_id
    ) + make_interval(months => COALESCE(
      policy_row.retention_months,
      12
    ))
  FROM app_data.promotion_targets AS target_row
  LEFT JOIN app_data.promotion_target_retention_policies AS policy_row
    ON policy_row.workspace_id = target_row.workspace_id
  WHERE target_row.promotion_target_id = requested_target_id
    AND target_row.status = 'active';
$function$;

-- Privacy erasure is the only permitted rewrite of sensitive audit text.
-- The public/runtime role still has no table update privilege.
CREATE OR REPLACE FUNCTION
  app_data.reject_promotion_target_relationship_revision_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' AND TG_TABLE_NAME IN (
      'promotion_target_relationship_revisions',
      'promotion_target_relationship_conflicts'
    )
  THEN
    IF current_setting(
      'app_data.anonymizing_promotion_target_id',
      true
    ) = OLD.promotion_target_id::text
    THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'promotion target relationship revisions are append-only';
END
$function$;

CREATE OR REPLACE FUNCTION
  app_data.validate_promotion_target_institution_relation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  person_row app_data.promotion_targets%ROWTYPE;
  institution_row app_data.promotion_targets%ROWTYPE;
  anonymizing_target_id text := current_setting(
    'app_data.anonymizing_promotion_target_id',
    true
  );
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'promotion target institution relationships are historical';
  END IF;

  IF TG_OP = 'UPDATE'
    AND anonymizing_target_id IN (
      OLD.person_target_id::text,
      OLD.institution_target_id::text
    )
    AND OLD.workspace_id = NEW.workspace_id
    AND OLD.person_target_id = NEW.person_target_id
    AND OLD.institution_target_id = NEW.institution_target_id
    AND OLD.relationship_kind = NEW.relationship_kind
    AND OLD.started_at = NEW.started_at
    AND OLD.created_by_app_user_id = NEW.created_by_app_user_id
    AND OLD.created_at = NEW.created_at
    AND NEW.role_description = '[已匿名化]'
    AND (
      (OLD.ended_at IS NULL
        AND NEW.ended_at IS NOT NULL
        AND NEW.current_revision = OLD.current_revision + 1)
      OR
      (OLD.ended_at IS NOT NULL
        AND NEW.ended_at = OLD.ended_at
        AND NEW.current_revision = OLD.current_revision)
    )
  THEN
    RETURN NEW;
  END IF;

  SELECT target_row.* INTO person_row
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.person_target_id;
  SELECT target_row.* INTO institution_row
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.institution_target_id;

  IF person_row.promotion_target_id IS NULL
    OR person_row.workspace_id <> NEW.workspace_id
    OR person_row.target_type <> 'person'
    OR person_row.status <> 'active'
    OR institution_row.promotion_target_id IS NULL
    OR institution_row.workspace_id <> NEW.workspace_id
    OR institution_row.target_type <> 'institution'
    OR institution_row.status <> 'active'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'institution relationship endpoints are invalid';
  END IF;

  IF TG_OP = 'UPDATE' AND (
    OLD.workspace_id <> NEW.workspace_id
    OR OLD.person_target_id <> NEW.person_target_id
    OR OLD.institution_target_id <> NEW.institution_target_id
    OR OLD.relationship_kind <> NEW.relationship_kind
    OR OLD.role_description IS DISTINCT FROM NEW.role_description
    OR OLD.started_at <> NEW.started_at
    OR OLD.created_by_app_user_id <> NEW.created_by_app_user_id
    OR OLD.created_at <> NEW.created_at
    OR OLD.ended_at IS NOT NULL
    OR NEW.ended_at IS NULL
    OR NEW.current_revision <> OLD.current_revision + 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'institution relationship history cannot be rewritten';
  END IF;
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_data.anonymize_promotion_target_internal(
  trusted_app_user_id uuid,
  requested_target_id uuid,
  requested_reason text,
  event_time timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  relationship_row app_data.promotion_target_project_relationships%ROWTYPE;
  institution_row
    app_data.promotion_target_institution_relationships%ROWTYPE;
  changed_fields_value text[];
  next_revision integer;
BEGIN
  PERFORM set_config(
    'app_data.anonymizing_promotion_target_id',
    requested_target_id::text,
    true
  );

  FOR relationship_row IN
    SELECT relation_row.*
    FROM app_data.promotion_target_project_relationships AS relation_row
    WHERE relation_row.promotion_target_id = requested_target_id
    FOR UPDATE
  LOOP
    changed_fields_value := ARRAY[]::text[];
    IF relationship_row.current_lifecycle_status <> 'ended' THEN
      changed_fields_value := array_append(
        changed_fields_value,
        'lifecycle_status'
      );
    END IF;
    IF relationship_row.current_follow_up_note IS NOT NULL THEN
      changed_fields_value := array_append(
        changed_fields_value,
        'follow_up_note'
      );
    END IF;
    IF cardinality(changed_fields_value) > 0 THEN
      next_revision := relationship_row.current_revision + 1;
      UPDATE app_data.promotion_target_project_relationships
      SET current_lifecycle_status = 'ended',
          current_follow_up_note = NULL,
          current_revision = next_revision,
          updated_by_app_user_id = trusted_app_user_id,
          updated_at = event_time
      WHERE promotion_target_id = requested_target_id
        AND project_id = relationship_row.project_id;
      INSERT INTO app_data.promotion_target_relationship_revisions (
        promotion_target_id,
        project_id,
        revision_number,
        old_stage,
        new_stage,
        old_lifecycle_status,
        new_lifecycle_status,
        follow_up_note,
        changed_fields,
        reason_code,
        changed_by_app_user_id,
        changed_at
      ) VALUES (
        requested_target_id,
        relationship_row.project_id,
        next_revision,
        relationship_row.current_stage,
        relationship_row.current_stage,
        relationship_row.current_lifecycle_status,
        'ended',
        NULL,
        changed_fields_value,
        'target_request',
        trusted_app_user_id,
        event_time
      );
    END IF;
  END LOOP;

  UPDATE app_data.promotion_target_relationship_revisions
  SET follow_up_note = NULL,
      reason_detail = NULL,
      requested_follow_up_note = NULL
  WHERE promotion_target_id = requested_target_id
    AND (
      follow_up_note IS NOT NULL
      OR reason_detail IS NOT NULL
      OR requested_follow_up_note IS NOT NULL
    );
  UPDATE app_data.promotion_target_relationship_conflicts
  SET proposed_follow_up_note = NULL,
      proposed_reason_detail = NULL
  WHERE promotion_target_id = requested_target_id
    AND (
      proposed_follow_up_note IS NOT NULL
      OR proposed_reason_detail IS NOT NULL
    );

  FOR institution_row IN
    SELECT relation_row.*
    FROM app_data.promotion_target_institution_relationships AS relation_row
    WHERE relation_row.person_target_id = requested_target_id
       OR relation_row.institution_target_id = requested_target_id
    FOR UPDATE
  LOOP
    IF institution_row.ended_at IS NULL THEN
      next_revision := institution_row.current_revision + 1;
      UPDATE app_data.promotion_target_institution_relationships
      SET role_description = '[已匿名化]',
          ended_at = event_time,
          current_revision = next_revision,
          updated_by_app_user_id = trusted_app_user_id,
          updated_at = event_time
      WHERE relationship_id = institution_row.relationship_id;
      INSERT INTO app_data.promotion_target_institution_relation_revisions (
        relationship_id,
        revision_number,
        event_type,
        old_status,
        new_status,
        ended_at,
        changed_by_app_user_id,
        changed_at,
        mutation_id,
        requested_base_revision
      ) VALUES (
        institution_row.relationship_id,
        next_revision,
        'ended',
        'active',
        'ended',
        event_time,
        trusted_app_user_id,
        event_time,
        'target-anonymized:' || institution_row.relationship_id::text,
        institution_row.current_revision
      );
    ELSIF institution_row.role_description <> '[已匿名化]' THEN
      UPDATE app_data.promotion_target_institution_relationships
      SET role_description = '[已匿名化]',
          updated_by_app_user_id = trusted_app_user_id,
          updated_at = event_time
      WHERE relationship_id = institution_row.relationship_id;
    END IF;
  END LOOP;

  UPDATE app_data.promotion_target_assignments
  SET ended_at = event_time,
      end_reason = 'target_anonymized'
  WHERE promotion_target_id = requested_target_id
    AND ended_at IS NULL;

  UPDATE app_data.promotion_targets
  SET display_name = '已匿名化对象',
      phone = NULL,
      email = NULL,
      status = 'anonymized',
      anonymized_at = event_time,
      anonymization_reason = requested_reason
  WHERE promotion_target_id = requested_target_id
    AND status = 'active';
END
$function$;

CREATE FUNCTION app_data.apply_promotion_target_retention_action(
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
  event_time timestamptz := clock_timestamp();
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
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid promotion target retention action';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target retention access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || normalized_mutation_id,
    0
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
      RAISE EXCEPTION USING
        ERRCODE = '23505',
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

  SELECT candidate.* INTO target_row
  FROM app_data.promotion_targets AS candidate
  WHERE candidate.promotion_target_id = requested_target_id
    AND candidate.workspace_id = trusted_workspace_id
  FOR UPDATE;
  IF NOT FOUND OR target_row.status <> 'active' OR NOT EXISTS (
    SELECT 1
    FROM app_data.promotion_target_assignments AS assignment_row
    WHERE assignment_row.promotion_target_id = requested_target_id
      AND assignment_row.app_user_id = trusted_app_user_id
      AND assignment_row.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target retention access is forbidden';
  END IF;

  due_at := app_data.promotion_target_review_due_at(requested_target_id);
  IF requested_reason = 'retention_expired' AND due_at > event_time THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'promotion target retention is not expired';
  END IF;
  IF requested_action = 'renew' AND due_at <= event_time THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'promotion target retention already expired';
  END IF;

  IF requested_action = 'renew' THEN
    INSERT INTO app_data.promotion_target_retention_events (
      workspace_id,
      promotion_target_id,
      actor_app_user_id,
      event_type,
      reason,
      occurred_at,
      mutation_id,
      review_due_at
    ) VALUES (
      trusted_workspace_id,
      requested_target_id,
      trusted_app_user_id,
      'renewed',
      'purpose_confirmed',
      event_time,
      normalized_mutation_id,
      event_time + make_interval(months => COALESCE((
        SELECT policy_row.retention_months
        FROM app_data.promotion_target_retention_policies AS policy_row
        WHERE policy_row.workspace_id = trusted_workspace_id
      ), 12))
    ) RETURNING review_due_at INTO due_at;
    RETURN QUERY SELECT jsonb_build_object(
      'target_id', requested_target_id,
      'status', 'active',
      'duplicate', false,
      'review_due_at', due_at
    );
    RETURN;
  END IF;

  PERFORM app_data.anonymize_promotion_target_internal(
    trusted_app_user_id,
    requested_target_id,
    requested_reason,
    event_time
  );
  INSERT INTO app_data.promotion_target_retention_events (
    workspace_id,
    promotion_target_id,
    actor_app_user_id,
    event_type,
    reason,
    occurred_at,
    mutation_id,
    review_due_at
  ) VALUES (
    trusted_workspace_id,
    requested_target_id,
    trusted_app_user_id,
    'anonymized',
    requested_reason,
    event_time,
    normalized_mutation_id,
    NULL
  );
  RETURN QUERY SELECT jsonb_build_object(
    'target_id', requested_target_id,
    'status', 'anonymized',
    'duplicate', false,
    'review_due_at', NULL
  );
END
$function$;

CREATE FUNCTION app_data.expire_assigned_promotion_targets(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  due_row record;
BEGIN
  FOR due_row IN
    SELECT
      target_row.promotion_target_id,
      app_data.promotion_target_review_due_at(
        target_row.promotion_target_id
      ) AS due_at
    FROM app_data.promotion_targets AS target_row
    JOIN app_data.promotion_target_assignments AS assignment_row
      ON assignment_row.promotion_target_id =
        target_row.promotion_target_id
     AND assignment_row.app_user_id = trusted_app_user_id
     AND assignment_row.ended_at IS NULL
    WHERE target_row.workspace_id = trusted_workspace_id
      AND target_row.status = 'active'
      AND app_data.promotion_target_review_due_at(
        target_row.promotion_target_id
      ) <= clock_timestamp()
    ORDER BY target_row.promotion_target_id
  LOOP
    PERFORM app_data.apply_promotion_target_retention_action(
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id,
      due_row.promotion_target_id,
      'anonymize',
      'retention_expired',
      'retention-expired:' || due_row.promotion_target_id::text || ':' ||
        extract(epoch FROM due_row.due_at)::bigint::text
    );
  END LOOP;
END
$function$;

CREATE FUNCTION app_data.list_promotion_target_retention_tasks(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (task jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target retention access is forbidden';
  END IF;
  PERFORM app_data.expire_assigned_promotion_targets(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  );
  RETURN QUERY
  SELECT jsonb_build_object(
    'target_id', target_row.promotion_target_id,
    'review_due_at', app_data.promotion_target_review_due_at(
      target_row.promotion_target_id
    )
  )
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active'
    AND app_data.promotion_target_review_due_at(
      target_row.promotion_target_id
    ) <= clock_timestamp() + interval '30 days'
  ORDER BY app_data.promotion_target_review_due_at(
    target_row.promotion_target_id
  ), target_row.promotion_target_id;
END
$function$;

CREATE FUNCTION app_data.configure_promotion_target_retention_policy(
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

CREATE OR REPLACE FUNCTION app_data.list_assigned_promotion_targets(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (target jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target access is forbidden';
  END IF;
  PERFORM app_data.expire_assigned_promotion_targets(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  );
  INSERT INTO app_data.promotion_target_access_events (
    workspace_id, promotion_target_id, actor_app_user_id, action
  )
  SELECT
    trusted_workspace_id,
    target_row.promotion_target_id,
    trusted_app_user_id,
    'viewed'
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active';
  RETURN QUERY
  SELECT app_data.promotion_target_document(target_row.promotion_target_id)
    || jsonb_build_object(
      'has_current_project_relationship',
        relationship_row.promotion_target_id IS NOT NULL,
      'project_relationship', CASE
        WHEN relationship_row.promotion_target_id IS NULL THEN NULL
        ELSE app_data.promotion_target_relationship_document(
          target_row.promotion_target_id,
          trusted_project_id,
          true
        )
      END
    )
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  LEFT JOIN app_data.promotion_target_project_relationships AS relationship_row
    ON relationship_row.promotion_target_id = target_row.promotion_target_id
   AND relationship_row.project_id = trusted_project_id
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active'
  ORDER BY target_row.created_at DESC, target_row.promotion_target_id;
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.promotion_target_retention_reference_at(uuid),
  app_data.promotion_target_review_due_at(uuid),
  app_data.anonymize_promotion_target_internal(uuid, uuid, text, timestamptz),
  app_data.expire_assigned_promotion_targets(uuid, uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL ON FUNCTION
  app_data.apply_promotion_target_retention_action(
    uuid, uuid, uuid, uuid, text, text, text
  ),
  app_data.list_promotion_target_retention_tasks(uuid, uuid, uuid),
  app_data.configure_promotion_target_retention_policy(
    uuid, uuid, uuid, integer
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.apply_promotion_target_retention_action(
    uuid, uuid, uuid, uuid, text, text, text
  ),
  app_data.list_promotion_target_retention_tasks(uuid, uuid, uuid),
  app_data.configure_promotion_target_retention_policy(
    uuid, uuid, uuid, integer
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.promotion_target_retention_policies IS
  'Workspace retention period, capped at the canonical 12-month maximum.';
COMMENT ON TABLE app_data.promotion_target_retention_events IS
  'PII-free append-only purpose renewals and anonymization audit.';
