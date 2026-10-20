-- Synthetic retention regression. All ordinary and confirmed facts roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE FUNCTION pg_temp.assert_0139(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
  IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION '0139 %',label; END IF;
END $function$;
CREATE FUNCTION pg_temp.state_0139() RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE relation record; rows jsonb; document jsonb:='{}'::jsonb;
BEGIN
  FOR relation IN SELECT schemaname,tablename FROM pg_catalog.pg_tables WHERE schemaname IN('app_data','app_private') ORDER BY schemaname,tablename LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t',relation.schemaname,relation.tablename) INTO rows;
    document:=document||jsonb_build_object(relation.schemaname||'.'||relation.tablename,rows);
  END LOOP;
  RETURN document;
END $function$;
CREATE TEMP TABLE fixture_0139_context AS SELECT * FROM app_data.bootstrap_personal_context('https://synthetic-0139.example.test','owner');
SELECT count(*) FROM app_data.list_personal_project_contexts('https://synthetic-0139.example.test','owner') WHERE is_current;
CREATE TEMP TABLE fixture_0139_targets(label text PRIMARY KEY,target_id uuid);
DO $targets$
DECLARE c record; label text; id uuid;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  FOREACH label IN ARRAY ARRAY['ordinary','first','second','unrelated'] LOOP
    SELECT (target->>'target_id')::uuid INTO STRICT id FROM app_data.create_promotion_target(c.app_user_id,c.workspace_id,c.project_id,
      'person','0139 original '||label,'+1 312 555 0139',label||'@0139.example.test','0139-create-'||label);
    INSERT INTO fixture_0139_targets VALUES(label,id);
  END LOOP;
END $targets$;
DO $entries$
DECLARE c record; target record; code text; contact text;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  FOR target IN TABLE fixture_0139_targets LOOP
    contact:='0139-entry-'||target.label;
    SELECT result_code INTO STRICT code FROM app_data.apply_contact_submit_v3(c.app_user_id,contact||'-submit',1,'contact.submit.v1','0139-device',contact,0,
      jsonb_build_object('contactId',contact,'workspaceId',c.workspace_id,'projectId',c.project_id,'questionnaireVersionId',c.questionnaire_version_id,
        'reason','0139 real project entry','occurredAtUtc','2020-01-01T00:00:00Z','occurredTimeZone','UTC','channel','video_call',
        'location',jsonb_build_object('kind','not_applicable'),'reachCount',2,'interestLevel',3,'answers','[]'::jsonb,
        'targetLinks',jsonb_build_array(jsonb_build_object('targetId',target.target_id,'targetType','person','responseLevel',2,
          'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true))));
    PERFORM pg_temp.assert_0139(code='accepted','ordinary contact did not create a real initial relationship');
  END LOOP;
END $entries$;
SELECT pg_temp.assert_0139(result->>'status'='accepted','ordinary other/detail was not accepted')
FROM fixture_0139_context c,fixture_0139_targets t,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  t.target_id,1,1,'active','0139-private-ordinary-note','other','0139-private-other-ordinary','0139-ordinary-other',NULL) updated WHERE t.label='ordinary';
SELECT pg_temp.assert_0139(result->>'status'='accepted','ordinary non-other/detail was not accepted')
FROM fixture_0139_context c,fixture_0139_targets t,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  t.target_id,2,2,'active','0139-private-nonother-note','progress_update','0139-private-nonother-detail','0139-ordinary-nonother',NULL) updated WHERE t.label='ordinary';
SELECT pg_temp.assert_0139(result->>'status'='conflict','ordinary stale update did not retain a real conflict')
FROM fixture_0139_context c,fixture_0139_targets t,LATERAL app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
  t.target_id,1,4,'active','0139-private-conflict-note','other','0139-private-conflict-detail','0139-ordinary-conflict',NULL) updated WHERE t.label='ordinary';
DO $missing_detail$
DECLARE before_state jsonb:=pg_temp.state_0139(); actual_state text; c record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  BEGIN
    PERFORM * FROM app_data.update_promotion_target_relationship(c.app_user_id,c.workspace_id,c.project_id,
      (SELECT target_id FROM fixture_0139_targets WHERE label='ordinary'),3,4,'active','0139 rejected note','other',NULL,'0139-missing-detail',NULL);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  PERFORM pg_temp.assert_0139(actual_state='22023' AND before_state=pg_temp.state_0139(),'missing other/detail was accepted or wrote persistent state');
END $missing_detail$;
CREATE TEMP TABLE fixture_0139_merge(generation_id uuid,request_id uuid,assignments jsonb,document jsonb,choices jsonb,ended_at timestamptz);
DO $confirm$
DECLARE c record; first_id uuid; second_id uuid; preview uuid; generation uuid; pending uuid; inventory jsonb; mapping jsonb; document jsonb; choices jsonb; request uuid:=gen_random_uuid(); ended timestamptz;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  SELECT target_id INTO STRICT first_id FROM fixture_0139_targets WHERE label='first';
  SELECT target_id INTO STRICT second_id FROM fixture_0139_targets WHERE label='second';
  SELECT preview_id INTO STRICT preview FROM app_data.preview_personal_target_pair_v1('https://synthetic-0139.example.test','owner',c.project_id,first_id,second_id);
  generation:=app_private.activate_personal_target_merge_generation_v2(c.app_user_id,c.project_id,gen_random_uuid(),preview,first_id,second_id,first_id,second_id);
  SELECT pending_fact_id INTO STRICT pending FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
    gen_random_uuid(),generation,3,'active',E'  0139-private-pending-note  ','other',E'  0139-private-other-confirmed\t');
  PERFORM * FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(c.app_user_id,c.workspace_id,c.project_id,
    gen_random_uuid(),generation,2,'paused','0139-private-unselected-note','progress_update','0139-private-unselected-detail');
  SELECT jsonb_agg(jsonb_build_object('pending_fact_id',header.pending_fact_id,'source_target_id',first_id) ORDER BY header.pending_fact_id)
    INTO mapping FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 header WHERE header.generation_id=generation;
  inventory:=app_private.read_personal_merge_unassigned_project_relationship_plan_v1(c.app_user_id,c.workspace_id,c.project_id,generation);
  document:=app_private.plan_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,c.project_id,generation,
    inventory->'known_source_plan'->>'fact_fingerprint',inventory->>'pending_fingerprint',mapping);
  choices:=jsonb_build_array(jsonb_build_object('project_id',c.project_id,'source_target_id',first_id,'candidate_kind','pending','pending_fact_id',pending));
  ended:=app_private.confirm_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,c.project_id,request,generation,
    document->'known_source_plan'->>'fact_fingerprint',document->>'pending_fingerprint',document->>'resolution_fingerprint',mapping,choices);
  INSERT INTO fixture_0139_merge VALUES(generation,request,mapping,document,choices,ended);
  PERFORM pg_temp.assert_0139(EXISTS(SELECT 1 FROM app_data.promotion_target_relationship_revisions
    WHERE promotion_target_id=first_id AND reason_code='other' AND reason_detail=E'  0139-private-other-confirmed\t'
      AND merge_generation_id=generation AND changed_fields=ARRAY['pending_source_assignment']::text[])
    AND NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 payload
      JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id) WHERE header.generation_id=generation),
    'real confirmation did not retain raw other history or consume project payload');
