-- Synthetic metadata-only resolution plans. Every source and pending event rolls back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE FUNCTION pg_temp.assert_0137(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0137 %',label; END IF;
END $function$;
CREATE FUNCTION pg_temp.state_0137() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; result jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT schemaname,tablename FROM pg_catalog.pg_tables WHERE schemaname IN('app_data','app_private') ORDER BY schemaname,tablename LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t',relation.schemaname,relation.tablename) INTO rows;
    result := result||jsonb_build_object(relation.schemaname||'.'||relation.tablename,rows);
  END LOOP;
  RETURN result;
END $function$;
CREATE FUNCTION pg_temp.expect_0137_failure(expected_state text,expected_message text,statement text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.state_0137(); actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT; END;
  IF actual_state IS DISTINCT FROM expected_state OR(expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0137 expected % / %, got % / %',expected_state,expected_message,actual_state,actual_message;
  END IF;
  PERFORM pg_temp.assert_0137(before_state=pg_temp.state_0137(),'rejected planner changed business data, context, audit, or fence');
END $function$;
CREATE TEMP TABLE fixture_0137_context AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0137.example.test','owner');
CREATE TEMP TABLE fixture_0137_other AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0137.example.test','other');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0137.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0137_projects AS SELECT 'a'::text AS name,c.* FROM fixture_0137_context c;
INSERT INTO fixture_0137_projects SELECT 'b',c.* FROM app_data.create_personal_project_context('https://synthetic-0137.example.test','owner','0137 project B') c;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0137.example.test','owner',(SELECT project_id FROM fixture_0137_context));
CREATE TEMP TABLE fixture_0137_pairs(kind text,target_type text,first_target uuid,second_target uuid,generation_id uuid);
DO $seed$
DECLARE c record; kind text; target_type text; first_target uuid; second_target uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0137_context;
  FOREACH kind IN ARRAY ARRAY['person','institution','empty'] LOOP
    target_type := CASE WHEN kind='empty' THEN 'person' ELSE kind END;
    SELECT (target->>'target_id')::uuid INTO STRICT first_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      target_type,'0137 first '||kind,'+1 312 555 0137',NULL,'0137-'||kind||'-first');
    SELECT (target->>'target_id')::uuid INTO STRICT second_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      target_type,'0137 second '||kind,'+1 312 555 0137',NULL,'0137-'||kind||'-second');
    INSERT INTO fixture_0137_pairs VALUES(kind,target_type,first_target,second_target,NULL);
  END LOOP;
END $seed$;
CREATE FUNCTION pg_temp.enter_project_0137(project_name text,kind text,source_number integer) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; pair record; source uuid; contact text; code text;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0137_projects WHERE name=$1;
  SELECT * INTO STRICT pair FROM fixture_0137_pairs p WHERE p.kind=$2;
  source := CASE source_number WHEN 1 THEN pair.first_target ELSE pair.second_target END;
  contact := '0137-entry-'||project_name||'-'||kind||'-'||source_number;
  PERFORM app_data.select_personal_project_context('https://synthetic-0137.example.test','owner',c.project_id);
  SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,contact||'-submit',1,'contact.submit.v1','0137-device',contact,0,
    jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
      'reason','0137 real project entry','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
      'targetLinks',jsonb_build_array(jsonb_build_object('targetId',source,'targetType',pair.target_type,'responseLevel',NULL,
        'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
  PERFORM pg_temp.assert_0137(code='accepted','ordinary contact revision did not create project relationship');
END $function$;
SELECT pg_temp.enter_project_0137('a','person',1);
SELECT pg_temp.enter_project_0137('a','person',2);
SELECT pg_temp.enter_project_0137('a','institution',1);
SELECT pg_temp.enter_project_0137('a','empty',1);
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0137.example.test','owner',(SELECT project_id FROM fixture_0137_context));
DO $activate$
DECLARE c record; pair record; preview uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0137_context;
  FOR pair IN TABLE fixture_0137_pairs LOOP
    SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0137.example.test','owner',c.project_id,pair.first_target,pair.second_target);
    UPDATE fixture_0137_pairs SET generation_id=app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,
      pair.first_target,pair.second_target,pair.first_target,pair.second_target) WHERE kind=pair.kind;
  END LOOP;
END $activate$;
SELECT pg_temp.enter_project_0137('b','person',2);
CREATE TEMP TABLE fixture_0137_pending(kind text,project_id uuid,pending_fact_id uuid,source_target_id uuid);
CREATE FUNCTION pg_temp.stage_0137(project_name text,kind text,source_number integer) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; pair record; pending uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0137_projects WHERE name=$1;
  SELECT * INTO STRICT pair FROM fixture_0137_pairs p WHERE p.kind=$2;
  PERFORM app_data.select_personal_project_context('https://synthetic-0137.example.test','owner',c.project_id);
  SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
    gen_random_uuid(),pair.generation_id,2,'paused','0137 private note private@example.test','progress_update','0137 private detail');
  INSERT INTO fixture_0137_pending VALUES(kind,c.project_id,pending,CASE source_number WHEN 1 THEN pair.first_target ELSE pair.second_target END);
END $function$;
SELECT pg_temp.stage_0137('a','person',1);
SELECT pg_temp.stage_0137('a','person',1);
SELECT pg_temp.stage_0137('a','institution',1);
SELECT pg_temp.stage_0137('b','person',1);
SELECT pg_temp.stage_0137('b','person',2);
SELECT pg_temp.stage_0137('b','institution',2);
CREATE TEMP TABLE fixture_0137_plans AS SELECT pair.kind,pair.generation_id,
  app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS original,
  coalesce((SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending.pending_fact_id,'source_target_id',pending.source_target_id) ORDER BY pending.pending_fact_id)
    FROM fixture_0137_pending pending WHERE pending.kind=pair.kind),'[]'::jsonb) AS assignments
