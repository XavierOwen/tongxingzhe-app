-- 0046_personal_target_response_level_ratios.sql
--
-- 为个人对象当次反应提供五档、可复算的比例入口。统计单位是当前有效
-- contact revision 中的接触对象关联；只有 response_level 非 NULL 的
-- 关联进入共同 answered 分母，NULL 关联作为 unanswered_count 单独保留。

CREATE FUNCTION app_data.read_personal_target_response_level_ratios(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS TABLE (
  response_level integer,
  numerator bigint,
  denominator bigint,
  unanswered_count bigint,
  percentage_basis_points integer
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
      MESSAGE = 'invalid personal target response level ratios request';
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
      MESSAGE = 'personal target response level ratios scope forbidden';
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
  aggregate AS (
    SELECT
      COUNT(*) FILTER (
        WHERE scoped.response_level IS NOT NULL
      )::bigint AS denominator,
      COUNT(*) FILTER (
        WHERE scoped.response_level IS NULL
      )::bigint AS unanswered_count
    FROM scoped_links AS scoped
  ),
  levels AS (
    SELECT generate_series(0, 4)::integer AS response_level
  ),
  ratio_rows AS (
    SELECT
      levels.response_level,
      COUNT(scoped.response_level) FILTER (
        WHERE scoped.response_level = levels.response_level
      )::bigint AS numerator,
      aggregate.denominator,
      aggregate.unanswered_count
    FROM levels
    CROSS JOIN aggregate
    LEFT JOIN scoped_links AS scoped
      ON scoped.response_level = levels.response_level
    GROUP BY levels.response_level,
             aggregate.denominator,
             aggregate.unanswered_count
  )
  SELECT
    ratio_rows.response_level,
    ratio_rows.numerator,
    ratio_rows.denominator,
    ratio_rows.unanswered_count,
    CASE
      WHEN ratio_rows.denominator = 0 THEN NULL::integer
      ELSE floor(
        (
          ratio_rows.numerator::numeric * 10000
          + ratio_rows.denominator::numeric / 2
        ) / ratio_rows.denominator::numeric
      )::integer
    END AS percentage_basis_points
  FROM ratio_rows
  ORDER BY ratio_rows.response_level;
END
$function$;

COMMENT ON FUNCTION app_data.read_personal_target_response_level_ratios(
  uuid, uuid, uuid, timestamptz, timestamptz
) IS
  'Backend-only personal target response level ratios over a UTC half-open interval; rows 0..4 are ordered by response_level, denominator counts only non-NULL responses from current active contact revisions, unanswered_count reports current links whose response_level is NULL, and percentage_basis_points uses integer half-up rounding with an empty denominator represented by NULL.';

REVOKE ALL
  ON FUNCTION app_data.read_personal_target_response_level_ratios(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_target_response_level_ratios(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;
