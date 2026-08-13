-- PostgreSQL fixture：个人单次兴趣两个非穷尽子集比例。
--
-- 复用 personal_contact_metrics_v1.csv 的 0、3、4 golden 输入，并补充
-- 仅 1–2、全 0、全 3–4、空期间和 2/3 舍入场景。两个指标共享一次
-- scoped denominator，但它们的分子不要求相加等于分母。

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE interest_subset_ratio_fixture (
  contact_id text NOT NULL,
  owner_key text NOT NULL,
  project_key text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  channel text NOT NULL,
  reach_count integer NOT NULL,
  interest_level integer NOT NULL,
  expected_in_primary_scope boolean NOT NULL
);

\copy interest_subset_ratio_fixture FROM 'backend/database/fixtures/shared/personal_contact_metrics_v1.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE interest_subset_ratio_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary'
);

CREATE TEMP TABLE interest_subset_ratio_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary',
  '另一个兴趣子集比例项目'
);

CREATE TEMP TABLE interest_subset_ratio_only_mid_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary',
  '仅中间兴趣比例项目'
);

CREATE TEMP TABLE interest_subset_ratio_all_zero_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary',
  '全零兴趣比例项目'
);

CREATE TEMP TABLE interest_subset_ratio_all_high_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary',
  '全高兴趣比例项目'
);

CREATE TEMP TABLE interest_subset_ratio_mixed_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary',
  '五档混合兴趣比例项目'
);

CREATE TEMP TABLE interest_subset_ratio_rounding_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-primary',
  '2/3 舍入兴趣比例项目'
);

CREATE TEMP TABLE interest_subset_ratio_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-subset-ratios.supabase.co/auth/v1',
  'synthetic-interest-subset-ratios-secondary'
);

CREATE TEMP TABLE interest_subset_ratio_input (
  contact_id text PRIMARY KEY,
  owner_key text NOT NULL,
  project_key text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  channel text NOT NULL,
  reach_count integer NOT NULL,
  interest_level integer NOT NULL
);

INSERT INTO interest_subset_ratio_input (
  contact_id,
  owner_key,
  project_key,
  occurred_at_utc,
  channel,
  reach_count,
  interest_level
)
SELECT
  contact_id,
  owner_key,
  project_key,
  occurred_at_utc,
  channel,
  reach_count,
  interest_level
FROM interest_subset_ratio_fixture;

INSERT INTO interest_subset_ratio_input (
  contact_id,
  owner_key,
  project_key,
  occurred_at_utc,
  channel,
  reach_count,
  interest_level
)
VALUES
  ('interest-subset-mid-1', 'primary', 'only_mid', '2030-01-10T10:00:00Z', 'video_call', 1, 1),
  ('interest-subset-mid-2', 'primary', 'only_mid', '2030-01-11T10:00:00Z', 'video_call', 1, 2),
  ('interest-subset-zero-1', 'primary', 'all_zero', '2030-01-10T10:00:00Z', 'video_call', 1, 0),
  ('interest-subset-zero-2', 'primary', 'all_zero', '2030-01-11T10:00:00Z', 'video_call', 1, 0),
  ('interest-subset-high-1', 'primary', 'all_high', '2030-01-10T10:00:00Z', 'video_call', 1, 3),
  ('interest-subset-high-2', 'primary', 'all_high', '2030-01-11T10:00:00Z', 'video_call', 1, 4),
  ('interest-subset-mixed-0', 'primary', 'mixed', '2030-01-10T10:00:00Z', 'video_call', 1, 0),
  ('interest-subset-mixed-1', 'primary', 'mixed', '2030-01-10T11:00:00Z', 'video_call', 1, 1),
  ('interest-subset-mixed-2', 'primary', 'mixed', '2030-01-10T12:00:00Z', 'video_call', 1, 2),
  ('interest-subset-mixed-3', 'primary', 'mixed', '2030-01-10T13:00:00Z', 'video_call', 1, 3),
  ('interest-subset-mixed-4', 'primary', 'mixed', '2030-01-10T14:00:00Z', 'video_call', 1, 4),
  ('interest-subset-rounding-1', 'primary', 'rounding', '2030-01-10T10:00:00Z', 'video_call', 1, 3),
  ('interest-subset-rounding-2', 'primary', 'rounding', '2030-01-11T10:00:00Z', 'video_call', 1, 3),
  ('interest-subset-rounding-3', 'primary', 'rounding', '2030-01-12T10:00:00Z', 'video_call', 1, 1);

