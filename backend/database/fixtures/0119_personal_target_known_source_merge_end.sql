\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0119_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-0119.example.test', 'owner'
);
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://synthetic-0119.example.test', 'owner'
) WHERE is_current;
CREATE TEMP TABLE fixture_0119_other_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0119.example.test','other-owner');
SELECT count(*) FROM app_data.list_personal_project_contexts(
  'https://synthetic-0119.example.test','other-owner'
) WHERE is_current;

CREATE FUNCTION pg_temp.fixture_0119_end_state() RETURNS jsonb
LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'events', (SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id)
      FROM app_private.personal_target_merge_end_events_v1 r),
    'maps', (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id)
      FROM app_private.personal_target_merge_active_members_v1 r),
    'fence', (SELECT to_jsonb(r)
      FROM app_private.personal_target_merge_generation_fence_v1 r),
    'targets', (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r),
    'assignments', (SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_data.promotion_target_assignments r),
    'retention', (SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_retention_events r),
    'links', (SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number,promotion_target_id) FROM app_data.contact_target_links r),
    'project_relationships', (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id) FROM app_data.promotion_target_project_relationships r),
    'project_revisions', (SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id,revision_number) FROM app_data.promotion_target_relationship_revisions r),
    'institution_relationships', (SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id) FROM app_data.promotion_target_institution_relationships r),
    'institution_revisions', (SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id,revision_number) FROM app_data.promotion_target_institution_relation_revisions r)
  )
$function$;

CREATE FUNCTION pg_temp.expect_0119_failure(expected_state text, statement_text text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0119_end_state();
BEGIN
  BEGIN
    EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION '0119 expected SQLSTATE %, got %', expected_state, actual_state;
  END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0119_end_state() THEN
    RAISE EXCEPTION '0119 rejected request left end or business writes';
  END IF;
END
$function$;

CREATE FUNCTION pg_temp.fixture_0119_payload(contact_id text, links jsonb)
RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'contactId', contact_id, 'workspaceId', workspace_id, 'projectId', project_id,
    'questionnaireVersionId', questionnaire_version_id,
    'reason', 'synthetic revision', 'occurredAtUtc', '2030-03-01T12:00:00Z',
    'occurredTimeZone', 'America/Chicago', 'channel', 'video_call',
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 2, 'interestLevel', 2, 'answers', '[]'::jsonb, 'targetLinks', links
  ) FROM fixture_0119_context
$function$;

CREATE TEMP TABLE fixture_0119_targets ON COMMIT DROP AS
SELECT id::uuid AS target_id, kind, label
FROM (VALUES
  ('7ee00000-0000-4000-8000-000000000001', 'person', '0119 person A'),
  ('7ee00000-0000-4000-8000-000000000002', 'person', '0119 person B'),
  ('7ee00000-0000-4000-8000-000000000003', 'institution', '0119 institution A'),
  ('7ee00000-0000-4000-8000-000000000004', 'institution', '0119 institution B'),
  ('7ee00000-0000-4000-8000-000000000005', 'institution', '0119 unmerged institution')
) t(id, kind, label);
INSERT INTO app_data.promotion_targets(
  promotion_target_id, workspace_id, target_type, display_name, phone,
  created_by_app_user_id, created_at
)
SELECT t.target_id, c.workspace_id, t.kind, t.label, '+1 312 555 0119',
  c.app_user_id, clock_timestamp() FROM fixture_0119_targets t CROSS JOIN fixture_0119_context c;
INSERT INTO app_data.promotion_target_assignments(
  assignment_id, promotion_target_id, app_user_id, assigned_by_app_user_id
)
SELECT t.target_id, t.target_id, c.app_user_id, c.app_user_id
FROM fixture_0119_targets t CROSS JOIN fixture_0119_context c;
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '7ee00000-0000-4000-8000-000000000090', workspace_id, '0119 alternate project'
FROM fixture_0119_context;

