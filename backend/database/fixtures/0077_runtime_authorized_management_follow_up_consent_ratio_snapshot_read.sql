-- Synthetic rollback fixture for the 6BS runtime follow-up consent-ratio
-- snapshot bridge.
--
-- This fixture is independent of the 0075 and 0076 fixtures. It rebuilds a
-- valid 0075 release and 0076 access provenance in one transaction, then
-- exercises only the 0077 exact external-identity bridge. All hierarchy
-- ranges use one transaction timestamp so a dump/restore cannot make a child
-- row precede its parent by a few microseconds. Every row is rolled back.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6bs_clock ON COMMIT DROP AS
SELECT clock_value AS fixture_now_utc,
       date_trunc('week', clock_value) - interval '7 days'
         AS current_period_start_utc,
       date_trunc('week', clock_value) - interval '14 days'
         AS previous_period_start_utc
FROM (SELECT transaction_timestamp() AS clock_value) AS stable_clock;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b510000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b510000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b510000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b510000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  (
    '6b511000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-follow-up-consent.synthetic/auth/v1',
    'active-reader',
    '6b510000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b511000-0000-4000-8000-000000000002'::uuid,
    ' https://runtime-follow-up-consent.synthetic/auth/v1 ',
    'spaced-reader',
    '6b510000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b511000-0000-4000-8000-000000000003'::uuid,
    'https://runtime-follow-up-consent.synthetic/auth/v1',
    'release-only-reader',
    '6b510000-0000-4000-8000-000000000003'::uuid
  ),
  (
    '6b511000-0000-4000-8000-000000000004'::uuid,
    'https://runtime-follow-up-consent.synthetic/auth/v1',
    'inactive-reader',
    '6b510000-0000-4000-8000-000000000004'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
)
VALUES (
  '6b520000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BS runtime follow-up consent organization',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
VALUES
  (
    '6b530000-0000-4000-8000-000000000001'::uuid,
    '6b520000-0000-4000-8000-000000000001'::uuid,
    '6BS runtime follow-up consent project',
    'active',
    false
  ),
  (
    '6b530000-0000-4000-8000-000000000002'::uuid,
    '6b520000-0000-4000-8000-000000000001'::uuid,
    '6BS runtime follow-up consent other project',
    'active',
    false
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES
  (
    '6b540000-0000-4000-8000-000000000001'::uuid,
    '6b530000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  ),
  (
    '6b540000-0000-4000-8000-000000000002'::uuid,
    '6b530000-0000-4000-8000-000000000002'::uuid,
    1,
    'published',
    true
  );

-- Keep every parent and child range derived from the same stable instant.
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
      '6b550000-0000-4000-8000-000000000001'::uuid,
      '6b520000-0000-4000-8000-000000000001'::uuid,
      '6b510000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b550000-0000-4000-8000-000000000002'::uuid,
      '6b520000-0000-4000-8000-000000000001'::uuid,
      '6b510000-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b550000-0000-4000-8000-000000000003'::uuid,
      '6b520000-0000-4000-8000-000000000001'::uuid,
      '6b510000-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6b550000-0000-4000-8000-000000000004'::uuid,
      '6b520000-0000-4000-8000-000000000001'::uuid,
      '6b510000-0000-4000-8000-000000000004'::uuid
    )
) AS membership(membership_id, workspace_id, app_user_id)
CROSS JOIN fixture_6bs_clock AS clock;

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
      '6b560000-0000-4000-8000-000000000001'::uuid,
      '6b550000-0000-4000-8000-000000000001'::uuid,
      '6b530000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b560000-0000-4000-8000-000000000002'::uuid,
      '6b550000-0000-4000-8000-000000000002'::uuid,
      '6b530000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b560000-0000-4000-8000-000000000003'::uuid,
      '6b550000-0000-4000-8000-000000000003'::uuid,
      '6b530000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b560000-0000-4000-8000-000000000004'::uuid,
      '6b550000-0000-4000-8000-000000000002'::uuid,
      '6b530000-0000-4000-8000-000000000002'::uuid
    )
) AS membership(membership_id, organization_membership_id, project_id)
CROSS JOIN fixture_6bs_clock AS clock;

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
      '6b570000-0000-4000-8000-000000000001'::uuid,
      '6b560000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b570000-0000-4000-8000-000000000002'::uuid,
      '6b560000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b570000-0000-4000-8000-000000000003'::uuid,
      '6b560000-0000-4000-8000-000000000003'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b570000-0000-4000-8000-000000000004'::uuid,
      '6b560000-0000-4000-8000-000000000004'::uuid,
      'view_anonymous_analytics'::text
    )
) AS grant_row(grant_id, project_membership_id, capability_id)
CROSS JOIN fixture_6bs_clock AS clock;

