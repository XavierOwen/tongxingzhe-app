-- synthetic rollback fixture：验证 Slice 7C 的组织创建、首个 owner 和权限边界。
-- 本文件只使用合成身份，并在最后回滚所有数据。
BEGIN;

SET LOCAL TIME ZONE 'UTC';

-- The fixture identity rows are installed by the migration/test owner.  The
-- runtime bridge below must resolve these exact, already-existing mappings.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0084-0000-0000-000000000001'::uuid, 'active'),
  ('00000000-0084-0000-0000-000000000002'::uuid, 'active'),
  ('00000000-0084-0000-0000-000000000003'::uuid, 'deletion_pending'),
  ('00000000-0084-0000-0000-000000000101'::uuid, 'active'),
  ('00000000-0084-0000-0000-000000000102'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
VALUES
  (
    '00000000-0084-1000-0000-000000000001'::uuid,
    'https://synthetic-0084.example/auth/v1',
    'owner-exact',
    '00000000-0084-0000-0000-000000000001'::uuid
  ),
  (
    '00000000-0084-1000-0000-000000000002'::uuid,
    'https://synthetic-0084.example/auth/v1',
    'other-exact',
    '00000000-0084-0000-0000-000000000002'::uuid
  ),
  (
    '00000000-0084-1000-0000-000000000003'::uuid,
    'https://synthetic-0084.example/auth/v1',
    'inactive-exact',
    '00000000-0084-0000-0000-000000000003'::uuid
  );

-- These tables are owned by the fixture session user so the runtime role can
-- insert bridge results while the assertions below run after RESET ROLE.
CREATE TEMP TABLE fixture_0084_first (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
);

CREATE TEMP TABLE fixture_0084_replay (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
);

GRANT ALL ON fixture_0084_first, fixture_0084_replay TO tongxingzhe_runtime;

-- U+0020 surrounds a name whose retained edges are NBSP and zero-width.
-- Canonicalization removes only the outer U+0020 characters.
SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0084_first
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-0084.example/auth/v1',
  'owner-exact',
  '00000000-0084-2000-0000-000000000001'::uuid,
  ' ' || chr(160) || 'Alpha' || chr(8239) || chr(8203) || ' '
);

-- The same request and canonical payload must return the original exact row.
INSERT INTO fixture_0084_replay
SELECT *
FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-0084.example/auth/v1',
  'owner-exact',
  '00000000-0084-2000-0000-000000000001'::uuid,
  ' ' || chr(160) || 'Alpha' || chr(8239) || chr(8203) || ' '
);

RESET ROLE;

DO $fixture$
DECLARE
  first_row fixture_0084_first%ROWTYPE;
  replay_row fixture_0084_replay%ROWTYPE;
  stored_name text;
  row_count bigint;
  expected_canonical_name text :=
    chr(160) || 'Alpha' || chr(8239) || chr(8203);
  audit_column text;
