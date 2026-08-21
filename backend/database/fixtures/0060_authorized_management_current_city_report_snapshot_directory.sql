-- Synthetic fixture for the 6AS current-city snapshot directory.
--
-- The fixture builds twenty-one approved current-city snapshots through the
-- same 0057 protected document validator and provenance tables.  It also
-- creates one snapshot without current-city provenance and one blocked
-- attempt; neither may enter the directory.  All rows are rolled back.
\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('a6110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('a6110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('a6110000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('a6110000-0000-4000-8000-000000000004'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
) VALUES
  (
    'a61e0000-0000-4000-8000-000000000001'::uuid,
    'https://current-city-directory.synthetic/auth/v1',
    'active-reader',
    'a6110000-0000-4000-8000-000000000002'::uuid
  ),
  (
    'a61e0000-0000-4000-8000-000000000002'::uuid,
    'https://current-city-directory.synthetic/auth/v1',
    'release-only',
    'a6110000-0000-4000-8000-000000000003'::uuid
  ),
  (
    'a61e0000-0000-4000-8000-000000000003'::uuid,
    ' https://current-city-directory.synthetic/auth/v1 ',
    'spaced-reader',
    'a6110000-0000-4000-8000-000000000002'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  deleted_at
) VALUES (
  'a6120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AS current-city directory workspace',
  NULL
);

INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default
) VALUES
  (
    'a6130000-0000-4000-8000-000000000001'::uuid,
    'a6120000-0000-4000-8000-000000000001'::uuid,
    '6AS current-city directory project',
    'active',
    false
  ),
  (
    'a6130000-0000-4000-8000-000000000002'::uuid,
    'a6120000-0000-4000-8000-000000000001'::uuid,
    '6AS empty current-city directory project',
    'active',
    false
  );

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    'a6140000-0000-4000-8000-000000000001'::uuid,
    'a6120000-0000-4000-8000-000000000001'::uuid,
    'a6110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6140000-0000-4000-8000-000000000002'::uuid,
    'a6120000-0000-4000-8000-000000000001'::uuid,
    'a6110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6140000-0000-4000-8000-000000000003'::uuid,
    'a6120000-0000-4000-8000-000000000001'::uuid,
    'a6110000-0000-4000-8000-000000000003'::uuid,
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
    'a6150000-0000-4000-8000-000000000001'::uuid,
    'a6140000-0000-4000-8000-000000000001'::uuid,
    'a6130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6150000-0000-4000-8000-000000000002'::uuid,
    'a6140000-0000-4000-8000-000000000002'::uuid,
    'a6130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6150000-0000-4000-8000-000000000003'::uuid,
    'a6140000-0000-4000-8000-000000000003'::uuid,
    'a6130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6150000-0000-4000-8000-000000000004'::uuid,
    'a6140000-0000-4000-8000-000000000002'::uuid,
    'a6130000-0000-4000-8000-000000000002'::uuid,
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
    'a6160000-0000-4000-8000-000000000001'::uuid,
    'a6150000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6160000-0000-4000-8000-000000000002'::uuid,
    'a6150000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6160000-0000-4000-8000-000000000003'::uuid,
    'a6150000-0000-4000-8000-000000000003'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6160000-0000-4000-8000-000000000004'::uuid,
    'a6150000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days',
    NULL
  ),
  (
    'a6160000-0000-4000-8000-000000000005'::uuid,
    'a6150000-0000-4000-8000-000000000004'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days',
    NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  'a6170000-0000-4000-8000-000000000001'::uuid,
  'a6110000-0000-4000-8000-000000000001'::uuid,
  'a6130000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

SELECT app_private.configure_project_reporting_time_zone_v1(
  'a6170000-0000-4000-8000-000000000002'::uuid,
  'a6110000-0000-4000-8000-000000000002'::uuid,
  'a6130000-0000-4000-8000-000000000002'::uuid,
  0,
  'UTC',
  clock_timestamp() - interval '30 days'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
) VALUES ('fixture-6as-target-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
)
VALUES
  (
    'fixture-6as-country',
    'fixture-6as-target-v1',
    NULL,
    '6AS Country',
    'country'
  ),
  (
    'fixture-6as-city',
    'fixture-6as-target-v1',
    'fixture-6as-country',
    '6AS City',
    'city'
  ),
  (
    'fixture-6as-venue',
    'fixture-6as-target-v1',
    'fixture-6as-city',
    '6AS Venue',
    'venue'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
) VALUES (
  'fixture-6as-boundary',
  'fixture-6as-venue',
  'fixture-6as-target-v1',
  polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.69))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6as-target-v1',
  true
);

