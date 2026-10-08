-- Prepare personal target PII bytes and their value-free audit atomically.

CREATE TABLE app_private.personal_target_pii_export_events (
  export_event_id uuid PRIMARY KEY,
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  export_contract_id text NOT NULL CHECK (
    export_contract_id = 'personal_promotion_target_pii_export_v1'
  ),
  authentication_method text NOT NULL CHECK (
    authentication_method = 'password'
  ),
  authenticated_at_utc timestamptz NOT NULL CHECK (
    isfinite(authenticated_at_utc)
  ),
  result text NOT NULL CHECK (result = 'prepared'),
  target_count integer NOT NULL CHECK (target_count >= 0),
  byte_count integer NOT NULL CHECK (byte_count >= 0),
  prepared_at_utc timestamptz NOT NULL CHECK (isfinite(prepared_at_utc))
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_pii_export_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.reject_personal_target_pii_export_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'personal target PII export events are immutable';
END
$function$;

CREATE TRIGGER personal_target_pii_export_events_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_pii_export_events
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_pii_export_mutation_v1();

CREATE FUNCTION app_private.prepare_personal_target_pii_export_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  trusted_password_authenticated_at timestamptz
)
RETURNS bytea
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_workspace_id uuid;
  resolved_event_id uuid := pg_catalog.gen_random_uuid();
  resolved_prepared_at timestamptz := transaction_timestamp();
  resolved_exported_at text;
  resolved_targets text := '';
  resolved_target_count integer := 0;
  resolved_payload text;
  resolved_bytes bytea;
  target_row app_data.promotion_targets%ROWTYPE;
  current_project_id uuid;
BEGIN
  IF trusted_password_authenticated_at IS NULL
    OR NOT isfinite(trusted_password_authenticated_at)
    OR trusted_password_authenticated_at > resolved_prepared_at + interval '60 seconds'
    OR trusted_password_authenticated_at <= resolved_prepared_at - interval '15 minutes'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target PII export authentication evidence';
  END IF;

  PERFORM 1
  FROM app_data.app_users AS user_row
  WHERE user_row.app_user_id = trusted_app_user_id
    AND user_row.status = 'active'
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target PII export scope is forbidden';
  END IF;

  SELECT workspace_row.workspace_id INTO resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
    AND workspace_row.deleted_at IS NULL
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target PII export scope is forbidden';
  END IF;

  SELECT current_row.project_id INTO current_project_id
  FROM app_data.user_current_projects AS current_row
  WHERE current_row.app_user_id = trusted_app_user_id
    AND current_row.project_id = requested_project_id
  FOR SHARE;
  IF NOT FOUND OR requested_project_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target PII export scope is forbidden';
  END IF;

  PERFORM 1
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = requested_project_id
    AND project_row.workspace_id = resolved_workspace_id
    AND project_row.status = 'active'
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target PII export scope is forbidden';
  END IF;

  resolved_exported_at := pg_catalog.to_char(
    resolved_prepared_at AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  );

  -- Keep the established anonymization lock order: target before assignment.
  FOR target_row IN
    SELECT candidate.*
    FROM app_data.promotion_targets AS candidate
    WHERE candidate.workspace_id = resolved_workspace_id
      AND candidate.status = 'active'
      AND EXISTS (
        SELECT 1
        FROM app_data.promotion_target_assignments AS candidate_assignment
        WHERE candidate_assignment.promotion_target_id = candidate.promotion_target_id
          AND candidate_assignment.app_user_id = trusted_app_user_id
          AND candidate_assignment.ended_at IS NULL
      )
    ORDER BY candidate.created_at, candidate.promotion_target_id
    FOR SHARE OF candidate
  LOOP
    PERFORM 1
    FROM app_data.promotion_target_assignments AS assignment_row
    WHERE assignment_row.promotion_target_id = target_row.promotion_target_id
      AND assignment_row.app_user_id = trusted_app_user_id
      AND assignment_row.ended_at IS NULL
    FOR SHARE;
    IF FOUND THEN
      IF resolved_target_count > 0 THEN
        resolved_targets := resolved_targets || ',';
      END IF;
      resolved_targets := resolved_targets || '{'
        || '"target_type":' || pg_catalog.to_json(target_row.target_type)::text
        || ',"display_name":' || pg_catalog.to_json(target_row.display_name)::text
        || ',"phone":' || COALESCE(pg_catalog.to_json(target_row.phone)::text, 'null')
        || ',"email":' || COALESCE(pg_catalog.to_json(target_row.email)::text, 'null')
        || '}';
      resolved_target_count := resolved_target_count + 1;
    END IF;
  END LOOP;

  resolved_payload := '{'
    || '"export_contract_id":"personal_promotion_target_pii_export_v1"'
    || ',"export_event_id":' || pg_catalog.to_json(resolved_event_id::text)::text
    || ',"exported_at_utc":' || pg_catalog.to_json(resolved_exported_at)::text
    || ',"targets":[' || resolved_targets || ']'
    || '}';
  resolved_bytes := pg_catalog.convert_to(resolved_payload, 'UTF8');

  INSERT INTO app_private.personal_target_pii_export_events (
    export_event_id,
    actor_app_user_id,
    workspace_id,
    export_contract_id,
    authentication_method,
    authenticated_at_utc,
    result,
    target_count,
    byte_count,
    prepared_at_utc
  ) VALUES (
    resolved_event_id,
    trusted_app_user_id,
    resolved_workspace_id,
    'personal_promotion_target_pii_export_v1',
    'password',
    trusted_password_authenticated_at,
    'prepared',
    resolved_target_count,
    octet_length(resolved_bytes),
    resolved_prepared_at
  );

  RETURN resolved_bytes;
END
$function$;

CREATE FUNCTION app_data.prepare_personal_target_pii_export_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  trusted_password_authenticated_at timestamptz
)
RETURNS bytea
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR trusted_subject IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target PII export identity';
  END IF;

  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = identity_row.app_user_id
   AND user_row.status = 'active'
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
  FOR SHARE OF identity_row, user_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target PII export scope is forbidden';
  END IF;

  RETURN app_private.prepare_personal_target_pii_export_v1(
    resolved_app_user_id,
    requested_project_id,
    trusted_password_authenticated_at
  );
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
      'export_target_pii'
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
  app_private.reject_personal_target_pii_export_mutation_v1(),
  app_private.prepare_personal_target_pii_export_v1(uuid, uuid, timestamptz),
  app_data.prepare_personal_target_pii_export_v1(text, text, uuid, timestamptz)
  FROM PUBLIC;
REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.reject_personal_target_pii_export_mutation_v1(),
  app_private.prepare_personal_target_pii_export_v1(uuid, uuid, timestamptz)
  FROM tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.prepare_personal_target_pii_export_v1(text, text, uuid, timestamptz)
  TO tongxingzhe_runtime;

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
    'ALTER TABLE app_private.personal_target_pii_export_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.reject_personal_target_pii_export_mutation_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.prepare_personal_target_pii_export_v1(uuid,uuid,timestamptz) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.prepare_personal_target_pii_export_v1(text,text,uuid,timestamptz) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
