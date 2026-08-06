-- 0011_questionnaire_execution.sql
--
-- 保存不可变发布问卷的受控定义，扩展八题型答案值列，并在所有正式写入前
-- 独立复验。客户端 evaluator 只改善离线体验，不能替代这里的授权和校验。

CREATE TABLE app_data.questionnaire_questions (
  questionnaire_version_id uuid NOT NULL
    REFERENCES app_data.questionnaire_versions (questionnaire_version_id)
    ON DELETE RESTRICT,
  question_id text NOT NULL CHECK (length(btrim(question_id)) > 0),
  position integer NOT NULL CHECK (position > 0),
  prompt text NOT NULL CHECK (length(btrim(prompt)) > 0),
  question_type text NOT NULL CHECK (
    question_type IN (
      'boolean', 'single_choice', 'ordinal_choice', 'multi_choice',
      'number', 'date', 'short_text', 'long_text'
    )
  ),
  is_required boolean NOT NULL,
  allow_unknown boolean NOT NULL,
  allow_refused boolean NOT NULL,
  allow_not_applicable boolean NOT NULL,
  minimum_selections integer,
  maximum_selections integer,
  number_kind text,
  unit text,
  minimum numeric,
  maximum numeric,
  maximum_length integer,
  PRIMARY KEY (questionnaire_version_id, question_id),
  UNIQUE (questionnaire_version_id, position),
  CHECK (
    (
      question_type = 'multi_choice'
      AND minimum_selections > 0
      AND maximum_selections >= minimum_selections
    )
    OR
    (
      question_type <> 'multi_choice'
      AND minimum_selections IS NULL
      AND maximum_selections IS NULL
    )
  ),
  CHECK (
    (
      question_type = 'number'
      AND number_kind IN ('integer', 'decimal')
      AND (minimum IS NULL OR maximum IS NULL OR minimum <= maximum)
    )
    OR
    (
      question_type <> 'number'
      AND number_kind IS NULL
      AND unit IS NULL
      AND minimum IS NULL
      AND maximum IS NULL
    )
  ),
  CHECK (
    (
      question_type IN ('short_text', 'long_text')
      AND maximum_length > 0
    )
    OR
    (
      question_type NOT IN ('short_text', 'long_text')
      AND maximum_length IS NULL
    )
  )
);

CREATE TABLE app_data.questionnaire_options (
  questionnaire_version_id uuid NOT NULL,
  question_id text NOT NULL,
  option_id text NOT NULL CHECK (length(btrim(option_id)) > 0),
  position integer NOT NULL CHECK (position > 0),
  label text NOT NULL CHECK (length(btrim(label)) > 0),
  PRIMARY KEY (questionnaire_version_id, question_id, option_id),
  UNIQUE (questionnaire_version_id, question_id, position),
  FOREIGN KEY (questionnaire_version_id, question_id)
    REFERENCES app_data.questionnaire_questions (
      questionnaire_version_id,
      question_id
    )
    ON DELETE RESTRICT
);

ALTER TABLE app_data.contact_answers
  DROP CONSTRAINT contact_answers_answer_type_check,
  DROP CONSTRAINT contact_answers_boolean_shape_valid,
  ADD COLUMN text_value text,
  ADD COLUMN number_value numeric,
  ADD COLUMN multi_choice_values text[],
  ADD CONSTRAINT contact_answers_typed_shape_valid CHECK (
    (
      answer_state IN ('unknown', 'refused', 'not_applicable', 'unanswered')
      AND boolean_value IS NULL
      AND text_value IS NULL
      AND number_value IS NULL
      AND multi_choice_values IS NULL
    )
    OR
    (
      answer_state = 'answered'
      AND (
        (
          answer_type = 'boolean'
          AND boolean_value IS NOT NULL
          AND text_value IS NULL
          AND number_value IS NULL
          AND multi_choice_values IS NULL
        )
        OR
        (
          answer_type IN (
            'single_choice', 'ordinal_choice', 'date',
            'short_text', 'long_text'
          )
          AND boolean_value IS NULL
          AND text_value IS NOT NULL
          AND length(text_value) > 0
          AND number_value IS NULL
          AND multi_choice_values IS NULL
        )
        OR
        (
          answer_type = 'number'
          AND boolean_value IS NULL
          AND text_value IS NULL
          AND number_value IS NOT NULL
          AND multi_choice_values IS NULL
        )
        OR
        (
          answer_type = 'multi_choice'
          AND boolean_value IS NULL
          AND text_value IS NULL
          AND number_value IS NULL
          AND multi_choice_values IS NOT NULL
        )
      )
    )
  );

