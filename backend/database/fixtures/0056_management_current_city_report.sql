-- Synthetic fixture for the DB-only current-city management report.
-- All rows are rolled back. No production data or external region source is used.
\set ON_ERROR_STOP on

BEGIN;

DO $contract_fixture$
DECLARE
  canonical_document jsonb;
  protected_cells jsonb;
  threshold_cells jsonb;
  invalid_request jsonb;
BEGIN
  canonical_document =
    app_private.canonicalize_management_current_city_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 1
      )
    );

  IF canonical_document <> jsonb_build_object(
    'report_id', 'contact_sessions_by_current_city_two_periods',
    'report_version', 1,
    'metric_id', 'contact_sessions',
    'metric_version', 1,
    'dimension', 'current_city',
    'view_mode', 'current',
    'region_granularity', 'city',
    'period_grain', 'week',
    'comparison_period_count', 2,
    'period_boundary_id', 'iso_week_monday_v1',
    'privacy_policy', 'management_current_city_contact_session_privacy_v1',
    'required_capability', 'view_anonymous_analytics',
    'query_fingerprint',
      'management-report:contact_sessions_by_current_city_two_periods:v1'
  ) THEN
    RAISE EXCEPTION 'current-city report canonical document is incorrect: %',
      canonical_document;
  END IF;

  BEGIN
    PERFORM app_private.canonicalize_management_current_city_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 1,
        'city_ids', jsonb_build_array('fixture-city-a')
      )
    );
    RAISE EXCEPTION 'current-city canonicalizer accepted an arbitrary city list';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  FOR invalid_request IN
    SELECT request.item
    FROM jsonb_array_elements(jsonb_build_array(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 0
      ),
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 2
      ),
      jsonb_build_object(
        'report_id', 'contact_sessions_by_channel_two_periods',
        'report_version', 1
      )
    )) AS request(item)
  LOOP
    BEGIN
      PERFORM
        app_private.canonicalize_management_current_city_report_request_v1(
          invalid_request
        );
      RAISE EXCEPTION 'current-city canonicalizer accepted %', invalid_request;
    EXCEPTION WHEN invalid_parameter_value THEN
      NULL;
    END;
  END LOOP;

  BEGIN
    PERFORM app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
        'report_version', 1
      )
    );
    RAISE EXCEPTION 'legacy channel canonicalizer accepted current-city report';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'city_id', protected.city_id,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  )
  INTO protected_cells
  FROM app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb_build_array(
      'fixture-city-a',
      'fixture-city-b',
      'fixture-city-c',
      'fixture-city-d'
    ),
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'period_key', contribution.period_key,
          'city_id', contribution.city_id,
          'contributor_key', contribution.contributor_key,
          'unit_count', contribution.unit_count
        ) ORDER BY
          contribution.period_key,
          contribution.city_id,
          contribution.contributor_key
      )
      FROM (
        VALUES
          ('previous', 'fixture-city-a', 'contributor-a', 5),
          ('previous', 'fixture-city-a', 'contributor-b', 3),
          ('previous', 'fixture-city-a', 'contributor-c', 2),
          ('previous', 'fixture-city-b', 'contributor-a', 5),
          ('previous', 'fixture-city-b', 'contributor-b', 3),
          ('previous', 'fixture-city-b', 'contributor-c', 2),
          ('current', 'fixture-city-a', 'contributor-a', 5),
          ('current', 'fixture-city-a', 'contributor-b', 3),
          ('current', 'fixture-city-a', 'contributor-c', 2),
          ('current', 'fixture-city-b', 'contributor-a', 5),
          ('current', 'fixture-city-b', 'contributor-b', 3),
          ('current', 'fixture-city-b', 'contributor-c', 2),
          ('current', 'fixture-city-d', 'contributor-a', 5),
          ('current', 'fixture-city-d', 'contributor-b', 3),
          ('current', 'fixture-city-d', 'contributor-c', 2)
      ) AS contribution(
        period_key,
        city_id,
        contributor_key,
        unit_count
      )
    )
  ) AS protected;

  IF jsonb_array_length(protected_cells) <> 8
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'previous'
        AND item->>'privacy_status' = 'displayed'
        AND item->>'value_count' = '10'
    ) <> 2
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'previous'
        AND item->>'privacy_status' = 'suppressed'
        AND item->'value_count' = 'null'::jsonb
    ) <> 2
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'privacy_status' = 'displayed'
        AND item->>'value_count' = '10'
    ) <> 2
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'privacy_status' = 'suppressed'
        AND item->'value_count' = 'null'::jsonb
    ) <> 2
  THEN
    RAISE EXCEPTION 'current-city primary or complementary suppression failed: %',
      protected_cells;
  END IF;

  IF (
      SELECT item->>'privacy_status'
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'city_id' = 'fixture-city-a'
    ) IS DISTINCT FROM 'suppressed'
    OR (
      SELECT item->>'privacy_status'
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'city_id' = 'fixture-city-b'
    ) IS DISTINCT FROM 'displayed'
    OR (
      SELECT item->>'privacy_status'
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'city_id' = 'fixture-city-c'
    ) IS DISTINCT FROM 'suppressed'
    OR (
      SELECT item->>'privacy_status'
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'city_id' = 'fixture-city-d'
    ) IS DISTINCT FROM 'displayed'
  THEN
    RAISE EXCEPTION
      'single primary suppression did not hide the first displayable city: %',
      protected_cells;
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'city_id', protected.city_id,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  )
  INTO threshold_cells
  FROM app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb_build_array(
      'fixture-threshold-city-a',
      'fixture-threshold-city-b',
      'fixture-threshold-city-c',
      'fixture-threshold-city-d'
    ),
    jsonb_build_array(
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-a', 'contributor_key', 'a1', 'unit_count', 4),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-a', 'contributor_key', 'a2', 'unit_count', 3),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-a', 'contributor_key', 'a3', 'unit_count', 2),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-b', 'contributor_key', 'b1', 'unit_count', 5),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-b', 'contributor_key', 'b2', 'unit_count', 5),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-c', 'contributor_key', 'c1', 'unit_count', 6),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-c', 'contributor_key', 'c2', 'unit_count', 2),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-c', 'contributor_key', 'c3', 'unit_count', 2),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-d', 'contributor_key', 'd1', 'unit_count', 5),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-d', 'contributor_key', 'd2', 'unit_count', 3),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-threshold-city-d', 'contributor_key', 'd3', 'unit_count', 2)
    )
  ) AS protected;

  IF (
      SELECT count(*)
      FROM jsonb_array_elements(threshold_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'privacy_status' = 'suppressed'
        AND item->>'city_id' IN (
          'fixture-threshold-city-a',
          'fixture-threshold-city-b',
          'fixture-threshold-city-c'
        )
    ) <> 3
    OR (
      SELECT item->>'value_count'
      FROM jsonb_array_elements(threshold_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'city_id' = 'fixture-threshold-city-d'
        AND item->>'privacy_status' = 'displayed'
    ) IS DISTINCT FROM '10'
  THEN
    RAISE EXCEPTION
      'k, contributor count, or maximum contribution threshold failed: %',
      threshold_cells;
  END IF;

  IF (
    SELECT array_agg((item->>'cell_order')::integer ORDER BY ordinal)
    FROM jsonb_array_elements(protected_cells)
      WITH ORDINALITY AS cell(item, ordinal)
  ) <> ARRAY[0, 1, 2, 3, 4, 5, 6, 7]
  THEN
    RAISE EXCEPTION 'current-city protected cell order is unstable';
  END IF;

  BEGIN
    PERFORM *
    FROM app_private.protect_management_current_city_contact_session_grid_v1(
      jsonb_build_array('fixture-city-a', 'fixture-city-a'),
      '[]'::jsonb
    );
    RAISE EXCEPTION 'duplicate city grid entry was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_private.protect_management_current_city_contact_session_grid_v1(
      jsonb_build_array('fixture-city-a'),
      jsonb_build_array(jsonb_build_object(
        'period_key', 'current',
        'city_id', 'fixture-city-outside-grid',
        'contributor_key', 'contributor-a',
        'unit_count', 10
      ))
    );
    RAISE EXCEPTION 'contribution outside the complete city grid was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$contract_fixture$;

-- End-to-end synthetic project, region releases, sources and contacts follow.
-- The fixture is intentionally in one transaction so published selections and
-- every generated provenance row disappear at ROLLBACK.

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6a110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6a110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6a110000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name
) VALUES (
  '6a120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AN synthetic management workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6a130000-0000-4000-8000-000000000001'::uuid,
    '6a120000-0000-4000-8000-000000000001'::uuid,
    '6AN current city report project'
  ),
  (
    '6a130000-0000-4000-8000-000000000002'::uuid,
    '6a120000-0000-4000-8000-000000000001'::uuid,
    '6AN other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES
  (
    '6a140000-0000-4000-8000-000000000001'::uuid,
    '6a130000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '6a140000-0000-4000-8000-000000000002'::uuid,
    '6a130000-0000-4000-8000-000000000002'::uuid,
    1,
    'published',
    true
  );

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
) VALUES
  ('fixture-6an-source-v1', 'draft', false),
  ('fixture-6an-target-v1', 'draft', false),
  ('fixture-6an-nested-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
) VALUES
  ('fixture-6an-source-country', 'fixture-6an-source-v1', NULL,
    'Source Country', 'country'),
  ('fixture-6an-source-city', 'fixture-6an-source-v1',
    'fixture-6an-source-country', 'Source City', 'city'),
  ('fixture-6an-source-coordinate', 'fixture-6an-source-v1',
    'fixture-6an-source-city', 'Source Coordinate Venue', 'venue'),
  ('fixture-6an-source-mapped', 'fixture-6an-source-v1',
    'fixture-6an-source-city', 'Source Mapped Venue', 'venue'),
  ('fixture-6an-source-unmapped', 'fixture-6an-source-v1',
    'fixture-6an-source-city', 'Source Unmapped Venue', 'venue'),
  ('fixture-6an-target-country', 'fixture-6an-target-v1', NULL,
    'Target Country', 'country'),
  ('fixture-6an-target-city-a', 'fixture-6an-target-v1',
    'fixture-6an-target-country', 'Target City A', 'city'),
  ('fixture-6an-target-city-b', 'fixture-6an-target-v1',
    'fixture-6an-target-country', 'Target City B', 'city'),
  ('fixture-6an-target-city-c', 'fixture-6an-target-v1',
    'fixture-6an-target-country', 'Target City C', 'city'),
  ('fixture-6an-target-city-d', 'fixture-6an-target-v1',
    'fixture-6an-target-country', 'Target City D', 'city'),
  ('fixture-6an-target-a-venue', 'fixture-6an-target-v1',
    'fixture-6an-target-city-a', 'Target A Venue', 'venue'),
  ('fixture-6an-target-b-venue', 'fixture-6an-target-v1',
    'fixture-6an-target-city-b', 'Target B Venue', 'venue'),
  ('fixture-6an-target-a-overlap', 'fixture-6an-target-v1',
    'fixture-6an-target-city-a', 'Target A Overlap Venue', 'venue'),
  ('fixture-6an-target-b-overlap', 'fixture-6an-target-v1',
    'fixture-6an-target-city-b', 'Target B Overlap Venue', 'venue'),
  ('fixture-6an-nested-country', 'fixture-6an-nested-v1', NULL,
    'Nested Country', 'country'),
  ('fixture-6an-nested-city-parent', 'fixture-6an-nested-v1',
    'fixture-6an-nested-country', 'Nested Parent City', 'city'),
  ('fixture-6an-nested-city-child', 'fixture-6an-nested-v1',
    'fixture-6an-nested-city-parent', 'Nested Child City', 'city'),
  ('fixture-6an-nested-venue', 'fixture-6an-nested-v1',
    'fixture-6an-nested-city-child', 'Nested Venue', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
) VALUES
  (
    'fixture-6an-source-boundary',
    'fixture-6an-source-coordinate',
    'fixture-6an-source-v1',
    polygon '((-88.00,41.60),(-87.50,41.60),(-87.50,42.00),(-88.00,42.00))'
  ),
  (
    'fixture-6an-target-a-boundary',
    'fixture-6an-target-a-venue',
    'fixture-6an-target-v1',
    polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'
  ),
  (
    'fixture-6an-target-b-boundary',
    'fixture-6an-target-b-venue',
    'fixture-6an-target-v1',
    polygon '((-87.61,41.69),(-87.59,41.69),(-87.59,41.71),(-87.61,41.71))'
  ),
  (
    'fixture-6an-target-a-overlap-boundary',
    'fixture-6an-target-a-overlap',
    'fixture-6an-target-v1',
    polygon '((-87.66,41.69),(-87.64,41.69),(-87.64,41.71),(-87.66,41.71))'
  ),
  (
    'fixture-6an-target-b-overlap-boundary',
    'fixture-6an-target-b-overlap',
    'fixture-6an-target-v1',
    polygon '((-87.66,41.69),(-87.64,41.69),(-87.64,41.71),(-87.66,41.71))'
  ),
  (
    'fixture-6an-nested-boundary',
    'fixture-6an-nested-venue',
    'fixture-6an-nested-v1',
    polygon '((-87.50,41.60),(-87.48,41.60),(-87.48,41.62),(-87.50,41.62))'
  );

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6an-source-v1',
  false
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6an-target-v1',
  true
);

