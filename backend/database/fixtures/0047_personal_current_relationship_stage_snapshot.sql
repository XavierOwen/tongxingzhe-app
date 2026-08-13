-- synthetic fixture：个人当前关系阶段 PII-free snapshot。
--
-- 共享 CSV 固定跨层 admission 语义。本 fixture 读取其中的主场景，建立
-- 对应的 synthetic PostgreSQL rows，再核对 bridge 的 active scope、UTC
-- metadata、五档 stage、空结果和 cross-project isolation。duplicate 场景
-- 保留在共享输入中，但不伪造违反生产主键的重复关系。

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE current_relationship_stage_fixture (
  scenario_key text NOT NULL,
  row_key text NOT NULL,
  query_viewer_key text NOT NULL,
  query_project_key text NOT NULL,
  target_key text NOT NULL,
  relationship_project_key text NOT NULL,
  assigned_viewer_key text NOT NULL,
  stage integer NOT NULL,
  lifecycle_status text NOT NULL,
  target_status text NOT NULL,
  assignment_status text NOT NULL,
  current_revision integer NOT NULL,
  updated_at_utc timestamptz NOT NULL,
  snapshot_as_of_utc timestamptz NOT NULL,
  expected_in_current_snapshot boolean NOT NULL,
  expected_reason text NOT NULL,
  expected_scenario_result text NOT NULL
);

\copy current_relationship_stage_fixture FROM 'backend/database/fixtures/shared/current_relationship_stage_v1.csv' WITH (FORMAT csv, HEADER true)

DO $fixture_input_checks$
BEGIN
  IF (SELECT count(*) FROM current_relationship_stage_fixture) <> 13
    OR (SELECT count(*) FROM current_relationship_stage_fixture
        WHERE scenario_key = 'primary_current') <> 11
    OR (SELECT count(*) FROM current_relationship_stage_fixture
        WHERE scenario_key = 'duplicate_projection') <> 2
    OR (SELECT count(*) FROM current_relationship_stage_fixture
        WHERE expected_scenario_result = 'duplicate_target_project') <> 2
  THEN
    RAISE EXCEPTION 'current relationship shared fixture was not consumed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM current_relationship_stage_fixture
    WHERE stage NOT BETWEEN 0 AND 4
      OR current_revision < 1
      OR updated_at_utc > snapshot_as_of_utc
  ) THEN
    RAISE EXCEPTION 'current relationship shared fixture has invalid values';
  END IF;
END
$fixture_input_checks$;

CREATE TEMP TABLE current_relationship_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-current-relationship-stage.example.test/auth/v1',
  'current-relationship-stage-owner'
);

CREATE TEMP TABLE current_relationship_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-current-relationship-stage.example.test/auth/v1',
  'current-relationship-stage-secondary'
);

CREATE TEMP TABLE current_relationship_other_project_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-current-relationship-stage.example.test/auth/v1',
  'current-relationship-stage-owner',
  '当前关系阶段其他项目'
);

CREATE TEMP TABLE current_relationship_empty_project_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-current-relationship-stage.example.test/auth/v1',
  'current-relationship-stage-owner',
  '当前关系阶段空项目'
);

CREATE TEMP TABLE current_relationship_target_map AS
SELECT
  requested.target_key,
  (created.target->>'target_id')::uuid AS target_id
FROM (
  SELECT DISTINCT target_key
  FROM current_relationship_stage_fixture
  WHERE scenario_key IN ('primary_current', 'duplicate_projection')
) AS requested
CROSS JOIN LATERAL app_data.create_promotion_target(
  (SELECT app_user_id FROM current_relationship_owner_context),
  (SELECT workspace_id FROM current_relationship_owner_context),
  (SELECT project_id FROM current_relationship_owner_context),
  'person',
  '当前阶段 synthetic ' || requested.target_key,
  NULL,
  NULL,
  'current-relationship-stage-' || replace(requested.target_key, '-', '_')
) AS created;

RESET ROLE;

-- The authoritative relation table has one target×project primary key. Insert
-- the final current projections from the shared admission rows; historical
-- revision fidelity is covered by 0018 and is intentionally out of this read.
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
  CASE fixture.relationship_project_key
    WHEN 'other' THEN (
      SELECT project_id FROM current_relationship_other_project_context
    )
    ELSE (SELECT project_id FROM current_relationship_owner_context)
  END,
  fixture.stage,
  fixture.lifecycle_status,
  1,
  (SELECT app_user_id FROM current_relationship_owner_context),
  (SELECT app_user_id FROM current_relationship_owner_context),
  fixture.updated_at_utc
