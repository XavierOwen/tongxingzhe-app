-- Drift 与 PostgreSQL 共用 personal_contact_metrics_v1.csv；本文件只负责把
-- 相同事实送入受控 PostgreSQL 写入函数，并核对相同 golden results。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE metric_fixture (
  contact_id text NOT NULL,
  owner_key text NOT NULL,
  project_key text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  channel text NOT NULL,
  reach_count integer NOT NULL,
  interest_level integer NOT NULL,
  expected_in_primary_scope boolean NOT NULL
);

\copy metric_fixture FROM 'backend/database/fixtures/shared/personal_contact_metrics_v1.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE metric_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-metrics.supabase.co/auth/v1',
  'synthetic-metrics-primary'
);

CREATE TEMP TABLE metric_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-metrics.supabase.co/auth/v1',
  'synthetic-metrics-primary',
  '其他推广项目'
);

CREATE TEMP TABLE metric_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-metrics.supabase.co/auth/v1',
  'synthetic-metrics-secondary'
);

CREATE TEMP TABLE metric_write_results AS
SELECT fixture.contact_id, applied.result_code
FROM metric_fixture AS fixture
CROSS JOIN LATERAL app_data.apply_contact_submit(
  CASE fixture.owner_key
    WHEN 'primary' THEN (SELECT app_user_id FROM metric_primary_context)
    ELSE (SELECT app_user_id FROM metric_secondary_context)
  END,
  'metric-command-' || fixture.contact_id,
  1,
  'contact.submit.v1',
  'synthetic-metric-device',
  fixture.contact_id,
  0,
  jsonb_build_object(
    'contactId', fixture.contact_id,
    'workspaceId', CASE fixture.owner_key
      WHEN 'primary' THEN (SELECT workspace_id FROM metric_primary_context)
      ELSE (SELECT workspace_id FROM metric_secondary_context)
    END,
    'projectId', CASE
      WHEN fixture.owner_key = 'primary' AND fixture.project_key = 'other'
        THEN (SELECT project_id FROM metric_other_project)
      WHEN fixture.owner_key = 'primary'
        THEN (SELECT project_id FROM metric_primary_context)
      ELSE (SELECT project_id FROM metric_secondary_context)
    END,
    'questionnaireVersionId', CASE
      WHEN fixture.owner_key = 'primary' AND fixture.project_key = 'other'
        THEN (SELECT questionnaire_version_id FROM metric_other_project)
      WHEN fixture.owner_key = 'primary'
        THEN (SELECT questionnaire_version_id FROM metric_primary_context)
      ELSE (SELECT questionnaire_version_id FROM metric_secondary_context)
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

CREATE TEMP TABLE metric_actual AS
SELECT *
FROM app_data.read_personal_contact_summary(
  (SELECT app_user_id FROM metric_primary_context),
  (SELECT workspace_id FROM metric_primary_context),
  (SELECT project_id FROM metric_primary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

DO $metric_check$
DECLARE
  expected_sessions bigint;
  expected_reach bigint;
  expected_interest bigint[];
  expected_channels jsonb;
  expected_latest timestamptz;
BEGIN
  IF EXISTS (
    SELECT 1 FROM metric_write_results WHERE result_code <> 'accepted'
  ) OR (SELECT count(*) FROM metric_write_results) <> 5 THEN
    RAISE EXCEPTION 'shared metric fixture was not fully accepted';
  END IF;

  SELECT
    count(*),
    sum(reach_count),
    ARRAY[
      count(*) FILTER (WHERE interest_level = 0),
      count(*) FILTER (WHERE interest_level = 1),
      count(*) FILTER (WHERE interest_level = 2),
      count(*) FILTER (WHERE interest_level = 3),
      count(*) FILTER (WHERE interest_level = 4)
    ],
    jsonb_build_object(
      'face_to_face', count(*) FILTER (WHERE channel = 'face_to_face'),
      'voice_call', count(*) FILTER (WHERE channel = 'voice_call'),
      'video_call', count(*) FILTER (WHERE channel = 'video_call'),
      'instant_text', count(*) FILTER (WHERE channel = 'instant_text'),
      'asynchronous_message', count(*) FILTER (
        WHERE channel = 'asynchronous_message'
      ),
      'mixed', count(*) FILTER (WHERE channel = 'mixed'),
      'other_direct', count(*) FILTER (WHERE channel = 'other_direct')
    ),
    max(occurred_at_utc)
    INTO expected_sessions, expected_reach, expected_interest,
      expected_channels, expected_latest
  FROM metric_fixture
  WHERE expected_in_primary_scope;

  IF NOT EXISTS (
    SELECT 1
    FROM metric_actual
    WHERE contact_session_count = expected_sessions
      AND reach_count = expected_reach
      AND ARRAY[
        interest_0_count,
        interest_1_count,
        interest_2_count,
        interest_3_count,
        interest_4_count
      ] = expected_interest
      AND channel_distribution = expected_channels
      AND latest_occurred_at_utc = expected_latest
  ) THEN
    RAISE EXCEPTION 'PostgreSQL metrics differ from the shared fixture';
  END IF;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_contact_summary(
      (SELECT app_user_id FROM metric_secondary_context),
      (SELECT workspace_id FROM metric_primary_context),
      (SELECT project_id FROM metric_primary_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'another user read the primary metric scope';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$metric_check$;

ROLLBACK;
