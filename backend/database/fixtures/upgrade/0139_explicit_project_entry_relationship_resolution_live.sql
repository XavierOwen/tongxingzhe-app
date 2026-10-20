\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TABLE public.fixture_0139_entry_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0139-entry-upgrade.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0139-entry-upgrade.example.test','owner') WHERE is_current;
CREATE TABLE public.fixture_0139_entry_targets AS
SELECT choice.ordinal,(created.target->>'target_id')::uuid AS target_id
FROM public.fixture_0139_entry_context c CROSS JOIN (VALUES(1),(2)) choice(ordinal)
CROSS JOIN LATERAL app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,'person',
  '0139 entry source '||choice.ordinal,'+1 312 555 0140',NULL,'0139-entry-source-'||choice.ordinal) created;
CREATE TABLE public.fixture_0139_entry_contact AS
SELECT submitted.result_code FROM public.fixture_0139_entry_context c JOIN public.fixture_0139_entry_targets t ON t.ordinal=1
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id,'0139-entry-contact-submit',1,'contact.submit.v1',
  '0139-entry-device','0139-entry-contact',0,jsonb_build_object('contactId','0139-entry-contact',
    'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
    'occurredAtUtc',to_char(clock_timestamp()-interval '1 day','YYYY-MM-DD"T"HH24:MI:SS"Z"'),'occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
    'targetLinks',jsonb_build_array(jsonb_build_object('targetId',t.target_id,'targetType','person',
      'responseLevel',NULL,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))) submitted;
CREATE TABLE public.fixture_0139_entry_generation AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,
  '7f390100-0000-4000-8000-000000000001',preview.preview_id,first.target_id,second.target_id,
  first.target_id,second.target_id) AS generation_id
FROM public.fixture_0139_entry_context c JOIN public.fixture_0139_entry_targets first ON first.ordinal=1
JOIN public.fixture_0139_entry_targets second ON second.ordinal=2
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0139-entry-upgrade.example.test','owner',
  c.project_id,first.target_id,second.target_id) preview;
SELECT result FROM public.fixture_0139_entry_context c JOIN public.fixture_0139_entry_targets t ON t.ordinal=1
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,t.target_id,
  1,1,'active','0139 original current note','progress_update',NULL,'0139-entry-ordinary-update',NULL);
CREATE TABLE public.fixture_0139_entry_pending AS
SELECT choice.ordinal,staged.*,choice.source_ordinal FROM public.fixture_0139_entry_context c
CROSS JOIN public.fixture_0139_entry_generation g
CROSS JOIN (VALUES(1,2,'7f390100-0000-4000-8000-000000000002'::uuid),
  (2,2,'7f390100-0000-4000-8000-000000000003'::uuid),
  (3,1,'7f390100-0000-4000-8000-000000000004'::uuid)) choice(ordinal,source_ordinal,request_id)
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,
  c.project_id,choice.request_id,g.generation_id,3,'paused','0139 raw shared note','other','0139 raw reason detail') staged;
CREATE TABLE public.fixture_0139_entry_raw AS
SELECT header.*,payload.new_stage,payload.new_lifecycle_status,payload.follow_up_note,payload.reason_code,payload.reason_detail,
  t.target_id AS source_target_id,p.ordinal
FROM public.fixture_0139_entry_pending p
JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 payload USING(pending_fact_id)
JOIN public.fixture_0139_entry_targets t ON t.ordinal=p.source_ordinal;
CREATE TABLE public.fixture_0139_entry_parents AS
SELECT r.* FROM app_data.promotion_target_project_relationships r JOIN public.fixture_0139_entry_targets t ON t.target_id=r.promotion_target_id;
CREATE TABLE public.fixture_0139_entry_relations AS
SELECT c.oid,n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('app_data','app_private');
CREATE TABLE public.fixture_0139_entry_functions AS
SELECT p.oid FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0139_entry_triggers AS
SELECT t.oid FROM pg_trigger t JOIN public.fixture_0139_entry_relations r ON r.oid=t.tgrelid;
CREATE FUNCTION public.fixture_0139_entry_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog',to_jsonb(p),'definition',pg_get_functiondef(p.oid)) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0139_entry_functions old ON old.oid=p.oid
$function$;
CREATE FUNCTION public.fixture_0139_entry_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',n.nspname,'name',c.relname,'kind',c.relkind,
    'owner',c.relowner,'acl',c.relacl,'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0),
    'constraints',(SELECT jsonb_agg(jsonb_build_object('catalog',to_jsonb(k),'definition',pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid=c.oid),
    'old_triggers',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t
      JOIN public.fixture_0139_entry_triggers old ON old.oid=t.oid WHERE t.tgrelid=c.oid),
    'index',(SELECT to_jsonb(i) FROM pg_index i WHERE i.indexrelid=c.oid),
    'view',CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid) END) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN public.fixture_0139_entry_relations old ON old.oid=c.oid
