-- Synthetic rollback fixture for directed invitation preview.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
SELECT
  format(
    '00000000-0091-0000-0000-%s',
    lpad(user_ordinal::text, 12, '0')
  )::uuid,
  'active'
FROM generate_series(1, 14) AS generated_user(user_ordinal);

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
SELECT
  format(
    '00000000-0091-1000-0000-%s',
    lpad(identity_row.user_ordinal::text, 12, '0')
  )::uuid,
  'https://synthetic-0091.example/auth/v1',
  identity_row.subject,
  format(
    '00000000-0091-0000-0000-%s',
    lpad(identity_row.user_ordinal::text, 12, '0')
  )::uuid
FROM (
  VALUES
    (2, 'preview-target'),
    (3, 'wrong-target'),
    (4, 'deletion-pending-target'),
    (5, 'accepted-target'),
    (6, 'current-member-target'),
    (7, 'boundary-start-target'),
    (8, 'boundary-end-target'),
    (9, 'recovery-target'),
    (10, 'personal-target'),
    (11, 'expired-target'),
    (12, ' preview-target '),
    (13, 'deleted-target'),
    (14, 'elapsed-expiry-target')
) AS identity_row(user_ordinal, subject);

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
    '00000000-0091-2000-0000-000000000001',
    'organization',
    ' 0091 Original 组织名称 ',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0091-2000-0000-000000000002',
    'organization',
    '0091 recovery organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0091-2000-0000-000000000003',
    'personal',
    '0091 personal workspace',
    '00000000-0091-0000-0000-000000000001',
    NULL,
    transaction_timestamp() - interval '1 day'
  );

INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
VALUES
  (
    '00000000-0091-3000-0000-000000000001',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000002',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000002',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000012',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000003',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000004',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000004',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000005',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    transaction_timestamp() - interval '30 minutes',
    '00000000-0091-3900-0000-000000000004'
  ),
  (
    '00000000-0091-3000-0000-000000000005',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000006',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000006',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000007',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000007',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000008',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000008',
    '00000000-0091-2000-0000-000000000002',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000009',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000009',
    '00000000-0091-2000-0000-000000000003',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000010',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000010',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000011',
    transaction_timestamp() - interval '168 hours',
    transaction_timestamp(),
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000011',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000002',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000012',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000002',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
  ),
  (
    '00000000-0091-3000-0000-000000000013',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000001',
    '00000000-0091-0000-0000-000000000013',
    transaction_timestamp() - interval '1 hour',
    transaction_timestamp() + interval '167 hours',
    NULL,
    NULL
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
    '00000000-0091-4000-0000-000000000001',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000006',
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0091-4000-0000-000000000002',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000007',
    transaction_timestamp(),
    NULL
  ),
  (
    '00000000-0091-4000-0000-000000000003',
    '00000000-0091-2000-0000-000000000001',
    '00000000-0091-0000-0000-000000000008',
    transaction_timestamp() - interval '1 day',
    transaction_timestamp()
  );

-- These state changes happen after claims exist, so preview must re-observe
-- account, workspace, and unlink state without exposing which fact failed.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0091-0000-0000-000000000004';

UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '00000000-0091-0000-0000-000000000013';

UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp() + interval '30 days'
WHERE workspace_id = '00000000-0091-2000-0000-000000000002';

UPDATE app_private.organization_directed_account_invitation_request_claims
SET inviter_app_user_id = NULL
WHERE invitation_id = '00000000-0091-3000-0000-000000000011';

UPDATE app_private.organization_directed_account_invitation_request_claims
SET target_app_user_id = NULL
WHERE invitation_id = '00000000-0091-3000-0000-000000000012';

-- This claim expires after this transaction began but before its preview.
WITH expiry_boundary AS MATERIALIZED (
  SELECT clock_timestamp() + interval '500 milliseconds' AS expires_at_utc
)
INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
SELECT
  '00000000-0091-3000-0000-000000000014',
  '00000000-0091-2000-0000-000000000001',
  '00000000-0091-0000-0000-000000000001',
  '00000000-0091-0000-0000-000000000014',
  expiry_boundary.expires_at_utc - interval '168 hours',
  expiry_boundary.expires_at_utc,
  NULL,
  NULL
