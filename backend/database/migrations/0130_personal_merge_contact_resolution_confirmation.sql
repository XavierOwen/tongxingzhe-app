-- Keep every pending history application distinct from the final current choice.
CREATE TABLE app_private.personal_merge_contact_resolution_requests_v1 (
  actor_app_user_id uuid NOT NULL REFERENCES app_data.app_users (app_user_id),
  request_id uuid NOT NULL,
  workspace_id uuid NOT NULL REFERENCES app_data.workspaces (workspace_id),
  project_id uuid NOT NULL REFERENCES app_data.projects (project_id),
  generation_id uuid NOT NULL UNIQUE REFERENCES app_private.personal_target_merge_generations_v1 (generation_id),
  known_fact_fingerprint text NOT NULL CHECK (known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  pending_fingerprint text NOT NULL CHECK (pending_fingerprint ~ '^[0-9a-f]{64}$'),
  resolution_fingerprint text NOT NULL CHECK (resolution_fingerprint ~ '^[0-9a-f]{64}$'),
  post_known_fact_fingerprint text NOT NULL CHECK (post_known_fact_fingerprint ~ '^[0-9a-f]{64}$'),
  confirmed_at_utc timestamptz NOT NULL CHECK (isfinite(confirmed_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id),
  CONSTRAINT pmcr_request_end_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_target_merge_end_events_v1 (actor_app_user_id, request_id)
    DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE app_private.personal_merge_contact_history_applications_v1 (
  pending_fact_id uuid PRIMARY KEY REFERENCES app_private.personal_merge_unassigned_contact_requests_v1 (pending_fact_id),
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  contact_id text NOT NULL,
  original_revision_number integer NOT NULL CHECK (original_revision_number > 0),
  from_revision_number integer NOT NULL CHECK (from_revision_number > 0),
  to_revision_number integer NOT NULL CHECK (to_revision_number = from_revision_number + 1),
  source_target_id uuid NOT NULL,
  child_command_id text NOT NULL CHECK (length(child_command_id) > 0),
  CONSTRAINT pmcr_history_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_contact_resolution_requests_v1 (actor_app_user_id, request_id)
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT pmcr_history_original_fk FOREIGN KEY (contact_id, original_revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  CONSTRAINT pmcr_history_base_fk FOREIGN KEY (contact_id, from_revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  CONSTRAINT pmcr_history_link_fk FOREIGN KEY (contact_id, to_revision_number, source_target_id)
    REFERENCES app_data.contact_target_links (contact_id, revision_number, promotion_target_id),
  CONSTRAINT pmcr_history_original_once UNIQUE (actor_app_user_id, request_id, contact_id, original_revision_number),
  UNIQUE (contact_id, to_revision_number),
  UNIQUE (actor_app_user_id, child_command_id)
);

CREATE TABLE app_private.personal_merge_contact_current_revisions_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  contact_id text NOT NULL,
  original_revision_number integer NOT NULL CHECK (original_revision_number > 0),
  from_revision_number integer NOT NULL CHECK (from_revision_number >= original_revision_number),
  to_revision_number integer NOT NULL CHECK (to_revision_number = from_revision_number + 1),
  child_command_id text NOT NULL CHECK (length(child_command_id) > 0),
  PRIMARY KEY (actor_app_user_id, request_id, contact_id),
  CONSTRAINT pmcr_current_request_fk FOREIGN KEY (actor_app_user_id, request_id)
    REFERENCES app_private.personal_merge_contact_resolution_requests_v1 (actor_app_user_id, request_id)
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT pmcr_current_original_fk FOREIGN KEY (contact_id, original_revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  CONSTRAINT pmcr_current_base_fk FOREIGN KEY (contact_id, from_revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  CONSTRAINT pmcr_current_final_fk FOREIGN KEY (contact_id, to_revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number),
  UNIQUE (actor_app_user_id, child_command_id)
);

CREATE TABLE app_private.personal_merge_contact_current_choices_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  contact_id text NOT NULL,
  source_target_id uuid NOT NULL REFERENCES app_data.promotion_targets (promotion_target_id),
  selected_pending_fact_id uuid REFERENCES app_private.personal_merge_contact_history_applications_v1 (pending_fact_id),
  PRIMARY KEY (actor_app_user_id, request_id, contact_id, source_target_id),
  CONSTRAINT pmcr_choice_current_fk FOREIGN KEY (actor_app_user_id, request_id, contact_id)
    REFERENCES app_private.personal_merge_contact_current_revisions_v1 (actor_app_user_id, request_id, contact_id)
);

CREATE TRIGGER personal_merge_contact_resolution_requests_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_contact_resolution_requests_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER personal_merge_contact_history_applications_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_contact_history_applications_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER personal_merge_contact_current_revisions_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_contact_current_revisions_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();
CREATE TRIGGER personal_merge_contact_current_choices_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_merge_contact_current_choices_v1
FOR EACH ROW EXECUTE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.personal_merge_contact_resolution_revision_proof_v1(
  trusted_app_user_id uuid, requested_child_command_id text, requested_contact_id text,
  requested_original_revision integer, requested_applied_revision integer, expected_target_links jsonb
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  SELECT coalesce((
    SELECT revised.revision_kind = 'corrected' AND revised.revised_by_app_user_id = trusted_app_user_id
      AND original.snapshot->'questionnaireVersionId' = to_jsonb(contact.questionnaire_version_id)
      AND revised.snapshot->'questionnaireVersionId' = to_jsonb(contact.questionnaire_version_id)
      AND (revised.snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
        = (original.snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
      AND revised.snapshot->'revisionKind' = '"corrected"'::jsonb
      AND (revised.snapshot->>'revisedAtUtc')::timestamptz = revised.revised_at_utc
      AND (revised.snapshot->>'firstSubmittedAtUtc')::timestamptz = contact.first_submitted_at_utc
      AND revised.snapshot->'targetLinks' = expected_target_links
      AND (SELECT coalesce(jsonb_agg(to_jsonb(answer) - 'revision_number' ORDER BY answer.question_id), '[]'::jsonb)
        FROM app_data.contact_answers answer WHERE answer.contact_id = contact.contact_id
          AND answer.revision_number = requested_applied_revision)
        = (SELECT coalesce(jsonb_agg(to_jsonb(answer) - 'revision_number' ORDER BY answer.question_id), '[]'::jsonb)
          FROM app_data.contact_answers answer WHERE answer.contact_id = contact.contact_id
            AND answer.revision_number = requested_original_revision)
      AND (SELECT to_jsonb(provenance) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc']
        FROM app_data.contact_location_provenance provenance WHERE provenance.contact_id = contact.contact_id
          AND provenance.revision_number = requested_applied_revision)
        = (SELECT to_jsonb(provenance) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc']
          FROM app_data.contact_location_provenance provenance WHERE provenance.contact_id = contact.contact_id
            AND provenance.revision_number = requested_original_revision)
      AND (SELECT count(*) FROM app_data.contact_target_links installed
        WHERE installed.contact_id = contact.contact_id AND installed.revision_number = requested_applied_revision)
        = jsonb_array_length(expected_target_links)
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(expected_target_links) expected
        WHERE NOT EXISTS (
          SELECT 1 FROM app_data.contact_target_links installed
          JOIN app_data.promotion_targets target ON target.promotion_target_id = installed.promotion_target_id
          WHERE installed.contact_id = contact.contact_id AND installed.revision_number = requested_applied_revision
            AND installed.promotion_target_id = (expected->>'targetId')::uuid
            AND target.target_type = expected->>'targetType'
            AND installed.response_level IS NOT DISTINCT FROM (expected->>'responseLevel')::integer
            AND installed.follow_up_consent = expected->>'followUpConsent'
            AND installed.institution_representative_confirmed = (expected->>'institutionRepresentativeConfirmed')::boolean
            AND installed.confirmed_project_entry = (expected->>'confirmStageZero')::boolean))
      AND EXISTS (
        SELECT 1 FROM app_data.processed_commands command
        JOIN app_data.change_feed feed ON feed.cursor_token = command.server_cursor
        WHERE command.app_user_id = trusted_app_user_id AND command.command_id = requested_child_command_id
          AND command.result_code = 'accepted' AND command.command_type = 'contact.revise.v1'
          AND command.protocol_version = 1 AND command.device_id = 'personal-merge-contact-resolve-v1'
          AND command.aggregate_id = contact.contact_id AND feed.aggregate_id = contact.contact_id
          AND feed.app_user_id = trusted_app_user_id AND feed.workspace_id = contact.workspace_id
          AND feed.project_id = contact.project_id AND feed.revision_number = requested_applied_revision
          AND feed.change_type = 'contact.revised' AND feed.change_payload = revised.snapshot)
      AND EXISTS (SELECT 1 FROM app_data.contact_audit_events audit
        WHERE audit.app_user_id = trusted_app_user_id AND audit.command_id = requested_child_command_id
          AND audit.contact_id = contact.contact_id AND audit.revision_number = requested_applied_revision
          AND audit.event_type = 'contact.revised')
      AND EXISTS (SELECT 1 FROM app_data.warehouse_outbox warehouse
        WHERE warehouse.contact_id = contact.contact_id AND warehouse.project_id = contact.project_id
          AND warehouse.revision_number = requested_applied_revision AND warehouse.event_type = 'contact.revised'
          AND NOT warehouse.analytics_payload ?| ARRAY['answers','_questionnaireAnswersV2','targetLinks','target_links','location','locationSource','location_source']
          AND warehouse.analytics_payload->'target_link_facts' = (
            SELECT coalesce(jsonb_agg(jsonb_build_object('target_type', target.target_type,
              'response_level', installed.response_level, 'follow_up_consent', installed.follow_up_consent)
              ORDER BY installed.promotion_target_id), '[]'::jsonb)
            FROM app_data.contact_target_links installed JOIN app_data.promotion_targets target
              ON target.promotion_target_id = installed.promotion_target_id
            WHERE installed.contact_id = contact.contact_id AND installed.revision_number = requested_applied_revision))
    FROM app_data.contacts contact
    JOIN app_data.contact_revisions original ON original.contact_id = contact.contact_id
      AND original.revision_number = requested_original_revision
    JOIN app_data.contact_revisions revised ON revised.contact_id = contact.contact_id
      AND revised.revision_number = requested_applied_revision
    WHERE contact.contact_id = requested_contact_id AND contact.app_user_id = trusted_app_user_id
      AND contact.lifecycle_status = 'active'
  ), false);
$function$;

CREATE FUNCTION app_private.personal_merge_contact_resolution_proof_v1(
  trusted_app_user_id uuid, requested_request_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  request_row app_private.personal_merge_contact_resolution_requests_v1%ROWTYPE;
  item record;
  current_item record;
  source_ids uuid[];
  expected_links jsonb;
  chosen_links jsonb;
  expected_slots jsonb;
  actual_slots jsonb;
  complete_receipt boolean;
  history_count bigint;
BEGIN
  SELECT * INTO request_row FROM app_private.personal_merge_contact_resolution_requests_v1 request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT array_agg(member.promotion_target_id ORDER BY member.promotion_target_id) INTO source_ids
    FROM app_private.personal_target_merge_generation_members_v1 member WHERE member.generation_id = request_row.generation_id;
  SELECT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 ended
    WHERE ended.actor_app_user_id = trusted_app_user_id AND ended.request_id = requested_request_id
      AND ended.workspace_id = request_row.workspace_id AND ended.project_id = request_row.project_id
      AND ended.generation_id = request_row.generation_id AND ended.operation = 'personal_target_known_source_merge_end'
      AND ended.reason = 'known_source_split' AND ended.outcome = 'ended'
      AND ended.fact_fingerprint = request_row.post_known_fact_fingerprint) INTO complete_receipt;
  SELECT count(*) INTO history_count FROM app_private.personal_merge_contact_history_applications_v1 application
    WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  IF cardinality(source_ids) IS DISTINCT FROM 2 OR history_count = 0
    OR history_count <> (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
      WHERE pending.generation_id = request_row.generation_id)
    OR (SELECT manifest.fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(request_row.generation_id) manifest)
      IS DISTINCT FROM request_row.post_known_fact_fingerprint
    OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 current_revision
      WHERE current_revision.actor_app_user_id = trusted_app_user_id AND current_revision.request_id = requested_request_id)
      <> (SELECT count(DISTINCT pending.contact_id) FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
        WHERE pending.generation_id = request_row.generation_id)
  THEN RETURN false; END IF;

  FOR item IN
    SELECT application.*, pending.generation_id, pending.actor_app_user_id AS pending_actor,
      pending.workspace_id, pending.project_id, pending.contact_id AS pending_contact,
      pending.revision_number AS pending_revision, pending.target_type,
      payload.pending_fact_id AS payload_id, payload.response_level, payload.follow_up_consent,
      payload.institution_representative_confirmed, payload.confirmed_project_entry,
      original.snapshot, link.merge_generation_id, link.response_level AS installed_response,
      link.follow_up_consent AS installed_consent, link.institution_representative_confirmed AS installed_representative,
      link.confirmed_project_entry AS installed_entry, contact.app_user_id AS contact_actor,
      contact.workspace_id AS contact_workspace, contact.project_id AS contact_project
    FROM app_private.personal_merge_contact_history_applications_v1 application
    LEFT JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING (pending_fact_id)
    LEFT JOIN app_data.personal_merge_unassigned_contact_facts_v1 payload USING (pending_fact_id)
    LEFT JOIN app_data.contacts contact ON contact.contact_id = application.contact_id
    LEFT JOIN app_data.contact_revisions original ON original.contact_id = application.contact_id
      AND original.revision_number = application.original_revision_number
    LEFT JOIN app_data.contact_target_links link ON link.contact_id = application.contact_id
      AND link.revision_number = application.to_revision_number AND link.promotion_target_id = application.source_target_id
    WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
  LOOP
    IF NOT coalesce(item.generation_id = request_row.generation_id AND item.pending_actor = trusted_app_user_id
      AND item.workspace_id = request_row.workspace_id AND item.pending_contact = item.contact_id
      AND item.pending_revision = item.original_revision_number
      AND item.contact_actor = trusted_app_user_id AND item.contact_workspace = item.workspace_id
      AND item.contact_project = item.project_id AND item.source_target_id = ANY(source_ids)
      AND item.merge_generation_id = request_row.generation_id
      AND item.child_command_id = 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':pending:' || item.pending_fact_id::text
      AND ((item.payload_id IS NOT NULL
        AND item.installed_response IS NOT DISTINCT FROM item.response_level
        AND item.installed_consent = item.follow_up_consent
        AND item.installed_representative = item.institution_representative_confirmed
        AND item.installed_entry = item.confirmed_project_entry)
        OR (item.payload_id IS NULL AND complete_receipt)), false)
    THEN RETURN false; END IF;
    IF EXISTS (SELECT 1 FROM app_data.contact_target_links prior WHERE prior.contact_id = item.contact_id
      AND prior.revision_number = item.original_revision_number AND prior.promotion_target_id = ANY(source_ids))
    THEN RETURN false; END IF;
    expected_links := coalesce(item.snapshot->'targetLinks', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'targetId', item.source_target_id, 'targetType', item.target_type, 'responseLevel', item.installed_response,
      'followUpConsent', item.installed_consent, 'institutionRepresentativeConfirmed', item.installed_representative,
      'confirmStageZero', item.installed_entry));
    IF NOT app_private.personal_merge_contact_resolution_revision_proof_v1(trusted_app_user_id,
      item.child_command_id, item.contact_id, item.original_revision_number, item.to_revision_number, expected_links)
    THEN RETURN false; END IF;
  END LOOP;

  FOR current_item IN
    SELECT current_revision.*, contact.current_revision, original.snapshot
    FROM app_private.personal_merge_contact_current_revisions_v1 current_revision
    JOIN app_data.contacts contact ON contact.contact_id = current_revision.contact_id
    JOIN app_data.contact_revisions original ON original.contact_id = current_revision.contact_id
      AND original.revision_number = current_revision.original_revision_number
    WHERE current_revision.actor_app_user_id = trusted_app_user_id AND current_revision.request_id = requested_request_id
  LOOP
    SELECT count(*) INTO history_count FROM app_private.personal_merge_contact_history_applications_v1 application
      WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
        AND application.contact_id = current_item.contact_id;
    IF history_count = 0 OR current_item.current_revision <> current_item.to_revision_number
      OR current_item.from_revision_number <> current_item.original_revision_number + history_count
      OR current_item.child_command_id <> 'personal-merge-contact-resolve-v1:' || requested_request_id::text
        || ':current:' || octet_length(current_item.contact_id)::text || ':' || current_item.contact_id
      OR EXISTS (
        SELECT 1 FROM (
          SELECT application.*, row_number() OVER (ORDER BY original_revision_number, pending_fact_id) AS application_order
          FROM app_private.personal_merge_contact_history_applications_v1 application
          WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
            AND application.contact_id = current_item.contact_id
        ) ordered WHERE ordered.original_revision_number > current_item.original_revision_number
          OR ordered.from_revision_number <> current_item.original_revision_number + ordered.application_order - 1)
    THEN RETURN false; END IF;
    SELECT coalesce(jsonb_agg(source_id ORDER BY source_id), '[]'::jsonb) INTO expected_slots FROM (
      SELECT application.source_target_id AS source_id FROM app_private.personal_merge_contact_history_applications_v1 application
      WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
        AND application.contact_id = current_item.contact_id
      UNION
      SELECT prior.promotion_target_id FROM app_data.contact_target_links prior
      WHERE prior.contact_id = current_item.contact_id AND prior.revision_number = current_item.original_revision_number
        AND prior.promotion_target_id = ANY(source_ids)
    ) slots;
    SELECT coalesce(jsonb_agg(choice.source_target_id ORDER BY choice.source_target_id), '[]'::jsonb) INTO actual_slots
      FROM app_private.personal_merge_contact_current_choices_v1 choice
      WHERE choice.actor_app_user_id = trusted_app_user_id AND choice.request_id = requested_request_id
        AND choice.contact_id = current_item.contact_id;
    IF actual_slots IS DISTINCT FROM expected_slots OR EXISTS (
      SELECT 1 FROM app_private.personal_merge_contact_current_choices_v1 choice
      LEFT JOIN app_private.personal_merge_contact_history_applications_v1 application
        ON application.pending_fact_id = choice.selected_pending_fact_id
      WHERE choice.actor_app_user_id = trusted_app_user_id AND choice.request_id = requested_request_id
        AND choice.contact_id = current_item.contact_id AND (
          (choice.selected_pending_fact_id IS NULL AND NOT EXISTS (
            SELECT 1 FROM app_data.contact_target_links prior WHERE prior.contact_id = current_item.contact_id
              AND prior.revision_number = current_item.original_revision_number AND prior.promotion_target_id = choice.source_target_id))
          OR (choice.selected_pending_fact_id IS NOT NULL AND NOT coalesce(
            application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id
            AND application.contact_id = choice.contact_id AND application.source_target_id = choice.source_target_id, false))))
    THEN RETURN false; END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('targetId', choice.source_target_id, 'targetType', target.target_type,
      'responseLevel', selected.response_level, 'followUpConsent', selected.follow_up_consent,
      'institutionRepresentativeConfirmed', selected.institution_representative_confirmed,
      'confirmStageZero', selected.confirmed_project_entry) ORDER BY choice.source_target_id), '[]'::jsonb) INTO chosen_links
    FROM app_private.personal_merge_contact_current_choices_v1 choice
    LEFT JOIN app_private.personal_merge_contact_history_applications_v1 application
      ON application.pending_fact_id = choice.selected_pending_fact_id
    JOIN app_data.contact_target_links selected ON selected.contact_id = choice.contact_id
      AND selected.revision_number = CASE WHEN choice.selected_pending_fact_id IS NULL
        THEN current_item.original_revision_number ELSE application.to_revision_number END
      AND selected.promotion_target_id = choice.source_target_id
    JOIN app_data.promotion_targets target ON target.promotion_target_id = choice.source_target_id
    WHERE choice.actor_app_user_id = trusted_app_user_id AND choice.request_id = requested_request_id
      AND choice.contact_id = current_item.contact_id;
    SELECT coalesce(jsonb_agg(value ORDER BY ordinality), '[]'::jsonb) INTO expected_links
      FROM jsonb_array_elements(coalesce(current_item.snapshot->'targetLinks', '[]'::jsonb)) WITH ORDINALITY
      WHERE NOT ((value->>'targetId')::uuid = ANY(source_ids));
    expected_links := expected_links || chosen_links;
    IF NOT app_private.personal_merge_contact_resolution_revision_proof_v1(trusted_app_user_id,
      current_item.child_command_id, current_item.contact_id, current_item.original_revision_number,
      current_item.to_revision_number, expected_links)
      OR EXISTS (SELECT 1 FROM app_data.contact_target_links installed WHERE installed.contact_id = current_item.contact_id
        AND installed.revision_number = current_item.to_revision_number AND installed.promotion_target_id = ANY(source_ids)
        AND installed.merge_generation_id IS DISTINCT FROM request_row.generation_id)
    THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END
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
  ) AND NOT (
    EXISTS (
      SELECT 1 FROM app_private.personal_merge_contact_confirmation_requests_v1 request
      WHERE request.actor_app_user_id = NEW.actor_app_user_id AND request.request_id = NEW.request_id
        AND request.workspace_id = NEW.workspace_id AND request.project_id = NEW.project_id
        AND request.generation_id = NEW.generation_id AND request.post_known_fact_fingerprint = NEW.fact_fingerprint
        AND NEW.operation = 'personal_target_known_source_merge_end' AND NEW.outcome = 'ended'
        AND app_private.personal_merge_contact_confirmation_proof_v1(request.actor_app_user_id, request.request_id))
    OR EXISTS (
      SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1 request
      WHERE request.actor_app_user_id = NEW.actor_app_user_id AND request.request_id = NEW.request_id
        AND request.workspace_id = NEW.workspace_id AND request.project_id = NEW.project_id
        AND request.generation_id = NEW.generation_id AND request.post_known_fact_fingerprint = NEW.fact_fingerprint
        AND NEW.operation = 'personal_target_known_source_merge_end' AND NEW.outcome = 'ended'
        AND app_private.personal_merge_contact_resolution_proof_v1(request.actor_app_user_id, request.request_id))
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
    JOIN app_private.personal_merge_contact_confirmation_requests_v1 request USING (actor_app_user_id, request_id)
    JOIN app_private.personal_target_merge_end_events_v1 receipt
      ON receipt.actor_app_user_id = request.actor_app_user_id AND receipt.request_id = request.request_id
      AND receipt.generation_id = request.generation_id AND receipt.workspace_id = request.workspace_id
      AND receipt.project_id = request.project_id AND receipt.fact_fingerprint = request.post_known_fact_fingerprint
    WHERE application.pending_fact_id = OLD.pending_fact_id AND receipt.reason = 'known_source_split'
      AND receipt.operation = 'personal_target_known_source_merge_end' AND receipt.outcome = 'ended'
      AND app_private.personal_merge_contact_confirmation_proof_v1(request.actor_app_user_id, request.request_id)
  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_contact_history_applications_v1 application
    JOIN app_private.personal_merge_contact_resolution_requests_v1 request USING (actor_app_user_id, request_id)
    JOIN app_private.personal_target_merge_end_events_v1 receipt
      ON receipt.actor_app_user_id = request.actor_app_user_id AND receipt.request_id = request.request_id
      AND receipt.generation_id = request.generation_id AND receipt.workspace_id = request.workspace_id
      AND receipt.project_id = request.project_id AND receipt.fact_fingerprint = request.post_known_fact_fingerprint
    JOIN app_data.contact_target_links installed ON installed.contact_id = application.contact_id
      AND installed.revision_number = application.to_revision_number
      AND installed.promotion_target_id = application.source_target_id
    WHERE application.pending_fact_id = OLD.pending_fact_id AND receipt.reason = 'known_source_split'
      AND receipt.operation = 'personal_target_known_source_merge_end' AND receipt.outcome = 'ended'
      -- End proves the whole batch; each deletion must still match its actual applied payload.
      AND installed.merge_generation_id = request.generation_id
      AND installed.response_level IS NOT DISTINCT FROM OLD.response_level
      AND installed.follow_up_consent = OLD.follow_up_consent
      AND installed.institution_representative_confirmed = OLD.institution_representative_confirmed
      AND installed.confirmed_project_entry = OLD.confirmed_project_entry
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact deletion requires expiry or applied confirmation receipt';
  END IF;
  RETURN OLD;
END
$function$;

CREATE FUNCTION app_private.confirm_personal_merge_contact_resolutions_v1(
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
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  assignment jsonb;
  choice jsonb;
  canonical_assignments jsonb;
  canonical_choices jsonb;
  replay_assignments jsonb;
  replay_choices jsonb;
  request_row app_private.personal_merge_contact_resolution_requests_v1%ROWTYPE;
  read_plan jsonb;
  source_ids uuid[];
  prelocked_pending uuid[];
  prelocked_contacts text[];
  child_commands text[];
  contact_key text;
  command_key text;
  current_item jsonb;
  item record;
  result_row record;
  original_snapshot jsonb;
  current_links jsonb;
  chosen_links jsonb;
  base_revision integer;
  original_revision integer;
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
    OR expected_resolution_fingerprint IS NULL OR expected_resolution_fingerprint !~ '^[0-9a-f]{64}$'
    OR requested_assignments IS NULL OR jsonb_typeof(requested_assignments) <> 'array'
    OR requested_current_choices IS NULL OR jsonb_typeof(requested_current_choices) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact resolution confirmation request';
  END IF;
  IF jsonb_array_length(requested_assignments) = 0 OR jsonb_array_length(requested_current_choices) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'pending contact resolution requires assignments and current choices';
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
  FOR choice IN SELECT value FROM jsonb_array_elements(requested_current_choices) LOOP
    IF jsonb_typeof(choice) <> 'object' THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact current choice';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(choice)) <> 4
      OR NOT choice ?& ARRAY['contact_id','source_target_id','candidate_kind','pending_fact_id']
      OR jsonb_typeof(choice->'contact_id') <> 'string' OR length(btrim(choice->>'contact_id')) = 0
      OR jsonb_typeof(choice->'source_target_id') <> 'string'
      OR choice->>'source_target_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      OR jsonb_typeof(choice->'candidate_kind') <> 'string' OR choice->>'candidate_kind' NOT IN ('current','pending')
      OR (choice->>'candidate_kind' = 'current' AND jsonb_typeof(choice->'pending_fact_id') <> 'null')
      OR (choice->>'candidate_kind' = 'pending' AND (jsonb_typeof(choice->'pending_fact_id') <> 'string'
        OR choice->>'pending_fact_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid pending contact current choice keys, kind or UUIDs';
    END IF;
  END LOOP;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', (value->>'pending_fact_id')::uuid,
    'source_target_id', (value->>'source_target_id')::uuid) ORDER BY (value->>'pending_fact_id')::uuid), count(*)
    INTO canonical_assignments, expected_count FROM jsonb_array_elements(requested_assignments);
  SELECT jsonb_agg(jsonb_build_object('contact_id', value->>'contact_id',
    'source_target_id', (value->>'source_target_id')::uuid, 'candidate_kind', value->>'candidate_kind',
    'pending_fact_id', (value->>'pending_fact_id')::uuid)
    ORDER BY value->>'contact_id' COLLATE "C", (value->>'source_target_id')::uuid)
    INTO canonical_choices FROM jsonb_array_elements(requested_current_choices);
  IF (SELECT count(DISTINCT (value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(canonical_assignments)) <> expected_count
    OR (SELECT count(*) FROM (SELECT DISTINCT value->>'contact_id', (value->>'source_target_id')::uuid
      FROM jsonb_array_elements(canonical_choices)) unique_choices) <> jsonb_array_length(canonical_choices) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'duplicate pending contact assignment or current choice';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));
  SELECT * INTO request_row FROM app_private.personal_merge_contact_resolution_requests_v1 request
    WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id;
  IF FOUND THEN
    IF request_row.workspace_id IS DISTINCT FROM trusted_workspace_id OR request_row.project_id IS DISTINCT FROM trusted_project_id
      OR request_row.generation_id IS DISTINCT FROM requested_generation_id
      OR request_row.known_fact_fingerprint IS DISTINCT FROM expected_known_fact_fingerprint
      OR request_row.pending_fingerprint IS DISTINCT FROM expected_pending_fingerprint
      OR request_row.resolution_fingerprint IS DISTINCT FROM expected_resolution_fingerprint THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact resolution request changed';
    END IF;
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id', application.pending_fact_id,
      'source_target_id', application.source_target_id) ORDER BY application.pending_fact_id) INTO replay_assignments
      FROM app_private.personal_merge_contact_history_applications_v1 application
      WHERE application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
    SELECT jsonb_agg(jsonb_build_object('contact_id', selected.contact_id, 'source_target_id', selected.source_target_id,
      'candidate_kind', CASE WHEN selected.selected_pending_fact_id IS NULL THEN 'current' ELSE 'pending' END,
      'pending_fact_id', selected.selected_pending_fact_id) ORDER BY selected.contact_id COLLATE "C", selected.source_target_id)
      INTO replay_choices FROM app_private.personal_merge_contact_current_choices_v1 selected
      WHERE selected.actor_app_user_id = trusted_app_user_id AND selected.request_id = requested_request_id;
    IF replay_assignments IS DISTINCT FROM canonical_assignments OR replay_choices IS DISTINCT FROM canonical_choices THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact resolution assignments or current choices changed';
    END IF;
    RETURN app_private.end_known_source_personal_target_merge_generation_v1(trusted_app_user_id, trusted_workspace_id,
      trusted_project_id, requested_request_id, requested_generation_id, request_row.post_known_fact_fingerprint);
  END IF;
  IF EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id)
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_contact_confirmation_requests_v1 request
      WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'resolution request belongs to another end operation';
  END IF;

  SELECT coalesce(array_agg(pending_fact_id ORDER BY pending_fact_id), ARRAY[]::uuid[]) INTO prelocked_pending
    FROM app_private.personal_merge_unassigned_contact_requests_v1 pending WHERE pending.generation_id = requested_generation_id;
  SELECT coalesce(array_agg(contact_id ORDER BY contact_id COLLATE "C"), ARRAY[]::text[]) INTO prelocked_contacts
    FROM (SELECT DISTINCT pending.contact_id FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
      WHERE pending.generation_id = requested_generation_id) contacts;
  SELECT array_agg(command_id ORDER BY command_id COLLATE "C") INTO child_commands FROM (
    SELECT 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':pending:' || pending_id::text AS command_id
      FROM unnest(prelocked_pending) pending_ids(pending_id)
    UNION ALL
    SELECT 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':current:'
      || octet_length(contact_id)::text || ':' || contact_id FROM unnest(prelocked_contacts) contacts(contact_id)
  ) commands;
  IF child_commands IS NOT NULL THEN
    FOREACH command_key IN ARRAY child_commands LOOP
      PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || command_key, 0));
    END LOOP;
  END IF;
  FOREACH contact_key IN ARRAY prelocked_contacts LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('contact:' || contact_key, 0));
    PERFORM 1 FROM app_data.contacts contact WHERE contact.contact_id = contact_key FOR UPDATE;
  END LOOP;
  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();
  read_plan := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, canonical_assignments);
  IF read_plan->>'resolution_fingerprint' IS DISTINCT FROM expected_resolution_fingerprint
    OR (SELECT coalesce(array_agg(pending_fact_id ORDER BY pending_fact_id), ARRAY[]::uuid[])
      FROM app_private.personal_merge_unassigned_contact_requests_v1 pending WHERE pending.generation_id = requested_generation_id)
      IS DISTINCT FROM prelocked_pending THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact resolution inventory or current revision changed';
  END IF;
  SELECT array_agg(value::uuid) INTO source_ids FROM jsonb_array_elements_text(read_plan->'known_source_plan'->'member_target_ids');
  PERFORM 1 FROM app_data.promotion_targets target WHERE target.promotion_target_id = ANY(source_ids)
    AND target.workspace_id = trusted_workspace_id AND target.target_type = read_plan->'known_source_plan'->>'target_type'
    AND target.status = 'active' ORDER BY target.created_at, target.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact resolution targets are unavailable';
  END IF;
  PERFORM 1 FROM app_data.promotion_target_assignments assigned WHERE assigned.promotion_target_id = ANY(source_ids)
    AND assigned.app_user_id = trusted_app_user_id AND assigned.ended_at IS NULL ORDER BY assigned.promotion_target_id FOR UPDATE;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 2 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact resolution assignments are unavailable';
  END IF;
  read_plan := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, canonical_assignments);
  checked_at := clock_timestamp();
  IF EXISTS (SELECT 1 FROM unnest(source_ids) member(target_id)
    WHERE app_data.promotion_target_review_due_at(member.target_id) IS NULL
      OR app_data.promotion_target_review_due_at(member.target_id) <= checked_at) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'pending contact resolution generation is due';
  END IF;
  IF read_plan->>'resolution_fingerprint' IS DISTINCT FROM expected_resolution_fingerprint THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact resolution snapshot changed';
  END IF;
  IF (SELECT jsonb_agg(jsonb_build_array(value->>'contact_id', (value->>'source_target_id')::uuid)
      ORDER BY value->>'contact_id' COLLATE "C", (value->>'source_target_id')::uuid)
      FROM jsonb_array_elements(read_plan->'source_slots')) IS DISTINCT FROM
    (SELECT jsonb_agg(jsonb_build_array(value->>'contact_id', (value->>'source_target_id')::uuid)
      ORDER BY value->>'contact_id' COLLATE "C", (value->>'source_target_id')::uuid)
      FROM jsonb_array_elements(canonical_choices))
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(canonical_choices) selected
      JOIN jsonb_array_elements(read_plan->'source_slots') slot ON slot->>'contact_id' = selected->>'contact_id'
        AND (slot->>'source_target_id')::uuid = (selected->>'source_target_id')::uuid
      WHERE (selected->>'candidate_kind' = 'current' AND NOT (slot->>'has_current_link')::boolean)
        OR (selected->>'candidate_kind' = 'pending' AND NOT slot->'pending_fact_ids' ? (selected->>'pending_fact_id')))
    OR EXISTS (SELECT 1 FROM app_data.processed_commands command WHERE command.app_user_id = trusted_app_user_id
      AND command.command_id = ANY(child_commands)) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact current choices or child commands conflict';
  END IF;
  IF EXISTS (
    SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
    JOIN app_data.contacts contact ON contact.contact_id = pending.contact_id
    JOIN app_data.contact_revisions original ON original.contact_id = pending.contact_id AND original.revision_number = pending.revision_number
    WHERE pending.generation_id = requested_generation_id AND (
      original.snapshot->'questionnaireVersionId' IS DISTINCT FROM to_jsonb(contact.questionnaire_version_id)
      OR EXISTS (SELECT 1 FROM app_data.contact_target_links prior WHERE prior.contact_id = pending.contact_id
        AND prior.revision_number = pending.revision_number AND prior.promotion_target_id = ANY(source_ids))))
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements(read_plan->'contacts') planned
      JOIN app_data.contacts contact ON contact.contact_id = planned->>'contact_id'
      JOIN app_data.contact_revisions original ON original.contact_id = contact.contact_id
        AND original.revision_number = (planned->>'current_revision_number')::integer
      WHERE original.snapshot->'questionnaireVersionId' IS DISTINCT FROM to_jsonb(contact.questionnaire_version_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact historical snapshot or questionnaire version is inconsistent';
  END IF;

  FOR item IN
    SELECT pending.*, (selected.value->>'source_target_id')::uuid AS source_target_id, payload.response_level,
      payload.follow_up_consent, payload.institution_representative_confirmed, payload.confirmed_project_entry, original.snapshot
    FROM app_private.personal_merge_unassigned_contact_requests_v1 pending
    JOIN jsonb_array_elements(canonical_assignments) selected ON (selected.value->>'pending_fact_id')::uuid = pending.pending_fact_id
    JOIN app_data.personal_merge_unassigned_contact_facts_v1 payload USING (pending_fact_id)
    JOIN app_data.contact_revisions original ON original.contact_id = pending.contact_id AND original.revision_number = pending.revision_number
    WHERE pending.generation_id = requested_generation_id ORDER BY pending.contact_id COLLATE "C", pending.revision_number, pending.pending_fact_id
  LOOP
    SELECT contact.current_revision INTO STRICT base_revision FROM app_data.contacts contact WHERE contact.contact_id = item.contact_id;
    command_key := 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':pending:' || item.pending_fact_id::text;
    SELECT * INTO result_row FROM app_data.apply_contact_revise_v3(trusted_app_user_id, command_key, 1,
      'contact.revise.v1', 'personal-merge-contact-resolve-v1', item.contact_id, base_revision,
      item.snapshot || jsonb_build_object('reason', 'Confirmed historical pending contact source',
        'targetLinks', coalesce(item.snapshot->'targetLinks', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
          'targetId', item.source_target_id, 'targetType', item.target_type, 'responseLevel', item.response_level,
          'followUpConsent', item.follow_up_consent, 'institutionRepresentativeConfirmed', item.institution_representative_confirmed,
          'confirmStageZero', item.confirmed_project_entry))));
    IF NOT FOUND OR result_row.result_code IS DISTINCT FROM 'accepted' OR result_row.server_cursor IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact historical revision was not accepted';
    END IF;
    INSERT INTO app_private.personal_merge_contact_history_applications_v1 (
      pending_fact_id, actor_app_user_id, request_id, contact_id, original_revision_number,
      from_revision_number, to_revision_number, source_target_id, child_command_id
    ) VALUES (item.pending_fact_id, trusted_app_user_id, requested_request_id, item.contact_id,
      item.revision_number, base_revision, base_revision + 1, item.source_target_id, command_key);
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact historical application count mismatch';
    END IF;
  END LOOP;
  FOR current_item IN SELECT value FROM jsonb_array_elements(read_plan->'contacts') LOOP
    contact_key := current_item->>'contact_id';
    original_revision := (current_item->>'current_revision_number')::integer;
    SELECT original.snapshot INTO STRICT original_snapshot FROM app_data.contact_revisions original
      WHERE original.contact_id = contact_key AND original.revision_number = original_revision;
    SELECT coalesce(jsonb_agg(value ORDER BY ordinality), '[]'::jsonb) INTO current_links
      FROM jsonb_array_elements(coalesce(original_snapshot->'targetLinks', '[]'::jsonb)) WITH ORDINALITY
      WHERE NOT ((value->>'targetId')::uuid = ANY(source_ids));
    SELECT coalesce(jsonb_agg(jsonb_build_object('targetId', (selected.value->>'source_target_id')::uuid,
      'targetType', target.target_type, 'responseLevel', link.response_level, 'followUpConsent', link.follow_up_consent,
      'institutionRepresentativeConfirmed', link.institution_representative_confirmed,
      'confirmStageZero', link.confirmed_project_entry) ORDER BY (selected.value->>'source_target_id')::uuid), '[]'::jsonb)
      INTO chosen_links FROM jsonb_array_elements(canonical_choices) selected
    LEFT JOIN app_private.personal_merge_contact_history_applications_v1 application
      ON application.pending_fact_id = (selected.value->>'pending_fact_id')::uuid
    JOIN app_data.contact_target_links link ON link.contact_id = contact_key
      AND link.revision_number = CASE WHEN selected.value->>'candidate_kind' = 'current'
        THEN original_revision ELSE application.to_revision_number END
      AND link.promotion_target_id = (selected.value->>'source_target_id')::uuid
    JOIN app_data.promotion_targets target ON target.promotion_target_id = link.promotion_target_id
    WHERE selected.value->>'contact_id' = contact_key;
    SELECT contact.current_revision INTO STRICT base_revision FROM app_data.contacts contact WHERE contact.contact_id = contact_key;
    command_key := 'personal-merge-contact-resolve-v1:' || requested_request_id::text || ':current:'
      || octet_length(contact_key)::text || ':' || contact_key;
    SELECT * INTO result_row FROM app_data.apply_contact_revise_v3(trusted_app_user_id, command_key, 1,
      'contact.revise.v1', 'personal-merge-contact-resolve-v1', contact_key, base_revision,
      original_snapshot || jsonb_build_object('reason', 'Confirmed pending contact current projection', 'targetLinks', current_links || chosen_links));
    IF NOT FOUND OR result_row.result_code IS DISTINCT FROM 'accepted' OR result_row.server_cursor IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'pending contact current revision was not accepted';
    END IF;
    INSERT INTO app_private.personal_merge_contact_current_revisions_v1 (
      actor_app_user_id, request_id, contact_id, original_revision_number, from_revision_number, to_revision_number, child_command_id
    ) VALUES (trusted_app_user_id, requested_request_id, contact_key, original_revision, base_revision, base_revision + 1, command_key);
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    IF affected_count <> 1 THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact current revision count mismatch';
    END IF;
  END LOOP;
  INSERT INTO app_private.personal_merge_contact_current_choices_v1 (
    actor_app_user_id, request_id, contact_id, source_target_id, selected_pending_fact_id
  ) SELECT trusted_app_user_id, requested_request_id, value->>'contact_id', (value->>'source_target_id')::uuid,
    (value->>'pending_fact_id')::uuid FROM jsonb_array_elements(canonical_choices);
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> jsonb_array_length(canonical_choices) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact current choice count mismatch';
  END IF;
  SELECT manifest.fact_fingerprint INTO post_fingerprint
    FROM app_private.personal_target_merge_known_source_manifest_v1(requested_generation_id) manifest;
  IF NOT FOUND OR post_fingerprint IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact resolution manifest is incomplete';
  END IF;
  -- Child request FKs are deferred until the final manifest can enter the immutable receipt.
  INSERT INTO app_private.personal_merge_contact_resolution_requests_v1 (
    actor_app_user_id, request_id, workspace_id, project_id, generation_id, known_fact_fingerprint,
    pending_fingerprint, resolution_fingerprint, post_known_fact_fingerprint, confirmed_at_utc
  ) VALUES (trusted_app_user_id, requested_request_id, trusted_workspace_id, trusted_project_id, requested_generation_id,
    expected_known_fact_fingerprint, expected_pending_fingerprint, expected_resolution_fingerprint,
    post_fingerprint, clock_timestamp());
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact resolution request count mismatch';
  END IF;
  IF NOT app_private.personal_merge_contact_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact resolution applications are incomplete';
  END IF;
  ended_at_value := app_private.end_known_source_personal_target_merge_generation_v1(trusted_app_user_id,
    trusted_workspace_id, trusted_project_id, requested_request_id, requested_generation_id, post_fingerprint);
  IF NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 receipt
    WHERE receipt.actor_app_user_id = trusted_app_user_id AND receipt.request_id = requested_request_id
      AND receipt.generation_id = requested_generation_id AND receipt.workspace_id = trusted_workspace_id
      AND receipt.project_id = trusted_project_id AND receipt.fact_fingerprint = post_fingerprint
      AND receipt.operation = 'personal_target_known_source_merge_end' AND receipt.reason = 'known_source_split'
      AND receipt.outcome = 'ended' AND receipt.ended_at_utc = ended_at_value)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 member WHERE member.generation_id = requested_generation_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact resolution end receipt is incomplete';
  END IF;
  DELETE FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
    USING app_private.personal_merge_contact_history_applications_v1 application
    WHERE payload.pending_fact_id = application.pending_fact_id
      AND application.actor_app_user_id = trusted_app_user_id AND application.request_id = requested_request_id;
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  IF affected_count <> expected_count OR EXISTS (
    SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
    JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING (pending_fact_id)
    WHERE pending.generation_id = requested_generation_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact resolution payload consumption is incomplete';
  END IF;
  IF NOT app_private.personal_merge_contact_resolution_proof_v1(trusted_app_user_id, requested_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'pending contact resolution final proof is incomplete';
  END IF;
  RETURN ended_at_value;
END
$function$;

REVOKE ALL ON TABLE app_private.personal_merge_contact_resolution_requests_v1,
  app_private.personal_merge_contact_history_applications_v1, app_private.personal_merge_contact_current_revisions_v1,
  app_private.personal_merge_contact_current_choices_v1 FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL ON FUNCTION app_private.personal_merge_contact_resolution_revision_proof_v1(uuid,text,text,integer,integer,jsonb),
  app_private.personal_merge_contact_resolution_proof_v1(uuid,uuid),
  app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; relation regclass; candidate regprocedure;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
    WHERE oid = 'app_private.stage_unassigned_personal_merge_contact_v1(uuid,uuid,uuid,uuid,uuid,text,integer,integer,text,boolean,boolean)'::regprocedure;
  FOREACH relation IN ARRAY ARRAY[
    'app_private.personal_merge_contact_resolution_requests_v1'::regclass,
    'app_private.personal_merge_contact_history_applications_v1'::regclass,
    'app_private.personal_merge_contact_current_revisions_v1'::regclass,
    'app_private.personal_merge_contact_current_choices_v1'::regclass] LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO %I', relation, trusted_owner);
  END LOOP;
  FOREACH candidate IN ARRAY ARRAY[
    'app_private.personal_merge_contact_resolution_revision_proof_v1(uuid,text,text,integer,integer,jsonb)'::regprocedure,
    'app_private.personal_merge_contact_resolution_proof_v1(uuid,uuid)'::regprocedure,
    'app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure] LOOP
    EXECUTE format('ALTER FUNCTION %s OWNER TO %I', candidate, trusted_owner);
  END LOOP;
END
$owner$;
