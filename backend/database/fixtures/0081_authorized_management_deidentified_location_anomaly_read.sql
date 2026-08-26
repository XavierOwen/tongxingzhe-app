-- Synthetic rollback fixture for Slice 6CC.
--
-- The fixture exercises the version-1 deidentified location-anomaly
-- directory/detail contracts using only the accepted contact revision and its
-- immutable provenance row.  It deliberately includes current, stale,
-- voided, cross-project, resolved and not-applicable evidence so that a
-- mapped source is not mistaken for a currently reportable anomaly.  All
-- timestamps derive from one transaction timestamp and every row is rolled
-- back.  Identifiers use the 6CC namespace so the fixture does not borrow
-- committed rows from the concurrency suite.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6cc_clock ON COMMIT DROP AS
SELECT transaction_timestamp() AS fixture_now_utc;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6cc10000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6cc10000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6cc10000-0000-4000-8000-000000000003'::uuid, 'active'),
  ('6cc10000-0000-4000-8000-000000000004'::uuid, 'active'),
  ('6cc10000-0000-4000-8000-000000000005'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at
)
VALUES (
  '6cc20000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6CC deidentified anomaly workspace',
  NULL,
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
    '6cc30000-0000-4000-8000-000000000001'::uuid,
    '6cc20000-0000-4000-8000-000000000001'::uuid,
    '6CC primary project',
    'active',
    false
  ),
  (
    '6cc30000-0000-4000-8000-000000000002'::uuid,
    '6cc20000-0000-4000-8000-000000000001'::uuid,
    '6CC cross-project target',
    'active',
    false
  ),
  (
    '6cc30000-0000-4000-8000-000000000003'::uuid,
    '6cc20000-0000-4000-8000-000000000001'::uuid,
    '6CC inactive project',
    'active',
    false
  );

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current,
  published_at
)
SELECT
  version_row.questionnaire_version_id,
  version_row.project_id,
  1,
  'published',
  true,
  base.fixture_now_utc - interval '365 days'
FROM fixture_6cc_clock AS base
CROSS JOIN (
  VALUES
    (
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6cc40000-0000-4000-8000-000000000002'::uuid,
      '6cc30000-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6cc40000-0000-4000-8000-000000000003'::uuid,
      '6cc30000-0000-4000-8000-000000000003'::uuid
    )
) AS version_row(questionnaire_version_id, project_id);

-- A single published tree is needed only to create one resolved control row.
-- That control must not become an anomaly merely because a provenance row
-- exists for it.
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
)
VALUES ('fixture-6cc-tree-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
)
VALUES
  (
    'fixture-6cc-country',
    'fixture-6cc-tree-v1',
    NULL,
    '6CC Country',
    'country'
  ),
  (
    'fixture-6cc-city',
    'fixture-6cc-tree-v1',
    'fixture-6cc-country',
    '6CC City',
    'city'
  ),
  (
    'fixture-6cc-venue',
    'fixture-6cc-tree-v1',
    'fixture-6cc-city',
    '6CC Venue',
    'venue'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
)
VALUES (
  'fixture-6cc-venue-boundary',
  'fixture-6cc-venue',
  'fixture-6cc-tree-v1',
  polygon '((-87.70,41.80),(-87.60,41.80),(-87.60,41.90),(-87.70,41.90))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6cc-tree-v1',
  false
);

CREATE TEMP TABLE fixture_6cc_region_fingerprint ON COMMIT DROP AS
SELECT content_fingerprint
FROM app_data.canonical_region_tree_releases
WHERE tree_version = 'fixture-6cc-tree-v1';

-- Every hierarchy range uses the same lower bound. This prevents a restore
-- clock or planner timing from making a child row precede its parent.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  membership_row.organization_membership_id,
  '6cc20000-0000-4000-8000-000000000001'::uuid,
  membership_row.app_user_id,
  base.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6cc_clock AS base
CROSS JOIN (
  VALUES
    (
      '6cc50000-0000-4000-8000-000000000001'::uuid,
      '6cc10000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6cc50000-0000-4000-8000-000000000002'::uuid,
      '6cc10000-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6cc50000-0000-4000-8000-000000000003'::uuid,
      '6cc10000-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6cc50000-0000-4000-8000-000000000004'::uuid,
      '6cc10000-0000-4000-8000-000000000004'::uuid
    ),
    (
      '6cc50000-0000-4000-8000-000000000005'::uuid,
      '6cc10000-0000-4000-8000-000000000005'::uuid
    )
) AS membership_row(organization_membership_id, app_user_id);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  membership_row.project_membership_id,
  membership_row.organization_membership_id,
  membership_row.project_id,
  base.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6cc_clock AS base
CROSS JOIN (
  VALUES
    (
      '6cc60000-0000-4000-8000-000000000001'::uuid,
      '6cc50000-0000-4000-8000-000000000001'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6cc60000-0000-4000-8000-000000000002'::uuid,
      '6cc50000-0000-4000-8000-000000000002'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6cc60000-0000-4000-8000-000000000003'::uuid,
      '6cc50000-0000-4000-8000-000000000003'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6cc60000-0000-4000-8000-000000000004'::uuid,
      '6cc50000-0000-4000-8000-000000000004'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6cc60000-0000-4000-8000-000000000005'::uuid,
      '6cc50000-0000-4000-8000-000000000001'::uuid,
      '6cc30000-0000-4000-8000-000000000003'::uuid
    ),
    (
      '6cc60000-0000-4000-8000-000000000006'::uuid,
      '6cc50000-0000-4000-8000-000000000005'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    )
) AS membership_row(
  project_membership_id,
  organization_membership_id,
  project_id
);

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT
  grant_row.capability_grant_id,
  grant_row.project_membership_id,
  grant_row.capability_id,
  base.fixture_now_utc - interval '365 days',
  NULL
