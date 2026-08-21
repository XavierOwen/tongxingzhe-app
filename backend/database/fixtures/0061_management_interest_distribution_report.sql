-- Synthetic fixture for the private management interest distribution report.
-- Every row is rolled back.  The shared CSV contains only aggregate,
-- non-identity contributions used by the policy contract.
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE management_interest_distribution_fixture (
  scenario text NOT NULL,
  period_key text NOT NULL,
  interest_level integer NOT NULL,
  contributor_key text NOT NULL,
  unit_count integer NOT NULL
);

\copy management_interest_distribution_fixture FROM 'backend/database/fixtures/shared/management_interest_distribution_v1.csv' WITH (FORMAT csv, HEADER MATCH)

DO $policy_fixture$
DECLARE
  scenario_name text;
  contributions jsonb;
  expected_unsafe_period text;
  large_safe_cell_count integer;
BEGIN
  FOREACH scenario_name IN ARRAY ARRAY[
    'safe',
    'small_sample',
    'two_contributors',
    'dominant',
    'cross_report_total'
  ] LOOP
    SELECT jsonb_agg(
      jsonb_build_object(
        'period_key', period_key,
        'interest_level', interest_level,
        'contributor_key', contributor_key,
        'unit_count', unit_count
      ) ORDER BY period_key, interest_level, contributor_key
    ) INTO contributions
    FROM management_interest_distribution_fixture
    WHERE scenario = scenario_name;

    IF contributions IS NULL THEN
      RAISE EXCEPTION 'interest distribution fixture scenario is missing: %',
        scenario_name;
    END IF;

    CREATE TEMP TABLE protected_result ON COMMIT DROP AS
    SELECT *
    FROM app_private.protect_management_interest_distribution_grid_v1(
      contributions
    );

    IF (SELECT count(*) FROM protected_result) <> 10
      OR (SELECT count(DISTINCT cell_order) FROM protected_result) <> 10
      OR (SELECT min(cell_order) FROM protected_result) <> 0
      OR (SELECT max(cell_order) FROM protected_result) <> 9
      OR EXISTS (
        SELECT 1 FROM protected_result
        WHERE privacy_status NOT IN ('displayed', 'suppressed')
          OR (privacy_status = 'suppressed' AND value_count IS NOT NULL)
          OR (privacy_status = 'displayed' AND value_count IS NULL)
          OR cell_order <> CASE period_key
            WHEN 'previous' THEN 0
            WHEN 'current' THEN 5
          END + interest_level
      )
    THEN
      RAISE EXCEPTION 'invalid protected interest grid for scenario %',
        scenario_name;
    END IF;

    expected_unsafe_period = CASE
      WHEN scenario_name = 'safe' THEN NULL
      ELSE 'current'
    END;

    IF expected_unsafe_period IS NULL THEN
      IF EXISTS (
        SELECT 1 FROM protected_result
        WHERE privacy_status <> 'displayed' OR value_count <> 10
      ) THEN
        RAISE EXCEPTION 'safe interest distribution fixture was suppressed';
      END IF;
    ELSE
      IF EXISTS (
        SELECT 1 FROM protected_result
        WHERE period_key = 'previous'
          AND (privacy_status <> 'displayed' OR value_count <> 10)
      ) OR EXISTS (
        SELECT 1 FROM protected_result
        WHERE period_key = expected_unsafe_period
          AND (privacy_status <> 'suppressed' OR value_count IS NOT NULL)
      ) THEN
        RAISE EXCEPTION
          'whole-period interest suppression is incorrect for scenario %',
          scenario_name;
      END IF;
    END IF;

    DROP TABLE protected_result;
  END LOOP;

  -- A displayed aggregate may exceed one PostgreSQL integer because the
  -- integer bound applies to each contributor, not to the protected cell.
  -- The result must stay exact through the shared 2^53-1 output contract.
  SELECT count(*)
  INTO large_safe_cell_count
  FROM app_private.protect_management_interest_distribution_grid_v1(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'period_key', 'current',
          'interest_level', level_row,
          'contributor_key', contributor_row.contributor_key,
          'unit_count', 2147483647
        ) ORDER BY level_row, contributor_row.contributor_key
      )
      FROM generate_series(0, 4) AS level_row
      CROSS JOIN (
        VALUES ('large-a'), ('large-b'), ('large-c')
      ) AS contributor_row(contributor_key)
    )
  ) AS protected
  WHERE protected.period_key = 'current'
    AND protected.privacy_status = 'displayed'
    AND protected.value_count = 6442450941;
  IF large_safe_cell_count <> 5 THEN
    RAISE EXCEPTION
      'large safe interest aggregates were not preserved exactly';
  END IF;

  CREATE TEMP TABLE empty_protected_result ON COMMIT DROP AS
  SELECT *
  FROM app_private.protect_management_interest_distribution_grid_v1(
    '[]'::jsonb
  );
  IF (SELECT count(*) FROM empty_protected_result) <> 10
    OR EXISTS (
      SELECT 1 FROM empty_protected_result
      WHERE privacy_status <> 'suppressed' OR value_count IS NOT NULL
    )
  THEN
    RAISE EXCEPTION 'empty interest distribution did not fail closed';
  END IF;
  DROP TABLE empty_protected_result;

  -- Every structural input failure must reject the whole policy call.
  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"current","interest_level":0,"contributor_key":"a"}]'::jsonb
    );
    RAISE EXCEPTION 'incomplete interest contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"future","interest_level":0,"contributor_key":"a","unit_count":1}]'::jsonb
    );
    RAISE EXCEPTION 'unknown interest period was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"current","interest_level":5,"contributor_key":"a","unit_count":1}]'::jsonb
    );
    RAISE EXCEPTION 'unknown interest level was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"current","interest_level":0,"contributor_key":"a","unit_count":0}]'::jsonb
    );
    RAISE EXCEPTION 'non-positive interest contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"current","interest_level":0,"contributor_key":"a","unit_count":1.5}]'::jsonb
    );
    RAISE EXCEPTION 'fractional interest contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"current","interest_level":0,"contributor_key":"a","unit_count":1,"extra":true}]'::jsonb
    );
    RAISE EXCEPTION 'extra interest contribution field was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.protect_management_interest_distribution_grid_v1(
      '[{"period_key":"current","interest_level":0,"contributor_key":"a","unit_count":1},{"period_key":"current","interest_level":0,"contributor_key":"a","unit_count":1}]'::jsonb
    );
    RAISE EXCEPTION 'duplicate interest contribution was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$policy_fixture$;

