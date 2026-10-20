\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TABLE public.fixture_0136_resolution_targets AS
SELECT choice.ordinal, (created.target->>'target_id')::uuid AS target_id
FROM public.fixture_0135_project_context c CROSS JOIN (VALUES (1), (2)) choice(ordinal)
CROSS JOIN LATERAL app_data.create_promotion_target(c.app_user_id, c.workspace_id, c.project_id, 'person',
  '0136 resolution target ' || choice.ordinal, '+1 312 555 0137', '0137-source@example.test',
  '0136-resolution-target-' || choice.ordinal) created;
CREATE TABLE public.fixture_0136_resolution_contact AS
SELECT result.result_code FROM public.fixture_0135_project_context c
JOIN public.fixture_0136_resolution_targets target ON target.ordinal = 1
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id, '0136-resolution-entry-submit',
  1, 'contact.submit.v1', '0136-resolution-device', '0136-resolution-entry', 0,
  jsonb_build_object('contactId', '0136-resolution-entry', 'workspaceId', c.workspace_id,
    'projectId', c.project_id, 'questionnaireVersionId', c.questionnaire_version_id,
    'occurredAtUtc', '2025-01-02T03:04:05Z', 'occurredTimeZone', 'UTC', 'channel', 'video_call',
    'location', jsonb_build_object('kind', 'not_applicable'), 'reachCount', 1, 'interestLevel', 2,
    'answers', '[]'::jsonb, 'targetLinks', jsonb_build_array(jsonb_build_object(
      'targetId', target.target_id, 'targetType', 'person', 'responseLevel', NULL,
      'followUpConsent', 'unknown', 'institutionRepresentativeConfirmed', false, 'confirmStageZero', true)))) result;
CREATE TABLE public.fixture_0136_resolution_generation AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id, c.project_id,
  '7f360100-0000-4000-8000-000000000004', preview.preview_id, first.target_id, second.target_id,
  first.target_id, second.target_id) AS generation_id
FROM public.fixture_0135_project_context c
JOIN public.fixture_0136_resolution_targets first ON first.ordinal = 1
JOIN public.fixture_0136_resolution_targets second ON second.ordinal = 2
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0135-project-upgrade.example.test',
  'owner', c.project_id, first.target_id, second.target_id) preview;
SELECT result FROM public.fixture_0135_project_context c
JOIN public.fixture_0136_resolution_targets target ON target.ordinal = 1
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id, c.workspace_id, c.project_id,
  target.target_id, 1, 1, 'active', '0136 existing private note', 'progress_update', NULL,
  '0136-resolution-ordinary-update', NULL);
CREATE TABLE public.fixture_0136_resolution_pending AS
SELECT choice.ordinal, staged.* FROM public.fixture_0135_project_context c
CROSS JOIN public.fixture_0136_resolution_generation g
CROSS JOIN (VALUES (1, '7f360100-0000-4000-8000-000000000001'::uuid),
  (2, '7f360100-0000-4000-8000-000000000002'::uuid)) choice(ordinal, request_id)
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id, c.workspace_id,
  c.project_id, choice.request_id, g.generation_id, 3, 'paused', '0136 private equal payload',
  'other', '0136 private equal reason') staged;
CREATE TABLE public.fixture_0136_resolution_other_project AS
SELECT * FROM app_data.create_personal_project_context('https://0135-project-upgrade.example.test', 'owner', '0136 original second project');
INSERT INTO public.fixture_0136_resolution_pending
SELECT 3, staged.* FROM public.fixture_0136_resolution_other_project c CROSS JOIN public.fixture_0136_resolution_generation g
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id, c.workspace_id,
  c.project_id, '7f360100-0000-4000-8000-000000000003', g.generation_id, 4, 'ended', NULL, 'target_request', NULL) staged;
SELECT selected.* FROM public.fixture_0135_project_context c CROSS JOIN LATERAL
  app_data.select_personal_project_context('https://0135-project-upgrade.example.test', 'owner', c.project_id) selected;
CREATE TABLE public.fixture_0136_resolution_assignments AS
SELECT pending.pending_fact_id, target.target_id AS source_target_id
FROM public.fixture_0136_resolution_pending pending
JOIN public.fixture_0136_resolution_targets target ON target.ordinal = CASE WHEN pending.ordinal = 3 THEN 2 ELSE 1 END;

CREATE TABLE public.fixture_0136_resolution_legacy_relations AS
SELECT c.oid, n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r';
CREATE TABLE public.fixture_0136_resolution_legacy_functions AS
SELECT p.oid FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0136_resolution_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0136_resolution_legacy_relations ORDER BY nspname, relname LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text), ''[]''::jsonb) FROM %I.%I r',
      relation.nspname, relation.relname) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE FUNCTION public.fixture_0136_resolution_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(p), 'definition', pg_get_functiondef(p.oid)) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0136_resolution_legacy_functions old ON old.oid = p.oid
