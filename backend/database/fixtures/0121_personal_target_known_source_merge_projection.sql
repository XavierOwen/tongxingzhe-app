\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0121_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0121.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0121.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0121_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0121.example.test','other-owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0121.example.test','other-owner') WHERE is_current;
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '7e700000-0000-4000-8000-000000000090',workspace_id,'0121 other project' FROM fixture_0121_context;
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT ('7e700000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,c.workspace_id,
  CASE WHEN n BETWEEN 3 AND 6 THEN 'institution' ELSE 'person' END,
  '0121 source ' || n,'+1 312 555 0121',CASE WHEN n = 1 THEN NULL ELSE 'same-0121@example.test' END,c.app_user_id
FROM fixture_0121_context c CROSS JOIN generate_series(1,10) n;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0121_context c WHERE t.workspace_id = c.workspace_id;

CREATE FUNCTION pg_temp.fixture_0121_links(first_target uuid,second_target uuid) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_agg(jsonb_build_object('targetId',target_id,'targetType','person','responseLevel',2,
    'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true) ORDER BY target_id)
  FROM (VALUES (first_target),(second_target)) t(target_id) WHERE target_id IS NOT NULL
$function$;
CREATE FUNCTION pg_temp.fixture_0121_payload(contact_id text,links jsonb) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object('contactId',contact_id,'workspaceId',workspace_id,'projectId',project_id,
    'questionnaireVersionId',questionnaire_version_id,'reason','0121 synthetic revision',
    'occurredAtUtc',clock_timestamp() - interval '2 days','occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',links)
  FROM fixture_0121_context
$function$;
CREATE FUNCTION pg_temp.fixture_0121_submit(contact_id text,links jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE result_value text;
BEGIN
  SELECT result_code INTO STRICT result_value FROM app_data.apply_contact_submit_v3(
    (SELECT app_user_id FROM fixture_0121_context),contact_id || '-submit',1,'contact.submit.v1','0121-device',contact_id,0,
    pg_temp.fixture_0121_payload(contact_id,links));
  IF result_value <> 'accepted' THEN RAISE EXCEPTION '0121 contact submit rejected: %',result_value; END IF;
END
$function$;
CREATE FUNCTION pg_temp.fixture_0121_activate(first_target uuid,second_target uuid,request_id uuid)
RETURNS uuid LANGUAGE sql AS $function$
  SELECT app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,request_id,p.preview_id,first_target,second_target,second_target,first_target)
  FROM fixture_0121_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
    'https://synthetic-0121.example.test','owner',c.project_id,first_target,second_target) p
$function$;
SELECT pg_temp.fixture_0121_submit('0121-pre-contact',
  pg_temp.fixture_0121_links('7e700000-0000-4000-8000-000000000001','7e700000-0000-4000-8000-000000000002'));
CREATE TEMP TABLE fixture_0121_old_generation ON COMMIT DROP AS
SELECT pg_temp.fixture_0121_activate('7e700000-0000-4000-8000-000000000001',
  '7e700000-0000-4000-8000-000000000002','7e700000-0000-4000-8000-000000000101') AS generation_id;
SELECT pg_temp.fixture_0121_submit('0121-old-contact',
  pg_temp.fixture_0121_links('7e700000-0000-4000-8000-000000000001','7e700000-0000-4000-8000-000000000002'));
SELECT app_private.end_known_source_personal_target_merge_generation_v1(
  c.app_user_id,c.workspace_id,c.project_id,'7e700000-0000-4000-8000-000000000201',g.generation_id,m.fact_fingerprint)
FROM fixture_0121_context c CROSS JOIN fixture_0121_old_generation g
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(g.generation_id) m;
CREATE TEMP TABLE fixture_0121_generations ON COMMIT DROP AS
SELECT 'person' AS kind,pg_temp.fixture_0121_activate('7e700000-0000-4000-8000-000000000001',
  '7e700000-0000-4000-8000-000000000002','7e700000-0000-4000-8000-000000000102') AS generation_id
UNION ALL SELECT 'institution',pg_temp.fixture_0121_activate('7e700000-0000-4000-8000-000000000003',
  '7e700000-0000-4000-8000-000000000004','7e700000-0000-4000-8000-000000000103')
UNION ALL SELECT 'expired',pg_temp.fixture_0121_activate('7e700000-0000-4000-8000-000000000007',
  '7e700000-0000-4000-8000-000000000008','7e700000-0000-4000-8000-000000000104');
UPDATE app_data.promotion_targets SET phone = NULL WHERE promotion_target_id = '7e700000-0000-4000-8000-000000000002';
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7e700000-0000-4000-8000-000000000007';
SELECT pg_temp.fixture_0121_submit('0121-current-contact',
  pg_temp.fixture_0121_links('7e700000-0000-4000-8000-000000000001','7e700000-0000-4000-8000-000000000002'));
SELECT pg_temp.fixture_0121_submit(contact_id,pg_temp.fixture_0121_links('7e700000-0000-4000-8000-000000000001',NULL))
FROM (VALUES ('0121-empty-contact'),('0121-void-contact'),('0121-replaced-contact')) t(contact_id);
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0121_context),'0121-empty-revise',1,'contact.revise.v1','0121-device','0121-empty-contact',1,
  pg_temp.fixture_0121_payload('0121-empty-contact','[]'::jsonb));
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0121_context),'0121-replaced-revise',1,'contact.revise.v1','0121-device','0121-replaced-contact',1,
  pg_temp.fixture_0121_payload('0121-replaced-contact',pg_temp.fixture_0121_links('7e700000-0000-4000-8000-000000000002',NULL)));
