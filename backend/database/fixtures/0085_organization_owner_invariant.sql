-- Synthetic rollback fixture for the 0085 organization owner invariant.
-- Every row is valid synthetic data and the whole fixture is rolled back.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

-- The existing owner-assignment INSERT contract only permits the current
-- transaction timestamp.  Seed older, otherwise valid history while
-- replication triggers are disabled so this rollback fixture can exercise a
-- later legal close in the same outer transaction.  Production triggers are
-- restored before any behavior is tested.
DO $seed$
BEGIN
  PERFORM set_config('session_replication_role', 'replica', true);

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  )
  SELECT seed.owner_assignment_id,
         seed.membership_id,
         transaction_timestamp() - interval '1 hour',
         NULL
  FROM (
    VALUES
      (
        '00000000-0085-1200-0000-000000000001'::uuid,
        '00000000-0085-1100-0000-000000000001'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000002'::uuid,
        '00000000-0085-1100-0000-000000000002'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000003'::uuid,
        '00000000-0085-1100-0000-000000000003'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000004'::uuid,
        '00000000-0085-1100-0000-000000000004'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000005'::uuid,
        '00000000-0085-1100-0000-000000000005'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000006'::uuid,
        '00000000-0085-1100-0000-000000000006'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000007'::uuid,
        '00000000-0085-1100-0000-000000000007'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000008'::uuid,
        '00000000-0085-1100-0000-000000000008'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000009'::uuid,
        '00000000-0085-1100-0000-000000000009'::uuid
      ),
      (
        '00000000-0085-1200-0000-000000000010'::uuid,
        '00000000-0085-1100-0000-000000000010'::uuid
      )
  ) AS seed(owner_assignment_id, membership_id);

  PERFORM set_config('session_replication_role', 'origin', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('session_replication_role', 'origin', true);
  RAISE;
END
$seed$;

INSERT INTO app_data.app_users (app_user_id, status)
SELECT user_id, 'active'
FROM (
  SELECT format(
    '00000000-0085-0000-0000-%s',
    lpad(number::text, 12, '0')
  )::uuid AS user_id
  FROM generate_series(1, 10) AS numbers(number)
) AS users;

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at,
  created_at
)
SELECT format(
         '00000000-0085-1000-0000-%s',
         lpad(number::text, 12, '0')
       )::uuid,
       'organization',
       format('0085 invariant organization %s', number),
       NULL,
       NULL,
       transaction_timestamp() - interval '1 hour'
FROM generate_series(1, 9) AS numbers(number);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT format(
         '00000000-0085-1100-0000-%s',
         lpad(number::text, 12, '0')
       )::uuid,
       format(
         '00000000-0085-1000-0000-%s',
         lpad(number::text, 12, '0')
       )::uuid,
       format(
         '00000000-0085-0000-0000-%s',
         lpad(number::text, 12, '0')
       )::uuid,
       transaction_timestamp() - interval '1 hour',
       NULL
FROM generate_series(1, 9) AS numbers(number);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '00000000-0085-1100-0000-000000000010'::uuid,
  '00000000-0085-1000-0000-000000000009'::uuid,
  '00000000-0085-0000-0000-000000000010'::uuid,
  transaction_timestamp() - interval '1 hour',
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
    '00000000-0085-1100-0000-000000000011'::uuid,
    '00000000-0085-1000-0000-000000000002'::uuid,
    '00000000-0085-0000-0000-000000000010'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0085-1100-0000-000000000012'::uuid,
    '00000000-0085-1000-0000-000000000003'::uuid,
    '00000000-0085-0000-0000-000000000010'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  );

