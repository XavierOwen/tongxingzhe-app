-- 0056_management_current_city_report.sql
--
-- Slice 6AN registers and executes one private current-city report.  The
-- report is deliberately not connected to the existing channel snapshot
-- dispatcher.  It consumes the trusted 6AM target context and the explicit
-- 6AL attribution contract, then returns a complete protected city grid.

DO $reader_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_management_region_report_reader'
  ) THEN
    CREATE ROLE tongxingzhe_management_region_report_reader
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

ALTER ROLE tongxingzhe_management_region_report_reader
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
  'contact_sessions_by_current_city_two_periods',
  1,
  'contact_sessions',
  1,
  'current_city',
  'week',
  2,
  'iso_week_monday_v1',
  'management_current_city_contact_session_privacy_v1',
  'view_anonymous_analytics',
  'management-report:contact_sessions_by_current_city_two_periods:v1'
);

-- The old 6AM/6AL functions intentionally retain their original ACL and
-- owners.  These two narrow wrappers let the new report reader compose them
-- without granting the new role execute access to those legacy functions;
-- each wrapper runs under the existing private reader that owns its target.
CREATE FUNCTION
  app_private.resolve_management_current_city_target_context_v1(
    requested_data_cutoff_utc timestamp with time zone
  )
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  SELECT app_private.resolve_management_report_region_target_context_v1(
    requested_data_cutoff_utc
  )
$function$;

CREATE FUNCTION
  app_private.resolve_management_current_city_attribution_v1(
    requested_source_id uuid,
    requested_view_mode text,
    requested_target_tree_version text,
    requested_target_content_fingerprint text
  )
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
  SELECT app_private.resolve_management_region_attribution_v1(
    requested_source_id,
    requested_view_mode,
    requested_target_tree_version,
    requested_target_content_fingerprint
  )
$function$;

