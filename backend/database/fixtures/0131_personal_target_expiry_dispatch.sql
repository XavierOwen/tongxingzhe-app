\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0131_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0131.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0131.example.test','owner') WHERE is_current;

CREATE TEMP TABLE fixture_0131_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0131_pairs VALUES
 ('person','7f310000-0000-4000-8000-000000000001','7f310000-0000-4000-8000-000000000002',NULL),
 ('person','7f310000-0000-4000-8000-000000000003','7f310000-0000-4000-8000-000000000004',NULL),
 ('institution','7f310000-0000-4000-8000-000000000005','7f310000-0000-4000-8000-000000000006',NULL);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.target_id,c.workspace_id,p.kind,'0131 synthetic source ' || t.target_id,'+1 773 555 0131',c.app_user_id
FROM fixture_0131_context c CROSS JOIN fixture_0131_pairs p
CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id)
SELECT '7f310000-0000-4000-8000-000000000007',workspace_id,'person','0131 synthetic ordinary target',app_user_id
FROM fixture_0131_context;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id)
SELECT '7f310000-0000-4000-8000-000000000009',workspace_id,'person','0131 synthetic due-drift target',app_user_id
FROM fixture_0131_context;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0131_context c WHERE t.workspace_id = c.workspace_id;

CREATE TEMP TABLE fixture_0131_activated ON COMMIT DROP AS
SELECT p.first_target,p.second_target,
 app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview.preview_id,
   p.first_target,p.second_target,p.first_target,p.second_target) AS generation_id
FROM fixture_0131_pairs p CROSS JOIN fixture_0131_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://synthetic-0131.example.test','owner',c.project_id,p.first_target,p.second_target) preview;
UPDATE fixture_0131_pairs p SET generation_id = a.generation_id FROM fixture_0131_activated a
WHERE p.first_target = a.first_target;

INSERT INTO app_data.questionnaire_questions(questionnaire_version_id,question_id,position,prompt,question_type,is_required,allow_unknown,allow_refused,allow_not_applicable)
SELECT questionnaire_version_id,'expiry_answer',1,'0131 synthetic answer','boolean',false,true,true,true FROM fixture_0131_context;
CREATE TEMP TABLE fixture_0131_pending ON COMMIT DROP AS
WITH submitted AS (
 SELECT c.app_user_id,c.workspace_id,c.project_id,c.questionnaire_version_id,
   app_data.apply_contact_submit_v3(c.app_user_id,'0131-pending-submit',1,'contact.submit.v1','0131-device','0131-pending-contact',0,
    jsonb_build_object('contactId','0131-pending-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
     'questionnaireVersionId',c.questionnaire_version_id,'reason','0131 fixture','occurredAtUtc',clock_timestamp(),
     'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
     'reachCount',1,'interestLevel',2,'answers',jsonb_build_array(jsonb_build_object('questionId','expiry_answer','state','answered','type','boolean','value',true)),
     'targetLinks','[]'::jsonb)) AS result
 FROM fixture_0131_context c
)
SELECT app_private.stage_unassigned_personal_merge_contact_v1(s.app_user_id,s.workspace_id,s.project_id,'7f310000-0000-4000-8000-000000000090',p.generation_id,
 '0131-pending-contact',1,CASE WHEN p.kind='person' THEN 2 ELSE NULL END,
 CASE WHEN p.kind='person' THEN 'yes' ELSE 'not_applicable' END,p.kind='institution',true) AS pending_fact_id,p.generation_id
FROM submitted s JOIN fixture_0131_pairs p ON p.generation_id = (SELECT generation_id FROM fixture_0131_pairs ORDER BY generation_id OFFSET 1 LIMIT 1);

-- One endpoint of the first pair is due; the later endpoint is intentionally not due.
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id IN ('7f310000-0000-4000-8000-000000000001','7f310000-0000-4000-8000-000000000002',
 '7f310000-0000-4000-8000-000000000003','7f310000-0000-4000-8000-000000000004',
 '7f310000-0000-4000-8000-000000000005','7f310000-0000-4000-8000-000000000006',
 '7f310000-0000-4000-8000-000000000007','7f310000-0000-4000-8000-000000000009');
