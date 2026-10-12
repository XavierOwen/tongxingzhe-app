\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0120_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0120.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0120.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0120_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0120.example.test','other-owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0120.example.test','other-owner') WHERE is_current;

CREATE TEMP TABLE fixture_0120_pairs ON COMMIT DROP AS
SELECT pair_number, kind,
  ('7ef00000-0000-4000-8000-' || lpad((pair_number * 2 - 1)::text,12,'0'))::uuid AS first_target,
  ('7ef00000-0000-4000-8000-' || lpad((pair_number * 2)::text,12,'0'))::uuid AS second_target,
  ('7ef00000-0000-4000-8000-' || lpad((100 + pair_number)::text,12,'0'))::uuid AS generation_id,
  ('7ef00000-0000-4000-8000-' || lpad((200 + pair_number)::text,12,'0'))::uuid AS request_id
FROM (VALUES (1,'person'),(2,'person'),(3,'institution'),(4,'person'),
  (5,'person'),(6,'institution'),(7,'person'),(8,'person')) p(pair_number,kind);
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id,created_at
)
SELECT t.target_id,c.workspace_id,p.kind,'0120 synthetic ' || t.target_id,
  '+1 312 555 0120','0120@example.test',c.app_user_id,clock_timestamp()
FROM fixture_0120_pairs p CROSS JOIN fixture_0120_context c
CROSS JOIN LATERAL (VALUES (p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(
  assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id
)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0120_context c
WHERE t.workspace_id = c.workspace_id;
INSERT INTO app_private.personal_target_merge_generations_v1(
  generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc
)
SELECT p.generation_id,c.workspace_id,p.kind,c.app_user_id,clock_timestamp()
FROM fixture_0120_pairs p CROSS JOIN fixture_0120_context c;
INSERT INTO app_private.personal_target_merge_generation_members_v1(
  generation_id,workspace_id,target_type,promotion_target_id
)
SELECT p.generation_id,c.workspace_id,p.kind,t.target_id
FROM fixture_0120_pairs p CROSS JOIN fixture_0120_context c
CROSS JOIN LATERAL (VALUES (p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_private.personal_target_merge_active_members_v1(
  promotion_target_id,generation_id,workspace_id,target_type
)
SELECT promotion_target_id,generation_id,workspace_id,target_type
FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id IN (SELECT generation_id FROM fixture_0120_pairs);
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '7ef00000-0000-4000-8000-000000000090',workspace_id,'0120 alternate project' FROM fixture_0120_context;

SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0120_context),'0120-bound-submit',1,'contact.submit.v1','0120-device','0120-bound-contact',0,
  (SELECT jsonb_build_object('contactId','0120-bound-contact','workspaceId',workspace_id,'projectId',project_id,
    'questionnaireVersionId',questionnaire_version_id,'occurredAtUtc',clock_timestamp() - interval '2 years',
    'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
    'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(
      jsonb_build_object('targetId','7ef00000-0000-4000-8000-000000000001','targetType','person',
        'responseLevel',2,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true),
      jsonb_build_object('targetId','7ef00000-0000-4000-8000-000000000002','targetType','person',
        'responseLevel',1,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
   FROM fixture_0120_context)
);
SELECT result FROM fixture_0120_context c CROSS JOIN (VALUES
  ('7ef00000-0000-4000-8000-000000000001'::uuid,'0120-project-a'),
  ('7ef00000-0000-4000-8000-000000000002'::uuid,'0120-project-b')) t(target_id,mutation_id)
CROSS JOIN LATERAL app_data.update_promotion_target_relationship(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,1,1,'active',
  'synthetic sensitive note','progress_update','synthetic sensitive reason',t.mutation_id,NULL
);
CREATE TEMP TABLE fixture_0120_active_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM fixture_0120_context c CROSS JOIN LATERAL app_data.create_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,'7ef00000-0000-4000-8000-000000000001',
  '7ef00000-0000-4000-8000-000000000011','employment_representative','synthetic active role','0120-active-relation'
);
CREATE TEMP TABLE fixture_0120_ended_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM fixture_0120_context c CROSS JOIN LATERAL app_data.create_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,'7ef00000-0000-4000-8000-000000000002',
  '7ef00000-0000-4000-8000-000000000012','membership_affiliation','synthetic ended role','0120-ended-relation'
);
SELECT result FROM fixture_0120_context c CROSS JOIN LATERAL app_data.end_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,(SELECT relationship_id FROM fixture_0120_ended_relation),1,'0120-ended-relation-end'
);

CREATE FUNCTION pg_temp.fixture_0120_expire(generation_id uuid,request_id uuid)
RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    app_user_id,workspace_id,project_id,request_id,generation_id
  ) FROM fixture_0120_context
