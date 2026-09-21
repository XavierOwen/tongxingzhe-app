-- Two approved 0075 snapshots committed before the 0083 replacement seam.
\set ON_ERROR_STOP on
\set QUIET on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0082_clock AS
SELECT transaction_timestamp() AS fixture_now_utc;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('82d10000-0000-4000-8000-000000000001', 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  '82d20000-0000-4000-8000-000000000001',
  'organization',
  '0082 consent replacement upgrade organization',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '82d30000-0000-4000-8000-000000000001',
  '82d20000-0000-4000-8000-000000000001',
  '0082 consent replacement upgrade project',
  'active',
  false
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '82d40000-0000-4000-8000-000000000001',
  '82d20000-0000-4000-8000-000000000001',
  '82d10000-0000-4000-8000-000000000001',
  fixture_now_utc - interval '365 days',
  NULL
FROM fixture_0082_clock;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '82d50000-0000-4000-8000-000000000001',
  '82d40000-0000-4000-8000-000000000001',
  '82d30000-0000-4000-8000-000000000001',
  fixture_now_utc - interval '365 days',
  NULL
FROM fixture_0082_clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '82d60000-0000-4000-8000-000000000001',
  '82d50000-0000-4000-8000-000000000001',
  'release_management_reports',
  fixture_now_utc - interval '365 days',
  NULL
FROM fixture_0082_clock;

CREATE TEMP TABLE fixture_0082_time_zone_receipt AS
SELECT app_private.configure_project_reporting_time_zone_v1(
  '82d70000-0000-4000-8000-000000000001',
  '82d10000-0000-4000-8000-000000000001',
  '82d30000-0000-4000-8000-000000000001',
  0,
  'UTC',
  fixture_now_utc - interval '365 days'
) AS receipt
FROM fixture_0082_clock;

CREATE TEMP TABLE fixture_0082_opt_in_receipts (
  configuration_order integer PRIMARY KEY,
  receipt jsonb NOT NULL
);
GRANT ALL ON fixture_0082_opt_in_receipts
  TO tongxingzhe_management_follow_up_consent_config_writer;

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
INSERT INTO fixture_0082_opt_in_receipts VALUES (
  1,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    '82d10000-0000-4000-8000-000000000001',
    '82d30000-0000-4000-8000-000000000001',
    'follow_up_consent_ratio@1',
    '82d80000-0000-4000-8000-000000000001',
    0,
    true
  )
);
RESET ROLE;

CREATE TEMP TABLE fixture_0082_release_receipts (
  release_order integer PRIMARY KEY,
  release_result jsonb NOT NULL
);

INSERT INTO fixture_0082_release_receipts VALUES (
  1,
  app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '82d90000-0000-4000-8000-000000000001',
    '82d10000-0000-4000-8000-000000000001',
    '82d30000-0000-4000-8000-000000000001',
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  )
);
COMMIT;

SELECT pg_sleep(0.01);
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO fixture_0082_release_receipts VALUES (
  2,
  app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '82d90000-0000-4000-8000-000000000002',
    '82d10000-0000-4000-8000-000000000001',
    '82d30000-0000-4000-8000-000000000001',
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  )
);

