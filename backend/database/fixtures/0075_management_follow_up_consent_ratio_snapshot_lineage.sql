-- Synthetic rollback fixture for Slice 6BQ.
--
-- This fixture consumes the already protected 0074 candidate and verifies the
-- private snapshot/release lineage seam. It never returns a protected report
-- through the release contract. All UUIDs use the legal 6b750000 namespace;
-- committed rows from the independent concurrency script use a different
-- namespace. A single transaction timestamp is used for every hierarchy range
-- so pg_dump/restore cannot create a parent/child containment race.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6bq_clock ON COMMIT DROP AS
SELECT clock_value AS fixture_now_utc,
       date_trunc('week', clock_value) AS current_iso_week_start_utc,
       date_trunc('week', clock_value) - interval '7 days'
         AS current_period_start_utc,
       date_trunc('week', clock_value) - interval '14 days'
         AS previous_period_start_utc,
       date_trunc('week', clock_value) + interval '1 hour'
         AS report_cutoff_utc
FROM (SELECT transaction_timestamp() AS clock_value) AS stable_clock;

GRANT SELECT ON fixture_6bq_clock
  TO tongxingzhe_management_follow_up_consent_config_writer,
     tongxingzhe_management_follow_up_consent_ratio_reader,
     tongxingzhe_management_current_city_snapshot_release_writer;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b750100-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b750100-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b750100-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b750100-0000-4000-8000-000000000004'::uuid, 'active'),
  ('6b750100-0000-4000-8000-000000000005'::uuid, 'deletion_pending');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
)
VALUES
  (
    '6b750200-0000-4000-8000-000000000001'::uuid,
    'organization', '6BQ consent snapshot organization', NULL
  ),
  (
    '6b750200-0000-4000-8000-000000000002'::uuid,
    'organization', '6BQ consent snapshot other organization', NULL
  ),
  (
    '6b750200-0000-4000-8000-000000000003'::uuid,
    'personal', '6BQ consent snapshot personal workspace',
    '6b750100-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
VALUES
  (
    '6b750300-0000-4000-8000-000000000001'::uuid,
    '6b750200-0000-4000-8000-000000000001'::uuid,
    '6BQ enabled safe project', 'active', false
  ),
  (
    '6b750300-0000-4000-8000-000000000002'::uuid,
    '6b750200-0000-4000-8000-000000000001'::uuid,
    '6BQ suppressed project', 'active', false
  ),
  (
    '6b750300-0000-4000-8000-000000000003'::uuid,
    '6b750200-0000-4000-8000-000000000001'::uuid,
    '6BQ not enabled project', 'active', false
  ),
  (
    '6b750300-0000-4000-8000-000000000004'::uuid,
    '6b750200-0000-4000-8000-000000000002'::uuid,
    '6BQ cross organization project', 'active', false
  ),
  (
    '6b750300-0000-4000-8000-000000000005'::uuid,
    '6b750200-0000-4000-8000-000000000003'::uuid,
    '6BQ personal project', 'active', true
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
SELECT format(
         '6b750350-0000-4000-8000-%s',
         lpad(project_row.project_number::text, 12, '0')
       )::uuid,
       project_row.project_id,
       1,
       'published',
       true
FROM (
  VALUES
    (1, '6b750300-0000-4000-8000-000000000001'::uuid),
    (2, '6b750300-0000-4000-8000-000000000002'::uuid),
    (3, '6b750300-0000-4000-8000-000000000003'::uuid),
    (4, '6b750300-0000-4000-8000-000000000004'::uuid),
    (5, '6b750300-0000-4000-8000-000000000005'::uuid)
) AS project_row(project_number, project_id);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.membership_id,
       membership.workspace_id,
       membership.app_user_id,
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '6b750400-0000-4000-8000-000000000001'::uuid,
      '6b750200-0000-4000-8000-000000000001'::uuid,
      '6b750100-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b750400-0000-4000-8000-000000000002'::uuid,
      '6b750200-0000-4000-8000-000000000002'::uuid,
      '6b750100-0000-4000-8000-000000000004'::uuid
    )
) AS membership(membership_id, workspace_id, app_user_id)
CROSS JOIN fixture_6bq_clock AS clock;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.membership_id,
       membership.organization_membership_id,
       membership.project_id,
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '6b750500-0000-4000-8000-000000000001'::uuid,
      '6b750400-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b750500-0000-4000-8000-000000000002'::uuid,
      '6b750400-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b750500-0000-4000-8000-000000000003'::uuid,
      '6b750400-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6b750500-0000-4000-8000-000000000004'::uuid,
      '6b750400-0000-4000-8000-000000000002'::uuid,
      '6b750300-0000-4000-8000-000000000004'::uuid
    )
) AS membership(membership_id, organization_membership_id, project_id)
CROSS JOIN fixture_6bq_clock AS clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT grant_row.grant_id,
       grant_row.project_membership_id,
       grant_row.capability_id,
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '6b750600-0000-4000-8000-000000000001'::uuid,
      '6b750500-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b750600-0000-4000-8000-000000000002'::uuid,
      '6b750500-0000-4000-8000-000000000002'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b750600-0000-4000-8000-000000000003'::uuid,
      '6b750500-0000-4000-8000-000000000003'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b750600-0000-4000-8000-000000000004'::uuid,
      '6b750500-0000-4000-8000-000000000004'::uuid,
      'release_management_reports'::text
    )
) AS grant_row(grant_id, project_membership_id, capability_id)
CROSS JOIN fixture_6bq_clock AS clock;

-- Keep one active actor with only the read capability.  This actor is used to
-- prove that a 6BQ release cannot be reached through the neighboring view
-- contract, while the active user below remains deliberately membership-free
-- for the missing-membership case.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '6b750400-0000-4000-8000-000000000003'::uuid,
  '6b750200-0000-4000-8000-000000000001'::uuid,
  '6b750100-0000-4000-8000-000000000002'::uuid,
  clock.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6bq_clock AS clock;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '6b750500-0000-4000-8000-000000000005'::uuid,
  '6b750400-0000-4000-8000-000000000003'::uuid,
  '6b750300-0000-4000-8000-000000000003'::uuid,
  clock.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6bq_clock AS clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '6b750600-0000-4000-8000-000000000006'::uuid,
  '6b750500-0000-4000-8000-000000000005'::uuid,
  'view_anonymous_analytics',
  clock.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6bq_clock AS clock;