SELECT * FROM app_data.apply_contact_void_v3(
  (SELECT app_user_id FROM fixture_0121_context),'0121-void',1,'contact.void.v1','0121-device','0121-void-contact',1,
  (SELECT jsonb_build_object('contactId','0121-void-contact','workspaceId',workspace_id,'projectId',project_id,'reason','synthetic void')
    FROM fixture_0121_context));
INSERT INTO app_data.contacts(contact_id,app_user_id,workspace_id,project_id,questionnaire_version_id,
  occurred_at_utc,occurred_time_zone,channel,location_kind,reach_count,interest_level)
SELECT t.contact_id,CASE WHEN t.contact_id = '0121-otheractor-contact' THEN o.app_user_id ELSE c.app_user_id END,
  c.workspace_id,CASE WHEN t.contact_id = '0121-otherproject-contact' THEN '7e700000-0000-4000-8000-000000000090'::uuid ELSE c.project_id END,
  c.questionnaire_version_id,clock_timestamp() - interval '2 days','UTC','video_call','not_applicable',1,2
FROM fixture_0121_context c CROSS JOIN fixture_0121_other o CROSS JOIN
  (VALUES ('0121-otheractor-contact'),('0121-otherproject-contact')) t(contact_id);
INSERT INTO app_data.contact_revisions(contact_id,revision_number,revised_by_app_user_id,snapshot)
SELECT contact_id,1,app_user_id,'{}'::jsonb FROM app_data.contacts WHERE contact_id IN ('0121-otheractor-contact','0121-otherproject-contact');
INSERT INTO app_data.contact_target_links(contact_id,revision_number,promotion_target_id,follow_up_consent,
  institution_representative_confirmed,confirmed_project_entry)
SELECT contact_id,1,'7e700000-0000-4000-8000-000000000001','unknown',false,false
FROM app_data.contacts WHERE contact_id IN ('0121-otheractor-contact','0121-otherproject-contact');
SELECT result FROM fixture_0121_context c CROSS JOIN (VALUES
  ('7e700000-0000-4000-8000-000000000001'::uuid,1,'note A','0121-project-a'),
  ('7e700000-0000-4000-8000-000000000002'::uuid,3,'note B','0121-project-b')) t(target_id,stage,note,mutation_id)
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,1,t.stage,'active',t.note,'progress_update',NULL,t.mutation_id,NULL);
INSERT INTO app_data.promotion_target_stage_aliases(project_id,stage,display_name,updated_by_app_user_id)
SELECT project_id,1,'0121 alias',app_user_id FROM fixture_0121_context;
CREATE TEMP TABLE fixture_0121_relations ON COMMIT DROP AS
SELECT t.visibility,(result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM fixture_0121_context c CROSS JOIN (VALUES
  ('visible_active','7e700000-0000-4000-8000-000000000001'::uuid,'7e700000-0000-4000-8000-000000000003'::uuid),
  ('visible_ended','7e700000-0000-4000-8000-000000000002'::uuid,'7e700000-0000-4000-8000-000000000004'::uuid),
  ('unassigned','7e700000-0000-4000-8000-000000000001'::uuid,'7e700000-0000-4000-8000-000000000005'::uuid),
  ('inactive','7e700000-0000-4000-8000-000000000001'::uuid,'7e700000-0000-4000-8000-000000000006'::uuid)
) t(visibility,person_id,institution_id) CROSS JOIN LATERAL app_data.create_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,t.person_id,t.institution_id,'employment_representative',
  '0121 role ' || t.visibility,'0121-relation-' || t.visibility);
