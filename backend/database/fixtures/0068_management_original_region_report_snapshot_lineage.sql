-- Synthetic rollback fixture for Slice 6BG.
--
-- The fixture recreates the private 6BD original-region report because the
-- preceding 0066 fixture is rolled back in its own psql process.  It proves
-- that original source-tree lineage can be released into the shared snapshot
-- store without becoming a current-city, interest or channel release.  All
-- rows created here are rolled back.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b910000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b910000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b910000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name
) VALUES (
  '6b920000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BG original-region snapshot workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6b930000-0000-4000-8000-000000000001'::uuid,
    '6b920000-0000-4000-8000-000000000001'::uuid,
    '6BG original-region snapshot project'
  ),
  (
    '6b930000-0000-4000-8000-000000000002'::uuid,
    '6b920000-0000-4000-8000-000000000001'::uuid,
    '6BG empty negative project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES
  (
    '6b940000-0000-4000-8000-000000000001'::uuid,
    '6b930000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    '6b940000-0000-4000-8000-000000000002'::uuid,
    '6b930000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '6b960000-0000-4000-8000-000000000001'::uuid,
  '6b920000-0000-4000-8000-000000000001'::uuid,
  '6b910000-0000-4000-8000-000000000001'::uuid,
  clock_timestamp() - interval '30 days',
  NULL
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
    '6b970000-0000-4000-8000-000000000001'::uuid,
    '6b960000-0000-4000-8000-000000000001'::uuid,
    '6b930000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b970000-0000-4000-8000-000000000002'::uuid,
    '6b960000-0000-4000-8000-000000000001'::uuid,
    '6b930000-0000-4000-8000-000000000002'::uuid,
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
    '6b980000-0000-4000-8000-000000000001'::uuid,
    '6b970000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b980000-0000-4000-8000-000000000002'::uuid,
    '6b970000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b950000-0000-4000-8000-000000000001'::uuid,
  '6b910000-0000-4000-8000-000000000001'::uuid,
  '6b930000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b950000-0000-4000-8000-000000000002'::uuid,
  '6b910000-0000-4000-8000-000000000001'::uuid,
  '6b930000-0000-4000-8000-000000000002'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6bg_report_context AS
WITH fixed_cutoff AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  fixed_cutoff.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', fixed_cutoff.data_cutoff_utc
  ) AS periods
FROM fixed_cutoff;

-- The source tree is the only tuple consumed by 0066.  The target tree and a
-- valid mapping intentionally coexist to prove that original mode does not
-- consult current selection, target mapping or display-name matches.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
)
VALUES
  ('fixture-6bg-original-v1', 'draft', false),
  ('fixture-6bg-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6bg-original-country', 'fixture-6bg-original-v1', NULL,
    '6BG Source Country', 'country'),
  ('fixture-6bg-original-city-a', 'fixture-6bg-original-v1',
    'fixture-6bg-original-country', '6BG City A', 'city'),
  ('fixture-6bg-original-city-b', 'fixture-6bg-original-v1',
    'fixture-6bg-original-country', '6BG City B', 'city'),
  ('fixture-6bg-original-city-c', 'fixture-6bg-original-v1',
    'fixture-6bg-original-country', '6BG City C', 'city'),
  ('fixture-6bg-original-venue-a', 'fixture-6bg-original-v1',
    'fixture-6bg-original-city-a', '6BG Venue A', 'venue'),
  ('fixture-6bg-original-venue-b', 'fixture-6bg-original-v1',
    'fixture-6bg-original-city-b', '6BG Venue B', 'venue'),
  ('fixture-6bg-original-venue-c', 'fixture-6bg-original-v1',
    'fixture-6bg-original-city-c', '6BG Venue C', 'venue'),
  ('fixture-6bg-target-country', 'fixture-6bg-target-v1', NULL,
    '6BG Source Country', 'country'),
  ('fixture-6bg-target-city-a', 'fixture-6bg-target-v1',
    'fixture-6bg-target-country', '6BG City A', 'city'),
  ('fixture-6bg-target-venue-a', 'fixture-6bg-target-v1',
    'fixture-6bg-target-city-a', '6BG Venue A', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES
  (
    'fixture-6bg-original-city-a-boundary',
    'fixture-6bg-original-city-a', 'fixture-6bg-original-v1',
    polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
  ),
  (
    'fixture-6bg-original-city-b-boundary',
    'fixture-6bg-original-city-b', 'fixture-6bg-original-v1',
    polygon '((-87.90,41.60),(-87.80,41.60),(-87.80,41.70),(-87.90,41.70))'
  ),
  (
    'fixture-6bg-original-city-c-boundary',
    'fixture-6bg-original-city-c', 'fixture-6bg-original-v1',
    polygon '((-87.80,41.60),(-87.70,41.60),(-87.70,41.70),(-87.80,41.70))'
  ),
  (
    'fixture-6bg-target-city-a-boundary',
    'fixture-6bg-target-city-a', 'fixture-6bg-target-v1',
    polygon '((-87.70,41.60),(-87.60,41.60),(-87.60,41.70),(-87.70,41.70))'
  );

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bg-original-v1', false
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bg-target-v1', true
);

