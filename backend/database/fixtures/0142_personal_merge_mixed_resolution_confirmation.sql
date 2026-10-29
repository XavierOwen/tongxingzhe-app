\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0142_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0142.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0142.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0142_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0142.example.test','other');
CREATE TEMP TABLE fixture_0142_projects ON COMMIT DROP AS SELECT 'a'::text AS name,c.* FROM fixture_0142_context c;
INSERT INTO fixture_0142_projects SELECT 'b',p.* FROM app_data.create_personal_project_context('https://synthetic-0142.example.test','owner','0142 project B') p;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,is_required,allow_unknown,allow_refused,allow_not_applicable,maximum_length)
SELECT questionnaire_version_id,'old_' || name,1,'0142 retained answer ' || name,CASE name WHEN 'b' THEN 'long_text' ELSE 'boolean' END,false,true,true,true,
 CASE name WHEN 'b' THEN 2000 ELSE NULL END FROM fixture_0142_projects;
INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current) VALUES ('0142-region-v1','draft',false);
INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind) VALUES
 ('0142-country','0142-region-v1',NULL,'0142 Country','country'),('0142-city','0142-region-v1','0142-country','0142 City','city'),
 ('0142-venue','0142-region-v1','0142-city','0142 Venue','venue');
INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
VALUES ('0142-boundary','0142-venue','0142-region-v1',polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))');
SELECT app_private.publish_canonical_region_tree_v1('0142-region-v1',true);
CREATE TEMP TABLE fixture_0142_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid,old_generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0142_pairs VALUES
 ('person','7f420000-0000-4000-8000-00000000000a','7f420000-0000-4000-8000-00000000000b',NULL,NULL),
 ('institution','7f420000-0000-4000-8000-00000000000c','7f420000-0000-4000-8000-00000000000d',NULL,NULL);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.id,c.workspace_id,p.kind,'0142 original private source','+1 312 555 0142',c.app_user_id
FROM fixture_0142_context c CROSS JOIN fixture_0142_pairs p CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(id);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id)
SELECT '7f420000-0000-4000-8000-00000000000e',workspace_id,'person','0142 unrelated original',app_user_id FROM fixture_0142_context;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id)
SELECT '7f420000-0000-4000-8000-00000000000f',workspace_id,'person','0142 current-only nonpair original',app_user_id FROM fixture_0142_context;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id FROM fixture_0142_context c JOIN app_data.promotion_targets t USING(workspace_id);

DO $existing_relationships$
DECLARE c record; target record; contact text; code text;
BEGIN
  FOR c IN TABLE fixture_0142_projects LOOP
    PERFORM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',c.project_id);
    FOR target IN SELECT * FROM app_data.promotion_targets WHERE workspace_id=c.workspace_id LOOP
      contact:='0142-entry-'||c.name||'-'||target.promotion_target_id;
      SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,contact||'-submit',1,'contact.submit.v1','0142-device',contact,0,
        jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
          'reason','0142 real existing relationship','occurredAtUtc','2025-01-01T00:00:00Z','occurredTimeZone','UTC','channel','video_call',
          'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
          'targetLinks',jsonb_build_array(jsonb_build_object('targetId',target.promotion_target_id,'targetType',target.target_type,
            'responseLevel',NULL,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
      IF code<>'accepted' THEN RAISE EXCEPTION '0142 real relationship entry was not accepted: %',code; END IF;
    END LOOP;
  END LOOP;
END $existing_relationships$;

DO $activate$
DECLARE c record; p record; preview uuid; generation uuid; fingerprint text;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0142_context;
 PERFORM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',c.project_id);
 FOR p IN SELECT * FROM fixture_0142_pairs LOOP
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0142.example.test','owner',c.project_id,p.first_target,p.second_target);
  generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target);
  SELECT fact_fingerprint INTO STRICT fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(generation);
  PERFORM app_private.end_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,fingerprint);
  UPDATE fixture_0142_pairs SET old_generation_id = generation WHERE kind = p.kind;
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0142.example.test','owner',c.project_id,p.first_target,p.second_target);
  UPDATE fixture_0142_pairs SET generation_id = app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target) WHERE kind = p.kind;
 END LOOP;
