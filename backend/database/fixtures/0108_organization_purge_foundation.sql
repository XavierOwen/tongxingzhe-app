\set ON_ERROR_STOP on
BEGIN;
-- Trusted rollback fixture proves the primitive, never organization selection.
CREATE TABLE app_private.purge_exact_row_fixture (workspace_id uuid, item_id integer, PRIMARY KEY(workspace_id,item_id));
CREATE TABLE app_private.purge_no_pk_fixture (item_id integer);
CREATE TRIGGER exact_row_fixture_immutable BEFORE UPDATE OR DELETE ON app_private.purge_exact_row_fixture
FOR EACH ROW EXECUTE FUNCTION app_private.reject_management_report_history_mutation();
INSERT INTO app_private.purge_exact_row_fixture VALUES
  ('81080000-0000-4000-8000-000000000001',1),
  ('81080000-0000-4000-8000-000000000001',2),
  ('81080000-0000-4000-8000-000000000002',1);
DO $proof$
DECLARE row_document jsonb := '{"workspace_id":"81080000-0000-4000-8000-000000000001","item_id":1}';
  target record;
BEGIN
  BEGIN
    DELETE FROM app_private.purge_exact_row_fixture WHERE item_id = 1;
    RAISE EXCEPTION '0108 unauthorized DELETE succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  FOR target IN SELECT * FROM (VALUES
    (pg_current_xact_id(), pg_backend_pid(), 'app_private.purge_exact_row_fixture'::regclass::oid, '{"item_id":1}'::jsonb),
    (pg_current_xact_id(), pg_backend_pid(), 'app_private.purge_exact_row_fixture'::regclass::oid, '{"workspace_id":"81080000-0000-4000-8000-000000000001","item_id":2}'::jsonb),
    (pg_current_xact_id(), pg_backend_pid(), 'app_private.purge_exact_row_fixture'::regclass::oid, row_document || '{"extra":true}'::jsonb),
    ('1'::xid8, pg_backend_pid(), 'app_private.purge_exact_row_fixture'::regclass::oid, row_document),
    (pg_current_xact_id(), pg_backend_pid()+1, 'app_private.purge_exact_row_fixture'::regclass::oid, row_document),
    (pg_current_xact_id(), pg_backend_pid(), 'app_private.purge_no_pk_fixture'::regclass::oid, row_document)
  ) AS wrong(transaction_id, backend_pid, relation_oid, row_pk) LOOP
    INSERT INTO app_private.organization_purge_delete_authorizations
    VALUES(target.transaction_id,target.backend_pid,'81080000-0000-4000-8000-000000000001',target.relation_oid,target.row_pk);
    IF app_private.organization_purge_row_delete_authorized_v1('app_private.purge_exact_row_fixture'::regclass,row_document)
    THEN RAISE EXCEPTION '0108 wrong full PK/relation/xid/backend authorized'; END IF;
    DELETE FROM app_private.organization_purge_delete_authorizations;
  END LOOP;
  INSERT INTO app_private.organization_purge_delete_authorizations VALUES(
    pg_current_xact_id(),pg_backend_pid(),'81080000-0000-4000-8000-000000000001',
    'app_private.purge_exact_row_fixture'::regclass,row_document);
  IF NOT app_private.organization_purge_row_delete_authorized_v1('app_private.purge_exact_row_fixture'::regclass,row_document)
    OR app_private.organization_purge_row_delete_authorized_v1('app_private.purge_exact_row_fixture'::regclass,'{"item_id":1}')
    OR app_private.organization_purge_row_delete_authorized_v1('app_private.purge_exact_row_fixture'::regclass,'{"workspace_id":"81080000-0000-4000-8000-000000000002","item_id":1}')
    OR app_private.organization_purge_row_delete_authorized_v1('app_private.purge_no_pk_fixture'::regclass,'{"item_id":1}')
  THEN RAISE EXCEPTION '0108 exact full PK/missing key/other row/no PK proof failed'; END IF;
  BEGIN
    UPDATE app_private.purge_exact_row_fixture SET item_id = 3 WHERE item_id = 1;
    RAISE EXCEPTION '0108 authorization admitted UPDATE';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  DELETE FROM app_private.purge_exact_row_fixture WHERE workspace_id = '81080000-0000-4000-8000-000000000001' AND item_id = 1;
  IF (SELECT count(*) FROM app_private.purge_exact_row_fixture) <> 2
  THEN RAISE EXCEPTION '0108 exact delete changed sibling/other workspace row'; END IF;
  DELETE FROM app_private.organization_purge_delete_authorizations;
  FOR target IN SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'app_private' AND c.relname IN (
'organization_creation_request_tombstones','organization_owner_transfer_request_tombstones','organization_directed_account_invitation_request_tombstones','organization_membership_self_leave_request_tombstones','organization_shareable_join_link_request_tombstones','organization_shareable_join_application_request_tombstones','organization_project_membership_assignment_request_tombstones','organization_purge_request_tombstones'
    ) LOOP
    INSERT INTO app_private.organization_purge_delete_authorizations VALUES(
      pg_current_xact_id(),pg_backend_pid(),'81080000-0000-4000-8000-000000000001',target.oid,'{"request_id":"81080000-0000-4000-8000-000000000003"}');
    IF app_private.organization_purge_row_delete_authorized_v1(target.oid,'{"request_id":"81080000-0000-4000-8000-000000000003"}')
    THEN RAISE EXCEPTION '0108 old tombstone authorized'; END IF;
  END LOOP;
  DELETE FROM app_private.organization_purge_delete_authorizations;
  BEGIN
    INSERT INTO app_private.organization_purge_request_tombstones VALUES('unknown','81080000-0000-4000-8000-000000000003',clock_timestamp());
    RAISE EXCEPTION '0108 unknown claim family accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO app_private.organization_purge_request_tombstones VALUES('organization-deletion-request','81080000-0000-4000-8000-000000000003','infinity');
    RAISE EXCEPTION '0108 infinite completion time accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
