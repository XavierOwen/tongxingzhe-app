\set ON_ERROR_STOP on

SELECT organization_workspace_id FROM app_private.organization_owner_transfer_request_claims
WHERE request_id = '00000000-0096-6000-0000-000000000702'
\gset legacy_
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL ROLE tongxingzhe_runtime;
SELECT * FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-owner-claim-upgrade.example/auth/v1', 'original-actor',
  '00000000-0096-6000-0000-000000000702', :'legacy_organization_workspace_id',
  '00000000-0096-3000-0000-000000000702');
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
