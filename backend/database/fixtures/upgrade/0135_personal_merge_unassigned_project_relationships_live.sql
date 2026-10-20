\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SELECT receipt.* FROM public.fixture_0134_unlink_context actor CROSS JOIN LATERAL
  app_private.unlink_due_account_history_contributions_v1(actor.app_user_id, '7f340100-0000-4000-8000-000000000030') receipt
WHERE actor.label = 'actor';
CREATE TABLE public.fixture_0135_project_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0135-project-upgrade.example.test', 'owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0135-project-upgrade.example.test', 'owner') WHERE is_current;
CREATE TABLE public.fixture_0135_project_targets AS
SELECT choice.ordinal, (created.target->>'target_id')::uuid AS target_id
FROM public.fixture_0135_project_context c CROSS JOIN (VALUES (1), (2)) choice(ordinal)
CROSS JOIN LATERAL app_data.create_promotion_target(c.app_user_id, c.workspace_id, c.project_id, 'person',
  '0135 retained target ' || choice.ordinal, '+1 312 555 0135', '0135-private@example.test',
  '0135-upgrade-target-' || choice.ordinal) created;
CREATE TABLE public.fixture_0135_project_generation AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id, c.project_id,
  '7f350100-0000-4000-8000-000000000001', preview.preview_id, first.target_id, second.target_id,
  first.target_id, second.target_id) AS generation_id
FROM public.fixture_0135_project_context c
JOIN public.fixture_0135_project_targets first ON first.ordinal = 1
JOIN public.fixture_0135_project_targets second ON second.ordinal = 2
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0135-project-upgrade.example.test',
  'owner', c.project_id, first.target_id, second.target_id) preview;

CREATE TABLE public.fixture_0135_project_legacy_relations AS
SELECT c.oid, n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r';
CREATE TABLE public.fixture_0135_project_legacy_functions AS
SELECT p.oid FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace);
CREATE TABLE public.fixture_0135_project_legacy_triggers AS
SELECT t.oid FROM pg_trigger t JOIN public.fixture_0135_project_legacy_relations r ON r.oid = t.tgrelid;
CREATE FUNCTION public.fixture_0135_project_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(p), 'definition', pg_get_functiondef(p.oid)) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0135_project_legacy_functions old ON old.oid = p.oid
$function$;
CREATE FUNCTION public.fixture_0135_project_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid', c.oid, 'schema', n.nspname, 'name', c.relname,
    'owner', c.relowner, 'acl', c.relacl, 'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), 'constraints',
    (SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(k), 'definition', pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid = c.oid), 'old_triggers',
    (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t
      JOIN public.fixture_0135_project_legacy_triggers old ON old.oid = t.oid WHERE t.tgrelid = c.oid)) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN public.fixture_0135_project_legacy_relations old ON old.oid = c.oid
$function$;
CREATE FUNCTION public.fixture_0135_project_business_state(allow_pair_expiry boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb; predicate text;
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0135_project_legacy_relations ORDER BY nspname, relname LOOP
    predicate := 'true';
    IF allow_pair_expiry THEN
      IF relation.nspname = 'app_data' AND relation.relname IN (
        'promotion_targets', 'promotion_target_assignments', 'promotion_target_retention_events') THEN
        predicate := 'r.promotion_target_id NOT IN (SELECT target_id FROM public.fixture_0135_project_targets)';
      ELSIF relation.nspname = 'app_private' AND relation.relname IN (
        'personal_target_merge_active_members_v1', 'personal_target_merge_end_events_v1') THEN
        predicate := 'r.generation_id NOT IN (SELECT generation_id FROM public.fixture_0135_project_generation)';
      END IF;
    END IF;
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text), ''[]''::jsonb) FROM %I.%I r WHERE %s',
      relation.nspname, relation.relname, predicate) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE FUNCTION public.fixture_0135_project_pending_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
BEGIN
  RETURN jsonb_build_object(
    'requests', (SELECT jsonb_agg(to_jsonb(r) ORDER BY pending_fact_id) FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 r),
    'payloads', (SELECT jsonb_agg(to_jsonb(r) ORDER BY pending_fact_id) FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 r),
    'purges', (SELECT jsonb_agg(to_jsonb(r) ORDER BY pending_fact_id) FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 r));
END $function$;
CREATE TABLE public.fixture_0135_project_state AS
SELECT c.app_user_id, c.workspace_id, c.project_id, g.generation_id,
  app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id, c.workspace_id, c.project_id, g.generation_id) AS known_plan,
  public.fixture_0135_project_business_state() AS business_state,
  public.fixture_0135_project_function_catalog() AS function_catalog,
  public.fixture_0135_project_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count
FROM public.fixture_0135_project_context c CROSS JOIN public.fixture_0135_project_generation g;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) <> '0135_account_history_contribution_unlink'
    OR (SELECT count(*) FROM public.fixture_0135_project_state) <> 1
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1
      WHERE generation_id = (SELECT generation_id FROM public.fixture_0135_project_generation)) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE reason = 'retention_expired')
    OR NOT EXISTS (SELECT 1 FROM app_private.account_deletion_request_claims)
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_historical_contact_copies_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1)
    OR to_regclass('app_private.personal_merge_unassigned_project_relationship_requests_v1') IS NOT NULL
  THEN RAISE EXCEPTION '0135 live pending project upgrade lacks active pair or historical receipts'; END IF;
