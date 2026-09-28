-- Two trusted-v2 channel snapshots committed before the 0067 replacement seam.
\set ON_ERROR_STOP on
\set QUIET on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0066_clock AS
SELECT transaction_timestamp() AS fixture_now_utc;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('66d10000-0000-4000-8000-000000000001', 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  '66d20000-0000-4000-8000-000000000001', 'organization',
  '0066 channel replacement upgrade organization', NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '66d30000-0000-4000-8000-000000000001',
  '66d20000-0000-4000-8000-000000000001',
  '0066 channel replacement upgrade project', 'active', false
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES (
  '66d80000-0000-4000-8000-000000000001',
  '66d30000-0000-4000-8000-000000000001', 1, 'published', true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
SELECT
  '66d40000-0000-4000-8000-000000000001',
  '66d20000-0000-4000-8000-000000000001',
  '66d10000-0000-4000-8000-000000000001',
  fixture_now_utc - interval '365 days', NULL
FROM fixture_0066_clock;

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
)
SELECT
  '66d50000-0000-4000-8000-000000000001',
  '66d40000-0000-4000-8000-000000000001',
  '66d30000-0000-4000-8000-000000000001',
  fixture_now_utc - interval '365 days', NULL
FROM fixture_0066_clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
)
SELECT
  '66d60000-0000-4000-8000-000000000001',
  '66d50000-0000-4000-8000-000000000001',
  'release_management_reports',
  fixture_now_utc - interval '365 days', NULL
FROM fixture_0066_clock;

CREATE TEMP TABLE fixture_0066_time_zone_receipt AS
SELECT app_private.configure_project_reporting_time_zone_v1(
  '66d70000-0000-4000-8000-000000000001',
  '66d10000-0000-4000-8000-000000000001',
  '66d30000-0000-4000-8000-000000000001',
  0, 'UTC', fixture_now_utc - interval '365 days'
) AS receipt
FROM fixture_0066_clock;

CREATE TEMP TABLE fixture_0066_contact_plan AS
SELECT
  format('fixture-0066-%s-%s', period_key, series_number) AS contact_id,
  (periods->(period_key || '_period')->>'start_utc')::timestamptz
    + interval '1 day' AS occurred_at_utc
FROM (
  SELECT app_private.resolve_management_report_periods_v1(
    'UTC', fixture_now_utc
  ) AS periods
  FROM fixture_0066_clock
) AS report_periods
CROSS JOIN (VALUES ('previous'), ('current')) AS period(period_key)
CROSS JOIN generate_series(1, 10) AS series_number;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, reach_count,
  interest_level
)
SELECT
  contact_id,
  '66d10000-0000-4000-8000-000000000001',
  '66d20000-0000-4000-8000-000000000001',
  '66d30000-0000-4000-8000-000000000001',
  '66d80000-0000-4000-8000-000000000001',
  occurred_at_utc, 'UTC', occurred_at_utc,
  'voice_call', 'not_applicable', 1, 2
FROM fixture_0066_contact_plan;

CREATE TEMP TABLE fixture_0066_release_receipts (
  release_order integer PRIMARY KEY,
  release_result jsonb NOT NULL
);

INSERT INTO fixture_0066_release_receipts VALUES (
  1,
  app_private.release_management_report_snapshot_v2(
    '66d90000-0000-4000-8000-000000000001',
    '66d10000-0000-4000-8000-000000000001',
    '66d30000-0000-4000-8000-000000000001',
    'contact_sessions_by_channel_two_periods', 1
  )
);
COMMIT;

SELECT pg_sleep(0.01);
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO fixture_0066_release_receipts VALUES (
  2,
  app_private.release_management_report_snapshot_v2(
    '66d90000-0000-4000-8000-000000000002',
    '66d10000-0000-4000-8000-000000000001',
    '66d30000-0000-4000-8000-000000000001',
    'contact_sessions_by_channel_two_periods', 1
  )
);