FROM current_relationship_stage_fixture AS fixture
JOIN current_relationship_target_map AS target_map
  ON target_map.target_key = fixture.target_key
WHERE fixture.scenario_key = 'primary_current';

-- Initial-revision triggers require revision 1. Promote the current projection
-- after insertion so the fixture can cover non-default current_revision values
-- without fabricating a history row for this read-only contract.
UPDATE app_data.promotion_target_project_relationships AS relationship_row
SET current_revision = fixture.current_revision,
    updated_at = fixture.updated_at_utc
FROM current_relationship_stage_fixture AS fixture
JOIN current_relationship_target_map AS target_map
  ON target_map.target_key = fixture.target_key
WHERE fixture.scenario_key = 'primary_current'
  AND relationship_row.promotion_target_id = target_map.target_id
  AND relationship_row.project_id = CASE fixture.relationship_project_key
    WHEN 'other' THEN (SELECT project_id FROM current_relationship_other_project_context)
    ELSE (SELECT project_id FROM current_relationship_owner_context)
  END;

-- Anonymization and assignment revocation are represented by their current
-- source states. The retention slice owns the destructive workflow itself.
UPDATE app_data.promotion_targets
SET display_name = '已匿名化对象',
    phone = NULL,
    email = NULL,
    status = 'anonymized',
    anonymized_at = clock_timestamp(),
    anonymization_reason = 'withdrawal'
WHERE promotion_target_id = (
  SELECT target_id
  FROM current_relationship_target_map
  WHERE target_key = 'target-anonymized'
);

UPDATE app_data.promotion_target_assignments
SET ended_at = clock_timestamp(),
    end_reason = 'synthetic current relationship stage fixture'
WHERE promotion_target_id IN (
  SELECT target_id
  FROM current_relationship_target_map
  WHERE target_key IN (
    'target-anonymized', 'target-unassigned', 'target-other-viewer'
  )
)
  AND app_user_id = (SELECT app_user_id FROM current_relationship_owner_context)
  AND ended_at IS NULL;

-- Keep a current assignment for the secondary synthetic viewer only. It is a
-- different personal workspace and therefore must never enter the owner query.
INSERT INTO app_data.promotion_target_assignments (
  promotion_target_id,
  app_user_id,
  assigned_by_app_user_id
)
VALUES (
  (
    SELECT target_id
    FROM current_relationship_target_map
    WHERE target_key = 'target-other-viewer'
  ),
  (SELECT app_user_id FROM current_relationship_secondary_context),
  (SELECT app_user_id FROM current_relationship_owner_context)
);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE current_relationship_primary_result AS
SELECT snapshot
FROM app_data.read_personal_current_relationship_stage_snapshot(
  (SELECT app_user_id FROM current_relationship_owner_context),
  (SELECT workspace_id FROM current_relationship_owner_context),
  (SELECT project_id FROM current_relationship_owner_context)
);

CREATE TEMP TABLE current_relationship_other_project_result AS
SELECT snapshot
FROM app_data.read_personal_current_relationship_stage_snapshot(
  (SELECT app_user_id FROM current_relationship_owner_context),
  (SELECT workspace_id FROM current_relationship_owner_context),
  (SELECT project_id FROM current_relationship_other_project_context)
);

CREATE TEMP TABLE current_relationship_empty_result AS
SELECT snapshot
FROM app_data.read_personal_current_relationship_stage_snapshot(
  (SELECT app_user_id FROM current_relationship_owner_context),
  (SELECT workspace_id FROM current_relationship_owner_context),
  (SELECT project_id FROM current_relationship_empty_project_context)
);

CREATE TEMP TABLE current_relationship_primary_rows AS
SELECT row_data.*
FROM current_relationship_primary_result AS result_row
CROSS JOIN LATERAL jsonb_to_recordset(result_row.snapshot->'relationships') AS row_data(
  target_key uuid,
  stage integer,
  revision integer,
  updated_at_utc text
);

CREATE TEMP TABLE current_relationship_other_project_rows AS
SELECT row_data.*
FROM current_relationship_other_project_result AS result_row
CROSS JOIN LATERAL jsonb_to_recordset(result_row.snapshot->'relationships') AS row_data(
  target_key uuid,
  stage integer,
  revision integer,
  updated_at_utc text
);

DO $snapshot_checks$
DECLARE
  primary_snapshot jsonb := (SELECT snapshot FROM current_relationship_primary_result);
  other_project_snapshot jsonb := (
    SELECT snapshot FROM current_relationship_other_project_result
  );
  empty_snapshot jsonb := (SELECT snapshot FROM current_relationship_empty_result);
  snapshot_time timestamptz;
  source_cutoff timestamptz;
  relationship_row jsonb;