CREATE TEMP TABLE fixture_0119_generations ON COMMIT DROP AS
SELECT id::uuid AS generation_id, kind
FROM (VALUES
  ('7ee00000-0000-4000-8000-000000000101', 'person'),
  ('7ee00000-0000-4000-8000-000000000102', 'person'),
  ('7ee00000-0000-4000-8000-000000000103', 'institution')
) g(id, kind);
INSERT INTO app_private.personal_target_merge_generations_v1(
  generation_id, workspace_id, target_type, created_by_app_user_id, activated_at_utc
)
SELECT g.generation_id, c.workspace_id, g.kind, c.app_user_id, clock_timestamp()
FROM fixture_0119_generations g CROSS JOIN fixture_0119_context c;
INSERT INTO app_private.personal_target_merge_generation_members_v1(
  generation_id, workspace_id, target_type, promotion_target_id
)
SELECT g.generation_id, c.workspace_id, g.kind, t.target_id
FROM fixture_0119_generations g JOIN fixture_0119_targets t ON t.kind = g.kind
CROSS JOIN fixture_0119_context c
WHERE t.target_id <> '7ee00000-0000-4000-8000-000000000005';
INSERT INTO app_private.personal_target_merge_active_members_v1(
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT promotion_target_id, generation_id, workspace_id, target_type
FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id IN ('7ee00000-0000-4000-8000-000000000101', '7ee00000-0000-4000-8000-000000000103');

CREATE TEMP TABLE fixture_0119_links ON COMMIT DROP AS
SELECT jsonb_agg(jsonb_build_object(
  'targetId', target_id, 'targetType', kind, 'responseLevel', 2,
  'followUpConsent', 'yes', 'institutionRepresentativeConfirmed', kind = 'institution',
  'confirmStageZero', true
) ORDER BY target_id) AS links FROM fixture_0119_targets
WHERE kind = 'person';
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0119_context), '0119-history-submit', 1,
  'contact.submit.v1', '0119-device', '0119-history-contact', 0,
  pg_temp.fixture_0119_payload('0119-history-contact', (SELECT links FROM fixture_0119_links))
);
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE generation_id = '7ee00000-0000-4000-8000-000000000101';
INSERT INTO app_private.personal_target_merge_active_members_v1(
  promotion_target_id, generation_id, workspace_id, target_type
)
SELECT promotion_target_id, generation_id, workspace_id, target_type
FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0119_context), '0119-active-submit', 1,
  'contact.submit.v1', '0119-device', '0119-active-contact', 0,
  pg_temp.fixture_0119_payload('0119-active-contact', (SELECT links FROM fixture_0119_links))
);
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context), '7ee00000-0000-4000-8000-000000000001',
  1, 1, 'active', 'synthetic note', 'progress_update', NULL, '0119-active-project', NULL
);
CREATE TEMP TABLE fixture_0119_dual_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context), '7ee00000-0000-4000-8000-000000000001',
  '7ee00000-0000-4000-8000-000000000003', 'employment_representative', 'synthetic role', '0119-dual-create'
);
CREATE TEMP TABLE fixture_0119_ended_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context), '7ee00000-0000-4000-8000-000000000002',
  '7ee00000-0000-4000-8000-000000000005', 'membership_affiliation', 'ended role', '0119-ended-create'
);
SELECT result FROM app_data.end_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context), (SELECT relationship_id FROM fixture_0119_ended_relation),
  1, '0119-ended-end'
);

