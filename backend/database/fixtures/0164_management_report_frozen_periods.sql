\set ON_ERROR_STOP on
\ir shared/database_state.sql

CREATE FUNCTION pg_temp.fixture_0164_families()
RETURNS TABLE(family text,report_id text,producer text,validator text,releaser text,reader text,audit_table text)
LANGUAGE sql AS $function$ VALUES
  ('interest','contact_sessions_by_interest_level_two_periods','execute_management_interest_distribution_report_v1',
    'validate_management_interest_report_document_v1','release_management_interest_report_snapshot_v1',
    'read_authorized_management_interest_report_snapshot_v1','management_interest_report_snapshot_access_events'),
  ('current_city','contact_sessions_by_current_city_two_periods','execute_management_current_city_contact_session_report_v1',
    'validate_management_current_city_report_document_v1','release_management_current_city_report_snapshot_v1',
    'read_authorized_management_current_city_report_snapshot_v1','management_current_city_report_snapshot_access_events'),
  ('consent','contact_target_follow_up_consent_ratio_two_periods','execute_management_follow_up_consent_ratio_report_v1',
    'validate_management_follow_up_consent_ratio_report_document_v1','release_management_follow_up_consent_ratio_report_snapshot_v1',
    'read_authorized_management_follow_up_consent_report_snapshot_v1','management_follow_up_consent_report_snapshot_access_events'),
  ('original_region','contact_sessions_by_original_region_two_periods','execute_management_original_region_contact_session_report_v1',
    'validate_management_original_region_report_document_v1','release_management_original_region_report_snapshot_v1',
    'read_authorized_management_original_region_report_snapshot_v1','management_original_region_report_snapshot_access_events')
$function$;

CREATE FUNCTION pg_temp.fixture_0164_seed(label text) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE c record; workspace_value uuid:=gen_random_uuid(); project_value uuid:=gen_random_uuid(); membership_value uuid:=gen_random_uuid();
  project_membership_value uuid:=gen_random_uuid(); tree_value text:='fixture-0164-'||gen_random_uuid();
BEGIN
  -- The 8000 group keeps this fixture independent of the existing consent UUID-regex defect.
  project_value:=overlay(project_value::text placing '8000' from 20 for 4)::uuid;
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0164.example.test',label);
  -- Canonical fixtures build organization authorization rows directly; release and version times use the real database clock.
  INSERT INTO app_data.workspaces(workspace_id,workspace_kind,display_name) VALUES(workspace_value,'organization','0164 frozen periods');
  INSERT INTO app_data.projects(project_id,workspace_id,display_name) VALUES(project_value,workspace_value,'0164 empty report project');
  INSERT INTO app_data.questionnaire_versions(questionnaire_version_id,project_id,version_number,status,is_current)
    VALUES(gen_random_uuid(),project_value,1,'published',true);
  INSERT INTO app_data.organization_memberships(organization_membership_id,organization_workspace_id,app_user_id,active_from_utc)
    VALUES(membership_value,workspace_value,c.app_user_id,transaction_timestamp());
  INSERT INTO app_data.project_memberships(project_membership_id,organization_membership_id,project_id,active_from_utc)
    VALUES(project_membership_value,membership_value,project_value,clock_timestamp());
  INSERT INTO app_data.management_report_capability_grants(capability_grant_id,project_membership_id,capability_id,active_from_utc)
    VALUES(gen_random_uuid(),project_membership_value,'release_management_reports',clock_timestamp()),
      (gen_random_uuid(),project_membership_value,'view_anonymous_analytics',clock_timestamp());
  INSERT INTO app_data.organization_owner_assignments(organization_owner_assignment_id,organization_membership_id,active_from_utc)
    VALUES(gen_random_uuid(),membership_value,transaction_timestamp());
  PERFORM app_private.configure_project_reporting_time_zone_v1(gen_random_uuid(),c.app_user_id,project_value,0,'America/Havana',clock_timestamp());
  PERFORM app_private.configure_management_follow_up_consent_opt_in_v1(c.app_user_id,project_value,'follow_up_consent_ratio@1',gen_random_uuid(),0,true);
  INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current) VALUES(tree_value,'draft',false);
  INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind) VALUES
    (tree_value||'-country',tree_value,NULL,'0164 Country','country'),
    (tree_value||'-city',tree_value,tree_value||'-country','0164 City','city'),
    (tree_value||'-venue',tree_value,tree_value||'-city','0164 Venue','venue');
  INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
    VALUES(tree_value||'-boundary',tree_value||'-venue',tree_value,polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))');
  PERFORM app_private.publish_canonical_region_tree_v1(tree_value,true);
  RETURN jsonb_build_object('actor',c.app_user_id,'workspace',workspace_value,'project',project_value,'zone','America/Havana');
