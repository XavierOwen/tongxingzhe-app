\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('e1000000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('e1000000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('e1000000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('e1000000-0000-4000-8000-000000000005'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  'e2000000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic trusted release workspace',
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
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'e2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic trusted release project',
    'active',
    false
  ),
  (
    'e3000000-0000-4000-8000-000000000002'::uuid,
    'e2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic unconfigured release project',
    'active',
    false
  ),
  (
    'e3000000-0000-4000-8000-000000000003'::uuid,
    'e2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic legacy release project',
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
  'e7000000-0000-4000-8000-000000000001'::uuid,
  'e3000000-0000-4000-8000-000000000001'::uuid,
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
  'trusted-release-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN 'e1000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN 'e1000000-0000-4000-8000-000000000002'::uuid
    ELSE 'e1000000-0000-4000-8000-000000000004'::uuid
  END,
  'e2000000-0000-4000-8000-000000000001'::uuid,
  'e3000000-0000-4000-8000-000000000001'::uuid,
  'e7000000-0000-4000-8000-000000000001'::uuid,
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
    'e4000000-0000-4000-8000-000000000001'::uuid,
    'e2000000-0000-4000-8000-000000000001'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e4000000-0000-4000-8000-000000000004'::uuid,
    'e2000000-0000-4000-8000-000000000001'::uuid,
    'e1000000-0000-4000-8000-000000000004'::uuid,
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
    'e5000000-0000-4000-8000-000000000001'::uuid,
    'e4000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e5000000-0000-4000-8000-000000000002'::uuid,
    'e4000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e5000000-0000-4000-8000-000000000003'::uuid,
    'e4000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e5000000-0000-4000-8000-000000000004'::uuid,
    'e4000000-0000-4000-8000-000000000004'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
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
    'e6000000-0000-4000-8000-000000000001'::uuid,
    'e5000000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e6000000-0000-4000-8000-000000000002'::uuid,
    'e5000000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e6000000-0000-4000-8000-000000000003'::uuid,
    'e5000000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'e6000000-0000-4000-8000-000000000004'::uuid,
    'e5000000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  );

DO $setup$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    'e9000000-0000-4000-8000-000000000001'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    'e9000000-0000-4000-8000-000000000003'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000003'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );
END
$setup$;

DO $fixture$
DECLARE
  result jsonb;
  replay jsonb;
  baseline_snapshot_id uuid;
  rolling_snapshot_id uuid;
  legacy_cutoff timestamp with time zone;
  attempt_count bigint;
BEGIN
  result = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000001'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF result->>'release_contract_id'
      <> 'trusted_management_report_snapshot_release_v2'
    OR result->>'result_status' <> 'approved_baseline'
    OR result->>'reporting_time_zone_version_number' <> '1'
    OR result->>'reporting_time_zone' <> 'UTC'
    OR result->>'released_snapshot_id' IS NULL
    OR result ? 'protected_report'
    OR result ? 'cells'
    OR result ? 'capability_grant_id'
    OR result::text LIKE '%contributor%'
  THEN
    RAISE EXCEPTION 'trusted release baseline is invalid or excessive';
  END IF;
  baseline_snapshot_id = (result->>'released_snapshot_id')::uuid;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts AS attempt
    WHERE attempt.release_request_id =
        'e8000000-0000-4000-8000-000000000001'::uuid
      AND attempt.capability_id = 'release_management_reports'
      AND attempt.authorization_reference_at_utc = attempt.data_cutoff_utc
      AND attempt.reporting_time_zone_version_number = 1
      AND attempt.delegated_release_request_id = attempt.release_request_id
      AND attempt.released_snapshot_id = baseline_snapshot_id
  ) THEN
    RAISE EXCEPTION 'trusted release evidence is incomplete';
  END IF;

  SELECT count(*) INTO attempt_count
  FROM app_private.management_report_release_v2_attempts;
  replay = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000001'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF replay <> result OR (
    SELECT count(*)
    FROM app_private.management_report_release_v2_attempts
  ) <> attempt_count THEN
    RAISE EXCEPTION 'trusted release replay changed its result';
  END IF;

  BEGIN
    PERFORM app_private.release_management_report_snapshot_v2(
      'e8000000-0000-4000-8000-000000000001'::uuid,
      'e1000000-0000-4000-8000-000000000001'::uuid,
      'e3000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      2
    );
    RAISE EXCEPTION 'trusted release idempotency conflict was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.release_management_report_snapshot_v2(
      'e8000000-0000-4000-8000-000000000004'::uuid,
      'e1000000-0000-4000-8000-000000000004'::uuid,
      'e3000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1
    );
    RAISE EXCEPTION 'view-only member released a report';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_private.release_management_report_snapshot_v2(
      'e8000000-0000-4000-8000-000000000005'::uuid,
      'e1000000-0000-4000-8000-000000000005'::uuid,
      'e3000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1
    );
    RAISE EXCEPTION 'account without membership released a report';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    PERFORM app_private.release_management_report_snapshot_v2(
      'e8000000-0000-4000-8000-000000000002'::uuid,
      'e1000000-0000-4000-8000-000000000001'::uuid,
      'e3000000-0000-4000-8000-000000000002'::uuid,
      'contact_sessions_by_channel_two_periods',
      1
    );
    RAISE EXCEPTION 'unconfigured project released a report';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id IN (
      'e8000000-0000-4000-8000-000000000002'::uuid,
      'e8000000-0000-4000-8000-000000000004'::uuid,
      'e8000000-0000-4000-8000-000000000005'::uuid
    )
  ) THEN
    RAISE EXCEPTION 'failed authorization wrote release evidence';
  END IF;

  result = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000006'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF result->>'result_status' <> 'approved'
    OR result->>'compared_snapshot_id' <> baseline_snapshot_id::text
  THEN
    RAISE EXCEPTION 'same-revision rolling release was not approved';
  END IF;
  rolling_snapshot_id = (result->>'released_snapshot_id')::uuid;

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
  ) VALUES (
    'trusted-release-current-extra',
    'e1000000-0000-4000-8000-000000000004'::uuid,
    'e2000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'e7000000-0000-4000-8000-000000000001'::uuid,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '5 days'
    ) AT TIME ZONE 'UTC',
    'UTC',
    transaction_timestamp() - interval '1 hour',
    'voice_call',
    'not_applicable',
    1,
    2
  );
  result = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000007'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF result->>'result_status' <> 'blocked'
    OR result->'reason_codes' = '[]'::jsonb
    OR result->>'released_snapshot_id' IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM app_private.management_report_snapshots
      WHERE release_request_id =
        'e8000000-0000-4000-8000-000000000007'::uuid
    )
  THEN
    RAISE EXCEPTION 'privacy-changing release did not fail closed';
  END IF;

  legacy_cutoff = date_trunc('milliseconds', clock_timestamp());
  PERFORM app_private.release_management_report_snapshot_v1(
    'e8000000-0000-4000-8000-000000000008'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    legacy_cutoff,
    legacy_cutoff
  );
  BEGIN
    PERFORM app_private.release_management_report_snapshot_v2(
      'e8000000-0000-4000-8000-000000000008'::uuid,
      'e1000000-0000-4000-8000-000000000001'::uuid,
      'e3000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1
    );
    RAISE EXCEPTION 'legacy request id received v2 provenance';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  legacy_cutoff = date_trunc('milliseconds', clock_timestamp());
  PERFORM app_private.release_management_report_snapshot_v1(
    'e8000000-0000-4000-8000-000000000009'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000003'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    legacy_cutoff,
    legacy_cutoff
  );
  result = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000010'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000003'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF result->>'result_status' <> 'blocked'
    OR result->'reason_codes'
      <> '["release_lineage_missing_v2_provenance"]'::jsonb
    OR EXISTS (
      SELECT 1
      FROM app_private.management_report_release_attempts
      WHERE release_request_id =
        'e8000000-0000-4000-8000-000000000010'::uuid
    )
  THEN
    RAISE EXCEPTION 'legacy lineage did not stop before report generation';
  END IF;

  PERFORM app_private.configure_project_reporting_time_zone_v1(
    'e9000000-0000-4000-8000-000000000002'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    1,
    'America/Chicago',
    transaction_timestamp() - interval '20 days'
  );
  result = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000011'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF result->>'result_status' <> 'blocked'
    OR result->>'reporting_time_zone_version_number' <> '2'
    OR result->'reason_codes'
      <> '["release_time_zone_revision_changed"]'::jsonb
  THEN
    RAISE EXCEPTION 'changed time-zone revision did not fail closed';
  END IF;

  PERFORM app_private.configure_project_reporting_time_zone_v1(
    'e9000000-0000-4000-8000-000000000004'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    2,
    'UTC',
    transaction_timestamp() - interval '10 days'
  );
  result = app_private.release_management_report_snapshot_v2(
    'e8000000-0000-4000-8000-000000000012'::uuid,
    'e1000000-0000-4000-8000-000000000001'::uuid,
    'e3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  IF result->>'result_status' <> 'blocked'
    OR result->>'reporting_time_zone_version_number' <> '3'
    OR result->>'reporting_time_zone' <> 'UTC'
    OR result->'reason_codes'
      <> '["release_time_zone_revision_changed"]'::jsonb
  THEN
    RAISE EXCEPTION 'same-name later revision bypassed lineage protection';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_report_snapshots
    WHERE project_id =
      'e3000000-0000-4000-8000-000000000001'::uuid
      AND snapshot_id IN (baseline_snapshot_id, rolling_snapshot_id)
  ) <> 2 THEN
    RAISE EXCEPTION 'trusted release changed approved snapshot history';
  END IF;

  BEGIN
    UPDATE app_private.management_report_release_v2_attempts
    SET result_status = 'blocked'
    WHERE release_request_id =
      'e8000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'trusted release history update was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id =
      'e8000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'trusted release history delete was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END
$fixture$;

ROLLBACK;
