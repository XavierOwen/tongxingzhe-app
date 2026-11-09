\set ON_ERROR_STOP on

BEGIN;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)
    IS DISTINCT FROM '0144_personal_merge_unassigned_contact_confirmation_isolation'
  THEN RAISE EXCEPTION 'Known-source terminal isolation upgrade requires the real 0144 baseline'; END IF;
END
$baseline$;

CREATE TEMP TABLE fixture_0144_known_source_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://0144-upgrade-known-source-isolation.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0144-upgrade-known-source-isolation.example.test','owner'
) WHERE is_current;

CREATE TEMP TABLE fixture_0144_known_source_pairs ON COMMIT DROP AS
SELECT * FROM (VALUES
  ('end','7f458000-0000-4000-8000-000000000001'::uuid,'7f458000-0000-4000-8000-000000000002'::uuid,
    '7f458000-0000-4000-8000-000000000031'::uuid),
  ('expiry','7f458000-0000-4000-8000-000000000003'::uuid,'7f458000-0000-4000-8000-000000000004'::uuid,
    '7f458000-0000-4000-8000-000000000032'::uuid)
) p(kind,first_target,second_target,request_id);

INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,'person','0144 upgrade original source','+1 773 555 0145','0144@example.test',c.app_user_id
FROM fixture_0144_known_source_context c CROSS JOIN fixture_0144_known_source_pairs p
CROSS JOIN LATERAL unnest(ARRAY[p.first_target,p.second_target]) t(target_id);

INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0144_known_source_context c WHERE t.workspace_id=c.workspace_id;

CREATE TEMP TABLE fixture_0144_known_source_generations ON COMMIT DROP AS
SELECT p.*,c.app_user_id,c.workspace_id,c.project_id,
  app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,gen_random_uuid(),preview.preview_id,p.first_target,p.first_target,p.second_target,p.first_target
  ) AS generation_id
FROM fixture_0144_known_source_context c CROSS JOIN fixture_0144_known_source_pairs p
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0144-upgrade-known-source-isolation.example.test','owner',c.project_id,p.first_target,p.second_target
) preview;

UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months'
WHERE promotion_target_id=(SELECT first_target FROM fixture_0144_known_source_pairs WHERE kind='expiry');

DO $due$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0144_known_source_generations g
    WHERE kind='expiry'
      AND app_data.promotion_target_review_due_at(first_target) < clock_timestamp()
      AND app_data.promotion_target_review_due_at(second_target) > clock_timestamp())
  THEN RAISE EXCEPTION '0144 upgrade requires exactly one due expiry member'; END IF;
END
$due$;

CREATE TABLE public.fixture_0144_known_source_isolation_receipts AS
SELECT g.*,m.fact_fingerprint,
  CASE WHEN g.kind='end' THEN app_private.end_known_source_personal_target_merge_generation_v1(
    g.app_user_id,g.workspace_id,g.project_id,g.request_id,g.generation_id,m.fact_fingerprint
  ) ELSE app_private.expire_known_source_personal_target_merge_generation_v1(
    g.app_user_id,g.workspace_id,g.project_id,g.request_id,g.generation_id
  ) END AS ended_at_utc
FROM fixture_0144_known_source_generations g
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(g.generation_id) m;

DO $receipts$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0144_known_source_isolation_receipts)<>2
    OR (SELECT count(*) FROM public.fixture_0144_known_source_isolation_receipts r
      JOIN app_private.personal_target_merge_end_events_v1 e
        USING (generation_id,workspace_id,project_id,request_id,fact_fingerprint,ended_at_utc)
      WHERE e.actor_app_user_id=r.app_user_id AND e.outcome='ended' AND e.target_count=2
        AND ((r.kind='end' AND e.operation='personal_target_known_source_merge_end' AND e.reason='known_source_split')
          OR (r.kind='expiry' AND e.operation='personal_target_known_source_merge_expire' AND e.reason='retention_expired')))<>2
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1
      JOIN public.fixture_0144_known_source_isolation_receipts USING (generation_id))
    OR (SELECT count(*) FROM app_data.promotion_targets t CROSS JOIN public.fixture_0144_known_source_isolation_receipts r
      WHERE r.kind='expiry' AND t.promotion_target_id IN (r.first_target,r.second_target)
        AND t.status='anonymized' AND t.display_name='已匿名化对象' AND t.phone IS NULL AND t.email IS NULL
        AND t.anonymized_at=r.ended_at_utc AND t.anonymization_reason='retention_expired')<>2
  THEN RAISE EXCEPTION '0144 upgrade did not create both terminal receipts and anonymize both expiry members'; END IF;
