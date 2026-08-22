-- Synthetic fixture for the private DB-only original-region report.
-- Every row is rolled back.  No production data, region source or identity is
-- used.  The fixture intentionally keeps a valid 0053 mapping and a current
-- target selection beside the source evidence to prove that original mode
-- does not consult either one.
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE fixture_6bd_report_context AS
SELECT
  '2030-04-17T12:00:00Z'::timestamptz AS data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', '2030-04-17T12:00:00Z'::timestamptz
  ) AS periods;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6bd10000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6bd10000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6bd10000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name
)
VALUES (
  '6bd20000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BD synthetic original-region workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6bd30000-0000-4000-8000-000000000001'::uuid,
    '6bd20000-0000-4000-8000-000000000001'::uuid,
    '6BD source project'
  ),
  (
    '6bd30000-0000-4000-8000-000000000002'::uuid,
    '6bd20000-0000-4000-8000-000000000001'::uuid,
    '6BD negative-case project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
)
VALUES
  (
    '6bd40000-0000-4000-8000-000000000001'::uuid,
    '6bd30000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '6bd40000-0000-4000-8000-000000000002'::uuid,
    '6bd30000-0000-4000-8000-000000000002'::uuid,
    1,
    'published',
    true
  );

-- Source tree has three stable cities.  City C deliberately has nine units
-- in the previous period so the fixture proves both primary and
-- complementary suppression while keeping the full city grid.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
)
VALUES
  ('fixture-6bd-source-v1', 'draft', false),
  ('fixture-6bd-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
)
VALUES
  ('fixture-6bd-source-country', 'fixture-6bd-source-v1', NULL,
    '6BD Source Country', 'country'),
  ('fixture-6bd-source-city-a', 'fixture-6bd-source-v1',
    'fixture-6bd-source-country', '6BD Source City A', 'city'),
  ('fixture-6bd-source-city-b', 'fixture-6bd-source-v1',
    'fixture-6bd-source-country', '6BD Source City B', 'city'),
  ('fixture-6bd-source-city-c', 'fixture-6bd-source-v1',
    'fixture-6bd-source-country', '6BD Source City C', 'city'),
  ('fixture-6bd-source-venue-a', 'fixture-6bd-source-v1',
    'fixture-6bd-source-city-a', '6BD Source Venue A', 'venue'),
  ('fixture-6bd-source-venue-b', 'fixture-6bd-source-v1',
    'fixture-6bd-source-city-b', '6BD Source Venue B', 'venue'),
  ('fixture-6bd-source-venue-c', 'fixture-6bd-source-v1',
    'fixture-6bd-source-city-c', '6BD Source Venue C', 'venue'),
  ('fixture-6bd-target-country', 'fixture-6bd-target-v1', NULL,
    '6BD Target Country', 'country'),
  ('fixture-6bd-target-city', 'fixture-6bd-target-v1',
    'fixture-6bd-target-country', '6BD Source City A', 'city'),
  ('fixture-6bd-target-venue', 'fixture-6bd-target-v1',
    'fixture-6bd-target-city', '6BD Source Venue A', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
)
VALUES
  (
    'fixture-6bd-source-city-a-boundary',
    'fixture-6bd-source-city-a',
    'fixture-6bd-source-v1',
    polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
  ),
  (
    'fixture-6bd-source-city-b-boundary',
    'fixture-6bd-source-city-b',
    'fixture-6bd-source-v1',
    polygon '((-87.90,41.60),(-87.80,41.60),(-87.80,41.70),(-87.90,41.70))'
  ),
  (
    'fixture-6bd-source-city-c-boundary',
    'fixture-6bd-source-city-c',
    'fixture-6bd-source-v1',
    polygon '((-87.80,41.60),(-87.70,41.60),(-87.70,41.70),(-87.80,41.70))'
  ),
  (
    'fixture-6bd-target-city-boundary',
    'fixture-6bd-target-city',
    'fixture-6bd-target-v1',
    polygon '((-87.70,41.60),(-87.60,41.60),(-87.60,41.70),(-87.70,41.70))'
  );

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bd-source-v1', false
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bd-target-v1', true
);

CREATE TEMP TABLE fixture_6bd_fingerprints AS
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6bd-source-v1'
  ) AS source_fingerprint,
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-6bd-target-v1'
  ) AS target_fingerprint
FROM app_data.canonical_region_tree_releases;

DO $fixture_fingerprints$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM fixture_6bd_fingerprints
    WHERE source_fingerprint !~ '^[0-9a-f]{64}$'
      OR target_fingerprint !~ '^[0-9a-f]{64}$'
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_tree_releases AS release_row
    WHERE release_row.tree_version = 'fixture-6bd-target-v1'
      AND release_row.lifecycle_state = 'published'
      AND release_row.is_current
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_tree_current_selections AS selection
    JOIN fixture_6bd_fingerprints AS fingerprints
      ON fingerprints.target_fingerprint = selection.content_fingerprint
    WHERE selection.selected_tree_version = 'fixture-6bd-target-v1'
      AND selection.selection_source = 'publication'
  ) THEN
    RAISE EXCEPTION '6BD fixture tree fingerprints or current target are invalid';
  END IF;
