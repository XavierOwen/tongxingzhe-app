-- Synthetic fixture for the 6AQ runtime bridge.
--
-- The protected current-city document is assembled through the same 0057
-- validator and immutable snapshot tables as production. The bridge is then
-- called as tongxingzhe_runtime. All rows are rolled back.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('af110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('af110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('af110000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    'af1e0000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-current-city.synthetic/auth/v1',
    'active-reader',
    'af110000-0000-4000-8000-000000000002'::uuid
  ),
  (
    'af1e0000-0000-4000-8000-000000000002'::uuid,
    'https://runtime-current-city.synthetic/auth/v1',
    'inactive-reader',
    'af110000-0000-4000-8000-000000000003'::uuid
  ),
  (
    'af1e0000-0000-4000-8000-000000000003'::uuid,
    ' https://runtime-current-city.synthetic/auth/v1 ',
    'spaced-reader',
    'af110000-0000-4000-8000-000000000002'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  deleted_at
) VALUES (
  'af120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AQ runtime current-city workspace',
  NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    'af130000-0000-4000-8000-000000000001'::uuid,
    'af120000-0000-4000-8000-000000000001'::uuid,
    '6AQ runtime current-city project'
  ),
  (
    'af130000-0000-4000-8000-000000000002'::uuid,
    'af120000-0000-4000-8000-000000000001'::uuid,
    '6AQ other project'
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
    'af160000-0000-4000-8000-000000000001'::uuid,
    'af120000-0000-4000-8000-000000000001'::uuid,
    'af110000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    'af160000-0000-4000-8000-000000000002'::uuid,
    'af120000-0000-4000-8000-000000000001'::uuid,
    'af110000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    'af160000-0000-4000-8000-000000000003'::uuid,
    'af120000-0000-4000-8000-000000000001'::uuid,
    'af110000-0000-4000-8000-000000000003'::uuid,
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
    'af170000-0000-4000-8000-000000000001'::uuid,
    'af160000-0000-4000-8000-000000000001'::uuid,
    'af130000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    'af170000-0000-4000-8000-000000000002'::uuid,
    'af160000-0000-4000-8000-000000000002'::uuid,
    'af130000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    'af170000-0000-4000-8000-000000000003'::uuid,
    'af160000-0000-4000-8000-000000000003'::uuid,
    'af130000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
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
    'af180000-0000-4000-8000-000000000001'::uuid,
    'af170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    'af180000-0000-4000-8000-000000000002'::uuid,
    'af170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    'af180000-0000-4000-8000-000000000003'::uuid,
    'af170000-0000-4000-8000-000000000003'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  );

-- Membership triggers require an active account while the authorization
-- history is created. Deactivate it afterwards so the bridge rejects the
-- identity at its exact mapping boundary.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = 'af110000-0000-4000-8000-000000000003'::uuid;

SELECT app_private.configure_project_reporting_time_zone_v1(
  'af150000-0000-4000-8000-000000000001'::uuid,
  'af110000-0000-4000-8000-000000000001'::uuid,
  'af130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  transaction_timestamp() - interval '30 days'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
) VALUES ('fixture-6aq-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
)
VALUES
  (
    'fixture-6aq-country',
    'fixture-6aq-target-v1',
    NULL,
    '6AQ Country',
    'country'
  ),
  (
    'fixture-6aq-city',
    'fixture-6aq-target-v1',
    'fixture-6aq-country',
    '6AQ City',
    'city'
  ),
  (
    'fixture-6aq-venue',
    'fixture-6aq-target-v1',
    'fixture-6aq-city',
    '6AQ Venue',
    'venue'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
)
VALUES (
  'fixture-6aq-boundary',
  'fixture-6aq-venue',
  'fixture-6aq-target-v1',
  polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6aq-target-v1',
  true
);

CREATE TEMP TABLE fixture_6aq_context ON COMMIT DROP AS
WITH captured AS (
  -- The report contract serializes timestamps to milliseconds. Capture at the
  -- same precision so snapshot metadata and protected_report remain exact.
  SELECT date_trunc('milliseconds', clock_timestamp()) AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC',
    captured.data_cutoff_utc
  ) AS periods,
  app_private.resolve_management_current_city_target_context_v1(
    captured.data_cutoff_utc
  ) AS target_context
FROM captured;

CREATE TEMP TABLE fixture_6aq_document ON COMMIT DROP AS
SELECT jsonb_build_object(
  'report_id', 'contact_sessions_by_current_city_two_periods',
  'report_version', 1,
  'metric_id', 'contact_sessions',
  'metric_version', 1,
  'dimension', 'current_city',
  'view_mode', 'current',
  'region_granularity', 'city',
  'query_fingerprint',
    'management-report:contact_sessions_by_current_city_two_periods:v1',
  'privacy_policy', 'management_current_city_contact_session_privacy_v1',
  'source_scope', 'backend_accepted_active_contacts_current_revision',
  'project_id', 'af130000-0000-4000-8000-000000000001',
  'periods', context.periods,
  'data_cutoff_utc', to_char(
    context.data_cutoff_utc AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  ),
  'source_change_sequence', 0,
  'target_context', context.target_context,
  'result_status', 'completed',
  'cells', jsonb_build_array(
    jsonb_build_object(
      'period_key', 'previous',
      'city_id', 'fixture-6aq-city',
      'cell_order', 0,
      'value_count', 10,
      'privacy_status', 'displayed'
    ),
    jsonb_build_object(
      'period_key', 'current',
      'city_id', 'fixture-6aq-city',
      'cell_order', 1,
      'value_count', 10,
      'privacy_status', 'displayed'
    )
  )
) AS protected_report
FROM fixture_6aq_context AS context;

CREATE TEMP TABLE fixture_6aq_snapshot ON COMMIT DROP AS
SELECT
  'af1a0000-0000-4000-8000-000000000001'::uuid AS snapshot_id,
  'af1b0000-0000-4000-8000-000000000001'::uuid AS release_request_id,
  context.data_cutoff_utc,
  document.protected_report
FROM fixture_6aq_context AS context
CROSS JOIN fixture_6aq_document AS document;

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
  snapshot.snapshot_id,
  snapshot.release_request_id,
  'af110000-0000-4000-8000-000000000001'::uuid,
  'af130000-0000-4000-8000-000000000001'::uuid,
  'management-region-report:contact_sessions_by_current_city_two_periods',
  'contact_sessions_by_current_city_two_periods',
  1,
  'management-report:contact_sessions_by_current_city_two_periods:v1',
  'UTC',
  snapshot.data_cutoff_utc,
  snapshot.data_cutoff_utc,
  NULL,
  0,
  snapshot.protected_report
FROM fixture_6aq_snapshot AS snapshot;

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
  snapshot.release_request_id,
  'af110000-0000-4000-8000-000000000001'::uuid,
  'af120000-0000-4000-8000-000000000001'::uuid,
  'af160000-0000-4000-8000-000000000001'::uuid,
  'af170000-0000-4000-8000-000000000001'::uuid,
  'af180000-0000-4000-8000-000000000001'::uuid,
  'release_management_reports',
  snapshot.data_cutoff_utc,
  'af130000-0000-4000-8000-000000000001'::uuid,
  1,
  'UTC',
  time_zone_version.effective_from_utc,
  snapshot.data_cutoff_utc,
  'management-region-report:contact_sessions_by_current_city_two_periods',
  'contact_sessions_by_current_city_two_periods',
  1,
  'management-report:contact_sessions_by_current_city_two_periods:v1',
  snapshot.protected_report->'target_context'->>'target_tree_version',
  snapshot.protected_report->'target_context'->>'target_content_fingerprint',
  NULL,
  snapshot.snapshot_id,
  'approved_baseline',
  '[]'::jsonb,
  jsonb_build_object(
    'release_contract_id',
      'current_city_management_report_snapshot_release_v1',
    'release_request_id', snapshot.release_request_id,
    'project_id', 'af130000-0000-4000-8000-000000000001',
    'release_lineage_id',
      'management-region-report:contact_sessions_by_current_city_two_periods',
    'report_id', 'contact_sessions_by_current_city_two_periods',
    'report_version', 1,
    'query_fingerprint',
      'management-report:contact_sessions_by_current_city_two_periods:v1',
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', 'UTC',
    'data_cutoff_utc', to_char(
      snapshot.data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'target_tree_version',
      snapshot.protected_report->'target_context'->>'target_tree_version',
    'target_content_fingerprint',
      snapshot.protected_report->'target_context'->>'target_content_fingerprint',
    'compared_snapshot_id', NULL,
    'released_snapshot_id', snapshot.snapshot_id,
    'result_status', 'approved_baseline',
    'reason_codes', '[]'::jsonb
  )
FROM fixture_6aq_snapshot AS snapshot
JOIN app_private.project_reporting_time_zone_versions AS time_zone_version
  ON time_zone_version.project_id =
    'af130000-0000-4000-8000-000000000001'::uuid
 AND time_zone_version.version_number = 1;

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6aq_runtime$
DECLARE
  active_read jsonb;
  repeated_read jsonb;
  spaced_read jsonb;
BEGIN
  active_read = app_data.read_authorized_management_current_city_report_snapshot_v1(
    'https://runtime-current-city.synthetic/auth/v1',
    'active-reader',
    'af130000-0000-4000-8000-000000000001'::uuid,
    'af1a0000-0000-4000-8000-000000000001'::uuid
  );
  IF active_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_current_city_management_report_snapshot_read_v1'
    OR active_read->>'result_status' IS DISTINCT FROM 'completed'
    OR active_read->>'resolved_snapshot_id' IS DISTINCT FROM
      'af1a0000-0000-4000-8000-000000000001'
    OR active_read ? 'project_id'
    OR active_read ? 'requested_app_user_id'
    OR active_read::text ~* 'organization_membership|capability_grant|app_user_id'
    OR active_read->'protected_report'->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_current_city_two_periods'
  THEN
    RAISE EXCEPTION 'runtime current-city bridge returned an invalid result';
  END IF;

  repeated_read = app_data.read_authorized_management_current_city_report_snapshot_v1(
    'https://runtime-current-city.synthetic/auth/v1',
    'active-reader',
    'af130000-0000-4000-8000-000000000001'::uuid,
    'af1a0000-0000-4000-8000-000000000001'::uuid
  );
  IF repeated_read->>'result_status' IS DISTINCT FROM 'completed'
    OR repeated_read->>'access_event_id' IS NULL
    OR repeated_read->>'access_event_id' = active_read->>'access_event_id'
  THEN
    RAISE EXCEPTION 'runtime current-city bridge did not append a new audit';
  END IF;

  -- Exact identity matching is intentional. A stored issuer with surrounding
  -- spaces must not be reached by a clean token.
  BEGIN
    PERFORM app_data.read_authorized_management_current_city_report_snapshot_v1(
      'https://runtime-current-city.synthetic/auth/v1',
      'spaced-reader',
      'af130000-0000-4000-8000-000000000001'::uuid,
      'af1a0000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime bridge trimmed a stored external identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  spaced_read = app_data.read_authorized_management_current_city_report_snapshot_v1(
    ' https://runtime-current-city.synthetic/auth/v1 ',
    'spaced-reader',
    'af130000-0000-4000-8000-000000000001'::uuid,
    'af1a0000-0000-4000-8000-000000000001'::uuid
  );
  IF spaced_read->>'result_status' IS DISTINCT FROM 'completed' THEN
    RAISE EXCEPTION 'exact stored external identity did not resolve';
  END IF;

  BEGIN
    PERFORM app_data.read_authorized_management_current_city_report_snapshot_v1(
      'https://runtime-current-city.synthetic/auth/v1',
      'inactive-reader',
      'af130000-0000-4000-8000-000000000001'::uuid,
      'af1a0000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime bridge accepted a deactivated identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_authorized_management_current_city_report_snapshot_v1(
      'https://runtime-current-city.synthetic/auth/v1',
      'unknown-reader',
      'af130000-0000-4000-8000-000000000001'::uuid,
      'af1a0000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime bridge accepted an unknown identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_authorized_management_current_city_report_snapshot_v1(
      'https://runtime-current-city.synthetic/auth/v1',
      'active-reader',
      'af130000-0000-4000-8000-000000000002'::uuid,
      'af1a0000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime bridge bypassed current-city project authorization';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_authorized_management_current_city_report_snapshot_v1(
      'https://runtime-current-city.synthetic/auth/v1',
      'active-reader',
      'not-a-uuid'::uuid,
      'af1a0000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime bridge accepted an invalid project UUID';
  EXCEPTION WHEN invalid_text_representation THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_current_city_report_snapshot_v1(
      'af110000-0000-4000-8000-000000000002'::uuid,
      'af130000-0000-4000-8000-000000000001'::uuid,
      'af1a0000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'runtime received direct app_private access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

END
$fixture_6aq_runtime$;

RESET ROLE;

DO $fixture_6aq_audit$
DECLARE
  event_count bigint;
BEGIN
  SELECT count(*)
  INTO event_count
  FROM app_private.management_current_city_report_snapshot_access_events
  WHERE requested_by_app_user_id =
    'af110000-0000-4000-8000-000000000002'::uuid;
  -- active, repeat and exact spaced identity are the only successful reads.
  IF event_count <> 3 THEN
    RAISE EXCEPTION 'runtime bridge audit count is incorrect: %', event_count;
  END IF;
END
$fixture_6aq_audit$;

ROLLBACK;
