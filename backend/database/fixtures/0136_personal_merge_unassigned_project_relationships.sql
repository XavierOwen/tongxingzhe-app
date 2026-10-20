-- Synthetic stage-only project relationship events. All rows and triggers roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0136_existing_payloads AS
SELECT * FROM app_data.personal_merge_unassigned_project_relationship_facts_v1;
CREATE FUNCTION pg_temp.assert_0136(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0136 %',label; END IF;
END $function$;
CREATE FUNCTION pg_temp.state_0136(exclude_stage_tables boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; result jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT schemaname,tablename FROM pg_catalog.pg_tables WHERE schemaname IN('app_data','app_private')
    AND NOT(exclude_stage_tables AND tablename IN('personal_merge_unassigned_project_relationship_requests_v1',
      'personal_merge_unassigned_project_relationship_facts_v1','personal_merge_unassigned_project_relationship_purges_v1',
      'personal_target_merge_generation_fence_v1')) ORDER BY schemaname,tablename LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t',relation.schemaname,relation.tablename) INTO rows;
    result := result||jsonb_build_object(relation.schemaname||'.'||relation.tablename,rows);
  END LOOP;
  RETURN result;
END $function$;
CREATE FUNCTION pg_temp.expect_0136_failure(expected_state text,expected_message text,statement text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.state_0136(); actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT; END;
  IF actual_state IS DISTINCT FROM expected_state OR(expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0136 expected % / %, got % / %',expected_state,expected_message,actual_state,actual_message;
  END IF;
  PERFORM pg_temp.assert_0136(before_state=pg_temp.state_0136(),'rejected operation changed old facts, pending values, or fence');
END $function$;
CREATE TEMP TABLE fixture_0136_context AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0136.example.test','owner');
CREATE TEMP TABLE fixture_0136_other AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0136.example.test','other');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0136.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0136_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid);
DO $seed$
DECLARE c record; kind text; first_target uuid; second_target uuid; preview uuid; generation uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0136_context;
  FOREACH kind IN ARRAY ARRAY['person','institution'] LOOP
    SELECT (target->>'target_id')::uuid INTO STRICT first_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      kind,'0136 first '||kind,'+1 312 555 0136',NULL,'0136-'||kind||'-first');
    SELECT (target->>'target_id')::uuid INTO STRICT second_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      kind,'0136 second '||kind,'+1 312 555 0136',NULL,'0136-'||kind||'-second');
    PERFORM pg_temp.assert_0136((SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(c.app_user_id,'0136-known-'||kind||'-submit',
      1,'contact.submit.v1','0136-device','0136-known-'||kind,0,jsonb_build_object('contactId','0136-known-'||kind,
        'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
        'reason','0136 project entry','occurredAtUtc','2024-01-01T00:00:00Z','occurredTimeZone','UTC','channel','video_call',
        'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
        'targetLinks',jsonb_build_array(jsonb_build_object('targetId',first_target,'targetType',kind,'responseLevel',NULL,
          'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))))), 'ordinary project entry seed was rejected');
    PERFORM app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,first_target,1,1,'active',
      '0136 existing known-source note','progress_update',NULL,'0136-known-'||kind,NULL);
    PERFORM pg_temp.assert_0136(EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id=first_target AND project_id=c.project_id AND current_stage=1 AND current_revision=2),'ordinary relationship writer seed was rejected');
    SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0136.example.test','owner',c.project_id,first_target,second_target);
    generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,first_target,second_target,first_target,second_target);
    INSERT INTO fixture_0136_pairs VALUES(kind,first_target,second_target,generation);
  END LOOP;
END $seed$;
CREATE FUNCTION pg_temp.stage_0136(kind text,request uuid,stage integer DEFAULT 2,lifecycle text DEFAULT 'paused',
  note text DEFAULT '0136 PII note private@example.test',reason text DEFAULT 'progress_update',detail text DEFAULT '0136 private reason')
RETURNS TABLE(unassigned_project_relationship_contract_id text,pending_fact_id uuid,staged_at_utc timestamptz)
LANGUAGE sql AS $function$
  SELECT result.* FROM fixture_0136_context c,fixture_0136_pairs pair,
    LATERAL app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,$2,pair.generation_id,$3,$4,$5,$6,$7) result
  WHERE pair.kind=$1
$function$;
CREATE FUNCTION pg_temp.read_0136(kind text) RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id)
  FROM fixture_0136_context c,fixture_0136_pairs p WHERE p.kind=$1
$function$;
CREATE FUNCTION pg_temp.expire_0136(kind text) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.expire_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id)
  FROM fixture_0136_context c,fixture_0136_pairs p WHERE p.kind=$1
$function$;
CREATE TEMP TABLE fixture_0136_before AS SELECT pg_temp.state_0136(true) AS state;
CREATE TEMP TABLE fixture_0136_first AS SELECT * FROM pg_temp.stage_0136('person','00000000-0136-1000-8000-000000000001');
CREATE TEMP TABLE fixture_0136_replay AS SELECT * FROM pg_temp.stage_0136('person','00000000-0136-1000-8000-000000000001');
CREATE TEMP TABLE fixture_0136_second AS SELECT * FROM pg_temp.stage_0136('person','00000000-0136-1000-8000-000000000002');
CREATE TEMP TABLE fixture_0136_institution AS SELECT * FROM pg_temp.stage_0136('institution','00000000-0136-1000-8000-000000000003',4,'ended',NULL,'target_request',NULL);
SELECT pg_temp.assert_0136((SELECT count(*)=1 AND bool_and(unassigned_project_relationship_contract_id='personal-merge-unassigned-project-relationship:v1'
    AND pending_fact_id IS NOT NULL AND isfinite(staged_at_utc) AND staged_at_utc<=clock_timestamp()) FROM fixture_0136_first)
  AND NOT EXISTS((TABLE fixture_0136_first EXCEPT TABLE fixture_0136_replay) UNION ALL(TABLE fixture_0136_replay EXCEPT TABLE fixture_0136_first))
  AND (SELECT first.pending_fact_id<>second.pending_fact_id FROM fixture_0136_first first,fixture_0136_second second)
  AND (SELECT count(*)=2 FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 WHERE generation_id=(SELECT generation_id FROM fixture_0136_pairs WHERE kind='person'))
  AND (SELECT state=pg_temp.state_0136(true) FROM fixture_0136_before),'receipt, exact replay, distinct equal-valued events, or ordinary facts drifted');
SELECT pg_temp.assert_0136((SELECT array_agg(key ORDER BY key)=ARRAY['actor_app_user_id','generation_id','pending_fact_id','project_id','request_id','staged_at_utc','target_type','workspace_id']
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 header,LATERAL jsonb_object_keys(to_jsonb(header)) key
    WHERE header.pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_first))
  AND (SELECT new_stage=2 AND new_lifecycle_status='paused' AND follow_up_note='0136 PII note private@example.test'
    AND reason_code='progress_update' AND reason_detail='0136 private reason' FROM app_data.personal_merge_unassigned_project_relationship_facts_v1
    WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_first)), 'header copied values or typed payload changed');