FROM expiry_boundary;

DO $early_transaction$
DECLARE
  expiry_time timestamptz;
BEGIN
  SELECT claim.expires_at_utc
  INTO STRICT expiry_time
  FROM app_private.organization_directed_account_invitation_request_claims
    AS claim
  WHERE claim.invitation_id =
    '00000000-0091-3000-0000-000000000014'::uuid;

  IF transaction_timestamp() >= expiry_time THEN
    RAISE EXCEPTION '0091 transaction did not begin before expiry';
  END IF;
END
$early_transaction$;

SELECT pg_sleep(0.75);

CREATE TEMP TABLE fixture_0091_counts_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_user_count,
  (SELECT count(*) FROM app_data.external_identities) AS identity_count,
  (SELECT count(*) FROM app_data.workspaces) AS workspace_count,
  (SELECT count(*) FROM app_data.organization_memberships)
    AS organization_membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments)
    AS owner_assignment_count,
  (
    SELECT count(*)
    FROM app_private.organization_directed_account_invitation_request_claims
  ) AS invitation_claim_count,
  (
    SELECT count(*)
    FROM app_private.organization_directed_account_invitation_request_tombstones
  ) AS invitation_tombstone_count,
  (
    SELECT count(*)
    FROM app_private.organization_directed_account_invitation_audit_events
  ) AS invitation_audit_count;

CREATE TEMP TABLE fixture_0091_previews (
  organization_invitation_preview_contract_id text,
  invitation_id uuid,
  organization_name text,
  expires_at_utc timestamptz
) ON COMMIT DROP;

GRANT ALL ON fixture_0091_previews TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0091_previews
SELECT *
FROM app_data.preview_organization_directed_invitation_for_identity_v1(
  'https://synthetic-0091.example/auth/v1',
  'preview-target',
  '00000000-0091-3000-0000-000000000001'
);

INSERT INTO fixture_0091_previews
SELECT *
FROM app_data.preview_organization_directed_invitation_for_identity_v1(
  'https://synthetic-0091.example/auth/v1',
  ' preview-target ',
  '00000000-0091-3000-0000-000000000002'
);

INSERT INTO fixture_0091_previews
SELECT *
FROM app_data.preview_organization_directed_invitation_for_identity_v1(
  'https://synthetic-0091.example/auth/v1',
  'boundary-end-target',
  '00000000-0091-3000-0000-000000000007'
);

RESET ROLE;

DO $preview_results$
DECLARE
  result_ids uuid[];
BEGIN
  SELECT array_agg(preview.invitation_id ORDER BY preview.invitation_id)
  INTO result_ids
  FROM fixture_0091_previews AS preview;

  IF result_ids IS DISTINCT FROM ARRAY[
      '00000000-0091-3000-0000-000000000001'::uuid,
      '00000000-0091-3000-0000-000000000002'::uuid,
      '00000000-0091-3000-0000-000000000007'::uuid
    ]::uuid[]
    OR EXISTS (
      SELECT 1
      FROM fixture_0091_previews AS preview
      WHERE preview.organization_invitation_preview_contract_id IS DISTINCT FROM
          'organization-directed-account-invitation-preview:v1'
        OR preview.organization_name IS DISTINCT FROM
          ' 0091 Original 组织名称 '
        OR preview.expires_at_utc <= clock_timestamp()
    )
  THEN
    RAISE EXCEPTION
      '0091 invitation preview result drifted: %', result_ids;
  END IF;
END
$preview_results$;

