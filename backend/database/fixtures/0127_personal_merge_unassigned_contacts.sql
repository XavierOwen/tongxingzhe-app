\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0127_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0127.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0127.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0127_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0127.example.test','other');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0127.example.test','other') WHERE is_current;
CREATE TEMP TABLE fixture_0127_pairs(kind text,first_target uuid,second_target uuid,generation_id uuid) ON COMMIT DROP;
INSERT INTO fixture_0127_pairs VALUES
  ('person','7f270000-0000-4000-8000-000000000001','7f270000-0000-4000-8000-000000000002',NULL),
  ('institution','7f270000-0000-4000-8000-000000000003','7f270000-0000-4000-8000-000000000004',NULL);
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT target_id,c.workspace_id,p.kind,'0127 synthetic source','+1 312 555 0127',c.app_user_id
FROM fixture_0127_pairs p CROSS JOIN fixture_0127_context c
CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0127_context c WHERE t.workspace_id = c.workspace_id;
CREATE FUNCTION pg_temp.fixture_0127_submit(contact text,links jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE code text;
BEGIN
  SELECT result_code INTO code FROM fixture_0127_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
    c.app_user_id,contact || '-submit',1,'contact.submit.v1','0127-device',contact,0,
    jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,
      'questionnaireVersionId',c.questionnaire_version_id,'reason','0127 synthetic contact',
      'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',2,
      'answers','[]'::jsonb,'targetLinks',links)) s;
  IF code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0127 synthetic contact setup rejected'; END IF;
END $function$;
SELECT pg_temp.fixture_0127_submit('0127-known-null-binding',jsonb_build_array(jsonb_build_object(
  'targetId',first_target,'targetType','person','responseLevel',NULL,'followUpConsent','unknown',
  'institutionRepresentativeConfirmed',false,'confirmStageZero',true))) FROM fixture_0127_pairs WHERE kind = 'person';
SELECT pg_temp.fixture_0127_submit('0127-before-generation','[]'::jsonb);
DO $activate$
DECLARE c record; p record; preview uuid; generation uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0127_context;
  FOR p IN SELECT * FROM fixture_0127_pairs LOOP
    SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1(
      'https://synthetic-0127.example.test','owner',c.project_id,p.first_target,p.second_target);
    generation := app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,
      gen_random_uuid(),preview,p.first_target,p.second_target,p.first_target,p.second_target);
    UPDATE fixture_0127_pairs SET generation_id = generation WHERE kind = p.kind;
  END LOOP;
END $activate$;
SELECT pg_temp.fixture_0127_submit(contact,'[]'::jsonb) FROM (VALUES
  ('0127 person | "TEXT": one'),('0127-person-two'),('0127-institution'),('0127-candidate')) t(contact);
SELECT pg_temp.fixture_0127_submit('0127-known-current',jsonb_build_array(jsonb_build_object(
  'targetId',first_target,'targetType','person','responseLevel',2,'followUpConsent','yes',
  'institutionRepresentativeConfirmed',false,'confirmStageZero',true))) FROM fixture_0127_pairs WHERE kind = 'person';

