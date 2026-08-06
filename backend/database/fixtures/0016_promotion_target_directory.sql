\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE target_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-targets.example.test',
  'target-owner'
);

CREATE TEMP TABLE target_intruder_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-targets.example.test',
  'target-intruder'
);

CREATE TEMP TABLE created_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_owner_context),
  (SELECT workspace_id FROM target_owner_context),
  (SELECT project_id FROM target_owner_context),
  'person',
  '王小明',
  '+1 312 555 0100',
  NULL,
  'create-target-1'
);

CREATE TEMP TABLE replayed_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_owner_context),
  (SELECT workspace_id FROM target_owner_context),
  (SELECT project_id FROM target_owner_context),
  'person',
  '王小明',
  '+1 312 555 0100',
  NULL,
  'create-target-1'
);

CREATE TEMP TABLE ended_target AS
SELECT target
FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM target_owner_context),
  (SELECT workspace_id FROM target_owner_context),
  (SELECT project_id FROM target_owner_context),
  'institution',
  '北区社区中心',
  NULL,
  'contact@example.test',
  'create-target-2'
);

RESET ROLE;

UPDATE app_data.promotion_target_assignments
SET ended_at = clock_timestamp(),
    end_reason = 'synthetic reassignment boundary'
WHERE promotion_target_id = (
  SELECT (target->>'target_id')::uuid FROM ended_target
)
  AND ended_at IS NULL;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE assigned_targets AS
SELECT target
FROM app_data.list_assigned_promotion_targets(
  (SELECT app_user_id FROM target_owner_context),
  (SELECT workspace_id FROM target_owner_context),
  (SELECT project_id FROM target_owner_context)
);

DO $runtime_check$
BEGIN
  IF (SELECT target FROM created_target)
    IS DISTINCT FROM (SELECT target FROM replayed_target)
    OR (SELECT count(*) FROM assigned_targets) <> 1
    OR (SELECT target->>'display_name' FROM assigned_targets) <> '王小明'
  THEN
    RAISE EXCEPTION 'assigned target directory or replay is unstable';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.list_personal_project_contexts(
      'https://synthetic-targets.example.test',
      'target-owner'
    )
    WHERE is_current
      AND capabilities @> ARRAY[
        'create_target',
        'view_assigned_target_pii'
      ]::text[]
  ) THEN
    RAISE EXCEPTION 'target capabilities are missing from trusted context';
  END IF;

  BEGIN
    PERFORM app_data.create_promotion_target(
      (SELECT app_user_id FROM target_owner_context),
      (SELECT workspace_id FROM target_owner_context),
      (SELECT project_id FROM target_owner_context),
      'person',
      '不同资料',
      NULL,
      NULL,
      'create-target-1'
    );
    RAISE EXCEPTION 'changed replay was accepted';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.create_promotion_target(
      (SELECT app_user_id FROM target_owner_context),
      (SELECT workspace_id FROM target_intruder_context),
      (SELECT project_id FROM target_intruder_context),
      'person',
      '伪造空间',
      NULL,
      NULL,
      'forged-workspace'
    );
    RAISE EXCEPTION 'forged workspace was accepted';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.list_assigned_promotion_targets(
      (SELECT app_user_id FROM target_intruder_context),
      (SELECT workspace_id FROM target_owner_context),
      (SELECT project_id FROM target_owner_context)
    );
    RAISE EXCEPTION 'unassigned identity read target PII';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM 1 FROM app_data.promotion_targets;
    RAISE EXCEPTION 'runtime role read promotion targets directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$runtime_check$;

RESET ROLE;

DO $owner_check$
DECLARE
  target_id uuid := (
    SELECT (target->>'target_id')::uuid FROM created_target
  );
BEGIN
  IF (
    SELECT count(*)
    FROM app_data.promotion_target_assignments
    WHERE promotion_target_id = target_id
      AND app_user_id = (SELECT app_user_id FROM target_owner_context)
      AND ended_at IS NULL
  ) <> 1 THEN
    RAISE EXCEPTION 'creator did not receive the initial assignment';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.promotion_target_creation_requests
    WHERE promotion_target_id = target_id
  ) <> 1 OR (
    SELECT count(*)
    FROM app_data.promotion_target_access_events
    WHERE promotion_target_id = target_id
      AND action = 'created'
  ) <> 1 OR (
    SELECT count(*)
    FROM app_data.promotion_target_access_events
    WHERE promotion_target_id = target_id
      AND action = 'viewed'
  ) <> 1 THEN
    RAISE EXCEPTION 'target request or access audit is incomplete';
  END IF;

  BEGIN
    UPDATE app_data.promotion_target_access_events
    SET occurred_at = clock_timestamp()
    WHERE promotion_target_id = target_id;
    RAISE EXCEPTION 'target audit event was mutable';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      NULL;
  END;
END
$owner_check$;

ROLLBACK;
