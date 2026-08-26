-- Synthetic rollback fixture for Slice 6BP.
--
-- This fixture exercises the private, organization-scoped candidate only.
-- UUIDs use the legal 6bf prefix; temporary objects use the 6bpf mnemonic.
-- Committed rows from the concurrency check use a different namespace.  A single
-- transaction timestamp is copied into fixture_6bpf_clock so all hierarchy
-- ranges and report periods have stable parent/child boundaries on restore.

\set ON_ERROR_STOP on

BEGIN;

-- All period arithmetic below is evaluated in UTC.  This keeps the fixture
-- independent of the runner session's default time zone.
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6bpf_clock ON COMMIT DROP AS
SELECT clock_value AS fixture_now_utc,
       date_trunc('week', clock_value) AS current_iso_week_start_utc,
       date_trunc('week', clock_value) - interval '7 days'
         AS current_period_start_utc,
       date_trunc('week', clock_value) - interval '14 days'
         AS previous_period_start_utc,
       date_trunc('week', clock_value) + interval '1 hour'
         AS report_cutoff_utc
FROM (SELECT transaction_timestamp() AS clock_value) AS stable_clock;

GRANT SELECT ON fixture_6bpf_clock
  TO tongxingzhe_management_follow_up_consent_ratio_reader;

-- The actor has release capability for the target project.  Other users and
-- projects below deliberately exercise the authorization resolver rather
-- than passing caller-supplied membership or capability provenance.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6bf01000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000005'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000006'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000007'::uuid, 'active'),
  ('6bf01000-0000-4000-8000-000000000008'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id
)
VALUES
  (
    '6bf02000-0000-4000-8000-000000000001'::uuid,
    'organization',
    '6BP candidate organization one',
    NULL
  ),
  (
    '6bf02000-0000-4000-8000-000000000002'::uuid,
    'organization',
    '6BP candidate organization two',
    NULL
  ),
  (
    '6bf02000-0000-4000-8000-000000000003'::uuid,
    'personal',
    '6BP candidate personal workspace',
    '6bf01000-0000-4000-8000-000000000008'::uuid
  ),
  (
    '6bf02000-0000-4000-8000-000000000004'::uuid,
    'organization',
    '6BP candidate deleted organization',
    NULL
  );

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
)
VALUES
  (
    '6bf03000-0000-4000-8000-000000000001'::uuid,
    '6bf02000-0000-4000-8000-000000000001'::uuid,
    '6BP enabled organization project',
    'active',
    false
  ),
  (
    '6bf03000-0000-4000-8000-000000000002'::uuid,
    '6bf02000-0000-4000-8000-000000000001'::uuid,
    '6BP view-only project',
    'active',
    false
  ),
  (
    '6bf03000-0000-4000-8000-000000000003'::uuid,
    '6bf02000-0000-4000-8000-000000000001'::uuid,
    '6BP archive candidate project',
    'active',
    false
  ),
  (
    '6bf03000-0000-4000-8000-000000000004'::uuid,
    '6bf02000-0000-4000-8000-000000000002'::uuid,
    '6BP cross-organization project',
    'active',
    false
  ),
  (
    '6bf03000-0000-4000-8000-000000000005'::uuid,
    '6bf02000-0000-4000-8000-000000000003'::uuid,
    '6BP personal project',
    'active',
    true
  ),
  (
    '6bf03000-0000-4000-8000-000000000006'::uuid,
    '6bf02000-0000-4000-8000-000000000004'::uuid,
    '6BP deleted workspace project',
    'active',
    false
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
)
VALUES
  (
    '6bf03500-0000-4000-8000-000000000001'::uuid,
    '6bf03000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '6bf03500-0000-4000-8000-000000000002'::uuid,
    '6bf03000-0000-4000-8000-000000000002'::uuid,
    1,
    'published',
    true
  ),
  (
    '6bf03500-0000-4000-8000-000000000003'::uuid,
    '6bf03000-0000-4000-8000-000000000003'::uuid,
    1,
    'published',
    true
  ),
  (
    '6bf03500-0000-4000-8000-000000000004'::uuid,
    '6bf03000-0000-4000-8000-000000000004'::uuid,
    1,
    'published',
    true
  ),
  (
    '6bf03500-0000-4000-8000-000000000005'::uuid,
    '6bf03000-0000-4000-8000-000000000005'::uuid,
    1,
    'published',
    true
  ),
  (
    '6bf03500-0000-4000-8000-000000000006'::uuid,
    '6bf03000-0000-4000-8000-000000000006'::uuid,
    1,
    'published',
    true
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership_id,
       workspace_id,
       app_user_id,
       clock.fixture_now_utc - interval '365 days',
       inactive_from_utc
FROM (
  VALUES
    (
      '6bf04000-0000-4000-8000-000000000001'::uuid,
      '6bf02000-0000-4000-8000-000000000001'::uuid,
      '6bf01000-0000-4000-8000-000000000001'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf04000-0000-4000-8000-000000000002'::uuid,
      '6bf02000-0000-4000-8000-000000000001'::uuid,
      '6bf01000-0000-4000-8000-000000000005'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf04000-0000-4000-8000-000000000003'::uuid,
      '6bf02000-0000-4000-8000-000000000001'::uuid,
      '6bf01000-0000-4000-8000-000000000006'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf04000-0000-4000-8000-000000000004'::uuid,
      '6bf02000-0000-4000-8000-000000000001'::uuid,
      '6bf01000-0000-4000-8000-000000000007'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf04000-0000-4000-8000-000000000005'::uuid,
      '6bf02000-0000-4000-8000-000000000004'::uuid,
      '6bf01000-0000-4000-8000-000000000001'::uuid,
      NULL::timestamptz
    )
) AS membership(membership_id, workspace_id, app_user_id, inactive_from_utc)
CROSS JOIN fixture_6bpf_clock AS clock;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership_id,
       organization_membership_id,
       project_id,
       clock.fixture_now_utc - interval '365 days',
       inactive_from_utc
FROM (
  VALUES
    (
      '6bf05000-0000-4000-8000-000000000001'::uuid,
      '6bf04000-0000-4000-8000-000000000001'::uuid,
      '6bf03000-0000-4000-8000-000000000001'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf05000-0000-4000-8000-000000000002'::uuid,
      '6bf04000-0000-4000-8000-000000000002'::uuid,
      '6bf03000-0000-4000-8000-000000000002'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf05000-0000-4000-8000-000000000003'::uuid,
      '6bf04000-0000-4000-8000-000000000003'::uuid,
      '6bf03000-0000-4000-8000-000000000001'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf05000-0000-4000-8000-000000000004'::uuid,
      '6bf04000-0000-4000-8000-000000000004'::uuid,
      '6bf03000-0000-4000-8000-000000000001'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf05000-0000-4000-8000-000000000005'::uuid,
      '6bf04000-0000-4000-8000-000000000001'::uuid,
      '6bf03000-0000-4000-8000-000000000003'::uuid,
      NULL::timestamptz
    ),
    (
      '6bf05000-0000-4000-8000-000000000006'::uuid,
      '6bf04000-0000-4000-8000-000000000005'::uuid,
      '6bf03000-0000-4000-8000-000000000006'::uuid,
      NULL::timestamptz
    )
) AS membership(
  membership_id,
  organization_membership_id,
  project_id,
  inactive_from_utc
)
CROSS JOIN fixture_6bpf_clock AS clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT grant_id,
       project_membership_id,
       capability_id,
       CASE
         WHEN grant_id = '6bf06000-0000-4000-8000-000000000005'::uuid
           THEN clock.fixture_now_utc - interval '30 days'
         ELSE clock.fixture_now_utc - interval '365 days'
       END,
       CASE
         WHEN grant_id = '6bf06000-0000-4000-8000-000000000005'::uuid
           THEN clock.fixture_now_utc - interval '1 day'
         ELSE NULL
       END
FROM (
  VALUES
    (
      '6bf06000-0000-4000-8000-000000000001'::uuid,
      '6bf05000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'::text
    ),
    (
      '6bf06000-0000-4000-8000-000000000002'::uuid,
      '6bf05000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6bf06000-0000-4000-8000-000000000003'::uuid,
      '6bf05000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6bf06000-0000-4000-8000-000000000004'::uuid,
      '6bf05000-0000-4000-8000-000000000003'::uuid,
      'release_management_reports'::text
    ),
    (
      '6bf06000-0000-4000-8000-000000000005'::uuid,
      '6bf05000-0000-4000-8000-000000000004'::uuid,
      'release_management_reports'::text
    ),
    (
      '6bf06000-0000-4000-8000-000000000006'::uuid,
      '6bf05000-0000-4000-8000-000000000005'::uuid,
      'release_management_reports'::text
    ),
    (
      '6bf06000-0000-4000-8000-000000000007'::uuid,
      '6bf05000-0000-4000-8000-000000000006'::uuid,
      'release_management_reports'::text
    )
) AS grant_row(grant_id, project_membership_id, capability_id)
CROSS JOIN fixture_6bpf_clock AS clock;

-- Establish the valid authorization hierarchy first; the inactive-account
-- negative case is created only after its historical membership chain exists.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6bf01000-0000-4000-8000-000000000006'::uuid;

-- Configure the main project and the future archive project while both are
-- active.  The first candidate read below is intentionally before this
-- configuration and therefore must return not_enabled without source data.
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_ratio_reader;

CREATE TEMP TABLE fixture_6bpf_initial_candidate ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000001'::uuid,
  'UTC',
  clock.report_cutoff_utc
) AS document
FROM fixture_6bpf_clock AS clock;