-- Preserve the historical membership chain, but make this identity inactive
-- before any runtime call so the bridge must reject it at identity mapping.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6b510000-0000-4000-8000-000000000004'::uuid;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b580000-0000-4000-8000-000000000001'::uuid,
  '6b510000-0000-4000-8000-000000000001'::uuid,
  '6b530000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock.fixture_now_utc - interval '365 days'
)
FROM fixture_6bs_clock AS clock;

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b510000-0000-4000-8000-000000000001'::uuid,
  '6b530000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b581000-0000-4000-8000-000000000001'::uuid,
  0,
  true
);
RESET ROLE;

-- The candidate's statistical unit is a contact-target link. Ten yes and ten
-- no links per period are spread 4/3/3 across three contributors, so both
-- ratio cells satisfy the k=10, three-contributor and half-contribution gates.
INSERT INTO app_data.promotion_targets (
  promotion_target_id,
  workspace_id,
  target_type,
  display_name,
  phone,
  email,
  created_by_app_user_id
)
SELECT format(
         '6b590000-0000-4000-8000-%s',
         lpad(target_number::text, 12, '0')
       )::uuid,
       '6b520000-0000-4000-8000-000000000001'::uuid,
       'person',
       '6BS synthetic target ' || target_number,
       NULL,
       NULL,
       '6b510000-0000-4000-8000-000000000001'::uuid
FROM generate_series(1, 40) AS target_number;

CREATE TEMP TABLE fixture_6bs_source_rows (
  contact_id text PRIMARY KEY,
  app_user_id uuid NOT NULL,
  project_id uuid NOT NULL,
  questionnaire_version_id uuid NOT NULL,
  occurred_at_utc timestamptz NOT NULL,
  first_submitted_at_utc timestamptz NOT NULL,
  promotion_target_id uuid NOT NULL,
  follow_up_consent text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6bs_source_rows (
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
         '6bs-main-%s-%s-%s',
         period.period_key,
         state.consent_state,
         series_number
       ),
       CASE ((series_number - 1) % 3)
         WHEN 0 THEN '6b510000-0000-4000-8000-000000000001'::uuid
         WHEN 1 THEN '6b510000-0000-4000-8000-000000000002'::uuid
         ELSE '6b510000-0000-4000-8000-000000000003'::uuid
       END,
       '6b530000-0000-4000-8000-000000000001'::uuid,
       '6b540000-0000-4000-8000-000000000001'::uuid,
       CASE period.period_key
         WHEN 'previous' THEN
           period.period_start_utc + interval '1 day'
             + series_number * interval '1 minute'
         ELSE
           period.period_start_utc + interval '1 day'
             + series_number * interval '1 minute'
       END,
       CASE period.period_key
         WHEN 'previous' THEN
           period.period_start_utc + interval '1 day'
             + series_number * interval '1 minute'
         ELSE
           period.period_start_utc + interval '1 day'
             + series_number * interval '1 minute'
       END,
       format(
         '6b590000-0000-4000-8000-%s',
         lpad(
           (
             (CASE WHEN period.period_key = 'previous' THEN 0 ELSE 20 END)
             + state.sort_order * 10
             + series_number
           )::text,
           12,
           '0'
         )
       )::uuid,
       state.consent_state
FROM (
  SELECT 'previous'::text AS period_key,
         clock.previous_period_start_utc AS period_start_utc,
         clock.fixture_now_utc
  FROM fixture_6bs_clock AS clock
  UNION ALL
  SELECT 'current'::text,
         clock.current_period_start_utc,
         clock.fixture_now_utc
  FROM fixture_6bs_clock AS clock
) AS period
CROSS JOIN (
  VALUES ('yes'::text, 0), ('no'::text, 1)
) AS state(consent_state, sort_order)
CROSS JOIN generate_series(1, 10) AS series_number
CROSS JOIN fixture_6bs_clock AS clock;

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
SELECT source.contact_id,
       source.app_user_id,
       '6b520000-0000-4000-8000-000000000001'::uuid,
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
FROM fixture_6bs_source_rows AS source;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT source.contact_id,
       1,
       source.app_user_id,
       'submitted',
       NULL,
       '{}'::jsonb
FROM fixture_6bs_source_rows AS source;

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
)
SELECT source.contact_id,
       1,
       source.promotion_target_id,
       NULL,
       source.follow_up_consent,
       false,
       true
