-- Synthetic account history unlink. All rows and fault triggers roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE FUNCTION pg_temp.assert_0135(condition boolean, label text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0135 %', label; END IF;
END
$function$;
CREATE FUNCTION pg_temp.state_0135(exclude_mutable_provenance boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; statements text; result jsonb;
BEGIN
  FOR relation IN SELECT schemaname, tablename FROM pg_catalog.pg_tables
    WHERE schemaname IN ('app_data','app_private')
      AND NOT (exclude_mutable_provenance AND schemaname='app_private' AND tablename IN (
        'personal_history_contribution_previews_v1','personal_history_contribution_confirmations_v1',
        'account_history_contribution_unlink_completions_v1')) ORDER BY schemaname,tablename
  LOOP
    statements := concat_ws(' UNION ALL ',statements,format('SELECT %L::text AS relation_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS contents FROM %I.%I t',
      relation.schemaname || '.' || relation.tablename,relation.schemaname,relation.tablename));
  END LOOP;
  IF statements IS NULL THEN RETURN '{}'::jsonb; END IF;
  EXECUTE 'SELECT jsonb_object_agg(relation_name,contents) FROM (' || statements || ') snapshots' INTO result;
  RETURN result;
END
$function$;
CREATE FUNCTION pg_temp.expect_0135_failure(expected_state text, expected_message text, statement text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE before_state jsonb := pg_temp.state_0135(); actual_state text; actual_message text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,actual_message=MESSAGE_TEXT;
  END;
  IF actual_state IS DISTINCT FROM expected_state
    OR (expected_message IS NOT NULL AND actual_message IS DISTINCT FROM expected_message) THEN
    RAISE EXCEPTION '0135 expected % / %, got % / %',expected_state,expected_message,actual_state,actual_message;
  END IF;
  PERFORM pg_temp.assert_0135(before_state=pg_temp.state_0135(),'failed unlink changed database facts');
END
$function$;

CREATE TEMP TABLE fixture_0135_actor AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0135.example.test','actor');
CREATE TEMP TABLE fixture_0135_owner AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0135.example.test','owner');
CREATE TEMP TABLE fixture_0135_empty AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0135.example.test','empty');
CREATE TEMP TABLE fixture_0135_org(kind text,organization_workspace_id uuid,project_id uuid,owner_membership_id uuid);
DO $seed$
DECLARE actor uuid := (SELECT app_user_id FROM fixture_0135_actor); owner uuid := (SELECT app_user_id FROM fixture_0135_owner);
  kind text; organization record; invitation uuid; membership uuid; project uuid;
BEGIN
  FOREACH kind IN ARRAY ARRAY['first','second'] LOOP
    SELECT * INTO STRICT organization FROM app_private.create_organization_v1(owner,gen_random_uuid(),'0135 '||kind||' organization');
    INSERT INTO app_data.projects(workspace_id,display_name) VALUES(organization.organization_workspace_id,'0135 '||kind||' project') RETURNING project_id INTO project;
    SELECT invitation_id INTO STRICT invitation FROM app_private.create_organization_directed_account_invitation_v1(owner,gen_random_uuid(),organization.organization_workspace_id,actor);
    SELECT organization_membership_id INTO STRICT membership FROM app_private.accept_organization_directed_account_invitation_v1(actor,invitation);
    PERFORM app_private.assign_organization_project_member_v1(owner,gen_random_uuid(),organization.organization_workspace_id,project,membership);
    PERFORM app_private.assign_organization_project_member_v1(owner,gen_random_uuid(),organization.organization_workspace_id,project,organization.organization_membership_id);
    INSERT INTO fixture_0135_org VALUES(kind,organization.organization_workspace_id,project,organization.organization_membership_id);
  END LOOP;
END
$seed$;
DO $seed$
DECLARE context record; contact text; result record;
BEGIN
  FOR context IN SELECT * FROM fixture_0135_actor UNION ALL SELECT * FROM fixture_0135_owner LOOP
    FOREACH contact IN ARRAY ARRAY['0135-source-one','0135-source-two','0135-unused-source'] LOOP
      contact := contact || CASE WHEN context.app_user_id=(SELECT app_user_id FROM fixture_0135_owner) THEN '-other' ELSE '' END;
      SELECT submitted.* INTO STRICT result FROM app_data.apply_contact_submit_v3(context.app_user_id,contact||'-submit',
        1,'contact.submit.v1','0135-device',contact,0,jsonb_build_object('contactId',contact,'workspaceId',context.workspace_id,
          'projectId',context.project_id,'questionnaireVersionId',context.questionnaire_version_id,'reason','0135 retained source',
          'occurredAtUtc','2025-05-06T07:08:09.123456Z','occurredTimeZone','Asia/Shanghai','channel','video_call',
          'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',3,'answers','[]'::jsonb,'targetLinks','[]'::jsonb)) submitted;
      PERFORM pg_temp.assert_0135(result.result_code='accepted',contact||' submit was rejected');
    END LOOP;
  END LOOP;
END
$seed$;
CREATE TEMP TABLE fixture_0135_paths(kind text,preview_id uuid,request_id uuid,copy_id uuid,target_project_id uuid,source_contact_id text);
DO $seed$
DECLARE actor uuid := (SELECT app_user_id FROM fixture_0135_actor); owner uuid := (SELECT app_user_id FROM fixture_0135_owner);
  org record; source text; preview uuid; request uuid; receipt record;
BEGIN
  FOR org IN TABLE fixture_0135_org LOOP
    FOREACH source IN ARRAY ARRAY['0135-source-one','0135-source-two'] LOOP
      SELECT preview_id INTO STRICT preview FROM app_private.preview_personal_history_contribution_v1(actor,source,org.project_id);
      request := gen_random_uuid();
      SELECT * INTO STRICT receipt FROM app_private.confirm_personal_history_contribution_v1(actor,request,preview);
      INSERT INTO fixture_0135_paths VALUES(org.kind||'-'||source,preview,request,receipt.copy_id,org.project_id,source);
    END LOOP;
    SELECT preview_id INTO STRICT preview FROM app_private.preview_personal_history_contribution_v1(actor,'0135-unused-source',org.project_id);
    INSERT INTO fixture_0135_paths VALUES(org.kind||'-unused',preview,NULL,NULL,org.project_id,'0135-unused-source');
  END LOOP;
  SELECT project_id INTO STRICT org FROM fixture_0135_org WHERE kind='first';
  SELECT preview_id INTO STRICT preview FROM app_private.preview_personal_history_contribution_v1(owner,'0135-source-one-other',org.project_id);
  request := gen_random_uuid();
  SELECT * INTO STRICT receipt FROM app_private.confirm_personal_history_contribution_v1(owner,request,preview);
  INSERT INTO fixture_0135_paths VALUES('other-actor',preview,request,receipt.copy_id,org.project_id,'0135-source-one-other');
END
$seed$;
-- Selection must follow either remaining identity reference and the preview closure.
UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id=NULL
WHERE preview_id IN(SELECT preview_id FROM fixture_0135_paths WHERE kind IN('second-0135-source-one','first-unused'));
UPDATE app_private.personal_history_contribution_confirmations_v1 SET actor_app_user_id=NULL
WHERE request_id=(SELECT request_id FROM fixture_0135_paths WHERE kind='second-0135-source-one');
UPDATE app_private.personal_history_contribution_previews_v1 SET source_contact_id=NULL
WHERE preview_id=(SELECT preview_id FROM fixture_0135_paths WHERE kind='first-0135-source-two');
UPDATE app_private.personal_history_contribution_confirmations_v1 SET source_contact_id=NULL
WHERE request_id=(SELECT request_id FROM fixture_0135_paths WHERE kind='first-0135-source-two');
UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id=NULL,source_contact_id=NULL
WHERE preview_id=(SELECT preview_id FROM fixture_0135_paths WHERE kind='second-0135-source-two');

CREATE TEMP TABLE fixture_0135_cycle AS SELECT receipt.* FROM fixture_0135_actor actor,
  LATERAL app_private.request_account_deletion_v1(actor.app_user_id,gen_random_uuid()) receipt;
SELECT pg_temp.expect_0135_failure('22023','invalid account history contribution unlink request',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1(NULL,NULL)');
SELECT pg_temp.expect_0135_failure('42501','account history contribution unlink forbidden',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1(NULL,gen_random_uuid())');
SELECT pg_temp.expect_0135_failure('42501','account history contribution unlink forbidden',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1(''00000000-0135-0000-8000-000000009999'',gen_random_uuid())');
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink not due',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle))');
SELECT pg_temp.expect_0135_failure('22023','account history contribution unlink cycle conflict',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),gen_random_uuid())');
SELECT * FROM app_private.restore_account_v1((SELECT app_user_id FROM fixture_0135_actor),gen_random_uuid(),(SELECT deletion_request_id FROM fixture_0135_cycle));
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle))');
CREATE TEMP TABLE fixture_0135_next AS SELECT receipt.* FROM fixture_0135_actor actor,
  LATERAL app_private.request_account_deletion_v1(actor.app_user_id,gen_random_uuid()) receipt;
SELECT pg_temp.expect_0135_failure('22023','account history contribution unlink cycle conflict',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle))');
DELETE FROM fixture_0135_cycle;
INSERT INTO fixture_0135_cycle TABLE fixture_0135_next;
DO $status$
DECLARE candidate_status text;
BEGIN
  FOREACH candidate_status IN ARRAY ARRAY['active','deleted'] LOOP
    UPDATE app_data.app_users SET status=candidate_status WHERE app_user_id=(SELECT app_user_id FROM fixture_0135_actor);
    PERFORM pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',
      'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle))');
    UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id=(SELECT app_user_id FROM fixture_0135_actor);
  END LOOP;
