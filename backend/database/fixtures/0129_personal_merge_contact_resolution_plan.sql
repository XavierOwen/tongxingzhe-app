\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0129_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0129.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0129.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0129_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0129.example.test','other');
CREATE TEMP TABLE fixture_0129_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid,old_generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0129_pairs VALUES
 ('person','7f290000-0000-4000-8000-00000000000a','7f290000-0000-4000-8000-00000000000b',NULL,NULL),
 ('institution','7f290000-0000-4000-8000-00000000000c','7f290000-0000-4000-8000-00000000000d',NULL,NULL);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.id,c.workspace_id,p.kind,'0129 business values must stay private','+1 312 555 0129',c.app_user_id
FROM fixture_0129_context c CROSS JOIN fixture_0129_pairs p CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM fixture_0129_context c JOIN app_data.promotion_targets t USING(workspace_id);
DO $activate$
DECLARE c record; p record; preview uuid; old_generation uuid; fingerprint text;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0129_context;
 FOR p IN SELECT * FROM fixture_0129_pairs LOOP
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1(
   'https://synthetic-0129.example.test','owner',c.project_id,p.first_target,p.second_target);
  old_generation := app_private.activate_personal_target_merge_generation_v2(
   c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target);
  SELECT fact_fingerprint INTO STRICT fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(old_generation);
  PERFORM app_private.end_known_source_personal_target_merge_generation_v1(
   c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),old_generation,fingerprint);
  UPDATE fixture_0129_pairs SET old_generation_id = old_generation WHERE kind = p.kind;
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1(
   'https://synthetic-0129.example.test','owner',c.project_id,p.first_target,p.second_target);
  UPDATE fixture_0129_pairs SET generation_id = app_private.activate_personal_target_merge_generation_v2(
   c.app_user_id,c.project_id,gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target)
  WHERE kind = p.kind;
 END LOOP;
END $activate$;
DO $empty$
DECLARE c record; p record; original jsonb; document jsonb;
BEGIN
 SELECT * INTO STRICT c FROM fixture_0129_context;
 FOR p IN SELECT * FROM fixture_0129_pairs LOOP
  original := app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id);
  document := app_private.plan_unassigned_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id,
   original->'known_source_plan'->>'fact_fingerprint',original->>'pending_fingerprint','[]'::jsonb);
  IF document->'contacts' <> '[]'::jsonb OR document->'source_slots' <> '[]'::jsonb OR document->>'conflict_count' <> '0'
   OR document->'known_source_plan' IS DISTINCT FROM original->'known_source_plan'
   OR document->'pending_fingerprint' IS DISTINCT FROM original->'pending_fingerprint'
  THEN RAISE EXCEPTION '0129 empty assignments must produce an empty plan only with zero pending'; END IF;
 END LOOP;
END $empty$;
CREATE FUNCTION pg_temp.fixture_0129_submit(contact text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE result record;
BEGIN
 SELECT s.* INTO result FROM fixture_0129_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id,contact || '-submit',1,'contact.submit.v1','0129-device',contact,0,
  jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,
   'questionnaireVersionId',c.questionnaire_version_id,'reason','0129 reason','occurredAtUtc','2025-05-03T04:05:06Z','occurredTimeZone','UTC',
   'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
   'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) s;
 IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0129 setup rejected: %',row_to_json(result); END IF;
END $function$;
SELECT pg_temp.fixture_0129_submit(contact) FROM (VALUES('0129 A | "TEXT": 汉字'),('0129-a'),('0129-institution')) t(contact);
CREATE TEMP TABLE fixture_0129_pending ON COMMIT DROP AS
SELECT p.kind,t.contact,t.source_target_id,
 app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  gen_random_uuid(),p.generation_id,t.contact,1,NULL,t.consent,t.representative,t.entry) AS pending_fact_id