RESET ROLE;
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;

SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6bf07000-0000-4000-8000-000000000001'::uuid,
  0,
  true
);

SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000003'::uuid,
  'follow_up_consent_ratio@1',
  '6bf07000-0000-4000-8000-000000000002'::uuid,
  0,
  true
);

SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000006'::uuid,
  'follow_up_consent_ratio@1',
  '6bf07000-0000-4000-8000-000000000003'::uuid,
  0,
  true
);

RESET ROLE;

-- The deleted-workspace project was configured while valid, then tombstoned;
-- its retained membership and capability must not revive authorization.
UPDATE app_data.workspaces AS workspace_row
SET deleted_at = clock.fixture_now_utc
FROM fixture_6bpf_clock AS clock
WHERE workspace_row.workspace_id =
  '6bf02000-0000-4000-8000-000000000004'::uuid;

DO $assert_not_enabled_before_source$
DECLARE
  document jsonb := (
    SELECT fixture.document FROM fixture_6bpf_initial_candidate AS fixture
  );
BEGIN
  IF document->>'status' <> 'not_enabled'
    OR document ? 'report_id'
    OR document ? 'periods'
    OR document ? 'period_results'
    OR document ? 'ratio'
    OR document ? 'coverage'
    OR document ? 'cells'
  THEN
    RAISE EXCEPTION
      'unconfigured management candidate leaked report data: %', document;
  END IF;
END
$assert_not_enabled_before_source$;

