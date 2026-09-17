-- 0096 基线的真实成功 claim；创建与 handoff 分属已提交事务。
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $check$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0096_organization_project_membership_assignment'
    OR position('OR target_membership_row.inactive_from_utc IS NOT NULL' IN
      pg_get_functiondef('app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure)) > 0
  THEN RAISE EXCEPTION 'owner claim seed requires the actual pre-0097 writer'; END IF;
END
$check$;
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0096-0000-0000-000000000701', 'active'),
  ('00000000-0096-0000-0000-000000000702', 'active'),
  ('00000000-0096-0000-0000-000000000703', 'active');
INSERT INTO app_data.external_identities (external_identity_id, issuer, subject, app_user_id)
VALUES
  ('00000000-0096-1000-0000-000000000701', 'https://synthetic-owner-claim-upgrade.example/auth/v1',
    'original-actor', '00000000-0096-0000-0000-000000000701'),
  ('00000000-0096-1000-0000-000000000702', 'https://synthetic-owner-claim-upgrade.example/auth/v1',
    'original-target', '00000000-0096-0000-0000-000000000702');
SET LOCAL ROLE tongxingzhe_runtime;
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-owner-claim-upgrade.example/auth/v1', 'original-actor',
  '00000000-0096-6000-0000-000000000701', '0096 owner claim upgrade organization')
\gset created_
RESET ROLE;
INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id, active_from_utc, inactive_from_utc
)
VALUES
  ('00000000-0096-3000-0000-000000000702', :'created_organization_workspace_id',
    '00000000-0096-0000-0000-000000000702', transaction_timestamp(), NULL),
  ('00000000-0096-3000-0000-000000000703', :'created_organization_workspace_id',
    '00000000-0096-0000-0000-000000000703', transaction_timestamp(), NULL);
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL ROLE tongxingzhe_runtime;
SELECT * FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-owner-claim-upgrade.example/auth/v1', 'original-actor',
  '00000000-0096-6000-0000-000000000702', :'created_organization_workspace_id',
  '00000000-0096-3000-0000-000000000702');
RESET ROLE;
DO $check$
DECLARE claim app_private.organization_owner_transfer_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT claim FROM app_private.organization_owner_transfer_request_claims
  WHERE request_id = '00000000-0096-6000-0000-000000000702';
  IF claim.actor_app_user_id <> '00000000-0096-0000-0000-000000000701'::uuid
    OR claim.target_organization_membership_id <> '00000000-0096-3000-0000-000000000702'::uuid
    OR claim.effective_at_utc <> transaction_timestamp()
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = claim.previous_owner_assignment_id
        AND inactive_from_utc = claim.effective_at_utc)
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = claim.organization_owner_assignment_id
        AND active_from_utc = claim.effective_at_utc AND inactive_from_utc IS NULL)
    OR (SELECT count(*) FROM app_private.organization_owner_transfer_request_claims
      WHERE organization_workspace_id = claim.organization_workspace_id) <> 1
    OR (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events
      WHERE organization_workspace_id = claim.organization_workspace_id) <> 1
  THEN RAISE EXCEPTION 'legacy handoff did not commit the expected owner, claim and audit facts'; END IF;
END
$check$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