-- Configure the reporting timezone and 6BO opt-in only after the complete
-- authorization hierarchy exists. All parent and child timestamps use the same
-- transaction-derived clock.
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750700-0000-4000-8000-000000000001'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock.report_cutoff_utc - interval '365 days'
)
FROM fixture_6bq_clock AS clock;
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750700-0000-4000-8000-000000000002'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock.report_cutoff_utc - interval '365 days'
)
FROM fixture_6bq_clock AS clock;
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750700-0000-4000-8000-000000000003'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000003'::uuid,
  0,
  'UTC',
  clock.report_cutoff_utc - interval '365 days'
)
FROM fixture_6bq_clock AS clock;
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750700-0000-4000-8000-000000000005'::uuid,
  '6b750100-0000-4000-8000-000000000004'::uuid,
  '6b750300-0000-4000-8000-000000000004'::uuid,
  0,
  'UTC',
  clock.report_cutoff_utc - interval '365 days'
)
FROM fixture_6bq_clock AS clock;
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b750710-0000-4000-8000-000000000001'::uuid,
  0,
  true
);
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000002'::uuid,
  'follow_up_consent_ratio@1',
  '6b750710-0000-4000-8000-000000000002'::uuid,
  0,
  true
);
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b750100-0000-4000-8000-000000000004'::uuid,
  '6b750300-0000-4000-8000-000000000004'::uuid,
  'follow_up_consent_ratio@1',
  '6b750710-0000-4000-8000-000000000004'::uuid,
  0,
  true
);
RESET ROLE;

-- One target per link is sufficient. The source rows intentionally use only
-- current active revisions and stable, pre-cutoff timestamps.
INSERT INTO app_data.promotion_targets (
  promotion_target_id, workspace_id, target_type, display_name,
  phone, email, created_by_app_user_id
)
SELECT format(
         '6b750800-0000-4000-8000-%s',
         lpad(target_number::text, 12, '0')
       )::uuid,
       '6b750200-0000-4000-8000-000000000001'::uuid,
       'person',
       '6BQ synthetic target ' || target_number,
       NULL,
       NULL,
       '6b750100-0000-4000-8000-000000000001'::uuid
FROM generate_series(1, 30) AS target_number;

CREATE TEMP TABLE fixture_6bq_source_rows (
  contact_id text PRIMARY KEY,
  app_user_id uuid NOT NULL,
  project_id uuid NOT NULL,
  questionnaire_version_id uuid NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  first_submitted_at_utc timestamptz NOT NULL,
  promotion_target_id uuid NOT NULL,
  follow_up_consent text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6bq_source_rows (
  contact_id, app_user_id, project_id, questionnaire_version_id,
  occurred_at_utc, first_submitted_at_utc, promotion_target_id,
  follow_up_consent
)
SELECT format('6bq-main-%s-%s-%s', period.period_key, state.consent_state, n),
       CASE ((n - 1) % 3)
         WHEN 0 THEN '6b750100-0000-4000-8000-000000000002'::uuid
         WHEN 1 THEN '6b750100-0000-4000-8000-000000000003'::uuid
         ELSE '6b750100-0000-4000-8000-000000000004'::uuid
       END,
       '6b750300-0000-4000-8000-000000000001'::uuid,
       '6b750350-0000-4000-8000-000000000001'::uuid,
       period.period_start_utc + interval '2 days'
         + (state.sort_order * 20 + n) * interval '1 minute',
       period.period_start_utc + interval '2 days'
         + (state.sort_order * 20 + n) * interval '1 minute'
         + interval '1 minute',
       format(
         '6b750800-0000-4000-8000-%s',
         lpad((((state.sort_order * 10) + n)::integer)::text, 12, '0')
       )::uuid,
       state.consent_state
FROM (
  SELECT 'previous'::text AS period_key,
         clock.previous_period_start_utc AS period_start_utc
  FROM fixture_6bq_clock AS clock
  UNION ALL
  SELECT 'current'::text,
         clock.current_period_start_utc
  FROM fixture_6bq_clock AS clock
) AS period
CROSS JOIN (
  VALUES ('yes'::text, 0), ('no'::text, 1)
) AS state(consent_state, sort_order)
CROSS JOIN generate_series(1, 10) AS n;

-- A second project has nine yes links spread over two contributors, so its
-- ratio is suppressed while its no cell remains separately safe.
INSERT INTO fixture_6bq_source_rows (
  contact_id, app_user_id, project_id, questionnaire_version_id,
  occurred_at_utc, first_submitted_at_utc, promotion_target_id,
  follow_up_consent
)
SELECT format('6bq-suppressed-%s-%s-%s', period.period_key, state.consent_state, n),
       CASE WHEN n % 2 = 0
         THEN '6b750100-0000-4000-8000-000000000002'::uuid
         ELSE '6b750100-0000-4000-8000-000000000003'::uuid
       END,
       '6b750300-0000-4000-8000-000000000002'::uuid,
       '6b750350-0000-4000-8000-000000000002'::uuid,
       period.period_start_utc + interval '2 days'
         + (state.sort_order * 20 + n) * interval '1 minute',
       period.period_start_utc + interval '2 days'
         + (state.sort_order * 20 + n) * interval '1 minute'
         + interval '1 minute',
       format(
         '6b750800-0000-4000-8000-%s',
         lpad((10 + ((state.sort_order * 10) + n))::text, 12, '0')
       )::uuid,
       state.consent_state
FROM (
  SELECT 'previous'::text AS period_key,
         clock.previous_period_start_utc AS period_start_utc
  FROM fixture_6bq_clock AS clock
  UNION ALL
  SELECT 'current'::text,
         clock.current_period_start_utc
  FROM fixture_6bq_clock AS clock
) AS period
CROSS JOIN (
  VALUES ('yes'::text, 0, 9), ('no'::text, 1, 10)
) AS state(consent_state, sort_order, state_count)
CROSS JOIN LATERAL generate_series(1, state.state_count) AS n;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, reach_count,
  interest_level, current_revision, lifecycle_status
)
SELECT source.contact_id,
       source.app_user_id,
       '6b750200-0000-4000-8000-000000000001'::uuid,
       source.project_id,
       source.questionnaire_version_id,
       source.occurred_at_utc,
       'UTC',
       source.first_submitted_at_utc,
       'video_call',
       'not_applicable',
       1,
       2,
       1,
       'active'
FROM fixture_6bq_source_rows AS source;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revised_by_app_user_id,
  revision_kind, reason, snapshot
)
SELECT source.contact_id,
       1,
       source.app_user_id,
       'submitted',
       NULL,
       '{}'::jsonb
FROM fixture_6bq_source_rows AS source;

INSERT INTO app_data.contact_target_links (
  contact_id, revision_number, promotion_target_id, response_level,
  follow_up_consent, institution_representative_confirmed,
  confirmed_project_entry
)
SELECT source.contact_id,
       1,
       source.promotion_target_id,
       NULL,
       source.follow_up_consent,
       false,
       true
FROM fixture_6bq_source_rows AS source;

DO $assert_source_fixture$
DECLARE
  source_count bigint;
  main_yes bigint;
  main_no bigint;
  suppressed_yes bigint;