FROM fixture_6cc_clock AS base
CROSS JOIN (
  VALUES
    (
      '6cc70000-0000-4000-8000-000000000001'::uuid,
      '6cc60000-0000-4000-8000-000000000001'::uuid,
      'view_deidentified_anomalies'::text
    ),
    (
      '6cc70000-0000-4000-8000-000000000002'::uuid,
      '6cc60000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6cc70000-0000-4000-8000-000000000003'::uuid,
      '6cc60000-0000-4000-8000-000000000003'::uuid,
      'view_deidentified_anomalies'::text
    ),
    (
      '6cc70000-0000-4000-8000-000000000004'::uuid,
      '6cc60000-0000-4000-8000-000000000004'::uuid,
      'view_deidentified_anomalies'::text
    ),
    (
      '6cc70000-0000-4000-8000-000000000005'::uuid,
      '6cc60000-0000-4000-8000-000000000005'::uuid,
      'view_deidentified_anomalies'::text
    ),
    (
      '6cc70000-0000-4000-8000-000000000006'::uuid,
      '6cc60000-0000-4000-8000-000000000006'::uuid,
      'view_deidentified_anomalies'::text
    )
) AS grant_row(capability_grant_id, project_membership_id, capability_id);

-- Membership and capability history are valid when created. Revoke the
-- otherwise-unused reader only after the hierarchy has been established, so
-- the authorization negative exercises account state rather than a malformed
-- membership fixture.
UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '6cc10000-0000-4000-8000-000000000004'::uuid;

-- The contact projection and its accepted revisions are synthetic. The
-- revision trigger is the only provenance writer; no fixture row is inserted
-- directly into contact_location_provenance.
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
  place_name,
  smallest_region_id,
  region_tree_version,
  latitude,
  longitude,
  location_accuracy_meters,
  current_revision,
  lifecycle_status,
  reach_count,
  interest_level
)
SELECT
  contact_row.contact_id,
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  '6cc20000-0000-4000-8000-000000000001'::uuid,
  contact_row.project_id,
  contact_row.questionnaire_version_id,
  base.fixture_now_utc - contact_row.occurred_offset,
  'UTC',
  base.fixture_now_utc - contact_row.occurred_offset + interval '1 hour',
  contact_row.channel,
  contact_row.location_kind,
  contact_row.place_name,
  contact_row.smallest_region_id,
  contact_row.region_tree_version,
  contact_row.latitude,
  contact_row.longitude,
  contact_row.location_accuracy_meters,
  contact_row.current_revision,
  contact_row.lifecycle_status,
  1,
  2
FROM fixture_6cc_clock AS base
CROSS JOIN (
  VALUES
    (
      '6cc-pending'::text,
      '6cc30000-0000-4000-8000-000000000001'::uuid,
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      interval '1 day',
      'face_to_face'::text,
      'pending_resolution'::text,
      NULL::text,
      NULL::text,
      NULL::text,
      41.881832::double precision,
      -87.623177::double precision,
      12.5::double precision,
      1,
      'active'::text
    ),
    (
      '6cc-legacy'::text,
      '6cc30000-0000-4000-8000-000000000001'::uuid,
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      interval '2 days',
      'voice_call'::text,
      'not_applicable'::text,
      NULL::text,
      NULL::text,
      NULL::text,
      NULL::double precision,
      NULL::double precision,
      NULL::double precision,
      1,
      'active'::text
    ),
    (
      '6cc-corrected'::text,
      '6cc30000-0000-4000-8000-000000000001'::uuid,
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      interval '1 day 30 minutes',
      'face_to_face'::text,
      'pending_resolution'::text,
      NULL::text,
      NULL::text,
      NULL::text,
      41.884400::double precision,
      -87.627700::double precision,
      18.0::double precision,
      2,
      'active'::text
    ),
    (
      '6cc-old-revision'::text,
      '6cc30000-0000-4000-8000-000000000001'::uuid,
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      interval '3 days',
      'voice_call'::text,
      'not_applicable'::text,
      NULL::text,
      NULL::text,
      NULL::text,
      NULL::double precision,
      NULL::double precision,
      NULL::double precision,
      2,
      'active'::text
    ),
    (
      '6cc-voided'::text,
      '6cc30000-0000-4000-8000-000000000001'::uuid,
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      interval '4 days',
      'face_to_face'::text,
      'pending_resolution'::text,
      NULL::text,
      NULL::text,
      NULL::text,
      41.882000::double precision,
      -87.624000::double precision,
      15.0::double precision,
      1,
      'voided'::text
    ),
    (
      '6cc-resolved'::text,
      '6cc30000-0000-4000-8000-000000000001'::uuid,
      '6cc40000-0000-4000-8000-000000000001'::uuid,
      interval '5 days',
      'face_to_face'::text,
      'resolved'::text,
      '6CC Venue'::text,
      'fixture-6cc-venue'::text,
      'fixture-6cc-tree-v1'::text,
      NULL::double precision,
      NULL::double precision,
      NULL::double precision,
      1,
      'active'::text
    ),
    (
      '6cc-cross-project'::text,
      '6cc30000-0000-4000-8000-000000000002'::uuid,
      '6cc40000-0000-4000-8000-000000000002'::uuid,
      interval '6 days',
      'face_to_face'::text,
      'pending_resolution'::text,
      NULL::text,
      NULL::text,
      NULL::text,
      41.883000::double precision,
      -87.625000::double precision,
      20.0::double precision,
      1,
      'active'::text
    )
) AS contact_row(
  contact_id,
  project_id,
  questionnaire_version_id,
  occurred_offset,
  channel,
  location_kind,
  place_name,
  smallest_region_id,
  region_tree_version,
  latitude,
  longitude,
  location_accuracy_meters,
  current_revision,
  lifecycle_status
);

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  revised_at_utc,
  reason,
  snapshot
)
SELECT
  revision_row.contact_id,
  revision_row.revision_number,
  revision_row.revision_kind,
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc - revision_row.revised_offset,
  revision_row.reason,
  revision_row.snapshot
