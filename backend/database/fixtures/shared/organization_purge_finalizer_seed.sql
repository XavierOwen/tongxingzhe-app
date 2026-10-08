-- 0109 bounded synthetic seed. Caller owns BEGIN/COMMIT/ROLLBACK.
-- Contact/questionnaire/target writers currently authorize only personal roots.
-- Build their coherent history through those writers, then import that synthetic
-- graph into W during setup. This does not claim an organization runtime writer.
\set ON_ERROR_STOP on
SET LOCAL TIME ZONE 'UTC';
CREATE TEMP TABLE fixture_0109_people AS
SELECT n, context.* FROM generate_series(1,4) n
CROSS JOIN LATERAL app_data.bootstrap_personal_context(
  'https://synthetic-0109.example', 'actor-' || n) context;
SELECT context.* FROM generate_series(1,4) n
CROSS JOIN LATERAL app_data.list_personal_project_contexts('https://synthetic-0109.example','actor-' || n) context;
CREATE TEMP TABLE fixture_0109_current_before AS TABLE app_data.user_current_projects;

INSERT INTO app_data.canonical_region_tree_releases(tree_version,lifecycle_state,is_current)
VALUES ('synthetic-0109-tree','draft',false);
INSERT INTO app_data.canonical_region_versions(region_id,tree_version,parent_region_id,canonical_name,kind)
VALUES ('synthetic-0109-country','synthetic-0109-tree',NULL,'0109 country','country'),
  ('synthetic-0109-city','synthetic-0109-tree','synthetic-0109-country','0109 city','city');
INSERT INTO app_data.canonical_region_boundaries(boundary_id,region_id,tree_version,boundary)
VALUES ('synthetic-0109-boundary','synthetic-0109-city','synthetic-0109-tree',
  polygon '((-88,41),(-87,41),(-87,42),(-88,42))');
SELECT app_private.publish_canonical_region_tree_v1('synthetic-0109-tree',true);

-- The personal sibling uses the same command text with a different actor.
SELECT * FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=2), '0109-submit',1,
  'contact.submit.v1','0109-personal-device','0109-personal-contact',0,
  (SELECT jsonb_build_object('contactId','0109-personal-contact','workspaceId',workspace_id,
    'projectId',project_id,'questionnaireVersionId',questionnaire_version_id,
    'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','voice_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,
    'interestLevel',2,'answers','[]'::jsonb) FROM fixture_0109_people WHERE n=2));
SELECT target FROM app_data.create_promotion_target(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=2),
  (SELECT workspace_id FROM fixture_0109_people WHERE n=2),
  (SELECT project_id FROM fixture_0109_people WHERE n=2),
  'person','0109 personal target',NULL,NULL,'0109-person') created;
CREATE TEMP TABLE fixture_0109_other AS
SELECT * FROM app_private.create_organization_v1(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=2),gen_random_uuid(),'0109 other organization');
INSERT INTO app_data.projects(workspace_id,display_name)
SELECT organization_workspace_id,'0109 other project' FROM fixture_0109_other;

-- Full-row controls: shared definitions, identities, personal data and another W.
CREATE TEMP TABLE fixture_0109_preserved(relation_name text,row_data jsonb);
DO $snapshot$
DECLARE relation_name text;
BEGIN
  FOR relation_name IN SELECT format('%I.%I',n.nspname,c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' LOOP
    EXECUTE format('INSERT INTO fixture_0109_preserved SELECT %L,to_jsonb(t) FROM %s t',relation_name,relation_name);
  END LOOP;
END
$snapshot$;

CREATE TEMP TABLE fixture_0109_org AS
SELECT * FROM app_private.create_organization_v1(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=1),gen_random_uuid(),'0109 enriched organization');
CREATE TEMP TABLE fixture_0109_project AS
SELECT * FROM app_data.create_personal_project_context(
  'https://synthetic-0109.example','actor-1','0109 imported history');
-- Match the existing fixed report fixture UUID shape. Current original-region
-- validators accept digit-only suffixes in the version and variant groups.
SET LOCAL session_replication_role=replica;
UPDATE app_data.projects SET project_id='00000109-0000-4000-8000-000000000001' WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE app_data.questionnaire_versions SET project_id='00000109-0000-4000-8000-000000000001' WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE app_data.user_current_projects SET project_id='00000109-0000-4000-8000-000000000001' WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE fixture_0109_project SET project_id='00000109-0000-4000-8000-000000000001';
SET LOCAL session_replication_role=origin;
CREATE TEMP TABLE fixture_0109_targets(kind text,target_id uuid);
CREATE TEMP TABLE fixture_0109_reports(family text,ordinal integer,request_id uuid,snapshot_id uuid,receipt jsonb);

