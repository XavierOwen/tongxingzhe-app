-- PostgreSQL fixture：个人对象反应五档分布。
--
-- 该夹具直接建立一组最小的匿名 contact/revision/link 事实，覆盖多对象关联、
-- NULL 未回答、current revision、作废、UTC 半开边界、跨 project/owner、空期间，
-- 并在读取前匿名化一个 target，证明统计事实不依赖仍然可见的 target PII。

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response.example.test/auth/v1',
  'synthetic-target-response-owner'
);

CREATE TEMP TABLE target_response_other_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-target-response.example.test/auth/v1',
  'synthetic-target-response-owner',
  '对象反应其他项目'
);

CREATE TEMP TABLE target_response_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-target-response.example.test/auth/v1',
  'synthetic-target-response-secondary'
);

-- The bulk targets belong to the owner's workspace. They are intentionally
-- created through the public target seam so each has a real assignment.
CREATE TEMP TABLE target_response_targets AS
SELECT request.target_key,
       (created.target->>'target_id')::uuid AS target_id
FROM (
  VALUES
    ('level-0', '对象反应五档 0', 'target-response-level-0'),
    ('level-1', '对象反应五档 1', 'target-response-level-1'),
    ('level-2', '对象反应五档 2', 'target-response-level-2'),
    ('level-3', '对象反应五档 3', 'target-response-level-3'),
    ('level-4', '对象反应五档 4', 'target-response-level-4'),
    ('unanswered-a', '对象反应未回答 A', 'target-response-unanswered-a'),
    ('revision-old-1', '对象反应旧 revision 1', 'target-response-revision-old-1'),
    ('revision-old-4', '对象反应旧 revision 4', 'target-response-revision-old-4'),
    ('revision-current-null', '对象反应当前未回答', 'target-response-revision-current-null'),
    ('voided', '对象反应作废', 'target-response-voided'),
    ('null-b', '对象反应未回答 B', 'target-response-null-b'),
    ('from-boundary', '对象反应起点', 'target-response-from-boundary'),
    ('right-boundary', '对象反应右边界', 'target-response-right-boundary'),
    ('retention', '对象反应保留对象', 'target-response-retention')
) AS request(target_key, display_name, request_id)
CROSS JOIN LATERAL app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  'person',
  request.display_name,
  CASE WHEN request.target_key = 'retention' THEN '312-555-0104' ELSE NULL END,
  CASE WHEN request.target_key = 'retention'
    THEN 'retention-target@example.test' ELSE NULL END,
  request.request_id
) AS created;

CREATE TEMP TABLE target_response_secondary_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_secondary_context),
  (SELECT workspace_id FROM target_response_secondary_context),
  (SELECT project_id FROM target_response_secondary_context),
  'person',
  '对象反应次用户对象',
  NULL,
  NULL,
  'target-response-secondary-target'
);

CREATE TEMP TABLE target_response_institution_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  'institution',
  '对象反应已确认代表机构',
  NULL,
  NULL,
  'target-response-institution-target'
);

RESET ROLE;

-- Contacts in the owner's default project. The revised contact has two old
-- links on revision 1 and only level 0/NULL on current revision 2. The voided
-- contact keeps its link facts but is excluded by lifecycle_status.
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
    ('target-response-mixed', '2030-01-10T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-revised', '2030-01-11T10:00:00Z'::timestamptz, 2, 'active'),
    ('target-response-voided', '2030-01-12T10:00:00Z'::timestamptz, 2, 'voided'),
    ('target-response-retention', '2030-01-13T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-all-null', '2030-01-14T10:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-from-boundary', '2030-01-08T00:00:00Z'::timestamptz, 1, 'active'),
    ('target-response-right-boundary', '2030-01-15T00:00:00Z'::timestamptz, 1, 'active')
) AS fixture(contact_id, occurred_at_utc, current_revision, lifecycle_status)
CROSS JOIN target_response_owner_context AS context;

