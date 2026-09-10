-- Synthetic rollback fixture for shareable organization join-link create/preview.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
SELECT
  format('00000000-0092-0000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  'active'
FROM generate_series(1, 10) AS generated_user(n);

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
SELECT
  format('00000000-0092-1000-0000-%s', lpad(identity_row.n::text, 12, '0'))::uuid,
  'https://synthetic-0092.example/auth/v1',
  identity_row.subject,
  format('00000000-0092-0000-0000-%s', lpad(identity_row.n::text, 12, '0'))::uuid
FROM (
  VALUES
    (1, 'main-owner'),
    (2, 'second-owner'),
    (3, 'viewer'),
    (4, 'non-owner'),
    (5, 'lost-owner'),
    (6, 'recovery-owner'),
    (7, 'detached-owner'),
    (8, 'inactive-owner'),
    (9, ' previewer '),
    (10, 'deleted-viewer')
) AS identity_row(n, subject);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at,
  created_at
)
VALUES
  ('00000000-0092-2000-0000-000000000001', 'organization',
    ' 0092 Original 组织名称 ', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0092-2000-0000-000000000002', 'organization',
    '0092 other organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0092-2000-0000-000000000003', 'organization',
    '0092 lost-owner organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0092-2000-0000-000000000004', 'organization',
    '0092 recovery organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0092-2000-0000-000000000005', 'organization',
    '0092 detached-creator organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0092-2000-0000-000000000006', 'organization',
    '0092 inactive-creator organization', NULL, NULL, transaction_timestamp() - interval '1 day'),
  ('00000000-0092-2000-0000-000000000007', 'personal',
    '0092 personal workspace', '00000000-0092-0000-0000-000000000003',
    NULL, transaction_timestamp() - interval '1 day');

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  ('00000000-0092-3000-0000-000000000001',
    '00000000-0092-2000-0000-000000000001',
    '00000000-0092-0000-0000-000000000001', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000002',
    '00000000-0092-2000-0000-000000000002',
    '00000000-0092-0000-0000-000000000001', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000003',
    '00000000-0092-2000-0000-000000000001',
    '00000000-0092-0000-0000-000000000002', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000004',
    '00000000-0092-2000-0000-000000000001',
    '00000000-0092-0000-0000-000000000004', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000005',
    '00000000-0092-2000-0000-000000000003',
    '00000000-0092-0000-0000-000000000005', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000006',
    '00000000-0092-2000-0000-000000000004',
    '00000000-0092-0000-0000-000000000006', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000007',
    '00000000-0092-2000-0000-000000000005',
    '00000000-0092-0000-0000-000000000007', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000008',
    '00000000-0092-2000-0000-000000000006',
    '00000000-0092-0000-0000-000000000008', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000009',
    '00000000-0092-2000-0000-000000000003',
    '00000000-0092-0000-0000-000000000002', transaction_timestamp() - interval '1 hour', NULL),
  ('00000000-0092-3000-0000-000000000010',
    '00000000-0092-2000-0000-000000000006',
    '00000000-0092-0000-0000-000000000002', transaction_timestamp() - interval '1 hour', NULL);

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  ('00000000-0092-4000-0000-000000000001',
    '00000000-0092-3000-0000-000000000001', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000002',
    '00000000-0092-3000-0000-000000000002', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000003',
    '00000000-0092-3000-0000-000000000003', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000005',
    '00000000-0092-3000-0000-000000000005', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000006',
    '00000000-0092-3000-0000-000000000006', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000007',
    '00000000-0092-3000-0000-000000000007', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000008',
    '00000000-0092-3000-0000-000000000008', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000009',
    '00000000-0092-3000-0000-000000000009', transaction_timestamp(), NULL),
  ('00000000-0092-4000-0000-000000000010',
    '00000000-0092-3000-0000-000000000010', transaction_timestamp(), NULL);

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

