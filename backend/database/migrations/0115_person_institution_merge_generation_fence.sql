-- Bind each side of a person/institution relationship independently to the
-- existing private merge ledger and serialize those writes on the 0114 fence.

ALTER TABLE app_data.promotion_target_institution_relationships
  ADD COLUMN person_merge_generation_id uuid,
  ADD COLUMN institution_merge_generation_id uuid,
  ADD CONSTRAINT pt_institution_relation_person_merge_member_fk
    FOREIGN KEY (person_merge_generation_id, person_target_id)
    REFERENCES app_private.personal_target_merge_generation_members_v1 (
      generation_id, promotion_target_id
    ) ON DELETE RESTRICT,
  ADD CONSTRAINT pt_institution_relation_institution_merge_member_fk
    FOREIGN KEY (institution_merge_generation_id, institution_target_id)
    REFERENCES app_private.personal_target_merge_generation_members_v1 (
      generation_id, promotion_target_id
    ) ON DELETE RESTRICT;

ALTER TABLE app_data.promotion_target_institution_relation_revisions
  ADD COLUMN person_merge_generation_id uuid,
  ADD COLUMN institution_merge_generation_id uuid;

CREATE FUNCTION app_private.acquire_personal_target_merge_generation_fence_v1()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
BEGIN
  UPDATE app_private.personal_target_merge_generation_fence_v1
  SET epoch = epoch + 1
  WHERE fence_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation fence is unavailable';
  END IF;
END
$function$;

-- Re-read the target after resolving its generation. The resolver waits on the
-- 0114 fence, so the pre-wait target row is not authoritative anymore.
CREATE OR REPLACE FUNCTION app_private.bind_personal_target_merge_generation_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  target_workspace_id uuid;
  target_type_value text;
  original_workspace_id uuid;
  original_target_type text;
  target_status text;
BEGIN
  IF NEW.merge_generation_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'merge generation is database assigned';
  END IF;

  SELECT target_row.workspace_id, target_row.target_type
    INTO target_workspace_id, target_type_value
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.promotion_target_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  original_workspace_id := target_workspace_id;
  original_target_type := target_type_value;

  NEW.merge_generation_id :=
    app_private.resolve_personal_target_merge_generation_v1(
      NEW.promotion_target_id,
      target_workspace_id,
      target_type_value
    );

  SELECT target_row.workspace_id, target_row.target_type, target_row.status
    INTO target_workspace_id, target_type_value, target_status
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.promotion_target_id;
  IF NOT FOUND
    OR target_workspace_id IS DISTINCT FROM original_workspace_id
    OR target_type_value IS DISTINCT FROM original_target_type
    OR target_status IS DISTINCT FROM 'active'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'personal target fact requires an active target';
  END IF;
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.bind_person_institution_merge_generations_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  relation_row app_data.promotion_target_institution_relationships%ROWTYPE;
  person_workspace_id uuid;
  person_type text;
  person_status text;
  institution_workspace_id uuid;
  institution_type text;
  institution_status text;
BEGIN
  IF NEW.person_merge_generation_id IS NOT NULL
    OR NEW.institution_merge_generation_id IS NOT NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'relationship merge generations are database assigned';
  END IF;

  IF TG_TABLE_NAME = 'promotion_target_institution_relationships' THEN
    relation_row.relationship_id := NEW.relationship_id;
    relation_row.workspace_id := NEW.workspace_id;
    relation_row.person_target_id := NEW.person_target_id;
    relation_row.institution_target_id := NEW.institution_target_id;
  ELSE
    SELECT relationship_row.* INTO relation_row
    FROM app_data.promotion_target_institution_relationships AS relationship_row
    WHERE relationship_row.relationship_id = NEW.relationship_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '23503',
        MESSAGE = 'institution relationship is missing';
    END IF;
  END IF;

  NEW.person_merge_generation_id :=
    app_private.resolve_personal_target_merge_generation_v1(
      relation_row.person_target_id,
      relation_row.workspace_id,
      'person'
    );
  NEW.institution_merge_generation_id :=
    app_private.resolve_personal_target_merge_generation_v1(
      relation_row.institution_target_id,
      relation_row.workspace_id,
      'institution'
    );

  -- The first resolver call takes the fence. Re-read endpoint lifecycle state
  -- after any wait so a writer cannot follow an anonymization with stale data.
  SELECT target_row.workspace_id, target_row.target_type, target_row.status
    INTO person_workspace_id, person_type, person_status
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = relation_row.person_target_id;
  SELECT target_row.workspace_id, target_row.target_type, target_row.status
    INTO institution_workspace_id, institution_type, institution_status
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = relation_row.institution_target_id;
  IF person_workspace_id IS DISTINCT FROM relation_row.workspace_id
    OR person_type IS DISTINCT FROM 'person'
    OR person_status IS DISTINCT FROM 'active'
    OR institution_workspace_id IS DISTINCT FROM relation_row.workspace_id
    OR institution_type IS DISTINCT FROM 'institution'
    OR institution_status IS DISTINCT FROM 'active'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'institution relationship endpoints are invalid';
  END IF;
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.reject_person_institution_merge_generation_change_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NEW.person_merge_generation_id
      IS DISTINCT FROM OLD.person_merge_generation_id
    OR NEW.institution_merge_generation_id
      IS DISTINCT FROM OLD.institution_merge_generation_id
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'relationship merge generations are database assigned';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER pt_institution_relation_bind_generations
BEFORE INSERT ON app_data.promotion_target_institution_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_private.bind_person_institution_merge_generations_v1();

