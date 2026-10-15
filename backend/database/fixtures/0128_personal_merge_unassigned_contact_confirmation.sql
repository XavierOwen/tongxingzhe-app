\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0128_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0128.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0128.example.test','owner') WHERE is_current;
INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,
  is_required,allow_unknown,allow_refused,allow_not_applicable)
SELECT questionnaire_version_id,'follow_up_consent',1,'0128 original answer','boolean',false,true,true,true FROM fixture_0128_context;
CREATE TEMP TABLE fixture_0128_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0128.example.test','other');
CREATE TEMP TABLE fixture_0128_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0128_pairs VALUES
  ('person','7f280000-0000-4000-8000-000000000001','7f280000-0000-4000-8000-000000000002',NULL),
  ('institution','7f280000-0000-4000-8000-000000000003','7f280000-0000-4000-8000-000000000004',NULL);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT target_id,c.workspace_id,p.kind,'0128 original source','+1 312 555 0128',c.app_user_id
FROM fixture_0128_pairs p CROSS JOIN fixture_0128_context c
CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id)
SELECT '7f280000-0000-4000-8000-000000000005',workspace_id,'person','0128 unrelated original',app_user_id
FROM fixture_0128_context;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0128_context c WHERE t.workspace_id = c.workspace_id;
DO $activate$
DECLARE c record; p record; preview uuid; generation uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0128_context;
  FOR p IN SELECT * FROM fixture_0128_pairs LOOP
    SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1(
      'https://synthetic-0128.example.test','owner',c.project_id,p.first_target,p.second_target);
    generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,
      gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target);
    UPDATE fixture_0128_pairs SET generation_id = generation WHERE kind = p.kind;
  END LOOP;
END $activate$;
CREATE FUNCTION pg_temp.fixture_0128_submit(contact text,links jsonb DEFAULT '[]'::jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE result record;
BEGIN
  SELECT s.* INTO result FROM fixture_0128_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
    c.app_user_id,contact || '-submit',1,'contact.submit.v1','0128-device',contact,0,
    jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,
      'questionnaireVersionId',c.questionnaire_version_id,'reason','0128 original reason',
      'occurredAtUtc','2025-05-03T04:05:06.123456Z','occurredTimeZone','America/Chicago','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',3,
      'answers',jsonb_build_array(jsonb_build_object('questionId','follow_up_consent','state','answered','type','boolean','value',true)),
      'targetLinks',links)) s;
  IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0128 contact setup rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0128_submit('0128 person | "TEXT": 汉字',jsonb_build_array(jsonb_build_object(
  'targetId','7f280000-0000-4000-8000-000000000005','targetType','person','responseLevel',1,
  'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
SELECT pg_temp.fixture_0128_submit(contact) FROM (VALUES
  ('0128-person-second'),('0128-institution-null'),('0128-institution-representative')) t(contact);
CREATE TEMP TABLE fixture_0128_pending ON COMMIT DROP AS
SELECT p.kind,t.contact,t.source_target_id,
  app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
    t.request_id,p.generation_id,t.contact,1,t.response,t.consent,t.representative,t.entry) AS pending_fact_id
FROM fixture_0128_context c CROSS JOIN fixture_0128_pairs p
JOIN (VALUES
  ('person','0128 person | "TEXT": 汉字','7f280000-0000-4000-8000-000000000201'::uuid,'7f280000-0000-4000-8000-000000000001'::uuid,NULL::integer,'unknown',false,true),
  ('person','0128-person-second','7f280000-0000-4000-8000-000000000202'::uuid,'7f280000-0000-4000-8000-000000000002'::uuid,2,'yes',false,true),
  ('institution','0128-institution-null','7f280000-0000-4000-8000-000000000203'::uuid,'7f280000-0000-4000-8000-000000000003'::uuid,NULL::integer,'not_applicable',false,false),
  ('institution','0128-institution-representative','7f280000-0000-4000-8000-000000000204'::uuid,'7f280000-0000-4000-8000-000000000004'::uuid,2,'yes',true,true)
) t(kind,contact,request_id,source_target_id,response,consent,representative,entry) ON t.kind = p.kind;
CREATE TEMP TABLE fixture_0128_plans ON COMMIT DROP AS
SELECT p.kind,p.generation_id,gen_random_uuid() AS request_id,
  app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id) AS document,
  (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',n.pending_fact_id,'source_target_id',n.source_target_id)
    ORDER BY n.pending_fact_id) FROM fixture_0128_pending n WHERE n.kind = p.kind) AS assignments