REVOKE ALL PRIVILEGES
  ON app_data.questionnaire_questions,
     app_data.questionnaire_options
  FROM tongxingzhe_runtime;

-- 0010 的三路比较必须看到真实类型化答案，但 0009 的严格写入仍只会插入
-- boolean。v2 包装器把真实答案放进私有兼容字段，并暂时给旧写入空数组；
-- 比较和自动合并读取兼容字段，最终再原子替换为类型化答案。
CREATE OR REPLACE FUNCTION app_data.contact_revision_comparison_value(
  snapshot jsonb,
  field_name text
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
  SELECT CASE field_name
    WHEN 'occurredAt' THEN jsonb_build_array(
      snapshot->'occurredAtUtc', snapshot->'occurredTimeZone'
    )
    WHEN 'channel' THEN jsonb_build_array(
      snapshot->'channel', snapshot->'channelDetail'
    )
    WHEN 'location' THEN snapshot->'location'
    WHEN 'reachCount' THEN snapshot->'reachCount'
    WHEN 'interestLevel' THEN snapshot->'interestLevel'
    WHEN 'answers' THEN COALESCE(
      (
        SELECT jsonb_object_agg(
          answer->>'questionId',
          answer - 'questionId'
          ORDER BY answer->>'questionId'
        )
        FROM jsonb_array_elements(
          COALESCE(
            snapshot->'_questionnaireAnswersV2',
            snapshot->'answers',
            '[]'::jsonb
          )
        ) AS answer_row(answer)
      ),
      '{}'::jsonb
    )
    ELSE 'null'::jsonb
  END;
$function$;

CREATE OR REPLACE FUNCTION app_data.merge_contact_revision_snapshots(
  current_snapshot jsonb,
  proposed_snapshot jsonb,
  proposed_changed_fields text[]
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  merged_snapshot jsonb := current_snapshot;
  merged_answers jsonb;
BEGIN
  IF 'occurredAt' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'occurredAtUtc', proposed_snapshot->'occurredAtUtc',
      'occurredTimeZone', proposed_snapshot->'occurredTimeZone'
    );
  END IF;
  IF 'channel' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'channel', proposed_snapshot->'channel',
      'channelDetail', proposed_snapshot->'channelDetail'
    );
  END IF;
  IF 'location' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'location', proposed_snapshot->'location'
    );
  END IF;
  IF 'reachCount' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'reachCount', proposed_snapshot->'reachCount'
    );
  END IF;
  IF 'interestLevel' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'interestLevel', proposed_snapshot->'interestLevel'
    );
  END IF;
  IF 'answers' = ANY(proposed_changed_fields) THEN
    merged_snapshot := merged_snapshot || jsonb_build_object(
      'answers', proposed_snapshot->'answers'
    );
  END IF;

  IF proposed_snapshot ? '_questionnaireAnswersV2' THEN
    merged_answers := COALESCE(
      current_snapshot->'_questionnaireAnswersV2',
      current_snapshot->'answers',
      '[]'::jsonb
    );
    IF 'answers' = ANY(proposed_changed_fields) THEN
      merged_answers := proposed_snapshot->'_questionnaireAnswersV2';
    END IF;
    merged_snapshot := jsonb_set(
      merged_snapshot - '_questionnaireAnswersV2',
      '{answers}',
      '[]'::jsonb
    ) || jsonb_build_object('_questionnaireAnswersV2', merged_answers);
  END IF;
  RETURN merged_snapshot;
END
$function$;

