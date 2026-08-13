-- PostgreSQL fixture：个人项目后续联系同意占比的当前启用开关。
--
-- 所有业务调用先以 issuer/subject 通过 runtime 窄函数完成；部署身份只在
-- 断言阶段读取私有历史，验证 runtime 不能绕过函数、版本只追加且停用后仍
-- 保留当前配置元数据。整个 fixture 回滚，可在恢复库中重复运行。

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE follow_up_consent_opt_in_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner'
);

CREATE TEMP TABLE follow_up_consent_opt_in_other_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-other'
);

CREATE TEMP TABLE follow_up_consent_opt_in_secondary_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  '同意占比未配置项目'
);

CREATE TEMP TABLE follow_up_consent_opt_in_archived_project AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  '同意占比归档项目'
);

CREATE TEMP TABLE follow_up_consent_opt_in_initial_state AS
SELECT app_data.read_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1'
) AS state;

DO $initial_read$
DECLARE
  initial_state jsonb := (
    SELECT state FROM follow_up_consent_opt_in_initial_state
  );
BEGIN
  IF initial_state->>'state_contract_id' <>
      'project_follow_up_consent_opt_in_state_v1'
    OR initial_state->>'status' <> 'not_enabled'
    OR initial_state->'configuration' IS DISTINCT FROM 'null'::jsonb
    OR initial_state ? 'numerator'
    OR initial_state ? 'denominator'
    OR initial_state ? 'coverage'
    OR initial_state ? 'excluded_count'
  THEN
    RAISE EXCEPTION 'unconfigured project did not return a clean not_enabled state';
  END IF;
END
$initial_read$;

CREATE TEMP TABLE follow_up_consent_opt_in_enabled_config AS
SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1',
  'e4800000-0000-4000-8000-000000000001'::uuid,
  0,
  true
) AS configuration;

CREATE TEMP TABLE follow_up_consent_opt_in_enabled_replay AS
SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1',
  'e4800000-0000-4000-8000-000000000001'::uuid,
  0,
  true
) AS configuration;

DO $initial_write$
DECLARE
  enabled_configuration jsonb := (
    SELECT configuration FROM follow_up_consent_opt_in_enabled_config
  );
  replay_configuration jsonb := (
    SELECT configuration FROM follow_up_consent_opt_in_enabled_replay
  );
BEGIN
  IF enabled_configuration->>'configuration_contract_id' <>
      'project_follow_up_consent_opt_in_configuration_v1'
    OR enabled_configuration->>'metric_id' <> 'follow_up_consent_ratio@1'
    OR enabled_configuration->>'version_number' <> '1'
    OR enabled_configuration->>'expected_version' <> '0'
    OR enabled_configuration->>'enabled' <> 'true'
    OR enabled_configuration->>'recorded_at_utc' IS NULL
    OR replay_configuration <> enabled_configuration
  THEN
    RAISE EXCEPTION 'initial project opt-in or its idempotent replay drifted';
  END IF;
END
$initial_write$;

DO $replay_conflict$
BEGIN
  PERFORM app_data.configure_project_follow_up_consent_opt_in_v1(
    'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
    'follow-up-consent-opt-in-owner',
    (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
    'follow_up_consent_ratio@1',
    'e4800000-0000-4000-8000-000000000001'::uuid,
    0,
    false
  );
  RAISE EXCEPTION 'changed project opt-in replay was accepted';
EXCEPTION
  WHEN SQLSTATE '22023' THEN
    NULL;
END
$replay_conflict$;

CREATE TEMP TABLE follow_up_consent_opt_in_enabled_state AS
SELECT app_data.read_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1'
) AS state;

DO $enabled_read$
DECLARE
  enabled_state jsonb := (
    SELECT state FROM follow_up_consent_opt_in_enabled_state
  );
  configuration jsonb;
BEGIN
  configuration := enabled_state->'configuration';
  IF enabled_state->>'status' <> 'enabled'
    OR configuration->>'version_number' <> '1'
    OR configuration->>'enabled' <> 'true'
    OR enabled_state ? 'numerator'
    OR enabled_state ? 'denominator'
    OR enabled_state ? 'coverage'
    OR enabled_state ? 'excluded_count'
  THEN
    RAISE EXCEPTION 'enabled project opt-in state is not metadata-only';
  END IF;
END
$enabled_read$;

