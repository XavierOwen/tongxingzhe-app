-- A committed 0095 approval lineage for the staged 0096 assignment upgrade.

\set ON_ERROR_STOP on
\set QUIET on

SET TIME ZONE 'UTC';

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0095-0000-0000-000000000901', 'active'),
  ('00000000-0095-0000-0000-000000000902', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  ('00000000-0095-1000-0000-000000000901',
    'https://synthetic-project-assignment-upgrade.example/auth/v1', 'owner',
    '00000000-0095-0000-0000-000000000901'),
  ('00000000-0095-1000-0000-000000000902',
    'https://synthetic-project-assignment-upgrade.example/auth/v1', 'member',
    '00000000-0095-0000-0000-000000000902');

CREATE TEMP TABLE fixture_0095_creation_receipt (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
);
CREATE TEMP TABLE fixture_0095_link_receipt (
  organization_shareable_join_link_contract_id text,
  link_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
);
CREATE TEMP TABLE fixture_0095_submission_receipt (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  link_id uuid,
  organization_workspace_id uuid,
  submitted_at_utc timestamptz,
  expires_at_utc timestamptz
);
CREATE TEMP TABLE fixture_0095_approval_receipt (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  approved_at_utc timestamptz
);
GRANT ALL ON fixture_0095_creation_receipt,
  fixture_0095_link_receipt,
  fixture_0095_submission_receipt,
  fixture_0095_approval_receipt
  TO tongxingzhe_runtime;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0095_creation_receipt
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-project-assignment-upgrade.example/auth/v1',
  'owner',
  '00000000-0095-5000-0000-000000000901',
  '0095 Project assignment upgrade organization'
);
COMMIT;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0095_link_receipt
SELECT link.*
FROM fixture_0095_creation_receipt AS creation
CROSS JOIN LATERAL
  app_data.create_organization_shareable_join_link_for_identity_v1(
    'https://synthetic-project-assignment-upgrade.example/auth/v1',
    'owner',
    '00000000-0095-6000-0000-000000000901',
    creation.organization_workspace_id
  ) AS link;
COMMIT;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0095_submission_receipt
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-project-assignment-upgrade.example/auth/v1',
  'member',
  '00000000-0095-7000-0000-000000000901',
  '00000000-0095-6000-0000-000000000901'
);
COMMIT;

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0095_approval_receipt
SELECT approval.*
FROM fixture_0095_creation_receipt AS creation
CROSS JOIN LATERAL
  app_data.approve_organization_shareable_join_application_for_identity_v1(
    'https://synthetic-project-assignment-upgrade.example/auth/v1',
    'owner',
    '00000000-0095-7000-0000-000000000901',
    creation.organization_workspace_id
  ) AS approval;
COMMIT;

-- The repository has no organization-project creation writer. This fixture
-- seeds only the active project needed to prove the assignment upgrade.
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
SELECT
  '00000000-0095-8000-0000-000000000901',
  creation.organization_workspace_id,
  '0095 Project assignment upgrade project'
FROM fixture_0095_creation_receipt AS creation;

