\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0124_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0124.example.test', 'owner'
);
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://synthetic-0124.example.test', 'owner'
) WHERE is_current;
CREATE TEMP TABLE fixture_0124_other_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0124.example.test','other-owner');
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://synthetic-0124.example.test','other-owner'
) WHERE is_current;

CREATE FUNCTION pg_temp.fixture_0124_payload(contact_id text, links jsonb)
RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'contactId', contact_id, 'workspaceId', workspace_id, 'projectId', project_id,
    'questionnaireVersionId', questionnaire_version_id,
    'reason', 'synthetic revision', 'occurredAtUtc', clock_timestamp() - interval '2 days',
    'occurredTimeZone', 'America/Chicago', 'channel', 'video_call',
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 2, 'interestLevel', 2, 'answers', '[]'::jsonb, 'targetLinks', links
  ) FROM fixture_0124_context
$function$;

CREATE TEMP TABLE fixture_0124_targets ON COMMIT DROP AS
SELECT id::uuid AS target_id, kind, label
FROM (VALUES
  ('7eb00000-0000-4000-8000-000000000001', 'person', '0124 person A'),
  ('7eb00000-0000-4000-8000-000000000002', 'person', '0124 person B'),
  ('7eb00000-0000-4000-8000-000000000003', 'institution', '0124 institution A'),
  ('7eb00000-0000-4000-8000-000000000004', 'institution', '0124 institution B'),
  ('7eb00000-0000-4000-8000-000000000005', 'institution', '0124 unmerged institution')
) t(id, kind, label);
INSERT INTO app_data.promotion_targets(
  promotion_target_id, workspace_id, target_type, display_name, phone,
  created_by_app_user_id, created_at
)
SELECT t.target_id, c.workspace_id, t.kind, t.label, '+1 312 555 0124',
  c.app_user_id, clock_timestamp() FROM fixture_0124_targets t CROSS JOIN fixture_0124_context c;
INSERT INTO app_data.promotion_target_assignments(
  assignment_id, promotion_target_id, app_user_id, assigned_by_app_user_id
)
SELECT t.target_id, t.target_id, c.app_user_id, c.app_user_id
FROM fixture_0124_targets t CROSS JOIN fixture_0124_context c;
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '7eb00000-0000-4000-8000-000000000090', workspace_id, '0124 alternate project'
FROM fixture_0124_context;

