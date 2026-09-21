-- 0087 基线的真实成功 claim；创建与 handoff 分属已提交事务。
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $baseline$
DECLARE
  definition text;
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0087_organization_directed_account_invitation'
  THEN
    RAISE EXCEPTION '0087 owner-transfer seed requires the exact baseline';
  END IF;

  SELECT pg_get_functiondef(
    'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure
  ) INTO STRICT definition;
  IF position('authorization_time' IN definition) > 0
    OR regexp_count(definition, '@>[[:space:]]*effective_time') <> 4
  THEN
    RAISE EXCEPTION '0087 owner-transfer seed requires the original 0086 writer';
  END IF;
END
$baseline$;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0087-0000-0000-000000000701', 'active'),
  ('00000000-0087-0000-0000-000000000702', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES (
  '00000000-0087-1000-0000-000000000701',
  'https://synthetic-owner-authorization-upgrade.example/auth/v1',
  'original-actor',
  '00000000-0087-0000-0000-000000000701'
);

SET LOCAL ROLE tongxingzhe_runtime;
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-owner-authorization-upgrade.example/auth/v1',
  'original-actor',
  '00000000-0087-6000-0000-000000000701',
  '0087 owner authorization upgrade organization'
)
\gset created_
RESET ROLE;

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '00000000-0087-3000-0000-000000000702',
  :'created_organization_workspace_id',
  '00000000-0087-0000-0000-000000000702',
  transaction_timestamp(),
  NULL
);
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0087_owner_transfer_receipt (
  owner_transfer_contract_id text,
  organization_workspace_id uuid,
  previous_owner_assignment_id uuid,
  organization_owner_assignment_id uuid,
  effective_at_utc timestamptz
) ON COMMIT DROP;
GRANT ALL ON fixture_0087_owner_transfer_receipt TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0087_owner_transfer_receipt
SELECT *
FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-owner-authorization-upgrade.example/auth/v1',
  'original-actor',
  '00000000-0087-6000-0000-000000000702',
  :'created_organization_workspace_id',
  '00000000-0087-3000-0000-000000000702'
);
RESET ROLE;

DO $committed_handoff$
DECLARE
  claim app_private.organization_owner_transfer_request_claims%ROWTYPE;
  receipt fixture_0087_owner_transfer_receipt%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM fixture_0087_owner_transfer_receipt;
  SELECT * INTO STRICT claim
  FROM app_private.organization_owner_transfer_request_claims
  WHERE request_id = '00000000-0087-6000-0000-000000000702';

  IF receipt.owner_transfer_contract_id IS DISTINCT FROM
      'organization-owner-transfer:v1'
    OR claim.actor_app_user_id IS DISTINCT FROM
      '00000000-0087-0000-0000-000000000701'::uuid
    OR claim.organization_workspace_id IS DISTINCT FROM
      receipt.organization_workspace_id
    OR claim.target_organization_membership_id IS DISTINCT FROM
      '00000000-0087-3000-0000-000000000702'::uuid
    OR claim.previous_owner_assignment_id IS DISTINCT FROM
      receipt.previous_owner_assignment_id
    OR claim.organization_owner_assignment_id IS DISTINCT FROM
      receipt.organization_owner_assignment_id
    OR claim.effective_at_utc IS DISTINCT FROM
      receipt.effective_at_utc
    OR claim.effective_at_utc IS DISTINCT FROM transaction_timestamp()
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments AS assignment
      JOIN app_data.organization_memberships AS membership
        ON membership.organization_membership_id =
          assignment.organization_membership_id
      WHERE assignment.organization_owner_assignment_id =
          claim.previous_owner_assignment_id
        AND membership.app_user_id =
          '00000000-0087-0000-0000-000000000701'::uuid
        AND assignment.inactive_from_utc = claim.effective_at_utc
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.organization_owner_assignments AS assignment
      WHERE assignment.organization_owner_assignment_id =
          claim.organization_owner_assignment_id
        AND assignment.organization_membership_id =
          claim.target_organization_membership_id
        AND assignment.active_from_utc = claim.effective_at_utc
        AND assignment.inactive_from_utc IS NULL
    )
    OR (SELECT count(*)
        FROM app_data.organization_owner_assignments AS assignment
        JOIN app_data.organization_memberships AS membership
          ON membership.organization_membership_id =
            assignment.organization_membership_id
        WHERE membership.organization_workspace_id =
            claim.organization_workspace_id
          AND assignment.inactive_from_utc IS NULL) <> 1
    OR (SELECT count(*)
        FROM app_data.organization_owner_assignments AS assignment
        JOIN app_data.organization_memberships AS membership
          ON membership.organization_membership_id =
            assignment.organization_membership_id
        WHERE membership.organization_workspace_id =
          claim.organization_workspace_id) <> 2
    OR (SELECT count(*)
        FROM app_private.organization_owner_transfer_request_claims
        WHERE organization_workspace_id = claim.organization_workspace_id) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_owner_transfer_audit_events
        WHERE organization_workspace_id = claim.organization_workspace_id) <> 1
    OR (SELECT count(*)
        FROM app_private.organization_owner_transfer_audit_events AS audit
        WHERE audit.request_id = claim.request_id
          AND audit.owner_transfer_contract_id =
            'organization-owner-transfer:v1'
          AND audit.organization_workspace_id =
            claim.organization_workspace_id
          AND audit.previous_owner_assignment_id =
            claim.previous_owner_assignment_id
          AND audit.organization_owner_assignment_id =
            claim.organization_owner_assignment_id
          AND audit.effective_at_utc = claim.effective_at_utc) <> 1
  THEN
    RAISE EXCEPTION
      '0087 old writer did not commit the expected owner, claim, audit, and receipt';
  END IF;
END
$committed_handoff$;

TABLE fixture_0087_owner_transfer_receipt;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
