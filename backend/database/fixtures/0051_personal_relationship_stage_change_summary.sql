-- PostgreSQL fixture：个人关系阶段变更汇总 bridge。
--
-- 共享 CSV 固定 admission 边界。本 fixture 把主场景映射为 synthetic
-- append-only revisions，然后通过 runtime 窄函数核对 5 / 4 / 3 / 2、空
-- 期间、跨 project / actor / workspace 隔离，以及结束 assignment 和匿名化
-- 对象的历史事件保留。所有写入都在最后回滚。

\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE relationship_stage_change_fixture (
  scenario_key text NOT NULL,
  row_key text NOT NULL,
  query_actor_key text NOT NULL,
  query_workspace_key text NOT NULL,
  query_project_key text NOT NULL,
  target_key text NOT NULL,
  relationship_workspace_key text NOT NULL,
  relationship_project_key text NOT NULL,
  revision_number integer NOT NULL,
  old_stage integer,
  new_stage integer NOT NULL,
  changed_fields text NOT NULL,
  reason_code text NOT NULL,
  changed_by_actor_key text NOT NULL,
  changed_at_utc timestamptz NOT NULL,
  current_assignment_status text NOT NULL,
  period_from_utc timestamptz NOT NULL,
  period_until_utc timestamptz NOT NULL,
  expected_in_personal_metric boolean NOT NULL,
  expected_reason text NOT NULL,
  expected_scenario_result text NOT NULL,
  expected_event_count integer NOT NULL,
  expected_distinct_relationship_count integer NOT NULL,
  expected_upward_count integer NOT NULL,
  expected_downward_count integer NOT NULL
);

\copy relationship_stage_change_fixture FROM 'backend/database/fixtures/shared/relationship_stage_changes_v1.csv' WITH (FORMAT csv, HEADER true)

DO $input_checks$
BEGIN
  IF (SELECT count(*) FROM relationship_stage_change_fixture) <> 17
    OR (SELECT count(*) FROM relationship_stage_change_fixture
        WHERE scenario_key = 'primary_events') <> 14
    OR (SELECT count(*) FROM relationship_stage_change_fixture
        WHERE scenario_key = 'duplicate_revision') <> 3
  THEN
    RAISE EXCEPTION 'relationship stage change shared fixture was not fully consumed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE scenario_key = 'primary_events'
      AND target_key = 'target-d'
      AND current_assignment_status = 'ended'
      AND expected_in_personal_metric
  ) OR NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE scenario_key = 'primary_events'
      AND changed_at_utc = period_from_utc
      AND expected_in_personal_metric
  ) THEN
    RAISE EXCEPTION 'ended assignment or inclusive UTC lower boundary is missing';
  END IF;

  IF (SELECT count(DISTINCT row_key)
      FROM relationship_stage_change_fixture)
      <> (SELECT count(*) FROM relationship_stage_change_fixture)
  THEN
    RAISE EXCEPTION 'relationship stage change fixture row keys are not unique';
  END IF;
END
$input_checks$;

CREATE TEMP TABLE stage_change_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner'
);

CREATE TEMP TABLE stage_change_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-secondary'
);

CREATE TEMP TABLE stage_change_other_project_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  '阶段变更其他项目'
);

CREATE TEMP TABLE stage_change_empty_project_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  '阶段变更空项目'
);

GRANT SELECT ON
  stage_change_primary_context,
  stage_change_secondary_context,
  stage_change_other_project_context,
  stage_change_empty_project_context
  TO tongxingzhe_runtime;

-- The project pointer is deliberately left on the empty project by the two
-- create calls above. Select the primary project through the same controlled
-- function used by the application before calling the summary bridge.
SET LOCAL ROLE tongxingzhe_runtime;
SELECT count(*)
FROM app_data.select_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  (SELECT project_id FROM stage_change_primary_context)
);
RESET ROLE;

CREATE TEMP TABLE stage_change_target_map (
  target_key text PRIMARY KEY,
  target_id uuid NOT NULL UNIQUE
);

