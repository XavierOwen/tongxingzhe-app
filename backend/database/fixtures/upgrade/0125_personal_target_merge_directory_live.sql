\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0126_upgrade_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0125-upgrade-known-source-split-plan.example.test/auth/v1','0125-upgrade-known-source-split-plan-owner'
);
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://0125-upgrade-known-source-split-plan.example.test/auth/v1','0125-upgrade-known-source-split-plan-owner'
) WHERE is_current;
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.target_id,c.workspace_id,t.kind,t.label,'+1 773 555 0125','0125-upgrade@example.test',c.app_user_id
FROM fixture_0126_upgrade_context c CROSS JOIN (VALUES
  ('7f268000-0000-4000-8000-000000000001'::uuid,'person','0125 upgrade active source A'),
  ('7f268000-0000-4000-8000-000000000002'::uuid,'person','0125 upgrade active source B'),
  ('7f268000-0000-4000-8000-000000000003'::uuid,'institution','0125 upgrade institution'),
  ('7f268000-0000-4000-8000-000000000004'::uuid,'person','0125 upgrade ordinary end A'),
  ('7f268000-0000-4000-8000-000000000005'::uuid,'person','0125 upgrade ordinary end B'),
  ('7f268000-0000-4000-8000-000000000006'::uuid,'person','0125 upgrade expiry A'),
  ('7f268000-0000-4000-8000-000000000007'::uuid,'person','0125 upgrade expiry B')
) t(target_id,kind,label);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0126_upgrade_context c WHERE t.workspace_id = c.workspace_id;
CREATE TEMP TABLE fixture_0126_upgrade_activations ON COMMIT DROP AS
SELECT t.pair_kind,t.request_id,
  app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,t.request_id,p.preview_id,t.first_target,t.second_target,t.second_target,t.first_target
  ) AS generation_id FROM fixture_0126_upgrade_context c CROSS JOIN (VALUES
    ('active','7f268000-0000-4000-8000-000000000021'::uuid,
      '7f268000-0000-4000-8000-000000000001'::uuid,'7f268000-0000-4000-8000-000000000002'::uuid),
    ('ordinary_end','7f268000-0000-4000-8000-000000000022'::uuid,
      '7f268000-0000-4000-8000-000000000004'::uuid,'7f268000-0000-4000-8000-000000000005'::uuid),
    ('expiry','7f268000-0000-4000-8000-000000000023'::uuid,
      '7f268000-0000-4000-8000-000000000006'::uuid,'7f268000-0000-4000-8000-000000000007'::uuid)
  ) t(pair_kind,request_id,first_target,second_target)
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://0125-upgrade-known-source-split-plan.example.test/auth/v1','0125-upgrade-known-source-split-plan-owner',
  c.project_id,t.first_target,t.second_target
) p;
CREATE TEMP TABLE fixture_0126_upgrade_ordinary_end ON COMMIT DROP AS
SELECT a.generation_id,'7f268000-0000-4000-8000-000000000031'::uuid AS request_id,m.fact_fingerprint,
  app_private.end_known_source_personal_target_merge_generation_v1(
    c.app_user_id,c.workspace_id,c.project_id,'7f268000-0000-4000-8000-000000000031',a.generation_id,m.fact_fingerprint
  ) AS ended_at_utc FROM fixture_0126_upgrade_context c CROSS JOIN fixture_0126_upgrade_activations a
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(a.generation_id) m
WHERE a.pair_kind = 'ordinary_end';

UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7f268000-0000-4000-8000-000000000006';
CREATE TEMP TABLE fixture_0126_upgrade_expiry ON COMMIT DROP AS
SELECT a.generation_id,'7f268000-0000-4000-8000-000000000032'::uuid AS request_id,
  app_private.expire_known_source_personal_target_merge_generation_v1(
    c.app_user_id,c.workspace_id,c.project_id,'7f268000-0000-4000-8000-000000000032',a.generation_id
  ) AS ended_at_utc FROM fixture_0126_upgrade_context c CROSS JOIN fixture_0126_upgrade_activations a WHERE a.pair_kind = 'expiry';

CREATE TEMP TABLE fixture_0126_upgrade_contact ON COMMIT DROP AS
SELECT s.result_code FROM fixture_0126_upgrade_context c CROSS JOIN LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id,'0125-upgrade-projection-submit',1,'contact.submit.v1','0125-upgrade-projection-device','0125-upgrade-projection-contact',0,
  jsonb_build_object('contactId','0125-upgrade-projection-contact','workspaceId',c.workspace_id,'projectId',c.project_id,
    'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc',clock_timestamp() - interval '2 years',
    'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
    'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(
      jsonb_build_object('targetId','7f268000-0000-4000-8000-000000000001','targetType','person',
        'responseLevel',2,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true),
      jsonb_build_object('targetId','7f268000-0000-4000-8000-000000000002','targetType','person',
        'responseLevel',1,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
) s;
CREATE TEMP TABLE fixture_0126_upgrade_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM fixture_0126_upgrade_context c CROSS JOIN LATERAL app_data.create_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,'7f268000-0000-4000-8000-000000000001',
  '7f268000-0000-4000-8000-000000000003','employment_representative','0125 original role','0125-upgrade-projection-relation'
);