FROM fixture_6bs_source_rows AS source;

DO $assert_source_fixture$
DECLARE
  source_count bigint;
  yes_count bigint;
  no_count bigint;
BEGIN
  SELECT count(*) INTO source_count FROM fixture_6bs_source_rows;
  SELECT count(*) INTO yes_count
  FROM fixture_6bs_source_rows
  WHERE follow_up_consent = 'yes';
  SELECT count(*) INTO no_count
  FROM fixture_6bs_source_rows
  WHERE follow_up_consent = 'no';
  IF source_count <> 40 OR yes_count <> 20 OR no_count <> 20 THEN
    RAISE EXCEPTION
      '6BS source fixture cardinality drifted: total %, yes %, no %',
      source_count,
      yes_count,
      no_count;
  END IF;
END
$assert_source_fixture$;

-- Generate a real 0075 snapshot. The returned envelope is intentionally
-- value-free; the protected document is read only through the 0076 contract.
CREATE TEMP TABLE fixture_6bs_baseline ON COMMIT DROP AS
SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b5a0000-0000-4000-8000-000000000001'::uuid,
  '6b510000-0000-4000-8000-000000000001'::uuid,
  '6b530000-0000-4000-8000-000000000001'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
) AS document;

DO $assert_baseline$
DECLARE
  document jsonb;
BEGIN
  SELECT fixture.document INTO STRICT document
  FROM fixture_6bs_baseline AS fixture;
  IF document->>'result_status' IS DISTINCT FROM 'approved_baseline'
    OR document->>'released_snapshot_id' IS NULL
    OR document ? 'protected_report'
    OR document ? 'period_results'
    OR document ? 'cells'
  THEN
    RAISE EXCEPTION '6BS baseline release is invalid or value-bearing: %',
      document;
  END IF;
END
$assert_baseline$;

-- Shape alone is not 0075 provenance. This exact document deliberately has no
-- 0075 attempt or release-family claim, so 0076 must return untrusted.
GRANT SELECT ON fixture_6bs_baseline
  TO tongxingzhe_management_consent_ratio_snapshot_release_writer;
SET LOCAL ROLE tongxingzhe_management_consent_ratio_snapshot_release_writer;
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
)
SELECT
  '6b5a0000-0000-4000-8000-000000000002'::uuid,
  '6b5a0000-0000-4000-8000-000000000003'::uuid,
  snapshot.created_by_app_user_id,
  snapshot.project_id,
  snapshot.release_lineage_id,
  snapshot.report_id,
  snapshot.report_version,
  snapshot.query_fingerprint,
  snapshot.reporting_time_zone,
  snapshot.data_cutoff_utc,
  snapshot.released_at_utc,
  NULL,
  snapshot.source_change_sequence,
  snapshot.protected_report
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.snapshot_id =
  (SELECT (fixture.document->>'released_snapshot_id')::uuid
   FROM fixture_6bs_baseline AS fixture);
RESET ROLE;

