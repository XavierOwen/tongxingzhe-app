-- Each request records a new event without choosing an ordinary relationship.
CREATE TABLE app_private.personal_merge_unassigned_project_relationship_requests_v1 (
  pending_fact_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  generation_id uuid NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('person', 'institution')),
  request_id uuid NOT NULL,
  staged_at_utc timestamptz NOT NULL CHECK (isfinite(staged_at_utc)),
  CONSTRAINT pmupr_request_actor_fk FOREIGN KEY (actor_app_user_id)
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  CONSTRAINT pmupr_request_workspace_fk FOREIGN KEY (workspace_id)
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  CONSTRAINT pmupr_request_project_fk FOREIGN KEY (project_id)
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  CONSTRAINT pmupr_request_generation_fk FOREIGN KEY (generation_id)
    REFERENCES app_private.personal_target_merge_generations_v1 (generation_id) ON DELETE RESTRICT,
  UNIQUE (actor_app_user_id, request_id),
  UNIQUE (pending_fact_id, generation_id)
);

CREATE TABLE app_data.personal_merge_unassigned_project_relationship_facts_v1 (
  pending_fact_id uuid PRIMARY KEY,
  new_stage integer NOT NULL CHECK (new_stage BETWEEN 0 AND 4),
  new_lifecycle_status text NOT NULL CHECK (new_lifecycle_status IN ('active', 'paused', 'ended')),
  follow_up_note text CHECK (follow_up_note IS NULL OR (length(follow_up_note) <= 4000 AND follow_up_note ~ '[^[:space:]]')),
  reason_code text NOT NULL CHECK (reason_code IN (
    'project_entry', 'progress_update', 'contact_lost', 'timing_changed',
    'requirements_changed', 'target_request', 'project_change', 'correction', 'other'
  )),
  reason_detail text CHECK (reason_detail IS NULL OR (length(reason_detail) <= 1000 AND reason_detail ~ '[^[:space:]]')),
  CHECK (reason_code <> 'other' OR reason_detail IS NOT NULL),
  CONSTRAINT pmupr_payload_request_fk FOREIGN KEY (pending_fact_id)
    REFERENCES app_private.personal_merge_unassigned_project_relationship_requests_v1 (pending_fact_id) ON DELETE RESTRICT
);

CREATE TABLE app_private.personal_merge_unassigned_project_relationship_purges_v1 (
  pending_fact_id uuid PRIMARY KEY,
  generation_id uuid NOT NULL,
  purged_at_utc timestamptz NOT NULL CHECK (isfinite(purged_at_utc)),
  CONSTRAINT pmupr_purge_generation_fk FOREIGN KEY (generation_id)
    REFERENCES app_private.personal_target_merge_end_events_v1 (generation_id) ON DELETE RESTRICT,
  CONSTRAINT pmupr_purge_request_fk FOREIGN KEY (pending_fact_id, generation_id)
    REFERENCES app_private.personal_merge_unassigned_project_relationship_requests_v1 (pending_fact_id, generation_id) ON DELETE RESTRICT
);

CREATE TRIGGER pmupr_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_unassigned_project_relationship_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE TRIGGER pmupr_purges_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_unassigned_project_relationship_purges_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()
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
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending project relationship deletion requires expiry receipt';
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER pmupr_payload_guard
BEFORE UPDATE OR DELETE ON app_data.personal_merge_unassigned_project_relationship_facts_v1
FOR EACH ROW EXECUTE FUNCTION app_private.guard_personal_merge_unassigned_project_relationship_payload_v1();

CREATE FUNCTION app_private.guard_personal_merge_unassigned_project_relationship_end_v1()
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
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'unassigned project relationship facts prevent known-source split';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER pmupr_end_guard
BEFORE INSERT ON app_private.personal_target_merge_end_events_v1
FOR EACH ROW EXECUTE FUNCTION app_private.guard_personal_merge_unassigned_project_relationship_end_v1();

CREATE FUNCTION app_private.purge_personal_merge_unassigned_project_relationships_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  expected_count bigint;
  affected_count bigint;
