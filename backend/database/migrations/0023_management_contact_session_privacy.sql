-- 0023_management_contact_session_privacy.sql
--
-- 固定双期间渠道报表的隐私政策只处理已经按“期间 × 渠道 × 推广者”聚合的
-- 可信贡献。函数不查询业务表、不做成员授权，也不授予 runtime 执行权限。
-- 后续生产报表必须先完成成员授权和项目报告时区解析，才能在服务端调用它。

CREATE SCHEMA app_private;
REVOKE ALL PRIVILEGES ON SCHEMA app_private
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_management_contact_session_grid_v1(
  requested_contributions jsonb
)
RETURNS TABLE (
  period_key text,
  category_key text,
  cell_order integer,
  value_count bigint,
  privacy_status text
)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
BEGIN
  IF requested_contributions IS NULL
    OR jsonb_typeof(requested_contributions) <> 'array'
    OR EXISTS (
      SELECT 1
      FROM jsonb_array_elements(requested_contributions) AS element(item)
      WHERE jsonb_typeof(item) <> 'object'
        OR NOT item ?& ARRAY[
          'period_key',
          'channel',
          'contributor_key',
          'unit_count'
        ]
        OR item - ARRAY[
          'period_key',
          'channel',
          'contributor_key',
          'unit_count'
        ] <> '{}'::jsonb
        OR jsonb_typeof(item->'period_key') <> 'string'
        OR item->>'period_key' NOT IN ('previous', 'current')
        OR jsonb_typeof(item->'channel') <> 'string'
        OR item->>'channel' NOT IN (
          'face_to_face',
          'voice_call',
          'video_call',
          'instant_text',
          'asynchronous_message',
          'mixed',
          'other_direct'
        )
        OR jsonb_typeof(item->'contributor_key') <> 'string'
        OR length(btrim(item->>'contributor_key')) NOT BETWEEN 1 AND 120
        OR jsonb_typeof(item->'unit_count') <> 'number'
        OR item->>'unit_count' !~ '^[1-9][0-9]*$'
        OR (item->>'unit_count')::numeric > 2147483647
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management contact session contributions';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(requested_contributions) AS element(item)
    GROUP BY
      item->>'period_key',
      item->>'channel',
      btrim(item->>'contributor_key')
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'duplicate management contact session contribution';
  END IF;

  RETURN QUERY
  WITH input_rows AS (
    SELECT
      item->>'period_key' AS input_period_key,
      item->>'channel' AS input_channel,
      btrim(item->>'contributor_key') AS input_contributor_key,
      (item->>'unit_count')::bigint AS input_unit_count
    FROM jsonb_array_elements(requested_contributions) AS element(item)
  ),
  periods(input_period_key, period_order) AS (
    VALUES ('previous'::text, 0), ('current'::text, 1)
  ),
  categories(input_channel, category_order) AS (
    VALUES
      ('face_to_face'::text, 1),
      ('voice_call'::text, 2),
      ('video_call'::text, 3),
      ('instant_text'::text, 4),
      ('asynchronous_message'::text, 5),
      ('mixed'::text, 6),
      ('other_direct'::text, 7)
  ),
  complete_leaf_grid AS (
    SELECT
      periods.input_period_key,
      periods.period_order,
      categories.input_channel,
      categories.category_order
    FROM periods
    CROSS JOIN categories
  ),
  leaf_statistics AS (
    SELECT
      grid.input_period_key,
      grid.period_order,
      grid.input_channel,
      grid.category_order,
      coalesce(sum(input_rows.input_unit_count), 0)::bigint AS unit_count,
      count(input_rows.input_contributor_key)::integer AS contributor_count,
      coalesce(max(input_rows.input_unit_count), 0)::bigint AS max_contribution
    FROM complete_leaf_grid AS grid
    LEFT JOIN input_rows
      ON input_rows.input_period_key = grid.input_period_key
     AND input_rows.input_channel = grid.input_channel
    GROUP BY
      grid.input_period_key,
      grid.period_order,
      grid.input_channel,
      grid.category_order
  ),
  protected_leaves AS (
    SELECT
      leaf_statistics.*,
      unit_count >= 10
        AND contributor_count >= 3
        AND max_contribution::numeric * 2 <= unit_count::numeric
        AS can_display
    FROM leaf_statistics
  ),
  total_by_contributor AS (
    SELECT
      input_period_key,
      input_contributor_key,
      sum(input_unit_count)::bigint AS unit_count
    FROM input_rows
    GROUP BY input_period_key, input_contributor_key
  ),
  total_statistics AS (
    SELECT
      periods.input_period_key,
      periods.period_order,
      coalesce(sum(total_by_contributor.unit_count), 0)::bigint AS unit_count,
      count(total_by_contributor.input_contributor_key)::integer
        AS contributor_count,
      coalesce(max(total_by_contributor.unit_count), 0)::bigint
        AS max_contribution
    FROM periods
    LEFT JOIN total_by_contributor
      ON total_by_contributor.input_period_key = periods.input_period_key
    GROUP BY periods.input_period_key, periods.period_order
  ),
  protected_totals AS (
    SELECT
      total_statistics.*,
      total_statistics.unit_count >= 10
        AND total_statistics.contributor_count >= 3
        AND total_statistics.max_contribution::numeric * 2
          <= total_statistics.unit_count::numeric
        AND NOT EXISTS (
          SELECT 1
          FROM protected_leaves
          WHERE protected_leaves.input_period_key =
              total_statistics.input_period_key
            AND NOT protected_leaves.can_display
        ) AS can_display
    FROM total_statistics
  ),
  protected_grid AS (
    SELECT
      protected_totals.input_period_key,
      protected_totals.period_order,
      'all'::text AS output_category_key,
      0 AS category_order,
      protected_totals.unit_count,
      protected_totals.can_display
    FROM protected_totals
    UNION ALL
    SELECT
      protected_leaves.input_period_key,
      protected_leaves.period_order,
      protected_leaves.input_channel,
      protected_leaves.category_order,
      protected_leaves.unit_count,
      protected_leaves.can_display
    FROM protected_leaves
  )
  SELECT
    protected_grid.input_period_key,
    protected_grid.output_category_key,
    protected_grid.period_order * 8 + protected_grid.category_order,
    CASE
      WHEN protected_grid.can_display THEN protected_grid.unit_count
      ELSE NULL
    END,
    CASE
      WHEN protected_grid.can_display THEN 'displayed'
      ELSE 'suppressed'
    END
  FROM protected_grid
  ORDER BY protected_grid.period_order, protected_grid.category_order;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_management_contact_session_grid_v1(jsonb)
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_private.protect_management_contact_session_grid_v1(jsonb)
IS 'Private fixture-first k=10 and contributor policy for the fixed v1 contact-session channel grid; performs no authorization.';
