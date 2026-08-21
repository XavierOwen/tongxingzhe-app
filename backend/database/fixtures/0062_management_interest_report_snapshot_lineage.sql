-- Synthetic fixture for the private management interest snapshot lineage.
--
-- The fixture is deliberately self-contained.  0061's fixture is rolled back
-- in its own psql process, so this test recreates the authorized project and
-- ten-cell interest report.  All rows are rolled back at the end.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b110000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name
) VALUES (
  '6b120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AW interest snapshot workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6b130000-0000-4000-8000-000000000001'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6AW interest snapshot project'
  ),
  (
    '6b130000-0000-4000-8000-000000000002'::uuid,
    '6b120000-0000-4000-8000-000000000001'::uuid,
    '6AW other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES
  (
    '6b140000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    '6b140000-0000-4000-8000-000000000002'::uuid,
    '6b130000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '6b160000-0000-4000-8000-000000000001'::uuid,
  '6b120000-0000-4000-8000-000000000001'::uuid,
  '6b110000-0000-4000-8000-000000000001'::uuid,
  clock_timestamp() - interval '30 days',
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6b170000-0000-4000-8000-000000000001'::uuid,
    '6b160000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b170000-0000-4000-8000-000000000002'::uuid,
    '6b160000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '6b180000-0000-4000-8000-000000000001'::uuid,
    '6b170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    '6b180000-0000-4000-8000-000000000002'::uuid,
    '6b170000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b150000-0000-4000-8000-000000000001'::uuid,
  '6b110000-0000-4000-8000-000000000001'::uuid,
  '6b130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6aw_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

-- Ten sessions per period and interest level, distributed 5/3/2 across three
-- contributors.  This is exactly the complete protected 6AV document which 6AW must
-- revalidate before accepting it into a snapshot.
CREATE TEMP TABLE fixture_6aw_expected_contacts AS
SELECT
  format(
    '6aw-contact-%s-%s-%s-%s',
    period_row.period_key,
    level_row,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  level_row AS interest_level,
  contributor_row.contributor_number,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 minute'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 minute'
  END AS occurred_at_utc
FROM fixture_6aw_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN generate_series(0, 4) AS level_row
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(1, contributor_row.unit_count)
  AS unit_row(unit_number);

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
  expected.contact_id,
  CASE expected.contributor_number
    WHEN 1 THEN '6b110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6b110000-0000-4000-8000-000000000002'::uuid
    ELSE '6b110000-0000-4000-8000-000000000003'::uuid
  END,
  '6b120000-0000-4000-8000-000000000001'::uuid,
  '6b130000-0000-4000-8000-000000000001'::uuid,
  '6b140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc,
  'UTC',
  expected.occurred_at_utc,
  'voice_call',
  'not_applicable',
  1,
  expected.interest_level
FROM fixture_6aw_expected_contacts AS expected;

-- The release must copy the source watermark observed with the executor, not
-- a caller-provided constant.  One committed feed row is enough to prove the
-- snapshot carries a non-zero change sequence.
INSERT INTO app_data.change_feed (
  app_user_id,
  workspace_id,
  project_id,
  aggregate_id,
  revision_number,
  change_type
) VALUES (
  '6b110000-0000-4000-8000-000000000001'::uuid,
  '6b120000-0000-4000-8000-000000000001'::uuid,
  '6b130000-0000-4000-8000-000000000001'::uuid,
  '6aw-initial-watermark',
  1,
  'contact.submitted'
);

DO $fixture_6aw_validator$
DECLARE
  report_document jsonb;
  mutated_cells jsonb;
  large_count_cells jsonb;
  mixed_privacy_cells jsonb;
  oversized_order_cells jsonb;
  swapped_cells jsonb;
  identity_mutation record;
  mutated_report jsonb;
BEGIN
  report_document := app_private.execute_management_interest_distribution_report_v1(
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'UTC',
    (SELECT data_cutoff_utc FROM fixture_6aw_report_context)
  );
  PERFORM app_private.validate_management_interest_report_document_v1(
    report_document
  );

  IF report_document->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_interest_level_two_periods'
    OR report_document->>'metric_id' IS DISTINCT FROM 'interest_distribution'
    OR report_document->>'dimension' IS DISTINCT FROM 'interest_level'
    OR jsonb_array_length(report_document->'cells') <> 10
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(report_document->'cells') AS item(value)
      WHERE (value->>'cell_order')::integer <> (
        CASE value->>'period_key'
          WHEN 'previous' THEN 0
          ELSE 5
        END + (value->>'interest_level')::integer
      )
        OR value->>'privacy_status' <> 'displayed'
        OR (value->>'value_count')::bigint <> 10
    )
  THEN
    RAISE EXCEPTION 'valid 6AW interest document has the wrong ten-cell shape: %',
      report_document;
  END IF;

  -- The validator accepts only the canonical fixed document, not a caller
  -- supplied identity, sensitive field, or altered grid.
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      report_document || jsonb_build_object('unexpected', true)
    );
    RAISE EXCEPTION '6AW validator accepted an extra top-level field';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{report_id}',
        to_jsonb('contact_sessions_by_channel_two_periods'::text))
    );
    RAISE EXCEPTION '6AW validator accepted a channel report identity';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  FOR identity_mutation IN
    SELECT *
    FROM (
      VALUES
        ('metric_id', to_jsonb('other_metric'::text)),
        ('metric_version', '2'::jsonb),
        ('statistical_unit', to_jsonb('person'::text)),
        ('dimension', to_jsonb('other_dimension'::text)),
        ('query_fingerprint', to_jsonb('other-query'::text)),
        ('privacy_policy', to_jsonb('other-policy'::text)),
        ('source_scope', to_jsonb('other-source'::text))
    ) AS mutation(field_name, field_value)
  LOOP
    mutated_report := jsonb_set(
      report_document,
      ARRAY[identity_mutation.field_name],
      identity_mutation.field_value
    );
    BEGIN
      PERFORM app_private.validate_management_interest_report_document_v1(
        mutated_report
      );
      RAISE EXCEPTION
        '6AW validator accepted altered fixed identity field: %',
        identity_mutation.field_name;
    EXCEPTION WHEN invalid_parameter_value THEN
      NULL;
    END;
  END LOOP;

  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      report_document || jsonb_build_object('result_status', 'unavailable')
    );
    RAISE EXCEPTION '6AW validator accepted an unavailable-shaped document';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells,0,contact_id}',
        to_jsonb('6aw-sensitive-contact'::text))
    );
    RAISE EXCEPTION '6AW validator accepted a sensitive cell field';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  SELECT jsonb_agg(
    CASE cell.ordinality
      WHEN 1 THEN report_document->'cells'->1
      WHEN 2 THEN report_document->'cells'->0
      ELSE cell.value
    END
    ORDER BY cell.ordinality
  )
  INTO swapped_cells
  FROM jsonb_array_elements(report_document->'cells')
    WITH ORDINALITY AS cell(value, ordinality);
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', swapped_cells)
    );
    RAISE EXCEPTION '6AW validator accepted an out-of-order grid';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', (report_document->'cells') - 0)
    );
    RAISE EXCEPTION '6AW validator accepted a nine-cell grid';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  mutated_cells := jsonb_set(
    report_document->'cells',
    '{1}',
    report_document->'cells'->0
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AW validator accepted a duplicate grid cell';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  mutated_cells := jsonb_set(
    report_document->'cells',
    '{0,interest_level}',
    '5'::jsonb
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AW validator accepted an invalid interest level';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  mutated_cells := jsonb_set(
    report_document->'cells',
    '{0,value_count}',
    '9'::jsonb
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AW validator accepted an unsafe displayed count';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(
        report_document,
        '{periods,period_boundary_id}',
        to_jsonb('other_boundary'::text)
      )
    );
    RAISE EXCEPTION '6AW validator accepted a different period boundary';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- Every period has one privacy state.  A mixed displayed/suppressed period
  -- is invalid even when the individual cell values look well formed.
  mixed_privacy_cells := jsonb_set(
    report_document->'cells',
    '{0}',
    jsonb_set(
      jsonb_set(report_document->'cells'->0, '{privacy_status}',
        to_jsonb('suppressed'::text)),
      '{value_count}', 'null'::jsonb
    )
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', mixed_privacy_cells)
    );
    RAISE EXCEPTION '6AW validator accepted mixed privacy states in one period';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  mutated_cells := jsonb_set(
    report_document->'cells',
    '{0,value_count}', '10'::jsonb
  );
  mutated_cells := jsonb_set(
    mutated_cells,
    '{0,privacy_status}', to_jsonb('suppressed'::text)
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', mutated_cells)
    );
    RAISE EXCEPTION '6AW validator accepted non-null suppressed count';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  large_count_cells := jsonb_set(
    report_document->'cells',
    '{0,value_count}', to_jsonb(9007199254740992::numeric)
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', large_count_cells)
    );
    RAISE EXCEPTION '6AW validator accepted a count above 2^53-1';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  oversized_order_cells := jsonb_set(
    report_document->'cells',
    '{0,cell_order}', to_jsonb(2147483648::numeric)
  );
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(
      jsonb_set(report_document, '{cells}', oversized_order_cells)
    );
    RAISE EXCEPTION '6AW validator accepted a cell order above int32';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
