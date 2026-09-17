-- 后续合法 handoff 保留 successor；旧 actor 与 target 的 parent 随后结束。
\set ON_ERROR_STOP on

SELECT organization_workspace_id FROM app_private.organization_owner_transfer_request_claims
WHERE request_id = '00000000-0096-6000-0000-000000000702'
\gset legacy_
BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $check$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0098_organization_owner_transfer_effective_time'
    OR NOT EXISTS (SELECT 1 FROM app_migrations.schema_migrations
      WHERE version = '0097_organization_owner_transfer_finite_parent')
  THEN RAISE EXCEPTION 'legacy claim upgrade must apply only 0097 and 0098'; END IF;
END
$check$;
SET LOCAL ROLE tongxingzhe_runtime;
SELECT * FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-owner-claim-upgrade.example/auth/v1', 'original-target',
  '00000000-0096-6000-0000-000000000703', :'legacy_organization_workspace_id',
  '00000000-0096-3000-0000-000000000703')
\gset successor_
RESET ROLE;
UPDATE app_data.organization_memberships SET inactive_from_utc = transaction_timestamp()
WHERE organization_workspace_id = :'legacy_organization_workspace_id'
  AND app_user_id IN ('00000000-0096-0000-0000-000000000701', '00000000-0096-0000-0000-000000000702');
DO $check$
DECLARE claim app_private.organization_owner_transfer_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT claim FROM app_private.organization_owner_transfer_request_claims
  WHERE request_id = '00000000-0096-6000-0000-000000000702';
  IF (SELECT status FROM app_data.app_users
      WHERE app_user_id = claim.actor_app_user_id) IS DISTINCT FROM 'active'
    OR (SELECT count(*) FROM app_data.organization_memberships
      WHERE organization_workspace_id = claim.organization_workspace_id
        AND app_user_id IN ('00000000-0096-0000-0000-000000000701', '00000000-0096-0000-0000-000000000702')
        AND inactive_from_utc = transaction_timestamp()) <> 2
    OR (SELECT count(*) FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id IN (claim.previous_owner_assignment_id, claim.organization_owner_assignment_id)
        AND inactive_from_utc IS NOT NULL AND inactive_from_utc <= transaction_timestamp()) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_owner_assignments AS owner
      JOIN app_data.organization_memberships AS member USING (organization_membership_id)
      JOIN app_data.app_users AS app_user USING (app_user_id)
      WHERE member.organization_workspace_id = claim.organization_workspace_id
        AND app_user.app_user_id = '00000000-0096-0000-0000-000000000703'
        AND app_user.status = 'active' AND member.inactive_from_utc IS NULL AND owner.inactive_from_utc IS NULL)
  THEN RAISE EXCEPTION 'legacy replay setup requires ended relationships, active original actor and active successor'; END IF;
END
$check$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
