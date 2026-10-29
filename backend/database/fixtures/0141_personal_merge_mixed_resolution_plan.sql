-- Synthetic metadata-only resolution plans. Every source and pending event rolls back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE FUNCTION pg_temp.assert_0141(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0141 %',label; END IF;
END $function$;
\ir shared/database_state.sql
CREATE FUNCTION pg_temp.expect_0141_failure(expected_state text,expected_message text,statement text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_database_state(); actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT; END;
  IF actual_state IS DISTINCT FROM expected_state OR(expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0141 expected % / %, got % / %',expected_state,expected_message,actual_state,actual_message;
  END IF;
  PERFORM pg_temp.assert_0141(before_state=pg_temp.fixture_database_state(),'rejected planner changed business data, context, audit, or fence');
END $function$;
CREATE TEMP TABLE fixture_0141_context AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0141.example.test','owner');
CREATE TEMP TABLE fixture_0141_other AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0141.example.test','other');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0141.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0141_projects AS SELECT 'a'::text AS name,c.* FROM fixture_0141_context c;
INSERT INTO fixture_0141_projects SELECT 'b',c.* FROM app_data.create_personal_project_context('https://synthetic-0141.example.test','owner','0141 project B') c;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0141.example.test','owner',(SELECT project_id FROM fixture_0141_context));
CREATE TEMP TABLE fixture_0141_pairs(kind text,target_type text,first_target uuid,second_target uuid,generation_id uuid);
DO $seed$
DECLARE c record; kind text; target_type text; first_target uuid; second_target uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0141_context;
  FOREACH kind IN ARRAY ARRAY['person','institution'] LOOP
    target_type := kind;
    SELECT (target->>'target_id')::uuid INTO STRICT first_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      target_type,'0141 first '||kind,'+1 312 555 0141',NULL,'0141-'||kind||'-first');
    SELECT (target->>'target_id')::uuid INTO STRICT second_target FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      target_type,'0141 second '||kind,'+1 312 555 0141',NULL,'0141-'||kind||'-second');
    INSERT INTO fixture_0141_pairs VALUES(kind,target_type,first_target,second_target,NULL);
  END LOOP;
END $seed$;
CREATE FUNCTION pg_temp.enter_project_0141(project_name text,kind text,source_number integer) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; pair record; source uuid; contact text; code text;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0141_projects WHERE name=$1;
  SELECT * INTO STRICT pair FROM fixture_0141_pairs p WHERE p.kind=$2;
  source := CASE source_number WHEN 1 THEN pair.first_target ELSE pair.second_target END;
  contact := '0141-entry-'||project_name||'-'||kind||'-'||source_number;
  PERFORM app_data.select_personal_project_context('https://synthetic-0141.example.test','owner',c.project_id);
  SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,contact||'-submit',1,'contact.submit.v1','0141-device',contact,0,
    jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
      'reason','0141 real project entry','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
      'targetLinks',jsonb_build_array(jsonb_build_object('targetId',source,'targetType',pair.target_type,'responseLevel',NULL,
        'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
  PERFORM pg_temp.assert_0141(code='accepted','ordinary contact revision did not create project relationship');
END $function$;
SELECT pg_temp.enter_project_0141('a','person',1);
SELECT pg_temp.enter_project_0141('a','institution',1);
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0141.example.test','owner',(SELECT project_id FROM fixture_0141_context));
DO $activate$
DECLARE c record; pair record; preview uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0141_context;
  FOR pair IN TABLE fixture_0141_pairs LOOP
    SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0141.example.test','owner',c.project_id,pair.first_target,pair.second_target);
    UPDATE fixture_0141_pairs SET generation_id=app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,
      pair.first_target,pair.second_target,pair.first_target,pair.second_target) WHERE kind=pair.kind;
  END LOOP;
END $activate$;

CREATE TEMP TABLE fixture_0141_contacts(kind text,project_name text,contact_id text,source_target_id uuid);
INSERT INTO fixture_0141_contacts
SELECT kind,'a',CASE kind WHEN 'person' THEN '0141 A | "TEXT": 汉字' ELSE '0141机构| "Q": exact' END,first_target FROM fixture_0141_pairs
UNION ALL SELECT kind,'b',CASE kind WHEN 'person' THEN '0141-a' ELSE '0141-institution-b' END,second_target FROM fixture_0141_pairs;
CREATE TEMP TABLE fixture_0141_contact_pending(kind text,pending_fact_id uuid,source_target_id uuid);
DO $contacts$
DECLARE item record; c record; pair record; code text; pending uuid; snapshot jsonb;
BEGIN
  FOR item IN TABLE fixture_0141_contacts LOOP
    SELECT * INTO STRICT c FROM fixture_0141_projects WHERE name=item.project_name;
    SELECT * INTO STRICT pair FROM fixture_0141_pairs WHERE kind=item.kind;
    PERFORM app_data.select_personal_project_context('https://synthetic-0141.example.test','owner',c.project_id);
    SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,item.contact_id||'-submit',1,'contact.submit.v1','0141-device',item.contact_id,0,
      jsonb_build_object('contactId',item.contact_id,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
        'reason','0141 private contact reason','occurredAtUtc','2025-01-02T03:04:05Z','occurredTimeZone','UTC','channel','video_call',
        'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));
    PERFORM pg_temp.assert_0141(code='accepted','real mixed contact submit was not accepted');
    pending:=app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),pair.generation_id,item.contact_id,1,2,'unknown',pair.target_type='institution',true);
    INSERT INTO fixture_0141_contact_pending VALUES(item.kind,pending,item.source_target_id);
    SELECT revision.snapshot INTO STRICT snapshot FROM app_data.contact_revisions revision WHERE contact_id=item.contact_id AND revision_number=1;
    SELECT result_code INTO STRICT code FROM app_data.apply_contact_revise_v3(c.app_user_id,item.contact_id||'-revise-1',1,'contact.revise.v1','0141-device',item.contact_id,1,
      snapshot||jsonb_build_object('reason','0141 private revised reason','interestLevel',3));
    PERFORM pg_temp.assert_0141(code='accepted','real historical contact revision was not accepted');
    pending:=app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),pair.generation_id,item.contact_id,2,2,'unknown',pair.target_type='institution',true);
    INSERT INTO fixture_0141_contact_pending VALUES(item.kind,pending,item.source_target_id);
    IF item.project_name='a' THEN
      SELECT revision.snapshot INTO STRICT snapshot FROM app_data.contact_revisions revision WHERE contact_id=item.contact_id AND revision_number=2;
      SELECT result_code INTO STRICT code FROM app_data.apply_contact_revise_v3(c.app_user_id,item.contact_id||'-revise-2',1,'contact.revise.v1','0141-device',item.contact_id,2,
        snapshot||jsonb_build_object('reason','0141 private current link reason','interestLevel',4,'targetLinks',jsonb_build_array(jsonb_build_object(
          'targetId',item.source_target_id,'targetType',pair.target_type,'responseLevel',NULL,'followUpConsent','unknown',
          'institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
      PERFORM pg_temp.assert_0141(code='accepted','real current source link revision was not accepted');
    END IF;
  END LOOP;
END $contacts$;
CREATE TEMP TABLE fixture_0141_project_pending(kind text,pending_fact_id uuid,source_target_id uuid);
DO $project_pending$
DECLARE pair record; c record; pending uuid; repeat_number integer;
BEGIN
  FOR pair IN TABLE fixture_0141_pairs LOOP
    FOR c IN TABLE fixture_0141_projects LOOP
      PERFORM app_data.select_personal_project_context('https://synthetic-0141.example.test','owner',c.project_id);
      FOR repeat_number IN 1..2 LOOP
        SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
          gen_random_uuid(),pair.generation_id,2,'paused','0141 private project note private@example.test','progress_update','0141 private project detail');
        INSERT INTO fixture_0141_project_pending VALUES(pair.kind,pending,CASE c.name WHEN 'a' THEN pair.first_target ELSE pair.second_target END);
      END LOOP;
    END LOOP;
  END LOOP;
END $project_pending$;
SELECT count(*) FROM app_data.select_personal_project_context('https://synthetic-0141.example.test','owner',(SELECT project_id FROM fixture_0141_projects WHERE name='b'));
CREATE TEMP TABLE fixture_0141_plans AS
SELECT pair.kind,pair.generation_id,
  app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS contact_inventory,
  app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,b.project_id,pair.generation_id) AS project_inventory,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id)
    FROM fixture_0141_contact_pending pending WHERE pending.kind=pair.kind) AS contact_assignments,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',pending_fact_id,'source_target_id',source_target_id) ORDER BY pending_fact_id)
    FROM fixture_0141_project_pending pending WHERE pending.kind=pair.kind) AS project_assignments