CREATE OR REPLACE FUNCTION pg_temp.expect_0091_preview_failure(
  case_name text,
  expected_sqlstate text,
  expected_message text,
  checked_issuer text,
  checked_subject text,
  checked_invitation_id uuid
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
    PERFORM 1
    FROM app_data.preview_organization_directed_invitation_for_identity_v1(
      checked_issuer,
      checked_subject,
      checked_invitation_id
    );
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
        '0091 % expected SQLSTATE/message %, % but got %, %',
        case_name,
        expected_sqlstate,
        expected_message,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0091 % unexpectedly succeeded', case_name;
END
$function$;

SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0091_preview_failure(
  failure_case.case_name,
  failure_case.expected_sqlstate,
  failure_case.expected_message,
  failure_case.checked_issuer,
  failure_case.checked_subject,
  failure_case.checked_invitation_id
)
FROM (
  VALUES
    (
      'null invitation',
      '22023',
      'invalid organization invitation request',
      'https://synthetic-0091.example/auth/v1',
      'preview-target',
      NULL::uuid
    ),
    (
      'null issuer',
      '22023',
      'invalid organization invitation identity',
      NULL,
      'preview-target',
      '00000000-0091-3000-0000-000000000001'::uuid
    ),
    (
      'space subject',
      '22023',
      'invalid organization invitation identity',
      'https://synthetic-0091.example/auth/v1',
      ' ',
      '00000000-0091-3000-0000-000000000001'::uuid
    ),
    (
      'oversized subject',
      '22023',
      'invalid organization invitation identity',
      'https://synthetic-0091.example/auth/v1',
      repeat('s', 513),
      '00000000-0091-3000-0000-000000000001'::uuid
    ),
    (
      'unmapped trimmed identity',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'preview-target ',
      '00000000-0091-3000-0000-000000000002'::uuid
    ),
    (
      'unknown invitation',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'preview-target',
      '00000000-0091-3000-0000-000000009999'::uuid
    ),
    (
      'wrong target',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'wrong-target',
      '00000000-0091-3000-0000-000000000001'::uuid
    ),
    (
      'deletion pending target',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'deletion-pending-target',
      '00000000-0091-3000-0000-000000000003'::uuid
    ),
    (
      'deleted target',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'deleted-target',
      '00000000-0091-3000-0000-000000000013'::uuid
    ),
    (
      'accepted invitation',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'accepted-target',
      '00000000-0091-3000-0000-000000000004'::uuid
    ),
    (
      'current member',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'current-member-target',
      '00000000-0091-3000-0000-000000000005'::uuid
    ),
    (
      'membership start boundary',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'boundary-start-target',
      '00000000-0091-3000-0000-000000000006'::uuid
    ),
    (
      'recovery workspace',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'recovery-target',
      '00000000-0091-3000-0000-000000000008'::uuid
    ),
    (
      'personal workspace',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'personal-target',
      '00000000-0091-3000-0000-000000000009'::uuid
    ),
    (
      'expiry boundary',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'expired-target',
      '00000000-0091-3000-0000-000000000010'::uuid
    ),
    (
      'transaction elapsed expiry',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'elapsed-expiry-target',
      '00000000-0091-3000-0000-000000000014'::uuid
    ),
    (
      'unlinked inviter',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'preview-target',
      '00000000-0091-3000-0000-000000000011'::uuid
    ),
    (
      'unlinked target',
      '42501',
      'organization invitation forbidden',
      'https://synthetic-0091.example/auth/v1',
      'preview-target',
      '00000000-0091-3000-0000-000000000012'::uuid
    )
) AS failure_case(
  case_name,
  expected_sqlstate,
  expected_message,
  checked_issuer,
  checked_subject,
  checked_invitation_id
);

RESET ROLE;

DO $read_only$
DECLARE
  before_counts fixture_0091_counts_before%ROWTYPE;
  after_counts fixture_0091_counts_before%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0091_counts_before;

  SELECT
    (SELECT count(*) FROM app_data.app_users),
    (SELECT count(*) FROM app_data.external_identities),
    (SELECT count(*) FROM app_data.workspaces),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (
      SELECT count(*)
      FROM app_private.organization_directed_account_invitation_request_claims
    ),
    (
      SELECT count(*)
      FROM app_private.organization_directed_account_invitation_request_tombstones
    ),
    (
      SELECT count(*)
      FROM app_private.organization_directed_account_invitation_audit_events
    )
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts THEN
    RAISE EXCEPTION
      '0091 invitation preview wrote facts: before %, after %',
      before_counts,
      after_counts;
  END IF;
END
$read_only$;

ROLLBACK;
