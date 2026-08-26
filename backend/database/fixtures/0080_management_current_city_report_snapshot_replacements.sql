-- Synthetic rollback fixture for Slice 6CB.
--
-- This fixture uses the public 6CB declaration and lifecycle seams.  It builds
-- two small, valid 6AO current-city snapshots and value-free provenance,
-- then exercises one strict direct edge, replay/idempotency, provenance and tuple
-- negatives, revoke, and immutable history.  Every row created here is rolled
-- back.  No report value is returned by the replacement contract.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6cb20000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6cb20000-0000-4000-8000-000000000002'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id,
  deleted_at
) VALUES
  (
    '6cb21000-0000-4000-8000-000000000001'::uuid,
    'organization', 'Slice 6CB current-city replacement workspace', NULL, NULL
  );

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES
  (
    '6cb22000-0000-4000-8000-000000000001'::uuid,
    '6cb21000-0000-4000-8000-000000000001'::uuid,
    'Slice 6CB current-city replacement project', 'active', false
  ),
  (
    '6cb22000-0000-4000-8000-000000000002'::uuid,
    '6cb21000-0000-4000-8000-000000000001'::uuid,
    'Slice 6CB cross-project negative', 'active', false
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
) VALUES (
  '6cb23000-0000-4000-8000-000000000001'::uuid,
  '6cb21000-0000-4000-8000-000000000001'::uuid,
  '6cb20000-0000-4000-8000-000000000001'::uuid,
  transaction_timestamp() - interval '30 days', NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6cb24000-0000-4000-8000-000000000001'::uuid,
    '6cb23000-0000-4000-8000-000000000001'::uuid,
    '6cb22000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days', NULL
  ),
  (
    '6cb24000-0000-4000-8000-000000000002'::uuid,
    '6cb23000-0000-4000-8000-000000000001'::uuid,
    '6cb22000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6cb25000-0000-4000-8000-000000000001'::uuid,
    '6cb24000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', transaction_timestamp() - interval '30 days', NULL
  ),
  (
    '6cb25000-0000-4000-8000-000000000002'::uuid,
    '6cb24000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports', transaction_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6cb26000-0000-4000-8000-000000000001'::uuid,
  '6cb20000-0000-4000-8000-000000000001'::uuid,
  '6cb22000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', transaction_timestamp() - interval '30 days'
);
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6cb26000-0000-4000-8000-000000000002'::uuid,
  '6cb20000-0000-4000-8000-000000000001'::uuid,
  '6cb22000-0000-4000-8000-000000000002'::uuid,
  0, 'UTC', transaction_timestamp() - interval '30 days'
);

-- A one-city published tree is sufficient for a two-cell current-city report.
-- The target tree release is intentionally older than both future synthetic
-- cutoffs, so the 6AO validator can prove the exact target tuple.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current, published_at_utc,
  content_fingerprint
) VALUES (
  'fixture-6cb-current-v1', 'draft', false, NULL, NULL
);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  (
    'fixture-6cb-country', 'fixture-6cb-current-v1', NULL,
    '6CB Country', 'country'
  ),
  (
    'fixture-6cb-city', 'fixture-6cb-current-v1', 'fixture-6cb-country',
    '6CB City', 'city'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'fixture-6cb-city-boundary', 'fixture-6cb-city',
  'fixture-6cb-current-v1',
  polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6cb-current-v1', true
);

CREATE TEMP TABLE fixture_6cb_source AS
SELECT tree_version, content_fingerprint
FROM app_data.canonical_region_tree_releases
WHERE tree_version = 'fixture-6cb-current-v1';