FROM fixture_0129_context c CROSS JOIN fixture_0129_pairs p JOIN (VALUES
 ('person','0129 A | "TEXT": 汉字','7f290000-0000-4000-8000-00000000000a'::uuid,'unknown',false,true),
 ('person','0129-a','7f290000-0000-4000-8000-00000000000b'::uuid,'refused',false,true),
 ('institution','0129-institution','7f290000-0000-4000-8000-00000000000c'::uuid,'not_applicable',false,false)
) t(kind,contact,source_target_id,consent,representative,entry) USING(kind);
CREATE TEMP TABLE fixture_0129_plans ON COMMIT DROP AS
SELECT p.kind,p.generation_id,
 app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id) AS original,
 (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',n.pending_fact_id,'source_target_id',n.source_target_id)
  ORDER BY n.pending_fact_id) FROM fixture_0129_pending n WHERE n.kind = p.kind) AS assignments
FROM fixture_0129_context c CROSS JOIN fixture_0129_pairs p;
CREATE FUNCTION pg_temp.fixture_0129_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; state jsonb := '{}'::jsonb;
BEGIN
 FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('app_data','app_private') AND c.relkind = 'r' ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM %I.%I r',relation.nspname,relation.relname) INTO rows;
  state := state || jsonb_build_object(relation.nspname || '.' || relation.relname,rows);
 END LOOP;
 RETURN state;
END $function$;
CREATE FUNCTION pg_temp.fixture_0129_read(kind text,mapping jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $function$
 SELECT app_private.plan_unassigned_personal_merge_contact_resolutions_v1(c.app_user_id,c.workspace_id,
  (SELECT project_id FROM app_data.user_current_projects WHERE app_user_id = c.app_user_id),p.generation_id,
  p.original->'known_source_plan'->>'fact_fingerprint',p.original->>'pending_fingerprint',coalesce($2,p.assignments))
 FROM fixture_0129_context c CROSS JOIN fixture_0129_plans p WHERE p.kind = $1
$function$;
CREATE FUNCTION pg_temp.fixture_0129_expect(expected text,command text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_0129_state(); actual text; detail text;
BEGIN
 BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE,detail = MESSAGE_TEXT; END;
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '0129 expected %, got % (%): %',expected,actual,detail,command; END IF;
 IF before_state IS DISTINCT FROM pg_temp.fixture_0129_state() THEN RAISE EXCEPTION '0129 rejected plan changed persisted state'; END IF;
END $function$;
CREATE FUNCTION pg_temp.fixture_0129_assert_shape(document jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE item jsonb; fact jsonb; link jsonb;
BEGIN
 IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(document) k) IS DISTINCT FROM
  ARRAY['conflict_count','contacts','contract_id','known_source_plan','pending_fingerprint','resolution_fingerprint','source_slots']
  OR document->>'contract_id' <> 'personal_merge_contact_resolution_plan_v1'
  OR document->>'resolution_fingerprint' !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION '0129 exact top-level metadata contract drift: %',document; END IF;
 IF document->'contacts' IS DISTINCT FROM (SELECT coalesce(jsonb_agg(value ORDER BY value->>'contact_id' COLLATE "C"),'[]'::jsonb) FROM jsonb_array_elements(document->'contacts'))
  OR document->'source_slots' IS DISTINCT FROM (SELECT coalesce(jsonb_agg(value ORDER BY value->>'contact_id' COLLATE "C",(value->>'source_target_id')::uuid),'[]'::jsonb) FROM jsonb_array_elements(document->'source_slots'))
 THEN RAISE EXCEPTION '0129 raw TEXT/C contact or source-slot order drift'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(document->'contacts') LOOP
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(item) k) IS DISTINCT FROM
   ARRAY['contact_id','current_revision_number','current_source_links','pending_facts','project_id']
  THEN RAISE EXCEPTION '0129 contact shape drift'; END IF;
  IF item->'pending_facts' IS DISTINCT FROM (SELECT jsonb_agg(value ORDER BY (value->>'revision_number')::integer,(value->>'pending_fact_id')::uuid) FROM jsonb_array_elements(item->'pending_facts'))
   OR item->'current_source_links' IS DISTINCT FROM (SELECT coalesce(jsonb_agg(value ORDER BY (value->>'source_target_id')::uuid),'[]'::jsonb) FROM jsonb_array_elements(item->'current_source_links'))
  THEN RAISE EXCEPTION '0129 per-contact pending/current-link order drift'; END IF;
  FOR fact IN SELECT value FROM jsonb_array_elements(item->'pending_facts') LOOP
   IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(fact) k) IS DISTINCT FROM
    ARRAY['is_current','pending_fact_id','revision_number','source_target_id'] THEN RAISE EXCEPTION '0129 pending shape drift'; END IF;
  END LOOP;
  FOR link IN SELECT value FROM jsonb_array_elements(item->'current_source_links') LOOP
   IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(link) k) IS DISTINCT FROM
    ARRAY['merge_generation_id','revision_number','source_target_id'] THEN RAISE EXCEPTION '0129 current link shape drift'; END IF;
  END LOOP;
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(document->'source_slots') LOOP
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(item) k) IS DISTINCT FROM
   ARRAY['candidate_count','contact_id','has_current_link','pending_fact_ids','requires_choice','source_target_id']
   OR (item->>'candidate_count')::integer <> jsonb_array_length(item->'pending_fact_ids') + (item->>'has_current_link')::boolean::integer
   OR (item->>'requires_choice')::boolean <> ((item->>'candidate_count')::integer > 1)
  THEN RAISE EXCEPTION '0129 source-slot shape/count drift'; END IF;
 END LOOP;
 IF (document->>'conflict_count')::integer <> (SELECT count(*) FROM jsonb_array_elements(document->'source_slots') s WHERE (s->>'requires_choice')::boolean)
 THEN RAISE EXCEPTION '0129 conflict count drift'; END IF;
