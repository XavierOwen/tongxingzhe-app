\set ON_ERROR_STOP on
BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('81030000-0000-4000-8000-000000000001', 'active'),
  ('81030000-0000-4000-8000-000000000008', 'active'),
  ('81030000-0000-4000-8000-000000000009', 'active');
SELECT app_private.create_organization_v1(
  '81030000-0000-4000-8000-000000000001',
  '81030000-0000-4000-8000-000000000002',
  '0103 recovery report read fixture'
);
INSERT INTO app_data.external_identities (issuer, subject, app_user_id)
VALUES (
  'https://synthetic-0103.example/issuer',
  'report-reader',
  '81030000-0000-4000-8000-000000000001'
);
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
SELECT
  '81030000-0000-4000-8000-000000000003',
  claim.organization_workspace_id,
  '0103 recovery report read project'
FROM app_private.organization_creation_request_claims AS claim
WHERE claim.request_id = '81030000-0000-4000-8000-000000000002';
INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc
)
SELECT
  '81030000-0000-4000-8000-000000000004',
  membership.organization_membership_id,
  '81030000-0000-4000-8000-000000000003',
  membership.active_from_utc
FROM app_data.organization_memberships AS membership
JOIN app_private.organization_creation_request_claims AS claim
  ON claim.organization_workspace_id = membership.organization_workspace_id
WHERE claim.request_id = '81030000-0000-4000-8000-000000000002'
  AND membership.app_user_id = '81030000-0000-4000-8000-000000000001';
INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc
)
VALUES (
  '81030000-0000-4000-8000-000000000005',
  '81030000-0000-4000-8000-000000000004',
  'view_anonymous_analytics',
  (SELECT active_from_utc FROM app_data.project_memberships
   WHERE project_membership_id = '81030000-0000-4000-8000-000000000004')
);
INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc
)
VALUES (
  '81030000-0000-4000-8000-000000000010',
  '81030000-0000-4000-8000-000000000004',
  'release_management_reports',
  (SELECT active_from_utc FROM app_data.project_memberships
   WHERE project_membership_id = '81030000-0000-4000-8000-000000000004')
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
)
VALUES (
  '81030000-0000-4000-8000-000000000011',
  '81030000-0000-4000-8000-000000000003',
  1,
  'published',
  true
);
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
  'organization-report-recovery-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '81030000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '81030000-0000-4000-8000-000000000008'::uuid
    ELSE '81030000-0000-4000-8000-000000000009'::uuid
  END,
  claim.organization_workspace_id,
  '81030000-0000-4000-8000-000000000003',
  '81030000-0000-4000-8000-000000000011',
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM app_private.organization_creation_request_claims AS claim
CROSS JOIN (
  SELECT
    'previous'::text AS period_key,
    (date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
      - interval '12 days') AT TIME ZONE 'UTC' AS occurred_at_utc
  UNION ALL
  SELECT
    'current'::text,
    (date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
      - interval '5 days') AT TIME ZONE 'UTC'
) AS period_row
CROSS JOIN generate_series(1, 10) AS series_row
WHERE claim.request_id = '81030000-0000-4000-8000-000000000002';

DO $published_snapshot$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '81030000-0000-4000-8000-000000000012',
    '81030000-0000-4000-8000-000000000001',
    '81030000-0000-4000-8000-000000000003',
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );
  PERFORM app_private.release_management_report_snapshot_v2(
    '81030000-0000-4000-8000-000000000013',
    '81030000-0000-4000-8000-000000000001',
    '81030000-0000-4000-8000-000000000003',
    'contact_sessions_by_channel_two_periods',
    1
  );
END
$published_snapshot$;

CREATE TEMP TABLE fixture_0103_published_snapshot AS
SELECT snapshot.snapshot_id, snapshot.protected_report
FROM app_private.management_report_snapshots AS snapshot
JOIN app_private.management_report_release_v2_attempts AS attempt
  ON attempt.released_snapshot_id = snapshot.snapshot_id
WHERE attempt.release_request_id = '81030000-0000-4000-8000-000000000013'
  AND attempt.result_status IN ('approved_baseline', 'approved');
GRANT SELECT ON fixture_0103_published_snapshot TO tongxingzhe_runtime;
DO $published_snapshot_contract$
BEGIN
  IF (SELECT count(*) FROM fixture_0103_published_snapshot) <> 1 THEN
    RAISE EXCEPTION '0103 did not create one trusted published snapshot';
  END IF;
END
$published_snapshot_contract$;

INSERT INTO app_private.organization_deletion_current (
  organization_workspace_id,
  deletion_request_id,
  effective_at_utc,
  purge_after_utc,
  status
)
SELECT
  claim.organization_workspace_id,
  '81030000-0000-4000-8000-000000000006',
  transaction_timestamp(),
  transaction_timestamp() + interval '720 hours',
  'deletion_pending'
