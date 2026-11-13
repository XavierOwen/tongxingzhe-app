\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL timezone='UTC';

CREATE TEMP TABLE retention_calendar_context ON COMMIT DROP AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://0153-retention-calendar.example.test/auth/v1','0153-retention-calendar-owner'
);
CREATE TEMP TABLE retention_calendar_targets ON COMMIT DROP AS
SELECT names.name,(created.target->>'target_id')::uuid AS target_id
FROM retention_calendar_context c
CROSS JOIN (VALUES ('normal'),('near'),('far'),('boundary')) names(name)
CROSS JOIN LATERAL app_data.create_promotion_target(
  c.app_user_id,c.workspace_id,c.project_id,'person','0153 calendar '||names.name,
  NULL,NULL,'0153-retention-calendar-'||names.name
) created;
SELECT app_data.configure_promotion_target_retention_policy(c.app_user_id,c.workspace_id,c.project_id,6)
FROM retention_calendar_context c;

-- The normal creation/policy path must describe the same instant in every session zone.
DO $normal_caller$
DECLARE zone text; target_id uuid; expected timestamptz;
BEGIN
  SELECT t.target_id,((p.created_at AT TIME ZONE 'UTC')+interval '6 months') AT TIME ZONE 'UTC'
  INTO STRICT target_id,expected FROM retention_calendar_targets t
  JOIN app_data.promotion_targets p ON p.promotion_target_id=t.target_id WHERE t.name='normal';
  FOREACH zone IN ARRAY ARRAY['UTC','America/New_York','America/Los_Angeles','Asia/Kolkata','Pacific/Kiritimati','Pacific/Honolulu'] LOOP
    PERFORM set_config('TimeZone',zone,true);
    IF app_data.promotion_target_review_due_at(target_id) IS DISTINCT FROM expected
    THEN RAISE EXCEPTION 'normal retention deadline changed in session zone %',zone; END IF;
  END LOOP;
END
$normal_caller$;

SET LOCAL timezone='America/New_York';
CREATE TEMP TABLE retention_calendar_renewal ON COMMIT DROP AS
SELECT action.result FROM retention_calendar_context c
JOIN retention_calendar_targets t ON t.name='normal'
CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,'renew','purpose_confirmed','0153-calendar-renewal'
) action;
SET LOCAL timezone='Pacific/Kiritimati';
CREATE TEMP TABLE retention_calendar_replay ON COMMIT DROP AS
SELECT action.result FROM retention_calendar_context c
JOIN retention_calendar_targets t ON t.name='normal'
CROSS JOIN LATERAL app_data.apply_promotion_target_retention_action(
  c.app_user_id,c.workspace_id,c.project_id,t.target_id,'renew','purpose_confirmed','0153-calendar-renewal'
) action;
DO $renewal$
DECLARE event app_data.promotion_target_retention_events%ROWTYPE; accepted jsonb; replayed jsonb;
BEGIN
  SELECT * INTO STRICT event FROM app_data.promotion_target_retention_events
  WHERE mutation_id='0153-calendar-renewal' AND actor_app_user_id=(SELECT app_user_id FROM retention_calendar_context);
  SELECT result INTO STRICT accepted FROM retention_calendar_renewal;
  SELECT result INTO STRICT replayed FROM retention_calendar_replay;
  IF event.review_due_at IS DISTINCT FROM
      ((event.occurred_at AT TIME ZONE 'UTC')+interval '6 months') AT TIME ZONE 'UTC'
    OR (accepted->>'review_due_at')::timestamptz IS DISTINCT FROM event.review_due_at
    OR app_data.promotion_target_review_due_at(event.promotion_target_id) IS DISTINCT FROM event.review_due_at
    OR (accepted->>'duplicate')::boolean IS DISTINCT FROM false
    OR (replayed->>'duplicate')::boolean IS DISTINCT FROM true
    OR (replayed->>'review_due_at')::timestamptz IS DISTINCT FROM event.review_due_at
    OR (SELECT count(*) FROM app_data.promotion_target_retention_events
      WHERE promotion_target_id=event.promotion_target_id)<>1
  THEN RAISE EXCEPTION 'non-UTC renewal, current deadline or cross-zone exact replay changed its instant'; END IF;
END
$renewal$;

