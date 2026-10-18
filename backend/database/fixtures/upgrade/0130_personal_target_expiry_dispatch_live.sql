\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0130_expiry_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://0130-upgrade-expiry.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0130-upgrade-expiry.example.test','owner') WHERE is_current;

CREATE TEMP TABLE fixture_0130_expiry_targets(label text,target_id uuid,kind text) ON COMMIT DROP;
INSERT INTO fixture_0130_expiry_targets VALUES
 ('old-a','7f300100-0000-4000-8000-000000000021','person'),('old-b','7f300100-0000-4000-8000-000000000022','person'),
 ('active-a','7f300100-0000-4000-8000-000000000023','person'),('active-b','7f300100-0000-4000-8000-000000000024','person'),
 ('ordinary','7f300100-0000-4000-8000-000000000025','person');
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.target_id,c.workspace_id,t.kind,'0130 upgrade synthetic source ' || t.label,'+1 773 555 0130',c.app_user_id
FROM fixture_0130_expiry_context c CROSS JOIN fixture_0130_expiry_targets t;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id FROM app_data.promotion_targets t
CROSS JOIN fixture_0130_expiry_context c WHERE t.workspace_id=c.workspace_id;
CREATE TEMP TABLE fixture_0130_expiry_generations(label text,generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0130_expiry_generations
SELECT g.label,app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),p.preview_id,g.first_target,g.second_target,g.first_target,g.second_target)
FROM fixture_0130_expiry_context c CROSS JOIN (VALUES
 ('old','7f300100-0000-4000-8000-000000000021'::uuid,'7f300100-0000-4000-8000-000000000022'::uuid),
 ('active','7f300100-0000-4000-8000-000000000023'::uuid,'7f300100-0000-4000-8000-000000000024'::uuid)
) g(label,first_target,second_target)
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0130-upgrade-expiry.example.test','owner',c.project_id,g.first_target,g.second_target) p;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months'
WHERE promotion_target_id IN ('7f300100-0000-4000-8000-000000000021','7f300100-0000-4000-8000-000000000022','7f300100-0000-4000-8000-000000000025');
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months'
WHERE promotion_target_id='7f300100-0000-4000-8000-000000000023';
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()
WHERE promotion_target_id='7f300100-0000-4000-8000-000000000024';
SELECT app_private.expire_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,
 '7f300100-0000-4000-8000-000000000031',g.generation_id)
FROM fixture_0130_expiry_context c CROSS JOIN fixture_0130_expiry_generations g WHERE g.label='old';

CREATE TABLE public.fixture_0130_expiry_legacy_functions AS
SELECT p.oid,p.oid::regprocedure::text AS signature,to_jsonb(p) AS catalog_row
FROM pg_catalog.pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0130_expiry_legacy_relations AS
SELECT n.nspname,c.relname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r';
CREATE FUNCTION public.fixture_0130_expiry_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
 SELECT jsonb_agg(to_jsonb(p) ORDER BY p.oid) FROM pg_catalog.pg_proc p JOIN public.fixture_0130_expiry_legacy_functions old ON old.oid=p.oid
$function$;
CREATE FUNCTION public.fixture_0130_expiry_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
 FOR relation IN SELECT * FROM public.fixture_0130_expiry_legacy_relations ORDER BY nspname,relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
  state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
 END LOOP;
 RETURN state;
END $function$;
CREATE TABLE public.fixture_0130_expiry_state AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
 (SELECT generation_id FROM fixture_0130_expiry_generations WHERE label='active') AS generation_id,
 (SELECT generation_id FROM fixture_0130_expiry_generations WHERE label='old') AS old_generation_id,
 (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
 public.fixture_0130_expiry_function_catalog() AS function_catalog,
 public.fixture_0130_expiry_business_state() AS business_state
FROM fixture_0130_expiry_context c;
DO $baseline$
BEGIN
 IF (SELECT count(*) FROM public.fixture_0130_expiry_state)<>1
  OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0130_personal_merge_contact_resolution_confirmation'
  OR to_regprocedure('app_private.dispatch_assigned_personal_target_expiry_v1(uuid,uuid,uuid,uuid)') IS NOT NULL
  OR to_regclass('app_private.personal_target_expiry_dispatch_requests_v1') IS NOT NULL
  OR (SELECT count(*) FROM public.fixture_0130_expiry_legacy_functions)<>jsonb_array_length(public.fixture_0130_expiry_function_catalog())
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE request_id='7f300100-0000-4000-8000-000000000031'
    AND operation='personal_target_known_source_merge_expire' AND reason='retention_expired')
 THEN RAISE EXCEPTION '0130→0131 frozen live upgrade baseline drift'; END IF;
