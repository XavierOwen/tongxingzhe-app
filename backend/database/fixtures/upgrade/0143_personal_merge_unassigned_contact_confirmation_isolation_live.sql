\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $version$
BEGIN
 IF (SELECT max(version) FROM app_migrations.schema_migrations)<>'0143_personal_merge_mixed_project_entry_confirmation'
 THEN RAISE EXCEPTION '0143 contact isolation upgrade requires the real 0143 baseline'; END IF;
END $version$;

CREATE TEMP TABLE fixture_0143_contact_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://0143-upgrade-contact-isolation.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0143-upgrade-contact-isolation.example.test','owner') WHERE is_current;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.target_id,c.workspace_id,'person','0143 upgrade original source','+1 773 555 0144',c.app_user_id
FROM fixture_0143_contact_context c CROSS JOIN (VALUES
 ('7f448000-0000-4000-8000-000000000001'::uuid),('7f448000-0000-4000-8000-000000000002'::uuid)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0143_contact_context c WHERE t.workspace_id=c.workspace_id;
CREATE TEMP TABLE fixture_0143_contact_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),p.preview_id,
 '7f448000-0000-4000-8000-000000000001','7f448000-0000-4000-8000-000000000002',
 '7f448000-0000-4000-8000-000000000001','7f448000-0000-4000-8000-000000000002') AS generation_id
FROM fixture_0143_contact_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
 'https://0143-upgrade-contact-isolation.example.test','owner',c.project_id,
 '7f448000-0000-4000-8000-000000000001','7f448000-0000-4000-8000-000000000002') p;
CREATE TEMP TABLE fixture_0143_contact_submit ON COMMIT DROP AS
SELECT s.result_code FROM fixture_0143_contact_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
 c.app_user_id,'0143-upgrade-contact-isolation-submit',1,'contact.submit.v1','0143-upgrade-device','0143-upgrade-contact-isolation',0,
 jsonb_build_object('contactId','0143-upgrade-contact-isolation','workspaceId',c.workspace_id,'projectId',c.project_id,
  'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc','2024-07-08T09:10:11Z','occurredTimeZone','UTC',
  'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
  'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) s;
CREATE TEMP TABLE fixture_0143_contact_pending ON COMMIT DROP AS
SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
 '7f448000-0000-4000-8000-000000000098',g.generation_id,'0143-upgrade-contact-isolation',1,2,'yes',false,true) AS pending_fact_id
FROM fixture_0143_contact_context c CROSS JOIN fixture_0143_contact_generation g;
CREATE TEMP TABLE fixture_0143_contact_plan ON COMMIT DROP AS
SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS document
FROM fixture_0143_contact_context c CROSS JOIN fixture_0143_contact_generation g;

