-- Synthetic existing-relationship confirmation. All facts roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE FUNCTION pg_temp.assert_0138(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0138 %',label; END IF;
END $function$;
CREATE FUNCTION pg_temp.state_0138() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; result jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT schemaname,tablename FROM pg_catalog.pg_tables WHERE schemaname IN('app_data','app_private') ORDER BY schemaname,tablename LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t',relation.schemaname,relation.tablename) INTO rows;
    result := result||jsonb_build_object(relation.schemaname||'.'||relation.tablename,rows);
  END LOOP;
  RETURN result;
END $function$;
CREATE FUNCTION pg_temp.expect_0138_failure(expected_state text,expected_message text,statement text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.state_0138(); actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT; END;
  IF actual_state IS DISTINCT FROM expected_state OR(expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0138 expected % / %, got % / %',expected_state,expected_message,actual_state,actual_message;
  END IF;
  PERFORM pg_temp.assert_0138(before_state=pg_temp.state_0138(),'rejected confirmation changed persistent state');
END $function$;
CREATE TEMP TABLE fixture_0138_context AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0138.example.test','owner');
CREATE TEMP TABLE fixture_0138_other AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0138.example.test','other');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0138.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0138_projects AS SELECT 'a'::text AS name,c.* FROM fixture_0138_context c;
INSERT INTO fixture_0138_projects SELECT 'b',c.* FROM app_data.create_personal_project_context('https://synthetic-0138.example.test','owner','0138 project B') c;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0138.example.test','owner',(SELECT project_id FROM fixture_0138_context));
CREATE TEMP TABLE fixture_0138_pairs(kind text,target_type text,first_target uuid,second_target uuid,generation_id uuid);
DO $seed$
DECLARE c record; kind text; target_type text; first_target uuid; second_target uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0138_context;
  FOREACH kind IN ARRAY ARRAY['person','institution'] LOOP
    target_type := kind;
    SELECT (target->>'target_id')::uuid INTO STRICT first_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      target_type,'0138 first '||kind,'+1 312 555 0138',NULL,'0138-'||kind||'-first');
    SELECT (target->>'target_id')::uuid INTO STRICT second_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      target_type,'0138 second '||kind,'+1 312 555 0138',NULL,'0138-'||kind||'-second');
    INSERT INTO fixture_0138_pairs VALUES(kind,target_type,first_target,second_target,NULL);
  END LOOP;
END $seed$;
CREATE FUNCTION pg_temp.enter_project_0138(project_name text,kind text,source_number integer) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; pair record; source uuid; contact text; code text;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0138_projects WHERE name=$1;
  SELECT * INTO STRICT pair FROM fixture_0138_pairs p WHERE p.kind=$2;
  source := CASE source_number WHEN 1 THEN pair.first_target ELSE pair.second_target END;
  contact := '0138-entry-'||project_name||'-'||kind||'-'||source_number;
  PERFORM app_data.select_personal_project_context('https://synthetic-0138.example.test','owner',c.project_id);
  SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,contact||'-submit',1,'contact.submit.v1','0138-device',contact,0,
    jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
      'reason','0138 real project entry','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
      'targetLinks',jsonb_build_array(jsonb_build_object('targetId',source,'targetType',pair.target_type,'responseLevel',NULL,
        'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
  PERFORM pg_temp.assert_0138(code='accepted','ordinary contact revision did not create project relationship');
END $function$;
SELECT pg_temp.enter_project_0138('a','person',1);
SELECT pg_temp.enter_project_0138('a','person',2);
SELECT pg_temp.enter_project_0138('a','institution',1);
SELECT pg_temp.enter_project_0138('a','institution',2);
SELECT pg_temp.enter_project_0138('b','person',1);
SELECT pg_temp.enter_project_0138('b','person',2);
SELECT pg_temp.enter_project_0138('b','institution',1);
SELECT pg_temp.enter_project_0138('b','institution',2);
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0138.example.test','owner',(SELECT project_id FROM fixture_0138_context));
DO $activate$
DECLARE c record; pair record; preview uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0138_context;
  FOR pair IN TABLE fixture_0138_pairs LOOP
    SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0138.example.test','owner',c.project_id,pair.first_target,pair.second_target);
    UPDATE fixture_0138_pairs SET generation_id=app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,
      pair.first_target,pair.second_target,pair.first_target,pair.second_target) WHERE kind=pair.kind;
  END LOOP;
END $activate$;

SELECT result FROM fixture_0138_context c,fixture_0138_pairs pair,
  LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,pair.first_target,1,1,'active',
    '0138 original current note','progress_update',NULL,'0138-preactivation-parent-revision',NULL) updated WHERE pair.kind='person';
SELECT pg_temp.assert_0138(EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships parent
  JOIN app_data.promotion_target_relationship_revisions revision ON revision.promotion_target_id=parent.promotion_target_id
    AND revision.project_id=parent.project_id AND revision.revision_number=parent.current_revision
  JOIN fixture_0138_pairs pair ON pair.first_target=parent.promotion_target_id
  WHERE pair.kind='person' AND parent.project_id=(SELECT project_id FROM fixture_0138_context)
    AND parent.merge_generation_id IS NULL AND revision.merge_generation_id=pair.generation_id AND parent.current_revision=2),
  'real ordinary update did not retain NULL parent and bind the new head');