-- A synthetic cross-report disclosure case: current-period channel and
-- current-city totals can pass their own policies while interest level 0 has
-- only nine contact sessions.  The interest policy must still close the
-- entire current five-level period.
DO $cross_report_fixture$
DECLARE
  channel_document jsonb;
  city_document jsonb;
  channel_total text;
  city_total text;
  interest_suppressed integer;
  interest_total integer;
  interest_level_zero integer;
  interest_other_levels integer;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'category_key', protected.category_key,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  )
  INTO channel_document
  FROM app_private.protect_management_contact_session_grid_v1(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'period_key', period_key,
          'channel', channel,
          'contributor_key', contributor_key,
          'unit_count', unit_count
        ) ORDER BY period_key, channel, contributor_key
      )
      FROM (
        VALUES
          ('current', 'face_to_face', 'a', 5),
          ('current', 'face_to_face', 'b', 3),
          ('current', 'face_to_face', 'c', 2),
          ('current', 'voice_call', 'a', 5),
          ('current', 'voice_call', 'b', 3),
          ('current', 'voice_call', 'c', 2),
          ('current', 'video_call', 'a', 5),
          ('current', 'video_call', 'b', 3),
          ('current', 'video_call', 'c', 2),
          ('current', 'instant_text', 'a', 5),
          ('current', 'instant_text', 'b', 3),
          ('current', 'instant_text', 'c', 2),
          ('current', 'asynchronous_message', 'a', 5),
          ('current', 'asynchronous_message', 'b', 3),
          ('current', 'asynchronous_message', 'c', 2),
          ('current', 'mixed', 'a', 5),
          ('current', 'mixed', 'b', 3),
          ('current', 'mixed', 'c', 2),
          ('current', 'other_direct', 'a', 5),
          ('current', 'other_direct', 'b', 3),
          ('current', 'other_direct', 'c', 2)
      ) AS contribution(period_key, channel, contributor_key, unit_count)
    )
  ) AS protected;

  SELECT item->>'value_count'
  INTO channel_total
  FROM jsonb_array_elements(channel_document) AS cell(item)
  WHERE item->>'period_key' = 'current'
    AND item->>'category_key' = 'all'
    AND item->>'privacy_status' = 'displayed';

  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', protected.period_key,
      'city_id', protected.city_id,
      'cell_order', protected.cell_order,
      'value_count', protected.value_count,
      'privacy_status', protected.privacy_status
    ) ORDER BY protected.cell_order
  )
  INTO city_document
  FROM app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb_build_array('cross-report-city'),
    jsonb_build_array(
      jsonb_build_object('period_key', 'current', 'city_id',
        'cross-report-city', 'contributor_key', 'a', 'unit_count', 30),
      jsonb_build_object('period_key', 'current', 'city_id',
        'cross-report-city', 'contributor_key', 'b', 'unit_count', 22),
      jsonb_build_object('period_key', 'current', 'city_id',
        'cross-report-city', 'contributor_key', 'c', 'unit_count', 18)
    )
  ) AS protected;

  SELECT item->>'value_count'
  INTO city_total
  FROM jsonb_array_elements(city_document) AS cell(item)
  WHERE item->>'period_key' = 'current'
    AND item->>'city_id' = 'cross-report-city'
    AND item->>'privacy_status' = 'displayed';

  SELECT count(*)
  INTO interest_suppressed
  FROM app_private.protect_management_interest_distribution_grid_v1(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'period_key', period_key,
          'interest_level', interest_level,
          'contributor_key', contributor_key,
          'unit_count', unit_count
        ) ORDER BY period_key, interest_level, contributor_key
      )
      FROM management_interest_distribution_fixture
      WHERE scenario = 'cross_report_total'
    )
  ) AS protected
  WHERE protected.period_key = 'current'
    AND protected.privacy_status = 'suppressed'
    AND protected.value_count IS NULL;

  SELECT
    sum(fixture.unit_count),
    sum(fixture.unit_count) FILTER (WHERE fixture.interest_level = 0),
    sum(fixture.unit_count) FILTER (WHERE fixture.interest_level > 0)
  INTO interest_total, interest_level_zero, interest_other_levels
  FROM management_interest_distribution_fixture AS fixture
  WHERE fixture.scenario = 'cross_report_total'
    AND fixture.period_key = 'current';

  IF channel_total IS DISTINCT FROM '70'
    OR city_total IS DISTINCT FROM '70'
    OR interest_suppressed <> 5
    OR interest_total <> 70
    OR interest_level_zero <> 9
    OR interest_other_levels <> 61
  THEN
    RAISE EXCEPTION
      'cross-report disclosure fixture is incorrect: channel %, city %, interest suppressed %, interest total %, level 0 %, other levels %',
      channel_total, city_total, interest_suppressed, interest_total,
      interest_level_zero, interest_other_levels;
  END IF;
