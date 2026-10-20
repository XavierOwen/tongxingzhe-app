-- Private historical contributions preserve their personal source.

CREATE TABLE app_private.personal_history_contribution_previews_v1 (
  preview_id uuid PRIMARY KEY,
  actor_app_user_id uuid,
  source_contact_id text,
  source_revision_number integer NOT NULL CHECK (source_revision_number > 0),
  target_project_id uuid NOT NULL,
  issued_at_utc timestamptz NOT NULL,
  expires_at_utc timestamptz NOT NULL,
  CONSTRAINT phc_preview_actor_fk FOREIGN KEY (actor_app_user_id)
    REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  CONSTRAINT phc_preview_source_fk FOREIGN KEY (source_contact_id)
    REFERENCES app_data.contacts(contact_id) ON DELETE SET NULL,
  CONSTRAINT phc_preview_project_fk FOREIGN KEY (target_project_id)
    REFERENCES app_data.projects(project_id) ON DELETE RESTRICT,
  CONSTRAINT phc_preview_time_check CHECK (
    isfinite(issued_at_utc) AND isfinite(expires_at_utc)
    AND expires_at_utc = issued_at_utc + interval '15 minutes'
  )
);

CREATE TABLE app_private.organization_historical_contact_copies_v1 (
  copy_id uuid PRIMARY KEY,
  target_project_id uuid NOT NULL,
  occurred_at_utc timestamptz NOT NULL CHECK (isfinite(occurred_at_utc)),
  occurred_time_zone text NOT NULL CHECK (length(btrim(occurred_time_zone)) > 0),
  channel text NOT NULL CHECK (channel IN (
    'face_to_face', 'voice_call', 'video_call', 'instant_text',
    'asynchronous_message', 'mixed', 'other_direct'
  )),
  reach_count integer NOT NULL CHECK (reach_count > 0),
  interest_level integer NOT NULL CHECK (interest_level BETWEEN 0 AND 4),
  confirmed_at_utc timestamptz NOT NULL CHECK (isfinite(confirmed_at_utc)),
  CONSTRAINT phc_copy_project_fk FOREIGN KEY (target_project_id)
    REFERENCES app_data.projects(project_id) ON DELETE RESTRICT
);

CREATE TABLE app_private.personal_history_contribution_confirmations_v1 (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid,
  source_contact_id text,
  target_project_id uuid NOT NULL,
  preview_id uuid NOT NULL UNIQUE,
  copy_id uuid NOT NULL UNIQUE,
  confirmed_at_utc timestamptz NOT NULL CHECK (isfinite(confirmed_at_utc)),
  CONSTRAINT phc_confirm_actor_fk FOREIGN KEY (actor_app_user_id)
    REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  CONSTRAINT phc_confirm_source_fk FOREIGN KEY (source_contact_id)
    REFERENCES app_data.contacts(contact_id) ON DELETE SET NULL,
  CONSTRAINT phc_confirm_project_fk FOREIGN KEY (target_project_id)
    REFERENCES app_data.projects(project_id) ON DELETE RESTRICT,
  CONSTRAINT phc_confirm_preview_fk FOREIGN KEY (preview_id)
    REFERENCES app_private.personal_history_contribution_previews_v1(preview_id) ON DELETE RESTRICT,
  CONSTRAINT phc_confirm_copy_fk FOREIGN KEY (copy_id)
    REFERENCES app_private.organization_historical_contact_copies_v1(copy_id) ON DELETE RESTRICT,
  CONSTRAINT phc_confirm_source_project_unique UNIQUE (target_project_id, source_contact_id)
);

REVOKE ALL ON TABLE
  app_private.personal_history_contribution_previews_v1,
  app_private.organization_historical_contact_copies_v1,
  app_private.personal_history_contribution_confirmations_v1
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_personal_history_contribution_provenance_v1()
RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF app_private.organization_purge_row_delete_authorized_v1(TG_RELID, to_jsonb(OLD)) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal history contribution provenance cannot be deleted';
  END IF;
  IF (NEW.actor_app_user_id IS NOT DISTINCT FROM OLD.actor_app_user_id
      OR (OLD.actor_app_user_id IS NOT NULL AND NEW.actor_app_user_id IS NULL))
    AND (NEW.source_contact_id IS NOT DISTINCT FROM OLD.source_contact_id
      OR (OLD.source_contact_id IS NOT NULL AND NEW.source_contact_id IS NULL))
    AND to_jsonb(NEW) - ARRAY['actor_app_user_id', 'source_contact_id']
      IS NOT DISTINCT FROM to_jsonb(OLD) - ARRAY['actor_app_user_id', 'source_contact_id']
    AND (NEW.actor_app_user_id IS DISTINCT FROM OLD.actor_app_user_id
      OR NEW.source_contact_id IS DISTINCT FROM OLD.source_contact_id)
  THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION USING ERRCODE = '55000',
    MESSAGE = 'personal history contribution provenance is immutable';