CREATE FUNCTION
  app_private.canonicalize_management_current_city_report_request_v1(
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
      'report_id', 'contact_sessions_by_current_city_two_periods',
      'report_version', 1
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid current city management report request';
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
    'dimension', definition_dimension_key,
    'view_mode', 'current',
    'region_granularity', 'city',
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
    MESSAGE = 'invalid current city management report request';
END
$function$;

CREATE FUNCTION
  app_private.protect_management_current_city_contact_session_grid_v1(
    requested_city_ids jsonb,
    requested_contributions jsonb
  )
RETURNS TABLE (
  period_key text,
  city_id text,
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
  city_count integer;
BEGIN
  IF requested_city_ids IS NULL
    OR jsonb_typeof(requested_city_ids) <> 'array'
    OR jsonb_array_length(requested_city_ids) = 0
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_city_ids) AS city(item)
      WHERE jsonb_typeof(city.item) <> 'string'
        OR length(btrim(city.item #>> '{}')) NOT BETWEEN 1 AND 120
    )
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_city_ids) AS city(item)
      GROUP BY btrim(city.item #>> '{}')
      HAVING count(*) > 1
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid current city report city grid';
  END IF;

  IF requested_contributions IS NULL
    OR jsonb_typeof(requested_contributions) <> 'array'
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_contributions) AS contribution(item)
      WHERE jsonb_typeof(contribution.item) <> 'object'
        OR NOT contribution.item ?& ARRAY[
          'period_key', 'city_id', 'contributor_key', 'unit_count'
        ]
        OR contribution.item - ARRAY[
          'period_key', 'city_id', 'contributor_key', 'unit_count'
        ] <> '{}'::jsonb
        OR jsonb_typeof(contribution.item->'period_key') <> 'string'
        OR contribution.item->>'period_key' NOT IN ('previous', 'current')
        OR jsonb_typeof(contribution.item->'city_id') <> 'string'
        OR length(btrim(contribution.item->>'city_id')) NOT BETWEEN 1 AND 120
        OR jsonb_typeof(contribution.item->'contributor_key') <> 'string'
        OR length(btrim(contribution.item->>'contributor_key'))
          NOT BETWEEN 1 AND 120
        OR jsonb_typeof(contribution.item->'unit_count') <> 'number'
        OR contribution.item->>'unit_count' !~ '^[1-9][0-9]*$'
        OR (contribution.item->>'unit_count')::numeric > 2147483647
    )
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_contributions) AS contribution(item)
      WHERE NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements_text(requested_city_ids) AS city(city_id)
        WHERE btrim(city.city_id) = btrim(contribution.item->>'city_id')
      )
    )
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_contributions) AS contribution(item)
      GROUP BY
        contribution.item->>'period_key',
        btrim(contribution.item->>'city_id'),
        btrim(contribution.item->>'contributor_key')
      HAVING count(*) > 1
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid current city report contributions';
  END IF;

  city_count = jsonb_array_length(requested_city_ids);

  RETURN QUERY
  WITH input_cities AS (
    SELECT
      btrim(city.city_id) AS input_city_id,
      row_number() OVER (
        ORDER BY btrim(city.city_id) COLLATE "C"
      )::integer - 1 AS city_order
    FROM jsonb_array_elements_text(requested_city_ids) AS city(city_id)
  ),
  input_rows AS (
    SELECT
      contribution.item->>'period_key' AS input_period_key,
      btrim(contribution.item->>'city_id') AS input_city_id,
      btrim(contribution.item->>'contributor_key') AS input_contributor_key,
      (contribution.item->>'unit_count')::bigint AS input_unit_count
    FROM jsonb_array_elements(requested_contributions)
      AS contribution(item)
  ),
  periods(input_period_key, period_order) AS (
    VALUES ('previous'::text, 0), ('current'::text, 1)
  ),
  complete_grid AS (
    SELECT
      period.input_period_key,
      period.period_order,
      city.input_city_id,
      city.city_order
    FROM periods AS period
    CROSS JOIN input_cities AS city
  ),
  leaf_statistics AS (
    SELECT
      grid.input_period_key,
      grid.period_order,
      grid.input_city_id,
      grid.city_order,
      coalesce(sum(input_row.input_unit_count), 0)::bigint AS unit_count,
      count(input_row.input_contributor_key)::integer AS contributor_count,
      coalesce(max(input_row.input_unit_count), 0)::bigint
        AS max_contribution
    FROM complete_grid AS grid
    LEFT JOIN input_rows AS input_row
      ON input_row.input_period_key = grid.input_period_key
     AND input_row.input_city_id = grid.input_city_id
    GROUP BY
      grid.input_period_key,
      grid.period_order,
      grid.input_city_id,
      grid.city_order
  ),
  primary_policy AS (
    SELECT
      statistics.*,
      statistics.unit_count >= 10
        AND statistics.contributor_count >= 3
        AND statistics.max_contribution::numeric * 2
          <= statistics.unit_count::numeric AS can_display
    FROM leaf_statistics AS statistics
  ),
  policy_counts AS (
    SELECT
      policy.*,
      count(*) FILTER (WHERE NOT policy.can_display) OVER (
        PARTITION BY policy.input_period_key
      )::integer AS primary_suppressed_count,
      count(*) FILTER (WHERE policy.can_display) OVER (
        PARTITION BY policy.input_period_key
      )::integer AS displayable_count
    FROM primary_policy AS policy
  ),
  final_policy AS (
    SELECT
      policy.*,
      CASE
        WHEN policy.can_display
          AND policy.primary_suppressed_count = 1
          AND policy.displayable_count > 0
          AND policy.city_order = (
            SELECT min(displayable.city_order)
            FROM policy_counts AS displayable
            WHERE displayable.input_period_key = policy.input_period_key
              AND displayable.can_display
          )
        THEN false
        ELSE policy.can_display
      END AS can_display_after_complementary_hiding
    FROM policy_counts AS policy
  )
  SELECT
    policy.input_period_key,
    policy.input_city_id,
    policy.period_order * city_count + policy.city_order,
    CASE
      WHEN policy.can_display_after_complementary_hiding
        THEN policy.unit_count
      ELSE NULL
    END,
    CASE
      WHEN policy.can_display_after_complementary_hiding
        THEN 'displayed'
      ELSE 'suppressed'
    END
  FROM final_policy AS policy
  ORDER BY policy.period_order, policy.city_order;
END
$function$;

CREATE FUNCTION
  app_private.execute_management_current_city_contact_session_report_v1(
    requested_project_id uuid,
    requested_reporting_time_zone text,
    requested_data_cutoff_utc timestamp with time zone
  )
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  canonical_request jsonb;
  report_periods jsonb;
  target_context jsonb;
  city_ids_document jsonb;
  contribution_document jsonb;
  protected_cells jsonb;
  source_change_sequence_value bigint;
  target_tree_version text;
  target_content_fingerprint text;
  target_city_count integer;
  missing_source boolean;
  invalid_attribution boolean;
  invalid_city_ancestor boolean;
  report_data_cutoff text;
