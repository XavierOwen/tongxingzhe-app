-- 0013_questionnaire_publishing.sql
--
-- 保存可编辑问卷草稿，并以项目级事务锁发布新的不可变版本。Backend 每次
-- 请求都重取可信上下文；这些函数仍独立复验个人空间所有权、项目状态和用户
-- 状态，避免把 UI 或先前取得的 capability 当成持续授权。

ALTER TABLE app_data.questionnaire_versions
  ADD COLUMN published_by_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  ADD COLUMN publication_note text,
  ADD CONSTRAINT questionnaire_versions_publication_note_valid CHECK (
    publication_note IS NULL
    OR length(btrim(publication_note)) BETWEEN 1 AND 500
  );

ALTER TABLE app_data.questionnaire_versions
  DROP CONSTRAINT questionnaire_versions_status_check,
  ADD CONSTRAINT questionnaire_versions_status_check CHECK (
    status IN ('publishing', 'published')
  );

CREATE FUNCTION app_data.questionnaire_questions_definition_valid(
  questions jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  question jsonb;
  option_row jsonb;
  rule_row jsonb;
  condition_row jsonb;
  source_question jsonb;
  question_type text;
  source_type text;
  operator_value text;
  operand jsonb;
  operand_item jsonb;
  question_ids text[] := ARRAY[]::text[];
  positions integer[] := ARRAY[]::integer[];
  option_ids text[];
  option_positions integer[];
  question_position integer;
  minimum_selections integer;
  maximum_selections integer;
BEGIN
  IF questions IS NULL OR jsonb_typeof(questions) <> 'array'
    OR jsonb_array_length(questions) > 100
  THEN
    RETURN false;
  END IF;

  FOR question IN SELECT value FROM jsonb_array_elements(questions)
  LOOP
    IF jsonb_typeof(question) <> 'object'
      OR question - ARRAY[
        'question_id', 'position', 'prompt', 'type', 'required',
        'allow_unknown', 'allow_refused', 'allow_not_applicable', 'options',
        'minimum_selections', 'maximum_selections', 'number_kind', 'unit',
        'minimum', 'maximum', 'maximum_length', 'display_rule'
      ]::text[] <> '{}'::jsonb
      OR jsonb_typeof(question->'question_id') IS DISTINCT FROM 'string'
      OR length(btrim(COALESCE(question->>'question_id', ''))) NOT BETWEEN 1 AND 120
      OR jsonb_typeof(question->'prompt') IS DISTINCT FROM 'string'
      OR length(btrim(COALESCE(question->>'prompt', ''))) NOT BETWEEN 1 AND 1000
      OR jsonb_typeof(question->'type') IS DISTINCT FROM 'string'
      OR jsonb_typeof(question->'position') IS DISTINCT FROM 'number'
      OR length(question->>'position') > 9
      OR question->>'position' !~ '^[1-9][0-9]*$'
      OR jsonb_typeof(question->'required') IS DISTINCT FROM 'boolean'
      OR jsonb_typeof(question->'allow_unknown') IS DISTINCT FROM 'boolean'
      OR jsonb_typeof(question->'allow_refused') IS DISTINCT FROM 'boolean'
      OR jsonb_typeof(question->'allow_not_applicable')
        IS DISTINCT FROM 'boolean'
    THEN
      RETURN false;
    END IF;

    question_position := (question->>'position')::integer;
    question_type := question->>'type';
    IF question_type NOT IN (
      'boolean', 'single_choice', 'ordinal_choice', 'multi_choice',
      'number', 'date', 'short_text', 'long_text'
    ) OR question->>'question_id' = ANY(question_ids)
      OR question_position = ANY(positions)
    THEN
      RETURN false;
    END IF;
    question_ids := array_append(question_ids, question->>'question_id');
    positions := array_append(positions, question_position);

    IF question_type IN ('single_choice', 'ordinal_choice', 'multi_choice') THEN
      IF jsonb_typeof(question->'options') IS DISTINCT FROM 'array'
        OR jsonb_array_length(question->'options') = 0
        OR jsonb_array_length(question->'options') > 50
      THEN
        RETURN false;
      END IF;
      option_ids := ARRAY[]::text[];
      option_positions := ARRAY[]::integer[];
      FOR option_row IN
        SELECT value FROM jsonb_array_elements(question->'options')
      LOOP
        IF jsonb_typeof(option_row) <> 'object'
          OR option_row - ARRAY['option_id', 'position', 'label']::text[]
            <> '{}'::jsonb
          OR jsonb_typeof(option_row->'option_id') IS DISTINCT FROM 'string'
          OR length(btrim(COALESCE(option_row->>'option_id', '')))
            NOT BETWEEN 1 AND 120
          OR jsonb_typeof(option_row->'label') IS DISTINCT FROM 'string'
          OR length(btrim(COALESCE(option_row->>'label', '')))
            NOT BETWEEN 1 AND 500
          OR jsonb_typeof(option_row->'position') IS DISTINCT FROM 'number'
          OR length(option_row->>'position') > 9
          OR option_row->>'position' !~ '^[1-9][0-9]*$'
          OR option_row->>'option_id' = ANY(option_ids)
          OR (option_row->>'position')::integer = ANY(option_positions)
        THEN
          RETURN false;
        END IF;
        option_ids := array_append(option_ids, option_row->>'option_id');
        option_positions := array_append(
          option_positions,
          (option_row->>'position')::integer
        );
      END LOOP;
    ELSIF question ? 'options' THEN
      RETURN false;
    END IF;

    IF question_type = 'multi_choice' THEN
      IF jsonb_typeof(question->'minimum_selections')
          IS DISTINCT FROM 'number'
        OR jsonb_typeof(question->'maximum_selections')
          IS DISTINCT FROM 'number'
        OR question->>'minimum_selections' !~ '^[1-9][0-9]*$'
        OR question->>'maximum_selections' !~ '^[1-9][0-9]*$'
      THEN
        RETURN false;
      END IF;
      minimum_selections := (question->>'minimum_selections')::integer;
      maximum_selections := (question->>'maximum_selections')::integer;
      IF maximum_selections < minimum_selections
        OR maximum_selections > jsonb_array_length(question->'options')
      THEN
        RETURN false;
      END IF;
    ELSIF question ? 'minimum_selections'
      OR question ? 'maximum_selections'
    THEN
      RETURN false;
    END IF;

    IF question_type = 'number' THEN
      IF jsonb_typeof(question->'number_kind') IS DISTINCT FROM 'string'
        OR question->>'number_kind' NOT IN ('integer', 'decimal')
        OR (
          question ? 'unit'
          AND (
            jsonb_typeof(question->'unit') IS DISTINCT FROM 'string'
            OR length(btrim(question->>'unit')) = 0
          )
        )
        OR (
          question ? 'minimum'
          AND jsonb_typeof(question->'minimum') IS DISTINCT FROM 'number'
        )
        OR (
          question ? 'maximum'
          AND jsonb_typeof(question->'maximum') IS DISTINCT FROM 'number'
        )
        OR (
          question ? 'minimum' AND question ? 'maximum'
          AND (question->>'minimum')::numeric > (question->>'maximum')::numeric
        )
      THEN
        RETURN false;
      END IF;
    ELSIF question ? 'number_kind' OR question ? 'unit'
      OR question ? 'minimum' OR question ? 'maximum'
    THEN
      RETURN false;
    END IF;

    IF question_type IN ('short_text', 'long_text') THEN
      IF jsonb_typeof(question->'maximum_length') IS DISTINCT FROM 'number'
        OR question->>'maximum_length' !~ '^[1-9][0-9]*$'
        OR length(question->>'maximum_length') > 9
      THEN
        RETURN false;
      END IF;
    ELSIF question ? 'maximum_length' THEN
      RETURN false;
    END IF;

    IF question ? 'display_rule' THEN
      rule_row := question->'display_rule';
      IF jsonb_typeof(rule_row) IS DISTINCT FROM 'object'
        OR rule_row - ARRAY['match', 'conditions']::text[] <> '{}'::jsonb
        OR jsonb_typeof(rule_row->'match') IS DISTINCT FROM 'string'
        OR rule_row->>'match' NOT IN ('all', 'any')
        OR jsonb_typeof(rule_row->'conditions') IS DISTINCT FROM 'array'
        OR jsonb_array_length(rule_row->'conditions') NOT BETWEEN 1 AND 20
      THEN
        RETURN false;
      END IF;
      FOR condition_row IN
        SELECT value FROM jsonb_array_elements(rule_row->'conditions')
      LOOP
        IF jsonb_typeof(condition_row) IS DISTINCT FROM 'object'
          OR condition_row - ARRAY[
            'source_question_id', 'operator', 'operand'
          ]::text[] <> '{}'::jsonb
          OR jsonb_typeof(condition_row->'source_question_id')
            IS DISTINCT FROM 'string'
          OR jsonb_typeof(condition_row->'operator')
            IS DISTINCT FROM 'string'
          OR length(btrim(COALESCE(
            condition_row->>'source_question_id', ''
          ))) NOT BETWEEN 1 AND 120
        THEN
          RETURN false;
        END IF;
        SELECT candidate INTO source_question
        FROM jsonb_array_elements(questions) AS source_rows(candidate)
        WHERE candidate->>'question_id' =
            condition_row->>'source_question_id'
          AND (candidate->>'position')::integer < question_position
        LIMIT 1;
        IF source_question IS NULL THEN
          RETURN false;
        END IF;
        source_type := source_question->>'type';
        operator_value := condition_row->>'operator';
        operand := condition_row->'operand';
        IF operator_value NOT IN (
          'equals', 'not_equals', 'in', 'contains', 'not_contains',
          'greater_than', 'greater_than_or_equal', 'less_than',
          'less_than_or_equal', 'between', 'is_answered', 'is_unanswered'
        ) THEN
          RETURN false;
        END IF;
        IF source_type IN ('short_text', 'long_text') THEN
          IF operator_value NOT IN ('is_answered', 'is_unanswered')
            OR condition_row ? 'operand'
          THEN
            RETURN false;
          END IF;
        ELSIF source_type = 'multi_choice' THEN
          IF operator_value NOT IN ('contains', 'not_contains')
            OR jsonb_typeof(operand) IS DISTINCT FROM 'string'
            OR NOT EXISTS (
              SELECT 1
              FROM jsonb_array_elements(
                source_question->'options'
              ) AS source_options(value)
              WHERE value->>'option_id' = operand #>> '{}'
            )
          THEN
            RETURN false;
          END IF;
        ELSIF source_type = 'boolean' THEN
          IF NOT (
            operator_value IN ('equals', 'not_equals')
              AND jsonb_typeof(operand) IS NOT DISTINCT FROM 'boolean'
            OR operator_value = 'in'
              AND jsonb_typeof(operand) IS NOT DISTINCT FROM 'array'
              AND jsonb_array_length(operand) > 0
          ) THEN
            RETURN false;
          END IF;
          IF operator_value = 'in' THEN
            FOR operand_item IN SELECT value FROM jsonb_array_elements(operand)
            LOOP
              IF jsonb_typeof(operand_item) IS DISTINCT FROM 'boolean' THEN
                RETURN false;
              END IF;
            END LOOP;
          END IF;
        ELSIF source_type IN ('single_choice', 'ordinal_choice') THEN
          IF NOT (
            operator_value IN ('equals', 'not_equals')
              AND jsonb_typeof(operand) IS NOT DISTINCT FROM 'string'
            OR operator_value = 'in'
              AND jsonb_typeof(operand) IS NOT DISTINCT FROM 'array'
              AND jsonb_array_length(operand) > 0
          ) THEN
            RETURN false;
          END IF;
          IF operator_value IN ('equals', 'not_equals') THEN
            IF NOT EXISTS (
              SELECT 1
              FROM jsonb_array_elements(
                source_question->'options'
              ) AS source_options(value)
              WHERE value->>'option_id' = operand #>> '{}'
            ) THEN
              RETURN false;
            END IF;
          ELSE
            FOR operand_item IN SELECT value FROM jsonb_array_elements(operand)
            LOOP
              IF jsonb_typeof(operand_item) IS DISTINCT FROM 'string'
                OR NOT EXISTS (
                  SELECT 1
                  FROM jsonb_array_elements(
                    source_question->'options'
                  ) AS source_options(value)
                  WHERE value->>'option_id' = operand_item #>> '{}'
                )
              THEN
                RETURN false;
              END IF;
            END LOOP;
          END IF;
        ELSIF source_type IN ('number', 'date') THEN
          IF operator_value NOT IN (
            'equals', 'not_equals', 'greater_than',
            'greater_than_or_equal', 'less_than', 'less_than_or_equal',
            'between'
          ) OR (
            operator_value = 'between'
            AND (
              jsonb_typeof(operand) IS DISTINCT FROM 'array'
              OR jsonb_array_length(operand) <> 2
            )
          ) THEN
            RETURN false;
          END IF;
          IF operator_value = 'between' THEN
            FOR operand_item IN SELECT value FROM jsonb_array_elements(operand)
            LOOP
              IF (
                source_type = 'number'
                AND jsonb_typeof(operand_item) IS DISTINCT FROM 'number'
              ) OR (
                source_type = 'date'
                AND (
                  jsonb_typeof(operand_item) IS DISTINCT FROM 'string'
                  OR operand_item #>> '{}' !~
                    '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                  OR to_char(
                    to_date(operand_item #>> '{}', 'YYYY-MM-DD'),
                    'YYYY-MM-DD'
                  ) <> operand_item #>> '{}'
                )
              )
              THEN
                RETURN false;
              END IF;
            END LOOP;
            IF (
              source_type = 'number'
              AND (operand->>0)::numeric > (operand->>1)::numeric
            ) OR (
              source_type = 'date'
              AND operand->>0 > operand->>1
            ) THEN
              RETURN false;
            END IF;
          ELSIF (
            source_type = 'number'
            AND jsonb_typeof(operand) IS DISTINCT FROM 'number'
          ) OR (
            source_type = 'date'
            AND (
              jsonb_typeof(operand) IS DISTINCT FROM 'string'
              OR operand #>> '{}' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
              OR to_char(
                to_date(operand #>> '{}', 'YYYY-MM-DD'),
                'YYYY-MM-DD'
              ) <> operand #>> '{}'
            )
          )
          THEN
            RETURN false;
          END IF;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
  RETURN true;
EXCEPTION
  WHEN invalid_text_representation
    OR numeric_value_out_of_range
    OR invalid_datetime_format
    OR datetime_field_overflow
  THEN
    RETURN false;
END
$function$;

CREATE TABLE app_data.questionnaire_drafts (
  questionnaire_draft_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  source_questionnaire_version_id uuid
    REFERENCES app_data.questionnaire_versions (questionnaire_version_id)
    ON DELETE RESTRICT,
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  definition jsonb NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'published')),
  created_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  updated_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  published_questionnaire_version_id uuid
    REFERENCES app_data.questionnaire_versions (questionnaire_version_id)
    ON DELETE RESTRICT,
  CHECK (
    jsonb_typeof(definition) = 'object'
    AND definition - 'questions' = '{}'::jsonb
    AND app_data.questionnaire_questions_definition_valid(
      definition->'questions'
    )
  ),
  CHECK (
    (status = 'draft' AND published_questionnaire_version_id IS NULL)
    OR
    (status = 'published' AND published_questionnaire_version_id IS NOT NULL)
  )
);

