-- Synthetic rollback fixture for organization membership self-leave.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0090-0000-0000-000000000001', 'active'),
  ('00000000-0090-0000-0000-000000000002', 'active'),
  ('00000000-0090-0000-0000-000000000003', 'active'),
  ('00000000-0090-0000-0000-000000000004', 'active'),
  ('00000000-0090-0000-0000-000000000005', 'active'),
  ('00000000-0090-0000-0000-000000000006', 'active'),
  ('00000000-0090-0000-0000-000000000007', 'active'),
  ('00000000-0090-0000-0000-000000000008', 'active'),
  ('00000000-0090-0000-0000-000000000009', 'active'),
  ('00000000-0090-0000-0000-000000000010', 'active'),
  ('00000000-0090-0000-0000-000000000011', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
VALUES
  (
    '00000000-0090-1000-0000-000000000001',
    'https://synthetic-0090.example/auth/v1',
    'main-owner',
    '00000000-0090-0000-0000-000000000001'
  ),
  (
    '00000000-0090-1000-0000-000000000002',
    'https://synthetic-0090.example/auth/v1',
    'integration-member',
    '00000000-0090-0000-0000-000000000002'
  ),
  (
    '00000000-0090-1000-0000-000000000003',
    'https://synthetic-0090.example/auth/v1',
    'successful-member',
    '00000000-0090-0000-0000-000000000003'
  ),
  (
    '00000000-0090-1000-0000-000000000004',
    'https://synthetic-0090.example/auth/v1',
    'current-owner-member',
    '00000000-0090-0000-0000-000000000004'
  ),
  (
    '00000000-0090-1000-0000-000000000005',
    'https://synthetic-0090.example/auth/v1',
    'future-owner-member',
    '00000000-0090-0000-0000-000000000005'
  ),
  (
    '00000000-0090-1000-0000-000000000006',
    'https://synthetic-0090.example/auth/v1',
    'project-history-member',
    '00000000-0090-0000-0000-000000000006'
  ),
  (
    '00000000-0090-1000-0000-000000000007',
    'https://synthetic-0090.example/auth/v1',
    'target-assignment-member',
    '00000000-0090-0000-0000-000000000007'
  ),
  (
    '00000000-0090-1000-0000-000000000008',
    'https://synthetic-0090.example/auth/v1',
    'scheduled-end-member',
    '00000000-0090-0000-0000-000000000008'
  ),
  (
    '00000000-0090-1000-0000-000000000009',
    'https://synthetic-0090.example/auth/v1',
    'nullified-claim-member',
    '00000000-0090-0000-0000-000000000009'
  ),
  (
    '00000000-0090-1000-0000-000000000010',
    'https://synthetic-0090.example/auth/v1',
    'past-owner-member',
    '00000000-0090-0000-0000-000000000010'
  ),
  (
    '00000000-0090-1000-0000-000000000011',
    'https://synthetic-0090.example/auth/v1',
    'recovery-member',
    '00000000-0090-0000-0000-000000000011'
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at,
  created_at
)
VALUES
  (
    '00000000-0090-2000-0000-000000000001',
    'organization',
    '0090 main organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '3 hours'
  ),
  (
    '00000000-0090-2000-0000-000000000002',
    'organization',
    '0090 recovery organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '3 hours'
  );

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default,
  created_at
)
VALUES (
  '00000000-0090-2500-0000-000000000001',
  '00000000-0090-2000-0000-000000000001',
  '0090 historical project',
  'active',
  false,
  transaction_timestamp() - interval '2 hours'
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-0090-2100-0000-000000000001',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000001',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000002',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000002',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000010',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000003',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000020',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000004',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000030',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000005',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000040',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000006',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000050',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000007',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000060',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000008',
    transaction_timestamp() - interval '2 hours',
    transaction_timestamp() + interval '2 hours'
  ),
  (
    '00000000-0090-2100-0000-000000000070',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000009',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2100-0000-000000000080',
    '00000000-0090-2000-0000-000000000001',
    '00000000-0090-0000-0000-000000000010',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2200-0000-000000000001',
    '00000000-0090-2000-0000-000000000002',
    '00000000-0090-0000-0000-000000000001',
    transaction_timestamp() - interval '2 hours',
    NULL
  ),
  (
    '00000000-0090-2200-0000-000000000002',
    '00000000-0090-2000-0000-000000000002',
    '00000000-0090-0000-0000-000000000011',
    transaction_timestamp() - interval '2 hours',
    NULL
  );

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-0090-2300-0000-000000000001',
    '00000000-0090-2100-0000-000000000001',
    transaction_timestamp(),
    NULL
  ),
  (
    '00000000-0090-2300-0000-000000000002',
    '00000000-0090-2200-0000-000000000001',
    transaction_timestamp(),
    NULL
  ),
  (
    '00000000-0090-2300-0000-000000000020',
    '00000000-0090-2100-0000-000000000020',
    transaction_timestamp(),
    NULL
  );