END $activate$;
SELECT result FROM fixture_0142_context c,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  '7f420000-0000-4000-8000-00000000000a',1,1,'active','0142 original current project note','progress_update',NULL,'0142-real-parent-head',NULL) updated;
CREATE TEMP TABLE fixture_0142_contacts(contact text PRIMARY KEY,project_name text,kind text) ON COMMIT DROP;
INSERT INTO fixture_0142_contacts VALUES ('0142 A | "TEXT": 汉字','a','person'),('0142-a','b','person'),('0142-institution','a','institution');
CREATE FUNCTION pg_temp.fixture_0142_submit(contact text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; result record;
BEGIN
 SELECT p.* INTO STRICT c FROM fixture_0142_contacts t JOIN fixture_0142_projects p ON p.name = t.project_name WHERE t.contact = $1;
 PERFORM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',c.project_id);
 SELECT s.* INTO result FROM app_data.apply_contact_submit_v3(c.app_user_id,contact || '-submit',1,'contact.submit.v1','0142-device',contact,0,
  jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
   'reason','0142 historical original','occurredAtUtc','2025-05-03T04:05:06.123456Z','occurredTimeZone','America/Chicago',
   'channel',CASE WHEN contact = '0142 A | "TEXT": 汉字' OR c.name = 'b' THEN 'face_to_face' ELSE 'video_call' END,
   'location',CASE WHEN contact = '0142 A | "TEXT": 汉字' THEN jsonb_build_object('kind','resolved','placeName','0142 Venue','smallestRegionId','0142-venue','regionTreeVersion','0142-region-v1')
    WHEN c.name = 'b' THEN jsonb_build_object('kind','pending_resolution','latitude',41.7897,'longitude',-87.5997,'accuracyMeters',8.5) ELSE jsonb_build_object('kind','not_applicable') END,
   'reachCount',2,'interestLevel',3,
   'answers',jsonb_build_array(jsonb_build_object('questionId','old_' || c.name,'state','answered','type',CASE c.name WHEN 'b' THEN 'long_text' ELSE 'boolean' END,
    'value',CASE c.name WHEN 'b' THEN to_jsonb('0142 B original text: 汉字'::text) ELSE 'true'::jsonb END)),
   'targetLinks',jsonb_build_array(jsonb_build_object('targetId','7f420000-0000-4000-8000-00000000000e','targetType','person','responseLevel',1,
    'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
  || CASE WHEN contact = '0142 A | "TEXT": 汉字' THEN jsonb_build_object('locationSource',jsonb_build_object('kind','captured_coordinates','latitude',41.7897,'longitude',-87.5997,'accuracyMeters',8.5,
   'resolverContractVersion','canonical-region-resolution:v1','regionTreeContentFingerprint',(SELECT content_fingerprint FROM app_data.canonical_region_tree_releases WHERE tree_version = '0142-region-v1'))) ELSE '{}'::jsonb END) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0142 submit rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0142_submit(contact) FROM fixture_0142_contacts ORDER BY contact COLLATE "C";
CREATE TEMP TABLE fixture_0142_pending(kind text,contact text,pending_fact_id uuid,source_target_id uuid,original_revision integer,response integer,consent text,representative boolean,entry boolean) ON COMMIT DROP;
CREATE FUNCTION pg_temp.fixture_0142_stage(contact text,source uuid,response integer,consent text,representative boolean,entry boolean) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; generation uuid; revision integer; pending uuid;
BEGIN
 SELECT p.*,t.kind INTO STRICT c FROM fixture_0142_contacts t JOIN fixture_0142_projects p ON p.name = t.project_name WHERE t.contact = $1;
 PERFORM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',c.project_id);
 SELECT generation_id INTO STRICT generation FROM fixture_0142_pairs WHERE kind = c.kind;
 SELECT current_revision INTO STRICT revision FROM app_data.contacts WHERE contact_id = $1;
 pending := app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,contact,revision,response,consent,representative,entry);
 INSERT INTO fixture_0142_pending VALUES(c.kind,contact,pending,source,revision,response,consent,representative,entry);
END $function$;
CREATE FUNCTION pg_temp.fixture_0142_revise(contact text,links jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; old app_data.contacts%ROWTYPE; snapshot jsonb; result record;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0142_context;
 SELECT * INTO STRICT old FROM app_data.contacts WHERE contact_id = $1;
 SELECT r.snapshot INTO STRICT snapshot FROM app_data.contact_revisions r WHERE r.contact_id = $1 AND r.revision_number = old.current_revision;
 SELECT s.* INTO result FROM app_data.apply_contact_revise_v3(c.app_user_id,contact || '-revise-' || old.current_revision,1,'contact.revise.v1','0142-device',contact,old.current_revision,
  snapshot || jsonb_build_object('reason','0142 revision ' || old.current_revision,'interestLevel',old.current_revision % 5,
   'occurredAtUtc',timestamptz '2025-05-03T04:05:06.123456Z' + old.current_revision * interval '1 day 1 microsecond',
   'answers',jsonb_build_array(CASE WHEN contact = '0142-a' THEN jsonb_build_object('questionId','old_b','state','answered','type','long_text','value','0142 B revised text ' || old.current_revision || ': 不同答案')
    ELSE jsonb_build_object('questionId','old_a','state',CASE old.current_revision WHEN 2 THEN 'unknown' WHEN 3 THEN 'refused' ELSE 'answered' END,'type','boolean',
     'value',CASE old.current_revision WHEN 1 THEN 'false'::jsonb WHEN 2 THEN 'null'::jsonb WHEN 3 THEN 'null'::jsonb ELSE 'true'::jsonb END) END))
  || CASE WHEN contact = '0142 A | "TEXT": 汉字' THEN jsonb_build_object('locationSource',(snapshot->'locationSource') || jsonb_build_object('latitude',41.7897 + old.current_revision * 0.0001,'accuracyMeters',8.5 + old.current_revision))
    WHEN contact = '0142-a' THEN jsonb_build_object('location',(snapshot->'location') || jsonb_build_object('latitude',41.7897 + old.current_revision * 0.0001,'accuracyMeters',8.5 + old.current_revision)) ELSE '{}'::jsonb END
  || CASE WHEN links IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('targetLinks',links) END) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0142 revise rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0142_stage('0142 A | "TEXT": 汉字','7f420000-0000-4000-8000-00000000000a',0,'yes',false,true);
SELECT pg_temp.fixture_0142_revise('0142 A | "TEXT": 汉字');
SELECT pg_temp.fixture_0142_stage('0142 A | "TEXT": 汉字','7f420000-0000-4000-8000-00000000000a',4,'no',false,true);
SELECT pg_temp.fixture_0142_revise('0142 A | "TEXT": 汉字');
SELECT pg_temp.fixture_0142_stage('0142 A | "TEXT": 汉字','7f420000-0000-4000-8000-00000000000b',0,'yes',false,true);
SELECT pg_temp.fixture_0142_revise('0142 A | "TEXT": 汉字',jsonb_set((SELECT r.snapshot->'targetLinks' FROM app_data.contact_revisions r WHERE contact_id = '0142 A | "TEXT": 汉字' AND revision_number = 3),'{0,targetId}',to_jsonb('7f420000-0000-4000-8000-00000000000f'::text)) || jsonb_build_array(
 jsonb_build_object('targetId','7f420000-0000-4000-8000-00000000000a','targetType','person','responseLevel',NULL,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true),
 jsonb_build_object('targetId','7f420000-0000-4000-8000-00000000000b','targetType','person','responseLevel',3,'followUpConsent','refused','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
-- Simulate bindings that predate this generation while retaining the original snapshot and business values.
ALTER TABLE app_data.contact_target_links DISABLE TRIGGER contact_target_links_merge_generation_immutable;
UPDATE app_data.contact_target_links SET merge_generation_id = CASE WHEN promotion_target_id = '7f420000-0000-4000-8000-00000000000a' THEN NULL ELSE (SELECT old_generation_id FROM fixture_0142_pairs WHERE kind = 'person') END
WHERE contact_id = '0142 A | "TEXT": 汉字' AND revision_number = 4 AND promotion_target_id IN ('7f420000-0000-4000-8000-00000000000a','7f420000-0000-4000-8000-00000000000b');
ALTER TABLE app_data.contact_target_links ENABLE TRIGGER contact_target_links_merge_generation_immutable;
SELECT pg_temp.fixture_0142_stage('0142-a','7f420000-0000-4000-8000-00000000000b',2,'yes',false,true);
SELECT pg_temp.fixture_0142_revise('0142-a');
SELECT pg_temp.fixture_0142_stage('0142-a','7f420000-0000-4000-8000-00000000000b',2,'yes',false,true);
SELECT pg_temp.fixture_0142_stage('0142-institution','7f420000-0000-4000-8000-00000000000c',NULL,'not_applicable',false,true);
SELECT pg_temp.fixture_0142_revise('0142-institution');
SELECT pg_temp.fixture_0142_stage('0142-institution','7f420000-0000-4000-8000-00000000000d',4,'yes',true,true);

CREATE TEMP TABLE fixture_0142_project_pending(kind text,project_id uuid,pending_fact_id uuid,source_target_id uuid);
DO $project_pending$
DECLARE pair record; c record; repeat_number integer; pending uuid; stage integer;
BEGIN
  FOR pair IN TABLE fixture_0142_pairs LOOP
    FOR c IN TABLE fixture_0142_projects LOOP
      PERFORM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',c.project_id);
      FOR repeat_number IN 1..2 LOOP
        stage:=CASE WHEN c.name='b' AND repeat_number=1 THEN 4 ELSE 2 END;
        SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
          gen_random_uuid(),pair.generation_id,stage,'paused',E'  0142 private project note\n原值  ',CASE stage WHEN 4 THEN 'other' ELSE 'progress_update' END,E'  0142 private detail\t');
        INSERT INTO fixture_0142_project_pending VALUES(pair.kind,c.project_id,pending,CASE c.name WHEN 'a' THEN pair.first_target ELSE pair.second_target END);
      END LOOP;
    END LOOP;
  END LOOP;
END $project_pending$;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',(SELECT project_id FROM fixture_0142_projects WHERE name='b'));
CREATE TEMP TABLE fixture_0142_plans AS
SELECT pair.kind,pair.generation_id,gen_random_uuid() AS request_id,
  app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS pending_plan,
  app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS project_inventory,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id)
    FROM fixture_0142_pending pending WHERE pending.kind=pair.kind) AS assignments,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id)
    FROM fixture_0142_project_pending pending WHERE pending.kind=pair.kind) AS project_assignments,
  NULL::jsonb AS mixed_document,NULL::jsonb AS document,NULL::jsonb AS project_document,NULL::jsonb AS choices,NULL::jsonb AS project_choices
FROM fixture_0142_pairs pair,fixture_0142_context c,fixture_0142_projects b WHERE b.name='b';
UPDATE fixture_0142_plans p SET mixed_document=app_private.plan_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.pending_plan->'known_source_plan'->>'fact_fingerprint',p.pending_plan->>'pending_fingerprint',p.project_inventory->>'pending_fingerprint',
  p.assignments,p.project_assignments)
FROM fixture_0142_context c,fixture_0142_projects b WHERE b.name='b';
UPDATE fixture_0142_plans SET document=mixed_document->'contact_resolution_plan',project_document=mixed_document->'project_relationship_resolution_plan';
UPDATE fixture_0142_plans p SET choices=(SELECT jsonb_agg(jsonb_build_object('contact_id',slot->>'contact_id','source_target_id',slot->>'source_target_id',
  'candidate_kind',CASE WHEN slot->>'contact_id'='0142 A | "TEXT": 汉字' AND slot->>'source_target_id'='7f420000-0000-4000-8000-00000000000b' THEN 'current' ELSE 'pending' END,
  'pending_fact_id',CASE WHEN slot->>'contact_id'='0142 A | "TEXT": 汉字' AND slot->>'source_target_id'='7f420000-0000-4000-8000-00000000000b' THEN NULL ELSE
    (SELECT pending_fact_id::text FROM fixture_0142_pending pending WHERE pending.contact=slot->>'contact_id'
      AND pending.source_target_id=(slot->>'source_target_id')::uuid ORDER BY original_revision,pending_fact_id LIMIT 1) END)
  ORDER BY slot->>'contact_id' COLLATE "C",(slot->>'source_target_id')::uuid) FROM jsonb_array_elements(p.document->'source_slots') slot);