END
$fixture_fingerprints$;

-- A valid source-to-target mapping and a current target selection are present.
-- Their target city and venue deliberately share the source display names but
-- have different IDs.  The report must neither map nor guess by those names.
SELECT app_private.register_canonical_region_version_mapping_v1(
  '6bd50000-0000-4000-8000-000000000001'::uuid,
  'fixture-6bd-source-v1',
  'fixture-6bd-source-venue-a',
  fingerprints.source_fingerprint,
  'fixture-6bd-target-v1',
  'fixture-6bd-target-venue',
  fingerprints.target_fingerprint,
  repeat('b', 64)
)
FROM fixture_6bd_fingerprints AS fingerprints;

CREATE TEMP TABLE fixture_6bd_contact_plan AS
SELECT
  format(
    'fixture-6bd-%s-%s-c%s-u%s',
    period_row.period_key,
    city_row.city_key,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  city_row.city_key,
  contributor_row.contributor_number,
  CASE contributor_row.contributor_number
    WHEN 1 THEN '6bd10000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6bd10000-0000-4000-8000-000000000002'::uuid
    ELSE '6bd10000-0000-4000-8000-000000000003'::uuid
  END AS contributor_id,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 day'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 day'
  END AS occurred_at_utc
FROM fixture_6bd_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES ('a'), ('b'), ('c')) AS city_row(city_key)
JOIN (
  VALUES
    ('a', 1, 5), ('a', 2, 3), ('a', 3, 2),
    ('b', 1, 5), ('b', 2, 3), ('b', 3, 2),
    ('c', 1, 5), ('c', 2, 3), ('c', 3, 2)
) AS contributor_row(city_key, contributor_number, unit_count)
  ON contributor_row.city_key = city_row.city_key
CROSS JOIN LATERAL generate_series(
  1,
  CASE
    WHEN period_row.period_key = 'previous'
      AND city_row.city_key = 'c'
      AND contributor_row.contributor_number = 1 THEN 5
    WHEN period_row.period_key = 'previous'
      AND city_row.city_key = 'c'
      AND contributor_row.contributor_number = 2 THEN 2
    WHEN period_row.period_key = 'previous'
      AND city_row.city_key = 'c'
      AND contributor_row.contributor_number = 3 THEN 2
    ELSE contributor_row.unit_count
  END
) AS unit_row(unit_number);

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
  plan.contact_id,
  plan.contributor_id,
  '6bd20000-0000-4000-8000-000000000001'::uuid,
  '6bd30000-0000-4000-8000-000000000001'::uuid,
  '6bd40000-0000-4000-8000-000000000001'::uuid,
  plan.occurred_at_utc,
  'UTC',
  plan.occurred_at_utc,
  'face_to_face',
  'resolved',
  '6BD synthetic source venue',
  format('fixture-6bd-source-venue-%s', plan.city_key),
  'fixture-6bd-source-v1',
  1,
  2
FROM fixture_6bd_contact_plan AS plan;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  snapshot
)
SELECT
  plan.contact_id,
  1,
  'submitted',
  plan.contributor_id,
  jsonb_build_object(
    'contactId', plan.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', '6BD synthetic source venue',
      'smallestRegionId', format('fixture-6bd-source-venue-%s', plan.city_key),
      'regionTreeVersion', 'fixture-6bd-source-v1'
    )
  )
FROM fixture_6bd_contact_plan AS plan;

INSERT INTO app_data.change_feed (
  app_user_id,
  workspace_id,
  project_id,
  aggregate_id,
  revision_number,
  change_type
)
VALUES (
  '6bd10000-0000-4000-8000-000000000001'::uuid,
  '6bd20000-0000-4000-8000-000000000001'::uuid,
  '6bd30000-0000-4000-8000-000000000001'::uuid,
  'fixture-6bd-source-watermark',
  1,
  'contact.submitted'
);

DO $fixture_contract$
DECLARE
  report_document jsonb;
  replayed_document jsonb;
  report_periods jsonb;
  expected_watermark bigint;
  source_fingerprint text;
  item jsonb;
  expected record;
