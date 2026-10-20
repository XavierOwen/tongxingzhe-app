\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TABLE public.fixture_0133_history_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0133-history-upgrade.example.test', 'owner');
CREATE TABLE public.fixture_0133_history_account_request AS
SELECT r.* FROM public.fixture_0133_history_context c CROSS JOIN LATERAL
  app_private.request_account_deletion_v1(c.app_user_id, '7f330100-0000-4000-8000-000000000001') r;
CREATE TABLE public.fixture_0133_history_account_restore AS
SELECT r.* FROM public.fixture_0133_history_context c CROSS JOIN LATERAL
  app_private.restore_account_v1(c.app_user_id, '7f330100-0000-4000-8000-000000000002',
    '7f330100-0000-4000-8000-000000000001') r;
CREATE TABLE public.fixture_0133_history_organization AS
SELECT r.* FROM public.fixture_0133_history_context c CROSS JOIN LATERAL
  app_private.create_organization_v1(c.app_user_id, '7f330100-0000-4000-8000-000000000003', '0133 retained contribution target') r;
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '7f330100-0000-4000-8000-000000000004', organization_workspace_id, '0133 contribution target'
FROM public.fixture_0133_history_organization;
CREATE TABLE public.fixture_0133_history_project_membership AS
SELECT r.* FROM public.fixture_0133_history_context c CROSS JOIN public.fixture_0133_history_organization o
CROSS JOIN LATERAL app_private.assign_organization_project_member_v1(c.app_user_id,
  '7f330100-0000-4000-8000-000000000005', o.organization_workspace_id,
  '7f330100-0000-4000-8000-000000000004', o.organization_membership_id) r;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id, question_id, position, prompt,
  question_type, is_required, allow_unknown, allow_refused, allow_not_applicable)
SELECT questionnaire_version_id, 'private_source_answer', 1, '0133 private source answer', 'boolean', false, true, true, true
FROM public.fixture_0133_history_context;
CREATE TABLE public.fixture_0133_history_submit AS
SELECT s.result_code FROM public.fixture_0133_history_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id, '0133-history-upgrade-submit', 1, 'contact.submit.v1', '0133-history-device', '0133-history-upgrade-source', 0,
  jsonb_build_object('contactId', '0133-history-upgrade-source', 'workspaceId', c.workspace_id,
    'projectId', c.project_id, 'questionnaireVersionId', c.questionnaire_version_id,
    'occurredAtUtc', '2025-03-09T07:30:00Z', 'occurredTimeZone', 'America/Chicago',
    'channel', 'instant_text', 'channelDetail', '0133 private channel detail',
    'location', jsonb_build_object('kind', 'not_applicable'), 'reachCount', 3, 'interestLevel', 4,
    'answers', jsonb_build_array(jsonb_build_object('questionId', 'private_source_answer',
      'state', 'answered', 'type', 'boolean', 'value', true)), 'targetLinks', '[]'::jsonb)) s;

CREATE TABLE public.fixture_0133_history_legacy_relations AS
SELECT c.oid, n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r';
CREATE TABLE public.fixture_0133_history_legacy_functions AS
SELECT p.oid, to_jsonb(p) AS catalog_row, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace);
CREATE TABLE public.fixture_0133_history_extensions(function_oid oid, label text PRIMARY KEY, fragment text);
INSERT INTO public.fixture_0133_history_extensions VALUES
('app_private.organization_purge_requests_v1(uuid)'::regprocedure, 'collector', $extension$
  UNION
  SELECT 14, 'personal-history-contribution-confirmation', 'personal-history-contribution-confirmation', request_id FROM app_private.personal_history_contribution_confirmations_v1
  WHERE target_project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id=requested_workspace_id)$extension$),
