-- Synthetic 0100 contract proof. Every fact in this file rolls back.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.expect_0100_failure(
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
    OR actual_message IS DISTINCT FROM expected_message THEN
    RAISE EXCEPTION '0100 expected % / %, got % / %',
      expected_state, expected_message, actual_state, actual_message;
  END IF;
END
$function$;

INSERT INTO app_data.app_users(app_user_id, status) VALUES
  ('00000000-0100-0000-8000-000000000001', 'active'),
  ('00000000-0100-0000-8000-000000000002', 'active'),
  ('00000000-0100-0000-8000-000000000003', 'active'),
  ('00000000-0100-0000-8000-000000000004', 'deletion_pending');

INSERT INTO app_data.workspaces(
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  '00000000-0100-1000-8000-000000000099', 'personal',
  '0100 synthetic personal workspace',
  '00000000-0100-0000-8000-000000000001'
);

CREATE TEMP TABLE fixture_0100_org AS
SELECT * FROM app_private.create_organization_v1(
  '00000000-0100-0000-8000-000000000001'::uuid,
  '00000000-0100-1000-8000-000000000001'::uuid,
  '0100 synthetic organization');

-- A second current owner may restore even when they did not request deletion.
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc)
SELECT '00000000-0100-2000-8000-000000000002',
  organization_workspace_id, '00000000-0100-0000-8000-000000000002',
  transaction_timestamp(), NULL
FROM fixture_0100_org;
INSERT INTO app_data.organization_owner_assignments(
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc)
VALUES ('00000000-0100-3000-8000-000000000002',
  '00000000-0100-2000-8000-000000000002', transaction_timestamp(), NULL);

CREATE TEMP TABLE fixture_0100_first AS
SELECT receipt.* FROM fixture_0100_org AS org,
LATERAL app_private.request_organization_deletion_v1(
  '00000000-0100-0000-8000-000000000001'::uuid,
  '00000000-0100-4000-8000-000000000001'::uuid,
  org.organization_workspace_id) AS receipt;
CREATE TEMP TABLE fixture_0100_replay AS
SELECT receipt.* FROM fixture_0100_org AS org,
LATERAL app_private.request_organization_deletion_v1(
  '00000000-0100-0000-8000-000000000001'::uuid,
  '00000000-0100-4000-8000-000000000001'::uuid,
  org.organization_workspace_id) AS receipt;

DO $fixture$
DECLARE first_row fixture_0100_first%ROWTYPE;
BEGIN
  SELECT * INTO STRICT first_row FROM fixture_0100_first;
  IF (SELECT count(*) FROM fixture_0100_replay) <> 1
    OR EXISTS ((TABLE fixture_0100_first EXCEPT TABLE fixture_0100_replay)
      UNION ALL (TABLE fixture_0100_replay EXCEPT TABLE fixture_0100_first))
    OR first_row.organization_deletion_contract_id IS DISTINCT FROM
      'organization-deletion-request:v1'
    OR first_row.deletion_request_id <> '00000000-0100-4000-8000-000000000001'
    OR first_row.purge_after_utc <> first_row.effective_at_utc + interval '720 hours'
    OR first_row.effective_at_utc > clock_timestamp()
    OR NOT isfinite(first_row.effective_at_utc)
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_deletion_current AS attempt
      JOIN app_data.workspaces AS workspace
        ON workspace.workspace_id = attempt.organization_workspace_id
      WHERE attempt.organization_workspace_id = first_row.organization_workspace_id
        AND attempt.deletion_request_id = first_row.deletion_request_id
        AND attempt.effective_at_utc = first_row.effective_at_utc
        AND attempt.purge_after_utc = first_row.purge_after_utc
        AND attempt.status = 'deletion_pending'
        AND attempt.restored_at_utc IS NULL
        AND workspace.deleted_at = first_row.effective_at_utc)
    OR (SELECT count(*) FROM app_private.organization_deletion_request_claims
      WHERE request_id = first_row.deletion_request_id) <> 1
    OR (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE request_id = first_row.deletion_request_id) <> 1
  THEN RAISE EXCEPTION '0100 first request, receipt, exact replay, or 720h drifted'; END IF;
