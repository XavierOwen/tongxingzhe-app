\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
SELECT selected.* FROM public.fixture_0136_resolution_other_project c CROSS JOIN LATERAL
  app_data.select_personal_project_context('https://0135-project-upgrade.example.test', 'owner', c.project_id) selected;
CREATE TABLE public.fixture_0137_confirmation_contact AS
SELECT result.result_code FROM public.fixture_0136_resolution_other_project c
JOIN public.fixture_0136_resolution_targets target ON target.ordinal = 2
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id, '0137-confirmation-entry-submit',
  1, 'contact.submit.v1', '0137-confirmation-device', '0137-confirmation-entry', 0,
  jsonb_build_object('contactId', '0137-confirmation-entry', 'workspaceId', c.workspace_id,
    'projectId', c.project_id, 'questionnaireVersionId', c.questionnaire_version_id,
    'occurredAtUtc', '2025-02-03T04:05:06Z', 'occurredTimeZone', 'UTC', 'channel', 'video_call',
    'location', jsonb_build_object('kind', 'not_applicable'), 'reachCount', 2, 'interestLevel', 3,
    'answers', '[]'::jsonb, 'targetLinks', jsonb_build_array(jsonb_build_object(
      'targetId', target.target_id, 'targetType', 'person', 'responseLevel', NULL,
      'followUpConsent', 'unknown', 'institutionRepresentativeConfirmed', false, 'confirmStageZero', true)))) result;
SELECT result FROM public.fixture_0136_resolution_other_project c
JOIN public.fixture_0136_resolution_targets target ON target.ordinal = 2
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id, c.workspace_id, c.project_id,
  target.target_id, 1, 2, 'active', '0137 second original current', 'progress_update', NULL,
  '0137-confirmation-ordinary-update', NULL);
SELECT selected.* FROM public.fixture_0135_project_context c CROSS JOIN LATERAL
  app_data.select_personal_project_context('https://0135-project-upgrade.example.test', 'owner', c.project_id) selected;
CREATE TABLE public.fixture_0137_confirmation_pending AS
SELECT header.*, payload.new_stage, payload.new_lifecycle_status, payload.follow_up_note, payload.reason_code,
  payload.reason_detail, assignment.source_target_id
FROM public.fixture_0136_resolution_assignments assignment
JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING (pending_fact_id)
JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 payload USING (pending_fact_id);
CREATE TABLE public.fixture_0137_confirmation_slots AS
SELECT relationship.*,
  CASE WHEN relationship.project_id = (SELECT project_id FROM public.fixture_0135_project_context)
    THEN (SELECT pending_fact_id FROM public.fixture_0136_resolution_pending WHERE ordinal = 1) END AS selected_pending_fact_id
FROM app_data.promotion_target_project_relationships relationship
JOIN (SELECT DISTINCT project_id, source_target_id FROM public.fixture_0137_confirmation_pending) slot
  ON slot.project_id = relationship.project_id AND slot.source_target_id = relationship.promotion_target_id;

CREATE TABLE public.fixture_0137_confirmation_legacy_relations AS
SELECT c.oid, n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('app_data', 'app_private') AND c.relkind = 'r';
CREATE TABLE public.fixture_0137_confirmation_legacy_functions AS
SELECT p.oid FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace, 'app_private'::regnamespace);
CREATE TABLE public.fixture_0137_confirmation_legacy_triggers AS
SELECT t.oid FROM pg_trigger t JOIN public.fixture_0137_confirmation_legacy_relations r ON r.oid = t.tgrelid;
CREATE TABLE public.fixture_0137_confirmation_guard_changes(function_oid oid, label text PRIMARY KEY, old_fragment text, new_fragment text);
INSERT INTO public.fixture_0137_confirmation_guard_changes VALUES
('app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure,'end-proof',
$old$  ) THEN$old$,$new$  ) AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
    WHERE request.actor_app_user_id = NEW.actor_app_user_id AND request.request_id = NEW.request_id
      AND request.workspace_id = NEW.workspace_id AND request.project_id = NEW.project_id
      AND request.generation_id = NEW.generation_id AND request.post_known_fact_fingerprint = NEW.fact_fingerprint
      AND NEW.operation = 'personal_target_known_source_merge_end' AND NEW.outcome = 'ended'
      AND NEW.ended_at_utc >= request.confirmed_at_utc
      AND app_private.personal_merge_project_relationship_resolution_proof_v1(request.actor_app_user_id, request.request_id)
  ) THEN$new$),
