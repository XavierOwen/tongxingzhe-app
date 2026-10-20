CREATE FUNCTION app_private.plan_personal_merge_project_relationship_resolutions_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_generation_id uuid,
  expected_known_fact_fingerprint text,
  expected_pending_fingerprint text,
  requested_assignments jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  assignment jsonb;
  read_plan jsonb;
  source_ids uuid[];
  assignment_items jsonb;
  slot_items jsonb;
  conflicts bigint;
  fingerprint_metadata jsonb;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_generation_id IS NULL
    OR expected_known_fact_fingerprint IS NULL OR expected_known_fact_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_pending_fingerprint IS NULL OR expected_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_assignments IS NULL OR jsonb_typeof(requested_assignments) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending project relationship resolution plan request';
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
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid)
      FROM jsonb_array_elements(requested_assignments)) <> jsonb_array_length(requested_assignments) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending project relationship resolution assignment';
  END IF;

  -- STABLE readers keep qualification and inventory in the calling command's snapshot.
  read_plan := app_private.read_personal_merge_unassigned_project_relationship_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id);
  SELECT array_agg(value::uuid) INTO source_ids
    FROM jsonb_array_elements_text(read_plan->'known_source_plan'->'member_target_ids');
  IF read_plan->'known_source_plan'->>'fact_fingerprint' IS DISTINCT FROM expected_known_fact_fingerprint
    OR read_plan->>'pending_fingerprint' IS DISTINCT FROM expected_pending_fingerprint
    OR (SELECT coalesce(jsonb_agg((value->>'pending_fact_id')::uuid
          ORDER BY (value->>'pending_fact_id')::uuid), '[]'::jsonb)
        FROM jsonb_array_elements(read_plan->'pending_project_relationships')) IS DISTINCT FROM
      (SELECT coalesce(jsonb_agg((value->>'pending_fact_id')::uuid
          ORDER BY (value->>'pending_fact_id')::uuid), '[]'::jsonb)
        FROM jsonb_array_elements(requested_assignments))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(requested_assignments)
      WHERE NOT ((value->>'source_target_id')::uuid = ANY(source_ids))) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending project relationship resolution inventory or source assignment changed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
    JOIN jsonb_array_elements(requested_assignments) AS choice
      ON (choice.value->>'pending_fact_id')::uuid = pending.pending_fact_id
    JOIN app_data.promotion_target_project_relationships AS relationship
      ON relationship.project_id = pending.project_id
      AND relationship.promotion_target_id = (choice.value->>'source_target_id')::uuid
    LEFT JOIN app_data.promotion_target_relationship_revisions AS revision
      ON revision.promotion_target_id = relationship.promotion_target_id
      AND revision.project_id = relationship.project_id
      AND revision.revision_number = relationship.current_revision
    WHERE pending.generation_id = requested_generation_id
      AND (revision.revision_number IS NULL
        OR EXISTS (
          SELECT 1
          FROM (VALUES (relationship.merge_generation_id), (revision.merge_generation_id)) AS binding(generation_id)
          WHERE binding.generation_id IS NOT NULL AND NOT EXISTS (
            SELECT 1
            FROM app_private.personal_target_merge_generations_v1 AS generation
            JOIN app_private.personal_target_merge_generation_members_v1 AS member
              ON member.generation_id = generation.generation_id
              AND member.workspace_id = generation.workspace_id
              AND member.target_type = generation.target_type
            WHERE generation.generation_id = binding.generation_id
              AND generation.workspace_id = trusted_workspace_id
              AND generation.target_type = read_plan->'known_source_plan'->>'target_type'
              AND member.promotion_target_id = relationship.promotion_target_id
          )
        ))
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship current revision or context is inconsistent';
  END IF;

  WITH pending AS MATERIALIZED (
    SELECT header.pending_fact_id, header.project_id, header.staged_at_utc,
      (choice.value->>'source_target_id')::uuid AS source_target_id
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS header
    JOIN jsonb_array_elements(requested_assignments) AS choice
      ON (choice.value->>'pending_fact_id')::uuid = header.pending_fact_id
    WHERE header.generation_id = requested_generation_id
  ), slots AS MATERIALIZED (
    SELECT DISTINCT pending.project_id, pending.source_target_id FROM pending
  ), candidates AS MATERIALIZED (
    SELECT slots.project_id, slots.source_target_id,
      (SELECT jsonb_agg(pending.pending_fact_id ORDER BY pending.staged_at_utc, pending.pending_fact_id)
        FROM pending WHERE pending.project_id = slots.project_id
          AND pending.source_target_id = slots.source_target_id) AS pending_fact_ids,
      CASE WHEN relationship.promotion_target_id IS NOT NULL THEN jsonb_build_object(
        'revision_number', revision.revision_number,
        'merge_generation_id', revision.merge_generation_id
      ) END AS current_relationship,
      relationship.promotion_target_id IS NOT NULL AS has_current_relationship
    FROM slots
    LEFT JOIN app_data.promotion_target_project_relationships AS relationship
      ON relationship.project_id = slots.project_id
      AND relationship.promotion_target_id = slots.source_target_id
    LEFT JOIN app_data.promotion_target_relationship_revisions AS revision
      ON revision.promotion_target_id = relationship.promotion_target_id
      AND revision.project_id = relationship.project_id
      AND revision.revision_number = relationship.current_revision
  )
  SELECT
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'pending_fact_id', pending.pending_fact_id,
      'source_target_id', pending.source_target_id,
      'project_id', pending.project_id
    ) ORDER BY pending.pending_fact_id), '[]'::jsonb) FROM pending),
    coalesce(jsonb_agg(jsonb_build_object(
      'project_id', candidates.project_id, 'source_target_id', candidates.source_target_id,
      'pending_fact_ids', candidates.pending_fact_ids,
      'current_relationship', candidates.current_relationship,
      'candidate_count', jsonb_array_length(candidates.pending_fact_ids) + candidates.has_current_relationship::integer,
      'requires_choice', jsonb_array_length(candidates.pending_fact_ids) + candidates.has_current_relationship::integer > 1
    ) ORDER BY candidates.project_id, candidates.source_target_id), '[]'::jsonb),
    count(*) FILTER (WHERE jsonb_array_length(candidates.pending_fact_ids) + candidates.has_current_relationship::integer > 1)
  INTO assignment_items, slot_items, conflicts FROM candidates;

  -- Candidate counts describe conflicts; every future write still needs an explicit decision.
  fingerprint_metadata := jsonb_build_object(
    'contract_id', 'personal_merge_project_relationship_resolution_plan_v1',
    'known_source_plan', read_plan->'known_source_plan',
    'pending_fingerprint', read_plan->>'pending_fingerprint',
    'assignments', assignment_items, 'source_slots', slot_items, 'conflict_count', conflicts);
  RETURN fingerprint_metadata || jsonb_build_object('resolution_fingerprint',
    encode(sha256(convert_to(fingerprint_metadata::text, 'UTF8')), 'hex'));
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb) OWNER TO %I', trusted_owner);
END
$owner$;
