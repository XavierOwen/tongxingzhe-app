-- Synthetic rollback fixture for Slice 6BO.
--
-- This fixture exercises only the organization/project opt-in lifecycle.  It
-- deliberately creates no contacts, contact-target links, reports, cells or
-- ratio candidates.  Every identifier belongs to the 6b0f namespace so the
-- committed rows from the concurrency check cannot collide with this
-- transaction and every assertion remains project-scoped.

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b0f1000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b0f1000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b0f1000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b0f1000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id
)
VALUES
  (
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    'organization',
    '6BO opt-in organization one',
    NULL
  ),
  (
    '6b0f2000-0000-4000-8000-000000000002'::uuid,
    'organization',
    '6BO opt-in organization two',
    NULL
  ),
  (
    '6b0f2000-0000-4000-8000-000000000003'::uuid,
    'personal',
    '6BO opt-in personal workspace',
    '6b0f1000-0000-4000-8000-000000000001'::uuid
  );

-- The archived project is made active while its membership is established;
-- the status transition itself is part of the project-lock contract.
INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
)
VALUES
  (
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6BO opt-in active project',
    'active',
    false
  ),
  (
    '6b0f3000-0000-4000-8000-000000000002'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6BO opt-in isolated project',
    'active',
    false
  ),
  (
    '6b0f3000-0000-4000-8000-000000000003'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6BO opt-in archived project',
    'active',
    false
  ),
  (
    '6b0f3000-0000-4000-8000-000000000004'::uuid,
    '6b0f2000-0000-4000-8000-000000000002'::uuid,
    '6BO opt-in cross-organization project',
    'active',
    false
  ),
  (
    '6b0f3000-0000-4000-8000-000000000005'::uuid,
    '6b0f2000-0000-4000-8000-000000000003'::uuid,
    '6BO opt-in personal project',
    'active',
    true
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
    '6b0f4000-0000-4000-8000-000000000001'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f4000-0000-4000-8000-000000000002'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6b0f1000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f4000-0000-4000-8000-000000000003'::uuid,
    '6b0f2000-0000-4000-8000-000000000002'::uuid,
    '6b0f1000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f4000-0000-4000-8000-000000000004'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6b0f1000-0000-4000-8000-000000000004'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6b0f5000-0000-4000-8000-000000000001'::uuid,
    '6b0f4000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f5000-0000-4000-8000-000000000002'::uuid,
    '6b0f4000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f5000-0000-4000-8000-000000000003'::uuid,
    '6b0f4000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f5000-0000-4000-8000-000000000004'::uuid,
    '6b0f4000-0000-4000-8000-000000000002'::uuid,
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f5000-0000-4000-8000-000000000005'::uuid,
    '6b0f4000-0000-4000-8000-000000000003'::uuid,
    '6b0f3000-0000-4000-8000-000000000004'::uuid,
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    '6b0f5000-0000-4000-8000-000000000006'::uuid,
    '6b0f4000-0000-4000-8000-000000000004'::uuid,
    '6b0f3000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '30 days',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6b0f6000-0000-4000-8000-000000000001'::uuid,
    '6b0f5000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f6000-0000-4000-8000-000000000002'::uuid,
    '6b0f5000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f6000-0000-4000-8000-000000000003'::uuid,
    '6b0f5000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f6000-0000-4000-8000-000000000004'::uuid,
    '6b0f5000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b0f6000-0000-4000-8000-000000000005'::uuid,
    '6b0f5000-0000-4000-8000-000000000005'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '30 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    '6b0f6000-0000-4000-8000-000000000006'::uuid,
    '6b0f5000-0000-4000-8000-000000000006'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '30 days',
    NULL
  );

-- Archive only after the valid membership and capability chain exists.  The
-- status trigger must take the exact 6BO project lock, which is also exercised
-- in the separate committed concurrency script.
UPDATE app_data.projects
SET status = 'archived'
WHERE project_id = '6b0f3000-0000-4000-8000-000000000003'::uuid;

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6b0f1000-0000-4000-8000-000000000004'::uuid;

-- Business calls run through the dedicated closed owner role.  This proves
-- that its forced-RLS policy and narrow column/function grants are usable;
-- the final history audit resets to the deployment session.
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;