DO $stale_version$
BEGIN
  PERFORM app_data.configure_project_follow_up_consent_opt_in_v1(
    'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
    'follow-up-consent-opt-in-owner',
    (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
    'follow_up_consent_ratio@1',
    'e4800000-0000-4000-8000-000000000002'::uuid,
    0,
    false
  );
  RAISE EXCEPTION 'stale project opt-in expected version was accepted';
EXCEPTION
  WHEN SQLSTATE '40001' THEN
    NULL;
END
$stale_version$;

CREATE TEMP TABLE follow_up_consent_opt_in_disabled_config AS
SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1',
  'e4800000-0000-4000-8000-000000000003'::uuid,
  1,
  false
) AS configuration;

CREATE TEMP TABLE follow_up_consent_opt_in_disabled_state AS
SELECT app_data.read_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1'
) AS state;

DO $disabled_read$
DECLARE
  disabled_configuration jsonb := (
    SELECT configuration FROM follow_up_consent_opt_in_disabled_config
  );
  disabled_state jsonb := (
    SELECT state FROM follow_up_consent_opt_in_disabled_state
  );
BEGIN
  IF disabled_configuration->>'version_number' <> '2'
    OR disabled_configuration->>'expected_version' <> '1'
    OR disabled_configuration->>'enabled' <> 'false'
    OR disabled_state->>'status' <> 'not_enabled'
    OR disabled_state->'configuration'->>'version_number' <> '2'
    OR disabled_state->'configuration'->>'enabled' <> 'false'
    OR disabled_state ? 'numerator'
    OR disabled_state ? 'denominator'
    OR disabled_state ? 'coverage'
    OR disabled_state ? 'excluded_count'
  THEN
    RAISE EXCEPTION 'disabled project opt-in lost current metadata or leaked values';
  END IF;
END
$disabled_read$;

CREATE TEMP TABLE follow_up_consent_opt_in_reenabled_config AS
SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
  'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
  'follow-up-consent-opt-in-owner',
  (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
  'follow_up_consent_ratio@1',
  'e4800000-0000-4000-8000-000000000004'::uuid,
  2,
  true
) AS configuration;

DO $reenable$
DECLARE
  reenabled_configuration jsonb := (
    SELECT configuration FROM follow_up_consent_opt_in_reenabled_config
  );
BEGIN
  IF reenabled_configuration->>'version_number' <> '3'
    OR reenabled_configuration->>'expected_version' <> '2'
    OR reenabled_configuration->>'enabled' <> 'true'
  THEN
    RAISE EXCEPTION 'project opt-in could not be re-enabled after disable';
  END IF;
END
$reenable$;

