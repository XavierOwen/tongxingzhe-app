-- synthetic fixture：证明 6S 来源按 revision 追加、形状严格、不可改写，且
-- 不把 current projection 当成历史来源。
BEGIN;

-- 两个已发布版本共用同一 synthetic boundary。v2 成为 current 后，v1 的
-- provenance 仍必须保留原树版本和内容指纹。
INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES
  ('provenance-v1', 'draft', false),
  ('provenance-v2', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  ('provenance-v1-country', 'provenance-v1', NULL, 'Provenance Country', 'country'),
  ('provenance-v1-city', 'provenance-v1', 'provenance-v1-country', 'Provenance City', 'city'),
  ('provenance-v1-venue', 'provenance-v1', 'provenance-v1-city', 'Provenance Venue', 'venue'),
  ('provenance-v2-country', 'provenance-v2', NULL, 'Provenance Country', 'country'),
  ('provenance-v2-city', 'provenance-v2', 'provenance-v2-country', 'Provenance City', 'city'),
  ('provenance-v2-venue', 'provenance-v2', 'provenance-v2-city', 'Provenance Venue', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES
  (
    'provenance-v1-boundary', 'provenance-v1-venue', 'provenance-v1',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  ),
  (
    'provenance-v2-boundary', 'provenance-v2-venue', 'provenance-v2',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  );

SELECT app_private.publish_canonical_region_tree_v1('provenance-v1', true);
SELECT app_private.publish_canonical_region_tree_v1('provenance-v2', true);

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE provenance_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-location-provenance.supabase.co/auth/v1',
  'synthetic-location-provenance-owner'
);

RESET ROLE;

CREATE TEMP TABLE provenance_release_fingerprints AS
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'provenance-v1'
  ) AS v1_fingerprint,
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'provenance-v2'
  ) AS v2_fingerprint
FROM app_data.canonical_region_tree_releases
WHERE tree_version IN ('provenance-v1', 'provenance-v2');

-- The idempotency probe deliberately runs as the client-facing runtime role.
-- Grant only this synthetic fingerprint input; the runtime role still has no
-- access to the provenance table or canonical release tables.
GRANT SELECT ON provenance_release_fingerprints TO tongxingzhe_runtime;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  channel, location_kind, place_name, smallest_region_id,
  region_tree_version, latitude, longitude, location_accuracy_meters,
  reach_count, interest_level
)
SELECT
  contact_id,
  context.app_user_id,
  context.workspace_id,
  context.project_id,
  context.questionnaire_version_id,
  '2030-02-01T12:00:00Z',
  'America/Chicago',
  location_row.channel,
  location_row.location_kind,
  location_row.place_name,
  location_row.smallest_region_id,
  location_row.region_tree_version,
  location_row.latitude,
  location_row.longitude,
  location_row.location_accuracy_meters,
  1,
  2
FROM provenance_owner_context AS context
CROSS JOIN (
  VALUES
    (
      'provenance-coordinate-contact', 'face_to_face', 'resolved',
      'Provenance Venue', 'provenance-v1-venue', 'provenance-v1',
      NULL::double precision, NULL::double precision, NULL::double precision
    ),
    (
      'provenance-region-only-contact', 'face_to_face', 'resolved',
      'Provenance Venue', 'provenance-v1-venue', 'provenance-v1',
      NULL::double precision, NULL::double precision, NULL::double precision
    ),
    (
      'provenance-pending-contact', 'face_to_face', 'pending_resolution',
      NULL, NULL, NULL,
      41.7897::double precision, -87.5997::double precision,
      8.5::double precision
    ),
    (
      'provenance-na-contact', 'voice_call', 'not_applicable',
      NULL, NULL, NULL,
      NULL::double precision, NULL::double precision, NULL::double precision
    ),
    (
      'provenance-legacy-incomplete-contact', 'voice_call', 'not_applicable',
      NULL, NULL, NULL,
      NULL::double precision, NULL::double precision, NULL::double precision
    )
) AS location_row(
  contact_id, channel, location_kind, place_name, smallest_region_id,
  region_tree_version, latitude, longitude, location_accuracy_meters
);

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id,
  snapshot
)
SELECT
  contact_row.contact_id,
  1,
  'submitted',
  context.app_user_id,
  CASE contact_row.contact_id
    WHEN 'provenance-coordinate-contact' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Provenance Venue',
        'smallestRegionId', 'provenance-v1-venue',
        'regionTreeVersion', 'provenance-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.7897,
        'longitude', -87.5997,
        'accuracyMeters', 8.5,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprints.v1_fingerprint
      )
    )
    WHEN 'provenance-region-only-contact' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Provenance Venue',
        'smallestRegionId', 'provenance-v1-venue',
        'regionTreeVersion', 'provenance-v1'
      )
    )
    WHEN 'provenance-pending-contact' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'pending_resolution',
        'latitude', 41.7897,
        'longitude', -87.5997,
        'accuracyMeters', 8.5
      )
    )
    WHEN 'provenance-legacy-incomplete-contact' THEN '{}'::jsonb
    ELSE jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object('kind', 'not_applicable')
    )
  END
