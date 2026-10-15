\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0126_context ON COMMIT DROP AS
SELECT identity.kind,identity.issuer,identity.subject,c.* FROM (VALUES
  ('owner','https://synthetic-0126.example.test','owner'),
  ('exact',' https://synthetic-0126.example.test ',' owner '),
  ('other','https://synthetic-0126.example.test','other')
) identity(kind,issuer,subject)
CROSS JOIN LATERAL app_data.bootstrap_personal_context(identity.issuer,identity.subject) c;
SELECT count(*) FROM fixture_0126_context c
CROSS JOIN LATERAL app_data.list_personal_project_contexts(c.issuer,c.subject) p WHERE p.is_current;
INSERT INTO app_data.app_users(app_user_id) VALUES ('7f260000-0000-4000-8000-000000999999');
CREATE TEMP TABLE fixture_0126_pairs ON COMMIT DROP AS
SELECT n,c.app_user_id,c.workspace_id,c.project_id,
  ('7f260000-0000-4000-8000-' || lpad((100000+n)::text,12,'0'))::uuid AS generation_id,
  ('7f260000-0000-4000-8000-' || lpad((2*n-1)::text,12,'0'))::uuid AS first_target,
  ('7f260000-0000-4000-8000-' || lpad((2*n)::text,12,'0'))::uuid AS second_target,
  CASE WHEN n % 2 = 0 THEN 'institution' ELSE 'person' END AS target_type
FROM generate_series(1,61) n JOIN fixture_0126_context c
  ON c.kind = CASE WHEN n = 61 THEN 'exact' ELSE 'owner' END;
INSERT INTO app_data.promotion_targets(
  promotion_target_id,workspace_id,target_type,display_name,phone,email,created_by_app_user_id
)
SELECT target_id,p.workspace_id,p.target_type,'0126 synthetic source','+1 312 555 0126',NULL,p.app_user_id
FROM fixture_0126_pairs p CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_data.promotion_target_assignments(assignment_id,promotion_target_id,app_user_id,assigned_by_app_user_id)
SELECT target_id,target_id,p.app_user_id,p.app_user_id FROM fixture_0126_pairs p
CROSS JOIN LATERAL (VALUES(p.first_target),(p.second_target)) t(target_id);
INSERT INTO app_private.personal_target_merge_generations_v1(generation_id,workspace_id,target_type,created_by_app_user_id,activated_at_utc)
SELECT generation_id,workspace_id,target_type,app_user_id,clock_timestamp() FROM fixture_0126_pairs;
INSERT INTO app_private.personal_target_merge_generation_members_v1(generation_id,workspace_id,target_type,promotion_target_id)
SELECT generation_id,workspace_id,target_type,target_id FROM fixture_0126_pairs
CROSS JOIN LATERAL (VALUES(first_target),(second_target)) t(target_id);
INSERT INTO app_private.personal_target_merge_active_members_v1(promotion_target_id,generation_id,workspace_id,target_type)
SELECT promotion_target_id,generation_id,workspace_id,target_type
FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id IN (SELECT generation_id FROM fixture_0126_pairs);
INSERT INTO app_private.personal_target_merge_activation_requests_v1(
  actor_app_user_id,request_id,workspace_id,preview_id,retained_target_id,display_name_source_target_id,
  phone_source_target_id,email_source_target_id,generation_id,activated_at_utc
)
SELECT app_user_id,('7f260000-0000-4000-8000-' || lpad((200000+n)::text,12,'0'))::uuid,workspace_id,
  ('7f260000-0000-4000-8000-' || lpad((300000+n)::text,12,'0'))::uuid,
  first_target,first_target,second_target,first_target,generation_id,clock_timestamp()
FROM fixture_0126_pairs WHERE n <> 46;
SELECT app_private.end_known_source_personal_target_merge_generation_v1(
  p.app_user_id,p.workspace_id,p.project_id,'7f260000-0000-4000-8000-000000400047',p.generation_id,m.fact_fingerprint)
FROM fixture_0126_pairs p CROSS JOIN LATERAL app_private.personal_target_merge_known_source_manifest_v1(p.generation_id) m WHERE n = 47;
UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '14 months'
WHERE promotion_target_id = (SELECT first_target FROM fixture_0126_pairs WHERE n = 48);
UPDATE app_data.promotion_target_assignments SET ended_at = clock_timestamp(),end_reason = 'user_requested'
WHERE promotion_target_id = (SELECT second_target FROM fixture_0126_pairs WHERE n = 49);
DELETE FROM app_private.personal_target_merge_active_members_v1
WHERE promotion_target_id = (SELECT second_target FROM fixture_0126_pairs WHERE n = 51);
UPDATE app_data.promotion_targets SET status = 'anonymized',phone = NULL,email = NULL,
  anonymized_at = clock_timestamp(),anonymization_reason = 'withdrawal'