CREATE TEMP TABLE fixture_6bg_fingerprints AS
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6bg-original-v1'
  ) AS original_fingerprint,
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6bg-target-v1'
  ) AS target_fingerprint
FROM app_data.canonical_region_tree_releases;

SELECT app_private.register_canonical_region_version_mapping_v1(
  '6b990000-0000-4000-8000-000000000001'::uuid,
  'fixture-6bg-original-v1', 'fixture-6bg-original-venue-a',
  fingerprints.original_fingerprint,
  'fixture-6bg-target-v1', 'fixture-6bg-target-venue-a',
  fingerprints.target_fingerprint, repeat('b', 64)
)
FROM fixture_6bg_fingerprints AS fingerprints;

CREATE TEMP TABLE fixture_6bg_contact_plan AS
SELECT
  format(
    'fixture-6bg-%s-%s-c%s-u%s',
    period_row.period_key, city_row.city_key,
    contributor_row.contributor_number, unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  city_row.city_key,
  contributor_row.contributor_number,
  CASE contributor_row.contributor_number
    WHEN 1 THEN '6b910000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6b910000-0000-4000-8000-000000000002'::uuid
    ELSE '6b910000-0000-4000-8000-000000000003'::uuid
  END AS contributor_id,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 day'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 day'
  END AS occurred_at_utc,
  CASE city_row.city_key
    WHEN 'a' THEN 1
    WHEN 'b' THEN 2
    ELSE 3
  END AS city_number
FROM fixture_6bg_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES ('a'), ('b'), ('c')) AS city_row(city_key)
JOIN (
  VALUES
    ('a', 1, 5), ('a', 2, 3), ('a', 3, 2),
    ('b', 1, 5), ('b', 2, 3), ('b', 3, 2),
    ('c', 1, 5), ('c', 2, 2), ('c', 3, 2)
) AS contributor_row(city_key, contributor_number, unit_count)
  ON contributor_row.city_key = city_row.city_key
CROSS JOIN LATERAL generate_series(
  1,
  CASE
    WHEN period_row.period_key = 'previous'
      AND city_row.city_key = 'c'
      THEN contributor_row.unit_count
    ELSE contributor_row.unit_count +
      CASE WHEN city_row.city_key = 'c' AND contributor_row.contributor_number = 2
        THEN 1 ELSE 0 END
  END
) AS unit_row(unit_number);

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, place_name,
  smallest_region_id, region_tree_version, reach_count, interest_level
)
SELECT
  plan.contact_id,
  plan.contributor_id,
  '6b920000-0000-4000-8000-000000000001'::uuid,
  '6b930000-0000-4000-8000-000000000001'::uuid,
  '6b940000-0000-4000-8000-000000000001'::uuid,
  plan.occurred_at_utc, 'UTC', plan.occurred_at_utc,
  'face_to_face', 'resolved', '6BG source venue',
  format('fixture-6bg-original-venue-%s', plan.city_key),
  'fixture-6bg-original-v1', 1, 2