DO $legacy$
DECLARE
  creation fixture_0095_creation_receipt%ROWTYPE;
  link fixture_0095_link_receipt%ROWTYPE;
  submitted fixture_0095_submission_receipt%ROWTYPE;
  approved fixture_0095_approval_receipt%ROWTYPE;
  link_claim
    app_private.organization_shareable_join_link_request_claims%ROWTYPE;
  application_claim
    app_private.organization_shareable_join_application_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT creation FROM fixture_0095_creation_receipt;
  SELECT * INTO STRICT link FROM fixture_0095_link_receipt;
  SELECT * INTO STRICT submitted FROM fixture_0095_submission_receipt;
  SELECT * INTO STRICT approved FROM fixture_0095_approval_receipt;
  SELECT * INTO STRICT link_claim
  FROM app_private.organization_shareable_join_link_request_claims
  WHERE link_id = link.link_id;
  SELECT * INTO STRICT application_claim
  FROM app_private.organization_shareable_join_application_request_claims
  WHERE application_id = submitted.application_id;

  IF creation.creation_contract_id IS DISTINCT FROM 'organization-creation:v1'
    OR link.organization_shareable_join_link_contract_id IS DISTINCT FROM
      'organization-shareable-join-link:v1'
    OR submitted.organization_shareable_join_application_contract_id
      IS DISTINCT FROM 'organization-shareable-join-application:v1'
    OR approved.organization_shareable_join_application_contract_id
      IS DISTINCT FROM 'organization-shareable-join-application:v1'
    OR (SELECT count(*) FROM fixture_0095_creation_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0095_link_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0095_submission_receipt) <> 1
    OR (SELECT count(*) FROM fixture_0095_approval_receipt) <> 1
    OR link.link_id IS DISTINCT FROM
      '00000000-0095-6000-0000-000000000901'::uuid
    OR submitted.application_id IS DISTINCT FROM
      '00000000-0095-7000-0000-000000000901'::uuid
    OR submitted.link_id IS DISTINCT FROM link.link_id
    OR link.organization_workspace_id IS DISTINCT FROM
      creation.organization_workspace_id
    OR submitted.organization_workspace_id IS DISTINCT FROM
      creation.organization_workspace_id
    OR approved.application_id IS DISTINCT FROM submitted.application_id
    OR approved.organization_workspace_id IS DISTINCT FROM
      creation.organization_workspace_id
    OR link_claim.organization_workspace_id IS DISTINCT FROM
      link.organization_workspace_id
    OR link_claim.creator_app_user_id IS DISTINCT FROM
      '00000000-0095-0000-0000-000000000901'::uuid
    OR link_claim.issued_at_utc IS DISTINCT FROM link.issued_at_utc
    OR link_claim.expires_at_utc IS DISTINCT FROM link.expires_at_utc
    OR link.expires_at_utc IS DISTINCT FROM
      link.issued_at_utc + interval '168 hours'
    OR application_claim.link_id IS DISTINCT FROM submitted.link_id
    OR application_claim.organization_workspace_id IS DISTINCT FROM
      submitted.organization_workspace_id
    OR application_claim.applicant_app_user_id IS DISTINCT FROM
      '00000000-0095-0000-0000-000000000902'::uuid
    OR application_claim.submitted_at_utc IS DISTINCT FROM
      submitted.submitted_at_utc
    OR application_claim.expires_at_utc IS DISTINCT FROM
      submitted.expires_at_utc
    OR submitted.expires_at_utc IS DISTINCT FROM
      submitted.submitted_at_utc + interval '168 hours'
    OR application_claim.approved_organization_membership_id
      IS DISTINCT FROM approved.organization_membership_id
    OR application_claim.approved_at_utc IS DISTINCT FROM
      approved.approved_at_utc
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_membership_id =
          creation.organization_membership_id
        AND membership.organization_workspace_id =
          creation.organization_workspace_id
        AND membership.app_user_id =
          '00000000-0095-0000-0000-000000000901'::uuid
        AND membership.active_from_utc = creation.created_at_utc
        AND membership.inactive_from_utc IS NULL
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments AS assignment
      WHERE assignment.organization_owner_assignment_id =
          creation.organization_owner_assignment_id
        AND assignment.organization_membership_id =
          creation.organization_membership_id
        AND assignment.active_from_utc = creation.created_at_utc
        AND assignment.inactive_from_utc IS NULL
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_membership_id =
          approved.organization_membership_id
        AND membership.organization_workspace_id =
          approved.organization_workspace_id
        AND membership.app_user_id =
          '00000000-0095-0000-0000-000000000902'::uuid
        AND membership.active_from_utc = approved.approved_at_utc
        AND membership.inactive_from_utc IS NULL
    )
    OR (SELECT count(*)
        FROM app_private.organization_shareable_join_link_audit_events
        WHERE link_id = link.link_id
          AND organization_shareable_join_link_contract_id =
            link.organization_shareable_join_link_contract_id
          AND organization_workspace_id = link.organization_workspace_id
          AND event_kind = 'link_created'
          AND issued_at_utc = link.issued_at_utc
          AND expires_at_utc = link.expires_at_utc) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_shareable_join_application_audit_events
        WHERE application_id = submitted.application_id
          AND organization_shareable_join_application_contract_id =
            submitted.organization_shareable_join_application_contract_id
          AND link_id = submitted.link_id
          AND organization_workspace_id = submitted.organization_workspace_id
          AND event_kind = 'application_submitted'
          AND organization_membership_id IS NULL
          AND occurred_at_utc = submitted.submitted_at_utc) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_shareable_join_application_audit_events
        WHERE application_id = approved.application_id
          AND organization_shareable_join_application_contract_id =
            approved.organization_shareable_join_application_contract_id
          AND link_id = submitted.link_id
          AND organization_workspace_id = approved.organization_workspace_id
          AND event_kind = 'application_approved'
          AND organization_membership_id = approved.organization_membership_id
          AND occurred_at_utc = approved.approved_at_utc) <> 1
    OR (SELECT count(*)
        FROM app_data.organization_memberships
        WHERE organization_workspace_id = creation.organization_workspace_id)
      <> 2
    OR (SELECT count(*) FROM app_data.organization_owner_assignments) <> 1
    OR (SELECT count(*)
        FROM app_data.projects
        WHERE project_id = '00000000-0095-8000-0000-000000000901'::uuid
          AND workspace_id = creation.organization_workspace_id
          AND status = 'active') <> 1
    OR (SELECT count(*) FROM app_data.project_memberships) <> 0
    OR (SELECT count(*)
        FROM app_data.management_report_capability_grants) <> 0
    OR (SELECT count(*) FROM app_data.promotion_target_assignments) <> 0
  THEN
    RAISE EXCEPTION '0095 approved membership assignment baseline drift';
  END IF;
END
$legacy$;

TABLE fixture_0095_approval_receipt;
