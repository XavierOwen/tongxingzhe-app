-- 0007_canonical_region_resolution.sql
--
-- 为平台治理的规范区域树保存可移植的 PostgreSQL 多边形边界，并提供最小
-- 只读解析函数。无当前版本或坐标未命中时返回空结果，调用方继续保留待解析。

CREATE TABLE app_data.canonical_region_tree_releases (
  tree_version text PRIMARY KEY
    CHECK (length(btrim(tree_version)) > 0),
  published_at_utc timestamptz NOT NULL,
  is_current boolean NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX canonical_region_tree_one_current
  ON app_data.canonical_region_tree_releases (is_current)
  WHERE is_current;

CREATE TABLE app_data.canonical_region_boundaries (
  boundary_id text NOT NULL CHECK (length(btrim(boundary_id)) > 0),
  region_id text NOT NULL,
  tree_version text NOT NULL
    REFERENCES app_data.canonical_region_tree_releases (tree_version)
    ON DELETE RESTRICT,
  boundary polygon NOT NULL,
  PRIMARY KEY (tree_version, boundary_id),
  FOREIGN KEY (region_id, tree_version)
    REFERENCES app_data.canonical_region_versions (region_id, tree_version)
    ON DELETE RESTRICT
);

CREATE INDEX canonical_region_boundaries_region
  ON app_data.canonical_region_boundaries (tree_version, region_id);

CREATE INDEX canonical_region_boundaries_geometry
  ON app_data.canonical_region_boundaries
  USING gist (boundary);

REVOKE ALL PRIVILEGES
  ON app_data.canonical_region_tree_releases,
     app_data.canonical_region_boundaries
  FROM tongxingzhe_runtime;

CREATE OR REPLACE FUNCTION app_data.resolve_canonical_region(
  latitude double precision,
  longitude double precision
)
RETURNS TABLE (
  region_id text,
  tree_version text,
  canonical_name text,
  region_path jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  WITH RECURSIVE matching_boundaries AS (
    SELECT
      boundary_row.boundary_id,
      boundary_row.region_id,
      boundary_row.tree_version,
      region_row.canonical_name
    FROM app_data.canonical_region_boundaries AS boundary_row
    JOIN app_data.canonical_region_tree_releases AS release_row
      ON release_row.tree_version = boundary_row.tree_version
      AND release_row.is_current
    JOIN app_data.canonical_region_versions AS region_row
      ON region_row.region_id = boundary_row.region_id
      AND region_row.tree_version = boundary_row.tree_version
    WHERE latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
      AND point(longitude, latitude) <@ boundary_row.boundary
  ),
  ancestor_walk AS (
    SELECT
      candidate.boundary_id,
      candidate.region_id AS candidate_region_id,
      candidate.tree_version,
      candidate.canonical_name AS candidate_name,
      region_row.region_id,
      region_row.parent_region_id,
      region_row.canonical_name,
      region_row.kind,
      region_row.attributes,
      0 AS depth
    FROM matching_boundaries AS candidate
    JOIN app_data.canonical_region_versions AS region_row
      ON region_row.region_id = candidate.region_id
      AND region_row.tree_version = candidate.tree_version
    UNION ALL
    SELECT
      child.boundary_id,
      child.candidate_region_id,
      child.tree_version,
      child.candidate_name,
      parent.region_id,
      parent.parent_region_id,
      parent.canonical_name,
      parent.kind,
      parent.attributes,
      child.depth + 1
    FROM ancestor_walk AS child
    JOIN app_data.canonical_region_versions AS parent
      ON parent.region_id = child.parent_region_id
      AND parent.tree_version = child.tree_version
  ),
  qualified AS (
    SELECT
      boundary_id,
      candidate_region_id,
      tree_version,
      candidate_name,
      max(depth) AS maximum_depth
    FROM ancestor_walk
    GROUP BY
      boundary_id,
      candidate_region_id,
      tree_version,
      candidate_name
    HAVING bool_or(kind = 'city')
  )
  SELECT
    candidate.candidate_region_id,
    candidate.tree_version,
    candidate.candidate_name,
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'regionId', path.region_id,
          'parentRegionId', path.parent_region_id,
          'canonicalName', path.canonical_name,
          'kind', path.kind,
          'attributes', path.attributes
        )
        ORDER BY path.depth DESC
      )
      FROM ancestor_walk AS path
      WHERE path.boundary_id = candidate.boundary_id
        AND path.tree_version = candidate.tree_version
    )
  FROM qualified AS candidate
  ORDER BY
    candidate.maximum_depth DESC,
    candidate.candidate_region_id,
    candidate.boundary_id
  LIMIT 1;
$function$;

REVOKE ALL
  ON FUNCTION app_data.resolve_canonical_region(
    double precision,
    double precision
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.resolve_canonical_region(
    double precision,
    double precision
  )
  TO tongxingzhe_runtime;