UPDATE fixture_0142_plans p SET project_choices=(SELECT jsonb_agg(jsonb_build_object('project_id',slot->>'project_id','source_target_id',slot->>'source_target_id',
  'candidate_kind',CASE WHEN p.kind='person' AND slot->>'project_id'=(SELECT project_id::text FROM fixture_0142_projects WHERE name='a') THEN 'current' ELSE 'pending' END,
  'pending_fact_id',CASE WHEN p.kind='person' AND slot->>'project_id'=(SELECT project_id::text FROM fixture_0142_projects WHERE name='a') THEN 'null'::jsonb ELSE slot->'pending_fact_ids'->0 END)
  ORDER BY (slot->>'project_id')::uuid,(slot->>'source_target_id')::uuid) FROM jsonb_array_elements(p.project_document->'source_slots') slot);
\ir shared/database_state.sql
CREATE FUNCTION pg_temp.assert_0142(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0142 %',label; END IF;
END $function$;
CREATE FUNCTION pg_temp.fixture_0142_confirm(kind text,mapping jsonb DEFAULT NULL,choices jsonb DEFAULT NULL,request uuid DEFAULT NULL,
  project_mapping jsonb DEFAULT NULL,project_choices jsonb DEFAULT NULL) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.confirm_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,coalesce($4,p.request_id),p.generation_id,
    p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.project_document->>'pending_fingerprint',p.mixed_document->>'resolution_fingerprint',
    coalesce($2,p.assignments),coalesce($3,p.choices),coalesce($5,p.project_assignments),coalesce($6,p.project_choices))
  FROM fixture_0142_context c,fixture_0142_projects b,fixture_0142_plans p WHERE b.name='b' AND p.kind=$1
$function$;
CREATE FUNCTION pg_temp.fixture_0142_expect(expected text,command text,expected_detail text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb:=pg_temp.fixture_database_state(); actual text; detail text;
BEGIN
  BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE,detail=MESSAGE_TEXT; END;
  IF actual IS DISTINCT FROM expected OR(expected_detail IS NOT NULL AND detail IS DISTINCT FROM expected_detail) THEN
    RAISE EXCEPTION '0142 expected % / %, got % / %',expected,expected_detail,actual,detail;
  END IF;
  PERFORM pg_temp.assert_0142(before_state=pg_temp.fixture_database_state(),'failed mixed confirmation changed persistent state');
END $function$;
CREATE TEMP TABLE fixture_0142_before_revisions AS SELECT revision.* FROM app_data.contact_revisions revision JOIN fixture_0142_contacts fixture ON fixture.contact=revision.contact_id;
CREATE TEMP TABLE fixture_0142_before_answers AS SELECT answer.* FROM app_data.contact_answers answer JOIN fixture_0142_contacts fixture ON fixture.contact=answer.contact_id;
CREATE TEMP TABLE fixture_0142_before_provenance AS SELECT provenance.* FROM app_data.contact_location_provenance provenance JOIN fixture_0142_contacts fixture ON fixture.contact=provenance.contact_id;
CREATE TEMP TABLE fixture_0142_before_links AS SELECT link.* FROM app_data.contact_target_links link JOIN fixture_0142_contacts fixture ON fixture.contact=link.contact_id;
CREATE TEMP TABLE fixture_0142_before_contacts AS SELECT contact.* FROM app_data.contacts contact JOIN fixture_0142_contacts fixture ON fixture.contact=contact.contact_id;
CREATE TEMP TABLE fixture_0142_before_relations AS SELECT * FROM app_data.promotion_target_project_relationships;
CREATE TEMP TABLE fixture_0142_before_project_revisions AS SELECT * FROM app_data.promotion_target_relationship_revisions;
CREATE TEMP TABLE fixture_0142_project_payloads AS SELECT header.*,payload.new_stage,payload.new_lifecycle_status,payload.follow_up_note,payload.reason_code,payload.reason_detail,pending.source_target_id
FROM fixture_0142_project_pending pending JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 payload USING(pending_fact_id);
CREATE TEMP TABLE fixture_0142_before_state AS SELECT pg_temp.fixture_database_state() AS state;

SELECT pg_temp.fixture_0142_expect('55000',format('SELECT app_private.confirm_personal_merge_contact_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
  c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint',
  p.document->>'pending_fingerprint',p.document->>'resolution_fingerprint',p.assignments,p.choices))
FROM fixture_0142_context c,fixture_0142_projects b,fixture_0142_plans p WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.fixture_0142_expect('55000',format('SELECT app_private.confirm_personal_merge_project_relationship_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
  c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,p.project_document->'known_source_plan'->>'fact_fingerprint',
  p.project_document->>'pending_fingerprint',p.project_document->>'resolution_fingerprint',p.project_assignments,p.project_choices))
FROM fixture_0142_context c,fixture_0142_projects b,fixture_0142_plans p WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.fixture_0142_expect(expected,format('SELECT pg_temp.fixture_0142_confirm(''person'',%L::jsonb,%L::jsonb,NULL,%L::jsonb,%L::jsonb)',
  CASE WHEN family='contact' AND field='mapping' THEN bad ELSE p.assignments END,
  CASE WHEN family='contact' AND field='choices' THEN bad ELSE p.choices END,
  CASE WHEN family='project' AND field='mapping' THEN bad ELSE p.project_assignments END,
  CASE WHEN family='project' AND field='choices' THEN bad ELSE p.project_choices END))
FROM fixture_0142_plans p,(VALUES('contact'),('project')) families(family),(VALUES('mapping'),('choices')) fields(field),
  LATERAL(SELECT CASE WHEN family='contact' THEN CASE field WHEN 'mapping' THEN p.assignments ELSE p.choices END
    ELSE CASE field WHEN 'mapping' THEN p.project_assignments ELSE p.project_choices END END original) source,
  LATERAL(VALUES('22023','{}'::jsonb),('23505',jsonb_build_array(original->0))) cases(expected,bad) WHERE p.kind='person';
SELECT pg_temp.fixture_0142_expect('23505',format('SELECT pg_temp.fixture_0142_confirm(''person'',%L::jsonb,NULL,NULL,%L::jsonb)',
  CASE WHEN family='contact' THEN changed ELSE p.assignments END,CASE WHEN family='project' THEN changed ELSE p.project_assignments END))
FROM fixture_0142_plans p,(VALUES('contact'),('project')) families(family),
  LATERAL(SELECT CASE family WHEN 'contact' THEN p.assignments ELSE p.project_assignments END original) source,
  LATERAL(SELECT jsonb_build_array((original->0)||jsonb_build_object('source_target_id','7f420000-0000-4000-8000-00000000000c'))||(original-0) changed) bad
WHERE p.kind='person';
SELECT pg_temp.fixture_0142_expect(expected,format('SELECT app_private.confirm_personal_merge_mixed_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb,%L::jsonb,%L::jsonb)',
  CASE field WHEN 'other_actor' THEN other.app_user_id ELSE c.app_user_id END,c.workspace_id,b.project_id,p.request_id,p.generation_id,
  CASE field WHEN 'known' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
  CASE field WHEN 'contact_pending' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,
  CASE field WHEN 'project_pending' THEN repeat('0',64) ELSE p.project_document->>'pending_fingerprint' END,
  CASE field WHEN 'mixed' THEN repeat('0',64) ELSE p.mixed_document->>'resolution_fingerprint' END,p.assignments,p.choices,p.project_assignments,p.project_choices))
FROM fixture_0142_context c,fixture_0142_other other,fixture_0142_projects b,fixture_0142_plans p,
  (VALUES('known','23505'),('contact_pending','23505'),('project_pending','23505'),('mixed','23505'),('other_actor','42501')) invalid(field,expected)
WHERE b.name='b' AND p.kind='person';
DO $missing_relationships$
DECLARE target_id uuid; c record; before_state jsonb;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0142_context;
  FOREACH target_id IN ARRAY ARRAY['7f420000-0000-4000-8000-00000000000e'::uuid,'7f420000-0000-4000-8000-00000000000f'::uuid] LOOP
    BEGIN
      SET LOCAL session_replication_role=replica;
      DELETE FROM app_data.promotion_target_project_relationships WHERE promotion_target_id=target_id AND project_id=c.project_id;
      SET LOCAL session_replication_role=origin;
      PERFORM pg_temp.fixture_0142_expect('55000','SELECT pg_temp.fixture_0142_confirm(''person'')','mixed resolution requires existing project relationships');
      RAISE SQLSTATE 'ZX001' USING MESSAGE='0142 rollback missing relation probe';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $missing_relationships$;
SAVEPOINT missing_project_slot;
SET LOCAL session_replication_role=replica;
DELETE FROM app_data.promotion_target_project_relationships WHERE promotion_target_id='7f420000-0000-4000-8000-00000000000b'
  AND project_id=(SELECT project_id FROM fixture_0142_projects WHERE name='b');
SET LOCAL session_replication_role=origin;
UPDATE fixture_0142_plans p SET pending_plan=app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id),
  project_inventory=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
