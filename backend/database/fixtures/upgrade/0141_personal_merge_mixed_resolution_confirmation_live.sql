\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TABLE public.fixture_0141_confirm_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0141-confirm-upgrade.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0141-confirm-upgrade.example.test','owner') WHERE is_current;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,is_required,
  allow_unknown,allow_refused,allow_not_applicable)
SELECT questionnaire_version_id,'0141_history_answer',1,'0141 retained original answer','boolean',false,true,true,true
FROM public.fixture_0141_confirm_context;
CREATE TABLE public.fixture_0141_confirm_targets AS
SELECT choice.ordinal,(created.target->>'target_id')::uuid AS target_id FROM public.fixture_0141_confirm_context c
CROSS JOIN (VALUES(1),(2),(3)) choice(ordinal)
CROSS JOIN LATERAL app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,'person',
  '0141 mixed source '||choice.ordinal,CASE WHEN choice.ordinal<3 THEN '+1 312 555 0142' END,NULL,
  '0141-confirm-source-'||choice.ordinal) created;
CREATE TABLE public.fixture_0141_confirm_submit AS
SELECT '0141-confirm-entry'::text AS contact_id,submitted.result_code FROM public.fixture_0141_confirm_context c
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id,'0141-confirm-entry-submit',1,'contact.submit.v1',
  '0141-confirm-device','0141-confirm-entry',0,jsonb_build_object('contactId','0141-confirm-entry',
    'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
    'reason','0141 original entry','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',3,'interestLevel',2,'answers','[]'::jsonb,
    'targetLinks',(SELECT jsonb_agg(jsonb_build_object('targetId',target_id,'targetType','person','responseLevel',NULL,
      'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true) ORDER BY ordinal)
      FROM public.fixture_0141_confirm_targets))) submitted;
CREATE TABLE public.fixture_0141_confirm_generation AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,
  '7f410100-0000-4000-8000-000000000001',preview.preview_id,first.target_id,second.target_id,
  first.target_id,second.target_id) AS generation_id
FROM public.fixture_0141_confirm_context c JOIN public.fixture_0141_confirm_targets first ON first.ordinal=1
JOIN public.fixture_0141_confirm_targets second ON second.ordinal=2
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0141-confirm-upgrade.example.test','owner',
  c.project_id,first.target_id,second.target_id) preview;
SELECT result FROM public.fixture_0141_confirm_context c JOIN public.fixture_0141_confirm_targets target ON target.ordinal=1
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,target.target_id,
  1,1,'active','0141 original current note','progress_update',NULL,'0141-confirm-ordinary-update',NULL);