INSERT INTO stage_change_target_map (target_key, target_id) VALUES
  ('target-a', 'b5100000-0000-4000-8000-000000000001'),
  ('target-b', 'b5100000-0000-4000-8000-000000000002'),
  ('target-c', 'b5100000-0000-4000-8000-000000000003'),
  ('target-d', 'b5100000-0000-4000-8000-000000000004'),
  ('target-entry', 'b5100000-0000-4000-8000-000000000005'),
  ('target-lifecycle', 'b5100000-0000-4000-8000-000000000006'),
  ('target-note', 'b5100000-0000-4000-8000-000000000007'),
  ('target-same', 'b5100000-0000-4000-8000-000000000008'),
  ('target-before', 'b5100000-0000-4000-8000-000000000009'),
  ('target-until', 'b5100000-0000-4000-8000-000000000010'),
  ('target-actor', 'b5100000-0000-4000-8000-000000000011'),
  ('target-workspace', 'b5100000-0000-4000-8000-000000000012'),
  ('target-project', 'b5100000-0000-4000-8000-000000000013'),
  ('target-replay', 'b5100000-0000-4000-8000-000000000014');

INSERT INTO app_data.promotion_targets (
  promotion_target_id,
  workspace_id,
  target_type,
  display_name,
  created_by_app_user_id
)
SELECT
  target_map.target_id,
  CASE target_map.target_key
    WHEN 'target-workspace' THEN
      (SELECT workspace_id FROM stage_change_secondary_context)
    ELSE (SELECT workspace_id FROM stage_change_primary_context)
  END,
  'person',
  '阶段变更 synthetic ' || target_map.target_key,
  (SELECT app_user_id FROM stage_change_primary_context)
FROM stage_change_target_map AS target_map;

-- Assignment state is intentionally not part of the bridge predicate.  The
-- ended assignment below proves that an event remains historical evidence.
INSERT INTO app_data.promotion_target_assignments (
  promotion_target_id,
  app_user_id,
  assigned_by_app_user_id
)
SELECT
  target_map.target_id,
  CASE target_map.target_key
    WHEN 'target-workspace' THEN
      (SELECT app_user_id FROM stage_change_secondary_context)
    ELSE (SELECT app_user_id FROM stage_change_primary_context)
  END,
  (SELECT app_user_id FROM stage_change_primary_context)
FROM stage_change_target_map AS target_map;

-- Every relation receives the trigger-installed project_entry revision.  The
-- later rows are the shared CSV revisions; target-project deliberately lives
-- in the owner's other project, while target-workspace lives in another
-- personal workspace.
INSERT INTO app_data.promotion_target_project_relationships (
  promotion_target_id,
  project_id,
  current_stage,
  current_lifecycle_status,
  current_revision,
  established_by_app_user_id,
  updated_by_app_user_id,
  updated_at
)
SELECT
  target_map.target_id,
  CASE fixture.target_key
    WHEN 'target-project' THEN
      (SELECT project_id FROM stage_change_other_project_context)
    ELSE (SELECT project_id FROM stage_change_primary_context)
  END,
  (array_agg(
    coalesce(fixture.old_stage, fixture.new_stage)
    ORDER BY fixture.revision_number
  ))[1],
  'active',
  1,
  (SELECT app_user_id FROM stage_change_primary_context),
  (SELECT app_user_id FROM stage_change_primary_context),
  min(fixture.changed_at_utc)
FROM relationship_stage_change_fixture AS fixture
JOIN stage_change_target_map AS target_map
  ON target_map.target_key = fixture.target_key
WHERE fixture.scenario_key = 'primary_events'
GROUP BY target_map.target_id, fixture.target_key;

INSERT INTO app_data.promotion_target_project_relationships (
  promotion_target_id,
  project_id,
  current_stage,
  established_by_app_user_id,
  established_at
)
SELECT
  target_map.target_id,
  (SELECT project_id FROM stage_change_empty_project_context),
  1,
  (SELECT app_user_id FROM stage_change_primary_context),
  '2030-01-01T00:00:00Z'::timestamptz
FROM stage_change_target_map AS target_map
WHERE target_map.target_key = 'target-replay';

-- The target-c history has a skipped row in the shared admission fixture. Add
-- a harmless same-stage note revision so its production revision chain remains
-- contiguous without changing the summary's eligible events.
INSERT INTO app_data.promotion_target_relationship_revisions (
  promotion_target_id,
  project_id,
  revision_number,
  old_stage,
  new_stage,
  old_lifecycle_status,
  new_lifecycle_status,
  follow_up_note,
  changed_fields,
  reason_code,
  reason_detail,
  changed_by_app_user_id,
  changed_at
)
SELECT
  target_map.target_id,
  (SELECT project_id FROM stage_change_primary_context),
  2,
  1,
  1,
  'active',
  'active',
  NULL,
  ARRAY['follow_up_note']::text[],
  'progress_update',
  NULL,
  (SELECT app_user_id FROM stage_change_primary_context),
  '2030-01-03T00:00:00Z'::timestamptz