END $confirm$;
CREATE TEMP TABLE fixture_0139_before_revisions AS SELECT * FROM app_data.promotion_target_relationship_revisions;
CREATE TEMP TABLE fixture_0139_before_conflicts AS SELECT * FROM app_data.promotion_target_relationship_conflicts;
CREATE TEMP TABLE fixture_0139_before_relations AS SELECT * FROM app_data.promotion_target_project_relationships;
UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years'
WHERE promotion_target_id=(SELECT target_id FROM fixture_0139_targets WHERE label='ordinary');
CREATE TEMP TABLE fixture_0139_before_state AS SELECT pg_temp.state_0139() AS document;
CREATE TEMP TABLE fixture_0139_results(label text PRIMARY KEY,result jsonb);
INSERT INTO fixture_0139_results
SELECT t.label,action.result FROM fixture_0139_context c,fixture_0139_targets t,LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,'anonymize','retention_expired','0139-ordinary-due') action WHERE t.label='ordinary';
SELECT pg_temp.assert_0139(result->>'status'='anonymized' AND result->>'duplicate'='false','ordinary other history blocked due anonymization')
FROM fixture_0139_results WHERE label='ordinary';
CREATE FUNCTION pg_temp.fail_0139() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
  IF NEW.promotion_target_id=(SELECT target_id FROM fixture_0139_targets WHERE label='first') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='0139 injected retention event failure';
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER fixture_0139_late_failure BEFORE INSERT ON app_data.promotion_target_retention_events
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_0139();
DO $rollback$
DECLARE before_state jsonb:=pg_temp.state_0139(); actual_state text; c record;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  BEGIN
    PERFORM * FROM app_data.apply_promotion_target_retention_action(c.app_user_id,c.workspace_id,c.project_id,
      (SELECT target_id FROM fixture_0139_targets WHERE label='first'),'anonymize','withdrawal','0139-confirmed-withdrawal');
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE; END;
  PERFORM pg_temp.assert_0139(actual_state='P0001' AND before_state=pg_temp.state_0139(),'late failure did not roll back complete anonymization');
