-- Synthetic fixture for the 6AY runtime interest snapshot bridge.
--
-- This fixture is independent of the 0063 fixture. It creates one approved
-- 0062 interest snapshot, an interest-shaped snapshot without trusted
-- provenance, and external identities for the runtime bridge. Every row is
-- rolled back at the end.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6f110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6f110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6f110000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6f110000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  (
    '6f1e0000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-interest.synthetic/auth/v1',
    'active-reader',
    '6f110000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6f1e0000-0000-4000-8000-000000000002'::uuid,
    ' https://runtime-interest.synthetic/auth/v1 ',
    'spaced-reader',
    '6f110000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6f1e0000-0000-4000-8000-000000000003'::uuid,
    'https://runtime-interest.synthetic/auth/v1',
    'release-only-reader',
    '6f110000-0000-4000-8000-000000000003'::uuid
  ),
  (
    '6f1e0000-0000-4000-8000-000000000004'::uuid,
    'https://runtime-interest.synthetic/auth/v1',
    'inactive-reader',
    '6f110000-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
)
VALUES (
  '6f120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AY runtime interest workspace',
  NULL
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '6f130000-0000-4000-8000-000000000001'::uuid,
    '6f120000-0000-4000-8000-000000000001'::uuid,
    '6AY runtime interest project'
  ),
  (
    '6f130000-0000-4000-8000-000000000002'::uuid,
    '6f120000-0000-4000-8000-000000000001'::uuid,
    '6AY other project'
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES
  (
    '6f140000-0000-4000-8000-000000000001'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    1, 'published', true
  ),
  (
    '6f140000-0000-4000-8000-000000000002'::uuid,
    '6f130000-0000-4000-8000-000000000002'::uuid,
    1, 'published', true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6f160000-0000-4000-8000-000000000001'::uuid,
    '6f120000-0000-4000-8000-000000000001'::uuid,
    '6f110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f160000-0000-4000-8000-000000000002'::uuid,
    '6f120000-0000-4000-8000-000000000001'::uuid,
    '6f110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f160000-0000-4000-8000-000000000003'::uuid,
    '6f120000-0000-4000-8000-000000000001'::uuid,
    '6f110000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f160000-0000-4000-8000-000000000004'::uuid,
    '6f120000-0000-4000-8000-000000000001'::uuid,
    '6f110000-0000-4000-8000-000000000004'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6f170000-0000-4000-8000-000000000001'::uuid,
    '6f160000-0000-4000-8000-000000000001'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f170000-0000-4000-8000-000000000002'::uuid,
    '6f160000-0000-4000-8000-000000000002'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f170000-0000-4000-8000-000000000003'::uuid,
    '6f160000-0000-4000-8000-000000000002'::uuid,
    '6f130000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f170000-0000-4000-8000-000000000004'::uuid,
    '6f160000-0000-4000-8000-000000000003'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f170000-0000-4000-8000-000000000005'::uuid,
    '6f160000-0000-4000-8000-000000000004'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '6f180000-0000-4000-8000-000000000001'::uuid,
    '6f170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f180000-0000-4000-8000-000000000002'::uuid,
    '6f170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f180000-0000-4000-8000-000000000003'::uuid,
    '6f170000-0000-4000-8000-000000000003'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f180000-0000-4000-8000-000000000004'::uuid,
    '6f170000-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6f180000-0000-4000-8000-000000000005'::uuid,
    '6f170000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  );

UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6f110000-0000-4000-8000-000000000004'::uuid;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6f150000-0000-4000-8000-000000000001'::uuid,
  '6f110000-0000-4000-8000-000000000001'::uuid,
  '6f130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6ay_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

CREATE TEMP TABLE fixture_6ay_interest_contacts AS
SELECT
  format(
    '6ay-interest-%s-%s-%s-%s',
    period_row.period_key,
    level_row,
    contributor_row.contributor_number,
    unit_row.unit_number
  ) AS contact_id,
  period_row.period_key,
  level_row AS interest_level,
  contributor_row.contributor_number,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 minute'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 minute'
  END AS occurred_at_utc
FROM fixture_6ay_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN generate_series(0, 4) AS level_row
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(1, contributor_row.unit_count)
  AS unit_row(unit_number);

INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel,
  location_kind,
  reach_count,
  interest_level
)
SELECT
  expected.contact_id,
  CASE expected.contributor_number
    WHEN 1 THEN '6f110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6f110000-0000-4000-8000-000000000002'::uuid
    ELSE '6f110000-0000-4000-8000-000000000003'::uuid
  END,
  '6f120000-0000-4000-8000-000000000001'::uuid,
  '6f130000-0000-4000-8000-000000000001'::uuid,
  '6f140000-0000-4000-8000-000000000001'::uuid,
  expected.occurred_at_utc,
  'UTC',
  expected.occurred_at_utc,
  'voice_call',
  'not_applicable',
  1,
  expected.interest_level
FROM fixture_6ay_interest_contacts AS expected;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
)
VALUES (
  '6f110000-0000-4000-8000-000000000001'::uuid,
  '6f120000-0000-4000-8000-000000000001'::uuid,
  '6f130000-0000-4000-8000-000000000001'::uuid,
  '6ay-runtime-watermark',
  1,
  'contact.submitted'
);