END
$fixture$;

CREATE TEMP TABLE fixture_0100_unproven AS
SELECT * FROM app_private.create_organization_v1(
  '00000000-0100-0000-8000-000000000001'::uuid,
  '00000000-0100-1000-8000-000000000098'::uuid,
  '0100 unavailable synthetic organization');
UPDATE app_data.workspaces SET deleted_at = clock_timestamp()
WHERE workspace_id = (SELECT organization_workspace_id FROM fixture_0100_unproven);

DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0100_org);
  unavailable_org_id uuid := (
  SELECT organization_workspace_id FROM fixture_0100_unproven
);
BEGIN
  PERFORM pg_temp.expect_0100_failure('22023', 'invalid organization deletion request',
    format('SELECT * FROM app_private.request_organization_deletion_v1(NULL, NULL, %L::uuid)', org_id));
  PERFORM pg_temp.expect_0100_failure('42501', 'organization deletion forbidden',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, gen_random_uuid(), %L::uuid)',
      '00000000-0100-0000-8000-000000000003', org_id));
  PERFORM pg_temp.expect_0100_failure('42501', 'organization deletion forbidden',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, gen_random_uuid(), %L::uuid)',
      '00000000-0100-0000-8000-000000000004', org_id));
  PERFORM pg_temp.expect_0100_failure('42501', 'organization deletion forbidden',
    'SELECT * FROM app_private.request_organization_deletion_v1('
      || '''00000000-0100-0000-8000-000000000001''::uuid, gen_random_uuid(), '
      || '''00000000-0100-1000-8000-000000000099''::uuid)');
  PERFORM pg_temp.expect_0100_failure('42501', 'organization deletion forbidden',
    'SELECT * FROM app_private.request_organization_deletion_v1('
      || '''00000000-0100-0000-8000-000000000001''::uuid, gen_random_uuid(), '
      || '''00000000-0100-1000-8000-000000000097''::uuid)');
  PERFORM pg_temp.expect_0100_failure('55000', 'organization deletion unavailable',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, gen_random_uuid(), %L::uuid)',
      '00000000-0100-0000-8000-000000000001', unavailable_org_id));
  PERFORM pg_temp.expect_0100_failure('22023', 'organization deletion idempotency conflict',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000002',
      '00000000-0100-4000-8000-000000000001', org_id));
  PERFORM pg_temp.expect_0100_failure('22023', 'organization deletion idempotency conflict',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, gen_random_uuid(), %L::uuid)',
      '00000000-0100-0000-8000-000000000002', org_id));
  PERFORM pg_temp.expect_0100_failure('22023', 'invalid organization restoration request',
    format('SELECT * FROM app_private.restore_organization_v1(NULL, NULL, %L::uuid, NULL)', org_id));
  PERFORM pg_temp.expect_0100_failure('22023', 'organization restoration idempotency conflict',
    format('SELECT * FROM app_private.restore_organization_v1(%L::uuid, gen_random_uuid(), %L::uuid, gen_random_uuid())',
      '00000000-0100-0000-8000-000000000002', org_id));
  PERFORM pg_temp.expect_0100_failure('42501', 'organization restoration forbidden',
    format('SELECT * FROM app_private.restore_organization_v1(%L::uuid, gen_random_uuid(), %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000003', org_id,
      '00000000-0100-4000-8000-000000000001'));
  PERFORM pg_temp.expect_0100_failure('42501', 'organization restoration forbidden',
    'SELECT * FROM app_private.restore_organization_v1('
      || '''00000000-0100-0000-8000-000000000001''::uuid, gen_random_uuid(), '
      || '''00000000-0100-1000-8000-000000000099''::uuid, gen_random_uuid())');
  PERFORM pg_temp.expect_0100_failure('42501', 'organization restoration forbidden',
    'SELECT * FROM app_private.restore_organization_v1('
      || '''00000000-0100-0000-8000-000000000001''::uuid, gen_random_uuid(), '
      || '''00000000-0100-1000-8000-000000000097''::uuid, gen_random_uuid())');