-- Date changes are fixture setup only; policy and renewal writes use their real entry points.
SET LOCAL timezone='UTC';
UPDATE app_data.promotion_targets p
SET created_at=((clock_timestamp()+CASE t.name WHEN 'near' THEN interval '360 hours' ELSE interval '1080 hours' END)
  AT TIME ZONE 'UTC'-interval '6 months') AT TIME ZONE 'UTC'
FROM retention_calendar_targets t WHERE p.promotion_target_id=t.target_id AND t.name IN ('near','far');
CREATE TEMP TABLE retention_calendar_tasks(zone text,target_id uuid,due_at timestamptz) ON COMMIT DROP;
DO $task_zones$
DECLARE session_zone text; c record;
BEGIN
  SELECT * INTO STRICT c FROM retention_calendar_context;
  FOREACH session_zone IN ARRAY ARRAY['UTC','America/New_York','Asia/Kolkata','Pacific/Kiritimati'] LOOP
    PERFORM set_config('TimeZone',session_zone,true);
    INSERT INTO retention_calendar_tasks
    SELECT session_zone,(task->>'target_id')::uuid,(task->>'review_due_at')::timestamptz
    FROM app_data.list_promotion_target_retention_tasks(c.app_user_id,c.workspace_id,c.project_id);
    IF (SELECT array_agg(target_id ORDER BY target_id) FROM retention_calendar_tasks WHERE retention_calendar_tasks.zone=session_zone)
      IS DISTINCT FROM ARRAY[(SELECT target_id FROM retention_calendar_targets WHERE name='near')]
    THEN RAISE EXCEPTION 'retention task near/far membership changed in zone %',session_zone; END IF;
  END LOOP;
  IF (SELECT count(DISTINCT due_at) FROM retention_calendar_tasks)<>1
    OR strpos(pg_get_functiondef('app_data.list_promotion_target_retention_tasks(uuid,uuid,uuid)'::regprocedure),
      $$clock_timestamp() + interval '720 hours'$$)=0
  THEN RAISE EXCEPTION 'retention tasks do not use one deadline and a continuous 720-hour horizon'; END IF;
END
$task_zones$;

DO $fixed_calendar_cases$
DECLARE zone text; sample record; c record; boundary_id uuid;
BEGIN
  SELECT * INTO STRICT c FROM retention_calendar_context;
  SELECT target_id INTO STRICT boundary_id FROM retention_calendar_targets WHERE name='boundary';
  FOR sample IN SELECT * FROM (VALUES
    ('leap month end',1,timestamptz '2024-01-31 00:00:00+00',timestamptz '2024-02-29 00:00:00+00'),
    ('leap annual clamp',12,timestamptz '2024-02-29 00:00:00+00',timestamptz '2025-02-28 00:00:00+00'),
    ('spring DST crossing',1,timestamptz '2024-02-15 12:30:00+00',timestamptz '2024-03-15 12:30:00+00'),
    ('autumn DST crossing',1,timestamptz '2024-10-15 12:30:00+00',timestamptz '2024-11-15 12:30:00+00'),
    ('east offset UTC month end',1,timestamptz '2024-02-01 00:30:00+14',timestamptz '2024-02-29 10:30:00+00'),
    ('west offset UTC next month',1,timestamptz '2024-01-31 23:30:00-10',timestamptz '2024-03-01 09:30:00+00')
  ) cases(label,months,reference_at,expected_due_at) LOOP
    UPDATE app_data.promotion_targets SET created_at=sample.reference_at WHERE promotion_target_id=boundary_id;
    PERFORM app_data.configure_promotion_target_retention_policy(c.app_user_id,c.workspace_id,c.project_id,sample.months);
    FOREACH zone IN ARRAY ARRAY['UTC','America/New_York','America/Los_Angeles','Asia/Kolkata','Pacific/Kiritimati','Pacific/Honolulu'] LOOP
      PERFORM set_config('TimeZone',zone,true);
      IF app_data.promotion_target_retention_reference_at(boundary_id) IS DISTINCT FROM sample.reference_at
        OR app_data.promotion_target_review_due_at(boundary_id) IS DISTINCT FROM sample.expected_due_at
      THEN RAISE EXCEPTION 'UTC calendar case % failed in zone %',sample.label,zone; END IF;
    END LOOP;
  END LOOP;
END
$fixed_calendar_cases$;
ROLLBACK;
