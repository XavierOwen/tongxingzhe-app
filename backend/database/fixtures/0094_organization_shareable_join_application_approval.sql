-- Synthetic rollback fixture for shareable organization join approval.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
SELECT
  format('00000000-0094-0000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  'active'
FROM generate_series(1, 13) AS generated_user(n);

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  ('00000000-0094-1000-0000-000000000001',
    'https://synthetic-0094.example/auth/v1', 'owner-one',
    '00000000-0094-0000-0000-000000000001'),
  ('00000000-0094-1000-0000-000000000002',
    'https://synthetic-0094.example/auth/v1', 'owner-two',
    '00000000-0094-0000-0000-000000000002'),
  ('00000000-0094-1000-0000-000000000003',
    'https://synthetic-0094.example/auth/v1', 'other-owner',
    '00000000-0094-0000-0000-000000000003'),
  ('00000000-0094-1000-0000-000000000004',
    'https://synthetic-0094.example/auth/v1', 'ordinary-member',
    '00000000-0094-0000-0000-000000000004');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name,
  personal_owner_app_user_id, deleted_at, created_at
)
VALUES
  ('00000000-0094-2000-0000-000000000001', 'organization',
    '0094 replay organization', NULL, NULL,
    transaction_timestamp() - interval '1 day'),
  ('00000000-0094-2000-0000-000000000002', 'organization',
    '0094 pending organization', NULL, NULL,
    transaction_timestamp() - interval '1 day'),
  ('00000000-0094-2000-0000-000000000003', 'organization',
    '0094 other organization', NULL, NULL,
    transaction_timestamp() - interval '1 day'),
  ('00000000-0094-2000-0000-000000000004', 'organization',
    '0094 recovery organization', NULL, NULL,
    transaction_timestamp() - interval '1 day'),
  ('00000000-0094-2000-0000-000000000005', 'organization',
    '0094 historical replay organization', NULL, NULL,
    transaction_timestamp() - interval '8 days');

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES
  ('00000000-0094-3000-0000-000000000001',
    '00000000-0094-2000-0000-000000000001',
    '00000000-0094-0000-0000-000000000001',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000002',
    '00000000-0094-2000-0000-000000000001',
    '00000000-0094-0000-0000-000000000002',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000003',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000001',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000004',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000002',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000005',
    '00000000-0094-2000-0000-000000000003',
    '00000000-0094-0000-0000-000000000003',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000006',
    '00000000-0094-2000-0000-000000000004',
    '00000000-0094-0000-0000-000000000001',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000007',
    '00000000-0094-2000-0000-000000000005',
    '00000000-0094-0000-0000-000000000002',
    transaction_timestamp() - interval '8 days', NULL),
  ('00000000-0094-3000-0000-000000000008',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000004',
    transaction_timestamp() - interval '1 day', NULL),
  ('00000000-0094-3000-0000-000000000009',
    '00000000-0094-2000-0000-000000000001',
    '00000000-0094-0000-0000-000000000005',
    transaction_timestamp() - interval '3 hours',
    transaction_timestamp() - interval '2 hours'),
  ('00000000-0094-3000-0000-000000000010',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000009',
    transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0094-3000-0000-000000000011',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000010',
    transaction_timestamp() + interval '1 hour',
    transaction_timestamp() + interval '2 hours'),
  ('00000000-0094-3000-0000-000000000012',
    '00000000-0094-2000-0000-000000000005',
    '00000000-0094-0000-0000-000000000012',
    transaction_timestamp() - interval '2 hours',
    transaction_timestamp() - interval '1 hour');

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc
)
VALUES
  ('00000000-0094-4000-0000-000000000001',
    '00000000-0094-3000-0000-000000000001', transaction_timestamp(), NULL),
  ('00000000-0094-4000-0000-000000000002',
    '00000000-0094-3000-0000-000000000002', transaction_timestamp(), NULL),
  ('00000000-0094-4000-0000-000000000003',
    '00000000-0094-3000-0000-000000000003', transaction_timestamp(), NULL),
  ('00000000-0094-4000-0000-000000000004',
    '00000000-0094-3000-0000-000000000004', transaction_timestamp(), NULL),
  ('00000000-0094-4000-0000-000000000005',
    '00000000-0094-3000-0000-000000000005', transaction_timestamp(), NULL),
  ('00000000-0094-4000-0000-000000000006',
    '00000000-0094-3000-0000-000000000006', transaction_timestamp(), NULL),
  ('00000000-0094-4000-0000-000000000007',
    '00000000-0094-3000-0000-000000000007', transaction_timestamp(), NULL);

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Seed approval-independent application facts; 0094 must never consult link.
INSERT INTO app_private.organization_shareable_join_application_request_claims (
  application_id, link_id, organization_workspace_id,
  applicant_app_user_id, submitted_at_utc, expires_at_utc,
  approved_at_utc, approved_organization_membership_id
)
VALUES
  ('00000000-0094-5000-0000-000000000001',
    '00000000-0094-6000-0000-000000000001',
    '00000000-0094-2000-0000-000000000001',
    '00000000-0094-0000-0000-000000000005',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000002',
    '00000000-0094-6000-0000-000000000002',
    '00000000-0094-2000-0000-000000000004',
    '00000000-0094-0000-0000-000000000006',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000003',
    '00000000-0094-6000-0000-000000000003',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000007',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000004',
    '00000000-0094-6000-0000-000000000004',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000008',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000005',
    '00000000-0094-6000-0000-000000000005',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000009',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000006',
    '00000000-0094-6000-0000-000000000006',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000010',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000007',
    '00000000-0094-6000-0000-000000000007',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000011',
    transaction_timestamp() - interval '169 hours',
    transaction_timestamp() - interval '1 hour', NULL, NULL),
  ('00000000-0094-5000-0000-000000000008',
    '00000000-0094-6000-0000-000000000008',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000013',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL),
  ('00000000-0094-5000-0000-000000000009',
    '00000000-0094-6000-0000-000000000009',
    '00000000-0094-2000-0000-000000000005', NULL,
    transaction_timestamp() - interval '169 hours',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() - interval '2 hours',
    '00000000-0094-3000-0000-000000000012'),
  ('00000000-0094-5000-0000-000000000020',
    '00000000-0094-6000-0000-000000000020',
    '00000000-0094-2000-0000-000000000002',
    '00000000-0094-0000-0000-000000000013',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL);

INSERT INTO app_private.organization_shareable_join_application_audit_events (
  organization_shareable_join_application_audit_event_id,
  organization_shareable_join_application_contract_id,
  application_id, link_id, organization_workspace_id, event_kind,
  organization_membership_id, occurred_at_utc
)
SELECT
  gen_random_uuid(), 'organization-shareable-join-application:v1',
  claim.application_id, claim.link_id, claim.organization_workspace_id,
  event.event_kind,
  CASE WHEN event.event_kind = 'application_approved'
    THEN claim.approved_organization_membership_id END,
  CASE WHEN event.event_kind = 'application_approved'
    THEN claim.approved_at_utc ELSE claim.submitted_at_utc END
FROM app_private.organization_shareable_join_application_request_claims AS claim
CROSS JOIN LATERAL (
  SELECT 'application_submitted'::text AS event_kind
  UNION ALL
  SELECT 'application_approved'::text
  WHERE claim.approved_at_utc IS NOT NULL
) AS event
WHERE claim.application_id::text LIKE '00000000-0094-%';

INSERT INTO app_private.organization_shareable_join_application_request_tombstones (
  claim_family, application_id
)
VALUES (
  'organization-shareable-join-application:v1',
  '00000000-0094-5000-0000-000000000020'
);

CREATE TEMP TABLE fixture_0094_receipt (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  approved_at_utc timestamptz
) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0094_same_owner
(LIKE fixture_0094_receipt INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0094_other_owner
(LIKE fixture_0094_receipt INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0094_lifecycle_replay
(LIKE fixture_0094_receipt INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0094_expired_replay
(LIKE fixture_0094_receipt INCLUDING ALL) ON COMMIT DROP;

GRANT ALL ON
  fixture_0094_receipt,
  fixture_0094_same_owner,
  fixture_0094_other_owner,
  fixture_0094_lifecycle_replay,
  fixture_0094_expired_replay
TO tongxingzhe_runtime;

CREATE TEMP TABLE fixture_0094_business_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owner_count,
  (SELECT count(*) FROM app_data.project_memberships) AS project_count,
  (SELECT count(*) FROM app_data.management_report_capability_grants) AS capability_count;

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0094_receipt
SELECT *
FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0094.example/auth/v1', 'owner-one',
  '00000000-0094-5000-0000-000000000001',
  '00000000-0094-2000-0000-000000000001');
INSERT INTO fixture_0094_same_owner
SELECT *
FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0094.example/auth/v1', 'owner-one',
  '00000000-0094-5000-0000-000000000001',
  '00000000-0094-2000-0000-000000000001');
INSERT INTO fixture_0094_other_owner
SELECT *
FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0094.example/auth/v1', 'owner-two',
  '00000000-0094-5000-0000-000000000001',
  '00000000-0094-2000-0000-000000000001');
RESET ROLE;

DO $success$
DECLARE
  receipt fixture_0094_receipt%ROWTYPE;
  same_owner fixture_0094_same_owner%ROWTYPE;
  other_owner fixture_0094_other_owner%ROWTYPE;
  before_counts fixture_0094_business_before%ROWTYPE;
  after_counts fixture_0094_business_before%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM fixture_0094_receipt;
  SELECT * INTO STRICT same_owner FROM fixture_0094_same_owner;
  SELECT * INTO STRICT other_owner FROM fixture_0094_other_owner;
  IF receipt.organization_shareable_join_application_contract_id <>
      'organization-shareable-join-application:v1'
    OR receipt.application_id <>
      '00000000-0094-5000-0000-000000000001'::uuid
    OR receipt.organization_workspace_id <>
      '00000000-0094-2000-0000-000000000001'::uuid
    OR receipt.organization_membership_id IS NULL
    OR receipt.approved_at_utc IS NULL
    OR same_owner IS DISTINCT FROM receipt
    OR other_owner IS DISTINCT FROM receipt
  THEN
    RAISE EXCEPTION '0094 approval receipt or owner-independent replay drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_application_request_claims AS claim
    JOIN app_data.organization_memberships AS membership
      ON membership.organization_membership_id =
        claim.approved_organization_membership_id
    JOIN app_private.organization_shareable_join_application_audit_events AS audit
      ON audit.application_id = claim.application_id
      AND audit.event_kind = 'application_approved'
    WHERE claim.application_id = receipt.application_id
      AND claim.approved_organization_membership_id =
        receipt.organization_membership_id
      AND claim.approved_at_utc = receipt.approved_at_utc
      AND membership.organization_workspace_id =
        receipt.organization_workspace_id
      AND membership.app_user_id =
        '00000000-0094-0000-0000-000000000005'::uuid
      AND membership.active_from_utc = receipt.approved_at_utc
      AND membership.inactive_from_utc IS NULL
      AND audit.organization_membership_id = receipt.organization_membership_id
      AND audit.occurred_at_utc = receipt.approved_at_utc
  ) OR (SELECT count(*)
        FROM app_private.organization_shareable_join_application_audit_events
        WHERE application_id = receipt.application_id) <> 2
  THEN
    RAISE EXCEPTION '0094 membership/claim/audit approval time lineage drifted';
  END IF;

  SELECT * INTO STRICT before_counts FROM fixture_0094_business_before;
  SELECT
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_data.project_memberships),
    (SELECT count(*) FROM app_data.management_report_capability_grants)
  INTO after_counts;
  IF after_counts.membership_count <> before_counts.membership_count + 1
    OR after_counts.owner_count <> before_counts.owner_count
    OR after_counts.project_count <> before_counts.project_count
    OR after_counts.capability_count <> before_counts.capability_count
    OR EXISTS (
      SELECT 1 FROM app_data.organization_owner_assignments
      WHERE organization_membership_id = receipt.organization_membership_id
    )
    OR EXISTS (
      SELECT 1 FROM app_data.project_memberships
      WHERE organization_membership_id = receipt.organization_membership_id
    )
  THEN
    RAISE EXCEPTION '0094 approval did not create exactly one ordinary membership';
  END IF;