CREATE TEMP TABLE fixture_0124_generations ON COMMIT DROP AS
SELECT id::uuid AS generation_id, kind
FROM (VALUES
  ('7eb00000-0000-4000-8000-000000000101', 'person'),
  ('7eb00000-0000-4000-8000-000000000102', 'person'),
  ('7eb00000-0000-4000-8000-000000000103', 'institution')
) g(id, kind);
INSERT INTO app_private.personal_target_merge_generations_v1(
  generation_id, workspace_id, target_type, created_by_app_user_id, activated_at_utc
)
SELECT g.generation_id, c.workspace_id, g.kind, c.app_user_id, clock_timestamp()
FROM fixture_0124_generations g CROSS JOIN fixture_0124_context c;
INSERT INTO app_private.personal_target_merge_generation_members_v1(
  generation_id, workspace_id, target_type, promotion_target_id
)
SELECT g.generation_id, c.workspace_id, g.kind, t.target_id
FROM fixture_0124_generations g JOIN fixture_0124_targets t ON t.kind = g.kind
CROSS JOIN fixture_0124_context c
WHERE t.target_id <> '7eb00000-0000-4000-8000-000000000005';
INSERT INTO app_private.personal_target_merge_active_members_v1(
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT promotion_target_id, generation_id, workspace_id, target_type
FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id IN ('7eb00000-0000-4000-8000-000000000101', '7eb00000-0000-4000-8000-000000000103');

CREATE TEMP TABLE fixture_0124_links ON COMMIT DROP AS
SELECT jsonb_agg(jsonb_build_object(
  'targetId', target_id, 'targetType', kind, 'responseLevel', 2,
  'followUpConsent', 'yes', 'institutionRepresentativeConfirmed', kind = 'institution',
  'confirmStageZero', true
) ORDER BY target_id) AS links FROM fixture_0124_targets
WHERE kind = 'person';
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0124_context), '0124-history-submit', 1,
  'contact.submit.v1', '0124-device', '0124-history-contact', 0,
  pg_temp.fixture_0124_payload('0124-history-contact', (SELECT links FROM fixture_0124_links))
);
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE generation_id = '7eb00000-0000-4000-8000-000000000101';
INSERT INTO app_private.personal_target_merge_active_members_v1(
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT promotion_target_id, generation_id, workspace_id, target_type
FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id = '7eb00000-0000-4000-8000-000000000102';
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0124_context), '0124-active-submit', 1,
  'contact.submit.v1', '0124-device', '0124-active-contact', 0,
  pg_temp.fixture_0124_payload('0124-active-contact', (SELECT links FROM fixture_0124_links))
);
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM fixture_0124_context), (SELECT workspace_id FROM fixture_0124_context),
  (SELECT project_id FROM fixture_0124_context), '7eb00000-0000-4000-8000-000000000001',
  1, 1, 'active', 'synthetic note', 'progress_update', NULL, '0124-active-project', NULL
);
CREATE TEMP TABLE fixture_0124_dual_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0124_context), (SELECT workspace_id FROM fixture_0124_context),
  (SELECT project_id FROM fixture_0124_context), '7eb00000-0000-4000-8000-000000000001',
  '7eb00000-0000-4000-8000-000000000003', 'employment_representative', 'synthetic role', '0124-dual-create'
);
CREATE TEMP TABLE fixture_0124_ended_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0124_context), (SELECT workspace_id FROM fixture_0124_context),
  (SELECT project_id FROM fixture_0124_context), '7eb00000-0000-4000-8000-000000000002',
  '7eb00000-0000-4000-8000-000000000005', 'membership_affiliation', 'ended role', '0124-ended-create'
);
SELECT result FROM app_data.end_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0124_context), (SELECT workspace_id FROM fixture_0124_context),
  (SELECT project_id FROM fixture_0124_context), (SELECT relationship_id FROM fixture_0124_ended_relation),
  1, '0124-ended-end'
);

-- A link-free revision changes the contact head, not historical attribution.
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0124_context), '0124-empty-links-revise', 1,
  'contact.revise.v1', '0124-device', '0124-active-contact', 1,
  pg_temp.fixture_0124_payload('0124-active-contact', '[]'::jsonb)
);

-- Both old and current contact revisions remain in the bound fact catalog.
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0124_context),'0124-restored-links-revise',1,'contact.revise.v1','0124-device',
  '0124-active-contact',2,pg_temp.fixture_0124_payload('0124-active-contact',(SELECT links FROM fixture_0124_links)));
-- Historical attribution is not restricted to the requested current project.
INSERT INTO app_data.promotion_target_project_relationships(
  promotion_target_id,project_id,current_stage,established_by_app_user_id,established_at,updated_by_app_user_id,updated_at)
SELECT '7eb00000-0000-4000-8000-000000000001','7eb00000-0000-4000-8000-000000000090',2,
  app_user_id,clock_timestamp(),app_user_id,clock_timestamp() FROM fixture_0124_context;

INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT target_id,c.workspace_id,'person','0124 empty source','+1 312 555 0124',c.app_user_id
FROM fixture_0124_context c CROSS JOIN (VALUES
  ('7eb00000-0000-4000-8000-000000000006'::uuid),('7eb00000-0000-4000-8000-000000000007'::uuid)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT target_id,target_id,c.app_user_id,c.app_user_id FROM fixture_0124_context c CROSS JOIN (VALUES
  ('7eb00000-0000-4000-8000-000000000006'::uuid),('7eb00000-0000-4000-8000-000000000007'::uuid)) t(target_id);
CREATE TEMP TABLE fixture_0124_v2 ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  c.app_user_id,c.project_id,'7eb00000-0000-4000-8000-000000000106',p.preview_id,
  '7eb00000-0000-4000-8000-000000000006','7eb00000-0000-4000-8000-000000000007',
  '7eb00000-0000-4000-8000-000000000006','7eb00000-0000-4000-8000-000000000007') AS generation_id