FROM fixture_0141_pairs pair,fixture_0141_context c,fixture_0141_projects b WHERE b.name='b';
CREATE FUNCTION pg_temp.read_0141(kind text,contact_assignments jsonb DEFAULT NULL,project_assignments jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT app_private.plan_personal_merge_mixed_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
    p.contact_inventory->'known_source_plan'->>'fact_fingerprint',p.contact_inventory->>'pending_fingerprint',p.project_inventory->>'pending_fingerprint',
    coalesce($2,p.contact_assignments),coalesce($3,p.project_assignments))
  FROM fixture_0141_context c,fixture_0141_projects b,fixture_0141_plans p WHERE b.name='b' AND p.kind=$1
$function$;
CREATE FUNCTION pg_temp.assert_document_0141(document jsonb) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  PERFORM pg_temp.assert_0141(ARRAY(SELECT jsonb_object_keys(document) ORDER BY 1)=
    ARRAY['contact_resolution_plan','contract_id','project_relationship_resolution_plan','resolution_fingerprint']
    AND document->>'contract_id'='personal_merge_mixed_resolution_plan_v1'
    AND document->>'resolution_fingerprint'=encode(sha256(convert_to((document-'resolution_fingerprint')::text,'UTF8')),'hex')
    AND document->'contact_resolution_plan'->'known_source_plan'=document->'project_relationship_resolution_plan'->'known_source_plan'
    AND position('private@example.test' IN document::text)=0 AND position('0141 private project detail' IN document::text)=0,
    'four-key contract, nested known plan, privacy allowlist, or metadata digest differs');
