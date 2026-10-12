\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

DO $fixture$
DECLARE
  context_row record;
  preview_id uuid;
  generation_id uuid;
  relation_id uuid;
  result_code text;
BEGIN
  SELECT * INTO STRICT context_row FROM app_data.bootstrap_personal_context(
    'https://0118-upgrade-known-source-end.example.test/auth/v1', '0118-upgrade-known-source-end-owner'
  );
  PERFORM 1 FROM app_data.list_personal_project_contexts(
    'https://0118-upgrade-known-source-end.example.test/auth/v1', '0118-upgrade-known-source-end-owner'
  ) WHERE is_current;
  INSERT INTO app_data.promotion_targets(
    promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
  ) VALUES
    ('7eea0000-0000-4000-8000-000000000001',context_row.workspace_id,'person',
      '0118 upgrade source A','+1 773 555 0119','0119-a@example.test',context_row.app_user_id),
    ('7eea0000-0000-4000-8000-000000000002',context_row.workspace_id,'person',
      '0118 upgrade source B','+1 773 555 0119','0119-b@example.test',context_row.app_user_id),
    ('7eea0000-0000-4000-8000-000000000003',context_row.workspace_id,'institution',
      '0118 upgrade institution',NULL,NULL,context_row.app_user_id);
  INSERT INTO app_data.promotion_target_assignments(
    assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id
  ) VALUES
    ('7eea0000-0000-4000-8000-000000000011','7eea0000-0000-4000-8000-000000000001',context_row.app_user_id,context_row.app_user_id),
    ('7eea0000-0000-4000-8000-000000000012','7eea0000-0000-4000-8000-000000000002',context_row.app_user_id,context_row.app_user_id),
    ('7eea0000-0000-4000-8000-000000000013','7eea0000-0000-4000-8000-000000000003',context_row.app_user_id,context_row.app_user_id);
  SELECT p.preview_id INTO STRICT preview_id FROM app_data.preview_personal_target_pair_v1(
    'https://0118-upgrade-known-source-end.example.test/auth/v1','0118-upgrade-known-source-end-owner',
    context_row.project_id,'7eea0000-0000-4000-8000-000000000001','7eea0000-0000-4000-8000-000000000002'
  ) p;
  generation_id := app_private.activate_personal_target_merge_generation_v2(
    context_row.app_user_id,context_row.project_id,'7eea0000-0000-4000-8000-000000000021',preview_id,
    '7eea0000-0000-4000-8000-000000000001','7eea0000-0000-4000-8000-000000000001',
    '7eea0000-0000-4000-8000-000000000002','7eea0000-0000-4000-8000-000000000001'
  );
  SELECT s.result_code INTO STRICT result_code FROM app_data.apply_contact_submit_v3(
    context_row.app_user_id,'0118-upgrade-end-submit',1,'contact.submit.v1','0118-upgrade-end-device',
    '0118-upgrade-end-contact',0,jsonb_build_object(
      'contactId','0118-upgrade-end-contact','workspaceId',context_row.workspace_id,
      'projectId',context_row.project_id,'questionnaireVersionId',context_row.questionnaire_version_id,
      'occurredAtUtc','2030-03-01T12:00:00Z','occurredTimeZone','America/Chicago',
      'channel','video_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(
        jsonb_build_object('targetId','7eea0000-0000-4000-8000-000000000001','targetType','person',
          'responseLevel',2,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true),
        jsonb_build_object('targetId','7eea0000-0000-4000-8000-000000000002','targetType','person',
          'responseLevel',1,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true)
      )
    )
  ) s;
  IF result_code <> 'accepted' THEN RAISE EXCEPTION '0118 upgrade contact was not accepted'; END IF;
  SELECT (r.result->'relationship'->>'relationship_id')::uuid INTO STRICT relation_id
  FROM app_data.create_target_institution_relationship(
    context_row.app_user_id,context_row.workspace_id,context_row.project_id,
    '7eea0000-0000-4000-8000-000000000001','7eea0000-0000-4000-8000-000000000003',
    'employment_representative','0118 original role','0118-upgrade-end-relation'
  ) r;
  IF (SELECT count(*) FROM app_data.contact_target_links l WHERE l.merge_generation_id = generation_id) <> 2
    OR (SELECT count(*) FROM app_data.promotion_target_project_relationships r WHERE r.merge_generation_id = generation_id) <> 2
    OR (SELECT count(*) FROM app_data.promotion_target_relationship_revisions r WHERE r.merge_generation_id = generation_id) <> 2
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships r
      WHERE r.relationship_id = relation_id AND r.person_merge_generation_id = generation_id AND r.institution_merge_generation_id IS NULL)
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relation_revisions r
      WHERE r.relationship_id = relation_id AND r.person_merge_generation_id = generation_id AND r.institution_merge_generation_id IS NULL)
  THEN RAISE EXCEPTION '0118 upgrade five original-source fact classes missing'; END IF;
END
$fixture$;

CREATE TABLE public.fixture_0119_upgrade_state AS
SELECT
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
  (SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_private.personal_target_assignment_end_events_v1 r) AS assignment_end_events;

DO $baseline$
BEGIN
  IF (SELECT count(*) FROM public.fixture_0119_upgrade_state) <> 1
    OR (SELECT migration_count FROM public.fixture_0119_upgrade_state) <> 117
    OR (SELECT latest_migration FROM public.fixture_0119_upgrade_state) IS DISTINCT FROM '0118_personal_target_assignment_end'
    OR to_regclass('app_private.personal_target_merge_end_events_v1') IS NOT NULL
    OR to_regprocedure('app_private.personal_target_merge_known_source_manifest_v1(uuid)') IS NOT NULL
    OR to_regprocedure('app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)') IS NOT NULL
    OR coalesce((SELECT jsonb_array_length(activation_requests) FROM public.fixture_0119_upgrade_state),0) < 1
    OR coalesce((SELECT jsonb_array_length(activation_audit) FROM public.fixture_0119_upgrade_state),0) < 1
    OR coalesce((SELECT jsonb_array_length(contact_links) FROM public.fixture_0119_upgrade_state),0) < 2
    OR coalesce((SELECT jsonb_array_length(institution_relation_revisions) FROM public.fixture_0119_upgrade_state),0) < 1
  THEN RAISE EXCEPTION '0118→0119 live upgrade baseline drift'; END IF;
END
$baseline$;

COMMIT;