CREATE FUNCTION pg_temp.fixture_0127_state(requested_workspace_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $function$
  WITH targets AS (
    SELECT promotion_target_id FROM app_data.promotion_targets WHERE workspace_id = requested_workspace_id
  ), contacts AS (
    SELECT contact_id FROM app_data.contacts WHERE workspace_id = requested_workspace_id
  ), generations AS (
    SELECT generation_id FROM app_private.personal_target_merge_generations_v1 WHERE workspace_id = requested_workspace_id
  ), relations AS (
    SELECT relationship_id FROM app_data.promotion_target_institution_relationships
    WHERE person_target_id IN (SELECT promotion_target_id FROM targets)
  ), owners AS (
    SELECT personal_owner_app_user_id AS app_user_id FROM app_data.workspaces WHERE workspace_id = requested_workspace_id
  )
  SELECT jsonb_build_object(
    'targets',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r WHERE workspace_id = requested_workspace_id),
    'assignments',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_data.promotion_target_assignments r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'retention_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_retention_events r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'retention_policies',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.promotion_target_retention_policies r WHERE workspace_id = requested_workspace_id),
    'contacts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id) FROM app_data.contacts r WHERE workspace_id = requested_workspace_id),
    'contact_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number) FROM app_data.contact_revisions r WHERE contact_id IN (SELECT contact_id FROM contacts)),
    'contact_links',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number,promotion_target_id) FROM app_data.contact_target_links r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'project_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id) FROM app_data.promotion_target_project_relationships r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'relationship_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id,revision_number) FROM app_data.promotion_target_relationship_revisions r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'institution_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id) FROM app_data.promotion_target_institution_relationships r WHERE relationship_id IN (SELECT relationship_id FROM relations)),
    'institution_relation_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id,revision_number) FROM app_data.promotion_target_institution_relation_revisions r WHERE relationship_id IN (SELECT relationship_id FROM relations)),
    'preview_receipts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY preview_id) FROM app_private.personal_target_pair_preview_receipts r WHERE workspace_id = requested_workspace_id),
    'generations',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_generations_v1 r WHERE workspace_id = requested_workspace_id),
    'generation_members',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id,promotion_target_id) FROM app_private.personal_target_merge_generation_members_v1 r WHERE generation_id IN (SELECT generation_id FROM generations)),
    'active_members',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_private.personal_target_merge_active_members_v1 r WHERE workspace_id = requested_workspace_id),
    'activation_requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_requests_v1 r WHERE workspace_id = requested_workspace_id),
    'activation_audit',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_audit_v1 r WHERE workspace_id = requested_workspace_id),
    'assignment_end_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_private.personal_target_assignment_end_events_v1 r WHERE workspace_id = requested_workspace_id),
    'end_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_end_events_v1 r WHERE generation_id IN (SELECT generation_id FROM generations)),
    'pii_export_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY export_event_id) FROM app_private.personal_target_pii_export_events r WHERE workspace_id = requested_workspace_id),
    'stage_aliases',(SELECT jsonb_agg(to_jsonb(r) ORDER BY project_id,stage) FROM app_data.promotion_target_stage_aliases r WHERE project_id IN (SELECT project_id FROM app_data.projects WHERE workspace_id = requested_workspace_id)),
    'app_users',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.app_users r WHERE app_user_id IN (SELECT app_user_id FROM owners)),
    'external_identities',(SELECT jsonb_agg(to_jsonb(r) ORDER BY external_identity_id) FROM app_data.external_identities r WHERE app_user_id IN (SELECT app_user_id FROM owners)),
    'workspaces',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.workspaces r WHERE workspace_id = requested_workspace_id),
    'projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY project_id) FROM app_data.projects r WHERE workspace_id = requested_workspace_id),
    'current_projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.user_current_projects r WHERE app_user_id IN (SELECT app_user_id FROM owners)),
    'pending_requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY pending_fact_id) FROM app_private.personal_merge_unassigned_contact_requests_v1 r WHERE workspace_id = requested_workspace_id),
    'pending_payloads',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.pending_fact_id) FROM app_data.personal_merge_unassigned_contact_facts_v1 p JOIN app_private.personal_merge_unassigned_contact_requests_v1 r USING(pending_fact_id) WHERE r.workspace_id = requested_workspace_id),
    'pending_purges',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.pending_fact_id) FROM app_private.personal_merge_unassigned_contact_purges_v1 p JOIN app_private.personal_merge_unassigned_contact_requests_v1 r USING(pending_fact_id) WHERE r.workspace_id = requested_workspace_id),
    'access_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_access_events r WHERE workspace_id = requested_workspace_id),
    'warehouse_outbox',(SELECT jsonb_agg(to_jsonb(r) ORDER BY warehouse_event_id) FROM app_data.warehouse_outbox r WHERE contact_id IN (SELECT contact_id FROM contacts)),
    'fence',(SELECT to_jsonb(r) FROM app_private.personal_target_merge_generation_fence_v1 r))
$function$;

CREATE FUNCTION pg_temp.fixture_0127_stage(kind text,request uuid,contact text,revision integer DEFAULT 1,
  response integer DEFAULT NULL,consent text DEFAULT 'unknown',representative boolean DEFAULT false,entry boolean DEFAULT true)
