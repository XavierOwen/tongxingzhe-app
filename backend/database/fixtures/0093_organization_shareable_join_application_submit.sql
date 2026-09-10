-- Synthetic rollback fixture for shareable organization join-application submit.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
SELECT
  format('00000000-0093-0000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  'active'
FROM generate_series(1, 12) AS generated_user(n);

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
SELECT
  format('00000000-0093-1000-0000-%s', lpad(identity_row.n::text, 12, '0'))::uuid,
  'https://synthetic-0093.example/auth/v1',
  identity_row.subject,
  format('00000000-0093-0000-0000-%s', lpad(identity_row.n::text, 12, '0'))::uuid
FROM (
  VALUES
    (1, 'owner'),
    (2, 'applicant'),
    (3, 'second-applicant'),
    (4, 'current-member'),
    (5, 'historical-replay-applicant'),
    (6, 'inactive-replay-applicant'),
    (7, 'detached-applicant'),
    (8, ' exact-applicant '),
    (9, 'retired-link-creator'),
    (10, 'backup-owner'),
    (11, 'wrong-applicant'),
    (12, 'deleted-applicant')
) AS identity_row(n, subject);

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name,
  personal_owner_app_user_id, deleted_at, created_at
)
VALUES
  ('00000000-0093-2000-0000-000000000001', 'organization',
    '0093 main organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0093-2000-0000-000000000002', 'organization',
    '0093 other organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0093-2000-0000-000000000003', 'organization',
    '0093 recovery organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0093-2000-0000-000000000004', 'organization',
    '0093 retired-creator organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0093-2000-0000-000000000005', 'personal',
    '0093 personal workspace', '00000000-0093-0000-0000-000000000003',
    NULL, transaction_timestamp() - interval '1 day');

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES
  ('00000000-0093-3000-0000-000000000001',
    '00000000-0093-2000-0000-000000000001',
    '00000000-0093-0000-0000-000000000001', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0093-3000-0000-000000000002',
    '00000000-0093-2000-0000-000000000002',
    '00000000-0093-0000-0000-000000000001', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0093-3000-0000-000000000003',
    '00000000-0093-2000-0000-000000000003',
    '00000000-0093-0000-0000-000000000001', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0093-3000-0000-000000000004',
    '00000000-0093-2000-0000-000000000004',
    '00000000-0093-0000-0000-000000000009', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0093-3000-0000-000000000005',
    '00000000-0093-2000-0000-000000000004',
    '00000000-0093-0000-0000-000000000010', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0093-3000-0000-000000000006',
    '00000000-0093-2000-0000-000000000001',
    '00000000-0093-0000-0000-000000000004', transaction_timestamp() - interval '1 hour', NULL);

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc
)
VALUES
  ('00000000-0093-4000-0000-000000000001',
    '00000000-0093-3000-0000-000000000001', transaction_timestamp(), NULL),
  ('00000000-0093-4000-0000-000000000002',
    '00000000-0093-3000-0000-000000000002', transaction_timestamp(), NULL),
  ('00000000-0093-4000-0000-000000000003',
    '00000000-0093-3000-0000-000000000003', transaction_timestamp(), NULL),
  ('00000000-0093-4000-0000-000000000004',
    '00000000-0093-3000-0000-000000000004', transaction_timestamp(), NULL),
  ('00000000-0093-4000-0000-000000000005',
    '00000000-0093-3000-0000-000000000005', transaction_timestamp(), NULL);

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Create ordinary links through the shipped 0092 writer.
SELECT count(*)
FROM app_private.create_organization_shareable_join_link_v1(
  '00000000-0093-0000-0000-000000000001',
  '00000000-0093-6000-0000-000000000001',
  '00000000-0093-2000-0000-000000000001');
SELECT count(*)
FROM app_private.create_organization_shareable_join_link_v1(
  '00000000-0093-0000-0000-000000000001',
  '00000000-0093-6000-0000-000000000002',
  '00000000-0093-2000-0000-000000000002');
