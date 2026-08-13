-- PostgreSQL fixture：个人对象反应有序汇总。
--
-- 该夹具使用独立的 synthetic 命名空间，覆盖奇数／偶数下中位、空期间、
-- 全 NULL、current revision、作废、UTC 半开边界、跨项目／用户 scope 和
-- 非法期间。整个 fixture 回滚，因此 Docker 的恢复库可以再次运行同一组
-- 断言而不会与源库的 synthetic 数据冲突。

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_ordinal_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response-ordinal.example.test/auth/v1',
  'synthetic-target-response-ordinal-owner'
);

CREATE TEMP TABLE target_response_ordinal_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-target-response-ordinal.example.test/auth/v1',
  'synthetic-target-response-ordinal-owner',
  '对象反应中位其他项目'
);

CREATE TEMP TABLE target_response_ordinal_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response-ordinal.example.test/auth/v1',
  'synthetic-target-response-ordinal-secondary'
);

-- The same target may appear in different contacts, but each contact revision
-- below uses a distinct target id for each link in its own snapshot.
CREATE TEMP TABLE target_response_ordinal_targets AS
SELECT request.target_key,
       (created.target->>'target_id')::uuid AS target_id
FROM (
  VALUES
    ('level-0', 'target-response-ordinal-level-0', 'target-response-ordinal-level-0'),
    ('level-1-a', 'target-response-ordinal-level-1-a', 'target-response-ordinal-level-1-a'),
    ('level-1-b', 'target-response-ordinal-level-1-b', 'target-response-ordinal-level-1-b'),
    ('level-2', 'target-response-ordinal-level-2', 'target-response-ordinal-level-2'),
    ('level-3', 'target-response-ordinal-level-3', 'target-response-ordinal-level-3'),
    ('level-4-a', 'target-response-ordinal-level-4-a', 'target-response-ordinal-level-4-a'),
    ('level-4-b', 'target-response-ordinal-level-4-b', 'target-response-ordinal-level-4-b'),
    ('null-a', 'target-response-ordinal-null-a', 'target-response-ordinal-null-a'),
    ('null-b', 'target-response-ordinal-null-b', 'target-response-ordinal-null-b'),
    ('from-boundary', 'target-response-ordinal-from-boundary', 'target-response-ordinal-from-boundary'),
    ('right-boundary', 'target-response-ordinal-right-boundary', 'target-response-ordinal-right-boundary')
) AS request(target_key, display_name, request_id)
CROSS JOIN LATERAL app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  'person',
  request.display_name,
  NULL,
  NULL,
  request.request_id
) AS created;

CREATE TEMP TABLE target_response_ordinal_secondary_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_ordinal_secondary_context),
  (SELECT workspace_id FROM target_response_ordinal_secondary_context),
  (SELECT project_id FROM target_response_ordinal_secondary_context),
  'person',
  'target-response-ordinal-secondary-target',
  NULL,
  NULL,
  'target-response-ordinal-secondary-target'
);

RESET ROLE;

-- The primary scope contains one odd sample, one even sample, a corrected
-- contact whose old links must be ignored, a voided contact, NULL-only links,
-- and both sides of a UTC half-open boundary.
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
    ('target-response-ordinal-odd', '2030-01-10T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ordinal-even', '2030-01-11T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ordinal-current', '2030-01-12T10:00:00Z'::timestamptz, 2, 'active'),
    ('target-response-ordinal-voided', '2030-01-13T10:00:00Z'::timestamptz, 1, 'voided'),
    ('target-response-ordinal-all-null', '2030-01-14T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ordinal-from-boundary', '2030-01-08T00:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-ordinal-right-boundary', '2030-01-15T00:00:00Z'::timestamptz, 1, 'active')
) AS fixture(contact_id, occurred_at_utc, current_revision, lifecycle_status)
CROSS JOIN target_response_ordinal_owner_context AS context;

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
  'target-response-ordinal-other-project',
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
FROM target_response_ordinal_other_project AS context;

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
  'target-response-ordinal-secondary',
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
FROM target_response_ordinal_secondary_context AS context;

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
       (SELECT app_user_id FROM target_response_ordinal_owner_context),
       fixture.revision_kind,
       fixture.reason,
       '{}'::jsonb