DO $business$
DECLARE actor uuid := (SELECT app_user_id FROM fixture_0109_people WHERE n=1);
  personal_w uuid := (SELECT workspace_id FROM fixture_0109_project);
  p uuid := (SELECT project_id FROM fixture_0109_project);
  q1 uuid := (SELECT questionnaire_version_id FROM fixture_0109_project);
  q2 uuid; q3 uuid; d jsonb; publication jsonb; metric_event jsonb; target jsonb;
  person uuid; institution uuid; result record; payload jsonb; original_payload jsonb;
  conflict jsonb; metric uuid := gen_random_uuid();
  questions jsonb := '[{"question_id":"consent","position":1,"prompt":"Continue?","type":"boolean","required":false,"allow_unknown":true,"allow_refused":true,"allow_not_applicable":true},{"question_id":"topic","position":2,"prompt":"Topic","type":"single_choice","required":false,"allow_unknown":true,"allow_refused":true,"allow_not_applicable":true,"options":[{"option_id":"a","position":1,"label":"A"},{"option_id":"b","position":2,"label":"B"}]}]'::jsonb;
BEGIN
  SELECT draft INTO d FROM app_data.create_questionnaire_draft(actor,personal_w,p,q1);
  PERFORM app_data.update_questionnaire_draft(actor,personal_w,p,(d->>'draft_id')::uuid,1,questions);
  SELECT published.publication INTO publication FROM app_data.publish_questionnaire_draft(
    actor,personal_w,p,(d->>'draft_id')::uuid,2,'0109-publish','0109 first publication') published;
  q2 := (publication#>>'{summary,questionnaire_version_id}')::uuid;
  SELECT draft INTO d FROM app_data.create_questionnaire_draft(actor,personal_w,p,q2);
  SELECT published.publication INTO publication FROM app_data.publish_questionnaire_draft(
    actor,personal_w,p,(d->>'draft_id')::uuid,1,'0109-publish-next','0109 second publication') published;
  q3 := (publication#>>'{summary,questionnaire_version_id}')::uuid;
  SELECT event INTO metric_event FROM app_data.record_questionnaire_metric_compatibility(
    actor,personal_w,p,metric,'0109 consent','proportion',q2,'consent',q3,'consent',
    'compatible','Same definition','0109-compatible');
  PERFORM app_data.revoke_questionnaire_metric_compatibility(actor,personal_w,p,
    (metric_event->>'event_id')::uuid,'Reviewed definition','0109-revoke');
  -- Leave a source-bound draft behind; purge must honor its version FK.
  PERFORM app_data.create_questionnaire_draft(actor,personal_w,p,q3);
  SELECT created.target INTO target FROM app_data.create_promotion_target(
    actor,personal_w,p,'person','0109 organization person','+1 312 555 0109',NULL,'0109-person') created;
  person := (target->>'target_id')::uuid;
  SELECT created.target INTO target FROM app_data.create_promotion_target(
    actor,personal_w,p,'institution','0109 institution',NULL,'0109@example.test','0109-institution') created;
  institution := (target->>'target_id')::uuid;
  INSERT INTO fixture_0109_targets VALUES ('person',person),('institution',institution);
  PERFORM app_data.create_target_institution_relationship(actor,personal_w,p,person,institution,
    'employment_representative','0109 representative','0109-institution-relation');
  PERFORM app_data.configure_promotion_target_retention_policy(actor,personal_w,p,6);
  PERFORM app_data.apply_promotion_target_retention_action(actor,personal_w,p,person,'renew','purpose_confirmed','0109-renew');
  SELECT * INTO result FROM app_data.apply_contact_attempt_submit(actor,'0109-attempt-command',1,
    'contact.attempt.submit.v1','0109-device','0109-attempt',0,
    jsonb_build_object('attemptId','0109-attempt','workspaceId',personal_w,'projectId',p,
      'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','voice_call'));
  IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0109 attempt seed rejected: %',result; END IF;
  payload := jsonb_build_object('contactId','0109-contact','workspaceId',personal_w,'projectId',p,
    'questionnaireVersionId',q3,'sourceAttemptId','0109-attempt',
    'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','pending_resolution','latitude',0,'longitude',0,'accuracyMeters',5),
    'reachCount',2,'interestLevel',3,'answers',jsonb_build_array(
      jsonb_build_object('questionId','consent','state','answered','type','boolean','value',true)),
    'targetLinks',jsonb_build_array(jsonb_build_object('targetId',person,'targetType','person',
      'responseLevel',3,'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true)));
  SELECT * INTO result FROM app_data.apply_contact_submit_v3(actor,'0109-submit',1,
    'contact.submit.v1','0109-device','0109-contact',0,payload);
  IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0109 contact seed rejected: %',result; END IF;
  SELECT * INTO result FROM app_data.apply_contact_submit_v3(actor,'0109-resolved-submit',1,
    'contact.submit.v1','0109-device','0109-resolved-contact',0,
    payload || jsonb_build_object('contactId','0109-resolved-contact','sourceAttemptId',NULL,
      'targetLinks','[]'::jsonb,'occurredAtUtc',
      app_private.resolve_management_report_periods_v1('UTC',clock_timestamp())#>>'{current_period,start_utc}',
      'location',jsonb_build_object('kind','resolved','placeName','0109 city',
        'smallestRegionId','synthetic-0109-city','regionTreeVersion','synthetic-0109-tree')));
  IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0109 resolved seed rejected: %',result; END IF;
  SELECT snapshot INTO original_payload FROM app_data.contact_revisions WHERE contact_id='0109-contact' AND revision_number=1;
  SELECT * INTO result FROM app_data.apply_contact_revise_v3(actor,'0109-revise',1,
    'contact.revise.v1','0109-device','0109-contact',1,
    original_payload || jsonb_build_object('reason','0109 corrected interest','interestLevel',4));
  IF result.result_code <> 'accepted' THEN RAISE EXCEPTION '0109 correction seed rejected: %',result; END IF;
  SELECT * INTO result FROM app_data.apply_contact_revise_v3(actor,'0109-conflict',1,
    'contact.revise.v1','0109-other-device','0109-contact',1,
    original_payload || jsonb_build_object('reason','0109 concurrent interest','interestLevel',0));
  IF result.result_code <> 'conflict' THEN RAISE EXCEPTION '0109 conflict seed missing: %',result; END IF;
  PERFORM app_data.configure_promotion_target_stage_aliases(actor,personal_w,p,
    '[{"stage":0,"display_name":"Initial"},{"stage":1,"display_name":null},{"stage":2,"display_name":"Following"},{"stage":3,"display_name":null},{"stage":4,"display_name":"Goal"}]'::jsonb);
  PERFORM app_data.update_promotion_target_relationship(actor,personal_w,p,person,1,4,'active',NULL,'progress_update',NULL,'0109-up',NULL);
  SELECT updated.result INTO conflict FROM app_data.update_promotion_target_relationship(actor,personal_w,p,person,
    1,2,'active',NULL,'correction','Other device','0109-target-conflict',NULL) updated;
  IF conflict->>'status' <> 'conflict' THEN RAISE EXCEPTION '0109 target conflict seed missing'; END IF;
  PERFORM app_data.update_promotion_target_relationship(actor,personal_w,p,person,
    2,2,'active',NULL,'correction','Resolve branch','0109-target-resolve',(conflict->>'conflict_id')::uuid);
  PERFORM app_data.list_assigned_promotion_targets(actor,personal_w,p);
END
$business$;

-- Explicit fixture import. No production guard is disabled by the finalizer.
SET LOCAL session_replication_role=replica;
UPDATE app_data.projects SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org)
WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE app_data.contacts SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE app_data.contact_attempts SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE attempt_id='0109-attempt';
UPDATE app_data.change_feed SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE app_data.contact_revision_conflicts SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE project_id=(SELECT project_id FROM fixture_0109_project);
UPDATE app_data.promotion_targets SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE promotion_target_id IN (SELECT target_id FROM fixture_0109_targets);
UPDATE app_data.promotion_target_access_events SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE promotion_target_id IN (SELECT target_id FROM fixture_0109_targets);
UPDATE app_data.promotion_target_institution_relationships SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE person_target_id IN (SELECT target_id FROM fixture_0109_targets);
UPDATE app_data.promotion_target_retention_events SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE promotion_target_id IN (SELECT target_id FROM fixture_0109_targets);
UPDATE app_data.promotion_target_retention_policies SET workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org) WHERE workspace_id=(SELECT workspace_id FROM fixture_0109_people WHERE n=1);
UPDATE app_data.user_current_projects t SET project_id=b.project_id,updated_at=b.updated_at
FROM fixture_0109_current_before b WHERE t.app_user_id=b.app_user_id;
SET LOCAL session_replication_role=origin;

DO $organization$
DECLARE actor uuid := (SELECT app_user_id FROM fixture_0109_people WHERE n=1);
  invited uuid := (SELECT app_user_id FROM fixture_0109_people WHERE n=3);
  applicant uuid := (SELECT app_user_id FROM fixture_0109_people WHERE n=4);
  w uuid := (SELECT organization_workspace_id FROM fixture_0109_org);
  p uuid := (SELECT project_id FROM fixture_0109_project);
  invitation uuid := gen_random_uuid(); link uuid := gen_random_uuid(); application uuid := gen_random_uuid();
  invited_member uuid; applicant_member uuid; actor_member uuid; pm uuid;
BEGIN
  PERFORM app_private.create_organization_directed_account_invitation_v1(actor,invitation,w,invited);
  SELECT organization_membership_id INTO invited_member FROM app_private.accept_organization_directed_account_invitation_v1(invited,invitation);
  PERFORM app_private.create_organization_shareable_join_link_v1(actor,link,w);
  PERFORM app_private.submit_organization_shareable_join_application_v1(applicant,application,link);
  SELECT organization_membership_id INTO applicant_member FROM app_private.approve_organization_shareable_join_application_v1(actor,application,w);
  actor_member := (SELECT organization_membership_id FROM fixture_0109_org);
  SELECT project_membership_id INTO pm FROM app_private.assign_organization_project_member_v1(actor,gen_random_uuid(),w,p,actor_member);
  PERFORM app_private.assign_organization_project_member_v1(actor,gen_random_uuid(),w,p,applicant_member);
  INSERT INTO app_data.management_report_capability_grants(capability_grant_id,project_membership_id,capability_id,active_from_utc)
  SELECT gen_random_uuid(),pm,capability,clock_timestamp() FROM unnest(ARRAY[
    'release_management_reports','view_anonymous_analytics','export_management_reports','view_deidentified_anomalies']) capability;
  PERFORM app_private.leave_organization_membership_v1(invited,gen_random_uuid(),w);
  -- 0098 closes at transaction_timestamp(); same-transaction newly created
  -- memberships cannot supply a historical transfer fixture without this setup.
  SET LOCAL session_replication_role=replica;
  UPDATE app_data.organization_memberships SET active_from_utc=transaction_timestamp()-interval '1 hour' WHERE organization_workspace_id=w;
  UPDATE app_data.organization_owner_assignments SET active_from_utc=transaction_timestamp()-interval '1 hour' WHERE organization_membership_id=actor_member;
  SET LOCAL session_replication_role=origin;
  PERFORM app_private.transfer_organization_owner_v1(actor,gen_random_uuid(),w,applicant_member);
  -- Real restored history precedes a new cycle; both UUID families must finish.
  SELECT deletion_request_id INTO invitation FROM app_private.request_organization_deletion_v1(applicant,gen_random_uuid(),w);
  PERFORM app_private.restore_organization_v1(applicant,gen_random_uuid(),w,invitation);
  PERFORM app_private.configure_project_reporting_time_zone_v1(gen_random_uuid(),actor,p,0,'UTC',transaction_timestamp()-interval '365 days');
END
$organization$;

SELECT * FROM app_data.select_management_analysis_context_v1('https://synthetic-0109.example','actor-1',
  (SELECT project_id FROM fixture_0109_project));

GRANT SELECT ON fixture_0109_people,fixture_0109_project TO tongxingzhe_management_follow_up_consent_config_writer;
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=1),
  (SELECT project_id FROM fixture_0109_project),'follow_up_consent_ratio@1',gen_random_uuid(),0,true);
