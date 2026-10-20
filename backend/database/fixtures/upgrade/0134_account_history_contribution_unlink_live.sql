\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TABLE public.fixture_0134_unlink_context AS
SELECT 'actor'::text AS label, c.* FROM app_data.bootstrap_personal_context('https://0134-unlink-upgrade.example.test', 'actor') c
UNION ALL SELECT 'owner', c.* FROM app_data.bootstrap_personal_context('https://0134-unlink-upgrade.example.test', 'owner') c;
CREATE TABLE public.fixture_0134_unlink_organizations AS
SELECT choice.label, choice.target_project_id, receipt.* FROM public.fixture_0134_unlink_context owner
CROSS JOIN (VALUES
  ('first', '7f340100-0000-4000-8000-000000000001'::uuid, '7f340100-0000-4000-8000-000000000010'::uuid),
  ('second', '7f340100-0000-4000-8000-000000000002'::uuid, '7f340100-0000-4000-8000-000000000011'::uuid)
) choice(label, request_id, target_project_id)
CROSS JOIN LATERAL app_private.create_organization_v1(owner.app_user_id, choice.request_id, '0134 unlink retained organization') receipt
WHERE owner.label = 'owner';
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT target_project_id, organization_workspace_id, '0134 unlink target' FROM public.fixture_0134_unlink_organizations;
CREATE TABLE public.fixture_0134_unlink_invitations AS
SELECT org.label, receipt.* FROM public.fixture_0134_unlink_organizations org
CROSS JOIN public.fixture_0134_unlink_context actor CROSS JOIN public.fixture_0134_unlink_context owner
CROSS JOIN LATERAL app_private.create_organization_directed_account_invitation_v1(owner.app_user_id,
  gen_random_uuid(), org.organization_workspace_id, actor.app_user_id) receipt
WHERE actor.label = 'actor' AND owner.label = 'owner';
CREATE TABLE public.fixture_0134_unlink_memberships AS
SELECT invitation.label, receipt.* FROM public.fixture_0134_unlink_invitations invitation
CROSS JOIN public.fixture_0134_unlink_context actor
CROSS JOIN LATERAL app_private.accept_organization_directed_account_invitation_v1(actor.app_user_id, invitation.invitation_id) receipt
WHERE actor.label = 'actor';
CREATE TABLE public.fixture_0134_unlink_project_memberships AS
SELECT org.label AS organization_label, actor.label AS actor_label, receipt.*
FROM public.fixture_0134_unlink_organizations org CROSS JOIN public.fixture_0134_unlink_context actor
CROSS JOIN public.fixture_0134_unlink_context owner
CROSS JOIN LATERAL app_private.assign_organization_project_member_v1(owner.app_user_id, gen_random_uuid(),
  org.organization_workspace_id, org.target_project_id, CASE WHEN actor.label = 'actor'
    THEN (SELECT organization_membership_id FROM public.fixture_0134_unlink_memberships m WHERE m.label = org.label)
    ELSE org.organization_membership_id END) receipt
WHERE owner.label = 'owner';
CREATE TABLE public.fixture_0134_unlink_submissions AS
SELECT c.label, submitted.result_code FROM public.fixture_0134_unlink_context c
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id, '0134-unlink-submit-' || c.label,
  1, 'contact.submit.v1', '0134-unlink-device', '0134-unlink-source-' || c.label, 0,
  jsonb_build_object('contactId', '0134-unlink-source-' || c.label, 'workspaceId', c.workspace_id,
    'projectId', c.project_id, 'questionnaireVersionId', c.questionnaire_version_id,
    'occurredAtUtc', '2025-03-09T07:59:59.123456Z', 'occurredTimeZone', 'America/Chicago',
    'channel', 'instant_text', 'channelDetail', '0134 retained private detail',
    'location', jsonb_build_object('kind', 'not_applicable'), 'reachCount', 3,
    'interestLevel', 4, 'answers', '[]'::jsonb, 'targetLinks', '[]'::jsonb)) submitted;