CREATE TEMP TABLE fixture_0119_manifest ON COMMIT DROP AS
SELECT g.generation_id, m.* FROM fixture_0119_generations g
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(g.generation_id) m;
DO $manifest_contract$
DECLARE expected_count bigint; g record;
BEGIN
  FOR g IN SELECT * FROM fixture_0119_manifest LOOP
    SELECT
      (SELECT count(*) FROM app_data.contact_target_links WHERE merge_generation_id = g.generation_id)
      + (SELECT count(*) FROM app_data.promotion_target_project_relationships WHERE merge_generation_id = g.generation_id)
      + (SELECT count(*) FROM app_data.promotion_target_relationship_revisions WHERE merge_generation_id = g.generation_id)
      + (SELECT count(*) FROM app_data.promotion_target_institution_relationships WHERE person_merge_generation_id = g.generation_id OR institution_merge_generation_id = g.generation_id)
      + (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions WHERE person_merge_generation_id = g.generation_id OR institution_merge_generation_id = g.generation_id)
    INTO expected_count;
    IF g.fact_count IS DISTINCT FROM expected_count OR expected_count = 0
      OR g.fact_fingerprint !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION '0119 manifest count/metadata fingerprint mismatch for %', g.generation_id;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = (SELECT relationship_id FROM fixture_0119_dual_relation)
        AND person_merge_generation_id = '7ee00000-0000-4000-8000-000000000102'
        AND institution_merge_generation_id = '7ee00000-0000-4000-8000-000000000103')
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships
      WHERE merge_generation_id = '7ee00000-0000-4000-8000-000000000101')
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions
      WHERE merge_generation_id = '7ee00000-0000-4000-8000-000000000102')
  THEN RAISE EXCEPTION '0119 source generations or five fact classes missing'; END IF;
END
$manifest_contract$;

-- A link-free revision changes the contact head, not historical attribution.
SELECT * FROM app_data.apply_contact_revise_v3(
  (SELECT app_user_id FROM fixture_0119_context), '0119-empty-links-revise', 1,
  'contact.revise.v1', '0119-device', '0119-active-contact', 1,
  pg_temp.fixture_0119_payload('0119-active-contact', '[]'::jsonb)
);
SAVEPOINT value_only_role;
SELECT set_config('app_data.anonymizing_promotion_target_id','7ee00000-0000-4000-8000-000000000005',true);
UPDATE app_data.promotion_target_institution_relationships SET role_description = '[已匿名化]'
WHERE relationship_id = (SELECT relationship_id FROM fixture_0119_ended_relation);
DO $value_free_manifest$
BEGIN
  IF EXISTS (SELECT 1 FROM fixture_0119_manifest old
      CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(old.generation_id) now
      WHERE old.fact_count IS DISTINCT FROM now.fact_count OR old.fact_fingerprint IS DISTINCT FROM now.fact_fingerprint)
    OR (SELECT current_revision FROM app_data.contacts WHERE contact_id = '0119-active-contact') <> 2
  THEN RAISE EXCEPTION '0119 manifest read contact head or role description'; END IF;
END
$value_free_manifest$;
ROLLBACK TO SAVEPOINT value_only_role;
RELEASE SAVEPOINT value_only_role;

CREATE FUNCTION pg_temp.fixture_0119_end(request_id uuid, generation_id uuid, fingerprint text)
RETURNS timestamptz LANGUAGE sql AS $function$
  SELECT app_private.end_known_source_personal_target_merge_generation_v1(
    app_user_id, workspace_id, project_id, request_id, generation_id, fingerprint
  ) FROM fixture_0119_context
$function$;

SELECT pg_temp.expect_0119_failure('22023', $$SELECT pg_temp.fixture_0119_end(NULL,
  '7ee00000-0000-4000-8000-000000000102', repeat('a',64))$$);
SELECT pg_temp.expect_0119_failure('22023', $$SELECT pg_temp.fixture_0119_end(
  '7ee00000-0000-4000-8000-000000000201', NULL, repeat('a',64))$$);
SELECT pg_temp.expect_0119_failure('22023', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201', '7ee00000-0000-4000-8000-000000000102', invalid_fingerprint))
FROM (VALUES (NULL::text),(''),(repeat('A',64)),(repeat('a',63)),(repeat('g',64))) bad(invalid_fingerprint);
SELECT pg_temp.expect_0119_failure('22023', format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  bad.actor_id, bad.ws_id, bad.prj_id, '7ee00000-0000-4000-8000-000000000201',
  '7ee00000-0000-4000-8000-000000000102', repeat('a',64)))
FROM fixture_0119_context c CROSS JOIN LATERAL (VALUES
  (NULL::uuid,c.workspace_id,c.project_id), (c.app_user_id,NULL::uuid,c.project_id),
  (c.app_user_id,c.workspace_id,NULL::uuid)) bad(actor_id,ws_id,prj_id);