BEGIN
  SELECT * INTO STRICT first_row FROM fixture_0084_first;
  SELECT * INTO STRICT replay_row FROM fixture_0084_replay;

  IF first_row.creation_contract_id <> 'organization-creation:v1'
    OR first_row.organization_workspace_id IS NULL
    OR first_row.organization_membership_id IS NULL
    OR first_row.organization_owner_assignment_id IS NULL
    OR first_row.created_at_utc IS NULL
    OR NOT isfinite(first_row.created_at_utc)
  THEN
    RAISE EXCEPTION '0084 first creation returned an invalid result row';
  END IF;

  IF ROW(
    replay_row.creation_contract_id,
    replay_row.organization_workspace_id,
    replay_row.organization_membership_id,
    replay_row.organization_owner_assignment_id,
    replay_row.created_at_utc
  ) IS DISTINCT FROM ROW(
    first_row.creation_contract_id,
    first_row.organization_workspace_id,
    first_row.organization_membership_id,
    first_row.organization_owner_assignment_id,
    first_row.created_at_utc
  ) THEN
    RAISE EXCEPTION '0084 exact replay changed the creation result';
  END IF;

  SELECT workspace_row.display_name
  INTO STRICT stored_name
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_id = first_row.organization_workspace_id;

  IF stored_name IS DISTINCT FROM expected_canonical_name THEN
    RAISE EXCEPTION '0084 canonical display name drifted: %', stored_name;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    WHERE workspace_row.workspace_id = first_row.organization_workspace_id
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.personal_owner_app_user_id IS NULL
      AND workspace_row.deleted_at IS NULL
      AND workspace_row.created_at = first_row.created_at_utc
  ) THEN
    RAISE EXCEPTION '0084 organization workspace fact is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS membership_row
    WHERE membership_row.organization_membership_id =
        first_row.organization_membership_id
      AND membership_row.organization_workspace_id =
        first_row.organization_workspace_id
      AND membership_row.app_user_id =
        '00000000-0084-0000-0000-000000000001'::uuid
      AND membership_row.active_from_utc = first_row.created_at_utc
      AND membership_row.inactive_from_utc IS NULL
  ) THEN
    RAISE EXCEPTION '0084 creator membership fact is incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.organization_owner_assignments AS owner_row
    WHERE owner_row.organization_owner_assignment_id =
        first_row.organization_owner_assignment_id
      AND owner_row.organization_membership_id =
        first_row.organization_membership_id
      AND owner_row.active_from_utc = first_row.created_at_utc
      AND owner_row.inactive_from_utc IS NULL
  ) THEN
    RAISE EXCEPTION '0084 first owner assignment fact is incomplete';
  END IF;

  SELECT count(*) INTO row_count
  FROM app_private.organization_creation_request_claims AS claim_row
  WHERE claim_row.request_id =
      '00000000-0084-2000-0000-000000000001'::uuid;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '0084 request claim count is %, expected one', row_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_creation_request_claims AS claim_row
    WHERE claim_row.request_id =
        '00000000-0084-2000-0000-000000000001'::uuid
      AND claim_row.actor_app_user_id =
        '00000000-0084-0000-0000-000000000001'::uuid
      AND claim_row.canonical_display_name = expected_canonical_name
      AND claim_row.organization_workspace_id =
        first_row.organization_workspace_id
      AND claim_row.organization_membership_id =
        first_row.organization_membership_id
      AND claim_row.organization_owner_assignment_id =
        first_row.organization_owner_assignment_id
      AND claim_row.created_at_utc = first_row.created_at_utc
  ) THEN
    RAISE EXCEPTION '0084 request claim payload is incomplete';
  END IF;

  SELECT count(*) INTO row_count
  FROM app_private.organization_creation_audit_events AS audit_row
  WHERE audit_row.request_id =
      '00000000-0084-2000-0000-000000000001'::uuid;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '0084 audit count is %, expected one', row_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_creation_audit_events AS audit_row
    WHERE audit_row.request_id =
        '00000000-0084-2000-0000-000000000001'::uuid
      AND audit_row.creation_contract_id = 'organization-creation:v1'
      AND audit_row.organization_workspace_id =
        first_row.organization_workspace_id
      AND audit_row.organization_membership_id =
        first_row.organization_membership_id
      AND audit_row.organization_owner_assignment_id =
        first_row.organization_owner_assignment_id
      AND audit_row.created_at_utc = first_row.created_at_utc
  ) THEN
    RAISE EXCEPTION '0084 audit payload is incomplete';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'app_private'
      AND column_row.table_name = 'organization_creation_audit_events'
      AND column_row.column_name NOT IN (
        'organization_creation_audit_event_id',
        'creation_contract_id',
        'request_id',
        'organization_workspace_id',
        'organization_membership_id',
        'organization_owner_assignment_id',
        'created_at_utc'
      )
  ) THEN
    SELECT column_row.column_name
    INTO audit_column
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'app_private'
      AND column_row.table_name = 'organization_creation_audit_events'
      AND column_row.column_name NOT IN (
        'organization_creation_audit_event_id',
        'creation_contract_id',
        'request_id',
        'organization_workspace_id',
        'organization_membership_id',
        'organization_owner_assignment_id',
        'created_at_utc'
      )
    ORDER BY column_row.ordinal_position
    LIMIT 1;
    RAISE EXCEPTION '0084 audit has an uncontracted column: %', audit_column;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.projects AS project_row
    WHERE project_row.workspace_id = first_row.organization_workspace_id
  ) OR EXISTS (
    SELECT 1
    FROM app_data.project_memberships AS project_membership_row
    JOIN app_data.organization_memberships AS membership_row
      ON membership_row.organization_membership_id =
        project_membership_row.organization_membership_id
    WHERE membership_row.organization_membership_id =
        first_row.organization_membership_id
  ) OR EXISTS (
    SELECT 1
    FROM app_data.management_report_capability_grants AS capability_row
    JOIN app_data.project_memberships AS project_membership_row
      ON project_membership_row.project_membership_id =
        capability_row.project_membership_id
    JOIN app_data.organization_memberships AS membership_row
      ON membership_row.organization_membership_id =
        project_membership_row.organization_membership_id
    WHERE membership_row.organization_membership_id =
        first_row.organization_membership_id
  ) THEN
    RAISE EXCEPTION '0084 organization creation provisioned project data';
  END IF;

  SELECT count(*) INTO row_count
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_id = first_row.organization_workspace_id;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '0084 replay duplicated the workspace';
  END IF;

  SELECT count(*) INTO row_count
  FROM app_data.organization_memberships AS membership_row
  WHERE membership_row.organization_membership_id =
      first_row.organization_membership_id;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '0084 replay duplicated the membership';
  END IF;

  SELECT count(*) INTO row_count
  FROM app_data.organization_owner_assignments AS owner_row
  WHERE owner_row.organization_owner_assignment_id =
      first_row.organization_owner_assignment_id;
  IF row_count <> 1 THEN
    RAISE EXCEPTION '0084 replay duplicated the owner assignment';
  END IF;