WITH earliest AS (SELECT first_target,second_target FROM fixture_0131_pairs ORDER BY generation_id LIMIT 1)
UPDATE app_data.promotion_targets t SET created_at = CASE WHEN t.promotion_target_id = e.first_target
 THEN clock_timestamp() - interval '14 months' ELSE clock_timestamp() END
FROM earliest e WHERE t.promotion_target_id IN (e.first_target,e.second_target);

CREATE FUNCTION pg_temp.fixture_0131_state() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; statements text; state jsonb;
BEGIN
 FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' ORDER BY n.nspname,c.relname LOOP
  statements := concat_ws(' UNION ALL ',statements,format('SELECT %L::text AS relation_name,coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) AS contents FROM %I.%I r',
      relation.nspname || '.' || relation.relname,relation.nspname,relation.relname));
 END LOOP;
 IF statements IS NULL THEN RETURN '{}'::jsonb; END IF;
 EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM (' || statements || ') snapshots' INTO state;
 RETURN state;
END $function$;
CREATE FUNCTION pg_temp.fixture_0131_dispatch(request uuid,project uuid DEFAULT NULL) RETURNS TABLE(unit_kind text,unit_id uuid,outcome text,failure_code text,failure_sqlstate text,processed_at_utc timestamptz)
LANGUAGE sql AS $function$
 SELECT d.* FROM fixture_0131_context c CROSS JOIN LATERAL app_private.dispatch_assigned_personal_target_expiry_v1(
   c.app_user_id,c.workspace_id,coalesce($2,c.project_id),$1) d
