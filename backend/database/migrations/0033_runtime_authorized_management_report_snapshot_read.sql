-- 0033_runtime_authorized_management_report_snapshot_read.sql
--
-- 把 Backend 已验证的外部身份映射为既有内部用户，并通过唯一的 runtime
-- bridge 调用 6K。函数不建立账号或个人上下文，也不开放 app_private。

CREATE FUNCTION app_data.read_authorized_management_report_snapshot_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_snapshot_id uuid
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
  IF trusted_issuer IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR trusted_subject IS NULL
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
    OR requested_project_id IS NULL
    OR requested_snapshot_id IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid runtime management report snapshot request';
  END IF;

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
      MESSAGE = 'management report snapshot access forbidden';
  END IF;

  RETURN app_private.read_authorized_management_report_snapshot_v1(
    resolved_app_user_id,
    requested_project_id,
    requested_snapshot_id
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.read_authorized_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.read_authorized_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_data.read_authorized_management_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
IS 'Maps one Backend-verified existing identity and performs one authorized snapshot read without granting runtime access to app_private.';