-- A contact in the owner's other project and one in another owner scope must
-- be present to prove that the full trusted scope, not just workspace, binds.
INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id, questionnaire_version_id,
  occurred_at_utc, occurred_time_zone, channel, location_kind,
  reach_count, interest_level, current_revision, lifecycle_status
)
SELECT
  'target-response-other-project', context.app_user_id, context.workspace_id,
  context.project_id, context.questionnaire_version_id,
  '2030-01-10T12:00:00Z', 'America/Chicago', 'video_call', 'not_applicable',
  1, 2, 1, 'active'
FROM target_response_other_project AS context;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id, questionnaire_version_id,
  occurred_at_utc, occurred_time_zone, channel, location_kind,
  reach_count, interest_level, current_revision, lifecycle_status
)
SELECT
  'target-response-secondary', context.app_user_id, context.workspace_id,
  context.project_id, context.questionnaire_version_id,
  '2030-01-10T13:00:00Z', 'America/Chicago', 'video_call', 'not_applicable',
  1, 2, 1, 'active'
FROM target_response_secondary_context AS context;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revised_by_app_user_id, revision_kind, reason, snapshot
)
SELECT fixture.contact_id,
       fixture.revision_number,
       (SELECT app_user_id FROM target_response_owner_context),
       fixture.revision_kind,
       fixture.reason,
       '{}'::jsonb
FROM (
  VALUES
    ('target-response-mixed', 1, 'submitted', NULL),
    ('target-response-revised', 1, 'submitted', NULL),
    ('target-response-revised', 2, 'corrected', 'synthetic current revision'),
    ('target-response-voided', 1, 'submitted', NULL),
    ('target-response-voided', 2, 'voided', 'synthetic void'),
    ('target-response-retention', 1, 'submitted', NULL),
    ('target-response-all-null', 1, 'submitted', NULL),
    ('target-response-from-boundary', 1, 'submitted', NULL),
    ('target-response-right-boundary', 1, 'submitted', NULL)
) AS fixture(contact_id, revision_number, revision_kind, reason);

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revised_by_app_user_id, revision_kind, reason, snapshot
)
SELECT
  'target-response-other-project', 1,
  context.app_user_id, 'submitted', NULL, '{}'::jsonb
FROM target_response_other_project AS context;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revised_by_app_user_id, revision_kind, reason, snapshot
)
SELECT
  'target-response-secondary', 1,
  context.app_user_id, 'submitted', NULL, '{}'::jsonb
FROM target_response_secondary_context AS context;

INSERT INTO app_data.contact_target_links (
  contact_id, revision_number, promotion_target_id, response_level,
  follow_up_consent, institution_representative_confirmed, confirmed_project_entry
)
VALUES
  ('target-response-mixed', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-0'), 0, 'unknown', false, true),
  ('target-response-mixed', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-1'), 1, 'unknown', false, true),
  ('target-response-mixed', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-2'), 2, 'unknown', false, true),
  ('target-response-mixed', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-3'), 3, 'unknown', false, true),
  ('target-response-mixed', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-4'), 4, 'unknown', false, true),
  ('target-response-mixed', 1, (SELECT target->>'target_id' FROM target_response_institution_target)::uuid, 3, 'unknown', true, true),
  ('target-response-mixed', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'unanswered-a'), NULL, 'unknown', false, true),
  ('target-response-revised', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'revision-old-1'), 1, 'unknown', false, true),
  ('target-response-revised', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'revision-old-4'), 4, 'unknown', false, true),
  ('target-response-revised', 2, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-0'), 0, 'unknown', false, true),
  ('target-response-revised', 2, (SELECT target_id FROM target_response_targets WHERE target_key = 'revision-current-null'), NULL, 'unknown', false, true),
  ('target-response-voided', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'voided'), 3, 'unknown', false, true),
  ('target-response-voided', 2, (SELECT target_id FROM target_response_targets WHERE target_key = 'voided'), 3, 'unknown', false, true),
  ('target-response-retention', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'retention'), 2, 'unknown', false, true),
  ('target-response-all-null', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'unanswered-a'), NULL, 'unknown', false, true),
  ('target-response-all-null', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'null-b'), NULL, 'unknown', false, true),
  ('target-response-from-boundary', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'from-boundary'), 4, 'unknown', false, true),
  ('target-response-right-boundary', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'right-boundary'), 4, 'unknown', false, true),
  ('target-response-other-project', 1, (SELECT target_id FROM target_response_targets WHERE target_key = 'level-1'), 1, 'unknown', false, true),
  ('target-response-secondary', 1, (SELECT target->>'target_id' FROM target_response_secondary_target)::uuid, 2, 'unknown', false, true);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_response_retention_result AS
