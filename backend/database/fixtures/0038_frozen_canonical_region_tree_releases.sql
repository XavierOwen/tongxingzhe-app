-- synthetic fixture：证明区域树可以在草稿期编辑，发布后内容和发布事实冻结。
BEGIN;

-- 第一个版本先作为草稿建立。发布函数会在同一事务内验证树、计算指纹，
-- 并追加 current 选择；节点和边界不是由 runtime 直接写入。
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
) VALUES ('freeze-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind, attributes
) VALUES
  ('freeze-v1-country', 'freeze-v1', NULL, 'Freeze Country', 'country', '[]'),
  ('freeze-v1-city', 'freeze-v1', 'freeze-v1-country', 'Freeze City', 'city', '[]'),
  ('freeze-v1-venue', 'freeze-v1', 'freeze-v1-city', 'Freeze Venue', 'venue', '["draft"]');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'freeze-v1-venue-boundary',
  'freeze-v1-venue',
  'freeze-v1',
  polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
);

-- 草稿编辑必须仍然可行。
UPDATE app_data.canonical_region_versions
SET canonical_name = 'Freeze Venue (edited before publish)',
    attributes = '["draft", "edited"]'
WHERE region_id = 'freeze-v1-venue' AND tree_version = 'freeze-v1';

SELECT app_private.publish_canonical_region_tree_v1('freeze-v1', true);

DO $published_v1$
DECLARE
  first_fingerprint text;
  second_fingerprint text;
  first_published_at timestamptz;
  second_published_at timestamptz;
  second_sqlstate text;
  failed boolean;
