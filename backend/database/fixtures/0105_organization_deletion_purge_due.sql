-- Synthetic 0105 proof. All changes in this file roll back.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.expect_0105_failure(
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
    RAISE EXCEPTION '0105 expected % / %, got % / %',
      expected_state, expected_message, actual_state, actual_message;
  END IF;
END
$function$;

INSERT INTO app_data.app_users(app_user_id, status) VALUES
  ('00000000-0105-0000-8000-000000000001', 'active'),
  ('00000000-0105-0000-8000-000000000002', 'active'),
  ('00000000-0105-0000-8000-000000000003', 'active');
INSERT INTO app_data.external_identities(issuer, subject, app_user_id) VALUES
  ('https://synthetic-0105.example/auth/v1', 'owner',
    '00000000-0105-0000-8000-000000000001');
INSERT INTO app_data.workspaces(
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  '00000000-0105-1000-8000-000000000099', 'personal',
  '0105 synthetic personal workspace',
  '00000000-0105-0000-8000-000000000001'
);

CREATE TEMP TABLE fixture_0105_orgs AS
SELECT 'due'::text AS case_name, created.organization_workspace_id
FROM app_private.create_organization_v1(
  '00000000-0105-0000-8000-000000000001',
  '00000000-0105-1000-8000-000000000001', '0105 due organization') AS created
UNION ALL
SELECT 'early', created.organization_workspace_id
FROM app_private.create_organization_v1(
  '00000000-0105-0000-8000-000000000002',
  '00000000-0105-1000-8000-000000000002', '0105 early organization') AS created
UNION ALL
SELECT 'restored', created.organization_workspace_id
FROM app_private.create_organization_v1(
  '00000000-0105-0000-8000-000000000003',
  '00000000-0105-1000-8000-000000000003', '0105 restored organization') AS created
UNION ALL
SELECT 'orphan', created.organization_workspace_id
FROM app_private.create_organization_v1(
  '00000000-0105-0000-8000-000000000001',
  '00000000-0105-1000-8000-000000000004', '0105 orphan attempt organization') AS created;

CREATE TEMP TABLE fixture_0105_attempts AS
SELECT org.case_name, org.organization_workspace_id,
  CASE org.case_name
    WHEN 'due' THEN '00000000-0105-4000-8000-000000000001'::uuid
    WHEN 'early' THEN '00000000-0105-4000-8000-000000000002'::uuid
    WHEN 'restored' THEN '00000000-0105-4000-8000-000000000003'::uuid
    ELSE '00000000-0105-4000-8000-000000000004'::uuid
  END AS deletion_request_id
FROM fixture_0105_orgs AS org;

INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '00000000-0105-6000-8000-000000000001', organization_workspace_id,
  '0105 due organization project'
FROM fixture_0105_orgs WHERE case_name = 'due';

SELECT app_private.request_organization_deletion_v1(
  '00000000-0105-0000-8000-000000000003',
  '00000000-0105-4000-8000-000000000003', organization_workspace_id
) FROM fixture_0105_attempts WHERE case_name = 'restored';

-- The due deadline is transaction_timestamp; the marker later reads
-- clock_timestamp after acquiring locks, so this is an elapsed-deadline case.
UPDATE app_data.workspaces AS workspace
SET deleted_at = CASE fixture.case_name
  WHEN 'due' THEN transaction_timestamp() - interval '720 hours'
  ELSE transaction_timestamp()
END
FROM fixture_0105_attempts AS fixture
WHERE fixture.case_name IN ('due', 'early', 'orphan')
  AND workspace.workspace_id = fixture.organization_workspace_id;
INSERT INTO app_private.organization_deletion_current(
  organization_workspace_id, deletion_request_id, effective_at_utc,
  purge_after_utc, status, restored_at_utc
)
SELECT workspace.workspace_id, fixture.deletion_request_id,
  workspace.deleted_at, workspace.deleted_at + interval '720 hours',
  'deletion_pending', NULL
FROM app_data.workspaces AS workspace
JOIN fixture_0105_attempts AS fixture
  ON fixture.organization_workspace_id = workspace.workspace_id
WHERE fixture.case_name IN ('due', 'early', 'orphan');
INSERT INTO app_private.organization_deletion_request_claims(
  request_id, actor_app_user_id, organization_workspace_id,
  deletion_request_id, effective_at_utc, purge_after_utc
)
SELECT attempt.deletion_request_id,
  CASE fixture.case_name WHEN 'due'
    THEN '00000000-0105-0000-8000-000000000001'::uuid
    ELSE '00000000-0105-0000-8000-000000000002'::uuid END,
  attempt.organization_workspace_id, attempt.deletion_request_id,
  attempt.effective_at_utc, attempt.purge_after_utc
FROM app_private.organization_deletion_current AS attempt
JOIN fixture_0105_attempts AS fixture
  ON fixture.organization_workspace_id = attempt.organization_workspace_id
WHERE fixture.case_name IN ('due', 'early');

SELECT * FROM app_private.restore_organization_v1(
  '00000000-0105-0000-8000-000000000003',
  '00000000-0105-5000-8000-000000000003',
  (SELECT organization_workspace_id FROM fixture_0105_attempts
    WHERE case_name = 'restored'),
  '00000000-0105-4000-8000-000000000003'
);

CREATE TEMP TABLE fixture_0105_before AS
SELECT (SELECT count(*) FROM app_private.organization_deletion_request_claims) AS request_claims,
  (SELECT count(*) FROM app_private.organization_deletion_restore_claims) AS restore_claims,
  (SELECT count(*) FROM app_private.organization_deletion_audit_events) AS audits;

DO $fixture$
DECLARE
  due_workspace_id uuid;
  early_workspace_id uuid;
  restored_workspace_id uuid;
  orphan_workspace_id uuid;
  marker_result text;
BEGIN
  SELECT organization_workspace_id INTO STRICT due_workspace_id
  FROM fixture_0105_attempts WHERE case_name = 'due';
  SELECT organization_workspace_id INTO STRICT early_workspace_id
  FROM fixture_0105_attempts WHERE case_name = 'early';
  SELECT organization_workspace_id INTO STRICT restored_workspace_id
  FROM fixture_0105_attempts WHERE case_name = 'restored';
  SELECT organization_workspace_id INTO STRICT orphan_workspace_id
  FROM fixture_0105_attempts WHERE case_name = 'orphan';

  marker_result := app_private.mark_organization_deletion_purge_due_v1(due_workspace_id);
  IF marker_result IS DISTINCT FROM 'organization-deletion-purge-due:marked'
    OR (SELECT status FROM app_private.organization_deletion_current
        WHERE organization_workspace_id = due_workspace_id) <> 'purge_due'
    OR NOT EXISTS (
      SELECT 1 FROM app_data.projects
      WHERE project_id = '00000000-0105-6000-8000-000000000001'
        AND workspace_id = due_workspace_id
    )
  THEN RAISE EXCEPTION '0105 elapsed deadline was not marked without changing project data'; END IF;
  IF app_private.mark_organization_deletion_purge_due_v1(due_workspace_id)
      IS DISTINCT FROM 'organization-deletion-purge-due:already-marked'
  THEN RAISE EXCEPTION '0105 repeat due marker was not idempotent'; END IF;

  PERFORM pg_temp.expect_0105_failure('55000', 'organization purge due unavailable',
    format('SELECT app_private.mark_organization_deletion_purge_due_v1(%L::uuid)',
      early_workspace_id));
  UPDATE app_data.workspaces SET deleted_at = deleted_at + interval '1 second'
  WHERE workspace_id = early_workspace_id;
  PERFORM pg_temp.expect_0105_failure('55000', 'organization purge due unavailable',
    format('SELECT app_private.mark_organization_deletion_purge_due_v1(%L::uuid)',
      early_workspace_id));
  UPDATE app_data.workspaces AS workspace
  SET deleted_at = attempt.effective_at_utc
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id = early_workspace_id
    AND workspace.workspace_id = early_workspace_id;
  PERFORM pg_temp.expect_0105_failure('55000', 'organization purge due unavailable',
    format('SELECT app_private.mark_organization_deletion_purge_due_v1(%L::uuid)',
      restored_workspace_id));
  PERFORM pg_temp.expect_0105_failure('55000', 'organization purge due unavailable',
    format('SELECT app_private.mark_organization_deletion_purge_due_v1(%L::uuid)',
      orphan_workspace_id));
  PERFORM pg_temp.expect_0105_failure('42501', 'organization purge due forbidden',
    'SELECT app_private.mark_organization_deletion_purge_due_v1(''00000000-0105-9000-8000-000000000099''::uuid)');
  PERFORM pg_temp.expect_0105_failure('42501', 'organization purge due forbidden',
    'SELECT app_private.mark_organization_deletion_purge_due_v1(''00000000-0105-1000-8000-000000000099''::uuid)');
  PERFORM pg_temp.expect_0105_failure('22023', 'invalid organization purge due request',
    'SELECT app_private.mark_organization_deletion_purge_due_v1(NULL)');

  -- A due attempt remains closed to exact deletion replay and recovery listing.
  PERFORM pg_temp.expect_0105_failure('22023',
    'organization deletion idempotency conflict',
    format('SELECT * FROM app_private.request_organization_deletion_v1(%L::uuid,%L::uuid,%L::uuid)',
      '00000000-0105-0000-8000-000000000001',
      '00000000-0105-4000-8000-000000000001', due_workspace_id));
  IF EXISTS (
    SELECT 1 FROM app_data.list_organization_deletion_recovery_for_identity_v1(
      'https://synthetic-0105.example/auth/v1', 'owner'
    ) AS directory
    WHERE directory.organization_workspace_id = due_workspace_id
  ) THEN RAISE EXCEPTION '0105 due attempt remained in recovery directory'; END IF;

  IF (SELECT request_claims FROM fixture_0105_before) <>
      (SELECT count(*) FROM app_private.organization_deletion_request_claims)
    OR (SELECT restore_claims FROM fixture_0105_before) <>
      (SELECT count(*) FROM app_private.organization_deletion_restore_claims)
    OR (SELECT audits FROM fixture_0105_before) <>
      (SELECT count(*) FROM app_private.organization_deletion_audit_events)
  THEN RAISE EXCEPTION '0105 marker wrote a claim or audit fact'; END IF;
END
$fixture$;

ROLLBACK;