END $function$;
CREATE TEMP TABLE fixture_0141_initial AS
SELECT p.kind,pg_temp.read_0141(p.kind) AS document,
  app_private.plan_unassigned_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
    p.contact_inventory->'known_source_plan'->>'fact_fingerprint',p.contact_inventory->>'pending_fingerprint',p.contact_assignments) AS contact_standalone,
  app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id,
    p.contact_inventory->'known_source_plan'->>'fact_fingerprint',p.project_inventory->>'pending_fingerprint',p.project_assignments) AS project_standalone
FROM fixture_0141_plans p,fixture_0141_context c,fixture_0141_projects b WHERE b.name='b';
DO $baseline$
DECLARE before_state jsonb:=pg_temp.fixture_database_state(); item record; canonical_contacts jsonb; canonical_projects jsonb;
BEGIN
  FOR item IN SELECT p.*,initial.document,initial.contact_standalone,initial.project_standalone FROM fixture_0141_plans p JOIN fixture_0141_initial initial USING(kind) LOOP
    PERFORM pg_temp.assert_document_0141(item.document);
    PERFORM pg_temp.assert_0141(item.document->'contact_resolution_plan'=item.contact_standalone
      AND item.document->'project_relationship_resolution_plan'=item.project_standalone,'nested plans differ from standalone plans in the same command');
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ordinal DESC)
      INTO canonical_contacts FROM jsonb_array_elements(item.contact_assignments) WITH ORDINALITY entries(value,ordinal);
    SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ordinal DESC)
      INTO canonical_projects FROM jsonb_array_elements(item.project_assignments) WITH ORDINALITY entries(value,ordinal);
    PERFORM pg_temp.assert_0141(pg_temp.read_0141(item.kind,canonical_contacts,canonical_projects)=item.document,'UUID case or assignment array order changed the complete composite');
    PERFORM pg_temp.assert_0141(jsonb_array_length(item.document->'contact_resolution_plan'->'contacts')=2
      AND (SELECT sum(jsonb_array_length(value->'pending_facts')) FROM jsonb_array_elements(item.document->'contact_resolution_plan'->'contacts'))=4
      AND jsonb_array_length(item.document->'project_relationship_resolution_plan'->'assignments')=4
      AND (SELECT count(*)=1 FROM jsonb_array_elements(item.document->'project_relationship_resolution_plan'->'source_slots') slot WHERE slot->'current_relationship'='null'::jsonb)
      AND (SELECT count(*)=1 FROM jsonb_array_elements(item.document->'project_relationship_resolution_plan'->'source_slots') slot WHERE slot->'current_relationship'<>'null'::jsonb),
      'nested inventories deduplicated equal events or changed existing/missing slots');
    PERFORM pg_temp.assert_0141(item.document->'contact_resolution_plan'->'contacts'=(SELECT jsonb_agg(value ORDER BY value->>'contact_id' COLLATE "C")
      FROM jsonb_array_elements(item.document->'contact_resolution_plan'->'contacts'))
      AND (SELECT count(*)=2 FROM jsonb_array_elements(item.document->'contact_resolution_plan'->'contacts') contact
        JOIN fixture_0141_contacts fixture ON fixture.contact_id=contact->>'contact_id' WHERE fixture.kind=item.kind),
      'exact TEXT contact IDs or C order changed');
  END LOOP;
  PERFORM pg_temp.assert_0141(before_state=pg_temp.fixture_database_state(),'successful mixed plan wrote business data, audit, context, or fence');
