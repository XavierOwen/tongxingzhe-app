-- Synthetic rollback fixture for Slice 6BU.
--
-- The directory is a private SQL seam. This fixture creates a stable,
-- value-free consent-ratio snapshot lineage, its negative provenance rows,
-- and the authorization cases needed by the directory contract. Every
-- hierarchy timestamp is derived from one transaction timestamp so a
-- pg_dump/restore cannot introduce a parent/child containment race. The
-- independent concurrency script uses the a6f* namespace and is intentionally
-- not reused here.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6bu_clock ON COMMIT DROP AS
SELECT transaction_timestamp() AS fixture_now_utc;

CREATE TEMP TABLE fixture_6bu_directory_exclusions (
  case_name text PRIMARY KEY,
  snapshot_id uuid NOT NULL,
  project_id uuid NOT NULL
) ON COMMIT DROP;

GRANT SELECT ON fixture_6bu_clock
  TO tongxingzhe_management_consent_ratio_snapshot_release_writer;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b800100-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b800100-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b800100-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b800100-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name
)
VALUES (
  '6b800200-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BU consent snapshot directory workspace'
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
VALUES
  (
    '6b800300-0000-4000-8000-000000000001'::uuid,
    '6b800200-0000-4000-8000-000000000001'::uuid,
    '6BU consent snapshot directory project',
    'active', false
  ),
  (
    '6b800300-0000-4000-8000-000000000002'::uuid,
    '6b800200-0000-4000-8000-000000000001'::uuid,
    '6BU cross-project provenance project',
    'active', false
  ),
  (
    '6b800300-0000-4000-8000-000000000003'::uuid,
    '6b800200-0000-4000-8000-000000000001'::uuid,
    '6BU authorized empty project',
    'active', false
  ),
  (
    '6b800300-0000-4000-8000-000000000004'::uuid,
    '6b800200-0000-4000-8000-000000000001'::uuid,
    '6BU project archived after authorization setup',
    'active', false
  );

-- All membership and grant ranges share one stable lower bound. The
-- revoked reader has a historical view grant but no grant at the resolver's
-- post-lock reference time.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.membership_id,
       '6b800200-0000-4000-8000-000000000001'::uuid,
       membership.app_user_id,
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '6b800400-0000-4000-8000-000000000001'::uuid,
      '6b800100-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b800400-0000-4000-8000-000000000002'::uuid,
      '6b800100-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b800400-0000-4000-8000-000000000003'::uuid,
      '6b800100-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6b800400-0000-4000-8000-000000000004'::uuid,
      '6b800100-0000-4000-8000-000000000004'::uuid
    )
) AS membership(membership_id, app_user_id)
CROSS JOIN fixture_6bu_clock AS clock;

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
      '6b800500-0000-4000-8000-000000000001'::uuid,
      '6b800400-0000-4000-8000-000000000001'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b800500-0000-4000-8000-000000000002'::uuid,
      '6b800400-0000-4000-8000-000000000001'::uuid,
      '6b800300-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b800500-0000-4000-8000-000000000003'::uuid,
      '6b800400-0000-4000-8000-000000000002'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b800500-0000-4000-8000-000000000004'::uuid,
      '6b800400-0000-4000-8000-000000000003'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b800500-0000-4000-8000-000000000005'::uuid,
      '6b800400-0000-4000-8000-000000000001'::uuid,
      '6b800300-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6b800500-0000-4000-8000-000000000006'::uuid,
      '6b800400-0000-4000-8000-000000000004'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b800500-0000-4000-8000-000000000007'::uuid,
      '6b800400-0000-4000-8000-000000000001'::uuid,
      '6b800300-0000-4000-8000-000000000004'::uuid
    )
) AS membership(membership_id, organization_membership_id, project_id)
CROSS JOIN fixture_6bu_clock AS clock;

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
       CASE WHEN grant_row.grant_id =
         '6b800600-0000-4000-8000-000000000006'::uuid
         THEN clock.fixture_now_utc - interval '1 hour'
         ELSE NULL
       END
FROM (
  VALUES
    (
      '6b800600-0000-4000-8000-000000000001'::uuid,
      '6b800500-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000002'::uuid,
      '6b800500-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000003'::uuid,
      '6b800500-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000004'::uuid,
      '6b800500-0000-4000-8000-000000000002'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000005'::uuid,
      '6b800500-0000-4000-8000-000000000003'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000006'::uuid,
      '6b800500-0000-4000-8000-000000000004'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000007'::uuid,
      '6b800500-0000-4000-8000-000000000005'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000008'::uuid,
      '6b800500-0000-4000-8000-000000000006'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b800600-0000-4000-8000-000000000009'::uuid,
      '6b800500-0000-4000-8000-000000000007'::uuid,
      'view_anonymous_analytics'::text
    )
) AS grant_row(grant_id, project_membership_id, capability_id)
CROSS JOIN fixture_6bu_clock AS clock;

-- Build valid historical authorization first, then make the subject and
-- project inactive. The fixture therefore proves the resolver rejects stale
-- authorization rather than merely rejecting a missing hierarchy.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6b800100-0000-4000-8000-000000000004'::uuid;

