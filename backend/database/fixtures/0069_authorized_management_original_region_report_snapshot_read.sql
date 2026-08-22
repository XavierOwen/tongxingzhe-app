-- Synthetic rollback fixture for the 6BH original-region snapshot reader.
--
-- The 0068 fixture is rolled back in a separate psql process, so this test
-- rebuilds one original-region baseline/rolling pair and the small set of
-- foreign or malformed provenance rows required for fail-closed reads.  All
-- identifiers use the 6BH namespace and every row is rolled back.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b810000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000005'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000006'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
) VALUES (
  '6b820000-0000-4000-8000-000000000001'::uuid,
  'organization', '6BH original-region read workspace', NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6b830000-0000-4000-8000-000000000001'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6BH original-region read project'
  ),
  (
    '6b830000-0000-4000-8000-000000000002'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6BH other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES
  (
    '6b840000-0000-4000-8000-000000000001'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    '6b840000-0000-4000-8000-000000000002'::uuid,
    '6b830000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6b860000-0000-4000-8000-000000000001'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b860000-0000-4000-8000-000000000002'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6b810000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b860000-0000-4000-8000-000000000003'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6b810000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b860000-0000-4000-8000-000000000004'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6b810000-0000-4000-8000-000000000004'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b860000-0000-4000-8000-000000000005'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6b810000-0000-4000-8000-000000000005'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6b870000-0000-4000-8000-000000000001'::uuid,
    '6b860000-0000-4000-8000-000000000001'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b870000-0000-4000-8000-000000000002'::uuid,
    '6b860000-0000-4000-8000-000000000002'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b870000-0000-4000-8000-000000000003'::uuid,
    '6b860000-0000-4000-8000-000000000003'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b870000-0000-4000-8000-000000000004'::uuid,
    '6b860000-0000-4000-8000-000000000004'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    '6b870000-0000-4000-8000-000000000005'::uuid,
    '6b860000-0000-4000-8000-000000000005'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b870000-0000-4000-8000-000000000006'::uuid,
    '6b860000-0000-4000-8000-000000000001'::uuid,
    '6b830000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b870000-0000-4000-8000-000000000007'::uuid,
    '6b860000-0000-4000-8000-000000000002'::uuid,
    '6b830000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6b880000-0000-4000-8000-000000000001'::uuid,
    '6b870000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b880000-0000-4000-8000-000000000002'::uuid,
    '6b870000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b880000-0000-4000-8000-000000000003'::uuid,
    '6b870000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b880000-0000-4000-8000-000000000004'::uuid,
    '6b870000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    '6b880000-0000-4000-8000-000000000005'::uuid,
    '6b870000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days',
    clock_timestamp() - interval '1 second'
  ),
  (
    '6b880000-0000-4000-8000-000000000006'::uuid,
    '6b870000-0000-4000-8000-000000000006'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b880000-0000-4000-8000-000000000007'::uuid,
    '6b870000-0000-4000-8000-000000000007'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b850000-0000-4000-8000-000000000001'::uuid,
  '6b810000-0000-4000-8000-000000000001'::uuid,
  '6b830000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b850000-0000-4000-8000-000000000002'::uuid,
  '6b810000-0000-4000-8000-000000000001'::uuid,
  '6b830000-0000-4000-8000-000000000002'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6bh_report_context AS
WITH captured AS (SELECT clock_timestamp() AS data_cutoff_utc)
SELECT captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

-- Original source and current target trees deliberately coexist.  The read
-- contract must trust only the original release family, never target mapping
-- or a report with a similar shape.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
)
VALUES
  ('fixture-6bh-original-v1', 'draft', false),
  ('fixture-6bh-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6bh-original-country', 'fixture-6bh-original-v1', NULL,
    '6BH Source Country', 'country'),
  ('fixture-6bh-original-city-a', 'fixture-6bh-original-v1',
    'fixture-6bh-original-country', '6BH City A', 'city'),
  ('fixture-6bh-original-city-b', 'fixture-6bh-original-v1',
    'fixture-6bh-original-country', '6BH City B', 'city'),
  ('fixture-6bh-original-city-c', 'fixture-6bh-original-v1',
    'fixture-6bh-original-country', '6BH City C', 'city'),
  ('fixture-6bh-original-venue-a', 'fixture-6bh-original-v1',
    'fixture-6bh-original-city-a', '6BH Venue A', 'venue'),
  ('fixture-6bh-original-venue-b', 'fixture-6bh-original-v1',
    'fixture-6bh-original-city-b', '6BH Venue B', 'venue'),
  ('fixture-6bh-original-venue-c', 'fixture-6bh-original-v1',
    'fixture-6bh-original-city-c', '6BH Venue C', 'venue'),
  ('fixture-6bh-target-country', 'fixture-6bh-target-v1', NULL,
    '6BH Target Country', 'country'),
  ('fixture-6bh-target-city-a', 'fixture-6bh-target-v1',
    'fixture-6bh-target-country', '6BH City A', 'city'),
  ('fixture-6bh-target-city-b', 'fixture-6bh-target-v1',
    'fixture-6bh-target-country', '6BH City B', 'city'),
  ('fixture-6bh-target-city-c', 'fixture-6bh-target-v1',
    'fixture-6bh-target-country', '6BH City C', 'city'),
  ('fixture-6bh-target-venue-a', 'fixture-6bh-target-v1',
    'fixture-6bh-target-city-a', '6BH Venue A', 'venue'),
  ('fixture-6bh-target-venue-b', 'fixture-6bh-target-v1',
    'fixture-6bh-target-city-b', '6BH Venue B', 'venue'),
  ('fixture-6bh-target-venue-c', 'fixture-6bh-target-v1',
    'fixture-6bh-target-city-c', '6BH Venue C', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES
  ('fixture-6bh-original-boundary-a', 'fixture-6bh-original-venue-a',
    'fixture-6bh-original-v1', polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'),
  ('fixture-6bh-original-boundary-b', 'fixture-6bh-original-venue-b',
    'fixture-6bh-original-v1', polygon '((-87.90,41.60),(-87.80,41.60),(-87.80,41.70),(-87.90,41.70))'),
  ('fixture-6bh-original-boundary-c', 'fixture-6bh-original-venue-c',
    'fixture-6bh-original-v1', polygon '((-87.80,41.60),(-87.70,41.60),(-87.70,41.70),(-87.80,41.70))'),
  ('fixture-6bh-target-boundary-a', 'fixture-6bh-target-venue-a',
    'fixture-6bh-target-v1', polygon '((-87.70,41.60),(-87.60,41.60),(-87.60,41.70),(-87.70,41.70))'),
  ('fixture-6bh-target-boundary-b', 'fixture-6bh-target-venue-b',
    'fixture-6bh-target-v1', polygon '((-87.60,41.60),(-87.50,41.60),(-87.50,41.70),(-87.60,41.70))'),
  ('fixture-6bh-target-boundary-c', 'fixture-6bh-target-venue-c',
    'fixture-6bh-target-v1', polygon '((-87.50,41.60),(-87.40,41.60),(-87.40,41.70),(-87.50,41.70))');

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bh-original-v1', false
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bh-target-v1', true
);

CREATE TEMP TABLE fixture_6bh_fingerprints AS
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6bh-original-v1'
  ) AS original_fingerprint,
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6bh-target-v1'
  ) AS target_fingerprint