FROM fixture_0142_context c,fixture_0142_projects b WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0142_plans p SET mixed_document=app_private.plan_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.pending_plan->'known_source_plan'->>'fact_fingerprint',p.pending_plan->>'pending_fingerprint',p.project_inventory->>'pending_fingerprint',
  p.assignments,p.project_assignments)
FROM fixture_0142_context c,fixture_0142_projects b WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0142_plans SET document=mixed_document->'contact_resolution_plan',project_document=mixed_document->'project_relationship_resolution_plan' WHERE kind='person';
SELECT pg_temp.fixture_0142_expect('55000','SELECT pg_temp.fixture_0142_confirm(''person'')','mixed resolution requires existing project relationships');
ROLLBACK TO missing_project_slot;
RELEASE missing_project_slot;
SAVEPOINT nonpair_revoked;
UPDATE app_data.promotion_target_assignments SET ended_at=clock_timestamp(),end_reason='0142 revoked historical nonpair'
WHERE promotion_target_id='7f420000-0000-4000-8000-00000000000e' AND ended_at IS NULL;
SELECT pg_temp.fixture_0142_expect('42501','SELECT pg_temp.fixture_0142_confirm(''person'')');
ROLLBACK TO nonpair_revoked;
RELEASE nonpair_revoked;
SAVEPOINT due_source;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years' WHERE promotion_target_id='7f420000-0000-4000-8000-00000000000a';
SELECT pg_temp.fixture_0142_expect('42501','SELECT pg_temp.fixture_0142_confirm(''person'')');
ROLLBACK TO due_source;
RELEASE due_source;
SAVEPOINT context_changed;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0142.example.test','owner',(SELECT project_id FROM fixture_0142_projects WHERE name='a'));
SELECT pg_temp.fixture_0142_expect('42501','SELECT pg_temp.fixture_0142_confirm(''person'')');
ROLLBACK TO context_changed;
RELEASE context_changed;
SAVEPOINT contact_growth;
SELECT pg_temp.fixture_0142_revise('0142-a');
SELECT pg_temp.fixture_0142_stage('0142-a','7f420000-0000-4000-8000-00000000000b',2,'yes',false,true);
SELECT pg_temp.fixture_0142_expect('23505','SELECT pg_temp.fixture_0142_confirm(''person'')');
ROLLBACK TO contact_growth;
RELEASE contact_growth;
SAVEPOINT project_growth;
SELECT staged.* FROM fixture_0142_context c,fixture_0142_projects b,fixture_0142_plans p,
LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,b.project_id,gen_random_uuid(),
  p.generation_id,2,'active','0142 new project pending','progress_update',NULL)
staged WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.fixture_0142_expect('23505','SELECT pg_temp.fixture_0142_confirm(''person'')');
ROLLBACK TO project_growth;
RELEASE project_growth;
CREATE FUNCTION pg_temp.fault_0142() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF TG_ARGV[0]='raise' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='0142 injected write failure'; END IF;
  RETURN NULL;
END $function$;
DO $faults$
DECLARE table_name text; operation text; mode text;
BEGIN
  FOR table_name,operation IN SELECT * FROM(VALUES
    ('app_data.contact_revisions','INSERT'),('app_data.contact_location_provenance','INSERT'),
    ('app_private.personal_merge_contact_current_choices_v1','INSERT'),
    ('app_data.promotion_target_relationship_revisions','INSERT'),('app_data.promotion_target_project_relationships','UPDATE'),
    ('app_private.personal_merge_project_relationship_current_choices_v1','INSERT'),
    ('app_private.personal_merge_contact_resolution_requests_v1','INSERT'),
    ('app_private.personal_merge_project_relationship_resolution_requests_v1','INSERT'),
    ('app_private.personal_merge_mixed_resolution_requests_v1','INSERT'),
    ('app_private.personal_target_merge_end_events_v1','INSERT'),
    ('app_data.personal_merge_unassigned_contact_facts_v1','DELETE'),
    ('app_data.personal_merge_unassigned_project_relationship_facts_v1','DELETE')) writes(name,operation) LOOP
    FOREACH mode IN ARRAY ARRAY['raise','suppress'] LOOP
      EXECUTE format('CREATE TRIGGER fixture_0142_fault BEFORE %s ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.fault_0142(%L)',operation,table_name,mode);
      RAISE NOTICE '0142 injected % % %',table_name,operation,mode;
      PERFORM pg_temp.fixture_0142_expect(CASE WHEN mode='raise' THEN 'P0001'
        WHEN table_name='app_data.contact_revisions' THEN '23503' ELSE '55000' END,'SELECT pg_temp.fixture_0142_confirm(''person'')');
      EXECUTE format('DROP TRIGGER fixture_0142_fault ON %s',table_name);
    END LOOP;
  END LOOP;
END $faults$;
CREATE FUNCTION pg_temp.tamper_metadata_0142() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF TG_TABLE_NAME='personal_merge_contact_resolution_requests_v1' THEN NEW.pending_fingerprint:=repeat('0',64);
  ELSIF TG_TABLE_NAME='personal_merge_project_relationship_resolution_requests_v1' THEN NEW.resolution_fingerprint:=repeat('0',64);
  ELSE NEW.resolution_fingerprint:=repeat('0',64);
  END IF;
  RETURN NEW;
END $function$;
DO $metadata$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['app_private.personal_merge_contact_resolution_requests_v1',
    'app_private.personal_merge_project_relationship_resolution_requests_v1','app_private.personal_merge_mixed_resolution_requests_v1'] LOOP
    EXECUTE format('CREATE TRIGGER fixture_0142_metadata BEFORE INSERT ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.tamper_metadata_0142()',table_name);
    PERFORM pg_temp.fixture_0142_expect('55000','SELECT pg_temp.fixture_0142_confirm(''person'')');
    EXECUTE format('DROP TRIGGER fixture_0142_metadata ON %s',table_name);
  END LOOP;
END $metadata$;
SELECT pg_temp.fixture_0142_expect('55000',$statement$
DO $forged$ DECLARE c record; p record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0142_context;
  SELECT * INTO STRICT p FROM fixture_0142_plans WHERE kind='person';
  INSERT INTO app_private.personal_merge_mixed_resolution_requests_v1 VALUES(c.app_user_id,p.request_id,p.generation_id,p.mixed_document->>'resolution_fingerprint');
  PERFORM pg_temp.assert_0142(NOT app_private.personal_merge_mixed_resolution_proof_v1(c.app_user_id,p.request_id),'forged common-only receipt passed live proof');
  PERFORM app_private.end_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,
    (SELECT project_id FROM fixture_0142_projects WHERE name='b'),p.request_id,p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint');
END $forged$;
$statement$);
CREATE FUNCTION pg_temp.corrupt_after_end_0142() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE affected integer;
BEGIN
  UPDATE app_data.processed_commands SET result_code='conflict',server_cursor=NULL,failure_code='0142_after_end_conflict'
  WHERE app_user_id=NEW.actor_app_user_id AND command_id='personal-merge-contact-resolve-v1:'||NEW.request_id||':current:'||octet_length('0142-a')||':0142-a';
  GET DIAGNOSTICS affected=ROW_COUNT;
  IF affected<>1 THEN RAISE EXCEPTION '0142 after-end injection missed final contact child'; END IF;
  RETURN NEW;
