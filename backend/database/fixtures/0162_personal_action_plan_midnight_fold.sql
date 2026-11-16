\set ON_ERROR_STOP on
\ir shared/database_state.sql
BEGIN;
SET LOCAL TIME ZONE 'UTC';

-- The first repeated midnight hour must already belong to the new weekly cycle.
DO $first_fold_creation$
DECLARE c record; document jsonb; effective timestamptz; reference_at timestamptz := '2026-11-01 04:30+00';
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0162.example.test','first-midnight-fold');
  PERFORM app_data.list_personal_project_contexts('https://synthetic-0162.example.test','first-midnight-fold');
  document := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,'America/Havana',7,'create',reference_at);
  SELECT version.effective_from_utc INTO STRICT effective FROM app_data.personal_action_plans plan
    JOIN app_data.personal_action_plan_versions version USING(plan_id)
    WHERE plan.app_user_id=c.app_user_id AND version.revision_number=1;
  IF document IS NULL OR jsonb_typeof(document) IS DISTINCT FROM 'object' OR effective>reference_at
    OR (document#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-01 04:00+00'
    OR (document#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-08 05:00+00'
  THEN RAISE EXCEPTION '0162 first midnight-fold creation returned NULL or a cycle outside the reference: document=%, effective=%, reference=%',document,effective,reference_at; END IF;
END
$first_fold_creation$;

DO $casey_repeated_date$
DECLARE c record; saved jsonb; document jsonb; reference_at timestamptz := timestamptz '2010-03-04 15:30Z';
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0162.example.test','casey-repeated-date');
  PERFORM app_data.list_personal_project_contexts('https://synthetic-0162.example.test','casey-repeated-date');
  saved := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,'Antarctica/Casey',5,'create',reference_at);
  FOREACH document IN ARRAY ARRAY[saved,app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,reference_at)] LOOP
    IF document IS NULL OR (document#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM timestamptz '2010-03-04 13:00Z'
      OR (document#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM timestamptz '2010-03-11 16:00Z'
      OR (document#>>'{progress,cycle_start_utc}')::timestamptz>reference_at
      OR (document#>>'{progress,cycle_until_utc}')::timestamptz<=reference_at THEN
      RAISE EXCEPTION '0162 Casey repeated local date returned an ended cycle for ordinary save/read: %',document;
    END IF;
  END LOOP;
END
$casey_repeated_date$;

DO $cycle_boundaries$
DECLARE item record; session_zone text; actual_start timestamptz; actual_until timestamptz; previous_start timestamptz;
BEGIN
  FOREACH session_zone IN ARRAY ARRAY['UTC','America/Chicago','Pacific/Auckland'] LOOP
    PERFORM set_config('TimeZone',session_zone,true);
    FOR item IN SELECT * FROM (VALUES
      ('America/Havana',7,timestamptz '2026-11-01 04:30Z',timestamptz '2026-11-01 04:00Z',timestamptz '2026-11-08 05:00Z'),
      ('America/Havana',7,timestamptz '2026-11-01 05:30Z',timestamptz '2026-11-01 04:00Z',timestamptz '2026-11-08 05:00Z'),
      ('Antarctica/Casey',5,timestamptz '2010-03-04 13:30Z',timestamptz '2010-03-04 13:00Z',timestamptz '2010-03-11 16:00Z'),
      ('Antarctica/Casey',5,timestamptz '2010-03-04 15:30Z',timestamptz '2010-03-04 13:00Z',timestamptz '2010-03-11 16:00Z'),
      ('Antarctica/Casey',5,timestamptz '2010-03-04 16:30Z',timestamptz '2010-03-04 13:00Z',timestamptz '2010-03-11 16:00Z'),
      ('UTC',7,timestamptz '2026-11-01 04:30Z',timestamptz '2026-11-01 00:00Z',timestamptz '2026-11-08 00:00Z'),
      ('America/Chicago',1,timestamptz '2030-03-09 18:00Z',timestamptz '2030-03-04 06:00Z',timestamptz '2030-03-11 05:00Z'),
      ('America/Havana',7,timestamptz '2026-03-08 06:30Z',timestamptz '2026-03-08 05:00Z',timestamptz '2026-03-15 04:00Z')
    ) AS cases(zone,week_day,reference,expected_start,expected_until) LOOP
      actual_start := app_data.personal_action_plan_cycle_start(item.reference,item.zone,item.week_day);
      actual_until := app_data.personal_action_plan_cycle_until(actual_start,item.zone);
      previous_start := app_data.personal_action_plan_cycle_start(item.reference-interval '168 hours',item.zone,item.week_day);
      IF actual_start IS DISTINCT FROM item.expected_start OR actual_until IS DISTINCT FROM item.expected_until
        OR actual_start>item.reference OR actual_until<=item.reference
        OR app_data.personal_action_plan_cycle_until(previous_start,item.zone) IS DISTINCT FROM actual_start
        OR app_data.personal_action_plan_cycle_start(actual_until,item.zone,item.week_day) IS DISTINCT FROM actual_until THEN
        RAISE EXCEPTION '0162 cycle boundary differs or overlaps: session %, case %',session_zone,to_jsonb(item);
      END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('TimeZone','UTC',true);
END
$cycle_boundaries$;

DO $ordinary_progress$
DECLARE c record; occurred timestamptz; result record; document jsonb; before_replay jsonb; scheduled jsonb;
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0162.example.test','first-midnight-fold');
  FOREACH occurred IN ARRAY ARRAY[timestamptz '2026-11-01 04:10Z',timestamptz '2026-11-01 05:10Z'] LOOP
    SELECT * INTO STRICT result FROM app_data.apply_contact_submit_v3(c.app_user_id,'0162-contact-'||extract(epoch FROM occurred),1,
      'contact.submit.v1','0162-device','0162-contact-'||extract(epoch FROM occurred),0,
      jsonb_build_object('contactId','0162-contact-'||extract(epoch FROM occurred),'workspaceId',c.workspace_id,'projectId',c.project_id,
        'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc',occurred,'occurredTimeZone','America/Havana','channel','video_call',
        'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));
    IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0162 ordinary fold contact submit failed: %',result.result_code; END IF;
  END LOOP;
  FOREACH occurred IN ARRAY ARRAY[timestamptz '2026-11-01 04:30Z',timestamptz '2026-11-01 05:30Z'] LOOP
    document := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,occurred);
    IF document IS NULL OR (document#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-01 04:00Z'
      OR (document#>>'{progress,recorded_contact_sessions}')::integer IS DISTINCT FROM (CASE WHEN occurred=timestamptz '2026-11-01 04:30Z' THEN 1 ELSE 2 END) THEN
      RAISE EXCEPTION '0162 ordinary progress lost a contact in the repeated first hour: %',document;
    END IF;
  END LOOP;
  scheduled := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,5,'America/Havana',7,'change',timestamptz '2026-11-01 04:30Z');
  IF scheduled#>>'{current,weekly_contact_target}' IS DISTINCT FROM '3'
    OR scheduled#>>'{pending,weekly_contact_target}' IS DISTINCT FROM '5'
    OR (scheduled#>>'{pending,effective_from_utc}')::timestamptz IS DISTINCT FROM timestamptz '2026-11-08 05:00Z' THEN
    RAISE EXCEPTION '0162 fold change did not retain the next-cycle version policy: %',scheduled;
  END IF;
  before_replay := pg_temp.fixture_database_state();
  document := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,5,'America/Havana',7,'change',timestamptz '2026-11-01 04:30Z');
  IF document IS DISTINCT FROM (scheduled||jsonb_build_object('duplicate',true))
    OR pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN
    RAISE EXCEPTION '0162 same-payload replay changed the pending version or database';
  END IF;
END
$ordinary_progress$;
ROLLBACK;
SELECT 'personal action plan midnight folds, calendar adjacency, and ordinary progress: passed' AS result;
SELECT 'personal action plan midnight-fold initial creation: passed' AS result;
