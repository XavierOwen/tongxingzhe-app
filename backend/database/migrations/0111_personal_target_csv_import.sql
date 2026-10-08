-- 0111_personal_target_csv_import.sql
-- Store bounded, value-free preview receipts and atomically confirm selected rows.

CREATE TABLE app_private.personal_target_csv_import_previews (
  preview_id uuid PRIMARY KEY,
  contract_id text NOT NULL CHECK (
    contract_id = 'personal-target-csv-import-preview:v1'
  ),
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  rows_fingerprint bytea NOT NULL CHECK (octet_length(rows_fingerprint) = 32),
  row_count integer NOT NULL CHECK (row_count BETWEEN 0 AND 500),
  hinted_rows integer[] NOT NULL,
  previewed_at_utc timestamptz NOT NULL CHECK (isfinite(previewed_at_utc)),
  expires_at_utc timestamptz NOT NULL CHECK (
    isfinite(expires_at_utc)
    AND expires_at_utc = previewed_at_utc + interval '15 minutes'
  )
);

CREATE TABLE app_private.personal_target_csv_import_request_claims (
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  preview_id uuid NOT NULL UNIQUE,
  request_id uuid NOT NULL,
  rows_fingerprint bytea NOT NULL CHECK (octet_length(rows_fingerprint) = 32),
  actions jsonb NOT NULL CHECK (jsonb_typeof(actions) = 'array'),
  outcome text NOT NULL CHECK (outcome IN ('confirmed', 'stale_preview')),
  row_count integer NOT NULL CHECK (row_count BETWEEN 0 AND 500),
  hint_count integer NOT NULL CHECK (hint_count BETWEEN 0 AND 500),
  created_count integer NOT NULL CHECK (created_count BETWEEN 0 AND row_count),
  created_targets jsonb NOT NULL CHECK (jsonb_typeof(created_targets) = 'array'),
  completed_at_utc timestamptz NOT NULL CHECK (isfinite(completed_at_utc)),
  PRIMARY KEY (actor_app_user_id, request_id)
);