END
$fixture$;

CREATE TEMP TABLE fixture_0100_restored AS
SELECT receipt.* FROM fixture_0100_org AS org,
LATERAL app_private.restore_organization_v1(
  '00000000-0100-0000-8000-000000000002'::uuid,
  '00000000-0100-5000-8000-000000000001'::uuid,
  org.organization_workspace_id,
  '00000000-0100-4000-8000-000000000001'::uuid) AS receipt;
CREATE TEMP TABLE fixture_0100_restore_replay AS
SELECT receipt.* FROM fixture_0100_org AS org,
LATERAL app_private.restore_organization_v1(
  '00000000-0100-0000-8000-000000000002'::uuid,
  '00000000-0100-5000-8000-000000000001'::uuid,
  org.organization_workspace_id,
  '00000000-0100-4000-8000-000000000001'::uuid) AS receipt;

DO $fixture$
DECLARE restored fixture_0100_restored%ROWTYPE;
BEGIN
  SELECT * INTO STRICT restored FROM fixture_0100_restored;
  IF restored.organization_deletion_restore_contract_id IS DISTINCT FROM
      'organization-deletion-restore:v1'
    OR restored.deletion_request_id <> '00000000-0100-4000-8000-000000000001'
    OR (SELECT count(*) FROM fixture_0100_restore_replay) <> 1
    OR EXISTS ((TABLE fixture_0100_restored EXCEPT TABLE fixture_0100_restore_replay)
      UNION ALL (TABLE fixture_0100_restore_replay EXCEPT TABLE fixture_0100_restored))
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_deletion_current AS attempt
      JOIN app_data.workspaces AS workspace
        ON workspace.workspace_id = attempt.organization_workspace_id
      WHERE attempt.organization_workspace_id = restored.organization_workspace_id
        AND attempt.status = 'restored'
        AND attempt.restored_at_utc = restored.restored_at_utc
        AND workspace.deleted_at IS NULL)
    OR (SELECT count(*) FROM app_private.organization_deletion_restore_claims
      WHERE request_id = '00000000-0100-5000-8000-000000000001') <> 1
    OR (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = restored.organization_workspace_id) <> 2
    OR (SELECT count(*) FROM app_data.organization_owner_assignments AS assignment
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE membership.organization_workspace_id = restored.organization_workspace_id
        AND membership.inactive_from_utc IS NULL
        AND assignment.inactive_from_utc IS NULL) <> 2
  THEN RAISE EXCEPTION '0100 restore or exact replay drifted'; END IF;
END
$fixture$;

CREATE TEMP TABLE fixture_0100_next AS
SELECT receipt.* FROM fixture_0100_org AS org,
LATERAL app_private.request_organization_deletion_v1(
  '00000000-0100-0000-8000-000000000002'::uuid,
  '00000000-0100-4000-8000-000000000002'::uuid,
  org.organization_workspace_id) AS receipt;

DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0100_org);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0100_next AS next_attempt
    CROSS JOIN fixture_0100_first AS first_attempt
    WHERE next_attempt.effective_at_utc > first_attempt.effective_at_utc
      AND next_attempt.deletion_request_id <> first_attempt.deletion_request_id
      AND next_attempt.purge_after_utc = next_attempt.effective_at_utc + interval '720 hours')
    OR (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = org_id) <> 3
  THEN RAISE EXCEPTION '0100 restored organization did not start a new 720h attempt'; END IF;
  PERFORM pg_temp.expect_0100_failure('22023', 'organization deletion idempotency conflict',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000001',
      '00000000-0100-4000-8000-000000000001', org_id));
  PERFORM pg_temp.expect_0100_failure('22023', 'organization restoration idempotency conflict',
    format('SELECT * FROM app_private.restore_organization_v1(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000002',
      '00000000-0100-5000-8000-000000000001', org_id,
      '00000000-0100-4000-8000-000000000001'));
  PERFORM pg_temp.expect_0100_failure('22023', 'organization restoration idempotency conflict',
    format('SELECT * FROM app_private.restore_organization_v1(%L::uuid, %L::uuid, %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000002',
      '00000000-0100-5000-8000-000000000001', org_id,
      '00000000-0100-4000-8000-000000000002'));