END
$status$;

SET LOCAL session_replication_role=replica;
UPDATE app_private.account_deletion_current SET effective_at_utc=boundary.at-interval '720 hours',purge_after_utc=boundary.at
FROM(SELECT clock_timestamp() AS at) boundary WHERE app_user_id=(SELECT app_user_id FROM fixture_0135_actor);
UPDATE app_private.account_deletion_request_claims claim SET effective_at_utc=attempt.effective_at_utc,purge_after_utc=attempt.purge_after_utc
FROM app_private.account_deletion_current attempt WHERE claim.request_id=attempt.deletion_request_id
  AND attempt.app_user_id=(SELECT app_user_id FROM fixture_0135_actor);
SET LOCAL session_replication_role=origin;

SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',$statement$
DO $corrupt$
BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_private.account_deletion_request_claims SET actor_app_user_id=NULL
  WHERE request_id=(SELECT deletion_request_id FROM fixture_0135_cycle);
  SET LOCAL session_replication_role=origin;
  PERFORM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle));
END $corrupt$
$statement$);
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',$statement$
DO $corrupt$
BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_private.personal_history_contribution_previews_v1 SET actor_app_user_id=(SELECT app_user_id FROM fixture_0135_owner)
  WHERE preview_id=(SELECT preview_id FROM fixture_0135_paths WHERE kind='first-unused');
  SET LOCAL session_replication_role=origin;
  PERFORM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle));
