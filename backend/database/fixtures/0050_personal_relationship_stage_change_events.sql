-- PostgreSQL fixture：个人关系阶段变更事件合同 v1。
--
-- 这个 fixture 只消费与 Dart 共用的无 PII CSV，并在 PostgreSQL 中重新计算
-- 候选边界和四个预期汇总值。它不调用生产 bridge，也不写入生产关系表；
-- duplicate_revision 场景模拟消费者必须失败关闭的重复 revision 输入。

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

DO $fixture_input_checks$
BEGIN
  IF (SELECT count(*) FROM relationship_stage_change_fixture) <> 17
    OR (SELECT count(*) FROM relationship_stage_change_fixture
        WHERE scenario_key = 'primary_events') <> 14
    OR (SELECT count(*) FROM relationship_stage_change_fixture
        WHERE scenario_key = 'duplicate_revision') <> 3
  THEN
    RAISE EXCEPTION 'relationship stage change shared fixture was not fully consumed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE scenario_key NOT IN ('primary_events', 'duplicate_revision')
      OR btrim(row_key) = ''
      OR btrim(query_actor_key) = ''
      OR btrim(query_workspace_key) = ''
      OR btrim(query_project_key) = ''
      OR btrim(target_key) = ''
      OR btrim(relationship_workspace_key) = ''
      OR btrim(relationship_project_key) = ''
      OR btrim(changed_by_actor_key) = ''
      OR revision_number < 1
      OR new_stage NOT BETWEEN 0 AND 4
      OR (old_stage IS NOT NULL AND old_stage NOT BETWEEN 0 AND 4)
      OR period_from_utc >= period_until_utc
      OR NOT isfinite(changed_at_utc)
      OR NOT isfinite(period_from_utc)
      OR NOT isfinite(period_until_utc)
      OR reason_code NOT IN (
        'project_entry',
        'progress_update',
        'contact_lost',
        'timing_changed',
        'requirements_changed',
        'target_request',
        'project_change',
        'correction',
        'other'
      )
      OR current_assignment_status NOT IN ('active', 'ended', 'none')
      OR expected_event_count < 0
      OR expected_distinct_relationship_count < 0
      OR expected_upward_count < 0
      OR expected_downward_count < 0
      OR expected_scenario_result NOT IN (
        'valid', 'duplicate_revision_fail_closed'
      )
  ) THEN
    RAISE EXCEPTION 'relationship stage change shared fixture has invalid values';
  END IF;

  IF (SELECT count(DISTINCT row_key)
      FROM relationship_stage_change_fixture)
      <> (SELECT count(*) FROM relationship_stage_change_fixture)
  THEN
    RAISE EXCEPTION 'relationship stage change fixture row keys are not unique';
  END IF;

  IF EXISTS (
    SELECT scenario_key
    FROM relationship_stage_change_fixture
    GROUP BY scenario_key
    HAVING count(DISTINCT query_actor_key) <> 1
      OR count(DISTINCT query_workspace_key) <> 1
      OR count(DISTINCT query_project_key) <> 1
      OR count(DISTINCT period_from_utc) <> 1
      OR count(DISTINCT period_until_utc) <> 1
      OR count(DISTINCT expected_event_count) <> 1
      OR count(DISTINCT expected_distinct_relationship_count) <> 1
      OR count(DISTINCT expected_upward_count) <> 1
      OR count(DISTINCT expected_downward_count) <> 1
  ) THEN
    RAISE EXCEPTION 'relationship stage change scenario context is inconsistent';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture AS fixture
    CROSS JOIN LATERAL unnest(string_to_array(fixture.changed_fields, '|'))
      AS changed_field(field_name)
    WHERE changed_field.field_name NOT IN (
      'stage', 'lifecycle_status', 'follow_up_note', 'conflict_resolution'
    )
      OR changed_field.field_name = ''
  ) THEN
    RAISE EXCEPTION 'relationship stage change fixture has an unknown changed field';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE scenario_key = 'primary_events'
      AND expected_scenario_result <> 'valid'
  ) OR EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE scenario_key = 'duplicate_revision'
      AND expected_scenario_result <> 'duplicate_revision_fail_closed'
  ) THEN
    RAISE EXCEPTION 'relationship stage change scenario result drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE old_stage IS NULL
      AND (revision_number <> 1 OR reason_code <> 'project_entry')
  ) OR EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE old_stage IS NOT NULL
      AND reason_code = 'project_entry'
  ) THEN
    RAISE EXCEPTION 'project entry old-stage semantics drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_fixture
    WHERE scenario_key = 'primary_events'
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
END
$fixture_input_checks$;