END
$fixture$;

-- A live exact replay does not renew owner/status authority. A privacy unlink
-- of its actor does make the same UUID unrepeatable.
UPDATE app_data.app_users SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0100-0000-8000-000000000002';
CREATE TEMP TABLE fixture_0100_next_replay AS
SELECT receipt.* FROM fixture_0100_org AS org,
LATERAL app_private.request_organization_deletion_v1(
  '00000000-0100-0000-8000-000000000002'::uuid,
  '00000000-0100-4000-8000-000000000002'::uuid,
  org.organization_workspace_id) AS receipt;
DO $fixture$
BEGIN
  IF EXISTS ((TABLE fixture_0100_next EXCEPT TABLE fixture_0100_next_replay)
    UNION ALL (TABLE fixture_0100_next_replay EXCEPT TABLE fixture_0100_next))
  THEN RAISE EXCEPTION '0100 exact replay rechecked current actor status'; END IF;
END
$fixture$;
UPDATE app_data.app_users SET status = 'active'
WHERE app_user_id = '00000000-0100-0000-8000-000000000002';

DO $fixture$
BEGIN
  PERFORM pg_temp.expect_0100_failure('55000', 'organization deletion claim is immutable',
    'UPDATE app_private.organization_deletion_request_claims '
    || 'SET purge_after_utc = purge_after_utc + interval ''1 hour'' '
    || 'WHERE request_id = ''00000000-0100-4000-8000-000000000002''');
  PERFORM pg_temp.expect_0100_failure('55000', 'organization deletion claim cannot be deleted',
    'DELETE FROM app_private.organization_deletion_restore_claims '
    || 'WHERE request_id = ''00000000-0100-5000-8000-000000000001''');
  PERFORM pg_temp.expect_0100_failure('55000', 'organization deletion audit is append-only',
    'UPDATE app_private.organization_deletion_audit_events '
    || 'SET occurred_at_utc = occurred_at_utc '
    || 'WHERE request_id = ''00000000-0100-4000-8000-000000000002''');
  PERFORM pg_temp.expect_0100_failure('55000', 'organization deletion audit is append-only',
    'DELETE FROM app_private.organization_deletion_audit_events '
    || 'WHERE request_id = ''00000000-0100-4000-8000-000000000002''');
END
$fixture$;
UPDATE app_private.organization_deletion_request_claims
SET actor_app_user_id = NULL
WHERE request_id = '00000000-0100-4000-8000-000000000002';
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0100_org);
BEGIN
  PERFORM pg_temp.expect_0100_failure('22023', 'organization deletion idempotency conflict',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid, %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000002',
      '00000000-0100-4000-8000-000000000002', org_id));
END
$fixture$;

-- A deadline reached immediately before the call probes the half-open fence.
-- Restore the physical values before the transaction ends; no production row changes.
CREATE TEMP TABLE fixture_0100_expired AS
SELECT * FROM app_private.create_organization_v1(
  '00000000-0100-0000-8000-000000000001'::uuid,
  '00000000-0100-1000-8000-000000000002'::uuid,
  '0100 expired synthetic organization');
UPDATE app_data.workspaces SET deleted_at = clock_timestamp() - interval '720 hours'
WHERE workspace_id = (SELECT organization_workspace_id FROM fixture_0100_expired);
INSERT INTO app_private.organization_deletion_current(
  organization_workspace_id, deletion_request_id, effective_at_utc,
  purge_after_utc, status, restored_at_utc)
