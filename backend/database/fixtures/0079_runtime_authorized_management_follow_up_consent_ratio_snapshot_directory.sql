-- Synthetic rollback fixture for Slice 6BV.
--
-- This fixture rebuilds a bounded, trusted 0075 consent-ratio snapshot lineage
-- and exercises only the 0079 exact external-identity bridge. The directory
-- itself remains the 0078 private seam. All hierarchy timestamps use one
-- transaction timestamp so the fixture is stable when it is replayed after a
-- dump/restore. Every row is rolled back at the end.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6bv_clock ON COMMIT DROP AS
SELECT transaction_timestamp() AS fixture_now_utc;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b910000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b910000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b910000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6b910000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('6b910000-0000-4000-8000-000000000005'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  (
    '6b911000-0000-4000-8000-000000000001'::uuid,
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'active-reader',
    '6b910000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b911000-0000-4000-8000-000000000002'::uuid,
    ' https://runtime-follow-up-consent-directory.synthetic/auth/v1 ',
    'spaced-reader',
    '6b910000-0000-4000-8000-000000000002'::uuid
  ),
  (
    '6b911000-0000-4000-8000-000000000003'::uuid,
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'release-only-reader',
    '6b910000-0000-4000-8000-000000000003'::uuid
  ),
  (
    '6b911000-0000-4000-8000-000000000004'::uuid,
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'inactive-reader',
    '6b910000-0000-4000-8000-000000000004'::uuid
  ),
  (
    '6b911000-0000-4000-8000-000000000005'::uuid,
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'no-capability-reader',
    '6b910000-0000-4000-8000-000000000005'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
)
VALUES (
  '6b920000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BV runtime consent directory organization',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
VALUES
  (
    '6b930000-0000-4000-8000-000000000001'::uuid,
    '6b920000-0000-4000-8000-000000000001'::uuid,
    '6BV runtime consent directory project',
    'active', false
  ),
  (
    '6b930000-0000-4000-8000-000000000002'::uuid,
    '6b920000-0000-4000-8000-000000000001'::uuid,
    '6BV unauthorized cross-project',
    'active', false
  ),
  (
    '6b930000-0000-4000-8000-000000000003'::uuid,
    '6b920000-0000-4000-8000-000000000001'::uuid,
    '6BV authorized empty project',
    'active', false
  );

-- Every parent and child range is derived from one stable instant. The fifth
-- user has a real project membership but no view capability, which keeps the
-- unauthorized case distinct from an unknown identity.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.membership_id,
       '6b920000-0000-4000-8000-000000000001'::uuid,
       membership.app_user_id,
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '6b940000-0000-4000-8000-000000000001'::uuid,
      '6b910000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b940000-0000-4000-8000-000000000002'::uuid,
      '6b910000-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b940000-0000-4000-8000-000000000003'::uuid,
      '6b910000-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6b940000-0000-4000-8000-000000000004'::uuid,
      '6b910000-0000-4000-8000-000000000004'::uuid
    ),
    (
      '6b940000-0000-4000-8000-000000000005'::uuid,
      '6b910000-0000-4000-8000-000000000005'::uuid
    )
) AS membership(membership_id, app_user_id)
CROSS JOIN fixture_6bv_clock AS clock;

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
      '6b950000-0000-4000-8000-000000000001'::uuid,
      '6b940000-0000-4000-8000-000000000001'::uuid,
      '6b930000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b950000-0000-4000-8000-000000000002'::uuid,
      '6b940000-0000-4000-8000-000000000002'::uuid,
      '6b930000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b950000-0000-4000-8000-000000000003'::uuid,
      '6b940000-0000-4000-8000-000000000003'::uuid,
      '6b930000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b950000-0000-4000-8000-000000000004'::uuid,
      '6b940000-0000-4000-8000-000000000004'::uuid,
      '6b930000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b950000-0000-4000-8000-000000000005'::uuid,
      '6b940000-0000-4000-8000-000000000005'::uuid,
      '6b930000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b950000-0000-4000-8000-000000000006'::uuid,
      '6b940000-0000-4000-8000-000000000002'::uuid,
      '6b930000-0000-4000-8000-000000000003'::uuid
    )
) AS membership(membership_id, organization_membership_id, project_id)
CROSS JOIN fixture_6bv_clock AS clock;

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
      '6b960000-0000-4000-8000-000000000001'::uuid,
      '6b950000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b960000-0000-4000-8000-000000000002'::uuid,
      '6b950000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b960000-0000-4000-8000-000000000003'::uuid,
      '6b950000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b960000-0000-4000-8000-000000000004'::uuid,
      '6b950000-0000-4000-8000-000000000003'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b960000-0000-4000-8000-000000000005'::uuid,
      '6b950000-0000-4000-8000-000000000004'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b960000-0000-4000-8000-000000000006'::uuid,
      '6b950000-0000-4000-8000-000000000006'::uuid,
      'view_anonymous_analytics'::text
    )
) AS grant_row(grant_id, project_membership_id, capability_id)
CROSS JOIN fixture_6bv_clock AS clock;