BEGIN
  SELECT periods INTO STRICT report_periods
  FROM fixture_6bd_report_context;
  SELECT fingerprints.source_fingerprint INTO STRICT source_fingerprint
  FROM fixture_6bd_fingerprints AS fingerprints;
  SELECT max(change_sequence) INTO STRICT expected_watermark
  FROM app_data.change_feed
  WHERE project_id = '6bd30000-0000-4000-8000-000000000001'::uuid;

  report_document =
    app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      '2030-04-17T12:00:00Z'::timestamptz
    );
  replayed_document =
    app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      '2030-04-17T12:00:00Z'::timestamptz
    );

  IF replayed_document IS DISTINCT FROM report_document THEN
    RAISE EXCEPTION '6BD replay changed the protected report';
  END IF;

  IF report_document->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_original_region_two_periods'
    OR report_document->>'report_version' IS DISTINCT FROM '1'
    OR report_document->>'metric_id' IS DISTINCT FROM 'contact_sessions'
    OR report_document->>'metric_version' IS DISTINCT FROM '1'
    OR report_document->>'dimension' IS DISTINCT FROM 'original_region'
    OR report_document->>'view_mode' IS DISTINCT FROM 'original'
    OR report_document->>'region_granularity' IS DISTINCT FROM 'city'
    OR report_document->>'result_status' IS DISTINCT FROM 'completed'
    OR report_document->>'project_id' IS DISTINCT FROM
      '6bd30000-0000-4000-8000-000000000001'
    OR report_document->'periods' IS DISTINCT FROM report_periods
    OR (report_document->>'source_change_sequence')::bigint
      IS DISTINCT FROM expected_watermark
    OR report_document->'source_tree_context'->>'result_status'
      IS DISTINCT FROM 'selected'
    OR report_document->'source_tree_context'->>'reason_code'
      IS DISTINCT FROM 'single_original_source_tree'
    OR report_document->'source_tree_context'->>'source_tree_version'
      IS DISTINCT FROM 'fixture-6bd-source-v1'
    OR report_document->'source_tree_context'->>'source_content_fingerprint'
      IS DISTINCT FROM source_fingerprint
  THEN
    RAISE EXCEPTION '6BD completed identity or source tuple is wrong: %',
      report_document;
  END IF;

  IF report_document - ARRAY[
    'report_id', 'report_version', 'metric_id', 'metric_version',
    'dimension', 'view_mode', 'region_granularity', 'query_fingerprint',
    'privacy_policy', 'source_scope', 'project_id', 'periods',
    'data_cutoff_utc', 'source_change_sequence', 'source_tree_context',
    'result_status', 'cells'
  ] <> '{}'::jsonb
    OR (SELECT count(*) FROM jsonb_object_keys(report_document)) <> 17
  THEN
    RAISE EXCEPTION '6BD returned uncontracted top-level keys: %',
      report_document;
  END IF;

  IF jsonb_array_length(report_document->'cells') <> 6
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
    ) <> 2
  THEN
    RAISE EXCEPTION '6BD grid or privacy result is wrong: %',
      report_document->'cells';
  END IF;

  FOR expected IN
    SELECT *
    FROM (VALUES
      (0, 'previous', 'fixture-6bd-source-city-a', 'suppressed', NULL),
      (1, 'previous', 'fixture-6bd-source-city-b', 'displayed', 10),
      (2, 'previous', 'fixture-6bd-source-city-c', 'suppressed', NULL),
      (3, 'current', 'fixture-6bd-source-city-a', 'displayed', 10),
      (4, 'current', 'fixture-6bd-source-city-b', 'displayed', 10),
      (5, 'current', 'fixture-6bd-source-city-c', 'displayed', 10)
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
      RAISE EXCEPTION 'unexpected 6BD cell %: %', expected.cell_order, item;
    END IF;
  END LOOP;

  IF report_document::text LIKE '%6bd10000-0000-4000-8000-00000000000%'
    OR report_document::text LIKE '%fixture-6bd-previous-%'
    OR report_document::text LIKE '%fixture-6bd-current-%'
    OR report_document::text LIKE '%6BD synthetic source venue%'
    OR report_document::text LIKE '%latitude%'
    OR report_document::text LIKE '%longitude%'
    OR report_document::text LIKE '%contact_id%'
    OR report_document::text LIKE '%revision_number%'
    OR report_document::text LIKE '%contributor_key%'
  THEN
    RAISE EXCEPTION '6BD report leaked source, contributor or PII: %',
      report_document;
  END IF;

  -- The current target selection and a valid mapping are both present.  The
  -- completed report must still use the original source tuple and source-city
  -- grid; no target city may appear in the cells or context.
  IF report_document::text LIKE '%fixture-6bd-target-%'
  THEN
    RAISE EXCEPTION '6BD original report consulted current/mapped target data';
  END IF;
END
$fixture_contract$;

-- A corrected current revision must use its matching append-only source row.
-- A conflicting current assignment beside that evidence must not change the
-- original report or pull the contact into the current target tree.
DO $fixture_current_revision_isolation$
DECLARE
  baseline_document jsonb;
  corrected_document jsonb;
  isolation_ok boolean := false;
BEGIN
  baseline_document =
    app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );

  BEGIN
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot, reason
    ) VALUES (
      'fixture-6bd-current-a-c1-u1', 2, 'corrected',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'contactId', 'fixture-6bd-current-a-c1-u1',
        'location', jsonb_build_object(
          'kind', 'resolved',
          'placeName', '6BD corrected source venue',
          'smallestRegionId', 'fixture-6bd-source-venue-a',
          'regionTreeVersion', 'fixture-6bd-source-v1'
        )
      ),
      '6BD synthetic corrected current revision'
    );
    UPDATE app_data.contacts
    SET current_revision = 2
    WHERE contact_id = 'fixture-6bd-current-a-c1-u1';
    UPDATE app_data.contact_region_assignments
    SET region_id = 'fixture-6bd-target-venue',
        tree_version = 'fixture-6bd-target-v1'
    WHERE contact_id = 'fixture-6bd-current-a-c1-u1';

    corrected_document =
      app_private.execute_management_original_region_contact_session_report_v1(
        '6bd30000-0000-4000-8000-000000000001'::uuid,
        'UTC', '2030-04-17T12:00:00Z'::timestamptz
      );
    isolation_ok = corrected_document IS NOT DISTINCT FROM baseline_document
      AND EXISTS (
        SELECT 1
        FROM app_data.contact_location_provenance AS provenance
        WHERE provenance.contact_id = 'fixture-6bd-current-a-c1-u1'
          AND provenance.revision_number = 2
          AND provenance.smallest_region_id = 'fixture-6bd-source-venue-a'
          AND provenance.region_tree_version = 'fixture-6bd-source-v1'
      )
      AND EXISTS (
        SELECT 1
        FROM app_data.contact_region_assignments AS assignment
        WHERE assignment.contact_id = 'fixture-6bd-current-a-c1-u1'
          AND assignment.region_id = 'fixture-6bd-target-venue'
          AND assignment.tree_version = 'fixture-6bd-target-v1'
      )
      AND corrected_document::text NOT LIKE '%fixture-6bd-target-%';
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'rollback corrected current revision isolation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> 'P0001' THEN
      RAISE;
    END IF;
  END;

  IF NOT isolation_ok THEN
    RAISE EXCEPTION
      'corrected source/current assignment isolation failed: %',
      corrected_document;
  END IF;