CREATE OR REPLACE FUNCTION pg_temp.expect_0085_failure(
  case_name text,
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

    IF actual_sqlstate IS DISTINCT FROM '23514'
      OR actual_message IS DISTINCT FROM
        'organization must retain an active owner'
    THEN
      RAISE EXCEPTION
        '0085 % expected SQLSTATE/message 23514, organization must retain an active owner but got %, %',
        case_name,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0085 % unexpectedly succeeded', case_name;
END
$function$;

-- A physical organization with one current active owner is healthy.
DO $healthy$
DECLARE
  owner_count bigint;
BEGIN
  SELECT count(*)
  INTO owner_count
  FROM app_data.workspaces AS workspace_row
  JOIN app_data.organization_memberships AS membership_row
    ON membership_row.organization_workspace_id = workspace_row.workspace_id
  JOIN app_data.organization_owner_assignments AS owner_row
    ON owner_row.organization_membership_id =
      membership_row.organization_membership_id
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = membership_row.app_user_id
  WHERE workspace_row.workspace_id =
      '00000000-0085-1000-0000-000000000001'::uuid
    AND workspace_row.workspace_kind = 'organization'
    AND tstzrange(
      membership_row.active_from_utc,
      membership_row.inactive_from_utc,
      '[)'
    ) @> transaction_timestamp()
    AND tstzrange(
      owner_row.active_from_utc,
      owner_row.inactive_from_utc,
      '[)'
    ) @> transaction_timestamp()
    AND user_row.status = 'active';

  IF owner_count <> 1 THEN
    RAISE EXCEPTION '0085 healthy organization has % current owners',
      owner_count;
  END IF;
END
$healthy$;

-- A transaction may pass through zero owners when it restores one before
-- the deferred check runs.
UPDATE app_data.organization_owner_assignments
SET inactive_from_utc = transaction_timestamp()
WHERE organization_owner_assignment_id =
  '00000000-0085-1200-0000-000000000002'::uuid;

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '00000000-0085-1200-0000-000000000012'::uuid,
  '00000000-0085-1100-0000-000000000011'::uuid,
  transaction_timestamp(),
  NULL
);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Granting a second owner before closing the original owner is valid.
INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '00000000-0085-1200-0000-000000000013'::uuid,
  '00000000-0085-1100-0000-000000000012'::uuid,
  transaction_timestamp(),
  NULL
);

UPDATE app_data.organization_owner_assignments
SET inactive_from_utc = transaction_timestamp()
WHERE organization_owner_assignment_id =
  '00000000-0085-1200-0000-000000000003'::uuid;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.expect_0085_failure(
  'unique owner assignment close',
  'UPDATE app_data.organization_owner_assignments '
    || 'SET inactive_from_utc = transaction_timestamp() '
    || 'WHERE organization_owner_assignment_id = '
    || quote_literal('00000000-0085-1200-0000-000000000004') || '::uuid'
);

SELECT pg_temp.expect_0085_failure(
  'unique owner membership close',
  'UPDATE app_data.organization_memberships '
    || 'SET inactive_from_utc = transaction_timestamp() '
    || 'WHERE organization_membership_id = '
    || quote_literal('00000000-0085-1100-0000-000000000005') || '::uuid'
);

SELECT pg_temp.expect_0085_failure(
  'unique owner deletion_pending status',
  'UPDATE app_data.app_users SET status = ' || quote_literal('deletion_pending')
    || ' WHERE app_user_id = '
    || quote_literal('00000000-0085-0000-0000-000000000006') || '::uuid'
);

SELECT pg_temp.expect_0085_failure(
  'unique owner deleted status',
  'UPDATE app_data.app_users SET status = ' || quote_literal('deleted')
    || ' WHERE app_user_id = '
    || quote_literal('00000000-0085-0000-0000-000000000007') || '::uuid'
);

SELECT pg_temp.expect_0085_failure(
  'soft-deleted physical organization ownerless',
  'DO $operation$ BEGIN '
    || 'UPDATE app_data.organization_owner_assignments '
    || 'SET inactive_from_utc = transaction_timestamp() '
    || 'WHERE organization_owner_assignment_id = '
    || quote_literal('00000000-0085-1200-0000-000000000008') || '::uuid; '
    || 'UPDATE app_data.workspaces '
    || 'SET deleted_at = transaction_timestamp() '
    || 'WHERE workspace_id = '
    || quote_literal('00000000-0085-1000-0000-000000000008') || '::uuid; '
    || 'END $operation$'
);