SELECT pg_temp.expect_0119_failure('42501', $$SELECT pg_temp.fixture_0119_end(
  '7ee00000-0000-4000-8000-000000000201', '7ee00000-0000-4000-8000-000000000199', repeat('a',64))$$);
SELECT pg_temp.expect_0119_failure('42501',format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,c.project_id,'7ee00000-0000-4000-8000-000000000201',
  '7ee00000-0000-4000-8000-000000000102',m.fact_fingerprint))
FROM fixture_0119_other_context c CROSS JOIN fixture_0119_manifest m
WHERE m.generation_id = '7ee00000-0000-4000-8000-000000000102';
SELECT pg_temp.expect_0119_failure('42501', format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  bad.actor_id, bad.ws_id, bad.prj_id, '7ee00000-0000-4000-8000-000000000201',
  '7ee00000-0000-4000-8000-000000000102', m.fact_fingerprint))
FROM fixture_0119_context c CROSS JOIN fixture_0119_manifest m
CROSS JOIN LATERAL (VALUES
  ('7ee00000-0000-4000-8000-000000000099'::uuid,c.workspace_id,c.project_id),
  (c.app_user_id,'7ee00000-0000-4000-8000-000000000099'::uuid,c.project_id),
  (c.app_user_id,c.workspace_id,'7ee00000-0000-4000-8000-000000000090'::uuid)) bad(actor_id,ws_id,prj_id)
WHERE m.generation_id = '7ee00000-0000-4000-8000-000000000102';
SELECT pg_temp.expect_0119_failure('23505', $$SELECT pg_temp.fixture_0119_end(
  '7ee00000-0000-4000-8000-000000000201', '7ee00000-0000-4000-8000-000000000102', repeat('0',64))$$);

INSERT INTO app_private.personal_target_merge_generations_v1(
  generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc
)
SELECT '7ee00000-0000-4000-8000-000000000104',workspace_id,'person',app_user_id,clock_timestamp()
FROM fixture_0119_context;
SELECT pg_temp.expect_0119_failure('55000', $$SELECT pg_temp.fixture_0119_end(
  '7ee00000-0000-4000-8000-000000000204','7ee00000-0000-4000-8000-000000000104',repeat('a',64))$$);

UPDATE app_data.app_users SET status = 'deletion_pending'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0119_context);
SELECT pg_temp.expect_0119_failure('42501', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
UPDATE app_data.app_users SET status = 'active'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0119_context);

DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE promotion_target_id = '7ee00000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0119_failure('55000', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201', generation_id, fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
INSERT INTO app_private.personal_target_merge_active_members_v1
SELECT promotion_target_id,generation_id,workspace_id,target_type
FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id = '7ee00000-0000-4000-8000-000000000102'
  AND promotion_target_id = '7ee00000-0000-4000-8000-000000000002';
UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(), end_reason = 'user_requested'
WHERE assignment_id = '7ee00000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0119_failure('42501', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201', generation_id, fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
UPDATE app_data.promotion_target_assignments SET ended_at = NULL, end_reason = NULL
WHERE assignment_id = '7ee00000-0000-4000-8000-000000000002';
CREATE TEMP TABLE fixture_0119_creation ON COMMIT DROP AS
SELECT created_at FROM app_data.promotion_targets WHERE promotion_target_id = '7ee00000-0000-4000-8000-000000000004';
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '2 years'
WHERE promotion_target_id = '7ee00000-0000-4000-8000-000000000004';
SELECT pg_temp.expect_0119_failure('42501', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201', generation_id, fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000103';
UPDATE app_data.promotion_targets SET created_at = (SELECT created_at FROM fixture_0119_creation)
WHERE promotion_target_id = '7ee00000-0000-4000-8000-000000000004';

SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0119_context),'0119-manifest-drift-submit',1,
  'contact.submit.v1','0119-device','0119-manifest-drift-contact',0,
  pg_temp.fixture_0119_payload('0119-manifest-drift-contact',(SELECT links FROM fixture_0119_links))
);
SELECT pg_temp.expect_0119_failure('23505', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
UPDATE fixture_0119_manifest old SET fact_count = now.fact_count,fact_fingerprint = now.fact_fingerprint
FROM app_private.personal_target_merge_known_source_manifest_v1('7ee00000-0000-4000-8000-000000000102') now
WHERE old.generation_id = '7ee00000-0000-4000-8000-000000000102';

CREATE TEMP TABLE fixture_0119_relation_metadata ON COMMIT DROP AS
SELECT current_revision, updated_at FROM app_data.promotion_target_institution_relationships
WHERE relationship_id = (SELECT relationship_id FROM fixture_0119_ended_relation);
SELECT result FROM app_data.apply_promotion_target_retention_action(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context), '7ee00000-0000-4000-8000-000000000005',
  'anonymize', 'withdrawal', '0119-anonymize-nonmerge-endpoint'
);
DO $ended_relation_marker$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships r
      CROSS JOIN fixture_0119_relation_metadata old
      WHERE r.relationship_id = (SELECT relationship_id FROM fixture_0119_ended_relation)
        AND r.current_revision = old.current_revision AND r.updated_at > old.updated_at
        AND r.role_description = '[已匿名化]')
    OR (SELECT fact_fingerprint FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102')
      IS NOT DISTINCT FROM (SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('7ee00000-0000-4000-8000-000000000102'))
  THEN RAISE EXCEPTION '0119 ended relation updated_at drift was omitted'; END IF;
END
$ended_relation_marker$;
SELECT pg_temp.expect_0119_failure('23505', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201', generation_id, fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
UPDATE fixture_0119_manifest old SET fact_count = now.fact_count, fact_fingerprint = now.fact_fingerprint
FROM app_private.personal_target_merge_known_source_manifest_v1('7ee00000-0000-4000-8000-000000000102') now
WHERE old.generation_id = '7ee00000-0000-4000-8000-000000000102';

CREATE FUNCTION pg_temp.fixture_0119_history() RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'targets',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r),
    'assignments',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_data.promotion_target_assignments r),
    'retention',(SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_retention_events r),
    'policies',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.promotion_target_retention_policies r),
    'contacts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id) FROM app_data.contacts r),
    'contact_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number) FROM app_data.contact_revisions r),
    'contact_links',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number,promotion_target_id) FROM app_data.contact_target_links r),
    'project_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id) FROM app_data.promotion_target_project_relationships r),
    'relationship_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id,revision_number) FROM app_data.promotion_target_relationship_revisions r),
    'institution_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id) FROM app_data.promotion_target_institution_relationships r),
    'institution_relation_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY relationship_id,revision_number) FROM app_data.promotion_target_institution_relation_revisions r),
    'generations',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_generations_v1 r),
    'members',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id,promotion_target_id) FROM app_private.personal_target_merge_generation_members_v1 r),
    'previews',(SELECT jsonb_agg(to_jsonb(r) ORDER BY preview_id) FROM app_private.personal_target_pair_preview_receipts r),
    'activation_requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_requests_v1 r),
    'activation_audit',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_audit_v1 r)
  )
$function$;
CREATE TEMP TABLE fixture_0119_before ON COMMIT DROP AS SELECT pg_temp.fixture_0119_history() AS history;
CREATE TEMP TABLE fixture_0119_first ON COMMIT DROP AS
SELECT pg_temp.fixture_0119_end('7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint) AS ended_at_utc
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
CREATE TEMP TABLE fixture_0119_replay ON COMMIT DROP AS
SELECT pg_temp.fixture_0119_end('7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint) AS ended_at_utc
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
DO $success_contract$
BEGIN
  IF (SELECT history FROM fixture_0119_before) IS DISTINCT FROM pg_temp.fixture_0119_history()
    OR (SELECT ended_at_utc FROM fixture_0119_first) IS DISTINCT FROM (SELECT ended_at_utc FROM fixture_0119_replay)
    OR NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 e
      CROSS JOIN fixture_0119_manifest m CROSS JOIN fixture_0119_context c
      WHERE e.generation_id = '7ee00000-0000-4000-8000-000000000102' AND m.generation_id = e.generation_id
        AND e.actor_app_user_id = c.app_user_id AND e.workspace_id = c.workspace_id AND e.project_id = c.project_id
        AND e.request_id = '7ee00000-0000-4000-8000-000000000201' AND e.operation = 'personal_target_known_source_merge_end'
        AND e.reason = 'known_source_split' AND e.outcome = 'ended' AND e.target_count = 2
        AND e.fact_count = m.fact_count AND e.fact_fingerprint = m.fact_fingerprint
        AND e.ended_at_utc = (SELECT ended_at_utc FROM fixture_0119_first) AND isfinite(e.ended_at_utc))
    OR (SELECT count(*) FROM app_private.personal_target_merge_end_events_v1
      WHERE actor_app_user_id = (SELECT app_user_id FROM fixture_0119_context)) <> 1
    OR EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1
      WHERE generation_id = '7ee00000-0000-4000-8000-000000000102')
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1
      WHERE generation_id = '7ee00000-0000-4000-8000-000000000103') <> 2
  THEN RAISE EXCEPTION '0119 end/replay preserved-history contract drift'; END IF;