END
$fixture_current_revision_isolation$;

DO $fixture_privacy$
DECLARE
  protected_cells jsonb;
  complementary_cells jsonb;
BEGIN
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
  FROM app_private.protect_management_original_region_contact_session_grid_v1(
    jsonb_build_array(
      'fixture-6bd-edge-a',
      'fixture-6bd-edge-b',
      'fixture-6bd-edge-c',
      'fixture-6bd-edge-empty'
    ),
    jsonb_build_array(
      -- Exactly 10, three contributors and exactly half is displayable.
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-a', 'contributor_key', 'a1', 'unit_count', 5),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-a', 'contributor_key', 'a2', 'unit_count', 3),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-a', 'contributor_key', 'a3', 'unit_count', 2),
      -- Exactly 10 but only two contributors: suppressed.
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-b', 'contributor_key', 'b1', 'unit_count', 5),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-b', 'contributor_key', 'b2', 'unit_count', 5),
      -- Exactly 10 and three contributors, but six is over half: suppressed.
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-c', 'contributor_key', 'c1', 'unit_count', 6),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-c', 'contributor_key', 'c2', 'unit_count', 2),
      jsonb_build_object('period_key', 'current', 'city_id',
        'fixture-6bd-edge-c', 'contributor_key', 'c3', 'unit_count', 2)
    )
  ) AS protected;

  IF jsonb_array_length(protected_cells) <> 8
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'city_id' = 'fixture-6bd-edge-a'
        AND item->>'privacy_status' = 'displayed'
        AND item->>'value_count' = '10'
    ) <> 1
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(protected_cells) AS cell(item)
      WHERE item->>'period_key' = 'current'
        AND item->>'privacy_status' = 'suppressed'
        AND item->'value_count' = 'null'::jsonb
    ) <> 3
  THEN
    RAISE EXCEPTION '6BD threshold/empty-cell fixture failed: %',
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
  INTO complementary_cells
  FROM app_private.protect_management_original_region_contact_session_grid_v1(
    jsonb_build_array(
      'fixture-6bd-complement-a',
      'fixture-6bd-complement-b',
      'fixture-6bd-complement-c'
    ),
    jsonb_build_array(
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-a', 'contributor_key', 'a1', 'unit_count', 5),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-a', 'contributor_key', 'a2', 'unit_count', 3),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-a', 'contributor_key', 'a3', 'unit_count', 2),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-b', 'contributor_key', 'b1', 'unit_count', 5),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-b', 'contributor_key', 'b2', 'unit_count', 3),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-b', 'contributor_key', 'b3', 'unit_count', 2),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-c', 'contributor_key', 'c1', 'unit_count', 5),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-c', 'contributor_key', 'c2', 'unit_count', 2),
      jsonb_build_object('period_key', 'previous', 'city_id',
        'fixture-6bd-complement-c', 'contributor_key', 'c3', 'unit_count', 2)
    )
  ) AS protected;

  IF (
    SELECT item->>'privacy_status'
    FROM jsonb_array_elements(complementary_cells) AS cell(item)
    WHERE item->>'period_key' = 'previous'
      AND item->>'city_id' = 'fixture-6bd-complement-a'
  ) IS DISTINCT FROM 'suppressed'
    OR (
      SELECT item->>'privacy_status'
      FROM jsonb_array_elements(complementary_cells) AS cell(item)
      WHERE item->>'period_key' = 'previous'
        AND item->>'city_id' = 'fixture-6bd-complement-b'
    ) IS DISTINCT FROM 'displayed'
    OR (
      SELECT item->>'value_count'
      FROM jsonb_array_elements(complementary_cells) AS cell(item)
      WHERE item->>'period_key' = 'previous'
        AND item->>'city_id' = 'fixture-6bd-complement-b'
    ) IS DISTINCT FROM '10'
    OR (
      SELECT item->'value_count'
      FROM jsonb_array_elements(complementary_cells) AS cell(item)
      WHERE item->>'period_key' = 'previous'
        AND item->>'city_id' = 'fixture-6bd-complement-c'
    ) <> 'null'::jsonb
  THEN
    RAISE EXCEPTION '6BD complementary suppression failed: %',
      complementary_cells;
  END IF;

  BEGIN
    PERFORM *
    FROM app_private.protect_management_original_region_contact_session_grid_v1(
      jsonb_build_array('fixture-6bd-duplicate', 'fixture-6bd-duplicate'),
      '[]'::jsonb
    );
    RAISE EXCEPTION '6BD protector accepted a duplicate city';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM *
    FROM app_private.protect_management_original_region_contact_session_grid_v1(
      jsonb_build_array('fixture-6bd-outside'),
      jsonb_build_array(jsonb_build_object(
        'period_key', 'current',
        'city_id', 'fixture-6bd-not-in-grid',
        'contributor_key', 'fixture-contributor',
        'unit_count', 10
      ))
    );
    RAISE EXCEPTION '6BD protector accepted a contribution outside its grid';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$fixture_privacy$;

