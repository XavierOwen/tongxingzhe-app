-- Synthetic rollback fixture for Slice 6CE consent-ratio snapshot replacement.
--
-- This fixture enables 6BO, creates approved snapshots through the 0075
-- release seam, then disables the opt-in before exercising 0083. A successful
-- replacement after that disable proves that replacement links existing
-- trusted history and does not read or regenerate the current candidate.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6ce_clock ON COMMIT DROP AS
SELECT transaction_timestamp() AS fixture_now_utc;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('83c10000-0000-4000-8000-000000000001'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
)
VALUES (
  '83c20000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6CE consent-ratio replacement workspace',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
VALUES
  (
    '83c30000-0000-4000-8000-000000000001'::uuid,
    '83c20000-0000-4000-8000-000000000001'::uuid,
    '6CE consent-ratio replacement project',
    'active',
    false
  ),
  (
    '83c30000-0000-4000-8000-000000000002'::uuid,
    '83c20000-0000-4000-8000-000000000001'::uuid,
    '6CE other project',
    'active',
    false
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  '83c40000-0000-4000-8000-000000000001'::uuid,
  '83c20000-0000-4000-8000-000000000001'::uuid,
  '83c10000-0000-4000-8000-000000000001'::uuid,
  clock.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6ce_clock AS clock;

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.project_membership_id,
       '83c40000-0000-4000-8000-000000000001'::uuid,
       membership.project_id,
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '83c50000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '83c50000-0000-4000-8000-000000000002'::uuid,
      '83c30000-0000-4000-8000-000000000002'::uuid
    )
) AS membership(project_membership_id, project_id)
CROSS JOIN fixture_6ce_clock AS clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT grant_row.capability_grant_id,
       grant_row.project_membership_id,
       'release_management_reports',
       clock.fixture_now_utc - interval '365 days',
       NULL
FROM (
  VALUES
    (
      '83c60000-0000-4000-8000-000000000001'::uuid,
      '83c50000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '83c60000-0000-4000-8000-000000000002'::uuid,
      '83c50000-0000-4000-8000-000000000002'::uuid
    )
) AS grant_row(capability_grant_id, project_membership_id)
CROSS JOIN fixture_6ce_clock AS clock;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '83c70000-0000-4000-8000-000000000001'::uuid,
  '83c10000-0000-4000-8000-000000000001'::uuid,
  '83c30000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock.fixture_now_utc - interval '365 days'
)
FROM fixture_6ce_clock AS clock;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '83c70000-0000-4000-8000-000000000002'::uuid,
  '83c10000-0000-4000-8000-000000000001'::uuid,
  '83c30000-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock.fixture_now_utc - interval '365 days'
)
FROM fixture_6ce_clock AS clock;

-- The candidate source is intentionally empty.  0074 therefore produces a
-- valid, fully suppressed two-period document with no report values exposed
-- by any release or replacement result.
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '83c10000-0000-4000-8000-000000000001'::uuid,
  '83c30000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '83c80000-0000-4000-8000-000000000001'::uuid,
  0,
  true
);
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '83c10000-0000-4000-8000-000000000001'::uuid,
  '83c30000-0000-4000-8000-000000000002'::uuid,
  'follow_up_consent_ratio@1',
  '83c80000-0000-4000-8000-000000000002'::uuid,
  0,
  true
);
RESET ROLE;

CREATE TEMP TABLE fixture_6ce_releases (
  release_order integer PRIMARY KEY,
  release_result jsonb NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6ce_releases VALUES (
  1,
  app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '83090000-0000-4000-8000-000000000001'::uuid,
    '83c10000-0000-4000-8000-000000000001'::uuid,
    '83c30000-0000-4000-8000-000000000001'::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  )
);
SELECT pg_sleep(0.01);
INSERT INTO fixture_6ce_releases VALUES (
  2,
  app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '83090000-0000-4000-8000-000000000002'::uuid,
    '83c10000-0000-4000-8000-000000000001'::uuid,
    '83c30000-0000-4000-8000-000000000001'::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  )
);
SELECT pg_sleep(0.01);
INSERT INTO fixture_6ce_releases VALUES (
  3,
  app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '83090000-0000-4000-8000-000000000003'::uuid,
    '83c10000-0000-4000-8000-000000000001'::uuid,
    '83c30000-0000-4000-8000-000000000001'::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  )
);
SELECT pg_sleep(0.01);
INSERT INTO fixture_6ce_releases VALUES (
  4,
  app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '83090000-0000-4000-8000-000000000004'::uuid,
    '83c10000-0000-4000-8000-000000000001'::uuid,
    '83c30000-0000-4000-8000-000000000002'::uuid,
    'contact_target_follow_up_consent_ratio_two_periods',
    1
  )
);