END $baseline$;
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only=on;
DO $readonly$
DECLARE before_state jsonb:=pg_temp.fixture_database_state();
BEGIN
  PERFORM pg_temp.assert_0141(current_setting('transaction_read_only')='on','READ ONLY mode was not enabled');
  PERFORM pg_temp.assert_document_0141(pg_temp.read_0141(kind)) FROM fixture_0141_plans;
  PERFORM pg_temp.assert_0141(before_state=pg_temp.fixture_database_state(),'READ ONLY mixed plan changed persisted state');
END $readonly$;
ROLLBACK TO readonly_scope;
RELEASE readonly_scope;
SAVEPOINT business_payloads;
SET LOCAL session_replication_role=replica;
UPDATE app_data.personal_merge_unassigned_contact_facts_v1 SET response_level=4 WHERE pending_fact_id IN(SELECT pending_fact_id FROM fixture_0141_contact_pending);
UPDATE app_data.personal_merge_unassigned_project_relationship_facts_v1 SET new_stage=4,follow_up_note='0141 changed private value',reason_detail='0141 changed private reason'
WHERE pending_fact_id IN(SELECT pending_fact_id FROM fixture_0141_project_pending);
SET LOCAL session_replication_role=origin;
SELECT pg_temp.assert_0141(document=pg_temp.read_0141(kind),'mixed plan read or hashed pending business values') FROM fixture_0141_initial;
ROLLBACK TO business_payloads;
RELEASE business_payloads;

SELECT pg_temp.expect_0141_failure('22023','mixed resolution plan requires nonempty assignment arrays',
  format('SELECT pg_temp.read_0141(''person'',%L::jsonb,%L::jsonb)',CASE family WHEN 'contact' THEN bad ELSE p.contact_assignments END,
    CASE family WHEN 'project' THEN bad ELSE p.project_assignments END))
FROM fixture_0141_plans p,(VALUES('contact'),('project')) families(family),(VALUES('null'::jsonb),('{}'),('4'),('[]')) invalid(bad) WHERE p.kind='person';
SELECT pg_temp.expect_0141_failure(expected_state,NULL,format('SELECT pg_temp.read_0141(''person'',%L::jsonb,%L::jsonb)',
  CASE family WHEN 'contact' THEN bad ELSE p.contact_assignments END,CASE family WHEN 'project' THEN bad ELSE p.project_assignments END))
FROM fixture_0141_plans p,(VALUES('contact'),('project')) families(family),
  LATERAL(SELECT CASE family WHEN 'contact' THEN p.contact_assignments ELSE p.project_assignments END mapping) original,
  LATERAL(VALUES('22023','[null]'::jsonb),('22023','[1]'::jsonb),('22023','[{}]'::jsonb),
    ('22023',mapping||jsonb_build_array(mapping->0)),
    ('22023',jsonb_build_array((mapping->0)||jsonb_build_object('extra',true))||(mapping-0)),
    ('22023',jsonb_build_array((mapping->0)-'source_target_id')||(mapping-0)),
    ('22023',jsonb_build_array((mapping->0)||jsonb_build_object('pending_fact_id','bad'))||(mapping-0)),
    ('22023',jsonb_build_array((mapping->0)||jsonb_build_object('source_target_id',replace(mapping->0->>'source_target_id','-','')))||(mapping-0)),
    ('23505',jsonb_build_array(mapping->0)),
    ('23505',mapping||jsonb_build_array(jsonb_build_object('pending_fact_id',gen_random_uuid(),'source_target_id',mapping->0->>'source_target_id'))),
    ('23505',jsonb_build_array((mapping->0)||jsonb_build_object('source_target_id',(SELECT first_target FROM fixture_0141_pairs WHERE kind='institution')))||(mapping-0))
  ) invalid(expected_state,bad) WHERE p.kind='person';