END $function$;
CREATE TEMP TABLE fixture_0129_initial ON COMMIT DROP AS SELECT kind,pg_temp.fixture_0129_read(kind) AS document FROM fixture_0129_plans;
DO $baseline$
DECLARE p record; state jsonb := pg_temp.fixture_0129_state(); reordered jsonb;
BEGIN
 FOR p IN SELECT * FROM fixture_0129_plans LOOP
  PERFORM pg_temp.fixture_0129_assert_shape(pg_temp.fixture_0129_read(p.kind));
  IF pg_temp.fixture_0129_read(p.kind)->'known_source_plan' IS DISTINCT FROM p.original->'known_source_plan'
   OR pg_temp.fixture_0129_read(p.kind)->'pending_fingerprint' IS DISTINCT FROM p.original->'pending_fingerprint'
   OR pg_temp.fixture_0129_read(p.kind)->>'conflict_count' <> '0' THEN RAISE EXCEPTION '0129 original plan or no-conflict semantics drift'; END IF;
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',upper(value->>'pending_fact_id'),'source_target_id',upper(value->>'source_target_id')) ORDER BY ord DESC)
   INTO reordered FROM jsonb_array_elements(p.assignments) WITH ORDINALITY a(value,ord);
  IF pg_temp.fixture_0129_read(p.kind,reordered) IS DISTINCT FROM pg_temp.fixture_0129_read(p.kind)
  THEN RAISE EXCEPTION '0129 UUID case or mapping order changed canonical result'; END IF;
 END LOOP;
 IF (pg_temp.fixture_0129_read('person')->'contacts'->0->>'contact_id') <> '0129 A | "TEXT": 汉字'
  OR state IS DISTINCT FROM pg_temp.fixture_0129_state() THEN RAISE EXCEPTION '0129 raw TEXT/C order or readonly state drift'; END IF;
