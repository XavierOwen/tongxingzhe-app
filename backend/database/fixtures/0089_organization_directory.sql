-- 0089 组织目录合成回滚 fixture：只使用合成身份与业务数据。

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0089-0000-0000-000000000001'::uuid, 'active'),
  ('00000000-0089-0000-0000-000000000002'::uuid, 'active'),
  ('00000000-0089-0000-0000-000000000003'::uuid, 'active'),
  ('00000000-0089-0000-0000-000000000004'::uuid, 'active'),
  ('00000000-0089-0000-0000-000000000005'::uuid, 'active'),
  ('00000000-0089-0000-0000-000000000006'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
VALUES
  (
    '00000000-0089-1000-0000-000000000001'::uuid,
    'https://synthetic-0089.example/auth/v1',
    'directory-member',
    '00000000-0089-0000-0000-000000000001'::uuid
  ),
  (
    '00000000-0089-1000-0000-000000000002'::uuid,
    'https://synthetic-0089.example/auth/v1',
    ' directory-member ',
    '00000000-0089-0000-0000-000000000002'::uuid
  ),
  (
    '00000000-0089-1000-0000-000000000003'::uuid,
    'https://synthetic-0089.example/auth/v1',
    'empty-directory-member',
    '00000000-0089-0000-0000-000000000003'::uuid
  ),
  (
    '00000000-0089-1000-0000-000000000004'::uuid,
    'https://synthetic-0089.example/auth/v1',
    'other-member',
    '00000000-0089-0000-0000-000000000004'::uuid
  ),
  (
    '00000000-0089-1000-0000-000000000005'::uuid,
    'https://synthetic-0089.example/auth/v1',
    'inactive-member',
    '00000000-0089-0000-0000-000000000005'::uuid
  ),
  (
    '00000000-0089-1000-0000-000000000006'::uuid,
    'https://synthetic-0089.example/auth/v1',
    'deleted-member',
    '00000000-0089-0000-0000-000000000006'::uuid
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
    '00000000-0089-2000-0000-000000000001'::uuid,
    'organization',
    ' 0089 Original 名称  ',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000002'::uuid,
    'organization',
    '0089 Alpha projectless',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000003'::uuid,
    'organization',
    '0089 Same',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000004'::uuid,
    'organization',
    '0089 Same',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000005'::uuid,
    'organization',
    '0089 Boundary start',
    NULL,
    NULL,
    transaction_timestamp()
  ),
  (
    '00000000-0089-2000-0000-000000000006'::uuid,
    'organization',
    '0089 Future',
    NULL,
    NULL,
    transaction_timestamp()
  ),
  (
    '00000000-0089-2000-0000-000000000007'::uuid,
    'organization',
    '0089 Ended',
    NULL,
    NULL,
    transaction_timestamp() - interval '2 days'
  ),
  (
    '00000000-0089-2000-0000-000000000008'::uuid,
    'organization',
    '0089 Boundary end',
    NULL,
    NULL,
    transaction_timestamp() - interval '2 days'
  ),
  (
    '00000000-0089-2000-0000-000000000009'::uuid,
    'organization',
    '0089 Deleted',
    NULL,
    NULL,
    transaction_timestamp() - interval '2 days'
  ),
  (
    '00000000-0089-2000-0000-000000000010'::uuid,
    'organization',
    '0089 Recovery',
    NULL,
    NULL,
    transaction_timestamp() - interval '2 days'
  ),
  (
    '00000000-0089-2000-0000-000000000011'::uuid,
    'organization',
    '0089 Other user',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000012'::uuid,
    'organization',
    '0089 Whitespace identity',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000013'::uuid,
    'organization',
    '0089 Inactive account',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-2000-0000-000000000014'::uuid,
    'organization',
    '0089 Deleted account',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 day'
  );

-- 2002 没有项目；2003 有项目但 actor 没有项目成员或 capability。
INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default,
  created_at
)
VALUES (
  '00000000-0089-2500-0000-000000000001'::uuid,
  '00000000-0089-2000-0000-000000000003'::uuid,
  '0089 Unassigned project',
  'active',
  false,
  transaction_timestamp()
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
    '00000000-0089-3000-0000-000000000001'::uuid,
    '00000000-0089-2000-0000-000000000001'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000002'::uuid,
    '00000000-0089-2000-0000-000000000002'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000003'::uuid,
    '00000000-0089-2000-0000-000000000003'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    transaction_timestamp() + interval '1 day'
  ),
  (
    '00000000-0089-3000-0000-000000000004'::uuid,
    '00000000-0089-2000-0000-000000000004'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000005'::uuid,
    '00000000-0089-2000-0000-000000000005'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000006'::uuid,
    '00000000-0089-2000-0000-000000000006'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() + interval '1 hour',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000007'::uuid,
    '00000000-0089-2000-0000-000000000007'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '2 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    '00000000-0089-3000-0000-000000000008'::uuid,
    '00000000-0089-2000-0000-000000000008'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    transaction_timestamp()
  ),
  (
    '00000000-0089-3000-0000-000000000009'::uuid,
    '00000000-0089-2000-0000-000000000009'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000010'::uuid,
    '00000000-0089-2000-0000-000000000010'::uuid,
    '00000000-0089-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000011'::uuid,
    '00000000-0089-2000-0000-000000000011'::uuid,
    '00000000-0089-0000-0000-000000000004'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000012'::uuid,
    '00000000-0089-2000-0000-000000000012'::uuid,
    '00000000-0089-0000-0000-000000000002'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000013'::uuid,
    '00000000-0089-2000-0000-000000000013'::uuid,
    '00000000-0089-0000-0000-000000000005'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    '00000000-0089-3000-0000-000000000014'::uuid,
    '00000000-0089-2000-0000-000000000014'::uuid,
    '00000000-0089-0000-0000-000000000006'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  );

