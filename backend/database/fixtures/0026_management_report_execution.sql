\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id)
VALUES
  ('61000000-0000-4000-8000-000000000001'::uuid),
  ('61000000-0000-4000-8000-000000000002'::uuid),
  ('61000000-0000-4000-8000-000000000003'::uuid);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name
) VALUES (
  '62000000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic report workspace'
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name
) VALUES
  (
    '63000000-0000-4000-8000-000000000001'::uuid,
    '62000000-0000-4000-8000-000000000001'::uuid,
    'Synthetic report project'
  ),
  (
    '63000000-0000-4000-8000-000000000002'::uuid,
    '62000000-0000-4000-8000-000000000001'::uuid,
    'Other synthetic project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES
  (
    '64000000-0000-4000-8000-000000000001'::uuid,
    '63000000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '64000000-0000-4000-8000-000000000002'::uuid,
    '63000000-0000-4000-8000-000000000002'::uuid,
    1,
    'published',
    true
  );

-- 每期十个有效 voice_call，由三位推广者贡献 5、3、2。
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
  'report-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '61000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '61000000-0000-4000-8000-000000000002'::uuid
    ELSE '61000000-0000-4000-8000-000000000003'::uuid
  END,
  '62000000-0000-4000-8000-000000000001'::uuid,
  '63000000-0000-4000-8000-000000000001'::uuid,
  '64000000-0000-4000-8000-000000000001'::uuid,
  CASE
    WHEN period_row.period_key = 'current' AND series_row = 1
      THEN '2026-06-08 00:00:00+00'::timestamptz
    ELSE period_row.occurred_at_utc
  END,
  'UTC',
  '2026-06-16 12:00:00+00'::timestamptz,
  'voice_call',
  'not_applicable',
  1,
  2
FROM (
  VALUES
    ('previous'::text, '2026-06-02 12:00:00+00'::timestamptz),
    ('current'::text, '2026-06-09 12:00:00+00'::timestamptz)
) AS period_row(period_key, occurred_at_utc)
CROSS JOIN generate_series(1, 10) AS series_row;

-- 以下记录都不得改变两个可显示 voice_call 格的值。
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
  interest_level,
  lifecycle_status
) VALUES
  (
    'report-voided',
    '61000000-0000-4000-8000-000000000001'::uuid,
    '62000000-0000-4000-8000-000000000001'::uuid,
    '63000000-0000-4000-8000-000000000001'::uuid,
    '64000000-0000-4000-8000-000000000001'::uuid,
    '2026-06-09 13:00:00+00'::timestamptz,
    'UTC',
    '2026-06-10 12:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    2,
    'voided'
  ),
  (
    'report-right-boundary',
    '61000000-0000-4000-8000-000000000001'::uuid,
    '62000000-0000-4000-8000-000000000001'::uuid,
    '63000000-0000-4000-8000-000000000001'::uuid,
    '64000000-0000-4000-8000-000000000001'::uuid,
    '2026-06-15 00:00:00+00'::timestamptz,
    'UTC',
    '2026-06-15 00:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    2,
    'active'
  ),
  (
    'report-after-cutoff-submit',
    '61000000-0000-4000-8000-000000000001'::uuid,
    '62000000-0000-4000-8000-000000000001'::uuid,
    '63000000-0000-4000-8000-000000000001'::uuid,
    '64000000-0000-4000-8000-000000000001'::uuid,
    '2026-06-09 14:00:00+00'::timestamptz,
    'UTC',
    '2026-06-18 00:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    2,
    'active'
  ),
  (
    'report-other-project',
    '61000000-0000-4000-8000-000000000001'::uuid,
    '62000000-0000-4000-8000-000000000001'::uuid,
    '63000000-0000-4000-8000-000000000002'::uuid,
    '64000000-0000-4000-8000-000000000002'::uuid,
    '2026-06-09 15:00:00+00'::timestamptz,
    'UTC',
    '2026-06-10 12:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    2,
    'active'
  );

INSERT INTO app_data.contact_attempts (
  attempt_id,
  app_user_id,
  workspace_id,
  project_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel
) VALUES (
  'report-attempt',
  '61000000-0000-4000-8000-000000000001'::uuid,
  '62000000-0000-4000-8000-000000000001'::uuid,
  '63000000-0000-4000-8000-000000000001'::uuid,
  '2026-06-09 16:00:00+00'::timestamptz,
  'UTC',
  '2026-06-10 12:00:00+00'::timestamptz,
  'voice_call'
);