END
$fixture$;

-- Keep expected-error assertions concise while retaining exact SQLSTATE and
-- stable messages for the creation contract.  The dynamic statement runs as
-- the invoker, which also lets the same helper assert runtime ACL failures.
CREATE OR REPLACE FUNCTION pg_temp.expect_0084_failure(
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
        '0084 % expected SQLSTATE/message %, % but got %, %',
        case_name,
        expected_sqlstate,
        expected_message,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0084 % unexpectedly succeeded', case_name;
END
$function$;

CREATE TEMP TABLE fixture_0084_failure_counts AS
SELECT
  (SELECT count(*) FROM app_data.workspaces) AS workspace_count,
  (SELECT count(*) FROM app_data.organization_memberships) AS membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owner_count,
  (SELECT count(*) FROM app_private.organization_creation_request_claims)
    AS claim_count,
  (SELECT count(*) FROM app_private.organization_creation_audit_events)
    AS audit_count;

-- Stable request/name validation, request idempotency drift, and identity
-- lookup failures must all leave the five creation fact sets unchanged.
SELECT pg_temp.expect_0084_failure(
  'actor drift',
  '22023',
  'organization creation idempotency conflict',
  format(
    'SELECT count(*) FROM app_private.create_organization_v1(%L::uuid, %L::uuid, %L)',
    '00000000-0084-0000-0000-000000000002',
    '00000000-0084-2000-0000-000000000001',
    'Alpha' || chr(160) || ' Org' || chr(8203)
  )
);

SELECT pg_temp.expect_0084_failure(
  'name drift',
  '22023',
  'organization creation idempotency conflict',
  format(
    'SELECT count(*) FROM app_private.create_organization_v1(%L::uuid, %L::uuid, %L)',
    '00000000-0084-0000-0000-000000000001',
    '00000000-0084-2000-0000-000000000001',
    'A different organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'NULL request id',
  '22023',
  'invalid organization creation request',
  format(
    'SELECT count(*) FROM app_private.create_organization_v1(%L::uuid, NULL::uuid, %L)',
    '00000000-0084-0000-0000-000000000001',
    'Valid organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'NULL display name',
  '22023',
  'invalid organization creation request',
  format(
    'SELECT count(*) FROM app_private.create_organization_v1(%L::uuid, %L::uuid, NULL::text)',
    '00000000-0084-0000-0000-000000000001',
    '00000000-0084-2000-0000-000000000002'
  )
);

SELECT pg_temp.expect_0084_failure(
  'U+0020-only display name',
  '22023',
  'invalid organization creation request',
  format(
    'SELECT count(*) FROM app_private.create_organization_v1(%L::uuid, %L::uuid, %L)',
    '00000000-0084-0000-0000-000000000001',
    '00000000-0084-2000-0000-000000000002',
    '   '
  )
);

SELECT pg_temp.expect_0084_failure(
  'Unicode White_Space-only display name',
  '22023',
  'invalid organization creation request',
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000003') || '::uuid, '
    || 'chr(160) || chr(8239)'
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'zero-width-only display name',
  '22023',
  'invalid organization creation request',
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000004') || '::uuid, '
    || 'chr(8203) || chr(8204) || chr(8205) || chr(8288) || chr(65279)'
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'Unicode White_Space plus zero-width display name',
  '22023',
  'invalid organization creation request',
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000012') || '::uuid, '
    || 'chr(160) || chr(8203)'
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'C0 control character in display name',
  '22023',
  'invalid organization creation request',
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000005') || '::uuid, '
    || 'chr(1) || ''Valid'''
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'C1 control character in display name',
  '22023',
  'invalid organization creation request',
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000006') || '::uuid, '
    || 'chr(128) || ''Valid'''
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'display name over 120 characters',
  '22023',
  'invalid organization creation request',
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000007') || '::uuid, '
    || 'repeat(''a'', 121)'
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'inactive trusted actor',
  '42501',
  'organization creation forbidden',
  format(
    'SELECT count(*) FROM app_private.create_organization_v1(%L::uuid, %L::uuid, %L)',
    '00000000-0084-0000-0000-000000000003',
    '00000000-0084-2000-0000-000000000017',
    'Inactive actor organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'NULL identity issuer',
  '22023',
  'invalid organization creation identity',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(NULL::text, %L, %L::uuid, %L)',
    'owner-exact',
    '00000000-0084-2000-0000-000000000013',
    'Invalid identity organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'blank identity subject',
  '22023',
  'invalid organization creation identity',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(%L, %L, %L::uuid, %L)',
    'https://synthetic-0084.example/auth/v1',
    '   ',
    '00000000-0084-2000-0000-000000000014',
    'Invalid identity organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'overlength identity issuer',
  '22023',
  'invalid organization creation identity',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(repeat(''i'', 2049), %L, %L::uuid, %L)',
    'owner-exact',
    '00000000-0084-2000-0000-000000000015',
    'Invalid identity organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'overlength identity subject',
  '22023',
  'invalid organization creation identity',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(%L, repeat(''s'', 513), %L::uuid, %L)',
    'https://synthetic-0084.example/auth/v1',
    '00000000-0084-2000-0000-000000000016',
    'Invalid identity organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'unknown exact identity',
  '42501',
  'organization creation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(%L, %L, %L::uuid, %L)',
    'https://synthetic-0084.example/auth/v1',
    'unknown-exact',
    '00000000-0084-2000-0000-000000000008',
    'Unknown identity organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'inactive exact identity',
  '42501',
  'organization creation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(%L, %L, %L::uuid, %L)',
    'https://synthetic-0084.example/auth/v1',
    'inactive-exact',
    '00000000-0084-2000-0000-000000000009',
    'Inactive identity organization'
  )
);

SELECT pg_temp.expect_0084_failure(
  'identity issuer whitespace drift',
  '42501',
  'organization creation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_for_identity_v1(%L, %L, %L::uuid, %L)',
    ' https://synthetic-0084.example/auth/v1',
    'owner-exact',
    '00000000-0084-2000-0000-000000000010',
    'Identity must remain exact'
  )
);

DO $fixture$
DECLARE
  before_counts fixture_0084_failure_counts%ROWTYPE;
  after_counts fixture_0084_failure_counts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0084_failure_counts;
  SELECT
    (SELECT count(*) FROM app_data.workspaces),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_private.organization_creation_request_claims),
    (SELECT count(*) FROM app_private.organization_creation_audit_events)
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts THEN
    RAISE EXCEPTION
      '0084 failed creation wrote partial facts: before %, after %',
      before_counts,
      after_counts;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.organization_creation_request_claims AS claim_row
    WHERE claim_row.request_id IN (
      '00000000-0084-2000-0000-000000000002'::uuid,
      '00000000-0084-2000-0000-000000000003'::uuid,
      '00000000-0084-2000-0000-000000000004'::uuid,
      '00000000-0084-2000-0000-000000000005'::uuid,
      '00000000-0084-2000-0000-000000000006'::uuid,
      '00000000-0084-2000-0000-000000000007'::uuid,
      '00000000-0084-2000-0000-000000000008'::uuid,
      '00000000-0084-2000-0000-000000000009'::uuid,
      '00000000-0084-2000-0000-000000000010'::uuid,
      '00000000-0084-2000-0000-000000000012'::uuid,
      '00000000-0084-2000-0000-000000000013'::uuid,
      '00000000-0084-2000-0000-000000000014'::uuid,
      '00000000-0084-2000-0000-000000000015'::uuid,
      '00000000-0084-2000-0000-000000000016'::uuid,
      '00000000-0084-2000-0000-000000000017'::uuid
    )
  ) THEN
    RAISE EXCEPTION '0084 failed request was unexpectedly claimed';
  END IF;
