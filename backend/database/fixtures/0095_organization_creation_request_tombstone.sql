-- Synthetic terminal facts only: no live claim or organization is purged.
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.expect_0095_failure(
  expected_state text, expected_message text, statement text
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  actual_state text;
  actual_message text;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state
    OR (expected_message IS NOT NULL
      AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0095 expected % / %, got % / %',
      expected_state, expected_message, actual_state, actual_message;
  END IF;
END
$function$;

INSERT INTO app_data.app_users (app_user_id, status) VALUES
  ('00000000-0095-4000-8000-000000000001', 'active'),
  ('00000000-0095-4000-8000-000000000002', 'active');
INSERT INTO app_data.external_identities
  (external_identity_id, issuer, subject, app_user_id) VALUES
  ('00000000-0095-4100-8000-000000000001',
   'https://synthetic-0095.example/auth/v1', 'creator-exact',
   '00000000-0095-4000-8000-000000000001'),
  ('00000000-0095-4100-8000-000000000002',
   'https://synthetic-0095.example/auth/v1', 'other-exact',
   '00000000-0095-4000-8000-000000000002');

CREATE TEMP TABLE fixture_0095_first AS
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-0095.example/auth/v1', 'creator-exact',
  '00000000-0095-5000-8000-000000000001', '  0095 retained organization  '
);
CREATE TEMP TABLE fixture_0095_replay AS
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-0095.example/auth/v1', 'creator-exact',
  '00000000-0095-5000-8000-000000000001', '0095 retained organization'
);

DO $fixture$
BEGIN
  IF (SELECT count(*) FROM fixture_0095_first) <> 1
    OR EXISTS ((TABLE fixture_0095_first EXCEPT TABLE fixture_0095_replay)
      UNION ALL (TABLE fixture_0095_replay EXCEPT TABLE fixture_0095_first))
    OR NOT EXISTS (
      SELECT 1 FROM fixture_0095_first AS receipt
      JOIN app_data.workspaces AS workspace
        ON workspace.workspace_id = receipt.organization_workspace_id
      JOIN app_data.organization_memberships AS membership
        ON membership.organization_membership_id = receipt.organization_membership_id
      JOIN app_data.organization_owner_assignments AS owner_assignment
        ON owner_assignment.organization_owner_assignment_id =
          receipt.organization_owner_assignment_id
      WHERE receipt.creation_contract_id = 'organization-creation:v1'
        AND workspace.display_name = '0095 retained organization'
        AND membership.organization_workspace_id = workspace.workspace_id
        AND membership.app_user_id = '00000000-0095-4000-8000-000000000001'
        AND owner_assignment.organization_membership_id =
          membership.organization_membership_id
        AND workspace.created_at = receipt.created_at_utc
        AND membership.active_from_utc = receipt.created_at_utc
        AND owner_assignment.active_from_utc = receipt.created_at_utc
        AND membership.inactive_from_utc IS NULL
        AND owner_assignment.inactive_from_utc IS NULL
        AND isfinite(receipt.created_at_utc)
    ) THEN
    RAISE EXCEPTION '0095 first create / exact replay / atomic owner changed';
  END IF;
END
$fixture$;

-- A transfer tombstone with the same UUID must not block creation.
INSERT INTO app_private.organization_owner_transfer_request_tombstones VALUES
  ('organization-owner-transfer:v1', '00000000-0095-5000-8000-000000000003');
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-0095.example/auth/v1', 'creator-exact',
  '00000000-0095-5000-8000-000000000003', '0095 separate family'
);

-- One tombstone has no live creation claim; the other deliberately coexists
-- with a live claim to prove terminal facts take precedence over exact replay.
INSERT INTO app_private.organization_creation_request_tombstones VALUES
  ('organization-creation:v1', '00000000-0095-5000-8000-000000000001'),
  ('organization-creation:v1', '00000000-0095-5000-8000-000000000002');

CREATE TEMP TABLE fixture_0095_before AS SELECT
  (SELECT count(*) FROM app_data.workspaces) AS workspace_count,
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owner_count,
  (SELECT count(*) FROM app_private.organization_creation_request_claims) AS claim_count,
  (SELECT count(*) FROM app_private.organization_creation_audit_events) AS audit_count,
  (SELECT count(*) FROM app_private.organization_creation_request_tombstones) AS tombstone_count;

