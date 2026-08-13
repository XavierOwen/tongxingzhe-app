-- PostgreSQL fixture：个人后续联系同意占比 v1 bridge。
--
-- 共享 CSV 同时包含可进入候选集的 contact-target link 和明确排除的
-- draft／attempt／问卷答案行。本 fixture 只把真实 link 行写入数据库，
-- 再用共享输入核对候选边界、当前 revision、空分母和 not_enabled 形状。

\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE follow_up_consent_ratio_fixture (
  scenario_key text NOT NULL,
  row_key text NOT NULL,
  analytics_enabled boolean NOT NULL,
  query_project_key text NOT NULL,
  row_project_key text NOT NULL,
  source_kind text NOT NULL,
  contact_key text NOT NULL,
  target_key text NOT NULL,
  revision_number integer NOT NULL,
  current_revision_number integer NOT NULL,
  lifecycle_status text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  period_start_utc timestamptz NOT NULL,
  period_end_utc timestamptz NOT NULL,
  consent_state text NOT NULL,
  expected_in_candidate boolean NOT NULL,
  expected_reason text NOT NULL,
  expected_status text NOT NULL,
  expected_yes_count text NOT NULL,
  expected_no_count text NOT NULL,
  expected_unknown_count text NOT NULL,
  expected_refused_count text NOT NULL,
  expected_not_applicable_count text NOT NULL,
  expected_unanswered_count text NOT NULL,
  expected_excluded_count text NOT NULL,
  expected_denominator text NOT NULL,
  expected_basis_points text NOT NULL
);

\copy follow_up_consent_ratio_fixture FROM 'backend/database/fixtures/shared/follow_up_consent_ratio_v1.csv' WITH (FORMAT csv, HEADER true)

DO $fixture_input_checks$
BEGIN
  IF (SELECT count(*) FROM follow_up_consent_ratio_fixture) <> 19
    OR (SELECT count(*) FROM follow_up_consent_ratio_fixture
        WHERE scenario_key = 'enabled_primary') <> 15
    OR (SELECT count(*) FROM follow_up_consent_ratio_fixture
        WHERE scenario_key = 'enabled_no_answers') <> 3
    OR (SELECT count(*) FROM follow_up_consent_ratio_fixture
        WHERE scenario_key = 'disabled_project') <> 1
  THEN
    RAISE EXCEPTION 'follow-up consent shared fixture was not fully consumed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE period_start_utc >= period_end_utc
      OR revision_number < 1
      OR current_revision_number < 1
      OR consent_state NOT IN (
        'yes', 'no', 'unknown', 'refused', 'not_applicable'
      )
  ) THEN
    RAISE EXCEPTION 'follow-up consent shared fixture has invalid values';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE (scenario_key = 'enabled_primary' AND (
        NOT analytics_enabled
        OR query_project_key <> 'default'
        OR expected_status <> 'ready'
      ))
      OR (scenario_key = 'enabled_no_answers' AND (
        NOT analytics_enabled
        OR query_project_key <> 'default'
        OR expected_status <> 'ready'
      ))
      OR (scenario_key = 'disabled_project' AND (
        analytics_enabled
        OR query_project_key <> 'default'
        OR expected_status <> 'not_enabled'
      ))
  ) THEN
    RAISE EXCEPTION 'follow-up consent shared scenario contract drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture AS fixture
    CROSS JOIN LATERAL (
      SELECT CASE
        WHEN NOT fixture.analytics_enabled THEN 'metric_not_enabled'
        WHEN fixture.row_project_key <> fixture.query_project_key
          THEN 'other_project'
        WHEN fixture.source_kind = 'draft_target_link' THEN 'draft'
        WHEN fixture.source_kind = 'contact_attempt_target_link'
          THEN 'contact_attempt'
        WHEN fixture.source_kind = 'questionnaire_answer'
          THEN 'wrong_statistical_unit'
        WHEN fixture.lifecycle_status = 'voided' THEN 'voided_contact'
        WHEN fixture.revision_number <> fixture.current_revision_number
          THEN 'old_revision'
        WHEN fixture.occurred_at_utc < fixture.period_start_utc
          THEN 'before_period'
        WHEN fixture.occurred_at_utc >= fixture.period_end_utc
          THEN 'right_boundary'
        ELSE 'included'
      END AS computed_reason
    ) AS eligibility
    WHERE fixture.expected_reason <> eligibility.computed_reason
      OR fixture.expected_in_candidate IS DISTINCT FROM
        (eligibility.computed_reason = 'included')
  ) THEN
    RAISE EXCEPTION 'follow-up consent shared candidate boundary drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE scenario_key = 'enabled_primary'
      AND (
        expected_status <> 'ready'
        OR expected_yes_count <> '2'
        OR expected_no_count <> '1'
        OR expected_unknown_count <> '0'
        OR expected_refused_count <> '1'
        OR expected_not_applicable_count <> '1'
        OR expected_unanswered_count <> '2'
        OR expected_excluded_count <> '0'
        OR expected_denominator <> '3'
        OR expected_basis_points <> '6667'
      )
  ) THEN
    RAISE EXCEPTION 'enabled primary shared consent summary drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE scenario_key = 'enabled_no_answers'
      AND (
        expected_status <> 'ready'
        OR expected_yes_count <> '0'
        OR expected_no_count <> '0'
        OR expected_unknown_count <> '0'
        OR expected_refused_count <> '1'
        OR expected_not_applicable_count <> '1'
        OR expected_unanswered_count <> '1'
        OR expected_excluded_count <> '0'
        OR expected_denominator <> '0'
        OR expected_basis_points <> 'NA'
      )
  ) THEN
    RAISE EXCEPTION 'enabled no-answer shared consent summary drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE source_kind = 'questionnaire_answer'
      AND expected_reason = 'wrong_statistical_unit'
      AND NOT expected_in_candidate
  ) OR NOT EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE source_kind = 'draft_target_link'
      AND expected_reason = 'draft'
      AND NOT expected_in_candidate
  ) OR NOT EXISTS (
    SELECT 1
    FROM follow_up_consent_ratio_fixture
    WHERE source_kind = 'contact_attempt_target_link'
      AND expected_reason = 'contact_attempt'
      AND NOT expected_in_candidate
  ) THEN
    RAISE EXCEPTION 'follow-up consent candidate exclusion semantics drifted';
  END IF;