END
$cross_report_fixture$;

-- End-to-end synthetic project.  Two complete UTC weeks contain exactly ten
-- sessions per level.  The additional rows cover source filters and are not
-- allowed to alter the result.
INSERT INTO app_data.app_users (app_user_id)
VALUES
  ('6a610000-0000-4000-8000-000000000001'::uuid),
  ('6a610000-0000-4000-8000-000000000002'::uuid),
  ('6a610000-0000-4000-8000-000000000003'::uuid);

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name
) VALUES
  (
    '6a620000-0000-4000-8000-000000000001'::uuid,
    'organization',
    '6AV synthetic management workspace'
  );

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name
) VALUES
  (
    '6a630000-0000-4000-8000-000000000001'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6AV interest report project'
  ),
  (
    '6a630000-0000-4000-8000-000000000002'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6AV other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
) VALUES
  (
    '6a640000-0000-4000-8000-000000000001'::uuid,
    '6a630000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '6a640000-0000-4000-8000-000000000002'::uuid,
    '6a630000-0000-4000-8000-000000000002'::uuid,
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
  '6av-contact-' || period_row.period_key || '-' || level_row::text || '-'
    || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '6a610000-0000-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '6a610000-0000-4000-8000-000000000002'::uuid
    ELSE '6a610000-0000-4000-8000-000000000003'::uuid
  END,
  '6a620000-0000-4000-8000-000000000001'::uuid,
  '6a630000-0000-4000-8000-000000000001'::uuid,
  '6a640000-0000-4000-8000-000000000001'::uuid,
  CASE
    WHEN period_row.period_key = 'previous'
      AND level_row = 0
      AND series_row = 1
      THEN '2026-06-01 00:00:00+00'::timestamptz
    ELSE period_row.occurred_at_utc + (level_row * interval '1 hour')
      + (series_row * interval '1 minute')
  END,
  'UTC',
  CASE
    WHEN period_row.period_key = 'previous'
      AND level_row = 0
      AND series_row = 1
      THEN '2026-06-01 01:00:00+00'::timestamptz
    ELSE period_row.occurred_at_utc + (level_row * interval '1 hour')
      + (series_row * interval '1 minute') + interval '1 hour'
  END,
  'voice_call',
  'not_applicable',
  1,
  level_row
FROM (
  VALUES
    ('previous'::text, '2026-06-02 12:00:00+00'::timestamptz),
    ('current'::text, '2026-06-09 12:00:00+00'::timestamptz)
) AS period_row(period_key, occurred_at_utc)
CROSS JOIN generate_series(0, 4) AS level_row
CROSS JOIN generate_series(1, 10) AS series_row;

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
    '6av-voided',
    '6a610000-0000-4000-8000-000000000001'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6a630000-0000-4000-8000-000000000001'::uuid,
    '6a640000-0000-4000-8000-000000000001'::uuid,
    '2026-06-10 12:00:00+00'::timestamptz,
    'UTC',
    '2026-06-10 13:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    0,
    'voided'
  ),
  (
    '6av-late-submission',
    '6a610000-0000-4000-8000-000000000001'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6a630000-0000-4000-8000-000000000001'::uuid,
    '6a640000-0000-4000-8000-000000000001'::uuid,
    '2026-06-10 13:00:00+00'::timestamptz,
    'UTC',
    '2026-06-18 00:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    0,
    'active'
  ),
  (
    '6av-left-boundary',
    '6a610000-0000-4000-8000-000000000001'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6a630000-0000-4000-8000-000000000001'::uuid,
    '6a640000-0000-4000-8000-000000000001'::uuid,
    '2026-05-31 23:59:59+00'::timestamptz,
    'UTC',
    '2026-06-01 00:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    0,
    'active'
  ),
  (
    '6av-right-boundary',
    '6a610000-0000-4000-8000-000000000001'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6a630000-0000-4000-8000-000000000001'::uuid,
    '6a640000-0000-4000-8000-000000000001'::uuid,
    '2026-06-15 00:00:00+00'::timestamptz,
    'UTC',
    '2026-06-15 01:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    0,
    'active'
  ),
  (
    '6av-other-project',
    '6a610000-0000-4000-8000-000000000001'::uuid,
    '6a620000-0000-4000-8000-000000000001'::uuid,
    '6a630000-0000-4000-8000-000000000002'::uuid,
    '6a640000-0000-4000-8000-000000000002'::uuid,
    '2026-06-10 14:00:00+00'::timestamptz,
    'UTC',
    '2026-06-10 15:00:00+00'::timestamptz,
    'voice_call',
    'not_applicable',
    1,
    0,
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
  '6av-attempt',
  '6a610000-0000-4000-8000-000000000001'::uuid,
  '6a620000-0000-4000-8000-000000000001'::uuid,
  '6a630000-0000-4000-8000-000000000001'::uuid,
  '2026-06-10 15:00:00+00'::timestamptz,
  'UTC',
  '2026-06-10 16:00:00+00'::timestamptz,
  'voice_call'
);

