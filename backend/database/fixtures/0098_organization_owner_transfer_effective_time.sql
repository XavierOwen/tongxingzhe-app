-- Random synthetic setup commits so the first owner has an older valid start.
-- Equality-boundary business calls roll back; no replication/guard exception.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0098_seed AS SELECT
  gen_random_uuid() AS actor_id, gen_random_uuid() AS target_id,
  gen_random_uuid() AS target_membership_id, gen_random_uuid() AS equal_owner_target_membership_id,
  gen_random_uuid() AS first_request_id, gen_random_uuid() AS equal_owner_request_id;
INSERT INTO app_data.app_users(app_user_id, status)
SELECT actor_id, 'active' FROM fixture_0098_seed UNION ALL SELECT target_id, 'active' FROM fixture_0098_seed;
INSERT INTO app_data.external_identities(external_identity_id, issuer, subject, app_user_id)
SELECT gen_random_uuid(), 'https://synthetic-0098.example', actor_id::text, actor_id FROM fixture_0098_seed;
CREATE TEMP TABLE fixture_0098_org AS
SELECT receipt.* FROM fixture_0098_seed AS seed,
LATERAL app_private.create_organization_v1(seed.actor_id, gen_random_uuid(), '0098 synthetic equality boundaries') AS receipt;
GRANT SELECT ON fixture_0098_seed, fixture_0098_org TO tongxingzhe_runtime;
COMMIT;

BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO app_data.organization_memberships
SELECT seed.target_membership_id, org.organization_workspace_id, seed.target_id, transaction_timestamp(), NULL
FROM fixture_0098_seed AS seed CROSS JOIN fixture_0098_org AS org;
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0098_first AS
SELECT receipt.* FROM fixture_0098_seed AS seed CROSS JOIN fixture_0098_org AS org,
LATERAL app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0098.example', seed.actor_id::text, seed.first_request_id,
  org.organization_workspace_id, seed.target_membership_id) AS receipt;
RESET ROLE;
DO $fixture$
DECLARE receipt fixture_0098_first%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM fixture_0098_first;
  IF receipt.effective_at_utc <> transaction_timestamp()
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_owner_assignments AS owner
      JOIN app_data.organization_memberships AS parent USING(organization_membership_id)
      WHERE owner.organization_owner_assignment_id = receipt.organization_owner_assignment_id
        AND parent.active_from_utc = receipt.effective_at_utc
        AND owner.active_from_utc = parent.active_from_utc AND owner.inactive_from_utc IS NULL)
    OR (SELECT inactive_from_utc FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = receipt.previous_owner_assignment_id) IS DISTINCT FROM receipt.effective_at_utc
  THEN RAISE EXCEPTION '0098 target parent start equality must allow a contained grant'; END IF;
END
$fixture$;

-- A newly created owner's start equals this transaction's immutable close
-- time. Reject before writing rather than attempting a zero-length interval.
CREATE TEMP TABLE fixture_0098_equal_owner_org AS
SELECT receipt.* FROM fixture_0098_seed AS seed,
LATERAL app_private.create_organization_v1(seed.actor_id, gen_random_uuid(), '0098 same-transaction owner') AS receipt;
INSERT INTO app_data.organization_memberships
SELECT seed.equal_owner_target_membership_id, org.organization_workspace_id, seed.target_id, transaction_timestamp(), NULL
FROM fixture_0098_seed AS seed CROSS JOIN fixture_0098_equal_owner_org AS org;
GRANT SELECT ON fixture_0098_equal_owner_org TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE actual_state text; actual_message text;
  seed fixture_0098_seed%ROWTYPE;
  org_id uuid := (SELECT organization_workspace_id FROM fixture_0098_equal_owner_org);
BEGIN
  SELECT * INTO STRICT seed FROM fixture_0098_seed;
  BEGIN
    PERFORM * FROM app_data.transfer_organization_owner_for_identity_v1(
      'https://synthetic-0098.example', seed.actor_id::text, seed.equal_owner_request_id,
      org_id, seed.equal_owner_target_membership_id);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '42501' OR actual_message IS DISTINCT FROM 'organization owner transfer forbidden'
  THEN RAISE EXCEPTION '0098 equal owner start expected exact forbidden, got % / %', actual_state, actual_message; END IF;
END
$fixture$;
RESET ROLE;
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0098_equal_owner_org);
BEGIN
  IF (SELECT count(*) FROM app_data.organization_owner_assignments AS owner
      JOIN app_data.organization_memberships AS member USING(organization_membership_id)
      WHERE member.organization_workspace_id = org_id) <> 1
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = (SELECT organization_owner_assignment_id FROM fixture_0098_equal_owner_org)
        AND active_from_utc = transaction_timestamp() AND inactive_from_utc IS NULL)
    OR EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_request_claims WHERE organization_workspace_id = org_id)
    OR EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_audit_events WHERE organization_workspace_id = org_id)
  THEN RAISE EXCEPTION '0098 equal owner start rejection wrote partial facts'; END IF;
END
$fixture$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