FROM app_data.canonical_region_tree_releases;

SELECT app_private.register_canonical_region_version_mapping_v1(
  mapping.mapping_id, 'fixture-6bh-original-v1', mapping.source_region_id,
  fingerprints.original_fingerprint, 'fixture-6bh-target-v1',
  mapping.target_region_id, fingerprints.target_fingerprint, repeat('b', 64)
)
FROM (VALUES
  ('6b890000-0000-4000-8000-000000000001'::uuid,
    'fixture-6bh-original-venue-a', 'fixture-6bh-target-venue-a'),
  ('6b890000-0000-4000-8000-000000000002'::uuid,
    'fixture-6bh-original-venue-b', 'fixture-6bh-target-venue-b'),
  ('6b890000-0000-4000-8000-000000000003'::uuid,
    'fixture-6bh-original-venue-c', 'fixture-6bh-target-venue-c')
) AS mapping(mapping_id, source_region_id, target_region_id)
CROSS JOIN fixture_6bh_fingerprints AS fingerprints;

CREATE TEMP TABLE fixture_6bh_contact_plan AS
SELECT
  format('fixture-6bh-%s-%s-c%s-u%s', period_row.period_key,
    city_row.city_key, contributor_row.contributor_number,
    unit_row.unit_number) AS contact_id,
  period_row.period_key, city_row.city_key,
  contributor_row.contributor_number,
  CASE contributor_row.contributor_number
    WHEN 1 THEN '6b810000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6b810000-0000-4000-8000-000000000002'::uuid
    ELSE '6b810000-0000-4000-8000-000000000003'::uuid
  END AS contributor_id,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 minute'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 minute'
  END AS occurred_at_utc
