-- Random committed setup permits legal owner/parent closes in a later TX.
-- Directory/business facts roll back. Temp maps are dropped for same-session reruns.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE fixture_0099_identity AS SELECT
  ' https://synthetic-0099.example/' || gen_random_uuid()::text || ' ' AS issuer,
  repeat('i',2012) || gen_random_uuid()::text AS max_issuer;
CREATE TEMP TABLE fixture_0099_users AS
SELECT n, gen_random_uuid() AS user_id FROM generate_series(1, 12) AS n;
CREATE TEMP TABLE fixture_0099_orgs AS
SELECT n, gen_random_uuid() AS workspace_id FROM generate_series(1, 6) AS n;
CREATE TEMP TABLE fixture_0099_parents AS
SELECT row_number() OVER () AS n, workspace_n, user_n, gen_random_uuid() AS parent_id,
  gen_random_uuid() AS owner_id
FROM (VALUES (1,1), (1,2), (1,3), (1,4), (1,7), (1,8), (1,9), (1,11), (1,12),
  (2,1), (3,10), (4,1), (5,1)) AS pairs(workspace_n, user_n);
INSERT INTO app_data.app_users(app_user_id, status)
SELECT user_id, 'active' FROM fixture_0099_users;
INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
SELECT (SELECT issuer FROM fixture_0099_identity),
  CASE WHEN n = 1 THEN ' owner exact ' ELSE 'user-' || n END, user_id FROM fixture_0099_users;
INSERT INTO app_data.external_identities(issuer, subject, app_user_id)
SELECT (SELECT max_issuer FROM fixture_0099_identity), repeat('s', 512), user_id FROM fixture_0099_users WHERE n = 1;
INSERT INTO app_data.workspaces(workspace_id, workspace_kind, display_name, personal_owner_app_user_id)
SELECT workspace_id, CASE WHEN org.n = 6 THEN 'personal' ELSE 'organization' END,
  '0099 synthetic directory ' || org.n,
  CASE WHEN org.n = 6 THEN actor.user_id ELSE NULL END
FROM fixture_0099_orgs AS org CROSS JOIN fixture_0099_users AS actor WHERE actor.n = 1;
INSERT INTO app_data.organization_memberships
SELECT parent.parent_id, org.workspace_id, actor.user_id,
  CASE WHEN parent.user_n = 7 THEN transaction_timestamp() + interval '1 hour' ELSE transaction_timestamp() END, NULL
FROM fixture_0099_parents AS parent JOIN fixture_0099_orgs AS org ON org.n = parent.workspace_n
JOIN fixture_0099_users AS actor ON actor.n = parent.user_n;
INSERT INTO app_data.organization_owner_assignments
SELECT owner_id, parent_id, transaction_timestamp(), NULL FROM fixture_0099_parents WHERE user_n NOT IN (4, 7);
GRANT SELECT ON fixture_0099_identity, fixture_0099_users, fixture_0099_orgs, fixture_0099_parents TO tongxingzhe_runtime;
COMMIT;

BEGIN;
SET LOCAL TIME ZONE 'Pacific/Honolulu';
UPDATE app_data.organization_owner_assignments SET inactive_from_utc = transaction_timestamp()
WHERE organization_owner_assignment_id IN (SELECT owner_id FROM fixture_0099_parents WHERE user_n IN (3,8,9));
UPDATE app_data.organization_memberships SET inactive_from_utc = transaction_timestamp()
WHERE organization_membership_id IN (SELECT parent_id FROM fixture_0099_parents WHERE user_n = 9);
UPDATE app_data.app_users SET status = CASE WHEN seed.n = 12 THEN 'deleted' ELSE 'deletion_pending' END
FROM fixture_0099_users AS seed WHERE app_user_id = seed.user_id AND seed.n IN (5,11,12);
UPDATE app_data.workspaces SET deleted_at = transaction_timestamp() -
  CASE WHEN seed.n = 4 THEN interval '1 hour' ELSE interval '31 days' END
