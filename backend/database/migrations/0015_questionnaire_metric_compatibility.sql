-- 0015_questionnaire_metric_compatibility.sql
--
-- 稳定问卷指标只通过明确决定接收版本化问题。决定和撤销均追加审计事件；
-- 当前成员关系只服务动态分析，历史比较与影响快照不会被覆盖。

CREATE TABLE app_data.questionnaire_metrics (
  questionnaire_metric_id uuid PRIMARY KEY,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  metric_label text NOT NULL CHECK (
    length(btrim(metric_label)) BETWEEN 1 AND 200
  ),
  analysis_operation text NOT NULL CHECK (
    analysis_operation IN ('count', 'distribution', 'proportion')
  ),
  created_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX questionnaire_metrics_project_created
  ON app_data.questionnaire_metrics (project_id, created_at);

CREATE TABLE app_data.questionnaire_metric_compatibility_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  questionnaire_metric_id uuid NOT NULL
    REFERENCES app_data.questionnaire_metrics (questionnaire_metric_id)
    ON DELETE RESTRICT,
  action text NOT NULL CHECK (action IN ('decided', 'revoked')),
  decision text NOT NULL CHECK (decision IN ('compatible', 'incompatible')),
  target_event_id uuid
    REFERENCES app_data.questionnaire_metric_compatibility_events (event_id)
    ON DELETE RESTRICT,
  reference_questionnaire_version_id uuid NOT NULL,
  reference_question_id text NOT NULL,
  candidate_questionnaire_version_id uuid NOT NULL,
  candidate_question_id text NOT NULL,
  actor_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 1000),
  comparison_snapshot jsonb NOT NULL CHECK (
    jsonb_typeof(comparison_snapshot) = 'object'
  ),
  impact_snapshot jsonb NOT NULL CHECK (
    jsonb_typeof(impact_snapshot) = 'object'
  ),
  request_id text NOT NULL CHECK (
    length(btrim(request_id)) BETWEEN 1 AND 120
  ),
  request_document jsonb NOT NULL CHECK (
    jsonb_typeof(request_document) = 'object'
  ),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (
    reference_questionnaire_version_id,
    reference_question_id
  ) REFERENCES app_data.questionnaire_questions (
    questionnaire_version_id,
    question_id
  ) ON DELETE RESTRICT,
  FOREIGN KEY (
    candidate_questionnaire_version_id,
    candidate_question_id
  ) REFERENCES app_data.questionnaire_questions (
    questionnaire_version_id,
    question_id
  ) ON DELETE RESTRICT,
  UNIQUE (actor_app_user_id, request_id),
  CHECK (
    reference_questionnaire_version_id <>
      candidate_questionnaire_version_id
  ),
  CHECK (
    (action = 'decided' AND target_event_id IS NULL)
    OR
    (action = 'revoked' AND target_event_id IS NOT NULL
      AND decision = 'compatible')
  )
);

CREATE UNIQUE INDEX questionnaire_metric_one_revocation_per_event
  ON app_data.questionnaire_metric_compatibility_events (target_event_id)
  WHERE action = 'revoked';

CREATE INDEX questionnaire_metric_events_metric_created
  ON app_data.questionnaire_metric_compatibility_events (
    questionnaire_metric_id,
    created_at DESC
  );

CREATE TABLE app_data.questionnaire_metric_members (
  questionnaire_metric_id uuid NOT NULL
    REFERENCES app_data.questionnaire_metrics (questionnaire_metric_id)
    ON DELETE RESTRICT,
  questionnaire_version_id uuid NOT NULL,
  question_id text NOT NULL,
  membership_role text NOT NULL CHECK (
    membership_role IN ('origin', 'compatible')
  ),
  source_event_id uuid NOT NULL
    REFERENCES app_data.questionnaire_metric_compatibility_events (event_id)
    ON DELETE RESTRICT,
  added_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (
    questionnaire_metric_id,
    questionnaire_version_id,
    question_id
  ),
  UNIQUE (questionnaire_metric_id, questionnaire_version_id),
  UNIQUE (questionnaire_version_id, question_id),
  UNIQUE (source_event_id, membership_role),
  FOREIGN KEY (questionnaire_version_id, question_id)
    REFERENCES app_data.questionnaire_questions (
      questionnaire_version_id,
      question_id
    ) ON DELETE RESTRICT
);