BEGIN
  SELECT content_fingerprint, published_at_utc
    INTO first_fingerprint, first_published_at
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'freeze-v1'
    AND lifecycle_state = 'published'
    AND is_current;
  IF first_fingerprint IS NULL OR first_published_at IS NULL THEN
    RAISE EXCEPTION 'draft tree was not published with fingerprint and timestamp';
  END IF;
  IF first_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'content fingerprint is not a lowercase SHA-256 hex value';
  END IF;

  PERFORM set_config('extra_float_digits', '0', true);
  IF app_private.canonical_region_tree_content_fingerprint_v1('freeze-v1')
    IS DISTINCT FROM first_fingerprint
  THEN
    RAISE EXCEPTION 'content fingerprint depends on session float formatting';
  END IF;
  PERFORM set_config('extra_float_digits', '1', true);

  -- 发布重复请求必须保持指纹和发布时间不变（也可以由函数返回稳定冲突）。
  BEGIN
    PERFORM app_private.publish_canonical_region_tree_v1('freeze-v1', true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS second_sqlstate = RETURNED_SQLSTATE;
    IF second_sqlstate <> '55000' THEN
      RAISE;
    END IF;
  END;
  SELECT content_fingerprint, published_at_utc
    INTO second_fingerprint, second_published_at
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'freeze-v1';
  IF second_fingerprint IS DISTINCT FROM first_fingerprint
    OR second_published_at IS DISTINCT FROM first_published_at
  THEN
    RAISE EXCEPTION 'idempotent publish changed release facts';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_versions
    SET parent_region_id = 'freeze-v1-venue'
    WHERE region_id = 'freeze-v1-city' AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published parent link was mutable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_versions
    SET canonical_name = 'mutated after publish'
    WHERE region_id = 'freeze-v1-venue' AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published canonical name was mutable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_versions
    SET kind = 'institution'
    WHERE region_id = 'freeze-v1-venue' AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published region kind was mutable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_versions
    SET attributes = '["tampered"]'
    WHERE region_id = 'freeze-v1-venue' AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published region attributes were mutable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_boundaries
    SET boundary = polygon '((-87.62,41.78),(-87.57,41.78),(-87.57,41.81),(-87.62,41.81))'
    WHERE boundary_id = 'freeze-v1-venue-boundary'
      AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published boundary was mutable';
  END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.canonical_region_versions (
      region_id, tree_version, parent_region_id, canonical_name, kind
    ) VALUES (
      'freeze-v1-new', 'freeze-v1', 'freeze-v1-city', 'New', 'other'
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published region node was insertable';
  END IF;

  failed := false;
  BEGIN
    DELETE FROM app_data.canonical_region_boundaries
    WHERE boundary_id = 'freeze-v1-venue-boundary'
      AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published boundary was deletable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_tree_releases
    SET published_at_utc = published_at_utc + interval '1 minute'
    WHERE tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published timestamp was mutable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_tree_releases
    SET content_fingerprint = repeat('0', 64)
    WHERE tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published fingerprint was mutable';
  END IF;

  failed := false;
  BEGIN
    PERFORM set_config('app_private.canonical_region_publish', 'on', true);
    UPDATE app_data.canonical_region_tree_releases
    SET published_at_utc = published_at_utc + interval '1 second'
    WHERE tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'session setting bypassed published release guard';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_tree_releases
    SET lifecycle_state = 'draft'
    WHERE tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published lifecycle was mutable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_tree_releases
    SET is_current = false
    WHERE tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current selection was mutable without an audit record';
  END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.canonical_region_versions (
      region_id, tree_version, parent_region_id, canonical_name, kind
    ) VALUES (
      'freeze-v1-inserted-boundary-node', 'freeze-v1',
      'freeze-v1-city', 'Inserted', 'other'
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published node was insertable after earlier guard';
  END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.canonical_region_boundaries (
      boundary_id, region_id, tree_version, boundary
    ) VALUES (
      'freeze-v1-inserted-boundary', 'freeze-v1-venue', 'freeze-v1',
      polygon '((-87.62,41.78),(-87.57,41.78),(-87.57,41.81),(-87.62,41.81))'
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published boundary was insertable';
  END IF;

  failed := false;
  BEGIN
    DELETE FROM app_data.canonical_region_versions
    WHERE region_id = 'freeze-v1-venue' AND tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'published node was deletable';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_tree_current_selections
    SET selected_tree_version = 'freeze-v2'
    WHERE selected_tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current selection history was mutable';
  END IF;

  failed := false;
  BEGIN
    DELETE FROM app_data.canonical_region_tree_current_selections
    WHERE selected_tree_version = 'freeze-v1';
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current selection history was deletable';
  END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.canonical_region_tree_current_selections (
      selected_tree_version,
      previous_tree_version,
      selected_at_utc,
      recorded_at_utc,
      selection_source,
      content_fingerprint
    ) VALUES (
      'freeze-v1',
      NULL,
      '2030-01-01T00:00:00Z',
      '2030-01-01T00:00:00Z',
      'publication',
      repeat('0', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current selection history was directly insertable';
  END IF;

  failed := false;
  BEGIN
    PERFORM set_config('app_private.canonical_region_publish', 'on', true);
    INSERT INTO app_data.canonical_region_tree_current_selections (
      selected_tree_version,
      previous_tree_version,
      selected_at_utc,
      recorded_at_utc,
      selection_source,
      content_fingerprint
    ) VALUES (
      'freeze-v1',
      NULL,
      '2030-01-01T00:00:00Z',
      '2030-01-01T00:00:00Z',
      'publication',
      repeat('0', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'session setting bypassed selection history guard';
  END IF;
  PERFORM set_config('app_private.canonical_region_publish', 'off', true);
END
$published_v1$;

-- 非法树和无边界版本必须在 draft 状态失败，不能留下 current 或半发布事实。
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES
  ('freeze-invalid-cycle', 'draft', false),
  ('freeze-invalid-no-boundary', 'draft', false),
  ('freeze-invalid-no-city', 'draft', false),
  ('freeze-invalid-degenerate-boundary', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  ('freeze-cycle-root', 'freeze-invalid-cycle', NULL, 'Root', 'country'),
  ('freeze-cycle-child', 'freeze-invalid-cycle', 'freeze-cycle-root', 'Child', 'city'),
  ('freeze-no-boundary-root', 'freeze-invalid-no-boundary', NULL, 'Root', 'country'),
  ('freeze-no-boundary-city', 'freeze-invalid-no-boundary', 'freeze-no-boundary-root', 'City', 'city'),
  ('freeze-no-city-root', 'freeze-invalid-no-city', NULL, 'Root', 'country'),
  ('freeze-degenerate-country', 'freeze-invalid-degenerate-boundary', NULL, 'Country', 'country'),
  ('freeze-degenerate-city', 'freeze-invalid-degenerate-boundary', 'freeze-degenerate-country', 'City', 'city'),
  ('freeze-degenerate-venue', 'freeze-invalid-degenerate-boundary', 'freeze-degenerate-city', 'Venue', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES
  (
    'freeze-cycle-boundary', 'freeze-cycle-child', 'freeze-invalid-cycle',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  ),
  (
    'freeze-no-city-boundary', 'freeze-no-city-root', 'freeze-invalid-no-city',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  ),
  (
    'freeze-degenerate-boundary', 'freeze-degenerate-venue',
    'freeze-invalid-degenerate-boundary',
    polygon '((0,0),(1,1),(2,2))'
  );

-- Build a cycle through the existing trigger before invoking publish. The
-- publication validator must still reject the candidate and leave it draft.
DO $cycle$
BEGIN
  ALTER TABLE app_data.canonical_region_versions
    DISABLE TRIGGER canonical_region_cycle_guard;
  BEGIN
    UPDATE app_data.canonical_region_versions
    SET parent_region_id = 'freeze-cycle-child'
    WHERE region_id = 'freeze-cycle-root'
      AND tree_version = 'freeze-invalid-cycle';
  EXCEPTION WHEN OTHERS THEN
    ALTER TABLE app_data.canonical_region_versions
      ENABLE TRIGGER canonical_region_cycle_guard;
    RAISE;
  END;
  ALTER TABLE app_data.canonical_region_versions
    ENABLE TRIGGER canonical_region_cycle_guard;
END
$cycle$;

DO $invalid_publication$
DECLARE
  failed boolean;
  lifecycle text;
  fingerprint text;
BEGIN
  failed := false;
  BEGIN
    PERFORM app_private.publish_canonical_region_tree_v1('freeze-invalid-cycle', false);
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'cyclic tree was published';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.publish_canonical_region_tree_v1('freeze-invalid-no-boundary', false);
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'tree without boundary was published';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.publish_canonical_region_tree_v1('freeze-invalid-no-city', false);
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'tree without city ancestor was published';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.publish_canonical_region_tree_v1(
      'freeze-invalid-degenerate-boundary', false
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'tree without a resolvable boundary was published';
  END IF;

  SELECT lifecycle_state, content_fingerprint
    INTO lifecycle, fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'freeze-invalid-no-boundary';
  IF lifecycle <> 'draft' OR fingerprint IS NOT NULL THEN
    RAISE EXCEPTION 'failed publication left partial release state';
  END IF;
END
$invalid_publication$;

-- 第二个有效版本拥有不同内容，并切换 current；旧版本保持可读。
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('freeze-v2', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind, attributes
) VALUES
  ('freeze-v2-country', 'freeze-v2', NULL, 'Freeze Country', 'country', '[]'),
  ('freeze-v2-city', 'freeze-v2', 'freeze-v2-country', 'Freeze City', 'city', '[]'),
  ('freeze-v2-venue', 'freeze-v2', 'freeze-v2-city', 'Freeze Venue (v2)', 'venue', '["published", "v2"]');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'freeze-v2-venue-boundary',
  'freeze-v2-venue',
  'freeze-v2',
  polygon '((-87.62,41.78),(-87.57,41.78),(-87.57,41.81),(-87.62,41.81))'
);

SELECT app_private.publish_canonical_region_tree_v1('freeze-v2', true);

DO $current_check$
DECLARE
  v1_fingerprint text;
  v2_fingerprint text;
  current_count integer;
  selection_count integer;
  resolved record;
BEGIN
  SELECT content_fingerprint INTO v1_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'freeze-v1';
  SELECT content_fingerprint INTO v2_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'freeze-v2';
  IF v1_fingerprint IS NULL OR v2_fingerprint IS NULL
    OR v1_fingerprint = v2_fingerprint THEN
    RAISE EXCEPTION 'content fingerprint was not stable and content-sensitive';
  END IF;

  SELECT count(*) INTO current_count
  FROM app_data.canonical_region_tree_releases
  WHERE lifecycle_state = 'published' AND is_current;
  IF current_count <> 1 THEN
    RAISE EXCEPTION 'there is not exactly one current published tree: %', current_count;
  END IF;

  -- Concurrency scripts commit their own rows before dump/restore; scope this
  -- fixture assertion to its two synthetic release versions.
  SELECT count(*) INTO selection_count
  FROM app_data.canonical_region_tree_current_selections
  WHERE selected_tree_version IN ('freeze-v1', 'freeze-v2');
  IF selection_count <> 2 THEN
    RAISE EXCEPTION 'current selection history is not append-only: %', selection_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM app_data.canonical_region_tree_releases
    WHERE tree_version = 'freeze-v1'
      AND lifecycle_state = 'published'
      AND NOT is_current
  ) THEN
    RAISE EXCEPTION 'old published tree was not retained after current switch';
  END IF;

END
$current_check$;

SET LOCAL ROLE tongxingzhe_runtime;
DO $runtime_resolver_check$
DECLARE
  resolved record;
BEGIN
  SELECT * INTO resolved
  FROM app_data.resolve_canonical_region(41.7897, -87.5997);
  IF resolved.tree_version IS DISTINCT FROM 'freeze-v2'
    OR resolved.region_id IS DISTINCT FROM 'freeze-v2-venue'
  THEN
    RAISE EXCEPTION 'resolver did not read the committed current published tree';
  END IF;
END
$runtime_resolver_check$;
RESET ROLE;

ROLLBACK;
