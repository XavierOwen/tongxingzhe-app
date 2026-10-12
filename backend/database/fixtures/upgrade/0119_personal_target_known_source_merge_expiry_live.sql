\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0120_upgrade_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0119-upgrade-known-source-expiry.example.test/auth/v1','0119-upgrade-known-source-expiry-owner'
);
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0119-upgrade-known-source-expiry.example.test/auth/v1','0119-upgrade-known-source-expiry-owner'
) WHERE is_current;
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,t.kind,t.label,'+1 773 555 0120','0120-upgrade@example.test',c.app_user_id
FROM fixture_0120_upgrade_context c CROSS JOIN (VALUES
  ('7efa0000-0000-4000-8000-000000000001'::uuid,'person','0119 upgrade active source A'),
  ('7efa0000-0000-4000-8000-000000000002'::uuid,'person','0119 upgrade active source B'),
  ('7efa0000-0000-4000-8000-000000000003'::uuid,'institution','0119 upgrade institution'),
  ('7efa0000-0000-4000-8000-000000000004'::uuid,'person','0119 upgrade ordinary end A'),
  ('7efa0000-0000-4000-8000-000000000005'::uuid,'person','0119 upgrade ordinary end B')
) t(target_id,kind,label);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0120_upgrade_context c WHERE t.workspace_id = c.workspace_id;
CREATE TEMP TABLE fixture_0120_upgrade_activations ON COMMIT DROP AS
SELECT t.pair_kind,t.request_id,
  app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,t.request_id,p.preview_id,t.first_target,t.first_target,t.second_target,t.first_target
  ) AS generation_id FROM fixture_0120_upgrade_context c CROSS JOIN (VALUES
    ('active','7efa0000-0000-4000-8000-000000000021'::uuid,
      '7efa0000-0000-4000-8000-000000000001'::uuid,'7efa0000-0000-4000-8000-000000000002'::uuid),
    ('ordinary_end','7efa0000-0000-4000-8000-000000000022'::uuid,
      '7efa0000-0000-4000-8000-000000000004'::uuid,'7efa0000-0000-4000-8000-000000000005'::uuid)
  ) t(pair_kind,request_id,first_target,second_target)
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0119-upgrade-known-source-expiry.example.test/auth/v1','0119-upgrade-known-source-expiry-owner',
  c.project_id,t.first_target,t.second_target
) p;
CREATE TEMP TABLE fixture_0120_upgrade_ordinary_end ON COMMIT DROP AS
SELECT a.generation_id,'7efa0000-0000-4000-8000-000000000031'::uuid AS request_id,m.fact_fingerprint,
  app_private.end_known_source_personal_target_merge_generation_v1(
    c.app_user_id,c.workspace_id,c.project_id,'7efa0000-0000-4000-8000-000000000031',a.generation_id,m.fact_fingerprint
  ) AS ended_at_utc FROM fixture_0120_upgrade_context c CROSS JOIN fixture_0120_upgrade_activations a
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(a.generation_id) m
WHERE a.pair_kind = 'ordinary_end';

CREATE TEMP TABLE fixture_0120_upgrade_contact ON COMMIT DROP AS
SELECT s.result_code FROM fixture_0120_upgrade_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id,'0119-upgrade-expiry-submit',1,'contact.submit.v1','0119-upgrade-expiry-device','0119-upgrade-expiry-contact',0,
  jsonb_build_object('contactId','0119-upgrade-expiry-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
    'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc',clock_timestamp() - interval '2 years',
    'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
    'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(
      jsonb_build_object('targetId','7efa0000-0000-4000-8000-000000000001','targetType','person',
        'responseLevel',2,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true),
      jsonb_build_object('targetId','7efa0000-0000-4000-8000-000000000002','targetType','person',
        'responseLevel',1,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
) s;
CREATE TEMP TABLE fixture_0120_upgrade_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM fixture_0120_upgrade_context c CROSS JOIN LATERAL app_data.create_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,'7efa0000-0000-4000-8000-000000000001',
  '7efa0000-0000-4000-8000-000000000003','employment_representative','0119 original role','0119-upgrade-expiry-relation'
);