SELECT count(*)
FROM app_private.create_organization_shareable_join_link_v1(
  '00000000-0093-0000-0000-000000000001',
  '00000000-0093-6000-0000-000000000005',
  '00000000-0093-2000-0000-000000000002');
SELECT count(*)
FROM app_private.create_organization_shareable_join_link_v1(
  '00000000-0093-0000-0000-000000000001',
  '00000000-0093-6000-0000-000000000006',
  '00000000-0093-2000-0000-000000000001');
SELECT count(*)
FROM app_private.create_organization_shareable_join_link_v1(
  '00000000-0093-0000-0000-000000000009',
  '00000000-0093-6000-0000-000000000004',
  '00000000-0093-2000-0000-000000000004');

-- This link is valid for the first submit and crosses expiry later in the
-- same transaction. Other retained rows exercise invalid workspace classes.
INSERT INTO app_private.organization_shareable_join_link_request_claims (
  link_id, organization_workspace_id, creator_app_user_id,
  issued_at_utc, expires_at_utc
)
WITH near_expiry AS MATERIALIZED (
  SELECT clock_timestamp() AS captured_at_utc
)
SELECT *
FROM (
VALUES
  ('00000000-0093-6000-0000-000000000003'::uuid,
    '00000000-0093-2000-0000-000000000003'::uuid,
    '00000000-0093-0000-0000-000000000001'::uuid,
    (SELECT captured_at_utc FROM near_expiry) - interval '168 hours'
      + interval '2 seconds',
    (SELECT captured_at_utc FROM near_expiry) + interval '2 seconds'),
  ('00000000-0093-6000-0000-000000000010',
    '00000000-0093-2000-0000-000000000001',
    '00000000-0093-0000-0000-000000000001',
    transaction_timestamp() - interval '169 hours',
    transaction_timestamp() - interval '1 hour'),
  ('00000000-0093-6000-0000-000000000011',
    '00000000-0093-2000-0000-000000000005',
    '00000000-0093-0000-0000-000000000001',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours'),
  ('00000000-0093-6000-0000-000000000012',
    '00000000-0093-2000-0000-000000009999',
    '00000000-0093-0000-0000-000000000001',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours'),
  ('00000000-0093-6000-0000-000000000013',
    '00000000-0093-2000-0000-000000000001',
    '00000000-0093-0000-0000-000000000001',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours')
  ) AS seeded_link(
    link_id, organization_workspace_id, creator_app_user_id,
    issued_at_utc, expires_at_utc
  );

INSERT INTO app_private.organization_shareable_join_link_audit_events (
  organization_shareable_join_link_audit_event_id,
  organization_shareable_join_link_contract_id,
  link_id, organization_workspace_id, event_kind,
  issued_at_utc, expires_at_utc
)
SELECT
  gen_random_uuid(), 'organization-shareable-join-link:v1',
  claim.link_id, claim.organization_workspace_id, 'link_created',
  claim.issued_at_utc, claim.expires_at_utc
FROM app_private.organization_shareable_join_link_request_claims AS claim
WHERE claim.link_id IN (
  '00000000-0093-6000-0000-000000000003',
  '00000000-0093-6000-0000-000000000010',
  '00000000-0093-6000-0000-000000000011',
  '00000000-0093-6000-0000-000000000012',
  '00000000-0093-6000-0000-000000000013'
);

-- A terminal link history outranks the otherwise-live claim.
INSERT INTO app_private.organization_shareable_join_link_request_tombstones (
  claim_family, link_id
)
VALUES (
  'organization-shareable-join-link:v1',
  '00000000-0093-6000-0000-000000000013'
);

-- Link usability is independent of later creator owner/membership/account
-- state and creator deassociation. Keep the organization valid via backup.
UPDATE app_data.organization_memberships
SET inactive_from_utc = clock_timestamp()
WHERE organization_membership_id =
  '00000000-0093-3000-0000-000000000004';
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0093-0000-0000-000000000009';
UPDATE app_private.organization_shareable_join_link_request_claims
SET creator_app_user_id = NULL
WHERE link_id = '00000000-0093-6000-0000-000000000004';

CREATE TEMP TABLE fixture_0093_submit (
  organization_shareable_join_application_contract_id text,
  application_id uuid,
  link_id uuid,
  organization_workspace_id uuid,
  submitted_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_replay
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_second_applicant
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_historical
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_historical_replay
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_creator_independent
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_detached
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0093_inactive
(LIKE fixture_0093_submit INCLUDING ALL) ON COMMIT DROP;

GRANT ALL ON
  fixture_0093_submit,
  fixture_0093_replay,
  fixture_0093_second_applicant,
  fixture_0093_historical,
  fixture_0093_historical_replay,
  fixture_0093_creator_independent,
  fixture_0093_detached,
  fixture_0093_inactive
TO tongxingzhe_runtime;

CREATE TEMP TABLE fixture_0093_business_counts_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owner_count,
  (SELECT count(*) FROM app_data.project_memberships) AS project_membership_count,
  (SELECT count(*) FROM app_data.management_report_capability_grants) AS capability_count;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0093_submit
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'applicant',
  '00000000-0093-5000-0000-000000000001',
  '00000000-0093-6000-0000-000000000001');
INSERT INTO fixture_0093_replay
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'applicant',
  '00000000-0093-5000-0000-000000000001',
  '00000000-0093-6000-0000-000000000001');
INSERT INTO fixture_0093_second_applicant
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'second-applicant',
  '00000000-0093-5000-0000-000000000002',
  '00000000-0093-6000-0000-000000000001');
INSERT INTO fixture_0093_historical
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'historical-replay-applicant',
  '00000000-0093-5000-0000-000000000003',
  '00000000-0093-6000-0000-000000000003');