FROM fixture_6bg_contact_plan AS plan;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind,
  revised_by_app_user_id, snapshot
)
SELECT
  plan.contact_id, 1, 'submitted', plan.contributor_id,
  jsonb_build_object(
    'contactId', plan.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', '6BG source venue',
      'smallestRegionId', format('fixture-6bg-original-venue-%s', plan.city_key),
      'regionTreeVersion', 'fixture-6bg-original-v1'
    )
  )
FROM fixture_6bg_contact_plan AS plan;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id,
  revision_number, change_type
)
VALUES (
  '6b910000-0000-4000-8000-000000000001'::uuid,
  '6b920000-0000-4000-8000-000000000001'::uuid,
  '6b930000-0000-4000-8000-000000000001'::uuid,
  'fixture-6bg-original-watermark', 1, 'contact.submitted'
);

DO $fixture_6bg_lineage$
DECLARE
  fixture_project_id constant uuid :=
    '6b930000-0000-4000-8000-000000000001';
  fixture_project_two constant uuid :=
    '6b930000-0000-4000-8000-000000000002';
  fixture_owner_id constant uuid :=
    '6b910000-0000-4000-8000-000000000001';
  report_id constant text := 'contact_sessions_by_original_region_two_periods';
  baseline_document jsonb;
  later_document jsonb;
  mutated_document jsonb;
  release_result jsonb;
  replay_result jsonb;
  pair_result jsonb;
  blocked_result jsonb;
  baseline_snapshot_id uuid;
  snapshot_count bigint;
  attempt_count bigint;
  failure_sqlstate text;
  failure_message text;
  attempt_audit text;
  blocked_attempt_audit text;
  source_fingerprint text;
  item jsonb;
