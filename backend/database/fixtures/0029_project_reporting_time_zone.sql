\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id)
VALUES
  ('96000000-0000-4000-8000-000000000001'::uuid),
  ('96000000-0000-4000-8000-000000000002'::uuid),
  ('96000000-0000-4000-8000-000000000003'::uuid);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
) VALUES
  (
    '97000000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Synthetic reporting time zone workspace',
    NULL,
    NULL
  ),
  (
    '97000000-0000-4000-8000-000000000002'::uuid,
    'personal',
    'Synthetic personal workspace',
    '96000000-0000-4000-8000-000000000001'::uuid,
    NULL
  ),
  (
    '97000000-0000-4000-8000-000000000003'::uuid,
    'organization',
    'Synthetic deleted workspace',
    NULL,
    '2026-03-01 00:00:00+00'::timestamptz
  );

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status
) VALUES
  (
    '98000000-0000-4000-8000-000000000001'::uuid,
    '97000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic reporting time zone project',
    'active'
  ),
  (
    '98000000-0000-4000-8000-000000000002'::uuid,
    '97000000-0000-4000-8000-000000000002'::uuid,
    'Synthetic personal project',
    'active'
  ),
  (
    '98000000-0000-4000-8000-000000000003'::uuid,
    '97000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic archived project',
    'archived'
  ),
  (
    '98000000-0000-4000-8000-000000000004'::uuid,
    '97000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic unconfigured project',
    'active'
  ),
  (
    '98000000-0000-4000-8000-000000000005'::uuid,
    '97000000-0000-4000-8000-000000000003'::uuid,
    'Synthetic deleted workspace project',
    'active'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  '9b000000-0000-4000-8000-000000000001'::uuid,
  '98000000-0000-4000-8000-000000000001'::uuid,
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
  'timezone-snapshot-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '96000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '96000000-0000-4000-8000-000000000002'::uuid
    ELSE '96000000-0000-4000-8000-000000000003'::uuid
  END,
  '97000000-0000-4000-8000-000000000001'::uuid,
  '98000000-0000-4000-8000-000000000001'::uuid,
  '9b000000-0000-4000-8000-000000000001'::uuid,
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  VALUES
    ('week_a'::text, '2026-02-18 12:00:00+00'::timestamptz),
    ('week_b'::text, '2026-02-25 12:00:00+00'::timestamptz)
) AS period_row(period_key, occurred_at_utc)
CROSS JOIN generate_series(1, 10) AS series_row;

DO $fixture$
DECLARE
  configuration jsonb;
  replay_configuration jsonb;
  second_configuration jsonb;
  state_document jsonb;
  release_result jsonb;
  snapshot_before jsonb;
  snapshot_after jsonb;
  released_snapshot_id uuid;
  snapshot_count_before integer;
