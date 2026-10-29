\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0143_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0143-7ff.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0143-7ff.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0143_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0143-7ff.example.test','other');
CREATE TEMP TABLE fixture_0143_projects ON COMMIT DROP AS SELECT 'a'::text AS name,c.* FROM fixture_0143_context c;
INSERT INTO fixture_0143_projects SELECT 'b',p.* FROM app_data.create_personal_project_context('https://synthetic-0143-7ff.example.test','owner','0143 project B') p;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,is_required,allow_unknown,allow_refused,allow_not_applicable,maximum_length)
SELECT questionnaire_version_id,'old_' || name,1,'0143 retained answer ' || name,CASE name WHEN 'b' THEN 'long_text' ELSE 'boolean' END,false,true,true,true,
 CASE name WHEN 'b' THEN 2000 ELSE NULL END FROM fixture_0143_projects;
INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current) VALUES ('0143-region-v1','draft',false);
INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind) VALUES
 ('0143-country','0143-region-v1',NULL,'0143 Country','country'),('0143-city','0143-region-v1','0143-country','0143 City','city'),
 ('0143-venue','0143-region-v1','0143-city','0143 Venue','venue');
INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
VALUES ('0143-boundary','0143-venue','0143-region-v1',polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))');
SELECT app_private.publish_canonical_region_tree_v1('0143-region-v1',true);
CREATE TEMP TABLE fixture_0143_pairs(kind text,target_type text,first_target uuid,second_target uuid,generation_id uuid,old_generation_id uuid);
CREATE TEMP TABLE fixture_0143_nonpair(name text,target_id uuid);
DO $targets$
DECLARE c record; kind text; target_type text; first_id uuid; second_id uuid; name text; target_id uuid;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0143_context;
 FOREACH kind IN ARRAY ARRAY['person','institution','existing'] LOOP
  target_type:=CASE kind WHEN 'existing' THEN 'person' ELSE kind END;
  SELECT (target->>'target_id')::uuid INTO STRICT first_id FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
   target_type,'0143-7ff first '||kind,'+1 312 555 0143',NULL,'0143-7ff-'||kind||'-first');
  SELECT (target->>'target_id')::uuid INTO STRICT second_id FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
   target_type,'0143-7ff second '||kind,'+1 312 555 0143',NULL,'0143-7ff-'||kind||'-second');
  INSERT INTO fixture_0143_pairs VALUES(kind,target_type,first_id,second_id,NULL,NULL);
 END LOOP;
 FOREACH name IN ARRAY ARRAY['historical','current'] LOOP
  SELECT (target->>'target_id')::uuid INTO STRICT target_id FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
   'person','0143-7ff nonpair '||name,NULL,NULL,'0143-7ff-nonpair-'||name);
  INSERT INTO fixture_0143_nonpair VALUES(name,target_id);
 END LOOP;
END $targets$;

DO $existing_relationships$
DECLARE c record; target record; contact text; code text;
BEGIN
  FOR c IN TABLE fixture_0143_projects LOOP
    PERFORM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',c.project_id);
    FOR target IN SELECT * FROM app_data.promotion_targets WHERE workspace_id=c.workspace_id
      AND NOT(c.name='a' AND promotion_target_id=(SELECT first_target FROM fixture_0143_pairs WHERE kind='person'))
      AND NOT(c.name='b' AND promotion_target_id IN(SELECT second_target FROM fixture_0143_pairs WHERE kind IN('person','institution')))
      AND NOT(c.name='a' AND promotion_target_id=(SELECT second_target FROM fixture_0143_pairs WHERE kind='institution')) LOOP
      contact:='0143-7ff-entry-'||c.name||'-'||target.promotion_target_id;
      SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,contact||'-submit',1,'contact.submit.v1','0143-7ff-device',contact,0,
        jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
          'reason','0143 real existing relationship','occurredAtUtc','2025-01-01T00:00:00Z','occurredTimeZone','UTC','channel','video_call',
          'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
          'targetLinks',jsonb_build_array(jsonb_build_object('targetId',target.promotion_target_id,'targetType',target.target_type,
            'responseLevel',NULL,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
      IF code<>'accepted' THEN RAISE EXCEPTION '0143 real relationship entry was not accepted: %',code; END IF;
    END LOOP;
  END LOOP;
END $existing_relationships$;

DO $activate$
DECLARE c record; p record; preview uuid; generation uuid; fingerprint text;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0143_context;
 PERFORM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',c.project_id);
 FOR p IN SELECT * FROM fixture_0143_pairs LOOP
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0143-7ff.example.test','owner',c.project_id,p.first_target,p.second_target);
  generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target);
  SELECT fact_fingerprint INTO STRICT fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(generation);
  PERFORM app_private.end_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,fingerprint);
  UPDATE fixture_0143_pairs SET old_generation_id = generation WHERE kind = p.kind;
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0143-7ff.example.test','owner',c.project_id,p.first_target,p.second_target);
  UPDATE fixture_0143_pairs SET generation_id = app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target) WHERE kind = p.kind;
 END LOOP;
