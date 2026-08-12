\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE management_region_privacy_fixture (
  scenario text NOT NULL,
  probe_patch jsonb NOT NULL,
  expected_status text NOT NULL,
  expected_reason_codes jsonb NOT NULL
);

\copy management_region_privacy_fixture FROM 'backend/database/fixtures/shared/management_region_privacy_v1.csv' WITH (FORMAT csv, HEADER true)

DO $fixture$
DECLARE
  base_probe jsonb;
  fixture_row management_region_privacy_fixture%ROWTYPE;
  assessment jsonb;
  assessment_text text;
BEGIN
  SELECT probe_patch INTO STRICT base_probe
  FROM management_region_privacy_fixture
  WHERE scenario = 'base';

  FOR fixture_row IN
    SELECT * FROM management_region_privacy_fixture ORDER BY scenario
  LOOP
    IF fixture_row.expected_status = 'malformed' THEN
      BEGIN
        PERFORM app_private.assess_management_region_privacy_v1(
          base_probe || fixture_row.probe_patch
        );
        RAISE EXCEPTION
          'malformed region privacy scenario % was accepted',
          fixture_row.scenario;
      EXCEPTION WHEN invalid_parameter_value THEN
        NULL;
      END;
      CONTINUE;
    END IF;

    assessment = app_private.assess_management_region_privacy_v1(
      base_probe || fixture_row.probe_patch
    );
    IF assessment->>'result_status' <> fixture_row.expected_status
      OR assessment->'reason_codes' <> fixture_row.expected_reason_codes
    THEN
      RAISE EXCEPTION
        'region privacy scenario % disagreed: %',
        fixture_row.scenario,
        assessment;
    END IF;
    IF assessment - ARRAY[
      'probe_id', 'query_fingerprint', 'result_status', 'reason_codes'
    ] <> '{}'::jsonb THEN
      RAISE EXCEPTION 'region privacy assessment shape is not minimal';
    END IF;
    assessment_text = assessment::text;
    IF assessment_text ~ '(value_count|contributor|latitude|longitude|city-a|campus-a|regions-v[12])'
    THEN
      RAISE EXCEPTION 'region privacy assessment exposed protected input';
    END IF;
  END LOOP;

  BEGIN
    PERFORM app_private.assess_management_region_privacy_v1(
      base_probe || jsonb_build_object('unexpected', true)
    );
    RAISE EXCEPTION 'probe with an extra key was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.assess_management_region_privacy_v1(
      jsonb_set(base_probe, '{reports,0,cells,0,value_count}', '-1'::jsonb)
    );
    RAISE EXCEPTION 'probe with a negative displayed value was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.assess_management_region_privacy_v1(
      jsonb_set(
        jsonb_set(
          base_probe,
          '{reports,0,cells,0,privacy_status}',
          '"suppressed"'::jsonb
        ),
        '{reports,0,cells,0,value_count}',
        '9'::jsonb
      )
    );
    RAISE EXCEPTION 'suppressed cell exposed an exact value';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SET LOCAL ROLE tongxingzhe_runtime;
  BEGIN
    PERFORM app_private.assess_management_region_privacy_v1(base_probe);
    RAISE EXCEPTION 'runtime executed the private region privacy probe';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
