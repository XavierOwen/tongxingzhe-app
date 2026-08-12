\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6c100000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6c100000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6c100000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    '6ce00000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-report.synthetic/auth/v1',
    'view-only-member',
    '6c100000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6ce00000-0000-4000-8000-000000000002'::uuid,
    'https://runtime-report.synthetic/auth/v1',
    'release-only-member',
    '6c100000-0000-4000-8000-000000000003'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  '6c200000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic runtime report workspace',
  NULL,
  NULL
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
) VALUES
  (
    '6c300000-0000-4000-8000-000000000001'::uuid,
    '6c200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic runtime report project',
    'active',
    false
  ),
  (
    '6c300000-0000-4000-8000-000000000002'::uuid,
    '6c200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic other runtime report project',
    'active',
    false
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  '6c700000-0000-4000-8000-000000000001'::uuid,
  '6c300000-0000-4000-8000-000000000001'::uuid,
  1,
  'published',
  true
);

INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel,
  location_kind,
  reach_count,
  interest_level
)
SELECT
  'runtime-report-read-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '6c100000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '6c100000-0000-4000-8000-000000000002'::uuid
    ELSE '6c100000-0000-4000-8000-000000000003'::uuid
  END,
  '6c200000-0000-4000-8000-000000000001'::uuid,
  '6c300000-0000-4000-8000-000000000001'::uuid,
  '6c700000-0000-4000-8000-000000000001'::uuid,
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  SELECT
    'previous'::text AS period_key,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '12 days'
    ) AT TIME ZONE 'UTC' AS occurred_at_utc
  UNION ALL
  SELECT
    'current'::text,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '5 days'
    ) AT TIME ZONE 'UTC'
) AS period_row
CROSS JOIN generate_series(1, 10) AS series_row;

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6c400000-0000-4000-8000-000000000001'::uuid,
    '6c200000-0000-4000-8000-000000000001'::uuid,
    '6c100000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c400000-0000-4000-8000-000000000002'::uuid,
    '6c200000-0000-4000-8000-000000000001'::uuid,
    '6c100000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c400000-0000-4000-8000-000000000003'::uuid,
    '6c200000-0000-4000-8000-000000000001'::uuid,
    '6c100000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6c500000-0000-4000-8000-000000000001'::uuid,
    '6c400000-0000-4000-8000-000000000001'::uuid,
    '6c300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c500000-0000-4000-8000-000000000002'::uuid,
    '6c400000-0000-4000-8000-000000000002'::uuid,
    '6c300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c500000-0000-4000-8000-000000000003'::uuid,
    '6c400000-0000-4000-8000-000000000003'::uuid,
    '6c300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c500000-0000-4000-8000-000000000004'::uuid,
    '6c400000-0000-4000-8000-000000000002'::uuid,
    '6c300000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6c600000-0000-4000-8000-000000000001'::uuid,
    '6c500000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c600000-0000-4000-8000-000000000002'::uuid,
    '6c500000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c600000-0000-4000-8000-000000000003'::uuid,
    '6c500000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '6c600000-0000-4000-8000-000000000004'::uuid,
    '6c500000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  );