END
$success$;

-- Approved replay ignores later applicant, membership and workspace state.
UPDATE app_private.organization_shareable_join_application_request_claims
SET applicant_app_user_id = NULL
WHERE application_id = '00000000-0094-5000-0000-000000000001';
UPDATE app_data.organization_memberships
SET inactive_from_utc = clock_timestamp()
WHERE organization_membership_id =
  (SELECT organization_membership_id FROM fixture_0094_receipt);
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0094-0000-0000-000000000005';
UPDATE app_data.workspaces
SET deleted_at = clock_timestamp() + interval '30 days'
WHERE workspace_id IN (
  '00000000-0094-2000-0000-000000000001',
  '00000000-0094-2000-0000-000000000005'
);
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0094-0000-0000-000000000012';

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0094_lifecycle_replay
SELECT *
FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0094.example/auth/v1', 'owner-two',
  '00000000-0094-5000-0000-000000000001',
  '00000000-0094-2000-0000-000000000001');
INSERT INTO fixture_0094_expired_replay
SELECT *
FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0094.example/auth/v1', 'owner-two',
  '00000000-0094-5000-0000-000000000009',
  '00000000-0094-2000-0000-000000000005');
RESET ROLE;

DO $historical_replay$
BEGIN
  IF (SELECT ROW(r.*) FROM fixture_0094_receipt AS r) IS DISTINCT FROM
      (SELECT ROW(l.*) FROM fixture_0094_lifecycle_replay AS l)
    OR (SELECT ROW(
          organization_shareable_join_application_contract_id,
          application_id, organization_workspace_id,
          organization_membership_id, approved_at_utc)
        FROM fixture_0094_expired_replay) IS DISTINCT FROM ROW(
          'organization-shareable-join-application:v1'::text,
          '00000000-0094-5000-0000-000000000009'::uuid,
          '00000000-0094-2000-0000-000000000005'::uuid,
          '00000000-0094-3000-0000-000000000012'::uuid,
          transaction_timestamp() - interval '2 hours')
  THEN
    RAISE EXCEPTION '0094 approved lifecycle or expiry replay drifted';
  END IF;
