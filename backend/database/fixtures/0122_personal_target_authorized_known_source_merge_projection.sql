\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_0122_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0122.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0122.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0122_other ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0122.example.test','other-owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0122.example.test','other-owner') WHERE is_current;
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT '7e800000-0000-4000-8000-000000000090',workspace_id,'0122 other project' FROM fixture_0122_context;
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT ('7e800000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,c.workspace_id,
  CASE WHEN n BETWEEN 3 AND 6 THEN 'institution' ELSE 'person' END,
  '0122 source ' || n,'+1 312 555 0122',CASE WHEN n = 1 THEN NULL ELSE 'same-0122@example.test' END,c.app_user_id
FROM fixture_0122_context c CROSS JOIN generate_series(1,10) n;
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t CROSS JOIN fixture_0122_context c WHERE t.workspace_id = c.workspace_id;

CREATE FUNCTION pg_temp.fixture_0122_links(first_target uuid,second_target uuid) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_agg(jsonb_build_object('targetId',target_id,'targetType','person','responseLevel',2,
    'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true) ORDER BY target_id)
  FROM (VALUES (first_target),(second_target)) t(target_id) WHERE target_id IS NOT NULL
$function$;
CREATE FUNCTION pg_temp.fixture_0122_payload(contact_id text,links jsonb) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object('contactId',contact_id,'workspaceId',workspace_id,'projectId',project_id,
    'questionnaireVersionId',questionnaire_version_id,'reason','0122 synthetic revision',
    'occurredAtUtc',clock_timestamp() - interval '2 days','occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',links)
  FROM fixture_0122_context
$function$;
CREATE FUNCTION pg_temp.fixture_0122_submit(contact_id text,links jsonb) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE result_value text;
BEGIN
  SELECT result_code INTO STRICT result_value FROM app_data.apply_contact_submit_v3(
    (SELECT app_user_id FROM fixture_0122_context),contact_id || '-submit',1,'contact.submit.v1','0122-device',contact_id,0,
    pg_temp.fixture_0122_payload(contact_id,links));
  IF result_value <> 'accepted' THEN RAISE EXCEPTION '0122 contact submit rejected: %',result_value; END IF;
END
$function$;
CREATE FUNCTION pg_temp.fixture_0122_activate(first_target uuid,second_target uuid,request_id uuid)
RETURNS uuid LANGUAGE sql AS $function$
  SELECT app_private.activate_personal_target_merge_generation_v2(
    c.app_user_id,c.project_id,request_id,p.preview_id,first_target,second_target,second_target,first_target)
  FROM fixture_0122_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
    'https://synthetic-0122.example.test','owner',c.project_id,first_target,second_target) p
$function$;
SELECT pg_temp.fixture_0122_submit('0122-pre-contact',
  pg_temp.fixture_0122_links('7e800000-0000-4000-8000-000000000001','7e800000-0000-4000-8000-000000000002'));
CREATE TEMP TABLE fixture_0122_old_generation ON COMMIT DROP AS
SELECT pg_temp.fixture_0122_activate('7e800000-0000-4000-8000-000000000001',
  '7e800000-0000-4000-8000-000000000002','7e800000-0000-4000-8000-000000000101') AS generation_id;
SELECT pg_temp.fixture_0122_submit('0122-old-contact',
  pg_temp.fixture_0122_links('7e800000-0000-4000-8000-000000000001','7e800000-0000-4000-8000-000000000002'));
SELECT app_private.end_known_source_personal_target_merge_generation_v1(
  c.app_user_id,c.workspace_id,c.project_id,'7e800000-0000-4000-8000-000000000201',g.generation_id,m.fact_fingerprint)
FROM fixture_0122_context c CROSS JOIN fixture_0122_old_generation g
CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(g.generation_id) m;
CREATE TEMP TABLE fixture_0122_generations ON COMMIT DROP AS
SELECT 'person' AS kind,pg_temp.fixture_0122_activate('7e800000-0000-4000-8000-000000000001',
  '7e800000-0000-4000-8000-000000000002','7e800000-0000-4000-8000-000000000102') AS generation_id
UNION ALL SELECT 'institution',pg_temp.fixture_0122_activate('7e800000-0000-4000-8000-000000000003',
  '7e800000-0000-4000-8000-000000000004','7e800000-0000-4000-8000-000000000103')
UNION ALL SELECT 'expired',pg_temp.fixture_0122_activate('7e800000-0000-4000-8000-000000000007',
  '7e800000-0000-4000-8000-000000000008','7e800000-0000-4000-8000-000000000104');
UPDATE app_data.promotion_targets SET phone = NULL WHERE promotion_target_id = '7e800000-0000-4000-8000-000000000002';
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = '7e800000-0000-4000-8000-000000000007';
SELECT pg_temp.fixture_0122_submit('0122-current-contact',
  pg_temp.fixture_0122_links('7e800000-0000-4000-8000-000000000001','7e800000-0000-4000-8000-000000000002'));
INSERT INTO app_private.personal_target_merge_generations_v1(generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc)
SELECT '7e800000-0000-4000-8000-000000000109',workspace_id,'person',app_user_id,clock_timestamp() FROM fixture_0122_context;
INSERT INTO app_private.personal_target_merge_generation_members_v1(generation_id,workspace_id,target_type,promotion_target_id)
SELECT '7e800000-0000-4000-8000-000000000109',c.workspace_id,'person',t.id FROM fixture_0122_context c
CROSS JOIN (VALUES ('7e800000-0000-4000-8000-000000000009'::uuid),('7e800000-0000-4000-8000-000000000010'::uuid)) t(id);
INSERT INTO app_private.personal_target_merge_active_members_v1(promotion_target_id,generation_id,workspace_id,target_type)
SELECT promotion_target_id,generation_id,workspace_id,target_type FROM app_private.personal_target_merge_generation_members_v1
WHERE generation_id = '7e800000-0000-4000-8000-000000000109';


-- Exact issuer and subject whitespace identify distinct owners.
INSERT INTO app_data.app_users(app_user_id) VALUES ('7e800000-0000-4000-8000-000000000099');
CREATE TEMP TABLE fixture_0122_exact_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(' https://synthetic-0122.example.test ',' owner ');
SELECT count(*) FROM app_data.list_personal_project_contexts(' https://synthetic-0122.example.test ',' owner ') WHERE is_current;
INSERT INTO app_data.promotion_targets(promotion_target_id,workspace_id,target_type,display_name,phone,created_by_app_user_id)
SELECT t.id,c.workspace_id,'person','0122 exact source','+1 312 555 0122',c.app_user_id
FROM fixture_0122_exact_context c CROSS JOIN (VALUES
  ('7e800000-0000-4000-8000-000000000011'::uuid),('7e800000-0000-4000-8000-000000000012'::uuid)) t(id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT t.promotion_target_id,t.promotion_target_id,c.app_user_id,c.app_user_id
FROM app_data.promotion_targets t JOIN fixture_0122_exact_context c USING(workspace_id);
CREATE TEMP TABLE fixture_0122_exact_generation ON COMMIT DROP AS
SELECT app_private.activate_personal_target_merge_generation_v2(
  c.app_user_id,c.project_id,'7e800000-0000-4000-8000-000000000112',p.preview_id,
  '7e800000-0000-4000-8000-000000000011','7e800000-0000-4000-8000-000000000012',
  '7e800000-0000-4000-8000-000000000011','7e800000-0000-4000-8000-000000000012') AS generation_id
FROM fixture_0122_exact_context c CROSS JOIN LATERAL app_data.preview_personal_target_pair_v1(
  ' https://synthetic-0122.example.test ',' owner ',c.project_id,
  '7e800000-0000-4000-8000-000000000011','7e800000-0000-4000-8000-000000000012') p;

CREATE FUNCTION pg_temp.fixture_0122_state(include_access boolean DEFAULT true) RETURNS jsonb LANGUAGE sql AS $function$
  WITH owners AS (
    SELECT app_user_id FROM app_data.external_identities WHERE btrim(issuer) LIKE 'https://synthetic-0122%'
  ), spaces AS (
    SELECT workspace_id FROM app_data.workspaces WHERE personal_owner_app_user_id IN (SELECT app_user_id FROM owners)
  ), targets AS (
    SELECT promotion_target_id FROM app_data.promotion_targets WHERE workspace_id IN (SELECT workspace_id FROM spaces)
  ), generations AS (
    SELECT generation_id FROM app_private.personal_target_merge_generations_v1 WHERE workspace_id IN (SELECT workspace_id FROM spaces)
  )
  SELECT jsonb_build_object(
    'identities',(SELECT jsonb_agg(to_jsonb(r) ORDER BY external_identity_id) FROM app_data.external_identities r WHERE btrim(issuer) LIKE 'https://synthetic-0122%'),
    'users',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.app_users r WHERE app_user_id IN (SELECT app_user_id FROM owners)),
    'workspaces',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.workspaces r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY project_id) FROM app_data.projects r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'current_projects',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.user_current_projects r WHERE app_user_id IN (SELECT app_user_id FROM owners)),
    'targets',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_data.promotion_targets r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'assignments',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_data.promotion_target_assignments r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'retention_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_retention_events r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'retention_policies',(SELECT jsonb_agg(to_jsonb(r) ORDER BY workspace_id) FROM app_data.promotion_target_retention_policies r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'contacts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id) FROM app_data.contacts r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'contact_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number) FROM app_data.contact_revisions r WHERE contact_id LIKE '0122-%'),
    'contact_links',(SELECT jsonb_agg(to_jsonb(r) ORDER BY contact_id,revision_number,promotion_target_id) FROM app_data.contact_target_links r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'project_relationships',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id) FROM app_data.promotion_target_project_relationships r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'relationship_revisions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id,project_id,revision_number) FROM app_data.promotion_target_relationship_revisions r WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets)),
    'generations',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_generations_v1 r WHERE generation_id IN (SELECT generation_id FROM generations)),
    'members',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id,promotion_target_id) FROM app_private.personal_target_merge_generation_members_v1 r WHERE generation_id IN (SELECT generation_id FROM generations)),
    'maps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY promotion_target_id) FROM app_private.personal_target_merge_active_members_v1 r WHERE generation_id IN (SELECT generation_id FROM generations)),
    'previews',(SELECT jsonb_agg(to_jsonb(r) ORDER BY preview_id) FROM app_private.personal_target_pair_preview_receipts r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'activation_requests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_requests_v1 r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'activation_audit',(SELECT jsonb_agg(to_jsonb(r) ORDER BY actor_app_user_id,request_id) FROM app_private.personal_target_merge_activation_audit_v1 r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'end_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY generation_id) FROM app_private.personal_target_merge_end_events_v1 r WHERE generation_id IN (SELECT generation_id FROM generations)),
    'assignment_end_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY assignment_id) FROM app_private.personal_target_assignment_end_events_v1 r WHERE assignment_id IN (SELECT assignment_id FROM app_data.promotion_target_assignments WHERE promotion_target_id IN (SELECT promotion_target_id FROM targets))),
    'pii_export_events',(SELECT jsonb_agg(to_jsonb(r) ORDER BY export_event_id) FROM app_private.personal_target_pii_export_events r WHERE workspace_id IN (SELECT workspace_id FROM spaces)),
    'access',CASE WHEN include_access THEN (SELECT jsonb_agg(to_jsonb(r) ORDER BY event_id) FROM app_data.promotion_target_access_events r WHERE workspace_id IN (SELECT workspace_id FROM spaces)) END,
    'fence',(SELECT to_jsonb(r) FROM app_private.personal_target_merge_generation_fence_v1 r))
