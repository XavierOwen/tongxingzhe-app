\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0125_context ON COMMIT DROP AS
SELECT identity.kind,identity.issuer,identity.subject,c.* FROM (VALUES
  ('owner','https://synthetic-0125.example.test','owner'),
  ('exact',' https://synthetic-0125.example.test ',' owner '),
  ('other','https://synthetic-0125.example.test','other')
) identity(kind,issuer,subject)
CROSS JOIN LATERAL app_data.bootstrap_personal_context(identity.issuer,identity.subject) c;
INSERT INTO app_data.app_users(app_user_id) VALUES ('7ed00000-0000-4000-8000-000000000099');
SELECT count(*) FROM fixture_0125_context c
CROSS JOIN LATERAL app_data.list_personal_project_contexts(c.issuer,c.subject) p WHERE p.is_current;
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '7ed00000-0000-4000-8000-000000000090',workspace_id,'0125 alternate personal project'
FROM fixture_0125_context WHERE kind = 'owner';
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT t.id,c.workspace_id,'person','0125 original ' || t.id,'+1 312 555 0125',NULL,c.app_user_id
FROM fixture_0125_context c CROSS JOIN (VALUES
  ('owner','7ed00000-0000-4000-8000-000000000001'::uuid),
  ('owner','7ed00000-0000-4000-8000-000000000002'::uuid),
  ('exact','7ed00000-0000-4000-8000-000000000003'::uuid),
  ('exact','7ed00000-0000-4000-8000-000000000004'::uuid),
  ('other','7ed00000-0000-4000-8000-000000000005'::uuid),
  ('other','7ed00000-0000-4000-8000-000000000006'::uuid)
) t(kind,id) WHERE t.kind = c.kind;
INSERT INTO app_data.promotion_target_assignments(
  assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id
)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM fixture_0125_context c JOIN app_data.promotion_targets t USING(workspace_id);
CREATE TEMP TABLE fixture_0125_generations ON COMMIT DROP AS
SELECT c.kind,app_private.activate_personal_target_merge_generation_v2(
  c.app_user_id,c.project_id,t.request_id,p.preview_id,t.first_id,t.second_id,t.second_id,t.first_id
) AS generation_id FROM fixture_0125_context c JOIN (VALUES
  ('owner','7ed00000-0000-4000-8000-000000000101'::uuid,
    '7ed00000-0000-4000-8000-000000000001'::uuid,'7ed00000-0000-4000-8000-000000000002'::uuid),
  ('exact','7ed00000-0000-4000-8000-000000000102'::uuid,
    '7ed00000-0000-4000-8000-000000000003'::uuid,'7ed00000-0000-4000-8000-000000000004'::uuid)
) t(kind,request_id,first_id,second_id) USING(kind)
CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(c.issuer,c.subject,c.project_id,t.first_id,t.second_id) p;
INSERT INTO app_private.personal_target_merge_generations_v1(generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc)
SELECT '7ed00000-0000-4000-8000-000000000107',workspace_id,'person',app_user_id,clock_timestamp()
FROM fixture_0125_context WHERE kind = 'other';
INSERT INTO app_private.personal_target_merge_generation_members_v1(generation_id,workspace_id,target_type,promotion_target_id)
SELECT '7ed00000-0000-4000-8000-000000000107',c.workspace_id,'person',t.promotion_target_id
FROM fixture_0125_context c JOIN app_data.promotion_targets t USING(workspace_id) WHERE kind = 'other';
INSERT INTO app_private.personal_target_merge_active_members_v1(promotion_target_id,generation_id,workspace_id,target_type)
SELECT promotion_target_id,generation_id,workspace_id,target_type
FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id = '7ed00000-0000-4000-8000-000000000107';
INSERT INTO fixture_0125_generations VALUES ('other','7ed00000-0000-4000-8000-000000000107');

CREATE TEMP TABLE fixture_0125_expected ON COMMIT DROP AS
SELECT c.kind,app_private.read_known_source_personal_merge_split_plan_v1(
  c.app_user_id,c.workspace_id,c.project_id,g.generation_id
) AS document FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind);

