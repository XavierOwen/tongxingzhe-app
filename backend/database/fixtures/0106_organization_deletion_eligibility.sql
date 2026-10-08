-- All synthetic rows, altered constraints, and observations roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0106_clock AS
SELECT transaction_timestamp() AS boundary_utc,
  ' https://synthetic-0106.example/' || gen_random_uuid()::text || ' ' AS issuer;
CREATE TEMP TABLE fixture_0106_users AS
SELECT n, gen_random_uuid() AS user_id FROM generate_series(1, 5) AS n;
CREATE TEMP TABLE fixture_0106_orgs AS
SELECT n, gen_random_uuid() AS workspace_id FROM generate_series(1, 19) AS n;
CREATE TEMP TABLE fixture_0106_memberships AS
SELECT n AS org_n, 1 AS user_n, gen_random_uuid() AS membership_id
FROM fixture_0106_orgs WHERE n <> 12
UNION ALL
SELECT n, 2, gen_random_uuid() FROM fixture_0106_orgs WHERE n IN (3, 12);

-- Historical/future assignments and unmapped identity cannot be created by
-- current writers. Load those reader boundary cases under replica mode only
-- inside this rollback transaction, then restore ordinary trigger behavior.
SET LOCAL session_replication_role = replica;
INSERT INTO app_data.app_users(app_user_id, status)
SELECT user_id, CASE n WHEN 4 THEN 'deletion_pending' WHEN 5 THEN 'deleted' ELSE 'active' END
FROM fixture_0106_users;
INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
SELECT clock.issuer,
  CASE n WHEN 1 THEN ' owner exact ' WHEN 2 THEN 'co-owner' WHEN 3 THEN 'empty'
    WHEN 4 THEN 'inactive' ELSE 'deleted' END, user_id
FROM fixture_0106_users CROSS JOIN fixture_0106_clock AS clock;
INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
SELECT issuer, 'unmapped', gen_random_uuid() FROM fixture_0106_clock;
-- Tabs are not ASCII spaces; the original maximum-length inputs are valid.
INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
SELECT E'\t', E'\t', user_id FROM fixture_0106_users WHERE n = 3;
INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
SELECT repeat('i', 2048), repeat('s', 512), user_id FROM fixture_0106_users WHERE n = 3;
INSERT INTO app_data.workspaces(workspace_id, workspace_kind, display_name, personal_owner_app_user_id, deleted_at)
SELECT org.workspace_id, CASE WHEN org.n = 14 THEN 'personal' ELSE 'organization' END,
  '0106 original name ' || org.n || ' ',
  CASE WHEN org.n = 14 THEN (SELECT user_id FROM fixture_0106_users WHERE n = 1) END,
  CASE WHEN org.n IN (9, 19) THEN clock.boundary_utc - interval '1 hour' END
FROM fixture_0106_orgs AS org CROSS JOIN fixture_0106_clock AS clock;
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id, active_from_utc, inactive_from_utc)
SELECT member.membership_id, org.workspace_id, actor.user_id,
  CASE WHEN org.n = 7 THEN clock.boundary_utc + interval '1 hour'
    WHEN org.n = 13 THEN clock.boundary_utc
    ELSE clock.boundary_utc - interval '2 hours' END,
  CASE WHEN org.n = 8 THEN clock.boundary_utc END
FROM fixture_0106_memberships AS member
JOIN fixture_0106_orgs AS org ON org.n = member.org_n
JOIN fixture_0106_users AS actor ON actor.n = member.user_n
CROSS JOIN fixture_0106_clock AS clock;
INSERT INTO app_data.organization_owner_assignments(
  organization_owner_assignment_id, organization_membership_id, active_from_utc, inactive_from_utc)
SELECT gen_random_uuid(), member.membership_id,
  CASE WHEN member.org_n = 5 THEN clock.boundary_utc + interval '1 hour'
    WHEN member.org_n = 6 THEN clock.boundary_utc - interval '1 hour'
    ELSE clock.boundary_utc END,
  CASE WHEN member.org_n = 6 THEN clock.boundary_utc END
