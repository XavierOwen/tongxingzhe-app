-- Synthetic setup and two legal handoffs commit so owner intervals can close
-- in later transactions. Every run uses random UUIDs; final replay rolls back.
-- No replication role, immutable-guard exception or deletion is used.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0097_members AS
SELECT kind, gen_random_uuid() AS app_user_id, gen_random_uuid() AS membership_id
FROM (VALUES ('actor'), ('finite'), ('unended'), ('expired'), ('future'), ('successor')) AS kinds(kind);
INSERT INTO app_data.app_users(app_user_id, status)
SELECT app_user_id, 'active' FROM fixture_0097_members;
INSERT INTO app_data.external_identities(external_identity_id, issuer, subject, app_user_id)
SELECT gen_random_uuid(), 'https://synthetic-0097.example', app_user_id::text, app_user_id
FROM fixture_0097_members WHERE kind IN ('actor', 'unended');
CREATE TEMP TABLE fixture_0097_org AS
SELECT receipt.* FROM fixture_0097_members AS actor,
LATERAL app_private.create_organization_v1(actor.app_user_id, gen_random_uuid(), '0097 synthetic organization') AS receipt
WHERE actor.kind = 'actor';
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id, active_from_utc, inactive_from_utc
)
SELECT member.membership_id, org.organization_workspace_id, member.app_user_id,
  CASE WHEN member.kind = 'future' THEN transaction_timestamp() + interval '1 day'
    ELSE transaction_timestamp() - interval '1 day' END,
  CASE WHEN member.kind = 'finite' THEN transaction_timestamp() + interval '1 day'
    WHEN member.kind = 'expired' THEN transaction_timestamp() - interval '1 hour' ELSE NULL END
FROM fixture_0097_members AS member CROSS JOIN fixture_0097_org AS org
WHERE member.kind <> 'actor';
GRANT SELECT ON fixture_0097_members, fixture_0097_org TO tongxingzhe_runtime;
COMMIT;

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;
SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE target_id uuid; actual_state text; actual_message text;
  actor_subject text := (SELECT app_user_id::text FROM fixture_0097_members WHERE kind = 'actor');
  org_id uuid := (SELECT organization_workspace_id FROM fixture_0097_org);
BEGIN
  FOR target_id IN SELECT membership_id FROM fixture_0097_members WHERE kind IN ('finite', 'expired', 'future') LOOP
    actual_state := NULL;
    actual_message := NULL;
    BEGIN
      PERFORM * FROM app_data.transfer_organization_owner_for_identity_v1(
        'https://synthetic-0097.example', actor_subject, gen_random_uuid(), org_id, target_id);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
    END;
    IF actual_state IS DISTINCT FROM '42501' OR actual_message IS DISTINCT FROM 'organization owner transfer forbidden' THEN
      RAISE EXCEPTION '0097 expected exact forbidden, got % / %', actual_state, actual_message;
    END IF;
  END LOOP;
END
$fixture$;
RESET ROLE;
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0097_org);
BEGIN
  IF (SELECT count(*) FROM app_data.organization_owner_assignments AS owner
      JOIN app_data.organization_memberships AS member USING(organization_membership_id)
      WHERE member.organization_workspace_id = org_id) <> 1
    OR EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_request_claims WHERE organization_workspace_id = org_id)
    OR EXISTS (SELECT 1 FROM app_private.organization_owner_transfer_audit_events WHERE organization_workspace_id = org_id)
    OR (SELECT inactive_from_utc FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = (SELECT organization_owner_assignment_id FROM fixture_0097_org)) IS NOT NULL
  THEN RAISE EXCEPTION '0097 rejected transfer changed owner, claim or audit facts'; END IF;
END
$fixture$;

CREATE TEMP TABLE fixture_0097_request AS SELECT gen_random_uuid() AS request_id;
GRANT SELECT ON fixture_0097_request TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0097_first AS
SELECT receipt.* FROM fixture_0097_members AS actor CROSS JOIN fixture_0097_org AS org
CROSS JOIN fixture_0097_members AS target CROSS JOIN fixture_0097_request AS request,
LATERAL app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0097.example', actor.app_user_id::text, request.request_id,
  org.organization_workspace_id, target.membership_id) AS receipt
