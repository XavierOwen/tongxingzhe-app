BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE plan_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-plans.supabase.co/auth/v1',
  'synthetic-plans-primary'
);

CREATE TEMP TABLE plan_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-plans.supabase.co/auth/v1',
  'synthetic-plans-secondary'
);

CREATE TEMP TABLE plan_counted_contact AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM plan_primary_context),
  'plan-counted-contact-command',
  1,
  'contact.submit.v1',
  'synthetic-plan-device',
  'plan-counted-contact',
  0,
  jsonb_build_object(
    'contactId', 'plan-counted-contact',
    'workspaceId', (SELECT workspace_id FROM plan_primary_context),
    'projectId', (SELECT project_id FROM plan_primary_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM plan_primary_context),
    'occurredAtUtc', '2030-03-05T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 8,
    'interestLevel', 4,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE plan_attempt AS
SELECT *
FROM app_data.apply_contact_attempt_submit(
  (SELECT app_user_id FROM plan_primary_context),
  'plan-attempt-command',
  1,
  'contact.attempt.submit.v1',
  'synthetic-plan-device',
  'plan-attempt',
  0,
  jsonb_build_object(
    'attemptId', 'plan-attempt',
    'workspaceId', (SELECT workspace_id FROM plan_primary_context),
    'projectId', (SELECT project_id FROM plan_primary_context),
    'occurredAtUtc', '2030-03-06T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'voice_call',
    'channelDetail', NULL
  )
);

CREATE TEMP TABLE plan_voided_contact AS
SELECT *
FROM app_data.apply_contact_submit(
  (SELECT app_user_id FROM plan_primary_context),
  'plan-voided-contact-command',
  1,
  'contact.submit.v1',
  'synthetic-plan-device',
  'plan-voided-contact',
  0,
  jsonb_build_object(
    'contactId', 'plan-voided-contact',
    'workspaceId', (SELECT workspace_id FROM plan_primary_context),
    'projectId', (SELECT project_id FROM plan_primary_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM plan_primary_context),
    'occurredAtUtc', '2030-03-07T18:00:00.000Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'video_call',
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', 1,
    'interestLevel', 1,
    'answers', jsonb_build_array()
  )
);

CREATE TEMP TABLE plan_void_result AS
SELECT *
FROM app_data.apply_contact_void(
  (SELECT app_user_id FROM plan_primary_context),
  'plan-void-command',
  1,
  'contact.void.v1',
  'synthetic-plan-device',
  'plan-voided-contact',
  1,
  jsonb_build_object(
    'contactId', 'plan-voided-contact',
    'workspaceId', (SELECT workspace_id FROM plan_primary_context),
    'projectId', (SELECT project_id FROM plan_primary_context),
    'reason', 'Synthetic duplicate'
  )
);

CREATE TEMP TABLE plan_created AS
SELECT app_data.save_personal_action_plan(
  (SELECT app_user_id FROM plan_primary_context),
  (SELECT workspace_id FROM plan_primary_context),
  (SELECT project_id FROM plan_primary_context),
  0,
  3,
  'America/Chicago',
  1,
  'plan-create-1',
  '2030-03-09T18:00:00Z'
) AS document;

DO $fixture$
DECLARE
  created jsonb := (SELECT document FROM plan_created);
  replayed jsonb;
  scheduled jsonb;
  before_change jsonb;
  after_change jsonb;
BEGIN
  IF created->>'duplicate' <> 'false'
    OR created->>'accepted_revision' <> '1'
    OR created#>>'{current,weekly_contact_target}' <> '3'
    OR created#>>'{current,statistics_time_zone}' <> 'America/Chicago'
    OR created#>>'{progress,cycle_start_utc}' <>
      '2030-03-04T06:00:00+00:00'
    OR created#>>'{progress,cycle_until_utc}' <>
      '2030-03-11T05:00:00+00:00'
    OR created#>>'{progress,recorded_contact_sessions}' <> '1'
    OR created#>>'{progress,remaining_contact_sessions}' <> '2'
    OR extract(epoch FROM (
      (created#>>'{progress,cycle_until_utc}')::timestamptz
      - (created#>>'{progress,cycle_start_utc}')::timestamptz
    )) <> 167 * 60 * 60
  THEN
    RAISE EXCEPTION 'DST-safe initial personal plan is incorrect: %', created;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM plan_counted_contact WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM plan_attempt WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM plan_void_result WHERE result_code = 'accepted'
  ) THEN
    RAISE EXCEPTION 'plan contact boundary fixture was not accepted';
  END IF;

  SELECT app_data.save_personal_action_plan(
    (SELECT app_user_id FROM plan_primary_context),
    (SELECT workspace_id FROM plan_primary_context),
    (SELECT project_id FROM plan_primary_context),
    0, 3, 'America/Chicago', 1, 'plan-create-1',
    '2030-03-09T18:00:00Z'
  ) INTO replayed;
  IF replayed->>'duplicate' <> 'true'
    OR replayed->>'accepted_revision' <> '1'
  THEN
    RAISE EXCEPTION 'personal plan replay is not idempotent';
  END IF;

  SELECT app_data.save_personal_action_plan(
    (SELECT app_user_id FROM plan_primary_context),
    (SELECT workspace_id FROM plan_primary_context),
    (SELECT project_id FROM plan_primary_context),
    1, 4, 'Asia/Shanghai', 7, 'plan-update-2',
    '2030-03-09T18:00:00Z'
  ) INTO scheduled;
  IF scheduled->>'accepted_revision' <> '2'
    OR scheduled#>>'{current,revision}' <> '1'
    OR scheduled#>>'{pending,revision}' <> '2'
    OR scheduled#>>'{pending,effective_from_utc}' <>
      '2030-03-16T16:00:00+00:00'
  THEN
    RAISE EXCEPTION 'next-cycle personal plan change is incorrect: %', scheduled;
  END IF;

  SELECT app_data.read_personal_action_plan(
    (SELECT app_user_id FROM plan_primary_context),
    (SELECT workspace_id FROM plan_primary_context),
    (SELECT project_id FROM plan_primary_context),
    '2030-03-16T15:59:59Z'
  ) INTO before_change;
  SELECT app_data.read_personal_action_plan(
    (SELECT app_user_id FROM plan_primary_context),
    (SELECT workspace_id FROM plan_primary_context),
    (SELECT project_id FROM plan_primary_context),
    '2030-03-16T16:00:00Z'
  ) INTO after_change;
  IF before_change#>>'{current,revision}' <> '1'
    OR after_change#>>'{current,revision}' <> '2'
    OR after_change->'pending' <> 'null'::jsonb
    OR after_change#>>'{progress,cycle_start_utc}' <>
      '2030-03-16T16:00:00+00:00'
  THEN
    RAISE EXCEPTION 'plan version boundary is not half-open';
  END IF;

  BEGIN
    PERFORM app_data.save_personal_action_plan(
      (SELECT app_user_id FROM plan_primary_context),
      (SELECT workspace_id FROM plan_primary_context),
      (SELECT project_id FROM plan_primary_context),
      1, 5, 'UTC', 1, 'plan-stale', '2030-03-17T00:00:00Z'
    );
    RAISE EXCEPTION 'stale personal plan revision was accepted';
  EXCEPTION WHEN serialization_failure THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.save_personal_action_plan(
      (SELECT app_user_id FROM plan_primary_context),
      (SELECT workspace_id FROM plan_primary_context),
      (SELECT project_id FROM plan_primary_context),
      2, 5, 'CST', 1, 'plan-bad-zone', '2030-03-17T00:00:00Z'
    );
    RAISE EXCEPTION 'time-zone abbreviation was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.save_personal_action_plan(
      (SELECT app_user_id FROM plan_primary_context),
      (SELECT workspace_id FROM plan_primary_context),
      (SELECT project_id FROM plan_primary_context),
      2, 5, NULL, NULL, 'plan-null-zone', '2030-03-17T00:00:00Z'
    );
    RAISE EXCEPTION 'null plan time-zone or week start was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_action_plan(
      (SELECT app_user_id FROM plan_secondary_context),
      (SELECT workspace_id FROM plan_primary_context),
      (SELECT project_id FROM plan_primary_context),
      '2030-03-17T00:00:00Z'
    );
    RAISE EXCEPTION 'another user read a private personal plan';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