SELECT result FROM fixture_0121_context c CROSS JOIN LATERAL app_data.end_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,(SELECT relationship_id FROM fixture_0121_relations WHERE visibility = 'visible_ended'),1,'0121-relation-end');
SELECT app_data.end_personal_target_assignment_v1(app_user_id,workspace_id,project_id,'7e700000-0000-4000-8000-000000000005')
FROM fixture_0121_context;
SELECT result FROM fixture_0121_context c CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,'7e700000-0000-4000-8000-000000000006','anonymize','withdrawal','0121-inactive-partner');
INSERT INTO app_private.personal_target_merge_generations_v1(generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc)
SELECT '7e700000-0000-4000-8000-000000000109',workspace_id,'person',app_user_id,clock_timestamp() FROM fixture_0121_context;
INSERT INTO app_private.personal_target_merge_generation_members_v1(generation_id,workspace_id,target_type,promotion_target_id)
SELECT '7e700000-0000-4000-8000-000000000109',c.workspace_id,'person',t.id FROM fixture_0121_context c
CROSS JOIN (VALUES ('7e700000-0000-4000-8000-000000000009'::uuid),('7e700000-0000-4000-8000-000000000010'::uuid)) t(id);
INSERT INTO app_private.personal_target_merge_active_members_v1(promotion_target_id,generation_id,workspace_id,target_type)
SELECT promotion_target_id,generation_id,workspace_id,target_type FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id = '7e700000-0000-4000-8000-000000000109';

CREATE FUNCTION pg_temp.fixture_0121_state() RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'targets',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r),
    'assignments',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_data.promotion_target_assignments r),
    'retention_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_retention_events r),
    'retention_policies',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.promotion_target_retention_policies r),
    'contacts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id) FROM app_data.contacts r),
    'contact_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number) FROM app_data.contact_revisions r),
    'contact_links',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number,promotion_target_id) FROM app_data.contact_target_links r),
    'project_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id) FROM app_data.promotion_target_project_relationships r),
    'relationship_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id,revision_number) FROM app_data.promotion_target_relationship_revisions r),
    'institution_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id) FROM app_data.promotion_target_institution_relationships r),
    'institution_relation_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id,revision_number) FROM app_data.promotion_target_institution_relation_revisions r),
    'generations',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_generations_v1 r),
    'members',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id,promotion_target_id) FROM app_private.personal_target_merge_generation_members_v1 r),
    'maps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_private.personal_target_merge_active_members_v1 r),
    'previews',(SELECT jsonb_agg(to_jsonb(r) ORDER BY preview_id) FROM app_private.personal_target_pair_preview_receipts r),
    'activation_requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_requests_v1 r),
    'activation_audit',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_audit_v1 r),
    'end_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_end_events_v1 r),
    'assignment_end_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_private.personal_target_assignment_end_events_v1 r),
    'pii_export_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY export_event_id) FROM app_private.personal_target_pii_export_events r),
    'fence',(SELECT to_jsonb(r) FROM app_private.personal_target_merge_generation_fence_v1 r),
    'app_users',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.app_users r),
    'workspaces',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.workspaces r),
    'projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY project_id) FROM app_data.projects r),
    'current_projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.user_current_projects r),
    'stage_aliases',(SELECT jsonb_agg(to_jsonb(r) ORDER BY project_id,stage) FROM app_data.promotion_target_stage_aliases r)
  )
$function$;