BEGIN
  SELECT count(*) INTO source_count FROM fixture_6bq_source_rows;
  SELECT count(*) INTO main_yes
  FROM fixture_6bq_source_rows
  WHERE project_id = '6b750300-0000-4000-8000-000000000001'::uuid
    AND follow_up_consent = 'yes';
  SELECT count(*) INTO main_no
  FROM fixture_6bq_source_rows
  WHERE project_id = '6b750300-0000-4000-8000-000000000001'::uuid
    AND follow_up_consent = 'no';
  SELECT count(*) INTO suppressed_yes
  FROM fixture_6bq_source_rows
  WHERE project_id = '6b750300-0000-4000-8000-000000000002'::uuid
    AND follow_up_consent = 'yes';
  IF source_count <> 78 OR main_yes <> 20 OR main_no <> 20
    OR suppressed_yes <> 18
  THEN
    RAISE EXCEPTION
      '6BQ source fixture cardinality drifted: total %, main yes/no %/%, suppressed yes %',
      source_count, main_yes, main_no, suppressed_yes;
  END IF;
END
$assert_source_fixture$;

-- The first snapshot is generated by the private release seam, not by a
-- caller-supplied report document. The returned envelope must be value-free.
CREATE TEMP TABLE fixture_6bq_baseline ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b750900-0000-4000-8000-000000000001'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;

DO $assert_baseline$
DECLARE
  document jsonb;
  document_text text;
  baseline_snapshot_id uuid;
BEGIN
  SELECT fixture.document INTO STRICT document
  FROM fixture_6bq_baseline AS fixture;
  document_text := document::text;
  IF document->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR document->>'released_snapshot_id' IS NULL
    OR document->>'compared_snapshot_id' IS NOT NULL
    OR document->>'release_lineage_id' IS DISTINCT FROM
      'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
    OR document ? 'protected_report'
    OR document ? 'period_results'
    OR document ? 'cells'
    OR document_text ~* '(contact_id|promotion_target_id|target_id|contributor|membership|capability_grant|raw_answer|phone|email|place_name|latitude|longitude)'
  THEN
    RAISE EXCEPTION '6BQ baseline release is not value-free: %', document;
  END IF;

  baseline_snapshot_id := (document->>'released_snapshot_id')::uuid;
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.snapshot_id = baseline_snapshot_id
      AND snapshot.project_id =
        '6b750300-0000-4000-8000-000000000001'::uuid
      AND snapshot.release_lineage_id =
        'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
      AND snapshot.previous_snapshot_id IS NULL
      AND snapshot.source_change_sequence >= 0
  ) THEN
    RAISE EXCEPTION '6BQ baseline snapshot provenance is incomplete';
  END IF;
END
$assert_baseline$;

-- Identical request replay is exact and must not append history.
CREATE TEMP TABLE fixture_6bq_counts_before_replay ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_private.management_report_snapshots
   WHERE project_id = '6b750300-0000-4000-8000-000000000001'::uuid) AS snapshots,
  (SELECT count(*) FROM app_private.management_follow_up_consent_report_release_attempts
   WHERE project_id = '6b750300-0000-4000-8000-000000000001'::uuid) AS attempts;
CREATE TEMP TABLE fixture_6bq_replay ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b750900-0000-4000-8000-000000000001'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;
DO $assert_replay$
DECLARE
  before_snapshots bigint;
  before_attempts bigint;
BEGIN
  SELECT snapshots, attempts INTO before_snapshots, before_attempts
  FROM fixture_6bq_counts_before_replay;
  IF (SELECT replay.document FROM fixture_6bq_replay AS replay)
      IS DISTINCT FROM (SELECT baseline.document FROM fixture_6bq_baseline AS baseline)
    OR (SELECT count(*) FROM app_private.management_report_snapshots
        WHERE project_id = '6b750300-0000-4000-8000-000000000001'::uuid)
        <> before_snapshots
    OR (SELECT count(*) FROM app_private.management_follow_up_consent_report_release_attempts
        WHERE project_id = '6b750300-0000-4000-8000-000000000001'::uuid)
        <> before_attempts
  THEN
    RAISE EXCEPTION '6BQ same-request replay was not exact and idempotent';
  END IF;
END
$assert_replay$;

-- A later request with the same fixed contract is a successor and links to
-- the baseline rather than forking the lineage.
SELECT pg_sleep(0.01);
CREATE TEMP TABLE fixture_6bq_successor ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b750900-0000-4000-8000-000000000002'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;

DO $assert_successor$
DECLARE
  document jsonb;
  baseline_id uuid;
BEGIN
  SELECT fixture.document INTO STRICT document FROM fixture_6bq_successor AS fixture;
  SELECT (fixture.document->>'released_snapshot_id')::uuid
  INTO STRICT baseline_id
  FROM fixture_6bq_baseline AS fixture;
  IF document->>'result_status' IS DISTINCT FROM 'approved'
    OR (document->>'compared_snapshot_id')::uuid IS DISTINCT FROM baseline_id
    OR document->>'released_snapshot_id' IS NULL
    OR document ? 'protected_report'
    OR document ? 'period_results'
  THEN
    RAISE EXCEPTION '6BQ successor release lost the baseline pointer: %', document;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.release_request_id =
      '6b750900-0000-4000-8000-000000000002'::uuid
      AND snapshot.previous_snapshot_id = baseline_id
  ) THEN
    RAISE EXCEPTION '6BQ successor snapshot has no previous pointer';
  END IF;
END
$assert_successor$;

-- A suppressed candidate may become a snapshot only with null hidden values.
-- A not-enabled candidate must not become a snapshot.
CREATE TEMP TABLE fixture_6bq_suppressed ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b750900-0000-4000-8000-000000000003'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000002'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;
CREATE TEMP TABLE fixture_6bq_not_enabled ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b750900-0000-4000-8000-000000000004'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000003'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;

DO $assert_blocked_candidates$
DECLARE
  document jsonb;
  audit_text text;
BEGIN
  SELECT fixture.document INTO STRICT document FROM fixture_6bq_suppressed AS fixture;
  IF document->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR document->>'released_snapshot_id' IS NULL
    OR document ? 'protected_report'
    OR document ? 'period_results'
    OR document ? 'cells'
  THEN
    RAISE EXCEPTION '6BQ suppressed candidate was not safely released: %', document;
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot,
      jsonb_array_elements(snapshot.protected_report->'period_results')
        AS period(item)
    WHERE snapshot.snapshot_id =
        (document->>'released_snapshot_id')::uuid
      AND period.item->'ratio'->>'privacy_status' = 'suppressed'
      AND period.item->'ratio'->'numerator' = 'null'::jsonb
      AND period.item->'ratio'->'denominator' = 'null'::jsonb
      AND period.item->'ratio'->'percentage_basis_points' = 'null'::jsonb
  ) THEN
    RAISE EXCEPTION '6BQ released suppressed values were not null';
  END IF;
  SELECT attempt.result_document::text
  INTO STRICT audit_text
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id =
    '6b750900-0000-4000-8000-000000000003'::uuid;
  IF audit_text ~* '(protected_report|period_results|cells|coverage|contact_id|promotion_target_id|contributor|phone|email)'
  THEN
    RAISE EXCEPTION '6BQ suppressed release audit leaked candidate values: %', audit_text;
  END IF;

  SELECT fixture.document INTO STRICT document FROM fixture_6bq_not_enabled AS fixture;
  IF document->>'result_status' IS DISTINCT FROM 'blocked'
    OR document->>'released_snapshot_id' IS NOT NULL
    OR document ? 'protected_report'
    OR document ? 'period_results'
    OR document ? 'cells'
  THEN
    RAISE EXCEPTION '6BQ not-enabled candidate was not value-free blocked: %', document;
  END IF;