END $function$;
SAVEPOINT corrupt_after_end;
CREATE TRIGGER fixture_0142_after_end AFTER INSERT ON app_private.personal_target_merge_end_events_v1 FOR EACH ROW EXECUTE FUNCTION pg_temp.corrupt_after_end_0142();
SELECT pg_temp.fixture_0142_expect('55000','SELECT pg_temp.fixture_0142_confirm(''person'')');
ROLLBACK TO corrupt_after_end;
RELEASE corrupt_after_end;
CREATE TEMP TABLE fixture_0142_results(kind text PRIMARY KEY,confirmed_at timestamptz);
INSERT INTO fixture_0142_results SELECT kind,pg_temp.fixture_0142_confirm(kind) FROM fixture_0142_plans ORDER BY kind;
SET CONSTRAINTS ALL IMMEDIATE;
DO $success$
DECLARE n record; t record; original jsonb; applied jsonb; current_snapshot jsonb; final_snapshot jsonb; expected_revision integer; choice jsonb;
BEGIN
 IF (SELECT count(*) FROM app_private.personal_merge_contact_resolution_requests_v1 WHERE workspace_id = (SELECT workspace_id FROM fixture_0142_context)) <> 2
  OR (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0142_pending)) <> 7
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE contact_id IN (SELECT contact FROM fixture_0142_contacts)) <> 3
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE contact_id IN (SELECT contact FROM fixture_0142_contacts)) <> 5
  OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0142_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0142_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id IN (SELECT generation_id FROM fixture_0142_pairs))
 THEN RAISE EXCEPTION '0142 exact history/current receipts, payload consumption or merge end drift'; END IF;
 IF EXISTS (SELECT 1 FROM fixture_0142_before_revisions b LEFT JOIN app_data.contact_revisions r USING(contact_id,revision_number) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(r))
  OR EXISTS (SELECT 1 FROM fixture_0142_before_answers b LEFT JOIN app_data.contact_answers a USING(contact_id,revision_number,question_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(a))
  OR EXISTS (SELECT 1 FROM fixture_0142_before_links b LEFT JOIN app_data.contact_target_links l USING(contact_id,revision_number,promotion_target_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(l))
  OR EXISTS (SELECT 1 FROM fixture_0142_before_provenance b LEFT JOIN app_data.contact_location_provenance p USING(source_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(p))
 THEN RAISE EXCEPTION '0142 rewrote original revisions, answers, NULL binding or old generation binding'; END IF;
 FOR t IN SELECT b.*,p.kind,p.request_id,p.generation_id FROM fixture_0142_before_contacts b JOIN fixture_0142_contacts fixture_contact ON fixture_contact.contact = b.contact_id JOIN fixture_0142_plans p USING(kind) ORDER BY b.contact_id COLLATE "C" LOOP
  expected_revision := t.current_revision;
  FOR n IN SELECT * FROM fixture_0142_pending WHERE contact = t.contact_id ORDER BY original_revision,pending_fact_id LOOP
   expected_revision := expected_revision + 1;
   SELECT snapshot INTO STRICT original FROM fixture_0142_before_revisions WHERE contact_id = n.contact AND revision_number = n.original_revision;
   SELECT snapshot INTO STRICT applied FROM app_data.contact_revisions WHERE contact_id = n.contact AND revision_number = expected_revision;
   IF (original - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM (applied - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
    OR (applied->>'occurredAtUtc')::timestamptz IS DISTINCT FROM (original->>'occurredAtUtc')::timestamptz
    OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = n.original_revision)
     IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = expected_revision)
    OR (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM fixture_0142_before_provenance p WHERE contact_id = n.contact AND revision_number = n.original_revision)
     IS DISTINCT FROM (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM app_data.contact_location_provenance p WHERE contact_id = n.contact AND revision_number = expected_revision)
    OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links l WHERE contact_id = n.contact AND revision_number = expected_revision AND promotion_target_id = n.source_target_id
     AND response_level IS NOT DISTINCT FROM n.response AND follow_up_consent = n.consent AND institution_representative_confirmed = n.representative AND confirmed_project_entry = n.entry AND merge_generation_id = t.generation_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.processed_commands p WHERE p.app_user_id = t.app_user_id AND p.command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':pending:' || n.pending_fact_id AND p.result_code = 'accepted' AND p.server_cursor IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_history_applications_v1 a WHERE a.pending_fact_id = n.pending_fact_id AND a.actor_app_user_id = t.app_user_id AND a.request_id = t.request_id
     AND a.contact_id = n.contact AND a.original_revision_number = n.original_revision AND a.from_revision_number = expected_revision - 1 AND a.to_revision_number = expected_revision AND a.source_target_id = n.source_target_id
     AND a.child_command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':pending:' || n.pending_fact_id)

    OR (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM fixture_0142_before_links link
      WHERE contact_id=n.contact AND revision_number=n.original_revision AND promotion_target_id NOT IN
        (SELECT first_target FROM fixture_0142_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0142_pairs WHERE kind=t.kind))
      IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM app_data.contact_target_links link
      WHERE contact_id=n.contact AND revision_number=expected_revision AND promotion_target_id NOT IN
        (SELECT first_target FROM fixture_0142_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0142_pairs WHERE kind=t.kind))
   THEN RAISE EXCEPTION '0142 historical application lost snapshot, answers, explicit business values or accepted child: %/%',n.contact,n.original_revision; END IF;
  END LOOP;
  expected_revision := expected_revision + 1;
  SELECT snapshot INTO STRICT current_snapshot FROM fixture_0142_before_revisions WHERE contact_id = t.contact_id AND revision_number = t.current_revision;
  SELECT snapshot INTO STRICT final_snapshot FROM app_data.contact_revisions WHERE contact_id = t.contact_id AND revision_number = expected_revision;
  IF (current_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM (final_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
   OR (final_snapshot->>'occurredAtUtc')::timestamptz IS DISTINCT FROM (current_snapshot->>'occurredAtUtc')::timestamptz
   OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM fixture_0142_before_answers a WHERE contact_id = t.contact_id AND revision_number = t.current_revision)
    IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = t.contact_id AND revision_number = expected_revision)
   OR (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM fixture_0142_before_provenance p WHERE contact_id = t.contact_id AND revision_number = t.current_revision)
    IS DISTINCT FROM (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM app_data.contact_location_provenance p WHERE contact_id = t.contact_id AND revision_number = expected_revision)
   OR NOT EXISTS (SELECT 1 FROM app_data.contacts c WHERE c.contact_id = t.contact_id AND c.current_revision = expected_revision AND c.project_id = t.project_id AND c.questionnaire_version_id = t.questionnaire_version_id AND c.occurred_at_utc = t.occurred_at_utc)
   OR NOT EXISTS (SELECT 1 FROM app_data.processed_commands p WHERE p.app_user_id = t.app_user_id AND p.command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':current:' || octet_length(t.contact_id) || ':' || t.contact_id AND p.result_code = 'accepted' AND p.server_cursor IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_current_revisions_v1 a WHERE a.actor_app_user_id = t.app_user_id AND a.request_id = t.request_id AND a.contact_id = t.contact_id
    AND a.original_revision_number = t.current_revision AND a.from_revision_number = expected_revision - 1 AND a.to_revision_number = expected_revision
    AND a.child_command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':current:' || octet_length(t.contact_id) || ':' || t.contact_id)
   OR jsonb_array_length(final_snapshot->'targetLinks') <> 1 + (SELECT count(*) FROM fixture_0142_plans p CROSS JOIN LATERAL jsonb_array_elements(p.choices) value WHERE value->>'contact_id' = t.contact_id)

   OR (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM fixture_0142_before_links link
     WHERE contact_id=t.contact_id AND revision_number=t.current_revision AND promotion_target_id NOT IN
       (SELECT first_target FROM fixture_0142_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0142_pairs WHERE kind=t.kind))
     IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM app_data.contact_target_links link
     WHERE contact_id=t.contact_id AND revision_number=expected_revision AND promotion_target_id NOT IN
       (SELECT first_target FROM fixture_0142_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0142_pairs WHERE kind=t.kind))
  THEN RAISE EXCEPTION '0142 final current snapshot, old questionnaire, event time or child drift: %',t.contact_id; END IF;
  FOR choice IN SELECT value FROM fixture_0142_plans p CROSS JOIN LATERAL jsonb_array_elements(p.choices) WHERE value->>'contact_id' = t.contact_id LOOP
   IF choice->>'candidate_kind' = 'current' THEN
    IF NOT EXISTS (SELECT 1 FROM fixture_0142_before_links b JOIN app_data.contact_target_links l USING(contact_id,promotion_target_id)
     WHERE b.contact_id = t.contact_id AND b.revision_number = t.current_revision AND l.revision_number = expected_revision AND l.promotion_target_id = (choice->>'source_target_id')::uuid
     AND (to_jsonb(b) - ARRAY['revision_number','merge_generation_id']) = (to_jsonb(l) - ARRAY['revision_number','merge_generation_id']) AND l.merge_generation_id = t.generation_id)
    THEN RAISE EXCEPTION '0142 explicit current choice lost original business values'; END IF;
   ELSE
    IF NOT EXISTS (SELECT 1 FROM fixture_0142_pending selected_pending JOIN app_data.contact_target_links l ON l.contact_id = selected_pending.contact AND l.promotion_target_id = selected_pending.source_target_id
     WHERE selected_pending.pending_fact_id = (choice->>'pending_fact_id')::uuid AND l.revision_number = expected_revision AND l.response_level IS NOT DISTINCT FROM selected_pending.response
     AND l.follow_up_consent = selected_pending.consent AND l.institution_representative_confirmed = selected_pending.representative AND l.confirmed_project_entry = selected_pending.entry AND l.merge_generation_id = t.generation_id)
    THEN RAISE EXCEPTION '0142 explicit older pending choice was replaced or folded'; END IF;
   END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_data.contact_revisions r WHERE r.contact_id = t.contact_id AND r.revision_number > t.current_revision
   AND (NOT EXISTS (SELECT 1 FROM app_data.change_feed f WHERE f.aggregate_id = r.contact_id AND f.revision_number = r.revision_number AND f.change_type = 'contact.revised' AND f.project_id = t.project_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.warehouse_outbox w WHERE w.contact_id = r.contact_id AND w.revision_number = r.revision_number AND w.project_id = t.project_id AND jsonb_array_length(w.analytics_payload->'target_link_facts') = jsonb_array_length(r.snapshot->'targetLinks'))))
   OR (SELECT count(*) FROM app_data.contact_audit_events a WHERE a.contact_id = t.contact_id AND a.command_id LIKE 'personal-merge-contact-resolve-v1:%' AND a.event_type = 'contact.revised') <> expected_revision - t.current_revision
  THEN RAISE EXCEPTION '0142 feed, audit, outbox or unrelated link lost original project scope'; END IF;
 END LOOP;
 IF (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0142_context)) IS DISTINCT FROM (SELECT project_id FROM fixture_0142_projects WHERE name = 'b')
 THEN RAISE EXCEPTION '0142 changed selected project'; END IF;