FROM fixture_6bh_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES ('a'), ('b'), ('c')) AS city_row(city_key)
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(
  1,
  CASE
    WHEN period_row.period_key = 'previous' AND city_row.city_key = 'c'
      THEN CASE contributor_row.contributor_number
        WHEN 1 THEN 4 WHEN 2 THEN 2 ELSE 2 END
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
  plan.contact_id, plan.contributor_id,
  '6b820000-0000-4000-8000-000000000001'::uuid,
  '6b830000-0000-4000-8000-000000000001'::uuid,
  '6b840000-0000-4000-8000-000000000001'::uuid,
  plan.occurred_at_utc, 'UTC', plan.occurred_at_utc,
  'face_to_face', 'resolved', '6BH source venue',
  format('fixture-6bh-original-venue-%s', plan.city_key),
  'fixture-6bh-original-v1', 1, 2
FROM fixture_6bh_contact_plan AS plan;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
)
SELECT
  plan.contact_id, 1, 'submitted', plan.contributor_id,
  jsonb_build_object(
    'contactId', plan.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved', 'placeName', '6BH source venue',
      'smallestRegionId', format('fixture-6bh-original-venue-%s', plan.city_key),
      'regionTreeVersion', 'fixture-6bh-original-v1'
    )
  )
FROM fixture_6bh_contact_plan AS plan;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id,
  revision_number, change_type
) VALUES (
  '6b810000-0000-4000-8000-000000000001'::uuid,
  '6b820000-0000-4000-8000-000000000001'::uuid,
  '6b830000-0000-4000-8000-000000000001'::uuid,
  'fixture-6bh-original-watermark', 1, 'contact.submitted'
);

DO $fixture_6bh_release$
DECLARE
  baseline jsonb;
  rolling jsonb;
BEGIN
  baseline := app_private.release_management_original_region_report_snapshot_v1(
    '6b8a0000-0000-4000-8000-000000000001'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_original_region_two_periods', 1
  );
  IF baseline->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR baseline->>'released_snapshot_id' IS NULL
    OR baseline ? 'protected_report'
    OR baseline ? 'cells'
  THEN
    RAISE EXCEPTION '6BH original baseline release failed: %', baseline;
  END IF;

  PERFORM pg_sleep(0.01);
  rolling := app_private.release_management_original_region_report_snapshot_v1(
    '6b8a0000-0000-4000-8000-000000000002'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    '6b830000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_original_region_two_periods', 1
  );
  IF rolling->>'result_status' IS DISTINCT FROM 'approved'
    OR rolling->>'released_snapshot_id' IS NULL
    OR rolling->>'compared_snapshot_id' IS DISTINCT FROM
      baseline->>'released_snapshot_id'
  THEN
    RAISE EXCEPTION '6BH original rolling release failed: %', rolling;
  END IF;
