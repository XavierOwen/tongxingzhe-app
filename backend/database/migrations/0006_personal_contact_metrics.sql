-- 0006_personal_contact_metrics.sql
--
-- 用与 Drift 相同的口径读取一个用户、空间、项目和 UTC 半开区间内的当前
-- 有效接触。函数只返回聚合，不暴露单条接触或 app_user_id。

CREATE OR REPLACE FUNCTION app_data.read_personal_contact_summary(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS TABLE (
  contact_session_count bigint,
  reach_count bigint,
  interest_0_count bigint,
  interest_1_count bigint,
  interest_2_count bigint,
  interest_3_count bigint,
  interest_4_count bigint,
  channel_distribution jsonb,
  latest_occurred_at_utc timestamptz
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
      MESSAGE = 'invalid personal contact summary request';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    JOIN app_data.projects AS project_row
      ON project_row.workspace_id = workspace_row.workspace_id
    WHERE workspace_row.workspace_id = trusted_workspace_id
      AND workspace_row.personal_owner_app_user_id = trusted_app_user_id
      AND workspace_row.deleted_at IS NULL
      AND project_row.project_id = trusted_project_id
      AND project_row.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal contact summary scope forbidden';
  END IF;

  RETURN QUERY
  SELECT
    COUNT(*) AS contact_session_count,
    COALESCE(SUM(contact_row.reach_count), 0)::bigint AS reach_count,
    COUNT(*) FILTER (WHERE contact_row.interest_level = 0),
    COUNT(*) FILTER (WHERE contact_row.interest_level = 1),
    COUNT(*) FILTER (WHERE contact_row.interest_level = 2),
    COUNT(*) FILTER (WHERE contact_row.interest_level = 3),
    COUNT(*) FILTER (WHERE contact_row.interest_level = 4),
    jsonb_build_object(
      'face_to_face', COUNT(*) FILTER (
        WHERE contact_row.channel = 'face_to_face'
      ),
      'voice_call', COUNT(*) FILTER (
        WHERE contact_row.channel = 'voice_call'
      ),
      'video_call', COUNT(*) FILTER (
        WHERE contact_row.channel = 'video_call'
      ),
      'instant_text', COUNT(*) FILTER (
        WHERE contact_row.channel = 'instant_text'
      ),
      'asynchronous_message', COUNT(*) FILTER (
        WHERE contact_row.channel = 'asynchronous_message'
      ),
      'mixed', COUNT(*) FILTER (WHERE contact_row.channel = 'mixed'),
      'other_direct', COUNT(*) FILTER (
        WHERE contact_row.channel = 'other_direct'
      )
    ),
    MAX(contact_row.occurred_at_utc)
  FROM app_data.contacts AS contact_row
  WHERE contact_row.app_user_id = trusted_app_user_id
    AND contact_row.workspace_id = trusted_workspace_id
    AND contact_row.project_id = trusted_project_id
    AND contact_row.occurred_at_utc >= from_utc
    AND contact_row.occurred_at_utc < until_utc
    AND contact_row.lifecycle_status = 'active';
END
$function$;

REVOKE ALL
  ON FUNCTION app_data.read_personal_contact_summary(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION app_data.read_personal_contact_summary(
    uuid, uuid, uuid, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.read_personal_contact_summary(
  uuid, uuid, uuid, timestamptz, timestamptz
) IS
  'Backend-only personal contact metrics over a UTC half-open interval.';