INSERT INTO fixture_0093_creator_independent
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'applicant',
  '00000000-0093-5000-0000-000000000004',
  '00000000-0093-6000-0000-000000000004');
INSERT INTO fixture_0093_detached
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'detached-applicant',
  '00000000-0093-5000-0000-000000000005',
  '00000000-0093-6000-0000-000000000006');
INSERT INTO fixture_0093_inactive
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'inactive-replay-applicant',
  '00000000-0093-5000-0000-000000000006',
  '00000000-0093-6000-0000-000000000002');

RESET ROLE;

DO $success$
DECLARE
  submitted fixture_0093_submit%ROWTYPE;
  replayed fixture_0093_replay%ROWTYPE;
  counts_before fixture_0093_business_counts_before%ROWTYPE;
  counts_after fixture_0093_business_counts_before%ROWTYPE;
BEGIN
  SELECT * INTO STRICT submitted FROM fixture_0093_submit;
  SELECT * INTO STRICT replayed FROM fixture_0093_replay;
  IF submitted.organization_shareable_join_application_contract_id <>
      'organization-shareable-join-application:v1'
    OR submitted.application_id <>
      '00000000-0093-5000-0000-000000000001'::uuid
    OR submitted.link_id <>
      '00000000-0093-6000-0000-000000000001'::uuid
    OR submitted.organization_workspace_id <>
      '00000000-0093-2000-0000-000000000001'::uuid
    OR submitted.submitted_at_utc IS NULL
    OR submitted.expires_at_utc - submitted.submitted_at_utc <>
      interval '168 hours'
    OR replayed IS DISTINCT FROM submitted
  THEN
    RAISE EXCEPTION '0093 submit six-field receipt or exact replay drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_application_request_claims AS claim
    JOIN app_private.organization_shareable_join_application_audit_events AS audit
      ON audit.application_id = claim.application_id
      AND audit.link_id = claim.link_id
      AND audit.organization_workspace_id = claim.organization_workspace_id
      AND audit.occurred_at_utc = claim.submitted_at_utc
    WHERE claim.application_id = submitted.application_id
      AND claim.applicant_app_user_id =
        '00000000-0093-0000-0000-000000000002'::uuid
      AND claim.submitted_at_utc = submitted.submitted_at_utc
      AND claim.expires_at_utc = submitted.expires_at_utc
      AND claim.approved_at_utc IS NULL
      AND claim.approved_organization_membership_id IS NULL
      AND audit.organization_shareable_join_application_contract_id =
        submitted.organization_shareable_join_application_contract_id
      AND audit.event_kind = 'application_submitted'
      AND audit.organization_membership_id IS NULL
  ) OR (SELECT count(*)
        FROM app_private.organization_shareable_join_application_audit_events
        WHERE application_id = submitted.application_id) <> 1
  THEN
    RAISE EXCEPTION '0093 submit claim/audit/receipt time lineage drifted';
  END IF;

  IF (SELECT count(DISTINCT applicant_app_user_id)
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE link_id = '00000000-0093-6000-0000-000000000001') <> 2
  THEN
    RAISE EXCEPTION '0093 one shareable link did not retain two applicants';
  END IF;

  SELECT * INTO STRICT counts_before FROM fixture_0093_business_counts_before;
  SELECT
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_data.project_memberships),
    (SELECT count(*) FROM app_data.management_report_capability_grants)
  INTO counts_after;
  IF counts_after IS DISTINCT FROM counts_before THEN
    RAISE EXCEPTION '0093 submit created membership or authorization facts';
  END IF;
