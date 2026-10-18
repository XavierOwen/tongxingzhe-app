\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0130_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0130.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0130.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0130_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0130.example.test','other');
CREATE TEMP TABLE fixture_0130_projects ON COMMIT DROP AS SELECT 'a'::text AS name,c.* FROM fixture_0130_context c;
INSERT INTO fixture_0130_projects SELECT 'b',p.* FROM app_data.create_personal_project_context('https://synthetic-0130.example.test','owner','0130 project B') p;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,is_required,allow_unknown,allow_refused,allow_not_applicable,maximum_length)
SELECT questionnaire_version_id,'old_' || name,1,'0130 retained answer ' || name,CASE name WHEN 'b' THEN 'long_text' ELSE 'boolean' END,false,true,true,true,
 CASE name WHEN 'b' THEN 2000 ELSE NULL END FROM fixture_0130_projects;
INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current) VALUES ('0130-region-v1','draft',false);
INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind) VALUES
 ('0130-country','0130-region-v1',NULL,'0130 Country','country'),('0130-city','0130-region-v1','0130-country','0130 City','city'),
 ('0130-venue','0130-region-v1','0130-city','0130 Venue','venue');
INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
VALUES ('0130-boundary','0130-venue','0130-region-v1',polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))');
SELECT app_private.publish_canonical_region_tree_v1('0130-region-v1',true);
CREATE TEMP TABLE fixture_0130_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid,old_generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0130_pairs VALUES
 ('person','7f300000-0000-4000-8000-00000000000a','7f300000-0000-4000-8000-00000000000b',NULL,NULL),
 ('institution','7f300000-0000-4000-8000-00000000000c','7f300000-0000-4000-8000-00000000000d',NULL,NULL);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.id,c.workspace_id,p.kind,'0130 original private source','+1 312 555 0130',c.app_user_id
FROM fixture_0130_context c CROSS JOIN fixture_0130_pairs p CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(id);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id)
SELECT '7f300000-0000-4000-8000-00000000000e',workspace_id,'person','0130 unrelated original',app_user_id FROM fixture_0130_context;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id FROM fixture_0130_context c JOIN app_data.promotion_targets t USING(workspace_id);
DO $activate$
DECLARE c record; p record; preview uuid; generation uuid; fingerprint text;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0130_context;
 PERFORM app_data.select_personal_project_context('https://synthetic-0130.example.test','owner',c.project_id);
 FOR p IN SELECT * FROM fixture_0130_pairs LOOP
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0130.example.test','owner',c.project_id,p.first_target,p.second_target);
  generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target);
  SELECT fact_fingerprint INTO STRICT fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(generation);
  PERFORM app_private.end_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,fingerprint);
  UPDATE fixture_0130_pairs SET old_generation_id = generation WHERE kind = p.kind;
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0130.example.test','owner',c.project_id,p.first_target,p.second_target);
  UPDATE fixture_0130_pairs SET generation_id = app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target) WHERE kind = p.kind;
 END LOOP;