CREATE TEMP TABLE fixture_6bs_counts ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_users,
  (SELECT count(*) FROM app_data.workspaces) AS workspaces,
  (SELECT count(*) FROM app_data.projects) AS projects;

SELECT set_config(
  'app.fixture_6bs_baseline_snapshot_id',
  (
    SELECT document->>'released_snapshot_id'
    FROM fixture_6bs_baseline
  ),
  true
);

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6bs_runtime$
DECLARE
  active_read jsonb;
  repeated_read jsonb;
  exact_read jsonb;
  missing_read jsonb;
  cross_project_read jsonb;
  untrusted_read jsonb;
BEGIN
  active_read :=
    app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
      'https://runtime-follow-up-consent.synthetic/auth/v1',
      'active-reader',
      '6b530000-0000-4000-8000-000000000001'::uuid,
      current_setting('app.fixture_6bs_baseline_snapshot_id')::uuid
    );
  IF active_read->>'access_contract_id' IS DISTINCT FROM
      'authorized_follow_up_consent_ratio_management_report_snapshot_read_v1'
    OR active_read->>'result_status' IS DISTINCT FROM 'completed'
    OR active_read->>'resolved_snapshot_id' IS DISTINCT FROM
      current_setting('app.fixture_6bs_baseline_snapshot_id')
    OR active_read->'protected_report'->>'report_id' IS DISTINCT FROM
      'contact_target_follow_up_consent_ratio_two_periods'
    OR active_read ? 'project_id'
    OR active_read ? 'requested_app_user_id'
    OR active_read::text ~* 'contact_id|promotion_target_id|contributor_key'
  THEN
    RAISE EXCEPTION '6BS active runtime read returned an invalid result: %',
      active_read;
  END IF;

  repeated_read :=
    app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
      'https://runtime-follow-up-consent.synthetic/auth/v1',
      'active-reader',
      '6b530000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
  IF repeated_read->>'result_status' IS DISTINCT FROM 'completed'
    OR repeated_read->>'access_event_id' IS NULL
    OR repeated_read->>'access_event_id' = active_read->>'access_event_id'
  THEN
    RAISE EXCEPTION '6BS repeated runtime read did not append an audit';
  END IF;

  -- The stored issuer contains spaces. A clean issuer must not be normalized
  -- into a match; the exact stored value is accepted separately.
  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        'spaced-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge trimmed a stored external identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  exact_read :=
    app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
      ' https://runtime-follow-up-consent.synthetic/auth/v1 ',
      'spaced-reader',
      '6b530000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
  IF exact_read->>'result_status' IS DISTINCT FROM 'completed'
    OR exact_read->>'access_event_id' IS NULL
  THEN
    RAISE EXCEPTION '6BS exact stored external identity did not resolve';
  END IF;

  missing_read :=
    app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
      'https://runtime-follow-up-consent.synthetic/auth/v1',
      'active-reader',
      '6b530000-0000-4000-8000-000000000001'::uuid,
      '6b5a0000-0000-4000-8000-000000000099'::uuid
    );
  IF missing_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR missing_read->>'reason_code' IS DISTINCT FROM 'snapshot_not_available'
    OR missing_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BS missing snapshot did not fail closed: %', missing_read;
  END IF;

  -- The reader is authorized in the other project, but the target snapshot
  -- is not in that project. This must remain indistinguishable from missing.
  cross_project_read :=
    app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
      'https://runtime-follow-up-consent.synthetic/auth/v1',
      'active-reader',
      '6b530000-0000-4000-8000-000000000002'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
  IF cross_project_read->>'result_status' IS DISTINCT FROM 'not_found'
    OR cross_project_read->>'reason_code' IS DISTINCT FROM
      'snapshot_not_available'
    OR cross_project_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BS cross-project snapshot was distinguishable: %',
      cross_project_read;
  END IF;

  untrusted_read :=
    app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
      'https://runtime-follow-up-consent.synthetic/auth/v1',
      'active-reader',
      '6b530000-0000-4000-8000-000000000001'::uuid,
      '6b5a0000-0000-4000-8000-000000000002'::uuid
    );
  IF untrusted_read->>'result_status' IS DISTINCT FROM 'untrusted_provenance'
    OR untrusted_read->>'reason_code' IS DISTINCT FROM
      'snapshot_provenance_untrusted'
    OR untrusted_read ? 'protected_report'
  THEN
    RAISE EXCEPTION '6BS untrusted provenance leaked values: %',
      untrusted_read;
  END IF;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        'release-only-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a release-only identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        'inactive-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted an inactive identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        'unknown-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted an unknown identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        NULL::text,
        'active-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a null issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        '',
        'active-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted an empty issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        '   ',
        'active-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a blank issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        NULL::text,
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a null subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        '',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted an empty subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        '   ',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a blank subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- The maximum issuer/subject lengths pass validation and then fail only
  -- because no exact identity exists. One more character fails as input.
  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        repeat('i', 2048),
        'active-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge rejected issuer boundary incorrectly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        repeat('i', 2049),
        'active-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted an overlong issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        repeat('s', 512),
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge rejected subject boundary incorrectly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        repeat('s', 513),
        '6b530000-0000-4000-8000-000000000001'::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted an overlong subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        'active-reader',
        NULL::uuid,
        (active_read->>'resolved_snapshot_id')::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a null project';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM
      app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
        'https://runtime-follow-up-consent.synthetic/auth/v1',
        'active-reader',
        '6b530000-0000-4000-8000-000000000001'::uuid,
        NULL::uuid
      );
    RAISE EXCEPTION '6BS runtime bridge accepted a null snapshot';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.read_authorized_management_follow_up_consent_report_snapshot_v1(
      '6b510000-0000-4000-8000-000000000002'::uuid,
      '6b530000-0000-4000-8000-000000000001'::uuid,
      (active_read->>'resolved_snapshot_id')::uuid
    );
    RAISE EXCEPTION '6BS runtime role received direct app_private access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture_6bs_runtime$;