INSERT INTO public.fixture_0141_confirm_submit
SELECT '0141 Mixed | "TEXT": 汉字',submitted.result_code FROM public.fixture_0141_confirm_context c
JOIN public.fixture_0141_confirm_targets target ON target.ordinal=3
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id,'0141-confirm-text-submit',1,'contact.submit.v1',
  '0141-confirm-device','0141 Mixed | "TEXT": 汉字',0,jsonb_build_object('contactId','0141 Mixed | "TEXT": 汉字',
    'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
    'reason','0141 original contact reason','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC',
    'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',2,
    'answers',jsonb_build_array(jsonb_build_object('questionId','0141_history_answer','state','answered','type','boolean','value',true)),
    'targetLinks',jsonb_build_array(jsonb_build_object('targetId',target.target_id,'targetType','person','responseLevel',1,
      'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))) submitted;
CREATE TABLE public.fixture_0141_confirm_contact_pending AS
SELECT 1 AS ordinal,app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f410100-0000-4000-8000-000000000002',g.generation_id,'0141 Mixed | "TEXT": 汉字',1,2,'yes',false,true) AS pending_fact_id,
  target.target_id AS source_target_id FROM public.fixture_0141_confirm_context c CROSS JOIN public.fixture_0141_confirm_generation g
JOIN public.fixture_0141_confirm_targets target ON target.ordinal=1;
INSERT INTO public.fixture_0141_confirm_submit
SELECT '0141 Mixed | "TEXT": 汉字',revised.result_code FROM public.fixture_0141_confirm_context c
JOIN public.fixture_0141_confirm_targets target ON target.ordinal=3
CROSS JOIN LATERAL app_data.apply_contact_revise_v3(c.app_user_id,'0141-confirm-text-revise',1,'contact.revise.v1','0141-confirm-device',
  '0141 Mixed | "TEXT": 汉字',1,(SELECT snapshot FROM app_data.contact_revisions
    WHERE contact_id='0141 Mixed | "TEXT": 汉字' AND revision_number=1)||jsonb_build_object('interestLevel',4,
    'occurredAtUtc','2025-02-03T04:05:06Z','reason','0141 corrected contact reason',
    'answers',jsonb_build_array(jsonb_build_object('questionId','0141_history_answer','state','answered','type','boolean','value',false)),
    'targetLinks',jsonb_build_array(jsonb_build_object('targetId',target.target_id,'targetType','person','responseLevel',4,
      'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))) revised;
INSERT INTO public.fixture_0141_confirm_contact_pending
SELECT 2,app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f410100-0000-4000-8000-000000000003',g.generation_id,'0141 Mixed | "TEXT": 汉字',2,2,'yes',false,true),target.target_id
FROM public.fixture_0141_confirm_context c CROSS JOIN public.fixture_0141_confirm_generation g
JOIN public.fixture_0141_confirm_targets target ON target.ordinal=1;
CREATE TABLE public.fixture_0141_confirm_project_pending AS
SELECT choice.ordinal,staged.*,target.target_id AS source_target_id FROM public.fixture_0141_confirm_context c
CROSS JOIN public.fixture_0141_confirm_generation g
CROSS JOIN (VALUES(1,2,'7f410100-0000-4000-8000-000000000004'::uuid),
  (2,2,'7f410100-0000-4000-8000-000000000005'::uuid),
  (3,1,'7f410100-0000-4000-8000-000000000006'::uuid)) choice(ordinal,source_ordinal,request_id)
JOIN public.fixture_0141_confirm_targets target ON target.ordinal=choice.source_ordinal
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
  choice.request_id,g.generation_id,3,'paused','0141 private equal note','other','0141 private equal reason') staged;
CREATE TABLE public.fixture_0141_confirm_contact_revisions AS
SELECT * FROM app_data.contact_revisions WHERE contact_id='0141 Mixed | "TEXT": 汉字';
CREATE TABLE public.fixture_0141_confirm_parents AS
SELECT r.* FROM app_data.promotion_target_project_relationships r
JOIN public.fixture_0141_confirm_targets t ON t.target_id=r.promotion_target_id;
CREATE TABLE public.fixture_0141_confirm_project_raw AS
SELECT h.*,f.new_stage,f.new_lifecycle_status,f.follow_up_note,f.reason_code,f.reason_detail,p.source_target_id,p.ordinal
FROM public.fixture_0141_confirm_project_pending p
JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 h USING(pending_fact_id)
JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 f USING(pending_fact_id);
CREATE TABLE public.fixture_0141_confirm_relations AS
SELECT c.oid,n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname IN ('app_data','app_private');
CREATE TABLE public.fixture_0141_confirm_functions AS
SELECT p.oid,p.prosrc FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE TABLE public.fixture_0141_confirm_triggers AS
SELECT t.oid FROM pg_trigger t JOIN public.fixture_0141_confirm_relations r ON r.oid=t.tgrelid;
CREATE TABLE public.fixture_0141_confirm_changes(function_oid oid PRIMARY KEY,old_fragment text NOT NULL,new_fragment text NOT NULL);
CREATE FUNCTION public.fixture_0141_confirm_original_source(function_oid oid,source text) RETURNS text LANGUAGE plpgsql AS $function$
DECLARE change record;
BEGIN
  SELECT * INTO change FROM public.fixture_0141_confirm_changes c WHERE c.function_oid=$1;
  IF FOUND THEN source:=replace(source,change.new_fragment,change.old_fragment); END IF;
  RETURN source;
END $function$;
CREATE FUNCTION public.fixture_0141_confirm_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog',jsonb_set(to_jsonb(p),'{prosrc}',
      to_jsonb(public.fixture_0141_confirm_original_source(p.oid,p.prosrc))),
    'definition',public.fixture_0141_confirm_original_source(p.oid,pg_get_functiondef(p.oid))) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0141_confirm_functions old ON old.oid=p.oid
$function$;
CREATE FUNCTION public.fixture_0141_confirm_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',n.nspname,'name',c.relname,'kind',c.relkind,
    'owner',c.relowner,'acl',c.relacl,'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0),
    'constraints',(SELECT jsonb_agg(jsonb_build_object('catalog',to_jsonb(k),'definition',pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid=c.oid),
    'old_triggers',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t
      JOIN public.fixture_0141_confirm_triggers old ON old.oid=t.oid WHERE t.tgrelid=c.oid),
    'index',(SELECT to_jsonb(i) FROM pg_index i WHERE i.indexrelid=c.oid),
    'view',CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid) END) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN public.fixture_0141_confirm_relations old ON old.oid=c.oid
$function$;
CREATE FUNCTION public.fixture_0141_confirm_business_state(allow_confirmation boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb:='{}'::jsonb; expression text; predicate text;
BEGIN
  FOR relation IN SELECT old.* FROM public.fixture_0141_confirm_relations old JOIN pg_class c ON c.oid=old.oid
    WHERE c.relkind='r' ORDER BY nspname,relname LOOP
    expression:='to_jsonb(r)'; predicate:='true';
    IF allow_confirmation THEN
      IF relation.nspname='app_private' AND relation.relname='personal_target_merge_generation_fence_v1' THEN
        expression:='to_jsonb(r)-''epoch''';
      ELSIF relation.nspname='app_private' AND relation.relname IN ('personal_target_merge_active_members_v1','personal_target_merge_end_events_v1',
        'personal_merge_contact_resolution_requests_v1','personal_merge_project_relationship_resolution_requests_v1') THEN
        predicate:='r.generation_id NOT IN (SELECT generation_id FROM public.fixture_0141_confirm_generation)';
      ELSIF relation.nspname='app_private' AND relation.relname IN ('personal_merge_contact_history_applications_v1',
        'personal_merge_contact_current_revisions_v1','personal_merge_contact_current_choices_v1',
        'personal_merge_project_relationship_history_applications_v1','personal_merge_project_relationship_current_choices_v1') THEN
        predicate:='r.request_id<>''7f410100-0000-4000-8000-000000000007''::uuid';
      ELSIF relation.nspname='app_data' THEN
        IF relation.relname IN ('personal_merge_unassigned_contact_facts_v1','personal_merge_unassigned_project_relationship_facts_v1') THEN
          predicate:='r.pending_fact_id NOT IN (SELECT pending_fact_id FROM public.fixture_0141_confirm_contact_pending
            UNION ALL SELECT pending_fact_id FROM public.fixture_0141_confirm_project_pending)';
        ELSIF relation.relname='contacts' THEN
          expression:='CASE WHEN r.contact_id=''0141 Mixed | "TEXT": 汉字'' THEN to_jsonb(r)-''current_revision'' ELSE to_jsonb(r) END';
        ELSIF relation.relname IN ('contact_revisions','contact_answers','contact_target_links','contact_location_provenance','warehouse_outbox') THEN
          predicate:='r.contact_id<>''0141 Mixed | "TEXT": 汉字'' OR r.revision_number<=2';
        ELSIF relation.relname IN ('processed_commands','contact_audit_events') THEN
          predicate:='r.command_id NOT LIKE ''personal-merge-contact-resolve-v1:7f410100-0000-4000-8000-000000000007:%''';
        ELSIF relation.relname='change_feed' THEN
          predicate:='r.aggregate_id<>''0141 Mixed | "TEXT": 汉字'' OR r.revision_number<=2';
        ELSIF relation.relname='promotion_target_relationship_revisions' THEN
          predicate:='NOT EXISTS(SELECT 1 FROM public.fixture_0141_confirm_targets t WHERE t.ordinal<3 AND t.target_id=r.promotion_target_id)
            OR EXISTS(SELECT 1 FROM public.fixture_0141_confirm_parents old WHERE old.promotion_target_id=r.promotion_target_id
              AND old.project_id=r.project_id AND r.revision_number<=old.current_revision)';
        ELSIF relation.relname='promotion_target_project_relationships' THEN
          expression:='CASE WHEN EXISTS(SELECT 1 FROM public.fixture_0141_confirm_targets t WHERE t.ordinal<3 AND t.target_id=r.promotion_target_id)
            THEN to_jsonb(r)-ARRAY[''current_stage'',''current_lifecycle_status'',''current_follow_up_note'',''current_revision'',
              ''updated_by_app_user_id'',''updated_at''] ELSE to_jsonb(r) END';
        END IF;
      END IF;
    END IF;
    EXECUTE format('SELECT coalesce(jsonb_agg(%s ORDER BY (%s)::text),''[]''::jsonb) FROM %I.%I r WHERE %s',
      expression,expression,relation.nspname,relation.relname,predicate) INTO rows;
    state:=state||jsonb_build_object(relation.nspname||'.'||relation.relname,rows);
  END LOOP;
  RETURN state;
END $function$;
DO $application_changes$
DECLARE item record; source text; start_at integer; end_at integer;
BEGIN
  FOR item IN SELECT * FROM (VALUES
    ('app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure,
      E'  FOR item IN\n    SELECT pending.*',
      E'  PERFORM app_private.apply_personal_merge_contact_resolutions_v1(trusted_app_user_id, requested_request_id,\n    requested_generation_id, read_plan, canonical_assignments, canonical_choices);\n'),
    ('app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure,
      '  FOR slot IN SELECT value FROM jsonb_array_elements(read_plan->''source_slots'')',
      E'  PERFORM app_private.apply_personal_merge_project_relationship_resolutions_v1(trusted_app_user_id, requested_request_id,\n    requested_generation_id, read_plan, canonical_assignments, canonical_choices, checked_at);\n')
    ) changes(function_oid,start_anchor,replacement) LOOP
    SELECT prosrc INTO STRICT source FROM pg_proc WHERE oid=item.function_oid;
    start_at:=strpos(source,item.start_anchor); end_at:=strpos(source,'  SELECT manifest.fact_fingerprint INTO post_fingerprint');
    IF start_at=0 OR end_at<=start_at OR length(source)-length(replace(source,item.start_anchor,''))<>length(item.start_anchor)
    THEN RAISE EXCEPTION '0141 exact native application anchor is missing or ambiguous'; END IF;
    INSERT INTO public.fixture_0141_confirm_changes VALUES(item.function_oid,substring(source FROM start_at FOR end_at-start_at),item.replacement);
  END LOOP;
END $application_changes$;
CREATE TABLE public.fixture_0141_confirm_proof_clause AS SELECT
$clause$    OR EXISTS (
      SELECT 1 FROM app_private.personal_merge_unassigned_contact_requests_v1 AS pending
      WHERE pending.generation_id = request_row.generation_id
        AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
          WHERE purge.pending_fact_id = pending.pending_fact_id)
    )$clause$::text AS contact_rejection;
INSERT INTO public.fixture_0141_confirm_changes
SELECT oid,prosrc,$wrapper$
  BEGIN
    IF EXISTS (
      SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1 AS request
      JOIN app_private.personal_merge_unassigned_contact_requests_v1 AS pending
        ON pending.generation_id = request.generation_id
      WHERE request.actor_app_user_id = trusted_app_user_id AND request.request_id = requested_request_id
        AND NOT EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 AS purge
          WHERE purge.pending_fact_id = pending.pending_fact_id)
    ) THEN RETURN false; END IF;
    RETURN app_private.personal_merge_project_relationship_resolution_fact_proof_v1(trusted_app_user_id, requested_request_id);
  END
  $wrapper$
FROM pg_proc WHERE oid='app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid)'::regprocedure;
INSERT INTO public.fixture_0141_confirm_changes VALUES(
  'app_private.guard_personal_merge_unassigned_project_relationship_end_v1()'::regprocedure,
  '      AND app_private.personal_merge_project_relationship_resolution_proof_v1(request.actor_app_user_id, request.request_id)',
$guard$      AND (app_private.personal_merge_project_relationship_resolution_proof_v1(request.actor_app_user_id, request.request_id)
        OR app_private.personal_merge_mixed_resolution_proof_v1(request.actor_app_user_id, request.request_id))$guard$);
CREATE TABLE public.fixture_0141_confirm_state AS
WITH inputs AS (
  SELECT c.*,g.generation_id,
    app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS contact_pending_plan,
    app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS project_pending_plan,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(pending_fact_id::text),'source_target_id',upper(source_target_id::text))
      ORDER BY ordinal DESC) FROM public.fixture_0141_confirm_contact_pending) AS contact_assignments,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(pending_fact_id::text),'source_target_id',upper(source_target_id::text))
      ORDER BY ordinal DESC) FROM public.fixture_0141_confirm_project_pending) AS project_assignments,
    (SELECT jsonb_build_array(jsonb_build_object('contact_id','0141 Mixed | "TEXT": 汉字','source_target_id',upper(source_target_id::text),
      'candidate_kind','pending','pending_fact_id',upper(pending_fact_id::text)))
      FROM public.fixture_0141_confirm_contact_pending WHERE ordinal=1) AS contact_choices,
    (SELECT jsonb_agg(jsonb_build_object('project_id',upper(c.project_id::text),'source_target_id',upper(t.target_id::text),
      'candidate_kind',CASE WHEN t.ordinal=1 THEN 'current' ELSE 'pending' END,'pending_fact_id',
      CASE WHEN t.ordinal=2 THEN (SELECT upper(pending_fact_id::text) FROM public.fixture_0141_confirm_project_pending WHERE ordinal=1) END)
      ORDER BY t.ordinal DESC) FROM public.fixture_0141_confirm_targets t WHERE ordinal<3) AS project_choices
  FROM public.fixture_0141_confirm_context c CROSS JOIN public.fixture_0141_confirm_generation g
)
SELECT inputs.*,app_private.plan_personal_merge_mixed_resolutions_v1(app_user_id,workspace_id,project_id,generation_id,
    contact_pending_plan->'known_source_plan'->>'fact_fingerprint',contact_pending_plan->>'pending_fingerprint',
    project_pending_plan->>'pending_fingerprint',contact_assignments,project_assignments) AS mixed_plan,
  public.fixture_0141_confirm_business_state() AS business_state,public.fixture_0141_confirm_business_state(true) AS preserved_state,
  public.fixture_0141_confirm_function_catalog() AS function_catalog,public.fixture_0141_confirm_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count FROM inputs;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)<>'0141_personal_merge_mixed_resolution_plan'
    OR EXISTS(SELECT 1 FROM public.fixture_0141_confirm_submit WHERE result_code<>'accepted')
    OR (SELECT count(*) FROM public.fixture_0141_confirm_submit)<>3
    OR (SELECT count(*) FROM public.fixture_0141_confirm_contact_pending)<>2
    OR (SELECT count(*) FROM public.fixture_0141_confirm_project_pending)<>3
    OR (SELECT count(*) FROM public.fixture_0141_confirm_parents)<>3
    OR (SELECT count(*) FROM public.fixture_0141_confirm_changes)<>4
    OR EXISTS(SELECT 1 FROM public.fixture_0141_confirm_changes change JOIN pg_proc p ON p.oid=change.function_oid
      WHERE length(p.prosrc)-length(replace(p.prosrc,change.old_fragment,''))<>length(change.old_fragment))
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0141_confirm_state WHERE contact_pending_plan->>'pending_count'='2'
      AND project_pending_plan->>'pending_count'='3' AND jsonb_array_length(mixed_plan->'project_relationship_resolution_plan'->'source_slots')=2)
    OR to_regclass('app_private.personal_merge_mixed_resolution_requests_v1') IS NOT NULL
  THEN RAISE EXCEPTION '0141 mixed confirmation baseline lacks real histories, existing slots or exact four source deltas'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0141_confirm_common_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
