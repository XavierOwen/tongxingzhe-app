-- Synthetic fixture for the private 6AX interest snapshot read contract.
--
-- This fixture is self-contained.  The 0062 fixture is rolled back in its own
-- psql process, so this file recreates the authorized project, releases one
-- interest snapshots, and creates channel/current-city, legacy, blocked,
-- wrong-claim and drifted rows for fail-closed checks. Every row is rolled
-- back at the end.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6c110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6c110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6c110000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6c110000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('6c110000-0000-4000-8000-000000000005'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
) VALUES (
  '6c120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AX authorized interest snapshot workspace',
  NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6c130000-0000-4000-8000-000000000001'::uuid,
    '6c120000-0000-4000-8000-000000000001'::uuid,
    '6AX interest snapshot project'
  ),
  (
    '6c130000-0000-4000-8000-000000000002'::uuid,
    '6c120000-0000-4000-8000-000000000001'::uuid,
    '6AX other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES
  (
    '6c140000-0000-4000-8000-000000000001'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    '6c140000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6c160000-0000-4000-8000-000000000001'::uuid,
    '6c120000-0000-4000-8000-000000000001'::uuid,
    '6c110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c160000-0000-4000-8000-000000000002'::uuid,
    '6c120000-0000-4000-8000-000000000001'::uuid,
    '6c110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c160000-0000-4000-8000-000000000003'::uuid,
    '6c120000-0000-4000-8000-000000000001'::uuid,
    '6c110000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c160000-0000-4000-8000-000000000004'::uuid,
    '6c120000-0000-4000-8000-000000000001'::uuid,
    '6c110000-0000-4000-8000-000000000004'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6c170000-0000-4000-8000-000000000001'::uuid,
    '6c160000-0000-4000-8000-000000000001'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c170000-0000-4000-8000-000000000002'::uuid,
    '6c160000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c170000-0000-4000-8000-000000000003'::uuid,
    '6c160000-0000-4000-8000-000000000003'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c170000-0000-4000-8000-000000000004'::uuid,
    '6c160000-0000-4000-8000-000000000004'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c170000-0000-4000-8000-000000000005'::uuid,
    '6c160000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6c180000-0000-4000-8000-000000000001'::uuid,
    '6c170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c180000-0000-4000-8000-000000000002'::uuid,
    '6c170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c180000-0000-4000-8000-000000000003'::uuid,
    '6c170000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6c180000-0000-4000-8000-000000000004'::uuid,
    '6c170000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days',
    clock_timestamp() - interval '1 day'
  ),
  (
    '6c180000-0000-4000-8000-000000000005'::uuid,
    '6c170000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6c150000-0000-4000-8000-000000000001'::uuid,
  '6c110000-0000-4000-8000-000000000001'::uuid,
  '6c130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6ax_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

-- Ten sessions per period and interest level, distributed 5/3/2 across three
-- active contributors, except current level 4 has nine.  That one unsafe cell
-- closes the whole current period, so the stored document exercises both
-- displayed counts and suppressed JSON nulls.
CREATE TEMP TABLE fixture_6ax_interest_contacts AS
SELECT
  format(
    '6ax-interest-%s-%s-%s-%s',
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
FROM fixture_6ax_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN generate_series(0, 4) AS level_row
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(
  1,
  CASE
    WHEN period_row.period_key = 'current'
      AND level_row = 4
      AND contributor_row.contributor_number = 1
      THEN contributor_row.unit_count - 1
    ELSE contributor_row.unit_count
  END
)
  AS unit_row(unit_number);

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, reach_count, interest_level
)
SELECT
  expected.contact_id,
  CASE expected.contributor_number
    WHEN 1 THEN '6c110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6c110000-0000-4000-8000-000000000002'::uuid
    ELSE '6c110000-0000-4000-8000-000000000003'::uuid
  END,
  '6c120000-0000-4000-8000-000000000001'::uuid,
  '6c130000-0000-4000-8000-000000000001'::uuid,
  '6c140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc, 'UTC', expected.occurred_at_utc,
  'voice_call', 'not_applicable', 1, expected.interest_level
FROM fixture_6ax_interest_contacts AS expected;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
) VALUES (
  '6c110000-0000-4000-8000-000000000001'::uuid,
  '6c120000-0000-4000-8000-000000000001'::uuid,
  '6c130000-0000-4000-8000-000000000001'::uuid,
  '6ax-interest-watermark', 1, 'contact.submitted'
);

DO $fixture_6ax_setup$
DECLARE
  interest_release jsonb;
  rolling_release jsonb;
  interest_document jsonb;
BEGIN
  interest_release := app_private.release_management_interest_report_snapshot_v1(
    '6c800000-0000-4000-8000-000000000001'::uuid,
    '6c110000-0000-4000-8000-000000000001'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF interest_release->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR interest_release->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION '6AX could not create the interest baseline: %',
      interest_release;
  END IF;

  interest_document := app_private.execute_management_interest_distribution_report_v1(
    '6c130000-0000-4000-8000-000000000001'::uuid,
    'UTC',
    (SELECT data_cutoff_utc FROM fixture_6ax_report_context)
  );
  IF jsonb_array_length(interest_document->'cells') <> 10 THEN
    RAISE EXCEPTION '6AX setup did not retain the ten-cell interest document';
  END IF;

  PERFORM pg_sleep(0.01);
  rolling_release := app_private.release_management_interest_report_snapshot_v1(
    '6c800000-0000-4000-8000-000000000002'::uuid,
    '6c110000-0000-4000-8000-000000000001'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF rolling_release->>'result_status' IS DISTINCT FROM 'approved'
    OR rolling_release->>'released_snapshot_id' IS NULL
    OR rolling_release->>'compared_snapshot_id'
      IS DISTINCT FROM interest_release->>'released_snapshot_id'
  THEN
    RAISE EXCEPTION '6AX could not create the approved rolling snapshot: %',
      rolling_release;
  END IF;
END
$fixture_6ax_setup$;

-- Create a valid current-city release after the interest baseline so the
-- interest report itself still has exactly ten cells.  This row is used only
-- to prove that the 6AX reader does not trust another report family.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('fixture-6ax-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6ax-country', 'fixture-6ax-target-v1', NULL,
    '6AX Country', 'country'),
  ('fixture-6ax-city-a', 'fixture-6ax-target-v1', 'fixture-6ax-country',
    '6AX City A', 'city'),
  ('fixture-6ax-city-b', 'fixture-6ax-target-v1', 'fixture-6ax-country',
    '6AX City B', 'city'),
  ('fixture-6ax-city-c', 'fixture-6ax-target-v1', 'fixture-6ax-country',
    '6AX City C', 'city'),
  ('fixture-6ax-venue-a', 'fixture-6ax-target-v1', 'fixture-6ax-city-a',
    '6AX Venue A', 'venue'),
  ('fixture-6ax-venue-b', 'fixture-6ax-target-v1', 'fixture-6ax-city-b',
    '6AX Venue B', 'venue'),
  ('fixture-6ax-venue-c', 'fixture-6ax-target-v1', 'fixture-6ax-city-c',
    '6AX Venue C', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES
  ('fixture-6ax-boundary-a', 'fixture-6ax-venue-a', 'fixture-6ax-target-v1',
    polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'),
  ('fixture-6ax-boundary-b', 'fixture-6ax-venue-b', 'fixture-6ax-target-v1',
    polygon '((-87.61,41.69),(-87.59,41.69),(-87.59,41.71),(-87.61,41.71))'),
  ('fixture-6ax-boundary-c', 'fixture-6ax-venue-c', 'fixture-6ax-target-v1',
    polygon '((-87.41,41.69),(-87.39,41.69),(-87.39,41.71),(-87.41,41.71))');

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6ax-target-v1', true
);

CREATE TEMP TABLE fixture_6ax_city_contacts AS
SELECT
  format(
    '6ax-city-%s-%s-u%s-%s',
    period_row.period_key,
    city_row.city_key,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  city_row.city_key,
  contributor_row.contributor_number,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 day'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 day'
  END AS occurred_at_utc
FROM fixture_6ax_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES ('a'), ('b'), ('c')) AS city_row(city_key)
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(
  1,
  CASE
    WHEN city_row.city_key = 'c' THEN
      CASE contributor_row.contributor_number
        WHEN 1 THEN 4
        WHEN 2 THEN 3
        ELSE 2
      END
    ELSE contributor_row.unit_count
  END
) AS unit_row(unit_number);

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, place_name,
  smallest_region_id, region_tree_version, reach_count, interest_level
)
SELECT
  expected.contact_id,
  CASE expected.contributor_number
    WHEN 1 THEN '6c110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6c110000-0000-4000-8000-000000000002'::uuid
    ELSE '6c110000-0000-4000-8000-000000000003'::uuid
  END,
  '6c120000-0000-4000-8000-000000000001'::uuid,
  '6c130000-0000-4000-8000-000000000001'::uuid,
  '6c140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc, 'UTC', expected.occurred_at_utc,
  'face_to_face', 'resolved', '6AX synthetic venue',
  format('fixture-6ax-venue-%s', expected.city_key),
  'fixture-6ax-target-v1', 1, 2
FROM fixture_6ax_city_contacts AS expected;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
)
SELECT
  expected.contact_id,
  1,
  'submitted',
  CASE expected.contributor_number
    WHEN 1 THEN '6c110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6c110000-0000-4000-8000-000000000002'::uuid
    ELSE '6c110000-0000-4000-8000-000000000003'::uuid
  END,
  jsonb_build_object(
    'contactId', expected.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', '6AX synthetic venue',
      'smallestRegionId', format('fixture-6ax-venue-%s', expected.city_key),
      'regionTreeVersion', 'fixture-6ax-target-v1'
    )
  )
FROM fixture_6ax_city_contacts AS expected;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
) VALUES (
  '6c110000-0000-4000-8000-000000000001'::uuid,
  '6c120000-0000-4000-8000-000000000001'::uuid,
  '6c130000-0000-4000-8000-000000000001'::uuid,
  '6ax-current-city-watermark', 1, 'contact.submitted'
);

