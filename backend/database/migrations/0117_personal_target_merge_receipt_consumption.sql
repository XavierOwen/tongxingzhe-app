-- Consume each preview receipt once and make generation activation replayable.

CREATE TABLE app_private.personal_target_merge_activation_requests_v1 (
  actor_app_user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  preview_id uuid NOT NULL,
  retained_target_id uuid NOT NULL,
  display_name_source_target_id uuid NOT NULL,
  phone_source_target_id uuid NOT NULL,
  email_source_target_id uuid NOT NULL,
  generation_id uuid NOT NULL UNIQUE,
  activated_at_utc timestamptz NOT NULL CHECK (isfinite(activated_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id),
  UNIQUE (preview_id),
  FOREIGN KEY (generation_id)
    REFERENCES app_private.personal_target_merge_generations_v1 (generation_id)
    ON DELETE RESTRICT
);

CREATE TABLE app_private.personal_target_merge_activation_audit_v1 (
  audit_event_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  request_id uuid NOT NULL,
  operation text NOT NULL CHECK (
    operation = 'personal_target_merge_activation'
  ),
  outcome text NOT NULL CHECK (outcome = 'activated'),
  target_count integer NOT NULL CHECK (target_count = 2),
  occurred_at_utc timestamptz NOT NULL CHECK (isfinite(occurred_at_utc)),
  UNIQUE (actor_app_user_id, request_id)
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_merge_activation_requests_v1,
  app_private.personal_target_merge_activation_audit_v1
  FROM PUBLIC, tongxingzhe_runtime;

CREATE TRIGGER personal_target_merge_activation_requests_immutable
BEFORE UPDATE OR DELETE
ON app_private.personal_target_merge_activation_requests_v1
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_history_mutation_v1();

CREATE TRIGGER personal_target_merge_activation_audit_immutable
BEFORE UPDATE OR DELETE
ON app_private.personal_target_merge_activation_audit_v1
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.activate_personal_target_merge_generation_v2(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_request_id uuid,
  requested_preview_id uuid,
  requested_retained_target_id uuid,
  requested_display_name_source_target_id uuid,
  requested_phone_source_target_id uuid,
  requested_email_source_target_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  trusted_workspace_id uuid;
  replay_row app_private.personal_target_merge_activation_requests_v1%ROWTYPE;
  created_generation_id uuid;
BEGIN
  IF trusted_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_request_id IS NULL
    OR requested_preview_id IS NULL
    OR requested_retained_target_id IS NULL
    OR requested_display_name_source_target_id IS NULL
    OR requested_phone_source_target_id IS NULL
    OR requested_email_source_target_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid personal target merge activation request';
  END IF;

  SELECT workspace_row.workspace_id INTO trusted_workspace_id
  FROM app_data.workspaces AS workspace_row
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
   AND project_row.project_id = requested_project_id
   AND project_row.status = 'active'
  JOIN app_data.user_current_projects AS current_project
    ON current_project.app_user_id = trusted_app_user_id
   AND current_project.project_id = project_row.project_id
  JOIN app_data.app_users AS actor
    ON actor.app_user_id = trusted_app_user_id
   AND actor.status = 'active'
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
    AND workspace_row.deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target merge generation activation is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || requested_request_id::text, 0
  ));
  IF NOT app_data.promotion_target_context_authorized(
      trusted_app_user_id, trusted_workspace_id, requested_project_id
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.user_current_projects AS current_project
      WHERE current_project.app_user_id = trusted_app_user_id
        AND current_project.project_id = requested_project_id
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target merge generation activation is forbidden';
  END IF;

  SELECT request_row.* INTO replay_row
  FROM app_private.personal_target_merge_activation_requests_v1 AS request_row
  WHERE request_row.actor_app_user_id = trusted_app_user_id
    AND request_row.request_id = requested_request_id;
  IF FOUND THEN
    IF replay_row.workspace_id <> trusted_workspace_id
      OR replay_row.preview_id <> requested_preview_id
      OR replay_row.retained_target_id <> requested_retained_target_id
      OR replay_row.display_name_source_target_id <>
        requested_display_name_source_target_id
      OR replay_row.phone_source_target_id <> requested_phone_source_target_id
      OR replay_row.email_source_target_id <> requested_email_source_target_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '23505',
        MESSAGE = 'personal target merge activation request was reused';
    END IF;
    RETURN replay_row.generation_id;
  END IF;

  PERFORM app_private.acquire_personal_target_merge_generation_fence_v1();

  PERFORM 1
  FROM app_private.personal_target_pair_preview_receipts AS receipt
  WHERE receipt.preview_id = requested_preview_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target merge generation activation is forbidden';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.personal_target_merge_activation_requests_v1 AS request_row
    WHERE request_row.preview_id = requested_preview_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505',
      MESSAGE = 'personal target merge preview receipt was already consumed';
  END IF;

  WITH timing AS MATERIALIZED (
    SELECT pg_catalog.clock_timestamp() AS activated_at_utc
  ),
  validated AS MATERIALIZED (
    SELECT
      receipt.*,
      first_target.target_type,
      timing.activated_at_utc
    FROM timing
    CROSS JOIN LATERAL
      app_private.validate_personal_target_pair_preview_v1(
        trusted_app_user_id,
        requested_project_id,
        requested_preview_id,
        timing.activated_at_utc
      ) AS receipt
    JOIN app_data.promotion_targets AS first_target
      ON first_target.promotion_target_id = receipt.first_target_id
     AND first_target.workspace_id = receipt.workspace_id
    JOIN app_data.promotion_targets AS second_target
      ON second_target.promotion_target_id = receipt.second_target_id
     AND second_target.workspace_id = receipt.workspace_id
     AND second_target.target_type = first_target.target_type
    WHERE requested_retained_target_id IN (
        receipt.first_target_id, receipt.second_target_id
      )
      AND requested_display_name_source_target_id IN (
        receipt.first_target_id, receipt.second_target_id
      )
      AND requested_phone_source_target_id IN (
        receipt.first_target_id, receipt.second_target_id
      )
      AND requested_email_source_target_id IN (
        receipt.first_target_id, receipt.second_target_id
      )
  ),
  eligible AS MATERIALIZED (
    SELECT validated.*
    FROM validated
    WHERE NOT EXISTS (
      SELECT 1
      FROM app_private.personal_target_merge_active_members_v1 AS active_row
      WHERE active_row.promotion_target_id IN (
        validated.first_target_id,
        validated.second_target_id
      )
    )
  ),
  created AS (
    INSERT INTO app_private.personal_target_merge_generations_v1 (
      generation_id,
      workspace_id,
      target_type,
      created_by_app_user_id,
      activated_at_utc
    )
    SELECT
      pg_catalog.gen_random_uuid(),
      eligible.workspace_id,
      eligible.target_type,
      trusted_app_user_id,
      eligible.activated_at_utc
    FROM eligible
    RETURNING generation_id, workspace_id, target_type, activated_at_utc
  ),
  members AS (
    INSERT INTO app_private.personal_target_merge_generation_members_v1 (
      generation_id,
      workspace_id,
      target_type,
      promotion_target_id
    )
    SELECT
      created.generation_id,
      created.workspace_id,
      created.target_type,
      target_id.promotion_target_id
    FROM created
    JOIN eligible USING (workspace_id, target_type)
    CROSS JOIN LATERAL (
      VALUES (eligible.first_target_id), (eligible.second_target_id)
    ) AS target_id(promotion_target_id)
    RETURNING generation_id, workspace_id, target_type, promotion_target_id
  ),
  active_members AS (
    INSERT INTO app_private.personal_target_merge_active_members_v1 (
      promotion_target_id,
      generation_id,
      workspace_id,
      target_type
    )
    SELECT
      promotion_target_id,
      generation_id,
      workspace_id,
      target_type
    FROM members
    RETURNING promotion_target_id
  ),
  request_result AS (
    INSERT INTO app_private.personal_target_merge_activation_requests_v1 (
      actor_app_user_id,
      request_id,
      workspace_id,
      preview_id,
      retained_target_id,
      display_name_source_target_id,
      phone_source_target_id,
      email_source_target_id,
      generation_id,
      activated_at_utc
    )
    SELECT
      trusted_app_user_id,
      requested_request_id,
      created.workspace_id,
      requested_preview_id,
      requested_retained_target_id,
      requested_display_name_source_target_id,
      requested_phone_source_target_id,
      requested_email_source_target_id,
      created.generation_id,
      created.activated_at_utc
    FROM created
    CROSS JOIN (SELECT count(*) AS member_count FROM members) AS member_count
    CROSS JOIN (
      SELECT count(*) AS active_member_count FROM active_members
    ) AS active_member_count
    WHERE member_count.member_count = 2
      AND active_member_count.active_member_count = 2
    RETURNING actor_app_user_id, workspace_id, request_id, generation_id,
      activated_at_utc
  ),
  audit AS (
    INSERT INTO app_private.personal_target_merge_activation_audit_v1 (
      audit_event_id,
      actor_app_user_id,
      workspace_id,
      request_id,
      operation,
      outcome,
      target_count,
      occurred_at_utc
    )
    SELECT
      pg_catalog.gen_random_uuid(),
      request_result.actor_app_user_id,
      request_result.workspace_id,
      request_result.request_id,
      'personal_target_merge_activation',
      'activated',
      2,
      request_result.activated_at_utc
    FROM request_result
    RETURNING audit_event_id
  )
  SELECT request_result.generation_id INTO created_generation_id
  FROM request_result
  CROSS JOIN (SELECT count(*) AS audit_count FROM audit) AS audit_count
  WHERE audit_count.audit_count = 1;

  IF created_generation_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'personal target merge generation activation is forbidden';
  END IF;
  RETURN created_generation_id;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.activate_personal_target_merge_generation_v2(
    uuid, uuid, uuid, uuid, uuid, uuid, uuid, uuid
  )
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
    'ALTER TABLE app_private.personal_target_merge_activation_requests_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_merge_activation_audit_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.activate_personal_target_merge_generation_v2(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
