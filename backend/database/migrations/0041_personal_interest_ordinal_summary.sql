-- 0041_personal_interest_ordinal_summary.sql
--
-- 为个人单次兴趣提供一个窄的有序汇总入口。统计单位仍是当前有效的
-- 接触场次；runtime 只得到五档数量、总场次和下中位等级，不能读取接触明细。

CREATE FUNCTION app_data.read_personal_interest_ordinal_summary(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS TABLE (
  contact_session_count bigint,
  interest_0_count bigint,
  interest_1_count bigint,
  interest_2_count bigint,
  interest_3_count bigint,
  interest_4_count bigint,
  median_level integer
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
      MESSAGE = 'invalid personal interest ordinal summary request';
  END IF;

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
      MESSAGE = 'personal interest ordinal summary scope forbidden';
  END IF;

  RETURN QUERY
  WITH counts AS (
    SELECT
      COUNT(*)::bigint AS contact_session_count,
      COUNT(*) FILTER (WHERE contact_row.interest_level = 0)::bigint
        AS interest_0_count,
      COUNT(*) FILTER (WHERE contact_row.interest_level = 1)::bigint
        AS interest_1_count,
      COUNT(*) FILTER (WHERE contact_row.interest_level = 2)::bigint
        AS interest_2_count,
      COUNT(*) FILTER (WHERE contact_row.interest_level = 3)::bigint
        AS interest_3_count,
      COUNT(*) FILTER (WHERE contact_row.interest_level = 4)::bigint
        AS interest_4_count
    FROM app_data.contacts AS contact_row
    WHERE contact_row.app_user_id = trusted_app_user_id
      AND contact_row.workspace_id = trusted_workspace_id
      AND contact_row.project_id = trusted_project_id
      AND contact_row.occurred_at_utc >= from_utc
      AND contact_row.occurred_at_utc < until_utc
      AND contact_row.lifecycle_status = 'active'
  ),
  distribution AS (
    SELECT
      level_row.ordinal_level,
      CASE level_row.ordinal_level
        WHEN 0 THEN counts.interest_0_count
        WHEN 1 THEN counts.interest_1_count
        WHEN 2 THEN counts.interest_2_count
        WHEN 3 THEN counts.interest_3_count
        WHEN 4 THEN counts.interest_4_count
      END AS level_count
    FROM counts
    CROSS JOIN generate_series(0, 4) AS level_row(ordinal_level)
  ),
  cumulative AS (
    SELECT
      distribution.ordinal_level,
      SUM(distribution.level_count) OVER (
        ORDER BY distribution.ordinal_level
      )::bigint AS cumulative_count
    FROM distribution
  )
  SELECT
    counts.contact_session_count,
    counts.interest_0_count,
    counts.interest_1_count,
    counts.interest_2_count,
    counts.interest_3_count,
    counts.interest_4_count,
    CASE
      WHEN counts.contact_session_count = 0 THEN NULL::integer
      ELSE (
        SELECT cumulative.ordinal_level::integer
        FROM cumulative
        WHERE cumulative.cumulative_count >= (
          (counts.contact_session_count + 1) / 2
        )
        ORDER BY cumulative.ordinal_level
        LIMIT 1
      )
    END AS median_level
  FROM counts;
END
$function$;

-- median_level is the lower median（下中位等级）：in ascending 0..4 order,
-- select the first level whose cumulative count reaches floor((total + 1) / 2).
-- An empty interval has no median and therefore returns NULL rather than level 0.
COMMENT ON FUNCTION app_data.read_personal_interest_ordinal_summary(
  uuid, uuid, uuid, timestamptz, timestamptz
) IS
  'Backend-only personal interest ordinal counts over a UTC half-open interval; median_level is the lower median (cumulative first reaches floor((total + 1) / 2)) and is NULL for an empty interval.';

REVOKE ALL
  ON FUNCTION app_data.read_personal_interest_ordinal_summary(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_interest_ordinal_summary(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;
