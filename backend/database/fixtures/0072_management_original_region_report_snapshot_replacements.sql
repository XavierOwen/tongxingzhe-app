-- Synthetic rollback fixture for Slice 6BN.
--
-- This fixture uses the public 6BN declaration and lifecycle seams.  It builds
-- two small, valid 6BG original-region snapshots and value-free provenance,
-- then exercises a strict chain, replay/idempotency, provenance and tuple
-- negatives, revoke, and immutable history.  Every row created here is rolled
-- back.  No report value is returned by the replacement contract.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b200000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b200000-0000-4000-8000-000000000002'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id,
  deleted_at
) VALUES
  (
    '6b210000-0000-4000-8000-000000000001'::uuid,
    'organization', 'Slice 6BN original replacement workspace', NULL, NULL
  );

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES
  (
    '6b220000-0000-4000-8000-000000000001'::uuid,
    '6b210000-0000-4000-8000-000000000001'::uuid,
    'Slice 6BN original replacement project', 'active', false
  ),
  (
    '6b220000-0000-4000-8000-000000000002'::uuid,
    '6b210000-0000-4000-8000-000000000001'::uuid,
    'Slice 6BN cross-project negative', 'active', false
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
) VALUES (
  '6b230000-0000-4000-8000-000000000001'::uuid,
  '6b210000-0000-4000-8000-000000000001'::uuid,
  '6b200000-0000-4000-8000-000000000001'::uuid,
  clock_timestamp() - interval '30 days', NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6b240000-0000-4000-8000-000000000001'::uuid,
    '6b230000-0000-4000-8000-000000000001'::uuid,
    '6b220000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b240000-0000-4000-8000-000000000002'::uuid,
    '6b230000-0000-4000-8000-000000000001'::uuid,
    '6b220000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6b250000-0000-4000-8000-000000000001'::uuid,
    '6b240000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6b250000-0000-4000-8000-000000000002'::uuid,
    '6b240000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b260000-0000-4000-8000-000000000001'::uuid,
  '6b200000-0000-4000-8000-000000000001'::uuid,
  '6b220000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b260000-0000-4000-8000-000000000002'::uuid,
  '6b200000-0000-4000-8000-000000000001'::uuid,
  '6b220000-0000-4000-8000-000000000002'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

-- A one-city published tree is sufficient for a two-cell original report.
-- The source tree release is intentionally older than both future synthetic
-- cutoffs, so the 6BG validator can prove the exact source tuple.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current, published_at_utc,
  content_fingerprint
) VALUES (
  'fixture-6bn-original-v1', 'draft', false, NULL, NULL
);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  (
    'fixture-6bn-country', 'fixture-6bn-original-v1', NULL,
    '6BN Country', 'country'
  ),
  (
    'fixture-6bn-city', 'fixture-6bn-original-v1', 'fixture-6bn-country',
    '6BN City', 'city'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'fixture-6bn-city-boundary', 'fixture-6bn-city',
  'fixture-6bn-original-v1',
  polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bn-original-v1', false
);

CREATE TEMP TABLE fixture_6bn_source AS
SELECT tree_version, content_fingerprint
FROM app_data.canonical_region_tree_releases
WHERE tree_version = 'fixture-6bn-original-v1';

CREATE TEMP TABLE fixture_6bn_snapshots (
  baseline_snapshot_id uuid,
  replacement_snapshot_id uuid,
  cross_project_snapshot_id uuid,
  drifted_snapshot_id uuid,
  legacy_snapshot_id uuid,
  blocked_snapshot_id uuid,
  privacy_drift_snapshot_id uuid,
  source_scope_drift_snapshot_id uuid,
  period_drift_snapshot_id uuid
) ON COMMIT DROP;

