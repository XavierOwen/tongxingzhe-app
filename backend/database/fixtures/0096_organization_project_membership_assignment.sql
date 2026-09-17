-- Rollback-only synthetic identities; not production identity proof.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE FUNCTION pg_temp.expect_0096_failure(state text, message text, statement text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM state OR (message IS NOT NULL AND actual_message IS DISTINCT FROM message)
  THEN RAISE EXCEPTION '0096 expected % / %, got % / %',state,message,actual_state,actual_message; END IF;
END
$function$;
INSERT INTO app_data.app_users(app_user_id,status) VALUES
  ('00000000-0096-4000-8000-000000000001','active'),
  ('00000000-0096-4000-8000-000000000002','active'),
  ('00000000-0096-4000-8000-000000000003','active');
INSERT INTO app_data.external_identities(external_identity_id,issuer,subject,app_user_id) VALUES
  ('00000000-0096-4100-8000-000000000001','https://synthetic-0096.example',' owner exact ',
   '00000000-0096-4000-8000-000000000001'),
  ('00000000-0096-4100-8000-000000000002','https://synthetic-0096.example','target',
   '00000000-0096-4000-8000-000000000002');
CREATE TEMP TABLE fixture_0096_org AS SELECT * FROM app_private.create_organization_v1(
  '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000001','0096 organization');
INSERT INTO app_data.organization_memberships SELECT
  '00000000-0096-4200-8000-000000000002',organization_workspace_id,
  '00000000-0096-4000-8000-000000000002',clock_timestamp()-interval '1 year',clock_timestamp()+interval '1 year'
FROM fixture_0096_org;
INSERT INTO app_data.organization_memberships SELECT
  '00000000-0096-4200-8000-000000000003',organization_workspace_id,
  '00000000-0096-4000-8000-000000000003',clock_timestamp()-interval '1 year',clock_timestamp()-interval '1 day'
FROM fixture_0096_org;
INSERT INTO app_data.projects(project_id,workspace_id,display_name)
SELECT id,organization_workspace_id,'0096 project' FROM fixture_0096_org CROSS JOIN
  (VALUES ('00000000-0096-4300-8000-000000000001'::uuid),
          ('00000000-0096-4300-8000-000000000002'::uuid),
          ('00000000-0096-4300-8000-000000000003'::uuid),
          ('00000000-0096-4300-8000-000000000004'::uuid)) AS projects(id);
-- Ended history is retained; a future overlap is rejected without changing it.
INSERT INTO app_data.project_memberships VALUES
  ('00000000-0096-4400-8000-000000000001','00000000-0096-4200-8000-000000000002',
   '00000000-0096-4300-8000-000000000001',clock_timestamp()-interval '2 months',clock_timestamp()-interval '1 month'),
  ('00000000-0096-4400-8000-000000000003','00000000-0096-4200-8000-000000000002',
   '00000000-0096-4300-8000-000000000003',clock_timestamp()+interval '1 month',clock_timestamp()+interval '2 months');
CREATE TEMP TABLE fixture_0096_before AS SELECT
  (SELECT count(*) FROM app_data.organization_memberships) AS parents,
  (SELECT count(*) FROM app_data.organization_owner_assignments) AS owners,
  (SELECT count(*) FROM app_data.management_report_capability_grants) AS grants;
CREATE TEMP TABLE fixture_0096_first AS SELECT receipt.* FROM fixture_0096_org AS org,
  LATERAL app_data.assign_organization_project_member_for_identity_v1(
    'https://synthetic-0096.example',' owner exact ','00000000-0096-5000-8000-000000000002',
    org.organization_workspace_id,'00000000-0096-4300-8000-000000000001',
    '00000000-0096-4200-8000-000000000002') AS receipt;
CREATE TEMP TABLE fixture_0096_replay AS SELECT receipt.* FROM fixture_0096_org AS org,
  LATERAL app_data.assign_organization_project_member_for_identity_v1(
    'https://synthetic-0096.example',' owner exact ','00000000-0096-5000-8000-000000000002',
    org.organization_workspace_id,'00000000-0096-4300-8000-000000000001',
    '00000000-0096-4200-8000-000000000002') AS receipt;
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0096_org);
  request text; receipt fixture_0096_first%ROWTYPE;