END $success$;

DO $joint_success$
DECLARE p record; slot jsonb; base record; payload record; applied record; selected record; final_revision record; choice jsonb; expected_revision integer;
BEGIN
  PERFORM pg_temp.assert_0142((SELECT count(*) FROM app_private.personal_merge_mixed_resolution_requests_v1 WHERE generation_id IN(SELECT generation_id FROM fixture_0142_pairs))=2
    AND (SELECT count(*) FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id IN(SELECT generation_id FROM fixture_0142_pairs))=2
    AND NOT EXISTS(SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id IN(SELECT generation_id FROM fixture_0142_pairs))
    AND NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 WHERE pending_fact_id IN(SELECT pending_fact_id FROM fixture_0142_project_pending)),
    'joint receipt, single end, active members, or project consumption count differs');
  PERFORM pg_temp.assert_0142((SELECT jsonb_agg(jsonb_build_array(promotion_target_id,project_id) ORDER BY project_id,promotion_target_id) FROM app_data.promotion_target_project_relationships)=
      (SELECT jsonb_agg(jsonb_build_array(promotion_target_id,project_id) ORDER BY project_id,promotion_target_id) FROM fixture_0142_before_relations)
    AND NOT EXISTS(SELECT 1 FROM fixture_0142_before_project_revisions old LEFT JOIN app_data.promotion_target_relationship_revisions live USING(promotion_target_id,project_id,revision_number)
      WHERE to_jsonb(old) IS DISTINCT FROM to_jsonb(live))
    AND (SELECT count(*) FROM app_data.promotion_target_relationship_revisions WHERE reason_code='project_entry')=
      (SELECT count(*) FROM fixture_0142_before_project_revisions WHERE reason_code='project_entry')
    AND NOT EXISTS(SELECT 1 FROM fixture_0142_before_relations old JOIN app_data.promotion_target_project_relationships live USING(promotion_target_id,project_id)
      WHERE old.merge_generation_id IS DISTINCT FROM live.merge_generation_id),'mixed confirmation created a relation/entry or changed old parent/history binding');
  FOR p IN SELECT plan.*,result.confirmed_at,contact_request.confirmed_at_utc AS applied_at FROM fixture_0142_plans plan
    JOIN fixture_0142_results result USING(kind) JOIN app_private.personal_merge_contact_resolution_requests_v1 contact_request
      ON contact_request.request_id=plan.request_id AND contact_request.actor_app_user_id=(SELECT app_user_id FROM fixture_0142_context) LOOP
    PERFORM pg_temp.assert_0142(app_private.personal_merge_mixed_resolution_proof_v1((SELECT app_user_id FROM fixture_0142_context),p.request_id)
      AND app_private.personal_merge_project_relationship_resolution_fact_proof_v1((SELECT app_user_id FROM fixture_0142_context),p.request_id)
      AND EXISTS(SELECT 1 FROM app_private.personal_merge_contact_resolution_requests_v1 contact
        JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 project USING(actor_app_user_id,request_id)
        JOIN app_private.personal_merge_mixed_resolution_requests_v1 common USING(actor_app_user_id,request_id)
        JOIN app_private.personal_target_merge_end_events_v1 ended USING(actor_app_user_id,request_id)
        WHERE common.request_id=p.request_id AND common.generation_id=p.generation_id AND common.resolution_fingerprint=p.mixed_document->>'resolution_fingerprint'
          AND contact.workspace_id=project.workspace_id AND contact.project_id=project.project_id AND contact.generation_id=project.generation_id
          AND contact.generation_id=p.generation_id AND contact.known_fact_fingerprint=project.known_fact_fingerprint
          AND contact.known_fact_fingerprint=p.document->'known_source_plan'->>'fact_fingerprint'
          AND contact.post_known_fact_fingerprint=project.post_known_fact_fingerprint
          AND contact.post_known_fact_fingerprint=ended.fact_fingerprint AND ended.ended_at_utc=p.confirmed_at
          AND contact.pending_fingerprint=p.document->>'pending_fingerprint' AND project.pending_fingerprint=p.project_document->>'pending_fingerprint'
          AND contact.resolution_fingerprint=p.document->>'resolution_fingerprint' AND project.resolution_fingerprint=p.project_document->>'resolution_fingerprint'
          AND contact.confirmed_at_utc=project.confirmed_at_utc AND contact.confirmed_at_utc<=ended.ended_at_utc),
      'families did not bind original metadata and one common final manifest/context/time');
    FOR slot IN SELECT value FROM jsonb_array_elements(p.project_document->'source_slots') LOOP
      SELECT * INTO STRICT base FROM fixture_0142_before_project_revisions
        WHERE promotion_target_id=(slot->>'source_target_id')::uuid AND project_id=(slot->>'project_id')::uuid
          AND revision_number=(slot->'current_relationship'->>'revision_number')::integer;
      expected_revision:=base.revision_number;
      FOR payload IN SELECT * FROM fixture_0142_project_payloads facts WHERE facts.project_id=(slot->>'project_id')::uuid
        AND facts.source_target_id=(slot->>'source_target_id')::uuid ORDER BY staged_at_utc,pending_fact_id LOOP
        expected_revision:=expected_revision+1;
        SELECT * INTO STRICT applied FROM app_data.promotion_target_relationship_revisions
          WHERE promotion_target_id=payload.source_target_id AND project_id=payload.project_id AND revision_number=expected_revision;
        PERFORM pg_temp.assert_0142(applied.old_stage=base.new_stage AND applied.old_lifecycle_status=base.new_lifecycle_status
          AND applied.new_stage=payload.new_stage AND applied.new_lifecycle_status=payload.new_lifecycle_status
          AND applied.follow_up_note IS NOT DISTINCT FROM payload.follow_up_note AND applied.reason_code=payload.reason_code
          AND applied.reason_detail IS NOT DISTINCT FROM payload.reason_detail AND applied.changed_at=payload.staged_at_utc
          AND applied.changed_fields=ARRAY['pending_source_assignment']::text[] AND applied.merge_generation_id=p.generation_id
          AND EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_history_applications_v1 application
            WHERE application.pending_fact_id=payload.pending_fact_id AND application.request_id=p.request_id
              AND application.original_revision_number=base.revision_number AND application.applied_revision_number=expected_revision),
          'project raw history, same-value event, original base, binding, or marker was lost');
      END LOOP;
      SELECT value INTO STRICT choice FROM jsonb_array_elements(p.project_choices) value
        WHERE value->>'project_id'=slot->>'project_id' AND value->>'source_target_id'=slot->>'source_target_id';
      IF choice->>'candidate_kind'='pending' THEN
        SELECT new_stage,new_lifecycle_status,follow_up_note INTO STRICT selected FROM fixture_0142_project_payloads WHERE pending_fact_id=(choice->>'pending_fact_id')::uuid;
      ELSE selected:=base;
      END IF;
      expected_revision:=expected_revision+1;
      SELECT * INTO STRICT final_revision FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id=(slot->>'source_target_id')::uuid AND project_id=(slot->>'project_id')::uuid AND revision_number=expected_revision;
      PERFORM pg_temp.assert_0142(final_revision.old_stage=base.new_stage AND final_revision.old_lifecycle_status=base.new_lifecycle_status
        AND final_revision.new_stage=selected.new_stage AND final_revision.new_lifecycle_status=selected.new_lifecycle_status
        AND final_revision.follow_up_note IS NOT DISTINCT FROM selected.follow_up_note AND final_revision.changed_at=p.applied_at
        AND final_revision.reason_code='correction' AND final_revision.reason_detail='Confirmed pending project relationship current selection'
        AND final_revision.changed_fields=ARRAY['pending_current_selection']::text[]
          ||CASE WHEN base.new_stage<>selected.new_stage THEN ARRAY['stage'] ELSE ARRAY[]::text[] END
          ||CASE WHEN base.new_lifecycle_status<>selected.new_lifecycle_status THEN ARRAY['lifecycle_status'] ELSE ARRAY[]::text[] END
          ||CASE WHEN base.follow_up_note IS DISTINCT FROM selected.follow_up_note THEN ARRAY['follow_up_note'] ELSE ARRAY[]::text[] END
        AND EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships parent WHERE parent.project_id=(slot->>'project_id')::uuid
          AND parent.promotion_target_id=(slot->>'source_target_id')::uuid AND parent.current_revision=expected_revision
          AND parent.current_stage=selected.new_stage AND parent.current_lifecycle_status=selected.new_lifecycle_status
          AND parent.current_follow_up_note IS NOT DISTINCT FROM selected.follow_up_note),'project explicit current or real stage metrics differ');
    END LOOP;
  END LOOP;
