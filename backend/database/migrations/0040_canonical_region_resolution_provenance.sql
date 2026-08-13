-- 0040_canonical_region_resolution_provenance.sql
--
-- Keep the original coordinate resolver compatible, but expose the frozen
-- release facts needed by a trusted location-source envelope through one
-- narrow runtime function.  The runtime role can execute this function; it
-- still cannot read canonical region releases or boundaries directly.

CREATE FUNCTION app_data.resolve_canonical_region_with_provenance(
  latitude double precision,
  longitude double precision
)
RETURNS TABLE (
  region_id text,
  tree_version text,
  canonical_name text,
  region_path jsonb,
  content_fingerprint text,
  resolver_contract_version text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  WITH resolved AS (
    SELECT
      resolution.region_id,
      resolution.tree_version,
      resolution.canonical_name,
      resolution.region_path
    FROM app_data.resolve_canonical_region(latitude, longitude)
      AS resolution
  )
  SELECT
    resolved.region_id,
    resolved.tree_version,
    resolved.canonical_name,
    resolved.region_path,
    release_row.content_fingerprint,
    'canonical-region-resolution:v1'::text
  FROM resolved
  JOIN app_data.canonical_region_tree_releases AS release_row
    ON release_row.tree_version = resolved.tree_version
  WHERE release_row.lifecycle_state = 'published'
    AND release_row.content_fingerprint ~ '^[0-9a-f]{64}$';
$function$;

COMMENT ON FUNCTION app_data.resolve_canonical_region_with_provenance(
  double precision,
  double precision
)
IS 'Narrow runtime bridge: returns an existing canonical match only with published release provenance.';

-- The function is an application boundary, not a general release-table read
-- surface.  Do not grant it to PUBLIC, the region publisher, or any future
-- management role; only the backend runtime may execute it.
REVOKE ALL
  ON FUNCTION app_data.resolve_canonical_region_with_provenance(
    double precision,
    double precision
  )
  FROM PUBLIC, tongxingzhe_region_publisher;

GRANT EXECUTE
  ON FUNCTION app_data.resolve_canonical_region_with_provenance(
    double precision,
    double precision
  )
  TO tongxingzhe_runtime;