BEGIN
  SELECT * INTO STRICT receipt FROM fixture_0096_first;
  IF EXISTS ((TABLE fixture_0096_first EXCEPT TABLE fixture_0096_replay)
    UNION ALL (TABLE fixture_0096_replay EXCEPT TABLE fixture_0096_first))
    OR receipt.project_membership_assignment_contract_id <> 'organization-project-membership-assignment:v1'
    OR receipt.active_from_utc <= transaction_timestamp()
    OR NOT EXISTS (SELECT 1 FROM app_data.project_memberships AS child
      JOIN app_data.organization_memberships AS parent USING(organization_membership_id)
      JOIN app_private.organization_project_membership_assignment_request_claims AS claim USING(project_membership_id)
      JOIN app_private.organization_project_membership_assignment_audit_events AS audit USING(project_membership_id)
      WHERE child.project_membership_id = receipt.project_membership_id
        AND child.active_from_utc = receipt.active_from_utc AND child.inactive_from_utc = parent.inactive_from_utc
        AND claim.active_from_utc = receipt.active_from_utc AND audit.active_from_utc = receipt.active_from_utc
        AND claim.inactive_from_utc = receipt.inactive_from_utc AND audit.inactive_from_utc = receipt.inactive_from_utc)
    THEN RAISE EXCEPTION '0096 finite parent / atomic receipt / exact replay drift'; END IF;
  request := format('SELECT * FROM app_private.assign_organization_project_member_v1(%L,%L,%L,%L,%L)',
    '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000003',org_id,
    '00000000-0096-4300-8000-000000000001','00000000-0096-4200-8000-000000000002');
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',request);
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    replace(request,'0096-4300-8000-000000000001','0096-4300-8000-000000000003'));
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    replace(request,'0096-4000-8000-000000000001','0096-4000-8000-000000000002'));
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    replace(request,org_id::text,gen_random_uuid()::text));
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    replace(request,'0096-4200-8000-000000000002','0096-4200-8000-000000000099'));
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    replace(request,'0096-4200-8000-000000000002','0096-4200-8000-000000000003'));
  PERFORM pg_temp.expect_0096_failure('22023','invalid organization project membership assignment request',
    'SELECT * FROM app_private.assign_organization_project_member_v1(NULL,NULL,NULL,NULL,NULL)');
  PERFORM pg_temp.expect_0096_failure('22023','organization project membership assignment idempotency conflict',
    replace(replace(request,'0096-5000-8000-000000000003','0096-5000-8000-000000000002'),
      '0096-4300-8000-000000000001','0096-4300-8000-000000000002'));
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    replace(replace(request,'0096-5000-8000-000000000003','0096-5000-8000-000000000002'),
      '0096-4000-8000-000000000001','0096-4000-8000-000000000002'));
  PERFORM pg_temp.expect_0096_failure('22023','invalid organization project membership assignment identity',
    'SELECT * FROM app_data.assign_organization_project_member_for_identity_v1('' '',NULL,NULL,NULL,NULL,NULL)');
  PERFORM pg_temp.expect_0096_failure('22023','invalid organization project membership assignment identity',
    'SELECT * FROM app_data.assign_organization_project_member_for_identity_v1(repeat(''x'',2049),''owner'',NULL,NULL,NULL,NULL)');
  PERFORM pg_temp.expect_0096_failure('22023','invalid organization project membership assignment identity',
    'SELECT * FROM app_data.assign_organization_project_member_for_identity_v1(''issuer'',repeat(''x'',513),NULL,NULL,NULL,NULL)');
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    'SELECT * FROM app_data.assign_organization_project_member_for_identity_v1(''https://synthetic-0096.example'',''owner exact'',NULL,NULL,NULL,NULL)');
  PERFORM pg_temp.expect_0096_failure('55000','membership authorization history is append-only',
    format('UPDATE app_data.project_memberships SET inactive_from_utc = clock_timestamp() WHERE project_membership_id = %L',receipt.project_membership_id));
END
$fixture$;
-- Independently test archived project, inactive target and recovery gates.
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0096_org); statement text;
BEGIN
  statement := format('SELECT * FROM app_private.assign_organization_project_member_v1(%L,%L,%L,%L,%L)',
    '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000005',org_id,
    '00000000-0096-4300-8000-000000000004','00000000-0096-4200-8000-000000000002');
  UPDATE app_data.projects SET status = 'archived' WHERE project_id = '00000000-0096-4300-8000-000000000004';
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',statement);
  UPDATE app_data.projects SET status = 'active' WHERE project_id = '00000000-0096-4300-8000-000000000004';
  UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = '00000000-0096-4000-8000-000000000002';
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',statement);
  UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = '00000000-0096-4000-8000-000000000002';
  UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = org_id;
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',statement);
  UPDATE app_data.workspaces SET deleted_at = NULL WHERE workspace_id = org_id;