DO $fixture_6as_setup$
DECLARE
  project_id_value uuid :=
    'a6130000-0000-4000-8000-000000000001'::uuid;
  release_user_id uuid :=
    'a6110000-0000-4000-8000-000000000001'::uuid;
  workspace_id_value uuid :=
    'a6120000-0000-4000-8000-000000000001'::uuid;
  organization_membership_id_value uuid :=
    'a6140000-0000-4000-8000-000000000001'::uuid;
  project_membership_id_value uuid :=
    'a6150000-0000-4000-8000-000000000001'::uuid;
  capability_grant_id_value uuid :=
    'a6160000-0000-4000-8000-000000000001'::uuid;
  time_zone_effective_from_utc_value timestamp with time zone;
  data_cutoff_value timestamp with time zone;
  periods_value jsonb;
  target_context_value jsonb;
  report_document jsonb;
  release_result_document jsonb;
  snapshot_id_value uuid;
  release_request_id_value uuid;
  previous_snapshot_id_value uuid := NULL;
  target_tree_version_value text;
  target_content_fingerprint_value text;
  release_number integer;
  legacy_channel_cutoff timestamp with time zone;
  legacy_channel_release_result jsonb;
  legacy_channel_v2_release_result jsonb;
BEGIN
  SELECT version_row.effective_from_utc
  INTO STRICT time_zone_effective_from_utc_value
  FROM app_private.project_reporting_time_zone_versions AS version_row
  WHERE version_row.project_id = project_id_value
    AND version_row.version_number = 1;

  FOR release_number IN 1..21 LOOP
    data_cutoff_value = date_trunc(
      'milliseconds',
      clock_timestamp()
    ) + interval '1 second' + (release_number - 1) * interval '1 minute';
    periods_value = app_private.resolve_management_report_periods_v1(
      'UTC',
      data_cutoff_value
    );
    target_context_value =
      app_private.resolve_management_current_city_target_context_v1(
        data_cutoff_value
      );
    target_tree_version_value =
      target_context_value->>'target_tree_version';
    target_content_fingerprint_value =
      target_context_value->>'target_content_fingerprint';

    report_document = jsonb_build_object(
      'report_id', 'contact_sessions_by_current_city_two_periods',
      'report_version', 1,
      'metric_id', 'contact_sessions',
      'metric_version', 1,
      'dimension', 'current_city',
      'view_mode', 'current',
      'region_granularity', 'city',
      'query_fingerprint',
        'management-report:contact_sessions_by_current_city_two_periods:v1',
      'privacy_policy', 'management_current_city_contact_session_privacy_v1',
      'source_scope', 'backend_accepted_active_contacts_current_revision',
      'project_id', project_id_value,
      'periods', periods_value,
      'data_cutoff_utc', to_char(
        data_cutoff_value AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', 0,
      'target_context', target_context_value,
      'result_status', 'completed',
      'cells', jsonb_build_array(
        jsonb_build_object(
          'period_key', 'previous',
          'city_id', 'fixture-6as-city',
          'cell_order', 0,
          'value_count', 10,
          'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'period_key', 'current',
          'city_id', 'fixture-6as-city',
          'cell_order', 1,
          'value_count', 10,
          'privacy_status', 'displayed'
        )
      )
    );

    PERFORM app_private.validate_management_current_city_report_document_v1(
      report_document
    );

    snapshot_id_value = (
      'a61a0000-0000-4000-8000-'
      || lpad(release_number::text, 12, '0')
    )::uuid;
    release_request_id_value = (
      'a61b0000-0000-4000-8000-'
      || lpad(release_number::text, 12, '0')
    )::uuid;

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
      snapshot_id_value,
      release_request_id_value,
      release_user_id,
      project_id_value,
      'management-region-report:contact_sessions_by_current_city_two_periods',
      'contact_sessions_by_current_city_two_periods',
      1,
      'management-report:contact_sessions_by_current_city_two_periods:v1',
      'UTC',
      data_cutoff_value,
      data_cutoff_value,
      previous_snapshot_id_value,
      0,
      report_document
    );

    release_result_document = jsonb_build_object(
      'release_contract_id',
        'current_city_management_report_snapshot_release_v1',
      'release_request_id', release_request_id_value,
      'project_id', project_id_value,
      'release_lineage_id',
        'management-region-report:contact_sessions_by_current_city_two_periods',
      'report_id', 'contact_sessions_by_current_city_two_periods',
      'report_version', 1,
      'query_fingerprint',
        'management-report:contact_sessions_by_current_city_two_periods:v1',
      'reporting_time_zone_version_number', 1,
      'reporting_time_zone', 'UTC',
      'data_cutoff_utc', to_char(
        data_cutoff_value AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'target_tree_version', target_tree_version_value,
      'target_content_fingerprint', target_content_fingerprint_value,
      'compared_snapshot_id', previous_snapshot_id_value,
      'released_snapshot_id', snapshot_id_value,
      'result_status', CASE
        WHEN release_number = 1 THEN 'approved_baseline'
        ELSE 'approved'
      END,
      'reason_codes', '[]'::jsonb
    );

    INSERT INTO app_private.management_current_city_report_release_attempts (
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
      target_tree_version,
      target_content_fingerprint,
      compared_snapshot_id,
      released_snapshot_id,
      result_status,
      reason_codes,
      result_document
    ) VALUES (
      release_request_id_value,
      release_user_id,
      workspace_id_value,
      organization_membership_id_value,
      project_membership_id_value,
      capability_grant_id_value,
      'release_management_reports',
      data_cutoff_value,
      project_id_value,
      1,
      'UTC',
      time_zone_effective_from_utc_value,
      data_cutoff_value,
      'management-region-report:contact_sessions_by_current_city_two_periods',
      'contact_sessions_by_current_city_two_periods',
      1,
      'management-report:contact_sessions_by_current_city_two_periods:v1',
      target_tree_version_value,
      target_content_fingerprint_value,
      previous_snapshot_id_value,
      snapshot_id_value,
      CASE
        WHEN release_number = 1 THEN 'approved_baseline'
        ELSE 'approved'
      END,
      '[]'::jsonb,
      release_result_document
    );

    previous_snapshot_id_value = snapshot_id_value;
  END LOOP;

  -- A real legacy channel release in the other project is deliberately
  -- present beside the current-city lineage.  The directory must not reuse
  -- this older provenance family, even when the runtime caller can view the
  -- other project.
  legacy_channel_v2_release_result =
    app_private.release_management_report_snapshot_v2(
      'a61b0000-0000-4000-8000-000000000097'::uuid,
      'a6110000-0000-4000-8000-000000000002'::uuid,
      'a6130000-0000-4000-8000-000000000002'::uuid,
      'contact_sessions_by_channel_two_periods',
      1
    );
  IF legacy_channel_v2_release_result->>'result_status' NOT IN (
      'approved_baseline', 'approved'
    )
    OR legacy_channel_v2_release_result->>'released_snapshot_id' IS NULL
    OR legacy_channel_v2_release_result->>'release_contract_id' IS DISTINCT FROM
      'trusted_management_report_snapshot_release_v2'
  THEN
    RAISE EXCEPTION 'legacy channel v2 provenance setup was not approved';
  END IF;

  legacy_channel_cutoff = date_trunc(
    'milliseconds',
    clock_timestamp()
  ) + interval '3 hours';
  legacy_channel_release_result =
    app_private.release_management_report_snapshot_v1(
      'a61b0000-0000-4000-8000-000000000096'::uuid,
      release_user_id,
      'a6130000-0000-4000-8000-000000000002'::uuid,
      'contact_sessions_by_channel_two_periods',
      1,
      'UTC',
      legacy_channel_cutoff,
      legacy_channel_cutoff
    );
  IF legacy_channel_release_result->>'result_status' NOT IN (
      'approved_baseline', 'approved'
    )
    OR legacy_channel_release_result->>'released_snapshot_id' IS NULL
  THEN
    RAISE EXCEPTION 'legacy channel provenance setup was not approved';
  END IF;

  -- A valid protected snapshot without a 0057 current-city attempt is not a
  -- directory entry.  This is the missing-provenance negative case.
  data_cutoff_value = date_trunc(
    'milliseconds',
    clock_timestamp()
  ) + interval '1 hour';
  periods_value = app_private.resolve_management_report_periods_v1(
    'UTC',
    data_cutoff_value
  );
  target_context_value =
    app_private.resolve_management_current_city_target_context_v1(
      data_cutoff_value
    );
  report_document = jsonb_build_object(
    'report_id', 'contact_sessions_by_current_city_two_periods',
    'report_version', 1,
    'metric_id', 'contact_sessions',
    'metric_version', 1,
    'dimension', 'current_city',
    'view_mode', 'current',
    'region_granularity', 'city',
    'query_fingerprint',
      'management-report:contact_sessions_by_current_city_two_periods:v1',
    'privacy_policy', 'management_current_city_contact_session_privacy_v1',
    'source_scope', 'backend_accepted_active_contacts_current_revision',
    'project_id', project_id_value,
    'periods', periods_value,
    'data_cutoff_utc', to_char(
      data_cutoff_value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'source_change_sequence', 0,
    'target_context', target_context_value,
    'result_status', 'completed',
    'cells', jsonb_build_array(
      jsonb_build_object(
        'period_key', 'previous', 'city_id', 'fixture-6as-city',
        'cell_order', 0, 'value_count', 10, 'privacy_status', 'displayed'
      ),
      jsonb_build_object(
        'period_key', 'current', 'city_id', 'fixture-6as-city',
        'cell_order', 1, 'value_count', 10, 'privacy_status', 'displayed'
      )
    )
  );
  PERFORM app_private.validate_management_current_city_report_document_v1(
    report_document
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
    'a61a0000-0000-4000-8000-000000000099'::uuid,
    'a61b0000-0000-4000-8000-000000000099'::uuid,
    release_user_id,
    project_id_value,
    'management-region-report:contact_sessions_by_current_city_two_periods',
    'contact_sessions_by_current_city_two_periods',
    1,
    'management-report:contact_sessions_by_current_city_two_periods:v1',
    'UTC',
    data_cutoff_value,
    data_cutoff_value,
    previous_snapshot_id_value,
    0,
    report_document
  );

  -- A blocked attempt is also excluded because it has no released snapshot.
  data_cutoff_value = date_trunc(
    'milliseconds',
    clock_timestamp()
  ) + interval '2 hours';
  release_request_id_value =
    'a61b0000-0000-4000-8000-000000000098'::uuid;
  release_result_document = jsonb_build_object(
    'release_contract_id',
      'current_city_management_report_snapshot_release_v1',
    'release_request_id', release_request_id_value,
    'project_id', project_id_value,
    'release_lineage_id',
      'management-region-report:contact_sessions_by_current_city_two_periods',
    'report_id', 'contact_sessions_by_current_city_two_periods',
    'report_version', 1,
    'query_fingerprint',
      'management-report:contact_sessions_by_current_city_two_periods:v1',
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', 'UTC',
    'data_cutoff_utc', to_char(
      data_cutoff_value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'target_tree_version', NULL,
    'target_content_fingerprint', NULL,
    'compared_snapshot_id', previous_snapshot_id_value,
    'released_snapshot_id', NULL,
    'result_status', 'blocked',
    'reason_codes', jsonb_build_array('release_target_context_unavailable')
  );
  INSERT INTO app_private.management_current_city_report_release_attempts (
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
    target_tree_version,
    target_content_fingerprint,
    compared_snapshot_id,
    released_snapshot_id,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    release_request_id_value,
    release_user_id,
    workspace_id_value,
    organization_membership_id_value,
    project_membership_id_value,
    capability_grant_id_value,
    'release_management_reports',
    data_cutoff_value,
    project_id_value,
    1,
    'UTC',
    time_zone_effective_from_utc_value,
    data_cutoff_value,
    'management-region-report:contact_sessions_by_current_city_two_periods',
    'contact_sessions_by_current_city_two_periods',
    1,
    'management-report:contact_sessions_by_current_city_two_periods:v1',
    NULL,
    NULL,
    previous_snapshot_id_value,
    NULL,
    'blocked',
    jsonb_build_array('release_target_context_unavailable'),
      release_result_document
  );

  -- A blocked release may carry a drifted target tuple, but without a
  -- released snapshot it is never a directory entry.  This is distinct from
  -- the unavailable-target attempt above and protects the join boundary.
  data_cutoff_value = date_trunc(
    'milliseconds',
    clock_timestamp()
  ) + interval '4 hours';
  release_request_id_value =
    'a61b0000-0000-4000-8000-000000000095'::uuid;
  release_result_document = jsonb_build_object(
    'release_contract_id',
      'current_city_management_report_snapshot_release_v1',
    'release_request_id', release_request_id_value,
    'project_id', project_id_value,
    'release_lineage_id',
      'management-region-report:contact_sessions_by_current_city_two_periods',
    'report_id', 'contact_sessions_by_current_city_two_periods',
    'report_version', 1,
    'query_fingerprint',
      'management-report:contact_sessions_by_current_city_two_periods:v1',
    'reporting_time_zone_version_number', 1,
    'reporting_time_zone', 'UTC',
    'data_cutoff_utc', to_char(
      data_cutoff_value AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'target_tree_version', target_tree_version_value || '-drift',
    'target_content_fingerprint', repeat('f', 64),
    'compared_snapshot_id', previous_snapshot_id_value,
    'released_snapshot_id', NULL,
    'result_status', 'blocked',
    'reason_codes', jsonb_build_array('release_target_context_changed')
  );
  INSERT INTO app_private.management_current_city_report_release_attempts (
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
    target_tree_version,
    target_content_fingerprint,
    compared_snapshot_id,
    released_snapshot_id,
    result_status,
    reason_codes,
    result_document
  ) VALUES (
    release_request_id_value,
    release_user_id,
    workspace_id_value,
    organization_membership_id_value,
    project_membership_id_value,
    capability_grant_id_value,
    'release_management_reports',
    data_cutoff_value,
    project_id_value,
    1,
    'UTC',
    time_zone_effective_from_utc_value,
    data_cutoff_value,
    'management-region-report:contact_sessions_by_current_city_two_periods',
    'contact_sessions_by_current_city_two_periods',
    1,
    'management-report:contact_sessions_by_current_city_two_periods:v1',
    target_tree_version_value || '-drift',
    repeat('f', 64),
    previous_snapshot_id_value,
    NULL,
    'blocked',
    jsonb_build_array('release_target_context_changed'),
    release_result_document
  );
END
$fixture_6as_setup$;

SET LOCAL ROLE tongxingzhe_runtime;

DO $fixture_6as_runtime$
DECLARE
  project_id_value uuid :=
    'a6130000-0000-4000-8000-000000000001'::uuid;
  empty_project_id_value uuid :=
    'a6130000-0000-4000-8000-000000000002'::uuid;
  directory_result jsonb;
  empty_result jsonb;
  spaced_result jsonb;
BEGIN
  directory_result =
    app_data.list_authorized_management_current_city_report_snapshots_v1(
      'https://current-city-directory.synthetic/auth/v1',
      'active-reader',
      project_id_value
    );

  IF directory_result - ARRAY[
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    ] <> '{}'::jsonb
    OR NOT directory_result ?& ARRAY[
      'access_contract_id', 'access_event_id', 'project_id', 'snapshots'
    ]
    OR directory_result->>'access_contract_id' IS DISTINCT FROM
      'authorized_current_city_management_report_snapshot_directory_v1'
    OR (directory_result->>'project_id')::uuid IS DISTINCT FROM project_id_value
    OR jsonb_array_length(directory_result->'snapshots') <> 20
    OR directory_result::text ~
      '(protected_report|cells|target_context|target_tree_version|canonical_name|contributor|coordinates)'
  THEN
    RAISE EXCEPTION 'current-city directory root or privacy contract is invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(directory_result->'snapshots') AS item(value)
    WHERE item.value - ARRAY[
        'snapshot_id', 'report_id', 'report_version',
        'reporting_time_zone', 'data_cutoff_utc', 'released_at_utc'
      ] <> '{}'::jsonb
      OR NOT item.value ?& ARRAY[
        'snapshot_id', 'report_id', 'report_version',
        'reporting_time_zone', 'data_cutoff_utc', 'released_at_utc'
      ]
      OR item.value->>'report_id' IS DISTINCT FROM
        'contact_sessions_by_current_city_two_periods'
      OR item.value->>'report_version' IS DISTINCT FROM '1'
      OR item.value->>'reporting_time_zone' IS DISTINCT FROM 'UTC'
  ) THEN
    RAISE EXCEPTION 'current-city directory item field contract is invalid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(directory_result->'snapshots')
      WITH ORDINALITY AS item(value, position)
    JOIN jsonb_array_elements(directory_result->'snapshots')
      WITH ORDINALITY AS previous(value, position)
      ON previous.position + 1 = item.position
    WHERE ROW(
      (previous.value->>'data_cutoff_utc')::timestamptz,
      (previous.value->>'released_at_utc')::timestamptz,
      (previous.value->>'snapshot_id')::uuid
    ) < ROW(
      (item.value->>'data_cutoff_utc')::timestamptz,
      (item.value->>'released_at_utc')::timestamptz,
      (item.value->>'snapshot_id')::uuid
    )
  ) THEN
    RAISE EXCEPTION 'current-city directory order is not descending and stable';
  END IF;

  IF directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', 'a61a0000-0000-4000-8000-000000000001'
      ))
    OR directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', 'a61a0000-0000-4000-8000-000000000099'
      ))
    OR directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', 'a61a0000-0000-4000-8000-000000000095'
      ))
    OR directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', 'a61a0000-0000-4000-8000-000000000096'
      ))
    OR directory_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', 'a61a0000-0000-4000-8000-000000000098'
      ))
  THEN
    RAISE EXCEPTION
      'current-city directory admitted an old, cross-project, drifted, or unavailable snapshot';
  END IF;

  empty_result =
    app_data.list_authorized_management_current_city_report_snapshots_v1(
      'https://current-city-directory.synthetic/auth/v1',
      'active-reader',
      empty_project_id_value
    );
  IF empty_result->'snapshots' <> '[]'::jsonb
    OR empty_result->'snapshots' @>
      jsonb_build_array(jsonb_build_object(
        'snapshot_id', 'a61a0000-0000-4000-8000-000000000096'
      ))
  THEN
    RAISE EXCEPTION
      'cross-project legacy channel snapshot entered current-city directory';
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_current_city_report_snapshots_v1(
      'https://current-city-directory.synthetic/auth/v1',
      'spaced-reader',
      project_id_value
    );
    RAISE EXCEPTION 'runtime directory trimmed a stored external identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  spaced_result =
    app_data.list_authorized_management_current_city_report_snapshots_v1(
      ' https://current-city-directory.synthetic/auth/v1 ',
      'spaced-reader',
      project_id_value
    );
  IF spaced_result->>'access_contract_id' IS DISTINCT FROM
      'authorized_current_city_management_report_snapshot_directory_v1'
    OR jsonb_array_length(spaced_result->'snapshots') <> 20
  THEN
    RAISE EXCEPTION 'exact stored external identity did not resolve';
  END IF;

  BEGIN
    PERFORM app_data.list_authorized_management_current_city_report_snapshots_v1(
      'https://current-city-directory.synthetic/auth/v1',
      'unknown-reader',
      project_id_value
    );
    RAISE EXCEPTION 'runtime directory accepted an unknown identity';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_current_city_report_snapshots_v1(
      'https://current-city-directory.synthetic/auth/v1',
      'release-only',
      project_id_value
    );
    RAISE EXCEPTION 'release-only identity read a current-city directory';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_data.list_authorized_management_current_city_report_snapshots_v1(
      'https://current-city-directory.synthetic/auth/v1',
      'active-reader',
      'a6130000-0000-4000-8000-000000000099'::uuid
    );
    RAISE EXCEPTION 'runtime directory accepted an unauthorized project';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  BEGIN
    PERFORM app_private.list_authorized_management_current_city_report_snapshots_v1(
      'a6110000-0000-4000-8000-000000000002'::uuid,
      project_id_value
    );
    RAISE EXCEPTION 'runtime received direct private directory access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