$function$;

CREATE FUNCTION pg_temp.fixture_0122_read(generation_id uuid) RETURNS jsonb LANGUAGE sql AS $function$
  SELECT app_private.read_authorized_known_source_personal_merge_projection_v1(
    'https://synthetic-0122.example.test','owner',project_id,generation_id) FROM fixture_0122_context
$function$;
CREATE FUNCTION pg_temp.expect_0122_failure(expected_state text,statement_text text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0122_state();
BEGIN
  BEGIN EXECUTE statement_text;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM expected_state THEN RAISE EXCEPTION '0122 expected %, got % for %',expected_state,actual_state,statement_text; END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0122_state() THEN RAISE EXCEPTION '0122 failed read left state or audit writes'; END IF;
END
$function$;

DO $successful_reads$
DECLARE before_state jsonb := pg_temp.fixture_0122_state(false); before_events uuid[]; document jsonb; expected jsonb; row_value record;
BEGIN
  FOR row_value IN SELECT c.*,g.generation_id,'https://synthetic-0122.example.test' AS issuer,'owner' AS subject
      FROM fixture_0122_context c CROSS JOIN fixture_0122_generations g WHERE g.kind IN ('person','institution')
    UNION ALL SELECT c.*,g.generation_id,' https://synthetic-0122.example.test ',' owner '
      FROM fixture_0122_exact_context c CROSS JOIN fixture_0122_exact_generation g
  LOOP
    expected := app_private.read_known_source_personal_target_merge_projection_v1(
      row_value.app_user_id,row_value.workspace_id,row_value.project_id,row_value.generation_id);
    FOR i IN 1..2 LOOP
      SELECT array_agg(event_id) INTO before_events FROM app_data.promotion_target_access_events WHERE workspace_id = row_value.workspace_id;
      document := app_private.read_authorized_known_source_personal_merge_projection_v1(
        row_value.issuer,row_value.subject,row_value.project_id,row_value.generation_id);
      IF document IS DISTINCT FROM expected OR document IS NULL
        OR (SELECT count(*) FROM app_data.promotion_target_access_events WHERE workspace_id = row_value.workspace_id
          AND NOT(event_id = ANY(coalesce(before_events,'{}'::uuid[])))) <> 2
        OR (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id)
            FROM app_data.promotion_target_access_events WHERE workspace_id = row_value.workspace_id
              AND NOT(event_id = ANY(coalesce(before_events,'{}'::uuid[])))) IS DISTINCT FROM
            (SELECT array_agg((s->>'target_id')::uuid ORDER BY (s->>'target_id')::uuid) FROM jsonb_array_elements(document->'sources') s)
        OR EXISTS (SELECT 1 FROM app_data.promotion_target_access_events WHERE workspace_id = row_value.workspace_id
          AND NOT(event_id = ANY(coalesce(before_events,'{}'::uuid[])))
          AND (actor_app_user_id <> row_value.app_user_id OR action <> 'viewed'))
      THEN RAISE EXCEPTION '0122 successful/repeated read projection or two-source audit drift'; END IF;
    END LOOP;
  END LOOP;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0122_state(false) THEN RAISE EXCEPTION '0122 successful read changed business/ledger state'; END IF;
  IF (SELECT app_user_id FROM fixture_0122_context) = (SELECT app_user_id FROM fixture_0122_exact_context)
    OR (SELECT pg_temp.fixture_0122_read(generation_id)->'phone' FROM fixture_0122_generations WHERE kind = 'person') <> 'null'::jsonb
    OR (SELECT pg_temp.fixture_0122_read(generation_id)->'email' FROM fixture_0122_generations WHERE kind = 'person') <> 'null'::jsonb
  THEN RAISE EXCEPTION '0122 exact identity or selected NULL drift'; END IF;