CREATE TEMP TABLE fixture_6ce_snapshot_bytes ON COMMIT DROP AS
SELECT snapshot_id, to_jsonb(snapshot.*) AS snapshot_bytes
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.snapshot_id IN (
  SELECT (release_result->>'released_snapshot_id')::uuid
  FROM fixture_6ce_releases
);

DO $assert_releases$
DECLARE
  release_statuses text;
  release_document text;
  snapshot_count bigint;
  first_snapshot_id uuid;
  second_snapshot_id uuid;
  third_snapshot_id uuid;
  other_project_snapshot_id uuid;
BEGIN
  SELECT string_agg(release_result->>'result_status', ',' ORDER BY release_order),
         string_agg(release_result::text, ' ' ORDER BY release_order),
         count(*)
  INTO release_statuses, release_document, snapshot_count
  FROM fixture_6ce_releases;

  SELECT
    (SELECT (release_result->>'released_snapshot_id')::uuid
     FROM fixture_6ce_releases WHERE release_order = 1),
    (SELECT (release_result->>'released_snapshot_id')::uuid
     FROM fixture_6ce_releases WHERE release_order = 2),
    (SELECT (release_result->>'released_snapshot_id')::uuid
     FROM fixture_6ce_releases WHERE release_order = 3),
    (SELECT (release_result->>'released_snapshot_id')::uuid
     FROM fixture_6ce_releases WHERE release_order = 4)
  INTO first_snapshot_id, second_snapshot_id, third_snapshot_id,
    other_project_snapshot_id;

  IF snapshot_count <> 4
    OR release_statuses <>
      'approved_baseline,approved,approved,approved_baseline'
    OR first_snapshot_id IS NULL
    OR second_snapshot_id IS NULL
    OR third_snapshot_id IS NULL
    OR other_project_snapshot_id IS NULL
    OR release_document ~*
      '"(protected_report|period_results|ratio|coverage|contact_id|promotion_target_id|contributor|phone|email)"[[:space:]]*:'
  THEN
    RAISE EXCEPTION
      '6CE 0075 release fixture is not four approved value-free envelopes: %',
      release_document;
  END IF;

  IF (SELECT count(*) FROM fixture_6ce_snapshot_bytes) <> 4 THEN
    RAISE EXCEPTION '6CE release fixture did not persist four snapshots';
  END IF;

  -- Keep the IDs available to the assertions below without exposing report
  -- values through the replacement result.
  CREATE TEMP TABLE fixture_6ce_snapshot_ids ON COMMIT DROP AS
  SELECT 1 AS snapshot_order, first_snapshot_id AS snapshot_id
  UNION ALL SELECT 2, second_snapshot_id
  UNION ALL SELECT 3, third_snapshot_id
  UNION ALL SELECT 4, other_project_snapshot_id;
END
$assert_releases$;

-- Replacement links historical approved snapshots after 6BO is disabled.
SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
CREATE TEMP TABLE fixture_6ce_disabled_config ON COMMIT DROP AS
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '83c10000-0000-4000-8000-000000000001'::uuid,
  '83c30000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '83c80000-0000-4000-8000-000000000003'::uuid,
  1,
  false
) AS configuration;
RESET ROLE;

DO $assert_disabled_config$
DECLARE
  configuration_document jsonb := (
    SELECT fixture_row.configuration
    FROM fixture_6ce_disabled_config AS fixture_row
  );
BEGIN
  IF configuration_document->>'status' <> 'not_enabled'
    OR configuration_document->>'enabled' <> 'false'
  THEN
    RAISE EXCEPTION
      '6CE fixture did not disable follow-up consent opt-in: %',
      configuration_document;
  END IF;
END
$assert_disabled_config$;

DO $assert_replacements$
DECLARE
  first_snapshot_id uuid;
  second_snapshot_id uuid;
  third_snapshot_id uuid;
  other_project_snapshot_id uuid;
  first_result jsonb;
  first_lifecycle jsonb;
  second_lifecycle jsonb;
  third_lifecycle jsonb;
  missing_lifecycle jsonb;
  replacement_count bigint;
