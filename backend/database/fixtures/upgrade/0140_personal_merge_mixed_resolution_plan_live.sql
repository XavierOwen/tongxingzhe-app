\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TABLE public.fixture_0140_mixed_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0140-mixed-upgrade.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://0140-mixed-upgrade.example.test','owner') WHERE is_current;
CREATE TABLE public.fixture_0140_mixed_targets AS
SELECT choice.ordinal,(created.target->>'target_id')::uuid AS target_id FROM public.fixture_0140_mixed_context c
CROSS JOIN (VALUES(1),(2)) choice(ordinal)
CROSS JOIN LATERAL app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,'person',
  '0140 mixed source '||choice.ordinal,'+1 312 555 0141',NULL,'0140-mixed-source-'||choice.ordinal) created;
CREATE TABLE public.fixture_0140_mixed_submit AS
SELECT choice.contact_id,submitted.result_code FROM public.fixture_0140_mixed_context c
JOIN public.fixture_0140_mixed_targets target ON target.ordinal=1
CROSS JOIN (VALUES('0140-mixed-entry')) choice(contact_id)
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id,choice.contact_id||'-submit',1,'contact.submit.v1',
  '0140-mixed-device',choice.contact_id,0,jsonb_build_object('contactId',choice.contact_id,
    'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,'reason','0140 original contact reason',
    'occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
    'targetLinks',CASE WHEN choice.contact_id='0140-mixed-entry' THEN jsonb_build_array(jsonb_build_object(
      'targetId',target.target_id,'targetType','person','responseLevel',NULL,'followUpConsent','unknown',
      'institutionRepresentativeConfirmed',false,'confirmStageZero',true)) ELSE '[]'::jsonb END)) submitted;
CREATE TABLE public.fixture_0140_mixed_generation AS
SELECT app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,
  '7f400100-0000-4000-8000-000000000001',preview.preview_id,first.target_id,second.target_id,
  first.target_id,second.target_id) AS generation_id
FROM public.fixture_0140_mixed_context c JOIN public.fixture_0140_mixed_targets first ON first.ordinal=1
JOIN public.fixture_0140_mixed_targets second ON second.ordinal=2
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://0140-mixed-upgrade.example.test','owner',
  c.project_id,first.target_id,second.target_id) preview;
INSERT INTO public.fixture_0140_mixed_submit
SELECT '0140 Mixed | "TEXT": 汉字',submitted.result_code FROM public.fixture_0140_mixed_context c
CROSS JOIN LATERAL app_data.apply_contact_submit_v3(c.app_user_id,'0140-mixed-text-submit',1,'contact.submit.v1',
  '0140-mixed-device','0140 Mixed | "TEXT": 汉字',0,jsonb_build_object('contactId','0140 Mixed | "TEXT": 汉字',
    'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
    'reason','0140 original contact reason','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC',
    'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
    'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) submitted;
SELECT result FROM public.fixture_0140_mixed_context c JOIN public.fixture_0140_mixed_targets target ON target.ordinal=1
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,target.target_id,
  1,1,'active','0140 original shared note','progress_update',NULL,'0140-mixed-ordinary-update',NULL);
CREATE TABLE public.fixture_0140_mixed_contact_pending AS
SELECT 1 AS ordinal,app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f400100-0000-4000-8000-000000000002',g.generation_id,'0140 Mixed | "TEXT": 汉字',1,2,'yes',false,true) AS pending_fact_id,
  target.target_id AS source_target_id FROM public.fixture_0140_mixed_context c CROSS JOIN public.fixture_0140_mixed_generation g
JOIN public.fixture_0140_mixed_targets target ON target.ordinal=1;
INSERT INTO public.fixture_0140_mixed_submit
SELECT '0140 Mixed | "TEXT": 汉字',revised.result_code FROM public.fixture_0140_mixed_context c
CROSS JOIN LATERAL app_data.apply_contact_revise_v3(c.app_user_id,'0140-mixed-revise',1,'contact.revise.v1','0140-mixed-device',
  '0140 Mixed | "TEXT": 汉字',1,(SELECT snapshot FROM app_data.contact_revisions
    WHERE contact_id='0140 Mixed | "TEXT": 汉字' AND revision_number=1)||jsonb_build_object('interestLevel',4,
    'occurredAtUtc','2025-02-03T04:05:06Z','reason','0140 corrected contact reason')) revised;
INSERT INTO public.fixture_0140_mixed_contact_pending
SELECT 2,app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f400100-0000-4000-8000-000000000003',g.generation_id,'0140 Mixed | "TEXT": 汉字',2,2,'yes',false,true),target.target_id
FROM public.fixture_0140_mixed_context c CROSS JOIN public.fixture_0140_mixed_generation g
JOIN public.fixture_0140_mixed_targets target ON target.ordinal=1;
CREATE TABLE public.fixture_0140_mixed_project_pending AS
SELECT choice.ordinal,staged.*,target.target_id AS source_target_id FROM public.fixture_0140_mixed_context c
CROSS JOIN public.fixture_0140_mixed_generation g
CROSS JOIN (VALUES(1,2,'7f400100-0000-4000-8000-000000000004'::uuid),
  (2,2,'7f400100-0000-4000-8000-000000000005'::uuid),
  (3,1,'7f400100-0000-4000-8000-000000000006'::uuid)) choice(ordinal,source_ordinal,request_id)
JOIN public.fixture_0140_mixed_targets target ON target.ordinal=choice.source_ordinal
CROSS JOIN LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
  choice.request_id,g.generation_id,3,'paused','0140 private same project note','other','0140 private same reason') staged;