FROM fixture_0137_pairs pair,fixture_0137_context c,fixture_0137_projects b WHERE b.name='b';
CREATE FUNCTION pg_temp.read_0137(kind text,mapping jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,
    (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id=c.app_user_id),p.generation_id,
    p.original->'known_source_plan'->>'fact_fingerprint',p.original->>'pending_fingerprint',coalesce($2,p.assignments))
  FROM fixture_0137_context c,fixture_0137_plans p WHERE p.kind=$1
$function$;
CREATE FUNCTION pg_temp.assert_shape_0137(document jsonb,kind text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE slot jsonb; expected_ids jsonb; current_pointer jsonb; canonical_assignments jsonb;
BEGIN
  PERFORM pg_temp.assert_0137(ARRAY(SELECT jsonb_object_keys(document) ORDER BY 1)=ARRAY['assignments','conflict_count','contract_id','known_source_plan','pending_fingerprint','resolution_fingerprint','source_slots']
    AND document->>'contract_id'='personal_merge_project_relationship_resolution_plan_v1'
    AND document->>'resolution_fingerprint'=encode(sha256(convert_to((document-'resolution_fingerprint')::text,'UTF8')),'hex')
    AND position('private@example.test' IN document::text)=0 AND position('0137 private detail' IN document::text)=0,'top-level metadata allowlist or SHA-256 differs');
  SELECT coalesce(jsonb_agg(jsonb_build_object('pending_fact_id',pending.pending_fact_id,'source_target_id',pending.source_target_id,
    'project_id',pending.project_id) ORDER BY pending.pending_fact_id),'[]'::jsonb) INTO canonical_assignments FROM fixture_0137_pending pending WHERE pending.kind=$2;
  PERFORM pg_temp.assert_0137(document->'assignments'=canonical_assignments,'canonical mapping omitted derived project or changed pending UUID order');
  PERFORM pg_temp.assert_0137(document->'source_slots'=(SELECT coalesce(jsonb_agg(value ORDER BY (value->>'project_id')::uuid,(value->>'source_target_id')::uuid),'[]'::jsonb)
    FROM jsonb_array_elements(document->'source_slots')),'source slot order differs');
  FOR slot IN SELECT value FROM jsonb_array_elements(document->'source_slots') LOOP
    SELECT coalesce(jsonb_agg(pending.pending_fact_id ORDER BY header.staged_at_utc,pending.pending_fact_id),'[]'::jsonb) INTO expected_ids
    FROM fixture_0137_pending pending JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
    WHERE pending.kind=$2 AND pending.project_id=(slot->>'project_id')::uuid AND pending.source_target_id=(slot->>'source_target_id')::uuid;
    SELECT jsonb_build_object('revision_number',relation.current_revision,'merge_generation_id',revision.merge_generation_id) INTO current_pointer
    FROM app_data.promotion_target_project_relationships relation JOIN app_data.promotion_target_relationship_revisions revision
      ON revision.promotion_target_id=relation.promotion_target_id AND revision.project_id=relation.project_id AND revision.revision_number=relation.current_revision
    WHERE relation.project_id=(slot->>'project_id')::uuid
      AND relation.promotion_target_id=(slot->>'source_target_id')::uuid;
    PERFORM pg_temp.assert_0137(ARRAY(SELECT jsonb_object_keys(slot) ORDER BY 1)=ARRAY['candidate_count','current_relationship','pending_fact_ids','project_id','requires_choice','source_target_id']
      AND jsonb_array_length(expected_ids)>0 AND slot->'pending_fact_ids'=expected_ids
      AND slot->'current_relationship'=coalesce(current_pointer,'null'::jsonb)
      AND (slot->>'candidate_count')::integer=jsonb_array_length(expected_ids)+(current_pointer IS NOT NULL)::integer
      AND (slot->>'requires_choice')::boolean=((slot->>'candidate_count')::integer>1),'slot fields, time order, real current pointer, or candidate count differs');
  END LOOP;
  PERFORM pg_temp.assert_0137(jsonb_array_length(document->'source_slots')=(SELECT count(*) FROM(SELECT DISTINCT project_id,source_target_id FROM fixture_0137_pending WHERE fixture_0137_pending.kind=$2) slots)
    AND (document->>'conflict_count')::integer=(SELECT count(*) FROM jsonb_array_elements(document->'source_slots') candidate WHERE (candidate->>'requires_choice')::boolean),
    'planner omitted affected slots or counted unrelated current relationships');
END $function$;
CREATE TEMP TABLE fixture_0137_initial AS SELECT kind,pg_temp.read_0137(kind) AS document FROM fixture_0137_plans;
DO $baseline$
DECLARE before_state jsonb := pg_temp.state_0137(); p record; reordered jsonb;
BEGIN
  FOR p IN TABLE fixture_0137_plans LOOP
    PERFORM pg_temp.assert_shape_0137(pg_temp.read_0137(p.kind),p.kind);
    SELECT coalesce(jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ordinal DESC),'[]'::jsonb)
      INTO reordered FROM jsonb_array_elements(p.assignments) WITH ORDINALITY entry(value,ordinal);
    PERFORM pg_temp.assert_0137(pg_temp.read_0137(p.kind,reordered)=pg_temp.read_0137(p.kind),'UUID case or input array order changed canonical result');
  END LOOP;
  PERFORM pg_temp.assert_0137((SELECT document->>'conflict_count'='2' AND jsonb_array_length(document->'assignments')=4 FROM fixture_0137_initial WHERE kind='person')
    AND (SELECT document->>'conflict_count'='1' FROM fixture_0137_initial WHERE kind='institution')
    AND (SELECT document->'source_slots'='[]'::jsonb AND document->'assignments'='[]'::jsonb AND document->>'conflict_count'='0' FROM fixture_0137_initial WHERE kind='empty')
    AND before_state=pg_temp.state_0137(),'equal-value events were deduplicated, empty plan changed, or planner wrote persistent state');