-- A channel total of 70 must not expose a nine-session original city by
-- subtraction.  The original report hides both the primary small cell and a
-- complementary large cell, even though both reports share the same total.
DO $fixture_cross_report_subtraction$
DECLARE
  channel_contributions jsonb;
  original_contributions jsonb;
  channel_document jsonb;
  original_document jsonb;
  channel_total text;
  original_suppressed integer;
  raw_total integer;
  raw_small_city integer;
BEGIN
  original_contributions = jsonb_build_array(
    jsonb_build_object('period_key', 'current', 'city_id',
      'cross-report-large', 'contributor_key', 'a', 'unit_count', 30),
    jsonb_build_object('period_key', 'current', 'city_id',
      'cross-report-large', 'contributor_key', 'b', 'unit_count', 19),
    jsonb_build_object('period_key', 'current', 'city_id',
      'cross-report-large', 'contributor_key', 'c', 'unit_count', 12),
    jsonb_build_object('period_key', 'current', 'city_id',
      'cross-report-small', 'contributor_key', 'a', 'unit_count', 5),
    jsonb_build_object('period_key', 'current', 'city_id',
      'cross-report-small', 'contributor_key', 'b', 'unit_count', 2),
    jsonb_build_object('period_key', 'current', 'city_id',
      'cross-report-small', 'contributor_key', 'c', 'unit_count', 2)
  );

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', 'current',
      'channel', channel_name,
      'contributor_key', contributor_key,
      'unit_count', unit_count
    ) ORDER BY channel_name, contributor_key
  )
  INTO channel_contributions
  FROM unnest(ARRAY[
    'face_to_face', 'voice_call', 'video_call', 'instant_text',
    'asynchronous_message', 'mixed', 'other_direct'
  ]) AS channel(channel_name)
  CROSS JOIN (VALUES ('a', 5), ('b', 3), ('c', 2))
    AS contributor(contributor_key, unit_count);

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'category_key', protected.category_key,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  )
  INTO channel_document
  FROM app_private.protect_management_contact_session_grid_v1(
    channel_contributions
  ) AS protected;

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'city_id', protected.city_id,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  )
  INTO original_document
  FROM app_private.protect_management_original_region_contact_session_grid_v1(
    jsonb_build_array('cross-report-large', 'cross-report-small'),
    original_contributions
  ) AS protected;

  SELECT
    sum((item->>'unit_count')::integer),
    sum((item->>'unit_count')::integer) FILTER (
      WHERE item->>'city_id' = 'cross-report-small'
    )
  INTO raw_total, raw_small_city
  FROM jsonb_array_elements(original_contributions) AS contribution(item);

  SELECT item->>'value_count'
  INTO channel_total
  FROM jsonb_array_elements(channel_document) AS cell(item)
  WHERE item->>'period_key' = 'current'
    AND item->>'category_key' = 'all'
    AND item->>'privacy_status' = 'displayed';

  SELECT count(*)
  INTO original_suppressed
  FROM jsonb_array_elements(original_document) AS cell(item)
  WHERE item->>'period_key' = 'current'
    AND item->>'city_id' IN ('cross-report-large', 'cross-report-small')
    AND item->>'privacy_status' = 'suppressed'
    AND item->'value_count' = 'null'::jsonb;

  IF channel_total IS DISTINCT FROM raw_total::text
    OR raw_total <> 70
    OR raw_small_city <> 9
    OR original_suppressed <> 2
  THEN
    RAISE EXCEPTION
      'cross-report subtraction fixture is incorrect: channel %, small %, original %',
      channel_total, raw_small_city, original_document;
  END IF;