DO $invalid_metric$
BEGIN
  PERFORM app_data.read_project_follow_up_consent_opt_in_v1(
    'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
    'follow-up-consent-opt-in-owner',
    (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
    'not_a_metric'
  );
  RAISE EXCEPTION 'invalid project opt-in metric was accepted by read';
EXCEPTION
  WHEN SQLSTATE '22023' THEN
    NULL;
END
$invalid_metric$;

DO $invalid_config_metric$
BEGIN
  PERFORM app_data.configure_project_follow_up_consent_opt_in_v1(
    'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
    'follow-up-consent-opt-in-owner',
    (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
    'not_a_metric',
    'e4800000-0000-4000-8000-000000000005'::uuid,
    3,
    true
  );
  RAISE EXCEPTION 'invalid project opt-in metric was accepted by configure';
EXCEPTION
  WHEN SQLSTATE '22023' THEN
    NULL;
END
$invalid_config_metric$;

DO $scope_checks$
BEGIN
  BEGIN
    PERFORM app_data.read_project_follow_up_consent_opt_in_v1(
      'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
      'follow-up-consent-opt-in-other',
      (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'another identity read the owner project opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.configure_project_follow_up_consent_opt_in_v1(
      'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
      'follow-up-consent-opt-in-other',
      (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
      'follow_up_consent_ratio@1',
      'e4800000-0000-4000-8000-000000000006'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'another identity configured the owner project opt-in';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL;
  END;
END
$scope_checks$;

RESET ROLE;

DO $private_insert_checks$
BEGIN
  BEGIN
    INSERT INTO app_private.project_follow_up_consent_opt_in_versions (
      project_id,
      metric_id,
      version_number,
      expected_version,
      enabled,
      actor_app_user_id,
      request_id
    ) VALUES (
      (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
      'follow_up_consent_ratio@1',
      4,
      3,
      true,
      (SELECT app_user_id FROM follow_up_consent_opt_in_other_context),
      'e4800000-0000-4000-8000-000000000009'::uuid
    );
    RAISE EXCEPTION 'invalid project opt-in actor scope was accepted';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL;
  END;

  BEGIN
    INSERT INTO app_private.project_follow_up_consent_opt_in_versions (
      project_id,
      metric_id,
      version_number,
      expected_version,
      enabled,
      actor_app_user_id,
      request_id
    ) VALUES (
      (SELECT project_id FROM follow_up_consent_opt_in_owner_context),
      'follow_up_consent_ratio@1',
      5,
      0,
      true,
      (SELECT app_user_id FROM follow_up_consent_opt_in_owner_context),
      'e4800000-0000-4000-8000-00000000000a'::uuid
    );
    RAISE EXCEPTION 'malformed project opt-in version chain was accepted';
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      NULL;
  END;
END
$private_insert_checks$;

UPDATE app_data.projects
SET status = 'archived'
WHERE project_id = (
  SELECT project_id FROM follow_up_consent_opt_in_archived_project
);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id
) VALUES (
  'e4900000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '同意占比组织空间',
  NULL
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status
) VALUES (
  'e4a00000-0000-4000-8000-000000000001'::uuid,
  'e4900000-0000-4000-8000-000000000001'::uuid,
  '同意占比组织项目',
  'active'
);

SET LOCAL ROLE tongxingzhe_runtime;

DO $archived_scope$
BEGIN
  BEGIN
    PERFORM app_data.read_project_follow_up_consent_opt_in_v1(
      'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
      'follow-up-consent-opt-in-owner',
      (SELECT project_id FROM follow_up_consent_opt_in_archived_project),
      'follow_up_consent_ratio@1'
    );
    RAISE EXCEPTION 'archived project opt-in was readable';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.configure_project_follow_up_consent_opt_in_v1(
      'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
      'follow-up-consent-opt-in-owner',
      (SELECT project_id FROM follow_up_consent_opt_in_archived_project),
      'follow_up_consent_ratio@1',
      'e4800000-0000-4000-8000-000000000007'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'archived project opt-in was configurable';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.configure_project_follow_up_consent_opt_in_v1(
      'https://synthetic-follow-up-consent-opt-in.example.test/auth/v1',
      'follow-up-consent-opt-in-owner',
      'e4a00000-0000-4000-8000-000000000001'::uuid,
      'follow_up_consent_ratio@1',
      'e4800000-0000-4000-8000-000000000008'::uuid,
      0,
      true
    );
    RAISE EXCEPTION 'organization project opt-in was configurable';
  EXCEPTION
    WHEN SQLSTATE '42501' THEN
      NULL;
  END;

  BEGIN
    SELECT count(*)
    FROM app_private.project_follow_up_consent_opt_in_versions;
    RAISE EXCEPTION 'runtime read the project opt-in history table';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    UPDATE app_private.project_follow_up_consent_opt_in_versions
    SET enabled = false;
    RAISE EXCEPTION 'runtime updated project opt-in history';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$archived_scope$;

RESET ROLE;

DO $immutable_history$
DECLARE
  history_count integer;
BEGIN
  SELECT count(*)
  INTO history_count
  FROM app_private.project_follow_up_consent_opt_in_versions
  WHERE project_id = (
    SELECT project_id FROM follow_up_consent_opt_in_owner_context
  );

  IF history_count <> 3 THEN
    RAISE EXCEPTION 'project opt-in history count drifted: %', history_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.project_follow_up_consent_opt_in_versions
    WHERE project_id = (
        SELECT project_id FROM follow_up_consent_opt_in_owner_context
      )
      AND recorded_at_utc IS NULL
  ) THEN
    RAISE EXCEPTION 'project opt-in history lost database recorded time';
  END IF;

  BEGIN
    UPDATE app_private.project_follow_up_consent_opt_in_versions
    SET enabled = false
    WHERE project_id = (
      SELECT project_id FROM follow_up_consent_opt_in_owner_context
    )
      AND version_number = 1;
    RAISE EXCEPTION 'project opt-in history update was accepted';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      NULL;
  END;

  BEGIN
    DELETE FROM app_private.project_follow_up_consent_opt_in_versions
    WHERE project_id = (
      SELECT project_id FROM follow_up_consent_opt_in_owner_context
    )
      AND version_number = 1;
    RAISE EXCEPTION 'project opt-in history delete was accepted';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      NULL;
  END;
END
$immutable_history$;

ROLLBACK;