DO $legacy$
DECLARE
  first_receipt jsonb := (
    SELECT release_result FROM fixture_0082_release_receipts
    WHERE release_order = 1
  );
  second_receipt jsonb := (
    SELECT release_result FROM fixture_0082_release_receipts
    WHERE release_order = 2
  );
  first_snapshot_id uuid :=
    (first_receipt->>'released_snapshot_id')::uuid;
  second_snapshot_id uuid :=
    (second_receipt->>'released_snapshot_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM app_data.app_users
      WHERE app_user_id = '82d10000-0000-4000-8000-000000000001'
        AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.workspaces
        WHERE workspace_id = '82d20000-0000-4000-8000-000000000001'
          AND workspace_kind = 'organization'
          AND personal_owner_app_user_id IS NULL
          AND deleted_at IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.projects
        WHERE project_id = '82d30000-0000-4000-8000-000000000001'
          AND workspace_id = '82d20000-0000-4000-8000-000000000001'
          AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.organization_memberships
        WHERE organization_membership_id =
            '82d40000-0000-4000-8000-000000000001'
          AND organization_workspace_id =
            '82d20000-0000-4000-8000-000000000001'
          AND app_user_id = '82d10000-0000-4000-8000-000000000001'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.project_memberships
        WHERE project_membership_id =
            '82d50000-0000-4000-8000-000000000001'
          AND organization_membership_id =
            '82d40000-0000-4000-8000-000000000001'
          AND project_id = '82d30000-0000-4000-8000-000000000001'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.management_report_capability_grants
        WHERE capability_grant_id =
            '82d60000-0000-4000-8000-000000000001'
          AND project_membership_id =
            '82d50000-0000-4000-8000-000000000001'
          AND capability_id = 'release_management_reports'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*)
        FROM app_private.project_reporting_time_zone_versions
        WHERE project_id = '82d30000-0000-4000-8000-000000000001'
          AND version_number = 1
          AND expected_version = 0
          AND change_request_id =
            '82d70000-0000-4000-8000-000000000001'
          AND requested_by_app_user_id =
            '82d10000-0000-4000-8000-000000000001'
          AND reporting_time_zone = 'UTC') <> 1
    OR (SELECT receipt->>'status'
        FROM fixture_0082_opt_in_receipts
        WHERE configuration_order = 1) IS DISTINCT FROM 'enabled'
    OR (SELECT receipt->>'enabled'
        FROM fixture_0082_opt_in_receipts
        WHERE configuration_order = 1) IS DISTINCT FROM 'true'
    OR (SELECT count(*) FROM fixture_0082_release_receipts) <> 2
    OR first_receipt - ARRAY[
      'release_contract_id', 'release_request_id', 'project_id',
      'release_lineage_id', 'report_id', 'report_version',
      'query_fingerprint', 'reporting_time_zone_version_number',
      'reporting_time_zone', 'data_cutoff_utc', 'source_change_sequence',
      'compared_snapshot_id', 'released_snapshot_id',
      'shared_period_count', 'assessed_cell_count', 'result_status',
      'reason_codes'
    ] <> '{}'::jsonb
    OR NOT first_receipt ?& ARRAY[
      'release_contract_id', 'release_request_id', 'project_id',
      'release_lineage_id', 'report_id', 'report_version',
      'query_fingerprint', 'reporting_time_zone_version_number',
      'reporting_time_zone', 'data_cutoff_utc', 'source_change_sequence',
      'compared_snapshot_id', 'released_snapshot_id',
      'shared_period_count', 'assessed_cell_count', 'result_status',
      'reason_codes'
    ]
    OR second_receipt - ARRAY[
      'release_contract_id', 'release_request_id', 'project_id',
      'release_lineage_id', 'report_id', 'report_version',
      'query_fingerprint', 'reporting_time_zone_version_number',
      'reporting_time_zone', 'data_cutoff_utc', 'source_change_sequence',
      'compared_snapshot_id', 'released_snapshot_id',
      'shared_period_count', 'assessed_cell_count', 'result_status',
      'reason_codes'
    ] <> '{}'::jsonb
    OR NOT second_receipt ?& ARRAY[
      'release_contract_id', 'release_request_id', 'project_id',
      'release_lineage_id', 'report_id', 'report_version',
      'query_fingerprint', 'reporting_time_zone_version_number',
      'reporting_time_zone', 'data_cutoff_utc', 'source_change_sequence',
      'compared_snapshot_id', 'released_snapshot_id',
      'shared_period_count', 'assessed_cell_count', 'result_status',
      'reason_codes'
    ]
    OR first_receipt->>'release_contract_id' IS DISTINCT FROM
      'follow_up_consent_ratio_management_report_snapshot_release_v1'
    OR first_receipt->>'release_request_id' IS DISTINCT FROM
      '82d90000-0000-4000-8000-000000000001'
    OR second_receipt->>'release_request_id' IS DISTINCT FROM
      '82d90000-0000-4000-8000-000000000002'
    OR first_receipt->>'project_id' IS DISTINCT FROM
      '82d30000-0000-4000-8000-000000000001'
    OR first_receipt->>'release_lineage_id' IS DISTINCT FROM
      'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
    OR first_receipt->>'report_id' IS DISTINCT FROM
      'contact_target_follow_up_consent_ratio_two_periods'
    OR first_receipt->>'report_version' IS DISTINCT FROM '1'
    OR first_receipt->>'query_fingerprint' IS DISTINCT FROM
      'management-report:contact_target_follow_up_consent_ratio_two_periods:v1'
    OR first_receipt->>'reporting_time_zone_version_number' IS DISTINCT FROM
      '1'
    OR first_receipt->>'reporting_time_zone' IS DISTINCT FROM 'UTC'
    OR second_receipt->>'release_contract_id' IS DISTINCT FROM
      first_receipt->>'release_contract_id'
    OR second_receipt->>'project_id' IS DISTINCT FROM
      first_receipt->>'project_id'
    OR second_receipt->>'release_lineage_id' IS DISTINCT FROM
      first_receipt->>'release_lineage_id'
    OR second_receipt->>'report_id' IS DISTINCT FROM
      first_receipt->>'report_id'
    OR second_receipt->>'report_version' IS DISTINCT FROM
      first_receipt->>'report_version'
    OR second_receipt->>'query_fingerprint' IS DISTINCT FROM
      first_receipt->>'query_fingerprint'
    OR second_receipt->>'reporting_time_zone_version_number' IS DISTINCT FROM
      first_receipt->>'reporting_time_zone_version_number'
    OR second_receipt->>'reporting_time_zone' IS DISTINCT FROM
      first_receipt->>'reporting_time_zone'
    OR first_receipt->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR second_receipt->>'result_status' IS DISTINCT FROM 'approved'
    OR first_receipt->>'shared_period_count' IS DISTINCT FROM '0'
    OR first_receipt->>'assessed_cell_count' IS DISTINCT FROM '0'
    OR second_receipt->>'shared_period_count' IS DISTINCT FROM '2'
    OR second_receipt->>'assessed_cell_count' IS DISTINCT FROM '8'
    OR first_receipt->>'source_change_sequence' IS DISTINCT FROM '0'
    OR second_receipt->>'source_change_sequence' IS DISTINCT FROM '0'
    OR first_receipt->'reason_codes' <> '[]'::jsonb
    OR second_receipt->'reason_codes' <> '[]'::jsonb
    OR first_receipt->'compared_snapshot_id' <> 'null'::jsonb
    OR second_receipt->>'compared_snapshot_id' IS DISTINCT FROM
      first_snapshot_id::text
    OR first_snapshot_id = second_snapshot_id
    OR (first_receipt->>'data_cutoff_utc')::timestamptz >=
      (second_receipt->>'data_cutoff_utc')::timestamptz
    OR (first_receipt::text || second_receipt::text) ~*
      '"(protected_report|period_results|ratio|coverage|contact_id|promotion_target_id|contributor|phone|email|raw_answer)"[[:space:]]*:'
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE snapshot_id IN (first_snapshot_id, second_snapshot_id)
          AND project_id = '82d30000-0000-4000-8000-000000000001'
          AND release_lineage_id =
            'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
          AND report_id =
            'contact_target_follow_up_consent_ratio_two_periods'
          AND report_version = 1) <> 2
    OR (SELECT previous_snapshot_id
        FROM app_private.management_report_snapshots
        WHERE snapshot_id = first_snapshot_id) IS NOT NULL
    OR (SELECT previous_snapshot_id
        FROM app_private.management_report_snapshots
        WHERE snapshot_id = second_snapshot_id) IS DISTINCT FROM
      first_snapshot_id
    OR (SELECT count(*)
        FROM app_private.management_follow_up_consent_report_release_attempts
        WHERE release_request_id IN (
          '82d90000-0000-4000-8000-000000000001',
          '82d90000-0000-4000-8000-000000000002'
        )
          AND requested_by_app_user_id =
            '82d10000-0000-4000-8000-000000000001'
          AND organization_workspace_id =
            '82d20000-0000-4000-8000-000000000001'
          AND organization_membership_id =
            '82d40000-0000-4000-8000-000000000001'
          AND project_membership_id =
            '82d50000-0000-4000-8000-000000000001'
          AND capability_grant_id =
            '82d60000-0000-4000-8000-000000000001'
          AND capability_id = 'release_management_reports'
          AND project_id = '82d30000-0000-4000-8000-000000000001'
          AND result_status IN ('approved_baseline', 'approved')) <> 2
    OR (SELECT count(*)
        FROM fixture_0082_release_receipts AS receipt_row
        JOIN app_private.management_follow_up_consent_report_release_attempts
          AS attempt
          ON attempt.release_request_id =
            (receipt_row.release_result->>'release_request_id')::uuid
        JOIN app_private.management_report_snapshots AS snapshot
          ON snapshot.snapshot_id = attempt.released_snapshot_id) <> 2
    OR EXISTS (
      SELECT 1
      FROM fixture_0082_release_receipts AS receipt_row
      JOIN app_private.management_follow_up_consent_report_release_attempts
        AS attempt
        ON attempt.release_request_id =
          (receipt_row.release_result->>'release_request_id')::uuid
      JOIN app_private.management_report_snapshots AS snapshot
        ON snapshot.snapshot_id = attempt.released_snapshot_id
      WHERE attempt.result_document IS DISTINCT FROM receipt_row.release_result
        OR attempt.requested_by_app_user_id IS DISTINCT FROM
          '82d10000-0000-4000-8000-000000000001'::uuid
        OR attempt.authorization_reference_at_utc IS DISTINCT FROM
          attempt.data_cutoff_utc
        OR attempt.data_cutoff_utc IS DISTINCT FROM snapshot.data_cutoff_utc
        OR attempt.data_cutoff_utc IS DISTINCT FROM snapshot.released_at_utc
        OR attempt.project_id IS DISTINCT FROM snapshot.project_id
        OR attempt.project_id::text IS DISTINCT FROM
          receipt_row.release_result->>'project_id'
        OR snapshot.release_request_id IS DISTINCT FROM
          attempt.release_request_id
        OR snapshot.created_by_app_user_id IS DISTINCT FROM
          attempt.requested_by_app_user_id
        OR attempt.release_lineage_id IS DISTINCT FROM
          snapshot.release_lineage_id
        OR attempt.release_lineage_id IS DISTINCT FROM
          receipt_row.release_result->>'release_lineage_id'
        OR attempt.report_id IS DISTINCT FROM snapshot.report_id
        OR attempt.report_id IS DISTINCT FROM
          receipt_row.release_result->>'report_id'
        OR attempt.report_version IS DISTINCT FROM snapshot.report_version
        OR attempt.report_version::text IS DISTINCT FROM
          receipt_row.release_result->>'report_version'
        OR attempt.query_fingerprint IS DISTINCT FROM
          snapshot.query_fingerprint
        OR attempt.query_fingerprint IS DISTINCT FROM
          receipt_row.release_result->>'query_fingerprint'
        OR attempt.reporting_time_zone_version_number::text IS DISTINCT FROM
          receipt_row.release_result->>'reporting_time_zone_version_number'
        OR attempt.reporting_time_zone IS DISTINCT FROM
          receipt_row.release_result->>'reporting_time_zone'
        OR attempt.data_cutoff_utc IS DISTINCT FROM
          (receipt_row.release_result->>'data_cutoff_utc')::timestamptz
        OR attempt.source_change_sequence IS DISTINCT FROM
          snapshot.source_change_sequence
        OR attempt.source_change_sequence::text IS DISTINCT FROM
          receipt_row.release_result->>'source_change_sequence'
        OR attempt.compared_snapshot_id IS DISTINCT FROM
          snapshot.previous_snapshot_id
        OR attempt.released_snapshot_id::text IS DISTINCT FROM
          receipt_row.release_result->>'released_snapshot_id'
        OR attempt.compared_snapshot_id::text IS DISTINCT FROM
          receipt_row.release_result->>'compared_snapshot_id'
        OR attempt.result_status IS DISTINCT FROM
          receipt_row.release_result->>'result_status'
        OR attempt.shared_period_count::text IS DISTINCT FROM
          receipt_row.release_result->>'shared_period_count'
        OR attempt.assessed_cell_count::text IS DISTINCT FROM
          receipt_row.release_result->>'assessed_cell_count'
        OR attempt.reason_codes IS DISTINCT FROM
          receipt_row.release_result->'reason_codes'
    )
    OR (SELECT count(*)
        FROM app_private.management_report_release_request_claims
        WHERE release_request_id IN (
          '82d90000-0000-4000-8000-000000000001',
          '82d90000-0000-4000-8000-000000000002'
        )
          AND release_family_id =
            'follow_up_consent_ratio_management_report_snapshot_release') <> 2
  THEN
    RAISE EXCEPTION '0082 consent replacement baseline drift';
  END IF;