END
$function$;

CREATE FUNCTION pg_temp.fixture_0164_reject_changes(validator_name text,document jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE bad jsonb;
BEGIN
  FOR bad IN SELECT value FROM (VALUES
    (jsonb_set(document,'{periods,current_period,until_utc}',
      to_jsonb(to_char(((document#>>'{periods,current_period,until_utc}')::timestamptz+interval '1 second') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')))),
    (jsonb_set(document,'{query_fingerprint}',to_jsonb('not-the-report-fingerprint'::text)))
  ) AS changes(value) LOOP
    BEGIN
      EXECUTE format('SELECT app_private.%I($1)',validator_name) USING bad;
      RAISE EXCEPTION '0164 validator accepted changed frozen periods or metadata: %',validator_name;
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
END
$function$;

CREATE FUNCTION pg_temp.fixture_0164_publish(c jsonb) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE family record; request_value uuid; receipt jsonb; document jsonb; snapshot_value uuid; reports jsonb:='[]'; cutoff timestamptz;
BEGIN
  FOR family IN SELECT * FROM pg_temp.fixture_0164_families() LOOP
    cutoff:=clock_timestamp(); request_value:=gen_random_uuid();
    IF family.family='consent' THEN
      EXECUTE format('SELECT app_private.%I($1,$2,$3,$4)',family.producer)
        INTO document USING (c->>'actor')::uuid,(c->>'project')::uuid,c->>'zone',cutoff;
    ELSE
      EXECUTE format('SELECT app_private.%I($1,$2,$3)',family.producer)
        INTO document USING (c->>'project')::uuid,c->>'zone',cutoff;
    END IF;
    IF family.family<>'original_region' THEN
      -- No snapshot exists yet: this document must still pass the current resolver.
      EXECUTE format('SELECT app_private.%I($1)',family.validator) USING document;
    END IF;
    EXECUTE format('SELECT app_private.%I($1,$2,$3,$4,1)',family.releaser)
      INTO receipt USING request_value,(c->>'actor')::uuid,(c->>'project')::uuid,family.report_id;
    IF family.family='original_region' THEN
      IF receipt->>'result_status' IS DISTINCT FROM 'blocked' OR receipt->>'released_snapshot_id' IS NOT NULL
        OR NOT (receipt->'reason_codes' ? 'release_source_tree_unavailable') THEN
        RAISE EXCEPTION '0164 empty original-region source gate changed: %',receipt;
      END IF;
      RAISE NOTICE '0164 original-region empty release stays blocked: release_source_tree_unavailable';
      CONTINUE;
    END IF;
    IF receipt->>'result_status' IS DISTINCT FROM 'approved_baseline' THEN RAISE EXCEPTION '0164 normal empty release failed: %, %',family.family,receipt; END IF;
    snapshot_value:=(receipt->>'released_snapshot_id')::uuid;
    SELECT protected_report INTO STRICT document FROM app_private.management_report_snapshots WHERE snapshot_id=snapshot_value;
    EXECUTE format('SELECT app_private.%I($1)',family.validator) USING document;
    PERFORM pg_temp.fixture_0164_reject_changes(family.validator,document);
    reports:=reports||jsonb_build_array(jsonb_build_object('family',family.family,'request',request_value,'snapshot',snapshot_value,'receipt',receipt,'report',document));
  END LOOP;
  IF EXISTS(SELECT 1 FROM app_data.contacts WHERE project_id=(c->>'project')::uuid) THEN RAISE EXCEPTION '0164 empty publication created contact facts'; END IF;
  RETURN reports;
END
$function$;

CREATE FUNCTION pg_temp.fixture_0164_read_replay(c jsonb,reports jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE family record; saved_report jsonb; detail jsonb; replayed jsonb; attempt integer; before_state jsonb:=pg_temp.fixture_database_state();
  after_state jsonb; audit_key text; expected_count integer; audit_keys text[]:=ARRAY[
    'app_private.management_interest_report_snapshot_access_events','app_private.management_current_city_report_snapshot_access_events',
    'app_private.management_follow_up_consent_report_snapshot_access_events','app_private.management_original_region_report_snapshot_access_events'];
BEGIN
  FOR saved_report IN SELECT value FROM jsonb_array_elements(reports) LOOP
    SELECT * INTO STRICT family FROM pg_temp.fixture_0164_families() WHERE fixture_0164_families.family=saved_report->>'family';
    PERFORM pg_temp.fixture_0164_reject_changes(family.validator,saved_report->'report');
    FOR attempt IN 1..2 LOOP
      EXECUTE format('SELECT app_private.%I($1,$2,$3)',family.reader)
        INTO detail USING (c->>'actor')::uuid,(c->>'project')::uuid,(saved_report->>'snapshot')::uuid;
      IF detail->>'result_status' IS DISTINCT FROM 'completed' OR detail->'protected_report' IS DISTINCT FROM saved_report->'report' THEN
        RAISE EXCEPTION '0164 frozen detail changed status or report: %, %',family.family,detail;
      END IF;
      EXECUTE format('SELECT app_private.%I($1,$2,$3,$4,1)',family.releaser)
        INTO replayed USING (saved_report->>'request')::uuid,(c->>'actor')::uuid,(c->>'project')::uuid,family.report_id;
      IF replayed IS DISTINCT FROM saved_report->'receipt' THEN RAISE EXCEPTION '0164 release replay changed its original receipt: %',family.family; END IF;
    END LOOP;
  END LOOP;
  after_state:=pg_temp.fixture_database_state();
  IF before_state-audit_keys IS DISTINCT FROM after_state-audit_keys THEN RAISE EXCEPTION '0164 detail/replay changed frozen reports, requests, versions, or release facts'; END IF;
  FOR family IN SELECT * FROM pg_temp.fixture_0164_families() LOOP
    audit_key:='app_private.'||family.audit_table;
    SELECT count(*)*2 INTO expected_count FROM jsonb_array_elements(reports) report WHERE report->>'family'=family.family;
    IF NOT (before_state->audit_key)<@(after_state->audit_key)
      OR jsonb_array_length(after_state->audit_key)-jsonb_array_length(before_state->audit_key)<>expected_count
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(after_state->audit_key) event
        WHERE NOT (before_state->audit_key)@>jsonb_build_array(event) AND (
          event->>'requested_by_app_user_id' IS DISTINCT FROM c->>'actor' OR event->>'project_id' IS DISTINCT FROM c->>'project'
          OR event->>'result_status' IS DISTINCT FROM 'completed'
          OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(reports) report WHERE report->>'family'=family.family
            AND event->>'requested_snapshot_id'=report->>'snapshot' AND event->>'resolved_snapshot_id'=report->>'snapshot'))) THEN
      RAISE EXCEPTION '0164 necessary completed-read audit delta differs: %',family.family;
    END IF;
  END LOOP;
END
$function$;

\if :{?fixture_0164_definitions_only}
\else
BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $fresh$
DECLARE c jsonb; reports jsonb;
BEGIN
  c:=pg_temp.fixture_0164_seed('fresh');
  reports:=pg_temp.fixture_0164_publish(c);
  PERFORM pg_temp.fixture_0164_read_replay(c,reports);
END
$fresh$;
DO $resolver_fault$
DECLARE c jsonb; reports jsonb; unfrozen jsonb; original pg_proc%ROWTYPE; actual_message text;
  fault_message text:='0164 synthetic resolver reached only for an unfrozen document';
BEGIN
  c:=pg_temp.fixture_0164_seed('resolver-fault');
  reports:=pg_temp.fixture_0164_publish(c);
  unfrozen:=app_private.execute_management_interest_distribution_report_v1((c->>'project')::uuid,c->>'zone',clock_timestamp());
  IF EXISTS(SELECT 1 FROM app_private.management_report_snapshots WHERE protected_report=unfrozen) THEN
    RAISE EXCEPTION '0164 unfrozen control unexpectedly matched an existing snapshot';
  END IF;
  SELECT * INTO STRICT original FROM pg_proc WHERE oid='app_private.resolve_management_report_periods_v1(text,timestamptz)'::regprocedure;
  EXECUTE replace(pg_get_functiondef(original.oid),original.prosrc,
    format('BEGIN RAISE EXCEPTION USING ERRCODE=''22023'', MESSAGE=%L; END',fault_message));
  -- This synthetic fault isolates frozen-period reuse; the real cross-tzdata regression uses the original resolver.
  PERFORM pg_temp.fixture_0164_read_replay(c,reports);
  BEGIN
    PERFORM app_private.validate_management_interest_report_document_v1(unfrozen);
    RAISE EXCEPTION '0164 unfrozen document bypassed the current resolver';
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS actual_message=MESSAGE_TEXT;
    IF actual_message IS DISTINCT FROM fault_message THEN RAISE EXCEPTION '0164 unfrozen control failed before the resolver: %',actual_message; END IF;
  END;
END
$resolver_fault$;
ROLLBACK;
SELECT 'management frozen periods: normal empty reports, strict fallback, exact replay, and read audit delta passed' AS result;
\endif
