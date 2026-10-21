-- Mixed confirmation applies both native histories before one terminal receipt.
CREATE TABLE app_private.personal_merge_mixed_resolution_requests_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  generation_id uuid NOT NULL UNIQUE,
  resolution_fingerprint text NOT NULL CHECK (resolution_fingerprint ~ '^[0-9a-f]{64}$'),
  PRIMARY KEY (actor_app_user_id, request_id),
  CONSTRAINT pmmr_generation_fk FOREIGN KEY (generation_id)
    REFERENCES app_private.personal_target_merge_generations_v1(generation_id) ON DELETE RESTRICT,
  CONSTRAINT pmmr_contact_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_contact_resolution_requests_v1(actor_app_user_id, request_id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT pmmr_project_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_project_relationship_resolution_requests_v1(actor_app_user_id, request_id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE TRIGGER personal_merge_mixed_resolution_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_mixed_resolution_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

REVOKE ALL ON TABLE app_private.personal_merge_mixed_resolution_requests_v1 FROM PUBLIC, tongxingzhe_runtime;

-- Exact application blocks keep ordinary and mixed callers on the same writers.
DO $applications$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  application text;
  replacement text;
  start_anchor text;
  end_anchor text := '  SELECT manifest.fact_fingerprint INTO post_fingerprint';
  start_at integer;
  end_at integer;
BEGIN
  SELECT * INTO STRICT original FROM pg_proc WHERE oid =
    'app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  start_anchor := E'  FOR item IN\n    SELECT pending.*';
  start_at := strpos(original.prosrc, start_anchor);
  end_at := strpos(original.prosrc, end_anchor);
  IF start_at = 0 OR end_at <= start_at
    OR length(original.prosrc) - length(replace(original.prosrc, start_anchor, '')) <> length(start_anchor)
    OR length(original.prosrc) - length(replace(original.prosrc, end_anchor, '')) <> length(end_anchor) THEN
    RAISE EXCEPTION '0142 contact application anchors unavailable';
  END IF;
  application := substring(original.prosrc FROM start_at FOR end_at - start_at);
  EXECUTE $ddl$CREATE FUNCTION app_private.apply_personal_merge_contact_resolutions_v1(
    trusted_app_user_id uuid, requested_request_id uuid, requested_generation_id uuid,
    locked_read_plan jsonb, canonical_assignments jsonb, canonical_choices jsonb
  ) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $body$
  DECLARE
    read_plan jsonb := locked_read_plan;
    source_ids uuid[];
    item record;
    result_row record;
    current_item jsonb;
    command_key text;
    contact_key text;
    base_revision integer;
    original_revision integer;
    original_snapshot jsonb;
    current_links jsonb;
    chosen_links jsonb;
    affected_count bigint;
  BEGIN
    SELECT array_agg(value::uuid) INTO source_ids
    FROM jsonb_array_elements_text(read_plan->'known_source_plan'->'member_target_ids');
  $ddl$ || application || E'END\n$body$;';
  replacement := E'  PERFORM app_private.apply_personal_merge_contact_resolutions_v1(trusted_app_user_id, requested_request_id,\n    requested_generation_id, read_plan, canonical_assignments, canonical_choices);\n';
  definition := pg_get_functiondef(original.oid);
  EXECUTE replace(definition, application, replacement);
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed WHERE changed.oid = original.oid
    AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
    AND replace(changed.prosrc, replacement, application) = original.prosrc) THEN
    RAISE EXCEPTION '0142 contact confirmer metadata or implementation drift';
  END IF;

  SELECT * INTO STRICT original FROM pg_proc WHERE oid =
    'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  start_anchor := '  FOR slot IN SELECT value FROM jsonb_array_elements(read_plan->''source_slots'')';
  start_at := strpos(original.prosrc, start_anchor);
  end_at := strpos(original.prosrc, end_anchor);
  IF start_at = 0 OR end_at <= start_at
    OR length(original.prosrc) - length(replace(original.prosrc, start_anchor, '')) <> length(start_anchor)
    OR length(original.prosrc) - length(replace(original.prosrc, end_anchor, '')) <> length(end_anchor) THEN
    RAISE EXCEPTION '0142 project application anchors unavailable';
  END IF;
  application := substring(original.prosrc FROM start_at FOR end_at - start_at);
  EXECUTE $ddl$CREATE FUNCTION app_private.apply_personal_merge_project_relationship_resolutions_v1(
    trusted_app_user_id uuid, requested_request_id uuid, requested_generation_id uuid,
    locked_read_plan jsonb, canonical_assignments jsonb, canonical_choices jsonb, confirmed_at_utc timestamptz
  ) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog AS $body$
  DECLARE
    read_plan jsonb := locked_read_plan;
    checked_at timestamptz := confirmed_at_utc;
    slot jsonb;
    item record;
    parent_row app_data.promotion_target_project_relationships%ROWTYPE;
    base_row app_data.promotion_target_relationship_revisions%ROWTYPE;
    chosen_row app_data.promotion_target_relationship_revisions%ROWTYPE;
    original_revision integer;
    next_revision integer;
    selected_pending uuid;
    expected_fields text[];
    affected_count bigint;
  BEGIN
  $ddl$ || application || E'END\n$body$;';
  replacement := E'  PERFORM app_private.apply_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id, requested_request_id,\n    requested_generation_id, read_plan, canonical_assignments, canonical_choices, checked_at);\n';
  definition := pg_get_functiondef(original.oid);
  EXECUTE replace(definition, application, replacement);
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed WHERE changed.oid = original.oid
    AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
    AND replace(changed.prosrc, replacement, application) = original.prosrc) THEN
    RAISE EXCEPTION '0142 project confirmer metadata or implementation drift';
  END IF;