END $rollback$;
DROP TRIGGER fixture_0139_late_failure ON app_data.promotion_target_retention_events;
INSERT INTO fixture_0139_results
SELECT t.label,action.result FROM fixture_0139_context c,fixture_0139_targets t,LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,'anonymize','withdrawal','0139-confirmed-withdrawal') action WHERE t.label='first';
DO $redacted$
DECLARE old record; live jsonb; before_state jsonb:=(SELECT document FROM fixture_0139_before_state); after_state jsonb:=pg_temp.state_0139(); key text;
BEGIN
  FOR old IN TABLE fixture_0139_before_revisions LOOP
    SELECT to_jsonb(revision) INTO STRICT live FROM app_data.promotion_target_relationship_revisions revision
      WHERE revision.promotion_target_id=old.promotion_target_id AND revision.project_id=old.project_id AND revision.revision_number=old.revision_number;
    IF old.promotion_target_id IN(SELECT target_id FROM fixture_0139_targets WHERE label IN('ordinary','first')) THEN
      PERFORM pg_temp.assert_0139(live-'follow_up_note'-'requested_follow_up_note'-'reason_detail'=to_jsonb(old)-'follow_up_note'-'requested_follow_up_note'-'reason_detail'
        AND live->>'follow_up_note' IS NULL AND live->>'requested_follow_up_note' IS NULL
        AND (live->>'reason_detail') IS NOT DISTINCT FROM CASE WHEN old.reason_code='other' THEN '[已匿名化]' ELSE NULL END,
        'redaction changed revision keys, reason, stage, lifecycle, actor, time, binding, or retained sensitive text');
    ELSE PERFORM pg_temp.assert_0139(live=to_jsonb(old),'redaction changed an unrelated revision'); END IF;
  END LOOP;
  FOR old IN TABLE fixture_0139_before_relations LOOP
    SELECT to_jsonb(parent) INTO STRICT live FROM app_data.promotion_target_project_relationships parent
      WHERE parent.promotion_target_id=old.promotion_target_id AND parent.project_id=old.project_id;
    IF old.promotion_target_id IN(SELECT target_id FROM fixture_0139_targets WHERE label IN('ordinary','first')) THEN
      PERFORM pg_temp.assert_0139(live-'current_lifecycle_status'-'current_follow_up_note'-'current_revision'-'updated_by_app_user_id'-'updated_at'
        =to_jsonb(old)-'current_lifecycle_status'-'current_follow_up_note'-'current_revision'-'updated_by_app_user_id'-'updated_at'
        AND (live->>'current_revision')::integer=old.current_revision+1,'anonymization changed parent stage, binding, identity, or initial provenance');
    ELSE PERFORM pg_temp.assert_0139(live=to_jsonb(old),'anonymization changed an unrelated parent'); END IF;
  END LOOP;
  FOR old IN TABLE fixture_0139_before_conflicts LOOP
    SELECT to_jsonb(conflict) INTO STRICT live FROM app_data.promotion_target_relationship_conflicts conflict WHERE conflict.conflict_id=old.conflict_id;
    IF old.promotion_target_id=(SELECT target_id FROM fixture_0139_targets WHERE label='ordinary') THEN
      PERFORM pg_temp.assert_0139(live-'proposed_follow_up_note'-'proposed_reason_detail'=to_jsonb(old)-'proposed_follow_up_note'-'proposed_reason_detail'
        AND live->>'proposed_follow_up_note' IS NULL AND live->>'proposed_reason_detail' IS NULL,'conflict redaction retained detail or changed provenance');
    ELSE PERFORM pg_temp.assert_0139(live=to_jsonb(old),'redaction changed an unrelated conflict'); END IF;
  END LOOP;
  PERFORM pg_temp.assert_0139((SELECT count(*)=2 AND bool_and(status='anonymized' AND phone IS NULL AND email IS NULL AND display_name='已匿名化对象')
    FROM app_data.promotion_targets WHERE promotion_target_id IN(SELECT target_id FROM fixture_0139_targets WHERE label IN('ordinary','first')))
    AND NOT EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships
      WHERE promotion_target_id IN(SELECT target_id FROM fixture_0139_targets WHERE label IN('ordinary','first'))
        AND (current_lifecycle_status<>'ended' OR current_follow_up_note IS NOT NULL)),'ordinary or confirmed anonymization left current PII');
  FOR key IN SELECT jsonb_object_keys(before_state) LOOP
    IF key=ANY(ARRAY['app_data.promotion_targets','app_data.promotion_target_assignments','app_data.promotion_target_project_relationships',
      'app_data.promotion_target_relationship_revisions','app_data.promotion_target_relationship_conflicts','app_data.promotion_target_retention_events',
      'app_private.personal_target_merge_generation_fence_v1']) THEN CONTINUE; END IF;
    PERFORM pg_temp.assert_0139(before_state->key=after_state->key,'anonymization changed contacts, links, headers, resolution metadata, or unrelated table '||key);
  END LOOP;
  FOREACH key IN ARRAY ARRAY['app_data.promotion_targets','app_data.promotion_target_assignments','app_data.promotion_target_project_relationships'] LOOP
    PERFORM pg_temp.assert_0139((SELECT coalesce(jsonb_agg(value ORDER BY value::text),'[]'::jsonb) FROM jsonb_array_elements(before_state->key) value
      WHERE value->>'promotion_target_id' NOT IN(SELECT target_id::text FROM fixture_0139_targets WHERE label IN('ordinary','first')))
      =(SELECT coalesce(jsonb_agg(value ORDER BY value::text),'[]'::jsonb) FROM jsonb_array_elements(after_state->key) value
      WHERE value->>'promotion_target_id' NOT IN(SELECT target_id::text FROM fixture_0139_targets WHERE label IN('ordinary','first'))),
      'anonymization changed another target, assignment, or project relationship');
  END LOOP;
  FOR key IN SELECT value FROM jsonb_object_keys(after_state) keys(value) WHERE value LIKE 'app_private.%' LOOP
    PERFORM pg_temp.assert_0139(position('0139-private-' IN (after_state->key)::text)=0,'private metadata retained original note or detail');
  END LOOP;