$function$;
CREATE FUNCTION pg_temp.fixture_0131_expect(expected text,request uuid,project uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_0131_state(); actual text;
BEGIN
 BEGIN PERFORM * FROM pg_temp.fixture_0131_dispatch(request,project);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE; END;
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '0131 expected SQLSTATE %, got %',expected,actual; END IF;
 IF before_state IS DISTINCT FROM pg_temp.fixture_0131_state() THEN RAISE EXCEPTION '0131 rejected dispatcher call changed persisted state'; END IF;
END $function$;

CREATE FUNCTION pg_temp.fixture_0131_suppress_pending_receipt() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.pending_fact_id = (SELECT pending_fact_id FROM fixture_0131_pending) THEN RETURN NULL; END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0131_suppress_pending_receipt BEFORE INSERT ON app_private.personal_merge_unassigned_contact_purges_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0131_suppress_pending_receipt();
CREATE FUNCTION pg_temp.fixture_0131_fail_later_generation_endpoint() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.promotion_target_id = (SELECT second_target FROM fixture_0131_pairs ORDER BY generation_id DESC LIMIT 1)
  AND NEW.status = 'anonymized' THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='0131 synthetic second-endpoint rejection';
 END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0131_fail_second_endpoint BEFORE UPDATE ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0131_fail_later_generation_endpoint();
CREATE FUNCTION pg_temp.fixture_0131_make_later_candidate_not_due() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.promotion_target_id = (SELECT first_target FROM fixture_0131_pairs ORDER BY generation_id LIMIT 1)
  AND NEW.status = 'anonymized' THEN
  UPDATE app_data.promotion_targets SET created_at=clock_timestamp()
   WHERE promotion_target_id='7f310000-0000-4000-8000-000000000009';
 END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0131_change_later_due BEFORE UPDATE ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0131_make_later_candidate_not_due();

CREATE TEMP TABLE fixture_0131_first_result ON COMMIT DROP AS
SELECT * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000100');
DROP TRIGGER fixture_0131_suppress_pending_receipt ON app_private.personal_merge_unassigned_contact_purges_v1;
DROP TRIGGER fixture_0131_fail_second_endpoint ON app_data.promotion_targets;
DROP TRIGGER fixture_0131_change_later_due ON app_data.promotion_targets;
DO $batch_assertions$
DECLARE first_generation uuid; earliest_first_target uuid; earliest_second_target uuid; pending_generation uuid; failed_generation uuid; ordinary_target uuid;
BEGIN
 SELECT generation_id,fixture_0131_pairs.first_target,fixture_0131_pairs.second_target INTO STRICT first_generation,earliest_first_target,earliest_second_target
  FROM fixture_0131_pairs ORDER BY generation_id LIMIT 1;
 SELECT generation_id INTO STRICT pending_generation FROM fixture_0131_pending;
 SELECT generation_id INTO STRICT failed_generation FROM fixture_0131_pairs ORDER BY generation_id DESC LIMIT 1;
 SELECT promotion_target_id INTO STRICT ordinary_target FROM app_data.promotion_targets WHERE promotion_target_id='7f310000-0000-4000-8000-000000000007';
 IF (SELECT count(*) FROM fixture_0131_first_result) <> 5
  OR (SELECT array_agg(unit_kind ORDER BY unit_kind,unit_id) FROM fixture_0131_first_result)
    IS DISTINCT FROM ARRAY['generation','generation','generation','target','target']
  OR (SELECT outcome FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=first_generation) IS DISTINCT FROM 'expired'
  OR (SELECT processed_at_utc IS NULL FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=first_generation)
  OR (SELECT outcome FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=pending_generation) IS DISTINCT FROM 'failed'
  OR (SELECT failure_code FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=pending_generation) IS DISTINCT FROM 'integrity_failure'
  OR (SELECT failure_sqlstate FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=pending_generation) IS DISTINCT FROM '55000'
  OR (SELECT processed_at_utc IS NOT NULL FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=pending_generation)
  OR (SELECT outcome FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=failed_generation) IS DISTINCT FROM 'failed'
  OR (SELECT failure_code FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=failed_generation) IS DISTINCT FROM 'integrity_failure'
  OR (SELECT failure_sqlstate FROM fixture_0131_first_result WHERE unit_kind='generation' AND unit_id=failed_generation) IS DISTINCT FROM '23514'
  OR (SELECT outcome FROM fixture_0131_first_result WHERE unit_kind='target' AND unit_id=ordinary_target) IS DISTINCT FROM 'expired'
  OR (SELECT processed_at_utc IS NULL FROM fixture_0131_first_result WHERE unit_kind='target' AND unit_id=ordinary_target)
  OR (SELECT outcome FROM fixture_0131_first_result WHERE unit_kind='target' AND unit_id='7f310000-0000-4000-8000-000000000009') IS DISTINCT FROM 'skipped'
  OR (SELECT failure_code FROM fixture_0131_first_result WHERE unit_kind='target' AND unit_id='7f310000-0000-4000-8000-000000000009') IS DISTINCT FROM 'not_due'
  OR (SELECT failure_sqlstate IS NOT NULL OR processed_at_utc IS NOT NULL FROM fixture_0131_first_result
       WHERE unit_kind='target' AND unit_id='7f310000-0000-4000-8000-000000000009')
 THEN RAISE EXCEPTION '0131 mixed batch result ordering or per-unit outcome drift: %',
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.unit_kind,r.unit_id) FROM fixture_0131_first_result r); END IF;
 IF NOT EXISTS (SELECT 1 FROM app_private.personal_target_expiry_dispatch_requests_v1 r CROSS JOIN fixture_0131_context c
   WHERE r.actor_app_user_id=c.app_user_id AND r.request_id='7f310000-0000-4000-8000-000000000100'
    AND r.workspace_id=c.workspace_id AND r.project_id=c.project_id AND r.unit_count=5
    AND r.expired_count=2 AND r.skipped_count=1 AND r.failed_count=2)
  OR (SELECT array_agg(unit_ordinal ORDER BY unit_ordinal) FROM app_private.personal_target_expiry_dispatch_units_v1
       WHERE request_id='7f310000-0000-4000-8000-000000000100') IS DISTINCT FROM ARRAY[1,2,3,4,5]
  OR EXISTS (SELECT 1 FROM app_private.personal_target_expiry_dispatch_units_v1 u CROSS JOIN fixture_0131_context c
    WHERE u.actor_app_user_id=c.app_user_id AND u.request_id='7f310000-0000-4000-8000-000000000100'
      AND u.child_request_id <> md5('personal-target-expiry-v1:' || c.app_user_id::text || ':' || u.request_id::text || ':'
        || CASE WHEN u.generation_id IS NULL THEN 'target' ELSE 'generation' END || ':'
        || coalesce(u.generation_id,u.promotion_target_id)::text)::uuid)
 THEN RAISE EXCEPTION '0131 parent counts, ordinals or deterministic opaque child IDs drift'; END IF;
 IF (SELECT count(*) FROM app_data.promotion_targets WHERE promotion_target_id IN (earliest_first_target,earliest_second_target) AND status='anonymized') <> 2
  OR (SELECT status FROM app_data.promotion_targets WHERE promotion_target_id='7f310000-0000-4000-8000-000000000007') IS DISTINCT FROM 'anonymized'
  OR EXISTS (SELECT 1 FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0131_pending))
  OR NOT EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0131_pending))
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=pending_generation)
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id=failed_generation)
  OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id IN (pending_generation,failed_generation))
  OR EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events WHERE promotion_target_id IN
    (SELECT p.first_target FROM fixture_0131_pairs p WHERE p.generation_id IN (pending_generation,failed_generation))
    OR promotion_target_id IN (SELECT p.second_target FROM fixture_0131_pairs p WHERE p.generation_id IN (pending_generation,failed_generation)))
  OR EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events WHERE promotion_target_id='7f310000-0000-4000-8000-000000000009')
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 e
    WHERE e.generation_id=first_generation AND e.request_id=(SELECT child_request_id FROM app_private.personal_target_expiry_dispatch_units_v1
      WHERE request_id='7f310000-0000-4000-8000-000000000100' AND generation_id=first_generation)
      AND e.operation='personal_target_known_source_merge_expire' AND e.reason='retention_expired' AND e.outcome='ended')
  OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events e
    JOIN app_private.personal_target_expiry_dispatch_units_v1 u ON u.promotion_target_id=e.promotion_target_id
    WHERE u.request_id='7f310000-0000-4000-8000-000000000100' AND u.generation_id IS NULL
      AND e.actor_app_user_id=(SELECT app_user_id FROM fixture_0131_context) AND e.event_type='anonymized'
      AND e.mutation_id='owner-expiry-v1:' || u.child_request_id::text AND e.reason='retention_expired')
  OR (SELECT min(app_data.promotion_target_review_due_at(promotion_target_id)) FROM app_data.promotion_targets
      WHERE promotion_target_id IN (earliest_first_target,earliest_second_target))
      > (SELECT ended_at_utc FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id=first_generation)
 THEN RAISE EXCEPTION '0131 unit rollback, earlier-endpoint pair due, or payload preservation drift'; END IF;