CREATE FUNCTION public.fixture_0126_business_state(requested_workspace_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $function$
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
    'fence',(SELECT to_jsonb(r) FROM app_private.personal_target_merge_generation_fence_v1 r))
$function$;


-- An existing v1 generation has no v2 field choices and may have no bound facts.
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT target_id,c.workspace_id,'person','0125 upgrade v1 source','+1 773 555 0125',c.app_user_id
FROM fixture_0126_upgrade_context c CROSS JOIN (VALUES
  ('7f268000-0000-4000-8000-000000000008'::uuid),('7f268000-0000-4000-8000-000000000009'::uuid)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT target_id,target_id,c.app_user_id,c.app_user_id FROM fixture_0126_upgrade_context c CROSS JOIN (VALUES
  ('7f268000-0000-4000-8000-000000000008'::uuid),('7f268000-0000-4000-8000-000000000009'::uuid)) t(target_id);
INSERT INTO app_private.personal_target_merge_generations_v1(generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc)
SELECT '7f268000-0000-4000-8000-000000000120',workspace_id,'person',app_user_id,clock_timestamp() FROM fixture_0126_upgrade_context;
INSERT INTO app_private.personal_target_merge_generation_members_v1(generation_id,workspace_id,target_type,promotion_target_id)
SELECT '7f268000-0000-4000-8000-000000000120',c.workspace_id,'person',target_id
FROM fixture_0126_upgrade_context c CROSS JOIN (VALUES
  ('7f268000-0000-4000-8000-000000000008'::uuid),('7f268000-0000-4000-8000-000000000009'::uuid)) t(target_id);
INSERT INTO app_private.personal_target_merge_active_members_v1(promotion_target_id,generation_id,workspace_id,target_type)
SELECT promotion_target_id,generation_id,workspace_id,target_type
FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id = '7f268000-0000-4000-8000-000000000120';

SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0126_upgrade_context),'0125-upgrade-split-plan-revise',1,'contact.revise.v1',
  '0125-upgrade-projection-device','0125-upgrade-projection-contact',1,
  (SELECT snapshot FROM app_data.contact_revisions WHERE contact_id = '0125-upgrade-projection-contact' AND revision_number = 1)
    || jsonb_build_object('targetLinks','[]'::jsonb,'reason','0125 synthetic history revision'));
SELECT result FROM fixture_0126_upgrade_context c CROSS JOIN LATERAL app_data.end_target_institution_relationship(
  c.app_user_id,c.workspace_id,c.project_id,(SELECT relationship_id FROM fixture_0126_upgrade_relation),1,'0125-upgrade-ended-relation');

CREATE FUNCTION public.fixture_0126_function_catalog() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(to_jsonb(f) ORDER BY f.oid)
  FROM pg_proc f WHERE f.oid IN (
    'app_private.read_authorized_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure,
    'app_data.read_personal_known_source_merge_split_plan_v1(text,text,uuid,uuid)'::regprocedure,
    'app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)'::regprocedure,
    'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure,
    'app_private.personal_target_merge_known_source_manifest_v1(uuid)'::regprocedure,
    'app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)'::regprocedure,
    'app_private.expire_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid)'::regprocedure,
    'app_private.read_authorized_known_source_personal_merge_projection_v1(text,text,uuid,uuid)'::regprocedure,
    'app_private.read_known_source_personal_target_merge_projection_v1(uuid,uuid,uuid,uuid)'::regprocedure,
    'app_data.read_personal_merge_projection_context_v1(text,text,uuid)'::regprocedure,
    'app_data.read_personal_known_source_merge_projection_v1(text,text,uuid,uuid)'::regprocedure,
    'app_data.promotion_target_document(uuid)'::regprocedure,
    'app_data.promotion_target_relationship_document(uuid,uuid,boolean)'::regprocedure,
    'app_data.promotion_target_institution_relation_document(uuid)'::regprocedure,
    'app_data.list_assigned_promotion_targets(uuid,uuid,uuid)'::regprocedure,
    'app_data.list_assigned_target_institution_relationships(uuid,uuid,uuid)'::regprocedure,
    'app_private.prepare_personal_target_pii_export_v1(uuid,uuid,timestamp with time zone)'::regprocedure,
    'app_data.prepare_personal_target_pii_export_v1(text,text,uuid,timestamp with time zone)'::regprocedure)
$function$;

