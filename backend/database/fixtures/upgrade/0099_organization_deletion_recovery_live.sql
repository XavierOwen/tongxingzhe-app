-- Committed 0099 organization data for the staged 0100 migration proof.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0099_organization_shareable_join_application_directory'
    OR to_regclass('app_private.organization_deletion_current') IS NOT NULL
  THEN RAISE EXCEPTION '0100 upgrade fixture requires the 0099 baseline'; END IF;
END
$baseline$;

INSERT INTO app_data.app_users(app_user_id, status) VALUES
  ('00000000-0100-0000-8000-000000000901', 'active'),
  ('00000000-0100-0000-8000-000000000902', 'active');

CREATE TEMP TABLE fixture_0099_organization AS
SELECT * FROM app_private.create_organization_v1(
  '00000000-0100-0000-8000-000000000901'::uuid,
  '00000000-0100-1000-8000-000000000901'::uuid,
  '0099 to 0100 retained organization');

INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc)
SELECT '00000000-0100-2000-8000-000000000902',
  organization_workspace_id, '00000000-0100-0000-8000-000000000902',
  transaction_timestamp(), NULL
FROM fixture_0099_organization;
INSERT INTO app_data.organization_owner_assignments(
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc)
VALUES ('00000000-0100-3000-8000-000000000902',
  '00000000-0100-2000-8000-000000000902', transaction_timestamp(), NULL);

INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '00000000-0100-6000-8000-000000000901',
  organization_workspace_id, '0099 retained project'
FROM fixture_0099_organization;

DO $baseline$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0099_organization);
BEGIN
  IF (SELECT count(*) FROM app_data.organization_owner_assignments AS assignment
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE membership.organization_workspace_id = org_id
        AND assignment.inactive_from_utc IS NULL) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_data.projects
      WHERE project_id = '00000000-0100-6000-8000-000000000901'
        AND workspace_id = org_id)
    OR (SELECT deleted_at FROM app_data.workspaces
      WHERE workspace_id = org_id) IS NOT NULL
  THEN RAISE EXCEPTION '0099 synthetic organization baseline is incomplete'; END IF;
END
$baseline$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