CREATE TEMP TABLE fixture_6bo_initial_state ON COMMIT DROP AS
SELECT app_private.read_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1'
) AS state;

DO $assert_initial_state$
DECLARE
  state_document jsonb := (SELECT state FROM fixture_6bo_initial_state);
BEGIN
  IF state_document->>'state_contract_id' <>
      'management_follow_up_consent_opt_in_state_v1'
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(state_document) AS state_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration', 'metric_id', 'project_id', 'state_contract_id', 'status'
    ]
    OR state_document->>'metric_id' <> 'follow_up_consent_ratio@1'
    OR state_document->>'project_id' <>
      '6b0f3000-0000-4000-8000-000000000001'
    OR state_document->>'status' <> 'not_enabled'
    OR state_document->'configuration' IS DISTINCT FROM 'null'::jsonb
    OR state_document ? 'numerator'
    OR state_document ? 'denominator'
    OR state_document ? 'coverage'
    OR state_document ? 'cells'
    OR state_document ? 'protected_report'
    OR state_document ?| ARRAY[
      'requested_by_app_user_id', 'actor_app_user_id',
      'organization_workspace_id', 'organization_membership_id',
      'project_membership_id', 'capability_grant_id', 'capability_id',
      'request_id', 'authorization_reference_at_utc', 'contact', 'source',
      'place_name', 'latitude', 'longitude'
    ]
  THEN
    RAISE EXCEPTION '6BO initial state is not a clean not_enabled metadata state';
  END IF;
END
$assert_initial_state$;

CREATE TEMP TABLE fixture_6bo_enabled_config ON COMMIT DROP AS
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b0f7000-0000-4000-8000-000000000001'::uuid,
  0,
  true
) AS configuration;

CREATE TEMP TABLE fixture_6bo_enabled_replay ON COMMIT DROP AS
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b0f7000-0000-4000-8000-000000000001'::uuid,
  0,
  true
) AS configuration;

DO $assert_enabled_config$
DECLARE
  configuration_document jsonb := (
    SELECT fixture_row.configuration
    FROM fixture_6bo_enabled_config AS fixture_row
  );
  replay_document jsonb := (
    SELECT fixture_row.configuration
    FROM fixture_6bo_enabled_replay AS fixture_row
  );
BEGIN
  IF configuration_document->>'configuration_contract_id' <>
      'management_follow_up_consent_opt_in_configuration_v1'
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(configuration_document) AS config_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration_contract_id', 'enabled', 'expected_version', 'metric_id',
      'project_id', 'recorded_at_utc', 'status', 'version_number'
    ]
    OR configuration_document->>'metric_id' <> 'follow_up_consent_ratio@1'
    OR configuration_document->>'project_id' <>
      '6b0f3000-0000-4000-8000-000000000001'
    OR configuration_document->>'version_number' <> '1'
    OR configuration_document->>'expected_version' <> '0'
    OR configuration_document->>'enabled' <> 'true'
    OR configuration_document->>'recorded_at_utc' IS NULL
    OR replay_document IS DISTINCT FROM configuration_document
    OR configuration_document ? 'numerator'
    OR configuration_document ? 'denominator'
    OR configuration_document ? 'coverage'
    OR configuration_document ? 'cells'
    OR configuration_document ? 'protected_report'
    OR configuration_document ? 'contact'
    OR configuration_document ? 'place_name'
    OR configuration_document ?| ARRAY[
      'requested_by_app_user_id', 'actor_app_user_id',
      'organization_workspace_id', 'organization_membership_id',
      'project_membership_id', 'capability_grant_id', 'capability_id',
      'request_id', 'authorization_reference_at_utc', 'contact', 'source',
      'place_name', 'latitude', 'longitude'
    ]
  THEN
    RAISE EXCEPTION '6BO enable or exact idempotent replay drifted';
  END IF;
END
$assert_enabled_config$;

DO $assert_payload_drift$
BEGIN
  PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    'follow_up_consent_ratio@1',
    '6b0f7000-0000-4000-8000-000000000001'::uuid,
    0,
    false
  );
  RAISE EXCEPTION '6BO idempotency payload drift was accepted';
EXCEPTION
  WHEN SQLSTATE '22023' THEN
    NULL;