END $baseline$;
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only=on;
DO $readonly$
DECLARE before_state jsonb := pg_temp.state_0137();
BEGIN
  IF current_setting('transaction_read_only')<>'on' THEN RAISE EXCEPTION '0137 READ ONLY was not enabled'; END IF;
  PERFORM pg_temp.assert_shape_0137(pg_temp.read_0137(kind),kind) FROM fixture_0137_plans;
  PERFORM pg_temp.assert_0137(before_state=pg_temp.state_0137(),'READ ONLY planner changed facts or fence');
END $readonly$;
ROLLBACK TO readonly_scope;
RELEASE SAVEPOINT readonly_scope;
SAVEPOINT payload_hash_probe;
SET LOCAL session_replication_role=replica;
UPDATE app_data.personal_merge_unassigned_project_relationship_facts_v1 SET new_stage=4,new_lifecycle_status='ended',follow_up_note='0137 changed PII',reason_code='other',reason_detail='0137 changed business reason';
SET LOCAL session_replication_role=origin;
SELECT pg_temp.assert_0137(document=pg_temp.read_0137(kind),'planner returned or hashed pending business values') FROM fixture_0137_initial;
ROLLBACK TO payload_hash_probe;
RELEASE SAVEPOINT payload_hash_probe;

SELECT pg_temp.expect_0137_failure('22023','invalid pending project relationship resolution plan request',format('SELECT pg_temp.read_0137(''person'',%L::jsonb)',value)) FROM(VALUES('null'),('{}'),('4')) cases(value);
SELECT pg_temp.expect_0137_failure('22023','invalid pending project relationship resolution assignment',format('SELECT pg_temp.read_0137(''person'',%L::jsonb)',value)) FROM(VALUES('[null]'),('[4]'),('["text"]')) cases(value);
SELECT pg_temp.expect_0137_failure('22023','invalid pending project relationship resolution assignment keys or UUIDs',format('SELECT pg_temp.read_0137(''person'',%L::jsonb)',value))
FROM fixture_0137_plans p,LATERAL(VALUES
  (jsonb_build_array((p.assignments->0)-'source_target_id')),(jsonb_build_array((p.assignments->0)||jsonb_build_object('project_id',gen_random_uuid()))),
  (jsonb_build_array((p.assignments->0)||jsonb_build_object('pending_fact_id',4))),(jsonb_build_array((p.assignments->0)||jsonb_build_object('source_target_id','bad'))),
  (jsonb_build_array((p.assignments->0)||jsonb_build_object('source_target_id',replace(p.assignments->0->>'source_target_id','-',''))))
) cases(value) WHERE p.kind='person';
SELECT pg_temp.expect_0137_failure('22023','duplicate pending project relationship resolution assignment',format('SELECT pg_temp.read_0137(''person'',%L::jsonb)',assignments||jsonb_build_array(assignments->0))) FROM fixture_0137_plans WHERE kind='person';
SELECT pg_temp.expect_0137_failure('23505','pending project relationship resolution inventory or source assignment changed',format('SELECT pg_temp.read_0137(''person'',%L::jsonb)',value))
FROM fixture_0137_plans p,LATERAL(VALUES('[]'::jsonb),(jsonb_build_array(p.assignments->0)),
  (p.assignments||jsonb_build_array(jsonb_build_object('pending_fact_id',gen_random_uuid(),'source_target_id',p.assignments->0->>'source_target_id'))),
  (jsonb_build_array((p.assignments->0)||jsonb_build_object('source_target_id',(SELECT first_target FROM fixture_0137_pairs WHERE kind='institution')))||(p.assignments-0)),
  (p.assignments||(SELECT assignments FROM fixture_0137_plans WHERE kind='institution'))
) cases(value) WHERE p.kind='person';
SELECT pg_temp.expect_0137_failure(expected_state,NULL,format('SELECT app_private.plan_personal_merge_project_relationship_resolutions_v1(%L,%L,%L,%L,%L,%L,%L::jsonb)',
  CASE WHEN field='actor_null' THEN NULL WHEN field='other_actor' THEN other.app_user_id ELSE c.app_user_id END,
  CASE WHEN field='workspace_null' THEN NULL WHEN field='other_workspace' THEN other.workspace_id ELSE c.workspace_id END,
  CASE WHEN field='project_null' THEN NULL WHEN field='inactive_context' THEN c.project_id ELSE b.project_id END,
  CASE WHEN field='generation_null' THEN NULL ELSE p.generation_id END,
  CASE WHEN field='known_null' THEN NULL WHEN field='known_bad' THEN 'bad' WHEN field='known_stale' THEN repeat('0',64) ELSE p.original->'known_source_plan'->>'fact_fingerprint' END,
  CASE WHEN field='pending_null' THEN NULL WHEN field='pending_bad' THEN 'bad' WHEN field='pending_stale' THEN repeat('0',64) ELSE p.original->>'pending_fingerprint' END,
  CASE WHEN field='assignments_null' THEN NULL ELSE p.assignments END))