$function$;
CREATE FUNCTION pg_temp.fixture_0120_state() RETURNS jsonb LANGUAGE sql AS $function$
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
    'fence',(SELECT to_jsonb(r) FROM app_private.personal_target_merge_generation_fence_v1 r)
  )
$function$;
CREATE FUNCTION pg_temp.expect_0120_failure(expected_state text,statement_text text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0120_state();
BEGIN
  BEGIN EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION '0120 expected SQLSTATE %, got %',expected_state,actual_state;
  END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0120_state() THEN
    RAISE EXCEPTION '0120 rejected request left business, end, retention, mapping or fence writes';
  END IF;
END
$function$;

CREATE TEMP TABLE fixture_0120_ordinary_end ON COMMIT DROP AS
SELECT p.generation_id,p.request_id,m.fact_fingerprint,
  app_private.end_known_source_personal_target_merge_generation_v1(
    c.app_user_id,c.workspace_id,c.project_id,p.request_id,p.generation_id,m.fact_fingerprint
  ) AS ended_at_utc FROM fixture_0120_pairs p CROSS JOIN fixture_0120_context c
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(p.generation_id) m WHERE p.pair_number = 5;
SELECT pg_temp.expect_0120_failure('23505',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_ordinary_end;
DO $ordinary_replay$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0120_ordinary_end e CROSS JOIN fixture_0120_context c
      WHERE app_private.end_known_source_personal_target_merge_generation_v1(
        c.app_user_id,c.workspace_id,c.project_id,e.request_id,e.generation_id,e.fact_fingerprint) = e.ended_at_utc)
  THEN RAISE EXCEPTION '0120 old ordinary end replay changed'; END IF;
END
$ordinary_replay$;

SELECT pg_temp.expect_0120_failure('22023',format(
  'SELECT app_private.expire_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L)',
  a,w,p,r,g)) FROM fixture_0120_context c CROSS JOIN LATERAL (VALUES
    (NULL::uuid,c.workspace_id,c.project_id,'7ef00000-0000-4000-8000-000000000201'::uuid,'7ef00000-0000-4000-8000-000000000101'::uuid),
    (c.app_user_id,NULL::uuid,c.project_id,'7ef00000-0000-4000-8000-000000000201'::uuid,'7ef00000-0000-4000-8000-000000000101'::uuid),
    (c.app_user_id,c.workspace_id,NULL::uuid,'7ef00000-0000-4000-8000-000000000201'::uuid,'7ef00000-0000-4000-8000-000000000101'::uuid),
    (c.app_user_id,c.workspace_id,c.project_id,NULL::uuid,'7ef00000-0000-4000-8000-000000000101'::uuid),
    (c.app_user_id,c.workspace_id,c.project_id,'7ef00000-0000-4000-8000-000000000201'::uuid,NULL::uuid)) bad(a,w,p,r,g);
SELECT pg_temp.expect_0120_failure('42501',format('SELECT app_private.expire_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L)',
  a,w,p,'7ef00000-0000-4000-8000-000000000201','7ef00000-0000-4000-8000-000000000101'))
FROM fixture_0120_context c CROSS JOIN fixture_0120_other o CROSS JOIN LATERAL (VALUES
  (o.app_user_id,o.workspace_id,o.project_id),(o.app_user_id,c.workspace_id,c.project_id),
  (c.app_user_id,o.workspace_id,c.project_id),(c.app_user_id,c.workspace_id,'7ef00000-0000-4000-8000-000000000090'::uuid)) bad(a,w,p);
SELECT pg_temp.expect_0120_failure('42501',$$SELECT pg_temp.fixture_0120_expire(
  '7ef00000-0000-4000-8000-000000000199','7ef00000-0000-4000-8000-000000000201')$$);
SELECT pg_temp.expect_0120_failure('22023',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_pairs WHERE pair_number = 2;

UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id IN ('7ef00000-0000-4000-8000-000000000001',
  '7ef00000-0000-4000-8000-000000000005','7ef00000-0000-4000-8000-000000000006',
  '7ef00000-0000-4000-8000-000000000013','7ef00000-0000-4000-8000-000000000015');
UPDATE app_data.promotion_targets SET created_at = transaction_timestamp() - interval '12 months'
WHERE promotion_target_id = '7ef00000-0000-4000-8000-000000000007';
UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'user_requested'
WHERE assignment_id = '7ef00000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0120_failure('42501',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_pairs WHERE pair_number = 1;
UPDATE app_data.promotion_target_assignments SET ended_at = NULL,end_reason = NULL
WHERE assignment_id = '7ef00000-0000-4000-8000-000000000002';
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE promotion_target_id = '7ef00000-0000-4000-8000-000000000016';
SELECT pg_temp.expect_0120_failure('55000',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_pairs WHERE pair_number = 8;

SAVEPOINT inconsistent_source;
SET LOCAL session_replication_role = replica;
UPDATE app_data.promotion_target_institution_relation_revisions
SET person_merge_generation_id = '7ef00000-0000-4000-8000-000000000107'
WHERE relationship_id = (SELECT relationship_id FROM fixture_0120_active_relation) AND revision_number = 1;
SET LOCAL session_replication_role = origin;
SELECT pg_temp.expect_0120_failure('55000',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_pairs WHERE pair_number = 7;
ROLLBACK TO SAVEPOINT inconsistent_source;
RELEASE SAVEPOINT inconsistent_source;

CREATE FUNCTION pg_temp.fail_0120_second_anonymization() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF NEW.promotion_target_id = '7ef00000-0000-4000-8000-000000000014' AND NEW.status = 'anonymized' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001',MESSAGE = '0120 injected second target failure';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0120_second_target_failure BEFORE UPDATE ON app_data.promotion_targets
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0120_second_anonymization();
SELECT pg_temp.expect_0120_failure('P0001',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_pairs WHERE pair_number = 7;
DROP TRIGGER fixture_0120_second_target_failure ON app_data.promotion_targets;

CREATE TEMP TABLE fixture_0120_before ON COMMIT DROP AS SELECT pg_temp.fixture_0120_state() AS state;
CREATE TEMP TABLE fixture_0120_manifest ON COMMIT DROP AS
SELECT m.* FROM app_private.personal_target_merge_known_source_manifest_v1('7ef00000-0000-4000-8000-000000000101') m;
CREATE TEMP TABLE fixture_0120_due ON COMMIT DROP AS
SELECT p.pair_number,app_data.promotion_target_review_due_at(first_target) AS first_due,
  app_data.promotion_target_review_due_at(second_target) AS second_due FROM fixture_0120_pairs p WHERE pair_number IN (1,3,4);
CREATE TEMP TABLE fixture_0120_first ON COMMIT DROP AS
SELECT pg_temp.fixture_0120_expire(generation_id,request_id) AS ended_at_utc
FROM fixture_0120_pairs WHERE pair_number = 1;
CREATE TEMP TABLE fixture_0120_replay ON COMMIT DROP AS
SELECT pg_temp.fixture_0120_expire(generation_id,request_id) AS ended_at_utc
FROM fixture_0120_pairs WHERE pair_number = 1;
DO $expiry_contract$
DECLARE before_state jsonb; ended_time timestamptz; key_name text;
BEGIN
  SELECT state INTO STRICT before_state FROM fixture_0120_before;
  SELECT ended_at_utc INTO STRICT ended_time FROM fixture_0120_first;
  IF ended_time IS NULL OR NOT isfinite(ended_time)
    OR ended_time IS DISTINCT FROM (SELECT ended_at_utc FROM fixture_0120_replay)
    OR NOT EXISTS (SELECT 1 FROM fixture_0120_due WHERE pair_number = 1 AND first_due <= ended_time AND second_due > ended_time)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 e CROSS JOIN fixture_0120_context c CROSS JOIN fixture_0120_manifest m
      WHERE e.generation_id = '7ef00000-0000-4000-8000-000000000101' AND e.actor_app_user_id = c.app_user_id
        AND e.workspace_id = c.workspace_id AND e.project_id = c.project_id AND e.request_id = '7ef00000-0000-4000-8000-000000000201'
        AND e.operation = 'personal_target_known_source_merge_expire' AND e.reason = 'retention_expired' AND e.outcome = 'ended'
        AND e.fact_count = m.fact_count AND e.fact_fingerprint = m.fact_fingerprint AND e.target_count = 2 AND e.ended_at_utc = ended_time)
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '7ef00000-0000-4000-8000-000000000101')
    OR (SELECT count(*) FROM app_data.promotion_targets
      WHERE promotion_target_id IN ('7ef00000-0000-4000-8000-000000000001','7ef00000-0000-4000-8000-000000000002')
        AND status = 'anonymized' AND phone IS NULL AND email IS NULL AND display_name = '已匿名化对象'
        AND anonymized_at = ended_time AND anonymization_reason = 'retention_expired') <> 2
    OR (SELECT count(*) FROM app_data.promotion_target_assignments
      WHERE promotion_target_id IN ('7ef00000-0000-4000-8000-000000000001','7ef00000-0000-4000-8000-000000000002')
        AND ended_at = ended_time AND end_reason = 'target_anonymized') <> 2
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events
      WHERE promotion_target_id IN ('7ef00000-0000-4000-8000-000000000001','7ef00000-0000-4000-8000-000000000002')
        AND actor_app_user_id = (SELECT app_user_id FROM fixture_0120_context)
        AND event_type = 'anonymized' AND reason = 'retention_expired' AND occurred_at = ended_time AND review_due_at IS NULL) <> 2
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id IN ('7ef00000-0000-4000-8000-000000000001','7ef00000-0000-4000-8000-000000000002')
        AND (current_lifecycle_status <> 'ended' OR current_follow_up_note IS NOT NULL OR merge_generation_id IS DISTINCT FROM '7ef00000-0000-4000-8000-000000000101'::uuid))
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions
      WHERE promotion_target_id IN ('7ef00000-0000-4000-8000-000000000001','7ef00000-0000-4000-8000-000000000002')
        AND (follow_up_note IS NOT NULL OR reason_detail IS NOT NULL OR requested_follow_up_note IS NOT NULL))
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '7ef00000-0000-4000-8000-000000000106') <> 2
  THEN RAISE EXCEPTION '0120 pair expiry/time/erasure/replay contract drift'; END IF;
  FOREACH key_name IN ARRAY ARRAY['retention_policies','contacts','contact_revisions','contact_links','generations','members','previews','activation_requests','activation_audit'] LOOP
    IF before_state->key_name IS DISTINCT FROM pg_temp.fixture_0120_state()->key_name THEN
      RAISE EXCEPTION '0120 expiry rewrote immutable history: %',key_name;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions r
      JOIN jsonb_array_elements(before_state->'relationship_revisions') old ON old->>'promotion_target_id' = r.promotion_target_id::text
        AND old->>'project_id' = r.project_id::text AND (old->>'revision_number')::integer = r.revision_number
      WHERE (to_jsonb(r) - 'follow_up_note' - 'reason_detail' - 'requested_follow_up_note')
        IS DISTINCT FROM (old - 'follow_up_note' - 'reason_detail' - 'requested_follow_up_note'))
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relation_revisions r
      JOIN jsonb_array_elements(before_state->'institution_relation_revisions') old ON old->>'relationship_id' = r.relationship_id::text
        AND (old->>'revision_number')::integer = r.revision_number WHERE to_jsonb(r) IS DISTINCT FROM old)
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships r
      JOIN jsonb_array_elements(before_state->'institution_relationships') old ON old->>'relationship_id' = r.relationship_id::text
      WHERE (to_jsonb(r) - 'role_description' - 'ended_at' - 'current_revision' - 'updated_at' - 'updated_by_app_user_id')
        IS DISTINCT FROM (old - 'role_description' - 'ended_at' - 'current_revision' - 'updated_at' - 'updated_by_app_user_id'))
    OR (SELECT count(*) FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id IN ((SELECT relationship_id FROM fixture_0120_active_relation),(SELECT relationship_id FROM fixture_0120_ended_relation))
        AND role_description = '[已匿名化]' AND ended_at IS NOT NULL AND person_merge_generation_id = '7ef00000-0000-4000-8000-000000000101'
        AND institution_merge_generation_id = '7ef00000-0000-4000-8000-000000000106') <> 2
  THEN RAISE EXCEPTION '0120 expiry rewrote original sources/bindings or omitted relationship erasure'; END IF;