DO $fixture_6ay_release$
DECLARE
  baseline jsonb;
  rolling jsonb;
BEGIN
  baseline := app_private.release_management_interest_report_snapshot_v1(
    '6f800000-0000-4000-8000-000000000001'::uuid,
    '6f110000-0000-4000-8000-000000000001'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  );
  IF baseline->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR baseline->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION '6AY could not create the interest baseline: %', baseline;
  END IF;

  PERFORM pg_sleep(0.01);
  rolling := app_private.release_management_interest_report_snapshot_v1(
    '6f800000-0000-4000-8000-000000000002'::uuid,
    '6f110000-0000-4000-8000-000000000001'::uuid,
    '6f130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  );
  IF rolling->>'result_status' IS DISTINCT FROM 'approved'
    OR rolling->>'released_snapshot_id' IS NULL
    OR rolling->>'compared_snapshot_id' IS DISTINCT FROM
      baseline->>'released_snapshot_id'
  THEN
    RAISE EXCEPTION '6AY could not create the approved rolling snapshot: %',
      rolling;
  END IF;
END
$fixture_6ay_release$;

-- Shape alone is not interest provenance. This copy has the exact report
-- document but no 0062 attempt or interest-family claim.
DO $fixture_6ay_untrusted$
DECLARE
  trusted_snapshot app_private.management_report_snapshots%ROWTYPE;
BEGIN
  SELECT snapshot.*
  INTO STRICT trusted_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id =
    '6f800000-0000-4000-8000-000000000001'::uuid;

  INSERT INTO app_private.management_report_snapshots (
    snapshot_id,
    release_request_id,
    created_by_app_user_id,
    project_id,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    reporting_time_zone,
    data_cutoff_utc,
    released_at_utc,
    previous_snapshot_id,
    source_change_sequence,
    protected_report
  ) VALUES (
    '6fa00000-0000-4000-8000-000000000001'::uuid,
    '6fa00000-0000-4000-8000-000000000001'::uuid,
    trusted_snapshot.created_by_app_user_id,
    trusted_snapshot.project_id,
    trusted_snapshot.release_lineage_id,
    trusted_snapshot.report_id,
    trusted_snapshot.report_version,
    trusted_snapshot.query_fingerprint,
    trusted_snapshot.reporting_time_zone,
    trusted_snapshot.data_cutoff_utc,
    trusted_snapshot.released_at_utc,
    trusted_snapshot.previous_snapshot_id,
    trusted_snapshot.source_change_sequence,
    trusted_snapshot.protected_report
  );
END
$fixture_6ay_untrusted$;

CREATE TEMP TABLE fixture_6ay_counts AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_users,
  (SELECT count(*) FROM app_data.workspaces) AS workspaces,
  (SELECT count(*) FROM app_data.projects) AS projects;

SELECT set_config(
  'app.fixture_6ay_baseline_snapshot_id',
  (
    SELECT released_snapshot_id::text
    FROM app_private.management_interest_report_release_attempts
    WHERE release_request_id = '6f800000-0000-4000-8000-000000000001'::uuid
  ),
  true
);

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6ay_runtime$
DECLARE
  active_read jsonb;
  repeated_read jsonb;
  exact_read jsonb;
  missing_read jsonb;
  cross_project_read jsonb;
  untrusted_read jsonb;
BEGIN
  active_read := app_data.read_authorized_management_interest_report_snapshot_v1(
    'https://runtime-interest.synthetic/auth/v1',
    'active-reader',
    '6f130000-0000-4000-8000-000000000001'::uuid,
    current_setting('app.fixture_6ay_baseline_snapshot_id')::uuid
  );
  IF active_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_interest_management_report_snapshot_read_v1'
    OR active_read->>'result_status' IS DISTINCT FROM 'completed'
    OR active_read->>'resolved_snapshot_id' IS NULL
    OR active_read->'protected_report'->>'report_id' IS DISTINCT FROM
      'contact_sessions_by_interest_level_two_periods'
    OR jsonb_array_length(active_read->'protected_report'->'cells') <> 10
    OR active_read ? 'project_id'
    OR active_read ? 'requested_app_user_id'
    OR active_read::text ~* 'organization_membership|capability_grant|app_user_id'
  THEN
    RAISE EXCEPTION '6AY active runtime read returned an invalid result: %',
      active_read;
  END IF;

  repeated_read := app_data.read_authorized_management_interest_report_snapshot_v1(
    'https://runtime-interest.synthetic/auth/v1',
    'active-reader',
    '6f130000-0000-4000-8000-000000000001'::uuid,
    (active_read->>'resolved_snapshot_id')::uuid
  );
  IF repeated_read->>'result_status' IS DISTINCT FROM 'completed'
    OR repeated_read->>'access_event_id' IS NULL
    OR repeated_read->>'access_event_id' = active_read->>'access_event_id'
  THEN
    RAISE EXCEPTION '6AY repeated runtime read did not append an audit';
  END IF;

  -- The stored issuer contains spaces. A clean issuer must not be trimmed into
  -- a match; the exact stored value is accepted as a separate successful read.
  BEGIN
    PERFORM app_data.read_authorized_management_interest_report_snapshot_v1(
      'https://runtime-interest.synthetic/auth/v1',
      'spaced-reader',
      '6f130000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
    RAISE EXCEPTION '6AY runtime bridge trimmed a stored external identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  exact_read := app_data.read_authorized_management_interest_report_snapshot_v1(
    ' https://runtime-interest.synthetic/auth/v1 ',
    'spaced-reader',
    '6f130000-0000-4000-8000-000000000001'::uuid,
    (active_read->>'resolved_snapshot_id')::uuid
  );
  IF exact_read->>'result_status' IS DISTINCT FROM 'completed'
    OR exact_read->>'access_event_id' IS NULL
  THEN
    RAISE EXCEPTION '6AY exact stored external identity did not resolve';
  END IF;

  missing_read := app_data.read_authorized_management_interest_report_snapshot_v1(
    'https://runtime-interest.synthetic/auth/v1',
    'active-reader',
    '6f130000-0000-4000-8000-000000000001'::uuid,
    '6fa00000-0000-4000-8000-000000000099'::uuid
  );
  IF missing_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR missing_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR missing_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6AY missing snapshot did not fail closed: %', missing_read;
  END IF;

  cross_project_read := app_data.read_authorized_management_interest_report_snapshot_v1(
    'https://runtime-interest.synthetic/auth/v1',
    'active-reader',
    '6f130000-0000-4000-8000-000000000002'::uuid,
    (active_read->>'resolved_snapshot_id')::uuid
  );
  IF cross_project_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR cross_project_read->>'reason_code' IS DISTINCT FROM
      'snapshot_not_available'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6AY cross-project snapshot was distinguishable: %',
      cross_project_read;
  END IF;

  untrusted_read := app_data.read_authorized_management_interest_report_snapshot_v1(
    'https://runtime-interest.synthetic/auth/v1',
    'active-reader',
    '6f130000-0000-4000-8000-000000000001'::uuid,
    '6fa00000-0000-4000-8000-000000000001'::uuid
  );
  IF untrusted_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR untrusted_read->>'reason_code' IS DISTINCT FROM
      'snapshot_provenance_untrusted'
    OR untrusted_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6AY untrusted provenance leaked values: %', untrusted_read;
  END IF;

  BEGIN
    PERFORM app_data.read_authorized_management_interest_report_snapshot_v1(
      'https://runtime-interest.synthetic/auth/v1',
      'release-only-reader',
      '6f130000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
    RAISE EXCEPTION '6AY runtime bridge accepted a release-only identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_authorized_management_interest_report_snapshot_v1(
      'https://runtime-interest.synthetic/auth/v1',
      'inactive-reader',
      '6f130000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
    RAISE EXCEPTION '6AY runtime bridge accepted an inactive identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.read_authorized_management_interest_report_snapshot_v1(
      'https://runtime-interest.synthetic/auth/v1',
      'unknown-reader',
      '6f130000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
    RAISE EXCEPTION '6AY runtime bridge accepted an unknown identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_interest_report_snapshot_v1(
      '6f110000-0000-4000-8000-000000000002'::uuid,
      '6f130000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
    RAISE EXCEPTION '6AY runtime role received direct app_private access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture_6ay_runtime$;

RESET ROLE;

DO $fixture_6ay_audit$
DECLARE
  expected_counts record;
  actual_counts record;
  history_text text;
BEGIN
  SELECT * INTO STRICT expected_counts FROM fixture_6ay_counts;
  SELECT
    (SELECT count(*) FROM app_data.app_users) AS app_users,
    (SELECT count(*) FROM app_data.workspaces) AS workspaces,
    (SELECT count(*) FROM app_data.projects) AS projects
  INTO STRICT actual_counts;
  IF actual_counts.app_users IS DISTINCT FROM expected_counts.app_users
    OR actual_counts.workspaces IS DISTINCT FROM expected_counts.workspaces
    OR actual_counts.projects IS DISTINCT FROM expected_counts.projects
  THEN
    RAISE EXCEPTION '6AY unknown identity bootstrapped application rows';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6f110000-0000-4000-8000-000000000002'::uuid
  ) <> 6
  OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6f110000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'completed'
  ) <> 3
  OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6f110000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'not_found'
  ) <> 2
  OR (
    SELECT count(*)
    FROM app_private.management_interest_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6f110000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'untrusted_provenance'
  ) <> 1
  THEN
    RAISE EXCEPTION '6AY runtime audit status counts are incorrect';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_interest_report_snapshot_access_events AS event
  WHERE event.requested_by_app_user_id =
    '6f110000-0000-4000-8000-000000000002'::uuid;
  IF history_text ~* '(protected_report|value_count|privacy_status|cell_order|contributor|place_name|canonical_name|pii)'
  THEN
    RAISE EXCEPTION '6AY runtime audit retained protected values';
  END IF;
END
$fixture_6ay_audit$;

ROLLBACK;