CREATE TEMP TABLE fixture_6cb_snapshots (
  baseline_snapshot_id uuid,
  replacement_snapshot_id uuid,
  cross_project_snapshot_id uuid,
  drifted_snapshot_id uuid,
  legacy_snapshot_id uuid,
  blocked_snapshot_id uuid,
  privacy_drift_snapshot_id uuid,
  source_scope_drift_snapshot_id uuid,
  period_drift_snapshot_id uuid,
  interest_family_snapshot_id uuid,
  original_region_family_snapshot_id uuid,
  consent_family_snapshot_id uuid,
  selection_evidence_drift_snapshot_id uuid,
  timezone_revision_drift_snapshot_id uuid,
  previous_pointer_drift_snapshot_id uuid,
  source_watermark_regression_snapshot_id uuid,
  same_cutoff_snapshot_id uuid,
  earlier_cutoff_snapshot_id uuid,
  released_at_drift_snapshot_id uuid
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_6cb_additional_candidates (
  snapshot_id uuid PRIMARY KEY,
  release_request_id uuid NOT NULL,
  data_cutoff_utc timestamptz NOT NULL,
  released_at_utc timestamptz NOT NULL,
  previous_snapshot_id uuid,
  source_change_sequence bigint NOT NULL,
  compared_snapshot_id uuid,
  protected_report jsonb NOT NULL
) ON COMMIT DROP;

DO $fixture_6cb_setup$
DECLARE
  project_id constant uuid := '6cb22000-0000-4000-8000-000000000001';
  other_project_id constant uuid := '6cb22000-0000-4000-8000-000000000002';
  owner_id constant uuid := '6cb20000-0000-4000-8000-000000000001';
  report_id constant text :=
    'contact_sessions_by_current_city_two_periods';
  lineage_id constant text :=
    'management-region-report:contact_sessions_by_current_city_two_periods';
  query_fingerprint constant text :=
    'management-report:contact_sessions_by_current_city_two_periods:v1';
  baseline_id constant uuid := '6cb27000-0000-4000-8000-000000000001';
  replacement_id constant uuid := '6cb27000-0000-4000-8000-000000000002';
  cross_project_id constant uuid := '6cb27000-0000-4000-8000-000000000003';
  drifted_id constant uuid := '6cb27000-0000-4000-8000-000000000004';
  legacy_id constant uuid := '6cb27000-0000-4000-8000-000000000005';
  blocked_id constant uuid := '6cb27000-0000-4000-8000-000000000006';
  privacy_drift_id constant uuid := '6cb27000-0000-4000-8000-000000000007';
  source_scope_drift_id constant uuid := '6cb27000-0000-4000-8000-000000000008';
  period_drift_id constant uuid := '6cb27000-0000-4000-8000-000000000009';
  isolated_baseline_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000010';
  interest_family_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000011';
  original_region_family_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000012';
  consent_family_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000013';
  selection_evidence_drift_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000014';
  timezone_revision_drift_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000015';
  previous_pointer_drift_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000016';
  source_watermark_regression_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000017';
  same_cutoff_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000018';
  earlier_cutoff_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000019';
  released_at_drift_id constant uuid :=
    '6cb27000-0000-4000-8000-00000000001a';
  baseline_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000001';
  replacement_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000002';
  cross_project_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000003';
  drifted_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000004';
  legacy_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000005';
  blocked_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000006';
  privacy_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000007';
  source_scope_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000008';
  period_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000009';
  isolated_baseline_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000010';
  interest_family_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000011';
  original_region_family_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000012';
  consent_family_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000013';
  selection_evidence_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000014';
  timezone_revision_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000015';
  previous_pointer_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000016';
  source_watermark_regression_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000017';
  same_cutoff_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000018';
  earlier_cutoff_request_id constant uuid :=
    '6cb28000-0000-4000-8000-000000000019';
  released_at_drift_request_id constant uuid :=
    '6cb28000-0000-4000-8000-00000000001a';
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
  selection_evidence_drift_cutoff constant timestamptz :=
    '2099-01-16 18:00:00+00';
  previous_pointer_drift_cutoff constant timestamptz :=
    '2099-01-16 19:00:00+00';
  source_watermark_regression_cutoff constant timestamptz :=
    '2099-01-16 20:00:00+00';
  timezone_revision_drift_cutoff constant timestamptz :=
    '2099-01-16 17:00:00+00';
  earlier_cutoff constant timestamptz :=
    '2099-01-15 11:00:00+00';
  released_at_drift_cutoff constant timestamptz :=
    '2099-01-16 10:00:00+00';
  baseline_released_at constant timestamptz :=
    '2099-01-15 13:00:00+00';
  replacement_released_at constant timestamptz :=
    '2099-01-16 13:00:00+00';
  isolated_baseline_released_at constant timestamptz :=
    '2099-01-17 13:00:00+00';
  selection_evidence_drift_released_at constant timestamptz :=
    '2099-01-16 19:00:00+00';
  previous_pointer_drift_released_at constant timestamptz :=
    '2099-01-16 20:00:00+00';
  source_watermark_regression_released_at constant timestamptz :=
    '2099-01-16 21:00:00+00';
  timezone_revision_drift_released_at constant timestamptz :=
    '2099-01-16 18:00:00+00';
  same_cutoff_released_at constant timestamptz :=
    '2099-01-15 14:00:00+00';
  earlier_cutoff_released_at constant timestamptz :=
    '2099-01-15 15:00:00+00';
  released_at_drift_released_at constant timestamptz :=
    '2099-01-16 11:00:00+00';
  timezone_revision_requested_at constant timestamptz :=
    '2099-01-16 16:00:00+00';
  timezone_revision_effective constant timestamptz :=
    '2099-01-16 16:30:00+00';
  time_zone_effective timestamptz;
  target_version text;
  target_fingerprint text;
  baseline_target_context jsonb;
  replacement_target_context jsonb;
  drifted_target_context jsonb;
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
      '6cb22000-0000-4000-8000-000000000001'::uuid
    AND version_row.version_number = 1;

  SELECT tree_version, content_fingerprint
  INTO STRICT target_version, target_fingerprint
  FROM fixture_6cb_source;

  baseline_target_context =
    app_private.resolve_management_current_city_target_context_v1(
      baseline_cutoff
    );
  replacement_target_context =
    app_private.resolve_management_current_city_target_context_v1(
      replacement_cutoff
    );
  drifted_target_context =
    app_private.resolve_management_current_city_target_context_v1(
      drifted_cutoff
    );
  IF baseline_target_context->>'result_status' IS DISTINCT FROM 'selected'
    OR replacement_target_context->>'result_status' IS DISTINCT FROM 'selected'
    OR baseline_target_context->>'target_tree_version' IS DISTINCT FROM
      target_version
    OR baseline_target_context->>'target_content_fingerprint' IS DISTINCT FROM
      target_fingerprint
  THEN
    RAISE EXCEPTION '6CB target selection fixture is not available';
  END IF;

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
    'dimension', 'current_city',
    'view_mode', 'current',
    'region_granularity', 'city',
    'query_fingerprint', query_fingerprint,
    'privacy_policy', 'management_current_city_contact_session_privacy_v1',
    'source_scope', 'backend_accepted_active_contacts_current_revision',
    'project_id', project_id,
    'periods', baseline_periods,
    'data_cutoff_utc', baseline_periods->>'data_cutoff_utc',
    'source_change_sequence', 1,
    'target_context', baseline_target_context,
    'result_status', 'completed',
    'cells', jsonb_build_array(
      jsonb_build_object(
        'period_key', 'previous', 'city_id', 'fixture-6cb-city',
        'cell_order', 0, 'value_count', 10, 'privacy_status', 'displayed'
      ),
      jsonb_build_object(
        'period_key', 'current', 'city_id', 'fixture-6cb-city',
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
    replacement_document, '{target_context}', replacement_target_context
  );
  replacement_document = jsonb_set(
    replacement_document, '{source_change_sequence}', '1'::jsonb
  );

  -- A trusted baseline and successor are inserted with the exact immutable
  -- report documents that 6AO would have produced.  This fixture does not
  -- call 6AO's report generator or invent a replacement report.
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

  -- The cross-project row has a valid current-city document whose project is the
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
  -- current-city report in isolation but is not a successor of the baseline.
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current, published_at_utc,
    content_fingerprint
  ) VALUES (
    'fixture-6cb-target-drift-v1', 'draft', false, NULL, NULL
  );
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('fixture-6cb-drift-country', 'fixture-6cb-target-drift-v1', NULL,
      '6CB Drift Country', 'country'),
    ('fixture-6cb-drift-city', 'fixture-6cb-target-drift-v1',
      'fixture-6cb-drift-country', '6CB Drift City', 'city');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES (
    'fixture-6cb-drift-boundary', 'fixture-6cb-drift-city',
    'fixture-6cb-target-drift-v1',
    polygon '((-89.00,41.60),(-88.90,41.60),(-88.90,41.70),(-89.00,41.70))'
  );
  PERFORM app_private.publish_canonical_region_tree_v1(
    'fixture-6cb-target-drift-v1', false
  );
  SELECT content_fingerprint INTO STRICT target_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'fixture-6cb-target-drift-v1';
  drifted_document = jsonb_set(
    replacement_document, '{periods}', drifted_periods
  );
  drifted_document = jsonb_set(
    drifted_document, '{data_cutoff_utc}',
    to_jsonb(drifted_periods->>'data_cutoff_utc')
  );
  drifted_document = jsonb_set(
    drifted_document, '{target_context}',
    jsonb_set(
      jsonb_set(
        drifted_target_context,
        '{target_tree_version}',
        to_jsonb('fixture-6cb-target-drift-v1'::text)
      ),
      '{target_content_fingerprint}',
      to_jsonb(target_fingerprint)
    )
  );
  drifted_document = jsonb_set(
    drifted_document, '{cells}', jsonb_build_array(
      jsonb_build_object(
        'period_key', 'previous',
        'city_id', 'fixture-6cb-drift-city',
        'cell_order', 0,
        'value_count', 10,
        'privacy_status', 'displayed'
      ),
      jsonb_build_object(
        'period_key', 'current',
        'city_id', 'fixture-6cb-drift-city',
        'cell_order', 1,
        'value_count', 10,
        'privacy_status', 'displayed'
      )
    )
  );
  PERFORM set_config('session_replication_role', 'replica', true);
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
  PERFORM set_config('session_replication_role', 'origin', true);

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
  -- snapshot trigger is bypassed only for negative rows; the public 6CB seam
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

  -- Each approved snapshot has independent 6AO release provenance and the
  -- shared request claim family.  The trigger checks the exact tuple and
  -- keeps the audit envelope value-free.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES
    (baseline_request_id, 'current_city_management_report_snapshot_release'),
    (replacement_request_id, 'current_city_management_report_snapshot_release'),
    (drifted_request_id, 'current_city_management_report_snapshot_release'),
    (privacy_drift_request_id,
      'current_city_management_report_snapshot_release'),
    (source_scope_drift_request_id,
      'current_city_management_report_snapshot_release'),
    (period_drift_request_id,
      'current_city_management_report_snapshot_release');

  baseline_audit = jsonb_build_object(
    'release_contract_id', 'current_city_management_report_snapshot_release_v1',
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
    'target_tree_version', 'fixture-6cb-current-v1',
    'target_content_fingerprint', (SELECT content_fingerprint
      FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-6cb-current-v1'),
    'compared_snapshot_id', NULL,
    'released_snapshot_id', baseline_id,
    'result_status', 'approved_baseline',
    'reason_codes', '[]'::jsonb
  );
  replacement_audit = jsonb_build_object(
    'release_contract_id', 'current_city_management_report_snapshot_release_v1',
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
    'target_tree_version', 'fixture-6cb-current-v1',
    'target_content_fingerprint', (SELECT content_fingerprint
      FROM app_data.canonical_region_tree_releases
      WHERE tree_version = 'fixture-6cb-current-v1'),
    'compared_snapshot_id', baseline_id,
    'released_snapshot_id', replacement_id,
    'result_status', 'approved',
    'reason_codes', '[]'::jsonb
  );

  INSERT INTO app_private.management_current_city_report_release_attempts (
    release_request_id, requested_by_app_user_id,
    organization_workspace_id, organization_membership_id,
    project_membership_id, capability_grant_id, capability_id,
    authorization_reference_at_utc, project_id,
    reporting_time_zone_version_number, reporting_time_zone,
    reporting_time_zone_effective_from_utc, data_cutoff_utc,
    release_lineage_id, report_id, report_version, query_fingerprint,
    target_tree_version, target_content_fingerprint,
    compared_snapshot_id, released_snapshot_id, result_status,
    reason_codes, result_document
  ) VALUES
    (
      baseline_request_id, owner_id,
      '6cb21000-0000-4000-8000-000000000001'::uuid,
      '6cb23000-0000-4000-8000-000000000001'::uuid,
      '6cb24000-0000-4000-8000-000000000001'::uuid,
      '6cb25000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', baseline_cutoff, project_id, 1, 'UTC',
      time_zone_effective, baseline_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6cb-current-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6cb-current-v1'), NULL, baseline_id,
      'approved_baseline', '[]'::jsonb,
      baseline_audit
    ),
    (
      replacement_request_id, owner_id,
      '6cb21000-0000-4000-8000-000000000001'::uuid,
      '6cb23000-0000-4000-8000-000000000001'::uuid,
      '6cb24000-0000-4000-8000-000000000001'::uuid,
      '6cb25000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', replacement_cutoff, project_id, 1, 'UTC',
      time_zone_effective, replacement_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6cb-current-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6cb-current-v1'), baseline_id,
      replacement_id, 'approved', '[]'::jsonb,
      replacement_audit
    );

  -- Synthetic approved provenance for the four tuple-drift rows ensures the
  -- public declaration reaches its cross-snapshot comparisons.  The fixture
  -- bypasses attempt validation only to isolate each malformed tuple.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_private.management_current_city_report_release_attempts (
    release_request_id, requested_by_app_user_id,
    organization_workspace_id, organization_membership_id,
    project_membership_id, capability_grant_id, capability_id,
    authorization_reference_at_utc, project_id,
    reporting_time_zone_version_number, reporting_time_zone,
    reporting_time_zone_effective_from_utc, data_cutoff_utc,
    release_lineage_id, report_id, report_version, query_fingerprint,
    target_tree_version, target_content_fingerprint,
    compared_snapshot_id, released_snapshot_id, result_status,
    reason_codes, result_document
  ) VALUES
    (
      drifted_request_id, owner_id,
      '6cb21000-0000-4000-8000-000000000001'::uuid,
      '6cb23000-0000-4000-8000-000000000001'::uuid,
      '6cb24000-0000-4000-8000-000000000001'::uuid,
      '6cb25000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', drifted_cutoff, project_id, 1, 'UTC',
      time_zone_effective, drifted_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6cb-target-drift-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6cb-target-drift-v1'), replacement_id,
      drifted_id, 'approved', '[]'::jsonb, '{}'::jsonb
    ),
    (
      privacy_drift_request_id, owner_id,
      '6cb21000-0000-4000-8000-000000000001'::uuid,
      '6cb23000-0000-4000-8000-000000000001'::uuid,
      '6cb24000-0000-4000-8000-000000000001'::uuid,
      '6cb25000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', privacy_drift_cutoff, project_id, 1, 'UTC',
      time_zone_effective, privacy_drift_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6cb-current-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6cb-current-v1'), replacement_id,
      privacy_drift_id, 'approved', '[]'::jsonb, '{}'::jsonb
    ),
    (
      source_scope_drift_request_id, owner_id,
      '6cb21000-0000-4000-8000-000000000001'::uuid,
      '6cb23000-0000-4000-8000-000000000001'::uuid,
      '6cb24000-0000-4000-8000-000000000001'::uuid,
      '6cb25000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', source_scope_drift_cutoff, project_id, 1,
      'UTC', time_zone_effective, source_scope_drift_cutoff, lineage_id,
      report_id, 1, query_fingerprint, 'fixture-6cb-current-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6cb-current-v1'), replacement_id,
      source_scope_drift_id, 'approved', '[]'::jsonb, '{}'::jsonb
    ),
    (
      period_drift_request_id, owner_id,
      '6cb21000-0000-4000-8000-000000000001'::uuid,
      '6cb23000-0000-4000-8000-000000000001'::uuid,
      '6cb24000-0000-4000-8000-000000000001'::uuid,
      '6cb25000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', period_drift_cutoff, project_id, 1, 'UTC',
      time_zone_effective, period_drift_cutoff, lineage_id, report_id, 1,
      query_fingerprint, 'fixture-6cb-current-v1',
      (SELECT content_fingerprint FROM app_data.canonical_region_tree_releases
       WHERE tree_version = 'fixture-6cb-current-v1'), replacement_id,
      period_drift_id, 'approved', '[]'::jsonb, '{}'::jsonb
    );
  PERFORM set_config('session_replication_role', 'origin', true);

  -- Keep the time-order negatives on an untouched local head.  The primary
  -- baseline is already superseded below, so using it for same/earlier and
  -- released-at checks would only prove the stale-head guard.  These rows are
  -- small copies of the value-valid current-city document; their release
  -- attempts and claims are synthetic 0057 provenance only.
  INSERT INTO fixture_6cb_additional_candidates (
    snapshot_id, release_request_id, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, compared_snapshot_id,
    protected_report
  ) VALUES
    (
      isolated_baseline_id, isolated_baseline_request_id, baseline_cutoff,
      isolated_baseline_released_at, NULL, 1, NULL, baseline_document
    ),
    (
      selection_evidence_drift_id, selection_evidence_drift_request_id,
      selection_evidence_drift_cutoff,
      selection_evidence_drift_released_at, baseline_id, 1, baseline_id,
      baseline_document
    ),
    (
      timezone_revision_drift_id, timezone_revision_drift_request_id,
      timezone_revision_drift_cutoff, timezone_revision_drift_released_at,
      baseline_id, 1, baseline_id, baseline_document
    ),
    (
      previous_pointer_drift_id, previous_pointer_drift_request_id,
      previous_pointer_drift_cutoff, previous_pointer_drift_released_at,
      replacement_id, 1, baseline_id, baseline_document
    ),
    (
      source_watermark_regression_id, source_watermark_regression_request_id,
      source_watermark_regression_cutoff,
      source_watermark_regression_released_at, baseline_id, 0, baseline_id,
      baseline_document
    ),
    (
      same_cutoff_id, same_cutoff_request_id, baseline_cutoff,
      same_cutoff_released_at, isolated_baseline_id, 1,
      isolated_baseline_id, baseline_document
    ),
    (
      earlier_cutoff_id, earlier_cutoff_request_id, earlier_cutoff,
      earlier_cutoff_released_at, isolated_baseline_id, 1,
      isolated_baseline_id, baseline_document
    ),
    (
      released_at_drift_id, released_at_drift_request_id,
      released_at_drift_cutoff, released_at_drift_released_at,
      isolated_baseline_id, 1, isolated_baseline_id, baseline_document
    );

  UPDATE fixture_6cb_additional_candidates AS candidate
  SET protected_report = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          baseline_document,
          '{periods}', resolved.periods
        ),
        '{data_cutoff_utc}',
        to_jsonb(resolved.periods->>'data_cutoff_utc')
      ),
      '{target_context}', resolved.target_context
    ),
    '{source_change_sequence}', to_jsonb(candidate.source_change_sequence)
  )
  FROM (
    SELECT candidate_row.snapshot_id,
      app_private.resolve_management_report_periods_v1(
        'UTC', candidate_row.data_cutoff_utc
      ) AS periods,
      app_private.resolve_management_current_city_target_context_v1(
        candidate_row.data_cutoff_utc
      ) AS target_context
    FROM fixture_6cb_additional_candidates AS candidate_row
  ) AS resolved
  WHERE candidate.snapshot_id = resolved.snapshot_id;

  -- Make one candidate fail only on selection evidence.  It remains a
  -- syntactically valid string, but no longer matches the immutable 0057
  -- selection event and differs from the superseded target context.
  UPDATE fixture_6cb_additional_candidates
  SET protected_report = jsonb_set(
    protected_report,
    '{target_context,selection_evidence_at_utc}',
    to_jsonb('2099-01-01T00:00:00.000Z'::text)
  )
  WHERE snapshot_id = selection_evidence_drift_id;

  -- The family-shaped rows are deliberately minimal foreign snapshots.  They
  -- are not given current-city claims or attempts: the current-city seam must
  -- reject the report identity before it can create a replacement claim.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES
    (
      interest_family_id, interest_family_request_id, owner_id, project_id,
      'management-interest-report:contact_sessions_by_interest_level_two_periods',
      'contact_sessions_by_interest_level_two_periods', 1,
      'management-report:contact_sessions_by_interest_level_two_periods:v1',
      'UTC', baseline_cutoff, baseline_released_at, NULL, 1,
      jsonb_build_object(
        'report_id', 'contact_sessions_by_interest_level_two_periods',
        'project_id', project_id
      )
    ),
    (
      original_region_family_id, original_region_family_request_id, owner_id,
      project_id,
      'management-original-region-report:contact_sessions_by_original_region_two_periods',
      'contact_sessions_by_original_region_two_periods', 1,
      'management-report:contact_sessions_by_original_region_two_periods:v1',
      'UTC', baseline_cutoff, baseline_released_at, NULL, 1,
      jsonb_build_object(
        'report_id', 'contact_sessions_by_original_region_two_periods',
        'project_id', project_id
      )
    ),
    (
      consent_family_id, consent_family_request_id, owner_id, project_id,
      'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
      'contact_target_follow_up_consent_ratio_two_periods', 1,
      'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
      'UTC', baseline_cutoff, baseline_released_at, NULL, 1,
      jsonb_build_object(
        'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
        'project_id', project_id
      )
    );

  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  )
  SELECT candidate.snapshot_id, candidate.release_request_id, owner_id,
    project_id, lineage_id, report_id, 1, query_fingerprint, 'UTC',
    candidate.data_cutoff_utc, candidate.released_at_utc,
    candidate.previous_snapshot_id, candidate.source_change_sequence,
    candidate.protected_report
  FROM fixture_6cb_additional_candidates AS candidate
  WHERE candidate.snapshot_id <> isolated_baseline_id;

  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    isolated_baseline_id, isolated_baseline_request_id, owner_id, project_id,
    lineage_id, report_id, 1, query_fingerprint, 'UTC', baseline_cutoff,
    isolated_baseline_released_at, NULL, 1, baseline_document
  );

  PERFORM set_config('session_replication_role', 'origin', true);

  -- Claims and approved attempts make the current-city candidates trusted
  -- enough to reach their intended cross-snapshot guard.  The replacement
  -- request UUIDs are intentionally not claimed here; every failed call below
  -- must leave no replacement-family claim behind.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  )
  SELECT candidate.release_request_id,
    'current_city_management_report_snapshot_release'
  FROM fixture_6cb_additional_candidates AS candidate
  WHERE candidate.snapshot_id <> isolated_baseline_id;

  INSERT INTO app_private.management_current_city_report_release_attempts (
    release_request_id, requested_by_app_user_id,
    organization_workspace_id, organization_membership_id,
    project_membership_id, capability_grant_id, capability_id,
    authorization_reference_at_utc, project_id,
    reporting_time_zone_version_number, reporting_time_zone,
    reporting_time_zone_effective_from_utc, data_cutoff_utc,
    release_lineage_id, report_id, report_version, query_fingerprint,
    target_tree_version, target_content_fingerprint,
    compared_snapshot_id, released_snapshot_id, result_status,
    reason_codes, result_document
  )
  SELECT candidate.release_request_id, owner_id,
    '6cb21000-0000-4000-8000-000000000001'::uuid,
    '6cb23000-0000-4000-8000-000000000001'::uuid,
    '6cb24000-0000-4000-8000-000000000001'::uuid,
    '6cb25000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', candidate.data_cutoff_utc, project_id,
    1, 'UTC', time_zone_effective, candidate.data_cutoff_utc, lineage_id,
    report_id, 1, query_fingerprint,
    candidate.protected_report->'target_context'->>'target_tree_version',
    candidate.protected_report->'target_context'->>'target_content_fingerprint',
    candidate.compared_snapshot_id, candidate.snapshot_id, 'approved',
    '[]'::jsonb, '{}'::jsonb
  FROM fixture_6cb_additional_candidates AS candidate
  WHERE candidate.snapshot_id <> isolated_baseline_id;

  -- A synthetic later time-zone revision is placed inside the same ISO-week
  -- window as the candidate.  The trigger is bypassed only for this negative
  -- row so the valid public configuration boundary is not part of the case;
  -- 0080 must still reject a 0057 attempt pinned to version 1 after revision 2
  -- became effective.
  INSERT INTO app_private.project_reporting_time_zone_versions (
    project_id, version_number, expected_version, change_request_id,
    requested_by_app_user_id, reporting_time_zone, period_boundary_id,
    effective_from_utc, requested_at_utc
  ) VALUES (
    project_id, 2, 1, '6cb2b000-0000-4000-8000-000000000001'::uuid,
    owner_id, 'America/Chicago', 'iso_week_monday_v1',
    timezone_revision_effective, timezone_revision_requested_at
  );

  -- The shared 0057 claim/attempt pair for the isolated baseline is inserted
  -- after its snapshot so the provenance helper can resolve it.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    isolated_baseline_request_id,
    'current_city_management_report_snapshot_release'
  );

  INSERT INTO app_private.management_current_city_report_release_attempts (
    release_request_id, requested_by_app_user_id,
    organization_workspace_id, organization_membership_id,
    project_membership_id, capability_grant_id, capability_id,
    authorization_reference_at_utc, project_id,
    reporting_time_zone_version_number, reporting_time_zone,
    reporting_time_zone_effective_from_utc, data_cutoff_utc,
    release_lineage_id, report_id, report_version, query_fingerprint,
    target_tree_version, target_content_fingerprint,
    compared_snapshot_id, released_snapshot_id, result_status,
    reason_codes, result_document
  ) VALUES (
    isolated_baseline_request_id, owner_id,
    '6cb21000-0000-4000-8000-000000000001'::uuid,
    '6cb23000-0000-4000-8000-000000000001'::uuid,
    '6cb24000-0000-4000-8000-000000000001'::uuid,
    '6cb25000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', baseline_cutoff, project_id,
    1, 'UTC', time_zone_effective, baseline_cutoff, lineage_id, report_id, 1,
    query_fingerprint,
    baseline_document->'target_context'->>'target_tree_version',
    baseline_document->'target_context'->>'target_content_fingerprint',
    NULL, isolated_baseline_id, 'approved_baseline', '[]'::jsonb, '{}'::jsonb
  );
  PERFORM set_config('session_replication_role', 'origin', true);

  INSERT INTO fixture_6cb_snapshots (
    baseline_snapshot_id, replacement_snapshot_id,
    cross_project_snapshot_id, drifted_snapshot_id,
    legacy_snapshot_id, blocked_snapshot_id,
    privacy_drift_snapshot_id, source_scope_drift_snapshot_id,
    period_drift_snapshot_id, interest_family_snapshot_id,
    original_region_family_snapshot_id, consent_family_snapshot_id,
    selection_evidence_drift_snapshot_id,
    timezone_revision_drift_snapshot_id, previous_pointer_drift_snapshot_id,
    source_watermark_regression_snapshot_id, same_cutoff_snapshot_id,
    earlier_cutoff_snapshot_id, released_at_drift_snapshot_id
  ) VALUES (baseline_id, replacement_id, cross_project_id, drifted_id,
    legacy_id, blocked_id, privacy_drift_id, source_scope_drift_id,
    period_drift_id, interest_family_id, original_region_family_id,
    consent_family_id, selection_evidence_drift_id,
    timezone_revision_drift_id, previous_pointer_drift_id,
    source_watermark_regression_id, same_cutoff_id, earlier_cutoff_id,
    released_at_drift_id);
