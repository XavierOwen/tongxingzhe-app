-- 0061_management_interest_distribution_report.sql
--
-- Slice 6AV registers one private management report for the five-level
-- contact-session interest distribution.  It is deliberately independent
-- from the channel and current-city reports: a complete period is hidden if
-- any one interest level cannot satisfy the disclosure policy.

DO $reader_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_management_interest_report_reader'
  ) THEN
    CREATE ROLE tongxingzhe_management_interest_report_reader
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$reader_role$;

ALTER ROLE tongxingzhe_management_interest_report_reader
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

INSERT INTO app_private.management_report_definitions (
  report_id,
  report_version,
  metric_id,
  metric_version,
  dimension_key,
  period_grain,
  comparison_period_count,
  period_boundary_id,
  privacy_policy,
  required_capability,
  query_fingerprint
) VALUES (
  'contact_sessions_by_interest_level_two_periods',
  1,
  'interest_distribution',
  1,
  'interest_level',
  'week',
  2,
  'iso_week_monday_v1',
  'management_interest_distribution_privacy_v1',
  'view_anonymous_analytics',
  'management-report:contact_sessions_by_interest_level_two_periods:v1'
);

CREATE FUNCTION
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    requested_request jsonb
  )
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  definition_report_id text;
  definition_report_version integer;
  definition_metric_id text;
  definition_metric_version integer;
  definition_dimension_key text;
  definition_period_grain text;
  definition_comparison_period_count integer;
  definition_period_boundary_id text;
  definition_privacy_policy text;
  definition_required_capability text;
  definition_query_fingerprint text;
