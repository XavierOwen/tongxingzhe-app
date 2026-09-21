-- A projectless organization committed by the shipped 0084 runtime writer.
\set ON_ERROR_STOP on
\set QUIET on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

DO $check$
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 87
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0088_organization_owner_transfer_authorization_time'
    OR to_regprocedure(
      'app_data.list_organizations_for_identity_v1(text,text)'
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION '0088 organization-directory upgrade baseline drift';
  END IF;
END
$check$;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('00000000-0088-0000-0000-000000000901', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES (
  '00000000-0088-1000-0000-000000000901',
  'https://synthetic-organization-directory-upgrade.example/auth/v1',
  'owner',
  '00000000-0088-0000-0000-000000000901'
);

CREATE TEMP TABLE fixture_0088_organization_creation_receipt (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
);
GRANT ALL ON fixture_0088_organization_creation_receipt
  TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0088_organization_creation_receipt
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-organization-directory-upgrade.example/auth/v1',
  'owner',
  '00000000-0088-6000-0000-000000000901',
  '  0088 Directory upgrade organization  '
);
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;

DO $legacy$
DECLARE
  receipt fixture_0088_organization_creation_receipt%ROWTYPE;
  claim app_private.organization_creation_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt
  FROM fixture_0088_organization_creation_receipt;
  SELECT * INTO STRICT claim
  FROM app_private.organization_creation_request_claims
  WHERE request_id = '00000000-0088-6000-0000-000000000901';

  IF receipt.creation_contract_id IS DISTINCT FROM
      'organization-creation:v1'
    OR claim.actor_app_user_id IS DISTINCT FROM
      '00000000-0088-0000-0000-000000000901'::uuid
    OR claim.canonical_display_name IS DISTINCT FROM
      '0088 Directory upgrade organization'
    OR claim.organization_workspace_id IS DISTINCT FROM
      receipt.organization_workspace_id
    OR claim.organization_membership_id IS DISTINCT FROM
      receipt.organization_membership_id
    OR claim.organization_owner_assignment_id IS DISTINCT FROM
      receipt.organization_owner_assignment_id
    OR claim.created_at_utc IS DISTINCT FROM receipt.created_at_utc
    OR (SELECT count(*)
        FROM fixture_0088_organization_creation_receipt) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_creation_request_claims) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_creation_audit_events) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.workspaces AS workspace
      WHERE workspace.workspace_id = receipt.organization_workspace_id
        AND workspace.workspace_kind = 'organization'
        AND workspace.display_name = '0088 Directory upgrade organization'
        AND workspace.personal_owner_app_user_id IS NULL
        AND workspace.deleted_at IS NULL
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_membership_id =
          receipt.organization_membership_id
        AND membership.organization_workspace_id =
          receipt.organization_workspace_id
        AND membership.app_user_id =
          '00000000-0088-0000-0000-000000000901'::uuid
        AND membership.active_from_utc = receipt.created_at_utc
        AND membership.inactive_from_utc IS NULL
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments AS assignment
      WHERE assignment.organization_owner_assignment_id =
          receipt.organization_owner_assignment_id
        AND assignment.organization_membership_id =
          receipt.organization_membership_id
        AND assignment.active_from_utc = receipt.created_at_utc
        AND assignment.inactive_from_utc IS NULL
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.projects AS project
      WHERE project.workspace_id = receipt.organization_workspace_id
    )
    OR EXISTS (SELECT 1 FROM app_data.project_memberships)
    OR EXISTS (SELECT 1 FROM app_data.management_report_capability_grants)
  THEN
    RAISE EXCEPTION '0088 legacy organization creation drift';
  END IF;
END
$legacy$;

COMMIT;

SELECT * FROM fixture_0088_organization_creation_receipt;