-- Seed legal past/future owner history without invoking the formal writer's
-- transaction-time rule. Production guards are restored before any call.
SET LOCAL session_replication_role = replica;
INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-0090-2300-0000-000000000030',
    '00000000-0090-2100-0000-000000000030',
    transaction_timestamp() + interval '1 hour',
    transaction_timestamp() + interval '2 hours'
  ),
  (
    '00000000-0090-2300-0000-000000000080',
    '00000000-0090-2100-0000-000000000080',
    transaction_timestamp() - interval '2 hours',
    transaction_timestamp() - interval '1 hour'
  );
SET LOCAL session_replication_role = origin;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '00000000-0090-2400-0000-000000000001',
  '00000000-0090-2100-0000-000000000040',
  '00000000-0090-2500-0000-000000000001',
  transaction_timestamp() - interval '90 minutes',
  transaction_timestamp() - interval '60 minutes'
);

INSERT INTO app_data.promotion_targets (
  promotion_target_id,
  workspace_id,
  target_type,
  display_name,
  phone,
  email,
  status,
  created_by_app_user_id,
  created_at
)
VALUES (
  '00000000-0090-2600-0000-000000000001',
  '00000000-0090-2000-0000-000000000001',
  'person',
  '0090 synthetic target',
  NULL,
  NULL,
  'active',
  '00000000-0090-0000-0000-000000000001',
  transaction_timestamp() - interval '1 hour'
);

INSERT INTO app_data.promotion_target_assignments (
  assignment_id,
  promotion_target_id,
  app_user_id,
  assigned_by_app_user_id,
  assigned_at,
  ended_at,
  end_reason
)
VALUES (
  '00000000-0090-2700-0000-000000000001',
  '00000000-0090-2600-0000-000000000001',
  '00000000-0090-0000-0000-000000000007',
  '00000000-0090-0000-0000-000000000001',
  transaction_timestamp() - interval '1 hour',
  NULL,
  NULL
);

CREATE TEMP TABLE fixture_0090_recovery_first_receipt ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'recovery-member',
  '00000000-0090-3000-0000-000000000104',
  '00000000-0090-2000-0000-000000000002'
);

UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp() + interval '30 days'
WHERE workspace_id = '00000000-0090-2000-0000-000000000002';

CREATE TEMP TABLE fixture_0090_recovery_replay_receipt ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'recovery-member',
  '00000000-0090-3000-0000-000000000104',
  '00000000-0090-2000-0000-000000000002'
);

DO $recovery_replay$
DECLARE
  first_row fixture_0090_recovery_first_receipt%ROWTYPE;
  replay_row fixture_0090_recovery_replay_receipt%ROWTYPE;
BEGIN
  SELECT * INTO STRICT first_row
  FROM fixture_0090_recovery_first_receipt;
  SELECT * INTO STRICT replay_row
  FROM fixture_0090_recovery_replay_receipt;

  IF first_row IS DISTINCT FROM replay_row
    OR first_row.organization_membership_id IS DISTINCT FROM
      '00000000-0090-2200-0000-000000000002'::uuid
    OR first_row.membership_self_leave_contract_id IS DISTINCT FROM
      'organization-membership-self-leave:v1'
  THEN
    RAISE EXCEPTION
      '0090 recovery period did not preserve the exact live replay receipt';
  END IF;
END
$recovery_replay$;

INSERT INTO app_private.organization_membership_self_leave_request_claims (
  request_id,
  actor_app_user_id,
  organization_workspace_id,
  organization_membership_id,
  effective_at_utc
)
VALUES (
  '00000000-0090-3000-0000-000000000003',
  '00000000-0090-0000-0000-000000000009',
  '00000000-0090-2000-0000-000000000001',
  '00000000-0090-2100-0000-000000000070',
  transaction_timestamp() - interval '1 minute'
);

UPDATE app_private.organization_membership_self_leave_request_claims
SET actor_app_user_id = NULL
WHERE request_id = '00000000-0090-3000-0000-000000000003';

INSERT INTO app_private.organization_membership_self_leave_request_tombstones (
  claim_family,
  request_id
)
VALUES (
  'organization-membership-self-leave:v1',
  '00000000-0090-3000-0000-000000000004'
);

SET CONSTRAINTS ALL IMMEDIATE;