CREATE TEMP TABLE fixture_6an_release_fingerprints AS
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6an-source-v1'
  ) AS source_fingerprint,
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6an-target-v1'
  ) AS target_fingerprint
FROM app_data.canonical_region_tree_releases;

SELECT app_private.register_canonical_region_version_mapping_v1(
  '6a150000-0000-4000-8000-000000000001'::uuid,
  'fixture-6an-source-v1',
  'fixture-6an-source-mapped',
  fingerprint.source_fingerprint,
  'fixture-6an-target-v1',
  'fixture-6an-target-b-venue',
  fingerprint.target_fingerprint,
  repeat('a', 64)
)
FROM fixture_6an_release_fingerprints AS fingerprint;

CREATE TEMP TABLE fixture_6an_report_context AS
SELECT
  '2030-04-17T12:00:00Z'::timestamptz AS data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC',
    '2030-04-17T12:00:00Z'::timestamptz
  ) AS periods;

CREATE TEMP TABLE fixture_6an_expected_contacts AS
SELECT
  format(
    'fixture-6an-%s-%s-u%s-%s',
    period_row.period_key,
    city_row.city_key,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  city_row.city_key,
  contributor_row.contributor_number,
  CASE
    WHEN city_row.city_key = 'a'
      AND contributor_row.contributor_number IN (2, 3)
      THEN 'coordinate'
    WHEN city_row.city_key = 'b'
      AND contributor_row.contributor_number IN (1, 2)
      THEN 'mapped'
    ELSE 'same_target'
  END AS evidence_kind,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 day'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 day'
  END AS occurred_at_utc
FROM fixture_6an_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES ('a'), ('b')) AS city_row(city_key)
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
  place_name,
  smallest_region_id,
  region_tree_version,
  reach_count,
  interest_level
)
SELECT
  expected.contact_id,
  CASE expected.contributor_number
    WHEN 1 THEN '6a110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6a110000-0000-4000-8000-000000000002'::uuid
    ELSE '6a110000-0000-4000-8000-000000000003'::uuid
  END,
  '6a120000-0000-4000-8000-000000000001'::uuid,
  '6a130000-0000-4000-8000-000000000001'::uuid,
  '6a140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc,
  'UTC',
  expected.occurred_at_utc,
  'face_to_face',
  'resolved',
  CASE expected.evidence_kind
    WHEN 'coordinate' THEN 'Private source coordinate venue'
    WHEN 'mapped' THEN 'Private source mapped venue'
    WHEN 'same_target' THEN 'Private target venue'
  END,
  CASE expected.evidence_kind
    WHEN 'coordinate' THEN 'fixture-6an-source-coordinate'
    WHEN 'mapped' THEN 'fixture-6an-source-mapped'
    WHEN 'same_target' THEN format(
      'fixture-6an-target-%s-venue',
      expected.city_key
    )
  END,
  CASE
    WHEN expected.evidence_kind = 'same_target'
      THEN 'fixture-6an-target-v1'
    ELSE 'fixture-6an-source-v1'
  END,
  1,
  2