FROM fixture_0137_context c,fixture_0137_other other,fixture_0137_projects b,fixture_0137_plans p,
  (VALUES('actor_null','22023'),('workspace_null','22023'),('project_null','22023'),('generation_null','22023'),('known_null','22023'),('known_bad','22023'),
    ('pending_null','22023'),('pending_bad','22023'),('assignments_null','22023'),('known_stale','23505'),('pending_stale','23505'),
    ('other_actor','42501'),('other_workspace','42501'),('inactive_context','42501')) cases(field,expected_state) WHERE b.name='b' AND p.kind='person';

SELECT pg_temp.expect_0137_failure('55000','pending project relationship current revision or context is inconsistent',$statement$
DO $corrupt$ BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_data.promotion_target_project_relationships SET current_revision=999 WHERE promotion_target_id=(SELECT first_target FROM fixture_0137_pairs WHERE kind='person')
    AND project_id=(SELECT project_id FROM fixture_0137_projects WHERE name='a');
  SET LOCAL session_replication_role=origin;
  UPDATE fixture_0137_plans p SET original=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
    FROM fixture_0137_context c,fixture_0137_projects b WHERE b.name='b' AND p.kind='person';
  PERFORM pg_temp.read_0137('person');
END $corrupt$ $statement$);
SELECT pg_temp.expect_0137_failure('55000','pending project relationship current revision or context is inconsistent',$statement$
DO $corrupt$ BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_data.promotion_target_relationship_revisions SET merge_generation_id=(SELECT generation_id FROM fixture_0137_pairs WHERE kind='institution')
    WHERE promotion_target_id=(SELECT first_target FROM fixture_0137_pairs WHERE kind='person') AND project_id=(SELECT project_id FROM fixture_0137_projects WHERE name='a')
      AND revision_number=(SELECT current_revision FROM app_data.promotion_target_project_relationships WHERE promotion_target_id=(SELECT first_target FROM fixture_0137_pairs WHERE kind='person')
        AND project_id=(SELECT project_id FROM fixture_0137_projects WHERE name='a'));
  SET LOCAL session_replication_role=origin;
  UPDATE fixture_0137_plans p SET original=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
    FROM fixture_0137_context c,fixture_0137_projects b WHERE b.name='b' AND p.kind='person';
  PERFORM pg_temp.read_0137('person');
END $corrupt$ $statement$);

