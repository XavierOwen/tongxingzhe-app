\set ON_ERROR_STOP on

-- The 0031 fixture has already created a real trusted-v2 baseline and its
-- delegated v1 attempt under one request UUID. The old v1 writer records a
-- second, blocked request UUID at the same cutoff.
DO $verify$
DECLARE
  baseline app_private.management_report_release_v2_attempts%ROWTYPE;
  legacy_result jsonb;
BEGIN
  SELECT * INTO STRICT baseline
  FROM app_private.management_report_release_v2_attempts
  WHERE release_request_id = '00000000-0000-4000-8000-000000007c0c';

  legacy_result = app_private.release_management_report_snapshot_v1(
    '00000000-0000-4000-8000-000000007c57',
    '00000000-0000-4000-8000-000000007c01',
    '00000000-0000-4000-8000-000000007c05',
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    baseline.data_cutoff_utc,
    clock_timestamp()
  );

  IF baseline.result_status <> 'approved_baseline'
    OR legacy_result->>'result_status' <> 'blocked'
    OR legacy_result->'reason_codes' <>
      '["release_cutoff_not_advanced"]'::jsonb
    OR (SELECT count(*) FROM app_private.management_report_snapshots) <> 1
    OR (SELECT count(*)
        FROM app_private.management_report_release_attempts) <> 2
    OR (SELECT count(*)
        FROM app_private.management_report_release_v2_attempts) <> 1
    OR (SELECT count(DISTINCT release_request_id)
        FROM (
          SELECT release_request_id
          FROM app_private.management_report_release_attempts
          UNION ALL
          SELECT release_request_id
          FROM app_private.management_report_release_v2_attempts
        ) AS old_attempts) <> 2
    OR to_regclass(
      'app_private.management_report_release_request_claims'
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION '0056 old channel release history is invalid';
  END IF;
END
$verify$;
