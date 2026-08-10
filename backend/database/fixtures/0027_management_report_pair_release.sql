\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id)
VALUES
  ('71000000-0000-4000-8000-000000000001'::uuid),
  ('71000000-0000-4000-8000-000000000002'::uuid),
  ('71000000-0000-4000-8000-000000000003'::uuid);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name
) VALUES (
  '72000000-0000-4000-8000-000000000001'::uuid,
  'organization',
  'Synthetic report release workspace'
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name
) VALUES (
  '73000000-0000-4000-8000-000000000001'::uuid,
  '72000000-0000-4000-8000-000000000001'::uuid,
  'Synthetic report release project'
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES (
  '74000000-0000-4000-8000-000000000001'::uuid,
  '73000000-0000-4000-8000-000000000001'::uuid,
  1,
  'published',
  true
);

-- 三个相邻周各有十个安全的语音通话格，贡献分布固定为 5、3、2。
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
  'release-voice-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '71000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '71000000-0000-4000-8000-000000000002'::uuid
    ELSE '71000000-0000-4000-8000-000000000003'::uuid
  END,
  '72000000-0000-4000-8000-000000000001'::uuid,
  '73000000-0000-4000-8000-000000000001'::uuid,
  '74000000-0000-4000-8000-000000000001'::uuid,
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
    )
) AS period_row(period_key, occurred_at_utc, first_submitted_at_utc)
CROSS JOIN generate_series(1, 10) AS series_row;

-- 共享的 week_b 先有九个面对面场次，必须保持 suppressed/null。
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
  'release-face-week-b-' || series_row::text,
  CASE
    WHEN series_row <= 4
      THEN '71000000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 7
      THEN '71000000-0000-4000-8000-000000000002'::uuid
    ELSE '71000000-0000-4000-8000-000000000003'::uuid
  END,
  '72000000-0000-4000-8000-000000000001'::uuid,
  '73000000-0000-4000-8000-000000000001'::uuid,
  '74000000-0000-4000-8000-000000000001'::uuid,
  '2026-06-11 12:00:00+00'::timestamptz,
  'UTC',
  '2026-06-11 13:00:00+00'::timestamptz,
  'face_to_face',
  'resolved',
  'Synthetic plaza',
  'synthetic-region',
  1,
  2
FROM generate_series(1, 9) AS series_row;

DO $fixture$
DECLARE
  earlier_report jsonb;
  same_period_later_report jsonb;
  stable_rolling_report jsonb;
  changed_rolling_report jsonb;
  distant_report jsonb;
  assessment jsonb;
  assessment_text text;