FROM fixture_6cc_clock AS base
CROSS JOIN (
  VALUES
    (
      '6cc-pending'::text,
      1,
      'submitted'::text,
      interval '1 day',
      NULL::text,
      jsonb_build_object(
        'contactId', '6cc-pending',
        'location', jsonb_build_object(
          'kind', 'pending_resolution',
          'latitude', 41.881832,
          'longitude', -87.623177,
          'accuracyMeters', 12.5
        )
      )
    ),
    (
      '6cc-legacy'::text,
      1,
      'submitted'::text,
      interval '2 days',
      NULL::text,
      jsonb_build_object('contactId', '6cc-legacy', 'legacyField', 'retained')
    ),
    (
      '6cc-corrected'::text,
      1,
      'submitted'::text,
      interval '1 day 30 minutes',
      NULL::text,
      jsonb_build_object(
        'contactId', '6cc-corrected',
        'legacyField', 'superseded by correction'
      )
    ),
    (
      '6cc-old-revision'::text,
      1,
      'submitted'::text,
      interval '3 days',
      NULL::text,
      jsonb_build_object(
        'contactId', '6cc-old-revision',
        'location', jsonb_build_object(
          'kind', 'pending_resolution',
          'latitude', 41.884000,
          'longitude', -87.626000,
          'accuracyMeters', 9.0
        )
      )
    ),
    (
      '6cc-old-revision'::text,
      2,
      'corrected'::text,
      interval '2 days 23 hours',
      '6CC superseded the pending revision',
      jsonb_build_object(
        'contactId', '6cc-old-revision',
        'location', jsonb_build_object('kind', 'not_applicable')
      )
    ),
    (
      '6cc-voided'::text,
      1,
      'submitted'::text,
      interval '4 days',
      NULL::text,
      jsonb_build_object(
        'contactId', '6cc-voided',
        'location', jsonb_build_object(
          'kind', 'pending_resolution',
          'latitude', 41.882000,
          'longitude', -87.624000,
          'accuracyMeters', 15.0
        )
      )
    ),
    (
      '6cc-cross-project'::text,
      1,
      'submitted'::text,
      interval '6 days',
      NULL::text,
      jsonb_build_object(
        'contactId', '6cc-cross-project',
        'location', jsonb_build_object(
          'kind', 'pending_resolution',
          'latitude', 41.883000,
          'longitude', -87.625000,
          'accuracyMeters', 20.0
        )
      )
    )
) AS revision_row(
  contact_id,
  revision_number,
  revision_kind,
  revised_offset,
  reason,
  snapshot
);

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  revised_at_utc,
  reason,
  snapshot
)
SELECT
  '6cc-corrected',
  2,
  'corrected',
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc - interval '1 day 29 minutes',
  '6CC corrected the location after the legacy submission',
  jsonb_build_object(
    'contactId', '6cc-corrected',
    'location', jsonb_build_object(
      'kind', 'pending_resolution',
      'latitude', 41.884400,
      'longitude', -87.627700,
      'accuracyMeters', 18.0
    )
  )
FROM fixture_6cc_clock AS base;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  revised_at_utc,
  reason,
  snapshot
)
SELECT
  '6cc-resolved',
  1,
  'submitted',
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc - interval '5 days',
  NULL,
  jsonb_build_object(
    'contactId', '6cc-resolved',
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', '6CC Venue',
      'smallestRegionId', 'fixture-6cc-venue',
      'regionTreeVersion', 'fixture-6cc-tree-v1'
    ),
    'locationSource', jsonb_build_object(
      'kind', 'captured_coordinates',
      'latitude', 41.850000,
      'longitude', -87.650000,
      'accuracyMeters', 5.0,
      'resolverContractVersion', 'canonical-region-resolution:v1',
      'regionTreeContentFingerprint', fingerprint.content_fingerprint
    )
  )
FROM fixture_6cc_clock AS base
CROSS JOIN fixture_6cc_region_fingerprint AS fingerprint;

-- Twenty-one current pending anomalies share one occurrence time. The
-- directory must return the twenty greatest opaque IDs at that time, rather
-- than relying on insertion order or a client-side limit.
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
  latitude,
  longitude,
  location_accuracy_meters,
  current_revision,
  lifecycle_status,
  reach_count,
  interest_level
)
SELECT
  format('6cc-cap-%s', lpad(series_row::text, 2, '0')),
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  '6cc20000-0000-4000-8000-000000000001'::uuid,
  '6cc30000-0000-4000-8000-000000000001'::uuid,
  '6cc40000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc - interval '1 hour',
  'UTC',
  base.fixture_now_utc - interval '1 hour',
  'face_to_face',
  'pending_resolution',
  (41.80 + series_row / 1000.0)::double precision,
  (-87.60 - series_row / 1000.0)::double precision,
  10.0::double precision,
  1,
  'active',
  1,
  2
FROM fixture_6cc_clock AS base
CROSS JOIN generate_series(1, 21) AS series_row;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  revised_at_utc,
  reason,
  snapshot
)
SELECT
  format('6cc-cap-%s', lpad(series_row::text, 2, '0')),
  1,
  'submitted',
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc - interval '1 hour',
  NULL,
  jsonb_build_object(
    'contactId', format('6cc-cap-%s', lpad(series_row::text, 2, '0')),
    'location', jsonb_build_object(
      'kind', 'pending_resolution',
      'latitude', (41.80 + series_row / 1000.0)::double precision,
      'longitude', (-87.60 - series_row / 1000.0)::double precision,
      'accuracyMeters', 10.0
    )
  )
FROM fixture_6cc_clock AS base
CROSS JOIN generate_series(1, 21) AS series_row;

-- Drafts and contact attempts intentionally have no accepted revision and no
-- contact_location_provenance seam. Their future-looking timestamps make an
-- accidental join visible in the directory contract below.
INSERT INTO app_data.contact_attempts (
  attempt_id,
  app_user_id,
  workspace_id,
  project_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel,
  linked_contact_id
)
SELECT
  '6cc-attempt',
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  '6cc20000-0000-4000-8000-000000000001'::uuid,
  '6cc30000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc + interval '1 hour',
  'UTC',
  base.fixture_now_utc + interval '1 hour',
  'face_to_face',
  NULL
FROM fixture_6cc_clock AS base;