RESET ROLE;

DO $reports$
DECLARE actor uuid := (SELECT app_user_id FROM fixture_0109_people WHERE n=1);
  p uuid := (SELECT project_id FROM fixture_0109_project);
  report record; ordinal integer; request uuid; receipt jsonb; first_snapshot uuid; last_snapshot uuid;
BEGIN
  FOR report IN SELECT * FROM (VALUES
    ('channel','release_management_report_snapshot_v2','contact_sessions_by_channel_two_periods','declare_management_report_snapshot_replacement_v1','read_authorized_management_report_snapshot_v1','list_authorized_management_report_snapshots_v1','contact_revision'),
    ('current_city','release_management_current_city_report_snapshot_v1','contact_sessions_by_current_city_two_periods','declare_management_current_city_snapshot_replacement_v1','read_authorized_management_current_city_report_snapshot_v1','list_authorized_management_current_city_report_snapshots_v1','late_accepted_data'),
    ('interest','release_management_interest_report_snapshot_v1','contact_sessions_by_interest_level_two_periods','declare_management_interest_snapshot_replacement_v1','read_authorized_management_interest_report_snapshot_v1','list_authorized_management_interest_report_snapshots_v1','late_accepted_data'),
    ('original_region','release_management_original_region_report_snapshot_v1','contact_sessions_by_original_region_two_periods','declare_management_original_region_snapshot_replacement_v1','read_authorized_management_original_region_report_snapshot_v1','list_authorized_management_original_region_report_snapshots_v1','late_accepted_data'),
    ('consent','release_management_follow_up_consent_ratio_report_snapshot_v1','contact_target_follow_up_consent_ratio_two_periods','declare_management_follow_up_consent_snapshot_replacement_v1','read_authorized_management_follow_up_consent_report_snapshot_v1','list_authorized_management_follow_up_consent_snapshots_v1','late_accepted_data')
  ) r(family,release_function,report_id,replacement_function,read_function,directory_function,reason) LOOP
    FOR ordinal IN 1..2 LOOP
      request:=gen_random_uuid();
      EXECUTE format('SELECT app_private.%I($1,$2,$3,$4,1)',report.release_function)
      INTO receipt USING request,actor,p,report.report_id;
      IF receipt->>'result_status' NOT IN ('approved_baseline','approved') OR receipt->>'released_snapshot_id' IS NULL THEN
        RAISE EXCEPTION '0109 % snapshot seed failed: %',report.family,receipt;
      END IF;
      last_snapshot:=(receipt->>'released_snapshot_id')::uuid;
      IF ordinal=1 THEN first_snapshot:=last_snapshot; END IF;
      INSERT INTO fixture_0109_reports VALUES(report.family,ordinal,request,last_snapshot,receipt);
      PERFORM pg_sleep(0.01);
    END LOOP;
    EXECUTE format('SELECT app_private.%I($1,$2,$3,$4,$5,$6)',report.replacement_function)
    USING gen_random_uuid(),actor,p,first_snapshot,last_snapshot,report.reason;
    EXECUTE format('SELECT app_private.%I($1,$2,$3)',report.read_function) USING actor,p,last_snapshot;
    EXECUTE format('SELECT app_private.%I($1,$2)',report.directory_function) USING actor,p;
  END LOOP;
  PERFORM app_private.export_authorized_management_report_snapshot_v1(actor,p,
    (SELECT saved.snapshot_id FROM fixture_0109_reports saved WHERE saved.family='channel' AND saved.ordinal=2));
  PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(actor,p);
  PERFORM app_private.read_authorized_deidentified_location_anomaly_v1(actor,p,
    (SELECT ids.anomaly_id FROM app_private.deidentified_location_anomaly_ids ids
      JOIN app_data.contact_location_provenance source USING(source_id)
      WHERE source.contact_id='0109-contact' AND source.revision_number=2));