DO $fixture$
DECLARE
  request_id uuid;
  subject text;
BEGIN
  FOREACH request_id IN ARRAY ARRAY[
    '00000000-0095-5000-8000-000000000001'::uuid,
    '00000000-0095-5000-8000-000000000002'::uuid
  ] LOOP
    FOREACH subject IN ARRAY ARRAY['creator-exact', 'other-exact'] LOOP
      PERFORM pg_temp.expect_0095_failure('22023',
        'organization creation idempotency conflict', format(
          'SELECT * FROM app_data.create_organization_for_identity_v1(%L, %L, %L::uuid, %L)',
          'https://synthetic-0095.example/auth/v1', subject, request_id,
          '0095 retained organization'
        ));
    END LOOP;
  END LOOP;
  -- Private writer must reach the fence before trying to lock/resolve actor.
  PERFORM pg_temp.expect_0095_failure('22023',
    'organization creation idempotency conflict',
    'SELECT * FROM app_private.create_organization_v1(NULL::uuid, '
    || '''00000000-0095-5000-8000-000000000002''::uuid, ''0095 retired'')');

  PERFORM pg_temp.expect_0095_failure('23514', NULL,
    'INSERT INTO app_private.organization_creation_request_tombstones VALUES '
    || '(''organization-owner-transfer:v1'', gen_random_uuid())');
  PERFORM pg_temp.expect_0095_failure('23502', NULL,
    'INSERT INTO app_private.organization_creation_request_tombstones VALUES '
    || '(NULL, gen_random_uuid())');
  PERFORM pg_temp.expect_0095_failure('23502', NULL,
    'INSERT INTO app_private.organization_creation_request_tombstones VALUES '
    || '(''organization-creation:v1'', NULL)');
  PERFORM pg_temp.expect_0095_failure('23505', NULL,
    'INSERT INTO app_private.organization_creation_request_tombstones VALUES '
    || '(''organization-creation:v1'', ''00000000-0095-5000-8000-000000000002'')');
  PERFORM pg_temp.expect_0095_failure('55000',
    'organization creation request tombstone is immutable',
    'UPDATE app_private.organization_creation_request_tombstones '
    || 'SET request_id = request_id');
  PERFORM pg_temp.expect_0095_failure('55000',
    'organization creation request tombstone is immutable',
    'DELETE FROM app_private.organization_creation_request_tombstones');
END
$fixture$;

SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_0095_failure('42501', NULL,
  'SELECT * FROM app_private.organization_creation_request_tombstones');
SELECT pg_temp.expect_0095_failure('42501', NULL,
  'INSERT INTO app_private.organization_creation_request_tombstones VALUES '
  || '(''organization-creation:v1'', gen_random_uuid())');
SELECT pg_temp.expect_0095_failure('22023',
  'organization creation idempotency conflict',
  'SELECT * FROM app_data.create_organization_for_identity_v1('
  || '''https://synthetic-0095.example/auth/v1'', ''creator-exact'', '
  || '''00000000-0095-5000-8000-000000000001'', ''0095 retained organization'')');
RESET ROLE;

DO $fixture$
DECLARE
  after_counts fixture_0095_before%ROWTYPE;
BEGIN
  SELECT
    (SELECT count(*) FROM app_data.workspaces),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_private.organization_creation_request_claims),
    (SELECT count(*) FROM app_private.organization_creation_audit_events),
    (SELECT count(*) FROM app_private.organization_creation_request_tombstones)
  INTO after_counts;
  IF after_counts IS DISTINCT FROM (SELECT row FROM fixture_0095_before AS row)
    OR EXISTS (SELECT 1 FROM app_private.organization_creation_request_claims
      WHERE request_id = '00000000-0095-5000-8000-000000000002')
    OR (SELECT count(*) FROM app_private.organization_creation_audit_events
      WHERE request_id = '00000000-0095-5000-8000-000000000001') <> 1
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_creation_request_claims
      WHERE request_id = '00000000-0095-5000-8000-000000000003') THEN
    RAISE EXCEPTION '0095 terminal conflicts wrote facts or family isolation failed';
  END IF;
END
$fixture$;

ROLLBACK;