FROM app_data.contacts AS contact_row
JOIN provenance_owner_context AS context
  ON context.project_id = contact_row.project_id
CROSS JOIN provenance_release_fingerprints AS fingerprints
WHERE contact_row.contact_id IN (
  'provenance-coordinate-contact',
  'provenance-region-only-contact',
  'provenance-pending-contact',
  'provenance-na-contact',
  'provenance-legacy-incomplete-contact'
);

DO $shape_check$
DECLARE
  v1_fingerprint text;
  coordinate_source record;
  region_only_source record;
  pending_source record;
  na_source record;
BEGIN
  SELECT fingerprints.v1_fingerprint
    INTO STRICT v1_fingerprint
  FROM provenance_release_fingerprints AS fingerprints;

  IF v1_fingerprint IS NULL OR v1_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'synthetic v1 release has no valid content fingerprint';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.contact_location_provenance
    WHERE contact_id LIKE 'provenance-%-contact'
  ) <> 5 THEN
    RAISE EXCEPTION 'each synthetic revision must have one provenance row (actual=%)', (
      SELECT count(*)
      FROM app_data.contact_location_provenance
      WHERE contact_id LIKE 'provenance-%-contact'
    );
  END IF;

  SELECT * INTO STRICT coordinate_source
  FROM app_data.contact_location_provenance
  WHERE contact_id = 'provenance-coordinate-contact'
    AND revision_number = 1;
  IF coordinate_source.location_kind <> 'resolved'
    OR coordinate_source.evidence_kind <> 'resolved_from_coordinates'
    OR coordinate_source.latitude <> 41.7897
    OR coordinate_source.longitude <> -87.5997
    OR coordinate_source.accuracy_meters <> 8.5
    OR coordinate_source.smallest_region_id <> 'provenance-v1-venue'
    OR coordinate_source.region_tree_version <> 'provenance-v1'
    OR coordinate_source.region_tree_content_fingerprint <> v1_fingerprint
    OR coordinate_source.resolver_contract_version
      <> 'canonical-region-resolution:v1'
    OR coordinate_source.recorded_at_utc IS NULL
  THEN
    RAISE EXCEPTION 'captured-coordinate provenance shape is wrong';
  END IF;

  SELECT * INTO STRICT region_only_source
  FROM app_data.contact_location_provenance
  WHERE contact_id = 'provenance-region-only-contact'
    AND revision_number = 1;
  IF region_only_source.location_kind <> 'resolved'
    OR region_only_source.evidence_kind <> 'resolved_region_only'
    OR region_only_source.latitude IS NOT NULL
    OR region_only_source.longitude IS NOT NULL
    OR region_only_source.accuracy_meters IS NOT NULL
    OR region_only_source.region_tree_content_fingerprint <> v1_fingerprint
  THEN
    RAISE EXCEPTION 'region-only provenance shape is wrong';
  END IF;

  SELECT * INTO STRICT pending_source
  FROM app_data.contact_location_provenance
  WHERE contact_id = 'provenance-pending-contact'
    AND revision_number = 1;
  IF pending_source.location_kind <> 'pending_resolution'
    OR pending_source.evidence_kind <> 'pending_coordinates'
    OR pending_source.latitude <> 41.7897
    OR pending_source.longitude <> -87.5997
    OR pending_source.accuracy_meters <> 8.5
    OR pending_source.smallest_region_id IS NOT NULL
    OR pending_source.region_tree_version IS NOT NULL
    OR pending_source.region_tree_content_fingerprint IS NOT NULL
  THEN
    RAISE EXCEPTION 'pending provenance shape is wrong';
  END IF;

  SELECT * INTO STRICT na_source
  FROM app_data.contact_location_provenance
  WHERE contact_id = 'provenance-na-contact'
    AND revision_number = 1;
  IF na_source.location_kind <> 'not_applicable'
    OR na_source.evidence_kind <> 'not_applicable'
    OR na_source.place_name IS NOT NULL
    OR na_source.latitude IS NOT NULL
    OR na_source.longitude IS NOT NULL
    OR na_source.accuracy_meters IS NOT NULL
    OR na_source.smallest_region_id IS NOT NULL
    OR na_source.region_tree_version IS NOT NULL
    OR na_source.region_tree_content_fingerprint IS NOT NULL
  THEN
    RAISE EXCEPTION 'not-applicable provenance shape is wrong';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.contact_location_provenance
    WHERE contact_id = 'provenance-legacy-incomplete-contact'
      AND revision_number = 1
      AND location_kind = 'unknown'
      AND evidence_kind = 'legacy_incomplete'
      AND place_name IS NULL
      AND latitude IS NULL
      AND longitude IS NULL
      AND smallest_region_id IS NULL
      AND region_tree_version IS NULL
  ) THEN
    RAISE EXCEPTION 'missing legacy location was not marked incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.contact_region_assignments
    WHERE contact_id IN (
      'provenance-coordinate-contact',
      'provenance-region-only-contact'
    )
  ) <> 2 OR EXISTS (
    SELECT 1
    FROM app_data.contact_region_assignments
    WHERE contact_id IN (
      'provenance-pending-contact', 'provenance-na-contact'
    )
  ) THEN
    RAISE EXCEPTION 'current assignment is not a projection of resolved rows';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.contact_location_provenance AS provenance
    LEFT JOIN app_data.canonical_region_tree_releases AS release_row
      ON release_row.tree_version = provenance.region_tree_version
    WHERE provenance.contact_id LIKE 'provenance-%-contact'
      AND provenance.location_kind = 'resolved'
      AND (
        release_row.lifecycle_state <> 'published'
        OR release_row.content_fingerprint
          IS DISTINCT FROM provenance.region_tree_content_fingerprint
      )
  ) THEN
    RAISE EXCEPTION 'resolved provenance is not bound to published fingerprint';
  END IF;

  -- Current v2 selection must not mutate the original v1 evidence.
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_tree_releases
    WHERE tree_version = 'provenance-v2' AND lifecycle_state = 'published'
      AND is_current
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.contact_location_provenance
    WHERE contact_id = 'provenance-region-only-contact'
      AND region_tree_version = 'provenance-v1'
      AND region_tree_content_fingerprint = v1_fingerprint
  ) THEN
    RAISE EXCEPTION 'current tree publication rewrote original provenance';
  END IF;
