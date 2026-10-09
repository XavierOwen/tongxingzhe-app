\set ON_ERROR_STOP on

BEGIN;

DO $fixture$
DECLARE
  actor_id uuid;
  workspace_id uuid;
  project_id uuid;
  first_target_id uuid := '7ed00000-0000-4000-8000-000000000001';
  second_target_id uuid := '7ed00000-0000-4000-8000-000000000002';
  first_assignment_id uuid := '7ed00000-0000-4000-8000-000000000011';
  second_assignment_id uuid := '7ed00000-0000-4000-8000-000000000012';
  preview_id uuid;
BEGIN
  SELECT context.app_user_id, context.workspace_id, context.project_id
  INTO STRICT actor_id, workspace_id, project_id
  FROM app_data.bootstrap_personal_context(
    'https://0117-upgrade-assignment-end.example.test/auth/v1',
    '0117-upgrade-assignment-end-owner'
  ) AS context;
  PERFORM 1
  FROM app_data.list_personal_project_contexts(
    'https://0117-upgrade-assignment-end.example.test/auth/v1',
    '0117-upgrade-assignment-end-owner'
  ) AS context
  WHERE context.is_current;

  INSERT INTO app_data.promotion_targets (
    promotion_target_id, workspace_id, target_type, display_name,
    phone, email, created_by_app_user_id
  ) VALUES
    (first_target_id, workspace_id, 'person', '0117 upgrade end first',
     '+1 773 555 0118', 'first-0118@example.test', actor_id),
    (second_target_id, workspace_id, 'person', '0117 upgrade end second',
     '+1 773 555 0118', 'second-0118@example.test', actor_id);
  INSERT INTO app_data.promotion_target_assignments (
    assignment_id, promotion_target_id, app_user_id, assigned_by_app_user_id
  ) VALUES
    (first_assignment_id, first_target_id, actor_id, actor_id),
    (second_assignment_id, second_target_id, actor_id, actor_id);

  SELECT preview.preview_id INTO STRICT preview_id
  FROM app_data.preview_personal_target_pair_v1(
    'https://0117-upgrade-assignment-end.example.test/auth/v1',
    '0117-upgrade-assignment-end-owner', project_id,
    first_target_id, second_target_id
  ) AS preview;
  PERFORM app_private.activate_personal_target_merge_generation_v2(
    actor_id, project_id, '7ed00000-0000-4000-8000-000000000021',
    preview_id, first_target_id, first_target_id, second_target_id, first_target_id
  );
END
$fixture$;

CREATE TABLE public.fixture_0118_upgrade_state AS
SELECT
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
  (SELECT max(version) FROM app_migrations.schema_migrations) AS latest_migration,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.promotion_target_id)
   FROM app_data.promotion_targets AS row_value) AS targets,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.assignment_id)
   FROM app_data.promotion_target_assignments AS row_value) AS assignments,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.promotion_target_id, row_value.event_id)
   FROM app_data.promotion_target_retention_events AS row_value)
    AS retention_events,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.workspace_id)
   FROM app_data.promotion_target_retention_policies AS row_value)
    AS retention_policies,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.preview_id)
   FROM app_private.personal_target_pair_preview_receipts AS row_value)
    AS preview_receipts,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.generation_id)
   FROM app_private.personal_target_merge_generations_v1 AS row_value)
    AS generations,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.generation_id, row_value.promotion_target_id)
   FROM app_private.personal_target_merge_generation_members_v1 AS row_value)
    AS generation_members,
  (SELECT jsonb_agg(to_jsonb(row_value) ORDER BY row_value.promotion_target_id)
   FROM app_private.personal_target_merge_active_members_v1 AS row_value)
    AS active_members,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.actor_app_user_id, row_value.request_id)
   FROM app_private.personal_target_merge_activation_requests_v1 AS row_value)
    AS activation_requests,
  (SELECT jsonb_agg(to_jsonb(row_value)
      ORDER BY row_value.actor_app_user_id, row_value.request_id)
   FROM app_private.personal_target_merge_activation_audit_v1 AS row_value)
    AS activation_audit;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0118_upgrade_state) <> 1
    OR (SELECT migration_count FROM public.fixture_0118_upgrade_state) <> 116
    OR (SELECT latest_migration FROM public.fixture_0118_upgrade_state)
      IS DISTINCT FROM '0117_personal_target_merge_receipt_consumption'
    OR (SELECT jsonb_array_length(activation_requests)
        FROM public.fixture_0118_upgrade_state) < 1
    OR (SELECT jsonb_array_length(activation_audit)
        FROM public.fixture_0118_upgrade_state) < 1
  THEN
    RAISE EXCEPTION '0117→0118 live upgrade baseline drift';
  END IF;
END
$baseline$;

COMMIT;
