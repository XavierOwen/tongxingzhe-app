-- Random-key owner hierarchies and lifecycle cases are committed so dump/restore
-- can include real private state; the reader observations themselves roll back.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE fixture_0101_clock AS
SELECT clock_timestamp() AS now_utc,
  ' https://synthetic-0101.example/' || gen_random_uuid()::text || ' ' AS issuer;
CREATE TEMP TABLE fixture_0101_users AS
SELECT n, gen_random_uuid() AS user_id
FROM generate_series(1, 4) AS n;
CREATE TEMP TABLE fixture_0101_orgs AS
SELECT n,
  gen_random_uuid() AS workspace_id
FROM generate_series(1, 9) AS n;
CREATE TEMP TABLE fixture_0101_memberships AS
SELECT row_number() OVER () AS n, org_n, user_n,
  gen_random_uuid() AS membership_id,
  gen_random_uuid() AS owner_id
FROM (VALUES (1,1),(1,2),(2,1),(3,1),(4,1),(4,2),(5,1),(6,1),
  (7,1),(7,2),(8,1),(8,2),(9,1)) AS row_data(org_n,user_n);
CREATE TEMP TABLE fixture_0101_attempts AS
SELECT n,workspace_id,gen_random_uuid() AS deletion_request_id
FROM fixture_0101_orgs WHERE n BETWEEN 1 AND 8;

INSERT INTO app_data.app_users(app_user_id,status)
SELECT user_id, CASE WHEN n=4 THEN 'deletion_pending' ELSE 'active' END
FROM fixture_0101_users;
INSERT INTO app_data.external_identities(issuer,subject,app_user_id)
SELECT (SELECT issuer FROM fixture_0101_clock),
  CASE n WHEN 1 THEN ' owner exact ' WHEN 2 THEN 'co-owner' WHEN 3 THEN 'empty' ELSE 'inactive' END,
  user_id FROM fixture_0101_users;
INSERT INTO app_data.workspaces(workspace_id,workspace_kind,display_name,personal_owner_app_user_id,deleted_at)
SELECT org.workspace_id,'organization',
  CASE org.n WHEN 1 THEN 'Beta' WHEN 2 THEN 'Alpha' ELSE 'Case '||org.n END,
  NULL,NULL
FROM fixture_0101_orgs AS org;
INSERT INTO app_data.organization_memberships(
  organization_membership_id,organization_workspace_id,app_user_id,active_from_utc,inactive_from_utc)
SELECT member.membership_id,org.workspace_id,user_row.user_id,
  clock.now_utc - interval '2 hours',
  CASE WHEN member.org_n=7 AND member.user_n=1 THEN clock.now_utc - interval '1 hour' ELSE NULL END
FROM fixture_0101_memberships AS member
JOIN fixture_0101_orgs AS org ON org.n=member.org_n
JOIN fixture_0101_users AS user_row ON user_row.n=member.user_n
CROSS JOIN fixture_0101_clock AS clock;
INSERT INTO app_data.organization_owner_assignments(
  organization_owner_assignment_id,organization_membership_id,active_from_utc,inactive_from_utc)
SELECT member.owner_id,member.membership_id,
  transaction_timestamp(),NULL
FROM fixture_0101_memberships AS member CROSS JOIN fixture_0101_clock AS clock
WHERE member.org_n<>7 OR member.user_n=2;
DO $fixture$
DECLARE orphaned integer[];
BEGIN
  SELECT array_agg(org.n) INTO orphaned
  FROM app_data.workspaces AS workspace
  JOIN fixture_0101_orgs AS org USING (workspace_id)
  WHERE NOT EXISTS (
      SELECT 1 FROM app_data.organization_memberships AS membership
      JOIN app_data.organization_owner_assignments AS assignment
        USING (organization_membership_id)
      JOIN app_data.app_users AS actor USING (app_user_id)
      WHERE membership.organization_workspace_id=workspace.workspace_id
        AND actor.status='active'
        AND tstzrange(membership.active_from_utc,membership.inactive_from_utc,'[)') @> clock_timestamp()
        AND tstzrange(assignment.active_from_utc,assignment.inactive_from_utc,'[)') @> clock_timestamp()
    );
  IF orphaned IS NOT NULL THEN RAISE EXCEPTION 'fixture 0101 orphaned organizations: %',orphaned; END IF;