CREATE TABLE public.fixture_0140_mixed_functions AS
SELECT p.oid FROM pg_proc p WHERE p.pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace);
CREATE FUNCTION public.fixture_0140_mixed_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('catalog',to_jsonb(p),'definition',pg_get_functiondef(p.oid)) ORDER BY p.oid)
  FROM pg_proc p JOIN public.fixture_0140_mixed_functions old ON old.oid=p.oid
$function$;
CREATE FUNCTION public.fixture_0140_mixed_relation_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',n.nspname,'name',c.relname,'kind',c.relkind,
    'owner',c.relowner,'acl',c.relacl,'columns',
    (SELECT jsonb_agg(to_jsonb(a) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0),
    'constraints',(SELECT jsonb_agg(jsonb_build_object('catalog',to_jsonb(k),'definition',pg_get_constraintdef(k.oid)) ORDER BY k.oid)
      FROM pg_constraint k WHERE k.conrelid=c.oid),
    'triggers',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.oid) FROM pg_trigger t WHERE t.tgrelid=c.oid),
    'index',(SELECT to_jsonb(i) FROM pg_index i WHERE i.indexrelid=c.oid),
    'view',CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid) END) ORDER BY c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('app_data','app_private')
$function$;
CREATE FUNCTION public.fixture_0140_mixed_business_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb:='{}'::jsonb;
BEGIN
  FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' ORDER BY n.nspname,c.relname LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',
      relation.nspname,relation.relname) INTO rows;
    state:=state||jsonb_build_object(relation.nspname||'.'||relation.relname,rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE TABLE public.fixture_0140_mixed_state AS
WITH inputs AS (
  SELECT c.*,g.generation_id,
    app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS contact_pending_plan,
    app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id) AS project_pending_plan,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(pending_fact_id::text),'source_target_id',upper(source_target_id::text))
      ORDER BY ordinal DESC) FROM public.fixture_0140_mixed_contact_pending) AS contact_assignments,
    (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(pending_fact_id::text),'source_target_id',upper(source_target_id::text))
      ORDER BY ordinal DESC) FROM public.fixture_0140_mixed_project_pending) AS project_assignments
  FROM public.fixture_0140_mixed_context c CROSS JOIN public.fixture_0140_mixed_generation g
)
SELECT inputs.*,app_private.plan_unassigned_personal_merge_contact_resolutions_v1(app_user_id,workspace_id,project_id,generation_id,
    contact_pending_plan->'known_source_plan'->>'fact_fingerprint',contact_pending_plan->>'pending_fingerprint',contact_assignments) AS contact_plan,
  app_private.plan_personal_merge_project_relationship_resolutions_v1(app_user_id,workspace_id,project_id,generation_id,
    contact_pending_plan->'known_source_plan'->>'fact_fingerprint',project_pending_plan->>'pending_fingerprint',project_assignments) AS project_plan,
  public.fixture_0140_mixed_business_state() AS business_state,public.fixture_0140_mixed_function_catalog() AS function_catalog,
  public.fixture_0140_mixed_relation_catalog() AS relation_catalog,
  (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m) AS migrations,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count FROM inputs;
DO $baseline$
BEGIN
  IF (SELECT max(version) FROM app_migrations.schema_migrations)<>'0140_explicit_project_entry_relationship_resolution'
    OR EXISTS(SELECT 1 FROM public.fixture_0140_mixed_submit WHERE result_code<>'accepted')
    OR (SELECT count(*) FROM public.fixture_0140_mixed_submit)<>3
    OR (SELECT count(*) FROM public.fixture_0140_mixed_contact_pending)<>2
    OR (SELECT count(*) FROM public.fixture_0140_mixed_project_pending)<>3
    OR NOT EXISTS(SELECT 1 FROM public.fixture_0140_mixed_state WHERE contact_plan->'known_source_plan'=project_plan->'known_source_plan'
      AND contact_pending_plan->>'pending_count'='2' AND project_pending_plan->>'pending_count'='3'
      AND jsonb_array_length(contact_plan->'contacts')=1 AND jsonb_array_length(project_plan->'source_slots')=2)
    OR NOT EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1)
    OR NOT EXISTS(SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1)
    OR to_regprocedure('app_private.plan_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)') IS NOT NULL
  THEN RAISE EXCEPTION '0140 mixed upgrade lacks true mixed history, canonical source maps or preserved rich baseline'; END IF;
