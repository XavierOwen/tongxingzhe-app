-- 0055_management_report_region_target_context.sql
--
-- Bind one trusted report cutoff to the append-only canonical-region selection
-- history.  The resolver is deliberately private: a later report release path
-- supplies the trusted cutoff after its own authorization and lineage locks.

CREATE FUNCTION app_private.resolve_management_report_region_target_context_v1(
  requested_data_cutoff_utc timestamp with time zone
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  selection_row app_data.canonical_region_tree_current_selections%ROWTYPE;
  release_lifecycle_state text;
  release_published_at_utc timestamp with time zone;
  release_content_fingerprint text;
  evidence_at_utc timestamp with time zone;
  baseline_count bigint;
  selected_document jsonb;
BEGIN
  IF requested_data_cutoff_utc IS NULL
    OR NOT isfinite(requested_data_cutoff_utc)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report region target cutoff';
  END IF;

  -- Publication and target resolution share the same transaction boundary.
  -- This makes a resolver that waited for a publication observe its committed
  -- history rather than a partially changed selection.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'canonical-region-tree-publication:v1',
      0
    )
  );

  SELECT count(*)
  INTO baseline_count
  FROM app_data.canonical_region_tree_current_selections AS selection
  WHERE selection.selection_source = 'migration_baseline';

  IF baseline_count > 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region selection history has multiple baselines';
  END IF;

  SELECT selection.*
  INTO selection_row
  FROM app_data.canonical_region_tree_current_selections AS selection
  WHERE (
      selection.selection_source = 'publication'
      AND selection.selected_at_utc <= requested_data_cutoff_utc
    ) OR (
      selection.selection_source = 'migration_baseline'
      AND selection.recorded_at_utc <= requested_data_cutoff_utc
    )
  ORDER BY
    CASE
      WHEN selection.selection_source = 'publication'
        THEN selection.selected_at_utc
      ELSE selection.recorded_at_utc
    END DESC,
    selection.selection_sequence DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'target_context_contract_id',
        'management-region-target-context:v1',
      'result_status', 'unavailable',
      'reason_code', 'selection_history_unavailable',
      'data_cutoff_utc', to_char(
        requested_data_cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    );
  END IF;

  evidence_at_utc = CASE
    WHEN selection_row.selection_source = 'publication'
      THEN selection_row.selected_at_utc
    ELSE selection_row.recorded_at_utc
  END;

  IF evidence_at_utc IS NULL
    OR NOT isfinite(evidence_at_utc)
    OR NOT isfinite(selection_row.recorded_at_utc)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region selection evidence time is inconsistent';
  END IF;

  SELECT
    release.lifecycle_state,
    release.published_at_utc,
    release.content_fingerprint
  INTO
    release_lifecycle_state,
    release_published_at_utc,
    release_content_fingerprint
  FROM app_data.canonical_region_tree_releases AS release
  WHERE release.tree_version = selection_row.selected_tree_version;

  IF NOT FOUND
    OR release_lifecycle_state <> 'published'
    OR release_published_at_utc IS NULL
    OR NOT isfinite(release_published_at_utc)
    OR release_published_at_utc > requested_data_cutoff_utc
    OR release_content_fingerprint IS DISTINCT FROM
      selection_row.content_fingerprint
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region selection release evidence is inconsistent';
  END IF;

  IF selection_row.selection_source = 'publication' THEN
    IF selection_row.selected_at_utc IS NULL
      OR selection_row.recorded_at_utc IS DISTINCT FROM
        selection_row.selected_at_utc
      OR release_published_at_utc IS DISTINCT FROM
        selection_row.selected_at_utc
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'canonical region publication selection evidence is inconsistent';
    END IF;
  ELSIF selection_row.selection_source <> 'migration_baseline' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region selection source is inconsistent';
  END IF;

  selected_document = jsonb_build_object(
    'target_context_contract_id',
      'management-region-target-context:v1',
    'result_status', 'selected',
    'reason_code', CASE
      WHEN selection_row.selection_source = 'publication'
        THEN 'publication_selection'
      ELSE 'migration_baseline_observation'
    END,
    'data_cutoff_utc', to_char(
      requested_data_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'target_tree_version', selection_row.selected_tree_version,
    'target_content_fingerprint', selection_row.content_fingerprint,
    'selection_sequence', selection_row.selection_sequence,
    'selection_source', selection_row.selection_source,
    'selection_evidence_at_utc', to_char(
      evidence_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'tree_published_at_utc', to_char(
      release_published_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  );

  RETURN selected_document;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.resolve_management_report_region_target_context_v1(
    timestamp with time zone
  )
  FROM
    PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer;

GRANT USAGE ON SCHEMA app_data
  TO tongxingzhe_region_attribution_reader;
GRANT SELECT ON app_data.canonical_region_tree_current_selections
  TO tongxingzhe_region_attribution_reader;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON app_data.canonical_region_tree_current_selections
  FROM tongxingzhe_region_attribution_reader;

-- Keep the migration identity able to run the synthetic fixture without
-- retaining membership in the internal reader role.
GRANT EXECUTE ON FUNCTION
  app_private.resolve_management_report_region_target_context_v1(
    timestamp with time zone
  )
  TO CURRENT_USER;

GRANT tongxingzhe_region_attribution_reader TO CURRENT_USER;
ALTER FUNCTION
  app_private.resolve_management_report_region_target_context_v1(
    timestamp with time zone
  ) OWNER TO tongxingzhe_region_attribution_reader;
REVOKE tongxingzhe_region_attribution_reader FROM CURRENT_USER;

DO $reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname = 'tongxingzhe_region_attribution_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_region_attribution_reader FROM %I',
      member_name
    );
  END LOOP;
END
$reader_membership$;

COMMENT ON FUNCTION
  app_private.resolve_management_report_region_target_context_v1(
    timestamp with time zone
  ) IS 'Resolves one published canonical region target tree from a trusted report cutoff and immutable selection evidence.';
