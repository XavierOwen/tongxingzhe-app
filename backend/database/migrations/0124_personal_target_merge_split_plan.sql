CREATE FUNCTION app_private.personal_target_merge_known_source_fact_catalog_v1(
  requested_generation_id uuid
)
RETURNS TABLE (source_target_id uuid, metadata jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
    SELECT
      link.promotion_target_id AS source_target_id,
      jsonb_build_array('contact_link', link.contact_id,
        link.revision_number, link.promotion_target_id) AS metadata
    FROM app_data.contact_target_links AS link
    WHERE link.merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.promotion_target_id,
      jsonb_build_array('project_relationship', relation.promotion_target_id,
        relation.project_id, relation.current_revision,
        to_char(relation.updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
    FROM app_data.promotion_target_project_relationships AS relation
    WHERE relation.merge_generation_id = requested_generation_id
    UNION ALL
    SELECT revision.promotion_target_id,
      jsonb_build_array('project_revision', revision.promotion_target_id,
        revision.project_id, revision.revision_number)
    FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.person_target_id,
      jsonb_build_array('institution_relationship_person', relation.relationship_id,
        relation.person_target_id, relation.institution_target_id,
        relation.current_revision,
        to_char(relation.updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        relation.institution_merge_generation_id)
    FROM app_data.promotion_target_institution_relationships AS relation
    WHERE relation.person_merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.institution_target_id,
      jsonb_build_array('institution_relationship_institution', relation.relationship_id,
        relation.person_target_id, relation.institution_target_id,
        relation.current_revision,
        to_char(relation.updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        relation.person_merge_generation_id)
    FROM app_data.promotion_target_institution_relationships AS relation
    WHERE relation.institution_merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.person_target_id,
      jsonb_build_array('institution_revision_person', revision.relationship_id,
        revision.revision_number, relation.person_target_id,
        relation.institution_target_id, revision.institution_merge_generation_id)
    FROM app_data.promotion_target_institution_relation_revisions AS revision
    JOIN app_data.promotion_target_institution_relationships AS relation
      USING (relationship_id)
    WHERE revision.person_merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.institution_target_id,
      jsonb_build_array('institution_revision_institution', revision.relationship_id,
        revision.revision_number, relation.person_target_id,
        relation.institution_target_id, revision.person_merge_generation_id)
    FROM app_data.promotion_target_institution_relation_revisions AS revision
    JOIN app_data.promotion_target_institution_relationships AS relation
      USING (relationship_id)
    WHERE revision.institution_merge_generation_id = requested_generation_id;
$function$;

CREATE OR REPLACE FUNCTION app_private.personal_target_merge_known_source_manifest_v1(
  requested_generation_id uuid
)
RETURNS TABLE (fact_count bigint, fact_fingerprint text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  WITH facts AS (
    SELECT source_target_id, metadata
    FROM app_private.personal_target_merge_known_source_fact_catalog_v1(requested_generation_id)
  )
  SELECT count(*), encode(sha256(convert_to(
    jsonb_build_object(
      'contract', 'personal_target_merge_known_source_manifest_v1',
      'generation_id', requested_generation_id,
      'facts', coalesce(jsonb_agg(metadata ORDER BY metadata::text), '[]'::jsonb)
    )::text, 'UTF8'
  )), 'hex')
  FROM facts
  HAVING coalesce(bool_and(EXISTS (
    SELECT 1
    FROM app_private.personal_target_merge_generation_members_v1 AS member
    WHERE member.generation_id = requested_generation_id
      AND member.promotion_target_id = facts.source_target_id
  )), true);
$function$;

CREATE FUNCTION app_private.read_known_source_personal_merge_split_plan_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  read_gate text;
  split_plan jsonb;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL OR requested_generation_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid known-source personal merge split plan request';
  END IF;

  WITH context AS MATERIALIZED (
    SELECT workspace_row.workspace_id
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
    JOIN app_data.user_current_projects AS current_project
      ON current_project.app_user_id = trusted_app_user_id
      AND current_project.project_id = project_row.project_id
    JOIN app_data.app_users AS actor
      ON actor.app_user_id = trusted_app_user_id AND actor.status = 'active'
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
  ),
  generation AS MATERIALIZED (
    SELECT generation_row.*
    FROM app_private.personal_target_merge_generations_v1 AS generation_row
    JOIN context ON context.workspace_id = generation_row.workspace_id
    WHERE generation_row.generation_id = requested_generation_id
      AND generation_row.created_by_app_user_id = trusted_app_user_id
  ),
  members AS MATERIALIZED (
    SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) AS target_ids,
      count(*) AS member_count,
      bool_and(member.workspace_id = generation.workspace_id
        AND member.target_type = generation.target_type) AS context_matches
    FROM generation
    JOIN app_private.personal_target_merge_generation_members_v1 AS member
      ON member.generation_id = generation.generation_id
  ),
  active_members AS MATERIALIZED (
    SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) AS target_ids,
      count(*) AS member_count,
      bool_and(member.workspace_id = generation.workspace_id
        AND member.target_type = generation.target_type) AS context_matches
    FROM generation
    JOIN app_private.personal_target_merge_active_members_v1 AS member
      ON member.generation_id = generation.generation_id
  ),
  source_targets AS MATERIALIZED (
    SELECT target.promotion_target_id,
      app_data.promotion_target_review_due_at(target.promotion_target_id) AS review_due_at
    FROM generation CROSS JOIN members
    JOIN app_data.promotion_targets AS target
      ON target.promotion_target_id = ANY(members.target_ids)
      AND target.workspace_id = generation.workspace_id
      AND target.target_type = generation.target_type AND target.status = 'active'
    WHERE EXISTS (
      SELECT 1 FROM app_data.promotion_target_assignments AS assignment
      WHERE assignment.promotion_target_id = target.promotion_target_id
        AND assignment.app_user_id = trusted_app_user_id AND assignment.ended_at IS NULL
    )
  ),
  facts AS MATERIALIZED (
    SELECT catalog.source_target_id, catalog.metadata
    FROM generation
    CROSS JOIN LATERAL app_private.personal_target_merge_known_source_fact_catalog_v1(
      generation.generation_id
    ) AS catalog
  ),
  manifest AS MATERIALIZED (
    SELECT manifest_row.fact_count, manifest_row.fact_fingerprint
    FROM generation
    CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(
      generation.generation_id
    ) AS manifest_row
  ),
  gate AS MATERIALIZED (
    SELECT CASE
      WHEN NOT EXISTS (SELECT 1 FROM generation)
        OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS event
          WHERE event.generation_id = requested_generation_id) THEN 'forbidden'
      WHEN members.member_count <> 2 OR NOT coalesce(members.context_matches, false)
        OR active_members.member_count <> 2
        OR NOT coalesce(active_members.context_matches, false)
        OR active_members.target_ids IS DISTINCT FROM members.target_ids THEN 'incomplete'
      WHEN (SELECT count(*) FROM source_targets) <> 2
        OR NOT coalesce((SELECT bool_and(source.review_due_at > statement_timestamp())
          FROM source_targets AS source), false) THEN 'forbidden'
      WHEN (SELECT count(*) FROM manifest) <> 1
        OR EXISTS (SELECT 1 FROM facts
          WHERE NOT (facts.source_target_id = ANY(members.target_ids))) THEN 'incomplete'
      ELSE 'ready'
    END AS status
    FROM members CROSS JOIN active_members
  )
  SELECT gate.status, CASE WHEN gate.status = 'ready' THEN (
    SELECT jsonb_build_object(
      'generation_id', generation.generation_id,
      'workspace_id', trusted_workspace_id,
      'project_id', trusted_project_id,
      'target_type', generation.target_type,
      'member_target_ids', members.target_ids,
      'review_due_at_utc', (SELECT to_char(min(source.review_due_at) AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') FROM source_targets AS source),
      'fact_count', manifest.fact_count,
      'fact_fingerprint', manifest.fact_fingerprint,
      'facts', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'source_target_id', facts.source_target_id, 'metadata', facts.metadata
      ) ORDER BY facts.metadata::text) FROM facts), '[]'::jsonb)
    )
    FROM generation CROSS JOIN members CROSS JOIN manifest
  ) END INTO read_gate, split_plan
  FROM gate;

  IF read_gate = 'forbidden' THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal merge split plan is forbidden';
  END IF;
  IF read_gate <> 'ready' THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal merge mapping or fact source is inconsistent';
  END IF;
  RETURN split_plan;
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.personal_target_merge_known_source_fact_catalog_v1(uuid),
  app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.personal_target_merge_known_source_manifest_v1(uuid)'::regprocedure;
  EXECUTE format(
    'ALTER FUNCTION app_private.personal_target_merge_known_source_fact_catalog_v1(uuid) OWNER TO %I', trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid) OWNER TO %I', trusted_owner
  );
END
$owner$;
