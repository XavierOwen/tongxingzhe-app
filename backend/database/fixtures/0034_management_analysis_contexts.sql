\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6d100000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6d100000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6d100000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    '6de00000-0000-4000-8000-000000000001'::uuid,
    'https://management-context.synthetic/auth/v1',
    'viewer',
    '6d100000-0000-4000-8000-000000000001'::uuid
  ),
  (
    '6de00000-0000-4000-8000-000000000002'::uuid,
    'https://management-context.synthetic/auth/v1',
    'release-only',
    '6d100000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6de00000-0000-4000-8000-000000000003'::uuid,
    'https://management-context.synthetic/auth/v1',
    'other-viewer',
    '6d100000-0000-4000-8000-000000000003'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id
) VALUES
  (
    '6d200000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Visible organization',
    NULL
  ),
  (
    '6d200000-0000-4000-8000-000000000002'::uuid,
    'organization',
    'Expired organization membership',
    NULL
  ),
  (
    '6d200000-0000-4000-8000-000000000003'::uuid,
    'organization',
    'Deleted organization',
    NULL
  ),
  (
    '6d200000-0000-4000-8000-000000000004'::uuid,
    'organization',
    'Other user organization',
    NULL
  );

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
) VALUES
  ('6d300000-0000-4000-8000-000000000001', '6d200000-0000-4000-8000-000000000001', 'Visible project one', 'active', false),
  ('6d300000-0000-4000-8000-000000000002', '6d200000-0000-4000-8000-000000000001', 'Visible project two', 'active', false),
  ('6d300000-0000-4000-8000-000000000003', '6d200000-0000-4000-8000-000000000001', 'Release-only project', 'active', false),
  ('6d300000-0000-4000-8000-000000000004', '6d200000-0000-4000-8000-000000000001', 'Expired grant project', 'active', false),
  ('6d300000-0000-4000-8000-000000000005', '6d200000-0000-4000-8000-000000000001', 'Expired project membership', 'active', false),
  ('6d300000-0000-4000-8000-000000000006', '6d200000-0000-4000-8000-000000000002', 'Expired organization project', 'active', false),
  ('6d300000-0000-4000-8000-000000000007', '6d200000-0000-4000-8000-000000000001', 'Archived project', 'active', false),
  ('6d300000-0000-4000-8000-000000000008', '6d200000-0000-4000-8000-000000000003', 'Deleted organization project', 'active', false),
  ('6d300000-0000-4000-8000-000000000009', '6d200000-0000-4000-8000-000000000004', 'Other user project', 'active', false);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  ('6d400000-0000-4000-8000-000000000001', '6d200000-0000-4000-8000-000000000001', '6d100000-0000-4000-8000-000000000001', transaction_timestamp() - interval '60 days', NULL),
  ('6d400000-0000-4000-8000-000000000002', '6d200000-0000-4000-8000-000000000001', '6d100000-0000-4000-8000-000000000002', transaction_timestamp() - interval '60 days', NULL),
  ('6d400000-0000-4000-8000-000000000003', '6d200000-0000-4000-8000-000000000002', '6d100000-0000-4000-8000-000000000001', transaction_timestamp() - interval '60 days', transaction_timestamp() - interval '30 days'),
  ('6d400000-0000-4000-8000-000000000004', '6d200000-0000-4000-8000-000000000003', '6d100000-0000-4000-8000-000000000001', transaction_timestamp() - interval '60 days', NULL),
  ('6d400000-0000-4000-8000-000000000005', '6d200000-0000-4000-8000-000000000004', '6d100000-0000-4000-8000-000000000003', transaction_timestamp() - interval '60 days', NULL);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  ('6d500000-0000-4000-8000-000000000001', '6d400000-0000-4000-8000-000000000001', '6d300000-0000-4000-8000-000000000001', transaction_timestamp() - interval '60 days', NULL),
  ('6d500000-0000-4000-8000-000000000002', '6d400000-0000-4000-8000-000000000001', '6d300000-0000-4000-8000-000000000002', transaction_timestamp() - interval '60 days', NULL),
  ('6d500000-0000-4000-8000-000000000003', '6d400000-0000-4000-8000-000000000001', '6d300000-0000-4000-8000-000000000004', transaction_timestamp() - interval '60 days', NULL),
  ('6d500000-0000-4000-8000-000000000004', '6d400000-0000-4000-8000-000000000001', '6d300000-0000-4000-8000-000000000005', transaction_timestamp() - interval '20 days', transaction_timestamp() - interval '10 days'),
  ('6d500000-0000-4000-8000-000000000005', '6d400000-0000-4000-8000-000000000003', '6d300000-0000-4000-8000-000000000006', transaction_timestamp() - interval '55 days', transaction_timestamp() - interval '35 days'),
  ('6d500000-0000-4000-8000-000000000006', '6d400000-0000-4000-8000-000000000001', '6d300000-0000-4000-8000-000000000007', transaction_timestamp() - interval '60 days', NULL),
  ('6d500000-0000-4000-8000-000000000007', '6d400000-0000-4000-8000-000000000004', '6d300000-0000-4000-8000-000000000008', transaction_timestamp() - interval '60 days', NULL),
  ('6d500000-0000-4000-8000-000000000008', '6d400000-0000-4000-8000-000000000002', '6d300000-0000-4000-8000-000000000003', transaction_timestamp() - interval '60 days', NULL),
  ('6d500000-0000-4000-8000-000000000009', '6d400000-0000-4000-8000-000000000005', '6d300000-0000-4000-8000-000000000009', transaction_timestamp() - interval '60 days', NULL);

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  ('6d600000-0000-4000-8000-000000000001', '6d500000-0000-4000-8000-000000000001', 'view_anonymous_analytics', transaction_timestamp() - interval '60 days', NULL),
  ('6d600000-0000-4000-8000-000000000002', '6d500000-0000-4000-8000-000000000002', 'view_anonymous_analytics', transaction_timestamp() - interval '60 days', NULL),
  ('6d600000-0000-4000-8000-000000000003', '6d500000-0000-4000-8000-000000000003', 'view_anonymous_analytics', transaction_timestamp() - interval '20 days', transaction_timestamp() - interval '10 days'),
  ('6d600000-0000-4000-8000-000000000004', '6d500000-0000-4000-8000-000000000004', 'view_anonymous_analytics', transaction_timestamp() - interval '18 days', transaction_timestamp() - interval '12 days'),
  ('6d600000-0000-4000-8000-000000000005', '6d500000-0000-4000-8000-000000000005', 'view_anonymous_analytics', transaction_timestamp() - interval '50 days', transaction_timestamp() - interval '40 days'),
  ('6d600000-0000-4000-8000-000000000006', '6d500000-0000-4000-8000-000000000006', 'view_anonymous_analytics', transaction_timestamp() - interval '60 days', NULL),
  ('6d600000-0000-4000-8000-000000000007', '6d500000-0000-4000-8000-000000000007', 'view_anonymous_analytics', transaction_timestamp() - interval '60 days', NULL),
  ('6d600000-0000-4000-8000-000000000008', '6d500000-0000-4000-8000-000000000008', 'release_management_reports', transaction_timestamp() - interval '60 days', NULL),
  ('6d600000-0000-4000-8000-000000000009', '6d500000-0000-4000-8000-000000000009', 'view_anonymous_analytics', transaction_timestamp() - interval '60 days', NULL);