END
$fixture$;

-- Build synthetic organization memberships for temporal owner-assignment
-- boundary tests.  They intentionally have no projects or capability grants.
INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  created_at
)
VALUES
  (
    '00000000-0084-3000-0000-000000000001'::uuid,
    'organization',
    '0084 containment organization',
    NULL,
    '2020-01-01 00:00:00+00'::timestamptz
  ),
  (
    '00000000-0084-3000-0000-000000000002'::uuid,
    'organization',
    '0084 append-only organization',
    NULL,
    '2020-02-01 00:00:00+00'::timestamptz
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
    '00000000-0084-3100-0000-000000000001'::uuid,
    '00000000-0084-3000-0000-000000000001'::uuid,
    '00000000-0084-0000-0000-000000000101'::uuid,
    '2020-01-01 00:00:00+00'::timestamptz,
    '2020-01-10 00:00:00+00'::timestamptz
  ),
  (
    '00000000-0084-3100-0000-000000000002'::uuid,
    '00000000-0084-3000-0000-000000000002'::uuid,
    '00000000-0084-0000-0000-000000000102'::uuid,
    '2020-02-01 00:00:00+00'::timestamptz,
    NULL
  );

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '00000000-0084-3200-0000-000000000001'::uuid,
  '00000000-0084-3100-0000-000000000002'::uuid,
  transaction_timestamp(),
  NULL
);