CREATE TEMP TABLE fixture_0092_create (
  organization_shareable_join_link_contract_id text,
  link_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0092_create_replay
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0092_lost_owner_create
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0092_lost_owner_replay
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0092_recovery_create
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0092_recovery_replay
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0092_detached_create
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;
CREATE TEMP TABLE fixture_0092_inactive_create
(LIKE fixture_0092_create INCLUDING ALL) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0092_previews (
  organization_shareable_join_link_preview_contract_id text,
  link_id uuid,
  organization_name text,
  expires_at_utc timestamptz
) ON COMMIT DROP;

GRANT ALL ON
  fixture_0092_create,
  fixture_0092_create_replay,
  fixture_0092_lost_owner_create,
  fixture_0092_lost_owner_replay,
  fixture_0092_recovery_create,
  fixture_0092_recovery_replay,
  fixture_0092_detached_create,
  fixture_0092_inactive_create,
  fixture_0092_previews
TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0092_create
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'main-owner',
  '00000000-0092-5000-0000-000000000001',
  '00000000-0092-2000-0000-000000000001'
);

INSERT INTO fixture_0092_create_replay
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'main-owner',
  '00000000-0092-5000-0000-000000000001',
  '00000000-0092-2000-0000-000000000001'
);

INSERT INTO fixture_0092_lost_owner_create
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'lost-owner',
  '00000000-0092-5000-0000-000000000002',
  '00000000-0092-2000-0000-000000000003'
);

INSERT INTO fixture_0092_recovery_create
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'recovery-owner',
  '00000000-0092-5000-0000-000000000003',
  '00000000-0092-2000-0000-000000000004'
);

INSERT INTO fixture_0092_detached_create
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'detached-owner',
  '00000000-0092-5000-0000-000000000004',
  '00000000-0092-2000-0000-000000000005'
);

INSERT INTO fixture_0092_inactive_create
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'inactive-owner',
  '00000000-0092-5000-0000-000000000005',
  '00000000-0092-2000-0000-000000000006'
);

RESET ROLE;

DO $valid_create$
DECLARE
  created fixture_0092_create%ROWTYPE;
  replayed fixture_0092_create_replay%ROWTYPE;
BEGIN
  SELECT * INTO STRICT created FROM fixture_0092_create;
  SELECT * INTO STRICT replayed FROM fixture_0092_create_replay;

  IF created.organization_shareable_join_link_contract_id IS DISTINCT FROM
      'organization-shareable-join-link:v1'
    OR created.link_id IS DISTINCT FROM
      '00000000-0092-5000-0000-000000000001'::uuid
    OR created.organization_workspace_id IS DISTINCT FROM
      '00000000-0092-2000-0000-000000000001'::uuid
    OR created.issued_at_utc IS NULL
    OR created.expires_at_utc IS NULL
    OR NOT isfinite(created.issued_at_utc)
    OR NOT isfinite(created.expires_at_utc)
    OR created.expires_at_utc - created.issued_at_utc <> interval '168 hours'
  THEN
    RAISE EXCEPTION '0092 create returned an invalid typed receipt';
  END IF;

  IF replayed IS DISTINCT FROM created THEN
    RAISE EXCEPTION '0092 exact create replay changed the receipt';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_link_request_claims AS claim
    WHERE claim.link_id = created.link_id
      AND claim.organization_workspace_id = created.organization_workspace_id
      AND claim.creator_app_user_id =
        '00000000-0092-0000-0000-000000000001'::uuid
      AND claim.issued_at_utc = created.issued_at_utc
      AND claim.expires_at_utc = created.expires_at_utc
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_link_request_claims AS claim
    JOIN app_private.organization_shareable_join_link_audit_events AS audit
      ON audit.link_id = claim.link_id
      AND audit.organization_workspace_id = claim.organization_workspace_id
      AND audit.issued_at_utc = claim.issued_at_utc
      AND audit.expires_at_utc = claim.expires_at_utc
    WHERE claim.link_id = created.link_id
      AND audit.organization_shareable_join_link_contract_id =
        created.organization_shareable_join_link_contract_id
      AND audit.event_kind = 'link_created'
      AND audit.issued_at_utc = created.issued_at_utc
      AND audit.expires_at_utc = created.expires_at_utc
  ) OR (SELECT count(*)
        FROM app_private.organization_shareable_join_link_audit_events
        WHERE link_id = created.link_id) <> 1
  THEN
    RAISE EXCEPTION '0092 create claim/audit lineage is invalid';
  END IF;
END
$valid_create$;

