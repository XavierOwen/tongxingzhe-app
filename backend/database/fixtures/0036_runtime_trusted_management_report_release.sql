\set ON_ERROR_STOP on

BEGIN;

-- Synthetic identities deliberately use a separate namespace from earlier
-- fixtures. No real user, contact, location or report data is stored.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('8f100000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('8f100000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('8f100000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    '8fe00000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-release.synthetic/auth/v1',
    'release-member',
    '8f100000-0000-4000-8000-000000000001'::uuid
  ),
  (
    '8fe00000-0000-4000-8000-000000000002'::uuid,
    'https://runtime-release.synthetic/auth/v1',
    'view-only-member',
    '8f100000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '8fe00000-0000-4000-8000-000000000003'::uuid,
    'https://runtime-release.synthetic/auth/v1',
    'disabled-member',
    '8f100000-0000-4000-8000-000000000003'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  '8f200000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic runtime release workspace',
  NULL,
  NULL
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
) VALUES
  (
    '8f300000-0000-4000-8000-000000000001'::uuid,
    '8f200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic configured release project',
    'active',
    false
  ),
  (
    '8f300000-0000-4000-8000-000000000002'::uuid,
    '8f200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic cross-project release project',
    'active',
    false
  ),
  (
    '8f300000-0000-4000-8000-000000000003'::uuid,
    '8f200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic unconfigured release project',
    'active',
    false
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  '8f700000-0000-4000-8000-000000000001'::uuid,
  '8f300000-0000-4000-8000-000000000001'::uuid,
  1,
  'published',
  true
);

-- 两个周期间各十条匿名接触，使固定报告可以通过 6J 的隐私门槛。
INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel,
  location_kind,
  reach_count,
  interest_level
)
SELECT
  'runtime-release-' || period_row.period_key || '-' || series_row::text,
  '8f100000-0000-4000-8000-000000000001'::uuid,
  '8f200000-0000-4000-8000-000000000001'::uuid,
  '8f300000-0000-4000-8000-000000000001'::uuid,
  '8f700000-0000-4000-8000-000000000001'::uuid,
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  SELECT
    'previous'::text AS period_key,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '12 days'
    ) AT TIME ZONE 'UTC' AS occurred_at_utc
  UNION ALL
  SELECT
    'current'::text,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '5 days'
    ) AT TIME ZONE 'UTC'
) AS period_row
CROSS JOIN generate_series(1, 10) AS series_row;

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '8f400000-0000-4000-8000-000000000001'::uuid,
    '8f200000-0000-4000-8000-000000000001'::uuid,
    '8f100000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f400000-0000-4000-8000-000000000002'::uuid,
    '8f200000-0000-4000-8000-000000000001'::uuid,
    '8f100000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f400000-0000-4000-8000-000000000003'::uuid,
    '8f200000-0000-4000-8000-000000000001'::uuid,
    '8f100000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '8f500000-0000-4000-8000-000000000001'::uuid,
    '8f400000-0000-4000-8000-000000000001'::uuid,
    '8f300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f500000-0000-4000-8000-000000000002'::uuid,
    '8f400000-0000-4000-8000-000000000001'::uuid,
    '8f300000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f500000-0000-4000-8000-000000000003'::uuid,
    '8f400000-0000-4000-8000-000000000001'::uuid,
    '8f300000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f500000-0000-4000-8000-000000000004'::uuid,
    '8f400000-0000-4000-8000-000000000002'::uuid,
    '8f300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f500000-0000-4000-8000-000000000005'::uuid,
    '8f400000-0000-4000-8000-000000000003'::uuid,
    '8f300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '8f600000-0000-4000-8000-000000000001'::uuid,
    '8f500000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f600000-0000-4000-8000-000000000002'::uuid,
    '8f500000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f600000-0000-4000-8000-000000000003'::uuid,
    '8f500000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f600000-0000-4000-8000-000000000004'::uuid,
    '8f500000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8f600000-0000-4000-8000-000000000005'::uuid,
    '8f500000-0000-4000-8000-000000000005'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  );

-- 0030 的 app_user active 校验要求先建立 disabled 身份的历史链，再将
-- 账号置为 deletion_pending；bridge 必须在映射阶段拒绝它。
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '8f100000-0000-4000-8000-000000000003'::uuid;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '8f900000-0000-4000-8000-000000000001'::uuid,
  '8f100000-0000-4000-8000-000000000001'::uuid,
  '8f300000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  transaction_timestamp() - interval '30 days'
);

CREATE TEMP TABLE runtime_trusted_release_before_counts
ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_users,
  (SELECT count(*) FROM app_data.workspaces) AS workspaces,
  (SELECT count(*) FROM app_data.projects) AS projects;

-- 以 runtime role 执行 bridge，确保 SECURITY DEFINER 是唯一入口。
SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture$
DECLARE
  baseline jsonb;
  replay jsonb;