SAVEPOINT real_source_changes;
SELECT result FROM fixture_0137_context c,fixture_0137_projects b,fixture_0137_pairs pair,
  LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,b.project_id,pair.second_target,1,1,'active',
    '0137 real changed note','progress_update',NULL,'0137-real-relationship-revision',NULL) updated WHERE b.name='b' AND pair.kind='person';
SELECT pg_temp.assert_0137(EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships WHERE promotion_target_id=(SELECT second_target FROM fixture_0137_pairs WHERE kind='person')
  AND project_id=(SELECT project_id FROM fixture_0137_projects WHERE name='b') AND current_revision=2 AND current_stage=1),'ordinary writer did not advance a real current revision');
SELECT pg_temp.expect_0137_failure('23505','pending project relationship resolution inventory or source assignment changed','SELECT pg_temp.read_0137(''person'')');
UPDATE fixture_0137_plans p SET original=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
  FROM fixture_0137_context c,fixture_0137_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.assert_shape_0137(pg_temp.read_0137('person'),'person');
SELECT pg_temp.assert_0137(pg_temp.read_0137('person')->>'resolution_fingerprint'<>(SELECT document->>'resolution_fingerprint' FROM fixture_0137_initial WHERE kind='person')
  AND pg_temp.read_0137('person')->>'pending_fingerprint'=(SELECT document->>'pending_fingerprint' FROM fixture_0137_initial WHERE kind='person'), 'real revision changed the wrong metadata fingerprint');
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0137.example.test','owner',(SELECT project_id FROM fixture_0137_projects WHERE name='a'));
SELECT result FROM fixture_0137_context c,fixture_0137_projects a,fixture_0137_pairs pair,
  LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,a.project_id,pair.first_target,1,1,'active',
    '0137 revised preactivation relationship','progress_update',NULL,'0137-real-preactivation-relationship-revision',NULL) updated WHERE a.name='a' AND pair.kind='person';
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0137.example.test','owner',(SELECT project_id FROM fixture_0137_projects WHERE name='b'));
SELECT relation.current_revision,relation.merge_generation_id AS parent_merge_generation_id,revision.merge_generation_id AS current_revision_merge_generation_id,pair.generation_id
FROM app_data.promotion_target_project_relationships relation JOIN app_data.promotion_target_relationship_revisions revision
  ON revision.promotion_target_id=relation.promotion_target_id AND revision.project_id=relation.project_id AND revision.revision_number=relation.current_revision