DO $legacy$
DECLARE
  first_receipt jsonb := (
    SELECT release_result FROM fixture_0066_release_receipts
    WHERE release_order = 1
  );
  second_receipt jsonb := (
    SELECT release_result FROM fixture_0066_release_receipts
    WHERE release_order = 2
  );
  first_snapshot_id uuid := (first_receipt->>'released_snapshot_id')::uuid;
  second_snapshot_id uuid := (second_receipt->>'released_snapshot_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM app_data.app_users
      WHERE app_user_id = '66d10000-0000-4000-8000-000000000001'
        AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.workspaces
        WHERE workspace_id = '66d20000-0000-4000-8000-000000000001'
          AND workspace_kind = 'organization'
          AND personal_owner_app_user_id IS NULL
          AND deleted_at IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.projects
        WHERE project_id = '66d30000-0000-4000-8000-000000000001'
          AND workspace_id = '66d20000-0000-4000-8000-000000000001'
          AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.questionnaire_versions
        WHERE questionnaire_version_id =
          '66d80000-0000-4000-8000-000000000001'
          AND project_id = '66d30000-0000-4000-8000-000000000001'
          AND version_number = 1 AND status = 'published' AND is_current) <> 1
    OR (SELECT count(*) FROM app_data.organization_memberships
        WHERE organization_membership_id =
          '66d40000-0000-4000-8000-000000000001'
          AND organization_workspace_id =
            '66d20000-0000-4000-8000-000000000001'
          AND app_user_id = '66d10000-0000-4000-8000-000000000001'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.project_memberships
        WHERE project_membership_id =
          '66d50000-0000-4000-8000-000000000001'
          AND organization_membership_id =
            '66d40000-0000-4000-8000-000000000001'
          AND project_id = '66d30000-0000-4000-8000-000000000001'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.management_report_capability_grants
        WHERE capability_grant_id = '66d60000-0000-4000-8000-000000000001'
          AND project_membership_id =
            '66d50000-0000-4000-8000-000000000001'
          AND capability_id = 'release_management_reports'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*)
        FROM app_private.project_reporting_time_zone_versions
        WHERE project_id = '66d30000-0000-4000-8000-000000000001'
          AND version_number = 1 AND expected_version = 0
          AND change_request_id =
            '66d70000-0000-4000-8000-000000000001'
          AND requested_by_app_user_id =
            '66d10000-0000-4000-8000-000000000001'
          AND reporting_time_zone = 'UTC') <> 1
    OR (SELECT count(*) FROM fixture_0066_time_zone_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0066_contact_plan) <> 20
    OR (SELECT count(*) FROM app_data.contacts
        WHERE contact_id IN (SELECT contact_id FROM fixture_0066_contact_plan)
          AND project_id = '66d30000-0000-4000-8000-000000000001'
          AND questionnaire_version_id =
            '66d80000-0000-4000-8000-000000000001'
          AND occurred_time_zone = 'UTC'
          AND channel = 'voice_call'
          AND lifecycle_status = 'active') <> 20
    OR (SELECT count(*) FROM fixture_0066_release_receipts) <> 2
    OR EXISTS (
      SELECT 1 FROM fixture_0066_release_receipts
      WHERE release_result - ARRAY[
        'release_contract_id', 'release_request_id', 'project_id',
        'release_lineage_id', 'report_id', 'report_version',
        'query_fingerprint', 'reporting_time_zone_version_number',
        'reporting_time_zone', 'data_cutoff_utc',
        'compared_snapshot_id', 'released_snapshot_id', 'result_status',
        'reason_codes'
      ] <> '{}'::jsonb
      OR NOT release_result ?& ARRAY[
        'release_contract_id', 'release_request_id', 'project_id',
        'release_lineage_id', 'report_id', 'report_version',
        'query_fingerprint', 'reporting_time_zone_version_number',
        'reporting_time_zone', 'data_cutoff_utc',
        'compared_snapshot_id', 'released_snapshot_id', 'result_status',
        'reason_codes'
      ]
    )
    OR first_receipt->>'release_contract_id' IS DISTINCT FROM
      'trusted_management_report_snapshot_release_v2'
    OR first_receipt->>'release_request_id' IS DISTINCT FROM
      '66d90000-0000-4000-8000-000000000001'
    OR second_receipt->>'release_request_id' IS DISTINCT FROM
      '66d90000-0000-4000-8000-000000000002'
    OR first_receipt->>'project_id' IS DISTINCT FROM
      '66d30000-0000-4000-8000-000000000001'
    OR first_receipt->>'release_lineage_id' IS DISTINCT FROM
      'management-report:contact_sessions_by_channel_two_periods'
    OR first_receipt->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_channel_two_periods'
    OR first_receipt->>'report_version' IS DISTINCT FROM '1'
    OR first_receipt->>'query_fingerprint' IS DISTINCT FROM
      'management-report:contact_sessions_by_channel_two_periods:v1'
    OR first_receipt->>'reporting_time_zone_version_number'
      IS DISTINCT FROM '1'
    OR first_receipt->>'reporting_time_zone' IS DISTINCT FROM 'UTC'
    OR (second_receipt - ARRAY[
      'release_request_id', 'data_cutoff_utc', 'compared_snapshot_id',
      'released_snapshot_id', 'result_status'
    ]) IS DISTINCT FROM (first_receipt - ARRAY[
      'release_request_id', 'data_cutoff_utc', 'compared_snapshot_id',
      'released_snapshot_id', 'result_status'
    ])
    OR first_receipt->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR second_receipt->>'result_status' IS DISTINCT FROM 'approved'
    OR first_receipt->'reason_codes' <> '[]'::jsonb
    OR second_receipt->'reason_codes' <> '[]'::jsonb
    OR first_receipt->'compared_snapshot_id' <> 'null'::jsonb
    OR second_receipt->>'compared_snapshot_id' IS DISTINCT FROM
      first_snapshot_id::text
    OR first_snapshot_id IS NULL OR second_snapshot_id IS NULL
    OR first_snapshot_id = second_snapshot_id
    OR (first_receipt->>'data_cutoff_utc')::timestamptz >=
      (second_receipt->>'data_cutoff_utc')::timestamptz
    OR (first_receipt::text || second_receipt::text) ~*
      '"(protected_report|period_results|cells|value_count|contact_id|contributor|phone|email|raw_answer)"[[:space:]]*:'
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE snapshot_id IN (first_snapshot_id, second_snapshot_id)
          AND project_id = '66d30000-0000-4000-8000-000000000001'
          AND release_lineage_id =
            'management-report:contact_sessions_by_channel_two_periods'
          AND report_id = 'contact_sessions_by_channel_two_periods'
          AND report_version = 1) <> 2
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE project_id = '66d30000-0000-4000-8000-000000000001'
          AND release_lineage_id =
            'management-report:contact_sessions_by_channel_two_periods') <> 2
    OR (SELECT previous_snapshot_id FROM app_private.management_report_snapshots
        WHERE snapshot_id = first_snapshot_id) IS NOT NULL
    OR (SELECT previous_snapshot_id FROM app_private.management_report_snapshots
        WHERE snapshot_id = second_snapshot_id) IS DISTINCT FROM
      first_snapshot_id
    OR (SELECT protected_report - ARRAY['data_cutoff_utc', 'periods']
        FROM app_private.management_report_snapshots
        WHERE snapshot_id = first_snapshot_id) IS DISTINCT FROM (
      SELECT protected_report - ARRAY['data_cutoff_utc', 'periods']
      FROM app_private.management_report_snapshots
      WHERE snapshot_id = second_snapshot_id
    )
    OR (SELECT (protected_report->'periods') - 'data_cutoff_utc'::text
        FROM app_private.management_report_snapshots
        WHERE snapshot_id = first_snapshot_id) IS DISTINCT FROM (
      SELECT (protected_report->'periods') - 'data_cutoff_utc'::text
      FROM app_private.management_report_snapshots
      WHERE snapshot_id = second_snapshot_id
    )
    OR (SELECT count(*) FROM app_private.management_report_release_v2_attempts
        WHERE release_request_id IN (
          '66d90000-0000-4000-8000-000000000001',
          '66d90000-0000-4000-8000-000000000002'
        ) AND requested_by_app_user_id =
          '66d10000-0000-4000-8000-000000000001'
          AND organization_workspace_id =
            '66d20000-0000-4000-8000-000000000001'
          AND organization_membership_id =
            '66d40000-0000-4000-8000-000000000001'
          AND project_membership_id =
            '66d50000-0000-4000-8000-000000000001'
          AND capability_grant_id =
            '66d60000-0000-4000-8000-000000000001'
          AND capability_id = 'release_management_reports'
          AND project_id = '66d30000-0000-4000-8000-000000000001'
          AND result_status IN ('approved_baseline', 'approved')) <> 2
    OR (SELECT count(*) FROM app_private.management_report_release_v2_attempts
        WHERE project_id = '66d30000-0000-4000-8000-000000000001') <> 2
    OR (SELECT count(*) FROM app_private.management_report_release_attempts
        WHERE release_request_id IN (
          '66d90000-0000-4000-8000-000000000001',
          '66d90000-0000-4000-8000-000000000002'
        ) AND requested_by_app_user_id =
          '66d10000-0000-4000-8000-000000000001'
          AND project_id = '66d30000-0000-4000-8000-000000000001'
          AND result_status IN ('approved_baseline', 'approved')) <> 2
    OR (SELECT count(*) FROM app_private.management_report_release_attempts
        WHERE project_id = '66d30000-0000-4000-8000-000000000001') <> 2
    OR (SELECT count(*)
        FROM app_private.management_report_release_request_claims
        WHERE release_request_id IN (
          '66d90000-0000-4000-8000-000000000001',
          '66d90000-0000-4000-8000-000000000002'
        ) AND release_family_id =
          'channel_management_report_snapshot_release') <> 2
    OR (SELECT count(*)
        FROM fixture_0066_release_receipts AS receipt_row
        JOIN app_private.management_report_release_v2_attempts AS v2
          ON v2.release_request_id =
            (receipt_row.release_result->>'release_request_id')::uuid
        JOIN app_private.management_report_release_attempts AS v1
          ON v1.release_request_id = v2.delegated_release_request_id
        JOIN app_private.management_report_snapshots AS snapshot
          ON snapshot.snapshot_id = v2.released_snapshot_id
        JOIN app_private.management_report_release_request_claims AS claim
          ON claim.release_request_id = v2.release_request_id) <> 2
    OR EXISTS (
      SELECT 1
      FROM fixture_0066_release_receipts AS receipt_row
      JOIN app_private.management_report_release_v2_attempts AS v2
        ON v2.release_request_id =
          (receipt_row.release_result->>'release_request_id')::uuid
      JOIN app_private.management_report_release_attempts AS v1
        ON v1.release_request_id = v2.delegated_release_request_id
      JOIN app_private.management_report_snapshots AS snapshot
        ON snapshot.snapshot_id = v2.released_snapshot_id
      JOIN app_private.management_report_release_request_claims AS claim
        ON claim.release_request_id = v2.release_request_id
      WHERE v2.result_document IS DISTINCT FROM receipt_row.release_result
        OR v2.authorization_reference_at_utc IS DISTINCT FROM
          v2.data_cutoff_utc
        OR v2.data_cutoff_utc IS DISTINCT FROM v1.data_cutoff_utc
        OR v2.data_cutoff_utc IS DISTINCT FROM snapshot.data_cutoff_utc
        OR v2.data_cutoff_utc IS DISTINCT FROM snapshot.released_at_utc
        OR v2.data_cutoff_utc IS DISTINCT FROM
          (receipt_row.release_result->>'data_cutoff_utc')::timestamptz
        OR v2.requested_by_app_user_id IS DISTINCT FROM
          snapshot.created_by_app_user_id
        OR v2.project_id IS DISTINCT FROM v1.project_id
        OR v2.project_id IS DISTINCT FROM snapshot.project_id
        OR v2.release_lineage_id IS DISTINCT FROM v1.release_lineage_id
        OR v2.release_lineage_id IS DISTINCT FROM snapshot.release_lineage_id
        OR v2.report_id IS DISTINCT FROM v1.report_id
        OR v2.report_id IS DISTINCT FROM snapshot.report_id
        OR v2.report_version IS DISTINCT FROM v1.report_version
        OR v2.report_version IS DISTINCT FROM snapshot.report_version
        OR v2.query_fingerprint IS DISTINCT FROM v1.query_fingerprint
        OR v2.query_fingerprint IS DISTINCT FROM snapshot.query_fingerprint
        OR v2.reporting_time_zone IS DISTINCT FROM v1.reporting_time_zone
        OR v2.reporting_time_zone IS DISTINCT FROM snapshot.reporting_time_zone
        OR v2.reporting_time_zone_version_number <> 1
        OR v2.reporting_time_zone_effective_from_utc IS DISTINCT FROM (
          SELECT effective_from_utc
          FROM app_private.project_reporting_time_zone_versions
          WHERE project_id = v2.project_id
            AND version_number = v2.reporting_time_zone_version_number
        )
        OR v2.compared_snapshot_id IS DISTINCT FROM v1.compared_snapshot_id
        OR v2.compared_snapshot_id IS DISTINCT FROM
          snapshot.previous_snapshot_id
        OR v2.released_snapshot_id IS DISTINCT FROM v1.released_snapshot_id
        OR snapshot.release_request_id IS DISTINCT FROM v2.release_request_id
        OR v2.result_status IS DISTINCT FROM v1.result_status
        OR v2.reason_codes IS DISTINCT FROM v1.reason_codes
        OR v2.reason_codes IS DISTINCT FROM '[]'::jsonb
        OR claim.release_family_id IS DISTINCT FROM
          'channel_management_report_snapshot_release'
        OR snapshot.source_change_sequence IS DISTINCT FROM
          v1.source_change_sequence
        OR snapshot.protected_report->'periods'->>'reporting_time_zone'
          IS DISTINCT FROM 'UTC'
    )
  THEN
    RAISE EXCEPTION '0066 channel replacement baseline drift';
  END IF;