END $redacted$;
DO $export$
DECLARE c record; exported text;
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  exported:=convert_from(app_data.prepare_personal_target_pii_export_v1('https://synthetic-0139.example.test','owner',c.project_id,transaction_timestamp()),'UTF8');
  PERFORM pg_temp.assert_0139(position('0139-private-' IN exported)=0 AND position('0139 original ordinary' IN exported)=0
    AND position('0139 original first' IN exported)=0,'PII export retained anonymized originals');
END $export$;
DO $replay$
DECLARE c record; target record; result jsonb; receipt record; before_state jsonb:=pg_temp.state_0139();
BEGIN
  SELECT * INTO STRICT c FROM fixture_0139_context;
  FOR target IN SELECT * FROM fixture_0139_targets WHERE label IN('ordinary','first') LOOP
    SELECT action.result INTO STRICT result FROM app_data.apply_promotion_target_retention_action(c.app_user_id,c.workspace_id,c.project_id,target.target_id,'anonymize',
      CASE target.label WHEN 'ordinary' THEN 'retention_expired' ELSE 'withdrawal' END,
      CASE target.label WHEN 'ordinary' THEN '0139-ordinary-due' ELSE '0139-confirmed-withdrawal' END) action;
    PERFORM pg_temp.assert_0139(result->>'duplicate'='true' AND result->>'status'='anonymized','exact replay did not return original anonymized status');
  END LOOP;
  SELECT * INTO STRICT receipt FROM fixture_0139_merge;
  PERFORM pg_temp.assert_0139(app_private.confirm_personal_merge_project_relationship_resolutions_v1(c.app_user_id,c.workspace_id,c.project_id,
    receipt.request_id,receipt.generation_id,receipt.document->'known_source_plan'->>'fact_fingerprint',receipt.document->>'pending_fingerprint',
    receipt.document->>'resolution_fingerprint',receipt.assignments,receipt.choices)=receipt.ended_at,'confirmed resolution replay returned a new end receipt');
  PERFORM pg_temp.assert_0139(before_state=pg_temp.state_0139(),'exact replay restored redacted text or changed retained facts');
END $replay$;
ROLLBACK;