INSERT INTO app_data.contact_drafts (
  draft_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  created_at_utc,
  updated_at_utc,
  deleted_at_utc,
  current_revision,
  source_device_id,
  content
)
SELECT
  '6cc-draft',
  '6cc10000-0000-4000-8000-000000000001'::uuid,
  '6cc20000-0000-4000-8000-000000000001'::uuid,
  '6cc30000-0000-4000-8000-000000000001'::uuid,
  '6cc40000-0000-4000-8000-000000000001'::uuid,
  base.fixture_now_utc,
  base.fixture_now_utc,
  NULL,
  1,
  '6cc-device',
  jsonb_build_object(
    'location', jsonb_build_object(
      'kind', 'pending_resolution',
      'latitude', 41.90,
      'longitude', -87.70
    )
  )
FROM fixture_6cc_clock AS base;

CREATE TEMP TABLE fixture_6cc_anomalies ON COMMIT DROP AS
SELECT
  mapping.anomaly_id,
  source.contact_id,
  source.revision_number,
  source.location_kind,
  source.evidence_kind
FROM app_private.deidentified_location_anomaly_ids AS mapping
JOIN app_data.contact_location_provenance AS source
  ON source.source_id = mapping.source_id
WHERE source.contact_id LIKE '6cc-%';

DO $fixture_6cc_source_map$
DECLARE
  mapped_count integer;
  pending_count integer;
  legacy_count integer;
  old_revision_count integer;
  voided_count integer;
  cross_project_count integer;
  corrected_count integer;
  cap_count integer;
  resolved_count integer;
  not_applicable_count integer;
BEGIN
  SELECT count(*) INTO mapped_count FROM fixture_6cc_anomalies;
  SELECT count(*) INTO pending_count
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-pending' AND revision_number = 1
    AND evidence_kind = 'pending_coordinates';
  SELECT count(*) INTO legacy_count
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-legacy' AND revision_number = 1
    AND evidence_kind = 'legacy_incomplete';
  SELECT count(*) INTO old_revision_count
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-old-revision' AND revision_number = 1;
  SELECT count(*) INTO voided_count
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-voided' AND revision_number = 1;
  SELECT count(*) INTO cross_project_count
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-cross-project' AND revision_number = 1;
  SELECT count(*) INTO corrected_count
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-corrected' AND revision_number = 2
    AND evidence_kind = 'pending_coordinates';
  SELECT count(*) INTO cap_count
  FROM fixture_6cc_anomalies
  WHERE contact_id LIKE '6cc-cap-%' AND revision_number = 1
    AND evidence_kind = 'pending_coordinates';
  SELECT count(*) INTO resolved_count
  FROM app_data.contact_location_provenance
  WHERE contact_id = '6cc-resolved'
    AND location_kind = 'resolved';
  SELECT count(*) INTO not_applicable_count
  FROM app_data.contact_location_provenance
  WHERE contact_id = '6cc-old-revision'
    AND revision_number = 2
    AND evidence_kind = 'not_applicable';

  IF mapped_count <> 28
    OR pending_count <> 1
    OR legacy_count <> 1
    OR old_revision_count <> 1
    OR voided_count <> 1
    OR cross_project_count <> 1
    OR corrected_count <> 1
    OR cap_count <> 21
    OR resolved_count <> 1
    OR not_applicable_count <> 1
  THEN
    RAISE EXCEPTION
      '6CC provenance map setup was not complete: mapped %, pending %, legacy %, old %, voided %, cross %, corrected %, cap %, resolved %, not-applicable %',
      mapped_count,
      pending_count,
      legacy_count,
      old_revision_count,
      voided_count,
      cross_project_count,
      corrected_count,
      cap_count,
      resolved_count,
      not_applicable_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM fixture_6cc_anomalies
    WHERE contact_id IN ('6cc-resolved', '6cc-old-revision')
      AND revision_number = 2
  ) THEN
    RAISE EXCEPTION '6CC resolved/current not-applicable evidence was mapped';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM fixture_6cc_anomalies
    WHERE contact_id IN ('6cc-draft', '6cc-attempt')
  ) THEN
    RAISE EXCEPTION
      '6CC draft or contact-attempt data crossed the accepted-revision provenance seam';
  END IF;
END
$fixture_6cc_source_map$;

CREATE TEMP TABLE fixture_6cc_cap_anomalies ON COMMIT DROP AS
SELECT *
FROM fixture_6cc_anomalies
WHERE contact_id LIKE '6cc-cap-%';