BEGIN
  SELECT count(*) INTO expected_count
  FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
  WHERE pending.generation_id = NEW.generation_id;
  IF NEW.operation IS DISTINCT FROM 'personal_target_known_source_merge_expire'
    OR NEW.outcome IS DISTINCT FROM 'ended'
    OR EXISTS (
      SELECT 1
      FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
      LEFT JOIN app_private.personal_target_merge_generations_v1 AS generation USING (generation_id)
      LEFT JOIN app_data.projects AS project ON project.project_id = pending.project_id
      LEFT JOIN app_data.workspaces AS workspace ON workspace.workspace_id = pending.workspace_id
      LEFT JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 AS fact USING (pending_fact_id)
      LEFT JOIN app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge USING (pending_fact_id)
      WHERE pending.generation_id = NEW.generation_id
        AND (fact.pending_fact_id IS NULL OR purge.pending_fact_id IS NOT NULL
          OR pending.actor_app_user_id IS DISTINCT FROM NEW.actor_app_user_id
          OR pending.workspace_id IS DISTINCT FROM NEW.workspace_id
          OR generation.workspace_id IS DISTINCT FROM pending.workspace_id
          OR generation.created_by_app_user_id IS DISTINCT FROM pending.actor_app_user_id
          OR generation.target_type IS DISTINCT FROM pending.target_type
          OR project.workspace_id IS DISTINCT FROM pending.workspace_id
          OR workspace.workspace_kind IS DISTINCT FROM 'personal'
          OR workspace.personal_owner_app_user_id IS DISTINCT FROM pending.actor_app_user_id)
    ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship metadata or payload is incomplete';
  END IF;

  INSERT INTO app_private.personal_merge_unassigned_project_relationship_purges_v1 (
    pending_fact_id, generation_id, purged_at_utc
  )
  SELECT pending.pending_fact_id, pending.generation_id, NEW.ended_at_utc
  FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
  WHERE pending.generation_id = NEW.generation_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship purge count mismatch';
  END IF;

  DELETE FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS fact
  USING app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
  WHERE pending.pending_fact_id = fact.pending_fact_id AND pending.generation_id = NEW.generation_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS fact
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
    WHERE pending.generation_id = NEW.generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship purge count mismatch';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER pmupr_expiry_purge
AFTER INSERT ON app_private.personal_target_merge_end_events_v1
FOR EACH ROW WHEN (NEW.reason = 'retention_expired')
EXECUTE FUNCTION app_private.purge_personal_merge_unassigned_project_relationships_v1();

CREATE FUNCTION app_private.stage_unassigned_personal_merge_project_relationship_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  requested_new_stage integer,
  requested_new_lifecycle_status text,
  requested_follow_up_note text,
  requested_reason_code text,
  requested_reason_detail text
)
RETURNS TABLE (
  unassigned_project_relationship_contract_id text,
  pending_fact_id uuid,
  staged_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  known_plan jsonb;
  pending_row app_private.personal_merge_unassigned_project_relationship_requests_v1%ROWTYPE;
  payload_row app_data.personal_merge_unassigned_project_relationship_facts_v1%ROWTYPE;
  source_ids uuid[];
  pending_id uuid;
  checked_at timestamptz;
  affected_count bigint;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'unassigned project relationship requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_request_id IS NULL OR requested_generation_id IS NULL
    OR requested_new_stage IS NULL OR requested_new_stage NOT BETWEEN 0 AND 4
    OR requested_new_lifecycle_status IS NULL OR requested_new_lifecycle_status NOT IN ('active', 'paused', 'ended')
    OR (requested_follow_up_note IS NOT NULL
      AND (length(requested_follow_up_note) > 4000 OR requested_follow_up_note !~ '[^[:space:]]'))
    OR requested_reason_code IS NULL OR requested_reason_code NOT IN (
      'project_entry', 'progress_update', 'contact_lost', 'timing_changed',
      'requirements_changed', 'target_request', 'project_change', 'correction', 'other'
    )
    OR (requested_reason_detail IS NOT NULL
      AND (length(requested_reason_detail) > 1000 OR requested_reason_detail !~ '[^[:space:]]'))
    OR (requested_reason_code = 'other' AND requested_reason_detail IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid unassigned project relationship request';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'personal-merge-unassigned-project-relationship:' || trusted_app_user_id::text || ':' || requested_request_id::text, 0
  ));
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  SELECT * INTO pending_row
  FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending
  WHERE pending.actor_app_user_id = trusted_app_user_id AND pending.request_id = requested_request_id;
  IF FOUND AND (pending_row.workspace_id IS DISTINCT FROM trusted_workspace_id
    OR pending_row.project_id IS DISTINCT FROM trusted_project_id
    OR pending_row.generation_id IS DISTINCT FROM requested_generation_id) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'unassigned project relationship request context changed';
  END IF;

  known_plan := app_private.read_known_source_personal_merge_split_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id
  );
  SELECT array_agg(value::uuid) INTO source_ids
  FROM jsonb_array_elements_text(known_plan->'member_target_ids');
  checked_at := clock_timestamp();
  IF NOT coalesce((SELECT bool_and(coalesce(app_data.promotion_target_review_due_at(member.target_id) > checked_at, false))
    FROM unnest(source_ids) AS member(target_id)), false) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'unassigned project relationship generation is due';
  END IF;

  IF pending_row.pending_fact_id IS NOT NULL THEN
    SELECT * INTO payload_row
    FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 AS fact
    WHERE fact.pending_fact_id = pending_row.pending_fact_id;
    IF NOT FOUND OR pending_row.target_type IS DISTINCT FROM known_plan->>'target_type'
      OR EXISTS (
        SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge
        WHERE purge.pending_fact_id = pending_row.pending_fact_id
      ) THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship metadata or payload is incomplete';
    END IF;
    IF payload_row.new_stage IS DISTINCT FROM requested_new_stage
      OR payload_row.new_lifecycle_status IS DISTINCT FROM requested_new_lifecycle_status
      OR payload_row.follow_up_note IS DISTINCT FROM requested_follow_up_note
      OR payload_row.reason_code IS DISTINCT FROM requested_reason_code
      OR payload_row.reason_detail IS DISTINCT FROM requested_reason_detail THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'unassigned project relationship request payload changed';
    END IF;
    RETURN QUERY SELECT 'personal-merge-unassigned-project-relationship:v1'::text,
      pending_row.pending_fact_id, pending_row.staged_at_utc;
    RETURN;
  END IF;

  pending_id := gen_random_uuid();
  INSERT INTO app_private.personal_merge_unassigned_project_relationship_requests_v1 (
    pending_fact_id, actor_app_user_id, workspace_id, project_id, generation_id,
    target_type, request_id, staged_at_utc
  ) VALUES (
    pending_id, trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    known_plan->>'target_type', requested_request_id, checked_at
  );
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship metadata or payload is incomplete';
  END IF;
  INSERT INTO app_data.personal_merge_unassigned_project_relationship_facts_v1 (
    pending_fact_id, new_stage, new_lifecycle_status, follow_up_note, reason_code, reason_detail
  ) VALUES (
    pending_id, requested_new_stage, requested_new_lifecycle_status,
    requested_follow_up_note, requested_reason_code, requested_reason_detail
  );
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship metadata or payload is incomplete';
  END IF;
  RETURN QUERY SELECT 'personal-merge-unassigned-project-relationship:v1'::text, pending_id, checked_at;
