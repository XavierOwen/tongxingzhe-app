-- 0027_management_report_pair_release.sql
--
-- 比较两份固定管理报告中实际 UTC 边界相同的期间。共享格的显示值或隐私
-- 状态发生变化时，后续授权端点必须阻止发布，避免通过重复查询直接得到变化量。
-- 判定结果不含格值；当前函数仍在 app_private，且不保存查询历史或执行授权。

CREATE FUNCTION app_private.validate_management_report_document_v1(
  requested_report jsonb
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  previous_start timestamp with time zone;
  previous_until timestamp with time zone;
  current_start timestamp with time zone;
  current_until timestamp with time zone;
  data_cutoff timestamp with time zone;
BEGIN
  IF requested_report IS NULL
    OR jsonb_typeof(requested_report) <> 'object'
    OR NOT requested_report ?& ARRAY[
      'report_id',
      'report_version',
      'metric_id',
      'metric_version',
      'dimension',
      'query_fingerprint',
      'privacy_policy',
      'source_scope',
      'project_id',
      'periods',
      'cells'
    ]
    OR requested_report - ARRAY[
      'report_id',
      'report_version',
      'metric_id',
      'metric_version',
      'dimension',
      'query_fingerprint',
      'privacy_policy',
      'source_scope',
      'project_id',
      'periods',
      'cells'
    ] <> '{}'::jsonb
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  IF requested_report->>'report_id'
      <> 'contact_sessions_by_channel_two_periods'
    OR requested_report->'report_version' <> '1'::jsonb
    OR requested_report->>'metric_id' <> 'contact_sessions'
    OR requested_report->'metric_version' <> '1'::jsonb
    OR requested_report->>'dimension' <> 'channel'
    OR requested_report->>'query_fingerprint'
      <> 'management-report:contact_sessions_by_channel_two_periods:v1'
    OR requested_report->>'privacy_policy'
      <> 'management_contact_session_privacy_v1'
    OR requested_report->>'source_scope' <> 'backend_accepted_contacts'
    OR jsonb_typeof(requested_report->'project_id') <> 'string'
    OR requested_report->>'project_id'
      !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    OR jsonb_typeof(requested_report->'periods') <> 'object'
    OR jsonb_typeof(requested_report->'cells') <> 'array'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  IF NOT ((requested_report->'periods') ?& ARRAY[
      'period_boundary_id',
      'reporting_time_zone',
      'data_cutoff_utc',
      'previous_period',
      'current_period'
    ])
    OR (requested_report->'periods') - ARRAY[
      'period_boundary_id',
      'reporting_time_zone',
      'data_cutoff_utc',
      'previous_period',
      'current_period'
    ] <> '{}'::jsonb
    OR requested_report->'periods'->>'period_boundary_id'
      <> 'iso_week_monday_v1'
    OR app_private.management_report_time_zone_valid_v1(
      requested_report->'periods'->>'reporting_time_zone'
    ) IS NOT TRUE
    OR jsonb_typeof(requested_report->'periods'->'data_cutoff_utc')
      <> 'string'
    OR jsonb_typeof(requested_report->'periods'->'previous_period')
      <> 'object'
    OR jsonb_typeof(requested_report->'periods'->'current_period')
      <> 'object'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  IF NOT ((requested_report->'periods'->'previous_period') ?& ARRAY[
      'start_utc',
      'until_utc'
    ])
    OR (requested_report->'periods'->'previous_period') - ARRAY[
      'start_utc',
      'until_utc'
    ] <> '{}'::jsonb
    OR NOT ((requested_report->'periods'->'current_period') ?& ARRAY[
      'start_utc',
      'until_utc'
    ])
    OR (requested_report->'periods'->'current_period') - ARRAY[
      'start_utc',
      'until_utc'
    ] <> '{}'::jsonb
    OR jsonb_typeof(
      requested_report->'periods'->'previous_period'->'start_utc'
    ) <> 'string'
    OR jsonb_typeof(
      requested_report->'periods'->'previous_period'->'until_utc'
    ) <> 'string'
    OR jsonb_typeof(
      requested_report->'periods'->'current_period'->'start_utc'
    ) <> 'string'
    OR jsonb_typeof(
      requested_report->'periods'->'current_period'->'until_utc'
    ) <> 'string'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  BEGIN
    previous_start = (
      requested_report->'periods'->'previous_period'->>'start_utc'
    )::timestamptz;
    previous_until = (
      requested_report->'periods'->'previous_period'->>'until_utc'
    )::timestamptz;
    current_start = (
      requested_report->'periods'->'current_period'->>'start_utc'
    )::timestamptz;
    current_until = (
      requested_report->'periods'->'current_period'->>'until_utc'
    )::timestamptz;
    data_cutoff = (
      requested_report->'periods'->>'data_cutoff_utc'
    )::timestamptz;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid protected management report document';
  END;

  IF NOT isfinite(previous_start)
    OR NOT isfinite(previous_until)
    OR NOT isfinite(current_start)
    OR NOT isfinite(current_until)
    OR NOT isfinite(data_cutoff)
    OR previous_start >= previous_until
    OR previous_until <> current_start
    OR current_start >= current_until
    OR current_until > data_cutoff
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  IF jsonb_array_length(requested_report->'cells') <> 16
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_report->'cells') AS element(cell)
      WHERE jsonb_typeof(cell) <> 'object'
        OR NOT cell ?& ARRAY[
          'period_key',
          'category_key',
          'cell_order',
          'value_count',
          'privacy_status'
        ]
        OR cell - ARRAY[
          'period_key',
          'category_key',
          'cell_order',
          'value_count',
          'privacy_status'
        ] <> '{}'::jsonb
        OR jsonb_typeof(cell->'period_key') <> 'string'
        OR cell->>'period_key' NOT IN ('previous', 'current')
        OR jsonb_typeof(cell->'category_key') <> 'string'
        OR cell->>'category_key' NOT IN (
          'all',
          'face_to_face',
          'voice_call',
          'video_call',
          'instant_text',
          'asynchronous_message',
          'mixed',
          'other_direct'
        )
        OR jsonb_typeof(cell->'cell_order') <> 'number'
        OR cell->>'cell_order' !~ '^(0|[1-9][0-9]*)$'
        OR jsonb_typeof(cell->'privacy_status') <> 'string'
        OR cell->>'privacy_status' NOT IN ('displayed', 'suppressed')
        OR (
          cell->>'privacy_status' = 'displayed'
          AND (
            jsonb_typeof(cell->'value_count') <> 'number'
            OR cell->>'value_count' !~ '^(0|[1-9][0-9]*)$'
          )
        )
        OR (
          cell->>'privacy_status' = 'suppressed'
          AND cell->'value_count' <> 'null'::jsonb
        )
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_report->'cells') AS element(cell)
    WHERE cell->>'privacy_status' = 'displayed'
      AND (
        (cell->>'value_count')::numeric < 10
        OR (cell->>'value_count')::numeric > 9223372036854775807
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;

  IF (
    SELECT count(DISTINCT (cell->>'period_key', cell->>'category_key'))
    FROM jsonb_array_elements(requested_report->'cells') AS element(cell)
  ) <> 16 OR EXISTS (
    WITH expected(period_key, category_key, cell_order) AS (
      VALUES
        ('previous'::text, 'all'::text, '0'::jsonb),
        ('previous'::text, 'face_to_face'::text, '1'::jsonb),
        ('previous'::text, 'voice_call'::text, '2'::jsonb),
        ('previous'::text, 'video_call'::text, '3'::jsonb),
        ('previous'::text, 'instant_text'::text, '4'::jsonb),
        ('previous'::text, 'asynchronous_message'::text, '5'::jsonb),
        ('previous'::text, 'mixed'::text, '6'::jsonb),
        ('previous'::text, 'other_direct'::text, '7'::jsonb),
        ('current'::text, 'all'::text, '8'::jsonb),
        ('current'::text, 'face_to_face'::text, '9'::jsonb),
        ('current'::text, 'voice_call'::text, '10'::jsonb),
        ('current'::text, 'video_call'::text, '11'::jsonb),
        ('current'::text, 'instant_text'::text, '12'::jsonb),
        ('current'::text, 'asynchronous_message'::text, '13'::jsonb),
        ('current'::text, 'mixed'::text, '14'::jsonb),
        ('current'::text, 'other_direct'::text, '15'::jsonb)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_report->'cells') AS element(cell)
    LEFT JOIN expected
      ON expected.period_key = cell->>'period_key'
     AND expected.category_key = cell->>'category_key'
     AND expected.cell_order = cell->'cell_order'
    WHERE expected.period_key IS NULL
  )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid protected management report document';
  END IF;
END
$function$;

CREATE FUNCTION app_private.assess_management_report_pair_release_v1(
  requested_earlier_report jsonb,
  requested_later_report jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  shared_period_count integer;
  assessed_cell_count integer;
  privacy_status_changed boolean;
  displayed_value_changed boolean;
  reason_codes jsonb = '[]'::jsonb;
BEGIN
  PERFORM app_private.validate_management_report_document_v1(
    requested_earlier_report
  );
  PERFORM app_private.validate_management_report_document_v1(
    requested_later_report
  );

  IF requested_earlier_report->>'report_id'
      <> requested_later_report->>'report_id'
    OR requested_earlier_report->'report_version'
      <> requested_later_report->'report_version'
    OR requested_earlier_report->>'query_fingerprint'
      <> requested_later_report->>'query_fingerprint'
    OR requested_earlier_report->>'privacy_policy'
      <> requested_later_report->>'privacy_policy'
    OR requested_earlier_report->>'project_id'
      <> requested_later_report->>'project_id'
    OR requested_earlier_report->'periods'->>'reporting_time_zone'
      <> requested_later_report->'periods'->>'reporting_time_zone'
    OR (requested_earlier_report->'periods'->>'data_cutoff_utc')::timestamptz
      >= (requested_later_report->'periods'->>'data_cutoff_utc')::timestamptz
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'incompatible management report release pair';
  END IF;

  WITH earlier_cells AS (
    SELECT
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_earlier_report->'periods'->'previous_period'->>'start_utc'
        ELSE
          requested_earlier_report->'periods'->'current_period'->>'start_utc'
      END AS start_utc,
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_earlier_report->'periods'->'previous_period'->>'until_utc'
        ELSE
          requested_earlier_report->'periods'->'current_period'->>'until_utc'
      END AS until_utc,
      cell->>'category_key' AS category_key,
      cell->>'privacy_status' AS privacy_status,
      cell->>'value_count' AS value_count
    FROM jsonb_array_elements(
      requested_earlier_report->'cells'
    ) AS element(cell)
  ),
  later_cells AS (
    SELECT
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_later_report->'periods'->'previous_period'->>'start_utc'
        ELSE
          requested_later_report->'periods'->'current_period'->>'start_utc'
      END AS start_utc,
      CASE cell->>'period_key'
        WHEN 'previous' THEN
          requested_later_report->'periods'->'previous_period'->>'until_utc'
        ELSE
          requested_later_report->'periods'->'current_period'->>'until_utc'
      END AS until_utc,
      cell->>'category_key' AS category_key,
      cell->>'privacy_status' AS privacy_status,
      cell->>'value_count' AS value_count
    FROM jsonb_array_elements(
      requested_later_report->'cells'
    ) AS element(cell)
  ),
  shared_cells AS (
    SELECT
      earlier_cells.start_utc,
      earlier_cells.until_utc,
      earlier_cells.privacy_status AS earlier_privacy_status,
      later_cells.privacy_status AS later_privacy_status,
      earlier_cells.value_count AS earlier_value_count,
      later_cells.value_count AS later_value_count
    FROM earlier_cells
    JOIN later_cells
      ON later_cells.start_utc = earlier_cells.start_utc
     AND later_cells.until_utc = earlier_cells.until_utc
     AND later_cells.category_key = earlier_cells.category_key
  )
  SELECT
    count(DISTINCT (start_utc, until_utc))::integer,
    count(*)::integer,
    coalesce(bool_or(
      earlier_privacy_status <> later_privacy_status
    ), false),
    coalesce(bool_or(
      earlier_privacy_status = 'displayed'
      AND later_privacy_status = 'displayed'
      AND earlier_value_count <> later_value_count
    ), false)
  INTO
    shared_period_count,
    assessed_cell_count,
    privacy_status_changed,
    displayed_value_changed
  FROM shared_cells;

  IF shared_period_count = 0 THEN
    reason_codes = reason_codes || jsonb_build_array('no_shared_period');
  END IF;
  IF privacy_status_changed THEN
    reason_codes = reason_codes
      || jsonb_build_array('shared_cell_privacy_status_changed');
  END IF;
  IF displayed_value_changed THEN
    reason_codes = reason_codes
      || jsonb_build_array('shared_displayed_value_changed');
  END IF;

  RETURN jsonb_build_object(
    'assessment_id', 'management_report_pair_release_v1',
    'report_id', requested_earlier_report->'report_id',
    'report_version', requested_earlier_report->'report_version',
    'query_fingerprint', requested_earlier_report->'query_fingerprint',
    'privacy_policy', requested_earlier_report->'privacy_policy',
    'project_id', requested_earlier_report->'project_id',
    'reporting_time_zone',
      requested_earlier_report->'periods'->'reporting_time_zone',
    'earlier_data_cutoff_utc',
      requested_earlier_report->'periods'->'data_cutoff_utc',
    'later_data_cutoff_utc',
      requested_later_report->'periods'->'data_cutoff_utc',
    'shared_period_count', shared_period_count,
    'assessed_cell_count', assessed_cell_count,
    'result_status', CASE
      WHEN jsonb_array_length(reason_codes) = 0 THEN 'approved'
      ELSE 'blocked'
    END,
    'reason_codes', reason_codes
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.validate_management_report_document_v1(jsonb),
  app_private.assess_management_report_pair_release_v1(jsonb, jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_private.assess_management_report_pair_release_v1(jsonb, jsonb)
IS 'Blocks release when overlapping protected report cells change; returns metadata and reason codes without cell values or authorization.';
