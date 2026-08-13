-- 0045_personal_target_response_ordinal_summary.sql
--
-- 为个人对象当次反应提供一个窄的有序汇总入口。统计单位是当前有效
-- contact revision 中的接触对象关联；只有 response_level 非 NULL 的
-- 关联进入五档总数和中位等级，NULL 关联作为 unanswered_count 单独保留。

CREATE FUNCTION app_data.read_personal_target_response_ordinal_summary(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS TABLE (
  target_response_total_count bigint,
  target_response_0_count bigint,
  target_response_1_count bigint,
  target_response_2_count bigint,
  target_response_3_count bigint,
  target_response_4_count bigint,
  median_level integer,
  unanswered_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF trusted_app_user_id IS NULL
    OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL
    OR from_utc IS NULL
    OR until_utc IS NULL
    OR from_utc >= until_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal target response ordinal summary request';
  END IF;

  -- The Backend supplies a trusted identity, but PostgreSQL still reauthorizes
  -- the complete personal workspace and active project at this boundary.
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.workspace_kind = 'personal'
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target response ordinal summary scope forbidden';
  END IF;

  RETURN QUERY
  WITH scoped_links AS (
    SELECT link_row.response_level
    FROM app_data.contacts AS contact_row
    JOIN app_data.contact_target_links AS link_row
      ON link_row.contact_id = contact_row.contact_id
     AND link_row.revision_number = contact_row.current_revision
    WHERE contact_row.app_user_id = trusted_app_user_id
      AND contact_row.workspace_id = trusted_workspace_id
      AND contact_row.project_id = trusted_project_id
      AND contact_row.occurred_at_utc >= from_utc
      AND contact_row.occurred_at_utc < until_utc
      AND contact_row.lifecycle_status = 'active'
  ),
  counts AS (
    SELECT
      COUNT(*) FILTER (
        WHERE scoped.response_level IS NOT NULL
      )::bigint AS target_response_total_count,
      COUNT(*) FILTER (
        WHERE scoped.response_level = 0
      )::bigint AS target_response_0_count,
      COUNT(*) FILTER (
        WHERE scoped.response_level = 1
      )::bigint AS target_response_1_count,
      COUNT(*) FILTER (
        WHERE scoped.response_level = 2
      )::bigint AS target_response_2_count,
      COUNT(*) FILTER (
        WHERE scoped.response_level = 3
      )::bigint AS target_response_3_count,
      COUNT(*) FILTER (
        WHERE scoped.response_level = 4
      )::bigint AS target_response_4_count,
      COUNT(*) FILTER (
        WHERE scoped.response_level IS NULL
      )::bigint AS unanswered_count
    FROM scoped_links AS scoped
  ),
  distribution AS (
    SELECT
      level_row.response_level,
      CASE level_row.response_level
        WHEN 0 THEN counts.target_response_0_count
        WHEN 1 THEN counts.target_response_1_count
        WHEN 2 THEN counts.target_response_2_count
        WHEN 3 THEN counts.target_response_3_count
        WHEN 4 THEN counts.target_response_4_count
      END AS level_count
    FROM counts
    CROSS JOIN generate_series(0, 4) AS level_row(response_level)
  ),
  cumulative AS (
    SELECT
      distribution.response_level,
      SUM(distribution.level_count) OVER (
        ORDER BY distribution.response_level
      )::bigint AS cumulative_count
    FROM distribution
  )
  SELECT
    counts.target_response_total_count,
    counts.target_response_0_count,
    counts.target_response_1_count,
    counts.target_response_2_count,
    counts.target_response_3_count,
    counts.target_response_4_count,
    CASE
      WHEN counts.target_response_total_count = 0 THEN NULL::integer
      ELSE (
        SELECT cumulative.response_level::integer
        FROM cumulative
        WHERE cumulative.cumulative_count >= (
          (counts.target_response_total_count + 1) / 2
        )
        ORDER BY cumulative.response_level
        LIMIT 1
      )
    END AS median_level,
    counts.unanswered_count
  FROM counts;
END
$function$;

-- median_level is the lower median（下中位等级）：in ascending 0..4 order,
-- select the first level whose cumulative count reaches floor((total + 1) / 2).
-- An empty answered set has no median and therefore returns NULL rather than
-- level 0. NULL responses never enter the five-level total or median.
COMMENT ON FUNCTION app_data.read_personal_target_response_ordinal_summary(
  uuid, uuid, uuid, timestamptz, timestamptz
) IS
  'Backend-only personal target response ordinal summary over a UTC half-open interval; five counts and target_response_total_count use current active contact revisions with non-NULL responses, median_level is the lower median and is NULL for an empty answered set, and unanswered_count reports current links whose response_level is NULL.';

REVOKE ALL
  ON FUNCTION app_data.read_personal_target_response_ordinal_summary(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_target_response_ordinal_summary(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;