CREATE INDEX questionnaire_drafts_project_status
  ON app_data.questionnaire_drafts (project_id, status, updated_at DESC);

CREATE TABLE app_data.questionnaire_publish_requests (
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  request_id text NOT NULL CHECK (
    length(btrim(request_id)) BETWEEN 1 AND 120
  ),
  questionnaire_draft_id uuid NOT NULL
    REFERENCES app_data.questionnaire_drafts (questionnaire_draft_id)
    ON DELETE RESTRICT,
  questionnaire_version_id uuid NOT NULL
    REFERENCES app_data.questionnaire_versions (questionnaire_version_id)
    ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (app_user_id, request_id)
);

REVOKE ALL PRIVILEGES
  ON app_data.questionnaire_drafts,
     app_data.questionnaire_publish_requests
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.questionnaire_management_authorized(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM app_data.app_users AS user_row
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.personal_owner_app_user_id = user_row.app_user_id
     AND workspace_row.workspace_kind = 'personal'
     AND workspace_row.deleted_at IS NULL
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
     AND project_row.status = 'active'
    WHERE user_row.app_user_id = trusted_app_user_id
      AND user_row.status = 'active'
      AND workspace_row.workspace_id = trusted_workspace_id
      AND project_row.project_id = trusted_project_id
  );