END
$applications$;

DO $project_proof$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  contact_rejection text := $anchor$    OR EXISTS (
      SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
      WHERE pending.generation_id = request_row.generation_id
        AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
          WHERE purge.pending_fact_id = pending.pending_fact_id)
    )$anchor$;
BEGIN
  SELECT * INTO STRICT original FROM pg_proc WHERE oid =
    'app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid)'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, contact_rejection, '')) <> length(contact_rejection) THEN
    RAISE EXCEPTION '0142 project proof contact rejection anchor unavailable';
  END IF;
  definition := replace(pg_get_functiondef(original.oid),
    'FUNCTION app_private.personal_merge_project_relationship_resolution_proof_v1(',
    'FUNCTION app_private.personal_merge_project_relationship_resolution_fact_proof_v1(');
  EXECUTE replace(definition, contact_rejection, '');
  EXECUTE $ddl$CREATE OR REPLACE FUNCTION app_private.personal_merge_project_relationship_resolution_proof_v1(
    trusted_app_user_id uuid, requested_request_id uuid
  ) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $body$
  BEGIN
    IF EXISTS (
      SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
      JOIN app_private.personal_merge_unassigned_contact_requests_v1 AS pending
        ON pending.generation_id = request.generation_id
      WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
        AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
          WHERE purge.pending_fact_id = pending.pending_fact_id)
    ) THEN RETURN false; END IF;
    RETURN app_private.personal_merge_project_relationship_resolution_fact_proof_v1(trusted_app_user_id, requested_request_id);
  END
  $body$;$ddl$;
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed WHERE changed.oid = original.oid
    AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc')
    OR NOT EXISTS (SELECT 1 FROM pg_proc core WHERE core.oid =
      'app_private.personal_merge_project_relationship_resolution_fact_proof_v1(uuid,uuid)'::regprocedure
      AND core.prosrc = replace(original.prosrc, contact_rejection, '')) THEN
    RAISE EXCEPTION '0142 project proof metadata or implementation drift';
  END IF;
END
$project_proof$;

CREATE FUNCTION app_private.personal_merge_mixed_resolution_proof_v1(
  trusted_app_user_id uuid, requested_request_id uuid
)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_mixed_resolution_requests_v1 AS mixed
    JOIN app_private.personal_merge_contact_resolution_requests_v1 AS contact USING(actor_app_user_id, request_id)
    JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 AS project USING(actor_app_user_id, request_id)
    WHERE mixed.actor_app_user_id = trusted_app_user_id AND mixed.request_id = requested_request_id
      AND mixed.generation_id = contact.generation_id AND mixed.generation_id = project.generation_id
      AND contact.workspace_id = project.workspace_id AND contact.project_id = project.project_id
      AND contact.known_fact_fingerprint = project.known_fact_fingerprint
      AND contact.post_known_fact_fingerprint = project.post_known_fact_fingerprint
      AND contact.confirmed_at_utc = project.confirmed_at_utc
  ) THEN RETURN false; END IF;
  RETURN app_private.personal_merge_contact_resolution_proof_v1(trusted_app_user_id, requested_request_id)
    AND app_private.personal_merge_project_relationship_resolution_fact_proof_v1(trusted_app_user_id, requested_request_id);
END
$function$;