END $baseline$;

CREATE FUNCTION public.fixture_0130_expiry_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0130_expiry_state%ROWTYPE; before_dispatch jsonb; first_result jsonb; replay_result jsonb; receipts jsonb;
BEGIN
 SELECT * INTO STRICT saved FROM public.fixture_0130_expiry_state;
 IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
  OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0131_personal_target_expiry_dispatch'
  OR public.fixture_0130_expiry_business_state() IS DISTINCT FROM saved.business_state
  OR public.fixture_0130_expiry_function_catalog() IS DISTINCT FROM saved.function_catalog
  OR (SELECT count(*) FROM public.fixture_0130_expiry_legacy_functions)<>jsonb_array_length(public.fixture_0130_expiry_function_catalog())
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=saved.old_generation_id
   AND request_id='7f300100-0000-4000-8000-000000000031' AND operation='personal_target_known_source_merge_expire')
 THEN RAISE EXCEPTION '0131 upgrade changed legacy function OID/body/ACL, prior expiry receipt, or business data'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.unit_kind,r.unit_id),'[]'::jsonb) INTO first_result
 FROM app_private.dispatch_assigned_personal_target_expiry_v1(saved.app_user_id,saved.workspace_id,saved.project_id,'7f300100-0000-4000-8000-000000000032') r;
 before_dispatch := public.fixture_0130_expiry_business_state();
 SELECT jsonb_build_object('request',to_jsonb(receipt),'units',(SELECT jsonb_agg(to_jsonb(unit) ORDER BY unit.unit_ordinal)
   FROM app_private.personal_target_expiry_dispatch_units_v1 unit WHERE unit.actor_app_user_id=saved.app_user_id AND unit.request_id=receipt.request_id))
 INTO receipts FROM app_private.personal_target_expiry_dispatch_requests_v1 receipt
 WHERE receipt.actor_app_user_id=saved.app_user_id AND receipt.request_id='7f300100-0000-4000-8000-000000000032';
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.unit_kind,r.unit_id),'[]'::jsonb) INTO replay_result
 FROM app_private.dispatch_assigned_personal_target_expiry_v1(saved.app_user_id,saved.workspace_id,saved.project_id,'7f300100-0000-4000-8000-000000000032') r;
 IF jsonb_array_length(first_result)<>2 OR first_result IS DISTINCT FROM replay_result
  OR receipts IS DISTINCT FROM (SELECT jsonb_build_object('request',to_jsonb(receipt),'units',(SELECT jsonb_agg(to_jsonb(unit) ORDER BY unit.unit_ordinal)
    FROM app_private.personal_target_expiry_dispatch_units_v1 unit WHERE unit.actor_app_user_id=saved.app_user_id AND unit.request_id=receipt.request_id))
    FROM app_private.personal_target_expiry_dispatch_requests_v1 receipt
    WHERE receipt.actor_app_user_id=saved.app_user_id AND receipt.request_id='7f300100-0000-4000-8000-000000000032')
  OR public.fixture_0130_expiry_business_state() IS DISTINCT FROM before_dispatch
  OR public.fixture_0130_expiry_function_catalog() IS DISTINCT FROM saved.function_catalog
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=saved.generation_id
   AND request_id=(SELECT child_request_id FROM app_private.personal_target_expiry_dispatch_units_v1 WHERE request_id='7f300100-0000-4000-8000-000000000032' AND generation_id=saved.generation_id)
   AND operation='personal_target_known_source_merge_expire' AND outcome='ended')
  OR (SELECT outcome FROM app_private.personal_target_expiry_dispatch_units_v1 WHERE request_id='7f300100-0000-4000-8000-000000000032'
   AND generation_id IS NULL AND promotion_target_id='7f300100-0000-4000-8000-000000000025') IS DISTINCT FROM 'expired'
 THEN RAISE EXCEPTION '0131 upgraded batch, pair/ordinary expiry or exact replay drift'; END IF;
END $function$;
COMMIT;