-- The current-city executor requires location provenance for every active
-- candidate contact.  The interest-only contacts already belong to the
-- immutable 6AW baseline; retire them from the later cross-family release so
-- the current-city setup observes only the resolved city contacts below.
UPDATE app_data.contacts
SET lifecycle_status = 'voided'
WHERE contact_id LIKE '6ax-interest-%';

DO $fixture_6ax_reads$
DECLARE
  interest_snapshot_id uuid;
  approved_snapshot_id uuid;
  channel_snapshot_id uuid;
  current_city_snapshot_id uuid;
  legacy_snapshot_id uuid :=
    '6ca00000-0000-4000-8000-000000000001'::uuid;
  blocked_snapshot_id uuid :=
    '6ca00000-0000-4000-8000-000000000003'::uuid;
  wrong_claim_snapshot_id uuid :=
    '6ca00000-0000-4000-8000-000000000005'::uuid;
  drifted_snapshot_id uuid :=
    '6ca00000-0000-4000-8000-000000000007'::uuid;
  channel_release jsonb;
  current_city_release jsonb;
  baseline_document jsonb;
  approved_document jsonb;
  trusted_attempt
    app_private.management_interest_report_release_attempts%ROWTYPE;
  first_read jsonb;
  second_read jsonb;
  approved_read jsonb;
  unknown_read jsonb;
  cross_project_read jsonb;
  channel_read jsonb;
  current_city_read jsonb;
  legacy_read jsonb;
  blocked_read jsonb;
  wrong_claim_read jsonb;
  drifted_read jsonb;
  audit_row app_private.management_interest_report_snapshot_access_events%ROWTYPE;
  audit_count bigint;
  history_text text;
