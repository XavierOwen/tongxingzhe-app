-- 0074_management_follow_up_consent_ratio.sql
--
-- Slice 6BP exposes only a private, already-protected candidate for the
-- future management release workflow.  It does not create a snapshot,
-- release lineage, runtime bridge, HTTP endpoint, or client contract.

DO $candidate_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname =
      'tongxingzhe_management_follow_up_consent_ratio_reader'
  ) THEN
    CREATE ROLE tongxingzhe_management_follow_up_consent_ratio_reader
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$candidate_role$;

ALTER ROLE tongxingzhe_management_follow_up_consent_ratio_reader
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
  'contact_target_follow_up_consent_ratio_two_periods',
  1,
  'follow_up_consent_ratio',
  1,
  'consent_state',
  'week',
  2,
  'iso_week_monday_v1',
  'management_follow_up_consent_ratio_privacy_v1',
  'release_management_reports',
  'management-report:contact_target_follow_up_consent_ratio_two_periods:v1'
);

CREATE FUNCTION
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    requested_request jsonb
  )
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  definition app_private.management_report_definitions%ROWTYPE;
BEGIN
  IF requested_request IS NULL
    OR jsonb_typeof(requested_request) <> 'object'
    OR requested_request <> jsonb_build_object(
      'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
      'report_version', 1
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent ratio report request';
  END IF;

  SELECT *
  INTO STRICT definition
  FROM app_private.management_report_definitions
  WHERE report_id = requested_request->>'report_id'
    AND report_version = (requested_request->>'report_version')::integer;

  RETURN jsonb_build_object(
    'report_id', definition.report_id,
    'report_version', definition.report_version,
    'metric_id', definition.metric_id,
    'metric_version', definition.metric_version,
    'statistical_unit', 'contact_target_link',
    'dimension', definition.dimension_key,
    'period_grain', definition.period_grain,
    'comparison_period_count', definition.comparison_period_count,
    'period_boundary_id', definition.period_boundary_id,
    'privacy_policy', definition.privacy_policy,
    'required_capability', definition.required_capability,
    'query_fingerprint', definition.query_fingerprint
  );
EXCEPTION WHEN no_data_found THEN
  RAISE EXCEPTION USING
    ERRCODE = '22023',
    MESSAGE = 'invalid management follow-up consent ratio report request';
END
$function$;

-- The 0073 read seam is owned by the closed configuration role.  Keep its
-- ACL owner-only and cross the boundary through this equally private helper;
-- the candidate reader receives execute only on the helper, never on the
-- configuration history reader itself.
CREATE FUNCTION app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_metric_id text
)
RETURNS jsonb
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
  SELECT app_private.read_management_follow_up_consent_opt_in_v1(
    trusted_app_user_id,
    requested_project_id,
    requested_metric_id
  )
$function$;