RETURNS uuid LANGUAGE sql AS $function$
  SELECT app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
    request,p.generation_id,contact,revision,response,consent,representative,entry)
  FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p WHERE p.kind = $1
$function$;
CREATE FUNCTION pg_temp.fixture_0127_read(kind text) RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id)
  FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p WHERE p.kind = $1
$function$;
CREATE FUNCTION pg_temp.fixture_0127_expect_failure(expected text,command text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb; actual text;
BEGIN
  SELECT pg_temp.fixture_0127_state(workspace_id) INTO before_state FROM fixture_0127_context;
  BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE; END;
  IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION '0127 expected %, got %',expected,actual; END IF;
  IF before_state IS DISTINCT FROM (SELECT pg_temp.fixture_0127_state(workspace_id) FROM fixture_0127_context)
  THEN RAISE EXCEPTION '0127 failed operation left business, pending, audit or fence changes'; END IF;
END $function$;
CREATE TEMP TABLE fixture_0127_before ON COMMIT DROP AS
SELECT pg_temp.fixture_0127_state(workspace_id) AS state FROM fixture_0127_context;
CREATE TEMP TABLE fixture_0127_pending ON COMMIT DROP AS
SELECT 'person-one'::text AS label,pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000201','0127 person | "TEXT": one') AS pending_fact_id
UNION ALL SELECT 'person-two',pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000202','0127-person-two',1,2,'yes')
UNION ALL SELECT 'institution',pg_temp.fixture_0127_stage('institution','7f270000-0000-4000-8000-000000000203','0127-institution',1,NULL,'not_applicable',false,true);
DO $success$
DECLARE document jsonb; old_state jsonb; new_state jsonb; item jsonb; pair record;
BEGIN
  SELECT state INTO old_state FROM fixture_0127_before;
  SELECT pg_temp.fixture_0127_state(workspace_id) INTO new_state FROM fixture_0127_context;
  IF (old_state - ARRAY['pending_requests','pending_payloads','pending_purges','fence']) IS DISTINCT FROM
      (new_state - ARRAY['pending_requests','pending_payloads','pending_purges','fence'])
    OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE workspace_id = (SELECT workspace_id FROM fixture_0127_context)) <> 3
    OR (SELECT count(*) FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0127_pending)) <> 3
    OR NOT EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one') AND response_level IS NULL)
    OR NOT EXISTS (SELECT 1 FROM app_data.contact_target_links WHERE contact_id = '0127-known-null-binding' AND merge_generation_id IS NULL)
  THEN RAISE EXCEPTION '0127 staging changed original facts or inferred unknown from NULL binding'; END IF;
  IF pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000201','0127 person | "TEXT": one')
      IS DISTINCT FROM (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one')
  THEN RAISE EXCEPTION '0127 exact replay did not return the original pending UUID'; END IF;
  FOR pair IN SELECT * FROM fixture_0127_pairs LOOP
    document := pg_temp.fixture_0127_read(pair.kind);
    IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(document) key) <>
        ARRAY['known_source_plan','pending_contacts','pending_count','pending_fingerprint']
      OR document->'known_source_plan' IS DISTINCT FROM app_private.read_known_source_personal_merge_split_plan_v1(
        (SELECT app_user_id FROM fixture_0127_context),(SELECT workspace_id FROM fixture_0127_context),(SELECT project_id FROM fixture_0127_context),pair.generation_id)
      OR (document->>'pending_count')::integer <> (CASE WHEN pair.kind = 'person' THEN 2 ELSE 1 END)
      OR document->>'pending_fingerprint' IS DISTINCT FROM encode(sha256(convert_to((document->'pending_contacts')::text,'UTF8')),'hex')
      OR document::text ~ 'response_level|follow_up_consent|representative_confirmed|confirmed_project_entry|0127 synthetic source'
    THEN RAISE EXCEPTION '0127 readonly plan metadata contract drift'; END IF;
    FOR item IN SELECT value FROM jsonb_array_elements(document->'pending_contacts') LOOP
      IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(item) key) <>
          ARRAY['contact_id','pending_fact_id','revision_number','staged_at_utc','target_type']
        OR item->>'staged_at_utc' !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$'
        OR item->>'target_type' IS DISTINCT FROM pair.kind
      THEN RAISE EXCEPTION '0127 pending metadata item shape drift'; END IF;
    END LOOP;
    IF document->'pending_contacts' IS DISTINCT FROM (SELECT jsonb_agg(value ORDER BY value->>'pending_fact_id')
        FROM jsonb_array_elements(document->'pending_contacts'))
    THEN RAISE EXCEPTION '0127 pending UUID order drift'; END IF;
  END LOOP;