END
$fixture_input_checks$;

GRANT SELECT ON follow_up_consent_ratio_fixture TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE follow_up_consent_ratio_default_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner'
);

CREATE TEMP TABLE follow_up_consent_ratio_other_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  '同意占比其他项目'
);

CREATE TEMP TABLE follow_up_consent_ratio_no_answer_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  '同意占比无回答项目'
);

CREATE TEMP TABLE follow_up_consent_ratio_disabled_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  '同意占比停用项目'
);

CREATE TEMP TABLE follow_up_consent_ratio_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-secondary'
);

CREATE TEMP TABLE follow_up_consent_ratio_inactive_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-inactive'
);

CREATE TEMP TABLE follow_up_consent_ratio_archived_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-archived'
);

CREATE TEMP TABLE follow_up_consent_ratio_deleted_workspace_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-deleted-workspace'
);

CREATE TEMP TABLE follow_up_consent_ratio_context_map AS
SELECT 'default'::text AS context_key, context.*
FROM follow_up_consent_ratio_default_context AS context
UNION ALL
SELECT 'other'::text AS context_key, context.*
FROM follow_up_consent_ratio_other_context AS context
UNION ALL
SELECT 'no_answers'::text AS context_key, context.*
FROM follow_up_consent_ratio_no_answer_context AS context
UNION ALL
SELECT 'disabled'::text AS context_key, context.*
FROM follow_up_consent_ratio_disabled_context AS context;

CREATE TEMP TABLE follow_up_consent_ratio_config_results AS
SELECT 'default'::text AS context_key,
       app_data.configure_project_follow_up_consent_opt_in_v1(
         'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
         'follow-up-consent-ratio-owner',
         context.project_id,
         'follow_up_consent_ratio@1',
         'e4900000-0000-4000-8000-000000000001'::uuid,
         0,
         true
       ) AS configuration
FROM follow_up_consent_ratio_default_context AS context
UNION ALL
SELECT 'other'::text AS context_key,
       app_data.configure_project_follow_up_consent_opt_in_v1(
         'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
         'follow-up-consent-ratio-owner',
         context.project_id,
         'follow_up_consent_ratio@1',
         'e4900000-0000-4000-8000-000000000002'::uuid,
         0,
         true
       ) AS configuration
