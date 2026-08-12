-- synthetic fixture：证明坐标选择当前区域树中含城市父链的最深节点。
BEGIN;

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('resolver-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind, attributes
) VALUES
  ('resolver-us', 'resolver-v1', NULL, 'United States', 'country', '[]'),
  ('resolver-il', 'resolver-v1', 'resolver-us', 'Illinois', 'admin_area', '[]'),
  ('resolver-chicago', 'resolver-v1', 'resolver-il', 'Chicago', 'city', '[]'),
  (
    'resolver-uchicago',
    'resolver-v1',
    'resolver-chicago',
    'University of Chicago',
    'institution',
    '["campus"]'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES
  (
    'resolver-chicago-main',
    'resolver-chicago',
    'resolver-v1',
    polygon '((-87.95,41.64),(-87.50,41.64),(-87.50,42.05),(-87.95,42.05))'
  ),
  (
    'resolver-uchicago-main',
    'resolver-uchicago',
    'resolver-v1',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  );

SELECT app_private.publish_canonical_region_tree_v1('resolver-v1', true);

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture$
DECLARE
  resolved record;
BEGIN
  SELECT * INTO resolved
  FROM app_data.resolve_canonical_region(41.7897, -87.5997);

  IF resolved.region_id IS DISTINCT FROM 'resolver-uchicago'
    OR resolved.tree_version IS DISTINCT FROM 'resolver-v1'
    OR resolved.canonical_name IS DISTINCT FROM 'University of Chicago'
    OR jsonb_array_length(resolved.region_path) <> 4
    OR resolved.region_path->0->>'regionId' <> 'resolver-us'
    OR resolved.region_path->3->>'regionId' <> 'resolver-uchicago'
  THEN
    RAISE EXCEPTION 'coordinate did not resolve to the deepest canonical node';
  END IF;

  IF EXISTS (
    SELECT 1 FROM app_data.resolve_canonical_region(0, 0)
  ) THEN
    RAISE EXCEPTION 'an unmatched coordinate produced a canonical region';
  END IF;

  BEGIN
    PERFORM 1 FROM app_data.canonical_region_boundaries;
    RAISE EXCEPTION 'runtime role read canonical region boundaries directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$fixture$;

ROLLBACK;