FROM stage_change_target_map AS target_map
WHERE target_map.target_key = 'target-c';

INSERT INTO app_data.promotion_target_relationship_revisions (
  promotion_target_id,
  project_id,
  revision_number,
  old_stage,
  new_stage,
  old_lifecycle_status,
  new_lifecycle_status,
  follow_up_note,
  changed_fields,
  reason_code,
  reason_detail,
  changed_by_app_user_id,
  changed_at
)
SELECT
  target_map.target_id,
  CASE fixture.target_key
    WHEN 'target-project' THEN
      (SELECT project_id FROM stage_change_other_project_context)
    ELSE (SELECT project_id FROM stage_change_primary_context)
  END,
  fixture.revision_number,
  fixture.old_stage,
  fixture.new_stage,
  CASE WHEN fixture.old_stage IS NULL THEN NULL ELSE 'active' END,
  'active',
  NULL,
  string_to_array(fixture.changed_fields, '|'),
  fixture.reason_code,
  CASE WHEN fixture.reason_code = 'other' THEN 'synthetic fixture' ELSE NULL END,
  CASE fixture.changed_by_actor_key
    WHEN 'secondary' THEN
      (SELECT app_user_id FROM stage_change_secondary_context)
    ELSE (SELECT app_user_id FROM stage_change_primary_context)
  END,
  fixture.changed_at_utc
FROM relationship_stage_change_fixture AS fixture
JOIN stage_change_target_map AS target_map
  ON target_map.target_key = fixture.target_key
WHERE fixture.scenario_key = 'primary_events'
  AND fixture.revision_number > 1;

-- The trigger-installed revision is always revision 1. Promote the current
-- projection only after the complete historical chain has been inserted.
UPDATE app_data.promotion_target_project_relationships AS relationship_row
SET current_stage = latest.new_stage,
    current_revision = latest.revision_number,
    current_lifecycle_status = 'active',
    updated_at = latest.changed_at_utc
FROM (
  SELECT DISTINCT ON (fixture.target_key)
    fixture.target_key,
    fixture.new_stage,
    fixture.revision_number,
    fixture.changed_at_utc
  FROM relationship_stage_change_fixture AS fixture
  WHERE fixture.scenario_key = 'primary_events'
  ORDER BY fixture.target_key, fixture.revision_number DESC
) AS latest
JOIN stage_change_target_map AS target_map
  ON target_map.target_key = latest.target_key
WHERE relationship_row.promotion_target_id = target_map.target_id;

-- Use the production anonymization path. It ends the assignment and appends a
-- same-stage lifecycle revision after target-d's qualifying stage event. The
-- summary must preserve the earlier event and exclude the generated revision.
SELECT app_data.anonymize_promotion_target_internal(
  (SELECT app_user_id FROM stage_change_primary_context),
  (SELECT target_id
   FROM stage_change_target_map
   WHERE target_key = 'target-d'),
  'withdrawal',
  '2030-01-06T00:00:00Z'::timestamptz
);

-- Exercise the production relationship mutation replay before reading. The
-- first call adds one event; the identical mutation must return the same
-- result without adding another revision.
GRANT SELECT ON stage_change_target_map TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE stage_change_first_mutation AS
SELECT result
FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM stage_change_primary_context),
  (SELECT workspace_id FROM stage_change_primary_context),
  (SELECT project_id FROM stage_change_empty_project_context),
  (SELECT target_id
   FROM stage_change_target_map
   WHERE target_key = 'target-replay'),
  1,
  2,
  'active',
  NULL,
  'progress_update',
  NULL,
  'stage-change-summary-replay-1',
  NULL
);

CREATE TEMP TABLE stage_change_replayed_mutation AS
SELECT result
FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM stage_change_primary_context),
  (SELECT workspace_id FROM stage_change_primary_context),
  (SELECT project_id FROM stage_change_empty_project_context),
  (SELECT target_id
   FROM stage_change_target_map
   WHERE target_key = 'target-replay'),
  1,
  2,
  'active',
  NULL,
  'progress_update',
  NULL,
  'stage-change-summary-replay-1',
  NULL
);

RESET ROLE;

CREATE TEMP TABLE stage_change_replay_period AS
SELECT
  revision_row.changed_at AS from_utc,
  revision_row.changed_at + interval '1 microsecond' AS until_utc
