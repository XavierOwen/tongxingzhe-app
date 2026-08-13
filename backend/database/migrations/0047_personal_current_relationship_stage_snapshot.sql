-- 0047_personal_current_relationship_stage_snapshot.sql
--
-- 为个人分析提供当前关系阶段的 PII-free 窄读取。结果不是接触期间
-- 指标，也不是历史 as-of 重建；每次调用只在一个 PostgreSQL statement
-- snapshot 中判断当前对象×项目关系。

CREATE FUNCTION app_data.read_personal_current_relationship_stage_snapshot(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (snapshot jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF trusted_app_user_id IS NULL
    OR trusted_workspace_id IS NULL
    OR trusted_project_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal current relationship stage snapshot request';
  END IF;

  -- Backend supplies these UUIDs from the verified current session. PostgreSQL
  -- repeats the complete personal-workspace and active-project authorization so
  -- a caller with only EXECUTE on this bridge cannot forge its scope.
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal current relationship stage snapshot scope forbidden';
  END IF;

  RETURN QUERY
  WITH snapshot_clock AS (
    SELECT statement_timestamp() AS snapshot_as_of_utc
  ),
  scoped_relationships AS (
    SELECT
      relationship_row.promotion_target_id AS target_key,
      relationship_row.current_stage AS stage,
      relationship_row.current_revision AS revision,
      relationship_row.updated_at AS updated_at_utc
    FROM app_data.promotion_target_project_relationships AS relationship_row
    JOIN app_data.promotion_targets AS target_row
      ON target_row.promotion_target_id = relationship_row.promotion_target_id
     AND target_row.workspace_id = trusted_workspace_id
     AND target_row.status = 'active'
    JOIN app_data.promotion_target_assignments AS assignment_row
      ON assignment_row.promotion_target_id =
        relationship_row.promotion_target_id
     AND assignment_row.app_user_id = trusted_app_user_id
     AND assignment_row.ended_at IS NULL
    WHERE relationship_row.project_id = trusted_project_id
      AND relationship_row.current_lifecycle_status = 'active'
  ),
  scoped_totals AS (
    SELECT
      COUNT(scoped.target_key)::bigint AS total,
      COALESCE(
        MAX(scoped.updated_at_utc),
        snapshot_clock.snapshot_as_of_utc
      ) AS source_cutoff_utc
    FROM snapshot_clock
    LEFT JOIN scoped_relationships AS scoped ON true
    GROUP BY snapshot_clock.snapshot_as_of_utc
  )
  SELECT jsonb_build_object(
    'contract_id', 'current_relationship_stage_distribution@1',
    'statistical_unit', 'targetProjectRelationship',
    'project_key', trusted_project_id,
    'snapshot_as_of_utc', to_char(
      snapshot_clock.snapshot_as_of_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'source_cutoff_utc', to_char(
      scoped_totals.source_cutoff_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'authorized_at_utc', to_char(
      snapshot_clock.snapshot_as_of_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'coverage', jsonb_build_object(
      'total', scoped_totals.total,
      'pending', 0
    ),
    'relationships', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'target_key', scoped.target_key,
            'stage', scoped.stage,
            'revision', scoped.revision,
            'updated_at_utc', to_char(
              scoped.updated_at_utc AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            )
          )
          ORDER BY scoped.target_key
        )
        FROM scoped_relationships AS scoped
      ),
      '[]'::jsonb
    )
  )
  FROM snapshot_clock
  CROSS JOIN scoped_totals;
END
$function$;

COMMENT ON FUNCTION app_data.read_personal_current_relationship_stage_snapshot(
  uuid, uuid, uuid
) IS
  'Backend-only PII-free current relationship stage snapshot for the trusted personal project; active assigned targets and active project relationships only, with one UTC snapshot and source cutoff, no historical as-of input.';

REVOKE ALL
  ON FUNCTION app_data.read_personal_current_relationship_stage_snapshot(
    uuid, uuid, uuid
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_current_relationship_stage_snapshot(
    uuid, uuid, uuid
  )
  TO tongxingzhe_runtime;