-- State changes after creation must not revoke the link. Exact create replay
-- remains valid after owner/membership loss and during organization recovery.
UPDATE app_data.organization_memberships
SET inactive_from_utc = clock_timestamp()
WHERE organization_membership_id =
  '00000000-0092-3000-0000-000000000005';
UPDATE app_data.workspaces
SET deleted_at = clock_timestamp() + interval '30 days'
WHERE workspace_id = '00000000-0092-2000-0000-000000000004';
UPDATE app_private.organization_shareable_join_link_request_claims
SET creator_app_user_id = NULL
WHERE link_id = '00000000-0092-5000-0000-000000000004';
UPDATE app_data.organization_memberships
SET inactive_from_utc = clock_timestamp()
WHERE organization_membership_id =
  '00000000-0092-3000-0000-000000000008';
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0092-0000-0000-000000000008';
UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '00000000-0092-0000-0000-000000000010';

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0092_lost_owner_replay
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'lost-owner',
  '00000000-0092-5000-0000-000000000002',
  '00000000-0092-2000-0000-000000000003'
);

INSERT INTO fixture_0092_recovery_replay
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'recovery-owner',
  '00000000-0092-5000-0000-000000000003',
  '00000000-0092-2000-0000-000000000004'
);

RESET ROLE;

DO $replay_after_state_change$
BEGIN
  IF (SELECT ROW(
        r.organization_shareable_join_link_contract_id,
        r.link_id,
        r.organization_workspace_id,
        r.issued_at_utc,
        r.expires_at_utc
      ) FROM fixture_0092_lost_owner_replay AS r) IS DISTINCT FROM
      (SELECT ROW(
        c.organization_shareable_join_link_contract_id,
        c.link_id,
        c.organization_workspace_id,
        c.issued_at_utc,
        c.expires_at_utc
      ) FROM fixture_0092_lost_owner_create AS c)
    OR (SELECT ROW(
        r.organization_shareable_join_link_contract_id,
        r.link_id,
        r.organization_workspace_id,
        r.issued_at_utc,
        r.expires_at_utc
      ) FROM fixture_0092_recovery_replay AS r) IS DISTINCT FROM
      (SELECT ROW(
        c.organization_shareable_join_link_contract_id,
        c.link_id,
        c.organization_workspace_id,
        c.issued_at_utc,
        c.expires_at_utc
      ) FROM fixture_0092_recovery_create AS c)
  THEN
    RAISE EXCEPTION '0092 state change altered exact replay receipt';
  END IF;
END
$replay_after_state_change$;