END $corrupt$
$statement$);
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',$statement$
DO $corrupt$
BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_private.personal_history_contribution_previews_v1 SET source_contact_id='0135-source-one-other'
  WHERE preview_id=(SELECT preview_id FROM fixture_0135_paths WHERE kind='first-0135-source-one');
  SET LOCAL session_replication_role=origin;
  PERFORM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle));
END $corrupt$
$statement$);
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',$statement$
DO $corrupt$
BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_private.organization_historical_contact_copies_v1 SET target_project_id=(SELECT project_id FROM fixture_0135_org WHERE kind='second')
  WHERE copy_id=(SELECT copy_id FROM fixture_0135_paths WHERE kind='first-0135-source-one');
  SET LOCAL session_replication_role=origin;
  PERFORM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle));
END $corrupt$
$statement$);
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',$statement$
DO $corrupt$
BEGIN
  SET LOCAL session_replication_role=replica;
  UPDATE app_private.personal_history_contribution_confirmations_v1 SET preview_id=(SELECT preview_id FROM fixture_0135_paths WHERE kind='first-unused')
  WHERE request_id=(SELECT request_id FROM fixture_0135_paths WHERE kind='first-0135-source-one');
  SET LOCAL session_replication_role=origin;
  PERFORM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle));
END $corrupt$
$statement$);