BEGIN
  baseline = app_data.release_management_report_snapshot_v1(
    'https://runtime-release.synthetic/auth/v1',
    'release-member',
    '8f800000-0000-4000-8000-000000000001'::uuid,
    '8f300000-0000-4000-8000-000000000001'::uuid
  );
  replay = app_data.release_management_report_snapshot_v1(
    'https://runtime-release.synthetic/auth/v1',
    'release-member',
    '8f800000-0000-4000-8000-000000000001'::uuid,
    '8f300000-0000-4000-8000-000000000001'::uuid
  );

  IF baseline <> replay
    OR baseline->>'release_contract_id' <>
      'trusted_management_report_snapshot_release_v2'
    OR baseline->>'release_request_id' <>
      '8f800000-0000-4000-8000-000000000001'
    OR baseline->>'project_id' <>
      '8f300000-0000-4000-8000-000000000001'
    OR baseline->>'release_lineage_id' <>
      'management-report:contact_sessions_by_channel_two_periods'
    OR baseline->>'report_id' <>
      'contact_sessions_by_channel_two_periods'
    OR baseline->>'report_version' <> '1'
    OR baseline->>'result_status' <> 'approved_baseline'
    OR baseline->>'reporting_time_zone_version_number' <> '1'
    OR baseline->>'reporting_time_zone' <> 'UTC'
    OR baseline->>'released_snapshot_id' IS NULL
    OR baseline->>'query_fingerprint' IS NULL
    OR baseline->>'data_cutoff_utc' IS NULL
    OR baseline->>'compared_snapshot_id' IS NOT NULL
    OR baseline->'reason_codes' <> '[]'::jsonb
    OR baseline ? 'protected_report'
    OR baseline ? 'cells'
    OR baseline ? 'contributor'
    OR baseline ? 'capability_grant_id'
    OR baseline ? 'authorization_reference_at_utc'
    OR baseline::text ~* 'contact_count|shared_period|assessed_cell|organization_membership|app_user'
  THEN
    RAISE EXCEPTION 'runtime trusted release result is not fixed and value-free';
  END IF;

  -- 同一 request UUID 不能换项目；6J 应在已有 attempt 上 fail closed，且
  -- 不允许 bridge 绕过 v2 的项目冲突检查。
  BEGIN
    PERFORM app_data.release_management_report_snapshot_v1(
      'https://runtime-release.synthetic/auth/v1',
      'release-member',
      '8f800000-0000-4000-8000-000000000001'::uuid,
      '8f300000-0000-4000-8000-000000000002'::uuid
    );
    RAISE EXCEPTION 'runtime trusted release accepted a cross-project replay';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  -- 配置缺失应保留 6J 的类型化 prerequisite error，且不可写入 attempt。
  BEGIN
    PERFORM app_data.release_management_report_snapshot_v1(
      'https://runtime-release.synthetic/auth/v1',
      'release-member',
      '8f800000-0000-4000-8000-000000000003'::uuid,
      '8f300000-0000-4000-8000-000000000003'::uuid
    );
    RAISE EXCEPTION 'runtime trusted release accepted an unconfigured project';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  BEGIN
    PERFORM app_data.release_management_report_snapshot_v1(
      'https://runtime-release.synthetic/auth/v1',
      'unknown-member',
      '8f800000-0000-0000-0000-000000000004'::uuid,
      '8f300000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime trusted release accepted an unknown identity';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.release_management_report_snapshot_v1(
      'https://runtime-release.synthetic/auth/v1',
      'disabled-member',
      '8f800000-0000-4000-8000-000000000005'::uuid,
      '8f300000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime trusted release accepted a disabled identity';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_data.release_management_report_snapshot_v1(
      'https://runtime-release.synthetic/auth/v1',
      'view-only-member',
      '8f800000-0000-4000-8000-000000000006'::uuid,
      '8f300000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime trusted release accepted a view-only identity';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

END
$fixture$;

RESET ROLE;

DO $stored_checks$
BEGIN
  -- 未知、停用和 view-only 身份均应在映射/授权阶段失败，不能 bootstrap
  -- 新账号或个人上下文。恢复测试可能已有其他 fixture 的提交数据，故与
  -- 本 fixture 开始前的计数比较，而不假设全库为空。
  IF (SELECT count(*) FROM app_data.app_users) <>
      (SELECT app_users FROM runtime_trusted_release_before_counts)
    OR (SELECT count(*) FROM app_data.workspaces) <>
      (SELECT workspaces FROM runtime_trusted_release_before_counts)
    OR (SELECT count(*) FROM app_data.projects) <>
      (SELECT projects FROM runtime_trusted_release_before_counts)
  THEN
    RAISE EXCEPTION 'runtime trusted release created identity context';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_report_release_v2_attempts
    WHERE project_id = '8f300000-0000-4000-8000-000000000001'::uuid
  ) <> 1 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshots
    WHERE project_id = '8f300000-0000-4000-8000-000000000001'::uuid
  ) <> 1 THEN
    RAISE EXCEPTION 'runtime trusted release replay or blocked paths wrote history';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id IN (
      '8f800000-0000-4000-8000-000000000003'::uuid,
      '8f800000-0000-0000-0000-000000000004'::uuid,
      '8f800000-0000-4000-8000-000000000005'::uuid,
      '8f800000-0000-4000-8000-000000000006'::uuid
    )
  ) THEN
    RAISE EXCEPTION 'forbidden or unconfigured runtime release wrote evidence';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts AS attempt
    WHERE attempt.release_request_id =
        '8f800000-0000-4000-8000-000000000001'::uuid
      AND attempt.requested_by_app_user_id =
        '8f100000-0000-4000-8000-000000000001'::uuid
      AND attempt.project_id =
        '8f300000-0000-4000-8000-000000000001'::uuid
      AND attempt.report_id = 'contact_sessions_by_channel_two_periods'
      AND attempt.report_version = 1
      AND attempt.result_status = 'approved_baseline'
      AND attempt.delegated_release_request_id = attempt.release_request_id
  ) THEN
    RAISE EXCEPTION 'runtime trusted release evidence is incomplete';
  END IF;
END
$stored_checks$;

ROLLBACK;
