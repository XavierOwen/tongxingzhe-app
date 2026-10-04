-- Synthetic, rollback-only proof of the 0102 BEFORE INSERT fence.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

INSERT INTO app_data.app_users(app_user_id, status)
VALUES ('00000000-0102-0000-8000-000000000001', 'active');

CREATE TEMP TABLE fixture_0102_organization AS
SELECT * FROM app_private.create_organization_v1(
  '00000000-0102-0000-8000-000000000001'::uuid,
  '00000000-0102-4000-8000-000000000001'::uuid,
  '0102 synthetic organization');

INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '00000000-0102-6000-8000-000000000001'::uuid,
  organization_workspace_id, '0102 synthetic project'
FROM fixture_0102_organization;

INSERT INTO app_data.workspaces(
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
)
VALUES (
  '00000000-0102-1000-8000-000000000001', 'personal',
  '0102 synthetic personal workspace',
  '00000000-0102-0000-8000-000000000001'
);
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
VALUES (
  '00000000-0102-6000-8000-000000000002',
  '00000000-0102-1000-8000-000000000001',
  '0102 synthetic personal project'
);

CREATE FUNCTION pg_temp.expect_0102_fence(
  table_name text, project_id uuid, expect_rejection boolean
) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; actual_message text;
BEGIN
  actual_state := NULL;
  actual_message := NULL;
  BEGIN
    EXECUTE format(
      'INSERT INTO app_private.%I (project_id) VALUES ($1)', table_name
    ) USING project_id;
    RAISE EXCEPTION USING
      ERRCODE = 'P0001', MESSAGE = '0102 fixture insertion reached sentinel';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;

  IF expect_rejection THEN
    IF actual_state IS DISTINCT FROM '55000'
      OR actual_message IS DISTINCT FROM
        'organization report write unavailable'
    THEN
      RAISE EXCEPTION '0102 expected fence rejection for %, got % / %',
        table_name, actual_state, actual_message;
    END IF;
  ELSIF actual_state = '55000'
    AND actual_message = 'organization report write unavailable'
  THEN
    RAISE EXCEPTION '0102 active organization was rejected for %', table_name;
  END IF;
END
$function$;

DO $active$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'management_report_snapshots',
    'management_report_release_attempts',
    'management_report_release_v2_attempts',
    'management_current_city_report_release_attempts',
    'management_interest_report_release_attempts',
    'management_original_region_report_release_attempts',
    'management_follow_up_consent_report_release_attempts',
    'management_report_snapshot_export_events',
    'management_report_snapshot_replacements',
    'management_original_region_report_snapshot_replacements',
    'management_current_city_report_snapshot_replacements',
    'management_interest_report_snapshot_replacements',
    'management_follow_up_consent_ratio_report_snapshot_replacements',
    'management_follow_up_consent_opt_in_versions'
  ] LOOP
    PERFORM pg_temp.expect_0102_fence(
      table_name, '00000000-0102-6000-8000-000000000001'::uuid, false);
  END LOOP;
  PERFORM pg_temp.expect_0102_fence(
    'management_report_release_attempts',
    '00000000-0102-6000-8000-000000000002'::uuid, true);
END
$active$;

SELECT * FROM app_private.request_organization_deletion_v1(
  '00000000-0102-0000-8000-000000000001'::uuid,
  '00000000-0102-4000-8000-000000000002'::uuid,
  (SELECT organization_workspace_id FROM fixture_0102_organization)
);

DO $pending$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'management_report_snapshots',
    'management_report_release_attempts',
    'management_report_release_v2_attempts',
    'management_current_city_report_release_attempts',
    'management_interest_report_release_attempts',
    'management_original_region_report_release_attempts',
    'management_follow_up_consent_report_release_attempts',
    'management_report_snapshot_export_events',
    'management_report_snapshot_replacements',
    'management_original_region_report_snapshot_replacements',
    'management_current_city_report_snapshot_replacements',
    'management_interest_report_snapshot_replacements',
    'management_follow_up_consent_ratio_report_snapshot_replacements',
    'management_follow_up_consent_opt_in_versions'
  ] LOOP
    PERFORM pg_temp.expect_0102_fence(
      table_name, '00000000-0102-6000-8000-000000000001'::uuid, true);
  END LOOP;
END
$pending$;

SET LOCAL ROLE tongxingzhe_management_consent_ratio_snapshot_release_writer;
SELECT pg_temp.expect_0102_fence(
  'management_report_snapshots',
  '00000000-0102-6000-8000-000000000001'::uuid, true
);
RESET ROLE;

DO $rollback$
DECLARE table_name text; row_count bigint;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'management_report_snapshots',
    'management_report_release_attempts',
    'management_report_release_v2_attempts',
    'management_current_city_report_release_attempts',
    'management_interest_report_release_attempts',
    'management_original_region_report_release_attempts',
    'management_follow_up_consent_report_release_attempts',
    'management_report_snapshot_export_events',
    'management_report_snapshot_replacements',
    'management_original_region_report_snapshot_replacements',
    'management_current_city_report_snapshot_replacements',
    'management_interest_report_snapshot_replacements',
    'management_follow_up_consent_ratio_report_snapshot_replacements',
    'management_follow_up_consent_opt_in_versions'
  ] LOOP
    EXECUTE format(
      'SELECT count(*) FROM app_private.%I WHERE project_id = $1', table_name
    ) INTO row_count USING '00000000-0102-6000-8000-000000000001'::uuid;
    IF row_count <> 0 THEN
      RAISE EXCEPTION '0102 pending insert left rows in %', table_name;
    END IF;
  END LOOP;
END
$rollback$;

SELECT * FROM app_private.restore_organization_v1(
  '00000000-0102-0000-8000-000000000001'::uuid,
  '00000000-0102-5000-8000-000000000001'::uuid,
  (SELECT organization_workspace_id FROM fixture_0102_organization),
  '00000000-0102-4000-8000-000000000002'::uuid
);

DO $restored$
BEGIN
  PERFORM pg_temp.expect_0102_fence(
    'management_report_release_attempts',
    '00000000-0102-6000-8000-000000000001'::uuid, false);
END
$restored$;

ROLLBACK;
