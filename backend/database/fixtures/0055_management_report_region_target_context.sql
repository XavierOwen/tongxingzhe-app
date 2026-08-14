\set ON_ERROR_STOP on

BEGIN;

-- Three immutable releases provide one migrated baseline observation and two
-- later publication selections. Concurrency probes commit their own selection
-- rows before dump/restore, so this rollback-only fixture first removes that
-- ambient history and then builds a self-contained cutoff timeline.
ALTER TABLE app_data.canonical_region_tree_current_selections
  DISABLE TRIGGER canonical_region_selection_history_guard;
DELETE FROM app_data.canonical_region_tree_current_selections;
ALTER TABLE app_data.canonical_region_tree_current_selections
  ENABLE TRIGGER canonical_region_selection_history_guard;

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
) VALUES
  ('fixture-target-context-baseline-v1', 'draft', false),
  ('fixture-target-context-v1', 'draft', false),
  ('fixture-target-context-v2', 'draft', false),
  ('fixture-target-context-draft-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
) VALUES
  ('fixture-context-baseline-country', 'fixture-target-context-baseline-v1', NULL, 'Baseline Country', 'country'),
  ('fixture-context-baseline-city', 'fixture-target-context-baseline-v1', 'fixture-context-baseline-country', 'Baseline City', 'city'),
  ('fixture-context-baseline-venue', 'fixture-target-context-baseline-v1', 'fixture-context-baseline-city', 'Baseline Venue', 'venue'),
  ('fixture-context-v1-country', 'fixture-target-context-v1', NULL, 'V1 Country', 'country'),
  ('fixture-context-v1-city', 'fixture-target-context-v1', 'fixture-context-v1-country', 'V1 City', 'city'),
  ('fixture-context-v1-venue', 'fixture-target-context-v1', 'fixture-context-v1-city', 'V1 Venue', 'venue'),
  ('fixture-context-v2-country', 'fixture-target-context-v2', NULL, 'V2 Country', 'country'),
  ('fixture-context-v2-city', 'fixture-target-context-v2', 'fixture-context-v2-country', 'V2 City', 'city'),
  ('fixture-context-v2-venue', 'fixture-target-context-v2', 'fixture-context-v2-city', 'V2 Venue', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
) VALUES
  (
    'fixture-context-baseline-boundary',
    'fixture-context-baseline-venue',
    'fixture-target-context-baseline-v1',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  ),
  (
    'fixture-context-v1-boundary',
    'fixture-context-v1-venue',
    'fixture-target-context-v1',
    polygon '((-87.62,41.77),(-87.57,41.77),(-87.57,41.81),(-87.62,41.81))'
  ),
  (
    'fixture-context-v2-boundary',
    'fixture-context-v2-venue',
    'fixture-target-context-v2',
    polygon '((-87.63,41.76),(-87.56,41.76),(-87.56,41.82),(-87.63,41.82))'
  );

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-target-context-baseline-v1', true
);

-- Convert the first normal publication row into the exact migration-baseline
-- shape. This exceptional mutation is local to this rollback-only fixture.
ALTER TABLE app_data.canonical_region_tree_current_selections
  DISABLE TRIGGER canonical_region_selection_history_guard;
UPDATE app_data.canonical_region_tree_current_selections
SET selection_source = 'migration_baseline',
    selected_at_utc = NULL,
    previous_tree_version = NULL
WHERE selected_tree_version = 'fixture-target-context-baseline-v1';
ALTER TABLE app_data.canonical_region_tree_current_selections
  ENABLE TRIGGER canonical_region_selection_history_guard;

SELECT pg_sleep(0.01);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-target-context-v1', true
);
SELECT pg_sleep(0.01);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-target-context-v2', true
);

DO $fixture$
DECLARE
  baseline_sequence bigint;
  baseline_recorded_at timestamptz;
  baseline_published_at timestamptz;
  baseline_fingerprint text;
  v1_sequence bigint;
  v1_selected_at timestamptz;
  v1_published_at timestamptz;
  v1_fingerprint text;
  v2_sequence bigint;
  v2_selected_at timestamptz;
  v2_published_at timestamptz;
  v2_fingerprint text;
  result jsonb;
  expected record;
  key_name text;
  failure_sqlstate text;
  corrupt_sequence bigint;