BEGIN
  release_result = app_private.release_management_report_snapshot_v1(
    '9c000000-0000-4000-8000-000000000001'::uuid,
    '96000000-0000-4000-8000-000000000001'::uuid,
    '98000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-03-04 12:00:00+00'::timestamptz,
    '2026-03-04 12:01:00+00'::timestamptz
  );
  IF release_result->>'result_status' <> 'approved_baseline' THEN
    RAISE EXCEPTION 'pre-configuration 6G snapshot was not released';
  END IF;

  released_snapshot_id = (release_result->>'released_snapshot_id')::uuid;
  SELECT to_jsonb(snapshot_row.*) INTO snapshot_before
  FROM app_private.management_report_snapshots AS snapshot_row
  WHERE snapshot_row.snapshot_id = released_snapshot_id;
  SELECT count(*) INTO snapshot_count_before
  FROM app_private.management_report_snapshots AS snapshot_row
  WHERE snapshot_row.project_id =
    '98000000-0000-4000-8000-000000000001'::uuid;

  configuration = app_private.configure_project_reporting_time_zone_v1(
    '99000000-0000-4000-8000-000000000001'::uuid,
    '96000000-0000-4000-8000-000000000001'::uuid,
    '98000000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    '2026-03-04 12:00:00+00'::timestamptz
  );

  IF configuration->>'configuration_contract_id'
      <> 'project_reporting_time_zone_configuration_v1'
    OR configuration->>'version_number' <> '1'
    OR configuration->>'reporting_time_zone' <> 'UTC'
    OR configuration->>'effective_from_utc'
      <> '2026-03-04T12:00:00.000Z'
  THEN
    RAISE EXCEPTION 'initial reporting time zone was not accepted';
  END IF;

  state_document = app_private.read_project_reporting_time_zone_v1(
    '98000000-0000-4000-8000-000000000001'::uuid,
    '2026-03-04 12:00:00+00'::timestamptz
  );

  IF state_document->>'state_contract_id'
      <> 'project_reporting_time_zone_state_v1'
    OR state_document->'current'->>'version_number' <> '1'
    OR state_document->'current'->>'reporting_time_zone' <> 'UTC'
    OR state_document->'pending' <> 'null'::jsonb
  THEN
    RAISE EXCEPTION 'initial reporting time zone was not readable';
  END IF;

  second_configuration =
    app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000002'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      1,
      'America/Chicago',
      '2026-03-04 18:00:00+00'::timestamptz
    );

  IF second_configuration->>'version_number' <> '2'
    OR second_configuration->>'reporting_time_zone'
      <> 'America/Chicago'
    OR second_configuration->>'effective_from_utc'
      <> '2026-03-09T00:00:00.000Z'
    OR second_configuration->>'period_boundary_id'
      <> 'iso_week_monday_v1'
  THEN
    RAISE EXCEPTION 'reporting time zone did not use the old UTC boundary';
  END IF;

  replay_configuration =
    app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000002'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      1,
      'America/Chicago',
      '2026-03-06 09:00:00+00'::timestamptz
    );

  IF replay_configuration <> second_configuration
    OR (
      SELECT count(*)
      FROM app_private.project_reporting_time_zone_versions
      WHERE project_id =
        '98000000-0000-4000-8000-000000000001'::uuid
    ) <> 2
  THEN
    RAISE EXCEPTION 'reporting time zone retry was not idempotent';
  END IF;

  state_document = app_private.read_project_reporting_time_zone_v1(
    '98000000-0000-4000-8000-000000000001'::uuid,
    '2026-03-08 23:59:59.999999+00'::timestamptz
  );
  IF state_document->'current'->>'reporting_time_zone' <> 'UTC'
    OR state_document->'pending'->>'reporting_time_zone'
      <> 'America/Chicago'
  THEN
    RAISE EXCEPTION 'pending reporting time zone replaced the current version';
  END IF;

  state_document = app_private.read_project_reporting_time_zone_v1(
    '98000000-0000-4000-8000-000000000001'::uuid,
    '2026-03-09 00:00:00+00'::timestamptz
  );
  IF state_document->'current'->>'reporting_time_zone'
      <> 'America/Chicago'
    OR state_document->'pending' <> 'null'::jsonb
  THEN
    RAISE EXCEPTION 'reporting time zone did not switch at its boundary';
  END IF;

  configuration = app_private.configure_project_reporting_time_zone_v1(
    '99000000-0000-4000-8000-000000000003'::uuid,
    '96000000-0000-4000-8000-000000000001'::uuid,
    '98000000-0000-4000-8000-000000000001'::uuid,
    2,
    'Asia/Shanghai',
    '2026-03-11 12:00:00+00'::timestamptz
  );
  IF configuration->>'effective_from_utc'
      <> '2026-03-16T05:00:00.000Z'
  THEN
    RAISE EXCEPTION 'old Chicago boundary did not govern the next change';
  END IF;

  IF app_private.project_reporting_time_zone_change_boundary_v1(
      '2026-10-28 12:00:00+00'::timestamptz,
      'America/Chicago'
    ) <> '2026-11-02 06:00:00+00'::timestamptz
  THEN
    RAISE EXCEPTION 'fall DST reporting boundary used a fixed duration';
  END IF;

  IF app_private.project_reporting_time_zone_change_boundary_v1(
      '2026-03-16 05:00:00+00'::timestamptz,
      'America/Chicago'
    ) <> '2026-03-23 05:00:00+00'::timestamptz
  THEN
    RAISE EXCEPTION 'an exact old-zone boundary did not advance one week';
  END IF;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000004'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      3,
      'UTC',
      '2026-03-12 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a second pending reporting time zone was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000005'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      3,
      'Asia/Shanghai',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'an unchanged reporting time zone was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000006'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      3,
      'UTC',
      '2026-03-10 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'an out-of-order reporting time zone was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000007'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      2,
      'UTC',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a stale reporting time zone version was accepted';
  EXCEPTION WHEN serialization_failure THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000008'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      3,
      'CST',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a time zone abbreviation was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000009'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000002'::uuid,
      0,
      'UTC',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a personal project accepted a management report zone';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000010'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000003'::uuid,
      0,
      'UTC',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'an archived project accepted a reporting time zone';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000011'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000005'::uuid,
      0,
      'UTC',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a deleted workspace accepted a reporting time zone';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_project_reporting_time_zone_v1(
      '98000000-0000-4000-8000-000000000004'::uuid,
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'an unconfigured project fell back to a time zone';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.configure_project_reporting_time_zone_v1(
      '99000000-0000-4000-8000-000000000002'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      '98000000-0000-4000-8000-000000000001'::uuid,
      2,
      'America/Chicago',
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a changed idempotency payload was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.project_reporting_time_zone_versions
    SET reporting_time_zone = 'UTC'
    WHERE project_id =
      '98000000-0000-4000-8000-000000000001'::uuid
      AND version_number = 2;
    RAISE EXCEPTION 'reporting time zone history was updated';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.project_reporting_time_zone_versions
    WHERE project_id =
      '98000000-0000-4000-8000-000000000001'::uuid
      AND version_number = 2;
    RAISE EXCEPTION 'reporting time zone history was deleted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_private.project_reporting_time_zone_versions (
      project_id,
      version_number,
      expected_version,
      change_request_id,
      requested_by_app_user_id,
      reporting_time_zone,
      period_boundary_id,
      effective_from_utc,
      requested_at_utc
    ) VALUES (
      '98000000-0000-4000-8000-000000000001'::uuid,
      4,
      3,
      '99000000-0000-4000-8000-000000000012'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      'CST',
      'iso_week_monday_v1',
      '2026-03-23 00:00:00+00'::timestamptz,
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a direct invalid reporting zone insert succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_private.project_reporting_time_zone_versions (
      project_id,
      version_number,
      expected_version,
      change_request_id,
      requested_by_app_user_id,
      reporting_time_zone,
      period_boundary_id,
      effective_from_utc,
      requested_at_utc
    ) VALUES (
      '98000000-0000-4000-8000-000000000001'::uuid,
      4,
      3,
      '99000000-0000-4000-8000-000000000013'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      'iso_week_monday_v1',
      '2026-03-23 00:00:00+00'::timestamptz,
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a direct forged effective boundary succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_private.project_reporting_time_zone_versions (
      project_id,
      version_number,
      expected_version,
      change_request_id,
      requested_by_app_user_id,
      reporting_time_zone,
      period_boundary_id,
      effective_from_utc,
      requested_at_utc
    ) VALUES (
      '98000000-0000-4000-8000-000000000001'::uuid,
      5,
      3,
      '99000000-0000-4000-8000-000000000014'::uuid,
      '96000000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      'iso_week_monday_v1',
      '2026-03-22 16:00:00+00'::timestamptz,
      '2026-03-17 12:00:00+00'::timestamptz
    );
    RAISE EXCEPTION 'a direct forged revision succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SELECT to_jsonb(snapshot_row.*) INTO snapshot_after
  FROM app_private.management_report_snapshots AS snapshot_row
  WHERE snapshot_row.snapshot_id = released_snapshot_id;
  IF snapshot_after <> snapshot_before
    OR (
      SELECT count(*)
      FROM app_private.management_report_snapshots AS snapshot_row
      WHERE snapshot_row.project_id =
        '98000000-0000-4000-8000-000000000001'::uuid
    ) <> snapshot_count_before
  THEN
    RAISE EXCEPTION 'reporting time zone history changed an existing 6G snapshot';
  END IF;
END
$fixture$;

ROLLBACK;