CREATE FUNCTION app_private.protect_management_follow_up_consent_ratio_periods_v1(
  requested_contributions jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  max_safe_integer CONSTANT numeric := 9007199254740991;
  protected_periods jsonb;
BEGIN
  IF requested_contributions IS NULL
    OR jsonb_typeof(requested_contributions) <> 'array'
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_contributions) AS element(item)
      WHERE jsonb_typeof(item) <> 'object'
        OR NOT item ?& ARRAY[
          'period_key',
          'consent_state',
          'contributor_key',
          'unit_count'
        ]
        OR item - ARRAY[
          'period_key',
          'consent_state',
          'contributor_key',
          'unit_count'
        ] <> '{}'::jsonb
        OR jsonb_typeof(item->'period_key') <> 'string'
        OR item->>'period_key' NOT IN ('previous', 'current')
        OR jsonb_typeof(item->'consent_state') <> 'string'
        OR item->>'consent_state' NOT IN (
          'yes',
          'no',
          'unanswered',
          'refused',
          'not_applicable'
        )
        OR jsonb_typeof(item->'contributor_key') <> 'string'
        OR length(btrim(item->>'contributor_key')) NOT BETWEEN 1 AND 120
        OR jsonb_typeof(item->'unit_count') <> 'number'
        OR item->>'unit_count' !~ '^[1-9][0-9]*$'
        OR (item->>'unit_count')::numeric > max_safe_integer
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent ratio contributions';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_contributions) AS element(item)
    GROUP BY
      item->>'period_key',
      item->>'consent_state',
      btrim(item->>'contributor_key')
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'duplicate management follow-up consent ratio contribution';
  END IF;

  -- Keep every aggregate in the exact JSON integer range.  The period total
  -- protects against a cross-state sum while the state total protects every
  -- value that is subsequently considered for disclosure.
  IF EXISTS (
    WITH input_rows AS (
      SELECT
        item->>'period_key' AS input_period_key,
        item->>'consent_state' AS input_consent_state,
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
      GROUP BY input_period_key, input_consent_state
    )
    SELECT 1
    FROM aggregate_rows
    WHERE aggregate_count > max_safe_integer
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management follow-up consent ratio aggregate is too large';
  END IF;

  WITH input_rows AS (
    SELECT
      item->>'period_key' AS input_period_key,
      item->>'consent_state' AS input_consent_state,
      btrim(item->>'contributor_key') AS input_contributor_key,
      (item->>'unit_count')::numeric AS input_unit_count
    FROM jsonb_array_elements(requested_contributions) AS element(item)
  ),
  periods(input_period_key, period_order) AS (
    VALUES ('previous'::text, 0), ('current'::text, 1)
  ),
  states(input_consent_state, state_order, coverage_order) AS (
    VALUES
      ('yes'::text, 0, NULL::integer),
      ('no'::text, 1, NULL::integer),
      ('unanswered'::text, 2, 0),
      ('refused'::text, 3, 1),
      ('not_applicable'::text, 4, 2)
  ),
  complete_grid AS (
    SELECT
      period.input_period_key,
      period.period_order,
      state.input_consent_state,
      state.state_order,
      state.coverage_order
    FROM periods AS period
    CROSS JOIN states AS state
  ),
  leaf_statistics AS (
    SELECT
      grid.input_period_key,
      grid.period_order,
      grid.input_consent_state,
      grid.state_order,
      grid.coverage_order,
      coalesce(sum(input_row.input_unit_count), 0)::numeric AS unit_count,
      count(DISTINCT input_row.input_contributor_key)::integer
        AS contributor_count,
      coalesce(max(input_row.input_unit_count), 0)::numeric
        AS max_contribution
    FROM complete_grid AS grid
    LEFT JOIN input_rows AS input_row
      ON input_row.input_period_key = grid.input_period_key
     AND input_row.input_consent_state = grid.input_consent_state
    GROUP BY
      grid.input_period_key,
      grid.period_order,
      grid.input_consent_state,
      grid.state_order,
      grid.coverage_order
  ),
  protected_leaves AS (
    SELECT
      statistics.*,
      statistics.unit_count >= 10
        AND statistics.contributor_count >= 3
        AND statistics.max_contribution * 2
          <= statistics.unit_count AS can_display
    FROM leaf_statistics AS statistics
  ),
  period_statistics AS (
    SELECT
      input_period_key,
      period_order,
      bool_and(can_display) FILTER (
        WHERE input_consent_state IN ('yes', 'no')
      ) AS ratio_can_display,
      max(unit_count) FILTER (
        WHERE input_consent_state = 'yes'
      ) AS yes_count,
      max(unit_count) FILTER (
        WHERE input_consent_state = 'no'
      ) AS no_count
    FROM protected_leaves
    GROUP BY input_period_key, period_order
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'period_key', period.input_period_key,
      'period_order', period.period_order,
      'ratio', jsonb_build_object(
        'privacy_status', CASE
          WHEN period.ratio_can_display THEN 'displayed'
          ELSE 'suppressed'
        END,
        'yes_count', CASE
          WHEN period.ratio_can_display THEN period.yes_count::bigint
          ELSE NULL
        END,
        'no_count', CASE
          WHEN period.ratio_can_display THEN period.no_count::bigint
          ELSE NULL
        END,
        'numerator', CASE
          WHEN period.ratio_can_display THEN period.yes_count::bigint
          ELSE NULL
        END,
        'denominator', CASE
          WHEN period.ratio_can_display
            THEN (period.yes_count + period.no_count)::bigint
          ELSE NULL
        END,
        'percentage_basis_points', CASE
          WHEN period.ratio_can_display THEN floor(
            (period.yes_count * 10000 / (
              period.yes_count + period.no_count
            )) + 0.5
          )::integer
          ELSE NULL
        END
      ),
      'coverage', (
        SELECT jsonb_agg(
          jsonb_build_object(
            'consent_state', leaf.input_consent_state,
            'cell_order', period.period_order * 3 + leaf.coverage_order,
            'value_count', CASE
              WHEN leaf.can_display THEN leaf.unit_count::bigint
              ELSE NULL
            END,
            'privacy_status', CASE
              WHEN leaf.can_display THEN 'displayed'
              ELSE 'suppressed'
            END
          ) ORDER BY leaf.coverage_order
        )
        FROM protected_leaves AS leaf
        WHERE leaf.input_period_key = period.input_period_key
          AND leaf.coverage_order IS NOT NULL
      ),
      'unknown_count', 0,
      'excluded_count', 0
    ) ORDER BY period.period_order
  )
  INTO protected_periods
  FROM period_statistics AS period;

  RETURN coalesce(protected_periods, '[]'::jsonb);