RESET ROLE;

DO $fixture_6bs_audit$
DECLARE
  expected_counts record;
  actual_counts record;
  history_text text;
BEGIN
  SELECT * INTO STRICT expected_counts FROM fixture_6bs_counts;
  SELECT
    (SELECT count(*) FROM app_data.app_users) AS app_users,
    (SELECT count(*) FROM app_data.workspaces) AS workspaces,
    (SELECT count(*) FROM app_data.projects) AS projects
  INTO STRICT actual_counts;
  IF actual_counts.app_users IS DISTINCT FROM expected_counts.app_users
    OR actual_counts.workspaces IS DISTINCT FROM expected_counts.workspaces
    OR actual_counts.projects IS DISTINCT FROM expected_counts.projects
  THEN
    RAISE EXCEPTION '6BS unknown identity bootstrapped application rows';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_follow_up_consent_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6b510000-0000-4000-8000-000000000002'::uuid
  ) <> 6
  OR (
    SELECT count(*)
    FROM app_private.management_follow_up_consent_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6b510000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'completed'
  ) <> 3
  OR (
    SELECT count(*)
    FROM app_private.management_follow_up_consent_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6b510000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'not_found'
  ) <> 2
  OR (
    SELECT count(*)
    FROM app_private.management_follow_up_consent_report_snapshot_access_events
    WHERE requested_by_app_user_id =
      '6b510000-0000-4000-8000-000000000002'::uuid
      AND result_status = 'untrusted_provenance'
  ) <> 1
  THEN
    RAISE EXCEPTION '6BS runtime audit status counts are incorrect';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_follow_up_consent_report_snapshot_access_events
    AS event
  WHERE event.requested_by_app_user_id =
    '6b510000-0000-4000-8000-000000000002'::uuid;
  IF history_text ~* 'protected_report|contact_id|promotion_target_id|contributor|phone|email|place_name|canonical_name|pii'
  THEN
    RAISE EXCEPTION '6BS runtime audit retained protected values';
  END IF;
END
$fixture_6bs_audit$;

ROLLBACK;
