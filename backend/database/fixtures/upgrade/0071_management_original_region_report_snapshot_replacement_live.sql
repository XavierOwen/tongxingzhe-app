-- Two real 0068 releases committed before the 0072 replacement seam.
\set ON_ERROR_STOP on
\set QUIET on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0071_clock AS
SELECT transaction_timestamp() AS fixture_now_utc;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('71d10000-0000-4000-8000-000000000001', 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  '71d20000-0000-4000-8000-000000000001', 'organization',
  '0071 original-region replacement upgrade organization', NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '71d30000-0000-4000-8000-000000000001',
  '71d20000-0000-4000-8000-000000000001',
  '0071 original-region replacement upgrade project', 'active', false
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES (
  '71d80000-0000-4000-8000-000000000001',
  '71d30000-0000-4000-8000-000000000001', 1, 'published', true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
SELECT
  '71d40000-0000-4000-8000-000000000001',
  '71d20000-0000-4000-8000-000000000001',
  '71d10000-0000-4000-8000-000000000001',
  fixture_now_utc - interval '365 days', NULL
FROM fixture_0071_clock;

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
)
SELECT
  '71d50000-0000-4000-8000-000000000001',
  '71d40000-0000-4000-8000-000000000001',
  '71d30000-0000-4000-8000-000000000001',
  fixture_now_utc - interval '365 days', NULL
FROM fixture_0071_clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
)
SELECT
  '71d60000-0000-4000-8000-000000000001',
  '71d50000-0000-4000-8000-000000000001',
  'release_management_reports',
  fixture_now_utc - interval '365 days', NULL
FROM fixture_0071_clock;

CREATE TEMP TABLE fixture_0071_time_zone_receipt AS
SELECT app_private.configure_project_reporting_time_zone_v1(
  '71d70000-0000-4000-8000-000000000001',
  '71d10000-0000-4000-8000-000000000001',
  '71d30000-0000-4000-8000-000000000001',
  0, 'UTC', fixture_now_utc - interval '365 days'
) AS receipt
FROM fixture_0071_clock;

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current, published_at_utc,
  content_fingerprint
) VALUES (
  'fixture-0071-original-v1', 'draft', false, NULL, NULL
);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  ('fixture-0071-country', 'fixture-0071-original-v1', NULL,
   '0071 Country', 'country'),
  ('fixture-0071-city', 'fixture-0071-original-v1',
   'fixture-0071-country', '0071 City', 'city');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'fixture-0071-city-boundary', 'fixture-0071-city',
  'fixture-0071-original-v1',
  polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
);

CREATE TEMP TABLE fixture_0071_region_receipt AS
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-0071-original-v1', false
) AS receipt;

CREATE TEMP TABLE fixture_0071_contact_plan AS
SELECT
  period_key,
  'fixture-0071-' || period_key AS contact_id,
  (periods->(period_key || '_period')->>'start_utc')::timestamptz
    AS occurred_at_utc
FROM (
  SELECT app_private.resolve_management_report_periods_v1(
    'UTC', fixture_now_utc
  ) AS periods
  FROM fixture_0071_clock
) AS report_periods
CROSS JOIN (VALUES ('previous'), ('current')) AS period(period_key);

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, place_name,
  smallest_region_id, region_tree_version, reach_count, interest_level
)
SELECT
  contact_id,
  '71d10000-0000-4000-8000-000000000001',
  '71d20000-0000-4000-8000-000000000001',
  '71d30000-0000-4000-8000-000000000001',
  '71d80000-0000-4000-8000-000000000001',
  occurred_at_utc, 'UTC', occurred_at_utc,
  'face_to_face', 'resolved', '0071 source city',
  'fixture-0071-city', 'fixture-0071-original-v1', 1, 2
FROM fixture_0071_contact_plan;

-- The accepted revision trigger captures the immutable source-tree tuple.
INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind,
  revised_by_app_user_id, snapshot
)
SELECT
  contact_id, 1, 'submitted',
  '71d10000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'contactId', contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved', 'placeName', '0071 source city',
      'smallestRegionId', 'fixture-0071-city',
      'regionTreeVersion', 'fixture-0071-original-v1'
    )
  )
FROM fixture_0071_contact_plan;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id,
  revision_number, change_type
)
SELECT
  '71d10000-0000-4000-8000-000000000001',
  '71d20000-0000-4000-8000-000000000001',
  '71d30000-0000-4000-8000-000000000001',
  contact_id, 1, 'contact.submitted'
FROM fixture_0071_contact_plan;