END
$successful_reads$;

SELECT pg_temp.expect_0122_failure('22023',format(
  'SELECT app_private.read_authorized_known_source_personal_merge_projection_v1(%L,%L,%L,%L)',issuer,subject,p,g))
FROM fixture_0122_context c CROSS JOIN fixture_0122_generations x CROSS JOIN LATERAL (VALUES
  (NULL::text,'owner',c.project_id,x.generation_id),('https://synthetic-0122.example.test',NULL::text,c.project_id,x.generation_id),
  ('','owner',c.project_id,x.generation_id),('  ','owner',c.project_id,x.generation_id),
  ('https://synthetic-0122.example.test','',c.project_id,x.generation_id),('https://synthetic-0122.example.test',' ',c.project_id,x.generation_id),
  (repeat('x',2049),'owner',c.project_id,x.generation_id),('https://synthetic-0122.example.test',repeat('x',513),c.project_id,x.generation_id),
  ('https://synthetic-0122.example.test','owner',NULL::uuid,x.generation_id),('https://synthetic-0122.example.test','owner',c.project_id,NULL::uuid)
) bad(issuer,subject,p,g) WHERE x.kind = 'person';
SELECT pg_temp.expect_0122_failure('42501',format(
  'SELECT app_private.read_authorized_known_source_personal_merge_projection_v1(%L,%L,%L,%L)',issuer,subject,p,x.generation_id))
