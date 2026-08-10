\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE management_report_request_fixture (
  case_name text NOT NULL,
  report_id text NOT NULL,
  report_version integer NOT NULL,
  extra_key text,
  extra_value text,
  expected_status text NOT NULL,
  expected_fingerprint text
);

\copy management_report_request_fixture FROM 'backend/database/fixtures/shared/management_report_requests_v1.csv' WITH (FORMAT csv, HEADER true)

DO $fixture$
DECLARE
  fixture_row management_report_request_fixture%ROWTYPE;
  request_document jsonb;
  canonical_request jsonb;
  audit_envelope jsonb;
BEGIN
  FOR fixture_row IN
    SELECT * FROM management_report_request_fixture ORDER BY case_name
  LOOP
    request_document = jsonb_build_object(
      'report_id', fixture_row.report_id,
      'report_version', fixture_row.report_version
    );
    IF fixture_row.extra_key IS NOT NULL THEN
      request_document = request_document || jsonb_build_object(
        fixture_row.extra_key,
        fixture_row.extra_value
      );
    END IF;

    BEGIN
      canonical_request =
        app_private.canonicalize_management_report_request_v1(
          request_document
        );
      IF fixture_row.expected_status <> 'accepted'
        OR canonical_request->>'query_fingerprint'
          IS DISTINCT FROM fixture_row.expected_fingerprint
      THEN
        RAISE EXCEPTION 'management request case was accepted incorrectly: %',
          fixture_row.case_name;
      END IF;
    EXCEPTION WHEN invalid_parameter_value THEN
      IF fixture_row.expected_status <> 'rejected' THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  canonical_request = app_private.canonicalize_management_report_request_v1(
    '{"report_id":"contact_sessions_by_channel_two_periods","report_version":1}'::jsonb
  );
  IF canonical_request <> jsonb_build_object(
    'report_id', 'contact_sessions_by_channel_two_periods',
    'report_version', 1,
    'metric_id', 'contact_sessions',
    'metric_version', 1,
    'dimension', 'channel',
    'period_grain', 'week',
    'comparison_period_count', 2,
    'privacy_policy', 'management_contact_session_privacy_v1',
    'required_capability', 'view_anonymous_analytics',
    'query_fingerprint',
      'management-report:contact_sessions_by_channel_two_periods:v1'
  ) THEN
    RAISE EXCEPTION 'canonical management request shape is incorrect';
  END IF;

  audit_envelope = app_private.build_management_report_audit_envelope_v1(
    '11111111-1111-4111-8111-111111111111'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    '2030-01-15 12:00:00+00'::timestamptz,
    'completed'
  );
  IF audit_envelope <> jsonb_build_object(
    'app_user_id', '11111111-1111-4111-8111-111111111111',
    'project_id', '33333333-3333-4333-8333-333333333333',
    'report_id', 'contact_sessions_by_channel_two_periods',
    'report_version', 1,
    'query_fingerprint',
      'management-report:contact_sessions_by_channel_two_periods:v1',
    'requested_at_utc', '2030-01-15T12:00:00.000Z',
    'result_status', 'completed'
  ) OR audit_envelope ?| ARRAY[
    'value_count',
    'contributor_count',
    'max_contribution',
    'suppressed_value'
  ] THEN
    RAISE EXCEPTION 'management report audit envelope is incorrect';
  END IF;

  BEGIN
    PERFORM app_private.build_management_report_audit_envelope_v1(
      '11111111-1111-4111-8111-111111111111'::uuid,
      '33333333-3333-4333-8333-333333333333'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      clock_timestamp(),
      'displayed'
    );
    RAISE EXCEPTION 'unknown management report audit status was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.build_management_report_audit_envelope_v1(
      '11111111-1111-4111-8111-111111111111'::uuid,
      '33333333-3333-4333-8333-333333333333'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      clock_timestamp(),
      NULL
    );
    RAISE EXCEPTION 'null management report audit status was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    UPDATE app_private.management_report_definitions
    SET metric_version = 2
    WHERE report_id = 'contact_sessions_by_channel_two_periods'
      AND report_version = 1;
    RAISE EXCEPTION 'versioned management report definition was mutated';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
