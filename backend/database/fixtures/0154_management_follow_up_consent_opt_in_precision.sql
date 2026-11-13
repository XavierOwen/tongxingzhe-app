\set ON_ERROR_STOP on
\ir shared/database_state.sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE precision_owner ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0154-opt-in-precision.example.test/auth/v1', '0154-opt-in-owner'
);
CREATE TEMP TABLE precision_org ON COMMIT DROP AS
SELECT created.* FROM precision_owner owner,
  LATERAL app_private.create_organization_v1(
    owner.app_user_id, gen_random_uuid(), '0154 opt-in precision organization'
  ) created;
CREATE TEMP TABLE precision_project ON COMMIT DROP AS SELECT gen_random_uuid() AS project_id;
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT project_id, organization_workspace_id, '0154 opt-in precision project'
FROM precision_project CROSS JOIN precision_org;
CREATE TEMP TABLE precision_member ON COMMIT DROP AS
SELECT assigned.* FROM precision_owner owner, precision_org org, precision_project project,
  LATERAL app_private.assign_organization_project_member_v1(
    owner.app_user_id, gen_random_uuid(), org.organization_workspace_id,
    project.project_id, org.organization_membership_id
  ) assigned;

DO $precision$
DECLARE
  owner precision_owner%ROWTYPE;
  member precision_member%ROWTYPE;
  invalid_period text;
  grant_start timestamptz;
  grant_id uuid;
  previous_grant_id uuid;
  trial_request_id uuid;
  started_at timestamptz;
  finished_at timestamptz;
  attempt integer;
  result jsonb;
  saved_state jsonb;
  version_row app_private.management_follow_up_consent_opt_in_versions%ROWTYPE;
BEGIN
  SELECT * INTO STRICT owner FROM precision_owner;
  SELECT * INTO STRICT member FROM precision_member;
  FOR invalid_period IN SELECT unnest(ARRAY['future', 'expired']) LOOP
    BEGIN
      INSERT INTO app_data.management_report_capability_grants(
        capability_grant_id, project_membership_id, capability_id, active_from_utc, inactive_from_utc
      ) SELECT gen_random_uuid(), member.project_membership_id, 'release_management_reports',
        CASE WHEN invalid_period = 'future' THEN clock_timestamp() + interval '1 hour'
          ELSE membership.active_from_utc END,
        CASE WHEN invalid_period = 'expired' THEN clock_timestamp() - interval '1 microsecond' END
      FROM app_data.project_memberships membership
      WHERE membership.project_membership_id = member.project_membership_id;
      saved_state := pg_temp.fixture_database_state();
      BEGIN
        PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(
          owner.app_user_id, member.project_id, 'follow_up_consent_ratio@1', gen_random_uuid(), 0, true
        );
        RAISE EXCEPTION '0154 % grant was accepted', invalid_period;
      EXCEPTION WHEN insufficient_privilege THEN NULL;
      END;
      IF pg_temp.fixture_database_state() IS DISTINCT FROM saved_state
      THEN RAISE EXCEPTION '0154 % grant rejection changed business facts', invalid_period; END IF;
      RAISE SQLSTATE 'P9001' USING MESSAGE = 'rollback synthetic invalid grant';
    EXCEPTION WHEN SQLSTATE 'P9001' THEN NULL;
    END;
  END LOOP;

  -- Repeated boundaries catch the warmed writer within the grant's first millisecond.
  FOR attempt IN 1..32 LOOP
    grant_id := gen_random_uuid();
    trial_request_id := gen_random_uuid();
    grant_start := date_trunc('milliseconds', clock_timestamp() + interval '5 milliseconds')
      + interval '1 microsecond';
    IF previous_grant_id IS NOT NULL THEN
      UPDATE app_data.management_report_capability_grants SET inactive_from_utc = grant_start
      WHERE capability_grant_id = previous_grant_id;
    END IF;
    INSERT INTO app_data.management_report_capability_grants(
      capability_grant_id, project_membership_id, capability_id, active_from_utc
    ) VALUES(grant_id, member.project_membership_id, 'release_management_reports', grant_start);
    WHILE clock_timestamp() < grant_start LOOP NULL; END LOOP;
    started_at := clock_timestamp();
    result := app_private.configure_management_follow_up_consent_opt_in_v1(
      owner.app_user_id, member.project_id, 'follow_up_consent_ratio@1', trial_request_id, attempt - 1, true
    );
    finished_at := clock_timestamp();
    SELECT * INTO STRICT version_row
    FROM app_private.management_follow_up_consent_opt_in_versions version
    WHERE version.request_id = trial_request_id;
    IF version_row.version_number <> attempt OR version_row.expected_version <> attempt - 1
      OR version_row.requested_by_app_user_id <> owner.app_user_id
      OR version_row.organization_membership_id <> member.organization_membership_id
      OR version_row.project_membership_id <> member.project_membership_id
      OR version_row.capability_grant_id <> grant_id
      OR version_row.authorization_reference_at_utc < grant_start
      OR version_row.authorization_reference_at_utc < started_at
      OR version_row.authorization_reference_at_utc > finished_at
      OR result IS DISTINCT FROM app_private.management_follow_up_consent_opt_in_document_v1(member.project_id, attempt)
      OR result->>'recorded_at_utc' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
    THEN RAISE EXCEPTION '0154 valid grant lost exact provenance or configuration at attempt %', attempt; END IF;
    previous_grant_id := grant_id;
  END LOOP;

  IF (SELECT count(*) FROM app_private.management_follow_up_consent_opt_in_versions
      WHERE project_id = member.project_id) <> 32
    OR EXISTS (
      SELECT 1 FROM app_private.management_follow_up_consent_opt_in_versions version
      JOIN app_data.management_report_capability_grants capability USING(capability_grant_id)
      WHERE version.project_id = member.project_id
        AND (version.authorization_reference_at_utc < capability.active_from_utc
          OR version.authorization_reference_at_utc >= capability.inactive_from_utc)
    )
  THEN RAISE EXCEPTION '0154 history no longer matches its exact grant intervals'; END IF;
  saved_state := pg_temp.fixture_database_state();
  IF app_private.configure_management_follow_up_consent_opt_in_v1(
      owner.app_user_id, member.project_id, 'follow_up_consent_ratio@1', trial_request_id, 31, true
    ) IS DISTINCT FROM result
    OR pg_temp.fixture_database_state() IS DISTINCT FROM saved_state
  THEN RAISE EXCEPTION '0154 exact configuration replay changed receipt or business facts'; END IF;
END
$precision$;

ROLLBACK;
SELECT 'management follow-up consent opt-in precise authorization, invalid intervals and replay: passed' AS result;