FROM fixture_6an_expected_contacts AS expected;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  snapshot
)
SELECT
  expected.contact_id,
  1,
  'submitted',
  CASE expected.contributor_number
    WHEN 1 THEN '6a110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6a110000-0000-4000-8000-000000000002'::uuid
    ELSE '6a110000-0000-4000-8000-000000000003'::uuid
  END,
  jsonb_build_object(
    'contactId', expected.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', CASE expected.evidence_kind
        WHEN 'coordinate' THEN 'Private source coordinate venue'
        WHEN 'mapped' THEN 'Private source mapped venue'
        ELSE 'Private target venue'
      END,
      'smallestRegionId', CASE expected.evidence_kind
        WHEN 'coordinate' THEN 'fixture-6an-source-coordinate'
        WHEN 'mapped' THEN 'fixture-6an-source-mapped'
        ELSE format('fixture-6an-target-%s-venue', expected.city_key)
      END,
      'regionTreeVersion', CASE
        WHEN expected.evidence_kind = 'same_target'
          THEN 'fixture-6an-target-v1'
        ELSE 'fixture-6an-source-v1'
      END
    )
  ) || CASE
    WHEN expected.evidence_kind = 'coordinate' THEN jsonb_build_object(
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.70,
        'longitude', -87.80,
        'accuracyMeters', 5.0,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprint.source_fingerprint
      )
    )
    ELSE '{}'::jsonb
  END
