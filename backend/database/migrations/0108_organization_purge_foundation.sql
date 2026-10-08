-- Slice 7DJ supplies value-free replay fences and exact-row transaction proof.
-- Organization/row selection and atomic purge execution belong to 0109.
CREATE TABLE app_private.organization_purge_request_tombstones (
  claim_family text NOT NULL CHECK (claim_family IN (
    'organization-creation-request',
    'organization-owner-transfer-request',
    'organization-directed-account-invitation-request',
    'organization-membership-self-leave-request',
    'organization-shareable-join-link-request',
    'organization-shareable-join-application-request',
    'organization-project-membership-assignment-request',
    'organization-deletion-request',
    'organization-deletion-restore-request',
    'channel_management_report_snapshot_release',
    'current_city_management_report_snapshot_release',
    'interest_management_report_snapshot_release',
    'original_region_management_report_snapshot_release',
    'original_region_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_release',
    'current_city_management_report_snapshot_replacement',
    'interest_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_replacement',
    'management-report-snapshot-replacement-request',
    'project-reporting-time-zone-change-request',
    'management-follow-up-consent-opt-in-request'
  )),
  request_uuid uuid NOT NULL,
  purge_completed_at_utc timestamptz NOT NULL CHECK (isfinite(purge_completed_at_utc)),
  PRIMARY KEY (claim_family, request_uuid)
);

CREATE TABLE app_private.organization_purge_delete_authorizations (
  transaction_id xid8 NOT NULL,
  backend_pid integer NOT NULL,
  organization_workspace_id uuid NOT NULL,
  relation_oid oid NOT NULL,
  row_pk jsonb NOT NULL CHECK (jsonb_typeof(row_pk) = 'object'),
  PRIMARY KEY (transaction_id, backend_pid, organization_workspace_id, relation_oid, row_pk)
);
REVOKE ALL ON app_private.organization_purge_request_tombstones,
  app_private.organization_purge_delete_authorizations FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_organization_purge_request_tombstone_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'organization purge request tombstone is immutable';
END
$function$;
CREATE TRIGGER organization_purge_request_tombstones_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_purge_request_tombstones
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_purge_request_tombstone_v1();

CREATE FUNCTION app_private.organization_purge_row_delete_authorized_v1(
  requested_relation_oid oid, old_row jsonb
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE complete_pk jsonb; key_count integer; valid_keys boolean;
BEGIN
  IF requested_relation_oid IN (
    
    'app_private.organization_creation_request_tombstones'::regclass,
    'app_private.organization_owner_transfer_request_tombstones'::regclass,
    'app_private.organization_directed_account_invitation_request_tombstones'::regclass,
    'app_private.organization_membership_self_leave_request_tombstones'::regclass,
    'app_private.organization_shareable_join_link_request_tombstones'::regclass,
    'app_private.organization_shareable_join_application_request_tombstones'::regclass,
    'app_private.organization_project_membership_assignment_request_tombstones'::regclass
  ) OR requested_relation_oid = 'app_private.organization_purge_request_tombstones'::regclass
    OR jsonb_typeof(old_row) IS DISTINCT FROM 'object'
  THEN RETURN false; END IF;

  SELECT jsonb_object_agg(attribute.attname, old_row -> attribute.attname),
    count(*), bool_and(old_row ? attribute.attname AND old_row -> attribute.attname <> 'null'::jsonb)
  INTO complete_pk, key_count, valid_keys
  FROM pg_index AS primary_index
  CROSS JOIN LATERAL unnest(primary_index.indkey) WITH ORDINALITY AS key_column(attnum, position)
  JOIN pg_attribute AS attribute
    ON attribute.attrelid = primary_index.indrelid AND attribute.attnum = key_column.attnum
  WHERE primary_index.indrelid = requested_relation_oid AND primary_index.indisprimary
    AND key_column.position <= primary_index.indnkeyatts AND NOT attribute.attisdropped;
  IF key_count = 0 OR valid_keys IS NOT TRUE THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM app_private.organization_purge_delete_authorizations AS authorization_row
    WHERE authorization_row.transaction_id = pg_current_xact_id()
      AND authorization_row.backend_pid = pg_backend_pid()
      AND authorization_row.relation_oid = requested_relation_oid
      AND authorization_row.row_pk = complete_pk
  );
END
$function$;

CREATE FUNCTION app_private.organization_purge_request_completed_v1(
  requested_claim_family text, requested_request_uuid uuid
)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM app_private.organization_purge_request_tombstones AS tombstone
    WHERE tombstone.request_uuid = requested_request_uuid
      AND (tombstone.claim_family = requested_claim_family OR (
        requested_claim_family IN (
          'channel_management_report_snapshot_release',
    'current_city_management_report_snapshot_release',
    'interest_management_report_snapshot_release',
    'original_region_management_report_snapshot_release',
    'original_region_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_release',
    'current_city_management_report_snapshot_replacement',
    'interest_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_replacement'
        ) AND tombstone.claim_family IN (
          'channel_management_report_snapshot_release',
    'current_city_management_report_snapshot_release',
    'interest_management_report_snapshot_release',
    'original_region_management_report_snapshot_release',
    'original_region_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_release',
    'current_city_management_report_snapshot_replacement',
    'interest_management_report_snapshot_replacement',
    'follow_up_consent_ratio_management_report_snapshot_replacement'
        )
      ))
  );