FROM app_private.organization_creation_request_claims AS claim
WHERE claim.request_id = '81030000-0000-4000-8000-000000000002';
UPDATE app_data.workspaces AS workspace
SET deleted_at = attempt.effective_at_utc
FROM app_private.organization_deletion_current AS attempt
WHERE attempt.deletion_request_id =
    '81030000-0000-4000-8000-000000000006'
  AND workspace.workspace_id = attempt.organization_workspace_id;

CREATE TEMP TABLE fixture_0103_before AS
SELECT
  (SELECT count(*) FROM app_private.management_report_snapshot_directory_access_events) AS channel_directory,
  (SELECT count(*) FROM app_private.management_report_snapshot_access_events) AS channel_detail,
  (SELECT count(*) FROM app_private.management_current_city_report_snapshot_directory_access_events) AS city_directory,
  (SELECT count(*) FROM app_private.management_current_city_report_snapshot_access_events) AS city_detail,
  (SELECT count(*) FROM app_private.management_interest_report_snapshot_directory_access_events) AS interest_directory,
  (SELECT count(*) FROM app_private.management_interest_report_snapshot_access_events) AS interest_detail,
  (SELECT count(*) FROM app_private.management_original_region_snapshot_directory_access_events) AS original_directory,
  (SELECT count(*) FROM app_private.management_original_region_report_snapshot_access_events) AS original_detail,
  (SELECT count(*) FROM app_private.management_follow_up_consent_snapshot_directory_access_events) AS consent_directory,
  (SELECT count(*) FROM app_private.management_follow_up_consent_report_snapshot_access_events) AS consent_detail;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0103_directories AS
SELECT
  app_data.list_authorized_management_report_snapshots_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003'
  ) AS channel,
  app_data.list_authorized_management_current_city_report_snapshots_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003'
  ) AS current_city,
  app_data.list_authorized_management_interest_report_snapshots_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003'
  ) AS interest,
  app_data.list_authorized_management_original_region_report_snapshots_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003'
  ) AS original_region,
  app_data.list_authorized_management_follow_up_consent_snapshots_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003'
  ) AS follow_up_consent;
CREATE TEMP TABLE fixture_0103_details AS
SELECT
  app_data.read_authorized_management_report_snapshot_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003',
    (SELECT snapshot_id FROM fixture_0103_published_snapshot)
  ) AS channel,
  app_data.read_authorized_management_current_city_report_snapshot_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003',
    '81030000-0000-4000-8000-000000000007'
  ) AS current_city,
  app_data.read_authorized_management_interest_report_snapshot_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003',
    '81030000-0000-4000-8000-000000000007'
  ) AS interest,
  app_data.read_authorized_management_original_region_report_snapshot_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003',
    '81030000-0000-4000-8000-000000000007'
  ) AS original_region,
  app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
    'https://synthetic-0103.example/issuer', 'report-reader',
    '81030000-0000-4000-8000-000000000003',
    '81030000-0000-4000-8000-000000000007'
  ) AS follow_up_consent;
DO $runtime_contract$
BEGIN
  IF (SELECT current_city->'snapshots' <> '[]'::jsonb
      OR interest->'snapshots' <> '[]'::jsonb
      OR original_region->'snapshots' <> '[]'::jsonb
      OR follow_up_consent->'snapshots' <> '[]'::jsonb
      FROM fixture_0103_directories)
  THEN
    RAISE EXCEPTION '0103 empty directory result contract changed';
  END IF;
  IF (SELECT NOT channel->'snapshots' @> jsonb_build_array(
        jsonb_build_object('snapshot_id', snapshot.snapshot_id::text))
      FROM fixture_0103_directories
      CROSS JOIN fixture_0103_published_snapshot AS snapshot)
  THEN
    RAISE EXCEPTION '0103 recovery directory omitted the published snapshot';
  END IF;
  IF (SELECT channel->>'result_status' <> 'completed'
      OR channel->'protected_report' IS DISTINCT FROM snapshot.protected_report
      OR current_city->>'result_status' <> 'not_found'
      OR interest->>'result_status' <> 'not_found'
      OR original_region->>'result_status' <> 'not_found'
      OR follow_up_consent->>'result_status' <> 'not_found'
      FROM fixture_0103_details
      CROSS JOIN fixture_0103_published_snapshot AS snapshot)
  THEN
    RAISE EXCEPTION '0103 published or missing detail result contract changed';
  END IF;
  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      '81030000-0000-4000-8000-000000000001',
      '81030000-0000-4000-8000-000000000003',
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION '0103 widened the shared strict report resolver';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$runtime_contract$;
RESET ROLE;