END
$function$;

CREATE FUNCTION app_private.execute_management_follow_up_consent_ratio_report_v1(
  trusted_app_user_id uuid,
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
  opt_in_state jsonb;
  authorization_evidence jsonb;
  report_periods jsonb;
  contribution_document jsonb;
  protected_periods jsonb;
BEGIN
  IF trusted_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_reporting_time_zone IS NULL
    OR length(btrim(requested_reporting_time_zone)) = 0
    OR requested_data_cutoff_utc IS NULL
    OR NOT isfinite(requested_data_cutoff_utc)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management follow-up consent ratio request';
  END IF;

  -- The private helper invokes 0073's
  -- app_private.read_management_follow_up_consent_opt_in_v1.  That seam
  -- performs authorization, membership/capability locking, opt-in
  -- project locking, and reauthorization before returning this state.  The
  -- transaction-level locks remain held through the candidate read below.
  opt_in_state :=
    app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
      trusted_app_user_id,
      requested_project_id,
      'follow_up_consent_ratio@1'
    );

  IF opt_in_state->>'status' <> 'enabled' THEN
    RETURN jsonb_build_object(
      'contract_id', 'management_follow_up_consent_ratio_candidate_v1',
      'metric_id', 'follow_up_consent_ratio@1',
      'project_id', requested_project_id,
      'status', 'not_enabled'
    );
  END IF;

  -- Re-resolve the release capability after the 0073 state read.  This is
  -- deliberately explicit in this seam so a future change to the 0073 read
  -- function cannot turn the candidate into a view-only or stale-authority
  -- path.
  authorization_evidence :=
    app_private.resolve_management_report_authorization_v1(
      trusted_app_user_id,
      requested_project_id,
      'release_management_reports'
    );

  canonical_request :=
    app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
      jsonb_build_object(
        'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
        'report_version', 1
      )
    );

  report_periods := app_private.resolve_management_report_periods_v1(
    btrim(requested_reporting_time_zone),
    requested_data_cutoff_utc
  );
  IF canonical_request->>'period_boundary_id'
    <> report_periods->>'period_boundary_id'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'management follow-up consent ratio period definition mismatch';
  END IF;

  -- The authorization evidence is intentionally used only to establish the
  -- trusted project scope.  No provenance IDs or user identity are returned.
  WITH bounded_links AS (
    SELECT
      CASE
        WHEN contact_row.occurred_at_utc <
          (report_periods->'current_period'->>'start_utc')::timestamptz
          THEN 'previous'
        ELSE 'current'
      END AS period_key,
      CASE link_row.follow_up_consent
        WHEN 'unknown' THEN 'unanswered'
        ELSE link_row.follow_up_consent
      END AS consent_state,
      contact_row.app_user_id::text AS contributor_key
    FROM app_data.contacts AS contact_row
    JOIN app_data.contact_target_links AS link_row
      ON link_row.contact_id = contact_row.contact_id
     AND link_row.revision_number = contact_row.current_revision
    WHERE contact_row.workspace_id =
        (authorization_evidence->>'organization_workspace_id')::uuid
      AND contact_row.project_id = requested_project_id
      AND contact_row.lifecycle_status = 'active'
      AND contact_row.first_submitted_at_utc <= requested_data_cutoff_utc
      AND contact_row.occurred_at_utc >=
        (report_periods->'previous_period'->>'start_utc')::timestamptz
      AND contact_row.occurred_at_utc <
        (report_periods->'current_period'->>'until_utc')::timestamptz
  ),
  contributions AS (
    SELECT
      bounded_links.period_key,
      bounded_links.consent_state,
      bounded_links.contributor_key,
      count(*)::bigint AS unit_count
    FROM bounded_links
    GROUP BY
      bounded_links.period_key,
      bounded_links.consent_state,
      bounded_links.contributor_key
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period_key', contributions.period_key,
        'consent_state', contributions.consent_state,
        'contributor_key', contributions.contributor_key,
        'unit_count', contributions.unit_count
      ) ORDER BY
        contributions.period_key,
        contributions.consent_state,
        contributions.contributor_key
    ),
    '[]'::jsonb
  )
  INTO contribution_document
  FROM contributions;

  protected_periods :=
    app_private.protect_management_follow_up_consent_ratio_periods_v1(
      contribution_document
    );

  RETURN jsonb_build_object(
    'contract_id', 'management_follow_up_consent_ratio_candidate_v1',
    'report_id', canonical_request->'report_id',
    'report_version', canonical_request->'report_version',
    'metric_id', canonical_request->'metric_id',
    'metric_version', canonical_request->'metric_version',
    'statistical_unit', canonical_request->'statistical_unit',
    'dimension', canonical_request->'dimension',
    'period_grain', canonical_request->'period_grain',
    'comparison_period_count', canonical_request->'comparison_period_count',
    'period_boundary_id', canonical_request->'period_boundary_id',
    'privacy_policy', canonical_request->'privacy_policy',
    'query_fingerprint', canonical_request->'query_fingerprint',
    'source_scope',
      'backend_accepted_active_contact_target_links_current_revision',
    'project_id', requested_project_id,
    'status', 'completed',
    'periods', report_periods,
    'period_results', protected_periods
  );