FROM app_data.promotion_target_relationship_revisions AS revision_row
WHERE revision_row.changed_by_app_user_id =
    (SELECT app_user_id FROM stage_change_primary_context)
  AND revision_row.mutation_id = 'stage-change-summary-replay-1';

GRANT SELECT ON stage_change_replay_period TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

SELECT count(*)
FROM app_data.select_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  (SELECT project_id FROM stage_change_empty_project_context)
);

CREATE TEMP TABLE stage_change_replay_summary AS
SELECT app_data.read_personal_relationship_stage_change_summary_v1(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  (SELECT from_utc FROM stage_change_replay_period),
  (SELECT until_utc FROM stage_change_replay_period)
) AS summary;

SELECT count(*)
FROM app_data.select_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  (SELECT project_id FROM stage_change_primary_context)
);

RESET ROLE;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE stage_change_primary_result AS
SELECT app_data.read_personal_relationship_stage_change_summary_v1(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  '2030-01-01T00:00:00Z'::timestamptz,
  '2030-01-08T00:00:00Z'::timestamptz
) AS summary;

CREATE TEMP TABLE stage_change_empty_result AS
SELECT app_data.read_personal_relationship_stage_change_summary_v1(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  '2040-01-01T00:00:00Z'::timestamptz,
  '2040-01-08T00:00:00Z'::timestamptz
) AS summary;

SELECT count(*)
FROM app_data.select_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  (SELECT project_id FROM stage_change_other_project_context)
);

CREATE TEMP TABLE stage_change_other_project_result AS
SELECT app_data.read_personal_relationship_stage_change_summary_v1(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  '2030-01-01T00:00:00Z'::timestamptz,
  '2030-01-08T00:00:00Z'::timestamptz
) AS summary;

RESET ROLE;

-- Restore the pointer for any later statements in this fixture and assert the
-- exact envelope and value keys returned by the bridge.
SET LOCAL ROLE tongxingzhe_runtime;
SELECT count(*)
FROM app_data.select_personal_project_context(
  'https://synthetic-stage-change-summary.example.test/auth/v1',
  'stage-change-summary-owner',
  (SELECT project_id FROM stage_change_primary_context)
);
RESET ROLE;

DO $summary_checks$
DECLARE
  primary_summary jsonb := (SELECT summary FROM stage_change_primary_result);
  empty_summary jsonb := (SELECT summary FROM stage_change_empty_result);
  other_project_summary jsonb := (
    SELECT summary FROM stage_change_other_project_result
  );
  replay_summary jsonb := (SELECT summary FROM stage_change_replay_summary);
  primary_snapshot_time timestamptz;