FROM fixture_6an_expected_contacts AS expected
CROSS JOIN fixture_6an_release_fingerprints AS fingerprint;

CREATE TEMP TABLE fixture_6an_excluded_contacts (
  contact_id text PRIMARY KEY,
  exclusion_kind text NOT NULL
);
INSERT INTO fixture_6an_excluded_contacts (contact_id, exclusion_kind)
VALUES
  ('fixture-6an-excluded-pending', 'pending'),
  ('fixture-6an-excluded-na', 'not_applicable'),
  ('fixture-6an-excluded-incomplete', 'incomplete'),
  ('fixture-6an-excluded-unmapped', 'unmapped'),
  ('fixture-6an-excluded-ambiguous', 'ambiguous'),
  ('fixture-6an-excluded-outside', 'outside_period'),
  ('fixture-6an-excluded-after-cutoff', 'after_cutoff'),
  ('fixture-6an-excluded-voided', 'voided');

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
  place_name,
  smallest_region_id,
  region_tree_version,
  latitude,
  longitude,
  location_accuracy_meters,
  reach_count,
  interest_level,
  lifecycle_status
)
SELECT
  excluded.contact_id,
  '6a110000-0000-4000-8000-000000000001'::uuid,
  '6a120000-0000-4000-8000-000000000001'::uuid,
  '6a130000-0000-4000-8000-000000000001'::uuid,
  '6a140000-0000-4000-8000-000000000001'::uuid,
  CASE excluded.exclusion_kind
    WHEN 'outside_period' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        - interval '1 day'
    ELSE (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '2 days'
  END,
  'UTC',
  CASE excluded.exclusion_kind
    WHEN 'after_cutoff' THEN context.data_cutoff_utc + interval '1 day'
    ELSE (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '2 days'
  END,
  CASE excluded.exclusion_kind
    WHEN 'not_applicable' THEN 'voice_call'
    WHEN 'incomplete' THEN 'voice_call'
    ELSE 'face_to_face'
  END,
  CASE excluded.exclusion_kind
    WHEN 'pending' THEN 'pending_resolution'
    WHEN 'not_applicable' THEN 'not_applicable'
    WHEN 'incomplete' THEN 'not_applicable'
    ELSE 'resolved'
  END,
  CASE
    WHEN excluded.exclusion_kind IN (
      'pending', 'not_applicable', 'incomplete'
    ) THEN NULL
    ELSE 'Excluded private venue'
  END,
  CASE excluded.exclusion_kind
    WHEN 'unmapped' THEN 'fixture-6an-source-unmapped'
    WHEN 'ambiguous' THEN 'fixture-6an-source-coordinate'
    WHEN 'pending' THEN NULL
    WHEN 'not_applicable' THEN NULL
    WHEN 'incomplete' THEN NULL
    ELSE 'fixture-6an-target-a-venue'
  END,
  CASE excluded.exclusion_kind
    WHEN 'unmapped' THEN 'fixture-6an-source-v1'
    WHEN 'ambiguous' THEN 'fixture-6an-source-v1'
    WHEN 'pending' THEN NULL
    WHEN 'not_applicable' THEN NULL
    WHEN 'incomplete' THEN NULL
    ELSE 'fixture-6an-target-v1'
  END,
  CASE WHEN excluded.exclusion_kind = 'pending' THEN 41.70 END,
  CASE WHEN excluded.exclusion_kind = 'pending' THEN -87.65 END,
  CASE WHEN excluded.exclusion_kind = 'pending' THEN 5.0 END,
  1,
  2,
  CASE WHEN excluded.exclusion_kind = 'voided' THEN 'voided' ELSE 'active' END
FROM fixture_6an_excluded_contacts AS excluded
CROSS JOIN fixture_6an_report_context AS context;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  snapshot
)
SELECT
  excluded.contact_id,
  1,
  'submitted',
  '6a110000-0000-4000-8000-000000000001'::uuid,
  CASE excluded.exclusion_kind
    WHEN 'pending' THEN jsonb_build_object(
      'contactId', excluded.contact_id,
      'location', jsonb_build_object(
        'kind', 'pending_resolution',
        'latitude', 41.70,
        'longitude', -87.65,
        'accuracyMeters', 5.0
      )
    )
    WHEN 'not_applicable' THEN jsonb_build_object(
      'contactId', excluded.contact_id,
      'location', jsonb_build_object('kind', 'not_applicable')
    )
    WHEN 'incomplete' THEN '{}'::jsonb
    ELSE jsonb_build_object(
      'contactId', excluded.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Excluded private venue',
        'smallestRegionId', CASE excluded.exclusion_kind
          WHEN 'unmapped' THEN 'fixture-6an-source-unmapped'
          WHEN 'ambiguous' THEN 'fixture-6an-source-coordinate'
          ELSE 'fixture-6an-target-a-venue'
        END,
        'regionTreeVersion', CASE
          WHEN excluded.exclusion_kind IN ('unmapped', 'ambiguous')
            THEN 'fixture-6an-source-v1'
          ELSE 'fixture-6an-target-v1'
        END
      )
    ) || CASE
      WHEN excluded.exclusion_kind = 'ambiguous' THEN jsonb_build_object(
        'locationSource', jsonb_build_object(
          'kind', 'captured_coordinates',
          'latitude', 41.70,
          'longitude', -87.65,
          'accuracyMeters', 5.0,
          'resolverContractVersion', 'canonical-region-resolution:v1',
          'regionTreeContentFingerprint', fingerprint.source_fingerprint
        )
      )
      ELSE '{}'::jsonb
    END
  END