END
$assert_blocked_candidates$;

-- The document validator must reject identity, privacy and period drift.
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_ratio_reader;
CREATE TEMP TABLE fixture_6bq_candidate ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'UTC',
  clock.report_cutoff_utc
) AS document
FROM fixture_6bq_clock AS clock;
RESET ROLE;
DO $assert_document_validator$
DECLARE
  base_document jsonb;
  mutation record;
  mutated_document jsonb;
  rejected boolean;
BEGIN
  SELECT fixture.document INTO STRICT base_document FROM fixture_6bq_candidate AS fixture;
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    base_document
  );
  FOR mutation IN
    SELECT *
    FROM (VALUES
      ('report_id'::text, to_jsonb('other_report'::text)),
      ('metric_id'::text, to_jsonb('other_metric'::text)),
      ('statistical_unit'::text, to_jsonb('person'::text)),
      ('period_boundary_id'::text, to_jsonb('other_boundary'::text)),
      ('privacy_policy'::text, to_jsonb('other_policy'::text)),
      ('query_fingerprint'::text, to_jsonb('other_query'::text)),
      ('unexpected'::text, to_jsonb(true))
    ) AS mutation(field_name, field_value)
  LOOP
    mutated_document := jsonb_set(
      base_document, ARRAY[mutation.field_name], mutation.field_value, true
    );
    rejected := false;
    BEGIN
      PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
        mutated_document
      );
    EXCEPTION WHEN SQLSTATE '22023' THEN
      rejected := true;
    END;
    IF NOT rejected THEN
      RAISE EXCEPTION '6BQ candidate validator accepted drifted field %',
        mutation.field_name;
    END IF;
  END LOOP;
  mutated_document := jsonb_set(
    base_document, '{period_results,0,ratio,numerator}', '9'::jsonb
  );
  BEGIN
    PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
      mutated_document
    );
    RAISE EXCEPTION '6BQ candidate validator accepted unsafe ratio mutation';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END
$assert_document_validator$;

-- TEST-046 rollback pairs are injected at the protected-document seam.  This
-- keeps each negative deterministic: the assessor receives valid 6BP
-- documents, while no release attempt or snapshot is appended by these pure
-- pair checks.
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_ratio_reader;
CREATE TEMP TABLE fixture_6bq_pair_later ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'UTC',
  clock.report_cutoff_utc + interval '15 days'
) AS document
FROM fixture_6bq_clock AS clock;
CREATE TEMP TABLE fixture_6bq_watermark_candidate ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6b750100-0000-4000-8000-000000000004'::uuid,
  '6b750300-0000-4000-8000-000000000004'::uuid,
  'UTC',
  clock.fixture_now_utc - interval '1 hour'
) AS document
FROM fixture_6bq_clock AS clock;
CREATE TEMP TABLE fixture_6bq_future_candidate ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6b750100-0000-4000-8000-000000000004'::uuid,
  '6b750300-0000-4000-8000-000000000004'::uuid,
  'UTC',
  clock.fixture_now_utc + interval '15 days'
) AS document
FROM fixture_6bq_clock AS clock;
RESET ROLE;

DO $assert_6bq_deterministic_pairs$
DECLARE
  base_document jsonb;
  later_document jsonb;
  same_cutoff_document jsonb;
  earlier_cutoff_document jsonb;
  monotone_document jsonb;
  ratio_changed_document jsonb;
  coverage_displayed_document jsonb;
  coverage_changed_document jsonb;
  privacy_transition_document jsonb;
  pair_result jsonb;
  before_snapshot_count bigint;
  before_attempt_count bigint;
  after_snapshot_count bigint;
  after_attempt_count bigint;
  base_cutoff timestamp with time zone;
  earlier_cutoff_text text;
  monotone_cutoff_text text;
