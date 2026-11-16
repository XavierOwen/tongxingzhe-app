\set ON_ERROR_STOP on
\ir shared/database_state.sql
BEGIN;
SET LOCAL TIME ZONE 'UTC';

DO $ordinary_skipped_date$
DECLARE c record; initial jsonb; scheduled jsonb; following jsonb; reference_at timestamptz := timestamptz '2011-12-31 00:00Z';
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0163.example.test','skipped-friday');
  PERFORM app_data.list_personal_project_contexts('https://synthetic-0163.example.test','skipped-friday');
  initial := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,'Pacific/Apia',5,'create',reference_at);
  scheduled := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,4,'Pacific/Apia',5,'change',reference_at+interval '1 hour');
  following := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,timestamptz '2012-01-05 12:00Z');
  IF initial IS NULL OR scheduled IS NULL OR following IS NULL
    OR (initial#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM timestamptz '2012-01-05 10:00Z'
    OR (scheduled#>>'{pending,effective_from_utc}')::timestamptz IS DISTINCT FROM timestamptz '2012-01-05 10:00Z'
    OR following#>>'{current,weekly_contact_target}' IS DISTINCT FROM '4'
    OR (initial#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM (following#>>'{progress,cycle_start_utc}')::timestamptz THEN
    RAISE EXCEPTION '0163 ordinary skipped-Friday cycle overlaps or delays the next goal: initial=%, scheduled=%, following=%',initial,scheduled,following;
  END IF;
END
$ordinary_skipped_date$;

CREATE TEMP TABLE fixture_0163_cycles(name text,zone text,weekday integer,reference_at timestamptz,expected_start timestamptz,expected_until timestamptz) ON COMMIT DROP;
INSERT INTO fixture_0163_cycles VALUES
  ('apia-friday','Pacific/Apia',5,'2011-12-31 00:00Z','2011-12-30 10:00Z','2012-01-05 10:00Z'),
  ('apia-saturday','Pacific/Apia',6,'2011-12-31 00:00Z','2011-12-30 10:00Z','2012-01-06 10:00Z'),
  ('utc-friday','UTC',5,'2011-12-31 00:00Z','2011-12-30 00:00Z','2012-01-06 00:00Z'),
  ('havana-fold','America/Havana',7,'2025-11-02 04:30Z','2025-11-02 04:00Z','2025-11-09 05:00Z'),
  ('casey-fold','Antarctica/Casey',5,'2010-03-04 15:30Z','2010-03-04 13:00Z','2010-03-11 16:00Z'),
  ('chicago-dst','America/Chicago',1,'2030-03-09 18:00Z','2030-03-04 06:00Z','2030-03-11 05:00Z'),
  ('havana-gap','America/Havana',7,'2025-03-09 06:30Z','2025-03-09 05:00Z','2025-03-16 04:00Z');
CREATE TEMP TABLE fixture_0163_replays(name text,context jsonb,document jsonb) ON COMMIT DROP;
DO $ordinary_cycles$
DECLARE item record; c record; initial jsonb; scheduled jsonb; document jsonb; event record; result record;
BEGIN
  FOR item IN TABLE fixture_0163_cycles LOOP
    SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0163.example.test',item.name);
    PERFORM app_data.list_personal_project_contexts('https://synthetic-0163.example.test',item.name);
    initial := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,item.zone,item.weekday,'create',item.reference_at);
    scheduled := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,4,item.zone,item.weekday,'change',item.reference_at+interval '1 hour');
    IF initial IS NULL OR scheduled IS NULL
      OR (initial#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM item.expected_start
      OR (initial#>>'{progress,cycle_until_utc}')::timestamptz IS DISTINCT FROM item.expected_until
      OR (scheduled#>>'{pending,effective_from_utc}')::timestamptz IS DISTINCT FROM item.expected_until
      OR scheduled#>>'{current,weekly_contact_target}' IS DISTINCT FROM '3' THEN
      RAISE EXCEPTION '0163 ordinary cycle or next-goal version differs: %, %, %',item.name,initial,scheduled;
    END IF;
    FOR event IN SELECT * FROM (VALUES ('before',item.expected_until-interval '1 second'),('at',item.expected_until),
      ('after',item.expected_until+interval '1 microsecond')) AS events(name,occurred_at) LOOP
      SELECT * INTO STRICT result FROM app_data.apply_contact_submit_v3(c.app_user_id,'0163-'||item.name||'-'||event.name,1,
        'contact.submit.v1','0163-device','0163-'||item.name||'-'||event.name,0,
        jsonb_build_object('contactId','0163-'||item.name||'-'||event.name,'workspaceId',c.workspace_id,'projectId',c.project_id,
          'questionnaireVersionId',c.questionnaire_version_id,'occurredAtUtc',event.occurred_at,'occurredTimeZone',item.zone,'channel','video_call',
          'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));
      IF result.result_code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0163 ordinary boundary contact was not accepted: %',item.name; END IF;
    END LOOP;
    document := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,item.expected_until-interval '1 microsecond');
    IF document#>>'{progress,recorded_contact_sessions}' IS DISTINCT FROM '1'
      OR document#>>'{current,weekly_contact_target}' IS DISTINCT FROM '3' THEN
      RAISE EXCEPTION '0163 last cycle lost its boundary contact or activated the goal early: %, %',item.name,document;
    END IF;
    document := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,item.expected_until);
    IF (document#>>'{progress,cycle_start_utc}')::timestamptz IS DISTINCT FROM item.expected_until
      OR document#>>'{progress,recorded_contact_sessions}' IS DISTINCT FROM '0'
      OR document#>>'{current,weekly_contact_target}' IS DISTINCT FROM '4' THEN
      RAISE EXCEPTION '0163 adjacent cycle or goal did not start at the configured boundary: %, %',item.name,document;
    END IF;
    document := app_data.read_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,item.expected_until+interval '1 second');
    IF document#>>'{progress,recorded_contact_sessions}' IS DISTINCT FROM '2' THEN
      RAISE EXCEPTION '0163 new cycle boundary contacts overlap or disappeared: %, %',item.name,document;
    END IF;
    INSERT INTO fixture_0163_replays VALUES(item.name,to_jsonb(c),scheduled);
  END LOOP;
END
$ordinary_cycles$;

DO $new_settings$
DECLARE c record; document jsonb;
BEGIN
  SELECT * INTO STRICT c FROM app_data.bootstrap_personal_context('https://synthetic-0163.example.test','new-settings');
  PERFORM app_data.list_personal_project_contexts('https://synthetic-0163.example.test','new-settings');
  PERFORM app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,0,3,'UTC',5,'create',timestamptz '2011-12-31 00:00Z');
  document := app_data.save_personal_action_plan(c.app_user_id,c.workspace_id,c.project_id,1,4,'Pacific/Apia',6,'change',timestamptz '2011-12-31 01:00Z');
  IF document#>>'{current,statistics_time_zone}' IS DISTINCT FROM 'UTC'
    OR document#>>'{current,week_start_iso_day}' IS DISTINCT FROM '5'
    OR document#>>'{pending,statistics_time_zone}' IS DISTINCT FROM 'Pacific/Apia'
    OR document#>>'{pending,week_start_iso_day}' IS DISTINCT FROM '6'
    OR (document#>>'{pending,effective_from_utc}')::timestamptz IS DISTINCT FROM timestamptz '2012-01-06 10:00Z' THEN
    RAISE EXCEPTION '0163 changed the existing next-cycle scheduling policy for requested new settings: %',document;
  END IF;
END
$new_settings$;

DO $time_zone_and_replay$
DECLARE item record; session_zone text; document jsonb; before_replay jsonb;
BEGIN
  FOREACH session_zone IN ARRAY ARRAY['UTC','America/Chicago','Pacific/Auckland'] LOOP
    PERFORM set_config('TimeZone',session_zone,true);
    FOR item IN TABLE fixture_0163_cycles LOOP
      IF app_private.personal_action_plan_cycle_until_v2(item.expected_start,item.zone,item.weekday) IS DISTINCT FROM item.expected_until THEN
        RAISE EXCEPTION '0163 configured-weekday boundary depends on session time zone: %, %',session_zone,item.name;
      END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('TimeZone','UTC',true);
  before_replay := pg_temp.fixture_database_state();
  FOR item IN SELECT cycle.*,replay.context,replay.document FROM fixture_0163_cycles cycle JOIN fixture_0163_replays replay USING(name) LOOP
    document := app_data.save_personal_action_plan((item.context->>'app_user_id')::uuid,(item.context->>'workspace_id')::uuid,
      (item.context->>'project_id')::uuid,1,4,item.zone,item.weekday,'change',item.reference_at+interval '1 hour');
    IF document IS DISTINCT FROM (item.document||jsonb_build_object('duplicate',true)) THEN
      RAISE EXCEPTION '0163 completed goal-change replay changed its original result: %',item.name;
    END IF;
  END LOOP;
  IF pg_temp.fixture_database_state() IS DISTINCT FROM before_replay THEN RAISE EXCEPTION '0163 completed replay wrote a plan or version'; END IF;
END
$time_zone_and_replay$;
ROLLBACK;
SELECT 'personal action plan skipped-date cycles, goal changes, boundary contacts, and controls: passed' AS result;