END $batch_assertions$;

CREATE TEMP TABLE fixture_0131_after_success ON COMMIT DROP AS SELECT pg_temp.fixture_0131_state() AS state;
CREATE TEMP TABLE fixture_0131_replay ON COMMIT DROP AS
SELECT * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000100');
DO $replay$
BEGIN
 IF (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.unit_kind,r.unit_id) FROM fixture_0131_replay r)
    IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.unit_kind,r.unit_id) FROM fixture_0131_first_result r)
  OR pg_temp.fixture_0131_state() IS DISTINCT FROM (SELECT state FROM fixture_0131_after_success)
 THEN RAISE EXCEPTION '0131 exact replay changed the complete result or state'; END IF;
END $replay$;
CREATE TEMP TABLE fixture_0131_alt_project ON COMMIT DROP AS
SELECT * FROM app_data.create_personal_project_context('https://synthetic-0131.example.test','owner','0131 context drift project');
SELECT count(*) FROM fixture_0131_alt_project c CROSS JOIN LATERAL app_data.select_personal_project_context(
 'https://synthetic-0131.example.test','owner',c.project_id) p;
SELECT pg_temp.fixture_0131_expect('23505','7f310000-0000-4000-8000-000000000100',(SELECT project_id FROM fixture_0131_alt_project));
SELECT count(*) FROM fixture_0131_context c CROSS JOIN LATERAL app_data.select_personal_project_context(
 'https://synthetic-0131.example.test','owner',c.project_id) p;