UPDATE app_data.projects
SET status = 'archived'
WHERE project_id = '6d300000-0000-4000-8000-000000000007'::uuid;

UPDATE app_data.workspaces
SET deleted_at = clock_timestamp()
WHERE workspace_id = '6d200000-0000-4000-8000-000000000003'::uuid;

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture$
DECLARE
  context_count integer;
  current_count integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE is_current)
  INTO context_count, current_count
  FROM app_data.list_management_analysis_contexts_v1(
    'https://management-context.synthetic/auth/v1',
    'viewer'
  );
  IF context_count <> 2 OR current_count <> 0 THEN
    RAISE EXCEPTION 'management context discovery exposed an invalid project';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.list_management_analysis_contexts_v1(
      'https://management-context.synthetic/auth/v1',
      'release-only'
    )
  ) THEN
    RAISE EXCEPTION 'release-only identity received a view context';
  END IF;

  PERFORM app_data.select_management_analysis_context_v1(
    'https://management-context.synthetic/auth/v1',
    'viewer',
    '6d300000-0000-4000-8000-000000000001'::uuid
  );

  SELECT count(*) INTO current_count
  FROM app_data.list_management_analysis_contexts_v1(
    'https://management-context.synthetic/auth/v1',
    'viewer'
  )
  WHERE is_current
    AND project_id = '6d300000-0000-4000-8000-000000000001'::uuid;
  IF current_count <> 1 THEN
    RAISE EXCEPTION 'management context selection was not restored';
  END IF;

  BEGIN
    PERFORM app_data.select_management_analysis_context_v1(
      'https://management-context.synthetic/auth/v1',
      'viewer',
      '6d300000-0000-4000-8000-000000000003'::uuid
    );
    RAISE EXCEPTION 'release-only project was selectable';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.select_management_analysis_context_v1(
      'https://management-context.synthetic/auth/v1',
      'viewer',
      '6d300000-0000-4000-8000-000000000009'::uuid
    );
    RAISE EXCEPTION 'another user project was selectable';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture$;

