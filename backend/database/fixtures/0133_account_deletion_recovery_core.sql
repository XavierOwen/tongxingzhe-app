-- Synthetic account lifecycle proof. All rows and fault triggers roll back.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'America/New_York';

CREATE FUNCTION pg_temp.assert_0133(condition boolean, label text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN
    RAISE EXCEPTION '0133 %', label;
  END IF;
END
$function$;

CREATE FUNCTION pg_temp.lifecycle_state_0133()
RETURNS jsonb LANGUAGE sql AS $function$
  SELECT jsonb_build_object(
    'users', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY app_user_id), '[]') FROM app_data.app_users t),
    'current', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY app_user_id), '[]') FROM app_private.account_deletion_current t),
    'request', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY request_id), '[]') FROM app_private.account_deletion_request_claims t),
    'restore', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY request_id), '[]') FROM app_private.account_deletion_restore_claims t),
    'audit', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY audit_event_id), '[]') FROM app_private.account_deletion_audit_events t));
$function$;

CREATE FUNCTION pg_temp.expect_0133_failure(expected_state text, expected_message text, statement text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.lifecycle_state_0133(); actual_state text; actual_message text;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE, actual_message = MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state
    OR (expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0133 expected % / %, got % / %', expected_state, expected_message, actual_state, actual_message;
  END IF;
  PERFORM pg_temp.assert_0133(before_state = pg_temp.lifecycle_state_0133(), 'failure left partial lifecycle facts');
END
$function$;

CREATE FUNCTION pg_temp.legacy_state_0133()
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; result jsonb := '{}'::jsonb; expression text;
BEGIN
  FOR relation IN SELECT schemaname, tablename FROM pg_catalog.pg_tables
    WHERE schemaname IN ('app_data', 'app_private')
      AND NOT (schemaname = 'app_private' AND tablename IN (
        'account_deletion_current', 'account_deletion_request_claims',
        'account_deletion_restore_claims', 'account_deletion_audit_events'))
    ORDER BY schemaname, tablename
  LOOP
    expression := CASE WHEN relation.schemaname = 'app_data' AND relation.tablename = 'app_users'
      THEN 'to_jsonb(t) - ''status''' ELSE 'to_jsonb(t)' END;
    EXECUTE format('SELECT coalesce(jsonb_agg(%s ORDER BY %s::text), ''[]''::jsonb) FROM %I.%I t',
      expression, expression, relation.schemaname, relation.tablename) INTO rows;
    result := result || jsonb_build_object(relation.schemaname || '.' || relation.tablename, rows);
  END LOOP;
  RETURN result;
END
$function$;

INSERT INTO app_data.app_users(app_user_id, status)
SELECT format('00000000-0133-0000-8000-%s', lpad(number::text, 12, '0'))::uuid,
  CASE number WHEN 3 THEN 'deleted' WHEN 4 THEN 'deletion_pending' ELSE 'active' END
FROM generate_series(1, 14) number;
INSERT INTO app_data.external_identities(issuer, subject, app_user_id) VALUES
  ('https://0133.example.test/auth/v1', '0133-owner', '00000000-0133-0000-8000-000000000001');
CREATE TEMP TABLE fixture_0133_context AS
SELECT * FROM app_data.bootstrap_personal_context('https://0133.example.test/auth/v1', '0133-owner');
SELECT app_data.create_promotion_target(app_user_id, workspace_id, project_id, 'person',
  '0133 retained person', '+1 312 555 0133', NULL, '0133-retained-target') FROM fixture_0133_context;
SELECT pg_temp.assert_0133(result_code = 'accepted', 'personal contact seed failed')
FROM fixture_0133_context c, LATERAL app_data.apply_contact_submit_v3(
  c.app_user_id, '0133-retained-submit', 1, 'contact.submit.v1', '0133-device', '0133-retained-contact', 0,
  jsonb_build_object('contactId', '0133-retained-contact', 'workspaceId', c.workspace_id,
    'projectId', c.project_id, 'questionnaireVersionId', c.questionnaire_version_id,
    'reason', '0133 retained contact', 'occurredAtUtc', clock_timestamp(), 'occurredTimeZone', 'UTC',
    'channel', 'video_call', 'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1, 'interestLevel', 2, 'answers', '[]'::jsonb, 'targetLinks', '[]'::jsonb)) result;

CREATE TEMP TABLE fixture_0133_organizations AS
SELECT 'shared' AS kind, receipt.* FROM app_private.create_organization_v1(
  '00000000-0133-0000-8000-000000000001', '00000000-0133-1000-8000-000000000001', '0133 shared organization') receipt
UNION ALL SELECT 'sole', receipt.* FROM app_private.create_organization_v1(
  '00000000-0133-0000-8000-000000000005', '00000000-0133-1000-8000-000000000002', '0133 sole owner') receipt
UNION ALL SELECT 'deleted', receipt.* FROM app_private.create_organization_v1(
  '00000000-0133-0000-8000-000000000006', '00000000-0133-1000-8000-000000000003', '0133 organization recovery') receipt
UNION ALL SELECT 'historical', receipt.* FROM app_private.create_organization_v1(
  '00000000-0133-0000-8000-000000000002', '00000000-0133-1000-8000-000000000004', '0133 historical membership') receipt;
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id, active_from_utc, inactive_from_utc)
SELECT '00000000-0133-2000-8000-000000000002', organization_workspace_id,
  '00000000-0133-0000-8000-000000000002', transaction_timestamp(), NULL
FROM fixture_0133_organizations WHERE kind = 'shared';
INSERT INTO app_data.organization_owner_assignments(
  organization_owner_assignment_id, organization_membership_id, active_from_utc, inactive_from_utc)
VALUES ('00000000-0133-3000-8000-000000000002', '00000000-0133-2000-8000-000000000002', transaction_timestamp(), NULL);
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id, active_from_utc, inactive_from_utc)
SELECT '00000000-0133-2000-8000-000000000008', organization_workspace_id,
  '00000000-0133-0000-8000-000000000008', transaction_timestamp(), NULL
FROM fixture_0133_organizations WHERE kind = 'sole';
-- Historical membership remains part of the governance fence.
INSERT INTO app_data.organization_memberships(
  organization_membership_id, organization_workspace_id, app_user_id, active_from_utc, inactive_from_utc)
SELECT '00000000-0133-2000-8000-000000000001', organization_workspace_id,
  '00000000-0133-0000-8000-000000000001', transaction_timestamp() - interval '2 hours', transaction_timestamp() - interval '1 hour'
FROM fixture_0133_organizations WHERE kind = 'historical';
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '00000000-0133-6000-8000-000000000001', organization_workspace_id, '0133 retained organization project'
FROM fixture_0133_organizations WHERE kind = 'shared';
SELECT receipt.* FROM fixture_0133_organizations org,
LATERAL app_private.request_organization_deletion_v1(
  '00000000-0133-0000-8000-000000000006', '00000000-0133-7000-8000-000000000001', org.organization_workspace_id) receipt
WHERE org.kind = 'deleted';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
CREATE TEMP TABLE fixture_0133_legacy AS SELECT pg_temp.legacy_state_0133() AS state;

SELECT pg_temp.expect_0133_failure('42501', 'account deletion forbidden',
  'SELECT * FROM app_private.request_account_deletion_v1(NULL, gen_random_uuid())');
SELECT pg_temp.expect_0133_failure('22023', 'invalid account deletion request',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000001'', NULL)');
SELECT pg_temp.expect_0133_failure('22023', 'invalid account restoration request',
  'SELECT * FROM app_private.restore_account_v1(NULL, NULL, NULL)');
SELECT pg_temp.expect_0133_failure('22023', 'invalid account restoration request',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000001'', NULL, gen_random_uuid())');
SELECT pg_temp.expect_0133_failure('22023', 'invalid account restoration request',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000001'', gen_random_uuid(), NULL)');
SELECT pg_temp.expect_0133_failure('42501', 'account restoration forbidden',
  'SELECT * FROM app_private.restore_account_v1(NULL, gen_random_uuid(), gen_random_uuid())');
DO $fixture$
DECLARE actor uuid;
BEGIN
  FOREACH actor IN ARRAY ARRAY['00000000-0133-0000-8000-000000000003'::uuid,
      '00000000-0133-0000-8000-000000009999'::uuid] LOOP
    PERFORM pg_temp.expect_0133_failure('42501', 'account deletion forbidden',
      format('SELECT * FROM app_private.request_account_deletion_v1(%L, gen_random_uuid())', actor));
    PERFORM pg_temp.expect_0133_failure('42501', 'account restoration forbidden',
      format('SELECT * FROM app_private.restore_account_v1(%L, gen_random_uuid(), gen_random_uuid())', actor));
  END LOOP;
  FOREACH actor IN ARRAY ARRAY['00000000-0133-0000-8000-000000000005'::uuid,
      '00000000-0133-0000-8000-000000000006'::uuid] LOOP
    PERFORM pg_temp.expect_0133_failure('42501', 'account deletion forbidden',
      format('SELECT * FROM app_private.request_account_deletion_v1(%L, gen_random_uuid())', actor));
  END LOOP;
END
$fixture$;
SELECT pg_temp.expect_0133_failure('55000', 'account deletion unavailable',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000004'', gen_random_uuid())');
SELECT pg_temp.expect_0133_failure('55000', 'account restoration unavailable',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000004'', gen_random_uuid(), gen_random_uuid())');
SELECT pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000001'', gen_random_uuid(), gen_random_uuid())');

CREATE TEMP TABLE fixture_0133_requested AS SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000001', '00000000-0133-4000-8000-000000000001');
CREATE TEMP TABLE fixture_0133_request_replay AS SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000001', '00000000-0133-4000-8000-000000000001');
SELECT pg_temp.assert_0133((SELECT count(*) = 1 AND bool_and(
  account_deletion_contract_id = 'account-deletion-request:v1'
  AND deletion_request_id = '00000000-0133-4000-8000-000000000001'
  AND isfinite(effective_at_utc) AND effective_at_utc <= clock_timestamp()
  AND extract(epoch FROM purge_after_utc - effective_at_utc) = 2592000) FROM fixture_0133_requested)
  AND NOT EXISTS ((TABLE fixture_0133_requested EXCEPT TABLE fixture_0133_request_replay)
    UNION ALL (TABLE fixture_0133_request_replay EXCEPT TABLE fixture_0133_requested)),
  'request receipt, exact replay, or continuous 720 hours drifted');
SELECT pg_temp.assert_0133((SELECT status = 'deletion_pending' FROM app_data.app_users
  WHERE app_user_id = '00000000-0133-0000-8000-000000000001')
  AND (SELECT count(*) = 1 FROM app_private.account_deletion_request_claims
    WHERE request_id = '00000000-0133-4000-8000-000000000001')
  AND (SELECT count(*) = 1 FROM app_private.account_deletion_audit_events
    WHERE request_id = '00000000-0133-4000-8000-000000000001'), 'request did not write one lifecycle fact set');
SELECT pg_temp.assert_0133((SELECT state = pg_temp.legacy_state_0133() FROM fixture_0133_legacy),
  'request changed retained personal or organization facts');
SELECT pg_temp.expect_0133_failure('22023', 'account deletion idempotency conflict',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000001'', gen_random_uuid())');
SELECT pg_temp.expect_0133_failure('22023', 'account deletion idempotency conflict',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000002'', ''00000000-0133-4000-8000-000000000001'')');
SELECT pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000001'', gen_random_uuid(), gen_random_uuid())');

