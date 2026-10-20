CREATE TABLE app_private.personal_merge_project_relationship_resolution_requests_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  generation_id uuid NOT NULL UNIQUE,
  known_fact_fingerprint text NOT NULL CHECK (known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  pending_fingerprint text NOT NULL CHECK (pending_fingerprint ~ '^[0-9a-f]{64}$'),
  resolution_fingerprint text NOT NULL CHECK (resolution_fingerprint ~ '^[0-9a-f]{64}$'),
  post_known_fact_fingerprint text NOT NULL CHECK (post_known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  confirmed_at_utc timestamptz NOT NULL CHECK (isfinite(confirmed_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id),
  CONSTRAINT pmprr_request_actor_fk FOREIGN KEY (actor_app_user_id)
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  CONSTRAINT pmprr_request_workspace_fk FOREIGN KEY (workspace_id)
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  CONSTRAINT pmprr_request_project_fk FOREIGN KEY (project_id)
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  CONSTRAINT pmprr_request_generation_fk FOREIGN KEY (generation_id)
    REFERENCES app_private.personal_target_merge_generations_v1 (generation_id) ON DELETE RESTRICT,
  CONSTRAINT pmprr_request_end_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_target_merge_end_events_v1 (actor_app_user_id, request_id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE app_private.personal_merge_project_relationship_history_applications_v1 (
  pending_fact_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  source_target_id uuid NOT NULL,
  project_id uuid NOT NULL,
  original_revision_number integer NOT NULL CHECK (original_revision_number > 0),
  applied_revision_number integer NOT NULL CHECK (applied_revision_number > original_revision_number),
  CONSTRAINT pmprr_history_pending_fk FOREIGN KEY (pending_fact_id)
    REFERENCES app_private.personal_merge_unassigned_project_relationship_requests_v1 (pending_fact_id) ON DELETE RESTRICT,
  CONSTRAINT pmprr_history_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_project_relationship_resolution_requests_v1 (actor_app_user_id, request_id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT pmprr_history_base_fk FOREIGN KEY (source_target_id, project_id, original_revision_number)
    REFERENCES app_data.promotion_target_relationship_revisions (promotion_target_id, project_id, revision_number) ON DELETE RESTRICT,
  CONSTRAINT pmprr_history_applied_fk FOREIGN KEY (source_target_id, project_id, applied_revision_number)
    REFERENCES app_data.promotion_target_relationship_revisions (promotion_target_id, project_id, revision_number) ON DELETE RESTRICT,
  UNIQUE (source_target_id, project_id, applied_revision_number)
);

CREATE TABLE app_private.personal_merge_project_relationship_current_choices_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  project_id uuid NOT NULL,
  source_target_id uuid NOT NULL,
  original_revision_number integer NOT NULL CHECK (original_revision_number > 0),
  final_revision_number integer NOT NULL CHECK (final_revision_number > original_revision_number),
  original_merge_generation_id uuid,
  selected_pending_fact_id uuid,
  PRIMARY KEY (actor_app_user_id, request_id, project_id, source_target_id),
  CONSTRAINT pmprr_current_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_project_relationship_resolution_requests_v1 (actor_app_user_id, request_id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT pmprr_current_base_fk FOREIGN KEY (source_target_id, project_id, original_revision_number)
    REFERENCES app_data.promotion_target_relationship_revisions (promotion_target_id, project_id, revision_number) ON DELETE RESTRICT,
  CONSTRAINT pmprr_current_final_fk FOREIGN KEY (source_target_id, project_id, final_revision_number)
    REFERENCES app_data.promotion_target_relationship_revisions (promotion_target_id, project_id, revision_number) ON DELETE RESTRICT,
  CONSTRAINT pmprr_current_selected_fk FOREIGN KEY (selected_pending_fact_id)
    REFERENCES app_private.personal_merge_project_relationship_history_applications_v1 (pending_fact_id) ON DELETE RESTRICT,
  CONSTRAINT pmprr_current_binding_fk FOREIGN KEY (original_merge_generation_id, source_target_id)
    REFERENCES app_private.personal_target_merge_generation_members_v1 (generation_id, promotion_target_id) ON DELETE RESTRICT,
  UNIQUE (source_target_id, project_id, final_revision_number)
);

CREATE TRIGGER pmprr_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_project_relationship_resolution_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER pmprr_history_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_project_relationship_history_applications_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER pmprr_current_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_project_relationship_current_choices_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.personal_merge_project_relationship_resolution_proof_v1(
  trusted_app_user_id uuid, requested_request_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  request_row app_private.personal_merge_project_relationship_resolution_requests_v1%ROWTYPE;
  payload_row app_data.personal_merge_unassigned_project_relationship_facts_v1%ROWTYPE;
  base_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  applied_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  final_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  chosen_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  parent_row app_data.promotion_target_project_relationships%ROWTYPE;
  item record;
  slot record;
  source_ids uuid[];
  history_count bigint;
  slot_history_count bigint;
  complete_receipt boolean;
  expected_fields text[];
BEGIN
  SELECT * INTO request_row
  FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
  WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) INTO source_ids
  FROM app_private.personal_target_merge_generation_members_v1 AS member
  JOIN app_private.personal_target_merge_generations_v1 AS generation USING (generation_id)
  WHERE member.generation_id = request_row.generation_id
    AND generation.workspace_id = request_row.workspace_id
    AND generation.created_by_app_user_id = trusted_app_user_id
    AND member.workspace_id = generation.workspace_id AND member.target_type = generation.target_type;
  SELECT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS ended
    WHERE ended.actor_app_user_id = trusted_app_user_id AND ended.request_id = requested_request_id
      AND ended.generation_id = request_row.generation_id AND ended.workspace_id = request_row.workspace_id
      AND ended.project_id = request_row.project_id AND ended.operation = 'personal_target_known_source_merge_end'
      AND ended.reason = 'known_source_split' AND ended.outcome = 'ended'
      AND ended.fact_fingerprint = request_row.post_known_fact_fingerprint
      AND ended.ended_at_utc >= request_row.confirmed_at_utc
  ) INTO complete_receipt;
  SELECT count(*) INTO history_count
  FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
  WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  IF cardinality(source_ids) IS DISTINCT FROM 2 OR history_count = 0
    OR history_count <> (SELECT count(*)
      FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
      WHERE pending.generation_id = request_row.generation_id)
    OR (SELECT manifest.fact_fingerprint
      FROM app_private.personal_target_merge_known_source_manifest_v1(request_row.generation_id) AS manifest)
      IS DISTINCT FROM request_row.post_known_fact_fingerprint
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_current_choices_v1 AS current_choice
      WHERE current_choice.actor_app_user_id = trusted_app_user_id AND current_choice.request_id = requested_request_id)
      <> (SELECT count(*) FROM (
        SELECT DISTINCT application.project_id, application.source_target_id
        FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
        WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
      ) AS slots)
    OR EXISTS (
      SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
      WHERE pending.generation_id = request_row.generation_id
        AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
          WHERE purge.pending_fact_id = pending.pending_fact_id)
    ) THEN RETURN false; END IF;

  FOR item IN
    SELECT application.*, pending.actor_app_user_id AS pending_actor, pending.workspace_id,
      pending.project_id AS pending_project, pending.generation_id, pending.target_type, pending.staged_at_utc,
      row_number() OVER (PARTITION BY application.project_id, application.source_target_id
        ORDER BY pending.staged_at_utc, pending.pending_fact_id) AS ordinal
    FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
    LEFT JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
    WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
  LOOP
    IF item.pending_actor IS DISTINCT FROM trusted_app_user_id
      OR item.workspace_id IS DISTINCT FROM request_row.workspace_id
      OR item.pending_project IS DISTINCT FROM item.project_id
      OR item.generation_id IS DISTINCT FROM request_row.generation_id
      OR NOT coalesce(item.source_target_id = ANY(source_ids), false)
      OR item.applied_revision_number IS DISTINCT FROM item.original_revision_number + item.ordinal
      OR NOT EXISTS (
        SELECT 1 FROM app_data.projects AS project
        JOIN app_data.workspaces AS workspace ON workspace.workspace_id = project.workspace_id
        JOIN app_private.personal_target_merge_generations_v1 AS generation
          ON generation.generation_id = item.generation_id
        WHERE project.project_id = item.project_id AND project.workspace_id = request_row.workspace_id
          AND workspace.workspace_kind = 'personal' AND workspace.personal_owner_app_user_id = trusted_app_user_id
          AND generation.target_type = item.target_type
      )
      OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge
        WHERE purge.pending_fact_id = item.pending_fact_id) THEN RETURN false; END IF;
    SELECT * INTO base_row FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.promotion_target_id = item.source_target_id AND revision.project_id = item.project_id
      AND revision.revision_number = item.original_revision_number;
    IF NOT FOUND THEN RETURN false; END IF;
    SELECT * INTO applied_row FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.promotion_target_id = item.source_target_id AND revision.project_id = item.project_id
      AND revision.revision_number = item.applied_revision_number;
    IF NOT FOUND THEN RETURN false; END IF;
    IF applied_row.old_stage IS DISTINCT FROM base_row.new_stage
      OR applied_row.old_lifecycle_status IS DISTINCT FROM base_row.new_lifecycle_status
      OR applied_row.changed_fields IS DISTINCT FROM ARRAY['pending_source_assignment']::text[]
      OR applied_row.changed_by_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR applied_row.changed_at IS DISTINCT FROM item.staged_at_utc
      OR applied_row.merge_generation_id IS DISTINCT FROM request_row.generation_id
      OR applied_row.mutation_id IS NOT NULL OR applied_row.requested_base_revision IS NOT NULL
      OR applied_row.requested_stage IS NOT NULL OR applied_row.requested_lifecycle_status IS NOT NULL
      OR applied_row.requested_follow_up_note IS NOT NULL OR applied_row.resolved_conflict_id IS NOT NULL
      OR NOT EXISTS (
        SELECT 1 FROM app_private.personal_merge_project_relationship_current_choices_v1 AS selected
        WHERE selected.actor_app_user_id = trusted_app_user_id AND selected.request_id = requested_request_id
          AND selected.project_id = item.project_id AND selected.source_target_id = item.source_target_id
          AND selected.original_revision_number = item.original_revision_number
      ) THEN RETURN false; END IF;
    SELECT * INTO payload_row FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload
    WHERE payload.pending_fact_id = item.pending_fact_id;
    IF FOUND THEN
      IF applied_row.new_stage IS DISTINCT FROM payload_row.new_stage
        OR applied_row.new_lifecycle_status IS DISTINCT FROM payload_row.new_lifecycle_status
        OR applied_row.follow_up_note IS DISTINCT FROM payload_row.follow_up_note
        OR applied_row.reason_code IS DISTINCT FROM payload_row.reason_code
        OR applied_row.reason_detail IS DISTINCT FROM payload_row.reason_detail THEN RETURN false; END IF;
    ELSIF NOT complete_receipt THEN RETURN false;
    END IF;
  END LOOP;

  FOR slot IN
    SELECT * FROM app_private.personal_merge_project_relationship_current_choices_v1 AS selected
    WHERE selected.actor_app_user_id = trusted_app_user_id AND selected.request_id = requested_request_id
  LOOP
    SELECT count(*) INTO slot_history_count
    FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
    WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
      AND application.project_id = slot.project_id AND application.source_target_id = slot.source_target_id;
    IF slot_history_count = 0
      OR slot.final_revision_number IS DISTINCT FROM slot.original_revision_number + slot_history_count + 1 THEN RETURN false; END IF;
    SELECT * INTO base_row FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.promotion_target_id = slot.source_target_id AND revision.project_id = slot.project_id
      AND revision.revision_number = slot.original_revision_number;
    IF NOT FOUND THEN RETURN false; END IF;
    chosen_row := base_row;
    IF slot.selected_pending_fact_id IS NOT NULL THEN
      SELECT revision.* INTO chosen_row
      FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
      JOIN app_data.promotion_target_relationship_revisions AS revision
        ON revision.promotion_target_id = application.source_target_id AND revision.project_id = application.project_id
        AND revision.revision_number = application.applied_revision_number
      WHERE application.pending_fact_id = slot.selected_pending_fact_id
        AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
        AND application.project_id = slot.project_id AND application.source_target_id = slot.source_target_id;
      IF NOT FOUND THEN RETURN false; END IF;
    END IF;
    SELECT * INTO final_row FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.promotion_target_id = slot.source_target_id AND revision.project_id = slot.project_id
      AND revision.revision_number = slot.final_revision_number;
    IF NOT FOUND THEN RETURN false; END IF;
    expected_fields := ARRAY['pending_current_selection']::text[];
    IF base_row.new_stage IS DISTINCT FROM chosen_row.new_stage THEN expected_fields := array_append(expected_fields, 'stage'); END IF;
    IF base_row.new_lifecycle_status IS DISTINCT FROM chosen_row.new_lifecycle_status THEN expected_fields := array_append(expected_fields, 'lifecycle_status'); END IF;
    IF base_row.follow_up_note IS DISTINCT FROM chosen_row.follow_up_note THEN expected_fields := array_append(expected_fields, 'follow_up_note'); END IF;
    IF final_row.old_stage IS DISTINCT FROM base_row.new_stage
      OR final_row.old_lifecycle_status IS DISTINCT FROM base_row.new_lifecycle_status
      OR final_row.new_stage IS DISTINCT FROM chosen_row.new_stage
      OR final_row.new_lifecycle_status IS DISTINCT FROM chosen_row.new_lifecycle_status
      OR final_row.follow_up_note IS DISTINCT FROM chosen_row.follow_up_note
      OR final_row.changed_fields IS DISTINCT FROM expected_fields
      OR final_row.reason_code IS DISTINCT FROM 'correction'
      OR final_row.reason_detail IS DISTINCT FROM 'Confirmed pending project relationship current selection'
      OR final_row.changed_by_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR final_row.changed_at IS DISTINCT FROM request_row.confirmed_at_utc
      OR final_row.merge_generation_id IS DISTINCT FROM request_row.generation_id
      OR final_row.mutation_id IS NOT NULL OR final_row.requested_base_revision IS NOT NULL
      OR final_row.requested_stage IS NOT NULL OR final_row.requested_lifecycle_status IS NOT NULL
      OR final_row.requested_follow_up_note IS NOT NULL OR final_row.resolved_conflict_id IS NOT NULL THEN RETURN false; END IF;
    SELECT * INTO parent_row FROM app_data.promotion_target_project_relationships AS relationship
    WHERE relationship.promotion_target_id = slot.source_target_id AND relationship.project_id = slot.project_id;
    IF NOT FOUND THEN RETURN false; END IF;
    IF parent_row.current_revision IS DISTINCT FROM slot.final_revision_number
      OR parent_row.merge_generation_id IS DISTINCT FROM slot.original_merge_generation_id
      OR parent_row.current_stage IS DISTINCT FROM final_row.new_stage
      OR parent_row.current_lifecycle_status IS DISTINCT FROM final_row.new_lifecycle_status
      OR parent_row.current_follow_up_note IS DISTINCT FROM final_row.follow_up_note
      OR parent_row.updated_by_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR parent_row.updated_at IS DISTINCT FROM request_row.confirmed_at_utc THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END
$function$;

CREATE OR REPLACE FUNCTION app_private.guard_personal_merge_unassigned_project_relationship_end_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NEW.reason = 'known_source_split' AND EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
    WHERE pending.generation_id = NEW.generation_id
      AND NOT EXISTS (
        SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge
        WHERE purge.pending_fact_id = pending.pending_fact_id
      )
  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = NEW.actor_app_user_id AND request.request_id = NEW.request_id
      AND request.workspace_id = NEW.workspace_id AND request.project_id = NEW.project_id
      AND request.generation_id = NEW.generation_id AND request.post_known_fact_fingerprint = NEW.fact_fingerprint
      AND NEW.operation = 'personal_target_known_source_merge_end' AND NEW.outcome = 'ended'
      AND NEW.ended_at_utc >= request.confirmed_at_utc
      AND app_private.personal_merge_project_relationship_resolution_proof_v1(request.actor_app_user_id, request.request_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'unassigned project relationship facts prevent known-source split';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship facts cannot be updated';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
      ON pending.pending_fact_id = purge.pending_fact_id AND pending.generation_id = purge.generation_id
    JOIN app_private.personal_target_merge_end_events_v1 AS receipt ON receipt.generation_id = purge.generation_id
    WHERE purge.pending_fact_id = OLD.pending_fact_id
      AND receipt.actor_app_user_id = pending.actor_app_user_id
      AND receipt.workspace_id = pending.workspace_id
      AND receipt.reason = 'retention_expired'
      AND receipt.operation = 'personal_target_known_source_merge_expire'
      AND receipt.outcome = 'ended'
      AND purge.purged_at_utc = receipt.ended_at_utc
  ) AND NOT EXISTS (
    SELECT 1
    FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
    JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 AS request USING (actor_app_user_id, request_id)
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
    JOIN app_private.personal_target_merge_end_events_v1 AS receipt
      ON receipt.actor_app_user_id = request.actor_app_user_id AND receipt.request_id = request.request_id
      AND receipt.generation_id = request.generation_id AND receipt.workspace_id = request.workspace_id
      AND receipt.project_id = request.project_id AND receipt.fact_fingerprint = request.post_known_fact_fingerprint
    JOIN app_data.promotion_target_relationship_revisions AS applied
      ON applied.promotion_target_id = application.source_target_id AND applied.project_id = application.project_id
      AND applied.revision_number = application.applied_revision_number
    JOIN app_data.promotion_target_relationship_revisions AS base
      ON base.promotion_target_id = application.source_target_id AND base.project_id = application.project_id
      AND base.revision_number = application.original_revision_number
    WHERE application.pending_fact_id = OLD.pending_fact_id
      AND pending.generation_id = request.generation_id AND pending.actor_app_user_id = request.actor_app_user_id
      AND pending.workspace_id = request.workspace_id AND pending.project_id = application.project_id
      AND receipt.reason = 'known_source_split' AND receipt.operation = 'personal_target_known_source_merge_end'
      AND receipt.outcome = 'ended' AND receipt.ended_at_utc >= request.confirmed_at_utc
      AND applied.merge_generation_id = request.generation_id
      AND applied.old_stage = base.new_stage AND applied.old_lifecycle_status = base.new_lifecycle_status
      AND applied.new_stage = OLD.new_stage AND applied.new_lifecycle_status = OLD.new_lifecycle_status
      AND applied.follow_up_note IS NOT DISTINCT FROM OLD.follow_up_note
      AND applied.reason_code = OLD.reason_code AND applied.reason_detail IS NOT DISTINCT FROM OLD.reason_detail
      AND applied.changed_fields = ARRAY['pending_source_assignment']::text[]
      AND applied.changed_by_app_user_id = request.actor_app_user_id AND applied.changed_at = pending.staged_at_utc
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending project relationship deletion requires expiry or applied confirmation receipt';
  END IF;
  RETURN OLD;
END
$function$;

CREATE FUNCTION app_private.confirm_personal_merge_project_relationship_resolutions_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  expected_known_fact_fingerprint text,
  expected_pending_fingerprint text,
  expected_resolution_fingerprint text,
  requested_assignments jsonb,
  requested_current_choices jsonb
)
RETURNS timestamptz
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  assignment jsonb;
  choice jsonb;
  canonical_assignments jsonb;
  canonical_choices jsonb;
  replay_assignments jsonb;
  replay_choices jsonb;
  request_row app_private.personal_merge_project_relationship_resolution_requests_v1%ROWTYPE;
  parent_row app_data.promotion_target_project_relationships%ROWTYPE;
  base_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  chosen_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  read_plan jsonb;
  source_ids uuid[];
  slot jsonb;
  item record;
  original_revision integer;
  next_revision integer;
  expected_fields text[];
  selected_pending uuid;
  affected_count bigint;
  expected_count bigint;
  post_fingerprint text;
  checked_at timestamptz;
  ended_at_value timestamptz;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'pending project relationship resolution confirmation requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_request_id IS NULL OR requested_generation_id IS NULL
    OR expected_known_fact_fingerprint IS NULL OR expected_known_fact_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_pending_fingerprint IS NULL OR expected_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_resolution_fingerprint IS NULL OR expected_resolution_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_assignments IS NULL OR jsonb_typeof(requested_assignments) <> 'array'
    OR requested_current_choices IS NULL OR jsonb_typeof(requested_current_choices) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship resolution confirmation request';
  END IF;
  IF jsonb_array_length(requested_assignments) = 0 OR jsonb_array_length(requested_current_choices) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'pending project relationship resolution requires assignments and current choices';
  END IF;
  FOR assignment IN SELECT value FROM jsonb_array_elements(requested_assignments) LOOP
    IF jsonb_typeof(assignment) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship resolution assignment';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(assignment)) <> 2
      OR NOT assignment ?& ARRAY['pending_fact_id','source_target_id']
      OR jsonb_typeof(assignment->'pending_fact_id') <> 'string'
      OR jsonb_typeof(assignment->'source_target_id') <> 'string'
      OR assignment->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR assignment->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship resolution assignment keys or UUIDs';
    END IF;
  END LOOP;
  FOR choice IN SELECT value FROM jsonb_array_elements(requested_current_choices) LOOP
    IF jsonb_typeof(choice) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship current choice';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(choice)) <> 4
      OR NOT choice ?& ARRAY['project_id','source_target_id','candidate_kind','pending_fact_id']
      OR jsonb_typeof(choice->'project_id') <> 'string'
      OR choice->>'project_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(choice->'source_target_id') <> 'string'
      OR choice->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(choice->'candidate_kind') <> 'string' OR choice->>'candidate_kind' NOT IN ('current','pending')
      OR (choice->>'candidate_kind' = 'current' AND jsonb_typeof(choice->'pending_fact_id') <> 'null')
      OR (choice->>'candidate_kind' = 'pending' AND (jsonb_typeof(choice->'pending_fact_id') <> 'string'
        OR choice->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship current choice keys, kind or UUIDs';
    END IF;
  END LOOP;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', (value->>'pending_fact_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid) ORDER BY (value->>'pending_fact_id')::uuid), count(*)
  INTO canonical_assignments, expected_count FROM jsonb_array_elements(requested_assignments);
  SELECT jsonb_agg(jsonb_build_object('project_id', (value->>'project_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid, 'candidate_kind', value->>'candidate_kind',
    'pending_fact_id', (value->>'pending_fact_id')::uuid)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
  INTO canonical_choices FROM jsonb_array_elements(requested_current_choices);
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(canonical_assignments)) <> expected_count
    OR (SELECT count(*) FROM (SELECT DISTINCT (value->>'project_id')::uuid, (value->>'source_target_id')::uuid
      FROM jsonb_array_elements(canonical_choices)) AS unique_choices) <> jsonb_array_length(canonical_choices) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending project relationship assignment or current choice';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));
  PERFORM 1 FROM app_data.app_users AS actor
  WHERE actor.app_user_id = trusted_app_user_id AND actor.status = 'active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending project relationship resolution actor is unavailable';
  END IF;
  SELECT * INTO request_row FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
  WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF FOUND THEN
    IF request_row.workspace_id IS DISTINCT FROM trusted_workspace_id OR request_row.project_id IS DISTINCT FROM trusted_project_id
      OR request_row.generation_id IS DISTINCT FROM requested_generation_id
      OR request_row.known_fact_fingerprint IS DISTINCT FROM expected_known_fact_fingerprint
      OR request_row.pending_fingerprint IS DISTINCT FROM expected_pending_fingerprint
      OR request_row.resolution_fingerprint IS DISTINCT FROM expected_resolution_fingerprint THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending project relationship resolution request changed';
    END IF;
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id', application.pending_fact_id,
      'source_target_id', application.source_target_id) ORDER BY application.pending_fact_id)
    INTO replay_assignments FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
    WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
    SELECT jsonb_agg(jsonb_build_object('project_id', selected.project_id, 'source_target_id', selected.source_target_id,
      'candidate_kind', CASE WHEN selected.selected_pending_fact_id IS NULL THEN 'current' ELSE 'pending' END,
      'pending_fact_id', selected.selected_pending_fact_id) ORDER BY selected.project_id, selected.source_target_id)
    INTO replay_choices FROM app_private.personal_merge_project_relationship_current_choices_v1 AS selected
    WHERE selected.actor_app_user_id = trusted_app_user_id AND selected.request_id = requested_request_id;
    IF replay_assignments IS DISTINCT FROM canonical_assignments OR replay_choices IS DISTINCT FROM canonical_choices THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending project relationship resolution assignments or current choices changed';
    END IF;
    RETURN app_private.end_known_source_personal_target_merge_generation_v1(trusted_app_user_id, trusted_workspace_id,
      trusted_project_id, requested_request_id, requested_generation_id, request_row.post_known_fact_fingerprint);
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'resolution request belongs to another end operation';
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  read_plan := app_private.plan_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, canonical_assignments);
  SELECT array_agg(value::uuid) INTO source_ids
  FROM jsonb_array_elements_text(read_plan->'known_source_plan'->'member_target_ids');
  PERFORM 1 FROM app_data.promotion_targets AS target
  WHERE target.promotion_target_id = ANY(source_ids) AND target.workspace_id = trusted_workspace_id
    AND target.target_type = read_plan->'known_source_plan'->>'target_type' AND target.status = 'active'
  ORDER BY target.created_at, target.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending project relationship resolution targets are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_assignments AS assigned
  WHERE assigned.promotion_target_id = ANY(source_ids) AND assigned.app_user_id = trusted_app_user_id
    AND assigned.ended_at IS NULL ORDER BY assigned.assignment_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending project relationship resolution assignments are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_project_relationships AS relationship
  WHERE EXISTS (
    SELECT 1 FROM jsonb_array_elements(read_plan->'source_slots') AS planned
    WHERE (planned.value->>'project_id')::uuid = relationship.project_id
      AND (planned.value->>'source_target_id')::uuid = relationship.promotion_target_id
  ) ORDER BY relationship.project_id, relationship.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> jsonb_array_length(read_plan->'source_slots') THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution requires existing current relationships';
  END IF;
  read_plan := app_private.plan_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, canonical_assignments);
  checked_at := clock_timestamp();
  IF EXISTS (SELECT 1 FROM unnest(source_ids) AS member(target_id)
    WHERE app_data.promotion_target_review_due_at(member.target_id) IS NULL
      OR app_data.promotion_target_review_due_at(member.target_id) <= checked_at) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending project relationship resolution generation is due';
  END IF;
  IF read_plan->>'resolution_fingerprint' IS DISTINCT FROM expected_resolution_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending project relationship resolution snapshot changed';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(read_plan->'source_slots') AS planned
    WHERE planned.value->'current_relationship' = 'null'::jsonb) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution requires existing current relationships';
  END IF;
  IF (SELECT jsonb_agg(jsonb_build_array((value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
    FROM jsonb_array_elements(read_plan->'source_slots')) IS DISTINCT FROM
    (SELECT jsonb_agg(jsonb_build_array((value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
    FROM jsonb_array_elements(canonical_choices))
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(canonical_choices) AS selected
      JOIN jsonb_array_elements(read_plan->'source_slots') AS planned
        ON (planned.value->>'project_id')::uuid = (selected.value->>'project_id')::uuid
        AND (planned.value->>'source_target_id')::uuid = (selected.value->>'source_target_id')::uuid
      WHERE selected.value->>'candidate_kind' = 'pending'
        AND NOT planned.value->'pending_fact_ids' ? (selected.value->>'pending_fact_id')
    ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending project relationship current choices conflict';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    WHERE pending.generation_id = requested_generation_id
      AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
        WHERE purge.pending_fact_id = pending.pending_fact_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact facts prevent project relationship resolution';
  END IF;

  FOR slot IN SELECT value FROM jsonb_array_elements(read_plan->'source_slots')
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid
  LOOP
    SELECT * INTO STRICT parent_row FROM app_data.promotion_target_project_relationships AS relationship
    WHERE relationship.project_id = (slot->>'project_id')::uuid
      AND relationship.promotion_target_id = (slot->>'source_target_id')::uuid;
    original_revision := parent_row.current_revision;
    SELECT * INTO STRICT base_row FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.promotion_target_id = parent_row.promotion_target_id AND revision.project_id = parent_row.project_id
      AND revision.revision_number = original_revision;
    IF parent_row.current_stage IS DISTINCT FROM base_row.new_stage
      OR parent_row.current_lifecycle_status IS DISTINCT FROM base_row.new_lifecycle_status
      OR parent_row.current_follow_up_note IS DISTINCT FROM base_row.follow_up_note THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship current revision or context is inconsistent';
    END IF;
    next_revision := original_revision;
    FOR item IN
      SELECT header.staged_at_utc, payload.*
      FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS header
      JOIN jsonb_array_elements(canonical_assignments) AS assigned
        ON (assigned.value->>'pending_fact_id')::uuid = header.pending_fact_id
      JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload USING (pending_fact_id)
      WHERE header.generation_id = requested_generation_id AND header.project_id = parent_row.project_id
        AND (assigned.value->>'source_target_id')::uuid = parent_row.promotion_target_id
      ORDER BY header.staged_at_utc, header.pending_fact_id
    LOOP
      next_revision := next_revision + 1;
      INSERT INTO app_data.promotion_target_relationship_revisions (
        promotion_target_id, project_id, revision_number, old_stage, new_stage,
        old_lifecycle_status, new_lifecycle_status, follow_up_note, changed_fields,
        reason_code, reason_detail, changed_by_app_user_id, changed_at
      ) VALUES (parent_row.promotion_target_id, parent_row.project_id, next_revision,
        base_row.new_stage, item.new_stage, base_row.new_lifecycle_status, item.new_lifecycle_status,
        item.follow_up_note, ARRAY['pending_source_assignment']::text[], item.reason_code,
        item.reason_detail, trusted_app_user_id, item.staged_at_utc);
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      IF affected_count <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship historical application count mismatch';
      END IF;
      INSERT INTO app_private.personal_merge_project_relationship_history_applications_v1 (
        pending_fact_id, actor_app_user_id, request_id, source_target_id, project_id,
        original_revision_number, applied_revision_number
      ) VALUES (item.pending_fact_id, trusted_app_user_id, requested_request_id,
        parent_row.promotion_target_id, parent_row.project_id, original_revision, next_revision);
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      IF affected_count <> 1 THEN
        RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship historical application count mismatch';
      END IF;
    END LOOP;
    SELECT (value->>'pending_fact_id')::uuid INTO selected_pending FROM jsonb_array_elements(canonical_choices)
    WHERE (value->>'project_id')::uuid = parent_row.project_id
      AND (value->>'source_target_id')::uuid = parent_row.promotion_target_id;
    chosen_row := base_row;
    IF selected_pending IS NOT NULL THEN
      SELECT revision.* INTO STRICT chosen_row
      FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
      JOIN app_data.promotion_target_relationship_revisions AS revision
        ON revision.promotion_target_id = application.source_target_id AND revision.project_id = application.project_id
        AND revision.revision_number = application.applied_revision_number
      WHERE application.pending_fact_id = selected_pending;
    END IF;
    next_revision := next_revision + 1;
    expected_fields := ARRAY['pending_current_selection']::text[];
    IF base_row.new_stage IS DISTINCT FROM chosen_row.new_stage THEN expected_fields := array_append(expected_fields, 'stage'); END IF;
    IF base_row.new_lifecycle_status IS DISTINCT FROM chosen_row.new_lifecycle_status THEN expected_fields := array_append(expected_fields, 'lifecycle_status'); END IF;
    IF base_row.follow_up_note IS DISTINCT FROM chosen_row.follow_up_note THEN expected_fields := array_append(expected_fields, 'follow_up_note'); END IF;
    INSERT INTO app_data.promotion_target_relationship_revisions (
      promotion_target_id, project_id, revision_number, old_stage, new_stage, old_lifecycle_status,
      new_lifecycle_status, follow_up_note, changed_fields, reason_code, reason_detail, changed_by_app_user_id, changed_at
    ) VALUES (parent_row.promotion_target_id, parent_row.project_id, next_revision, base_row.new_stage,
      chosen_row.new_stage, base_row.new_lifecycle_status, chosen_row.new_lifecycle_status, chosen_row.follow_up_note,
      expected_fields, 'correction', 'Confirmed pending project relationship current selection', trusted_app_user_id, checked_at);
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship current selection count mismatch';
    END IF;
    UPDATE app_data.promotion_target_project_relationships AS relationship
    SET current_stage = chosen_row.new_stage, current_lifecycle_status = chosen_row.new_lifecycle_status,
      current_follow_up_note = chosen_row.follow_up_note, current_revision = next_revision,
      updated_by_app_user_id = trusted_app_user_id, updated_at = checked_at
    WHERE relationship.promotion_target_id = parent_row.promotion_target_id AND relationship.project_id = parent_row.project_id;
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship current selection count mismatch';
    END IF;
    INSERT INTO app_private.personal_merge_project_relationship_current_choices_v1 (
      actor_app_user_id, request_id, project_id, source_target_id, original_revision_number,
      final_revision_number, original_merge_generation_id, selected_pending_fact_id
    ) VALUES (trusted_app_user_id, requested_request_id, parent_row.project_id, parent_row.promotion_target_id,
      original_revision, next_revision, parent_row.merge_generation_id, selected_pending);
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship current selection count mismatch';
    END IF;
  END LOOP;
  SELECT manifest.fact_fingerprint INTO post_fingerprint
  FROM app_private.personal_target_merge_known_source_manifest_v1(requested_generation_id) AS manifest;
  IF NOT FOUND OR post_fingerprint IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution manifest is incomplete';
  END IF;
  INSERT INTO app_private.personal_merge_project_relationship_resolution_requests_v1 (
    actor_app_user_id, request_id, workspace_id, project_id, generation_id, known_fact_fingerprint,
    pending_fingerprint, resolution_fingerprint, post_known_fact_fingerprint, confirmed_at_utc
  ) VALUES (trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id,
    requested_generation_id, expected_known_fact_fingerprint, expected_pending_fingerprint,
    expected_resolution_fingerprint, post_fingerprint, checked_at);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
      AND request.workspace_id = trusted_workspace_id AND request.project_id = trusted_project_id
      AND request.generation_id = requested_generation_id AND request.known_fact_fingerprint = expected_known_fact_fingerprint
      AND request.pending_fingerprint = expected_pending_fingerprint AND request.resolution_fingerprint = expected_resolution_fingerprint
      AND request.post_known_fact_fingerprint = post_fingerprint AND request.confirmed_at_utc = checked_at
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution request count mismatch';
  END IF;
  IF NOT app_private.personal_merge_project_relationship_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution applications are incomplete';
  END IF;
  ended_at_value := app_private.end_known_source_personal_target_merge_generation_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_request_id, requested_generation_id, post_fingerprint);
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id
      AND receipt.generation_id = requested_generation_id AND receipt.workspace_id = trusted_workspace_id
      AND receipt.project_id = trusted_project_id AND receipt.fact_fingerprint = post_fingerprint
      AND receipt.operation = 'personal_target_known_source_merge_end' AND receipt.reason = 'known_source_split'
      AND receipt.outcome = 'ended' AND receipt.ended_at_utc = ended_at_value
  ) OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 AS member
    WHERE member.generation_id = requested_generation_id)
    OR NOT app_private.personal_merge_project_relationship_resolution_proof_v1(trusted_app_user_id, requested_request_id)
    OR (SELECT count(*) FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload
      JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
      WHERE pending.generation_id = requested_generation_id) <> expected_count THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution end receipt is incomplete';
  END IF;
  DELETE FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload
  USING app_private.personal_merge_project_relationship_history_applications_v1 AS application
  WHERE payload.pending_fact_id = application.pending_fact_id
    AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
    WHERE pending.generation_id = requested_generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution payload consumption is incomplete';
  END IF;
  IF NOT app_private.personal_merge_project_relationship_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship resolution final proof is incomplete';
  END IF;
  RETURN ended_at_value;
END
$function$;

REVOKE ALL ON TABLE
  app_private.personal_merge_project_relationship_resolution_requests_v1,
  app_private.personal_merge_project_relationship_history_applications_v1,
  app_private.personal_merge_project_relationship_current_choices_v1
  FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION
  app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid),
  app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; object_name text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.personal_merge_project_relationship_resolution_requests_v1',
    'app_private.personal_merge_project_relationship_history_applications_v1',
    'app_private.personal_merge_project_relationship_current_choices_v1'
  ] LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid)',
    'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
END
$owner$;