('app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure,'payload-proof',
$old$  ) THEN$old$,$new$  ) AND NOT EXISTS (
    SELECT 1
    FROM app_private.personal_merge_project_relationship_history_applications_v1 AS application
    JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 AS request USING (actor_app_user_id, request_id)
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 AS pending USING (pending_fact_id)
    JOIN app_private.personal_target_merge_end_events_v1 AS receipt
      ON receipt.actor_app_user_id = request.actor_app_user_id AND receipt.request_id = request.request_id
      AND receipt.generation_id = request.generation_id AND receipt.workspace_id = request.workspace_id
      AND receipt.project_id = request.project_id AND receipt.fact_fingerprint = request.post_known_fact_fingerprint
    JOIN app_data.promotion_target_relationship_revisions AS applied
      ON applied.promotion_target_id = application.source_target_id AND applied.project_id = application.project_id
      AND applied.revision_number = application.applied_revision_number
    JOIN app_data.promotion_target_relationship_revisions AS base
      ON base.promotion_target_id = application.source_target_id AND base.project_id = application.project_id
      AND base.revision_number = application.original_revision_number
    WHERE application.pending_fact_id = OLD.pending_fact_id
      AND pending.generation_id = request.generation_id AND pending.actor_app_user_id = request.actor_app_user_id
      AND pending.workspace_id = request.workspace_id AND pending.project_id = application.project_id
      AND receipt.reason = 'known_source_split' AND receipt.operation = 'personal_target_known_source_merge_end'
      AND receipt.outcome = 'ended' AND receipt.ended_at_utc >= request.confirmed_at_utc
      AND applied.merge_generation_id = request.generation_id
      AND applied.old_stage = base.new_stage AND applied.old_lifecycle_status = base.new_lifecycle_status
      AND applied.new_stage = OLD.new_stage AND applied.new_lifecycle_status = OLD.new_lifecycle_status
      AND applied.follow_up_note IS NOT DISTINCT FROM OLD.follow_up_note
      AND applied.reason_code = OLD.reason_code AND applied.reason_detail IS NOT DISTINCT FROM OLD.reason_detail
      AND applied.changed_fields = ARRAY['pending_source_assignment']::text[]
      AND applied.changed_by_app_user_id = request.actor_app_user_id AND applied.changed_at = pending.staged_at_utc
  ) THEN$new$),
('app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure,'payload-error',
 'pending project relationship deletion requires expiry receipt',
 'pending project relationship deletion requires expiry or applied confirmation receipt');
CREATE FUNCTION public.fixture_0137_confirmation_original_body(function_oid oid, source text)
RETURNS text LANGUAGE plpgsql AS $function$
DECLARE change record;
BEGIN
  FOR change IN SELECT old_fragment, new_fragment FROM public.fixture_0137_confirmation_guard_changes c
    WHERE c.function_oid = $1 ORDER BY label LOOP
    source := replace(source, change.new_fragment, change.old_fragment);
  END LOOP;
  RETURN source;