JOIN fixture_0137_pairs pair ON pair.first_target=relation.promotion_target_id
WHERE pair.kind='person' AND relation.project_id=(SELECT project_id FROM fixture_0137_projects WHERE name='a');
SELECT pg_temp.assert_0137(EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships relation
  JOIN app_data.promotion_target_relationship_revisions revision ON revision.promotion_target_id=relation.promotion_target_id
    AND revision.project_id=relation.project_id AND revision.revision_number=relation.current_revision
  JOIN fixture_0137_pairs pair ON pair.first_target=relation.promotion_target_id
  WHERE pair.kind='person' AND relation.project_id=(SELECT project_id FROM fixture_0137_projects WHERE name='a')
    AND relation.current_revision=2 AND relation.merge_generation_id IS NULL AND revision.merge_generation_id=pair.generation_id),
  'ordinary revision did not retain the preactivation parent and bind the real new head');
UPDATE fixture_0137_plans p SET original=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
  FROM fixture_0137_context c,fixture_0137_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.assert_shape_0137(pg_temp.read_0137('person'),'person');
SELECT pg_temp.stage_0137('b','person',1);
SELECT pg_temp.expect_0137_failure('23505','pending project relationship resolution inventory or source assignment changed','SELECT pg_temp.read_0137(''person'')');
UPDATE fixture_0137_plans p SET original=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id),
  assignments=(SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending.pending_fact_id,'source_target_id',pending.source_target_id) ORDER BY pending.pending_fact_id)
    FROM fixture_0137_pending pending WHERE pending.kind=p.kind) FROM fixture_0137_context c,fixture_0137_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.assert_shape_0137(pg_temp.read_0137('person'),'person');
ROLLBACK TO real_source_changes;
RELEASE SAVEPOINT real_source_changes;
SELECT pg_temp.assert_0137(NOT has_function_privilege('tongxingzhe_runtime','app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)','EXECUTE')
  AND NOT has_function_privilege('public','app_private.plan_personal_merge_project_relationship_resolutions_v1(uuid,uuid,uuid,uuid,text,text,jsonb)','EXECUTE'),'planner is executable by runtime or PUBLIC');
ROLLBACK;
