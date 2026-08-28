-- Synthetic rollback fixture for Slice 6CD interest snapshot replacement.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('82010000-0000-4000-8000-000000000001'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name
) VALUES (
  '82020000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6CD interest replacement workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES
  (
    '82030000-0000-4000-8000-000000000001'::uuid,
    '82020000-0000-4000-8000-000000000001'::uuid,
    '6CD interest replacement project'
  ),
  (
    '82030000-0000-4000-8000-000000000002'::uuid,
    '82020000-0000-4000-8000-000000000001'::uuid,
    '6CD other project'
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '82040000-0000-4000-8000-000000000001'::uuid,
  '82020000-0000-4000-8000-000000000001'::uuid,
  '82010000-0000-4000-8000-000000000001'::uuid,
  clock_timestamp() - interval '30 days',
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '82050000-0000-4000-8000-000000000001'::uuid,
    '82040000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    '82050000-0000-4000-8000-000000000002'::uuid,
    '82040000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '82060000-0000-4000-8000-000000000001'::uuid,
    '82050000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    '82060000-0000-4000-8000-000000000002'::uuid,
    '82050000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '82070000-0000-4000-8000-000000000001'::uuid,
  '82010000-0000-4000-8000-000000000001'::uuid,
  '82030000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

SELECT app_private.configure_project_reporting_time_zone_v1(
  '82070000-0000-4000-8000-000000000002'::uuid,
  '82010000-0000-4000-8000-000000000001'::uuid,
  '82030000-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6cd_releases (
  release_order integer PRIMARY KEY,
  release_result jsonb NOT NULL
);

INSERT INTO fixture_6cd_releases VALUES
  (1, app_private.release_management_interest_report_snapshot_v1(
    '82080000-0000-4000-8000-000000000001'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  ));
INSERT INTO fixture_6cd_releases VALUES
  (2, app_private.release_management_interest_report_snapshot_v1(
    '82080000-0000-4000-8000-000000000002'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  ));
INSERT INTO fixture_6cd_releases VALUES
  (3, app_private.release_management_interest_report_snapshot_v1(
    '82080000-0000-4000-8000-000000000003'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  ));
INSERT INTO fixture_6cd_releases VALUES
  (4, app_private.release_management_interest_report_snapshot_v1(
    '82080000-0000-4000-8000-000000000004'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000002'::uuid,
    'contact_sessions_by_interest_level_two_periods',
    1
  ));

CREATE TEMP TABLE fixture_6cd_snapshot_bytes AS
SELECT snapshot_id, to_jsonb(snapshot.*) AS snapshot_bytes
FROM app_private.management_report_snapshots AS snapshot
WHERE snapshot.snapshot_id IN (
  SELECT (release_result->>'released_snapshot_id')::uuid
  FROM fixture_6cd_releases
  WHERE release_order <= 3
);

DO $fixture$
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
BEGIN
  SELECT
    (max(release_result::text) FILTER (WHERE release_order = 1)::jsonb
      ->>'released_snapshot_id')::uuid,
    (max(release_result::text) FILTER (WHERE release_order = 2)::jsonb
      ->>'released_snapshot_id')::uuid,
    (max(release_result::text) FILTER (WHERE release_order = 3)::jsonb
      ->>'released_snapshot_id')::uuid,
    (max(release_result::text) FILTER (WHERE release_order = 4)::jsonb
      ->>'released_snapshot_id')::uuid
  INTO first_snapshot_id, second_snapshot_id, third_snapshot_id,
    other_project_snapshot_id
  FROM fixture_6cd_releases;

  IF first_snapshot_id IS NULL OR second_snapshot_id IS NULL
    OR third_snapshot_id IS NULL OR other_project_snapshot_id IS NULL
    OR EXISTS (
      SELECT 1
      FROM fixture_6cd_releases
      WHERE release_result->>'result_status' NOT IN (
        'approved_baseline', 'approved'
      )
    )
  THEN
    RAISE EXCEPTION '6CD fixture could not create trusted interest snapshots';
  END IF;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82090000-0000-4000-8000-000000000010'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      second_snapshot_id,
      first_snapshot_id,
      'late_accepted_data'
    );
    RAISE EXCEPTION '6CD accepted an earlier replacement snapshot';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82090000-0000-4000-8000-000000000011'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'manual_override'
    );
    RAISE EXCEPTION '6CD accepted an unlisted replacement reason';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82080000-0000-4000-8000-000000000001'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'late_accepted_data'
    );
    RAISE EXCEPTION '6CD reused an interest release request UUID';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  first_result := app_private.declare_management_interest_snapshot_replacement_v1(
    '82090000-0000-4000-8000-000000000001'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
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
    OR first_result::text ~* 'cells|value_count|contributor|contact_id'
  THEN
    RAISE EXCEPTION '6CD replacement result is not value-free: %', first_result;
  END IF;

  IF app_private.declare_management_interest_snapshot_replacement_v1(
    '82090000-0000-4000-8000-000000000001'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
    first_snapshot_id,
    second_snapshot_id,
    'late_accepted_data'
  ) <> first_result THEN
    RAISE EXCEPTION '6CD exact idempotent retry drifted';
  END IF;

  PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
    '82090000-0000-4000-8000-000000000002'::uuid,
    '82010000-0000-4000-8000-000000000001'::uuid,
    '82030000-0000-4000-8000-000000000001'::uuid,
    second_snapshot_id,
    third_snapshot_id,
    'contact_revision'
  );

  first_lifecycle :=
    app_private.read_management_interest_report_snapshot_lifecycle_v1(
      '82030000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id
    );
  second_lifecycle :=
    app_private.read_management_interest_report_snapshot_lifecycle_v1(
      '82030000-0000-4000-8000-000000000001'::uuid,
      second_snapshot_id
    );
  third_lifecycle :=
    app_private.read_management_interest_report_snapshot_lifecycle_v1(
      '82030000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id
    );
  missing_lifecycle :=
    app_private.read_management_interest_report_snapshot_lifecycle_v1(
      '82030000-0000-4000-8000-000000000001'::uuid,
      '820a0000-0000-4000-8000-000000000001'::uuid
    );

  IF first_lifecycle->>'lifecycle_status' <> 'superseded'
    OR first_lifecycle->>'replacement_snapshot_id' <> second_snapshot_id::text
    OR second_lifecycle->>'lifecycle_status' <> 'superseded'
    OR second_lifecycle->>'replacement_snapshot_id' <> third_snapshot_id::text
    OR third_lifecycle->>'lifecycle_status' <> 'active'
    OR third_lifecycle->'replacement_snapshot_id' <> 'null'::jsonb
    OR missing_lifecycle->>'lifecycle_status' <> 'not_found'
    OR first_lifecycle::text ~* 'cells|value_count|contributor|contact_id'
  THEN
    RAISE EXCEPTION '6CD lifecycle result is incorrect';
  END IF;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82090000-0000-4000-8000-000000000001'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      second_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CD accepted idempotency payload drift';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82090000-0000-4000-8000-000000000003'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      first_snapshot_id,
      third_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CD accepted a stale head';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82090000-0000-4000-8000-000000000004'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      third_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CD accepted a self replacement';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    PERFORM app_private.declare_management_interest_snapshot_replacement_v1(
      '82090000-0000-4000-8000-000000000005'::uuid,
      '82010000-0000-4000-8000-000000000001'::uuid,
      '82030000-0000-4000-8000-000000000001'::uuid,
      third_snapshot_id,
      other_project_snapshot_id,
      'contact_void'
    );
    RAISE EXCEPTION '6CD accepted a cross-project replacement';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM fixture_6cd_snapshot_bytes AS before_row
    JOIN app_private.management_report_snapshots AS snapshot
      USING (snapshot_id)
    WHERE before_row.snapshot_bytes IS DISTINCT FROM to_jsonb(snapshot.*)
  ) THEN
    RAISE EXCEPTION '6CD changed an existing snapshot';
  END IF;

  BEGIN
    UPDATE app_private.management_interest_report_snapshot_replacements
    SET replacement_reason_code = 'contact_void'
    WHERE replacement_request_id =
      '82090000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION '6CD replacement history allowed UPDATE';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END
$fixture$;

ROLLBACK;