('app_private.finalize_organization_purge_v1(uuid,uuid)'::regprocedure, 'relations', $extension$    'app_private.personal_history_contribution_confirmations_v1',
    'app_private.personal_history_contribution_previews_v1',
    'app_private.organization_historical_contact_copies_v1',
$extension$),
('app_private.finalize_organization_purge_v1(uuid,uuid)'::regprocedure, 'scope', $extension$    't.target_project_id = ANY($2)',
    't.target_project_id = ANY($2)',
    't.target_project_id = ANY($2)',
$extension$),
('app_private.finalize_organization_purge_v1(uuid,uuid)'::regprocedure, 'provenance', $extension$  IF EXISTS (
    SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 confirmation
    LEFT JOIN app_private.personal_history_contribution_previews_v1 preview USING(preview_id)
    LEFT JOIN app_private.organization_historical_contact_copies_v1 copy USING(copy_id)
    WHERE (confirmation.target_project_id=ANY(project_ids)
      OR preview.target_project_id=ANY(project_ids) OR copy.target_project_id=ANY(project_ids))
      AND (confirmation.target_project_id IS DISTINCT FROM preview.target_project_id
        OR confirmation.target_project_id IS DISTINCT FROM copy.target_project_id
        OR confirmation.confirmed_at_utc IS DISTINCT FROM copy.confirmed_at_utc
        OR (confirmation.actor_app_user_id IS NOT NULL AND preview.actor_app_user_id IS NOT NULL
          AND confirmation.actor_app_user_id IS DISTINCT FROM preview.actor_app_user_id)
        OR (confirmation.source_contact_id IS NOT NULL AND preview.source_contact_id IS NOT NULL
          AND confirmation.source_contact_id IS DISTINCT FROM preview.source_contact_id))
  ) OR EXISTS (
    SELECT 1 FROM app_private.organization_historical_contact_copies_v1 copy
    WHERE copy.target_project_id=ANY(project_ids) AND NOT EXISTS (
      SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 confirmation
      WHERE confirmation.copy_id=copy.copy_id)
  ) OR EXISTS (
    SELECT 1 FROM (
      SELECT actor_app_user_id,source_contact_id FROM app_private.personal_history_contribution_previews_v1
      WHERE target_project_id=ANY(project_ids)
      UNION ALL
      SELECT actor_app_user_id,source_contact_id FROM app_private.personal_history_contribution_confirmations_v1
      WHERE target_project_id=ANY(project_ids)
    ) provenance
    JOIN app_data.contacts source ON source.contact_id=provenance.source_contact_id
    JOIN app_data.workspaces workspace ON workspace.workspace_id=source.workspace_id
    JOIN app_data.projects project ON project.project_id=source.project_id
    WHERE workspace.workspace_kind IS DISTINCT FROM 'personal'
      OR project.workspace_id IS DISTINCT FROM source.workspace_id
      OR workspace.personal_owner_app_user_id IS DISTINCT FROM source.app_user_id
      OR (provenance.actor_app_user_id IS NOT NULL
        AND provenance.actor_app_user_id IS DISTINCT FROM source.app_user_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='organization purge contribution provenance mismatch';
  END IF;

$extension$);

CREATE FUNCTION public.fixture_0133_history_strip_extensions(function_oid oid, source text)
RETURNS text LANGUAGE plpgsql AS $function$
DECLARE extension record;
BEGIN
  FOR extension IN SELECT fragment FROM public.fixture_0133_history_extensions e
    WHERE e.function_oid = $1 ORDER BY label LOOP
    source := replace(source, extension.fragment, '');
  END LOOP;
  RETURN source;
END $function$;
CREATE FUNCTION public.fixture_0133_history_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(CASE WHEN p.oid IN (
      'app_private.organization_purge_requests_v1(uuid)'::regprocedure,
      'app_private.finalize_organization_purge_v1(uuid,uuid)'::regprocedure)
    THEN jsonb_build_object('catalog', jsonb_set(to_jsonb(p), '{prosrc}',
      to_jsonb(public.fixture_0133_history_strip_extensions(p.oid, p.prosrc))),
      'definition', public.fixture_0133_history_strip_extensions(p.oid, pg_get_functiondef(p.oid)))
    ELSE jsonb_build_object('catalog', to_jsonb(p), 'definition', pg_get_functiondef(p.oid)) END ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0133_history_legacy_functions old ON old.oid = p.oid
$function$;
CREATE FUNCTION public.fixture_0133_history_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0133_history_legacy_relations ORDER BY nspname, relname LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text), ''[]''::jsonb) FROM %I.%I r',
      relation.nspname, relation.relname) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE FUNCTION public.fixture_0133_history_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid', c.oid, 'schema', n.nspname, 'name', c.relname,
    'owner', c.relowner, 'acl', c.relacl, 'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), 'constraints',
    (SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(k), 'definition', pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid = c.oid
      AND NOT (k.conrelid = 'app_private.organization_purge_request_tombstones'::regclass
        AND k.conname = 'organization_purge_request_tombstones_claim_family_check'))) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN public.fixture_0133_history_legacy_relations old ON old.oid = c.oid