DO $fixture$
DECLARE
  report_document jsonb;
  report_text text;
BEGIN
  report_document =
    app_private.execute_management_contact_session_report_v1(
      '63000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz
    );

  IF NOT report_document ?& ARRAY[
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'dimension',
    'query_fingerprint',
    'privacy_policy',
    'source_scope',
    'project_id',
    'periods',
    'cells'
  ] OR report_document - ARRAY[
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'dimension',
    'query_fingerprint',
    'privacy_policy',
    'source_scope',
    'project_id',
    'periods',
    'cells'
  ] <> '{}'::jsonb
    OR report_document->>'report_id'
      <> 'contact_sessions_by_channel_two_periods'
    OR report_document->>'report_version' <> '1'
    OR report_document->>'metric_id' <> 'contact_sessions'
    OR report_document->>'metric_version' <> '1'
    OR report_document->>'dimension' <> 'channel'
    OR report_document->>'query_fingerprint'
      <> 'management-report:contact_sessions_by_channel_two_periods:v1'
    OR report_document->>'privacy_policy'
      <> 'management_contact_session_privacy_v1'
    OR report_document->>'source_scope' <> 'backend_accepted_contacts'
    OR report_document->>'project_id'
      <> '63000000-0000-4000-8000-000000000001'
    OR report_document->'periods'->>'period_boundary_id'
      <> 'iso_week_monday_v1'
    OR report_document->'periods'->>'reporting_time_zone' <> 'UTC'
    OR jsonb_array_length(report_document->'cells') <> 16
  THEN
    RAISE EXCEPTION 'private management report metadata is incorrect';
  END IF;

  IF (
    SELECT array_agg((cell->>'cell_order')::integer ORDER BY ordinal)
    FROM jsonb_array_elements(report_document->'cells')
      WITH ORDINALITY AS element(cell, ordinal)
  ) <> ARRAY[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
  THEN
    RAISE EXCEPTION 'private management report cell order is unstable';
  END IF;

  IF (
    SELECT count(*)
    FROM jsonb_array_elements(report_document->'cells') AS element(cell)
    WHERE cell->>'category_key' = 'voice_call'
      AND cell->>'privacy_status' = 'displayed'
      AND (cell->>'value_count')::integer = 10
  ) <> 2 OR (
    SELECT count(*)
    FROM jsonb_array_elements(report_document->'cells') AS element(cell)
    WHERE cell->>'privacy_status' = 'suppressed'
      AND cell->'value_count' = 'null'::jsonb
  ) <> 14 THEN
    RAISE EXCEPTION 'private management report privacy output is incorrect';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(report_document->'cells') AS element(cell)
    WHERE NOT cell ?& ARRAY[
      'period_key',
      'category_key',
      'cell_order',
      'value_count',
      'privacy_status'
    ] OR cell - ARRAY[
      'period_key',
      'category_key',
      'cell_order',
      'value_count',
      'privacy_status'
    ] <> '{}'::jsonb
  ) THEN
    RAISE EXCEPTION 'private management report cell shape is not minimal';
  END IF;

  report_text = report_document::text;
  IF report_text ~ '(app_user_id|contributor_key|contributor_count|max_contribution|reach_count|interest_level|place_name|61000000-0000-4000-8000-00000000000[1-3])'
  THEN
    RAISE EXCEPTION 'private management report exposed source details';
  END IF;

  BEGIN
    PERFORM app_private.execute_management_contact_session_report_v1(
      '63000000-0000-4000-8000-000000000099'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz
    );
    RAISE EXCEPTION 'unknown management report project was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.execute_management_contact_session_report_v1(
      '63000000-0000-4000-8000-000000000001'::uuid,
      'unknown_report',
      1,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz
    );
    RAISE EXCEPTION 'unknown management report definition was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.execute_management_contact_session_report_v1(
      '63000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      2,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz
    );
    RAISE EXCEPTION 'unknown management report version was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.execute_management_contact_session_report_v1(
      '63000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'CST',
      '2026-06-17 12:34:56+00'::timestamptz
    );
    RAISE EXCEPTION 'invalid management report time zone was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