CREATE TABLE public.fixture_0134_unlink_previews(actor_label text, organization_label text, variant text, preview_id uuid);
DO $previews$
DECLARE choice record; issued_preview_id uuid;
BEGIN
  FOR choice IN SELECT actor.label AS actor_label, actor.app_user_id, org.label AS organization_label,
    org.target_project_id, variant.variant
    FROM public.fixture_0134_unlink_context actor CROSS JOIN public.fixture_0134_unlink_organizations org
    CROSS JOIN (VALUES ('confirmed'), ('unused-actor'), ('unused-source')) variant(variant)
    WHERE (actor.label = 'actor' AND (variant.variant = 'confirmed' OR org.label = 'first'))
      OR (actor.label = 'owner' AND org.label = 'first' AND variant.variant = 'confirmed')
  LOOP
    SELECT preview_id INTO STRICT issued_preview_id FROM app_private.preview_personal_history_contribution_v1(
      choice.app_user_id, '0134-unlink-source-' || choice.actor_label, choice.target_project_id);
    INSERT INTO public.fixture_0134_unlink_previews
      VALUES (choice.actor_label, choice.organization_label, choice.variant, issued_preview_id);
  END LOOP;
END $previews$;
CREATE TABLE public.fixture_0134_unlink_confirmations AS
SELECT preview.actor_label, preview.organization_label, request.request_id, receipt.*
FROM public.fixture_0134_unlink_previews preview
JOIN public.fixture_0134_unlink_context actor ON actor.label = preview.actor_label
CROSS JOIN LATERAL (SELECT CASE WHEN actor.label = 'owner' THEN '7f340100-0000-4000-8000-000000000022'::uuid
  WHEN preview.organization_label = 'first' THEN '7f340100-0000-4000-8000-000000000020'::uuid
  ELSE '7f340100-0000-4000-8000-000000000021'::uuid END AS request_id) request
CROSS JOIN LATERAL app_private.confirm_personal_history_contribution_v1(actor.app_user_id, request.request_id, preview.preview_id) receipt
WHERE preview.variant = 'confirmed';
UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id = NULL
WHERE preview_id IN (SELECT preview_id FROM public.fixture_0134_unlink_previews
  WHERE actor_label = 'actor' AND organization_label = 'first' AND variant IN ('confirmed', 'unused-source'));
UPDATE app_private.personal_history_contribution_previews_v1 SET source_contact_id = NULL
WHERE preview_id IN (SELECT preview_id FROM public.fixture_0134_unlink_previews
  WHERE actor_label = 'actor' AND variant = 'unused-actor');
UPDATE app_private.personal_history_contribution_confirmations_v1 SET source_contact_id = NULL
WHERE request_id = '7f340100-0000-4000-8000-000000000021';
CREATE TABLE public.fixture_0134_unlink_cycle AS
SELECT receipt.* FROM public.fixture_0134_unlink_context actor CROSS JOIN LATERAL
  app_private.request_account_deletion_v1(actor.app_user_id, '7f340100-0000-4000-8000-000000000030') receipt
WHERE actor.label = 'actor';
-- Synthetic expiry changes matching lifecycle timestamps before the frozen upgrade baseline.
SET LOCAL session_replication_role = replica;
UPDATE app_private.account_deletion_current
SET effective_at_utc = transaction_timestamp() - interval '721 hours', purge_after_utc = transaction_timestamp() - interval '1 hour'
WHERE deletion_request_id = '7f340100-0000-4000-8000-000000000030';
UPDATE app_private.account_deletion_request_claims claim
SET effective_at_utc = cycle.effective_at_utc, purge_after_utc = cycle.purge_after_utc
FROM app_private.account_deletion_current cycle
WHERE claim.request_id = cycle.deletion_request_id AND claim.request_id = '7f340100-0000-4000-8000-000000000030';
UPDATE app_private.account_deletion_audit_events audit SET occurred_at_utc = cycle.effective_at_utc
FROM app_private.account_deletion_current cycle
WHERE audit.request_id = cycle.deletion_request_id AND audit.request_id = '7f340100-0000-4000-8000-000000000030';
SET LOCAL session_replication_role = origin;