BEGIN
  SELECT fixture.document INTO STRICT base_document
  FROM fixture_6bq_candidate AS fixture;
  SELECT fixture.document INTO STRICT later_document
  FROM fixture_6bq_pair_later AS fixture;

  SELECT count(*) INTO before_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id =
    '6b750300-0000-4000-8000-000000000001'::uuid;
  SELECT count(*) INTO before_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.project_id =
    '6b750300-0000-4000-8000-000000000001'::uuid;

  -- Equal cutoff is a context regression, even though the two documents are
  -- otherwise byte-for-byte identical.
  same_cutoff_document := base_document;
  pair_result := app_private.assess_management_consent_ratio_report_pair_release_v1(
    same_cutoff_document, base_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR pair_result->'reason_codes' <>
      jsonb_build_array('release_lineage_context_changed')
  THEN
    RAISE EXCEPTION '6BQ same cutoff was not exactly blocked: %', pair_result;
  END IF;

  -- Keep the ISO-week boundaries fixed and move only the cutoff backward by
  -- one second.  This is still a valid protected document but is not a
  -- monotone successor.
  base_cutoff :=
    (base_document->'periods'->>'data_cutoff_utc')::timestamptz;
  earlier_cutoff_text := to_char(
    (base_cutoff - interval '1 second') AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  );
  earlier_cutoff_document := jsonb_set(
    base_document,
    '{periods,data_cutoff_utc}',
    to_jsonb(earlier_cutoff_text)
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    earlier_cutoff_document
  );
  pair_result := app_private.assess_management_consent_ratio_report_pair_release_v1(
    base_document, earlier_cutoff_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR pair_result->'reason_codes' <>
      jsonb_build_array('release_lineage_context_changed')
  THEN
    RAISE EXCEPTION '6BQ earlier cutoff was not exactly blocked: %', pair_result;
  END IF;

  monotone_cutoff_text := to_char(
    (base_cutoff + interval '1 second') AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  );
  monotone_document := jsonb_set(
    base_document,
    '{periods,data_cutoff_utc}',
    to_jsonb(monotone_cutoff_text)
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    monotone_document
  );

  pair_result := app_private.assess_management_consent_ratio_report_pair_release_v1(
    base_document, later_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR pair_result->'reason_codes' <> jsonb_build_array('no_shared_period')
  THEN
    RAISE EXCEPTION '6BQ no-shared-period pair was not exact: %', pair_result;
  END IF;

  -- A ratio mutation changes only the displayed ratio fields and remains
  -- validator-valid.  The pair assessor must return only its value-drift
  -- reason, not a privacy or period reason.
  ratio_changed_document := jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          monotone_document,
          '{period_results,0,ratio,yes_count}',
          '21'::jsonb
        ),
        '{period_results,0,ratio,no_count}',
        '20'::jsonb
      ),
      '{period_results,0,ratio,numerator}',
      '21'::jsonb
    ),
    '{period_results,0,ratio,denominator}',
    '41'::jsonb
  );
  ratio_changed_document := jsonb_set(
    ratio_changed_document,
    '{period_results,0,ratio,percentage_basis_points}',
    '5122'::jsonb
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    ratio_changed_document
  );
  pair_result := app_private.assess_management_consent_ratio_report_pair_release_v1(
    base_document, ratio_changed_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR pair_result->'reason_codes' <>
      jsonb_build_array('shared_displayed_value_changed')
  THEN
    RAISE EXCEPTION '6BQ ratio value drift was not exact: %', pair_result;
  END IF;

  -- Coverage is independently protected.  Turn one originally suppressed
  -- coverage cell into a valid displayed cell, then change only its displayed
  -- count so the ratio assertion cannot mask the coverage assertion.
  coverage_displayed_document := jsonb_set(
    jsonb_set(
      base_document,
      '{period_results,0,coverage,0,privacy_status}',
      to_jsonb('displayed'::text)
    ),
    '{period_results,0,coverage,0,value_count}',
    '10'::jsonb
  );
  coverage_changed_document := jsonb_set(
    jsonb_set(
      jsonb_set(
        monotone_document,
        '{period_results,0,coverage,0,privacy_status}',
        to_jsonb('displayed'::text)
      ),
      '{period_results,0,coverage,0,value_count}',
      '10'::jsonb
    ),
    '{period_results,0,coverage,0,value_count}', '11'::jsonb
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    coverage_displayed_document
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    coverage_changed_document
  );
  pair_result := app_private.assess_management_consent_ratio_report_pair_release_v1(
    coverage_displayed_document, coverage_changed_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR pair_result->'reason_codes' <>
      jsonb_build_array('shared_displayed_value_changed')
  THEN
    RAISE EXCEPTION '6BQ coverage value drift was not exact: %', pair_result;
  END IF;

  privacy_transition_document := jsonb_set(
    jsonb_set(
      monotone_document,
      '{period_results,0,coverage,0,privacy_status}',
      to_jsonb('suppressed'::text)
    ),
    '{period_results,0,coverage,0,value_count}',
    'null'::jsonb
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    privacy_transition_document
  );
  pair_result := app_private.assess_management_consent_ratio_report_pair_release_v1(
    coverage_displayed_document, privacy_transition_document
  );
  IF pair_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR pair_result->'reason_codes' <>
      jsonb_build_array('shared_privacy_status_changed')
  THEN
    RAISE EXCEPTION '6BQ privacy transition was not exact: %', pair_result;
  END IF;

  SELECT count(*) INTO after_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id =
    '6b750300-0000-4000-8000-000000000001'::uuid;
  SELECT count(*) INTO after_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.project_id =
    '6b750300-0000-4000-8000-000000000001'::uuid;
  IF after_snapshot_count <> before_snapshot_count
    OR after_attempt_count <> before_attempt_count
  THEN
    RAISE EXCEPTION '6BQ pure rollback pairs appended release state: %/% -> %/%',
      before_snapshot_count, before_attempt_count,
      after_snapshot_count, after_attempt_count;
  END IF;

  -- Every persisted attempt remains a metadata-only envelope; the pure pair
  -- paths above cannot introduce candidate values through a hidden audit row.
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
    WHERE attempt.project_id =
      '6b750300-0000-4000-8000-000000000001'::uuid
      AND attempt.result_document::text ~*
        '(protected_report|period_results|cells|contact_id|promotion_target_id|contributor|raw_answer|phone|email|place_name|latitude|longitude)'
  ) THEN
    RAISE EXCEPTION '6BQ rollback pair audit contains candidate values';
  END IF;
END
$assert_6bq_deterministic_pairs$;

-- Use the isolated cross-organization project to exercise the release seam's
-- actual cutoff and source-watermark guards without competing with the main
-- project's already-approved baseline.  The synthetic predecessor rows are
-- valid metadata-only snapshots; the two release calls below must append only
-- value-free blocked attempts.
DO $assert_6bq_release_rollbacks$
DECLARE
  watermark_candidate jsonb;
  future_candidate jsonb;
  watermark_snapshot_id uuid :=
    '6b750900-0000-4000-8000-000000000008'::uuid;
  watermark_request_id uuid :=
    '6b750900-0000-4000-8000-000000000009'::uuid;
  future_snapshot_id uuid :=
    '6b750900-0000-4000-8000-00000000000a'::uuid;
  future_request_id uuid :=
    '6b750900-0000-4000-8000-00000000000b'::uuid;
  watermark_release_request_id uuid :=
    '6b750900-0000-4000-8000-00000000000c'::uuid;
  cutoff_release_request_id uuid :=
    '6b750900-0000-4000-8000-00000000000d'::uuid;
  source_watermark bigint;
  watermark_cutoff timestamp with time zone;
  future_cutoff timestamp with time zone;
  time_zone_effective_from timestamp with time zone;
  release_result jsonb;
  before_snapshot_count bigint;
  before_attempt_count bigint;
  after_snapshot_count bigint;
  after_attempt_count bigint;
  audit_text text;
BEGIN
  SELECT fixture.document INTO STRICT watermark_candidate
  FROM fixture_6bq_watermark_candidate AS fixture;
  SELECT fixture.document INTO STRICT future_candidate
  FROM fixture_6bq_future_candidate AS fixture;
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    watermark_candidate
  );
  PERFORM app_private.validate_management_follow_up_consent_ratio_report_document_v1(
    future_candidate
  );

  watermark_cutoff :=
    (watermark_candidate->'periods'->>'data_cutoff_utc')::timestamptz;
  future_cutoff :=
    (future_candidate->'periods'->>'data_cutoff_utc')::timestamptz;
  SELECT version_row.effective_from_utc
  INTO STRICT time_zone_effective_from
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id =
      '6b750300-0000-4000-8000-000000000004'::uuid
    AND version_row.version_number = 1;

  INSERT INTO app_data.change_feed (
    app_user_id,
    workspace_id,
    project_id,
    aggregate_id,
    revision_number,
    change_type
  ) VALUES (
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750200-0000-4000-8000-000000000002'::uuid,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    '6bq-watermark-only-aggregate',
    1,
    'contact.submitted'
  ) RETURNING change_sequence INTO source_watermark;

  -- The first predecessor deliberately advertises one sequence beyond the
  -- committed source watermark.  Its cutoff is in the past, so the release
  -- call reaches the watermark comparison instead of the cutoff guard.
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
    watermark_snapshot_id,
    watermark_request_id,
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
    'contact_target_follow_up_consent_ratio_two_periods',
    1,
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    'UTC',
    watermark_cutoff,
    watermark_cutoff,
    NULL,
    source_watermark + 1,
    watermark_candidate
  );
  INSERT INTO app_private.management_follow_up_consent_report_release_attempts (
    release_request_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    reporting_time_zone_version_number,
    reporting_time_zone,
    reporting_time_zone_effective_from_utc,
    data_cutoff_utc,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    source_change_sequence,
    compared_snapshot_id,
    released_snapshot_id,
    shared_period_count,
    assessed_cell_count,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    watermark_request_id,
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750200-0000-4000-8000-000000000002'::uuid,
    '6b750400-0000-4000-8000-000000000002'::uuid,
    '6b750500-0000-4000-8000-000000000004'::uuid,
    '6b750600-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    watermark_cutoff,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    1,
    'UTC',
    time_zone_effective_from,
    watermark_cutoff,
    'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
    'contact_target_follow_up_consent_ratio_two_periods',
    1,
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    source_watermark + 1,
    NULL,
    watermark_snapshot_id,
    0,
    0,
    'approved_baseline',
    '[]'::jsonb,
    jsonb_build_object(
      'release_contract_id',
        'follow_up_consent_ratio_management_report_snapshot_release_v1',
      'release_request_id', watermark_request_id,
      'project_id',
        '6b750300-0000-4000-8000-000000000004'::uuid,
      'release_lineage_id',
        'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
      'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
      'report_version', 1,
      'query_fingerprint',
        'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
      'reporting_time_zone_version_number', 1,
      'reporting_time_zone', 'UTC',
      'data_cutoff_utc', to_char(
        watermark_cutoff AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', source_watermark + 1,
      'compared_snapshot_id', NULL,
      'released_snapshot_id', watermark_snapshot_id,
      'shared_period_count', 0,
      'assessed_cell_count', 0,
      'result_status', 'approved_baseline',
      'reason_codes', '[]'::jsonb
    )
  );

  SELECT count(*) INTO before_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id =
    '6b750300-0000-4000-8000-000000000004'::uuid;
  SELECT count(*) INTO before_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.project_id =
    '6b750300-0000-4000-8000-000000000004'::uuid;
  release_result := app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    watermark_release_request_id,
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR release_result->'reason_codes' <>
      jsonb_build_array('release_source_watermark_regressed')
    OR release_result->>'released_snapshot_id' IS NOT NULL
    OR release_result ? 'protected_report'
    OR release_result ? 'period_results'
    OR release_result ? 'cells'
  THEN
    RAISE EXCEPTION '6BQ watermark regression was not exact and value-free: %',
      release_result;
  END IF;
  SELECT count(*) INTO after_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id =
    '6b750300-0000-4000-8000-000000000004'::uuid;
  SELECT count(*) INTO after_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.project_id =
    '6b750300-0000-4000-8000-000000000004'::uuid;
  IF after_snapshot_count <> before_snapshot_count
    OR after_attempt_count <> before_attempt_count + 1
  THEN
    RAISE EXCEPTION '6BQ watermark rollback wrote unexpected history: %/% -> %/%',
      before_snapshot_count, before_attempt_count,
      after_snapshot_count, after_attempt_count;
  END IF;
  SELECT attempt.result_document::text INTO STRICT audit_text
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id = watermark_release_request_id;
  IF audit_text ~* '(protected_report|period_results|cells|contact_id|promotion_target_id|contributor|raw_answer|phone|email|place_name|latitude|longitude)'
  THEN
    RAISE EXCEPTION '6BQ watermark blocked attempt leaked candidate values: %',
      audit_text;
  END IF;

  -- A future predecessor is the deterministic earlier-cutoff release case.
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
    future_snapshot_id,
    future_request_id,
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
    'contact_target_follow_up_consent_ratio_two_periods',
    1,
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    'UTC',
    future_cutoff,
    future_cutoff,
    NULL,
    source_watermark,
    future_candidate
  );
  INSERT INTO app_private.management_follow_up_consent_report_release_attempts (
    release_request_id,
    requested_by_app_user_id,
    organization_workspace_id,
    organization_membership_id,
    project_membership_id,
    capability_grant_id,
    capability_id,
    authorization_reference_at_utc,
    project_id,
    reporting_time_zone_version_number,
    reporting_time_zone,
    reporting_time_zone_effective_from_utc,
    data_cutoff_utc,
    release_lineage_id,
    report_id,
    report_version,
    query_fingerprint,
    source_change_sequence,
    compared_snapshot_id,
    released_snapshot_id,
    shared_period_count,
    assessed_cell_count,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    future_request_id,
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750200-0000-4000-8000-000000000002'::uuid,
    '6b750400-0000-4000-8000-000000000002'::uuid,
    '6b750500-0000-4000-8000-000000000004'::uuid,
    '6b750600-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    future_cutoff,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    1,
    'UTC',
    time_zone_effective_from,
    future_cutoff,
    'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
    'contact_target_follow_up_consent_ratio_two_periods',
    1,
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    source_watermark,
    NULL,
    future_snapshot_id,
    0,
    0,
    'approved_baseline',
    '[]'::jsonb,
    jsonb_build_object(
      'release_contract_id',
        'follow_up_consent_ratio_management_report_snapshot_release_v1',
      'release_request_id', future_request_id,
      'project_id',
        '6b750300-0000-4000-8000-000000000004'::uuid,
      'release_lineage_id',
        'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
      'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
      'report_version', 1,
      'query_fingerprint',
        'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
      'reporting_time_zone_version_number', 1,
      'reporting_time_zone', 'UTC',
      'data_cutoff_utc', to_char(
        future_cutoff AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', source_watermark,
      'compared_snapshot_id', NULL,
      'released_snapshot_id', future_snapshot_id,
      'shared_period_count', 0,
      'assessed_cell_count', 0,
      'result_status', 'approved_baseline',
      'reason_codes', '[]'::jsonb
    )
  );
  release_result := app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    cutoff_release_request_id,
    '6b750100-0000-4000-8000-000000000004'::uuid,
    '6b750300-0000-4000-8000-000000000004'::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  );
  IF release_result->>'result_status' IS DISTINCT FROM 'blocked'
    OR release_result->'reason_codes' <>
      jsonb_build_array('release_cutoff_not_advanced')
    OR release_result->>'released_snapshot_id' IS NOT NULL
    OR release_result ? 'protected_report'
    OR release_result ? 'period_results'
    OR release_result ? 'cells'
  THEN
    RAISE EXCEPTION '6BQ earlier cutoff was not exact and value-free: %',
      release_result;
  END IF;
  SELECT attempt.result_document::text INTO STRICT audit_text
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id = cutoff_release_request_id;
  IF audit_text ~* '(protected_report|period_results|cells|contact_id|promotion_target_id|contributor|raw_answer|phone|email|place_name|latitude|longitude)'
  THEN
    RAISE EXCEPTION '6BQ cutoff blocked attempt leaked candidate values: %',
      audit_text;
  END IF;
