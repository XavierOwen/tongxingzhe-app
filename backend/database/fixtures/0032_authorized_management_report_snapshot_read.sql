\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('c1000000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('c1000000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('c1000000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('c1000000-0000-4000-8000-000000000005'::uuid, 'active'),
  ('c1000000-0000-4000-8000-000000000006'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  'c2000000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic authorized report read workspace',
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
    'c3000000-0000-4000-8000-000000000001'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic authorized report read project',
    'active',
    false
  ),
  (
    'c3000000-0000-4000-8000-000000000002'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic other report read project',
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
  'c7000000-0000-4000-8000-000000000001'::uuid,
  'c3000000-0000-4000-8000-000000000001'::uuid,
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
  'authorized-report-read-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN 'c1000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN 'c1000000-0000-4000-8000-000000000002'::uuid
    ELSE 'c1000000-0000-4000-8000-000000000003'::uuid
  END,
  'c2000000-0000-4000-8000-000000000001'::uuid,
  'c3000000-0000-4000-8000-000000000001'::uuid,
  'c7000000-0000-4000-8000-000000000001'::uuid,
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
    'c4000000-0000-4000-8000-000000000001'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c4000000-0000-4000-8000-000000000002'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c4000000-0000-4000-8000-000000000003'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000003'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c4000000-0000-4000-8000-000000000004'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000004'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c4000000-0000-4000-8000-000000000006'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000006'::uuid,
    transaction_timestamp() - interval '60 days',
    transaction_timestamp() - interval '1 day'
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'c5000000-0000-4000-8000-000000000001'::uuid,
    'c4000000-0000-4000-8000-000000000001'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c5000000-0000-4000-8000-000000000002'::uuid,
    'c4000000-0000-4000-8000-000000000002'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c5000000-0000-4000-8000-000000000003'::uuid,
    'c4000000-0000-4000-8000-000000000002'::uuid,
    'c3000000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c5000000-0000-4000-8000-000000000004'::uuid,
    'c4000000-0000-4000-8000-000000000003'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c5000000-0000-4000-8000-000000000005'::uuid,
    'c4000000-0000-4000-8000-000000000004'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c5000000-0000-4000-8000-000000000006'::uuid,
    'c4000000-0000-4000-8000-000000000006'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    transaction_timestamp() - interval '1 day'
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'c6000000-0000-4000-8000-000000000001'::uuid,
    'c5000000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c6000000-0000-4000-8000-000000000002'::uuid,
    'c5000000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c6000000-0000-4000-8000-000000000003'::uuid,
    'c5000000-0000-4000-8000-000000000003'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c6000000-0000-4000-8000-000000000004'::uuid,
    'c5000000-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    'c6000000-0000-4000-8000-000000000005'::uuid,
    'c5000000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    transaction_timestamp() - interval '1 day'
  ),
  (
    'c6000000-0000-4000-8000-000000000006'::uuid,
    'c5000000-0000-4000-8000-000000000006'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    transaction_timestamp() - interval '1 day'
  );

DO $setup$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    'c9000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000001'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );
END
$setup$;

DO $fixture$
DECLARE
  release_result jsonb;
  first_read jsonb;
  second_read jsonb;
  unavailable_read jsonb;
  cross_project_read jsonb;
  legacy_read jsonb;
  trusted_snapshot_id uuid;
  legacy_snapshot_id uuid;
  trusted_report jsonb;
  legacy_cutoff timestamp with time zone;
  event_count bigint;
  history_text text;
BEGIN
  release_result = app_private.release_management_report_snapshot_v2(
    'c8000000-0000-4000-8000-000000000001'::uuid,
    'c1000000-0000-4000-8000-000000000001'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
  trusted_snapshot_id =
    (release_result->>'released_snapshot_id')::uuid;

  SELECT snapshot.protected_report INTO STRICT trusted_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = trusted_snapshot_id;

  first_read =
    app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000002'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );

  IF first_read->>'access_contract_id'
      <> 'authorized_management_report_snapshot_read_v1'
    OR first_read->>'result_status' <> 'completed'
    OR first_read->>'reason_code' IS NOT NULL
    OR (first_read->>'resolved_snapshot_id')::uuid <> trusted_snapshot_id
    OR first_read->'protected_report' <> trusted_report
    OR first_read ? 'capability_grant_id'
    OR first_read ? 'authorization_reference_at_utc'
  THEN
    RAISE EXCEPTION 'view-only member did not receive the trusted snapshot';
  END IF;

  legacy_cutoff =
    (release_result->>'data_cutoff_utc')::timestamptz
      + interval '1 second';
  PERFORM app_private.release_management_report_snapshot_v1(
    'c8000000-0000-4000-8000-000000000002'::uuid,
    'c1000000-0000-4000-8000-000000000001'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    legacy_cutoff,
    legacy_cutoff
  );
  SELECT attempt.released_snapshot_id INTO STRICT legacy_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    'c8000000-0000-4000-8000-000000000002'::uuid;

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
    'authorized-report-read-after-release',
    'c1000000-0000-4000-8000-000000000001'::uuid,
    'c2000000-0000-4000-8000-000000000001'::uuid,
    'c3000000-0000-4000-8000-000000000001'::uuid,
    'c7000000-0000-4000-8000-000000000001'::uuid,
    (
      date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
        - interval '4 days'
    ) AT TIME ZONE 'UTC',
    'UTC',
    transaction_timestamp(),
    'voice_call',
    'not_applicable',
    1,
    2
  );

  second_read =
    app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000002'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
  IF second_read->'protected_report' <> trusted_report
    OR second_read->>'access_event_id' = first_read->>'access_event_id'
  THEN
    RAISE EXCEPTION 'repeated read changed the snapshot or reused its audit';
  END IF;

  unavailable_read =
    app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000002'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      'ca000000-0000-4000-8000-000000000001'::uuid
    );
  cross_project_read =
    app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000002'::uuid,
      'c3000000-0000-4000-8000-000000000002'::uuid,
      trusted_snapshot_id
    );

  IF unavailable_read->>'result_status' <> 'not_found'
    OR unavailable_read->>'reason_code' <> 'snapshot_not_available'
    OR unavailable_read->>'resolved_snapshot_id' IS NOT NULL
    OR cross_project_read->>'result_status' <> 'not_found'
    OR cross_project_read->>'reason_code' <> 'snapshot_not_available'
    OR cross_project_read->>'resolved_snapshot_id' IS NOT NULL
    OR unavailable_read ? 'protected_report'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION 'unknown and cross-project snapshots are distinguishable';
  END IF;

  legacy_read =
    app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000002'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      legacy_snapshot_id
    );
  IF legacy_read->>'result_status' <> 'untrusted_provenance'
    OR legacy_read->>'reason_code' <> 'snapshot_provenance_untrusted'
    OR legacy_read ? 'protected_report'
  THEN
    RAISE EXCEPTION 'legacy snapshot was exposed as a trusted report';
  END IF;

  BEGIN
    PERFORM app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000003'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'release-only member read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000004'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'expired view capability read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000005'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'user without a membership read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_report_snapshot_v1(
      'c1000000-0000-4000-8000-000000000006'::uuid,
      'c3000000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'expired member read a protected snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  SELECT count(*) INTO event_count
  FROM app_private.management_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id =
    'c1000000-0000-4000-8000-000000000002'::uuid;
  IF event_count <> 5 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      'c1000000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'completed'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      'c1000000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'not_found'
  ) <> 2 OR (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events AS event
    WHERE event.requested_by_app_user_id =
      'c1000000-0000-4000-8000-000000000002'::uuid
      AND event.result_status = 'untrusted_provenance'
  ) <> 1 THEN
    RAISE EXCEPTION 'snapshot access audit counts are incorrect';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ') INTO history_text
  FROM app_private.management_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id =
    'c1000000-0000-4000-8000-000000000002'::uuid;
  IF history_text ~ '(protected_report|cells|value_count|contributor|reach_count|interest_level)'
  THEN
    RAISE EXCEPTION 'snapshot access audit retained protected report values';
  END IF;

  BEGIN
    INSERT INTO app_private.management_report_snapshot_access_events (
      access_event_id,
      requested_by_app_user_id,
      organization_workspace_id,
      organization_membership_id,
      project_membership_id,
      capability_grant_id,
      capability_id,
      authorization_reference_at_utc,
      project_id,
      requested_snapshot_id,
      resolved_snapshot_id,
      report_id,
      report_version,
      query_fingerprint,
      accessed_at_utc,
      result_status,
      reason_code
    ) VALUES (
      'cb000000-0000-4000-8000-000000000001'::uuid,
      'c1000000-0000-4000-8000-000000000002'::uuid,
      'c2000000-0000-4000-8000-000000000001'::uuid,
      'c4000000-0000-4000-8000-000000000002'::uuid,
      'c5000000-0000-4000-8000-000000000002'::uuid,
      'c6000000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics',
      transaction_timestamp(),
      'c3000000-0000-4000-8000-000000000001'::uuid,
      legacy_snapshot_id,
      legacy_snapshot_id,
      'contact_sessions_by_channel_two_periods',
      1,
      'management-report:contact_sessions_by_channel_two_periods:v1',
      transaction_timestamp(),
      'completed',
      NULL
    );
    RAISE EXCEPTION 'legacy snapshot forged a completed access event';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.management_report_snapshot_access_events
    SET reason_code = 'snapshot_not_available'
    WHERE access_event_id = (first_read->>'access_event_id')::uuid;
    RAISE EXCEPTION 'snapshot access history update was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_report_snapshot_access_events
    WHERE access_event_id = (first_read->>'access_event_id')::uuid;
    RAISE EXCEPTION 'snapshot access history delete was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
