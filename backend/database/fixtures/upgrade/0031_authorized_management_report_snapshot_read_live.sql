\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0000-4000-8000-000000007c01', 'active'),
  ('00000000-0000-4000-8000-000000007c02', 'active'),
  ('00000000-0000-4000-8000-000000007c0f', 'active');

INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
VALUES (
  '00000000-0000-4000-8000-000000007c03',
  'organization',
  '7CK upgrade workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES (
  '00000000-0000-4000-8000-000000007c05',
  '00000000-0000-4000-8000-000000007c03',
  '7CK upgrade project'
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES (
  '00000000-0000-4000-8000-000000007c0d',
  '00000000-0000-4000-8000-000000007c05',
  1, 'published', true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc
) VALUES
  (
    '00000000-0000-4000-8000-000000007c06',
    '00000000-0000-4000-8000-000000007c03',
    '00000000-0000-4000-8000-000000007c01',
    transaction_timestamp() - interval '60 days'
  ),
  (
    '00000000-0000-4000-8000-000000007c07',
    '00000000-0000-4000-8000-000000007c03',
    '00000000-0000-4000-8000-000000007c02',
    transaction_timestamp() - interval '60 days'
  );

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc
) VALUES
  (
    '00000000-0000-4000-8000-000000007c08',
    '00000000-0000-4000-8000-000000007c06',
    '00000000-0000-4000-8000-000000007c05',
    transaction_timestamp() - interval '60 days'
  ),
  (
    '00000000-0000-4000-8000-000000007c09',
    '00000000-0000-4000-8000-000000007c07',
    '00000000-0000-4000-8000-000000007c05',
    transaction_timestamp() - interval '60 days'
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id, active_from_utc
) VALUES
  (
    '00000000-0000-4000-8000-000000007c0a',
    '00000000-0000-4000-8000-000000007c08',
    'release_management_reports',
    transaction_timestamp() - interval '60 days'
  ),
  (
    '00000000-0000-4000-8000-000000007c0b',
    '00000000-0000-4000-8000-000000007c09',
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days'
  );

DO $setup$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '00000000-0000-4000-8000-000000007c10',
    '00000000-0000-4000-8000-000000007c01',
    '00000000-0000-4000-8000-000000007c05',
    0, 'UTC', transaction_timestamp() - interval '30 days'
  );
END
$setup$;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, reach_count, interest_level
)
SELECT
  '7ck-upgrade-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5 THEN
      '00000000-0000-4000-8000-000000007c01'::uuid
    WHEN series_row <= 8 THEN
      '00000000-0000-4000-8000-000000007c02'::uuid
    ELSE '00000000-0000-4000-8000-000000007c0f'::uuid
  END,
  '00000000-0000-4000-8000-000000007c03',
  '00000000-0000-4000-8000-000000007c05',
  '00000000-0000-4000-8000-000000007c0d',
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call', 'not_applicable', 1, 2
FROM (
  SELECT
    'previous' AS period_key,
    (date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
      - interval '12 days') AT TIME ZONE 'UTC' AS occurred_at_utc
  UNION ALL
  SELECT
    'current',
    (date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
      - interval '5 days') AT TIME ZONE 'UTC'
) AS period_row
CROSS JOIN generate_series(1, 10) AS series_row;

CREATE TEMP TABLE fixture_7ck_receipt AS
SELECT app_private.release_management_report_snapshot_v2(
  '00000000-0000-4000-8000-000000007c0c',
  '00000000-0000-4000-8000-000000007c01',
  '00000000-0000-4000-8000-000000007c05',
  'contact_sessions_by_channel_two_periods',
  1
) AS receipt;

DO $verify$
DECLARE
  receipt jsonb;
  v2 app_private.management_report_release_v2_attempts%ROWTYPE;
  v1 app_private.management_report_release_attempts%ROWTYPE;
  snapshot app_private.management_report_snapshots%ROWTYPE;
  zone app_private.project_reporting_time_zone_versions%ROWTYPE;
  periods jsonb;