FROM follow_up_consent_ratio_other_context AS context
UNION ALL
SELECT 'no_answers'::text AS context_key,
       app_data.configure_project_follow_up_consent_opt_in_v1(
         'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
         'follow-up-consent-ratio-owner',
         context.project_id,
         'follow_up_consent_ratio@1',
         'e4900000-0000-4000-8000-000000000003'::uuid,
         0,
         true
       ) AS configuration
FROM follow_up_consent_ratio_no_answer_context AS context
UNION ALL
SELECT 'disabled'::text AS context_key,
       app_data.configure_project_follow_up_consent_opt_in_v1(
         'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
         'follow-up-consent-ratio-owner',
         context.project_id,
         'follow_up_consent_ratio@1',
         'e4900000-0000-4000-8000-000000000004'::uuid,
         0,
         false
       ) AS configuration
FROM follow_up_consent_ratio_disabled_context AS context;

CREATE TEMP TABLE follow_up_consent_ratio_actual_rows AS
SELECT fixture.*,
       CASE
         WHEN fixture.scenario_key = 'enabled_no_answers' THEN 'no_answers'
         WHEN fixture.scenario_key = 'disabled_project' THEN 'disabled'
         WHEN fixture.row_project_key = 'other' THEN 'other'
         ELSE 'default'
       END AS context_key
FROM follow_up_consent_ratio_fixture AS fixture
WHERE fixture.source_kind = 'contact_target_link';

CREATE TEMP TABLE follow_up_consent_ratio_target_map AS
SELECT requested.target_key,
       requested.context_key,
       (created.target->>'target_id')::uuid AS target_id
FROM (
  SELECT DISTINCT target_key, context_key
  FROM follow_up_consent_ratio_actual_rows
) AS requested
JOIN follow_up_consent_ratio_context_map AS context
  ON context.context_key = requested.context_key
CROSS JOIN LATERAL app_data.create_promotion_target(
  context.app_user_id,
  context.workspace_id,
  context.project_id,
  'person',
  '同意占比 synthetic ' || requested.target_key,
  NULL,
  NULL,
  'follow-up-consent-ratio-target-' || replace(requested.target_key, '-', '_')
) AS created;

RESET ROLE;

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = (
  SELECT app_user_id FROM follow_up_consent_ratio_inactive_context
);

UPDATE app_data.projects
SET status = 'archived'
WHERE project_id = (
  SELECT project_id FROM follow_up_consent_ratio_archived_context
);

UPDATE app_data.workspaces
SET deleted_at = clock_timestamp()
WHERE workspace_id = (
  SELECT workspace_id FROM follow_up_consent_ratio_deleted_workspace_context
);

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  'e4900000-0000-4000-8000-000000000101',
  'organization',
  '同意占比组织空间',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  'e4900000-0000-4000-8000-000000000102',
  'e4900000-0000-4000-8000-000000000101',
  '同意占比组织项目',
  'active',
  false
);

INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  channel,
  location_kind,
  reach_count,
  interest_level,
  current_revision,
  lifecycle_status
)
SELECT contact_row.contact_key,
       context.app_user_id,
       context.workspace_id,
       context.project_id,
       context.questionnaire_version_id,
       contact_row.occurred_at_utc,
       'UTC',
       'video_call',
       'not_applicable',
       1,
       2,
       contact_row.current_revision_number,
       contact_row.lifecycle_status
FROM (
  SELECT context_key,
         contact_key,
         min(occurred_at_utc) AS occurred_at_utc,
         max(current_revision_number) AS current_revision_number,
         max(lifecycle_status) AS lifecycle_status
  FROM follow_up_consent_ratio_actual_rows
  GROUP BY context_key, contact_key
) AS contact_row
JOIN follow_up_consent_ratio_context_map AS context
  ON context.context_key = contact_row.context_key;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT revision_row.contact_key,
       revision_row.revision_number,
       context.app_user_id,
       CASE WHEN revision_row.revision_number = 1
         THEN 'submitted' ELSE 'corrected' END,
       CASE WHEN revision_row.revision_number = 1
         THEN NULL ELSE 'synthetic current revision' END,
       '{}'::jsonb