END
$historical_replay$;

-- Prepare pending-state failures after their immutable claims exist.
UPDATE app_data.workspaces
SET deleted_at = clock_timestamp() + interval '30 days'
WHERE workspace_id = '00000000-0094-2000-0000-000000000004';
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0094-0000-0000-000000000007';
UPDATE app_private.organization_shareable_join_application_request_claims
SET applicant_app_user_id = NULL
WHERE application_id = '00000000-0094-5000-0000-000000000004';

CREATE OR REPLACE FUNCTION pg_temp.expect_0094_failure(
  case_name text,
  expected_sqlstate text,
  expected_message text,
  statement text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  actual_sqlstate text;
  actual_message text;
BEGIN
  BEGIN
    EXECUTE statement;
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      actual_sqlstate = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
    SET CONSTRAINTS ALL DEFERRED;
    IF actual_sqlstate IS DISTINCT FROM expected_sqlstate
      OR (expected_message IS NOT NULL
        AND actual_message IS DISTINCT FROM expected_message)
    THEN
      RAISE EXCEPTION
        '0094 % expected SQLSTATE/message %, % but got %, %',
        case_name, expected_sqlstate, expected_message,
        actual_sqlstate, actual_message;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '0094 % unexpectedly succeeded', case_name;
END
$function$;

CREATE TEMP TABLE fixture_0094_failure_counts ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count,
  (SELECT count(*)
    FROM app_private.organization_shareable_join_application_audit_events
    WHERE application_id::text LIKE '00000000-0094-%') AS audit_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owner_count,
  (SELECT count(*) FROM app_data.project_memberships) AS project_count,
  (SELECT count(*) FROM app_data.management_report_capability_grants) AS capability_count;
CREATE TEMP TABLE fixture_0094_failure_claims ON COMMIT DROP AS
SELECT *
FROM app_private.organization_shareable_join_application_request_claims
WHERE application_id::text LIKE '00000000-0094-%'
ORDER BY application_id;

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_0094_failure(case_name, sqlstate, message, statement)
FROM (
  VALUES
    ('unknown application', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000099','00000000-0094-2000-0000-000000000002')$$),
    ('application tombstone', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000020','00000000-0094-2000-0000-000000000002')$$),
    ('workspace drift', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000008','00000000-0094-2000-0000-000000000001')$$),
    ('wrong owner', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','other-owner','00000000-0094-5000-0000-000000000008','00000000-0094-2000-0000-000000000002')$$),
    ('ordinary member actor', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','ordinary-member','00000000-0094-5000-0000-000000000008','00000000-0094-2000-0000-000000000002')$$),
    ('expired pending application', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000007','00000000-0094-2000-0000-000000000002')$$),
    ('recovery pending application', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000002','00000000-0094-2000-0000-000000000004')$$),
    ('inactive applicant', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000003','00000000-0094-2000-0000-000000000002')$$),
    ('deassociated applicant', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000004','00000000-0094-2000-0000-000000000002')$$),
    ('current member applicant', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000005','00000000-0094-2000-0000-000000000002')$$),
    ('future membership overlap', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one','00000000-0094-5000-0000-000000000006','00000000-0094-2000-0000-000000000002')$$),
    ('null application', '22023', 'invalid organization shareable join request',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1('https://synthetic-0094.example/auth/v1','owner-one',NULL,'00000000-0094-2000-0000-000000000002')$$),
    ('invalid identity', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.approve_organization_shareable_join_application_for_identity_v1(' ','owner-one','00000000-0094-5000-0000-000000000008','00000000-0094-2000-0000-000000000002')$$)
) AS failure_case(case_name, sqlstate, message, statement);
RESET ROLE;

DO $failure_atomicity$
DECLARE
  before_counts fixture_0094_failure_counts%ROWTYPE;
  after_counts fixture_0094_failure_counts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0094_failure_counts;
  SELECT
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*)
      FROM app_private.organization_shareable_join_application_audit_events
      WHERE application_id::text LIKE '00000000-0094-%'),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_data.project_memberships),
    (SELECT count(*) FROM app_data.management_report_capability_grants)
  INTO after_counts;
  IF after_counts IS DISTINCT FROM before_counts
    OR EXISTS (
      SELECT *
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id::text LIKE '00000000-0094-%'
      EXCEPT ALL SELECT * FROM fixture_0094_failure_claims
    )
    OR EXISTS (
      SELECT * FROM fixture_0094_failure_claims
      EXCEPT ALL
      SELECT *
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id::text LIKE '00000000-0094-%'
    )
  THEN
    RAISE EXCEPTION '0094 failed approval changed business facts';
  END IF;
END
$failure_atomicity$;

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_0094_failure(
  'runtime private approval ACL', '42501', NULL,
  $$SELECT count(*) FROM app_private.approve_organization_shareable_join_application_v1(
    '00000000-0094-0000-0000-000000000001',
    '00000000-0094-5000-0000-000000000008',
    '00000000-0094-2000-0000-000000000002')$$);
SELECT pg_temp.expect_0094_failure(
  'runtime claim ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_application_request_claims');
SELECT pg_temp.expect_0094_failure(
  'runtime audit ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_application_audit_events');
SELECT pg_temp.expect_0094_failure(
  'runtime tombstone ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_application_request_tombstones');
RESET ROLE;

DO $acl$
BEGIN
  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      'app_data.approve_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.approve_organization_shareable_join_application_v1(uuid,uuid,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'public',
      'app_data.approve_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'public',
      'app_private.approve_organization_shareable_join_application_v1(uuid,uuid,uuid)',
      'EXECUTE')
  THEN
    RAISE EXCEPTION '0094 approval privilege drifted';
  END IF;
END
$acl$;

ROLLBACK;
