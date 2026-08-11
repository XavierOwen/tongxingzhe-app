\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('b1000000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000005'::uuid, 'deletion_pending'),
  ('b1000000-0000-4000-8000-000000000006'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000007'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000008'::uuid, 'active'),
  ('b1000000-0000-4000-8000-000000000009'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES
  (
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Synthetic authorization workspace',
    NULL,
    NULL
  ),
  (
    'b2000000-0000-4000-8000-000000000002'::uuid,
    'organization',
    'Synthetic other organization',
    NULL,
    NULL
  ),
  (
    'b2000000-0000-4000-8000-000000000003'::uuid,
    'organization',
    'Synthetic deleted organization',
    NULL,
    transaction_timestamp() - interval '1 day'
  ),
  (
    'b2000000-0000-4000-8000-000000000004'::uuid,
    'personal',
    'Synthetic personal workspace',
    'b1000000-0000-4000-8000-000000000001'::uuid,
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
    'b3000000-0000-4000-8000-000000000001'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic authorized project',
    'active',
    false
  ),
  (
    'b3000000-0000-4000-8000-000000000002'::uuid,
    'b2000000-0000-4000-8000-000000000002'::uuid,
    'Synthetic other project',
    'active',
    false
  ),
  (
    'b3000000-0000-4000-8000-000000000003'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic archived project',
    'archived',
    false
  ),
  (
    'b3000000-0000-4000-8000-000000000004'::uuid,
    'b2000000-0000-4000-8000-000000000003'::uuid,
    'Synthetic deleted organization project',
    'active',
    false
  ),
  (
    'b3000000-0000-4000-8000-000000000005'::uuid,
    'b2000000-0000-4000-8000-000000000004'::uuid,
    'Synthetic personal project',
    'active',
    true
  );

INSERT INTO app_data.user_current_projects (app_user_id, project_id)
VALUES (
  'b1000000-0000-4000-8000-000000000001'::uuid,
  'b3000000-0000-4000-8000-000000000005'::uuid
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  'b7000000-0000-4000-8000-000000000001'::uuid,
  'b3000000-0000-4000-8000-000000000001'::uuid,
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
  'authorization-regression-' || period_row.period_key
    || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN 'b1000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN 'b1000000-0000-4000-8000-000000000002'::uuid
    ELSE 'b1000000-0000-4000-8000-000000000003'::uuid
  END,
  'b2000000-0000-4000-8000-000000000001'::uuid,
  'b3000000-0000-4000-8000-000000000001'::uuid,
  'b7000000-0000-4000-8000-000000000001'::uuid,
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  VALUES
    ('week_a'::text, '2026-06-03 12:00:00+00'::timestamptz),
    ('week_b'::text, '2026-06-10 12:00:00+00'::timestamptz)
) AS period_row(period_key, occurred_at_utc)
CROSS JOIN generate_series(1, 10) AS series_row;

DO $regression_setup$
DECLARE
  release_result jsonb;
  time_zone_result jsonb;
BEGIN
  release_result = app_private.release_management_report_snapshot_v1(
    'b8000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000001'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-17 12:00:00+00'::timestamptz,
    '2026-06-17 12:01:00+00'::timestamptz
  );
  IF release_result->>'result_status' <> 'approved_baseline' THEN
    RAISE EXCEPTION '6G regression snapshot was not created';
  END IF;

  time_zone_result = app_private.configure_project_reporting_time_zone_v1(
    'b9000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000001'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    '2026-06-17 12:02:00+00'::timestamptz
  );
  IF time_zone_result->>'version_number' <> '1' THEN
    RAISE EXCEPTION '6H regression time zone was not configured';
  END IF;
END
$regression_setup$;

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'b4000000-0000-4000-8000-000000000001'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  ),
  (
    'b4000000-0000-4000-8000-000000000002'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b4000000-0000-4000-8000-000000000003'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b4000000-0000-4000-8000-000000000004'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000004'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b4000000-0000-4000-8000-000000000006'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000006'::uuid,
    transaction_timestamp() + interval '1 day',
    NULL
  ),
  (
    'b4000000-0000-4000-8000-000000000070'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000007'::uuid,
    transaction_timestamp() - interval '10 days',
    transaction_timestamp() - interval '5 days'
  ),
  (
    'b4000000-0000-4000-8000-000000000071'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000007'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b4000000-0000-4000-8000-000000000008'::uuid,
    'b2000000-0000-4000-8000-000000000001'::uuid,
    'b1000000-0000-4000-8000-000000000008'::uuid,
    transaction_timestamp() - interval '1 day',
    transaction_timestamp()
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'b5000000-0000-4000-8000-000000000001'::uuid,
    'b4000000-0000-4000-8000-000000000001'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  ),
  (
    'b5000000-0000-4000-8000-000000000002'::uuid,
    'b4000000-0000-4000-8000-000000000002'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b5000000-0000-4000-8000-000000000004'::uuid,
    'b4000000-0000-4000-8000-000000000004'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b5000000-0000-4000-8000-000000000006'::uuid,
    'b4000000-0000-4000-8000-000000000006'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() + interval '1 day',
    NULL
  ),
  (
    'b5000000-0000-4000-8000-000000000070'::uuid,
    'b4000000-0000-4000-8000-000000000070'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '10 days',
    transaction_timestamp() - interval '5 days'
  ),
  (
    'b5000000-0000-4000-8000-000000000008'::uuid,
    'b4000000-0000-4000-8000-000000000008'::uuid,
    'b3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '1 day',
    transaction_timestamp()
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'b6000000-0000-4000-8000-000000000001'::uuid,
    'b5000000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp(),
    NULL
  ),
  (
    'b6000000-0000-4000-8000-000000000002'::uuid,
    'b5000000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '1 day',
    NULL
  ),
  (
    'b6000000-0000-4000-8000-000000000006'::uuid,
    'b5000000-0000-4000-8000-000000000006'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() + interval '1 day',
    NULL
  ),
  (
    'b6000000-0000-4000-8000-000000000070'::uuid,
    'b5000000-0000-4000-8000-000000000070'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '10 days',
    transaction_timestamp() - interval '5 days'
  ),
  (
    'b6000000-0000-4000-8000-000000000008'::uuid,
    'b5000000-0000-4000-8000-000000000008'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '1 day',
    transaction_timestamp()
  );

