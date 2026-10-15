\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0128_upgrade_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://0127-upgrade-confirmation.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0127-upgrade-confirmation.example.test','owner') WHERE is_current;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.target_id,c.workspace_id,'person','0127 upgrade original source','+1 773 555 0128',c.app_user_id
FROM fixture_0128_upgrade_context c CROSS JOIN (VALUES
  ('7f288000-0000-4000-8000-000000000001'::uuid),('7f288000-0000-4000-8000-000000000002'::uuid),
  ('7f288000-0000-4000-8000-000000000003'::uuid),('7f288000-0000-4000-8000-000000000004'::uuid),
  ('7f288000-0000-4000-8000-000000000005'::uuid),('7f288000-0000-4000-8000-000000000006'::uuid)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0128_upgrade_context c WHERE t.workspace_id = c.workspace_id;
CREATE TEMP TABLE fixture_0128_upgrade_generations ON COMMIT DROP AS
SELECT t.kind,app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,
  gen_random_uuid(),p.preview_id,t.first_target,t.second_target,t.first_target,t.second_target) AS generation_id
FROM fixture_0128_upgrade_context c CROSS JOIN (VALUES
  ('active','7f288000-0000-4000-8000-000000000001'::uuid,'7f288000-0000-4000-8000-000000000002'::uuid),
  ('ended','7f288000-0000-4000-8000-000000000003'::uuid,'7f288000-0000-4000-8000-000000000004'::uuid),
  ('expired','7f288000-0000-4000-8000-000000000005'::uuid,'7f288000-0000-4000-8000-000000000006'::uuid)
) t(kind,first_target,second_target)
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0127-upgrade-confirmation.example.test','owner',c.project_id,t.first_target,t.second_target) p;
CREATE TEMP TABLE fixture_0128_upgrade_end ON COMMIT DROP AS
SELECT g.generation_id,gen_random_uuid() AS request_id,m.fact_fingerprint
FROM fixture_0128_upgrade_generations g CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(g.generation_id) m WHERE kind = 'ended';
ALTER TABLE fixture_0128_upgrade_end ADD COLUMN ended_at_utc timestamptz;
UPDATE fixture_0128_upgrade_end e SET ended_at_utc = app_private.end_known_source_personal_target_merge_generation_v1(
  c.app_user_id,c.workspace_id,c.project_id,e.request_id,e.generation_id,e.fact_fingerprint) FROM fixture_0128_upgrade_context c;
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7f288000-0000-4000-8000-000000000005';
CREATE TEMP TABLE fixture_0128_upgrade_expiry ON COMMIT DROP AS
SELECT g.generation_id,gen_random_uuid() AS request_id FROM fixture_0128_upgrade_generations g WHERE kind = 'expired';
ALTER TABLE fixture_0128_upgrade_expiry ADD COLUMN ended_at_utc timestamptz;
UPDATE fixture_0128_upgrade_expiry e SET ended_at_utc = app_private.expire_known_source_personal_target_merge_generation_v1(
  c.app_user_id,c.workspace_id,c.project_id,e.request_id,e.generation_id) FROM fixture_0128_upgrade_context c;