END
$function$;

CREATE TRIGGER personal_history_contribution_previews_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_history_contribution_previews_v1
FOR EACH ROW EXECUTE FUNCTION app_private.protect_personal_history_contribution_provenance_v1();

CREATE TRIGGER personal_history_contribution_confirmations_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_history_contribution_confirmations_v1
FOR EACH ROW EXECUTE FUNCTION app_private.protect_personal_history_contribution_provenance_v1();

CREATE TRIGGER organization_historical_contact_copies_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_historical_contact_copies_v1
FOR EACH ROW EXECUTE FUNCTION app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_private.lock_personal_history_contribution_context_v1(
  trusted_app_user_id uuid,
  requested_source_contact_id text,
  requested_target_project_id uuid
)
RETURNS timestamptz
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  organization_id uuid;
  reference_time timestamptz;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'personal history contribution requires read committed';
  END IF;
  -- Preserve actor status without blocking the source writer's author FK checks.
  PERFORM 1 FROM app_data.app_users AS actor
  WHERE actor.app_user_id = trusted_app_user_id FOR NO KEY UPDATE;
  SELECT project.workspace_id INTO organization_id FROM app_data.projects AS project
  WHERE project.project_id = requested_target_project_id;
  IF organization_id IS NULL OR trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal history contribution forbidden';
  END IF;
  PERFORM app_private.lock_organization_governance_v1(organization_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'organization-membership:' || organization_id::text || ':' || trusted_app_user_id::text, 0
  ));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'project-membership:' || requested_target_project_id::text || ':' || trusted_app_user_id::text, 0
  ));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'management-follow-up-consent-opt-in:' || requested_target_project_id::text, 0
  ));
  IF requested_source_contact_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('contact:' || requested_source_contact_id, 0));
  END IF;

  reference_time := clock_timestamp();
  IF NOT EXISTS (
    SELECT 1 FROM app_data.app_users AS actor
    JOIN app_data.organization_memberships AS membership ON membership.app_user_id = actor.app_user_id
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.organization_membership_id = membership.organization_membership_id
    JOIN app_data.projects AS project ON project.project_id = project_membership.project_id
    JOIN app_data.workspaces AS workspace ON workspace.workspace_id = project.workspace_id
    WHERE actor.app_user_id = trusted_app_user_id AND actor.status = 'active'
      AND workspace.workspace_id = organization_id AND workspace.workspace_kind = 'organization'
      AND workspace.deleted_at IS NULL AND project.project_id = requested_target_project_id
      AND project.status = 'active' AND membership.organization_workspace_id = workspace.workspace_id
      AND tstzrange(membership.active_from_utc, membership.inactive_from_utc, '[)') @> reference_time
      AND tstzrange(project_membership.active_from_utc, project_membership.inactive_from_utc, '[)') @> reference_time
      AND NOT EXISTS (SELECT 1 FROM app_private.organization_deletion_current AS deletion
        WHERE deletion.organization_workspace_id = workspace.workspace_id AND deletion.status <> 'restored')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal history contribution forbidden';
  END IF;
  RETURN reference_time;
END
$function$;

CREATE FUNCTION app_private.preview_personal_history_contribution_v1(
  trusted_app_user_id uuid,
  requested_source_contact_id text,
  requested_target_project_id uuid
)
RETURNS TABLE (
  contribution_preview_contract_id text,
  preview_id uuid,
  source_revision_number integer,
  target_project_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz,
  occurred_at_utc timestamptz,
  occurred_time_zone text,
  channel text,
  reach_count integer,
  interest_level integer
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  reference_time timestamptz;
  issued_preview_id uuid := gen_random_uuid();
  source record;
BEGIN
  IF requested_source_contact_id IS NULL OR length(btrim(requested_source_contact_id)) = 0
    OR requested_target_project_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid personal history contribution preview';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'personal history contribution requires read committed';
  END IF;
  reference_time := app_private.lock_personal_history_contribution_context_v1(
    trusted_app_user_id, requested_source_contact_id, requested_target_project_id
  );
  SELECT contact.current_revision, contact.occurred_at_utc, contact.occurred_time_zone,
    contact.channel, contact.reach_count, contact.interest_level,
    (revision.snapshot->>'occurredAtUtc')::timestamptz AS snapshot_occurred_at_utc,
    revision.snapshot->>'occurredTimeZone' AS snapshot_time_zone,
    revision.snapshot->>'channel' AS snapshot_channel,
    (revision.snapshot->>'reachCount')::integer AS snapshot_reach_count,
    (revision.snapshot->>'interestLevel')::integer AS snapshot_interest_level
  INTO source
  FROM app_data.contacts AS contact
  JOIN app_data.workspaces AS workspace ON workspace.workspace_id = contact.workspace_id
  JOIN app_data.contact_revisions AS revision ON revision.contact_id = contact.contact_id
    AND revision.revision_number = contact.current_revision
  WHERE contact.contact_id = requested_source_contact_id AND contact.app_user_id = trusted_app_user_id
    AND workspace.workspace_kind = 'personal' AND workspace.personal_owner_app_user_id = trusted_app_user_id
    AND workspace.deleted_at IS NULL AND contact.lifecycle_status = 'active'
    AND revision.revision_kind IN ('submitted', 'corrected');
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal history contribution forbidden';
  END IF;
  IF source.occurred_at_utc IS DISTINCT FROM source.snapshot_occurred_at_utc
    OR source.occurred_time_zone IS DISTINCT FROM source.snapshot_time_zone
    OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = source.snapshot_time_zone)
    OR source.channel IS DISTINCT FROM source.snapshot_channel
    OR source.reach_count IS DISTINCT FROM source.snapshot_reach_count
    OR source.interest_level IS DISTINCT FROM source.snapshot_interest_level
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal history contribution unavailable';
  END IF;
  INSERT INTO app_private.personal_history_contribution_previews_v1 (
    preview_id, actor_app_user_id, source_contact_id, source_revision_number,
    target_project_id, issued_at_utc, expires_at_utc
  ) VALUES (
    issued_preview_id, trusted_app_user_id, requested_source_contact_id, source.current_revision,
    requested_target_project_id, reference_time, reference_time + interval '15 minutes'
  );
  RETURN QUERY SELECT 'personal-history-contribution-preview:v1'::text, issued_preview_id,
    source.current_revision, requested_target_project_id, reference_time, reference_time + interval '15 minutes',
    source.snapshot_occurred_at_utc, source.snapshot_time_zone, source.snapshot_channel,
    source.snapshot_reach_count, source.snapshot_interest_level;
END
$function$;

CREATE FUNCTION app_private.confirm_personal_history_contribution_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid,
  requested_preview_id uuid
)
RETURNS TABLE (
  contribution_contract_id text,
  copy_id uuid,
  target_project_id uuid,
  confirmed_at_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  reference_time timestamptz;
  preview app_private.personal_history_contribution_previews_v1%ROWTYPE;
  confirmation app_private.personal_history_contribution_confirmations_v1%ROWTYPE;
  source record;
  created_copy_id uuid := gen_random_uuid();
BEGIN
  IF requested_request_id IS NULL OR requested_preview_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid personal history contribution request';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'personal history contribution requires read committed';
  END IF;
  IF trusted_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal history contribution forbidden';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'personal-history-contribution-confirmation:' || requested_request_id::text, 0
  ));
  IF app_private.organization_purge_request_completed_v1(
    'personal-history-contribution-confirmation', requested_request_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'personal history contribution idempotency conflict';
  END IF;
  SELECT claim.* INTO confirmation FROM app_private.personal_history_contribution_confirmations_v1 AS claim
  WHERE claim.request_id = requested_request_id;
  IF confirmation.request_id IS NOT NULL AND (
    confirmation.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
    OR confirmation.preview_id IS DISTINCT FROM requested_preview_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'personal history contribution idempotency conflict';
  END IF;
  SELECT receipt.* INTO preview FROM app_private.personal_history_contribution_previews_v1 AS receipt
  WHERE receipt.preview_id = requested_preview_id;
  IF NOT FOUND OR preview.actor_app_user_id IS DISTINCT FROM trusted_app_user_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal history contribution forbidden';
  END IF;
  reference_time := app_private.lock_personal_history_contribution_context_v1(
    trusted_app_user_id, preview.source_contact_id, preview.target_project_id
  );
  IF confirmation.request_id IS NOT NULL THEN
    IF confirmation.target_project_id IS DISTINCT FROM preview.target_project_id
      OR confirmation.source_contact_id IS DISTINCT FROM preview.source_contact_id
      OR NOT EXISTS (SELECT 1 FROM app_private.organization_historical_contact_copies_v1 AS copy
        WHERE copy.copy_id = confirmation.copy_id AND copy.target_project_id = confirmation.target_project_id
          AND copy.confirmed_at_utc = confirmation.confirmed_at_utc)
    THEN
      RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal history contribution unavailable';
    END IF;
    RETURN QUERY SELECT 'personal-history-contribution-confirmation:v1'::text,
      confirmation.copy_id, confirmation.target_project_id, confirmation.confirmed_at_utc;
    RETURN;
  END IF;
  IF preview.source_contact_id IS NULL OR reference_time < preview.issued_at_utc
    OR reference_time >= preview.expires_at_utc
    OR EXISTS (SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 AS claim
      WHERE claim.preview_id = requested_preview_id
        OR (claim.target_project_id = preview.target_project_id AND claim.source_contact_id = preview.source_contact_id))
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'personal history contribution idempotency conflict';
  END IF;

  SELECT contact.current_revision, contact.lifecycle_status, revision.revision_kind,
    contact.occurred_at_utc, contact.occurred_time_zone, contact.channel, contact.reach_count, contact.interest_level,
    (revision.snapshot->>'occurredAtUtc')::timestamptz AS snapshot_occurred_at_utc,
    revision.snapshot->>'occurredTimeZone' AS snapshot_time_zone,
    revision.snapshot->>'channel' AS snapshot_channel,
    (revision.snapshot->>'reachCount')::integer AS snapshot_reach_count,
    (revision.snapshot->>'interestLevel')::integer AS snapshot_interest_level
  INTO source
  FROM app_data.contacts AS contact
  JOIN app_data.workspaces AS workspace ON workspace.workspace_id = contact.workspace_id
  JOIN app_data.contact_revisions AS revision ON revision.contact_id = contact.contact_id
    AND revision.revision_number = contact.current_revision
  WHERE contact.contact_id = preview.source_contact_id AND contact.app_user_id = trusted_app_user_id
    AND workspace.workspace_kind = 'personal' AND workspace.personal_owner_app_user_id = trusted_app_user_id
    AND workspace.deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'personal history contribution forbidden';
  END IF;
  IF source.current_revision IS DISTINCT FROM preview.source_revision_number
    OR source.lifecycle_status IS DISTINCT FROM 'active' OR source.revision_kind NOT IN ('submitted', 'corrected')
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'personal history contribution idempotency conflict';
  END IF;
  IF source.occurred_at_utc IS DISTINCT FROM source.snapshot_occurred_at_utc
    OR source.occurred_time_zone IS DISTINCT FROM source.snapshot_time_zone
    OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = source.snapshot_time_zone)
    OR source.channel IS DISTINCT FROM source.snapshot_channel
    OR source.reach_count IS DISTINCT FROM source.snapshot_reach_count
    OR source.interest_level IS DISTINCT FROM source.snapshot_interest_level
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'personal history contribution unavailable';
  END IF;
  INSERT INTO app_private.organization_historical_contact_copies_v1 (
    copy_id, target_project_id, occurred_at_utc, occurred_time_zone, channel, reach_count, interest_level, confirmed_at_utc
  ) VALUES (
    created_copy_id, preview.target_project_id, source.snapshot_occurred_at_utc,
    source.snapshot_time_zone, source.snapshot_channel, source.snapshot_reach_count,
    source.snapshot_interest_level, reference_time
  );
  INSERT INTO app_private.personal_history_contribution_confirmations_v1 (
    request_id, actor_app_user_id, source_contact_id, target_project_id, preview_id, copy_id, confirmed_at_utc
  ) VALUES (
    requested_request_id, trusted_app_user_id, preview.source_contact_id, preview.target_project_id,
    requested_preview_id, created_copy_id, reference_time
  );
  RETURN QUERY SELECT 'personal-history-contribution-confirmation:v1'::text,
    created_copy_id, preview.target_project_id, reference_time;
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.protect_personal_history_contribution_provenance_v1(),
  app_private.lock_personal_history_contribution_context_v1(uuid,text,uuid),
  app_private.preview_personal_history_contribution_v1(uuid,text,uuid),
  app_private.confirm_personal_history_contribution_v1(uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text; object_name text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  FOREACH object_name IN ARRAY ARRAY[
    'personal_history_contribution_previews_v1', 'organization_historical_contact_copies_v1',
    'personal_history_contribution_confirmations_v1'
  ] LOOP
    EXECUTE format('ALTER TABLE app_private.%I OWNER TO %I', object_name, trusted_owner);
  END LOOP;
  FOREACH object_name IN ARRAY ARRAY[
    'protect_personal_history_contribution_provenance_v1()',
    'lock_personal_history_contribution_context_v1(uuid,text,uuid)',
    'preview_personal_history_contribution_v1(uuid,text,uuid)',
    'confirm_personal_history_contribution_v1(uuid,uuid,uuid)'
  ] LOOP
    EXECUTE format('ALTER FUNCTION app_private.%s OWNER TO %I', object_name, trusted_owner);
  END LOOP;
END
$owner$;

-- Organization purge extension follows the private contribution core.

DO $purge_family$
DECLARE
  original pg_constraint%ROWTYPE;
  definition text;
  family_anchor text := $anchor$'management-follow-up-consent-opt-in-request'::text$anchor$;
  family_extension text := $extension$'personal-history-contribution-confirmation'::text, $extension$;
BEGIN
  SELECT * INTO STRICT original FROM pg_constraint
    WHERE conrelid = 'app_private.organization_purge_request_tombstones'::regclass
      AND conname = 'organization_purge_request_tombstones_claim_family_check';
  definition := pg_get_constraintdef(original.oid);
  IF length(definition) - length(replace(definition, family_anchor, '')) <> length(family_anchor)
    OR position('personal-history-contribution-confirmation' IN definition) <> 0 THEN
    RAISE EXCEPTION '0134 organization purge family anchor unavailable';
  END IF;
  ALTER TABLE app_private.organization_purge_request_tombstones
    DROP CONSTRAINT organization_purge_request_tombstones_claim_family_check;
  EXECUTE 'ALTER TABLE app_private.organization_purge_request_tombstones ADD CONSTRAINT '
    || 'organization_purge_request_tombstones_claim_family_check '
    || replace(definition, family_anchor, family_extension || family_anchor);
END
$purge_family$;

DO $purge_collector$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  collector_anchor text := $anchor$  SELECT 13, 'management-follow-up-consent-opt-in-request', 'management-follow-up-consent-opt-in-request', request_id FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)$anchor$;
  collector_extension text := $extension$
  UNION
  SELECT 14, 'personal-history-contribution-confirmation', 'personal-history-contribution-confirmation', request_id FROM app_private.personal_history_contribution_confirmations_v1
  WHERE target_project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)$extension$;