$function$;
CREATE FUNCTION public.fixture_0133_history_receipt_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
BEGIN
  RETURN jsonb_build_object(
    'previews', (SELECT jsonb_agg(to_jsonb(r) ORDER BY preview_id) FROM app_private.personal_history_contribution_previews_v1 r),
    'copies', (SELECT jsonb_agg(to_jsonb(r) ORDER BY copy_id) FROM app_private.organization_historical_contact_copies_v1 r),
    'confirmations', (SELECT jsonb_agg(to_jsonb(r) ORDER BY request_id) FROM app_private.personal_history_contribution_confirmations_v1 r));
END $function$;
CREATE TABLE public.fixture_0133_history_state AS
SELECT public.fixture_0133_history_business_state() AS business_state,
  public.fixture_0133_history_function_catalog() AS function_catalog,
  public.fixture_0133_history_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conrelid = 'app_private.organization_purge_request_tombstones'::regclass
      AND conname = 'organization_purge_request_tombstones_claim_family_check') AS family_check_definition;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) <> '0133_account_deletion_recovery_core'
    OR (SELECT result_code FROM public.fixture_0133_history_submit) IS DISTINCT FROM 'accepted'
    OR (SELECT count(*) FROM public.fixture_0133_history_context) <> 1
    OR NOT EXISTS (SELECT 1 FROM app_private.account_deletion_current
      WHERE deletion_request_id = '7f330100-0000-4000-8000-000000000001' AND status = 'restored')
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1)
    OR EXISTS (SELECT 1 FROM public.fixture_0133_history_extensions e JOIN pg_proc p ON p.oid = e.function_oid
      WHERE position(e.fragment IN p.prosrc) <> 0)
    OR to_regclass('app_private.personal_history_contribution_previews_v1') IS NOT NULL
  THEN RAISE EXCEPTION '0133 history contribution live baseline lacks accepted source or historical receipts'; END IF;
END $baseline$;