SELECT pg_temp.expect_0141_failure(expected_state,NULL,format('SELECT app_private.plan_personal_merge_mixed_resolutions_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
  CASE WHEN field='actor_null' THEN NULL WHEN field='other_actor' THEN other.app_user_id ELSE c.app_user_id END,
  CASE WHEN field='workspace_null' THEN NULL WHEN field='other_workspace' THEN other.workspace_id ELSE c.workspace_id END,
  CASE WHEN field='project_null' THEN NULL WHEN field='wrong_context' THEN c.project_id ELSE b.project_id END,
  CASE WHEN field='generation_null' THEN NULL ELSE p.generation_id END,
  CASE WHEN field='known_null' THEN NULL WHEN field='known_bad' THEN 'bad' WHEN field='known_stale' THEN repeat('0',64) ELSE p.contact_inventory->'known_source_plan'->>'fact_fingerprint' END,
  CASE WHEN field='contact_fp_null' THEN NULL WHEN field='contact_fp_bad' THEN 'bad' WHEN field='contact_fp_stale' THEN repeat('0',64) ELSE p.contact_inventory->>'pending_fingerprint' END,
  CASE WHEN field='project_fp_null' THEN NULL WHEN field='project_fp_bad' THEN 'bad' WHEN field='project_fp_stale' THEN repeat('0',64) ELSE p.project_inventory->>'pending_fingerprint' END,
  CASE WHEN field='contact_array_null' THEN NULL ELSE p.contact_assignments END,CASE WHEN field='project_array_null' THEN NULL ELSE p.project_assignments END))
FROM fixture_0141_context c,fixture_0141_other other,fixture_0141_projects b,fixture_0141_plans p,
  (VALUES('actor_null','22023'),('workspace_null','22023'),('project_null','22023'),('generation_null','22023'),
    ('known_null','22023'),('known_bad','22023'),('contact_fp_null','22023'),('contact_fp_bad','22023'),('project_fp_null','22023'),('project_fp_bad','22023'),
    ('contact_array_null','22023'),('project_array_null','22023'),('known_stale','23505'),('contact_fp_stale','23505'),('project_fp_stale','23505'),
    ('other_actor','42501'),('other_workspace','42501'),('wrong_context','42501')) invalid(field,expected_state) WHERE b.name='b' AND p.kind='person';
SAVEPOINT unavailable_contact;
SET LOCAL session_replication_role=replica;
UPDATE app_data.contacts SET current_revision=999 WHERE contact_id='0141-a';
SET LOCAL session_replication_role=origin;
SELECT pg_temp.expect_0141_failure('55000','pending contact current revision or context is inconsistent','SELECT pg_temp.read_0141(''person'')');
ROLLBACK TO unavailable_contact;
RELEASE unavailable_contact;
SAVEPOINT unavailable_relationship;
SET LOCAL session_replication_role=replica;
UPDATE app_data.promotion_target_project_relationships SET current_revision=999
WHERE promotion_target_id=(SELECT first_target FROM fixture_0141_pairs WHERE kind='person') AND project_id=(SELECT project_id FROM fixture_0141_projects WHERE name='a');
SET LOCAL session_replication_role=origin;
UPDATE fixture_0141_plans p SET contact_inventory=app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,b.project_id,p.generation_id)
FROM fixture_0141_context c,fixture_0141_projects b WHERE b.name='b' AND p.kind='person';
SELECT pg_temp.expect_0141_failure('55000','pending project relationship current revision or context is inconsistent','SELECT pg_temp.read_0141(''person'')');
ROLLBACK TO unavailable_relationship;
RELEASE unavailable_relationship;
SAVEPOINT revoked_scope;
UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id=(SELECT app_user_id FROM fixture_0141_context);
SELECT pg_temp.expect_0141_failure('42501',NULL,'SELECT pg_temp.read_0141(''person'')');
ROLLBACK TO revoked_scope;
RELEASE revoked_scope;
SELECT pg_temp.assert_0141(NOT has_function_privilege('public',
  'app_private.plan_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('tongxingzhe_runtime',
  'app_private.plan_personal_merge_mixed_resolutions_v1(uuid,uuid,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE'),'mixed reader is exposed to PUBLIC or runtime');
ROLLBACK;