-- Ten links per status and period are spread across three contributors as
-- 4/3/3.  The extra two links on one contact prove that the statistical unit
-- is the link rather than the contact.  All timestamps derive from the one
-- fixture clock and stay before the database-owned cutoff.
CREATE TEMP TABLE fixture_6bpf_targets (
  target_number integer PRIMARY KEY,
  promotion_target_id uuid NOT NULL UNIQUE
) ON COMMIT DROP;

INSERT INTO fixture_6bpf_targets (target_number, promotion_target_id)
SELECT target_number,
       format(
         '6bf08000-0000-4000-8000-%s',
         lpad(target_number::text, 12, '0')
       )::uuid
FROM generate_series(1, 10) AS target_number;

INSERT INTO app_data.promotion_targets (
  promotion_target_id,
  workspace_id,
  target_type,
  display_name,
  phone,
  email,
  created_by_app_user_id
)
SELECT target.promotion_target_id,
       '6bf02000-0000-4000-8000-000000000001'::uuid,
       'person',
       '6BP synthetic target ' || target.target_number,
       NULL,
       NULL,
       '6bf01000-0000-4000-8000-000000000001'::uuid
FROM fixture_6bpf_targets AS target;

CREATE TEMP TABLE fixture_6bpf_link_rows (
  contact_id text NOT NULL,
  app_user_id uuid NOT NULL,
  project_id uuid NOT NULL,
  questionnaire_version_id uuid NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  first_submitted_at_utc timestamptz NOT NULL,
  promotion_target_id uuid NOT NULL,
  revision_number integer NOT NULL DEFAULT 1,
  follow_up_consent text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6bpf_link_rows (
  contact_id,
  app_user_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  first_submitted_at_utc,
  promotion_target_id,
  follow_up_consent
)
SELECT format(
         '6bpf-contact-%s-%s-%s',
         period.period_key,
         consent.consent_state,
         series_number
       ),
       CASE ((series_number - 1) % 3)
         WHEN 0 THEN '6bf01000-0000-4000-8000-000000000002'::uuid
         WHEN 1 THEN '6bf01000-0000-4000-8000-000000000003'::uuid
         ELSE '6bf01000-0000-4000-8000-000000000004'::uuid
       END,
       '6bf03000-0000-4000-8000-000000000001'::uuid,
       '6bf03500-0000-4000-8000-000000000001'::uuid,
       period.period_start_utc
         + interval '2 days'
         + (consent.sort_order * 2 + series_number) * interval '1 minute',
       period.period_start_utc
         + interval '2 days'
         + (consent.sort_order * 2 + series_number) * interval '1 minute'
         + interval '1 minute',
       target.promotion_target_id,
       consent.consent_state
FROM (
  SELECT 'previous'::text AS period_key,
         clock.previous_period_start_utc AS period_start_utc
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT 'current'::text,
         clock.current_period_start_utc
  FROM fixture_6bpf_clock AS clock
) AS period
CROSS JOIN (
  VALUES
    ('yes'::text, 0),
    ('no'::text, 1),
    ('unknown'::text, 2),
    ('refused'::text, 3),
    ('not_applicable'::text, 4)
) AS consent(consent_state, sort_order)
CROSS JOIN generate_series(1, 10) AS series_number
JOIN fixture_6bpf_targets AS target
  ON target.target_number = ((series_number - 1) % 10) + 1;

-- Two links on one contact are intentionally different target links but share
-- the same trusted contributor and current contact revision.
INSERT INTO fixture_6bpf_link_rows (
  contact_id,
  app_user_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  first_submitted_at_utc,
  promotion_target_id,
  follow_up_consent
)
SELECT '6bpf-contact-multi-previous-yes',
       '6bf01000-0000-4000-8000-000000000002'::uuid,
       '6bf03000-0000-4000-8000-000000000001'::uuid,
       '6bf03500-0000-4000-8000-000000000001'::uuid,
       clock.previous_period_start_utc + interval '3 days',
       clock.previous_period_start_utc + interval '3 days 1 minute',
       target.promotion_target_id,
       'yes'
FROM fixture_6bpf_clock AS clock
JOIN fixture_6bpf_targets AS target
  ON target.target_number IN (9, 10);

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
  interest_level,
  current_revision,
  lifecycle_status
)
SELECT DISTINCT ON (link.contact_id)
       link.contact_id,
       link.app_user_id,
       '6bf02000-0000-4000-8000-000000000001'::uuid,
       link.project_id,
       link.questionnaire_version_id,
       link.occurred_at_utc,
       'video_call',
       link.first_submitted_at_utc,
       'video_call',
       'not_applicable',
       1,
       2,
       1,
       'active'
FROM fixture_6bpf_link_rows AS link
ORDER BY link.contact_id, link.promotion_target_id;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT DISTINCT link.contact_id,
       1,
       link.app_user_id,
       'submitted',
       NULL,
       '{}'::jsonb
FROM fixture_6bpf_link_rows AS link;

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
)
SELECT link.contact_id,
       link.revision_number,
       link.promotion_target_id,
       NULL,
       link.follow_up_consent,
       false,
       true
FROM fixture_6bpf_link_rows AS link;

GRANT SELECT ON fixture_6bpf_link_rows
  TO tongxingzhe_management_follow_up_consent_ratio_reader;

-- Boundary and source-shape rows.  Only the left boundary is included.  The
-- right boundary, before-period row, post-cutoff submission, old revision,
-- voided contact and other-project row must stay out of the candidate.
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
  interest_level,
  current_revision,
  lifecycle_status
)
SELECT row_data.contact_id,
       '6bf01000-0000-4000-8000-000000000003'::uuid,
       '6bf02000-0000-4000-8000-000000000001'::uuid,
       row_data.project_id,
       row_data.questionnaire_version_id,
       row_data.occurred_at_utc,
       'UTC',
       row_data.first_submitted_at_utc,
       'video_call',
       'not_applicable',
       1,
       2,
       row_data.current_revision,
       row_data.lifecycle_status
