-- Synthetic rollback fixture for Slice 6BK.
--
-- The fixture creates a small valid original-region lineage directly through
-- the existing immutable snapshot contract. It then exercises the 0071
-- runtime directory bridge with 21 eligible snapshots, an authorized empty
-- project, blocked provenance, cross-project data, and authorization failures.
-- All rows are rolled back.
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE fixture_6bk_directory_exclusions (
  case_name text PRIMARY KEY,
  snapshot_id uuid NOT NULL,
  project_id uuid NOT NULL,
  report_id text NOT NULL
) ON COMMIT DROP;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b710000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b710000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b710000-0000-4000-8000-000000000003'::uuid, 'deletion_pending'),
  ('6b710000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  (
    '6b7e0000-0000-4000-8000-000000000001'::uuid,
    'https://directory-original.synthetic/auth/v1',
    'active-reader',
    '6b710000-0000-4000-8000-000000000001'::uuid
  ),
  (
    '6b7e0000-0000-4000-8000-000000000002'::uuid,
    'https://directory-original.synthetic/auth/v1',
    'no-capability-reader',
    '6b710000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b7e0000-0000-4000-8000-000000000003'::uuid,
    'https://directory-original.synthetic/auth/v1',
    'inactive-reader',
    '6b710000-0000-4000-8000-000000000003'::uuid
  ),
  (
    '6b7e0000-0000-4000-8000-000000000004'::uuid,
    ' https://directory-original.synthetic/auth/v1 ',
    'spaced-reader',
    '6b710000-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
)
VALUES (
  '6b720000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BK original-region directory workspace',
  NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6b730000-0000-4000-8000-000000000001'::uuid,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6BK original-region directory project'
  ),
  (
    '6b730000-0000-4000-8000-000000000002'::uuid,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6BK authorized empty project'
  ),
  (
    '6b730000-0000-4000-8000-000000000003'::uuid,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6BK cross-project original lineage'
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
    '6b760000-0000-4000-8000-000000000001'::uuid,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6b710000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b760000-0000-4000-8000-000000000002'::uuid,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6b710000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b760000-0000-4000-8000-000000000003'::uuid,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6b710000-0000-4000-8000-000000000004'::uuid,
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
    '6b770000-0000-4000-8000-000000000001'::uuid,
    '6b760000-0000-4000-8000-000000000001'::uuid,
    '6b730000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b770000-0000-4000-8000-000000000002'::uuid,
    '6b760000-0000-4000-8000-000000000001'::uuid,
    '6b730000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b770000-0000-4000-8000-000000000003'::uuid,
    '6b760000-0000-4000-8000-000000000001'::uuid,
    '6b730000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b770000-0000-4000-8000-000000000004'::uuid,
    '6b760000-0000-4000-8000-000000000002'::uuid,
    '6b730000-0000-4000-8000-000000000001'::uuid,
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
    '6b780000-0000-4000-8000-000000000001'::uuid,
    '6b770000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b780000-0000-4000-8000-000000000002'::uuid,
    '6b770000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b780000-0000-4000-8000-000000000003'::uuid,
    '6b770000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b780000-0000-4000-8000-000000000004'::uuid,
    '6b770000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750000-0000-4000-8000-000000000001'::uuid,
  '6b710000-0000-4000-8000-000000000001'::uuid,
  '6b730000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750000-0000-4000-8000-000000000002'::uuid,
  '6b710000-0000-4000-8000-000000000001'::uuid,
  '6b730000-0000-4000-8000-000000000002'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750000-0000-4000-8000-000000000003'::uuid,
  '6b710000-0000-4000-8000-000000000001'::uuid,
  '6b730000-0000-4000-8000-000000000003'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
)
VALUES ('fixture-6bk-original-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  (
    'fixture-6bk-country', 'fixture-6bk-original-v1', NULL,
    '6BK Country', 'country'
  ),
  (
    'fixture-6bk-city', 'fixture-6bk-original-v1', 'fixture-6bk-country',
    '6BK City', 'city'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES (
  'fixture-6bk-city-boundary', 'fixture-6bk-city',
  'fixture-6bk-original-v1',
  polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bk-original-v1', false
);

SET LOCAL ROLE tongxingzhe_management_original_region_snapshot_release_writer;

DO $fixture_6bk_snapshots$
DECLARE
  fixture_project_id constant uuid :=
    '6b730000-0000-4000-8000-000000000001';
  fixture_empty_project_id constant uuid :=
    '6b730000-0000-4000-8000-000000000002';
  fixture_cross_project_id constant uuid :=
    '6b730000-0000-4000-8000-000000000003';
  fixture_owner_id constant uuid :=
    '6b710000-0000-4000-8000-000000000001';
  fixture_report_id constant text :=
    'contact_sessions_by_original_region_two_periods';
  query_fingerprint constant text :=
    'management-report:contact_sessions_by_original_region_two_periods:v1';
  release_lineage_id constant text :=
    'management-original-region-report:contact_sessions_by_original_region_two_periods';
  source_tree_version constant text := 'fixture-6bk-original-v1';
  source_fingerprint text;
  zone_effective_utc timestamptz;
  request_id uuid;
  snapshot_id uuid;
  previous_snapshot_id uuid := NULL;
  cutoff_utc timestamptz;
  report_document jsonb;
  result_document jsonb;
  result_status text;
  shared_period_count integer;
  assessed_cell_count integer;
  snapshot_count integer;
  snapshot_number integer;
BEGIN
  SELECT content_fingerprint
  INTO STRICT source_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = source_tree_version;
  SELECT effective_from_utc
  INTO STRICT zone_effective_utc
  FROM app_private.project_reporting_time_zone_versions
  WHERE project_id = fixture_project_id
    AND version_number = 1;

  -- Twenty-one valid original-region snapshots prove the directory cap. The
  -- report itself is fixed and contains no source or contact details.
  FOR snapshot_number IN 1..21 LOOP
    -- The canonical JSON timestamp is millisecond precision.  Truncate the
    -- database cutoff to the same precision so the immutable snapshot trigger
    -- compares the exact value rather than a rounded representation.
    cutoff_utc = date_trunc(
      'milliseconds',
      clock_timestamp() - interval '30 days'
        + (snapshot_number * interval '1 hour')
    );
    request_id = gen_random_uuid();
    snapshot_id = gen_random_uuid();
    result_status = CASE
      WHEN snapshot_number = 1 THEN 'approved_baseline'
      ELSE 'approved'
    END;
    shared_period_count = CASE
      WHEN snapshot_number = 1 THEN 0
      ELSE 2
    END;
    assessed_cell_count = CASE
      WHEN snapshot_number = 1 THEN 0
      ELSE 4
    END;
    report_document = jsonb_build_object(
      'report_id', fixture_report_id,
      'report_version', 1,
      'metric_id', 'contact_sessions',
      'metric_version', 1,
      'dimension', 'original_region',
      'view_mode', 'original',
      'region_granularity', 'city',
      'query_fingerprint', query_fingerprint,
      'privacy_policy', 'management_original_region_contact_session_privacy_v1',
      'source_scope', 'backend_accepted_active_contacts_original_current_revision',
      'project_id', fixture_project_id,
      'periods', app_private.resolve_management_report_periods_v1(
        'UTC', cutoff_utc
      ),
      'data_cutoff_utc', to_char(
        cutoff_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', 0,
      'source_tree_context', jsonb_build_object(
        'source_tree_context_contract_id', 'management-original-region-source-tree:v1',
        'result_status', 'selected',
        'reason_code', 'single_original_source_tree',
        'source_tree_version', source_tree_version,
        'source_content_fingerprint', source_fingerprint
      ),
      'result_status', 'completed',
      'cells', jsonb_build_array(
        jsonb_build_object(
          'period_key', 'previous', 'city_id', 'fixture-6bk-city',
          'cell_order', 0, 'value_count', 10, 'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'period_key', 'current', 'city_id', 'fixture-6bk-city',
          'cell_order', 1, 'value_count', 10, 'privacy_status', 'displayed'
        )
      )
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
    ) VALUES (
      snapshot_id,
      request_id,
      fixture_owner_id,
      fixture_project_id,
      release_lineage_id,
      fixture_report_id,
      1,
      query_fingerprint,
      'UTC',
      cutoff_utc,
      cutoff_utc + interval '1 minute',
      previous_snapshot_id,
      0,
      report_document
    );

    result_document = jsonb_build_object(
      'release_contract_id',
        'original_region_management_report_snapshot_release_v1',
      'release_request_id', request_id,
      'project_id', fixture_project_id,
      'release_lineage_id', release_lineage_id,
      'report_id', fixture_report_id,
      'report_version', 1,
      'query_fingerprint', query_fingerprint,
      'reporting_time_zone_version_number', 1,
      'reporting_time_zone', 'UTC',
      'data_cutoff_utc', to_char(
        cutoff_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_tree_version', source_tree_version,
      'source_content_fingerprint', source_fingerprint,
      'source_change_sequence', 0,
      'compared_snapshot_id', previous_snapshot_id,
      'released_snapshot_id', snapshot_id,
      'shared_period_count', shared_period_count,
      'assessed_cell_count', assessed_cell_count,
      'result_status', result_status,
      'reason_codes', '[]'::jsonb
    );

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
    ) VALUES (
      request_id,
      fixture_owner_id,
      '6b720000-0000-4000-8000-000000000001'::uuid,
      '6b760000-0000-4000-8000-000000000001'::uuid,
      '6b770000-0000-4000-8000-000000000001'::uuid,
      '6b780000-0000-4000-8000-000000000002'::uuid,
      'release_management_reports',
      cutoff_utc,
      fixture_project_id,
      1,
      'UTC',
      zone_effective_utc,
      cutoff_utc,
      release_lineage_id,
      fixture_report_id,
      1,
      query_fingerprint,
      source_tree_version,
      source_fingerprint,
      0,
      previous_snapshot_id,
      snapshot_id,
      shared_period_count,
      assessed_cell_count,
      result_status,
      '[]'::jsonb,
      result_document
    );
    previous_snapshot_id = snapshot_id;
  END LOOP;

  -- A blocked result has no released snapshot and must never enter a
  -- metadata directory. It proves the blocked provenance branch separately.
  request_id = gen_random_uuid();
  cutoff_utc = date_trunc('milliseconds', clock_timestamp() - interval '1 hour');
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
  ) VALUES (
    request_id,
    fixture_owner_id,
    '6b720000-0000-4000-8000-000000000001'::uuid,
    '6b760000-0000-4000-8000-000000000001'::uuid,
    '6b770000-0000-4000-8000-000000000001'::uuid,
    '6b780000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    cutoff_utc,
    fixture_project_id,
    1,
    'UTC',
    zone_effective_utc,
    cutoff_utc,
    release_lineage_id,
    fixture_report_id,
    1,
    query_fingerprint,
    source_tree_version,
    source_fingerprint,
    0,
    previous_snapshot_id,
    NULL,
    2,
    4,
    'blocked',
    '["release_source_tree_changed"]'::jsonb,
    jsonb_build_object(
      'release_contract_id',
        'original_region_management_report_snapshot_release_v1',
      'release_request_id', request_id,
      'project_id', fixture_project_id,
      'release_lineage_id', release_lineage_id,
      'report_id', fixture_report_id,
      'report_version', 1,
      'query_fingerprint', query_fingerprint,
      'reporting_time_zone_version_number', 1,
      'reporting_time_zone', 'UTC',
      'data_cutoff_utc', to_char(
        cutoff_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_tree_version', source_tree_version,
      'source_content_fingerprint', source_fingerprint,
      'source_change_sequence', 0,
      'compared_snapshot_id', previous_snapshot_id,
      'released_snapshot_id', NULL,
      'shared_period_count', 2,
      'assessed_cell_count', 4,
      'result_status', 'blocked',
      'reason_codes', '["release_source_tree_changed"]'::jsonb
    )
  );

  SELECT count(*) INTO snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = fixture_project_id
    AND snapshot.report_id = fixture_report_id;
  IF snapshot_count <> 21 THEN
    RAISE EXCEPTION '6BK did not create 21 eligible snapshots: %', snapshot_count;
  END IF;
END
$fixture_6bk_snapshots$;

RESET ROLE;

-- Shared snapshot storage also contains rows that must not be visible through
-- this original-region directory.  Construct one row for each important
-- exclusion, then keep the IDs in a temp table so the runtime assertion can
-- prove both construction and non-membership in the returned directory.
DO $fixture_6bk_directory_exclusions$
DECLARE
  base_snapshot app_private.management_report_snapshots%ROWTYPE;
  base_attempt
    app_private.management_original_region_report_release_attempts%ROWTYPE;
  candidate_attempt
    app_private.management_original_region_report_release_attempts%ROWTYPE;
  cross_project_id constant uuid :=
    '6b730000-0000-4000-8000-000000000003';
  main_project_id constant uuid :=
    '6b730000-0000-4000-8000-000000000001';
  original_report_id constant text :=
    'contact_sessions_by_original_region_two_periods';
  original_lineage constant text :=
    'management-original-region-report:contact_sessions_by_original_region_two_periods';
  cross_snapshot_id constant uuid :=
    '6b790000-0000-4000-8000-000000000001';
  cross_request_id constant uuid :=
    '6b7a0000-0000-4000-8000-000000000001';
  channel_snapshot_id constant uuid :=
    '6b790000-0000-4000-8000-000000000002';
  channel_request_id constant uuid :=
    '6b7a0000-0000-4000-8000-000000000002';
  current_city_snapshot_id constant uuid :=
    '6b790000-0000-4000-8000-000000000003';
  current_city_request_id constant uuid :=
    '6b7a0000-0000-4000-8000-000000000003';
  interest_snapshot_id constant uuid :=
    '6b790000-0000-4000-8000-000000000004';
  interest_request_id constant uuid :=
    '6b7a0000-0000-4000-8000-000000000004';
  legacy_snapshot_id constant uuid :=
    '6b790000-0000-4000-8000-000000000005';
  legacy_request_id constant uuid :=
    '6b7a0000-0000-4000-8000-000000000005';
  drift_snapshot_id constant uuid :=
    '6b790000-0000-4000-8000-000000000006';
  drift_request_id constant uuid :=
    '6b7a0000-0000-4000-8000-000000000006';
  cross_report jsonb;
  cross_zone_effective_utc timestamptz;
BEGIN
  SELECT snapshot.*
  INTO STRICT base_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = main_project_id
    AND snapshot.report_id = original_report_id
  ORDER BY snapshot.data_cutoff_utc DESC
  LIMIT 1;

  SELECT attempt.*
  INTO STRICT base_attempt
  FROM app_private.management_original_region_report_release_attempts AS attempt
  WHERE attempt.released_snapshot_id = base_snapshot.snapshot_id
    AND attempt.release_request_id = base_snapshot.release_request_id;

  SELECT version_row.effective_from_utc
  INTO STRICT cross_zone_effective_utc
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = cross_project_id
    AND version_row.version_number = 1;

  -- A valid original snapshot in another project is still excluded by the
  -- directory's requested-project predicate.
  cross_report = jsonb_set(
    base_snapshot.protected_report,
    ARRAY['project_id'],
    to_jsonb(cross_project_id::text),
    false
  );
  PERFORM app_private.validate_management_original_region_report_document_v1(
    cross_report
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
  ) VALUES (
    cross_snapshot_id,
    cross_request_id,
    base_snapshot.created_by_app_user_id,
    cross_project_id,
    base_snapshot.release_lineage_id,
    base_snapshot.report_id,
    base_snapshot.report_version,
    base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone,
    base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc,
    NULL,
    base_snapshot.source_change_sequence,
    cross_report
  );
  INSERT INTO fixture_6bk_directory_exclusions (
    case_name, snapshot_id, project_id, report_id
  ) VALUES (
    'cross_project_original', cross_snapshot_id, cross_project_id,
    original_report_id
  );

  -- Keep the cross-project row otherwise eligible: 0068's original-region
  -- attempt and ORIGINAL family claim must match every provenance JOIN field.
  -- The directory can then exclude it only at requested_project_id.
  candidate_attempt = base_attempt;
  candidate_attempt.release_request_id = cross_request_id;
  candidate_attempt.project_membership_id =
    '6b770000-0000-4000-8000-000000000003'::uuid;
  candidate_attempt.capability_grant_id =
    '6b780000-0000-4000-8000-000000000004'::uuid;
  candidate_attempt.authorization_reference_at_utc =
    base_snapshot.data_cutoff_utc;
  candidate_attempt.project_id = cross_project_id;
  candidate_attempt.reporting_time_zone_effective_from_utc =
    cross_zone_effective_utc;
  candidate_attempt.data_cutoff_utc = base_snapshot.data_cutoff_utc;
  candidate_attempt.compared_snapshot_id = NULL;
  candidate_attempt.released_snapshot_id = cross_snapshot_id;
  candidate_attempt.shared_period_count = 0;
  candidate_attempt.assessed_cell_count = 0;
  candidate_attempt.result_status = 'approved_baseline';
  candidate_attempt.reason_codes = '[]'::jsonb;
  candidate_attempt.result_document = jsonb_build_object(
    'release_contract_id',
      'original_region_management_report_snapshot_release_v1',
    'release_request_id', candidate_attempt.release_request_id,
    'project_id', candidate_attempt.project_id,
    'release_lineage_id', candidate_attempt.release_lineage_id,
    'report_id', candidate_attempt.report_id,
    'report_version', candidate_attempt.report_version,
    'query_fingerprint', candidate_attempt.query_fingerprint,
    'reporting_time_zone_version_number',
      candidate_attempt.reporting_time_zone_version_number,
    'reporting_time_zone', candidate_attempt.reporting_time_zone,
    'data_cutoff_utc', to_char(
      candidate_attempt.data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'source_tree_version', candidate_attempt.source_tree_version,
    'source_content_fingerprint', candidate_attempt.source_content_fingerprint,
    'source_change_sequence', candidate_attempt.source_change_sequence,
    'compared_snapshot_id', candidate_attempt.compared_snapshot_id,
    'released_snapshot_id', candidate_attempt.released_snapshot_id,
    'shared_period_count', candidate_attempt.shared_period_count,
    'assessed_cell_count', candidate_attempt.assessed_cell_count,
    'result_status', candidate_attempt.result_status,
    'reason_codes', candidate_attempt.reason_codes
  );

  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    cross_request_id,
    'original_region_management_report_snapshot_release'
  );
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
    candidate_attempt.source_tree_version,
    candidate_attempt.source_content_fingerprint,
    candidate_attempt.source_change_sequence,
    candidate_attempt.compared_snapshot_id,
    candidate_attempt.released_snapshot_id,
    candidate_attempt.shared_period_count,
    candidate_attempt.assessed_cell_count,
    candidate_attempt.result_status,
    candidate_attempt.reason_codes,
    candidate_attempt.result_document
  );
  PERFORM set_config('session_replication_role', 'origin', true);

  -- These three rows deliberately carry foreign family metadata in the
  -- shared store.  0068's original-region attempt CHECK permits only the
  -- canonical original report and lineage, so no matching original-region
  -- attempt/ORIGINAL claim can exist for these rows.  The closed provenance
  -- JOIN therefore rejects them before the directory report WHERE predicate.
  PERFORM set_config('session_replication_role', 'replica', true);
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
      channel_snapshot_id,
      channel_request_id,
      base_snapshot.created_by_app_user_id,
      main_project_id,
      'management-report:contact_sessions_by_channel_two_periods',
      'contact_sessions_by_channel_two_periods',
      1,
      'management-report:contact_sessions_by_channel_two_periods:v1',
      base_snapshot.reporting_time_zone,
      base_snapshot.data_cutoff_utc,
      base_snapshot.released_at_utc,
      NULL,
      base_snapshot.source_change_sequence,
      base_snapshot.protected_report
    ),
    (
      current_city_snapshot_id,
      current_city_request_id,
      base_snapshot.created_by_app_user_id,
      main_project_id,
      'management-region-report:contact_sessions_by_current_city_two_periods',
      'contact_sessions_by_current_city_two_periods',
      1,
      'management-report:contact_sessions_by_current_city_two_periods:v1',
      base_snapshot.reporting_time_zone,
      base_snapshot.data_cutoff_utc,
      base_snapshot.released_at_utc,
      NULL,
      base_snapshot.source_change_sequence,
      base_snapshot.protected_report
    ),
    (
      interest_snapshot_id,
      interest_request_id,
      base_snapshot.created_by_app_user_id,
      main_project_id,
      'management-interest-report:contact_sessions_by_interest_level_two_periods',
      'contact_sessions_by_interest_level_two_periods',
      1,
      'management-report:contact_sessions_by_interest_level_two_periods:v1',
      base_snapshot.reporting_time_zone,
      base_snapshot.data_cutoff_utc,
      base_snapshot.released_at_utc,
      NULL,
      base_snapshot.source_change_sequence,
      base_snapshot.protected_report
    );
  PERFORM set_config('session_replication_role', 'origin', true);
  INSERT INTO fixture_6bk_directory_exclusions (
    case_name, snapshot_id, project_id, report_id
  ) VALUES
    (
      'foreign_channel', channel_snapshot_id, main_project_id,
      'contact_sessions_by_channel_two_periods'
    ),
    (
      'foreign_current_city', current_city_snapshot_id, main_project_id,
      'contact_sessions_by_current_city_two_periods'
    ),
    (
      'foreign_interest', interest_snapshot_id, main_project_id,
      'contact_sessions_by_interest_level_two_periods'
    );

  -- A legacy/unprovenanced original snapshot has valid protected metadata but
  -- no release attempt or family claim, so the closed directory join rejects it.
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
    legacy_snapshot_id,
    legacy_request_id,
    base_snapshot.created_by_app_user_id,
    main_project_id,
    base_snapshot.release_lineage_id,
    base_snapshot.report_id,
    base_snapshot.report_version,
    base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone,
    base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc,
    NULL,
    base_snapshot.source_change_sequence,
    base_snapshot.protected_report
  );
  INSERT INTO fixture_6bk_directory_exclusions (
    case_name, snapshot_id, project_id, report_id
  ) VALUES (
    'legacy_unprovenanced', legacy_snapshot_id, main_project_id,
    original_report_id
  );

  -- A drifted lineage tuple has an otherwise valid protected document but no
  -- longer belongs to the canonical original-region release family.  The
  -- 0068 attempt CHECK rejects a matching drifted attempt, so this remains a
  -- snapshot-only fail-closed case rather than a WHERE-only exclusion.
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
    drift_snapshot_id,
    drift_request_id,
    base_snapshot.created_by_app_user_id,
    main_project_id,
    'management-original-region-report:drifted-lineage',
    base_snapshot.report_id,
    base_snapshot.report_version,
    base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone,
    base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc,
    NULL,
    base_snapshot.source_change_sequence,
    base_snapshot.protected_report
  );
  INSERT INTO fixture_6bk_directory_exclusions (
    case_name, snapshot_id, project_id, report_id
  ) VALUES (
    'original_lineage_drift', drift_snapshot_id, main_project_id,
    original_report_id
  );

  IF (SELECT count(*) FROM fixture_6bk_directory_exclusions) <> 6
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = cross_snapshot_id
        AND snapshot.project_id = cross_project_id
        AND snapshot.report_id = original_report_id
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_private.management_report_snapshots AS snapshot
      JOIN app_private.management_original_region_report_release_attempts
        AS attempt
        ON attempt.released_snapshot_id = snapshot.snapshot_id
        AND attempt.release_request_id = snapshot.release_request_id
        AND attempt.requested_by_app_user_id =
          snapshot.created_by_app_user_id
        AND attempt.project_id = snapshot.project_id
        AND attempt.capability_id = 'release_management_reports'
        AND attempt.report_id = snapshot.report_id
        AND attempt.report_version = snapshot.report_version
        AND attempt.query_fingerprint = snapshot.query_fingerprint
        AND attempt.release_lineage_id = snapshot.release_lineage_id
        AND attempt.reporting_time_zone = snapshot.reporting_time_zone
        AND attempt.authorization_reference_at_utc =
          snapshot.data_cutoff_utc
        AND attempt.data_cutoff_utc = snapshot.data_cutoff_utc
        AND attempt.source_change_sequence = snapshot.source_change_sequence
        AND attempt.compared_snapshot_id IS NOT DISTINCT FROM
          snapshot.previous_snapshot_id
        AND attempt.source_tree_version =
          snapshot.protected_report->'source_tree_context'->>
            'source_tree_version'
        AND attempt.source_content_fingerprint =
          snapshot.protected_report->'source_tree_context'->>
            'source_content_fingerprint'
      JOIN app_private.management_report_release_request_claims AS claim
        ON claim.release_request_id = attempt.release_request_id
        AND claim.release_family_id =
          'original_region_management_report_snapshot_release'
      WHERE snapshot.snapshot_id = cross_snapshot_id
        AND snapshot.project_id = cross_project_id
        AND snapshot.report_id = original_report_id
        AND attempt.result_status IN ('approved_baseline', 'approved')
        AND attempt.reason_codes = '[]'::jsonb
        AND EXISTS (
          SELECT 1
          FROM app_private.project_reporting_time_zone_versions
            AS version_row
          WHERE version_row.project_id = attempt.project_id
            AND version_row.version_number =
              attempt.reporting_time_zone_version_number
            AND version_row.reporting_time_zone =
              attempt.reporting_time_zone
            AND version_row.effective_from_utc =
              attempt.reporting_time_zone_effective_from_utc
        )
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = channel_snapshot_id
        AND snapshot.report_id = 'contact_sessions_by_channel_two_periods'
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = current_city_snapshot_id
        AND snapshot.report_id = 'contact_sessions_by_current_city_two_periods'
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = interest_snapshot_id
        AND snapshot.report_id = 'contact_sessions_by_interest_level_two_periods'
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = legacy_snapshot_id
        AND snapshot.report_id = original_report_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_private.management_original_region_report_release_attempts AS attempt
      WHERE attempt.release_request_id = legacy_request_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_private.management_report_release_request_claims AS claim
      WHERE claim.release_request_id = legacy_request_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_private.management_original_region_report_release_attempts
        AS attempt
      WHERE attempt.release_request_id IN (
        channel_request_id,
        current_city_request_id,
        interest_request_id,
        drift_request_id
      )
    )
    OR EXISTS (
      SELECT 1
      FROM app_private.management_report_release_request_claims AS claim
      WHERE claim.release_request_id IN (
        channel_request_id,
        current_city_request_id,
        interest_request_id,
        drift_request_id
      )
    )
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot.snapshot_id = drift_snapshot_id
        AND snapshot.report_id = original_report_id
        AND snapshot.release_lineage_id <> original_lineage
    )
  THEN
    RAISE EXCEPTION '6BK directory exclusion rows were not constructed';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    PERFORM set_config('session_replication_role', 'origin', true);
    RAISE;