END
$assert_6bq_release_rollbacks$;

-- Release authorization is a separate contract from candidate visibility.
-- These calls must fail before they can append an attempt or snapshot, and
-- their errors must not carry any protected candidate fields.
DO $assert_6bq_release_authorization_negatives$
DECLARE
  baseline_request_id uuid :=
    '6b750900-0000-4000-8000-000000000001'::uuid;
  unknown_request_id uuid :=
    '6b750900-0000-4000-8000-00000000000e'::uuid;
  missing_membership_request_id uuid :=
    '6b750900-0000-4000-8000-00000000000f'::uuid;
  view_only_request_id uuid :=
    '6b750900-0000-4000-8000-000000000010'::uuid;
  failure_sqlstate text;
  failure_message text;
  before_attempt_count bigint;
  after_attempt_count bigint;
  before_snapshot_count bigint;
  after_snapshot_count bigint;
BEGIN
  -- The same request cannot change its canonical report version.  Version 2
  -- is rejected before authorization and therefore cannot touch release state.
  SELECT count(*) INTO before_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id = baseline_request_id;
  SELECT count(*) INTO before_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id = baseline_request_id;
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      baseline_request_id,
      '6b750100-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000001'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods',
      2
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ canonical request drift was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '22023'
    OR failure_message IS DISTINCT FROM
      'invalid follow-up consent ratio report release request'
    OR failure_message ~* (
      '(protected_report|period_results|cells|contact_id|'
      || 'promotion_target_id|raw_answer|phone|email|place_name|latitude|longitude)'
    )
  THEN
    RAISE EXCEPTION '6BQ canonical request drift failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;
  SELECT count(*) INTO after_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id = baseline_request_id;
  SELECT count(*) INTO after_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id = baseline_request_id;
  IF after_attempt_count <> before_attempt_count
    OR after_snapshot_count <> before_snapshot_count
  THEN
    RAISE EXCEPTION '6BQ canonical request drift wrote release state';
  END IF;

  -- The same request UUID cannot move to another project, even when the
  -- requesting actor is authorized in both project contexts.
  SELECT count(*) INTO before_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id = baseline_request_id;
  SELECT count(*) INTO before_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id = baseline_request_id;
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      baseline_request_id,
      '6b750100-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000002'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods',
      1
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ cross-project request reuse was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '22023'
    OR failure_message IS DISTINCT FROM
      'follow-up consent ratio report release idempotency conflict'
    OR failure_message ~* (
      '(protected_report|period_results|cells|contact_id|'
      || 'promotion_target_id|raw_answer|phone|email|place_name|latitude|longitude)'
    )
  THEN
    RAISE EXCEPTION '6BQ cross-project reuse failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;
  SELECT count(*) INTO after_attempt_count
  FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
  WHERE attempt.release_request_id = baseline_request_id;
  SELECT count(*) INTO after_snapshot_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id = baseline_request_id;
  IF after_attempt_count <> before_attempt_count
    OR after_snapshot_count <> before_snapshot_count
  THEN
    RAISE EXCEPTION '6BQ cross-project request reuse wrote release state';
  END IF;

  -- An unknown actor must not turn an otherwise unknown request UUID into a
  -- value-bearing attempt or snapshot.
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      unknown_request_id,
      '6b750100-0000-4000-8000-000000009999'::uuid,
      '6b750300-0000-4000-8000-000000000001'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods',
      1
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ unknown actor release was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '42501'
    OR failure_message IS DISTINCT FROM
      'management report authorization forbidden'
    OR failure_message ~* (
      '(protected_report|period_results|cells|contact_id|'
      || 'promotion_target_id|raw_answer|phone|email|place_name|latitude|longitude)'
    )
  THEN
    RAISE EXCEPTION '6BQ unknown actor failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
    WHERE attempt.release_request_id = unknown_request_id
  ) OR EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.release_request_id = unknown_request_id
  ) THEN
    RAISE EXCEPTION '6BQ unknown actor wrote release state';
  END IF;

  -- An active user with no organization/project membership fails closed at
  -- the shared authorization resolver.
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      missing_membership_request_id,
      '6b750100-0000-4000-8000-000000000003'::uuid,
      '6b750300-0000-4000-8000-000000000001'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods',
      1
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ missing-membership release was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '42501'
    OR failure_message IS DISTINCT FROM
      'management report authorization forbidden'
    OR failure_message ~* (
      '(protected_report|period_results|cells|contact_id|'
      || 'promotion_target_id|raw_answer|phone|email|place_name|latitude|longitude)'
    )
  THEN
    RAISE EXCEPTION '6BQ missing membership failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
    WHERE attempt.release_request_id = missing_membership_request_id
  ) OR EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.release_request_id = missing_membership_request_id
  ) THEN
    RAISE EXCEPTION '6BQ missing membership wrote release state';
  END IF;

  -- A valid membership with only the neighboring read capability is still
  -- forbidden from entering the 6BQ release contract.
  failure_sqlstate := NULL;
  failure_message := NULL;
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      view_only_request_id,
      '6b750100-0000-4000-8000-000000000002'::uuid,
      '6b750300-0000-4000-8000-000000000003'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods',
      1
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ view-only release was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '42501'
    OR failure_message IS DISTINCT FROM
      'management report authorization forbidden'
    OR failure_message ~* (
      '(protected_report|period_results|cells|contact_id|'
      || 'promotion_target_id|raw_answer|phone|email|place_name|latitude|longitude)'
    )
  THEN
    RAISE EXCEPTION '6BQ view-only capability failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_report_release_attempts AS attempt
    WHERE attempt.release_request_id = view_only_request_id
  ) OR EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.release_request_id = view_only_request_id
  ) THEN
    RAISE EXCEPTION '6BQ view-only capability wrote release state';
  END IF;