CREATE TABLE public.fixture_0134_unlink_legacy_relations AS
SELECT c.oid, n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r';
CREATE TABLE public.fixture_0134_unlink_legacy_functions AS
SELECT p.oid FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0134_unlink_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(p), 'definition', pg_get_functiondef(p.oid)) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0134_unlink_legacy_functions old ON old.oid = p.oid
$function$;
CREATE FUNCTION public.fixture_0134_unlink_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid', c.oid, 'schema', n.nspname, 'name', c.relname,
    'owner', c.relowner, 'acl', c.relacl, 'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), 'constraints',
    (SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(k), 'definition', pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid = c.oid), 'triggers',
    (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t WHERE t.tgrelid = c.oid)) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN public.fixture_0134_unlink_legacy_relations old ON old.oid = c.oid
$function$;
CREATE FUNCTION public.fixture_0134_unlink_business_state(expected_unlinked boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb; expression text;
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0134_unlink_legacy_relations ORDER BY nspname, relname LOOP
    expression := 'to_jsonb(r)';
    IF expected_unlinked AND relation.nspname = 'app_private' THEN
      IF relation.relname = 'personal_history_contribution_previews_v1' THEN
        expression := 'CASE WHEN r.preview_id IN (SELECT preview_id FROM public.fixture_0134_unlink_previews WHERE actor_label = ''actor'')
          THEN to_jsonb(r) || jsonb_build_object(''actor_app_user_id'', NULL, ''source_contact_id'', NULL) ELSE to_jsonb(r) END';
      ELSIF relation.relname = 'personal_history_contribution_confirmations_v1' THEN
        expression := 'CASE WHEN r.request_id IN (SELECT request_id FROM public.fixture_0134_unlink_confirmations WHERE actor_label = ''actor'')
          THEN to_jsonb(r) || jsonb_build_object(''actor_app_user_id'', NULL, ''source_contact_id'', NULL) ELSE to_jsonb(r) END';
      END IF;
    END IF;
    EXECUTE format('SELECT coalesce(jsonb_agg(%s ORDER BY (%s)::text), ''[]''::jsonb) FROM %I.%I r',
      expression, expression, relation.nspname, relation.relname) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE TABLE public.fixture_0134_unlink_state AS
SELECT public.fixture_0134_unlink_business_state() AS business_state,
  public.fixture_0134_unlink_business_state(true) AS expected_unlinked_state,
  public.fixture_0134_unlink_function_catalog() AS function_catalog,
  public.fixture_0134_unlink_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) <> '0134_personal_history_contribution'
    OR (SELECT count(*) FROM public.fixture_0134_unlink_submissions WHERE result_code = 'accepted') <> 2
    OR (SELECT count(*) FROM public.fixture_0134_unlink_previews) <> 5
    OR (SELECT count(*) FROM public.fixture_0134_unlink_confirmations) <> 3
    OR (SELECT count(*) FROM app_private.personal_history_contribution_previews_v1) <> 5
    OR (SELECT count(*) FROM app_private.personal_history_contribution_confirmations_v1) <> 3
    OR (SELECT count(*) FROM app_private.organization_historical_contact_copies_v1) <> 3
    OR NOT EXISTS (SELECT 1 FROM app_private.account_deletion_current cycle
      JOIN app_private.account_deletion_request_claims claim ON claim.request_id = cycle.deletion_request_id
      JOIN public.fixture_0134_unlink_context actor ON actor.app_user_id = cycle.app_user_id
      WHERE actor.label = 'actor' AND cycle.status = 'deletion_pending'
        AND cycle.deletion_request_id = '7f340100-0000-4000-8000-000000000030'
        AND claim.actor_app_user_id = actor.app_user_id AND claim.effective_at_utc = cycle.effective_at_utc
        AND claim.purge_after_utc = cycle.purge_after_utc
        AND cycle.purge_after_utc = cycle.effective_at_utc + interval '720 hours'
        AND cycle.purge_after_utc < clock_timestamp())
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1)
    OR to_regclass('app_private.account_history_contribution_unlink_completions_v1') IS NOT NULL
  THEN RAISE EXCEPTION '0134 contribution unlink live baseline lacks due provenance or historical receipts'; END IF;