BEGIN
  SELECT attempt.released_snapshot_id
  INTO STRICT interest_snapshot_id
  FROM app_private.management_interest_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6c800000-0000-4000-8000-000000000001'::uuid;

  SELECT snapshot.protected_report
  INTO STRICT baseline_document
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = interest_snapshot_id;

  SELECT attempt.*
  INTO STRICT trusted_attempt
  FROM app_private.management_interest_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6c800000-0000-4000-8000-000000000001'::uuid;

  IF jsonb_array_length(baseline_document->'cells') <> 10
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(baseline_document->'cells') AS element(cell)
      WHERE cell->>'period_key' = 'current'
        AND cell->>'privacy_status' = 'suppressed'
        AND cell->'value_count' = 'null'::jsonb
    ) <> 5
  THEN
    RAISE EXCEPTION
      '6AX interest snapshot setup did not retain ten cells and null suppression';
  END IF;

  SELECT attempt.released_snapshot_id
  INTO STRICT approved_snapshot_id
  FROM app_private.management_interest_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6c800000-0000-4000-8000-000000000002'::uuid
    AND attempt.result_status = 'approved';

  SELECT snapshot.protected_report
  INTO STRICT approved_document
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = approved_snapshot_id;

  -- A channel snapshot is valid for its own reader, but it is not interest
  -- provenance.  Use a cutoff after the interest release so generic v1 can
  -- observe the complete channel source set.
  channel_release := app_private.release_management_report_snapshot_v1(
    '6c800000-0000-4000-8000-000000000003'::uuid,
    '6c110000-0000-4000-8000-000000000001'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    (baseline_document->'periods'->>'data_cutoff_utc')::timestamptz
      + interval '1 second',
    (baseline_document->'periods'->>'data_cutoff_utc')::timestamptz
      + interval '1 second'
  );
  SELECT attempt.released_snapshot_id
  INTO STRICT channel_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6c800000-0000-4000-8000-000000000003'::uuid;

  current_city_release :=
    app_private.release_management_current_city_report_snapshot_v1(
      '6c800000-0000-4000-8000-000000000004'::uuid,
      '6c110000-0000-4000-8000-000000000001'::uuid,
      '6c130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_current_city_two_periods', 1
    );
  IF current_city_release->>'released_snapshot_id' IS NULL THEN
    RAISE EXCEPTION '6AX current-city cross-family setup failed: %',
      current_city_release;
  END IF;
  current_city_snapshot_id :=
    (current_city_release->>'released_snapshot_id')::uuid;

  -- A legacy interest-shaped snapshot has no claim or 0062 attempt. Shape
  -- alone must never become trusted provenance.
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
  ) SELECT
    legacy_snapshot_id,
    '6ca00000-0000-4000-8000-000000000002'::uuid,
    snapshot.created_by_app_user_id,
    snapshot.project_id,
    snapshot.release_lineage_id,
    snapshot.report_id,
    snapshot.report_version,
    snapshot.query_fingerprint,
    snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc,
    snapshot.released_at_utc,
    snapshot.previous_snapshot_id,
    snapshot.source_change_sequence,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = interest_snapshot_id;

  -- A blocked 0062 attempt has no released snapshot by contract. A trusted
  -- actor must not make another snapshot readable merely by reusing that
  -- blocked request UUID.
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
    '6ca00000-0000-4000-8000-000000000004'::uuid,
    trusted_attempt.requested_by_app_user_id,
    trusted_attempt.organization_workspace_id,
    trusted_attempt.organization_membership_id,
    trusted_attempt.project_membership_id,
    trusted_attempt.capability_grant_id,
    trusted_attempt.capability_id,
    trusted_attempt.authorization_reference_at_utc,
    trusted_attempt.project_id,
    trusted_attempt.reporting_time_zone_version_number,
    trusted_attempt.reporting_time_zone,
    trusted_attempt.reporting_time_zone_effective_from_utc,
    trusted_attempt.data_cutoff_utc,
    trusted_attempt.release_lineage_id,
    trusted_attempt.report_id,
    trusted_attempt.report_version,
    trusted_attempt.query_fingerprint,
    trusted_attempt.source_change_sequence,
    interest_snapshot_id,
    NULL,
    2,
    10,
    'blocked',
    '["release_cutoff_not_advanced"]'::jsonb,
    jsonb_build_object(
      'release_contract_id',
        'interest_management_report_snapshot_release_v1',
      'release_request_id',
        '6ca00000-0000-4000-8000-000000000004'::uuid,
      'project_id', trusted_attempt.project_id,
      'release_lineage_id', trusted_attempt.release_lineage_id,
      'report_id', trusted_attempt.report_id,
      'report_version', trusted_attempt.report_version,
      'query_fingerprint', trusted_attempt.query_fingerprint,
      'reporting_time_zone_version_number',
        trusted_attempt.reporting_time_zone_version_number,
      'reporting_time_zone', trusted_attempt.reporting_time_zone,
      'data_cutoff_utc', to_char(
        trusted_attempt.data_cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', trusted_attempt.source_change_sequence,
      'compared_snapshot_id', interest_snapshot_id,
      'released_snapshot_id', NULL,
      'shared_period_count', 2,
      'assessed_cell_count', 10,
      'result_status', 'blocked',
      'reason_codes', '["release_cutoff_not_advanced"]'::jsonb
    )
  );

  INSERT INTO app_private.management_report_snapshots
  SELECT
    blocked_snapshot_id,
    '6ca00000-0000-4000-8000-000000000004'::uuid,
    snapshot.created_by_app_user_id,
    snapshot.project_id,
    snapshot.release_lineage_id,
    snapshot.report_id,
    snapshot.report_version,
    snapshot.query_fingerprint,
    snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc,
    snapshot.released_at_utc,
    snapshot.previous_snapshot_id,
    snapshot.source_change_sequence,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = interest_snapshot_id;

  -- A claim for another release family is not interest provenance, even when
  -- the stored document has the interest shape.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id,
    release_family_id
  ) VALUES (
    '6ca00000-0000-4000-8000-000000000006'::uuid,
    'channel_management_report_snapshot_release'
  );
  INSERT INTO app_private.management_report_snapshots
  SELECT
    wrong_claim_snapshot_id,
    '6ca00000-0000-4000-8000-000000000006'::uuid,
    snapshot.created_by_app_user_id,
    snapshot.project_id,
    snapshot.release_lineage_id,
    snapshot.report_id,
    snapshot.report_version,
    snapshot.query_fingerprint,
    snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc,
    snapshot.released_at_utc,
    snapshot.previous_snapshot_id,
    snapshot.source_change_sequence,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = interest_snapshot_id;

  -- Snapshot metadata that drifts from an otherwise exact interest attempt is
  -- rejected by the 0062 insert validator. The orphaned snapshot remains
  -- untrusted to the read path.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id,
    release_family_id
  ) VALUES (
    '6ca00000-0000-4000-8000-000000000008'::uuid,
    'interest_management_report_snapshot_release'
  );
  INSERT INTO app_private.management_report_snapshots
  SELECT
    drifted_snapshot_id,
    '6ca00000-0000-4000-8000-000000000008'::uuid,
    snapshot.created_by_app_user_id,
    snapshot.project_id,
    snapshot.release_lineage_id,
    snapshot.report_id,
    snapshot.report_version,
    snapshot.query_fingerprint,
    snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc,
    snapshot.released_at_utc,
    snapshot.previous_snapshot_id,
    snapshot.source_change_sequence + 1,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = interest_snapshot_id;

  BEGIN
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
      '6ca00000-0000-4000-8000-000000000008'::uuid,
      trusted_attempt.requested_by_app_user_id,
      trusted_attempt.organization_workspace_id,
      trusted_attempt.organization_membership_id,
      trusted_attempt.project_membership_id,
      trusted_attempt.capability_grant_id,
      trusted_attempt.capability_id,
      trusted_attempt.authorization_reference_at_utc,
      trusted_attempt.project_id,
      trusted_attempt.reporting_time_zone_version_number,
      trusted_attempt.reporting_time_zone,
      trusted_attempt.reporting_time_zone_effective_from_utc,
      trusted_attempt.data_cutoff_utc,
      trusted_attempt.release_lineage_id,
      trusted_attempt.report_id,
      trusted_attempt.report_version,
      trusted_attempt.query_fingerprint,
      trusted_attempt.source_change_sequence,
      NULL,
      drifted_snapshot_id,
      0,
      0,
      'approved_baseline',
      '[]'::jsonb,
      jsonb_build_object(
        'release_contract_id',
          'interest_management_report_snapshot_release_v1',
        'release_request_id',
          '6ca00000-0000-4000-8000-000000000008'::uuid,
        'project_id', trusted_attempt.project_id,
        'release_lineage_id', trusted_attempt.release_lineage_id,
        'report_id', trusted_attempt.report_id,
        'report_version', trusted_attempt.report_version,
        'query_fingerprint', trusted_attempt.query_fingerprint,
        'reporting_time_zone_version_number',
          trusted_attempt.reporting_time_zone_version_number,
        'reporting_time_zone', trusted_attempt.reporting_time_zone,
        'data_cutoff_utc', to_char(
          trusted_attempt.data_cutoff_utc AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
        ),
        'source_change_sequence', trusted_attempt.source_change_sequence,
        'compared_snapshot_id', NULL,
        'released_snapshot_id', drifted_snapshot_id,
        'shared_period_count', 0,
        'assessed_cell_count', 0,
        'result_status', 'approved_baseline',
        'reason_codes', '[]'::jsonb
      )
    );
    RAISE EXCEPTION '6AX accepted drifted interest provenance';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  first_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    interest_snapshot_id
  );
  IF first_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_interest_management_report_snapshot_read_v1'
    OR first_read->>'result_status' IS DISTINCT FROM 'completed'
    OR first_read->>'reason_code' IS NOT NULL
    OR (first_read->>'resolved_snapshot_id')::uuid
      IS DISTINCT FROM interest_snapshot_id
    OR first_read->'protected_report' IS DISTINCT FROM baseline_document
    OR jsonb_array_length(first_read->'protected_report'->'cells') <> 10
  THEN
    RAISE EXCEPTION '6AX authorized read did not return the exact ten-cell snapshot: %',
      first_read;
  END IF;

  second_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    interest_snapshot_id
  );
  IF second_read->'protected_report' IS DISTINCT FROM baseline_document
    OR second_read->>'access_event_id' IS NULL
    OR second_read->>'access_event_id' = first_read->>'access_event_id'
  THEN
    RAISE EXCEPTION '6AX repeated authorized read changed the snapshot or reused audit';
  END IF;

  approved_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    approved_snapshot_id
  );
  IF approved_read->>'result_status' IS DISTINCT FROM 'completed'
    OR approved_read->'protected_report' IS DISTINCT FROM approved_document
    OR approved_read->>'reason_code' IS NOT NULL
  THEN
    RAISE EXCEPTION '6AX approved rolling snapshot read failed: %', approved_read;
  END IF;

  unknown_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    '6cb00000-0000-4000-8000-000000000001'::uuid
  );
  cross_project_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000002'::uuid,
    interest_snapshot_id
  );
  IF unknown_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR unknown_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR unknown_read ? 'protected_report'
    OR cross_project_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR cross_project_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6AX unknown/cross-project reads were distinguishable';
  END IF;

  channel_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    channel_snapshot_id
  );
  current_city_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    current_city_snapshot_id
  );
  legacy_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    legacy_snapshot_id
  );
  blocked_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    blocked_snapshot_id
  );
  wrong_claim_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    wrong_claim_snapshot_id
  );
  drifted_read := app_private.read_authorized_management_interest_report_snapshot_v1(
    '6c110000-0000-4000-8000-000000000002'::uuid,
    '6c130000-0000-4000-8000-000000000001'::uuid,
    drifted_snapshot_id
  );
  IF channel_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR channel_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR channel_read ? 'protected_report'
    OR current_city_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR current_city_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR current_city_read ? 'protected_report'
    OR legacy_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR legacy_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR legacy_read ? 'protected_report'
    OR blocked_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR blocked_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR blocked_read ? 'protected_report'
    OR wrong_claim_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR wrong_claim_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR wrong_claim_read ? 'protected_report'
    OR drifted_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR drifted_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR drifted_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6AX foreign, blocked or drifted provenance leaked values';
  END IF;

  -- Authorization failures occur before the audit insert.  Keep the failure
  -- assertions narrow so a future SQLSTATE mapping cannot hide a real error.
  audit_count := (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
  );
  BEGIN
    PERFORM app_private.read_authorized_management_interest_report_snapshot_v1(
      '6c110000-0000-4000-8000-000000000003'::uuid,
      '6c130000-0000-4000-8000-000000000001'::uuid,
      interest_snapshot_id
    );
    RAISE EXCEPTION '6AX release-only member read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.read_authorized_management_interest_report_snapshot_v1(
      '6c110000-0000-4000-8000-000000000004'::uuid,
      '6c130000-0000-4000-8000-000000000001'::uuid,
      interest_snapshot_id
    );
    RAISE EXCEPTION '6AX expired member read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.read_authorized_management_interest_report_snapshot_v1(
      '6c110000-0000-4000-8000-000000000005'::uuid,
      '6c130000-0000-4000-8000-000000000001'::uuid,
      interest_snapshot_id
    );
    RAISE EXCEPTION '6AX user without membership read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  IF (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
  ) <> audit_count THEN
    RAISE EXCEPTION '6AX authorization failures left an audit event';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_interest_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id =
    '6c110000-0000-4000-8000-000000000002'::uuid;
  IF history_text ~
      '(protected_report|value_count|privacy_status|cell_order|contributor|place_name|canonical_name)'
  THEN
    RAISE EXCEPTION '6AX read audit retained protected values';
  END IF;

  SELECT event.*
  INTO STRICT audit_row
  FROM app_private.management_interest_report_snapshot_access_events AS event
  WHERE event.access_event_id = (first_read->>'access_event_id')::uuid;
  IF audit_row.result_status <> 'completed'
    OR audit_row.report_id <> 'contact_sessions_by_interest_level_two_periods'
    OR audit_row.report_version <> 1
    OR audit_row.query_fingerprint <>
      'management-report:contact_sessions_by_interest_level_two_periods:v1'
  THEN
    RAISE EXCEPTION '6AX successful read audit lineage is incorrect';
  END IF;

  -- A value-free audit row cannot be forged with another report identity.
  audit_row.access_event_id := '6cd00000-0000-4000-8000-000000000001'::uuid;
  audit_row.query_fingerprint := 'management-report:wrong:v1';
  BEGIN
    INSERT INTO app_private.management_interest_report_snapshot_access_events
    SELECT audit_row.*;
    RAISE EXCEPTION '6AX accepted a forged read audit row';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.management_interest_report_snapshot_access_events
    SET reason_code = 'snapshot_not_available'
    WHERE access_event_id = (first_read->>'access_event_id')::uuid;
    RAISE EXCEPTION '6AX read audit update was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_interest_report_snapshot_access_events
    WHERE access_event_id = (first_read->>'access_event_id')::uuid;
    RAISE EXCEPTION '6AX read audit delete was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  IF (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6c110000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'completed'
  ) <> 3 OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6c110000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'not_found'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6c110000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'untrusted_provenance'
  ) <> 6
  THEN
    RAISE EXCEPTION '6AX read audit status counts are incorrect';
  END IF;
END
$fixture_6ax_reads$;

ROLLBACK;