CREATE FUNCTION pg_temp.fail_0135_write() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF current_setting('fixture.fail_0135_table',true)=TG_TABLE_NAME THEN
    RAISE EXCEPTION USING ERRCODE='P0135',MESSAGE='0135 injected write failure';
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER fixture_0135_preview_failure BEFORE UPDATE ON app_private.personal_history_contribution_previews_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0135_write();
CREATE TRIGGER fixture_0135_confirmation_failure BEFORE UPDATE ON app_private.personal_history_contribution_confirmations_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0135_write();
CREATE TRIGGER fixture_0135_completion_failure BEFORE INSERT ON app_private.account_history_contribution_unlink_completions_v1
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0135_write();
DO $faults$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['personal_history_contribution_previews_v1','personal_history_contribution_confirmations_v1',
    'account_history_contribution_unlink_completions_v1'] LOOP
    PERFORM set_config('fixture.fail_0135_table',table_name,true);
    PERFORM pg_temp.expect_0135_failure('P0135','0135 injected write failure',
      'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle))');
  END LOOP;
  PERFORM set_config('fixture.fail_0135_table','',true);
END
$faults$;
CREATE TEMP TABLE fixture_0135_before AS SELECT pg_temp.state_0135(true) AS state;
CREATE TEMP TABLE fixture_0135_previews_before AS TABLE app_private.personal_history_contribution_previews_v1;
CREATE TEMP TABLE fixture_0135_confirmations_before AS TABLE app_private.personal_history_contribution_confirmations_v1;
CREATE TEMP TABLE fixture_0135_completed AS SELECT receipt.* FROM fixture_0135_actor actor,fixture_0135_cycle cycle,
  LATERAL app_private.unlink_due_account_history_contributions_v1(actor.app_user_id,cycle.deletion_request_id) receipt;
CREATE TEMP TABLE fixture_0135_replay AS SELECT receipt.* FROM fixture_0135_actor actor,fixture_0135_cycle cycle,
  LATERAL app_private.unlink_due_account_history_contributions_v1(actor.app_user_id,cycle.deletion_request_id) receipt;
SELECT pg_temp.assert_0135((SELECT count(*)=1 AND bool_and(account_history_contribution_unlink_contract_id='account-history-contribution-unlink:v1'
    AND deletion_request_id=(SELECT deletion_request_id FROM fixture_0135_cycle) AND isfinite(unlinked_at_utc)
    AND unlinked_at_utc >= (SELECT purge_after_utc FROM app_private.account_deletion_current WHERE app_user_id=(SELECT app_user_id FROM fixture_0135_actor)))
    FROM fixture_0135_completed)
  AND NOT EXISTS((TABLE fixture_0135_completed EXCEPT TABLE fixture_0135_replay) UNION ALL(TABLE fixture_0135_replay EXCEPT TABLE fixture_0135_completed))
  AND (SELECT count(*)=1 FROM app_private.account_history_contribution_unlink_completions_v1 WHERE deletion_request_id=(SELECT deletion_request_id FROM fixture_0135_cycle))
  AND (SELECT state=pg_temp.state_0135(true) FROM fixture_0135_before),'completion receipt, exact replay, or retained old facts drifted');