-- Removing one of two current owners remains valid.
UPDATE app_data.organization_owner_assignments
SET inactive_from_utc = transaction_timestamp()
WHERE organization_owner_assignment_id =
  '00000000-0085-1200-0000-000000000009'::uuid;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $assert_failures_rolled_back$
DECLARE
  closed_assignment timestamptz;
  closed_membership timestamptz;
  pending_status text;
  deleted_status text;
  soft_deleted_at timestamptz;
  current_owner_count bigint;
BEGIN
  SELECT inactive_from_utc INTO closed_assignment
  FROM app_data.organization_owner_assignments
  WHERE organization_owner_assignment_id =
    '00000000-0085-1200-0000-000000000004'::uuid;
  IF closed_assignment IS NOT NULL THEN
    RAISE EXCEPTION '0085 failed owner assignment close left residue';
  END IF;

  SELECT inactive_from_utc INTO closed_membership
  FROM app_data.organization_memberships
  WHERE organization_membership_id =
    '00000000-0085-1100-0000-000000000005'::uuid;
  IF closed_membership IS NOT NULL THEN
    RAISE EXCEPTION '0085 failed membership close left residue';
  END IF;

  SELECT status INTO pending_status
  FROM app_data.app_users
  WHERE app_user_id = '00000000-0085-0000-0000-000000000006'::uuid;
  SELECT status INTO deleted_status
  FROM app_data.app_users
  WHERE app_user_id = '00000000-0085-0000-0000-000000000007'::uuid;
  IF pending_status <> 'active' OR deleted_status <> 'active' THEN
    RAISE EXCEPTION '0085 failed status changes left residue';
  END IF;

  SELECT deleted_at INTO soft_deleted_at
  FROM app_data.workspaces
  WHERE workspace_id = '00000000-0085-1000-0000-000000000008'::uuid;
  IF soft_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION '0085 failed soft delete left residue';
  END IF;

  SELECT count(*) INTO current_owner_count
  FROM app_data.organization_owner_assignments AS owner_row
  JOIN app_data.organization_memberships AS membership_row
    ON membership_row.organization_membership_id =
      owner_row.organization_membership_id
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = membership_row.app_user_id
  WHERE membership_row.organization_workspace_id =
      '00000000-0085-1000-0000-000000000009'::uuid
    AND tstzrange(
      membership_row.active_from_utc,
      membership_row.inactive_from_utc,
      '[)'
    ) @> transaction_timestamp()
    AND tstzrange(
      owner_row.active_from_utc,
      owner_row.inactive_from_utc,
      '[)'
    ) @> transaction_timestamp()
    AND user_row.status = 'active';
  IF current_owner_count <> 1 THEN
    RAISE EXCEPTION '0085 multi-owner withdrawal left % current owners',
      current_owner_count;
  END IF;
END
$assert_failures_rolled_back$;

-- Personal bootstrap and personal workspace rows are not organization rows and
-- must remain outside the organization owner invariant.
CREATE TEMP TABLE fixture_0085_personal_result (
  app_user_id uuid,
  workspace_id uuid,
  workspace_kind text,
  workspace_name text,
  project_id uuid,
  project_name text,
  questionnaire_version_id uuid,
  questionnaire_version_number integer,
  capabilities text[]
) ON COMMIT DROP;
GRANT ALL ON fixture_0085_personal_result TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0085_personal_result
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-0085.example/auth/v1',
  'personal-bootstrap'
);
RESET ROLE;

DO $personal$
DECLARE
  personal_row fixture_0085_personal_result%ROWTYPE;
BEGIN
  SELECT * INTO STRICT personal_row FROM fixture_0085_personal_result;
  IF personal_row.workspace_kind <> 'personal'
    OR personal_row.app_user_id IS NULL
    OR personal_row.workspace_id IS NULL
    OR personal_row.project_id IS NULL
    OR personal_row.questionnaire_version_id IS NULL
  THEN
    RAISE EXCEPTION '0085 personal bootstrap was affected by organization guard';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    WHERE workspace_row.workspace_id = personal_row.workspace_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.personal_owner_app_user_id = personal_row.app_user_id
      AND workspace_row.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION '0085 personal workspace fact is incomplete';
  END IF;
END
$personal$;

ROLLBACK;