DO $fixture$
DECLARE
  authorization_document jsonb;
  current_project_before jsonb;
  current_project_after jsonb;
  snapshot_before jsonb;
  snapshot_after jsonb;
  time_zone_before jsonb;
  time_zone_after jsonb;
  snapshot_count_before bigint;
  snapshot_count_after bigint;
  time_zone_count_before bigint;
  time_zone_count_after bigint;
  authorization_window_start timestamp with time zone;
  authorization_window_end timestamp with time zone;
BEGIN
  IF tstzrange(
      '2026-01-01 00:00:00+00'::timestamptz,
      '2026-01-02 00:00:00+00'::timestamptz,
      '[)'
    ) @> '2026-01-01 00:00:00+00'::timestamptz IS NOT TRUE
    OR tstzrange(
      '2026-01-01 00:00:00+00'::timestamptz,
      '2026-01-02 00:00:00+00'::timestamptz,
      '[)'
    ) @> '2026-01-02 00:00:00+00'::timestamptz IS TRUE
  THEN
    RAISE EXCEPTION 'management authorization periods are not left-closed right-open';
  END IF;

  SELECT to_jsonb(current_row.*) INTO STRICT current_project_before
  FROM app_data.user_current_projects AS current_row
  WHERE current_row.app_user_id =
    'b1000000-0000-4000-8000-000000000001'::uuid;

  SELECT count(*) INTO snapshot_count_before
  FROM app_private.management_report_snapshots;

  SELECT to_jsonb(snapshot_row.*) INTO STRICT snapshot_before
  FROM app_private.management_report_snapshots AS snapshot_row
  WHERE snapshot_row.project_id =
    'b3000000-0000-4000-8000-000000000001'::uuid;

  SELECT count(*) INTO time_zone_count_before
  FROM app_private.project_reporting_time_zone_versions;

  SELECT to_jsonb(time_zone_row.*) INTO STRICT time_zone_before
  FROM app_private.project_reporting_time_zone_versions AS time_zone_row
  WHERE time_zone_row.project_id =
    'b3000000-0000-4000-8000-000000000001'::uuid;

  authorization_window_start = clock_timestamp();
  authorization_document =
    app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
  authorization_window_end = clock_timestamp();

  IF authorization_document->>'authorization_contract_id'
      <> 'management_report_authorization_v1'
    OR authorization_document->>'organization_workspace_id'
      <> 'b2000000-0000-4000-8000-000000000001'
    OR authorization_document->>'organization_membership_id'
      <> 'b4000000-0000-4000-8000-000000000001'
    OR authorization_document->>'project_membership_id'
      <> 'b5000000-0000-4000-8000-000000000001'
    OR authorization_document->>'capability_grant_id'
      <> 'b6000000-0000-4000-8000-000000000001'
    OR authorization_document->>'capability_id'
      <> 'view_anonymous_analytics'
    OR (authorization_document->>'reference_at_utc')::timestamptz
      < date_trunc('milliseconds', authorization_window_start)
    OR (authorization_document->>'reference_at_utc')::timestamptz
      > authorization_window_end
  THEN
    RAISE EXCEPTION 'management report authorization evidence is incorrect';
  END IF;

  authorization_document =
    app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000002'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'
    );
  IF authorization_document->>'capability_id'
      <> 'release_management_reports'
  THEN
    RAISE EXCEPTION 'report release authorization was not resolved';
  END IF;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'
    );
    RAISE EXCEPTION 'view capability implied report release';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000002'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'report release capability implied analytics view';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000003'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'organization membership implied project access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000004'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'project membership implied management capability';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000009'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'active account implied organization membership';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000006'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'future authorization chain was accepted';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000008'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'right-open revocation boundary was accepted';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000007'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'
    );
    RAISE EXCEPTION 'old child authorization revived after rejoining';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      NULL
    );
    RAISE EXCEPTION 'null management capability was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.resolve_management_report_authorization_v1(
      'b1000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      'manage_everything'
    );
    RAISE EXCEPTION 'unknown management capability was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc
    ) VALUES (
      'b4000000-0000-4000-8000-000000000005'::uuid,
      'b2000000-0000-4000-8000-000000000001'::uuid,
      'b1000000-0000-4000-8000-000000000005'::uuid,
      transaction_timestamp()
    );
    RAISE EXCEPTION 'inactive account joined organization';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc
    ) VALUES (
      'b4000000-0000-4000-8000-000000000050'::uuid,
      'b2000000-0000-4000-8000-000000000004'::uuid,
      'b1000000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp()
    );
    RAISE EXCEPTION 'personal workspace accepted organization membership';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc
    ) VALUES (
      'b4000000-0000-4000-8000-000000000051'::uuid,
      'b2000000-0000-4000-8000-000000000003'::uuid,
      'b1000000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp()
    );
    RAISE EXCEPTION 'deleted organization accepted membership';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.project_memberships (
      project_membership_id,
      organization_membership_id,
      project_id,
      active_from_utc
    ) VALUES (
      'b5000000-0000-4000-8000-000000000050'::uuid,
      'b4000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000002'::uuid,
      transaction_timestamp()
    );
    RAISE EXCEPTION 'cross-organization project membership was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.project_memberships (
      project_membership_id,
      organization_membership_id,
      project_id,
      active_from_utc
    ) VALUES (
      'b5000000-0000-4000-8000-000000000051'::uuid,
      'b4000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000003'::uuid,
      transaction_timestamp()
    );
    RAISE EXCEPTION 'archived project accepted membership';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc
    ) VALUES (
      'b4000000-0000-4000-8000-000000000052'::uuid,
      'b2000000-0000-4000-8000-000000000001'::uuid,
      'b1000000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp() + interval '1 hour'
    );
    RAISE EXCEPTION 'overlapping organization membership was accepted';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.project_memberships (
      project_membership_id,
      organization_membership_id,
      project_id,
      active_from_utc
    ) VALUES (
      'b5000000-0000-4000-8000-000000000052'::uuid,
      'b4000000-0000-4000-8000-000000000001'::uuid,
      'b3000000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp() + interval '1 hour'
    );
    RAISE EXCEPTION 'overlapping project membership was accepted';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.management_report_capability_grants (
      capability_grant_id,
      project_membership_id,
      capability_id,
      active_from_utc
    ) VALUES (
      'b6000000-0000-4000-8000-000000000052'::uuid,
      'b5000000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics',
      transaction_timestamp() + interval '1 hour'
    );
    RAISE EXCEPTION 'overlapping capability grant was accepted';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.project_memberships (
      project_membership_id,
      organization_membership_id,
      project_id,
      active_from_utc,
      inactive_from_utc
    ) VALUES (
      'b5000000-0000-4000-8000-000000000053'::uuid,
      'b4000000-0000-4000-8000-000000000008'::uuid,
      'b3000000-0000-4000-8000-000000000002'::uuid,
      transaction_timestamp() - interval '2 days',
      transaction_timestamp()
    );
    RAISE EXCEPTION 'child membership exceeded parent period';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc,
      inactive_from_utc
    ) VALUES (
      'b4000000-0000-4000-8000-000000000053'::uuid,
      'b2000000-0000-4000-8000-000000000002'::uuid,
      'b1000000-0000-4000-8000-000000000008'::uuid,
      transaction_timestamp(),
      transaction_timestamp()
    );
    RAISE EXCEPTION 'empty membership interval was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.management_report_capability_grants (
      capability_grant_id,
      project_membership_id,
      capability_id,
      active_from_utc,
      inactive_from_utc
    ) VALUES (
      'b6000000-0000-4000-8000-000000000054'::uuid,
      'b5000000-0000-4000-8000-000000000008'::uuid,
      'release_management_reports',
      transaction_timestamp() - interval '1 day',
      transaction_timestamp() + interval '1 day'
    );
    RAISE EXCEPTION 'capability grant exceeded project membership';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_data.management_report_capability_grants (
      capability_grant_id,
      project_membership_id,
      capability_id,
      active_from_utc
    ) VALUES (
      'b6000000-0000-4000-8000-000000000053'::uuid,
      'b5000000-0000-4000-8000-000000000001'::uuid,
      'manage_everything',
      transaction_timestamp()
    );
    RAISE EXCEPTION 'unknown stored capability was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE app_data.organization_memberships
    SET app_user_id = 'b1000000-0000-4000-8000-000000000002'::uuid,
        inactive_from_utc = transaction_timestamp() + interval '1 day'
    WHERE organization_membership_id =
      'b4000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'membership identity was rewritten';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'b6000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'capability history was deleted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    UPDATE app_data.project_memberships
    SET inactive_from_utc = transaction_timestamp() + interval '1 day'
    WHERE project_membership_id =
      'b5000000-0000-4000-8000-000000000002'::uuid;
    RAISE EXCEPTION 'project membership closed before capability grant';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    UPDATE app_data.organization_memberships
    SET inactive_from_utc = transaction_timestamp() + interval '1 day'
    WHERE organization_membership_id =
      'b4000000-0000-4000-8000-000000000002'::uuid;
    RAISE EXCEPTION 'organization membership closed before child relations';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  SELECT to_jsonb(current_row.*) INTO STRICT current_project_after
  FROM app_data.user_current_projects AS current_row
  WHERE current_row.app_user_id =
    'b1000000-0000-4000-8000-000000000001'::uuid;

  SELECT count(*) INTO snapshot_count_after
  FROM app_private.management_report_snapshots;

  SELECT to_jsonb(snapshot_row.*) INTO STRICT snapshot_after
  FROM app_private.management_report_snapshots AS snapshot_row
  WHERE snapshot_row.project_id =
    'b3000000-0000-4000-8000-000000000001'::uuid;

  SELECT count(*) INTO time_zone_count_after
  FROM app_private.project_reporting_time_zone_versions;

  SELECT to_jsonb(time_zone_row.*) INTO STRICT time_zone_after
  FROM app_private.project_reporting_time_zone_versions AS time_zone_row
  WHERE time_zone_row.project_id =
    'b3000000-0000-4000-8000-000000000001'::uuid;

  IF current_project_after IS DISTINCT FROM current_project_before
    OR snapshot_after IS DISTINCT FROM snapshot_before
    OR snapshot_count_after <> snapshot_count_before
    OR time_zone_after IS DISTINCT FROM time_zone_before
    OR time_zone_count_after <> time_zone_count_before
  THEN
    RAISE EXCEPTION 'existing context or management report history changed';
  END IF;
END
$fixture$;

ROLLBACK;