END $baseline$;

CREATE FUNCTION public.fixture_0134_unlink_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0134_unlink_state%ROWTYPE; actor uuid;
  first_result jsonb; replay_result jsonb; completion_state jsonb;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0134_unlink_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
    OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0135_account_history_contribution_unlink'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version <> '0135_account_history_contribution_unlink') IS DISTINCT FROM saved.migrations
    OR public.fixture_0134_unlink_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0134_unlink_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0134_unlink_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM public.fixture_0134_unlink_legacy_functions)
      <> jsonb_array_length(public.fixture_0134_unlink_function_catalog())
    OR (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace)
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0134_unlink_legacy_functions old WHERE old.oid = p.oid)) <> 1
    OR (SELECT array_agg(c.relname::text ORDER BY c.relname) FROM pg_class c
      WHERE c.relnamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace) AND c.relkind = 'r'
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0134_unlink_legacy_relations old WHERE old.oid = c.oid))
      IS DISTINCT FROM ARRAY['account_history_contribution_unlink_completions_v1']::text[]
    OR EXISTS (SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1)
  THEN RAISE EXCEPTION '0135 migration changed old rows, function identities, owners, ACLs, definitions or constraints'; END IF;

  SELECT app_user_id INTO STRICT actor FROM public.fixture_0134_unlink_context WHERE label = 'actor';
  SELECT to_jsonb(r) INTO STRICT first_result FROM app_private.unlink_due_account_history_contributions_v1(
    actor, '7f340100-0000-4000-8000-000000000030') r;
  IF first_result->>'account_history_contribution_unlink_contract_id' IS DISTINCT FROM 'account-history-contribution-unlink:v1'
    OR first_result->>'deletion_request_id' IS DISTINCT FROM '7f340100-0000-4000-8000-000000000030'
    OR NOT isfinite((first_result->>'unlinked_at_utc')::timestamptz)
    OR (first_result->>'unlinked_at_utc')::timestamptz < (SELECT purge_after_utc
      FROM app_private.account_deletion_current WHERE app_user_id = actor)
    OR (SELECT count(*) FROM app_private.account_history_contribution_unlink_completions_v1) <> 1
    OR NOT EXISTS (SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1
      WHERE deletion_request_id = '7f340100-0000-4000-8000-000000000030'
        AND unlinked_at_utc = (first_result->>'unlinked_at_utc')::timestamptz)
    OR public.fixture_0134_unlink_business_state() IS DISTINCT FROM saved.expected_unlinked_state
    OR public.fixture_0134_unlink_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0134_unlink_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0135 unlink changed retained sources, copies, other actors, lifecycle or old metadata'; END IF;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY deletion_request_id) INTO completion_state
  FROM app_private.account_history_contribution_unlink_completions_v1 r;
  SELECT to_jsonb(r) INTO STRICT replay_result FROM app_private.unlink_due_account_history_contributions_v1(
    actor, '7f340100-0000-4000-8000-000000000030') r;
  IF replay_result IS DISTINCT FROM first_result
    OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY deletion_request_id)
      FROM app_private.account_history_contribution_unlink_completions_v1 r) IS DISTINCT FROM completion_state
    OR public.fixture_0134_unlink_business_state() IS DISTINCT FROM saved.expected_unlinked_state
    OR public.fixture_0134_unlink_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0134_unlink_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0135 exact unlink replay changed its receipt or retained facts'; END IF;
END $function$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