CREATE TEMP TABLE fixture_6cc_reads (
  read_name text PRIMARY KEY,
  document jsonb NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6cc_reads (read_name, document)
VALUES (
  'directory_first',
  app_private.list_authorized_deidentified_location_anomalies_v1(
    '6cc10000-0000-4000-8000-000000000001'::uuid,
    '6cc30000-0000-4000-8000-000000000001'::uuid
  )
), (
  'directory_second',
  app_private.list_authorized_deidentified_location_anomalies_v1(
    '6cc10000-0000-4000-8000-000000000001'::uuid,
    '6cc30000-0000-4000-8000-000000000001'::uuid
  )
);

DO $fixture_6cc_directory_contract$
DECLARE
  directory_first jsonb;
  directory_second jsonb;
  directory_item jsonb;
  directory_item_count integer;
  expected_cap_ids uuid[];
  returned_cap_ids uuid[];
  expected_cap_occurred_at text;
  expected_keys text[] := ARRAY[
    'anomaly_id',
    'evidence_kind',
    'has_usable_coordinates',
    'location_kind',
    'occurred_at_utc',
    'reason_code',
    'status'
  ];
BEGIN
  SELECT document INTO STRICT directory_first
  FROM fixture_6cc_reads
  WHERE read_name = 'directory_first';
  SELECT document INTO STRICT directory_second
  FROM fixture_6cc_reads
  WHERE read_name = 'directory_second';

  SELECT array_agg(anomaly_id ORDER BY anomaly_id DESC)
  INTO STRICT expected_cap_ids
  FROM (
    SELECT anomaly_id
    FROM fixture_6cc_cap_anomalies
    ORDER BY anomaly_id DESC
    LIMIT 20
  ) AS expected;

  SELECT array_agg(
      (item.value->>'anomaly_id')::uuid ORDER BY item.ordinality
    )
  INTO STRICT returned_cap_ids
  FROM jsonb_array_elements(directory_first->'anomalies')
    WITH ORDINALITY AS item(value, ordinality);

  SELECT to_char(
      (base.fixture_now_utc - interval '1 hour') AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  INTO STRICT expected_cap_occurred_at
  FROM fixture_6cc_clock AS base;

  IF directory_first->>'access_contract_id'
      IS DISTINCT FROM
        'authorized_deidentified_location_anomaly_directory_v1'
    OR directory_first->>'project_id'
      IS DISTINCT FROM '6cc30000-0000-4000-8000-000000000001'
    OR jsonb_array_length(directory_first->'anomalies') <> 20
    OR directory_first->>'access_event_id' IS NULL
    OR directory_second->>'access_event_id' IS NULL
    OR directory_first->>'access_event_id'
      = directory_second->>'access_event_id'
    OR directory_first->'anomalies' <> directory_second->'anomalies'
    OR returned_cap_ids IS DISTINCT FROM expected_cap_ids
    OR directory_first ?| ARRAY[
      'latitude',
      'longitude',
      'accuracy_meters',
      'coordinates',
      'contact_id',
      'revision_number',
      'source_id',
      'app_user_id'
    ]
    OR (
      SELECT count(*) FROM jsonb_object_keys(directory_first)
    ) <> 4
    OR NOT (directory_first ?& ARRAY[
      'access_contract_id',
      'access_event_id',
      'anomalies',
      'project_id'
    ])
  THEN
    RAISE EXCEPTION '6CC directory contract or repeated result is invalid: % / %',
      directory_first,
      directory_second;
  END IF;

  SELECT count(*) INTO directory_item_count
  FROM jsonb_array_elements(directory_first->'anomalies') AS item(value)
  WHERE (
      SELECT count(*) FROM jsonb_object_keys(item.value)
    ) <> 7
    OR NOT (item.value ?& expected_keys)
    OR item.value->>'occurred_at_utc'
      IS DISTINCT FROM expected_cap_occurred_at
    OR item.value->>'reason_code' IS DISTINCT FROM 'pending_resolution'
    OR item.value->>'location_kind'
      IS DISTINCT FROM 'pending_resolution'
    OR item.value->>'evidence_kind'
      IS DISTINCT FROM 'pending_coordinates'
    OR item.value->>'has_usable_coordinates' IS DISTINCT FROM 'true'
    OR item.value ?| ARRAY[
      'latitude',
      'longitude',
      'accuracy_meters',
      'coordinates',
      'contact_id',
      'revision_number',
      'source_id',
      'app_user_id'
    ];
  IF directory_item_count <> 0 THEN
    RAISE EXCEPTION '6CC directory exposed forbidden or extra fields';
  END IF;

  SELECT item.value INTO STRICT directory_item
  FROM jsonb_array_elements(directory_first->'anomalies') AS item(value)
  ORDER BY (item.value->>'occurred_at_utc') DESC, item.value->>'anomaly_id' DESC
  LIMIT 1;
  IF directory_item->>'reason_code' IS DISTINCT FROM 'pending_resolution'
    OR directory_item->>'evidence_kind'
      IS DISTINCT FROM 'pending_coordinates'
    OR directory_item->>'location_kind'
      IS DISTINCT FROM 'pending_resolution'
    OR directory_item->>'has_usable_coordinates' IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION '6CC pending directory item is invalid: %', directory_item;
  END IF;

END
$fixture_6cc_directory_contract$;

-- Remove the cap-only controls from current eligibility, then prove the
-- ordinary directory exposes both anomaly reasons and a current correction.
UPDATE app_data.contacts
SET lifecycle_status = 'voided'
WHERE contact_id LIKE '6cc-cap-%';

INSERT INTO fixture_6cc_reads (read_name, document)
VALUES (
  'directory_anomaly_kinds',
  app_private.list_authorized_deidentified_location_anomalies_v1(
    '6cc10000-0000-4000-8000-000000000001'::uuid,
    '6cc30000-0000-4000-8000-000000000001'::uuid
  )
);

DO $fixture_6cc_directory_anomaly_kinds$
DECLARE
  directory_document jsonb;
  expected_ids uuid[];
  returned_ids uuid[];
  corrected_id uuid;
BEGIN
  SELECT document INTO STRICT directory_document
  FROM fixture_6cc_reads
  WHERE read_name = 'directory_anomaly_kinds';

  SELECT
    array_agg(
      mapping.anomaly_id
      ORDER BY contact.occurred_at_utc DESC, mapping.anomaly_id DESC
    ),
    (array_agg(mapping.anomaly_id) FILTER (
      WHERE source.contact_id = '6cc-corrected'
    ))[1]
  INTO STRICT expected_ids, corrected_id
  FROM app_private.deidentified_location_anomaly_ids AS mapping
  JOIN app_data.contact_location_provenance AS source
    ON source.source_id = mapping.source_id
  JOIN app_data.contacts AS contact
    ON contact.contact_id = source.contact_id
   AND contact.current_revision = source.revision_number
  WHERE source.contact_id IN (
    '6cc-pending', '6cc-legacy', '6cc-corrected'
  );

  SELECT array_agg(
    (item.value->>'anomaly_id')::uuid ORDER BY item.ordinality
  )
  INTO STRICT returned_ids
  FROM jsonb_array_elements(directory_document->'anomalies')
    WITH ORDINALITY AS item(value, ordinality);

  IF jsonb_array_length(directory_document->'anomalies') <> 3
    OR returned_ids IS DISTINCT FROM expected_ids
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(directory_document->'anomalies') AS item(value)
      WHERE item.value->>'reason_code' = 'pending_resolution'
        AND item.value->>'evidence_kind' = 'pending_coordinates'
    ) <> 2
    OR (
      SELECT count(*)
      FROM jsonb_array_elements(directory_document->'anomalies') AS item(value)
      WHERE item.value->>'reason_code' = 'legacy_incomplete'
        AND item.value->>'evidence_kind' = 'legacy_incomplete'
        AND item.value->>'has_usable_coordinates' = 'false'
    ) <> 1
    OR NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(directory_document->'anomalies') AS item(value)
      WHERE (item.value->>'anomaly_id')::uuid = corrected_id
        AND item.value->>'reason_code' = 'pending_resolution'
    )
  THEN
    RAISE EXCEPTION
      '6CC ordinary directory did not expose pending, legacy and corrected anomalies: %',
      directory_document;
  END IF;