BEGIN
  SELECT snapshot_id INTO first_snapshot_id
  FROM fixture_6ce_snapshot_ids WHERE snapshot_order = 1;
  SELECT snapshot_id INTO second_snapshot_id
  FROM fixture_6ce_snapshot_ids WHERE snapshot_order = 2;
  SELECT snapshot_id INTO third_snapshot_id
  FROM fixture_6ce_snapshot_ids WHERE snapshot_order = 3;
  SELECT snapshot_id INTO other_project_snapshot_id
  FROM fixture_6ce_snapshot_ids WHERE snapshot_order = 4;

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000010'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'manual_override'
    );
    RAISE EXCEPTION '6CE accepted an unlisted replacement reason';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000011'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      second_snapshot_id,
      'late_accepted_data'
    );
    RAISE EXCEPTION '6CE accepted an earlier replacement snapshot';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  -- A 0075 release request UUID is already owned by the release family.
  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '83090000-0000-4000-8000-000000000001'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'late_accepted_data'
    );
    RAISE EXCEPTION '6CE reused a 0075 release request UUID';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  first_result :=
    app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000001'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'late_accepted_data'
    );

  IF first_result - ARRAY[
      'replacement_contract_id', 'replacement_request_id', 'project_id',
      'release_lineage_id', 'report_id', 'report_version',
      'superseded_snapshot_id', 'replacement_snapshot_id',
      'replacement_reason_code', 'declared_at_utc', 'result_status'
    ] <> '{}'::jsonb
    OR NOT first_result ?& ARRAY[
      'replacement_contract_id', 'replacement_request_id', 'project_id',
      'release_lineage_id', 'report_id', 'report_version',
      'superseded_snapshot_id', 'replacement_snapshot_id',
      'replacement_reason_code', 'declared_at_utc', 'result_status'
    ]
    OR first_result->>'result_status' <> 'completed'
    OR first_result::text ~*
      '"(period_results|ratio|coverage|unknown_count|excluded_count|contact_target_link|contact_id|promotion_target_id|contributor|phone|email|raw_answer)"[[:space:]]*:'
  THEN
    RAISE EXCEPTION '6CE replacement result is not value-free: %', first_result;
  END IF;

  IF app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '830a0000-0000-4000-8000-000000000001'::uuid,
    '83c10000-0000-4000-8000-000000000001'::uuid,
    '83c30000-0000-4000-8000-000000000001'::uuid,
    first_snapshot_id,
    second_snapshot_id,
    'late_accepted_data'
  ) IS DISTINCT FROM first_result THEN
    RAISE EXCEPTION '6CE exact idempotent retry drifted';
  END IF;

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000001'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CE accepted idempotency payload drift';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '830a0000-0000-4000-8000-000000000002'::uuid,
    '83c10000-0000-4000-8000-000000000001'::uuid,
    '83c30000-0000-4000-8000-000000000001'::uuid,
    second_snapshot_id,
    third_snapshot_id,
    'contact_revision'
  );

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000003'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      third_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CE accepted a stale active head';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000004'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      third_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CE accepted a self replacement';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000005'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      other_project_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CE accepted a cross-project replacement';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
      '830a0000-0000-4000-8000-000000000006'::uuid,
      '83c10000-0000-4000-8000-000000000001'::uuid,
      '83c30000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      first_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CE accepted a cycle';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  first_lifecycle :=
    app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(
      '83c30000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id
    );
  second_lifecycle :=
    app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(
      '83c30000-0000-4000-8000-000000000001'::uuid,
      second_snapshot_id
    );
  third_lifecycle :=
    app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(
      '83c30000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id
    );
  missing_lifecycle :=
    app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(
      '83c30000-0000-4000-8000-000000000001'::uuid,
      '83ca0000-0000-4000-8000-000000000001'::uuid
    );

  IF first_lifecycle->>'lifecycle_status' <> 'superseded'
    OR first_lifecycle->>'replacement_snapshot_id' <> second_snapshot_id::text
    OR second_lifecycle->>'lifecycle_status' <> 'superseded'
    OR second_lifecycle->>'replacement_snapshot_id' <> third_snapshot_id::text
    OR third_lifecycle->>'lifecycle_status' <> 'active'
    OR third_lifecycle->'replacement_snapshot_id' <> 'null'::jsonb
    OR missing_lifecycle->>'lifecycle_status' <> 'not_found'
    OR first_lifecycle::text ~*
      '"(period_results|ratio|coverage|unknown_count|excluded_count|contact_target_link|contact_id|promotion_target_id|contributor|phone|email|raw_answer)"[[:space:]]*:'
  THEN
    RAISE EXCEPTION '6CE lifecycle result is incorrect: % / % / % / %',
      first_lifecycle, second_lifecycle, third_lifecycle, missing_lifecycle;
  END IF;

  SELECT count(*) INTO replacement_count
  FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements
  WHERE project_id = '83c30000-0000-4000-8000-000000000001'::uuid;
  IF replacement_count <> 2 THEN
    RAISE EXCEPTION '6CE replacement edge count drifted: %', replacement_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM fixture_6ce_snapshot_bytes AS before_row
    JOIN app_private.management_report_snapshots AS snapshot
      USING (snapshot_id)
    WHERE before_row.snapshot_bytes IS DISTINCT FROM to_jsonb(snapshot.*)
  ) THEN
    RAISE EXCEPTION '6CE changed an existing snapshot';
  END IF;

  BEGIN
    UPDATE app_private.management_follow_up_consent_ratio_report_snapshot_replacements
    SET replacement_reason_code = 'contact_void'
    WHERE replacement_request_id =
      '830a0000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6CE replacement history allowed UPDATE';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  BEGIN
    DELETE FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements
    WHERE replacement_request_id =
      '830a0000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6CE replacement history allowed DELETE';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END
$assert_replacements$;

ROLLBACK;
