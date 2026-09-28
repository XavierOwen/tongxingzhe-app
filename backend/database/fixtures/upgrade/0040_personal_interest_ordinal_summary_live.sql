\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE interest_upgrade_input (
  contact_id text NOT NULL,
  owner_key text NOT NULL,
  project_key text NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  channel text NOT NULL,
  reach_count integer NOT NULL,
  interest_level integer NOT NULL,
  expected_in_primary_scope boolean NOT NULL
);
\copy interest_upgrade_input FROM 'backend/database/fixtures/shared/personal_contact_metrics_v1.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE interest_upgrade_primary AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-upgrade.example/auth/v1',
  '7co-primary'
);
CREATE TEMP TABLE interest_upgrade_other AS
SELECT * FROM app_data.create_personal_project_context(
  'https://synthetic-interest-upgrade.example/auth/v1',
  '7co-primary',
  '其他兴趣项目'
);
CREATE TEMP TABLE interest_upgrade_secondary AS
SELECT * FROM app_data.bootstrap_personal_context(
  'https://synthetic-interest-upgrade.example/auth/v1',
  '7co-secondary'
);

CREATE TEMP TABLE interest_upgrade_results AS
SELECT input.contact_id, written.result_code
FROM interest_upgrade_input AS input
CROSS JOIN LATERAL app_data.apply_contact_submit(
  CASE input.owner_key
    WHEN 'primary' THEN (SELECT app_user_id FROM interest_upgrade_primary)
    ELSE (SELECT app_user_id FROM interest_upgrade_secondary)
  END,
  '7co-command-' || input.contact_id,
  1,
  'contact.submit.v1',
  'synthetic-interest-upgrade-device',
  '7co-' || input.contact_id,
  0,
  jsonb_build_object(
    'contactId', '7co-' || input.contact_id,
    'workspaceId', CASE input.owner_key
      WHEN 'primary' THEN (SELECT workspace_id FROM interest_upgrade_primary)
      ELSE (SELECT workspace_id FROM interest_upgrade_secondary)
    END,
    'projectId', CASE
      WHEN input.owner_key = 'primary' AND input.project_key = 'other'
        THEN (SELECT project_id FROM interest_upgrade_other)
      WHEN input.owner_key = 'primary'
        THEN (SELECT project_id FROM interest_upgrade_primary)
      ELSE (SELECT project_id FROM interest_upgrade_secondary)
    END,
    'questionnaireVersionId', CASE
      WHEN input.owner_key = 'primary' AND input.project_key = 'other'
        THEN (SELECT questionnaire_version_id FROM interest_upgrade_other)
      WHEN input.owner_key = 'primary'
        THEN (SELECT questionnaire_version_id FROM interest_upgrade_primary)
      ELSE (SELECT questionnaire_version_id FROM interest_upgrade_secondary)
    END,
    'occurredAtUtc', to_char(
      input.occurred_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'occurredTimeZone', 'America/Chicago',
    'channel', input.channel,
    'channelDetail', NULL,
    'location', jsonb_build_object('kind', 'not_applicable'),
    'reachCount', input.reach_count,
    'interestLevel', input.interest_level,
    'answers', jsonb_build_array()
  )
) AS written;

RESET ROLE;

DO $check$
BEGIN
  IF (SELECT count(*) FROM interest_upgrade_input) <> 7
    OR (SELECT count(*) FROM interest_upgrade_results
        WHERE result_code = 'accepted') <> 7
    OR (SELECT count(*) FROM app_data.contacts
        WHERE contact_id LIKE '7co-metric-contact-%') <> 7
    OR (SELECT count(*) FROM app_data.contact_revisions
        WHERE contact_id LIKE '7co-metric-contact-%') <> 7
    OR (SELECT count(*) FROM app_data.contact_location_provenance
        WHERE contact_id LIKE '7co-metric-contact-%') <> 7
    OR (SELECT count(*) FROM app_data.processed_commands
        WHERE command_id LIKE '7co-command-metric-contact-%') <> 7
  THEN
    RAISE EXCEPTION '7CO shared CSV writer history was not fully accepted';
  END IF;
END
$check$;

COMMIT;