BEGIN
  IF (SELECT count(*) FROM stage_change_primary_result) <> 1
    OR (SELECT count(*) FROM stage_change_empty_result) <> 1
    OR (SELECT count(*) FROM stage_change_other_project_result) <> 1
  THEN
    RAISE EXCEPTION 'stage change summary bridge did not return one envelope';
  END IF;

  IF primary_summary IS NULL
    OR primary_summary - ARRAY[
      'contract_id', 'project_id', 'time_basis', 'period',
      'data_cutoff_utc', 'authorized_at_utc', 'value'
    ] <> '{}'::jsonb
    OR (primary_summary->'period') - ARRAY['from_utc', 'until_utc'] <> '{}'::jsonb
    OR (primary_summary->'value') - ARRAY[
      'event_count', 'distinct_relationship_count', 'upward_count',
      'downward_count'
    ] <> '{}'::jsonb
  THEN
    RAISE EXCEPTION 'stage change summary envelope keys drifted';
  END IF;

  IF primary_summary->>'contract_id' <>
      'personal_relationship_stage_change_summary_result_v1'
    OR primary_summary->>'time_basis' <> 'relationshipChangedAtUtc'
    OR primary_summary->>'project_id' <>
      (SELECT project_id::text FROM stage_change_primary_context)
    OR (primary_summary#>>'{period,from_utc}') <>
      '2030-01-01T00:00:00.000000Z'
    OR (primary_summary#>>'{period,until_utc}') <>
      '2030-01-08T00:00:00.000000Z'
    OR (primary_summary#>>'{value,event_count}')::bigint <> 5
    OR (primary_summary#>>'{value,distinct_relationship_count}')::bigint <> 4
    OR (primary_summary#>>'{value,upward_count}')::bigint <> 3
    OR (primary_summary#>>'{value,downward_count}')::bigint <> 2
  THEN
    RAISE EXCEPTION 'primary stage change summary diverged';
  END IF;

  primary_snapshot_time := (primary_summary->>'data_cutoff_utc')::timestamptz;
  IF NOT isfinite(primary_snapshot_time)
    OR primary_summary->>'authorized_at_utc' <>
      primary_summary->>'data_cutoff_utc'
    OR primary_snapshot_time > clock_timestamp()
  THEN
    RAISE EXCEPTION 'stage change summary metadata is not a trusted UTC snapshot';
  END IF;

  IF empty_summary->>'project_id' <>
      (SELECT project_id::text FROM stage_change_primary_context)
    OR (empty_summary#>>'{value,event_count}')::bigint <> 0
    OR (empty_summary#>>'{value,distinct_relationship_count}')::bigint <> 0
    OR (empty_summary#>>'{value,upward_count}')::bigint <> 0
    OR (empty_summary#>>'{value,downward_count}')::bigint <> 0
  THEN
    RAISE EXCEPTION 'empty stage change summary is not four zero counts';
  END IF;

  IF other_project_summary->>'project_id' <>
      (SELECT project_id::text FROM stage_change_other_project_context)
    OR (other_project_summary#>>'{value,event_count}')::bigint <> 1
    OR (other_project_summary#>>'{value,upward_count}')::bigint <> 1
    OR (other_project_summary#>>'{value,downward_count}')::bigint <> 0
  THEN
    RAISE EXCEPTION 'current-project switch did not isolate the other project';
  END IF;

  IF (SELECT result->>'status' FROM stage_change_first_mutation)
      IS DISTINCT FROM 'accepted'
    OR (SELECT (result->>'duplicate')::boolean
        FROM stage_change_first_mutation) IS DISTINCT FROM false
    OR (SELECT result->>'status' FROM stage_change_replayed_mutation)
      IS DISTINCT FROM 'accepted'
    OR (SELECT (result->>'duplicate')::boolean
        FROM stage_change_replayed_mutation) IS DISTINCT FROM true
    OR (SELECT result->'relationship' FROM stage_change_first_mutation) IS NULL
    OR (SELECT result->'relationship' FROM stage_change_first_mutation)
      IS DISTINCT FROM
      (SELECT result->'relationship' FROM stage_change_replayed_mutation)
    OR (SELECT (result->>'accepted_revision')::integer
        FROM stage_change_first_mutation) IS DISTINCT FROM 2
    OR (SELECT (result->>'accepted_revision')::integer
        FROM stage_change_replayed_mutation) IS DISTINCT FROM 2
    OR (SELECT count(*)
        FROM app_data.promotion_target_relationship_revisions
        WHERE changed_by_app_user_id =
          (SELECT app_user_id FROM stage_change_primary_context)
          AND mutation_id = 'stage-change-summary-replay-1') <> 1
    OR (replay_summary#>>'{value,event_count}')::bigint <> 1
    OR (replay_summary#>>'{value,distinct_relationship_count}')::bigint <> 1
    OR (replay_summary#>>'{value,upward_count}')::bigint <> 1
    OR (replay_summary#>>'{value,downward_count}')::bigint <> 0
  THEN
    RAISE EXCEPTION
      'mutation replay changed the stage event summary: first=%, replay=%, revisions=%, summary=%',
      (SELECT result FROM stage_change_first_mutation),
      (SELECT result FROM stage_change_replayed_mutation),
      (SELECT count(*)
       FROM app_data.promotion_target_relationship_revisions
       WHERE changed_by_app_user_id =
         (SELECT app_user_id FROM stage_change_primary_context)
         AND mutation_id = 'stage-change-summary-replay-1'),
      replay_summary;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.promotion_target_relationship_revisions AS revision_row
    WHERE revision_row.promotion_target_id = (
      SELECT target_id
      FROM stage_change_target_map
      WHERE target_key = 'target-d'
    )
      AND revision_row.old_stage = revision_row.new_stage
      AND 'lifecycle_status' = ANY (revision_row.changed_fields)
  ) THEN
    RAISE EXCEPTION 'anonymization did not install the excluded lifecycle revision';
  END IF;

  IF primary_summary::text ~* 'display_name|phone|email|follow_up_note|reason|revision'
  THEN
    RAISE EXCEPTION 'stage change summary contains PII or revision details';
  END IF;
END
$summary_checks$;

ROLLBACK;