FROM (
  SELECT '6bpf-left-boundary'::text AS contact_id,
         '6bf03000-0000-4000-8000-000000000001'::uuid AS project_id,
         '6bf03500-0000-4000-8000-000000000001'::uuid
           AS questionnaire_version_id,
         clock.previous_period_start_utc AS occurred_at_utc,
         clock.previous_period_start_utc + interval '1 minute'
           AS first_submitted_at_utc,
         1 AS current_revision,
         'active'::text AS lifecycle_status
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT '6bpf-right-boundary',
         '6bf03000-0000-4000-8000-000000000001'::uuid,
         '6bf03500-0000-4000-8000-000000000001'::uuid,
         clock.current_iso_week_start_utc,
         clock.current_iso_week_start_utc + interval '1 minute',
         1,
         'active'
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT '6bpf-before-period',
         '6bf03000-0000-4000-8000-000000000001'::uuid,
         '6bf03500-0000-4000-8000-000000000001'::uuid,
         clock.previous_period_start_utc - interval '1 minute',
         clock.previous_period_start_utc,
         1,
         'active'
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT '6bpf-after-cutoff',
         '6bf03000-0000-4000-8000-000000000001'::uuid,
         '6bf03500-0000-4000-8000-000000000001'::uuid,
         clock.current_period_start_utc + interval '1 day',
         clock.report_cutoff_utc + interval '1 minute',
         1,
         'active'
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT '6bpf-old-revision',
         '6bf03000-0000-4000-8000-000000000001'::uuid,
         '6bf03500-0000-4000-8000-000000000001'::uuid,
         clock.current_period_start_utc + interval '2 days',
         clock.current_period_start_utc + interval '2 days 1 minute',
         2,
         'active'
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT '6bpf-voided',
         '6bf03000-0000-4000-8000-000000000001'::uuid,
         '6bf03500-0000-4000-8000-000000000001'::uuid,
         clock.current_period_start_utc + interval '3 days',
         clock.current_period_start_utc + interval '3 days 1 minute',
         1,
         'voided'
  FROM fixture_6bpf_clock AS clock
  UNION ALL
  SELECT '6bpf-other-project',
         '6bf03000-0000-4000-8000-000000000002'::uuid,
         '6bf03500-0000-4000-8000-000000000002'::uuid,
         clock.current_period_start_utc + interval '4 days',
         clock.current_period_start_utc + interval '4 days 1 minute',
         1,
         'active'
  FROM fixture_6bpf_clock AS clock
) AS row_data
CROSS JOIN fixture_6bpf_clock AS clock;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
VALUES
  (
    '6bpf-left-boundary',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  ),
  (
    '6bpf-right-boundary',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  ),
  (
    '6bpf-before-period',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  ),
  (
    '6bpf-after-cutoff',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  ),
  (
    '6bpf-old-revision',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  ),
  (
    '6bpf-old-revision',
    2,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'corrected',
    'synthetic current revision',
    '{}'::jsonb
  ),
  (
    '6bpf-voided',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  ),
  (
    '6bpf-other-project',
    1,
    '6bf01000-0000-4000-8000-000000000003'::uuid,
    'submitted',
    NULL,
    '{}'::jsonb
  );

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
)
SELECT boundary.contact_id,
       boundary.revision_number,
       target.promotion_target_id,
       NULL,
       boundary.follow_up_consent,
       false,
       true
FROM (
  VALUES
    ('6bpf-left-boundary'::text, 1, 'yes'::text),
    ('6bpf-right-boundary'::text, 1, 'yes'::text),
    ('6bpf-before-period'::text, 1, 'yes'::text),
    ('6bpf-after-cutoff'::text, 1, 'yes'::text),
    ('6bpf-old-revision'::text, 1, 'yes'::text),
    ('6bpf-voided'::text, 1, 'yes'::text),
    ('6bpf-other-project'::text, 1, 'yes'::text)
) AS boundary(contact_id, revision_number, follow_up_consent)
JOIN fixture_6bpf_targets AS target
  ON target.target_number = 1;

-- A questionnaire answer, contact attempt and draft are separate source
-- units.  They remain in the transaction to make accidental source widening
-- visible to the executor assertions, but none has a contact-target link.
INSERT INTO app_data.contact_answers (
  contact_id,
  revision_number,
  question_id,
  answer_state,
  answer_type,
  boolean_value
)
VALUES (
  '6bpf-left-boundary',
  1,
  'follow_up_consent',
  'answered',
  'boolean',
  true
);

INSERT INTO app_data.contact_attempts (
  attempt_id,
  app_user_id,
  workspace_id,
  project_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel
)
SELECT '6bpf-contact-attempt',
       '6bf01000-0000-4000-8000-000000000002'::uuid,
       '6bf02000-0000-4000-8000-000000000001'::uuid,
       '6bf03000-0000-4000-8000-000000000001'::uuid,
       clock.current_period_start_utc + interval '5 days',
       'UTC',
       clock.current_period_start_utc + interval '5 days 1 minute',
       'video_call'
FROM fixture_6bpf_clock AS clock;

INSERT INTO app_data.contact_drafts (
  draft_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  created_at_utc,
  updated_at_utc,
  current_revision,
  source_device_id,
  content
)
SELECT '6bpf-contact-draft',
       '6bf01000-0000-4000-8000-000000000002'::uuid,
       '6bf02000-0000-4000-8000-000000000001'::uuid,
       '6bf03000-0000-4000-8000-000000000001'::uuid,
       '6bf03500-0000-4000-8000-000000000001'::uuid,
       clock.current_period_start_utc + interval '5 days',
       clock.current_period_start_utc + interval '5 days 1 minute',
       1,
       '6bpf-device',
       jsonb_build_object('followUpConsent', 'yes')