FROM fixture_0099_orgs AS seed WHERE app_data.workspaces.workspace_id = seed.workspace_id AND seed.n IN (4,5);
-- An expired link whose creator no longer owns the organization cannot hide a pending application.
INSERT INTO app_private.organization_shareable_join_link_request_claims
SELECT '00000000-0099-6000-0000-000000000004', org.workspace_id, actor.user_id,
  transaction_timestamp() - interval '169 hours', transaction_timestamp() - interval '1 hour'
FROM fixture_0099_orgs AS org CROSS JOIN fixture_0099_users AS actor WHERE org.n = 1 AND actor.n = 3;
INSERT INTO app_private.organization_shareable_join_application_request_claims
SELECT format('00000000-0099-5000-0000-%s', lpad(generated.n::text,12,'0'))::uuid,
  format('00000000-0099-6000-0000-%s', lpad(generated.n::text,12,'0'))::uuid,
  org.workspace_id,
  CASE WHEN generated.n = 1 THEN NULL ELSE (SELECT user_id FROM fixture_0099_users
    WHERE fixture_0099_users.n = CASE WHEN generated.n = 2 THEN 5 WHEN generated.n = 3 THEN 4 ELSE 6 END) END,
  transaction_timestamp() - interval '1 hour', transaction_timestamp() + interval '167 hours', NULL, NULL
FROM generate_series(1,21) AS generated(n) CROSS JOIN fixture_0099_orgs AS org WHERE org.n = 1;
INSERT INTO app_private.organization_shareable_join_application_request_claims
SELECT format('00000000-0099-5000-0000-%s', lpad(generated.n::text,12,'0'))::uuid,
  gen_random_uuid(), org.workspace_id, NULL,
  transaction_timestamp() - age, transaction_timestamp() - age + interval '168 hours',
  CASE WHEN generated.n = 92 THEN transaction_timestamp() ELSE NULL END,
  CASE WHEN generated.n = 92 THEN (SELECT parent_id FROM fixture_0099_parents WHERE user_n = 4) ELSE NULL END
FROM (VALUES (90,interval '2 hours'), (91,interval '169 hours'), (92,interval '3 hours')) AS generated(n,age)
CROSS JOIN fixture_0099_orgs AS org WHERE org.n = 1;
-- A foreign organization's pending claim must not appear in this directory.
INSERT INTO app_private.organization_shareable_join_application_request_claims
SELECT gen_random_uuid(), gen_random_uuid(), workspace_id, NULL, transaction_timestamp(), transaction_timestamp() + interval '168 hours', NULL, NULL
FROM fixture_0099_orgs WHERE n = 3;
SET CONSTRAINTS ALL IMMEDIATE;

-- Live, fixture-scoped full snapshots catch reads that accidentally mutate facts.
CREATE TEMP VIEW fixture_0099_facts AS SELECT jsonb_build_object(
  'users', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.app_user_id) FROM app_data.app_users x WHERE x.app_user_id IN (SELECT user_id FROM fixture_0099_users)),
  'identities', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.external_identity_id) FROM app_data.external_identities x WHERE x.app_user_id IN (SELECT user_id FROM fixture_0099_users)),
  'workspaces', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.workspace_id) FROM app_data.workspaces x WHERE x.workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)),
  'parents', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.organization_membership_id) FROM app_data.organization_memberships x WHERE x.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs) OR x.app_user_id IN (SELECT user_id FROM fixture_0099_users)),
  'owners', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.organization_owner_assignment_id) FROM app_data.organization_owner_assignments x JOIN app_data.organization_memberships m USING(organization_membership_id) WHERE m.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs) OR m.app_user_id IN (SELECT user_id FROM fixture_0099_users)),
  'projects', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.project_id) FROM app_data.projects x WHERE x.workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)),
  'project_members', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.project_membership_id) FROM app_data.project_memberships x JOIN app_data.organization_memberships m USING(organization_membership_id) WHERE m.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs) OR m.app_user_id IN (SELECT user_id FROM fixture_0099_users)),
  'grants', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.capability_grant_id) FROM app_data.management_report_capability_grants x JOIN app_data.project_memberships p USING(project_membership_id) JOIN app_data.organization_memberships m USING(organization_membership_id) WHERE m.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs) OR m.app_user_id IN (SELECT user_id FROM fixture_0099_users)),
  'link_claims', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.link_id) FROM app_private.organization_shareable_join_link_request_claims x WHERE x.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)),
  'link_audits', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.organization_shareable_join_link_audit_event_id) FROM app_private.organization_shareable_join_link_audit_events x WHERE x.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)),
  'applications', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.application_id) FROM app_private.organization_shareable_join_application_request_claims x WHERE x.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)),
  'application_audits', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.organization_shareable_join_application_audit_event_id) FROM app_private.organization_shareable_join_application_audit_events x WHERE x.organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)),
  'application_tombstones', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.application_id) FROM app_private.organization_shareable_join_application_request_tombstones x WHERE x.application_id IN (SELECT application_id FROM app_private.organization_shareable_join_application_request_claims WHERE organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs))),
  'link_tombstones', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.link_id) FROM app_private.organization_shareable_join_link_request_tombstones x WHERE x.link_id IN (SELECT link_id FROM app_private.organization_shareable_join_application_request_claims WHERE organization_workspace_id IN (SELECT workspace_id FROM fixture_0099_orgs)))
) AS facts;
CREATE TEMP TABLE fixture_0099_before AS SELECT * FROM fixture_0099_facts;
SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE receipt record; coowner record; empty_receipt record; item jsonb;
  actual_ids text[]; expected_ids text[];