-- Management navigation coexists with the independent personal current project.
INSERT INTO app_data.workspaces(workspace_id,workspace_kind,display_name)
VALUES ('7ed00000-0000-4000-8000-000000000030','organization','0125 management organization');
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
VALUES ('7ed00000-0000-4000-8000-000000000031','7ed00000-0000-4000-8000-000000000030','0125 management project');
INSERT INTO app_data.organization_memberships(
  organization_membership_id,organization_workspace_id,app_user_id,active_from_utc
)
SELECT '7ed00000-0000-4000-8000-000000000032','7ed00000-0000-4000-8000-000000000030',app_user_id,
  transaction_timestamp() - interval '1 day' FROM fixture_0125_context WHERE kind = 'owner';
INSERT INTO app_data.project_memberships(project_membership_id,organization_membership_id,project_id,active_from_utc)
VALUES ('7ed00000-0000-4000-8000-000000000033','7ed00000-0000-4000-8000-000000000032',
  '7ed00000-0000-4000-8000-000000000031',transaction_timestamp() - interval '1 day');
INSERT INTO app_data.management_report_capability_grants(capability_grant_id,project_membership_id,capability_id,active_from_utc)
VALUES ('7ed00000-0000-4000-8000-000000000034','7ed00000-0000-4000-8000-000000000033',
  'view_anonymous_analytics',transaction_timestamp() - interval '1 day');
INSERT INTO app_data.management_analysis_current_contexts(
  app_user_id,organization_workspace_id,organization_membership_id,project_id,project_membership_id,capability_grant_id,selected_at_utc
)
SELECT app_user_id,'7ed00000-0000-4000-8000-000000000030','7ed00000-0000-4000-8000-000000000032',
  '7ed00000-0000-4000-8000-000000000031','7ed00000-0000-4000-8000-000000000033',
  '7ed00000-0000-4000-8000-000000000034',transaction_timestamp()
FROM fixture_0125_context WHERE kind = 'owner';

CREATE FUNCTION pg_temp.fixture_0125_workspace_state(requested_workspace_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $function$
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

CREATE FUNCTION pg_temp.fixture_0125_state() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_build_object(
    'users',(SELECT count(*) FROM app_data.app_users),
    'identities',(SELECT count(*) FROM app_data.external_identities),
    'workspaces',(SELECT count(*) FROM app_data.workspaces),
    'current_projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.user_current_projects r),
    'access_events',(SELECT count(*) FROM app_data.promotion_target_access_events),
    'business',(SELECT jsonb_agg(pg_temp.fixture_0125_workspace_state(workspace_id) ORDER BY workspace_id) FROM fixture_0125_context),
    'targets',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r
      WHERE workspace_id IN (SELECT workspace_id FROM fixture_0125_context)))