CREATE TEMP TABLE fixture_0136_plan AS SELECT pg_temp.read_0136('person') AS document;
SELECT pg_temp.assert_0136((SELECT document->>'pending_count'='2'
  AND ARRAY(SELECT jsonb_object_keys(document) ORDER BY 1)=ARRAY['known_source_plan','pending_count','pending_fingerprint','pending_project_relationships']
  AND document->>'pending_fingerprint'=encode(sha256(convert_to((document->'pending_project_relationships')::text,'UTF8')),'hex')
  AND position('private@example.test' IN document::text)=0
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(document->'pending_project_relationships') item
    WHERE ARRAY(SELECT jsonb_object_keys(item) ORDER BY 1)<>ARRAY['pending_fact_id','project_id','staged_at_utc','target_type']
      OR item->>'staged_at_utc' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$') FROM fixture_0136_plan),
  'reader included payload, omitted metadata, or hashed values');
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only=on;
DO $readonly$
DECLARE before_state jsonb := pg_temp.state_0136(); plan_document jsonb;
BEGIN
  IF current_setting('transaction_read_only')<>'on' THEN RAISE EXCEPTION '0136 READ ONLY is not active'; END IF;
  plan_document := pg_temp.read_0136('person');
  PERFORM pg_temp.assert_0136(plan_document=(SELECT document FROM fixture_0136_plan) AND before_state=pg_temp.state_0136(),'READ ONLY reader wrote facts or changed its plan');
END $readonly$;
ROLLBACK TO readonly_scope;
RELEASE SAVEPOINT readonly_scope;
SAVEPOINT payload_hash_probe;
SET LOCAL session_replication_role=replica;
UPDATE app_data.personal_merge_unassigned_project_relationship_facts_v1 SET new_stage=0,follow_up_note='0136 different PII'
WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_first);
SET LOCAL session_replication_role=origin;
SELECT pg_temp.assert_0136(pg_temp.read_0136('person')=(SELECT document FROM fixture_0136_plan),'metadata fingerprint depends on business values');
ROLLBACK TO payload_hash_probe;

