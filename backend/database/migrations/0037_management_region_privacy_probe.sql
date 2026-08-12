-- 0037_management_region_privacy_probe.sql
--
-- 对固定 synthetic 区域候选运行披露风险探针。该函数不查询业务表、不注册
-- 报告，也不向 runtime 开放。结果只含稳定身份、状态和 allowlist 原因码。

CREATE FUNCTION app_private.assess_management_region_privacy_v1(
  requested_probe jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  reason_codes text[] := ARRAY[]::text[];
BEGIN
  IF requested_probe IS NULL
    OR jsonb_typeof(requested_probe) <> 'object'
    OR NOT requested_probe ?& ARRAY[
      'probe_id',
      'query_fingerprint',
      'view_mode',
      'tree_version',
      'region_granularity',
      'reports',
      'region_relationships',
      'query_overlaps',
      'version_mappings',
      'location_states',
      'external_facts'
    ]
    OR requested_probe - ARRAY[
      'probe_id',
      'query_fingerprint',
      'view_mode',
      'tree_version',
      'region_granularity',
      'reports',
      'region_relationships',
      'query_overlaps',
      'version_mappings',
      'location_states',
      'external_facts'
    ] <> '{}'::jsonb
    OR requested_probe->>'probe_id'
      IS DISTINCT FROM 'management_region_privacy_probe_v1'
    OR requested_probe->>'query_fingerprint'
      IS DISTINCT FROM 'management-region-privacy-probe:v1'
    OR jsonb_typeof(requested_probe->'view_mode') <> 'string'
    OR length(btrim(requested_probe->>'view_mode')) = 0
    OR jsonb_typeof(requested_probe->'tree_version') <> 'string'
    OR length(btrim(requested_probe->>'tree_version')) = 0
    OR jsonb_typeof(requested_probe->'region_granularity') <> 'string'
    OR length(btrim(requested_probe->>'region_granularity')) = 0
    OR jsonb_typeof(requested_probe->'reports') <> 'array'
    OR jsonb_array_length(requested_probe->'reports') = 0
    OR jsonb_typeof(requested_probe->'region_relationships') <> 'array'
    OR jsonb_typeof(requested_probe->'query_overlaps') <> 'array'
    OR jsonb_typeof(requested_probe->'version_mappings') <> 'array'
    OR jsonb_typeof(requested_probe->'location_states') <> 'array'
    OR jsonb_typeof(requested_probe->'external_facts') <> 'array'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management region privacy probe';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    WHERE jsonb_typeof(item) <> 'object'
      OR NOT item ?& ARRAY[
        'report_key',
        'period_key',
        'view_mode',
        'tree_version',
        'region_granularity',
        'scope_kind',
        'cells'
      ]
      OR item - ARRAY[
        'report_key',
        'period_key',
        'view_mode',
        'tree_version',
        'region_granularity',
        'scope_kind',
        'cells'
      ] <> '{}'::jsonb
      OR jsonb_typeof(item->'report_key') <> 'string'
      OR length(btrim(item->>'report_key')) = 0
      OR jsonb_typeof(item->'period_key') <> 'string'
      OR length(btrim(item->>'period_key')) = 0
      OR jsonb_typeof(item->'view_mode') <> 'string'
      OR length(btrim(item->>'view_mode')) = 0
      OR jsonb_typeof(item->'tree_version') <> 'string'
      OR length(btrim(item->>'tree_version')) = 0
      OR jsonb_typeof(item->'region_granularity') <> 'string'
      OR length(btrim(item->>'region_granularity')) = 0
      OR jsonb_typeof(item->'scope_kind') <> 'string'
      OR length(btrim(item->>'scope_kind')) = 0
      OR jsonb_typeof(item->'cells') <> 'array'
      OR jsonb_array_length(item->'cells') = 0
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    CROSS JOIN LATERAL jsonb_array_elements(item->'cells') AS cell(item)
    WHERE jsonb_typeof(cell.item) <> 'object'
      OR NOT cell.item ?& ARRAY[
        'region_id',
        'tree_version',
        'privacy_status',
        'value_count',
        'contributor_count',
        'max_contribution',
        'category_key'
      ]
      OR cell.item - ARRAY[
        'region_id',
        'tree_version',
        'privacy_status',
        'value_count',
        'contributor_count',
        'max_contribution',
        'category_key'
      ] <> '{}'::jsonb
      OR jsonb_typeof(cell.item->'region_id') <> 'string'
      OR length(btrim(cell.item->>'region_id')) = 0
      OR jsonb_typeof(cell.item->'tree_version') <> 'string'
      OR length(btrim(cell.item->>'tree_version')) = 0
      OR jsonb_typeof(cell.item->'privacy_status') <> 'string'
      OR cell.item->>'privacy_status' NOT IN ('displayed', 'suppressed')
      OR jsonb_typeof(cell.item->'contributor_count') <> 'number'
      OR cell.item->>'contributor_count' !~ '^[0-9]+$'
      OR jsonb_typeof(cell.item->'max_contribution') <> 'number'
      OR cell.item->>'max_contribution' !~ '^[0-9]+$'
      OR jsonb_typeof(cell.item->'category_key') <> 'string'
      OR length(btrim(cell.item->>'category_key')) = 0
      OR (
        cell.item->>'privacy_status' = 'displayed'
        AND (
          jsonb_typeof(cell.item->'value_count') <> 'number'
          OR cell.item->>'value_count' !~ '^[0-9]+$'
        )
      )
      OR (
        cell.item->>'privacy_status' = 'suppressed'
        AND cell.item->'value_count' <> 'null'::jsonb
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management region privacy probe';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      requested_probe->'region_relationships'
    ) AS relationship(item)
    WHERE jsonb_typeof(item) <> 'object'
      OR NOT item ?& ARRAY[
        'parent_region_id', 'child_region_id', 'tree_version'
      ]
      OR item - ARRAY[
        'parent_region_id', 'child_region_id', 'tree_version'
      ] <> '{}'::jsonb
      OR jsonb_typeof(item->'parent_region_id') <> 'string'
      OR jsonb_typeof(item->'child_region_id') <> 'string'
      OR jsonb_typeof(item->'tree_version') <> 'string'
      OR length(btrim(item->>'parent_region_id')) = 0
      OR length(btrim(item->>'child_region_id')) = 0
      OR length(btrim(item->>'tree_version')) = 0
      OR item->>'parent_region_id' = item->>'child_region_id'
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'query_overlaps')
      AS overlap(item)
    WHERE jsonb_typeof(item) <> 'object'
      OR NOT item ?& ARRAY[
        'left_region_id',
        'left_tree_version',
        'right_region_id',
        'right_tree_version'
      ]
      OR item - ARRAY[
        'left_region_id',
        'left_tree_version',
        'right_region_id',
        'right_tree_version'
      ] <> '{}'::jsonb
      OR jsonb_typeof(item->'left_region_id') <> 'string'
      OR jsonb_typeof(item->'left_tree_version') <> 'string'
      OR jsonb_typeof(item->'right_region_id') <> 'string'
      OR jsonb_typeof(item->'right_tree_version') <> 'string'
      OR length(btrim(item->>'left_region_id')) = 0
      OR length(btrim(item->>'left_tree_version')) = 0
      OR length(btrim(item->>'right_region_id')) = 0
      OR length(btrim(item->>'right_tree_version')) = 0
      OR (
        item->>'left_region_id' = item->>'right_region_id'
        AND item->>'left_tree_version' = item->>'right_tree_version'
      )
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'version_mappings')
      AS mapping(item)
    WHERE jsonb_typeof(item) <> 'object'
      OR NOT item ?& ARRAY[
        'from_region_id',
        'from_tree_version',
        'to_region_id',
        'to_tree_version'
      ]
      OR item - ARRAY[
        'from_region_id',
        'from_tree_version',
        'to_region_id',
        'to_tree_version'
      ] <> '{}'::jsonb
      OR jsonb_typeof(item->'from_region_id') <> 'string'
      OR jsonb_typeof(item->'from_tree_version') <> 'string'
      OR jsonb_typeof(item->'to_region_id') <> 'string'
      OR jsonb_typeof(item->'to_tree_version') <> 'string'
      OR length(btrim(item->>'from_region_id')) = 0
      OR length(btrim(item->>'from_tree_version')) = 0
      OR length(btrim(item->>'to_region_id')) = 0
      OR length(btrim(item->>'to_tree_version')) = 0
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'location_states')
      AS location(item)
    WHERE jsonb_typeof(item) <> 'object'
      OR NOT item ?& ARRAY[
        'state', 'region_id', 'tree_version', 'included_in_region_cell'
      ]
      OR item - ARRAY[
        'state', 'region_id', 'tree_version', 'included_in_region_cell'
      ] <> '{}'::jsonb
      OR jsonb_typeof(item->'state') <> 'string'
      OR item->>'state' NOT IN (
        'resolved', 'pending_resolution', 'not_applicable'
      )
      OR jsonb_typeof(item->'included_in_region_cell') <> 'boolean'
      OR jsonb_typeof(item->'region_id') NOT IN ('string', 'null')
      OR jsonb_typeof(item->'tree_version') NOT IN ('string', 'null')
      OR (
        item->>'state' = 'resolved'
        AND (
          jsonb_typeof(item->'region_id') <> 'string'
          OR jsonb_typeof(item->'tree_version') <> 'string'
          OR length(btrim(item->>'region_id')) = 0
          OR length(btrim(item->>'tree_version')) = 0
        )
      )
      OR (
        item->>'state' = 'pending_resolution'
        AND (
          jsonb_typeof(item->'region_id') <> 'null'
          OR jsonb_typeof(item->'tree_version') <> 'null'
        )
      )
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'external_facts')
      AS fact(item)
    WHERE jsonb_typeof(item) <> 'object'
      OR NOT item ?& ARRAY[
        'fact_kind',
        'known_unit_count',
        'target_region_id',
        'target_tree_version',
        'period_key',
        'category_key'
      ]
      OR item - ARRAY[
        'fact_kind',
        'known_unit_count',
        'target_region_id',
        'target_tree_version',
        'period_key',
        'category_key'
      ] <> '{}'::jsonb
      OR jsonb_typeof(item->'fact_kind') <> 'string'
      OR length(btrim(item->>'fact_kind')) = 0
      OR jsonb_typeof(item->'known_unit_count') <> 'number'
      OR item->>'known_unit_count' !~ '^[0-9]+$'
      OR jsonb_typeof(item->'target_region_id') <> 'string'
      OR jsonb_typeof(item->'target_tree_version') <> 'string'
      OR jsonb_typeof(item->'period_key') <> 'string'
      OR jsonb_typeof(item->'category_key') <> 'string'
      OR length(btrim(item->>'target_region_id')) = 0
      OR length(btrim(item->>'target_tree_version')) = 0
      OR length(btrim(item->>'period_key')) = 0
      OR length(btrim(item->>'category_key')) = 0
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management region privacy probe';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    GROUP BY report.item->>'report_key'
    HAVING count(*) > 1
  ) OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports')
      WITH ORDINALITY AS report(item, report_index)
    CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells') AS cell(item)
    GROUP BY
      report.report_index,
      cell.item->>'region_id',
      cell.item->>'tree_version',
      cell.item->>'category_key'
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management region privacy probe';
  END IF;

  -- 父子节点都显示会开放直接包含差分。
  IF EXISTS (
    WITH cells AS (
      SELECT
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'privacy_status' AS privacy_status
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'region_relationships')
      AS relationship(item)
    JOIN cells AS parent
      ON parent.region_id = relationship.item->>'parent_region_id'
     AND parent.tree_version = relationship.item->>'tree_version'
     AND parent.privacy_status = 'displayed'
    JOIN cells AS child
      ON child.region_id = relationship.item->>'child_region_id'
     AND child.tree_version = relationship.item->>'tree_version'
     AND child.privacy_status = 'displayed'
     AND child.period_key = parent.period_key
  ) THEN
    reason_codes = array_append(reason_codes, 'parent_child_overlap');
  END IF;

  -- 非父子关系也可能代表两个查询集合有交集。
  IF EXISTS (
    WITH cells AS (
      SELECT
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'privacy_status' AS privacy_status
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'query_overlaps')
      AS overlap(item)
    JOIN cells AS left_cell
      ON left_cell.region_id = overlap.item->>'left_region_id'
     AND left_cell.tree_version = overlap.item->>'left_tree_version'
     AND left_cell.privacy_status = 'displayed'
    JOIN cells AS right_cell
      ON right_cell.region_id = overlap.item->>'right_region_id'
     AND right_cell.tree_version = overlap.item->>'right_tree_version'
     AND right_cell.privacy_status = 'displayed'
     AND right_cell.period_key = left_cell.period_key
  ) THEN
    reason_codes = array_append(reason_codes, 'overlapping_query_sets');
  END IF;

  IF EXISTS (
    WITH cells AS (
      SELECT
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'version_mappings')
      AS mapping(item)
    JOIN cells AS source
      ON source.region_id = mapping.item->>'from_region_id'
     AND source.tree_version = mapping.item->>'from_tree_version'
    JOIN cells AS target
      ON target.region_id = mapping.item->>'to_region_id'
     AND target.tree_version = mapping.item->>'to_tree_version'
     AND target.period_key = source.period_key
  ) THEN
    reason_codes = array_append(reason_codes, 'cross_version_overlap');
  END IF;

  IF EXISTS (
    WITH cells AS (
      SELECT
        report.report_index,
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'category_key' AS category_key,
        cell.item->>'privacy_status' AS privacy_status,
        (cell.item->>'value_count')::numeric AS value_count
      FROM jsonb_array_elements(requested_probe->'reports')
        WITH ORDINALITY AS report(item, report_index)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM cells AS earlier
    JOIN cells AS later
      ON later.report_index > earlier.report_index
     AND later.period_key = earlier.period_key
     AND later.region_id = earlier.region_id
     AND later.tree_version = earlier.tree_version
     AND later.category_key = earlier.category_key
    WHERE earlier.privacy_status = 'displayed'
      AND later.privacy_status = 'displayed'
      AND earlier.value_count <> later.value_count
  ) THEN
    reason_codes = array_append(
      reason_codes, 'shared_period_value_changed'
    );
  END IF;

  IF EXISTS (
    WITH cells AS (
      SELECT
        report.report_index,
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'category_key' AS category_key,
        cell.item->>'privacy_status' AS privacy_status
      FROM jsonb_array_elements(requested_probe->'reports')
        WITH ORDINALITY AS report(item, report_index)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM cells AS earlier
    JOIN cells AS later
      ON later.report_index > earlier.report_index
     AND later.period_key = earlier.period_key
     AND later.region_id = earlier.region_id
     AND later.tree_version = earlier.tree_version
     AND later.category_key = earlier.category_key
    WHERE earlier.privacy_status <> later.privacy_status
  ) THEN
    reason_codes = array_append(
      reason_codes, 'shared_period_privacy_status_changed'
    );
  END IF;

  IF EXISTS (
    WITH cells AS (
      SELECT
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'privacy_status' AS privacy_status
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'region_relationships')
      AS relationship(item)
    JOIN cells AS parent
      ON parent.region_id = relationship.item->>'parent_region_id'
     AND parent.tree_version = relationship.item->>'tree_version'
     AND parent.privacy_status = 'displayed'
    JOIN cells AS child
      ON child.region_id = relationship.item->>'child_region_id'
     AND child.tree_version = relationship.item->>'tree_version'
     AND child.privacy_status = 'suppressed'
     AND child.period_key = parent.period_key
  ) OR EXISTS (
    WITH cells AS (
      SELECT
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'privacy_status' AS privacy_status,
        cell.item->>'category_key' AS category_key
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM cells AS total
    JOIN cells AS category
      ON category.period_key = total.period_key
     AND category.region_id = total.region_id
     AND category.tree_version = total.tree_version
     AND category.category_key <> 'all'
     AND category.privacy_status = 'suppressed'
    WHERE total.category_key = 'all'
      AND total.privacy_status = 'displayed'
  ) THEN
    reason_codes = array_append(
      reason_codes, 'complementary_cell_exposure'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
      AS cell(item)
    WHERE cell.item->>'privacy_status' = 'suppressed'
  ) THEN
    reason_codes = array_append(reason_codes, 'sparse_cell');
  END IF;

  IF EXISTS (
    WITH cells AS (
      SELECT
        report.item->>'period_key' AS period_key,
        cell.item->>'region_id' AS region_id,
        cell.item->>'tree_version' AS tree_version,
        cell.item->>'category_key' AS category_key
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
        AS cell(item)
    )
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'external_facts') AS fact(item)
    JOIN cells
      ON cells.region_id = fact.item->>'target_region_id'
     AND cells.tree_version = fact.item->>'target_tree_version'
     AND cells.period_key = fact.item->>'period_key'
     AND cells.category_key = fact.item->>'category_key'
    WHERE (fact.item->>'known_unit_count')::numeric BETWEEN 1 AND 9
  ) THEN
    reason_codes = array_append(reason_codes, 'external_fact_exposure');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
      AS cell(item)
    WHERE cell.item->>'privacy_status' = 'displayed'
      AND (
        (cell.item->>'value_count')::numeric < 10
        OR (cell.item->>'contributor_count')::numeric < 3
        OR (cell.item->>'max_contribution')::numeric * 2
          > (cell.item->>'value_count')::numeric
      )
  ) THEN
    reason_codes = array_append(reason_codes, 'threshold_error_exposure');
  END IF;

  IF requested_probe->>'view_mode' = 'original' AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells') AS cell(item)
    WHERE NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_probe->'location_states')
        AS location(item)
      WHERE location.item->>'state' = 'resolved'
        AND (location.item->>'included_in_region_cell')::boolean
        AND location.item->>'region_id' = cell.item->>'region_id'
        AND location.item->>'tree_version' = cell.item->>'tree_version'
    )
  ) THEN
    reason_codes = array_append(reason_codes, 'original_provenance_missing');
  END IF;

  IF requested_probe->>'view_mode' = 'current' AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells') AS cell(item)
    WHERE NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_probe->'location_states')
        AS location(item)
      WHERE location.item->>'state' = 'resolved'
        AND (location.item->>'included_in_region_cell')::boolean
        AND (
          (
            location.item->>'region_id' = cell.item->>'region_id'
            AND location.item->>'tree_version' = cell.item->>'tree_version'
          )
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(requested_probe->'version_mappings')
              AS mapping(item)
            WHERE mapping.item->>'from_region_id'
                = location.item->>'region_id'
              AND mapping.item->>'from_tree_version'
                = location.item->>'tree_version'
              AND mapping.item->>'to_region_id' = cell.item->>'region_id'
              AND mapping.item->>'to_tree_version'
                = cell.item->>'tree_version'
          )
        )
    )
  ) THEN
    reason_codes = array_append(reason_codes, 'current_mapping_missing');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'location_states')
      AS location(item)
    WHERE item->>'state' = 'pending_resolution'
      AND (item->>'included_in_region_cell')::boolean
  ) THEN
    reason_codes = array_append(
      reason_codes, 'pending_resolution_not_reportable'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'location_states')
      AS location(item)
    WHERE item->>'state' = 'not_applicable'
      AND (item->>'included_in_region_cell')::boolean
  ) THEN
    reason_codes = array_append(reason_codes, 'not_applicable_separate');
  END IF;

  IF requested_probe->>'view_mode' NOT IN ('original', 'current') OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    WHERE item->>'view_mode' <> requested_probe->>'view_mode'
  ) THEN
    reason_codes = array_append(reason_codes, 'mixed_view');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    CROSS JOIN LATERAL jsonb_array_elements(report.item->'cells')
      AS cell(item)
    WHERE report.item->>'tree_version' <> requested_probe->>'tree_version'
      OR cell.item->>'tree_version' <> report.item->>'tree_version'
  ) THEN
    reason_codes = array_append(reason_codes, 'mixed_tree_version');
  END IF;

  IF requested_probe->>'region_granularity'
      NOT IN ('smallest_region', 'coordinates')
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
      WHERE item->>'region_granularity'
        NOT IN ('smallest_region', 'coordinates')
    )
  THEN
    reason_codes = array_append(reason_codes, 'unknown_granularity');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    WHERE item->>'scope_kind' NOT IN ('fixed_nodes', 'coordinates')
  ) THEN
    reason_codes = array_append(reason_codes, 'free_region_scope');
  END IF;

  IF requested_probe->>'region_granularity' = 'coordinates' OR EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'reports') AS report(item)
    WHERE item->>'region_granularity' = 'coordinates'
      OR item->>'scope_kind' = 'coordinates'
  ) THEN
    reason_codes = array_append(reason_codes, 'coordinate_dimension');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_probe->'location_states')
      AS location(item)
    WHERE item->>'state' = 'not_applicable'
      AND (
        jsonb_typeof(item->'region_id') <> 'null'
        OR jsonb_typeof(item->'tree_version') <> 'null'
      )
  ) THEN
    reason_codes = array_append(reason_codes, 'fake_not_applicable');
  END IF;

  RETURN jsonb_build_object(
    'probe_id', requested_probe->'probe_id',
    'query_fingerprint', requested_probe->'query_fingerprint',
    'result_status', CASE
      WHEN cardinality(reason_codes) = 0 THEN 'approved'
      ELSE 'blocked'
    END,
    'reason_codes', to_jsonb(reason_codes)
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.assess_management_region_privacy_v1(jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_private.assess_management_region_privacy_v1(jsonb)
IS 'Fixture-first fixed region disclosure-risk probe; registers no report, grants no runtime access, and returns no coordinates, contributors, or hidden values.';