END $baseline$;

CREATE FUNCTION public.fixture_0135_project_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0135_project_state%ROWTYPE; first_result jsonb; replayed jsonb; document jsonb;
  before_pending jsonb; before_old jsonb; preserved_old jsonb; targets_before jsonb; assignments_before jsonb;
  actual_state text; actual_message text; expired_at timestamptz; expiration_replay timestamptz;
  fence constant text := 'app_private.personal_target_merge_generation_fence_v1';
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0135_project_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
    OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0136_personal_merge_unassigned_project_relationships'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version <> '0136_personal_merge_unassigned_project_relationships') IS DISTINCT FROM saved.migrations
    OR public.fixture_0135_project_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0135_project_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0135_project_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM public.fixture_0135_project_legacy_functions) <> jsonb_array_length(public.fixture_0135_project_function_catalog())
    OR (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace)
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0135_project_legacy_functions old WHERE old.oid = p.oid)) <> 5
    OR (SELECT array_agg(n.nspname || '.' || c.relname ORDER BY n.nspname, c.relname)
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r'
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0135_project_legacy_relations old WHERE old.oid = c.oid))
      IS DISTINCT FROM ARRAY['app_data.personal_merge_unassigned_project_relationship_facts_v1',
        'app_private.personal_merge_unassigned_project_relationship_purges_v1',
        'app_private.personal_merge_unassigned_project_relationship_requests_v1']::text[]
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_requests_v1)
    OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1)
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_purges_v1)
  THEN RAISE EXCEPTION '0136 migration changed old facts, bindings, OID/owner/ACL, definitions, constraints or old triggers'; END IF;

  SELECT to_jsonb(r) INTO STRICT first_result FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
    saved.app_user_id, saved.workspace_id, saved.project_id, '7f350100-0000-4000-8000-000000000002', saved.generation_id,
    3, 'paused', '0136 private pending note', 'other', '0136 private pending reason') r;
  before_pending := public.fixture_0135_project_pending_state();
  SELECT to_jsonb(r) INTO STRICT replayed FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
    saved.app_user_id, saved.workspace_id, saved.project_id, '7f350100-0000-4000-8000-000000000002', saved.generation_id,
    3, 'paused', '0136 private pending note', 'other', '0136 private pending reason') r;
  IF first_result IS DISTINCT FROM replayed OR public.fixture_0135_project_pending_state() IS DISTINCT FROM before_pending
    OR first_result->>'unassigned_project_relationship_contract_id' IS DISTINCT FROM 'personal-merge-unassigned-project-relationship:v1'
    OR NOT isfinite((first_result->>'staged_at_utc')::timestamptz)
    OR (public.fixture_0135_project_business_state() - fence) IS DISTINCT FROM (saved.business_state - fence)
  THEN RAISE EXCEPTION '0136 stage/replay changed old facts or its exact pending receipt'; END IF;
  PERFORM * FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
    saved.app_user_id, saved.workspace_id, saved.project_id, '7f350100-0000-4000-8000-000000000003', saved.generation_id,
    3, 'paused', '0136 private pending note', 'other', '0136 private pending reason');
  before_pending := public.fixture_0135_project_pending_state();
  before_old := public.fixture_0135_project_business_state();
  document := app_private.read_personal_merge_unassigned_project_relationship_plan_v1(
    saved.app_user_id, saved.workspace_id, saved.project_id, saved.generation_id);
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(document) key)
      IS DISTINCT FROM ARRAY['known_source_plan','pending_count','pending_fingerprint','pending_project_relationships']::text[]
    OR document->'known_source_plan' IS DISTINCT FROM saved.known_plan
    OR document->>'pending_count' IS DISTINCT FROM '2'
    OR jsonb_array_length(document->'pending_project_relationships') <> 2
    OR document->>'pending_fingerprint' IS DISTINCT FROM encode(sha256(convert_to((document->'pending_project_relationships')::text, 'UTF8')), 'hex')
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(document->'pending_project_relationships') item
      WHERE (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(item) key)
        IS DISTINCT FROM ARRAY['pending_fact_id','project_id','staged_at_utc','target_type']::text[]
        OR item->>'project_id' IS DISTINCT FROM saved.project_id::text OR item->>'target_type' IS DISTINCT FROM 'person'
        OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 r
          WHERE r.pending_fact_id = (item->>'pending_fact_id')::uuid
            AND r.staged_at_utc = (item->>'staged_at_utc')::timestamptz AND r.generation_id = saved.generation_id))
    OR (SELECT count(*) FROM app_data.personal_merge_unassigned_project_relationship_facts_v1
      WHERE new_stage = 3 AND new_lifecycle_status = 'paused' AND follow_up_note = '0136 private pending note'
        AND reason_code = 'other' AND reason_detail = '0136 private pending reason') <> 2
    OR public.fixture_0135_project_pending_state() IS DISTINCT FROM before_pending
    OR public.fixture_0135_project_business_state() IS DISTINCT FROM before_old
  THEN RAISE EXCEPTION '0136 metadata read leaked payload, lost duplicate facts, changed its fingerprint or wrote data'; END IF;

  BEGIN
    PERFORM app_private.end_known_source_personal_target_merge_generation_v1(saved.app_user_id, saved.workspace_id,
      saved.project_id, '7f350100-0000-4000-8000-000000000004', saved.generation_id, saved.known_plan->>'fact_fingerprint');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM '55000' OR actual_message IS DISTINCT FROM 'unassigned project relationship facts prevent known-source split'
    OR public.fixture_0135_project_pending_state() IS DISTINCT FROM before_pending
    OR public.fixture_0135_project_business_state() IS DISTINCT FROM before_old
  THEN RAISE EXCEPTION '0136 pending relationship facts did not reject the old split atomically'; END IF;

  preserved_old := public.fixture_0135_project_business_state(true) - fence;
  UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
  WHERE promotion_target_id IN (SELECT target_id FROM public.fixture_0135_project_targets WHERE ordinal = 1);
  SELECT jsonb_agg(to_jsonb(t) ORDER BY promotion_target_id) INTO targets_before FROM app_data.promotion_targets t
  WHERE promotion_target_id IN (SELECT target_id FROM public.fixture_0135_project_targets);
  SELECT jsonb_agg(to_jsonb(a) ORDER BY assignment_id) INTO assignments_before FROM app_data.promotion_target_assignments a
  WHERE promotion_target_id IN (SELECT target_id FROM public.fixture_0135_project_targets);
  expired_at := app_private.expire_known_source_personal_target_merge_generation_v1(saved.app_user_id, saved.workspace_id,
    saved.project_id, '7f350100-0000-4000-8000-000000000005', saved.generation_id);
  IF EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1)
    OR (SELECT count(*) FROM app_private.personal_merge_unassigned_project_relationship_purges_v1
      WHERE generation_id = saved.generation_id AND purged_at_utc = expired_at) <> 2
    OR (public.fixture_0135_project_pending_state()->'requests') IS DISTINCT FROM before_pending->'requests'
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = saved.generation_id
      AND request_id = '7f350100-0000-4000-8000-000000000005' AND reason = 'retention_expired'
      AND operation = 'personal_target_known_source_merge_expire' AND outcome = 'ended' AND target_count = 2
      AND fact_fingerprint = saved.known_plan->>'fact_fingerprint' AND fact_count = (saved.known_plan->>'fact_count')::bigint
      AND ended_at_utc = expired_at)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = saved.generation_id)
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(targets_before) old
      LEFT JOIN app_data.promotion_targets t ON t.promotion_target_id = (old->>'promotion_target_id')::uuid
      WHERE to_jsonb(t) - ARRAY['display_name','phone','email','status','anonymized_at','anonymization_reason','profile_revision']
        IS DISTINCT FROM old - ARRAY['display_name','phone','email','status','anonymized_at','anonymization_reason','profile_revision']
        OR t.status IS DISTINCT FROM 'anonymized' OR t.phone IS NOT NULL OR t.email IS NOT NULL
        OR t.profile_revision IS DISTINCT FROM (old->>'profile_revision')::bigint + 1
        OR t.anonymized_at IS DISTINCT FROM expired_at OR t.anonymization_reason IS DISTINCT FROM 'retention_expired')
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(assignments_before) old
      LEFT JOIN app_data.promotion_target_assignments a ON a.assignment_id = (old->>'assignment_id')::uuid
      WHERE to_jsonb(a) - ARRAY['ended_at','end_reason'] IS DISTINCT FROM old - ARRAY['ended_at','end_reason']
        OR a.ended_at IS DISTINCT FROM expired_at OR a.end_reason IS DISTINCT FROM 'target_anonymized')
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events
      WHERE promotion_target_id IN (SELECT target_id FROM public.fixture_0135_project_targets)
        AND event_type = 'anonymized' AND reason = 'retention_expired' AND occurred_at = expired_at) <> 2
    OR (public.fixture_0135_project_business_state(true) - fence) IS DISTINCT FROM preserved_old
    OR public.fixture_0135_project_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0135_project_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0136 expiry failed exact payload cleanup or changed unrelated old facts, bindings or metadata'; END IF;
  before_pending := public.fixture_0135_project_pending_state(); before_old := public.fixture_0135_project_business_state();
  expiration_replay := app_private.expire_known_source_personal_target_merge_generation_v1(saved.app_user_id, saved.workspace_id,
    saved.project_id, '7f350100-0000-4000-8000-000000000005', saved.generation_id);
  IF expiration_replay IS DISTINCT FROM expired_at OR public.fixture_0135_project_pending_state() IS DISTINCT FROM before_pending
    OR public.fixture_0135_project_business_state() IS DISTINCT FROM before_old
  THEN RAISE EXCEPTION '0136 expiry replay changed its original end or purge receipts'; END IF;
END $function$;
COMMIT;