CREATE TEMP TABLE fixture_0071_source_watermark AS
SELECT max(change_sequence) AS source_change_sequence
FROM app_data.change_feed
WHERE project_id = '71d30000-0000-4000-8000-000000000001';

CREATE TEMP TABLE fixture_0071_release_receipts (
  release_order integer PRIMARY KEY,
  release_result jsonb NOT NULL
);

INSERT INTO fixture_0071_release_receipts VALUES (
  1,
  app_private.release_management_original_region_report_snapshot_v1(
    '71d90000-0000-4000-8000-000000000001',
    '71d10000-0000-4000-8000-000000000001',
    '71d30000-0000-4000-8000-000000000001',
    'contact_sessions_by_original_region_two_periods', 1
  )
);
COMMIT;

SELECT pg_sleep(0.01);
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO fixture_0071_release_receipts VALUES (
  2,
  app_private.release_management_original_region_report_snapshot_v1(
    '71d90000-0000-4000-8000-000000000002',
    '71d10000-0000-4000-8000-000000000001',
    '71d30000-0000-4000-8000-000000000001',
    'contact_sessions_by_original_region_two_periods', 1
  )
);

DO $legacy$
DECLARE
  first_receipt jsonb := (
    SELECT release_result FROM fixture_0071_release_receipts
    WHERE release_order = 1
  );
  second_receipt jsonb := (
    SELECT release_result FROM fixture_0071_release_receipts
    WHERE release_order = 2
  );
  first_snapshot_id uuid :=
    (first_receipt->>'released_snapshot_id')::uuid;
  second_snapshot_id uuid :=
    (second_receipt->>'released_snapshot_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM app_data.app_users
      WHERE app_user_id = '71d10000-0000-4000-8000-000000000001'
        AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.workspaces
        WHERE workspace_id = '71d20000-0000-4000-8000-000000000001'
          AND workspace_kind = 'organization'
          AND personal_owner_app_user_id IS NULL
          AND deleted_at IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.projects
        WHERE project_id = '71d30000-0000-4000-8000-000000000001'
          AND workspace_id = '71d20000-0000-4000-8000-000000000001'
          AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.questionnaire_versions
        WHERE questionnaire_version_id =
          '71d80000-0000-4000-8000-000000000001'
          AND project_id = '71d30000-0000-4000-8000-000000000001'
          AND version_number = 1 AND status = 'published' AND is_current) <> 1
    OR (SELECT count(*) FROM app_data.organization_memberships
        WHERE organization_membership_id =
          '71d40000-0000-4000-8000-000000000001'
          AND organization_workspace_id =
            '71d20000-0000-4000-8000-000000000001'
          AND app_user_id = '71d10000-0000-4000-8000-000000000001'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.project_memberships
        WHERE project_membership_id =
          '71d50000-0000-4000-8000-000000000001'
          AND organization_membership_id =
            '71d40000-0000-4000-8000-000000000001'
          AND project_id = '71d30000-0000-4000-8000-000000000001'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.management_report_capability_grants
        WHERE capability_grant_id =
          '71d60000-0000-4000-8000-000000000001'
          AND project_membership_id =
            '71d50000-0000-4000-8000-000000000001'
          AND capability_id = 'release_management_reports'
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*)
        FROM app_private.project_reporting_time_zone_versions
        WHERE project_id = '71d30000-0000-4000-8000-000000000001'
          AND version_number = 1 AND expected_version = 0
          AND change_request_id =
            '71d70000-0000-4000-8000-000000000001'
          AND requested_by_app_user_id =
            '71d10000-0000-4000-8000-000000000001'
          AND reporting_time_zone = 'UTC') <> 1
    OR (SELECT count(*) FROM fixture_0071_time_zone_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0071_region_receipt) <> 1
    OR (SELECT receipt - ARRAY[
          'tree_version', 'lifecycle_state', 'is_current',
          'content_fingerprint', 'published_at_utc'
        ] FROM fixture_0071_region_receipt) <> '{}'::jsonb
    OR NOT (SELECT receipt ?& ARRAY[
          'tree_version', 'lifecycle_state', 'is_current',
          'content_fingerprint', 'published_at_utc'
        ] FROM fixture_0071_region_receipt)
    OR (SELECT receipt->>'tree_version' FROM fixture_0071_region_receipt)
      IS DISTINCT FROM 'fixture-0071-original-v1'
    OR (SELECT receipt->>'lifecycle_state' FROM fixture_0071_region_receipt)
      IS DISTINCT FROM 'published'
    OR (SELECT receipt->>'is_current' FROM fixture_0071_region_receipt)
      IS DISTINCT FROM 'false'
    OR (SELECT receipt->>'content_fingerprint'
        FROM fixture_0071_region_receipt) IS DISTINCT FROM (
      SELECT content_fingerprint
      FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-0071-original-v1'
        AND lifecycle_state = 'published' AND NOT is_current
    )
    OR (SELECT (receipt->>'published_at_utc')::timestamptz
        FROM fixture_0071_region_receipt) IS DISTINCT FROM (
      SELECT published_at_utc FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-0071-original-v1'
    )
    OR (SELECT count(*) FROM app_data.canonical_region_versions
        WHERE tree_version = 'fixture-0071-original-v1') <> 2
    OR (SELECT count(*) FROM app_data.canonical_region_boundaries
        WHERE tree_version = 'fixture-0071-original-v1') <> 1
    OR (SELECT count(*) FROM fixture_0071_contact_plan) <> 2
    OR (SELECT count(*) FROM app_data.contacts
        WHERE contact_id IN (SELECT contact_id FROM fixture_0071_contact_plan)
          AND project_id = '71d30000-0000-4000-8000-000000000001'
          AND questionnaire_version_id =
            '71d80000-0000-4000-8000-000000000001'
          AND occurred_time_zone = 'UTC'
          AND lifecycle_status = 'active') <> 2
    OR (SELECT count(*) FROM app_data.contact_location_provenance
        WHERE contact_id IN (SELECT contact_id FROM fixture_0071_contact_plan)
          AND revision_number = 1 AND revision_kind = 'submitted'
          AND location_kind = 'resolved'
          AND evidence_kind = 'resolved_region_only'
          AND smallest_region_id = 'fixture-0071-city'
          AND region_tree_version = 'fixture-0071-original-v1'
          AND region_tree_content_fingerprint = (
            SELECT content_fingerprint
            FROM app_data.canonical_region_tree_releases
            WHERE tree_version = 'fixture-0071-original-v1'
          )) <> 2
    OR (SELECT source_change_sequence FROM fixture_0071_source_watermark)
      IS NULL
    OR (SELECT source_change_sequence FROM fixture_0071_source_watermark)
      <= 0
    OR (SELECT count(*) FROM fixture_0071_release_receipts) <> 2
    OR EXISTS (
      SELECT 1 FROM fixture_0071_release_receipts
      WHERE release_result - ARRAY[
        'release_contract_id', 'release_request_id', 'project_id',
        'release_lineage_id', 'report_id', 'report_version',
        'query_fingerprint', 'reporting_time_zone_version_number',
        'reporting_time_zone', 'data_cutoff_utc', 'source_tree_version',
        'source_content_fingerprint', 'source_change_sequence',
        'compared_snapshot_id', 'released_snapshot_id',
        'shared_period_count', 'assessed_cell_count', 'result_status',
        'reason_codes'
      ] <> '{}'::jsonb
      OR NOT release_result ?& ARRAY[
        'release_contract_id', 'release_request_id', 'project_id',
        'release_lineage_id', 'report_id', 'report_version',
        'query_fingerprint', 'reporting_time_zone_version_number',
        'reporting_time_zone', 'data_cutoff_utc', 'source_tree_version',
        'source_content_fingerprint', 'source_change_sequence',
        'compared_snapshot_id', 'released_snapshot_id',
        'shared_period_count', 'assessed_cell_count', 'result_status',
        'reason_codes'
      ]
    )
    OR first_receipt->>'release_contract_id' IS DISTINCT FROM
      'original_region_management_report_snapshot_release_v1'
    OR first_receipt->>'release_request_id' IS DISTINCT FROM
      '71d90000-0000-4000-8000-000000000001'
    OR second_receipt->>'release_request_id' IS DISTINCT FROM
      '71d90000-0000-4000-8000-000000000002'
    OR first_receipt->>'project_id' IS DISTINCT FROM
      '71d30000-0000-4000-8000-000000000001'
    OR first_receipt->>'release_lineage_id' IS DISTINCT FROM
      'management-original-region-report:contact_sessions_by_original_region_two_periods'
    OR first_receipt->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_original_region_two_periods'
    OR first_receipt->>'report_version' IS DISTINCT FROM '1'
    OR first_receipt->>'query_fingerprint' IS DISTINCT FROM
      'management-report:contact_sessions_by_original_region_two_periods:v1'
    OR first_receipt->>'reporting_time_zone_version_number'
      IS DISTINCT FROM '1'
    OR first_receipt->>'reporting_time_zone' IS DISTINCT FROM 'UTC'
    OR first_receipt->>'source_tree_version' IS DISTINCT FROM
      'fixture-0071-original-v1'
    OR first_receipt->>'source_content_fingerprint' IS DISTINCT FROM (
      SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-0071-original-v1'
    )
    OR first_receipt->>'source_change_sequence' IS DISTINCT FROM (
      SELECT source_change_sequence::text FROM fixture_0071_source_watermark
    )
    OR second_receipt->>'source_change_sequence' IS DISTINCT FROM (
      SELECT source_change_sequence::text FROM fixture_0071_source_watermark
    )
    OR (second_receipt - ARRAY[
      'release_request_id', 'data_cutoff_utc', 'compared_snapshot_id',
      'released_snapshot_id', 'shared_period_count', 'assessed_cell_count',
      'result_status'
    ]) IS DISTINCT FROM (first_receipt - ARRAY[
      'release_request_id', 'data_cutoff_utc', 'compared_snapshot_id',
      'released_snapshot_id', 'shared_period_count', 'assessed_cell_count',
      'result_status'
    ])
    OR first_receipt->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR second_receipt->>'result_status' IS DISTINCT FROM 'approved'
    OR first_receipt->>'shared_period_count' IS DISTINCT FROM '0'
    OR first_receipt->>'assessed_cell_count' IS DISTINCT FROM '0'
    OR second_receipt->>'shared_period_count' IS DISTINCT FROM '2'
    OR second_receipt->>'assessed_cell_count' IS DISTINCT FROM '2'
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
          AND project_id = '71d30000-0000-4000-8000-000000000001'
          AND release_lineage_id =
            'management-original-region-report:contact_sessions_by_original_region_two_periods'
          AND report_id = 'contact_sessions_by_original_region_two_periods'
          AND report_version = 1) <> 2
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE project_id = '71d30000-0000-4000-8000-000000000001'
          AND release_lineage_id =
            'management-original-region-report:contact_sessions_by_original_region_two_periods') <> 2
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
    OR EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots
      WHERE snapshot_id IN (first_snapshot_id, second_snapshot_id)
        AND protected_report->'periods'->>'reporting_time_zone'
          IS DISTINCT FROM 'UTC'
    )
    OR (SELECT count(*)
        FROM app_private.management_original_region_report_release_attempts
        WHERE release_request_id IN (
          '71d90000-0000-4000-8000-000000000001',
          '71d90000-0000-4000-8000-000000000002'
        )
          AND requested_by_app_user_id =
            '71d10000-0000-4000-8000-000000000001'
          AND organization_workspace_id =
            '71d20000-0000-4000-8000-000000000001'
          AND organization_membership_id =
            '71d40000-0000-4000-8000-000000000001'
          AND project_membership_id =
            '71d50000-0000-4000-8000-000000000001'
          AND capability_grant_id =
            '71d60000-0000-4000-8000-000000000001'
          AND capability_id = 'release_management_reports'
          AND project_id = '71d30000-0000-4000-8000-000000000001'
          AND result_status IN ('approved_baseline', 'approved')) <> 2
    OR (SELECT count(*)
        FROM app_private.management_original_region_report_release_attempts
        WHERE project_id = '71d30000-0000-4000-8000-000000000001') <> 2
    OR (SELECT count(*)
        FROM fixture_0071_release_receipts AS receipt_row
        JOIN app_private.management_original_region_report_release_attempts
          AS attempt ON attempt.release_request_id =
            (receipt_row.release_result->>'release_request_id')::uuid
        JOIN app_private.management_report_snapshots AS snapshot
          ON snapshot.snapshot_id = attempt.released_snapshot_id) <> 2
    OR EXISTS (
      SELECT 1
      FROM fixture_0071_release_receipts AS receipt_row
      JOIN app_private.management_original_region_report_release_attempts
        AS attempt ON attempt.release_request_id =
          (receipt_row.release_result->>'release_request_id')::uuid
      JOIN app_private.management_report_snapshots AS snapshot
        ON snapshot.snapshot_id = attempt.released_snapshot_id
      WHERE attempt.result_document IS DISTINCT FROM receipt_row.release_result
        OR attempt.requested_by_app_user_id IS DISTINCT FROM
          '71d10000-0000-4000-8000-000000000001'::uuid
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
        OR attempt.release_lineage_id IS DISTINCT FROM snapshot.release_lineage_id
        OR attempt.release_lineage_id IS DISTINCT FROM
          receipt_row.release_result->>'release_lineage_id'
        OR attempt.report_id IS DISTINCT FROM snapshot.report_id
        OR attempt.report_id IS DISTINCT FROM receipt_row.release_result->>'report_id'
        OR attempt.report_version IS DISTINCT FROM snapshot.report_version
        OR attempt.report_version::text IS DISTINCT FROM
          receipt_row.release_result->>'report_version'
        OR attempt.query_fingerprint IS DISTINCT FROM snapshot.query_fingerprint
        OR attempt.query_fingerprint IS DISTINCT FROM
          receipt_row.release_result->>'query_fingerprint'
        OR attempt.reporting_time_zone_version_number::text IS DISTINCT FROM
          receipt_row.release_result->>'reporting_time_zone_version_number'
        OR attempt.reporting_time_zone IS DISTINCT FROM
          receipt_row.release_result->>'reporting_time_zone'
        OR attempt.reporting_time_zone_effective_from_utc IS DISTINCT FROM (
          SELECT version_row.effective_from_utc
          FROM app_private.project_reporting_time_zone_versions AS version_row
          WHERE version_row.project_id = attempt.project_id
            AND version_row.version_number =
              attempt.reporting_time_zone_version_number
        )
        OR attempt.data_cutoff_utc IS DISTINCT FROM
          (receipt_row.release_result->>'data_cutoff_utc')::timestamptz
        OR attempt.source_tree_version IS DISTINCT FROM
          receipt_row.release_result->>'source_tree_version'
        OR attempt.source_tree_version IS DISTINCT FROM
          snapshot.protected_report->'source_tree_context'->>'source_tree_version'
        OR attempt.source_content_fingerprint IS DISTINCT FROM
          receipt_row.release_result->>'source_content_fingerprint'
        OR attempt.source_content_fingerprint IS DISTINCT FROM
          snapshot.protected_report->'source_tree_context'->>
            'source_content_fingerprint'
        OR attempt.source_change_sequence IS DISTINCT FROM
          snapshot.source_change_sequence
        OR attempt.source_change_sequence::text IS DISTINCT FROM
          receipt_row.release_result->>'source_change_sequence'
        OR attempt.source_change_sequence IS DISTINCT FROM
          (SELECT source_change_sequence FROM fixture_0071_source_watermark)
        OR snapshot.source_change_sequence::text IS DISTINCT FROM
          snapshot.protected_report->>'source_change_sequence'
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
    OR (SELECT count(*) FROM app_private.management_report_release_request_claims
        WHERE release_request_id IN (
          '71d90000-0000-4000-8000-000000000001',
          '71d90000-0000-4000-8000-000000000002'
        ) AND release_family_id =
          'original_region_management_report_snapshot_release') <> 2
  THEN
    RAISE EXCEPTION '0071 original-region replacement baseline drift';
  END IF;
END
$legacy$;

CREATE TEMP TABLE fixture_0071_history_bytes (
  entity_kind text NOT NULL,
  entity_id uuid NOT NULL,
  entity_bytes jsonb NOT NULL,
  PRIMARY KEY (entity_kind, entity_id)
);
INSERT INTO fixture_0071_history_bytes
SELECT 'snapshot', snapshot_id, to_jsonb(snapshot.*)
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot_id IN (
  SELECT (release_result->>'released_snapshot_id')::uuid
  FROM fixture_0071_release_receipts
)
UNION ALL
SELECT 'attempt', release_request_id, to_jsonb(attempt.*)
FROM app_private.management_original_region_report_release_attempts AS attempt
WHERE release_request_id IN (
  '71d90000-0000-4000-8000-000000000001',
  '71d90000-0000-4000-8000-000000000002'
)
UNION ALL
SELECT 'claim', release_request_id, to_jsonb(claim.*)
FROM app_private.management_report_release_request_claims AS claim
WHERE release_request_id IN (
  '71d90000-0000-4000-8000-000000000001',
  '71d90000-0000-4000-8000-000000000002'
);

DO $saved_history$
BEGIN
  IF (SELECT count(*) FROM fixture_0071_history_bytes) <> 6
    OR EXISTS (
      SELECT 1
      FROM fixture_0071_history_bytes AS saved
      LEFT JOIN LATERAL (
        SELECT to_jsonb(snapshot.*) AS current_bytes
        FROM app_private.management_report_snapshots AS snapshot
        WHERE saved.entity_kind = 'snapshot'
          AND snapshot.snapshot_id = saved.entity_id
        UNION ALL
        SELECT to_jsonb(attempt.*)
        FROM app_private.management_original_region_report_release_attempts
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
    RAISE EXCEPTION '0071 original-region replacement history snapshot drift';
  END IF;
END
$saved_history$;

COMMIT;

SELECT release_result::text
FROM fixture_0071_release_receipts
ORDER BY release_order;
