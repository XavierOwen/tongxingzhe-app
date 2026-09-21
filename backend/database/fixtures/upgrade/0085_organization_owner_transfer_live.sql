-- An organization committed by the shipped 0084 runtime writer before 0086.
\set ON_ERROR_STOP on
\set QUIET on

SET TIME ZONE 'UTC';

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0085-0000-0000-000000000501', 'active'),
  ('00000000-0085-0000-0000-000000000502', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES (
  '00000000-0085-1000-0000-000000000501',
  'https://synthetic-owner-transfer-upgrade.example/auth/v1',
  'owner',
  '00000000-0085-0000-0000-000000000501'
);

CREATE TEMP TABLE fixture_0085_creation_receipt (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
);
GRANT ALL ON fixture_0085_creation_receipt TO tongxingzhe_runtime;

SET ROLE tongxingzhe_runtime;
INSERT INTO fixture_0085_creation_receipt
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-owner-transfer-upgrade.example/auth/v1',
  'owner',
  '00000000-0085-5000-0000-000000000501',
  '  0085 Owner transfer upgrade organization  '
);
RESET ROLE;

BEGIN;
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '00000000-0085-3000-0000-000000000502',
  receipt.organization_workspace_id,
  '00000000-0085-0000-0000-000000000502',
  receipt.created_at_utc,
  NULL
FROM fixture_0085_creation_receipt AS receipt;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

DO $legacy$
DECLARE
  receipt fixture_0085_creation_receipt%ROWTYPE;
  claim app_private.organization_creation_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM fixture_0085_creation_receipt;
  SELECT * INTO STRICT claim
  FROM app_private.organization_creation_request_claims
  WHERE request_id = '00000000-0085-5000-0000-000000000501'::uuid;

  IF (SELECT count(*) FROM fixture_0085_creation_receipt) <> 1
    OR receipt.creation_contract_id IS DISTINCT FROM
      'organization-creation:v1'
    OR claim.actor_app_user_id IS DISTINCT FROM
      '00000000-0085-0000-0000-000000000501'::uuid
    OR claim.canonical_display_name IS DISTINCT FROM
      '0085 Owner transfer upgrade organization'
    OR claim.organization_workspace_id IS DISTINCT FROM
      receipt.organization_workspace_id
    OR claim.organization_membership_id IS DISTINCT FROM
      receipt.organization_membership_id
    OR claim.organization_owner_assignment_id IS DISTINCT FROM
      receipt.organization_owner_assignment_id
    OR claim.created_at_utc IS DISTINCT FROM receipt.created_at_utc
    OR (SELECT count(*)
        FROM app_private.organization_creation_request_claims) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_creation_audit_events
        WHERE creation_contract_id = receipt.creation_contract_id
          AND request_id = '00000000-0085-5000-0000-000000000501'::uuid
          AND organization_workspace_id = receipt.organization_workspace_id
          AND organization_membership_id = receipt.organization_membership_id
          AND organization_owner_assignment_id =
            receipt.organization_owner_assignment_id
          AND created_at_utc = receipt.created_at_utc) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_creation_audit_events) <> 1
    OR (SELECT count(*)
        FROM app_data.app_users
        WHERE status = 'active') <> 2
    OR (SELECT count(*)
        FROM app_data.external_identities
        WHERE issuer =
            'https://synthetic-owner-transfer-upgrade.example/auth/v1'
          AND subject = 'owner'
          AND app_user_id =
            '00000000-0085-0000-0000-000000000501'::uuid) <> 1
    OR (SELECT count(*) FROM app_data.external_identities) <> 1
    OR (SELECT count(*)
        FROM app_data.workspaces
        WHERE workspace_id = receipt.organization_workspace_id
          AND workspace_kind = 'organization'
          AND display_name = '0085 Owner transfer upgrade organization'
          AND personal_owner_app_user_id IS NULL
          AND deleted_at IS NULL
          AND created_at = receipt.created_at_utc) <> 1
    OR (SELECT count(*)
        FROM app_data.organization_memberships
        WHERE organization_membership_id = receipt.organization_membership_id
          AND organization_workspace_id = receipt.organization_workspace_id
          AND app_user_id =
            '00000000-0085-0000-0000-000000000501'::uuid
          AND active_from_utc = receipt.created_at_utc
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*)
        FROM app_data.organization_memberships
        WHERE organization_membership_id =
            '00000000-0085-3000-0000-000000000502'::uuid
          AND organization_workspace_id = receipt.organization_workspace_id
          AND app_user_id =
            '00000000-0085-0000-0000-000000000502'::uuid
          AND active_from_utc = receipt.created_at_utc
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.organization_memberships) <> 2
    OR (SELECT count(*)
        FROM app_data.organization_owner_assignments
        WHERE organization_owner_assignment_id =
            receipt.organization_owner_assignment_id
          AND organization_membership_id = receipt.organization_membership_id
          AND active_from_utc = receipt.created_at_utc
          AND inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*) FROM app_data.organization_owner_assignments) <> 1
    OR EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments
      WHERE organization_membership_id =
        '00000000-0085-3000-0000-000000000502'::uuid
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.external_identities
      WHERE app_user_id =
        '00000000-0085-0000-0000-000000000502'::uuid
    )
    OR (SELECT count(*) FROM app_data.projects) <> 0
    OR (SELECT count(*) FROM app_data.project_memberships) <> 0
    OR (SELECT count(*)
        FROM app_data.management_report_capability_grants) <> 0
    OR (SELECT count(*) FROM app_data.promotion_target_assignments) <> 0
  THEN
    RAISE EXCEPTION '0085 owner-transfer baseline drift';
  END IF;
END
$legacy$;

TABLE fixture_0085_creation_receipt;