END
$fixture$;
COMMIT;

BEGIN;
UPDATE app_data.organization_owner_assignments AS assignment
SET inactive_from_utc=transaction_timestamp()
FROM fixture_0101_memberships AS member
WHERE assignment.organization_owner_assignment_id=member.owner_id
  AND member.org_n=8 AND member.user_n=1;
UPDATE app_data.organization_memberships AS membership
SET inactive_from_utc=transaction_timestamp()
FROM fixture_0101_memberships AS member
WHERE membership.organization_membership_id=member.membership_id
  AND member.org_n=8 AND member.user_n=1;
UPDATE app_data.workspaces AS workspace
SET deleted_at=CASE WHEN org.n=4 THEN clock.now_utc + interval '1 hour'
  WHEN org.n=6 THEN clock.now_utc - interval '1 hour' - interval '1 second'
  ELSE clock.now_utc - interval '1 hour' END
FROM fixture_0101_orgs AS org CROSS JOIN fixture_0101_clock AS clock
WHERE workspace.workspace_id=org.workspace_id AND org.n<>5;
INSERT INTO app_private.organization_deletion_current(
  organization_workspace_id,deletion_request_id,effective_at_utc,purge_after_utc,status,restored_at_utc)
SELECT org.workspace_id,
  attempt.deletion_request_id,
  CASE WHEN org.n=3 THEN clock.now_utc - interval '721 hours'
    WHEN org.n=4 THEN clock.now_utc + interval '1 hour'
    ELSE clock.now_utc - interval '1 hour' END,
  CASE WHEN org.n=3 THEN clock.now_utc - interval '1 hour'
    WHEN org.n=4 THEN clock.now_utc + interval '721 hours'
    ELSE clock.now_utc + interval '719 hours' END,
  CASE WHEN org.n=5 THEN 'restored' ELSE 'deletion_pending' END,
  CASE WHEN org.n=5 THEN clock.now_utc - interval '30 minutes' ELSE NULL END
FROM fixture_0101_orgs AS org
JOIN fixture_0101_attempts AS attempt ON attempt.n=org.n
CROSS JOIN fixture_0101_clock AS clock
WHERE org.n BETWEEN 1 AND 8;
COMMIT;

BEGIN;

CREATE TEMP TABLE fixture_0101_before AS
SELECT (SELECT count(*) FROM app_private.organization_deletion_current) AS attempts,
  (SELECT count(*) FROM app_private.organization_deletion_request_claims) AS deletion_claims,
  (SELECT count(*) FROM app_private.organization_deletion_restore_claims) AS restore_claims,
  (SELECT count(*) FROM app_private.organization_deletion_audit_events) AS audit_events;
CREATE TEMP TABLE fixture_0101_failures(
  issuer text, subject text, expected_state text, expected_message text
);
INSERT INTO fixture_0101_failures VALUES
  (NULL,' owner exact ','22023','invalid organization deletion recovery directory identity'),
  (' ',' owner exact ','22023','invalid organization deletion recovery directory identity'),
  (repeat('i',2049),' owner exact ','22023','invalid organization deletion recovery directory identity'),
  ((SELECT issuer FROM fixture_0101_clock),NULL,'22023','invalid organization deletion recovery directory identity'),
  ((SELECT issuer FROM fixture_0101_clock),' ','22023','invalid organization deletion recovery directory identity'),
  ((SELECT issuer FROM fixture_0101_clock),repeat('s',513),'22023','invalid organization deletion recovery directory identity'),
  (btrim((SELECT issuer FROM fixture_0101_clock)),' owner exact ','42501','organization deletion recovery directory forbidden'),
  ((SELECT issuer FROM fixture_0101_clock),'owner exact','42501','organization deletion recovery directory forbidden'),
  ((SELECT issuer FROM fixture_0101_clock),'inactive','42501','organization deletion recovery directory forbidden'),
  ('unknown','unknown','42501','organization deletion recovery directory forbidden');
GRANT SELECT ON fixture_0101_clock,fixture_0101_users,fixture_0101_orgs,
  fixture_0101_memberships,fixture_0101_attempts,fixture_0101_before,
  fixture_0101_failures TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0101_directory AS
SELECT * FROM app_data.list_organization_deletion_recovery_for_identity_v1(
  (SELECT issuer FROM fixture_0101_clock),' owner exact ');
