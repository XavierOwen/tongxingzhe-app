-- 0042_personal_interest_level_ratios.sql
--
-- 为个人单次兴趣提供五档、可复算的比例合同。函数只返回聚合后的
-- `(interest_level, numerator, denominator)` 行，不暴露接触明细或用户身份。
-- 当前核心字段由 contacts.interest_level 的 NOT NULL 与 0..4 CHECK 约束，
-- 因而四种缺失计数和比例定义排除数都由 schema 证明为零；它们仍作为
-- 显式列返回，避免调用层把“没有缺失”误解成“没有统计边界”。

CREATE FUNCTION app_data.read_personal_interest_level_ratios(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS TABLE (
  interest_level integer,
  numerator bigint,
  denominator bigint,
  unknown_count bigint,
  refused_count bigint,
  not_applicable_count bigint,
  unanswered_count bigint,
  excluded_count bigint,
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
      MESSAGE = 'invalid personal interest level ratios request';
  END IF;

  -- The caller supplies a trusted identity from the Backend, but the database
  -- still reauthorizes the complete personal scope at the SQL boundary.
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
      MESSAGE = 'personal interest level ratios scope forbidden';
  END IF;

  RETURN QUERY
  WITH scoped_contacts AS (
    SELECT contact_row.interest_level
    FROM app_data.contacts AS contact_row
    WHERE contact_row.app_user_id = trusted_app_user_id
      AND contact_row.workspace_id = trusted_workspace_id
      AND contact_row.project_id = trusted_project_id
      -- timestamptz values are compared as instants; this is the UTC
      -- half-open interval [from_utc, until_utc).
      AND contact_row.occurred_at_utc >= from_utc
      AND contact_row.occurred_at_utc < until_utc
      AND contact_row.lifecycle_status = 'active'
  ),
  aggregate AS (
    SELECT COUNT(*)::bigint AS denominator
    FROM scoped_contacts
  ),
  levels AS (
    SELECT generate_series(0, 4)::integer AS interest_level
  ),
  ratio_rows AS (
    SELECT
      levels.interest_level,
      COUNT(scoped_contacts.interest_level) FILTER (
        WHERE scoped_contacts.interest_level = levels.interest_level
      )::bigint AS numerator,
      aggregate.denominator
    FROM levels
    CROSS JOIN aggregate
    LEFT JOIN scoped_contacts
      ON scoped_contacts.interest_level = levels.interest_level
    GROUP BY levels.interest_level, aggregate.denominator
  )
  SELECT
    ratio_rows.interest_level,
    ratio_rows.numerator,
    ratio_rows.denominator,
    0::bigint AS unknown_count,
    0::bigint AS refused_count,
    0::bigint AS not_applicable_count,
    0::bigint AS unanswered_count,
    0::bigint AS excluded_count,
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
  ORDER BY ratio_rows.interest_level;
END
$function$;

COMMENT ON FUNCTION app_data.read_personal_interest_level_ratios(
  uuid, uuid, uuid, timestamptz, timestamptz
) IS
  'Backend-only personal five-level interest ratios over a UTC half-open interval; percentages are integer basis points rounded half-up, and missing/excluded fields are schema-proven zero for the current core interest fact.';

REVOKE ALL
  ON FUNCTION app_data.read_personal_interest_level_ratios(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_interest_level_ratios(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;
