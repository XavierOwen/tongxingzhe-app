BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE reminder_primary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-reminders.supabase.co/auth/v1',
  'synthetic-reminders-primary'
);

CREATE TEMP TABLE reminder_secondary_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-reminders.supabase.co/auth/v1',
  'synthetic-reminders-secondary'
);

CREATE TEMP TABLE reminder_created AS
SELECT app_data.save_personal_action_reminder(
  (SELECT app_user_id FROM reminder_primary_context),
  (SELECT workspace_id FROM reminder_primary_context),
  (SELECT project_id FROM reminder_primary_context),
  0,
  19 * 60,
  'reminder-create-1',
  '2030-03-09T18:00:00Z'
) AS document;

DO $fixture$
DECLARE
  created jsonb := (SELECT document FROM reminder_created);
  replayed jsonb;
  cleared jsonb;
  loaded jsonb;
BEGIN
  IF created->>'duplicate' <> 'false'
    OR created->>'accepted_revision' <> '1'
    OR created->>'local_minute_of_day' <> '1140'
    OR created->>'updated_at_utc' <> '2030-03-09T18:00:00+00:00'
  THEN
    RAISE EXCEPTION 'personal reminder create is incorrect: %', created;
  END IF;

  SELECT app_data.save_personal_action_reminder(
    (SELECT app_user_id FROM reminder_primary_context),
    (SELECT workspace_id FROM reminder_primary_context),
    (SELECT project_id FROM reminder_primary_context),
    0, 1140, 'reminder-create-1', '2030-03-09T18:00:00Z'
  ) INTO replayed;
  IF replayed->>'duplicate' <> 'true'
    OR replayed->>'accepted_revision' <> '1'
  THEN
    RAISE EXCEPTION 'personal reminder replay is not idempotent';
  END IF;

  SELECT app_data.save_personal_action_reminder(
    (SELECT app_user_id FROM reminder_primary_context),
    (SELECT workspace_id FROM reminder_primary_context),
    (SELECT project_id FROM reminder_primary_context),
    1, NULL, 'reminder-clear-2', '2030-03-10T18:00:00Z'
  ) INTO cleared;
  IF cleared->>'accepted_revision' <> '2'
    OR cleared->'local_minute_of_day' <> 'null'::jsonb
  THEN
    RAISE EXCEPTION 'personal reminder clear is incorrect: %', cleared;
  END IF;

  SELECT app_data.read_personal_action_reminder(
    (SELECT app_user_id FROM reminder_primary_context),
    (SELECT workspace_id FROM reminder_primary_context),
    (SELECT project_id FROM reminder_primary_context)
  ) INTO loaded;
  IF loaded->>'revision' <> '2'
    OR loaded->'local_minute_of_day' <> 'null'::jsonb
  THEN
    RAISE EXCEPTION 'personal reminder read is incorrect: %', loaded;
  END IF;

  BEGIN
    PERFORM app_data.save_personal_action_reminder(
      (SELECT app_user_id FROM reminder_primary_context),
      (SELECT workspace_id FROM reminder_primary_context),
      (SELECT project_id FROM reminder_primary_context),
      1, 600, 'reminder-stale', '2030-03-11T18:00:00Z'
    );
    RAISE EXCEPTION 'stale reminder revision was accepted';
  EXCEPTION WHEN serialization_failure THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.save_personal_action_reminder(
      (SELECT app_user_id FROM reminder_primary_context),
      (SELECT workspace_id FROM reminder_primary_context),
      (SELECT project_id FROM reminder_primary_context),
      2, 1440, 'reminder-invalid-minute', '2030-03-11T18:00:00Z'
    );
    RAISE EXCEPTION 'invalid reminder minute was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_personal_action_reminder(
      (SELECT app_user_id FROM reminder_secondary_context),
      (SELECT workspace_id FROM reminder_primary_context),
      (SELECT project_id FROM reminder_primary_context)
    );
    RAISE EXCEPTION 'another user read a private reminder';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture$;

ROLLBACK;
