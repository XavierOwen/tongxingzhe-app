\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id)
VALUES
  ('81000000-0000-4000-8000-000000000001'::uuid),
  ('81000000-0000-4000-8000-000000000002'::uuid),
  ('81000000-0000-4000-8000-000000000003'::uuid);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name
) VALUES (
  '82000000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic report snapshot workspace'
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name
) VALUES (
  '83000000-0000-4000-8000-000000000001'::uuid,
  '82000000-0000-4000-8000-000000000001'::uuid,
  'Synthetic report snapshot project'
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  '84000000-0000-4000-8000-000000000001'::uuid,
  '83000000-0000-4000-8000-000000000001'::uuid,
  1,
  'published',
  true
);

-- Four complete weeks provide a baseline, a stable rolling release, and a
-- later overlapping report whose historical week changes after late entry.
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
  'snapshot-voice-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '81000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '81000000-0000-4000-8000-000000000002'::uuid
    ELSE '81000000-0000-4000-8000-000000000003'::uuid
  END,
  '82000000-0000-4000-8000-000000000001'::uuid,
  '83000000-0000-4000-8000-000000000001'::uuid,
  '84000000-0000-4000-8000-000000000001'::uuid,
  period_row.occurred_at_utc,
  'UTC',
  period_row.first_submitted_at_utc,
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  VALUES
    (
      'week_a'::text,
      '2026-06-03 12:00:00+00'::timestamptz,
      '2026-06-03 13:00:00+00'::timestamptz
    ),
    (
      'week_b'::text,
      '2026-06-10 12:00:00+00'::timestamptz,
      '2026-06-10 13:00:00+00'::timestamptz
    ),
    (
      'week_c'::text,
      '2026-06-17 12:00:00+00'::timestamptz,
      '2026-06-17 13:00:00+00'::timestamptz
    ),
    (
      'week_d'::text,
      '2026-06-24 12:00:00+00'::timestamptz,
      '2026-06-24 13:00:00+00'::timestamptz
    )
) AS period_row(period_key, occurred_at_utc, first_submitted_at_utc)
CROSS JOIN generate_series(1, 10) AS series_row;

-- The stable snapshot contains a suppressed face-to-face cell in week C.
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
  place_name,
  smallest_region_id,
  reach_count,
  interest_level
)
SELECT
  'snapshot-face-week-c-' || series_row::text,
  CASE
    WHEN series_row <= 4
      THEN '81000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 7
      THEN '81000000-0000-4000-8000-000000000002'::uuid
    ELSE '81000000-0000-4000-8000-000000000003'::uuid
  END,
  '82000000-0000-4000-8000-000000000001'::uuid,
  '83000000-0000-4000-8000-000000000001'::uuid,
  '84000000-0000-4000-8000-000000000001'::uuid,
  '2026-06-18 12:00:00+00'::timestamptz,
  'UTC',
  '2026-06-18 13:00:00+00'::timestamptz,
  'face_to_face',
  'resolved',
  'Synthetic plaza',
  'synthetic-region',
  1,
  2
FROM generate_series(1, 9) AS series_row;

INSERT INTO app_data.change_feed (
  app_user_id,
  workspace_id,
  project_id,
  aggregate_id,
  revision_number,
  change_type,
  created_at_utc
) VALUES (
  '81000000-0000-4000-8000-000000000001'::uuid,
  '82000000-0000-4000-8000-000000000001'::uuid,
  '83000000-0000-4000-8000-000000000001'::uuid,
  'snapshot-voice-week-a-1',
  1,
  'contact.submitted',
  '2026-06-03 13:00:00+00'::timestamptz
);

DO $fixture$
DECLARE
  baseline_result jsonb;
  replay_result jsonb;
  stable_result jsonb;
  changed_result jsonb;
  distant_result jsonb;
  changed_context_result jsonb;
  repeated_cutoff_result jsonb;
  baseline_snapshot jsonb;
  baseline_snapshot_id uuid;
  stable_snapshot_id uuid;
  snapshot_count integer;
  audit_text text;