BEGIN
  SELECT original_fingerprint INTO STRICT source_fingerprint
  FROM fixture_6bg_fingerprints;

  baseline_document :=
    app_private.execute_management_original_region_contact_session_report_v1(
      fixture_project_id, 'UTC',
      (SELECT data_cutoff_utc FROM fixture_6bg_report_context)
    );
  PERFORM app_private.validate_management_original_region_report_document_v1(
    baseline_document
  );

  IF baseline_document->>'report_id' IS DISTINCT FROM report_id
    OR baseline_document->>'report_version' IS DISTINCT FROM '1'
    OR baseline_document->>'metric_id' IS DISTINCT FROM 'contact_sessions'
    OR baseline_document->>'dimension' IS DISTINCT FROM 'original_region'
    OR baseline_document->>'view_mode' IS DISTINCT FROM 'original'
    OR baseline_document->>'region_granularity' IS DISTINCT FROM 'city'
    OR baseline_document->>'result_status' IS DISTINCT FROM 'completed'
    OR jsonb_array_length(baseline_document->'cells') <> 6
    OR baseline_document->'source_tree_context'->>'source_tree_version'
      IS DISTINCT FROM 'fixture-6bg-original-v1'
    OR baseline_document->'source_tree_context'->>'source_content_fingerprint'
      IS DISTINCT FROM source_fingerprint
  THEN
    RAISE EXCEPTION '6BG original report document identity is wrong: %',
      baseline_document;
  END IF;

  IF baseline_document::text ~
      '(contact_id|revision_number|contributor_key|source_id|place_name|latitude|longitude|geometry|fixture-6bg-target)'
  THEN
    RAISE EXCEPTION '6BG original report leaked source or target details';
  END IF;

  -- The original source report has three cities and two periods. City C in
  -- the previous period is below k; deterministic complementary hiding also
  -- suppresses the first otherwise-displayable city in that period. Every
  -- remaining cell is a safe three-contributor count of ten.
  IF baseline_document->'cells' <> jsonb_build_array(
    jsonb_build_object(
      'period_key', 'previous', 'city_id', 'fixture-6bg-original-city-a',
      'cell_order', 0, 'value_count', NULL, 'privacy_status', 'suppressed'
    ),
    jsonb_build_object(
      'period_key', 'previous', 'city_id', 'fixture-6bg-original-city-b',
      'cell_order', 1, 'value_count', 10, 'privacy_status', 'displayed'
    ),
    jsonb_build_object(
      'period_key', 'previous', 'city_id', 'fixture-6bg-original-city-c',
      'cell_order', 2, 'value_count', NULL, 'privacy_status', 'suppressed'
    ),
    jsonb_build_object(
      'period_key', 'current', 'city_id', 'fixture-6bg-original-city-a',
      'cell_order', 3, 'value_count', 10, 'privacy_status', 'displayed'
    ),
    jsonb_build_object(
      'period_key', 'current', 'city_id', 'fixture-6bg-original-city-b',
      'cell_order', 4, 'value_count', 10, 'privacy_status', 'displayed'
    ),
    jsonb_build_object(
      'period_key', 'current', 'city_id', 'fixture-6bg-original-city-c',
      'cell_order', 5, 'value_count', 10, 'privacy_status', 'displayed'
    )
  )
  THEN
    RAISE EXCEPTION '6BG original privacy grid is incorrect: %',
      baseline_document->'cells';
  END IF;

  -- Same-cutoff pair is never a valid successor.
  pair_result :=
    app_private.assess_management_original_region_report_pair_release_v1(
      baseline_document, baseline_document
    );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'release_lineage_context_changed')
  THEN
    RAISE EXCEPTION '6BG same-cutoff pair was not blocked: %', pair_result;
  END IF;

  release_result :=
    app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000001'::uuid,
      fixture_owner_id, fixture_project_id, report_id, 1
    );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR release_result->>'released_snapshot_id' IS NULL
    OR release_result ? 'protected_report'
    OR release_result ? 'cells'
  THEN
    RAISE EXCEPTION '6BG baseline release is not value-free: %', release_result;
  END IF;
  baseline_snapshot_id := (release_result->>'released_snapshot_id')::uuid;

  SELECT snapshot.protected_report INTO STRICT mutated_document
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;
  -- The release function takes its authorization reference after acquiring
  -- the request/time-zone/lineage locks.  Recreate that exact candidate cutoff
  -- before comparing the immutable protected document; the earlier fixture
  -- context is intentionally only a shape/privacy probe.
  later_document :=
    app_private.execute_management_original_region_contact_session_report_v1(
      fixture_project_id, 'UTC',
      (release_result->>'data_cutoff_utc')::timestamptz
    );
  PERFORM app_private.validate_management_original_region_report_document_v1(
    later_document
  );
  IF (mutated_document - ARRAY['data_cutoff_utc', 'periods'])
      IS DISTINCT FROM (later_document - ARRAY['data_cutoff_utc', 'periods'])
    OR ((mutated_document->'periods') - 'data_cutoff_utc'::text)
      IS DISTINCT FROM
        ((later_document->'periods') - 'data_cutoff_utc'::text)
  THEN
    RAISE EXCEPTION '6BG stored baseline differs from source document';
  END IF;

  SELECT attempt.result_document::text INTO STRICT attempt_audit
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b980000-0000-4000-8000-000000000001'::uuid;
  IF attempt_audit ~
      '(protected_report|cells|contact_id|contributor|source_id|latitude|longitude|geometry|place_name|fixture-6bg-original-venue)'
  THEN
    RAISE EXCEPTION '6BG baseline attempt leaked protected values: %', attempt_audit;
  END IF;

  replay_result :=
    app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000001'::uuid,
      fixture_owner_id, fixture_project_id, report_id, 1
    );
  IF replay_result IS DISTINCT FROM release_result THEN
    RAISE EXCEPTION '6BG same-request replay changed its envelope';
  END IF;

  PERFORM pg_sleep(0.01);
  release_result :=
    app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000002'::uuid,
      fixture_owner_id, fixture_project_id, report_id, 1
    );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved'
    OR (release_result->>'compared_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
    OR release_result->>'released_snapshot_id' IS NULL
    OR release_result ? 'protected_report'
    OR release_result ? 'cells'
  THEN
    RAISE EXCEPTION '6BG rolling release lost its previous pointer: %',
      release_result;
  END IF;

  snapshot_count := (
    SELECT count(*)
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.project_id = fixture_project_id
      AND snapshot.release_lineage_id =
        'management-original-region-report:contact_sessions_by_original_region_two_periods'
  );
  attempt_count := (
    SELECT count(*)
    FROM app_private.management_original_region_report_release_attempts AS attempt
    WHERE attempt.project_id = fixture_project_id
  );
  IF snapshot_count <> 2 OR attempt_count <> 2 THEN
    RAISE EXCEPTION '6BG approved history count is wrong: %/%',
      snapshot_count, attempt_count;
  END IF;

  -- A displayed value change remains a valid candidate document but cannot be
  -- appended to the same lineage.
  SELECT jsonb_set(
    baseline_document,
    ARRAY['cells', (cell_index - 1)::text, 'value_count'],
    to_jsonb((cell->>'value_count')::integer + 1)
  )
  INTO STRICT mutated_document
  FROM jsonb_array_elements(baseline_document->'cells')
    WITH ORDINALITY AS candidate(cell, cell_index)
  WHERE cell->>'privacy_status' = 'displayed'
  ORDER BY cell_index
  LIMIT 1;
  PERFORM app_private.validate_management_original_region_report_document_v1(
    mutated_document
  );
  pair_result :=
    app_private.assess_management_original_region_report_pair_release_v1(
      baseline_document, mutated_document
    );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'shared_displayed_value_changed')
  THEN
    RAISE EXCEPTION '6BG displayed value drift was not blocked: %', pair_result;
  END IF;

  -- Watermark and source tuple are independent guards.
  mutated_document := jsonb_set(
    baseline_document, '{source_change_sequence}',
    to_jsonb((baseline_document->>'source_change_sequence')::bigint - 1)
  );
  pair_result :=
    app_private.assess_management_original_region_report_pair_release_v1(
      baseline_document, mutated_document
    );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked' THEN
    RAISE EXCEPTION '6BG source watermark regression was accepted: %', pair_result;
  END IF;

  mutated_document := jsonb_set(
    baseline_document,
    '{source_tree_context,source_content_fingerprint}',
    to_jsonb(repeat('f', 64))
  );
  BEGIN
    pair_result :=
      app_private.assess_management_original_region_report_pair_release_v1(
        baseline_document, mutated_document
      );
    RAISE EXCEPTION '6BG source tuple drift was accepted: %', pair_result;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    IF SQLERRM <> 'original region source tree release is unavailable' THEN
      RAISE;
    END IF;
  END;

  -- A privacy transition on a shared cell is also a blocked successor. Keep
  -- the cell contract valid by changing the value to JSON null together with
  -- its privacy status.
  SELECT jsonb_set(
    jsonb_set(
      baseline_document,
      ARRAY['cells', (cell_index - 1)::text, 'privacy_status'],
      to_jsonb('suppressed'::text)
    ),
    ARRAY['cells', (cell_index - 1)::text, 'value_count'],
    'null'::jsonb
  )
  INTO STRICT mutated_document
  FROM jsonb_array_elements(baseline_document->'cells')
    WITH ORDINALITY AS candidate(cell, cell_index)
  WHERE cell->>'privacy_status' = 'displayed'
  ORDER BY cell_index
  LIMIT 1;
  PERFORM app_private.validate_management_original_region_report_document_v1(
    mutated_document
  );
  pair_result :=
    app_private.assess_management_original_region_report_pair_release_v1(
      baseline_document, mutated_document
    );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'shared_cell_privacy_status_changed')
  THEN
    RAISE EXCEPTION '6BG privacy drift was not blocked: %', pair_result;
  END IF;

  -- No shared period is a value-free blocked pair.
  mutated_document :=
    app_private.execute_management_original_region_contact_session_report_v1(
      fixture_project_id, 'UTC',
      (SELECT data_cutoff_utc FROM fixture_6bg_report_context)
        + interval '15 days'
    );
  later_document := jsonb_set(
    jsonb_set(
      baseline_document, '{periods}', mutated_document->'periods'
    ),
    '{data_cutoff_utc}', mutated_document->'data_cutoff_utc'
  );
  pair_result :=
    app_private.assess_management_original_region_report_pair_release_v1(
      baseline_document, later_document
    );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'no_shared_period')
  THEN
    RAISE EXCEPTION '6BG no-shared-period pair was not blocked: %', pair_result;
  END IF;

  -- An empty authorized project produces no snapshot and no protected values.
  blocked_result :=
    app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000003'::uuid,
      fixture_owner_id, fixture_project_two, report_id, 1
    );
  IF blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR blocked_result->>'released_snapshot_id' IS NOT NULL
    OR blocked_result ? 'protected_report'
    OR blocked_result ? 'cells'
    OR NOT (blocked_result->'reason_codes' ? 'release_source_tree_unavailable')
  THEN
    RAISE EXCEPTION '6BG unavailable source did not fail closed: %',
      blocked_result;
  END IF;

  SELECT attempt.result_document::text INTO STRICT blocked_attempt_audit
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b980000-0000-4000-8000-000000000003'::uuid;
  IF blocked_attempt_audit ~ (
      '(protected_report|cells|hidden|source_key|source_id|contact_id|'
      || 'contributor|place_name|canonical_name|latitude|longitude|geometry|'
      || 'email|phone|token|fixture-6bg-original-venue)'
  ) THEN
    RAISE EXCEPTION
      '6BG blocked attempt leaked protected values: %', blocked_attempt_audit;
  END IF;

  -- A non-member cannot reach the release seam and must not create history.
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000004'::uuid,
      '6b910000-0000-4000-8000-000000000002'::uuid,
      fixture_project_id, report_id, 1
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'unauthorized release passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '42501'
    OR failure_message IS DISTINCT FROM
      'management report authorization forbidden'
  THEN
    RAISE EXCEPTION 'unauthorized release failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;

  -- The same request UUID cannot move to a different project.
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000001'::uuid,
      fixture_owner_id, fixture_project_two, report_id, 1
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'cross-project replay passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '22023'
    OR failure_message IS DISTINCT FROM
      'original region report release idempotency conflict'
  THEN
    RAISE EXCEPTION 'cross-project replay failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;

  -- A request claim owned by another release family cannot be reused.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    '6b980000-0000-4000-8000-000000000009'::uuid,
    'channel_management_report_snapshot_release'
  );
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000009'::uuid,
      fixture_owner_id, fixture_project_id, report_id, 1
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'family reuse passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '22023'
    OR failure_message IS DISTINCT FROM
      'release request id was already used by another report contract'
  THEN
    RAISE EXCEPTION 'request-family reuse failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;

  -- A new reporting-time-zone version after the first release is an explicit
  -- lineage break. The release is audited as blocked and creates no second
  -- snapshot until a later contract deliberately handles the revision.
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '6b950000-0000-4000-8000-000000000003'::uuid,
    fixture_owner_id,
    fixture_project_id,
    1, 'America/Chicago', clock_timestamp() - interval '12 days'
  );
  blocked_result :=
    app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000010'::uuid,
      fixture_owner_id, fixture_project_id, report_id, 1
    );
  IF blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR blocked_result->>'released_snapshot_id' IS NOT NULL
    OR NOT (blocked_result->'reason_codes' ? 'release_time_zone_revision_changed')
  THEN
    RAISE EXCEPTION '6BG time-zone revision was not blocked: %', blocked_result;
  END IF;

  -- A reportable candidate with missing source provenance must become the
  -- same value-free blocked result. The source-invalid row has no provenance
  -- revision by design; it is rolled back with the fixture. Keep this after
  -- the time-zone revision check so it cannot affect that release lineage.
  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    first_submitted_at_utc, channel, location_kind, place_name,
    smallest_region_id, region_tree_version, reach_count, interest_level
  ) VALUES (
    'fixture-6bg-invalid-source', fixture_owner_id,
    '6b920000-0000-4000-8000-000000000001'::uuid,
    fixture_project_two,
    '6b940000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '1 minute', 'UTC',
    clock_timestamp() - interval '1 minute',
    'face_to_face', 'resolved', '6BG invalid source venue',
    'fixture-6bg-original-venue-a', 'fixture-6bg-original-v1', 1, 2
  );
  blocked_result :=
    app_private.release_management_original_region_report_snapshot_v1(
      '6b980000-0000-4000-8000-000000000011'::uuid,
      fixture_owner_id, fixture_project_two, report_id, 1
    );
  IF blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR blocked_result->>'released_snapshot_id' IS NOT NULL
    OR blocked_result ? 'protected_report'
    OR blocked_result ? 'cells'
    OR NOT (blocked_result->'reason_codes' ?
      'release_source_tree_unavailable')
  THEN
    RAISE EXCEPTION
      '6BG source-invalid release did not fail closed: %', blocked_result;
  END IF;
  SELECT attempt.result_document::text INTO STRICT blocked_attempt_audit
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b980000-0000-4000-8000-000000000011'::uuid;
  IF blocked_attempt_audit ~ (
      '(protected_report|cells|hidden|source_key|source_id|contact_id|'
      || 'contributor|place_name|canonical_name|latitude|longitude|geometry|'
      || 'email|phone|token|fixture-6bg-invalid-source|'
      || 'fixture-6bg-original-venue)'
  ) THEN
    RAISE EXCEPTION
      '6BG source-invalid blocked attempt leaked protected values: %',
      blocked_attempt_audit;
  END IF;

  -- History and request claims are append-only.
  BEGIN
    UPDATE app_private.management_report_snapshots
    SET query_fingerprint = 'tampered'
    WHERE snapshot_id = baseline_snapshot_id;
    RAISE EXCEPTION '6BG snapshot accepted UPDATE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    DELETE FROM app_private.management_original_region_report_release_attempts
    WHERE release_request_id =
      '6b980000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6BG attempt accepted DELETE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    UPDATE app_private.management_report_release_request_claims
    SET release_family_id = 'interest_management_report_snapshot_release'
    WHERE release_request_id =
      '6b980000-0000-4000-8000-000000000009'::uuid;
    RAISE EXCEPTION '6BG request claim accepted UPDATE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;

  -- Cross-family writer scope: current-city writer cannot see or insert an
  -- original snapshot even though the physical store is shared.
  CREATE TEMP TABLE fixture_6bg_original_snapshot_row ON COMMIT DROP AS
  SELECT snapshot.*
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;
  GRANT SELECT ON fixture_6bg_original_snapshot_row
    TO tongxingzhe_management_current_city_snapshot_release_writer;
  SET LOCAL ROLE tongxingzhe_management_current_city_snapshot_release_writer;
  IF EXISTS (
    SELECT 1 FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.report_id =
      'contact_sessions_by_original_region_two_periods'
  ) THEN
    RAISE EXCEPTION 'current-city writer can read original snapshot';
  END IF;
  BEGIN
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
    )
    SELECT
      '6b9a0000-0000-4000-8000-000000000001'::uuid,
      '6b9a0000-0000-4000-8000-000000000002'::uuid,
      copied.created_by_app_user_id,
      copied.project_id,
      copied.release_lineage_id,
      copied.report_id,
      copied.report_version,
      copied.query_fingerprint,
      copied.reporting_time_zone,
      copied.data_cutoff_utc,
      copied.released_at_utc,
      copied.previous_snapshot_id,
      copied.source_change_sequence,
      copied.protected_report
    FROM fixture_6bg_original_snapshot_row AS copied;
    RAISE EXCEPTION 'current-city writer can insert original snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  RESET ROLE;

  IF coalesce(attempt_audit, '') ~
      '(protected_report|cells|contact_id|contributor|source_id|latitude|longitude|geometry)'
  THEN
    RAISE EXCEPTION '6BG release audit contains protected values';
  END IF;
END
$fixture_6bg_lineage$;

ROLLBACK;