FROM fixture_6an_excluded_contacts AS excluded
CROSS JOIN fixture_6an_release_fingerprints AS fingerprint;

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
  place_name,
  smallest_region_id,
  region_tree_version,
  reach_count,
  interest_level
)
SELECT
  'fixture-6an-other-project',
  '6a110000-0000-4000-8000-000000000001'::uuid,
  '6a120000-0000-4000-8000-000000000001'::uuid,
  '6a130000-0000-4000-8000-000000000002'::uuid,
  '6a140000-0000-4000-8000-000000000002'::uuid,
  (context.periods->'current_period'->>'start_utc')::timestamptz
    + interval '2 days',
  'UTC',
  (context.periods->'current_period'->>'start_utc')::timestamptz
    + interval '2 days',
  'face_to_face',
  'resolved',
  'Other project private venue',
  'fixture-6an-target-a-venue',
  'fixture-6an-target-v1',
  1,
  2
FROM fixture_6an_report_context AS context;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  snapshot
) VALUES (
  'fixture-6an-other-project',
  1,
  'submitted',
  '6a110000-0000-4000-8000-000000000001'::uuid,
  jsonb_build_object(
    'contactId', 'fixture-6an-other-project',
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', 'Other project private venue',
      'smallestRegionId', 'fixture-6an-target-a-venue',
      'regionTreeVersion', 'fixture-6an-target-v1'
    )
  )
);