BEGIN
  SELECT * INTO STRICT receipt FROM app_data.list_org_join_applications_for_identity_v1(
    (SELECT issuer FROM fixture_0099_identity), ' owner exact ', (SELECT workspace_id FROM fixture_0099_orgs WHERE n = 1));
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(to_jsonb(receipt)) AS key)
      IS DISTINCT FROM ARRAY['applications','observed_at_utc','organization_shareable_join_application_directory_contract_id','organization_workspace_id']::text[]
    OR receipt.organization_shareable_join_application_directory_contract_id IS DISTINCT FROM 'organization-shareable-join-application-directory:v1'
    OR receipt.organization_workspace_id IS DISTINCT FROM (SELECT workspace_id FROM fixture_0099_orgs WHERE n = 1)
    OR receipt.observed_at_utc IS NULL OR receipt.observed_at_utc < transaction_timestamp() OR receipt.observed_at_utc > clock_timestamp()
    OR jsonb_array_length(receipt.applications) <> 20
  THEN RAISE EXCEPTION '0099 exact root/current owner/limit receipt drift'; END IF;
  SELECT array_agg(value->>'application_id' ORDER BY ordinality) INTO actual_ids
  FROM jsonb_array_elements(receipt.applications) WITH ORDINALITY;
  SELECT ARRAY['00000000-0099-5000-0000-000000000090'] || array_agg(format('00000000-0099-5000-0000-%s', lpad(n::text,12,'0')) ORDER BY n)
  INTO expected_ids FROM generate_series(1,19) AS n;
  IF actual_ids IS DISTINCT FROM expected_ids
  THEN RAISE EXCEPTION '0099 submitted order/tie break/pending lifecycle drift: %', actual_ids; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(receipt.applications) LOOP
    IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(item) AS key)
        IS DISTINCT FROM ARRAY['application_id','expires_at_utc','link_id','submitted_at_utc']::text[]
      OR jsonb_typeof(item->'application_id') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'link_id') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'submitted_at_utc') IS DISTINCT FROM 'string'
      OR jsonb_typeof(item->'expires_at_utc') IS DISTINCT FROM 'string'
      OR item->>'application_id' !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
      OR item->>'link_id' !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
      OR item->>'submitted_at_utc' !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$'
      OR item->>'expires_at_utc' !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$'
      OR (item->>'expires_at_utc')::timestamptz <= receipt.observed_at_utc
      OR (item->>'expires_at_utc')::timestamptz IS DISTINCT FROM (item->>'submitted_at_utc')::timestamptz + interval '168 hours'
    THEN RAISE EXCEPTION '0099 item exact UUID/UTC/raw expiry boundary drift'; END IF;
  END LOOP;
  SELECT * INTO STRICT coowner FROM app_data.list_org_join_applications_for_identity_v1(
    (SELECT issuer FROM fixture_0099_identity), 'user-2', receipt.organization_workspace_id);
  IF coowner.applications IS DISTINCT FROM receipt.applications
  THEN RAISE EXCEPTION '0099 co-owner directory mismatch'; END IF;
  SELECT * INTO STRICT empty_receipt FROM app_data.list_org_join_applications_for_identity_v1(
    (SELECT max_issuer FROM fixture_0099_identity), repeat('s',512), (SELECT workspace_id FROM fixture_0099_orgs WHERE n = 2));
  IF empty_receipt.applications IS DISTINCT FROM '[]'::jsonb
  THEN RAISE EXCEPTION '0099 authorized empty/max-length identity directory drift'; END IF;
