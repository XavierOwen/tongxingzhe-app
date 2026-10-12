-- End a known-source generation without rewriting its original facts.

CREATE TABLE app_private.personal_target_merge_end_events_v1 (
  generation_id uuid PRIMARY KEY REFERENCES
    app_private.personal_target_merge_generations_v1 (generation_id)
    ON DELETE RESTRICT,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  request_id uuid NOT NULL,
  operation text NOT NULL CHECK (
    operation = 'personal_target_known_source_merge_end'
  ),
  reason text NOT NULL CHECK (reason = 'known_source_split'),
  outcome text NOT NULL CHECK (outcome = 'ended'),
  fact_fingerprint text NOT NULL CHECK (
    fact_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  fact_count bigint NOT NULL CHECK (fact_count >= 0),
  target_count integer NOT NULL CHECK (target_count = 2),
  ended_at_utc timestamptz NOT NULL CHECK (isfinite(ended_at_utc)),
  UNIQUE (actor_app_user_id, request_id)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_merge_end_events_v1
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER personal_target_merge_end_events_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_merge_end_events_v1
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_history_mutation_v1();

CREATE INDEX contact_target_links_merge_generation
  ON app_data.contact_target_links (merge_generation_id)
  WHERE merge_generation_id IS NOT NULL;
CREATE INDEX pt_relationships_merge_generation
  ON app_data.promotion_target_project_relationships (merge_generation_id)
  WHERE merge_generation_id IS NOT NULL;
CREATE INDEX pt_relationship_revisions_merge_generation
  ON app_data.promotion_target_relationship_revisions (merge_generation_id)
  WHERE merge_generation_id IS NOT NULL;
CREATE INDEX pt_institution_relationships_person_generation
  ON app_data.promotion_target_institution_relationships (person_merge_generation_id)
  WHERE person_merge_generation_id IS NOT NULL;
CREATE INDEX pt_institution_relationships_institution_generation
  ON app_data.promotion_target_institution_relationships (institution_merge_generation_id)
  WHERE institution_merge_generation_id IS NOT NULL;
CREATE INDEX pt_institution_revisions_person_generation
  ON app_data.promotion_target_institution_relation_revisions (person_merge_generation_id)
  WHERE person_merge_generation_id IS NOT NULL;
CREATE INDEX pt_institution_revisions_institution_generation
  ON app_data.promotion_target_institution_relation_revisions (institution_merge_generation_id)
  WHERE institution_merge_generation_id IS NOT NULL;

CREATE FUNCTION app_private.personal_target_merge_known_source_manifest_v1(
  requested_generation_id uuid
)
RETURNS TABLE (fact_count bigint, fact_fingerprint text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  WITH facts AS (
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
    WHERE revision.institution_merge_generation_id = requested_generation_id
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

CREATE FUNCTION app_private.end_known_source_personal_target_merge_generation_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  requested_fact_fingerprint text
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
  current_fact_count bigint;
  current_fact_fingerprint text;
  ended_at_value timestamptz;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL OR requested_request_id IS NULL
    OR requested_generation_id IS NULL OR requested_fact_fingerprint IS NULL
    OR requested_fact_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid known-source personal target merge end request';
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
      MESSAGE = 'known-source personal target merge end is forbidden';
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
      MESSAGE = 'known-source personal target merge end is forbidden';
  END IF;

  SELECT event_row.* INTO replay_row
  FROM app_private.personal_target_merge_end_events_v1 AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.request_id = requested_request_id;
  IF FOUND THEN
    IF replay_row.workspace_id <> trusted_workspace_id
      OR replay_row.project_id <> trusted_project_id
      OR replay_row.generation_id <> requested_generation_id
      OR replay_row.fact_fingerprint <> requested_fact_fingerprint
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'known-source personal target merge end request was reused';
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
      MESSAGE = 'known-source personal target merge end is forbidden';
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

  -- PII export uses this order and does not acquire the generation fence.
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
      MESSAGE = 'known-source personal target merge end is forbidden';
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
      MESSAGE = 'known-source personal target merge end is forbidden';
  END IF;

  ended_at_value := clock_timestamp();
  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id
    ) OR NOT EXISTS (
      SELECT 1 FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = trusted_project_id
    ) OR EXISTS (
      SELECT 1 FROM app_data.promotion_targets AS candidate
      WHERE candidate.promotion_target_id = ANY(member_target_ids)
        AND app_data.promotion_target_review_due_at(candidate.promotion_target_id)
          <= ended_at_value
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'known-source personal target merge end is forbidden';
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
  IF current_fact_fingerprint <> requested_fact_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505',
      MESSAGE = 'personal target merge fact manifest changed';
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
    'personal_target_known_source_merge_end', 'known_source_split', 'ended',
    current_fact_fingerprint, current_fact_count, 2, ended_at_value
  );

  RETURN ended_at_value;
END
$function$;

CREATE FUNCTION app_private.reject_ended_personal_target_merge_activation_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
BEGIN
  -- Wait for an in-flight end before deciding whether its generation can activate.
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  IF EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_end_events_v1 AS event_row
    WHERE event_row.generation_id = NEW.generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation has ended';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER personal_target_merge_active_members_reject_ended
BEFORE INSERT OR UPDATE ON app_private.personal_target_merge_active_members_v1
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_ended_personal_target_merge_activation_v1();

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.personal_target_merge_known_source_manifest_v1(uuid),
  app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text),
  app_private.reject_ended_personal_target_merge_activation_v1()
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_merge_end_events_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.personal_target_merge_known_source_manifest_v1(uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.reject_ended_personal_target_merge_activation_v1() OWNER TO %I',
    trusted_owner
  );
END
$owner$;
