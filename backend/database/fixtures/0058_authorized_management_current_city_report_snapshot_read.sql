-- Synthetic fixture for the private current-city snapshot read contract.
--
-- This fixture creates a current-city baseline through 0057, reads it through
-- 6AP, and proves that the generic channel read cannot consume it.  All rows
-- are rolled back; identifiers use the 6AP namespace so restored/concurrent
-- databases cannot accidentally borrow another fixture's data.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('ad110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('ad110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('ad110000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('ad110000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
) VALUES (
  'ad120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AP current-city read workspace',
  NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    'ad130000-0000-4000-8000-000000000001'::uuid,
    'ad120000-0000-4000-8000-000000000001'::uuid,
    '6AP current-city read project'
  ),
  (
    'ad130000-0000-4000-8000-000000000002'::uuid,
    'ad120000-0000-4000-8000-000000000001'::uuid,
    '6AP other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES
  (
    'ad140000-0000-4000-8000-000000000001'::uuid,
    'ad130000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    'ad140000-0000-4000-8000-000000000002'::uuid,
    'ad130000-0000-4000-8000-000000000002'::uuid,
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
    'ad160000-0000-4000-8000-000000000001'::uuid,
    'ad120000-0000-4000-8000-000000000001'::uuid,
    'ad110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad160000-0000-4000-8000-000000000002'::uuid,
    'ad120000-0000-4000-8000-000000000001'::uuid,
    'ad110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad160000-0000-4000-8000-000000000003'::uuid,
    'ad120000-0000-4000-8000-000000000001'::uuid,
    'ad110000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad160000-0000-4000-8000-000000000004'::uuid,
    'ad120000-0000-4000-8000-000000000001'::uuid,
    'ad110000-0000-4000-8000-000000000004'::uuid,
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
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
    'ad170000-0000-4000-8000-000000000001'::uuid,
    'ad160000-0000-4000-8000-000000000001'::uuid,
    'ad130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad170000-0000-4000-8000-000000000002'::uuid,
    'ad160000-0000-4000-8000-000000000002'::uuid,
    'ad130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad170000-0000-4000-8000-000000000003'::uuid,
    'ad160000-0000-4000-8000-000000000003'::uuid,
    'ad130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad170000-0000-4000-8000-000000000004'::uuid,
    'ad160000-0000-4000-8000-000000000004'::uuid,
    'ad130000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    'ad170000-0000-4000-8000-000000000005'::uuid,
    'ad160000-0000-4000-8000-000000000002'::uuid,
    'ad130000-0000-4000-8000-000000000002'::uuid,
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
    'ad180000-0000-4000-8000-000000000001'::uuid,
    'ad170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad180000-0000-4000-8000-000000000002'::uuid,
    'ad170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad180000-0000-4000-8000-000000000003'::uuid,
    'ad170000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ad180000-0000-4000-8000-000000000004'::uuid,
    'ad170000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    'ad180000-0000-4000-8000-000000000005'::uuid,
    'ad170000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  'ad150000-0000-4000-8000-000000000001'::uuid,
  'ad110000-0000-4000-8000-000000000001'::uuid,
  'ad130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('fixture-6ap-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6ap-country', 'fixture-6ap-target-v1', NULL,
    '6AP Country', 'country'),
  ('fixture-6ap-city-a', 'fixture-6ap-target-v1', 'fixture-6ap-country',
    '6AP City A', 'city'),
  ('fixture-6ap-city-b', 'fixture-6ap-target-v1', 'fixture-6ap-country',
    '6AP City B', 'city'),
  ('fixture-6ap-city-c', 'fixture-6ap-target-v1', 'fixture-6ap-country',
    '6AP City C', 'city'),
  ('fixture-6ap-venue-a', 'fixture-6ap-target-v1', 'fixture-6ap-city-a',
    '6AP Venue A', 'venue'),
  ('fixture-6ap-venue-b', 'fixture-6ap-target-v1', 'fixture-6ap-city-b',
    '6AP Venue B', 'venue'),
  ('fixture-6ap-venue-c', 'fixture-6ap-target-v1', 'fixture-6ap-city-c',
    '6AP Venue C', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES
  ('fixture-6ap-boundary-a', 'fixture-6ap-venue-a', 'fixture-6ap-target-v1',
    polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'),
  ('fixture-6ap-boundary-b', 'fixture-6ap-venue-b', 'fixture-6ap-target-v1',
    polygon '((-87.61,41.69),(-87.59,41.69),(-87.59,41.71),(-87.61,41.71))'),
  ('fixture-6ap-boundary-c', 'fixture-6ap-venue-c', 'fixture-6ap-target-v1',
    polygon '((-87.41,41.69),(-87.39,41.69),(-87.39,41.71),(-87.41,41.69))');

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6ap-target-v1', true
);

CREATE TEMP TABLE fixture_6ap_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

CREATE TEMP TABLE fixture_6ap_expected_contacts AS
SELECT
  format(
    'fixture-6ap-%s-%s-u%s-%s',
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
FROM fixture_6ap_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES
  ('a', 5), ('b', 5), ('c', 4)
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
    WHEN 1 THEN 'ad110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN 'ad110000-0000-4000-8000-000000000002'::uuid
    ELSE 'ad110000-0000-4000-8000-000000000003'::uuid
  END,
  'ad120000-0000-4000-8000-000000000001'::uuid,
  'ad130000-0000-4000-8000-000000000001'::uuid,
  'ad140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc,
  'UTC',
  expected.occurred_at_utc,
  'face_to_face', 'resolved', '6AP synthetic venue',
  format('fixture-6ap-venue-%s', expected.city_key),
  'fixture-6ap-target-v1', 1, 2
FROM fixture_6ap_expected_contacts AS expected;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
)
SELECT
  expected.contact_id,
  1,
  'submitted',
  CASE expected.contributor_number
    WHEN 1 THEN 'ad110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN 'ad110000-0000-4000-8000-000000000002'::uuid
    ELSE 'ad110000-0000-4000-8000-000000000003'::uuid
  END,
  jsonb_build_object(
    'contactId', expected.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', '6AP synthetic venue',
      'smallestRegionId', format('fixture-6ap-venue-%s', expected.city_key),
      'regionTreeVersion', 'fixture-6ap-target-v1'
    )
  )
FROM fixture_6ap_expected_contacts AS expected;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
)
VALUES (
  'ad110000-0000-4000-8000-000000000001'::uuid,
  'ad120000-0000-4000-8000-000000000001'::uuid,
  'ad130000-0000-4000-8000-000000000001'::uuid,
  'fixture-6ap-current-city-watermark', 1, 'contact.submitted'
);

DO $fixture_6ap_read$
DECLARE
  release_result jsonb;
  rolling_release_result jsonb;
  baseline_snapshot_id uuid;
  trusted_snapshot_id uuid;
  trusted_report jsonb;
  current_read jsonb;
  repeated_read jsonb;
  legacy_read jsonb;
  generic_current_read jsonb;
  unavailable_read jsonb;
  cross_project_read jsonb;
  legacy_snapshot_id uuid;
  event_count bigint;
  history_text text;
  authorization_evidence jsonb;
  current_attempt
    app_private.management_current_city_report_release_attempts%ROWTYPE;
BEGIN
  release_result :=
    app_private.release_management_current_city_report_snapshot_v1(
      'ad190000-0000-4000-8000-000000000001'::uuid,
      'ad110000-0000-4000-8000-000000000001'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_current_city_two_periods',
      1
    );

  IF release_result->>'result_status' <> 'approved_baseline'
    OR release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION '6AP fixture could not create current-city baseline: %',
      release_result;
  END IF;

  trusted_snapshot_id =
    (release_result->>'released_snapshot_id')::uuid;

  baseline_snapshot_id = trusted_snapshot_id;
  -- The read contract must accept an approved rolling attempt, not only the
  -- approved_baseline status used for the first snapshot.
  PERFORM pg_sleep(0.01);
  rolling_release_result :=
    app_private.release_management_current_city_report_snapshot_v1(
      'ad190000-0000-4000-8000-000000000003'::uuid,
      'ad110000-0000-4000-8000-000000000001'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_current_city_two_periods',
      1
    );
  IF rolling_release_result->>'result_status' IS DISTINCT FROM 'approved'
    OR rolling_release_result->>'released_snapshot_id' IS NULL
    OR (rolling_release_result->>'compared_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
  THEN
    RAISE EXCEPTION '6AP approved rolling release contract failed: %',
      rolling_release_result;
  END IF;
  trusted_snapshot_id =
    (rolling_release_result->>'released_snapshot_id')::uuid;

  SELECT snapshot.protected_report
  INTO STRICT trusted_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = trusted_snapshot_id;

  current_read =
    app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );

  IF current_read->>'access_contract_id'
      <> 'authorized_current_city_management_report_snapshot_read_v1'
    OR current_read->>'result_status' <> 'completed'
    OR current_read->>'reason_code' IS NOT NULL
    OR (current_read->>'resolved_snapshot_id')::uuid <> trusted_snapshot_id
    OR current_read->'protected_report' <> trusted_report
    OR jsonb_array_length(current_read->'protected_report'->'cells') <> 6
    OR NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(current_read->'protected_report'->'cells')
        AS cell(item)
      WHERE cell.item->>'privacy_status' = 'suppressed'
        AND cell.item->'value_count' = 'null'::jsonb
    )
  THEN
    RAISE EXCEPTION 'authorized current-city read returned an invalid report';
  END IF;

  repeated_read =
    app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
  IF repeated_read->'protected_report' <> trusted_report
    OR repeated_read->>'access_event_id' = current_read->>'access_event_id'
  THEN
    RAISE EXCEPTION 'repeated current-city read changed the snapshot or audit';
  END IF;

  -- A legacy channel snapshot is deliberately created with the generic v1
  -- release path.  It must remain untrusted to the 6AP contract.
  PERFORM app_private.release_management_report_snapshot_v1(
    'ad190000-0000-4000-8000-000000000002'::uuid,
    'ad110000-0000-4000-8000-000000000001'::uuid,
    'ad130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    (release_result->>'data_cutoff_utc')::timestamptz + interval '1 second',
    (release_result->>'data_cutoff_utc')::timestamptz + interval '1 second'
  );
  SELECT attempt.released_snapshot_id
  INTO STRICT legacy_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    'ad190000-0000-4000-8000-000000000002'::uuid;

  legacy_read =
    app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      legacy_snapshot_id
    );
  generic_current_read =
    app_private.read_authorized_management_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
  IF legacy_read->>'result_status' <> 'untrusted_provenance'
    OR legacy_read->>'reason_code' <> 'snapshot_provenance_untrusted'
    OR legacy_read ? 'protected_report'
    OR generic_current_read->>'result_status' <> 'untrusted_provenance'
    OR generic_current_read ? 'protected_report'
  THEN
    RAISE EXCEPTION 'channel and current-city provenance crossed a read boundary';
  END IF;

  unavailable_read =
    app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      'ada00000-0000-4000-8000-000000000001'::uuid
    );
  cross_project_read =
    app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000002'::uuid,
      trusted_snapshot_id
    );
  IF unavailable_read->>'result_status' <> 'not_found'
    OR unavailable_read->>'reason_code' <> 'snapshot_not_available'
    OR unavailable_read ? 'protected_report'
    OR cross_project_read->>'result_status' <> 'not_found'
    OR cross_project_read->>'reason_code' <> 'snapshot_not_available'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION 'unknown and cross-project current-city snapshots leaked';
  END IF;

  BEGIN
    PERFORM app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000003'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'release-only member read a current-city snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_current_city_report_snapshot_v1(
      'ad110000-0000-4000-8000-000000000004'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'revoked member read a current-city snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  SELECT count(*)
  INTO event_count
  FROM app_private.management_current_city_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id =
    'ad110000-0000-4000-8000-000000000002'::uuid;
  IF event_count <> 5 OR (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      'ad110000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'completed'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      'ad110000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'not_found'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      'ad110000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'untrusted_provenance'
  ) <> 1
  THEN
    RAISE EXCEPTION 'current-city read audit counts are incorrect';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_current_city_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id =
    'ad110000-0000-4000-8000-000000000002'::uuid;
  IF history_text ~
      '(protected_report|cells|value_count|contributor|canonical_name|place_name)'
  THEN
    RAISE EXCEPTION 'current-city read audit retained protected values';
  END IF;

  SELECT attempt.*
  INTO STRICT current_attempt
  FROM app_private.management_current_city_report_release_attempts AS attempt
  WHERE attempt.released_snapshot_id = trusted_snapshot_id;
  authorization_evidence =
    app_private.resolve_management_report_authorization_v1(
      'ad110000-0000-4000-8000-000000000002'::uuid,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );

  BEGIN
    INSERT INTO app_private.management_current_city_report_snapshot_access_events (
      access_event_id,
      requested_by_app_user_id,
      organization_workspace_id,
      organization_membership_id,
      project_membership_id,
      capability_grant_id,
      capability_id,
      authorization_reference_at_utc,
      project_id,
      requested_snapshot_id,
      resolved_snapshot_id,
      current_city_release_request_id,
      report_id,
      report_version,
      query_fingerprint,
      release_lineage_id,
      target_tree_version,
      target_content_fingerprint,
      data_cutoff_utc,
      accessed_at_utc,
      result_status,
      reason_code
    ) VALUES (
      'adb00000-0000-4000-8000-000000000001'::uuid,
      'ad110000-0000-4000-8000-000000000002'::uuid,
      (authorization_evidence->>'organization_workspace_id')::uuid,
      (authorization_evidence->>'organization_membership_id')::uuid,
      (authorization_evidence->>'project_membership_id')::uuid,
      (authorization_evidence->>'capability_grant_id')::uuid,
      'view_anonymous_analytics',
      (authorization_evidence->>'reference_at_utc')::timestamptz,
      'ad130000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id,
      trusted_snapshot_id,
      current_attempt.release_request_id,
      current_attempt.report_id,
      current_attempt.report_version,
      current_attempt.query_fingerprint,
      current_attempt.release_lineage_id,
      current_attempt.target_tree_version,
      repeat('0', 64),
      current_attempt.data_cutoff_utc,
      (authorization_evidence->>'reference_at_utc')::timestamptz,
      'completed',
      NULL
    );
    RAISE EXCEPTION 'forged current-city access event was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.management_current_city_report_snapshot_access_events
    SET reason_code = 'snapshot_not_available'
    WHERE access_event_id = (current_read->>'access_event_id')::uuid;
    RAISE EXCEPTION 'current-city access history update was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_current_city_report_snapshot_access_events
    WHERE access_event_id = (current_read->>'access_event_id')::uuid;
    RAISE EXCEPTION 'current-city access history delete was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END
$fixture_6ap_read$;

ROLLBACK;