END
$legacy$;

CREATE TEMP TABLE fixture_0082_history_bytes (
  entity_kind text NOT NULL,
  entity_id uuid NOT NULL,
  entity_bytes jsonb NOT NULL,
  PRIMARY KEY (entity_kind, entity_id)
);
INSERT INTO fixture_0082_history_bytes
SELECT 'snapshot', snapshot_id, to_jsonb(snapshot.*)
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot_id IN (
  SELECT (release_result->>'released_snapshot_id')::uuid
  FROM fixture_0082_release_receipts
)
UNION ALL
SELECT 'attempt', release_request_id, to_jsonb(attempt.*)
FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
WHERE release_request_id IN (
  '82d90000-0000-4000-8000-000000000001',
  '82d90000-0000-4000-8000-000000000002'
)
UNION ALL
SELECT 'claim', release_request_id, to_jsonb(claim.*)
FROM app_private.management_report_release_request_claims AS claim
WHERE release_request_id IN (
  '82d90000-0000-4000-8000-000000000001',
  '82d90000-0000-4000-8000-000000000002'
);

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
INSERT INTO fixture_0082_opt_in_receipts VALUES (
  2,
  app_private.configure_management_follow_up_consent_opt_in_v1(
    '82d10000-0000-4000-8000-000000000001',
    '82d30000-0000-4000-8000-000000000001',
    'follow_up_consent_ratio@1',
    '82d80000-0000-4000-8000-000000000002',
    1,
    false
  )
);
RESET ROLE;

