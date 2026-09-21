-- An ordinary member committed by the shipped 0084 and 0087 runtime writers.
\set ON_ERROR_STOP on
\set QUIET on

DO $check$
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 88
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0089_organization_directory'
    OR to_regclass(
      'app_private.organization_membership_self_leave_request_claims'
    ) IS NOT NULL
    OR to_regclass(
      'app_private.organization_membership_self_leave_request_tombstones'
    ) IS NOT NULL
    OR to_regclass(
      'app_private.organization_membership_self_leave_audit_events'
    ) IS NOT NULL
    OR to_regprocedure(
      'app_private.leave_organization_membership_v1(uuid,uuid,uuid)'
    ) IS NOT NULL
    OR to_regprocedure(
      'app_data.leave_organization_membership_for_identity_v1(text,text,uuid,uuid)'
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION '0089 membership-self-leave upgrade baseline drift';
  END IF;
END
$check$;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0089-0000-0000-000000000901', 'active'),
  ('00000000-0089-0000-0000-000000000902', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  ('00000000-0089-1000-0000-000000000901',
    'https://synthetic-membership-leave-upgrade.example/auth/v1', 'owner',
    '00000000-0089-0000-0000-000000000901'),
  ('00000000-0089-1000-0000-000000000902',
    'https://synthetic-membership-leave-upgrade.example/auth/v1', 'target',
    '00000000-0089-0000-0000-000000000902');

CREATE TEMP TABLE fixture_0089_creation_receipt (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
);
CREATE TEMP TABLE fixture_0089_invitation_receipt (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
);
CREATE TEMP TABLE fixture_0089_accept_receipt (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
);
GRANT ALL ON fixture_0089_creation_receipt,
  fixture_0089_invitation_receipt,
  fixture_0089_accept_receipt
  TO tongxingzhe_runtime;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0089_creation_receipt
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-membership-leave-upgrade.example/auth/v1',
  'owner',
  '00000000-0089-5000-0000-000000000901',
  '0089 Membership leave upgrade organization'
);
COMMIT;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0089_invitation_receipt
SELECT invitation.*
FROM fixture_0089_creation_receipt AS creation
CROSS JOIN LATERAL
  app_data.create_organization_directed_account_invitation_for_identity_v1(
    'https://synthetic-membership-leave-upgrade.example/auth/v1',
    'owner',
    '00000000-0089-6000-0000-000000000901',
    creation.organization_workspace_id,
    '00000000-0089-0000-0000-000000000902'
  ) AS invitation;
COMMIT;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0089_accept_receipt
SELECT *
FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-membership-leave-upgrade.example/auth/v1',
  'target',
  '00000000-0089-6000-0000-000000000901'
);
COMMIT;

DO $legacy$
DECLARE
  creation fixture_0089_creation_receipt%ROWTYPE;
  invitation fixture_0089_invitation_receipt%ROWTYPE;
  accepted fixture_0089_accept_receipt%ROWTYPE;
  claim
    app_private.organization_directed_account_invitation_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT creation FROM fixture_0089_creation_receipt;
  SELECT * INTO STRICT invitation FROM fixture_0089_invitation_receipt;
  SELECT * INTO STRICT accepted FROM fixture_0089_accept_receipt;
  SELECT * INTO STRICT claim
  FROM app_private.organization_directed_account_invitation_request_claims
  WHERE invitation_id = accepted.invitation_id;

  IF creation.creation_contract_id IS DISTINCT FROM 'organization-creation:v1'
    OR invitation.organization_invitation_contract_id IS DISTINCT FROM
      'organization-directed-account-invitation:v1'
    OR accepted.organization_invitation_contract_id IS DISTINCT FROM
      'organization-directed-account-invitation:v1'
    OR invitation.invitation_id IS DISTINCT FROM accepted.invitation_id
    OR invitation.organization_workspace_id IS DISTINCT FROM
      accepted.organization_workspace_id
    OR creation.organization_workspace_id IS DISTINCT FROM
      accepted.organization_workspace_id
    OR claim.inviter_app_user_id IS DISTINCT FROM
      '00000000-0089-0000-0000-000000000901'::uuid
    OR claim.target_app_user_id IS DISTINCT FROM
      '00000000-0089-0000-0000-000000000902'::uuid
    OR claim.organization_workspace_id IS DISTINCT FROM
      accepted.organization_workspace_id
    OR claim.issued_at_utc IS DISTINCT FROM invitation.issued_at_utc
    OR claim.expires_at_utc IS DISTINCT FROM invitation.expires_at_utc
    OR claim.expires_at_utc IS DISTINCT FROM
      claim.issued_at_utc + interval '168 hours'
    OR claim.accepted_organization_membership_id IS DISTINCT FROM
      accepted.organization_membership_id
    OR claim.accepted_at_utc IS DISTINCT FROM accepted.accepted_at_utc
    OR (SELECT count(*) FROM fixture_0089_creation_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0089_invitation_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0089_accept_receipt) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_request_claims)
      <> 1
    OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_request_tombstones)
      <> 0
    OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_audit_events)
      <> 2
    OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_audit_events
        WHERE invitation_id = claim.invitation_id
          AND event_kind = 'invitation_issued'
          AND organization_membership_id IS NULL
          AND occurred_at_utc = claim.issued_at_utc) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_audit_events
        WHERE invitation_id = claim.invitation_id
          AND event_kind = 'invitation_accepted'
          AND organization_membership_id = accepted.organization_membership_id
          AND occurred_at_utc = accepted.accepted_at_utc) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_membership_id =
          accepted.organization_membership_id
        AND membership.organization_workspace_id =
          accepted.organization_workspace_id
        AND membership.app_user_id =
          '00000000-0089-0000-0000-000000000902'::uuid
        AND membership.active_from_utc = accepted.accepted_at_utc
        AND membership.inactive_from_utc IS NULL
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments AS assignment
      WHERE assignment.organization_membership_id =
        accepted.organization_membership_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.project_memberships AS project_membership
      WHERE project_membership.organization_membership_id =
        accepted.organization_membership_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.management_report_capability_grants AS capability
      JOIN app_data.project_memberships AS project_membership
        ON project_membership.project_membership_id =
          capability.project_membership_id
      WHERE project_membership.organization_membership_id =
        accepted.organization_membership_id
    )
    OR EXISTS (
      SELECT 1
      FROM app_data.promotion_target_assignments AS assignment
      JOIN app_data.promotion_targets AS target
        ON target.promotion_target_id = assignment.promotion_target_id
      WHERE assignment.app_user_id =
          '00000000-0089-0000-0000-000000000902'::uuid
        AND target.workspace_id = accepted.organization_workspace_id
    )
  THEN
    RAISE EXCEPTION '0089 legacy invited membership drift';
  END IF;
END
$legacy$;

SET TIME ZONE 'UTC';
SELECT * FROM fixture_0089_accept_receipt;