SELECT result
FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  (SELECT target_id FROM target_response_targets WHERE target_key = 'retention'),
  'anonymize',
  'withdrawal',
  'target-response-retention-action'
);

CREATE TEMP TABLE target_response_primary_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_revised_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  '2030-01-11T00:00:00Z',
  '2030-01-12T00:00:00Z'
);

CREATE TEMP TABLE target_response_voided_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  '2030-01-12T00:00:00Z',
  '2030-01-13T00:00:00Z'
);

CREATE TEMP TABLE target_response_all_null_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  '2030-01-14T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_empty_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  '2031-01-01T00:00:00Z',
  '2031-01-02T00:00:00Z'
);

CREATE TEMP TABLE target_response_right_boundary_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_owner_context),
  (SELECT workspace_id FROM target_response_owner_context),
  (SELECT project_id FROM target_response_owner_context),
  '2030-01-15T00:00:00Z',
  '2030-01-16T00:00:00Z'
);

CREATE TEMP TABLE target_response_other_project_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_other_project),
  (SELECT workspace_id FROM target_response_other_project),
  (SELECT project_id FROM target_response_other_project),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

CREATE TEMP TABLE target_response_secondary_actual AS
SELECT *
FROM app_data.read_personal_target_response_distribution(
  (SELECT app_user_id FROM target_response_secondary_context),
  (SELECT workspace_id FROM target_response_secondary_context),
  (SELECT project_id FROM target_response_secondary_context),
  '2030-01-08T00:00:00Z',
  '2030-01-15T00:00:00Z'
);

RESET ROLE;

DO $target_response_check$
DECLARE
  level_result integer[];