END
$assert_payload_drift$;

DO $assert_cross_project_request_replay$
BEGIN
  PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000002'::uuid,
    'follow_up_consent_ratio@1',
    '6b0f7000-0000-4000-8000-000000000001'::uuid,
    0,
    true
  );
  RAISE EXCEPTION '6BO request UUID replayed across projects';
EXCEPTION
  WHEN SQLSTATE '22023' THEN
    NULL;
END
$assert_cross_project_request_replay$;

DO $assert_stale_version$
BEGIN
  PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    'follow_up_consent_ratio@1',
    '6b0f7000-0000-4000-8000-000000000002'::uuid,
    0,
    false
  );
  RAISE EXCEPTION '6BO stale expected version was accepted';
EXCEPTION
  WHEN SQLSTATE '40001' THEN
    NULL;
END
$assert_stale_version$;

DO $assert_invalid_expected_version$
DECLARE
  overflow_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000001'::uuid,
      '6b0f3000-0000-4000-8000-000000000001'::uuid,
      'follow_up_consent_ratio@1',
      '6b0f7000-0000-4000-8000-000000000010'::uuid,
      2147483647,
      true
    );
    RAISE EXCEPTION '6BO maximum integer expected_version was accepted';
  EXCEPTION
    WHEN SQLSTATE '22023' OR SQLSTATE '40001' THEN
      NULL;
  END;

  BEGIN
    EXECUTE $$
      SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
        '6b0f1000-0000-4000-8000-000000000001'::uuid,
        '6b0f3000-0000-4000-8000-000000000001'::uuid,
        'follow_up_consent_ratio@1',
        '6b0f7000-0000-4000-8000-000000000011'::uuid,
        2147483648,
        true
      )
    $$;
  EXCEPTION
    WHEN OTHERS THEN
      overflow_rejected := true;
  END;

  IF NOT overflow_rejected THEN
    RAISE EXCEPTION '6BO integer overflow expected_version was accepted';
  END IF;
END
$assert_invalid_expected_version$;

SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b0f7000-0000-4000-8000-000000000002'::uuid,
  1,
  false
);

CREATE TEMP TABLE fixture_6bo_disabled_state ON COMMIT DROP AS
SELECT app_private.read_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1'
) AS state;

DO $assert_disabled_state$
DECLARE
  state_document jsonb := (SELECT state FROM fixture_6bo_disabled_state);
BEGIN
  IF state_document->>'status' <> 'not_enabled'
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(state_document) AS state_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration', 'metric_id', 'project_id', 'state_contract_id', 'status'
    ]
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(state_document->'configuration') AS config_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration_contract_id', 'enabled', 'expected_version', 'metric_id',
      'project_id', 'recorded_at_utc', 'status', 'version_number'
    ]
    OR state_document->'configuration'->>'version_number' <> '2'
    OR state_document->'configuration'->>'enabled' <> 'false'
    OR state_document ? 'numerator'
    OR state_document ? 'denominator'
    OR state_document ? 'coverage'
    OR COALESCE((state_document->'configuration') ?| ARRAY[
      'requested_by_app_user_id', 'actor_app_user_id',
      'organization_workspace_id', 'organization_membership_id',
      'project_membership_id', 'capability_grant_id', 'capability_id',
      'request_id', 'authorization_reference_at_utc', 'numerator',
      'denominator', 'coverage', 'cells', 'protected_report', 'contact',
      'source', 'place_name', 'latitude', 'longitude'
    ], false)
  THEN
    RAISE EXCEPTION '6BO disabled state did not preserve metadata-only history';
  END IF;
END
$assert_disabled_state$;

SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b0f7000-0000-4000-8000-000000000003'::uuid,
  2,
  true
);

CREATE TEMP TABLE fixture_6bo_enabled_state ON COMMIT DROP AS
SELECT app_private.read_management_follow_up_consent_opt_in_v1(
  '6b0f1000-0000-4000-8000-000000000001'::uuid,
  '6b0f3000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1'
) AS state;

DO $assert_reenabled_state$
DECLARE
  state_document jsonb := (SELECT state FROM fixture_6bo_enabled_state);