$function$;
REVOKE ALL ON FUNCTION app_private.protect_organization_purge_request_tombstone_v1(),
  app_private.organization_purge_row_delete_authorized_v1(oid,jsonb),
  app_private.organization_purge_request_completed_v1(text,uuid)
FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE trusted_owner text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  EXECUTE format('ALTER TABLE app_private.organization_purge_request_tombstones OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER TABLE app_private.organization_purge_delete_authorizations OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.protect_organization_purge_request_tombstone_v1() OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.organization_purge_row_delete_authorized_v1(oid,jsonb) OWNER TO %I', trusted_owner);
  EXECUTE format('ALTER FUNCTION app_private.organization_purge_request_completed_v1(text,uuid) OWNER TO %I', trusted_owner);
END
$owner$;

-- Fixed reviewed guards only. Preserve the remainder of each existing body,
-- including every UPDATE/unlink exception and its owner/ACL/security settings.
DO $guards$
DECLARE identity text; function_row pg_proc%ROWTYPE; definition text; insert_at integer;
BEGIN
  FOREACH identity IN ARRAY ARRAY[
'app_data.enforce_questionnaire_definition_immutability()',
    'app_data.reject_questionnaire_metric_audit_mutation()',
    'app_data.reject_promotion_target_audit_mutation()',
    'app_data.reject_promotion_target_relationship_revision_mutation()',
    'app_data.validate_promotion_target_institution_relation()',
    'app_private.protect_membership_history_v1()',
    'app_private.protect_organization_owner_assignment_history_v1()',
    'app_private.protect_organization_creation_request_claim_v1()',
    'app_private.protect_organization_creation_audit_event_v1()',
    'app_private.protect_organization_owner_transfer_request_claim_v1()',
    'app_private.protect_organization_owner_transfer_audit_event_v1()',
    'app_private.protect_organization_directed_invitation_claim_v1()',
    'app_private.protect_organization_directed_invitation_audit_event_v1()',
    'app_private.protect_organization_membership_self_leave_request_claim_v1()',
    'app_private.protect_organization_membership_self_leave_audit_event_v1()',
    'app_private.protect_organization_shareable_join_link_claim_v1()',
    'app_private.protect_organization_shareable_join_link_audit_event_v1()',
    'app_private.protect_organization_shareable_join_application_claim_v1()',
    'app_private.protect_organization_shareable_join_application_audit_event_v1()',
    'app_private.protect_organization_project_membership_assignment_claim_v1()',
    'app_private.protect_organization_project_membership_assignment_terminal_v1()',
    'app_private.protect_organization_deletion_claim_v1()',
    'app_private.protect_organization_deletion_audit_v1()',
    'app_private.reject_management_report_history_mutation()',
    'app_private.reject_management_current_city_report_release_mutation()',
    'app_private.reject_project_reporting_time_zone_mutation_v1()',
    'app_private.reject_management_follow_up_consent_opt_in_mutation_v1()',
    'app_private.reject_contact_location_provenance_mutation_v1()'
  ] LOOP
    SELECT * INTO STRICT function_row FROM pg_proc WHERE oid = identity::regprocedure;
    definition := pg_get_functiondef(function_row.oid);
    insert_at := strpos(definition, E'BEGIN\n');
    IF insert_at = 0 THEN RAISE EXCEPTION '0108 guard body not found: %', identity; END IF;
    EXECUTE overlay(definition PLACING E'BEGIN\n  IF TG_OP = ''DELETE'' AND has_schema_privilege(current_user, ''app_private'', ''USAGE'') THEN\n    IF has_function_privilege(current_user, ''app_private.organization_purge_row_delete_authorized_v1(oid,jsonb)'', ''EXECUTE'') THEN\n      IF app_private.organization_purge_row_delete_authorized_v1(TG_RELID, to_jsonb(OLD)) THEN RETURN OLD; END IF;\n    END IF;\n  END IF;\n' FROM insert_at FOR 6);
    EXECUTE format('GRANT EXECUTE ON FUNCTION app_private.organization_purge_row_delete_authorized_v1(oid,jsonb) TO %I', pg_get_userbyid(function_row.proowner));
    IF NOT EXISTS (SELECT 1 FROM pg_proc AS replaced WHERE replaced.oid = function_row.oid
      AND replaced.proowner = function_row.proowner AND replaced.proacl IS NOT DISTINCT FROM function_row.proacl
      AND replaced.prosecdef = function_row.prosecdef AND replaced.proconfig IS NOT DISTINCT FROM function_row.proconfig)
    THEN RAISE EXCEPTION '0108 guard identity/owner/ACL changed: %', identity; END IF;
  END LOOP;