END
$fixture_6cc_directory_anomaly_kinds$;

CREATE TEMP TABLE fixture_6cc_detail_ids ON COMMIT DROP AS
SELECT
  (array_agg(anomaly_id ORDER BY anomaly_id)
    FILTER (WHERE contact_id = '6cc-pending'))[1] AS pending_id,
  (array_agg(anomaly_id ORDER BY anomaly_id)
    FILTER (WHERE contact_id = '6cc-legacy'))[1] AS legacy_id,
  (array_agg(anomaly_id ORDER BY anomaly_id)
    FILTER (
      WHERE contact_id = '6cc-corrected' AND revision_number = 2
    ))[1] AS corrected_id,
  (array_agg(anomaly_id ORDER BY anomaly_id)
    FILTER (WHERE contact_id = '6cc-old-revision'))[1] AS old_revision_id,
  (array_agg(anomaly_id ORDER BY anomaly_id)
    FILTER (WHERE contact_id = '6cc-voided'))[1] AS voided_id,
  (array_agg(anomaly_id ORDER BY anomaly_id)
    FILTER (WHERE contact_id = '6cc-cross-project'))[1] AS cross_project_id
FROM fixture_6cc_anomalies;

INSERT INTO fixture_6cc_reads (read_name, document)
SELECT
  detail_row.read_name,
  app_private.read_authorized_deidentified_location_anomaly_v1(
    '6cc10000-0000-4000-8000-000000000001'::uuid,
    '6cc30000-0000-4000-8000-000000000001'::uuid,
    detail_row.anomaly_id
  )
FROM fixture_6cc_detail_ids AS ids
CROSS JOIN LATERAL (
  VALUES
    ('pending_detail'::text, ids.pending_id),
    ('pending_detail_repeat'::text, ids.pending_id),
    ('legacy_detail'::text, ids.legacy_id),
    ('corrected_detail'::text, ids.corrected_id),
    ('old_revision_detail'::text, ids.old_revision_id),
    ('voided_detail'::text, ids.voided_id),
    ('cross_project_detail'::text, ids.cross_project_id),
    (
      'unknown_detail'::text,
      '00000000-0000-4000-8000-000000000999'::uuid
    )
) AS detail_row(read_name, anomaly_id);

DO $fixture_6cc_detail_contract$
DECLARE
  pending_detail jsonb;
  pending_repeat jsonb;
  legacy_detail jsonb;
  corrected_detail jsonb;
  detail_item jsonb;
  detail_item_count integer;
  expected_keys text[] := ARRAY[
    'anomaly_id',
    'coordinates',
    'evidence_kind',
    'has_usable_coordinates',
    'location_kind',
    'occurred_at_utc',
    'reason_code',
    'status'
  ];
