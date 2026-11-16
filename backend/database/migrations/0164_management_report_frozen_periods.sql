-- Published UTC periods keep their original meaning when tzdata changes.
DO $frozen_periods$
DECLARE
  scope record;
  original pg_catalog.pg_proc%ROWTYPE;
  source text;
  replacement text;
  anchor text := $anchor$  expected_periods = app_private.resolve_management_report_periods_v1(
    requested_report->'periods'->>'reporting_time_zone',
    report_data_cutoff
  );$anchor$;
BEGIN
  FOR scope IN SELECT * FROM (VALUES
    (
      'app_private.validate_management_current_city_report_document_v1(jsonb)',
      'app_private.management_current_city_report_release_attempts'::regclass,
      'management-region-report:contact_sessions_by_current_city_two_periods',
      $predicate$        AND frozen_snapshot.protected_report->'target_context'->>'target_tree_version' = frozen_attempt.target_tree_version
        AND frozen_snapshot.protected_report->'target_context'->>'target_content_fingerprint' = frozen_attempt.target_content_fingerprint$predicate$
    ),
    (
      'app_private.validate_management_interest_report_document_v1(jsonb)',
      'app_private.management_interest_report_release_attempts'::regclass,
      'management-interest-report:contact_sessions_by_interest_level_two_periods',
      '        AND frozen_snapshot.source_change_sequence = frozen_attempt.source_change_sequence'
    ),
    (
      'app_private.validate_management_original_region_report_document_v1(jsonb)',
      'app_private.management_original_region_report_release_attempts'::regclass,
      'management-original-region-report:contact_sessions_by_original_region_two_periods',
      $predicate$        AND frozen_snapshot.source_change_sequence = frozen_attempt.source_change_sequence
        AND frozen_snapshot.protected_report->'source_tree_context'->>'source_tree_version' = frozen_attempt.source_tree_version
        AND frozen_snapshot.protected_report->'source_tree_context'->>'source_content_fingerprint' = frozen_attempt.source_content_fingerprint$predicate$
    ),
    (
      'app_private.validate_management_follow_up_consent_ratio_report_document_v1(jsonb)',
      'app_private.management_follow_up_consent_report_release_attempts'::regclass,
      'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
      '        AND frozen_snapshot.source_change_sequence = frozen_attempt.source_change_sequence'
    )
  ) AS scopes(signature, attempt_table, lineage_id, extra_predicate) LOOP
    SELECT * INTO STRICT original FROM pg_catalog.pg_proc WHERE oid = scope.signature::regprocedure;
    IF NOT has_table_privilege(original.proowner, scope.attempt_table, 'SELECT')
      OR NOT has_table_privilege(original.proowner, 'app_private.management_report_snapshots', 'SELECT')
      OR length(original.prosrc) - length(replace(original.prosrc, anchor, '')) <> length(anchor) THEN
      RAISE EXCEPTION '0164 frozen-period source privileges or calendar anchor unavailable: %', scope.signature;
    END IF;

    -- Document cutoffs have millisecond precision; snapshot metadata keeps its original precision.
    replacement := format($replacement$  expected_periods = COALESCE(
    (
      SELECT frozen_snapshot.protected_report->'periods'
      FROM app_private.management_report_snapshots AS frozen_snapshot
      JOIN %s AS frozen_attempt
        ON frozen_attempt.released_snapshot_id = frozen_snapshot.snapshot_id
      WHERE frozen_snapshot.project_id = (requested_report->>'project_id')::uuid
        AND frozen_snapshot.release_lineage_id = %L
        AND frozen_snapshot.data_cutoff_utc >= report_data_cutoff
        AND frozen_snapshot.data_cutoff_utc < report_data_cutoff + interval '1 millisecond'
        AND frozen_snapshot.protected_report = requested_report
        AND frozen_attempt.result_status IN ('approved_baseline', 'approved')
        AND frozen_attempt.reason_codes = '[]'::jsonb
        AND frozen_attempt.capability_id = 'release_management_reports'
        AND frozen_snapshot.release_request_id = frozen_attempt.release_request_id
        AND frozen_snapshot.created_by_app_user_id IS NOT DISTINCT FROM frozen_attempt.requested_by_app_user_id
        AND frozen_snapshot.project_id = frozen_attempt.project_id
        AND frozen_snapshot.report_id = frozen_attempt.report_id
        AND frozen_snapshot.report_version = frozen_attempt.report_version
        AND frozen_snapshot.query_fingerprint = frozen_attempt.query_fingerprint
        AND frozen_snapshot.release_lineage_id = frozen_attempt.release_lineage_id
        AND frozen_snapshot.reporting_time_zone = frozen_attempt.reporting_time_zone
        AND frozen_snapshot.data_cutoff_utc = frozen_attempt.data_cutoff_utc
        AND frozen_snapshot.previous_snapshot_id IS NOT DISTINCT FROM frozen_attempt.compared_snapshot_id
%s
      LIMIT 1
    ),
    app_private.resolve_management_report_periods_v1(
      requested_report->'periods'->>'reporting_time_zone',
      report_data_cutoff
    )
  );$replacement$, scope.attempt_table, scope.lineage_id, scope.extra_predicate);
    source := replace(original.prosrc, anchor, replacement);
    EXECUTE replace(pg_catalog.pg_get_functiondef(original.oid), original.prosrc, source);
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc changed WHERE changed.oid = original.oid
      AND to_jsonb(changed) - 'prosrc' = to_jsonb(original) - 'prosrc' AND changed.prosrc = source) THEN
      RAISE EXCEPTION '0164 frozen-period validation changed metadata or unrelated implementation: %', scope.signature;
    END IF;
  END LOOP;
END
$frozen_periods$;
