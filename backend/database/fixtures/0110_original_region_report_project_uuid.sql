-- A real original-region document validator must accept hexadecimal UUID tails.
-- Only project_id changes between cases; the published tree and report stay fixed.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current)
VALUES ('synthetic-0110-tree','draft',false);
INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind)
VALUES ('synthetic-0110-country','synthetic-0110-tree',NULL,'0110 country','country'),
  ('synthetic-0110-city','synthetic-0110-tree','synthetic-0110-country','0110 city','city');
INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
VALUES ('synthetic-0110-boundary','synthetic-0110-city','synthetic-0110-tree',
  polygon '((-88,41),(-87,41),(-87,42),(-88,42))');
SELECT app_private.publish_canonical_region_tree_v1('synthetic-0110-tree',false);

DO $uuid_regression$
DECLARE
  periods jsonb := app_private.resolve_management_report_periods_v1('UTC',clock_timestamp());
  report jsonb;
  project_uuid text;
BEGIN
  report := jsonb_build_object(
    'report_id','contact_sessions_by_original_region_two_periods','report_version',1,
    'metric_id','contact_sessions','metric_version',1,'dimension','original_region',
    'view_mode','original','region_granularity','city',
    'query_fingerprint','management-report:contact_sessions_by_original_region_two_periods:v1',
    'privacy_policy','management_original_region_contact_session_privacy_v1',
    'source_scope','backend_accepted_active_contacts_original_current_revision',
    'project_id','f2458ab8-c322-4771-9123-74bd3f9b34c0',
    'periods',periods,'data_cutoff_utc',periods->>'data_cutoff_utc',
    'source_change_sequence',0,'result_status','completed',
    'source_tree_context',jsonb_build_object(
      'source_tree_context_contract_id','management-original-region-source-tree:v1',
      'result_status','selected','reason_code','single_original_source_tree',
      'source_tree_version','synthetic-0110-tree',
      'source_content_fingerprint',(SELECT content_fingerprint
        FROM app_data.canonical_region_tree_releases WHERE tree_version='synthetic-0110-tree')),
    'cells','[{"period_key":"previous","city_id":"synthetic-0110-city","cell_order":0,"value_count":null,"privacy_status":"suppressed"},{"period_key":"current","city_id":"synthetic-0110-city","cell_order":1,"value_count":null,"privacy_status":"suppressed"}]'::jsonb);
  PERFORM app_private.validate_management_original_region_report_document_v1(report);
  FOREACH project_uuid IN ARRAY ARRAY[
    'f2458ab8-c322-4abc-9123-74bd3f9b34c0',
    'f2458ab8-c322-4771-91ce-74bd3f9b34c0',
    'f2458ab8-c322-4abc-8def-74bd3f9b34c0'
  ] LOOP
    PERFORM app_private.validate_management_original_region_report_document_v1(
      jsonb_set(report,'{project_id}',to_jsonb(project_uuid)));
  END LOOP;
  FOREACH project_uuid IN ARRAY ARRAY[
    'f2458ab8-c322-4abg-8def-74bd3f9b34c0',
    'f2458ab8-c322-0abc-8def-74bd3f9b34c0',
    'f2458ab8-c322-4abc-7def-74bd3f9b34c0',
    'F2458AB8-C322-4ABC-8DEF-74BD3F9B34C0',
    'f2458ab8c322-4abc-8def-74bd3f9b34c0',
    'f2458ab8-c322-4abc-8def-74bd3f9b34c'
  ] LOOP
    BEGIN
      PERFORM app_private.validate_management_original_region_report_document_v1(
        jsonb_set(report,'{project_id}',to_jsonb(project_uuid)));
      RAISE EXCEPTION '0110 invalid project UUID accepted: %',project_uuid;
    EXCEPTION WHEN invalid_parameter_value THEN
      IF SQLERRM <> 'invalid original region management report document' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM app_private.validate_management_original_region_report_document_v1(
      report || jsonb_build_object('unexpected_field',true));
    RAISE EXCEPTION '0110 extra report field accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'invalid original region management report document' THEN RAISE; END IF;
  END;
END
$uuid_regression$;
SELECT 'original-region project UUID regression: passed' AS result;
ROLLBACK;
