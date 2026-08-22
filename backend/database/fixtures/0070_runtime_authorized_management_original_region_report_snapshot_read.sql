-- Synthetic rollback fixture for the 6BI runtime original-region snapshot
-- bridge.
--
-- The 0069 private-reader fixture is rolled back in a separate psql process, so this test
-- rebuilds one original-region baseline/rolling pair and the small set of
-- foreign or malformed provenance rows required for fail-closed reads. It
-- then adds exact external identities and calls the 0070 bridge as runtime.
-- Every row is rolled back.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b810000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000004'::uuid, 'deletion_pending'),
  ('6b810000-0000-4000-8000-000000000005'::uuid, 'active'),
  ('6b810000-0000-4000-8000-000000000006'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  (
    '6b9e0000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-original.synthetic/auth/v1',
    'active-reader',
    '6b810000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b9e0000-0000-4000-8000-000000000002'::uuid,
    ' https://runtime-original.synthetic/auth/v1 ',
    'spaced-reader',
    '6b810000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b9e0000-0000-4000-8000-000000000003'::uuid,
    'https://runtime-original.synthetic/auth/v1',
    'release-only-reader',
    '6b810000-0000-4000-8000-000000000003'::uuid
  ),
  (
    '6b9e0000-0000-4000-8000-000000000004'::uuid,
    'https://runtime-original.synthetic/auth/v1',
    'inactive-reader',
    '6b810000-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
) VALUES (
  '6b820000-0000-4000-8000-000000000001'::uuid,
  'organization', '6BI original-region read workspace', NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6b830000-0000-4000-8000-000000000001'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6BI original-region read project'
  ),
  (
    '6b830000-0000-4000-8000-000000000002'::uuid,
    '6b820000-0000-4000-8000-000000000001'::uuid,
    '6BI other project'
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
    '6BI Source Country', 'country'),
  ('fixture-6bh-original-city-a', 'fixture-6bh-original-v1',
    'fixture-6bh-original-country', '6BI City A', 'city'),
  ('fixture-6bh-original-city-b', 'fixture-6bh-original-v1',
    'fixture-6bh-original-country', '6BI City B', 'city'),
  ('fixture-6bh-original-city-c', 'fixture-6bh-original-v1',
    'fixture-6bh-original-country', '6BI City C', 'city'),
  ('fixture-6bh-original-venue-a', 'fixture-6bh-original-v1',
    'fixture-6bh-original-city-a', '6BI Venue A', 'venue'),
  ('fixture-6bh-original-venue-b', 'fixture-6bh-original-v1',
    'fixture-6bh-original-city-b', '6BI Venue B', 'venue'),
  ('fixture-6bh-original-venue-c', 'fixture-6bh-original-v1',
    'fixture-6bh-original-city-c', '6BI Venue C', 'venue'),
  ('fixture-6bh-target-country', 'fixture-6bh-target-v1', NULL,
    '6BI Target Country', 'country'),
  ('fixture-6bh-target-city-a', 'fixture-6bh-target-v1',
    'fixture-6bh-target-country', '6BI City A', 'city'),
  ('fixture-6bh-target-city-b', 'fixture-6bh-target-v1',
    'fixture-6bh-target-country', '6BI City B', 'city'),
  ('fixture-6bh-target-city-c', 'fixture-6bh-target-v1',
    'fixture-6bh-target-country', '6BI City C', 'city'),
  ('fixture-6bh-target-venue-a', 'fixture-6bh-target-v1',
    'fixture-6bh-target-city-a', '6BI Venue A', 'venue'),
  ('fixture-6bh-target-venue-b', 'fixture-6bh-target-v1',
    'fixture-6bh-target-city-b', '6BI Venue B', 'venue'),
  ('fixture-6bh-target-venue-c', 'fixture-6bh-target-v1',
    'fixture-6bh-target-city-c', '6BI Venue C', 'venue');

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
  'face_to_face', 'resolved', '6BI source venue',
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
      'kind', 'resolved', 'placeName', '6BI source venue',
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

DO $fixture_6bi_release$
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
    RAISE EXCEPTION '6BI original baseline release failed: %', baseline;
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
    RAISE EXCEPTION '6BI original rolling release failed: %', rolling;
  END IF;
END
$fixture_6bi_release$;

DO $fixture_6bi_setup$
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
    RAISE EXCEPTION '6BI baseline is not a complete value-safe original grid';
  END IF;

  -- Prepare foreign-family snapshots. Shape or a valid foreign release must
  -- not confer original-region provenance to the runtime bridge.
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
    RAISE EXCEPTION '6BI current-city setup failed: %', release_result;
  END IF;
  current_city_snapshot_id := (release_result->>'released_snapshot_id')::uuid;

  release_result := app_private.release_management_interest_report_snapshot_v1(
    '6b8a0000-0000-4000-8000-000000000022'::uuid,
    '6b810000-0000-4000-8000-000000000001'::uuid,
    project_id, 'contact_sessions_by_interest_level_two_periods', 1
  );
  IF release_result->>'released_snapshot_id' IS NULL THEN
    RAISE EXCEPTION '6BI interest setup failed: %', release_result;
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
  -- tuple is not the fixed 6BI lineage and has no matching attempt.
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

END
$fixture_6bi_setup$;

SELECT set_config(
  'app.fixture_6bi_baseline_snapshot_id',
  (
    SELECT released_snapshot_id::text
    FROM app_private.management_original_region_report_release_attempts
    WHERE release_request_id =
      '6b8a0000-0000-4000-8000-000000000001'::uuid
  ),
  true
);
SELECT set_config(
  'app.fixture_6bi_identity_issuer',
  'https://runtime-original.synthetic/auth/v1',
  true
);
SELECT set_config(
  'app.fixture_6bi_identity_subject',
  'active-reader',
  true
);
SELECT set_config(
  'app.fixture_6bi_project_id',
  '6b830000-0000-4000-8000-000000000001',
  true
);

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6bi_runtime$
DECLARE
  project_id constant uuid := '6b830000-0000-4000-8000-000000000001';
  project_two constant uuid := '6b830000-0000-4000-8000-000000000002';
  baseline_snapshot_id uuid;
  first_read jsonb;
  repeated_read jsonb;
  exact_spaced_read jsonb;
  unknown_read jsonb;
  cross_project_read jsonb;
  untrusted_read jsonb;
  audit_text text;
BEGIN
  baseline_snapshot_id :=
    current_setting('app.fixture_6bi_baseline_snapshot_id')::uuid;

  first_read :=
    app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1',
      'active-reader',
      project_id,
      baseline_snapshot_id
    );
  IF first_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_original_region_management_report_snapshot_read_v1'
    OR first_read->>'result_status' IS DISTINCT FROM 'completed'
    OR first_read->>'reason_code' IS NOT NULL
    OR (first_read->>'requested_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
    OR (first_read->>'resolved_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
    OR first_read->'protected_report' IS NULL
    OR jsonb_array_length(first_read->'protected_report'->'cells') <> 6
    OR first_read ? 'project_id'
    OR first_read ? 'requested_app_user_id'
    OR first_read::text ~* 'organization_membership|capability_grant|app_user_id'
  THEN
    RAISE EXCEPTION '6BI active runtime read was not the 0069 contract: %',
      first_read;
  END IF;

  repeated_read :=
    app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1',
      'active-reader',
      project_id,
      (first_read->>'resolved_snapshot_id')::uuid
    );
  IF repeated_read->>'result_status' IS DISTINCT FROM 'completed'
    OR repeated_read->'protected_report' IS DISTINCT FROM
      first_read->'protected_report'
    OR repeated_read->>'access_event_id' IS NULL
    OR repeated_read->>'access_event_id' = first_read->>'access_event_id'
  THEN
    RAISE EXCEPTION '6BI repeated runtime read did not append an exact audit';
  END IF;

  -- A stored issuer containing spaces is not matched by a normalized input.
  -- Passing that exact stored value is a separate successful identity match.
  BEGIN
    PERFORM app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1',
      'spaced-reader',
      project_id,
      baseline_snapshot_id
    );
    RAISE EXCEPTION '6BI runtime bridge trimmed a stored issuer';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  exact_spaced_read :=
    app_data.read_authorized_management_original_region_report_snapshot_v1(
      ' https://runtime-original.synthetic/auth/v1 ',
      'spaced-reader',
      project_id,
      baseline_snapshot_id
    );
  IF exact_spaced_read->>'result_status' IS DISTINCT FROM 'completed'
    OR exact_spaced_read->'protected_report' IS DISTINCT FROM
      first_read->'protected_report'
  THEN
    RAISE EXCEPTION '6BI exact stored identity did not resolve';
  END IF;

  unknown_read :=
    app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1',
      'active-reader',
      project_id,
      '6bb00000-0000-4000-8000-000000000001'::uuid
    );
  cross_project_read :=
    app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1',
      'active-reader',
      project_two,
      baseline_snapshot_id
    );
  IF unknown_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR unknown_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR unknown_read ? 'protected_report'
    OR cross_project_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR cross_project_read->>'reason_code' IS DISTINCT FROM
      'snapshot_not_available'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BI unknown/cross-project read was not indistinguishable';
  END IF;

  untrusted_read :=
    app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1',
      'active-reader',
      project_id,
      '6ba00000-0000-4000-8000-000000000001'::uuid
    );
  IF untrusted_read->>'result_status' IS DISTINCT FROM
      'untrusted_provenance'
    OR untrusted_read->>'reason_code' IS DISTINCT FROM
      'snapshot_provenance_untrusted'
    OR untrusted_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BI untrusted runtime read leaked values: %',
      untrusted_read;
  END IF;

  FOREACH audit_text IN ARRAY ARRAY[
    'https://runtime-original.synthetic/auth/v1|release-only-reader',
    'https://runtime-original.synthetic/auth/v1|inactive-reader',
    'https://runtime-original.invalid/auth/v1|active-reader',
    'https://runtime-original.synthetic/auth/v1|unknown-reader'
  ] LOOP
    BEGIN
      PERFORM app_data.read_authorized_management_original_region_report_snapshot_v1(
        split_part(audit_text, '|', 1),
        split_part(audit_text, '|', 2),
        project_id,
        baseline_snapshot_id
      );
      RAISE EXCEPTION '6BI unauthorized identity was accepted: %', audit_text;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END LOOP;

  -- Invalid arguments are a strict contract error, not an identity failure.
  BEGIN
    PERFORM app_data.read_authorized_management_original_region_report_snapshot_v1(
      NULL, 'active-reader', project_id, baseline_snapshot_id
    );
    RAISE EXCEPTION '6BI accepted a NULL issuer';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1', '', project_id,
      baseline_snapshot_id
    );
    RAISE EXCEPTION '6BI accepted an empty subject';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1', 'active-reader', NULL,
      baseline_snapshot_id
    );
    RAISE EXCEPTION '6BI accepted a NULL project';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_data.read_authorized_management_original_region_report_snapshot_v1(
      'https://runtime-original.synthetic/auth/v1', 'active-reader', project_id,
      NULL
    );
    RAISE EXCEPTION '6BI accepted a NULL snapshot';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- The bridge is the only runtime entry point. Direct identity/private access
  -- must fail even inside the same database session.
  BEGIN
    PERFORM count(*) FROM app_data.external_identities;
    RAISE EXCEPTION '6BI runtime can read external identities directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.read_authorized_management_original_region_report_snapshot_v1(
      '6b810000-0000-4000-8000-000000000002'::uuid,
      project_id,
      baseline_snapshot_id
    );
    RAISE EXCEPTION '6BI runtime can execute the private original-region read';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