END
$fixture_cross_report_subtraction$;

-- Empty candidates are unavailable rather than an empty completed grid.
DO $fixture_empty$
DECLARE
  empty_document jsonb;
BEGIN
  empty_document =
    app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000002'::uuid,
      'UTC',
      '2030-04-17T12:00:00Z'::timestamptz
    );
  IF empty_document->>'result_status' IS DISTINCT FROM 'unavailable'
    OR empty_document->>'reason_code' IS DISTINCT FROM 'source_tree_unavailable'
    OR empty_document ? 'cells'
  THEN
    RAISE EXCEPTION '6BD empty-source result is incorrect: %', empty_document;
  END IF;
END
$fixture_empty$;

-- Every following block is a subtransaction.  Its synthetic malformed input
-- rolls back after the expected fail-closed assertion, so later cases remain
-- independent and the fixture can remain a single top-level rollback.
DO $fixture_fail_closed$
DECLARE
  failure_sqlstate text;
  drift_contact_id text := 'fixture-6bd-drift-contact';
  missing_contact_id text := 'fixture-6bd-missing-source-contact';
  pending_contact_id text := 'fixture-6bd-pending-contact';
  na_contact_id text := 'fixture-6bd-na-contact';
  legacy_contact_id text := 'fixture-6bd-legacy-contact';
BEGIN
  -- A current revision without a matching source row cannot be silently
  -- dropped from the denominator.
  failure_sqlstate := NULL;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, place_name,
      smallest_region_id, region_tree_version, reach_count, interest_level,
      current_revision
    ) VALUES (
      missing_contact_id,
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      '6bd40000-0000-4000-8000-000000000001'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'face_to_face', 'resolved', 'Missing source venue',
      'fixture-6bd-source-venue-a', 'fixture-6bd-source-v1', 1, 2, 2
    );
    IF NOT EXISTS (
      SELECT 1
      FROM app_data.contacts AS contact_row
      WHERE contact_row.contact_id = missing_contact_id
        AND contact_row.project_id =
          '6bd30000-0000-4000-8000-000000000001'::uuid
        AND contact_row.lifecycle_status = 'active'
        AND contact_row.current_revision = 2
        AND contact_row.first_submitted_at_utc <=
          '2030-04-17T12:00:00Z'::timestamptz
        AND contact_row.occurred_at_utc >=
          '2030-04-08T00:00:00Z'::timestamptz
        AND contact_row.occurred_at_utc <
          '2030-04-15T00:00:00Z'::timestamptz
    ) OR EXISTS (
      SELECT 1
      FROM app_data.contact_location_provenance AS provenance
      WHERE provenance.contact_id = missing_contact_id
        AND provenance.revision_number = 2
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0002',
        MESSAGE = 'missing-source fixture precondition is invalid';
    END IF;
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'missing source passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'missing original source did not fail closed: %',
      failure_sqlstate;
  END IF;

  -- Drift is injected only in this rolled-back synthetic subtransaction.  It
  -- exercises the fail-closed path without weakening the append-only guard.
  failure_sqlstate := NULL;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, place_name,
      smallest_region_id, region_tree_version, reach_count, interest_level
    ) VALUES (
      drift_contact_id,
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      '6bd40000-0000-4000-8000-000000000001'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'face_to_face', 'resolved', 'Drift source venue',
      'fixture-6bd-source-venue-a', 'fixture-6bd-source-v1', 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    ) VALUES (
      drift_contact_id, 1, 'submitted',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'contactId', drift_contact_id,
        'location', jsonb_build_object(
          'kind', 'resolved',
          'placeName', 'Drift source venue',
          'smallestRegionId', 'fixture-6bd-source-venue-a',
          'regionTreeVersion', 'fixture-6bd-source-v1'
        )
      )
    );
    SET LOCAL session_replication_role = replica;
    UPDATE app_data.contact_location_provenance
    SET region_tree_content_fingerprint = repeat('f', 64)
    WHERE contact_id = drift_contact_id;
    SET LOCAL session_replication_role = origin;
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'drift passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'fingerprint drift did not fail closed: %', failure_sqlstate;
  END IF;

  -- A saved tuple cannot remain reportable after its release is no longer
  -- published.  Replica mode is confined to this rolled-back negative case.
  failure_sqlstate := NULL;
  BEGIN
    SET LOCAL session_replication_role = replica;
    UPDATE app_data.canonical_region_tree_releases
    SET lifecycle_state = 'draft',
        published_at_utc = NULL,
        content_fingerprint = NULL,
        is_current = false
    WHERE tree_version = 'fixture-6bd-source-v1';
    SET LOCAL session_replication_role = origin;
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001', MESSAGE = 'unpublished source tree passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'unpublished source tree did not fail closed: %',
      failure_sqlstate;
  END IF;

  -- A source tuple that names no node must fail closed instead of falling
  -- back to the contact projection or matching a name in the same tree.
  failure_sqlstate := NULL;
  BEGIN
    SET LOCAL session_replication_role = replica;
    UPDATE app_data.contact_location_provenance
    SET smallest_region_id = 'fixture-6bd-unknown-source-node'
    WHERE contact_id = 'fixture-6bd-current-a-c1-u1';
    SET LOCAL session_replication_role = origin;
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001', MESSAGE = 'unknown source node passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'unknown source node did not fail closed: %',
      failure_sqlstate;
  END IF;

  -- A saved provenance tuple cannot name an unknown release even when its
  -- fingerprint and region ID look syntactically valid.
  failure_sqlstate := NULL;
  BEGIN
    SET LOCAL session_replication_role = replica;
    UPDATE app_data.contact_location_provenance
    SET region_tree_version = 'fixture-6bd-unknown-source-tree',
        region_tree_content_fingerprint = repeat('a', 64)
    WHERE contact_id = 'fixture-6bd-current-a-c1-u1';
    SET LOCAL session_replication_role = origin;
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001', MESSAGE = 'unknown source tree passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'unknown source tree did not fail closed: %',
      failure_sqlstate;
  END IF;

  -- A broken parent chain cannot yield a partial city lineage.  The mutation
  -- is synthetic, bypasses frozen-tree triggers and rolls back immediately.
  failure_sqlstate := NULL;
  BEGIN
    SET LOCAL session_replication_role = replica;
    UPDATE app_data.canonical_region_versions
    SET parent_region_id = 'fixture-6bd-missing-source-parent'
    WHERE tree_version = 'fixture-6bd-source-v1'
      AND region_id = 'fixture-6bd-source-city-a';
    SET LOCAL session_replication_role = origin;
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001', MESSAGE = 'missing source parent passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'missing source parent did not fail closed: %',
      failure_sqlstate;
  END IF;

  -- pending_resolution, not_applicable and legacy-incomplete evidence never
  -- become anonymous zeroes or inferred cities.
  failure_sqlstate := NULL;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, latitude, longitude,
      location_accuracy_meters, reach_count, interest_level
    ) VALUES (
      pending_contact_id,
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      '6bd40000-0000-4000-8000-000000000001'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'face_to_face', 'pending_resolution', 41.70, -87.70, 5, 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    ) VALUES (
      pending_contact_id, 1, 'submitted',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'contactId', pending_contact_id,
        'location', jsonb_build_object(
          'kind', 'pending_resolution', 'latitude', 41.70,
          'longitude', -87.70, 'accuracyMeters', 5
        )
      )
    );
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'pending passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'pending evidence did not fail closed: %', failure_sqlstate;
  END IF;

  failure_sqlstate := NULL;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, reach_count,
      interest_level
    ) VALUES (
      na_contact_id,
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      '6bd40000-0000-4000-8000-000000000001'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'voice_call', 'not_applicable', 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    ) VALUES (
      na_contact_id, 1, 'submitted',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'contactId', na_contact_id,
        'location', jsonb_build_object('kind', 'not_applicable')
      )
    );
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'not-applicable passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'not-applicable evidence did not fail closed: %', failure_sqlstate;
  END IF;

  failure_sqlstate := NULL;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, place_name,
      smallest_region_id, region_tree_version, reach_count, interest_level
    ) VALUES (
      legacy_contact_id,
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      '6bd40000-0000-4000-8000-000000000001'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'face_to_face', 'resolved', 'Legacy incomplete venue',
      'fixture-6bd-source-venue-a', 'fixture-6bd-source-v1', 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    ) VALUES (
      legacy_contact_id, 1, 'submitted',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '{}'::jsonb
    );
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'legacy passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'legacy evidence did not fail closed: %', failure_sqlstate;
  END IF;
