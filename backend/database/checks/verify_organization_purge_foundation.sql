\set ON_ERROR_STOP on
DO $check$
DECLARE owner_oid oid; target record; table_oid oid; role_row record; body text;
BEGIN
  SELECT proowner INTO STRICT owner_oid FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  FOR table_oid IN SELECT unnest(ARRAY[
    'app_private.organization_purge_request_tombstones'::regclass,
    'app_private.organization_purge_delete_authorizations'::regclass])
  LOOP
    IF has_table_privilege('tongxingzhe_runtime', table_oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    THEN RAISE EXCEPTION '0108 runtime purge table access leaked'; END IF;
    IF (SELECT relowner FROM pg_class WHERE oid = table_oid) <> owner_oid
      OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = table_oid AND contype = 'f')
    THEN RAISE EXCEPTION '0108 table owner/FK drift'; END IF;
    FOR role_row IN SELECT oid, rolname FROM pg_roles WHERE oid <> owner_oid AND NOT rolsuper AND rolname LIKE 'tongxingzhe_%' LOOP
      IF has_table_privilege(role_row.oid, table_oid, 'INSERT,UPDATE,DELETE,TRUNCATE')
      THEN RAISE EXCEPTION '0108 purge table mutation leaked to %', role_row.rolname; END IF;
    END LOOP;
  END LOOP;
  IF (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute
    WHERE attrelid = 'app_private.organization_purge_request_tombstones'::regclass AND attnum > 0 AND NOT attisdropped)
    IS DISTINCT FROM ARRAY['claim_family','request_uuid','purge_completed_at_utc']::text[]
    OR (SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid = 'app_private.organization_purge_delete_authorizations'::regclass AND contype = 'p')
      IS DISTINCT FROM 'PRIMARY KEY (transaction_id, backend_pid, organization_workspace_id, relation_oid, row_pk)'
  THEN RAISE EXCEPTION '0108 value-free/composite PK contract drift'; END IF;
  FOR target IN SELECT * FROM (VALUES
    ('app_private.organization_purge_row_delete_authorized_v1(oid,jsonb)'),
    ('app_private.organization_purge_request_completed_v1(text,uuid)'),
    ('app_private.protect_organization_purge_request_tombstone_v1()')
  ) AS functions(identity) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = target.identity::regprocedure
      AND proowner = owner_oid AND prosecdef AND proconfig = ARRAY['search_path=pg_catalog'])
      OR has_function_privilege('tongxingzhe_runtime', target.identity, 'EXECUTE')
    THEN RAISE EXCEPTION '0108 private helper owner/security/ACL drift: %', target.identity; END IF;
  END LOOP;
  FOR target IN SELECT * FROM (VALUES
    ('app_private.request_organization_deletion_v1(uuid,uuid,uuid)', 'organization-deletion-request', 'requested_request_id'),
    ('app_private.restore_organization_v1(uuid,uuid,uuid,uuid)', 'organization-deletion-restore-request', 'requested_request_id'),
    ('app_private.configure_project_reporting_time_zone_v1(uuid,uuid,uuid,integer,text,timestamptz)', 'project-reporting-time-zone-change-request', 'requested_change_request_id'),
    ('app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)', 'channel_management_report_snapshot_release', 'requested_release_request_id'),
    ('app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'current_city_management_report_snapshot_release', 'requested_release_request_id'),
    ('app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'interest_management_report_snapshot_release', 'requested_release_request_id'),
    ('app_private.declare_management_report_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'management-report-snapshot-replacement-request', 'requested_replacement_request_id'),
    ('app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'original_region_management_report_snapshot_release', 'requested_release_request_id'),
    ('app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'original_region_management_report_snapshot_replacement', 'requested_replacement_request_id'),
    ('app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)', 'management-follow-up-consent-opt-in-request', 'requested_request_id'),
    ('app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'follow_up_consent_ratio_management_report_snapshot_release', 'requested_release_request_id'),
    ('app_private.declare_management_current_city_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'current_city_management_report_snapshot_replacement', 'requested_replacement_request_id'),
    ('app_private.declare_management_interest_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'interest_management_report_snapshot_replacement', 'requested_replacement_request_id'),
    ('app_private.declare_management_follow_up_consent_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'follow_up_consent_ratio_management_report_snapshot_replacement', 'requested_replacement_request_id')
  ) AS writers(identity, family, request_parameter) LOOP
    SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid = target.identity::regprocedure;
    IF strpos(body, 'organization_purge_request_completed_v1') = 0
      OR strpos(body, 'organization_purge_request_completed_v1') < strpos(body, 'pg_advisory_xact_lock')
      OR strpos(body, 'organization_purge_request_completed_v1') > strpos(body, 'INSERT INTO')
    THEN RAISE EXCEPTION '0108 terminal fence missing/outside request lock: %', target.identity; END IF;
  END LOOP;
END
$check$;
SELECT 'organization purge foundation schema/ACL: passed' AS result;