$function$;
CREATE FUNCTION public.fixture_0136_resolution_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid', c.oid, 'schema', n.nspname, 'name', c.relname,
    'owner', c.relowner, 'acl', c.relacl, 'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), 'constraints',
    (SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(k), 'definition', pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid = c.oid), 'triggers',
    (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t WHERE t.tgrelid = c.oid)) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN public.fixture_0136_resolution_legacy_relations old ON old.oid = c.oid
$function$;
CREATE TABLE public.fixture_0136_resolution_state AS
WITH selected AS (
  SELECT header.pending_fact_id, header.project_id, header.staged_at_utc, assignment.source_target_id
  FROM public.fixture_0136_resolution_assignments assignment
  JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING (pending_fact_id)
), grouped AS (
  SELECT project_id, source_target_id,
    jsonb_agg(pending_fact_id ORDER BY staged_at_utc, pending_fact_id) AS pending_fact_ids,
    count(*) AS pending_count FROM selected GROUP BY project_id, source_target_id
), slots AS (
  SELECT grouped.project_id, grouped.source_target_id, grouped.pending_fact_ids,
    CASE WHEN relationship.promotion_target_id IS NOT NULL THEN jsonb_build_object(
      'revision_number', revision.revision_number, 'merge_generation_id', revision.merge_generation_id) END AS current_relationship,
    grouped.pending_count + CASE WHEN relationship.promotion_target_id IS NOT NULL THEN 1 ELSE 0 END AS candidate_count,
    grouped.pending_count + CASE WHEN relationship.promotion_target_id IS NOT NULL THEN 1 ELSE 0 END > 1 AS requires_choice
  FROM grouped LEFT JOIN app_data.promotion_target_project_relationships relationship
    ON relationship.promotion_target_id = grouped.source_target_id AND relationship.project_id = grouped.project_id
  LEFT JOIN app_data.promotion_target_relationship_revisions revision
    ON revision.promotion_target_id = relationship.promotion_target_id AND revision.project_id = relationship.project_id
      AND revision.revision_number = relationship.current_revision
), metadata AS (
  SELECT c.app_user_id, c.workspace_id, c.project_id, g.generation_id,
    app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id, c.workspace_id, c.project_id, g.generation_id) AS pending_plan,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id', upper(pending_fact_id::text),
      'source_target_id', upper(source_target_id::text)) ORDER BY pending_fact_id DESC) FROM selected) AS input_assignments,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id', pending_fact_id, 'source_target_id', source_target_id,
      'project_id', project_id) ORDER BY pending_fact_id) FROM selected) AS canonical_assignments,
    (SELECT jsonb_agg(to_jsonb(slot) ORDER BY project_id, source_target_id) FROM slots slot) AS source_slots,
    (SELECT count(*) FROM slots WHERE requires_choice) AS conflict_count
  FROM public.fixture_0135_project_context c CROSS JOIN public.fixture_0136_resolution_generation g
)
SELECT metadata.*, jsonb_build_object('contract_id', 'personal_merge_project_relationship_resolution_plan_v1',
    'known_source_plan', pending_plan->'known_source_plan', 'pending_fingerprint', pending_plan->>'pending_fingerprint',
    'assignments', canonical_assignments, 'source_slots', source_slots, 'conflict_count', conflict_count) AS expected_metadata,
  public.fixture_0136_resolution_business_state() AS business_state,
  public.fixture_0136_resolution_function_catalog() AS function_catalog,
  public.fixture_0136_resolution_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count FROM metadata;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations) <> '0136_personal_merge_unassigned_project_relationships'
    OR (SELECT result_code FROM public.fixture_0136_resolution_contact) IS DISTINCT FROM 'accepted'
    OR (SELECT count(*) FROM public.fixture_0136_resolution_pending) <> 3
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships relationship
      JOIN public.fixture_0136_resolution_targets target ON target.target_id = relationship.promotion_target_id AND target.ordinal = 1
      JOIN public.fixture_0135_project_context c ON c.project_id = relationship.project_id
      JOIN app_data.promotion_target_relationship_revisions revision
        ON revision.promotion_target_id = relationship.promotion_target_id AND revision.project_id = relationship.project_id
        AND revision.revision_number = relationship.current_revision
      WHERE relationship.current_revision = 2 AND relationship.current_stage = 1
        AND relationship.merge_generation_id IS NULL
        AND revision.merge_generation_id = (SELECT generation_id FROM public.fixture_0136_resolution_generation)
        AND EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions initial
          WHERE initial.promotion_target_id = relationship.promotion_target_id AND initial.project_id = relationship.project_id
            AND initial.revision_number = 1 AND initial.merge_generation_id IS NULL))
    OR (SELECT pending_plan->>'pending_count' FROM public.fixture_0136_resolution_state) IS DISTINCT FROM '3'
    OR (SELECT conflict_count FROM public.fixture_0136_resolution_state) <> 1
    OR (SELECT jsonb_array_length(source_slots) FROM public.fixture_0136_resolution_state) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1)
    OR NOT EXISTS (SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1)
    OR to_regprocedure('app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)') IS NOT NULL
  THEN RAISE EXCEPTION '0136 resolution upgrade lacks real current revision, multi-project pending facts or historical receipts'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0136_resolution_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0136_resolution_state%ROWTYPE; document jsonb; expected jsonb; canonical_input jsonb;
  invalid_case integer; known_fingerprint text; pending_fingerprint text; assignments jsonb;
  actual_state text; actual_message text;