END
$success_contract$;

SELECT pg_temp.expect_0119_failure('23505', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000202',generation_id,fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
SELECT pg_temp.expect_0119_failure('23505', $$SELECT pg_temp.fixture_0119_end(
  '7ee00000-0000-4000-8000-000000000201','7ee00000-0000-4000-8000-000000000102',repeat('0',64))$$);
SELECT pg_temp.expect_0119_failure('23505', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000103';
UPDATE app_data.user_current_projects SET project_id = '7ee00000-0000-4000-8000-000000000090'
WHERE app_user_id = (SELECT app_user_id FROM fixture_0119_context);
SELECT pg_temp.expect_0119_failure('42501', format('SELECT pg_temp.fixture_0119_end(%L,%L,%L)',
  '7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint))
FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
SELECT pg_temp.expect_0119_failure('23505',format(
  'SELECT app_private.end_known_source_personal_target_merge_generation_v1(%L,%L,%L,%L,%L,%L)',
  c.app_user_id,c.workspace_id,'7ee00000-0000-4000-8000-000000000090',
  '7ee00000-0000-4000-8000-000000000201',m.generation_id,m.fact_fingerprint))
FROM fixture_0119_context c CROSS JOIN fixture_0119_manifest m
WHERE m.generation_id = '7ee00000-0000-4000-8000-000000000102';
UPDATE app_data.user_current_projects SET project_id = (SELECT project_id FROM fixture_0119_context)
WHERE app_user_id = (SELECT app_user_id FROM fixture_0119_context);
SELECT pg_temp.expect_0119_failure('55000', $$UPDATE app_private.personal_target_merge_end_events_v1
  SET ended_at_utc = ended_at_utc WHERE generation_id = '7ee00000-0000-4000-8000-000000000102'$$);
SELECT pg_temp.expect_0119_failure('55000', $$DELETE FROM app_private.personal_target_merge_end_events_v1
  WHERE generation_id = '7ee00000-0000-4000-8000-000000000102'$$);
SELECT pg_temp.expect_0119_failure('55000', $$INSERT INTO app_private.personal_target_merge_active_members_v1
  SELECT promotion_target_id,generation_id,workspace_id,target_type FROM app_private.personal_target_merge_generation_members_v1
  WHERE generation_id = '7ee00000-0000-4000-8000-000000000102'$$);

SELECT * FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM fixture_0119_context), '0119-post-end-submit', 1,
  'contact.submit.v1', '0119-device', '0119-post-end-contact', 0,
  pg_temp.fixture_0119_payload('0119-post-end-contact',(SELECT links FROM fixture_0119_links))
);
SELECT result FROM app_data.update_promotion_target_relationship(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context),'7ee00000-0000-4000-8000-000000000001',
  2,2,'active',NULL,'progress_update',NULL,'0119-post-end-project',NULL
);
CREATE TEMP TABLE fixture_0119_post_end_relation ON COMMIT DROP AS
SELECT (result->'relationship'->>'relationship_id')::uuid AS relationship_id
FROM app_data.create_target_institution_relationship(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context),'7ee00000-0000-4000-8000-000000000002',
  '7ee00000-0000-4000-8000-000000000004','learning_participation','new relation','0119-post-end-relation'
);
DO $new_writes_unbound$
BEGIN
  IF (SELECT count(*) FROM app_data.contact_target_links WHERE contact_id = '0119-post-end-contact') <> 2
    OR EXISTS (SELECT 1 FROM app_data.contact_target_links WHERE contact_id = '0119-post-end-contact' AND merge_generation_id IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions
      WHERE mutation_id = '0119-post-end-project' AND merge_generation_id IS NULL)
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relationships
      WHERE relationship_id = (SELECT relationship_id FROM fixture_0119_post_end_relation)
        AND person_merge_generation_id IS NULL AND institution_merge_generation_id = '7ee00000-0000-4000-8000-000000000103')
    OR NOT EXISTS (SELECT 1 FROM app_data.promotion_target_institution_relation_revisions
      WHERE mutation_id = '0119-post-end-relation' AND person_merge_generation_id IS NULL
        AND institution_merge_generation_id = '7ee00000-0000-4000-8000-000000000103')
  THEN RAISE EXCEPTION '0119 post-end facts bound to closed generation'; END IF;