REVOKE ALL PRIVILEGES
  ON app_data.questionnaire_metrics,
     app_data.questionnaire_metric_compatibility_events,
     app_data.questionnaire_metric_members
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.reject_questionnaire_metric_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'questionnaire metric audit history is append-only';
END
$function$;

CREATE TRIGGER questionnaire_metrics_immutable
BEFORE UPDATE OR DELETE ON app_data.questionnaire_metrics
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_questionnaire_metric_audit_mutation();

CREATE TRIGGER questionnaire_metric_events_immutable
BEFORE UPDATE OR DELETE
ON app_data.questionnaire_metric_compatibility_events
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_questionnaire_metric_audit_mutation();

CREATE FUNCTION app_data.questionnaire_metric_question_document(
  target_questionnaire_version_id uuid,
  target_question_id text
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'questionnaire_version_id', question_row.questionnaire_version_id,
    'questionnaire_version_number', version_row.version_number,
    'question_id', question_row.question_id,
    'definition', jsonb_build_object(
      'prompt', question_row.prompt,
      'question_type', question_row.question_type,
      'required', question_row.is_required,
      'display_rule', question_row.display_rule
    ),
    'options', COALESCE(
      (
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
      ),
      '[]'::jsonb
    ),
    'time_scope', jsonb_build_object(
      'kind', 'all_recorded_contacts',
      'timestamp_field', 'occurred_at_utc'
    ),
    'answer_mode', jsonb_build_object(
      'question_type', question_row.question_type,
      'allow_unknown', question_row.allow_unknown,
      'allow_refused', question_row.allow_refused,
      'allow_not_applicable', question_row.allow_not_applicable,
      'minimum_selections', question_row.minimum_selections,
      'maximum_selections', question_row.maximum_selections,
      'number_kind', question_row.number_kind,
      'unit', question_row.unit,
      'minimum', question_row.minimum,
      'maximum', question_row.maximum,
      'maximum_length', question_row.maximum_length
    )
  )
  FROM app_data.questionnaire_questions AS question_row
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.questionnaire_version_id =
      question_row.questionnaire_version_id
  WHERE question_row.questionnaire_version_id =
      target_questionnaire_version_id
    AND question_row.question_id = target_question_id;
$function$;

CREATE FUNCTION app_data.questionnaire_metric_answered_sample_count(
  target_project_id uuid,
  target_questionnaire_version_id uuid,
  target_question_id text
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT count(*)
  FROM app_data.contacts AS contact_row
  JOIN app_data.contact_answers AS answer_row
    ON answer_row.contact_id = contact_row.contact_id
   AND answer_row.revision_number = contact_row.current_revision
   AND answer_row.question_id = target_question_id
   AND answer_row.answer_state = 'answered'
  WHERE contact_row.project_id = target_project_id
    AND contact_row.questionnaire_version_id =
      target_questionnaire_version_id
    AND contact_row.lifecycle_status = 'active';
$function$;

CREATE FUNCTION app_data.questionnaire_metric_impact_document(
  target_project_id uuid,
  reference_questionnaire_version_id uuid,
  reference_question_id text,
  candidate_questionnaire_version_id uuid,
  candidate_question_id text
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'reference_sample_count', reference_count,
    'candidate_sample_count', candidate_count,
    'combined_sample_count', reference_count + candidate_count,
    'separate_series', jsonb_build_array(
      jsonb_build_object(
        'questionnaire_version_id', reference_questionnaire_version_id,
        'sample_count', reference_count
      ),
      jsonb_build_object(
        'questionnaire_version_id', candidate_questionnaire_version_id,
        'sample_count', candidate_count
      )
    ),
    'trend_series', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'period_start', trend.period_start,
            'reference_sample_count', trend.reference_sample_count,
            'candidate_sample_count', trend.candidate_sample_count,
            'combined_sample_count',
              trend.reference_sample_count + trend.candidate_sample_count
          ) ORDER BY trend.period_start
        )
        FROM (
          SELECT
            to_char(
              date_trunc(
                'month',
                contact_row.occurred_at_utc AT TIME ZONE 'UTC'
              ),
              'YYYY-MM-01'
            ) AS period_start,
            count(*) FILTER (
              WHERE contact_row.questionnaire_version_id =
                  reference_questionnaire_version_id
                AND answer_row.question_id = reference_question_id
            ) AS reference_sample_count,
            count(*) FILTER (
              WHERE contact_row.questionnaire_version_id =
                  candidate_questionnaire_version_id
                AND answer_row.question_id = candidate_question_id
            ) AS candidate_sample_count
          FROM app_data.contacts AS contact_row
          JOIN app_data.contact_answers AS answer_row
            ON answer_row.contact_id = contact_row.contact_id
           AND answer_row.revision_number = contact_row.current_revision
           AND answer_row.answer_state = 'answered'
          WHERE contact_row.project_id = target_project_id
            AND contact_row.lifecycle_status = 'active'
            AND (
              contact_row.questionnaire_version_id =
                reference_questionnaire_version_id
              AND answer_row.question_id = reference_question_id
              OR contact_row.questionnaire_version_id =
                candidate_questionnaire_version_id
              AND answer_row.question_id = candidate_question_id
            )
          GROUP BY 1
        ) AS trend
      ),
      '[]'::jsonb
    )
  )
  FROM (
    SELECT
      app_data.questionnaire_metric_answered_sample_count(
        target_project_id,
        reference_questionnaire_version_id,
        reference_question_id
      ) AS reference_count,
      app_data.questionnaire_metric_answered_sample_count(
        target_project_id,
        candidate_questionnaire_version_id,
        candidate_question_id
      ) AS candidate_count
  ) AS counts;