CREATE TEMP TABLE interest_subset_ratio_write_results AS
SELECT input.contact_id, applied.result_code
FROM interest_subset_ratio_input AS input
CROSS JOIN LATERAL app_data.apply_contact_submit(
  CASE input.owner_key
    WHEN 'primary' THEN (SELECT app_user_id FROM interest_subset_ratio_primary_context)
    ELSE (SELECT app_user_id FROM interest_subset_ratio_secondary_context)
  END,
  'interest-subset-ratios-command-' || input.contact_id,
  1,
  'contact.submit.v1',
  'synthetic-interest-subset-ratios-device',
  input.contact_id,
  0,
  jsonb_build_object(
    'contactId', input.contact_id,
    'workspaceId', CASE input.owner_key
      WHEN 'primary' THEN (SELECT workspace_id FROM interest_subset_ratio_primary_context)
      ELSE (SELECT workspace_id FROM interest_subset_ratio_secondary_context)
    END,
    'projectId', CASE
      WHEN input.owner_key = 'secondary'
        THEN (SELECT project_id FROM interest_subset_ratio_secondary_context)
      WHEN input.project_key = 'other'
        THEN (SELECT project_id FROM interest_subset_ratio_other_project)
      WHEN input.project_key = 'only_mid'
        THEN (SELECT project_id FROM interest_subset_ratio_only_mid_project)
      WHEN input.project_key = 'all_zero'
        THEN (SELECT project_id FROM interest_subset_ratio_all_zero_project)
      WHEN input.project_key = 'all_high'
        THEN (SELECT project_id FROM interest_subset_ratio_all_high_project)
      WHEN input.project_key = 'mixed'
        THEN (SELECT project_id FROM interest_subset_ratio_mixed_project)
      WHEN input.project_key = 'rounding'
        THEN (SELECT project_id FROM interest_subset_ratio_rounding_project)
      ELSE (SELECT project_id FROM interest_subset_ratio_primary_context)
    END,
    'questionnaireVersionId', CASE
      WHEN input.owner_key = 'secondary'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_secondary_context)
      WHEN input.project_key = 'other'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_other_project)
      WHEN input.project_key = 'only_mid'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_only_mid_project)
      WHEN input.project_key = 'all_zero'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_all_zero_project)
      WHEN input.project_key = 'all_high'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_all_high_project)
      WHEN input.project_key = 'mixed'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_mixed_project)
      WHEN input.project_key = 'rounding'
        THEN (SELECT questionnaire_version_id FROM interest_subset_ratio_rounding_project)
      ELSE (SELECT questionnaire_version_id FROM interest_subset_ratio_primary_context)
    END,
    'occurredAtUtc', to_char(
      input.occurred_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'occurredTimeZone', 'America/Chicago',
    'channel', input.channel,
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', input.reach_count,
    'interestLevel', input.interest_level,
    'answers', jsonb_build_array()
  )
) AS applied;

-- A voided contact shares the primary default period but must not enter its
-- denominator. Its lifecycle exclusion is not subset_ratio excluded_count.
CREATE TEMP TABLE interest_subset_ratio_void_submit AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  'interest-subset-ratios-void-submit',
  1,
  'contact.submit.v1',
  'synthetic-interest-subset-ratios-device',
  'interest-subset-voided-contact',
  0,
  jsonb_build_object(
    'contactId', 'interest-subset-voided-contact',
    'workspaceId', (SELECT workspace_id FROM interest_subset_ratio_primary_context),
    'projectId', (SELECT project_id FROM interest_subset_ratio_primary_context),
    'questionnaireVersionId', (SELECT questionnaire_version_id FROM interest_subset_ratio_primary_context),
    'occurredAtUtc', '2030-01-11T12:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 4,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE interest_subset_ratio_void_result AS
SELECT *
FROM app_data.apply_contact_void(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  'interest-subset-ratios-void-command',
  1,
  'contact.void.v1',
  'synthetic-interest-subset-ratios-device',
  'interest-subset-voided-contact',
  1,
  jsonb_build_object(
    'contactId', 'interest-subset-voided-contact',
    'workspaceId', (SELECT workspace_id FROM interest_subset_ratio_primary_context),
    'projectId', (SELECT project_id FROM interest_subset_ratio_primary_context),
    'reason', 'Synthetic subset ratio void fixture'
  )
);

CREATE TEMP TABLE interest_subset_ratio_default_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_primary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
) WITH ORDINALITY;

