-- 0089_organization_directory.sql
--
-- 把 Backend 已验证的外部身份映射为当前组织目录。目录只依赖组织成员
-- 关系，不需要 owner、项目成员或 capability。

CREATE FUNCTION app_data.list_organizations_for_identity_v1(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (
  organization_workspace_id uuid,
  organization_name text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  directory_row record;
  directory_time timestamp with time zone := clock_timestamp();
BEGIN
  IF trusted_issuer IS NULL
    OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL
    OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization directory identity';
  END IF;

  -- btrim 只拒绝 ASCII 空格组成的输入；查找仍按 issuer/subject 原值精确匹配。
  -- LEFT JOIN 使 active 用户在没有组织时仍产生一个空行，便于和未映射身份区分。
  FOR directory_row IN
    SELECT
      workspace_row.workspace_id,
      workspace_row.display_name
    FROM app_data.external_identities AS identity_row
    JOIN app_data.app_users AS app_user
      ON app_user.app_user_id = identity_row.app_user_id
      AND app_user.status = 'active'
    LEFT JOIN app_data.organization_memberships AS membership_row
      ON membership_row.app_user_id = app_user.app_user_id
      AND tstzrange(
        membership_row.active_from_utc,
        membership_row.inactive_from_utc,
        '[)'
      ) @> directory_time
    LEFT JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id =
        membership_row.organization_workspace_id
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
    WHERE identity_row.issuer = trusted_issuer
      AND identity_row.subject = trusted_subject
    ORDER BY
      workspace_row.display_name COLLATE "C",
      workspace_row.workspace_id
  LOOP
    IF directory_row.workspace_id IS NOT NULL THEN
      organization_workspace_id := directory_row.workspace_id;
      organization_name := directory_row.display_name;
      RETURN NEXT;
    END IF;
  END LOOP;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization directory forbidden';
  END IF;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.list_organizations_for_identity_v1(text, text)
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.list_organizations_for_identity_v1(text, text)
  TO tongxingzhe_runtime;

-- 复用既有成员校验器的非 runtime owner，不引入新角色。
DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER FUNCTION app_data.list_organizations_for_identity_v1(text,text) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION
  app_data.list_organizations_for_identity_v1(text, text)
IS '按原值映射 Backend 已验证的 issuer/subject；NULL、ASCII 空值或原值超限时拒绝，返回读取时当前组织 workspace UUID 与未修剪名称，空目录返回零行；无写入，不授予 owner、项目或 capability 权限，runtime 仅可执行本函数。';