$function$;

CREATE FUNCTION app_data.questionnaire_draft_document(
  target_questionnaire_draft_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'draft_id', draft_row.questionnaire_draft_id,
    'project_id', draft_row.project_id,
    'source_version_id', draft_row.source_questionnaire_version_id,
    'revision', draft_row.revision,
    'updated_at', draft_row.updated_at,
    'definition', draft_row.definition
  )
  FROM app_data.questionnaire_drafts AS draft_row
  WHERE draft_row.questionnaire_draft_id = target_questionnaire_draft_id;
$function$;

CREATE FUNCTION app_data.questionnaire_publication_document(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  target_questionnaire_version_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'questionnaire_version_id', version_row.questionnaire_version_id,
      'version_number', version_row.version_number,
      'is_current', version_row.is_current,
      'published_at', version_row.published_at,
      'published_by_app_user_id', version_row.published_by_app_user_id,
      'publication_note', version_row.publication_note
    ),
    'questionnaire', (
      SELECT questionnaire_definition
      FROM app_data.read_published_questionnaire(
        trusted_app_user_id,
        trusted_workspace_id,
        trusted_project_id,
        target_questionnaire_version_id
      )
    )
  )
  FROM app_data.questionnaire_versions AS version_row
  WHERE version_row.questionnaire_version_id = target_questionnaire_version_id
    AND version_row.project_id = trusted_project_id
    AND version_row.status = 'published';