END
$fixture_fail_closed$;

-- A second published source tree makes the candidate tuple mixed.  The report
-- returns a stable unavailable envelope instead of silently dropping the
-- target-tree contact or combining source trees.
DO $fixture_mixed$
DECLARE
  mixed_document jsonb;
  mixed_ok boolean := false;
BEGIN
  BEGIN
    INSERT INTO app_data.canonical_region_tree_releases (
      tree_version, lifecycle_state, is_current
    ) VALUES ('fixture-6bd-mixed-v1', 'draft', false);
    INSERT INTO app_data.canonical_region_versions (
      region_id, tree_version, parent_region_id, canonical_name, kind
    ) VALUES
      ('fixture-6bd-mixed-country', 'fixture-6bd-mixed-v1', NULL,
        '6BD Mixed Country', 'country'),
      ('fixture-6bd-mixed-city', 'fixture-6bd-mixed-v1',
        'fixture-6bd-mixed-country', '6BD Mixed City', 'city'),
      ('fixture-6bd-mixed-venue', 'fixture-6bd-mixed-v1',
        'fixture-6bd-mixed-city', '6BD Mixed Venue', 'venue');
    INSERT INTO app_data.canonical_region_boundaries (
      boundary_id, region_id, tree_version, boundary
    ) VALUES (
      'fixture-6bd-mixed-city-boundary',
      'fixture-6bd-mixed-city',
      'fixture-6bd-mixed-v1',
      polygon '((-87.50,41.60),(-87.40,41.60),(-87.40,41.70),(-87.50,41.70))'
    );
    PERFORM app_private.publish_canonical_region_tree_v1(
      'fixture-6bd-mixed-v1', false
    );
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, place_name,
      smallest_region_id, region_tree_version, reach_count, interest_level
    ) VALUES (
      'fixture-6bd-mixed-contact',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000001'::uuid,
      '6bd40000-0000-4000-8000-000000000001'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'face_to_face', 'resolved', '6BD Mixed Venue',
      'fixture-6bd-mixed-venue', 'fixture-6bd-mixed-v1', 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    ) VALUES (
      'fixture-6bd-mixed-contact', 1, 'submitted',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'contactId', 'fixture-6bd-mixed-contact',
        'location', jsonb_build_object(
          'kind', 'resolved', 'placeName', '6BD Mixed Venue',
          'smallestRegionId', 'fixture-6bd-mixed-venue',
          'regionTreeVersion', 'fixture-6bd-mixed-v1'
        )
      )
    );
    mixed_document =
      app_private.execute_management_original_region_contact_session_report_v1(
        '6bd30000-0000-4000-8000-000000000001'::uuid,
        'UTC', '2030-04-17T12:00:00Z'::timestamptz
      );
    mixed_ok = mixed_document->>'result_status' = 'unavailable'
      AND mixed_document->>'reason_code' = 'source_tree_mixed'
      AND NOT mixed_document ? 'cells'
      AND mixed_document::text NOT LIKE '%fixture-6bd-mixed-venue%';
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'rollback mixed case';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> 'P0001' THEN
      RAISE;
    END IF;
  END;
  IF NOT mixed_ok THEN
    RAISE EXCEPTION 'mixed source tree did not fail closed: %', mixed_document;
  END IF;