BEGIN
  SELECT document INTO STRICT pending_detail
  FROM fixture_6cc_reads WHERE read_name = 'pending_detail';
  SELECT document INTO STRICT pending_repeat
  FROM fixture_6cc_reads WHERE read_name = 'pending_detail_repeat';
  SELECT document INTO STRICT legacy_detail
  FROM fixture_6cc_reads WHERE read_name = 'legacy_detail';
  SELECT document INTO STRICT corrected_detail
  FROM fixture_6cc_reads WHERE read_name = 'corrected_detail';

  IF pending_detail->>'access_contract_id'
      IS DISTINCT FROM
        'authorized_deidentified_location_anomaly_detail_v1'
    OR pending_detail->>'project_id'
      IS DISTINCT FROM '6cc30000-0000-4000-8000-000000000001'
    OR pending_detail->>'result_status' IS DISTINCT FROM 'completed'
    OR pending_detail->'anomaly' IS NULL
    OR pending_detail->>'access_event_id' IS NULL
    OR pending_repeat->>'access_event_id' IS NULL
    OR pending_detail->>'access_event_id'
      = pending_repeat->>'access_event_id'
    OR pending_detail->'anomaly' <> pending_repeat->'anomaly'
    OR (
      SELECT count(*) FROM jsonb_object_keys(pending_detail)
    ) <> 5
    OR NOT (pending_detail ?& ARRAY[
      'access_contract_id',
      'access_event_id',
      'anomaly',
      'project_id',
      'result_status'
    ])
    OR pending_detail ?| ARRAY[
      'latitude',
      'longitude',
      'accuracy_meters',
      'coordinates',
      'contact_id',
      'revision_number',
      'source_id',
      'app_user_id'
    ]
  THEN
    RAISE EXCEPTION '6CC pending detail contract or repeat is invalid: % / %',
      pending_detail,
      pending_repeat;
  END IF;

  detail_item = corrected_detail->'anomaly';
  IF corrected_detail->>'access_contract_id'
      IS DISTINCT FROM
        'authorized_deidentified_location_anomaly_detail_v1'
    OR corrected_detail->>'project_id'
      IS DISTINCT FROM '6cc30000-0000-4000-8000-000000000001'
    OR corrected_detail->>'result_status' IS DISTINCT FROM 'completed'
    OR (
      SELECT count(*) FROM jsonb_object_keys(corrected_detail)
    ) <> 5
    OR NOT (corrected_detail ?& ARRAY[
      'access_contract_id',
      'access_event_id',
      'anomaly',
      'project_id',
      'result_status'
    ])
    OR (
      SELECT count(*) FROM jsonb_object_keys(detail_item)
    ) <> 8
    OR NOT (detail_item ?& expected_keys)
    OR detail_item->>'reason_code' IS DISTINCT FROM 'pending_resolution'
    OR detail_item->>'evidence_kind'
      IS DISTINCT FROM 'pending_coordinates'
    OR detail_item->'coordinates' <> jsonb_build_object(
      'latitude', 41.884400,
      'longitude', -87.627700,
      'accuracy_meters', 18.0
    )
  THEN
    RAISE EXCEPTION '6CC corrected current detail is invalid: %',
      corrected_detail;
  END IF;

  detail_item = pending_detail->'anomaly';
  IF (
      SELECT count(*) FROM jsonb_object_keys(detail_item)
    ) <> 8
    OR NOT (detail_item ?& expected_keys)
    OR detail_item ?| ARRAY[
      'contact_id',
      'revision_number',
      'source_id',
      'project_id',
      'app_user_id',
      'region_tree_version',
      'smallest_region_id'
    ]
    OR detail_item->>'reason_code' IS DISTINCT FROM 'pending_resolution'
    OR detail_item->>'location_kind'
      IS DISTINCT FROM 'pending_resolution'
    OR detail_item->>'evidence_kind'
      IS DISTINCT FROM 'pending_coordinates'
    OR detail_item->>'has_usable_coordinates' IS DISTINCT FROM 'true'
    OR detail_item->'coordinates' <> jsonb_build_object(
      'latitude', 41.881832,
      'longitude', -87.623177,
      'accuracy_meters', 12.5
    )
  THEN
    RAISE EXCEPTION '6CC pending detail exposed the wrong shape: %', detail_item;
  END IF;

  detail_item = legacy_detail->'anomaly';
  IF legacy_detail->>'result_status' IS DISTINCT FROM 'completed'
    OR (
      SELECT count(*) FROM jsonb_object_keys(detail_item)
    ) <> 8
    OR NOT (detail_item ?& expected_keys)
    OR detail_item->>'reason_code' IS DISTINCT FROM 'legacy_incomplete'
    OR detail_item->>'location_kind' IS DISTINCT FROM 'unknown'
    OR detail_item->>'evidence_kind'
      IS DISTINCT FROM 'legacy_incomplete'
    OR detail_item->>'has_usable_coordinates' IS DISTINCT FROM 'false'
    OR detail_item->'coordinates' <> 'null'::jsonb
  THEN
    RAISE EXCEPTION '6CC legacy detail is invalid: %', legacy_detail;
  END IF;

  SELECT count(*) INTO detail_item_count
  FROM fixture_6cc_reads
  WHERE read_name LIKE '%detail%'
    AND (
      (
        SELECT count(*) FROM jsonb_object_keys(document)
      ) <> 5
      OR NOT (document ?& ARRAY[
        'access_contract_id',
        'access_event_id',
        'anomaly',
        'project_id',
        'result_status'
      ])
    );
  IF detail_item_count <> 0 THEN
    RAISE EXCEPTION '6CC detail root exposed extra or missing fields';
  END IF;

  SELECT count(*) INTO detail_item_count
  FROM fixture_6cc_reads
  WHERE read_name IN (
    'old_revision_detail',
    'voided_detail',
    'cross_project_detail',
    'unknown_detail'
  )
    AND (
      document->>'result_status' IS DISTINCT FROM 'not_found'
      OR document->'anomaly' <> 'null'::jsonb
    );
  IF detail_item_count <> 0 THEN
    RAISE EXCEPTION
      '6CC stale, voided, cross-project or unknown detail escaped not_found';
  END IF;

  SELECT count(*) INTO detail_item_count
  FROM fixture_6cc_reads
  WHERE read_name LIKE '%detail%'
    AND (
      document->'anomaly' ?| ARRAY[
        'contact_id',
        'revision_number',
        'source_id',
        'app_user_id',
        'project_membership_id'
      ]
    );
  IF detail_item_count <> 0 THEN
    RAISE EXCEPTION '6CC detail exposed identity or source identifiers';
  END IF;
END
$fixture_6cc_detail_contract$;

DO $fixture_6cc_audit_contract$
DECLARE
  audit_count integer;
  directory_audit_count integer;
  detail_audit_count integer;
  audit_key text;
  audit_event_id uuid;
  anomaly_id_value uuid;
  error_code text;