FROM fixture_6bpf_clock AS clock;

-- The privacy policy receives already aggregated, value-free contributions.
-- Each scenario is intentionally small and tests the disclosure gates before
-- the end-to-end executor.  `consent_state` is the fixed policy dimension;
-- contributors are opaque synthetic keys, never returned by the helper.
CREATE TEMP TABLE fixture_6bpf_policy_rows (
  scenario text NOT NULL,
  period_key text NOT NULL,
  consent_state text NOT NULL,
  contributor_key text NOT NULL,
  unit_count integer NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6bpf_policy_rows (
  scenario,
  period_key,
  consent_state,
  contributor_key,
  unit_count
)
SELECT 'safe',
       period.period_key,
       state.consent_state,
       contributor.contributor_key,
       contributor.unit_count
FROM (VALUES ('previous'::text), ('current'::text)) AS period(period_key)
CROSS JOIN (
  VALUES
    ('yes'::text),
    ('no'::text),
    ('unanswered'::text),
    ('refused'::text),
    ('not_applicable'::text)
) AS state(consent_state)
CROSS JOIN (
  VALUES
    ('contributor-a'::text, 4),
    ('contributor-b'::text, 3),
    ('contributor-c'::text, 3)
) AS contributor(contributor_key, unit_count);

INSERT INTO fixture_6bpf_policy_rows
SELECT 'yes_unsafe',
       row_data.period_key,
       row_data.consent_state,
       row_data.contributor_key,
       row_data.unit_count
FROM fixture_6bpf_policy_rows AS row_data
WHERE row_data.scenario = 'safe'
  AND NOT (
    row_data.period_key = 'current'
    AND row_data.consent_state = 'yes'
  );

INSERT INTO fixture_6bpf_policy_rows
VALUES
  ('yes_unsafe', 'current', 'yes', 'contributor-a', 3),
  ('yes_unsafe', 'current', 'yes', 'contributor-b', 3),
  ('yes_unsafe', 'current', 'yes', 'contributor-c', 3);

INSERT INTO fixture_6bpf_policy_rows
SELECT 'no_unsafe',
       row_data.period_key,
       row_data.consent_state,
       row_data.contributor_key,
       row_data.unit_count
FROM fixture_6bpf_policy_rows AS row_data
WHERE row_data.scenario = 'safe'
  AND NOT (
    row_data.period_key = 'current'
    AND row_data.consent_state = 'no'
  );

INSERT INTO fixture_6bpf_policy_rows
VALUES
  ('no_unsafe', 'current', 'no', 'contributor-a', 5),
  ('no_unsafe', 'current', 'no', 'contributor-b', 5);

INSERT INTO fixture_6bpf_policy_rows
SELECT 'dominant',
       row_data.period_key,
       row_data.consent_state,
       row_data.contributor_key,
       row_data.unit_count
FROM fixture_6bpf_policy_rows AS row_data
WHERE row_data.scenario = 'safe'
  AND NOT (
    row_data.period_key = 'current'
    AND row_data.consent_state = 'yes'
  );

INSERT INTO fixture_6bpf_policy_rows
VALUES
  ('dominant', 'current', 'yes', 'contributor-a', 6),
  ('dominant', 'current', 'yes', 'contributor-b', 2),
  ('dominant', 'current', 'yes', 'contributor-c', 2);

INSERT INTO fixture_6bpf_policy_rows
SELECT 'coverage_unsafe',
       row_data.period_key,
       row_data.consent_state,
       row_data.contributor_key,
       row_data.unit_count
FROM fixture_6bpf_policy_rows AS row_data
WHERE row_data.scenario = 'safe'
  AND NOT (
    row_data.period_key = 'current'
    AND row_data.consent_state = 'refused'
  );

INSERT INTO fixture_6bpf_policy_rows
VALUES
  ('coverage_unsafe', 'current', 'refused', 'contributor-a', 3),
  ('coverage_unsafe', 'current', 'refused', 'contributor-b', 3),
  ('coverage_unsafe', 'current', 'refused', 'contributor-c', 3);

INSERT INTO fixture_6bpf_policy_rows
SELECT 'zero_denominator',
       row_data.period_key,
       row_data.consent_state,
       row_data.contributor_key,
       row_data.unit_count
FROM fixture_6bpf_policy_rows AS row_data
WHERE row_data.scenario = 'safe'
  AND row_data.consent_state NOT IN ('yes', 'no');

INSERT INTO fixture_6bpf_policy_rows
SELECT 'half_boundary',
       period.period_key,
       state.consent_state,
       contributor.contributor_key,
       contributor.unit_count
FROM (VALUES ('previous'::text), ('current'::text)) AS period(period_key)
CROSS JOIN (
  VALUES
    ('yes'::text),
    ('no'::text),
    ('unanswered'::text),
    ('refused'::text),
    ('not_applicable'::text)
) AS state(consent_state)
CROSS JOIN (
  VALUES
    ('contributor-a'::text, 5),
    ('contributor-b'::text, 3),
    ('contributor-c'::text, 2)
) AS contributor(contributor_key, unit_count);

INSERT INTO fixture_6bpf_policy_rows
SELECT 'independent_periods',
       row_data.period_key,
       row_data.consent_state,
       row_data.contributor_key,
       row_data.unit_count
FROM fixture_6bpf_policy_rows AS row_data
WHERE row_data.scenario = 'safe'
  AND row_data.period_key = 'previous';

INSERT INTO fixture_6bpf_policy_rows
VALUES
  ('independent_periods', 'current', 'yes', 'contributor-a', 3),
  ('independent_periods', 'current', 'yes', 'contributor-b', 3),
  ('independent_periods', 'current', 'yes', 'contributor-c', 3),
  ('independent_periods', 'current', 'no', 'contributor-a', 5),
  ('independent_periods', 'current', 'no', 'contributor-b', 5),
  ('independent_periods', 'current', 'unanswered', 'contributor-a', 4),
  ('independent_periods', 'current', 'unanswered', 'contributor-b', 3),
  ('independent_periods', 'current', 'unanswered', 'contributor-c', 3),
  ('independent_periods', 'current', 'refused', 'contributor-a', 4),
  ('independent_periods', 'current', 'refused', 'contributor-b', 3),
  ('independent_periods', 'current', 'refused', 'contributor-c', 3),
  ('independent_periods', 'current', 'not_applicable', 'contributor-a', 4),
  ('independent_periods', 'current', 'not_applicable', 'contributor-b', 3),
  ('independent_periods', 'current', 'not_applicable', 'contributor-c', 3);

CREATE TEMP TABLE fixture_6bpf_policy_inputs ON COMMIT DROP AS
SELECT scenario,
       jsonb_agg(
         jsonb_build_object(
           'period_key', period_key,
           'consent_state', consent_state,
           'contributor_key', contributor_key,
           'unit_count', unit_count
         ) ORDER BY period_key, consent_state, contributor_key
       ) AS contributions
FROM fixture_6bpf_policy_rows
GROUP BY scenario;

GRANT SELECT ON fixture_6bpf_policy_inputs
  TO tongxingzhe_management_follow_up_consent_ratio_reader;

RESET ROLE;

DO $assert_policy_boundaries$
DECLARE
  unit_total integer;
  contributor_total integer;
  maximum_contribution integer;
BEGIN
  SELECT coalesce(sum(unit_count), 0), count(DISTINCT contributor_key)
    INTO unit_total, contributor_total
  FROM fixture_6bpf_policy_rows
  WHERE scenario = 'yes_unsafe'
    AND period_key = 'current'
    AND consent_state = 'yes';
  IF unit_total <> 9 OR contributor_total <> 3 THEN
    RAISE EXCEPTION
      'N=9 boundary fixture drifted: total %, contributors %',
      unit_total,
      contributor_total;
  END IF;

  SELECT coalesce(sum(unit_count), 0), count(DISTINCT contributor_key)
    INTO unit_total, contributor_total
  FROM fixture_6bpf_policy_rows
  WHERE scenario = 'no_unsafe'
    AND period_key = 'current'
    AND consent_state = 'no';
  IF unit_total <> 10 OR contributor_total <> 2 THEN
    RAISE EXCEPTION
      'N=10/P=2 boundary fixture drifted: total %, contributors %',
      unit_total,
      contributor_total;
  END IF;

  SELECT coalesce(sum(unit_count), 0), max(unit_count)
    INTO unit_total, maximum_contribution
  FROM fixture_6bpf_policy_rows
  WHERE scenario = 'dominant'
    AND period_key = 'current'
    AND consent_state = 'yes';
  IF unit_total <> 10 OR maximum_contribution <> 6 THEN
    RAISE EXCEPTION
      'N=10/M=6 boundary fixture drifted: total %, maximum %',
      unit_total,
      maximum_contribution;
  END IF;
END
$assert_policy_boundaries$;

DO $assert_view_only_fixture$
DECLARE
  has_view_only_hierarchy boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS organization_membership
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.organization_membership_id =
        organization_membership.organization_membership_id
    JOIN app_data.management_report_capability_grants AS capability_grant
      ON capability_grant.project_membership_id =
        project_membership.project_membership_id
    WHERE organization_membership.app_user_id =
      '6bf01000-0000-4000-8000-000000000005'::uuid
      AND project_membership.project_id =
        '6bf03000-0000-4000-8000-000000000002'::uuid
      AND capability_grant.capability_id = 'view_anonymous_analytics'
  ) INTO has_view_only_hierarchy;

  IF NOT has_view_only_hierarchy THEN
    RAISE EXCEPTION
      'view-only negative case lost its project membership or view grant';
  END IF;