END
$expiry_contract$;

SELECT pg_temp.expect_0120_failure('23505',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,'7ef00000-0000-4000-8000-000000000299'))
FROM fixture_0120_pairs WHERE pair_number = 1;
SELECT pg_temp.expect_0120_failure('23505',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,'7ef00000-0000-4000-8000-000000000201'))
FROM fixture_0120_pairs WHERE pair_number = 2;
SELECT pg_temp.expect_0120_failure('23505',format('SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,'7ef00000-0000-4000-8000-000000000201',
  '7ef00000-0000-4000-8000-000000000101',m.fact_fingerprint)) FROM fixture_0120_context c CROSS JOIN fixture_0120_manifest m;
UPDATE app_data.user_current_projects SET project_id = '7ef00000-0000-4000-8000-000000000090'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0120_context);
SELECT pg_temp.expect_0120_failure('42501',format('SELECT pg_temp.fixture_0120_expire(%L,%L)',generation_id,request_id))
FROM fixture_0120_pairs WHERE pair_number = 1;
SELECT pg_temp.expect_0120_failure('23505',format('SELECT app_private.expire_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,'7ef00000-0000-4000-8000-000000000090',p.request_id,p.generation_id))
FROM fixture_0120_context c CROSS JOIN fixture_0120_pairs p WHERE pair_number = 1;
UPDATE app_data.user_current_projects SET project_id = (SELECT project_id FROM fixture_0120_context)
WHERE app_user_id = (SELECT app_user_id FROM fixture_0120_context);
SELECT pg_temp.expect_0120_failure('55000',$$INSERT INTO app_private.personal_target_merge_active_members_v1
  SELECT promotion_target_id,generation_id,workspace_id,target_type FROM app_private.personal_target_merge_generation_members_v1
  WHERE generation_id = '7ef00000-0000-4000-8000-000000000101'$$);
SELECT pg_temp.expect_0120_failure('55000',$$UPDATE app_private.personal_target_merge_end_events_v1
  SET reason = reason WHERE generation_id = '7ef00000-0000-4000-8000-000000000101'$$);
SELECT pg_temp.expect_0120_failure('55000',$$DELETE FROM app_private.personal_target_merge_end_events_v1
  WHERE generation_id = '7ef00000-0000-4000-8000-000000000101'$$);

CREATE TEMP TABLE fixture_0120_other_expiries ON COMMIT DROP AS
SELECT p.pair_number,p.first_target,p.second_target,p.generation_id,
  pg_temp.fixture_0120_expire(p.generation_id,p.request_id) AS ended_at_utc
FROM fixture_0120_pairs p WHERE p.pair_number IN (3,4);
DO $both_and_boundary$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM fixture_0120_due WHERE pair_number = 4 AND first_due = transaction_timestamp())
    OR NOT EXISTS (SELECT 1 FROM fixture_0120_due WHERE pair_number = 3 AND first_due <= clock_timestamp() AND second_due <= clock_timestamp())
    OR EXISTS (SELECT 1 FROM fixture_0120_other_expiries e
      WHERE (SELECT count(*) FROM app_data.promotion_targets t WHERE t.promotion_target_id IN (e.first_target,e.second_target)
          AND t.status = 'anonymized' AND t.anonymized_at = e.ended_at_utc) <> 2
        OR (SELECT count(*) FROM app_data.promotion_target_retention_events r WHERE r.promotion_target_id IN (e.first_target,e.second_target)
          AND r.reason = 'retention_expired' AND r.occurred_at = e.ended_at_utc) <> 2
        OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 m WHERE m.generation_id = e.generation_id))
  THEN RAISE EXCEPTION '0120 both-due or inclusive due boundary drift'; END IF;
END
$both_and_boundary$;
DO $private_acl$
BEGIN
  IF has_function_privilege('public','app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_table_privilege('public','app_private.personal_target_merge_end_events_v1','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime','app_private.personal_target_merge_end_events_v1','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  THEN RAISE EXCEPTION '0120 expiry/end ledger ACL drift'; END IF;
END
$private_acl$;

ROLLBACK;