SELECT pg_temp.expect_0084_failure(
  'owner assignment is not contained in finite membership',
  '22023',
  'organization owner assignment exceeds membership',
  'INSERT INTO app_data.organization_owner_assignments VALUES ('
    || quote_literal('00000000-0084-3200-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0084-3100-0000-000000000001') || '::uuid, '
    || 'transaction_timestamp(), NULL'
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'finite owner assignment is rejected at creation',
  '22023',
  'invalid organization owner assignment',
  'INSERT INTO app_data.organization_owner_assignments VALUES ('
    || quote_literal('00000000-0084-3200-0000-000000000003') || '::uuid, '
    || quote_literal('00000000-0084-3100-0000-000000000001') || '::uuid, '
    || 'transaction_timestamp(), '
    || 'transaction_timestamp() + interval ''1 second'''
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'overlapping owner assignment',
  '23P01',
  'organization owner assignment periods overlap',
  'INSERT INTO app_data.organization_owner_assignments VALUES ('
    || quote_literal('00000000-0084-3200-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0084-3100-0000-000000000002') || '::uuid, '
    || 'transaction_timestamp(), NULL'
    || ')'
);

-- A legal close needs a later transaction timestamp, so it is covered by the
-- committed-row concurrency script.  This rollback fixture proves that an
-- open assignment cannot be rewritten or deleted in place.
SELECT pg_temp.expect_0084_failure(
  'open owner assignment update',
  '55000',
  'organization owner assignment history is append-only',
  'UPDATE app_data.organization_owner_assignments '
    || 'SET active_from_utc = transaction_timestamp() + interval ''1 second'' '
    || 'WHERE organization_owner_assignment_id = '
    || quote_literal('00000000-0084-3200-0000-000000000001') || '::uuid'
);

SELECT pg_temp.expect_0084_failure(
  'owner assignment delete',
  '55000',
  'organization owner assignment history cannot be deleted',
  'DELETE FROM app_data.organization_owner_assignments WHERE '
    || 'organization_owner_assignment_id = '
    || quote_literal('00000000-0084-3200-0000-000000000001') || '::uuid'
);

-- Verify that runtime can use only the exact identity bridge.  It cannot call
-- the private writer or read any of the three new storage tables.
SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0084_failure(
  'runtime private writer ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.create_organization_v1('
    || quote_literal('00000000-0084-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0084-2000-0000-000000000011') || '::uuid, '
    || quote_literal('runtime private writer')
    || ')'
);

SELECT pg_temp.expect_0084_failure(
  'runtime owner assignment table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.organization_owner_assignments'
);

SELECT pg_temp.expect_0084_failure(
  'runtime request claim table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_creation_request_claims'
);

SELECT pg_temp.expect_0084_failure(
  'runtime audit table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_creation_audit_events'
);

RESET ROLE;

DO $fixture$
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.create_organization_for_identity_v1(text,text,uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '0084 runtime bridge EXECUTE privilege is missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.create_organization_v1(uuid,uuid,text)',
    'EXECUTE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.organization_owner_assignments',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_private.organization_creation_request_claims',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_private.organization_creation_audit_events',
    'SELECT'
  ) THEN
    RAISE EXCEPTION '0084 runtime received a private function/table privilege';
  END IF;
END
$fixture$;

ROLLBACK;