UPDATE app_data.projects
SET status = 'archived'
WHERE project_id = '6b800300-0000-4000-8000-000000000004'::uuid;

-- The directory contract only needs a real reporting-time-zone lineage. It
-- does not need the 6BQ source tables because the protected documents below
-- are built through the same validator used by the snapshot trigger.
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b800700-0000-4000-8000-000000000001'::uuid,
  '6b800100-0000-4000-8000-000000000001'::uuid,
  '6b800300-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock.fixture_now_utc - interval '365 days'
)
FROM fixture_6bu_clock AS clock;
SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b800700-0000-4000-8000-000000000002'::uuid,
  '6b800100-0000-4000-8000-000000000001'::uuid,
  '6b800300-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock.fixture_now_utc - interval '365 days'
)
FROM fixture_6bu_clock AS clock;

-- Insert a complete baseline/successor chain as the closed release writer.
-- Snapshot seven is deliberately suppressed; its protected report still
-- contains metadata-only privacy nulls and therefore remains directory-safe.
SET LOCAL ROLE tongxingzhe_management_consent_ratio_snapshot_release_writer;
DO $fixture_6bu_snapshots$
DECLARE
  fixture_now_utc timestamptz;
  zone_effective_utc timestamptz;
  fixture_owner_id constant uuid :=
    '6b800100-0000-4000-8000-000000000001';
  fixture_project_id constant uuid :=
    '6b800300-0000-4000-8000-000000000001';
  fixture_workspace_id constant uuid :=
    '6b800200-0000-4000-8000-000000000001';
  fixture_membership_id constant uuid :=
    '6b800400-0000-4000-8000-000000000001';
  fixture_project_membership_id constant uuid :=
    '6b800500-0000-4000-8000-000000000001';
  fixture_capability_grant_id constant uuid :=
    '6b800600-0000-4000-8000-000000000002';
  fixture_report_id constant text :=
    'contact_target_follow_up_consent_ratio_two_periods';
  fixture_lineage_id constant text :=
    'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods';
  fixture_query_fingerprint constant text :=
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1';
  request_id uuid;
  snapshot_id uuid;
  previous_snapshot_id uuid;
  cutoff_utc timestamptz;
  report_document jsonb;
  result_document jsonb;
  ratio_document jsonb;
  previous_coverage jsonb;
  current_coverage jsonb;
  periods_document jsonb;
  snapshot_number integer;
  result_status text;
  shared_period_count integer;
  assessed_cell_count integer;