BEGIN
  SELECT
    selection.selection_sequence,
    selection.recorded_at_utc,
    release_row.published_at_utc,
    selection.content_fingerprint
  INTO STRICT
    baseline_sequence,
    baseline_recorded_at,
    baseline_published_at,
    baseline_fingerprint
  FROM app_data.canonical_region_tree_current_selections AS selection
  JOIN app_data.canonical_region_tree_releases AS release_row
    ON release_row.tree_version = selection.selected_tree_version
  WHERE selection.selected_tree_version =
    'fixture-target-context-baseline-v1';

  SELECT
    selection.selection_sequence,
    selection.selected_at_utc,
    release_row.published_at_utc,
    selection.content_fingerprint
  INTO STRICT
    v1_sequence,
    v1_selected_at,
    v1_published_at,
    v1_fingerprint
  FROM app_data.canonical_region_tree_current_selections AS selection
  JOIN app_data.canonical_region_tree_releases AS release_row
    ON release_row.tree_version = selection.selected_tree_version
  WHERE selection.selected_tree_version = 'fixture-target-context-v1';

  SELECT
    selection.selection_sequence,
    selection.selected_at_utc,
    release_row.published_at_utc,
    selection.content_fingerprint
  INTO STRICT
    v2_sequence,
    v2_selected_at,
    v2_published_at,
    v2_fingerprint
  FROM app_data.canonical_region_tree_current_selections AS selection
  JOIN app_data.canonical_region_tree_releases AS release_row
    ON release_row.tree_version = selection.selected_tree_version
  WHERE selection.selected_tree_version = 'fixture-target-context-v2';

  IF NOT (
    baseline_published_at <= baseline_recorded_at
    AND baseline_recorded_at < v1_selected_at
    AND v1_selected_at < v2_selected_at
  ) THEN
    RAISE EXCEPTION 'fixture target context times are not strictly ordered';
  END IF;

  FOR expected IN
    SELECT *
    FROM (VALUES
      (
        'before-baseline',
        baseline_recorded_at - interval '1 microsecond',
        'unavailable',
        'selection_history_unavailable',
        NULL::text,
        NULL::text,
        NULL::bigint,
        NULL::text,
        NULL::timestamptz,
        NULL::timestamptz
      ),
      (
        'baseline-equal',
        baseline_recorded_at,
        'selected',
        'migration_baseline_observation',
        'fixture-target-context-baseline-v1',
        baseline_fingerprint,
        baseline_sequence,
        'migration_baseline',
        baseline_recorded_at,
        baseline_published_at
      ),
      (
        'baseline-after',
        v1_selected_at - interval '1 microsecond',
        'selected',
        'migration_baseline_observation',
        'fixture-target-context-baseline-v1',
        baseline_fingerprint,
        baseline_sequence,
        'migration_baseline',
        baseline_recorded_at,
        baseline_published_at
      ),
      (
        'v1-equal',
        v1_selected_at,
        'selected',
        'publication_selection',
        'fixture-target-context-v1',
        v1_fingerprint,
        v1_sequence,
        'publication',
        v1_selected_at,
        v1_published_at
      ),
      (
        'v1-after',
        v2_selected_at - interval '1 microsecond',
        'selected',
        'publication_selection',
        'fixture-target-context-v1',
        v1_fingerprint,
        v1_sequence,
        'publication',
        v1_selected_at,
        v1_published_at
      ),
      (
        'v2-equal',
        v2_selected_at,
        'selected',
        'publication_selection',
        'fixture-target-context-v2',
        v2_fingerprint,
        v2_sequence,
        'publication',
        v2_selected_at,
        v2_published_at
      ),
      (
        'v2-after',
        v2_selected_at + interval '1 hour',
        'selected',
        'publication_selection',
        'fixture-target-context-v2',
        v2_fingerprint,
        v2_sequence,
        'publication',
        v2_selected_at,
        v2_published_at
      ),
      (
        'old-cutoff-repeat',
        v1_selected_at,
        'selected',
        'publication_selection',
        'fixture-target-context-v1',
        v1_fingerprint,
        v1_sequence,
        'publication',
        v1_selected_at,
        v1_published_at
      )
    ) AS cases(
      case_name,
      data_cutoff_utc,
      result_status,
      reason_code,
      target_tree_version,
      target_content_fingerprint,
      selection_sequence,
      selection_source,
      selection_evidence_at_utc,
      tree_published_at_utc
    )
  LOOP
    result := app_private.resolve_management_report_region_target_context_v1(
      expected.data_cutoff_utc
    );

    IF result->>'target_context_contract_id'
        IS DISTINCT FROM 'management-region-target-context:v1'
      OR result->>'result_status' IS DISTINCT FROM expected.result_status
      OR result->>'reason_code' IS DISTINCT FROM expected.reason_code
      OR result->>'data_cutoff_utc' IS DISTINCT FROM to_char(
        expected.data_cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    THEN
      RAISE EXCEPTION 'unexpected target context for %: %',
        expected.case_name, result;
    END IF;

    IF expected.target_tree_version IS NULL THEN
      IF result ?| ARRAY[
        'target_tree_version', 'target_content_fingerprint',
        'selection_sequence', 'selection_source',
        'selection_evidence_at_utc', 'tree_published_at_utc'
      ] OR (
        SELECT count(*) FROM jsonb_object_keys(result)
      ) <> 4
      THEN
        RAISE EXCEPTION 'unavailable context leaked target evidence for %: %',
          expected.case_name, result;
      END IF;
    ELSE
      IF result->>'target_tree_version'
          IS DISTINCT FROM expected.target_tree_version
        OR result->>'target_content_fingerprint'
          IS DISTINCT FROM expected.target_content_fingerprint
        OR (result->>'selection_sequence')::bigint
          IS DISTINCT FROM expected.selection_sequence
        OR result->>'selection_source'
          IS DISTINCT FROM expected.selection_source
        OR result->>'selection_evidence_at_utc' IS DISTINCT FROM to_char(
          expected.selection_evidence_at_utc AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
        )
        OR result->>'tree_published_at_utc' IS DISTINCT FROM to_char(
          expected.tree_published_at_utc AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
        )
        OR (
          SELECT count(*) FROM jsonb_object_keys(result)
        ) <> 10
      THEN
        RAISE EXCEPTION 'selected target evidence is wrong for %: %',
          expected.case_name, result;
      END IF;
    END IF;

    FOR key_name IN SELECT jsonb_object_keys(result)
    LOOP
      IF key_name NOT IN (
        'target_context_contract_id', 'result_status', 'reason_code',
        'data_cutoff_utc', 'target_tree_version',
        'target_content_fingerprint', 'selection_sequence',
        'selection_source', 'selection_evidence_at_utc',
        'tree_published_at_utc'
      ) THEN
        RAISE EXCEPTION 'target context returned uncontracted key %', key_name;
      END IF;
    END LOOP;

    IF result ?| ARRAY[
      'contact_id', 'source_id', 'revision_number', 'latitude', 'longitude',
      'canonical_name', 'place_name', 'project_id', 'app_user_id',
      'contributor_id', 'region_id', 'is_current'
    ] THEN
      RAISE EXCEPTION 'target context leaked sensitive or mutable evidence: %',
        result;
    END IF;
  END LOOP;

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      NULL
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '22023' THEN
    RAISE EXCEPTION 'NULL cutoff did not fail with 22023: %', failure_sqlstate;
  END IF;

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      'infinity'::timestamptz
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '22023' THEN
    RAISE EXCEPTION 'infinite cutoff did not fail with 22023: %',
      failure_sqlstate;
  END IF;

  -- Corrupt one selected fingerprint inside the rollback-only fixture. The
  -- resolver must reject the mismatch instead of emitting a target tuple.
  ALTER TABLE app_data.canonical_region_tree_current_selections
    DISABLE TRIGGER canonical_region_selection_history_guard;
  UPDATE app_data.canonical_region_tree_current_selections
  SET content_fingerprint = repeat('f', 64)
  WHERE selection_sequence = v2_sequence;
  ALTER TABLE app_data.canonical_region_tree_current_selections
    ENABLE TRIGGER canonical_region_selection_history_guard;

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      v2_selected_at
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'drifted selection fingerprint did not fail closed: %',
      failure_sqlstate;
  END IF;

  ALTER TABLE app_data.canonical_region_tree_current_selections
    DISABLE TRIGGER canonical_region_selection_history_guard;
  UPDATE app_data.canonical_region_tree_current_selections
  SET content_fingerprint = v2_fingerprint
  WHERE selection_sequence = v2_sequence;
  ALTER TABLE app_data.canonical_region_tree_current_selections
    ENABLE TRIGGER canonical_region_selection_history_guard;

  -- A publication row must carry the release publication timestamp exactly.
  ALTER TABLE app_data.canonical_region_tree_current_selections
    DISABLE TRIGGER canonical_region_selection_history_guard;
  UPDATE app_data.canonical_region_tree_current_selections
  SET selected_at_utc = selected_at_utc + interval '1 microsecond'
  WHERE selection_sequence = v2_sequence;
  ALTER TABLE app_data.canonical_region_tree_current_selections
    ENABLE TRIGGER canonical_region_selection_history_guard;

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      v2_selected_at + interval '1 microsecond'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'drifted selection timestamp did not fail closed: %',
      failure_sqlstate;
  END IF;

  ALTER TABLE app_data.canonical_region_tree_current_selections
    DISABLE TRIGGER canonical_region_selection_history_guard;
  UPDATE app_data.canonical_region_tree_current_selections
  SET selected_at_utc = v2_selected_at
  WHERE selection_sequence = v2_sequence;
  ALTER TABLE app_data.canonical_region_tree_current_selections
    ENABLE TRIGGER canonical_region_selection_history_guard;

  -- Valid databases cannot point selection history at a draft or missing
  -- release. Temporarily bypass replication triggers to prove the resolver's
  -- own fail-closed checks still reject either corrupted catalog shape.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO app_data.canonical_region_tree_current_selections (
    selected_tree_version,
    previous_tree_version,
    selected_at_utc,
    recorded_at_utc,
    selection_source,
    content_fingerprint
  ) VALUES (
    'fixture-target-context-draft-v1',
    'fixture-target-context-v2',
    v2_selected_at + interval '1 hour',
    v2_selected_at + interval '1 hour',
    'publication',
    repeat('d', 64)
  )
  RETURNING selection_sequence INTO corrupt_sequence;
  PERFORM set_config('session_replication_role', 'origin', true);

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      v2_selected_at + interval '1 hour'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'draft selection release did not fail closed: %',
      failure_sqlstate;
  END IF;

  PERFORM set_config('session_replication_role', 'replica', true);
  DELETE FROM app_data.canonical_region_tree_current_selections
  WHERE selection_sequence = corrupt_sequence;
  INSERT INTO app_data.canonical_region_tree_current_selections (
    selected_tree_version,
    previous_tree_version,
    selected_at_utc,
    recorded_at_utc,
    selection_source,
    content_fingerprint
  ) VALUES (
    'fixture-target-context-missing-v1',
    'fixture-target-context-v2',
    v2_selected_at + interval '2 hours',
    v2_selected_at + interval '2 hours',
    'publication',
    repeat('e', 64)
  )
  RETURNING selection_sequence INTO corrupt_sequence;
  PERFORM set_config('session_replication_role', 'origin', true);

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      v2_selected_at + interval '2 hours'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'missing selection release did not fail closed: %',
      failure_sqlstate;
  END IF;

  PERFORM set_config('session_replication_role', 'replica', true);
  DELETE FROM app_data.canonical_region_tree_current_selections
  WHERE selection_sequence = corrupt_sequence;
  INSERT INTO app_data.canonical_region_tree_current_selections (
    selected_tree_version,
    previous_tree_version,
    selected_at_utc,
    recorded_at_utc,
    selection_source,
    content_fingerprint
  ) VALUES (
    'fixture-target-context-baseline-v1',
    NULL,
    NULL,
    v2_selected_at + interval '3 hours',
    'migration_baseline',
    baseline_fingerprint
  );
  PERFORM set_config('session_replication_role', 'origin', true);

  failure_sqlstate := NULL;
  BEGIN
    PERFORM app_private.resolve_management_report_region_target_context_v1(
      v2_selected_at + interval '3 hours'
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '55000' THEN
    RAISE EXCEPTION 'multiple migration baselines did not fail closed: %',
      failure_sqlstate;
  END IF;
END
$fixture$;

ROLLBACK;