DO $end_guard$
DECLARE
  original pg_proc%ROWTYPE;
  old_predicate text := '      AND app_private.personal_merge_project_relationship_resolution_proof_v1(request.actor_app_user_id, request.request_id)';
  new_predicate text := $replacement$      AND (app_private.personal_merge_project_relationship_resolution_proof_v1(request.actor_app_user_id, request.request_id)
        OR app_private.personal_merge_mixed_resolution_proof_v1(request.actor_app_user_id, request.request_id))$replacement$;
BEGIN
  SELECT * INTO STRICT original FROM pg_proc WHERE oid =
    'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure;
  IF length(original.prosrc) - length(replace(original.prosrc, old_predicate, '')) <> length(old_predicate) THEN
    RAISE EXCEPTION '0142 project end guard proof anchor unavailable';
  END IF;
  EXECUTE replace(pg_get_functiondef(original.oid), old_predicate, new_predicate);
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed WHERE changed.oid = original.oid
    AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
    AND replace(changed.prosrc, new_predicate, old_predicate) = original.prosrc) THEN
    RAISE EXCEPTION '0142 project end guard metadata or implementation drift';
  END IF;
END
$end_guard$;

CREATE FUNCTION app_private.confirm_personal_merge_mixed_resolutions_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  expected_known_fact_fingerprint text,
  expected_contact_pending_fingerprint text,
  expected_project_pending_fingerprint text,
  expected_resolution_fingerprint text,
  requested_contact_assignments jsonb,
  requested_contact_current_choices jsonb,
  requested_project_assignments jsonb,
  requested_project_current_choices jsonb
)
RETURNS timestamptz
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  item jsonb;
  assignment_array jsonb;
  contact_assignments jsonb;
  contact_choices jsonb;
  project_assignments jsonb;
  project_choices jsonb;
  replay_assignments jsonb;
  replay_choices jsonb;
  mixed_row app_private.personal_merge_mixed_resolution_requests_v1%ROWTYPE;
  contact_request app_private.personal_merge_contact_resolution_requests_v1%ROWTYPE;
  project_request app_private.personal_merge_project_relationship_resolution_requests_v1%ROWTYPE;
  read_plan jsonb;
  contact_plan jsonb;
  project_plan jsonb;
  prelocked_contacts text[];
  child_commands text[];
  prelocked_targets uuid[];
  source_ids uuid[];
  prelocked_relations jsonb;
  contact_inventory jsonb;
  project_inventory jsonb;
  head_inventory jsonb;
  contact_key text;
  command_key text;
  checked_at timestamptz;
  post_fingerprint text;
  ended_at_value timestamptz;
  affected_count bigint;
  contact_count bigint;
  project_count bigint;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'pending mixed resolution confirmation requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_request_id IS NULL OR requested_generation_id IS NULL
    OR expected_known_fact_fingerprint IS NULL OR expected_known_fact_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_contact_pending_fingerprint IS NULL OR expected_contact_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_project_pending_fingerprint IS NULL OR expected_project_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_resolution_fingerprint IS NULL OR expected_resolution_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_contact_assignments IS NULL OR jsonb_typeof(requested_contact_assignments) <> 'array'
    OR requested_contact_current_choices IS NULL OR jsonb_typeof(requested_contact_current_choices) <> 'array'
    OR requested_project_assignments IS NULL OR jsonb_typeof(requested_project_assignments) <> 'array'
    OR requested_project_current_choices IS NULL OR jsonb_typeof(requested_project_current_choices) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed resolution confirmation request';
  END IF;
  IF jsonb_array_length(requested_contact_assignments) = 0 OR jsonb_array_length(requested_project_assignments) = 0
    OR jsonb_array_length(requested_contact_current_choices) = 0 OR jsonb_array_length(requested_project_current_choices) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'pending mixed resolution requires both assignment and choice sets';
  END IF;
  FOREACH assignment_array IN ARRAY ARRAY[requested_contact_assignments, requested_project_assignments] LOOP
    FOR item IN SELECT value FROM jsonb_array_elements(assignment_array) LOOP
      IF jsonb_typeof(item) <> 'object' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed resolution assignment';
      END IF;
      IF (SELECT count(*) FROM jsonb_object_keys(item)) <> 2
        OR NOT item ?& ARRAY['pending_fact_id','source_target_id']
        OR jsonb_typeof(item->'pending_fact_id') <> 'string' OR jsonb_typeof(item->'source_target_id') <> 'string'
        OR item->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        OR item->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed resolution assignment';
      END IF;
    END LOOP;
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(requested_contact_current_choices) LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed contact choice';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(item)) <> 4
      OR NOT item ?& ARRAY['contact_id','source_target_id','candidate_kind','pending_fact_id']
      OR jsonb_typeof(item->'contact_id') <> 'string' OR length(btrim(item->>'contact_id')) = 0
      OR jsonb_typeof(item->'source_target_id') <> 'string'
      OR item->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(item->'candidate_kind') <> 'string' OR item->>'candidate_kind' NOT IN ('current','pending')
      OR (item->>'candidate_kind' = 'current' AND jsonb_typeof(item->'pending_fact_id') <> 'null')
      OR (item->>'candidate_kind' = 'pending' AND (jsonb_typeof(item->'pending_fact_id') <> 'string'
        OR item->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed contact choice';
    END IF;
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(requested_project_current_choices) LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed project choice';
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
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending mixed project choice';
    END IF;
  END LOOP;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', (value->>'pending_fact_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid) ORDER BY (value->>'pending_fact_id')::uuid)
  INTO contact_assignments FROM jsonb_array_elements(requested_contact_assignments);
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', (value->>'pending_fact_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid) ORDER BY (value->>'pending_fact_id')::uuid)
  INTO project_assignments FROM jsonb_array_elements(requested_project_assignments);
  SELECT jsonb_agg(jsonb_build_object('contact_id', value->>'contact_id', 'source_target_id', (value->>'source_target_id')::uuid,
    'candidate_kind', value->>'candidate_kind', 'pending_fact_id', (value->>'pending_fact_id')::uuid)
    ORDER BY value->>'contact_id' COLLATE "C", (value->>'source_target_id')::uuid)
  INTO contact_choices FROM jsonb_array_elements(requested_contact_current_choices);
  SELECT jsonb_agg(jsonb_build_object('project_id', (value->>'project_id')::uuid, 'source_target_id', (value->>'source_target_id')::uuid,
    'candidate_kind', value->>'candidate_kind', 'pending_fact_id', (value->>'pending_fact_id')::uuid)
    ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
  INTO project_choices FROM jsonb_array_elements(requested_project_current_choices);
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(contact_assignments)) <> jsonb_array_length(contact_assignments)
    OR (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(project_assignments)) <> jsonb_array_length(project_assignments)
    OR (SELECT count(*) FROM (SELECT DISTINCT value->>'contact_id', (value->>'source_target_id')::uuid
      FROM jsonb_array_elements(contact_choices)) AS choices) <> jsonb_array_length(contact_choices)
    OR (SELECT count(*) FROM (SELECT DISTINCT (value->>'project_id')::uuid, (value->>'source_target_id')::uuid
      FROM jsonb_array_elements(project_choices)) AS choices) <> jsonb_array_length(project_choices) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending mixed resolution assignment or choice';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));
  PERFORM 1 FROM app_data.app_users AS actor
  WHERE actor.app_user_id = trusted_app_user_id AND actor.status = 'active' FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending mixed resolution actor is unavailable';
  END IF;
  SELECT * INTO mixed_row FROM app_private.personal_merge_mixed_resolution_requests_v1 AS request
  WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF FOUND THEN
    SELECT * INTO contact_request FROM app_private.personal_merge_contact_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
    SELECT * INTO project_request FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
    IF mixed_row.generation_id IS DISTINCT FROM requested_generation_id OR mixed_row.resolution_fingerprint IS DISTINCT FROM expected_resolution_fingerprint
      OR contact_request.workspace_id IS DISTINCT FROM trusted_workspace_id OR project_request.workspace_id IS DISTINCT FROM trusted_workspace_id
      OR contact_request.project_id IS DISTINCT FROM trusted_project_id OR project_request.project_id IS DISTINCT FROM trusted_project_id
      OR contact_request.generation_id IS DISTINCT FROM requested_generation_id OR project_request.generation_id IS DISTINCT FROM requested_generation_id
      OR contact_request.known_fact_fingerprint IS DISTINCT FROM expected_known_fact_fingerprint
      OR project_request.known_fact_fingerprint IS DISTINCT FROM expected_known_fact_fingerprint
      OR contact_request.pending_fingerprint IS DISTINCT FROM expected_contact_pending_fingerprint
      OR project_request.pending_fingerprint IS DISTINCT FROM expected_project_pending_fingerprint
      OR contact_request.post_known_fact_fingerprint IS DISTINCT FROM project_request.post_known_fact_fingerprint
      OR contact_request.confirmed_at_utc IS DISTINCT FROM project_request.confirmed_at_utc THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed resolution request changed';
    END IF;
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id', application.pending_fact_id,
      'source_target_id', application.source_target_id) ORDER BY application.pending_fact_id)
    INTO replay_assignments FROM app_private.personal_merge_contact_history_applications_v1 AS application
    WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
    SELECT jsonb_agg(jsonb_build_object('contact_id', selected.contact_id, 'source_target_id', selected.source_target_id,
      'candidate_kind', CASE WHEN selected.selected_pending_fact_id IS NULL THEN 'current' ELSE 'pending' END,
      'pending_fact_id', selected.selected_pending_fact_id) ORDER BY selected.contact_id COLLATE "C", selected.source_target_id)
    INTO replay_choices FROM app_private.personal_merge_contact_current_choices_v1 AS selected
    WHERE selected.actor_app_user_id = trusted_app_user_id AND selected.request_id = requested_request_id;
    IF replay_assignments IS DISTINCT FROM contact_assignments OR replay_choices IS DISTINCT FROM contact_choices THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed contact assignments or choices changed';
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
    IF replay_assignments IS DISTINCT FROM project_assignments OR replay_choices IS DISTINCT FROM project_choices THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed project assignments or choices changed';
    END IF;
    RETURN app_private.end_known_source_personal_target_merge_generation_v1(trusted_app_user_id, trusted_workspace_id,
      trusted_project_id, requested_request_id, requested_generation_id, contact_request.post_known_fact_fingerprint);
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1 AS request
      WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id)
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
      WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS ended
      WHERE ended.actor_app_user_id = trusted_app_user_id AND ended.request_id = requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'mixed resolution request belongs to another confirmation';
  END IF;

  read_plan := app_private.plan_personal_merge_mixed_resolutions_v1(trusted_app_user_id, trusted_workspace_id,
    trusted_project_id, requested_generation_id, expected_known_fact_fingerprint, expected_contact_pending_fingerprint,
    expected_project_pending_fingerprint, contact_assignments, project_assignments);
  IF read_plan->>'resolution_fingerprint' IS DISTINCT FROM expected_resolution_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed resolution inventory or snapshot changed';
  END IF;
  SELECT jsonb_agg(to_jsonb(pending) ORDER BY pending.pending_fact_id), count(*)
  INTO contact_inventory, contact_count FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
  WHERE pending.generation_id = requested_generation_id;
  SELECT jsonb_agg(to_jsonb(pending) ORDER BY pending.pending_fact_id), count(*)
  INTO project_inventory, project_count FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
  WHERE pending.generation_id = requested_generation_id;
  SELECT array_agg(contact_id ORDER BY contact_id COLLATE "C") INTO prelocked_contacts FROM (
    SELECT DISTINCT pending.contact_id FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    WHERE pending.generation_id = requested_generation_id
  ) AS contacts;
  SELECT jsonb_agg(jsonb_build_array(contact.contact_id, contact.current_revision) ORDER BY contact.contact_id COLLATE "C")
  INTO head_inventory FROM app_data.contacts AS contact WHERE contact.contact_id = ANY(prelocked_contacts);
  SELECT array_agg(command_id ORDER BY command_id COLLATE "C") INTO child_commands FROM (
    SELECT 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':pending:' || pending.pending_fact_id::text AS command_id
    FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending WHERE pending.generation_id = requested_generation_id
    UNION ALL
    SELECT 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':current:'
      || octet_length(contact_id)::text || ':' || contact_id FROM unnest(prelocked_contacts) AS contacts(contact_id)
  ) AS commands;
  -- Include every preserved historical/current non-pair link before the fence.
  WITH snapshots AS (
    SELECT revision.snapshot, pending.project_id FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    JOIN app_data.contact_revisions AS revision ON revision.contact_id = pending.contact_id AND revision.revision_number = pending.revision_number
    WHERE pending.generation_id = requested_generation_id
    UNION ALL
    SELECT revision.snapshot, contact.project_id FROM app_data.contacts AS contact
    JOIN app_data.contact_revisions AS revision ON revision.contact_id = contact.contact_id AND revision.revision_number = contact.current_revision
    WHERE contact.contact_id = ANY(prelocked_contacts)
  ), slots AS (
    SELECT snapshot.project_id, (link.value->>'targetId')::uuid AS source_target_id
    FROM snapshots AS snapshot CROSS JOIN LATERAL jsonb_array_elements(coalesce(snapshot.snapshot->'targetLinks','[]'::jsonb)) AS link
    UNION
    SELECT pending.project_id, (assigned.value->>'source_target_id')::uuid
    FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    JOIN jsonb_array_elements(contact_assignments) AS assigned ON (assigned.value->>'pending_fact_id')::uuid = pending.pending_fact_id
    WHERE pending.generation_id = requested_generation_id
    UNION
    SELECT pending.project_id, (assigned.value->>'source_target_id')::uuid
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
    JOIN jsonb_array_elements(project_assignments) AS assigned ON (assigned.value->>'pending_fact_id')::uuid = pending.pending_fact_id
    WHERE pending.generation_id = requested_generation_id
  )
  SELECT jsonb_agg(jsonb_build_object('project_id', project_id, 'source_target_id', source_target_id)
    ORDER BY project_id, source_target_id) INTO prelocked_relations FROM slots;
  SELECT array_agg(target_id ORDER BY target_id) INTO prelocked_targets FROM (
    SELECT (value->>'source_target_id')::uuid AS target_id FROM jsonb_array_elements(prelocked_relations)
    UNION SELECT member.promotion_target_id FROM app_private.personal_target_merge_generation_members_v1 AS member
      WHERE member.generation_id = requested_generation_id
  ) AS targets;
  FOREACH command_key IN ARRAY child_commands LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || command_key, 0));
  END LOOP;
  FOREACH contact_key IN ARRAY prelocked_contacts LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('contact:' || contact_key, 0));
    PERFORM 1 FROM app_data.contacts AS contact WHERE contact.contact_id = contact_key FOR UPDATE;
  END LOOP;
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  IF (SELECT jsonb_agg(to_jsonb(pending) ORDER BY pending.pending_fact_id)
      FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending WHERE pending.generation_id = requested_generation_id)
      IS DISTINCT FROM contact_inventory
    OR (SELECT jsonb_agg(to_jsonb(pending) ORDER BY pending.pending_fact_id)
      FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending WHERE pending.generation_id = requested_generation_id)
      IS DISTINCT FROM project_inventory
    OR (SELECT jsonb_agg(jsonb_build_array(contact.contact_id, contact.current_revision) ORDER BY contact.contact_id COLLATE "C")
      FROM app_data.contacts AS contact WHERE contact.contact_id = ANY(prelocked_contacts)) IS DISTINCT FROM head_inventory THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed resolution inventory or snapshot changed';
  END IF;
  PERFORM 1 FROM app_data.promotion_targets AS target WHERE target.promotion_target_id = ANY(prelocked_targets)
  ORDER BY target.created_at, target.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> cardinality(prelocked_targets) OR EXISTS (
    SELECT 1 FROM app_data.promotion_targets AS target WHERE target.promotion_target_id = ANY(prelocked_targets)
      AND (target.workspace_id IS DISTINCT FROM trusted_workspace_id OR target.status IS DISTINCT FROM 'active')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending mixed resolution targets are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_assignments AS assigned
  WHERE assigned.promotion_target_id = ANY(prelocked_targets) AND assigned.app_user_id = trusted_app_user_id AND assigned.ended_at IS NULL
  ORDER BY assigned.assignment_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> cardinality(prelocked_targets) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending mixed resolution assignments are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_project_relationships AS relationship
  JOIN jsonb_to_recordset(prelocked_relations) AS slot(project_id uuid, source_target_id uuid)
    ON slot.project_id = relationship.project_id AND slot.source_target_id = relationship.promotion_target_id
  ORDER BY relationship.project_id, relationship.promotion_target_id FOR UPDATE OF relationship;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> jsonb_array_length(prelocked_relations) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'mixed resolution requires existing project relationships';
  END IF;
  read_plan := app_private.plan_personal_merge_mixed_resolutions_v1(trusted_app_user_id, trusted_workspace_id,
    trusted_project_id, requested_generation_id, expected_known_fact_fingerprint, expected_contact_pending_fingerprint,
    expected_project_pending_fingerprint, contact_assignments, project_assignments);
  IF read_plan->>'resolution_fingerprint' IS DISTINCT FROM expected_resolution_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed resolution inventory or snapshot changed';
  END IF;
  contact_plan := read_plan->'contact_resolution_plan';
  project_plan := read_plan->'project_relationship_resolution_plan';
  SELECT array_agg(value::uuid) INTO source_ids FROM jsonb_array_elements_text(contact_plan->'known_source_plan'->'member_target_ids');
  checked_at := clock_timestamp();
  IF EXISTS (SELECT 1 FROM unnest(source_ids) AS member(target_id)
    WHERE app_data.promotion_target_review_due_at(member.target_id) IS NULL
      OR app_data.promotion_target_review_due_at(member.target_id) <= checked_at) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending mixed resolution generation is due';
  END IF;
  IF (SELECT jsonb_agg(jsonb_build_array(value->>'contact_id', (value->>'source_target_id')::uuid)
      ORDER BY value->>'contact_id' COLLATE "C", (value->>'source_target_id')::uuid) FROM jsonb_array_elements(contact_plan->'source_slots'))
      IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_array(value->>'contact_id', (value->>'source_target_id')::uuid)
        ORDER BY value->>'contact_id' COLLATE "C", (value->>'source_target_id')::uuid) FROM jsonb_array_elements(contact_choices))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(contact_choices) AS selected
      JOIN jsonb_array_elements(contact_plan->'source_slots') AS slot ON slot.value->>'contact_id' = selected.value->>'contact_id'
        AND (slot.value->>'source_target_id')::uuid = (selected.value->>'source_target_id')::uuid
      WHERE (selected.value->>'candidate_kind' = 'current' AND NOT (slot.value->>'has_current_link')::boolean)
        OR (selected.value->>'candidate_kind' = 'pending' AND NOT slot.value->'pending_fact_ids' ? (selected.value->>'pending_fact_id')))
    OR (SELECT jsonb_agg(jsonb_build_array((value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
      ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid) FROM jsonb_array_elements(project_plan->'source_slots'))
      IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_array((value->>'project_id')::uuid, (value->>'source_target_id')::uuid)
        ORDER BY (value->>'project_id')::uuid, (value->>'source_target_id')::uuid) FROM jsonb_array_elements(project_choices))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(project_choices) AS selected
      JOIN jsonb_array_elements(project_plan->'source_slots') AS slot
        ON (slot.value->>'project_id')::uuid = (selected.value->>'project_id')::uuid
        AND (slot.value->>'source_target_id')::uuid = (selected.value->>'source_target_id')::uuid
      WHERE selected.value->>'candidate_kind' = 'pending' AND NOT slot.value->'pending_fact_ids' ? (selected.value->>'pending_fact_id'))
    OR EXISTS (SELECT 1 FROM app_data.processed_commands AS command
      WHERE command.app_user_id = trusted_app_user_id AND command.command_id = ANY(child_commands)) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending mixed resolution current choices or child commands conflict';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    JOIN app_data.contacts AS contact ON contact.contact_id = pending.contact_id
    JOIN app_data.contact_revisions AS original ON original.contact_id = pending.contact_id AND original.revision_number = pending.revision_number
    WHERE pending.generation_id = requested_generation_id AND (
      original.snapshot->'questionnaireVersionId' IS DISTINCT FROM to_jsonb(contact.questionnaire_version_id)
      OR EXISTS (SELECT 1 FROM app_data.contact_target_links AS prior WHERE prior.contact_id = pending.contact_id
        AND prior.revision_number = pending.revision_number AND prior.promotion_target_id = ANY(source_ids))))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(contact_plan->'contacts') AS planned
      JOIN app_data.contacts AS contact ON contact.contact_id = planned.value->>'contact_id'
      JOIN app_data.contact_revisions AS original ON original.contact_id = contact.contact_id
        AND original.revision_number = (planned.value->>'current_revision_number')::integer
      WHERE original.snapshot->'questionnaireVersionId' IS DISTINCT FROM to_jsonb(contact.questionnaire_version_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact historical snapshot or questionnaire version is inconsistent';
  END IF;

  PERFORM app_private.apply_personal_merge_contact_resolutions_v1(trusted_app_user_id, requested_request_id,
    requested_generation_id, contact_plan, contact_assignments, contact_choices);
  PERFORM app_private.apply_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id, requested_request_id,
    requested_generation_id, project_plan, project_assignments, project_choices, checked_at);
  SELECT manifest.fact_fingerprint INTO post_fingerprint
  FROM app_private.personal_target_merge_known_source_manifest_v1(requested_generation_id) AS manifest;
  IF NOT FOUND OR post_fingerprint IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed resolution manifest is incomplete';
  END IF;
  INSERT INTO app_private.personal_merge_contact_resolution_requests_v1 (
    actor_app_user_id, request_id, workspace_id, project_id, generation_id, known_fact_fingerprint,
    pending_fingerprint, resolution_fingerprint, post_known_fact_fingerprint, confirmed_at_utc
  ) VALUES (trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_contact_pending_fingerprint, contact_plan->>'resolution_fingerprint', post_fingerprint, checked_at);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
      AND request.workspace_id = trusted_workspace_id AND request.project_id = trusted_project_id AND request.generation_id = requested_generation_id
      AND request.known_fact_fingerprint = expected_known_fact_fingerprint AND request.pending_fingerprint = expected_contact_pending_fingerprint
      AND request.resolution_fingerprint = contact_plan->>'resolution_fingerprint'
      AND request.post_known_fact_fingerprint = post_fingerprint AND request.confirmed_at_utc = checked_at
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed contact request metadata is incomplete';
  END IF;
  INSERT INTO app_private.personal_merge_project_relationship_resolution_requests_v1 (
    actor_app_user_id, request_id, workspace_id, project_id, generation_id, known_fact_fingerprint,
    pending_fingerprint, resolution_fingerprint, post_known_fact_fingerprint, confirmed_at_utc
  ) VALUES (trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_project_pending_fingerprint, project_plan->>'resolution_fingerprint', post_fingerprint, checked_at);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
      AND request.workspace_id = trusted_workspace_id AND request.project_id = trusted_project_id AND request.generation_id = requested_generation_id
      AND request.known_fact_fingerprint = expected_known_fact_fingerprint AND request.pending_fingerprint = expected_project_pending_fingerprint
      AND request.resolution_fingerprint = project_plan->>'resolution_fingerprint'
      AND request.post_known_fact_fingerprint = post_fingerprint AND request.confirmed_at_utc = checked_at
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed project request metadata is incomplete';
  END IF;
  INSERT INTO app_private.personal_merge_mixed_resolution_requests_v1 (
    actor_app_user_id, request_id, generation_id, resolution_fingerprint
  ) VALUES (trusted_app_user_id, requested_request_id, requested_generation_id, expected_resolution_fingerprint);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_mixed_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
      AND request.generation_id = requested_generation_id AND request.resolution_fingerprint = expected_resolution_fingerprint
  ) OR NOT app_private.personal_merge_mixed_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed resolution applications or metadata are incomplete';
  END IF;
  ended_at_value := app_private.end_known_source_personal_target_merge_generation_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_request_id, requested_generation_id, post_fingerprint);
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS ended
    WHERE ended.actor_app_user_id = trusted_app_user_id AND ended.request_id = requested_request_id
      AND ended.workspace_id = trusted_workspace_id AND ended.project_id = trusted_project_id AND ended.generation_id = requested_generation_id
      AND ended.fact_fingerprint = post_fingerprint AND ended.operation = 'personal_target_known_source_merge_end'
      AND ended.reason = 'known_source_split' AND ended.outcome = 'ended' AND ended.ended_at_utc = ended_at_value
      AND ended.ended_at_utc >= checked_at
  ) OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 AS member WHERE member.generation_id = requested_generation_id)
    OR NOT app_private.personal_merge_mixed_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed resolution end receipt is incomplete';
  END IF;
  DELETE FROM app_data.personal_merge_unassigned_contact_facts_v1 AS payload
  USING app_private.personal_merge_contact_history_applications_v1 AS application
  WHERE payload.pending_fact_id = application.pending_fact_id
    AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> contact_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 AS payload
    JOIN app_private.personal_merge_unassigned_contact_requests_v1 AS pending USING(pending_fact_id)
    WHERE pending.generation_id = requested_generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed contact payload consumption is incomplete';
  END IF;
  DELETE FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload
  USING app_private.personal_merge_project_relationship_history_applications_v1 AS application
  WHERE payload.pending_fact_id = application.pending_fact_id
    AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> project_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS payload
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING(pending_fact_id)
    WHERE pending.generation_id = requested_generation_id
  ) OR NOT app_private.personal_merge_mixed_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending mixed resolution final proof or payload consumption is incomplete';
  END IF;
  RETURN ended_at_value;
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb),
  app_private.apply_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz),
  app_private.personal_merge_project_relationship_resolution_fact_proof_v1(uuid,uuid),
  app_private.personal_merge_mixed_resolution_proof_v1(uuid,uuid),
  app_private.confirm_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; function_identity text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
  EXECUTE format('ALTER TABLE app_private.personal_merge_mixed_resolution_requests_v1 OWNER TO %I', trusted_owner);
  FOREACH function_identity IN ARRAY ARRAY[
    'apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)',
    'apply_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)',
    'personal_merge_project_relationship_resolution_fact_proof_v1(uuid,uuid)',
    'personal_merge_mixed_resolution_proof_v1(uuid,uuid)',
    'confirm_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION app_private.%s OWNER TO %I', function_identity, trusted_owner);
  END LOOP;
END
$owner$;