FROM fixture_0128_context c CROSS JOIN fixture_0128_pairs p;
CREATE FUNCTION pg_temp.fixture_0128_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
  FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind = 'r' ORDER BY n.nspname,c.relname LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
    state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
  END LOOP;
  RETURN state;
END $function$;
CREATE FUNCTION pg_temp.fixture_0128_confirm(kind text,assignments jsonb,request uuid DEFAULT NULL) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(c.app_user_id,c.workspace_id,
    (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = c.app_user_id),
    coalesce($3,p.request_id),p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint',
    p.document->>'pending_fingerprint',$2)
  FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p WHERE p.kind = $1
$function$;
CREATE FUNCTION pg_temp.fixture_0128_run(kind text) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT pg_temp.fixture_0128_confirm($1,p.assignments) FROM fixture_0128_plans p WHERE p.kind = $1
$function$;
CREATE FUNCTION pg_temp.fixture_0128_expect_failure(expected text,command text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_0128_state(); actual text; detail text;
BEGIN
  BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE,detail = MESSAGE_TEXT; END;
  IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '0128 expected %, got % (%): %',expected,actual,detail,command; END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0128_state()
  THEN RAISE EXCEPTION '0128 failed operation left business, fence, feed, outbox or receipt changes'; END IF;
END $function$;
SELECT pg_temp.fixture_0128_expect_failure('22023',format('SELECT pg_temp.fixture_0128_confirm(''person'',%L::jsonb)',value))
FROM (VALUES ('null'),('{}'),('[]'),('[null]'),('[1]'),('[{}]')) t(value);
SELECT pg_temp.fixture_0128_expect_failure('22023',$$SELECT pg_temp.fixture_0128_confirm('person',NULL::jsonb)$$);
SELECT pg_temp.fixture_0128_expect_failure('22023',format(
  'SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
  CASE WHEN field = 'actor' THEN NULL ELSE c.app_user_id END,CASE WHEN field = 'workspace' THEN NULL ELSE c.workspace_id END,
  CASE WHEN field = 'project' THEN NULL ELSE c.project_id END,CASE WHEN field = 'request' THEN NULL ELSE p.request_id END,
  CASE WHEN field = 'generation' THEN NULL ELSE p.generation_id END,
  CASE WHEN field = 'known' THEN NULL WHEN field = 'known_shape' THEN 'bad' ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
  CASE WHEN field = 'pending' THEN NULL WHEN field = 'pending_shape' THEN 'bad' ELSE p.document->>'pending_fingerprint' END,p.assignments))
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p
CROSS JOIN (VALUES('actor'),('workspace'),('project'),('request'),('generation'),('known'),('known_shape'),('pending'),('pending_shape')) t(field)
WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('22023',format('SELECT pg_temp.fixture_0128_confirm(''person'',%L::jsonb)',
  jsonb_build_array((assignments->0) || jsonb_build_object(key,value),assignments->1)))
FROM fixture_0128_plans CROSS JOIN (VALUES
  ('confirm_stage_zero','true'::jsonb),('response_level','2'::jsonb),('source_target_id','"not-a-uuid"'::jsonb),
  ('pending_fact_id','null'::jsonb),('pending_fact_id','4'::jsonb)) t(key,value) WHERE kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('22023',format('SELECT pg_temp.fixture_0128_confirm(''person'',%L::jsonb)',
  jsonb_build_array((assignments->0) - key,assignments->1)))
FROM fixture_0128_plans CROSS JOIN (VALUES('pending_fact_id'),('source_target_id')) t(key) WHERE kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure(expected,format('SELECT pg_temp.fixture_0128_confirm(''person'',%L::jsonb)',value))
FROM fixture_0128_plans CROSS JOIN LATERAL (VALUES
  ('23505',jsonb_build_array(assignments->0)),('22023',assignments || jsonb_build_array(assignments->0)),
  ('22023',jsonb_build_array(assignments->0,assignments->0)),
  ('23505',jsonb_build_array((assignments->0) || jsonb_build_object('pending_fact_id',gen_random_uuid()),assignments->1)),
  ('23505',assignments || jsonb_build_array(jsonb_build_object('pending_fact_id',gen_random_uuid(),'source_target_id','7f280000-0000-4000-8000-000000000001'))),
  ('23505',jsonb_build_array((assignments->0) || jsonb_build_object('source_target_id','7f280000-0000-4000-8000-000000000005'),assignments->1)),
  ('23505',jsonb_build_array((assignments->0) || jsonb_build_object('source_target_id','7f280000-0000-4000-8000-000000000003'),assignments->1))
) t(expected,value) WHERE kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('23505',format(
  'SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
  c.app_user_id,c.workspace_id,c.project_id,p.request_id,p.generation_id,
  CASE WHEN field = 'known' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
  CASE WHEN field = 'pending' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,p.assignments))
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p CROSS JOIN (VALUES('known'),('pending')) t(field) WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('42501',format(
  'SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
  o.app_user_id,c.workspace_id,c.project_id,p.request_id,p.generation_id,
  p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.assignments))
FROM fixture_0128_context c CROSS JOIN fixture_0128_other o CROSS JOIN fixture_0128_plans p WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('55000',format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,p.document->'known_source_plan'->>'fact_fingerprint'))
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p WHERE p.kind = 'person';