SAVEPOINT raw_text_boundaries;
CREATE TEMP TABLE fixture_0136_raw_boundary AS SELECT * FROM pg_temp.stage_0136('person',gen_random_uuid(),2,'paused',
  repeat(' ',3999)||'x','progress_update',repeat(' ',999)||'x');
SELECT pg_temp.assert_0136((SELECT length(follow_up_note)=4000 AND follow_up_note=repeat(' ',3999)||'x'
  AND length(reason_detail)=1000 AND reason_detail=repeat(' ',999)||'x'
  FROM app_data.personal_merge_unassigned_project_relationship_facts_v1
  WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_raw_boundary)), 'raw text boundaries were trimmed or rejected');
ROLLBACK TO raw_text_boundaries;
RELEASE SAVEPOINT raw_text_boundaries;
SELECT pg_temp.expect_0136_failure('22023','invalid unassigned project relationship request',command) FROM (VALUES
  ($test$SELECT * FROM pg_temp.stage_0136('person',gen_random_uuid(),2,'paused',repeat(' ',4000)||'x')$test$),
  ($test$SELECT * FROM pg_temp.stage_0136('person',gen_random_uuid(),2,'paused',NULL,'progress_update',repeat(' ',1000)||'x')$test$),
  ($test$SELECT * FROM pg_temp.stage_0136('person',gen_random_uuid(),2,'paused',E'\t\n')$test$),
  ($test$SELECT * FROM pg_temp.stage_0136('person',gen_random_uuid(),2,'paused',NULL,'progress_update',E'\t\n')$test$)
) cases(command);

SELECT pg_temp.expect_0136_failure('22023','unassigned project relationship request context changed',
  'SELECT * FROM pg_temp.stage_0136(''institution'',''00000000-0136-1000-8000-000000000001'')');
SELECT pg_temp.expect_0136_failure('22023','unassigned project relationship request payload changed',command) FROM (VALUES
  ('SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'',3)'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'',2,''active'')'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'',2,''paused'',NULL)'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'',2,''paused'',''0136 PII note private@example.test'',''other'')'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'',2,''paused'',''0136 PII note private@example.test'',''progress_update'',NULL)')
) cases(command);
SELECT pg_temp.expect_0136_failure('22023','invalid unassigned project relationship request',command) FROM (VALUES
  ('SELECT * FROM pg_temp.stage_0136(''person'',NULL)'),('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),NULL)'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),5)'),('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),2,''bad'')'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),2,''active'',''   '')'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),2,''active'',repeat(''x'',4001))'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),2,''active'',NULL,''bad'')'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),2,''active'',NULL,''other'',''   '')'),
  ('SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid(),2,''active'',NULL,''other'',repeat(''x'',1001))')
) cases(command);
SELECT pg_temp.expect_0136_failure('55000','pending project relationship metadata or payload is incomplete',$statement$
DO $corrupt$ BEGIN
  SET LOCAL session_replication_role=replica;
  DELETE FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_first);
  SET LOCAL session_replication_role=origin;
  PERFORM pg_temp.read_0136('person');
END $corrupt$ $statement$);
DO $qualification$
DECLARE variant integer;
BEGIN
  FOR variant IN 1..4 LOOP
    BEGIN
      CASE variant
        WHEN 1 THEN UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id=(SELECT app_user_id FROM fixture_0136_context);
        WHEN 2 THEN DELETE FROM app_data.user_current_projects WHERE app_user_id=(SELECT app_user_id FROM fixture_0136_context);
        WHEN 3 THEN UPDATE app_data.projects SET status='archived' WHERE project_id=(SELECT project_id FROM fixture_0136_context);
        WHEN 4 THEN UPDATE app_data.promotion_target_assignments SET ended_at=clock_timestamp(),end_reason='0136 qualification ended'
          WHERE promotion_target_id=(SELECT second_target FROM fixture_0136_pairs WHERE kind='person') AND ended_at IS NULL;
      END CASE;
      PERFORM pg_temp.expect_0136_failure('42501',NULL,'SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'')');
      RAISE EXCEPTION USING ERRCODE='ZXREV',MESSAGE='restore synthetic qualification';
    EXCEPTION WHEN SQLSTATE 'ZXREV' THEN NULL;
    END;
  END LOOP;
