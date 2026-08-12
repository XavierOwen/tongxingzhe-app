\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('7d100000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('7d100000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('7d100000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    '7de00000-0000-4000-8000-000000000001'::uuid,
    'https://snapshot-directory.synthetic/auth/v1',
    'view-member',
    '7d100000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '7de00000-0000-4000-8000-000000000002'::uuid,
    'https://snapshot-directory.synthetic/auth/v1',
    'release-only-member',
    '7d100000-0000-4000-8000-000000000003'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  '7d200000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic snapshot directory organization',
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
    '7d300000-0000-4000-8000-000000000001'::uuid,
    '7d200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic snapshot directory project',
    'active',
    false
  ),
  (
    '7d300000-0000-4000-8000-000000000002'::uuid,
    '7d200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic empty directory project',
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
  '7d700000-0000-4000-8000-000000000001'::uuid,
  '7d300000-0000-4000-8000-000000000001'::uuid,
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
  'snapshot-directory-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '7d100000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '7d100000-0000-4000-8000-000000000002'::uuid
    ELSE '7d100000-0000-4000-8000-000000000003'::uuid
  END,
  '7d200000-0000-4000-8000-000000000001'::uuid,
  '7d300000-0000-4000-8000-000000000001'::uuid,
  '7d700000-0000-4000-8000-000000000001'::uuid,
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
    '7d400000-0000-4000-8000-000000000001'::uuid,
    '7d200000-0000-4000-8000-000000000001'::uuid,
    '7d100000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d400000-0000-4000-8000-000000000002'::uuid,
    '7d200000-0000-4000-8000-000000000001'::uuid,
    '7d100000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d400000-0000-4000-8000-000000000003'::uuid,
    '7d200000-0000-4000-8000-000000000001'::uuid,
    '7d100000-0000-4000-8000-000000000003'::uuid,
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
    '7d500000-0000-4000-8000-000000000001'::uuid,
    '7d400000-0000-4000-8000-000000000001'::uuid,
    '7d300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d500000-0000-4000-8000-000000000002'::uuid,
    '7d400000-0000-4000-8000-000000000002'::uuid,
    '7d300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d500000-0000-4000-8000-000000000003'::uuid,
    '7d400000-0000-4000-8000-000000000003'::uuid,
    '7d300000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d500000-0000-4000-8000-000000000004'::uuid,
    '7d400000-0000-4000-8000-000000000002'::uuid,
    '7d300000-0000-4000-8000-000000000002'::uuid,
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
    '7d600000-0000-4000-8000-000000000001'::uuid,
    '7d500000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d600000-0000-4000-8000-000000000002'::uuid,
    '7d500000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d600000-0000-4000-8000-000000000003'::uuid,
    '7d500000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '7d600000-0000-4000-8000-000000000004'::uuid,
    '7d500000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  );

DO $setup$
DECLARE
  release_result jsonb;
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '7d900000-0000-4000-8000-000000000001'::uuid,
    '7d100000-0000-4000-8000-000000000001'::uuid,
    '7d300000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );

  FOR release_number IN 1..21 LOOP
    release_result = app_private.release_management_report_snapshot_v2(
      ('7d800000-0000-4000-8000-'
        || lpad(release_number::text, 12, '0'))::uuid,
      '7d100000-0000-4000-8000-000000000001'::uuid,
      '7d300000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1
    );
    IF release_result->>'result_status' NOT IN (
      'approved_baseline',
      'approved'
    ) OR release_result->>'released_snapshot_id' IS NULL THEN
      RAISE EXCEPTION 'trusted directory setup release was not approved';
    END IF;
    PERFORM pg_sleep(0.005);
  END LOOP;
END
$setup$;

DO $fixture$
DECLARE
  directory_result jsonb;
  empty_result jsonb;
  legacy_cutoff timestamp with time zone;
  legacy_snapshot_id uuid;
  oldest_v2_snapshot_id uuid;
  audit_event_id uuid;
  before_app_users bigint;
  before_workspaces bigint;
  before_projects bigint;
BEGIN
  SELECT max(attempt.data_cutoff_utc) + interval '1 second'
    INTO STRICT legacy_cutoff
  FROM app_private.management_report_release_v2_attempts AS attempt
  WHERE attempt.project_id =
    '7d300000-0000-4000-8000-000000000001'::uuid;
  PERFORM app_private.release_management_report_snapshot_v1(
    '7d800000-0000-4000-8000-000000000099'::uuid,
    '7d100000-0000-4000-8000-000000000001'::uuid,
    '7d300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    legacy_cutoff,
    legacy_cutoff
  );
  SELECT attempt.released_snapshot_id INTO STRICT legacy_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '7d800000-0000-4000-8000-000000000099'::uuid;

  directory_result =
    app_data.list_authorized_management_report_snapshots_v1(
      'https://snapshot-directory.synthetic/auth/v1',
      'view-member',
      '7d300000-0000-4000-8000-000000000001'::uuid
    );
  IF directory_result->>'access_contract_id' <>
      'authorized_management_report_snapshot_directory_v1'
    OR (directory_result->>'project_id')::uuid <>
      '7d300000-0000-4000-8000-000000000001'::uuid
    OR jsonb_array_length(directory_result->'snapshots') <> 20
    OR directory_result::text ~
      'protected_report|cells|contributor|membership|capability|subject'
  THEN
    RAISE EXCEPTION 'authorized snapshot directory contract is invalid';
  END IF;

  SELECT attempt.released_snapshot_id INTO STRICT oldest_v2_snapshot_id
  FROM app_private.management_report_release_v2_attempts AS attempt
  WHERE attempt.project_id =
      '7d300000-0000-4000-8000-000000000001'::uuid
    AND attempt.released_snapshot_id IS NOT NULL
  ORDER BY
    attempt.data_cutoff_utc,
    attempt.released_snapshot_id
  LIMIT 1;
  IF directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', oldest_v2_snapshot_id
      ))
    OR directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object('snapshot_id', legacy_snapshot_id))
  THEN
    RAISE EXCEPTION 'snapshot directory limit or provenance filter failed';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(directory_result->'snapshots')
      WITH ORDINALITY AS item(document, position)
    JOIN jsonb_array_elements(directory_result->'snapshots')
      WITH ORDINALITY AS previous(document, position)
      ON previous.position + 1 = item.position
    WHERE ROW(
      (previous.document->>'data_cutoff_utc')::timestamptz,
      (previous.document->>'released_at_utc')::timestamptz,
      (previous.document->>'snapshot_id')::uuid
    ) < ROW(
      (item.document->>'data_cutoff_utc')::timestamptz,
      (item.document->>'released_at_utc')::timestamptz,
      (item.document->>'snapshot_id')::uuid
    )
  ) THEN
    RAISE EXCEPTION 'snapshot directory order is unstable';
  END IF;

  audit_event_id = (directory_result->>'access_event_id')::uuid;
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshot_directory_access_events
      AS event
    WHERE event.access_event_id = audit_event_id
      AND event.requested_by_app_user_id =
        '7d100000-0000-4000-8000-000000000002'::uuid
      AND event.capability_grant_id =
        '7d600000-0000-4000-8000-000000000002'::uuid
      AND event.returned_snapshot_count = 20
      AND event.result_status = 'completed'
  ) THEN
    RAISE EXCEPTION 'snapshot directory audit is incomplete';
  END IF;

  empty_result = app_data.list_authorized_management_report_snapshots_v1(
    'https://snapshot-directory.synthetic/auth/v1',
    'view-member',
    '7d300000-0000-4000-8000-000000000002'::uuid
  );
  IF empty_result->'snapshots' <> '[]'::jsonb OR NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshot_directory_access_events
      AS event
    WHERE event.access_event_id =
        (empty_result->>'access_event_id')::uuid
      AND event.returned_snapshot_count = 0
  ) THEN
    RAISE EXCEPTION 'empty snapshot directory was not audited';
  END IF;

  SELECT count(*) INTO before_app_users FROM app_data.app_users;
  SELECT count(*) INTO before_workspaces FROM app_data.workspaces;
  SELECT count(*) INTO before_projects FROM app_data.projects;
  BEGIN
    PERFORM app_data.list_authorized_management_report_snapshots_v1(
      'https://snapshot-directory.synthetic/auth/v1',
      'unknown-member',
      '7d300000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'unknown identity read a snapshot directory';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
  IF before_app_users <> (SELECT count(*) FROM app_data.app_users)
    OR before_workspaces <> (SELECT count(*) FROM app_data.workspaces)
    OR before_projects <> (SELECT count(*) FROM app_data.projects)
  THEN
    RAISE EXCEPTION 'unknown directory identity bootstrapped personal data';
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_report_snapshots_v1(
      'https://snapshot-directory.synthetic/auth/v1',
      'release-only-member',
      '7d300000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION 'release-only member read a snapshot directory';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    UPDATE app_private.management_report_snapshot_directory_access_events
    SET returned_snapshot_count = 0
    WHERE access_event_id = audit_event_id;
    RAISE EXCEPTION 'snapshot directory audit accepted UPDATE';
  EXCEPTION
    WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    DELETE FROM
      app_private.management_report_snapshot_directory_access_events
    WHERE access_event_id = audit_event_id;
    RAISE EXCEPTION 'snapshot directory audit accepted DELETE';
  EXCEPTION
    WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END
$fixture$;

ROLLBACK;
