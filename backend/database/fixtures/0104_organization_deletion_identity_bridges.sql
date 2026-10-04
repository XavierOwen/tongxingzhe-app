-- Synthetic 0104 bridge proof. All identity, lifecycle, and audit rows roll back.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.expect_0104_failure(
  expected_state text, expected_message text, statement text
) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; actual_message text;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state
    OR actual_message IS DISTINCT FROM expected_message
  THEN
    RAISE EXCEPTION '0104 expected % / %, got % / %',
      expected_state, expected_message, actual_state, actual_message;
  END IF;
END
$function$;

INSERT INTO app_data.app_users(app_user_id, status) VALUES
  ('00000000-0104-0000-8000-000000000001', 'active'),
  ('00000000-0104-0000-8000-000000000002', 'active'),
  ('00000000-0104-0000-8000-000000000003', 'active'),
  ('00000000-0104-0000-8000-000000000004', 'deletion_pending');
INSERT INTO app_data.external_identities(issuer, subject, app_user_id) VALUES
  (' https://synthetic-0104.example/issuer ', 'owner one',
    '00000000-0104-0000-8000-000000000001'),
  (' https://synthetic-0104.example/issuer ', 'owner two',
    '00000000-0104-0000-8000-000000000002'),
  (' https://synthetic-0104.example/issuer ', 'member',
    '00000000-0104-0000-8000-000000000003'),
  (' https://synthetic-0104.example/issuer ', 'inactive',
    '00000000-0104-0000-8000-000000000004');

CREATE TEMP TABLE fixture_0104_org AS
SELECT * FROM app_private.create_organization_v1(
  '00000000-0104-0000-8000-000000000001'::uuid,
  '00000000-0104-1000-8000-000000000001'::uuid,
  '0104 synthetic organization');
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
SELECT '00000000-0104-2000-8000-000000000002', organization_workspace_id,
  '00000000-0104-0000-8000-000000000002', transaction_timestamp(), NULL
FROM fixture_0104_org;
INSERT INTO app_data.organization_owner_assignments(
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc
) VALUES (
  '00000000-0104-3000-8000-000000000002',
  '00000000-0104-2000-8000-000000000002', transaction_timestamp(), NULL
);
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
SELECT '00000000-0104-2000-8000-000000000003', organization_workspace_id,
  '00000000-0104-0000-8000-000000000003', transaction_timestamp(), NULL
FROM fixture_0104_org;

GRANT SELECT ON fixture_0104_org TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0104_first AS
SELECT receipt.* FROM fixture_0104_org AS org,
LATERAL app_data.request_organization_deletion_for_identity_v1(
  ' https://synthetic-0104.example/issuer ', 'owner one',
  '00000000-0104-4000-8000-000000000001'::uuid,
  org.organization_workspace_id) AS receipt;
CREATE TEMP TABLE fixture_0104_replay AS
SELECT receipt.* FROM fixture_0104_org AS org,
LATERAL app_data.request_organization_deletion_for_identity_v1(
  ' https://synthetic-0104.example/issuer ', 'owner one',
  '00000000-0104-4000-8000-000000000001'::uuid,
  org.organization_workspace_id) AS receipt;
RESET ROLE;

DO $fixture$
DECLARE first_row fixture_0104_first%ROWTYPE;
BEGIN
  SELECT * INTO STRICT first_row FROM fixture_0104_first;
  IF first_row.organization_deletion_contract_id IS DISTINCT FROM
      'organization-deletion-request:v1'
    OR first_row.deletion_request_id IS DISTINCT FROM
      '00000000-0104-4000-8000-000000000001'
    OR first_row.purge_after_utc IS DISTINCT FROM
      first_row.effective_at_utc + interval '720 hours'
    OR first_row.effective_at_utc > clock_timestamp()
    OR (SELECT count(*) FROM fixture_0104_replay) <> 1
    OR EXISTS ((TABLE fixture_0104_first EXCEPT TABLE fixture_0104_replay)
      UNION ALL (TABLE fixture_0104_replay EXCEPT TABLE fixture_0104_first))
  THEN RAISE EXCEPTION '0104 request receipt or exact replay drifted'; END IF;