CREATE TEMP TABLE fixture_0133_restored AS SELECT * FROM app_private.restore_account_v1(
  '00000000-0133-0000-8000-000000000001', '00000000-0133-5000-8000-000000000001', '00000000-0133-4000-8000-000000000001');
CREATE TEMP TABLE fixture_0133_restore_replay AS SELECT * FROM app_private.restore_account_v1(
  '00000000-0133-0000-8000-000000000001', '00000000-0133-5000-8000-000000000001', '00000000-0133-4000-8000-000000000001');
SELECT pg_temp.assert_0133((SELECT count(*) = 1 AND bool_and(
    account_deletion_restore_contract_id = 'account-deletion-restore:v1'
    AND deletion_request_id = '00000000-0133-4000-8000-000000000001'
    AND restored_at_utc >= (SELECT effective_at_utc FROM fixture_0133_requested)
    AND restored_at_utc < (SELECT purge_after_utc FROM fixture_0133_requested)) FROM fixture_0133_restored)
  AND NOT EXISTS ((TABLE fixture_0133_restored EXCEPT TABLE fixture_0133_restore_replay)
    UNION ALL (TABLE fixture_0133_restore_replay EXCEPT TABLE fixture_0133_restored))
  AND (SELECT status = 'active' FROM app_data.app_users WHERE app_user_id = '00000000-0133-0000-8000-000000000001')
  AND (SELECT count(*) = 1 FROM app_private.account_deletion_restore_claims WHERE request_id = '00000000-0133-5000-8000-000000000001')
  AND (SELECT count(*) = 2 FROM app_private.account_deletion_audit_events WHERE deletion_request_id = '00000000-0133-4000-8000-000000000001'),
  'restore receipt, exact replay, or lifecycle facts drifted');