END $baseline$;
CREATE FUNCTION public.fixture_0140_mixed_assert_upgrade() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE saved public.fixture_0140_mixed_state%ROWTYPE; document jsonb; contact_plan jsonb; project_plan jsonb;
  metadata jsonb; replayed jsonb; contact_assignments jsonb; project_assignments jsonb;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0140_mixed_state;
  IF current_setting('transaction_read_only')<>'on'
    OR (SELECT count(*) FROM app_migrations.schema_migrations)<>saved.migration_count+1
    OR (SELECT max(version) FROM app_migrations.schema_migrations)<>'0141_personal_merge_mixed_resolution_plan'
    OR (SELECT jsonb_agg(to_jsonb(m) ORDER BY version) FROM app_migrations.schema_migrations m
      WHERE version<>'0141_personal_merge_mixed_resolution_plan') IS DISTINCT FROM saved.migrations
    OR public.fixture_0140_mixed_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0140_mixed_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0140_mixed_relation_catalog() IS DISTINCT FROM saved.relation_catalog
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace IN ('app_data'::regnamespace,'app_private'::regnamespace))
      <>(SELECT count(*)+1 FROM public.fixture_0140_mixed_functions)
  THEN RAISE EXCEPTION '0141 migration changed old rows/catalog or more than one new function, or assertion is not READ ONLY'; END IF;
  SELECT app_private.plan_unassigned_personal_merge_contact_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id,
      saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',saved.contact_pending_plan->>'pending_fingerprint',saved.contact_assignments),
    app_private.plan_personal_merge_project_relationship_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id,
      saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',saved.project_pending_plan->>'pending_fingerprint',saved.project_assignments),
    app_private.plan_personal_merge_mixed_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id,
      saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',saved.contact_pending_plan->>'pending_fingerprint',
      saved.project_pending_plan->>'pending_fingerprint',saved.contact_assignments,saved.project_assignments)
    INTO STRICT contact_plan,project_plan,document;
  metadata:=jsonb_build_object('contract_id','personal_merge_mixed_resolution_plan_v1',
    'contact_resolution_plan',contact_plan,'project_relationship_resolution_plan',project_plan);
  IF contact_plan IS DISTINCT FROM saved.contact_plan OR project_plan IS DISTINCT FROM saved.project_plan
    OR document IS DISTINCT FROM metadata||jsonb_build_object('resolution_fingerprint',encode(sha256(convert_to(metadata::text,'UTF8')),'hex'))
    OR document->'contact_resolution_plan'->'known_source_plan' IS DISTINCT FROM document->'project_relationship_resolution_plan'->'known_source_plan'
    OR document->'contact_resolution_plan'->'contacts'->0->>'contact_id' IS DISTINCT FROM '0140 Mixed | "TEXT": 汉字'
    OR public.fixture_0140_mixed_business_state() IS DISTINCT FROM saved.business_state
  THEN RAISE EXCEPTION '0141 exact nested standalone plans, raw TEXT identity, shared snapshot, digest or read-only state drift'; END IF;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',(value->>'pending_fact_id')::uuid::text,
    'source_target_id',(value->>'source_target_id')::uuid::text) ORDER BY (value->>'pending_fact_id')::uuid)
    INTO contact_assignments FROM jsonb_array_elements(saved.contact_assignments);
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',(value->>'pending_fact_id')::uuid::text,
    'source_target_id',(value->>'source_target_id')::uuid::text) ORDER BY (value->>'pending_fact_id')::uuid)
    INTO project_assignments FROM jsonb_array_elements(saved.project_assignments);
  replayed:=app_private.plan_personal_merge_mixed_resolutions_v1(saved.app_user_id,saved.workspace_id,saved.project_id,saved.generation_id,
    saved.contact_pending_plan->'known_source_plan'->>'fact_fingerprint',saved.contact_pending_plan->>'pending_fingerprint',
    saved.project_pending_plan->>'pending_fingerprint',contact_assignments,project_assignments);
  IF replayed IS DISTINCT FROM document OR public.fixture_0140_mixed_business_state() IS DISTINCT FROM saved.business_state
    OR public.fixture_0140_mixed_function_catalog() IS DISTINCT FROM saved.function_catalog
    OR public.fixture_0140_mixed_relation_catalog() IS DISTINCT FROM saved.relation_catalog
  THEN RAISE EXCEPTION '0141 canonical plan replay changed metadata, old facts, fence, context or catalog'; END IF;
END $function$;
COMMIT;