END
$fixture$;
SELECT organization_workspace_id AS fixture_0096_org_id FROM fixture_0096_org \gset
SET LOCAL ROLE tongxingzhe_runtime;
SELECT * FROM app_data.assign_organization_project_member_for_identity_v1(
    'https://synthetic-0096.example',' owner exact ','00000000-0096-5000-8000-000000000002',
    :'fixture_0096_org_id','00000000-0096-4300-8000-000000000001',
    '00000000-0096-4200-8000-000000000002');
RESET ROLE;
-- Owner explicitly assigns self, with no grant; a creation tombstone does not
-- consume this family's request UUID.
INSERT INTO app_private.organization_creation_request_tombstones VALUES
  ('organization-creation:v1','00000000-0096-5000-8000-000000000004');
CREATE TEMP TABLE fixture_0096_self AS SELECT receipt.* FROM fixture_0096_org AS org,
  LATERAL app_private.assign_organization_project_member_v1(
    '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000004',
    org.organization_workspace_id,'00000000-0096-4300-8000-000000000002',org.organization_membership_id) AS receipt;
-- Recovery freezes first assignment but exact historical replay ignores
-- workspace/target/project state. Ownership loss is checked in committed
-- concurrency transactions (0084 owner end must equal transaction timestamp).
UPDATE app_data.workspaces SET deleted_at = clock_timestamp()
WHERE workspace_id = (SELECT organization_workspace_id FROM fixture_0096_org);
UPDATE app_data.projects SET status = 'archived' WHERE project_id = '00000000-0096-4300-8000-000000000001';
UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = '00000000-0096-4000-8000-000000000002';
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0096_org); historical record;
  statement text;
BEGIN
  SELECT * INTO STRICT historical FROM app_private.assign_organization_project_member_v1(
    '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000002',org_id,
    '00000000-0096-4300-8000-000000000001','00000000-0096-4200-8000-000000000002');
  IF to_jsonb(historical) IS DISTINCT FROM (SELECT to_jsonb(r) FROM fixture_0096_first AS r)
    OR (SELECT inactive_from_utc FROM fixture_0096_self) IS NOT NULL
    THEN RAISE EXCEPTION '0096 historical or nullable receipt drift'; END IF;
  statement := format('SELECT * FROM app_private.assign_organization_project_member_v1(%L,%L,%L,%L,%L)',
    '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000005',org_id,
    '00000000-0096-4300-8000-000000000004','00000000-0096-4200-8000-000000000002');
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',statement);
END
$fixture$;
-- Tombstone wins over both live exact replay and unresolved actor.
INSERT INTO app_private.organization_project_membership_assignment_request_tombstones VALUES
  ('organization-project-membership-assignment:v1','00000000-0096-5000-8000-000000000002'),
  ('organization-project-membership-assignment:v1','00000000-0096-5000-8000-000000000006');
DO $fixture$
DECLARE org_id uuid := (SELECT organization_workspace_id FROM fixture_0096_org); request_id uuid; table_name text;
BEGIN
  FOREACH request_id IN ARRAY ARRAY['00000000-0096-5000-8000-000000000002'::uuid,
    '00000000-0096-5000-8000-000000000006'::uuid] LOOP
    PERFORM pg_temp.expect_0096_failure('22023','organization project membership assignment idempotency conflict',
      format('SELECT * FROM app_private.assign_organization_project_member_v1(NULL,%L,%L,%L,%L)',
        request_id,org_id,'00000000-0096-4300-8000-000000000001','00000000-0096-4200-8000-000000000002'));
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY[
    'organization_project_membership_assignment_request_claims',
    'organization_project_membership_assignment_request_tombstones',
    'organization_project_membership_assignment_audit_events'] LOOP
    PERFORM pg_temp.expect_0096_failure('55000',NULL,format('DELETE FROM app_private.%I',table_name));
    PERFORM pg_temp.expect_0096_failure('55000',NULL,format('UPDATE app_private.%I SET request_id = request_id',table_name));
  END LOOP;