-- A failed pair is retried only under a new parent request. Its old receipts remain immutable.
CREATE TEMP TABLE fixture_0131_retry ON COMMIT DROP AS
SELECT * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000101');
DO $retry$
BEGIN
 IF EXISTS (SELECT 1 FROM fixture_0131_retry WHERE outcome='failed')
  OR (SELECT count(*) FROM fixture_0131_retry) <> 2
  OR EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0131_pending))
  OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id IN
    (SELECT generation_id FROM fixture_0131_pairs WHERE generation_id IN (SELECT generation_id FROM fixture_0131_retry WHERE unit_kind='generation')))
  OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0131_pending)) <> 1
  OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id=(SELECT pending_fact_id FROM fixture_0131_pending)) <> 1
 THEN RAISE EXCEPTION '0131 new request did not retry only the previously failed units'; END IF;
END $retry$;

-- Add a due target after the first request has fixed its candidate set; only a new request sees it.
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,created_by_app_user_id,created_at)
SELECT '7f310000-0000-4000-8000-000000000008',workspace_id,'person','0131 later request target',app_user_id,clock_timestamp()-interval '14 months' FROM fixture_0131_context;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT '7f310000-0000-4000-8000-000000000008','7f310000-0000-4000-8000-000000000008',app_user_id,app_user_id FROM fixture_0131_context;
CREATE TEMP TABLE fixture_0131_later ON COMMIT DROP AS SELECT * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000102');
DO $later$
BEGIN
 IF (SELECT count(*) FROM fixture_0131_later) <> 1 OR NOT EXISTS (SELECT 1 FROM fixture_0131_later WHERE unit_kind='target'
   AND unit_id='7f310000-0000-4000-8000-000000000008' AND outcome='expired' AND processed_at_utc IS NOT NULL)
 THEN RAISE EXCEPTION '0131 later request did not select the newly due target'; END IF;
END $later$;
CREATE TEMP TABLE fixture_0131_empty ON COMMIT DROP AS SELECT * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000103');
CREATE TEMP TABLE fixture_0131_empty_replay ON COMMIT DROP AS SELECT * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000103');
DO $empty$
BEGIN
 IF (SELECT count(*) FROM fixture_0131_empty) <> 0 OR (SELECT count(*) FROM fixture_0131_empty_replay) <> 0
  OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_expiry_dispatch_requests_v1 WHERE request_id='7f310000-0000-4000-8000-000000000103' AND unit_count=0 AND expired_count=0 AND skipped_count=0 AND failed_count=0)
 THEN RAISE EXCEPTION '0131 empty batch receipt/replay drift'; END IF;
END $empty$;

-- A genuine deadlock-class failure must escape the per-unit handler and roll back earlier units too.
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.target_id,c.workspace_id,'person','0131 deadlock source','+1 773 555 0131',c.app_user_id FROM fixture_0131_context c CROSS JOIN (VALUES
 ('7f310000-0000-4000-8000-000000000011'::uuid),('7f310000-0000-4000-8000-000000000012'::uuid),
 ('7f310000-0000-4000-8000-000000000013'::uuid),('7f310000-0000-4000-8000-000000000014'::uuid)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id FROM app_data.promotion_targets t CROSS JOIN fixture_0131_context c
WHERE t.promotion_target_id IN ('7f310000-0000-4000-8000-000000000011','7f310000-0000-4000-8000-000000000012','7f310000-0000-4000-8000-000000000013','7f310000-0000-4000-8000-000000000014');
INSERT INTO fixture_0131_pairs(kind,first_target,second_target,generation_id)
SELECT 'person',t.first_target,t.second_target,app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview.preview_id,
 t.first_target,t.second_target,t.first_target,t.second_target)
FROM fixture_0131_context c CROSS JOIN (VALUES
 ('7f310000-0000-4000-8000-000000000011'::uuid,'7f310000-0000-4000-8000-000000000012'::uuid),
 ('7f310000-0000-4000-8000-000000000013'::uuid,'7f310000-0000-4000-8000-000000000014'::uuid)) t(first_target,second_target)
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1('https://synthetic-0131.example.test','owner',c.project_id,t.first_target,t.second_target) preview;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months'
WHERE promotion_target_id IN ('7f310000-0000-4000-8000-000000000011','7f310000-0000-4000-8000-000000000012','7f310000-0000-4000-8000-000000000013','7f310000-0000-4000-8000-000000000014');
CREATE TEMP TABLE fixture_0131_deadlock_order ON COMMIT DROP AS
SELECT (array_agg(generation_id ORDER BY generation_id))[1] AS first_generation,
 (array_agg(generation_id ORDER BY generation_id))[2] AS failing_generation FROM fixture_0131_pairs