BEGIN
  canonical_request =
    app_private.canonicalize_management_current_city_report_request_v1(
      jsonb_build_object(
        'report_id', 'contact_sessions_by_current_city_two_periods',
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
      MESSAGE = 'invalid current city management report project';
  END IF;

  report_periods = app_private.resolve_management_report_periods_v1(
    requested_reporting_time_zone,
    requested_data_cutoff_utc
  );
  IF canonical_request->>'period_boundary_id'
    <> report_periods->>'period_boundary_id'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current city report period definition is inconsistent';
  END IF;
  report_data_cutoff = report_periods->>'data_cutoff_utc';

  -- The wrappers delegate to resolve_management_report_region_target_context_v1
  -- and resolve_management_region_attribution_v1 under their established
  -- private owners; this role never receives their legacy ACL directly.
  target_context =
    app_private.resolve_management_current_city_target_context_v1(
      requested_data_cutoff_utc
    );

  IF target_context->>'target_context_contract_id'
      IS DISTINCT FROM 'management-region-target-context:v1'
    OR target_context->>'result_status' IS NULL
    OR target_context->>'result_status' NOT IN ('selected', 'unavailable')
    OR nullif(btrim(target_context->>'reason_code'), '') IS NULL
    OR (
      target_context->>'result_status' = 'unavailable'
      AND target_context ?| ARRAY[
        'target_tree_version', 'target_content_fingerprint',
        'selection_sequence', 'selection_source',
        'selection_evidence_at_utc', 'tree_published_at_utc'
      ]
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current city report target context is inconsistent';
  END IF;

  IF target_context->>'result_status' <> 'selected' THEN
    SELECT coalesce(max(change_row.change_sequence), 0)::bigint
    INTO source_change_sequence_value
    FROM app_data.change_feed AS change_row
    WHERE change_row.project_id = requested_project_id;

    RETURN jsonb_build_object(
      'report_id', canonical_request->'report_id',
      'report_version', canonical_request->'report_version',
      'metric_id', canonical_request->'metric_id',
      'metric_version', canonical_request->'metric_version',
      'dimension', canonical_request->'dimension',
      'view_mode', canonical_request->'view_mode',
      'region_granularity', canonical_request->'region_granularity',
      'query_fingerprint', canonical_request->'query_fingerprint',
      'privacy_policy', canonical_request->'privacy_policy',
      'source_scope', 'backend_accepted_active_contacts_current_revision',
      'project_id', requested_project_id,
      'periods', report_periods,
      'data_cutoff_utc', report_data_cutoff,
      'source_change_sequence', source_change_sequence_value,
      'target_context', target_context,
      'result_status', 'unavailable',
      'reason_code', coalesce(
        target_context->>'reason_code',
        'selection_history_unavailable'
      )
    );
  END IF;

  target_tree_version = target_context->>'target_tree_version';
  target_content_fingerprint =
    target_context->>'target_content_fingerprint';

  IF target_tree_version IS NULL
    OR length(btrim(target_tree_version)) = 0
    OR target_content_fingerprint IS NULL
    OR target_content_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current city report target context is inconsistent';
  END IF;

  SELECT
    coalesce(
      jsonb_agg(
        to_jsonb(city.region_id)
        ORDER BY city.region_id COLLATE "C"
      ),
      '[]'::jsonb
    ),
    count(*)::integer
  INTO city_ids_document, target_city_count
  FROM app_data.canonical_region_versions AS city
  WHERE city.tree_version = target_tree_version
    AND city.kind = 'city';

  IF target_city_count = 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current city report target tree has no cities';
  END IF;

  -- A city node may not itself descend from another city node.  Reporting a
  -- source against such a tree would make the city dimension ambiguous.
  IF EXISTS (
    WITH RECURSIVE city_ancestors AS (
      SELECT
        node.region_id AS starting_city_id,
        node.region_id,
        node.parent_region_id,
        node.kind
      FROM app_data.canonical_region_versions AS node
      WHERE node.tree_version = target_tree_version
        AND node.kind = 'city'
      UNION ALL
      SELECT
        ancestor.starting_city_id,
        parent.region_id,
        parent.parent_region_id,
        parent.kind
      FROM city_ancestors AS ancestor
      JOIN app_data.canonical_region_versions AS parent
        ON parent.tree_version = target_tree_version
       AND parent.region_id = ancestor.parent_region_id
    ),
    city_counts AS (
      SELECT
        starting_city_id,
        count(*) FILTER (WHERE kind = 'city') AS city_count
      FROM city_ancestors
      GROUP BY starting_city_id
    )
    SELECT 1
    FROM city_counts
    WHERE city_count <> 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current city report target tree has nested cities';
  END IF;

  WITH RECURSIVE candidate_contacts AS (
    SELECT
      contact_row.contact_id,
      contact_row.app_user_id::text AS contributor_key,
      contact_row.current_revision,
      CASE
        WHEN contact_row.occurred_at_utc <
          (report_periods->'current_period'->>'start_utc')::timestamptz
          THEN 'previous'
        ELSE 'current'
      END AS period_key
    FROM app_data.contacts AS contact_row
    WHERE contact_row.project_id = requested_project_id
      AND contact_row.lifecycle_status = 'active'
      AND contact_row.first_submitted_at_utc <= requested_data_cutoff_utc
      AND contact_row.occurred_at_utc >=
        (report_periods->'previous_period'->>'start_utc')::timestamptz
      AND contact_row.occurred_at_utc <
        (report_periods->'current_period'->>'until_utc')::timestamptz
  ),
  current_sources AS (
    SELECT
      candidate.contact_id,
      candidate.contributor_key,
      candidate.period_key,
      provenance.source_id
    FROM candidate_contacts AS candidate
    JOIN app_data.contact_location_provenance AS provenance
      ON provenance.contact_id = candidate.contact_id
     AND provenance.revision_number = candidate.current_revision
  ),
  source_status AS (
    SELECT EXISTS (
      SELECT 1
      FROM candidate_contacts AS candidate
      WHERE NOT EXISTS (
        SELECT 1
        FROM app_data.contact_location_provenance AS provenance
        WHERE provenance.contact_id = candidate.contact_id
          AND provenance.revision_number = candidate.current_revision
      )
    ) AS has_missing_source
  ),
  source_watermark AS (
    SELECT coalesce(max(change_row.change_sequence), 0)::bigint
      AS source_change_sequence
    FROM app_data.change_feed AS change_row
    WHERE change_row.project_id = requested_project_id
  ),
  attributions AS (
    SELECT
      source.contact_id,
      source.contributor_key,
      source.period_key,
      app_private.resolve_management_current_city_attribution_v1(
        source.source_id,
        'current',
        target_tree_version,
        target_content_fingerprint
      ) AS attribution_document
    FROM current_sources AS source
  ),
  attributed AS (
    SELECT
      attribution.contact_id,
      attribution.contributor_key,
      attribution.period_key,
      attribution.attribution_document
    FROM attributions AS attribution
    WHERE attribution.attribution_document->>'result_status' = 'attributed'
  ),
  evidence_status AS (
    SELECT coalesce(bool_or(
      attribution.attribution_document->>'attribution_contract_id'
        IS DISTINCT FROM 'management-region-attribution:v1'
      OR attribution.attribution_document->>'view_mode'
        IS DISTINCT FROM 'current'
      OR attribution.attribution_document->>'result_status' IS NULL
      OR attribution.attribution_document->>'result_status' NOT IN (
        'attributed', 'not_reportable', 'unmapped', 'ambiguous'
      )
      OR nullif(btrim(
        attribution.attribution_document->>'reason_code'
      ), '') IS NULL
      OR (
        attribution.attribution_document->>'result_status' = 'attributed'
        AND (
          attribution.attribution_document->>'tree_version'
            IS DISTINCT FROM target_tree_version
          OR attribution.attribution_document->>'content_fingerprint'
            IS DISTINCT FROM target_content_fingerprint
          OR attribution.attribution_document->>'region_id' IS NULL
        )
      )
      OR (
        attribution.attribution_document->>'result_status' <> 'attributed'
        AND attribution.attribution_document ?| ARRAY[
          'region_id', 'tree_version', 'content_fingerprint'
        ]
      )
    ), false) AS has_invalid_attribution
    FROM attributions AS attribution
  ),
  region_ancestors AS (
    SELECT
      attribution.contact_id,
      attribution.contributor_key,
      attribution.period_key,
      node.region_id,
      node.parent_region_id,
      node.kind
    FROM attributed AS attribution
    JOIN app_data.canonical_region_versions AS node
      ON node.tree_version = target_tree_version
     AND node.region_id = attribution.attribution_document->>'region_id'
    UNION ALL
    SELECT
      ancestor.contact_id,
      ancestor.contributor_key,
      ancestor.period_key,
      parent.region_id,
      parent.parent_region_id,
      parent.kind
    FROM region_ancestors AS ancestor
    JOIN app_data.canonical_region_versions AS parent
      ON parent.tree_version = target_tree_version
     AND parent.region_id = ancestor.parent_region_id
  ),
  city_by_contact AS (
    SELECT
      ancestor.contact_id,
      ancestor.contributor_key,
      ancestor.period_key,
      count(*) FILTER (WHERE ancestor.kind = 'city') AS city_count,
      min(ancestor.region_id) FILTER (WHERE ancestor.kind = 'city')
        AS city_id
    FROM region_ancestors AS ancestor
    GROUP BY
      ancestor.contact_id,
      ancestor.contributor_key,
      ancestor.period_key
  ),
  city_status AS (
    SELECT
      coalesce(bool_or(city.city_count <> 1), false)
        OR count(city.contact_id) <> (SELECT count(*) FROM attributed)
        AS has_invalid_city_ancestor
    FROM city_by_contact AS city
  ),
  contributions AS (
    SELECT
      city.period_key,
      city.city_id,
      city.contributor_key,
      count(*)::bigint AS unit_count
    FROM city_by_contact AS city
    GROUP BY city.period_key, city.city_id, city.contributor_key
  )
  SELECT
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'period_key', contribution.period_key,
            'city_id', contribution.city_id,
            'contributor_key', contribution.contributor_key,
            'unit_count', contribution.unit_count
          ) ORDER BY
            contribution.period_key,
            contribution.city_id COLLATE "C",
            contribution.contributor_key COLLATE "C"
        )
        FROM contributions AS contribution
      ),
      '[]'::jsonb
    ),
    (SELECT source_status.has_missing_source FROM source_status),
    (SELECT evidence_status.has_invalid_attribution FROM evidence_status),
    (SELECT city_status.has_invalid_city_ancestor FROM city_status),
    (SELECT source_watermark.source_change_sequence FROM source_watermark)
  INTO
    contribution_document,
    missing_source,
    invalid_attribution,
    invalid_city_ancestor,
    source_change_sequence_value;

  IF missing_source OR invalid_attribution OR invalid_city_ancestor THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'current city report attribution evidence is inconsistent';
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period_key', protected.period_key,
        'city_id', protected.city_id,
        'cell_order', protected.cell_order,
        'value_count', protected.value_count,
        'privacy_status', protected.privacy_status
      ) ORDER BY protected.cell_order
    ),
    '[]'::jsonb
  )
  INTO protected_cells
  FROM app_private.protect_management_current_city_contact_session_grid_v1(
    city_ids_document,
    contribution_document
  ) AS protected;

  RETURN jsonb_build_object(
    'report_id', canonical_request->'report_id',
    'report_version', canonical_request->'report_version',
    'metric_id', canonical_request->'metric_id',
    'metric_version', canonical_request->'metric_version',
    'dimension', canonical_request->'dimension',
    'view_mode', canonical_request->'view_mode',
    'region_granularity', canonical_request->'region_granularity',
    'query_fingerprint', canonical_request->'query_fingerprint',
    'privacy_policy', canonical_request->'privacy_policy',
    'source_scope', 'backend_accepted_active_contacts_current_revision',
    'project_id', requested_project_id,
    'periods', report_periods,
    'data_cutoff_utc', report_data_cutoff,
    'source_change_sequence', source_change_sequence_value,
    'target_context', target_context,
    'result_status', 'completed',
    'cells', protected_cells
  );