END $baseline$;
SELECT pg_temp.fixture_0129_expect('22023',format('SELECT pg_temp.fixture_0129_read(''person'',%L::jsonb)',value))
FROM (VALUES('null'),('{}'),('[null]'),('[1]'),('[{}]')) t(value);
SELECT pg_temp.fixture_0129_expect(expected,format('SELECT pg_temp.fixture_0129_read(''person'',%L::jsonb)',value))
FROM fixture_0129_plans CROSS JOIN LATERAL (VALUES
 ('22023',assignments || jsonb_build_array(assignments->0)),
 ('22023',jsonb_build_array((assignments->0) || '{"extra":true}'::jsonb,assignments->1)),
 ('22023',jsonb_build_array((assignments->0) - 'source_target_id',assignments->1)),
 ('22023',jsonb_build_array((assignments->0) || '{"pending_fact_id":4}'::jsonb,assignments->1)),
 ('22023',jsonb_build_array((assignments->0) || '{"source_target_id":"bad"}'::jsonb,assignments->1)),
 ('23505','[]'::jsonb),('23505',jsonb_build_array(assignments->0)),
 ('23505',assignments || jsonb_build_array(jsonb_build_object('pending_fact_id',gen_random_uuid(),'source_target_id','7f290000-0000-4000-8000-00000000000a'))),
 ('23505',jsonb_build_array((assignments->0) || jsonb_build_object('source_target_id','7f290000-0000-4000-8000-00000000000c'),assignments->1))
) t(expected,value) WHERE kind = 'person';
SELECT pg_temp.fixture_0129_expect(expected,format('SELECT app_private.plan_unassigned_personal_merge_contact_resolutions_v1(%L,%L,%L,%L,%L,%L,%L::jsonb)',
 CASE WHEN field = 'actor_null' THEN NULL WHEN field = 'other' THEN o.app_user_id ELSE c.app_user_id END,
 CASE WHEN field = 'workspace_null' THEN NULL ELSE c.workspace_id END,CASE WHEN field = 'project_null' THEN NULL ELSE c.project_id END,
 CASE WHEN field = 'generation_null' THEN NULL ELSE p.generation_id END,
 CASE WHEN field = 'known_null' THEN NULL WHEN field = 'known_bad' THEN 'bad' WHEN field = 'known_stale' THEN repeat('0',64) ELSE p.original->'known_source_plan'->>'fact_fingerprint' END,
 CASE WHEN field = 'pending_null' THEN NULL WHEN field = 'pending_bad' THEN 'bad' WHEN field = 'pending_stale' THEN repeat('0',64) ELSE p.original->>'pending_fingerprint' END,
 CASE WHEN field = 'assignments_null' THEN NULL ELSE p.assignments END))
FROM fixture_0129_context c CROSS JOIN fixture_0129_other o CROSS JOIN fixture_0129_plans p CROSS JOIN (VALUES
 ('actor_null','22023'),('workspace_null','22023'),('project_null','22023'),('generation_null','22023'),('known_null','22023'),
 ('known_bad','22023'),('pending_null','22023'),('pending_bad','22023'),('assignments_null','22023'),('known_stale','23505'),('pending_stale','23505'),('other','42501')) t(field,expected)
WHERE p.kind = 'person';

SAVEPOINT historical;
SELECT result_code FROM fixture_0129_context c CROSS JOIN LATERAL app_data.apply_contact_revise_v3(c.app_user_id,
 '0129-revise',1,'contact.revise.v1','0129-device','0129 A | "TEXT": 汉字',1,
 (SELECT snapshot FROM app_data.contact_revisions WHERE contact_id = '0129 A | "TEXT": 汉字' AND revision_number = 1)) s;
DO $movement$
DECLARE document jsonb := pg_temp.fixture_0129_read('person');
BEGIN
 PERFORM pg_temp.fixture_0129_assert_shape(document);
 IF document->>'resolution_fingerprint' = (SELECT i.document->>'resolution_fingerprint' FROM fixture_0129_initial i WHERE kind = 'person')
  OR document->'pending_fingerprint' IS DISTINCT FROM (SELECT original->'pending_fingerprint' FROM fixture_0129_plans WHERE kind = 'person')
  OR document->'known_source_plan' IS DISTINCT FROM (SELECT original->'known_source_plan' FROM fixture_0129_plans WHERE kind = 'person')
  OR document->'contacts'->0->'pending_facts'->0->>'is_current' <> 'false'
 THEN RAISE EXCEPTION '0129 historical revision/current-revision fingerprint binding drift'; END IF;
END $movement$;
SELECT pg_temp.fixture_0129_expect('23505',format('SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
 c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,p.original->'known_source_plan'->>'fact_fingerprint',p.original->>'pending_fingerprint',p.assignments))
FROM fixture_0129_context c CROSS JOIN fixture_0129_plans p WHERE kind = 'person';
INSERT INTO fixture_0129_pending
SELECT p.kind,'0129 A | "TEXT": 汉字',p.first_target,app_private.stage_unassigned_personal_merge_contact_v1(
 c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,'0129 A | "TEXT": 汉字',2,2,'yes',false,true)
FROM fixture_0129_context c CROSS JOIN fixture_0129_pairs p WHERE kind = 'person';
UPDATE fixture_0129_plans p SET original = app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id),
 assignments = (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',n.pending_fact_id,'source_target_id',n.source_target_id) ORDER BY n.pending_fact_id)
 FROM fixture_0129_pending n WHERE n.kind = p.kind) FROM fixture_0129_context c WHERE kind = 'person';