END
$fixture_6bk_directory_exclusions$;

GRANT SELECT ON fixture_6bk_directory_exclusions
  TO tongxingzhe_runtime;

DO $fixture_6bk_runtime$
DECLARE
  directory_result jsonb;
  empty_result jsonb;
  forbidden boolean := false;
  exclusion record;
BEGIN
  SET LOCAL ROLE tongxingzhe_runtime;

  directory_result = app_data.list_authorized_management_original_region_report_snapshots_v1(
    'https://directory-original.synthetic/auth/v1',
    'active-reader',
    '6b730000-0000-4000-8000-000000000001'::uuid
  );
  IF directory_result->>'access_contract_id' IS DISTINCT FROM
      'authorized_original_region_management_report_snapshot_directory_v1'
    OR jsonb_array_length(directory_result->'snapshots') <> 20
    OR directory_result->>'project_id' IS DISTINCT FROM
      '6b730000-0000-4000-8000-000000000001'
    OR directory_result::text ~
      '(protected_report|cells|source_tree|contributor|contact_id|source_key|PII|membership|capability)'
  THEN
    RAISE EXCEPTION '6BK directory result is not bounded: %', directory_result;
  END IF;

  FOR exclusion IN
    SELECT case_name, snapshot_id, project_id, report_id
    FROM fixture_6bk_directory_exclusions
    ORDER BY case_name
  LOOP
    IF EXISTS (
      SELECT 1
      FROM jsonb_array_elements(directory_result->'snapshots') AS item
      WHERE item->>'snapshot_id' = exclusion.snapshot_id::text
    ) THEN
      RAISE EXCEPTION
        '6BK directory admitted exclusion: %', exclusion.case_name;
    END IF;
  END LOOP;

  empty_result = app_data.list_authorized_management_original_region_report_snapshots_v1(
    'https://directory-original.synthetic/auth/v1',
    'active-reader',
    '6b730000-0000-4000-8000-000000000002'::uuid
  );
  IF jsonb_array_length(empty_result->'snapshots') <> 0 THEN
    RAISE EXCEPTION '6BK empty directory is not empty: %', empty_result;
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_original_region_report_snapshots_v1(
      'https://directory-original.synthetic/auth/v1',
      'unknown-reader',
      '6b730000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION 'unknown identity reached original-region directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_original_region_report_snapshots_v1(
      'https://directory-original.synthetic/auth/v1',
      'no-capability-reader',
      '6b730000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION 'reader without capability reached original-region directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_original_region_report_snapshots_v1(
      'https://directory-original.synthetic/auth/v1',
      'inactive-reader',
      '6b730000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION 'inactive identity reached original-region directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_original_region_report_snapshots_v1(
      'https://directory-original.synthetic/auth/v1',
      'spaced-reader',
      '6b730000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION 'trimmed identity reached original-region directory';
  END IF;

  RESET ROLE;
END
$fixture_6bk_runtime$;

DO $fixture_6bk_acl$
DECLARE
  audit_count bigint;
BEGIN
  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_original_region_snapshot_directory_access_events',
      'SELECT'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.list_authorized_management_original_region_report_snapshots_v1(uuid,uuid)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime received private original-region directory access';
  END IF;

  SELECT count(*) INTO audit_count
  FROM app_private.management_original_region_snapshot_directory_access_events
  WHERE project_id = '6b730000-0000-4000-8000-000000000002'::uuid;
  IF audit_count <> 1 THEN
    RAISE EXCEPTION 'empty directory did not leave one value-free audit: %', audit_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_original_region_snapshot_directory_access_events
    WHERE project_id = '6b730000-0000-4000-8000-000000000002'::uuid
      AND returned_snapshot_count <> 0
  ) THEN
    RAISE EXCEPTION 'empty directory audit returned a non-zero count';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_original_region_report_release_attempts AS attempt
    WHERE attempt.project_id = '6b730000-0000-4000-8000-000000000001'::uuid
      AND attempt.result_status = 'blocked'
      AND attempt.released_snapshot_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'blocked provenance created a released snapshot';
  END IF;
END
$fixture_6bk_acl$;

ROLLBACK;