END
$proof$;

-- An INVOKER guard keeps its original 55000 path for a role denied checker.
CREATE TABLE app_data.purge_invoker_fixture (id integer PRIMARY KEY);
CREATE TRIGGER purge_invoker_guard BEFORE UPDATE OR DELETE ON app_data.purge_invoker_fixture
FOR EACH ROW EXECUTE FUNCTION app_data.reject_promotion_target_audit_mutation();
INSERT INTO app_data.purge_invoker_fixture VALUES(1);
GRANT DELETE ON app_data.purge_invoker_fixture TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
DO $invoker$
BEGIN
  BEGIN
    DELETE FROM app_data.purge_invoker_fixture;
    RAISE EXCEPTION '0108 runtime INVOKER guard admitted delete';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    IF SQLERRM <> 'promotion target audit is append-only' THEN RAISE; END IF;
  END;
END
$invoker$;
RESET ROLE;

DO $terminal$
DECLARE target record; completed_uuid uuid := '81070000-0000-4000-8000-000000000005';
BEGIN
  FOR target IN SELECT * FROM (VALUES
    ('request_organization_deletion_v1', 'organization-deletion-request', 'organization deletion idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000003'::uuid$arguments$),
    ('restore_organization_v1', 'organization-deletion-restore-request', 'organization restoration idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid$arguments$),
    ('configure_project_reporting_time_zone_v1', 'project-reporting-time-zone-change-request', 'project reporting time zone idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 0, 'America/Chicago', clock_timestamp()$arguments$),
    ('release_management_report_snapshot_v2', 'channel_management_report_snapshot_release', 'trusted management report release idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_channel_two_periods', 1$arguments$),
    ('release_management_current_city_report_snapshot_v1', 'current_city_management_report_snapshot_release', 'current city report release idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_current_city_two_periods', 1$arguments$),
    ('release_management_interest_report_snapshot_v1', 'interest_management_report_snapshot_release', 'management interest report release idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_interest_level_two_periods', 1$arguments$),
    ('declare_management_report_snapshot_replacement_v1', 'management-report-snapshot-replacement-request', 'management report replacement idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
    ('release_management_original_region_report_snapshot_v1', 'original_region_management_report_snapshot_release', 'original region report release idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_sessions_by_original_region_two_periods', 1$arguments$),
    ('declare_management_original_region_snapshot_replacement_v1', 'original_region_management_report_snapshot_replacement', 'original-region replacement idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
    ('configure_management_follow_up_consent_opt_in_v1', 'management-follow-up-consent-opt-in-request', 'management follow-up consent opt-in idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'follow_up_consent_ratio@1', '81070000-0000-4000-8000-000000000005'::uuid, 0, true$arguments$),
    ('release_management_follow_up_consent_ratio_report_snapshot_v1', 'follow_up_consent_ratio_management_report_snapshot_release', 'follow-up consent ratio report release idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, 'contact_target_follow_up_consent_ratio_two_periods', 1$arguments$),
    ('declare_management_current_city_snapshot_replacement_v1', 'current_city_management_report_snapshot_replacement', 'current-city replacement idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
    ('declare_management_interest_snapshot_replacement_v1', 'interest_management_report_snapshot_replacement', 'interest replacement idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$),
    ('declare_management_follow_up_consent_snapshot_replacement_v1', 'follow_up_consent_ratio_management_report_snapshot_replacement', 'follow-up consent ratio replacement idempotency conflict', $arguments$'81070000-0000-4000-8000-000000000005'::uuid, '81070000-0000-4000-8000-000000000001'::uuid, '81070000-0000-4000-8000-000000000003'::uuid, '81070000-0000-4000-8000-000000000006'::uuid, '81070000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'$arguments$)
  ) AS calls(name, family, error_message, arguments) LOOP
    IF target.family IN ('organization-deletion-request','organization-deletion-restore-request',
      'project-reporting-time-zone-change-request','management-follow-up-consent-opt-in-request',
      'management-report-snapshot-replacement-request','channel_management_report_snapshot_release')
    THEN
      INSERT INTO app_private.organization_purge_request_tombstones VALUES(target.family,completed_uuid,clock_timestamp()) ON CONFLICT DO NOTHING;
    END IF;
    BEGIN
      EXECUTE 'SELECT app_private.' || target.name || '(' || target.arguments || ')';
      RAISE EXCEPTION '0108 terminal request succeeded: %',target.name;
    EXCEPTION WHEN invalid_parameter_value THEN
      IF SQLERRM <> target.error_message THEN RAISE EXCEPTION '0108 terminal typed error changed: %',SQLERRM; END IF;
    END;
  END LOOP;
  -- One completed shared family bars every release/replacement family.
  -- The earlier loop's channel terminal is enough; helper check confirms nine.
  IF NOT app_private.organization_purge_request_completed_v1('interest_management_report_snapshot_replacement',completed_uuid)
    OR app_private.organization_purge_request_completed_v1('organization-creation-request',completed_uuid)
    OR EXISTS (SELECT 1 FROM app_private.management_report_release_request_claims WHERE release_request_id = completed_uuid)
    OR EXISTS (SELECT 1 FROM app_private.organization_deletion_request_claims WHERE request_id = completed_uuid)
    OR EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations)
  THEN RAISE EXCEPTION '0108 cross-family fence/claim absence failed'; END IF;
  BEGIN
    DELETE FROM app_private.organization_purge_request_tombstones WHERE request_uuid = completed_uuid;
    RAISE EXCEPTION '0108 terminal ledger DELETE succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN
    UPDATE app_private.organization_purge_request_tombstones SET purge_completed_at_utc = clock_timestamp() WHERE request_uuid = completed_uuid;
    RAISE EXCEPTION '0108 terminal ledger UPDATE succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END
$terminal$;
SELECT 'organization purge exact-row/replay rollback fixture: passed' AS result;
ROLLBACK;