RESET ROLE;

DO $unknown_identity$
DECLARE
  before_users bigint;
  before_workspaces bigint;
  before_projects bigint;
BEGIN
  SELECT count(*) INTO before_users FROM app_data.app_users;
  SELECT count(*) INTO before_workspaces FROM app_data.workspaces;
  SELECT count(*) INTO before_projects FROM app_data.projects;
  BEGIN
    PERFORM app_data.list_management_analysis_contexts_v1(
      'https://management-context.synthetic/auth/v1',
      'unknown'
    );
    RAISE EXCEPTION 'unknown identity received a management context';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  IF before_users <> (SELECT count(*) FROM app_data.app_users)
    OR before_workspaces <> (SELECT count(*) FROM app_data.workspaces)
    OR before_projects <> (SELECT count(*) FROM app_data.projects)
  THEN
    RAISE EXCEPTION 'management context discovery bootstrapped identity data';
  END IF;
END
$unknown_identity$;

UPDATE app_data.management_report_capability_grants
SET inactive_from_utc = clock_timestamp()
WHERE capability_grant_id =
  '6d600000-0000-4000-8000-000000000001'::uuid;

SET LOCAL ROLE tongxingzhe_runtime;

DO $revoked_selection$
DECLARE
  context_count integer;
  current_count integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE is_current)
  INTO context_count, current_count
  FROM app_data.list_management_analysis_contexts_v1(
    'https://management-context.synthetic/auth/v1',
    'viewer'
  );
  IF context_count <> 1 OR current_count <> 0 THEN
    RAISE EXCEPTION 'revoked management selection remained current';
  END IF;
END
$revoked_selection$;

RESET ROLE;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc
) SELECT
  '6d600000-0000-4000-8000-000000000010'::uuid,
  '6d500000-0000-4000-8000-000000000001'::uuid,
  'view_anonymous_analytics',
  previous_grant.inactive_from_utc
FROM app_data.management_report_capability_grants AS previous_grant
WHERE previous_grant.capability_grant_id =
  '6d600000-0000-4000-8000-000000000001'::uuid;

SET LOCAL ROLE tongxingzhe_runtime;

DO $rejoined_grant$
DECLARE
  context_count integer;
  current_count integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE is_current)
  INTO context_count, current_count
  FROM app_data.list_management_analysis_contexts_v1(
    'https://management-context.synthetic/auth/v1',
    'viewer'
  );
  IF context_count <> 2 OR current_count <> 0 THEN
    RAISE EXCEPTION 'new grant silently revived old management selection';
  END IF;

  PERFORM app_data.select_management_analysis_context_v1(
    'https://management-context.synthetic/auth/v1',
    'viewer',
    '6d300000-0000-4000-8000-000000000001'::uuid
  );
END
$rejoined_grant$;

RESET ROLE;

DO $evidence$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.management_analysis_current_contexts AS current_context
    WHERE current_context.app_user_id =
        '6d100000-0000-4000-8000-000000000001'::uuid
      AND current_context.organization_membership_id =
        '6d400000-0000-4000-8000-000000000001'::uuid
      AND current_context.project_membership_id =
        '6d500000-0000-4000-8000-000000000001'::uuid
      AND current_context.capability_grant_id =
        '6d600000-0000-4000-8000-000000000010'::uuid
  ) THEN
    RAISE EXCEPTION 'management selection did not persist exact new evidence';
  END IF;
END
$evidence$;

ROLLBACK;