DO $setup$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '6c900000-0000-4000-8000-000000000001'::uuid,
    '6c100000-0000-4000-8000-000000000001'::uuid,
    '6c300000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );

  PERFORM app_private.release_management_report_snapshot_v2(
    '6c800000-0000-4000-8000-000000000001'::uuid,
    '6c100000-0000-4000-8000-000000000001'::uuid,
    '6c300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
END
$setup$;

SELECT released_snapshot_id AS trusted_snapshot_id
FROM app_private.management_report_release_v2_attempts
WHERE release_request_id =
  '6c800000-0000-4000-8000-000000000001'::uuid
\gset

SET LOCAL ROLE tongxingzhe_runtime;
SELECT app_data.read_authorized_management_report_snapshot_v1(
  'https://runtime-report.synthetic/auth/v1',
  'view-only-member',
  '6c300000-0000-4000-8000-000000000001'::uuid,
  :'trusted_snapshot_id'::uuid
);
RESET ROLE;

DO $fixture$
DECLARE
  trusted_snapshot_id uuid;
  legacy_snapshot_id uuid;
  trusted_report jsonb;
  repeated_read jsonb;
  unavailable_read jsonb;
  cross_project_read jsonb;
  legacy_read jsonb;
  legacy_cutoff timestamp with time zone;
  before_app_users bigint;
  before_workspaces bigint;
  before_projects bigint;
BEGIN
  SELECT
    attempt.released_snapshot_id,
    attempt.data_cutoff_utc
    INTO STRICT trusted_snapshot_id, legacy_cutoff
  FROM app_private.management_report_release_v2_attempts AS attempt
  WHERE attempt.release_request_id =
    '6c800000-0000-4000-8000-000000000001'::uuid;

  SELECT snapshot.protected_report INTO STRICT trusted_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = trusted_snapshot_id;

  repeated_read = app_data.read_authorized_management_report_snapshot_v1(
    'https://runtime-report.synthetic/auth/v1',
    'view-only-member',
    '6c300000-0000-4000-8000-000000000001'::uuid,
    trusted_snapshot_id
  );
  IF repeated_read->>'result_status' <> 'completed'
    OR repeated_read->'protected_report' <> trusted_report
    OR (repeated_read->>'resolved_snapshot_id')::uuid <> trusted_snapshot_id
  THEN
    RAISE EXCEPTION 'runtime bridge did not return the trusted snapshot';
  END IF;

  legacy_cutoff = legacy_cutoff + interval '1 second';
  PERFORM app_private.release_management_report_snapshot_v1(
    '6c800000-0000-4000-8000-000000000002'::uuid,
    '6c100000-0000-4000-8000-000000000001'::uuid,
    '6c300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    legacy_cutoff,
    legacy_cutoff
  );
  SELECT attempt.released_snapshot_id INTO STRICT legacy_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6c800000-0000-4000-8000-000000000002'::uuid;

  unavailable_read =
    app_data.read_authorized_management_report_snapshot_v1(
      'https://runtime-report.synthetic/auth/v1',
      'view-only-member',
      '6c300000-0000-4000-8000-000000000001'::uuid,
      '6ca00000-0000-4000-8000-000000000001'::uuid
    );
  cross_project_read =
    app_data.read_authorized_management_report_snapshot_v1(
      'https://runtime-report.synthetic/auth/v1',
      'view-only-member',
      '6c300000-0000-4000-8000-000000000002'::uuid,
      trusted_snapshot_id
    );
  legacy_read = app_data.read_authorized_management_report_snapshot_v1(
    'https://runtime-report.synthetic/auth/v1',
    'view-only-member',
    '6c300000-0000-4000-8000-000000000001'::uuid,
    legacy_snapshot_id
  );

  IF unavailable_read->>'result_status' <> 'not_found'
    OR cross_project_read->>'result_status' <> 'not_found'
    OR unavailable_read->>'reason_code' <> 'snapshot_not_available'
    OR cross_project_read->>'reason_code' <> 'snapshot_not_available'
    OR unavailable_read ? 'protected_report'
    OR cross_project_read ? 'protected_report'
    OR legacy_read->>'result_status' <> 'untrusted_provenance'
    OR legacy_read->>'reason_code' <> 'snapshot_provenance_untrusted'
    OR legacy_read ? 'protected_report'
  THEN
    RAISE EXCEPTION 'runtime bridge exposed an unavailable snapshot';
  END IF;

  BEGIN
    PERFORM app_data.read_authorized_management_report_snapshot_v1(
      'https://runtime-report.synthetic/auth/v1',
      'release-only-member',
      '6c300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'runtime bridge treated release capability as view';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  SELECT count(*) INTO before_app_users FROM app_data.app_users;
  SELECT count(*) INTO before_workspaces FROM app_data.workspaces;
  SELECT count(*) INTO before_projects FROM app_data.projects;
  BEGIN
    PERFORM app_data.read_authorized_management_report_snapshot_v1(
      'https://runtime-report.synthetic/auth/v1',
      'unknown-member',
      '6c300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'runtime bridge accepted an unknown identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  IF before_app_users <> (SELECT count(*) FROM app_data.app_users)
    OR before_workspaces <> (SELECT count(*) FROM app_data.workspaces)
    OR before_projects <> (SELECT count(*) FROM app_data.projects)
  THEN
    RAISE EXCEPTION 'management report read bootstrapped personal context';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      '6c100000-0000-4000-8000-000000000002'::uuid
  ) <> 5 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
        '6c100000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'completed'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
        '6c100000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'not_found'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
        '6c100000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'untrusted_provenance'
  ) <> 1 THEN
    RAISE EXCEPTION 'runtime bridge access audit counts are incorrect';
  END IF;
END
$fixture$;

ROLLBACK;
