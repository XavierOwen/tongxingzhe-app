\set ON_ERROR_STOP on

BEGIN;

SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0116-retention.example.test', 'retention-fence-owner'
);
CREATE TEMP TABLE fixture_0116_context ON COMMIT DROP AS
SELECT app_user_id, workspace_id, project_id
FROM app_data.list_personal_project_contexts(
  'https://synthetic-0116-retention.example.test', 'retention-fence-owner'
)
WHERE is_current;
GRANT SELECT ON fixture_0116_context TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0116_target ON COMMIT DROP AS
SELECT (created.target->>'target_id')::uuid AS target_id
FROM fixture_0116_context AS context_row
CROSS JOIN LATERAL app_data.create_promotion_target(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id,
  'person', '0116 retention fence target', NULL, NULL,
  '0116-retention-fence-target'
) AS created;
CREATE TEMP TABLE fixture_0116_policy_9 ON COMMIT DROP AS
SELECT app_data.configure_promotion_target_retention_policy(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id, 9
) AS retention_months
FROM fixture_0116_context AS context_row;
CREATE TEMP TABLE fixture_0116_first_renewal ON COMMIT DROP AS
SELECT result
FROM fixture_0116_context AS context_row
CROSS JOIN fixture_0116_target AS target_row
CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id,
  target_row.target_id, 'renew', 'purpose_confirmed',
  '0116-retention-fence-renewal'
);
SELECT app_data.configure_promotion_target_retention_policy(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id, 1
)
FROM fixture_0116_context AS context_row;
CREATE TEMP TABLE fixture_0116_expired_target ON COMMIT DROP AS
SELECT (created.target->>'target_id')::uuid AS target_id
FROM fixture_0116_context AS context_row
CROSS JOIN LATERAL app_data.create_promotion_target(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id,
  'person', '0116 expired retention target', NULL, NULL,
  '0116-retention-expired-target'
) AS created;
RESET ROLE;

UPDATE app_data.promotion_targets
SET created_at = clock_timestamp() - interval '2 months'
WHERE promotion_target_id = (SELECT target_id FROM fixture_0116_expired_target);

CREATE TEMP TABLE fixture_0116_before_replay ON COMMIT DROP AS
SELECT fence.epoch,
       (SELECT count(*)
        FROM app_data.promotion_target_retention_events AS event_row
        WHERE event_row.mutation_id = '0116-retention-fence-renewal')
         AS event_count
FROM app_private.personal_target_merge_generation_fence_v1 AS fence;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0116_replay ON COMMIT DROP AS
SELECT result
FROM fixture_0116_context AS context_row
CROSS JOIN fixture_0116_target AS target_row
CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  context_row.app_user_id, context_row.workspace_id, context_row.project_id,
  target_row.target_id, 'renew', 'purpose_confirmed',
  '0116-retention-fence-renewal'
);

DO $errors$
DECLARE
  context_row record;
  target_id_value uuid;
BEGIN
  SELECT * INTO STRICT context_row FROM fixture_0116_context;
  SELECT target_id INTO STRICT target_id_value FROM fixture_0116_target;

  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      context_row.app_user_id, context_row.workspace_id,
      context_row.project_id, target_id_value, 'invalid',
      'purpose_confirmed', '0116-invalid-action'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'invalid action was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      context_row.app_user_id, context_row.workspace_id,
      context_row.project_id, target_id_value, 'anonymize',
      'withdrawal', '0116-retention-fence-renewal'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'mutation reuse was accepted';
  EXCEPTION WHEN SQLSTATE '23505' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.apply_promotion_target_retention_action(
      context_row.app_user_id, context_row.workspace_id,
      context_row.project_id,
      (SELECT expired.target_id FROM fixture_0116_expired_target AS expired),
      'renew', 'purpose_confirmed', '0116-expired-renewal'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'expired target was renewed';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END
$errors$;
RESET ROLE;

DO $assertions$
DECLARE
  previous_epoch bigint;
  current_epoch bigint;
  prior_event_count bigint;
  current_event_count bigint;
  history_due_at timestamptz;
  recalculated_due_at timestamptz;
  policy_months integer;
BEGIN
  SELECT epoch, event_count INTO STRICT previous_epoch, prior_event_count
  FROM fixture_0116_before_replay;
  SELECT epoch INTO STRICT current_epoch
  FROM app_private.personal_target_merge_generation_fence_v1;
  SELECT count(*) INTO current_event_count
  FROM app_data.promotion_target_retention_events
  WHERE mutation_id = '0116-retention-fence-renewal';
  SELECT event_row.review_due_at, app_data.promotion_target_review_due_at(
      event_row.promotion_target_id
    ), policy_row.retention_months
    INTO STRICT history_due_at, recalculated_due_at, policy_months
  FROM app_data.promotion_target_retention_events AS event_row
  JOIN app_data.promotion_target_retention_policies AS policy_row
    USING (workspace_id)
  WHERE event_row.mutation_id = '0116-retention-fence-renewal';

  IF (SELECT result->>'duplicate' FROM fixture_0116_first_renewal)
        IS DISTINCT FROM 'false'
    OR (SELECT retention_months FROM fixture_0116_policy_9) <> 9
    OR (SELECT result->>'status' FROM fixture_0116_first_renewal)
        IS DISTINCT FROM 'active'
    OR (SELECT result->>'duplicate' FROM fixture_0116_replay)
        IS DISTINCT FROM 'true'
    OR (SELECT (result->>'review_due_at')::timestamptz
        FROM fixture_0116_replay) IS DISTINCT FROM history_due_at
    OR previous_epoch IS DISTINCT FROM current_epoch
    OR prior_event_count <> 1 OR current_event_count <> 1
    OR policy_months <> 1
    OR history_due_at IS DISTINCT FROM (
      SELECT event_row.occurred_at + interval '9 months'
      FROM app_data.promotion_target_retention_events AS event_row
      WHERE event_row.mutation_id = '0116-retention-fence-renewal'
    )
    OR history_due_at = recalculated_due_at
    OR recalculated_due_at IS DISTINCT FROM (
      SELECT event_row.occurred_at + interval '1 month'
      FROM app_data.promotion_target_retention_events AS event_row
      WHERE event_row.mutation_id = '0116-retention-fence-renewal'
    )
  THEN
    RAISE EXCEPTION '0116 renewal replay or retention policy behavior drifted';
  END IF;
END
$assertions$;

ROLLBACK;