FROM (
  VALUES
    ('target-response-ordinal-odd', 1, 'submitted', NULL),
    ('target-response-ordinal-even', 1, 'submitted', NULL),
    ('target-response-ordinal-current', 1, 'submitted', NULL),
    ('target-response-ordinal-current', 2, 'corrected', 'synthetic current revision'),
    ('target-response-ordinal-voided', 1, 'submitted', NULL),
    ('target-response-ordinal-all-null', 1, 'submitted', NULL),
    ('target-response-ordinal-from-boundary', 1, 'submitted', NULL),
    ('target-response-ordinal-right-boundary', 1, 'submitted', NULL)
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
  'target-response-ordinal-other-project',
  1,
  context.app_user_id,
  'submitted',
  NULL,
  '{}'::jsonb
FROM target_response_ordinal_other_project AS context;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT
  'target-response-ordinal-secondary',
  1,
  context.app_user_id,
  'submitted',
  NULL,
  '{}'::jsonb
FROM target_response_ordinal_secondary_context AS context;

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
  -- Five answered levels plus one NULL make an odd sample with median 1.
  ('target-response-ordinal-odd', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-0'), 0, 'unknown', false, true),
  ('target-response-ordinal-odd', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-1-a'), 1, 'unknown', false, true),
  ('target-response-ordinal-odd', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-1-b'), 1, 'unknown', false, true),
  ('target-response-ordinal-odd', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-3'), 3, 'unknown', false, true),
  ('target-response-ordinal-odd', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-4-a'), 4, 'unknown', false, true),
  ('target-response-ordinal-odd', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'null-a'), NULL, 'unknown', false, true),
  -- Two answered values test the lower, not upper, median.
  ('target-response-ordinal-even', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-0'), 0, 'unknown', false, true),
  ('target-response-ordinal-even', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-4-b'), 4, 'unknown', false, true),
  -- Old revision links must not leak into the current projection.
  ('target-response-ordinal-current', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-4-a'), 4, 'unknown', false, true),
  ('target-response-ordinal-current', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-4-b'), 4, 'unknown', false, true),
  ('target-response-ordinal-current', 2, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-2'), 2, 'unknown', false, true),
  ('target-response-ordinal-current', 2, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'null-a'), NULL, 'unknown', false, true),
  -- A voided contact remains stored but contributes no links.
  ('target-response-ordinal-voided', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-3'), 3, 'unknown', false, true),
  -- NULL-only links have no answered denominator or median.
  ('target-response-ordinal-all-null', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'null-a'), NULL, 'unknown', false, true),
  ('target-response-ordinal-all-null', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'null-b'), NULL, 'unknown', false, true),
  -- The lower bound is included; the right boundary is tested separately.
  ('target-response-ordinal-from-boundary', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-3'), 3, 'unknown', false, true),
  ('target-response-ordinal-right-boundary', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'right-boundary'), 4, 'unknown', false, true),
  ('target-response-ordinal-other-project', 1, (SELECT target_id FROM target_response_ordinal_targets WHERE target_key = 'level-1-a'), 1, 'unknown', false, true),
  ('target-response-ordinal-secondary', 1, (SELECT target->>'target_id' FROM target_response_ordinal_secondary_target)::uuid, 2, 'unknown', false, true);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_ordinal_primary_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_odd_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-10T00:00:00Z',
  '2030-01-11T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_even_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-11T00:00:00Z',
  '2030-01-12T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_current_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-12T00:00:00Z',
  '2030-01-13T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_voided_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-13T00:00:00Z',
  '2030-01-14T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_null_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-14T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_empty_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2031-01-01T00:00:00Z',
  '2031-01-02T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_right_boundary_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_owner_context),
  (SELECT workspace_id FROM target_response_ordinal_owner_context),
  (SELECT project_id FROM target_response_ordinal_owner_context),
  '2030-01-15T00:00:00Z',
  '2030-01-16T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_other_project_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_other_project),
  (SELECT workspace_id FROM target_response_ordinal_other_project),
  (SELECT project_id FROM target_response_ordinal_other_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_ordinal_secondary_actual AS
SELECT *
FROM app_data.read_personal_target_response_ordinal_summary(
  (SELECT app_user_id FROM target_response_ordinal_secondary_context),
  (SELECT workspace_id FROM target_response_ordinal_secondary_context),
  (SELECT project_id FROM target_response_ordinal_secondary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

RESET ROLE;

DO $target_response_ordinal_check$
DECLARE
  primary_result record;
  odd_result record;
  even_result record;
  current_result record;
  voided_result record;
  null_result record;
  empty_result record;
  right_boundary_result record;
  other_project_result record;
  secondary_result record;
BEGIN
  SELECT * INTO STRICT primary_result FROM target_response_ordinal_primary_actual;
  IF primary_result.target_response_total_count IS DISTINCT FROM 9
    OR primary_result.target_response_0_count IS DISTINCT FROM 2
    OR primary_result.target_response_1_count IS DISTINCT FROM 2
    OR primary_result.target_response_2_count IS DISTINCT FROM 1
    OR primary_result.target_response_3_count IS DISTINCT FROM 2
    OR primary_result.target_response_4_count IS DISTINCT FROM 2
    OR primary_result.median_level IS DISTINCT FROM 2
    OR primary_result.unanswered_count IS DISTINCT FROM 4
  THEN
    RAISE EXCEPTION 'primary target response ordinal summary is incorrect';
  END IF;

  SELECT * INTO STRICT odd_result FROM target_response_ordinal_odd_actual;
  IF odd_result.target_response_total_count IS DISTINCT FROM 5
    OR odd_result.target_response_0_count IS DISTINCT FROM 1
    OR odd_result.target_response_1_count IS DISTINCT FROM 2
    OR odd_result.target_response_2_count IS DISTINCT FROM 0
    OR odd_result.target_response_3_count IS DISTINCT FROM 1
    OR odd_result.target_response_4_count IS DISTINCT FROM 1
    OR odd_result.median_level IS DISTINCT FROM 1
    OR odd_result.unanswered_count IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION 'odd target response ordinal summary is incorrect';
  END IF;

  SELECT * INTO STRICT even_result FROM target_response_ordinal_even_actual;
  IF even_result.target_response_total_count IS DISTINCT FROM 2
    OR even_result.target_response_0_count IS DISTINCT FROM 1
    OR even_result.target_response_1_count IS DISTINCT FROM 0
    OR even_result.target_response_2_count IS DISTINCT FROM 0
    OR even_result.target_response_3_count IS DISTINCT FROM 0
    OR even_result.target_response_4_count IS DISTINCT FROM 1
    OR even_result.median_level IS DISTINCT FROM 0
    OR even_result.unanswered_count IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'even target response ordinal summary is not lower median';
  END IF;

  SELECT * INTO STRICT current_result FROM target_response_ordinal_current_actual;
  IF current_result.target_response_total_count IS DISTINCT FROM 1
    OR current_result.target_response_0_count IS DISTINCT FROM 0
    OR current_result.target_response_1_count IS DISTINCT FROM 0
    OR current_result.target_response_2_count IS DISTINCT FROM 1
    OR current_result.target_response_3_count IS DISTINCT FROM 0
    OR current_result.target_response_4_count IS DISTINCT FROM 0
    OR current_result.median_level IS DISTINCT FROM 2
    OR current_result.unanswered_count IS DISTINCT FROM 1
  THEN
    RAISE EXCEPTION 'current contact revision leaked old target links';
  END IF;

  SELECT * INTO STRICT voided_result FROM target_response_ordinal_voided_actual;
  IF voided_result.target_response_total_count IS DISTINCT FROM 0
    OR voided_result.target_response_0_count IS DISTINCT FROM 0
    OR voided_result.target_response_1_count IS DISTINCT FROM 0
    OR voided_result.target_response_2_count IS DISTINCT FROM 0
    OR voided_result.target_response_3_count IS DISTINCT FROM 0
    OR voided_result.target_response_4_count IS DISTINCT FROM 0
    OR voided_result.median_level IS NOT NULL
    OR voided_result.unanswered_count IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'voided contact was not excluded';
  END IF;

  SELECT * INTO STRICT null_result FROM target_response_ordinal_null_actual;
  IF null_result.target_response_total_count IS DISTINCT FROM 0
    OR null_result.target_response_0_count IS DISTINCT FROM 0
    OR null_result.target_response_1_count IS DISTINCT FROM 0
    OR null_result.target_response_2_count IS DISTINCT FROM 0
    OR null_result.target_response_3_count IS DISTINCT FROM 0
    OR null_result.target_response_4_count IS DISTINCT FROM 0
    OR null_result.median_level IS NOT NULL
    OR null_result.unanswered_count IS DISTINCT FROM 2
  THEN
    RAISE EXCEPTION 'NULL-only target response ordinal summary is incorrect';
  END IF;

  SELECT * INTO STRICT empty_result FROM target_response_ordinal_empty_actual;
  IF empty_result.target_response_total_count IS DISTINCT FROM 0
    OR empty_result.target_response_0_count IS DISTINCT FROM 0
    OR empty_result.target_response_1_count IS DISTINCT FROM 0
    OR empty_result.target_response_2_count IS DISTINCT FROM 0
    OR empty_result.target_response_3_count IS DISTINCT FROM 0
    OR empty_result.target_response_4_count IS DISTINCT FROM 0
    OR empty_result.median_level IS NOT NULL
    OR empty_result.unanswered_count IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'empty target response ordinal summary is incorrect';
  END IF;

  SELECT * INTO STRICT right_boundary_result
  FROM target_response_ordinal_right_boundary_actual;
  IF right_boundary_result.target_response_total_count IS DISTINCT FROM 1
    OR right_boundary_result.target_response_0_count IS DISTINCT FROM 0
    OR right_boundary_result.target_response_1_count IS DISTINCT FROM 0
    OR right_boundary_result.target_response_2_count IS DISTINCT FROM 0
    OR right_boundary_result.target_response_3_count IS DISTINCT FROM 0
    OR right_boundary_result.target_response_4_count IS DISTINCT FROM 1
    OR right_boundary_result.median_level IS DISTINCT FROM 4
    OR right_boundary_result.unanswered_count IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'UTC half-open boundary handling is incorrect';
  END IF;

  SELECT * INTO STRICT other_project_result
  FROM target_response_ordinal_other_project_actual;
  IF other_project_result.target_response_total_count IS DISTINCT FROM 1
    OR other_project_result.target_response_0_count IS DISTINCT FROM 0
    OR other_project_result.target_response_1_count IS DISTINCT FROM 1
    OR other_project_result.target_response_2_count IS DISTINCT FROM 0
    OR other_project_result.target_response_3_count IS DISTINCT FROM 0
    OR other_project_result.target_response_4_count IS DISTINCT FROM 0
    OR other_project_result.median_level IS DISTINCT FROM 1
    OR other_project_result.unanswered_count IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'other project scope is incorrect';
  END IF;

  SELECT * INTO STRICT secondary_result
  FROM target_response_ordinal_secondary_actual;
  IF secondary_result.target_response_total_count IS DISTINCT FROM 1
    OR secondary_result.target_response_0_count IS DISTINCT FROM 0
    OR secondary_result.target_response_1_count IS DISTINCT FROM 0
    OR secondary_result.target_response_2_count IS DISTINCT FROM 1
    OR secondary_result.target_response_3_count IS DISTINCT FROM 0
    OR secondary_result.target_response_4_count IS DISTINCT FROM 0
    OR secondary_result.median_level IS DISTINCT FROM 2
    OR secondary_result.unanswered_count IS DISTINCT FROM 0
  THEN
    RAISE EXCEPTION 'secondary owner scope is incorrect';
  END IF;

  -- PostgreSQL reauthorizes user, workspace and project together, rather than
  -- trusting a caller that owns only one of those identifiers.
  BEGIN
    PERFORM *
    FROM app_data.read_personal_target_response_ordinal_summary(
      (SELECT app_user_id FROM target_response_ordinal_secondary_context),
      (SELECT workspace_id FROM target_response_ordinal_owner_context),
      (SELECT project_id FROM target_response_ordinal_owner_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'cross-owner target response ordinal scope was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_target_response_ordinal_summary(
      (SELECT app_user_id FROM target_response_ordinal_owner_context),
      (SELECT workspace_id FROM target_response_ordinal_owner_context),
      (SELECT project_id FROM target_response_ordinal_owner_context),
      '2030-01-15T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'invalid target response ordinal period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;
END
$target_response_ordinal_check$;

ROLLBACK;