END
$legacy$;

CREATE TEMP TABLE fixture_0066_history_bytes (
  entity_kind text NOT NULL,
  entity_id uuid NOT NULL,
  entity_bytes jsonb NOT NULL,
  PRIMARY KEY (entity_kind, entity_id)
);
INSERT INTO fixture_0066_history_bytes
SELECT 'snapshot', snapshot_id, to_jsonb(snapshot.*)
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.release_request_id IN (
  '66d90000-0000-4000-8000-000000000001',
  '66d90000-0000-4000-8000-000000000002'
)
UNION ALL
SELECT 'v2_attempt', release_request_id, to_jsonb(attempt.*)
FROM app_private.management_report_release_v2_attempts AS attempt
WHERE release_request_id IN (
  '66d90000-0000-4000-8000-000000000001',
  '66d90000-0000-4000-8000-000000000002'
)
UNION ALL
SELECT 'v1_attempt', release_request_id, to_jsonb(attempt.*)
FROM app_private.management_report_release_attempts AS attempt
WHERE release_request_id IN (
  '66d90000-0000-4000-8000-000000000001',
  '66d90000-0000-4000-8000-000000000002'
)
UNION ALL
SELECT 'claim', release_request_id, to_jsonb(claim.*)
FROM app_private.management_report_release_request_claims AS claim
WHERE release_request_id IN (
  '66d90000-0000-4000-8000-000000000001',
  '66d90000-0000-4000-8000-000000000002'
);

DO $saved_history$
BEGIN
  IF (SELECT count(*) FROM fixture_0066_history_bytes) <> 8
  THEN
    RAISE EXCEPTION '0066 channel replacement history snapshot drift';
  END IF;
END
$saved_history$;

COMMIT;

SELECT release_result::text
FROM fixture_0066_release_receipts
ORDER BY release_order;