FROM (
  SELECT DISTINCT context_key, contact_key, revision_number
  FROM follow_up_consent_ratio_actual_rows
) AS revision_row
JOIN follow_up_consent_ratio_context_map AS context
  ON context.context_key = revision_row.context_key;

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
)
SELECT actual.contact_key,
       actual.revision_number,
       target_map.target_id,
       2,
       actual.consent_state,
       false,
       true
FROM follow_up_consent_ratio_actual_rows AS actual
JOIN follow_up_consent_ratio_target_map AS target_map
  ON target_map.target_key = actual.target_key
 AND target_map.context_key = actual.context_key;

-- These two rows are deliberately inconsistent composite scopes. The base
-- schema has independent foreign keys, so the read seam must bind actor,
-- workspace, and project instead of assuming one column implies the others.
INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  channel, location_kind, reach_count, interest_level
)
SELECT
  'follow-up-consent-ratio-cross-workspace',
  owner_context.app_user_id,
  secondary_context.workspace_id,
  owner_context.project_id,
  owner_context.questionnaire_version_id,
  '2026-08-05T15:00:00Z'::timestamptz,
  'UTC', 'video_call', 'not_applicable', 1, 2
FROM follow_up_consent_ratio_default_context AS owner_context
CROSS JOIN follow_up_consent_ratio_secondary_context AS secondary_context
UNION ALL
SELECT
  'follow-up-consent-ratio-cross-owner',
  secondary_context.app_user_id,
  owner_context.workspace_id,
  owner_context.project_id,
  owner_context.questionnaire_version_id,
  '2026-08-05T16:00:00Z'::timestamptz,
  'UTC', 'video_call', 'not_applicable', 1, 2
FROM follow_up_consent_ratio_default_context AS owner_context
CROSS JOIN follow_up_consent_ratio_secondary_context AS secondary_context;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revised_by_app_user_id,
  revision_kind, reason, snapshot
)
SELECT
  'follow-up-consent-ratio-cross-workspace', 1,
  owner_context.app_user_id, 'submitted', NULL, '{}'::jsonb
FROM follow_up_consent_ratio_default_context AS owner_context
UNION ALL
SELECT
  'follow-up-consent-ratio-cross-owner', 1,
  secondary_context.app_user_id, 'submitted', NULL, '{}'::jsonb
FROM follow_up_consent_ratio_secondary_context AS secondary_context;

INSERT INTO app_data.contact_target_links (
  contact_id, revision_number, promotion_target_id, response_level,
  follow_up_consent, institution_representative_confirmed,
  confirmed_project_entry
)
SELECT
  excluded_contact.contact_id,
  1,
  target_map.target_id,
  2,
  'yes',
  false,
  true
FROM (
  VALUES
    ('follow-up-consent-ratio-cross-workspace'),
    ('follow-up-consent-ratio-cross-owner')
) AS excluded_contact(contact_id)
CROSS JOIN LATERAL (
  SELECT mapped.target_id
  FROM follow_up_consent_ratio_target_map AS mapped
  WHERE mapped.context_key = 'default'
  ORDER BY mapped.target_key
  LIMIT 1
) AS target_map;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE follow_up_consent_ratio_default_actual AS
SELECT app_data.read_personal_follow_up_consent_ratio_v1(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  context.project_id,
  'follow_up_consent_ratio@1',
  '2026-08-01T00:00:00Z',
  '2026-08-08T00:00:00Z'
) AS result
FROM follow_up_consent_ratio_default_context AS context;

CREATE TEMP TABLE follow_up_consent_ratio_no_answer_actual AS
SELECT app_data.read_personal_follow_up_consent_ratio_v1(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  context.project_id,
  'follow_up_consent_ratio@1',
  '2026-08-01T00:00:00Z',
  '2026-08-08T00:00:00Z'
) AS result
FROM follow_up_consent_ratio_no_answer_context AS context;

CREATE TEMP TABLE follow_up_consent_ratio_other_actual AS
SELECT app_data.read_personal_follow_up_consent_ratio_v1(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  context.project_id,
  'follow_up_consent_ratio@1',
  '2026-08-01T00:00:00Z',
  '2026-08-08T00:00:00Z'
) AS result
FROM follow_up_consent_ratio_other_context AS context;