CREATE TEMP TABLE fixture_0138_pending(kind text,project_id uuid,pending_fact_id uuid,source_target_id uuid);
CREATE FUNCTION pg_temp.stage_0138(project_name text,kind text,source_number integer,stage integer DEFAULT 2) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; pair record; pending uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0138_projects WHERE name=$1;
  SELECT * INTO STRICT pair FROM fixture_0138_pairs p WHERE p.kind=$2;
  PERFORM app_data.select_personal_project_context('https://synthetic-0138.example.test','owner',c.project_id);
  SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
    gen_random_uuid(),pair.generation_id,stage,'paused',E'  0138 private@example.test\n原值  ','progress_update',E'  0138 raw reason\t');
  INSERT INTO fixture_0138_pending VALUES(kind,c.project_id,pending,CASE source_number WHEN 1 THEN pair.first_target ELSE pair.second_target END);
END $function$;
SELECT pg_temp.stage_0138('a','person',1);
SELECT pg_temp.stage_0138('a','person',1);
SELECT pg_temp.stage_0138('a','person',2,3);
SELECT pg_temp.stage_0138('b','person',1,4);
SELECT pg_temp.stage_0138('b','person',1,2);
SELECT pg_temp.stage_0138('b','person',2);
SELECT pg_temp.stage_0138('a','institution',1);
SELECT pg_temp.stage_0138('a','institution',1);
SELECT pg_temp.stage_0138('b','institution',2,4);
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0138.example.test','owner',(SELECT project_id FROM fixture_0138_projects WHERE name='b'));
CREATE TEMP TABLE fixture_0138_plans AS
SELECT pair.kind,pair.generation_id,gen_random_uuid() AS request_id,
  app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS inventory,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending.pending_fact_id,'source_target_id',pending.source_target_id) ORDER BY pending.pending_fact_id)
    FROM fixture_0138_pending pending WHERE pending.kind=pair.kind) AS assignments,NULL::jsonb AS document,NULL::jsonb AS choices
FROM fixture_0138_pairs pair,fixture_0138_context c,fixture_0138_projects b WHERE b.name='b';
UPDATE fixture_0138_plans p SET document=app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.inventory->'known_source_plan'->>'fact_fingerprint',p.inventory->>'pending_fingerprint',p.assignments)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b';
UPDATE fixture_0138_plans p SET choices=(SELECT jsonb_agg(jsonb_build_object('project_id',slot->>'project_id','source_target_id',slot->>'source_target_id',
  'candidate_kind',CASE WHEN slot->>'project_id'=(SELECT project_id::text FROM fixture_0138_projects WHERE name='a')
    AND slot->>'source_target_id'=(SELECT first_target::text FROM fixture_0138_pairs WHERE kind='person') THEN 'current' ELSE 'pending' END,
  'pending_fact_id',CASE WHEN slot->>'project_id'=(SELECT project_id::text FROM fixture_0138_projects WHERE name='a')
    AND slot->>'source_target_id'=(SELECT first_target::text FROM fixture_0138_pairs WHERE kind='person') THEN 'null'::jsonb ELSE slot->'pending_fact_ids'->0 END)
  ORDER BY (slot->>'project_id')::uuid,(slot->>'source_target_id')::uuid) FROM jsonb_array_elements(p.document->'source_slots') slot);
CREATE FUNCTION pg_temp.confirm_0138(kind text,mapping jsonb DEFAULT NULL,choices jsonb DEFAULT NULL) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.confirm_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,
    p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.document->>'resolution_fingerprint',
    coalesce($2,p.assignments),coalesce($3,p.choices))
  FROM fixture_0138_context c,fixture_0138_projects b,fixture_0138_plans p WHERE b.name='b' AND p.kind=$1
