-- 0054_management_region_attribution.sql
--
-- Resolve one immutable location-provenance row for a future fixed management
-- region report. The caller must choose original or provide one explicit
-- published target tree; this migration does not read the mutable current flag.

DO $reader_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_region_attribution_reader'
  ) THEN
    CREATE ROLE tongxingzhe_region_attribution_reader
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

ALTER ROLE tongxingzhe_region_attribution_reader
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

CREATE FUNCTION app_private.resolve_management_region_attribution_v1(
  requested_source_id uuid,
  requested_view_mode text,
  requested_target_tree_version text,
  requested_target_content_fingerprint text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  normalized_view_mode text := btrim(requested_view_mode);
  normalized_target_tree_version text :=
    btrim(requested_target_tree_version);
  normalized_target_fingerprint text :=
    btrim(requested_target_content_fingerprint);
  source_row app_data.contact_location_provenance%ROWTYPE;
  target_release_lifecycle_state text;
  target_release_content_fingerprint text;
  mapped_document jsonb;
  resolved_target_region_id text;
  source_has_city boolean;
  target_has_city boolean;
  coordinate_match_count integer;
  coordinate_qualified_count integer;
  coordinate_deepest_count integer;
  coordinate_selected_region_id text;
  coordinate_has_cross_branch boolean;
BEGIN
  IF requested_source_id IS NULL
    OR normalized_view_mode IS NULL
    OR normalized_view_mode NOT IN ('original', 'current')
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management region attribution request';
  END IF;

  IF normalized_view_mode = 'original' THEN
    IF requested_target_tree_version IS NOT NULL
      OR requested_target_content_fingerprint IS NOT NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'original region attribution does not accept a target tree';
    END IF;
  ELSIF normalized_target_tree_version IS NULL
    OR length(normalized_target_tree_version) = 0
    OR normalized_target_fingerprint IS NULL
    OR normalized_target_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'current region attribution requires a target tree fingerprint';
  END IF;

  -- A current request validates its explicit target even when the source later
  -- proves not reportable. Invalid target evidence never becomes a soft status.
  IF normalized_view_mode = 'current' THEN
    SELECT
      release_row.lifecycle_state,
      release_row.content_fingerprint
    INTO
      target_release_lifecycle_state,
      target_release_content_fingerprint
    FROM app_data.canonical_region_tree_releases AS release_row
    WHERE release_row.tree_version = normalized_target_tree_version;

    IF NOT FOUND
      OR target_release_lifecycle_state <> 'published'
      OR target_release_content_fingerprint
        IS DISTINCT FROM normalized_target_fingerprint
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'management region attribution target is unavailable';
    END IF;
  END IF;

  SELECT *
  INTO source_row
  FROM app_data.contact_location_provenance AS source
  WHERE source.source_id = requested_source_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', normalized_view_mode,
      'result_status', 'not_reportable',
      'reason_code', 'source_unavailable'
    );
  END IF;

  IF source_row.location_kind = 'pending_resolution'
    AND source_row.evidence_kind = 'pending_coordinates'
  THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', normalized_view_mode,
      'result_status', 'not_reportable',
      'reason_code', 'pending_resolution'
    );
  ELSIF source_row.location_kind = 'not_applicable'
    AND source_row.evidence_kind = 'not_applicable'
  THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', normalized_view_mode,
      'result_status', 'not_reportable',
      'reason_code', 'not_applicable'
    );
  ELSIF source_row.location_kind = 'unknown'
    AND source_row.evidence_kind = 'legacy_incomplete'
  THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', normalized_view_mode,
      'result_status', 'not_reportable',
      'reason_code', 'source_incomplete'
    );
  END IF;

  IF source_row.location_kind <> 'resolved'
    OR source_row.evidence_kind NOT IN (
      'resolved_from_coordinates',
      'resolved_region_only'
    )
    OR source_row.smallest_region_id IS NULL
    OR source_row.region_tree_version IS NULL
    OR source_row.region_tree_content_fingerprint IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'management region attribution source shape is invalid';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_tree_releases AS release_row
    WHERE release_row.tree_version = source_row.region_tree_version
      AND release_row.lifecycle_state = 'published'
      AND release_row.content_fingerprint
        = source_row.region_tree_content_fingerprint
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_versions AS node
    WHERE node.tree_version = source_row.region_tree_version
      AND node.region_id = source_row.smallest_region_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'management region attribution source evidence is unavailable';
  END IF;

  WITH RECURSIVE source_ancestors AS (
    SELECT
      node.region_id,
      node.parent_region_id,
      node.kind
    FROM app_data.canonical_region_versions AS node
    WHERE node.tree_version = source_row.region_tree_version
      AND node.region_id = source_row.smallest_region_id
    UNION ALL
    SELECT
      parent.region_id,
      parent.parent_region_id,
      parent.kind
    FROM source_ancestors AS child
    JOIN app_data.canonical_region_versions AS parent
      ON parent.tree_version = source_row.region_tree_version
      AND parent.region_id = child.parent_region_id
  )
  SELECT COALESCE(bool_or(kind = 'city'), false)
  INTO source_has_city
  FROM source_ancestors;

  IF NOT source_has_city THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', normalized_view_mode,
      'result_status', 'not_reportable',
      'reason_code', 'source_region_not_reportable'
    );
  END IF;

  IF normalized_view_mode = 'original' THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', 'original',
      'result_status', 'attributed',
      'reason_code', 'original_exact_source',
      'region_id', source_row.smallest_region_id,
      'tree_version', source_row.region_tree_version,
      'content_fingerprint',
        source_row.region_tree_content_fingerprint
    );
  END IF;

  IF source_row.evidence_kind = 'resolved_region_only' THEN
    IF source_row.region_tree_version = normalized_target_tree_version THEN
      RETURN jsonb_build_object(
        'attribution_contract_id', 'management-region-attribution:v1',
        'view_mode', 'current',
        'result_status', 'attributed',
        'reason_code', 'current_same_version_source',
        'region_id', source_row.smallest_region_id,
        'tree_version', normalized_target_tree_version,
        'content_fingerprint', normalized_target_fingerprint
      );
    END IF;

    mapped_document :=
      app_private.resolve_canonical_region_version_mapping_v1(
        source_row.region_tree_version,
        source_row.smallest_region_id,
        source_row.region_tree_content_fingerprint,
        normalized_target_tree_version,
        normalized_target_fingerprint
      );

    IF mapped_document->>'mapping_status' <> 'mapped' THEN
      RETURN jsonb_build_object(
        'attribution_contract_id', 'management-region-attribution:v1',
        'view_mode', 'current',
        'result_status', 'unmapped',
        'reason_code', 'explicit_mapping_missing'
      );
    END IF;

    resolved_target_region_id := mapped_document->>'target_region_id';
    WITH RECURSIVE target_ancestors AS (
      SELECT
        node.region_id,
        node.parent_region_id,
        node.kind
      FROM app_data.canonical_region_versions AS node
      WHERE node.tree_version = normalized_target_tree_version
        AND node.region_id = resolved_target_region_id
      UNION ALL
      SELECT
        parent.region_id,
        parent.parent_region_id,
        parent.kind
      FROM target_ancestors AS child
      JOIN app_data.canonical_region_versions AS parent
        ON parent.tree_version = normalized_target_tree_version
        AND parent.region_id = child.parent_region_id
    )
    SELECT COALESCE(bool_or(kind = 'city'), false)
    INTO target_has_city
    FROM target_ancestors;

    IF NOT target_has_city THEN
      RETURN jsonb_build_object(
        'attribution_contract_id', 'management-region-attribution:v1',
        'view_mode', 'current',
        'result_status', 'unmapped',
        'reason_code', 'target_region_not_reportable'
      );
    END IF;

    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', 'current',
      'result_status', 'attributed',
      'reason_code', 'current_explicit_mapping',
      'region_id', resolved_target_region_id,
      'tree_version', normalized_target_tree_version,
      'content_fingerprint', normalized_target_fingerprint
    );
  END IF;

  -- Coordinates are sensitive source evidence. They are consumed inside this
  -- function and never copied into the returned attribution document.
  WITH RECURSIVE matching_regions AS (
    SELECT DISTINCT boundary_row.region_id
    FROM app_data.canonical_region_boundaries AS boundary_row
    WHERE boundary_row.tree_version = normalized_target_tree_version
      AND point(source_row.longitude, source_row.latitude)
        <@ boundary_row.boundary
  ),
  candidate_ancestors AS (
    SELECT
      candidate.region_id AS candidate_region_id,
      node.region_id,
      node.parent_region_id,
      node.kind,
      0 AS depth
    FROM matching_regions AS candidate
    JOIN app_data.canonical_region_versions AS node
      ON node.tree_version = normalized_target_tree_version
      AND node.region_id = candidate.region_id
    UNION ALL
    SELECT
      child.candidate_region_id,
      parent.region_id,
      parent.parent_region_id,
      parent.kind,
      child.depth + 1
    FROM candidate_ancestors AS child
    JOIN app_data.canonical_region_versions AS parent
      ON parent.tree_version = normalized_target_tree_version
      AND parent.region_id = child.parent_region_id
  ),
  qualified_candidates AS (
    SELECT
      candidate_region_id,
      max(depth) AS maximum_depth
    FROM candidate_ancestors
    GROUP BY candidate_region_id
    HAVING bool_or(kind = 'city')
  ),
  deepest_candidates AS (
    SELECT candidate_region_id
    FROM qualified_candidates
    WHERE maximum_depth = (
      SELECT max(maximum_depth)
      FROM qualified_candidates
    )
  ),
  selected_candidate AS (
    SELECT candidate_region_id
    FROM deepest_candidates
    WHERE (SELECT count(*) FROM deepest_candidates) = 1
  ),
  selected_ancestors AS (
    SELECT ancestor.region_id
    FROM candidate_ancestors AS ancestor
    JOIN selected_candidate AS selected
      ON selected.candidate_region_id = ancestor.candidate_region_id
  )
  SELECT
    (SELECT count(*) FROM matching_regions),
    (SELECT count(*) FROM qualified_candidates),
    (SELECT count(*) FROM deepest_candidates),
    (SELECT candidate_region_id FROM selected_candidate),
    EXISTS (
      SELECT 1
      FROM matching_regions AS matched
      WHERE NOT EXISTS (
        SELECT 1
        FROM selected_ancestors AS ancestor
        WHERE ancestor.region_id = matched.region_id
      )
    )
  INTO
    coordinate_match_count,
    coordinate_qualified_count,
    coordinate_deepest_count,
    coordinate_selected_region_id,
    coordinate_has_cross_branch;

  IF coordinate_match_count = 0 THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', 'current',
      'result_status', 'unmapped',
      'reason_code', 'coordinate_no_match'
    );
  ELSIF coordinate_qualified_count = 0 THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', 'current',
      'result_status', 'unmapped',
      'reason_code', 'target_region_not_reportable'
    );
  ELSIF coordinate_deepest_count <> 1
    OR coordinate_has_cross_branch
  THEN
    RETURN jsonb_build_object(
      'attribution_contract_id', 'management-region-attribution:v1',
      'view_mode', 'current',
      'result_status', 'ambiguous',
      'reason_code', 'coordinate_ambiguous'
    );
  END IF;

  RETURN jsonb_build_object(
    'attribution_contract_id', 'management-region-attribution:v1',
    'view_mode', 'current',
    'result_status', 'attributed',
    'reason_code', 'current_coordinate_match',
    'region_id', coordinate_selected_region_id,
    'tree_version', normalized_target_tree_version,
    'content_fingerprint', normalized_target_fingerprint
  );