BEGIN
  IF requested_request IS NULL
    OR jsonb_typeof(requested_request) <> 'object'
    OR requested_request <> jsonb_build_object(
      'report_id', 'contact_sessions_by_interest_level_two_periods',
      'report_version', 1
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest distribution report request';
  END IF;

  SELECT
    definition.report_id,
    definition.report_version,
    definition.metric_id,
    definition.metric_version,
    definition.dimension_key,
    definition.period_grain,
    definition.comparison_period_count,
    definition.period_boundary_id,
    definition.privacy_policy,
    definition.required_capability,
    definition.query_fingerprint
  INTO STRICT
    definition_report_id,
    definition_report_version,
    definition_metric_id,
    definition_metric_version,
    definition_dimension_key,
    definition_period_grain,
    definition_comparison_period_count,
    definition_period_boundary_id,
    definition_privacy_policy,
    definition_required_capability,
    definition_query_fingerprint
  FROM app_private.management_report_definitions AS definition
  WHERE definition.report_id = requested_request->>'report_id'
    AND definition.report_version =
      (requested_request->>'report_version')::integer;

  RETURN jsonb_build_object(
    'report_id', definition_report_id,
    'report_version', definition_report_version,
    'metric_id', definition_metric_id,
    'metric_version', definition_metric_version,
    'statistical_unit', 'contact_session',
    'dimension', definition_dimension_key,
    'period_grain', definition_period_grain,
    'comparison_period_count', definition_comparison_period_count,
    'period_boundary_id', definition_period_boundary_id,
    'privacy_policy', definition_privacy_policy,
    'required_capability', definition_required_capability,
    'query_fingerprint', definition_query_fingerprint
  );
EXCEPTION WHEN no_data_found THEN
  RAISE EXCEPTION USING
    ERRCODE = '22023',
    MESSAGE = 'invalid management interest distribution report request';
END
$function$;

CREATE FUNCTION
  app_private.protect_management_interest_distribution_grid_v1(
    requested_contributions jsonb
  )
RETURNS TABLE (
  period_key text,
  interest_level integer,
  cell_order integer,
  value_count bigint,
  privacy_status text
)
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  max_safe_integer CONSTANT numeric := 9007199254740991;
BEGIN
  IF requested_contributions IS NULL
    OR jsonb_typeof(requested_contributions) <> 'array'
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_contributions) AS element(item)
      WHERE jsonb_typeof(item) <> 'object'
        OR NOT item ?& ARRAY[
          'period_key',
          'interest_level',
          'contributor_key',
          'unit_count'
        ]
        OR item - ARRAY[
          'period_key',
          'interest_level',
          'contributor_key',
          'unit_count'
        ] <> '{}'::jsonb
        OR jsonb_typeof(item->'period_key') <> 'string'
        OR item->>'period_key' NOT IN ('previous', 'current')
        OR jsonb_typeof(item->'interest_level') <> 'number'
        OR item->>'interest_level' !~ '^[0-4]$'
        OR jsonb_typeof(item->'contributor_key') <> 'string'
        OR length(btrim(item->>'contributor_key')) NOT BETWEEN 1 AND 120
        OR jsonb_typeof(item->'unit_count') <> 'number'
        OR item->>'unit_count' !~ '^[1-9][0-9]*$'
        OR (item->>'unit_count')::numeric > 2147483647
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest distribution contributions';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_contributions) AS element(item)
    GROUP BY
      item->>'period_key',
      (item->>'interest_level')::integer,
      btrim(item->>'contributor_key')
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'duplicate management interest distribution contribution';
  END IF;

  -- JSON clients and Dart use exact integers only up to 2^53-1. Keep
  -- aggregation numeric and reject both a leaf and a whole-period total
  -- beyond that boundary before the private result is converted to bigint.
  IF EXISTS (
    WITH input_rows AS (
      SELECT
        item->>'period_key' AS input_period_key,
        (item->>'interest_level')::integer AS input_interest_level,
        (item->>'unit_count')::numeric AS input_unit_count
      FROM jsonb_array_elements(requested_contributions) AS element(item)
    ),
    aggregate_rows AS (
      SELECT
        input_period_key,
        sum(input_unit_count) AS aggregate_count
      FROM input_rows
      GROUP BY input_period_key
      UNION ALL
      SELECT
        input_period_key,
        sum(input_unit_count) AS aggregate_count
      FROM input_rows
      GROUP BY input_period_key, input_interest_level
    )
    SELECT 1
    FROM aggregate_rows
    WHERE aggregate_count > max_safe_integer
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management interest distribution aggregate is too large';
  END IF;

  RETURN QUERY
  WITH input_rows AS (
    SELECT
      item->>'period_key' AS input_period_key,
      (item->>'interest_level')::integer AS input_interest_level,
      btrim(item->>'contributor_key') AS input_contributor_key,
      (item->>'unit_count')::numeric AS input_unit_count
    FROM jsonb_array_elements(requested_contributions) AS element(item)
  ),
  periods(input_period_key, period_order) AS (
    VALUES ('previous'::text, 0), ('current'::text, 1)
  ),
  levels(input_interest_level) AS (
    VALUES (0), (1), (2), (3), (4)
  ),
  complete_grid AS (
    SELECT
      period.input_period_key,
      period.period_order,
      level.input_interest_level
    FROM periods AS period
    CROSS JOIN levels AS level
  ),
  leaf_statistics AS (
    SELECT
      grid.input_period_key,
      grid.period_order,
      grid.input_interest_level,
      coalesce(sum(input_row.input_unit_count), 0)::numeric AS unit_count,
      count(input_row.input_contributor_key)::integer AS contributor_count,
      coalesce(max(input_row.input_unit_count), 0)::numeric
        AS max_contribution
    FROM complete_grid AS grid
    LEFT JOIN input_rows AS input_row
      ON input_row.input_period_key = grid.input_period_key
     AND input_row.input_interest_level = grid.input_interest_level
    GROUP BY
      grid.input_period_key,
      grid.period_order,
      grid.input_interest_level
  ),
  protected_leaves AS (
    SELECT
      statistics.*,
      statistics.unit_count >= 10
        AND statistics.contributor_count >= 3
        AND statistics.max_contribution::numeric * 2
          <= statistics.unit_count::numeric AS can_display
    FROM leaf_statistics AS statistics
  ),
  period_policy AS (
    SELECT
      input_period_key,
      bool_and(can_display) AS period_can_display
    FROM protected_leaves
    GROUP BY input_period_key
  )
  SELECT
    leaf.input_period_key,
    leaf.input_interest_level,
    leaf.period_order * 5 + leaf.input_interest_level,
    CASE
      WHEN policy.period_can_display AND leaf.can_display
        THEN leaf.unit_count::bigint
      ELSE NULL
    END,
    CASE
      WHEN policy.period_can_display AND leaf.can_display
        THEN 'displayed'
      ELSE 'suppressed'
    END
  FROM protected_leaves AS leaf
  JOIN period_policy AS policy
    ON policy.input_period_key = leaf.input_period_key
  ORDER BY leaf.period_order, leaf.input_interest_level;
END
$function$;

CREATE FUNCTION
  app_private.execute_management_interest_distribution_report_v1(
    requested_project_id uuid,
    requested_reporting_time_zone text,
    requested_data_cutoff_utc timestamp with time zone
  )
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  canonical_request jsonb;
  report_periods jsonb;
  contribution_document jsonb;
  protected_cells jsonb;
BEGIN
  canonical_request =
    app_private.canonicalize_management_interest_distribution_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_interest_level_two_periods',
        'report_version', 1
      )
    );

  IF requested_project_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM app_data.projects AS project_row
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id = project_row.workspace_id
    WHERE project_row.project_id = requested_project_id
      AND project_row.status = 'active'
      AND workspace_row.deleted_at IS NULL
      AND workspace_row.workspace_kind = 'organization'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management interest distribution project';
  END IF;

  report_periods = app_private.resolve_management_report_periods_v1(
    requested_reporting_time_zone,
    requested_data_cutoff_utc
  );
  IF canonical_request->>'period_boundary_id'
    <> report_periods->>'period_boundary_id'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management interest distribution period definition mismatch';
  END IF;

  WITH bounded_contacts AS (
    SELECT
      CASE
        WHEN contact_row.occurred_at_utc <
          (report_periods->'current_period'->>'start_utc')::timestamptz
          THEN 'previous'
        ELSE 'current'
      END AS period_key,
      contact_row.interest_level,
      contact_row.app_user_id::text AS contributor_key
    FROM app_data.contacts AS contact_row
    WHERE contact_row.project_id = requested_project_id
      AND contact_row.lifecycle_status = 'active'
      AND contact_row.first_submitted_at_utc <= requested_data_cutoff_utc
      AND contact_row.occurred_at_utc >=
        (report_periods->'previous_period'->>'start_utc')::timestamptz
      AND contact_row.occurred_at_utc <
        (report_periods->'current_period'->>'until_utc')::timestamptz
  ),
  contributions AS (
    SELECT
      bounded_contacts.period_key,
      bounded_contacts.interest_level,
      bounded_contacts.contributor_key,
      count(*)::bigint AS unit_count
    FROM bounded_contacts
    GROUP BY
      bounded_contacts.period_key,
      bounded_contacts.interest_level,
      bounded_contacts.contributor_key
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period_key', contributions.period_key,
        'interest_level', contributions.interest_level,
        'contributor_key', contributions.contributor_key,
        'unit_count', contributions.unit_count
      ) ORDER BY
        contributions.period_key,
        contributions.interest_level,
        contributions.contributor_key
    ),
    '[]'::jsonb
  ) INTO contribution_document
  FROM contributions;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period_key', protected.period_key,
        'interest_level', protected.interest_level,
        'cell_order', protected.cell_order,
        'value_count', protected.value_count,
        'privacy_status', protected.privacy_status
      ) ORDER BY protected.cell_order
    ),
    '[]'::jsonb
  )
  INTO protected_cells
  FROM app_private.protect_management_interest_distribution_grid_v1(
    contribution_document
  ) AS protected;

  RETURN jsonb_build_object(
    'report_id', canonical_request->'report_id',
    'report_version', canonical_request->'report_version',
    'metric_id', canonical_request->'metric_id',
    'metric_version', canonical_request->'metric_version',
    'statistical_unit', canonical_request->'statistical_unit',
    'dimension', canonical_request->'dimension',
    'query_fingerprint', canonical_request->'query_fingerprint',
    'privacy_policy', canonical_request->'privacy_policy',
    'source_scope', 'backend_accepted_active_contacts_current_revision',
    'project_id', requested_project_id,
    'periods', report_periods,
    'cells', protected_cells
  );
