\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0130_upgrade_context ON COMMIT DROP AS SELECT * FROM app_data.bootstrap_personal_context('https://0129-upgrade-confirmation.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0129-upgrade-confirmation.example.test','owner') WHERE is_current;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,is_required,allow_unknown,allow_refused,allow_not_applicable)
SELECT questionnaire_version_id,'legacy_answer',1,'0129 original answer','boolean',false,true,true,true FROM fixture_0130_upgrade_context;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.id,c.workspace_id,'person','0129 upgrade private original','+1 773 555 0130',c.app_user_id FROM fixture_0130_upgrade_context c CROSS JOIN (VALUES
 ('7f308000-0000-4000-8000-000000000001'::uuid),('7f308000-0000-4000-8000-000000000002'::uuid)) t(id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id FROM fixture_0130_upgrade_context c JOIN app_data.promotion_targets t USING(workspace_id);
CREATE TEMP TABLE fixture_0130_upgrade_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),p.preview_id,
 '7f308000-0000-4000-8000-000000000001','7f308000-0000-4000-8000-000000000002','7f308000-0000-4000-8000-000000000001','7f308000-0000-4000-8000-000000000002') AS generation_id
FROM fixture_0130_upgrade_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0129-upgrade-confirmation.example.test','owner',c.project_id,
 '7f308000-0000-4000-8000-000000000001','7f308000-0000-4000-8000-000000000002') p;
CREATE TEMP TABLE fixture_0130_upgrade_submit ON COMMIT DROP AS
SELECT s.result_code FROM fixture_0130_upgrade_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id,
 '0129-upgrade-confirmation-submit',1,'contact.submit.v1','0129-upgrade-device','0129-upgrade-confirmation-contact',0,
 jsonb_build_object('contactId','0129-upgrade-confirmation-contact','workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
  'reason','0129 original','occurredAtUtc','2025-07-08T09:10:11.123456Z','occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
  'reachCount',1,'interestLevel',2,'answers',jsonb_build_array(jsonb_build_object('questionId','legacy_answer','state','answered','type','boolean','value',true)),'targetLinks','[]'::jsonb)) s;
CREATE TEMP TABLE fixture_0130_upgrade_pending(pending_fact_id uuid,source_target_id uuid,original_revision integer) ON COMMIT DROP;
INSERT INTO fixture_0130_upgrade_pending SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),g.generation_id,
 '0129-upgrade-confirmation-contact',1,0,'yes',false,true),'7f308000-0000-4000-8000-000000000001',1 FROM fixture_0130_upgrade_context c CROSS JOIN fixture_0130_upgrade_generation g;
SELECT s.result_code FROM fixture_0130_upgrade_context c CROSS JOIN LATERAL app_data.apply_contact_revise_v3(c.app_user_id,'0129-upgrade-confirmation-revise',1,'contact.revise.v1',
 '0129-upgrade-device','0129-upgrade-confirmation-contact',1,(SELECT snapshot FROM app_data.contact_revisions WHERE contact_id = '0129-upgrade-confirmation-contact' AND revision_number = 1)
 || jsonb_build_object('interestLevel',4,'occurredAtUtc','2025-07-09T10:11:12.654321Z',
  'answers',jsonb_build_array(jsonb_build_object('questionId','legacy_answer','state','answered','type','boolean','value',false)))) s;
INSERT INTO fixture_0130_upgrade_pending SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),g.generation_id,
 '0129-upgrade-confirmation-contact',2,4,'no',false,true),'7f308000-0000-4000-8000-000000000001',2 FROM fixture_0130_upgrade_context c CROSS JOIN fixture_0130_upgrade_generation g;
CREATE TABLE public.fixture_0130_legacy_function_oids AS SELECT oid FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0130_legacy_relations AS SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('app_data','app_private') AND c.relkind = 'r';
CREATE FUNCTION public.fixture_0130_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
 SELECT jsonb_agg(CASE WHEN f.oid IN ('app_private.guard_personal_merge_unassigned_contact_end_v1()'::regprocedure,'app_private.guard_personal_merge_unassigned_contact_payload_v1()'::regprocedure)
  THEN to_jsonb(f) - 'prosrc' ELSE to_jsonb(f) END ORDER BY f.oid) FROM pg_proc f WHERE f.oid IN (SELECT oid FROM public.fixture_0130_legacy_function_oids)
$function$;
CREATE FUNCTION public.fixture_0130_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
 FOR relation IN SELECT * FROM public.fixture_0130_legacy_relations ORDER BY nspname,relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
  state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
 END LOOP;
 RETURN state;
END $function$;
CREATE TABLE public.fixture_0130_upgrade_state AS
SELECT c.app_user_id,c.workspace_id,c.project_id,c.questionnaire_version_id,g.generation_id,gen_random_uuid() AS request_id,
 (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
 app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS pending_plan,
 app_private.read_known_source_personal_target_merge_projection_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS projection_document,
 app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS split_plan_document,
 (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id) FROM fixture_0130_upgrade_pending) AS assignments,
 public.fixture_0130_function_catalog() AS function_catalog,public.fixture_0130_business_state() AS business_state
FROM fixture_0130_upgrade_context c CROSS JOIN fixture_0130_upgrade_generation g;
ALTER TABLE public.fixture_0130_upgrade_state ADD COLUMN resolution_plan jsonb;
UPDATE public.fixture_0130_upgrade_state s SET resolution_plan = app_private.plan_unassigned_personal_merge_contact_resolutions_v1(s.app_user_id,s.workspace_id,s.project_id,s.generation_id,
 s.pending_plan->'known_source_plan'->>'fact_fingerprint',s.pending_plan->>'pending_fingerprint',s.assignments);