CREATE TEMP TABLE fixture_0101_coowner AS
SELECT * FROM app_data.list_organization_deletion_recovery_for_identity_v1(
  (SELECT issuer FROM fixture_0101_clock),'co-owner');
CREATE TEMP TABLE fixture_0101_empty AS
SELECT * FROM app_data.list_organization_deletion_recovery_for_identity_v1(
  (SELECT issuer FROM fixture_0101_clock),'empty');
DO $fixture$
DECLARE first_row record;
BEGIN
  IF (SELECT count(*) FROM fixture_0101_directory) <> 2
    OR (SELECT count(DISTINCT observed_at_utc) FROM fixture_0101_directory) <> 1
    OR (SELECT array_agg(display_name ORDER BY ordinal)
        FROM (SELECT display_name,row_number() OVER (ORDER BY display_name COLLATE "C",organization_workspace_id) ordinal
              FROM fixture_0101_directory) ordered_rows) IS DISTINCT FROM ARRAY['Alpha','Beta']::text[]
    OR (SELECT count(*) FROM fixture_0101_coowner) <> 3
    OR NOT EXISTS (SELECT 1 FROM fixture_0101_coowner WHERE display_name='Beta')
    OR (SELECT count(*) FROM fixture_0101_empty) <> 0
  THEN RAISE EXCEPTION '0101 exact owner scope, empty result, or stable C ordering drift'; END IF;

  SELECT * INTO STRICT first_row FROM fixture_0101_directory WHERE display_name='Alpha';
  IF first_row.organization_deletion_recovery_directory_contract_id
      IS DISTINCT FROM 'organization-deletion-recovery-directory:v1'
    OR first_row.organization_workspace_id IS DISTINCT FROM
      (SELECT workspace_id FROM fixture_0101_orgs WHERE n=2)
    OR first_row.deletion_request_id IS DISTINCT FROM
      (SELECT deletion_request_id FROM fixture_0101_attempts WHERE n=2)
    OR first_row.status IS DISTINCT FROM 'deletion_pending'
    OR first_row.purge_after_utc IS DISTINCT FROM first_row.effective_at_utc + interval '720 hours'
    OR first_row.observed_at_utc < (SELECT now_utc FROM fixture_0101_clock)
    OR first_row.observed_at_utc > clock_timestamp()
    OR first_row.observed_at_utc < first_row.effective_at_utc
    OR first_row.observed_at_utc >= first_row.purge_after_utc
    OR EXISTS (SELECT 1 FROM fixture_0101_directory AS directory
      JOIN fixture_0101_attempts AS attempt USING (deletion_request_id)
      WHERE attempt.n BETWEEN 3 AND 8)
  THEN RAISE EXCEPTION '0101 typed row, half-open window, status, or lifecycle reconciliation drift'; END IF;
END
$fixture$;
CREATE TEMP TABLE fixture_0101_runtime_failures AS SELECT * FROM fixture_0101_failures;
DO $fixture$
DECLARE failure record; actual_state text; actual_message text;
BEGIN
  FOR failure IN SELECT * FROM fixture_0101_runtime_failures LOOP
    actual_state := NULL; actual_message := NULL;
    BEGIN
      PERFORM * FROM app_data.list_organization_deletion_recovery_for_identity_v1(
        failure.issuer,failure.subject);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
    END;
    IF actual_state IS DISTINCT FROM failure.expected_state
      OR actual_message IS DISTINCT FROM failure.expected_message
    THEN RAISE EXCEPTION '0101 expected % / %, got % / %',
      failure.expected_state,failure.expected_message,actual_state,actual_message; END IF;
  END LOOP;
  BEGIN
    PERFORM * FROM app_private.organization_deletion_current;
    RAISE EXCEPTION '0101 runtime read private lifecycle state';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$fixture$;
RESET ROLE;
DO $fixture$
BEGIN
  IF (SELECT attempts FROM fixture_0101_before) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_current)
    OR (SELECT deletion_claims FROM fixture_0101_before) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_request_claims)
    OR (SELECT restore_claims FROM fixture_0101_before) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_restore_claims)
    OR (SELECT audit_events FROM fixture_0101_before) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_audit_events)
  THEN RAISE EXCEPTION '0101 read changed deletion claims, state, or audit'; END IF;
END
$fixture$;
ROLLBACK;