CREATE FUNCTION app_data.questionnaire_revision_payload(typed_payload jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_set(
    typed_payload - '_questionnaireAnswersV2',
    '{answers}',
    '[]'::jsonb
  ) || jsonb_build_object(
    '_questionnaireAnswersV2',
    COALESCE(typed_payload->'answers', '[]'::jsonb)
  );
$function$;

CREATE FUNCTION app_data.finalize_questionnaire_revision(
  target_contact_id text,
  target_cursor uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  accepted_answers jsonb;
  accepted_revision_number integer;
BEGIN
  SELECT feed.revision_number,
         COALESCE(
           revision_row.snapshot->'_questionnaireAnswersV2',
           revision_row.snapshot->'answers'
         )
    INTO accepted_revision_number, accepted_answers
  FROM app_data.change_feed AS feed
  JOIN app_data.contact_revisions AS revision_row
    ON revision_row.contact_id = feed.aggregate_id
   AND revision_row.revision_number = feed.revision_number
  WHERE feed.cursor_token = target_cursor
    AND feed.aggregate_id = target_contact_id;
  IF jsonb_typeof(accepted_answers) <> 'array' THEN
    RAISE EXCEPTION 'accepted questionnaire answers are missing';
  END IF;
  PERFORM app_data.insert_questionnaire_answers(
    target_contact_id,
    accepted_revision_number,
    accepted_answers
  );
  UPDATE app_data.contact_revisions
  SET snapshot = jsonb_set(
    snapshot - '_questionnaireAnswersV2',
    '{answers}',
    accepted_answers
  )
  WHERE contact_id = target_contact_id
    AND revision_number = accepted_revision_number;
  UPDATE app_data.change_feed
  SET change_payload = jsonb_set(
    change_payload - '_questionnaireAnswersV2',
    '{answers}',
    accepted_answers
  )
  WHERE cursor_token = target_cursor;
  UPDATE app_data.warehouse_outbox
  SET analytics_payload = analytics_payload
    - '_questionnaireAnswersV2'
    - 'answers'
  WHERE contact_id = target_contact_id
    AND revision_number = accepted_revision_number;
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
  seen_question_ids text[] := ARRAY[]::text[];
  answer_row jsonb;
  answer_value jsonb;
  question_id_value text;
  state_value text;
  type_value text;
  question_row app_data.questionnaire_questions%ROWTYPE;
  selected_count integer;
  selected_distinct_count integer;
  numeric_value numeric;
  date_value date;
BEGIN
  IF jsonb_typeof(submitted_answers) <> 'array' THEN
    RETURN ARRAY['invalid_answers:?'];
  END IF;

  FOR answer_row IN
    SELECT item FROM jsonb_array_elements(submitted_answers) AS values(item)
  LOOP
    IF jsonb_typeof(answer_row) <> 'object' THEN
      errors := array_append(errors, 'invalid_answer:?');
      CONTINUE;
    END IF;
    question_id_value := NULLIF(btrim(answer_row->>'questionId'), '');
    IF question_id_value IS NULL THEN
      errors := array_append(errors, 'invalid_question_id:?');
      CONTINUE;
    END IF;
    IF question_id_value = ANY(seen_question_ids) THEN
      errors := array_append(
        errors,
        'duplicate_answer:' || question_id_value
      );
      CONTINUE;
    END IF;
    seen_question_ids := array_append(seen_question_ids, question_id_value);

    SELECT * INTO question_row
    FROM app_data.questionnaire_questions AS question
    WHERE question.questionnaire_version_id = target_questionnaire_version_id
      AND question.question_id = question_id_value;
    IF NOT FOUND THEN
      errors := array_append(errors, 'unknown_question:' || question_id_value);
      CONTINUE;
    END IF;

    state_value := answer_row->>'state';
    type_value := answer_row->>'type';
    answer_value := answer_row->'value';
    IF type_value IS DISTINCT FROM question_row.question_type THEN
      errors := array_append(
        errors,
        'answer_type_mismatch:' || question_id_value
      );
      CONTINUE;
    END IF;
    IF state_value NOT IN (
      'answered', 'unknown', 'refused', 'not_applicable', 'unanswered'
    ) THEN
      errors := array_append(
        errors,
        'invalid_answer_state:' || question_id_value
      );
      CONTINUE;
    END IF;

    IF state_value <> 'answered' THEN
      IF answer_value IS DISTINCT FROM 'null'::jsonb THEN
        errors := array_append(
          errors,
          'answer_value_shape_invalid:' || question_id_value
        );
      ELSIF state_value = 'unanswered'
        AND question_row.is_required
        AND require_complete
      THEN
        errors := array_append(
          errors,
          'required_answer_missing:' || question_id_value
        );
      ELSIF (state_value = 'unknown' AND NOT question_row.allow_unknown)
        OR (state_value = 'refused' AND NOT question_row.allow_refused)
        OR (
          state_value = 'not_applicable'
          AND NOT question_row.allow_not_applicable
        )
      THEN
        errors := array_append(
          errors,
          'answer_state_not_allowed:' || question_id_value
        );
      END IF;
      CONTINUE;
    END IF;

    IF question_row.question_type = 'boolean' THEN
      IF jsonb_typeof(answer_value) <> 'boolean' THEN
        errors := array_append(
          errors,
          'answer_value_invalid:' || question_id_value
        );
      END IF;
    ELSIF question_row.question_type IN ('single_choice', 'ordinal_choice') THEN
      IF jsonb_typeof(answer_value) <> 'string'
        OR NOT EXISTS (
          SELECT 1
          FROM app_data.questionnaire_options AS option_row
          WHERE option_row.questionnaire_version_id =
              target_questionnaire_version_id
            AND option_row.question_id = question_id_value
            AND option_row.option_id = answer_row->>'value'
        )
      THEN
        errors := array_append(
          errors,
          'answer_value_invalid:' || question_id_value
        );
      END IF;
    ELSIF question_row.question_type = 'multi_choice' THEN
      IF jsonb_typeof(answer_value) <> 'array' THEN
        errors := array_append(
          errors,
          'answer_value_invalid:' || question_id_value
        );
      ELSE
        SELECT count(*), count(DISTINCT item #>> '{}')
          INTO selected_count, selected_distinct_count
        FROM jsonb_array_elements(answer_value) AS selected(item);
        IF selected_count < question_row.minimum_selections
          OR selected_count > question_row.maximum_selections
          OR selected_count <> selected_distinct_count
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(answer_value) AS selected(item)
            WHERE jsonb_typeof(selected.item) <> 'string'
              OR NOT EXISTS (
                SELECT 1
                FROM app_data.questionnaire_options AS option_row
                WHERE option_row.questionnaire_version_id =
                    target_questionnaire_version_id
                  AND option_row.question_id = question_id_value
                  AND option_row.option_id = selected.item #>> '{}'
              )
          )
        THEN
          errors := array_append(
            errors,
            'answer_value_invalid:' || question_id_value
          );
        END IF;
      END IF;
    ELSIF question_row.question_type = 'number' THEN
      IF jsonb_typeof(answer_value) <> 'number' THEN
        errors := array_append(
          errors,
          'answer_value_invalid:' || question_id_value
        );
      ELSE
        numeric_value := (answer_value::text)::numeric;
        IF (question_row.number_kind = 'integer'
              AND numeric_value <> trunc(numeric_value))
          OR (question_row.minimum IS NOT NULL
              AND numeric_value < question_row.minimum)
          OR (question_row.maximum IS NOT NULL
              AND numeric_value > question_row.maximum)
        THEN
          errors := array_append(
            errors,
            'answer_value_invalid:' || question_id_value
          );
        END IF;
      END IF;
    ELSIF question_row.question_type = 'date' THEN
      BEGIN
        IF jsonb_typeof(answer_value) <> 'string'
          OR (answer_row->>'value') !~ '^\d{4}-\d{2}-\d{2}$'
        THEN
          RAISE EXCEPTION USING ERRCODE = '22007';
        END IF;
        date_value := to_date(answer_row->>'value', 'YYYY-MM-DD');
        IF to_char(date_value, 'YYYY-MM-DD') <> answer_row->>'value' THEN
          RAISE EXCEPTION USING ERRCODE = '22007';
        END IF;
      EXCEPTION WHEN OTHERS THEN
        errors := array_append(
          errors,
          'answer_value_invalid:' || question_id_value
        );
      END;
    ELSIF question_row.question_type IN ('short_text', 'long_text') THEN
      IF jsonb_typeof(answer_value) <> 'string'
        OR length(btrim(answer_row->>'value')) = 0
        OR char_length(answer_row->>'value') > question_row.maximum_length
      THEN
        errors := array_append(
          errors,
          'answer_value_invalid:' || question_id_value
        );
      END IF;
    END IF;
  END LOOP;

  IF require_complete THEN
    FOR question_row IN
      SELECT *
      FROM app_data.questionnaire_questions AS question
      WHERE question.questionnaire_version_id = target_questionnaire_version_id
        AND question.is_required
      ORDER BY question.position
    LOOP
      IF NOT question_row.question_id = ANY(seen_question_ids) THEN
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

CREATE FUNCTION app_data.apply_contact_submit_v2(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_errors text[];
  inner_result record;
  version_id uuid;
BEGIN
  version_id := (typed_payload->>'questionnaireVersionId')::uuid;
  validation_errors := app_data.questionnaire_answer_errors(
    version_id,
    typed_payload->'answers',
    true
  );
  IF cardinality(validation_errors) > 0 THEN
    RETURN QUERY SELECT 'rejected', NULL::text, validation_errors[1];
    RETURN;
  END IF;
  SELECT * INTO inner_result
  FROM app_data.apply_contact_submit(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision,
    jsonb_set(typed_payload, '{answers}', '[]'::jsonb)
  );
  IF inner_result.result_code = 'accepted' THEN
    PERFORM app_data.insert_questionnaire_answers(
      client_aggregate_id,
      1,
      typed_payload->'answers'
    );
    UPDATE app_data.contact_revisions
    SET snapshot = jsonb_set(snapshot, '{answers}', typed_payload->'answers')
    WHERE contact_id = client_aggregate_id AND revision_number = 1;
    UPDATE app_data.change_feed
    SET change_payload = jsonb_set(
      change_payload,
      '{answers}',
      typed_payload->'answers'
    )
    WHERE cursor_token = inner_result.server_cursor::uuid;
    UPDATE app_data.warehouse_outbox
    SET analytics_payload = analytics_payload - 'answers'
    WHERE contact_id = client_aggregate_id
      AND revision_number = 1;
  END IF;
  RETURN QUERY SELECT
    inner_result.result_code::text,
    inner_result.server_cursor::text,
    inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_contact_revise_v2(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_errors text[];
  inner_result record;
  version_id uuid;
BEGIN
  SELECT contact_row.questionnaire_version_id INTO version_id
  FROM app_data.contacts AS contact_row
  WHERE contact_row.contact_id = client_aggregate_id
    AND contact_row.app_user_id = trusted_app_user_id
    AND contact_row.workspace_id = (typed_payload->>'workspaceId')::uuid
    AND contact_row.project_id = (typed_payload->>'projectId')::uuid;
  IF version_id IS NOT NULL THEN
    validation_errors := app_data.questionnaire_answer_errors(
      version_id,
      typed_payload->'answers',
      true
    );
    IF cardinality(validation_errors) > 0 THEN
      RETURN QUERY SELECT 'rejected', NULL::text, validation_errors[1];
      RETURN;
    END IF;
  END IF;
  SELECT * INTO inner_result
  FROM app_data.apply_contact_revise(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision,
    app_data.questionnaire_revision_payload(typed_payload)
  );
  IF inner_result.result_code = 'accepted' THEN
    PERFORM app_data.finalize_questionnaire_revision(
      client_aggregate_id,
      inner_result.server_cursor::uuid
    );
  ELSIF inner_result.result_code = 'conflict' THEN
    UPDATE app_data.contact_revision_conflicts
    SET proposed_snapshot = jsonb_set(
      proposed_snapshot - '_questionnaireAnswersV2',
      '{answers}',
      typed_payload->'answers'
    )
    WHERE app_user_id = trusted_app_user_id
      AND command_id = client_command_id;
  END IF;
  RETURN QUERY SELECT
    inner_result.result_code::text,
    inner_result.server_cursor::text,
    inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_contact_conflict_resolution_v2(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_errors text[];
  inner_result record;
  version_id uuid;
BEGIN
  SELECT contact_row.questionnaire_version_id INTO version_id
  FROM app_data.contacts AS contact_row
  WHERE contact_row.contact_id = client_aggregate_id
    AND contact_row.app_user_id = trusted_app_user_id
    AND contact_row.workspace_id = (typed_payload->>'workspaceId')::uuid
    AND contact_row.project_id = (typed_payload->>'projectId')::uuid;
  IF version_id IS NOT NULL THEN
    validation_errors := app_data.questionnaire_answer_errors(
      version_id,
      typed_payload->'answers',
      true
    );
    IF cardinality(validation_errors) > 0 THEN
      RETURN QUERY SELECT 'rejected', NULL::text, validation_errors[1];
      RETURN;
    END IF;
  END IF;
  SELECT * INTO inner_result
  FROM app_data.apply_contact_conflict_resolution(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision,
    app_data.questionnaire_revision_payload(typed_payload)
  );
  IF inner_result.result_code = 'accepted' THEN
    PERFORM app_data.finalize_questionnaire_revision(
      client_aggregate_id,
      inner_result.server_cursor::uuid
    );
  END IF;
  RETURN QUERY SELECT
    inner_result.result_code::text,
    inner_result.server_cursor::text,
    inner_result.failure_code::text;
END
$function$;

CREATE FUNCTION app_data.apply_draft_upsert_v2(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  validation_errors text[];
BEGIN
  validation_errors := app_data.questionnaire_answer_errors(
    (typed_payload->>'questionnaireVersionId')::uuid,
    typed_payload->'answers',
    false
  );
  IF cardinality(validation_errors) > 0 THEN
    RETURN QUERY SELECT 'rejected', NULL::text, validation_errors[1];
    RETURN;
  END IF;
  RETURN QUERY SELECT *
  FROM app_data.apply_draft_upsert(
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    client_base_revision, typed_payload
  );
END
$function$;

CREATE FUNCTION app_data.apply_contact_void_v2(
  trusted_app_user_id uuid,
  client_command_id text,
  client_protocol_version integer,
  client_command_type text,
  client_device_id text,
  client_aggregate_id text,
  client_base_revision integer,
  typed_payload jsonb
)
RETURNS TABLE (result_code text, server_cursor text, failure_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  prior_result record;
  payload_contact_id text;
  payload_workspace_id uuid;
  payload_project_id uuid;
  reason_value text;
  current_contact app_data.contacts%ROWTYPE;
  previous_snapshot jsonb;
  revision_snapshot jsonb;
  accepted_revision integer;
  accepted_cursor uuid;
  revised_at timestamptz := clock_timestamp();
BEGIN
  IF trusted_app_user_id IS NULL
    OR client_protocol_version <> 1
    OR client_command_type <> 'contact.void.v1'
    OR client_base_revision < 1
    OR jsonb_typeof(typed_payload) <> 'object'
    OR typed_payload ? 'appUserId'
    OR typed_payload ? 'app_user_id'
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid void command';
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended(trusted_app_user_id::text || ':' || client_command_id, 0)
  );
  SELECT processed.result_code, processed.server_cursor,
      processed.failure_code
    INTO prior_result
  FROM app_data.processed_commands AS processed
  WHERE processed.app_user_id = trusted_app_user_id
    AND processed.command_id = client_command_id;
  IF FOUND THEN
    RETURN QUERY SELECT
      CASE WHEN prior_result.result_code = 'accepted' THEN 'duplicate'
        ELSE prior_result.result_code END,
      prior_result.server_cursor::text,
      prior_result.failure_code::text;
    RETURN;
  END IF;

  payload_contact_id := typed_payload->>'contactId';
  payload_workspace_id := (typed_payload->>'workspaceId')::uuid;
  payload_project_id := (typed_payload->>'projectId')::uuid;
  reason_value := NULLIF(btrim(typed_payload->>'reason'), '');
  IF payload_contact_id IS NULL
    OR payload_contact_id <> client_aggregate_id
    OR reason_value IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'invalid void payload';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = payload_workspace_id
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = payload_project_id
      AND project_row.status = 'active'
  ) THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'forbidden', 'project_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'project_forbidden';
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('contact:' || payload_contact_id, 0));
  SELECT * INTO current_contact
  FROM app_data.contacts AS contact_row
  WHERE contact_row.contact_id = payload_contact_id
  FOR UPDATE;
  IF NOT FOUND
    OR current_contact.app_user_id <> trusted_app_user_id
    OR current_contact.workspace_id <> payload_workspace_id
    OR current_contact.project_id <> payload_project_id
  THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'forbidden', 'contact_forbidden'
    );
    RETURN QUERY SELECT 'forbidden', NULL::text, 'contact_forbidden';
    RETURN;
  END IF;
  IF current_contact.lifecycle_status = 'voided'
    OR current_contact.current_revision <> client_base_revision
  THEN
    INSERT INTO app_data.processed_commands (
      app_user_id, command_id, protocol_version, command_type, device_id,
      aggregate_id, result_code, failure_code
    ) VALUES (
      trusted_app_user_id, client_command_id, client_protocol_version,
      client_command_type, client_device_id, client_aggregate_id,
      'conflict', CASE WHEN current_contact.lifecycle_status = 'voided'
        THEN 'contact_already_voided' ELSE 'contact_revision_conflict' END
    );
    RETURN QUERY SELECT 'conflict', NULL::text,
      CASE WHEN current_contact.lifecycle_status = 'voided'
        THEN 'contact_already_voided' ELSE 'contact_revision_conflict' END;
    RETURN;
  END IF;

  accepted_revision := client_base_revision + 1;
  SELECT revision_row.snapshot INTO STRICT previous_snapshot
  FROM app_data.contact_revisions AS revision_row
  WHERE revision_row.contact_id = payload_contact_id
    AND revision_row.revision_number = client_base_revision;
  revision_snapshot := previous_snapshot || jsonb_build_object(
    'reason', reason_value,
    'firstSubmittedAtUtc', current_contact.first_submitted_at_utc,
    'revisionKind', 'voided',
    'revisedAtUtc', revised_at
  );
  INSERT INTO app_data.contact_revisions (
    contact_id, revision_number, revision_kind, revised_by_app_user_id,
    revised_at_utc, reason, snapshot
  ) VALUES (
    payload_contact_id, accepted_revision, 'voided', trusted_app_user_id,
    revised_at, reason_value, revision_snapshot
  );
  INSERT INTO app_data.contact_answers (
    contact_id, revision_number, question_id, answer_state, answer_type,
    boolean_value, text_value, number_value, multi_choice_values
  )
  SELECT
    contact_id, accepted_revision, question_id, answer_state, answer_type,
    boolean_value, text_value, number_value, multi_choice_values
  FROM app_data.contact_answers
  WHERE contact_id = payload_contact_id
    AND revision_number = client_base_revision;
  UPDATE app_data.contacts
  SET current_revision = accepted_revision, lifecycle_status = 'voided'
  WHERE contact_id = payload_contact_id;

  accepted_cursor := gen_random_uuid();
  INSERT INTO app_data.change_feed (
    cursor_token, app_user_id, workspace_id, project_id, aggregate_id,
    revision_number, change_type, change_payload
  ) VALUES (
    accepted_cursor, trusted_app_user_id, payload_workspace_id,
    payload_project_id, payload_contact_id, accepted_revision,
    'contact.voided', revision_snapshot
  );
  INSERT INTO app_data.processed_commands (
    app_user_id, command_id, protocol_version, command_type, device_id,
    aggregate_id, result_code, server_cursor
  ) VALUES (
    trusted_app_user_id, client_command_id, client_protocol_version,
    client_command_type, client_device_id, client_aggregate_id,
    'accepted', accepted_cursor
  );
  INSERT INTO app_data.contact_audit_events (
    app_user_id, command_id, contact_id, revision_number, event_type
  ) VALUES (
    trusted_app_user_id, client_command_id, payload_contact_id,
    accepted_revision, 'contact.voided'
  );
  INSERT INTO app_data.warehouse_outbox (
    contact_id, project_id, revision_number, event_type, analytics_payload
  ) VALUES (
    payload_contact_id, payload_project_id, accepted_revision,
    'contact.voided',
    (revision_snapshot - 'answers') || jsonb_build_object(
      'contact_id', payload_contact_id,
      'project_id', payload_project_id,
      'revision_number', accepted_revision,
      'lifecycle_status', 'voided'
    )
  );
  RETURN QUERY SELECT 'accepted', accepted_cursor::text, NULL::text;
END
$function$;

CREATE FUNCTION app_data.insert_questionnaire_answers(
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
    contact_id, revision_number, question_id, answer_state, answer_type,
    boolean_value, text_value, number_value, multi_choice_values
  )
  SELECT
    target_contact_id,
    target_revision_number,
    answer->>'questionId',
    answer->>'state',
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

REVOKE ALL ON FUNCTION
  app_data.questionnaire_answer_errors(uuid, jsonb, boolean),
  app_data.questionnaire_revision_payload(jsonb),
  app_data.finalize_questionnaire_revision(text, uuid),
  app_data.insert_questionnaire_answers(text, integer, jsonb),
  app_data.apply_contact_submit_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_contact_revise_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_contact_conflict_resolution_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_contact_void_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_draft_upsert_v2(uuid, text, integer, text, text, text, integer, jsonb)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.apply_contact_submit_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_contact_revise_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_contact_conflict_resolution_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_contact_void_v2(uuid, text, integer, text, text, text, integer, jsonb),
  app_data.apply_draft_upsert_v2(uuid, text, integer, text, text, text, integer, jsonb)
  TO tongxingzhe_runtime;

CREATE FUNCTION app_data.read_published_questionnaire(
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
            'maximum_length', question_row.maximum_length
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
  app_data.read_published_questionnaire(uuid, uuid, uuid, uuid)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.read_published_questionnaire(uuid, uuid, uuid, uuid)
  TO tongxingzhe_runtime;