SELECT workspace.workspace_id,
  '00000000-0100-4000-8000-000000000003',
  workspace.deleted_at, workspace.deleted_at + interval '720 hours',
  'deletion_pending', NULL
FROM app_data.workspaces AS workspace
WHERE workspace.workspace_id = (
  SELECT organization_workspace_id FROM fixture_0100_expired
);

DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0100_expired);
BEGIN
  PERFORM pg_temp.expect_0100_failure('22023', 'organization restoration idempotency conflict',
    format('SELECT * FROM app_private.restore_organization_v1(%L::uuid, gen_random_uuid(), %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000001', org_id,
      '00000000-0100-4000-8000-000000000003'));
  IF (SELECT status FROM app_private.organization_deletion_current
      WHERE organization_workspace_id = org_id) <> 'deletion_pending'
    OR (SELECT count(*) FROM app_private.organization_deletion_restore_claims
      WHERE organization_workspace_id = org_id) <> 0
    OR (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = org_id) <> 0
  THEN RAISE EXCEPTION '0100 expired failure wrote partial facts'; END IF;
END
$fixture$;

-- A backward database-clock step must also fail with the fixed conflict.
UPDATE app_data.workspaces SET deleted_at = clock_timestamp() + interval '1 hour'
WHERE workspace_id = (SELECT organization_workspace_id FROM fixture_0100_expired);
UPDATE app_private.organization_deletion_current AS attempt
SET effective_at_utc = workspace.deleted_at,
  purge_after_utc = workspace.deleted_at + interval '720 hours'
FROM app_data.workspaces AS workspace
WHERE attempt.organization_workspace_id = workspace.workspace_id
  AND workspace.workspace_id = (
    SELECT organization_workspace_id FROM fixture_0100_expired
  );
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0100_expired);
BEGIN
  PERFORM pg_temp.expect_0100_failure(
    '22023', 'organization restoration idempotency conflict',
    format('SELECT * FROM app_private.restore_organization_v1(%L::uuid, gen_random_uuid(), %L::uuid, %L::uuid)',
      '00000000-0100-0000-8000-000000000001', org_id,
      '00000000-0100-4000-8000-000000000003')
  );
  IF (SELECT count(*) FROM app_private.organization_deletion_restore_claims
      WHERE organization_workspace_id = org_id) <> 0
    OR (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = org_id) <> 0
  THEN RAISE EXCEPTION '0100 pre-effective failure wrote partial facts'; END IF;
END
$fixture$;

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_0100_failure('42501', 'permission denied for schema app_private',
  'SELECT * FROM app_private.organization_deletion_current');
SELECT pg_temp.expect_0100_failure('42501', 'permission denied for schema app_private',
  'SELECT * FROM app_private.organization_deletion_request_claims');
SELECT pg_temp.expect_0100_failure('42501', 'permission denied for schema app_private',
  'SELECT * FROM app_private.organization_deletion_restore_claims');
SELECT pg_temp.expect_0100_failure('42501', 'permission denied for schema app_private',
  'SELECT * FROM app_private.organization_deletion_audit_events');
RESET ROLE;

DO $fixture$
BEGIN
  IF has_function_privilege('tongxingzhe_runtime',
      'app_private.request_organization_deletion_v1(uuid,uuid,uuid)', 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime',
      'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)', 'EXECUTE')
    OR has_function_privilege('public',
      'app_private.request_organization_deletion_v1(uuid,uuid,uuid)', 'EXECUTE')
    OR has_function_privilege('public',
      'app_private.restore_organization_v1(uuid,uuid,uuid,uuid)', 'EXECUTE')
  THEN RAISE EXCEPTION '0100 private writers are executable by runtime or PUBLIC'; END IF;
END
$fixture$;

ROLLBACK;
