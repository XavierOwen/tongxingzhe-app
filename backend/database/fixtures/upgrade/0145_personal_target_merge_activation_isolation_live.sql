\set ON_ERROR_STOP on

BEGIN ISOLATION LEVEL READ COMMITTED;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0145_personal_target_known_source_terminal_isolation'
  THEN RAISE EXCEPTION 'Activation isolation upgrade requires the real 0145 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0145_activation_context ON COMMIT DROP AS
SELECT c.*,
  '7f468000-0000-4000-8000-000000000001'::uuid AS first_target,
  '7f468000-0000-4000-8000-000000000002'::uuid AS second_target,
  '7f468000-0000-4000-8000-000000000031'::uuid AS request_id
FROM app_data.bootstrap_personal_context('https://0145-upgrade-activation-isolation.example.test','owner') c;
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0145-upgrade-activation-isolation.example.test','owner'
) WHERE is_current;

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0145 upgrade original source','+1 773 555 0146','0145@example.test',c.app_user_id
FROM fixture_0145_activation_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.target_id,t.target_id,c.app_user_id,c.app_user_id
FROM fixture_0145_activation_context c
CROSS JOIN LATERAL unnest(ARRAY[c.first_target,c.second_target]) t(target_id);

CREATE TABLE public.fixture_0145_activation_isolation_receipt AS
SELECT c.app_user_id,c.workspace_id,c.project_id,c.request_id,c.first_target,c.second_target,preview.preview_id,
  app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,c.request_id,preview.preview_id,c.first_target,c.first_target,c.second_target,c.first_target
  ) AS generation_id
FROM fixture_0145_activation_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0145-upgrade-activation-isolation.example.test','owner',c.project_id,c.first_target,c.second_target
) preview;

DO $receipt$
DECLARE
  receipt public.fixture_0145_activation_isolation_receipt%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM public.fixture_0145_activation_isolation_receipt;
  IF NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1 r
    JOIN app_private.personal_target_merge_activation_audit_v1 a USING (actor_app_user_id,workspace_id,request_id)
    JOIN app_private.personal_target_merge_generations_v1 g USING (generation_id,workspace_id,activated_at_utc)
    WHERE r.actor_app_user_id=receipt.app_user_id AND r.workspace_id=receipt.workspace_id
      AND r.request_id=receipt.request_id AND r.preview_id=receipt.preview_id AND r.generation_id=receipt.generation_id
      AND r.retained_target_id=receipt.first_target AND r.display_name_source_target_id=receipt.first_target
      AND r.phone_source_target_id=receipt.second_target AND r.email_source_target_id=receipt.first_target
      AND a.operation='personal_target_merge_activation' AND a.outcome='activated' AND a.target_count=2
      AND a.occurred_at_utc=r.activated_at_utc AND g.created_by_app_user_id=receipt.app_user_id
  ) OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1 m
    JOIN app_data.promotion_targets t USING (promotion_target_id,workspace_id,target_type)
    JOIN app_data.promotion_target_assignments a USING (promotion_target_id)
    WHERE m.generation_id=receipt.generation_id AND m.workspace_id=receipt.workspace_id
      AND m.promotion_target_id IN (receipt.first_target,receipt.second_target)
      AND t.status='active' AND a.app_user_id=receipt.app_user_id AND a.ended_at IS NULL)<>2
  THEN RAISE EXCEPTION '0145 upgrade did not create the original activation receipt, audit and two active assigned members'; END IF;
END
$receipt$;

CREATE FUNCTION public.fixture_0145_activation_isolation_business_state()
RETURNS jsonb LANGUAGE plpgsql SET timezone='UTC' AS $function$
DECLARE
  statements text;
  result jsonb;
BEGIN
  SELECT string_agg(format(
    'SELECT %L::text AS relation_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text COLLATE "C"),''[]''::jsonb) AS contents FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)
  INTO statements FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');
  EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM ('||statements||') snapshots' INTO result;
  RETURN result;
END
$function$;

CREATE TABLE public.fixture_0145_activation_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);

CREATE TABLE public.fixture_0145_activation_isolation_snapshot AS
SELECT public.fixture_0145_activation_isolation_business_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0145_activation_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
  saved public.fixture_0145_activation_isolation_snapshot%ROWTYPE;
  receipt public.fixture_0145_activation_isolation_receipt%ROWTYPE;
  activation_oid oid := 'app_private.activate_personal_target_merge_generation_v2(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid)'::regprocedure;
  old_source text;
  actual_source text;
  authorization_start integer;
  guard CONSTANT text := $guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'personal target merge generation activation requires read committed';
  END IF;
$guard$;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0145_activation_isolation_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0146 activation replay verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0146_personal_target_merge_activation_isolation'
    OR public.fixture_0145_activation_isolation_business_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0145_activation_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid=activation_oid
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0145→0146 changed legacy data or function catalog'; END IF;

  SELECT catalog_row->>'prosrc' INTO STRICT old_source
  FROM public.fixture_0145_activation_isolation_catalog WHERE oid=activation_oid;
  SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=activation_oid;
  authorization_start := strpos(old_source,'  SELECT workspace_row.workspace_id INTO trusted_workspace_id');
  IF authorization_start=0 OR strpos(old_source,guard)<>0
    OR actual_source IS DISTINCT FROM overlay(old_source PLACING guard FROM authorization_start FOR 0)
  THEN RAISE EXCEPTION '0145→0146 changed v2 activation beyond the exact three-line guard before authorization'; END IF;

  SELECT * INTO STRICT receipt FROM public.fixture_0145_activation_isolation_receipt;
  IF app_private.activate_personal_target_merge_generation_v2(
    receipt.app_user_id,receipt.project_id,receipt.request_id,receipt.preview_id,
    receipt.first_target,receipt.first_target,receipt.second_target,receipt.first_target
  ) IS DISTINCT FROM receipt.generation_id
  THEN RAISE EXCEPTION '0146 RC activation replay changed its original generation'; END IF;
  IF public.fixture_0145_activation_isolation_business_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0146 RC activation replay changed business data'; END IF;
END
$function$;