FROM fixture_0124_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://synthetic-0124.example.test','owner',c.project_id,
  '7eb00000-0000-4000-8000-000000000006','7eb00000-0000-4000-8000-000000000007') p;
INSERT INTO app_data.app_users(app_user_id) VALUES ('7eb00000-0000-4000-8000-000000000098');

CREATE FUNCTION pg_temp.fixture_0124_workspace_state(requested_workspace_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $function$
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



CREATE FUNCTION pg_temp.fixture_0124_state() RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'workspaces',(SELECT jsonb_agg(pg_temp.fixture_0124_workspace_state(workspace_id) ORDER BY workspace_id)
      FROM (SELECT workspace_id FROM fixture_0124_context UNION SELECT workspace_id FROM fixture_0124_other_context) c),
    'access',(SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_access_events r
      WHERE workspace_id IN (SELECT workspace_id FROM fixture_0124_context UNION SELECT workspace_id FROM fixture_0124_other_context)),
    'identities',(SELECT jsonb_agg(to_jsonb(r) ORDER BY external_identity_id) FROM app_data.external_identities r
      WHERE issuer = 'https://synthetic-0124.example.test'),
    'unknown_user',(SELECT to_jsonb(r) FROM app_data.app_users r WHERE app_user_id = '7eb00000-0000-4000-8000-000000000099'))