END $activate$;
SELECT result FROM fixture_0143_context c,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  (SELECT second_target FROM fixture_0143_pairs WHERE kind='person'),1,1,'active','0143 original current project note','progress_update',NULL,'0143-real-parent-head',NULL) updated;
CREATE TEMP TABLE fixture_0143_contacts(contact text PRIMARY KEY,project_name text,kind text) ON COMMIT DROP;
INSERT INTO fixture_0143_contacts VALUES ('0143-7ff A | "TEXT": 汉字','a','person'),('0143-7ff-a','b','person'),('0143-7ff-institution','a','institution'),('0143-7ff-existing','a','existing');
CREATE FUNCTION pg_temp.fixture_0143_submit(contact text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; result record;
BEGIN
 SELECT p.* INTO STRICT c FROM fixture_0143_contacts t JOIN fixture_0143_projects p ON p.name = t.project_name WHERE t.contact = $1;
 PERFORM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',c.project_id);
 SELECT s.* INTO result FROM app_data.apply_contact_submit_v3(c.app_user_id,contact || '-submit',1,'contact.submit.v1','0143-7ff-device',contact,0,
  jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
   'reason','0143 historical original','occurredAtUtc','2025-05-03T04:05:06.123456Z','occurredTimeZone','America/Chicago',
   'channel',CASE WHEN contact = '0143-7ff A | "TEXT": 汉字' OR c.name = 'b' THEN 'face_to_face' ELSE 'video_call' END,
   'location',CASE WHEN contact = '0143-7ff A | "TEXT": 汉字' THEN jsonb_build_object('kind','resolved','placeName','0143 Venue','smallestRegionId','0143-venue','regionTreeVersion','0143-region-v1')
    WHEN c.name = 'b' THEN jsonb_build_object('kind','pending_resolution','latitude',41.7897,'longitude',-87.5997,'accuracyMeters',8.5) ELSE jsonb_build_object('kind','not_applicable') END,
   'reachCount',2,'interestLevel',3,
   'answers',jsonb_build_array(jsonb_build_object('questionId','old_' || c.name,'state','answered','type',CASE c.name WHEN 'b' THEN 'long_text' ELSE 'boolean' END,
    'value',CASE c.name WHEN 'b' THEN to_jsonb('0143 B original text: 汉字'::text) ELSE 'true'::jsonb END)),
   'targetLinks',jsonb_build_array(jsonb_build_object('targetId',(SELECT target_id FROM fixture_0143_nonpair WHERE name='historical'),'targetType','person','responseLevel',1,
    'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
  || CASE WHEN contact = '0143-7ff A | "TEXT": 汉字' THEN jsonb_build_object('locationSource',jsonb_build_object('kind','captured_coordinates','latitude',41.7897,'longitude',-87.5997,'accuracyMeters',8.5,
   'resolverContractVersion','canonical-region-resolution:v1','regionTreeContentFingerprint',(SELECT content_fingerprint FROM app_data.canonical_region_tree_releases WHERE tree_version = '0143-region-v1'))) ELSE '{}'::jsonb END) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0143 submit rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0143_submit(contact) FROM fixture_0143_contacts ORDER BY contact COLLATE "C";
CREATE TEMP TABLE fixture_0143_pending(kind text,contact text,pending_fact_id uuid,source_target_id uuid,original_revision integer,response integer,consent text,representative boolean,entry boolean) ON COMMIT DROP;
CREATE FUNCTION pg_temp.fixture_0143_stage(contact text,source uuid,response integer,consent text,representative boolean,entry boolean) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; generation uuid; revision integer; pending uuid;
BEGIN
 SELECT p.*,t.kind INTO STRICT c FROM fixture_0143_contacts t JOIN fixture_0143_projects p ON p.name = t.project_name WHERE t.contact = $1;
 PERFORM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',c.project_id);
 SELECT generation_id INTO STRICT generation FROM fixture_0143_pairs WHERE kind = c.kind;
 SELECT current_revision INTO STRICT revision FROM app_data.contacts WHERE contact_id = $1;
 pending := app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),generation,contact,revision,response,consent,representative,entry);
 INSERT INTO fixture_0143_pending VALUES(c.kind,contact,pending,source,revision,response,consent,representative,entry);
END $function$;
CREATE FUNCTION pg_temp.fixture_0143_revise(contact text,links jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; old app_data.contacts%ROWTYPE; snapshot jsonb; result record;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0143_context;
 SELECT * INTO STRICT old FROM app_data.contacts WHERE contact_id = $1;
 SELECT r.snapshot INTO STRICT snapshot FROM app_data.contact_revisions r WHERE r.contact_id = $1 AND r.revision_number = old.current_revision;
 SELECT s.* INTO result FROM app_data.apply_contact_revise_v3(c.app_user_id,contact || '-revise-' || old.current_revision,1,'contact.revise.v1','0143-7ff-device',contact,old.current_revision,
  snapshot || jsonb_build_object('reason','0143 revision ' || old.current_revision,'interestLevel',old.current_revision % 5,
   'occurredAtUtc',timestamptz '2025-05-03T04:05:06.123456Z' + old.current_revision * interval '1 day 1 microsecond',
   'answers',jsonb_build_array(CASE WHEN contact = '0143-7ff-a' THEN jsonb_build_object('questionId','old_b','state','answered','type','long_text','value','0143 B revised text ' || old.current_revision || ': 不同答案')
    ELSE jsonb_build_object('questionId','old_a','state',CASE old.current_revision WHEN 2 THEN 'unknown' WHEN 3 THEN 'refused' ELSE 'answered' END,'type','boolean',
     'value',CASE old.current_revision WHEN 1 THEN 'false'::jsonb WHEN 2 THEN 'null'::jsonb WHEN 3 THEN 'null'::jsonb ELSE 'true'::jsonb END) END))
  || CASE WHEN contact = '0143-7ff A | "TEXT": 汉字' THEN jsonb_build_object('locationSource',(snapshot->'locationSource') || jsonb_build_object('latitude',41.7897 + old.current_revision * 0.0001,'accuracyMeters',8.5 + old.current_revision))
    WHEN contact = '0143-7ff-a' THEN jsonb_build_object('location',(snapshot->'location') || jsonb_build_object('latitude',41.7897 + old.current_revision * 0.0001,'accuracyMeters',8.5 + old.current_revision)) ELSE '{}'::jsonb END
  || CASE WHEN links IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('targetLinks',links) END) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0143 revise rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0143_stage('0143-7ff A | "TEXT": 汉字',(SELECT first_target FROM fixture_0143_pairs WHERE kind='person'),0,'yes',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff A | "TEXT": 汉字');
SELECT pg_temp.fixture_0143_stage('0143-7ff A | "TEXT": 汉字',(SELECT first_target FROM fixture_0143_pairs WHERE kind='person'),4,'no',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff A | "TEXT": 汉字');
SELECT pg_temp.fixture_0143_stage('0143-7ff A | "TEXT": 汉字',(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'),0,'yes',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff A | "TEXT": 汉字',jsonb_set((SELECT r.snapshot->'targetLinks' FROM app_data.contact_revisions r WHERE contact_id = '0143-7ff A | "TEXT": 汉字' AND revision_number = 3),'{0,targetId}',to_jsonb((SELECT target_id::text FROM fixture_0143_nonpair WHERE name='current'))) || jsonb_build_array(
 jsonb_build_object('targetId',(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'),'targetType','person','responseLevel',3,'followUpConsent','refused','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
-- Simulate bindings that predate this generation while retaining the original snapshot and business values.
ALTER TABLE app_data.contact_target_links DISABLE TRIGGER contact_target_links_merge_generation_immutable;
UPDATE app_data.contact_target_links SET merge_generation_id = CASE WHEN promotion_target_id = (SELECT first_target FROM fixture_0143_pairs WHERE kind='person') THEN NULL ELSE (SELECT old_generation_id FROM fixture_0143_pairs WHERE kind = 'person') END
WHERE contact_id = '0143-7ff A | "TEXT": 汉字' AND revision_number = 4 AND promotion_target_id IN ((SELECT first_target FROM fixture_0143_pairs WHERE kind='person'),(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'));
ALTER TABLE app_data.contact_target_links ENABLE TRIGGER contact_target_links_merge_generation_immutable;
SELECT pg_temp.fixture_0143_stage('0143-7ff-a',(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'),2,'yes',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff-a');
SELECT pg_temp.fixture_0143_stage('0143-7ff-a',(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'),2,'yes',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff-a',(SELECT snapshot->'targetLinks' FROM app_data.contact_revisions
 WHERE contact_id='0143-7ff-a' AND revision_number=2)||jsonb_build_array(jsonb_build_object(
 'targetId',(SELECT first_target FROM fixture_0143_pairs WHERE kind='person'),'targetType','person','responseLevel',1,
 'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
SELECT pg_temp.fixture_0143_stage('0143-7ff-institution',(SELECT first_target FROM fixture_0143_pairs WHERE kind='institution'),NULL,'not_applicable',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff-institution');
SELECT pg_temp.fixture_0143_stage('0143-7ff-institution',(SELECT second_target FROM fixture_0143_pairs WHERE kind='institution'),4,'yes',true,true);
SELECT pg_temp.fixture_0143_stage('0143-7ff-existing',(SELECT first_target FROM fixture_0143_pairs WHERE kind='existing'),1,'no',false,true);
SELECT pg_temp.fixture_0143_revise('0143-7ff-existing');
SELECT pg_temp.fixture_0143_stage('0143-7ff-existing',(SELECT first_target FROM fixture_0143_pairs WHERE kind='existing'),1,'no',false,true);

CREATE TEMP TABLE fixture_0143_project_pending(kind text,project_id uuid,pending_fact_id uuid,source_target_id uuid);
DO $project_pending$
DECLARE pair record; c record; repeat_number integer; pending uuid; stage integer;
BEGIN
  FOR pair IN TABLE fixture_0143_pairs LOOP
    FOR c IN TABLE fixture_0143_projects LOOP
      PERFORM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',c.project_id);
      FOR repeat_number IN 1..2 LOOP
        stage:=CASE WHEN c.name='b' AND repeat_number=1 THEN 4 ELSE 2 END;
        SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
          gen_random_uuid(),pair.generation_id,stage,'paused',E'  0143 private project note\n原值  ',CASE stage WHEN 4 THEN 'other' ELSE 'progress_update' END,E'  0143 private detail\t');
        INSERT INTO fixture_0143_project_pending VALUES(pair.kind,c.project_id,pending,CASE c.name WHEN 'a' THEN pair.first_target ELSE pair.second_target END);
      END LOOP;
    END LOOP;
  END LOOP;
  FOR pair IN SELECT * FROM fixture_0143_pairs WHERE kind IN('person','institution') LOOP
    SELECT * INTO STRICT c FROM fixture_0143_projects WHERE name='a';
    PERFORM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',c.project_id);
    SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
      gen_random_uuid(),pair.generation_id,3,'paused','0143 overlap or explicit existing current','progress_update',NULL);
    INSERT INTO fixture_0143_project_pending VALUES(pair.kind,c.project_id,pending,pair.second_target);
  END LOOP;
END $project_pending$;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0143-7ff.example.test','owner',(SELECT project_id FROM fixture_0143_projects WHERE name='b'));
CREATE TEMP TABLE fixture_0143_plans AS
SELECT pair.kind,pair.generation_id,gen_random_uuid() AS request_id,
  app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS pending_plan,
  app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS project_inventory,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id)
    FROM fixture_0143_pending pending WHERE pending.kind=pair.kind) AS assignments,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id)
    FROM fixture_0143_project_pending pending WHERE pending.kind=pair.kind) AS project_assignments,
  NULL::jsonb AS mixed_document,NULL::jsonb AS document,NULL::jsonb AS project_document,NULL::jsonb AS choices,NULL::jsonb AS project_choices
FROM fixture_0143_pairs pair,fixture_0143_context c,fixture_0143_projects b WHERE b.name='b';
UPDATE fixture_0143_plans p SET mixed_document=app_private.plan_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.pending_plan->'known_source_plan'->>'fact_fingerprint',p.pending_plan->>'pending_fingerprint',p.project_inventory->>'pending_fingerprint',
  p.assignments,p.project_assignments)
FROM fixture_0143_context c,fixture_0143_projects b WHERE b.name='b';
UPDATE fixture_0143_plans SET document=mixed_document->'contact_resolution_plan',project_document=mixed_document->'project_relationship_resolution_plan';
UPDATE fixture_0143_plans p SET choices=(SELECT jsonb_agg(jsonb_build_object('contact_id',slot->>'contact_id','source_target_id',slot->>'source_target_id',
  'candidate_kind',CASE WHEN (slot->>'contact_id'='0143-7ff A | "TEXT": 汉字' AND (slot->>'source_target_id')::uuid=(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'))
    OR NOT EXISTS(SELECT 1 FROM fixture_0143_pending pending WHERE pending.contact=slot->>'contact_id' AND pending.source_target_id=(slot->>'source_target_id')::uuid) THEN 'current' ELSE 'pending' END,
  'pending_fact_id',CASE WHEN (slot->>'contact_id'='0143-7ff A | "TEXT": 汉字' AND (slot->>'source_target_id')::uuid=(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'))
    OR NOT EXISTS(SELECT 1 FROM fixture_0143_pending pending WHERE pending.contact=slot->>'contact_id' AND pending.source_target_id=(slot->>'source_target_id')::uuid) THEN NULL ELSE
    (SELECT pending_fact_id::text FROM fixture_0143_pending pending WHERE pending.contact=slot->>'contact_id'
      AND pending.source_target_id=(slot->>'source_target_id')::uuid ORDER BY original_revision,pending_fact_id LIMIT 1) END)
  ORDER BY slot->>'contact_id' COLLATE "C",(slot->>'source_target_id')::uuid) FROM jsonb_array_elements(p.document->'source_slots') slot);
UPDATE fixture_0143_plans p SET project_choices=(SELECT jsonb_agg(jsonb_build_object('project_id',slot->>'project_id','source_target_id',slot->>'source_target_id',
  'candidate_kind',CASE WHEN slot->>'project_id'=(SELECT project_id::text FROM fixture_0143_projects WHERE name='a')
    AND (p.kind='existing' OR (p.kind='person' AND (slot->>'source_target_id')::uuid=(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'))) THEN 'current' ELSE 'pending' END,
  'pending_fact_id',CASE WHEN slot->>'project_id'=(SELECT project_id::text FROM fixture_0143_projects WHERE name='a')
    AND (p.kind='existing' OR (p.kind='person' AND (slot->>'source_target_id')::uuid=(SELECT second_target FROM fixture_0143_pairs WHERE kind='person'))) THEN 'null'::jsonb ELSE slot->'pending_fact_ids'->0 END)
  ORDER BY (slot->>'project_id')::uuid,(slot->>'source_target_id')::uuid) FROM jsonb_array_elements(p.project_document->'source_slots') slot);
\ir shared/database_state.sql
CREATE FUNCTION pg_temp.assert_0143(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0143 %',label; END IF;
END $function$;
ALTER TABLE fixture_0143_plans ADD COLUMN acknowledgements jsonb;
UPDATE fixture_0143_plans p SET acknowledgements=(SELECT coalesce(jsonb_agg(jsonb_build_object(
 'project_id',choice->>'project_id','source_target_id',choice->>'source_target_id','pending_fact_id',choice->>'pending_fact_id')
 ORDER BY (choice->>'project_id')::uuid,(choice->>'source_target_id')::uuid),'[]'::jsonb)
 FROM jsonb_array_elements(p.project_choices) choice JOIN jsonb_array_elements(p.project_document->'source_slots') slot
 ON choice->>'project_id'=slot->>'project_id' AND choice->>'source_target_id'=slot->>'source_target_id'
 WHERE slot->'current_relationship'='null'::jsonb);
CREATE FUNCTION pg_temp.fixture_0143_confirm(kind text,mapping jsonb DEFAULT NULL,choices jsonb DEFAULT NULL,request uuid DEFAULT NULL,
  project_mapping jsonb DEFAULT NULL,project_choices jsonb DEFAULT NULL,acks jsonb DEFAULT NULL) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.confirm_personal_merge_mixed_resolutions_v2(c.app_user_id,c.workspace_id,b.project_id,coalesce($4,p.request_id),p.generation_id,
    p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.project_document->>'pending_fingerprint',p.mixed_document->>'resolution_fingerprint',
    coalesce($2,p.assignments),coalesce($3,p.choices),coalesce($5,p.project_assignments),coalesce($6,p.project_choices),coalesce($7,p.acknowledgements))
  FROM fixture_0143_context c,fixture_0143_projects b,fixture_0143_plans p WHERE b.name='b' AND p.kind=$1
$function$;
CREATE FUNCTION pg_temp.fixture_0143_expect(expected text,command text,expected_detail text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb:=pg_temp.fixture_database_state(); actual text; detail text;
BEGIN
  BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE,detail=MESSAGE_TEXT; END;
  IF actual IS DISTINCT FROM expected OR(expected_detail IS NOT NULL AND detail IS DISTINCT FROM expected_detail) THEN
    RAISE EXCEPTION '0143 expected % / %, got % / %',expected,expected_detail,actual,detail;
  END IF;
  PERFORM pg_temp.assert_0143(before_state=pg_temp.fixture_database_state(),'failed mixed confirmation changed persistent state');
END $function$;
CREATE TEMP TABLE fixture_0143_before_revisions AS SELECT revision.* FROM app_data.contact_revisions revision JOIN fixture_0143_contacts fixture ON fixture.contact=revision.contact_id;
CREATE TEMP TABLE fixture_0143_before_answers AS SELECT answer.* FROM app_data.contact_answers answer JOIN fixture_0143_contacts fixture ON fixture.contact=answer.contact_id;
CREATE TEMP TABLE fixture_0143_before_provenance AS SELECT provenance.* FROM app_data.contact_location_provenance provenance JOIN fixture_0143_contacts fixture ON fixture.contact=provenance.contact_id;
CREATE TEMP TABLE fixture_0143_before_links AS SELECT link.* FROM app_data.contact_target_links link JOIN fixture_0143_contacts fixture ON fixture.contact=link.contact_id;
CREATE TEMP TABLE fixture_0143_before_contacts AS SELECT contact.* FROM app_data.contacts contact JOIN fixture_0143_contacts fixture ON fixture.contact=contact.contact_id;
CREATE TEMP TABLE fixture_0143_before_relations AS SELECT * FROM app_data.promotion_target_project_relationships;
CREATE TEMP TABLE fixture_0143_before_project_revisions AS SELECT * FROM app_data.promotion_target_relationship_revisions;
CREATE TEMP TABLE fixture_0143_project_payloads AS SELECT header.*,payload.new_stage,payload.new_lifecycle_status,payload.follow_up_note,payload.reason_code,payload.reason_detail,pending.source_target_id
FROM fixture_0143_project_pending pending JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 payload USING(pending_fact_id);
CREATE TEMP TABLE fixture_0143_before_state AS SELECT pg_temp.fixture_database_state() AS state;

SELECT pg_temp.assert_0143((SELECT jsonb_array_length(acknowledgements)=2 FROM fixture_0143_plans WHERE kind='person')
 AND (SELECT jsonb_array_length(acknowledgements)=2 FROM fixture_0143_plans WHERE kind='institution')
 AND (SELECT acknowledgements='[]'::jsonb FROM fixture_0143_plans WHERE kind='existing'),'missing and existing slot setup differs');
SELECT pg_temp.fixture_0143_expect('22023',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',bad))
FROM(VALUES('null'),('{}'),('[null]'),('[{"project_id":"bad","source_target_id":"bad","pending_fact_id":"bad"}]')) malformed(bad);
SELECT pg_temp.fixture_0143_expect('22023',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',bad))
FROM fixture_0143_plans p,LATERAL(VALUES(p.acknowledgements||jsonb_build_array(p.acknowledgements->0)),
 (jsonb_build_array((p.acknowledgements->0)-'pending_fact_id')),
 (jsonb_build_array((p.acknowledgements->0)||jsonb_build_object('extra',true)))) malformed(bad) WHERE p.kind='person';
SELECT pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',bad))
FROM fixture_0143_plans p,LATERAL(VALUES('[]'::jsonb),(jsonb_build_array(p.acknowledgements->0)),
 (jsonb_set(p.acknowledgements,'{0,pending_fact_id}',to_jsonb(gen_random_uuid()::text))),
 (jsonb_set(p.acknowledgements,'{0,project_id}',to_jsonb(gen_random_uuid()::text)))) malformed(bad) WHERE p.kind='person';
DO $wrong_slot$
DECLARE p record; extra jsonb; choices jsonb; wrong jsonb;
BEGIN
 SELECT * INTO STRICT p FROM fixture_0143_plans WHERE kind='person';
 SELECT jsonb_build_object('project_id',slot->>'project_id','source_target_id',slot->>'source_target_id','pending_fact_id',slot->'pending_fact_ids'->>0)
 INTO STRICT extra FROM jsonb_array_elements(p.project_document->'source_slots') slot WHERE slot->'current_relationship'<>'null'::jsonb;
 PERFORM pg_temp.assert_0143(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p.acknowledgements) ack
  WHERE ack->>'pending_fact_id'=extra->>'pending_fact_id' OR (ack->>'project_id'=extra->>'project_id' AND ack->>'source_target_id'=extra->>'source_target_id')),
  'existing-slot extra acknowledgement accidentally duplicates a missing slot');
 PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',p.acknowledgements||jsonb_build_array(extra)));
 wrong:=jsonb_set(p.acknowledgements,'{0,pending_fact_id}',extra->'pending_fact_id');
 PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',wrong));
 SELECT jsonb_set(p.acknowledgements,'{0,pending_fact_id}',slot->'pending_fact_ids'->1) INTO STRICT wrong
 FROM jsonb_array_elements(p.project_document->'source_slots') slot
 WHERE slot->>'project_id'=p.acknowledgements->0->>'project_id' AND slot->>'source_target_id'=p.acknowledgements->0->>'source_target_id';
 PERFORM pg_temp.assert_0143(wrong->0->>'pending_fact_id' IS NOT NULL AND wrong<>p.acknowledgements,'same-slot wrong candidate setup differs');
 PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',wrong));
 SELECT jsonb_agg(CASE WHEN choice->>'project_id'=p.acknowledgements->0->>'project_id' AND choice->>'source_target_id'=p.acknowledgements->0->>'source_target_id'
  THEN choice||jsonb_build_object('candidate_kind','current','pending_fact_id',NULL) ELSE choice END) INTO choices FROM jsonb_array_elements(p.project_choices) choice;
 PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,%L::jsonb)',choices));
END $wrong_slot$;
SELECT pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',%L::jsonb)',jsonb_build_array(assignments->0))) FROM fixture_0143_plans WHERE kind='person';
SELECT pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,%L::jsonb)',jsonb_build_array(choices->0))) FROM fixture_0143_plans WHERE kind='person';
SELECT pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,%L::jsonb)',jsonb_build_array(project_assignments->0))) FROM fixture_0143_plans WHERE kind='person';
SELECT pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,%L::jsonb)',jsonb_build_array(project_choices->0))) FROM fixture_0143_plans WHERE kind='person';
SELECT pg_temp.fixture_0143_expect(expected,format('SELECT app_private.confirm_personal_merge_mixed_resolutions_v2(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb,%L::jsonb,%L::jsonb,%L::jsonb)',
 CASE field WHEN 'actor' THEN other.app_user_id ELSE c.app_user_id END,c.workspace_id,b.project_id,p.request_id,p.generation_id,
 CASE field WHEN 'known' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
 CASE field WHEN 'contact' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,
 CASE field WHEN 'project' THEN repeat('0',64) ELSE p.project_document->>'pending_fingerprint' END,
 CASE field WHEN 'mixed' THEN repeat('0',64) ELSE p.mixed_document->>'resolution_fingerprint' END,
 p.assignments,p.choices,p.project_assignments,p.project_choices,p.acknowledgements))
FROM fixture_0143_context c,fixture_0143_other other,fixture_0143_projects b,fixture_0143_plans p,
 (VALUES('known','23505'),('contact','23505'),('project','23505'),('mixed','23505'),('actor','42501')) invalid(field,expected) WHERE b.name='b' AND p.kind='person';
DO $closure$
DECLARE missing record; c record;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0143_context;
 FOR missing IN SELECT target_id,c.project_id FROM fixture_0143_nonpair UNION SELECT first_target,
  (SELECT project_id FROM fixture_0143_projects WHERE name='b') FROM fixture_0143_pairs WHERE kind='person' LOOP
  BEGIN
   SET LOCAL session_replication_role=replica;
   DELETE FROM app_data.promotion_target_project_relationships WHERE promotion_target_id=missing.target_id AND project_id=missing.project_id;
   SET LOCAL session_replication_role=origin;
   UPDATE fixture_0143_plans p SET pending_plan=app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,
    (SELECT project_id FROM fixture_0143_projects WHERE name='b'),p.generation_id),
    project_inventory=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,
    (SELECT project_id FROM fixture_0143_projects WHERE name='b'),p.generation_id) WHERE kind='person';
   UPDATE fixture_0143_plans p SET mixed_document=app_private.plan_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,
    (SELECT project_id FROM fixture_0143_projects WHERE name='b'),p.generation_id,p.pending_plan->'known_source_plan'->>'fact_fingerprint',
    p.pending_plan->>'pending_fingerprint',p.project_inventory->>'pending_fingerprint',p.assignments,p.project_assignments) WHERE kind='person';
   UPDATE fixture_0143_plans SET document=mixed_document->'contact_resolution_plan',project_document=mixed_document->'project_relationship_resolution_plan' WHERE kind='person';
   PERFORM pg_temp.fixture_0143_expect('55000','SELECT pg_temp.fixture_0143_confirm(''person'')','mixed project entry requires existing unacknowledged project relationships');
   RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
 END LOOP;
END $closure$;
SAVEPOINT revoked;
UPDATE app_data.promotion_target_assignments SET ended_at=clock_timestamp(),end_reason='0143 revoked historical nonpair'
WHERE promotion_target_id=(SELECT target_id FROM fixture_0143_nonpair WHERE name='historical') AND ended_at IS NULL;
SELECT pg_temp.fixture_0143_expect('42501','SELECT pg_temp.fixture_0143_confirm(''person'')');
ROLLBACK TO revoked;
RELEASE revoked;
SAVEPOINT due;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years' WHERE promotion_target_id=(SELECT first_target FROM fixture_0143_pairs WHERE kind='person');
SELECT pg_temp.fixture_0143_expect('42501','SELECT pg_temp.fixture_0143_confirm(''person'')');
ROLLBACK TO due;
RELEASE due;
SAVEPOINT archived;
UPDATE app_data.projects SET status='archived' WHERE project_id=(SELECT project_id FROM fixture_0143_projects WHERE name='a');
SELECT pg_temp.fixture_0143_expect('42501','SELECT pg_temp.fixture_0143_confirm(''person'')');
ROLLBACK TO archived;
RELEASE archived;

CREATE FUNCTION pg_temp.fault_0143() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF TG_TABLE_NAME='promotion_target_relationship_revisions' THEN
  IF TG_ARGV[0] LIKE 'application_%' AND NEW.reason_code='project_entry' THEN RETURN NEW; END IF;
 END IF;
 IF TG_ARGV[0] IN('raise','application_raise') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='0143 injected write failure'; END IF;
 RETURN NULL;
END $function$;
DO $faults$
DECLARE relation text; operation text; mode text;
BEGIN
 FOR relation,operation IN SELECT * FROM(VALUES
  ('app_data.promotion_target_project_relationships','INSERT'),('app_data.promotion_target_relationship_revisions','INSERT'),
  ('app_private.personal_merge_mixed_project_entry_requests_v1','INSERT'),('app_private.personal_merge_mixed_project_entry_origins_v1','INSERT'),
  ('app_data.contact_revisions','INSERT'),('app_private.personal_merge_contact_current_revisions_v1','INSERT'),
  ('app_private.personal_merge_contact_resolution_requests_v1','INSERT'),('app_private.personal_merge_project_relationship_resolution_requests_v1','INSERT'),
  ('app_private.personal_merge_mixed_resolution_requests_v1','INSERT'),('app_private.personal_target_merge_end_events_v1','INSERT'),
  ('app_data.personal_merge_unassigned_contact_facts_v1','DELETE'),('app_data.personal_merge_unassigned_project_relationship_facts_v1','DELETE')) writes(name,operation) LOOP
  FOREACH mode IN ARRAY CASE WHEN relation='app_data.promotion_target_relationship_revisions'
    THEN ARRAY['raise','suppress','application_raise','application_suppress'] ELSE ARRAY['raise','suppress'] END LOOP
   EXECUTE format('CREATE TRIGGER fixture_0143_fault BEFORE %s ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.fault_0143(%L)',operation,relation,mode);
   RAISE NOTICE '0143 injected % % %',relation,operation,mode;
   PERFORM pg_temp.fixture_0143_expect(CASE WHEN mode IN('raise','application_raise') THEN 'P0001' WHEN relation='app_data.contact_revisions' THEN '23503' ELSE '55000' END,
    'SELECT pg_temp.fixture_0143_confirm(''person'')');
   EXECUTE format('DROP TRIGGER fixture_0143_fault ON %s',relation);
  END LOOP;
 END LOOP;
END $faults$;
CREATE FUNCTION pg_temp.tamper_0143() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF TG_TABLE_NAME='personal_merge_mixed_project_entry_origins_v1' THEN NEW.initialized_at_utc:=NEW.initialized_at_utc-interval '1 second';
 ELSIF TG_TABLE_NAME='personal_merge_contact_resolution_requests_v1' THEN NEW.pending_fingerprint:=repeat('0',64);
 ELSE NEW.resolution_fingerprint:=repeat('0',64); END IF;
 RETURN NEW;
END $function$;
DO $tamper$
DECLARE relation text;
BEGIN
 FOREACH relation IN ARRAY ARRAY['app_private.personal_merge_mixed_project_entry_requests_v1','app_private.personal_merge_mixed_project_entry_origins_v1',
  'app_private.personal_merge_contact_resolution_requests_v1','app_private.personal_merge_project_relationship_resolution_requests_v1','app_private.personal_merge_mixed_resolution_requests_v1'] LOOP
  EXECUTE format('CREATE TRIGGER fixture_0143_tamper BEFORE INSERT ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.tamper_0143()',relation);
  PERFORM pg_temp.fixture_0143_expect('55000','SELECT pg_temp.fixture_0143_confirm(''person'')');
  EXECUTE format('DROP TRIGGER fixture_0143_tamper ON %s',relation);
 END LOOP;
END $tamper$;
SELECT pg_temp.fixture_0143_expect('23503',$statement$
DO $deferred$ DECLARE c record; p record;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0143_context;
 SELECT * INTO STRICT p FROM fixture_0143_plans WHERE kind='person';
 INSERT INTO app_private.personal_merge_mixed_project_entry_requests_v1 VALUES(c.app_user_id,p.request_id,c.workspace_id,
  (SELECT project_id FROM fixture_0143_projects WHERE name='b'),p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint',
  p.document->>'pending_fingerprint',p.project_document->>'pending_fingerprint',p.mixed_document->>'resolution_fingerprint',
  p.document->'known_source_plan'->>'fact_fingerprint',p.mixed_document->>'resolution_fingerprint',clock_timestamp());
 PERFORM pg_temp.assert_0143(NOT app_private.personal_merge_mixed_project_entry_resolution_proof_v1(c.app_user_id,p.request_id),'empty origins and missing inner receipt passed proof');
 SET CONSTRAINTS ALL IMMEDIATE;
END $deferred$;
$statement$);
CREATE TEMP TABLE fixture_0143_results AS SELECT kind,pg_temp.fixture_0143_confirm(kind) AS ended_at FROM fixture_0143_plans ORDER BY kind;
SET CONSTRAINTS ALL IMMEDIATE;
DO $success$
DECLARE n record; t record; original jsonb; applied jsonb; current_snapshot jsonb; final_snapshot jsonb; expected_revision integer; choice jsonb;
BEGIN
 IF (SELECT count(*) FROM app_private.personal_merge_contact_resolution_requests_v1 WHERE workspace_id = (SELECT workspace_id FROM fixture_0143_context)) <> 3
  OR (SELECT count(*) FROM app_private.personal_merge_contact_history_applications_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0143_pending)) <> 9
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_revisions_v1 WHERE contact_id IN (SELECT contact FROM fixture_0143_contacts)) <> 4
  OR (SELECT count(*) FROM app_private.personal_merge_contact_current_choices_v1 WHERE contact_id IN (SELECT contact FROM fixture_0143_contacts)) <> 7
  OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0143_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0143_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id IN (SELECT generation_id FROM fixture_0143_pairs))
 THEN RAISE EXCEPTION '0143 exact history/current receipts, payload consumption or merge end drift'; END IF;
 IF EXISTS (SELECT 1 FROM fixture_0143_before_revisions b LEFT JOIN app_data.contact_revisions r USING(contact_id,revision_number) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(r))
  OR EXISTS (SELECT 1 FROM fixture_0143_before_answers b LEFT JOIN app_data.contact_answers a USING(contact_id,revision_number,question_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(a))
  OR EXISTS (SELECT 1 FROM fixture_0143_before_links b LEFT JOIN app_data.contact_target_links l USING(contact_id,revision_number,promotion_target_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(l))
  OR EXISTS (SELECT 1 FROM fixture_0143_before_provenance b LEFT JOIN app_data.contact_location_provenance p USING(source_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(p))
 THEN RAISE EXCEPTION '0143 rewrote original revisions, answers, NULL binding or old generation binding'; END IF;
 FOR t IN SELECT b.*,p.kind,p.request_id,p.generation_id FROM fixture_0143_before_contacts b JOIN fixture_0143_contacts fixture_contact ON fixture_contact.contact = b.contact_id JOIN fixture_0143_plans p USING(kind) ORDER BY b.contact_id COLLATE "C" LOOP
  expected_revision := t.current_revision;
  FOR n IN SELECT * FROM fixture_0143_pending WHERE contact = t.contact_id ORDER BY original_revision,pending_fact_id LOOP
   expected_revision := expected_revision + 1;
   SELECT snapshot INTO STRICT original FROM fixture_0143_before_revisions WHERE contact_id = n.contact AND revision_number = n.original_revision;
   SELECT snapshot INTO STRICT applied FROM app_data.contact_revisions WHERE contact_id = n.contact AND revision_number = expected_revision;
   IF (original - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM (applied - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
    OR (applied->>'occurredAtUtc')::timestamptz IS DISTINCT FROM (original->>'occurredAtUtc')::timestamptz
    OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = n.original_revision)
     IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = expected_revision)
    OR (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM fixture_0143_before_provenance p WHERE contact_id = n.contact AND revision_number = n.original_revision)
     IS DISTINCT FROM (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM app_data.contact_location_provenance p WHERE contact_id = n.contact AND revision_number = expected_revision)
    OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links l WHERE contact_id = n.contact AND revision_number = expected_revision AND promotion_target_id = n.source_target_id
     AND response_level IS NOT DISTINCT FROM n.response AND follow_up_consent = n.consent AND institution_representative_confirmed = n.representative AND confirmed_project_entry = n.entry AND merge_generation_id = t.generation_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.processed_commands p WHERE p.app_user_id = t.app_user_id AND p.command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':pending:' || n.pending_fact_id AND p.result_code = 'accepted' AND p.server_cursor IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_history_applications_v1 a WHERE a.pending_fact_id = n.pending_fact_id AND a.actor_app_user_id = t.app_user_id AND a.request_id = t.request_id
     AND a.contact_id = n.contact AND a.original_revision_number = n.original_revision AND a.from_revision_number = expected_revision - 1 AND a.to_revision_number = expected_revision AND a.source_target_id = n.source_target_id
     AND a.child_command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':pending:' || n.pending_fact_id)

    OR (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM fixture_0143_before_links link
      WHERE contact_id=n.contact AND revision_number=n.original_revision AND promotion_target_id NOT IN
        (SELECT first_target FROM fixture_0143_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0143_pairs WHERE kind=t.kind))
      IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM app_data.contact_target_links link
      WHERE contact_id=n.contact AND revision_number=expected_revision AND promotion_target_id NOT IN
        (SELECT first_target FROM fixture_0143_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0143_pairs WHERE kind=t.kind))
   THEN RAISE EXCEPTION '0143 historical application lost snapshot, answers, explicit business values or accepted child: %/%',n.contact,n.original_revision; END IF;
  END LOOP;
  expected_revision := expected_revision + 1;
  SELECT snapshot INTO STRICT current_snapshot FROM fixture_0143_before_revisions WHERE contact_id = t.contact_id AND revision_number = t.current_revision;
  SELECT snapshot INTO STRICT final_snapshot FROM app_data.contact_revisions WHERE contact_id = t.contact_id AND revision_number = expected_revision;
  IF (current_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc']) IS DISTINCT FROM (final_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
   OR (final_snapshot->>'occurredAtUtc')::timestamptz IS DISTINCT FROM (current_snapshot->>'occurredAtUtc')::timestamptz
   OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM fixture_0143_before_answers a WHERE contact_id = t.contact_id AND revision_number = t.current_revision)
    IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = t.contact_id AND revision_number = expected_revision)
   OR (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM fixture_0143_before_provenance p WHERE contact_id = t.contact_id AND revision_number = t.current_revision)
    IS DISTINCT FROM (SELECT to_jsonb(p) - ARRAY['source_id','revision_number','revision_kind','recorded_at_utc'] FROM app_data.contact_location_provenance p WHERE contact_id = t.contact_id AND revision_number = expected_revision)
   OR NOT EXISTS (SELECT 1 FROM app_data.contacts c WHERE c.contact_id = t.contact_id AND c.current_revision = expected_revision AND c.project_id = t.project_id AND c.questionnaire_version_id = t.questionnaire_version_id AND c.occurred_at_utc = t.occurred_at_utc)
   OR NOT EXISTS (SELECT 1 FROM app_data.processed_commands p WHERE p.app_user_id = t.app_user_id AND p.command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':current:' || octet_length(t.contact_id) || ':' || t.contact_id AND p.result_code = 'accepted' AND p.server_cursor IS NOT NULL)
   OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_current_revisions_v1 a WHERE a.actor_app_user_id = t.app_user_id AND a.request_id = t.request_id AND a.contact_id = t.contact_id
    AND a.original_revision_number = t.current_revision AND a.from_revision_number = expected_revision - 1 AND a.to_revision_number = expected_revision
    AND a.child_command_id = 'personal-merge-contact-resolve-v1:' || t.request_id || ':current:' || octet_length(t.contact_id) || ':' || t.contact_id)
   OR jsonb_array_length(final_snapshot->'targetLinks') <> 1 + (SELECT count(*) FROM fixture_0143_plans p CROSS JOIN LATERAL jsonb_array_elements(p.choices) value WHERE value->>'contact_id' = t.contact_id)

   OR (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM fixture_0143_before_links link
     WHERE contact_id=t.contact_id AND revision_number=t.current_revision AND promotion_target_id NOT IN
       (SELECT first_target FROM fixture_0143_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0143_pairs WHERE kind=t.kind))
     IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(link)-'revision_number' ORDER BY promotion_target_id) FROM app_data.contact_target_links link
     WHERE contact_id=t.contact_id AND revision_number=expected_revision AND promotion_target_id NOT IN
       (SELECT first_target FROM fixture_0143_pairs WHERE kind=t.kind UNION SELECT second_target FROM fixture_0143_pairs WHERE kind=t.kind))
  THEN RAISE EXCEPTION '0143 final current snapshot, old questionnaire, event time or child drift: %',t.contact_id; END IF;
  FOR choice IN SELECT value FROM fixture_0143_plans p CROSS JOIN LATERAL jsonb_array_elements(p.choices) WHERE value->>'contact_id' = t.contact_id LOOP
   IF choice->>'candidate_kind' = 'current' THEN
    IF NOT EXISTS (SELECT 1 FROM fixture_0143_before_links b JOIN app_data.contact_target_links l USING(contact_id,promotion_target_id)
     WHERE b.contact_id = t.contact_id AND b.revision_number = t.current_revision AND l.revision_number = expected_revision AND l.promotion_target_id = (choice->>'source_target_id')::uuid
     AND (to_jsonb(b) - ARRAY['revision_number','merge_generation_id']) = (to_jsonb(l) - ARRAY['revision_number','merge_generation_id']) AND l.merge_generation_id = t.generation_id)
    THEN RAISE EXCEPTION '0143 explicit current choice lost original business values'; END IF;
   ELSE
    IF NOT EXISTS (SELECT 1 FROM fixture_0143_pending selected_pending JOIN app_data.contact_target_links l ON l.contact_id = selected_pending.contact AND l.promotion_target_id = selected_pending.source_target_id
     WHERE selected_pending.pending_fact_id = (choice->>'pending_fact_id')::uuid AND l.revision_number = expected_revision AND l.response_level IS NOT DISTINCT FROM selected_pending.response
     AND l.follow_up_consent = selected_pending.consent AND l.institution_representative_confirmed = selected_pending.representative AND l.confirmed_project_entry = selected_pending.entry AND l.merge_generation_id = t.generation_id)
    THEN RAISE EXCEPTION '0143 explicit older pending choice was replaced or folded'; END IF;
   END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_data.contact_revisions r WHERE r.contact_id = t.contact_id AND r.revision_number > t.current_revision
   AND (NOT EXISTS (SELECT 1 FROM app_data.change_feed f WHERE f.aggregate_id = r.contact_id AND f.revision_number = r.revision_number AND f.change_type = 'contact.revised' AND f.project_id = t.project_id)
    OR NOT EXISTS (SELECT 1 FROM app_data.warehouse_outbox w WHERE w.contact_id = r.contact_id AND w.revision_number = r.revision_number AND w.project_id = t.project_id AND jsonb_array_length(w.analytics_payload->'target_link_facts') = jsonb_array_length(r.snapshot->'targetLinks'))))
   OR (SELECT count(*) FROM app_data.contact_audit_events a WHERE a.contact_id = t.contact_id AND a.command_id LIKE 'personal-merge-contact-resolve-v1:%' AND a.event_type = 'contact.revised') <> expected_revision - t.current_revision
  THEN RAISE EXCEPTION '0143 feed, audit, outbox or unrelated link lost original project scope'; END IF;
 END LOOP;
 IF (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0143_context)) IS DISTINCT FROM (SELECT project_id FROM fixture_0143_projects WHERE name = 'b')
 THEN RAISE EXCEPTION '0143 changed selected project'; END IF;
END $success$;
DO $entries$
DECLARE p record; ack jsonb; origin record; parent record; initial record;
BEGIN
 PERFORM pg_temp.assert_0143((SELECT count(*) FROM app_private.personal_merge_mixed_project_entry_origins_v1
  WHERE request_id IN(SELECT request_id FROM fixture_0143_plans))=4
  AND (SELECT count(*) FROM app_data.promotion_target_project_relationships)=(SELECT count(*)+4 FROM fixture_0143_before_relations)
  AND (SELECT count(*) FROM app_data.promotion_target_relationship_revisions WHERE reason_code='project_entry')=
   (SELECT count(*)+4 FROM fixture_0143_before_project_revisions WHERE reason_code='project_entry')
  AND NOT EXISTS(SELECT 1 FROM fixture_0143_before_relations old JOIN app_data.promotion_target_project_relationships live USING(promotion_target_id,project_id)
   WHERE old.merge_generation_id IS DISTINCT FROM live.merge_generation_id)
  AND NOT EXISTS(SELECT 1 FROM fixture_0143_before_project_revisions old LEFT JOIN app_data.promotion_target_relationship_revisions live USING(promotion_target_id,project_id,revision_number)
   WHERE to_jsonb(old) IS DISTINCT FROM to_jsonb(live)),'entry set, original binding or old relationship history differs');
 FOR p IN SELECT plans.*,results.ended_at,outer_request.initialized_at_utc FROM fixture_0143_plans plans JOIN fixture_0143_results results USING(kind)
  JOIN app_private.personal_merge_mixed_project_entry_requests_v1 outer_request ON outer_request.request_id=plans.request_id LOOP
  PERFORM pg_temp.assert_0143(app_private.personal_merge_mixed_project_entry_resolution_proof_v1((SELECT app_user_id FROM fixture_0143_context),p.request_id)
   AND app_private.personal_merge_mixed_resolution_proof_v1((SELECT app_user_id FROM fixture_0143_context),p.request_id)
   AND (SELECT count(*) FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=p.generation_id)=1
   AND NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 WHERE pending_fact_id IN
    (SELECT pending_fact_id FROM fixture_0143_project_pending WHERE kind=p.kind))
   AND EXISTS(SELECT 1 FROM app_private.personal_merge_mixed_project_entry_requests_v1 wrapper
    JOIN app_private.personal_merge_mixed_resolution_requests_v1 inner_request USING(actor_app_user_id,request_id)
    JOIN app_private.personal_merge_contact_resolution_requests_v1 contact USING(actor_app_user_id,request_id)
    JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 project USING(actor_app_user_id,request_id)
    JOIN app_private.personal_target_merge_end_events_v1 ended USING(actor_app_user_id,request_id)
    WHERE wrapper.request_id=p.request_id AND wrapper.workspace_id=contact.workspace_id AND wrapper.project_id=contact.project_id
     AND wrapper.generation_id=inner_request.generation_id AND contact.generation_id=project.generation_id AND contact.generation_id=p.generation_id
     AND wrapper.known_fact_fingerprint=p.document->'known_source_plan'->>'fact_fingerprint'
     AND wrapper.contact_pending_fingerprint=p.document->>'pending_fingerprint' AND wrapper.project_pending_fingerprint=p.project_document->>'pending_fingerprint'
     AND wrapper.resolution_fingerprint=p.mixed_document->>'resolution_fingerprint'
     AND wrapper.internal_known_fact_fingerprint=contact.known_fact_fingerprint AND contact.known_fact_fingerprint=project.known_fact_fingerprint
     AND wrapper.internal_resolution_fingerprint=inner_request.resolution_fingerprint
     AND contact.pending_fingerprint=wrapper.contact_pending_fingerprint AND project.pending_fingerprint=wrapper.project_pending_fingerprint
     AND contact.post_known_fact_fingerprint=project.post_known_fact_fingerprint AND contact.post_known_fact_fingerprint=ended.fact_fingerprint
     AND contact.confirmed_at_utc=project.confirmed_at_utc AND ended.ended_at_utc=p.ended_at
     AND (wrapper.known_fact_fingerprint<>wrapper.internal_known_fact_fingerprint)=(jsonb_array_length(p.acknowledgements)>0)),
   'outer/inner metadata, native proofs, single end or payload consumption differs');
  FOR ack IN SELECT value FROM jsonb_array_elements(p.acknowledgements) LOOP
   SELECT * INTO STRICT origin FROM app_private.personal_merge_mixed_project_entry_origins_v1 WHERE request_id=p.request_id
    AND project_id=(ack->>'project_id')::uuid AND source_target_id=(ack->>'source_target_id')::uuid;
   SELECT * INTO STRICT parent FROM app_data.promotion_target_project_relationships WHERE project_id=origin.project_id AND promotion_target_id=origin.source_target_id;
   SELECT * INTO STRICT initial FROM app_data.promotion_target_relationship_revisions WHERE project_id=origin.project_id AND promotion_target_id=origin.source_target_id AND revision_number=1;
   PERFORM pg_temp.assert_0143(origin.pending_fact_id=(ack->>'pending_fact_id')::uuid AND origin.initial_revision_number=1
    AND origin.initialized_at_utc=p.initialized_at_utc AND initial.changed_at=p.initialized_at_utc AND parent.established_at=p.initialized_at_utc
    AND p.initialized_at_utc>(SELECT staged_at_utc FROM fixture_0143_project_payloads WHERE pending_fact_id=origin.pending_fact_id)
    AND p.initialized_at_utc<=p.ended_at AND parent.established_by_app_user_id=(SELECT app_user_id FROM fixture_0143_context)
    AND initial.changed_by_app_user_id=parent.established_by_app_user_id AND initial.merge_generation_id=p.generation_id AND parent.merge_generation_id=p.generation_id
    AND initial.old_stage IS NULL AND initial.new_stage=0 AND initial.old_lifecycle_status IS NULL AND initial.new_lifecycle_status='active'
    AND initial.follow_up_note IS NULL AND initial.reason_detail IS NULL AND initial.reason_code='project_entry'
    AND initial.changed_fields=ARRAY['stage','lifecycle_status']::text[] AND initial.mutation_id IS NULL AND initial.requested_base_revision IS NULL,
    'origin did not prove a real actor/time/revision-one stage-zero administrative entry');
  END LOOP;
 END LOOP;
END $entries$;
DO $project_history$
DECLARE payload record; revision record; base record; p record; slot jsonb; choice jsonb; selected record; final_revision record;
BEGIN
 FOR payload IN SELECT facts.*,application.original_revision_number,application.applied_revision_number FROM fixture_0143_project_payloads facts
  JOIN app_private.personal_merge_project_relationship_history_applications_v1 application USING(pending_fact_id) LOOP
  SELECT * INTO STRICT revision FROM app_data.promotion_target_relationship_revisions WHERE project_id=payload.project_id
   AND promotion_target_id=payload.source_target_id AND revision_number=payload.applied_revision_number;
  SELECT * INTO STRICT base FROM app_data.promotion_target_relationship_revisions WHERE project_id=payload.project_id
   AND promotion_target_id=payload.source_target_id AND revision_number=payload.original_revision_number;
  PERFORM pg_temp.assert_0143(revision.old_stage=base.new_stage AND revision.old_lifecycle_status=base.new_lifecycle_status
   AND revision.new_stage=payload.new_stage AND revision.new_lifecycle_status=payload.new_lifecycle_status
   AND revision.follow_up_note IS NOT DISTINCT FROM payload.follow_up_note AND revision.reason_code=payload.reason_code
   AND revision.reason_detail IS NOT DISTINCT FROM payload.reason_detail AND revision.changed_at=payload.staged_at_utc
   AND revision.merge_generation_id=payload.generation_id AND revision.changed_fields=ARRAY['pending_source_assignment']::text[],
   'raw historical project event or same-value marker was lost');
 END LOOP;
 FOR p IN SELECT plans.*,request.confirmed_at_utc FROM fixture_0143_plans plans
  JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 request USING(request_id) LOOP
  FOR slot IN SELECT value FROM jsonb_array_elements(p.project_document->'source_slots') LOOP
   SELECT * INTO STRICT base FROM app_data.promotion_target_relationship_revisions WHERE project_id=(slot->>'project_id')::uuid
    AND promotion_target_id=(slot->>'source_target_id')::uuid AND revision_number=coalesce((slot->'current_relationship'->>'revision_number')::integer,1);
   SELECT value INTO STRICT choice FROM jsonb_array_elements(p.project_choices) value WHERE value->>'project_id'=slot->>'project_id' AND value->>'source_target_id'=slot->>'source_target_id';
   IF choice->>'candidate_kind'='pending' THEN
    SELECT new_stage,new_lifecycle_status,follow_up_note INTO STRICT selected FROM fixture_0143_project_payloads WHERE pending_fact_id=(choice->>'pending_fact_id')::uuid;
   ELSE selected:=base; END IF;
   SELECT live_revision.* INTO STRICT final_revision FROM app_data.promotion_target_project_relationships parent
    JOIN app_data.promotion_target_relationship_revisions live_revision USING(project_id,promotion_target_id)
    WHERE parent.project_id=(slot->>'project_id')::uuid AND parent.promotion_target_id=(slot->>'source_target_id')::uuid AND live_revision.revision_number=parent.current_revision;
   PERFORM pg_temp.assert_0143(final_revision.old_stage=base.new_stage AND final_revision.new_stage=selected.new_stage
    AND final_revision.old_lifecycle_status=base.new_lifecycle_status AND final_revision.new_lifecycle_status=selected.new_lifecycle_status
    AND final_revision.follow_up_note IS NOT DISTINCT FROM selected.follow_up_note AND final_revision.changed_at=p.confirmed_at_utc
    AND final_revision.changed_fields=ARRAY['pending_current_selection']::text[]
      ||CASE WHEN base.new_stage<>selected.new_stage THEN ARRAY['stage'] ELSE ARRAY[]::text[] END
      ||CASE WHEN base.new_lifecycle_status<>selected.new_lifecycle_status THEN ARRAY['lifecycle_status'] ELSE ARRAY[]::text[] END
      ||CASE WHEN base.follow_up_note IS DISTINCT FROM selected.follow_up_note THEN ARRAY['follow_up_note'] ELSE ARRAY[]::text[] END,
    'explicit older/current selection or real stage metrics differ');
  END LOOP;
 END LOOP;
END $project_history$;
SAVEPOINT missing_origins;
SET LOCAL session_replication_role=replica;
DELETE FROM app_private.personal_merge_mixed_project_entry_origins_v1 WHERE request_id=(SELECT request_id FROM fixture_0143_plans WHERE kind='person');
SET LOCAL session_replication_role=origin;
SELECT pg_temp.assert_0143(NOT app_private.personal_merge_mixed_project_entry_resolution_proof_v1(c.app_user_id,p.request_id),
 'a completed mixed receipt without its missing-slot origins passed proof') FROM fixture_0143_context c,fixture_0143_plans p WHERE p.kind='person';
ROLLBACK TO missing_origins;
RELEASE missing_origins;
DO $unrelated$
DECLARE before_state jsonb:=(SELECT state FROM fixture_0143_before_state); after_state jsonb:=pg_temp.fixture_database_state(); key text;
BEGIN
 FOREACH key IN ARRAY ARRAY['app_data.contact_revisions','app_data.contact_answers','app_data.contact_target_links','app_data.contact_location_provenance',
  'app_data.processed_commands','app_data.change_feed','app_data.warehouse_outbox','app_data.contact_audit_events','app_data.promotion_target_relationship_revisions',
  'app_private.deidentified_location_anomaly_ids'] LOOP
  PERFORM pg_temp.assert_0143((before_state->key)<@(after_state->key),'confirmation rewrote an old append-only row in '||key);
 END LOOP;
 FOR key IN SELECT jsonb_object_keys(before_state) LOOP
  IF key=ANY(ARRAY['app_data.contacts','app_data.contact_revisions','app_data.contact_answers','app_data.contact_target_links','app_data.contact_location_provenance',
   'app_data.processed_commands','app_data.change_feed','app_data.warehouse_outbox','app_data.contact_audit_events','app_private.deidentified_location_anomaly_ids',
   'app_data.promotion_target_project_relationships','app_data.promotion_target_relationship_revisions',
   'app_private.personal_merge_contact_history_applications_v1','app_private.personal_merge_contact_current_revisions_v1',
   'app_private.personal_merge_contact_current_choices_v1','app_private.personal_merge_contact_resolution_requests_v1',
   'app_private.personal_merge_project_relationship_history_applications_v1','app_private.personal_merge_project_relationship_current_choices_v1',
   'app_private.personal_merge_project_relationship_resolution_requests_v1','app_private.personal_merge_mixed_resolution_requests_v1',
   'app_private.personal_merge_mixed_project_entry_requests_v1','app_private.personal_merge_mixed_project_entry_origins_v1',
   'app_private.personal_target_merge_active_members_v1','app_private.personal_target_merge_end_events_v1',
   'app_data.personal_merge_unassigned_contact_facts_v1','app_data.personal_merge_unassigned_project_relationship_facts_v1',
   'app_private.personal_target_merge_generation_fence_v1']) THEN CONTINUE; END IF;
  PERFORM pg_temp.assert_0143((before_state->key)=(after_state->key),'confirmation changed an unrelated table '||key);
 END LOOP;
 PERFORM pg_temp.assert_0143((SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(before_state->'app_data.contacts') value
  WHERE value->>'contact_id' NOT IN(SELECT contact FROM fixture_0143_contacts))=
  (SELECT jsonb_agg(value ORDER BY value::text) FROM jsonb_array_elements(after_state->'app_data.contacts') value
  WHERE value->>'contact_id' NOT IN(SELECT contact FROM fixture_0143_contacts)),'entry synthesized a contact or changed another current contact');
END $unrelated$;
CREATE FUNCTION pg_temp.replay_0143() RETURNS void LANGUAGE plpgsql AS $function$
DECLARE p record; mapping jsonb; choices jsonb; project_mapping jsonb; project_choices jsonb; acks jsonb; before_state jsonb:=pg_temp.fixture_database_state();
BEGIN
 FOR p IN SELECT plan.*,result.ended_at FROM fixture_0143_plans plan JOIN fixture_0143_results result USING(kind) LOOP
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
  SELECT coalesce(jsonb_agg(jsonb_build_object('project_id',upper(value->>'project_id'),'source_target_id',upper(value->>'source_target_id'),
   'pending_fact_id',upper(value->>'pending_fact_id')) ORDER BY ordinal DESC),'[]'::jsonb)
   INTO acks FROM jsonb_array_elements(p.acknowledgements) WITH ORDINALITY items(value,ordinal);
  PERFORM pg_temp.assert_0143(pg_temp.fixture_0143_confirm(p.kind)=p.ended_at
   AND pg_temp.fixture_0143_confirm(p.kind,mapping,choices,NULL,project_mapping,project_choices,acks)=p.ended_at,'exact/canonical terminal replay changed original time');
 END LOOP;
 PERFORM pg_temp.assert_0143(before_state=pg_temp.fixture_database_state(),'terminal replay reinitialized, applied history, restored private text or changed context');
END $function$;
SELECT pg_temp.replay_0143();
SELECT pg_temp.fixture_0143_expect('23505',format('SELECT app_private.confirm_personal_merge_mixed_resolutions_v2(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb,%L::jsonb,%L::jsonb,%L::jsonb)',
 c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,
 CASE field WHEN 'known' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
 CASE field WHEN 'contact' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,
 CASE field WHEN 'project' THEN repeat('0',64) ELSE p.project_document->>'pending_fingerprint' END,
 CASE field WHEN 'mixed' THEN repeat('0',64) ELSE p.mixed_document->>'resolution_fingerprint' END,
 p.assignments,p.choices,p.project_assignments,p.project_choices,p.acknowledgements))
FROM fixture_0143_context c,fixture_0143_projects b,fixture_0143_plans p,(VALUES('known'),('contact'),('project'),('mixed')) changed(field) WHERE b.name='b' AND p.kind='person';
DO $replay_drift$
DECLARE p record; family text; mapping jsonb; choices jsonb;
BEGIN
 SELECT * INTO STRICT p FROM fixture_0143_plans WHERE kind='person';
 FOREACH family IN ARRAY ARRAY['contact','project'] LOOP
  mapping:=CASE family WHEN 'contact' THEN p.assignments ELSE p.project_assignments END;
  mapping:=jsonb_set(mapping,'{0,source_target_id}',to_jsonb(CASE (mapping->0->>'source_target_id')::uuid
   WHEN (SELECT first_target FROM fixture_0143_pairs WHERE kind='person') THEN (SELECT second_target FROM fixture_0143_pairs WHERE kind='person')
   ELSE (SELECT first_target FROM fixture_0143_pairs WHERE kind='person') END));
  choices:=CASE family WHEN 'contact' THEN p.choices ELSE p.project_choices END;
  choices:=jsonb_set(jsonb_set(choices,'{0,candidate_kind}','"pending"'::jsonb),'{0,pending_fact_id}',to_jsonb(gen_random_uuid()::text));
  IF family='contact' THEN
   PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',%L::jsonb)',mapping));
   PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,%L::jsonb)',choices));
  ELSE
   PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,%L::jsonb)',mapping));
   PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,%L::jsonb)',choices));
  END IF;
 END LOOP;
 PERFORM pg_temp.fixture_0143_expect('23505',format('SELECT pg_temp.fixture_0143_confirm(''person'',NULL,NULL,NULL,NULL,NULL,%L::jsonb)',
  jsonb_set(p.acknowledgements,'{0,pending_fact_id}',to_jsonb(gen_random_uuid()::text))));