DO $fixture_6bn_setup$
DECLARE
  project_id constant uuid := '6b220000-0000-4000-8000-000000000001';
  other_project_id constant uuid := '6b220000-0000-4000-8000-000000000002';
  owner_id constant uuid := '6b200000-0000-4000-8000-000000000001';
  report_id constant text :=
    'contact_sessions_by_original_region_two_periods';
  lineage_id constant text :=
    'management-original-region-report:contact_sessions_by_original_region_two_periods';
  query_fingerprint constant text :=
    'management-report:contact_sessions_by_original_region_two_periods:v1';
  baseline_id constant uuid := '6b270000-0000-4000-8000-000000000001';
  replacement_id constant uuid := '6b270000-0000-4000-8000-000000000002';
  cross_project_id constant uuid := '6b270000-0000-4000-8000-000000000003';
  drifted_id constant uuid := '6b270000-0000-4000-8000-000000000004';
  legacy_id constant uuid := '6b270000-0000-4000-8000-000000000005';
  blocked_id constant uuid := '6b270000-0000-4000-8000-000000000006';
  privacy_drift_id constant uuid := '6b270000-0000-4000-8000-000000000007';
  source_scope_drift_id constant uuid := '6b270000-0000-4000-8000-000000000008';
  period_drift_id constant uuid := '6b270000-0000-4000-8000-000000000009';
  baseline_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000001';
  replacement_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000002';
  cross_project_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000003';
  drifted_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000004';
  legacy_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000005';
  blocked_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000006';
  privacy_drift_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000007';
  source_scope_drift_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000008';
  period_drift_request_id constant uuid :=
    '6b280000-0000-4000-8000-000000000009';
  baseline_cutoff constant timestamptz :=
    '2099-01-15 12:00:00+00';
  replacement_cutoff constant timestamptz :=
    '2099-01-16 12:00:00+00';
  drifted_cutoff constant timestamptz :=
    '2099-01-16 13:00:00+00';
  privacy_drift_cutoff constant timestamptz :=
    '2099-01-16 14:00:00+00';
  source_scope_drift_cutoff constant timestamptz :=
    '2099-01-16 15:00:00+00';
  period_drift_cutoff constant timestamptz :=
    '2099-01-16 16:00:00+00';
  baseline_released_at constant timestamptz :=
    '2099-01-15 13:00:00+00';
  replacement_released_at constant timestamptz :=
    '2099-01-16 13:00:00+00';
  time_zone_effective timestamptz;
  source_version text;
  source_fingerprint text;
  baseline_periods jsonb;
  replacement_periods jsonb;
  drifted_periods jsonb;
  privacy_drift_periods jsonb;
  source_scope_drift_periods jsonb;
  period_drift_periods jsonb;
  baseline_document jsonb;
  replacement_document jsonb;
  cross_project_document jsonb;
  drifted_document jsonb;
  privacy_drift_document jsonb;
  source_scope_drift_document jsonb;
  period_drift_document jsonb;
  baseline_audit jsonb;
  replacement_audit jsonb;