$function$;
CREATE TEMP TABLE fixture_0138_before_revisions AS SELECT * FROM app_data.promotion_target_relationship_revisions;
CREATE TEMP TABLE fixture_0138_before_relations AS SELECT * FROM app_data.promotion_target_project_relationships;
CREATE TEMP TABLE fixture_0138_payloads AS
SELECT header.*,payload.new_stage,payload.new_lifecycle_status,payload.follow_up_note,payload.reason_code,payload.reason_detail,
  pending.source_target_id
FROM fixture_0138_pending pending JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
JOIN app_data.personal_merge_unassigned_project_relationship_facts_v1 payload USING(pending_fact_id);
CREATE TEMP TABLE fixture_0138_before_state AS SELECT pg_temp.state_0138() AS document;
SELECT pg_temp.assert_0138((SELECT count(*)=2 FROM fixture_0138_payloads
  WHERE project_id=(SELECT project_id FROM fixture_0138_projects WHERE name='a')
    AND source_target_id=(SELECT first_target FROM fixture_0138_pairs WHERE kind='person')
    AND new_stage=2 AND new_lifecycle_status='paused' AND follow_up_note=E'  0138 private@example.test\n原值  '),'same-value pending setup differs');

SELECT pg_temp.expect_0138_failure('22023',NULL,format('SELECT pg_temp.confirm_0138(''person'',%L::jsonb)',bad))
FROM (VALUES('null'),('{}'),('[]'),('[null]'),('[1]'),('[{"pending_fact_id":"bad","source_target_id":"bad"}]')) malformed(bad);
SELECT pg_temp.expect_0138_failure('22023',NULL,format('SELECT pg_temp.confirm_0138(''person'',%L::jsonb)',assignments||jsonb_build_array(assignments->0)))
FROM fixture_0138_plans WHERE kind='person';
SELECT pg_temp.expect_0138_failure('23505',NULL,format('SELECT pg_temp.confirm_0138(''person'',%L::jsonb)',bad))
FROM fixture_0138_plans p,LATERAL(VALUES(jsonb_build_array(p.assignments->0)),
  (p.assignments||jsonb_build_array(jsonb_build_object('pending_fact_id',gen_random_uuid(),'source_target_id',p.assignments->0->>'source_target_id'))),
  (jsonb_build_array((p.assignments->0)||jsonb_build_object('source_target_id',(SELECT first_target FROM fixture_0138_pairs WHERE kind='institution')))||(p.assignments-0))) malformed(bad)
WHERE p.kind='person';
SELECT pg_temp.expect_0138_failure('22023',NULL,format('SELECT pg_temp.confirm_0138(''person'',NULL,%L::jsonb)',bad))
FROM (VALUES('null'),('{}'),('[]'),('[null]'),('[1]'),
  ('[{"project_id":"bad","source_target_id":"bad","candidate_kind":"pending","pending_fact_id":"bad"}]')) malformed(bad);
SELECT pg_temp.expect_0138_failure('22023',NULL,format('SELECT pg_temp.confirm_0138(''person'',NULL,%L::jsonb)',bad))
FROM fixture_0138_plans p,LATERAL(VALUES(p.choices||jsonb_build_array(p.choices->0)),
  (jsonb_build_array((p.choices->0)-'candidate_kind')||(p.choices-0)),
  (jsonb_build_array((p.choices->0)||jsonb_build_object('extra',true))||(p.choices-0)),
  (jsonb_build_array((p.choices->0)||jsonb_build_object('candidate_kind','latest'))||(p.choices-0)),
  (jsonb_build_array((p.choices->0)||jsonb_build_object('candidate_kind','current','pending_fact_id',gen_random_uuid()))||(p.choices-0)),
  (jsonb_build_array((p.choices->0)||jsonb_build_object('candidate_kind','pending','pending_fact_id',NULL))||(p.choices-0))) malformed(bad)
WHERE p.kind='person';
SELECT pg_temp.expect_0138_failure('23505',NULL,format('SELECT pg_temp.confirm_0138(''person'',NULL,%L::jsonb)',bad))
FROM fixture_0138_plans p,LATERAL(VALUES(jsonb_build_array(p.choices->0)),
  (jsonb_build_array((p.choices->0)||jsonb_build_object('project_id',gen_random_uuid()))||(p.choices-0)),
  (jsonb_build_array((p.choices->0)||jsonb_build_object('candidate_kind','pending','pending_fact_id',gen_random_uuid()))||(p.choices-0))) malformed(bad)