END $activate$;
CREATE TEMP TABLE fixture_0130_contacts(contact text PRIMARY KEY,project_name text,kind text) ON COMMIT DROP;
INSERT INTO fixture_0130_contacts VALUES ('0130 A | "TEXT": 汉字','a','person'),('0130-a','b','person'),('0130-institution','a','institution');
CREATE FUNCTION pg_temp.fixture_0130_submit(contact text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; result record;
BEGIN
 SELECT p.* INTO STRICT c FROM fixture_0130_contacts t JOIN fixture_0130_projects p ON p.name = t.project_name WHERE t.contact = $1;
 PERFORM app_data.select_personal_project_context('https://synthetic-0130.example.test','owner',c.project_id);
 SELECT s.* INTO result FROM app_data.apply_contact_submit_v3(c.app_user_id,contact || '-submit',1,'contact.submit.v1','0130-device',contact,0,
  jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
   'reason','0130 historical original','occurredAtUtc','2025-05-03T04:05:06.123456Z','occurredTimeZone','America/Chicago',
   'channel',CASE WHEN contact = '0130 A | "TEXT": 汉字' OR c.name = 'b' THEN 'face_to_face' ELSE 'video_call' END,
   'location',CASE WHEN contact = '0130 A | "TEXT": 汉字' THEN jsonb_build_object('kind','resolved','placeName','0130 Venue','smallestRegionId','0130-venue','regionTreeVersion','0130-region-v1')
    WHEN c.name = 'b' THEN jsonb_build_object('kind','pending_resolution','latitude',41.7897,'longitude',-87.5997,'accuracyMeters',8.5) ELSE jsonb_build_object('kind','not_applicable') END,
   'reachCount',2,'interestLevel',3,
   'answers',jsonb_build_array(jsonb_build_object('questionId','old_' || c.name,'state','answered','type',CASE c.name WHEN 'b' THEN 'long_text' ELSE 'boolean' END,
    'value',CASE c.name WHEN 'b' THEN to_jsonb('0130 B original text: 汉字'::text) ELSE 'true'::jsonb END)),
   'targetLinks',jsonb_build_array(jsonb_build_object('targetId','7f300000-0000-4000-8000-00000000000e','targetType','person','responseLevel',1,
    'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
  || CASE WHEN contact = '0130 A | "TEXT": 汉字' THEN jsonb_build_object('locationSource',jsonb_build_object('kind','captured_coordinates','latitude',41.7897,'longitude',-87.5997,'accuracyMeters',8.5,
   'resolverContractVersion','canonical-region-resolution:v1','regionTreeContentFingerprint',(SELECT content_fingerprint FROM app_data.canonical_region_tree_releases WHERE tree_version = '0130-region-v1'))) ELSE '{}'::jsonb END) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0130 submit rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0130_submit(contact) FROM fixture_0130_contacts ORDER BY contact COLLATE "C";
CREATE TEMP TABLE fixture_0130_pending(kind text,contact text,pending_fact_id uuid,source_target_id uuid,original_revision integer,response integer,consent text,representative boolean,entry boolean) ON COMMIT DROP;
CREATE FUNCTION pg_temp.fixture_0130_stage(contact text,source uuid,response integer,consent text,representative boolean,entry boolean) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; generation uuid; revision integer; pending uuid;
BEGIN
 SELECT p.*,t.kind INTO STRICT c FROM fixture_0130_contacts t JOIN fixture_0130_projects p ON p.name = t.project_name WHERE t.contact = $1;
 PERFORM app_data.select_personal_project_context('https://synthetic-0130.example.test','owner',c.project_id);
 SELECT generation_id INTO STRICT generation FROM fixture_0130_pairs WHERE kind = c.kind;
 SELECT current_revision INTO STRICT revision FROM app_data.contacts WHERE contact_id = $1;
 pending := app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,contact,revision,response,consent,representative,entry);
 INSERT INTO fixture_0130_pending VALUES(c.kind,contact,pending,source,revision,response,consent,representative,entry);
END $function$;
CREATE FUNCTION pg_temp.fixture_0130_revise(contact text,links jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; old app_data.contacts%ROWTYPE; snapshot jsonb; result record;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0130_context;
 SELECT * INTO STRICT old FROM app_data.contacts WHERE contact_id = $1;
 SELECT r.snapshot INTO STRICT snapshot FROM app_data.contact_revisions r WHERE r.contact_id = $1 AND r.revision_number = old.current_revision;
 SELECT s.* INTO result FROM app_data.apply_contact_revise_v3(c.app_user_id,contact || '-revise-' || old.current_revision,1,'contact.revise.v1','0130-device',contact,old.current_revision,
  snapshot || jsonb_build_object('reason','0130 revision ' || old.current_revision,'interestLevel',old.current_revision % 5,
   'occurredAtUtc',timestamptz '2025-05-03T04:05:06.123456Z' + old.current_revision * interval '1 day 1 microsecond',
   'answers',jsonb_build_array(CASE WHEN contact = '0130-a' THEN jsonb_build_object('questionId','old_b','state','answered','type','long_text','value','0130 B revised text ' || old.current_revision || ': 不同答案')
    ELSE jsonb_build_object('questionId','old_a','state',CASE old.current_revision WHEN 2 THEN 'unknown' WHEN 3 THEN 'refused' ELSE 'answered' END,'type','boolean',
     'value',CASE old.current_revision WHEN 1 THEN 'false'::jsonb WHEN 2 THEN 'null'::jsonb WHEN 3 THEN 'null'::jsonb ELSE 'true'::jsonb END) END))
  || CASE WHEN contact = '0130 A | "TEXT": 汉字' THEN jsonb_build_object('locationSource',(snapshot->'locationSource') || jsonb_build_object('latitude',41.7897 + old.current_revision * 0.0001,'accuracyMeters',8.5 + old.current_revision))
    WHEN contact = '0130-a' THEN jsonb_build_object('location',(snapshot->'location') || jsonb_build_object('latitude',41.7897 + old.current_revision * 0.0001,'accuracyMeters',8.5 + old.current_revision)) ELSE '{}'::jsonb END
  || CASE WHEN links IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('targetLinks',links) END) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0130 revise rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0130_stage('0130 A | "TEXT": 汉字','7f300000-0000-4000-8000-00000000000a',0,'yes',false,true);
SELECT pg_temp.fixture_0130_revise('0130 A | "TEXT": 汉字');
SELECT pg_temp.fixture_0130_stage('0130 A | "TEXT": 汉字','7f300000-0000-4000-8000-00000000000a',4,'no',false,true);
SELECT pg_temp.fixture_0130_revise('0130 A | "TEXT": 汉字');
SELECT pg_temp.fixture_0130_stage('0130 A | "TEXT": 汉字','7f300000-0000-4000-8000-00000000000b',0,'yes',false,true);
SELECT pg_temp.fixture_0130_revise('0130 A | "TEXT": 汉字',(SELECT r.snapshot->'targetLinks' FROM app_data.contact_revisions r WHERE contact_id = '0130 A | "TEXT": 汉字' AND revision_number = 3) || jsonb_build_array(
 jsonb_build_object('targetId','7f300000-0000-4000-8000-00000000000a','targetType','person','responseLevel',NULL,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true),
 jsonb_build_object('targetId','7f300000-0000-4000-8000-00000000000b','targetType','person','responseLevel',3,'followUpConsent','refused','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
-- Simulate bindings that predate this generation while retaining the original snapshot and business values.
ALTER TABLE app_data.contact_target_links DISABLE TRIGGER contact_target_links_merge_generation_immutable;
UPDATE app_data.contact_target_links SET merge_generation_id = CASE WHEN promotion_target_id = '7f300000-0000-4000-8000-00000000000a' THEN NULL ELSE (SELECT old_generation_id FROM fixture_0130_pairs WHERE kind = 'person') END
WHERE contact_id = '0130 A | "TEXT": 汉字' AND revision_number = 4 AND promotion_target_id IN ('7f300000-0000-4000-8000-00000000000a','7f300000-0000-4000-8000-00000000000b');
ALTER TABLE app_data.contact_target_links ENABLE TRIGGER contact_target_links_merge_generation_immutable;
SELECT pg_temp.fixture_0130_stage('0130-a','7f300000-0000-4000-8000-00000000000b',2,'yes',false,true);
SELECT pg_temp.fixture_0130_revise('0130-a');
SELECT pg_temp.fixture_0130_stage('0130-a','7f300000-0000-4000-8000-00000000000b',2,'yes',false,true);
SELECT pg_temp.fixture_0130_stage('0130-institution','7f300000-0000-4000-8000-00000000000c',NULL,'not_applicable',false,true);
SELECT pg_temp.fixture_0130_revise('0130-institution');
SELECT pg_temp.fixture_0130_stage('0130-institution','7f300000-0000-4000-8000-00000000000d',4,'yes',true,true);
DO $publish$
DECLARE c record; draft jsonb;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0130_context;
 PERFORM app_data.select_personal_project_context('https://synthetic-0130.example.test','owner',c.project_id);
 SELECT d.draft INTO STRICT draft FROM app_data.create_questionnaire_draft(c.app_user_id,c.workspace_id,c.project_id,c.questionnaire_version_id) d;
 PERFORM app_data.update_questionnaire_draft(c.app_user_id,c.workspace_id,c.project_id,(draft->>'draft_id')::uuid,1,
  '[{"question_id":"new_required","position":1,"prompt":"0130 new required answer","type":"boolean","required":true,"allow_unknown":false,"allow_refused":false,"allow_not_applicable":false}]'::jsonb);
 PERFORM app_data.publish_questionnaire_draft(c.app_user_id,c.workspace_id,c.project_id,(draft->>'draft_id')::uuid,2,'0130-publish','0130 newer published schema');
END $publish$;
SELECT count(*) FROM fixture_0130_projects p CROSS JOIN LATERAL app_data.select_personal_project_context('https://synthetic-0130.example.test','owner',p.project_id) s WHERE p.name = 'b';
CREATE TEMP TABLE fixture_0130_plans(kind text PRIMARY KEY,generation_id uuid,request_id uuid,pending_plan jsonb,assignments jsonb,document jsonb,choices jsonb) ON COMMIT DROP;
INSERT INTO fixture_0130_plans SELECT p.kind,p.generation_id,gen_random_uuid(),
 app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id),
 (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',n.pending_fact_id,'source_target_id',n.source_target_id) ORDER BY n.pending_fact_id) FROM fixture_0130_pending n WHERE n.kind = p.kind),NULL,NULL
FROM fixture_0130_pairs p CROSS JOIN fixture_0130_context c CROSS JOIN fixture_0130_projects b WHERE b.name = 'b';
UPDATE fixture_0130_plans p SET document = app_private.plan_unassigned_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
 p.pending_plan->'known_source_plan'->>'fact_fingerprint',p.pending_plan->>'pending_fingerprint',p.assignments)
FROM fixture_0130_context c CROSS JOIN fixture_0130_projects b WHERE b.name = 'b';
UPDATE fixture_0130_plans p SET choices = (SELECT jsonb_agg(jsonb_build_object('contact_id',s->>'contact_id','source_target_id',s->>'source_target_id',
 'candidate_kind',CASE WHEN s->>'contact_id' = '0130 A | "TEXT": 汉字' AND s->>'source_target_id' = '7f300000-0000-4000-8000-00000000000b' THEN 'current' ELSE 'pending' END,
 'pending_fact_id',CASE WHEN s->>'contact_id' = '0130 A | "TEXT": 汉字' AND s->>'source_target_id' = '7f300000-0000-4000-8000-00000000000b' THEN NULL ELSE
 (SELECT n.pending_fact_id::text FROM fixture_0130_pending n WHERE n.contact = s->>'contact_id' AND n.source_target_id = (s->>'source_target_id')::uuid ORDER BY n.original_revision,n.pending_fact_id LIMIT 1) END)
 ORDER BY s->>'contact_id' COLLATE "C",(s->>'source_target_id')::uuid) FROM jsonb_array_elements(p.document->'source_slots') s);
CREATE FUNCTION pg_temp.fixture_0130_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
 FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('app_data','app_private') AND c.relkind = 'r' ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
  state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
 END LOOP;
 RETURN state;
END $function$;
CREATE FUNCTION pg_temp.fixture_0130_confirm(kind text,mapping jsonb DEFAULT NULL,choices jsonb DEFAULT NULL,request uuid DEFAULT NULL) RETURNS timestamptz LANGUAGE sql AS $function$
 SELECT app_private.confirm_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,
  (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = c.app_user_id),coalesce($4,p.request_id),p.generation_id,
  p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.document->>'resolution_fingerprint',coalesce($2,p.assignments),coalesce($3,p.choices))
 FROM fixture_0130_context c CROSS JOIN fixture_0130_plans p WHERE p.kind = $1
$function$;
CREATE FUNCTION pg_temp.fixture_0130_expect(expected text,command text,expected_detail text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_0130_state(); actual text; detail text;
BEGIN
 BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE,detail = MESSAGE_TEXT; END;
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '0130 expected %, got % (%): %',expected,actual,detail,command; END IF;
 IF expected_detail IS NOT NULL AND detail IS DISTINCT FROM expected_detail THEN RAISE EXCEPTION '0130 expected error %, got %',expected_detail,detail; END IF;
 IF before_state IS DISTINCT FROM pg_temp.fixture_0130_state() THEN RAISE EXCEPTION '0130 failed operation changed persisted state'; END IF;
END $function$;
SELECT pg_temp.fixture_0130_expect(expected,format('SELECT pg_temp.fixture_0130_confirm(''person'',%L::jsonb)',value)) FROM fixture_0130_plans CROSS JOIN LATERAL (VALUES
 ('22023','null'::jsonb),('22023','{}'::jsonb),('22023','[]'::jsonb),('22023','[null]'::jsonb),('22023','[{}]'::jsonb),
 ('22023',assignments || jsonb_build_array(assignments->0)),('22023',jsonb_set(assignments,'{0,extra}','true')),
 ('22023',jsonb_set(assignments,'{0}',(assignments->0) - 'source_target_id')),
 ('22023',jsonb_set(assignments,'{0,pending_fact_id}','4')),('22023',jsonb_set(assignments,'{0,source_target_id}','"bad"')),
 ('23505',assignments - 0),('23505',jsonb_set(assignments,'{0,source_target_id}','"7f300000-0000-4000-8000-00000000000e"'))
) t(expected,value) WHERE kind = 'person';
SELECT pg_temp.fixture_0130_expect(expected,format('SELECT pg_temp.fixture_0130_confirm(''person'',NULL,%L::jsonb)',value)) FROM fixture_0130_plans CROSS JOIN LATERAL (VALUES
 ('22023','null'::jsonb),('22023','{}'::jsonb),('22023','[]'::jsonb),('22023','[null]'::jsonb),('22023','[{}]'::jsonb),
 ('22023',choices || jsonb_build_array(choices->0)),('22023',jsonb_set(choices,'{0,extra}','true')),
 ('22023',jsonb_set(choices,'{0}',(choices->0) - 'pending_fact_id')),
 ('22023',jsonb_set(choices,'{0,pending_fact_id}','null')),('22023',jsonb_set(choices,'{1,pending_fact_id}',to_jsonb(gen_random_uuid()::text))),
 ('22023',jsonb_set(choices,'{0,contact_id}','4')),('22023',jsonb_set(choices,'{0,candidate_kind}','"latest"')),
 ('23505',choices - 0),('23505',choices - 2),('23505',jsonb_set(choices,'{0,pending_fact_id}',to_jsonb(gen_random_uuid()::text))),
 ('23505',jsonb_set(choices,'{2}',(choices->2) || '{"candidate_kind":"current","pending_fact_id":null}'::jsonb)),
 ('23505',jsonb_set(choices,'{0,contact_id}','"0130 unknown"'))
) t(expected,value) WHERE kind = 'person';
SELECT pg_temp.fixture_0130_expect(expected,format('SELECT app_private.confirm_personal_merge_contact_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
 CASE WHEN field = 'actor_null' THEN NULL WHEN field = 'other' THEN o.app_user_id ELSE c.app_user_id END,
 CASE WHEN field = 'workspace_null' THEN NULL ELSE c.workspace_id END,CASE WHEN field = 'project_null' THEN NULL ELSE b.project_id END,
 CASE WHEN field = 'request_null' THEN NULL ELSE p.request_id END,CASE WHEN field = 'generation_null' THEN NULL ELSE p.generation_id END,
 CASE WHEN field = 'known_null' THEN NULL WHEN field = 'known_bad' THEN 'bad' WHEN field = 'known_stale' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
 CASE WHEN field = 'pending_null' THEN NULL WHEN field = 'pending_bad' THEN 'bad' WHEN field = 'pending_stale' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,
 CASE WHEN field = 'resolution_null' THEN NULL WHEN field = 'resolution_bad' THEN 'bad' WHEN field = 'resolution_stale' THEN repeat('0',64) ELSE p.document->>'resolution_fingerprint' END,
 CASE WHEN field = 'assignments_null' THEN NULL ELSE p.assignments END,CASE WHEN field = 'choices_null' THEN NULL ELSE p.choices END))
FROM fixture_0130_context c CROSS JOIN fixture_0130_other o CROSS JOIN fixture_0130_projects b CROSS JOIN fixture_0130_plans p CROSS JOIN (VALUES
 ('actor_null','22023'),('workspace_null','22023'),('project_null','22023'),('request_null','22023'),('generation_null','22023'),
 ('known_null','22023'),('known_bad','22023'),('pending_null','22023'),('pending_bad','22023'),('resolution_null','22023'),('resolution_bad','22023'),
 ('assignments_null','22023'),('choices_null','22023'),('known_stale','23505'),('pending_stale','23505'),('resolution_stale','23505'),('other','42501')) t(field,expected)
WHERE p.kind = 'person' AND b.name = 'b';
SELECT pg_temp.fixture_0130_expect('23505',format('SELECT pg_temp.fixture_0130_confirm(''person'',%L::jsonb)',jsonb_set(assignments,'{0,source_target_id}',
 to_jsonb(CASE assignments->0->>'source_target_id' WHEN '7f300000-0000-4000-8000-00000000000a' THEN '7f300000-0000-4000-8000-00000000000b' ELSE '7f300000-0000-4000-8000-00000000000a' END)))) FROM fixture_0130_plans WHERE kind = 'person';
SELECT pg_temp.fixture_0130_expect('23505',format('SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
 c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.assignments))
FROM fixture_0130_context c CROSS JOIN fixture_0130_projects b CROSS JOIN fixture_0130_plans p WHERE b.name = 'b' AND p.kind = 'person';
SAVEPOINT current_revision_drift;
SELECT pg_temp.fixture_0130_revise('0130-a');
SELECT pg_temp.fixture_0130_expect('23505',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT current_revision_drift;
RELEASE SAVEPOINT current_revision_drift;
SAVEPOINT pending_inventory_drift;
SELECT pg_temp.fixture_0130_revise('0130-a');
SELECT pg_temp.fixture_0130_stage('0130-a','7f300000-0000-4000-8000-00000000000a',1,'no',false,true);
SELECT pg_temp.fixture_0130_expect('23505',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT pending_inventory_drift;
RELEASE SAVEPOINT pending_inventory_drift;
CREATE FUNCTION pg_temp.fixture_0130_suppress() RETURNS trigger LANGUAGE plpgsql AS $function$ BEGIN RETURN NULL; END $function$;
DO $suppressed$
DECLARE relation text;
BEGIN
 FOREACH relation IN ARRAY ARRAY['app_private.personal_merge_contact_resolution_requests_v1','app_private.personal_merge_contact_history_applications_v1',
  'app_private.personal_merge_contact_current_revisions_v1','app_private.personal_merge_contact_current_choices_v1','app_private.personal_target_merge_end_events_v1'] LOOP
  EXECUTE format('CREATE TRIGGER fixture_0130_suppress BEFORE INSERT ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0130_suppress()',relation);
  PERFORM pg_temp.fixture_0130_expect('55000',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
  EXECUTE format('DROP TRIGGER fixture_0130_suppress ON %s',relation);
 END LOOP;
END $suppressed$;
SAVEPOINT suppressed_delete;
CREATE TRIGGER fixture_0130_suppress BEFORE DELETE ON app_data.personal_merge_unassigned_contact_facts_v1 FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0130_suppress();
SELECT pg_temp.fixture_0130_expect('55000',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT suppressed_delete;
RELEASE SAVEPOINT suppressed_delete;
SAVEPOINT occupied_history;
INSERT INTO app_data.processed_commands(app_user_id,command_id,protocol_version,command_type,device_id,aggregate_id,result_code,server_cursor)
SELECT c.app_user_id,'personal-merge-contact-resolve-v1:' || p.request_id || ':pending:' || n.pending_fact_id,1,'contact.revise.v1','0130-occupied',n.contact,'accepted',gen_random_uuid()
FROM fixture_0130_context c CROSS JOIN fixture_0130_plans p JOIN fixture_0130_pending n USING(kind) WHERE n.contact = '0130-a' AND n.original_revision = 2;
SELECT pg_temp.fixture_0130_expect('23505',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT occupied_history;
RELEASE SAVEPOINT occupied_history;
SAVEPOINT occupied_current;
INSERT INTO app_data.processed_commands(app_user_id,command_id,protocol_version,command_type,device_id,aggregate_id,result_code,server_cursor)
SELECT c.app_user_id,'personal-merge-contact-resolve-v1:' || p.request_id || ':current:' || octet_length('0130-a') || ':0130-a',1,'contact.revise.v1','0130-occupied','0130-a','accepted',gen_random_uuid()
FROM fixture_0130_context c CROSS JOIN fixture_0130_plans p WHERE p.kind = 'person';
SELECT pg_temp.fixture_0130_expect('23505',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT occupied_current;
RELEASE SAVEPOINT occupied_current;
CREATE FUNCTION pg_temp.fixture_0130_reject_child() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.command_id LIKE 'personal-merge-contact-resolve-v1:%:current:6:0130-a' THEN NEW.result_code := 'conflict'; NEW.server_cursor := NULL; NEW.failure_code := '0130_injected_conflict'; END IF;
 RETURN NEW;
END $function$;
SAVEPOINT corrupt_final_receipt;
CREATE TRIGGER fixture_0130_reject_child BEFORE INSERT ON app_data.processed_commands FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0130_reject_child();
SELECT pg_temp.fixture_0130_expect('55000',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT corrupt_final_receipt;
RELEASE SAVEPOINT corrupt_final_receipt;
CREATE FUNCTION pg_temp.fixture_0130_suppress_final_provenance() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.contact_id = '0130-a' AND NEW.revision_number = 5 THEN RETURN NULL; END IF;
 RETURN NEW;
END $function$;
SAVEPOINT missing_final_provenance;
CREATE TRIGGER fixture_0130_suppress_final_provenance BEFORE INSERT ON app_data.contact_location_provenance FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0130_suppress_final_provenance();
SELECT pg_temp.fixture_0130_expect('55000',$$SELECT pg_temp.fixture_0130_confirm('person')$$,'pending contact resolution applications are incomplete');
ROLLBACK TO SAVEPOINT missing_final_provenance;
RELEASE SAVEPOINT missing_final_provenance;
CREATE FUNCTION pg_temp.fixture_0130_corrupt_after_end() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE affected bigint;
BEGIN
 IF EXISTS (SELECT 1 FROM fixture_0130_plans p CROSS JOIN fixture_0130_context c CROSS JOIN fixture_0130_projects b
  WHERE p.kind = 'person' AND b.name = 'b' AND NEW.actor_app_user_id = c.app_user_id AND NEW.request_id = p.request_id AND NEW.generation_id = p.generation_id
   AND NEW.workspace_id = c.workspace_id AND NEW.project_id = b.project_id AND NEW.operation = 'personal_target_known_source_merge_end' AND NEW.reason = 'known_source_split' AND NEW.outcome = 'ended') THEN
  UPDATE app_data.processed_commands SET result_code = 'conflict',server_cursor = NULL,failure_code = '0130_after_end_conflict'
  WHERE app_user_id = NEW.actor_app_user_id AND command_id = 'personal-merge-contact-resolve-v1:' || NEW.request_id || ':current:6:0130-a';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 THEN RAISE EXCEPTION '0130 after-end injection missed the final child'; END IF;
 END IF;
 RETURN NEW;
END $function$;
SAVEPOINT corrupt_after_end;
CREATE TRIGGER fixture_0130_corrupt_after_end AFTER INSERT ON app_private.personal_target_merge_end_events_v1 FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0130_corrupt_after_end();
SELECT pg_temp.fixture_0130_expect('55000',$$SELECT pg_temp.fixture_0130_confirm('person')$$,'pending contact resolution final proof is incomplete');
ROLLBACK TO SAVEPOINT corrupt_after_end;
RELEASE SAVEPOINT corrupt_after_end;
CREATE FUNCTION pg_temp.fixture_0130_conflict_later_child() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.aggregate_id = '0130 A | "TEXT": 汉字' AND NEW.command_id LIKE 'personal-merge-contact-resolve-v1:%:current:%' THEN
  INSERT INTO app_data.processed_commands(app_user_id,command_id,protocol_version,command_type,device_id,aggregate_id,result_code,server_cursor,failure_code)
  SELECT NEW.app_user_id,'personal-merge-contact-resolve-v1:' || p.request_id || ':current:6:0130-a',1,'contact.revise.v1','personal-merge-contact-resolve-v1','0130-a','conflict',NULL,'0130_injected_conflict'
  FROM fixture_0130_plans p WHERE kind = 'person';
 END IF;
 RETURN NEW;
END $function$;
SAVEPOINT failed_final_child;
CREATE TRIGGER fixture_0130_conflict_later_child AFTER INSERT ON app_data.processed_commands FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0130_conflict_later_child();
SELECT pg_temp.fixture_0130_expect('23505',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT failed_final_child;
RELEASE SAVEPOINT failed_final_child;
SAVEPOINT inactive_historical_link;
UPDATE app_data.promotion_targets SET status = 'anonymized',anonymized_at = clock_timestamp(),anonymization_reason = 'withdrawal' WHERE promotion_target_id = '7f300000-0000-4000-8000-00000000000e';
SELECT pg_temp.fixture_0130_expect('23505',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT inactive_historical_link;
RELEASE SAVEPOINT inactive_historical_link;
SAVEPOINT historical_schema_mismatch;
UPDATE app_data.contact_revisions SET snapshot = jsonb_set(snapshot,'{questionnaireVersionId}',to_jsonb((SELECT questionnaire_version_id::text FROM fixture_0130_projects WHERE name = 'b')))
WHERE contact_id = '0130 A | "TEXT": 汉字' AND revision_number = 1;
SELECT pg_temp.fixture_0130_expect('55000',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT historical_schema_mismatch;
RELEASE SAVEPOINT historical_schema_mismatch;
SAVEPOINT due_source;
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months' WHERE promotion_target_id = '7f300000-0000-4000-8000-00000000000a';
SELECT pg_temp.fixture_0130_expect('42501',$$SELECT pg_temp.fixture_0130_confirm('person')$$);
ROLLBACK TO SAVEPOINT due_source;
RELEASE SAVEPOINT due_source;
CREATE TEMP TABLE fixture_0130_before_revisions ON COMMIT DROP AS SELECT r.* FROM app_data.contact_revisions r JOIN fixture_0130_contacts t ON t.contact = r.contact_id;
CREATE TEMP TABLE fixture_0130_before_answers ON COMMIT DROP AS SELECT a.* FROM app_data.contact_answers a JOIN fixture_0130_contacts t ON t.contact = a.contact_id;
CREATE TEMP TABLE fixture_0130_before_provenance ON COMMIT DROP AS SELECT p.* FROM app_data.contact_location_provenance p JOIN fixture_0130_contacts t ON t.contact = p.contact_id;
CREATE TEMP TABLE fixture_0130_before_links ON COMMIT DROP AS SELECT l.* FROM app_data.contact_target_links l JOIN fixture_0130_contacts t ON t.contact = l.contact_id;
CREATE TEMP TABLE fixture_0130_before_contacts ON COMMIT DROP AS SELECT c.* FROM app_data.contacts c JOIN fixture_0130_contacts t ON t.contact = c.contact_id;
CREATE TEMP TABLE fixture_0130_payloads ON COMMIT DROP AS SELECT f.* FROM app_data.personal_merge_unassigned_contact_facts_v1 f JOIN fixture_0130_pending n USING(pending_fact_id);
DO $distinct_original_facts$
BEGIN
 IF (SELECT array_agg((snapshot->>'occurredAtUtc')::timestamptz ORDER BY revision_number) FROM fixture_0130_before_revisions WHERE contact_id = '0130 A | "TEXT": 汉字') IS DISTINCT FROM
  ARRAY[timestamptz '2025-05-03T04:05:06.123456Z',timestamptz '2025-05-04T04:05:06.123457Z',timestamptz '2025-05-05T04:05:06.123458Z',timestamptz '2025-05-06T04:05:06.123459Z']
  OR (SELECT jsonb_agg(jsonb_build_object('state',answer_state,'type',answer_type,'value',boolean_value) ORDER BY revision_number) FROM fixture_0130_before_answers WHERE contact_id = '0130 A | "TEXT": 汉字') IS DISTINCT FROM
   '[{"state":"answered","type":"boolean","value":true},{"state":"answered","type":"boolean","value":false},{"state":"unknown","type":"boolean","value":null},{"state":"refused","type":"boolean","value":null}]'::jsonb
  OR (SELECT array_agg(text_value ORDER BY revision_number) FROM fixture_0130_before_answers WHERE contact_id = '0130-a' AND answer_type = 'long_text' AND boolean_value IS NULL AND number_value IS NULL)
   IS DISTINCT FROM ARRAY['0130 B original text: 汉字','0130 B revised text 1: 不同答案']
  OR (SELECT count(DISTINCT snapshot->>'occurredAtUtc') FROM fixture_0130_before_revisions WHERE contact_id = '0130-a') <> 2
  OR (SELECT count(DISTINCT latitude) FROM fixture_0130_before_provenance WHERE contact_id = '0130 A | "TEXT": 汉字' AND evidence_kind = 'resolved_from_coordinates' AND region_tree_version = '0130-region-v1') <> 4
  OR (SELECT count(DISTINCT latitude) FROM fixture_0130_before_provenance WHERE contact_id = '0130-a' AND evidence_kind = 'pending_coordinates') <> 2
 THEN RAISE EXCEPTION '0130 setup must distinguish historical timestamps, typed answers and location sources'; END IF;
END $distinct_original_facts$;
CREATE TEMP TABLE fixture_0130_results(kind text PRIMARY KEY,confirmed_at timestamptz) ON COMMIT DROP;
INSERT INTO fixture_0130_results SELECT kind,pg_temp.fixture_0130_confirm(kind) FROM fixture_0130_plans WHERE kind = 'institution';
SET LOCAL track_functions = 'all';
CREATE TEMP TABLE fixture_0130_proof_calls ON COMMIT DROP AS
SELECT coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'app_private.personal_merge_contact_resolution_proof_v1(uuid,uuid)'::regprocedure),0) AS before_calls;
INSERT INTO fixture_0130_results SELECT kind,pg_temp.fixture_0130_confirm(kind) FROM fixture_0130_plans WHERE kind = 'person';
DO $proof_call_count$
BEGIN
 IF coalesce((SELECT calls FROM pg_stat_xact_user_functions WHERE funcid = 'app_private.personal_merge_contact_resolution_proof_v1(uuid,uuid)'::regprocedure),0)
  - (SELECT before_calls FROM fixture_0130_proof_calls) <> 3 THEN RAISE EXCEPTION '0130 confirmation must run exactly three full-batch proofs'; END IF;
END $proof_call_count$;
SET CONSTRAINTS ALL IMMEDIATE;
DO $success$
DECLARE n record; t record; original jsonb; applied jsonb; current_snapshot jsonb; final_snapshot jsonb; expected_revision integer; choice jsonb;
BEGIN
 IF (SELECT count(*) FROM app_private.personal_merge_contact_resolution_requests_v1 WHERE workspace_id = (SELECT workspace_id FROM fixture_0130_context)) <> 2
  OR (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0130_pending)) <> 7
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE contact_id IN (SELECT contact FROM fixture_0130_contacts)) <> 3
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE contact_id IN (SELECT contact FROM fixture_0130_contacts)) <> 5
  OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0130_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0130_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id IN (SELECT generation_id FROM fixture_0130_pairs))
 THEN RAISE EXCEPTION '0130 exact history/current receipts, payload consumption or merge end drift'; END IF;
 IF EXISTS (SELECT 1 FROM fixture_0130_before_revisions b LEFT JOIN app_data.contact_revisions r USING(contact_id,revision_number) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(r))
  OR EXISTS (SELECT 1 FROM fixture_0130_before_answers b LEFT JOIN app_data.contact_answers a USING(contact_id,revision_number,question_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(a))
  OR EXISTS (SELECT 1 FROM fixture_0130_before_links b LEFT JOIN app_data.contact_target_links l USING(contact_id,revision_number,promotion_target_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(l))
  OR EXISTS (SELECT 1 FROM fixture_0130_before_provenance b LEFT JOIN app_data.contact_location_provenance p USING(source_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(p))
 THEN RAISE EXCEPTION '0130 rewrote original revisions, answers, NULL binding or old generation binding'; END IF;
 FOR t IN SELECT b.*,p.request_id,p.generation_id FROM fixture_0130_before_contacts b JOIN fixture_0130_contacts fixture_contact ON fixture_contact.contact = b.contact_id JOIN fixture_0130_plans p USING(kind) ORDER BY b.contact_id COLLATE "C" LOOP
  expected_revision := t.current_revision;
  FOR n IN SELECT * FROM fixture_0130_pending WHERE contact = t.contact_id ORDER BY original_revision,pending_fact_id LOOP
   expected_revision := expected_revision + 1;
   SELECT snapshot INTO STRICT original FROM fixture_0130_before_revisions WHERE contact_id = n.contact AND revision_number = n.original_revision;
   SELECT snapshot INTO STRICT applied FROM app_data.contact_revisions WHERE contact_id = n.contact AND revision_number = expected_revision;
   IF (original - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM (applied - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
    OR (applied->>'occurredAtUtc')::timestamptz IS DISTINCT FROM (original->>'occurredAtUtc')::timestamptz
    OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = n.original_revision)
     IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = expected_revision)
    OR (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM fixture_0130_before_provenance p WHERE contact_id = n.contact AND revision_number = n.original_revision)
     IS DISTINCT FROM (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM app_data.contact_location_provenance p WHERE contact_id = n.contact AND revision_number = expected_revision)
    OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links l WHERE contact_id = n.contact AND revision_number = expected_revision AND promotion_target_id = n.source_target_id
     AND response_level IS NOT DISTINCT FROM n.response AND follow_up_consent = n.consent AND institution_representative_confirmed = n.representative AND confirmed_project_entry = n.entry AND merge_generation_id = t.generation_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.processed_commands p WHERE p.app_user_id = t.app_user_id AND p.command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':pending:' || n.pending_fact_id AND p.result_code = 'accepted' AND p.server_cursor IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_history_applications_v1 a WHERE a.pending_fact_id = n.pending_fact_id AND a.actor_app_user_id = t.app_user_id AND a.request_id = t.request_id
     AND a.contact_id = n.contact AND a.original_revision_number = n.original_revision AND a.from_revision_number = expected_revision - 1 AND a.to_revision_number = expected_revision AND a.source_target_id = n.source_target_id
     AND a.child_command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':pending:' || n.pending_fact_id)
   THEN RAISE EXCEPTION '0130 historical application lost snapshot, answers, explicit business values or accepted child: %/%',n.contact,n.original_revision; END IF;
  END LOOP;
  expected_revision := expected_revision + 1;
  SELECT snapshot INTO STRICT current_snapshot FROM fixture_0130_before_revisions WHERE contact_id = t.contact_id AND revision_number = t.current_revision;
  SELECT snapshot INTO STRICT final_snapshot FROM app_data.contact_revisions WHERE contact_id = t.contact_id AND revision_number = expected_revision;
  IF (current_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM (final_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
   OR (final_snapshot->>'occurredAtUtc')::timestamptz IS DISTINCT FROM (current_snapshot->>'occurredAtUtc')::timestamptz
   OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM fixture_0130_before_answers a WHERE contact_id = t.contact_id AND revision_number = t.current_revision)
    IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = t.contact_id AND revision_number = expected_revision)
   OR (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM fixture_0130_before_provenance p WHERE contact_id = t.contact_id AND revision_number = t.current_revision)
    IS DISTINCT FROM (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM app_data.contact_location_provenance p WHERE contact_id = t.contact_id AND revision_number = expected_revision)
   OR NOT EXISTS (SELECT 1 FROM app_data.contacts c WHERE c.contact_id = t.contact_id AND c.current_revision = expected_revision AND c.project_id = t.project_id AND c.questionnaire_version_id = t.questionnaire_version_id AND c.occurred_at_utc = t.occurred_at_utc)
   OR NOT EXISTS (SELECT 1 FROM app_data.processed_commands p WHERE p.app_user_id = t.app_user_id AND p.command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':current:' || octet_length(t.contact_id) || ':' || t.contact_id AND p.result_code = 'accepted' AND p.server_cursor IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_current_revisions_v1 a WHERE a.actor_app_user_id = t.app_user_id AND a.request_id = t.request_id AND a.contact_id = t.contact_id
    AND a.original_revision_number = t.current_revision AND a.from_revision_number = expected_revision - 1 AND a.to_revision_number = expected_revision
    AND a.child_command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':current:' || octet_length(t.contact_id) || ':' || t.contact_id)
   OR jsonb_array_length(final_snapshot->'targetLinks') <> 1 + (SELECT count(*) FROM fixture_0130_plans p CROSS JOIN LATERAL jsonb_array_elements(p.choices) value WHERE value->>'contact_id' = t.contact_id)
  THEN RAISE EXCEPTION '0130 final current snapshot, old questionnaire, event time or child drift: %',t.contact_id; END IF;
  FOR choice IN SELECT value FROM fixture_0130_plans p CROSS JOIN LATERAL jsonb_array_elements(p.choices) WHERE value->>'contact_id' = t.contact_id LOOP
   IF choice->>'candidate_kind' = 'current' THEN
    IF NOT EXISTS (SELECT 1 FROM fixture_0130_before_links b JOIN app_data.contact_target_links l USING(contact_id,promotion_target_id)
     WHERE b.contact_id = t.contact_id AND b.revision_number = t.current_revision AND l.revision_number = expected_revision AND l.promotion_target_id = (choice->>'source_target_id')::uuid
     AND (to_jsonb(b) - ARRAY['revision_number','merge_generation_id']) = (to_jsonb(l) - ARRAY['revision_number','merge_generation_id']) AND l.merge_generation_id = t.generation_id)
    THEN RAISE EXCEPTION '0130 explicit current choice lost original business values'; END IF;
   ELSE
    IF NOT EXISTS (SELECT 1 FROM fixture_0130_pending selected_pending JOIN app_data.contact_target_links l ON l.contact_id = selected_pending.contact AND l.promotion_target_id = selected_pending.source_target_id
     WHERE selected_pending.pending_fact_id = (choice->>'pending_fact_id')::uuid AND l.revision_number = expected_revision AND l.response_level IS NOT DISTINCT FROM selected_pending.response
     AND l.follow_up_consent = selected_pending.consent AND l.institution_representative_confirmed = selected_pending.representative AND l.confirmed_project_entry = selected_pending.entry AND l.merge_generation_id = t.generation_id)
    THEN RAISE EXCEPTION '0130 explicit older pending choice was replaced or folded'; END IF;
   END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_data.contact_revisions r WHERE r.contact_id = t.contact_id AND r.revision_number > t.current_revision
   AND (NOT EXISTS (SELECT 1 FROM app_data.change_feed f WHERE f.aggregate_id = r.contact_id AND f.revision_number = r.revision_number AND f.change_type = 'contact.revised' AND f.project_id = t.project_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.warehouse_outbox w WHERE w.contact_id = r.contact_id AND w.revision_number = r.revision_number AND w.project_id = t.project_id AND jsonb_array_length(w.analytics_payload->'target_link_facts') = jsonb_array_length(r.snapshot->'targetLinks'))
    OR NOT EXISTS (SELECT 1 FROM fixture_0130_before_links b JOIN app_data.contact_target_links l USING(contact_id,promotion_target_id)
     WHERE b.contact_id = r.contact_id AND b.revision_number = 1 AND b.promotion_target_id = '7f300000-0000-4000-8000-00000000000e' AND l.revision_number = r.revision_number AND to_jsonb(b) - 'revision_number' = to_jsonb(l) - 'revision_number')))
   OR (SELECT count(*) FROM app_data.contact_audit_events a WHERE a.contact_id = t.contact_id AND a.command_id LIKE 'personal-merge-contact-resolve-v1:%' AND a.event_type = 'contact.revised') <> expected_revision - t.current_revision
  THEN RAISE EXCEPTION '0130 feed, audit, outbox or unrelated link lost original project scope'; END IF;
 END LOOP;
 IF (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0130_context)) IS DISTINCT FROM (SELECT project_id FROM fixture_0130_projects WHERE name = 'b')
 THEN RAISE EXCEPTION '0130 changed selected project'; END IF;
END $success$;
CREATE TEMP TABLE fixture_0130_after ON COMMIT DROP AS SELECT pg_temp.fixture_0130_state() AS state;
DO $replay$
DECLARE p record; result timestamptz; mapping jsonb; choices jsonb;
BEGIN
 FOR p IN SELECT plan.*,r.confirmed_at FROM fixture_0130_plans plan JOIN fixture_0130_results r USING(kind) LOOP
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ord DESC) INTO mapping FROM jsonb_array_elements(p.assignments) WITH ORDINALITY a(value,ord);
  SELECT jsonb_agg(value || jsonb_build_object('source_target_id',upper(value->>'source_target_id'),'pending_fact_id',CASE WHEN value->>'pending_fact_id' IS NULL THEN NULL ELSE upper(value->>'pending_fact_id') END) ORDER BY ord DESC) INTO choices FROM jsonb_array_elements(p.choices) WITH ORDINALITY a(value,ord);
  IF pg_temp.fixture_0130_confirm(p.kind) IS DISTINCT FROM p.confirmed_at OR pg_temp.fixture_0130_confirm(p.kind,mapping,choices) IS DISTINCT FROM p.confirmed_at THEN RAISE EXCEPTION '0130 exact/canonical terminal replay changed timestamp'; END IF;
 END LOOP;
 IF pg_temp.fixture_0130_state() IS DISTINCT FROM (SELECT state FROM fixture_0130_after) THEN RAISE EXCEPTION '0130 terminal replay changed business state'; END IF;
END $replay$;
SELECT pg_temp.fixture_0130_expect('23505',format('SELECT pg_temp.fixture_0130_confirm(''person'',NULL,%L::jsonb)',jsonb_set(choices,'{0,pending_fact_id}',to_jsonb(gen_random_uuid()::text)))) FROM fixture_0130_plans WHERE kind = 'person';
SELECT pg_temp.fixture_0130_expect('23505',format('SELECT pg_temp.fixture_0130_confirm(''person'',%L::jsonb)',jsonb_set(assignments,'{0,source_target_id}',
 to_jsonb(CASE assignments->0->>'source_target_id' WHEN '7f300000-0000-4000-8000-00000000000a' THEN '7f300000-0000-4000-8000-00000000000b' ELSE '7f300000-0000-4000-8000-00000000000a' END)))) FROM fixture_0130_plans WHERE kind = 'person';
SELECT pg_temp.fixture_0130_expect('42501',format('SELECT pg_temp.fixture_0130_confirm(''person'',NULL,NULL,%L)',gen_random_uuid()));
SELECT pg_temp.fixture_0130_expect('23505',format('SELECT app_private.confirm_personal_merge_contact_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
 c.app_user_id,CASE WHEN field = 'workspace' THEN gen_random_uuid() ELSE c.workspace_id END,CASE WHEN field = 'project' THEN c.project_id ELSE b.project_id END,p.request_id,
 CASE WHEN field = 'generation' THEN gen_random_uuid() ELSE p.generation_id END,
 CASE WHEN field = 'known' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
 CASE WHEN field = 'pending' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,
 CASE WHEN field = 'resolution' THEN repeat('0',64) ELSE p.document->>'resolution_fingerprint' END,p.assignments,p.choices))
FROM fixture_0130_context c CROSS JOIN fixture_0130_projects b CROSS JOIN fixture_0130_plans p CROSS JOIN (VALUES('workspace'),('project'),('generation'),('known'),('pending'),('resolution')) t(field) WHERE b.name = 'b' AND p.kind = 'person';
SELECT pg_temp.fixture_0130_expect('55000',$$UPDATE app_private.personal_merge_contact_resolution_requests_v1 SET confirmed_at_utc = confirmed_at_utc$$);
SELECT pg_temp.fixture_0130_expect('55000',$$DELETE FROM app_private.personal_merge_contact_history_applications_v1$$);
ROLLBACK;