BEGIN
  baseline_result = app_private.release_management_report_snapshot_v1(
    '85000000-0000-4000-8000-000000000001'::uuid,
    '81000000-0000-4000-8000-000000000001'::uuid,
    '83000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-17 12:34:56+00'::timestamptz,
    '2026-06-17 12:35:00+00'::timestamptz
  );

  IF baseline_result->>'result_status' <> 'approved_baseline'
    OR baseline_result->'compared_snapshot_id' <> 'null'::jsonb
    OR jsonb_typeof(baseline_result->'released_snapshot_id') <> 'string'
    OR baseline_result->>'shared_period_count' <> '0'
    OR baseline_result->>'assessed_cell_count' <> '0'
    OR baseline_result->'reason_codes' <> '[]'::jsonb
  THEN
    RAISE EXCEPTION 'first protected report did not establish a baseline';
  END IF;

  baseline_snapshot_id =
    (baseline_result->>'released_snapshot_id')::uuid;
  baseline_snapshot = app_private.read_management_report_snapshot_v1(
    baseline_snapshot_id
  );

  PERFORM app_private.validate_management_report_document_v1(
    baseline_snapshot
  );
  IF baseline_snapshot->>'project_id'
      <> '83000000-0000-4000-8000-000000000001'
    OR jsonb_array_length(baseline_snapshot->'cells') <> 16
    OR baseline_snapshot::text ~ '(contributor|max_contribution|place_name)'
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(baseline_snapshot->'cells') AS element(cell)
      WHERE cell->>'privacy_status' = 'suppressed'
        AND cell->'value_count' <> 'null'::jsonb
    )
  THEN
    RAISE EXCEPTION 'stored baseline was not the protected report document';
  END IF;

  replay_result = app_private.release_management_report_snapshot_v1(
    '85000000-0000-4000-8000-000000000001'::uuid,
    '81000000-0000-4000-8000-000000000001'::uuid,
    '83000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-17 12:34:56+00'::timestamptz,
    '2026-06-17 13:35:00+00'::timestamptz
  );
  IF replay_result <> baseline_result
    OR (
      SELECT count(*)
      FROM app_private.management_report_snapshots
      WHERE project_id =
        '83000000-0000-4000-8000-000000000001'::uuid
    ) <> 1
    OR (
      SELECT count(*)
      FROM app_private.management_report_release_attempts
      WHERE project_id =
        '83000000-0000-4000-8000-000000000001'::uuid
    ) <> 1
  THEN
    RAISE EXCEPTION 'service-timed release retry was not idempotent';
  END IF;

  IF (
    SELECT source_change_sequence <= 0
    FROM app_private.management_report_snapshots
    WHERE snapshot_id = baseline_snapshot_id
  ) THEN
    RAISE EXCEPTION 'snapshot did not retain its source change watermark';
  END IF;

  repeated_cutoff_result =
    app_private.release_management_report_snapshot_v1(
      '85000000-0000-4000-8000-000000000006'::uuid,
      '81000000-0000-4000-8000-000000000001'::uuid,
      '83000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz,
      '2026-06-17 12:36:00+00'::timestamptz
    );
  IF repeated_cutoff_result->>'result_status' <> 'blocked'
    OR repeated_cutoff_result->'reason_codes'
      <> jsonb_build_array('release_cutoff_not_advanced')
    OR repeated_cutoff_result->>'compared_snapshot_id'
      <> baseline_snapshot_id::text
    OR repeated_cutoff_result->'released_snapshot_id' <> 'null'::jsonb
  THEN
    RAISE EXCEPTION 'a new request re-released the same report cutoff';
  END IF;

  stable_result = app_private.release_management_report_snapshot_v1(
    '85000000-0000-4000-8000-000000000002'::uuid,
    '81000000-0000-4000-8000-000000000001'::uuid,
    '83000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-24 12:34:56+00'::timestamptz,
    '2026-06-24 12:35:00+00'::timestamptz
  );
  stable_snapshot_id = (stable_result->>'released_snapshot_id')::uuid;
  IF stable_result->>'result_status' <> 'approved'
    OR stable_result->>'compared_snapshot_id'
      <> baseline_snapshot_id::text
    OR stable_result->>'shared_period_count' <> '1'
    OR stable_result->>'assessed_cell_count' <> '8'
    OR stable_result->'reason_codes' <> '[]'::jsonb
    OR app_private.read_management_report_snapshot_v1(
      stable_snapshot_id
    )->'periods'->>'data_cutoff_utc'
      <> '2026-06-24T12:34:56.000Z'
  THEN
    RAISE EXCEPTION 'stable rolling report was not released';
  END IF;

  -- A trusted time-zone change belongs to the same logical report lineage.
  -- It cannot silently create a fresh baseline and bypass earlier releases.
  changed_context_result =
    app_private.release_management_report_snapshot_v1(
      '85000000-0000-4000-8000-000000000005'::uuid,
      '81000000-0000-4000-8000-000000000001'::uuid,
      '83000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'Asia/Shanghai',
      '2026-06-25 12:34:56+00'::timestamptz,
      '2026-06-25 12:35:00+00'::timestamptz
    );
  IF changed_context_result->>'result_status' <> 'blocked'
    OR changed_context_result->'reason_codes'
      <> jsonb_build_array('release_lineage_context_changed')
    OR changed_context_result->>'compared_snapshot_id'
      <> stable_snapshot_id::text
    OR (
      SELECT count(*)
      FROM app_private.management_report_snapshots
      WHERE project_id =
        '83000000-0000-4000-8000-000000000001'::uuid
    ) <> 2
  THEN
    RAISE EXCEPTION 'changed report context reset the release lineage';
  END IF;

  -- Late accepted facts change the already released week C from 10 to 11 and
  -- from suppressed to displayed. The next rolling report must not persist.
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
    place_name,
    smallest_region_id,
    reach_count,
    interest_level
  ) VALUES
    (
      'snapshot-late-voice-week-c',
      '81000000-0000-4000-8000-000000000003'::uuid,
      '82000000-0000-4000-8000-000000000001'::uuid,
      '83000000-0000-4000-8000-000000000001'::uuid,
      '84000000-0000-4000-8000-000000000001'::uuid,
      '2026-06-19 12:00:00+00'::timestamptz,
      'UTC',
      '2026-06-27 12:00:00+00'::timestamptz,
      'voice_call',
      'not_applicable',
      NULL,
      NULL,
      1,
      2
    ),
    (
      'snapshot-late-face-week-c',
      '81000000-0000-4000-8000-000000000003'::uuid,
      '82000000-0000-4000-8000-000000000001'::uuid,
      '83000000-0000-4000-8000-000000000001'::uuid,
      '84000000-0000-4000-8000-000000000001'::uuid,
      '2026-06-19 13:00:00+00'::timestamptz,
      'UTC',
      '2026-06-27 12:00:00+00'::timestamptz,
      'face_to_face',
      'resolved',
      'Synthetic plaza',
      'synthetic-region',
      1,
      2
    );

  changed_result = app_private.release_management_report_snapshot_v1(
    '85000000-0000-4000-8000-000000000003'::uuid,
    '81000000-0000-4000-8000-000000000001'::uuid,
    '83000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-07-01 12:34:56+00'::timestamptz,
    '2026-07-01 12:35:00+00'::timestamptz
  );
  SELECT count(*) INTO snapshot_count
  FROM app_private.management_report_snapshots
  WHERE project_id =
    '83000000-0000-4000-8000-000000000001'::uuid;
  IF changed_result->>'result_status' <> 'blocked'
    OR changed_result->>'compared_snapshot_id' <> stable_snapshot_id::text
    OR changed_result->'released_snapshot_id' <> 'null'::jsonb
    OR changed_result->'reason_codes' <> jsonb_build_array(
      'shared_cell_privacy_status_changed',
      'shared_displayed_value_changed'
    )
    OR snapshot_count <> 2
  THEN
    RAISE EXCEPTION 'changed historical cells created a report snapshot';
  END IF;

  distant_result = app_private.release_management_report_snapshot_v1(
    '85000000-0000-4000-8000-000000000004'::uuid,
    '81000000-0000-4000-8000-000000000001'::uuid,
    '83000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-07-15 12:34:56+00'::timestamptz,
    '2026-07-15 12:35:00+00'::timestamptz
  );
  IF distant_result->>'result_status' <> 'blocked'
    OR distant_result->'reason_codes'
      <> jsonb_build_array('no_shared_period')
    OR (
      SELECT count(*)
      FROM app_private.management_report_snapshots
      WHERE project_id =
        '83000000-0000-4000-8000-000000000001'::uuid
    ) <> 2
  THEN
    RAISE EXCEPTION 'non-overlapping report created a snapshot';
  END IF;

  IF NOT changed_result ?& ARRAY[
      'release_contract_id',
      'release_request_id',
      'project_id',
      'release_lineage_id',
      'report_id',
      'report_version',
      'query_fingerprint',
      'reporting_time_zone',
      'data_cutoff_utc',
      'requested_at_utc',
      'compared_snapshot_id',
      'released_snapshot_id',
      'shared_period_count',
      'assessed_cell_count',
      'result_status',
      'reason_codes'
    ]
    OR changed_result - ARRAY[
      'release_contract_id',
      'release_request_id',
      'project_id',
      'release_lineage_id',
      'report_id',
      'report_version',
      'query_fingerprint',
      'reporting_time_zone',
      'data_cutoff_utc',
      'requested_at_utc',
      'compared_snapshot_id',
      'released_snapshot_id',
      'shared_period_count',
      'assessed_cell_count',
      'result_status',
      'reason_codes'
    ] <> '{}'::jsonb
    OR changed_result::text ~ '(cells|value_count|contributor)'
  THEN
    RAISE EXCEPTION 'release result exposed report values or changed shape';
  END IF;

  SELECT string_agg(to_jsonb(attempt_row)::text, ' ')
  INTO audit_text
  FROM app_private.management_report_release_attempts AS attempt_row
  WHERE project_id =
      '83000000-0000-4000-8000-000000000001'::uuid
    AND result_status = 'blocked';
  IF audit_text ~ '(cells|value_count|protected_report|contributor)'
  THEN
    RAISE EXCEPTION 'blocked release audit retained candidate report values';
  END IF;

  BEGIN
    PERFORM app_private.release_management_report_snapshot_v1(
      '85000000-0000-4000-8000-000000000001'::uuid,
      '81000000-0000-4000-8000-000000000001'::uuid,
      '83000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-24 12:34:56+00'::timestamptz,
      '2026-06-24 12:35:00+00'::timestamptz
    );
    RAISE EXCEPTION 'release request id accepted different parameters';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    INSERT INTO app_private.management_report_release_attempts (
      release_request_id,
      requested_by_app_user_id,
      project_id,
      release_lineage_id,
      report_id,
      report_version,
      query_fingerprint,
      reporting_time_zone,
      data_cutoff_utc,
      requested_at_utc,
      source_change_sequence,
      compared_snapshot_id,
      released_snapshot_id,
      shared_period_count,
      assessed_cell_count,
      result_status,
      reason_codes,
      result_document
    )
    SELECT
      '85000000-0000-4000-8000-000000000099'::uuid,
      requested_by_app_user_id,
      project_id,
      release_lineage_id,
      report_id,
      report_version,
      query_fingerprint,
      reporting_time_zone,
      data_cutoff_utc,
      requested_at_utc + interval '2 hours',
      source_change_sequence,
      baseline_snapshot_id,
      NULL,
      0,
      0,
      'blocked',
      jsonb_build_array('release_cutoff_not_advanced'),
      jsonb_build_object('cells', jsonb_build_array())
    FROM app_private.management_report_release_attempts
    WHERE release_request_id =
      '85000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'release audit accepted a forged result document';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.management_report_snapshots
    SET released_at_utc = released_at_utc + interval '1 second'
    WHERE snapshot_id = baseline_snapshot_id;
    RAISE EXCEPTION 'published snapshot was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_report_snapshots
    WHERE snapshot_id = baseline_snapshot_id;
    RAISE EXCEPTION 'published snapshot was deletable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.management_report_release_attempts
    SET requested_at_utc = requested_at_utc + interval '1 second'
    WHERE release_request_id =
      '85000000-0000-4000-8000-000000000004'::uuid;
    RAISE EXCEPTION 'release audit was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_report_release_attempts
    WHERE release_request_id =
      '85000000-0000-4000-8000-000000000004'::uuid;
    RAISE EXCEPTION 'release audit was deletable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
