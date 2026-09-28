\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
) VALUES (
  '00000000-0000-4000-8000-000000007c12',
  'https://upgrade-directory.synthetic/auth/v1',
  '7cm-viewer',
  '00000000-0000-4000-8000-000000007c02'
);

SET LOCAL ROLE tongxingzhe_runtime;

DO $select$
DECLARE
  selected record;
BEGIN
  SELECT * INTO STRICT selected
  FROM app_data.select_management_analysis_context_v1(
    'https://upgrade-directory.synthetic/auth/v1',
    '7cm-viewer',
    '00000000-0000-4000-8000-000000007c05'
  );
  IF selected.organization_workspace_id <>
      '00000000-0000-4000-8000-000000007c03'
    OR selected.organization_name <> '7CK upgrade workspace'
    OR selected.project_id <> '00000000-0000-4000-8000-000000007c05'
    OR selected.project_name <> '7CK upgrade project'
    OR selected.is_current IS NOT TRUE
  THEN
    RAISE EXCEPTION '7CM current context response drift';
  END IF;
END
$select$;

RESET ROLE;

DO $verify$
DECLARE
  context_row app_data.management_analysis_current_contexts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT context_row
  FROM app_data.management_analysis_current_contexts
  WHERE app_user_id = '00000000-0000-4000-8000-000000007c02';

  IF context_row.organization_workspace_id <>
      '00000000-0000-4000-8000-000000007c03'
    OR context_row.organization_membership_id <>
      '00000000-0000-4000-8000-000000007c07'
    OR context_row.project_id <>
      '00000000-0000-4000-8000-000000007c05'
    OR context_row.project_membership_id <>
      '00000000-0000-4000-8000-000000007c09'
    OR context_row.capability_grant_id <>
      '00000000-0000-4000-8000-000000007c0b'
    OR context_row.selected_at_utc IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.external_identities AS identity_row
      JOIN app_data.app_users AS app_user
        ON app_user.app_user_id = identity_row.app_user_id
      JOIN app_data.organization_memberships AS organization_membership
        ON organization_membership.organization_membership_id =
          context_row.organization_membership_id
       AND organization_membership.app_user_id = app_user.app_user_id
      JOIN app_data.project_memberships AS project_membership
        ON project_membership.project_membership_id =
          context_row.project_membership_id
       AND project_membership.organization_membership_id =
          organization_membership.organization_membership_id
      JOIN app_data.management_report_capability_grants AS grant_row
        ON grant_row.capability_grant_id = context_row.capability_grant_id
       AND grant_row.project_membership_id = project_membership.project_membership_id
      WHERE identity_row.external_identity_id =
          '00000000-0000-4000-8000-000000007c12'
        AND identity_row.app_user_id = context_row.app_user_id
        AND grant_row.capability_id = 'view_anonymous_analytics'
        AND project_membership.project_id = context_row.project_id
        AND organization_membership.organization_workspace_id =
          context_row.organization_workspace_id
        AND tstzrange(organization_membership.active_from_utc,
          organization_membership.inactive_from_utc, '[)') @> context_row.selected_at_utc
        AND tstzrange(project_membership.active_from_utc,
          project_membership.inactive_from_utc, '[)') @> context_row.selected_at_utc
        AND tstzrange(grant_row.active_from_utc,
          grant_row.inactive_from_utc, '[)') @> context_row.selected_at_utc
    )
  THEN
    RAISE EXCEPTION '7CM current context authorization evidence drift';
  END IF;
END
$verify$;

COMMIT;