WHERE actor.kind = 'actor' AND target.kind = 'unended';
RESET ROLE;
DO $fixture$
DECLARE receipt fixture_0097_first%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM fixture_0097_first;
  IF receipt.owner_transfer_contract_id <> 'organization-owner-transfer:v1'
    OR receipt.previous_owner_assignment_id <> (SELECT organization_owner_assignment_id FROM fixture_0097_org)
    OR receipt.effective_at_utc <> transaction_timestamp()
    OR (SELECT inactive_from_utc FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = receipt.previous_owner_assignment_id) IS DISTINCT FROM receipt.effective_at_utc
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = receipt.organization_owner_assignment_id
        AND organization_membership_id = (SELECT membership_id FROM fixture_0097_members WHERE kind = 'unended')
        AND active_from_utc = receipt.effective_at_utc AND inactive_from_utc IS NULL)
    OR (SELECT count(*) FROM app_private.organization_owner_transfer_request_claims
      WHERE organization_workspace_id = receipt.organization_workspace_id) <> 1
    OR (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events
      WHERE organization_workspace_id = receipt.organization_workspace_id) <> 1
  THEN RAISE EXCEPTION '0097 unended handoff drift'; END IF;
END
$fixture$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

-- A later legal handoff closes the original target assignment while retaining
-- an active successor owner; only then may its parent membership end.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL ROLE tongxingzhe_runtime;
SELECT receipt.* FROM fixture_0097_members AS actor CROSS JOIN fixture_0097_org AS org
CROSS JOIN fixture_0097_members AS target,
LATERAL app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0097.example', actor.app_user_id::text, gen_random_uuid(),
  org.organization_workspace_id, target.membership_id) AS receipt
WHERE actor.kind = 'unended' AND target.kind = 'successor';
RESET ROLE;
UPDATE app_data.organization_memberships SET inactive_from_utc = transaction_timestamp()
WHERE organization_membership_id = (SELECT membership_id FROM fixture_0097_members WHERE kind = 'unended');
DO $fixture$
BEGIN
  IF (SELECT inactive_from_utc FROM app_data.organization_owner_assignments
      WHERE organization_owner_assignment_id = (SELECT organization_owner_assignment_id FROM fixture_0097_first))
      IS DISTINCT FROM transaction_timestamp()
    OR transaction_timestamp() <= (SELECT effective_at_utc FROM fixture_0097_first)
  THEN RAISE EXCEPTION '0097 original target owner did not legally end in a later transaction'; END IF;
END
$fixture$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;

BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0097_before_replay AS
SELECT
  (SELECT count(*) FROM app_data.organization_owner_assignments AS owner
    JOIN app_data.organization_memberships AS member USING(organization_membership_id)
    WHERE member.organization_workspace_id = org.organization_workspace_id) AS owners,
  (SELECT count(*) FROM app_private.organization_owner_transfer_request_claims
    WHERE organization_workspace_id = org.organization_workspace_id) AS claims,
  (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events
    WHERE organization_workspace_id = org.organization_workspace_id) AS audits
FROM fixture_0097_org AS org;
-- Exact replay ignores both the ended parent and the target's later account
-- state, while the original actor remains active but is no longer an owner.
UPDATE app_data.app_users SET status = 'deletion_pending'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0097_members WHERE kind = 'unended');
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0097_replay AS
SELECT receipt.* FROM fixture_0097_members AS actor CROSS JOIN fixture_0097_org AS org
CROSS JOIN fixture_0097_members AS target CROSS JOIN fixture_0097_request AS request,
LATERAL app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0097.example', actor.app_user_id::text, request.request_id,
  org.organization_workspace_id, target.membership_id) AS receipt
WHERE actor.kind = 'actor' AND target.kind = 'unended';
RESET ROLE;
DO $fixture$
DECLARE before_counts fixture_0097_before_replay%ROWTYPE;
  after_counts fixture_0097_before_replay%ROWTYPE;
  org_id uuid := (SELECT organization_workspace_id FROM fixture_0097_org);
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0097_before_replay;
  SELECT
    (SELECT count(*) FROM app_data.organization_owner_assignments AS owner
      JOIN app_data.organization_memberships AS member USING(organization_membership_id)
      WHERE member.organization_workspace_id = org_id),
    (SELECT count(*) FROM app_private.organization_owner_transfer_request_claims WHERE organization_workspace_id = org_id),
    (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events WHERE organization_workspace_id = org_id)
  INTO after_counts;
  IF EXISTS ((TABLE fixture_0097_first EXCEPT TABLE fixture_0097_replay)
    UNION ALL (TABLE fixture_0097_replay EXCEPT TABLE fixture_0097_first))
    OR after_counts IS DISTINCT FROM before_counts
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_memberships
      WHERE organization_membership_id = (SELECT membership_id FROM fixture_0097_members WHERE kind = 'unended')
        AND inactive_from_utc IS NOT NULL AND inactive_from_utc <= clock_timestamp())
    OR (SELECT status FROM app_data.app_users
      WHERE app_user_id = (SELECT app_user_id FROM fixture_0097_members WHERE kind = 'actor')) <> 'active'
  THEN RAISE EXCEPTION '0097 ended-parent historical replay changed receipt or appended facts'; END IF;
END
$fixture$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
