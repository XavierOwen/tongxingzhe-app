-- PostgreSQL fixture：个人对象反应五档比例。
--
-- 该夹具使用独立的 synthetic 命名空间，覆盖混合五档（2/9）、全 NULL、
-- 空期间、current revision、作废、UTC 半开边界、跨项目／用户 scope 和
-- 非法期间。整个 fixture 回滚，因此恢复库可以重复运行而不会留下数据。

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_ratio_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response-ratio.example.test/auth/v1',
  'synthetic-target-response-ratio-owner'
);

CREATE TEMP TABLE target_response_ratio_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-target-response-ratio.example.test/auth/v1',
  'synthetic-target-response-ratio-owner',
  '对象反应比例其他项目'
);

CREATE TEMP TABLE target_response_ratio_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response-ratio.example.test/auth/v1',
  'synthetic-target-response-ratio-secondary'
);

CREATE TEMP TABLE target_response_ratio_targets AS
SELECT request.target_key,
       (created.target->>'target_id')::uuid AS target_id
FROM (
  VALUES
    ('level-0-a', '对象反应比例 0 A', 'target-response-ratio-level-0-a'),
    ('level-0-b', '对象反应比例 0 B', 'target-response-ratio-level-0-b'),
    ('level-1', '对象反应比例 1', 'target-response-ratio-level-1'),
    ('level-2-a', '对象反应比例 2 A', 'target-response-ratio-level-2-a'),
    ('level-2-b', '对象反应比例 2 B', 'target-response-ratio-level-2-b'),
    ('level-3-a', '对象反应比例 3 A', 'target-response-ratio-level-3-a'),
    ('level-3-b', '对象反应比例 3 B', 'target-response-ratio-level-3-b'),
    ('level-4-a', '对象反应比例 4 A', 'target-response-ratio-level-4-a'),
    ('level-4-b', '对象反应比例 4 B', 'target-response-ratio-level-4-b'),
    ('null-a', '对象反应比例未回答 A', 'target-response-ratio-null-a'),
    ('null-b', '对象反应比例未回答 B', 'target-response-ratio-null-b')
) AS request(target_key, display_name, request_id)
CROSS JOIN LATERAL app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  'person',
  request.display_name,
  NULL,
  NULL,
  request.request_id
) AS created;

CREATE TEMP TABLE target_response_ratio_secondary_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_ratio_secondary_context),
  (SELECT workspace_id FROM target_response_ratio_secondary_context),
  (SELECT project_id FROM target_response_ratio_secondary_context),
  'person',
  '对象反应比例次用户对象',
  NULL,
  NULL,
  'target-response-ratio-secondary-target'
);

RESET ROLE;

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
SELECT fixture.contact_id,
       context.app_user_id,
       context.workspace_id,
       context.project_id,
       context.questionnaire_version_id,
       fixture.occurred_at_utc,
       'America/Chicago',
       'video_call',
       'not_applicable',
       1,
       2,
       fixture.current_revision,
       fixture.lifecycle_status
FROM (
  VALUES
    ('target-response-ratio-mixed', '2030-01-10T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ratio-current', '2030-01-11T10:00:00Z'::timestamptz, 2, 'active'),
    ('target-response-ratio-voided', '2030-01-12T10:00:00Z'::timestamptz, 2, 'voided'),
    ('target-response-ratio-all-null', '2030-01-13T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ratio-from-boundary', '2030-01-08T00:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ratio-right-boundary', '2030-01-15T00:00:00Z'::timestamptz, 1, 'active')
) AS fixture(contact_id, occurred_at_utc, current_revision, lifecycle_status)
CROSS JOIN target_response_ratio_owner_context AS context;

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
SELECT
  'target-response-ratio-other-project',
  context.app_user_id,
  context.workspace_id,
  context.project_id,
  context.questionnaire_version_id,
  '2030-01-10T12:00:00Z',
  'America/Chicago',
  'video_call',
  'not_applicable',
  1,
  2,
  1,
  'active'
FROM target_response_ratio_other_project AS context;

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
SELECT
  'target-response-ratio-secondary',
  context.app_user_id,
  context.workspace_id,
  context.project_id,
  context.questionnaire_version_id,
  '2030-01-10T13:00:00Z',
  'America/Chicago',
  'video_call',
  'not_applicable',
  1,
  2,
  1,
  'active'
FROM target_response_ratio_secondary_context AS context;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT fixture.contact_id,
       fixture.revision_number,
       (SELECT app_user_id FROM target_response_ratio_owner_context),
       fixture.revision_kind,
       fixture.reason,
       '{}'::jsonb