END
$assert_view_only_fixture$;

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_ratio_reader;

DO $policy_fixture$
DECLARE
  policy_row record;
  protected_document jsonb;
  protected_result_type text;
  protected_text text;
  rejected boolean;
BEGIN
  SELECT pg_get_function_result(
    to_regprocedure(
      'app_private.protect_management_follow_up_consent_ratio_periods_v1(jsonb)'
    )
  ) INTO protected_result_type;

  FOR policy_row IN
    SELECT scenario, contributions
    FROM fixture_6bpf_policy_inputs
    ORDER BY scenario
  LOOP
    IF protected_result_type = 'jsonb' THEN
      EXECUTE
        'SELECT app_private.protect_management_follow_up_consent_ratio_periods_v1($1)'
      INTO protected_document
      USING policy_row.contributions;
    ELSE
      EXECUTE
        'SELECT coalesce(jsonb_agg(to_jsonb(protected_row)), ''[]''::jsonb) '
        || 'FROM app_private.protect_management_follow_up_consent_ratio_periods_v1($1) '
        || 'AS protected_row'
      INTO protected_document
      USING policy_row.contributions;
    END IF;

    protected_text := protected_document::text;
    IF protected_document IS NULL
      OR protected_text ~* '(6bpf|contributor_key|app_user_id|contact_id|target_id|membership|capability|phone|email|latitude|longitude)'
    THEN
      RAISE EXCEPTION
        'policy returned null or identifying source data for %: %',
        policy_row.scenario,
        protected_document;
    END IF;

    IF policy_row.scenario IN ('safe', 'half_boundary')
      AND protected_text !~* 'displayed'
    THEN
      RAISE EXCEPTION 'safe 10/3/5 policy case was not displayed: %',
        protected_document;
    END IF;

    IF policy_row.scenario IN (
      'yes_unsafe',
      'no_unsafe',
      'dominant',
      'coverage_unsafe',
      'zero_denominator',
      'independent_periods'
    )
      AND protected_text !~* 'suppressed'
    THEN
      RAISE EXCEPTION 'unsafe policy case did not fail closed (%): %',
        policy_row.scenario,
        protected_document;
    END IF;
  END LOOP;

  -- Strict shape, duplicate, and safe-integer failures must reject the whole
  -- helper call rather than silently dropping one malformed contribution.
  FOREACH protected_text IN ARRAY ARRAY[
    '[{"period_key":"current","consent_state":"yes","contributor_key":"a"}]',
    '[{"period_key":"current","consent_state":"future","contributor_key":"a","unit_count":1}]',
    '[{"period_key":"current","consent_state":"yes","contributor_key":"a","unit_count":0}]',
    '[{"period_key":"current","consent_state":"yes","contributor_key":"a","unit_count":1,"extra":true}]',
    '[{"period_key":"current","consent_state":"yes","contributor_key":"a","unit_count":1},{"period_key":"current","consent_state":"yes","contributor_key":"a","unit_count":1}]',
    '[{"period_key":"current","consent_state":"yes","contributor_key":"a","unit_count":9007199254740992}]'
  ]
  LOOP
    rejected := false;
    BEGIN
      EXECUTE
        'SELECT app_private.protect_management_follow_up_consent_ratio_periods_v1($1)'
      INTO protected_document
      USING protected_text::jsonb;
    EXCEPTION WHEN SQLSTATE '22023' THEN
      rejected := true;
    END;
    IF NOT rejected THEN
      RAISE EXCEPTION 'malformed consent policy input was accepted: %',
        protected_text;
    END IF;
  END LOOP;
