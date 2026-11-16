\set ON_ERROR_STOP on
\set fixture_0164_definitions_only true
\ir 0164_management_report_frozen_periods.sql
\unset fixture_0164_definitions_only

CREATE FUNCTION pg_temp.fixture_0165_project(c jsonb,variant_group text) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE project_value uuid:=overlay(c->>'project' placing variant_group from 20 for 4)::uuid; membership_value uuid; project_membership_value uuid:=gen_random_uuid();
BEGIN
  IF project_value=(c->>'project')::uuid THEN RETURN c; END IF;
  SELECT organization_membership_id INTO STRICT membership_value FROM app_data.organization_memberships
    WHERE organization_workspace_id=(c->>'workspace')::uuid AND app_user_id=(c->>'actor')::uuid;
  INSERT INTO app_data.projects(project_id,workspace_id,display_name) VALUES(project_value,(c->>'workspace')::uuid,'0165 canonical UUID project');
  INSERT INTO app_data.questionnaire_versions(questionnaire_version_id,project_id,version_number,status,is_current)
    VALUES(gen_random_uuid(),project_value,1,'published',true);
  INSERT INTO app_data.project_memberships(project_membership_id,organization_membership_id,project_id,active_from_utc)
    VALUES(project_membership_value,membership_value,project_value,clock_timestamp());
  INSERT INTO app_data.management_report_capability_grants(capability_grant_id,project_membership_id,capability_id,active_from_utc)
    VALUES(gen_random_uuid(),project_membership_value,'release_management_reports',clock_timestamp()),
      (gen_random_uuid(),project_membership_value,'view_anonymous_analytics',clock_timestamp());
  PERFORM app_private.configure_project_reporting_time_zone_v1(gen_random_uuid(),(c->>'actor')::uuid,project_value,0,c->>'zone',clock_timestamp());
  PERFORM app_private.configure_management_follow_up_consent_opt_in_v1((c->>'actor')::uuid,project_value,'follow_up_consent_ratio@1',gen_random_uuid(),0,true);
  RETURN jsonb_set(c,'{project}',to_jsonb(project_value));
END
$function$;

CREATE FUNCTION pg_temp.fixture_0165_publish(c jsonb) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE document jsonb; receipt jsonb; request_value uuid:=gen_random_uuid(); snapshot_value uuid;
BEGIN
  document:=app_private.execute_management_follow_up_consent_ratio_report_v1((c->>'actor')::uuid,(c->>'project')::uuid,c->>'zone',clock_timestamp());
  IF document->>'status' IS DISTINCT FROM 'completed' THEN RAISE EXCEPTION '0165 normal consent producer failed: %',document; END IF;
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(document);
  receipt:=app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(request_value,(c->>'actor')::uuid,(c->>'project')::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',1);
  IF receipt->>'result_status' IS DISTINCT FROM 'approved_baseline' THEN RAISE EXCEPTION '0165 valid canonical UUID did not publish: %',receipt; END IF;
  snapshot_value:=(receipt->>'released_snapshot_id')::uuid;
  SELECT protected_report INTO STRICT document FROM app_private.management_report_snapshots WHERE snapshot_id=snapshot_value;
  RETURN jsonb_build_object('family','consent','request',request_value,'snapshot',snapshot_value,'receipt',receipt,'report',document);
END
$function$;

\if :{?fixture_0165_definitions_only}
\else
BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $canonical_projects$
DECLARE original_context jsonb; c jsonb; report jsonb; variant_group text; invalid_project text; before_validation jsonb; actual_state text;
BEGIN
  original_context:=pg_temp.fixture_0164_seed('0165-canonical-projects');
  FOREACH variant_group IN ARRAY ARRAY['8000','8abc','9def','a123','bfed'] LOOP
    c:=pg_temp.fixture_0165_project(original_context,variant_group);
    RAISE NOTICE '0165 normal canonical project group=% project=%',variant_group,c->>'project';
    report:=pg_temp.fixture_0165_publish(c);
    PERFORM pg_temp.fixture_0164_read_replay(c,jsonb_build_array(report));
    before_validation:=pg_temp.fixture_database_state();
    FOREACH invalid_project IN ARRAY ARRAY[overlay(c->>'project' placing '0' from 15 for 1),
      overlay(c->>'project' placing 'c' from 20 for 1),replace(c->>'project','-',''),
      upper(overlay(c->>'project' placing 'abcd' from 1 for 4))] LOOP
      actual_state:=NULL;
      BEGIN PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
        jsonb_set(report->'report','{project_id}',to_jsonb(invalid_project)));
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
      IF actual_state IS DISTINCT FROM '22023' THEN RAISE EXCEPTION '0165 invalid UUID version, variant, or format was accepted: %, %',invalid_project,actual_state; END IF;
    END LOOP;
    IF pg_temp.fixture_database_state() IS DISTINCT FROM before_validation THEN RAISE EXCEPTION '0165 invalid UUID validation changed report facts'; END IF;
  END LOOP;
END
$canonical_projects$;
ROLLBACK;
SELECT 'consent canonical hexadecimal UUID projects, strict invalid inputs, and exact read/replay: passed' AS result;
\endif