END
$receipts$;

CREATE FUNCTION public.fixture_0144_known_source_isolation_business_state()
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

CREATE TABLE public.fixture_0144_known_source_isolation_catalog AS
SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);

CREATE TABLE public.fixture_0144_known_source_isolation_snapshot AS
SELECT public.fixture_0144_known_source_isolation_business_state() AS business_state,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
COMMIT;

CREATE FUNCTION public.fixture_0144_known_source_isolation_assert_upgrade()
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
  saved public.fixture_0144_known_source_isolation_snapshot%ROWTYPE;
  receipt public.fixture_0144_known_source_isolation_receipts%ROWTYPE;
  target record;
  result timestamptz;
  old_source text;
  actual_source text;
  guard text;
  guard_start integer;
  authorization_start integer;
  end_oid oid := 'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure;
  expiry_oid oid := 'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0144_known_source_isolation_snapshot;
  IF current_setting('transaction_isolation')<>'read committed' OR current_setting('transaction_read_only')<>'on'
  THEN RAISE EXCEPTION '0145 receipt replay verification requires read-only read committed'; END IF;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0145_personal_target_known_source_terminal_isolation'
    OR public.fixture_0144_known_source_isolation_business_state() IS DISTINCT FROM saved.business_state
    OR EXISTS (
      SELECT 1 FROM public.fixture_0144_known_source_isolation_catalog frozen
      FULL JOIN (
        SELECT p.oid,to_jsonb(p) AS catalog_row FROM pg_catalog.pg_proc p
        WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace)
      ) live USING (oid)
      WHERE CASE WHEN oid IN (end_oid,expiry_oid)
        THEN (live.catalog_row-'prosrc') IS DISTINCT FROM (frozen.catalog_row-'prosrc')
        ELSE live.catalog_row IS DISTINCT FROM frozen.catalog_row
      END
    )
  THEN RAISE EXCEPTION '0144→0145 changed legacy data or function catalog'; END IF;

  FOR target IN SELECT * FROM (VALUES (end_oid,'end'),(expiry_oid,'expiry')) t(function_oid,kind) LOOP
    SELECT catalog_row->>'prosrc' INTO STRICT old_source
    FROM public.fixture_0144_known_source_isolation_catalog WHERE oid=target.function_oid;
    SELECT prosrc INTO STRICT actual_source FROM pg_catalog.pg_proc WHERE oid=target.function_oid;
    guard := format($guard$  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000', MESSAGE = 'known-source personal target merge %s requires read committed';
  END IF;
$guard$,target.kind);
    authorization_start := strpos(old_source,'  IF NOT app_data.promotion_target_context_authorized(');
    guard_start := strpos(actual_source,guard);
    IF authorization_start=0 OR guard_start<>authorization_start
      OR replace(actual_source,guard,'') IS DISTINCT FROM old_source
      OR length(actual_source)<>length(old_source)+length(guard)
    THEN RAISE EXCEPTION '0144→0145 changed known-source % beyond the exact three-line guard',target.kind; END IF;
  END LOOP;

  FOR receipt IN SELECT * FROM public.fixture_0144_known_source_isolation_receipts ORDER BY kind LOOP
    IF receipt.kind='end' THEN
      result := app_private.end_known_source_personal_target_merge_generation_v1(
        receipt.app_user_id,receipt.workspace_id,receipt.project_id,receipt.request_id,receipt.generation_id,receipt.fact_fingerprint
      );
    ELSE
      result := app_private.expire_known_source_personal_target_merge_generation_v1(
        receipt.app_user_id,receipt.workspace_id,receipt.project_id,receipt.request_id,receipt.generation_id
      );
    END IF;
    IF result IS DISTINCT FROM receipt.ended_at_utc
    THEN RAISE EXCEPTION '0145 RC known-source % replay changed its original receipt',receipt.kind; END IF;
  END LOOP;
  IF public.fixture_0144_known_source_isolation_business_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0145 RC terminal receipt replay changed business data'; END IF;
END
$function$;