$function$;
CREATE FUNCTION public.fixture_0139_entry_business_state(allow_confirmation boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb:='{}'::jsonb; expression text; predicate text;
BEGIN
  FOR relation IN SELECT old.* FROM public.fixture_0139_entry_relations old JOIN pg_class c ON c.oid=old.oid
    WHERE c.relkind='r' ORDER BY nspname,relname LOOP
    expression:='to_jsonb(r)'; predicate:='true';
    IF allow_confirmation THEN
      IF relation.nspname='app_private' AND relation.relname='personal_target_merge_generation_fence_v1' THEN
        expression:='to_jsonb(r)-''epoch''';
      ELSIF relation.nspname='app_private' AND relation.relname IN ('personal_target_merge_active_members_v1',
        'personal_target_merge_end_events_v1','personal_merge_project_relationship_resolution_requests_v1') THEN
        predicate:='r.generation_id NOT IN (SELECT generation_id FROM public.fixture_0139_entry_generation)';
      ELSIF relation.nspname='app_private' AND relation.relname='personal_merge_project_relationship_history_applications_v1' THEN
        predicate:='r.pending_fact_id NOT IN (SELECT pending_fact_id FROM public.fixture_0139_entry_pending)';
      ELSIF relation.nspname='app_private' AND relation.relname='personal_merge_project_relationship_current_choices_v1' THEN
        predicate:='r.request_id<>''7f390100-0000-4000-8000-000000000005''::uuid';
      ELSIF relation.nspname='app_data' AND relation.relname='personal_merge_unassigned_project_relationship_facts_v1' THEN
        predicate:='r.pending_fact_id NOT IN (SELECT pending_fact_id FROM public.fixture_0139_entry_pending)';
      ELSIF relation.nspname='app_data' AND relation.relname='promotion_target_relationship_revisions' THEN
        predicate:='NOT EXISTS(SELECT 1 FROM public.fixture_0139_entry_targets t WHERE t.target_id=r.promotion_target_id)
          OR EXISTS(SELECT 1 FROM public.fixture_0139_entry_parents old WHERE old.promotion_target_id=r.promotion_target_id
            AND old.project_id=r.project_id AND r.revision_number<=old.current_revision)';
      ELSIF relation.nspname='app_data' AND relation.relname='promotion_target_project_relationships' THEN
        predicate:='NOT EXISTS(SELECT 1 FROM public.fixture_0139_entry_targets t WHERE t.ordinal=2 AND t.target_id=r.promotion_target_id)';
        expression:='CASE WHEN EXISTS(SELECT 1 FROM public.fixture_0139_entry_parents old WHERE old.promotion_target_id=r.promotion_target_id
          AND old.project_id=r.project_id) THEN to_jsonb(r)-ARRAY[''current_stage'',''current_lifecycle_status'',''current_follow_up_note'',
            ''current_revision'',''updated_by_app_user_id'',''updated_at''] ELSE to_jsonb(r) END';
      END IF;
    END IF;
    EXECUTE format('SELECT coalesce(jsonb_agg(%s ORDER BY (%s)::text),''[]''::jsonb) FROM %I.%I r WHERE %s',
      expression,expression,relation.nspname,relation.relname,predicate) INTO rows;
    state:=state||jsonb_build_object(relation.nspname||'.'||relation.relname,rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE TABLE public.fixture_0139_entry_state AS
WITH inputs AS (
  SELECT c.*,g.generation_id,
    app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS pending_plan,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(pending_fact_id::text),
      'source_target_id',upper(source_target_id::text)) ORDER BY ordinal DESC) FROM public.fixture_0139_entry_raw) AS assignments,
    (SELECT jsonb_agg(jsonb_build_object('project_id',upper(c.project_id::text),'source_target_id',upper(t.target_id::text),
      'candidate_kind',CASE WHEN t.ordinal=1 THEN 'current' ELSE 'pending' END,'pending_fact_id',
      CASE WHEN t.ordinal=2 THEN (SELECT upper(pending_fact_id::text) FROM public.fixture_0139_entry_pending WHERE ordinal=1) END)
      ORDER BY t.ordinal DESC) FROM public.fixture_0139_entry_targets t) AS choices,
    (SELECT jsonb_build_array(jsonb_build_object('project_id',upper(c.project_id::text),'source_target_id',upper(t.target_id::text),
      'pending_fact_id',(SELECT upper(pending_fact_id::text) FROM public.fixture_0139_entry_pending WHERE ordinal=1)))
      FROM public.fixture_0139_entry_targets t WHERE ordinal=2) AS acknowledgements
  FROM public.fixture_0139_entry_context c CROSS JOIN public.fixture_0139_entry_generation g
)
SELECT inputs.*,app_private.plan_personal_merge_project_relationship_resolutions_v1(app_user_id,workspace_id,project_id,generation_id,
    pending_plan->'known_source_plan'->>'fact_fingerprint',pending_plan->>'pending_fingerprint',assignments) AS resolution_plan,
  public.fixture_0139_entry_business_state() AS business_state,public.fixture_0139_entry_business_state(true) AS preserved_state,
  public.fixture_0139_entry_function_catalog() AS function_catalog,public.fixture_0139_entry_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count FROM inputs;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)<>'0139_other_relationship_reason_redaction'
    OR (SELECT result_code FROM public.fixture_0139_entry_contact) IS DISTINCT FROM 'accepted'
    OR NOT EXISTS(SELECT 1 FROM app_data.user_current_projects current_project
      JOIN public.fixture_0139_entry_context c USING(app_user_id) WHERE current_project.project_id=c.project_id)
    OR (SELECT count(*) FROM public.fixture_0139_entry_parents)<>1
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0139_entry_parents WHERE current_revision=2 AND merge_generation_id IS NULL)
    OR (SELECT count(*) FROM public.fixture_0139_entry_pending)<>3
    OR (SELECT jsonb_array_length(resolution_plan->'source_slots') FROM public.fixture_0139_entry_state)<>2
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1)
    OR NOT EXISTS(SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1)
  THEN RAISE EXCEPTION '0139 explicit entry upgrade lacks native mixed slots or preserved rich history'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0139_entry_new_metadata() RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$
