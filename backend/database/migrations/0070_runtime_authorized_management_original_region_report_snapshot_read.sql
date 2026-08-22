-- 0070_runtime_authorized_management_original_region_report_snapshot_read.sql
--
-- Slice 6BI exposes one narrow runtime bridge for the private 6BH
-- original-region snapshot read. Backend verifies the external token before
-- passing its issuer and subject. The bridge maps only an existing active
-- identity and never exposes app_private to tongxingzhe_runtime.

CREATE FUNCTION app_data.read_authorized_management_original_region_report_snapshot_v1(
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
      MESSAGE = 'invalid runtime original-region snapshot request';
  END IF;

  -- btrim above is only an input-length guard.  The stored identity must
  -- match issuer and subject byte-for-byte; whitespace cannot be normalized
  -- into a different identity.
  SELECT identity_row.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'original-region snapshot access forbidden';
  END IF;

  -- 0069 owns authorization, provenance validation, locking, audit and the
  -- completed/not_found/untrusted_provenance response contract.
  RETURN app_private.read_authorized_management_original_region_report_snapshot_v1(
    resolved_app_user_id,
    requested_project_id,
    requested_snapshot_id
  );
END
$function$;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.read_authorized_management_original_region_report_snapshot_v1(uuid,uuid,uuid)'::regprocedure;

  EXECUTE format(
    'ALTER FUNCTION app_data.read_authorized_management_original_region_report_snapshot_v1(text,text,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.read_authorized_management_original_region_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  FROM PUBLIC,
    tongxingzhe_runtime,
    tongxingzhe_region_publisher,
    tongxingzhe_region_mapping_writer,
    tongxingzhe_contact_provenance_writer,
    tongxingzhe_region_attribution_reader,
    tongxingzhe_management_region_report_reader,
    tongxingzhe_management_original_region_report_reader,
    tongxingzhe_management_interest_report_reader,
    tongxingzhe_management_current_city_snapshot_release_writer,
    tongxingzhe_management_interest_snapshot_release_writer,
    tongxingzhe_management_original_region_snapshot_release_writer,
    tongxingzhe_management_report_snapshot_lifecycle_writer;

GRANT EXECUTE ON FUNCTION
  app_data.read_authorized_management_original_region_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_data.read_authorized_management_original_region_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
IS 'Maps one Backend-verified exact external identity and performs the fixed 0069 authorized original-region snapshot read without exposing app_private.';