CREATE TRIGGER pt_institution_relation_revision_bind_generations
BEFORE INSERT ON app_data.promotion_target_institution_relation_revisions
FOR EACH ROW EXECUTE FUNCTION
  app_private.bind_person_institution_merge_generations_v1();

CREATE TRIGGER pt_institution_relation_generations_immutable
BEFORE UPDATE OF person_merge_generation_id, institution_merge_generation_id
ON app_data.promotion_target_institution_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_person_institution_merge_generation_change_v1();

CREATE TRIGGER pt_institution_relation_revision_generations_immutable
BEFORE UPDATE OF person_merge_generation_id, institution_merge_generation_id
ON app_data.promotion_target_institution_relation_revisions
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_person_institution_merge_generation_change_v1();

-- Acquire the same 0114 fence before the first anonymization side effect.
CREATE OR REPLACE FUNCTION app_data.anonymize_promotion_target_internal(
  trusted_app_user_id uuid,
  requested_target_id uuid,
  requested_reason text,
  event_time timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  target_row app_data.promotion_targets%ROWTYPE;
  relationship_row app_data.promotion_target_project_relationships%ROWTYPE;
  institution_row
    app_data.promotion_target_institution_relationships%ROWTYPE;
  changed_fields_value text[];
  next_revision integer;
BEGIN
  SELECT candidate.* INTO target_row
  FROM app_data.promotion_targets AS candidate
  WHERE candidate.promotion_target_id = requested_target_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'promotion target anonymization is forbidden';
  END IF;

  -- The retention API holds the shared fence before acquiring tuple locks.
  IF app_private.resolve_personal_target_merge_generation_v1(
      requested_target_id, target_row.workspace_id, target_row.target_type
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'active merge member cannot be anonymized';
  END IF;

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
      changed_fields_value := array_append(changed_fields_value, 'lifecycle_status');
    END IF;
    IF relationship_row.current_follow_up_note IS NOT NULL THEN
      changed_fields_value := array_append(changed_fields_value, 'follow_up_note');
    END IF;
    IF cardinality(changed_fields_value) > 0 THEN
      next_revision := relationship_row.current_revision + 1;
      UPDATE app_data.promotion_target_project_relationships
      SET current_lifecycle_status = 'ended', current_follow_up_note = NULL,
          current_revision = next_revision,
          updated_by_app_user_id = trusted_app_user_id, updated_at = event_time
      WHERE promotion_target_id = requested_target_id
        AND project_id = relationship_row.project_id;
      INSERT INTO app_data.promotion_target_relationship_revisions (
        promotion_target_id, project_id, revision_number, old_stage, new_stage,
        old_lifecycle_status, new_lifecycle_status, follow_up_note,
        changed_fields, reason_code, changed_by_app_user_id, changed_at
      ) VALUES (
        requested_target_id, relationship_row.project_id, next_revision,
        relationship_row.current_stage, relationship_row.current_stage,
        relationship_row.current_lifecycle_status, 'ended', NULL,
        changed_fields_value, 'target_request', trusted_app_user_id, event_time
      );
    END IF;
  END LOOP;

  UPDATE app_data.promotion_target_relationship_revisions
  SET follow_up_note = NULL, reason_detail = NULL,
      requested_follow_up_note = NULL
  WHERE promotion_target_id = requested_target_id
    AND (follow_up_note IS NOT NULL OR reason_detail IS NOT NULL
      OR requested_follow_up_note IS NOT NULL);
  UPDATE app_data.promotion_target_relationship_conflicts
  SET proposed_follow_up_note = NULL, proposed_reason_detail = NULL
  WHERE promotion_target_id = requested_target_id
    AND (proposed_follow_up_note IS NOT NULL OR proposed_reason_detail IS NOT NULL);

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
      SET role_description = '[已匿名化]', ended_at = event_time,
          current_revision = next_revision,
          updated_by_app_user_id = trusted_app_user_id, updated_at = event_time
      WHERE relationship_id = institution_row.relationship_id;
      INSERT INTO app_data.promotion_target_institution_relation_revisions (
        relationship_id, revision_number, event_type, old_status, new_status,
        ended_at, changed_by_app_user_id, changed_at, mutation_id,
        requested_base_revision
      ) VALUES (
        institution_row.relationship_id, next_revision, 'ended', 'active',
        'ended', event_time, trusted_app_user_id, event_time,
        'target-anonymized:' || institution_row.relationship_id::text,
        institution_row.current_revision
      );
    ELSIF institution_row.role_description <> '[已匿名化]' THEN
      UPDATE app_data.promotion_target_institution_relationships
      SET role_description = '[已匿名化]',
          updated_by_app_user_id = trusted_app_user_id, updated_at = event_time
      WHERE relationship_id = institution_row.relationship_id;
    END IF;
  END LOOP;

  UPDATE app_data.promotion_target_assignments
  SET ended_at = event_time, end_reason = 'target_anonymized'
  WHERE promotion_target_id = requested_target_id AND ended_at IS NULL;
  UPDATE app_data.promotion_targets
  SET display_name = '已匿名化对象', phone = NULL, email = NULL,
      status = 'anonymized', anonymized_at = event_time,
      anonymization_reason = requested_reason
  WHERE promotion_target_id = requested_target_id AND status = 'active';
END
$function$;

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
    PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
    -- The fence wait is part of this mutation's linearization point. Refresh
    -- its timestamp afterward so anonymization cannot end a relation before
    -- a concurrent create that committed while this call was waiting.
    event_time := clock_timestamp();
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

CREATE OR REPLACE FUNCTION app_data.update_promotion_target_relationship(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_target_id uuid,
  expected_revision integer,
  requested_stage integer,
  requested_lifecycle_status text,
  requested_follow_up_note text,
  requested_reason_code text,
  requested_reason_detail text,
  requested_mutation_id text,
  requested_resolved_conflict_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  current_row app_data.promotion_target_project_relationships%ROWTYPE;
  base_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  replay_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  replay_conflict app_data.promotion_target_relationship_conflicts%ROWTYPE;
  resolved_conflict app_data.promotion_target_relationship_conflicts%ROWTYPE;
  normalized_note text := CASE
    WHEN requested_follow_up_note IS NULL
      OR btrim(requested_follow_up_note) = '' THEN NULL
    ELSE btrim(requested_follow_up_note)
  END;
  normalized_detail text := CASE
    WHEN requested_reason_detail IS NULL
      OR btrim(requested_reason_detail) = '' THEN NULL
    ELSE btrim(requested_reason_detail)
  END;
  normalized_mutation_id text := btrim(requested_mutation_id);
  proposed_fields text[] := ARRAY[]::text[];
  server_fields text[] := ARRAY[]::text[];
  conflicting_fields_value text[] := ARRAY[]::text[];
  changed_fields_value text[] := ARRAY[]::text[];
  effective_stage integer;
  effective_lifecycle_status text;
  effective_note text;
  conflict_id_value uuid;
  resolution_choice_value text;
  next_revision integer;
BEGIN
  IF requested_target_id IS NULL
    OR expected_revision IS NULL OR expected_revision < 1
    OR requested_stage IS NULL OR requested_stage NOT BETWEEN 0 AND 4
    OR requested_lifecycle_status IS NULL
    OR requested_lifecycle_status NOT IN ('active', 'paused', 'ended')
    OR requested_reason_code IS NULL
    OR requested_reason_code NOT IN (
      'progress_update', 'contact_lost', 'timing_changed',
      'requirements_changed', 'target_request', 'project_change',
      'correction', 'other'
    )
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
    OR (normalized_note IS NOT NULL AND length(normalized_note) > 4000)
    OR (normalized_detail IS NOT NULL AND length(normalized_detail) > 1000)
    OR (requested_reason_code = 'other' AND normalized_detail IS NULL)
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid promotion target relationship update';
  END IF;

  IF NOT app_data.promotion_target_relationship_authorized(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id,
    requested_target_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'promotion target relationship access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    requested_target_id::text || ':' || trusted_project_id::text, 0
  ));

  SELECT revision_row.* INTO replay_row
  FROM app_data.promotion_target_relationship_revisions AS revision_row
  WHERE revision_row.changed_by_app_user_id = trusted_app_user_id
    AND revision_row.mutation_id = normalized_mutation_id;
  IF FOUND THEN
    IF replay_row.promotion_target_id <> requested_target_id
      OR replay_row.project_id <> trusted_project_id
      OR replay_row.requested_base_revision <> expected_revision
      OR replay_row.requested_stage <> requested_stage
      OR replay_row.requested_lifecycle_status <> requested_lifecycle_status
      OR replay_row.requested_follow_up_note IS DISTINCT FROM normalized_note
      OR replay_row.reason_code <> requested_reason_code
      OR replay_row.reason_detail IS DISTINCT FROM normalized_detail
      OR replay_row.resolved_conflict_id IS DISTINCT FROM requested_resolved_conflict_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'relationship mutation id was reused with different input';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'status', 'accepted', 'duplicate', true,
      'accepted_revision', replay_row.revision_number,
      'relationship', app_data.promotion_target_relationship_document(
        requested_target_id, trusted_project_id, true
      )
    );
    RETURN;
  END IF;

  SELECT conflict_row.* INTO replay_conflict
  FROM app_data.promotion_target_relationship_conflicts AS conflict_row
  WHERE conflict_row.created_by_app_user_id = trusted_app_user_id
    AND conflict_row.mutation_id = normalized_mutation_id;
  IF FOUND THEN
    IF replay_conflict.promotion_target_id <> requested_target_id
      OR replay_conflict.project_id <> trusted_project_id
      OR replay_conflict.base_revision <> expected_revision
      OR replay_conflict.proposed_stage <> requested_stage
      OR replay_conflict.proposed_lifecycle_status <> requested_lifecycle_status
      OR replay_conflict.proposed_follow_up_note IS DISTINCT FROM normalized_note
      OR replay_conflict.proposed_reason_code <> requested_reason_code
      OR replay_conflict.proposed_reason_detail IS DISTINCT FROM normalized_detail
      OR requested_resolved_conflict_id IS NOT NULL
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'relationship mutation id was reused with different input';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'status', 'conflict', 'conflict_id', replay_conflict.conflict_id,
      'conflicting_fields', replay_conflict.conflicting_fields,
      'current', app_data.promotion_target_relationship_document(
        requested_target_id, trusted_project_id, true
      ),
      'proposed', jsonb_build_object(
        'expected_revision', replay_conflict.base_revision,
        'stage', replay_conflict.proposed_stage,
        'display_stage', replay_conflict.proposed_stage * 2,
        'lifecycle_status', replay_conflict.proposed_lifecycle_status,
        'follow_up_note', replay_conflict.proposed_follow_up_note,
        'reason_code', replay_conflict.proposed_reason_code,
        'reason_detail', replay_conflict.proposed_reason_detail
      )
    );
    RETURN;
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  IF NOT app_data.promotion_target_relationship_authorized(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id,
    requested_target_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'promotion target relationship access is forbidden';
  END IF;

  SELECT relationship_row.* INTO STRICT current_row
  FROM app_data.promotion_target_project_relationships AS relationship_row
  WHERE relationship_row.promotion_target_id = requested_target_id
    AND relationship_row.project_id = trusted_project_id
  FOR UPDATE;

  IF requested_resolved_conflict_id IS NOT NULL THEN
    SELECT conflict_row.* INTO resolved_conflict
    FROM app_data.promotion_target_relationship_conflicts AS conflict_row
    WHERE conflict_row.conflict_id = requested_resolved_conflict_id
      AND conflict_row.promotion_target_id = requested_target_id
      AND conflict_row.project_id = trusted_project_id
      AND NOT EXISTS (
        SELECT 1
        FROM app_data.promotion_target_relationship_conflict_resolutions AS resolution_row
        WHERE resolution_row.conflict_id = conflict_row.conflict_id
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'relationship conflict is missing or already resolved';
    END IF;
  END IF;

  IF expected_revision > current_row.current_revision THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'relationship expected revision is ahead of current';
  END IF;
  IF expected_revision < current_row.current_revision THEN
    SELECT revision_row.* INTO base_row
    FROM app_data.promotion_target_relationship_revisions AS revision_row
    WHERE revision_row.promotion_target_id = requested_target_id
      AND revision_row.project_id = trusted_project_id
      AND revision_row.revision_number = expected_revision;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'relationship base revision is unavailable';
    END IF;

    IF requested_stage < base_row.new_stage
      AND requested_reason_code NOT IN (
        'contact_lost', 'timing_changed', 'requirements_changed',
        'target_request', 'project_change', 'correction', 'other'
      )
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'relationship stage decrease requires a structured reason';
    END IF;
    IF base_row.new_stage <> requested_stage THEN
      proposed_fields := array_append(proposed_fields, 'stage');
    END IF;
    IF base_row.new_lifecycle_status <> requested_lifecycle_status THEN
      proposed_fields := array_append(proposed_fields, 'lifecycle_status');
    END IF;
    IF base_row.follow_up_note IS DISTINCT FROM normalized_note THEN
      proposed_fields := array_append(proposed_fields, 'follow_up_note');
    END IF;
    IF base_row.new_stage <> current_row.current_stage THEN
      server_fields := array_append(server_fields, 'stage');
    END IF;
    IF base_row.new_lifecycle_status <> current_row.current_lifecycle_status THEN
      server_fields := array_append(server_fields, 'lifecycle_status');
    END IF;
    IF base_row.follow_up_note IS DISTINCT FROM current_row.current_follow_up_note THEN
      server_fields := array_append(server_fields, 'follow_up_note');
    END IF;
    SELECT COALESCE(array_agg(field_name), ARRAY[]::text[])
      INTO conflicting_fields_value
    FROM unnest(proposed_fields) AS proposed(field_name)
    WHERE field_name = ANY(server_fields);

    IF cardinality(conflicting_fields_value) > 0 THEN
      INSERT INTO app_data.promotion_target_relationship_conflicts (
        promotion_target_id, project_id, base_revision, current_revision,
        proposed_stage, proposed_lifecycle_status, proposed_follow_up_note,
        proposed_reason_code, proposed_reason_detail, conflicting_fields,
        created_by_app_user_id, mutation_id
      ) VALUES (
        requested_target_id, trusted_project_id, expected_revision,
        current_row.current_revision, requested_stage,
        requested_lifecycle_status, normalized_note, requested_reason_code,
        normalized_detail, conflicting_fields_value, trusted_app_user_id,
        normalized_mutation_id
      ) RETURNING conflict_id INTO conflict_id_value;
      RETURN QUERY SELECT jsonb_build_object(
        'status', 'conflict', 'conflict_id', conflict_id_value,
        'conflicting_fields', conflicting_fields_value,
        'current', app_data.promotion_target_relationship_document(
          requested_target_id, trusted_project_id, true
        ),
        'proposed', jsonb_build_object(
          'expected_revision', expected_revision,
          'stage', requested_stage,
          'display_stage', requested_stage * 2,
          'lifecycle_status', requested_lifecycle_status,
          'follow_up_note', normalized_note,
          'reason_code', requested_reason_code,
          'reason_detail', normalized_detail
        )
      );
      RETURN;
    END IF;

    effective_stage := CASE WHEN 'stage' = ANY(proposed_fields)
      THEN requested_stage ELSE current_row.current_stage END;
    effective_lifecycle_status := CASE
      WHEN 'lifecycle_status' = ANY(proposed_fields)
      THEN requested_lifecycle_status ELSE current_row.current_lifecycle_status
    END;
    effective_note := CASE WHEN 'follow_up_note' = ANY(proposed_fields)
      THEN normalized_note ELSE current_row.current_follow_up_note END;
  ELSE
    effective_stage := requested_stage;
    effective_lifecycle_status := requested_lifecycle_status;
    effective_note := normalized_note;
  END IF;

  IF current_row.current_stage <> effective_stage THEN
    changed_fields_value := array_append(changed_fields_value, 'stage');
  END IF;
  IF current_row.current_lifecycle_status <> effective_lifecycle_status THEN
    changed_fields_value := array_append(changed_fields_value, 'lifecycle_status');
  END IF;
  IF current_row.current_follow_up_note IS DISTINCT FROM effective_note THEN
    changed_fields_value := array_append(changed_fields_value, 'follow_up_note');
  END IF;
  IF requested_resolved_conflict_id IS NOT NULL THEN
    changed_fields_value := array_append(changed_fields_value, 'conflict_resolution');
  ELSIF cardinality(changed_fields_value) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'promotion target relationship update has no changes';
  END IF;
  IF effective_stage < current_row.current_stage
    AND requested_reason_code NOT IN (
      'contact_lost', 'timing_changed', 'requirements_changed',
      'target_request', 'project_change', 'correction', 'other'
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'relationship stage decrease requires a structured reason';
  END IF;

  next_revision := current_row.current_revision + 1;
  UPDATE app_data.promotion_target_project_relationships
  SET current_stage = effective_stage,
      current_lifecycle_status = effective_lifecycle_status,
      current_follow_up_note = effective_note,
      current_revision = next_revision,
      updated_by_app_user_id = trusted_app_user_id,
      updated_at = clock_timestamp()
  WHERE promotion_target_id = requested_target_id
    AND project_id = trusted_project_id;

  INSERT INTO app_data.promotion_target_relationship_revisions (
    promotion_target_id, project_id, revision_number, old_stage, new_stage,
    old_lifecycle_status, new_lifecycle_status, follow_up_note, changed_fields,
    reason_code, reason_detail, changed_by_app_user_id, mutation_id,
    requested_base_revision, requested_stage, requested_lifecycle_status,
    requested_follow_up_note, resolved_conflict_id
  ) VALUES (
    requested_target_id, trusted_project_id, next_revision,
    current_row.current_stage, effective_stage,
    current_row.current_lifecycle_status, effective_lifecycle_status,
    effective_note, changed_fields_value, requested_reason_code,
    normalized_detail, trusted_app_user_id, normalized_mutation_id,
    expected_revision, requested_stage, requested_lifecycle_status,
    normalized_note, requested_resolved_conflict_id
  );

  IF requested_resolved_conflict_id IS NOT NULL THEN
    resolution_choice_value := CASE
      WHEN effective_stage = current_row.current_stage
        AND effective_lifecycle_status = current_row.current_lifecycle_status
        AND effective_note IS NOT DISTINCT FROM current_row.current_follow_up_note
        THEN 'keep_current'
      WHEN effective_stage = resolved_conflict.proposed_stage
        AND effective_lifecycle_status = resolved_conflict.proposed_lifecycle_status
        AND effective_note IS NOT DISTINCT FROM resolved_conflict.proposed_follow_up_note
        THEN 'apply_proposed'
      ELSE 'custom'
    END;
    INSERT INTO app_data.promotion_target_relationship_conflict_resolutions (
      conflict_id, resolved_by_app_user_id, resolved_revision,
      resolution_choice
    ) VALUES (
      requested_resolved_conflict_id, trusted_app_user_id, next_revision,
      resolution_choice_value
    );
  END IF;

  RETURN QUERY SELECT jsonb_build_object(
    'status', 'accepted', 'duplicate', false,
    'accepted_revision', next_revision,
    'relationship', app_data.promotion_target_relationship_document(
      requested_target_id, trusted_project_id, true
    )
  );
END
$function$;

CREATE OR REPLACE FUNCTION app_data.create_target_institution_relationship(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_person_target_id uuid,
  requested_institution_target_id uuid,
  requested_relationship_kind text,
  requested_role_description text,
  requested_mutation_id text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_role text := CASE
    WHEN requested_role_description IS NULL
      OR btrim(requested_role_description) = '' THEN NULL
    ELSE btrim(requested_role_description)
  END;
  normalized_mutation_id text := btrim(requested_mutation_id);
  replay_revision app_data.promotion_target_institution_relation_revisions%ROWTYPE;
  replay_relationship app_data.promotion_target_institution_relationships%ROWTYPE;
  new_relationship_id uuid := gen_random_uuid();
  event_time timestamptz;
BEGIN
  IF requested_person_target_id IS NULL
    OR requested_institution_target_id IS NULL
    OR requested_relationship_kind IS NULL
    OR requested_mutation_id IS NULL
    OR requested_relationship_kind NOT IN (
      'employment_representative',
      'ownership_governance',
      'learning_participation',
      'membership_affiliation',
      'partnership_service',
      'other'
    )
    OR (normalized_role IS NOT NULL AND length(normalized_role) > 500)
    OR (requested_relationship_kind = 'other' AND normalized_role IS NULL)
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid institution relationship';
  END IF;

  IF NOT app_data.promotion_target_pair_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    requested_person_target_id,
    requested_institution_target_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || normalized_mutation_id,
    0
  ));

  SELECT revision_row.* INTO replay_revision
  FROM app_data.promotion_target_institution_relation_revisions
    AS revision_row
  WHERE revision_row.changed_by_app_user_id = trusted_app_user_id
    AND revision_row.mutation_id = normalized_mutation_id;

  IF FOUND THEN
    SELECT relationship_row.* INTO STRICT replay_relationship
    FROM app_data.promotion_target_institution_relationships
      AS relationship_row
    WHERE relationship_row.relationship_id =
      replay_revision.relationship_id;
    IF replay_revision.event_type <> 'created'
      OR replay_relationship.workspace_id <> trusted_workspace_id
      OR replay_relationship.person_target_id <>
        requested_person_target_id
      OR replay_relationship.institution_target_id <>
        requested_institution_target_id
      OR replay_relationship.relationship_kind <>
        requested_relationship_kind
      OR replay_relationship.role_description IS DISTINCT FROM normalized_role
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'institution relationship mutation was reused';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'duplicate', true,
      'relationship',
        app_data.promotion_target_institution_relation_document(
          replay_relationship.relationship_id
        )
    );
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_workspace_id::text || ':'
      || requested_person_target_id::text || ':'
      || requested_institution_target_id::text || ':'
      || requested_relationship_kind,
    0
  ));

  IF EXISTS (
    SELECT 1
    FROM app_data.promotion_target_institution_relationships AS relationship_row
    WHERE relationship_row.workspace_id = trusted_workspace_id
      AND relationship_row.person_target_id = requested_person_target_id
      AND relationship_row.institution_target_id = requested_institution_target_id
      AND relationship_row.relationship_kind = requested_relationship_kind
      AND relationship_row.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'active institution relationship already exists';
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  IF NOT app_data.promotion_target_pair_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    requested_person_target_id,
    requested_institution_target_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  -- The generation fence is the mutation's linearization point. Capture all
  -- created/history timestamps after any activation wait on that fence.
  event_time := clock_timestamp();

  INSERT INTO app_data.promotion_target_institution_relationships (
    relationship_id,
    workspace_id,
    person_target_id,
    institution_target_id,
    relationship_kind,
    role_description,
    started_at,
    created_by_app_user_id,
    created_at,
    updated_by_app_user_id,
    updated_at
  ) VALUES (
    new_relationship_id,
    trusted_workspace_id,
    requested_person_target_id,
    requested_institution_target_id,
    requested_relationship_kind,
    normalized_role,
    event_time,
    trusted_app_user_id,
    event_time,
    trusted_app_user_id,
    event_time
  );

  INSERT INTO app_data.promotion_target_institution_relation_revisions (
    relationship_id,
    revision_number,
    event_type,
    old_status,
    new_status,
    changed_by_app_user_id,
    changed_at,
    mutation_id
  ) VALUES (
    new_relationship_id,
    1,
    'created',
    NULL,
    'active',
    trusted_app_user_id,
    event_time,
    normalized_mutation_id
  );

  RETURN QUERY SELECT jsonb_build_object(
    'duplicate', false,
    'relationship',
      app_data.promotion_target_institution_relation_document(
        new_relationship_id
      )
  );
END
$function$;

CREATE OR REPLACE FUNCTION app_data.end_target_institution_relationship(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_relationship_id uuid,
  requested_expected_revision integer,
  requested_mutation_id text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_mutation_id text := btrim(requested_mutation_id);
  replay_revision app_data.promotion_target_institution_relation_revisions%ROWTYPE;
  replay_relationship app_data.promotion_target_institution_relationships%ROWTYPE;
  current_relationship app_data.promotion_target_institution_relationships%ROWTYPE;
  next_revision integer;
  event_time timestamptz;
BEGIN
  IF requested_relationship_id IS NULL
    OR requested_expected_revision IS NULL
    OR requested_expected_revision < 1
    OR requested_mutation_id IS NULL
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid institution relationship end';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  SELECT relationship_row.* INTO current_relationship
  FROM app_data.promotion_target_institution_relationships AS relationship_row
  WHERE relationship_row.relationship_id = requested_relationship_id
    AND relationship_row.workspace_id = trusted_workspace_id;
  IF NOT FOUND OR NOT app_data.promotion_target_pair_authorized(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id,
    current_relationship.person_target_id,
    current_relationship.institution_target_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || normalized_mutation_id, 0
  ));
  SELECT revision_row.* INTO replay_revision
  FROM app_data.promotion_target_institution_relation_revisions AS revision_row
  WHERE revision_row.changed_by_app_user_id = trusted_app_user_id
    AND revision_row.mutation_id = normalized_mutation_id;
  IF FOUND THEN
    SELECT relationship_row.* INTO STRICT replay_relationship
    FROM app_data.promotion_target_institution_relationships AS relationship_row
    WHERE relationship_row.relationship_id = replay_revision.relationship_id;
    IF replay_revision.event_type <> 'ended'
      OR replay_relationship.relationship_id <> requested_relationship_id
      OR replay_revision.requested_base_revision <> requested_expected_revision
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'institution relationship mutation was reused';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'duplicate', true,
      'relationship', app_data.promotion_target_institution_relation_document(
        requested_relationship_id
      )
    );
    RETURN;
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  SELECT relationship_row.* INTO current_relationship
  FROM app_data.promotion_target_institution_relationships AS relationship_row
  WHERE relationship_row.relationship_id = requested_relationship_id
    AND relationship_row.workspace_id = trusted_workspace_id;
  IF NOT FOUND OR NOT app_data.promotion_target_pair_authorized(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id,
    current_relationship.person_target_id,
    current_relationship.institution_target_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  event_time := clock_timestamp();

  SELECT relationship_row.* INTO STRICT current_relationship
  FROM app_data.promotion_target_institution_relationships AS relationship_row
  WHERE relationship_row.relationship_id = requested_relationship_id
    AND relationship_row.workspace_id = trusted_workspace_id
  FOR UPDATE;
  IF current_relationship.ended_at IS NOT NULL
    OR current_relationship.current_revision <> requested_expected_revision
  THEN
    RAISE EXCEPTION USING ERRCODE = '23505',
      MESSAGE = 'institution relationship revision conflict';
  END IF;

  next_revision := current_relationship.current_revision + 1;
  UPDATE app_data.promotion_target_institution_relationships
  SET ended_at = event_time, current_revision = next_revision,
      updated_by_app_user_id = trusted_app_user_id, updated_at = event_time
  WHERE relationship_id = requested_relationship_id;
  INSERT INTO app_data.promotion_target_institution_relation_revisions (
    relationship_id, revision_number, event_type, old_status, new_status,
    ended_at, changed_by_app_user_id, changed_at, mutation_id,
    requested_base_revision
  ) VALUES (
    requested_relationship_id, next_revision, 'ended', 'active', 'ended',
    event_time, trusted_app_user_id, event_time, normalized_mutation_id,
    requested_expected_revision
  );

  RETURN QUERY SELECT jsonb_build_object(
    'duplicate', false,
    'relationship', app_data.promotion_target_institution_relation_document(
      requested_relationship_id
    )
  );
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.acquire_personal_target_merge_generation_fence_v1(),
  app_private.bind_personal_target_merge_generation_v1(),
  app_private.bind_person_institution_merge_generations_v1(),
  app_private.reject_person_institution_merge_generation_change_v1()
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_private.acquire_personal_target_merge_generation_fence_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.bind_person_institution_merge_generations_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.reject_person_institution_merge_generation_change_v1() OWNER TO %I',
    trusted_owner
  );
END
$owner$;
