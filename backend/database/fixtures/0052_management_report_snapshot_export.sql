\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('8a100000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('8a100000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('8a100000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('8a100000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('8a100000-0000-4000-8000-000000000005'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    '8ae00000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-report-export.synthetic/auth/v1',
    'full-export-member',
    '8a100000-0000-4000-8000-000000000001'::uuid
  ),
  (
    '8ae00000-0000-4000-8000-000000000002'::uuid,
    'https://runtime-report-export.synthetic/auth/v1',
    'view-only-member',
    '8a100000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '8ae00000-0000-4000-8000-000000000003'::uuid,
    'https://runtime-report-export.synthetic/auth/v1',
    'export-only-member',
    '8a100000-0000-4000-8000-000000000003'::uuid
  ),
  (
    '8ae00000-0000-4000-8000-000000000004'::uuid,
    'https://runtime-report-export.synthetic/auth/v1',
    'release-only-member',
    '8a100000-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES (
  '8a200000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic report export workspace',
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
    '8a300000-0000-4000-8000-000000000001'::uuid,
    '8a200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic report export project',
    'active',
    false
  ),
  (
    '8a300000-0000-4000-8000-000000000002'::uuid,
    '8a200000-0000-4000-8000-000000000001'::uuid,
    'Synthetic other export project',
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
  '8a700000-0000-4000-8000-000000000001'::uuid,
  '8a300000-0000-4000-8000-000000000001'::uuid,
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
  'report-export-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '8a100000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '8a100000-0000-4000-8000-000000000002'::uuid
    ELSE '8a100000-0000-4000-8000-000000000004'::uuid
  END,
  '8a200000-0000-4000-8000-000000000001'::uuid,
  '8a300000-0000-4000-8000-000000000001'::uuid,
  '8a700000-0000-4000-8000-000000000001'::uuid,
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
)
SELECT
  ('8a400000-0000-4000-8000-' || lpad(series_row::text, 12, '0'))::uuid,
  '8a200000-0000-4000-8000-000000000001'::uuid,
  ('8a100000-0000-4000-8000-' || lpad(series_row::text, 12, '0'))::uuid,
  transaction_timestamp() - interval '60 days',
  NULL
FROM generate_series(1, 5) AS series_row;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  ('8a500000-0000-4000-8000-' || lpad(series_row::text, 12, '0'))::uuid,
  ('8a400000-0000-4000-8000-' || lpad(series_row::text, 12, '0'))::uuid,
  '8a300000-0000-4000-8000-000000000001'::uuid,
  transaction_timestamp() - interval '60 days',
  NULL
FROM generate_series(1, 5) AS series_row;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '8a500000-0000-4000-8000-000000000006'::uuid,
  '8a400000-0000-4000-8000-000000000001'::uuid,
  '8a300000-0000-4000-8000-000000000002'::uuid,
  transaction_timestamp() - interval '60 days',
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
    '8a600000-0000-4000-8000-000000000001'::uuid,
    '8a500000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000002'::uuid,
    '8a500000-0000-4000-8000-000000000001'::uuid,
    'export_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000003'::uuid,
    '8a500000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000004'::uuid,
    '8a500000-0000-4000-8000-000000000003'::uuid,
    'export_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000005'::uuid,
    '8a500000-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000006'::uuid,
    '8a500000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000007'::uuid,
    '8a500000-0000-4000-8000-000000000005'::uuid,
    'export_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000008'::uuid,
    '8a500000-0000-4000-8000-000000000006'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '60 days',
    NULL
  ),
  (
    '8a600000-0000-4000-8000-000000000009'::uuid,
    '8a500000-0000-4000-8000-000000000006'::uuid,
    'export_management_reports',
    transaction_timestamp() - interval '60 days',
    NULL
  );

DO $setup$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '8a900000-0000-4000-8000-000000000001'::uuid,
    '8a100000-0000-4000-8000-000000000004'::uuid,
    '8a300000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );

  PERFORM app_private.release_management_report_snapshot_v2(
    '8a800000-0000-4000-8000-000000000001'::uuid,
    '8a100000-0000-4000-8000-000000000004'::uuid,
    '8a300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
END
$setup$;

SELECT released_snapshot_id AS trusted_snapshot_id
FROM app_private.management_report_release_v2_attempts
WHERE release_request_id =
  '8a800000-0000-4000-8000-000000000001'::uuid
\gset

SET LOCAL ROLE tongxingzhe_runtime;
SELECT app_data.export_authorized_management_report_snapshot_v1(
  'https://runtime-report-export.synthetic/auth/v1',
  'full-export-member',
  '8a300000-0000-4000-8000-000000000001'::uuid,
  :'trusted_snapshot_id'::uuid
);
RESET ROLE;

DO $fixture$
DECLARE
  trusted_snapshot_id uuid;
  trusted_report jsonb;
  first_export jsonb;
  repeated_export jsonb;
  unavailable_export jsonb;
  cross_project_export jsonb;
  view_only_export jsonb;
  export_only_export jsonb;
  release_only_export jsonb;
  legacy_snapshot_id uuid;
  legacy_export jsonb;
  legacy_cutoff timestamp with time zone;
  before_app_users bigint;
  before_workspaces bigint;
  before_projects bigint;
  before_read_events bigint;
  first_event_id uuid;
  second_event_id uuid;
  export_document_keys text[];
  common_keys text[] := ARRAY[
    'export_access_contract_id',
    'export_event_id',
    'requested_snapshot_id',
    'resolved_snapshot_id',
    'result_status',
    'reason_code'
  ];
BEGIN
  SELECT count(*) INTO before_read_events
  FROM app_private.management_report_snapshot_access_events;

  SELECT
    attempt.released_snapshot_id,
    attempt.data_cutoff_utc
    INTO STRICT trusted_snapshot_id, legacy_cutoff
  FROM app_private.management_report_release_v2_attempts AS attempt
  WHERE attempt.release_request_id =
    '8a800000-0000-4000-8000-000000000001'::uuid;

  SELECT snapshot.protected_report INTO STRICT trusted_report
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = trusted_snapshot_id;

  first_export = app_data.export_authorized_management_report_snapshot_v1(
    'https://runtime-report-export.synthetic/auth/v1',
    'full-export-member',
    '8a300000-0000-4000-8000-000000000001'::uuid,
    trusted_snapshot_id
  );
  repeated_export = app_data.export_authorized_management_report_snapshot_v1(
    'https://runtime-report-export.synthetic/auth/v1',
    'full-export-member',
    '8a300000-0000-4000-8000-000000000001'::uuid,
    trusted_snapshot_id
  );

  IF first_export->>'export_access_contract_id' <>
      'authorized_management_report_snapshot_export_v1'
    OR first_export->>'result_status' <> 'completed'
    OR first_export->>'reason_code' IS NOT NULL
    OR (first_export->>'resolved_snapshot_id')::uuid <> trusted_snapshot_id
    OR NOT (first_export ?& common_keys)
    OR NOT (first_export ? 'export_document')
    OR (SELECT count(*) FROM jsonb_object_keys(first_export)) <> 7
  THEN
    RAISE EXCEPTION 'runtime bridge did not return the exact completed export result';
  END IF;

  export_document_keys = ARRAY(
    SELECT key
    FROM jsonb_object_keys(first_export->'export_document') AS key
    ORDER BY key
  );
  IF export_document_keys <> ARRAY[
    'export_contract_id', 'released_at_utc', 'report', 'snapshot_id'
  ]
    OR first_export->'export_document'->>'export_contract_id' <>
      'management_report_snapshot_export_v1'
    OR (first_export->'export_document'->>'snapshot_id')::uuid <> trusted_snapshot_id
    OR first_export->'export_document'->'report' <> trusted_report
    OR first_export->'export_document'->>'released_at_utc' IS NULL
  THEN
    RAISE EXCEPTION 'canonical export document is not a fixed protected snapshot';
  END IF;

  IF (first_export->'export_document')::text LIKE '%location%'
    OR (first_export->'export_document')::text LIKE '%app_user%'
    OR (first_export->'export_document')::text LIKE '%contributor%'
  THEN
    RAISE EXCEPTION 'canonical export document leaked forbidden source details';
  END IF;

  IF (SELECT count(*) FROM jsonb_array_elements(
      first_export->'export_document'->'report'->'cells'
    ) AS cell) <> 16
  OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      first_export->'export_document'->'report'->'cells'
    ) AS cell
    WHERE cell->>'privacy_status' = 'suppressed'
      AND cell->'value_count' <> 'null'::jsonb
  )
  THEN
    RAISE EXCEPTION 'export did not preserve the 16-cell suppressed null grid';
  END IF;

  first_event_id = (first_export->>'export_event_id')::uuid;
  second_event_id = (repeated_export->>'export_event_id')::uuid;
  IF first_event_id = second_event_id
    OR repeated_export->'export_document' <> first_export->'export_document'
  THEN
    RAISE EXCEPTION 'repeating one snapshot did not create a stable fresh export event';
  END IF;

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
    'report-export-post-release-contact',
    '8a100000-0000-4000-8000-000000000001'::uuid,
    '8a200000-0000-4000-8000-000000000001'::uuid,
    '8a300000-0000-4000-8000-000000000001'::uuid,
    '8a700000-0000-4000-8000-000000000001'::uuid,
    legacy_cutoff + interval '2 days',
    'UTC',
    legacy_cutoff + interval '2 days',
    'voice_call',
    'not_applicable',
    1,
    2
  );

  IF app_data.export_authorized_management_report_snapshot_v1(
      'https://runtime-report-export.synthetic/auth/v1',
      'full-export-member',
      '8a300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    )->'export_document' <> first_export->'export_document'
  THEN
    RAISE EXCEPTION 'export re-ran a dynamic report after snapshot release';
  END IF;

  unavailable_export = app_data.export_authorized_management_report_snapshot_v1(
    'https://runtime-report-export.synthetic/auth/v1',
    'full-export-member',
    '8a300000-0000-4000-8000-000000000001'::uuid,
    '8aa00000-0000-4000-8000-000000000001'::uuid
  );
  cross_project_export = app_data.export_authorized_management_report_snapshot_v1(
    'https://runtime-report-export.synthetic/auth/v1',
    'full-export-member',
    '8a300000-0000-4000-8000-000000000002'::uuid,
    trusted_snapshot_id
  );
  IF unavailable_export->>'result_status' <> 'not_found'
    OR cross_project_export->>'result_status' <> 'not_found'
    OR unavailable_export->>'reason_code' <> 'snapshot_not_available'
    OR cross_project_export->>'reason_code' <> 'snapshot_not_available'
    OR (SELECT count(*) FROM jsonb_object_keys(unavailable_export)) <> 6
    OR unavailable_export ? 'export_document'
    OR cross_project_export ? 'export_document'
  THEN
    RAISE EXCEPTION 'missing or cross-project export was not safely hidden';
  END IF;

  legacy_cutoff = legacy_cutoff + interval '1 second';
  PERFORM app_private.release_management_report_snapshot_v1(
    '8a800000-0000-4000-8000-000000000002'::uuid,
    '8a100000-0000-4000-8000-000000000004'::uuid,
    '8a300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    legacy_cutoff,
    legacy_cutoff
  );
  SELECT attempt.released_snapshot_id INTO STRICT legacy_snapshot_id
  FROM app_private.management_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '8a800000-0000-4000-8000-000000000002'::uuid;

  legacy_export = app_data.export_authorized_management_report_snapshot_v1(
    'https://runtime-report-export.synthetic/auth/v1',
    'full-export-member',
    '8a300000-0000-4000-8000-000000000001'::uuid,
    legacy_snapshot_id
  );
  IF legacy_export->>'result_status' <> 'untrusted_provenance'
    OR legacy_export->>'reason_code' <> 'snapshot_provenance_untrusted'
    OR (SELECT count(*) FROM jsonb_object_keys(legacy_export)) <> 6
    OR legacy_export ? 'export_document'
  THEN
    RAISE EXCEPTION 'untrusted snapshot export was not withheld';
  END IF;

  BEGIN
    view_only_export = app_data.export_authorized_management_report_snapshot_v1(
      'https://runtime-report-export.synthetic/auth/v1',
      'view-only-member',
      '8a300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'view-only member unexpectedly exported: %', view_only_export;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF before_read_events <> (
    SELECT count(*)
    FROM app_private.management_report_snapshot_access_events
  ) THEN
    RAISE EXCEPTION 'snapshot export was recorded as an ordinary read';
  END IF;
END
$fixture$;

DO $authorization$
DECLARE
  trusted_snapshot_id uuid;
  before_events bigint;
  before_app_users bigint;
  before_workspaces bigint;
  before_projects bigint;
BEGIN
  SELECT released_snapshot_id INTO STRICT trusted_snapshot_id
  FROM app_private.management_report_release_v2_attempts
  WHERE release_request_id =
    '8a800000-0000-4000-8000-000000000001'::uuid;

  SELECT count(*) INTO before_events
  FROM app_private.management_report_snapshot_export_events;

  BEGIN
    PERFORM app_data.export_authorized_management_report_snapshot_v1(
      'https://runtime-report-export.synthetic/auth/v1',
      'export-only-member',
      '8a300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'export-only member unexpectedly exported';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.export_authorized_management_report_snapshot_v1(
      'https://runtime-report-export.synthetic/auth/v1',
      'release-only-member',
      '8a300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'release-only member unexpectedly exported';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  SELECT count(*) INTO before_app_users FROM app_data.app_users;
  SELECT count(*) INTO before_workspaces FROM app_data.workspaces;
  SELECT count(*) INTO before_projects FROM app_data.projects;
  BEGIN
    PERFORM app_data.export_authorized_management_report_snapshot_v1(
      'https://runtime-report-export.synthetic/auth/v1',
      'unknown-member',
      '8a300000-0000-4000-8000-000000000001'::uuid,
      trusted_snapshot_id
    );
    RAISE EXCEPTION 'unknown member unexpectedly exported';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  IF before_events <> (
      SELECT count(*) FROM app_private.management_report_snapshot_export_events
    )
    OR before_app_users <> (SELECT count(*) FROM app_data.app_users)
    OR before_workspaces <> (SELECT count(*) FROM app_data.workspaces)
    OR before_projects <> (SELECT count(*) FROM app_data.projects)
  THEN
    RAISE EXCEPTION 'failed export attempts changed audit or identity state';
  END IF;

  BEGIN
    UPDATE app_private.management_report_snapshot_export_events
    SET result_status = result_status
    WHERE export_event_id = (
      SELECT export_event_id
      FROM app_private.management_report_snapshot_export_events
      ORDER BY requested_at_utc
      LIMIT 1
    );
    RAISE EXCEPTION 'export audit accepted an update';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_report_snapshot_export_events
    WHERE export_event_id = (
      SELECT export_event_id
      FROM app_private.management_report_snapshot_export_events
      ORDER BY requested_at_utc
      LIMIT 1
    );
    RAISE EXCEPTION 'export audit accepted a delete';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END
$authorization$;

ROLLBACK;
