-- Slice 7CZ exposes the 0100 lifecycle writers through exact active identities.
-- The writers retain all lock-after authorization, state, and deadline checks.

CREATE FUNCTION app_data.request_organization_deletion_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_request_id uuid,
  requested_organization_workspace_id uuid
)
RETURNS TABLE (
  organization_deletion_contract_id text,
  organization_workspace_id uuid,
  deletion_request_id uuid,
  effective_at_utc timestamptz,
  purge_after_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization deletion request identity';
  END IF;

  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization deletion forbidden';
  END IF;

  RETURN QUERY
  SELECT result.organization_deletion_contract_id,
    result.organization_workspace_id, result.deletion_request_id,
    result.effective_at_utc, result.purge_after_utc
  FROM app_private.request_organization_deletion_v1(
    resolved_app_user_id, requested_request_id,
    requested_organization_workspace_id
  ) AS result;
END
$function$;

CREATE FUNCTION app_data.restore_organization_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_request_id uuid,
  requested_organization_workspace_id uuid,
  requested_deletion_request_id uuid
)
RETURNS TABLE (
  organization_deletion_restore_contract_id text,
  organization_workspace_id uuid,
  deletion_request_id uuid,
  restored_at_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization restoration identity';
  END IF;

  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization restoration forbidden';
  END IF;

  RETURN QUERY
  SELECT result.organization_deletion_restore_contract_id,
    result.organization_workspace_id, result.deletion_request_id,
    result.restored_at_utc
  FROM app_private.restore_organization_v1(
    resolved_app_user_id, requested_request_id,
    requested_organization_workspace_id, requested_deletion_request_id
  ) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.request_organization_deletion_for_identity_v1(text,text,uuid,uuid),
  app_data.restore_organization_for_identity_v1(text,text,uuid,uuid,uuid)
  FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.request_organization_deletion_for_identity_v1(text,text,uuid,uuid),
  app_data.restore_organization_for_identity_v1(text,text,uuid,uuid,uuid)
  TO tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER FUNCTION app_data.request_organization_deletion_for_identity_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.restore_organization_for_identity_v1(text,text,uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION app_data.request_organization_deletion_for_identity_v1(
  text,text,uuid,uuid
) IS 'Resolve an exact active external identity and delegate organization deletion to the lock-after private writer.';
COMMENT ON FUNCTION app_data.restore_organization_for_identity_v1(
  text,text,uuid,uuid,uuid
) IS 'Resolve an exact active external identity and delegate organization restoration to the lock-after private writer.';