END
$fixture_6bi_runtime$;

RESET ROLE;

DO $fixture_6bi_audit$
DECLARE
  viewer_id constant uuid := '6b810000-0000-4000-8000-000000000002';
  history_text text;
BEGIN
  -- Identity failures and strict argument failures happen before private
  -- authorization, so only the six result-bearing bridge calls append audit.
  IF (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_access_events
    WHERE requested_by_app_user_id = viewer_id
  ) <> 6
    OR (
      SELECT count(*)
      FROM app_private.management_original_region_report_snapshot_access_events
      WHERE requested_by_app_user_id = viewer_id
        AND result_status = 'completed'
    ) <> 3
    OR (
      SELECT count(*)
      FROM app_private.management_original_region_report_snapshot_access_events
      WHERE requested_by_app_user_id = viewer_id
        AND result_status = 'not_found'
    ) <> 2
    OR (
      SELECT count(*)
      FROM app_private.management_original_region_report_snapshot_access_events
      WHERE requested_by_app_user_id = viewer_id
        AND result_status = 'untrusted_provenance'
    ) <> 1
  THEN
    RAISE EXCEPTION '6BI runtime audit status counts are incorrect';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_original_region_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id = viewer_id;
  IF history_text ~
    '(protected_report|cells|value_count|privacy_status|contact_id|revision_number|contributor|source_id|place_name|canonical_name|latitude|longitude|geometry|email|phone|token)'
  THEN
    RAISE EXCEPTION '6BI runtime audit retained protected values';
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
    RAISE EXCEPTION '6BI untrusted runtime audit retained source evidence';
  END IF;
END
$fixture_6bi_audit$;

ROLLBACK;