CREATE TABLE app_private.personal_target_csv_import_audit_events (
  audit_event_id uuid PRIMARY KEY,
  contract_id text NOT NULL CHECK (
    contract_id IN (
      'personal-target-csv-import-preview:v1',
      'personal-target-csv-import-confirm:v1'
    )
  ),
  actor_app_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  preview_id uuid NOT NULL,
  request_id uuid,
  phase text NOT NULL CHECK (phase IN ('preview', 'confirm')),
  outcome text NOT NULL CHECK (
    outcome IN ('previewed', 'confirmed', 'stale_preview')
  ),
  row_count integer NOT NULL CHECK (row_count BETWEEN 0 AND 500),
  hint_count integer NOT NULL CHECK (hint_count BETWEEN 0 AND 500),
  created_count integer NOT NULL CHECK (created_count BETWEEN 0 AND row_count),
  source_kind text NOT NULL CHECK (source_kind = 'csv'),
  occurred_at_utc timestamptz NOT NULL CHECK (isfinite(occurred_at_utc)),
  CHECK (
    (phase = 'preview' AND request_id IS NULL AND outcome = 'previewed'
      AND created_count = 0)
    OR
    (phase = 'confirm' AND request_id IS NOT NULL
      AND outcome IN ('confirmed', 'stale_preview'))
  )
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_csv_import_previews,
  app_private.personal_target_csv_import_request_claims,
  app_private.personal_target_csv_import_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.reject_personal_target_csv_import_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'personal target CSV import records are immutable';
END
$function$;

CREATE TRIGGER personal_target_csv_import_previews_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_csv_import_previews
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_csv_import_mutation_v1();

CREATE TRIGGER personal_target_csv_import_request_claims_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_csv_import_request_claims
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_csv_import_mutation_v1();

CREATE TRIGGER personal_target_csv_import_audit_events_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_csv_import_audit_events
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_csv_import_mutation_v1();

CREATE FUNCTION app_private.canonical_personal_target_csv_import_rows_v1(
  requested_rows jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  row_value jsonb;
  target_type_value text;
  display_name_value text;
  phone_value text;
  email_value text;
  normalized_rows jsonb := '[]'::jsonb;
  row_count_value integer;
BEGIN
  IF requested_rows IS NULL OR jsonb_typeof(requested_rows) <> 'array' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import rows';
  END IF;

  row_count_value := jsonb_array_length(requested_rows);
  IF row_count_value > 500 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import rows';
  END IF;

  FOR row_value IN SELECT value FROM jsonb_array_elements(requested_rows)
  LOOP
    IF jsonb_typeof(row_value) <> 'object'
      OR row_value - ARRAY[
        'target_type', 'display_name', 'phone', 'email'
      ] <> '{}'::jsonb
      OR NOT row_value ?& ARRAY[
        'target_type', 'display_name', 'phone', 'email'
      ]
      OR jsonb_typeof(row_value->'target_type') <> 'string'
      OR jsonb_typeof(row_value->'display_name') <> 'string'
      OR jsonb_typeof(row_value->'phone') NOT IN ('string', 'null')
      OR jsonb_typeof(row_value->'email') NOT IN ('string', 'null')
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid personal target CSV import rows';
    END IF;

    target_type_value := row_value->>'target_type';
    display_name_value := btrim(row_value->>'display_name');
    phone_value := nullif(btrim(row_value->>'phone'), '');
    email_value := nullif(btrim(row_value->>'email'), '');
    IF target_type_value NOT IN ('person', 'institution')
      OR length(display_name_value) NOT BETWEEN 1 AND 200
      OR (phone_value IS NOT NULL AND length(phone_value) NOT BETWEEN 1 AND 80)
      OR (email_value IS NOT NULL AND length(email_value) NOT BETWEEN 1 AND 320)
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid personal target CSV import rows';
    END IF;

    normalized_rows := normalized_rows || jsonb_build_array(
      jsonb_build_object(
        'target_type', target_type_value,
        'display_name', display_name_value,
        'phone', phone_value,
        'email', email_value
      )
    );
  END LOOP;

  RETURN normalized_rows;
END
$function$;

-- Domain-separated SHA-256 binds a receipt to canonical rows; it is not PII
-- encryption, so the digest remains private.
CREATE FUNCTION app_private.personal_target_csv_import_fingerprint_v1(
  requested_preview_id uuid,
  canonical_rows jsonb
)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
  SELECT sha256(convert_to(jsonb_build_object(
    'fingerprint_contract', 'personal-target-csv-import-preview:v1',
    'preview_id', requested_preview_id,
    'rows', canonical_rows
  )::text, 'UTF8'))
$function$;

CREATE FUNCTION app_private.personal_target_csv_import_hint_rows_v1(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  canonical_rows jsonb
)
RETURNS integer[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT COALESCE(array_agg(row_item.ordinality::integer ORDER BY row_item.ordinality),
    ARRAY[]::integer[])
  FROM jsonb_array_elements(canonical_rows) WITH ORDINALITY AS row_item(value, ordinality)
  WHERE EXISTS (
    SELECT 1
    FROM jsonb_array_elements(canonical_rows) WITH ORDINALITY AS other_item(value, ordinality)
    WHERE other_item.ordinality <> row_item.ordinality
      AND (
        (row_item.value->>'phone' IS NOT NULL
          AND row_item.value->>'phone' = other_item.value->>'phone')
        OR
        (row_item.value->>'email' IS NOT NULL
          AND lower(row_item.value->>'email') = lower(other_item.value->>'email'))
      )
  ) OR EXISTS (
    SELECT 1
    FROM app_data.promotion_targets AS target_row
    JOIN app_data.promotion_target_assignments AS assignment_row
      ON assignment_row.promotion_target_id = target_row.promotion_target_id
     AND assignment_row.app_user_id = trusted_app_user_id
     AND assignment_row.ended_at IS NULL
    WHERE target_row.workspace_id = trusted_workspace_id
      AND target_row.status = 'active'
      AND (
        (row_item.value->>'phone' IS NOT NULL
          AND target_row.phone = row_item.value->>'phone')
        OR
        (row_item.value->>'email' IS NOT NULL
          AND lower(target_row.email) = lower(row_item.value->>'email'))
      )
  )
$function$;

CREATE FUNCTION app_private.resolve_personal_target_csv_import_context_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid
)
RETURNS TABLE (app_user_id uuid, workspace_id uuid)
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR trusted_subject IS NULL
    OR requested_project_id IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import identity';
  END IF;

  SELECT app_user.app_user_id, workspace_row.workspace_id
  INTO resolved_app_user_id, resolved_workspace_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.personal_owner_app_user_id = app_user.app_user_id
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active'
    AND workspace_row.workspace_kind = 'personal'
    AND workspace_row.deleted_at IS NULL
    AND project_row.project_id = requested_project_id
    AND project_row.status = 'active'
  FOR SHARE OF identity_row, app_user, workspace_row, project_row;

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target CSV import scope is forbidden';
  END IF;

  RETURN QUERY SELECT resolved_app_user_id, resolved_workspace_id;
END
$function$;

CREATE FUNCTION app_private.personal_target_csv_import_actions_v1(
  requested_actions jsonb,
  hinted_rows integer[],
  row_count integer
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  action_value jsonb;
  action_text text;
  row_number integer := 0;
  normalized_actions jsonb := '[]'::jsonb;
  hint_set integer[] := COALESCE(hinted_rows, ARRAY[]::integer[]);
BEGIN
  IF requested_actions IS NULL
    OR jsonb_typeof(requested_actions) <> 'array'
    OR jsonb_array_length(requested_actions) <> row_count
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import actions';
  END IF;

  FOR action_value IN SELECT value FROM jsonb_array_elements(requested_actions)
  LOOP
    row_number := row_number + 1;
    IF jsonb_typeof(action_value) <> 'string' THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid personal target CSV import actions';
    END IF;
    action_text := action_value#>>'{}';
    IF (row_number = ANY(hint_set)
        AND action_text NOT IN ('skip', 'create_separate'))
      OR (NOT row_number = ANY(hint_set)
        AND action_text NOT IN ('skip', 'create'))
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid personal target CSV import actions';
    END IF;
    normalized_actions := normalized_actions || jsonb_build_array(action_text);
  END LOOP;

  RETURN normalized_actions;
END
$function$;

CREATE FUNCTION app_data.preview_personal_target_csv_import_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_rows jsonb
)
RETURNS TABLE (
  contract_id text,
  preview_id uuid,
  row_count integer,
  hinted_rows integer[],
  previewed_at_utc timestamptz,
  expires_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  normalized_rows jsonb;
  resolved_preview_id uuid := pg_catalog.gen_random_uuid();
  resolved_row_count integer;
  resolved_hinted_rows integer[];
  resolved_previewed_at timestamptz;
  resolved_expires_at timestamptz;
BEGIN
  SELECT context_row.app_user_id, context_row.workspace_id
  INTO STRICT resolved_app_user_id, resolved_workspace_id
  FROM app_private.resolve_personal_target_csv_import_context_v1(
    trusted_issuer, trusted_subject, requested_project_id
  ) AS context_row;
  normalized_rows := app_private.canonical_personal_target_csv_import_rows_v1(
    requested_rows
  );
  resolved_row_count := jsonb_array_length(normalized_rows);
  resolved_hinted_rows := app_private.personal_target_csv_import_hint_rows_v1(
    resolved_app_user_id, resolved_workspace_id, normalized_rows
  );
  resolved_previewed_at := pg_catalog.clock_timestamp();
  resolved_expires_at := resolved_previewed_at + interval '15 minutes';

  INSERT INTO app_private.personal_target_csv_import_previews (
    preview_id, contract_id, actor_app_user_id, workspace_id, project_id,
    rows_fingerprint, row_count, hinted_rows, previewed_at_utc, expires_at_utc
  ) VALUES (
    resolved_preview_id,
    'personal-target-csv-import-preview:v1',
    resolved_app_user_id,
    resolved_workspace_id,
    requested_project_id,
    app_private.personal_target_csv_import_fingerprint_v1(
      resolved_preview_id, normalized_rows
    ),
    resolved_row_count,
    resolved_hinted_rows,
    resolved_previewed_at,
    resolved_expires_at
  );

  INSERT INTO app_private.personal_target_csv_import_audit_events (
    audit_event_id, contract_id, actor_app_user_id, workspace_id,
    preview_id, request_id, phase, outcome, row_count, hint_count,
    created_count, source_kind, occurred_at_utc
  ) VALUES (
    pg_catalog.gen_random_uuid(),
    'personal-target-csv-import-preview:v1',
    resolved_app_user_id,
    resolved_workspace_id,
    resolved_preview_id,
    NULL,
    'preview',
    'previewed',
    resolved_row_count,
    cardinality(resolved_hinted_rows),
    0,
    'csv',
    resolved_previewed_at
  );

  RETURN QUERY SELECT
    'personal-target-csv-import-preview:v1'::text,
    resolved_preview_id,
    resolved_row_count,
    resolved_hinted_rows,
    resolved_previewed_at,
    resolved_expires_at;
END
$function$;

CREATE FUNCTION app_data.confirm_personal_target_csv_import_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_preview_id uuid,
  requested_request_id uuid,
  requested_rows jsonb,
  requested_actions jsonb
)
RETURNS TABLE (
  contract_id text,
  preview_id uuid,
  request_id uuid,
  outcome text,
  row_count integer,
  hint_count integer,
  created_count integer,
  created_targets jsonb,
  completed_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  preview_row app_private.personal_target_csv_import_previews%ROWTYPE;
  claim_row app_private.personal_target_csv_import_request_claims%ROWTYPE;
  replay_hinted_rows integer[];
  normalized_rows jsonb;
  normalized_actions jsonb;
  submitted_fingerprint bytea;
  current_hinted_rows integer[];
  selected_row jsonb;
  action_text text;
  target_id uuid;
  targets_result jsonb := '[]'::jsonb;
  resolved_row_count integer;
  resolved_hint_count integer;
  resolved_created_count integer := 0;
  resolved_outcome text;
  resolved_checked_at timestamptz;
  resolved_completed_at timestamptz;
  row_number integer;
BEGIN
  IF requested_project_id IS NULL
    OR requested_preview_id IS NULL
    OR requested_request_id IS NULL
    OR trusted_issuer IS NULL
    OR trusted_subject IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import request';
  END IF;

  SELECT identity_row.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject;
  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target CSV import scope is forbidden';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'personal-target-csv-import-confirm:v1:'
        || resolved_app_user_id::text || ':' || requested_request_id::text,
      0
    )
  );

  SELECT claim.*
  INTO claim_row
  FROM app_private.personal_target_csv_import_request_claims AS claim
  WHERE claim.actor_app_user_id = resolved_app_user_id
    AND claim.request_id = requested_request_id;
  IF FOUND THEN
    SELECT context_row.app_user_id, context_row.workspace_id
    INTO STRICT resolved_app_user_id, resolved_workspace_id
    FROM app_private.resolve_personal_target_csv_import_context_v1(
      trusted_issuer, trusted_subject, requested_project_id
    ) AS context_row;
    IF claim_row.workspace_id <> resolved_workspace_id
      OR claim_row.project_id <> requested_project_id
      OR claim_row.preview_id <> requested_preview_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'personal target CSV import request conflict';
    END IF;
    SELECT preview.hinted_rows
    INTO STRICT replay_hinted_rows
    FROM app_private.personal_target_csv_import_previews AS preview
    WHERE preview.preview_id = requested_preview_id;
    BEGIN
      normalized_rows := app_private.canonical_personal_target_csv_import_rows_v1(
        requested_rows
      );
      submitted_fingerprint := app_private.personal_target_csv_import_fingerprint_v1(
        requested_preview_id, normalized_rows
      );
      normalized_actions := app_private.personal_target_csv_import_actions_v1(
        requested_actions,
        replay_hinted_rows,
        jsonb_array_length(normalized_rows)
      );
    EXCEPTION WHEN SQLSTATE '22023' THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'personal target CSV import request conflict';
    END;
    IF submitted_fingerprint <> claim_row.rows_fingerprint
      OR normalized_actions <> claim_row.actions
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'personal target CSV import request conflict';
    END IF;
    RETURN QUERY SELECT
      'personal-target-csv-import-confirm:v1'::text,
      claim_row.preview_id,
      claim_row.request_id,
      claim_row.outcome,
      claim_row.row_count,
      claim_row.hint_count,
      claim_row.created_count,
      claim_row.created_targets,
      claim_row.completed_at_utc;
    RETURN;
  END IF;

  SELECT preview.*
  INTO preview_row
  FROM app_private.personal_target_csv_import_previews AS preview
  WHERE preview.preview_id = requested_preview_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target CSV import scope is forbidden';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.personal_target_csv_import_request_claims AS claim
    WHERE claim.preview_id = requested_preview_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'personal target CSV import request conflict';
  END IF;

  SELECT context_row.app_user_id, context_row.workspace_id
  INTO STRICT resolved_app_user_id, resolved_workspace_id
  FROM app_private.resolve_personal_target_csv_import_context_v1(
    trusted_issuer, trusted_subject, requested_project_id
  ) AS context_row;
  IF preview_row.actor_app_user_id <> resolved_app_user_id
    OR preview_row.workspace_id <> resolved_workspace_id
    OR preview_row.project_id <> requested_project_id
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target CSV import scope is forbidden';
  END IF;

  BEGIN
    normalized_rows := app_private.canonical_personal_target_csv_import_rows_v1(
      requested_rows
    );
    resolved_row_count := jsonb_array_length(normalized_rows);
    normalized_actions := app_private.personal_target_csv_import_actions_v1(
      requested_actions, preview_row.hinted_rows, resolved_row_count
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target CSV import confirmation';
  END;

  submitted_fingerprint := app_private.personal_target_csv_import_fingerprint_v1(
    requested_preview_id, normalized_rows
  );
  current_hinted_rows := app_private.personal_target_csv_import_hint_rows_v1(
    resolved_app_user_id, resolved_workspace_id, normalized_rows
  );
  resolved_hint_count := cardinality(preview_row.hinted_rows);
  resolved_checked_at := pg_catalog.clock_timestamp();
  IF resolved_checked_at >= preview_row.expires_at_utc
    OR resolved_row_count <> preview_row.row_count
    OR submitted_fingerprint <> preview_row.rows_fingerprint
    OR current_hinted_rows <> preview_row.hinted_rows
  THEN
    resolved_outcome := 'stale_preview';
  ELSE
    resolved_outcome := 'confirmed';
    FOR selected_row, row_number IN
      SELECT row_item.value, row_item.ordinality::integer
      FROM jsonb_array_elements(normalized_rows) WITH ORDINALITY
        AS row_item(value, ordinality)
    LOOP
      action_text := normalized_actions->>(row_number - 1);
      IF action_text IN ('create', 'create_separate') THEN
        target_id := pg_catalog.gen_random_uuid();
        INSERT INTO app_data.promotion_targets (
          promotion_target_id, workspace_id, target_type, display_name,
          phone, email, created_by_app_user_id
        ) VALUES (
          target_id,
          resolved_workspace_id,
          selected_row->>'target_type',
          selected_row->>'display_name',
          selected_row->>'phone',
          selected_row->>'email',
          resolved_app_user_id
        );
        INSERT INTO app_data.promotion_target_assignments (
          promotion_target_id, app_user_id, assigned_by_app_user_id
        ) VALUES (target_id, resolved_app_user_id, resolved_app_user_id);
        INSERT INTO app_data.promotion_target_access_events (
          workspace_id, promotion_target_id, actor_app_user_id, action
        ) VALUES (
          resolved_workspace_id, target_id, resolved_app_user_id, 'created'
        );
        targets_result := targets_result || jsonb_build_array(
          jsonb_build_object('row_number', row_number, 'target_id', target_id)
        );
        resolved_created_count := resolved_created_count + 1;
      END IF;
    END LOOP;
  END IF;

  resolved_completed_at := pg_catalog.clock_timestamp();

  INSERT INTO app_private.personal_target_csv_import_request_claims (
    actor_app_user_id, workspace_id, project_id, preview_id, request_id,
    rows_fingerprint, actions, outcome, row_count, hint_count, created_count,
    created_targets, completed_at_utc
  ) VALUES (
    resolved_app_user_id,
    resolved_workspace_id,
    requested_project_id,
    requested_preview_id,
    requested_request_id,
    submitted_fingerprint,
    normalized_actions,
    resolved_outcome,
    resolved_row_count,
    resolved_hint_count,
    resolved_created_count,
    targets_result,
    resolved_completed_at
  );
  INSERT INTO app_private.personal_target_csv_import_audit_events (
    audit_event_id, contract_id, actor_app_user_id, workspace_id,
    preview_id, request_id, phase, outcome, row_count, hint_count,
    created_count, source_kind, occurred_at_utc
  ) VALUES (
    pg_catalog.gen_random_uuid(),
    'personal-target-csv-import-confirm:v1',
    resolved_app_user_id,
    resolved_workspace_id,
    requested_preview_id,
    requested_request_id,
    'confirm',
    resolved_outcome,
    resolved_row_count,
    resolved_hint_count,
    resolved_created_count,
    'csv',
    resolved_completed_at
  );

  RETURN QUERY SELECT
    'personal-target-csv-import-confirm:v1'::text,
    requested_preview_id,
    requested_request_id,
    resolved_outcome,
    resolved_row_count,
    resolved_hint_count,
    resolved_created_count,
    targets_result,
    resolved_completed_at;
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
      'import_target_pii'
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
  app_private.reject_personal_target_csv_import_mutation_v1(),
  app_private.canonical_personal_target_csv_import_rows_v1(jsonb),
  app_private.personal_target_csv_import_fingerprint_v1(uuid, jsonb),
  app_private.personal_target_csv_import_hint_rows_v1(uuid, uuid, jsonb),
  app_private.resolve_personal_target_csv_import_context_v1(text, text, uuid),
  app_private.personal_target_csv_import_actions_v1(jsonb, integer[], integer)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.preview_personal_target_csv_import_v1(text, text, uuid, jsonb),
  app_data.confirm_personal_target_csv_import_v1(
    text, text, uuid, uuid, uuid, jsonb, jsonb
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.preview_personal_target_csv_import_v1(text, text, uuid, jsonb),
  app_data.confirm_personal_target_csv_import_v1(
    text, text, uuid, uuid, uuid, jsonb, jsonb
  )
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
    'ALTER TABLE app_private.personal_target_csv_import_previews OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_csv_import_request_claims OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_csv_import_audit_events OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.reject_personal_target_csv_import_mutation_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.canonical_personal_target_csv_import_rows_v1(jsonb) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.personal_target_csv_import_fingerprint_v1(uuid,jsonb) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.personal_target_csv_import_hint_rows_v1(uuid,uuid,jsonb) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.resolve_personal_target_csv_import_context_v1(text,text,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.personal_target_csv_import_actions_v1(jsonb,integer[],integer) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.preview_personal_target_csv_import_v1(text,text,uuid,jsonb) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.confirm_personal_target_csv_import_v1(text,text,uuid,uuid,uuid,jsonb,jsonb) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