BEGIN
  RETURN (SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_merge_mixed_resolution_requests_v1 r);
END $function$;
CREATE FUNCTION public.fixture_0141_confirm_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0141_confirm_state%ROWTYPE; contact_request record; project_request record; common record;
  confirmation_request_id constant uuid:='7f410100-0000-4000-8000-000000000007';
  actual_state text; ended_at timestamptz; replayed_at timestamptz; change record; helper_source text;
  after_state jsonb; after_common jsonb; contact_assignments jsonb; project_assignments jsonb; contact_choices jsonb; project_choices jsonb;
  item record; original jsonb; applied jsonb; expected_links jsonb; final_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  parent_row app_data.promotion_target_project_relationships%ROWTYPE; choice_row record; slot record;
  base_stage integer; base_revision integer; expected_fields text[];
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0141_confirm_state;
  IF (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0142_personal_merge_mixed_resolution_confirmation'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version<>'0142_personal_merge_mixed_resolution_confirmation') IS DISTINCT FROM saved.migrations
    OR public.fixture_0141_confirm_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0141_confirm_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0141_confirm_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))
      <>(SELECT count(*)+5 FROM public.fixture_0141_confirm_functions)
    OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r')
      <>(SELECT count(*)+1 FROM public.fixture_0141_confirm_relations old JOIN pg_class c ON c.oid=old.oid WHERE c.relkind='r')
    OR EXISTS(SELECT 1 FROM app_private.personal_merge_mixed_resolution_requests_v1)
    OR EXISTS(SELECT 1 FROM public.fixture_0141_confirm_changes delta JOIN pg_proc p ON p.oid=delta.function_oid
      WHERE length(p.prosrc)-length(replace(p.prosrc,delta.new_fragment,''))<>length(delta.new_fragment))
  THEN RAISE EXCEPTION '0142 migration changed old rows/catalog or more than the four exact function deltas'; END IF;
  IF (SELECT count(*) FROM pg_trigger t JOIN public.fixture_0141_confirm_relations old ON old.oid=t.tgrelid
      WHERE NOT EXISTS(SELECT 1 FROM public.fixture_0141_confirm_triggers original WHERE original.oid=t.oid))<>6
    OR EXISTS(SELECT 1 FROM pg_trigger t JOIN public.fixture_0141_confirm_relations old ON old.oid=t.tgrelid
      LEFT JOIN pg_constraint k ON k.oid=t.tgconstraint
      WHERE NOT EXISTS(SELECT 1 FROM public.fixture_0141_confirm_triggers original WHERE original.oid=t.oid)
        AND NOT coalesce(t.tgisinternal AND t.tgenabled='O' AND t.tgrelid=k.confrelid
          AND k.conrelid='app_private.personal_merge_mixed_resolution_requests_v1'::regclass
          AND k.conname IN ('pmmr_generation_fk','pmmr_contact_request_fk','pmmr_project_request_fk')
          AND ((t.tgfoid='pg_catalog."RI_FKey_restrict_del"()'::regprocedure AND t.tgtype=9)
            OR (t.tgfoid='pg_catalog."RI_FKey_noaction_upd"()'::regprocedure AND t.tgtype=17)),false))
  THEN RAISE EXCEPTION '0142 old-parent trigger delta is not exactly the six new foreign-key RI triggers'; END IF;
  FOR change IN SELECT * FROM public.fixture_0141_confirm_changes WHERE function_oid IN (
    'app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure,
    'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure) LOOP
    SELECT prosrc INTO STRICT helper_source FROM pg_proc WHERE oid=CASE
      WHEN change.function_oid='app_private.confirm_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)'::regprocedure
      THEN 'app_private.apply_personal_merge_contact_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb)'::regprocedure
      ELSE 'app_private.apply_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,timestamptz)'::regprocedure END;
    IF length(helper_source)-length(replace(helper_source,change.old_fragment,''))<>length(change.old_fragment)
    THEN RAISE EXCEPTION '0142 shared helper did not preserve the complete original application block'; END IF;
  END LOOP;
  IF (SELECT prosrc FROM pg_proc WHERE oid='app_private.personal_merge_project_relationship_resolution_fact_proof_v1(uuid,uuid)'::regprocedure)
    IS DISTINCT FROM (SELECT replace(old.prosrc,clause.contact_rejection,'') FROM public.fixture_0141_confirm_functions old
      CROSS JOIN public.fixture_0141_confirm_proof_clause clause
      WHERE old.oid='app_private.personal_merge_project_relationship_resolution_proof_v1(uuid,uuid)'::regprocedure)
  THEN RAISE EXCEPTION '0142 project fact core differs beyond the original contact-pending refusal'; END IF;
  BEGIN
    PERFORM app_private.confirm_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
      '7f410100-0000-4000-8000-000000000008',saved.generation_id,saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',
      saved.contact_pending_plan->>'pending_fingerprint',saved.mixed_plan->'contact_resolution_plan'->>'resolution_fingerprint',
      saved.contact_assignments,saved.contact_choices);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '55000' OR public.fixture_0141_confirm_business_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0142 widened old contact-only LIVE confirmation or failed to roll it back'; END IF;
  actual_state:=NULL;
  BEGIN
    PERFORM app_private.confirm_personal_merge_project_relationship_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
      '7f410100-0000-4000-8000-000000000009',saved.generation_id,saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',
      saved.project_pending_plan->>'pending_fingerprint',saved.mixed_plan->'project_relationship_resolution_plan'->>'resolution_fingerprint',
      saved.project_assignments,saved.project_choices);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '55000' OR public.fixture_0141_confirm_business_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0142 widened old project-only LIVE confirmation or failed to roll it back'; END IF;
  ended_at:=app_private.confirm_personal_merge_mixed_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
    confirmation_request_id,saved.generation_id,saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',
    saved.contact_pending_plan->>'pending_fingerprint',saved.project_pending_plan->>'pending_fingerprint',saved.mixed_plan->>'resolution_fingerprint',
    saved.contact_assignments,saved.contact_choices,saved.project_assignments,saved.project_choices);
  SELECT r.* INTO STRICT contact_request FROM app_private.personal_merge_contact_resolution_requests_v1 r
    WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id;
  SELECT r.* INTO STRICT project_request FROM app_private.personal_merge_project_relationship_resolution_requests_v1 r
    WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id;
  SELECT r.* INTO STRICT common FROM app_private.personal_merge_mixed_resolution_requests_v1 r
    WHERE r.actor_app_user_id=saved.app_user_id AND r.request_id=confirmation_request_id;
  IF (to_jsonb(contact_request)-ARRAY['pending_fingerprint','resolution_fingerprint'])
      IS DISTINCT FROM (to_jsonb(project_request)-ARRAY['pending_fingerprint','resolution_fingerprint'])
    OR contact_request.workspace_id IS DISTINCT FROM saved.workspace_id OR contact_request.project_id IS DISTINCT FROM saved.project_id
    OR contact_request.generation_id IS DISTINCT FROM saved.generation_id
    OR contact_request.known_fact_fingerprint IS DISTINCT FROM saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint'
    OR contact_request.pending_fingerprint IS DISTINCT FROM saved.contact_pending_plan->>'pending_fingerprint'
    OR project_request.pending_fingerprint IS DISTINCT FROM saved.project_pending_plan->>'pending_fingerprint'
    OR contact_request.resolution_fingerprint IS DISTINCT FROM saved.mixed_plan->'contact_resolution_plan'->>'resolution_fingerprint'
    OR project_request.resolution_fingerprint IS DISTINCT FROM saved.mixed_plan->'project_relationship_resolution_plan'->>'resolution_fingerprint'
    OR common.generation_id IS DISTINCT FROM saved.generation_id OR common.resolution_fingerprint IS DISTINCT FROM saved.mixed_plan->>'resolution_fingerprint'
    OR NOT isfinite(contact_request.confirmed_at_utc) OR ended_at<contact_request.confirmed_at_utc
    OR contact_request.post_known_fact_fingerprint IS DISTINCT FROM
      (SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(saved.generation_id))
    OR (SELECT count(*) FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=saved.generation_id)<>1
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_target_merge_end_events_v1 e WHERE e.actor_app_user_id=saved.app_user_id
      AND e.request_id=confirmation_request_id AND e.generation_id=saved.generation_id AND e.workspace_id=saved.workspace_id
      AND e.project_id=saved.project_id AND e.reason='known_source_split' AND e.operation='personal_target_known_source_merge_end'
      AND e.outcome='ended' AND e.fact_fingerprint=contact_request.post_known_fact_fingerprint AND e.ended_at_utc=ended_at)
    OR EXISTS(SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=saved.generation_id)
    OR EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 f JOIN public.fixture_0141_confirm_contact_pending p USING(pending_fact_id))
    OR EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 f JOIN public.fixture_0141_confirm_project_pending p USING(pending_fact_id))
    OR (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE request_id=confirmation_request_id)<>2
    OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE request_id=confirmation_request_id)<>1
    OR (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE request_id=confirmation_request_id)<>1
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_history_applications_v1 WHERE request_id=confirmation_request_id)<>3
    OR (SELECT count(*) FROM app_private.personal_merge_project_relationship_current_choices_v1 WHERE request_id=confirmation_request_id)<>2
    OR (SELECT count(*) FROM app_private.personal_merge_mixed_resolution_requests_v1)<>1
    OR NOT app_private.personal_merge_contact_resolution_proof_v1(saved.app_user_id,confirmation_request_id)
    OR NOT app_private.personal_merge_project_relationship_resolution_fact_proof_v1(saved.app_user_id,confirmation_request_id)
    OR NOT app_private.personal_merge_mixed_resolution_proof_v1(saved.app_user_id,confirmation_request_id)
    OR app_private.personal_merge_project_relationship_resolution_proof_v1(saved.app_user_id,confirmation_request_id)
    OR public.fixture_0141_confirm_business_state(true) IS DISTINCT FROM saved.preserved_state
  THEN RAISE EXCEPTION '0142 common final manifest/receipts, exact end, consumed payloads, legacy refusal or unrelated facts drift'; END IF;
  FOR item IN SELECT a.*,pending.ordinal FROM app_private.personal_merge_contact_history_applications_v1 a
    JOIN public.fixture_0141_confirm_contact_pending pending USING(pending_fact_id) WHERE a.request_id=confirmation_request_id LOOP
    SELECT snapshot INTO STRICT original FROM public.fixture_0141_confirm_contact_revisions WHERE revision_number=item.ordinal;
    SELECT snapshot INTO STRICT applied FROM app_data.contact_revisions WHERE contact_id=item.contact_id AND revision_number=item.to_revision_number;
    expected_links:=original->'targetLinks'||jsonb_build_array(jsonb_build_object('targetId',item.source_target_id,'targetType','person',
      'responseLevel',2,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true));
    IF item.contact_id IS DISTINCT FROM '0141 Mixed | "TEXT": 汉字' OR item.original_revision_number<>item.ordinal
      OR item.from_revision_number<>item.ordinal+1 OR item.to_revision_number<>item.ordinal+2
      OR (applied-ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM
        (original-ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
      OR applied->'targetLinks' IS DISTINCT FROM expected_links
      OR (SELECT jsonb_agg(to_jsonb(a)-'revision_number' ORDER BY question_id) FROM app_data.contact_answers a
        WHERE a.contact_id=item.contact_id AND a.revision_number=item.to_revision_number) IS DISTINCT FROM
        (SELECT jsonb_agg(to_jsonb(a)-'revision_number' ORDER BY question_id) FROM app_data.contact_answers a
        WHERE a.contact_id=item.contact_id AND a.revision_number=item.original_revision_number)
      OR (SELECT jsonb_agg(to_jsonb(p)-ARRAY['source_id','revision_number','revision_kind','recorded_at_utc']) FROM app_data.contact_location_provenance p
        WHERE p.contact_id=item.contact_id AND p.revision_number=item.to_revision_number) IS DISTINCT FROM
        (SELECT jsonb_agg(to_jsonb(p)-ARRAY['source_id','revision_number','revision_kind','recorded_at_utc']) FROM app_data.contact_location_provenance p
        WHERE p.contact_id=item.contact_id AND p.revision_number=item.original_revision_number)
    THEN RAISE EXCEPTION '0142 contact history lost original event/time/answers/provenance or nonpair links'; END IF;
  END LOOP;
  SELECT snapshot INTO STRICT original FROM public.fixture_0141_confirm_contact_revisions WHERE revision_number=2;
  SELECT snapshot INTO STRICT applied FROM app_data.contact_revisions WHERE contact_id='0141 Mixed | "TEXT": 汉字' AND revision_number=5;
  expected_links:=original->'targetLinks'||jsonb_build_array(jsonb_build_object('targetId',
    (SELECT target_id FROM public.fixture_0141_confirm_targets WHERE ordinal=1),'targetType','person','responseLevel',2,
    'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true));
  IF (applied-ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM
      (original-ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
    OR applied->'targetLinks' IS DISTINCT FROM expected_links
    OR (SELECT current_revision FROM app_data.contacts WHERE contact_id='0141 Mixed | "TEXT": 汉字')<>5
    OR (SELECT count(*) FROM app_data.contact_revisions WHERE contact_id='0141 Mixed | "TEXT": 汉字')<>5
    OR (SELECT array_agg(boolean_value ORDER BY revision_number) FROM app_data.contact_answers
      WHERE contact_id='0141 Mixed | "TEXT": 汉字' AND question_id='0141_history_answer') IS DISTINCT FROM ARRAY[true,false,true,false,false]
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_merge_contact_current_choices_v1 choice
      WHERE choice.actor_app_user_id=saved.app_user_id AND choice.request_id=confirmation_request_id
        AND choice.selected_pending_fact_id=(SELECT pending_fact_id FROM public.fixture_0141_confirm_contact_pending WHERE ordinal=1))
    OR (SELECT count(*) FROM app_data.processed_commands WHERE command_id LIKE
      'personal-merge-contact-resolve-v1:7f410100-0000-4000-8000-000000000007:%')<>3
    OR (SELECT count(*) FROM app_data.contact_audit_events WHERE command_id LIKE
      'personal-merge-contact-resolve-v1:7f410100-0000-4000-8000-000000000007:%')<>3
    OR (SELECT count(*) FROM app_data.change_feed WHERE aggregate_id='0141 Mixed | "TEXT": 汉字' AND revision_number>2)<>3
    OR (SELECT count(*) FROM app_data.warehouse_outbox WHERE contact_id='0141 Mixed | "TEXT": 汉字' AND revision_number>2)<>3
  THEN RAISE EXCEPTION '0142 final contact current did not retain original current/nonpair data and explicit older pending choice'; END IF;
  IF EXISTS(
    SELECT 1 FROM (SELECT raw.*,parent.current_revision,parent.current_stage,parent.current_lifecycle_status,
      row_number() OVER(PARTITION BY raw.project_id,raw.source_target_id ORDER BY raw.staged_at_utc,raw.pending_fact_id) AS sequence
      FROM public.fixture_0141_confirm_project_raw raw JOIN public.fixture_0141_confirm_parents parent
        ON parent.promotion_target_id=raw.source_target_id AND parent.project_id=raw.project_id) expected
    LEFT JOIN app_private.personal_merge_project_relationship_history_applications_v1 a USING(pending_fact_id)
    LEFT JOIN app_data.promotion_target_relationship_revisions v ON v.promotion_target_id=a.source_target_id
      AND v.project_id=a.project_id AND v.revision_number=a.applied_revision_number
    WHERE a.actor_app_user_id IS DISTINCT FROM saved.app_user_id OR a.request_id IS DISTINCT FROM confirmation_request_id
      OR a.source_target_id IS DISTINCT FROM expected.source_target_id OR a.project_id IS DISTINCT FROM expected.project_id
      OR a.original_revision_number IS DISTINCT FROM expected.current_revision
      OR a.applied_revision_number IS DISTINCT FROM expected.current_revision+expected.sequence
      OR v.old_stage IS DISTINCT FROM expected.current_stage OR v.old_lifecycle_status IS DISTINCT FROM expected.current_lifecycle_status
      OR v.new_stage IS DISTINCT FROM expected.new_stage OR v.new_lifecycle_status IS DISTINCT FROM expected.new_lifecycle_status
      OR v.follow_up_note IS DISTINCT FROM expected.follow_up_note OR v.reason_code IS DISTINCT FROM expected.reason_code
      OR v.reason_detail IS DISTINCT FROM expected.reason_detail OR v.changed_at IS DISTINCT FROM expected.staged_at_utc
      OR v.changed_fields IS DISTINCT FROM ARRAY['pending_source_assignment']::text[]
      OR v.changed_by_app_user_id IS DISTINCT FROM saved.app_user_id OR v.merge_generation_id IS DISTINCT FROM saved.generation_id
  ) THEN RAISE EXCEPTION '0142 project history lost same-valued facts, original base, event time or generation binding'; END IF;
  FOR slot IN SELECT t.*,p.current_stage,p.current_revision FROM public.fixture_0141_confirm_targets t
    JOIN public.fixture_0141_confirm_parents p ON p.promotion_target_id=t.target_id WHERE t.ordinal<3 LOOP
    SELECT * INTO STRICT choice_row FROM app_private.personal_merge_project_relationship_current_choices_v1
      WHERE actor_app_user_id=saved.app_user_id AND request_id=confirmation_request_id AND source_target_id=slot.target_id;
    SELECT * INTO STRICT final_row FROM app_data.promotion_target_relationship_revisions
      WHERE promotion_target_id=slot.target_id AND project_id=saved.project_id AND revision_number=4;
    SELECT * INTO STRICT parent_row FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id=slot.target_id AND project_id=saved.project_id;
    expected_fields:=CASE WHEN slot.ordinal=1 THEN ARRAY['pending_current_selection']::text[]
      ELSE ARRAY['pending_current_selection','stage','lifecycle_status','follow_up_note']::text[] END;
    IF choice_row.original_revision_number IS DISTINCT FROM slot.current_revision OR choice_row.final_revision_number<>4
      OR choice_row.original_merge_generation_id IS NOT NULL OR parent_row.merge_generation_id IS NOT NULL
      OR choice_row.selected_pending_fact_id IS DISTINCT FROM (CASE WHEN slot.ordinal=2 THEN
        (SELECT pending_fact_id FROM public.fixture_0141_confirm_project_pending WHERE ordinal=1) END)
      OR final_row.old_stage IS DISTINCT FROM slot.current_stage OR final_row.old_lifecycle_status IS DISTINCT FROM 'active'
      OR final_row.new_stage IS DISTINCT FROM (CASE WHEN slot.ordinal=1 THEN 1 ELSE 3 END)
      OR final_row.new_lifecycle_status IS DISTINCT FROM (CASE WHEN slot.ordinal=1 THEN 'active' ELSE 'paused' END)
      OR final_row.follow_up_note IS DISTINCT FROM (CASE WHEN slot.ordinal=1 THEN '0141 original current note' ELSE '0141 private equal note' END)
      OR final_row.changed_fields IS DISTINCT FROM expected_fields OR final_row.reason_code IS DISTINCT FROM 'correction'
      OR final_row.reason_detail IS DISTINCT FROM 'Confirmed pending project relationship current selection'
      OR final_row.changed_by_app_user_id IS DISTINCT FROM saved.app_user_id OR final_row.changed_at IS DISTINCT FROM contact_request.confirmed_at_utc
      OR final_row.merge_generation_id IS DISTINCT FROM saved.generation_id OR parent_row.current_revision<>4
      OR parent_row.current_stage IS DISTINCT FROM final_row.new_stage OR parent_row.current_lifecycle_status IS DISTINCT FROM final_row.new_lifecycle_status
      OR parent_row.current_follow_up_note IS DISTINCT FROM final_row.follow_up_note
      OR parent_row.updated_at IS DISTINCT FROM contact_request.confirmed_at_utc OR parent_row.updated_by_app_user_id IS DISTINCT FROM saved.app_user_id
    THEN RAISE EXCEPTION '0142 explicit project current, original parent binding or final selection metadata drift'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM app_data.promotion_target_project_relationships r
      JOIN public.fixture_0141_confirm_targets t ON t.target_id=r.promotion_target_id)<>3
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions v
      JOIN public.fixture_0141_confirm_targets t ON t.target_id=v.promotion_target_id WHERE v.reason_code='project_entry')<>3
  THEN RAISE EXCEPTION '0142 confirmation created an unauthorized relationship or project-entry event'; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  after_state:=public.fixture_0141_confirm_business_state(); after_common:=public.fixture_0141_confirm_common_state();
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',(value->>'pending_fact_id')::uuid::text,
    'source_target_id',(value->>'source_target_id')::uuid::text) ORDER BY (value->>'pending_fact_id')::uuid)
    INTO contact_assignments FROM jsonb_array_elements(saved.contact_assignments);
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',(value->>'pending_fact_id')::uuid::text,
    'source_target_id',(value->>'source_target_id')::uuid::text) ORDER BY (value->>'pending_fact_id')::uuid)
    INTO project_assignments FROM jsonb_array_elements(saved.project_assignments);
  SELECT jsonb_agg(value||jsonb_build_object('source_target_id',(value->>'source_target_id')::uuid::text,
    'pending_fact_id',(value->>'pending_fact_id')::uuid::text) ORDER BY value->>'contact_id' COLLATE "C",(value->>'source_target_id')::uuid)
    INTO contact_choices FROM jsonb_array_elements(saved.contact_choices);
  SELECT jsonb_agg(value||jsonb_build_object('project_id',(value->>'project_id')::uuid::text,
    'source_target_id',(value->>'source_target_id')::uuid::text,'pending_fact_id',(value->>'pending_fact_id')::uuid::text)
    ORDER BY (value->>'project_id')::uuid,(value->>'source_target_id')::uuid)
    INTO project_choices FROM jsonb_array_elements(saved.project_choices);
  replayed_at:=app_private.confirm_personal_merge_mixed_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,
    confirmation_request_id,saved.generation_id,saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',
    saved.contact_pending_plan->>'pending_fingerprint',saved.project_pending_plan->>'pending_fingerprint',saved.mixed_plan->>'resolution_fingerprint',
    contact_assignments,contact_choices,project_assignments,project_choices);
  IF replayed_at IS DISTINCT FROM ended_at OR public.fixture_0141_confirm_business_state() IS DISTINCT FROM after_state
    OR public.fixture_0141_confirm_common_state() IS DISTINCT FROM after_common
    OR public.fixture_0141_confirm_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0141_confirm_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0142 canonical mixed replay changed old data, shared metadata, end or catalog'; END IF;
END $function$;
COMMIT;