WHERE promotion_target_id = (SELECT second_target FROM fixture_0126_pairs WHERE n = 53);
SET LOCAL session_replication_role = replica;
UPDATE app_private.personal_target_merge_activation_requests_v1 SET phone_source_target_id = '7f260000-0000-4000-8000-000000999999'
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 50);
UPDATE app_private.personal_target_merge_generation_members_v1 SET workspace_id = (SELECT workspace_id FROM fixture_0126_context WHERE kind = 'other')
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 52);
UPDATE app_private.personal_target_merge_activation_requests_v1 SET display_name_source_target_id = '7f260000-0000-4000-8000-000000999999'
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 54);
UPDATE app_private.personal_target_merge_activation_requests_v1 SET email_source_target_id = '7f260000-0000-4000-8000-000000999999'
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 55);
UPDATE app_private.personal_target_merge_activation_requests_v1 SET retained_target_id = '7f260000-0000-4000-8000-000000999999'
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 56);
UPDATE app_private.personal_target_merge_activation_requests_v1 SET actor_app_user_id = (SELECT app_user_id FROM fixture_0126_context WHERE kind = 'other')
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 57);
UPDATE app_private.personal_target_merge_activation_requests_v1 SET workspace_id = (SELECT workspace_id FROM fixture_0126_context WHERE kind = 'other')
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 58);
UPDATE app_private.personal_target_merge_generation_members_v1 SET target_type = 'institution'
WHERE generation_id = (SELECT generation_id FROM fixture_0126_pairs WHERE n = 59);
SET LOCAL session_replication_role = origin;
INSERT INTO app_private.personal_target_merge_generation_members_v1(generation_id,workspace_id,target_type,promotion_target_id)
SELECT generation_id,workspace_id,target_type,'7f260000-0000-4000-8000-000000999998' FROM fixture_0126_pairs WHERE n = 60;
INSERT INTO app_private.personal_target_merge_active_members_v1(promotion_target_id,generation_id,workspace_id,target_type)
SELECT promotion_target_id,generation_id,workspace_id,target_type FROM app_private.personal_target_merge_generation_members_v1
WHERE promotion_target_id = '7f260000-0000-4000-8000-000000999998';

CREATE FUNCTION pg_temp.fixture_0126_workspace_state(requested_workspace_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $function$
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

CREATE FUNCTION pg_temp.fixture_0126_state() RETURNS jsonb LANGUAGE sql STABLE AS $function$
  SELECT jsonb_build_object(
    'users',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.app_users r),
    'identities',(SELECT jsonb_agg(to_jsonb(r) ORDER BY external_identity_id) FROM app_data.external_identities r),
    'current',(SELECT jsonb_agg(to_jsonb(r) ORDER BY app_user_id) FROM app_data.user_current_projects r),
    'business',(SELECT jsonb_agg(pg_temp.fixture_0126_workspace_state(workspace_id) ORDER BY workspace_id) FROM fixture_0126_context),
    'audit',(SELECT count(*) FROM app_data.promotion_target_access_events))
$function$;
CREATE FUNCTION pg_temp.expect_0126_failure(expected_state text,statement_text text) RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; before_state jsonb := pg_temp.fixture_0126_state();
BEGIN
  BEGIN
    SET LOCAL ROLE tongxingzhe_runtime;
    EXECUTE statement_text;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
  END;
  RESET ROLE;
  IF actual_state IS DISTINCT FROM expected_state THEN RAISE EXCEPTION '0126 expected %, got %',expected_state,actual_state; END IF;
  IF before_state IS DISTINCT FROM pg_temp.fixture_0126_state() THEN RAISE EXCEPTION '0126 rejected directory changed facts/context/audit'; END IF;