$function$;
CREATE FUNCTION pg_temp.expect_0125_failure(expected_state text,statement_text text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0125_state();
BEGIN
  BEGIN
    SET LOCAL ROLE tongxingzhe_runtime;
    EXECUTE statement_text;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION '0125 expected %, got % for %',expected_state,actual_state,statement_text;
  END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0125_state() THEN
    RAISE EXCEPTION '0125 rejected runtime read changed identity, current project, audit or source facts';
  END IF;
END
$function$;
GRANT SELECT ON fixture_0125_context,fixture_0125_generations,fixture_0125_expected TO tongxingzhe_runtime;

DO $runtime_success$
DECLARE c record; context_document jsonb; document jsonb; expected jsonb; before_events bigint; before_ids uuid[];
  before_business jsonb := pg_temp.fixture_0125_state() - 'access_events';
BEGIN
  FOR c IN SELECT context_row.*,g.generation_id FROM fixture_0125_context context_row JOIN fixture_0125_generations g USING(kind) LOOP
    SELECT count(*) INTO before_events FROM app_data.promotion_target_access_events;
    SET LOCAL ROLE tongxingzhe_runtime;
    context_document := app_data.read_personal_merge_projection_context_v1(c.issuer,c.subject,c.project_id);
    RESET ROLE;
    IF context_document IS DISTINCT FROM jsonb_build_object('app_user_id',c.app_user_id,
      'workspace_id',c.workspace_id,'workspace_kind','personal','project_id',c.project_id,
      'capabilities',jsonb_build_array('view_assigned_target_pii','manage_assigned_target_merges'))
      OR (SELECT count(*) FROM app_data.promotion_target_access_events) <> before_events
    THEN RAISE EXCEPTION '0125 runtime eligibility shape or zero-audit contract drift'; END IF;
    SELECT e.document INTO STRICT expected FROM fixture_0125_expected e WHERE e.kind = c.kind;
    FOR i IN 1..2 LOOP
      SELECT count(*),array_agg(event_id) INTO before_events,before_ids FROM app_data.promotion_target_access_events;
      SET LOCAL ROLE tongxingzhe_runtime;
      document := app_data.read_personal_known_source_merge_split_plan_v1(c.issuer,c.subject,c.project_id,c.generation_id);
      RESET ROLE;
      IF document IS DISTINCT FROM expected
        OR (SELECT count(*) FROM app_data.promotion_target_access_events) <> before_events + 2
        OR (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id) FROM app_data.promotion_target_access_events
          WHERE NOT (event_id = ANY(coalesce(before_ids,'{}'::uuid[])))) IS DISTINCT FROM
          (SELECT array_agg(value::uuid ORDER BY value::uuid) FROM jsonb_array_elements_text(document->'member_target_ids'))
        OR EXISTS (SELECT 1 FROM app_data.promotion_target_access_events
          WHERE NOT (event_id = ANY(coalesce(before_ids,'{}'::uuid[])))
            AND (workspace_id <> c.workspace_id OR actor_app_user_id <> c.app_user_id
              OR action <> 'viewed' OR occurred_at <> statement_timestamp()))
      THEN RAISE EXCEPTION '0125 runtime plan, repeated member audit or statement time drift'; END IF;
    END LOOP;
  END LOOP;
  IF before_business IS DISTINCT FROM (pg_temp.fixture_0125_state() - 'access_events')
  THEN RAISE EXCEPTION '0125 successful reads changed business, ledger, fence or context'; END IF;
END
$runtime_success$;

SELECT pg_temp.expect_0125_failure('42501',format(
  'SELECT app_data.read_personal_merge_projection_context_v1(%L,%L,%L)',bad.issuer,bad.subject,bad.project_id))
FROM fixture_0125_context c CROSS JOIN fixture_0125_context o CROSS JOIN LATERAL (VALUES
  ('https://synthetic-0125.example.test','unknown',c.project_id),
  ('https://synthetic-0125.example.test','other',c.project_id),
  ('https://synthetic-0125.example.test',' owner ',c.project_id),
  (' https://synthetic-0125.example.test ','owner',c.project_id),
  (c.issuer,c.subject,o.project_id),(c.issuer,c.subject,'7ed00000-0000-4000-8000-000000000090'::uuid),
  (c.issuer,c.subject,'7ed00000-0000-4000-8000-000000000031'::uuid)
) bad(issuer,subject,project_id) WHERE c.kind = 'owner' AND o.kind = 'other';
SELECT pg_temp.expect_0125_failure('42501',format(
  'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',bad.issuer,bad.subject,bad.project_id,g.generation_id))
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind)
CROSS JOIN LATERAL (VALUES
  (c.issuer,'unknown',c.project_id),(c.issuer,'other',c.project_id),
  (c.issuer,' owner ',c.project_id),(' https://synthetic-0125.example.test ','owner',c.project_id),
  (c.issuer,c.subject,'7ed00000-0000-4000-8000-000000000090'::uuid)
) bad(issuer,subject,project_id) WHERE c.kind = 'owner';
SELECT pg_temp.expect_0125_failure('22023',format(
  'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',bad.issuer,bad.subject,bad.project_id,bad.generation_id))
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind) CROSS JOIN LATERAL (VALUES
  (NULL::text,c.subject,c.project_id,g.generation_id),(c.issuer,NULL::text,c.project_id,g.generation_id),
  (' ',c.subject,c.project_id,g.generation_id),(c.issuer,' ',c.project_id,g.generation_id),
  (repeat('x',2049),c.subject,c.project_id,g.generation_id),(c.issuer,repeat('x',513),c.project_id,g.generation_id),
  (c.issuer,c.subject,NULL::uuid,g.generation_id),(c.issuer,c.subject,c.project_id,NULL::uuid)
) bad(issuer,subject,project_id,generation_id) WHERE kind = 'owner';
SELECT pg_temp.expect_0125_failure('22023',format(
  'SELECT app_data.read_personal_merge_projection_context_v1(%L,%L,%L)',bad.issuer,bad.subject,bad.project_id))