BEGIN
  SELECT clock.fixture_now_utc
  INTO STRICT fixture_now_utc
  FROM fixture_6bu_clock AS clock;
  SELECT version_row.effective_from_utc
  INTO STRICT zone_effective_utc
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = fixture_project_id
    AND version_row.version_number = 1;

  FOR snapshot_number IN 1..21 LOOP
    cutoff_utc = date_trunc(
      'milliseconds',
      fixture_now_utc - interval '21 days'
        + snapshot_number * interval '1 minute'
    );
    request_id = format(
      '6b800900-0000-4000-8000-%s',
      lpad(snapshot_number::text, 12, '0')
    )::uuid;
    snapshot_id = format(
      '6b800800-0000-4000-8000-%s',
      lpad(snapshot_number::text, 12, '0')
    )::uuid;
    result_status = CASE
      WHEN snapshot_number = 1 THEN 'approved_baseline'
      ELSE 'approved'
    END;
    shared_period_count = CASE
      WHEN snapshot_number = 1 THEN 0
      ELSE 2
    END;
    assessed_cell_count = shared_period_count * 4;

    IF snapshot_number = 7 THEN
      ratio_document = jsonb_build_object(
        'privacy_status', 'suppressed',
        'yes_count', NULL::integer,
        'no_count', NULL::integer,
        'numerator', NULL::integer,
        'denominator', NULL::integer,
        'percentage_basis_points', NULL::integer
      );
      previous_coverage = jsonb_build_array(
        jsonb_build_object(
          'consent_state', 'unanswered', 'cell_order', 0,
          'value_count', NULL::integer, 'privacy_status', 'suppressed'
        ),
        jsonb_build_object(
          'consent_state', 'refused', 'cell_order', 1,
          'value_count', NULL::integer, 'privacy_status', 'suppressed'
        ),
        jsonb_build_object(
          'consent_state', 'not_applicable', 'cell_order', 2,
          'value_count', NULL::integer, 'privacy_status', 'suppressed'
        )
      );
      current_coverage = jsonb_build_array(
        jsonb_build_object(
          'consent_state', 'unanswered', 'cell_order', 3,
          'value_count', NULL::integer, 'privacy_status', 'suppressed'
        ),
        jsonb_build_object(
          'consent_state', 'refused', 'cell_order', 4,
          'value_count', NULL::integer, 'privacy_status', 'suppressed'
        ),
        jsonb_build_object(
          'consent_state', 'not_applicable', 'cell_order', 5,
          'value_count', NULL::integer, 'privacy_status', 'suppressed'
        )
      );
    ELSE
      ratio_document = jsonb_build_object(
        'privacy_status', 'displayed',
        'yes_count', 10,
        'no_count', 10,
        'numerator', 10,
        'denominator', 20,
        'percentage_basis_points', 5000
      );
      previous_coverage = jsonb_build_array(
        jsonb_build_object(
          'consent_state', 'unanswered', 'cell_order', 0,
          'value_count', 10, 'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'refused', 'cell_order', 1,
          'value_count', 10, 'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'not_applicable', 'cell_order', 2,
          'value_count', 10, 'privacy_status', 'displayed'
        )
      );
      current_coverage = jsonb_build_array(
        jsonb_build_object(
          'consent_state', 'unanswered', 'cell_order', 3,
          'value_count', 10, 'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'refused', 'cell_order', 4,
          'value_count', 10, 'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'consent_state', 'not_applicable', 'cell_order', 5,
          'value_count', 10, 'privacy_status', 'displayed'
        )
      );
    END IF;

    periods_document = app_private.resolve_management_report_periods_v1(
      'UTC', cutoff_utc
    );
    report_document = jsonb_build_object(
      'contract_id', 'management_follow_up_consent_ratio_candidate_v1',
      'report_id', fixture_report_id,
      'report_version', 1,
      'metric_id', 'follow_up_consent_ratio',
      'metric_version', 1,
      'statistical_unit', 'contact_target_link',
      'dimension', 'consent_state',
      'period_grain', 'week',
      'comparison_period_count', 2,
      'period_boundary_id', 'iso_week_monday_v1',
      'privacy_policy', 'management_follow_up_consent_ratio_privacy_v1',
      'query_fingerprint', fixture_query_fingerprint,
      'source_scope',
        'backend_accepted_active_contact_target_links_current_revision',
      'project_id', fixture_project_id,
      'status', 'completed',
      'periods', periods_document,
      'period_results', jsonb_build_array(
        jsonb_build_object(
          'period_key', 'previous', 'period_order', 0,
          'ratio', ratio_document,
          'coverage', previous_coverage,
          'unknown_count', 0, 'excluded_count', 0
        ),
        jsonb_build_object(
          'period_key', 'current', 'period_order', 1,
          'ratio', ratio_document,
          'coverage', current_coverage,
          'unknown_count', 0, 'excluded_count', 0
        )
      )
    );

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
      snapshot_id,
      request_id,
      fixture_owner_id,
      fixture_project_id,
      fixture_lineage_id,
      fixture_report_id,
      1,
      fixture_query_fingerprint,
      'UTC',
      cutoff_utc,
      cutoff_utc + interval '1 second',
      previous_snapshot_id,
      0,
      report_document
    );

    result_document = jsonb_build_object(
      'release_contract_id',
        'follow_up_consent_ratio_management_report_snapshot_release_v1',
      'release_request_id', request_id,
      'project_id', fixture_project_id,
      'release_lineage_id', fixture_lineage_id,
      'report_id', fixture_report_id,
      'report_version', 1,
      'query_fingerprint', fixture_query_fingerprint,
      'reporting_time_zone_version_number', 1,
      'reporting_time_zone', 'UTC',
      'data_cutoff_utc', to_char(
        cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', 0,
      'compared_snapshot_id', previous_snapshot_id,
      'released_snapshot_id', snapshot_id,
      'shared_period_count', shared_period_count,
      'assessed_cell_count', assessed_cell_count,
      'result_status', result_status,
      'reason_codes', '[]'::jsonb
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
      request_id,
      fixture_owner_id,
      fixture_workspace_id,
      fixture_membership_id,
      fixture_project_membership_id,
      fixture_capability_grant_id,
      'release_management_reports',
      cutoff_utc,
      fixture_project_id,
      1,
      'UTC',
      zone_effective_utc,
      cutoff_utc,
      fixture_lineage_id,
      fixture_report_id,
      1,
      fixture_query_fingerprint,
      0,
      previous_snapshot_id,
      snapshot_id,
      shared_period_count,
      assessed_cell_count,
      result_status,
      '[]'::jsonb,
      result_document
    );
    previous_snapshot_id = snapshot_id;
  END LOOP;
END
$fixture_6bu_snapshots$;
RESET ROLE;

-- A blocked release attempt is provenance noise, not a directory entry.
-- It has no released snapshot and is inserted as an ordinary valid row under
-- the release writer so its status/check constraints remain active.
SET LOCAL ROLE tongxingzhe_management_consent_ratio_snapshot_release_writer;
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
)
SELECT
  '6b801200-0000-4000-8000-000000000001'::uuid,
  '6b800100-0000-4000-8000-000000000001'::uuid,
  '6b800200-0000-4000-8000-000000000001'::uuid,
  '6b800400-0000-4000-8000-000000000001'::uuid,
  '6b800500-0000-4000-8000-000000000001'::uuid,
  '6b800600-0000-4000-8000-000000000002'::uuid,
  'release_management_reports',
  clock.fixture_now_utc - interval '1 hour',
  '6b800300-0000-4000-8000-000000000001'::uuid,
  1,
  'UTC',
  clock.fixture_now_utc - interval '365 days',
  clock.fixture_now_utc - interval '1 hour',
  'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
  'contact_target_follow_up_consent_ratio_two_periods',
  1,
  'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
  0,
  '6b800800-0000-4000-8000-000000000001'::uuid,
  NULL,
  0,
  0,
  'blocked',
  '["release_opt_in_not_enabled"]'::jsonb,
  jsonb_build_object(
    'release_contract_id',
      'follow_up_consent_ratio_management_report_snapshot_release_v1',
    'release_request_id',
      '6b801200-0000-4000-8000-000000000001'::uuid,
    'project_id', '6b800300-0000-4000-8000-000000000001'::uuid,
    'release_lineage_id',
      'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods',
    'report_id', 'contact_target_follow_up_consent_ratio_two_periods',
    'report_version', 1,
    'query_fingerprint',
      'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', 'UTC',
    'data_cutoff_utc', to_char(
      clock.fixture_now_utc - interval '1 hour',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'source_change_sequence', 0,
    'compared_snapshot_id',
      '6b800800-0000-4000-8000-000000000001'::uuid,
    'released_snapshot_id', NULL,
    'shared_period_count', 0,
    'assessed_cell_count', 0,
    'result_status', 'blocked',
    'reason_codes', '["release_opt_in_not_enabled"]'::jsonb
  )
FROM fixture_6bu_clock AS clock;
RESET ROLE;

-- The directory's closed join must reject all of these otherwise plausible
-- rows. User-controlled provenance mutation is intentionally simulated only
-- in this rollback fixture with session_replication_role, as in the existing
-- 6BA/6BK fixtures; production paths remain protected by the triggers.
DO $fixture_6bu_exclusions$
DECLARE
  base_snapshot app_private.management_report_snapshots%ROWTYPE;
  base_attempt
    app_private.management_follow_up_consent_report_release_attempts%ROWTYPE;
  fixture_project_id constant uuid :=
    '6b800300-0000-4000-8000-000000000001';
  fixture_other_project_id constant uuid :=
    '6b800300-0000-4000-8000-000000000002';
  fixture_owner_id constant uuid :=
    '6b800100-0000-4000-8000-000000000001';
  fixture_workspace_id constant uuid :=
    '6b800200-0000-4000-8000-000000000001';
  fixture_other_project_membership_id constant uuid :=
    '6b800500-0000-4000-8000-000000000002';
  fixture_other_release_grant_id constant uuid :=
    '6b800600-0000-4000-8000-000000000004';
  legacy_snapshot_id constant uuid :=
    '6b801000-0000-4000-8000-000000000001';
  legacy_request_id constant uuid :=
    '6b801100-0000-4000-8000-000000000001';
  missing_claim_snapshot_id constant uuid :=
    '6b801000-0000-4000-8000-000000000002';
  missing_claim_request_id constant uuid :=
    '6b801100-0000-4000-8000-000000000002';
  foreign_family_snapshot_id constant uuid :=
    '6b801000-0000-4000-8000-000000000003';
  foreign_family_request_id constant uuid :=
    '6b801100-0000-4000-8000-000000000003';
  drift_snapshot_id constant uuid :=
    '6b801000-0000-4000-8000-000000000004';
  drift_request_id constant uuid :=
    '6b801100-0000-4000-8000-000000000004';
  cross_project_snapshot_id constant uuid :=
    '6b801000-0000-4000-8000-000000000005';
  cross_project_request_id constant uuid :=
    '6b801100-0000-4000-8000-000000000005';
  cross_project_report jsonb;
  cross_project_attempt_document jsonb;
  cross_project_cutoff timestamptz;
  cross_project_zone_effective timestamptz;
BEGIN
  SELECT snapshot.*
  INTO STRICT base_snapshot
  FROM app_private.management_report_snapshots AS snapshot
  WHERE snapshot.project_id = fixture_project_id
    AND snapshot.snapshot_id =
      '6b800800-0000-4000-8000-000000000021'::uuid;
  SELECT attempt.*
  INTO STRICT base_attempt
  FROM app_private.management_follow_up_consent_report_release_attempts
    AS attempt
  WHERE attempt.release_request_id = base_snapshot.release_request_id;

  SELECT version_row.effective_from_utc
  INTO STRICT cross_project_zone_effective
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = fixture_other_project_id
    AND version_row.version_number = 1;
  cross_project_cutoff = base_snapshot.data_cutoff_utc;

  PERFORM set_config('session_replication_role', 'replica', true);

  -- Legacy: a snapshot without an attempt or family claim.
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    legacy_snapshot_id, legacy_request_id, base_snapshot.created_by_app_user_id,
    fixture_project_id, base_snapshot.release_lineage_id, base_snapshot.report_id,
    base_snapshot.report_version, base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone, base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc, NULL, base_snapshot.source_change_sequence,
    base_snapshot.protected_report
  );
  INSERT INTO fixture_6bu_directory_exclusions (
    case_name, snapshot_id, project_id
  ) VALUES ('legacy_without_attempt', legacy_snapshot_id, fixture_project_id);

  -- Missing claim: the snapshot and release attempt agree, but the shared
  -- request ledger has no family row.
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    missing_claim_snapshot_id, missing_claim_request_id,
    base_snapshot.created_by_app_user_id, fixture_project_id,
    base_snapshot.release_lineage_id, base_snapshot.report_id,
    base_snapshot.report_version, base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone, base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc + interval '3 seconds', NULL,
    base_snapshot.source_change_sequence, base_snapshot.protected_report
  );
  INSERT INTO app_private.management_follow_up_consent_report_release_attempts
  SELECT missing_claim_request_id,
         base_attempt.requested_by_app_user_id,
         base_attempt.organization_workspace_id,
         base_attempt.organization_membership_id,
         base_attempt.project_membership_id,
         base_attempt.capability_grant_id,
         base_attempt.capability_id,
         base_attempt.authorization_reference_at_utc,
         base_attempt.project_id,
         base_attempt.reporting_time_zone_version_number,
         base_attempt.reporting_time_zone,
         base_attempt.reporting_time_zone_effective_from_utc,
         base_attempt.data_cutoff_utc,
         base_attempt.release_lineage_id,
         base_attempt.report_id,
         base_attempt.report_version,
         base_attempt.query_fingerprint,
         base_attempt.source_change_sequence,
         NULL,
         missing_claim_snapshot_id,
         0,
         0,
         'approved_baseline',
         '[]'::jsonb,
         base_attempt.result_document
  ;
  INSERT INTO fixture_6bu_directory_exclusions (
    case_name, snapshot_id, project_id
  ) VALUES ('missing_family_claim', missing_claim_snapshot_id, fixture_project_id);

  -- Foreign family: an otherwise complete consent tuple is claimed by a
  -- neighboring release family, so the directory's exact claim join rejects it.
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    foreign_family_snapshot_id, foreign_family_request_id,
    base_snapshot.created_by_app_user_id, fixture_project_id,
    base_snapshot.release_lineage_id, base_snapshot.report_id,
    base_snapshot.report_version, base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone, base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc + interval '2 seconds', NULL,
    base_snapshot.source_change_sequence, base_snapshot.protected_report
  );
  INSERT INTO app_private.management_follow_up_consent_report_release_attempts
  SELECT foreign_family_request_id,
         base_attempt.requested_by_app_user_id,
         base_attempt.organization_workspace_id,
         base_attempt.organization_membership_id,
         base_attempt.project_membership_id,
         base_attempt.capability_grant_id,
         base_attempt.capability_id,
         base_attempt.authorization_reference_at_utc,
         base_attempt.project_id,
         base_attempt.reporting_time_zone_version_number,
         base_attempt.reporting_time_zone,
         base_attempt.reporting_time_zone_effective_from_utc,
         base_attempt.data_cutoff_utc,
         base_attempt.release_lineage_id,
         base_attempt.report_id,
         base_attempt.report_version,
         base_attempt.query_fingerprint,
         base_attempt.source_change_sequence,
         NULL,
         foreign_family_snapshot_id,
         0,
         0,
         'approved_baseline',
         '[]'::jsonb,
         base_attempt.result_document;
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    foreign_family_request_id, 'interest_management_report_snapshot_release'
  );
  INSERT INTO fixture_6bu_directory_exclusions (
    case_name, snapshot_id, project_id
  ) VALUES ('foreign_release_family', foreign_family_snapshot_id, fixture_project_id);

  -- Drifted tuple: the snapshot is canonical, but the attempt watermark no
  -- longer agrees with it. This protects against an owner-repaired mismatch.
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    drift_snapshot_id, drift_request_id, base_snapshot.created_by_app_user_id,
    fixture_project_id, base_snapshot.release_lineage_id, base_snapshot.report_id,
    base_snapshot.report_version, base_snapshot.query_fingerprint,
    base_snapshot.reporting_time_zone, base_snapshot.data_cutoff_utc,
    base_snapshot.released_at_utc + interval '1 second', NULL,
    base_snapshot.source_change_sequence, base_snapshot.protected_report
  );
  INSERT INTO app_private.management_follow_up_consent_report_release_attempts
  SELECT drift_request_id,
         base_attempt.requested_by_app_user_id,
         base_attempt.organization_workspace_id,
         base_attempt.organization_membership_id,
         base_attempt.project_membership_id,
         base_attempt.capability_grant_id,
         base_attempt.capability_id,
         base_attempt.authorization_reference_at_utc,
         base_attempt.project_id,
         base_attempt.reporting_time_zone_version_number,
         base_attempt.reporting_time_zone,
         base_attempt.reporting_time_zone_effective_from_utc,
         base_attempt.data_cutoff_utc,
         base_attempt.release_lineage_id,
         base_attempt.report_id,
         base_attempt.report_version,
         base_attempt.query_fingerprint,
         1,
         NULL,
         drift_snapshot_id,
         0,
         0,
         'approved_baseline',
         '[]'::jsonb,
         base_attempt.result_document;
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    drift_request_id,
    'follow_up_consent_ratio_management_report_snapshot_release'
  );
  INSERT INTO fixture_6bu_directory_exclusions (
    case_name, snapshot_id, project_id
  ) VALUES ('drifted_source_watermark', drift_snapshot_id, fixture_project_id);

  -- Cross-project: preserve the same trusted lineage in the empty project.
  -- It is eligible for that project's directory only, never for project one.
  cross_project_report = jsonb_set(
    base_snapshot.protected_report,
    ARRAY['project_id'],
    to_jsonb(fixture_other_project_id::text),
    false
  );
  INSERT INTO app_private.management_report_snapshots (
    snapshot_id, release_request_id, created_by_app_user_id, project_id,
    release_lineage_id, report_id, report_version, query_fingerprint,
    reporting_time_zone, data_cutoff_utc, released_at_utc,
    previous_snapshot_id, source_change_sequence, protected_report
  ) VALUES (
    cross_project_snapshot_id, cross_project_request_id, fixture_owner_id,
    fixture_other_project_id, base_snapshot.release_lineage_id,
    base_snapshot.report_id, base_snapshot.report_version,
    base_snapshot.query_fingerprint, base_snapshot.reporting_time_zone,
    cross_project_cutoff, base_snapshot.released_at_utc, NULL,
    base_snapshot.source_change_sequence, cross_project_report
  );
  cross_project_attempt_document = jsonb_set(
    base_attempt.result_document,
    ARRAY['release_request_id'], to_jsonb(cross_project_request_id), false
  );
  cross_project_attempt_document = jsonb_set(
    cross_project_attempt_document,
    ARRAY['project_id'], to_jsonb(fixture_other_project_id), false
  );
  cross_project_attempt_document = jsonb_set(
    cross_project_attempt_document,
    ARRAY['data_cutoff_utc'], to_jsonb(to_char(
      cross_project_cutoff AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )), false
  );
  cross_project_attempt_document = jsonb_set(
    cross_project_attempt_document,
    ARRAY['released_snapshot_id'], to_jsonb(cross_project_snapshot_id), false
  );
  INSERT INTO app_private.management_follow_up_consent_report_release_attempts
  SELECT cross_project_request_id,
         base_attempt.requested_by_app_user_id,
         fixture_workspace_id,
         base_attempt.organization_membership_id,
         fixture_other_project_membership_id,
         fixture_other_release_grant_id,
         base_attempt.capability_id,
         cross_project_cutoff,
         fixture_other_project_id,
         base_attempt.reporting_time_zone_version_number,
         base_attempt.reporting_time_zone,
         cross_project_zone_effective,
         cross_project_cutoff,
         base_attempt.release_lineage_id,
         base_attempt.report_id,
         base_attempt.report_version,
         base_attempt.query_fingerprint,
         base_attempt.source_change_sequence,
         NULL,
         cross_project_snapshot_id,
         0,
         0,
         'approved_baseline',
         '[]'::jsonb,
         cross_project_attempt_document;
  INSERT INTO app_private.management_report_release_request_claims (
    release_request_id, release_family_id
  ) VALUES (
    cross_project_request_id,
    'follow_up_consent_ratio_management_report_snapshot_release'
  );
  INSERT INTO fixture_6bu_directory_exclusions (
    case_name, snapshot_id, project_id
  ) VALUES ('cross_project_snapshot', cross_project_snapshot_id,
    fixture_other_project_id);

  PERFORM set_config('session_replication_role', 'origin', true);

  IF (SELECT count(*) FROM fixture_6bu_directory_exclusions) <> 5
    OR NOT EXISTS (
      SELECT 1 FROM app_private.management_report_snapshots
      WHERE snapshot_id = legacy_snapshot_id
    )
    OR EXISTS (
      SELECT 1 FROM app_private.management_follow_up_consent_report_release_attempts
      WHERE release_request_id = legacy_request_id
    )
    OR EXISTS (
      SELECT 1 FROM app_private.management_report_release_request_claims
      WHERE release_request_id = missing_claim_request_id
    )
  THEN
    RAISE EXCEPTION '6BU negative provenance rows were not constructed';
  END IF;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('session_replication_role', 'origin', true);
  RAISE;
