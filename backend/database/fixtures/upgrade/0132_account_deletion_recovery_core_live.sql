\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TABLE public.fixture_0132_account_context AS
SELECT 'active'::text AS fixture_status, c.*
FROM app_data.bootstrap_personal_context('https://0132-account-upgrade.example.test', 'active') c
UNION ALL
SELECT 'deleted'::text, c.*
FROM app_data.bootstrap_personal_context('https://0132-account-upgrade.example.test', 'deleted') c;
UPDATE app_data.app_users SET status = 'deleted'
WHERE app_user_id = (SELECT app_user_id FROM public.fixture_0132_account_context WHERE fixture_status = 'deleted');

CREATE TABLE public.fixture_0132_account_legacy_relations AS
SELECT c.oid, n.nspname, c.relname, c.relowner, c.relacl,
  (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
    WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columns
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r';
CREATE TABLE public.fixture_0132_account_legacy_functions AS
SELECT p.oid, to_jsonb(p) AS catalog_row, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace);

CREATE FUNCTION public.fixture_0132_account_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0132_account_legacy_relations ORDER BY nspname, relname LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text), ''[]''::jsonb) FROM %I.%I r',
      relation.nspname, relation.relname) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE FUNCTION public.fixture_0132_account_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(p), 'definition', pg_get_functiondef(p.oid)) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0132_account_legacy_functions old ON old.oid = p.oid
$function$;
CREATE FUNCTION public.fixture_0132_account_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid', c.oid, 'schema', n.nspname, 'name', c.relname,
    'owner', c.relowner, 'acl', c.relacl, 'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped)) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN public.fixture_0132_account_legacy_relations old ON old.oid = c.oid
$function$;
CREATE FUNCTION public.fixture_0132_account_receipt_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
BEGIN
  RETURN jsonb_build_object(
    'current', (SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_private.account_deletion_current r),
    'requests', (SELECT jsonb_agg(to_jsonb(r) ORDER BY request_id) FROM app_private.account_deletion_request_claims r),
    'restores', (SELECT jsonb_agg(to_jsonb(r) ORDER BY request_id) FROM app_private.account_deletion_restore_claims r),
    'audit', (SELECT jsonb_agg(to_jsonb(r) ORDER BY audit_event_id) FROM app_private.account_deletion_audit_events r));
END $function$;
CREATE TABLE public.fixture_0132_account_state AS
SELECT public.fixture_0132_account_business_state() AS business_state,
  public.fixture_0132_account_function_catalog() AS function_catalog,
  public.fixture_0132_account_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;

DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) <> '0132_personal_merge_contact_resolution_isolation'
    OR (SELECT count(*) FROM public.fixture_0132_account_context) <> 2
    OR (SELECT count(*) FROM public.fixture_0132_account_legacy_functions)
      <> jsonb_array_length(public.fixture_0132_account_function_catalog())
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1)
    OR EXISTS (SELECT 1 FROM app_data.app_users WHERE status = 'deletion_pending')
    OR to_regclass('app_private.account_deletion_current') IS NOT NULL
    OR to_regprocedure('app_private.request_account_deletion_v1(uuid,uuid)') IS NOT NULL
  THEN RAISE EXCEPTION '0132 account deletion live baseline lacks historical data or has lifecycle state'; END IF;
END $baseline$;

CREATE FUNCTION public.fixture_0132_account_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0132_account_state%ROWTYPE; actor uuid;
  requested jsonb; restored jsonb; replayed jsonb; receipt_state jsonb;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0132_account_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
    OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0133_account_deletion_recovery_core'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version <> '0133_account_deletion_recovery_core') IS DISTINCT FROM saved.migrations
    OR public.fixture_0132_account_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0132_account_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0132_account_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM public.fixture_0132_account_legacy_functions)
      <> jsonb_array_length(public.fixture_0132_account_function_catalog())
    OR (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace)
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0132_account_legacy_functions old WHERE old.oid = p.oid)) <> 3
    OR (SELECT array_agg(c.relname::text ORDER BY c.relname) FROM pg_class c
      WHERE c.relnamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace) AND c.relkind = 'r'
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0132_account_legacy_relations old WHERE old.oid = c.oid))
      IS DISTINCT FROM ARRAY['account_deletion_audit_events', 'account_deletion_current',
        'account_deletion_request_claims', 'account_deletion_restore_claims']::text[]
    OR EXISTS (SELECT 1 FROM app_private.account_deletion_current)
    OR EXISTS (SELECT 1 FROM app_private.account_deletion_request_claims)
    OR EXISTS (SELECT 1 FROM app_private.account_deletion_restore_claims)
    OR EXISTS (SELECT 1 FROM app_private.account_deletion_audit_events)
  THEN RAISE EXCEPTION '0133 changed old rows, function identity, owner, ACL, definition or table metadata'; END IF;

  SELECT app_user_id INTO STRICT actor FROM public.fixture_0132_account_context WHERE fixture_status = 'active';
  SELECT to_jsonb(r) INTO STRICT requested FROM app_private.request_account_deletion_v1(actor, '7f320100-0000-4000-8000-000000000001') r;
  receipt_state := public.fixture_0132_account_receipt_state();
  SELECT to_jsonb(r) INTO STRICT replayed FROM app_private.request_account_deletion_v1(actor, '7f320100-0000-4000-8000-000000000001') r;
  IF requested IS DISTINCT FROM replayed
    OR public.fixture_0132_account_receipt_state() IS DISTINCT FROM receipt_state
    OR requested->>'account_deletion_contract_id' IS DISTINCT FROM 'account-deletion-request:v1'
    OR requested->>'deletion_request_id' IS DISTINCT FROM '7f320100-0000-4000-8000-000000000001'
    OR (requested->>'purge_after_utc')::timestamptz - (requested->>'effective_at_utc')::timestamptz <> interval '720 hours'
    OR (SELECT status FROM app_data.app_users WHERE app_user_id = actor) IS DISTINCT FROM 'deletion_pending'
    OR (SELECT count(*) FROM app_private.account_deletion_audit_events) <> 1
    OR (public.fixture_0132_account_business_state() - 'app_data.app_users')
      IS DISTINCT FROM (saved.business_state - 'app_data.app_users')
  THEN RAISE EXCEPTION '0133 upgraded request, exact replay, 720-hour window or retained facts drift'; END IF;

  SELECT to_jsonb(r) INTO STRICT restored FROM app_private.restore_account_v1(actor,
    '7f320100-0000-4000-8000-000000000002', '7f320100-0000-4000-8000-000000000001') r;
  receipt_state := public.fixture_0132_account_receipt_state();
  SELECT to_jsonb(r) INTO STRICT replayed FROM app_private.restore_account_v1(actor,
    '7f320100-0000-4000-8000-000000000002', '7f320100-0000-4000-8000-000000000001') r;
  IF restored IS DISTINCT FROM replayed
    OR restored->>'account_deletion_restore_contract_id' IS DISTINCT FROM 'account-deletion-restore:v1'
    OR restored->>'deletion_request_id' IS DISTINCT FROM requested->>'deletion_request_id'
    OR (SELECT status FROM app_data.app_users WHERE app_user_id = actor) IS DISTINCT FROM 'active'
    OR (SELECT count(*) FROM app_private.account_deletion_audit_events) <> 2
    OR public.fixture_0132_account_receipt_state() IS DISTINCT FROM receipt_state
    OR public.fixture_0132_account_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0132_account_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0132_account_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0133 upgraded restore, exact receipt replay or old business facts drift'; END IF;
END $function$;
COMMIT;