CREATE FUNCTION pg_temp.fixture_0121_read(generation_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_0121_state(); document jsonb;
BEGIN
  SELECT app_private.read_known_source_personal_target_merge_projection_v1(app_user_id,workspace_id,project_id,generation_id)
  INTO STRICT document FROM fixture_0121_context;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0121_state() THEN RAISE EXCEPTION '0121 successful read left writes'; END IF;
  RETURN document;
END
$function$;
CREATE FUNCTION pg_temp.expect_0121_failure(expected_state text,statement_text text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0121_state();
BEGIN
  BEGIN EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM expected_state THEN RAISE EXCEPTION '0121 expected %, got %',expected_state,actual_state; END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0121_state() THEN RAISE EXCEPTION '0121 rejected read left writes'; END IF;
END
$function$;
CREATE TEMP TABLE fixture_0121_documents ON COMMIT DROP AS
SELECT kind,pg_temp.fixture_0121_read(generation_id) AS document FROM fixture_0121_generations WHERE kind <> 'expired';
DO $projection_contract$
DECLARE row_value record; source jsonb; target_id uuid; expected_contacts text[]; actual_contacts text[];
BEGIN
  FOR row_value IN SELECT * FROM fixture_0121_documents LOOP
    IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(row_value.document) k) IS DISTINCT FROM ARRAY[
        'display_name','display_name_source_target_id','email','email_source_target_id','generation_id','phone',
        'phone_source_target_id','project_id','retained_target_id','review_due_at_utc','sources','target_type','workspace_id']
      OR jsonb_array_length(row_value.document->'sources') <> 2
      OR row_value.document->>'target_type' <> row_value.kind
      OR row_value.document->>'workspace_id' IS DISTINCT FROM (SELECT workspace_id::text FROM fixture_0121_context)
      OR row_value.document->>'project_id' IS DISTINCT FROM (SELECT project_id::text FROM fixture_0121_context)
      OR row_value.document->>'generation_id' IS DISTINCT FROM (SELECT generation_id::text FROM fixture_0121_generations WHERE kind = row_value.kind)
      OR (row_value.document->>'review_due_at_utc')::timestamptz IS DISTINCT FROM (
        SELECT min(app_data.promotion_target_review_due_at((s->>'target_id')::uuid)) FROM jsonb_array_elements(row_value.document->'sources') s)
    THEN RAISE EXCEPTION '0121 top-level projection shape or dynamic pair due drift'; END IF;
    FOR source IN SELECT value FROM jsonb_array_elements(row_value.document->'sources') LOOP
      target_id := (source->>'target_id')::uuid;
      IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(source) k) IS DISTINCT FROM ARRAY[
          'contact_links','institution_relationships','profile','project_relationship','review_due_at_utc','target_id']
        OR source->'profile' IS DISTINCT FROM app_data.promotion_target_document(target_id)
        OR source->'project_relationship' IS DISTINCT FROM coalesce(app_data.promotion_target_relationship_document(target_id,
          (SELECT project_id FROM fixture_0121_context),false),'null'::jsonb)
        OR (source->>'review_due_at_utc')::timestamptz IS DISTINCT FROM app_data.promotion_target_review_due_at(target_id)
        OR jsonb_array_length(source->'institution_relationships') <> 1
        OR (source->'institution_relationships'->0) ? 'history'
        OR (source->'institution_relationships'->0) IS DISTINCT FROM (
          SELECT app_data.promotion_target_institution_relation_document(r.relationship_id) - 'history'
          FROM app_data.promotion_target_institution_relationships r
          WHERE r.relationship_id IN (SELECT relationship_id FROM fixture_0121_relations WHERE visibility IN ('visible_active','visible_ended'))
            AND target_id IN (r.person_target_id,r.institution_target_id))
      THEN RAISE EXCEPTION '0121 source/helper/partner visibility drift for %',target_id; END IF;
      IF row_value.kind = 'person' THEN
        expected_contacts := ARRAY['0121-current-contact','0121-old-contact','0121-pre-contact'];
        IF target_id = '7e700000-0000-4000-8000-000000000002' THEN expected_contacts := array_append(expected_contacts,'0121-replaced-contact'); END IF;
        SELECT array_agg(link->>'contact_id' ORDER BY link->>'contact_id') INTO actual_contacts FROM jsonb_array_elements(source->'contact_links') link;
        IF actual_contacts IS DISTINCT FROM expected_contacts OR EXISTS (
          SELECT 1 FROM jsonb_array_elements(source->'contact_links') link
          WHERE (SELECT count(*) FROM jsonb_object_keys(link)) <> 8 OR (link->>'promotion_target_id')::uuid <> target_id
            OR link IS DISTINCT FROM (SELECT to_jsonb(l) FROM app_data.contact_target_links l
              WHERE l.contact_id = link->>'contact_id' AND l.revision_number = (link->>'revision_number')::integer AND l.promotion_target_id = target_id))
        THEN RAISE EXCEPTION '0121 current/original-source contact filtering drift'; END IF;
      ELSIF source->'contact_links' <> '[]'::jsonb OR source->'project_relationship' <> 'null'::jsonb THEN
        RAISE EXCEPTION '0121 empty facts are not []/null';
      END IF;
    END LOOP;
    IF row_value.document->'sources'->0->>'target_id' > row_value.document->'sources'->1->>'target_id' THEN
      RAISE EXCEPTION '0121 sources not UUID ordered';
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM fixture_0121_documents WHERE kind = 'person'
      AND document->>'retained_target_id' = '7e700000-0000-4000-8000-000000000001'
      AND document->>'display_name' = '0121 source 2' AND document->'phone' = 'null'::jsonb AND document->'email' = 'null'::jsonb
      AND document->>'display_name_source_target_id' = '7e700000-0000-4000-8000-000000000002'
      AND document->>'phone_source_target_id' = '7e700000-0000-4000-8000-000000000002'
      AND document->>'email_source_target_id' = '7e700000-0000-4000-8000-000000000001'
      AND document->'sources'->0->'project_relationship'->>'stage' = '1'
      AND document->'sources'->1->'project_relationship'->>'stage' = '3'
      AND document->'sources'->0->'project_relationship'->>'follow_up_note' = 'note A'
      AND document->'sources'->1->'project_relationship'->>'follow_up_note' = 'note B')
    OR NOT EXISTS (SELECT 1 FROM fixture_0121_documents WHERE kind = 'institution'
      AND document->>'display_name' = '0121 source 4' AND document->>'phone' = '+1 312 555 0121'
      AND document->>'email' = 'same-0121@example.test'
      AND document->>'retained_target_id' = '7e700000-0000-4000-8000-000000000003'
      AND document->>'phone_source_target_id' = '7e700000-0000-4000-8000-000000000004'
      AND document->>'email_source_target_id' = '7e700000-0000-4000-8000-000000000003')
  THEN RAISE EXCEPTION '0121 selected source/NULL/same-value/independent stages drift'; END IF;