BEGIN
  earlier_report = app_private.execute_management_contact_session_report_v1(
    '73000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-17 12:34:56+00'::timestamptz
  );
  same_period_later_report =
    app_private.execute_management_contact_session_report_v1(
      '73000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-18 12:34:56+00'::timestamptz
    );
  stable_rolling_report =
    app_private.execute_management_contact_session_report_v1(
      '73000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-24 12:34:56+00'::timestamptz
    );

  assessment = app_private.assess_management_report_pair_release_v1(
    earlier_report,
    same_period_later_report
  );
  IF assessment->>'result_status' <> 'approved'
    OR assessment->>'shared_period_count' <> '2'
    OR assessment->>'assessed_cell_count' <> '16'
    OR assessment->'reason_codes' <> '[]'::jsonb
  THEN
    RAISE EXCEPTION 'unchanged two-period report pair was not approved';
  END IF;

  assessment = app_private.assess_management_report_pair_release_v1(
    earlier_report,
    stable_rolling_report
  );
  IF assessment->>'result_status' <> 'approved'
    OR assessment->>'shared_period_count' <> '1'
    OR assessment->>'assessed_cell_count' <> '8'
    OR assessment->'reason_codes' <> '[]'::jsonb
  THEN
    RAISE EXCEPTION 'stable rolling report pair was not approved';
  END IF;

  IF (
    SELECT count(*)
    FROM jsonb_array_elements(earlier_report->'cells') AS element(cell)
    WHERE cell->>'period_key' = 'current'
      AND cell->>'category_key' IN ('all', 'face_to_face')
      AND cell->>'privacy_status' = 'suppressed'
      AND cell->'value_count' = 'null'::jsonb
  ) <> 2 THEN
    RAISE EXCEPTION 'sparse and complementary cells did not stay hidden';
  END IF;

  -- 两条补录让同一个历史周的 voice_call 从 10 变 11，并让
  -- face_to_face 从 suppressed 变为 displayed。后续报告必须阻止发布。
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
      'release-late-voice-week-b',
      '71000000-0000-4000-8000-000000000003'::uuid,
      '72000000-0000-4000-8000-000000000001'::uuid,
      '73000000-0000-4000-8000-000000000001'::uuid,
      '74000000-0000-4000-8000-000000000001'::uuid,
      '2026-06-12 12:00:00+00'::timestamptz,
      'UTC',
      '2026-06-20 12:00:00+00'::timestamptz,
      'voice_call',
      'not_applicable',
      NULL,
      NULL,
      1,
      2
    ),
    (
      'release-late-face-week-b',
      '71000000-0000-4000-8000-000000000003'::uuid,
      '72000000-0000-4000-8000-000000000001'::uuid,
      '73000000-0000-4000-8000-000000000001'::uuid,
      '74000000-0000-4000-8000-000000000001'::uuid,
      '2026-06-12 13:00:00+00'::timestamptz,
      'UTC',
      '2026-06-20 12:00:00+00'::timestamptz,
      'face_to_face',
      'resolved',
      'Synthetic plaza',
      'synthetic-region',
      1,
      2
    );

  changed_rolling_report =
    app_private.execute_management_contact_session_report_v1(
      '73000000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      '2026-06-24 12:34:56+00'::timestamptz
    );
  assessment = app_private.assess_management_report_pair_release_v1(
    earlier_report,
    changed_rolling_report
  );

  IF assessment->>'result_status' <> 'blocked'
    OR assessment->>'shared_period_count' <> '1'
    OR assessment->>'assessed_cell_count' <> '8'
    OR assessment->'reason_codes' <> jsonb_build_array(
      'shared_cell_privacy_status_changed',
      'shared_displayed_value_changed'
    )
  THEN
    RAISE EXCEPTION 'changed overlapping cells did not block release';
  END IF;

  IF NOT assessment ?& ARRAY[
      'assessment_id',
      'report_id',
      'report_version',
      'query_fingerprint',
      'privacy_policy',
      'project_id',
      'reporting_time_zone',
      'earlier_data_cutoff_utc',
      'later_data_cutoff_utc',
      'shared_period_count',
      'assessed_cell_count',
      'result_status',
      'reason_codes'
    ]
    OR assessment - ARRAY[
      'assessment_id',
      'report_id',
      'report_version',
      'query_fingerprint',
      'privacy_policy',
      'project_id',
      'reporting_time_zone',
      'earlier_data_cutoff_utc',
      'later_data_cutoff_utc',
      'shared_period_count',
      'assessed_cell_count',
      'result_status',
      'reason_codes'
    ] <> '{}'::jsonb
  THEN
    RAISE EXCEPTION 'report pair release audit shape is not minimal';
  END IF;

  assessment_text = assessment::text;
  IF assessment_text ~ '(value_count|cells|app_user_id|contributor|71000000-0000-4000-8000-00000000000[1-3])'
  THEN
    RAISE EXCEPTION 'report pair release audit exposed protected details';
  END IF;

  distant_report = app_private.execute_management_contact_session_report_v1(
    '73000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-07-08 12:34:56+00'::timestamptz
  );
  assessment = app_private.assess_management_report_pair_release_v1(
    earlier_report,
    distant_report
  );
  IF assessment->>'result_status' <> 'blocked'
    OR assessment->>'shared_period_count' <> '0'
    OR assessment->>'assessed_cell_count' <> '0'
    OR assessment->'reason_codes' <> jsonb_build_array('no_shared_period')
  THEN
    RAISE EXCEPTION 'non-overlapping report pair did not fail closed';
  END IF;

  BEGIN
    PERFORM app_private.assess_management_report_pair_release_v1(
      jsonb_set(earlier_report, '{cells,0,value_count}', '9'::jsonb),
      stable_rolling_report
    );
    RAISE EXCEPTION 'suppressed cell accepted a forged exact value';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.assess_management_report_pair_release_v1(
      jsonb_set(earlier_report, '{cells,10,value_count}', '9'::jsonb),
      stable_rolling_report
    );
    RAISE EXCEPTION 'displayed cell below k=10 was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.assess_management_report_pair_release_v1(
      stable_rolling_report,
      earlier_report
    );
    RAISE EXCEPTION 'reversed report cutoffs were accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_channel_two_periods',
        'report_version', 1,
        'dimensions', jsonb_build_array('region')
      )
    );
    RAISE EXCEPTION 'overlapping region probe was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_channel_two_periods',
        'report_version', 1,
        'from_utc', '2026-06-08T00:00:00.000Z'
      )
    );
    RAISE EXCEPTION 'arbitrary period probe was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_channel_two_periods',
        'report_version', 1,
        'exclude_app_user_id',
          '71000000-0000-4000-8000-000000000001'
      )
    );
    RAISE EXCEPTION 'known-contributor exclusion probe was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