END
$fixture$;

CREATE TEMP TABLE fixture_0104_before_request_failures AS
SELECT
  (SELECT count(*) FROM app_private.organization_deletion_current) AS attempts,
  (SELECT count(*) FROM app_private.organization_deletion_request_claims) AS deletion_claims,
  (SELECT count(*) FROM app_private.organization_deletion_restore_claims) AS restore_claims,
  (SELECT count(*) FROM app_private.organization_deletion_audit_events) AS audit_events;
SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0104_org);
BEGIN
  PERFORM pg_temp.expect_0104_failure('42501', 'organization deletion forbidden',
    format('SELECT * FROM app_data.request_organization_deletion_for_identity_v1(%L,%L,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'member',
      '00000000-0104-4000-8000-000000000002', org_id));
  PERFORM pg_temp.expect_0104_failure('42501', 'organization deletion forbidden',
    format('SELECT * FROM app_data.request_organization_deletion_for_identity_v1(%L,%L,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'inactive',
      '00000000-0104-4000-8000-000000000003', org_id));
  PERFORM pg_temp.expect_0104_failure('42501', 'organization deletion forbidden',
    format('SELECT * FROM app_data.request_organization_deletion_for_identity_v1(%L,%L,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'unknown',
      '00000000-0104-4000-8000-000000000004', org_id));
  PERFORM pg_temp.expect_0104_failure('22023',
    'invalid organization deletion request identity',
    format('SELECT * FROM app_data.request_organization_deletion_for_identity_v1(%L,%L,%L::uuid,%L::uuid)',
      ' ', 'owner one',
      '00000000-0104-4000-8000-000000000005', org_id));
  PERFORM pg_temp.expect_0104_failure('22023',
    'organization deletion idempotency conflict',
    format('SELECT * FROM app_data.request_organization_deletion_for_identity_v1(%L,%L,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'owner two',
      '00000000-0104-4000-8000-000000000001', org_id));
  PERFORM pg_temp.expect_0104_failure('42501', 'organization restoration forbidden',
    format('SELECT * FROM app_data.restore_organization_for_identity_v1(%L,%L,%L::uuid,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'inactive',
      '00000000-0104-5000-8000-000000000003', org_id,
      '00000000-0104-4000-8000-000000000001'));
  PERFORM pg_temp.expect_0104_failure('42501', 'organization restoration forbidden',
    format('SELECT * FROM app_data.restore_organization_for_identity_v1(%L,%L,%L::uuid,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'unknown',
      '00000000-0104-5000-8000-000000000004', org_id,
      '00000000-0104-4000-8000-000000000001'));
  PERFORM pg_temp.expect_0104_failure('42501', 'organization restoration forbidden',
    format('SELECT * FROM app_data.restore_organization_for_identity_v1(%L,%L,%L::uuid,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'member',
      '00000000-0104-5000-8000-000000000005', org_id,
      '00000000-0104-4000-8000-000000000001'));
END
$fixture$;
RESET ROLE;
DO $fixture$
BEGIN
  IF (SELECT attempts FROM fixture_0104_before_request_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_current)
    OR (SELECT deletion_claims FROM fixture_0104_before_request_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_request_claims)
    OR (SELECT restore_claims FROM fixture_0104_before_request_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_restore_claims)
    OR (SELECT audit_events FROM fixture_0104_before_request_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_audit_events)
  THEN RAISE EXCEPTION '0104 rejected requests left partial writes'; END IF;
END
$fixture$;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0104_restored AS
SELECT receipt.* FROM fixture_0104_org AS org,
LATERAL app_data.restore_organization_for_identity_v1(
  ' https://synthetic-0104.example/issuer ', 'owner two',
  '00000000-0104-5000-8000-000000000001'::uuid,
  org.organization_workspace_id,
  '00000000-0104-4000-8000-000000000001'::uuid) AS receipt;
CREATE TEMP TABLE fixture_0104_restore_replay AS
SELECT receipt.* FROM fixture_0104_org AS org,
LATERAL app_data.restore_organization_for_identity_v1(
  ' https://synthetic-0104.example/issuer ', 'owner two',
  '00000000-0104-5000-8000-000000000001'::uuid,
  org.organization_workspace_id,
  '00000000-0104-4000-8000-000000000001'::uuid) AS receipt;