INSERT INTO app_data.change_feed (
  app_user_id,
  workspace_id,
  project_id,
  aggregate_id,
  revision_number,
  change_type
) VALUES
  (
    '6a110000-0000-4000-8000-000000000001'::uuid,
    '6a120000-0000-4000-8000-000000000001'::uuid,
    '6a130000-0000-4000-8000-000000000001'::uuid,
    'fixture-6an-current-watermark',
    1,
    'contact.submitted'
  ),
  (
    '6a110000-0000-4000-8000-000000000001'::uuid,
    '6a120000-0000-4000-8000-000000000001'::uuid,
    '6a130000-0000-4000-8000-000000000002'::uuid,
    'fixture-6an-other-watermark',
    1,
    'contact.submitted'
  );

DO $end_to_end_fixture$
DECLARE
  report_document jsonb;
  replayed_document jsonb;
  unavailable_document jsonb;
  target_fingerprint text;
  report_periods jsonb;
  data_cutoff_utc timestamptz;
  expected_watermark bigint;
  item jsonb;
  expected record;
  failure_sqlstate text;
BEGIN
  SELECT fingerprint.target_fingerprint
    INTO STRICT target_fingerprint
  FROM fixture_6an_release_fingerprints AS fingerprint;
  SELECT context.periods, context.data_cutoff_utc
    INTO STRICT report_periods, data_cutoff_utc
  FROM fixture_6an_report_context AS context;
  SELECT max(change_row.change_sequence)
    INTO STRICT expected_watermark
  FROM app_data.change_feed AS change_row
  WHERE change_row.project_id =
    '6a130000-0000-4000-8000-000000000001'::uuid;

  report_document =
    app_private.execute_management_current_city_contact_session_report_v1(
      '6a130000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      data_cutoff_utc
    );
  replayed_document =
    app_private.execute_management_current_city_contact_session_report_v1(
      '6a130000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      data_cutoff_utc
    );
  IF replayed_document IS DISTINCT FROM report_document THEN
    RAISE EXCEPTION
      'same-state current city report replay changed its protected document';
  END IF;

  IF report_document->>'report_id'
      IS DISTINCT FROM 'contact_sessions_by_current_city_two_periods'
    OR report_document->>'report_version' IS DISTINCT FROM '1'
    OR report_document->>'metric_id' IS DISTINCT FROM 'contact_sessions'
    OR report_document->>'metric_version' IS DISTINCT FROM '1'
    OR report_document->>'dimension' IS DISTINCT FROM 'current_city'
    OR report_document->>'view_mode' IS DISTINCT FROM 'current'
    OR report_document->>'region_granularity' IS DISTINCT FROM 'city'
    OR report_document->>'result_status' IS DISTINCT FROM 'completed'
    OR report_document->>'project_id' IS DISTINCT FROM
      '6a130000-0000-4000-8000-000000000001'
    OR report_document->'periods' IS DISTINCT FROM report_periods
    OR (report_document->>'source_change_sequence')::bigint
      IS DISTINCT FROM expected_watermark
    OR report_document->'target_context'->>'target_tree_version'
      IS DISTINCT FROM 'fixture-6an-target-v1'
    OR report_document->'target_context'->>'target_content_fingerprint'
      IS DISTINCT FROM target_fingerprint
  THEN
    RAISE EXCEPTION 'current city end-to-end contract is incorrect: %',
      report_document;
  END IF;

  IF report_document - ARRAY[
    'report_id', 'report_version', 'metric_id', 'metric_version',
    'dimension', 'view_mode', 'region_granularity', 'query_fingerprint',
    'privacy_policy', 'source_scope', 'project_id', 'periods',
    'data_cutoff_utc', 'source_change_sequence', 'target_context',
    'result_status', 'cells'
  ] <> '{}'::jsonb
    OR (SELECT count(*) FROM jsonb_object_keys(report_document)) <> 17
  THEN
    RAISE EXCEPTION 'current city report returned uncontracted top-level keys';
  END IF;

  IF jsonb_array_length(report_document->'cells') <> 8
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(report_document->'cells') AS cell(value)
      WHERE value->>'privacy_status' = 'displayed'
        AND value->>'value_count' = '10'
    ) <> 4
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(report_document->'cells') AS cell(value)
      WHERE value->>'privacy_status' = 'suppressed'
        AND value->'value_count' = 'null'::jsonb
    ) <> 4
  THEN
    RAISE EXCEPTION 'current city report grid or privacy result is wrong: %',
      report_document->'cells';
  END IF;

  FOR expected IN
    SELECT *
    FROM (VALUES
      (0, 'previous', 'fixture-6an-target-city-a', 'displayed', 10),
      (1, 'previous', 'fixture-6an-target-city-b', 'displayed', 10),
      (2, 'previous', 'fixture-6an-target-city-c', 'suppressed', NULL),
      (3, 'previous', 'fixture-6an-target-city-d', 'suppressed', NULL),
      (4, 'current', 'fixture-6an-target-city-a', 'displayed', 10),
      (5, 'current', 'fixture-6an-target-city-b', 'displayed', 10),
      (6, 'current', 'fixture-6an-target-city-c', 'suppressed', NULL),
      (7, 'current', 'fixture-6an-target-city-d', 'suppressed', NULL)
    ) AS expected_cells(
      cell_order,
      period_key,
      city_id,
      privacy_status,
      value_count
    )
  LOOP
    SELECT cell.value
      INTO STRICT item
    FROM jsonb_array_elements(report_document->'cells') AS cell(value)
    WHERE (cell.value->>'cell_order')::integer = expected.cell_order;

    IF item->>'period_key' IS DISTINCT FROM expected.period_key
      OR item->>'city_id' IS DISTINCT FROM expected.city_id
      OR item->>'privacy_status' IS DISTINCT FROM expected.privacy_status
      OR (
        expected.value_count IS NULL
        AND item->'value_count' <> 'null'::jsonb
      )
      OR (
        expected.value_count IS NOT NULL
        AND (item->>'value_count')::integer <> expected.value_count
      )
      OR item - ARRAY[
        'period_key', 'city_id', 'cell_order', 'value_count', 'privacy_status'
      ] <> '{}'::jsonb
      OR (SELECT count(*) FROM jsonb_object_keys(item)) <> 5
    THEN
      RAISE EXCEPTION 'unexpected current city cell %: %',
        expected.cell_order, item;
    END IF;
  END LOOP;

  IF report_document::text LIKE '%fixture-6an-source-%'
    OR report_document::text LIKE '%fixture-6an-%-u%'
    OR report_document::text LIKE '%Private%'
    OR report_document::text LIKE '%41.70%'
    OR report_document::text LIKE '%-87.%'
    OR report_document::text LIKE
      '%6a110000-0000-4000-8000-00000000000%'
  THEN
    RAISE EXCEPTION 'current city report leaked source evidence or PII: %',
      report_document;
  END IF;

  unavailable_document =
    app_private.execute_management_current_city_contact_session_report_v1(
      '6a130000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      '1900-01-10T12:00:00Z'::timestamptz
    );
  IF unavailable_document->>'result_status' IS DISTINCT FROM 'unavailable'
    OR unavailable_document->>'reason_code'
      IS DISTINCT FROM 'selection_history_unavailable'
    OR unavailable_document ? 'cells'
    OR unavailable_document ?| ARRAY[
      'contact_id', 'source_id', 'revision_number', 'contributor_id'
    ]
  THEN
    RAISE EXCEPTION 'unavailable current city report is incorrect: %',
      unavailable_document;
  END IF;

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
    place_name,
    smallest_region_id,
    region_tree_version,
    reach_count,
    interest_level
  ) VALUES (
    'fixture-6an-missing-current-source',
    '6a110000-0000-4000-8000-000000000001'::uuid,
    '6a120000-0000-4000-8000-000000000001'::uuid,
    '6a130000-0000-4000-8000-000000000001'::uuid,
    '6a140000-0000-4000-8000-000000000001'::uuid,
    (report_periods->'current_period'->>'start_utc')::timestamptz
      + interval '3 days',
    'UTC',
    (report_periods->'current_period'->>'start_utc')::timestamptz
      + interval '3 days',
    'face_to_face',
    'resolved',
    'Missing source private venue',
    'fixture-6an-target-a-venue',
    'fixture-6an-target-v1',
    1,
    2
  );

  failure_sqlstate := NULL;
  BEGIN
    PERFORM
      app_private.execute_management_current_city_contact_session_report_v1(
        '6a130000-0000-4000-8000-000000000001'::uuid,
        'UTC',
        data_cutoff_utc
      );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'missing current provenance did not fail closed: %',
      failure_sqlstate;
  END IF;
  DELETE FROM app_data.contacts
  WHERE contact_id = 'fixture-6an-missing-current-source';

  PERFORM app_private.publish_canonical_region_tree_v1(
    'fixture-6an-nested-v1',
    true
  );
  failure_sqlstate := NULL;
  BEGIN
    PERFORM
      app_private.execute_management_current_city_contact_session_report_v1(
        '6a130000-0000-4000-8000-000000000001'::uuid,
        'UTC',
        data_cutoff_utc
      );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'nested target cities did not fail closed: %',
      failure_sqlstate;
  END IF;
END;
$end_to_end_fixture$;

ROLLBACK;
