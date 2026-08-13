-- PostgreSQL fixture：用与 Drift 共用的个人接触输入，对账五档数量、总场次和
-- 下中位等级。共享 CSV 当前在主项目窗内提供 0、3、4 三个等级；较窄的
-- 半开期间形成偶数样本，另以空期间和其他项目核对边界与 scope。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE interest_fixture (
  contact_id text NOT NULL,
  owner_key text NOT NULL,
  project_key text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  channel text NOT NULL,
  reach_count integer NOT NULL,
  interest_level integer NOT NULL,
  expected_in_primary_scope boolean NOT NULL
);

\copy interest_fixture FROM 'backend/database/fixtures/shared/personal_contact_metrics_v1.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE interest_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-ordinal.supabase.co/auth/v1',
  'synthetic-interest-ordinal-primary'
);

CREATE TEMP TABLE interest_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-interest-ordinal.supabase.co/auth/v1',
  'synthetic-interest-ordinal-primary',
  '其他兴趣项目'
);

CREATE TEMP TABLE interest_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-ordinal.supabase.co/auth/v1',
  'synthetic-interest-ordinal-secondary'
);

CREATE TEMP TABLE interest_write_results AS
SELECT fixture.contact_id, applied.result_code
FROM interest_fixture AS fixture
CROSS JOIN LATERAL app_data.apply_contact_submit(
  CASE fixture.owner_key
    WHEN 'primary' THEN (SELECT app_user_id FROM interest_primary_context)
    ELSE (SELECT app_user_id FROM interest_secondary_context)
  END,
  'interest-ordinal-command-' || fixture.contact_id,
  1,
  'contact.submit.v1',
  'synthetic-interest-ordinal-device',
  fixture.contact_id,
  0,
  jsonb_build_object(
    'contactId', fixture.contact_id,
    'workspaceId', CASE fixture.owner_key
      WHEN 'primary' THEN (SELECT workspace_id FROM interest_primary_context)
      ELSE (SELECT workspace_id FROM interest_secondary_context)
    END,
    'projectId', CASE
      WHEN fixture.owner_key = 'primary' AND fixture.project_key = 'other'
        THEN (SELECT project_id FROM interest_other_project)
      WHEN fixture.owner_key = 'primary'
        THEN (SELECT project_id FROM interest_primary_context)
      ELSE (SELECT project_id FROM interest_secondary_context)
    END,
    'questionnaireVersionId', CASE
      WHEN fixture.owner_key = 'primary' AND fixture.project_key = 'other'
        THEN (SELECT questionnaire_version_id FROM interest_other_project)
      WHEN fixture.owner_key = 'primary'
        THEN (SELECT questionnaire_version_id FROM interest_primary_context)
      ELSE (SELECT questionnaire_version_id FROM interest_secondary_context)
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

CREATE TEMP TABLE interest_odd_actual AS
SELECT *
FROM app_data.read_personal_interest_ordinal_summary(
  (SELECT app_user_id FROM interest_primary_context),
  (SELECT workspace_id FROM interest_primary_context),
  (SELECT project_id FROM interest_primary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE interest_even_actual AS
SELECT *
FROM app_data.read_personal_interest_ordinal_summary(
  (SELECT app_user_id FROM interest_primary_context),
  (SELECT workspace_id FROM interest_primary_context),
  (SELECT project_id FROM interest_primary_context),
  '2030-01-09T00:00:00Z',
  '2030-01-13T00:00:00Z'
);

CREATE TEMP TABLE interest_empty_actual AS
SELECT *
FROM app_data.read_personal_interest_ordinal_summary(
  (SELECT app_user_id FROM interest_primary_context),
  (SELECT workspace_id FROM interest_primary_context),
  (SELECT project_id FROM interest_primary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-09T00:00:00Z'
);

CREATE TEMP TABLE interest_other_project_actual AS
SELECT *
FROM app_data.read_personal_interest_ordinal_summary(
  (SELECT app_user_id FROM interest_primary_context),
  (SELECT workspace_id FROM interest_primary_context),
  (SELECT project_id FROM interest_other_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

DO $interest_check$
DECLARE
  odd_result record;
  even_result record;
  empty_result record;
  other_project_result record;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM interest_write_results
    WHERE result_code <> 'accepted'
  ) OR (
    SELECT count(*) FROM interest_write_results
  ) <> (
    SELECT count(*) FROM interest_fixture
  ) THEN
    RAISE EXCEPTION 'shared interest fixture was not fully accepted';
  END IF;

  SELECT * INTO STRICT odd_result FROM interest_odd_actual;
  IF odd_result.contact_session_count IS DISTINCT FROM 3
    OR odd_result.interest_0_count IS DISTINCT FROM 1
    OR odd_result.interest_1_count IS DISTINCT FROM 0
    OR odd_result.interest_2_count IS DISTINCT FROM 0
    OR odd_result.interest_3_count IS DISTINCT FROM 1
    OR odd_result.interest_4_count IS DISTINCT FROM 1
    OR odd_result.median_level IS DISTINCT FROM 3
  THEN
    RAISE EXCEPTION 'odd personal interest ordinal summary is incorrect';
  END IF;

  -- Two values (0, 3) must select 0, not an arithmetic average or the upper
  -- middle value.
  SELECT * INTO STRICT even_result FROM interest_even_actual;
  IF even_result.contact_session_count IS DISTINCT FROM 2
    OR even_result.interest_0_count IS DISTINCT FROM 1
    OR even_result.interest_1_count IS DISTINCT FROM 0
    OR even_result.interest_2_count IS DISTINCT FROM 0
    OR even_result.interest_3_count IS DISTINCT FROM 1
    OR even_result.interest_4_count IS DISTINCT FROM 0
    OR even_result.median_level IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'even personal interest ordinal summary is not lower median';
  END IF;

  SELECT * INTO STRICT empty_result FROM interest_empty_actual;
  IF empty_result.contact_session_count IS DISTINCT FROM 0
    OR empty_result.interest_0_count IS DISTINCT FROM 0
    OR empty_result.interest_1_count IS DISTINCT FROM 0
    OR empty_result.interest_2_count IS DISTINCT FROM 0
    OR empty_result.interest_3_count IS DISTINCT FROM 0
    OR empty_result.interest_4_count IS DISTINCT FROM 0
    OR empty_result.median_level IS NOT NULL
  THEN
    RAISE EXCEPTION 'empty personal interest ordinal summary is incorrect';
  END IF;

  -- The other project is an authorized personal scope, but must not be mixed
  -- into the default project's distribution.
  SELECT * INTO STRICT other_project_result FROM interest_other_project_actual;
  IF other_project_result.contact_session_count IS DISTINCT FROM 1
    OR other_project_result.interest_0_count IS DISTINCT FROM 0
    OR other_project_result.interest_1_count IS DISTINCT FROM 1
    OR other_project_result.interest_2_count IS DISTINCT FROM 0
    OR other_project_result.interest_3_count IS DISTINCT FROM 0
    OR other_project_result.interest_4_count IS DISTINCT FROM 0
    OR other_project_result.median_level IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION 'other personal project entered the wrong summary scope';
  END IF;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_interest_ordinal_summary(
      (SELECT app_user_id FROM interest_secondary_context),
      (SELECT workspace_id FROM interest_primary_context),
      (SELECT project_id FROM interest_primary_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'another user read the primary interest scope';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$interest_check$;

ROLLBACK;