END
$fixture$;
RESET ROLE;
CREATE TEMP TABLE fixture_0099_failures(issuer text, subject text, workspace_id uuid, expected_state text, expected_message text);
INSERT INTO fixture_0099_failures
SELECT (SELECT issuer FROM fixture_0099_identity), 'user-' || n, (SELECT workspace_id FROM fixture_0099_orgs WHERE n = 1),
  '42501', 'organization shareable join application directory forbidden'
FROM unnest(ARRAY[3,4,5,6,7,8,9,10,11,12]) AS n;
INSERT INTO fixture_0099_failures
SELECT (SELECT issuer FROM fixture_0099_identity), ' owner exact ', workspace_id, '42501',
  'organization shareable join application directory forbidden' FROM fixture_0099_orgs WHERE n IN (3,4,5,6);
INSERT INTO fixture_0099_failures VALUES
  ((SELECT issuer FROM fixture_0099_identity), ' owner exact ', gen_random_uuid(), '42501', 'organization shareable join application directory forbidden');
INSERT INTO fixture_0099_failures
SELECT issuer, subject, (SELECT workspace_id FROM fixture_0099_orgs WHERE n = 1), expected_state,
  CASE WHEN expected_state = '22023' THEN 'invalid organization shareable join application directory identity'
    ELSE 'organization shareable join application directory forbidden' END
FROM (VALUES (NULL::text,' owner exact ','22023'), (' ', ' owner exact ','22023'), (repeat('i',2049),' owner exact ','22023'),
  ((SELECT issuer FROM fixture_0099_identity), NULL,'22023'), ((SELECT issuer FROM fixture_0099_identity),' ','22023'),
  ((SELECT issuer FROM fixture_0099_identity),repeat('s',513),'22023'), (btrim((SELECT issuer FROM fixture_0099_identity)),' owner exact ','42501'),
  ((SELECT issuer FROM fixture_0099_identity),'owner exact','42501'), ((SELECT issuer FROM fixture_0099_identity),' OWNER EXACT ','42501'),
  (E'\t',' owner exact ','42501'), ('unknown','unknown','42501')) AS cases(issuer,subject,expected_state);
INSERT INTO fixture_0099_failures VALUES
  ((SELECT issuer FROM fixture_0099_identity), ' owner exact ', NULL, '22023', 'invalid organization shareable join application directory request');
GRANT SELECT ON fixture_0099_failures TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
DO $fixture$
DECLARE failure record; actual_state text; actual_message text;
BEGIN
  FOR failure IN SELECT * FROM fixture_0099_failures LOOP
    actual_state := NULL; actual_message := NULL;
    BEGIN
      PERFORM * FROM app_data.list_org_join_applications_for_identity_v1(failure.issuer, failure.subject, failure.workspace_id);
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
    END;
    IF actual_state IS DISTINCT FROM failure.expected_state OR actual_message IS DISTINCT FROM failure.expected_message
    THEN RAISE EXCEPTION '0099 expected exact % / %, got % / %', failure.expected_state, failure.expected_message, actual_state, actual_message; END IF;
  END LOOP;
  BEGIN
    PERFORM * FROM app_private.organization_shareable_join_application_request_claims;
    RAISE EXCEPTION '0099 runtime read private claims';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$fixture$;
RESET ROLE;
DO $fixture$
BEGIN
  IF (SELECT facts FROM fixture_0099_facts) IS DISTINCT FROM (SELECT facts FROM fixture_0099_before)
  THEN RAISE EXCEPTION '0099 directory changed fixture-scoped business facts'; END IF;
END
$fixture$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
DROP TABLE fixture_0099_parents, fixture_0099_orgs, fixture_0099_users, fixture_0099_identity;