BEGIN
  SELECT version_row.effective_from_utc
  INTO STRICT time_zone_effective
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id =
      '6b220000-0000-4000-8000-000000000001'::uuid
    AND version_row.version_number = 1;

  SELECT tree_version, content_fingerprint
  INTO STRICT source_version, source_fingerprint
  FROM fixture_6bn_source;

  baseline_periods = app_private.resolve_management_report_periods_v1(
    'UTC', baseline_cutoff
  );
  replacement_periods = app_private.resolve_management_report_periods_v1(
    'UTC', replacement_cutoff
  );
  drifted_periods = app_private.resolve_management_report_periods_v1(
    'UTC', drifted_cutoff
  );
  privacy_drift_periods = app_private.resolve_management_report_periods_v1(
    'UTC', privacy_drift_cutoff
  );
  source_scope_drift_periods = app_private.resolve_management_report_periods_v1(
    'UTC', source_scope_drift_cutoff
  );
  period_drift_periods = app_private.resolve_management_report_periods_v1(
    'UTC', period_drift_cutoff
  );

  baseline_document = jsonb_build_object(
    'report_id', report_id,
    'report_version', 1,
    'metric_id', 'contact_sessions',
    'metric_version', 1,
    'dimension', 'original_region',
    'view_mode', 'original',
    'region_granularity', 'city',
    'query_fingerprint', query_fingerprint,
    'privacy_policy', 'management_original_region_contact_session_privacy_v1',
    'source_scope', 'backend_accepted_active_contacts_original_current_revision',
    'project_id', project_id,
    'periods', baseline_periods,
    'data_cutoff_utc', baseline_periods->>'data_cutoff_utc',
    'source_change_sequence', 1,
    'source_tree_context', jsonb_build_object(
      'source_tree_context_contract_id', 'management-original-region-source-tree:v1',
      'result_status', 'selected',
      'reason_code', 'single_original_source_tree',
      'source_tree_version', source_version,
      'source_content_fingerprint', source_fingerprint
    ),
    'result_status', 'completed',
    'cells', jsonb_build_array(
      jsonb_build_object(
        'period_key', 'previous', 'city_id', 'fixture-6bn-city',
        'cell_order', 0, 'value_count', 10, 'privacy_status', 'displayed'
      ),
      jsonb_build_object(
        'period_key', 'current', 'city_id', 'fixture-6bn-city',
        'cell_order', 1, 'value_count', 10, 'privacy_status', 'displayed'
      )
    )
  );

  replacement_document = jsonb_set(
    baseline_document,
    '{project_id}', to_jsonb(project_id::text)
  );
  replacement_document = jsonb_set(
    replacement_document, '{periods}', replacement_periods
  );
  replacement_document = jsonb_set(
    replacement_document, '{data_cutoff_utc}',
    to_jsonb(replacement_periods->>'data_cutoff_utc')
  );
  replacement_document = jsonb_set(
    replacement_document, '{source_change_sequence}', '1'::jsonb
  );

  -- A trusted baseline and successor are inserted with the exact immutable
  -- report documents that 6BG would have produced.  This fixture does not
  -- call 6BG's report generator or invent a replacement report.
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES
    (
      baseline_id, baseline_request_id, owner_id, project_id, lineage_id,
      report_id, 1, query_fingerprint, 'UTC', baseline_cutoff,
      baseline_released_at, NULL, 1, baseline_document
    ),
    (
      replacement_id, replacement_request_id, owner_id, project_id, lineage_id,
      report_id, 1, query_fingerprint, 'UTC', replacement_cutoff,
      replacement_released_at, baseline_id, 1, replacement_document
    );

  -- The cross-project row has a valid original document whose project is the
  -- second project.  It must not be usable from the primary project.
  cross_project_document = jsonb_set(
    baseline_document, '{project_id}', to_jsonb(other_project_id::text)
  );
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    cross_project_id, cross_project_request_id, owner_id, other_project_id,
    lineage_id, report_id, 1, query_fingerprint, 'UTC', baseline_cutoff,
    baseline_released_at, NULL, 1, cross_project_document
  );

  -- The drifted row points at a different source tuple.  It remains a valid
  -- original report in isolation but is not a successor of the baseline.
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current, published_at_utc,
    content_fingerprint
  ) VALUES (
    'fixture-6bn-drifted-v1', 'draft', false, NULL, NULL
  );
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('fixture-6bn-drift-country', 'fixture-6bn-drifted-v1', NULL,
      '6BN Drift Country', 'country'),
    ('fixture-6bn-drift-city', 'fixture-6bn-drifted-v1',
      'fixture-6bn-drift-country', '6BN Drift City', 'city');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES (
    'fixture-6bn-drift-boundary', 'fixture-6bn-drift-city',
    'fixture-6bn-drifted-v1',
    polygon '((-89.00,41.60),(-88.90,41.60),(-88.90,41.70),(-89.00,41.70))'
  );
  PERFORM app_private.publish_canonical_region_tree_v1(
    'fixture-6bn-drifted-v1', false
  );
  SELECT content_fingerprint INTO STRICT source_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'fixture-6bn-drifted-v1';
  drifted_document = jsonb_set(
    replacement_document, '{periods}', drifted_periods
  );
  drifted_document = jsonb_set(
    drifted_document, '{data_cutoff_utc}',
    to_jsonb(drifted_periods->>'data_cutoff_utc')
  );
  drifted_document = jsonb_set(
    drifted_document, '{source_tree_context}', jsonb_build_object(
      'source_tree_context_contract_id', 'management-original-region-source-tree:v1',
      'result_status', 'selected',
      'reason_code', 'single_original_source_tree',
      'source_tree_version', 'fixture-6bn-drifted-v1',
      'source_content_fingerprint', source_fingerprint
    )
  );
  drifted_document = jsonb_set(
    drifted_document, '{cells}', jsonb_build_array(
      jsonb_build_object(
        'period_key', 'previous',
        'city_id', 'fixture-6bn-drift-city',
        'cell_order', 0,
        'value_count', 10,
        'privacy_status', 'displayed'
      ),
      jsonb_build_object(
        'period_key', 'current',
        'city_id', 'fixture-6bn-drift-city',
        'cell_order', 1,
        'value_count', 10,
        'privacy_status', 'displayed'
      )
    )
  );
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    drifted_id, drifted_request_id, owner_id, project_id, lineage_id,
    report_id, 1, query_fingerprint, 'UTC', drifted_cutoff,
    drifted_cutoff + interval '1 hour', replacement_id, 1, drifted_document
  );

  privacy_drift_document = jsonb_set(
    replacement_document, '{periods}', privacy_drift_periods
  );
  privacy_drift_document = jsonb_set(
    privacy_drift_document, '{data_cutoff_utc}',
    to_jsonb(privacy_drift_periods->>'data_cutoff_utc')
  );
  privacy_drift_document = jsonb_set(
    privacy_drift_document, '{privacy_policy}', '"fixture-privacy-drift"'::jsonb
  );
  source_scope_drift_document = jsonb_set(
    replacement_document, '{periods}', source_scope_drift_periods
  );
  source_scope_drift_document = jsonb_set(
    source_scope_drift_document, '{data_cutoff_utc}',
    to_jsonb(source_scope_drift_periods->>'data_cutoff_utc')
  );
  source_scope_drift_document = jsonb_set(
    source_scope_drift_document, '{source_scope}',
    '"fixture-source-scope-drift"'::jsonb
  );
  period_drift_periods = jsonb_set(
    period_drift_periods,
    '{current_period,start_utc}',
    to_jsonb(
      (period_drift_periods->'current_period'->>'start_utc') || '-drift'
    )
  );
  period_drift_document = jsonb_set(
    replacement_document, '{periods}', period_drift_periods
  );
  period_drift_document = jsonb_set(
    period_drift_document, '{data_cutoff_utc}',
    to_jsonb(period_drift_periods->>'data_cutoff_utc')
  );

  -- These rows exercise family and blocked provenance checks.  The shared
  -- snapshot trigger is bypassed only for negative rows; the public 6BN seam
  -- must still reject them before it can write a replacement ledger row.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES
    (
      legacy_id, legacy_request_id, owner_id, project_id,
      'management-report:contact_sessions_by_channel_two_periods',
      'contact_sessions_by_channel_two_periods', 1, 'legacy-channel', 'UTC',
      baseline_cutoff, baseline_released_at, NULL, 1, '{}'::jsonb
    ),
    (
      blocked_id, blocked_request_id, owner_id, project_id, lineage_id,
      report_id, 1, query_fingerprint, 'UTC', replacement_cutoff + interval '2 days',
      replacement_released_at + interval '2 days', NULL, 4, '{}'::jsonb
    ),
    (
      privacy_drift_id, privacy_drift_request_id, owner_id, project_id,
      lineage_id, report_id, 1, query_fingerprint, 'UTC', privacy_drift_cutoff,
      privacy_drift_cutoff + interval '1 hour', replacement_id, 1,
      privacy_drift_document
    ),
    (
      source_scope_drift_id, source_scope_drift_request_id, owner_id, project_id,
      lineage_id, report_id, 1, query_fingerprint, 'UTC',
      source_scope_drift_cutoff,
      source_scope_drift_cutoff + interval '1 hour', replacement_id, 1,
      source_scope_drift_document
    ),
    (
      period_drift_id, period_drift_request_id, owner_id, project_id,
      lineage_id, report_id, 1, query_fingerprint, 'UTC', period_drift_cutoff,
      period_drift_cutoff + interval '1 hour', replacement_id, 1,
      period_drift_document
    );
  PERFORM set_config('session_replication_role', 'origin', true);

  -- Each approved snapshot has independent 6BG release provenance and the
  -- shared request claim family.  The trigger checks the exact tuple and
  -- keeps the audit envelope value-free.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES
    (baseline_request_id, 'original_region_management_report_snapshot_release'),
    (replacement_request_id, 'original_region_management_report_snapshot_release'),
    (drifted_request_id, 'original_region_management_report_snapshot_release'),
    (privacy_drift_request_id,
      'original_region_management_report_snapshot_release'),
    (source_scope_drift_request_id,
      'original_region_management_report_snapshot_release'),
    (period_drift_request_id,
      'original_region_management_report_snapshot_release');

  baseline_audit = jsonb_build_object(
    'release_contract_id', 'original_region_management_report_snapshot_release_v1',
    'release_request_id', baseline_request_id,
    'project_id', project_id,
    'release_lineage_id', lineage_id,
    'report_id', report_id,
    'report_version', 1,
    'query_fingerprint', query_fingerprint,
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', 'UTC',
    'data_cutoff_utc', to_char(baseline_cutoff AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_tree_version', 'fixture-6bn-original-v1',
    'source_content_fingerprint', (SELECT content_fingerprint
      FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-6bn-original-v1'),
    'source_change_sequence', 1,
    'compared_snapshot_id', NULL,
    'released_snapshot_id', baseline_id,
    'shared_period_count', 0,
    'assessed_cell_count', 0,
    'result_status', 'approved_baseline',
    'reason_codes', '[]'::jsonb
  );
  replacement_audit = jsonb_build_object(
    'release_contract_id', 'original_region_management_report_snapshot_release_v1',
    'release_request_id', replacement_request_id,
    'project_id', project_id,
    'release_lineage_id', lineage_id,
    'report_id', report_id,
    'report_version', 1,
    'query_fingerprint', query_fingerprint,
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', 'UTC',
    'data_cutoff_utc', to_char(replacement_cutoff AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source_tree_version', 'fixture-6bn-original-v1',
    'source_content_fingerprint', (SELECT content_fingerprint
      FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-6bn-original-v1'),
    'source_change_sequence', 1,
    'compared_snapshot_id', baseline_id,
    'released_snapshot_id', replacement_id,
    'shared_period_count', 2,
    'assessed_cell_count', 4,
    'result_status', 'approved',
    'reason_codes', '[]'::jsonb
  );

  INSERT INTO app_private.management_original_region_report_release_attempts (
    release_request_id, requested_by_app_user_id,
    organization_workspace_id, organization_membership_id,
    project_membership_id, capability_grant_id, capability_id,
    authorization_reference_at_utc, project_id,
    reporting_time_zone_version_number, reporting_time_zone,
    reporting_time_zone_effective_from_utc, data_cutoff_utc,
    release_lineage_id, report_id, report_version, query_fingerprint,
    source_tree_version, source_content_fingerprint, source_change_sequence,
    compared_snapshot_id, released_snapshot_id, shared_period_count,
    assessed_cell_count, result_status, reason_codes, result_document
  ) VALUES
    (
      baseline_request_id, owner_id,
      '6b210000-0000-4000-8000-000000000001'::uuid,
      '6b230000-0000-4000-8000-000000000001'::uuid,
      '6b240000-0000-4000-8000-000000000001'::uuid,
      '6b250000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', baseline_cutoff, project_id, 1, 'UTC',
      time_zone_effective, baseline_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6bn-original-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6bn-original-v1'), 1, NULL, baseline_id,
      0, 0, 'approved_baseline', '[]'::jsonb,
      baseline_audit
    ),
    (
      replacement_request_id, owner_id,
      '6b210000-0000-4000-8000-000000000001'::uuid,
      '6b230000-0000-4000-8000-000000000001'::uuid,
      '6b240000-0000-4000-8000-000000000001'::uuid,
      '6b250000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', replacement_cutoff, project_id, 1, 'UTC',
      time_zone_effective, replacement_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6bn-original-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6bn-original-v1'), 1, baseline_id,
      replacement_id, 2, 4, 'approved', '[]'::jsonb,
      replacement_audit
    );

  -- Synthetic approved provenance for the four tuple-drift rows ensures the
  -- public declaration reaches its cross-snapshot comparisons.  The fixture
  -- bypasses attempt validation only to isolate each malformed tuple.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_private.management_original_region_report_release_attempts (
    release_request_id, requested_by_app_user_id,
    organization_workspace_id, organization_membership_id,
    project_membership_id, capability_grant_id, capability_id,
    authorization_reference_at_utc, project_id,
    reporting_time_zone_version_number, reporting_time_zone,
    reporting_time_zone_effective_from_utc, data_cutoff_utc,
    release_lineage_id, report_id, report_version, query_fingerprint,
    source_tree_version, source_content_fingerprint, source_change_sequence,
    compared_snapshot_id, released_snapshot_id, shared_period_count,
    assessed_cell_count, result_status, reason_codes, result_document
  ) VALUES
    (
      drifted_request_id, owner_id,
      '6b210000-0000-4000-8000-000000000001'::uuid,
      '6b230000-0000-4000-8000-000000000001'::uuid,
      '6b240000-0000-4000-8000-000000000001'::uuid,
      '6b250000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', drifted_cutoff, project_id, 1, 'UTC',
      time_zone_effective, drifted_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6bn-drifted-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6bn-drifted-v1'), 1, replacement_id,
      drifted_id, 2, 4, 'approved', '[]'::jsonb, '{}'::jsonb
    ),
    (
      privacy_drift_request_id, owner_id,
      '6b210000-0000-4000-8000-000000000001'::uuid,
      '6b230000-0000-4000-8000-000000000001'::uuid,
      '6b240000-0000-4000-8000-000000000001'::uuid,
      '6b250000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', privacy_drift_cutoff, project_id, 1, 'UTC',
      time_zone_effective, privacy_drift_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6bn-original-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6bn-original-v1'), 1, replacement_id,
      privacy_drift_id, 2, 4, 'approved', '[]'::jsonb, '{}'::jsonb
    ),
    (
      source_scope_drift_request_id, owner_id,
      '6b210000-0000-4000-8000-000000000001'::uuid,
      '6b230000-0000-4000-8000-000000000001'::uuid,
      '6b240000-0000-4000-8000-000000000001'::uuid,
      '6b250000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', source_scope_drift_cutoff, project_id, 1,
      'UTC', time_zone_effective, source_scope_drift_cutoff, lineage_id,
      report_id, 1, query_fingerprint, 'fixture-6bn-original-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6bn-original-v1'), 1, replacement_id,
      source_scope_drift_id, 2, 4, 'approved', '[]'::jsonb, '{}'::jsonb
    ),
    (
      period_drift_request_id, owner_id,
      '6b210000-0000-4000-8000-000000000001'::uuid,
      '6b230000-0000-4000-8000-000000000001'::uuid,
      '6b240000-0000-4000-8000-000000000001'::uuid,
      '6b250000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', period_drift_cutoff, project_id, 1, 'UTC',
      time_zone_effective, period_drift_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6bn-original-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6bn-original-v1'), 1, replacement_id,
      period_drift_id, 2, 4, 'approved', '[]'::jsonb, '{}'::jsonb
    );
  PERFORM set_config('session_replication_role', 'origin', true);

  INSERT INTO fixture_6bn_snapshots (
    baseline_snapshot_id, replacement_snapshot_id,
    cross_project_snapshot_id, drifted_snapshot_id,
    legacy_snapshot_id, blocked_snapshot_id,
    privacy_drift_snapshot_id, source_scope_drift_snapshot_id,
    period_drift_snapshot_id
  ) VALUES (baseline_id, replacement_id, cross_project_id, drifted_id,
    legacy_id, blocked_id, privacy_drift_id, source_scope_drift_id,
    period_drift_id);
END
$fixture_6bn_setup$;

DO $fixture_6bn_contract$
DECLARE
  project_id constant uuid := '6b220000-0000-4000-8000-000000000001';
  owner_id constant uuid := '6b200000-0000-4000-8000-000000000001';
  baseline_id uuid;
  replacement_id uuid;
  cross_project_id uuid;
  drifted_id uuid;
  legacy_id uuid;
  blocked_id uuid;
  privacy_drift_id uuid;
  source_scope_drift_id uuid;
  period_drift_id uuid;
  declaration_result jsonb;
  replay_result jsonb;
  lifecycle_result jsonb;
  replacement_count bigint;
  snapshot_before jsonb;
  snapshot_after jsonb;
BEGIN
  SELECT baseline_snapshot_id, replacement_snapshot_id,
    cross_project_snapshot_id, drifted_snapshot_id,
    legacy_snapshot_id, blocked_snapshot_id,
    privacy_drift_snapshot_id, source_scope_drift_snapshot_id,
    period_drift_snapshot_id
  INTO STRICT baseline_id, replacement_id, cross_project_id, drifted_id,
    legacy_id, blocked_id, privacy_drift_id, source_scope_drift_id,
    period_drift_id
  FROM fixture_6bn_snapshots;

  -- The replacement is not a second report definition.  Pin every invariant
  -- that the public seam must re-check, while allowing only cutoff, publish
  -- time and source watermark to advance.
  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS old_snapshot
    JOIN app_private.management_report_snapshots AS new_snapshot
      ON new_snapshot.snapshot_id = replacement_id
    WHERE old_snapshot.snapshot_id = baseline_id
      AND (
        old_snapshot.project_id IS DISTINCT FROM new_snapshot.project_id
        OR old_snapshot.release_lineage_id IS DISTINCT FROM
          new_snapshot.release_lineage_id
        OR old_snapshot.report_id IS DISTINCT FROM new_snapshot.report_id
        OR old_snapshot.report_version IS DISTINCT FROM new_snapshot.report_version
        OR old_snapshot.query_fingerprint IS DISTINCT FROM
          new_snapshot.query_fingerprint
        OR old_snapshot.reporting_time_zone IS DISTINCT FROM
          new_snapshot.reporting_time_zone
        OR old_snapshot.data_cutoff_utc >= new_snapshot.data_cutoff_utc
        OR old_snapshot.released_at_utc >= new_snapshot.released_at_utc
        OR old_snapshot.source_change_sequence > new_snapshot.source_change_sequence
        OR old_snapshot.protected_report->>'privacy_policy' IS DISTINCT FROM
          new_snapshot.protected_report->>'privacy_policy'
        OR old_snapshot.protected_report->>'source_scope' IS DISTINCT FROM
          new_snapshot.protected_report->>'source_scope'
        OR old_snapshot.protected_report->'source_tree_context' IS DISTINCT FROM
          new_snapshot.protected_report->'source_tree_context'
        OR (
          (old_snapshot.protected_report->'periods') -
            'data_cutoff_utc'::text
        )
          IS DISTINCT FROM
          (
            (new_snapshot.protected_report->'periods') -
              'data_cutoff_utc'::text
          )
      )
  ) THEN
    RAISE EXCEPTION
      'original replacement cross-snapshot contract is not stable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_original_region_report_release_attempts
      AS old_attempt
    JOIN app_private.management_original_region_report_release_attempts
      AS new_attempt
      ON new_attempt.release_request_id =
        '6b280000-0000-4000-8000-000000000002'::uuid
    WHERE old_attempt.release_request_id =
        '6b280000-0000-4000-8000-000000000001'::uuid
      AND (
        old_attempt.project_id IS DISTINCT FROM new_attempt.project_id
        OR old_attempt.release_lineage_id IS DISTINCT FROM
          new_attempt.release_lineage_id
        OR old_attempt.report_id IS DISTINCT FROM new_attempt.report_id
        OR old_attempt.report_version IS DISTINCT FROM new_attempt.report_version
        OR old_attempt.query_fingerprint IS DISTINCT FROM
          new_attempt.query_fingerprint
        OR old_attempt.reporting_time_zone_version_number IS DISTINCT FROM
          new_attempt.reporting_time_zone_version_number
        OR old_attempt.reporting_time_zone IS DISTINCT FROM
          new_attempt.reporting_time_zone
        OR old_attempt.reporting_time_zone_effective_from_utc IS DISTINCT FROM
          new_attempt.reporting_time_zone_effective_from_utc
        OR old_attempt.source_tree_version IS DISTINCT FROM
          new_attempt.source_tree_version
        OR old_attempt.source_content_fingerprint IS DISTINCT FROM
          new_attempt.source_content_fingerprint
        OR old_attempt.authorization_reference_at_utc >=
          new_attempt.authorization_reference_at_utc
        OR old_attempt.source_change_sequence >
          new_attempt.source_change_sequence
      )
  ) THEN
    RAISE EXCEPTION
      'original replacement release provenance contract is not stable';
  END IF;

  SELECT to_jsonb(snapshot) - ARRAY['snapshot_id', 'release_request_id']
  INTO STRICT snapshot_before
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_id;

  IF NOT app_private.management_original_region_snapshot_has_trusted_provenance_v1(
      drifted_id,
      project_id
    )
    OR NOT app_private.management_original_region_snapshot_has_trusted_provenance_v1(
      privacy_drift_id,
      project_id
    )
    OR NOT app_private.management_original_region_snapshot_has_trusted_provenance_v1(
      source_scope_drift_id,
      project_id
    )
    OR NOT app_private.management_original_region_snapshot_has_trusted_provenance_v1(
      period_drift_id,
      project_id
    )
  THEN
    RAISE EXCEPTION
      'tuple-drift negatives do not reach cross-snapshot validation';
  END IF;

  -- A release request owns its UUID before a replacement can claim it.
  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b280000-0000-4000-8000-000000000001'::uuid,
        owner_id, project_id, baseline_id, replacement_id, 'contact_revision'
      );
    RAISE EXCEPTION 'release request UUID was reused for replacement';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  declaration_result =
    app_private.declare_management_original_region_snapshot_replacement_v1(
      '6b290000-0000-4000-8000-000000000001'::uuid,
      owner_id, project_id, baseline_id, replacement_id, 'contact_revision'
    );
  IF declaration_result->>'replacement_contract_id' IS DISTINCT FROM
      'original_region_management_report_snapshot_replacement_v1'
    OR declaration_result->>'result_status' IS DISTINCT FROM 'completed'
    OR declaration_result->>'superseded_snapshot_id' IS DISTINCT FROM baseline_id::text
    OR declaration_result->>'replacement_snapshot_id' IS DISTINCT FROM replacement_id::text
    OR declaration_result->>'replacement_reason_code' IS DISTINCT FROM 'contact_revision'
    OR declaration_result ? 'protected_report'
    OR declaration_result ? 'result_document'
    OR declaration_result::text ~
      '(cells|value_count|contributor|contact_id|place_name|source_tree_context)'
  THEN
    RAISE EXCEPTION 'valid original replacement result is not value-free: %',
      declaration_result;
  END IF;

  SELECT count(*) INTO replacement_count
  FROM app_private.management_original_region_report_snapshot_replacements;
  replay_result =
    app_private.declare_management_original_region_snapshot_replacement_v1(
      '6b290000-0000-4000-8000-000000000001'::uuid,
      owner_id, project_id, baseline_id, replacement_id, 'contact_revision'
    );
  IF replay_result <> declaration_result
    OR (SELECT count(*)
        FROM app_private.management_original_region_report_snapshot_replacements)
      <> replacement_count
  THEN
    RAISE EXCEPTION 'identical original replacement retry was not idempotent';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_request_claims AS claim
    WHERE claim.release_request_id =
        '6b290000-0000-4000-8000-000000000001'::uuid
      AND claim.release_family_id =
        'original_region_management_report_snapshot_replacement'
  ) THEN
    RAISE EXCEPTION 'replacement request did not claim its global UUID';
  END IF;

  -- The replacement claim also prevents a later 6BG release from reusing the
  -- same UUID.  Both contracts use the common request advisory lock.
  BEGIN
    PERFORM app_private.release_management_original_region_report_snapshot_v1(
      '6b290000-0000-4000-8000-000000000001'::uuid,
      owner_id,
      project_id,
      'contact_sessions_by_original_region_two_periods',
      1
    );
    RAISE EXCEPTION 'replacement request UUID was reused for release';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  lifecycle_result =
    app_private.read_management_original_region_report_snapshot_lifecycle_v1(
      project_id, baseline_id
    );
  IF lifecycle_result <> jsonb_build_object(
      'lifecycle_contract_id',
        'original_region_management_report_snapshot_lifecycle_v1',
      'project_id', project_id, 'snapshot_id', baseline_id,
      'lifecycle_status', 'superseded',
      'replacement_snapshot_id', replacement_id
    )
  THEN
    RAISE EXCEPTION 'superseded original lifecycle result is incorrect: %',
      lifecycle_result;
  END IF;

  lifecycle_result =
    app_private.read_management_original_region_report_snapshot_lifecycle_v1(
      project_id, replacement_id
    );
  IF lifecycle_result->>'lifecycle_status' IS DISTINCT FROM 'active'
    OR lifecycle_result->>'replacement_snapshot_id' IS NOT NULL
    OR lifecycle_result ? 'protected_report'
  THEN
    RAISE EXCEPTION 'active original lifecycle result is incorrect: %',
      lifecycle_result;
  END IF;

  -- A request UUID is bound to its complete canonical payload.
  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000001'::uuid,
        owner_id, project_id, baseline_id, replacement_id, 'contact_void'
      );
    RAISE EXCEPTION 'original replacement request payload drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-00000000000d'::uuid,
        owner_id, project_id, replacement_id, drifted_id, 'manual_override'
      );
    RAISE EXCEPTION 'unknown original replacement reason was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- Old heads cannot branch; self, reverse, cross-project, source-tree drift,
  -- blocked provenance, legacy family and an unknown ID all fail closed.
  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000002'::uuid,
        owner_id, project_id, baseline_id, baseline_id, 'contact_void'
      );
    RAISE EXCEPTION 'original self replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000003'::uuid,
        owner_id, project_id, replacement_id, baseline_id, 'late_accepted_data'
      );
    RAISE EXCEPTION 'original reverse replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000004'::uuid,
        owner_id, project_id, replacement_id, cross_project_id, 'contact_void'
      );
    RAISE EXCEPTION 'original cross-project replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000005'::uuid,
        owner_id, project_id, replacement_id, drifted_id, 'contact_revision'
      );
    RAISE EXCEPTION 'original source-tree drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-00000000000a'::uuid,
        owner_id, project_id, replacement_id, privacy_drift_id, 'contact_revision'
      );
    RAISE EXCEPTION 'original privacy drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-00000000000b'::uuid,
        owner_id, project_id, replacement_id,
        source_scope_drift_id, 'contact_revision'
      );
    RAISE EXCEPTION 'original source scope drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-00000000000c'::uuid,
        owner_id, project_id, replacement_id, period_drift_id, 'contact_revision'
      );
    RAISE EXCEPTION 'original period drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000006'::uuid,
        owner_id, project_id, replacement_id, blocked_id, 'contact_revision'
      );
    RAISE EXCEPTION 'original blocked provenance was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000007'::uuid,
        owner_id, project_id, replacement_id, legacy_id, 'contact_revision'
      );
    RAISE EXCEPTION 'legacy family replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000008'::uuid,
        owner_id, project_id, replacement_id,
        '6b2a0000-0000-4000-8000-000000000001'::uuid, 'contact_revision'
      );
    RAISE EXCEPTION 'unknown original replacement snapshot was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  -- A revoked capability is rechecked after the request/lineage locks.  No
  -- replacement row may be written when authorization is inactive.
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '6b250000-0000-4000-8000-000000000001'::uuid;
  BEGIN
    PERFORM
      app_private.declare_management_original_region_snapshot_replacement_v1(
        '6b290000-0000-4000-8000-000000000009'::uuid,
        owner_id, project_id, replacement_id,
        '6b270000-0000-4000-8000-000000000007'::uuid, 'contact_void'
      );
    RAISE EXCEPTION 'revoked original replacement was accepted';
  EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  IF (
    SELECT count(*)
    FROM app_private.management_original_region_report_snapshot_replacements
      AS replacement
    WHERE replacement.project_id =
      '6b220000-0000-4000-8000-000000000001'::uuid
  ) <> 1 THEN
    RAISE EXCEPTION 'failed original replacement requests wrote partial history';
  END IF;

  SELECT to_jsonb(snapshot) - ARRAY['snapshot_id', 'release_request_id']
  INTO STRICT snapshot_after
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_id;
  IF snapshot_before IS DISTINCT FROM snapshot_after THEN
    RAISE EXCEPTION 'original replacement changed an existing snapshot';
  END IF;

  -- The append-only audit cannot be rewritten or removed.
  BEGIN
    UPDATE app_private.management_original_region_report_snapshot_replacements
    SET replacement_reason_code = 'contact_void'
    WHERE replacement_request_id =
      '6b290000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'original replacement history update was accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_original_region_report_snapshot_replacements
    WHERE replacement_request_id =
      '6b290000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'original replacement history delete was accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;

  lifecycle_result =
    app_private.read_management_original_region_report_snapshot_lifecycle_v1(
      project_id, '6b2a0000-0000-4000-8000-000000000001'::uuid
    );
  IF lifecycle_result->>'lifecycle_status' IS DISTINCT FROM 'not_found'
    OR lifecycle_result ? 'protected_report'
    OR lifecycle_result ? 'cells'
    OR lifecycle_result ? 'source_tree_context'
  THEN
    RAISE EXCEPTION 'unknown original lifecycle result is not value-free: %',
      lifecycle_result;
  END IF;
END
$fixture_6bn_contract$;

ROLLBACK;