END
$fixture_6cb_setup$;

DO $fixture_6cb_contract$
DECLARE
  project_id constant uuid := '6cb22000-0000-4000-8000-000000000001';
  owner_id constant uuid := '6cb20000-0000-4000-8000-000000000001';
  baseline_id uuid;
  replacement_id uuid;
  cross_project_id uuid;
  drifted_id uuid;
  legacy_id uuid;
  blocked_id uuid;
  privacy_drift_id uuid;
  source_scope_drift_id uuid;
  period_drift_id uuid;
  interest_family_id uuid;
  original_region_family_id uuid;
  consent_family_id uuid;
  selection_evidence_drift_id uuid;
  timezone_revision_drift_id uuid;
  previous_pointer_drift_id uuid;
  source_watermark_regression_id uuid;
  same_cutoff_id uuid;
  earlier_cutoff_id uuid;
  released_at_drift_id uuid;
  isolated_baseline_id constant uuid :=
    '6cb27000-0000-4000-8000-000000000010';
  declaration_result jsonb;
  replay_result jsonb;
  lifecycle_result jsonb;
  replacement_count bigint;
  snapshot_before jsonb;
  snapshot_after jsonb;
  replacement_snapshot_before jsonb;
  replacement_snapshot_after jsonb;
BEGIN
  SELECT baseline_snapshot_id, replacement_snapshot_id,
    cross_project_snapshot_id, drifted_snapshot_id,
    legacy_snapshot_id, blocked_snapshot_id,
    privacy_drift_snapshot_id, source_scope_drift_snapshot_id,
    period_drift_snapshot_id, interest_family_snapshot_id,
    original_region_family_snapshot_id, consent_family_snapshot_id,
    selection_evidence_drift_snapshot_id,
    timezone_revision_drift_snapshot_id, previous_pointer_drift_snapshot_id,
    source_watermark_regression_snapshot_id, same_cutoff_snapshot_id,
    earlier_cutoff_snapshot_id, released_at_drift_snapshot_id
  INTO STRICT baseline_id, replacement_id, cross_project_id, drifted_id,
    legacy_id, blocked_id, privacy_drift_id, source_scope_drift_id,
    period_drift_id, interest_family_id, original_region_family_id,
    consent_family_id, selection_evidence_drift_id,
    timezone_revision_drift_id, previous_pointer_drift_id,
    source_watermark_regression_id, same_cutoff_id, earlier_cutoff_id,
    released_at_drift_id
  FROM fixture_6cb_snapshots;

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
        OR (
          (old_snapshot.protected_report->'target_context') -
            'data_cutoff_utc'::text
        ) IS DISTINCT FROM (
          (new_snapshot.protected_report->'target_context') -
            'data_cutoff_utc'::text
        )
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
      'current-city replacement cross-snapshot contract is not stable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_release_attempts
      AS old_attempt
    JOIN app_private.management_current_city_report_release_attempts
      AS new_attempt
      ON new_attempt.release_request_id =
        '6cb28000-0000-4000-8000-000000000002'::uuid
    WHERE old_attempt.release_request_id =
        '6cb28000-0000-4000-8000-000000000001'::uuid
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
        OR old_attempt.target_tree_version IS DISTINCT FROM
          new_attempt.target_tree_version
        OR old_attempt.target_content_fingerprint IS DISTINCT FROM
          new_attempt.target_content_fingerprint
        OR old_attempt.authorization_reference_at_utc >=
          new_attempt.authorization_reference_at_utc
      )
  ) THEN
    RAISE EXCEPTION
      'current-city replacement release provenance contract is not stable';
  END IF;

  SELECT to_jsonb(snapshot) - ARRAY['snapshot_id', 'release_request_id']
  INTO STRICT snapshot_before
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_id;
  SELECT snapshot.protected_report
  INTO STRICT replacement_snapshot_before
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = replacement_id;

  IF NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      drifted_id,
      project_id
    )
    OR NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      privacy_drift_id,
      project_id
    )
    OR NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      source_scope_drift_id,
      project_id
    )
    OR NOT app_private.management_current_city_snapshot_has_trusted_provenance_v1(
      period_drift_id,
      project_id
    )
  THEN
    RAISE EXCEPTION
      'tuple-drift negatives do not reach cross-snapshot validation: target=%, privacy=%, source=%, period=%',
      app_private.management_current_city_snapshot_has_trusted_provenance_v1(
        drifted_id, project_id
      ),
      app_private.management_current_city_snapshot_has_trusted_provenance_v1(
        privacy_drift_id, project_id
      ),
      app_private.management_current_city_snapshot_has_trusted_provenance_v1(
        source_scope_drift_id, project_id
      ),
      app_private.management_current_city_snapshot_has_trusted_provenance_v1(
        period_drift_id, project_id
      );
  END IF;

  -- A release request owns its UUID before a replacement can claim it.
  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb28000-0000-4000-8000-000000000001'::uuid,
        owner_id, project_id, baseline_id, replacement_id, 'contact_revision'
      );
    RAISE EXCEPTION 'release request UUID was reused for replacement';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  declaration_result =
    app_private.declare_management_current_city_snapshot_replacement_v1(
      '6cb29000-0000-4000-8000-000000000001'::uuid,
      owner_id, project_id, baseline_id, replacement_id, 'contact_revision'
    );
  IF declaration_result->>'replacement_contract_id' IS DISTINCT FROM
      'current_city_management_report_snapshot_replacement_v1'
    OR declaration_result->>'result_status' IS DISTINCT FROM 'completed'
    OR declaration_result->>'superseded_snapshot_id' IS DISTINCT FROM baseline_id::text
    OR declaration_result->>'replacement_snapshot_id' IS DISTINCT FROM replacement_id::text
    OR declaration_result->>'replacement_reason_code' IS DISTINCT FROM 'contact_revision'
    OR declaration_result ? 'protected_report'
    OR declaration_result ? 'result_document'
    OR declaration_result::text ~
      '(cells|value_count|contributor|contact_id|place_name|target_context)'
  THEN
    RAISE EXCEPTION 'valid current-city replacement result is not value-free: %',
      declaration_result;
  END IF;

  SELECT count(*) INTO replacement_count
  FROM app_private.management_current_city_report_snapshot_replacements;
  replay_result =
    app_private.declare_management_current_city_snapshot_replacement_v1(
      '6cb29000-0000-4000-8000-000000000001'::uuid,
      owner_id, project_id, baseline_id, replacement_id, 'contact_revision'
    );
  IF replay_result <> declaration_result
    OR (SELECT count(*)
        FROM app_private.management_current_city_report_snapshot_replacements)
      <> replacement_count
  THEN
    RAISE EXCEPTION 'identical current-city replacement retry was not idempotent';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_request_claims AS claim
    WHERE claim.release_request_id =
        '6cb29000-0000-4000-8000-000000000001'::uuid
      AND claim.release_family_id =
        'current_city_management_report_snapshot_replacement'
  ) THEN
    RAISE EXCEPTION 'replacement request did not claim its global UUID';
  END IF;

  -- The replacement claim also prevents a later 6AO release from reusing the
  -- same UUID.  Both contracts use the common request advisory lock.
  BEGIN
    PERFORM app_private.release_management_current_city_report_snapshot_v1(
      '6cb29000-0000-4000-8000-000000000001'::uuid,
      owner_id,
      project_id,
      'contact_sessions_by_current_city_two_periods',
      1
    );
    RAISE EXCEPTION 'replacement request UUID was reused for release';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  lifecycle_result =
    app_private.read_management_current_city_report_snapshot_lifecycle_v1(
      project_id, baseline_id
    );
  IF lifecycle_result <> jsonb_build_object(
      'lifecycle_contract_id',
        'current_city_management_report_snapshot_lifecycle_v1',
      'project_id', project_id, 'snapshot_id', baseline_id,
      'lifecycle_status', 'superseded',
      'replacement_snapshot_id', replacement_id
    )
  THEN
    RAISE EXCEPTION 'superseded current-city lifecycle result is incorrect: %',
      lifecycle_result;
  END IF;

  lifecycle_result =
    app_private.read_management_current_city_report_snapshot_lifecycle_v1(
      project_id, replacement_id
    );
  IF lifecycle_result->>'lifecycle_status' IS DISTINCT FROM 'active'
    OR lifecycle_result->>'replacement_snapshot_id' IS NOT NULL
    OR lifecycle_result ? 'protected_report'
  THEN
    RAISE EXCEPTION 'active current-city lifecycle result is incorrect: %',
      lifecycle_result;
  END IF;

  -- A request UUID is bound to its complete canonical payload.
  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000001'::uuid,
        owner_id, project_id, baseline_id, replacement_id, 'contact_void'
      );
    RAISE EXCEPTION 'current-city replacement request payload drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-00000000000d'::uuid,
        owner_id, project_id, replacement_id, drifted_id, 'manual_override'
      );
    RAISE EXCEPTION 'unknown current-city replacement reason was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- Old heads cannot branch; self, reverse, cross-project, source-tree drift,
  -- blocked provenance, legacy family and an unknown ID all fail closed.
  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000002'::uuid,
        owner_id, project_id, baseline_id, baseline_id, 'contact_void'
      );
    RAISE EXCEPTION 'current-city self replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000003'::uuid,
        owner_id, project_id, replacement_id, baseline_id, 'late_accepted_data'
      );
    RAISE EXCEPTION 'current-city reverse replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000004'::uuid,
        owner_id, project_id, replacement_id, cross_project_id, 'contact_void'
      );
    RAISE EXCEPTION 'current-city cross-project replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000005'::uuid,
        owner_id, project_id, replacement_id, drifted_id, 'contact_revision'
      );
    RAISE EXCEPTION 'current-city target-tree drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-00000000000a'::uuid,
        owner_id, project_id, replacement_id, privacy_drift_id, 'contact_revision'
      );
    RAISE EXCEPTION 'current-city privacy drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-00000000000b'::uuid,
        owner_id, project_id, replacement_id,
        source_scope_drift_id, 'contact_revision'
      );
    RAISE EXCEPTION 'current-city source scope drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-00000000000c'::uuid,
        owner_id, project_id, replacement_id, period_drift_id, 'contact_revision'
      );
    RAISE EXCEPTION 'current-city period drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000006'::uuid,
        owner_id, project_id, replacement_id, blocked_id, 'contact_revision'
      );
    RAISE EXCEPTION 'current-city blocked provenance was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000007'::uuid,
        owner_id, project_id, replacement_id, legacy_id, 'contact_revision'
      );
    RAISE EXCEPTION 'legacy family replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000008'::uuid,
        owner_id, project_id, replacement_id,
        '6cb2a000-0000-4000-8000-000000000001'::uuid, 'contact_revision'
      );
    RAISE EXCEPTION 'unknown current-city replacement snapshot was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  -- Explicit neighboring-family negatives must fail before a foreign report
  -- can claim the current-city replacement family.
  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000011'::uuid,
        owner_id, project_id, replacement_id, interest_family_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'interest-family replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000012'::uuid,
        owner_id, project_id, replacement_id, original_region_family_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'original-region-family replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000013'::uuid,
        owner_id, project_id, replacement_id, consent_family_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'follow-up-consent-family replacement was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  -- Each following candidate isolates one current-city provenance or ordering
  -- invariant.  The time-order cases use the untouched local baseline below,
  -- so they cannot be satisfied by an existing stale-head failure.
  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000014'::uuid,
        owner_id, project_id, baseline_id, selection_evidence_drift_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'selection-evidence drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000015'::uuid,
        owner_id, project_id, baseline_id, timezone_revision_drift_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'time-zone revision drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000016'::uuid,
        owner_id, project_id, baseline_id, previous_pointer_drift_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'previous-pointer drift was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000017'::uuid,
        owner_id, project_id, baseline_id, source_watermark_regression_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'source-watermark regression was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000018'::uuid,
        owner_id, project_id, isolated_baseline_id, same_cutoff_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'same cutoff was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000019'::uuid,
        owner_id, project_id, isolated_baseline_id, earlier_cutoff_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'earlier cutoff was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-00000000001a'::uuid,
        owner_id, project_id, isolated_baseline_id, released_at_drift_id,
        'contact_revision'
      );
    RAISE EXCEPTION 'released-at reversal was accepted';
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  -- A revoked capability is rechecked after the request/lineage locks.  No
  -- replacement row may be written when authorization is inactive.
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '6cb25000-0000-4000-8000-000000000001'::uuid;
  BEGIN
    PERFORM
      app_private.declare_management_current_city_snapshot_replacement_v1(
        '6cb29000-0000-4000-8000-000000000009'::uuid,
        owner_id, project_id, replacement_id,
        '6cb27000-0000-4000-8000-000000000007'::uuid, 'contact_void'
      );
    RAISE EXCEPTION 'revoked current-city replacement was accepted';
  EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '22023' OR SQLSTATE '55000' THEN NULL;
  END;

  IF (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_replacements
      AS replacement
    WHERE replacement.project_id =
      '6cb22000-0000-4000-8000-000000000001'::uuid
  ) <> 1 THEN
    RAISE EXCEPTION 'failed current-city replacement requests wrote partial history';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_snapshot_replacements
      AS replacement
    WHERE replacement.replacement_request_id IN (
      '6cb29000-0000-4000-8000-000000000011'::uuid,
      '6cb29000-0000-4000-8000-000000000012'::uuid,
      '6cb29000-0000-4000-8000-000000000013'::uuid,
      '6cb29000-0000-4000-8000-000000000014'::uuid,
      '6cb29000-0000-4000-8000-000000000015'::uuid,
      '6cb29000-0000-4000-8000-000000000016'::uuid,
      '6cb29000-0000-4000-8000-000000000017'::uuid,
      '6cb29000-0000-4000-8000-000000000018'::uuid,
      '6cb29000-0000-4000-8000-000000000019'::uuid,
      '6cb29000-0000-4000-8000-00000000001a'::uuid
    )
  ) OR EXISTS (
    SELECT 1
    FROM app_private.management_report_release_request_claims AS claim
    WHERE claim.release_request_id IN (
      '6cb29000-0000-4000-8000-000000000011'::uuid,
      '6cb29000-0000-4000-8000-000000000012'::uuid,
      '6cb29000-0000-4000-8000-000000000013'::uuid,
      '6cb29000-0000-4000-8000-000000000014'::uuid,
      '6cb29000-0000-4000-8000-000000000015'::uuid,
      '6cb29000-0000-4000-8000-000000000016'::uuid,
      '6cb29000-0000-4000-8000-000000000017'::uuid,
      '6cb29000-0000-4000-8000-000000000018'::uuid,
      '6cb29000-0000-4000-8000-000000000019'::uuid,
      '6cb29000-0000-4000-8000-00000000001a'::uuid
    )
  ) THEN
    RAISE EXCEPTION
      'failed current-city replacement requests left a row or orphan claim';
  END IF;

  SELECT to_jsonb(snapshot) - ARRAY['snapshot_id', 'release_request_id']
  INTO STRICT snapshot_after
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_id;
  IF snapshot_before IS DISTINCT FROM snapshot_after THEN
    RAISE EXCEPTION 'current-city replacement changed an existing snapshot';
  END IF;
  SELECT snapshot.protected_report
  INTO STRICT replacement_snapshot_after
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = replacement_id;
  IF replacement_snapshot_before IS DISTINCT FROM replacement_snapshot_after THEN
    RAISE EXCEPTION 'current-city replacement changed the successor snapshot';
  END IF;

  -- A privileged historical row that bypassed the 0057 insert trigger still
  -- cannot become trusted when its protected document is detached from the
  -- snapshot metadata.  Restore the bytes after each synthetic corruption.
  FOR replacement_snapshot_after IN
    SELECT corrupted_document
    FROM (VALUES
      (
        jsonb_set(
          replacement_snapshot_before,
          '{project_id}',
          to_jsonb('6cb22000-0000-4000-8000-000000000002'::uuid)
        )
      ),
      (snapshot_before->'protected_report'),
      (
        jsonb_set(
          replacement_snapshot_before,
          '{source_change_sequence}',
          to_jsonb(
            (replacement_snapshot_before->>'source_change_sequence')::bigint
              + 1
          )
        )
      )
    ) AS corrupted(corrupted_document)
  LOOP
    PERFORM set_config('session_replication_role', 'replica', true);
    UPDATE app_private.management_report_snapshots
    SET protected_report = replacement_snapshot_after
    WHERE snapshot_id = replacement_id;
    PERFORM set_config('session_replication_role', 'origin', true);

    IF app_private.management_current_city_snapshot_has_trusted_provenance_v1(
        replacement_id,
        project_id
      )
    THEN
      RAISE EXCEPTION
        'document-to-row metadata drift retained trusted provenance';
    END IF;

    PERFORM set_config('session_replication_role', 'replica', true);
    UPDATE app_private.management_report_snapshots
    SET protected_report = replacement_snapshot_before
    WHERE snapshot_id = replacement_id;
    PERFORM set_config('session_replication_role', 'origin', true);
  END LOOP;

  -- The append-only audit cannot be rewritten or removed.
  BEGIN
    UPDATE app_private.management_current_city_report_snapshot_replacements
    SET replacement_reason_code = 'contact_void'
    WHERE replacement_request_id =
      '6cb29000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'current-city replacement history update was accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_current_city_report_snapshot_replacements
    WHERE replacement_request_id =
      '6cb29000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'current-city replacement history delete was accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
  END;

  lifecycle_result =
    app_private.read_management_current_city_report_snapshot_lifecycle_v1(
      project_id, '6cb2a000-0000-4000-8000-000000000001'::uuid
    );
  IF lifecycle_result->>'lifecycle_status' IS DISTINCT FROM 'not_found'
    OR lifecycle_result ? 'protected_report'
    OR lifecycle_result ? 'cells'
    OR lifecycle_result ? 'target_context'
  THEN
    RAISE EXCEPTION 'unknown current-city lifecycle result is not value-free: %',
      lifecycle_result;
  END IF;
END
$fixture_6cb_contract$;

ROLLBACK;
