\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE relationship_owner_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-relationships.example.test',
  'relationship-owner'
);

CREATE TEMP TABLE relationship_intruder_context AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-relationships.example.test',
  'relationship-intruder'
);

CREATE TEMP TABLE relationship_target AS
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  'person',
  '关系审计对象',
  NULL,
  NULL,
  'relationship-target-1'
);

RESET ROLE;

INSERT INTO app_data.promotion_target_project_relationships (
  promotion_target_id,
  project_id,
  current_stage,
  established_by_app_user_id
) VALUES (
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  (SELECT project_id FROM relationship_owner_context),
  0,
  (SELECT app_user_id FROM relationship_owner_context)
);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE configured_relationship_aliases AS
SELECT aliases FROM app_data.configure_promotion_target_stage_aliases(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  jsonb_build_array(
    jsonb_build_object('stage', 0, 'display_name', '初识'),
    jsonb_build_object('stage', 1, 'display_name', NULL),
    jsonb_build_object('stage', 2, 'display_name', '同行'),
    jsonb_build_object('stage', 3, 'display_name', NULL),
    jsonb_build_object('stage', 4, 'display_name', '同行目标')
  )
);

CREATE TEMP TABLE relationship_up_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  1,
  4,
  'active',
  NULL,
  'progress_update',
  NULL,
  'relationship-up-1',
  NULL
);

CREATE TEMP TABLE relationship_replay_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  1,
  4,
  'active',
  NULL,
  'progress_update',
  NULL,
  'relationship-up-1',
  NULL
);

CREATE TEMP TABLE relationship_note_merge_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  1,
  0,
  'active',
  '并发设备补充备注',
  'correction',
  NULL,
  'relationship-note-merge-1',
  NULL
);

CREATE TEMP TABLE relationship_replay_after_merge_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  1,
  4,
  'active',
  NULL,
  'progress_update',
  NULL,
  'relationship-up-1',
  NULL
);

CREATE TEMP TABLE relationship_conflict_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  1,
  3,
  'active',
  '另一个设备的备注',
  'progress_update',
  NULL,
  'relationship-conflict-1',
  NULL
);

DO $reject_unstructured_decrease$
BEGIN
  BEGIN
    PERFORM app_data.update_promotion_target_relationship(
      (SELECT app_user_id FROM relationship_owner_context),
      (SELECT workspace_id FROM relationship_owner_context),
      (SELECT project_id FROM relationship_owner_context),
      (SELECT (target->>'target_id')::uuid FROM relationship_target),
      3,
      3,
      'active',
      '暂缓推进',
      'progress_update',
      NULL,
      'relationship-invalid-down-1',
      NULL
    );
    RAISE EXCEPTION 'unstructured relationship decrease was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;
END
$reject_unstructured_decrease$;

CREATE TEMP TABLE relationship_down_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  3,
  3,
  'paused',
  '对方希望下月再联系',
  'target_request',
  '暂缓一个月',
  'relationship-down-1',
  NULL
);

CREATE TEMP TABLE relationship_resolution_result AS
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM relationship_owner_context),
  (SELECT workspace_id FROM relationship_owner_context),
  (SELECT project_id FROM relationship_owner_context),
  (SELECT (target->>'target_id')::uuid FROM relationship_target),
  4,
  3,
  'active',
  '另一个设备的备注',
  'correction',
  '明确采用冲突中的拟提交值',
  'relationship-resolution-1',
  (SELECT (result->>'conflict_id')::uuid
   FROM relationship_conflict_result)
);

RESET ROLE;