SELECT pg_temp.assert_0135((SELECT count(*) FROM app_private.personal_history_contribution_previews_v1)=(SELECT count(*) FROM fixture_0135_previews_before)
  AND NOT EXISTS(SELECT 1 FROM fixture_0135_previews_before old JOIN app_private.personal_history_contribution_previews_v1 current USING(preview_id)
    WHERE to_jsonb(current) IS DISTINCT FROM CASE WHEN old.preview_id IN(SELECT preview_id FROM fixture_0135_paths WHERE kind<>'other-actor')
      THEN to_jsonb(old)||jsonb_build_object('actor_app_user_id',NULL,'source_contact_id',NULL) ELSE to_jsonb(old) END)
  AND (SELECT count(*) FROM app_private.personal_history_contribution_confirmations_v1)=(SELECT count(*) FROM fixture_0135_confirmations_before)
  AND NOT EXISTS(SELECT 1 FROM fixture_0135_confirmations_before old JOIN app_private.personal_history_contribution_confirmations_v1 current USING(request_id)
    WHERE to_jsonb(current) IS DISTINCT FROM CASE WHEN old.request_id IN(SELECT request_id FROM fixture_0135_paths WHERE kind<>'other-actor')
      THEN to_jsonb(old)||jsonb_build_object('actor_app_user_id',NULL,'source_contact_id',NULL) ELSE to_jsonb(old) END),
  'unlink changed metadata, missed a one-sided reference, or touched another actor');
SELECT pg_temp.expect_0135_failure('55000',NULL,
  'UPDATE app_private.account_history_contribution_unlink_completions_v1 SET unlinked_at_utc=unlinked_at_utc');
SELECT pg_temp.expect_0135_failure('55000',NULL,'DELETE FROM app_private.account_history_contribution_unlink_completions_v1');
SAVEPOINT residual_provenance;
INSERT INTO app_private.personal_history_contribution_previews_v1(preview_id,actor_app_user_id,source_contact_id,source_revision_number,target_project_id,issued_at_utc,expires_at_utc)
SELECT gen_random_uuid(),actor.app_user_id,'0135-unused-source',1,org.project_id,boundary.at,boundary.at+interval '15 minutes'
FROM fixture_0135_actor actor,fixture_0135_org org,(SELECT clock_timestamp() AS at) boundary WHERE org.kind='first';
SELECT pg_temp.expect_0135_failure('55000','account history contribution unlink unavailable',
  'SELECT * FROM app_private.unlink_due_account_history_contributions_v1((SELECT app_user_id FROM fixture_0135_actor),(SELECT deletion_request_id FROM fixture_0135_cycle))');
ROLLBACK TO residual_provenance;

CREATE TEMP TABLE fixture_0135_empty_cycle AS SELECT receipt.* FROM fixture_0135_empty actor,
  LATERAL app_private.request_account_deletion_v1(actor.app_user_id,gen_random_uuid()) receipt;
SET LOCAL session_replication_role=replica;
UPDATE app_private.account_deletion_current SET effective_at_utc=boundary.at-interval '720 hours',purge_after_utc=boundary.at
FROM(SELECT clock_timestamp() AS at) boundary WHERE app_user_id=(SELECT app_user_id FROM fixture_0135_empty);
UPDATE app_private.account_deletion_request_claims claim SET effective_at_utc=attempt.effective_at_utc,purge_after_utc=attempt.purge_after_utc
FROM app_private.account_deletion_current attempt WHERE claim.request_id=attempt.deletion_request_id AND attempt.app_user_id=(SELECT app_user_id FROM fixture_0135_empty);
SET LOCAL session_replication_role=origin;
CREATE TEMP TABLE fixture_0135_empty_completed AS SELECT receipt.* FROM fixture_0135_empty actor,fixture_0135_empty_cycle cycle,
  LATERAL app_private.unlink_due_account_history_contributions_v1(actor.app_user_id,cycle.deletion_request_id) receipt;
SELECT pg_temp.assert_0135((SELECT count(*)=1 FROM fixture_0135_empty_completed),'empty contribution set did not complete');