END $joint_success$;

DO $unrelated$
DECLARE before_state jsonb:=(SELECT state FROM fixture_0142_before_state); after_state jsonb:=pg_temp.fixture_database_state(); key text;
BEGIN
  FOREACH key IN ARRAY ARRAY['app_data.contact_revisions','app_data.contact_answers','app_data.contact_target_links','app_data.contact_location_provenance',
    'app_data.processed_commands','app_data.change_feed','app_data.warehouse_outbox','app_data.contact_audit_events','app_data.promotion_target_relationship_revisions',
    'app_private.deidentified_location_anomaly_ids'] LOOP
    PERFORM pg_temp.assert_0142((before_state->key)<@(after_state->key),'mixed confirmation rewrote an old append-only row in '||key);
  END LOOP;
  FOR key IN SELECT jsonb_object_keys(before_state) LOOP
    IF key=ANY(ARRAY['app_data.contacts','app_data.contact_revisions','app_data.contact_answers','app_data.contact_target_links','app_data.contact_location_provenance',
      'app_data.processed_commands','app_data.change_feed','app_data.warehouse_outbox','app_data.contact_audit_events',
      'app_data.promotion_target_project_relationships','app_data.promotion_target_relationship_revisions',
      'app_private.personal_merge_contact_history_applications_v1','app_private.personal_merge_contact_current_revisions_v1',
      'app_private.personal_merge_contact_current_choices_v1','app_private.personal_merge_contact_resolution_requests_v1',
      'app_private.personal_merge_project_relationship_history_applications_v1','app_private.personal_merge_project_relationship_current_choices_v1',
      'app_private.personal_merge_project_relationship_resolution_requests_v1','app_private.personal_merge_mixed_resolution_requests_v1',
      'app_private.personal_target_merge_active_members_v1','app_private.personal_target_merge_end_events_v1',
      'app_data.personal_merge_unassigned_contact_facts_v1','app_data.personal_merge_unassigned_project_relationship_facts_v1',
      'app_private.personal_target_merge_generation_fence_v1','app_private.deidentified_location_anomaly_ids']) THEN CONTINUE; END IF;
    PERFORM pg_temp.assert_0142((before_state->key)=(after_state->key),'mixed confirmation changed unrelated table '||key);
  END LOOP;
  PERFORM pg_temp.assert_0142((SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(before_state->'app_data.contacts') value
    WHERE value->>'contact_id' NOT IN(SELECT contact FROM fixture_0142_contacts))=
    (SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(after_state->'app_data.contacts') value
    WHERE value->>'contact_id' NOT IN(SELECT contact FROM fixture_0142_contacts)),'mixed confirmation changed another contact');
  PERFORM pg_temp.assert_0142(NOT EXISTS(SELECT 1 FROM fixture_0142_before_relations old
    JOIN app_data.promotion_target_project_relationships live USING(promotion_target_id,project_id)
    WHERE NOT EXISTS(SELECT 1 FROM fixture_0142_project_pending pending WHERE pending.project_id=old.project_id AND pending.source_target_id=old.promotion_target_id)
      AND to_jsonb(old) IS DISTINCT FROM to_jsonb(live)),'contact application changed an unrelated project current base');
  PERFORM pg_temp.assert_0142(NOT EXISTS(SELECT 1 FROM app_private.deidentified_location_anomaly_ids mapped
    WHERE NOT (before_state->'app_private.deidentified_location_anomaly_ids')@>jsonb_build_array(to_jsonb(mapped))
      AND NOT EXISTS(SELECT 1 FROM app_data.contact_location_provenance source
        JOIN fixture_0142_before_contacts old USING(contact_id)
        WHERE source.source_id=mapped.source_id AND source.revision_number>old.current_revision
          AND source.revision_kind='corrected' AND source.location_kind='pending_resolution' AND source.evidence_kind='pending_coordinates'))
    AND NOT EXISTS(SELECT 1 FROM app_data.contact_location_provenance source JOIN fixture_0142_before_contacts old USING(contact_id)
      WHERE source.revision_number>old.current_revision AND source.revision_kind='corrected'
        AND source.location_kind='pending_resolution' AND source.evidence_kind='pending_coordinates'
        AND NOT EXISTS(SELECT 1 FROM app_private.deidentified_location_anomaly_ids mapped WHERE mapped.source_id=source.source_id)),
    'ordinary contact provenance anomaly mapping escaped the affected revisions');