END
$fixture_6bu_exclusions$;

-- Direct private read: 21 trusted rows become 20 metadata items. The first
-- item is the newest historical cutoff, not a claim that it is "latest" or
-- current; this fixture checks the fixed ordering explicitly.
CREATE TEMP TABLE fixture_6bu_first_read ON COMMIT DROP AS
SELECT app_private.list_authorized_management_follow_up_consent_snapshots_v1(
  '6b800100-0000-4000-8000-000000000001'::uuid,
  '6b800300-0000-4000-8000-000000000001'::uuid
) AS document;

CREATE TEMP TABLE fixture_6bu_second_read ON COMMIT DROP AS
SELECT app_private.list_authorized_management_follow_up_consent_snapshots_v1(
  '6b800100-0000-4000-8000-000000000001'::uuid,
  '6b800300-0000-4000-8000-000000000001'::uuid
) AS document;

CREATE TEMP TABLE fixture_6bu_empty_read ON COMMIT DROP AS
SELECT app_private.list_authorized_management_follow_up_consent_snapshots_v1(
  '6b800100-0000-4000-8000-000000000001'::uuid,
  '6b800300-0000-4000-8000-000000000003'::uuid
) AS document;

DO $fixture_6bu_assert_directory$
DECLARE
  first_document jsonb;
  second_document jsonb;
  empty_document jsonb;
  item jsonb;
  item_number integer;
  prior_item jsonb;
  forbidden boolean;
  exclusion record;
  audit_count bigint;
  expected_snapshot_count bigint;
  snapshot_count bigint;
