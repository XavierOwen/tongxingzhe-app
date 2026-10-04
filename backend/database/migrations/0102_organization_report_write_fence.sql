-- Slice 7CW serializes final report/config writes against organization
-- deletion by taking a KEY SHARE lock on the owning workspace row.

CREATE FUNCTION app_private.require_active_organization_report_write_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  workspace_kind text;
  workspace_deleted_at timestamptz;
BEGIN
  SELECT workspace.workspace_kind, workspace.deleted_at
  INTO workspace_kind, workspace_deleted_at
  FROM app_data.projects AS project
  JOIN app_data.workspaces AS workspace
    ON workspace.workspace_id = project.workspace_id
  WHERE project.project_id = NEW.project_id
  FOR KEY SHARE OF workspace;

  IF NOT FOUND
    OR workspace_kind IS DISTINCT FROM 'organization'
    OR workspace_deleted_at IS NOT NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization report write unavailable';
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.require_active_organization_report_write_v1()
  FROM PUBLIC, tongxingzhe_runtime;

DO $install_triggers$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'management_report_snapshots',
    'management_report_release_attempts',
    'management_report_release_v2_attempts',
    'management_current_city_report_release_attempts',
    'management_interest_report_release_attempts',
    'management_original_region_report_release_attempts',
    'management_follow_up_consent_report_release_attempts',
    'management_report_snapshot_export_events',
    'management_report_snapshot_replacements',
    'management_original_region_report_snapshot_replacements',
    'management_current_city_report_snapshot_replacements',
    'management_interest_report_snapshot_replacements',
    'management_follow_up_consent_ratio_report_snapshot_replacements',
    'management_follow_up_consent_opt_in_versions'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER a_org_report_write_fence BEFORE INSERT ON app_private.%I '
        'FOR EACH ROW EXECUTE FUNCTION '
        'app_private.require_active_organization_report_write_v1()',
      table_name
    );
  END LOOP;
END
$install_triggers$;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER FUNCTION app_private.require_active_organization_report_write_v1() OWNER TO %I',
    trusted_owner
  );
END
$owner$;