END
$function$;

-- Only the new reader can invoke the composition wrappers.  The wrappers
-- retain the existing 6AM/6AL owners and therefore do not widen those ACLs.
REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.resolve_management_current_city_target_context_v1(
    timestamp with time zone
  ),
  app_private.resolve_management_current_city_attribution_v1(
    uuid, text, text, text
  )
  FROM
    PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.canonicalize_management_current_city_report_request_v1(jsonb),
  app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb, jsonb
  ),
  app_private.execute_management_current_city_contact_session_report_v1(
    uuid, text, timestamp with time zone
  )
  FROM
    PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_region_report_reader;

-- Column-level grants keep the report reader from reading names, coordinates,
-- raw locations or complete source records.  6AL performs sensitive evidence
-- resolution under its own existing SECURITY DEFINER owner.
REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_definitions,
  app_data.projects,
  app_data.workspaces,
  app_data.contacts,
  app_data.contact_location_provenance,
  app_data.canonical_region_versions,
  app_data.change_feed
  FROM tongxingzhe_management_region_report_reader;

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
TO tongxingzhe_management_region_report_reader;

GRANT SELECT (project_id, workspace_id, status)
  ON app_data.projects
  TO tongxingzhe_management_region_report_reader;
GRANT SELECT (workspace_id, workspace_kind, deleted_at)
  ON app_data.workspaces
  TO tongxingzhe_management_region_report_reader;
