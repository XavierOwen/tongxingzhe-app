-- Inventory every pending candidate and current source link without selecting a winner.
CREATE FUNCTION app_private.plan_unassigned_personal_merge_contact_resolutions_v1(
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
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  assignment jsonb;
  read_plan jsonb;
  source_ids uuid[];
  contact_items jsonb;
  slot_items jsonb;
  conflicts bigint;
  fingerprint_metadata jsonb;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_generation_id IS NULL
    OR expected_known_fact_fingerprint IS NULL OR expected_known_fact_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_pending_fingerprint IS NULL OR expected_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_assignments IS NULL OR jsonb_typeof(requested_assignments) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact resolution plan request';
  END IF;
  FOR assignment IN SELECT value FROM jsonb_array_elements(requested_assignments) LOOP
    IF jsonb_typeof(assignment) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact resolution assignment';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(assignment)) <> 2
      OR NOT assignment ?& ARRAY['pending_fact_id','source_target_id']
      OR jsonb_typeof(assignment->'pending_fact_id') <> 'string'
      OR jsonb_typeof(assignment->'source_target_id') <> 'string'
      OR assignment->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR assignment->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact resolution assignment keys or UUIDs';
    END IF;
  END LOOP;
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid)
      FROM jsonb_array_elements(requested_assignments)) <> jsonb_array_length(requested_assignments) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending contact resolution assignment';
  END IF;

  -- STABLE readers share the calling command's snapshot, including qualification and inventory.
  read_plan := app_private.read_personal_merge_unassigned_contact_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id);
  SELECT array_agg(value::uuid) INTO source_ids
    FROM jsonb_array_elements_text(read_plan->'known_source_plan'->'member_target_ids');
  IF read_plan->'known_source_plan'->>'fact_fingerprint' IS DISTINCT FROM expected_known_fact_fingerprint
    OR read_plan->>'pending_fingerprint' IS DISTINCT FROM expected_pending_fingerprint
    OR (SELECT coalesce(jsonb_agg((value->>'pending_fact_id')::uuid
          ORDER BY (value->>'pending_fact_id')::uuid), '[]'::jsonb)
        FROM jsonb_array_elements(read_plan->'pending_contacts')) IS DISTINCT FROM
      (SELECT coalesce(jsonb_agg((value->>'pending_fact_id')::uuid
          ORDER BY (value->>'pending_fact_id')::uuid), '[]'::jsonb)
        FROM jsonb_array_elements(requested_assignments))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(requested_assignments)
      WHERE NOT ((value->>'source_target_id')::uuid = ANY(source_ids))) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact resolution inventory or source assignment changed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    LEFT JOIN app_data.contacts AS contact ON contact.contact_id = pending.contact_id
    LEFT JOIN app_data.contact_revisions AS revision ON revision.contact_id = contact.contact_id
      AND revision.revision_number = contact.current_revision
    WHERE pending.generation_id = requested_generation_id AND NOT coalesce(
      contact.app_user_id = pending.actor_app_user_id
      AND contact.workspace_id = pending.workspace_id AND contact.project_id = pending.project_id
      AND contact.lifecycle_status = 'active' AND revision.contact_id IS NOT NULL, false)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact current revision or context is inconsistent';
  END IF;

  WITH pending AS MATERIALIZED (
    SELECT header.pending_fact_id, header.contact_id, header.revision_number,
      (choice.value->>'source_target_id')::uuid AS source_target_id
    FROM app_private.personal_merge_unassigned_contact_requests_v1 AS header
    JOIN jsonb_array_elements(requested_assignments) AS choice
      ON (choice.value->>'pending_fact_id')::uuid = header.pending_fact_id
    WHERE header.generation_id = requested_generation_id
  ), contacts AS MATERIALIZED (
    SELECT contact.contact_id, contact.project_id, contact.current_revision
    FROM app_data.contacts AS contact
    WHERE EXISTS (SELECT 1 FROM pending WHERE pending.contact_id = contact.contact_id)
  ), current_links AS MATERIALIZED (
    SELECT link.contact_id, link.promotion_target_id AS source_target_id,
      link.revision_number, link.merge_generation_id
    FROM contacts JOIN app_data.contact_target_links AS link
      ON link.contact_id = contacts.contact_id AND link.revision_number = contacts.current_revision
    WHERE link.promotion_target_id = ANY(source_ids)
  ), slots AS MATERIALIZED (
    SELECT pending.contact_id, pending.source_target_id FROM pending
    UNION
    SELECT current_links.contact_id, current_links.source_target_id FROM current_links
  ), candidates AS MATERIALIZED (
    SELECT slots.contact_id, slots.source_target_id,
      (SELECT coalesce(jsonb_agg(pending.pending_fact_id ORDER BY pending.revision_number, pending.pending_fact_id), '[]'::jsonb)
        FROM pending WHERE pending.contact_id = slots.contact_id
          AND pending.source_target_id = slots.source_target_id) AS pending_fact_ids,
      EXISTS (SELECT 1 FROM current_links WHERE current_links.contact_id = slots.contact_id
        AND current_links.source_target_id = slots.source_target_id) AS has_current_link
    FROM slots
  )
  SELECT
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'contact_id', contacts.contact_id, 'project_id', contacts.project_id,
      'current_revision_number', contacts.current_revision,
      'pending_facts', (SELECT jsonb_agg(jsonb_build_object(
        'pending_fact_id', pending.pending_fact_id, 'revision_number', pending.revision_number,
        'source_target_id', pending.source_target_id,
        'is_current', pending.revision_number = contacts.current_revision
      ) ORDER BY pending.revision_number, pending.pending_fact_id)
        FROM pending WHERE pending.contact_id = contacts.contact_id),
      'current_source_links', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'source_target_id', current_links.source_target_id,
        'revision_number', current_links.revision_number,
        'merge_generation_id', current_links.merge_generation_id
      ) ORDER BY current_links.source_target_id), '[]'::jsonb)
        FROM current_links WHERE current_links.contact_id = contacts.contact_id)
    ) ORDER BY contacts.contact_id COLLATE "C"), '[]'::jsonb) FROM contacts),
    coalesce(jsonb_agg(jsonb_build_object(
      'contact_id', candidates.contact_id, 'source_target_id', candidates.source_target_id,
      'pending_fact_ids', candidates.pending_fact_ids, 'has_current_link', candidates.has_current_link,
      'candidate_count', jsonb_array_length(candidates.pending_fact_ids) + candidates.has_current_link::integer,
      'requires_choice', jsonb_array_length(candidates.pending_fact_ids) + candidates.has_current_link::integer > 1
    ) ORDER BY candidates.contact_id COLLATE "C", candidates.source_target_id), '[]'::jsonb),
    count(*) FILTER (WHERE jsonb_array_length(candidates.pending_fact_ids) + candidates.has_current_link::integer > 1)
  INTO contact_items, slot_items, conflicts FROM candidates;

  -- Candidate counts describe conflicts; even one candidate requires a future explicit write decision.
  fingerprint_metadata := jsonb_build_object(
    'contract_id', 'personal_merge_contact_resolution_plan_v1',
    'known_source_plan', read_plan->'known_source_plan',
    'pending_fingerprint', read_plan->>'pending_fingerprint',
    'contacts', contact_items, 'source_slots', slot_items, 'conflict_count', conflicts);
  RETURN fingerprint_metadata || jsonb_build_object('resolution_fingerprint',
    encode(sha256(convert_to(fingerprint_metadata::text, 'UTF8')), 'hex'));
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.plan_unassigned_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.read_personal_merge_unassigned_contact_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  EXECUTE format('ALTER FUNCTION app_private.plan_unassigned_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb) OWNER TO %I', trusted_owner);
END
$owner$;