FROM fixture_0125_context c CROSS JOIN LATERAL (VALUES
  (NULL::text,c.subject,c.project_id),('',c.subject,c.project_id),(' ',c.subject,c.project_id),
  (repeat('x',2049),c.subject,c.project_id),(c.issuer,NULL::text,c.project_id),
  (c.issuer,'',c.project_id),(c.issuer,' ',c.project_id),(c.issuer,repeat('x',513),c.project_id),
  (c.issuer,c.subject,NULL::uuid)
) bad(issuer,subject,project_id) WHERE c.kind = 'owner';

DO $revocation$
DECLARE change_statement text; c record;
BEGIN
  SELECT context_row.*,g.generation_id INTO STRICT c FROM fixture_0125_context context_row JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
  FOREACH change_statement IN ARRAY ARRAY[
    $$UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = (SELECT app_user_id FROM fixture_0125_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.app_users SET status = 'deleted' WHERE app_user_id = (SELECT app_user_id FROM fixture_0125_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = (SELECT workspace_id FROM fixture_0125_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.workspaces SET personal_owner_app_user_id = '7ed00000-0000-4000-8000-000000000099' WHERE workspace_id = (SELECT workspace_id FROM fixture_0125_context WHERE kind = 'owner')$$,
    $$DELETE FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0125_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.user_current_projects SET project_id = '7ed00000-0000-4000-8000-000000000090' WHERE app_user_id = (SELECT app_user_id FROM fixture_0125_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.projects SET status = 'archived' WHERE project_id = (SELECT project_id FROM fixture_0125_context WHERE kind = 'owner')$$
  ] LOOP
    BEGIN
      SET LOCAL ROLE tongxingzhe_runtime;
      PERFORM app_data.read_personal_merge_projection_context_v1(c.issuer,c.subject,c.project_id);
      RESET ROLE;
      EXECUTE change_statement;
      PERFORM pg_temp.expect_0125_failure('42501',format(
        'SELECT app_data.read_personal_merge_projection_context_v1(%L,%L,%L)',c.issuer,c.subject,c.project_id));
      PERFORM pg_temp.expect_0125_failure('42501',format(
        'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',c.issuer,c.subject,c.project_id,c.generation_id));
      RAISE EXCEPTION USING ERRCODE = 'ZX123',MESSAGE = 'rollback synthetic revocation';
    EXCEPTION WHEN SQLSTATE 'ZX123' THEN NULL;
    END;
  END LOOP;
END
$revocation$;

SAVEPOINT assignment_revocation;
SET LOCAL ROLE tongxingzhe_runtime;
SELECT app_data.read_personal_merge_projection_context_v1(issuer,subject,project_id)
FROM fixture_0125_context WHERE kind = 'owner';
RESET ROLE;
UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'user_requested'
WHERE assignment_id = '7ed00000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0125_failure('42501',format(
  'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',c.issuer,c.subject,c.project_id,g.generation_id))
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
ROLLBACK TO SAVEPOINT assignment_revocation;
RELEASE SAVEPOINT assignment_revocation;

SAVEPOINT incomplete_mapping;
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE promotion_target_id = '7ed00000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_0125_failure('55000',format(
  'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',c.issuer,c.subject,c.project_id,g.generation_id))
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
ROLLBACK TO SAVEPOINT incomplete_mapping;
RELEASE SAVEPOINT incomplete_mapping;

CREATE TEMP TABLE fixture_0125_audit_probe(n integer);
INSERT INTO fixture_0125_audit_probe VALUES (0);
CREATE FUNCTION pg_temp.fail_second_0125_audit() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE event_number integer;
BEGIN
  IF NEW.workspace_id = (SELECT workspace_id FROM fixture_0125_context WHERE kind = 'owner') AND NEW.action = 'viewed' THEN
    UPDATE fixture_0125_audit_probe SET n = n + 1 RETURNING n INTO event_number;
    IF event_number = 2 THEN
      IF TG_NARGS = 1 AND TG_ARGV[0] = 'skip' THEN RETURN NULL; END IF;
      RAISE EXCEPTION USING ERRCODE = 'ZXAU5',MESSAGE = 'synthetic second audit failure';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0125_fail_second_audit BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_0125_audit();