END
$fixture_6as_runtime$;

RESET ROLE;

DO $fixture_6as_audit$
DECLARE
  audit_event_id uuid;
  history_text text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_attempts AS channel_attempt
    JOIN app_private.management_report_snapshots AS channel_snapshot
      ON channel_snapshot.snapshot_id = channel_attempt.released_snapshot_id
    WHERE channel_attempt.release_request_id =
      'a61b0000-0000-4000-8000-000000000096'::uuid
      AND channel_attempt.report_id = 'contact_sessions_by_channel_two_periods'
      AND channel_snapshot.project_id =
        'a6130000-0000-4000-8000-000000000002'::uuid
  )
  OR NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_release_v2_attempts AS channel_v2_attempt
    JOIN app_private.management_report_snapshots AS channel_v2_snapshot
      ON channel_v2_snapshot.snapshot_id =
        channel_v2_attempt.released_snapshot_id
    WHERE channel_v2_attempt.release_request_id =
      'a61b0000-0000-4000-8000-000000000097'::uuid
      AND channel_v2_attempt.report_id =
        'contact_sessions_by_channel_two_periods'
      AND channel_v2_snapshot.project_id =
        'a6130000-0000-4000-8000-000000000002'::uuid
  )
  OR NOT EXISTS (
    SELECT 1
    FROM app_private.management_report_snapshots AS missing_snapshot
    WHERE missing_snapshot.snapshot_id =
      'a61a0000-0000-4000-8000-000000000099'::uuid
  )
  OR EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_release_attempts
    WHERE released_snapshot_id =
      'a61a0000-0000-4000-8000-000000000099'::uuid
  )
  OR NOT EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_release_attempts
    WHERE release_request_id = 'a61b0000-0000-4000-8000-000000000098'::uuid
      AND result_status = 'blocked'
      AND reason_codes = '["release_target_context_unavailable"]'::jsonb
      AND released_snapshot_id IS NULL
  )
  OR NOT EXISTS (
    SELECT 1
    FROM app_private.management_current_city_report_release_attempts
    WHERE release_request_id = 'a61b0000-0000-4000-8000-000000000095'::uuid
      AND result_status = 'blocked'
      AND reason_codes = '["release_target_context_changed"]'::jsonb
      AND target_tree_version LIKE '%-drift'
      AND target_content_fingerprint = repeat('f', 64)
      AND released_snapshot_id IS NULL
  )
  THEN
    RAISE EXCEPTION
      'current-city directory negative provenance cases were not constructed';
  END IF;

  IF (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_directory_access_events
    WHERE requested_by_app_user_id =
      'a6110000-0000-4000-8000-000000000002'::uuid
  ) <> 3
  OR (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_directory_access_events
    WHERE requested_by_app_user_id =
      'a6110000-0000-4000-8000-000000000002'::uuid
      AND project_id =
        'a6130000-0000-4000-8000-000000000001'::uuid
      AND capability_grant_id =
        'a6160000-0000-4000-8000-000000000002'::uuid
      AND returned_snapshot_count = 20
      AND result_status = 'completed'
  ) <> 2
  OR (
    SELECT count(*)
    FROM app_private.management_current_city_report_snapshot_directory_access_events
    WHERE requested_by_app_user_id =
      'a6110000-0000-4000-8000-000000000002'::uuid
      AND project_id =
        'a6130000-0000-4000-8000-000000000002'::uuid
      AND returned_snapshot_count = 0
      AND result_status = 'completed'
  ) <> 1
  THEN
    RAISE EXCEPTION 'current-city directory audit is incomplete';
  END IF;

  SELECT string_agg(to_jsonb(event)::text, ' ')
  INTO history_text
  FROM app_private.management_current_city_report_snapshot_directory_access_events
    AS event
  WHERE event.requested_by_app_user_id =
    'a6110000-0000-4000-8000-000000000002'::uuid;
  IF history_text ~
      '(snapshot_id|report_id|protected_report|cells|target_tree_version|subject|contributor|coordinates)'
  THEN
    RAISE EXCEPTION 'current-city directory audit retained protected values';
  END IF;

  SELECT event.access_event_id
  INTO STRICT audit_event_id
  FROM app_private.management_current_city_report_snapshot_directory_access_events
    AS event
  WHERE event.requested_by_app_user_id =
    'a6110000-0000-4000-8000-000000000002'::uuid
    AND event.returned_snapshot_count = 20
  ORDER BY event.accessed_at_utc, event.access_event_id
  LIMIT 1;

  BEGIN
    UPDATE app_private.management_current_city_report_snapshot_directory_access_events
    SET returned_snapshot_count = 0
    WHERE access_event_id = audit_event_id;
    RAISE EXCEPTION 'current-city directory audit accepted UPDATE';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    DELETE FROM
      app_private.management_current_city_report_snapshot_directory_access_events
    WHERE access_event_id = audit_event_id;
    RAISE EXCEPTION 'current-city directory audit accepted DELETE';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;
END
$fixture_6as_audit$;

ROLLBACK;