END
$reports$;

CREATE TEMP TABLE fixture_0109_cycle AS
SELECT * FROM app_private.request_organization_deletion_v1(
  (SELECT app_user_id FROM fixture_0109_people WHERE n=4),gen_random_uuid(),
  (SELECT organization_workspace_id FROM fixture_0109_org));
-- Expiry setup changes only matching synthetic lifecycle provenance. Ordinary
-- trigger behavior is restored before any production finalizer invocation.
SET LOCAL session_replication_role=replica;
UPDATE app_private.organization_deletion_current SET effective_at_utc=transaction_timestamp()-interval '721 hours',
  purge_after_utc=transaction_timestamp()-interval '1 hour'
WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org);
UPDATE app_private.organization_deletion_request_claims c SET effective_at_utc=a.effective_at_utc,purge_after_utc=a.purge_after_utc
FROM app_private.organization_deletion_current a WHERE c.request_id=a.deletion_request_id
  AND a.organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org);
UPDATE app_private.organization_deletion_audit_events audit SET occurred_at_utc=a.effective_at_utc
FROM app_private.organization_deletion_current a WHERE audit.request_id=a.deletion_request_id
  AND a.organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org);
UPDATE app_data.workspaces w SET deleted_at=a.effective_at_utc FROM app_private.organization_deletion_current a
WHERE w.workspace_id=a.organization_workspace_id AND w.workspace_id=(SELECT organization_workspace_id FROM fixture_0109_org);
SET LOCAL session_replication_role=origin;