CREATE TEMP TABLE follow_up_consent_ratio_disabled_actual AS
SELECT app_data.read_personal_follow_up_consent_ratio_v1(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-owner',
  context.project_id,
  'follow_up_consent_ratio@1',
  '2026-08-01T00:00:00Z',
  '2026-08-08T00:00:00Z'
) AS result
FROM follow_up_consent_ratio_disabled_context AS context;

CREATE TEMP TABLE follow_up_consent_ratio_unconfigured_actual AS
SELECT app_data.read_personal_follow_up_consent_ratio_v1(
  'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
  'follow-up-consent-ratio-secondary',
  context.project_id,
  'follow_up_consent_ratio@1',
  '2026-08-01T00:00:00Z',
  '2026-08-08T00:00:00Z'
) AS result
FROM follow_up_consent_ratio_secondary_context AS context;

DO $ratio_check$
DECLARE
  default_result jsonb;
  no_answer_result jsonb;
  other_result jsonb;
  disabled_result jsonb;
  unconfigured_result jsonb;
  default_value jsonb;
  no_answer_value jsonb;
  other_value jsonb;
BEGIN
  SELECT result INTO STRICT default_result
  FROM follow_up_consent_ratio_default_actual;
  SELECT result INTO STRICT no_answer_result
  FROM follow_up_consent_ratio_no_answer_actual;
  SELECT result INTO STRICT other_result
  FROM follow_up_consent_ratio_other_actual;
  SELECT result INTO STRICT disabled_result
  FROM follow_up_consent_ratio_disabled_actual;
  SELECT result INTO STRICT unconfigured_result
  FROM follow_up_consent_ratio_unconfigured_actual;

  default_value := default_result->'value';
  IF default_result->>'contract_id' IS DISTINCT FROM
      'personal_follow_up_consent_ratio_result_v1'
    OR default_result->>'metric_id' IS DISTINCT FROM
      'follow_up_consent_ratio@1'
    OR default_result->>'project_id' IS DISTINCT FROM (
      SELECT project_id::text
      FROM follow_up_consent_ratio_default_context
    )
    OR default_result->>'status' IS DISTINCT FROM 'ready'
    OR (SELECT count(*) FROM jsonb_object_keys(default_result)) <> 6
    OR (SELECT count(*) FROM jsonb_object_keys(default_result->'period')) <> 2
    OR (SELECT count(*) FROM jsonb_object_keys(default_value)) <> 10
    OR default_result->'period'->>'from_utc' IS DISTINCT FROM
      '2026-08-01T00:00:00.000000Z'
    OR default_result->'period'->>'until_utc' IS DISTINCT FROM
      '2026-08-08T00:00:00.000000Z'
    OR default_value->>'yes_count' IS DISTINCT FROM '2'
    OR default_value->>'no_count' IS DISTINCT FROM '1'
    OR default_value->>'numerator' IS DISTINCT FROM '2'
    OR default_value->>'denominator' IS DISTINCT FROM '3'
    OR default_value->>'unknown_count' IS DISTINCT FROM '0'
    OR default_value->>'refused_count' IS DISTINCT FROM '1'
    OR default_value->>'not_applicable_count' IS DISTINCT FROM '1'
    OR default_value->>'unanswered_count' IS DISTINCT FROM '2'
    OR default_value->>'excluded_count' IS DISTINCT FROM '0'
    OR default_value->>'percentage_basis_points' IS DISTINCT FROM '6667'
  THEN
    RAISE EXCEPTION 'enabled primary consent ratio is incorrect: %',
      default_result;
  END IF;

  no_answer_value := no_answer_result->'value';
  IF no_answer_result->>'status' IS DISTINCT FROM 'ready'
    OR no_answer_result->'period' IS NULL
    OR no_answer_value->>'yes_count' IS DISTINCT FROM '0'
    OR no_answer_value->>'no_count' IS DISTINCT FROM '0'
    OR no_answer_value->>'numerator' IS DISTINCT FROM '0'
    OR no_answer_value->>'denominator' IS DISTINCT FROM '0'
    OR no_answer_value->>'unknown_count' IS DISTINCT FROM '0'
    OR no_answer_value->>'refused_count' IS DISTINCT FROM '1'
    OR no_answer_value->>'not_applicable_count' IS DISTINCT FROM '1'
    OR no_answer_value->>'unanswered_count' IS DISTINCT FROM '1'
    OR no_answer_value->>'excluded_count' IS DISTINCT FROM '0'
    OR NOT (no_answer_value ? 'percentage_basis_points')
    OR jsonb_typeof(no_answer_value->'percentage_basis_points') IS DISTINCT FROM 'null'
  THEN
    RAISE EXCEPTION 'enabled no-answer consent ratio is incorrect: %',
      no_answer_result;
  END IF;

  other_value := other_result->'value';
  IF other_result->>'status' IS DISTINCT FROM 'ready'
    OR other_value->>'yes_count' IS DISTINCT FROM '1'
    OR other_value->>'no_count' IS DISTINCT FROM '0'
    OR other_value->>'numerator' IS DISTINCT FROM '1'
    OR other_value->>'denominator' IS DISTINCT FROM '1'
    OR other_value->>'percentage_basis_points' IS DISTINCT FROM '10000'
  THEN
    RAISE EXCEPTION 'other project consent ratio is incorrect: %',
      other_result;
  END IF;

  IF disabled_result <> jsonb_build_object(
    'contract_id', 'personal_follow_up_consent_ratio_result_v1',
    'metric_id', 'follow_up_consent_ratio@1',
    'project_id', disabled_result->'project_id',
    'status', 'not_enabled'
  ) OR disabled_result ? 'period'
    OR disabled_result ? 'value'
  THEN
    RAISE EXCEPTION 'disabled consent ratio did not short circuit: %',
      disabled_result;
  END IF;

  IF unconfigured_result <> jsonb_build_object(
    'contract_id', 'personal_follow_up_consent_ratio_result_v1',
    'metric_id', 'follow_up_consent_ratio@1',
    'project_id', unconfigured_result->'project_id',
    'status', 'not_enabled'
  ) THEN
    RAISE EXCEPTION 'unconfigured consent ratio did not short circuit: %',
      unconfigured_result;
  END IF;

  IF (SELECT count(*) FROM follow_up_consent_ratio_actual_rows
      WHERE context_key = 'default'
        AND expected_in_candidate) <> 7
  THEN
    RAISE EXCEPTION 'primary candidate boundary count drifted';
  END IF;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-owner',
      (SELECT project_id FROM follow_up_consent_ratio_default_context),
      'wrong_metric@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'invalid follow-up consent ratio metric was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-owner',
      (SELECT project_id FROM follow_up_consent_ratio_default_context),
      'follow_up_consent_ratio@1',
      '2026-08-08T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'empty follow-up consent ratio period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-owner',
      (SELECT project_id FROM follow_up_consent_ratio_default_context),
      'follow_up_consent_ratio@1',
      'infinity'::timestamptz,
      'infinity'::timestamptz
    );
    RAISE EXCEPTION 'infinite follow-up consent ratio period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-secondary',
      (SELECT project_id FROM follow_up_consent_ratio_default_context),
      'follow_up_consent_ratio@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'cross-owner follow-up consent ratio was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-forged-subject',
      (SELECT project_id FROM follow_up_consent_ratio_default_context),
      'follow_up_consent_ratio@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'forged follow-up consent ratio identity was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-inactive',
      (SELECT project_id FROM follow_up_consent_ratio_inactive_context),
      'follow_up_consent_ratio@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'inactive follow-up consent ratio owner was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-archived',
      (SELECT project_id FROM follow_up_consent_ratio_archived_context),
      'follow_up_consent_ratio@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'archived follow-up consent ratio project was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-deleted-workspace',
      (
        SELECT project_id
        FROM follow_up_consent_ratio_deleted_workspace_context
      ),
      'follow_up_consent_ratio@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'deleted follow-up consent ratio workspace was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_follow_up_consent_ratio_v1(
      'https://synthetic-follow-up-consent-ratio.example.test/auth/v1',
      'follow-up-consent-ratio-owner',
      'e4900000-0000-4000-8000-000000000102',
      'follow_up_consent_ratio@1',
      '2026-08-01T00:00:00Z',
      '2026-08-08T00:00:00Z'
    );
    RAISE EXCEPTION 'organization follow-up consent ratio project was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM count(*)
    FROM app_private.project_follow_up_consent_opt_in_versions;
    RAISE EXCEPTION 'runtime can read project opt-in history';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END
$ratio_check$;

RESET ROLE;
ROLLBACK;