BEGIN
  SELECT count(*) INTO audit_count
  FROM app_private.deidentified_location_anomaly_access_events
  WHERE requested_by_app_user_id =
    '6cc10000-0000-4000-8000-000000000001'::uuid
    AND project_id = '6cc30000-0000-4000-8000-000000000001'::uuid;
  SELECT count(*) INTO directory_audit_count
  FROM app_private.deidentified_location_anomaly_access_events
  WHERE requested_by_app_user_id =
    '6cc10000-0000-4000-8000-000000000001'::uuid
    AND project_id = '6cc30000-0000-4000-8000-000000000001'::uuid
    AND access_kind = 'directory';
  SELECT count(*) INTO detail_audit_count
  FROM app_private.deidentified_location_anomaly_access_events
  WHERE requested_by_app_user_id =
    '6cc10000-0000-4000-8000-000000000001'::uuid
    AND project_id = '6cc30000-0000-4000-8000-000000000001'::uuid
    AND access_kind = 'detail';

  IF audit_count <> 11
    OR directory_audit_count <> 3
    OR detail_audit_count <> 8
  THEN
    RAISE EXCEPTION
      '6CC audit count is wrong: total %, directory %, detail %',
      audit_count,
      directory_audit_count,
      detail_audit_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.deidentified_location_anomaly_access_events AS event_row
    WHERE event_row.requested_by_app_user_id =
        '6cc10000-0000-4000-8000-000000000001'::uuid
      AND event_row.project_id =
        '6cc30000-0000-4000-8000-000000000001'::uuid
      AND (
        event_row.capability_id <> 'view_deidentified_anomalies'
        OR event_row.authorization_reference_at_utc
          <> event_row.accessed_at_utc
        OR to_jsonb(event_row) ?| ARRAY[
          'anomaly_id',
          'source_id',
          'contact_id',
          'revision_number',
          'latitude',
          'longitude',
          'coordinates',
          'pii',
          'protected_report'
        ]
      )
  ) THEN
    RAISE EXCEPTION '6CC audit is not value-free or has mismatched authorization';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute
    WHERE attrelid =
      'app_private.deidentified_location_anomaly_access_events'::regclass
      AND attnum > 0
      AND NOT attisdropped
      AND attname IN (
        'anomaly_id',
        'source_id',
        'contact_id',
        'revision_number',
        'latitude',
        'longitude',
        'coordinates',
        'pii',
        'protected_report'
      )
  ) THEN
    RAISE EXCEPTION '6CC audit table has a forbidden value-bearing column';
  END IF;

  SELECT access_event_id INTO STRICT audit_event_id
  FROM app_private.deidentified_location_anomaly_access_events
  WHERE requested_by_app_user_id =
    '6cc10000-0000-4000-8000-000000000001'::uuid
  ORDER BY accessed_at_utc, access_event_id
  LIMIT 1;

  SELECT anomaly_id INTO STRICT anomaly_id_value
  FROM fixture_6cc_anomalies
  WHERE contact_id = '6cc-pending';

  BEGIN
    UPDATE app_private.deidentified_location_anomaly_ids
    SET mapped_at_utc = mapped_at_utc + interval '1 second'
    WHERE anomaly_id = anomaly_id_value;
    RAISE EXCEPTION '6CC opaque anomaly mapping update unexpectedly succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '55000' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    DELETE FROM app_private.deidentified_location_anomaly_ids
    WHERE anomaly_id = anomaly_id_value;
    RAISE EXCEPTION '6CC opaque anomaly mapping delete unexpectedly succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '55000' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    UPDATE app_private.deidentified_location_anomaly_access_events
    SET project_id = '6cc30000-0000-4000-8000-000000000002'::uuid
    WHERE access_event_id = audit_event_id;
    RAISE EXCEPTION '6CC audit update unexpectedly succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '55000' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    DELETE FROM app_private.deidentified_location_anomaly_access_events
    WHERE access_event_id = audit_event_id;
    RAISE EXCEPTION '6CC audit delete unexpectedly succeeded';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '55000' THEN
      RAISE;
    END IF;
  END;

  SELECT key_name INTO audit_key
  FROM jsonb_object_keys(
    (
      SELECT to_jsonb(event_row)
      FROM app_private.deidentified_location_anomaly_access_events AS event_row
      WHERE event_row.access_event_id = audit_event_id
    )
  ) AS key_row(key_name)
  WHERE key_name IN (
    'anomaly_id',
    'source_id',
    'contact_id',
    'revision_number',
    'latitude',
    'longitude',
    'coordinates',
    'pii'
  )
  LIMIT 1;
  IF audit_key IS NOT NULL THEN
    RAISE EXCEPTION '6CC audit contained forbidden key %', audit_key;
  END IF;
END
$fixture_6cc_audit_contract$;

DO $fixture_6cc_authorization$
DECLARE
  before_count integer;
  after_count integer;
  error_code text;
BEGIN
  SELECT count(*) INTO before_count
  FROM app_private.deidentified_location_anomaly_access_events;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000002'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6CC generic analytics capability implied anomaly access';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000004'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6CC inactive user retained anomaly access';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000001'::uuid,
      '6cc30000-0000-4000-8000-000000000002'::uuid
    );
    RAISE EXCEPTION '6CC project membership was incorrectly inferred';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  -- Establish a complete historical hierarchy, then make the project
  -- inactive. The read must fail at authorization and must not append audit.
  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = '6cc30000-0000-4000-8000-000000000003'::uuid;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000001'::uuid,
      '6cc30000-0000-4000-8000-000000000003'::uuid
    );
    RAISE EXCEPTION '6CC inactive project retained anomaly access';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  -- Close one capability and project membership while its organization
  -- membership remains active. Child-to-parent closure preserves the valid
  -- historical range while proving the expired project hierarchy fails closed.
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = base.fixture_now_utc - interval '6 seconds'
  FROM fixture_6cc_clock AS base
  WHERE capability_grant_id =
    '6cc70000-0000-4000-8000-000000000006'::uuid;
  UPDATE app_data.project_memberships
  SET inactive_from_utc = base.fixture_now_utc - interval '5 seconds'
  FROM fixture_6cc_clock AS base
  WHERE project_membership_id =
    '6cc60000-0000-4000-8000-000000000006'::uuid;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000005'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6CC expired project membership retained anomaly access';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  -- Close the full hierarchy for a separate actor. The organization membership
  -- is the outer expired boundary; descendant ranges stay contained and the
  -- read fails without deleting the historical authorization rows.
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = base.fixture_now_utc - interval '4 seconds'
  FROM fixture_6cc_clock AS base
  WHERE capability_grant_id =
    '6cc70000-0000-4000-8000-000000000003'::uuid;
  UPDATE app_data.project_memberships
  SET inactive_from_utc = base.fixture_now_utc - interval '3 seconds'
  FROM fixture_6cc_clock AS base
  WHERE project_membership_id =
    '6cc60000-0000-4000-8000-000000000003'::uuid;
  UPDATE app_data.organization_memberships
  SET inactive_from_utc = base.fixture_now_utc - interval '2 seconds'
  FROM fixture_6cc_clock AS base
  WHERE organization_membership_id =
    '6cc50000-0000-4000-8000-000000000003'::uuid;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000003'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION
      '6CC expired organization membership retained anomaly access';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = base.fixture_now_utc - interval '1 second'
  FROM fixture_6cc_clock AS base
  WHERE capability_grant_id =
    '6cc70000-0000-4000-8000-000000000001'::uuid;

  BEGIN
    PERFORM app_private.list_authorized_deidentified_location_anomalies_v1(
      '6cc10000-0000-4000-8000-000000000001'::uuid,
      '6cc30000-0000-4000-8000-000000000001'::uuid
    );
    RAISE EXCEPTION '6CC revoked capability retained anomaly access';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code = RETURNED_SQLSTATE;
    IF error_code <> '42501' THEN
      RAISE;
    END IF;
  END;

  SELECT count(*) INTO after_count
  FROM app_private.deidentified_location_anomaly_access_events;
  IF after_count <> before_count THEN
    RAISE EXCEPTION '6CC denied requests wrote audit rows';
  END IF;
END
$fixture_6cc_authorization$;

ROLLBACK;