FROM fixture_0122_context c CROSS JOIN fixture_0122_other o CROSS JOIN fixture_0122_generations x CROSS JOIN LATERAL (VALUES
  ('https://synthetic-0122-unknown.example.test','never-known',c.project_id),
  ('https://synthetic-0122.example.test','never-known',c.project_id),
  ('https://synthetic-0122.example.test','other-owner',c.project_id),
  ('https://synthetic-0122.example.test','other-owner',o.project_id),
  ('https://synthetic-0122.example.test','owner','7e800000-0000-4000-8000-000000000090'::uuid),
  ('https://synthetic-0122.example.test',' owner ',c.project_id),
  (' https://synthetic-0122.example.test ','owner',c.project_id)
) bad(issuer,subject,p) WHERE x.kind = 'person';
SELECT pg_temp.expect_0122_failure('42501',format(
  'SELECT app_private.read_authorized_known_source_personal_merge_projection_v1(%L,%L,%L,%L)',
  'https://synthetic-0122.example.test','owner',c.project_id,g.generation_id))
FROM fixture_0122_exact_context c CROSS JOIN fixture_0122_exact_generation g;
SELECT pg_temp.expect_0122_failure('42501',format('SELECT pg_temp.fixture_0122_read(%L)',generation_id)) FROM fixture_0122_old_generation;
SELECT pg_temp.expect_0122_failure('42501',format('SELECT pg_temp.fixture_0122_read(%L)',generation_id)) FROM fixture_0122_generations WHERE kind = 'expired';
SELECT pg_temp.expect_0122_failure('42501',$$SELECT pg_temp.fixture_0122_read('7e800000-0000-4000-8000-000000000199')$$);
SELECT pg_temp.expect_0122_failure('55000',$$SELECT pg_temp.fixture_0122_read('7e800000-0000-4000-8000-000000000109')$$);