END $function$;
CREATE FUNCTION public.fixture_0137_confirmation_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(CASE WHEN p.oid IN (
    'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure,
    'app_private.guard_personal_merge_unassigned_project_relationship_payload_v1()'::regprocedure)
    THEN jsonb_build_object('catalog', jsonb_set(to_jsonb(p), '{prosrc}',
      to_jsonb(public.fixture_0137_confirmation_original_body(p.oid, p.prosrc))),
      'definition', public.fixture_0137_confirmation_original_body(p.oid, pg_get_functiondef(p.oid)))
    ELSE jsonb_build_object('catalog', to_jsonb(p), 'definition', pg_get_functiondef(p.oid)) END ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0137_confirmation_legacy_functions old ON old.oid = p.oid
$function$;
CREATE FUNCTION public.fixture_0137_confirmation_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid', c.oid, 'schema', n.nspname, 'name', c.relname,
    'owner', c.relowner, 'acl', c.relacl, 'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped), 'constraints',
    (SELECT jsonb_agg(jsonb_build_object('catalog', to_jsonb(k), 'definition', pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid = c.oid), 'old_triggers',
    (SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t
      JOIN public.fixture_0137_confirmation_legacy_triggers old ON old.oid = t.oid WHERE t.tgrelid = c.oid)) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN public.fixture_0137_confirmation_legacy_relations old ON old.oid = c.oid
$function$;
CREATE FUNCTION public.fixture_0137_confirmation_business_state(allow_confirmation boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb; expression text; predicate text;
BEGIN
  FOR relation IN SELECT * FROM public.fixture_0137_confirmation_legacy_relations ORDER BY nspname, relname LOOP
    expression := 'to_jsonb(r)'; predicate := 'true';
    IF allow_confirmation THEN
      IF relation.nspname = 'app_private' AND relation.relname = 'personal_target_merge_generation_fence_v1' THEN
        expression := 'to_jsonb(r) - ''epoch''';
      ELSIF relation.nspname = 'app_private' AND relation.relname IN (
        'personal_target_merge_active_members_v1', 'personal_target_merge_end_events_v1') THEN
        predicate := 'r.generation_id NOT IN (SELECT generation_id FROM public.fixture_0136_resolution_generation)';
      ELSIF relation.nspname = 'app_data' AND relation.relname = 'personal_merge_unassigned_project_relationship_facts_v1' THEN
        predicate := 'r.pending_fact_id NOT IN (SELECT pending_fact_id FROM public.fixture_0137_confirmation_pending)';
      ELSIF relation.nspname = 'app_data' AND relation.relname = 'promotion_target_relationship_revisions' THEN
        predicate := 'NOT EXISTS (SELECT 1 FROM public.fixture_0137_confirmation_slots s WHERE s.promotion_target_id=r.promotion_target_id
          AND s.project_id=r.project_id AND r.revision_number>s.current_revision)';
      ELSIF relation.nspname = 'app_data' AND relation.relname = 'promotion_target_project_relationships' THEN
        expression := 'CASE WHEN EXISTS (SELECT 1 FROM public.fixture_0137_confirmation_slots s WHERE s.promotion_target_id=r.promotion_target_id
          AND s.project_id=r.project_id) THEN to_jsonb(r) - ARRAY[''current_stage'',''current_lifecycle_status'',
            ''current_follow_up_note'',''current_revision'',''updated_by_app_user_id'',''updated_at''] ELSE to_jsonb(r) END';
      END IF;
    END IF;
    EXECUTE format('SELECT coalesce(jsonb_agg(%s ORDER BY (%s)::text), ''[]''::jsonb) FROM %I.%I r WHERE %s',
      expression, expression, relation.nspname, relation.relname, predicate) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname, rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE FUNCTION public.fixture_0137_confirmation_metadata_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
BEGIN
  RETURN jsonb_build_object(
    'requests', (SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_merge_project_relationship_resolution_requests_v1 r),
    'history', (SELECT jsonb_agg(to_jsonb(r) ORDER BY pending_fact_id) FROM app_private.personal_merge_project_relationship_history_applications_v1 r),
    'choices', (SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id,project_id,source_target_id) FROM app_private.personal_merge_project_relationship_current_choices_v1 r));