CREATE TABLE public.fixture_0143_contact_legacy_functions AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0143_contact_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE statements text; result jsonb;
BEGIN
 SELECT string_agg(format(
  'SELECT %L::text AS relation_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS contents FROM %I.%I t',
  schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)
 INTO statements FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');
 IF statements IS NULL THEN RETURN '{}'::jsonb; END IF;
 EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM ('||statements||') snapshots' INTO result;
 RETURN result;
END $function$;
CREATE FUNCTION public.fixture_0143_contact_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
 SELECT jsonb_agg(CASE WHEN p.oid='app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure
  THEN to_jsonb(p)-'prosrc' ELSE to_jsonb(p) END ORDER BY p.oid)
 FROM pg_catalog.pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
$function$;
CREATE TABLE public.fixture_0143_contact_isolation_seed AS
SELECT c.app_user_id,c.workspace_id,c.project_id,g.generation_id,'7f448000-0000-4000-8000-000000000099'::uuid AS request_id,
 p.document->'known_source_plan'->>'fact_fingerprint' AS known_fingerprint,p.document->>'pending_fingerprint' AS pending_fingerprint,
 jsonb_build_array(jsonb_build_object('pending_fact_id',n.pending_fact_id,
  'source_target_id','7f448000-0000-4000-8000-000000000002')) AS assignments,
 (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
 public.fixture_0143_contact_function_catalog() AS function_catalog,
 (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=
  'app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure) AS function_source
FROM fixture_0143_contact_context c CROSS JOIN fixture_0143_contact_generation g
CROSS JOIN fixture_0143_contact_pending n CROSS JOIN fixture_0143_contact_plan p;
ALTER TABLE public.fixture_0143_contact_isolation_seed ADD COLUMN result_at timestamptz;
UPDATE public.fixture_0143_contact_isolation_seed SET result_at=app_private.confirm_unassigned_personal_merge_contacts_v1(
 app_user_id,workspace_id,project_id,request_id,generation_id,known_fingerprint,pending_fingerprint,assignments);
ALTER TABLE public.fixture_0143_contact_isolation_seed ADD COLUMN confirmed_at_utc timestamptz;
UPDATE public.fixture_0143_contact_isolation_seed s SET confirmed_at_utc=(SELECT r.confirmed_at_utc
 FROM app_private.personal_merge_contact_confirmation_requests_v1 r WHERE r.actor_app_user_id=s.app_user_id AND r.request_id=s.request_id);
ALTER TABLE public.fixture_0143_contact_isolation_seed ADD COLUMN business_state jsonb;
UPDATE public.fixture_0143_contact_isolation_seed SET business_state=public.fixture_0143_contact_business_state();
DO $baseline$
DECLARE saved public.fixture_0143_contact_isolation_seed%ROWTYPE;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0143_contact_isolation_seed;
 IF (SELECT result_code FROM fixture_0143_contact_submit) IS DISTINCT FROM 'accepted'
  OR saved.result_at IS NULL OR saved.confirmed_at_utc IS NULL
  OR (SELECT count(*) FROM public.fixture_0143_contact_legacy_functions)<>jsonb_array_length(saved.function_catalog)
  OR NOT app_private.personal_merge_contact_confirmation_proof_v1(saved.app_user_id,saved.request_id)
  OR (SELECT count(*) FROM app_private.personal_merge_contact_confirmation_requests_v1
   WHERE actor_app_user_id=saved.app_user_id AND request_id=saved.request_id)<>1
  OR (SELECT count(*) FROM app_private.personal_merge_contact_applications_v1
   WHERE actor_app_user_id=saved.app_user_id AND request_id=saved.request_id)<>1
  OR (SELECT current_revision FROM app_data.contacts WHERE contact_id='0143-upgrade-contact-isolation') IS DISTINCT FROM 2
  OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links WHERE contact_id='0143-upgrade-contact-isolation'
   AND revision_number=2 AND promotion_target_id='7f448000-0000-4000-8000-000000000002'
   AND response_level=2 AND follow_up_consent='yes' AND NOT institution_representative_confirmed AND confirmed_project_entry)
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1
   WHERE actor_app_user_id=saved.app_user_id AND request_id=saved.request_id AND generation_id=saved.generation_id
    AND outcome='ended' AND reason='known_source_split' AND ended_at_utc=saved.result_at)
  OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
   JOIN app_private.personal_merge_unassigned_contact_requests_v1 pending USING(pending_fact_id) WHERE pending.generation_id=saved.generation_id)
 THEN RAISE EXCEPTION '0143 frozen single-contact terminal confirmation baseline drift'; END IF;
END $baseline$;
COMMIT;

CREATE FUNCTION public.fixture_0143_contact_isolation_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0143_contact_isolation_seed%ROWTYPE; actual_source text; result timestamptz;
 guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'pending contact confirmation requires read committed';
  END IF;
$guard$;
 parent_lock text := $parent$  PERFORM pg_advisory_xact_lock(hashtextextended(trusted_app_user_id::text || ':' || requested_request_id::text, 0));$parent$;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0143_contact_isolation_seed;
 SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc
 WHERE oid='app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)'::regprocedure;
 IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
  OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0144_personal_merge_unassigned_contact_confirmation_isolation'
  OR public.fixture_0143_contact_business_state() IS DISTINCT FROM saved.business_state
  OR public.fixture_0143_contact_function_catalog() IS DISTINCT FROM saved.function_catalog
  OR replace(actual_source,guard,'') IS DISTINCT FROM saved.function_source
  OR length(actual_source)-length(replace(actual_source,guard,''))<>length(guard)
  OR length(actual_source)-length(replace(actual_source,chr(10),''))<>
   length(saved.function_source)-length(replace(saved.function_source,chr(10),''))+3
  OR position(guard||parent_lock IN actual_source)=0
  OR (SELECT confirmed_at_utc FROM app_private.personal_merge_contact_confirmation_requests_v1
   WHERE actor_app_user_id=saved.app_user_id AND request_id=saved.request_id) IS DISTINCT FROM saved.confirmed_at_utc
 THEN RAISE EXCEPTION '0143→0144 changed legacy state or confirmation beyond the three-line isolation guard'; END IF;
 IF current_setting('transaction_isolation')<>'read committed'
 THEN RAISE EXCEPTION '0144 upgrade replay requires read committed'; END IF;
 result := app_private.confirm_unassigned_personal_merge_contacts_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
  saved.request_id,saved.generation_id,saved.known_fingerprint,saved.pending_fingerprint,saved.assignments);
 IF result IS DISTINCT FROM saved.result_at OR public.fixture_0143_contact_business_state() IS DISTINCT FROM saved.business_state
  OR public.fixture_0143_contact_function_catalog() IS DISTINCT FROM saved.function_catalog
 THEN RAISE EXCEPTION '0144 RC single-contact terminal replay changed its receipt or data'; END IF;
END $function$;
