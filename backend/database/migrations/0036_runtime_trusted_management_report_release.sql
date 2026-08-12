-- 0036_runtime_trusted_management_report_release.sql
--
-- 为生产 HTTP 入口提供唯一的窄 runtime bridge。Backend 先验证 bearer
-- 身份，只把可信 issuer/subject、请求幂等 UUID 和项目 UUID 传入；数据库
-- 在同一私有事务中重新确认 active identity，再固定报告合同并调用 6J。
-- bridge 不创建账号、个人上下文或授权记录，也不把 app_private 暴露给
-- runtime。发布结果沿用 6J 的 value-free JSON 文档。

CREATE FUNCTION app_data.release_management_report_snapshot_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_release_request_id uuid,
  requested_project_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  -- issuer/subject 必须来自已验证的外部身份；bridge 不接受客户端提供的
  -- app_user_id、报告、时区、数据截止时间或 capability。长度边界与既有
  -- runtime identity bridge 保持一致，避免异常输入进入私有函数。
  IF trusted_issuer IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR trusted_subject IS NULL
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
    OR requested_release_request_id IS NULL
    OR requested_project_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid runtime management report release request';
  END IF;

  -- 只映射已存在且仍 active 的身份。未知、deletion_pending 或 deleted
  -- 身份均 fail closed；这里不调用 bootstrap，也不写任何 app_data 行。
  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report release access forbidden';
  END IF;

  -- 报告 ID/version 是数据库合同的一部分，不由 HTTP body 或 query
  -- 提供。6J 负责授权、锁顺序、可信时区 revision、隐私阻断和幂等。
  RETURN app_private.release_management_report_snapshot_v2(
    requested_release_request_id,
    resolved_app_user_id,
    requested_project_id,
    'contact_sessions_by_channel_two_periods',
    1
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.release_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.release_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION app_data.release_management_report_snapshot_v1(
  text,
  text,
  uuid,
  uuid
)
IS 'Maps one verified existing active identity and publishes the fixed contact_sessions_by_channel_two_periods v1 report through the trusted v2 release contract without exposing app_private.';