END
$fixture_6bh_release$;

DO $fixture_6bh_reads$
DECLARE
  project_id constant uuid := '6b830000-0000-4000-8000-000000000001';
  project_two constant uuid := '6b830000-0000-4000-8000-000000000002';
  viewer_id constant uuid := '6b810000-0000-4000-8000-000000000002';
  report_id constant text := 'contact_sessions_by_original_region_two_periods';
  baseline_snapshot_id uuid;
  rolling_snapshot_id uuid;
  channel_snapshot_id uuid;
  current_city_snapshot_id uuid;
  interest_snapshot_id uuid;
  legacy_snapshot_id constant uuid :=
    '6ba00000-0000-4000-8000-000000000001';
  blocked_snapshot_id constant uuid :=
    '6ba00000-0000-4000-8000-000000000003';
  wrong_claim_snapshot_id constant uuid :=
    '6ba00000-0000-4000-8000-000000000005';
  drifted_snapshot_id constant uuid :=
    '6ba00000-0000-4000-8000-000000000007';
  blocked_request_id constant uuid :=
    '6b8a0000-0000-4000-8000-000000000003';
  baseline_document jsonb;
  rolling_document jsonb;
  first_read jsonb;
  repeated_read jsonb;
  rolling_read jsonb;
  unknown_read jsonb;
  cross_project_read jsonb;
  channel_read jsonb;
  current_city_read jsonb;
  interest_read jsonb;
  legacy_read jsonb;
  blocked_read jsonb;
  wrong_claim_read jsonb;
  drifted_read jsonb;
  release_result jsonb;
  history_text text;
  audit_count bigint;
  audit_row app_private.management_original_region_report_snapshot_access_events%ROWTYPE;