END
$function$;

-- Keep the private policy and executor behind the dedicated reader role.  No
-- runtime or ordinary app role receives either direct execute or schema usage.
REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    jsonb
  ),
  app_private.protect_management_interest_distribution_grid_v1(jsonb),
  app_private.execute_management_interest_distribution_report_v1(
    uuid, text, timestamp with time zone
  )
  FROM
    PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_interest_report_reader;

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_definitions,
  app_data.projects,
  app_data.workspaces,
  app_data.contacts
  FROM tongxingzhe_management_interest_report_reader;

GRANT SELECT (
  report_id,
  report_version,
  metric_id,
  metric_version,
  dimension_key,
  period_grain,
  comparison_period_count,
  period_boundary_id,
  privacy_policy,
  required_capability,
  query_fingerprint
)
ON app_private.management_report_definitions
TO tongxingzhe_management_interest_report_reader;

GRANT SELECT (project_id, workspace_id, status)
  ON app_data.projects
  TO tongxingzhe_management_interest_report_reader;
GRANT SELECT (workspace_id, workspace_kind, deleted_at)
  ON app_data.workspaces
  TO tongxingzhe_management_interest_report_reader;
GRANT SELECT (
  app_user_id,
  project_id,
  occurred_at_utc,
  first_submitted_at_utc,
  interest_level,
  lifecycle_status
)
ON app_data.contacts
TO tongxingzhe_management_interest_report_reader;

