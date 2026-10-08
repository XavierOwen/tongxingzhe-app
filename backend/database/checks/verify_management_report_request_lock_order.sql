\set ON_ERROR_STOP on

DO $check$
DECLARE
  target record;
  function_row pg_catalog.pg_proc%ROWTYPE;
  function_body text;
  request_position integer;
  authorization_position integer;
  receipt_position integer;
  trusted_owner text;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0107_management_report_request_lock_order') <> 1 THEN
    RAISE EXCEPTION '0107 migration not recorded exactly once';
  END IF;
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  FOR target IN
    SELECT * FROM (VALUES
      ('app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)', 'resolve_management_report_authorization_v1', 'management-report-release-request:', trusted_owner, false, 'search_path=pg_catalog'),
      ('app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_current_city_release_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_current_city_snapshot_release_writer', true, 'search_path=pg_catalog, app_private, app_data'),
      ('app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_interest_release_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_interest_snapshot_release_writer', true, 'search_path=pg_catalog, app_private, app_data'),
      ('app_private.declare_management_report_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-snapshot-replacement-request:', 'tongxingzhe_management_report_snapshot_lifecycle_writer', true, 'search_path=pg_catalog, app_private'),
      ('app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_original_region_release_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_original_region_snapshot_release_writer', true, 'search_path=pg_catalog, app_private, app_data'),
      ('app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_report_snapshot_lifecycle_writer', true, 'search_path=pg_catalog, app_private'),
      ('app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)', 'resolve_management_report_authorization_v1', 'management-follow-up-consent-opt-in-request:', 'tongxingzhe_management_follow_up_consent_config_writer', true, 'search_path=pg_catalog, app_data'),
      ('app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_consent_ratio_report_release_auth_v1', 'management-report-release-request:', 'tongxingzhe_management_consent_ratio_snapshot_release_writer', true, 'search_path=pg_catalog, app_private, app_data'),
      ('app_private.declare_management_current_city_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_report_snapshot_lifecycle_writer', true, 'search_path=pg_catalog, app_private'),
      ('app_private.declare_management_interest_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_report_snapshot_lifecycle_writer', true, 'search_path=pg_catalog, app_private'),
      ('app_private.declare_management_follow_up_consent_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:', 'tongxingzhe_management_report_snapshot_lifecycle_writer', true, 'search_path=pg_catalog, app_private')
    ) AS writers(identity, resolver, request_namespace, owner_name, security_definer, search_path)
  LOOP
    SELECT * INTO STRICT function_row FROM pg_catalog.pg_proc
    WHERE oid = target.identity::regprocedure;
    IF pg_get_userbyid(function_row.proowner) IS DISTINCT FROM target.owner_name
      OR function_row.prosecdef IS DISTINCT FROM target.security_definer
      OR function_row.provolatile <> 'v'
      OR function_row.proconfig IS DISTINCT FROM ARRAY[target.search_path]::text[]
      OR pg_get_function_result(function_row.oid) IS DISTINCT FROM 'jsonb'
      OR has_function_privilege('tongxingzhe_runtime', function_row.oid, 'EXECUTE')
      OR EXISTS (
        SELECT 1 FROM pg_catalog.aclexplode(coalesce(function_row.proacl,
          pg_catalog.acldefault('f', function_row.proowner))) AS acl
        WHERE acl.grantee <> function_row.proowner
      )
    THEN
      RAISE EXCEPTION '0107 writer signature, owner, security or ACL drift: %', target.identity;
    END IF;

    function_body := regexp_replace(function_row.prosrc, '--[^\n]*', '', 'g');
    request_position := strpos(function_body, 'PERFORM pg_catalog.pg_advisory_xact_lock(');
    authorization_position := strpos(function_body, 'app_private.' || target.resolver || '(');
    receipt_position := strpos(function_body, 'INTO existing_');
    IF request_position = 0 OR authorization_position <= request_position
      OR strpos(function_body, target.request_namespace) <= request_position
      OR strpos(function_body, target.request_namespace) >= authorization_position
      OR regexp_count(function_body, 'app_private\.' || target.resolver || '\(') <> 2
      OR substring(function_body FROM request_position
        FOR authorization_position - request_position) !~ '0[[:space:]]*\)[[:space:]]*\);'
      OR (receipt_position > 0 AND receipt_position <= authorization_position)
      OR strpos(function_body, 'INSERT INTO') <= authorization_position
    THEN
      RAISE EXCEPTION '0107 request, post-lock authorization or receipt/write order drift: %', target.identity;
    END IF;
  END LOOP;
END
$check$;