BEGIN
  SELECT * INTO STRICT original FROM pg_proc
    WHERE oid = 'app_private.organization_purge_requests_v1(uuid)'::regprocedure;
  definition := pg_get_functiondef(original.oid);
  IF length(definition) - length(replace(definition, collector_anchor, '')) <> length(collector_anchor)
    OR position('personal-history-contribution-confirmation' IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0134 organization purge collector anchor unavailable';
  END IF;
  EXECUTE replace(definition, collector_anchor, collector_anchor || collector_extension);
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND replace(changed.prosrc, collector_extension, '') = original.prosrc) THEN
    RAISE EXCEPTION '0134 organization purge collector metadata or implementation drift';
  END IF;
END
$purge_collector$;

DO $purge_finalizer$
DECLARE
  original pg_proc%ROWTYPE;
  definition text;
  relation_anchor text := $anchor$  relation_list text[] := ARRAY[
$anchor$;
  relation_extension text := $extension$    'app_private.personal_history_contribution_confirmations_v1',
    'app_private.personal_history_contribution_previews_v1',
    'app_private.organization_historical_contact_copies_v1',
$extension$;
  scope_anchor text := $anchor$  scope_predicates text[] := ARRAY[
$anchor$;
  scope_extension text := $extension$    't.target_project_id = ANY($2)',
    't.target_project_id = ANY($2)',
    't.target_project_id = ANY($2)',
$extension$;
  provenance_anchor text := $anchor$  -- Report provenance checks use only the fixed reporting relations above.$anchor$;
  provenance_extension text := $extension$  IF EXISTS (
    SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 confirmation
    LEFT JOIN app_private.personal_history_contribution_previews_v1 preview USING(preview_id)
    LEFT JOIN app_private.organization_historical_contact_copies_v1 copy USING(copy_id)
    WHERE (confirmation.target_project_id=ANY(project_ids)
      OR preview.target_project_id=ANY(project_ids) OR copy.target_project_id=ANY(project_ids))
      AND (confirmation.target_project_id IS DISTINCT FROM preview.target_project_id
        OR confirmation.target_project_id IS DISTINCT FROM copy.target_project_id
        OR confirmation.confirmed_at_utc IS DISTINCT FROM copy.confirmed_at_utc
        OR (confirmation.actor_app_user_id IS NOT NULL AND preview.actor_app_user_id IS NOT NULL
          AND confirmation.actor_app_user_id IS DISTINCT FROM preview.actor_app_user_id)
        OR (confirmation.source_contact_id IS NOT NULL AND preview.source_contact_id IS NOT NULL
          AND confirmation.source_contact_id IS DISTINCT FROM preview.source_contact_id))
  ) OR EXISTS (
    SELECT 1 FROM app_private.organization_historical_contact_copies_v1 copy
    WHERE copy.target_project_id=ANY(project_ids) AND NOT EXISTS (
      SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 confirmation
      WHERE confirmation.copy_id=copy.copy_id)
  ) OR EXISTS (
    SELECT 1 FROM (
      SELECT actor_app_user_id,source_contact_id FROM app_private.personal_history_contribution_previews_v1
      WHERE target_project_id=ANY(project_ids)
      UNION ALL
      SELECT actor_app_user_id,source_contact_id FROM app_private.personal_history_contribution_confirmations_v1
      WHERE target_project_id=ANY(project_ids)
    ) provenance
    JOIN app_data.contacts source ON source.contact_id=provenance.source_contact_id
    JOIN app_data.workspaces workspace ON workspace.workspace_id=source.workspace_id
    JOIN app_data.projects project ON project.project_id=source.project_id
    WHERE workspace.workspace_kind IS DISTINCT FROM 'personal'
      OR project.workspace_id IS DISTINCT FROM source.workspace_id
      OR workspace.personal_owner_app_user_id IS DISTINCT FROM source.app_user_id
      OR (provenance.actor_app_user_id IS NOT NULL
        AND provenance.actor_app_user_id IS DISTINCT FROM source.app_user_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge contribution provenance mismatch';
  END IF;

$extension$;
BEGIN
  SELECT * INTO STRICT original FROM pg_proc
    WHERE oid = 'app_private.finalize_organization_purge_v1(uuid,uuid)'::regprocedure;
  definition := pg_get_functiondef(original.oid);
  IF length(definition) - length(replace(definition, relation_anchor, '')) <> length(relation_anchor)
    OR length(definition) - length(replace(definition, scope_anchor, '')) <> length(scope_anchor)
    OR length(definition) - length(replace(definition, provenance_anchor, '')) <> length(provenance_anchor)
    OR position('personal_history_contribution_' IN original.prosrc) <> 0 THEN
    RAISE EXCEPTION '0134 organization purge finalizer anchor unavailable';
  END IF;
  definition := replace(definition, relation_anchor, relation_anchor || relation_extension);
  definition := replace(definition, scope_anchor, scope_anchor || scope_extension);
  EXECUTE replace(definition, provenance_anchor, provenance_extension || provenance_anchor);
  IF NOT EXISTS (SELECT 1 FROM pg_proc changed
    WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc'
      AND replace(replace(replace(changed.prosrc, relation_extension, ''), scope_extension, ''), provenance_extension, '') = original.prosrc) THEN
    RAISE EXCEPTION '0134 organization purge finalizer metadata or implementation drift';
  END IF;
END
$purge_finalizer$;