-- The revision identity deliberately excludes row_key and changed_at. Two rows
-- for the same target×workspace×project revision are one malformed input set,
-- and the whole duplicate scenario must be rejected before any count is used.
CREATE TEMP TABLE relationship_stage_change_scored AS
WITH revision_occurrences AS (
  SELECT
    fixture.*,
    count(*) OVER (
      PARTITION BY
        scenario_key,
        target_key,
        relationship_workspace_key,
        relationship_project_key,
        revision_number
    ) AS revision_occurrence_count
  FROM relationship_stage_change_fixture AS fixture
), scenario_occurrences AS (
  SELECT
    occurrence.*,
    bool_or(occurrence.revision_occurrence_count > 1) OVER (
      PARTITION BY occurrence.scenario_key
    ) AS scenario_has_duplicate_revision
  FROM revision_occurrences AS occurrence
)
SELECT
  occurrence.*,
  CASE
    WHEN occurrence.scenario_has_duplicate_revision
      THEN 'duplicate_revision'
    WHEN occurrence.relationship_workspace_key <> occurrence.query_workspace_key
      THEN 'other_workspace'
    WHEN occurrence.relationship_project_key <> occurrence.query_project_key
      THEN 'other_project'
    WHEN occurrence.changed_by_actor_key <> occurrence.query_actor_key
      THEN 'other_actor'
    WHEN occurrence.changed_at_utc < occurrence.period_from_utc
      THEN 'before_period'
    WHEN occurrence.changed_at_utc >= occurrence.period_until_utc
      THEN 'period_until'
    WHEN occurrence.old_stage IS NULL
      OR occurrence.reason_code = 'project_entry'
      THEN 'project_entry'
    WHEN NOT (
      'stage' = ANY(string_to_array(occurrence.changed_fields, '|'))
    )
      THEN 'lifecycle_only'
    WHEN occurrence.old_stage = occurrence.new_stage
      THEN 'same_stage'
    ELSE 'included'
  END AS computed_reason,
  NOT occurrence.scenario_has_duplicate_revision
    AND occurrence.relationship_workspace_key = occurrence.query_workspace_key
    AND occurrence.relationship_project_key = occurrence.query_project_key
    AND occurrence.changed_by_actor_key = occurrence.query_actor_key
    AND occurrence.changed_at_utc >= occurrence.period_from_utc
    AND occurrence.changed_at_utc < occurrence.period_until_utc
    AND occurrence.old_stage IS NOT NULL
    AND occurrence.reason_code <> 'project_entry'
    AND 'stage' = ANY(string_to_array(occurrence.changed_fields, '|'))
    AND occurrence.old_stage <> occurrence.new_stage
    AS computed_in_personal_metric
FROM scenario_occurrences AS occurrence;

DO $eligibility_checks$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE expected_reason <> computed_reason
      OR expected_in_personal_metric IS DISTINCT FROM
        computed_in_personal_metric
  ) THEN
    RAISE EXCEPTION 'relationship stage change candidate boundary drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'primary_events'
      AND computed_reason = 'lifecycle_only'
      AND changed_fields = 'lifecycle_status'
  ) OR NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'primary_events'
      AND computed_reason = 'lifecycle_only'
      AND changed_fields = 'follow_up_note'
  ) OR NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'primary_events'
      AND computed_reason = 'same_stage'
  ) THEN
    RAISE EXCEPTION 'lifecycle, note-only, or same-stage exclusion is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'primary_events'
      AND computed_in_personal_metric
      AND current_assignment_status = 'ended'
  ) OR NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'primary_events'
      AND computed_in_personal_metric
      AND changed_at_utc = period_from_utc
  ) THEN
    RAISE EXCEPTION 'eligibility incorrectly filtered ended assignment or lower boundary';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'primary_events'
      AND target_key = 'target-a'
      AND computed_in_personal_metric
    GROUP BY target_key
    HAVING count(*) = 2
       AND count(DISTINCT revision_number) = 2
  ) THEN
    RAISE EXCEPTION 'multiple revisions of one relationship were not retained as events';
  END IF;

  IF (
    SELECT count(*)
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'duplicate_revision'
      AND scenario_has_duplicate_revision
      AND NOT computed_in_personal_metric
      AND expected_reason = 'duplicate_revision'
  ) <> 3
  THEN
    RAISE EXCEPTION 'duplicate revision scenario was not rejected fail-closed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'duplicate_revision'
      AND revision_occurrence_count = 1
      AND scenario_has_duplicate_revision
      AND NOT computed_in_personal_metric
  ) THEN
    RAISE EXCEPTION 'otherwise-valid row escaped duplicate scenario rejection';
  END IF;
END
$eligibility_checks$;

CREATE TEMP TABLE relationship_stage_change_summary AS
SELECT
  scenario_key,
  count(*) FILTER (WHERE computed_in_personal_metric)::integer AS event_count,
  count(DISTINCT (
    target_key || '|' || relationship_workspace_key || '|'
      || relationship_project_key
  )) FILTER (WHERE computed_in_personal_metric)::integer
    AS distinct_relationship_count,
  count(*) FILTER (
    WHERE computed_in_personal_metric AND new_stage > old_stage
  )::integer AS upward_count,
  count(*) FILTER (
    WHERE computed_in_personal_metric AND new_stage < old_stage
  )::integer AS downward_count
FROM relationship_stage_change_scored
GROUP BY scenario_key;

DO $summary_checks$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored AS fixture
    JOIN relationship_stage_change_summary AS summary
      ON summary.scenario_key = fixture.scenario_key
    WHERE fixture.expected_event_count <> summary.event_count
      OR fixture.expected_distinct_relationship_count <>
        summary.distinct_relationship_count
      OR fixture.expected_upward_count <> summary.upward_count
      OR fixture.expected_downward_count <> summary.downward_count
  ) THEN
    RAISE EXCEPTION 'relationship stage change expected summary diverged';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_summary
    WHERE scenario_key = 'primary_events'
      AND event_count = 5
      AND distinct_relationship_count = 4
      AND upward_count = 3
      AND downward_count = 2
  ) OR NOT EXISTS (
    SELECT 1
    FROM relationship_stage_change_summary
    WHERE scenario_key = 'duplicate_revision'
      AND event_count = 0
      AND distinct_relationship_count = 0
      AND upward_count = 0
      AND downward_count = 0
  ) THEN
    RAISE EXCEPTION 'relationship stage change independently recomputed totals drifted';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM relationship_stage_change_scored
    WHERE scenario_key = 'duplicate_revision'
      AND (
        expected_in_personal_metric
        OR computed_in_personal_metric
        OR expected_scenario_result <> 'duplicate_revision_fail_closed'
      )
  ) THEN
    RAISE EXCEPTION 'duplicate revision scenario was not fail-closed';
  END IF;
END
$summary_checks$;

ROLLBACK;