SAVEPOINT stale_revision;
SELECT result_code FROM fixture_0128_context c CROSS JOIN LATERAL app_data.apply_contact_revise_v3(
  c.app_user_id,'0128-ordinary-revise',1,'contact.revise.v1','0128-device','0128-person-second',1,
  (SELECT snapshot FROM app_data.contact_revisions WHERE contact_id = '0128-person-second' AND revision_number = 1)) s;
SELECT pg_temp.fixture_0128_expect_failure('23505',$$SELECT pg_temp.fixture_0128_run('person')$$);
CREATE TEMP TABLE fixture_0128_multiple ON COMMIT DROP AS
SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  gen_random_uuid(),p.generation_id,'0128-person-second',2,2,'yes',false,true) AS pending_fact_id
FROM fixture_0128_context c CROSS JOIN fixture_0128_pairs p WHERE p.kind = 'person';
UPDATE fixture_0128_plans p SET document = app_private.read_personal_merge_unassigned_contact_plan_v1(
  c.app_user_id,c.workspace_id,c.project_id,p.generation_id),assignments = p.assignments || jsonb_build_array(
    jsonb_build_object('pending_fact_id',m.pending_fact_id,'source_target_id','7f280000-0000-4000-8000-000000000001'))
FROM fixture_0128_context c CROSS JOIN fixture_0128_multiple m WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('23505',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT stale_revision;
RELEASE SAVEPOINT stale_revision;

SAVEPOINT existing_link;
INSERT INTO app_data.contact_target_links(contact_id,revision_number,promotion_target_id,response_level,
  follow_up_consent,institution_representative_confirmed,confirmed_project_entry)
VALUES('0128-person-second',1,'7f280000-0000-4000-8000-000000000002',NULL,'unknown',false,true);
UPDATE fixture_0128_plans p SET document = app_private.read_personal_merge_unassigned_contact_plan_v1(
  c.app_user_id,c.workspace_id,c.project_id,p.generation_id) FROM fixture_0128_context c WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('23505',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT existing_link;
RELEASE SAVEPOINT existing_link;

SAVEPOINT due_target;
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7f280000-0000-4000-8000-000000000002';
SELECT pg_temp.fixture_0128_expect_failure('42501',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT due_target;
RELEASE SAVEPOINT due_target;

SELECT pg_temp.fixture_0128_expect_failure('23505',$$SELECT pg_temp.fixture_0128_run('institution')$$);
SAVEPOINT unconfirmed_representative;
ALTER TABLE app_data.personal_merge_unassigned_contact_facts_v1 DISABLE TRIGGER guard_personal_merge_unassigned_contact_payload_trigger;
UPDATE app_data.personal_merge_unassigned_contact_facts_v1 SET institution_representative_confirmed = false
WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0128_pending WHERE contact = '0128-institution-representative');
ALTER TABLE app_data.personal_merge_unassigned_contact_facts_v1 ENABLE TRIGGER guard_personal_merge_unassigned_contact_payload_trigger;
SELECT pg_temp.fixture_0128_expect_failure('23505',$$SELECT pg_temp.fixture_0128_run('institution')$$);
ROLLBACK TO SAVEPOINT unconfirmed_representative;
RELEASE SAVEPOINT unconfirmed_representative;

SAVEPOINT preoccupied_child;
INSERT INTO app_data.processed_commands(app_user_id,command_id,protocol_version,command_type,device_id,aggregate_id,result_code,server_cursor)
SELECT c.app_user_id,'personal-merge-contact-confirm-v1:' || p.request_id || ':' || octet_length(n.contact) || ':' || n.contact,
  1,'contact.revise.v1','0128-occupied',n.contact,'accepted',gen_random_uuid()
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p JOIN fixture_0128_pending n USING(kind) WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('23505',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT preoccupied_child;
RELEASE SAVEPOINT preoccupied_child;

CREATE FUNCTION pg_temp.fixture_0128_suppress() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN RETURN NULL; END $function$;
SAVEPOINT suppressed_header;
CREATE TRIGGER fixture_0128_suppress BEFORE INSERT ON app_private.personal_merge_contact_confirmation_requests_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0128_suppress();
SELECT pg_temp.fixture_0128_expect_failure('55000',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT suppressed_header;
RELEASE SAVEPOINT suppressed_header;
SAVEPOINT suppressed_application;
CREATE TRIGGER fixture_0128_suppress BEFORE INSERT ON app_private.personal_merge_contact_applications_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0128_suppress();
SELECT pg_temp.fixture_0128_expect_failure('55000',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT suppressed_application;
RELEASE SAVEPOINT suppressed_application;
SAVEPOINT suppressed_delete;
CREATE TRIGGER fixture_0128_suppress BEFORE DELETE ON app_data.personal_merge_unassigned_contact_facts_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0128_suppress();
SELECT pg_temp.fixture_0128_expect_failure('55000',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT suppressed_delete;
RELEASE SAVEPOINT suppressed_delete;
SAVEPOINT suppressed_end;
CREATE TRIGGER fixture_0128_suppress BEFORE INSERT ON app_private.personal_target_merge_end_events_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0128_suppress();
SELECT pg_temp.fixture_0128_expect_failure('55000',$$SELECT pg_temp.fixture_0128_run('person')$$);
ROLLBACK TO SAVEPOINT suppressed_end;
RELEASE SAVEPOINT suppressed_end;

SAVEPOINT forged_incomplete_application;
SELECT s.result_code FROM fixture_0128_context c CROSS JOIN fixture_0128_pending n
CROSS JOIN LATERAL app_data.apply_contact_revise_v3(c.app_user_id,'0128-forged-child',1,'contact.revise.v1',
  '0128-device',n.contact,1,(SELECT snapshot FROM app_data.contact_revisions WHERE contact_id = n.contact AND revision_number = 1)
  || jsonb_build_object('targetLinks',jsonb_build_array(jsonb_build_object('targetId',n.source_target_id,
    'targetType','person','responseLevel',2,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))) s
WHERE n.contact = '0128-person-second';
INSERT INTO app_private.personal_merge_contact_confirmation_requests_v1(actor_app_user_id,request_id,workspace_id,project_id,
  generation_id,known_fact_fingerprint,pending_fingerprint,post_known_fact_fingerprint,confirmed_at_utc)
SELECT c.app_user_id,p.request_id,c.workspace_id,c.project_id,p.generation_id,
  p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',m.fact_fingerprint,clock_timestamp()
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(p.generation_id) m WHERE p.kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('55000',format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,p.request_id,p.generation_id,m.fact_fingerprint))
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(p.generation_id) m WHERE p.kind = 'person';
INSERT INTO app_private.personal_merge_contact_applications_v1(pending_fact_id,actor_app_user_id,request_id,contact_id,
  from_revision_number,to_revision_number,source_target_id,child_command_id)
SELECT n.pending_fact_id,c.app_user_id,p.request_id,n.contact,1,2,n.source_target_id,'0128-forged-child'
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p JOIN fixture_0128_pending n USING(kind)
WHERE n.contact = '0128-person-second';
SELECT pg_temp.fixture_0128_expect_failure('55000',format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,p.request_id,p.generation_id,m.fact_fingerprint))
FROM fixture_0128_context c CROSS JOIN fixture_0128_plans p
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(p.generation_id) m WHERE p.kind = 'person';
ROLLBACK TO SAVEPOINT forged_incomplete_application;
RELEASE SAVEPOINT forged_incomplete_application;

SAVEPOINT unchanged_expiry;
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7f280000-0000-4000-8000-000000000003';
CREATE TEMP TABLE fixture_0128_expired ON COMMIT DROP AS
SELECT p.generation_id,gen_random_uuid() AS request_id FROM fixture_0128_pairs p WHERE kind = 'institution';
ALTER TABLE fixture_0128_expired ADD COLUMN ended_at_utc timestamptz;
UPDATE fixture_0128_expired e SET ended_at_utc = app_private.expire_known_source_personal_target_merge_generation_v1(
  c.app_user_id,c.workspace_id,c.project_id,e.request_id,e.generation_id) FROM fixture_0128_context c;
DO $expiry$
BEGIN
  IF (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE generation_id = (SELECT generation_id FROM fixture_0128_expired)) <> 2
    OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0128_pending WHERE kind = 'institution'))
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_contact_confirmation_requests_v1 WHERE generation_id = (SELECT generation_id FROM fixture_0128_expired))
    OR EXISTS (SELECT 1 FROM app_data.contact_revisions WHERE contact_id IN (SELECT contact FROM fixture_0128_pending WHERE kind = 'institution') AND revision_number <> 1)
    OR (SELECT app_private.expire_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,
      e.request_id,e.generation_id) FROM fixture_0128_context c CROSS JOIN fixture_0128_expired e) IS DISTINCT FROM (SELECT ended_at_utc FROM fixture_0128_expired)
  THEN RAISE EXCEPTION '0128 changed the original expiry/pending purge path'; END IF;
END $expiry$;
ROLLBACK TO SAVEPOINT unchanged_expiry;
RELEASE SAVEPOINT unchanged_expiry;

-- The same false stage-zero decision succeeds once that original source already has its project relationship.
SELECT pg_temp.fixture_0128_submit('0128-established-institution-source',jsonb_build_array(jsonb_build_object(
  'targetId','7f280000-0000-4000-8000-000000000003','targetType','institution','responseLevel',NULL,
  'followUpConsent','not_applicable','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
UPDATE fixture_0128_plans p SET document = app_private.read_personal_merge_unassigned_contact_plan_v1(
  c.app_user_id,c.workspace_id,c.project_id,p.generation_id) FROM fixture_0128_context c WHERE p.kind = 'institution';
CREATE TEMP TABLE fixture_0128_before_revisions ON COMMIT DROP AS SELECT * FROM app_data.contact_revisions
WHERE contact_id IN (SELECT contact FROM fixture_0128_pending);
CREATE TEMP TABLE fixture_0128_before_answers ON COMMIT DROP AS SELECT * FROM app_data.contact_answers
WHERE contact_id IN (SELECT contact FROM fixture_0128_pending);
CREATE TEMP TABLE fixture_0128_before_links ON COMMIT DROP AS SELECT * FROM app_data.contact_target_links
WHERE contact_id IN (SELECT contact FROM fixture_0128_pending);
CREATE TEMP TABLE fixture_0128_before_contacts ON COMMIT DROP AS SELECT * FROM app_data.contacts
WHERE contact_id IN (SELECT contact FROM fixture_0128_pending);
CREATE TEMP TABLE fixture_0128_payloads ON COMMIT DROP AS SELECT * FROM app_data.personal_merge_unassigned_contact_facts_v1
WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0128_pending);
CREATE TEMP TABLE fixture_0128_project_b ON COMMIT DROP AS
SELECT * FROM app_data.create_personal_project_context('https://synthetic-0128.example.test','owner','0128 current B');
SELECT count(*) FROM fixture_0128_project_b c CROSS JOIN LATERAL app_data.select_personal_project_context(
  'https://synthetic-0128.example.test','owner',c.project_id) p;
CREATE TEMP TABLE fixture_0128_result ON COMMIT DROP AS
SELECT kind,pg_temp.fixture_0128_run(kind) AS confirmed_at FROM fixture_0128_plans;
SET CONSTRAINTS ALL IMMEDIATE;
DO $success$
DECLARE n record; original_snapshot jsonb; revised_snapshot jsonb; old_link record;
BEGIN
  IF (SELECT count(*) FROM app_private.personal_merge_contact_confirmation_requests_v1 WHERE workspace_id = (SELECT workspace_id FROM fixture_0128_context)) <> 2
    OR (SELECT count(*) FROM app_private.personal_merge_contact_applications_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0128_pending)) <> 4
    OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0128_pending))
    OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0128_pending))
    OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0128_pending)) <> 4
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id IN (SELECT generation_id FROM fixture_0128_pairs))
  THEN RAISE EXCEPTION '0128 confirmation did not consume exactly all payloads and retain metadata receipts'; END IF;
  IF EXISTS (SELECT 1 FROM fixture_0128_before_revisions b LEFT JOIN app_data.contact_revisions r USING(contact_id,revision_number) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(r))
    OR EXISTS (SELECT 1 FROM fixture_0128_before_answers b LEFT JOIN app_data.contact_answers a USING(contact_id,revision_number,question_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(a))
    OR EXISTS (SELECT 1 FROM fixture_0128_before_links b LEFT JOIN app_data.contact_target_links l USING(contact_id,revision_number,promotion_target_id) WHERE to_jsonb(b) IS DISTINCT FROM to_jsonb(l))
  THEN RAISE EXCEPTION '0128 rewrote an original revision, answer or link'; END IF;
  FOR n IN SELECT pending.*,payload.*,p.request_id,p.generation_id FROM fixture_0128_pending pending
    JOIN fixture_0128_payloads payload USING(pending_fact_id) JOIN fixture_0128_plans p USING(kind) LOOP
    SELECT snapshot INTO original_snapshot FROM fixture_0128_before_revisions WHERE contact_id = n.contact;
    SELECT snapshot INTO STRICT revised_snapshot FROM app_data.contact_revisions WHERE contact_id = n.contact AND revision_number = 2;
    IF (original_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
      IS DISTINCT FROM (revised_snapshot - ARRAY['targetLinks','reason','revisionKind','revisedAtUtc','firstSubmittedAtUtc'])
      OR NOT EXISTS (SELECT 1 FROM app_data.contacts c JOIN fixture_0128_before_contacts b USING(contact_id)
        WHERE c.contact_id = n.contact AND c.current_revision = 2 AND c.occurred_at_utc = b.occurred_at_utc AND c.project_id = b.project_id)
      OR (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = 1)
        IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) - 'revision_number' ORDER BY question_id) FROM app_data.contact_answers a WHERE contact_id = n.contact AND revision_number = 2)
      OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links l WHERE l.contact_id = n.contact AND l.revision_number = 2
        AND l.promotion_target_id = n.source_target_id AND l.response_level IS NOT DISTINCT FROM n.response_level
        AND l.follow_up_consent = n.follow_up_consent AND l.institution_representative_confirmed = n.institution_representative_confirmed
        AND l.confirmed_project_entry = n.confirmed_project_entry AND l.merge_generation_id = n.generation_id)
      OR NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_applications_v1 a WHERE a.pending_fact_id = n.pending_fact_id
        AND a.contact_id = n.contact AND a.from_revision_number = 1 AND a.to_revision_number = 2 AND a.source_target_id = n.source_target_id
        AND a.child_command_id = 'personal-merge-contact-confirm-v1:' || n.request_id || ':' || octet_length(n.contact) || ':' || n.contact)
      OR NOT EXISTS (SELECT 1 FROM app_data.change_feed f WHERE f.aggregate_id = n.contact AND f.revision_number = 2
        AND f.change_type = 'contact.revised' AND f.project_id = (SELECT project_id FROM fixture_0128_context))
      OR NOT EXISTS (SELECT 1 FROM app_data.warehouse_outbox w WHERE w.contact_id = n.contact AND w.revision_number = 2
        AND w.project_id = (SELECT project_id FROM fixture_0128_context)
        AND jsonb_array_length(w.analytics_payload->'target_link_facts') = jsonb_array_length(revised_snapshot->'targetLinks')
        AND w.analytics_payload::text !~* 'targetId|target_id|0128 original source|phone|email')
    THEN RAISE EXCEPTION '0128 new revision lost original facts, explicit decisions, feed scope or original source ID: %',n.contact; END IF;
  END LOOP;
  FOR old_link IN SELECT * FROM fixture_0128_before_links LOOP
    IF NOT EXISTS (SELECT 1 FROM app_data.contact_target_links l WHERE l.contact_id = old_link.contact_id AND l.revision_number = 2
      AND (to_jsonb(l) - 'revision_number') = (to_jsonb(old_link) - 'revision_number'))
    THEN RAISE EXCEPTION '0128 dropped an unrelated original link in the new revision'; END IF;
  END LOOP;
  IF (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0128_context))
    IS DISTINCT FROM (SELECT project_id FROM fixture_0128_project_b)
  THEN RAISE EXCEPTION '0128 confirmation switched current project'; END IF;
  IF (SELECT count(*) FROM fixture_0128_context c CROSS JOIN LATERAL app_data.pull_contact_changes(
      c.app_user_id,c.workspace_id,c.project_id,NULL,100) f WHERE f.change_type = 'contact.revised' AND f.revision_number = 2) <> 4
    OR EXISTS (SELECT 1 FROM fixture_0128_project_b c CROSS JOIN LATERAL app_data.pull_contact_changes(
      c.app_user_id,c.workspace_id,c.project_id,NULL,100) f WHERE f.contact_payload->>'contactId' IN (SELECT contact FROM fixture_0128_pending))
  THEN RAISE EXCEPTION '0128 sync did not retain original project A scope while B was current'; END IF;