END
$success$;

-- Exact replay is classified before later link expiry, workspace recovery,
-- current membership, or approval state.
INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0093-3000-0000-000000000007',
  '00000000-0093-2000-0000-000000000003',
  '00000000-0093-0000-0000-000000000005', clock_timestamp(), NULL
);
UPDATE app_data.workspaces
SET deleted_at = clock_timestamp() + interval '30 days'
WHERE workspace_id = '00000000-0093-2000-0000-000000000003';
UPDATE app_private.organization_shareable_join_application_request_claims
SET approved_at_utc = clock_timestamp(),
    approved_organization_membership_id =
      '00000000-0093-3000-0000-000000000007'
WHERE application_id = '00000000-0093-5000-0000-000000000003';
INSERT INTO app_private.organization_shareable_join_application_audit_events (
  organization_shareable_join_application_audit_event_id,
  organization_shareable_join_application_contract_id,
  application_id, link_id, organization_workspace_id, event_kind,
  organization_membership_id, occurred_at_utc
)
SELECT
  '00000000-0093-7000-0000-000000000003',
  'organization-shareable-join-application:v1',
  claim.application_id, claim.link_id, claim.organization_workspace_id,
  'application_approved', claim.approved_organization_membership_id,
  claim.approved_at_utc
FROM app_private.organization_shareable_join_application_request_claims AS claim
WHERE claim.application_id = '00000000-0093-5000-0000-000000000003';
SELECT pg_sleep(2.1);

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0093_historical_replay
SELECT *
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1', 'historical-replay-applicant',
  '00000000-0093-5000-0000-000000000003',
  '00000000-0093-6000-0000-000000000003');
RESET ROLE;

DO $historical_replay$
BEGIN
  IF (SELECT ROW(h.*) FROM fixture_0093_historical AS h) IS DISTINCT FROM
      (SELECT ROW(r.*) FROM fixture_0093_historical_replay AS r)
    OR (SELECT count(*)
        FROM app_private.organization_shareable_join_application_audit_events
        WHERE application_id = '00000000-0093-5000-0000-000000000003') <> 2
  THEN
    RAISE EXCEPTION '0093 historical exact replay changed receipt or audit';
  END IF;
END
$historical_replay$;

-- Applicant deassociation and later account inactivity forbid replay but do
-- not rewrite or consume the retained application.
UPDATE app_private.organization_shareable_join_application_request_claims
SET applicant_app_user_id = NULL
WHERE application_id = '00000000-0093-5000-0000-000000000005';
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0093-0000-0000-000000000006';
UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '00000000-0093-0000-0000-000000000012';