END
$new_writes_unbound$;

SELECT app_data.end_personal_target_assignment_v1(
  (SELECT app_user_id FROM fixture_0119_context), (SELECT workspace_id FROM fixture_0119_context),
  (SELECT project_id FROM fixture_0119_context),'7ee00000-0000-4000-8000-000000000001'
);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT '7ee00000-0000-4000-8000-000000000011','7ee00000-0000-4000-8000-000000000001',app_user_id,app_user_id
FROM fixture_0119_context;
CREATE TEMP TABLE fixture_0119_new_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  c.app_user_id,c.project_id,'7ee00000-0000-4000-8000-000000000301',p.preview_id,
  '7ee00000-0000-4000-8000-000000000001','7ee00000-0000-4000-8000-000000000001',
  '7ee00000-0000-4000-8000-000000000002','7ee00000-0000-4000-8000-000000000001'
) AS generation_id FROM fixture_0119_context c
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  'https://synthetic-0119.example.test','owner',c.project_id,
  '7ee00000-0000-4000-8000-000000000001','7ee00000-0000-4000-8000-000000000002'
) p;
DO $historical_replay$
DECLARE replay_time timestamptz;
BEGIN
  SELECT pg_temp.fixture_0119_end('7ee00000-0000-4000-8000-000000000201',generation_id,fact_fingerprint)
  INTO STRICT replay_time FROM fixture_0119_manifest WHERE generation_id = '7ee00000-0000-4000-8000-000000000102';
  IF replay_time IS DISTINCT FROM (SELECT ended_at_utc FROM fixture_0119_first)
    OR (SELECT generation_id FROM fixture_0119_new_generation) = '7ee00000-0000-4000-8000-000000000102'
    OR (SELECT count(*) FROM app_private.personal_target_merge_active_members_v1
      WHERE generation_id = (SELECT generation_id FROM fixture_0119_new_generation)) <> 2
    OR (SELECT count(*) FROM app_private.personal_target_merge_end_events_v1
      WHERE actor_app_user_id = (SELECT app_user_id FROM fixture_0119_context)) <> 1
  THEN RAISE EXCEPTION '0119 old replay ended a later generation'; END IF;
END
$historical_replay$;

DO $private_acl$
BEGIN
  IF has_table_privilege('public','app_private.personal_target_merge_end_events_v1','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_table_privilege('tongxingzhe_runtime','app_private.personal_target_merge_end_events_v1','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    OR has_function_privilege('public','app_private.personal_target_merge_known_source_manifest_v1(uuid)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.personal_target_merge_known_source_manifest_v1(uuid)','EXECUTE')
    OR has_function_privilege('public','app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)','EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime','app_private.end_known_source_personal_target_merge_generation_v1(uuid,uuid,uuid,uuid,uuid,text)','EXECUTE')
  THEN RAISE EXCEPTION '0119 private end permissions drift'; END IF;
END
$private_acl$;

ROLLBACK;