END $success$;
CREATE TEMP TABLE fixture_0128_after ON COMMIT DROP AS SELECT pg_temp.fixture_0128_state() AS state;
DO $replay$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM fixture_0128_result LOOP
    IF pg_temp.fixture_0128_run(r.kind) IS DISTINCT FROM r.confirmed_at
      OR (SELECT pg_temp.fixture_0128_confirm(r.kind,jsonb_build_array(p.assignments->1,p.assignments->0))
        FROM fixture_0128_plans p WHERE p.kind = r.kind) IS DISTINCT FROM r.confirmed_at
    THEN RAISE EXCEPTION '0128 terminal replay timestamp changed'; END IF;
  END LOOP;
  IF pg_temp.fixture_0128_state() IS DISTINCT FROM (SELECT state FROM fixture_0128_after)
  THEN RAISE EXCEPTION '0128 exact terminal replay changed facts, feed, outbox, fence or ledger'; END IF;
END $replay$;
SELECT pg_temp.fixture_0128_expect_failure('23505',format('SELECT pg_temp.fixture_0128_confirm(''person'',%L::jsonb)',
  jsonb_build_array((assignments->0) || jsonb_build_object('source_target_id',CASE assignments->0->>'source_target_id'
    WHEN '7f280000-0000-4000-8000-000000000001' THEN '7f280000-0000-4000-8000-000000000002'
    ELSE '7f280000-0000-4000-8000-000000000001' END),assignments->1)))