SELECT pg_temp.assert_0133((SELECT state = pg_temp.legacy_state_0133() FROM fixture_0133_legacy),
  'restore changed retained personal or organization facts');
SELECT pg_temp.expect_0133_failure('22023', 'account deletion idempotency conflict',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000001'', ''00000000-0133-4000-8000-000000000001'')');
SELECT pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000002'', ''00000000-0133-5000-8000-000000000001'', ''00000000-0133-4000-8000-000000000001'')');
CREATE TEMP TABLE fixture_0133_next AS SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000001', '00000000-0133-4000-8000-000000000002');
SELECT pg_temp.assert_0133((SELECT n.effective_at_utc > r.restored_at_utc
  AND n.deletion_request_id <> r.deletion_request_id FROM fixture_0133_next n CROSS JOIN fixture_0133_restored r),
  'new cycle did not follow the restored cycle');
SELECT pg_temp.expect_0133_failure('22023', 'account deletion idempotency conflict',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000001'', ''00000000-0133-4000-8000-000000000001'')');
SELECT pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000001'', ''00000000-0133-5000-8000-000000000001'', ''00000000-0133-4000-8000-000000000001'')');
SELECT pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000001'', ''00000000-0133-5000-8000-000000000001'', ''00000000-0133-4000-8000-000000000002'')');
SELECT * FROM app_private.restore_account_v1('00000000-0133-0000-8000-000000000001',
  '00000000-0133-5000-8000-000000000002', '00000000-0133-4000-8000-000000000002');
