-- PostgreSQL fixture：复用 personal_contact_metrics_v1.csv 的个人接触事实，
-- 对账五档比例、整数 half-up、UTC 半开边界、作废、跨项目和跨用户权限。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE interest_ratio_fixture (
  contact_id text NOT NULL,
  owner_key text NOT NULL,
  project_key text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  channel text NOT NULL,
  reach_count integer NOT NULL,
  interest_level integer NOT NULL,
  expected_in_primary_scope boolean NOT NULL
);

\copy interest_ratio_fixture FROM 'backend/database/fixtures/shared/personal_contact_metrics_v1.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE interest_ratio_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-ratios.supabase.co/auth/v1',
  'synthetic-interest-ratios-primary'
);

CREATE TEMP TABLE interest_ratio_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-ratios.supabase.co/auth/v1',
  'synthetic-interest-ratios-primary',
  '其他比例项目'
);

CREATE TEMP TABLE interest_ratio_rounding_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-ratios.supabase.co/auth/v1',
  'synthetic-interest-ratios-primary',
  'half-up 比例项目'
);

CREATE TEMP TABLE interest_ratio_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-ratios.supabase.co/auth/v1',
  'synthetic-interest-ratios-secondary'
);

CREATE TEMP TABLE interest_ratio_write_results AS
SELECT fixture.contact_id, applied.result_code
FROM interest_ratio_fixture AS fixture
CROSS JOIN LATERAL app_data.apply_contact_submit(
  CASE fixture.owner_key
    WHEN 'primary' THEN (SELECT app_user_id FROM interest_ratio_primary_context)
    ELSE (SELECT app_user_id FROM interest_ratio_secondary_context)
  END,
  'interest-ratios-command-' || fixture.contact_id,
  1,
  'contact.submit.v1',
  'synthetic-interest-ratios-device',
  fixture.contact_id,
  0,
  jsonb_build_object(
    'contactId', fixture.contact_id,
    'workspaceId', CASE fixture.owner_key
      WHEN 'primary' THEN (SELECT workspace_id FROM interest_ratio_primary_context)
      ELSE (SELECT workspace_id FROM interest_ratio_secondary_context)
    END,
    'projectId', CASE
      WHEN fixture.owner_key = 'primary' AND fixture.project_key = 'other'
        THEN (SELECT project_id FROM interest_ratio_other_project)
      WHEN fixture.owner_key = 'primary'
        THEN (SELECT project_id FROM interest_ratio_primary_context)
      ELSE (SELECT project_id FROM interest_ratio_secondary_context)
    END,
    'questionnaireVersionId', CASE
      WHEN fixture.owner_key = 'primary' AND fixture.project_key = 'other'
        THEN (SELECT questionnaire_version_id FROM interest_ratio_other_project)
      WHEN fixture.owner_key = 'primary'
        THEN (SELECT questionnaire_version_id FROM interest_ratio_primary_context)
      ELSE (SELECT questionnaire_version_id FROM interest_ratio_secondary_context)
    END,
    'occurredAtUtc', to_char(
      fixture.occurred_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'occurredTimeZone', 'America/Chicago',
    'channel', fixture.channel,
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', fixture.reach_count,
    'interestLevel', fixture.interest_level,
    'answers', jsonb_build_array()
  )
) AS applied;

-- This row is inside the primary default period, but its lifecycle is voided.
-- It must not increase the denominator, and it must not be reported as the
-- ratio contract's excluded_count (that field is not a lifecycle census).
CREATE TEMP TABLE interest_ratio_void_submit AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  'interest-ratios-void-submit',
  1,
  'contact.submit.v1',
  'synthetic-interest-ratios-device',
  'interest-ratios-voided-contact',
  0,
  jsonb_build_object(
    'contactId', 'interest-ratios-voided-contact',
    'workspaceId', (SELECT workspace_id FROM interest_ratio_primary_context),
    'projectId', (SELECT project_id FROM interest_ratio_primary_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM interest_ratio_primary_context),
    'occurredAtUtc', '2030-01-11T12:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE interest_ratio_void_result AS
SELECT *
FROM app_data.apply_contact_void(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  'interest-ratios-void-command',
  1,
  'contact.void.v1',
  'synthetic-interest-ratios-device',
  'interest-ratios-voided-contact',
  1,
  jsonb_build_object(
    'contactId', 'interest-ratios-voided-contact',
    'workspaceId', (SELECT workspace_id FROM interest_ratio_primary_context),
    'projectId', (SELECT project_id FROM interest_ratio_primary_context),
    'reason', 'Synthetic ratio boundary fixture'
  )
);

-- Three rows with two level-1 observations make 2/3 = 6666.666..., proving
-- deterministic integer half-up rather than truncation (6666).
CREATE TEMP TABLE interest_ratio_rounding_input (
  contact_id text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  interest_level integer NOT NULL
);

INSERT INTO interest_ratio_rounding_input (
  contact_id, occurred_at_utc, interest_level
)
VALUES
  ('interest-ratios-rounding-1', '2030-01-08T10:00:00Z', 1),
  ('interest-ratios-rounding-2', '2030-01-09T10:00:00Z', 1),
  ('interest-ratios-rounding-3', '2030-01-10T10:00:00Z', 4);

CREATE TEMP TABLE interest_ratio_rounding_write_results AS
SELECT input.contact_id, applied.result_code
FROM interest_ratio_rounding_input AS input
CROSS JOIN LATERAL app_data.apply_contact_submit(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  'interest-ratios-' || input.contact_id,
  1,
  'contact.submit.v1',
  'synthetic-interest-ratios-rounding-device',
  input.contact_id,
  0,
  jsonb_build_object(
    'contactId', input.contact_id,
    'workspaceId', (SELECT workspace_id FROM interest_ratio_rounding_project),
    'projectId', (SELECT project_id FROM interest_ratio_rounding_project),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM interest_ratio_rounding_project),
    'occurredAtUtc', to_char(
      input.occurred_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', input.interest_level,
    'answers', jsonb_build_array()
  )
) AS applied;

CREATE TEMP TABLE interest_ratio_default_actual AS
SELECT *
FROM app_data.read_personal_interest_level_ratios(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  (SELECT workspace_id FROM interest_ratio_primary_context),
  (SELECT project_id FROM interest_ratio_primary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_ratio_even_actual AS
SELECT *
FROM app_data.read_personal_interest_level_ratios(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  (SELECT workspace_id FROM interest_ratio_primary_context),
  (SELECT project_id FROM interest_ratio_primary_context),
  '2030-01-09T00:00:00Z',
  '2030-01-13T00:00:00Z'
);

CREATE TEMP TABLE interest_ratio_empty_actual AS
SELECT *
FROM app_data.read_personal_interest_level_ratios(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  (SELECT workspace_id FROM interest_ratio_primary_context),
  (SELECT project_id FROM interest_ratio_primary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-09T00:00:00Z'
);

CREATE TEMP TABLE interest_ratio_right_boundary_actual AS
SELECT *
FROM app_data.read_personal_interest_level_ratios(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  (SELECT workspace_id FROM interest_ratio_primary_context),
  (SELECT project_id FROM interest_ratio_primary_context),
  '2030-01-15T00:00:00Z',
  '2030-01-16T00:00:00Z'
);

CREATE TEMP TABLE interest_ratio_other_project_actual AS
SELECT *
FROM app_data.read_personal_interest_level_ratios(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  (SELECT workspace_id FROM interest_ratio_primary_context),
  (SELECT project_id FROM interest_ratio_other_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_ratio_rounding_actual AS
SELECT *
FROM app_data.read_personal_interest_level_ratios(
  (SELECT app_user_id FROM interest_ratio_primary_context),
  (SELECT workspace_id FROM interest_ratio_primary_context),
  (SELECT project_id FROM interest_ratio_rounding_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

DO $interest_ratio_check$
DECLARE
  default_sum bigint;
  even_sum bigint;
  empty_sum bigint;
  boundary_sum bigint;
  other_sum bigint;
  rounding_sum bigint;
BEGIN
  IF EXISTS (
    SELECT 1 FROM interest_ratio_write_results WHERE result_code <> 'accepted'
  ) OR (
    SELECT count(*) FROM interest_ratio_write_results
  ) <> (SELECT count(*) FROM interest_ratio_fixture) THEN
    RAISE EXCEPTION 'shared interest ratio fixture was not fully accepted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM interest_ratio_void_submit WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM interest_ratio_void_result WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'voided ratio fixture contact was not accepted and voided';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM interest_ratio_rounding_write_results
    WHERE result_code <> 'accepted'
  ) OR (
    SELECT count(*) FROM interest_ratio_rounding_write_results
  ) <> (SELECT count(*) FROM interest_ratio_rounding_input) THEN
    RAISE EXCEPTION 'half-up rounding fixture was not fully accepted';
  END IF;

  SELECT sum(numerator) INTO default_sum FROM interest_ratio_default_actual;
  IF default_sum IS DISTINCT FROM 3
    OR (SELECT count(*) FROM interest_ratio_default_actual) <> 5
    OR EXISTS (
      SELECT 1 FROM interest_ratio_default_actual
      WHERE denominator <> 3
        OR unknown_count <> 0
        OR refused_count <> 0
        OR not_applicable_count <> 0
        OR unanswered_count <> 0
        OR excluded_count <> 0
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_default_actual
      WHERE interest_level = 0 AND numerator = 1
        AND percentage_basis_points = 3333
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_default_actual
      WHERE interest_level = 1 AND numerator = 0
        AND percentage_basis_points = 0
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_default_actual
      WHERE interest_level = 2 AND numerator = 0
        AND percentage_basis_points = 0
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_default_actual
      WHERE interest_level = 3 AND numerator = 1
        AND percentage_basis_points = 3333
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_default_actual
      WHERE interest_level = 4 AND numerator = 1
        AND percentage_basis_points = 3333
    ) THEN
    RAISE EXCEPTION 'default personal interest level ratios are incorrect';
  END IF;

  SELECT sum(numerator) INTO even_sum FROM interest_ratio_even_actual;
  IF even_sum IS DISTINCT FROM 2
    OR EXISTS (
      SELECT 1 FROM interest_ratio_even_actual
      WHERE denominator <> 2 OR excluded_count <> 0
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_even_actual
      WHERE interest_level = 0 AND numerator = 1
        AND percentage_basis_points = 5000
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_even_actual
      WHERE interest_level = 3 AND numerator = 1
        AND percentage_basis_points = 5000
    ) THEN
    RAISE EXCEPTION 'UTC half-open even ratio window is incorrect';
  END IF;

  SELECT sum(numerator) INTO empty_sum FROM interest_ratio_empty_actual;
  IF empty_sum IS DISTINCT FROM 0
    OR EXISTS (
      SELECT 1 FROM interest_ratio_empty_actual
      WHERE denominator <> 0
        OR percentage_basis_points IS NOT NULL
        OR numerator <> 0
        OR unknown_count <> 0
        OR refused_count <> 0
        OR not_applicable_count <> 0
        OR unanswered_count <> 0
        OR excluded_count <> 0
    ) THEN
    RAISE EXCEPTION 'empty personal interest ratio window is incorrect';
  END IF;

  SELECT sum(numerator) INTO boundary_sum FROM interest_ratio_right_boundary_actual;
  IF boundary_sum IS DISTINCT FROM 1
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_right_boundary_actual
      WHERE interest_level = 1
        AND numerator = 1
        AND denominator = 1
        AND percentage_basis_points = 10000
    ) THEN
    RAISE EXCEPTION 'UTC right-boundary ratio semantics are incorrect';
  END IF;

  SELECT sum(numerator) INTO other_sum FROM interest_ratio_other_project_actual;
  IF other_sum IS DISTINCT FROM 1
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_other_project_actual
      WHERE interest_level = 1
        AND numerator = 1
        AND denominator = 1
        AND percentage_basis_points = 10000
    ) THEN
    RAISE EXCEPTION 'other project entered the wrong ratio scope';
  END IF;

  SELECT sum(numerator) INTO rounding_sum FROM interest_ratio_rounding_actual;
  IF rounding_sum IS DISTINCT FROM 3
    OR EXISTS (
      SELECT 1 FROM interest_ratio_rounding_actual
      WHERE denominator <> 3 OR excluded_count <> 0
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_rounding_actual
      WHERE interest_level = 1
        AND numerator = 2
        AND percentage_basis_points = 6667
    )
    OR NOT EXISTS (
      SELECT 1 FROM interest_ratio_rounding_actual
      WHERE interest_level = 4
        AND numerator = 1
        AND percentage_basis_points = 3333
    ) THEN
    RAISE EXCEPTION 'integer half-up percentage basis points are incorrect';
  END IF;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_interest_level_ratios(
      (SELECT app_user_id FROM interest_ratio_secondary_context),
      (SELECT workspace_id FROM interest_ratio_primary_context),
      (SELECT project_id FROM interest_ratio_primary_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'another user read the primary ratio scope';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_interest_level_ratios(
      (SELECT app_user_id FROM interest_ratio_primary_context),
      (SELECT workspace_id FROM interest_ratio_primary_context),
      (SELECT project_id FROM interest_ratio_primary_context),
      '2030-01-15T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'invalid ratio period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;
END
$interest_ratio_check$;

ROLLBACK;