END
$function$;

CREATE FUNCTION app_private.read_personal_merge_unassigned_project_relationship_plan_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_generation_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  preview jsonb;
  complete boolean;
BEGIN
  WITH known AS MATERIALIZED (
    SELECT app_private.read_known_source_personal_merge_split_plan_v1(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id
    ) AS plan
  ), pending AS MATERIALIZED (
    SELECT header.pending_fact_id, header.project_id, header.target_type, header.staged_at_utc,
      fact.pending_fact_id IS NOT NULL AND purge.pending_fact_id IS NULL
        AND header.actor_app_user_id = trusted_app_user_id
        AND header.workspace_id = trusted_workspace_id
        AND project.workspace_id = header.workspace_id
        AND workspace.workspace_kind = 'personal'
        AND workspace.personal_owner_app_user_id = header.actor_app_user_id
        AND generation.workspace_id = header.workspace_id
        AND generation.created_by_app_user_id = header.actor_app_user_id
        AND generation.target_type = header.target_type
        AND header.target_type = known.plan->>'target_type' AS intact
    FROM known
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS header
      ON header.generation_id = (known.plan->>'generation_id')::uuid
    LEFT JOIN app_private.personal_target_merge_generations_v1 AS generation USING (generation_id)
    LEFT JOIN app_data.projects AS project ON project.project_id = header.project_id
    LEFT JOIN app_data.workspaces AS workspace ON workspace.workspace_id = header.workspace_id
    LEFT JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 AS fact USING (pending_fact_id)
    LEFT JOIN app_private.personal_merge_unassigned_project_relationship_purges_v1 AS purge USING (pending_fact_id)
  ), metadata AS MATERIALIZED (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'pending_fact_id', pending.pending_fact_id, 'project_id', pending.project_id,
      'target_type', pending.target_type,
      'staged_at_utc', to_char(pending.staged_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ) ORDER BY pending.pending_fact_id), '[]'::jsonb) AS items,
      count(*) AS item_count, coalesce(bool_and(coalesce(pending.intact, false)), true) AS intact
    FROM pending
  )
  SELECT jsonb_build_object(
    'known_source_plan', known.plan, 'pending_project_relationships', metadata.items,
    'pending_count', metadata.item_count,
    'pending_fingerprint', encode(sha256(convert_to(metadata.items::text, 'UTF8')), 'hex')
  ), metadata.intact INTO preview, complete
  FROM known CROSS JOIN metadata;
  IF NOT coalesce(complete, false) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending project relationship metadata or payload is incomplete';
  END IF;
  RETURN preview;
END
$function$;

REVOKE ALL ON TABLE
  app_private.personal_merge_unassigned_project_relationship_requests_v1,
  app_data.personal_merge_unassigned_project_relationship_facts_v1,
  app_private.personal_merge_unassigned_project_relationship_purges_v1
  FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION
  app_private.guard_personal_merge_unassigned_project_relationship_payload_v1(),
  app_private.guard_personal_merge_unassigned_project_relationship_end_v1(),
  app_private.purge_personal_merge_unassigned_project_relationships_v1(),
  app_private.stage_unassigned_personal_merge_project_relationship_v1(uuid,uuid,uuid,uuid,uuid,integer,text,text,text,text),
  app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
  object_name text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.personal_merge_unassigned_project_relationship_requests_v1',
    'app_data.personal_merge_unassigned_project_relationship_facts_v1',
    'app_private.personal_merge_unassigned_project_relationship_purges_v1'
  ] LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()',
    'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()',
    'app_private.purge_personal_merge_unassigned_project_relationships_v1()',
    'app_private.stage_unassigned_personal_merge_project_relationship_v1(uuid,uuid,uuid,uuid,uuid,integer,text,text,text,text)',
    'app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
END
$owner$;