END
$fixture_6aw_validator$;

DO $fixture_6aw_lineage$
DECLARE
  baseline_document jsonb;
  later_document jsonb;
  no_shared_document jsonb;
  pair_result jsonb;
  release_result jsonb;
  replay_result jsonb;
  blocked_result jsonb;
  one_period_document jsonb;
  mutated_document jsonb;
  baseline_snapshot_id uuid;
  snapshot_count bigint;
  attempt_count bigint;
  baseline_source_sequence bigint;
  current_cutoff timestamptz;
  future_cutoff timestamptz;
  one_period_cutoff timestamptz;
  cross_project_snapshot_count bigint;
  cross_project_attempt_count bigint;
BEGIN
  current_cutoff := (SELECT data_cutoff_utc FROM fixture_6aw_report_context);
  baseline_document :=
    app_private.execute_management_interest_distribution_report_v1(
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'UTC', current_cutoff
    );

  pair_result := app_private.assess_management_interest_report_pair_release_v1(
    baseline_document, baseline_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'release_lineage_context_changed')
    OR pair_result->>'assessed_cell_count' IS DISTINCT FROM '10'
  THEN
    RAISE EXCEPTION 'same-cutoff interest pair was not blocked: %', pair_result;
  END IF;

  release_result := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR release_result->>'released_snapshot_id' IS NULL
    OR release_result->>'release_lineage_id' IS DISTINCT FROM
      'management-interest-report:contact_sessions_by_interest_level_two_periods'
    OR release_result ? 'protected_report'
    OR release_result ? 'cells'
  THEN
    RAISE EXCEPTION '6AW baseline release contract failed: %', release_result;
  END IF;
  baseline_snapshot_id := (release_result->>'released_snapshot_id')::uuid;

  SELECT snapshot.source_change_sequence
  INTO STRICT baseline_source_sequence
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.snapshot_id = baseline_snapshot_id;
  IF baseline_source_sequence <= 0 THEN
    RAISE EXCEPTION '6AW snapshot did not preserve the source watermark';
  END IF;

  SELECT count(*) INTO snapshot_count
  FROM app_private.management_report_snapshots
  WHERE project_id = '6b130000-0000-4000-8000-000000000001'::uuid
    AND release_lineage_id =
      'management-interest-report:contact_sessions_by_interest_level_two_periods';
  SELECT count(*) INTO attempt_count
  FROM app_private.management_interest_report_release_attempts
  WHERE project_id = '6b130000-0000-4000-8000-000000000001'::uuid;

  replay_result := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF replay_result IS DISTINCT FROM release_result
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE project_id = '6b130000-0000-4000-8000-000000000001'::uuid
          AND release_lineage_id =
            'management-interest-report:contact_sessions_by_interest_level_two_periods')
        <> snapshot_count
    OR (SELECT count(*)
        FROM app_private.management_interest_report_release_attempts
        WHERE project_id = '6b130000-0000-4000-8000-000000000001'::uuid)
        <> attempt_count
  THEN
    RAISE EXCEPTION '6AW same-request replay was not exact and idempotent';
  END IF;

  -- The same request UUID cannot be replayed for another project.  The
  -- conflict must fail before it creates a project-two attempt or snapshot.
  SELECT count(*)
  INTO cross_project_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = '6b130000-0000-4000-8000-000000000002'::uuid;
  SELECT count(*)
  INTO cross_project_attempt_count
  FROM app_private.management_interest_report_release_attempts AS attempt
  WHERE attempt.project_id = '6b130000-0000-4000-8000-000000000002'::uuid;
  BEGIN
    PERFORM app_private.release_management_interest_report_snapshot_v1(
      '6b800000-0000-4000-8000-000000000001'::uuid,
      '6b110000-0000-4000-8000-000000000001'::uuid,
      '6b130000-0000-4000-8000-000000000002'::uuid,
      'contact_sessions_by_interest_level_two_periods', 1
    );
    RAISE EXCEPTION '6AW same-request cross-project replay was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  IF (
    SELECT count(*)
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.project_id =
      '6b130000-0000-4000-8000-000000000002'::uuid
  ) <> cross_project_snapshot_count
  OR (
    SELECT count(*)
    FROM app_private.management_interest_report_release_attempts AS attempt
    WHERE attempt.project_id =
      '6b130000-0000-4000-8000-000000000002'::uuid
  ) <> cross_project_attempt_count
  THEN
    RAISE EXCEPTION '6AW cross-project idempotency conflict persisted release state';
  END IF;

  PERFORM pg_sleep(0.01);
  later_document :=
    app_private.execute_management_interest_distribution_report_v1(
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'UTC', clock_timestamp()
    );
  pair_result := app_private.assess_management_interest_report_pair_release_v1(
    baseline_document, later_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'approved'
    OR pair_result->>'shared_period_count' IS DISTINCT FROM '2'
    OR pair_result->>'assessed_cell_count' IS DISTINCT FROM '10'
  THEN
    RAISE EXCEPTION 'stable later interest pair was not approved: %', pair_result;
  END IF;

  -- A normal rolling week shares only the earlier document's current period;
  -- the ten-cell contract therefore assesses exactly five cells, not ten.
  one_period_cutoff :=
    (baseline_document->'periods'->'current_period'->>'until_utc')::timestamptz
      + interval '8 days';
  one_period_document :=
    app_private.execute_management_interest_distribution_report_v1(
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'UTC', one_period_cutoff
    );
  pair_result := app_private.assess_management_interest_report_pair_release_v1(
    baseline_document, one_period_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'approved'
    OR pair_result->>'shared_period_count' IS DISTINCT FROM '1'
    OR pair_result->>'assessed_cell_count' IS DISTINCT FROM '5'
  THEN
    RAISE EXCEPTION 'one-period interest pair did not assess five cells: %',
      pair_result;
  END IF;

  release_result := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000002'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'approved'
    OR (release_result->>'compared_snapshot_id')::uuid
      IS DISTINCT FROM baseline_snapshot_id
  THEN
    RAISE EXCEPTION '6AW rolling release lost its previous pointer: %', release_result;
  END IF;

  -- Reversing the pair is the stable earlier-cutoff guard.
  pair_result := app_private.assess_management_interest_report_pair_release_v1(
    later_document, baseline_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'release_lineage_context_changed')
  THEN
    RAISE EXCEPTION 'earlier interest cutoff was not blocked: %', pair_result;
  END IF;

  -- A displayed value change is distinct from a privacy-state change.  The
  -- candidate remains a valid ten-cell document but cannot be released.
  mutated_document := jsonb_set(
    later_document,
    '{cells,0,value_count}',
    to_jsonb(11)
  );
  PERFORM app_private.validate_management_interest_report_document_v1(
    mutated_document
  );
  pair_result := app_private.assess_management_interest_report_pair_release_v1(
    baseline_document, mutated_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'shared_displayed_value_changed')
  THEN
    RAISE EXCEPTION 'displayed interest value change was not blocked: %',
      pair_result;
  END IF;

  future_cutoff :=
    (baseline_document->'periods'->'current_period'->>'until_utc')::timestamptz
      + interval '15 days';
  no_shared_document :=
    app_private.execute_management_interest_distribution_report_v1(
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'UTC', future_cutoff
    );
  pair_result := app_private.assess_management_interest_report_pair_release_v1(
    baseline_document, no_shared_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (pair_result->'reason_codes' ? 'no_shared_period')
  THEN
    RAISE EXCEPTION 'no-shared-period interest pair was not blocked: %', pair_result;
  END IF;

  -- One current-period level becomes unsafe.  The complete period must be
  -- hidden and the release attempt must retain no candidate values.
  UPDATE app_data.contacts
  SET lifecycle_status = 'voided'
  WHERE contact_id = '6aw-contact-current-0-1-1';
  PERFORM pg_sleep(0.01);
  blocked_result := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000003'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (blocked_result->'reason_codes' ? 'shared_cell_privacy_status_changed')
    OR blocked_result ? 'protected_report'
    OR blocked_result ? 'cells'
  THEN
    RAISE EXCEPTION '6AW privacy-blocked attempt was not value-free: %', blocked_result;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_interest_report_release_attempts AS attempt
    WHERE attempt.release_request_id =
        '6b800000-0000-4000-8000-000000000003'::uuid
      AND attempt.result_document::text ~
        '(6aw-contact-|contributor|contact_id)'
  ) THEN
    RAISE EXCEPTION '6AW blocked attempt stored candidate report material';
  END IF;

  -- A request UUID claimed by the channel family cannot be reused for an
  -- interest release, even though both contracts use the same snapshot store.
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    '6b800000-0000-4000-8000-000000000009'::uuid,
    'channel_management_report_snapshot_release'
  );
  BEGIN
    PERFORM app_private.release_management_interest_report_snapshot_v1(
      '6b800000-0000-4000-8000-000000000009'::uuid,
      '6b110000-0000-4000-8000-000000000001'::uuid,
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_interest_level_two_periods', 1
    );
    RAISE EXCEPTION '6AW interest release reused a channel claim UUID';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    '6b800000-0000-4000-8000-00000000000a'::uuid,
    'current_city_management_report_snapshot_release'
  );
  BEGIN
    PERFORM app_private.release_management_interest_report_snapshot_v1(
      '6b800000-0000-4000-8000-00000000000a'::uuid,
      '6b110000-0000-4000-8000-000000000001'::uuid,
      '6b130000-0000-4000-8000-000000000001'::uuid,
      'contact_sessions_by_interest_level_two_periods', 1
    );
    RAISE EXCEPTION '6AW interest release reused a current-city claim UUID';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- A new effective time-zone revision blocks the next release before it can
  -- generate or persist another protected document.
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '6b850000-0000-4000-8000-000000000001'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    1,
    'America/Chicago',
    clock_timestamp() - interval '8 days'
  );
  blocked_result := app_private.release_management_interest_report_snapshot_v1(
    '6b800000-0000-4000-8000-000000000004'::uuid,
    '6b110000-0000-4000-8000-000000000001'::uuid,
    '6b130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1
  );
  IF blocked_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (blocked_result->'reason_codes' ? 'release_time_zone_revision_changed')
    OR blocked_result ? 'protected_report'
  THEN
    RAISE EXCEPTION '6AW time-zone revision drift was not blocked: %',
      blocked_result;
  END IF;