END
$assert_6bq_release_authorization_negatives$;

-- A request UUID claimed by another report family cannot be reused. The claim
-- ledger and approved history are append-only.
INSERT INTO app_private.management_report_release_request_claims (
  release_request_id, release_family_id
)
VALUES (
  '6b750900-0000-4000-8000-000000000005'::uuid,
  'channel_management_report_snapshot_release'
);
DO $assert_cross_family$
DECLARE
  rejected boolean := false;
BEGIN
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      '6b750900-0000-4000-8000-000000000005'::uuid,
      '6b750100-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000001'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods', 1
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION '6BQ cross-family request claim was reused';
  END IF;
END
$assert_cross_family$;

DO $assert_claim_immutable$
BEGIN
  BEGIN
    UPDATE app_private.management_report_release_request_claims
    SET release_family_id = 'follow_up_consent_ratio_management_report_snapshot_release'
    WHERE release_request_id =
      '6b750900-0000-4000-8000-000000000005'::uuid;
    RAISE EXCEPTION '6BQ claim ledger accepted UPDATE';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_report_release_request_claims
    WHERE release_request_id =
      '6b750900-0000-4000-8000-000000000005'::uuid;
    RAISE EXCEPTION '6BQ claim ledger accepted DELETE';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END
$assert_claim_immutable$;