CREATE TEMP TABLE interest_subset_ratio_only_mid_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_only_mid_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_all_zero_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_all_zero_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_all_high_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_all_high_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_mixed_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_mixed_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_rounding_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_rounding_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_empty_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_only_mid_project),
  '2030-02-01T00:00:00Z',
  '2030-02-02T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_right_boundary_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_primary_context),
  '2030-01-15T00:00:00Z',
  '2030-01-16T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_other_project_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_primary_context),
  (SELECT workspace_id FROM interest_subset_ratio_primary_context),
  (SELECT project_id FROM interest_subset_ratio_other_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_subset_ratio_secondary_actual AS
SELECT *
FROM app_data.read_personal_interest_subset_ratios(
  (SELECT app_user_id FROM interest_subset_ratio_secondary_context),
  (SELECT workspace_id FROM interest_subset_ratio_secondary_context),
  (SELECT project_id FROM interest_subset_ratio_secondary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

DO $interest_subset_ratio_check$
DECLARE
  default_high bigint;
  default_zero bigint;
  mid_high bigint;
  mid_zero bigint;
  zero_high bigint;
  zero_zero bigint;
  high_high bigint;
  high_zero bigint;
  mixed_high bigint;
  mixed_zero bigint;
  rounding_high bigint;
  empty_denominator bigint;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM interest_subset_ratio_write_results
    WHERE result_code <> 'accepted'
  ) OR (
    SELECT count(*) FROM interest_subset_ratio_write_results
  ) <> (SELECT count(*) FROM interest_subset_ratio_input) THEN
    RAISE EXCEPTION 'shared and subset ratio synthetic contacts were not fully accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM interest_subset_ratio_void_submit WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM interest_subset_ratio_void_result WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'voided subset ratio fixture contact was not accepted and voided';
  END IF;

  IF (SELECT count(*) FROM interest_subset_ratio_default_actual) <> 2
    OR EXISTS (
      SELECT 1
      FROM interest_subset_ratio_default_actual
      WHERE metric_id NOT IN ('interest_3_4_ratio', 'interest_0_ratio')
        OR denominator <> 3
        OR unknown_count <> 0
        OR refused_count <> 0
        OR not_applicable_count <> 0
        OR unanswered_count <> 0
        OR excluded_count <> 0
    )
    OR (SELECT array_agg(metric_id ORDER BY ordinality) FROM interest_subset_ratio_default_actual)
      <> ARRAY['interest_3_4_ratio', 'interest_0_ratio']::text[]
  THEN
    RAISE EXCEPTION 'default subset ratio shape or shared denominator is incorrect';
  END IF;

  SELECT numerator INTO default_high
  FROM interest_subset_ratio_default_actual
  WHERE metric_id = 'interest_3_4_ratio';
  SELECT numerator INTO default_zero
  FROM interest_subset_ratio_default_actual
  WHERE metric_id = 'interest_0_ratio';
  IF default_high IS DISTINCT FROM 2
    OR default_zero IS DISTINCT FROM 1
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_default_actual WHERE metric_id = 'interest_3_4_ratio') <> 6667
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_default_actual WHERE metric_id = 'interest_0_ratio') <> 3333
  THEN
    RAISE EXCEPTION '0, 3, 4 golden subset ratios are incorrect';
  END IF;

  SELECT numerator INTO mid_high
  FROM interest_subset_ratio_only_mid_actual
  WHERE metric_id = 'interest_3_4_ratio';
  SELECT numerator INTO mid_zero
  FROM interest_subset_ratio_only_mid_actual
  WHERE metric_id = 'interest_0_ratio';
  IF mid_high IS DISTINCT FROM 0
    OR mid_zero IS DISTINCT FROM 0
    OR EXISTS (
      SELECT 1 FROM interest_subset_ratio_only_mid_actual WHERE denominator <> 2
    )
    OR mid_high + mid_zero >= 2
  THEN
    RAISE EXCEPTION 'only 1-2 subset ratios did not preserve a non-exhaustive denominator';
  END IF;

  SELECT numerator INTO zero_high
  FROM interest_subset_ratio_all_zero_actual
  WHERE metric_id = 'interest_3_4_ratio';
  SELECT numerator INTO zero_zero
  FROM interest_subset_ratio_all_zero_actual
  WHERE metric_id = 'interest_0_ratio';
  IF zero_high IS DISTINCT FROM 0
    OR zero_zero IS DISTINCT FROM 2
    OR EXISTS (
      SELECT 1 FROM interest_subset_ratio_all_zero_actual WHERE denominator <> 2
    )
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_all_zero_actual WHERE metric_id = 'interest_0_ratio') <> 10000
  THEN
    RAISE EXCEPTION 'all-zero subset ratios are incorrect';
  END IF;

  SELECT numerator INTO high_high
  FROM interest_subset_ratio_all_high_actual
  WHERE metric_id = 'interest_3_4_ratio';
  SELECT numerator INTO high_zero
  FROM interest_subset_ratio_all_high_actual
  WHERE metric_id = 'interest_0_ratio';
  IF high_high IS DISTINCT FROM 2
    OR high_zero IS DISTINCT FROM 0
    OR EXISTS (
      SELECT 1 FROM interest_subset_ratio_all_high_actual WHERE denominator <> 2
    )
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_all_high_actual WHERE metric_id = 'interest_3_4_ratio') <> 10000
  THEN
    RAISE EXCEPTION 'all-high subset ratios are incorrect';
  END IF;

  SELECT numerator INTO mixed_high
  FROM interest_subset_ratio_mixed_actual
  WHERE metric_id = 'interest_3_4_ratio';
  SELECT numerator INTO mixed_zero
  FROM interest_subset_ratio_mixed_actual
  WHERE metric_id = 'interest_0_ratio';
  IF mixed_high IS DISTINCT FROM 2
    OR mixed_zero IS DISTINCT FROM 1
    OR EXISTS (
      SELECT 1 FROM interest_subset_ratio_mixed_actual WHERE denominator <> 5
    )
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_mixed_actual WHERE metric_id = 'interest_3_4_ratio') <> 4000
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_mixed_actual WHERE metric_id = 'interest_0_ratio') <> 2000
  THEN
    RAISE EXCEPTION 'five-level mixed subset ratios are incorrect';
  END IF;

  SELECT numerator INTO rounding_high
  FROM interest_subset_ratio_rounding_actual
  WHERE metric_id = 'interest_3_4_ratio';
  IF rounding_high IS DISTINCT FROM 2
    OR EXISTS (
      SELECT 1 FROM interest_subset_ratio_rounding_actual WHERE denominator <> 3
    )
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_rounding_actual WHERE metric_id = 'interest_3_4_ratio') <> 6667
    OR (SELECT percentage_basis_points FROM interest_subset_ratio_rounding_actual WHERE metric_id = 'interest_0_ratio') <> 0
  THEN
    RAISE EXCEPTION 'integer half-up 2/3 subset ratio is incorrect';
  END IF;

  SELECT min(denominator) INTO empty_denominator
  FROM interest_subset_ratio_empty_actual;
  IF (SELECT count(*) FROM interest_subset_ratio_empty_actual) <> 2
    OR empty_denominator IS DISTINCT FROM 0
    OR EXISTS (
      SELECT 1
      FROM interest_subset_ratio_empty_actual
      WHERE numerator <> 0
        OR percentage_basis_points IS NOT NULL
        OR unknown_count <> 0
        OR refused_count <> 0
        OR not_applicable_count <> 0
        OR unanswered_count <> 0
        OR excluded_count <> 0
    )
  THEN
    RAISE EXCEPTION 'empty subset ratio window is incorrect';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM interest_subset_ratio_right_boundary_actual
    WHERE denominator <> 1
      OR numerator <> 0
      OR percentage_basis_points <> 0
  ) THEN
    RAISE EXCEPTION 'UTC right-boundary subset ratio semantics are incorrect';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM interest_subset_ratio_other_project_actual
    WHERE denominator <> 1
      OR numerator <> 0
  ) THEN
    RAISE EXCEPTION 'other project entered the wrong subset ratio scope';
  END IF;

  IF (SELECT denominator FROM interest_subset_ratio_secondary_actual LIMIT 1) <> 1
    OR (SELECT numerator FROM interest_subset_ratio_secondary_actual WHERE metric_id = 'interest_3_4_ratio') <> 1
    OR (SELECT numerator FROM interest_subset_ratio_secondary_actual WHERE metric_id = 'interest_0_ratio') <> 0
  THEN
    RAISE EXCEPTION 'secondary user subset ratio fixture is incorrect';
  END IF;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_interest_subset_ratios(
      (SELECT app_user_id FROM interest_subset_ratio_secondary_context),
      (SELECT workspace_id FROM interest_subset_ratio_primary_context),
      (SELECT project_id FROM interest_subset_ratio_primary_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'another user read the primary subset ratio scope';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_interest_subset_ratios(
      (SELECT app_user_id FROM interest_subset_ratio_primary_context),
      (SELECT workspace_id FROM interest_subset_ratio_primary_context),
      (SELECT project_id FROM interest_subset_ratio_primary_context),
      '2030-01-15T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'invalid subset ratio period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;
END
$interest_subset_ratio_check$;

ROLLBACK;