WHERE first_target IN ('7f310000-0000-4000-8000-000000000011','7f310000-0000-4000-8000-000000000013');
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months'
WHERE promotion_target_id IN (SELECT p.first_target FROM fixture_0131_pairs p JOIN fixture_0131_deadlock_order d ON p.generation_id IN (d.first_generation,d.failing_generation)
 UNION SELECT p.second_target FROM fixture_0131_pairs p JOIN fixture_0131_deadlock_order d ON p.generation_id IN (d.first_generation,d.failing_generation));
CREATE TEMP TABLE fixture_0131_deadlock_before ON COMMIT DROP AS SELECT pg_temp.fixture_0131_state() AS state;
CREATE TEMP TABLE fixture_0131_escaping_state(sqlstate text) ON COMMIT DROP;
INSERT INTO fixture_0131_escaping_state VALUES ('40P01');
CREATE FUNCTION pg_temp.fixture_0131_raise_deadlock() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE injected_state text;
BEGIN
 IF NEW.promotion_target_id=(SELECT second_target FROM fixture_0131_pairs WHERE generation_id=(SELECT failing_generation FROM fixture_0131_deadlock_order))
  AND NEW.status='anonymized' THEN
  SELECT sqlstate INTO STRICT injected_state FROM fixture_0131_escaping_state;
  RAISE EXCEPTION USING ERRCODE=injected_state,MESSAGE='0131 synthetic escaping failure';
 END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0131_deadlock BEFORE UPDATE ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0131_raise_deadlock();
DO $deadlock$
DECLARE actual text; injected_state text;
BEGIN
 IF (SELECT first_generation=failing_generation OR first_generation IS NULL OR failing_generation IS NULL FROM fixture_0131_deadlock_order)
 THEN RAISE EXCEPTION '0131 deadlock fixture requires an earlier successful generation unit'; END IF;
 FOREACH injected_state IN ARRAY ARRAY['40P01','55006','P0001','57014'] LOOP
  UPDATE fixture_0131_escaping_state SET sqlstate=injected_state;
  actual := NULL;
  BEGIN PERFORM * FROM pg_temp.fixture_0131_dispatch(CASE injected_state
    WHEN '40P01' THEN '7f310000-0000-4000-8000-000000000104'::uuid
    WHEN '55006' THEN '7f310000-0000-4000-8000-000000000105'::uuid
    WHEN 'P0001' THEN '7f310000-0000-4000-8000-000000000106'::uuid
    ELSE '7f310000-0000-4000-8000-000000000107'::uuid END);
  EXCEPTION WHEN SQLSTATE '57014' THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE;
    WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
  IF actual IS DISTINCT FROM injected_state THEN RAISE EXCEPTION '0131 escaping SQLSTATE % was swallowed/reclassified as %',injected_state,actual; END IF;
  IF pg_temp.fixture_0131_state() IS DISTINCT FROM (SELECT state FROM fixture_0131_deadlock_before)
  THEN RAISE EXCEPTION '0131 batch did not roll back prior generation after %',injected_state; END IF;
 END LOOP;
END $deadlock$;
DROP TRIGGER fixture_0131_deadlock ON app_data.promotion_targets;
CREATE FUNCTION pg_temp.fixture_0131_suppress_dispatch_unit() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN IF NEW.unit_ordinal=2 THEN RETURN NULL; END IF; RETURN NEW; END $function$;
CREATE TRIGGER fixture_0131_suppress_unit BEFORE INSERT ON app_private.personal_target_expiry_dispatch_units_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0131_suppress_dispatch_unit();
DO $receipt_failure$
DECLARE actual text; before_state jsonb := pg_temp.fixture_0131_state();
BEGIN
 BEGIN PERFORM * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000108');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
 IF actual IS DISTINCT FROM '55000' OR pg_temp.fixture_0131_state() IS DISTINCT FROM before_state
 THEN RAISE EXCEPTION '0131 dispatcher receipt failure must abort and roll back all successful units, got %',actual; END IF;