DO $baseline$
DECLARE saved public.fixture_0130_upgrade_state%ROWTYPE;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0130_upgrade_state;
 IF saved.migration_count <> 128 OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0129_personal_merge_contact_resolution_plan'
  OR to_regprocedure('app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)') IS NOT NULL
  OR saved.pending_plan->>'pending_count' <> '2' OR saved.resolution_plan->>'conflict_count' <> '1' OR (SELECT result_code FROM fixture_0130_upgrade_submit) <> 'accepted'
  OR jsonb_array_length(saved.function_catalog) <> (SELECT count(*) FROM public.fixture_0130_legacy_function_oids)
 THEN RAISE EXCEPTION '0129→0130 frozen live upgrade baseline drift'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0130_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0130_upgrade_state%ROWTYPE; document jsonb; choices jsonb; result timestamptz; after_state jsonb; actual text;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0130_upgrade_state;
 IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
  OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0130_personal_merge_contact_resolution_confirmation'
  OR public.fixture_0130_business_state() IS DISTINCT FROM saved.business_state OR public.fixture_0130_function_catalog() IS DISTINCT FROM saved.function_catalog
  OR app_private.read_personal_merge_unassigned_contact_plan_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id) IS DISTINCT FROM saved.pending_plan
  OR app_private.read_known_source_personal_target_merge_projection_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id) IS DISTINCT FROM saved.projection_document
  OR app_private.read_known_source_personal_merge_split_plan_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id) IS DISTINCT FROM saved.split_plan_document
  OR app_private.plan_unassigned_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id,
    saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',saved.assignments) IS DISTINCT FROM saved.resolution_plan
 THEN RAISE EXCEPTION '0130 upgrade changed legacy pg_proc/OID/ACL, facts or existing readers'; END IF;
 BEGIN
  PERFORM app_private.confirm_unassigned_personal_merge_contacts_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.request_id,saved.generation_id,
   saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',saved.assignments);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE; END;
 IF actual IS DISTINCT FROM '23505' OR public.fixture_0130_business_state() IS DISTINCT FROM saved.business_state THEN RAISE EXCEPTION '0130 widened the original 0128 restricted writer'; END IF;
 choices := jsonb_build_array(jsonb_build_object('contact_id','0129-upgrade-confirmation-contact','source_target_id','7f308000-0000-4000-8000-000000000001','candidate_kind','pending',
  'pending_fact_id',(SELECT pending_fact_id FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE generation_id = saved.generation_id AND revision_number = 1)));
 result := app_private.confirm_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.request_id,saved.generation_id,
  saved.resolution_plan->'known_source_plan'->>'fact_fingerprint',saved.resolution_plan->>'pending_fingerprint',saved.resolution_plan->>'resolution_fingerprint',saved.assignments,choices);
 IF result IS NULL OR (SELECT current_revision FROM app_data.contacts WHERE contact_id = '0129-upgrade-confirmation-contact') <> 5
  OR (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE request_id = saved.request_id) <> 2
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE request_id = saved.request_id) <> 1
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE request_id = saved.request_id) <> 1
  OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 f JOIN app_private.personal_merge_unassigned_contact_requests_v1 p USING(pending_fact_id) WHERE p.generation_id = saved.generation_id)
  OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = saved.generation_id)
  OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links WHERE contact_id = '0129-upgrade-confirmation-contact' AND revision_number = 5 AND promotion_target_id = '7f308000-0000-4000-8000-000000000001' AND response_level = 0 AND follow_up_consent = 'yes')
  OR EXISTS (SELECT 1 FROM app_data.contact_revisions WHERE contact_id = '0129-upgrade-confirmation-contact' AND snapshot->>'questionnaireVersionId' <> saved.questionnaire_version_id::text)
  OR (SELECT count(*) FROM app_data.contact_answers WHERE contact_id = '0129-upgrade-confirmation-contact' AND question_id = 'legacy_answer') <> 5
  OR (SELECT array_agg(boolean_value ORDER BY revision_number) FROM app_data.contact_answers WHERE contact_id = '0129-upgrade-confirmation-contact' AND question_id = 'legacy_answer')
   IS DISTINCT FROM ARRAY[true,false,true,false,false]
  OR (SELECT array_agg((snapshot->>'occurredAtUtc')::timestamptz ORDER BY revision_number) FROM app_data.contact_revisions WHERE contact_id = '0129-upgrade-confirmation-contact')
   IS DISTINCT FROM ARRAY[timestamptz '2025-07-08T09:10:11.123456Z',timestamptz '2025-07-09T10:11:12.654321Z',timestamptz '2025-07-08T09:10:11.123456Z',timestamptz '2025-07-09T10:11:12.654321Z',timestamptz '2025-07-09T10:11:12.654321Z']
 THEN RAISE EXCEPTION '0130 upgraded writer lost independent historical applications, explicit older choice or legacy answers'; END IF;
 after_state := public.fixture_0130_business_state();
 IF app_private.confirm_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.request_id,saved.generation_id,
   saved.resolution_plan->'known_source_plan'->>'fact_fingerprint',saved.resolution_plan->>'pending_fingerprint',saved.resolution_plan->>'resolution_fingerprint',saved.assignments,choices) IS DISTINCT FROM result
  OR public.fixture_0130_business_state() IS DISTINCT FROM after_state OR public.fixture_0130_function_catalog() IS DISTINCT FROM saved.function_catalog
 THEN RAISE EXCEPTION '0130 upgraded writer terminal replay changed timestamp or facts'; END IF;
END $function$;
COMMIT;
