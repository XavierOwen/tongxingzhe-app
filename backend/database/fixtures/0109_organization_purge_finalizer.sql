-- Synthetic imported history; all rows and injected guards roll back.
\set ON_ERROR_STOP on
BEGIN;
\ir shared/organization_purge_finalizer_seed.sql

CREATE TEMP TABLE fixture_0109_before(relation_name text,row_data jsonb);
DO $snapshot$
DECLARE relation_name text;
BEGIN
  FOR relation_name IN SELECT format('%I.%I',n.nspname,c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' LOOP
    EXECUTE format('INSERT INTO fixture_0109_before SELECT %L,to_jsonb(t) FROM %s t',relation_name,relation_name);
  END LOOP;
END
$snapshot$;
-- The merge fence is a global mutable control; keep its post-seed epoch.
UPDATE fixture_0109_preserved AS preserved
SET row_data = current.row_data
FROM fixture_0109_before AS current
WHERE preserved.relation_name =
    'app_private.personal_target_merge_generation_fence_v1'
  AND current.relation_name = preserved.relation_name;
CREATE TEMP TABLE fixture_0109_org_rows AS
TABLE fixture_0109_before EXCEPT TABLE fixture_0109_preserved;

-- Independent expectation from the populated source tables, not the purge's
-- collection helper or deletion predicates. Every current and historical UUID
-- is expected to receive the same finite completion time.
CREATE TEMP TABLE fixture_0109_completion_expected AS
SELECT 'organization-creation-request'::text AS claim_family,request_id AS request_uuid
FROM app_private.organization_creation_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-owner-transfer-request',request_id FROM app_private.organization_owner_transfer_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-directed-account-invitation-request',invitation_id FROM app_private.organization_directed_account_invitation_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-membership-self-leave-request',request_id FROM app_private.organization_membership_self_leave_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-shareable-join-link-request',link_id FROM app_private.organization_shareable_join_link_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-shareable-join-application-request',application_id FROM app_private.organization_shareable_join_application_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-project-membership-assignment-request',request_id FROM app_private.organization_project_membership_assignment_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-deletion-request',request_id FROM app_private.organization_deletion_request_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'organization-deletion-restore-request',request_id FROM app_private.organization_deletion_restore_claims WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
UNION SELECT 'channel_management_report_snapshot_release',release_request_id FROM app_private.management_report_release_attempts WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'channel_management_report_snapshot_release',release_request_id FROM app_private.management_report_release_v2_attempts WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'current_city_management_report_snapshot_release',release_request_id FROM app_private.management_current_city_report_release_attempts WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'interest_management_report_snapshot_release',release_request_id FROM app_private.management_interest_report_release_attempts WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'original_region_management_report_snapshot_release',release_request_id FROM app_private.management_original_region_report_release_attempts WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'follow_up_consent_ratio_management_report_snapshot_release',release_request_id FROM app_private.management_follow_up_consent_report_release_attempts WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'management-report-snapshot-replacement-request',replacement_request_id FROM app_private.management_report_snapshot_replacements WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'current_city_management_report_snapshot_replacement',replacement_request_id FROM app_private.management_current_city_report_snapshot_replacements WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'interest_management_report_snapshot_replacement',replacement_request_id FROM app_private.management_interest_report_snapshot_replacements WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'original_region_management_report_snapshot_replacement',replacement_request_id FROM app_private.management_original_region_report_snapshot_replacements WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'follow_up_consent_ratio_management_report_snapshot_replacement',replacement_request_id FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'project-reporting-time-zone-change-request',change_request_id FROM app_private.project_reporting_time_zone_versions WHERE project_id=(SELECT project_id FROM fixture_0109_project)
UNION SELECT 'management-follow-up-consent-opt-in-request',request_id FROM app_private.management_follow_up_consent_opt_in_versions WHERE project_id=(SELECT project_id FROM fixture_0109_project);

CREATE FUNCTION pg_temp.expect_0109_failure(expected_state text,statement text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE actual_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM expected_state THEN
    RAISE EXCEPTION '0109 expected SQLSTATE %, got % for %',expected_state,actual_state,statement;
  END IF;
END
$function$;

DO $fixture$
DECLARE w uuid := (SELECT organization_workspace_id FROM fixture_0109_org);
  cycle uuid := (SELECT deletion_request_id FROM fixture_0109_cycle);
  table_name text;
BEGIN
  IF (SELECT count(DISTINCT claim_family) FROM fixture_0109_completion_expected) <> 21 THEN
    RAISE EXCEPTION '0109 seed does not exercise all 21 UUID completion families'; END IF;
  FOREACH table_name IN ARRAY ARRAY[
    'app_data.change_feed',
    'app_data.contact_answers',
    'app_data.contact_attempts',
    'app_data.contact_audit_events',
    'app_data.contact_location_provenance',
    'app_data.contact_region_assignments',
    'app_data.contact_revision_conflicts',
    'app_data.contact_revisions',
    'app_data.contacts',
    'app_data.contact_target_links',
    'app_data.management_analysis_current_contexts',
    'app_data.management_report_capability_grants',
    'app_data.organization_memberships',
    'app_data.organization_owner_assignments',
    'app_data.processed_commands',
    'app_data.project_memberships',
    'app_data.projects',
    'app_data.promotion_target_access_events',
    'app_data.promotion_target_assignments',
    'app_data.promotion_target_creation_requests',
    'app_data.promotion_target_institution_relation_revisions',
    'app_data.promotion_target_institution_relationships',
    'app_data.promotion_target_project_relationships',
    'app_data.promotion_target_relationship_conflict_resolutions',
    'app_data.promotion_target_relationship_conflicts',
    'app_data.promotion_target_relationship_revisions',
    'app_data.promotion_target_retention_events',
    'app_data.promotion_target_retention_policies',
    'app_data.promotion_targets',
    'app_data.promotion_target_stage_aliases',
    'app_data.questionnaire_drafts',
    'app_data.questionnaire_metric_compatibility_events',
    'app_data.questionnaire_metric_members',
    'app_data.questionnaire_metrics',
    'app_data.questionnaire_options',
    'app_data.questionnaire_publish_requests',
    'app_data.questionnaire_questions',
    'app_data.questionnaire_versions',
    'app_data.warehouse_outbox',
    'app_data.workspaces',
    'app_private.deidentified_location_anomaly_access_events',
    'app_private.deidentified_location_anomaly_ids',
    'app_private.management_current_city_report_release_attempts',
    'app_private.management_current_city_report_snapshot_access_events',
    'app_private.management_current_city_report_snapshot_directory_access_events',
    'app_private.management_current_city_report_snapshot_replacements',
    'app_private.management_follow_up_consent_opt_in_versions',
    'app_private.management_follow_up_consent_ratio_report_snapshot_replacements',
    'app_private.management_follow_up_consent_report_release_attempts',
    'app_private.management_follow_up_consent_report_snapshot_access_events',
    'app_private.management_follow_up_consent_snapshot_directory_access_events',
    'app_private.management_interest_report_release_attempts',
    'app_private.management_interest_report_snapshot_access_events',
    'app_private.management_interest_report_snapshot_directory_access_events',
    'app_private.management_interest_report_snapshot_replacements',
    'app_private.management_original_region_report_release_attempts',
    'app_private.management_original_region_report_snapshot_access_events',
    'app_private.management_original_region_report_snapshot_replacements',
    'app_private.management_original_region_snapshot_directory_access_events',
    'app_private.management_report_release_attempts',
    'app_private.management_report_release_request_claims',
    'app_private.management_report_release_v2_attempts',
    'app_private.management_report_snapshot_access_events',
    'app_private.management_report_snapshot_directory_access_events',
    'app_private.management_report_snapshot_export_events',
    'app_private.management_report_snapshot_replacements',
    'app_private.management_report_snapshots',
    'app_private.organization_creation_audit_events',
    'app_private.organization_creation_request_claims',
    'app_private.organization_deletion_audit_events',
    'app_private.organization_deletion_current',
    'app_private.organization_deletion_request_claims',
    'app_private.organization_deletion_restore_claims',
    'app_private.organization_directed_account_invitation_audit_events',
    'app_private.organization_directed_account_invitation_request_claims',
    'app_private.organization_membership_self_leave_audit_events',
    'app_private.organization_membership_self_leave_request_claims',
    'app_private.organization_owner_transfer_audit_events',
    'app_private.organization_owner_transfer_request_claims',
    'app_private.organization_project_membership_assignment_audit_events',
    'app_private.organization_project_membership_assignment_request_claims',
    'app_private.organization_shareable_join_application_audit_events',
    'app_private.organization_shareable_join_application_request_claims',
    'app_private.organization_shareable_join_link_audit_events',
    'app_private.organization_shareable_join_link_request_claims',
    'app_private.project_reporting_time_zone_versions'] LOOP
    IF NOT EXISTS (SELECT 1 FROM fixture_0109_org_rows WHERE relation_name=table_name) THEN
      RAISE EXCEPTION '0109 business fixture has no real row in %',table_name; END IF;
  END LOOP;
  PERFORM pg_temp.expect_0109_failure('22023','SELECT * FROM app_private.finalize_organization_purge_v1(NULL,NULL)');
  PERFORM pg_temp.expect_0109_failure('42501',format('SELECT * FROM app_private.finalize_organization_purge_v1(%L,%L)',
    (SELECT workspace_id FROM fixture_0109_people WHERE n=1),cycle));
  PERFORM pg_temp.expect_0109_failure('55000',format('SELECT * FROM app_private.finalize_organization_purge_v1(%L,gen_random_uuid())',w));
  -- Old restored cycle cannot select the current request.
  PERFORM pg_temp.expect_0109_failure('55000',format('SELECT * FROM app_private.finalize_organization_purge_v1(%L,%L)',w,
    (SELECT deletion_request_id FROM app_private.organization_deletion_restore_claims WHERE organization_workspace_id=w LIMIT 1)));
  IF app_private.record_organization_purge_failed_v1(w,gen_random_uuid()) THEN RAISE EXCEPTION '0109 stale cycle failure marker changed state'; END IF;
END
$fixture$;

SELECT pg_temp.expect_0109_failure('55000',$statement$
  DO $future$
  DECLARE w uuid := (SELECT organization_workspace_id FROM fixture_0109_org);
    cycle uuid := (SELECT deletion_request_id FROM fixture_0109_cycle);
  BEGIN
    SET LOCAL session_replication_role=replica;
    UPDATE app_private.organization_deletion_current SET effective_at_utc=transaction_timestamp(),
      purge_after_utc=transaction_timestamp()+interval '720 hours' WHERE organization_workspace_id=w;
    UPDATE app_private.organization_deletion_request_claims c SET effective_at_utc=a.effective_at_utc,purge_after_utc=a.purge_after_utc
    FROM app_private.organization_deletion_current a WHERE c.request_id=a.deletion_request_id AND a.organization_workspace_id=w;
    UPDATE app_data.workspaces t SET deleted_at=a.effective_at_utc FROM app_private.organization_deletion_current a
    WHERE t.workspace_id=w AND a.organization_workspace_id=w;
    UPDATE app_private.organization_deletion_audit_events t SET occurred_at_utc=a.effective_at_utc
    FROM app_private.organization_deletion_current a WHERE t.request_id=a.deletion_request_id AND a.organization_workspace_id=w;
    SET LOCAL session_replication_role=origin;
    IF app_private.record_organization_purge_failed_v1(w,cycle) THEN RAISE EXCEPTION '0109 early failure marker accepted'; END IF;
    PERFORM app_private.finalize_organization_purge_v1(w,cycle);
  END
  $future$
$statement$);
SELECT pg_temp.expect_0109_failure('55000',$statement$
  DO $personal_reference$
  BEGIN
    UPDATE app_data.user_current_projects SET project_id=(SELECT project_id FROM fixture_0109_project)
    WHERE app_user_id=(SELECT app_user_id FROM fixture_0109_people WHERE n=2);
    PERFORM app_private.finalize_organization_purge_v1(
      (SELECT organization_workspace_id FROM fixture_0109_org),(SELECT deletion_request_id FROM fixture_0109_cycle));
  END
  $personal_reference$
$statement$);
SELECT pg_temp.expect_0109_failure('23503',$statement$
  DO $incoming_reference$
  BEGIN
    -- A personal draft holds an incoming FK to the imported organization Q.
    -- The finalizer must fail the real FK; it cannot expand its deletion scope.
    INSERT INTO app_data.questionnaire_drafts(project_id,source_questionnaire_version_id,definition,created_by_app_user_id,updated_by_app_user_id)
    SELECT control.project_id,imported.questionnaire_version_id,'{"questions":[]}'::jsonb,control.app_user_id,control.app_user_id
    FROM fixture_0109_people control CROSS JOIN fixture_0109_project imported WHERE control.n=2;
    PERFORM app_private.finalize_organization_purge_v1(
      (SELECT organization_workspace_id FROM fixture_0109_org),(SELECT deletion_request_id FROM fixture_0109_cycle));
  END
  $incoming_reference$
$statement$);

-- The guard fires after the final business root DELETE. This tests rollback
-- of already deleted children, both ledgers and transient authorization.
CREATE FUNCTION pg_temp.fail_0109_final_workspace_delete() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF OLD.workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='0109 injected final business delete failure';
  END IF;
  RETURN OLD;
END
$function$;
CREATE TRIGGER fixture_0109_final_delete_failure AFTER DELETE ON app_data.workspaces
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0109_final_workspace_delete();
SELECT pg_temp.expect_0109_failure('P0001',format('SELECT * FROM app_private.finalize_organization_purge_v1(%L,%L)',
  (SELECT organization_workspace_id FROM fixture_0109_org),(SELECT deletion_request_id FROM fixture_0109_cycle)));
DROP TRIGGER fixture_0109_final_delete_failure ON app_data.workspaces;

DO $unchanged$
DECLARE checked_relation text; actual_rows jsonb; expected_rows jsonb;
BEGIN
  FOR checked_relation IN SELECT format('%I.%I',n.nspname,c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %s t',checked_relation) INTO actual_rows;
    SELECT coalesce(jsonb_agg(row_data ORDER BY row_data::text),'[]'::jsonb) INTO expected_rows
    FROM fixture_0109_before saved WHERE saved.relation_name=checked_relation;
    IF actual_rows IS DISTINCT FROM expected_rows THEN RAISE EXCEPTION '0109 failure did not roll back %',checked_relation; END IF;
  END LOOP;
END
$unchanged$;

CREATE TEMP TABLE fixture_0109_completed AS
SELECT * FROM app_private.finalize_organization_purge_v1(
  (SELECT organization_workspace_id FROM fixture_0109_org),(SELECT deletion_request_id FROM fixture_0109_cycle));
CREATE TEMP TABLE fixture_0109_completed_retry AS
SELECT * FROM app_private.finalize_organization_purge_v1(
  (SELECT organization_workspace_id FROM fixture_0109_org),(SELECT deletion_request_id FROM fixture_0109_cycle));

DO $purged$
DECLARE checked_relation text; actual_rows jsonb; expected_rows jsonb;
  legacy record; actual_ids uuid[]; expected_ids uuid[];
BEGIN
  IF (SELECT count(*) FROM fixture_0109_completed) <> 1
    OR (SELECT count(*) FROM fixture_0109_completed_retry) <> 1
    OR EXISTS ((TABLE fixture_0109_completed EXCEPT TABLE fixture_0109_completed_retry)
      UNION ALL (TABLE fixture_0109_completed_retry EXCEPT TABLE fixture_0109_completed))
    OR EXISTS (SELECT 1 FROM fixture_0109_completed WHERE deletion_request_id<>(SELECT deletion_request_id FROM fixture_0109_cycle)
      OR NOT isfinite(purge_completed_at_utc) OR purge_completed_at_utc>clock_timestamp()) THEN
    RAISE EXCEPTION '0109 completion or same-result retry drift'; END IF;
  IF EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations)
    OR EXISTS (SELECT 1 FROM app_private.organization_deletion_current WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org))
    OR EXISTS (SELECT 1 FROM app_data.workspaces WHERE workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)) THEN
    RAISE EXCEPTION '0109 retained W/current/transient authorization'; END IF;
  IF EXISTS ((SELECT claim_family,request_uuid FROM app_private.organization_purge_request_tombstones
      EXCEPT (SELECT claim_family,request_uuid FROM fixture_0109_completion_expected
        UNION SELECT row_data->>'claim_family',(row_data->>'request_uuid')::uuid FROM fixture_0109_preserved WHERE relation_name='app_private.organization_purge_request_tombstones'))
    UNION ALL ((SELECT claim_family,request_uuid FROM fixture_0109_completion_expected
      UNION SELECT row_data->>'claim_family',(row_data->>'request_uuid')::uuid FROM fixture_0109_preserved WHERE relation_name='app_private.organization_purge_request_tombstones') EXCEPT SELECT claim_family,request_uuid FROM app_private.organization_purge_request_tombstones))
    OR EXISTS (SELECT 1 FROM app_private.organization_purge_request_tombstones
      WHERE (claim_family,request_uuid) IN (SELECT claim_family,request_uuid FROM fixture_0109_completion_expected)
        AND purge_completed_at_utc IS DISTINCT FROM (SELECT purge_completed_at_utc FROM fixture_0109_completed)) THEN
    RAISE EXCEPTION '0109 exact completion UUIDs or single observation time drift'; END IF;
  FOR legacy IN SELECT * FROM (VALUES
    ('organization_creation_request_tombstones','request_id','organization-creation-request','organization-creation:v1'),
    ('organization_owner_transfer_request_tombstones','request_id','organization-owner-transfer-request','organization-owner-transfer:v1'),
    ('organization_directed_account_invitation_request_tombstones','invitation_id','organization-directed-account-invitation-request','organization-directed-account-invitation:v1'),
    ('organization_membership_self_leave_request_tombstones','request_id','organization-membership-self-leave-request','organization-membership-self-leave:v1'),
    ('organization_shareable_join_link_request_tombstones','link_id','organization-shareable-join-link-request','organization-shareable-join-link:v1'),
    ('organization_shareable_join_application_request_tombstones','application_id','organization-shareable-join-application-request','organization-shareable-join-application:v1'),
    ('organization_project_membership_assignment_request_tombstones','request_id','organization-project-membership-assignment-request','organization-project-membership-assignment:v1')
  ) l(table_name,key_name,family,legacy_family) LOOP
    EXECUTE format('SELECT array_agg(%I ORDER BY %I) FROM app_private.%I WHERE claim_family=$1',legacy.key_name,legacy.key_name,legacy.table_name)
    INTO actual_ids USING legacy.legacy_family;
    SELECT array_agg(request_uuid ORDER BY request_uuid) INTO expected_ids FROM (
      SELECT request_uuid FROM fixture_0109_completion_expected WHERE claim_family=legacy.family
      UNION SELECT (row_data->>legacy.key_name)::uuid FROM fixture_0109_preserved
      WHERE relation_name='app_private.' || legacy.table_name AND row_data->>'claim_family'=legacy.legacy_family) expected;
    IF actual_ids IS DISTINCT FROM expected_ids THEN RAISE EXCEPTION '0109 old family tombstone missing: %',legacy.family; END IF;
  END LOOP;
  -- Prior completed UUIDs are controls too, including their full row values.
  FOR checked_relation IN SELECT DISTINCT relation_name FROM fixture_0109_preserved
    WHERE relation_name LIKE '%request_tombstones' LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %s t WHERE to_jsonb(t) IN (SELECT row_data FROM fixture_0109_preserved WHERE relation_name=$1)',checked_relation)
      INTO actual_rows USING checked_relation;
    SELECT coalesce(jsonb_agg(row_data ORDER BY row_data::text),'[]'::jsonb) INTO expected_rows
      FROM fixture_0109_preserved WHERE relation_name=checked_relation;
    IF actual_rows IS DISTINCT FROM expected_rows THEN RAISE EXCEPTION '0109 existing terminal control row changed in %',checked_relation; END IF;
  END LOOP;
  FOR checked_relation IN SELECT format('%I.%I',n.nspname,c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r'
      AND c.relname NOT LIKE '%request_tombstones' LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %s t',checked_relation) INTO actual_rows;
    SELECT coalesce(jsonb_agg(row_data ORDER BY row_data::text),'[]'::jsonb) INTO expected_rows
    FROM fixture_0109_preserved saved WHERE saved.relation_name=checked_relation;
    IF actual_rows IS DISTINCT FROM expected_rows THEN
      RAISE EXCEPTION '0109 organization payload remains or control changed in %',checked_relation; END IF;
  END LOOP;
END
$purged$;

-- Composite text receipts are removed by business evidence. The old W/P is
-- unavailable, but the same text key can serve a NEW personal operation.
SELECT pg_temp.expect_0109_failure('42501',format('SELECT target FROM app_data.create_promotion_target(%L,%L,%L,''person'',''0109 organization person'',NULL,NULL,''0109-person'')',
  (SELECT app_user_id FROM fixture_0109_people WHERE n=1),(SELECT organization_workspace_id FROM fixture_0109_org),(SELECT project_id FROM fixture_0109_project)));
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=1),(SELECT workspace_id FROM fixture_0109_people WHERE n=1),
  (SELECT project_id FROM fixture_0109_people WHERE n=1),'person','0109 new personal operation',NULL,NULL,'0109-person');