CREATE TEMP TABLE fixture_0103_after AS
SELECT
  (SELECT count(*) FROM app_private.management_report_snapshot_directory_access_events) AS channel_directory,
  (SELECT count(*) FROM app_private.management_report_snapshot_access_events) AS channel_detail,
  (SELECT count(*) FROM app_private.management_current_city_report_snapshot_directory_access_events) AS city_directory,
  (SELECT count(*) FROM app_private.management_current_city_report_snapshot_access_events) AS city_detail,
  (SELECT count(*) FROM app_private.management_interest_report_snapshot_directory_access_events) AS interest_directory,
  (SELECT count(*) FROM app_private.management_interest_report_snapshot_access_events) AS interest_detail,
  (SELECT count(*) FROM app_private.management_original_region_snapshot_directory_access_events) AS original_directory,
  (SELECT count(*) FROM app_private.management_original_region_report_snapshot_access_events) AS original_detail,
  (SELECT count(*) FROM app_private.management_follow_up_consent_snapshot_directory_access_events) AS consent_directory,
  (SELECT count(*) FROM app_private.management_follow_up_consent_report_snapshot_access_events) AS consent_detail;

DO $audit_contract$
BEGIN
  IF (SELECT after_row.channel_directory - before_row.channel_directory
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.channel_detail - before_row.channel_detail
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.city_directory - before_row.city_directory
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.city_detail - before_row.city_detail
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.interest_directory - before_row.interest_directory
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.interest_detail - before_row.interest_detail
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.original_directory - before_row.original_directory
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.original_detail - before_row.original_detail
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.consent_directory - before_row.consent_directory
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
    OR (SELECT after_row.consent_detail - before_row.consent_detail
      FROM fixture_0103_after AS after_row CROSS JOIN fixture_0103_before AS before_row) <> 1
  THEN
    RAISE EXCEPTION '0103 did not append one value-free event per read';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.project_id = '81030000-0000-4000-8000-000000000003'
      AND event.requested_snapshot_id = (
        SELECT snapshot_id FROM fixture_0103_published_snapshot
      )
      AND to_jsonb(event) ? 'protected_report'
  ) THEN
    RAISE EXCEPTION '0103 snapshot access audit contains report values';
  END IF;
END
$audit_contract$;

DO $closed_windows$
DECLARE
  actual_state text;
  actual_message text;
  fixture_workspace_id uuid;
  deadline_utc timestamptz;
BEGIN
  SELECT organization_workspace_id INTO STRICT fixture_workspace_id
  FROM app_private.organization_deletion_current
  WHERE deletion_request_id = '81030000-0000-4000-8000-000000000006';
  SELECT purge_after_utc INTO STRICT deadline_utc
  FROM app_private.organization_deletion_current
  WHERE organization_workspace_id = fixture_workspace_id;

  PERFORM app_private.resolve_management_report_recovery_read_authorization_v1(
    '81030000-0000-4000-8000-000000000001',
    '81030000-0000-4000-8000-000000000003',
    'view_anonymous_analytics',
    (SELECT effective_at_utc FROM app_private.organization_deletion_current
     WHERE organization_workspace_id = fixture_workspace_id)
  );

  actual_state := NULL;
  actual_message := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_recovery_read_authorization_v1(
      '81030000-0000-4000-8000-000000000001',
      '81030000-0000-4000-8000-000000000003',
      'view_anonymous_analytics',
      deadline_utc
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '42501'
    OR actual_message IS DISTINCT FROM 'management report authorization forbidden'
  THEN
    RAISE EXCEPTION '0103 accepted the half-open recovery deadline';
  END IF;

  UPDATE app_data.workspaces
  SET deleted_at = deleted_at + interval '1 second'
  WHERE workspaces.workspace_id = fixture_workspace_id;
  actual_state := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_recovery_read_authorization_v1(
      '81030000-0000-4000-8000-000000000001',
      '81030000-0000-4000-8000-000000000003',
      'view_anonymous_analytics'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  IF actual_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION '0103 accepted a mismatched deleted_at';
  END IF;

  UPDATE app_data.workspaces
  SET deleted_at = NULL
  WHERE workspaces.workspace_id = fixture_workspace_id;
  UPDATE app_private.organization_deletion_current
  SET status = 'restored', restored_at_utc = clock_timestamp()
  WHERE organization_workspace_id = fixture_workspace_id;
  PERFORM app_private.resolve_management_report_recovery_read_authorization_v1(
    '81030000-0000-4000-8000-000000000001',
    '81030000-0000-4000-8000-000000000003',
    'view_anonymous_analytics'
  );

  UPDATE app_data.workspaces
  SET deleted_at = clock_timestamp()
  WHERE workspaces.workspace_id = fixture_workspace_id;
  DELETE FROM app_private.organization_deletion_current
  WHERE organization_workspace_id = fixture_workspace_id;
  actual_state := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_recovery_read_authorization_v1(
      '81030000-0000-4000-8000-000000000001',
      '81030000-0000-4000-8000-000000000003',
      'view_anonymous_analytics'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  IF actual_state IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION '0103 accepted deleted_at without a lifecycle attempt';
  END IF;
END
$closed_windows$;

ROLLBACK;