END $receipt_failure$;
DROP TRIGGER fixture_0131_suppress_unit ON app_private.personal_target_expiry_dispatch_units_v1;
CREATE FUNCTION pg_temp.fixture_0131_revoke_owner() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
 IF NEW.promotion_target_id=(SELECT second_target FROM fixture_0131_pairs WHERE generation_id=(SELECT failing_generation FROM fixture_0131_deadlock_order))
  AND NEW.status='anonymized' THEN
  UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id=(SELECT app_user_id FROM fixture_0131_context);
 END IF;
 RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0131_revoke_during_unit BEFORE UPDATE ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0131_revoke_owner();
DO $revocation$
DECLARE actual text; before_state jsonb := pg_temp.fixture_0131_state();
BEGIN
 BEGIN PERFORM * FROM pg_temp.fixture_0131_dispatch('7f310000-0000-4000-8000-000000000109');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
 IF actual IS DISTINCT FROM '42501' OR pg_temp.fixture_0131_state() IS DISTINCT FROM before_state
 THEN RAISE EXCEPTION '0131 whole-call owner revocation must abort and roll back prior units, got %',actual; END IF;
END $revocation$;
DROP TRIGGER fixture_0131_revoke_during_unit ON app_data.promotion_targets;

DO $metadata_contract$
DECLARE allowed text[] := ARRAY['actor_app_user_id','request_id','workspace_id','project_id','selected_at_utc','completed_at_utc','unit_count','expired_count','skipped_count','failed_count'];
BEGIN
 IF has_table_privilege('tongxingzhe_runtime','app_private.personal_target_expiry_dispatch_requests_v1','SELECT')
  OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='app_private.personal_target_expiry_dispatch_requests_v1'::regclass
    AND tgname LIKE '%immutable%' AND NOT tgisinternal)
  OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='app_private' AND table_name='personal_target_expiry_dispatch_requests_v1'
    AND column_name NOT IN (SELECT unnest(allowed)))
  OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='app_private' AND table_name='personal_target_expiry_dispatch_units_v1'
    AND column_name ~* '(name|phone|email|address|answer|payload|summary|message|detail|fingerprint|hash)')
  OR has_function_privilege('tongxingzhe_runtime','app_private.dispatch_assigned_personal_target_expiry_v1(uuid,uuid,uuid,uuid)','EXECUTE')
  OR EXISTS (SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl
    WHERE c.oid IN ('app_private.personal_target_expiry_dispatch_requests_v1'::regclass,'app_private.personal_target_expiry_dispatch_units_v1'::regclass)
      AND acl.grantee=0)
  OR EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    WHERE p.oid='app_private.dispatch_assigned_personal_target_expiry_v1(uuid,uuid,uuid,uuid)'::regprocedure AND acl.grantee=0)
 THEN RAISE EXCEPTION '0131 dispatcher metadata/ACL/immutability boundary drift'; END IF;
END $metadata_contract$;
DO $immutable$
DECLARE before_state jsonb := pg_temp.fixture_0131_state(); actual text;
BEGIN
 BEGIN UPDATE app_private.personal_target_expiry_dispatch_requests_v1 SET unit_count=unit_count
   WHERE request_id='7f310000-0000-4000-8000-000000000100';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
 IF actual IS DISTINCT FROM '55000' THEN RAISE EXCEPTION '0131 request receipt update was not rejected as immutable'; END IF;
 actual := NULL;
 BEGIN DELETE FROM app_private.personal_target_expiry_dispatch_units_v1 WHERE request_id='7f310000-0000-4000-8000-000000000100';
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual=RETURNED_SQLSTATE; END;
 IF actual IS DISTINCT FROM '55000' OR pg_temp.fixture_0131_state() IS DISTINCT FROM before_state
 THEN RAISE EXCEPTION '0131 unit receipt delete was not rejected as immutable'; END IF;
END $immutable$;
ROLLBACK;