$function$;
CREATE FUNCTION pg_temp.fixture_0124_read(generation_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.fixture_0124_state(); document jsonb;
BEGIN
  SELECT app_private.read_known_source_personal_merge_split_plan_v1(app_user_id,workspace_id,project_id,generation_id)
  INTO STRICT document FROM fixture_0124_context;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0124_state() THEN RAISE EXCEPTION '0124 successful plan read left writes'; END IF;
  RETURN document;
END
$function$;
CREATE FUNCTION pg_temp.expect_0124_failure(expected_state text,statement_text text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0124_state();
BEGIN
  BEGIN EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM expected_state THEN RAISE EXCEPTION '0124 expected %, got %',expected_state,actual_state; END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0124_state() THEN RAISE EXCEPTION '0124 rejected request left writes'; END IF;
END
$function$;
-- This independent oracle retains the seven original 0119 metadata variants.
CREATE FUNCTION pg_temp.fixture_0124_expected_facts(requested_generation_id uuid)
RETURNS TABLE(source_target_id uuid,metadata jsonb) LANGUAGE sql STABLE AS $function$
  WITH facts AS (
    SELECT
      link.promotion_target_id AS source_target_id,
      jsonb_build_array('contact_link', link.contact_id,
        link.revision_number, link.promotion_target_id) AS metadata
    FROM app_data.contact_target_links AS link
    WHERE link.merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.promotion_target_id,
      jsonb_build_array('project_relationship', relation.promotion_target_id,
        relation.project_id, relation.current_revision,
        to_char(relation.updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
    FROM app_data.promotion_target_project_relationships AS relation
    WHERE relation.merge_generation_id = requested_generation_id
    UNION ALL
    SELECT revision.promotion_target_id,
      jsonb_build_array('project_revision', revision.promotion_target_id,
        revision.project_id, revision.revision_number)
    FROM app_data.promotion_target_relationship_revisions AS revision
    WHERE revision.merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.person_target_id,
      jsonb_build_array('institution_relationship_person', relation.relationship_id,
        relation.person_target_id, relation.institution_target_id,
        relation.current_revision,
        to_char(relation.updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        relation.institution_merge_generation_id)
    FROM app_data.promotion_target_institution_relationships AS relation
    WHERE relation.person_merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.institution_target_id,
      jsonb_build_array('institution_relationship_institution', relation.relationship_id,
        relation.person_target_id, relation.institution_target_id,
        relation.current_revision,
        to_char(relation.updated_at AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        relation.person_merge_generation_id)
    FROM app_data.promotion_target_institution_relationships AS relation
    WHERE relation.institution_merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.person_target_id,
      jsonb_build_array('institution_revision_person', revision.relationship_id,
        revision.revision_number, relation.person_target_id,
        relation.institution_target_id, revision.institution_merge_generation_id)
    FROM app_data.promotion_target_institution_relation_revisions AS revision
    JOIN app_data.promotion_target_institution_relationships AS relation
      USING (relationship_id)
    WHERE revision.person_merge_generation_id = requested_generation_id
    UNION ALL
    SELECT relation.institution_target_id,
      jsonb_build_array('institution_revision_institution', revision.relationship_id,
        revision.revision_number, relation.person_target_id,
        relation.institution_target_id, revision.person_merge_generation_id)
    FROM app_data.promotion_target_institution_relation_revisions AS revision
    JOIN app_data.promotion_target_institution_relationships AS relation
      USING (relationship_id)
    WHERE revision.institution_merge_generation_id = requested_generation_id
  )
  SELECT source_target_id,metadata FROM facts
$function$;

CREATE TEMP TABLE fixture_0124_documents ON COMMIT DROP AS
SELECT generation_id,pg_temp.fixture_0124_read(generation_id) AS document
FROM fixture_0124_generations WHERE generation_id IN (
  '7eb00000-0000-4000-8000-000000000102','7eb00000-0000-4000-8000-000000000103')
UNION ALL SELECT generation_id,pg_temp.fixture_0124_read(generation_id) FROM fixture_0124_v2;

DO $plan_contract$
DECLARE row_value record; expected_facts jsonb; expected_metadata jsonb; expected_count bigint; expected_fingerprint text;
BEGIN
  FOR row_value IN SELECT * FROM fixture_0124_documents LOOP
    SELECT coalesce(jsonb_agg(jsonb_build_object('source_target_id',source_target_id,'metadata',metadata) ORDER BY metadata::text),'[]'::jsonb),
      coalesce(jsonb_agg(metadata ORDER BY metadata::text),'[]'::jsonb),count(*)
    INTO expected_facts,expected_metadata,expected_count FROM pg_temp.fixture_0124_expected_facts(row_value.generation_id);
    expected_fingerprint := encode(sha256(convert_to(jsonb_build_object(
      'contract','personal_target_merge_known_source_manifest_v1','generation_id',row_value.generation_id,'facts',expected_metadata)::text,'UTF8')),'hex');
    IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(row_value.document) k) IS DISTINCT FROM ARRAY[
        'fact_count','fact_fingerprint','facts','generation_id','member_target_ids','project_id','review_due_at_utc','target_type','workspace_id']
      OR row_value.document->>'generation_id' IS DISTINCT FROM row_value.generation_id::text
      OR row_value.document->>'workspace_id' IS DISTINCT FROM (SELECT workspace_id::text FROM fixture_0124_context)
      OR row_value.document->>'project_id' IS DISTINCT FROM (SELECT project_id::text FROM fixture_0124_context)
      OR row_value.document->>'target_type' IS DISTINCT FROM (SELECT target_type FROM app_private.personal_target_merge_generations_v1 WHERE generation_id = row_value.generation_id)
      OR row_value.document->'member_target_ids' IS DISTINCT FROM (
        SELECT jsonb_agg(promotion_target_id ORDER BY promotion_target_id) FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id = row_value.generation_id)
      OR row_value.document->>'review_due_at_utc' IS DISTINCT FROM (
        SELECT to_char(min(app_data.promotion_target_review_due_at(promotion_target_id)) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id = row_value.generation_id)
      OR row_value.document->'facts' IS DISTINCT FROM expected_facts
      OR (row_value.document->>'fact_count')::bigint <> expected_count
      OR row_value.document->>'fact_fingerprint' IS DISTINCT FROM expected_fingerprint
      OR row_value.document->>'fact_fingerprint' IS DISTINCT FROM (
        SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1(row_value.generation_id))
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(row_value.document->'facts') f
        WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(f) k) IS DISTINCT FROM ARRAY['metadata','source_target_id'])
      OR position('+1 312 555 0124' IN row_value.document::text) > 0
      OR position('synthetic note' IN row_value.document::text) > 0 OR position('ended role' IN row_value.document::text) > 0
    THEN RAISE EXCEPTION '0124 exact source metadata, original fingerprint or PII-free plan contract drift'; END IF;
  END LOOP;
  IF (SELECT array_agg(DISTINCT f->'metadata'->>0 ORDER BY f->'metadata'->>0)
      FROM fixture_0124_documents d CROSS JOIN LATERAL jsonb_array_elements(d.document->'facts') f)
    IS DISTINCT FROM ARRAY['contact_link','institution_relationship_institution','institution_relationship_person',
      'institution_revision_institution','institution_revision_person','project_relationship','project_revision']
    OR NOT EXISTS (SELECT 1 FROM fixture_0124_documents WHERE generation_id = (SELECT generation_id FROM fixture_0124_v2)
      AND document->'facts' = '[]'::jsonb AND document->>'fact_count' = '0')
    OR (SELECT count(*) FROM pg_temp.fixture_0124_expected_facts('7eb00000-0000-4000-8000-000000000102')
      WHERE metadata->>0 = 'contact_link' AND metadata->>1 = '0124-active-contact' AND metadata->>2 IN ('1','3')) <> 4
    OR NOT EXISTS (SELECT 1 FROM pg_temp.fixture_0124_expected_facts('7eb00000-0000-4000-8000-000000000102')
      WHERE metadata->>0 = 'project_relationship' AND metadata->>2 = '7eb00000-0000-4000-8000-000000000090')
    OR NOT EXISTS (SELECT 1 FROM pg_temp.fixture_0124_expected_facts('7eb00000-0000-4000-8000-000000000102')
      WHERE metadata->>0 = 'institution_relationship_person' AND metadata->>1 = (SELECT relationship_id::text FROM fixture_0124_ended_relation))
  THEN RAISE EXCEPTION '0124 seven variants, historical/current revision, cross-project, ended relation or empty v2 fixture missing'; END IF;
END
$plan_contract$;

SELECT pg_temp.expect_0124_failure('22023',format('SELECT app_private.read_known_source_personal_merge_split_plan_v1(%L,%L,%L,%L)',a,w,p,g))
FROM fixture_0124_context c CROSS JOIN LATERAL (VALUES
  (NULL::uuid,c.workspace_id,c.project_id,'7eb00000-0000-4000-8000-000000000102'::uuid),
  (c.app_user_id,NULL::uuid,c.project_id,'7eb00000-0000-4000-8000-000000000102'::uuid),
  (c.app_user_id,c.workspace_id,NULL::uuid,'7eb00000-0000-4000-8000-000000000102'::uuid),
  (c.app_user_id,c.workspace_id,c.project_id,NULL::uuid)) bad(a,w,p,g);
SELECT pg_temp.expect_0124_failure('42501',format('SELECT app_private.read_known_source_personal_merge_split_plan_v1(%L,%L,%L,%L)',a,w,p,'7eb00000-0000-4000-8000-000000000102'))
FROM fixture_0124_context c CROSS JOIN fixture_0124_other_context o CROSS JOIN LATERAL (VALUES
  (o.app_user_id,o.workspace_id,o.project_id),(o.app_user_id,c.workspace_id,c.project_id),
  (c.app_user_id,o.workspace_id,c.project_id),(c.app_user_id,c.workspace_id,'7eb00000-0000-4000-8000-000000000090'::uuid),
  ('7eb00000-0000-4000-8000-000000000099'::uuid,c.workspace_id,c.project_id)) bad(a,w,p);
SELECT pg_temp.expect_0124_failure('42501',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000199')$$);
SELECT pg_temp.expect_0124_failure('55000',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000101')$$);

DO $authorization_gates$
DECLARE change_statement text;
BEGIN
  FOREACH change_statement IN ARRAY ARRAY[
    $$UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = (SELECT app_user_id FROM fixture_0124_context)$$,
    $$UPDATE app_data.app_users SET status = 'deleted' WHERE app_user_id = (SELECT app_user_id FROM fixture_0124_context)$$,
    $$UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = (SELECT workspace_id FROM fixture_0124_context)$$,
    $$UPDATE app_data.workspaces SET personal_owner_app_user_id = '7eb00000-0000-4000-8000-000000000098' WHERE workspace_id = (SELECT workspace_id FROM fixture_0124_context)$$,
    $$DELETE FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0124_context)$$,
    $$UPDATE app_data.user_current_projects SET project_id = '7eb00000-0000-4000-8000-000000000090' WHERE app_user_id = (SELECT app_user_id FROM fixture_0124_context)$$,
    $$UPDATE app_data.projects SET status = 'archived' WHERE project_id = (SELECT project_id FROM fixture_0124_context)$$,
    $$UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'user_requested' WHERE assignment_id = '7eb00000-0000-4000-8000-000000000002'$$,
    $$UPDATE app_data.promotion_targets SET status = 'anonymized',phone = NULL,email = NULL,anonymized_at = clock_timestamp(),anonymization_reason = 'withdrawal'
      WHERE promotion_target_id = '7eb00000-0000-4000-8000-000000000002'$$
  ] LOOP
    BEGIN
      EXECUTE change_statement;
      PERFORM pg_temp.expect_0124_failure('42501',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000102')$$);
      RAISE EXCEPTION USING ERRCODE = 'ZX124',MESSAGE = 'rollback synthetic authorization change';
    EXCEPTION WHEN SQLSTATE 'ZX124' THEN NULL;
    END;
  END LOOP;
END
$authorization_gates$;
SAVEPOINT due_gate;
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7eb00000-0000-4000-8000-000000000004';
SELECT pg_temp.expect_0124_failure('42501',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000103')$$);
ROLLBACK TO SAVEPOINT due_gate;
RELEASE SAVEPOINT due_gate;
SAVEPOINT missing_mapping;
DELETE FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id = '7eb00000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0124_failure('55000',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000102')$$);
ROLLBACK TO SAVEPOINT missing_mapping;
RELEASE SAVEPOINT missing_mapping;
SAVEPOINT inconsistent_source;
SET LOCAL session_replication_role = replica;
INSERT INTO app_data.contact_target_links(contact_id,revision_number,promotion_target_id,follow_up_consent,
  institution_representative_confirmed,confirmed_project_entry,merge_generation_id)
VALUES ('0124-active-contact',1,'7eb00000-0000-4000-8000-000000000005','unknown',false,false,'7eb00000-0000-4000-8000-000000000102');
SET LOCAL session_replication_role = origin;
SELECT pg_temp.expect_0124_failure('55000',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000102')$$);
ROLLBACK TO SAVEPOINT inconsistent_source;
RELEASE SAVEPOINT inconsistent_source;

SAVEPOINT no_v2_choices;
SET LOCAL session_replication_role = replica;
DELETE FROM app_private.personal_target_merge_activation_requests_v1 WHERE generation_id = (SELECT generation_id FROM fixture_0124_v2);
SET LOCAL session_replication_role = origin;
SELECT pg_temp.fixture_0124_read(generation_id) FROM fixture_0124_v2;
ROLLBACK TO SAVEPOINT no_v2_choices;
RELEASE SAVEPOINT no_v2_choices;

SAVEPOINT read_only_scope;
SET LOCAL transaction_read_only = on;
DO $readonly$ BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION '0124 expected actual READ ONLY'; END IF;
  PERFORM pg_temp.fixture_0124_read(generation_id) FROM fixture_0124_documents;
END $readonly$;
ROLLBACK TO SAVEPOINT read_only_scope;
RELEASE SAVEPOINT read_only_scope;

CREATE FUNCTION pg_temp.fixture_0124_end(request_id uuid,generation_id uuid,fingerprint text) RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.end_known_source_personal_target_merge_generation_v1(app_user_id,workspace_id,project_id,request_id,generation_id,fingerprint)
  FROM fixture_0124_context
$function$;
SAVEPOINT new_fact_conflict;
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0124_context),'0124-new-fact-submit',1,'contact.submit.v1','0124-device','0124-new-fact-contact',0,
  pg_temp.fixture_0124_payload('0124-new-fact-contact',(SELECT links FROM fixture_0124_links)));
SELECT pg_temp.expect_0124_failure('23505',format('SELECT pg_temp.fixture_0124_end(%L,%L,%L)',
  '7eb00000-0000-4000-8000-000000000201',generation_id,document->>'fact_fingerprint'))
FROM fixture_0124_documents WHERE generation_id = '7eb00000-0000-4000-8000-000000000102';
DO $new_plan$ BEGIN
  IF (pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000102')->>'fact_count')::bigint <>
      (SELECT (document->>'fact_count')::bigint + 2 FROM fixture_0124_documents WHERE generation_id = '7eb00000-0000-4000-8000-000000000102')
  THEN RAISE EXCEPTION '0124 fresh preflight omitted newly bound facts'; END IF;
END $new_plan$;
ROLLBACK TO SAVEPOINT new_fact_conflict;
RELEASE SAVEPOINT new_fact_conflict;

SAVEPOINT metadata_conflict;
SELECT result FROM fixture_0124_context c CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,'7eb00000-0000-4000-8000-000000000005','anonymize','withdrawal','0124-erased-partner');
SELECT pg_temp.expect_0124_failure('23505',format('SELECT pg_temp.fixture_0124_end(%L,%L,%L)',
  '7eb00000-0000-4000-8000-000000000201',generation_id,document->>'fact_fingerprint'))
FROM fixture_0124_documents WHERE generation_id = '7eb00000-0000-4000-8000-000000000102';
DO $changed_metadata$ BEGIN
  IF pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000102')->>'fact_fingerprint' IS NOT DISTINCT FROM
      (SELECT document->>'fact_fingerprint' FROM fixture_0124_documents WHERE generation_id = '7eb00000-0000-4000-8000-000000000102')
  THEN RAISE EXCEPTION '0124 fresh preflight omitted ended relationship metadata drift'; END IF;
END $changed_metadata$;
ROLLBACK TO SAVEPOINT metadata_conflict;
RELEASE SAVEPOINT metadata_conflict;

DO $confirm_original_plan$
DECLARE ended_at_value timestamptz; replay_time timestamptz; plan jsonb;
BEGIN
  SELECT document INTO STRICT plan FROM fixture_0124_documents WHERE generation_id = '7eb00000-0000-4000-8000-000000000102';
  ended_at_value := pg_temp.fixture_0124_end('7eb00000-0000-4000-8000-000000000201',
    '7eb00000-0000-4000-8000-000000000102',plan->>'fact_fingerprint');
  replay_time := pg_temp.fixture_0124_end('7eb00000-0000-4000-8000-000000000201',
    '7eb00000-0000-4000-8000-000000000102',plan->>'fact_fingerprint');
  IF ended_at_value IS DISTINCT FROM replay_time OR NOT EXISTS (
      SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = '7eb00000-0000-4000-8000-000000000102'
      AND fact_fingerprint = plan->>'fact_fingerprint' AND fact_count = (plan->>'fact_count')::bigint)
  THEN RAISE EXCEPTION '0124 original preflight fingerprint was not accepted by unchanged 0119 confirmation'; END IF;
END
$confirm_original_plan$;
SELECT pg_temp.expect_0124_failure('42501',$$SELECT pg_temp.fixture_0124_read('7eb00000-0000-4000-8000-000000000102')$$);
DO $acl$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid IN (
      'app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)'::regprocedure,
      'app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)'::regprocedure) AND provolatile <> 's')
    OR has_function_privilege('public','app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.read_known_source_personal_merge_split_plan_v1(uuid,uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('public','app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.personal_target_merge_known_source_fact_catalog_v1(uuid)','EXECUTE')
  THEN RAISE EXCEPTION '0124 private STABLE function ACL drift'; END IF;
END $acl$;

ROLLBACK;