CREATE OR REPLACE FUNCTION pg_temp.expect_0090_failure(
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
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      actual_sqlstate = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;

    IF actual_sqlstate IS DISTINCT FROM expected_sqlstate
      OR (
        expected_message IS NOT NULL
        AND actual_message IS DISTINCT FROM expected_message
      )
    THEN
      RAISE EXCEPTION
        '0090 % expected SQLSTATE/message %, % but got %, %',
        case_name,
        expected_sqlstate,
        expected_message,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0090 % unexpectedly succeeded', case_name;
END
$function$;

CREATE TEMP TABLE fixture_0090_first_receipt ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'successful-member',
  '00000000-0090-3000-0000-000000000101',
  '00000000-0090-2000-0000-000000000001'
);

CREATE TEMP TABLE fixture_0090_replay_receipt ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'successful-member',
  '00000000-0090-3000-0000-000000000101',
  '00000000-0090-2000-0000-000000000001'
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '00000000-0090-2100-0000-000000000011',
  '00000000-0090-2000-0000-000000000001',
  '00000000-0090-0000-0000-000000000003',
  clock_timestamp(),
  NULL
);

CREATE TEMP TABLE fixture_0090_old_request_after_rejoin ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'successful-member',
  '00000000-0090-3000-0000-000000000101',
  '00000000-0090-2000-0000-000000000001'
);

CREATE TEMP TABLE fixture_0090_new_leave_after_rejoin ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'successful-member',
  '00000000-0090-3000-0000-000000000102',
  '00000000-0090-2000-0000-000000000001'
);

CREATE TEMP TABLE fixture_0090_past_owner_receipt ON COMMIT DROP AS
SELECT *
FROM app_data.leave_organization_membership_for_identity_v1(
  'https://synthetic-0090.example/auth/v1',
  'past-owner-member',
  '00000000-0090-3000-0000-000000000103',
  '00000000-0090-2000-0000-000000000001'
);

DO $receipts$
DECLARE
  first_row fixture_0090_first_receipt%ROWTYPE;
  replay_row fixture_0090_replay_receipt%ROWTYPE;
  old_request_row fixture_0090_old_request_after_rejoin%ROWTYPE;
  new_request_row fixture_0090_new_leave_after_rejoin%ROWTYPE;
BEGIN
  SELECT * INTO STRICT first_row FROM fixture_0090_first_receipt;
  SELECT * INTO STRICT replay_row FROM fixture_0090_replay_receipt;
  SELECT * INTO STRICT old_request_row
  FROM fixture_0090_old_request_after_rejoin;
  SELECT * INTO STRICT new_request_row
  FROM fixture_0090_new_leave_after_rejoin;

  IF first_row IS DISTINCT FROM replay_row
    OR first_row IS DISTINCT FROM old_request_row
    OR first_row.membership_self_leave_contract_id IS DISTINCT FROM
      'organization-membership-self-leave:v1'
    OR first_row.organization_workspace_id IS DISTINCT FROM
      '00000000-0090-2000-0000-000000000001'::uuid
    OR first_row.organization_membership_id IS DISTINCT FROM
      '00000000-0090-2100-0000-000000000010'::uuid
    OR new_request_row.organization_membership_id IS DISTINCT FROM
      '00000000-0090-2100-0000-000000000011'::uuid
    OR new_request_row.effective_at_utc <= first_row.effective_at_utc
    OR (SELECT count(*) FROM fixture_0090_past_owner_receipt) <> 1
  THEN
    RAISE EXCEPTION '0090 success/replay/rejoin receipt contract drifted';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_membership_id =
          first_row.organization_membership_id
        AND membership.inactive_from_utc = first_row.effective_at_utc
    )
    OR (
      SELECT count(*)
      FROM app_private.organization_membership_self_leave_request_claims
      WHERE request_id IN (
        '00000000-0090-3000-0000-000000000101',
        '00000000-0090-3000-0000-000000000102',
        '00000000-0090-3000-0000-000000000103'
      )
    ) <> 3
    OR (
      SELECT count(*)
      FROM app_private.organization_membership_self_leave_audit_events
      WHERE request_id IN (
        '00000000-0090-3000-0000-000000000101',
        '00000000-0090-3000-0000-000000000102',
        '00000000-0090-3000-0000-000000000103'
      )
    ) <> 3
  THEN
    RAISE EXCEPTION '0090 success facts are incomplete';
  END IF;
END
$receipts$;

CREATE TEMP TABLE fixture_0090_failure_counts ON COMMIT DROP AS
SELECT
  (SELECT count(*)
   FROM app_private.organization_membership_self_leave_request_claims)
    AS claim_count,
  (SELECT count(*)
   FROM app_private.organization_membership_self_leave_audit_events)
    AS audit_count;