END $function$;
CREATE TABLE public.fixture_0137_confirmation_state AS
WITH inputs AS (
  SELECT c.app_user_id,c.workspace_id,c.project_id,g.generation_id,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(p.pending_fact_id::text),
      'source_target_id',upper(p.source_target_id::text)) ORDER BY p.pending_fact_id DESC)
      FROM public.fixture_0137_confirmation_pending p) AS assignments,
    (SELECT jsonb_agg(jsonb_build_object('project_id',upper(s.project_id::text),'source_target_id',upper(s.promotion_target_id::text),
      'candidate_kind',CASE WHEN s.selected_pending_fact_id IS NULL THEN 'current' ELSE 'pending' END,
      'pending_fact_id',upper(s.selected_pending_fact_id::text)) ORDER BY s.project_id DESC,s.promotion_target_id DESC)
      FROM public.fixture_0137_confirmation_slots s) AS choices,
    app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS pending_plan
  FROM public.fixture_0135_project_context c CROSS JOIN public.fixture_0136_resolution_generation g
)
SELECT inputs.*,app_private.plan_personal_merge_project_relationship_resolutions_v1(app_user_id,workspace_id,project_id,generation_id,
    pending_plan->'known_source_plan'->>'fact_fingerprint',pending_plan->>'pending_fingerprint',assignments) AS resolution_plan,
  public.fixture_0137_confirmation_business_state() AS business_state,
  public.fixture_0137_confirmation_business_state(true) AS preserved_state,
  public.fixture_0137_confirmation_function_catalog() AS function_catalog,
  public.fixture_0137_confirmation_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count FROM inputs;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)<>'0137_personal_merge_project_relationship_resolution_plan'
    OR (SELECT result_code FROM public.fixture_0137_confirmation_contact) IS DISTINCT FROM 'accepted'
    OR (SELECT count(*) FROM public.fixture_0137_confirmation_slots)<>2
    OR (SELECT count(*) FROM public.fixture_0137_confirmation_pending)<>3
    OR EXISTS(SELECT 1 FROM public.fixture_0137_confirmation_slots WHERE current_revision<>2)
    OR (SELECT count(*) FROM public.fixture_0137_confirmation_guard_changes)<>3
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1)
    OR NOT EXISTS(SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1)
    OR to_regclass('app_private.personal_merge_project_relationship_resolution_requests_v1') IS NOT NULL
  THEN RAISE EXCEPTION '0137 confirmation upgrade lacks existing raw history, complete pending slots or exact guard deltas'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0137_confirmation_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0137_confirmation_state%ROWTYPE; request_row record; slot record; selected record;
  final_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  parent_row app_data.promotion_target_project_relationships%ROWTYPE;
  expected_fields text[]; chosen_stage integer; chosen_lifecycle text; chosen_note text;
  ended_at timestamptz; replayed_at timestamptz; before_replay jsonb; before_metadata jsonb; drift_choices jsonb; actual_state text;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0137_confirmation_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0138_personal_merge_project_relationship_resolution_confirmation'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version<>'0138_personal_merge_project_relationship_resolution_confirmation') IS DISTINCT FROM saved.migrations
    OR public.fixture_0137_confirmation_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0137_confirmation_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0137_confirmation_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM public.fixture_0137_confirmation_legacy_functions)<>jsonb_array_length(public.fixture_0137_confirmation_function_catalog())
    OR (SELECT count(*) FROM pg_proc p WHERE p.pronamespace IN('app_data'::regnamespace,'app_private'::regnamespace)
      AND NOT EXISTS(SELECT 1 FROM public.fixture_0137_confirmation_legacy_functions old WHERE old.oid=p.oid))<>2
    OR EXISTS(SELECT 1 FROM public.fixture_0137_confirmation_guard_changes c JOIN pg_proc p ON p.oid=c.function_oid
      WHERE length(p.prosrc)-length(replace(p.prosrc,c.new_fragment,''))<>length(c.new_fragment))
    OR (SELECT array_agg(c.relname::text ORDER BY c.relname) FROM pg_class c
      WHERE c.relnamespace IN('app_data'::regnamespace,'app_private'::regnamespace) AND c.relkind='r'
        AND NOT EXISTS(SELECT 1 FROM public.fixture_0137_confirmation_legacy_relations old WHERE old.oid=c.oid))
      IS DISTINCT FROM ARRAY['personal_merge_project_relationship_current_choices_v1',
        'personal_merge_project_relationship_history_applications_v1','personal_merge_project_relationship_resolution_requests_v1']::text[]
    OR EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1)
    OR EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_history_applications_v1)
    OR EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_current_choices_v1)
  THEN RAISE EXCEPTION '0138 changed legacy rows/catalog or exceeded exact old guard extensions'; END IF;
  ended_at:=app_private.confirm_personal_merge_project_relationship_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
    '7f370100-0000-4000-8000-000000000001',saved.generation_id,saved.pending_plan->'known_source_plan'->>'fact_fingerprint',
    saved.pending_plan->>'pending_fingerprint',saved.resolution_plan->>'resolution_fingerprint',saved.assignments,saved.choices);
  SELECT * INTO STRICT request_row FROM app_private.personal_merge_project_relationship_resolution_requests_v1
    WHERE actor_app_user_id=saved.app_user_id AND request_id='7f370100-0000-4000-8000-000000000001';
  IF (SELECT count(*) FROM app_private.personal_merge_project_relationship_resolution_requests_v1)<>1
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_history_applications_v1)<>3
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_current_choices_v1)<>2
    OR request_row.workspace_id IS DISTINCT FROM saved.workspace_id OR request_row.project_id IS DISTINCT FROM saved.project_id
    OR request_row.generation_id IS DISTINCT FROM saved.generation_id
    OR request_row.known_fact_fingerprint IS DISTINCT FROM saved.pending_plan->'known_source_plan'->>'fact_fingerprint'
    OR request_row.pending_fingerprint IS DISTINCT FROM saved.pending_plan->>'pending_fingerprint'
    OR request_row.resolution_fingerprint IS DISTINCT FROM saved.resolution_plan->>'resolution_fingerprint'
    OR NOT isfinite(request_row.confirmed_at_utc) OR ended_at<request_row.confirmed_at_utc
    OR EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1
      WHERE pending_fact_id IN(SELECT pending_fact_id FROM public.fixture_0137_confirmation_pending))
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=saved.generation_id
      AND actor_app_user_id=saved.app_user_id AND request_id=request_row.request_id AND workspace_id=saved.workspace_id
      AND project_id=saved.project_id AND operation='personal_target_known_source_merge_end' AND reason='known_source_split'
      AND outcome='ended' AND ended_at_utc=ended_at AND fact_fingerprint=request_row.post_known_fact_fingerprint)
    OR EXISTS(SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=saved.generation_id)
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions revision
      JOIN public.fixture_0137_confirmation_slots s ON s.promotion_target_id=revision.promotion_target_id AND s.project_id=revision.project_id
      WHERE revision.revision_number>s.current_revision)<>5
    OR public.fixture_0137_confirmation_business_state(true) IS DISTINCT FROM saved.preserved_state
    OR NOT app_private.personal_merge_project_relationship_resolution_proof_v1(saved.app_user_id,request_row.request_id)
  THEN RAISE EXCEPTION '0138 confirmation/end/payload/proof or unrelated old facts drift'; END IF;
  IF EXISTS(
    SELECT 1 FROM (SELECT pending.*,s.current_revision,s.current_stage,s.current_lifecycle_status,
      row_number() OVER(PARTITION BY pending.project_id,pending.source_target_id ORDER BY pending.staged_at_utc,pending.pending_fact_id) AS ordinal
      FROM public.fixture_0137_confirmation_pending pending JOIN public.fixture_0137_confirmation_slots s
        ON s.project_id=pending.project_id AND s.promotion_target_id=pending.source_target_id) expected
    LEFT JOIN app_private.personal_merge_project_relationship_history_applications_v1 application USING(pending_fact_id)
    LEFT JOIN app_data.promotion_target_relationship_revisions revision
      ON revision.promotion_target_id=application.source_target_id AND revision.project_id=application.project_id
        AND revision.revision_number=application.applied_revision_number
    WHERE application.actor_app_user_id IS DISTINCT FROM saved.app_user_id OR application.request_id IS DISTINCT FROM request_row.request_id
      OR application.source_target_id IS DISTINCT FROM expected.source_target_id OR application.project_id IS DISTINCT FROM expected.project_id
      OR application.original_revision_number IS DISTINCT FROM expected.current_revision
      OR application.applied_revision_number IS DISTINCT FROM expected.current_revision+expected.ordinal
      OR revision.old_stage IS DISTINCT FROM expected.current_stage OR revision.old_lifecycle_status IS DISTINCT FROM expected.current_lifecycle_status
      OR revision.new_stage IS DISTINCT FROM expected.new_stage OR revision.new_lifecycle_status IS DISTINCT FROM expected.new_lifecycle_status
      OR revision.follow_up_note IS DISTINCT FROM expected.follow_up_note OR revision.reason_code IS DISTINCT FROM expected.reason_code
      OR revision.reason_detail IS DISTINCT FROM expected.reason_detail OR revision.changed_at IS DISTINCT FROM expected.staged_at_utc
      OR revision.changed_by_app_user_id IS DISTINCT FROM saved.app_user_id OR revision.merge_generation_id IS DISTINCT FROM saved.generation_id
      OR revision.changed_fields IS DISTINCT FROM ARRAY['pending_source_assignment']::text[] OR revision.mutation_id IS NOT NULL
      OR revision.requested_base_revision IS NOT NULL OR revision.requested_stage IS NOT NULL OR revision.requested_lifecycle_status IS NOT NULL
      OR revision.requested_follow_up_note IS NOT NULL OR revision.resolved_conflict_id IS NOT NULL
  ) THEN RAISE EXCEPTION '0138 failed raw pending history, original base, continuous revisions or source binding'; END IF;
  FOR slot IN SELECT * FROM public.fixture_0137_confirmation_slots LOOP
    SELECT * INTO STRICT selected FROM app_private.personal_merge_project_relationship_current_choices_v1
      WHERE actor_app_user_id=saved.app_user_id AND request_id=request_row.request_id
        AND project_id=slot.project_id AND source_target_id=slot.promotion_target_id;
    SELECT * INTO STRICT final_row FROM app_data.promotion_target_relationship_revisions
      WHERE promotion_target_id=slot.promotion_target_id AND project_id=slot.project_id AND revision_number=selected.final_revision_number;
    SELECT * INTO STRICT parent_row FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id=slot.promotion_target_id AND project_id=slot.project_id;
    chosen_stage:=slot.current_stage; chosen_lifecycle:=slot.current_lifecycle_status; chosen_note:=slot.current_follow_up_note;
    IF slot.selected_pending_fact_id IS NOT NULL THEN
      SELECT new_stage,new_lifecycle_status,follow_up_note INTO STRICT chosen_stage,chosen_lifecycle,chosen_note
      FROM public.fixture_0137_confirmation_pending WHERE pending_fact_id=slot.selected_pending_fact_id;
    END IF;
    expected_fields:=ARRAY['pending_current_selection']::text[];
    IF slot.current_stage IS DISTINCT FROM chosen_stage THEN expected_fields:=array_append(expected_fields,'stage'); END IF;
    IF slot.current_lifecycle_status IS DISTINCT FROM chosen_lifecycle THEN expected_fields:=array_append(expected_fields,'lifecycle_status'); END IF;
    IF slot.current_follow_up_note IS DISTINCT FROM chosen_note THEN expected_fields:=array_append(expected_fields,'follow_up_note'); END IF;
    IF selected.original_revision_number IS DISTINCT FROM slot.current_revision
      OR selected.original_merge_generation_id IS DISTINCT FROM slot.merge_generation_id
      OR selected.selected_pending_fact_id IS DISTINCT FROM slot.selected_pending_fact_id
      OR selected.final_revision_number IS DISTINCT FROM slot.current_revision+1+(SELECT count(*) FROM public.fixture_0137_confirmation_pending
        WHERE project_id=slot.project_id AND source_target_id=slot.promotion_target_id)
      OR final_row.old_stage IS DISTINCT FROM slot.current_stage OR final_row.old_lifecycle_status IS DISTINCT FROM slot.current_lifecycle_status
      OR final_row.new_stage IS DISTINCT FROM chosen_stage OR final_row.new_lifecycle_status IS DISTINCT FROM chosen_lifecycle
      OR final_row.follow_up_note IS DISTINCT FROM chosen_note OR final_row.changed_fields IS DISTINCT FROM expected_fields
      OR final_row.reason_code IS DISTINCT FROM 'correction'
      OR final_row.reason_detail IS DISTINCT FROM 'Confirmed pending project relationship current selection'
      OR final_row.changed_by_app_user_id IS DISTINCT FROM saved.app_user_id OR final_row.changed_at IS DISTINCT FROM request_row.confirmed_at_utc
      OR final_row.merge_generation_id IS DISTINCT FROM saved.generation_id OR final_row.mutation_id IS NOT NULL
      OR parent_row.current_revision IS DISTINCT FROM selected.final_revision_number
      OR parent_row.current_stage IS DISTINCT FROM chosen_stage OR parent_row.current_lifecycle_status IS DISTINCT FROM chosen_lifecycle
      OR parent_row.current_follow_up_note IS DISTINCT FROM chosen_note OR parent_row.merge_generation_id IS DISTINCT FROM slot.merge_generation_id
      OR parent_row.updated_by_app_user_id IS DISTINCT FROM saved.app_user_id OR parent_row.updated_at IS DISTINCT FROM request_row.confirmed_at_utc
    THEN RAISE EXCEPTION '0138 explicit current selection, original parent binding or final revision drift'; END IF;
  END LOOP;
  before_replay:=public.fixture_0137_confirmation_business_state(); before_metadata:=public.fixture_0137_confirmation_metadata_state();
  replayed_at:=app_private.confirm_personal_merge_project_relationship_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
    request_row.request_id,saved.generation_id,saved.pending_plan->'known_source_plan'->>'fact_fingerprint',
    saved.pending_plan->>'pending_fingerprint',saved.resolution_plan->>'resolution_fingerprint',saved.assignments,saved.choices);
  IF replayed_at IS DISTINCT FROM ended_at OR public.fixture_0137_confirmation_business_state() IS DISTINCT FROM before_replay
    OR public.fixture_0137_confirmation_metadata_state() IS DISTINCT FROM before_metadata
    OR public.fixture_0137_confirmation_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0137_confirmation_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0138 exact confirmation replay rewrote history, current state, end or metadata'; END IF;
  SELECT jsonb_agg(CASE WHEN choice->>'candidate_kind'='pending' THEN choice||jsonb_build_object('pending_fact_id',
    (SELECT pending_fact_id::text FROM public.fixture_0136_resolution_pending WHERE ordinal=2)) ELSE choice END)
    INTO drift_choices FROM jsonb_array_elements(saved.choices) choice;
  BEGIN
    PERFORM app_private.confirm_personal_merge_project_relationship_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
      request_row.request_id,saved.generation_id,saved.pending_plan->'known_source_plan'->>'fact_fingerprint',
      saved.pending_plan->>'pending_fingerprint',saved.resolution_plan->>'resolution_fingerprint',saved.assignments,drift_choices);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '23505' OR public.fixture_0137_confirmation_business_state() IS DISTINCT FROM before_replay
    OR public.fixture_0137_confirmation_metadata_state() IS DISTINCT FROM before_metadata
  THEN RAISE EXCEPTION '0138 same-valued alternate history choice reused an old request or changed facts'; END IF;
END $function$;
COMMIT;
