\set ON_ERROR_STOP on
BEGIN;

-- A valid active owner/project membership without a release capability must
-- still fail before any receipt lookup, claim or report/config write.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('81070000-0000-4000-8000-000000000001', 'active');
SELECT app_private.create_organization_v1(
  '81070000-0000-4000-8000-000000000001',
  '81070000-0000-4000-8000-000000000002',
  '0107 request lock authorization fixture');
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
SELECT '81070000-0000-4000-8000-000000000003',
  claim.organization_workspace_id, '0107 request lock fixture project'
FROM app_private.organization_creation_request_claims AS claim
WHERE claim.request_id = '81070000-0000-4000-8000-000000000002';
INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id, active_from_utc
)
SELECT '81070000-0000-4000-8000-000000000004',
  membership.organization_membership_id,
  '81070000-0000-4000-8000-000000000003', membership.active_from_utc
FROM app_data.organization_memberships AS membership
WHERE membership.organization_workspace_id = (
  SELECT organization_workspace_id
  FROM app_private.organization_creation_request_claims
  WHERE request_id = '81070000-0000-4000-8000-000000000002'
) AND membership.app_user_id = '81070000-0000-4000-8000-000000000001';

DO $failure_semantics$
DECLARE target record; table_name text; row_count bigint;
BEGIN
  FOR target IN SELECT * FROM (VALUES
      ('release_management_report_snapshot_v2', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_channel_two_periods', 1$arguments$),
      ('release_management_current_city_report_snapshot_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_current_city_two_periods', 1$arguments$),
      ('release_management_interest_report_snapshot_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_interest_level_two_periods', 1$arguments$),
      ('declare_management_report_snapshot_replacement_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
      ('release_management_original_region_report_snapshot_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_original_region_two_periods', 1$arguments$),
      ('declare_management_original_region_snapshot_replacement_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
      ('configure_management_follow_up_consent_opt_in_v1', $arguments$'81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'follow_up_consent_ratio@1', '81070000-0000-4000-8000-000000000005'::uuid, 0, true$arguments$),
      ('release_management_follow_up_consent_ratio_report_snapshot_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_target_follow_up_consent_ratio_two_periods', 1$arguments$),
      ('declare_management_current_city_snapshot_replacement_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
      ('declare_management_interest_snapshot_replacement_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
      ('declare_management_follow_up_consent_snapshot_replacement_v1', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$)
    ) AS calls(name, arguments)
  LOOP
    BEGIN
      EXECUTE 'SELECT app_private.' || target.name || '(' || target.arguments || ')';
      RAISE EXCEPTION '0107 unauthorized writer succeeded: %', target.name;
    EXCEPTION WHEN insufficient_privilege THEN
      IF SQLERRM IS DISTINCT FROM 'management report authorization forbidden' THEN
        RAISE EXCEPTION '0107 authorization error changed: %', SQLERRM;
      END IF;
    END;
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY[
    'management_report_snapshots', 'management_report_release_attempts',
    'management_report_release_v2_attempts',
    'management_current_city_report_release_attempts',
    'management_interest_report_release_attempts',
    'management_original_region_report_release_attempts',
    'management_follow_up_consent_report_release_attempts',
    'management_report_snapshot_replacements',
    'management_original_region_report_snapshot_replacements',
    'management_current_city_report_snapshot_replacements',
    'management_interest_report_snapshot_replacements',
    'management_follow_up_consent_ratio_report_snapshot_replacements',
    'management_follow_up_consent_opt_in_versions',
    'management_report_snapshot_access_events',
    'management_report_snapshot_directory_access_events'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM app_private.%I WHERE project_id = $1', table_name)
    INTO row_count USING '81070000-0000-4000-8000-000000000003'::uuid;
    IF row_count <> 0 THEN
      RAISE EXCEPTION '0107 unauthorized writer added receipt, business or audit rows in %', table_name;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_private.management_report_release_request_claims
    WHERE release_request_id = '81070000-0000-4000-8000-000000000005') THEN
    RAISE EXCEPTION '0107 unauthorized writer claimed the request';
  END IF;
END
$failure_semantics$;
ROLLBACK;