$function$;

CREATE FUNCTION app_data.list_questionnaire_administration(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (administration jsonb)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'management forbidden';
  END IF;
  RETURN QUERY
  SELECT jsonb_build_object(
    'current_version_id', current_version.questionnaire_version_id,
    'versions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'questionnaire_version_id', version_row.questionnaire_version_id,
        'version_number', version_row.version_number,
        'is_current', version_row.is_current,
        'published_at', version_row.published_at,
        'published_by_app_user_id', version_row.published_by_app_user_id,
        'publication_note', version_row.publication_note
      ) ORDER BY version_row.version_number DESC)
      FROM app_data.questionnaire_versions AS version_row
      WHERE version_row.project_id = trusted_project_id
        AND version_row.status = 'published'
    ), '[]'::jsonb),
    'drafts', COALESCE((
      SELECT jsonb_agg(
        app_data.questionnaire_draft_document(
          draft_row.questionnaire_draft_id
        ) ORDER BY draft_row.updated_at DESC
      )
      FROM app_data.questionnaire_drafts AS draft_row
      WHERE draft_row.project_id = trusted_project_id
        AND draft_row.status = 'draft'
    ), '[]'::jsonb)
  )
  FROM app_data.questionnaire_versions AS current_version
  WHERE current_version.project_id = trusted_project_id
    AND current_version.status = 'published'
    AND current_version.is_current;