DO $text_receipts$
DECLARE actor uuid := (SELECT app_user_id FROM fixture_0109_people WHERE n=1);
  result record; draft jsonb;
BEGIN
  -- Observe the old missing W/P inside a rollback subtransaction, since a new
  -- forbidden result is itself a processed command and must not occupy the key
  -- in the subsequent NEW personal operation test.
  BEGIN
    SELECT * INTO result FROM app_data.apply_contact_submit(actor,'0109-submit',1,'contact.submit.v1',
      '0109-device','0109-contact',0,jsonb_build_object('contactId','0109-contact',
        'workspaceId',(SELECT organization_workspace_id FROM fixture_0109_org),
        'projectId',(SELECT project_id FROM fixture_0109_project),
        'questionnaireVersionId',(SELECT questionnaire_version_id FROM fixture_0109_project)));
    IF result.result_code IS DISTINCT FROM 'forbidden' THEN RAISE EXCEPTION '0109 old receipt payload remained readable: %',result; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0109',MESSAGE='rollback observed new forbidden receipt';
  EXCEPTION WHEN SQLSTATE 'Z0109' THEN NULL; END;
  SELECT * INTO result FROM app_data.apply_contact_submit(actor,'0109-submit',1,'contact.submit.v1',
    '0109-new-personal-device','0109-new-personal-contact',0,
    (SELECT jsonb_build_object('contactId','0109-new-personal-contact','workspaceId',workspace_id,
      'projectId',project_id,'questionnaireVersionId',questionnaire_version_id,'occurredAtUtc',clock_timestamp(),
      'occurredTimeZone','UTC','channel','voice_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',1,'interestLevel',2,'answers','[]'::jsonb) FROM fixture_0109_people WHERE n=1));
  IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0109 deleted text command key became a permanent UUID fence'; END IF;
  SELECT created.draft INTO draft FROM app_data.create_questionnaire_draft(actor,
    (SELECT workspace_id FROM fixture_0109_people WHERE n=1),(SELECT project_id FROM fixture_0109_people WHERE n=1),
    (SELECT questionnaire_version_id FROM fixture_0109_people WHERE n=1)) created;
  PERFORM app_data.update_questionnaire_draft(actor,(SELECT workspace_id FROM fixture_0109_people WHERE n=1),
    (SELECT project_id FROM fixture_0109_people WHERE n=1),(draft->>'draft_id')::uuid,1,
    '[{"question_id":"consent","position":1,"prompt":"Continue?","type":"boolean","required":false,"allow_unknown":true,"allow_refused":true,"allow_not_applicable":true}]'::jsonb);
  PERFORM app_data.publish_questionnaire_draft(actor,(SELECT workspace_id FROM fixture_0109_people WHERE n=1),
    (SELECT project_id FROM fixture_0109_people WHERE n=1),(draft->>'draft_id')::uuid,2,'0109-publish','NEW personal publication');
END
$text_receipts$;
ROLLBACK;