INSERT INTO app_data.contact_drafts (
  draft_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  created_at_utc,
  updated_at_utc,
  current_revision,
  source_device_id,
  content
) VALUES (
  '6av-draft',
  '6a610000-0000-4000-8000-000000000001'::uuid,
  '6a620000-0000-4000-8000-000000000001'::uuid,
  '6a630000-0000-4000-8000-000000000001'::uuid,
  '6a640000-0000-4000-8000-000000000001'::uuid,
  '2026-06-10 17:00:00+00'::timestamptz,
  '2026-06-10 17:00:00+00'::timestamptz,
  1,
  '6av-fixture-device',
  jsonb_build_object('interestLevel', 0)
);

DO $report_fixture$
DECLARE
  report_document jsonb;
  report_text text;
  expected_cell_orders integer[];
BEGIN
  report_document =
    app_private.execute_management_interest_distribution_report_v1(
      '6a630000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz
    );

  IF NOT report_document ?& ARRAY[
    'report_id',
    'report_version',
    'metric_id',
    'metric_version',
    'statistical_unit',
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
    'statistical_unit',
    'dimension',
    'query_fingerprint',
    'privacy_policy',
    'source_scope',
    'project_id',
    'periods',
    'cells'
  ] <> '{}'::jsonb
    OR report_document->>'report_id'
      <> 'contact_sessions_by_interest_level_two_periods'
    OR report_document->>'report_version' <> '1'
    OR report_document->>'metric_id' <> 'interest_distribution'
    OR report_document->>'metric_version' <> '1'
    OR report_document->>'statistical_unit' <> 'contact_session'
    OR report_document->>'dimension' <> 'interest_level'
    OR report_document->>'query_fingerprint'
      <> 'management-report:contact_sessions_by_interest_level_two_periods:v1'
    OR report_document->>'privacy_policy'
      <> 'management_interest_distribution_privacy_v1'
    OR report_document->>'source_scope'
      <> 'backend_accepted_active_contacts_current_revision'
    OR report_document->>'project_id' <>
      '6a630000-0000-4000-8000-000000000001'
    OR report_document->'periods'->>'period_boundary_id'
      <> 'iso_week_monday_v1'
    OR report_document->'periods'->>'reporting_time_zone' <> 'UTC'
    OR report_document->'periods'->>'data_cutoff_utc'
      <> '2026-06-17T12:34:56.000Z'
    OR jsonb_array_length(report_document->'cells') <> 10
  THEN
    RAISE EXCEPTION 'private interest report metadata is incorrect: %',
      report_document;
  END IF;

  SELECT array_agg(
    (cell->>'cell_order')::integer ORDER BY ordinal
  ) INTO expected_cell_orders
  FROM jsonb_array_elements(report_document->'cells')
    WITH ORDINALITY AS element(cell, ordinal);
  IF expected_cell_orders <> ARRAY[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  THEN
    RAISE EXCEPTION 'private interest report cell order is unstable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(report_document->'cells') AS element(cell)
    WHERE cell->>'privacy_status' <> 'displayed'
      OR (cell->>'value_count')::integer <> 10
      OR cell - ARRAY[
        'period_key',
        'interest_level',
        'cell_order',
        'value_count',
        'privacy_status'
      ] <> '{}'::jsonb
  ) THEN
    RAISE EXCEPTION 'private interest report cells are not complete and minimal';
  END IF;

  report_text = report_document::text;
  IF report_text ~ '(app_user_id|contributor_key|contributor_count|max_contribution|contact_id|channel|place_name|latitude|longitude|6av-contact-|6a610000-0000-4000-8000-00000000000[1-3])'
  THEN
    RAISE EXCEPTION 'private interest report exposed source details';
  END IF;

  BEGIN
    PERFORM app_private.execute_management_interest_distribution_report_v1(
      '6a630000-0000-4000-8000-000000000099'::uuid,
      'UTC',
      '2026-06-17 12:34:56+00'::timestamptz
    );
    RAISE EXCEPTION 'unknown management interest report project was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.canonicalize_management_interest_distribution_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_channel_two_periods',
        'report_version', 1
      )
    );
    RAISE EXCEPTION 'wrong management interest report identity was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.execute_management_interest_distribution_report_v1(
      '6a630000-0000-4000-8000-000000000001'::uuid,
      'CST',
      '2026-06-17 12:34:56+00'::timestamptz
    );
    RAISE EXCEPTION 'invalid management interest report time zone was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.execute_management_interest_distribution_report_v1(
      '6a630000-0000-4000-8000-000000000001'::uuid,
      'UTC',
      NULL
    );
    RAISE EXCEPTION 'null management interest report cutoff was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$report_fixture$;

ROLLBACK;