END
$policy_fixture$;

-- The enabled executor must return only its fixed report envelope and
-- protected periods.  It may not expose any source identity, target data,
-- membership provenance, raw answer or pre-protection count.
CREATE TEMP TABLE fixture_6bpf_enabled_candidate ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000001'::uuid,
  'UTC',
  clock.report_cutoff_utc
) AS document
FROM fixture_6bpf_clock AS clock;

DO $assert_enabled_candidate$
DECLARE
  document jsonb := (
    SELECT fixture.document FROM fixture_6bpf_enabled_candidate AS fixture
  );
  document_text text;
  period_result jsonb;
  period_order integer;
  expected_period_key text;
  expected_yes_count integer;
  expected_denominator integer;
  expected_basis_points integer;
  expected_coverage jsonb;
BEGIN
  document_text := document::text;
  IF document->>'report_id' <>
      'contact_target_follow_up_consent_ratio_two_periods'
    OR document->>'report_version' <> '1'
    OR document->>'metric_id' <> 'follow_up_consent_ratio'
    OR document->>'metric_version' <> '1'
    OR document->>'statistical_unit' <> 'contact_target_link'
    OR document->>'project_id' <>
      '6bf03000-0000-4000-8000-000000000001'
    OR document->>'status' <> 'completed'
    OR document->'periods' IS NULL
    OR document->'periods' = 'null'::jsonb
    OR document->'period_results' IS NULL
    OR document->'period_results' = 'null'::jsonb
    OR document ? 'total_contact_target_links'
    OR document ? 'trend'
    OR document ? 'difference'
    OR document_text ~* '(6bpf-|6bf08000-|app_user_id|contributor_key|contact_id|promotion_target_id|membership_id|capability_grant_id|place_name|latitude|longitude|raw_answer|phone|email)'
  THEN
    RAISE EXCEPTION 'enabled candidate envelope is not fixed/value-free: %',
      document;
  END IF;

  -- The source fixture deliberately stores unknown, not unanswered.  The
  -- report must map all twenty such links to the unanswered coverage cell.
  IF (SELECT count(*) FROM fixture_6bpf_link_rows
      WHERE follow_up_consent = 'unknown') <> 20
    OR (SELECT count(*) FROM fixture_6bpf_link_rows
        WHERE follow_up_consent = 'unanswered') <> 0
  THEN
    RAISE EXCEPTION 'source unknown/unanswered fixture counts drifted';
  END IF;

  IF jsonb_array_length(document->'period_results') <> 2 THEN
    RAISE EXCEPTION 'candidate did not return exactly two period results: %',
      document->'period_results';
  END IF;

  FOR period_result, period_order IN
    SELECT result_row.result, result_row.result_order::integer
    FROM jsonb_array_elements(document->'period_results') WITH ORDINALITY
      AS result_row(result, result_order)
    ORDER BY result_row.result_order
  LOOP
    expected_period_key := CASE period_order
      WHEN 1 THEN 'previous'
      WHEN 2 THEN 'current'
      ELSE NULL
    END;
    expected_yes_count := CASE period_order
      WHEN 1 THEN 13
      WHEN 2 THEN 10
      ELSE NULL
    END;
    expected_denominator := expected_yes_count + 10;
    expected_basis_points := CASE period_order
      WHEN 1 THEN 5652
      WHEN 2 THEN 5000
      ELSE NULL
    END;
    expected_coverage := CASE period_order
      WHEN 1 THEN jsonb_build_array(
        jsonb_build_object(
          'consent_state', 'unanswered',
          'cell_order', 0,
          'value_count', 10,
          'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'refused',
          'cell_order', 1,
          'value_count', 10,
          'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'not_applicable',
          'cell_order', 2,
          'value_count', 10,
          'privacy_status', 'displayed'
        )
      )
      WHEN 2 THEN jsonb_build_array(
        jsonb_build_object(
          'consent_state', 'unanswered',
          'cell_order', 3,
          'value_count', 10,
          'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'refused',
          'cell_order', 4,
          'value_count', 10,
          'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'not_applicable',
          'cell_order', 5,
          'value_count', 10,
          'privacy_status', 'displayed'
        )
      )
      ELSE '[]'::jsonb
    END;

    IF period_result->>'period_key' IS DISTINCT FROM expected_period_key
      OR period_result->>'period_order' IS DISTINCT FROM (period_order - 1)::text
      OR period_result->'ratio' <> jsonb_build_object(
        'privacy_status', 'displayed',
        'yes_count', expected_yes_count,
        'no_count', 10,
        'numerator', expected_yes_count,
        'denominator', expected_denominator,
        'percentage_basis_points', expected_basis_points
      )
      OR period_result->'coverage' <> expected_coverage
      OR period_result->>'unknown_count' IS DISTINCT FROM '0'
      OR period_result->>'excluded_count' IS DISTINCT FROM '0'
    THEN
      RAISE EXCEPTION
        'period result is not the expected protected value-free result: %',
        period_result;
    END IF;
  END LOOP;
