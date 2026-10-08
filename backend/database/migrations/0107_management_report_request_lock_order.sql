-- Slice 7DI removes the unused authorization resolution before the request
-- lock in exactly eleven existing writers. Later revalidation remains intact.
-- Replacing catalog definitions preserves function identity, owner and ACL.
DO $request_before_authorization$
DECLARE
  target record;
  function_row pg_catalog.pg_proc%ROWTYPE;
  function_definition text;
  unused_resolution text;
  updated_definition text;
  authorization_pattern text;
BEGIN
  FOR target IN
    SELECT * FROM (VALUES
      ('app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)', 'resolve_management_report_authorization_v1', 'management-report-release-request:'),
      ('app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_current_city_release_authorization_v1', 'management-report-release-request:'),
      ('app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_interest_release_authorization_v1', 'management-report-release-request:'),
      ('app_private.declare_management_report_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-snapshot-replacement-request:'),
      ('app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_original_region_release_authorization_v1', 'management-report-release-request:'),
      ('app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:'),
      ('app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)', 'resolve_management_report_authorization_v1', 'management-follow-up-consent-opt-in-request:'),
      ('app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'resolve_management_consent_ratio_report_release_auth_v1', 'management-report-release-request:'),
      ('app_private.declare_management_current_city_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:'),
      ('app_private.declare_management_interest_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:'),
      ('app_private.declare_management_follow_up_consent_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'resolve_management_report_authorization_v1', 'management-report-release-request:')
    ) AS writers(identity, resolver, request_namespace)
  LOOP
    SELECT * INTO STRICT function_row FROM pg_catalog.pg_proc
    WHERE oid = target.identity::regprocedure;
    function_definition := pg_catalog.pg_get_functiondef(function_row.oid);
    authorization_pattern := '  authorization_evidence (:=|=)[[:space:]]+'
      || 'app_private\.' || target.resolver || '\([^;]+;';
    unused_resolution := substring(function_definition FROM
      '(' || authorization_pattern || ')');
    IF unused_resolution IS NULL
      OR regexp_count(function_definition, 'app_private\.' || target.resolver || '\(') <> 3
      OR strpos(function_definition, unused_resolution) >
        strpos(function_definition, 'PERFORM pg_catalog.pg_advisory_xact_lock(')
      OR strpos(function_definition, target.request_namespace) = 0
    THEN
      RAISE EXCEPTION '0107 expected unused pre-request resolution in %', target.identity;
    END IF;

    updated_definition := overlay(function_definition PLACING ''
      FROM strpos(function_definition, unused_resolution)
      FOR length(unused_resolution));
    -- Only the generated 0031 definition changes its contrary lock comment.
    updated_definition := replace(updated_definition,
      E'  -- Lock order is authorization, release request, project time zone, then\n'
        '  -- report lineage. The first resolution acquires the authorization locks;\n'
        '  -- they remain held until this release transaction finishes.',
      E'  -- Lock order is release request, authorization, project time zone, then\n'
        '  -- report lineage. Authorization remains before receipt reads and writes.');
    EXECUTE updated_definition;

    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS replaced
      WHERE replaced.oid = function_row.oid
        AND replaced.proowner = function_row.proowner
        AND replaced.proacl IS NOT DISTINCT FROM function_row.proacl
        AND replaced.prosecdef = function_row.prosecdef
        AND replaced.proconfig IS NOT DISTINCT FROM function_row.proconfig
    ) THEN
      RAISE EXCEPTION '0107 changed writer identity, owner, security or ACL: %', target.identity;
    END IF;
  END LOOP;
END
$request_before_authorization$;