-- A member who is not an owner may leave the active owner in place.
SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000008', '00000000-0133-4000-8000-000000000008');
SELECT * FROM app_private.restore_account_v1('00000000-0133-0000-8000-000000000008',
  '00000000-0133-5000-8000-000000000008', '00000000-0133-4000-8000-000000000008');

CREATE FUNCTION pg_temp.fail_0133_write()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF current_setting('fixture.fail_0133_table', true) = TG_TABLE_NAME THEN
    RAISE EXCEPTION USING ERRCODE = 'P0133', MESSAGE = '0133 injected write failure';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0133_request_failure BEFORE INSERT ON app_private.account_deletion_request_claims
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0133_write();
CREATE TRIGGER fixture_0133_restore_failure BEFORE INSERT ON app_private.account_deletion_restore_claims
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0133_write();
CREATE TRIGGER fixture_0133_audit_failure BEFORE INSERT ON app_private.account_deletion_audit_events
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0133_write();
DO $fixture$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['account_deletion_request_claims', 'account_deletion_audit_events'] LOOP
    PERFORM set_config('fixture.fail_0133_table', table_name, true);
    PERFORM pg_temp.expect_0133_failure('P0133', '0133 injected write failure',
      'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000009'', ''00000000-0133-4000-8000-000000000009'')');
  END LOOP;
  PERFORM set_config('fixture.fail_0133_table', '', true);
END
$fixture$;
SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000009', '00000000-0133-4000-8000-000000000009');
DO $fixture$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['account_deletion_restore_claims', 'account_deletion_audit_events'] LOOP
    PERFORM set_config('fixture.fail_0133_table', table_name, true);
    PERFORM pg_temp.expect_0133_failure('P0133', '0133 injected write failure',
      'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000009'', ''00000000-0133-5000-8000-000000000009'', ''00000000-0133-4000-8000-000000000009'')');
  END LOOP;
  PERFORM set_config('fixture.fail_0133_table', '', true);
END
$fixture$;
SELECT * FROM app_private.restore_account_v1('00000000-0133-0000-8000-000000000009',
  '00000000-0133-5000-8000-000000000009', '00000000-0133-4000-8000-000000000009');

-- The two operation families may use the same request UUID.
SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000010', '00000000-0133-4000-8000-000000000010');
SELECT * FROM app_private.restore_account_v1('00000000-0133-0000-8000-000000000010',
  '00000000-0133-4000-8000-000000000010', '00000000-0133-4000-8000-000000000010');
SELECT pg_temp.assert_0133((SELECT count(*) = 2 FROM app_private.account_deletion_audit_events
  WHERE request_id = '00000000-0133-4000-8000-000000000010'), 'request families share an idempotency namespace');