GRANT SELECT (
  contact_id,
  app_user_id,
  project_id,
  occurred_at_utc,
  first_submitted_at_utc,
  current_revision,
  lifecycle_status
)
ON app_data.contacts
TO tongxingzhe_management_region_report_reader;
GRANT SELECT (source_id, contact_id, revision_number)
  ON app_data.contact_location_provenance
  TO tongxingzhe_management_region_report_reader;
GRANT SELECT (region_id, tree_version, parent_region_id, kind)
  ON app_data.canonical_region_versions
  TO tongxingzhe_management_region_report_reader;
GRANT SELECT (project_id, change_sequence)
  ON app_data.change_feed
  TO tongxingzhe_management_region_report_reader;

GRANT EXECUTE ON FUNCTION
  app_private.resolve_management_current_city_target_context_v1(
    timestamp with time zone
  ),
  app_private.resolve_management_current_city_attribution_v1(
    uuid, text, text, text
  ),
  app_private.management_report_time_zone_valid_v1(text),
  app_private.resolve_management_report_periods_v1(
    text, timestamp with time zone
  ),
  app_private.canonicalize_management_current_city_report_request_v1(jsonb),
  app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb, jsonb
  ),
  app_private.execute_management_current_city_contact_session_report_v1(
    uuid, text, timestamp with time zone
  )
  TO tongxingzhe_management_region_report_reader;