END
$function$;

-- The candidate is private and release-only.  The 0073 read seam is the only
-- permitted path to the append-only opt-in state; source tables are column
-- allow-listed below and no runtime or ordinary report role is widened.
REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    jsonb
  ),
  app_private.protect_management_follow_up_consent_ratio_periods_v1(jsonb),
  app_private.execute_management_follow_up_consent_ratio_report_v1(
    uuid, uuid, text, timestamp with time zone
  )
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer,
    tongxingzhe_management_follow_up_consent_config_writer;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.read_management_follow_up_consent_opt_in_v1(uuid, uuid, text)
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_management_follow_up_consent_ratio_reader;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
    uuid, uuid, text
  )
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer,
    tongxingzhe_management_follow_up_consent_config_writer;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_management_follow_up_consent_ratio_reader;

REVOKE ALL PRIVILEGES ON TABLE
  app_private.management_report_definitions,
  app_data.app_users,
  app_data.workspaces,
  app_data.projects,
  app_data.organization_memberships,
  app_data.project_memberships,
  app_data.management_report_capability_grants,
  app_data.contacts,
  app_data.contact_target_links
  FROM tongxingzhe_management_follow_up_consent_ratio_reader;

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
TO tongxingzhe_management_follow_up_consent_ratio_reader;

GRANT SELECT (app_user_id, status)
  ON app_data.app_users
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (workspace_id, workspace_kind, deleted_at)
  ON app_data.workspaces
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (project_id, workspace_id, status)
  ON app_data.projects
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  )
  ON app_data.organization_memberships
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (
    project_membership_id,
    organization_membership_id,
    project_id,
    active_from_utc,
    inactive_from_utc
  )
  ON app_data.project_memberships
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (
    capability_grant_id,
    project_membership_id,
    capability_id,
    active_from_utc,
    inactive_from_utc
  )
  ON app_data.management_report_capability_grants
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (
    contact_id,
    app_user_id,
    workspace_id,
    project_id,
    occurred_at_utc,
    first_submitted_at_utc,
    current_revision,
    lifecycle_status
  )
  ON app_data.contacts
  TO tongxingzhe_management_follow_up_consent_ratio_reader;
GRANT SELECT (
  contact_id,
  revision_number,
  follow_up_consent
)
ON app_data.contact_target_links
TO tongxingzhe_management_follow_up_consent_ratio_reader;