END
$fixture_6aw_lineage$;

-- The current-city release writer retains shared-table privileges for its
-- own report family. Row security must hide interest snapshots and reject a
-- direct interest insert before that role can bypass 6AW provenance.
CREATE TEMP TABLE fixture_6aw_interest_snapshot_row
ON COMMIT DROP
AS
SELECT snapshot.*
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.release_request_id =
  '6b800000-0000-4000-8000-000000000001'::uuid;

GRANT SELECT ON fixture_6aw_interest_snapshot_row
  TO tongxingzhe_management_current_city_snapshot_release_writer;

SET LOCAL ROLE tongxingzhe_management_current_city_snapshot_release_writer;

DO $fixture_6aw_cross_writer_scope$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.report_id =
      'contact_sessions_by_interest_level_two_periods'
  ) THEN
    RAISE EXCEPTION 'current-city writer can read an interest snapshot';
  END IF;

  BEGIN
    INSERT INTO app_private.management_report_snapshots (
      snapshot_id,
      release_request_id,
      created_by_app_user_id,
      project_id,
      release_lineage_id,
      report_id,
      report_version,
      query_fingerprint,
      reporting_time_zone,
      data_cutoff_utc,
      released_at_utc,
      previous_snapshot_id,
      source_change_sequence,
      protected_report
    )
    SELECT
      '6b810000-0000-4000-8000-000000000010'::uuid,
      '6b800000-0000-4000-8000-000000000010'::uuid,
      source_row.created_by_app_user_id,
      source_row.project_id,
      source_row.release_lineage_id,
      source_row.report_id,
      source_row.report_version,
      source_row.query_fingerprint,
      source_row.reporting_time_zone,
      source_row.data_cutoff_utc,
      source_row.released_at_utc,
      NULL,
      source_row.source_change_sequence,
      source_row.protected_report
    FROM pg_temp.fixture_6aw_interest_snapshot_row AS source_row;
    RAISE EXCEPTION 'current-city writer inserted an interest snapshot';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture_6aw_cross_writer_scope$;