$function$;

CREATE FUNCTION app_data.questionnaire_metric_event_document(
  requested_event_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'event_id', event_row.event_id,
    'metric_id', event_row.questionnaire_metric_id,
    'action', event_row.action,
    'decision', event_row.decision,
    'target_event_id', event_row.target_event_id,
    'reference', jsonb_build_object(
      'questionnaire_version_id',
        event_row.reference_questionnaire_version_id,
      'question_id', event_row.reference_question_id
    ),
    'candidate', jsonb_build_object(
      'questionnaire_version_id',
        event_row.candidate_questionnaire_version_id,
      'question_id', event_row.candidate_question_id
    ),
    'actor_app_user_id', event_row.actor_app_user_id,
    'reason', event_row.reason,
    'comparison_snapshot', event_row.comparison_snapshot,
    'impact_snapshot', event_row.impact_snapshot,
    'created_at', event_row.created_at
  )
  FROM app_data.questionnaire_metric_compatibility_events AS event_row
  WHERE event_row.event_id = requested_event_id;
$function$;

CREATE FUNCTION app_data.list_questionnaire_metric_compatibility(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (compatibility jsonb)
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
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'questionnaire metric management is forbidden';
  END IF;

  RETURN QUERY
  SELECT jsonb_build_object(
    'metrics', COALESCE(
      (
        SELECT jsonb_agg(metric_document ORDER BY created_at, metric_id)
        FROM (
          SELECT
            metric_row.created_at,
            metric_row.questionnaire_metric_id AS metric_id,
            jsonb_build_object(
              'metric_id', metric_row.questionnaire_metric_id,
              'metric_label', metric_row.metric_label,
              'analysis_operation', metric_row.analysis_operation,
              'active_members', COALESCE(
                (
                  SELECT jsonb_agg(
                    jsonb_build_object(
                      'questionnaire_version_id',
                        member_row.questionnaire_version_id,
                      'question_id', member_row.question_id
                    ) ORDER BY version_row.version_number,
                      member_row.question_id
                  )
                  FROM app_data.questionnaire_metric_members AS member_row
                  JOIN app_data.questionnaire_versions AS version_row
                    ON version_row.questionnaire_version_id =
                      member_row.questionnaire_version_id
                  WHERE member_row.questionnaire_metric_id =
                    metric_row.questionnaire_metric_id
                ),
                '[]'::jsonb
              )
            ) AS metric_document
          FROM app_data.questionnaire_metrics AS metric_row
          WHERE metric_row.project_id = trusted_project_id
        ) AS metric_documents
      ),
      '[]'::jsonb
    ),
    'available_questions', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'reference', jsonb_build_object(
              'questionnaire_version_id',
                question_row.questionnaire_version_id,
              'question_id', question_row.question_id
            ),
            'version_number', version_row.version_number,
            'comparison_snapshot',
              app_data.questionnaire_metric_question_document(
                question_row.questionnaire_version_id,
                question_row.question_id
              ),
            'sample_count',
              app_data.questionnaire_metric_answered_sample_count(
                trusted_project_id,
                question_row.questionnaire_version_id,
                question_row.question_id
              ),
            'trend_series', COALESCE(
              (
                SELECT jsonb_agg(
                  jsonb_build_object(
                    'period_start', trend.period_start,
                    'sample_count', trend.sample_count
                  ) ORDER BY trend.period_start
                )
                FROM (
                  SELECT
                    to_char(
                      date_trunc(
                        'month',
                        contact_row.occurred_at_utc AT TIME ZONE 'UTC'
                      ),
                      'YYYY-MM-01'
                    ) AS period_start,
                    count(*) AS sample_count
                  FROM app_data.contacts AS contact_row
                  JOIN app_data.contact_answers AS answer_row
                    ON answer_row.contact_id = contact_row.contact_id
                   AND answer_row.revision_number = contact_row.current_revision
                   AND answer_row.question_id = question_row.question_id
                   AND answer_row.answer_state = 'answered'
                  WHERE contact_row.project_id = trusted_project_id
                    AND contact_row.questionnaire_version_id =
                      question_row.questionnaire_version_id
                    AND contact_row.lifecycle_status = 'active'
                  GROUP BY 1
                ) AS trend
              ),
              '[]'::jsonb
            )
          ) ORDER BY version_row.version_number, question_row.position
        )
        FROM app_data.questionnaire_questions AS question_row
        JOIN app_data.questionnaire_versions AS version_row
          ON version_row.questionnaire_version_id =
            question_row.questionnaire_version_id
         AND version_row.project_id = trusted_project_id
         AND version_row.status = 'published'
        WHERE question_row.question_type NOT IN ('short_text', 'long_text')
      ),
      '[]'::jsonb
    ),
    'events', COALESCE(
      (
        SELECT jsonb_agg(
          app_data.questionnaire_metric_event_document(event_row.event_id)
          ORDER BY event_row.created_at DESC, event_row.event_id DESC
        )
        FROM app_data.questionnaire_metric_compatibility_events AS event_row
        WHERE event_row.project_id = trusted_project_id
      ),
      '[]'::jsonb
    )
  );