WHERE p.kind='person';
SELECT pg_temp.expect_0138_failure(expected_state,NULL,format('SELECT app_private.confirm_personal_merge_project_relationship_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
  CASE WHEN field='actor_null' THEN NULL WHEN field='other_actor' THEN other.app_user_id ELSE c.app_user_id END,
  CASE WHEN field='workspace_null' THEN NULL WHEN field='other_workspace' THEN other.workspace_id ELSE c.workspace_id END,
  CASE WHEN field='project_null' THEN NULL WHEN field='wrong_context' THEN c.project_id ELSE b.project_id END,
  CASE WHEN field='request_null' THEN NULL ELSE p.request_id END,CASE WHEN field='generation_null' THEN NULL ELSE p.generation_id END,
  CASE WHEN field='known_null' THEN NULL WHEN field='known_bad' THEN 'bad' WHEN field='known_stale' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
  CASE WHEN field='pending_null' THEN NULL WHEN field='pending_bad' THEN 'bad' WHEN field='pending_stale' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,
  CASE WHEN field='resolution_null' THEN NULL WHEN field='resolution_bad' THEN 'bad' WHEN field='resolution_stale' THEN repeat('0',64) ELSE p.document->>'resolution_fingerprint' END,
  CASE WHEN field='mapping_null' THEN NULL ELSE p.assignments END,CASE WHEN field='choices_null' THEN NULL ELSE p.choices END))
FROM fixture_0138_context c,fixture_0138_other other,fixture_0138_projects b,fixture_0138_plans p,
  (VALUES('actor_null','22023'),('workspace_null','22023'),('project_null','22023'),('request_null','22023'),('generation_null','22023'),
    ('known_null','22023'),('known_bad','22023'),('pending_null','22023'),('pending_bad','22023'),('resolution_null','22023'),('resolution_bad','22023'),
    ('mapping_null','22023'),('choices_null','22023'),('known_stale','23505'),('pending_stale','23505'),('resolution_stale','23505'),
    ('other_actor','42501'),('other_workspace','42501'),('wrong_context','42501')) cases(field,expected_state) WHERE b.name='b' AND p.kind='person';