END $replay_drift$;
SELECT pg_temp.fixture_0143_revise('0143-7ff-a');
SELECT pg_temp.assert_0143(result->>'status'='accepted','later ordinary project edit failed')
FROM fixture_0143_context c,fixture_0143_projects b,fixture_0143_pairs pair,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,b.project_id,
 pair.second_target,(SELECT current_revision FROM app_data.promotion_target_project_relationships WHERE promotion_target_id=pair.second_target AND project_id=b.project_id),
 3,'active','0143 later private note','correction',NULL,'0143-7ff-later-edit',NULL) updated WHERE b.name='b' AND pair.kind='person';
SELECT pg_temp.assert_0143(NOT app_private.personal_merge_mixed_project_entry_resolution_proof_v1(c.app_user_id,p.request_id),'later edit unexpectedly retained live proof')
FROM fixture_0143_context c,fixture_0143_plans p WHERE p.kind='person';
SELECT pg_temp.replay_0143();
SELECT pg_temp.assert_0143(result->>'status'='anonymized','later withdrawal failed')
FROM fixture_0143_context c,fixture_0143_projects b,fixture_0143_pairs pair,LATERAL app_data.apply_promotion_target_retention_action(c.app_user_id,c.workspace_id,b.project_id,
 pair.second_target,'anonymize','withdrawal','0143-7ff-later-withdrawal') action WHERE b.name='b' AND pair.kind='person';
SELECT pg_temp.assert_0143(NOT EXISTS(SELECT 1 FROM app_data.promotion_target_relationship_revisions WHERE promotion_target_id=
 (SELECT second_target FROM fixture_0143_pairs WHERE kind='person') AND (follow_up_note IS NOT NULL OR requested_follow_up_note IS NOT NULL
  OR reason_detail IS DISTINCT FROM CASE reason_code WHEN 'other' THEN '[已匿名化]' ELSE NULL END)),'withdrawal did not redact initialized and applied project history');
SELECT pg_temp.replay_0143();
SELECT pg_temp.fixture_0143_expect('55000','UPDATE app_private.personal_merge_mixed_project_entry_requests_v1 SET initialized_at_utc=initialized_at_utc');
SELECT pg_temp.fixture_0143_expect('55000','DELETE FROM app_private.personal_merge_mixed_project_entry_origins_v1');
ROLLBACK;