END
$fixture_mixed$;

-- A published tree with nested cities must not create an ambiguous city grid.
DO $fixture_nested$
DECLARE
  failure_sqlstate text;
BEGIN
  failure_sqlstate := NULL;
  BEGIN
    INSERT INTO app_data.canonical_region_tree_releases (
      tree_version, lifecycle_state, is_current
    ) VALUES ('fixture-6bd-nested-v1', 'draft', false);
    INSERT INTO app_data.canonical_region_versions (
      region_id, tree_version, parent_region_id, canonical_name, kind
    ) VALUES
      ('fixture-6bd-nested-country', 'fixture-6bd-nested-v1', NULL,
        '6BD Nested Country', 'country'),
      ('fixture-6bd-nested-city-parent', 'fixture-6bd-nested-v1',
        'fixture-6bd-nested-country', '6BD Nested Parent', 'city'),
      ('fixture-6bd-nested-city-child', 'fixture-6bd-nested-v1',
        'fixture-6bd-nested-city-parent', '6BD Nested Child', 'city'),
      ('fixture-6bd-nested-venue', 'fixture-6bd-nested-v1',
        'fixture-6bd-nested-city-child', '6BD Nested Venue', 'venue');
    INSERT INTO app_data.canonical_region_boundaries (
      boundary_id, region_id, tree_version, boundary
    ) VALUES (
      'fixture-6bd-nested-city-boundary',
      'fixture-6bd-nested-city-child',
      'fixture-6bd-nested-v1',
      polygon '((-87.40,41.60),(-87.30,41.60),(-87.30,41.70),(-87.40,41.70))'
    );
    PERFORM app_private.publish_canonical_region_tree_v1(
      'fixture-6bd-nested-v1', false
    );
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, place_name,
      smallest_region_id, region_tree_version, reach_count, interest_level
    ) VALUES (
      'fixture-6bd-nested-contact',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      '6bd20000-0000-4000-8000-000000000001'::uuid,
      '6bd30000-0000-4000-8000-000000000002'::uuid,
      '6bd40000-0000-4000-8000-000000000002'::uuid,
      '2030-04-09T12:00:00Z', 'UTC', '2030-04-09T12:00:00Z',
      'face_to_face', 'resolved', '6BD Nested Venue',
      'fixture-6bd-nested-venue', 'fixture-6bd-nested-v1', 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    ) VALUES (
      'fixture-6bd-nested-contact', 1, 'submitted',
      '6bd10000-0000-4000-8000-000000000001'::uuid,
      jsonb_build_object(
        'contactId', 'fixture-6bd-nested-contact',
        'location', jsonb_build_object(
          'kind', 'resolved', 'placeName', '6BD Nested Venue',
          'smallestRegionId', 'fixture-6bd-nested-venue',
          'regionTreeVersion', 'fixture-6bd-nested-v1'
        )
      )
    );
    PERFORM app_private.execute_management_original_region_contact_session_report_v1(
      '6bd30000-0000-4000-8000-000000000002'::uuid,
      'UTC', '2030-04-17T12:00:00Z'::timestamptz
    );
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'nested tree passed';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'nested city tree did not fail closed: %', failure_sqlstate;
  END IF;
END
$fixture_nested$;

ROLLBACK;