END $unrelated$;
CREATE FUNCTION pg_temp.replay_0142() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE p record; mapping jsonb; choices jsonb; project_mapping jsonb; project_choices jsonb; before_state jsonb:=pg_temp.fixture_database_state();
BEGIN
  FOR p IN SELECT plan.*,result.confirmed_at FROM fixture_0142_plans plan JOIN fixture_0142_results result USING(kind) LOOP
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ordinal DESC)
      INTO mapping FROM jsonb_array_elements(p.assignments) WITH ORDINALITY items(value,ordinal);
    SELECT jsonb_agg(value||jsonb_build_object('source_target_id',upper(value->>'source_target_id'),
      'pending_fact_id',CASE WHEN value->>'pending_fact_id' IS NULL THEN 'null'::jsonb ELSE to_jsonb(upper(value->>'pending_fact_id')) END) ORDER BY ordinal DESC)
      INTO choices FROM jsonb_array_elements(p.choices) WITH ORDINALITY items(value,ordinal);
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ordinal DESC)
      INTO project_mapping FROM jsonb_array_elements(p.project_assignments) WITH ORDINALITY items(value,ordinal);
    SELECT jsonb_agg(value||jsonb_build_object('project_id',upper(value->>'project_id'),'source_target_id',upper(value->>'source_target_id'),
      'pending_fact_id',CASE WHEN value->>'pending_fact_id' IS NULL THEN 'null'::jsonb ELSE to_jsonb(upper(value->>'pending_fact_id')) END) ORDER BY ordinal DESC)
      INTO project_choices FROM jsonb_array_elements(p.project_choices) WITH ORDINALITY items(value,ordinal);
    PERFORM pg_temp.assert_0142(pg_temp.fixture_0142_confirm(p.kind)=p.confirmed_at
      AND pg_temp.fixture_0142_confirm(p.kind,mapping,choices,NULL,project_mapping,project_choices)=p.confirmed_at,
      'mixed exact/canonical replay changed the original end time');
  END LOOP;
  PERFORM pg_temp.assert_0142(before_state=pg_temp.fixture_database_state(),'mixed replay reapplied history, restored PII, or changed context/fence');
END $function$;
SELECT pg_temp.replay_0142();
DO $old_terminal_receipts$
DECLARE p record; c record; before_state jsonb:=pg_temp.fixture_database_state();
BEGIN
  SELECT * INTO STRICT c FROM fixture_0142_context;
  FOR p IN SELECT plan.*,result.confirmed_at FROM fixture_0142_plans plan JOIN fixture_0142_results result USING(kind) LOOP
    PERFORM pg_temp.assert_0142(app_private.confirm_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,
      (SELECT project_id FROM fixture_0142_projects WHERE name='b'),p.request_id,p.generation_id,
      p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.document->>'resolution_fingerprint',p.assignments,p.choices)=p.confirmed_at
      AND app_private.confirm_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,
      (SELECT project_id FROM fixture_0142_projects WHERE name='b'),p.request_id,p.generation_id,
      p.project_document->'known_source_plan'->>'fact_fingerprint',p.project_document->>'pending_fingerprint',p.project_document->>'resolution_fingerprint',
      p.project_assignments,p.project_choices)=p.confirmed_at,'old terminal metadata replay changed its existing contract');
  END LOOP;
  PERFORM pg_temp.assert_0142(before_state=pg_temp.fixture_database_state(),'old single-family terminal replay wrote mixed facts');
END $old_terminal_receipts$;
DO $replay_drift$
DECLARE p record; family text; mapping jsonb; choices jsonb;
BEGIN
  SELECT * INTO STRICT p FROM fixture_0142_plans WHERE kind='person';
  FOREACH family IN ARRAY ARRAY['contact','project'] LOOP
    mapping:=CASE family WHEN 'contact' THEN p.assignments ELSE p.project_assignments END;
    mapping:=jsonb_set(mapping,'{0,source_target_id}',to_jsonb(CASE mapping->0->>'source_target_id'
      WHEN '7f420000-0000-4000-8000-00000000000a' THEN '7f420000-0000-4000-8000-00000000000b' ELSE '7f420000-0000-4000-8000-00000000000a' END));
    choices:=CASE family WHEN 'contact' THEN p.choices ELSE p.project_choices END;
    choices:=jsonb_set(jsonb_set(choices,'{0,candidate_kind}','"pending"'::jsonb),'{0,pending_fact_id}',to_jsonb(gen_random_uuid()::text));
    IF family='contact' THEN
      PERFORM pg_temp.fixture_0142_expect('23505',format('SELECT pg_temp.fixture_0142_confirm(''person'',%L::jsonb)',mapping));
      PERFORM pg_temp.fixture_0142_expect('23505',format('SELECT pg_temp.fixture_0142_confirm(''person'',NULL,%L::jsonb)',choices));
    ELSE
      PERFORM pg_temp.fixture_0142_expect('23505',format('SELECT pg_temp.fixture_0142_confirm(''person'',NULL,NULL,NULL,%L::jsonb)',mapping));
      PERFORM pg_temp.fixture_0142_expect('23505',format('SELECT pg_temp.fixture_0142_confirm(''person'',NULL,NULL,NULL,NULL,%L::jsonb)',choices));
    END IF;
  END LOOP;
END $replay_drift$;
SELECT pg_temp.assert_0142(result->>'status'='accepted','post-mixed ordinary project edit was not accepted')
FROM fixture_0142_context c,fixture_0142_projects b,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,b.project_id,
  '7f420000-0000-4000-8000-00000000000b',(SELECT current_revision FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id='7f420000-0000-4000-8000-00000000000b' AND project_id=b.project_id),
  3,'active','0142 later ordinary note','correction',NULL,'0142-later-project-edit',NULL) updated WHERE b.name='b';
SELECT pg_temp.assert_0142(NOT app_private.personal_merge_mixed_resolution_proof_v1(c.app_user_id,p.request_id),'later edit unexpectedly retained the old live proof')
FROM fixture_0142_context c,fixture_0142_plans p WHERE p.kind='person';
SELECT pg_temp.replay_0142();
SELECT pg_temp.assert_0142(result->>'status'='anonymized','post-mixed withdrawal was not accepted')
FROM fixture_0142_context c,fixture_0142_projects b,LATERAL app_data.apply_promotion_target_retention_action(c.app_user_id,c.workspace_id,b.project_id,
  '7f420000-0000-4000-8000-00000000000b','anonymize','withdrawal','0142-later-withdrawal') action WHERE b.name='b';
SELECT pg_temp.assert_0142(NOT EXISTS(SELECT 1 FROM app_data.promotion_target_relationship_revisions
  WHERE promotion_target_id='7f420000-0000-4000-8000-00000000000b' AND (follow_up_note IS NOT NULL OR requested_follow_up_note IS NOT NULL
    OR reason_detail IS DISTINCT FROM CASE reason_code WHEN 'other' THEN '[已匿名化]' ELSE NULL END)),
  'withdrawal did not redact mixed project history');
SELECT pg_temp.replay_0142();
SELECT pg_temp.fixture_0142_expect('55000','UPDATE app_private.personal_merge_mixed_resolution_requests_v1 SET resolution_fingerprint=resolution_fingerprint');
SELECT pg_temp.fixture_0142_expect('55000','DELETE FROM app_private.personal_merge_mixed_resolution_requests_v1');
SELECT pg_temp.assert_0142(NOT has_function_privilege('public',
  'app_private.confirm_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('tongxingzhe_runtime',
  'app_private.confirm_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE'),
  'mixed confirmer is exposed to PUBLIC or runtime');
ROLLBACK;