-- 成员行必须在 workspace 未删除时合法建立，随后的恢复期／删除状态不得出现在目录。
UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp() - interval '1 hour'
WHERE workspace_id = '00000000-0089-2000-0000-000000000009'::uuid;

UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp() + interval '30 days'
WHERE workspace_id = '00000000-0089-2000-0000-000000000010'::uuid;

-- 先建立合法成员历史，再改变账号状态，验证 reader 每次重新检查 active user。
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0089-0000-0000-000000000005'::uuid;

UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '00000000-0089-0000-0000-000000000006'::uuid;

CREATE TEMP TABLE fixture_0089_counts_before ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_user_count,
  (SELECT count(*) FROM app_data.external_identities) AS identity_count,
  (SELECT count(*) FROM app_data.workspaces) AS workspace_count,
  (SELECT count(*) FROM app_data.projects) AS project_count,
  (SELECT count(*) FROM app_data.organization_memberships)
    AS organization_membership_count,
  (SELECT count(*) FROM app_data.organization_owner_assignments)
    AS owner_assignment_count,
  (SELECT count(*) FROM app_data.project_memberships)
    AS project_membership_count,
  (SELECT count(*) FROM app_data.management_report_capability_grants)
    AS capability_count;

CREATE TEMP TABLE fixture_0089_main_directory (
  result_ordinal bigint,
  organization_workspace_id uuid,
  organization_name text
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0089_whitespace_directory (
  organization_workspace_id uuid,
  organization_name text
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0089_empty_directory (
  organization_workspace_id uuid,
  organization_name text
) ON COMMIT DROP;

GRANT ALL ON
  fixture_0089_main_directory,
  fixture_0089_whitespace_directory,
  fixture_0089_empty_directory
TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0089_main_directory
SELECT row_number() OVER (), result.*
FROM app_data.list_organizations_for_identity_v1(
  'https://synthetic-0089.example/auth/v1',
  'directory-member'
) AS result;

INSERT INTO fixture_0089_whitespace_directory
SELECT *
FROM app_data.list_organizations_for_identity_v1(
  'https://synthetic-0089.example/auth/v1',
  ' directory-member '
);

INSERT INTO fixture_0089_empty_directory
SELECT *
FROM app_data.list_organizations_for_identity_v1(
  'https://synthetic-0089.example/auth/v1',
  'empty-directory-member'
);

RESET ROLE;

DO $results$
DECLARE
  actual_ids uuid[];
  actual_names text[];
BEGIN
  SELECT
    array_agg(result_row.organization_workspace_id ORDER BY result_ordinal),
    array_agg(result_row.organization_name ORDER BY result_ordinal)
  INTO actual_ids, actual_names
  FROM fixture_0089_main_directory AS result_row;

  IF actual_ids IS DISTINCT FROM ARRAY[
      '00000000-0089-2000-0000-000000000001'::uuid,
      '00000000-0089-2000-0000-000000000002'::uuid,
      '00000000-0089-2000-0000-000000000005'::uuid,
      '00000000-0089-2000-0000-000000000003'::uuid,
      '00000000-0089-2000-0000-000000000004'::uuid
    ]::uuid[]
    OR actual_names IS DISTINCT FROM ARRAY[
      ' 0089 Original 名称  ',
      '0089 Alpha projectless',
      '0089 Boundary start',
      '0089 Same',
      '0089 Same'
    ]::text[]
  THEN
    RAISE EXCEPTION
      '0089 current organization directory order/content drifted: %, %',
      actual_ids,
      actual_names;
  END IF;

  IF (
    SELECT count(*) FROM fixture_0089_empty_directory
  ) <> 0 THEN
    RAISE EXCEPTION '0089 active user empty directory was not empty';
  END IF;

  IF (
    SELECT count(*)
    FROM fixture_0089_whitespace_directory
    WHERE organization_workspace_id =
        '00000000-0089-2000-0000-000000000012'::uuid
      AND organization_name = '0089 Whitespace identity'
  ) <> 1 OR (
    SELECT count(*) FROM fixture_0089_whitespace_directory
  ) <> 1 THEN
    RAISE EXCEPTION '0089 exact whitespace identity lookup drifted';
  END IF;
END
$results$;

CREATE OR REPLACE FUNCTION pg_temp.expect_0089_failure(
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
        '0089 % expected SQLSTATE/message %, % but got %, %',
        case_name,
        expected_sqlstate,
        expected_message,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0089 % unexpectedly succeeded', case_name;
END
$function$;

SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0089_failure(
  'null issuer',
  '22023',
  'invalid organization directory identity',
  'SELECT * FROM app_data.list_organizations_for_identity_v1(NULL, '
    || quote_literal('directory-member') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'space issuer',
  '22023',
  'invalid organization directory identity',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('   ') || ', '
    || quote_literal('directory-member') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'null subject',
  '22023',
  'invalid organization directory identity',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1')
    || ', NULL)'
);

SELECT pg_temp.expect_0089_failure(
  'space subject',
  '22023',
  'invalid organization directory identity',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1') || ', '
    || quote_literal(' ') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'oversized issuer',
  '22023',
  'invalid organization directory identity',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal(repeat('i', 2049)) || ', '
    || quote_literal('directory-member') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'oversized subject',
  '22023',
  'invalid organization directory identity',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1') || ', '
    || quote_literal(repeat('s', 513)) || ')'
);

SELECT pg_temp.expect_0089_failure(
  'unknown identity',
  '42501',
  'organization directory forbidden',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1') || ', '
    || quote_literal('unknown-member') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'inactive identity',
  '42501',
  'organization directory forbidden',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1') || ', '
    || quote_literal('inactive-member') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'deleted identity',
  '42501',
  'organization directory forbidden',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1') || ', '
    || quote_literal('deleted-member') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'unmapped trimmed subject',
  '42501',
  'organization directory forbidden',
  'SELECT * FROM app_data.list_organizations_for_identity_v1('
    || quote_literal('https://synthetic-0089.example/auth/v1') || ', '
    || quote_literal('directory-member  ') || ')'
);

SELECT pg_temp.expect_0089_failure(
  'runtime external identity SELECT',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.external_identities'
);

SELECT pg_temp.expect_0089_failure(
  'runtime app user SELECT',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.app_users'
);

SELECT pg_temp.expect_0089_failure(
  'runtime workspace SELECT',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.workspaces'
);

SELECT pg_temp.expect_0089_failure(
  'runtime membership SELECT',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.organization_memberships'
);

RESET ROLE;

DO $read_only$
DECLARE
  before_counts fixture_0089_counts_before%ROWTYPE;
  after_counts fixture_0089_counts_before%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0089_counts_before;

  SELECT
    (SELECT count(*) FROM app_data.app_users),
    (SELECT count(*) FROM app_data.external_identities),
    (SELECT count(*) FROM app_data.workspaces),
    (SELECT count(*) FROM app_data.projects),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*) FROM app_data.project_memberships),
    (SELECT count(*) FROM app_data.management_report_capability_grants)
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts THEN
    RAISE EXCEPTION
      '0089 organization directory wrote business facts: before %, after %',
      before_counts,
      after_counts;
  END IF;
END
$read_only$;

ROLLBACK;