BEGIN
  IF (SELECT count(*) FROM target_response_primary_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_primary_actual
      WHERE denominator IS DISTINCT FROM 9
        OR unanswered_count IS DISTINCT FROM 4
        OR (response_level = 0 AND numerator IS DISTINCT FROM 2)
        OR (response_level = 1 AND numerator IS DISTINCT FROM 1)
        OR (response_level = 2 AND numerator IS DISTINCT FROM 2)
        OR (response_level = 3 AND numerator IS DISTINCT FROM 2)
        OR (response_level = 4 AND numerator IS DISTINCT FROM 2)
    )
  THEN
    RAISE EXCEPTION 'primary target response distribution is incorrect';
  END IF;

  -- Current revision 2 contributes exactly level 0 plus one unanswered link;
  -- the two revision 1 links must not leak into the current projection.
  IF (SELECT count(*) FROM target_response_revised_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_revised_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 1
        OR (response_level = 0 AND numerator IS DISTINCT FROM 1)
        OR (response_level <> 0 AND numerator IS DISTINCT FROM 0)
    )
  THEN
    RAISE EXCEPTION 'current contact revision was not isolated';
  END IF;

  IF (SELECT count(*) FROM target_response_voided_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_voided_actual
      WHERE numerator IS DISTINCT FROM 0
        OR denominator IS DISTINCT FROM 0
        OR unanswered_count IS DISTINCT FROM 0
    )
  THEN
    RAISE EXCEPTION 'voided contact was not excluded';
  END IF;

  IF (SELECT count(*) FROM target_response_all_null_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_all_null_actual
      WHERE numerator IS DISTINCT FROM 0
        OR denominator IS DISTINCT FROM 0
        OR unanswered_count IS DISTINCT FROM 2
    )
  THEN
    RAISE EXCEPTION 'NULL-only target response distribution is incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_empty_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_empty_actual
      WHERE numerator IS DISTINCT FROM 0
        OR denominator IS DISTINCT FROM 0
        OR unanswered_count IS DISTINCT FROM 0
    )
  THEN
    RAISE EXCEPTION 'empty target response distribution is incorrect';
  END IF;

  -- The right-boundary contact is excluded from [Jan 8, Jan 15), but is
  -- included when Jan 15 becomes the lower bound of a new half-open window.
  IF (SELECT count(*) FROM target_response_right_boundary_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_right_boundary_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 4 AND numerator IS DISTINCT FROM 1)
        OR (response_level <> 4 AND numerator IS DISTINCT FROM 0)
    )
  THEN
    RAISE EXCEPTION 'UTC half-open boundary handling is incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_other_project_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_other_project_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 1 AND numerator IS DISTINCT FROM 1)
        OR (response_level <> 1 AND numerator IS DISTINCT FROM 0)
    )
  THEN
    RAISE EXCEPTION 'other project scope is incorrect';
  END IF;

  IF (SELECT count(*) FROM target_response_secondary_actual) <> 5
    OR EXISTS (
      SELECT 1
      FROM target_response_secondary_actual
      WHERE denominator IS DISTINCT FROM 1
        OR unanswered_count IS DISTINCT FROM 0
        OR (response_level = 2 AND numerator IS DISTINCT FROM 1)
        OR (response_level <> 2 AND numerator IS DISTINCT FROM 0)
    )
  THEN
    RAISE EXCEPTION 'secondary owner scope is incorrect';
  END IF;

  IF (SELECT result->>'status' FROM target_response_retention_result LIMIT 1)
      IS DISTINCT FROM 'anonymized'
    OR (SELECT status FROM app_data.promotion_targets
        WHERE promotion_target_id = (
          SELECT target_id FROM target_response_targets
          WHERE target_key = 'retention'
        )) IS DISTINCT FROM 'anonymized'
    OR (SELECT phone FROM app_data.promotion_targets
        WHERE promotion_target_id = (
          SELECT target_id FROM target_response_targets
          WHERE target_key = 'retention'
        )) IS NOT NULL
  THEN
    RAISE EXCEPTION 'retention target was not anonymized before metric read';
  END IF;

  -- Authorization is checked against user, workspace and project together.
  BEGIN
    PERFORM *
    FROM app_data.read_personal_target_response_distribution(
      (SELECT app_user_id FROM target_response_secondary_context),
      (SELECT workspace_id FROM target_response_owner_context),
      (SELECT project_id FROM target_response_owner_context),
      '2030-01-08T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'cross-owner target response scope was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_data.read_personal_target_response_distribution(
      (SELECT app_user_id FROM target_response_owner_context),
      (SELECT workspace_id FROM target_response_owner_context),
      (SELECT project_id FROM target_response_owner_context),
      '2030-01-15T00:00:00Z',
      '2030-01-15T00:00:00Z'
    );
    RAISE EXCEPTION 'invalid target response period was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;

  -- Ensure the generated rows are the fixed ordered 0..4 contract.
  SELECT array_agg(response_level ORDER BY response_level)
    INTO level_result
  FROM target_response_primary_actual;
  IF level_result IS DISTINCT FROM ARRAY[0, 1, 2, 3, 4]::integer[] THEN
    RAISE EXCEPTION 'target response distribution level order drifted: %', level_result;
  END IF;
END
$target_response_check$;

ROLLBACK;
