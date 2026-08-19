-- Synthetic fixture for the private current-city snapshot lineage.
--
-- The fixture is intentionally self-contained.  0056's fixture is rolled back
-- in its own psql process, so a snapshot test cannot depend on its temporary
-- tables or rows.  All identifiers use the 6AO namespace and the transaction
-- is rolled back at the end.
\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_6ao_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-current-city-snapshot.supabase.co/auth/v1',
  'synthetic-6ao-owner'
);
RESET ROLE;

-- Keep the organization/project setup separate from the 6AN fixture.  The
-- release function derives its cutoff and reporting-time-zone revision from
-- the database, so the facts below are placed relative to one captured UTC
-- reference instead of using wall-clock literals.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('ab110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('ab110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('ab110000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name
) VALUES (
  'ab120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AO current-city snapshot workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'ab120000-0000-4000-8000-000000000001'::uuid,
    '6AO current-city snapshot project'
  ),
  (
    'ab130000-0000-4000-8000-000000000002'::uuid,
    'ab120000-0000-4000-8000-000000000001'::uuid,
    '6AO other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES
  (
    'ab140000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    'ab140000-0000-4000-8000-000000000002'::uuid,
    'ab130000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

-- The release function resolves the complete private authorization chain at
-- its transaction-time cutoff.  Keep these rows in the fixture namespace so
-- a dump/restore run cannot accidentally borrow another fixture's grant.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  'ab160000-0000-4000-8000-000000000001'::uuid,
  'ab120000-0000-4000-8000-000000000001'::uuid,
  'ab110000-0000-4000-8000-000000000001'::uuid,
  clock_timestamp() - interval '30 days',
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'ab170000-0000-4000-8000-000000000001'::uuid,
    'ab160000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'ab170000-0000-4000-8000-000000000002'::uuid,
    'ab160000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'ab180000-0000-4000-8000-000000000001'::uuid,
    'ab170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'ab180000-0000-4000-8000-000000000002'::uuid,
    'ab170000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  'ab150000-0000-4000-8000-000000000001'::uuid,
  'ab110000-0000-4000-8000-000000000001'::uuid,
  'ab130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

-- Four cities make the 6AN contract an eight-cell document (two periods ×
-- the complete city grid).  City C is the sparse/hidden cell; A, B and D have
-- 5/3/2 contributions from three users.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('fixture-6ao-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6ao-country', 'fixture-6ao-target-v1', NULL,
    '6AO Country', 'country'),
  ('fixture-6ao-city-a', 'fixture-6ao-target-v1', 'fixture-6ao-country',
    '6AO City A', 'city'),
  ('fixture-6ao-city-b', 'fixture-6ao-target-v1', 'fixture-6ao-country',
    '6AO City B', 'city'),
  ('fixture-6ao-city-c', 'fixture-6ao-target-v1', 'fixture-6ao-country',
    '6AO City C', 'city'),
  ('fixture-6ao-city-d', 'fixture-6ao-target-v1', 'fixture-6ao-country',
    '6AO City D', 'city'),
  ('fixture-6ao-venue-a', 'fixture-6ao-target-v1', 'fixture-6ao-city-a',
    '6AO Venue A', 'venue'),
  ('fixture-6ao-venue-b', 'fixture-6ao-target-v1', 'fixture-6ao-city-b',
    '6AO Venue B', 'venue'),
  ('fixture-6ao-venue-c', 'fixture-6ao-target-v1', 'fixture-6ao-city-c',
    '6AO Venue C', 'venue'),
  ('fixture-6ao-venue-d', 'fixture-6ao-target-v1', 'fixture-6ao-city-d',
    '6AO Venue D', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES
  ('fixture-6ao-boundary-a', 'fixture-6ao-venue-a', 'fixture-6ao-target-v1',
    polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'),
  ('fixture-6ao-boundary-b', 'fixture-6ao-venue-b', 'fixture-6ao-target-v1',
    polygon '((-87.61,41.69),(-87.59,41.69),(-87.59,41.71),(-87.61,41.71))'),
  ('fixture-6ao-boundary-c', 'fixture-6ao-venue-c', 'fixture-6ao-target-v1',
    polygon '((-87.41,41.69),(-87.39,41.69),(-87.39,41.71),(-87.41,41.71))'),
  ('fixture-6ao-boundary-d', 'fixture-6ao-venue-d', 'fixture-6ao-target-v1',
    polygon '((-87.21,41.69),(-87.19,41.69),(-87.19,41.71),(-87.21,41.71))');

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6ao-target-v1', true
);

CREATE TEMP TABLE fixture_6ao_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

CREATE TEMP TABLE fixture_6ao_expected_contacts AS
SELECT
  format(
    'fixture-6ao-%s-%s-u%s-%s',
    period_row.period_key,
    city_row.city_key,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  city_row.city_key,
  contributor_row.contributor_number,
  contributor_row.unit_count,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 day'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 day'
  END AS occurred_at_utc
FROM fixture_6ao_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES
  ('a', 5), ('b', 5), ('c', 4), ('d', 5)
) AS city_row(city_key, ignored_city_count)
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(
  1,
  CASE
    WHEN city_row.city_key = 'c'
      THEN CASE contributor_row.contributor_number
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
    WHEN 1 THEN 'ab110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN 'ab110000-0000-4000-8000-000000000002'::uuid
    ELSE 'ab110000-0000-4000-8000-000000000003'::uuid
  END,
  'ab120000-0000-4000-8000-000000000001'::uuid,
  'ab130000-0000-4000-8000-000000000001'::uuid,
  'ab140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc,
  'UTC',
  expected.occurred_at_utc,
  'face_to_face', 'resolved', '6AO synthetic venue',
  format('fixture-6ao-venue-%s', expected.city_key),
  'fixture-6ao-target-v1', 1, 2
FROM fixture_6ao_expected_contacts AS expected;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
)
SELECT
  expected.contact_id,
  1,
  'submitted',
  CASE expected.contributor_number
    WHEN 1 THEN 'ab110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN 'ab110000-0000-4000-8000-000000000002'::uuid
    ELSE 'ab110000-0000-4000-8000-000000000003'::uuid
  END,
  jsonb_build_object(
    'contactId', expected.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', '6AO synthetic venue',
      'smallestRegionId', format('fixture-6ao-venue-%s', expected.city_key),
      'regionTreeVersion', 'fixture-6ao-target-v1'
    )
  )
FROM fixture_6ao_expected_contacts AS expected;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
)
VALUES (
  'ab110000-0000-4000-8000-000000000001'::uuid,
  'ab120000-0000-4000-8000-000000000001'::uuid,
  'ab130000-0000-4000-8000-000000000001'::uuid,
  'fixture-6ao-current-watermark', 1, 'contact.submitted'
);

DO $fixture_6ao_snapshot_lineage$
DECLARE
  report_document jsonb;
  baseline_document jsonb;
  later_document jsonb;
  unavailable_document jsonb;
  no_shared_document jsonb;
  target_drift_document jsonb;
  mutated_document jsonb;
  mutated_cells jsonb;
  target_v2_release jsonb;
  target_v2_context jsonb;
  time_zone_result jsonb;
  pair_result jsonb;
  release_result jsonb;
  replay_result jsonb;
  rolling_result jsonb;
  value_blocked_result jsonb;
  privacy_blocked_result jsonb;
  baseline_snapshot_id uuid;
  rolling_snapshot_id uuid;
  compared_snapshot_id uuid;
  snapshot_count bigint;
  attempt_count bigint;
  blocked_audit text;
  future_cutoff timestamptz;
  target_v2_fingerprint text;
  target_v2_published_at timestamptz;
BEGIN
  report_document := app_private.execute_management_current_city_contact_session_report_v1(
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'UTC',
    (SELECT data_cutoff_utc FROM fixture_6ao_report_context)
  );

  PERFORM app_private.validate_management_current_city_report_document_v1(
    report_document
  );

  IF report_document->>'report_id'
      IS DISTINCT FROM 'contact_sessions_by_current_city_two_periods'
    OR report_document->>'report_version' IS DISTINCT FROM '1'
    OR report_document->>'metric_id' IS DISTINCT FROM 'contact_sessions'
    OR report_document->>'metric_version' IS DISTINCT FROM '1'
    OR report_document->>'dimension' IS DISTINCT FROM 'current_city'
    OR report_document->>'view_mode' IS DISTINCT FROM 'current'
    OR report_document->>'region_granularity' IS DISTINCT FROM 'city'
    OR report_document->>'result_status' IS DISTINCT FROM 'completed'
    OR jsonb_array_length(report_document->'cells') <> 8
    OR report_document::text ~ '(contributor|source_id|contact_id|place_name|latitude|longitude)'
  THEN
    RAISE EXCEPTION 'valid 6AN report has the wrong 6AO snapshot shape: %',
      report_document;
  END IF;

  -- Every city/period is present; hidden values are JSON null.  This also
  -- protects the release path from accidentally reusing the legacy 16-cell
  -- channel validator.
  IF (
    SELECT count(*)
    FROM jsonb_array_elements(report_document->'cells') AS cell(value)
    WHERE value->>'period_key' IN ('previous', 'current')
      AND value->>'city_id' IN (
        'fixture-6ao-city-a', 'fixture-6ao-city-b',
        'fixture-6ao-city-c', 'fixture-6ao-city-d'
      )
  ) <> 8
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(report_document->'cells') AS cell(value)
    WHERE value->>'privacy_status' = 'suppressed'
      AND value->'value_count' <> 'null'::jsonb
  ) THEN
    RAISE EXCEPTION '6AO complete grid or null suppression contract failed';
  END IF;

  -- A cutoff before the first published selection is a safe, value-free
  -- unavailable result rather than a partial report.
  unavailable_document :=
    app_private.execute_management_current_city_contact_session_report_v1(
      'ab130000-0000-4000-8000-000000000001'::uuid,
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
    RAISE EXCEPTION '6AO unavailable result is not value-free: %',
      unavailable_document;
  END IF;

  -- Identity, period, grid order/cardinality and privacy shape are all
  -- fail-closed validator boundaries, not release-time heuristics.
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(
        report_document,
        '{report_id}',
        to_jsonb('wrong_current_city_identity'::text)
      )
    );
    RAISE EXCEPTION '6AO validator accepted a wrong report identity';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.release_management_current_city_report_snapshot_v1(
      'ab800000-0000-4000-8000-000000000006'::uuid,
      'ab110000-0000-4000-8000-000000000001'::uuid,
      'ab130000-0000-4000-8000-000000000001'::uuid,
      'wrong_current_city_identity',
      1
    );
    RAISE EXCEPTION '6AO release accepted a wrong report identity';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(
        report_document,
        '{periods,previous_period,until_utc}',
        to_jsonb('2000-01-01T00:00:00.000Z'::text)
      )
    );
    RAISE EXCEPTION '6AO validator accepted period boundary drift';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(
        report_document,
        '{cells,1,city_id}',
        report_document->'cells'->0->'city_id'
      )
    );
    RAISE EXCEPTION '6AO validator accepted a duplicate city cell';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  SELECT jsonb_agg(
    CASE cell.ordinality
      WHEN 1 THEN report_document->'cells'->1
      WHEN 2 THEN report_document->'cells'->0
      ELSE cell.value
    END
    ORDER BY cell.ordinality
  )
  INTO mutated_cells
  FROM jsonb_array_elements(report_document->'cells')
    WITH ORDINALITY AS cell(value, ordinality);
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AO validator accepted a physically out-of-order cell grid';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(
        report_document,
        '{cells,0,contact_id}',
        to_jsonb('sensitive-contact-fixture'::text)
      )
    );
    RAISE EXCEPTION '6AO validator accepted a sensitive cell field';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SELECT jsonb_agg(
    CASE
      WHEN cell.value->>'privacy_status' = 'displayed'
        AND cell.ordinality = min_displayed.ordinality
      THEN jsonb_set(cell.value, '{value_count}', to_jsonb(9))
      ELSE cell.value
    END
    ORDER BY cell.ordinality
  )
  INTO mutated_cells
  FROM jsonb_array_elements(report_document->'cells')
    WITH ORDINALITY AS cell(value, ordinality)
  CROSS JOIN LATERAL (
    SELECT min(displayed.ordinality) AS ordinality
    FROM jsonb_array_elements(report_document->'cells')
      WITH ORDINALITY AS displayed(value, ordinality)
    WHERE displayed.value->>'privacy_status' = 'displayed'
  ) AS min_displayed;
  IF mutated_cells IS NULL THEN
    RAISE EXCEPTION '6AO fixture did not produce a displayed threshold cell';
  END IF;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AO validator accepted a displayed value below threshold';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SELECT jsonb_agg(
    CASE
      WHEN cell.value->>'privacy_status' = 'suppressed'
        AND cell.ordinality = min_suppressed.ordinality
      THEN jsonb_set(cell.value, '{value_count}', to_jsonb(0))
      ELSE cell.value
    END
    ORDER BY cell.ordinality
  )
  INTO mutated_cells
  FROM jsonb_array_elements(report_document->'cells')
    WITH ORDINALITY AS cell(value, ordinality)
  CROSS JOIN LATERAL (
    SELECT min(suppressed.ordinality) AS ordinality
    FROM jsonb_array_elements(report_document->'cells')
      WITH ORDINALITY AS suppressed(value, ordinality)
    WHERE suppressed.value->>'privacy_status' = 'suppressed'
  ) AS min_suppressed;
  IF mutated_cells IS NULL THEN
    RAISE EXCEPTION '6AO fixture did not produce a suppressed cell';
  END IF;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AO validator accepted a non-null suppressed value';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      report_document || jsonb_build_object('unexpected', true)
    );
    RAISE EXCEPTION '6AO validator accepted an extra top-level field';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(
        report_document,
        '{target_context,target_tree_version}',
        to_jsonb('fixture-6ao-target-does-not-exist'::text)
      )
    );
    RAISE EXCEPTION '6AO validator accepted an unknown target tree';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.validate_management_current_city_report_document_v1(
      jsonb_set(report_document, '{cells}', '[]'::jsonb)
    );
    RAISE EXCEPTION '6AO validator accepted an incomplete city grid';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- A pair must advance its cutoff.  The same document therefore exercises
  -- the fail-closed cutoff guard; a later unchanged document is tested below.
  pair_result := app_private.assess_management_current_city_report_pair_release_v1(
    report_document, report_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'release_lineage_context_changed')
  THEN
    RAISE EXCEPTION 'same-cutoff 6AO pair did not fail closed: %', pair_result;
  END IF;

  release_result := app_private.release_management_current_city_report_snapshot_v1(
    'ab800000-0000-4000-8000-000000000001'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR release_result->>'released_snapshot_id' IS NULL
    OR release_result ? 'protected_report'
    OR release_result ? 'cells'
  THEN
    RAISE EXCEPTION '6AO baseline release contract failed: %', release_result;
  END IF;
  baseline_snapshot_id := (release_result->>'released_snapshot_id')::uuid;

  SELECT count(*) INTO snapshot_count
  FROM app_private.management_report_snapshots
  WHERE project_id = 'ab130000-0000-4000-8000-000000000001'::uuid;
  SELECT count(*) INTO attempt_count
  FROM app_private.management_current_city_report_release_attempts
  WHERE project_id = 'ab130000-0000-4000-8000-000000000001'::uuid;

  replay_result := app_private.release_management_current_city_report_snapshot_v1(
    'ab800000-0000-4000-8000-000000000001'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods',
    1
  );
  IF replay_result IS DISTINCT FROM release_result
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE project_id = 'ab130000-0000-4000-8000-000000000001'::uuid)
        <> snapshot_count
    OR (SELECT count(*) FROM app_private.management_current_city_report_release_attempts
        WHERE project_id = 'ab130000-0000-4000-8000-000000000001'::uuid)
        <> attempt_count
  THEN
    RAISE EXCEPTION '6AO same-request replay was not exact and idempotent';
  END IF;

  -- A later unchanged state is an approved rolling release and points back to
  -- the baseline. Sleep avoids a platform clock with only millisecond
  -- precision producing an indistinguishable cutoff.
  PERFORM pg_sleep(0.01);
  rolling_result := app_private.release_management_current_city_report_snapshot_v1(
    'ab800000-0000-4000-8000-000000000002'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods',
    1
  );
  IF rolling_result->>'result_status' IS DISTINCT FROM 'approved'
    OR (rolling_result->>'released_snapshot_id')::uuid IS NULL
    OR (rolling_result->>'compared_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
    OR rolling_result ? 'protected_report'
    OR rolling_result ? 'cells'
  THEN
    RAISE EXCEPTION '6AO rolling release contract failed: %', rolling_result;
  END IF;
  rolling_snapshot_id := (rolling_result->>'released_snapshot_id')::uuid;

  SELECT snapshot.protected_report
  INTO STRICT baseline_document
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;
  SELECT snapshot.previous_snapshot_id
  INTO STRICT compared_snapshot_id
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = rolling_snapshot_id;
  IF compared_snapshot_id IS DISTINCT FROM baseline_snapshot_id THEN
    RAISE EXCEPTION '6AO rolling snapshot lost its previous pointer';
  END IF;

  later_document := app_private.execute_management_current_city_contact_session_report_v1(
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'UTC',
    clock_timestamp()
  );
  pair_result := app_private.assess_management_current_city_report_pair_release_v1(
    baseline_document, later_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'approved'
    OR pair_result->>'shared_period_count' IS DISTINCT FROM '2'
    OR pair_result->>'assessed_cell_count' IS DISTINCT FROM '8'
  THEN
    RAISE EXCEPTION 'unchanged later 6AO pair was not stable: %', pair_result;
  END IF;

  -- Passing the newer document as the earlier side exercises an earlier
  -- cutoff; the pair contract must remain blocked rather than accepting a
  -- backwards lineage.
  pair_result := app_private.assess_management_current_city_report_pair_release_v1(
    later_document, baseline_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'release_lineage_context_changed')
  THEN
    RAISE EXCEPTION 'earlier 6AO cutoff was not blocked: %', pair_result;
  END IF;

  -- Use the canonical resolver for the synthetic future document.  This keeps
  -- the test valid across ISO-week and DST boundaries as the validator's
  -- exact-period contract evolves.
  future_cutoff :=
    (report_document->'periods'->'current_period'->>'until_utc')::timestamptz
      + interval '15 days';
  no_shared_document := report_document;
  no_shared_document := jsonb_set(
    no_shared_document,
    '{data_cutoff_utc}',
    to_jsonb(to_char(
      future_cutoff AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ))
  );
  no_shared_document := jsonb_set(
    no_shared_document,
    '{periods}',
    app_private.resolve_management_report_periods_v1(
      'UTC', future_cutoff
    )
  );
  no_shared_document := jsonb_set(
    no_shared_document,
    '{target_context,data_cutoff_utc}',
    no_shared_document->'data_cutoff_utc'
  );
  PERFORM app_private.validate_management_current_city_report_document_v1(
    no_shared_document
  );
  pair_result := app_private.assess_management_current_city_report_pair_release_v1(
    report_document, no_shared_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'no_shared_period')
  THEN
    RAISE EXCEPTION 'no-shared-period 6AO pair was not blocked: %', pair_result;
  END IF;

  -- One new accepted contact in a displayed city changes a shared value.  The
  -- attempted report is never stored in either release history.
  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    first_submitted_at_utc, channel, location_kind, place_name,
    smallest_region_id, region_tree_version, reach_count, interest_level
  )
  SELECT
    'fixture-6ao-late-city-b',
    'ab110000-0000-4000-8000-000000000003'::uuid,
    'ab120000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'ab140000-0000-4000-8000-000000000001'::uuid,
    (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '2 days',
    'UTC',
    (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '2 days',
    'face_to_face', 'resolved', '6AO late venue B',
    'fixture-6ao-venue-b', 'fixture-6ao-target-v1', 1, 2
  FROM fixture_6ao_report_context AS context;
  INSERT INTO app_data.contact_revisions (
    contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
  ) VALUES (
    'fixture-6ao-late-city-b', 1, 'submitted',
    'ab110000-0000-4000-8000-000000000003'::uuid,
    jsonb_build_object(
      'contactId', 'fixture-6ao-late-city-b',
      'location', jsonb_build_object(
        'kind', 'resolved', 'placeName', '6AO late venue B',
        'smallestRegionId', 'fixture-6ao-venue-b',
        'regionTreeVersion', 'fixture-6ao-target-v1'
      )
    )
  );
  INSERT INTO app_data.change_feed (
    app_user_id, workspace_id, project_id, aggregate_id, revision_number,
    change_type
  ) VALUES (
    'ab110000-0000-4000-8000-000000000003'::uuid,
    'ab120000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'fixture-6ao-late-city-b', 1, 'contact.submitted'
  );

  PERFORM pg_sleep(0.01);
  value_blocked_result := app_private.release_management_current_city_report_snapshot_v1(
    'ab800000-0000-4000-8000-000000000003'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods',
    1
  );
  IF value_blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (value_blocked_result->'reason_codes'
      ? 'shared_displayed_value_changed')
    OR value_blocked_result->>'released_snapshot_id' IS NOT NULL
  THEN
    RAISE EXCEPTION '6AO displayed-value change was not blocked: %',
      value_blocked_result;
  END IF;

  -- Raise the sparse city to the privacy threshold. This exercises the
  -- suppressed/displayed side of pair comparison independently of values.
  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    first_submitted_at_utc, channel, location_kind, place_name,
    smallest_region_id, region_tree_version, reach_count, interest_level
  )
  SELECT
    'fixture-6ao-late-city-c',
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab120000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'ab140000-0000-4000-8000-000000000001'::uuid,
    (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '2 days',
    'UTC',
    (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '2 days',
    'face_to_face', 'resolved', '6AO late venue C',
    'fixture-6ao-venue-c', 'fixture-6ao-target-v1', 1, 2
  FROM fixture_6ao_report_context AS context;
  INSERT INTO app_data.contact_revisions (
    contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
  ) VALUES (
    'fixture-6ao-late-city-c', 1, 'submitted',
    'ab110000-0000-4000-8000-000000000001'::uuid,
    jsonb_build_object(
      'contactId', 'fixture-6ao-late-city-c',
      'location', jsonb_build_object(
        'kind', 'resolved', 'placeName', '6AO late venue C',
        'smallestRegionId', 'fixture-6ao-venue-c',
        'regionTreeVersion', 'fixture-6ao-target-v1'
      )
    )
  );
  INSERT INTO app_data.change_feed (
    app_user_id, workspace_id, project_id, aggregate_id, revision_number,
    change_type
  ) VALUES (
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab120000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'fixture-6ao-late-city-c', 1, 'contact.submitted'
  );

  PERFORM pg_sleep(0.01);
  privacy_blocked_result := app_private.release_management_current_city_report_snapshot_v1(
    'ab800000-0000-4000-8000-000000000004'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods',
    1
  );
  IF privacy_blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (privacy_blocked_result->'reason_codes'
      ? 'shared_cell_privacy_status_changed')
    OR privacy_blocked_result->>'released_snapshot_id' IS NOT NULL
  THEN
    RAISE EXCEPTION '6AO privacy transition was not blocked: %',
      privacy_blocked_result;
  END IF;

  -- Publish an equivalent city grid under a new immutable target tuple.  The
  -- pair assessor must report target drift without exposing candidate cells.
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES ('fixture-6ao-target-v2', 'draft', false);
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  )
  VALUES
    ('fixture-6ao-country', 'fixture-6ao-target-v2', NULL,
      '6AO Country', 'country'),
    ('fixture-6ao-city-a', 'fixture-6ao-target-v2', 'fixture-6ao-country',
      '6AO City A', 'city'),
    ('fixture-6ao-city-b', 'fixture-6ao-target-v2', 'fixture-6ao-country',
      '6AO City B', 'city'),
    ('fixture-6ao-city-c', 'fixture-6ao-target-v2', 'fixture-6ao-country',
      '6AO City C', 'city'),
    ('fixture-6ao-city-d', 'fixture-6ao-target-v2', 'fixture-6ao-country',
      '6AO City D', 'city'),
    ('fixture-6ao-venue-a', 'fixture-6ao-target-v2', 'fixture-6ao-city-a',
      '6AO Venue A', 'venue'),
    ('fixture-6ao-venue-b', 'fixture-6ao-target-v2', 'fixture-6ao-city-b',
      '6AO Venue B', 'venue'),
    ('fixture-6ao-venue-c', 'fixture-6ao-target-v2', 'fixture-6ao-city-c',
      '6AO Venue C', 'venue'),
    ('fixture-6ao-venue-d', 'fixture-6ao-target-v2', 'fixture-6ao-city-d',
      '6AO Venue D', 'venue');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  )
  VALUES
    ('fixture-6ao-boundary-v2-a', 'fixture-6ao-venue-a',
      'fixture-6ao-target-v2',
      polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'),
    ('fixture-6ao-boundary-v2-b', 'fixture-6ao-venue-b',
      'fixture-6ao-target-v2',
      polygon '((-87.61,41.69),(-87.59,41.69),(-87.59,41.71),(-87.61,41.71))'),
    ('fixture-6ao-boundary-v2-c', 'fixture-6ao-venue-c',
      'fixture-6ao-target-v2',
      polygon '((-87.41,41.69),(-87.39,41.69),(-87.39,41.71),(-87.41,41.71))'),
    ('fixture-6ao-boundary-v2-d', 'fixture-6ao-venue-d',
      'fixture-6ao-target-v2',
      polygon '((-87.21,41.69),(-87.19,41.69),(-87.19,41.71),(-87.21,41.71))');
  SELECT app_private.publish_canonical_region_tree_v1(
    'fixture-6ao-target-v2', true
  ) INTO target_v2_release;
  target_v2_fingerprint := target_v2_release->>'content_fingerprint';
  target_v2_published_at :=
    (target_v2_release->>'published_at_utc')::timestamptz;

  -- Use a cutoff shortly after publication but before the next ISO-week
  -- boundary, so the two documents share periods and differ only in target
  -- lineage.  Resolve the actual selection context instead of fabricating a
  -- sequence, source or evidence timestamp.
  target_drift_document := later_document;
  future_cutoff :=
    clock_timestamp() + interval '1 hour';
  target_drift_document := jsonb_set(
    target_drift_document,
    '{data_cutoff_utc}',
    to_jsonb(to_char(
      future_cutoff AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ))
  );
  target_drift_document := jsonb_set(
    target_drift_document,
    '{periods}',
    app_private.resolve_management_report_periods_v1(
      'UTC', future_cutoff
    )
  );
  target_v2_context :=
    app_private.resolve_management_current_city_target_context_v1(
      future_cutoff
    );
  IF target_v2_context->>'target_tree_version'
      IS DISTINCT FROM 'fixture-6ao-target-v2'
    OR target_v2_context->>'selection_source' IS DISTINCT FROM 'publication'
  THEN
    RAISE EXCEPTION '6AO target v2 selection context was not current: %',
      target_v2_context;
  END IF;
  target_drift_document := jsonb_set(
    target_drift_document,
    '{target_context}',
    target_v2_context
  );
  PERFORM app_private.validate_management_current_city_report_document_v1(
    target_drift_document
  );
  pair_result := app_private.assess_management_current_city_report_pair_release_v1(
    later_document, target_drift_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes'
      ? 'release_target_context_changed')
  THEN
    RAISE EXCEPTION '6AO target tuple drift was not blocked: %', pair_result;
  END IF;
  mutated_document := pair_result;
  pair_result := app_private.assess_management_current_city_report_pair_release_v1(
    later_document, target_drift_document
  );
  IF pair_result IS DISTINCT FROM mutated_document THEN
    RAISE EXCEPTION '6AO target tuple drift reason was not stable';
  END IF;

  -- A new effective timezone revision blocks the release before candidate
  -- report materialization.  Use the prior ISO-week boundary so version 2 is
  -- already effective at the transaction-time authorization cutoff.
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'ab150000-0000-4000-8000-000000000002'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    1,
    'America/Chicago',
    date_trunc('week', clock_timestamp()) - interval '7 days'
  ) INTO time_zone_result;
  IF time_zone_result->>'version_number' IS DISTINCT FROM '2' THEN
    RAISE EXCEPTION '6AO timezone revision setup failed: %', time_zone_result;
  END IF;
  PERFORM pg_sleep(0.01);
  release_result := app_private.release_management_current_city_report_snapshot_v1(
    'ab800000-0000-4000-8000-000000000005'::uuid,
    'ab110000-0000-4000-8000-000000000001'::uuid,
    'ab130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (release_result->'reason_codes'
      ? 'release_time_zone_revision_changed')
    OR release_result->>'released_snapshot_id' IS NOT NULL
  THEN
    RAISE EXCEPTION '6AO timezone revision was not blocked: %', release_result;
  END IF;

  snapshot_count := (
    SELECT count(*)
    FROM app_private.management_report_snapshots
    WHERE project_id = 'ab130000-0000-4000-8000-000000000001'::uuid
  );
  attempt_count := (
    SELECT count(*)
    FROM app_private.management_current_city_report_release_attempts
    WHERE project_id = 'ab130000-0000-4000-8000-000000000001'::uuid
  );
  IF snapshot_count <> 2 OR attempt_count <> 5 THEN
    RAISE EXCEPTION '6AO blocked releases changed approved history: snapshots %, attempts %',
      snapshot_count, attempt_count;
  END IF;

  -- A UUID claimed by either channel release contract cannot be reused for
  -- current-city, even if no old attempt row is visible to this function.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id,
    release_family_id
  ) VALUES (
    'ab800000-0000-4000-8000-000000000007'::uuid,
    'channel_management_report_snapshot_release'
  );
  BEGIN
    PERFORM app_private.release_management_current_city_report_snapshot_v1(
      'ab800000-0000-4000-8000-000000000007'::uuid,
      'ab110000-0000-4000-8000-000000000001'::uuid,
      'ab130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_current_city_two_periods',
      1
    );
    RAISE EXCEPTION '6AO reused a channel release request UUID';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    UPDATE app_private.management_report_release_request_claims
    SET release_family_id = 'current_city_management_report_snapshot_release'
    WHERE release_request_id =
      'ab800000-0000-4000-8000-000000000007'::uuid;
    RAISE EXCEPTION '6AO request claim was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_report_release_request_claims
    WHERE release_request_id =
      'ab800000-0000-4000-8000-000000000007'::uuid;
    RAISE EXCEPTION '6AO request claim was deletable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  -- Direct table writes still pass through the fixed reason-code allowlist.
  -- Rebuilding the result document keeps the test focused on that boundary.
  BEGIN
    INSERT INTO app_private.management_current_city_report_release_attempts (
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
      target_tree_version,
      target_content_fingerprint,
      compared_snapshot_id,
      released_snapshot_id,
      result_status,
      reason_codes,
      result_document
    )
    SELECT
      'ab800000-0000-4000-8000-000000000008'::uuid,
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
      attempt.target_tree_version,
      attempt.target_content_fingerprint,
      attempt.compared_snapshot_id,
      NULL,
      'blocked',
      jsonb_build_array('invented_release_reason'),
      jsonb_set(
        jsonb_set(
          attempt.result_document,
          '{release_request_id}',
          to_jsonb('ab800000-0000-4000-8000-000000000008'::uuid)
        ),
        '{reason_codes}',
        jsonb_build_array('invented_release_reason')
      )
    FROM app_private.management_current_city_report_release_attempts AS attempt
    WHERE attempt.release_request_id =
      'ab800000-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION '6AO stored an unknown blocked reason code';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SELECT string_agg(to_jsonb(attempt_row)::text, ' ')
  INTO blocked_audit
  FROM app_private.management_current_city_report_release_attempts AS attempt_row
  WHERE attempt_row.result_status = 'blocked';
  IF coalesce(blocked_audit, '') ~
      '(cells|value_count|contributor|source_id|contact_id|latitude|longitude)'
  THEN
    RAISE EXCEPTION '6AO blocked audit exposed protected values';
  END IF;

  -- The old channel validator must remain the only owner of the old report
  -- shape; a current-city document cannot enter its release path.
  BEGIN
    PERFORM app_private.validate_management_report_document_v1(report_document);
    RAISE EXCEPTION 'legacy channel validator accepted a current-city document';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- The generic snapshot history is immutable.  The region attempt history is
  -- checked separately because 0057 intentionally gives it a region-specific
  -- provenance contract.
  BEGIN
    UPDATE app_private.management_report_snapshots
    SET released_at_utc = released_at_utc + interval '1 second'
    WHERE snapshot_id = baseline_snapshot_id;
    RAISE EXCEPTION '6AO snapshot was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_report_snapshots
    WHERE snapshot_id = baseline_snapshot_id;
    RAISE EXCEPTION '6AO snapshot was deletable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
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
      'ab810000-0000-4000-8000-000000000009'::uuid,
      'ab800000-0000-4000-8000-000000000009'::uuid,
      snapshot.created_by_app_user_id,
      snapshot.project_id,
      snapshot.release_lineage_id,
      snapshot.report_id,
      snapshot.report_version,
      snapshot.query_fingerprint,
      snapshot.reporting_time_zone,
      snapshot.data_cutoff_utc,
      snapshot.released_at_utc,
      NULL,
      snapshot.source_change_sequence + 1,
      snapshot.protected_report
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = baseline_snapshot_id;
    RAISE EXCEPTION '6AO snapshot accepted a mismatched source watermark';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    UPDATE app_private.management_current_city_report_release_attempts
    SET result_status = 'approved'
    WHERE release_request_id =
      'ab800000-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION '6AO release-attempt history was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_current_city_report_release_attempts
    WHERE release_request_id =
      'ab800000-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION '6AO release-attempt history was deletable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
  IF baseline_snapshot_id IS NULL OR rolling_snapshot_id IS NULL THEN
    RAISE EXCEPTION '6AO approved snapshot IDs were lost';
  END IF;
END
$fixture_6ao_snapshot_lineage$;

ROLLBACK;