CREATE FUNCTION public.fixture_0126_manifests(requested_workspace_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_agg(jsonb_build_object('generation_id',g.generation_id,'fact_count',m.fact_count,
    'fact_fingerprint',m.fact_fingerprint) ORDER BY g.generation_id)
  FROM app_private.personal_target_merge_generations_v1 g
  CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(g.generation_id) m
  WHERE g.workspace_id = requested_workspace_id
$function$;

SELECT app_data.read_personal_known_source_merge_projection_v1(
  'https://0125-upgrade-known-source-split-plan.example.test/auth/v1','0125-upgrade-known-source-split-plan-owner',
  c.project_id,a.generation_id)
FROM fixture_0126_upgrade_context c CROSS JOIN fixture_0126_upgrade_activations a WHERE a.pair_kind = 'active';

CREATE TABLE public.fixture_0126_upgrade_state AS
SELECT c.app_user_id,c.workspace_id,c.project_id,
  'https://0125-upgrade-known-source-split-plan.example.test/auth/v1'::text AS trusted_issuer,
  '0125-upgrade-known-source-split-plan-owner'::text AS trusted_subject,
  'https://0125-upgrade-known-source-split-plan.example.test/auth/v1'::text AS unknown_issuer,
  '0125-upgrade-never-known'::text AS unknown_subject,
  a.generation_id AS active_generation_id,
  '7f268000-0000-4000-8000-000000000120'::uuid AS v1_generation_id,
  e.generation_id AS ordinary_end_generation_id,e.request_id AS ordinary_end_request_id,
  e.fact_fingerprint AS ordinary_end_fingerprint,e.ended_at_utc AS ordinary_end_at_utc,
  (SELECT generation_id FROM fixture_0126_upgrade_expiry) AS expiry_generation_id,
  (SELECT request_id FROM fixture_0126_upgrade_expiry) AS expiry_request_id,
  (SELECT ended_at_utc FROM fixture_0126_upgrade_expiry) AS expiry_at_utc,
  (SELECT count(*) FROM app_migrations.schema_migrations) AS migration_count,
  (SELECT max(version) FROM app_migrations.schema_migrations) AS latest_migration,
  (SELECT count(*) FROM app_data.promotion_target_access_events WHERE workspace_id = c.workspace_id) AS access_event_count,
  (SELECT count(*) FROM app_data.external_identities WHERE issuer = 'https://0125-upgrade-known-source-split-plan.example.test/auth/v1') AS identity_count,
  app_private.read_known_source_personal_target_merge_projection_v1(c.app_user_id,c.workspace_id,c.project_id,a.generation_id) AS projection_document,
  app_data.read_personal_merge_projection_context_v1(
    'https://0125-upgrade-known-source-split-plan.example.test/auth/v1','0125-upgrade-known-source-split-plan-owner',c.project_id) AS context_document,
  app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id,c.workspace_id,c.project_id,a.generation_id) AS split_plan_document,
  app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id,c.workspace_id,c.project_id,'7f268000-0000-4000-8000-000000000120') AS v1_split_plan_document,
  public.fixture_0126_manifests(c.workspace_id) AS manifests,
  public.fixture_0126_business_state(c.workspace_id) AS business_state,
  public.fixture_0126_function_catalog() AS function_catalog
FROM fixture_0126_upgrade_context c CROSS JOIN fixture_0126_upgrade_activations a
CROSS JOIN fixture_0126_upgrade_ordinary_end e WHERE a.pair_kind = 'active';

DO $baseline$
DECLARE saved public.fixture_0126_upgrade_state%ROWTYPE;
BEGIN
  SELECT * INTO STRICT saved FROM public.fixture_0126_upgrade_state;
  IF saved.migration_count <> 124 OR saved.latest_migration IS DISTINCT FROM '0125_personal_target_authorized_merge_split_plan'
    OR to_regprocedure('app_private.read_authorized_personal_merge_directory_v1(text,text,uuid,uuid)') IS NOT NULL
    OR to_regprocedure('app_data.read_personal_merge_directory_v1(text,text,uuid,uuid)') IS NOT NULL
    OR saved.projection_document IS NULL OR saved.context_document IS NULL
    OR jsonb_array_length(saved.function_catalog) <> 18
    OR jsonb_array_length(saved.manifests) <> 4
    OR saved.identity_count <> 1
    OR (SELECT fact_count FROM app_private.personal_target_merge_known_source_manifest_v1(saved.active_generation_id)) <> 9
    OR (SELECT fact_count FROM app_private.personal_target_merge_known_source_manifest_v1(saved.v1_generation_id)) <> 0
    OR NOT EXISTS (SELECT 1 FROM app_data.contacts WHERE contact_id = '0125-upgrade-projection-contact' AND current_revision = 2)
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = (SELECT relationship_id FROM fixture_0126_upgrade_relation) AND ended_at IS NOT NULL)
    OR EXISTS (SELECT 1 FROM app_data.external_identities WHERE issuer = saved.unknown_issuer AND subject = saved.unknown_subject)
  THEN RAISE EXCEPTION '0125→0126 live upgrade baseline drift'; END IF;
END
$baseline$;

COMMIT;
