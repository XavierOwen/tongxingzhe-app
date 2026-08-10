\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE management_report_period_fixture (
  case_name text NOT NULL,
  reporting_time_zone text,
  data_cutoff_utc text NOT NULL,
  expected_status text NOT NULL,
  expected_previous_start_utc text,
  expected_previous_until_utc text,
  expected_current_start_utc text,
  expected_current_until_utc text,
  expected_previous_hours integer,
  expected_current_hours integer
);

\copy management_report_period_fixture FROM 'backend/database/fixtures/shared/management_report_periods_v1.csv' WITH (FORMAT csv, HEADER true)

DO $fixture$
DECLARE
  fixture_row management_report_period_fixture%ROWTYPE;
  resolved jsonb;
  previous_hours numeric;
  current_hours numeric;
BEGIN
  FOR fixture_row IN
    SELECT * FROM management_report_period_fixture ORDER BY case_name
  LOOP
    BEGIN
      resolved = app_private.resolve_management_report_periods_v1(
        fixture_row.reporting_time_zone,
        fixture_row.data_cutoff_utc::timestamptz
      );
      IF fixture_row.expected_status <> 'accepted' THEN
        RAISE EXCEPTION 'period fixture was accepted incorrectly: %',
          fixture_row.case_name;
      END IF;
      IF resolved <> jsonb_build_object(
        'period_boundary_id', 'iso_week_monday_v1',
        'reporting_time_zone', fixture_row.reporting_time_zone,
        'data_cutoff_utc', fixture_row.data_cutoff_utc,
        'previous_period', jsonb_build_object(
          'start_utc', fixture_row.expected_previous_start_utc,
          'until_utc', fixture_row.expected_previous_until_utc
        ),
        'current_period', jsonb_build_object(
          'start_utc', fixture_row.expected_current_start_utc,
          'until_utc', fixture_row.expected_current_until_utc
        )
      ) THEN
        RAISE EXCEPTION 'period fixture disagrees with expected output: %',
          fixture_row.case_name;
      END IF;

      previous_hours = extract(epoch FROM (
        (resolved->'previous_period'->>'until_utc')::timestamptz
        - (resolved->'previous_period'->>'start_utc')::timestamptz
      )) / 3600;
      current_hours = extract(epoch FROM (
        (resolved->'current_period'->>'until_utc')::timestamptz
        - (resolved->'current_period'->>'start_utc')::timestamptz
      )) / 3600;
      IF previous_hours <> fixture_row.expected_previous_hours
        OR current_hours <> fixture_row.expected_current_hours
        OR resolved->'previous_period'->>'until_utc'
          <> resolved->'current_period'->>'start_utc'
        OR (resolved->'current_period'->>'until_utc')::timestamptz
          > fixture_row.data_cutoff_utc::timestamptz
      THEN
        RAISE EXCEPTION 'period invariants failed: %', fixture_row.case_name;
      END IF;
    EXCEPTION WHEN invalid_parameter_value THEN
      IF fixture_row.expected_status <> 'rejected' THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  BEGIN
    PERFORM app_private.resolve_management_report_periods_v1('UTC', NULL);
    RAISE EXCEPTION 'null management report cutoff was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