END
$fixture$;
UPDATE app_private.organization_project_membership_assignment_request_claims SET actor_app_user_id = NULL
WHERE request_id = '00000000-0096-5000-8000-000000000004';
DO $fixture$
DECLARE org fixture_0096_org%ROWTYPE;
BEGIN
  SELECT * INTO STRICT org FROM fixture_0096_org;
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    format('SELECT * FROM app_private.assign_organization_project_member_v1(%L,%L,%L,%L,%L)',
      '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000004',
      org.organization_workspace_id,'00000000-0096-4300-8000-000000000002',org.organization_membership_id));
  PERFORM pg_temp.expect_0096_failure('55000',NULL,
    'UPDATE app_private.organization_project_membership_assignment_request_claims SET actor_app_user_id = ''00000000-0096-4000-8000-000000000001'' WHERE actor_app_user_id IS NULL');
  UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = '00000000-0096-4000-8000-000000000001';
  PERFORM pg_temp.expect_0096_failure('42501','organization project membership assignment forbidden',
    format('SELECT * FROM app_private.assign_organization_project_member_v1(%L,%L,%L,%L,%L)',
      '00000000-0096-4000-8000-000000000001','00000000-0096-5000-8000-000000000004',
      org.organization_workspace_id,'00000000-0096-4300-8000-000000000002',org.organization_membership_id));
  IF (SELECT count(*) FROM app_private.organization_project_membership_assignment_request_claims
      WHERE request_id::text LIKE '00000000-0096-%') <> 2
    OR (SELECT count(*) FROM app_private.organization_project_membership_assignment_audit_events
      WHERE request_id::text LIKE '00000000-0096-%') <> 2
    OR EXISTS (SELECT 1 FROM fixture_0096_before WHERE parents <> (SELECT count(*) FROM app_data.organization_memberships)
      OR owners <> (SELECT count(*) FROM app_data.organization_owner_assignments)
      OR grants <> (SELECT count(*) FROM app_data.management_report_capability_grants))
    THEN RAISE EXCEPTION '0096 rejected/replayed calls added facts or management grants'; END IF;
END
$fixture$;
SET LOCAL ROLE tongxingzhe_runtime;
SELECT pg_temp.expect_0096_failure('42501',NULL,'SELECT * FROM app_private.organization_project_membership_assignment_request_claims');
SELECT pg_temp.expect_0096_failure('42501',NULL,'SELECT * FROM app_data.project_memberships');
SELECT pg_temp.expect_0096_failure('42501',NULL,'SELECT * FROM app_private.assign_organization_project_member_v1(NULL,NULL,NULL,NULL,NULL)');
SELECT pg_temp.expect_0096_failure('22023','invalid organization project membership assignment identity',
  'SELECT * FROM app_data.assign_organization_project_member_for_identity_v1(NULL,NULL,NULL,NULL,NULL,NULL)');
RESET ROLE;
ROLLBACK;

-- Both seam guards must fire before even identity/request validation, and
-- must acquire no advisory lock in unsupported transaction snapshots.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $fixture$
BEGIN
  BEGIN PERFORM * FROM app_private.assign_organization_project_member_v1(NULL,NULL,NULL,NULL,NULL);
    RAISE EXCEPTION '0096 RR private accepted';
  EXCEPTION WHEN SQLSTATE '0A000' THEN
    IF SQLERRM <> 'organization project membership assignment requires read committed' THEN RAISE; END IF;
  END;
  BEGIN PERFORM * FROM app_data.assign_organization_project_member_for_identity_v1(NULL,NULL,NULL,NULL,NULL,NULL);
    RAISE EXCEPTION '0096 RR bridge accepted';
  EXCEPTION WHEN SQLSTATE '0A000' THEN
    IF SQLERRM <> 'organization project membership assignment requires read committed' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM pg_locks WHERE pid = pg_backend_pid() AND locktype = 'advisory')
    THEN RAISE EXCEPTION '0096 RR guard acquired locks'; END IF;
END
$fixture$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $fixture$
BEGIN
  BEGIN PERFORM * FROM app_private.assign_organization_project_member_v1(NULL,NULL,NULL,NULL,NULL);
    RAISE EXCEPTION '0096 serializable private accepted';
  EXCEPTION WHEN SQLSTATE '0A000' THEN
    IF SQLERRM <> 'organization project membership assignment requires read committed' THEN RAISE; END IF;
  END;
  BEGIN PERFORM * FROM app_data.assign_organization_project_member_for_identity_v1(NULL,NULL,NULL,NULL,NULL,NULL);
    RAISE EXCEPTION '0096 serializable bridge accepted';
  EXCEPTION WHEN SQLSTATE '0A000' THEN
    IF SQLERRM <> 'organization project membership assignment requires read committed' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM pg_locks WHERE pid = pg_backend_pid() AND locktype = 'advisory')
    THEN RAISE EXCEPTION '0096 serializable guard acquired locks'; END IF;
END
$fixture$;
ROLLBACK;