END $qualification$;
CREATE FUNCTION pg_temp.fail_0136_insert() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF current_setting('fixture.fail_0136_table',true)=TG_TABLE_NAME THEN RAISE EXCEPTION USING ERRCODE='P0136',MESSAGE='0136 injected insert failure'; END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0136_header_failure BEFORE INSERT ON app_private.personal_merge_unassigned_project_relationship_requests_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0136_insert();
CREATE TRIGGER fixture_0136_payload_failure BEFORE INSERT ON app_data.personal_merge_unassigned_project_relationship_facts_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0136_insert();
DO $faults$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['personal_merge_unassigned_project_relationship_requests_v1','personal_merge_unassigned_project_relationship_facts_v1'] LOOP
    PERFORM set_config('fixture.fail_0136_table',table_name,true);
    PERFORM pg_temp.expect_0136_failure('P0136','0136 injected insert failure','SELECT * FROM pg_temp.stage_0136(''person'',gen_random_uuid())');
  END LOOP;
  PERFORM set_config('fixture.fail_0136_table','',true);
END $faults$;
SELECT pg_temp.expect_0136_failure('55000','pending project relationship facts cannot be updated',
  'UPDATE app_data.personal_merge_unassigned_project_relationship_facts_v1 SET new_stage=new_stage');
SELECT pg_temp.expect_0136_failure('42501','pending project relationship deletion requires expiry receipt',
  'DELETE FROM app_data.personal_merge_unassigned_project_relationship_facts_v1');
SELECT pg_temp.expect_0136_failure('55000',NULL,'DELETE FROM app_private.personal_merge_unassigned_project_relationship_requests_v1');
SELECT pg_temp.expect_0136_failure('55000',NULL,'UPDATE app_private.personal_merge_unassigned_project_relationship_requests_v1 SET request_id=request_id');
SELECT pg_temp.expect_0136_failure('55000','unassigned project relationship facts prevent known-source split',
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,
    (pg_temp.read_0136(''person'')->''known_source_plan''->>''fact_fingerprint'')) FROM fixture_0136_context c,fixture_0136_pairs p WHERE p.kind=''person''');

SELECT pg_temp.assert_0136(result_code='accepted','contact confirmation source seed was rejected') FROM fixture_0136_context c,
  LATERAL app_data.apply_contact_submit_v3(c.app_user_id,'0136-contact-submit',1,'contact.submit.v1','0136-device','0136-contact',0,
    jsonb_build_object('contactId','0136-contact','workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
      'reason','0136 source','occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) submitted;
CREATE TEMP TABLE fixture_0136_contact_pending AS SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  gen_random_uuid(),p.generation_id,'0136-contact',1,2,'yes',false,true) AS pending_fact_id,p.first_target
FROM fixture_0136_context c,fixture_0136_pairs p WHERE p.kind='person';
SELECT pg_temp.expect_0136_failure('55000','unassigned project relationship facts prevent known-source split',
  'SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,
    plan->''known_source_plan''->>''fact_fingerprint'',plan->>''pending_fingerprint'',
    jsonb_build_array(jsonb_build_object(''pending_fact_id'',pending.pending_fact_id,''source_target_id'',pending.first_target)))
  FROM fixture_0136_context c,fixture_0136_pairs p,fixture_0136_contact_pending pending,
    LATERAL (SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id) plan) document WHERE p.kind=''person''');

UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months' WHERE promotion_target_id IN(SELECT first_target FROM fixture_0136_pairs UNION ALL SELECT second_target FROM fixture_0136_pairs);
CREATE FUNCTION pg_temp.suppress_0136_purge() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF NEW.pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_first) THEN RETURN NULL; END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0136_suppress_purge BEFORE INSERT ON app_private.personal_merge_unassigned_project_relationship_purges_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_0136_purge();
SELECT pg_temp.expect_0136_failure('55000','pending project relationship purge count mismatch','SELECT pg_temp.expire_0136(''person'')');
DROP TRIGGER fixture_0136_suppress_purge ON app_private.personal_merge_unassigned_project_relationship_purges_v1;
CREATE TEMP TABLE fixture_0136_expired AS SELECT pg_temp.expire_0136('person') AS ended_at_utc;
SELECT pg_temp.assert_0136(NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 fact
    JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
    WHERE header.generation_id=(SELECT generation_id FROM fixture_0136_pairs WHERE kind='person'))
  AND (SELECT count(*)=2 AND bool_and(purge.purged_at_utc=receipt.ended_at_utc AND receipt.reason='retention_expired'
    AND receipt.operation='personal_target_known_source_merge_expire' AND receipt.outcome='ended')
    FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 purge JOIN app_private.personal_target_merge_end_events_v1 receipt USING(generation_id)
    WHERE purge.generation_id=(SELECT generation_id FROM fixture_0136_pairs WHERE kind='person'))
  AND (SELECT count(*)=2 FROM app_data.promotion_targets WHERE status='anonymized' AND promotion_target_id IN(
    SELECT first_target FROM fixture_0136_pairs WHERE kind='person' UNION ALL SELECT second_target FROM fixture_0136_pairs WHERE kind='person')),
  'pair expiry did not atomically purge every payload with the exact end receipt');