GRANT EXECUTE ON FUNCTION
  app_private.management_report_time_zone_valid_v1(text),
  app_private.resolve_management_report_periods_v1(
    text, timestamp with time zone
  ),
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    jsonb
  ),
  app_private.protect_management_interest_distribution_grid_v1(jsonb),
  app_private.execute_management_interest_distribution_report_v1(
    uuid, text, timestamp with time zone
  )
  TO tongxingzhe_management_interest_report_reader;

-- The migration identity runs the structural fixture; it does not retain the
-- dedicated role membership after this migration transaction.
GRANT EXECUTE ON FUNCTION
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    jsonb
  ),
  app_private.protect_management_interest_distribution_grid_v1(jsonb),
  app_private.execute_management_interest_distribution_report_v1(
    uuid, text, timestamp with time zone
  )
  TO CURRENT_USER;

GRANT tongxingzhe_management_interest_report_reader TO CURRENT_USER;

ALTER FUNCTION
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    jsonb
  ) OWNER TO tongxingzhe_management_interest_report_reader;
ALTER FUNCTION
  app_private.protect_management_interest_distribution_grid_v1(jsonb)
  OWNER TO tongxingzhe_management_interest_report_reader;
ALTER FUNCTION
  app_private.execute_management_interest_distribution_report_v1(
    uuid, text, timestamp with time zone
  ) OWNER TO tongxingzhe_management_interest_report_reader;

REVOKE tongxingzhe_management_interest_report_reader FROM CURRENT_USER;

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
    WHERE reader_role.rolname =
      'tongxingzhe_management_interest_report_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_interest_report_reader FROM %I',
      member_name
    );
  END LOOP;
END
$reader_membership$;

COMMENT ON FUNCTION
  app_private.canonicalize_management_interest_distribution_report_request_v1(
    jsonb
  )
IS 'Canonicalizes only contact_sessions_by_interest_level_two_periods@1; it performs no authorization or execution.';

COMMENT ON FUNCTION
  app_private.protect_management_interest_distribution_grid_v1(jsonb)
IS 'Applies k=10, three-contributor, half-contribution and whole-period suppression to the fixed previous/current five-level interest grid.';

COMMENT ON FUNCTION
  app_private.execute_management_interest_distribution_report_v1(
    uuid, text, timestamp with time zone
  )
IS 'Builds a private two-period interest distribution from accepted active contacts and returns no contributors, contact IDs, raw answers or PII.';