SELECT pg_temp.expect_0125_failure('ZXAU5',format(
  'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',c.issuer,c.subject,c.project_id,g.generation_id))
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
DROP TRIGGER fixture_0125_fail_second_audit ON app_data.promotion_target_access_events;
CREATE TRIGGER fixture_0125_skip_second_audit BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_0125_audit('skip');
SELECT pg_temp.expect_0125_failure('55000',format(
  'SELECT app_data.read_personal_known_source_merge_split_plan_v1(%L,%L,%L,%L)',c.issuer,c.subject,c.project_id,g.generation_id))
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
DROP TRIGGER fixture_0125_skip_second_audit ON app_data.promotion_target_access_events;
DO $audit_rollback$ BEGIN
  IF (SELECT n FROM fixture_0125_audit_probe) <> 0 THEN RAISE EXCEPTION '0125 audit/probe did not roll back'; END IF;
END $audit_rollback$;

SELECT pg_temp.expect_0125_failure('42501',statement_text) FROM (VALUES
  ('SELECT * FROM app_data.external_identities'),('SELECT * FROM app_data.promotion_targets'),
  ('SELECT * FROM app_data.promotion_target_access_events'),('SELECT * FROM app_private.personal_target_merge_generations_v1'),
  ($$SELECT app_private.read_authorized_known_source_personal_merge_projection_v1('issuer','subject',NULL,NULL)$$),
  ($$SELECT app_private.read_authorized_known_source_merge_split_plan_v1('issuer','subject',NULL,NULL)$$),
  ($$SELECT app_private.read_known_source_personal_merge_split_plan_v1(NULL,NULL,NULL,NULL)$$),
  ($$SELECT * FROM app_data.preview_personal_target_pair_v1('issuer','subject',NULL,NULL,NULL)$$),
  ($$SELECT app_private.activate_personal_target_merge_generation_v2(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$),
  ($$SELECT app_private.end_known_source_personal_target_merge_generation_v1(NULL,NULL,NULL,NULL,NULL,NULL)$$),
  ($$SELECT app_private.expire_known_source_personal_target_merge_generation_v1(NULL,NULL,NULL,NULL,NULL)$$)
) denied(statement_text);

DO $old_contracts$
DECLARE c record; exported jsonb;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0125_context WHERE kind = 'owner';
  IF (SELECT count(*) FROM app_data.list_assigned_promotion_targets(c.app_user_id,c.workspace_id,c.project_id)) <> 2
  THEN RAISE EXCEPTION '0125 ordinary directory must retain both original targets'; END IF;
  exported := convert_from(app_data.prepare_personal_target_pii_export_v1(c.issuer,c.subject,c.project_id,transaction_timestamp()),'UTF8')::jsonb;
  IF jsonb_array_length(exported->'targets') <> 2 THEN RAISE EXCEPTION '0125 PII export must retain both original targets'; END IF;
END
$old_contracts$;

SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only = on;
SELECT app_private.read_known_source_personal_merge_split_plan_v1(c.app_user_id,c.workspace_id,c.project_id,g.generation_id)
FROM fixture_0125_context c JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
SET LOCAL ROLE tongxingzhe_runtime;
DO $readonly$
DECLARE c record;
BEGIN
  SELECT context_row.*,g.generation_id INTO STRICT c FROM fixture_0125_context context_row JOIN fixture_0125_generations g USING(kind) WHERE kind = 'owner';
  IF current_setting('transaction_read_only') <> 'on'
    OR app_data.read_personal_merge_projection_context_v1(c.issuer,c.subject,c.project_id) IS NULL
  THEN RAISE EXCEPTION '0125 eligibility must work in actual READ ONLY'; END IF;
  BEGIN
    PERFORM app_data.read_personal_known_source_merge_split_plan_v1(c.issuer,c.subject,c.project_id,c.generation_id);
    RAISE EXCEPTION '0125 audited bridge must reject READ ONLY';
  EXCEPTION WHEN read_only_sql_transaction THEN NULL;
  END;
END
$readonly$;
RESET ROLE;
ROLLBACK TO SAVEPOINT readonly_scope;
RELEASE SAVEPOINT readonly_scope;
ROLLBACK;