DO $multiple$
DECLARE document jsonb := pg_temp.fixture_0129_read('person'); different jsonb;
BEGIN
 PERFORM pg_temp.fixture_0129_assert_shape(document);
 IF document->>'conflict_count' <> '1' OR jsonb_array_length(document->'contacts'->0->'pending_facts') <> 2
  OR document->'contacts'->0->'pending_facts'->0->>'revision_number' <> '1'
  OR document->'contacts'->0->'pending_facts'->1->>'revision_number' <> '2'
 THEN RAISE EXCEPTION '0129 multiple historical candidates or order drift'; END IF;
 SELECT jsonb_agg(CASE WHEN value->>'pending_fact_id' = (SELECT pending_fact_id::text FROM fixture_0129_pending WHERE contact = '0129 A | "TEXT": 汉字' ORDER BY pending_fact_id DESC LIMIT 1)
  THEN value || jsonb_build_object('source_target_id','7f290000-0000-4000-8000-00000000000b') ELSE value END) INTO different
 FROM fixture_0129_plans p CROSS JOIN LATERAL jsonb_array_elements(p.assignments) WHERE kind = 'person';
 IF pg_temp.fixture_0129_read('person',different)->>'conflict_count' <> '0'
  OR pg_temp.fixture_0129_read('person',different)->>'resolution_fingerprint' = document->>'resolution_fingerprint'
 THEN RAISE EXCEPTION '0129 chosen mapping does not control slot grouping/fingerprint'; END IF;
END $multiple$;
SELECT pg_temp.fixture_0129_expect('23505',format('SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(%L,%L,%L,%L,%L,%L,%L,%L::jsonb)',
 c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,p.original->'known_source_plan'->>'fact_fingerprint',p.original->>'pending_fingerprint',p.assignments))
FROM fixture_0129_context c CROSS JOIN fixture_0129_plans p WHERE kind = 'person';
ROLLBACK TO SAVEPOINT historical;
RELEASE SAVEPOINT historical;

SAVEPOINT current_links;
ALTER TABLE app_data.contact_target_links DISABLE TRIGGER contact_target_links_bind_merge_generation;
INSERT INTO app_data.contact_target_links(contact_id,revision_number,promotion_target_id,response_level,follow_up_consent,institution_representative_confirmed,confirmed_project_entry,merge_generation_id)
SELECT '0129 A | "TEXT": 汉字',1,first_target,NULL::integer,'unknown',false,true,NULL::uuid FROM fixture_0129_pairs WHERE kind = 'person'
UNION ALL SELECT '0129 A | "TEXT": 汉字',1,second_target,NULL,'refused',false,true,old_generation_id FROM fixture_0129_pairs WHERE kind = 'person';
ALTER TABLE app_data.contact_target_links ENABLE TRIGGER contact_target_links_bind_merge_generation;
UPDATE fixture_0129_plans p SET original = app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id)
FROM fixture_0129_context c WHERE kind = 'person';
DO $links$
DECLARE document jsonb := pg_temp.fixture_0129_read('person');
BEGIN
 PERFORM pg_temp.fixture_0129_assert_shape(document);
 IF document->>'conflict_count' <> '1' OR jsonb_array_length(document->'source_slots') <> 3
  OR jsonb_array_length(document->'contacts'->0->'current_source_links') <> 2
  OR document->'contacts'->0->'current_source_links'->0->'merge_generation_id' <> 'null'::jsonb
  OR document->'contacts'->0->'current_source_links'->1->>'merge_generation_id' IS DISTINCT FROM
   (SELECT old_generation_id::text FROM fixture_0129_pairs WHERE kind = 'person')
  OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(document->'source_slots') s WHERE s->>'contact_id' = '0129 A | "TEXT": 汉字'
   AND s->>'source_target_id' = '7f290000-0000-4000-8000-00000000000b' AND s->>'candidate_count' = '1' AND s->>'has_current_link' = 'true' AND s->>'requires_choice' = 'false')
 THEN RAISE EXCEPTION '0129 same-source conflict, other-source preserved slot or original NULL/old binding drift'; END IF;