END
$function$;

CREATE FUNCTION app_data.record_questionnaire_metric_compatibility(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_metric_id uuid,
  requested_metric_label text,
  requested_analysis_operation text,
  requested_reference_version_id uuid,
  requested_reference_question_id text,
  requested_candidate_version_id uuid,
  requested_candidate_question_id text,
  requested_decision text,
  requested_reason text,
  requested_request_id text
)
RETURNS TABLE (event jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_label text := btrim(requested_metric_label);
  normalized_reason text := btrim(requested_reason);
  normalized_request_id text := btrim(requested_request_id);
  normalized_reference_question_id text :=
    btrim(requested_reference_question_id);
  normalized_candidate_question_id text :=
    btrim(requested_candidate_question_id);
  request_value jsonb;
  existing_event_id uuid;
  existing_request jsonb;
  created_event_id uuid;
  metric_is_new boolean := false;
  reference_type text;
  candidate_type text;
  comparison_value jsonb;
  impact_value jsonb;
BEGIN
  IF requested_metric_id IS NULL
    OR length(normalized_label) NOT BETWEEN 1 AND 200
    OR requested_analysis_operation NOT IN (
      'count', 'distribution', 'proportion'
    )
    OR requested_reference_version_id IS NULL
    OR length(normalized_reference_question_id) NOT BETWEEN 1 AND 120
    OR requested_candidate_version_id IS NULL
    OR length(normalized_candidate_question_id) NOT BETWEEN 1 AND 120
    OR requested_reference_version_id = requested_candidate_version_id
    OR requested_decision NOT IN ('compatible', 'incompatible')
    OR length(normalized_reason) NOT BETWEEN 1 AND 1000
    OR length(normalized_request_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid questionnaire metric decision';
  END IF;

  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'questionnaire metric management is forbidden';
  END IF;

  request_value := jsonb_build_object(
    'metric_id', requested_metric_id,
    'metric_label', normalized_label,
    'analysis_operation', requested_analysis_operation,
    'reference_version_id', requested_reference_version_id,
    'reference_question_id', normalized_reference_question_id,
    'candidate_version_id', requested_candidate_version_id,
    'candidate_question_id', normalized_candidate_question_id,
    'decision', requested_decision,
    'reason', normalized_reason
  );

  SELECT event_row.event_id, event_row.request_document
    INTO existing_event_id, existing_request
  FROM app_data.questionnaire_metric_compatibility_events AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.request_id = normalized_request_id;
  IF existing_event_id IS NOT NULL THEN
    IF existing_request <> request_value THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'questionnaire metric decision conflict';
    END IF;
    RETURN QUERY SELECT app_data.questionnaire_metric_event_document(
      existing_event_id
    );
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(requested_metric_id::text, 0)
  );

  -- The first lookup can race with an identical request waiting on this lock.
  -- Recheck after serialization so concurrent retries return the first event.
  SELECT event_row.event_id, event_row.request_document
    INTO existing_event_id, existing_request
  FROM app_data.questionnaire_metric_compatibility_events AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.request_id = normalized_request_id;
  IF existing_event_id IS NOT NULL THEN
    IF existing_request <> request_value THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'questionnaire metric decision conflict';
    END IF;
    RETURN QUERY SELECT app_data.questionnaire_metric_event_document(
      existing_event_id
    );
    RETURN;
  END IF;

  SELECT question_row.question_type INTO reference_type
  FROM app_data.questionnaire_questions AS question_row
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.questionnaire_version_id =
      question_row.questionnaire_version_id
   AND version_row.project_id = trusted_project_id
   AND version_row.status = 'published'
  WHERE question_row.questionnaire_version_id =
      requested_reference_version_id
    AND question_row.question_id = normalized_reference_question_id;
  SELECT question_row.question_type INTO candidate_type
  FROM app_data.questionnaire_questions AS question_row
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.questionnaire_version_id =
      question_row.questionnaire_version_id
   AND version_row.project_id = trusted_project_id
   AND version_row.status = 'published'
  WHERE question_row.questionnaire_version_id =
      requested_candidate_version_id
    AND question_row.question_id = normalized_candidate_question_id;
  IF reference_type IS NULL OR candidate_type IS NULL
    OR reference_type IN ('short_text', 'long_text')
    OR candidate_type IN ('short_text', 'long_text')
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid questionnaire metric decision';
  END IF;
  IF requested_analysis_operation = 'proportion'
    AND (
      reference_type NOT IN ('boolean', 'single_choice', 'multi_choice')
      OR candidate_type NOT IN ('boolean', 'single_choice', 'multi_choice')
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid questionnaire metric decision';
  END IF;
  IF requested_decision = 'compatible' AND reference_type <> candidate_type
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'compatible questions require one answer type';
  END IF;
  IF requested_decision = 'compatible'
    AND reference_type IN (
      'single_choice', 'ordinal_choice', 'multi_choice'
    )
    AND ARRAY(
      SELECT option_row.option_id
      FROM app_data.questionnaire_options AS option_row
      WHERE option_row.questionnaire_version_id =
          requested_reference_version_id
        AND option_row.question_id = normalized_reference_question_id
      ORDER BY option_row.option_id
    ) IS DISTINCT FROM ARRAY(
      SELECT option_row.option_id
      FROM app_data.questionnaire_options AS option_row
      WHERE option_row.questionnaire_version_id =
          requested_candidate_version_id
        AND option_row.question_id = normalized_candidate_question_id
      ORDER BY option_row.option_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'compatible choice questions require stable option ids';
  END IF;

  IF EXISTS (
    SELECT 1 FROM app_data.questionnaire_metrics AS metric_row
    WHERE metric_row.questionnaire_metric_id = requested_metric_id
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM app_data.questionnaire_metrics AS metric_row
      WHERE metric_row.questionnaire_metric_id = requested_metric_id
        AND metric_row.project_id = trusted_project_id
        AND metric_row.metric_label = normalized_label
        AND metric_row.analysis_operation = requested_analysis_operation
    ) OR NOT EXISTS (
      SELECT 1
      FROM app_data.questionnaire_metric_members AS member_row
      WHERE member_row.questionnaire_metric_id = requested_metric_id
        AND member_row.questionnaire_version_id =
          requested_reference_version_id
        AND member_row.question_id = normalized_reference_question_id
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'questionnaire metric decision conflict';
    END IF;
  ELSE
    INSERT INTO app_data.questionnaire_metrics (
      questionnaire_metric_id,
      project_id,
      metric_label,
      analysis_operation,
      created_by_app_user_id
    ) VALUES (
      requested_metric_id,
      trusted_project_id,
      normalized_label,
      requested_analysis_operation,
      trusted_app_user_id
    );
    metric_is_new := true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.questionnaire_metric_members AS member_row
    WHERE member_row.questionnaire_version_id =
        requested_candidate_version_id
      AND member_row.question_id = normalized_candidate_question_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'questionnaire metric decision conflict';
  END IF;

  comparison_value := jsonb_build_object(
    'reference', app_data.questionnaire_metric_question_document(
      requested_reference_version_id,
      normalized_reference_question_id
    ),
    'candidate', app_data.questionnaire_metric_question_document(
      requested_candidate_version_id,
      normalized_candidate_question_id
    ),
    'analysis_operation', requested_analysis_operation
  );
  impact_value := app_data.questionnaire_metric_impact_document(
    trusted_project_id,
    requested_reference_version_id,
    normalized_reference_question_id,
    requested_candidate_version_id,
    normalized_candidate_question_id
  );

  INSERT INTO app_data.questionnaire_metric_compatibility_events (
    project_id,
    questionnaire_metric_id,
    action,
    decision,
    reference_questionnaire_version_id,
    reference_question_id,
    candidate_questionnaire_version_id,
    candidate_question_id,
    actor_app_user_id,
    reason,
    comparison_snapshot,
    impact_snapshot,
    request_id,
    request_document
  ) VALUES (
    trusted_project_id,
    requested_metric_id,
    'decided',
    requested_decision,
    requested_reference_version_id,
    normalized_reference_question_id,
    requested_candidate_version_id,
    normalized_candidate_question_id,
    trusted_app_user_id,
    normalized_reason,
    comparison_value,
    impact_value,
    normalized_request_id,
    request_value
  ) RETURNING event_id INTO created_event_id;

  IF metric_is_new THEN
    INSERT INTO app_data.questionnaire_metric_members (
      questionnaire_metric_id,
      questionnaire_version_id,
      question_id,
      membership_role,
      source_event_id
    ) VALUES (
      requested_metric_id,
      requested_reference_version_id,
      normalized_reference_question_id,
      'origin',
      created_event_id
    );
  END IF;
  IF requested_decision = 'compatible' THEN
    INSERT INTO app_data.questionnaire_metric_members (
      questionnaire_metric_id,
      questionnaire_version_id,
      question_id,
      membership_role,
      source_event_id
    ) VALUES (
      requested_metric_id,
      requested_candidate_version_id,
      normalized_candidate_question_id,
      'compatible',
      created_event_id
    );
  END IF;

  RETURN QUERY SELECT app_data.questionnaire_metric_event_document(
    created_event_id
  );
END
$function$;

CREATE FUNCTION app_data.revoke_questionnaire_metric_compatibility(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_event_id uuid,
  requested_reason text,
  requested_request_id text
)
RETURNS TABLE (event jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_reason text := btrim(requested_reason);
  normalized_request_id text := btrim(requested_request_id);
  request_value jsonb;
  existing_event_id uuid;
  existing_request jsonb;
  target_row app_data.questionnaire_metric_compatibility_events%ROWTYPE;
  created_event_id uuid;
  impact_value jsonb;
BEGIN
  IF requested_event_id IS NULL
    OR length(normalized_reason) NOT BETWEEN 1 AND 1000
    OR length(normalized_request_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid questionnaire metric revocation';
  END IF;
  IF NOT app_data.questionnaire_management_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'questionnaire metric management is forbidden';
  END IF;

  request_value := jsonb_build_object(
    'event_id', requested_event_id,
    'reason', normalized_reason
  );
  SELECT event_row.event_id, event_row.request_document
    INTO existing_event_id, existing_request
  FROM app_data.questionnaire_metric_compatibility_events AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.request_id = normalized_request_id;
  IF existing_event_id IS NOT NULL THEN
    IF existing_request <> request_value THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'questionnaire metric decision conflict';
    END IF;
    RETURN QUERY SELECT app_data.questionnaire_metric_event_document(
      existing_event_id
    );
    RETURN;
  END IF;

  SELECT event_row.* INTO target_row
  FROM app_data.questionnaire_metric_compatibility_events AS event_row
  WHERE event_row.event_id = requested_event_id
    AND event_row.project_id = trusted_project_id
    AND event_row.action = 'decided'
    AND event_row.decision = 'compatible';
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'questionnaire metric event not found';
  END IF;
  PERFORM pg_advisory_xact_lock(
    hashtextextended(target_row.questionnaire_metric_id::text, 0)
  );
  SELECT event_row.event_id, event_row.request_document
    INTO existing_event_id, existing_request
  FROM app_data.questionnaire_metric_compatibility_events AS event_row
  WHERE event_row.actor_app_user_id = trusted_app_user_id
    AND event_row.request_id = normalized_request_id;
  IF existing_event_id IS NOT NULL THEN
    IF existing_request <> request_value THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'questionnaire metric decision conflict';
    END IF;
    RETURN QUERY SELECT app_data.questionnaire_metric_event_document(
      existing_event_id
    );
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_data.questionnaire_metric_compatibility_events AS event_row
    WHERE event_row.target_event_id = requested_event_id
      AND event_row.action = 'revoked'
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.questionnaire_metric_members AS member_row
    WHERE member_row.questionnaire_metric_id =
        target_row.questionnaire_metric_id
      AND member_row.questionnaire_version_id =
        target_row.candidate_questionnaire_version_id
      AND member_row.question_id = target_row.candidate_question_id
      AND member_row.source_event_id = requested_event_id
      AND member_row.membership_role = 'compatible'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'questionnaire metric decision conflict';
  END IF;

  impact_value := app_data.questionnaire_metric_impact_document(
    trusted_project_id,
    target_row.reference_questionnaire_version_id,
    target_row.reference_question_id,
    target_row.candidate_questionnaire_version_id,
    target_row.candidate_question_id
  );
  INSERT INTO app_data.questionnaire_metric_compatibility_events (
    project_id,
    questionnaire_metric_id,
    action,
    decision,
    target_event_id,
    reference_questionnaire_version_id,
    reference_question_id,
    candidate_questionnaire_version_id,
    candidate_question_id,
    actor_app_user_id,
    reason,
    comparison_snapshot,
    impact_snapshot,
    request_id,
    request_document
  ) VALUES (
    trusted_project_id,
    target_row.questionnaire_metric_id,
    'revoked',
    'compatible',
    requested_event_id,
    target_row.reference_questionnaire_version_id,
    target_row.reference_question_id,
    target_row.candidate_questionnaire_version_id,
    target_row.candidate_question_id,
    trusted_app_user_id,
    normalized_reason,
    target_row.comparison_snapshot,
    impact_value,
    normalized_request_id,
    request_value
  ) RETURNING event_id INTO created_event_id;

  DELETE FROM app_data.questionnaire_metric_members AS member_row
  WHERE member_row.questionnaire_metric_id =
      target_row.questionnaire_metric_id
    AND member_row.questionnaire_version_id =
      target_row.candidate_questionnaire_version_id
    AND member_row.question_id = target_row.candidate_question_id
    AND member_row.source_event_id = requested_event_id
    AND member_row.membership_role = 'compatible';

  RETURN QUERY SELECT app_data.questionnaire_metric_event_document(
    created_event_id
  );
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.reject_questionnaire_metric_audit_mutation(),
  app_data.questionnaire_metric_question_document(uuid, text),
  app_data.questionnaire_metric_answered_sample_count(uuid, uuid, text),
  app_data.questionnaire_metric_impact_document(
    uuid, uuid, text, uuid, text
  ),
  app_data.questionnaire_metric_event_document(uuid)
  FROM PUBLIC;

REVOKE ALL ON FUNCTION
  app_data.list_questionnaire_metric_compatibility(uuid, uuid, uuid),
  app_data.record_questionnaire_metric_compatibility(
    uuid, uuid, uuid, uuid, text, text, uuid, text, uuid, text, text,
    text, text
  ),
  app_data.revoke_questionnaire_metric_compatibility(
    uuid, uuid, uuid, uuid, text, text
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.list_questionnaire_metric_compatibility(uuid, uuid, uuid),
  app_data.record_questionnaire_metric_compatibility(
    uuid, uuid, uuid, uuid, text, text, uuid, text, uuid, text, text,
    text, text
  ),
  app_data.revoke_questionnaire_metric_compatibility(
    uuid, uuid, uuid, uuid, text, text
  )
  TO tongxingzhe_runtime;