SELECT pg_temp.expect_0090_failure(
  'null request',
  '22023',
  'invalid organization membership self-leave request',
  'SELECT * FROM app_private.leave_organization_membership_v1('
    || quote_literal('00000000-0090-0000-0000-000000000002')
    || '::uuid, NULL, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'null workspace',
  '22023',
  'invalid organization membership self-leave request',
  'SELECT * FROM app_private.leave_organization_membership_v1('
    || quote_literal('00000000-0090-0000-0000-000000000002')
    || '::uuid, '
    || quote_literal('00000000-0090-3000-0000-000000000105')
    || '::uuid, NULL)'
);

SELECT pg_temp.expect_0090_failure(
  'current owner dependency',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('current-owner-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000106')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'future owner dependency',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('future-owner-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000107')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'project membership history',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('project-history-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000108')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'active organization target assignment',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('target-assignment-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000109')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'scheduled membership end',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('scheduled-end-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000110')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'organization recovery',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('recovery-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000111')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000002')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'nullified actor claim',
  '22023',
  'organization membership self-leave idempotency conflict',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('nullified-claim-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000003')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'request tombstone',
  '22023',
  'organization membership self-leave idempotency conflict',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('integration-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000004')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'workspace drift',
  '22023',
  'organization membership self-leave idempotency conflict',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('successful-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000101')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000002')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'actor drift',
  '22023',
  'organization membership self-leave idempotency conflict',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal('integration-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000101')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'trimmed identity is not normalized',
  '42501',
  'organization membership self-leave forbidden',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal('https://synthetic-0090.example/auth/v1') || ', '
    || quote_literal(' integration-member ') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000112')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

SELECT pg_temp.expect_0090_failure(
  'blank identity',
  '22023',
  'invalid organization membership self-leave identity',
  'SELECT * FROM app_data.leave_organization_membership_for_identity_v1('
    || quote_literal(' ') || ', '
    || quote_literal('integration-member') || ', '
    || quote_literal('00000000-0090-3000-0000-000000000113')
    || '::uuid, '
    || quote_literal('00000000-0090-2000-0000-000000000001')
    || '::uuid)'
);

DO $failure_atomicity$
DECLARE
  before_counts fixture_0090_failure_counts%ROWTYPE;
  after_claims bigint;
  after_audits bigint;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0090_failure_counts;
  SELECT count(*) INTO after_claims
  FROM app_private.organization_membership_self_leave_request_claims;
  SELECT count(*) INTO after_audits
  FROM app_private.organization_membership_self_leave_audit_events;

  IF after_claims <> before_counts.claim_count
    OR after_audits <> before_counts.audit_count
    OR EXISTS (
      SELECT 1
      FROM app_data.organization_memberships AS membership
      WHERE membership.organization_membership_id IN (
          '00000000-0090-2100-0000-000000000020',
          '00000000-0090-2100-0000-000000000030',
          '00000000-0090-2100-0000-000000000040',
          '00000000-0090-2100-0000-000000000050'
        )
        AND membership.inactive_from_utc IS NOT NULL
    )
  THEN
    RAISE EXCEPTION '0090 forbidden requests wrote partial facts';
  END IF;
END
$failure_atomicity$;

-- Claim actor deassociation is the sole allowed mutation; all second changes,
-- tombstone changes, and audit changes stay append-only.
SELECT pg_temp.expect_0090_failure(
  'claim second mutation',
  '55000',
  'organization membership self-leave request claim is immutable',
  'UPDATE app_private.organization_membership_self_leave_request_claims '
    || 'SET organization_workspace_id = '
    || quote_literal('00000000-0090-2000-0000-000000000002')
    || '::uuid WHERE request_id = '
    || quote_literal('00000000-0090-3000-0000-000000000003')
    || '::uuid'
);

SELECT pg_temp.expect_0090_failure(
  'claim delete',
  '55000',
  'organization membership self-leave request claim cannot be deleted',
  'DELETE FROM app_private.organization_membership_self_leave_request_claims '
    || 'WHERE request_id = '
    || quote_literal('00000000-0090-3000-0000-000000000003')
    || '::uuid'
);

SELECT pg_temp.expect_0090_failure(
  'tombstone mutation',
  '55000',
  'organization membership self-leave request tombstone is immutable',
  'DELETE FROM app_private.organization_membership_self_leave_request_tombstones '
    || 'WHERE request_id = '
    || quote_literal('00000000-0090-3000-0000-000000000004')
    || '::uuid'
);

SELECT pg_temp.expect_0090_failure(
  'audit mutation',
  '55000',
  'organization membership self-leave audit is append-only',
  'UPDATE app_private.organization_membership_self_leave_audit_events '
    || 'SET effective_at_utc = clock_timestamp() WHERE request_id = '
    || quote_literal('00000000-0090-3000-0000-000000000101')
    || '::uuid'
);

ROLLBACK;