CREATE TABLE public.fixture_0120_upgrade_state AS
SELECT
  c.app_user_id,c.workspace_id,c.project_id,
  (SELECT generation_id FROM fixture_0120_upgrade_activations WHERE pair_kind = 'active') AS active_generation_id,
  e.generation_id AS ordinary_end_generation_id,e.request_id AS ordinary_end_request_id,
  e.fact_fingerprint AS ordinary_end_fingerprint,e.ended_at_utc AS ordinary_end_at_utc,
  p.oid AS end_function_oid,p.proowner AS end_function_owner,p.proacl AS end_function_acl,p.proconfig AS end_function_config,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
  (SELECT max(version) FROM app_migrations.schema_migrations) AS latest_migration,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r) AS targets,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_data.promotion_target_assignments r) AS assignments,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,event_id) FROM app_data.promotion_target_retention_events r) AS retention_events,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.promotion_target_retention_policies r) AS retention_policies,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id) FROM app_data.contacts r) AS contacts,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number) FROM app_data.contact_revisions r) AS contact_revisions,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number,promotion_target_id) FROM app_data.contact_target_links r) AS contact_links,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id) FROM app_data.promotion_target_project_relationships r) AS project_relationships,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id,revision_number) FROM app_data.promotion_target_relationship_revisions r) AS relationship_revisions,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id) FROM app_data.promotion_target_institution_relationships r) AS institution_relationships,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id,revision_number) FROM app_data.promotion_target_institution_relation_revisions r) AS institution_relation_revisions,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY preview_id) FROM app_private.personal_target_pair_preview_receipts r) AS preview_receipts,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_generations_v1 r) AS generations,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id,promotion_target_id) FROM app_private.personal_target_merge_generation_members_v1 r) AS generation_members,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_private.personal_target_merge_active_members_v1 r) AS active_members,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_requests_v1 r) AS activation_requests,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_audit_v1 r) AS activation_audit,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_private.personal_target_assignment_end_events_v1 r) AS assignment_end_events,
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_end_events_v1 r) AS end_events
FROM fixture_0120_upgrade_context c CROSS JOIN fixture_0120_upgrade_ordinary_end e CROSS JOIN pg_proc p
WHERE p.oid = 'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure;

DO $baseline$
DECLARE active_generation uuid;
BEGIN
  SELECT active_generation_id INTO STRICT active_generation FROM public.fixture_0120_upgrade_state;
  IF (SELECT migration_count FROM public.fixture_0120_upgrade_state) <> 118
    OR (SELECT latest_migration FROM public.fixture_0120_upgrade_state) IS DISTINCT FROM '0119_personal_target_known_source_merge_end'
    OR to_regprocedure('app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)') IS NOT NULL
    OR (SELECT result_code FROM fixture_0120_upgrade_contact) IS DISTINCT FROM 'accepted'
    OR (SELECT fact_count FROM app_private.personal_target_merge_known_source_manifest_v1(active_generation)) <> 8
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = active_generation) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 r CROSS JOIN fixture_0120_upgrade_ordinary_end e
      WHERE r.generation_id = e.generation_id AND r.request_id = e.request_id
        AND r.operation = 'personal_target_known_source_merge_end' AND r.reason = 'known_source_split' AND r.ended_at_utc = e.ended_at_utc)
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships r
      WHERE r.relationship_id = (SELECT relationship_id FROM fixture_0120_upgrade_relation)
        AND r.person_merge_generation_id = active_generation AND r.institution_merge_generation_id IS NULL)
  THEN RAISE EXCEPTION '0119→0120 live upgrade baseline drift'; END IF;
END
$baseline$;

COMMIT;