SAVEPOINT due;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years'
WHERE promotion_target_id=(SELECT first_target FROM fixture_0138_pairs WHERE kind='person');
SELECT pg_temp.expect_0138_failure('42501',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO due;
RELEASE due;
SAVEPOINT source_assignment;
UPDATE app_data.promotion_target_assignments SET ended_at=clock_timestamp(),end_reason='0138 revocation'
WHERE promotion_target_id=(SELECT first_target FROM fixture_0138_pairs WHERE kind='person') AND ended_at IS NULL;
SELECT pg_temp.expect_0138_failure('42501',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO source_assignment;
RELEASE source_assignment;
SAVEPOINT actor_status;
UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id=(SELECT app_user_id FROM fixture_0138_context);
SELECT pg_temp.expect_0138_failure('42501',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO actor_status;
RELEASE actor_status;
SAVEPOINT missing_head;
SET LOCAL session_replication_role=replica;
DELETE FROM app_data.promotion_target_relationship_revisions WHERE (promotion_target_id,project_id,revision_number)=
  (SELECT first_target,project_id,2 FROM fixture_0138_pairs,fixture_0138_projects WHERE kind='person' AND name='a');
SET LOCAL session_replication_role=origin;
UPDATE fixture_0138_plans p SET inventory=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0138_plans SET document=jsonb_set(document,'{known_source_plan}',inventory->'known_source_plan') WHERE kind='person';
SELECT pg_temp.expect_0138_failure('55000',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO missing_head;
RELEASE missing_head;
SAVEPOINT missing_relationship;
SET LOCAL session_replication_role=replica;
DELETE FROM app_data.promotion_target_project_relationships WHERE promotion_target_id=(SELECT first_target FROM fixture_0138_pairs WHERE kind='person')
  AND project_id=(SELECT project_id FROM fixture_0138_projects WHERE name='a');
SET LOCAL session_replication_role=origin;
UPDATE fixture_0138_plans p SET inventory=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0138_plans p SET document=app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.inventory->'known_source_plan'->>'fact_fingerprint',p.inventory->>'pending_fingerprint',p.assignments)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.expect_0138_failure('55000',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO missing_relationship;
RELEASE missing_relationship;
SAVEPOINT ordinary_revision;
SELECT result FROM fixture_0138_context c,fixture_0138_pairs pair,fixture_0138_projects b,
  LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,b.project_id,pair.first_target,1,1,'active',
    '0138 concurrent real revision','progress_update',NULL,'0138-real-drift',NULL) updated WHERE pair.kind='person' AND b.name='b';
SELECT pg_temp.expect_0138_failure('23505',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO ordinary_revision;
RELEASE ordinary_revision;
SAVEPOINT inconsistent_projection;
SET LOCAL session_replication_role=replica;
UPDATE app_data.promotion_target_project_relationships SET current_stage=4,current_lifecycle_status='ended',current_follow_up_note='0138 inconsistent projection'
WHERE promotion_target_id=(SELECT first_target FROM fixture_0138_pairs WHERE kind='person')
  AND project_id=(SELECT project_id FROM fixture_0138_projects WHERE name='a');
SET LOCAL session_replication_role=origin;
UPDATE fixture_0138_plans p SET inventory=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0138_plans p SET document=app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.inventory->'known_source_plan'->>'fact_fingerprint',p.inventory->>'pending_fingerprint',p.assignments)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.expect_0138_failure('55000',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO inconsistent_projection;
RELEASE inconsistent_projection;
SAVEPOINT pending_growth;
SELECT pg_temp.stage_0138('b','person',1);
SELECT pg_temp.expect_0138_failure('23505',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO pending_growth;
RELEASE pending_growth;
SAVEPOINT contact_pending;
SELECT pg_temp.assert_0138(result_code='accepted','mixed-pending contact submit was not accepted')
FROM fixture_0138_context c,fixture_0138_projects b,LATERAL app_data.apply_contact_submit_v3(c.app_user_id,'0138-mixed-submit',1,'contact.submit.v1','0138-device','0138-mixed-contact',0,
  jsonb_build_object('contactId','0138-mixed-contact','workspaceId',c.workspace_id,'projectId',b.project_id,'questionnaireVersionId',b.questionnaire_version_id,
    'reason','0138 mixed pending contact','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) submitted WHERE b.name='b';
SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,b.project_id,gen_random_uuid(),p.generation_id,
  '0138-mixed-contact',1,2,'unknown',false,true)
FROM fixture_0138_context c,fixture_0138_projects b,fixture_0138_pairs p WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0138_plans p SET inventory=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
UPDATE fixture_0138_plans p SET document=app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
  p.inventory->'known_source_plan'->>'fact_fingerprint',p.inventory->>'pending_fingerprint',p.assignments)
FROM fixture_0138_context c,fixture_0138_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.expect_0138_failure('55000',NULL,'SELECT pg_temp.confirm_0138(''person'')');
ROLLBACK TO contact_pending;
RELEASE contact_pending;

CREATE FUNCTION pg_temp.fault_0138() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF TG_ARGV[0]='raise' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='0138 injected write failure'; END IF;
  IF TG_ARGV[0]='suppress' THEN RETURN NULL; END IF;
  RETURN NEW;
END $function$;
DO $faults$
DECLARE relation text; operation text; mode text;
BEGIN
  FOREACH relation IN ARRAY ARRAY['app_data.promotion_target_relationship_revisions','app_private.personal_merge_project_relationship_resolution_requests_v1',
    'app_private.personal_merge_project_relationship_history_applications_v1','app_private.personal_merge_project_relationship_current_choices_v1',
    'app_private.personal_target_merge_end_events_v1','app_private.personal_target_merge_active_members_v1',
    'app_data.promotion_target_project_relationships','app_data.personal_merge_unassigned_project_relationship_facts_v1'] LOOP
    operation:=CASE relation WHEN 'app_data.promotion_target_project_relationships' THEN 'UPDATE'
      WHEN 'app_data.personal_merge_unassigned_project_relationship_facts_v1' THEN 'DELETE'
      WHEN 'app_private.personal_target_merge_active_members_v1' THEN 'DELETE' ELSE 'INSERT' END;
    FOREACH mode IN ARRAY ARRAY['raise','suppress'] LOOP
      EXECUTE format('CREATE TRIGGER fixture_0138_fault BEFORE %s ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.fault_0138(%L)',operation,relation,mode);
      PERFORM pg_temp.expect_0138_failure(CASE mode WHEN 'raise' THEN 'P0001' ELSE '55000' END,NULL,'SELECT pg_temp.confirm_0138(''person'')');
      EXECUTE format('DROP TRIGGER fixture_0138_fault ON %s',relation);
    END LOOP;
  END LOOP;
END $faults$;
SELECT pg_temp.expect_0138_failure('55000',NULL,format('SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint'))
FROM fixture_0138_context c,fixture_0138_projects b,fixture_0138_plans p WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.expect_0138_failure('42501',NULL,'DELETE FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0138_pending LIMIT 1)');
CREATE TEMP TABLE fixture_0138_results(kind text PRIMARY KEY,confirmed_at timestamptz);
INSERT INTO fixture_0138_results SELECT kind,pg_temp.confirm_0138(kind) FROM fixture_0138_plans ORDER BY kind;
SET CONSTRAINTS ALL IMMEDIATE;
DO $success$
DECLARE p record; slot record; base record; applied record; final_revision record; payload record; expected_number integer; choice jsonb; selected record;
BEGIN
  PERFORM pg_temp.assert_0138(NOT EXISTS(SELECT 1 FROM fixture_0138_before_revisions old LEFT JOIN app_data.promotion_target_relationship_revisions live
    USING(promotion_target_id,project_id,revision_number) WHERE to_jsonb(old) IS DISTINCT FROM to_jsonb(live)),'confirmation changed an old ordinary revision');
  PERFORM pg_temp.assert_0138(NOT EXISTS(SELECT 1 FROM fixture_0138_before_relations old JOIN app_data.promotion_target_project_relationships live
    USING(promotion_target_id,project_id) WHERE old.merge_generation_id IS DISTINCT FROM live.merge_generation_id),'confirmation rewrote parent generation binding');
  FOR p IN SELECT plans.*,results.confirmed_at,request.confirmed_at_utc AS revision_at FROM fixture_0138_plans plans
    JOIN fixture_0138_results results USING(kind) JOIN app_private.personal_merge_project_relationship_resolution_requests_v1 request
      ON request.request_id=plans.request_id AND request.actor_app_user_id=(SELECT app_user_id FROM fixture_0138_context) LOOP
    PERFORM pg_temp.assert_0138(app_private.personal_merge_project_relationship_resolution_proof_v1((SELECT app_user_id FROM fixture_0138_context),p.request_id)
      AND EXISTS(SELECT 1 FROM app_private.personal_target_merge_end_events_v1 receipt WHERE receipt.request_id=p.request_id AND receipt.generation_id=p.generation_id
        AND receipt.ended_at_utc=p.confirmed_at AND receipt.reason='known_source_split')
      AND NOT EXISTS(SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=p.generation_id),
      'complete metadata proof or exact ended receipt is missing');
    FOR slot IN SELECT value->>'project_id' AS project_id,value->>'source_target_id' AS source_target_id
      FROM jsonb_array_elements(p.document->'source_slots') LOOP
      SELECT revision.*,parent.merge_generation_id AS parent_merge_generation_id INTO STRICT base FROM fixture_0138_before_revisions revision JOIN fixture_0138_before_relations parent
        USING(promotion_target_id,project_id) WHERE parent.promotion_target_id=slot.source_target_id::uuid AND parent.project_id=slot.project_id::uuid
          AND revision.revision_number=parent.current_revision;
      expected_number:=base.revision_number;
      FOR payload IN SELECT facts.* FROM fixture_0138_payloads facts
        WHERE facts.project_id=slot.project_id::uuid AND facts.source_target_id=slot.source_target_id::uuid ORDER BY staged_at_utc,pending_fact_id LOOP
        expected_number:=expected_number+1;
        SELECT * INTO STRICT applied FROM app_data.promotion_target_relationship_revisions
          WHERE promotion_target_id=payload.source_target_id AND project_id=payload.project_id AND revision_number=expected_number;
        PERFORM pg_temp.assert_0138(applied.old_stage=base.new_stage AND applied.old_lifecycle_status=base.new_lifecycle_status
          AND applied.new_stage=payload.new_stage AND applied.new_lifecycle_status=payload.new_lifecycle_status
          AND applied.follow_up_note IS NOT DISTINCT FROM payload.follow_up_note AND applied.reason_code=payload.reason_code
          AND applied.reason_detail IS NOT DISTINCT FROM payload.reason_detail AND applied.changed_at=payload.staged_at_utc
          AND applied.changed_fields=ARRAY['pending_source_assignment']::text[] AND applied.merge_generation_id=p.generation_id,
          'historical application changed raw payload, original base, event time, or metrics marker');
        PERFORM pg_temp.assert_0138(EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_history_applications_v1 ledger
          WHERE ledger.pending_fact_id=payload.pending_fact_id AND ledger.request_id=p.request_id AND ledger.source_target_id=payload.source_target_id
            AND ledger.project_id=payload.project_id AND ledger.original_revision_number=base.revision_number AND ledger.applied_revision_number=expected_number),
          'pending history ID-only receipt is missing');
      END LOOP;
      SELECT value INTO STRICT choice FROM jsonb_array_elements(p.choices) value
        WHERE value->>'project_id'=slot.project_id AND value->>'source_target_id'=slot.source_target_id;
      IF choice->>'candidate_kind'='pending' THEN
        SELECT new_stage,new_lifecycle_status,follow_up_note INTO STRICT selected FROM fixture_0138_payloads WHERE pending_fact_id=(choice->>'pending_fact_id')::uuid;
      ELSE selected:=base;
      END IF;
      expected_number:=expected_number+1;
      SELECT * INTO STRICT final_revision FROM app_data.promotion_target_relationship_revisions
        WHERE promotion_target_id=slot.source_target_id::uuid AND project_id=slot.project_id::uuid AND revision_number=expected_number;
      PERFORM pg_temp.assert_0138(final_revision.old_stage=base.new_stage AND final_revision.old_lifecycle_status=base.new_lifecycle_status
        AND final_revision.new_stage=selected.new_stage AND final_revision.new_lifecycle_status=selected.new_lifecycle_status
        AND final_revision.follow_up_note IS NOT DISTINCT FROM selected.follow_up_note AND final_revision.changed_at=p.revision_at
        AND p.revision_at<=p.confirmed_at
        AND final_revision.reason_code='correction' AND final_revision.reason_detail='Confirmed pending project relationship current selection'
        AND final_revision.merge_generation_id=p.generation_id
        AND final_revision.changed_fields=ARRAY['pending_current_selection']::text[]
          ||CASE WHEN base.new_stage<>selected.new_stage THEN ARRAY['stage'] ELSE ARRAY[]::text[] END
          ||CASE WHEN base.new_lifecycle_status<>selected.new_lifecycle_status THEN ARRAY['lifecycle_status'] ELSE ARRAY[]::text[] END
          ||CASE WHEN base.follow_up_note IS DISTINCT FROM selected.follow_up_note THEN ARRAY['follow_up_note'] ELSE ARRAY[]::text[] END,
        'explicit current selection lost raw values or emitted false stage metrics');
      PERFORM pg_temp.assert_0138(EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships parent
        WHERE parent.promotion_target_id=slot.source_target_id::uuid AND parent.project_id=slot.project_id::uuid
          AND parent.current_revision=expected_number AND parent.current_stage=selected.new_stage AND parent.current_lifecycle_status=selected.new_lifecycle_status
          AND parent.current_follow_up_note IS NOT DISTINCT FROM selected.follow_up_note)
        AND EXISTS(SELECT 1 FROM app_private.personal_merge_project_relationship_current_choices_v1 ledger
          WHERE ledger.request_id=p.request_id AND ledger.source_target_id=slot.source_target_id::uuid AND ledger.project_id=slot.project_id::uuid
            AND ledger.original_revision_number=base.revision_number AND ledger.final_revision_number=expected_number
            AND ledger.selected_pending_fact_id IS NOT DISTINCT FROM (choice->>'pending_fact_id')::uuid
            AND ledger.original_merge_generation_id IS NOT DISTINCT FROM base.parent_merge_generation_id),
        'final projection or explicit current choice ledger differs');
    END LOOP;
  END LOOP;
  PERFORM pg_temp.assert_0138(NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1
    WHERE pending_fact_id IN(SELECT pending_fact_id FROM fixture_0138_pending))
    AND NOT EXISTS(SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_purges_v1
      WHERE pending_fact_id IN(SELECT pending_fact_id FROM fixture_0138_pending)),'confirmation left payloads or mislabelled consumption as retention purge');
  PERFORM pg_temp.assert_0138((SELECT count(*) FROM app_private.personal_merge_project_relationship_history_applications_v1
    WHERE pending_fact_id IN(SELECT pending_fact_id FROM fixture_0138_pending))=(SELECT count(*) FROM fixture_0138_pending),'same-value or unselected history was lost');
END $success$;
DO $unrelated$
DECLARE before_state jsonb:=(SELECT document FROM fixture_0138_before_state); after_state jsonb:=pg_temp.state_0138(); key text;
BEGIN
  FOR key IN SELECT jsonb_object_keys(before_state) LOOP
    IF key=ANY(ARRAY['app_data.promotion_target_project_relationships','app_data.promotion_target_relationship_revisions',
      'app_private.personal_target_merge_active_members_v1','app_private.personal_target_merge_end_events_v1',
      'app_private.personal_merge_project_relationship_resolution_requests_v1','app_private.personal_merge_project_relationship_history_applications_v1',
      'app_private.personal_merge_project_relationship_current_choices_v1','app_data.personal_merge_unassigned_project_relationship_facts_v1',
      'app_private.personal_target_merge_generation_fence_v1']) THEN CONTINUE; END IF;
    PERFORM pg_temp.assert_0138(before_state->key=after_state->key,'confirmation changed unrelated table '||key);
  END LOOP;
  PERFORM pg_temp.assert_0138(NOT EXISTS(SELECT 1 FROM fixture_0138_before_relations old
    JOIN app_data.promotion_target_project_relationships live USING(promotion_target_id,project_id)
    WHERE NOT EXISTS(SELECT 1 FROM fixture_0138_pending pending WHERE pending.source_target_id=old.promotion_target_id AND pending.project_id=old.project_id)
      AND to_jsonb(old) IS DISTINCT FROM to_jsonb(live)),'confirmation changed an unaffected source/project');
END $unrelated$;
DO $replay$
DECLARE p record; original_state jsonb:=pg_temp.state_0138(); mappings jsonb; choices jsonb;
BEGIN
  FOR p IN SELECT plans.*,results.confirmed_at FROM fixture_0138_plans plans JOIN fixture_0138_results results USING(kind) LOOP
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ordinal DESC)
      INTO mappings FROM jsonb_array_elements(p.assignments) WITH ORDINALITY entries(value,ordinal);
    SELECT jsonb_agg(jsonb_build_object('project_id',upper(value->>'project_id'),'source_target_id',upper(value->>'source_target_id'),
      'candidate_kind',value->>'candidate_kind','pending_fact_id',CASE WHEN value->>'pending_fact_id' IS NULL THEN 'null'::jsonb ELSE to_jsonb(upper(value->>'pending_fact_id')) END) ORDER BY ordinal DESC)
      INTO choices FROM jsonb_array_elements(p.choices) WITH ORDINALITY entries(value,ordinal);
    PERFORM pg_temp.assert_0138(pg_temp.confirm_0138(p.kind,mappings,choices)=p.confirmed_at,'canonical exact replay returned a new receipt');
  END LOOP;
  PERFORM pg_temp.assert_0138(original_state=pg_temp.state_0138(),'exact replay wrote history, receipt, context, or fence');
END $replay$;
SELECT pg_temp.expect_0138_failure('23505',NULL,format('SELECT pg_temp.confirm_0138(''person'',%L::jsonb)',jsonb_build_array((assignments->0)||
  jsonb_build_object('source_target_id',(SELECT CASE WHEN first_target::text=assignments->0->>'source_target_id' THEN second_target ELSE first_target END
    FROM fixture_0138_pairs WHERE kind='person')))||(assignments-0))) FROM fixture_0138_plans WHERE kind='person';
SELECT pg_temp.expect_0138_failure('23505',NULL,format('SELECT pg_temp.confirm_0138(''person'',NULL,%L::jsonb)',jsonb_build_array((choices->0)||
  jsonb_build_object('candidate_kind','pending','pending_fact_id',gen_random_uuid()))||(choices-0))) FROM fixture_0138_plans WHERE kind='person';
DO $immutable$
DECLARE relation text;
BEGIN
  FOREACH relation IN ARRAY ARRAY['app_private.personal_merge_project_relationship_resolution_requests_v1',
    'app_private.personal_merge_project_relationship_history_applications_v1','app_private.personal_merge_project_relationship_current_choices_v1'] LOOP
    PERFORM pg_temp.expect_0138_failure('55000',NULL,format('DELETE FROM %s',relation));
  END LOOP;
END $immutable$;
SELECT pg_temp.assert_0138(NOT has_function_privilege('public',
  'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('tongxingzhe_runtime',
  'app_private.confirm_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE'),'confirmation is exposed to PUBLIC or runtime');
ROLLBACK;