BEGIN
  SELECT document INTO STRICT first_document FROM fixture_6bu_first_read;
  SELECT document INTO STRICT second_document FROM fixture_6bu_second_read;
  SELECT document INTO STRICT empty_document FROM fixture_6bu_empty_read;

  IF first_document - ARRAY[
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    ] <> '{}'::jsonb
    OR NOT first_document ?& ARRAY[
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    ]
    OR first_document->>'access_contract_id' IS DISTINCT FROM
      'authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1'
    OR first_document->>'project_id' IS DISTINCT FROM
      '6b800300-0000-4000-8000-000000000001'
    OR jsonb_array_length(first_document->'snapshots') <> 20
    OR first_document::text ~* '(protected_report|period_results|cells|coverage|yes_count|no_count|numerator|denominator|percentage_basis_points|value_count|contributor_key|target_id|contact_id|external_subject|phone|email|pii)'
  THEN
    RAISE EXCEPTION '6BU directory envelope is not bounded or value-free: %',
      first_document;
  END IF;

  IF second_document - ARRAY['access_event_id'] IS DISTINCT FROM
      first_document - ARRAY['access_event_id']
  THEN
    RAISE EXCEPTION '6BU repeated directory read changed its metadata result';
  END IF;

  SELECT count(*) INTO snapshot_count
  FROM app_private.management_report_snapshots
  WHERE project_id = '6b800300-0000-4000-8000-000000000001'::uuid
    AND report_id = 'contact_target_follow_up_consent_ratio_two_periods'
    AND NOT EXISTS (
      SELECT 1
      FROM fixture_6bu_directory_exclusions AS excluded_row
      WHERE excluded_row.snapshot_id =
        app_private.management_report_snapshots.snapshot_id
    );
  IF snapshot_count <> 21 THEN
    RAISE EXCEPTION '6BU did not construct twenty-one consent snapshots: %',
      snapshot_count;
  END IF;

  SELECT count(*) INTO expected_snapshot_count
  FROM jsonb_array_elements(first_document->'snapshots');
  IF expected_snapshot_count <> 20 THEN
    RAISE EXCEPTION '6BU directory cap changed: %', expected_snapshot_count;
  END IF;

  item_number := 0;
  prior_item := NULL;
  FOR item IN SELECT value FROM jsonb_array_elements(first_document->'snapshots')
  LOOP
    item_number := item_number + 1;
    IF item - ARRAY[
        'snapshot_id', 'report_id', 'report_version',
        'reporting_time_zone', 'data_cutoff_utc', 'released_at_utc'
      ] <> '{}'::jsonb
      OR NOT item ?& ARRAY[
        'snapshot_id', 'report_id', 'report_version',
        'reporting_time_zone', 'data_cutoff_utc', 'released_at_utc'
      ]
      OR item->>'report_id' IS DISTINCT FROM
        'contact_target_follow_up_consent_ratio_two_periods'
      OR item->>'report_version' IS DISTINCT FROM '1'
      OR item->>'reporting_time_zone' IS DISTINCT FROM 'UTC'
    THEN
      RAISE EXCEPTION '6BU directory item contract is invalid: %', item;
    END IF;
    IF prior_item IS NOT NULL AND NOT (
      (item->>'data_cutoff_utc')::timestamptz <
        (prior_item->>'data_cutoff_utc')::timestamptz
      OR (
        (item->>'data_cutoff_utc')::timestamptz =
          (prior_item->>'data_cutoff_utc')::timestamptz
        AND (item->>'released_at_utc')::timestamptz <
          (prior_item->>'released_at_utc')::timestamptz
      )
      OR (
        (item->>'data_cutoff_utc')::timestamptz =
          (prior_item->>'data_cutoff_utc')::timestamptz
        AND (item->>'released_at_utc')::timestamptz =
          (prior_item->>'released_at_utc')::timestamptz
        AND (item->>'snapshot_id')::uuid < (prior_item->>'snapshot_id')::uuid
      )
    ) THEN
      RAISE EXCEPTION '6BU directory order is not fixed descending: % then %',
        prior_item, item;
    END IF;
    prior_item := item;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(first_document->'snapshots') AS item(value)
    WHERE item.value->>'snapshot_id' =
      '6b800800-0000-4000-8000-000000000007'
  ) OR NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(first_document->'snapshots') AS item(value)
    WHERE item.value->>'snapshot_id' =
      '6b800800-0000-4000-8000-000000000002'
  )
  THEN
    RAISE EXCEPTION '6BU directory omitted the successor or suppressed snapshot';
  END IF;

  FOR exclusion IN
    SELECT case_name, snapshot_id
    FROM fixture_6bu_directory_exclusions
    ORDER BY case_name
  LOOP
    IF EXISTS (
      SELECT 1
      FROM jsonb_array_elements(first_document->'snapshots') AS item(value)
      WHERE item.value->>'snapshot_id' = exclusion.snapshot_id::text
    ) THEN
      RAISE EXCEPTION '6BU directory admitted exclusion %', exclusion.case_name;
    END IF;
  END LOOP;

  IF empty_document->>'access_contract_id' IS DISTINCT FROM
      'authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1'
    OR jsonb_array_length(empty_document->'snapshots') <> 0
  THEN
    RAISE EXCEPTION '6BU authorized empty directory is not empty: %',
      empty_document;
  END IF;

  SELECT count(*) INTO audit_count
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events
  WHERE project_id = '6b800300-0000-4000-8000-000000000001'::uuid;
  IF audit_count <> 2 THEN
    RAISE EXCEPTION '6BU repeat reads did not create two audits: %', audit_count;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_snapshot_directory_access_events
    WHERE project_id = '6b800300-0000-4000-8000-000000000001'::uuid
      AND returned_snapshot_count <> 20
  ) OR EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_snapshot_directory_access_events
    WHERE project_id = '6b800300-0000-4000-8000-000000000003'::uuid
      AND returned_snapshot_count <> 0
  ) THEN
    RAISE EXCEPTION '6BU directory audit counts are incorrect';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_snapshot_directory_access_events AS event
    WHERE row_to_json(event)::text
      ~* '(snapshot_id|report_id|report_version|query_fingerprint|release_lineage|source_change|protected_report|period|ratio|coverage|source|contributor|target|contact|external|subject|phone|email|pii)'
  ) THEN
    RAISE EXCEPTION '6BU directory audit retained protected values';
  END IF;

  -- The audit joins back to the exact authorization evidence captured by the
  -- resolver, not a caller-provided project or capability tuple.
  IF EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_snapshot_directory_access_events
      AS event
    WHERE event.project_id = ANY (
        ARRAY[
          '6b800300-0000-4000-8000-000000000001'::uuid,
          '6b800300-0000-4000-8000-000000000003'::uuid
        ]
      )
      AND (
        event.capability_id <> 'view_anonymous_analytics'
        OR event.authorization_reference_at_utc <> event.accessed_at_utc
        OR event.organization_workspace_id <>
          '6b800200-0000-4000-8000-000000000001'::uuid
        OR event.organization_membership_id <>
          '6b800400-0000-4000-8000-000000000001'::uuid
        OR event.project_membership_id <> ALL (
          ARRAY[
            '6b800500-0000-4000-8000-000000000001'::uuid,
            '6b800500-0000-4000-8000-000000000002'::uuid,
            '6b800500-0000-4000-8000-000000000005'::uuid
          ]
        )
      )
  ) THEN
    RAISE EXCEPTION '6BU directory audit authorization evidence drifted';
  END IF;

  forbidden := false;
  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b800100-0000-4000-8000-000000000002'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU user without view capability reached directory';
  END IF;

  forbidden := false;
  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b800100-0000-4000-8000-000000000003'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU revoked capability reached directory';
  END IF;

  forbidden := false;
  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b800100-0000-4000-8000-000000000002'::uuid,
      '6b800300-0000-4000-8000-000000000003'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU cross-project authorization reached directory';
  END IF;

  forbidden := false;
  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b800100-0000-4000-8000-000000009999'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU unknown user reached directory';
  END IF;

  forbidden := false;
  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b800100-0000-4000-8000-000000000004'::uuid,
      '6b800300-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU inactive user reached directory';
  END IF;

  forbidden := false;
  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b800100-0000-4000-8000-000000000001'::uuid,
      '6b800300-0000-4000-8000-000000000004'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU inactive project reached directory';
  END IF;

  SELECT count(*) INTO audit_count
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events
  WHERE project_id = ANY (
    ARRAY[
      '6b800300-0000-4000-8000-000000000001'::uuid,
      '6b800300-0000-4000-8000-000000000003'::uuid
    ]
  );
  IF audit_count <> 3 THEN
    RAISE EXCEPTION '6BU failed authorization wrote a success audit: %',
      audit_count;
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid,uuid)',
      'EXECUTE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_follow_up_consent_snapshot_directory_access_events',
      'SELECT'
    )
    OR has_function_privilege(
      'tongxingzhe_management_follow_up_consent_ratio_reader',
      'app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid,uuid)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION '6BU direct private directory ACL is too broad';
  END IF;

  forbidden := false;
  BEGIN
    UPDATE app_private.management_follow_up_consent_snapshot_directory_access_events
    SET returned_snapshot_count = returned_snapshot_count
    WHERE project_id = '6b800300-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION 'audit UPDATE unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU audit accepted UPDATE';
  END IF;

  forbidden := false;
  BEGIN
    DELETE FROM app_private.management_follow_up_consent_snapshot_directory_access_events
    WHERE project_id = '6b800300-0000-4000-8000-000000000003'::uuid;
    RAISE EXCEPTION 'audit DELETE unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    forbidden := true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BU audit accepted DELETE';
  END IF;
END
$fixture_6bu_assert_directory$;

-- The blocked attempt is intentionally checked after the successful reads so
-- that it cannot be mistaken for a zero-count directory audit.
DO $fixture_6bu_assert_blocked$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_follow_up_consent_report_release_attempts
    WHERE release_request_id = '6b801200-0000-4000-8000-000000000001'::uuid
      AND result_status = 'blocked'
      AND released_snapshot_id IS NULL
  ) THEN
    RAISE EXCEPTION '6BU blocked provenance attempt is missing';
  END IF;
END
$fixture_6bu_assert_blocked$;

ROLLBACK;