END
$shape_check$;

-- A resolved revision may be corrected to pending. The old resolved source is
-- immutable, while the current assignment is cleared by the existing 0005
-- projection trigger.
UPDATE app_data.contacts
SET location_kind = 'pending_resolution',
    place_name = NULL,
    smallest_region_id = NULL,
    region_tree_version = NULL,
    latitude = 41.7897,
    longitude = -87.5997,
    location_accuracy_meters = 8.5,
    current_revision = 2
WHERE contact_id = 'provenance-region-only-contact';

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id,
  reason, snapshot
)
SELECT
  'provenance-region-only-contact',
  2,
  'corrected',
  app_user_id,
  'Synthetic pending correction',
  jsonb_build_object(
    'contactId', 'provenance-region-only-contact',
    'location', jsonb_build_object(
      'kind', 'pending_resolution',
      'latitude', 41.7897,
      'longitude', -87.5997,
      'accuracyMeters', 8.5
    )
  )
FROM provenance_owner_context;

DO $revision_history_check$
DECLARE
  v1_count integer;
  v2_count integer;
BEGIN
  SELECT count(*) INTO v1_count
  FROM app_data.contact_location_provenance
  WHERE contact_id = 'provenance-region-only-contact'
    AND revision_number = 1;
  SELECT count(*) INTO v2_count
  FROM app_data.contact_location_provenance
  WHERE contact_id = 'provenance-region-only-contact'
    AND revision_number = 2
    AND evidence_kind = 'pending_coordinates'
    AND location_kind = 'pending_resolution'
    AND latitude = 41.7897
    AND longitude = -87.5997
    AND region_tree_version IS NULL;
  IF v1_count <> 1 OR v2_count <> 1 THEN
    RAISE EXCEPTION 'pending correction did not append independent source rows';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM app_data.contact_region_assignments
    WHERE contact_id = 'provenance-region-only-contact'
  ) OR EXISTS (
    SELECT 1
    FROM app_data.contacts
    WHERE contact_id = 'provenance-region-only-contact'
      AND region_tree_version IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'pending correction retained a stale current assignment';
  END IF;
END
$revision_history_check$;

-- Source rows cannot be edited or removed, including after an application-private
-- setting that a naive trigger might use as an internal bypass.
DO $append_only_check$
DECLARE
  failed boolean;
BEGIN
  failed := false;
  BEGIN
    PERFORM set_config(
      'app_private.contact_location_provenance_write', 'on', true
    );
    UPDATE app_data.contact_location_provenance
    SET place_name = 'tampered'
    WHERE contact_id = 'provenance-coordinate-contact'
      AND revision_number = 1;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'provenance UPDATE bypassed append-only guard';
  END IF;

  failed := false;
  BEGIN
    DELETE FROM app_data.contact_location_provenance
    WHERE contact_id = 'provenance-coordinate-contact'
      AND revision_number = 1;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'provenance DELETE bypassed append-only guard';
  END IF;
END
$append_only_check$;

-- Invalid legacy/new shapes fail closed and leave no source row.
DO $invalid_shape_check$
DECLARE
  failed boolean;
BEGIN
  failed := false;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, reach_count, interest_level
    )
    SELECT
      'provenance-invalid-na-face-to-face', app_user_id, workspace_id,
      project_id, questionnaire_version_id, '2030-02-01T12:00:00Z',
      'America/Chicago', 'face_to_face', 'not_applicable', 1, 2
    FROM provenance_owner_context;
    RAISE EXCEPTION 'face-to-face N/A contact was accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'invalid face-to-face N/A shape did not fail';
  END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, place_name, smallest_region_id,
      region_tree_version, reach_count, interest_level
    )
    SELECT
      'provenance-invalid-tree', app_user_id, workspace_id,
      project_id, questionnaire_version_id, '2030-02-01T12:00:00Z',
      'America/Chicago', 'face_to_face', 'resolved', 'Unknown',
      'does-not-exist', 'does-not-exist', 1, 2
    FROM provenance_owner_context;
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    )
    SELECT
      'provenance-invalid-tree', 1, 'submitted', app_user_id,
      jsonb_build_object(
        'location', jsonb_build_object(
          'kind', 'resolved',
          'placeName', 'Unknown',
          'smallestRegionId', 'does-not-exist',
          'regionTreeVersion', 'does-not-exist'
        )
      )
    FROM provenance_owner_context;
    RAISE EXCEPTION 'resolved revision accepted an unknown tree';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'unknown tree shape did not fail';
  END IF;

  failed := false;
  BEGIN
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, place_name, smallest_region_id,
      region_tree_version, reach_count, interest_level
    )
    SELECT
      'provenance-invalid-fingerprint', app_user_id, workspace_id,
      project_id, questionnaire_version_id, '2030-02-01T12:00:00Z',
      'America/Chicago', 'face_to_face', 'resolved', 'Provenance Venue',
      'provenance-v1-venue', 'provenance-v1', 1, 2
    FROM provenance_owner_context;
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    )
    SELECT
      'provenance-invalid-fingerprint', 1, 'submitted', app_user_id,
      jsonb_build_object(
        'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Provenance Venue',
        'smallestRegionId', 'provenance-v1-venue',
        'regionTreeVersion', 'provenance-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.7897,
        'longitude', -87.5997,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', repeat('0', 64)
      )
      )
    FROM provenance_owner_context;
    RAISE EXCEPTION 'mismatched tree fingerprint was accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'mismatched fingerprint did not fail';
  END IF;