DO $authorization_gates$
DECLARE change_statement text;
BEGIN
  FOREACH change_statement IN ARRAY ARRAY[
    $$UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = (SELECT app_user_id FROM fixture_0122_context)$$,
    $$UPDATE app_data.app_users SET status = 'deleted' WHERE app_user_id = (SELECT app_user_id FROM fixture_0122_context)$$,
    $$UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = (SELECT workspace_id FROM fixture_0122_context)$$,
    $$UPDATE app_data.workspaces SET personal_owner_app_user_id = '7e800000-0000-4000-8000-000000000099' WHERE workspace_id = (SELECT workspace_id FROM fixture_0122_context)$$,
    $$DELETE FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0122_context)$$,
    $$UPDATE app_data.user_current_projects SET project_id = '7e800000-0000-4000-8000-000000000090' WHERE app_user_id = (SELECT app_user_id FROM fixture_0122_context)$$,
    $$UPDATE app_data.projects SET status = 'archived' WHERE project_id = (SELECT project_id FROM fixture_0122_context)$$,
    $$UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'user_requested' WHERE assignment_id = '7e800000-0000-4000-8000-000000000002'$$,
    $$UPDATE app_data.promotion_targets SET status = 'anonymized',phone = NULL,email = NULL,
      anonymized_at = clock_timestamp(),anonymization_reason = 'withdrawal'
      WHERE promotion_target_id = '7e800000-0000-4000-8000-000000000002'$$,
    $$WITH stale_contacts AS (
      UPDATE app_data.contacts SET occurred_at_utc = clock_timestamp() - interval '14 months'
      WHERE contact_id LIKE '0122-%' RETURNING contact_id
    ) UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
      WHERE promotion_target_id = '7e800000-0000-4000-8000-000000000002'$$
  ] LOOP
    BEGIN
      EXECUTE change_statement;
      PERFORM pg_temp.expect_0122_failure('42501',format('SELECT pg_temp.fixture_0122_read(%L)',generation_id))
      FROM fixture_0122_generations WHERE kind = 'person';
      RAISE EXCEPTION USING ERRCODE = 'ZX122',MESSAGE = 'rollback synthetic authorization change';
    EXCEPTION WHEN SQLSTATE 'ZX122' THEN NULL;
    END;
  END LOOP;
END
$authorization_gates$;