-- The bridge must reject this otherwise valid identity before it reaches the
-- private directory. The historical membership and grant remain present.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '6b910000-0000-4000-8000-000000000004'::uuid;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b970000-0000-4000-8000-000000000001'::uuid,
  '6b910000-0000-4000-8000-000000000001'::uuid,
  '6b930000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock.fixture_now_utc - interval '365 days'
)
FROM fixture_6bv_clock AS clock;

-- Build twenty-one trusted 0075 snapshots as the closed release writer. The
-- protected document is synthetic but conforms to the existing validator;
-- the runtime bridge must expose only the metadata directory envelope.
SET LOCAL ROLE tongxingzhe_management_consent_ratio_snapshot_release_writer;
DO $fixture_6bv_snapshots$
DECLARE
  fixture_now_utc timestamptz := transaction_timestamp();
  zone_effective_utc timestamptz;
  fixture_owner_id constant uuid :=
    '6b910000-0000-4000-8000-000000000001';
  fixture_project_id constant uuid :=
    '6b930000-0000-4000-8000-000000000001';
  fixture_workspace_id constant uuid :=
    '6b920000-0000-4000-8000-000000000001';
  fixture_membership_id constant uuid :=
    '6b940000-0000-4000-8000-000000000001';
  fixture_project_membership_id constant uuid :=
    '6b950000-0000-4000-8000-000000000001';
  fixture_capability_grant_id constant uuid :=
    '6b960000-0000-4000-8000-000000000001';
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
  zone_document jsonb;
  ratio_document jsonb;
  previous_coverage jsonb;
  current_coverage jsonb;
  report_document jsonb;
  result_document jsonb;
  snapshot_number integer;
  result_status text;
  shared_period_count integer;
  assessed_cell_count integer;
BEGIN
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
      '6b990000-0000-4000-8000-%s',
      lpad(snapshot_number::text, 12, '0')
    )::uuid;
    snapshot_id = format(
      '6b980000-0000-4000-8000-%s',
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

    zone_document = app_private.resolve_management_report_periods_v1(
      'UTC', cutoff_utc
    );
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
      'periods', zone_document,
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
$fixture_6bv_snapshots$;
RESET ROLE;

CREATE TEMP TABLE fixture_6bv_counts ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.app_users) AS app_users,
  (SELECT count(*) FROM app_data.external_identities) AS external_identities,
  (SELECT count(*) FROM app_data.workspaces) AS workspaces,
  (SELECT count(*) FROM app_data.projects) AS projects;

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6bv_runtime$
DECLARE
  active_result jsonb;
  repeated_result jsonb;
  exact_spaced_result jsonb;
  empty_result jsonb;
  forbidden boolean;
  item jsonb;
  prior_item jsonb;