-- The migration identity runs the structural fixture without retaining the
-- reader role as a member after migration.
GRANT EXECUTE ON FUNCTION
  app_private.canonicalize_management_current_city_report_request_v1(jsonb),
  app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb, jsonb
  ),
  app_private.execute_management_current_city_contact_session_report_v1(
    uuid, text, timestamp with time zone
  )
  TO CURRENT_USER;

GRANT tongxingzhe_management_region_report_reader TO CURRENT_USER;
ALTER FUNCTION
  app_private.resolve_management_current_city_target_context_v1(
    timestamp with time zone
  ) OWNER TO tongxingzhe_region_attribution_reader;
ALTER FUNCTION
  app_private.resolve_management_current_city_attribution_v1(
    uuid, text, text, text
  ) OWNER TO tongxingzhe_region_attribution_reader;
ALTER FUNCTION
  app_private.canonicalize_management_current_city_report_request_v1(jsonb)
  OWNER TO tongxingzhe_management_region_report_reader;
ALTER FUNCTION
  app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb, jsonb
  ) OWNER TO tongxingzhe_management_region_report_reader;
ALTER FUNCTION
  app_private.execute_management_current_city_contact_session_report_v1(
    uuid, text, timestamp with time zone
  ) OWNER TO tongxingzhe_management_region_report_reader;
REVOKE tongxingzhe_management_region_report_reader FROM CURRENT_USER;

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
      'tongxingzhe_management_region_report_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_region_report_reader FROM %I',
      member_name
    );
  END LOOP;
END
$reader_membership$;

COMMENT ON FUNCTION
  app_private.canonicalize_management_current_city_report_request_v1(jsonb)
IS 'Canonicalizes only the fixed current-city management report request; it performs no authorization or execution.';

COMMENT ON FUNCTION
  app_private.protect_management_current_city_contact_session_grid_v1(
    jsonb, jsonb
  )
IS 'Applies the fixed current-city k=10, contributor and complementary suppression policy to a complete two-period grid.';

COMMENT ON FUNCTION
  app_private.execute_management_current_city_contact_session_report_v1(
    uuid, text, timestamp with time zone
  )
IS 'Builds a private current-city report from the trusted target context and current revision provenance; it returns no names, coordinates or identifiers beyond stable city IDs.';