BEGIN
  SELECT attempt.released_snapshot_id
  INTO STRICT baseline_snapshot_id
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b8a0000-0000-4000-8000-000000000001'::uuid;
  SELECT attempt.released_snapshot_id
  INTO STRICT rolling_snapshot_id
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b8a0000-0000-4000-8000-000000000002'::uuid;
  SELECT snapshot.protected_report
  INTO STRICT baseline_document
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;
  SELECT snapshot.protected_report
  INTO STRICT rolling_document
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = rolling_snapshot_id;

  IF jsonb_array_length(baseline_document->'cells') <> 6
    OR jsonb_array_length(rolling_document->'cells') <> 6
    OR NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(baseline_document->'cells') AS item(cell)
      WHERE item.cell->>'privacy_status' = 'suppressed'
        AND item.cell->'value_count' = 'null'::jsonb
    )
    OR baseline_document::text ~
      '(contact_id|revision_number|contributor_key|source_id|place_name|latitude|longitude|geometry|email|phone)'
  THEN
    RAISE EXCEPTION '6BH baseline is not a complete value-safe original grid';
  END IF;

  -- These three valid families are deliberately read through the original
  -- reader.  Shape or a valid foreign release must not confer original
  -- provenance.
  release_result := app_private.release_management_report_snapshot_v1(
    '6b8a0000-0000-4000-8000-000000000020'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    project_id, 'contact_sessions_by_channel_two_periods', 1,
    'UTC',
    (baseline_document->'periods'->>'data_cutoff_utc')::timestamptz
      + interval '1 second',
    (baseline_document->'periods'->>'data_cutoff_utc')::timestamptz
      + interval '1 second'
  );
  SELECT attempt.released_snapshot_id INTO STRICT channel_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b8a0000-0000-4000-8000-000000000020'::uuid;

  release_result := app_private.release_management_current_city_report_snapshot_v1(
    '6b8a0000-0000-4000-8000-000000000021'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    project_id, 'contact_sessions_by_current_city_two_periods', 1
  );
  IF release_result->>'released_snapshot_id' IS NULL THEN
    RAISE EXCEPTION '6BH current-city setup failed: %', release_result;
  END IF;
  current_city_snapshot_id := (release_result->>'released_snapshot_id')::uuid;

  release_result := app_private.release_management_interest_report_snapshot_v1(
    '6b8a0000-0000-4000-8000-000000000022'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    project_id, 'contact_sessions_by_interest_level_two_periods', 1
  );
  IF release_result->>'released_snapshot_id' IS NULL THEN
    RAISE EXCEPTION '6BH interest setup failed: %', release_result;
  END IF;
  interest_snapshot_id := (release_result->>'released_snapshot_id')::uuid;

  -- Create a valid same-project blocked attempt at the baseline cutoff.  Its
  -- request is then attached to a copied snapshot: the reader must reject the
  -- row because the attempt did not release any snapshot.
  INSERT INTO app_private.management_original_region_report_release_attempts (
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
    source_tree_version,
    source_content_fingerprint,
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
    blocked_request_id,
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
    attempt.source_tree_version,
    attempt.source_content_fingerprint,
    attempt.source_change_sequence,
    baseline_snapshot_id,
    NULL,
    0,
    0,
    'blocked',
    jsonb_build_array('release_cutoff_not_advanced'),
    jsonb_build_object(
      'release_contract_id',
        'original_region_management_report_snapshot_release_v1',
      'release_request_id', blocked_request_id,
      'project_id', attempt.project_id,
      'release_lineage_id', attempt.release_lineage_id,
      'report_id', attempt.report_id,
      'report_version', attempt.report_version,
      'query_fingerprint', attempt.query_fingerprint,
      'reporting_time_zone_version_number',
        attempt.reporting_time_zone_version_number,
      'reporting_time_zone', attempt.reporting_time_zone,
      'data_cutoff_utc', to_char(
        attempt.data_cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_tree_version', attempt.source_tree_version,
      'source_content_fingerprint', attempt.source_content_fingerprint,
      'source_change_sequence', attempt.source_change_sequence,
      'compared_snapshot_id', baseline_snapshot_id,
      'released_snapshot_id', NULL,
      'shared_period_count', 0,
      'assessed_cell_count', 0,
      'result_status', 'blocked',
      'reason_codes', jsonb_build_array('release_cutoff_not_advanced')
    )
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b8a0000-0000-4000-8000-000000000001'::uuid;

  -- Legacy: exact protected document, no 0068 attempt/claim.
  INSERT INTO app_private.management_report_snapshots
  SELECT legacy_snapshot_id, '6ba00000-0000-4000-8000-000000000002'::uuid,
    snapshot.created_by_app_user_id, snapshot.project_id,
    snapshot.release_lineage_id, snapshot.report_id, snapshot.report_version,
    snapshot.query_fingerprint, snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc, snapshot.released_at_utc,
    snapshot.previous_snapshot_id, snapshot.source_change_sequence,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;

  -- Blocked: the attempt exists but has no released snapshot.
  INSERT INTO app_private.management_report_snapshots
  SELECT blocked_snapshot_id, blocked_request_id,
    snapshot.created_by_app_user_id, snapshot.project_id,
    snapshot.release_lineage_id, snapshot.report_id, snapshot.report_version,
    snapshot.query_fingerprint, snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc, snapshot.released_at_utc,
    snapshot.previous_snapshot_id, snapshot.source_change_sequence,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;

  -- Wrong family claim: a valid-looking original document is claimed by the
  -- channel family and is therefore never trusted by this reader.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    '6ba00000-0000-4000-8000-000000000006'::uuid,
    'channel_management_report_snapshot_release'
  );
  INSERT INTO app_private.management_report_snapshots
  SELECT wrong_claim_snapshot_id,
    '6ba00000-0000-4000-8000-000000000006'::uuid,
    snapshot.created_by_app_user_id, snapshot.project_id,
    snapshot.release_lineage_id, snapshot.report_id, snapshot.report_version,
    snapshot.query_fingerprint, snapshot.reporting_time_zone,
    snapshot.data_cutoff_utc, snapshot.released_at_utc,
    snapshot.previous_snapshot_id, snapshot.source_change_sequence,
    snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;

  -- Drifted lineage: the row has an original-shaped report but its lineage
  -- tuple is not the fixed 6BH lineage and has no matching attempt.
  INSERT INTO app_private.management_report_snapshots
  SELECT drifted_snapshot_id,
    '6ba00000-0000-4000-0000-000000000008'::uuid,
    snapshot.created_by_app_user_id, snapshot.project_id,
    'management-original-region-report:drifted', snapshot.report_id,
    snapshot.report_version, snapshot.query_fingerprint,
    snapshot.reporting_time_zone, snapshot.data_cutoff_utc,
    snapshot.released_at_utc, snapshot.previous_snapshot_id,
    snapshot.source_change_sequence, snapshot.protected_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;

  first_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, baseline_snapshot_id
  );
  IF first_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_original_region_management_report_snapshot_read_v1'
    OR first_read->>'result_status' IS DISTINCT FROM 'completed'
    OR first_read->>'reason_code' IS NOT NULL
    OR (first_read->>'resolved_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
    OR first_read->'protected_report' IS DISTINCT FROM baseline_document
    OR jsonb_array_length(first_read->'protected_report'->'cells') <> 6
  THEN
    RAISE EXCEPTION '6BH first original-region read was not exact: %', first_read;
  END IF;

  repeated_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, baseline_snapshot_id
  );
  IF repeated_read->'protected_report' IS DISTINCT FROM baseline_document
    OR repeated_read->>'access_event_id' IS NULL
    OR repeated_read->>'access_event_id' = first_read->>'access_event_id'
  THEN
    RAISE EXCEPTION '6BH repeated original-region read changed the snapshot';
  END IF;

  rolling_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, rolling_snapshot_id
  );
  IF rolling_read->>'result_status' IS DISTINCT FROM 'completed'
    OR rolling_read->'protected_report' IS DISTINCT FROM rolling_document
    OR NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(rolling_read->'protected_report'->'cells') AS item(cell)
      WHERE item.cell->>'privacy_status' = 'suppressed'
        AND item.cell->'value_count' = 'null'::jsonb
    )
  THEN
    RAISE EXCEPTION '6BH rolling original-region read was not exact: %', rolling_read;
  END IF;

  unknown_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, '6bb00000-0000-4000-8000-000000000001'::uuid
  );
  cross_project_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_two, baseline_snapshot_id
  );
  IF unknown_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR unknown_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR unknown_read ? 'protected_report'
    OR cross_project_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR cross_project_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BH unknown/cross-project read was distinguishable';
  END IF;

  channel_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, channel_snapshot_id
  );
  current_city_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, current_city_snapshot_id
  );
  interest_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, interest_snapshot_id
  );
  legacy_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, legacy_snapshot_id
  );
  blocked_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, blocked_snapshot_id
  );
  wrong_claim_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, wrong_claim_snapshot_id
  );
  drifted_read := app_private.read_authorized_management_original_region_report_snapshot_v1(
    viewer_id, project_id, drifted_snapshot_id
  );
  IF channel_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR current_city_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR interest_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR legacy_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR blocked_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR wrong_claim_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR drifted_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR channel_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR current_city_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR interest_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR legacy_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR blocked_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR wrong_claim_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR drifted_read->>'reason_code' IS DISTINCT FROM 'snapshot_provenance_untrusted'
    OR channel_read ? 'protected_report'
    OR current_city_read ? 'protected_report'
    OR interest_read ? 'protected_report'
    OR legacy_read ? 'protected_report'
    OR blocked_read ? 'protected_report'
    OR wrong_claim_read ? 'protected_report'
    OR drifted_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BH foreign/blocked/drifted provenance leaked values';
  END IF;

  -- Authorization failures happen before audit insertion.  Cover release-only,
  -- expired, revoked, no-membership and inactive-project requests with one
  -- stable fail-closed rule.
  audit_count := (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_access_events
  );
  FOREACH release_result IN ARRAY ARRAY[
    jsonb_build_object('user_id', '6b810000-0000-4000-8000-000000000003'::uuid),
    jsonb_build_object('user_id', '6b810000-0000-4000-8000-000000000004'::uuid),
    jsonb_build_object('user_id', '6b810000-0000-4000-8000-000000000005'::uuid),
    jsonb_build_object('user_id', '6b810000-0000-4000-8000-000000000006'::uuid)
  ] LOOP
    BEGIN
      PERFORM app_private.read_authorized_management_original_region_report_snapshot_v1(
        (release_result->>'user_id')::uuid, project_id, baseline_snapshot_id
      );
      RAISE EXCEPTION '6BH unauthorized original-region read passed: %', release_result;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END LOOP;
  UPDATE app_data.projects AS project
  SET status = 'archived'
  WHERE project.project_id = project_two;
  BEGIN
    PERFORM app_private.read_authorized_management_original_region_report_snapshot_v1(
      viewer_id, project_two, baseline_snapshot_id
    );
    RAISE EXCEPTION '6BH inactive-project original-region read passed';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  IF (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_access_events
  ) <> audit_count THEN
    RAISE EXCEPTION '6BH unauthorized reads appended audit rows';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_original_region_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id = viewer_id;
  IF history_text ~
    '(protected_report|cells|value_count|privacy_status|contact_id|revision_number|contributor|source_id|place_name|canonical_name|latitude|longitude|geometry|email|phone|token)'
  THEN
    RAISE EXCEPTION '6BH original-region read audit retained protected values';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_original_region_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id = viewer_id
      AND event.result_status = 'untrusted_provenance'
      AND (
        event.source_tree_version IS NOT NULL
        OR event.source_content_fingerprint IS NOT NULL
        OR event.source_change_sequence IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION '6BH untrusted audit retained an unverified source tuple';
  END IF;

  SELECT event.*
  INTO STRICT audit_row
  FROM app_private.management_original_region_report_snapshot_access_events AS event
  WHERE event.access_event_id = (first_read->>'access_event_id')::uuid;
  IF audit_row.result_status IS DISTINCT FROM 'completed'
    OR audit_row.report_id IS DISTINCT FROM report_id
    OR audit_row.report_version IS DISTINCT FROM 1
    OR audit_row.query_fingerprint IS DISTINCT FROM
      'management-report:contact_sessions_by_original_region_two_periods:v1'
    OR audit_row.source_tree_version IS NULL
    OR audit_row.source_content_fingerprint IS NULL
    OR audit_row.source_change_sequence IS NULL
  THEN
    RAISE EXCEPTION '6BH successful read audit lineage is incorrect';
  END IF;

  -- The audit is value-free and append-only.
  audit_row.access_event_id := '6bd00000-0000-4000-8000-000000000001'::uuid;
  audit_row.query_fingerprint := 'management-report:wrong:v1';
  BEGIN
    INSERT INTO app_private.management_original_region_report_snapshot_access_events
    SELECT audit_row.*;
    RAISE EXCEPTION '6BH forged original-region audit row was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    UPDATE app_private.management_original_region_report_snapshot_access_events
    SET reason_code = 'snapshot_not_available'
    WHERE access_event_id = (first_read->>'access_event_id')::uuid;
    RAISE EXCEPTION '6BH original-region audit UPDATE was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_original_region_report_snapshot_access_events
    WHERE access_event_id = (first_read->>'access_event_id')::uuid;
    RAISE EXCEPTION '6BH original-region audit DELETE was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  IF (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_access_events
    WHERE requested_by_app_user_id = viewer_id
      AND result_status = 'completed'
  ) <> 3 OR (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_access_events
    WHERE requested_by_app_user_id = viewer_id
      AND result_status = 'not_found'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_access_events
    WHERE requested_by_app_user_id = viewer_id
      AND result_status = 'untrusted_provenance'
  ) <> 7
  THEN
    RAISE EXCEPTION '6BH original-region read audit status counts are incorrect';
  END IF;
END
$fixture_6bh_reads$;

ROLLBACK;