-- Manually retained claims model elapsed/boundary expiry, personal/unknown
-- workspace selectors, and a value-free tombstone without production data.
INSERT INTO app_private.organization_shareable_join_link_request_claims (
  link_id, organization_workspace_id, creator_app_user_id,
  issued_at_utc, expires_at_utc
)
VALUES
  ('00000000-0092-5000-0000-000000000010',
    '00000000-0092-2000-0000-000000000001',
    '00000000-0092-0000-0000-000000000001',
    transaction_timestamp() - interval '169 hours',
    transaction_timestamp() - interval '1 hour'),
  ('00000000-0092-5000-0000-000000000011',
    '00000000-0092-2000-0000-000000000007',
    '00000000-0092-0000-0000-000000000001',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours'),
  ('00000000-0092-5000-0000-000000000012',
    '00000000-0092-2000-0000-000000009999',
    '00000000-0092-0000-0000-000000000001',
    transaction_timestamp(), transaction_timestamp() + interval '168 hours'),
  ('00000000-0092-5000-0000-000000000013',
    '00000000-0092-2000-0000-000000000001',
    '00000000-0092-0000-0000-000000000001',
    transaction_timestamp() - interval '168 hours', transaction_timestamp());

INSERT INTO app_private.organization_shareable_join_link_audit_events (
  organization_shareable_join_link_audit_event_id,
  organization_shareable_join_link_contract_id,
  link_id,
  organization_workspace_id,
  event_kind,
  issued_at_utc,
  expires_at_utc
)
SELECT
  format('00000000-0092-6000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  'organization-shareable-join-link:v1',
  format('00000000-0092-5000-0000-%s', lpad(n::text, 12, '0'))::uuid,
  workspace_id,
  'link_created',
  issued_at_utc,
  expires_at_utc
FROM (
  VALUES
    (10, '00000000-0092-2000-0000-000000000001'::uuid,
      transaction_timestamp() - interval '169 hours',
      transaction_timestamp() - interval '1 hour'),
    (11, '00000000-0092-2000-0000-000000000007'::uuid,
      transaction_timestamp(), transaction_timestamp() + interval '168 hours'),
    (12, '00000000-0092-2000-0000-000000009999'::uuid,
      transaction_timestamp(), transaction_timestamp() + interval '168 hours'),
    (13, '00000000-0092-2000-0000-000000000001'::uuid,
      transaction_timestamp() - interval '168 hours', transaction_timestamp())
) AS audit_seed(n, workspace_id, issued_at_utc, expires_at_utc);

INSERT INTO app_private.organization_shareable_join_link_request_tombstones (
  claim_family,
  link_id
)
VALUES (
  'organization-shareable-join-link:v1',
  '00000000-0092-5000-0000-000000000020'
);

CREATE OR REPLACE FUNCTION pg_temp.expect_0092_failure(
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
        '0092 % expected SQLSTATE/message %, % but got %, %',
        case_name, expected_sqlstate, expected_message,
        actual_sqlstate, actual_message;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION '0092 % unexpectedly succeeded', case_name;
END
$function$;

CREATE TEMP TABLE fixture_0092_create_counts_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims
    WHERE split_part(link_id::text, '-', 2) = '0092') AS claim_count,
  (SELECT count(*) FROM app_private.organization_shareable_join_link_request_tombstones
    WHERE split_part(link_id::text, '-', 2) = '0092') AS tombstone_count,
  (SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events
    WHERE split_part(link_id::text, '-', 2) = '0092') AS audit_count;

CREATE TEMP TABLE fixture_0092_claims_before ON COMMIT DROP AS
SELECT *
FROM app_private.organization_shareable_join_link_request_claims
WHERE split_part(link_id::text, '-', 2) = '0092'
ORDER BY link_id;

SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0092_failure(case_name, sqlstate, message, statement)
FROM (
  VALUES
    ('null link', '22023', 'invalid organization shareable join request',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','main-owner',NULL,'00000000-0092-2000-0000-000000000001')$$),
    ('null workspace', '22023', 'invalid organization shareable join request',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','main-owner','00000000-0092-5000-0000-000000000030',NULL)$$),
    ('null issuer', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1(NULL,'main-owner','00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$),
    ('space subject', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1',' ','00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$),
    ('oversized issuer', '22023', 'invalid organization shareable join identity',
      format($$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1(%L,'main-owner','00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$, repeat('i', 2049))),
    ('oversized subject', '22023', 'invalid organization shareable join identity',
      format($$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1',%L,'00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$, repeat('s', 513))),
    ('unknown identity', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','unknown','00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$),
    ('trimmed identity is not exact', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','previewer','00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$),
    ('non-owner create', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','non-owner','00000000-0092-5000-0000-000000000030','00000000-0092-2000-0000-000000000001')$$),
    ('lost-owner new create', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','lost-owner','00000000-0092-5000-0000-000000000031','00000000-0092-2000-0000-000000000003')$$),
    ('recovery new create', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','recovery-owner','00000000-0092-5000-0000-000000000032','00000000-0092-2000-0000-000000000004')$$),
    ('inactive creator replay', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','inactive-owner','00000000-0092-5000-0000-000000000005','00000000-0092-2000-0000-000000000006')$$),
    ('detached creator replay', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','detached-owner','00000000-0092-5000-0000-000000000004','00000000-0092-2000-0000-000000000005')$$),
    ('unknown workspace', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','main-owner','00000000-0092-5000-0000-000000000033','00000000-0092-2000-0000-000000009999')$$),
    ('personal workspace', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','main-owner','00000000-0092-5000-0000-000000000034','00000000-0092-2000-0000-000000000007')$$),
    ('creator drift', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','second-owner','00000000-0092-5000-0000-000000000001','00000000-0092-2000-0000-000000000001')$$),
    ('same creator workspace drift', '22023', 'organization shareable join idempotency conflict',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','main-owner','00000000-0092-5000-0000-000000000001','00000000-0092-2000-0000-000000000002')$$),
    ('tombstone conflict', '22023', 'organization shareable join idempotency conflict',
      $$SELECT count(*) FROM app_data.create_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','main-owner','00000000-0092-5000-0000-000000000020','00000000-0092-2000-0000-000000000001')$$)
) AS create_failure(case_name, sqlstate, message, statement);

RESET ROLE;

DO $create_failure_atomicity$
DECLARE
  before_counts fixture_0092_create_counts_before%ROWTYPE;
  after_counts fixture_0092_create_counts_before%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0092_create_counts_before;
  SELECT
    (SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims
      WHERE split_part(link_id::text, '-', 2) = '0092'),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_request_tombstones
      WHERE split_part(link_id::text, '-', 2) = '0092'),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events
      WHERE split_part(link_id::text, '-', 2) = '0092')
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts
    OR EXISTS (
      SELECT * FROM app_private.organization_shareable_join_link_request_claims
      WHERE split_part(link_id::text, '-', 2) = '0092'
      EXCEPT ALL SELECT * FROM fixture_0092_claims_before
    )
    OR EXISTS (
      SELECT * FROM fixture_0092_claims_before
      EXCEPT ALL
      SELECT * FROM app_private.organization_shareable_join_link_request_claims
      WHERE split_part(link_id::text, '-', 2) = '0092'
    )
  THEN
    RAISE EXCEPTION '0092 failed create changed link facts';
  END IF;
END
$create_failure_atomicity$;

CREATE TEMP TABLE fixture_0092_preview_counts_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_user_count,
  (SELECT count(*) FROM app_data.external_identities) AS identity_count,
  (SELECT count(*) FROM app_data.workspaces) AS workspace_count,
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owner_count,
  (SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims) AS claim_count,
  (SELECT count(*) FROM app_private.organization_shareable_join_link_request_tombstones) AS tombstone_count,
  (SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events) AS audit_count;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0092_previews
SELECT * FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'viewer',
  '00000000-0092-5000-0000-000000000001');
INSERT INTO fixture_0092_previews
SELECT * FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'main-owner',
  '00000000-0092-5000-0000-000000000001');
INSERT INTO fixture_0092_previews
SELECT * FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'viewer',
  '00000000-0092-5000-0000-000000000002');
INSERT INTO fixture_0092_previews
SELECT * FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'viewer',
  '00000000-0092-5000-0000-000000000004');
INSERT INTO fixture_0092_previews
SELECT * FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', 'viewer',
  '00000000-0092-5000-0000-000000000005');
INSERT INTO fixture_0092_previews
SELECT * FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0092.example/auth/v1', ' previewer ',
  '00000000-0092-5000-0000-000000000001');

SELECT pg_temp.expect_0092_failure(case_name, sqlstate, message, statement)
FROM (
  VALUES
    ('preview null link', '22023', 'invalid organization shareable join request',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer',NULL)$$),
    ('preview null identity', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1(NULL,'viewer','00000000-0092-5000-0000-000000000001')$$),
    ('preview blank identity', '22023', 'invalid organization shareable join identity',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1',' ','00000000-0092-5000-0000-000000000001')$$),
    ('preview trimmed identity', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','previewer','00000000-0092-5000-0000-000000000001')$$),
    ('preview inactive actor', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','inactive-owner','00000000-0092-5000-0000-000000000001')$$),
    ('preview deleted actor', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','deleted-viewer','00000000-0092-5000-0000-000000000001')$$),
    ('preview unknown link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer','00000000-0092-5000-0000-000000009999')$$),
    ('preview expired link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer','00000000-0092-5000-0000-000000000010')$$),
    ('preview expiry boundary', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer','00000000-0092-5000-0000-000000000013')$$),
    ('preview recovery link', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer','00000000-0092-5000-0000-000000000003')$$),
    ('preview personal workspace', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer','00000000-0092-5000-0000-000000000011')$$),
    ('preview unknown workspace', '42501', 'organization shareable join forbidden',
      $$SELECT count(*) FROM app_data.preview_organization_shareable_join_link_for_identity_v1('https://synthetic-0092.example/auth/v1','viewer','00000000-0092-5000-0000-000000000012')$$)
) AS preview_failure(case_name, sqlstate, message, statement);

RESET ROLE;

DO $preview_results$
DECLARE
  counts_before fixture_0092_preview_counts_before%ROWTYPE;
  counts_after fixture_0092_preview_counts_before%ROWTYPE;
BEGIN
  IF (SELECT count(*) FROM fixture_0092_previews) <> 6
    OR EXISTS (
      SELECT 1 FROM fixture_0092_previews AS preview
      WHERE preview.organization_shareable_join_link_preview_contract_id
          IS DISTINCT FROM 'organization-shareable-join-link-preview:v1'
        OR preview.expires_at_utc <= clock_timestamp()
    )
    OR (SELECT count(*) FROM fixture_0092_previews
        WHERE link_id = '00000000-0092-5000-0000-000000000001'
          AND organization_name = ' 0092 Original 组织名称 ') <> 3
    OR (SELECT count(*) FROM fixture_0092_previews
        WHERE link_id = '00000000-0092-5000-0000-000000000002'
          AND organization_name = '0092 lost-owner organization') <> 1
    OR (SELECT count(*) FROM fixture_0092_previews
        WHERE link_id = '00000000-0092-5000-0000-000000000004'
          AND organization_name = '0092 detached-creator organization') <> 1
    OR (SELECT count(*) FROM fixture_0092_previews
        WHERE link_id = '00000000-0092-5000-0000-000000000005'
          AND organization_name = '0092 inactive-creator organization') <> 1
  THEN
    RAISE EXCEPTION '0092 preview typed receipt or retained-link behavior drifted';
  END IF;

  SELECT * INTO STRICT counts_before FROM fixture_0092_preview_counts_before;
  SELECT
    (SELECT count(*) FROM app_data.app_users),
    (SELECT count(*) FROM app_data.external_identities),
    (SELECT count(*) FROM app_data.workspaces),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_request_tombstones),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events)
  INTO counts_after;
  IF counts_after IS DISTINCT FROM counts_before THEN
    RAISE EXCEPTION '0092 preview wrote facts: before %, after %',
      counts_before, counts_after;
  END IF;
END
$preview_results$;

DO $audit_allowlist$
DECLARE
  actual_columns text[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY ordinal_position)
  INTO actual_columns
  FROM information_schema.columns
  WHERE table_schema = 'app_private'
    AND table_name = 'organization_shareable_join_link_audit_events';

  IF actual_columns IS DISTINCT FROM ARRAY[
    'organization_shareable_join_link_audit_event_id',
    'organization_shareable_join_link_contract_id',
    'link_id',
    'organization_workspace_id',
    'event_kind',
    'issued_at_utc',
    'expires_at_utc'
  ]::text[]
    OR EXISTS (
      SELECT 1
      FROM app_private.organization_shareable_join_link_audit_events
      WHERE split_part(link_id::text, '-', 2) = '0092'
        AND (organization_shareable_join_link_contract_id <>
              'organization-shareable-join-link:v1'
          OR event_kind <> 'link_created'
          OR expires_at_utc - issued_at_utc <> interval '168 hours')
    )
  THEN
    RAISE EXCEPTION '0092 link audit allowlist or values drifted: %', actual_columns;
  END IF;
END
$audit_allowlist$;

-- Only one creator deassociation is legal; every other claim/tombstone/audit
-- mutation remains guarded.
SELECT pg_temp.expect_0092_failure(
  'creator reattachment', '55000',
  'organization shareable join link request claim is immutable',
  $$UPDATE app_private.organization_shareable_join_link_request_claims
    SET creator_app_user_id = '00000000-0092-0000-0000-000000000007'
    WHERE link_id = '00000000-0092-5000-0000-000000000004'$$
);
SELECT pg_temp.expect_0092_failure(
  'claim workspace update', '55000',
  'organization shareable join link request claim is immutable',
  $$UPDATE app_private.organization_shareable_join_link_request_claims
    SET organization_workspace_id = '00000000-0092-2000-0000-000000000002'
    WHERE link_id = '00000000-0092-5000-0000-000000000001'$$
);
SELECT pg_temp.expect_0092_failure(
  'claim delete', '55000',
  'organization shareable join link request claim cannot be deleted',
  $$DELETE FROM app_private.organization_shareable_join_link_request_claims
    WHERE link_id = '00000000-0092-5000-0000-000000000001'$$
);
SELECT pg_temp.expect_0092_failure(
  'tombstone update', '55000',
  'organization shareable join link request tombstone is immutable',
  $$UPDATE app_private.organization_shareable_join_link_request_tombstones
    SET link_id = '00000000-0092-5000-0000-000000000021'
    WHERE link_id = '00000000-0092-5000-0000-000000000020'$$
);
SELECT pg_temp.expect_0092_failure(
  'tombstone delete', '55000',
  'organization shareable join link request tombstone is immutable',
  $$DELETE FROM app_private.organization_shareable_join_link_request_tombstones
    WHERE link_id = '00000000-0092-5000-0000-000000000020'$$
);
SELECT pg_temp.expect_0092_failure(
  'audit update', '55000',
  'organization shareable join link audit is append-only',
  $$UPDATE app_private.organization_shareable_join_link_audit_events
    SET event_kind = 'link_created'
    WHERE link_id = '00000000-0092-5000-0000-000000000001'$$
);
SELECT pg_temp.expect_0092_failure(
  'audit delete', '55000',
  'organization shareable join link audit is append-only',
  $$DELETE FROM app_private.organization_shareable_join_link_audit_events
    WHERE link_id = '00000000-0092-5000-0000-000000000001'$$
);

SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0092_failure(
  'runtime private create ACL', '42501', NULL,
  $$SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '00000000-0092-0000-0000-000000000001',
    '00000000-0092-5000-0000-000000000040',
    '00000000-0092-2000-0000-000000000001')$$
);
SELECT pg_temp.expect_0092_failure(
  'runtime claim ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims'
);
SELECT pg_temp.expect_0092_failure(
  'runtime tombstone ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_link_request_tombstones'
);
SELECT pg_temp.expect_0092_failure(
  'runtime audit ACL', '42501', NULL,
  'SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events'
);

RESET ROLE;

DO $acl$
DECLARE
  validator_owner oid;
  writer_owner oid;
BEGIN
  IF NOT has_function_privilege(
      'tongxingzhe_runtime',
      'app_data.create_organization_shareable_join_link_for_identity_v1(text,text,uuid,uuid)',
      'EXECUTE')
    OR NOT has_function_privilege(
      'tongxingzhe_runtime',
      'app_data.preview_organization_shareable_join_link_for_identity_v1(text,text,uuid)',
      'EXECUTE')
  THEN
    RAISE EXCEPTION '0092 runtime bridge EXECUTE privilege is missing';
  END IF;

  IF has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.create_organization_shareable_join_link_v1(uuid,uuid,uuid)',
      'EXECUTE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.organization_shareable_join_link_request_claims', 'SELECT')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.organization_shareable_join_link_request_tombstones', 'SELECT')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.organization_shareable_join_link_audit_events', 'SELECT')
  THEN
    RAISE EXCEPTION '0092 runtime received a private join-link privilege';
  END IF;

  IF has_function_privilege(
      'public',
      'app_data.create_organization_shareable_join_link_for_identity_v1(text,text,uuid,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'public',
      'app_data.preview_organization_shareable_join_link_for_identity_v1(text,text,uuid)',
      'EXECUTE')
    OR has_function_privilege(
      'public',
      'app_private.create_organization_shareable_join_link_v1(uuid,uuid,uuid)',
      'EXECUTE')
  THEN
    RAISE EXCEPTION '0092 PUBLIC received a join-link function privilege';
  END IF;

  SELECT proowner INTO STRICT validator_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT proowner INTO STRICT writer_owner
  FROM pg_catalog.pg_proc
  WHERE oid =
    'app_private.create_organization_shareable_join_link_v1(uuid,uuid,uuid)'::regprocedure;
  IF writer_owner <> validator_owner
    OR pg_catalog.pg_get_userbyid(writer_owner) = 'tongxingzhe_runtime'
  THEN
    RAISE EXCEPTION '0092 join-link writer has the wrong owner';
  END IF;
END
$acl$;

ROLLBACK;