END
$invalid_shape_check$;

-- Runtime can use the existing contact command seam, but cannot inspect or
-- mutate the source table. Replaying one command must not append a second row.
GRANT SELECT ON provenance_release_fingerprints TO tongxingzhe_runtime;
SET LOCAL ROLE tongxingzhe_runtime;
CREATE TEMP TABLE first_submit AS
SELECT *
FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM provenance_owner_context),
  'provenance-idempotent-command',
  1,
  'contact.submit.v1',
  'synthetic-provenance-device',
  'provenance-idempotent-contact',
  0,
  jsonb_build_object(
    'contactId', 'provenance-idempotent-contact',
    'workspaceId', (SELECT workspace_id FROM provenance_owner_context),
    'projectId', (SELECT project_id FROM provenance_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM provenance_owner_context),
    'occurredAtUtc', '2030-02-01T12:00:00Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'face_to_face',
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', 'Provenance Venue',
      'smallestRegionId', 'provenance-v1-venue',
      'regionTreeVersion', 'provenance-v1'
    ),
    'locationSource', jsonb_build_object(
      'kind', 'captured_coordinates',
      'latitude', 41.7897,
      'longitude', -87.5997,
      'accuracyMeters', 8.5,
      'resolverContractVersion', 'canonical-region-resolution:v1',
      'regionTreeContentFingerprint',
        (SELECT v1_fingerprint FROM provenance_release_fingerprints)
    ),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', '[]'::jsonb,
    'targetLinks', '[]'::jsonb
  )
);

