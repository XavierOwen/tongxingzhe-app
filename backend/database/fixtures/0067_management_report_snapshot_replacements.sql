-- Synthetic rollback fixture for Slice 6BE.
--
-- The fixture creates four stable trusted-v2 channel snapshots in one project,
-- one trusted-v2 snapshot in a second project, and one legacy v1 snapshot in a
-- third project.  It then exercises a strict replacement chain, idempotency,
-- stale/divergent/reversed/self/cross-project inputs, family and blocked
-- provenance exclusion, value-free lifecycle reads, and immutable history.
-- Every row created here is rolled back at the end.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6be10000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6be10000-0000-4000-8000-000000000002'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  '6be20000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Slice 6BE replacement workspace',
  NULL,
  NULL
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
) VALUES
  (
    '6be30000-0000-4000-8000-000000000001'::uuid,
    '6be20000-0000-4000-8000-000000000001'::uuid,
    'Slice 6BE primary project',
    'active',
    false
  ),
  (
    '6be30000-0000-4000-8000-000000000002'::uuid,
    '6be20000-0000-4000-8000-000000000001'::uuid,
    'Slice 6BE cross-project target',
    'active',
    false
  ),
  (
    '6be30000-0000-4000-8000-000000000003'::uuid,
    '6be20000-0000-4000-8000-000000000001'::uuid,
    'Slice 6BE legacy project',
    'active',
    false
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES
  (
    '6be40000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '6be40000-0000-4000-8000-000000000002'::uuid,
    '6be30000-0000-4000-8000-000000000002'::uuid,
    1,
    'published',
    true
  ),
  (
    '6be40000-0000-4000-8000-000000000003'::uuid,
    '6be30000-0000-4000-8000-000000000003'::uuid,
    1,
    'published',
    true
  );

-- The report contract needs one safe channel cell in each complete period.
-- Ten voice contacts make that cell displayed while the other fixed channel
-- cells remain suppressed without introducing any sensitive fixture values.
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
  format('6be-contact-%s-%s-%s', project_row.project_key,
    period_row.period_key, series_row),
  '6be10000-0000-4000-8000-000000000002'::uuid,
  '6be20000-0000-4000-8000-000000000001'::uuid,
  project_row.project_id,
  project_row.questionnaire_version_id,
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  VALUES
    (
      'primary'::text,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      '6be40000-0000-4000-8000-000000000001'::uuid
    ),
    (
      'cross'::text,
      '6be30000-0000-4000-8000-000000000002'::uuid,
      '6be40000-0000-4000-8000-000000000002'::uuid
    ),
    (
      'legacy'::text,
      '6be30000-0000-4000-8000-000000000003'::uuid,
      '6be40000-0000-4000-8000-000000000003'::uuid
    )
) AS project_row(project_key, project_id, questionnaire_version_id)
CROSS JOIN (
  SELECT
    'previous'::text AS period_key,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '12 days'
    ) AT TIME ZONE 'UTC' AS occurred_at_utc
  UNION ALL
  SELECT
    'current'::text,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '5 days'
    ) AT TIME ZONE 'UTC'
) AS period_row
CROSS JOIN generate_series(1, 10) AS series_row;

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '6be50000-0000-4000-8000-000000000001'::uuid,
  '6be20000-0000-4000-8000-000000000001'::uuid,
  '6be10000-0000-4000-8000-000000000001'::uuid,
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
    '6be60000-0000-4000-8000-000000000001'::uuid,
    '6be50000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6be60000-0000-4000-8000-000000000002'::uuid,
    '6be50000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000002'::uuid,
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
    '6be70000-0000-4000-8000-000000000001'::uuid,
    '6be60000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6be70000-0000-4000-8000-000000000002'::uuid,
    '6be60000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6be80000-0000-4000-8000-000000000001'::uuid,
  '6be10000-0000-4000-8000-000000000001'::uuid,
  '6be30000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6be80000-0000-4000-8000-000000000002'::uuid,
  '6be10000-0000-4000-8000-000000000001'::uuid,
  '6be30000-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

-- Four trusted-v2 releases create three possible strict lineage edges and a
-- later head.  The release function derives the cutoff and authorization
-- evidence; the fixture never fabricates either value.
DO $release_setup$
DECLARE
  release_result jsonb;
