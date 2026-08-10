\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE management_contact_session_fixture (
  scenario text NOT NULL,
  period_key text NOT NULL,
  channel text NOT NULL,
  contributor_key text NOT NULL,
  unit_count integer NOT NULL
);

\copy management_contact_session_fixture FROM 'backend/database/fixtures/shared/management_contact_sessions_v1.csv' WITH (FORMAT csv, HEADER true)

DO $fixture$
DECLARE
  scenario_name text;
  contributions jsonb;
BEGIN
  FOREACH scenario_name IN ARRAY ARRAY[
    'safe',
    'small_sample',
    'two_contributors',
    'dominant',
    'complementary'
  ] LOOP
    SELECT jsonb_agg(
      jsonb_build_object(
        'period_key', period_key,
        'channel', channel,
        'contributor_key', contributor_key,
        'unit_count', unit_count
      ) ORDER BY period_key, channel, contributor_key
    ) INTO contributions
    FROM management_contact_session_fixture
    WHERE scenario = scenario_name;

    IF contributions IS NULL THEN
      RAISE EXCEPTION 'management fixture scenario is missing: %', scenario_name;
    END IF;

    CREATE TEMP TABLE protected_result ON COMMIT DROP AS
    SELECT *
    FROM app_private.protect_management_contact_session_grid_v1(contributions);

    IF (SELECT count(*) FROM protected_result) <> 16
      OR (SELECT count(DISTINCT cell_order) FROM protected_result) <> 16
      OR (SELECT min(cell_order) FROM protected_result) <> 0
      OR (SELECT max(cell_order) FROM protected_result) <> 15
      OR EXISTS (
        SELECT 1 FROM protected_result
        WHERE privacy_status NOT IN ('displayed', 'suppressed')
          OR privacy_status = 'suppressed' AND value_count IS NOT NULL
          OR privacy_status = 'displayed' AND value_count IS NULL
          OR cell_order <> CASE period_key
            WHEN 'previous' THEN 0
            WHEN 'current' THEN 8
          END + CASE category_key
            WHEN 'all' THEN 0
            WHEN 'face_to_face' THEN 1
            WHEN 'voice_call' THEN 2
            WHEN 'video_call' THEN 3
            WHEN 'instant_text' THEN 4
            WHEN 'asynchronous_message' THEN 5
            WHEN 'mixed' THEN 6
            WHEN 'other_direct' THEN 7
          END
      )
    THEN
      RAISE EXCEPTION 'invalid protected grid for scenario %', scenario_name;
    END IF;

    IF scenario_name = 'safe' THEN
      IF EXISTS (
        SELECT 1 FROM protected_result WHERE privacy_status <> 'displayed'
      ) OR (
        SELECT value_count FROM protected_result
        WHERE period_key = 'current' AND category_key = 'all'
      ) <> 70 THEN
        RAISE EXCEPTION 'safe management fixture was suppressed';
      END IF;
    ELSIF scenario_name = 'small_sample' THEN
      IF (
        SELECT privacy_status FROM protected_result
        WHERE period_key = 'current' AND category_key = 'face_to_face'
      ) <> 'suppressed' THEN
        RAISE EXCEPTION 'k=9 management cell was displayed';
      END IF;
    ELSIF scenario_name = 'two_contributors' THEN
      IF (
        SELECT privacy_status FROM protected_result
        WHERE period_key = 'current' AND category_key = 'video_call'
      ) <> 'suppressed' THEN
        RAISE EXCEPTION 'two-contributor management cell was displayed';
      END IF;
    ELSIF scenario_name = 'dominant' THEN
      IF (
        SELECT privacy_status FROM protected_result
        WHERE period_key = 'current' AND category_key = 'voice_call'
      ) <> 'suppressed' THEN
        RAISE EXCEPTION 'dominant-contributor management cell was displayed';
      END IF;
    ELSIF scenario_name = 'complementary' THEN
      IF (
        SELECT privacy_status FROM protected_result
        WHERE period_key = 'current' AND category_key = 'all'
      ) <> 'suppressed' OR (
        SELECT privacy_status FROM protected_result
        WHERE period_key = 'current' AND category_key = 'voice_call'
      ) <> 'displayed' THEN
        RAISE EXCEPTION 'complementary management suppression is incorrect';
      END IF;
    END IF;

    DROP TABLE protected_result;
  END LOOP;

  BEGIN
    PERFORM app_private.protect_management_contact_session_grid_v1(
      '[{"period_key":"current","channel":"face_to_face","contributor_key":"a"}]'::jsonb
    );
    RAISE EXCEPTION 'incomplete management contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_contact_session_grid_v1(
      '[{"period_key":"future","channel":"face_to_face","contributor_key":"a","unit_count":1}]'::jsonb
    );
    RAISE EXCEPTION 'unknown management period was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_contact_session_grid_v1(
      '[{"period_key":"current","channel":"unknown","contributor_key":"a","unit_count":1}]'::jsonb
    );
    RAISE EXCEPTION 'unknown management channel was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_contact_session_grid_v1(
      '[{"period_key":"current","channel":"face_to_face","contributor_key":"a","unit_count":0}]'::jsonb
    );
    RAISE EXCEPTION 'non-positive management contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_contact_session_grid_v1(
      '[{"period_key":"current","channel":"face_to_face","contributor_key":"a","unit_count":1},{"period_key":"current","channel":"face_to_face","contributor_key":"a","unit_count":1}]'::jsonb
    );
    RAISE EXCEPTION 'duplicate management contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