-- Move synthetic clocks together; production claim immutability stays enabled for calls.
SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000011', '00000000-0133-4000-8000-000000000011');
SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000012', '00000000-0133-4000-8000-000000000012');
SET LOCAL session_replication_role = replica;
UPDATE app_private.account_deletion_current SET effective_at_utc = boundary.at - interval '720 hours',
  purge_after_utc = boundary.at
FROM (SELECT clock_timestamp() - interval '1 second' AS at) boundary
WHERE app_user_id = '00000000-0133-0000-8000-000000000011';
UPDATE app_private.account_deletion_current SET effective_at_utc = boundary.at,
  purge_after_utc = boundary.at + interval '720 hours'
FROM (SELECT clock_timestamp() + interval '1 hour' AS at) boundary
WHERE app_user_id = '00000000-0133-0000-8000-000000000012';
UPDATE app_private.account_deletion_request_claims claim SET effective_at_utc = attempt.effective_at_utc,
  purge_after_utc = attempt.purge_after_utc FROM app_private.account_deletion_current attempt
WHERE claim.request_id = attempt.deletion_request_id AND attempt.app_user_id IN (
  '00000000-0133-0000-8000-000000000011', '00000000-0133-0000-8000-000000000012');
SET LOCAL session_replication_role = origin;
DO $fixture$
DECLARE suffix text; actor uuid; cycle uuid;
BEGIN
  FOREACH suffix IN ARRAY ARRAY['000000000011', '000000000012'] LOOP
    actor := ('00000000-0133-0000-8000-' || suffix)::uuid;
    cycle := ('00000000-0133-4000-8000-' || suffix)::uuid;
    PERFORM pg_temp.expect_0133_failure('22023', 'account deletion idempotency conflict',
      format('SELECT * FROM app_private.request_account_deletion_v1(%L, %L)', actor, cycle));
    PERFORM pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
      format('SELECT * FROM app_private.restore_account_v1(%L, gen_random_uuid(), %L)', actor, cycle));
  END LOOP;
END
$fixture$;

-- A restored cycle may replay its original receipt after the recovery deadline.
INSERT INTO app_private.account_deletion_request_claims(
  request_id, actor_app_user_id, deletion_request_id, effective_at_utc, purge_after_utc)
VALUES ('00000000-0133-4000-8000-000000000013', '00000000-0133-0000-8000-000000000013',
  '00000000-0133-4000-8000-000000000013', '2024-02-20 12:00:00-05', '2024-03-21 13:00:00-04');
INSERT INTO app_private.account_deletion_current(
  app_user_id, deletion_request_id, effective_at_utc, purge_after_utc, status, restored_at_utc)
VALUES ('00000000-0133-0000-8000-000000000013', '00000000-0133-4000-8000-000000000013',
  '2024-02-20 12:00:00-05', '2024-03-21 13:00:00-04', 'restored', '2024-03-01 12:00:00-05');
INSERT INTO app_private.account_deletion_restore_claims(request_id, actor_app_user_id, deletion_request_id, restored_at_utc)
VALUES ('00000000-0133-5000-8000-000000000013', '00000000-0133-0000-8000-000000000013',
  '00000000-0133-4000-8000-000000000013', '2024-03-01 12:00:00-05');
CREATE TEMP TABLE fixture_0133_after_deadline AS SELECT pg_temp.lifecycle_state_0133() AS state;
SELECT pg_temp.assert_0133(account_deletion_restore_contract_id = 'account-deletion-restore:v1'
  AND deletion_request_id = '00000000-0133-4000-8000-000000000013'
  AND restored_at_utc = '2024-03-01 12:00:00-05'::timestamptz,
  'expired restored cycle did not return the original receipt')
FROM app_private.restore_account_v1('00000000-0133-0000-8000-000000000013',
  '00000000-0133-5000-8000-000000000013', '00000000-0133-4000-8000-000000000013');
SELECT pg_temp.assert_0133((SELECT state = pg_temp.lifecycle_state_0133() FROM fixture_0133_after_deadline),
  'expired restored cycle replay changed lifecycle facts');

-- A status without its matching cycle cannot be repaired by a new request.
SELECT * FROM app_private.request_account_deletion_v1(
  '00000000-0133-0000-8000-000000000014', '00000000-0133-4000-8000-000000000014');
UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = '00000000-0133-0000-8000-000000000014';
SELECT pg_temp.expect_0133_failure('55000', 'account deletion unavailable',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000014'', gen_random_uuid())');
SELECT pg_temp.expect_0133_failure('55000', 'account restoration unavailable',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000014'', gen_random_uuid(), ''00000000-0133-4000-8000-000000000014'')');

SELECT pg_temp.expect_0133_failure('55000', NULL,
  'UPDATE app_private.account_deletion_request_claims SET purge_after_utc = purge_after_utc + interval ''1 hour'' WHERE request_id = ''00000000-0133-4000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('55000', NULL,
  'UPDATE app_private.account_deletion_request_claims SET actor_app_user_id = ''00000000-0133-0000-8000-000000000002'' WHERE request_id = ''00000000-0133-4000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('55000', NULL,
  'DELETE FROM app_private.account_deletion_request_claims WHERE request_id = ''00000000-0133-4000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('55000', NULL,
  'UPDATE app_private.account_deletion_restore_claims SET restored_at_utc = restored_at_utc + interval ''1 hour'' WHERE request_id = ''00000000-0133-5000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('55000', NULL,
  'DELETE FROM app_private.account_deletion_restore_claims WHERE request_id = ''00000000-0133-5000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('55000', 'promotion target audit is append-only',
  'UPDATE app_private.account_deletion_audit_events SET occurred_at_utc = occurred_at_utc WHERE request_id = ''00000000-0133-4000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('55000', 'promotion target audit is append-only',
  'DELETE FROM app_private.account_deletion_audit_events WHERE request_id = ''00000000-0133-4000-8000-000000000009''');
UPDATE app_private.account_deletion_request_claims SET actor_app_user_id = NULL
WHERE request_id = '00000000-0133-4000-8000-000000000009';
UPDATE app_private.account_deletion_restore_claims SET actor_app_user_id = NULL
WHERE request_id = '00000000-0133-5000-8000-000000000009';
SELECT pg_temp.expect_0133_failure('55000', NULL,
  'UPDATE app_private.account_deletion_restore_claims SET actor_app_user_id = ''00000000-0133-0000-8000-000000000009'' WHERE request_id = ''00000000-0133-5000-8000-000000000009''');
SELECT pg_temp.expect_0133_failure('22023', 'account deletion idempotency conflict',
  'SELECT * FROM app_private.request_account_deletion_v1(''00000000-0133-0000-8000-000000000009'', ''00000000-0133-4000-8000-000000000009'')');
SELECT pg_temp.expect_0133_failure('22023', 'account restoration idempotency conflict',
  'SELECT * FROM app_private.restore_account_v1(''00000000-0133-0000-8000-000000000009'', ''00000000-0133-5000-8000-000000000009'', ''00000000-0133-4000-8000-000000000009'')');

SELECT pg_temp.assert_0133((SELECT state = pg_temp.legacy_state_0133() FROM fixture_0133_legacy),
  'account lifecycle changed legacy business facts');
SELECT pg_temp.assert_0133(NOT has_function_privilege('tongxingzhe_runtime',
  'app_private.request_account_deletion_v1(uuid,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('tongxingzhe_runtime', 'app_private.restore_account_v1(uuid,uuid,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'app_private.request_account_deletion_v1(uuid,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'app_private.restore_account_v1(uuid,uuid,uuid)', 'EXECUTE'),
  'private writers are executable by runtime or PUBLIC');
SET LOCAL ROLE tongxingzhe_runtime;
-- The privileged snapshot helper cannot run as runtime; check ACL errors directly.
DO $fixture$
DECLARE statement text; actual_state text; relation_name text;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY['account_deletion_current', 'account_deletion_request_claims',
      'account_deletion_restore_claims', 'account_deletion_audit_events'] LOOP
    actual_state := NULL;
    BEGIN EXECUTE format('SELECT * FROM app_private.%I', relation_name);
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
    END;
    IF actual_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '0133 runtime accessed %', relation_name; END IF;
  END LOOP;
  FOREACH statement IN ARRAY ARRAY[
    'SELECT * FROM app_private.request_account_deletion_v1(gen_random_uuid(), gen_random_uuid())',
    'SELECT * FROM app_private.restore_account_v1(gen_random_uuid(), gen_random_uuid(), gen_random_uuid())'] LOOP
    actual_state := NULL;
    BEGIN EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
    END;
    IF actual_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '0133 runtime executed a private writer'; END IF;
  END LOOP;
END
$fixture$;
RESET ROLE;

ROLLBACK;