SAVEPOINT incomplete_choice;
SET LOCAL session_replication_role = replica;
UPDATE app_private.personal_target_merge_activation_requests_v1 SET phone_source_target_id = '7e800000-0000-4000-8000-000000000003'
WHERE generation_id = (SELECT generation_id FROM fixture_0122_generations WHERE kind = 'person');
SET LOCAL session_replication_role = origin;
SELECT pg_temp.expect_0122_failure('55000',format('SELECT pg_temp.fixture_0122_read(%L)',generation_id)) FROM fixture_0122_generations WHERE kind = 'person';
ROLLBACK TO SAVEPOINT incomplete_choice;
RELEASE SAVEPOINT incomplete_choice;

-- The trigger lets the first event insert, then aborts the second in the same command.
CREATE TEMP TABLE fixture_0122_audit_probe(n integer);
INSERT INTO fixture_0122_audit_probe VALUES (0);
CREATE FUNCTION pg_temp.fail_second_0122_audit() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE event_number integer;
BEGIN
  IF NEW.workspace_id = (SELECT workspace_id FROM fixture_0122_context) AND NEW.action = 'viewed' THEN
    UPDATE fixture_0122_audit_probe SET n = n + 1 RETURNING n INTO event_number;
    IF event_number = 2 THEN
      IF TG_NARGS = 1 AND TG_ARGV[0] = 'skip' THEN RETURN NULL; END IF;
      RAISE EXCEPTION USING ERRCODE = 'ZXAUD',MESSAGE = 'synthetic second audit failure';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0122_fail_second_audit BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_0122_audit();
SELECT pg_temp.expect_0122_failure('ZXAUD',format('SELECT pg_temp.fixture_0122_read(%L)',generation_id)) FROM fixture_0122_generations WHERE kind = 'person';
DO $audit_rollback$ BEGIN
  IF (SELECT n FROM fixture_0122_audit_probe) <> 0 THEN RAISE EXCEPTION '0122 first audit/probe did not roll back'; END IF;
END $audit_rollback$;
DROP TRIGGER fixture_0122_fail_second_audit ON app_data.promotion_target_access_events;

CREATE TRIGGER fixture_0122_skip_second_audit BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_0122_audit('skip');
SELECT pg_temp.expect_0122_failure('55000',format('SELECT pg_temp.fixture_0122_read(%L)',generation_id)) FROM fixture_0122_generations WHERE kind = 'person';
DO $audit_count_rollback$ BEGIN
  IF (SELECT n FROM fixture_0122_audit_probe) <> 0 THEN RAISE EXCEPTION '0122 incomplete audit insert/probe did not roll back'; END IF;
END $audit_count_rollback$;
DROP TRIGGER fixture_0122_skip_second_audit ON app_data.promotion_target_access_events;

SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only = on;
DO $readonly_contract$
DECLARE c record; g uuid; document jsonb;
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN RAISE EXCEPTION '0122 expected actual READ ONLY'; END IF;
  SELECT * INTO STRICT c FROM fixture_0122_context;
  SELECT generation_id INTO STRICT g FROM fixture_0122_generations WHERE kind = 'person';
  document := app_private.read_known_source_personal_target_merge_projection_v1(c.app_user_id,c.workspace_id,c.project_id,g);
  IF document IS NULL THEN RAISE EXCEPTION '0121 READ ONLY projection missing'; END IF;
  PERFORM pg_temp.expect_0122_failure('25006',format('SELECT pg_temp.fixture_0122_read(%L)',g));
END
$readonly_contract$;
ROLLBACK TO SAVEPOINT readonly_scope;
RELEASE SAVEPOINT readonly_scope;

GRANT SELECT ON fixture_0122_context,fixture_0122_generations TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
DO $runtime_denied$
DECLARE actual_state text; project_id uuid; generation_id uuid;
BEGIN
  SELECT c.project_id,g.generation_id INTO STRICT project_id,generation_id
  FROM fixture_0122_context c CROSS JOIN fixture_0122_generations g WHERE kind = 'person';
  BEGIN
    PERFORM app_private.read_authorized_known_source_personal_merge_projection_v1(
      'https://synthetic-0122.example.test','owner',project_id,generation_id);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '0122 runtime direct execution was not denied: %',actual_state; END IF;
END
$runtime_denied$;
RESET ROLE;

ROLLBACK;