END $links$;
ROLLBACK TO SAVEPOINT current_links;
RELEASE SAVEPOINT current_links;

CREATE TEMP TABLE fixture_0129_project_b ON COMMIT DROP AS
SELECT * FROM app_data.create_personal_project_context('https://synthetic-0129.example.test','owner','0129 project B');
SELECT count(*) FROM fixture_0129_project_b c CROSS JOIN LATERAL app_data.select_personal_project_context('https://synthetic-0129.example.test','owner',c.project_id) s;
DO $project_switch$
BEGIN
 IF pg_temp.fixture_0129_read('person')->'contacts' IS DISTINCT FROM (SELECT document->'contacts' FROM fixture_0129_initial WHERE kind = 'person')
  OR pg_temp.fixture_0129_read('person')->>'resolution_fingerprint' = (SELECT document->>'resolution_fingerprint' FROM fixture_0129_initial WHERE kind = 'person')
 THEN RAISE EXCEPTION '0129 project A pending/current B metadata or fingerprint drift'; END IF;
END $project_switch$;
SELECT result_code FROM fixture_0129_project_b c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
 c.app_user_id,'0129-project-b-submit',1,'contact.submit.v1','0129-device','0129-project-b-contact',0,
 jsonb_build_object('contactId','0129-project-b-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
  'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc','2025-05-03T04:05:06Z','occurredTimeZone','UTC',
  'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
  'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) s;
INSERT INTO fixture_0129_pending
SELECT p.kind,'0129-project-b-contact',p.second_target,app_private.stage_unassigned_personal_merge_contact_v1(
 c.app_user_id,c.workspace_id,c.project_id,gen_random_uuid(),p.generation_id,'0129-project-b-contact',1,NULL,'unknown',false,true)
FROM fixture_0129_project_b c CROSS JOIN fixture_0129_pairs p WHERE kind = 'person';
UPDATE fixture_0129_plans p SET original = app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id),
 assignments = (SELECT jsonb_agg(jsonb_build_object('pending_fact_id',n.pending_fact_id,'source_target_id',n.source_target_id) ORDER BY n.pending_fact_id)
 FROM fixture_0129_pending n WHERE n.kind = p.kind) FROM fixture_0129_project_b c WHERE kind = 'person';
DO $cross_project_complete$
DECLARE document jsonb := pg_temp.fixture_0129_read('person');
BEGIN
 PERFORM pg_temp.fixture_0129_assert_shape(document);
 IF jsonb_array_length(document->'contacts') <> 3 OR document->>'conflict_count' <> '0'
  OR (SELECT count(*) FROM jsonb_array_elements(document->'contacts') item WHERE item->>'project_id' = (SELECT project_id::text FROM fixture_0129_context)) <> 2
  OR (SELECT count(*) FROM jsonb_array_elements(document->'contacts') item WHERE item->>'project_id' = (SELECT project_id::text FROM fixture_0129_project_b)) <> 1
 THEN RAISE EXCEPTION '0129 current B plan omitted or duplicated project A/B pending facts'; END IF;
END $cross_project_complete$;
SELECT pg_temp.fixture_0129_expect('23505',format('SELECT pg_temp.fixture_0129_read(''person'',%L::jsonb)',
 (SELECT jsonb_agg(a.value) FROM jsonb_array_elements(p.assignments) a
  WHERE a.value->>'pending_fact_id' <> (SELECT pending_fact_id::text FROM fixture_0129_pending WHERE contact = '0129-project-b-contact'))))
FROM fixture_0129_plans p WHERE kind = 'person';
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only = on;
DO $readonly$
DECLARE state jsonb := pg_temp.fixture_0129_state();
BEGIN
 IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION '0129 true READ ONLY not enabled'; END IF;
 PERFORM pg_temp.fixture_0129_assert_shape(pg_temp.fixture_0129_read(kind)) FROM fixture_0129_plans;
 IF state IS DISTINCT FROM pg_temp.fixture_0129_state() THEN RAISE EXCEPTION '0129 readonly plan changed persisted state'; END IF;
END $readonly$;
ROLLBACK TO SAVEPOINT readonly_scope;
RELEASE SAVEPOINT readonly_scope;
ROLLBACK;