DO $disabled$
BEGIN
  IF (SELECT receipt->>'status' FROM fixture_0082_opt_in_receipts
      WHERE configuration_order = 2) IS DISTINCT FROM 'not_enabled'
    OR (SELECT receipt->>'enabled' FROM fixture_0082_opt_in_receipts
        WHERE configuration_order = 2) IS DISTINCT FROM 'false'
    OR (SELECT count(*) FROM fixture_0082_history_bytes) <> 6
    OR EXISTS (
      SELECT 1
      FROM fixture_0082_history_bytes AS saved
      LEFT JOIN LATERAL (
        SELECT to_jsonb(snapshot.*) AS current_bytes
        FROM app_private.management_report_snapshots AS snapshot
        WHERE saved.entity_kind = 'snapshot'
          AND snapshot.snapshot_id = saved.entity_id
        UNION ALL
        SELECT to_jsonb(attempt.*)
        FROM app_private.management_follow_up_consent_report_release_attempts
          AS attempt
        WHERE saved.entity_kind = 'attempt'
          AND attempt.release_request_id = saved.entity_id
        UNION ALL
        SELECT to_jsonb(claim.*)
        FROM app_private.management_report_release_request_claims AS claim
        WHERE saved.entity_kind = 'claim'
          AND claim.release_request_id = saved.entity_id
      ) AS current_row ON true
      WHERE current_row.current_bytes IS DISTINCT FROM saved.entity_bytes
    )
  THEN
    RAISE EXCEPTION '0082 consent opt-in disable rewrote release history';
  END IF;
END
$disabled$;

COMMIT;

SELECT release_result::text
FROM fixture_0082_release_receipts
ORDER BY release_order;