BEGIN
  RETURN jsonb_build_object('requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id)
      FROM app_private.personal_merge_project_entry_resolution_requests_v1 r),
    'origins',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id,project_id,source_target_id)
      FROM app_private.personal_merge_project_entry_origins_v1 r));
END
$function$;
CREATE FUNCTION public.fixture_0139_entry_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0139_entry_state%ROWTYPE; wrapper record; inner_request record; origin record;
  confirmation_request_id constant uuid:='7f390100-0000-4000-8000-000000000005';
  missing_target uuid:=(SELECT target_id FROM public.fixture_0139_entry_targets WHERE ordinal=2);
  started_at timestamptz; ended_at timestamptz; replayed_at timestamptz;
  after_state jsonb; after_metadata jsonb; assignments jsonb; choices jsonb; acknowledgements jsonb;
  slot record; final_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  parent_row app_data.promotion_target_project_relationships%ROWTYPE;
  original_stage integer; original_lifecycle text; original_note text; base_revision integer; final_revision integer;
  expected_fields text[];
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0139_entry_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version<>'0140_explicit_project_entry_relationship_resolution') IS DISTINCT FROM saved.migrations
    OR (SELECT count(*) FROM app_migrations.schema_migrations WHERE version='0140_explicit_project_entry_relationship_resolution')<>1
    OR public.fixture_0139_entry_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0139_entry_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0139_entry_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))
      <>(SELECT count(*)+2 FROM public.fixture_0139_entry_functions)
    OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r')
      <>(SELECT count(*)+2 FROM public.fixture_0139_entry_relations old JOIN pg_class c ON c.oid=old.oid WHERE c.relkind='r')
    OR EXISTS(SELECT 1 FROM app_private.personal_merge_project_entry_resolution_requests_v1)
    OR EXISTS(SELECT 1 FROM app_private.personal_merge_project_entry_origins_v1)
  THEN RAISE EXCEPTION '0140 migration changed old rows/functions/catalog or unexpected object count'; END IF;
  started_at:=clock_timestamp();
  ended_at:=app_private.confirm_personal_merge_project_relationship_resolutions_v2(saved.app_user_id,saved.workspace_id,saved.project_id,
    confirmation_request_id,saved.generation_id,saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',
    saved.resolution_plan->>'resolution_fingerprint',saved.assignments,saved.choices,saved.acknowledgements);
  SELECT r.* INTO STRICT wrapper FROM app_private.personal_merge_project_entry_resolution_requests_v1 r
    WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id;
  SELECT r.* INTO STRICT inner_request FROM app_private.personal_merge_project_relationship_resolution_requests_v1 r
    WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id;
  SELECT r.* INTO STRICT origin FROM app_private.personal_merge_project_entry_origins_v1 r
    WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id;
  IF (SELECT count(*) FROM app_private.personal_merge_project_entry_resolution_requests_v1)<>1
    OR (SELECT count(*) FROM app_private.personal_merge_project_entry_origins_v1)<>1
    OR wrapper.workspace_id IS DISTINCT FROM saved.workspace_id OR wrapper.project_id IS DISTINCT FROM saved.project_id
    OR wrapper.generation_id IS DISTINCT FROM saved.generation_id
    OR wrapper.known_fact_fingerprint IS DISTINCT FROM saved.pending_plan->'known_source_plan'->>'fact_fingerprint'
    OR wrapper.pending_fingerprint IS DISTINCT FROM saved.pending_plan->>'pending_fingerprint'
    OR wrapper.resolution_fingerprint IS DISTINCT FROM saved.resolution_plan->>'resolution_fingerprint'
    OR wrapper.internal_known_fact_fingerprint IS DISTINCT FROM inner_request.known_fact_fingerprint
    OR wrapper.internal_resolution_fingerprint IS DISTINCT FROM inner_request.resolution_fingerprint
    OR inner_request.pending_fingerprint IS DISTINCT FROM wrapper.pending_fingerprint
    OR wrapper.internal_known_fact_fingerprint=wrapper.known_fact_fingerprint
    OR wrapper.internal_resolution_fingerprint=wrapper.resolution_fingerprint
    OR NOT isfinite(wrapper.initialized_at_utc) OR wrapper.initialized_at_utc<started_at
    OR inner_request.confirmed_at_utc<wrapper.initialized_at_utc OR ended_at<inner_request.confirmed_at_utc
    OR origin.source_target_id IS DISTINCT FROM missing_target OR origin.project_id IS DISTINCT FROM saved.project_id
    OR origin.pending_fact_id IS DISTINCT FROM (SELECT pending_fact_id FROM public.fixture_0139_entry_pending WHERE ordinal=1)
    OR origin.initial_revision_number<>1 OR origin.initialized_at_utc IS DISTINCT FROM wrapper.initialized_at_utc
    OR NOT EXISTS(SELECT 1 FROM app_data.promotion_target_relationship_revisions v
      JOIN app_data.promotion_target_project_relationships p USING(promotion_target_id,project_id)
      WHERE v.promotion_target_id=missing_target AND v.project_id=saved.project_id AND v.revision_number=1
        AND v.old_stage IS NULL AND v.new_stage=0 AND v.old_lifecycle_status IS NULL AND v.new_lifecycle_status='active'
        AND v.follow_up_note IS NULL AND v.reason_code='project_entry' AND v.reason_detail IS NULL
        AND v.changed_fields=ARRAY['stage','lifecycle_status']::text[] AND v.changed_by_app_user_id=saved.app_user_id
        AND v.changed_at=wrapper.initialized_at_utc AND v.merge_generation_id=saved.generation_id
        AND v.mutation_id IS NULL AND v.requested_base_revision IS NULL AND v.requested_stage IS NULL
        AND v.requested_lifecycle_status IS NULL AND v.requested_follow_up_note IS NULL AND v.resolved_conflict_id IS NULL
        AND p.established_by_app_user_id=saved.app_user_id AND p.established_at=wrapper.initialized_at_utc
        AND p.merge_generation_id=saved.generation_id)
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_target_merge_end_events_v1 e
      WHERE e.actor_app_user_id=saved.app_user_id AND e.request_id=confirmation_request_id
        AND e.workspace_id=saved.workspace_id AND e.project_id=saved.project_id AND e.generation_id=saved.generation_id
        AND e.reason='known_source_split' AND e.operation='personal_target_known_source_merge_end' AND e.outcome='ended'
        AND e.fact_fingerprint=inner_request.post_known_fact_fingerprint AND e.ended_at_utc=ended_at)
    OR EXISTS(SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=saved.generation_id)
    OR EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 payload
      JOIN public.fixture_0139_entry_pending pending USING(pending_fact_id))
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_history_applications_v1 a
      JOIN public.fixture_0139_entry_pending p USING(pending_fact_id))<>3
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_current_choices_v1 r
      WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id)<>2
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions v
      JOIN public.fixture_0139_entry_targets t ON t.target_id=v.promotion_target_id)<>8
    OR (SELECT count(*) FROM app_data.promotion_target_project_relationships r
      JOIN public.fixture_0139_entry_targets t ON t.target_id=r.promotion_target_id)<>2
    OR public.fixture_0139_entry_business_state(true) IS DISTINCT FROM saved.preserved_state
    OR NOT app_private.personal_merge_project_entry_resolution_proof_v1(saved.app_user_id,confirmation_request_id)
    OR NOT app_private.personal_merge_project_relationship_resolution_proof_v1(saved.app_user_id,confirmation_request_id)
  THEN RAISE EXCEPTION '0140 genuine entry/origin/time/internal receipt or contact/consent/unrelated facts drift'; END IF;
  IF EXISTS(
    SELECT 1 FROM (SELECT raw.*,CASE WHEN raw.source_target_id=missing_target THEN 1 ELSE 2 END AS base_revision,
      CASE WHEN raw.source_target_id=missing_target THEN 0 ELSE 1 END AS base_stage,
      row_number() OVER(PARTITION BY raw.source_target_id,raw.project_id ORDER BY raw.staged_at_utc,raw.pending_fact_id) AS sequence
      FROM public.fixture_0139_entry_raw raw) expected
    LEFT JOIN app_private.personal_merge_project_relationship_history_applications_v1 a USING(pending_fact_id)
    LEFT JOIN app_data.promotion_target_relationship_revisions v ON v.promotion_target_id=a.source_target_id
      AND v.project_id=a.project_id AND v.revision_number=a.applied_revision_number
    WHERE a.actor_app_user_id IS DISTINCT FROM saved.app_user_id OR a.request_id IS DISTINCT FROM confirmation_request_id
      OR a.source_target_id IS DISTINCT FROM expected.source_target_id OR a.project_id IS DISTINCT FROM expected.project_id
      OR a.original_revision_number IS DISTINCT FROM expected.base_revision
      OR a.applied_revision_number IS DISTINCT FROM expected.base_revision+expected.sequence
      OR v.old_stage IS DISTINCT FROM expected.base_stage OR v.old_lifecycle_status IS DISTINCT FROM 'active'
      OR v.new_stage IS DISTINCT FROM expected.new_stage OR v.new_lifecycle_status IS DISTINCT FROM expected.new_lifecycle_status
      OR v.follow_up_note IS DISTINCT FROM expected.follow_up_note OR v.reason_code IS DISTINCT FROM expected.reason_code
      OR v.reason_detail IS DISTINCT FROM expected.reason_detail OR v.changed_at IS DISTINCT FROM expected.staged_at_utc
      OR v.changed_by_app_user_id IS DISTINCT FROM saved.app_user_id OR v.merge_generation_id IS DISTINCT FROM saved.generation_id
      OR v.changed_fields IS DISTINCT FROM ARRAY['pending_source_assignment']::text[] OR v.mutation_id IS NOT NULL
      OR v.requested_base_revision IS NOT NULL OR v.requested_stage IS NOT NULL OR v.requested_lifecycle_status IS NOT NULL
      OR v.requested_follow_up_note IS NOT NULL OR v.resolved_conflict_id IS NOT NULL
  ) THEN RAISE EXCEPTION '0140 wrapper lost raw pending history, original stage-zero/current base or source binding'; END IF;
  FOR slot IN SELECT * FROM public.fixture_0139_entry_targets LOOP
    original_stage:=CASE WHEN slot.ordinal=1 THEN 1 ELSE 0 END;
    original_lifecycle:='active'; original_note:=CASE WHEN slot.ordinal=1 THEN '0139 original current note' END;
    base_revision:=CASE WHEN slot.ordinal=1 THEN 2 ELSE 1 END;
    final_revision:=4;
    SELECT * INTO STRICT final_row FROM app_data.promotion_target_relationship_revisions
      WHERE promotion_target_id=slot.target_id AND project_id=saved.project_id AND revision_number=final_revision;
    SELECT * INTO STRICT parent_row FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id=slot.target_id AND project_id=saved.project_id;
    expected_fields:=CASE WHEN slot.ordinal=1 THEN ARRAY['pending_current_selection']::text[]
      ELSE ARRAY['pending_current_selection','stage','lifecycle_status','follow_up_note']::text[] END;
    IF final_row.old_stage IS DISTINCT FROM original_stage OR final_row.old_lifecycle_status IS DISTINCT FROM original_lifecycle
      OR final_row.new_stage IS DISTINCT FROM (CASE WHEN slot.ordinal=1 THEN 1 ELSE 3 END)
      OR final_row.new_lifecycle_status IS DISTINCT FROM (CASE WHEN slot.ordinal=1 THEN 'active' ELSE 'paused' END)
      OR final_row.follow_up_note IS DISTINCT FROM (CASE WHEN slot.ordinal=1 THEN original_note ELSE '0139 raw shared note' END)
      OR final_row.changed_fields IS DISTINCT FROM expected_fields OR final_row.reason_code IS DISTINCT FROM 'correction'
      OR final_row.reason_detail IS DISTINCT FROM 'Confirmed pending project relationship current selection'
      OR final_row.changed_at IS DISTINCT FROM inner_request.confirmed_at_utc OR final_row.changed_by_app_user_id IS DISTINCT FROM saved.app_user_id
      OR final_row.merge_generation_id IS DISTINCT FROM saved.generation_id
      OR parent_row.current_revision IS DISTINCT FROM final_revision OR parent_row.current_stage IS DISTINCT FROM final_row.new_stage
      OR parent_row.current_lifecycle_status IS DISTINCT FROM final_row.new_lifecycle_status
      OR parent_row.current_follow_up_note IS DISTINCT FROM final_row.follow_up_note
      OR parent_row.updated_by_app_user_id IS DISTINCT FROM saved.app_user_id OR parent_row.updated_at IS DISTINCT FROM inner_request.confirmed_at_utc
      OR NOT EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_current_choices_v1 choice
        WHERE choice.actor_app_user_id=saved.app_user_id AND choice.request_id=confirmation_request_id
          AND choice.source_target_id=slot.target_id AND choice.project_id=saved.project_id
          AND choice.original_revision_number=base_revision AND choice.final_revision_number=final_revision
          AND choice.selected_pending_fact_id IS NOT DISTINCT FROM CASE WHEN slot.ordinal=2 THEN origin.pending_fact_id END
          AND choice.original_merge_generation_id IS NOT DISTINCT FROM CASE WHEN slot.ordinal=2 THEN saved.generation_id END)
    THEN RAISE EXCEPTION '0140 explicit current selection, original parent binding or final revision drift'; END IF;
  END LOOP;
  after_state:=public.fixture_0139_entry_business_state(); after_metadata:=public.fixture_0139_entry_new_metadata();
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',(item->>'pending_fact_id')::uuid::text,
    'source_target_id',(item->>'source_target_id')::uuid::text) ORDER BY (item->>'pending_fact_id')::uuid)
    INTO assignments FROM jsonb_array_elements(saved.assignments) item;
  SELECT jsonb_agg(jsonb_build_object('project_id',(item->>'project_id')::uuid::text,'source_target_id',(item->>'source_target_id')::uuid::text,
    'candidate_kind',item->>'candidate_kind','pending_fact_id',(item->>'pending_fact_id')::uuid::text)
    ORDER BY (item->>'source_target_id')::uuid) INTO choices FROM jsonb_array_elements(saved.choices) item;
  SELECT jsonb_agg(jsonb_build_object('project_id',(item->>'project_id')::uuid::text,'source_target_id',(item->>'source_target_id')::uuid::text,
    'pending_fact_id',(item->>'pending_fact_id')::uuid::text)) INTO acknowledgements FROM jsonb_array_elements(saved.acknowledgements) item;
  replayed_at:=app_private.confirm_personal_merge_project_relationship_resolutions_v2(saved.app_user_id,saved.workspace_id,saved.project_id,
    confirmation_request_id,saved.generation_id,saved.pending_plan->'known_source_plan'->>'fact_fingerprint',saved.pending_plan->>'pending_fingerprint',
    saved.resolution_plan->>'resolution_fingerprint',assignments,choices,acknowledgements);
  IF replayed_at IS DISTINCT FROM ended_at OR public.fixture_0139_entry_business_state() IS DISTINCT FROM after_state
    OR public.fixture_0139_entry_new_metadata() IS DISTINCT FROM after_metadata
    OR public.fixture_0139_entry_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0139_entry_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0140 canonical replay changed entry, raw history, current values, end or old catalog'; END IF;
END $function$;
COMMIT;