END $success$;
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only = on;
DO $readonly$
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION '0127 actual READ ONLY was not enabled'; END IF;
  PERFORM pg_temp.fixture_0127_read(kind) FROM fixture_0127_pairs;
END $readonly$;
ROLLBACK TO SAVEPOINT readonly_scope;
RELEASE SAVEPOINT readonly_scope;

CREATE TEMP TABLE fixture_0127_project_a_plan ON COMMIT DROP AS
SELECT pg_temp.fixture_0127_read('institution') AS document;
CREATE TEMP TABLE fixture_0127_project_b ON COMMIT DROP AS
SELECT * FROM app_data.create_personal_project_context('https://synthetic-0127.example.test','owner','0127 other project');
SELECT count(*) FROM fixture_0127_project_b c CROSS JOIN LATERAL app_data.select_personal_project_context(
  'https://synthetic-0127.example.test','owner',c.project_id) p;
DO $cross_project_existing$
DECLARE document jsonb;
BEGIN
  SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id)
    INTO document FROM fixture_0127_project_b c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'institution';
  IF document->'pending_contacts' IS DISTINCT FROM (SELECT a.document->'pending_contacts' FROM fixture_0127_project_a_plan a)
    OR document->>'pending_count' <> '1'
  THEN RAISE EXCEPTION '0127 switching current project hid a legitimate pending contact'; END IF;
END $cross_project_existing$;
SELECT result_code FROM fixture_0127_project_b c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id,'0127-project-b-submit',1,'contact.submit.v1','0127-device','0127-project-b-contact',0,
  jsonb_build_object('contactId','0127-project-b-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
    'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC',
    'channel','video_call','location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
    'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) s;
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SELECT pg_temp.fixture_0127_stage('institution','7f270000-0000-4000-8000-000000000204','0127-project-b-contact',1,2,'yes',true,true)$$);
INSERT INTO fixture_0127_pending
SELECT 'institution-B',app_private.stage_unassigned_personal_merge_contact_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f270000-0000-4000-8000-000000000204',p.generation_id,'0127-project-b-contact',1,2,'yes',true,true)
FROM fixture_0127_project_b c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'institution';
CREATE TEMP TABLE fixture_0127_project_b_plan ON COMMIT DROP AS
SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(c.app_user_id,c.workspace_id,c.project_id,p.generation_id) AS document
FROM fixture_0127_project_b c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'institution';
SELECT count(*) FROM fixture_0127_context c CROSS JOIN LATERAL app_data.select_personal_project_context(
  'https://synthetic-0127.example.test','owner',c.project_id) p;
DO $cross_project_complete$
DECLARE document jsonb; item jsonb;
BEGIN
  document := pg_temp.fixture_0127_read('institution');
  IF document->>'pending_count' <> '2'
    OR document->'pending_contacts' IS DISTINCT FROM (SELECT b.document->'pending_contacts' FROM fixture_0127_project_b_plan b)
    OR document->'pending_fingerprint' IS DISTINCT FROM (SELECT b.document->'pending_fingerprint' FROM fixture_0127_project_b_plan b)
  THEN RAISE EXCEPTION '0127 cross-project pending inventory was filtered or changed'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(document->'pending_contacts') LOOP
    IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(item) key) <>
      ARRAY['contact_id','pending_fact_id','revision_number','staged_at_utc','target_type']
    THEN RAISE EXCEPTION '0127 cross-project plan copied business payload'; END IF;
  END LOOP;
END $cross_project_complete$;

