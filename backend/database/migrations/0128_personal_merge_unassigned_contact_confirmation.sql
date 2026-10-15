-- Resolve only one current pending association per contact through the shared revision writer.
CREATE TABLE app_private.personal_merge_contact_confirmation_requests_v1 (
  actor_app_user_id uuid NOT NULL REFERENCES app_data.app_users (app_user_id),
  request_id uuid NOT NULL,
  workspace_id uuid NOT NULL REFERENCES app_data.workspaces (workspace_id),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  generation_id uuid NOT NULL UNIQUE REFERENCES app_private.personal_target_merge_generations_v1 (generation_id),
  known_fact_fingerprint text NOT NULL CHECK (known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  pending_fingerprint text NOT NULL CHECK (pending_fingerprint ~ '^[0-9a-f]{64}$'),
  post_known_fact_fingerprint text NOT NULL CHECK (post_known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  confirmed_at_utc timestamptz NOT NULL CHECK (isfinite(confirmed_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id),
  FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_target_merge_end_events_v1 (actor_app_user_id, request_id)
    DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE app_private.personal_merge_contact_applications_v1 (
  pending_fact_id uuid PRIMARY KEY REFERENCES app_private.personal_merge_unassigned_contact_requests_v1 (pending_fact_id),
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  contact_id text NOT NULL,
  from_revision_number integer NOT NULL CHECK (from_revision_number > 0),
  to_revision_number integer NOT NULL CHECK (to_revision_number = from_revision_number + 1),
  source_target_id uuid NOT NULL,
  child_command_id text NOT NULL CHECK (length(child_command_id) > 0),
  FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_contact_confirmation_requests_v1 (actor_app_user_id, request_id),
  FOREIGN KEY (contact_id, from_revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  FOREIGN KEY (contact_id, to_revision_number, source_target_id)
    REFERENCES app_data.contact_target_links (contact_id, revision_number, promotion_target_id),
  UNIQUE (actor_app_user_id, request_id, contact_id),
  UNIQUE (actor_app_user_id, child_command_id)
);

CREATE TRIGGER personal_merge_contact_confirmation_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_contact_confirmation_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER personal_merge_contact_applications_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_contact_applications_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.personal_merge_contact_confirmation_proof_v1(
  trusted_app_user_id uuid, requested_request_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  SELECT coalesce((
    SELECT
      (SELECT count(*) FROM app_private.personal_merge_contact_applications_v1 a
        WHERE a.actor_app_user_id = request.actor_app_user_id AND a.request_id = request.request_id) > 0
      AND (SELECT count(*) FROM app_private.personal_merge_contact_applications_v1 a
        WHERE a.actor_app_user_id = request.actor_app_user_id AND a.request_id = request.request_id)
        = (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
          WHERE pending.generation_id = request.generation_id)
      AND (SELECT manifest.fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(
        request.generation_id) manifest) = request.post_known_fact_fingerprint
      AND NOT EXISTS (
        SELECT 1 FROM app_private.personal_merge_contact_applications_v1 application
        LEFT JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING (pending_fact_id)
        LEFT JOIN app_data.personal_merge_unassigned_contact_facts_v1 payload USING (pending_fact_id)
        LEFT JOIN app_data.contacts contact ON contact.contact_id = application.contact_id
        LEFT JOIN app_data.contact_revisions original ON original.contact_id = application.contact_id
          AND original.revision_number = application.from_revision_number
        LEFT JOIN app_data.contact_revisions revised ON revised.contact_id = application.contact_id
          AND revised.revision_number = application.to_revision_number
        LEFT JOIN app_data.contact_target_links link ON link.contact_id = application.contact_id
          AND link.revision_number = application.to_revision_number AND link.promotion_target_id = application.source_target_id
        WHERE application.actor_app_user_id = request.actor_app_user_id AND application.request_id = request.request_id
          AND NOT coalesce(
            pending.generation_id = request.generation_id
            AND pending.actor_app_user_id = request.actor_app_user_id AND pending.workspace_id = request.workspace_id
            AND pending.contact_id = application.contact_id AND pending.revision_number = application.from_revision_number
            AND contact.app_user_id = pending.actor_app_user_id AND contact.workspace_id = pending.workspace_id
            AND contact.project_id = pending.project_id AND contact.lifecycle_status = 'active'
            AND contact.current_revision = application.to_revision_number
            AND revised.revision_kind = 'corrected' AND revised.revised_by_app_user_id = request.actor_app_user_id
            AND EXISTS (SELECT 1 FROM app_private.personal_target_merge_generation_members_v1 member
              WHERE member.generation_id = request.generation_id AND member.promotion_target_id = application.source_target_id
                AND member.workspace_id = pending.workspace_id AND member.target_type = pending.target_type)
            AND link.merge_generation_id = request.generation_id
            AND (
              (payload.pending_fact_id IS NOT NULL
                AND link.response_level IS NOT DISTINCT FROM payload.response_level
                AND link.follow_up_consent = payload.follow_up_consent
                AND link.institution_representative_confirmed = payload.institution_representative_confirmed
                AND link.confirmed_project_entry = payload.confirmed_project_entry)
              OR (payload.pending_fact_id IS NULL AND EXISTS (
                SELECT 1 FROM app_private.personal_target_merge_end_events_v1 ended
                WHERE ended.generation_id = request.generation_id AND ended.actor_app_user_id = request.actor_app_user_id
                  AND ended.request_id = request.request_id AND ended.workspace_id = request.workspace_id
                  AND ended.project_id = request.project_id AND ended.reason = 'known_source_split'
                  AND ended.operation = 'personal_target_known_source_merge_end' AND ended.outcome = 'ended'
                  AND ended.fact_fingerprint = request.post_known_fact_fingerprint))
            )
            AND (revised.snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
              = (original.snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
            AND revised.snapshot->'targetLinks' = coalesce(original.snapshot->'targetLinks', '[]'::jsonb)
              || jsonb_build_array(jsonb_build_object(
                'targetId', application.source_target_id, 'targetType', pending.target_type,
                'responseLevel', link.response_level, 'followUpConsent', link.follow_up_consent,
                'institutionRepresentativeConfirmed', link.institution_representative_confirmed,
                'confirmStageZero', link.confirmed_project_entry))
            AND (SELECT count(*) FROM app_data.contact_target_links installed
              WHERE installed.contact_id = application.contact_id AND installed.revision_number = application.to_revision_number)
              = (SELECT count(*) + 1 FROM app_data.contact_target_links prior
                WHERE prior.contact_id = application.contact_id AND prior.revision_number = application.from_revision_number)
            AND NOT EXISTS (SELECT 1 FROM app_data.contact_target_links prior
              WHERE prior.contact_id = application.contact_id AND prior.revision_number = application.from_revision_number
                AND NOT EXISTS (SELECT 1 FROM app_data.contact_target_links installed
                  WHERE installed.contact_id = prior.contact_id AND installed.revision_number = application.to_revision_number
                    AND installed.promotion_target_id = prior.promotion_target_id
                    AND installed.response_level IS NOT DISTINCT FROM prior.response_level
                    AND installed.follow_up_consent = prior.follow_up_consent
                    AND installed.institution_representative_confirmed = prior.institution_representative_confirmed
                    AND installed.confirmed_project_entry = prior.confirmed_project_entry))
            AND EXISTS (SELECT 1 FROM app_data.processed_commands command
              JOIN app_data.change_feed feed ON feed.cursor_token = command.server_cursor
              WHERE command.app_user_id = request.actor_app_user_id AND command.command_id = application.child_command_id
                AND command.result_code = 'accepted' AND command.command_type = 'contact.revise.v1'
                AND command.aggregate_id = application.contact_id AND feed.aggregate_id = application.contact_id
                AND feed.app_user_id = pending.actor_app_user_id AND feed.workspace_id = pending.workspace_id
                AND feed.project_id = pending.project_id AND feed.revision_number = application.to_revision_number
                AND feed.change_type = 'contact.revised' AND feed.change_payload = revised.snapshot)
            AND EXISTS (SELECT 1 FROM app_data.contact_audit_events audit
              WHERE audit.app_user_id = request.actor_app_user_id AND audit.command_id = application.child_command_id
                AND audit.contact_id = application.contact_id AND audit.revision_number = application.to_revision_number
                AND audit.event_type = 'contact.revised')
            AND EXISTS (SELECT 1 FROM app_data.warehouse_outbox warehouse
              WHERE warehouse.contact_id = application.contact_id AND warehouse.project_id = pending.project_id
                AND warehouse.revision_number = application.to_revision_number AND warehouse.event_type = 'contact.revised'
                AND NOT warehouse.analytics_payload ?| ARRAY['targetLinks','target_links','location','locationSource','location_source']
                AND warehouse.analytics_payload->'target_link_facts' = (
                  SELECT coalesce(jsonb_agg(jsonb_build_object('target_type', target.target_type,
                    'response_level', installed.response_level, 'follow_up_consent', installed.follow_up_consent)
                    ORDER BY installed.promotion_target_id), '[]'::jsonb)
                  FROM app_data.contact_target_links installed JOIN app_data.promotion_targets target
                    ON target.promotion_target_id = installed.promotion_target_id
                  WHERE installed.contact_id = application.contact_id AND installed.revision_number = application.to_revision_number))
          , false)
      )
    FROM app_private.personal_merge_contact_confirmation_requests_v1 request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
  ), false);
$function$;

CREATE OR REPLACE FUNCTION app_private.guard_personal_merge_unassigned_contact_end_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
BEGIN
  IF NEW.reason = 'known_source_split' AND EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
    WHERE pending.generation_id = NEW.generation_id
      AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 purge
        WHERE purge.pending_fact_id = pending.pending_fact_id)
  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_contact_confirmation_requests_v1 request
    WHERE request.actor_app_user_id = NEW.actor_app_user_id AND request.request_id = NEW.request_id
      AND request.workspace_id = NEW.workspace_id AND request.project_id = NEW.project_id
      AND request.generation_id = NEW.generation_id AND request.post_known_fact_fingerprint = NEW.fact_fingerprint
      AND NEW.operation = 'personal_target_known_source_merge_end' AND NEW.outcome = 'ended'
      AND app_private.personal_merge_contact_confirmation_proof_v1(request.actor_app_user_id, request.request_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'unassigned contact facts require complete revision applications';
  END IF;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION app_private.guard_personal_merge_unassigned_contact_payload_v1()
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
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 purge
    JOIN app_private.personal_target_merge_end_events_v1 receipt USING (generation_id)
    WHERE purge.pending_fact_id = OLD.pending_fact_id AND receipt.reason = 'retention_expired'
      AND receipt.operation = 'personal_target_known_source_merge_expire' AND receipt.outcome = 'ended'
      AND purge.purged_at_utc = receipt.ended_at_utc
  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_contact_applications_v1 application
    JOIN app_private.personal_merge_contact_confirmation_requests_v1 request
      USING (actor_app_user_id, request_id)
    JOIN app_private.personal_target_merge_end_events_v1 receipt
      ON receipt.actor_app_user_id = request.actor_app_user_id AND receipt.request_id = request.request_id
      AND receipt.generation_id = request.generation_id AND receipt.workspace_id = request.workspace_id
      AND receipt.project_id = request.project_id AND receipt.fact_fingerprint = request.post_known_fact_fingerprint
    WHERE application.pending_fact_id = OLD.pending_fact_id AND receipt.reason = 'known_source_split'
      AND receipt.operation = 'personal_target_known_source_merge_end' AND receipt.outcome = 'ended'
      AND app_private.personal_merge_contact_confirmation_proof_v1(request.actor_app_user_id, request.request_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact deletion requires expiry or applied confirmation receipt';
  END IF;
  RETURN OLD;
END
$function$;

CREATE FUNCTION app_private.confirm_unassigned_personal_merge_contacts_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_request_id uuid,
  requested_generation_id uuid,
  expected_known_fact_fingerprint text,
  expected_pending_fingerprint text,
  requested_assignments jsonb
)
RETURNS timestamptz
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  assignment jsonb;
  canonical_assignments jsonb;
  replay_assignments jsonb;
  request_row app_private.personal_merge_contact_confirmation_requests_v1%ROWTYPE;
  read_plan jsonb;
  source_ids uuid[];
  prelocked_contacts text[];
  contact_key text;
  command_key text;
  item record;
  result_row record;
  affected_count bigint;
  expected_count bigint;
  post_fingerprint text;
  ended_at_value timestamptz;
  checked_at timestamptz;
BEGIN
  IF trusted_app_user_id IS NULL OR trusted_workspace_id IS NULL OR trusted_project_id IS NULL
    OR requested_request_id IS NULL OR requested_generation_id IS NULL
    OR expected_known_fact_fingerprint IS NULL OR expected_known_fact_fingerprint !~ '^[0-9a-f]{64}$'
    OR expected_pending_fingerprint IS NULL OR expected_pending_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_assignments IS NULL OR jsonb_typeof(requested_assignments) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact confirmation request';
  END IF;
  IF jsonb_array_length(requested_assignments) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'pending contact confirmation requires assignments';
  END IF;
  FOR assignment IN SELECT value FROM jsonb_array_elements(requested_assignments) LOOP
    IF jsonb_typeof(assignment) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact assignment';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(assignment)) <> 2
      OR NOT assignment ?& ARRAY['pending_fact_id','source_target_id']
      OR jsonb_typeof(assignment->'pending_fact_id') <> 'string'
      OR jsonb_typeof(assignment->'source_target_id') <> 'string'
      OR assignment->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR assignment->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact assignment keys or UUIDs';
    END IF;
  END LOOP;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', (value->>'pending_fact_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid) ORDER BY (value->>'pending_fact_id')::uuid), count(*)
    INTO canonical_assignments, expected_count FROM jsonb_array_elements(requested_assignments);
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid)
      FROM jsonb_array_elements(canonical_assignments)) <> expected_count THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending contact assignment';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));
  SELECT * INTO request_row FROM app_private.personal_merge_contact_confirmation_requests_v1 request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF FOUND THEN
    IF request_row.workspace_id IS DISTINCT FROM trusted_workspace_id
      OR request_row.project_id IS DISTINCT FROM trusted_project_id
      OR request_row.generation_id IS DISTINCT FROM requested_generation_id
      OR request_row.known_fact_fingerprint IS DISTINCT FROM expected_known_fact_fingerprint
      OR request_row.pending_fingerprint IS DISTINCT FROM expected_pending_fingerprint THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact confirmation request changed';
    END IF;
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id', application.pending_fact_id,
      'source_target_id', application.source_target_id) ORDER BY application.pending_fact_id)
      INTO replay_assignments FROM app_private.personal_merge_contact_applications_v1 application
      WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
    IF replay_assignments IS DISTINCT FROM canonical_assignments THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact confirmation assignments changed';
    END IF;
    RETURN app_private.end_known_source_personal_target_merge_generation_v1(
      trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_request_id,
      requested_generation_id, request_row.post_known_fact_fingerprint);
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'confirmation request already belongs to another end operation';
  END IF;

  SELECT coalesce(array_agg(contact_id ORDER BY contact_id COLLATE "C"), ARRAY[]::text[])
    INTO prelocked_contacts FROM (SELECT DISTINCT pending.contact_id
      FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
      WHERE pending.generation_id = requested_generation_id) contacts;
  FOR command_key IN SELECT command_id FROM (
    SELECT 'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
      || octet_length(contact_id)::text || ':' || contact_id AS command_id
    FROM unnest(prelocked_contacts) contacts(contact_id)
  ) commands ORDER BY command_id COLLATE "C"
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || command_key, 0));
  END LOOP;
  FOREACH contact_key IN ARRAY prelocked_contacts LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('contact:' || contact_key, 0));
    PERFORM 1 FROM app_data.contacts contact WHERE contact.contact_id = contact_key FOR UPDATE;
  END LOOP;
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  read_plan := app_private.read_personal_merge_unassigned_contact_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id);
  IF read_plan->'known_source_plan'->>'fact_fingerprint' IS DISTINCT FROM expected_known_fact_fingerprint
    OR read_plan->>'pending_fingerprint' IS DISTINCT FROM expected_pending_fingerprint
    OR (SELECT jsonb_agg(value->'pending_fact_id' ORDER BY (value->>'pending_fact_id')::uuid)
      FROM jsonb_array_elements(read_plan->'pending_contacts')) IS DISTINCT FROM
      (SELECT jsonb_agg(value->'pending_fact_id' ORDER BY (value->>'pending_fact_id')::uuid)
        FROM jsonb_array_elements(canonical_assignments))
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
      WHERE pending.generation_id = requested_generation_id AND NOT (pending.contact_id = ANY(prelocked_contacts)))
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
      WHERE pending.generation_id = requested_generation_id GROUP BY pending.contact_id HAVING count(*) <> 1) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact confirmation inventory changed or has multiple revisions';
  END IF;
  SELECT array_agg(value::uuid) INTO source_ids
    FROM jsonb_array_elements_text(read_plan->'known_source_plan'->'member_target_ids');
  PERFORM 1 FROM app_data.promotion_targets target
    WHERE target.promotion_target_id = ANY(source_ids) AND target.workspace_id = trusted_workspace_id
      AND target.target_type = read_plan->'known_source_plan'->>'target_type' AND target.status = 'active'
    ORDER BY target.created_at, target.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact confirmation targets are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_assignments assignment_row
    WHERE assignment_row.promotion_target_id = ANY(source_ids) AND assignment_row.app_user_id = trusted_app_user_id
      AND assignment_row.ended_at IS NULL ORDER BY assignment_row.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact confirmation assignments are unavailable';
  END IF;
  read_plan := app_private.read_personal_merge_unassigned_contact_plan_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_generation_id);
  checked_at := clock_timestamp();
  IF EXISTS (SELECT 1 FROM unnest(source_ids) member(target_id)
    WHERE app_data.promotion_target_review_due_at(member.target_id) IS NULL
      OR app_data.promotion_target_review_due_at(member.target_id) <= checked_at) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact confirmation generation is due';
  END IF;
  IF read_plan->'known_source_plan'->>'fact_fingerprint' IS DISTINCT FROM expected_known_fact_fingerprint
    OR read_plan->>'pending_fingerprint' IS DISTINCT FROM expected_pending_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact confirmation snapshot changed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
    JOIN jsonb_array_elements(canonical_assignments) choice ON (choice.value->>'pending_fact_id')::uuid = pending.pending_fact_id
    JOIN app_data.contacts contact ON contact.contact_id = pending.contact_id
    WHERE pending.generation_id = requested_generation_id AND (
      pending.actor_app_user_id <> trusted_app_user_id OR pending.workspace_id <> trusted_workspace_id
      OR contact.app_user_id <> pending.actor_app_user_id OR contact.workspace_id <> pending.workspace_id
      OR contact.project_id <> pending.project_id OR contact.lifecycle_status <> 'active'
      OR contact.current_revision <> pending.revision_number
      OR NOT ((choice.value->>'source_target_id')::uuid = ANY(source_ids))
      OR EXISTS (SELECT 1 FROM app_data.contact_target_links link
        WHERE link.contact_id = pending.contact_id AND link.promotion_target_id = ANY(source_ids))
      OR EXISTS (SELECT 1 FROM app_data.processed_commands command
        WHERE command.app_user_id = trusted_app_user_id AND command.command_id =
          'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
          || octet_length(pending.contact_id)::text || ':' || pending.contact_id)
    )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact revision, source link or child command conflicts';
  END IF;

  FOR item IN
    SELECT pending.*, (choice.value->>'source_target_id')::uuid AS source_target_id,
      payload.response_level, payload.follow_up_consent, payload.institution_representative_confirmed,
      payload.confirmed_project_entry, original.snapshot
    FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
    JOIN jsonb_array_elements(canonical_assignments) choice ON (choice.value->>'pending_fact_id')::uuid = pending.pending_fact_id
    JOIN app_data.personal_merge_unassigned_contact_facts_v1 payload USING (pending_fact_id)
    JOIN app_data.contact_revisions original ON original.contact_id = pending.contact_id
      AND original.revision_number = pending.revision_number
    WHERE pending.generation_id = requested_generation_id ORDER BY pending.contact_id COLLATE "C"
  LOOP
    command_key := 'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
      || octet_length(item.contact_id)::text || ':' || item.contact_id;
    -- confirmStageZero is the existing wire name of the stored confirmed_project_entry fact.
    SELECT * INTO result_row FROM app_data.apply_contact_revise_v3(
      trusted_app_user_id, command_key, 1, 'contact.revise.v1', 'personal-merge-contact-confirm-v1',
      item.contact_id, item.revision_number, item.snapshot || jsonb_build_object(
        'reason', 'Confirmed pending contact source',
        'targetLinks', coalesce(item.snapshot->'targetLinks', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
          'targetId', item.source_target_id, 'targetType', item.target_type, 'responseLevel', item.response_level,
          'followUpConsent', item.follow_up_consent,
          'institutionRepresentativeConfirmed', item.institution_representative_confirmed,
          'confirmStageZero', item.confirmed_project_entry))));
    IF NOT FOUND OR result_row.result_code IS DISTINCT FROM 'accepted' OR result_row.server_cursor IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact revision was not accepted';
    END IF;
  END LOOP;
  SELECT manifest.fact_fingerprint INTO post_fingerprint
    FROM app_private.personal_target_merge_known_source_manifest_v1(requested_generation_id) manifest;
  IF NOT FOUND OR post_fingerprint IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'confirmed contact manifest is incomplete';
  END IF;
  INSERT INTO app_private.personal_merge_contact_confirmation_requests_v1 (
    actor_app_user_id, request_id, workspace_id, project_id, generation_id,
    known_fact_fingerprint, pending_fingerprint, post_known_fact_fingerprint, confirmed_at_utc
  ) VALUES (trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id,
    requested_generation_id, expected_known_fact_fingerprint, expected_pending_fingerprint, post_fingerprint, clock_timestamp());
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'confirmation request insert count mismatch';
  END IF;
  INSERT INTO app_private.personal_merge_contact_applications_v1 (
    pending_fact_id, actor_app_user_id, request_id, contact_id, from_revision_number,
    to_revision_number, source_target_id, child_command_id
  ) SELECT pending.pending_fact_id, trusted_app_user_id, requested_request_id, pending.contact_id,
    pending.revision_number, pending.revision_number + 1, (choice.value->>'source_target_id')::uuid,
    'personal-merge-contact-confirm-v1:' || requested_request_id::text || ':'
      || octet_length(pending.contact_id)::text || ':' || pending.contact_id
  FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
  JOIN jsonb_array_elements(canonical_assignments) choice ON (choice.value->>'pending_fact_id')::uuid = pending.pending_fact_id
  WHERE pending.generation_id = requested_generation_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count
    OR NOT app_private.personal_merge_contact_confirmation_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'confirmed contact revision applications are incomplete';
  END IF;
  ended_at_value := app_private.end_known_source_personal_target_merge_generation_v1(
    trusted_app_user_id, trusted_workspace_id, trusted_project_id, requested_request_id, requested_generation_id, post_fingerprint);
  IF NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id
      AND receipt.generation_id = requested_generation_id AND receipt.workspace_id = trusted_workspace_id
      AND receipt.project_id = trusted_project_id AND receipt.fact_fingerprint = post_fingerprint
      AND receipt.operation = 'personal_target_known_source_merge_end' AND receipt.reason = 'known_source_split'
      AND receipt.outcome = 'ended' AND receipt.ended_at_utc = ended_at_value)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 member
      WHERE member.generation_id = requested_generation_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'confirmation end receipt is incomplete';
  END IF;
  DELETE FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
    USING app_private.personal_merge_contact_applications_v1 application
    WHERE payload.pending_fact_id = application.pending_fact_id
      AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
    JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING (pending_fact_id)
    WHERE pending.generation_id = requested_generation_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'confirmed contact payload consumption is incomplete';
  END IF;
  RETURN ended_at_value;
END
$function$;

REVOKE ALL ON TABLE app_private.personal_merge_contact_confirmation_requests_v1,
  app_private.personal_merge_contact_applications_v1 FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION app_private.personal_merge_contact_confirmation_proof_v1(uuid,uuid),
  app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)'::regprocedure;
  EXECUTE format('ALTER TABLE app_private.personal_merge_contact_confirmation_requests_v1 OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER TABLE app_private.personal_merge_contact_applications_v1 OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.personal_merge_contact_confirmation_proof_v1(uuid,uuid) OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb) OWNER TO %I', trusted_owner);
END
$owner$;