RESET ROLE;

-- Snapshot and attempt history must remain append-only.  The trigger should
-- reject both mutations without exposing any candidate report data.
DO $fixture_6aw_immutability$
DECLARE
  fixture_snapshot_id uuid;
BEGIN
  SELECT snapshot.snapshot_id INTO STRICT fixture_snapshot_id
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = '6b130000-0000-4000-8000-000000000001'::uuid
    AND release_lineage_id =
      'management-interest-report:contact_sessions_by_interest_level_two_periods'
  ORDER BY snapshot.released_at_utc
  LIMIT 1;

  BEGIN
    UPDATE app_private.management_report_snapshots AS snapshot
    SET query_fingerprint = 'tampered'
    WHERE snapshot.snapshot_id = fixture_snapshot_id;
    RAISE EXCEPTION '6AW snapshot accepted UPDATE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    DELETE FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = fixture_snapshot_id;
    RAISE EXCEPTION '6AW snapshot accepted DELETE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    UPDATE app_private.management_interest_report_release_attempts AS attempt
    SET reason_codes = '[]'::jsonb
    WHERE attempt.release_request_id =
      '6b800000-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION '6AW attempt accepted UPDATE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    DELETE FROM app_private.management_interest_report_release_attempts AS attempt
    WHERE attempt.release_request_id =
      '6b800000-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION '6AW attempt accepted DELETE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    UPDATE app_private.management_report_release_request_claims AS claim
    SET release_family_id = 'interest_management_report_snapshot_release'
    WHERE claim.release_request_id =
      '6b800000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6AW request claim accepted UPDATE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
  BEGIN
    DELETE FROM app_private.management_report_release_request_claims AS claim
    WHERE claim.release_request_id =
      '6b800000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6AW request claim accepted DELETE';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'management report release history is immutable' THEN
      RAISE;
    END IF;
  END;
END
$fixture_6aw_immutability$;

ROLLBACK;