CREATE FUNCTION public.fixture_0133_history_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0133_history_state%ROWTYPE; actor uuid; preview jsonb;
  confirmed jsonb; replayed jsonb; receipt_state jsonb; source_row app_data.contacts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0133_history_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
    OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0134_personal_history_contribution'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version <> '0134_personal_history_contribution') IS DISTINCT FROM saved.migrations
    OR public.fixture_0133_history_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0133_history_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0133_history_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM public.fixture_0133_history_legacy_functions)
      <> jsonb_array_length(public.fixture_0133_history_function_catalog())
    OR EXISTS (SELECT 1 FROM public.fixture_0133_history_extensions e JOIN pg_proc p ON p.oid = e.function_oid
      WHERE length(p.prosrc) - length(replace(p.prosrc, e.fragment, '')) <> length(e.fragment))
    OR (SELECT replace(pg_get_constraintdef(oid), '''personal-history-contribution-confirmation''::text, ', '')
      FROM pg_constraint WHERE conrelid = 'app_private.organization_purge_request_tombstones'::regclass
        AND conname = 'organization_purge_request_tombstones_claim_family_check') IS DISTINCT FROM saved.family_check_definition
    OR (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace)
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0133_history_legacy_functions old WHERE old.oid = p.oid)) <> 4
    OR (SELECT array_agg(c.relname::text ORDER BY c.relname) FROM pg_class c
      WHERE c.relnamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace) AND c.relkind = 'r'
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0133_history_legacy_relations old WHERE old.oid = c.oid))
      IS DISTINCT FROM ARRAY['organization_historical_contact_copies_v1',
        'personal_history_contribution_confirmations_v1', 'personal_history_contribution_previews_v1']::text[]
    OR EXISTS (SELECT 1 FROM app_private.personal_history_contribution_previews_v1)
    OR EXISTS (SELECT 1 FROM app_private.organization_historical_contact_copies_v1)
    OR EXISTS (SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1)
  THEN RAISE EXCEPTION '0134 changed old rows, OID/owner/ACL/definitions, constraints or exact purge extensions'; END IF;

  SELECT app_user_id INTO STRICT actor FROM public.fixture_0133_history_context;
  SELECT * INTO STRICT source_row FROM app_data.contacts WHERE contact_id = '0133-history-upgrade-source';
  SELECT to_jsonb(r) INTO STRICT preview FROM app_private.preview_personal_history_contribution_v1(
    actor, source_row.contact_id, '7f330100-0000-4000-8000-000000000004') r;
  IF preview->>'contribution_preview_contract_id' IS DISTINCT FROM 'personal-history-contribution-preview:v1'
    OR (preview->>'source_revision_number')::integer IS DISTINCT FROM source_row.current_revision
    OR (preview->>'expires_at_utc')::timestamptz - (preview->>'issued_at_utc')::timestamptz <> interval '15 minutes'
    OR preview->>'target_project_id' IS DISTINCT FROM '7f330100-0000-4000-8000-000000000004'
    OR (preview->>'occurred_at_utc')::timestamptz IS DISTINCT FROM source_row.occurred_at_utc
    OR preview->>'occurred_time_zone' IS DISTINCT FROM source_row.occurred_time_zone
    OR preview->>'channel' IS DISTINCT FROM source_row.channel
    OR (preview->>'reach_count')::integer IS DISTINCT FROM source_row.reach_count
    OR (preview->>'interest_level')::integer IS DISTINCT FROM source_row.interest_level
  THEN RAISE EXCEPTION '0134 upgraded preview source facts or 15-minute receipt drift'; END IF;
  SELECT to_jsonb(r) INTO STRICT confirmed FROM app_private.confirm_personal_history_contribution_v1(
    actor, '7f330100-0000-4000-8000-000000000006', (preview->>'preview_id')::uuid) r;
  receipt_state := public.fixture_0133_history_receipt_state();
  SELECT to_jsonb(r) INTO STRICT replayed FROM app_private.confirm_personal_history_contribution_v1(
    actor, '7f330100-0000-4000-8000-000000000006', (preview->>'preview_id')::uuid) r;
  IF confirmed IS DISTINCT FROM replayed
    OR confirmed->>'contribution_contract_id' IS DISTINCT FROM 'personal-history-contribution-confirmation:v1'
    OR confirmed->>'target_project_id' IS DISTINCT FROM '7f330100-0000-4000-8000-000000000004'
    OR public.fixture_0133_history_receipt_state() IS DISTINCT FROM receipt_state
    OR (SELECT count(*) FROM app_private.personal_history_contribution_previews_v1) <> 1
    OR (SELECT count(*) FROM app_private.organization_historical_contact_copies_v1) <> 1
    OR (SELECT count(*) FROM app_private.personal_history_contribution_confirmations_v1) <> 1
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_historical_contact_copies_v1 copy
      WHERE copy.copy_id = (confirmed->>'copy_id')::uuid
        AND copy.target_project_id = '7f330100-0000-4000-8000-000000000004'
        AND copy.occurred_at_utc = source_row.occurred_at_utc AND copy.occurred_time_zone = source_row.occurred_time_zone
        AND copy.channel = source_row.channel AND copy.reach_count = source_row.reach_count
        AND copy.interest_level = source_row.interest_level
        AND copy.confirmed_at_utc = (confirmed->>'confirmed_at_utc')::timestamptz)
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_purge_requests_v1(
      (SELECT organization_workspace_id FROM public.fixture_0133_history_organization))
      WHERE lock_rank = 14 AND lock_namespace = 'personal-history-contribution-confirmation'
        AND claim_family = 'personal-history-contribution-confirmation'
        AND request_uuid = '7f330100-0000-4000-8000-000000000006')
    OR public.fixture_0133_history_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0133_history_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0133_history_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0134 upgraded immutable copy, exact replay, purge collector or retained old facts drift'; END IF;
END $function$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
