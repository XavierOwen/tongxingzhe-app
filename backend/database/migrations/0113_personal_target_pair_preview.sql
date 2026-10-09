-- Validate one caller-supplied personal target pair in a single command snapshot.
-- Runtime access remains closed until receipt cleanup has a deployed SLA.

ALTER TABLE app_data.promotion_targets
  ADD COLUMN profile_revision bigint NOT NULL DEFAULT 1 CHECK (
    profile_revision > 0
  );

CREATE FUNCTION app_private.bump_promotion_target_profile_revision_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF ROW(
      NEW.target_type,
      NEW.display_name,
      NEW.phone,
      NEW.email,
      NEW.status
    ) IS DISTINCT FROM ROW(
      OLD.target_type,
      OLD.display_name,
      OLD.phone,
      OLD.email,
      OLD.status
    )
  THEN
    NEW.profile_revision := OLD.profile_revision + 1;
  ELSE
    NEW.profile_revision := OLD.profile_revision;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER promotion_targets_profile_revision
BEFORE UPDATE ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION
  app_private.bump_promotion_target_profile_revision_v1();

CREATE TABLE app_private.personal_target_pair_preview_receipts (
  preview_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  first_target_id uuid NOT NULL,
  second_target_id uuid NOT NULL,
  first_profile_revision bigint NOT NULL CHECK (first_profile_revision > 0),
  second_profile_revision bigint NOT NULL CHECK (second_profile_revision > 0),
  first_assignment_id uuid NOT NULL,
  second_assignment_id uuid NOT NULL,
  first_retention_due_at_utc timestamptz NOT NULL CHECK (
    isfinite(first_retention_due_at_utc)
  ),
  second_retention_due_at_utc timestamptz NOT NULL CHECK (
    isfinite(second_retention_due_at_utc)
  ),
  merge_deadline_at_utc timestamptz NOT NULL CHECK (
    isfinite(merge_deadline_at_utc)
  ),
  phone_match boolean NOT NULL,
  email_match boolean NOT NULL,
  previewed_at_utc timestamptz NOT NULL CHECK (isfinite(previewed_at_utc)),
  expires_at_utc timestamptz NOT NULL CHECK (isfinite(expires_at_utc)),
  CHECK (first_target_id < second_target_id),
  CHECK (phone_match OR email_match),
  CHECK (
    merge_deadline_at_utc = LEAST(
      first_retention_due_at_utc,
      second_retention_due_at_utc
    )
  ),
  CHECK (expires_at_utc = previewed_at_utc + interval '15 minutes')
);

CREATE INDEX personal_target_pair_preview_receipts_expiry
  ON app_private.personal_target_pair_preview_receipts (
    expires_at_utc,
    preview_id
  );