DO $assert_history_immutable$
DECLARE
  baseline_id uuid;
BEGIN
  SELECT (fixture.document->>'released_snapshot_id')::uuid
  INTO STRICT baseline_id
  FROM fixture_6bq_baseline AS fixture;
  BEGIN
    UPDATE app_private.management_report_snapshots
    SET released_at_utc = released_at_utc + interval '1 second'
    WHERE snapshot_id = baseline_id;
    RAISE EXCEPTION '6BQ snapshot accepted UPDATE';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_report_snapshots
    WHERE snapshot_id = baseline_id;
    RAISE EXCEPTION '6BQ snapshot accepted DELETE';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    UPDATE app_private.management_follow_up_consent_report_release_attempts
    SET result_status = 'blocked'
    WHERE release_request_id =
      '6b750900-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6BQ release attempt accepted UPDATE';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    DELETE FROM app_private.management_follow_up_consent_report_release_attempts
    WHERE release_request_id =
      '6b750900-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6BQ release attempt accepted DELETE';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END
$assert_history_immutable$;

-- Cross-family writer RLS must not expose or insert a 6BQ snapshot in the
-- shared physical table.
CREATE TEMP TABLE fixture_6bq_snapshot_copy ON COMMIT DROP AS
SELECT snapshot.*
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.release_request_id =
  '6b750900-0000-4000-8000-000000000001'::uuid;
GRANT SELECT ON fixture_6bq_snapshot_copy
  TO tongxingzhe_management_current_city_snapshot_release_writer;
SET LOCAL ROLE tongxingzhe_management_current_city_snapshot_release_writer;
DO $assert_cross_writer$
DECLARE
  visible_count bigint;
  failure_sqlstate text;
BEGIN
  SELECT count(*) INTO visible_count
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.release_request_id =
    '6b750900-0000-4000-8000-000000000001'::uuid;
  IF visible_count <> 0 THEN
    RAISE EXCEPTION '6BQ current-city writer can read consent snapshot';
  END IF;
  BEGIN
    INSERT INTO app_private.management_report_snapshots (
      snapshot_id, release_request_id, created_by_app_user_id, project_id,
      release_lineage_id, report_id, report_version, query_fingerprint,
      reporting_time_zone, data_cutoff_utc, released_at_utc,
      previous_snapshot_id, source_change_sequence, protected_report
    )
    SELECT gen_random_uuid(),
           '6b750900-0000-4000-8000-000000000011'::uuid,
           copy.created_by_app_user_id,
           copy.project_id,
           copy.release_lineage_id,
           copy.report_id,
           copy.report_version,
           copy.query_fingerprint,
           copy.reporting_time_zone,
           copy.data_cutoff_utc,
           copy.released_at_utc,
           copy.previous_snapshot_id,
           copy.source_change_sequence,
           copy.protected_report
    FROM fixture_6bq_snapshot_copy AS copy;
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ current-city writer inserted consent snapshot';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS failure_sqlstate = RETURNED_SQLSTATE;
  END;
  IF failure_sqlstate IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION '6BQ cross-writer RLS failed with SQLSTATE %',
      failure_sqlstate;
  END IF;
END
$assert_cross_writer$;
RESET ROLE;

-- Revocation and timezone changes are checked after the valid history exists;
-- no blocked request may create a second snapshot or an attempt with values.
UPDATE app_data.management_report_capability_grants
SET inactive_from_utc = clock.fixture_now_utc
FROM fixture_6bq_clock AS clock
WHERE capability_grant_id =
  '6b750600-0000-4000-8000-000000000001'::uuid;
DO $assert_revoked$
DECLARE
  failure_sqlstate text;
  failure_message text;
BEGIN
  BEGIN
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      '6b750900-0000-4000-8000-000000000006'::uuid,
      '6b750100-0000-4000-8000-000000000001'::uuid,
      '6b750300-0000-4000-8000-000000000001'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods', 1
    );
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = '6BQ revoked capability was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      failure_sqlstate = RETURNED_SQLSTATE,
      failure_message = MESSAGE_TEXT;
  END;
  IF failure_sqlstate IS DISTINCT FROM '42501'
    OR failure_message IS DISTINCT FROM
      'management report authorization forbidden'
  THEN
    RAISE EXCEPTION '6BQ revoked capability failed unexpectedly: %/%',
      failure_sqlstate, failure_message;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_report_release_attempts
    WHERE release_request_id =
      '6b750900-0000-4000-8000-000000000006'::uuid
  ) THEN
    RAISE EXCEPTION '6BQ revoked request wrote release history';
  END IF;
END
$assert_revoked$;

-- The fixture also proves that a new effective reporting-time-zone revision is
-- a lineage break, not a silent successor.
INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '6b750600-0000-4000-8000-000000000005'::uuid,
  '6b750500-0000-4000-8000-000000000001'::uuid,
  'release_management_reports',
  clock.fixture_now_utc,
  NULL
FROM fixture_6bq_clock AS clock;
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b750700-0000-4000-8000-000000000004'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  1,
  'America/Chicago',
  clock.fixture_now_utc - interval '8 days'
)
FROM fixture_6bq_clock AS clock;

CREATE TEMP TABLE fixture_6bq_timezone_blocked ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b750900-0000-4000-8000-000000000007'::uuid,
  '6b750100-0000-4000-8000-000000000001'::uuid,
  '6b750300-0000-4000-8000-000000000001'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;
DO $assert_timezone_blocked$
DECLARE
  document jsonb;
BEGIN
  SELECT fixture.document INTO STRICT document
  FROM fixture_6bq_timezone_blocked AS fixture;
  IF document->>'result_status' IS DISTINCT FROM 'blocked'
    OR NOT (document->'reason_codes' ? 'release_time_zone_revision_changed')
    OR document->>'released_snapshot_id' IS NOT NULL
    OR document ? 'protected_report'
    OR document ? 'period_results'
  THEN
    RAISE EXCEPTION '6BQ timezone revision did not fail closed: %', document;
  END IF;
END
$assert_timezone_blocked$;

ROLLBACK;