INSERT INTO app_private.organization_shareable_join_application_request_tombstones (
  claim_family, application_id
)
VALUES (
  'organization-shareable-join-application:v1',
  '00000000-0093-5000-0000-000000000020'
);

CREATE OR REPLACE FUNCTION pg_temp.expect_0093_failure(
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
        '0093 % expected SQLSTATE/message %, % but got %, %',
        case_name, expected_sqlstate, expected_message,
        actual_sqlstate, actual_message;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '0093 % unexpectedly succeeded', case_name;
END
$function$;

CREATE TEMP TABLE fixture_0093_failure_counts_before ON COMMIT DROP AS
SELECT
  (SELECT count(*)
    FROM app_private.organization_shareable_join_application_request_claims
    WHERE split_part(application_id::text, '-', 2) = '0093') AS claim_count,
  (SELECT count(*)
    FROM app_private.organization_shareable_join_application_request_tombstones
    WHERE split_part(application_id::text, '-', 2) = '0093') AS tombstone_count,
  (SELECT count(*)
    FROM app_private.organization_shareable_join_application_audit_events
    WHERE split_part(application_id::text, '-', 2) = '0093') AS audit_count,
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count;

CREATE TEMP TABLE fixture_0093_claims_before ON COMMIT DROP AS
SELECT *
FROM app_private.organization_shareable_join_application_request_claims
WHERE split_part(application_id::text, '-', 2) = '0093'
ORDER BY application_id;

SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0093_failure(case_name, sqlstate, message, statement)
FROM (
  VALUES
    ('null application', '22023', 'invalid organization shareable join request',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant',NULL,'00000000-0093-6000-0000-000000000001')$$),
    ('null link', '22023', 'invalid organization shareable join request',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000030',NULL)$$),
    ('null identity', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1(NULL,'applicant','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000000001')$$),
    ('blank identity', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1',' ','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000000001')$$),
    ('oversized issuer', '22023', 'invalid organization shareable join identity',
      format($$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1(%L,'applicant','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000000001')$$, repeat('i', 2049))),
    ('trimmed identity is not exact', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','exact-applicant','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000000001')$$),
    ('unknown identity', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','unknown','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000000001')$$),
    ('deleted identity', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','deleted-applicant','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000000001')$$),
    ('unknown link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000030','00000000-0093-6000-0000-000000009999')$$),
    ('expired link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000031','00000000-0093-6000-0000-000000000010')$$),
    ('personal workspace link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000032','00000000-0093-6000-0000-000000000011')$$),
    ('unknown workspace link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000033','00000000-0093-6000-0000-000000000012')$$),
    ('link claim plus tombstone', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000038','00000000-0093-6000-0000-000000000013')$$),
    ('recovery new application', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','second-applicant','00000000-0093-5000-0000-000000000034','00000000-0093-6000-0000-000000000003')$$),
    ('current member new application', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','current-member','00000000-0093-5000-0000-000000000035','00000000-0093-6000-0000-000000000001')$$),
    ('wrong applicant replay', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','wrong-applicant','00000000-0093-5000-0000-000000000001','00000000-0093-6000-0000-000000000001')$$),
    ('same applicant application link drift', '22023', 'organization shareable join idempotency conflict',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000001','00000000-0093-6000-0000-000000000005')$$),
    ('same applicant link alternate application', '22023', 'organization shareable join idempotency conflict',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000036','00000000-0093-6000-0000-000000000001')$$),
    ('historical alternate application before current-state checks', '22023', 'organization shareable join idempotency conflict',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','historical-replay-applicant','00000000-0093-5000-0000-000000000037','00000000-0093-6000-0000-000000000003')$$),
    ('application tombstone before link lookup', '22023', 'organization shareable join idempotency conflict',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','applicant','00000000-0093-5000-0000-000000000020','00000000-0093-6000-0000-000000009999')$$),
    ('detached applicant replay', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','detached-applicant','00000000-0093-5000-0000-000000000005','00000000-0093-6000-0000-000000000006')$$),
    ('inactive applicant replay', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.submit_organization_shareable_join_application_for_identity_v1('https://synthetic-0093.example/auth/v1','inactive-replay-applicant','00000000-0093-5000-0000-000000000006','00000000-0093-6000-0000-000000000002')$$)
) AS failure_case(case_name, sqlstate, message, statement);

RESET ROLE;

DO $failure_atomicity$
DECLARE
  before_counts fixture_0093_failure_counts_before%ROWTYPE;
  after_counts fixture_0093_failure_counts_before%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0093_failure_counts_before;
  SELECT
    (SELECT count(*)
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE split_part(application_id::text, '-', 2) = '0093'),
    (SELECT count(*)
      FROM app_private.organization_shareable_join_application_request_tombstones
      WHERE split_part(application_id::text, '-', 2) = '0093'),
    (SELECT count(*)
      FROM app_private.organization_shareable_join_application_audit_events
      WHERE split_part(application_id::text, '-', 2) = '0093'),
    (SELECT count(*) FROM app_data.organization_memberships)
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts
    OR EXISTS (
      SELECT * FROM app_private.organization_shareable_join_application_request_claims
      WHERE split_part(application_id::text, '-', 2) = '0093'
      EXCEPT ALL SELECT * FROM fixture_0093_claims_before
    )
    OR EXISTS (
      SELECT * FROM fixture_0093_claims_before
      EXCEPT ALL
      SELECT * FROM app_private.organization_shareable_join_application_request_claims
      WHERE split_part(application_id::text, '-', 2) = '0093'
    )
  THEN
    RAISE EXCEPTION '0093 failed submit changed application facts';
  END IF;
END
$failure_atomicity$;

-- Approval-ready and unlink guards permit only their two one-way transitions.
SELECT pg_temp.expect_0093_failure(
  'detached applicant reattachment', '55000',
  'organization shareable join application request claim is immutable',
  $$UPDATE app_private.organization_shareable_join_application_request_claims
    SET applicant_app_user_id = '00000000-0093-0000-0000-000000000007'
    WHERE application_id = '00000000-0093-5000-0000-000000000005'$$);
SELECT pg_temp.expect_0093_failure(
  'half approval', '55000',
  'organization shareable join application request claim is immutable',
  $$UPDATE app_private.organization_shareable_join_application_request_claims
    SET approved_at_utc = clock_timestamp()
    WHERE application_id = '00000000-0093-5000-0000-000000000002'$$);
SELECT pg_temp.expect_0093_failure(
  'approval rewrite', '55000',
  'organization shareable join application request claim is immutable',
  $$UPDATE app_private.organization_shareable_join_application_request_claims
    SET approved_at_utc = clock_timestamp()
    WHERE application_id = '00000000-0093-5000-0000-000000000003'$$);
SELECT pg_temp.expect_0093_failure(
  'claim payload update', '55000',
  'organization shareable join application request claim is immutable',
  $$UPDATE app_private.organization_shareable_join_application_request_claims
    SET link_id = '00000000-0093-6000-0000-000000000005'
    WHERE application_id = '00000000-0093-5000-0000-000000000002'$$);
SELECT pg_temp.expect_0093_failure(
  'claim delete', '55000',
  'organization shareable join application request claim cannot be deleted',
  $$DELETE FROM app_private.organization_shareable_join_application_request_claims
    WHERE application_id = '00000000-0093-5000-0000-000000000002'$$);
SELECT pg_temp.expect_0093_failure(
  'tombstone update', '55000',
  'organization shareable join application request tombstone is immutable',
  $$UPDATE app_private.organization_shareable_join_application_request_tombstones
    SET application_id = '00000000-0093-5000-0000-000000000021'
    WHERE application_id = '00000000-0093-5000-0000-000000000020'$$);
SELECT pg_temp.expect_0093_failure(
  'tombstone delete', '55000',
  'organization shareable join application request tombstone is immutable',
  $$DELETE FROM app_private.organization_shareable_join_application_request_tombstones
    WHERE application_id = '00000000-0093-5000-0000-000000000020'$$);
SELECT pg_temp.expect_0093_failure(
  'audit update', '55000',
  'organization shareable join application audit is append-only',
  $$UPDATE app_private.organization_shareable_join_application_audit_events
    SET event_kind = 'application_submitted'
    WHERE application_id = '00000000-0093-5000-0000-000000000001'$$);
SELECT pg_temp.expect_0093_failure(
  'audit delete', '55000',
  'organization shareable join application audit is append-only',
  $$DELETE FROM app_private.organization_shareable_join_application_audit_events
    WHERE application_id = '00000000-0093-5000-0000-000000000001'$$);

DO $approval_ready_and_audit$
DECLARE
  actual_columns text[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY ordinal_position)
  INTO actual_columns
  FROM information_schema.columns
  WHERE table_schema = 'app_private'
    AND table_name = 'organization_shareable_join_application_audit_events';

  IF actual_columns IS DISTINCT FROM ARRAY[
      'organization_shareable_join_application_audit_event_id',
      'organization_shareable_join_application_contract_id',
      'application_id', 'link_id', 'organization_workspace_id',
      'event_kind', 'organization_membership_id', 'occurred_at_utc'
    ]::text[]
    OR EXISTS (
      SELECT 1
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE split_part(application_id::text, '-', 2) = '0093'
        AND ((approved_at_utc IS NULL) <>
             (approved_organization_membership_id IS NULL))
    )
    OR EXISTS (
      SELECT 1
      FROM app_private.organization_shareable_join_application_audit_events
      WHERE split_part(application_id::text, '-', 2) = '0093'
        AND (organization_shareable_join_application_contract_id <>
              'organization-shareable-join-application:v1'
          OR event_kind NOT IN ('application_submitted', 'application_approved')
          OR (event_kind = 'application_submitted'
              AND organization_membership_id IS NOT NULL)
          OR (event_kind = 'application_approved'
              AND organization_membership_id IS NULL))
    )
  THEN
    RAISE EXCEPTION '0093 approval-ready shape or audit allowlist drifted: %',
      actual_columns;
  END IF;
END
$approval_ready_and_audit$;

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_0093_failure(
  'runtime private submit ACL', '42501', NULL,
  $$SELECT count(*) FROM app_private.submit_organization_shareable_join_application_v1(
    '00000000-0093-0000-0000-000000000002',
    '00000000-0093-5000-0000-000000000040',
    '00000000-0093-6000-0000-000000000001')$$);
SELECT pg_temp.expect_0093_failure(
  'runtime claim ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_application_request_claims');
SELECT pg_temp.expect_0093_failure(
  'runtime tombstone ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_application_request_tombstones');
SELECT pg_temp.expect_0093_failure(
  'runtime audit ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_application_audit_events');
RESET ROLE;

DO $acl$
DECLARE
  validator_owner oid;
  writer_owner oid;
BEGIN
  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      'app_data.submit_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.submit_organization_shareable_join_application_v1(uuid,uuid,uuid)',
      'EXECUTE')
  THEN
    RAISE EXCEPTION '0093 runtime submit privilege drifted';
  END IF;
  IF has_function_privilege(
      'public',
      'app_data.submit_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'public',
      'app_private.submit_organization_shareable_join_application_v1(uuid,uuid,uuid)',
      'EXECUTE')
  THEN
    RAISE EXCEPTION '0093 PUBLIC received application submit privilege';
  END IF;
  SELECT proowner INTO STRICT validator_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT proowner INTO STRICT writer_owner
  FROM pg_catalog.pg_proc
  WHERE oid =
    'app_private.submit_organization_shareable_join_application_v1(uuid,uuid,uuid)'::regprocedure;
  IF writer_owner <> validator_owner
    OR pg_catalog.pg_get_userbyid(writer_owner) = 'tongxingzhe_runtime'
  THEN
    RAISE EXCEPTION '0093 application submit writer has wrong owner';
  END IF;
END
$acl$;

ROLLBACK;