END
$function$;

CREATE FUNCTION app_data.create_questionnaire_draft(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  source_questionnaire_version_id uuid
)
RETURNS TABLE (draft jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  questions jsonb := '[]'::jsonb;
  created_draft_id uuid;
BEGIN
  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'management forbidden';
  END IF;
  IF source_questionnaire_version_id IS NOT NULL THEN
    SELECT questionnaire_definition->'questions' INTO questions
    FROM app_data.read_published_questionnaire(
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id,
      source_questionnaire_version_id
    );
    IF questions IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'source not found';
    END IF;
  END IF;
  INSERT INTO app_data.questionnaire_drafts (
    project_id,
    source_questionnaire_version_id,
    definition,
    created_by_app_user_id,
    updated_by_app_user_id
  ) VALUES (
    trusted_project_id,
    source_questionnaire_version_id,
    jsonb_build_object('questions', questions),
    trusted_app_user_id,
    trusted_app_user_id
  )
  RETURNING questionnaire_drafts.questionnaire_draft_id
    INTO created_draft_id;
  RETURN QUERY SELECT app_data.questionnaire_draft_document(created_draft_id);
END
$function$;

CREATE FUNCTION app_data.read_questionnaire_draft(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  target_questionnaire_draft_id uuid
)
RETURNS TABLE (draft jsonb)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'management forbidden';
  END IF;
  RETURN QUERY
  SELECT app_data.questionnaire_draft_document(
    draft_row.questionnaire_draft_id
  )
  FROM app_data.questionnaire_drafts AS draft_row
  WHERE draft_row.questionnaire_draft_id = target_questionnaire_draft_id
    AND draft_row.project_id = trusted_project_id;
END
$function$;

CREATE FUNCTION app_data.update_questionnaire_draft(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  target_questionnaire_draft_id uuid,
  expected_revision integer,
  candidate_questions jsonb
)
RETURNS TABLE (draft jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  updated_draft_id uuid;
BEGIN
  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'management forbidden';
  END IF;
  IF expected_revision < 1
    OR NOT app_data.questionnaire_questions_definition_valid(
      candidate_questions
    )
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid definition';
  END IF;
  UPDATE app_data.questionnaire_drafts AS draft_row
  SET definition = jsonb_build_object('questions', candidate_questions),
      revision = draft_row.revision + 1,
      updated_by_app_user_id = trusted_app_user_id,
      updated_at = clock_timestamp()
  WHERE draft_row.questionnaire_draft_id = target_questionnaire_draft_id
    AND draft_row.project_id = trusted_project_id
    AND draft_row.status = 'draft'
    AND draft_row.revision = expected_revision
  RETURNING draft_row.questionnaire_draft_id INTO updated_draft_id;
  IF updated_draft_id IS NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM app_data.questionnaire_drafts AS draft_row
      WHERE draft_row.questionnaire_draft_id = target_questionnaire_draft_id
        AND draft_row.project_id = trusted_project_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'draft not found';
    END IF;
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'draft changed';
  END IF;
  RETURN QUERY SELECT app_data.questionnaire_draft_document(updated_draft_id);
END
$function$;

CREATE FUNCTION app_data.publish_questionnaire_draft(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  target_questionnaire_draft_id uuid,
  expected_revision integer,
  publish_request_id text,
  requested_publication_note text
)
RETURNS TABLE (publication jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  draft_row app_data.questionnaire_drafts%ROWTYPE;
  existing_request app_data.questionnaire_publish_requests%ROWTYPE;
  created_version_id uuid;
  next_version_number integer;
  question jsonb;
  option_row jsonb;
  normalized_note text := btrim(requested_publication_note);
  normalized_request_id text := btrim(publish_request_id);
BEGIN
  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'management forbidden';
  END IF;
  IF expected_revision < 1 OR publish_request_id IS NULL
    OR length(normalized_request_id) NOT BETWEEN 1 AND 120
    OR length(normalized_note) NOT BETWEEN 1 AND 500
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid publication';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(trusted_project_id::text, 13)
  );
  SELECT * INTO existing_request
  FROM app_data.questionnaire_publish_requests AS request_row
  WHERE request_row.app_user_id = trusted_app_user_id
    AND request_row.request_id = normalized_request_id;
  IF FOUND THEN
    IF existing_request.questionnaire_draft_id <>
      target_questionnaire_draft_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'request reused';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM app_data.questionnaire_drafts AS request_draft
      WHERE request_draft.questionnaire_draft_id =
        target_questionnaire_draft_id
        AND request_draft.project_id = trusted_project_id
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'draft not found';
    END IF;
    RETURN QUERY SELECT app_data.questionnaire_publication_document(
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id,
      existing_request.questionnaire_version_id
    );
    RETURN;
  END IF;

  SELECT * INTO draft_row
  FROM app_data.questionnaire_drafts AS candidate
  WHERE candidate.questionnaire_draft_id = target_questionnaire_draft_id
    AND candidate.project_id = trusted_project_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'draft not found';
  END IF;

  IF draft_row.status = 'published' THEN
    created_version_id := draft_row.published_questionnaire_version_id;
  ELSE
    IF draft_row.revision <> expected_revision THEN
      RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'draft changed';
    END IF;
    IF jsonb_array_length(draft_row.definition->'questions') = 0
      OR NOT app_data.questionnaire_questions_definition_valid(
        draft_row.definition->'questions'
      )
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid definition';
    END IF;

    SELECT COALESCE(MAX(version_row.version_number), 0) + 1
      INTO next_version_number
    FROM app_data.questionnaire_versions AS version_row
    WHERE version_row.project_id = trusted_project_id;

    UPDATE app_data.questionnaire_versions AS version_row
    SET is_current = false
    WHERE version_row.project_id = trusted_project_id
      AND version_row.is_current;

    INSERT INTO app_data.questionnaire_versions (
      project_id,
      version_number,
      status,
      is_current,
      published_by_app_user_id,
      publication_note
    ) VALUES (
      trusted_project_id,
      next_version_number,
      'publishing',
      true,
      trusted_app_user_id,
      normalized_note
    ) RETURNING questionnaire_versions.questionnaire_version_id
      INTO created_version_id;

    FOR question IN
      SELECT value FROM jsonb_array_elements(draft_row.definition->'questions')
    LOOP
      INSERT INTO app_data.questionnaire_questions (
        questionnaire_version_id,
        question_id,
        position,
        prompt,
        question_type,
        is_required,
        allow_unknown,
        allow_refused,
        allow_not_applicable,
        minimum_selections,
        maximum_selections,
        number_kind,
        unit,
        minimum,
        maximum,
        maximum_length,
        display_rule
      ) VALUES (
        created_version_id,
        question->>'question_id',
        (question->>'position')::integer,
        question->>'prompt',
        question->>'type',
        (question->>'required')::boolean,
        (question->>'allow_unknown')::boolean,
        (question->>'allow_refused')::boolean,
        (question->>'allow_not_applicable')::boolean,
        NULLIF(question->>'minimum_selections', '')::integer,
        NULLIF(question->>'maximum_selections', '')::integer,
        question->>'number_kind',
        question->>'unit',
        NULLIF(question->>'minimum', '')::numeric,
        NULLIF(question->>'maximum', '')::numeric,
        NULLIF(question->>'maximum_length', '')::integer,
        question->'display_rule'
      );
      IF question ? 'options' THEN
        FOR option_row IN
          SELECT value FROM jsonb_array_elements(question->'options')
        LOOP
          INSERT INTO app_data.questionnaire_options (
            questionnaire_version_id,
            question_id,
            option_id,
            position,
            label
          ) VALUES (
            created_version_id,
            question->>'question_id',
            option_row->>'option_id',
            (option_row->>'position')::integer,
            option_row->>'label'
          );
        END LOOP;
      END IF;
    END LOOP;

    UPDATE app_data.questionnaire_versions AS version_row
    SET status = 'published'
    WHERE version_row.questionnaire_version_id = created_version_id;

    UPDATE app_data.questionnaire_drafts AS target
    SET status = 'published',
        published_questionnaire_version_id = created_version_id,
        updated_by_app_user_id = trusted_app_user_id,
        updated_at = clock_timestamp()
    WHERE target.questionnaire_draft_id = target_questionnaire_draft_id;
  END IF;

  INSERT INTO app_data.questionnaire_publish_requests (
    app_user_id,
    request_id,
    questionnaire_draft_id,
    questionnaire_version_id
  ) VALUES (
    trusted_app_user_id,
    normalized_request_id,
    target_questionnaire_draft_id,
    created_version_id
  );

  RETURN QUERY SELECT app_data.questionnaire_publication_document(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    created_version_id
  );
END
$function$;

CREATE FUNCTION app_data.enforce_questionnaire_definition_immutability()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  parent_status text;
  parent_publisher uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT version_row.status, version_row.published_by_app_user_id
      INTO parent_status, parent_publisher
    FROM app_data.questionnaire_versions AS version_row
    WHERE version_row.questionnaire_version_id =
      NEW.questionnaire_version_id;
    -- 新的管理端版本只在 publish transaction 的内部 building phase
    -- 接受定义行。published_by 为空的 pre-0013/bootstrap 版本仍允许旧 fixture
    -- 建立定义；runtime role 没有任何表级 INSERT 权限。
    IF parent_status = 'publishing' OR parent_publisher IS NULL THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'published questionnaire definitions are immutable';
END
$function$;

CREATE FUNCTION app_data.limit_published_questionnaire_version_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF OLD.status = 'publishing'
    AND NEW.status = 'published'
    AND NEW.questionnaire_version_id IS NOT DISTINCT FROM
      OLD.questionnaire_version_id
    AND NEW.project_id IS NOT DISTINCT FROM OLD.project_id
    AND NEW.version_number IS NOT DISTINCT FROM OLD.version_number
    AND NEW.is_current IS NOT DISTINCT FROM OLD.is_current
    AND NEW.published_at IS NOT DISTINCT FROM OLD.published_at
    AND NEW.published_by_app_user_id IS NOT DISTINCT FROM
      OLD.published_by_app_user_id
    AND NEW.publication_note IS NOT DISTINCT FROM OLD.publication_note
  THEN
    RETURN NEW;
  END IF;
  IF NEW.questionnaire_version_id IS DISTINCT FROM OLD.questionnaire_version_id
    OR NEW.project_id IS DISTINCT FROM OLD.project_id
    OR NEW.version_number IS DISTINCT FROM OLD.version_number
    OR NEW.status IS DISTINCT FROM OLD.status
    OR NEW.published_at IS DISTINCT FROM OLD.published_at
    OR NEW.published_by_app_user_id IS DISTINCT FROM OLD.published_by_app_user_id
    OR NEW.publication_note IS DISTINCT FROM OLD.publication_note
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'published questionnaire versions are immutable';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER questionnaire_versions_immutable
  BEFORE UPDATE ON app_data.questionnaire_versions
  FOR EACH ROW EXECUTE FUNCTION
    app_data.limit_published_questionnaire_version_update();

CREATE TRIGGER questionnaire_versions_no_delete
  BEFORE DELETE ON app_data.questionnaire_versions
  FOR EACH ROW EXECUTE FUNCTION
    app_data.enforce_questionnaire_definition_immutability();

CREATE TRIGGER questionnaire_questions_immutable
  BEFORE INSERT OR UPDATE OR DELETE ON app_data.questionnaire_questions
  FOR EACH ROW EXECUTE FUNCTION
    app_data.enforce_questionnaire_definition_immutability();

CREATE TRIGGER questionnaire_options_immutable
  BEFORE INSERT OR UPDATE OR DELETE ON app_data.questionnaire_options
  FOR EACH ROW EXECUTE FUNCTION
    app_data.enforce_questionnaire_definition_immutability();

-- 个人空间所有者管理自己的项目定义。组织成员能力表在组织 Slice 中建立；
-- 本迁移不把个人所有权扩展为任意组织管理权。
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
      'manage_analysis_definitions'
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

REVOKE ALL ON FUNCTION
  app_data.questionnaire_questions_definition_valid(jsonb),
  app_data.questionnaire_management_authorized(uuid, uuid, uuid),
  app_data.questionnaire_draft_document(uuid),
  app_data.questionnaire_publication_document(uuid, uuid, uuid, uuid),
  app_data.enforce_questionnaire_definition_immutability(),
  app_data.limit_published_questionnaire_version_update()
  FROM PUBLIC;

REVOKE ALL ON FUNCTION
  app_data.list_questionnaire_administration(uuid, uuid, uuid),
  app_data.create_questionnaire_draft(uuid, uuid, uuid, uuid),
  app_data.read_questionnaire_draft(uuid, uuid, uuid, uuid),
  app_data.update_questionnaire_draft(uuid, uuid, uuid, uuid, integer, jsonb),
  app_data.publish_questionnaire_draft(
    uuid, uuid, uuid, uuid, integer, text, text
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.list_questionnaire_administration(uuid, uuid, uuid),
  app_data.create_questionnaire_draft(uuid, uuid, uuid, uuid),
  app_data.read_questionnaire_draft(uuid, uuid, uuid, uuid),
  app_data.update_questionnaire_draft(uuid, uuid, uuid, uuid, integer, jsonb),
  app_data.publish_questionnaire_draft(
    uuid, uuid, uuid, uuid, integer, text, text
  )
  TO tongxingzhe_runtime;

REVOKE ALL ON FUNCTION app_data.list_personal_project_contexts(text, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_data.list_personal_project_contexts(text, text)
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.publish_questionnaire_draft(
    uuid, uuid, uuid, uuid, integer, text, text
) IS
  'Publishes one immutable version under a project lock and idempotency key.';