END
$projection_contract$;

SELECT pg_temp.expect_0121_failure('22023',format('SELECT app_private.read_known_source_personal_target_merge_projection_v1(%L,%L,%L,%L)',a,w,p,g))
FROM fixture_0121_context c CROSS JOIN fixture_0121_generations x CROSS JOIN LATERAL (VALUES
  (NULL::uuid,c.workspace_id,c.project_id,x.generation_id),(c.app_user_id,NULL::uuid,c.project_id,x.generation_id),
  (c.app_user_id,c.workspace_id,NULL::uuid,x.generation_id),(c.app_user_id,c.workspace_id,c.project_id,NULL::uuid)) bad(a,w,p,g)
WHERE x.kind = 'person';
SELECT pg_temp.expect_0121_failure('42501',format('SELECT app_private.read_known_source_personal_target_merge_projection_v1(%L,%L,%L,%L)',a,w,p,x.generation_id))
FROM fixture_0121_context c CROSS JOIN fixture_0121_other o CROSS JOIN fixture_0121_generations x CROSS JOIN LATERAL (VALUES
  (o.app_user_id,o.workspace_id,o.project_id),(o.app_user_id,c.workspace_id,c.project_id),
  (c.app_user_id,o.workspace_id,c.project_id),(c.app_user_id,c.workspace_id,'7e700000-0000-4000-8000-000000000090'::uuid)) bad(a,w,p)
WHERE x.kind = 'person';
SELECT pg_temp.expect_0121_failure('42501',format('SELECT pg_temp.fixture_0121_read(%L)',generation_id))
FROM fixture_0121_old_generation;
SELECT pg_temp.expect_0121_failure('42501',format('SELECT pg_temp.fixture_0121_read(%L)',generation_id))
FROM fixture_0121_generations WHERE kind = 'expired';
SELECT pg_temp.expect_0121_failure('42501',$$SELECT pg_temp.fixture_0121_read('7e700000-0000-4000-8000-000000000199')$$);
SELECT pg_temp.expect_0121_failure('55000',$$SELECT pg_temp.fixture_0121_read('7e700000-0000-4000-8000-000000000109')$$);
SAVEPOINT missing_map;
DELETE FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id = '7e700000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0121_failure('55000',format('SELECT pg_temp.fixture_0121_read(%L)',generation_id)) FROM fixture_0121_generations WHERE kind = 'person';
ROLLBACK TO SAVEPOINT missing_map;
RELEASE SAVEPOINT missing_map;
SAVEPOINT bad_selection;
SET LOCAL session_replication_role = replica;
UPDATE app_private.personal_target_merge_activation_requests_v1 SET phone_source_target_id = '7e700000-0000-4000-8000-000000000003'
WHERE generation_id = (SELECT generation_id FROM fixture_0121_generations WHERE kind = 'person');
SET LOCAL session_replication_role = origin;
SELECT pg_temp.expect_0121_failure('55000',format('SELECT pg_temp.fixture_0121_read(%L)',generation_id)) FROM fixture_0121_generations WHERE kind = 'person';
ROLLBACK TO SAVEPOINT bad_selection;
RELEASE SAVEPOINT bad_selection;
SAVEPOINT ended_assignment;
UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'user_requested'
WHERE assignment_id = '7e700000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0121_failure('42501',format('SELECT pg_temp.fixture_0121_read(%L)',generation_id)) FROM fixture_0121_generations WHERE kind = 'person';
ROLLBACK TO SAVEPOINT ended_assignment;
RELEASE SAVEPOINT ended_assignment;
SAVEPOINT changed_context;
UPDATE app_data.user_current_projects SET project_id = '7e700000-0000-4000-8000-000000000090'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0121_context);
SELECT pg_temp.expect_0121_failure('42501',format('SELECT pg_temp.fixture_0121_read(%L)',generation_id)) FROM fixture_0121_generations WHERE kind = 'person';
ROLLBACK TO SAVEPOINT changed_context;
RELEASE SAVEPOINT changed_context;