BEGIN
  active_result = app_data.list_authorized_management_follow_up_consent_snapshots_v1(
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'active-reader',
    '6b930000-0000-4000-8000-000000000001'::uuid
  );
  IF active_result - ARRAY[
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    ] <> '{}'::jsonb
    OR NOT active_result ?& ARRAY[
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    ]
    OR active_result->>'access_contract_id' IS DISTINCT FROM
      'authorized_follow_up_consent_ratio_management_report_snapshot_directory_v1'
    OR active_result->>'project_id' IS DISTINCT FROM
      '6b930000-0000-4000-8000-000000000001'
    OR jsonb_array_length(active_result->'snapshots') <> 20
    OR active_result::text ~* '(protected_report|period_results|cells|coverage|yes_count|no_count|numerator|denominator|percentage_basis_points|value_count|contributor|target_id|contact_id|external_subject|phone|email|pii)'
  THEN
    RAISE EXCEPTION '6BV bridge returned an invalid directory envelope: %',
      active_result;
  END IF;

  FOR item IN
    SELECT value FROM jsonb_array_elements(active_result->'snapshots')
  LOOP
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
      RAISE EXCEPTION '6BV bridge directory item contract is invalid: %', item;
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
        AND (item->>'snapshot_id')::uuid <
          (prior_item->>'snapshot_id')::uuid
      )
    ) THEN
      RAISE EXCEPTION '6BV bridge directory order drifted: % then %',
        prior_item, item;
    END IF;
    prior_item = item;
  END LOOP;

  repeated_result = app_data.list_authorized_management_follow_up_consent_snapshots_v1(
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'active-reader',
    '6b930000-0000-4000-8000-000000000001'::uuid
  );
  IF repeated_result - ARRAY['access_event_id'] IS DISTINCT FROM
      active_result - ARRAY['access_event_id']
    OR repeated_result->>'access_event_id' IS NOT DISTINCT FROM
      active_result->>'access_event_id'
  THEN
    RAISE EXCEPTION '6BV repeated bridge read did not preserve metadata';
  END IF;

  -- The stored issuer contains spaces. A clean issuer must not be normalized
  -- into a match; the exact stored value succeeds separately.
  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'spaced-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BV bridge trimmed a stored external identity';
  END IF;

  exact_spaced_result =
    app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      ' https://runtime-follow-up-consent-directory.synthetic/auth/v1 ',
      'spaced-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
  IF exact_spaced_result->>'access_event_id' IS NULL
    OR jsonb_array_length(exact_spaced_result->'snapshots') <> 20
  THEN
    RAISE EXCEPTION '6BV exact stored external identity did not resolve';
  END IF;

  empty_result = app_data.list_authorized_management_follow_up_consent_snapshots_v1(
    'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
    'active-reader',
    '6b930000-0000-4000-8000-000000000003'::uuid
  );
  IF empty_result->>'project_id' IS DISTINCT FROM
      '6b930000-0000-4000-8000-000000000003'
    OR jsonb_array_length(empty_result->'snapshots') <> 0
  THEN
    RAISE EXCEPTION '6BV authorized empty project was not empty: %', empty_result;
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'release-only-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BV release-only identity reached directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'no-capability-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BV unauthorized identity reached directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'active-reader',
      '6b930000-0000-4000-8000-000000000002'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BV cross-project authorization reached directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'inactive-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BV inactive identity reached directory';
  END IF;

  forbidden = false;
  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'unknown-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
  EXCEPTION WHEN insufficient_privilege THEN
    forbidden = true;
  END;
  IF NOT forbidden THEN
    RAISE EXCEPTION '6BV unknown identity reached directory';
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      NULL::text,
      'active-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted a null issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      '   ',
      'active-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted a blank issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      NULL::text,
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted a null subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      '   ',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted a blank subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      repeat('i', 2049),
      'active-reader',
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted an overlong issuer';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      repeat('s', 513),
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted an overlong subject';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_follow_up_consent_snapshots_v1(
      'https://runtime-follow-up-consent-directory.synthetic/auth/v1',
      'active-reader',
      NULL::uuid
    );
    RAISE EXCEPTION '6BV bridge accepted a null project';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.list_authorized_management_follow_up_consent_snapshots_v1(
      '6b910000-0000-4000-8000-000000000002'::uuid,
      '6b930000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6BV runtime role received direct private access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$fixture_6bv_runtime$;

RESET ROLE;

DO $fixture_6bv_audit$
DECLARE
  expected_counts record;
  actual_counts record;
  history_text text;
  audit_count bigint;
BEGIN
  SELECT * INTO STRICT expected_counts FROM fixture_6bv_counts;
  SELECT
    (SELECT count(*) FROM app_data.app_users) AS app_users,
    (SELECT count(*) FROM app_data.external_identities) AS external_identities,
    (SELECT count(*) FROM app_data.workspaces) AS workspaces,
    (SELECT count(*) FROM app_data.projects) AS projects
  INTO STRICT actual_counts;
  IF actual_counts.app_users IS DISTINCT FROM expected_counts.app_users
    OR actual_counts.external_identities IS DISTINCT FROM
      expected_counts.external_identities
    OR actual_counts.workspaces IS DISTINCT FROM expected_counts.workspaces
    OR actual_counts.projects IS DISTINCT FROM expected_counts.projects
  THEN
    RAISE EXCEPTION '6BV unknown identity bootstrapped application rows';
  END IF;

  SELECT count(*) INTO audit_count
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events
  WHERE project_id = '6b930000-0000-4000-8000-000000000001'::uuid;
  IF audit_count <> 3 THEN
    RAISE EXCEPTION '6BV repeated/identity reads wrote wrong audit count: %',
      audit_count;
  END IF;

  SELECT count(*) INTO audit_count
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events
  WHERE project_id = '6b930000-0000-4000-8000-000000000003'::uuid;
  IF audit_count <> 1 THEN
    RAISE EXCEPTION '6BV empty directory did not write one audit: %',
      audit_count;
  END IF;

  SELECT string_agg(row_to_json(event)::text, ' ')
  INTO history_text
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events
    AS event
  WHERE event.project_id = ANY (ARRAY[
    '6b930000-0000-4000-8000-000000000001'::uuid,
    '6b930000-0000-4000-8000-000000000003'::uuid
  ]);
  IF history_text ~* '(snapshot_id|report_id|period_results|cells|ratio|coverage|source|contributor|target|contact|external_subject|subject|phone|email|pii)'
  THEN
    RAISE EXCEPTION '6BV bridge audit retained protected values';
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
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.external_identities',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION '6BV runtime received direct private or identity access';
  END IF;
END
$fixture_6bv_audit$;

ROLLBACK;