BEGIN
  IF (SELECT count(*) FROM current_relationship_primary_result) <> 1
    OR (SELECT count(*) FROM current_relationship_other_project_result) <> 1
    OR (SELECT count(*) FROM current_relationship_empty_result) <> 1
  THEN
    RAISE EXCEPTION 'current relationship bridge did not return one envelope';
  END IF;

  IF primary_snapshot->>'contract_id' <>
      'current_relationship_stage_distribution@1'
    OR primary_snapshot->>'statistical_unit' <> 'targetProjectRelationship'
    OR primary_snapshot->>'project_key' <>
      (SELECT project_id::text FROM current_relationship_owner_context)
    OR jsonb_typeof(primary_snapshot->'relationships') <> 'array'
    OR jsonb_typeof(primary_snapshot->'coverage') <> 'object'
  THEN
    RAISE EXCEPTION 'current relationship snapshot contract drifted';
  END IF;

  snapshot_time := (primary_snapshot->>'snapshot_as_of_utc')::timestamptz;
  source_cutoff := (primary_snapshot->>'source_cutoff_utc')::timestamptz;
  IF primary_snapshot->>'authorized_at_utc' <>
      primary_snapshot->>'snapshot_as_of_utc'
    OR source_cutoff > snapshot_time
    OR (primary_snapshot#>>'{coverage,pending}')::integer <> 0
    OR (primary_snapshot#>>'{coverage,total}')::integer <> 5
    OR jsonb_array_length(primary_snapshot->'relationships') <> 5
  THEN
    RAISE EXCEPTION 'current relationship snapshot metadata or total drifted';
  END IF;

  IF (SELECT count(*) FROM current_relationship_primary_rows) <> 5
    OR (SELECT count(DISTINCT target_key)
        FROM current_relationship_primary_rows) <> 5
    OR EXISTS (
      SELECT 1
      FROM current_relationship_primary_rows
      WHERE stage NOT BETWEEN 0 AND 4
        OR revision < 1
        OR updated_at_utc::timestamptz > snapshot_time
    )
  THEN
    RAISE EXCEPTION 'current relationship rows are not unique or bounded';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM current_relationship_stage_fixture AS expected
    JOIN current_relationship_target_map AS target_map
      ON target_map.target_key = expected.target_key
    LEFT JOIN current_relationship_primary_rows AS actual
      ON actual.target_key = target_map.target_id
    WHERE expected.scenario_key = 'primary_current'
      AND expected.expected_in_current_snapshot
      AND (
        actual.target_key IS NULL
        OR actual.stage <> expected.stage
        OR actual.revision <> expected.current_revision
        OR actual.updated_at_utc::timestamptz <> expected.updated_at_utc
      )
  ) THEN
    RAISE EXCEPTION 'shared fixture active stages did not reach the bridge';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM current_relationship_stage_fixture AS expected
    JOIN current_relationship_target_map AS target_map
      ON target_map.target_key = expected.target_key
    JOIN current_relationship_primary_rows AS actual
      ON actual.target_key = target_map.target_id
    WHERE expected.scenario_key = 'primary_current'
      AND NOT expected.expected_in_current_snapshot
      AND expected.expected_reason <> 'other_project'
  ) THEN
    RAISE EXCEPTION 'excluded current relationship entered the bridge';
  END IF;

  IF (
    SELECT count(*)
    FROM current_relationship_primary_rows
    WHERE stage = 0
  ) <> 1 OR (
    SELECT count(*)
    FROM current_relationship_primary_rows
    WHERE stage = 1
  ) <> 1 OR (
    SELECT count(*)
    FROM current_relationship_primary_rows
    WHERE stage = 2
  ) <> 1 OR (
    SELECT count(*)
    FROM current_relationship_primary_rows
    WHERE stage = 3
  ) <> 1 OR (
    SELECT count(*)
    FROM current_relationship_primary_rows
    WHERE stage = 4
  ) <> 1
  THEN
    RAISE EXCEPTION 'current relationship five-stage distribution diverged';
  END IF;

  IF source_cutoff <> (
    SELECT max(updated_at_utc)
    FROM current_relationship_stage_fixture
    WHERE scenario_key = 'primary_current'
      AND expected_in_current_snapshot
  ) THEN
    RAISE EXCEPTION 'shared fixture source cutoff did not reach the bridge';
  END IF;

  IF (SELECT count(*) FROM current_relationship_other_project_rows) <> 1
    OR (SELECT stage FROM current_relationship_other_project_rows) <> 4
    OR (SELECT revision FROM current_relationship_other_project_rows) <> 1
    OR other_project_snapshot->>'project_key' <>
      (SELECT project_id::text FROM current_relationship_other_project_context)
  THEN
    RAISE EXCEPTION 'current relationship project scope diverged';
  END IF;

  IF empty_snapshot->>'contract_id' <>
      'current_relationship_stage_distribution@1'
    OR jsonb_array_length(empty_snapshot->'relationships') <> 0
    OR (empty_snapshot#>>'{coverage,total}')::integer <> 0
    OR (empty_snapshot#>>'{coverage,pending}')::integer <> 0
    OR empty_snapshot->>'snapshot_as_of_utc' <>
      empty_snapshot->>'source_cutoff_utc'
    OR empty_snapshot->>'authorized_at_utc' <>
      empty_snapshot->>'snapshot_as_of_utc'
  THEN
    RAISE EXCEPTION 'empty current relationship scope lost metadata';
  END IF;

  IF primary_snapshot::text ~* 'display_name|phone|email|follow_up_note|history'
    OR other_project_snapshot::text ~* 'display_name|phone|email|follow_up_note|history'
  THEN
    RAISE EXCEPTION 'current relationship snapshot contains PII or history';
  END IF;

  FOR relationship_row IN
    SELECT value FROM jsonb_array_elements(primary_snapshot->'relationships')
  LOOP
    IF relationship_row ?| ARRAY[
      'display_name', 'phone', 'email', 'follow_up_note', 'lifecycle_status'
    ] THEN
      RAISE EXCEPTION 'current relationship row contains forbidden fields';
    END IF;
  END LOOP;

  IF (
    SELECT count(*)
    FROM current_relationship_stage_fixture
    WHERE scenario_key = 'duplicate_projection'
      AND expected_scenario_result = 'duplicate_target_project'
  ) <> 2
  THEN
    RAISE EXCEPTION 'duplicate projection fail-closed case was not consumed';
  END IF;
END
$snapshot_checks$;

RESET ROLE;

-- The production table cannot contain two current rows for one target×project.
-- Execute the shared duplicate scenario against that boundary instead of only
-- counting its CSV rows. Client fail-closed parsing is covered by the Flutter
-- consumer of the same scenario.
DO $duplicate_projection_check$
DECLARE
  duplicate_target_id uuid := (
    SELECT target_id
    FROM current_relationship_target_map
    WHERE target_key = 'target-duplicate'
  );
  duplicate_project_id uuid := (
    SELECT project_id FROM current_relationship_owner_context
  );
  owner_id uuid := (SELECT app_user_id FROM current_relationship_owner_context);
BEGIN
  INSERT INTO app_data.promotion_target_project_relationships (
    promotion_target_id,
    project_id,
    current_stage,
    current_revision,
    established_by_app_user_id,
    updated_by_app_user_id,
    updated_at
  )
  SELECT
    duplicate_target_id,
    duplicate_project_id,
    stage,
    current_revision,
    owner_id,
    owner_id,
    updated_at_utc
  FROM current_relationship_stage_fixture
  WHERE scenario_key = 'duplicate_projection'
    AND row_key = 'duplicate-a';

  BEGIN
    INSERT INTO app_data.promotion_target_project_relationships (
      promotion_target_id,
      project_id,
      current_stage,
      current_revision,
      established_by_app_user_id,
      updated_by_app_user_id,
      updated_at
    )
    SELECT
      duplicate_target_id,
      duplicate_project_id,
      stage,
      current_revision,
      owner_id,
      owner_id,
      updated_at_utc
    FROM current_relationship_stage_fixture
    WHERE scenario_key = 'duplicate_projection'
      AND row_key = 'duplicate-b';
    RAISE EXCEPTION 'duplicate target-project projection was accepted';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
  END;

  IF (
    SELECT count(*)
    FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id = duplicate_target_id
      AND project_id = duplicate_project_id
  ) <> 1 THEN
    RAISE EXCEPTION 'duplicate target-project rejection left invalid state';
  END IF;
END
$duplicate_projection_check$;

DO $forbidden_scope_check$
BEGIN
  SET LOCAL ROLE tongxingzhe_runtime;
  BEGIN
    PERFORM app_data.read_personal_current_relationship_stage_snapshot(
      (SELECT app_user_id FROM current_relationship_secondary_context),
      (SELECT workspace_id FROM current_relationship_owner_context),
      (SELECT project_id FROM current_relationship_owner_context)
    );
    RAISE EXCEPTION 'cross-workspace current relationship scope was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
  RESET ROLE;
END
$forbidden_scope_check$;

ROLLBACK;