BEGIN
  IF current_setting('transaction_read_only') <> 'on'
  THEN RAISE EXCEPTION '0137 live plan assertion must run inside READ ONLY'; END IF;
  SELECT * INTO STRICT saved FROM public.fixture_0136_resolution_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> saved.migration_count + 1
    OR (SELECT max(version) FROM app_migrations.schema_migrations) <> '0137_personal_merge_project_relationship_resolution_plan'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version <> '0137_personal_merge_project_relationship_resolution_plan') IS DISTINCT FROM saved.migrations
    OR public.fixture_0136_resolution_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0136_resolution_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0136_resolution_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM public.fixture_0136_resolution_legacy_functions)
      <> jsonb_array_length(public.fixture_0136_resolution_function_catalog())
    OR (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace)
      AND NOT EXISTS (SELECT 1 FROM public.fixture_0136_resolution_legacy_functions old WHERE old.oid = p.oid)) <> 1
    OR (SELECT count(*) FROM pg_class c WHERE c.relnamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace) AND c.relkind = 'r')
      <> (SELECT count(*) FROM public.fixture_0136_resolution_legacy_relations)
  THEN RAISE EXCEPTION '0137 migration changed old rows, OID/owner/ACL, definitions, constraints, triggers or relations'; END IF;
  expected := saved.expected_metadata || jsonb_build_object('resolution_fingerprint',
    encode(sha256(convert_to(saved.expected_metadata::text, 'UTF8')), 'hex'));
  document := app_private.plan_personal_merge_project_relationship_resolutions_v1(saved.app_user_id, saved.workspace_id,
    saved.project_id, saved.generation_id, saved.pending_plan->'known_source_plan'->>'fact_fingerprint',
    saved.pending_plan->>'pending_fingerprint', saved.input_assignments);
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id', lower(item->>'pending_fact_id'),
    'source_target_id', lower(item->>'source_target_id')) ORDER BY item->>'pending_fact_id') INTO canonical_input
  FROM jsonb_array_elements(saved.input_assignments) item;
  IF document IS DISTINCT FROM expected OR app_private.plan_personal_merge_project_relationship_resolutions_v1(
      saved.app_user_id, saved.workspace_id, saved.project_id, saved.generation_id,
      saved.pending_plan->'known_source_plan'->>'fact_fingerprint', saved.pending_plan->>'pending_fingerprint', canonical_input)
      IS DISTINCT FROM expected
    OR public.fixture_0136_resolution_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0136_resolution_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0136_resolution_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0137 full metadata JSON, canonical UUID/order, candidates, fingerprint or read-only state drift'; END IF;
  FOR invalid_case IN 1..3 LOOP
    known_fingerprint := saved.pending_plan->'known_source_plan'->>'fact_fingerprint';
    pending_fingerprint := saved.pending_plan->>'pending_fingerprint'; assignments := saved.input_assignments;
    IF invalid_case = 1 THEN known_fingerprint := repeat('0', 64);
    ELSIF invalid_case = 2 THEN pending_fingerprint := repeat('0', 64);
    ELSE assignments := jsonb_set(assignments, '{0,source_target_id}', to_jsonb('7f360100-0000-4000-8000-000000000099'::text)); END IF;
    actual_state := NULL; actual_message := NULL;
    BEGIN
      PERFORM app_private.plan_personal_merge_project_relationship_resolutions_v1(saved.app_user_id, saved.workspace_id,
        saved.project_id, saved.generation_id, known_fingerprint, pending_fingerprint, assignments);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
    END;
    IF actual_state IS DISTINCT FROM '23505'
      OR actual_message IS DISTINCT FROM 'pending project relationship resolution inventory or source assignment changed'
      OR public.fixture_0136_resolution_business_state() IS DISTINCT FROM saved.business_state
      OR public.fixture_0136_resolution_function_catalog() IS DISTINCT FROM saved.function_catalog
      OR public.fixture_0136_resolution_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    THEN RAISE EXCEPTION '0137 stale fingerprint or foreign source mapping accepted or changed old state: case %', invalid_case; END IF;
  END LOOP;
END $function$;
COMMIT;