BEGIN
  release_result = app_private.release_management_report_snapshot_v2(
    '6be90000-0000-4000-8000-000000000001'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION 'trusted-v2 baseline was not released: %', release_result;
  END IF;

  PERFORM pg_sleep(0.01);
  release_result = app_private.release_management_report_snapshot_v2(
    '6be90000-0000-4000-8000-000000000002'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved'
    OR release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION 'trusted-v2 second snapshot was not released: %', release_result;
  END IF;

  PERFORM pg_sleep(0.01);
  release_result = app_private.release_management_report_snapshot_v2(
    '6be90000-0000-4000-8000-000000000003'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved'
    OR release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION 'trusted-v2 third snapshot was not released: %', release_result;
  END IF;

  PERFORM pg_sleep(0.01);
  release_result = app_private.release_management_report_snapshot_v2(
    '6be90000-0000-4000-8000-000000000004'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved'
    OR release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION 'trusted-v2 fourth snapshot was not released: %', release_result;
  END IF;

  release_result = app_private.release_management_report_snapshot_v2(
    '6be90000-0000-4000-8000-000000000011'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000002'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION 'cross-project trusted-v2 baseline was not released: %',
      release_result;
  END IF;
END
$release_setup$;

-- Keep family-shaped and blocked-shaped rows in the shared source table. They
-- are inserted only as synthetic negative inputs, with triggers/FKs bypassed;
-- the lifecycle writer must still refuse them because they lack trusted-v2
-- channel provenance (and the RLS policy hides non-channel report families).
SELECT set_config('session_replication_role', 'replica', true);
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
) VALUES
  (
    '6be00000-0000-4000-8000-000000000041'::uuid,
    '6be00000-0000-4000-8000-000000000041'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'management-region-report:contact_sessions_by_current_city_two_periods',
    'contact_sessions_by_current_city_two_periods',
    1,
    'synthetic-current-city',
    'UTC',
    clock_timestamp() - interval '4 hours',
    clock_timestamp() - interval '3 hours',
    NULL,
    0,
    '{}'::jsonb
  ),
  (
    '6be00000-0000-4000-8000-000000000042'::uuid,
    '6be00000-0000-4000-8000-000000000042'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'management-interest-report:contact_sessions_by_interest_level_two_periods',
    'contact_sessions_by_interest_level_two_periods',
    1,
    'synthetic-interest',
    'UTC',
    clock_timestamp() - interval '4 hours',
    clock_timestamp() - interval '3 hours',
    NULL,
    0,
    '{}'::jsonb
  ),
  (
    '6be00000-0000-4000-8000-000000000043'::uuid,
    '6be00000-0000-4000-8000-000000000043'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    'management-report:contact_sessions_by_channel_two_periods',
    'contact_sessions_by_channel_two_periods',
    1,
    'blocked-candidate',
    'UTC',
    clock_timestamp() - interval '2 hours',
    clock_timestamp() - interval '1 hour',
    NULL,
    0,
    '{}'::jsonb
  );
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
  '6be00000-0000-0000-0000-000000000031'::uuid,
  '6be00000-0000-0000-0000-000000000031'::uuid,
  snapshot.created_by_app_user_id,
  snapshot.project_id,
  snapshot.release_lineage_id,
  snapshot.report_id,
  snapshot.report_version,
  snapshot.query_fingerprint,
  snapshot.reporting_time_zone,
  snapshot.data_cutoff_utc + interval '1 second',
  snapshot.released_at_utc + interval '1 second',
  NULL,
  snapshot.source_change_sequence,
  snapshot.protected_report
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.release_request_id =
  '6be90000-0000-4000-8000-000000000001'::uuid;
SELECT set_config('session_replication_role', 'origin', true);

CREATE TEMP TABLE fixture_6be_snapshot_bytes
ON COMMIT DROP
AS
SELECT
  snapshot_id,
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
FROM app_private.management_report_snapshots
WHERE release_request_id IN (
  '6be90000-0000-4000-8000-000000000001'::uuid,
  '6be90000-0000-4000-8000-000000000002'::uuid,
  '6be90000-0000-4000-8000-000000000003'::uuid,
  '6be90000-0000-4000-8000-000000000004'::uuid,
  '6be90000-0000-4000-8000-000000000011'::uuid,
  '6be00000-0000-0000-0000-000000000031'::uuid
);

DO $fixture$
DECLARE
  baseline_snapshot_id uuid;
  second_snapshot_id uuid;
  third_snapshot_id uuid;
  fourth_snapshot_id uuid;
  cross_project_snapshot_id uuid;
  legacy_snapshot_id uuid;
  declaration_result jsonb;
  replay_result jsonb;
  lifecycle_result jsonb;
  replacement_count bigint;
  snapshot_count bigint;
BEGIN
  SELECT snapshot_id
  INTO STRICT baseline_snapshot_id
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '6be90000-0000-4000-8000-000000000001'::uuid;
  SELECT snapshot_id
  INTO STRICT second_snapshot_id
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '6be90000-0000-4000-8000-000000000002'::uuid;
  SELECT snapshot_id
  INTO STRICT third_snapshot_id
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '6be90000-0000-4000-8000-000000000003'::uuid;
  SELECT snapshot_id
  INTO STRICT fourth_snapshot_id
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '6be90000-0000-4000-8000-000000000004'::uuid;
  SELECT snapshot_id
  INTO STRICT cross_project_snapshot_id
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '6be90000-0000-4000-8000-000000000011'::uuid;
  SELECT snapshot_id
  INTO STRICT legacy_snapshot_id
  FROM app_private.management_report_snapshots
  WHERE release_request_id =
    '6be00000-0000-0000-0000-000000000031'::uuid;

  declaration_result = app_private.declare_management_report_snapshot_replacement_v1(
    '6be91000-0000-4000-8000-000000000001'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    baseline_snapshot_id,
    second_snapshot_id,
    'contact_revision'
  );
  IF declaration_result->>'replacement_contract_id' IS DISTINCT FROM
      'channel_management_report_snapshot_replacement_v1'
    OR declaration_result->>'result_status' IS DISTINCT FROM 'completed'
    OR declaration_result->>'superseded_snapshot_id'
      IS DISTINCT FROM baseline_snapshot_id::text
    OR declaration_result->>'replacement_snapshot_id'
      IS DISTINCT FROM second_snapshot_id::text
    OR declaration_result->>'replacement_reason_code'
      IS DISTINCT FROM 'contact_revision'
    OR declaration_result ? 'protected_report'
    OR declaration_result ? 'result_document'
    OR declaration_result::text ~ '(cells|value_count|contributor|contact_id|place_name)'
  THEN
    RAISE EXCEPTION 'valid replacement result is not value-free: %',
      declaration_result;
  END IF;

  SELECT count(*) INTO replacement_count
  FROM app_private.management_report_snapshot_replacements;
  replay_result = app_private.declare_management_report_snapshot_replacement_v1(
    '6be91000-0000-4000-8000-000000000001'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    baseline_snapshot_id,
    second_snapshot_id,
    'contact_revision'
  );
  IF replay_result <> declaration_result
    OR (SELECT count(*) FROM app_private.management_report_snapshot_replacements)
      <> replacement_count
  THEN
    RAISE EXCEPTION 'identical replacement retry was not idempotent';
  END IF;

  lifecycle_result = app_private.read_management_report_snapshot_lifecycle_v1(
    '6be30000-0000-4000-8000-000000000001'::uuid,
    baseline_snapshot_id
  );
  IF lifecycle_result <> jsonb_build_object(
      'lifecycle_contract_id',
      'channel_management_report_snapshot_lifecycle_v1',
      'project_id', '6be30000-0000-4000-8000-000000000001'::uuid,
      'snapshot_id', baseline_snapshot_id,
      'lifecycle_status', 'superseded',
      'replacement_snapshot_id', second_snapshot_id
    )
  THEN
    RAISE EXCEPTION 'superseded lifecycle result is incorrect: %', lifecycle_result;
  END IF;

  lifecycle_result = app_private.read_management_report_snapshot_lifecycle_v1(
    '6be30000-0000-4000-8000-000000000001'::uuid,
    second_snapshot_id
  );
  IF lifecycle_result <> jsonb_build_object(
      'lifecycle_contract_id',
      'channel_management_report_snapshot_lifecycle_v1',
      'project_id', '6be30000-0000-4000-8000-000000000001'::uuid,
      'snapshot_id', second_snapshot_id,
      'lifecycle_status', 'active',
      'replacement_snapshot_id', NULL
    )
  THEN
    RAISE EXCEPTION 'active lifecycle result is incorrect: %', lifecycle_result;
  END IF;

  -- A valid strict chain advances from the current active head.  This also
  -- proves that the old snapshot remains byte-for-byte unchanged.
  declaration_result = app_private.declare_management_report_snapshot_replacement_v1(
    '6be91000-0000-4000-8000-000000000002'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    second_snapshot_id,
    third_snapshot_id,
    'late_accepted_data'
  );
  IF declaration_result->>'result_status' IS DISTINCT FROM 'completed'
    OR declaration_result->>'superseded_snapshot_id'
      IS DISTINCT FROM second_snapshot_id::text
    OR declaration_result->>'replacement_snapshot_id'
      IS DISTINCT FROM third_snapshot_id::text
  THEN
    RAISE EXCEPTION 'valid second replacement did not complete: %', declaration_result;
  END IF;

  declaration_result = app_private.declare_management_report_snapshot_replacement_v1(
    '6be91000-0000-4000-8000-000000000003'::uuid,
    '6be10000-0000-4000-8000-000000000001'::uuid,
    '6be30000-0000-4000-8000-000000000001'::uuid,
    third_snapshot_id,
    fourth_snapshot_id,
    'contact_void'
  );
  IF declaration_result->>'result_status' IS DISTINCT FROM 'completed'
    OR declaration_result->>'superseded_snapshot_id'
      IS DISTINCT FROM third_snapshot_id::text
    OR declaration_result->>'replacement_snapshot_id'
      IS DISTINCT FROM fourth_snapshot_id::text
  THEN
    RAISE EXCEPTION 'valid third replacement did not complete: %', declaration_result;
  END IF;

  lifecycle_result = app_private.read_management_report_snapshot_lifecycle_v1(
    '6be30000-0000-4000-8000-000000000001'::uuid,
    third_snapshot_id
  );
  IF lifecycle_result->>'lifecycle_status' IS DISTINCT FROM 'superseded'
    OR lifecycle_result->>'replacement_snapshot_id'
      IS DISTINCT FROM fourth_snapshot_id::text
    OR lifecycle_result ? 'protected_report'
    OR lifecycle_result ? 'result_document'
  THEN
    RAISE EXCEPTION 'strict replacement chain lifecycle is incorrect: %',
      lifecycle_result;
  END IF;

  -- The same old snapshot cannot branch or be reused after it has been
  -- superseded.  Reverse, self and cross-project pairs fail before insertion.
  BEGIN
    PERFORM app_private.declare_management_report_snapshot_replacement_v1(
      '6be91000-0000-4000-8000-000000000004'::uuid,
      '6be10000-0000-4000-8000-000000000001'::uuid,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      baseline_snapshot_id,
      fourth_snapshot_id,
      'contact_revision'
    );
    RAISE EXCEPTION 'stale/divergent replacement was accepted';
  EXCEPTION WHEN SQLSTATE '55000' OR SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_report_snapshot_replacement_v1(
      '6be91000-0000-4000-8000-000000000005'::uuid,
      '6be10000-0000-4000-8000-000000000001'::uuid,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      fourth_snapshot_id,
      third_snapshot_id,
      'contact_revision'
    );
    RAISE EXCEPTION 'reverse replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_report_snapshot_replacement_v1(
      '6be91000-0000-4000-8000-000000000006'::uuid,
      '6be10000-0000-4000-8000-000000000001'::uuid,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      fourth_snapshot_id,
      fourth_snapshot_id,
      'contact_revision'
    );
    RAISE EXCEPTION 'self replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_report_snapshot_replacement_v1(
      '6be91000-0000-4000-8000-000000000007'::uuid,
      '6be10000-0000-4000-8000-000000000001'::uuid,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      cross_project_snapshot_id,
      'contact_revision'
    );
    RAISE EXCEPTION 'cross-project replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- A request UUID cannot drift to a different reason or snapshot pair.
  BEGIN
    PERFORM app_private.declare_management_report_snapshot_replacement_v1(
      '6be91000-0000-4000-8000-000000000001'::uuid,
      '6be10000-0000-4000-8000-000000000001'::uuid,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      baseline_snapshot_id,
      second_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION 'replacement request reason drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- Legacy, current-city, interest and blocked-shaped rows all share the
  -- source table but fail the dedicated trusted-v2 channel provenance check.
  BEGIN
    PERFORM app_private.declare_management_report_snapshot_replacement_v1(
      '6be91000-0000-4000-8000-000000000008'::uuid,
      '6be10000-0000-4000-8000-000000000001'::uuid,
      '6be30000-0000-4000-8000-000000000001'::uuid,
      legacy_snapshot_id,
      fourth_snapshot_id,
      'contact_revision'
    );
    RAISE EXCEPTION 'legacy snapshot replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  FOREACH snapshot_count IN ARRAY ARRAY[41::bigint, 42::bigint, 43::bigint]
  LOOP
    BEGIN
      PERFORM app_private.declare_management_report_snapshot_replacement_v1(
        ('6be91000-0000-4000-8000-00000000' ||
          lpad(snapshot_count::text, 4, '0'))::uuid,
        '6be10000-0000-4000-8000-000000000001'::uuid,
        '6be30000-0000-4000-8000-000000000001'::uuid,
        ('6be00000-0000-4000-8000-0000000000' ||
          lpad(snapshot_count::text, 2, '0'))::uuid,
        fourth_snapshot_id,
        'contact_revision'
      );
      RAISE EXCEPTION 'non-channel or blocked snapshot replacement was accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
    END;
  END LOOP;

  IF (
    SELECT count(*)
    FROM app_private.management_report_snapshot_replacements
    WHERE project_id = '6be30000-0000-4000-8000-000000000001'::uuid
  ) <> 3 THEN
    RAISE EXCEPTION 'failed replacement requests wrote partial history';
  END IF;

  -- The lifecycle query has a stable value-free not-found contract for an
  -- unknown, blocked or non-channel snapshot, including the no-value keys.
  lifecycle_result = app_private.read_management_report_snapshot_lifecycle_v1(
    '6be30000-0000-4000-8000-000000000001'::uuid,
    '6be00000-0000-4000-8000-000000000043'::uuid
  );
  IF lifecycle_result <> jsonb_build_object(
      'lifecycle_contract_id',
      'channel_management_report_snapshot_lifecycle_v1',
      'project_id', '6be30000-0000-4000-8000-000000000001'::uuid,
      'snapshot_id', '6be00000-0000-4000-8000-000000000043'::uuid,
      'lifecycle_status', 'not_found',
      'replacement_snapshot_id', NULL
    )
  THEN
    RAISE EXCEPTION 'value-free not-found lifecycle result is incorrect: %',
      lifecycle_result;
  END IF;

  -- Immutable relation: neither audit rows nor source snapshots can be
  -- rewritten by a caller after a declaration has committed.
  BEGIN
    UPDATE app_private.management_report_snapshot_replacements
    SET replacement_reason_code = 'contact_void'
    WHERE replacement_request_id =
      '6be91000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'replacement history update was accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_report_snapshot_replacements
    WHERE replacement_request_id =
      '6be91000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'replacement history delete was accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM fixture_6be_snapshot_bytes AS before_row
    JOIN app_private.management_report_snapshots AS after_row
      ON after_row.snapshot_id = before_row.snapshot_id
    WHERE before_row.project_id IS DISTINCT FROM after_row.project_id
      OR before_row.release_lineage_id IS DISTINCT FROM after_row.release_lineage_id
      OR before_row.report_id IS DISTINCT FROM after_row.report_id
      OR before_row.report_version IS DISTINCT FROM after_row.report_version
      OR before_row.query_fingerprint IS DISTINCT FROM after_row.query_fingerprint
      OR before_row.reporting_time_zone IS DISTINCT FROM after_row.reporting_time_zone
      OR before_row.data_cutoff_utc IS DISTINCT FROM after_row.data_cutoff_utc
      OR before_row.released_at_utc IS DISTINCT FROM after_row.released_at_utc
      OR before_row.previous_snapshot_id IS DISTINCT FROM after_row.previous_snapshot_id
      OR before_row.source_change_sequence IS DISTINCT FROM after_row.source_change_sequence
      OR before_row.protected_report IS DISTINCT FROM after_row.protected_report
  ) THEN
    RAISE EXCEPTION 'replacement declaration changed an existing snapshot';
  END IF;
END
$fixture$;

ROLLBACK;
