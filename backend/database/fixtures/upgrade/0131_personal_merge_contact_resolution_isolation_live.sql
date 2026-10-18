\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0131_resolution_saved ON COMMIT DROP AS
SELECT s.*,jsonb_build_array(jsonb_build_object('contact_id','0129-upgrade-confirmation-contact',
 'source_target_id','7f308000-0000-4000-8000-000000000001','candidate_kind','pending',
 'pending_fact_id',(SELECT pending_fact_id FROM app_private.personal_merge_unassigned_contact_requests_v1
  WHERE generation_id=s.generation_id AND revision_number=1))) AS choices
FROM public.fixture_0130_upgrade_state s;

CREATE TABLE public.fixture_0131_resolution_legacy_relations AS
SELECT n.nspname,c.relname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r';
CREATE TABLE public.fixture_0131_resolution_legacy_functions AS
SELECT p.oid,p.oid::regprocedure::text AS signature,to_jsonb(p) AS catalog_row
FROM pg_catalog.pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0131_resolution_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
 FOR relation IN SELECT * FROM public.fixture_0131_resolution_legacy_relations ORDER BY nspname,relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
  state := state || jsonb_build_object(relation.nspname||'.'||relation.relname,rows);
 END LOOP;
 RETURN state;
END $function$;
CREATE FUNCTION public.fixture_0131_resolution_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
 SELECT jsonb_agg(CASE WHEN p.oid='app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure
  THEN to_jsonb(p)-'prosrc' ELSE to_jsonb(p) END ORDER BY p.oid)
 FROM pg_catalog.pg_proc p JOIN public.fixture_0131_resolution_legacy_functions old ON old.oid=p.oid
$function$;

CREATE TABLE public.fixture_0131_resolution_seed AS
SELECT s.app_user_id,s.workspace_id,s.project_id,s.generation_id,s.request_id,
 s.resolution_plan->'known_source_plan'->>'fact_fingerprint' AS known_fingerprint,
 s.resolution_plan->>'pending_fingerprint' AS pending_fingerprint,
 s.resolution_plan->>'resolution_fingerprint' AS resolution_fingerprint,
 s.assignments,s.choices,(SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
 public.fixture_0131_resolution_function_catalog() AS function_catalog
FROM fixture_0131_resolution_saved s;
ALTER TABLE public.fixture_0131_resolution_seed ADD COLUMN result_at timestamptz;
UPDATE public.fixture_0131_resolution_seed SET result_at=app_private.confirm_personal_merge_contact_resolutions_v1(app_user_id,workspace_id,project_id,request_id,generation_id,
 known_fingerprint,pending_fingerprint,resolution_fingerprint,assignments,choices);
ALTER TABLE public.fixture_0131_resolution_seed ADD COLUMN confirmed_at_utc timestamptz;
UPDATE public.fixture_0131_resolution_seed SET confirmed_at_utc=(SELECT confirmed_at_utc FROM app_private.personal_merge_contact_resolution_requests_v1
 WHERE request_id=fixture_0131_resolution_seed.request_id);
ALTER TABLE public.fixture_0131_resolution_seed ADD COLUMN business_state jsonb;
UPDATE public.fixture_0131_resolution_seed SET business_state=public.fixture_0131_resolution_business_state();
ALTER TABLE public.fixture_0131_resolution_seed ADD COLUMN function_source text;
UPDATE public.fixture_0131_resolution_seed SET function_source=(SELECT prosrc FROM pg_proc
 WHERE oid='app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure);
DO $baseline$
BEGIN
 IF (SELECT count(*) FROM public.fixture_0131_resolution_seed)<>1
  OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0131_personal_target_expiry_dispatch'
  OR (SELECT count(*) FROM public.fixture_0131_resolution_legacy_functions)<>jsonb_array_length(public.fixture_0131_resolution_function_catalog())
  OR (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed))<>2
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed))<>1
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed))<>1
  OR (SELECT current_revision FROM app_data.contacts WHERE contact_id='0129-upgrade-confirmation-contact')<>5
  OR (SELECT count(*) FROM app_private.personal_merge_contact_resolution_requests_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed))<>1
 THEN RAISE EXCEPTION '0131 frozen terminal confirmation baseline drift: seed %, version %, functions %/% history % current revision % choices % head % receipts %',
  (SELECT count(*) FROM public.fixture_0131_resolution_seed),(SELECT max(version) FROM app_migrations.schema_migrations),
  (SELECT count(*) FROM public.fixture_0131_resolution_legacy_functions),(SELECT jsonb_array_length(public.fixture_0131_resolution_function_catalog())),
  (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed)),
  (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed)),
  (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed)),
  (SELECT current_revision FROM app_data.contacts WHERE contact_id='0129-upgrade-confirmation-contact'),
  (SELECT count(*) FROM app_private.personal_merge_contact_resolution_requests_v1 WHERE request_id=(SELECT request_id FROM public.fixture_0131_resolution_seed)); END IF;
END $baseline$;
COMMIT;

CREATE FUNCTION public.fixture_0131_resolution_isolation_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0131_resolution_seed%ROWTYPE; before_state jsonb; actual_source text; result timestamptz;
 guard text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'pending contact resolution confirmation requires read committed';
  END IF;
$guard$;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0131_resolution_seed;
 SELECT prosrc INTO STRICT actual_source FROM pg_proc
 WHERE oid='app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure;
 IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
  OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0132_personal_merge_contact_resolution_isolation'
  OR public.fixture_0131_resolution_business_state() IS DISTINCT FROM saved.business_state
  OR public.fixture_0131_resolution_function_catalog() IS DISTINCT FROM saved.function_catalog
  OR replace(actual_source,guard,'') IS DISTINCT FROM saved.function_source
  OR length(actual_source)-length(replace(actual_source,chr(10),'')) <> length(saved.function_source)-length(replace(saved.function_source,chr(10),''))+3
  OR length(actual_source)-length(replace(actual_source,guard,'')) <> length(guard)
  OR (SELECT confirmed_at_utc FROM app_private.personal_merge_contact_resolution_requests_v1 WHERE request_id=saved.request_id) IS DISTINCT FROM saved.confirmed_at_utc
 THEN RAISE EXCEPTION '0131→0132 changed legacy state or confirmation implementation beyond the three-line guard'; END IF;
 before_state := public.fixture_0131_resolution_business_state();
 result := app_private.confirm_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.request_id,saved.generation_id,
  saved.known_fingerprint,saved.pending_fingerprint,saved.resolution_fingerprint,saved.assignments,saved.choices);
 IF result IS DISTINCT FROM saved.result_at OR public.fixture_0131_resolution_business_state() IS DISTINCT FROM before_state
  OR public.fixture_0131_resolution_function_catalog() IS DISTINCT FROM saved.function_catalog
 THEN RAISE EXCEPTION '0132 RC historical terminal replay changed its receipt or data'; END IF;
END $function$;