BEGIN
  SELECT r.receipt INTO STRICT receipt FROM fixture_7ck_receipt AS r;
  SELECT a.* INTO STRICT v2
  FROM app_private.management_report_release_v2_attempts AS a
  WHERE a.release_request_id = '00000000-0000-4000-8000-000000007c0c';
  SELECT a.* INTO STRICT v1
  FROM app_private.management_report_release_attempts AS a
  WHERE a.release_request_id = '00000000-0000-4000-8000-000000007c0c';
  SELECT s.* INTO STRICT snapshot
  FROM app_private.management_report_snapshots AS s
  WHERE s.snapshot_id = v2.released_snapshot_id;
  SELECT z.* INTO STRICT zone
  FROM app_private.project_reporting_time_zone_versions AS z
  WHERE z.project_id = '00000000-0000-4000-8000-000000007c05'
    AND z.version_number = 1;

  IF receipt <> jsonb_build_object(
    'release_contract_id', 'trusted_management_report_snapshot_release_v2',
    'release_request_id', v2.release_request_id,
    'project_id', v2.project_id,
    'release_lineage_id', v2.release_lineage_id,
    'report_id', v2.report_id,
    'report_version', v2.report_version,
    'query_fingerprint', v2.query_fingerprint,
    'reporting_time_zone_version_number', v2.reporting_time_zone_version_number,
    'reporting_time_zone', v2.reporting_time_zone,
    'data_cutoff_utc', to_char(
      v2.data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'compared_snapshot_id', v2.compared_snapshot_id,
    'released_snapshot_id', v2.released_snapshot_id,
    'result_status', v2.result_status,
    'reason_codes', v2.reason_codes
  ) OR v2.result_document <> receipt
    OR v2.requested_by_app_user_id <>
      '00000000-0000-4000-8000-000000007c01'
    OR v2.organization_workspace_id <>
      '00000000-0000-4000-8000-000000007c03'
    OR v2.organization_membership_id <>
      '00000000-0000-4000-8000-000000007c06'
    OR v2.project_membership_id <>
      '00000000-0000-4000-8000-000000007c08'
    OR v2.capability_grant_id <>
      '00000000-0000-4000-8000-000000007c0a'
    OR v2.capability_id <> 'release_management_reports'
    OR v2.authorization_reference_at_utc <> v2.data_cutoff_utc
    OR v2.reporting_time_zone_version_number <> zone.version_number
    OR v2.reporting_time_zone <> zone.reporting_time_zone
    OR v2.reporting_time_zone <> 'UTC'
    OR v2.reporting_time_zone_effective_from_utc <> zone.effective_from_utc
    OR v2.delegated_release_request_id <> v2.release_request_id
    OR v2.result_status <> 'approved_baseline'
    OR v2.compared_snapshot_id IS NOT NULL
    OR v2.reason_codes <> '[]'::jsonb
  THEN
    RAISE EXCEPTION '7CK trusted release receipt or authorization is invalid';
  END IF;

  IF v1.requested_by_app_user_id <> v2.requested_by_app_user_id
    OR v1.project_id <> v2.project_id
    OR v1.release_lineage_id <> v2.release_lineage_id
    OR v1.report_id <> v2.report_id
    OR v1.report_version <> v2.report_version
    OR v1.query_fingerprint <> v2.query_fingerprint
    OR v1.reporting_time_zone <> v2.reporting_time_zone
    OR v1.data_cutoff_utc <> v2.data_cutoff_utc
    OR v1.compared_snapshot_id IS NOT NULL
    OR v1.released_snapshot_id <> v2.released_snapshot_id
    OR v1.result_status <> v2.result_status
    OR v1.reason_codes <> v2.reason_codes
    OR snapshot.release_request_id <> v2.release_request_id
    OR snapshot.created_by_app_user_id <> v2.requested_by_app_user_id
    OR snapshot.project_id <> v2.project_id
    OR snapshot.release_lineage_id <> v2.release_lineage_id
    OR snapshot.report_id <> v2.report_id
    OR snapshot.report_version <> v2.report_version
    OR snapshot.query_fingerprint <> v2.query_fingerprint
    OR snapshot.reporting_time_zone <> v2.reporting_time_zone
    OR snapshot.data_cutoff_utc <> v2.data_cutoff_utc
    OR snapshot.previous_snapshot_id IS NOT NULL
  THEN
    RAISE EXCEPTION '7CK v1 attempt or snapshot lineage differs from receipt';
  END IF;

  periods = app_private.resolve_management_report_periods_v1(
    'UTC', v2.data_cutoff_utc
  );
  IF snapshot.protected_report->'periods' <> periods
    OR (SELECT count(*) FROM app_data.contacts AS c
        WHERE c.project_id = v2.project_id) <> 20
    OR (SELECT count(*) FROM app_data.contacts AS c
        WHERE c.project_id = v2.project_id
          AND c.channel = 'voice_call'
          AND c.first_submitted_at_utc <= v2.data_cutoff_utc
          AND c.occurred_at_utc >=
            (periods->'previous_period'->>'start_utc')::timestamptz
          AND c.occurred_at_utc <
            (periods->'previous_period'->>'until_utc')::timestamptz) <> 10
    OR (SELECT count(*) FROM app_data.contacts AS c
        WHERE c.project_id = v2.project_id
          AND c.channel = 'voice_call'
          AND c.first_submitted_at_utc <= v2.data_cutoff_utc
          AND c.occurred_at_utc >=
            (periods->'current_period'->>'start_utc')::timestamptz
          AND c.occurred_at_utc <
            (periods->'current_period'->>'until_utc')::timestamptz) <> 10
  THEN
    RAISE EXCEPTION '7CK completed UTC source periods are invalid';
  END IF;
END
$verify$;

COMMIT;

SELECT receipt::text FROM fixture_7ck_receipt;