GRANT EXECUTE ON FUNCTION
  app_private.management_report_time_zone_valid_v1(text),
  app_private.resolve_management_report_periods_v1(
    text, timestamp with time zone
  ),
  app_private.resolve_management_report_authorization_v1(uuid, uuid, text),
  app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
    uuid, uuid, text
  ),
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    jsonb
  ),
  app_private.protect_management_follow_up_consent_ratio_periods_v1(jsonb),
  app_private.execute_management_follow_up_consent_ratio_report_v1(
    uuid, uuid, text, timestamp with time zone
  )
  TO tongxingzhe_management_follow_up_consent_ratio_reader;

-- The migration identity runs structural/fixture checks.  It does not retain
-- the closed reader membership after the migration transaction.
GRANT EXECUTE ON FUNCTION
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    jsonb
  ),
  app_private.protect_management_follow_up_consent_ratio_periods_v1(jsonb),
  app_private.execute_management_follow_up_consent_ratio_report_v1(
    uuid, uuid, text, timestamp with time zone
  )
  TO CURRENT_USER;

GRANT tongxingzhe_management_follow_up_consent_ratio_reader TO CURRENT_USER;

ALTER FUNCTION
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    jsonb
  ) OWNER TO tongxingzhe_management_follow_up_consent_ratio_reader;
ALTER FUNCTION app_private.protect_management_follow_up_consent_ratio_periods_v1(
  jsonb
) OWNER TO tongxingzhe_management_follow_up_consent_ratio_reader;
ALTER FUNCTION app_private.execute_management_follow_up_consent_ratio_report_v1(
  uuid, uuid, text, timestamp with time zone
) OWNER TO tongxingzhe_management_follow_up_consent_ratio_reader;

ALTER FUNCTION app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
  uuid, uuid, text
) OWNER TO tongxingzhe_management_follow_up_consent_config_writer;

-- The helper is owned by the 0073 configuration role and is the only
-- candidate-to-opt-in boundary.  The underlying 0073 read function remains
-- owner-only, preserving the 6BO ACL contract.
GRANT EXECUTE ON FUNCTION
  app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
    uuid, uuid, text
  )
  TO tongxingzhe_management_follow_up_consent_ratio_reader;

REVOKE tongxingzhe_management_follow_up_consent_ratio_reader FROM CURRENT_USER;

DO $candidate_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS candidate_role
      ON candidate_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE candidate_role.rolname =
      'tongxingzhe_management_follow_up_consent_ratio_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_follow_up_consent_ratio_reader FROM %I',
      member_name
    );
  END LOOP;
END
$candidate_membership$;

ALTER FUNCTION
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    jsonb
  ) OWNER TO tongxingzhe_management_follow_up_consent_ratio_reader;
ALTER FUNCTION app_private.protect_management_follow_up_consent_ratio_periods_v1(
  jsonb
) OWNER TO tongxingzhe_management_follow_up_consent_ratio_reader;
ALTER FUNCTION app_private.execute_management_follow_up_consent_ratio_report_v1(
  uuid, uuid, text, timestamp with time zone
) OWNER TO tongxingzhe_management_follow_up_consent_ratio_reader;
ALTER FUNCTION app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(
  uuid, uuid, text
) OWNER TO tongxingzhe_management_follow_up_consent_config_writer;

COMMENT ON FUNCTION
  app_private.canonicalize_management_follow_up_consent_ratio_request_v1(
    jsonb
  )
IS 'Canonicalizes only contact_target_follow_up_consent_ratio_two_periods@1; it performs no authorization or source read.';

COMMENT ON FUNCTION app_private.protect_management_follow_up_consent_ratio_periods_v1(
  jsonb
)
IS 'Protects fixed previous/current yes/no ratio and independent unanswered/refused/not_applicable cells with k=10, three-contributor, and half-contribution thresholds.';

COMMENT ON FUNCTION app_private.execute_management_follow_up_consent_ratio_report_v1(
  uuid, uuid, text, timestamp with time zone
)
IS 'Builds a private protected two-period follow-up consent candidate after release authorization and 6BO opt-in reauthorization; returns no contact, target, contributor, provenance, raw-answer, or PII fields.';