-- Organization purge still removes the unlinked graph; the personal sources and other organization remain.
CREATE TEMP TABLE fixture_0135_sources_preserved AS SELECT to_jsonb(t) AS value FROM app_data.contacts t WHERE contact_id LIKE '0135-%';
CREATE TEMP TABLE fixture_0135_other_preserved AS SELECT to_jsonb(t) AS value FROM app_private.organization_historical_contact_copies_v1 t
  WHERE target_project_id=(SELECT project_id FROM fixture_0135_org WHERE kind='second');
CREATE TEMP TABLE fixture_0135_org_cycle AS SELECT receipt.* FROM fixture_0135_owner owner,fixture_0135_org org,
  LATERAL app_private.request_organization_deletion_v1(owner.app_user_id,gen_random_uuid(),org.organization_workspace_id) receipt WHERE org.kind='first';
SET LOCAL session_replication_role=replica;
UPDATE app_private.organization_deletion_current SET effective_at_utc=transaction_timestamp()-interval '721 hours',purge_after_utc=transaction_timestamp()-interval '1 hour'
WHERE organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0135_org WHERE kind='first');
UPDATE app_private.organization_deletion_request_claims claim SET effective_at_utc=attempt.effective_at_utc,purge_after_utc=attempt.purge_after_utc
FROM app_private.organization_deletion_current attempt WHERE claim.request_id=attempt.deletion_request_id
  AND attempt.organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0135_org WHERE kind='first');
UPDATE app_private.organization_deletion_audit_events audit SET occurred_at_utc=attempt.effective_at_utc
FROM app_private.organization_deletion_current attempt WHERE audit.request_id=attempt.deletion_request_id
  AND attempt.organization_workspace_id=(SELECT organization_workspace_id FROM fixture_0135_org WHERE kind='first');
UPDATE app_data.workspaces workspace SET deleted_at=attempt.effective_at_utc FROM app_private.organization_deletion_current attempt
WHERE workspace.workspace_id=attempt.organization_workspace_id AND workspace.workspace_id=(SELECT organization_workspace_id FROM fixture_0135_org WHERE kind='first');
SET LOCAL session_replication_role=origin;
SELECT * FROM app_private.finalize_organization_purge_v1((SELECT organization_workspace_id FROM fixture_0135_org WHERE kind='first'),(SELECT deletion_request_id FROM fixture_0135_org_cycle));
SELECT pg_temp.assert_0135(NOT EXISTS(SELECT 1 FROM app_private.personal_history_contribution_previews_v1 WHERE target_project_id=(SELECT project_id FROM fixture_0135_org WHERE kind='first'))
  AND NOT EXISTS(SELECT 1 FROM app_private.personal_history_contribution_confirmations_v1 WHERE target_project_id=(SELECT project_id FROM fixture_0135_org WHERE kind='first'))
  AND NOT EXISTS(SELECT 1 FROM app_private.organization_historical_contact_copies_v1 WHERE target_project_id=(SELECT project_id FROM fixture_0135_org WHERE kind='first'))
  AND NOT EXISTS(SELECT value FROM fixture_0135_sources_preserved EXCEPT SELECT to_jsonb(t) FROM app_data.contacts t)
  AND NOT EXISTS(SELECT value FROM fixture_0135_other_preserved EXCEPT SELECT to_jsonb(t) FROM app_private.organization_historical_contact_copies_v1 t),
  'organization purge retained unlinked dependencies or changed preserved sources and copies');
SELECT pg_temp.assert_0135(NOT has_function_privilege('tongxingzhe_runtime','app_private.unlink_due_account_history_contributions_v1(uuid,uuid)','EXECUTE')
  AND NOT has_function_privilege('public','app_private.unlink_due_account_history_contributions_v1(uuid,uuid)','EXECUTE'),'unlink is executable by runtime or PUBLIC');
SET LOCAL ROLE tongxingzhe_runtime;
DO $acl$
DECLARE actual_state text;
BEGIN
  BEGIN PERFORM * FROM app_private.account_history_contribution_unlink_completions_v1;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  IF actual_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '0135 runtime read completion ledger'; END IF;
END
$acl$;
RESET ROLE;
ROLLBACK;
