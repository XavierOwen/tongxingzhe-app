ALTER TABLE app_data.questionnaire_questions
  ADD COLUMN display_rule jsonb,
  ADD CONSTRAINT questionnaire_questions_display_rule_check CHECK (
    display_rule IS NULL OR (
      jsonb_typeof(display_rule) = 'object'
      AND display_rule->>'match' IN ('all', 'any')
      AND jsonb_typeof(display_rule->'conditions') = 'array'
      AND jsonb_array_length(display_rule->'conditions') > 0
    )
  );

ALTER TABLE app_data.contact_answers
  ADD COLUMN answer_state_reason text,
  ADD CONSTRAINT contact_answers_state_reason_check CHECK (
    answer_state_reason IS NULL OR (
      answer_state = 'not_applicable'
      AND answer_state_reason = 'rule_skipped'
    )
  );

ALTER FUNCTION app_data.questionnaire_answer_errors(uuid, jsonb, boolean)
  RENAME TO questionnaire_answer_errors_v1;

CREATE FUNCTION app_data.questionnaire_visibility_condition_matches(
  target_questionnaire_version_id uuid,
  condition jsonb,
  submitted_answers jsonb,
  visible_question_ids text[]
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  source_question app_data.questionnaire_questions%ROWTYPE;
  source_answer jsonb;
  source_value jsonb;
  operator_value text := condition->>'operator';
  operand jsonb := condition->'operand';
  source_answer_is_valid boolean;
  bounds jsonb;
BEGIN
  SELECT * INTO source_question
  FROM app_data.questionnaire_questions AS question
  WHERE question.questionnaire_version_id = target_questionnaire_version_id
    AND question.question_id = condition->>'source_question_id';
  IF NOT FOUND OR NOT source_question.question_id = ANY(visible_question_ids) THEN
    RETURN false;
  END IF;
  SELECT answer INTO source_answer
  FROM jsonb_array_elements(submitted_answers) AS answers(answer)
  WHERE answer->>'questionId' = source_question.question_id
  LIMIT 1;
  source_answer_is_valid := source_answer IS NOT NULL
    AND source_answer->>'state' = 'answered'
    AND NULLIF(source_answer->>'stateReason', '') IS NULL
    AND cardinality(app_data.questionnaire_answer_errors_v1(
      target_questionnaire_version_id,
      jsonb_build_array(source_answer),
      false
    )) = 0;
  IF operator_value = 'is_answered' THEN
    RETURN source_answer_is_valid;
  ELSIF operator_value = 'is_unanswered' THEN
    RETURN NOT source_answer_is_valid;
  ELSIF NOT source_answer_is_valid THEN
    RETURN false;
  END IF;

  source_value := source_answer->'value';
  IF operator_value = 'equals' THEN
    RETURN source_value = operand;
  ELSIF operator_value = 'not_equals' THEN
    RETURN source_value <> operand;
  ELSIF operator_value = 'in' THEN
    RETURN jsonb_typeof(operand) = 'array'
      AND operand @> jsonb_build_array(source_value);
  ELSIF operator_value = 'contains' THEN
    RETURN jsonb_typeof(source_value) = 'array'
      AND source_value @> jsonb_build_array(operand);
  ELSIF operator_value = 'not_contains' THEN
    RETURN jsonb_typeof(source_value) = 'array'
      AND NOT source_value @> jsonb_build_array(operand);
  ELSIF operator_value IN (
    'greater_than', 'greater_than_or_equal',
    'less_than', 'less_than_or_equal'
  ) THEN
    IF source_question.question_type = 'number'
      AND jsonb_typeof(source_value) = 'number'
      AND jsonb_typeof(operand) = 'number'
    THEN
      RETURN CASE operator_value
        WHEN 'greater_than' THEN (source_value::text)::numeric > (operand::text)::numeric
        WHEN 'greater_than_or_equal' THEN (source_value::text)::numeric >= (operand::text)::numeric
        WHEN 'less_than' THEN (source_value::text)::numeric < (operand::text)::numeric
        ELSE (source_value::text)::numeric <= (operand::text)::numeric
      END;
    ELSIF source_question.question_type = 'date'
      AND jsonb_typeof(source_value) = 'string'
      AND jsonb_typeof(operand) = 'string'
    THEN
      RETURN CASE operator_value
        WHEN 'greater_than' THEN source_value #>> '{}' > operand #>> '{}'
        WHEN 'greater_than_or_equal' THEN source_value #>> '{}' >= operand #>> '{}'
        WHEN 'less_than' THEN source_value #>> '{}' < operand #>> '{}'
        ELSE source_value #>> '{}' <= operand #>> '{}'
      END;
    END IF;
    RETURN false;
  ELSIF operator_value = 'between'
    AND jsonb_typeof(operand) = 'array'
    AND jsonb_array_length(operand) = 2
  THEN
    bounds := operand;
    IF source_question.question_type = 'number'
      AND jsonb_typeof(source_value) = 'number'
      AND jsonb_typeof(bounds->0) = 'number'
      AND jsonb_typeof(bounds->1) = 'number'
    THEN
      RETURN (source_value::text)::numeric >= ((bounds->0)::text)::numeric
        AND (source_value::text)::numeric <= ((bounds->1)::text)::numeric;
    ELSIF source_question.question_type = 'date'
      AND jsonb_typeof(source_value) = 'string'
      AND jsonb_typeof(bounds->0) = 'string'
      AND jsonb_typeof(bounds->1) = 'string'
    THEN
      RETURN source_value #>> '{}' >= bounds->>0
        AND source_value #>> '{}' <= bounds->>1;
    END IF;
  END IF;
  RETURN false;
END
$function$;

CREATE FUNCTION app_data.questionnaire_visible_question_ids(
  target_questionnaire_version_id uuid,
  submitted_answers jsonb
)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  visible_ids text[] := ARRAY[]::text[];
  question_row app_data.questionnaire_questions%ROWTYPE;
  condition jsonb;
  condition_matches boolean;
  question_visible boolean;
BEGIN
  FOR question_row IN
    SELECT *
    FROM app_data.questionnaire_questions AS question
    WHERE question.questionnaire_version_id = target_questionnaire_version_id
    ORDER BY question.position
  LOOP
    IF question_row.display_rule IS NULL THEN
      visible_ids := array_append(visible_ids, question_row.question_id);
      CONTINUE;
    END IF;
    question_visible := question_row.display_rule->>'match' = 'all';
    FOR condition IN
      SELECT item
      FROM jsonb_array_elements(
        question_row.display_rule->'conditions'
      ) AS conditions(item)
    LOOP
      condition_matches := app_data.questionnaire_visibility_condition_matches(
        target_questionnaire_version_id,
        condition,
        submitted_answers,
        visible_ids
      );
      IF question_row.display_rule->>'match' = 'all' AND NOT condition_matches THEN
        question_visible := false;
        EXIT;
      ELSIF question_row.display_rule->>'match' = 'any' AND condition_matches THEN
        question_visible := true;
        EXIT;
      END IF;
    END LOOP;
    IF question_visible THEN
      visible_ids := array_append(visible_ids, question_row.question_id);
    END IF;
  END LOOP;
  RETURN visible_ids;
END
$function$;

CREATE FUNCTION app_data.questionnaire_answer_errors(
  target_questionnaire_version_id uuid,
  submitted_answers jsonb,
  require_complete boolean DEFAULT true
)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  errors text[] := ARRAY[]::text[];
  visible_ids text[];
  visible_and_unknown_answers jsonb;
  answer_row jsonb;
  question_row app_data.questionnaire_questions%ROWTYPE;
  submitted_answer_count integer;
BEGIN
  IF jsonb_typeof(submitted_answers) <> 'array' THEN
    RETURN ARRAY['invalid_answers:?'];
  END IF;
  visible_ids := app_data.questionnaire_visible_question_ids(
    target_questionnaire_version_id,
    submitted_answers
  );
  SELECT COALESCE(jsonb_agg(answer), '[]'::jsonb)
    INTO visible_and_unknown_answers
  FROM jsonb_array_elements(submitted_answers) AS answers(answer)
  WHERE NOT EXISTS (
      SELECT 1
      FROM app_data.questionnaire_questions AS known_question
      WHERE known_question.questionnaire_version_id = target_questionnaire_version_id
        AND known_question.question_id = answer->>'questionId'
    )
    OR answer->>'questionId' = ANY(visible_ids);

  errors := app_data.questionnaire_answer_errors_v1(
    target_questionnaire_version_id,
    visible_and_unknown_answers,
    false
  );

  FOR answer_row IN
    SELECT answer
    FROM jsonb_array_elements(submitted_answers) AS answers(answer)
  LOOP
    SELECT * INTO question_row
    FROM app_data.questionnaire_questions AS question
    WHERE question.questionnaire_version_id = target_questionnaire_version_id
      AND question.question_id = answer_row->>'questionId';
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    IF NOT question_row.question_id = ANY(visible_ids) THEN
      IF answer_row->>'type' IS DISTINCT FROM question_row.question_type
        OR answer_row->>'state' IS DISTINCT FROM 'not_applicable'
        OR answer_row->>'stateReason' IS DISTINCT FROM 'rule_skipped'
        OR answer_row->'value' IS DISTINCT FROM 'null'::jsonb
      THEN
        errors := array_append(
          errors,
          'hidden_answer_present:' || question_row.question_id
        );
      END IF;
    ELSIF answer_row->'stateReason' IS NOT NULL
      AND answer_row->'stateReason' <> 'null'::jsonb
    THEN
      errors := array_append(
        errors,
        'answer_state_reason_invalid:' || question_row.question_id
      );
    END IF;
  END LOOP;

  FOR question_row IN
    SELECT *
    FROM app_data.questionnaire_questions AS question
    WHERE question.questionnaire_version_id = target_questionnaire_version_id
      AND NOT question.question_id = ANY(visible_ids)
    ORDER BY question.position
  LOOP
    SELECT count(*) INTO submitted_answer_count
    FROM jsonb_array_elements(submitted_answers) AS answers(answer)
    WHERE answer->>'questionId' = question_row.question_id;
    IF submitted_answer_count = 0 THEN
      errors := array_append(
        errors,
        'rule_skipped_answer_missing:' || question_row.question_id
      );
    ELSIF submitted_answer_count > 1 THEN
      errors := array_append(
        errors,
        'duplicate_answer:' || question_row.question_id
      );
    END IF;
  END LOOP;

  IF require_complete THEN
    FOR question_row IN
      SELECT *
      FROM app_data.questionnaire_questions AS question
      WHERE question.questionnaire_version_id = target_questionnaire_version_id
        AND question.question_id = ANY(visible_ids)
        AND question.is_required
      ORDER BY question.position
    LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(submitted_answers) AS answers(answer)
        WHERE answer->>'questionId' = question_row.question_id
          AND answer->>'state' <> 'unanswered'
      ) THEN
        errors := array_append(
          errors,
          'required_answer_missing:' || question_row.question_id
        );
      END IF;
    END LOOP;
  END IF;
  RETURN errors;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.insert_questionnaire_answers(
  target_contact_id text,
  target_revision_number integer,
  submitted_answers jsonb
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  INSERT INTO app_data.contact_answers (
    contact_id, revision_number, question_id, answer_state,
    answer_state_reason, answer_type,
    boolean_value, text_value, number_value, multi_choice_values
  )
  SELECT
    target_contact_id,
    target_revision_number,
    answer->>'questionId',
    answer->>'state',
    NULLIF(answer->>'stateReason', ''),
    answer->>'type',
    CASE
      WHEN answer->>'state' = 'answered' AND answer->>'type' = 'boolean'
        THEN (answer->>'value')::boolean
      ELSE NULL
    END,
    CASE
      WHEN answer->>'state' = 'answered' AND answer->>'type' IN (
        'single_choice', 'ordinal_choice', 'date', 'short_text', 'long_text'
      ) THEN answer->>'value'
      ELSE NULL
    END,
    CASE
      WHEN answer->>'state' = 'answered' AND answer->>'type' = 'number'
        THEN (answer->>'value')::numeric
      ELSE NULL
    END,
    CASE
      WHEN answer->>'state' = 'answered' AND answer->>'type' = 'multi_choice'
        THEN ARRAY(
          SELECT selected #>> '{}'
          FROM jsonb_array_elements(answer->'value') AS values(selected)
        )
      ELSE NULL
    END
  FROM jsonb_array_elements(submitted_answers) AS answers(answer);
$function$;

CREATE FUNCTION app_data.copy_voided_questionnaire_state_reason()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NEW.answer_state_reason IS NULL
    AND EXISTS (
      SELECT 1
      FROM app_data.contact_revisions AS revision
      WHERE revision.contact_id = NEW.contact_id
        AND revision.revision_number = NEW.revision_number
        AND revision.revision_kind = 'voided'
    )
  THEN
    SELECT previous.answer_state_reason INTO NEW.answer_state_reason
    FROM app_data.contact_answers AS previous
    WHERE previous.contact_id = NEW.contact_id
      AND previous.revision_number = NEW.revision_number - 1
      AND previous.question_id = NEW.question_id;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER contact_answers_copy_voided_state_reason
BEFORE INSERT ON app_data.contact_answers
FOR EACH ROW EXECUTE FUNCTION app_data.copy_voided_questionnaire_state_reason();

CREATE OR REPLACE FUNCTION app_data.read_published_questionnaire(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_questionnaire_version_id uuid
)
RETURNS TABLE (questionnaire_definition jsonb)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'questionnaire_version_id', version_row.questionnaire_version_id,
    'project_id', version_row.project_id,
    'version_number', version_row.version_number,
    'status', version_row.status,
    'questions', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object(
            'question_id', question_row.question_id,
            'position', question_row.position,
            'prompt', question_row.prompt,
            'type', question_row.question_type,
            'required', question_row.is_required,
            'allow_unknown', question_row.allow_unknown,
            'allow_refused', question_row.allow_refused,
            'allow_not_applicable', question_row.allow_not_applicable,
            'options', CASE
              WHEN question_row.question_type IN (
                'single_choice', 'ordinal_choice', 'multi_choice'
              ) THEN (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    'option_id', option_row.option_id,
                    'position', option_row.position,
                    'label', option_row.label
                  ) ORDER BY option_row.position
                )
                FROM app_data.questionnaire_options AS option_row
                WHERE option_row.questionnaire_version_id =
                    question_row.questionnaire_version_id
                  AND option_row.question_id = question_row.question_id
              )
              ELSE NULL
            END,
            'minimum_selections', question_row.minimum_selections,
            'maximum_selections', question_row.maximum_selections,
            'number_kind', question_row.number_kind,
            'unit', question_row.unit,
            'minimum', question_row.minimum,
            'maximum', question_row.maximum,
            'maximum_length', question_row.maximum_length,
            'display_rule', question_row.display_rule
          )) ORDER BY question_row.position
        )
        FROM app_data.questionnaire_questions AS question_row
        WHERE question_row.questionnaire_version_id =
            version_row.questionnaire_version_id
      ),
      '[]'::jsonb
    )
  )
  FROM app_data.questionnaire_versions AS version_row
  JOIN app_data.projects AS project_row
    ON project_row.project_id = version_row.project_id
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.workspace_id = project_row.workspace_id
  WHERE version_row.questionnaire_version_id =
      requested_questionnaire_version_id
    AND version_row.project_id = trusted_project_id
    AND version_row.status = 'published'
    AND project_row.workspace_id = trusted_workspace_id
    AND project_row.status = 'active'
    AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
    AND workspace_row.deleted_at IS NULL;
$function$;

REVOKE ALL ON FUNCTION
  app_data.questionnaire_answer_errors_v1(uuid, jsonb, boolean),
  app_data.questionnaire_visibility_condition_matches(uuid, jsonb, jsonb, text[]),
  app_data.questionnaire_visible_question_ids(uuid, jsonb),
  app_data.questionnaire_answer_errors(uuid, jsonb, boolean),
  app_data.insert_questionnaire_answers(text, integer, jsonb),
  app_data.copy_voided_questionnaire_state_reason()
  FROM PUBLIC, tongxingzhe_runtime;