CREATE TEMP TABLE fixture_0128_upgrade_submit ON COMMIT DROP AS
SELECT s.result_code FROM fixture_0128_upgrade_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id,'0127-upgrade-confirmation-submit',1,'contact.submit.v1','0127-upgrade-device','0127-upgrade-confirmation-contact',0,
  jsonb_build_object('contactId','0127-upgrade-confirmation-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
    'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc','2024-07-08T09:10:11Z','occurredTimeZone','UTC',
    'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
    'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) s;
CREATE TEMP TABLE fixture_0128_upgrade_pending ON COMMIT DROP AS
SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f288000-0000-4000-8000-000000000099',g.generation_id,'0127-upgrade-confirmation-contact',1,NULL,'unknown',false,true) AS pending_fact_id
FROM fixture_0128_upgrade_context c CROSS JOIN fixture_0128_upgrade_generations g WHERE kind = 'active';
CREATE TABLE public.fixture_0128_legacy_function_oids AS
SELECT oid FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0128_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(CASE WHEN f.oid IN (
      'app_private.guard_personal_merge_unassigned_contact_payload_v1()'::regprocedure,
      'app_private.guard_personal_merge_unassigned_contact_end_v1()'::regprocedure)
    THEN to_jsonb(f) - 'prosrc' ELSE to_jsonb(f) END ORDER BY f.oid)
  FROM pg_proc f WHERE f.oid IN (SELECT oid FROM public.fixture_0128_legacy_function_oids)
$function$;
CREATE FUNCTION public.fixture_0128_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind = 'r'
      AND c.relname NOT IN ('personal_merge_contact_confirmation_requests_v1','personal_merge_contact_applications_v1')
    ORDER BY n.nspname,c.relname LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE TEMP TABLE fixture_0128_upgrade_old_readers ON COMMIT DROP AS
SELECT app_data.read_personal_merge_directory_v1('https://0127-upgrade-confirmation.example.test','owner',c.project_id,NULL) AS directory_document,
  app_data.read_personal_merge_projection_context_v1('https://0127-upgrade-confirmation.example.test','owner',c.project_id) AS context_document
FROM fixture_0128_upgrade_context c;
CREATE TABLE public.fixture_0128_upgrade_state AS
SELECT c.app_user_id,c.workspace_id,c.project_id,g.generation_id AS active_generation_id,p.pending_fact_id,
  e.generation_id AS ended_generation_id,e.request_id AS ended_request_id,e.fact_fingerprint AS ended_fingerprint,e.ended_at_utc,
  x.generation_id AS expired_generation_id,x.request_id AS expired_request_id,x.ended_at_utc AS expired_at_utc,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
  app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS pending_plan,
  app_private.read_known_source_personal_target_merge_projection_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS projection_document,
  app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS split_plan_document,
  (SELECT jsonb_agg(jsonb_build_object('generation_id',v.generation_id,'fact_count',m.fact_count,'fact_fingerprint',m.fact_fingerprint) ORDER BY v.generation_id)
    FROM app_private.personal_target_merge_generations_v1 v CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(v.generation_id) m
    WHERE v.workspace_id = c.workspace_id) AS manifests,
  public.fixture_0128_function_catalog() AS function_catalog,
  (SELECT directory_document FROM fixture_0128_upgrade_old_readers) AS directory_document,
  (SELECT context_document FROM fixture_0128_upgrade_old_readers) AS context_document,
  public.fixture_0128_business_state() AS business_state
FROM fixture_0128_upgrade_context c CROSS JOIN fixture_0128_upgrade_generations g CROSS JOIN fixture_0128_upgrade_pending p
CROSS JOIN fixture_0128_upgrade_end e CROSS JOIN fixture_0128_upgrade_expiry x WHERE g.kind = 'active';
DO $baseline$
DECLARE saved public.fixture_0128_upgrade_state%ROWTYPE;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0128_upgrade_state;
  IF saved.migration_count <> 126 OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0127_personal_merge_unassigned_contacts'
    OR to_regprocedure('app_private.confirm_unassigned_personal_merge_contacts_v1(uuid,uuid,uuid,uuid,uuid,text,text,jsonb)') IS NOT NULL
    OR saved.pending_plan->>'pending_count' <> '1' OR (SELECT result_code FROM fixture_0128_upgrade_submit) <> 'accepted'
    OR jsonb_array_length(saved.function_catalog) <> (SELECT count(*) FROM public.fixture_0128_legacy_function_oids)
  THEN RAISE EXCEPTION '0127→0128 live upgrade baseline drift'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0128_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0128_upgrade_state%ROWTYPE; confirmed timestamptz; state jsonb; assignments jsonb; document jsonb;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0128_upgrade_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
    OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0128_personal_merge_unassigned_contact_confirmation'
    OR public.fixture_0128_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0128_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR app_private.read_personal_merge_unassigned_contact_plan_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.active_generation_id) IS DISTINCT FROM saved.pending_plan
    OR app_private.read_known_source_personal_target_merge_projection_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.active_generation_id) IS DISTINCT FROM saved.projection_document
    OR app_private.read_known_source_personal_merge_split_plan_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.active_generation_id) IS DISTINCT FROM saved.split_plan_document
    OR (SELECT jsonb_agg(jsonb_build_object('generation_id',v.generation_id,'fact_count',m.fact_count,'fact_fingerprint',m.fact_fingerprint) ORDER BY v.generation_id)
      FROM app_private.personal_target_merge_generations_v1 v CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(v.generation_id) m
      WHERE v.workspace_id = saved.workspace_id) IS DISTINCT FROM saved.manifests
    OR app_private.end_known_source_personal_target_merge_generation_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
      saved.ended_request_id,saved.ended_generation_id,saved.ended_fingerprint) IS DISTINCT FROM saved.ended_at_utc
    OR app_private.expire_known_source_personal_target_merge_generation_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
      saved.expired_request_id,saved.expired_generation_id) IS DISTINCT FROM saved.expired_at_utc
  THEN RAISE EXCEPTION '0128 upgrade changed existing functions/OID/ACL, facts, manifests, readers or terminal replay'; END IF;
  SET LOCAL ROLE tongxingzhe_runtime;
  document := app_data.read_personal_merge_directory_v1('https://0127-upgrade-confirmation.example.test','owner',saved.project_id,NULL);
  RESET ROLE;
  IF document IS DISTINCT FROM saved.directory_document
    OR app_data.read_personal_merge_projection_context_v1('https://0127-upgrade-confirmation.example.test','owner',saved.project_id)
      IS DISTINCT FROM saved.context_document
  THEN RAISE EXCEPTION '0128 changed old directory or context reader'; END IF;
  SET LOCAL ROLE tongxingzhe_runtime;
  document := app_data.read_personal_known_source_merge_projection_v1(
    'https://0127-upgrade-confirmation.example.test','owner',saved.project_id,saved.active_generation_id);
  RESET ROLE;
  IF document IS DISTINCT FROM saved.projection_document THEN RAISE EXCEPTION '0128 changed old runtime projection reader'; END IF;
  SET LOCAL ROLE tongxingzhe_runtime;
  document := app_data.read_personal_known_source_merge_split_plan_v1(
    'https://0127-upgrade-confirmation.example.test','owner',saved.project_id,saved.active_generation_id);
  RESET ROLE;
  IF document IS DISTINCT FROM saved.split_plan_document THEN RAISE EXCEPTION '0128 changed old runtime split-plan reader'; END IF;
  assignments := jsonb_build_array(jsonb_build_object('pending_fact_id',saved.pending_fact_id,'source_target_id','7f288000-0000-4000-8000-000000000002'));
  confirmed := app_private.confirm_unassigned_personal_merge_contacts_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
    '7f288000-0000-4000-8000-000000000100',saved.active_generation_id,
    saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',assignments);
  state := public.fixture_0128_business_state();
  IF app_private.confirm_unassigned_personal_merge_contacts_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
      '7f288000-0000-4000-8000-000000000100',saved.active_generation_id,
      saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',assignments) IS DISTINCT FROM confirmed
    OR public.fixture_0128_business_state() IS DISTINCT FROM state
    OR public.fixture_0128_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id = saved.pending_fact_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.contact_revisions WHERE contact_id = '0127-upgrade-confirmation-contact' AND revision_number = 1)
    OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links WHERE contact_id = '0127-upgrade-confirmation-contact'
      AND revision_number = 2 AND promotion_target_id = '7f288000-0000-4000-8000-000000000002' AND response_level IS NULL)
  THEN RAISE EXCEPTION '0128 upgraded pending contact confirmation, history or replay drift'; END IF;
END $function$;
COMMIT;