FROM fixture_0128_plans WHERE kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('42501',format('SELECT pg_temp.fixture_0128_confirm(''person'',%L::jsonb,%L)',assignments,gen_random_uuid()))
FROM fixture_0128_plans WHERE kind = 'person';
SELECT pg_temp.fixture_0128_expect_failure('23505',format(
  'SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
  c.app_user_id,CASE WHEN field = 'workspace' THEN gen_random_uuid() ELSE c.workspace_id END,
  CASE WHEN field = 'project' THEN c.project_id ELSE b.project_id END,p.request_id,
  CASE WHEN field = 'generation' THEN gen_random_uuid() ELSE p.generation_id END,
  CASE WHEN field = 'known' THEN repeat('0',64) ELSE p.document->'known_source_plan'->>'fact_fingerprint' END,
  CASE WHEN field = 'pending' THEN repeat('0',64) ELSE p.document->>'pending_fingerprint' END,p.assignments))
FROM fixture_0128_context c CROSS JOIN fixture_0128_project_b b CROSS JOIN fixture_0128_plans p
CROSS JOIN (VALUES('workspace'),('project'),('generation'),('known'),('pending')) t(field) WHERE p.kind = 'person';
SAVEPOINT terminal_replay_qualification;
SELECT count(*) FROM fixture_0128_context c CROSS JOIN LATERAL app_data.select_personal_project_context(
  'https://synthetic-0128.example.test','owner',c.project_id) p;
SELECT pg_temp.fixture_0128_expect_failure('42501',format(
  'SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
  c.app_user_id,c.workspace_id,b.project_id,p.request_id,p.generation_id,
  p.document->'known_source_plan'->>'fact_fingerprint',p.document->>'pending_fingerprint',p.assignments))
FROM fixture_0128_context c CROSS JOIN fixture_0128_project_b b CROSS JOIN fixture_0128_plans p WHERE p.kind = 'person';
ROLLBACK TO SAVEPOINT terminal_replay_qualification;
RELEASE SAVEPOINT terminal_replay_qualification;
SELECT pg_temp.fixture_0128_expect_failure('55000',$$UPDATE app_private.personal_merge_contact_confirmation_requests_v1 SET confirmed_at_utc = confirmed_at_utc$$);
SELECT pg_temp.fixture_0128_expect_failure('55000',$$DELETE FROM app_private.personal_merge_contact_applications_v1$$);
ROLLBACK;