END
$function$;

REVOKE ALL
  ON FUNCTION app_private.resolve_management_region_attribution_v1(
    uuid, text, text, text
  )
  FROM
    PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_region_attribution_reader;
GRANT SELECT ON
  app_data.contact_location_provenance,
  app_data.canonical_region_tree_releases,
  app_data.canonical_region_versions,
  app_data.canonical_region_boundaries
  TO tongxingzhe_region_attribution_reader;
GRANT EXECUTE ON FUNCTION
  app_private.resolve_canonical_region_version_mapping_v1(
    text, text, text, text, text
  )
  TO tongxingzhe_region_attribution_reader;

-- Keep the migration identity able to run the synthetic fixture without
-- retaining membership in the internal reader role.
GRANT EXECUTE ON FUNCTION
  app_private.resolve_management_region_attribution_v1(
    uuid, text, text, text
  )
  TO CURRENT_USER;

GRANT tongxingzhe_region_attribution_reader TO CURRENT_USER;
ALTER FUNCTION app_private.resolve_management_region_attribution_v1(
  uuid, text, text, text
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

COMMENT ON FUNCTION app_private.resolve_management_region_attribution_v1(
  uuid, text, text, text
) IS 'Resolves one private location source for an explicit original or target-tree view without reading current selection or exposing coordinates.';