FROM fixture_0106_memberships AS member CROSS JOIN fixture_0106_clock AS clock
WHERE member.org_n <> 4;
SET LOCAL session_replication_role = origin;

-- 0105 only stores pending/restored/due. Widen the fixture constraint to
-- demonstrate that future failure/finalizer states also fail closed; this
-- does not implement or validate writers for those states.
ALTER TABLE app_private.organization_deletion_current
  DROP CONSTRAINT organization_deletion_current_state_check;
INSERT INTO app_private.organization_deletion_current(
  organization_workspace_id, deletion_request_id, effective_at_utc, purge_after_utc, status, restored_at_utc)
SELECT org.workspace_id, gen_random_uuid(), clock.boundary_utc - interval '2 hours',
  clock.boundary_utc + interval '718 hours',
  CASE org.n WHEN 2 THEN 'restored' WHEN 10 THEN 'deletion_pending'
    WHEN 11 THEN 'purge_due' WHEN 15 THEN 'purging' WHEN 16 THEN 'purge_failed'
    WHEN 17 THEN 'purged' WHEN 18 THEN 'deletion_pending' ELSE 'restored' END,
  CASE WHEN org.n IN (2, 19) THEN clock.boundary_utc - interval '1 hour' END
FROM fixture_0106_orgs AS org CROSS JOIN fixture_0106_clock AS clock
WHERE org.n IN (2, 10, 11, 15, 16, 17, 18, 19);
-- A genuinely expired pending/due attempt is still ineligible even with
-- deleted_at NULL, independently testing the lifecycle predicate.
UPDATE app_private.organization_deletion_current AS attempt
SET effective_at_utc = clock.boundary_utc - interval '721 hours',
  purge_after_utc = clock.boundary_utc - interval '1 hour'
FROM fixture_0106_orgs AS org CROSS JOIN fixture_0106_clock AS clock
WHERE attempt.organization_workspace_id = org.workspace_id AND org.n IN (11, 18);

CREATE TEMP TABLE fixture_0106_before(table_name text, row_data jsonb);
DO $snapshot$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'app_data.app_users', 'app_data.external_identities', 'app_data.workspaces',
    'app_data.organization_memberships', 'app_data.organization_owner_assignments',
    'app_private.organization_deletion_current', 'app_private.organization_deletion_request_claims',
    'app_private.organization_deletion_restore_claims', 'app_private.organization_deletion_audit_events'
  ] LOOP
    EXECUTE format('INSERT INTO fixture_0106_before SELECT %L, coalesce(jsonb_agg(to_jsonb(row_data) ORDER BY to_jsonb(row_data)::text), ''[]''::jsonb) FROM %s AS row_data', table_name, table_name);
  END LOOP;
END
$snapshot$;
CREATE TEMP TABLE fixture_0106_failures(issuer text, subject text, expected_state text, expected_message text);
INSERT INTO fixture_0106_failures VALUES
  (NULL, ' owner exact ', '22023', 'invalid organization deletion eligibility identity'),
  ('   ', ' owner exact ', '22023', 'invalid organization deletion eligibility identity'),
  (repeat('i', 2048) || ' ', ' owner exact ', '22023', 'invalid organization deletion eligibility identity'),
  ((SELECT issuer FROM fixture_0106_clock), NULL, '22023', 'invalid organization deletion eligibility identity'),
  ((SELECT issuer FROM fixture_0106_clock), '   ', '22023', 'invalid organization deletion eligibility identity'),
  ((SELECT issuer FROM fixture_0106_clock), repeat('s', 512) || ' ', '22023', 'invalid organization deletion eligibility identity'),
  (btrim((SELECT issuer FROM fixture_0106_clock)), ' owner exact ', '42501', 'organization deletion eligibility forbidden'),
  ((SELECT issuer FROM fixture_0106_clock), 'owner exact', '42501', 'organization deletion eligibility forbidden'),
  ((SELECT issuer FROM fixture_0106_clock), 'inactive', '42501', 'organization deletion eligibility forbidden'),
  ((SELECT issuer FROM fixture_0106_clock), 'deleted', '42501', 'organization deletion eligibility forbidden'),
  ((SELECT issuer FROM fixture_0106_clock), 'unmapped', '42501', 'organization deletion eligibility forbidden'),
  ('unknown', 'unknown', '42501', 'organization deletion eligibility forbidden');
