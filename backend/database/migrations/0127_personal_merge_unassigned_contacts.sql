-- New contact associations awaiting a source decision; existing facts stay bound.
CREATE TABLE app_private.personal_merge_unassigned_contact_requests_v1 (
  pending_fact_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL REFERENCES app_data.app_users (app_user_id),
  workspace_id uuid NOT NULL REFERENCES app_data.workspaces (workspace_id),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  generation_id uuid NOT NULL REFERENCES app_private.personal_target_merge_generations_v1 (generation_id),
  contact_id text NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  target_type text NOT NULL CHECK (target_type IN ('person', 'institution')),
  request_id uuid NOT NULL,
  staged_at_utc timestamptz NOT NULL CHECK (isfinite(staged_at_utc)),
  FOREIGN KEY (contact_id, revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  UNIQUE (actor_app_user_id, request_id),
  UNIQUE (generation_id, contact_id, revision_number),
  UNIQUE (pending_fact_id, generation_id)
);

CREATE TABLE app_data.personal_merge_unassigned_contact_facts_v1 (
  pending_fact_id uuid PRIMARY KEY REFERENCES
    app_private.personal_merge_unassigned_contact_requests_v1 (pending_fact_id),
  response_level integer CHECK (response_level BETWEEN 0 AND 4),
  follow_up_consent text NOT NULL CHECK (
    follow_up_consent IN ('yes', 'no', 'unknown', 'refused', 'not_applicable')
  ),
  institution_representative_confirmed boolean NOT NULL,
  confirmed_project_entry boolean NOT NULL
);

CREATE TABLE app_private.personal_merge_unassigned_contact_purges_v1 (
  pending_fact_id uuid PRIMARY KEY,
  generation_id uuid NOT NULL REFERENCES app_private.personal_target_merge_end_events_v1 (generation_id),
  purged_at_utc timestamptz NOT NULL CHECK (isfinite(purged_at_utc)),
  FOREIGN KEY (pending_fact_id, generation_id) REFERENCES
    app_private.personal_merge_unassigned_contact_requests_v1 (pending_fact_id, generation_id)
);

CREATE TRIGGER personal_merge_unassigned_contact_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_unassigned_contact_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE TRIGGER personal_merge_unassigned_contact_purges_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_unassigned_contact_purges_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.guard_personal_merge_unassigned_contact_payload_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact facts cannot be updated';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
    JOIN app_private.personal_target_merge_end_events_v1 AS receipt USING (generation_id)
    WHERE purge.pending_fact_id = OLD.pending_fact_id
      AND receipt.reason = 'retention_expired'
      AND receipt.operation = 'personal_target_known_source_merge_expire'
      AND receipt.outcome = 'ended'
      AND purge.purged_at_utc = receipt.ended_at_utc
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact deletion requires expiry receipt';
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER guard_personal_merge_unassigned_contact_payload_trigger
BEFORE UPDATE OR DELETE ON app_data.personal_merge_unassigned_contact_facts_v1
FOR EACH ROW EXECUTE FUNCTION app_private.guard_personal_merge_unassigned_contact_payload_v1();

CREATE FUNCTION app_private.guard_personal_merge_unassigned_contact_end_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
BEGIN
  IF NEW.reason = 'known_source_split' AND EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
    WHERE pending.generation_id = NEW.generation_id
      AND NOT EXISTS (
        SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
        WHERE purge.pending_fact_id = pending.pending_fact_id
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'unassigned contact facts prevent known-source split';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER guard_personal_merge_unassigned_contact_end_trigger
BEFORE INSERT ON app_private.personal_target_merge_end_events_v1
FOR EACH ROW EXECUTE FUNCTION app_private.guard_personal_merge_unassigned_contact_end_v1();

CREATE FUNCTION app_private.purge_personal_merge_unassigned_contacts_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  expected_count bigint;
  affected_count bigint;
BEGIN
  SELECT count(*) INTO expected_count
  FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
  WHERE pending.generation_id = NEW.generation_id;
  IF (SELECT count(*)
      FROM app_data.personal_merge_unassigned_contact_facts_v1 AS fact
      JOIN app_private.personal_merge_unassigned_contact_requests_v1 AS pending USING (pending_fact_id)
      WHERE pending.generation_id = NEW.generation_id) <> expected_count THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact payload is incomplete';
  END IF;

  INSERT INTO app_private.personal_merge_unassigned_contact_purges_v1 (
    pending_fact_id, generation_id, purged_at_utc
  )
  SELECT pending.pending_fact_id, pending.generation_id, NEW.ended_at_utc
  FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
  WHERE pending.generation_id = NEW.generation_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact purge history count mismatch';
  END IF;

  DELETE FROM app_data.personal_merge_unassigned_contact_facts_v1 AS fact
  USING app_private.personal_merge_unassigned_contact_requests_v1 AS pending
  WHERE pending.pending_fact_id = fact.pending_fact_id
    AND pending.generation_id = NEW.generation_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 AS fact
    JOIN app_private.personal_merge_unassigned_contact_requests_v1 AS pending USING (pending_fact_id)
    WHERE pending.generation_id = NEW.generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact purge count mismatch';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER purge_personal_merge_unassigned_contacts_trigger
AFTER INSERT ON app_private.personal_target_merge_end_events_v1
FOR EACH ROW WHEN (NEW.reason = 'retention_expired')
EXECUTE FUNCTION app_private.purge_personal_merge_unassigned_contacts_v1();

CREATE FUNCTION app_private.stage_unassigned_personal_merge_contact_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  requested_contact_id text,
  requested_revision_number integer,
  requested_response_level integer,
  requested_follow_up_consent text,
  requested_institution_representative_confirmed boolean,
  requested_confirmed_project_entry boolean
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  known_plan jsonb;
  pending_row app_private.personal_merge_unassigned_contact_requests_v1%ROWTYPE;
  payload_row app_data.personal_merge_unassigned_contact_facts_v1%ROWTYPE;
  source_ids uuid[];
  pending_id uuid;
  affected_count bigint;
  checked_at timestamptz;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_request_id IS NULL OR requested_generation_id IS NULL
    OR requested_contact_id IS NULL OR length(btrim(requested_contact_id)) = 0
    OR requested_revision_number IS NULL OR requested_revision_number <= 0
    OR (requested_response_level IS NOT NULL AND requested_response_level NOT BETWEEN 0 AND 4)
    OR requested_follow_up_consent IS NULL
    OR requested_follow_up_consent NOT IN ('yes', 'no', 'unknown', 'refused', 'not_applicable')
    OR requested_institution_representative_confirmed IS NULL
    OR requested_confirmed_project_entry IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid unassigned contact request';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || requested_request_id::text, 0
  ));
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  SELECT * INTO pending_row
  FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
  WHERE pending.actor_app_user_id = trusted_app_user_id AND pending.request_id = requested_request_id;
  IF FOUND AND (
    pending_row.workspace_id IS DISTINCT FROM trusted_workspace_id
    OR pending_row.project_id IS DISTINCT FROM trusted_project_id
    OR pending_row.generation_id IS DISTINCT FROM requested_generation_id
    OR pending_row.contact_id IS DISTINCT FROM requested_contact_id
    OR pending_row.revision_number IS DISTINCT FROM requested_revision_number
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'unassigned contact request context changed';
  END IF;
  known_plan := app_private.read_known_source_personal_merge_split_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id
  );
  SELECT array_agg(value::uuid) INTO source_ids
  FROM jsonb_array_elements_text(known_plan->'member_target_ids');
  checked_at := clock_timestamp();
  IF NOT coalesce((SELECT bool_and(
    app_data.promotion_target_review_due_at(member.target_id) > checked_at
  ) FROM unnest(source_ids) AS member(target_id)), false) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'unassigned contact generation is due';
  END IF;
  IF (known_plan->>'target_type' = 'person' AND requested_institution_representative_confirmed)
    OR (known_plan->>'target_type' = 'institution' AND requested_response_level IS NOT NULL
      AND NOT requested_institution_representative_confirmed) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid unassigned contact target response';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.contacts AS contact
    JOIN app_data.contact_revisions AS revision USING (contact_id)
    JOIN app_private.personal_target_merge_generations_v1 AS generation
      ON generation.generation_id = requested_generation_id
    WHERE contact.contact_id = requested_contact_id
      AND revision.revision_number = requested_revision_number
      AND contact.app_user_id = trusted_app_user_id
      AND contact.workspace_id = trusted_workspace_id AND contact.project_id = trusted_project_id
      AND contact.lifecycle_status = 'active'
      AND revision.revised_by_app_user_id = trusted_app_user_id
      AND revision.revised_at_utc >= generation.activated_at_utc
  ) OR EXISTS (
    SELECT 1 FROM app_data.contact_target_links AS link
    WHERE link.contact_id = requested_contact_id AND link.revision_number = requested_revision_number
      AND link.promotion_target_id = ANY(source_ids)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'contact revision is not eligible for unassigned staging';
  END IF;

  IF pending_row.pending_fact_id IS NOT NULL THEN
    IF pending_row.target_type IS DISTINCT FROM known_plan->>'target_type' THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact target type is inconsistent';
    END IF;
    SELECT * INTO payload_row FROM app_data.personal_merge_unassigned_contact_facts_v1 AS fact
    WHERE fact.pending_fact_id = pending_row.pending_fact_id;
    IF NOT FOUND OR EXISTS (
      SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
      WHERE purge.pending_fact_id = pending_row.pending_fact_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'live pending contact payload is incomplete';
    END IF;
    IF payload_row.response_level IS DISTINCT FROM requested_response_level
      OR payload_row.follow_up_consent IS DISTINCT FROM requested_follow_up_consent
      OR payload_row.institution_representative_confirmed IS DISTINCT FROM requested_institution_representative_confirmed
      OR payload_row.confirmed_project_entry IS DISTINCT FROM requested_confirmed_project_entry THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'unassigned contact request payload changed';
    END IF;
    RETURN pending_row.pending_fact_id;
  END IF;

  pending_id := gen_random_uuid();
  INSERT INTO app_private.personal_merge_unassigned_contact_requests_v1 (
    pending_fact_id, actor_app_user_id, workspace_id, project_id, generation_id,
    contact_id, revision_number, target_type, request_id, staged_at_utc
  ) VALUES (
    pending_id, trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    requested_contact_id, requested_revision_number, known_plan->>'target_type', requested_request_id, clock_timestamp()
  );
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact request insert count mismatch';
  END IF;
  INSERT INTO app_data.personal_merge_unassigned_contact_facts_v1 (
    pending_fact_id, response_level, follow_up_consent,
    institution_representative_confirmed, confirmed_project_entry
  ) VALUES (
    pending_id, requested_response_level, requested_follow_up_consent,
    requested_institution_representative_confirmed, requested_confirmed_project_entry
  );
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact fact insert count mismatch';
  END IF;
  RETURN pending_id;
END
$function$;

CREATE FUNCTION app_private.read_personal_merge_unassigned_contact_plan_v1(
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
  preview jsonb;
  complete boolean;
BEGIN
  WITH known AS MATERIALIZED (
    SELECT app_private.read_known_source_personal_merge_split_plan_v1(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id
    ) AS plan
  ), pending AS MATERIALIZED (
    SELECT header.pending_fact_id, header.contact_id, header.revision_number,
      header.target_type, header.staged_at_utc,
      fact.pending_fact_id IS NOT NULL AND purge.pending_fact_id IS NULL
        AND header.actor_app_user_id = trusted_app_user_id
        AND header.workspace_id = trusted_workspace_id
        AND EXISTS (
          SELECT 1 FROM app_data.contacts AS contact
          WHERE contact.contact_id = header.contact_id
            AND contact.app_user_id = header.actor_app_user_id
            AND contact.workspace_id = header.workspace_id
            AND contact.project_id = header.project_id
        )
        AND header.target_type = known.plan->>'target_type' AS intact
    FROM known
    JOIN app_private.personal_merge_unassigned_contact_requests_v1 AS header
      ON header.generation_id = (known.plan->>'generation_id')::uuid
    LEFT JOIN app_data.personal_merge_unassigned_contact_facts_v1 AS fact USING (pending_fact_id)
    LEFT JOIN app_private.personal_merge_unassigned_contact_purges_v1 AS purge USING (pending_fact_id)
  ), metadata AS MATERIALIZED (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'pending_fact_id', pending.pending_fact_id, 'contact_id', pending.contact_id,
      'revision_number', pending.revision_number, 'target_type', pending.target_type,
      'staged_at_utc', to_char(pending.staged_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ) ORDER BY pending.pending_fact_id), '[]'::jsonb) AS items,
      count(*) AS item_count, coalesce(bool_and(pending.intact), true) AS intact
    FROM pending
  )
  SELECT jsonb_build_object(
    'known_source_plan', known.plan, 'pending_contacts', metadata.items,
    'pending_count', metadata.item_count,
    'pending_fingerprint', encode(sha256(convert_to(metadata.items::text, 'UTF8')), 'hex')
  ), metadata.intact INTO preview, complete
  FROM known CROSS JOIN metadata;
  IF NOT coalesce(complete, false) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact metadata or payload is incomplete';
  END IF;
  RETURN preview;
END
$function$;

REVOKE ALL ON TABLE
  app_private.personal_merge_unassigned_contact_requests_v1,
  app_data.personal_merge_unassigned_contact_facts_v1,
  app_private.personal_merge_unassigned_contact_purges_v1
  FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION
  app_private.guard_personal_merge_unassigned_contact_payload_v1(),
  app_private.guard_personal_merge_unassigned_contact_end_v1(),
  app_private.purge_personal_merge_unassigned_contacts_v1(),
  app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean),
  app_private.read_personal_merge_unassigned_contact_plan_v1(uuid,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
  object_name text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.personal_merge_unassigned_contact_requests_v1',
    'app_data.personal_merge_unassigned_contact_facts_v1',
    'app_private.personal_merge_unassigned_contact_purges_v1'
  ] LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.guard_personal_merge_unassigned_contact_payload_v1()',
    'app_private.guard_personal_merge_unassigned_contact_end_v1()',
    'app_private.purge_personal_merge_unassigned_contacts_v1()',
    'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)',
    'app_private.read_personal_merge_unassigned_contact_plan_v1(uuid,uuid,uuid,uuid)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
END
$owner$;