END
$function$;
CREATE FUNCTION pg_temp.fixture_0126_read(after_id uuid,owner_kind text DEFAULT 'owner') RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE c record; document jsonb; expected_ids uuid[]; actual_ids uuid[]; before_ids uuid[]; before_business jsonb;
  item jsonb; pair_row record; expected_next uuid; remaining_count bigint;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0126_context WHERE kind = owner_kind;
  before_business := pg_temp.fixture_0126_state() - 'audit';
  SELECT array_agg(event_id) INTO before_ids FROM app_data.promotion_target_access_events;
  SELECT count(*) INTO remaining_count FROM fixture_0126_pairs
    WHERE app_user_id = c.app_user_id AND (n <= 45 OR n = 61) AND (after_id IS NULL OR generation_id > after_id);
  SELECT array_agg(generation_id ORDER BY generation_id) INTO expected_ids FROM (
    SELECT generation_id FROM fixture_0126_pairs WHERE app_user_id = c.app_user_id
      AND (n <= 45 OR n = 61) AND (after_id IS NULL OR generation_id > after_id)
    ORDER BY generation_id LIMIT 20
  ) page;
  SET LOCAL ROLE tongxingzhe_runtime;
  document := app_data.read_personal_merge_directory_v1(c.issuer,c.subject,c.project_id,after_id);
  RESET ROLE;
  SELECT array_agg((value->>'generation_id')::uuid ORDER BY ordinal) INTO actual_ids
  FROM jsonb_array_elements(document->'items') WITH ORDINALITY items(value,ordinal);
  IF remaining_count > 20 THEN expected_next := expected_ids[20]; END IF;
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(document) key) <> ARRAY['items','next_cursor','project_id','workspace_id']::text[]
    OR document->>'workspace_id' IS DISTINCT FROM c.workspace_id::text
    OR document->>'project_id' IS DISTINCT FROM c.project_id::text
    OR actual_ids IS DISTINCT FROM expected_ids OR document->>'next_cursor' IS DISTINCT FROM expected_next::text
    OR (SELECT count(*) FROM app_data.promotion_target_access_events WHERE NOT(event_id = ANY(coalesce(before_ids,'{}'::uuid[]))))
      <> 2 * coalesce(cardinality(expected_ids),0)
  THEN RAISE EXCEPTION '0126 directory keys, scope, page order, cursor or audit count drift'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(document->'items') LOOP
    SELECT * INTO STRICT pair_row FROM fixture_0126_pairs WHERE generation_id = (item->>'generation_id')::uuid;
    IF item IS DISTINCT FROM jsonb_build_object('generation_id',pair_row.generation_id,'target_type',pair_row.target_type,
      'retained_target_id',pair_row.first_target,'member_target_ids',ARRAY[pair_row.first_target,pair_row.second_target],
      'review_due_at_utc',to_char(least(app_data.promotion_target_review_due_at(pair_row.first_target),
        app_data.promotion_target_review_due_at(pair_row.second_target)) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
    THEN RAISE EXCEPTION '0126 item keys, type, pair or current due drift'; END IF;
  END LOOP;
  IF (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id) FROM app_data.promotion_target_access_events
      WHERE NOT(event_id = ANY(coalesce(before_ids,'{}'::uuid[])))) IS DISTINCT FROM
      (SELECT array_agg(target_id ORDER BY target_id) FROM fixture_0126_pairs p
        CROSS JOIN LATERAL (VALUES(first_target),(second_target)) t(target_id) WHERE generation_id = ANY(expected_ids))
    OR EXISTS (SELECT 1 FROM app_data.promotion_target_access_events WHERE NOT(event_id = ANY(coalesce(before_ids,'{}'::uuid[])))
      AND (workspace_id <> c.workspace_id OR actor_app_user_id <> c.app_user_id OR action <> 'viewed' OR occurred_at <> statement_timestamp()))
    OR before_business IS DISTINCT FROM (pg_temp.fixture_0126_state() - 'audit')
  THEN RAISE EXCEPTION '0126 directory audited an unreturned member, changed timestamp or wrote business facts'; END IF;
  RETURN document;
END
$function$;
GRANT SELECT ON fixture_0126_context,fixture_0126_pairs TO tongxingzhe_runtime;
SELECT pg_temp.fixture_0126_read(NULL);
SELECT pg_temp.fixture_0126_read(NULL);
SELECT pg_temp.fixture_0126_read('7f260000-0000-4000-8000-000000100020');
SELECT pg_temp.fixture_0126_read('7f260000-0000-4000-8000-000000100040');
SELECT pg_temp.fixture_0126_read('7f260000-0000-4000-8000-000000100024');
SELECT pg_temp.fixture_0126_read('7f260000-0000-4000-8000-000000100025');
SELECT pg_temp.fixture_0126_read('7f260000-0000-4000-8000-000000100000');
SELECT pg_temp.fixture_0126_read('00000000-0000-0000-0000-000000000000');
SELECT pg_temp.fixture_0126_read('ffffffff-ffff-ffff-ffff-ffffffffffff');
SELECT pg_temp.fixture_0126_read(NULL,'exact');
SELECT pg_temp.fixture_0126_read(NULL,'other');

SELECT pg_temp.expect_0126_failure('42501',format('SELECT app_data.read_personal_merge_directory_v1(%L,%L,%L,NULL)',bad.issuer,bad.subject,bad.project_id))
FROM fixture_0126_context c CROSS JOIN LATERAL (VALUES
  (c.issuer,'unknown',c.project_id),(c.issuer,' owner ',c.project_id),
  (' https://synthetic-0126.example.test ','owner',c.project_id),
  (c.issuer,'other',c.project_id),(c.issuer,c.subject,'7f260000-0000-4000-8000-000000999999'::uuid)
) bad(issuer,subject,project_id) WHERE kind = 'owner';
SELECT pg_temp.expect_0126_failure('22023',format('SELECT app_data.read_personal_merge_directory_v1(%L,%L,%L,NULL)',bad.issuer,bad.subject,bad.project_id))
FROM fixture_0126_context c CROSS JOIN LATERAL (VALUES
  (NULL::text,c.subject,c.project_id),('',c.subject,c.project_id),(' ',c.subject,c.project_id),
  (repeat('x',2049),c.subject,c.project_id),(c.issuer,NULL::text,c.project_id),
  (c.issuer,'',c.project_id),(c.issuer,repeat('x',513),c.project_id),(c.issuer,c.subject,NULL::uuid)
) bad(issuer,subject,project_id) WHERE kind = 'owner';
DO $revocation$
DECLARE change_statement text;
BEGIN
  FOREACH change_statement IN ARRAY ARRAY[
    $$UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = (SELECT app_user_id FROM fixture_0126_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.app_users SET status = 'deleted' WHERE app_user_id = (SELECT app_user_id FROM fixture_0126_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = (SELECT workspace_id FROM fixture_0126_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.workspaces SET personal_owner_app_user_id = '7f260000-0000-4000-8000-000000999999' WHERE workspace_id = (SELECT workspace_id FROM fixture_0126_context WHERE kind = 'owner')$$,
    $$DELETE FROM app_data.user_current_projects WHERE app_user_id = (SELECT app_user_id FROM fixture_0126_context WHERE kind = 'owner')$$,
    $$UPDATE app_data.projects SET status = 'archived' WHERE project_id = (SELECT project_id FROM fixture_0126_context WHERE kind = 'owner')$$
  ] LOOP
    BEGIN
      EXECUTE change_statement;
      PERFORM pg_temp.expect_0126_failure('42501',format('SELECT app_data.read_personal_merge_directory_v1(%L,%L,%L,NULL)',issuer,subject,project_id))
      FROM fixture_0126_context WHERE kind = 'owner';
      RAISE EXCEPTION USING ERRCODE = 'ZX126',MESSAGE = 'rollback synthetic directory revocation';
    EXCEPTION WHEN SQLSTATE 'ZX126' THEN NULL;
    END;
  END LOOP;
END
$revocation$;
CREATE TEMP TABLE fixture_0126_audit_probe(n integer);
INSERT INTO fixture_0126_audit_probe VALUES (0);
CREATE FUNCTION pg_temp.fail_second_0126_audit() RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE event_number integer;
BEGIN
  UPDATE fixture_0126_audit_probe SET n = n + 1 RETURNING n INTO event_number;
  IF event_number = 2 THEN
    IF TG_NARGS = 1 AND TG_ARGV[0] = 'skip' THEN RETURN NULL; END IF;
    RAISE EXCEPTION USING ERRCODE = 'ZXAU6',MESSAGE = 'synthetic second audit failure';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0126_fail_audit BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_0126_audit();
SELECT pg_temp.expect_0126_failure('ZXAU6',format('SELECT app_data.read_personal_merge_directory_v1(%L,%L,%L,NULL)',issuer,subject,project_id))
FROM fixture_0126_context WHERE kind = 'owner';
DROP TRIGGER fixture_0126_fail_audit ON app_data.promotion_target_access_events;
CREATE TRIGGER fixture_0126_skip_audit BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_second_0126_audit('skip');
SELECT pg_temp.expect_0126_failure('55000',format('SELECT app_data.read_personal_merge_directory_v1(%L,%L,%L,NULL)',issuer,subject,project_id))
FROM fixture_0126_context WHERE kind = 'owner';
DROP TRIGGER fixture_0126_skip_audit ON app_data.promotion_target_access_events;
DO $audit_rollback$ BEGIN
  IF (SELECT n FROM fixture_0126_audit_probe) <> 0 THEN RAISE EXCEPTION '0126 audit/probe did not roll back'; END IF;
END $audit_rollback$;
SELECT pg_temp.expect_0126_failure('42501',$$SELECT app_private.read_authorized_personal_merge_directory_v1('issuer','subject',NULL,NULL)$$);
SAVEPOINT readonly_scope;
SET LOCAL transaction_read_only = on;
SELECT pg_temp.expect_0126_failure('25006',format('SELECT app_data.read_personal_merge_directory_v1(%L,%L,%L,NULL)',issuer,subject,project_id))
FROM fixture_0126_context WHERE kind IN ('owner','other');
ROLLBACK TO SAVEPOINT readonly_scope;
RELEASE SAVEPOINT readonly_scope;
ROLLBACK;