CREATE TABLE app_private.personal_target_pair_preview_audit_events (
  audit_event_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  operation text NOT NULL CHECK (
    operation = 'personal_target_pair_preview'
  ),
  outcome text NOT NULL CHECK (outcome = 'previewed'),
  target_count integer NOT NULL CHECK (target_count = 2),
  match_signal_count integer NOT NULL CHECK (
    match_signal_count BETWEEN 1 AND 2
  ),
  occurred_at_utc timestamptz NOT NULL CHECK (isfinite(occurred_at_utc))
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_pair_preview_receipts,
  app_private.personal_target_pair_preview_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER personal_target_pair_preview_receipts_immutable
BEFORE UPDATE ON app_private.personal_target_pair_preview_receipts
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_audit_mutation();

CREATE TRIGGER personal_target_pair_preview_audit_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.personal_target_pair_preview_audit_events
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_audit_mutation();

CREATE FUNCTION app_private.validate_personal_target_pair_preview_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_preview_id uuid,
  trusted_validated_at_utc timestamptz
)
RETURNS TABLE (
  preview_id uuid,
  actor_app_user_id uuid,
  workspace_id uuid,
  first_target_id uuid,
  second_target_id uuid,
  first_profile_revision bigint,
  second_profile_revision bigint,
  first_assignment_id uuid,
  second_assignment_id uuid,
  first_retention_due_at_utc timestamptz,
  second_retention_due_at_utc timestamptz,
  merge_deadline_at_utc timestamptz,
  phone_match boolean,
  email_match boolean,
  previewed_at_utc timestamptz,
  expires_at_utc timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, app_data
AS $function$
  SELECT
    receipt.preview_id,
    receipt.actor_app_user_id,
    receipt.workspace_id,
    receipt.first_target_id,
    receipt.second_target_id,
    receipt.first_profile_revision,
    receipt.second_profile_revision,
    receipt.first_assignment_id,
    receipt.second_assignment_id,
    receipt.first_retention_due_at_utc,
    receipt.second_retention_due_at_utc,
    receipt.merge_deadline_at_utc,
    receipt.phone_match,
    receipt.email_match,
    receipt.previewed_at_utc,
    receipt.expires_at_utc
  FROM app_private.personal_target_pair_preview_receipts AS receipt
  JOIN app_data.app_users AS actor
    ON actor.app_user_id = receipt.actor_app_user_id
   AND actor.app_user_id = trusted_app_user_id
   AND actor.status = 'active'
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.workspace_id = receipt.workspace_id
   AND workspace_row.workspace_kind = 'personal'
   AND workspace_row.personal_owner_app_user_id = actor.app_user_id
   AND workspace_row.deleted_at IS NULL
  JOIN app_data.user_current_projects AS current_project
    ON current_project.app_user_id = actor.app_user_id
   AND current_project.project_id = requested_project_id
  JOIN app_data.projects AS project_row
    ON project_row.project_id = current_project.project_id
   AND project_row.workspace_id = workspace_row.workspace_id
   AND project_row.status = 'active'
  JOIN app_data.promotion_targets AS first_target
    ON first_target.promotion_target_id = receipt.first_target_id
   AND first_target.workspace_id = receipt.workspace_id
   AND first_target.profile_revision = receipt.first_profile_revision
   AND first_target.status = 'active'
  JOIN app_data.promotion_targets AS second_target
    ON second_target.promotion_target_id = receipt.second_target_id
   AND second_target.workspace_id = receipt.workspace_id
   AND second_target.profile_revision = receipt.second_profile_revision
   AND second_target.status = 'active'
   AND second_target.target_type = first_target.target_type
  JOIN app_data.promotion_target_assignments AS first_assignment
    ON first_assignment.assignment_id = receipt.first_assignment_id
   AND first_assignment.promotion_target_id = first_target.promotion_target_id
   AND first_assignment.app_user_id = actor.app_user_id
   AND first_assignment.ended_at IS NULL
  JOIN app_data.promotion_target_assignments AS second_assignment
    ON second_assignment.assignment_id = receipt.second_assignment_id
   AND second_assignment.promotion_target_id = second_target.promotion_target_id
   AND second_assignment.app_user_id = actor.app_user_id
   AND second_assignment.ended_at IS NULL
  CROSS JOIN LATERAL (
    SELECT
      app_data.promotion_target_review_due_at(
        first_target.promotion_target_id
      ) AS first_due_at,
      app_data.promotion_target_review_due_at(
        second_target.promotion_target_id
      ) AS second_due_at,
      COALESCE(
        NULLIF(btrim(first_target.phone), '') =
          NULLIF(btrim(second_target.phone), ''),
        false
      ) AS current_phone_match,
      COALESCE(
        lower(NULLIF(btrim(first_target.email), '')) =
          lower(NULLIF(btrim(second_target.email), '')),
        false
      ) AS current_email_match
  ) AS current_facts
  WHERE receipt.preview_id = requested_preview_id
    AND trusted_validated_at_utc IS NOT NULL
    AND isfinite(trusted_validated_at_utc)
    AND trusted_validated_at_utc >= receipt.previewed_at_utc
    AND trusted_validated_at_utc < receipt.expires_at_utc
    AND current_facts.first_due_at = receipt.first_retention_due_at_utc
    AND current_facts.second_due_at = receipt.second_retention_due_at_utc
    AND current_facts.first_due_at > trusted_validated_at_utc
    AND current_facts.second_due_at > trusted_validated_at_utc
    AND current_facts.current_phone_match = receipt.phone_match
    AND current_facts.current_email_match = receipt.email_match
    AND (
      current_facts.current_phone_match
      OR current_facts.current_email_match
    )
$function$;

CREATE FUNCTION app_private.cleanup_personal_target_pair_preview_receipts_v1()
RETURNS integer
LANGUAGE sql
VOLATILE
SET search_path = pg_catalog
AS $function$
  WITH cutoff AS MATERIALIZED (
    SELECT clock_timestamp() AS cutoff_at_utc
  ),
  expired AS MATERIALIZED (
    SELECT receipt.preview_id
    FROM app_private.personal_target_pair_preview_receipts AS receipt
    CROSS JOIN cutoff
    WHERE receipt.expires_at_utc <= cutoff.cutoff_at_utc
    ORDER BY receipt.expires_at_utc, receipt.preview_id
    LIMIT 100
    FOR UPDATE OF receipt SKIP LOCKED
  ),
  deleted AS (
    DELETE FROM app_private.personal_target_pair_preview_receipts AS receipt
    USING expired
    WHERE receipt.preview_id = expired.preview_id
    RETURNING 1
  )
  SELECT count(*)::integer FROM deleted
$function$;

CREATE FUNCTION app_data.preview_personal_target_pair_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_first_target_id uuid,
  requested_second_target_id uuid
)
RETURNS TABLE (
  preview_id uuid,
  first_target_id uuid,
  first_target_type text,
  first_display_name text,
  first_phone text,
  first_email text,
  second_target_id uuid,
  second_target_type text,
  second_display_name text,
  second_phone text,
  second_email text,
  phone_match boolean,
  email_match boolean,
  first_retention_due_at_utc timestamptz,
  second_retention_due_at_utc timestamptz,
  merge_deadline_at_utc timestamptz,
  expiry_consequence text,
  previewed_at_utc timestamptz,
  expires_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RETURN QUERY
  WITH facts AS MATERIALIZED (
    SELECT
      actor.app_user_id AS actor_app_user_id,
      workspace_row.workspace_id AS workspace_id,
      first_target.promotion_target_id AS first_target_id,
      first_target.target_type AS first_target_type,
      first_target.display_name AS first_display_name,
      first_target.phone AS first_phone,
      first_target.email AS first_email,
      first_target.profile_revision AS first_profile_revision,
      first_assignment.assignment_id AS first_assignment_id,
      first_retention.review_due_at AS first_retention_due_at_utc,
      second_target.promotion_target_id AS second_target_id,
      second_target.target_type AS second_target_type,
      second_target.display_name AS second_display_name,
      second_target.phone AS second_phone,
      second_target.email AS second_email,
      second_target.profile_revision AS second_profile_revision,
      second_assignment.assignment_id AS second_assignment_id,
      second_retention.review_due_at AS second_retention_due_at_utc,
      COALESCE(
        NULLIF(btrim(first_target.phone), '') =
          NULLIF(btrim(second_target.phone), ''),
        false
      ) AS phone_match,
      COALESCE(
        lower(NULLIF(btrim(first_target.email), '')) =
          lower(NULLIF(btrim(second_target.email), '')),
        false
      ) AS email_match
    FROM app_data.external_identities AS identity_row
    JOIN app_data.app_users AS actor
      ON actor.app_user_id = identity_row.app_user_id
     AND actor.status = 'active'
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.personal_owner_app_user_id = actor.app_user_id
     AND workspace_row.workspace_kind = 'personal'
     AND workspace_row.deleted_at IS NULL
    JOIN app_data.user_current_projects AS current_project
      ON current_project.app_user_id = actor.app_user_id
     AND current_project.project_id = requested_project_id
    JOIN app_data.projects AS project_row
      ON project_row.project_id = current_project.project_id
     AND project_row.workspace_id = workspace_row.workspace_id
     AND project_row.status = 'active'
    JOIN app_data.promotion_targets AS first_target
      ON first_target.promotion_target_id = LEAST(
        requested_first_target_id,
        requested_second_target_id
      )
     AND first_target.workspace_id = workspace_row.workspace_id
     AND first_target.status = 'active'
    JOIN app_data.promotion_targets AS second_target
      ON second_target.promotion_target_id = GREATEST(
        requested_first_target_id,
        requested_second_target_id
      )
     AND second_target.workspace_id = workspace_row.workspace_id
     AND second_target.status = 'active'
     AND second_target.target_type = first_target.target_type
    JOIN app_data.promotion_target_assignments AS first_assignment
      ON first_assignment.promotion_target_id = first_target.promotion_target_id
     AND first_assignment.app_user_id = actor.app_user_id
     AND first_assignment.ended_at IS NULL
    JOIN app_data.promotion_target_assignments AS second_assignment
      ON second_assignment.promotion_target_id = second_target.promotion_target_id
     AND second_assignment.app_user_id = actor.app_user_id
     AND second_assignment.ended_at IS NULL
    CROSS JOIN LATERAL (
      SELECT app_data.promotion_target_review_due_at(
        first_target.promotion_target_id
      ) AS review_due_at
    ) AS first_retention
    CROSS JOIN LATERAL (
      SELECT app_data.promotion_target_review_due_at(
        second_target.promotion_target_id
      ) AS review_due_at
    ) AS second_retention
    WHERE identity_row.issuer = trusted_issuer
      AND identity_row.subject = trusted_subject
      AND trusted_issuer IS NOT NULL
      AND trusted_subject IS NOT NULL
      AND length(btrim(trusted_issuer)) BETWEEN 1 AND 2048
      AND length(btrim(trusted_subject)) BETWEEN 1 AND 512
      AND requested_project_id IS NOT NULL
      AND requested_first_target_id IS NOT NULL
      AND requested_second_target_id IS NOT NULL
      AND requested_first_target_id <> requested_second_target_id
      AND (
        COALESCE(
          NULLIF(btrim(first_target.phone), '') =
            NULLIF(btrim(second_target.phone), ''),
          false
        )
        OR COALESCE(
          lower(NULLIF(btrim(first_target.email), '')) =
            lower(NULLIF(btrim(second_target.email), '')),
          false
        )
      )
  ),
  timed AS MATERIALIZED (
    SELECT
      pg_catalog.gen_random_uuid() AS preview_id,
      pg_catalog.clock_timestamp() AS previewed_at_utc
    FROM facts
  ),
  eligible AS MATERIALIZED (
    SELECT
      facts.*,
      timed.preview_id,
      timed.previewed_at_utc,
      timed.previewed_at_utc + interval '15 minutes' AS expires_at_utc
    FROM facts
    CROSS JOIN timed
    WHERE facts.first_retention_due_at_utc > timed.previewed_at_utc
      AND facts.second_retention_due_at_utc > timed.previewed_at_utc
  ),
  inserted_receipt AS (
    INSERT INTO app_private.personal_target_pair_preview_receipts (
      preview_id,
      actor_app_user_id,
      workspace_id,
      first_target_id,
      second_target_id,
      first_profile_revision,
      second_profile_revision,
      first_assignment_id,
      second_assignment_id,
      first_retention_due_at_utc,
      second_retention_due_at_utc,
      merge_deadline_at_utc,
      phone_match,
      email_match,
      previewed_at_utc,
      expires_at_utc
    )
    SELECT
      eligible.preview_id,
      eligible.actor_app_user_id,
      eligible.workspace_id,
      eligible.first_target_id,
      eligible.second_target_id,
      eligible.first_profile_revision,
      eligible.second_profile_revision,
      eligible.first_assignment_id,
      eligible.second_assignment_id,
      eligible.first_retention_due_at_utc,
      eligible.second_retention_due_at_utc,
      LEAST(
        eligible.first_retention_due_at_utc,
        eligible.second_retention_due_at_utc
      ),
      eligible.phone_match,
      eligible.email_match,
      eligible.previewed_at_utc,
      eligible.expires_at_utc
    FROM eligible
    RETURNING *
  ),
  inserted_access_events AS (
    INSERT INTO app_data.promotion_target_access_events (
      event_id,
      workspace_id,
      promotion_target_id,
      actor_app_user_id,
      action,
      occurred_at
    )
    SELECT
      pg_catalog.gen_random_uuid(),
      receipt.workspace_id,
      target_id.target_id,
      receipt.actor_app_user_id,
      'viewed',
      receipt.previewed_at_utc
    FROM inserted_receipt AS receipt
    CROSS JOIN LATERAL (
      VALUES (receipt.first_target_id), (receipt.second_target_id)
    ) AS target_id(target_id)
    RETURNING event_id
  ),
  inserted_audit AS (
    INSERT INTO app_private.personal_target_pair_preview_audit_events (
      audit_event_id,
      actor_app_user_id,
      workspace_id,
      operation,
      outcome,
      target_count,
      match_signal_count,
      occurred_at_utc
    )
    SELECT
      pg_catalog.gen_random_uuid(),
      receipt.actor_app_user_id,
      receipt.workspace_id,
      'personal_target_pair_preview',
      'previewed',
      2,
      CASE WHEN receipt.phone_match THEN 1 ELSE 0 END
        + CASE WHEN receipt.email_match THEN 1 ELSE 0 END,
      receipt.previewed_at_utc
    FROM inserted_receipt AS receipt
    RETURNING audit_event_id
  )
  SELECT
    eligible.preview_id,
    eligible.first_target_id,
    eligible.first_target_type,
    eligible.first_display_name,
    eligible.first_phone,
    eligible.first_email,
    eligible.second_target_id,
    eligible.second_target_type,
    eligible.second_display_name,
    eligible.second_phone,
    eligible.second_email,
    eligible.phone_match,
    eligible.email_match,
    eligible.first_retention_due_at_utc,
    eligible.second_retention_due_at_utc,
    LEAST(
      eligible.first_retention_due_at_utc,
      eligible.second_retention_due_at_utc
    ),
    'anonymize_both'::text,
    eligible.previewed_at_utc,
    eligible.expires_at_utc
  FROM eligible
  JOIN inserted_receipt AS receipt
    ON receipt.preview_id = eligible.preview_id
  CROSS JOIN (
    SELECT count(*) AS inserted_count FROM inserted_access_events
  ) AS access_count
  CROSS JOIN (
    SELECT count(*) AS inserted_count FROM inserted_audit
  ) AS audit_count
  WHERE access_count.inserted_count = 2
    AND audit_count.inserted_count = 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target pair preview is forbidden';
  END IF;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.list_personal_project_contexts(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (
  app_user_id uuid,
  workspace_id uuid,
  workspace_kind text,
  workspace_name text,
  project_id uuid,
  project_name text,
  questionnaire_version_id uuid,
  questionnaire_version_number integer,
  capabilities text[],
  is_current boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  resolved_project_id uuid;
BEGIN
  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = identity_row.app_user_id
   AND user_row.status = 'active'
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject;
  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'trusted identity is not mapped to an active app user';
  END IF;
  SELECT workspace_row.workspace_id INTO STRICT resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = resolved_app_user_id
    AND workspace_row.deleted_at IS NULL;
  SELECT current_row.project_id INTO resolved_project_id
  FROM app_data.user_current_projects AS current_row
  JOIN app_data.projects AS project_row
    ON project_row.project_id = current_row.project_id
   AND project_row.workspace_id = resolved_workspace_id
   AND project_row.status = 'active'
  WHERE current_row.app_user_id = resolved_app_user_id;
  IF resolved_project_id IS NULL THEN
    SELECT project_row.project_id INTO STRICT resolved_project_id
    FROM app_data.projects AS project_row
    WHERE project_row.workspace_id = resolved_workspace_id
      AND project_row.is_personal_default
      AND project_row.status = 'active';
    INSERT INTO app_data.user_current_projects (app_user_id, project_id)
    VALUES (resolved_app_user_id, resolved_project_id)
    ON CONFLICT ON CONSTRAINT user_current_projects_pkey DO UPDATE
      SET project_id = EXCLUDED.project_id,
          updated_at = clock_timestamp();
  END IF;
  RETURN QUERY
  SELECT
    resolved_app_user_id,
    workspace_row.workspace_id,
    workspace_row.workspace_kind,
    workspace_row.display_name,
    project_row.project_id,
    project_row.display_name,
    version_row.questionnaire_version_id,
    version_row.version_number,
    ARRAY[
      'record_contact',
      'manage_analysis_definitions',
      'create_target',
      'view_assigned_target_pii',
      'manage_assigned_target_follow_up',
      'manage_assigned_target_relations',
      'import_target_pii',
      'export_target_pii',
      'manage_assigned_target_merges'
    ]::text[],
    project_row.project_id = resolved_project_id
  FROM app_data.workspaces AS workspace_row
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
   AND project_row.status = 'active'
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.project_id = project_row.project_id
   AND version_row.is_current
   AND version_row.status = 'published'
  WHERE workspace_row.workspace_id = resolved_workspace_id
  ORDER BY
    (project_row.project_id = resolved_project_id) DESC,
    project_row.is_personal_default DESC,
    project_row.created_at,
    project_row.project_id;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.bump_promotion_target_profile_revision_v1(),
  app_private.validate_personal_target_pair_preview_v1(
    uuid, uuid, uuid, timestamptz
  ),
  app_private.cleanup_personal_target_pair_preview_receipts_v1(),
  app_data.preview_personal_target_pair_v1(text, text, uuid, uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER TABLE app_private.personal_target_pair_preview_receipts OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_pair_preview_audit_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.bump_promotion_target_profile_revision_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.validate_personal_target_pair_preview_v1(uuid,uuid,uuid,timestamptz) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.cleanup_personal_target_pair_preview_receipts_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.preview_personal_target_pair_v1(text,text,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