FROM (
  VALUES
    ('target-response-ratio-mixed', 1, 'submitted', NULL),
    ('target-response-ratio-current', 1, 'submitted', NULL),
    ('target-response-ratio-current', 2, 'corrected', 'synthetic current revision'),
    ('target-response-ratio-voided', 1, 'submitted', NULL),
    ('target-response-ratio-voided', 2, 'voided', 'synthetic void'),
    ('target-response-ratio-all-null', 1, 'submitted', NULL),
    ('target-response-ratio-from-boundary', 1, 'submitted', NULL),
    ('target-response-ratio-right-boundary', 1, 'submitted', NULL)
) AS fixture(contact_id, revision_number, revision_kind, reason);

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT
  'target-response-ratio-other-project',
  1,
  context.app_user_id,
  'submitted',
  NULL,
  '{}'::jsonb
FROM target_response_ratio_other_project AS context;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT
  'target-response-ratio-secondary',
  1,
  context.app_user_id,
  'submitted',
  NULL,
  '{}'::jsonb
FROM target_response_ratio_secondary_context AS context;

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
)
VALUES
  -- Nine answered links exercise all five levels; each 2/9 row rounds to 2222.
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-0-a'), 0, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-0-b'), 0, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-1'), 1, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-2-a'), 2, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-2-b'), 2, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-3-a'), 3, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-3-b'), 3, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-4-a'), 4, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-4-b'), 4, 'unknown', false, true),
  ('target-response-ratio-mixed', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'null-a'), NULL, 'unknown', false, true),
  -- Old revision links must not leak into the current projection.
  ('target-response-ratio-current', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-4-a'), 4, 'unknown', false, true),
  ('target-response-ratio-current', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-1'), 1, 'unknown', false, true),
  ('target-response-ratio-current', 2, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-2-a'), 2, 'unknown', false, true),
  ('target-response-ratio-current', 2, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'null-b'), NULL, 'unknown', false, true),
  -- A voided contact retains stored links but contributes no ratio rows.
  ('target-response-ratio-voided', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-3-a'), 3, 'unknown', false, true),
  ('target-response-ratio-voided', 2, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-4-b'), 4, 'unknown', false, true),
  -- NULL-only links have a zero answered denominator.
  ('target-response-ratio-all-null', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'null-a'), NULL, 'unknown', false, true),
  ('target-response-ratio-all-null', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'null-b'), NULL, 'unknown', false, true),
  ('target-response-ratio-from-boundary', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-3-a'), 3, 'unknown', false, true),
  ('target-response-ratio-right-boundary', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-4-b'), 4, 'unknown', false, true),
  ('target-response-ratio-other-project', 1, (SELECT target_id FROM target_response_ratio_targets WHERE target_key = 'level-1'), 1, 'unknown', false, true),
  ('target-response-ratio-secondary', 1, (SELECT target->>'target_id' FROM target_response_ratio_secondary_target)::uuid, 2, 'unknown', false, true);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_ratio_mixed_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2030-01-10T00:00:00Z',
  '2030-01-11T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_current_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2030-01-11T00:00:00Z',
  '2030-01-12T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_voided_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2030-01-12T00:00:00Z',
  '2030-01-13T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_null_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2030-01-13T00:00:00Z',
  '2030-01-14T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_empty_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2031-01-01T00:00:00Z',
  '2031-01-02T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_from_boundary_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2030-01-08T00:00:00Z',
  '2030-01-10T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_right_boundary_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_owner_context),
  (SELECT workspace_id FROM target_response_ratio_owner_context),
  (SELECT project_id FROM target_response_ratio_owner_context),
  '2030-01-15T00:00:00Z',
  '2030-01-16T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_other_project_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_other_project),
  (SELECT workspace_id FROM target_response_ratio_other_project),
  (SELECT project_id FROM target_response_ratio_other_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_ratio_secondary_actual AS
SELECT *
FROM app_data.read_personal_target_response_level_ratios(
  (SELECT app_user_id FROM target_response_ratio_secondary_context),
  (SELECT workspace_id FROM target_response_ratio_secondary_context),
  (SELECT project_id FROM target_response_ratio_secondary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

RESET ROLE;

DO $target_response_ratio_check$
DECLARE
  level_result integer[];
BEGIN
  SELECT array_agg(response_level ORDER BY response_level)
    INTO level_result
  FROM target_response_ratio_mixed_actual;
  IF level_result IS DISTINCT FROM ARRAY[0, 1, 2, 3, 4]::integer[] THEN
    RAISE EXCEPTION 'target response ratio level order drifted: %', level_result;
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_mixed_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_mixed_actual
      WHERE denominator IS DISTINCT FROM 9
        OR unanswered_count IS DISTINCT FROM 1
        OR (response_level = 0 AND (numerator IS DISTINCT FROM 2 OR percentage_basis_points IS DISTINCT FROM 2222))
        OR (response_level = 1 AND (numerator IS DISTINCT FROM 1 OR percentage_basis_points IS DISTINCT FROM 1111))
        OR (response_level = 2 AND (numerator IS DISTINCT FROM 2 OR percentage_basis_points IS DISTINCT FROM 2222))
        OR (response_level = 3 AND (numerator IS DISTINCT FROM 2 OR percentage_basis_points IS DISTINCT FROM 2222))
        OR (response_level = 4 AND (numerator IS DISTINCT FROM 2 OR percentage_basis_points IS DISTINCT FROM 2222))
    )
  THEN
    RAISE EXCEPTION 'mixed target response ratios or 2/9 half-up rounding are incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_current_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_current_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 1
        OR (response_level = 2 AND (numerator IS DISTINCT FROM 1 OR percentage_basis_points IS DISTINCT FROM 10000))
        OR (response_level <> 2 AND (numerator IS DISTINCT FROM 0 OR percentage_basis_points IS DISTINCT FROM 0))
    )
  THEN
    RAISE EXCEPTION 'current contact revision leaked old target response links';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_voided_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_voided_actual
      WHERE numerator IS DISTINCT FROM 0
        OR denominator IS DISTINCT FROM 0
        OR unanswered_count IS DISTINCT FROM 0
        OR percentage_basis_points IS NOT NULL
    )
  THEN
    RAISE EXCEPTION 'voided contact was not excluded from target response ratios';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_null_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_null_actual
      WHERE numerator IS DISTINCT FROM 0
        OR denominator IS DISTINCT FROM 0
        OR unanswered_count IS DISTINCT FROM 2
        OR percentage_basis_points IS NOT NULL
    )
  THEN
    RAISE EXCEPTION 'NULL-only target response ratios are incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_empty_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_empty_actual
      WHERE numerator IS DISTINCT FROM 0
        OR denominator IS DISTINCT FROM 0
        OR unanswered_count IS DISTINCT FROM 0
        OR percentage_basis_points IS NOT NULL
    )
  THEN
    RAISE EXCEPTION 'empty target response ratios are incorrect';
  END IF;

  -- The left boundary is included in [from, until); the mixed contact at the
  -- right boundary is excluded from this window.
  IF (SELECT count(*) FROM target_response_ratio_from_boundary_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_from_boundary_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 3 AND (numerator IS DISTINCT FROM 1 OR percentage_basis_points IS DISTINCT FROM 10000))
        OR (response_level <> 3 AND (numerator IS DISTINCT FROM 0 OR percentage_basis_points IS DISTINCT FROM 0))
    )
  THEN
    RAISE EXCEPTION 'left UTC boundary handling is incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_right_boundary_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_right_boundary_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 4 AND (numerator IS DISTINCT FROM 1 OR percentage_basis_points IS DISTINCT FROM 10000))
        OR (response_level <> 4 AND (numerator IS DISTINCT FROM 0 OR percentage_basis_points IS DISTINCT FROM 0))
    )
  THEN
    RAISE EXCEPTION 'right UTC boundary handling is incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_other_project_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_other_project_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 1 AND (numerator IS DISTINCT FROM 1 OR percentage_basis_points IS DISTINCT FROM 10000))
        OR (response_level <> 1 AND (numerator IS DISTINCT FROM 0 OR percentage_basis_points IS DISTINCT FROM 0))
    )
  THEN
    RAISE EXCEPTION 'other project scope is incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_ratio_secondary_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_ratio_secondary_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 2 AND (numerator IS DISTINCT FROM 1 OR percentage_basis_points IS DISTINCT FROM 10000))
        OR (response_level <> 2 AND (numerator IS DISTINCT FROM 0 OR percentage_basis_points IS DISTINCT FROM 0))
    )
  THEN
    RAISE EXCEPTION 'secondary owner scope is incorrect';
  END IF;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_target_response_level_ratios(
      (SELECT app_user_id FROM target_response_ratio_secondary_context),
      (SELECT workspace_id FROM target_response_ratio_owner_context),
      (SELECT project_id FROM target_response_ratio_owner_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'cross-owner target response ratio scope was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_target_response_level_ratios(
      (SELECT app_user_id FROM target_response_ratio_owner_context),
      (SELECT workspace_id FROM target_response_ratio_owner_context),
      (SELECT project_id FROM target_response_ratio_owner_context),
      '2030-01-15T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'invalid target response ratio period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;
END
$target_response_ratio_check$;

ROLLBACK;