DO $relationship_checks$
DECLARE
  target_id_value uuid := (
    SELECT (target->>'target_id')::uuid FROM relationship_target
  );
  project_id_value uuid := (
    SELECT project_id FROM relationship_owner_context
  );
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.list_personal_project_contexts(
      'https://synthetic-relationships.example.test',
      'relationship-owner'
    )
    WHERE is_current
      AND capabilities @> ARRAY[
        'view_assigned_target_pii',
        'manage_assigned_target_follow_up'
      ]::text[]
  ) THEN
    RAISE EXCEPTION 'relationship follow-up capability is missing';
  END IF;

  IF (SELECT result->>'status' FROM relationship_up_result) <> 'accepted'
    OR (SELECT (result->>'duplicate')::boolean
        FROM relationship_up_result)
    OR NOT (SELECT (result->>'duplicate')::boolean
            FROM relationship_replay_result)
    OR (SELECT result->>'status' FROM relationship_conflict_result)
      <> 'conflict'
    OR (SELECT (result#>>'{current,revision_number}')::integer
        FROM relationship_conflict_result) <> 3
    OR (SELECT result->>'status' FROM relationship_note_merge_result)
      <> 'accepted'
    OR NOT (SELECT (result->>'duplicate')::boolean
            FROM relationship_replay_after_merge_result)
    OR (SELECT result->>'status' FROM relationship_down_result)
      <> 'accepted'
    OR (SELECT result->>'status' FROM relationship_resolution_result)
      <> 'accepted'
  THEN
    RAISE EXCEPTION 'relationship replay or conflict result is unstable';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id = target_id_value
      AND project_id = project_id_value
      AND current_stage = 3
      AND current_lifecycle_status = 'active'
      AND current_follow_up_note = '另一个设备的备注'
      AND current_revision = 5
  ) OR (
    SELECT count(*)
    FROM app_data.promotion_target_relationship_revisions
    WHERE promotion_target_id = target_id_value
      AND project_id = project_id_value
  ) <> 5 THEN
    RAISE EXCEPTION 'relationship projection or append-only history diverged';
  END IF;

  IF (SELECT aliases#>>'{0,display_stage}'
      FROM configured_relationship_aliases) <> '0'
    OR (SELECT aliases#>>'{4,display_stage}'
        FROM configured_relationship_aliases) <> '8'
    OR (SELECT aliases#>>'{4,display_name}'
        FROM configured_relationship_aliases) <> '同行目标'
  THEN
    RAISE EXCEPTION 'stage aliases changed stored scale semantics';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.promotion_target_relationship_revisions
    WHERE promotion_target_id = target_id_value
      AND revision_number = 3
      AND old_stage = 4
      AND new_stage = 4
      AND follow_up_note = '并发设备补充备注'
      AND changed_fields = ARRAY['follow_up_note']::text[]
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.promotion_target_relationship_conflicts AS conflict_row
    JOIN app_data.promotion_target_relationship_conflict_resolutions
      AS resolution_row USING (conflict_id)
    WHERE conflict_row.promotion_target_id = target_id_value
      AND conflict_row.conflicting_fields @> ARRAY['stage']::text[]
      AND conflict_row.proposed_follow_up_note = '另一个设备的备注'
      AND resolution_row.resolution_choice = 'apply_proposed'
      AND resolution_row.resolved_revision = 5
  ) THEN
    RAISE EXCEPTION 'field merge or explicit conflict resolution was lost';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.warehouse_outbox
    WHERE analytics_payload::text ~*
      '(关系审计对象|并发设备补充备注|对方希望下月再联系|另一个设备的备注)'
  ) THEN
    RAISE EXCEPTION 'relationship PII or notes entered warehouse payload';
  END IF;

  BEGIN
    UPDATE app_data.promotion_target_relationship_revisions
    SET reason_detail = 'tampered'
    WHERE promotion_target_id = target_id_value;
    RAISE EXCEPTION 'relationship revision history was mutable';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      NULL;
  END;
END
$relationship_checks$;

UPDATE app_data.promotion_target_assignments
SET ended_at = clock_timestamp(),
    end_reason = 'synthetic assignment revocation'
WHERE promotion_target_id = (
  SELECT (target->>'target_id')::uuid FROM relationship_target
)
  AND app_user_id = (SELECT app_user_id FROM relationship_owner_context)
  AND ended_at IS NULL;

SET LOCAL ROLE tongxingzhe_runtime;

DO $revoked_assignment_check$
BEGIN
  BEGIN
    PERFORM app_data.update_promotion_target_relationship(
      (SELECT app_user_id FROM relationship_owner_context),
      (SELECT workspace_id FROM relationship_owner_context),
      (SELECT project_id FROM relationship_owner_context),
      (SELECT (target->>'target_id')::uuid FROM relationship_target),
      5,
      4,
      'active',
      NULL,
      'progress_update',
      NULL,
      'relationship-after-revocation',
      NULL
    );
    RAISE EXCEPTION 'revoked assignee updated relationship';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$revoked_assignment_check$;

RESET ROLE;

ROLLBACK;