BEGIN
  IF state_document->>'status' <> 'enabled'
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(state_document) AS state_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration', 'metric_id', 'project_id', 'state_contract_id', 'status'
    ]
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(state_document->'configuration') AS config_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration_contract_id', 'enabled', 'expected_version', 'metric_id',
      'project_id', 'recorded_at_utc', 'status', 'version_number'
    ]
    OR state_document->'configuration'->>'version_number' <> '3'
    OR state_document->'configuration'->>'enabled' <> 'true'
    OR state_document ? 'numerator'
    OR state_document ? 'denominator'
    OR state_document ? 'coverage'
    OR state_document ? 'cells'
    OR state_document ? 'protected_report'
    OR COALESCE((state_document->'configuration') ?| ARRAY[
      'requested_by_app_user_id', 'actor_app_user_id',
      'organization_workspace_id', 'organization_membership_id',
      'project_membership_id', 'capability_grant_id', 'capability_id',
      'request_id', 'authorization_reference_at_utc', 'numerator',
      'denominator', 'coverage', 'cells', 'protected_report', 'contact',
      'source', 'place_name', 'latitude', 'longitude'
    ], false)
  THEN
    RAISE EXCEPTION '6BO re-enabled state is not metadata-only';
  END IF;
END
$assert_reenabled_state$;

DO $assert_project_isolation$
DECLARE
  state_document jsonb;
BEGIN
  state_document := app_private.read_management_follow_up_consent_opt_in_v1(
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000002'::uuid,
    'follow_up_consent_ratio@1'
  );
  IF state_document->>'status' <> 'not_enabled'
    OR ARRAY(
      SELECT key
      FROM jsonb_object_keys(state_document) AS state_keys(key)
      ORDER BY key
    ) IS DISTINCT FROM ARRAY[
      'configuration', 'metric_id', 'project_id', 'state_contract_id', 'status'
    ]
    OR state_document->'configuration' IS DISTINCT FROM 'null'::jsonb
  THEN
    RAISE EXCEPTION '6BO configuration leaked between organization projects';
  END IF;
END
$assert_project_isolation$;

DO $assert_invalid_metric$
BEGIN
  PERFORM app_private.read_management_follow_up_consent_opt_in_v1(
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    'follow_up_consent_ratio@2'
  );
  RAISE EXCEPTION '6BO accepted an unknown metric on read';
EXCEPTION
  WHEN SQLSTATE '22023' THEN
    NULL;
END
$assert_invalid_metric$;

DO $assert_forbidden_scopes$
BEGIN
  -- A view grant is intentionally insufficient for configuration.
  BEGIN
    PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000002'::uuid,
      '6b0f3000-0000-4000-8000-000000000001'::uuid,
      'follow_up_consent_ratio@1',
      '6b0f7000-0000-4000-8000-000000000004'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'view-only management capability configured opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000001'::uuid,
      '6b0f3000-0000-4000-8000-000000000004'::uuid,
      'follow_up_consent_ratio@1',
      '6b0f7000-0000-4000-8000-000000000005'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'cross-organization project configured opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  -- A personal project cannot have the organization authorization chain that
  -- this resolver requires, so rejection must occur before configuration.
  BEGIN
    PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000001'::uuid,
      '6b0f3000-0000-4000-8000-000000000005'::uuid,
      'follow_up_consent_ratio@1',
      '6b0f7000-0000-4000-8000-000000000006'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'personal project configured management opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000001'::uuid,
      '6b0f3000-0000-4000-8000-000000000003'::uuid,
      'follow_up_consent_ratio@1',
      '6b0f7000-0000-4000-8000-000000000007'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'archived project configured management opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000004'::uuid,
      '6b0f3000-0000-4000-8000-000000000002'::uuid,
      'follow_up_consent_ratio@1',
      '6b0f7000-0000-4000-8000-000000000008'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'inactive app user configured management opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.read_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000003'::uuid,
      '6b0f3000-0000-4000-8000-000000000004'::uuid,
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'expired project membership read management opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.read_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000002'::uuid,
      '6b0f3000-0000-4000-8000-000000000002'::uuid,
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'same-organization actor without project membership read opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.read_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000099'::uuid,
      '6b0f3000-0000-4000-8000-000000000001'::uuid,
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'unknown app user read management opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    PERFORM app_private.read_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000001'::uuid,
      '6b0f3000-0000-4000-8000-000000000099'::uuid,
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'unknown project read management opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;
END
$assert_forbidden_scopes$;