END
$guards$;

-- Check terminal UUIDs immediately after the existing family request lock.
DO $writers$
DECLARE target record; function_row pg_proc%ROWTYPE; definition text; request_lock text; fence text;
BEGIN
  FOR target IN SELECT * FROM (VALUES
    ('app_private.request_organization_deletion_v1(uuid,uuid,uuid)', 'organization-deletion-request', 'requested_request_id', 'organization deletion idempotency conflict'),
    ('app_private.restore_organization_v1(uuid,uuid,uuid,uuid)', 'organization-deletion-restore-request', 'requested_request_id', 'organization restoration idempotency conflict'),
    ('app_private.configure_project_reporting_time_zone_v1(uuid,uuid,uuid,integer,text,timestamptz)', 'project-reporting-time-zone-change-request', 'requested_change_request_id', 'project reporting time zone idempotency conflict'),
    ('app_private.release_management_report_snapshot_v1(uuid,uuid,uuid,text,integer,text,timestamptz,timestamptz)', 'channel_management_report_snapshot_release', 'requested_release_request_id', 'management report release idempotency conflict'),
    ('app_private.release_management_report_snapshot_v2(uuid,uuid,uuid,text,integer)', 'channel_management_report_snapshot_release', 'requested_release_request_id', 'trusted management report release idempotency conflict'),
    ('app_private.release_management_current_city_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'current_city_management_report_snapshot_release', 'requested_release_request_id', 'current city report release idempotency conflict'),
    ('app_private.release_management_interest_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'interest_management_report_snapshot_release', 'requested_release_request_id', 'management interest report release idempotency conflict'),
    ('app_private.declare_management_report_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'management-report-snapshot-replacement-request', 'requested_replacement_request_id', 'management report replacement idempotency conflict'),
    ('app_private.release_management_original_region_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'original_region_management_report_snapshot_release', 'requested_release_request_id', 'original region report release idempotency conflict'),
    ('app_private.declare_management_original_region_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'original_region_management_report_snapshot_replacement', 'requested_replacement_request_id', 'original-region replacement idempotency conflict'),
    ('app_private.configure_management_follow_up_consent_opt_in_v1(uuid,uuid,text,uuid,integer,boolean)', 'management-follow-up-consent-opt-in-request', 'requested_request_id', 'management follow-up consent opt-in idempotency conflict'),
    ('app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(uuid,uuid,uuid,text,integer)', 'follow_up_consent_ratio_management_report_snapshot_release', 'requested_release_request_id', 'follow-up consent ratio report release idempotency conflict'),
    ('app_private.declare_management_current_city_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'current_city_management_report_snapshot_replacement', 'requested_replacement_request_id', 'current-city replacement idempotency conflict'),
    ('app_private.declare_management_interest_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'interest_management_report_snapshot_replacement', 'requested_replacement_request_id', 'interest replacement idempotency conflict'),
    ('app_private.declare_management_follow_up_consent_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)', 'follow_up_consent_ratio_management_report_snapshot_replacement', 'requested_replacement_request_id', 'follow-up consent ratio replacement idempotency conflict')
  ) AS writers(identity, family, request_parameter, error_message)
  LOOP
    SELECT * INTO STRICT function_row FROM pg_proc WHERE oid = target.identity::regprocedure;
    definition := pg_get_functiondef(function_row.oid);
    request_lock := substring(definition FROM '(PERFORM (pg_catalog\.)?pg_advisory_xact_lock\([^;]+;)');
    IF request_lock IS NULL OR strpos(request_lock, target.request_parameter) = 0
    THEN RAISE EXCEPTION '0108 expected first request lock: %', target.identity; END IF;
    fence := format(E'\n  IF app_private.organization_purge_request_completed_v1(%L, %s) THEN\n    RAISE EXCEPTION USING ERRCODE = ''22023'', MESSAGE = %L;\n  END IF;\n', target.family, target.request_parameter, target.error_message);
    EXECUTE overlay(definition PLACING request_lock || fence FROM strpos(definition, request_lock) FOR length(request_lock));
    EXECUTE format('GRANT EXECUTE ON FUNCTION app_private.organization_purge_request_completed_v1(text,uuid) TO %I', pg_get_userbyid(function_row.proowner));
    IF NOT EXISTS (SELECT 1 FROM pg_proc AS replaced WHERE replaced.oid = function_row.oid
      AND replaced.proowner = function_row.proowner AND replaced.proacl IS NOT DISTINCT FROM function_row.proacl
      AND replaced.prosecdef = function_row.prosecdef AND replaced.proconfig IS NOT DISTINCT FROM function_row.proconfig)
    THEN RAISE EXCEPTION '0108 writer identity/owner/ACL changed: %', target.identity; END IF;
  END LOOP;
END
$writers$;
