-- 0059_runtime_authorized_management_current_city_report_snapshot_read.sql
--
-- Slice 6AQ exposes one narrow runtime bridge for the private 6AP current-city
-- read. The bridge maps only an existing active external identity and never
-- exposes app_private to tongxingzhe_runtime.

CREATE FUNCTION app_data.read_authorized_management_current_city_report_snapshot_v1(
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
      MESSAGE = 'invalid runtime current-city snapshot request';
  END IF;

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
      MESSAGE = 'current-city snapshot access forbidden';
  END IF;

  RETURN app_private.read_authorized_management_current_city_report_snapshot_v1(
    resolved_app_user_id,
    requested_project_id,
    requested_snapshot_id
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.read_authorized_management_current_city_report_snapshot_v1(
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
    tongxingzhe_management_current_city_snapshot_release_writer;

GRANT EXECUTE ON FUNCTION
  app_data.read_authorized_management_current_city_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
  TO tongxingzhe_runtime;

COMMENT ON FUNCTION
  app_data.read_authorized_management_current_city_report_snapshot_v1(
    text,
    text,
    uuid,
    uuid
  )
IS 'Maps one existing active external identity and calls only the private current-city snapshot read bridge.';