RESET ROLE;
DO $fixture$
DECLARE restored fixture_0104_restored%ROWTYPE;
BEGIN
  SELECT * INTO STRICT restored FROM fixture_0104_restored;
  IF restored.organization_deletion_restore_contract_id IS DISTINCT FROM
      'organization-deletion-restore:v1'
    OR restored.deletion_request_id IS DISTINCT FROM
      '00000000-0104-4000-8000-000000000001'
    OR (SELECT count(*) FROM fixture_0104_restore_replay) <> 1
    OR EXISTS ((TABLE fixture_0104_restored EXCEPT TABLE fixture_0104_restore_replay)
      UNION ALL (TABLE fixture_0104_restore_replay EXCEPT TABLE fixture_0104_restored))
    OR (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = restored.organization_workspace_id) <> 2
  THEN RAISE EXCEPTION '0104 restore receipt or exact replay drifted'; END IF;
END
$fixture$;

SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE fixture_0104_next_cycle AS
SELECT receipt.* FROM fixture_0104_org AS org,
LATERAL app_data.request_organization_deletion_for_identity_v1(
  ' https://synthetic-0104.example/issuer ', 'owner two',
  '00000000-0104-4000-8000-000000000002'::uuid,
  org.organization_workspace_id) AS receipt;
RESET ROLE;

CREATE TEMP TABLE fixture_0104_before_restore_failures AS
SELECT
  (SELECT count(*) FROM app_private.organization_deletion_current) AS attempts,
  (SELECT count(*) FROM app_private.organization_deletion_request_claims) AS deletion_claims,
  (SELECT count(*) FROM app_private.organization_deletion_restore_claims) AS restore_claims,
  (SELECT count(*) FROM app_private.organization_deletion_audit_events) AS audit_events;
-- Preserve the 0100 720-hour relation while moving this selector past expiry.
WITH expired AS MATERIALIZED (
  SELECT clock_timestamp() - interval '721 hours' AS effective_at_utc
)
UPDATE app_private.organization_deletion_current AS attempt
SET effective_at_utc = expired.effective_at_utc,
    purge_after_utc = expired.effective_at_utc + interval '720 hours'
FROM expired
WHERE attempt.organization_workspace_id =
  (SELECT organization_workspace_id FROM fixture_0104_org);
UPDATE app_data.workspaces
SET deleted_at = (SELECT effective_at_utc
  FROM app_private.organization_deletion_current
  WHERE organization_workspace_id = app_data.workspaces.workspace_id)
WHERE workspace_id = (SELECT organization_workspace_id FROM fixture_0104_org);

SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0104_org);
BEGIN
  PERFORM pg_temp.expect_0104_failure('22023',
    'organization restoration idempotency conflict',
    format('SELECT * FROM app_data.restore_organization_for_identity_v1(%L,%L,%L::uuid,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'owner two',
      '00000000-0104-5000-8000-000000000001', org_id,
      '00000000-0104-4000-8000-000000000001'));
  PERFORM pg_temp.expect_0104_failure('22023',
    'organization restoration idempotency conflict',
    format('SELECT * FROM app_data.restore_organization_for_identity_v1(%L,%L,%L::uuid,%L::uuid,%L::uuid)',
      ' https://synthetic-0104.example/issuer ', 'owner one',
      '00000000-0104-5000-8000-000000000002', org_id,
      '00000000-0104-4000-8000-000000000002'));
END
$fixture$;
RESET ROLE;
DO $fixture$
BEGIN
  IF (SELECT attempts FROM fixture_0104_before_restore_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_current)
    OR (SELECT deletion_claims FROM fixture_0104_before_restore_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_request_claims)
    OR (SELECT restore_claims FROM fixture_0104_before_restore_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_restore_claims)
    OR (SELECT audit_events FROM fixture_0104_before_restore_failures) IS DISTINCT FROM
      (SELECT count(*) FROM app_private.organization_deletion_audit_events)
  THEN RAISE EXCEPTION '0104 rejected restores left partial writes'; END IF;
END
$fixture$;

ROLLBACK;