SELECT pg_temp.fixture_0127_expect_failure('23505',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000201','0127 person | "TEXT": one',1,1)$$);
SELECT pg_temp.fixture_0127_expect_failure('23505',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000201','0127 person | "TEXT": one',1,NULL,'no')$$);
SELECT pg_temp.fixture_0127_expect_failure('23505',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127 person | "TEXT": one')$$);
SELECT pg_temp.fixture_0127_expect_failure('23505',$$SELECT pg_temp.fixture_0127_stage('institution','7f270000-0000-4000-8000-000000000201','0127-institution')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-known-null-binding')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-known-current')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-before-generation')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',format(
  'SELECT app_private.stage_unassigned_personal_merge_contact_v1(%L,%L,%L,%L,%L,%L,1,NULL,%L,false,true)',
  other_owner.app_user_id,c.workspace_id,c.project_id,'7f270000-0000-4000-8000-000000000211',p.generation_id,'0127-candidate','unknown'))
FROM fixture_0127_context c CROSS JOIN fixture_0127_other other_owner CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'person';
SELECT pg_temp.fixture_0127_expect_failure('22023',command) FROM (VALUES
  ($$SELECT pg_temp.fixture_0127_stage('person',NULL,'0127-candidate')$$),
  ($$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211',NULL)$$),
  ($$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate',0)$$),
  ($$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate',1,5)$$),
  ($$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate',1,NULL,'bad')$$),
  ($$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate',1,NULL,'unknown',true)$$),
  ($$SELECT pg_temp.fixture_0127_stage('institution','7f270000-0000-4000-8000-000000000211','0127-candidate',1,2,'unknown',false)$$),
  ($$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate',1,NULL,'unknown',NULL)$$)
) cases(command);
DO $qualification$
DECLARE variant integer; command text := $$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate')$$;
BEGIN
  FOR variant IN 1..6 LOOP
    BEGIN
      CASE variant
        WHEN 1 THEN UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = (SELECT app_user_id FROM fixture_0127_context);
        WHEN 2 THEN DELETE FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0127_context);
        WHEN 3 THEN UPDATE app_data.projects SET status = 'archived' WHERE project_id = (SELECT project_id FROM fixture_0127_context);
        WHEN 4 THEN UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'synthetic ended' WHERE promotion_target_id = (SELECT first_target FROM fixture_0127_pairs WHERE kind = 'person');
        WHEN 5 THEN
          UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months' WHERE promotion_target_id = (SELECT first_target FROM fixture_0127_pairs WHERE kind = 'person');
          UPDATE app_data.contacts SET occurred_at_utc = clock_timestamp() - interval '14 months'
          WHERE contact_id IN ('0127-known-null-binding','0127-known-current');
        WHEN 6 THEN DELETE FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id = (SELECT first_target FROM fixture_0127_pairs WHERE kind = 'person');
      END CASE;
      PERFORM pg_temp.fixture_0127_expect_failure(CASE WHEN variant = 6 THEN '55000' ELSE '42501' END,command);
      RAISE EXCEPTION USING ERRCODE = 'ZXREV',MESSAGE = 'restore synthetic qualification';
    EXCEPTION WHEN SQLSTATE 'ZXREV' THEN NULL;
    END;
  END LOOP;
END $qualification$;
SELECT pg_temp.fixture_0127_expect_failure('55000',$$UPDATE app_private.personal_merge_unassigned_contact_requests_v1 SET request_id = request_id WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one')$$);
SELECT pg_temp.fixture_0127_expect_failure('55000',$$DELETE FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one')$$);
SELECT pg_temp.fixture_0127_expect_failure('55000',$$UPDATE app_data.personal_merge_unassigned_contact_facts_v1 SET response_level = 1 WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$DELETE FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one')$$);
SELECT pg_temp.fixture_0127_expect_failure('55000',format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,'7f270000-0000-4000-8000-000000000221',p.generation_id,m.fact_fingerprint))
FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(p.generation_id) m WHERE p.kind = 'person';

CREATE FUNCTION pg_temp.fixture_0127_stage_failure() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN RAISE EXCEPTION USING ERRCODE = 'ZXSTG',MESSAGE = 'synthetic payload insertion failure'; END $function$;
CREATE TRIGGER fixture_0127_stage_failure BEFORE INSERT ON app_data.personal_merge_unassigned_contact_facts_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0127_stage_failure();
SELECT pg_temp.fixture_0127_expect_failure('ZXSTG',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000211','0127-candidate')$$);
DROP TRIGGER fixture_0127_stage_failure ON app_data.personal_merge_unassigned_contact_facts_v1;

UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = (SELECT first_target FROM fixture_0127_pairs WHERE kind = 'person');
UPDATE app_data.contacts SET occurred_at_utc = clock_timestamp() - interval '14 months'
WHERE contact_id IN ('0127-known-null-binding','0127-known-current');
CREATE TEMP TABLE fixture_0127_probe(mode text,n integer) ON COMMIT DROP;
INSERT INTO fixture_0127_probe VALUES ('raise',0);
CREATE FUNCTION pg_temp.fixture_0127_purge_failure() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE mode_value text; ordinal integer;
BEGIN
  UPDATE fixture_0127_probe SET n = n + 1 RETURNING mode,n INTO mode_value,ordinal;
  IF ordinal = 2 THEN
    IF mode_value = 'suppress' THEN RETURN NULL; END IF;
    RAISE EXCEPTION USING ERRCODE = 'ZXPRG',MESSAGE = 'synthetic second purge failure';
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0127_purge_failure BEFORE INSERT ON app_private.personal_merge_unassigned_contact_purges_v1
FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_0127_purge_failure();
SELECT pg_temp.fixture_0127_expect_failure('ZXPRG',format(
  'SELECT app_private.expire_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,'7f270000-0000-4000-8000-000000000222',p.generation_id))
FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'person';
UPDATE fixture_0127_probe SET mode = 'suppress';
SELECT pg_temp.fixture_0127_expect_failure('55000',format(
  'SELECT app_private.expire_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,'7f270000-0000-4000-8000-000000000222',p.generation_id))
FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'person';
DO $probe$ BEGIN
  IF (SELECT n FROM fixture_0127_probe) <> 0 THEN RAISE EXCEPTION '0127 first purge/probe did not roll back'; END IF;
END $probe$;
DROP TRIGGER fixture_0127_purge_failure ON app_private.personal_merge_unassigned_contact_purges_v1;
CREATE TEMP TABLE fixture_0127_expired ON COMMIT DROP AS
SELECT app_private.expire_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,
  '7f270000-0000-4000-8000-000000000222',p.generation_id) AS expired_at
FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'person';
DO $expiry$
DECLARE expiry_time timestamptz;
BEGIN
  IF (SELECT count(*) FROM app_data.promotion_targets t JOIN fixture_0127_pairs p ON t.promotion_target_id IN (p.first_target,p.second_target)
      WHERE p.kind = 'person' AND t.status = 'anonymized' AND t.phone IS NULL AND t.email IS NULL) <> 2
    OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0127_pending)) <> 4
    OR (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0127_pending)) <> 2
    OR (SELECT count(*) FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id IN (SELECT pending_fact_id FROM fixture_0127_pending)) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'institution'))
  THEN RAISE EXCEPTION '0127 expiry failed atomic two-member erasure, payload purge or preserved history'; END IF;
  SELECT app_private.expire_known_source_personal_target_merge_generation_v1(c.app_user_id,c.workspace_id,c.project_id,
    '7f270000-0000-4000-8000-000000000222',p.generation_id) INTO expiry_time
  FROM fixture_0127_context c CROSS JOIN fixture_0127_pairs p WHERE p.kind = 'person';
  IF expiry_time IS DISTINCT FROM (SELECT expired_at FROM fixture_0127_expired)
  THEN RAISE EXCEPTION '0127 existing expiry receipt replay changed'; END IF;
END $expiry$;
SELECT pg_temp.fixture_0127_expect_failure('55000',$$DELETE FROM app_private.personal_merge_unassigned_contact_purges_v1 WHERE pending_fact_id = (SELECT pending_fact_id FROM fixture_0127_pending WHERE label = 'person-one')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SELECT pg_temp.fixture_0127_read('person')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SELECT pg_temp.fixture_0127_stage('person','7f270000-0000-4000-8000-000000000201','0127 person | "TEXT": one')$$);
SELECT pg_temp.fixture_0127_expect_failure('42501',$$SET LOCAL ROLE tongxingzhe_runtime; SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(NULL,NULL,NULL,NULL)$$);
ROLLBACK;