GRANT SELECT ON fixture_0106_clock, fixture_0106_orgs, fixture_0106_failures TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0106_directory AS
SELECT directory.*, row_number() OVER () AS ordinal
FROM app_data.list_organization_deletion_eligible_for_identity_v1(
  (SELECT issuer FROM fixture_0106_clock), ' owner exact ') AS directory;
DO $fixture$
DECLARE failure record; actual_state text; actual_message text; table_name text;
BEGIN
  IF (SELECT array_agg(organization_workspace_id ORDER BY ordinal) FROM fixture_0106_directory)
      IS DISTINCT FROM (SELECT array_agg(workspace_id ORDER BY workspace_id) FROM fixture_0106_orgs WHERE n IN (1, 2, 3, 13))
    OR (SELECT count(*) FROM app_data.list_organization_deletion_eligible_for_identity_v1(
        (SELECT issuer FROM fixture_0106_clock), 'co-owner')) <> 2
    OR EXISTS (SELECT 1 FROM app_data.list_organization_deletion_eligible_for_identity_v1(
        (SELECT issuer FROM fixture_0106_clock), 'empty'))
    OR EXISTS (SELECT 1 FROM app_data.list_organization_deletion_eligible_for_identity_v1(E'\t', E'\t'))
    OR EXISTS (SELECT 1 FROM app_data.list_organization_deletion_eligible_for_identity_v1(repeat('i', 2048), repeat('s', 512)))
  THEN RAISE EXCEPTION '0106 owner, effective range, lifecycle, empty identity, exact input, or UUID ordering drift'; END IF;

  FOR failure IN SELECT * FROM fixture_0106_failures LOOP
    actual_state := NULL; actual_message := NULL;
    BEGIN
      PERFORM * FROM app_data.list_organization_deletion_eligible_for_identity_v1(failure.issuer, failure.subject);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
    END;
    IF actual_state IS DISTINCT FROM failure.expected_state OR actual_message IS DISTINCT FROM failure.expected_message THEN
      RAISE EXCEPTION '0106 identity error contract drift: expected % / %, got % / %',
        failure.expected_state, failure.expected_message, actual_state, actual_message;
    END IF;
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY[
    'app_data.external_identities', 'app_data.app_users', 'app_data.workspaces',
    'app_data.organization_memberships', 'app_data.organization_owner_assignments',
    'app_private.organization_deletion_current', 'app_private.organization_deletion_request_claims',
    'app_private.organization_deletion_restore_claims', 'app_private.organization_deletion_audit_events'
  ] LOOP
    BEGIN
      EXECUTE format('SELECT 1 FROM %s LIMIT 1', table_name);
      RAISE EXCEPTION '0106 runtime directly read %', table_name;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END
$fixture$;
RESET ROLE;
DO $unchanged$
DECLARE saved record; actual_data jsonb;
BEGIN
  FOR saved IN SELECT * FROM fixture_0106_before LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(row_data) ORDER BY to_jsonb(row_data)::text), ''[]''::jsonb) FROM %s AS row_data', saved.table_name) INTO actual_data;
    IF actual_data IS DISTINCT FROM saved.row_data THEN
      RAISE EXCEPTION '0106 observation changed original rows/timestamps in %', saved.table_name;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_data.projects AS project
      JOIN fixture_0106_orgs AS org ON org.workspace_id = project.workspace_id) THEN
    RAISE EXCEPTION '0106 fixture must demonstrate projectless owners';
  END IF;
END
$unchanged$;
ROLLBACK;
