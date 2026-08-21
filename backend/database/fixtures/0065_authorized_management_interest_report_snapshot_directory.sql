-- Synthetic fixture for the 6BA runtime interest snapshot bridge.
--
-- This fixture is independent of the 0063 fixture. It creates an approved
-- baseline, 20 approved rolling snapshots, negative provenance cases, and
-- external identities for the runtime bridge. Every row is rolled back.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b110000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b110000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  (
    '6b1e0000-0000-4000-8000-000000000001'::uuid,
    'https://directory-interest.synthetic/auth/v1',
    'active-reader',
    '6b110000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b1e0000-0000-4000-8000-000000000002'::uuid,
    ' https://directory-interest.synthetic/auth/v1 ',
    'spaced-reader',
    '6b110000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b1e0000-0000-4000-8000-000000000003'::uuid,
    'https://directory-interest.synthetic/auth/v1',
    'release-only-reader',
    '6b110000-0000-4000-8000-000000000001'::uuid
  ),
  (
    '6b1e0000-0000-4000-8000-000000000004'::uuid,
    'https://directory-interest.synthetic/auth/v1',
    'inactive-reader',
    '6b110000-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
)
VALUES (
  '6b120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BA runtime interest workspace',
  NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6b130000-0000-4000-8000-000000000001'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6BA runtime interest project'
  ),
  (
    '6b130000-0000-4000-8000-000000000002'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6BA other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES
  (
    '6b140000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    '6b140000-0000-4000-8000-000000000002'::uuid,
    '6b130000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6b160000-0000-4000-8000-000000000001'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b160000-0000-4000-8000-000000000002'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b160000-0000-4000-8000-000000000003'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b160000-0000-4000-8000-000000000004'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000004'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6b170000-0000-4000-8000-000000000001'::uuid,
    '6b160000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b170000-0000-4000-8000-000000000002'::uuid,
    '6b160000-0000-4000-8000-000000000002'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b170000-0000-4000-8000-000000000003'::uuid,
    '6b160000-0000-4000-8000-000000000002'::uuid,
    '6b130000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b170000-0000-4000-8000-000000000004'::uuid,
    '6b160000-0000-4000-8000-000000000003'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b170000-0000-4000-8000-000000000005'::uuid,
    '6b160000-0000-4000-8000-000000000004'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6b180000-0000-4000-8000-000000000001'::uuid,
    '6b170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b180000-0000-4000-8000-000000000002'::uuid,
    '6b170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b180000-0000-4000-8000-000000000003'::uuid,
    '6b170000-0000-4000-8000-000000000003'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b180000-0000-4000-8000-000000000004'::uuid,
    '6b170000-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b180000-0000-4000-8000-000000000005'::uuid,
    '6b170000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  );

-- Project 2 receives a valid interest snapshot later so the project-scope
-- exclusion is exercised against real 0062 provenance. Project 3 remains an
-- authorized empty project for the separate empty-directory assertion.
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES (
  '6b130000-0000-4000-8000-000000000003'::uuid,
  '6b120000-0000-4000-8000-000000000001'::uuid,
  '6BA empty project'
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES (
  '6b140000-0000-4000-8000-000000000003'::uuid,
  '6b130000-0000-4000-8000-000000000003'::uuid,
  1, 'published', true
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '6b170000-0000-4000-8000-000000000006'::uuid,
  '6b160000-0000-4000-8000-000000000002'::uuid,
  '6b130000-0000-4000-8000-000000000003'::uuid,
  clock_timestamp() - interval '30 days', NULL
);

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6b180000-0000-4000-8000-000000000006'::uuid,
    '6b170000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b180000-0000-4000-8000-000000000007'::uuid,
    '6b170000-0000-4000-8000-000000000006'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b150000-0000-4000-8000-000000000002'::uuid,
  '6b110000-0000-4000-8000-000000000002'::uuid,
  '6b130000-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6b110000-0000-4000-8000-000000000004'::uuid;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b150000-0000-4000-8000-000000000001'::uuid,
  '6b110000-0000-4000-8000-000000000001'::uuid,
  '6b130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6ba_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

CREATE TEMP TABLE fixture_6ba_interest_contacts AS
SELECT
  format(
    '6ba-interest-%s-%s-%s-%s',
    period_row.period_key,
    level_row,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  level_row AS interest_level,
  contributor_row.contributor_number,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 minute'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 minute'
  END AS occurred_at_utc
FROM fixture_6ba_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN generate_series(0, 4) AS level_row
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(1, contributor_row.unit_count)
  AS unit_row(unit_number);

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
  expected.contact_id,
  CASE expected.contributor_number
    WHEN 1 THEN '6b110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6b110000-0000-4000-8000-000000000002'::uuid
    ELSE '6b110000-0000-4000-8000-000000000003'::uuid
  END,
  '6b120000-0000-4000-8000-000000000001'::uuid,
  '6b130000-0000-4000-8000-000000000001'::uuid,
  '6b140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc,
  'UTC',
  expected.occurred_at_utc,
  'voice_call',
  'not_applicable',
  1,
  expected.interest_level
FROM fixture_6ba_interest_contacts AS expected;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
)
VALUES (
  '6b110000-0000-4000-8000-000000000001'::uuid,
  '6b120000-0000-4000-8000-000000000001'::uuid,
  '6b130000-0000-4000-8000-000000000001'::uuid,
  '6ba-runtime-watermark',
  1,
  'contact.submitted'
);

DO $fixture_6ba_release$
DECLARE
  baseline jsonb;
  rolling jsonb;
  release_number integer;
BEGIN
  baseline := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  );
  IF baseline->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR baseline->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION '6BA could not create the interest baseline: %', baseline;
  END IF;

  PERFORM pg_sleep(0.01);
  rolling := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000002'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  );
  IF rolling->>'result_status' IS DISTINCT FROM 'approved'
    OR rolling->>'released_snapshot_id' IS NULL
    OR rolling->>'compared_snapshot_id' IS DISTINCT FROM
      baseline->>'released_snapshot_id'
  THEN
    RAISE EXCEPTION '6BA could not create the approved rolling snapshot: %',
      rolling;
  END IF;
  FOR release_number IN 3..21 LOOP
    PERFORM pg_sleep(0.005);
    rolling := app_private.release_management_interest_report_snapshot_v1(
      ('6b800000-0000-4000-8000-' || lpad(release_number::text, 12, '0'))::uuid,
      '6b110000-0000-4000-8000-000000000001'::uuid,
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_interest_level_two_periods',
      1
    );
    IF rolling->>'result_status' IS DISTINCT FROM 'approved'
      OR rolling->>'released_snapshot_id' IS NULL
    THEN
      RAISE EXCEPTION '6BA could not create approved directory snapshot %: %',
        release_number, rolling;
    END IF;
  END LOOP;
END
$fixture_6ba_release$;

SELECT set_config(
  'app.fixture_6ba_baseline_snapshot_id',
  (
    SELECT released_snapshot_id::text
    FROM app_private.management_interest_report_release_attempts
    WHERE release_request_id = '6b800000-0000-4000-8000-000000000001'::uuid
  ),
  true
);

RESET ROLE;

-- A fully valid interest snapshot in another project exercises the explicit
-- project predicate. It must remain absent from project 1 even though its
-- 0062 attempt and claim are otherwise complete.
DO $fixture_6ba_cross_project$
DECLARE
  source_snapshot app_private.management_report_snapshots%ROWTYPE;
  project_snapshot_id uuid :=
    '6ba00000-0000-4000-8000-000000000030'::uuid;
  project_request_id uuid :=
    '6b800000-0000-4000-8000-000000000030'::uuid;
  project_id_value uuid :=
    '6b130000-0000-4000-8000-000000000002'::uuid;
  project_cutoff timestamp with time zone := date_trunc(
    'milliseconds',
    clock_timestamp()
  ) + interval '200 hours';
  project_document jsonb;
  result_document jsonb;
  time_zone_effective_from_utc_value timestamp with time zone;
BEGIN
  SELECT snapshot.*
  INTO STRICT source_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id =
    '6b800000-0000-4000-8000-000000000001'::uuid;

  project_document = jsonb_set(
    source_snapshot.protected_report,
    ARRAY['project_id'],
    to_jsonb(project_id_value::text),
    false
  );
  project_document = jsonb_set(
    project_document,
    ARRAY['periods'],
    app_private.resolve_management_report_periods_v1(
      source_snapshot.reporting_time_zone,
      project_cutoff
    ),
    false
  );
  PERFORM app_private.validate_management_interest_report_document_v1(
    project_document
  );

  SELECT version_row.effective_from_utc
  INTO STRICT time_zone_effective_from_utc_value
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = project_id_value
    AND version_row.version_number = 1;

  INSERT INTO app_private.management_report_snapshots (
    snapshot_id,
    release_request_id,
    created_by_app_user_id,
    project_id,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    reporting_time_zone,
    data_cutoff_utc,
    released_at_utc,
    previous_snapshot_id,
    source_change_sequence,
    protected_report
  ) VALUES (
    project_snapshot_id,
    project_request_id,
    '6b110000-0000-4000-8000-000000000002'::uuid,
    project_id_value,
    source_snapshot.release_lineage_id,
    source_snapshot.report_id,
    source_snapshot.report_version,
    source_snapshot.query_fingerprint,
    source_snapshot.reporting_time_zone,
    project_cutoff,
    project_cutoff,
    NULL,
    source_snapshot.source_change_sequence,
    project_document
  );

  result_document = jsonb_build_object(
    'release_contract_id',
      'interest_management_report_snapshot_release_v1',
    'release_request_id', project_request_id,
    'project_id', project_id_value,
    'release_lineage_id', source_snapshot.release_lineage_id,
    'report_id', source_snapshot.report_id,
    'report_version', source_snapshot.report_version,
    'query_fingerprint', source_snapshot.query_fingerprint,
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', source_snapshot.reporting_time_zone,
    'data_cutoff_utc', to_char(
      project_cutoff AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'source_change_sequence', source_snapshot.source_change_sequence,
    'compared_snapshot_id', NULL,
    'released_snapshot_id', project_snapshot_id,
    'shared_period_count', 0,
    'assessed_cell_count', 0,
    'result_status', 'approved_baseline',
    'reason_codes', '[]'::jsonb
  );

  INSERT INTO app_private.management_interest_report_release_attempts (
    release_request_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    reporting_time_zone_version_number,
    reporting_time_zone,
    reporting_time_zone_effective_from_utc,
    data_cutoff_utc,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    source_change_sequence,
    compared_snapshot_id,
    released_snapshot_id,
    shared_period_count,
    assessed_cell_count,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    project_request_id,
    '6b110000-0000-4000-8000-000000000002'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6b160000-0000-4000-8000-000000000002'::uuid,
    '6b170000-0000-4000-8000-000000000003'::uuid,
    '6b180000-0000-4000-8000-000000000006'::uuid,
    'release_management_reports',
    project_cutoff,
    project_id_value,
    1,
    source_snapshot.reporting_time_zone,
    time_zone_effective_from_utc_value,
    project_cutoff,
    source_snapshot.release_lineage_id,
    source_snapshot.report_id,
    source_snapshot.report_version,
    source_snapshot.query_fingerprint,
    source_snapshot.source_change_sequence,
    NULL,
    project_snapshot_id,
    0,
    0,
    'approved_baseline',
    '[]'::jsonb,
    result_document
  );
END
$fixture_6ba_cross_project$;

-- The normal 0062 write path rejects every tuple below before commit. The
-- directory still keeps its own closed join contract so a restored or
-- owner-repaired database cannot turn drifted provenance into a listing.
-- Replica mode is limited to this synthetic transaction and is reset even
-- when construction fails.
DO $fixture_6ba_drifted_provenance$
DECLARE
  base_snapshot app_private.management_report_snapshots%ROWTYPE;
  base_attempt
    app_private.management_interest_report_release_attempts%ROWTYPE;
  candidate_snapshot app_private.management_report_snapshots%ROWTYPE;
  candidate_attempt
    app_private.management_interest_report_release_attempts%ROWTYPE;
  case_number integer;
  case_name text;
  candidate_snapshot_id uuid;
  candidate_request_id uuid;
  candidate_cutoff timestamp with time zone;
BEGIN
  SELECT snapshot.*
  INTO STRICT base_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id =
    '6b800000-0000-4000-8000-000000000001'::uuid;

  SELECT attempt.*
  INTO STRICT base_attempt
  FROM app_private.management_interest_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b800000-0000-4000-8000-000000000001'::uuid;

  PERFORM set_config('session_replication_role', 'replica', true);

  FOR case_number, case_name IN
    SELECT case_row.case_number, case_row.case_name
    FROM (VALUES
      (101, 'claim_mismatch'),
      (102, 'channel_provenance'),
      (103, 'current_city_provenance'),
      (104, 'legacy_provenance'),
      (105, 'lineage_drift'),
      (106, 'time_zone_drift'),
      (107, 'cutoff_drift'),
      (108, 'previous_pointer_drift'),
      (109, 'source_watermark_drift'),
      (110, 'report_version_drift'),
      (111, 'query_fingerprint_drift')
    ) AS case_row(case_number, case_name)
  LOOP
    candidate_snapshot_id = (
      '6ba00000-0000-4000-8000-'
        || lpad(case_number::text, 12, '0')
    )::uuid;
    candidate_request_id = (
      '6bb00000-0000-4000-8000-'
        || lpad(case_number::text, 12, '0')
    )::uuid;
    candidate_cutoff = date_trunc(
      'milliseconds',
      clock_timestamp()
    ) + case_number * interval '1 hour';

    candidate_snapshot = base_snapshot;
    candidate_snapshot.snapshot_id = candidate_snapshot_id;
    candidate_snapshot.release_request_id = candidate_request_id;
    candidate_snapshot.data_cutoff_utc = candidate_cutoff;
    candidate_snapshot.released_at_utc = candidate_cutoff;
    candidate_snapshot.previous_snapshot_id = NULL;

    candidate_attempt = base_attempt;
    candidate_attempt.release_request_id = candidate_request_id;
    candidate_attempt.authorization_reference_at_utc = candidate_cutoff;
    candidate_attempt.data_cutoff_utc = candidate_cutoff;
    candidate_attempt.compared_snapshot_id = NULL;
    candidate_attempt.released_snapshot_id = candidate_snapshot_id;
    candidate_attempt.shared_period_count = 0;
    candidate_attempt.assessed_cell_count = 0;
    candidate_attempt.result_status = 'approved_baseline';
    candidate_attempt.reason_codes = '[]'::jsonb;

    CASE case_name
      WHEN 'channel_provenance' THEN
        candidate_snapshot.report_id =
          'contact_sessions_by_channel_two_periods';
        candidate_snapshot.release_lineage_id =
          'management-report:contact_sessions_by_channel_two_periods';
        candidate_snapshot.query_fingerprint =
          'management-report:contact_sessions_by_channel_two_periods:v1';
      WHEN 'current_city_provenance' THEN
        candidate_snapshot.report_id =
          'contact_sessions_by_current_city_two_periods';
        candidate_snapshot.release_lineage_id =
          'management-region-report:contact_sessions_by_current_city_two_periods';
        candidate_snapshot.query_fingerprint =
          'management-report:contact_sessions_by_current_city_two_periods:v1';
      WHEN 'legacy_provenance' THEN
        candidate_snapshot.release_lineage_id =
          'management-report:contact_sessions_by_interest_level_two_periods';
      WHEN 'lineage_drift' THEN
        candidate_snapshot.release_lineage_id =
          'management-interest-report:drifted-interest-lineage';
      WHEN 'time_zone_drift' THEN
        candidate_snapshot.reporting_time_zone = 'America/Chicago';
      WHEN 'cutoff_drift' THEN
        candidate_snapshot.data_cutoff_utc =
          candidate_snapshot.data_cutoff_utc + interval '1 second';
        candidate_snapshot.released_at_utc =
          candidate_snapshot.data_cutoff_utc;
      WHEN 'previous_pointer_drift' THEN
        candidate_snapshot.previous_snapshot_id = base_snapshot.snapshot_id;
      WHEN 'source_watermark_drift' THEN
        candidate_snapshot.source_change_sequence =
          candidate_snapshot.source_change_sequence + 1;
      WHEN 'report_version_drift' THEN
        candidate_snapshot.report_version = 2;
      WHEN 'query_fingerprint_drift' THEN
        candidate_snapshot.query_fingerprint =
          'management-report:contact_sessions_by_interest_level_two_periods:drift';
      ELSE
        NULL;
    END CASE;

    INSERT INTO app_private.management_report_snapshots (
      snapshot_id,
      release_request_id,
      created_by_app_user_id,
      project_id,
      release_lineage_id,
      report_id,
      report_version,
      query_fingerprint,
      reporting_time_zone,
      data_cutoff_utc,
      released_at_utc,
      previous_snapshot_id,
      source_change_sequence,
      protected_report
    ) VALUES (
      candidate_snapshot.snapshot_id,
      candidate_snapshot.release_request_id,
      candidate_snapshot.created_by_app_user_id,
      candidate_snapshot.project_id,
      candidate_snapshot.release_lineage_id,
      candidate_snapshot.report_id,
      candidate_snapshot.report_version,
      candidate_snapshot.query_fingerprint,
      candidate_snapshot.reporting_time_zone,
      candidate_snapshot.data_cutoff_utc,
      candidate_snapshot.released_at_utc,
      candidate_snapshot.previous_snapshot_id,
      candidate_snapshot.source_change_sequence,
      candidate_snapshot.protected_report
    );

    INSERT INTO app_private.management_report_release_request_claims (
      release_request_id,
      release_family_id
    ) VALUES (
      candidate_request_id,
      CASE case_name
        WHEN 'claim_mismatch' THEN
          'channel_management_report_snapshot_release'
        ELSE 'interest_management_report_snapshot_release'
      END
    );

    INSERT INTO app_private.management_interest_report_release_attempts (
      release_request_id,
      requested_by_app_user_id,
      organization_workspace_id,
      organization_membership_id,
      project_membership_id,
      capability_grant_id,
      capability_id,
      authorization_reference_at_utc,
      project_id,
      reporting_time_zone_version_number,
      reporting_time_zone,
      reporting_time_zone_effective_from_utc,
      data_cutoff_utc,
      release_lineage_id,
      report_id,
      report_version,
      query_fingerprint,
      source_change_sequence,
      compared_snapshot_id,
      released_snapshot_id,
      shared_period_count,
      assessed_cell_count,
      result_status,
      reason_codes,
      result_document
    ) VALUES (
      candidate_attempt.release_request_id,
      candidate_attempt.requested_by_app_user_id,
      candidate_attempt.organization_workspace_id,
      candidate_attempt.organization_membership_id,
      candidate_attempt.project_membership_id,
      candidate_attempt.capability_grant_id,
      candidate_attempt.capability_id,
      candidate_attempt.authorization_reference_at_utc,
      candidate_attempt.project_id,
      candidate_attempt.reporting_time_zone_version_number,
      candidate_attempt.reporting_time_zone,
      candidate_attempt.reporting_time_zone_effective_from_utc,
      candidate_attempt.data_cutoff_utc,
      candidate_attempt.release_lineage_id,
      candidate_attempt.report_id,
      candidate_attempt.report_version,
      candidate_attempt.query_fingerprint,
      candidate_attempt.source_change_sequence,
      candidate_attempt.compared_snapshot_id,
      candidate_attempt.released_snapshot_id,
      candidate_attempt.shared_period_count,
      candidate_attempt.assessed_cell_count,
      candidate_attempt.result_status,
      candidate_attempt.reason_codes,
      candidate_attempt.result_document
    );
  END LOOP;

  PERFORM set_config('session_replication_role', 'origin', true);

  IF (
    SELECT count(*)
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id::text LIKE
      '6ba00000-0000-4000-8000-0000000001%'
  ) <> 11 OR (
    SELECT count(*)
    FROM app_private.management_interest_report_release_attempts AS attempt
    WHERE attempt.release_request_id::text LIKE
      '6bb00000-0000-4000-8000-0000000001%'
  ) <> 11 OR (
    SELECT count(*)
    FROM app_private.management_report_release_request_claims AS claim
    WHERE claim.release_request_id::text LIKE
      '6bb00000-0000-4000-8000-0000000001%'
  ) <> 11 THEN
    RAISE EXCEPTION '6BA drifted provenance cases were not constructed';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    PERFORM set_config('session_replication_role', 'origin', true);
    RAISE;
END
$fixture_6ba_drifted_provenance$;

-- A protected interest document without a matching 0062 attempt and claim is
-- deliberately not a directory entry, even though its shape is valid.
DO $fixture_6ba_untrusted$
DECLARE
  trusted_snapshot app_private.management_report_snapshots%ROWTYPE;
BEGIN
  SELECT snapshot.*
  INTO STRICT trusted_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id =
    '6b800000-0000-4000-8000-000000000001'::uuid;

  INSERT INTO app_private.management_report_snapshots (
    snapshot_id,
    release_request_id,
    created_by_app_user_id,
    project_id,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    reporting_time_zone,
    data_cutoff_utc,
    released_at_utc,
    previous_snapshot_id,
    source_change_sequence,
    protected_report
  ) VALUES (
    '6ba00000-0000-4000-8000-000000000099'::uuid,
    '6bb00000-0000-4000-8000-000000000099'::uuid,
    trusted_snapshot.created_by_app_user_id,
    trusted_snapshot.project_id,
    trusted_snapshot.release_lineage_id,
    trusted_snapshot.report_id,
    trusted_snapshot.report_version,
    trusted_snapshot.query_fingerprint,
    trusted_snapshot.reporting_time_zone,
    trusted_snapshot.data_cutoff_utc,
    trusted_snapshot.released_at_utc,
    trusted_snapshot.previous_snapshot_id,
    trusted_snapshot.source_change_sequence,
    trusted_snapshot.protected_report
  );
END
$fixture_6ba_untrusted$;

-- This blocked interest attempt has a valid release-family claim but no
-- released snapshot.  It must not be made visible by a directory join.
INSERT INTO app_private.management_interest_report_release_attempts (
  release_request_id,
  requested_by_app_user_id,
  organization_workspace_id,
  organization_membership_id,
  project_membership_id,
  capability_grant_id,
  capability_id,
  authorization_reference_at_utc,
  project_id,
  reporting_time_zone_version_number,
  reporting_time_zone,
  reporting_time_zone_effective_from_utc,
  data_cutoff_utc,
  release_lineage_id,
  report_id,
  report_version,
  query_fingerprint,
  source_change_sequence,
  compared_snapshot_id,
  released_snapshot_id,
  shared_period_count,
  assessed_cell_count,
  result_status,
  reason_codes,
  result_document
)
SELECT
  '6b800000-0000-4000-8000-000000000022'::uuid,
  attempt.requested_by_app_user_id,
  attempt.organization_workspace_id,
  attempt.organization_membership_id,
  attempt.project_membership_id,
  attempt.capability_grant_id,
  attempt.capability_id,
  attempt.authorization_reference_at_utc,
  attempt.project_id,
  attempt.reporting_time_zone_version_number,
  attempt.reporting_time_zone,
  attempt.reporting_time_zone_effective_from_utc,
  attempt.data_cutoff_utc,
  attempt.release_lineage_id,
  attempt.report_id,
  attempt.report_version,
  attempt.query_fingerprint,
  attempt.source_change_sequence,
  attempt.compared_snapshot_id,
  NULL::uuid,
  attempt.shared_period_count,
  attempt.assessed_cell_count,
  'blocked',
  '["release_time_zone_revision_changed"]'::jsonb,
  attempt.result_document || jsonb_build_object(
    'release_request_id',
      '6b800000-0000-4000-8000-000000000022'::uuid,
    'released_snapshot_id', NULL::uuid,
    'result_status', 'blocked',
    'reason_codes', '["release_time_zone_revision_changed"]'::jsonb
  )
FROM app_private.management_interest_report_release_attempts AS attempt
WHERE attempt.release_request_id =
  '6b800000-0000-4000-8000-000000000002'::uuid;

CREATE TEMP TABLE fixture_6ba_counts AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_users,
  (SELECT count(*) FROM app_data.workspaces) AS workspaces,
  (SELECT count(*) FROM app_data.projects) AS projects;

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6ba_runtime$
DECLARE
  active_read jsonb;
  exact_spaced_read jsonb;
  empty_read jsonb;
  snapshot_entry jsonb;
  previous_cutoff timestamp with time zone;
  previous_released_at timestamp with time zone;
  previous_snapshot_id uuid;
  current_cutoff timestamp with time zone;
  current_released_at timestamp with time zone;
  current_snapshot_id uuid;
BEGIN
  active_read := app_data.list_authorized_management_interest_report_snapshots_v1(
    'https://directory-interest.synthetic/auth/v1',
    'active-reader',
    '6b130000-0000-4000-8000-000000000001'::uuid
  );

  IF (
    SELECT count(*)
    FROM jsonb_object_keys(active_read) AS object_key(key)
    WHERE key NOT IN (
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    )
  ) <> 0
    OR (
      SELECT count(*) FROM jsonb_object_keys(active_read)
    ) <> 4
    OR active_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_interest_management_report_snapshot_directory_v1'
    OR active_read->>'project_id' IS DISTINCT FROM
      '6b130000-0000-4000-8000-000000000001'
    OR jsonb_array_length(active_read->'snapshots') <> 20
    OR active_read::text ~* '(protected_report|source_change_sequence|cells|value_count|privacy_status|contributor|contact_id|organization_membership|capability_grant|app_user_id)'
  THEN
    RAISE EXCEPTION '6BA active directory envelope is invalid: %', active_read;
  END IF;

  FOR snapshot_entry IN
    SELECT value FROM jsonb_array_elements(active_read->'snapshots')
  LOOP
    IF (
      SELECT count(*)
      FROM jsonb_object_keys(snapshot_entry) AS object_key(key)
      WHERE key NOT IN (
        'data_cutoff_utc', 'released_at_utc', 'report_id', 'report_version',
        'reporting_time_zone', 'snapshot_id'
      )
    ) <> 0
      OR (
        SELECT count(*) FROM jsonb_object_keys(snapshot_entry)
      ) <> 6
      OR snapshot_entry->>'report_id' IS DISTINCT FROM
        'contact_sessions_by_interest_level_two_periods'
      OR snapshot_entry->>'report_version' IS DISTINCT FROM '1'
      OR snapshot_entry->>'reporting_time_zone' IS DISTINCT FROM 'UTC'
      OR snapshot_entry::text ~* '(protected_report|source_change_sequence|cells|value_count|privacy_status|contributor|contact_id|organization_membership|capability_grant|app_user_id)'
    THEN
      RAISE EXCEPTION '6BA directory item is not metadata-only: %',
        snapshot_entry;
    END IF;

    current_cutoff = (snapshot_entry->>'data_cutoff_utc')::timestamptz;
    current_released_at = (snapshot_entry->>'released_at_utc')::timestamptz;
    current_snapshot_id = (snapshot_entry->>'snapshot_id')::uuid;
    IF previous_cutoff IS NOT NULL
      AND (current_cutoff, current_released_at, current_snapshot_id) >=
        (previous_cutoff, previous_released_at, previous_snapshot_id)
    THEN
      RAISE EXCEPTION '6BA directory order is not strictly descending';
    END IF;
    previous_cutoff = current_cutoff;
    previous_released_at = current_released_at;
    previous_snapshot_id = current_snapshot_id;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(active_read->'snapshots') AS item
    WHERE item->>'snapshot_id' IN (
      current_setting('app.fixture_6ba_baseline_snapshot_id'),
      '6ba00000-0000-4000-8000-000000000030',
      '6ba00000-0000-4000-8000-000000000099'
    )
      OR item->>'snapshot_id' LIKE
        '6ba00000-0000-4000-8000-0000000001%'
  ) THEN
    RAISE EXCEPTION
      '6BA directory returned an old, cross-project, or drifted snapshot';
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_interest_report_snapshots_v1(
      'https://directory-interest.synthetic/auth/v1',
      'spaced-reader',
      '6b130000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BA runtime bridge trimmed an issuer';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  exact_spaced_read :=
    app_data.list_authorized_management_interest_report_snapshots_v1(
      ' https://directory-interest.synthetic/auth/v1 ',
      'spaced-reader',
      '6b130000-0000-4000-8000-000000000001'::uuid
    );
  IF exact_spaced_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_interest_management_report_snapshot_directory_v1'
    OR jsonb_array_length(exact_spaced_read->'snapshots') <> 20
  THEN
    RAISE EXCEPTION '6BA exact spaced identity did not resolve';
  END IF;

  empty_read := app_data.list_authorized_management_interest_report_snapshots_v1(
    'https://directory-interest.synthetic/auth/v1',
    'active-reader',
    '6b130000-0000-4000-8000-000000000003'::uuid
  );
  IF empty_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_interest_management_report_snapshot_directory_v1'
    OR jsonb_array_length(empty_read->'snapshots') <> 0
  THEN
    RAISE EXCEPTION '6BA empty project directory is invalid: %', empty_read;
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_interest_report_snapshots_v1(
      'https://directory-interest.synthetic/auth/v1',
      'release-only-reader',
      '6b130000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BA runtime bridge accepted release-only access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_interest_report_snapshots_v1(
      'https://directory-interest.synthetic/auth/v1',
      'inactive-reader',
      '6b130000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BA runtime bridge accepted inactive access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_interest_report_snapshots_v1(
      'https://directory-interest.synthetic/auth/v1',
      'unknown-reader',
      '6b130000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BA runtime bridge accepted unknown access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.list_authorized_management_interest_report_snapshots_v1(
      '6b110000-0000-4000-8000-000000000002'::uuid,
      '6b130000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BA runtime role received direct app_private access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture_6ba_runtime$;

RESET ROLE;

DO $fixture_6ba_audit$
DECLARE
  expected_counts record;
  actual_counts record;
  history_text text;
  audit_event_id_value uuid;
BEGIN
  SELECT * INTO STRICT expected_counts FROM fixture_6ba_counts;
  SELECT
    (SELECT count(*) FROM app_data.app_users) AS app_users,
    (SELECT count(*) FROM app_data.workspaces) AS workspaces,
    (SELECT count(*) FROM app_data.projects) AS projects
  INTO STRICT actual_counts;
  IF actual_counts.app_users IS DISTINCT FROM expected_counts.app_users
    OR actual_counts.workspaces IS DISTINCT FROM expected_counts.workspaces
    OR actual_counts.projects IS DISTINCT FROM expected_counts.projects
  THEN
    RAISE EXCEPTION '6BA unknown identity bootstrapped application rows';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_directory_access_events
    WHERE requested_by_app_user_id =
      '6b110000-0000-4000-8000-000000000002'::uuid
  ) <> 3
  OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_directory_access_events
    WHERE requested_by_app_user_id =
      '6b110000-0000-4000-8000-000000000002'::uuid
      AND returned_snapshot_count = 20
      AND result_status = 'completed'
  ) <> 2
  OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_directory_access_events
    WHERE requested_by_app_user_id =
      '6b110000-0000-4000-8000-000000000002'::uuid
      AND project_id = '6b130000-0000-4000-8000-000000000003'::uuid
      AND returned_snapshot_count = 0
      AND result_status = 'completed'
  ) <> 1
  THEN
    RAISE EXCEPTION '6BA directory audit status counts are incorrect';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_interest_report_snapshot_directory_access_events AS event
  WHERE event.requested_by_app_user_id IN (
    '6b110000-0000-4000-8000-000000000002'::uuid,
    '6b110000-0000-4000-8000-000000000003'::uuid
  );
  IF history_text ~* '(protected_report|report_id|snapshot_id|source_change_sequence|cell|value_count|privacy_status|contributor|contact_id|pii)'
  THEN
    RAISE EXCEPTION '6BA directory audit retained protected values';
  END IF;

  SELECT access_event_id
  INTO STRICT audit_event_id_value
  FROM app_private.management_interest_report_snapshot_directory_access_events
  LIMIT 1;
  BEGIN
    UPDATE app_private.management_interest_report_snapshot_directory_access_events
    SET result_status = 'completed'
    WHERE access_event_id = audit_event_id_value;
    RAISE EXCEPTION '6BA directory audit was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_interest_report_snapshot_directory_access_events
    WHERE access_event_id = audit_event_id_value;
    RAISE EXCEPTION '6BA directory audit was deletable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END
$fixture_6ba_audit$;

ROLLBACK;