SELECT app_data.configure_promotion_target_retention_policy(app_user_id,workspace_id,project_id,9) FROM fixture_0121_context;
CREATE TEMP TABLE fixture_0121_policy_read ON COMMIT DROP AS
SELECT pg_temp.fixture_0121_read(generation_id) AS document FROM fixture_0121_generations WHERE kind = 'person';
SELECT result FROM fixture_0121_context c CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,'7e700000-0000-4000-8000-000000000001','renew','purpose_confirmed','0121-renew');
CREATE TEMP TABLE fixture_0121_latest ON COMMIT DROP AS
SELECT pg_temp.fixture_0121_read(generation_id) AS document FROM fixture_0121_generations WHERE kind = 'person';
DO $latest_due$
BEGIN
  IF (SELECT (document->>'review_due_at_utc')::timestamptz FROM fixture_0121_latest) IS DISTINCT FROM (
      SELECT least(app_data.promotion_target_review_due_at('7e700000-0000-4000-8000-000000000001'),
        app_data.promotion_target_review_due_at('7e700000-0000-4000-8000-000000000002')))
    OR (SELECT document->>'review_due_at_utc' FROM fixture_0121_latest) IS NOT DISTINCT FROM (
      SELECT document->>'review_due_at_utc' FROM fixture_0121_documents WHERE kind = 'person')
    OR EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)'::regprocedure AND provolatile <> 's')
    OR has_function_privilege('public','app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION '0121 current policy/renewal due, STABLE or ACL drift'; END IF;
END
$latest_due$;

SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0121_context),'0121-latest-submit',1,'contact.submit.v1','0121-device','0121-latest-contact',0,
  pg_temp.fixture_0121_payload('0121-latest-contact',pg_temp.fixture_0121_links(
    '7e700000-0000-4000-8000-000000000001','7e700000-0000-4000-8000-000000000002'))
    || jsonb_build_object('occurredAtUtc',clock_timestamp() + interval '1 day'));
CREATE TEMP TABLE fixture_0121_current_due ON COMMIT DROP AS
SELECT pg_temp.fixture_0121_read(generation_id) AS document FROM fixture_0121_generations WHERE kind = 'person';
DO $current_contact_due$
BEGIN
  IF (SELECT (document->>'review_due_at_utc')::timestamptz FROM fixture_0121_current_due) IS DISTINCT FROM (
      SELECT least(app_data.promotion_target_review_due_at('7e700000-0000-4000-8000-000000000001'),
        app_data.promotion_target_review_due_at('7e700000-0000-4000-8000-000000000002')))
    OR (SELECT (document->>'review_due_at_utc')::timestamptz FROM fixture_0121_current_due) <= (
      SELECT (document->>'review_due_at_utc')::timestamptz FROM fixture_0121_latest)
    OR (SELECT count(*) FROM fixture_0121_current_due d CROSS JOIN LATERAL jsonb_array_elements(d.document->'sources') s
      CROSS JOIN LATERAL jsonb_array_elements(s->'contact_links') l WHERE l->>'contact_id' = '0121-latest-contact') <> 2
  THEN RAISE EXCEPTION '0121 current contact failed to update current due and both source groups'; END IF;
END
$current_contact_due$;

ROLLBACK;