SELECT pg_temp.expect_0136_failure('55000',NULL,'DELETE FROM app_private.personal_merge_unassigned_project_relationship_purges_v1');
SELECT pg_temp.expect_0136_failure('42501',NULL,'SELECT * FROM pg_temp.stage_0136(''person'',''00000000-0136-1000-8000-000000000001'')');

CREATE TEMP TABLE fixture_0136_ordinary AS SELECT (target->>'target_id')::uuid AS target_id FROM fixture_0136_context c,
  LATERAL app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,'person','0136 ordinary due target',NULL,NULL,'0136-ordinary') created;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months' WHERE promotion_target_id=(SELECT target_id FROM fixture_0136_ordinary);
CREATE FUNCTION pg_temp.suppress_0136_payload_delete() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF OLD.pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_institution) THEN RETURN NULL; END IF;
  RETURN OLD;
END $function$;
CREATE TRIGGER fixture_0136_suppress_payload_delete BEFORE DELETE ON app_data.personal_merge_unassigned_project_relationship_facts_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.suppress_0136_payload_delete();
CREATE TEMP TABLE fixture_0136_batch AS SELECT result.* FROM fixture_0136_context c,
  LATERAL app_private.dispatch_assigned_personal_target_expiry_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid()) result;
DROP TRIGGER fixture_0136_suppress_payload_delete ON app_data.personal_merge_unassigned_project_relationship_facts_v1;
SELECT pg_temp.assert_0136((SELECT count(*)=2 FROM fixture_0136_batch)
  AND EXISTS(SELECT 1 FROM fixture_0136_batch WHERE unit_kind='generation' AND unit_id=(SELECT generation_id FROM fixture_0136_pairs WHERE kind='institution')
    AND outcome='failed' AND failure_code='integrity_failure' AND failure_sqlstate='55000' AND processed_at_utc IS NULL)
  AND EXISTS(SELECT 1 FROM fixture_0136_batch WHERE unit_kind='target' AND unit_id=(SELECT target_id FROM fixture_0136_ordinary) AND outcome='expired')
  AND EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_institution))
  AND NOT EXISTS(SELECT 1 FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0136_institution))
  AND NOT EXISTS(SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=(SELECT generation_id FROM fixture_0136_pairs WHERE kind='institution')),
  'failed project payload purge leaked pair changes or blocked the unrelated expiry unit');
SELECT result.* FROM fixture_0136_context c,LATERAL app_private.dispatch_assigned_personal_target_expiry_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid()) result;
SELECT pg_temp.assert_0136(NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 fact
  JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id)
  JOIN fixture_0136_pairs pair USING(generation_id)), 'retry did not clear the failed pair payload');
SELECT pg_temp.assert_0136(NOT EXISTS(
  (TABLE fixture_0136_existing_payloads EXCEPT TABLE app_data.personal_merge_unassigned_project_relationship_facts_v1)
  UNION ALL
  (TABLE app_data.personal_merge_unassigned_project_relationship_facts_v1 EXCEPT TABLE fixture_0136_existing_payloads)
), 'pair expiry changed another context pending payload');
SELECT pg_temp.assert_0136(NOT has_function_privilege('tongxingzhe_runtime','app_private.stage_unassigned_personal_merge_project_relationship_v1(uuid,uuid,uuid,uuid,uuid,integer,text,text,text,text)','EXECUTE')
  AND NOT has_function_privilege('public','app_private.read_personal_merge_unassigned_project_relationship_plan_v1(uuid,uuid,uuid,uuid)','EXECUTE'), 'new stage or reader ACL is open');
ROLLBACK;