DO $assert_forged_provenance$
BEGIN
  INSERT INTO app_private.management_follow_up_consent_opt_in_versions (
    project_id,
    metric_id,
    version_number,
    expected_version,
    enabled,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    request_id,
    authorization_reference_at_utc,
    recorded_at_utc
  ) VALUES (
    '6b0f3000-0000-4000-8000-000000000001'::uuid,
    'follow_up_consent_ratio@1',
    4,
    3,
    true,
    '6b0f1000-0000-4000-8000-000000000001'::uuid,
    '6b0f2000-0000-4000-8000-000000000001'::uuid,
    '6b0f4000-0000-4000-8000-000000000002'::uuid,
    '6b0f5000-0000-4000-8000-000000000004'::uuid,
    '6b0f6000-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    '6b0f7000-0000-4000-8000-000000000009'::uuid,
    clock_timestamp(),
    clock_timestamp()
  );
  RAISE EXCEPTION 'forged 6BO authorization provenance was accepted';
EXCEPTION
  WHEN SQLSTATE '22023' OR SQLSTATE '42501' THEN
    NULL;
END
$assert_forged_provenance$;

DO $assert_immutable_history$
BEGIN
  BEGIN
    UPDATE app_private.management_follow_up_consent_opt_in_versions
    SET enabled = false
    WHERE project_id = '6b0f3000-0000-4000-8000-000000000001'::uuid
      AND version_number = 1;
    RAISE EXCEPTION '6BO history UPDATE was accepted';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_follow_up_consent_opt_in_versions
    WHERE project_id = '6b0f3000-0000-4000-8000-000000000001'::uuid
      AND version_number = 1;
    RAISE EXCEPTION '6BO history DELETE was accepted';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN NULL;
  END;
END
$assert_immutable_history$;

SET LOCAL ROLE tongxingzhe_runtime;

DO $assert_runtime_boundary$
BEGIN
  BEGIN
    PERFORM app_private.read_management_follow_up_consent_opt_in_v1(
      '6b0f1000-0000-4000-8000-000000000001'::uuid,
      '6b0f3000-0000-4000-8000-000000000001'::uuid,
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'runtime executed private 6BO read';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;

  BEGIN
    EXECUTE 'SELECT 1 FROM app_private.management_follow_up_consent_opt_in_versions LIMIT 1';
    RAISE EXCEPTION 'runtime selected private 6BO history';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN NULL;
  END;
END
$assert_runtime_boundary$;

RESET ROLE;

DO $assert_history$
DECLARE
  history_count integer;
  wrong_provenance_count integer;
BEGIN
  SELECT count(*)::integer
  INTO history_count
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '6b0f3000-0000-4000-8000-000000000001'::uuid;

  SELECT count(*)::integer
  INTO wrong_provenance_count
  FROM app_private.management_follow_up_consent_opt_in_versions AS version_row
  WHERE version_row.project_id =
      '6b0f3000-0000-4000-8000-000000000001'::uuid
    AND (
      version_row.requested_by_app_user_id <>
        '6b0f1000-0000-4000-8000-000000000001'::uuid
      OR version_row.organization_workspace_id <>
        '6b0f2000-0000-4000-8000-000000000001'::uuid
      OR version_row.organization_membership_id <>
        '6b0f4000-0000-4000-8000-000000000001'::uuid
      OR version_row.project_membership_id <>
        '6b0f5000-0000-4000-8000-000000000001'::uuid
      OR version_row.capability_grant_id <>
        '6b0f6000-0000-4000-8000-000000000001'::uuid
      OR version_row.capability_id <>
        'release_management_reports'
      OR version_row.authorization_reference_at_utc IS NULL
      OR version_row.recorded_at_utc IS NULL
    );

  IF history_count <> 3 OR wrong_provenance_count <> 0 THEN
    RAISE EXCEPTION
      '6BO history expected three immutable versions with complete provenance: %, %',
      history_count,
      wrong_provenance_count;
  END IF;
END
$assert_history$;

ROLLBACK;
