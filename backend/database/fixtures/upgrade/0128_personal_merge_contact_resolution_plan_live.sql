\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0129_upgrade_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://0128-upgrade-resolution.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0128-upgrade-resolution.example.test','owner') WHERE is_current;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.id,c.workspace_id,'person','0128 upgrade private original','+1 773 555 0129',c.app_user_id
FROM fixture_0129_upgrade_context c CROSS JOIN (VALUES
 ('7f298000-0000-4000-8000-000000000001'::uuid),('7f298000-0000-4000-8000-000000000002'::uuid)) t(id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM fixture_0129_upgrade_context c JOIN app_data.promotion_targets t USING(workspace_id);
CREATE TEMP TABLE fixture_0129_upgrade_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),p.preview_id,
 '7f298000-0000-4000-8000-000000000001','7f298000-0000-4000-8000-000000000002',
 '7f298000-0000-4000-8000-000000000001','7f298000-0000-4000-8000-000000000002') AS generation_id
FROM fixture_0129_upgrade_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
 'https://0128-upgrade-resolution.example.test','owner',c.project_id,
 '7f298000-0000-4000-8000-000000000001','7f298000-0000-4000-8000-000000000002') p;
CREATE TEMP TABLE fixture_0129_upgrade_submit ON COMMIT DROP AS
SELECT s.result_code FROM fixture_0129_upgrade_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
 c.app_user_id,'0128-upgrade-resolution-submit',1,'contact.submit.v1','0128-upgrade-device','0128-upgrade-resolution-contact',0,
 jsonb_build_object('contactId','0128-upgrade-resolution-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
  'questionnaireVersionId',c.questionnaire_version_id,'reason','0128 original','occurredAtUtc','2025-07-08T09:10:11Z','occurredTimeZone','UTC',
  'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
  'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) s;
CREATE TEMP TABLE fixture_0129_upgrade_pending ON COMMIT DROP AS
SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
 '7f298000-0000-4000-8000-000000000099',g.generation_id,'0128-upgrade-resolution-contact',1,NULL,'unknown',false,true) AS pending_fact_id
FROM fixture_0129_upgrade_context c CROSS JOIN fixture_0129_upgrade_generation g;
CREATE TABLE public.fixture_0129_legacy_function_oids AS
SELECT oid FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0129_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
 SELECT jsonb_agg(to_jsonb(f) ORDER BY f.oid) FROM pg_proc f
 WHERE f.oid IN (SELECT oid FROM public.fixture_0129_legacy_function_oids)
$function$;
CREATE FUNCTION public.fixture_0129_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
 FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('app_data','app_private') AND c.relkind = 'r' ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
  state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
 END LOOP;
 RETURN state;
END $function$;
CREATE TABLE public.fixture_0129_upgrade_state AS
SELECT c.app_user_id,c.workspace_id,c.project_id,g.generation_id,p.pending_fact_id,
 (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
 app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS pending_plan,
 app_data.read_personal_merge_directory_v1('https://0128-upgrade-resolution.example.test','owner',c.project_id,NULL) AS directory_document,
 app_data.read_personal_merge_projection_context_v1('https://0128-upgrade-resolution.example.test','owner',c.project_id) AS context_document,
 app_private.read_known_source_personal_target_merge_projection_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS projection_document,
 app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS split_plan_document,
 public.fixture_0129_function_catalog() AS function_catalog,public.fixture_0129_business_state() AS business_state
FROM fixture_0129_upgrade_context c CROSS JOIN fixture_0129_upgrade_generation g CROSS JOIN fixture_0129_upgrade_pending p;
DO $baseline$
DECLARE saved public.fixture_0129_upgrade_state%ROWTYPE;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0129_upgrade_state;
 IF saved.migration_count <> 127 OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0128_personal_merge_unassigned_contact_confirmation'
  OR to_regprocedure('app_private.plan_unassigned_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)') IS NOT NULL
  OR saved.pending_plan->>'pending_count' <> '1' OR (SELECT result_code FROM fixture_0129_upgrade_submit) <> 'accepted'
  OR jsonb_array_length(saved.function_catalog) <> (SELECT count(*) FROM public.fixture_0129_legacy_function_oids)
 THEN RAISE EXCEPTION '0128→0129 frozen live upgrade baseline drift'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0129_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0129_upgrade_state%ROWTYPE; document jsonb; before_plan jsonb;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0129_upgrade_state;
 IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
  OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0129_personal_merge_contact_resolution_plan'
  OR public.fixture_0129_business_state() IS DISTINCT FROM saved.business_state
  OR public.fixture_0129_function_catalog() IS DISTINCT FROM saved.function_catalog
  OR app_private.read_personal_merge_unassigned_contact_plan_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id) IS DISTINCT FROM saved.pending_plan
  OR app_private.read_known_source_personal_target_merge_projection_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id) IS DISTINCT FROM saved.projection_document
  OR app_private.read_known_source_personal_merge_split_plan_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id) IS DISTINCT FROM saved.split_plan_document
  OR app_data.read_personal_merge_directory_v1('https://0128-upgrade-resolution.example.test','owner',saved.project_id,NULL) IS DISTINCT FROM saved.directory_document
  OR app_data.read_personal_merge_projection_context_v1('https://0128-upgrade-resolution.example.test','owner',saved.project_id) IS DISTINCT FROM saved.context_document
 THEN RAISE EXCEPTION '0129 upgrade changed old complete pg_proc/OID/ACL, facts or existing readers'; END IF;
 before_plan := public.fixture_0129_business_state();
 document := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id,
  saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',
  jsonb_build_array(jsonb_build_object('pending_fact_id',saved.pending_fact_id,'source_target_id','7f298000-0000-4000-8000-000000000002')));
 IF document->>'contract_id' <> 'personal_merge_contact_resolution_plan_v1' OR document->>'conflict_count' <> '0'
  OR document->'known_source_plan' IS DISTINCT FROM saved.pending_plan->'known_source_plan'
  OR document->'pending_fingerprint' IS DISTINCT FROM saved.pending_plan->'pending_fingerprint'
  OR public.fixture_0129_business_state() IS DISTINCT FROM before_plan
  OR public.fixture_0129_function_catalog() IS DISTINCT FROM saved.function_catalog
 THEN RAISE EXCEPTION '0129 upgraded planner changed original business/fence/receipt state or contract'; END IF;
END $function$;
COMMIT;