END
$assert_enabled_candidate$;

-- Disable the current switch and verify that the candidate short-circuits to
-- not_enabled.  The source rows remain present and are not deleted.
RESET ROLE;
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6bf07000-0000-4000-8000-000000000004'::uuid,
  1,
  false
);
RESET ROLE;

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_ratio_reader;
CREATE TEMP TABLE fixture_6bpf_disabled_candidate ON COMMIT DROP AS
SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
  '6bf01000-0000-4000-8000-000000000001'::uuid,
  '6bf03000-0000-4000-8000-000000000001'::uuid,
  'UTC',
  clock.report_cutoff_utc
) AS document
FROM fixture_6bpf_clock AS clock;

DO $assert_disabled_candidate$
DECLARE
  document jsonb := (
    SELECT fixture.document FROM fixture_6bpf_disabled_candidate AS fixture
  );
BEGIN
  IF document->>'status' <> 'not_enabled'
    OR document ? 'report_id'
    OR document ? 'periods'
    OR document ? 'period_results'
    OR document ? 'ratio'
    OR document ? 'coverage'
    OR document ? 'cells'
  THEN
    RAISE EXCEPTION 'disabled candidate leaked a report or exact value: %',
      document;
  END IF;
END
$assert_disabled_candidate$;

-- The archive candidate was configured while active, then archived.  The
-- project status trigger and the candidate authorization resolver must reject
-- it after the committed status change.
RESET ROLE;
UPDATE app_data.projects
SET status = 'archived'
WHERE project_id = '6bf03000-0000-4000-8000-000000000003'::uuid;

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_ratio_reader;
DO $assert_forbidden_scopes$
DECLARE
  request_row record;
  rejected boolean;
BEGIN
  FOR request_row IN
    SELECT *
    FROM (
      VALUES
        (
          'view-only capability'::text,
          '6bf01000-0000-4000-8000-000000000005'::uuid,
          '6bf03000-0000-4000-8000-000000000002'::uuid
        ),
        (
          'inactive user',
          '6bf01000-0000-4000-8000-000000000006'::uuid,
          '6bf03000-0000-4000-8000-000000000001'::uuid
        ),
        (
          'expired capability',
          '6bf01000-0000-4000-8000-000000000007'::uuid,
          '6bf03000-0000-4000-8000-000000000001'::uuid
        ),
        (
          'archived project',
          '6bf01000-0000-4000-8000-000000000001'::uuid,
          '6bf03000-0000-4000-8000-000000000003'::uuid
        ),
        (
          'personal project',
          '6bf01000-0000-4000-8000-000000000001'::uuid,
          '6bf03000-0000-4000-8000-000000000005'::uuid
        ),
        (
          'cross organization project',
          '6bf01000-0000-4000-8000-000000000001'::uuid,
          '6bf03000-0000-4000-8000-000000000004'::uuid
        ),
        (
          'deleted workspace project',
          '6bf01000-0000-4000-8000-000000000001'::uuid,
          '6bf03000-0000-4000-8000-000000000006'::uuid
        ),
        (
          'unknown project',
          '6bf01000-0000-4000-8000-000000000001'::uuid,
          '6bf03000-0000-4000-8000-000000000099'::uuid
        )
    ) AS request(label, actor_id, project_id)
  LOOP
    rejected := false;
    BEGIN
      PERFORM app_private.execute_management_follow_up_consent_ratio_report_v1(
        request_row.actor_id,
        request_row.project_id,
        'UTC',
        (SELECT report_cutoff_utc FROM fixture_6bpf_clock)
      );
    EXCEPTION WHEN SQLSTATE '42501' THEN
      rejected := true;
    END;

    IF NOT rejected THEN
      RAISE EXCEPTION
        'forbidden candidate scope was accepted (%): actor %, project %',
        request_row.label,
        request_row.actor_id,
        request_row.project_id;
    END IF;
  END LOOP;
END
$assert_forbidden_scopes$;

RESET ROLE;

ROLLBACK;
