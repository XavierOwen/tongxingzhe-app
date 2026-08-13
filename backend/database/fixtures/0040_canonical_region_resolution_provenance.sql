-- synthetic fixture：证明 runtime 可以取得冻结 release 来源，但不能直读
-- release／边界；无命中和非 published／非法指纹结果均 fail closed。
BEGIN;

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('resolver-provenance-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind, attributes
) VALUES
  (
    'resolver-provenance-country', 'resolver-provenance-v1', NULL,
    'Resolver Provenance Country', 'country', '[]'
  ),
  (
    'resolver-provenance-city', 'resolver-provenance-v1',
    'resolver-provenance-country', 'Resolver Provenance City', 'city', '[]'
  ),
  (
    'resolver-provenance-venue', 'resolver-provenance-v1',
    'resolver-provenance-city', 'Resolver Provenance Venue', 'venue', '[]'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'resolver-provenance-boundary',
  'resolver-provenance-venue',
  'resolver-provenance-v1',
  polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'resolver-provenance-v1',
  true
);

CREATE TEMP TABLE resolver_provenance_expected AS
SELECT content_fingerprint
FROM app_data.canonical_region_tree_releases
WHERE tree_version = 'resolver-provenance-v1';

GRANT SELECT ON resolver_provenance_expected TO tongxingzhe_runtime;

SET LOCAL ROLE tongxingzhe_runtime;

DO $runtime_resolver_check$
DECLARE
  resolved record;
BEGIN
  SELECT *
  INTO resolved
  FROM app_data.resolve_canonical_region_with_provenance(41.7897, -87.5997);

  IF resolved.region_id IS DISTINCT FROM 'resolver-provenance-venue'
    OR resolved.tree_version IS DISTINCT FROM 'resolver-provenance-v1'
    OR resolved.canonical_name IS DISTINCT FROM 'Resolver Provenance Venue'
    OR jsonb_array_length(resolved.region_path) <> 3
    OR resolved.region_path->0->>'regionId'
      IS DISTINCT FROM 'resolver-provenance-country'
    OR resolved.region_path->2->>'regionId'
      IS DISTINCT FROM 'resolver-provenance-venue'
    OR resolved.content_fingerprint IS DISTINCT FROM (
      SELECT content_fingerprint
      FROM resolver_provenance_expected
    )
    OR resolved.content_fingerprint !~ '^[0-9a-f]{64}$'
    OR resolved.resolver_contract_version
      IS DISTINCT FROM 'canonical-region-resolution:v1'
  THEN
    RAISE EXCEPTION 'runtime provenance resolver returned incomplete release facts';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.resolve_canonical_region_with_provenance(0, 0)
  ) THEN
    RAISE EXCEPTION 'unmatched coordinate produced a provenance resolution';
  END IF;

  BEGIN
    PERFORM 1 FROM app_data.canonical_region_tree_releases;
    RAISE EXCEPTION 'runtime role read canonical releases directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    PERFORM 1 FROM app_data.canonical_region_boundaries;
    RAISE EXCEPTION 'runtime role read canonical boundaries directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$runtime_resolver_check$;

RESET ROLE;

-- The bridge is deliberately not a publisher or management surface.
SET LOCAL ROLE tongxingzhe_region_publisher;
DO $publisher_permission_check$
BEGIN
  BEGIN
    PERFORM 1
    FROM app_data.resolve_canonical_region_with_provenance(41.7897, -87.5997);
    RAISE EXCEPTION 'region publisher executed the runtime provenance resolver';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$publisher_permission_check$;
RESET ROLE;

ROLLBACK;
