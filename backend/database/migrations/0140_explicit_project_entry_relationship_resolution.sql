CREATE TABLE app_private.personal_merge_project_entry_resolution_requests_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  generation_id uuid NOT NULL UNIQUE,
  known_fact_fingerprint text NOT NULL CHECK (known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  pending_fingerprint text NOT NULL CHECK (pending_fingerprint ~ '^[0-9a-f]{64}$'),
  resolution_fingerprint text NOT NULL CHECK (resolution_fingerprint ~ '^[0-9a-f]{64}$'),
  internal_known_fact_fingerprint text NOT NULL CHECK (internal_known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  internal_resolution_fingerprint text NOT NULL CHECK (internal_resolution_fingerprint ~ '^[0-9a-f]{64}$'),
  initialized_at_utc timestamptz NOT NULL CHECK (isfinite(initialized_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id),
  CONSTRAINT pmer_request_actor_fk FOREIGN KEY (actor_app_user_id)
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  CONSTRAINT pmer_request_workspace_fk FOREIGN KEY (workspace_id)
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  CONSTRAINT pmer_request_project_fk FOREIGN KEY (project_id)
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  CONSTRAINT pmer_request_generation_fk FOREIGN KEY (generation_id)
    REFERENCES app_private.personal_target_merge_generations_v1 (generation_id) ON DELETE RESTRICT,
  CONSTRAINT pmer_request_inner_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_project_relationship_resolution_requests_v1 (actor_app_user_id, request_id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE app_private.personal_merge_project_entry_origins_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  project_id uuid NOT NULL,
  source_target_id uuid NOT NULL,
  pending_fact_id uuid NOT NULL,
  initial_revision_number integer NOT NULL CHECK (initial_revision_number = 1),
  initialized_at_utc timestamptz NOT NULL CHECK (isfinite(initialized_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id, project_id, source_target_id),
  CONSTRAINT pmer_origin_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_project_entry_resolution_requests_v1 (actor_app_user_id, request_id) ON DELETE RESTRICT,
  CONSTRAINT pmer_origin_pending_fk FOREIGN KEY (pending_fact_id)
    REFERENCES app_private.personal_merge_unassigned_project_relationship_requests_v1 (pending_fact_id) ON DELETE RESTRICT,
  CONSTRAINT pmer_origin_initial_fk FOREIGN KEY (source_target_id, project_id, initial_revision_number)
    REFERENCES app_data.promotion_target_relationship_revisions (promotion_target_id, project_id, revision_number) ON DELETE RESTRICT
);

CREATE TRIGGER pmer_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_project_entry_resolution_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER pmer_origins_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_project_entry_origins_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.personal_merge_project_entry_resolution_proof_v1(
  trusted_app_user_id uuid, requested_request_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  request_row app_private.personal_merge_project_entry_resolution_requests_v1%ROWTYPE;
BEGIN
  SELECT * INTO request_row FROM app_private.personal_merge_project_entry_resolution_requests_v1 AS request
  WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS inner_request
    JOIN app_private.personal_target_merge_end_events_v1 AS ended USING (actor_app_user_id, request_id)
    WHERE inner_request.actor_app_user_id = trusted_app_user_id AND inner_request.request_id = requested_request_id
      AND inner_request.workspace_id = request_row.workspace_id AND inner_request.project_id = request_row.project_id
      AND inner_request.generation_id = request_row.generation_id
      AND inner_request.known_fact_fingerprint = request_row.internal_known_fact_fingerprint
      AND inner_request.pending_fingerprint = request_row.pending_fingerprint
      AND inner_request.resolution_fingerprint = request_row.internal_resolution_fingerprint
      AND inner_request.confirmed_at_utc >= request_row.initialized_at_utc
      AND ended.workspace_id = request_row.workspace_id AND ended.project_id = request_row.project_id
      AND ended.generation_id = request_row.generation_id AND ended.operation = 'personal_target_known_source_merge_end'
      AND ended.reason = 'known_source_split' AND ended.outcome = 'ended'
      AND ended.fact_fingerprint = inner_request.post_known_fact_fingerprint
      AND ended.ended_at_utc >= inner_request.confirmed_at_utc
  ) OR NOT app_private.personal_merge_project_relationship_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.personal_merge_project_entry_origins_v1 AS origin
    LEFT JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
    LEFT JOIN app_private.personal_merge_project_relationship_history_applications_v1 AS application USING (pending_fact_id)
    LEFT JOIN app_private.personal_merge_project_relationship_current_choices_v1 AS selected
      ON selected.actor_app_user_id = origin.actor_app_user_id AND selected.request_id = origin.request_id
      AND selected.project_id = origin.project_id AND selected.source_target_id = origin.source_target_id
    LEFT JOIN app_data.promotion_target_project_relationships AS relationship
      ON relationship.project_id = origin.project_id AND relationship.promotion_target_id = origin.source_target_id
    LEFT JOIN app_data.promotion_target_relationship_revisions AS initial
      ON initial.promotion_target_id = origin.source_target_id AND initial.project_id = origin.project_id
      AND initial.revision_number = origin.initial_revision_number
    WHERE origin.actor_app_user_id = trusted_app_user_id AND origin.request_id = requested_request_id
      AND NOT coalesce(
        origin.initialized_at_utc = request_row.initialized_at_utc
        AND pending.actor_app_user_id = trusted_app_user_id AND pending.workspace_id = request_row.workspace_id
        AND pending.project_id = origin.project_id AND pending.generation_id = request_row.generation_id
        AND pending.staged_at_utc <= origin.initialized_at_utc
        AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
        AND application.project_id = origin.project_id AND application.source_target_id = origin.source_target_id
        AND application.original_revision_number = 1
        AND selected.selected_pending_fact_id = origin.pending_fact_id
        AND selected.original_revision_number = 1 AND selected.original_merge_generation_id = request_row.generation_id
        AND relationship.established_by_app_user_id = trusted_app_user_id
        AND relationship.established_at = origin.initialized_at_utc
        AND relationship.merge_generation_id = request_row.generation_id
        AND initial.revision_number = 1 AND initial.old_stage IS NULL AND initial.new_stage = 0
        AND initial.old_lifecycle_status IS NULL AND initial.new_lifecycle_status = 'active'
        AND initial.follow_up_note IS NULL AND initial.changed_fields = ARRAY['stage','lifecycle_status']::text[]
        AND initial.reason_code = 'project_entry' AND initial.reason_detail IS NULL
        AND initial.changed_by_app_user_id = trusted_app_user_id AND initial.changed_at = origin.initialized_at_utc
        AND initial.merge_generation_id = request_row.generation_id
        AND initial.mutation_id IS NULL AND initial.requested_base_revision IS NULL
        AND initial.requested_stage IS NULL AND initial.requested_lifecycle_status IS NULL
        AND initial.requested_follow_up_note IS NULL AND initial.resolved_conflict_id IS NULL, false)
  ) OR EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_relationship_current_choices_v1 AS selected
    JOIN app_data.promotion_target_project_relationships AS relationship
      ON relationship.project_id = selected.project_id AND relationship.promotion_target_id = selected.source_target_id
    WHERE selected.actor_app_user_id = trusted_app_user_id AND selected.request_id = requested_request_id
      AND selected.original_revision_number = 1
      AND relationship.established_at = request_row.initialized_at_utc
      AND NOT EXISTS (
        SELECT 1 FROM app_private.personal_merge_project_entry_origins_v1 AS origin
        WHERE origin.actor_app_user_id = trusted_app_user_id AND origin.request_id = requested_request_id
          AND origin.project_id = selected.project_id AND origin.source_target_id = selected.source_target_id
      )
  ) THEN RETURN false; END IF;
  RETURN true;
END
$function$;

CREATE FUNCTION app_private.confirm_personal_merge_project_relationship_resolutions_v2(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  expected_known_fact_fingerprint text,
  expected_pending_fingerprint text,
  expected_resolution_fingerprint text,
  requested_assignments jsonb,
  requested_current_choices jsonb,
  project_entry_acknowledgements jsonb
)
RETURNS timestamptz
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  item jsonb;
  canonical_assignments jsonb;
  canonical_choices jsonb;
  canonical_acknowledgements jsonb;
  replay_assignments jsonb;
  replay_choices jsonb;
  replay_acknowledgements jsonb;
  request_row app_private.personal_merge_project_entry_resolution_requests_v1%ROWTYPE;
  read_plan jsonb;
  internal_plan jsonb;
  known_plan jsonb;
  source_ids uuid[];
  affected_count bigint;
  expected_existing bigint;
  checked_at timestamptz;
  ended_at_value timestamptz;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'explicit project entry resolution confirmation requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_request_id IS NULL OR requested_generation_id IS NULL
    OR expected_known_fact_fingerprint IS NULL OR expected_known_fact_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_pending_fingerprint IS NULL OR expected_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_resolution_fingerprint IS NULL OR expected_resolution_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_assignments IS NULL OR jsonb_typeof(requested_assignments) <> 'array'
    OR requested_current_choices IS NULL OR jsonb_typeof(requested_current_choices) <> 'array'
    OR project_entry_acknowledgements IS NULL OR jsonb_typeof(project_entry_acknowledgements) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid explicit project entry resolution confirmation request';
  END IF;
  IF jsonb_array_length(requested_assignments) = 0 OR jsonb_array_length(requested_current_choices) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'explicit project entry resolution requires assignments and current choices';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(requested_assignments) LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship resolution assignment';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(item)) <> 2 OR NOT item ?& ARRAY['pending_fact_id','source_target_id']
      OR jsonb_typeof(item->'pending_fact_id') <> 'string' OR jsonb_typeof(item->'source_target_id') <> 'string'
      OR item->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR item->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship resolution assignment keys or UUIDs';
    END IF;
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(requested_current_choices) LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship current choice';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(item)) <> 4
      OR NOT item ?& ARRAY['project_id','source_target_id','candidate_kind','pending_fact_id']
      OR jsonb_typeof(item->'project_id') <> 'string' OR jsonb_typeof(item->'source_target_id') <> 'string'
      OR item->>'project_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR item->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(item->'candidate_kind') <> 'string' OR item->>'candidate_kind' NOT IN ('current','pending')
      OR (item->>'candidate_kind' = 'current' AND jsonb_typeof(item->'pending_fact_id') <> 'null')
      OR (item->>'candidate_kind' = 'pending' AND (jsonb_typeof(item->'pending_fact_id') <> 'string'
        OR item->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship current choice keys, kind or UUIDs';
    END IF;
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(project_entry_acknowledgements) LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid project entry acknowledgement';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(item)) <> 3
      OR NOT item ?& ARRAY['project_id','source_target_id','pending_fact_id']
      OR jsonb_typeof(item->'project_id') <> 'string' OR jsonb_typeof(item->'source_target_id') <> 'string'
      OR jsonb_typeof(item->'pending_fact_id') <> 'string'
      OR item->>'project_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR item->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR item->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid project entry acknowledgement keys or UUIDs';
    END IF;
  END LOOP;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', (value->>'pending_fact_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid) ORDER BY (value->>'pending_fact_id')::uuid)
  INTO canonical_assignments FROM jsonb_array_elements(requested_assignments);
  SELECT jsonb_agg(jsonb_build_object('project_id', (value->>'project_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid, 'candidate_kind', value->>'candidate_kind',
    'pending_fact_id', (value->>'pending_fact_id')::uuid)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
  INTO canonical_choices FROM jsonb_array_elements(requested_current_choices);
  SELECT coalesce(jsonb_agg(jsonb_build_object('project_id', (value->>'project_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid, 'pending_fact_id', (value->>'pending_fact_id')::uuid)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid), '[]'::jsonb)
  INTO canonical_acknowledgements FROM jsonb_array_elements(project_entry_acknowledgements);
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(canonical_assignments))
      <> jsonb_array_length(canonical_assignments)
    OR (SELECT count(*) FROM (SELECT DISTINCT (value->>'project_id')::uuid, (value->>'source_target_id')::uuid
      FROM jsonb_array_elements(canonical_choices)) AS unique_choices) <> jsonb_array_length(canonical_choices) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending project relationship assignment or current choice';
  END IF;
  IF (SELECT count(*) FROM (SELECT DISTINCT (value->>'project_id')::uuid, (value->>'source_target_id')::uuid
    FROM jsonb_array_elements(canonical_acknowledgements)) AS unique_acknowledgements) <> jsonb_array_length(canonical_acknowledgements)
    OR (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(canonical_acknowledgements))
      <> jsonb_array_length(canonical_acknowledgements) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate project entry acknowledgement';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));
  PERFORM 1 FROM app_data.app_users AS actor
  WHERE actor.app_user_id = trusted_app_user_id AND actor.status = 'active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'explicit project entry resolution actor is unavailable';
  END IF;
  SELECT * INTO request_row FROM app_private.personal_merge_project_entry_resolution_requests_v1 AS request
  WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF FOUND THEN
    IF request_row.workspace_id IS DISTINCT FROM trusted_workspace_id OR request_row.project_id IS DISTINCT FROM trusted_project_id
      OR request_row.generation_id IS DISTINCT FROM requested_generation_id
      OR request_row.known_fact_fingerprint IS DISTINCT FROM expected_known_fact_fingerprint
      OR request_row.pending_fingerprint IS DISTINCT FROM expected_pending_fingerprint
      OR request_row.resolution_fingerprint IS DISTINCT FROM expected_resolution_fingerprint THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'explicit project entry resolution request changed';
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
    SELECT coalesce(jsonb_agg(jsonb_build_object('project_id', origin.project_id, 'source_target_id', origin.source_target_id,
      'pending_fact_id', origin.pending_fact_id) ORDER BY origin.project_id, origin.source_target_id), '[]'::jsonb)
    INTO replay_acknowledgements FROM app_private.personal_merge_project_entry_origins_v1 AS origin
    WHERE origin.actor_app_user_id = trusted_app_user_id AND origin.request_id = requested_request_id;
    IF replay_assignments IS DISTINCT FROM canonical_assignments OR replay_choices IS DISTINCT FROM canonical_choices
      OR replay_acknowledgements IS DISTINCT FROM canonical_acknowledgements THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'explicit project entry resolution assignments, choices or acknowledgements changed';
    END IF;
    RETURN app_private.confirm_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id,
      trusted_workspace_id, trusted_project_id, requested_request_id, requested_generation_id,
      request_row.internal_known_fact_fingerprint, request_row.pending_fingerprint,
      request_row.internal_resolution_fingerprint, canonical_assignments, canonical_choices);
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS ended
      WHERE ended.actor_app_user_id = trusted_app_user_id AND ended.request_id = requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'explicit project entry resolution request belongs to another confirmation';
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
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'explicit project entry resolution targets are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_assignments AS assigned
  WHERE assigned.promotion_target_id = ANY(source_ids) AND assigned.app_user_id = trusted_app_user_id
    AND assigned.ended_at IS NULL ORDER BY assigned.assignment_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'explicit project entry resolution assignments are unavailable';
  END IF;
  SELECT count(*) INTO expected_existing FROM jsonb_array_elements(read_plan->'source_slots') AS planned
  WHERE planned.value->'current_relationship' <> 'null'::jsonb;
  PERFORM 1 FROM app_data.promotion_target_project_relationships AS relationship
  WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(read_plan->'source_slots') AS planned
    WHERE (planned.value->>'project_id')::uuid = relationship.project_id
      AND (planned.value->>'source_target_id')::uuid = relationship.promotion_target_id)
  ORDER BY relationship.project_id, relationship.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_existing THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'explicit project entry resolution snapshot changed';
  END IF;
  read_plan := app_private.plan_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, canonical_assignments);
  checked_at := clock_timestamp();
  IF EXISTS (SELECT 1 FROM unnest(source_ids) AS member(target_id)
    WHERE app_data.promotion_target_review_due_at(member.target_id) IS NULL
      OR app_data.promotion_target_review_due_at(member.target_id) <= checked_at) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'explicit project entry resolution generation is due';
  END IF;
  IF read_plan->>'resolution_fingerprint' IS DISTINCT FROM expected_resolution_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'explicit project entry resolution snapshot changed';
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
      WHERE (selected.value->>'candidate_kind' = 'pending'
        AND NOT planned.value->'pending_fact_ids' ? (selected.value->>'pending_fact_id'))
        OR (planned.value->'current_relationship' = 'null'::jsonb AND selected.value->>'candidate_kind' <> 'pending')
    ) OR canonical_acknowledgements IS DISTINCT FROM (
      SELECT coalesce(jsonb_agg(jsonb_build_object('project_id', (planned.value->>'project_id')::uuid,
        'source_target_id', (planned.value->>'source_target_id')::uuid,
        'pending_fact_id', (selected.value->>'pending_fact_id')::uuid)
        ORDER BY (planned.value->>'project_id')::uuid, (planned.value->>'source_target_id')::uuid), '[]'::jsonb)
      FROM jsonb_array_elements(read_plan->'source_slots') AS planned
      JOIN jsonb_array_elements(canonical_choices) AS selected
        ON (planned.value->>'project_id')::uuid = (selected.value->>'project_id')::uuid
        AND (planned.value->>'source_target_id')::uuid = (selected.value->>'source_target_id')::uuid
      WHERE planned.value->'current_relationship' = 'null'::jsonb
    ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'project entry acknowledgements or current choices conflict';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(canonical_acknowledgements) AS acknowledged
    LEFT JOIN app_data.projects AS project ON project.project_id = (acknowledged.value->>'project_id')::uuid
    LEFT JOIN app_data.workspaces AS workspace ON workspace.workspace_id = project.workspace_id
    WHERE NOT coalesce(project.workspace_id = trusted_workspace_id AND project.status = 'active'
      AND workspace.workspace_kind = 'personal' AND workspace.personal_owner_app_user_id = trusted_app_user_id
      AND workspace.deleted_at IS NULL, false)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'explicit project entry project is unavailable';
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(canonical_acknowledgements)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid
  LOOP
    INSERT INTO app_data.promotion_target_project_relationships (
      promotion_target_id, project_id, current_stage, established_by_app_user_id, established_at,
      current_lifecycle_status, current_follow_up_note, current_revision, updated_by_app_user_id, updated_at
    ) VALUES ((item->>'source_target_id')::uuid, (item->>'project_id')::uuid, 0,
      trusted_app_user_id, checked_at, 'active', NULL, 1, trusted_app_user_id, checked_at);
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'explicit project entry initialization is incomplete';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM app_data.promotion_target_project_relationships AS relationship
      JOIN app_data.promotion_target_relationship_revisions AS initial
        ON initial.promotion_target_id = relationship.promotion_target_id AND initial.project_id = relationship.project_id
        AND initial.revision_number = relationship.current_revision
      WHERE relationship.promotion_target_id = (item->>'source_target_id')::uuid
        AND relationship.project_id = (item->>'project_id')::uuid
        AND relationship.current_stage = 0 AND relationship.current_lifecycle_status = 'active'
        AND relationship.current_follow_up_note IS NULL AND relationship.current_revision = 1
        AND relationship.established_by_app_user_id = trusted_app_user_id AND relationship.established_at = checked_at
        AND relationship.updated_by_app_user_id = trusted_app_user_id AND relationship.updated_at = checked_at
        AND relationship.merge_generation_id = requested_generation_id
        AND initial.old_stage IS NULL AND initial.new_stage = 0 AND initial.old_lifecycle_status IS NULL
        AND initial.new_lifecycle_status = 'active' AND initial.follow_up_note IS NULL
        AND initial.reason_code = 'project_entry' AND initial.reason_detail IS NULL
        AND initial.changed_fields = ARRAY['stage','lifecycle_status']::text[]
        AND initial.changed_by_app_user_id = trusted_app_user_id AND initial.changed_at = checked_at
        AND initial.merge_generation_id = requested_generation_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'explicit project entry initialization is incomplete';
    END IF;
  END LOOP;
  known_plan := app_private.read_known_source_personal_merge_split_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id);
  internal_plan := app_private.plan_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_generation_id,
    known_plan->>'fact_fingerprint', expected_pending_fingerprint, canonical_assignments);
  INSERT INTO app_private.personal_merge_project_entry_resolution_requests_v1 (
    actor_app_user_id, request_id, workspace_id, project_id, generation_id, known_fact_fingerprint,
    pending_fingerprint, resolution_fingerprint, internal_known_fact_fingerprint,
    internal_resolution_fingerprint, initialized_at_utc
  ) VALUES (trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, expected_resolution_fingerprint,
    known_plan->>'fact_fingerprint', internal_plan->>'resolution_fingerprint', checked_at);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_entry_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
      AND request.workspace_id = trusted_workspace_id AND request.project_id = trusted_project_id
      AND request.generation_id = requested_generation_id AND request.known_fact_fingerprint = expected_known_fact_fingerprint
      AND request.pending_fingerprint = expected_pending_fingerprint AND request.resolution_fingerprint = expected_resolution_fingerprint
      AND request.internal_known_fact_fingerprint = known_plan->>'fact_fingerprint'
      AND request.internal_resolution_fingerprint = internal_plan->>'resolution_fingerprint'
      AND request.initialized_at_utc = checked_at
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'explicit project entry resolution request count mismatch';
  END IF;
  INSERT INTO app_private.personal_merge_project_entry_origins_v1 (
    actor_app_user_id, request_id, project_id, source_target_id, pending_fact_id, initial_revision_number, initialized_at_utc
  ) SELECT trusted_app_user_id, requested_request_id, (value->>'project_id')::uuid,
    (value->>'source_target_id')::uuid, (value->>'pending_fact_id')::uuid, 1, checked_at
  FROM jsonb_array_elements(canonical_acknowledgements);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> jsonb_array_length(canonical_acknowledgements) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'explicit project entry origin count mismatch';
  END IF;
  ended_at_value := app_private.confirm_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_request_id, requested_generation_id,
    known_plan->>'fact_fingerprint', expected_pending_fingerprint,
    internal_plan->>'resolution_fingerprint', canonical_assignments, canonical_choices);
  IF NOT app_private.personal_merge_project_entry_resolution_proof_v1(trusted_app_user_id, requested_request_id)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS ended
      WHERE ended.actor_app_user_id = trusted_app_user_id AND ended.request_id = requested_request_id
        AND ended.generation_id = requested_generation_id AND ended.ended_at_utc = ended_at_value) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'explicit project entry resolution proof is incomplete';
  END IF;
  RETURN ended_at_value;
END
$function$;

REVOKE ALL ON TABLE
  app_private.personal_merge_project_entry_resolution_requests_v1,
  app_private.personal_merge_project_entry_origins_v1
  FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION
  app_private.personal_merge_project_entry_resolution_proof_v1(uuid,uuid),
  app_private.confirm_personal_merge_project_relationship_resolutions_v2(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; object_name text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.personal_merge_project_entry_resolution_requests_v1',
    'app_private.personal_merge_project_entry_origins_v1'
  ] LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.personal_merge_project_entry_resolution_proof_v1(uuid,uuid)',
    'app_private.confirm_personal_merge_project_relationship_resolutions_v2(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb,jsonb)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
END
$owner$;