CREATE TEMP TABLE duplicate_submit AS
SELECT *
FROM app_data.apply_contact_submit_v3(
  (SELECT app_user_id FROM provenance_owner_context),
  'provenance-idempotent-command',
  1,
  'contact.submit.v1',
  'synthetic-provenance-device',
  'provenance-idempotent-contact',
  0,
  jsonb_build_object(
    'contactId', 'provenance-idempotent-contact',
    'workspaceId', (SELECT workspace_id FROM provenance_owner_context),
    'projectId', (SELECT project_id FROM provenance_owner_context),
    'questionnaireVersionId',
      (SELECT questionnaire_version_id FROM provenance_owner_context),
    'occurredAtUtc', '2030-02-01T12:00:00Z',
    'occurredTimeZone', 'America/Chicago',
    'channel', 'face_to_face',
    'location', jsonb_build_object(
      'kind', 'resolved',
      'placeName', 'Provenance Venue',
      'smallestRegionId', 'provenance-v1-venue',
      'regionTreeVersion', 'provenance-v1'
    ),
    'reachCount', 1,
    'interestLevel', 2,
    'answers', '[]'::jsonb,
    'targetLinks', '[]'::jsonb
  )
);

DO $idempotency_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM first_submit WHERE result_code = 'accepted'
  ) OR NOT EXISTS (
    SELECT 1 FROM duplicate_submit WHERE result_code = 'duplicate'
  ) THEN
    RAISE EXCEPTION 'contact submit replay was not idempotent';
  END IF;
END
$idempotency_check$;

RESET ROLE;

SET LOCAL ROLE tongxingzhe_runtime;

DO $runtime_permission_check$
BEGIN
  BEGIN
    PERFORM 1 FROM app_data.contact_location_provenance;
    RAISE EXCEPTION 'runtime role read provenance table directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    INSERT INTO app_data.contact_location_provenance (
      source_id, contact_id, revision_number, revision_kind,
      location_kind, evidence_kind, recorded_at_utc
    ) VALUES (
      DEFAULT, 'provenance-coordinate-contact', 1, 'submitted',
      'resolved', 'resolved_region_only', clock_timestamp()
    );
    RAISE EXCEPTION 'runtime role inserted provenance directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END
$runtime_permission_check$;

RESET ROLE;

ROLLBACK;
