-- Synthetic fixture for the private management-region attribution resolver.
-- It exercises original evidence, explicit current-tree attribution, and the
-- fail-closed states without exposing any contact or coordinate in the result.
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE attribution_owner_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-region-attribution.supabase.co/auth/v1',
  'synthetic-region-attribution-owner'
);

RESET ROLE;

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES
  ('fixture-attribution-source-v1', 'draft', false),
  ('fixture-attribution-target-v1', 'draft', false),
  ('fixture-attribution-draft-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
) VALUES
  ('fixture-attribution-source-country', 'fixture-attribution-source-v1',
    NULL, 'Attribution Source Country', 'country'),
  ('fixture-attribution-source-city', 'fixture-attribution-source-v1',
    'fixture-attribution-source-country', 'Attribution Source City', 'city'),
  ('fixture-attribution-source-region', 'fixture-attribution-source-v1',
    'fixture-attribution-source-city', 'Attribution Source Region', 'venue'),
  ('fixture-attribution-source-region-2', 'fixture-attribution-source-v1',
    'fixture-attribution-source-city', 'Attribution Source Region 2', 'venue'),
  ('fixture-attribution-target-country', 'fixture-attribution-target-v1',
    NULL, 'Attribution Target Country', 'country'),
  ('fixture-attribution-target-city', 'fixture-attribution-target-v1',
    'fixture-attribution-target-country', 'Attribution Target City', 'city'),
  ('fixture-attribution-target-alt-city', 'fixture-attribution-target-v1',
    'fixture-attribution-target-country', 'Attribution Target Alt City', 'city'),
  ('fixture-attribution-target-unique', 'fixture-attribution-target-v1',
    'fixture-attribution-target-city', 'Attribution Target Unique', 'venue'),
  ('fixture-attribution-target-outer', 'fixture-attribution-target-v1',
    'fixture-attribution-target-city', 'Attribution Target Outer', 'venue'),
  ('fixture-attribution-target-inner', 'fixture-attribution-target-v1',
    'fixture-attribution-target-outer', 'Attribution Target Inner', 'venue'),
  ('fixture-attribution-target-cross', 'fixture-attribution-target-v1',
    'fixture-attribution-target-alt-city', 'Attribution Target Cross', 'venue'),
  ('fixture-attribution-target-sibling-a', 'fixture-attribution-target-v1',
    'fixture-attribution-target-city', 'Attribution Target Sibling A', 'venue'),
  ('fixture-attribution-target-sibling-b', 'fixture-attribution-target-v1',
    'fixture-attribution-target-city', 'Attribution Target Sibling B', 'venue'),
  ('fixture-attribution-draft-country', 'fixture-attribution-draft-v1',
    NULL, 'Attribution Draft Country', 'country'),
  ('fixture-attribution-draft-city', 'fixture-attribution-draft-v1',
    'fixture-attribution-draft-country', 'Attribution Draft City', 'city');

-- Target boundaries deliberately cover separate synthetic points:
-- unique, nested same-chain, cross-chain, same-depth siblings and zero match.
INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES
  (
    'fixture-attribution-source-boundary',
    'fixture-attribution-source-region',
    'fixture-attribution-source-v1',
    polygon '((-88.00,41.60),(-87.50,41.60),(-87.50,42.00),(-88.00,42.00))'
  ),
  (
    'fixture-attribution-target-unique-boundary',
    'fixture-attribution-target-unique',
    'fixture-attribution-target-v1',
    polygon '((-87.80,41.70),(-87.78,41.70),(-87.78,41.72),(-87.80,41.72))'
  ),
  (
    'fixture-attribution-target-outer-boundary',
    'fixture-attribution-target-outer',
    'fixture-attribution-target-v1',
    polygon '((-87.62,41.77),(-87.56,41.77),(-87.56,41.82),(-87.62,41.82))'
  ),
  (
    'fixture-attribution-target-inner-boundary',
    'fixture-attribution-target-inner',
    'fixture-attribution-target-v1',
    polygon '((-87.60,41.785),(-87.59,41.785),(-87.59,41.795),(-87.60,41.795))'
  ),
  (
    'fixture-attribution-target-cross-boundary',
    'fixture-attribution-target-cross',
    'fixture-attribution-target-v1',
    polygon '((-87.59,41.77),(-87.53,41.77),(-87.53,41.82),(-87.59,41.82))'
  ),
  (
    'fixture-attribution-target-sibling-a-boundary',
    'fixture-attribution-target-sibling-a',
    'fixture-attribution-target-v1',
    polygon '((-87.72,41.70),(-87.68,41.70),(-87.68,41.73),(-87.72,41.73))'
  ),
  (
    'fixture-attribution-target-sibling-b-boundary',
    'fixture-attribution-target-sibling-b',
    'fixture-attribution-target-v1',
    polygon '((-87.71,41.705),(-87.67,41.705),(-87.67,41.735),(-87.71,41.735))'
  );

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-attribution-source-v1', false
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-attribution-target-v1', false
);

CREATE TEMP TABLE attribution_release_fingerprints AS
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-attribution-source-v1'
  ) AS source_fingerprint,
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-attribution-target-v1'
  ) AS target_fingerprint
FROM app_data.canonical_region_tree_releases;

-- This mapping is the only permitted bridge for the region-only cross-version
-- case. The second source region intentionally has no mapping.
SELECT app_private.register_canonical_region_version_mapping_v1(
  '54a00000-0000-4000-8000-000000000001'::uuid,
  'fixture-attribution-source-v1',
  'fixture-attribution-source-region',
  fingerprints.source_fingerprint,
  'fixture-attribution-target-v1',
  'fixture-attribution-target-unique',
  fingerprints.target_fingerprint,
  repeat('a', 64)
)
FROM attribution_release_fingerprints AS fingerprints;

-- The trigger on contact_revisions is the only supported provenance writer.
-- Contacts are synthetic and the fixture never commits them.
INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  channel,
  location_kind,
  place_name,
  smallest_region_id,
  region_tree_version,
  latitude,
  longitude,
  location_accuracy_meters,
  reach_count,
  interest_level
)
SELECT
  location_row.contact_id,
  context.app_user_id,
  context.workspace_id,
  context.project_id,
  context.questionnaire_version_id,
  '2030-04-01T12:00:00Z',
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
FROM attribution_owner_context AS context
CROSS JOIN (
  VALUES
    ('attr-coordinate-unique', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-coordinate-nested', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-coordinate-cross', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-coordinate-sibling', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-coordinate-zero', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-region-only-same', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-region-only-mapped', 'face_to_face', 'resolved',
      'Attribution Source Region', 'fixture-attribution-source-region',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-region-only-missing', 'face_to_face', 'resolved',
      'Attribution Source Region 2', 'fixture-attribution-source-region-2',
      'fixture-attribution-source-v1', NULL::double precision,
      NULL::double precision, NULL::double precision),
    ('attr-pending', 'face_to_face', 'pending_resolution',
      NULL, NULL, NULL, 41.7897::double precision, -87.5997::double precision,
      8.5::double precision),
    ('attr-not-applicable', 'voice_call', 'not_applicable',
      NULL, NULL, NULL, NULL::double precision, NULL::double precision,
      NULL::double precision),
    ('attr-incomplete', 'voice_call', 'not_applicable',
      NULL, NULL, NULL, NULL::double precision, NULL::double precision,
      NULL::double precision)
) AS location_row(
  contact_id,
  channel,
  location_kind,
  place_name,
  smallest_region_id,
  region_tree_version,
  latitude,
  longitude,
  location_accuracy_meters
);

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revision_kind,
  revised_by_app_user_id,
  snapshot
)
SELECT
  contact_row.contact_id,
  1,
  'submitted',
  context.app_user_id,
  CASE contact_row.contact_id
    WHEN 'attr-coordinate-unique' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.71,
        'longitude', -87.79,
        'accuracyMeters', 5.0,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprints.source_fingerprint
      )
    )
    WHEN 'attr-coordinate-nested' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.79,
        'longitude', -87.595,
        'accuracyMeters', 5.0,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprints.source_fingerprint
      )
    )
    WHEN 'attr-coordinate-cross' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.79,
        'longitude', -87.565,
        'accuracyMeters', 5.0,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprints.source_fingerprint
      )
    )
    WHEN 'attr-coordinate-sibling' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 41.71,
        'longitude', -87.70,
        'accuracyMeters', 5.0,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprints.source_fingerprint
      )
    )
    WHEN 'attr-coordinate-zero' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      ),
      'locationSource', jsonb_build_object(
        'kind', 'captured_coordinates',
        'latitude', 40.0,
        'longitude', -80.0,
        'accuracyMeters', 5.0,
        'resolverContractVersion', 'canonical-region-resolution:v1',
        'regionTreeContentFingerprint', fingerprints.source_fingerprint
      )
    )
    WHEN 'attr-region-only-same' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      )
    )
    WHEN 'attr-region-only-mapped' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region',
        'smallestRegionId', 'fixture-attribution-source-region',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      )
    )
    WHEN 'attr-region-only-missing' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'resolved',
        'placeName', 'Attribution Source Region 2',
        'smallestRegionId', 'fixture-attribution-source-region-2',
        'regionTreeVersion', 'fixture-attribution-source-v1'
      )
    )
    WHEN 'attr-pending' THEN jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object(
        'kind', 'pending_resolution',
        'latitude', 41.7897,
        'longitude', -87.5997,
        'accuracyMeters', 8.5
      )
    )
    WHEN 'attr-incomplete' THEN '{}'::jsonb
    ELSE jsonb_build_object(
      'contactId', contact_row.contact_id,
      'location', jsonb_build_object('kind', 'not_applicable')
    )
  END
FROM app_data.contacts AS contact_row
JOIN attribution_owner_context AS context
  ON context.project_id = contact_row.project_id
CROSS JOIN attribution_release_fingerprints AS fingerprints
WHERE contact_row.contact_id LIKE 'attr-%';

CREATE TEMP TABLE attribution_sources AS
SELECT contact_id, source_id
FROM app_data.contact_location_provenance
WHERE contact_id LIKE 'attr-%';

DO $fixture$
DECLARE
  source_id_value uuid;
  source_fingerprint text;
  target_fingerprint text;
  result jsonb;
  expected record;
  key_name text;
  failed boolean;
BEGIN
  SELECT fingerprints.source_fingerprint, fingerprints.target_fingerprint
    INTO STRICT source_fingerprint, target_fingerprint
  FROM attribution_release_fingerprints AS fingerprints;

  IF source_fingerprint !~ '^[0-9a-f]{64}$'
    OR target_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'attribution fixture releases have invalid fingerprints';
  END IF;

  IF (SELECT count(*) FROM attribution_sources) <> 11 THEN
    RAISE EXCEPTION 'expected 11 attribution provenance rows, got %',
      (SELECT count(*) FROM attribution_sources);
  END IF;

  -- Every case below is intentionally checked through the public shape of the
  -- private contract. A result must never echo source/contact/revision data,
  -- names, coordinates or PII.
  FOR expected IN
    SELECT *
    FROM (VALUES
      ('attr-coordinate-unique', 'original', NULL::text, NULL::text,
        'attributed', 'original_exact_source',
        'fixture-attribution-source-region',
        'fixture-attribution-source-v1', source_fingerprint),
      ('attr-coordinate-unique', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'attributed', 'current_coordinate_match',
        'fixture-attribution-target-unique',
        'fixture-attribution-target-v1', target_fingerprint),
      ('attr-coordinate-nested', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'attributed', 'current_coordinate_match',
        'fixture-attribution-target-inner',
        'fixture-attribution-target-v1', target_fingerprint),
      ('attr-coordinate-cross', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'ambiguous', 'coordinate_ambiguous', NULL::text, NULL::text, NULL::text),
      ('attr-coordinate-sibling', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'ambiguous', 'coordinate_ambiguous', NULL::text, NULL::text, NULL::text),
      ('attr-coordinate-zero', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'unmapped', 'coordinate_no_match', NULL::text, NULL::text, NULL::text),
      ('attr-region-only-same', 'current',
        'fixture-attribution-source-v1', source_fingerprint,
        'attributed', 'current_same_version_source',
        'fixture-attribution-source-region',
        'fixture-attribution-source-v1', source_fingerprint),
      ('attr-region-only-mapped', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'attributed', 'current_explicit_mapping',
        'fixture-attribution-target-unique',
        'fixture-attribution-target-v1', target_fingerprint),
      ('attr-region-only-missing', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'unmapped', 'explicit_mapping_missing', NULL::text, NULL::text, NULL::text),
      ('attr-pending', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'not_reportable', 'pending_resolution', NULL::text, NULL::text, NULL::text),
      ('attr-not-applicable', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'not_reportable', 'not_applicable', NULL::text, NULL::text, NULL::text),
      ('attr-incomplete', 'current',
        'fixture-attribution-target-v1', target_fingerprint,
        'not_reportable', 'source_incomplete', NULL::text, NULL::text, NULL::text)
    ) AS cases(
      contact_id, view_mode, target_tree_version, target_fingerprint,
      result_status, reason_code, region_id, tree_version,
      result_fingerprint
    )
  LOOP
    SELECT sources.source_id
      INTO STRICT source_id_value
    FROM attribution_sources AS sources
    WHERE sources.contact_id = expected.contact_id;

    result := app_private.resolve_management_region_attribution_v1(
      source_id_value,
      expected.view_mode,
      expected.target_tree_version,
      expected.target_fingerprint
    );

    IF result->>'attribution_contract_id'
        IS DISTINCT FROM 'management-region-attribution:v1'
      OR result->>'view_mode' IS DISTINCT FROM expected.view_mode
      OR result->>'result_status' IS DISTINCT FROM expected.result_status
      OR result->>'reason_code' IS DISTINCT FROM expected.reason_code
    THEN
      RAISE EXCEPTION 'unexpected attribution result for %: %',
        expected.contact_id, result;
    END IF;

    IF expected.region_id IS NULL THEN
      IF result ? 'region_id'
        OR result ? 'tree_version'
        OR result ? 'content_fingerprint'
      THEN
        RAISE EXCEPTION 'non-attributed result leaked a region tuple for %: %',
          expected.contact_id, result;
      END IF;
    ELSE
      IF result->>'region_id' IS DISTINCT FROM expected.region_id
        OR result->>'tree_version' IS DISTINCT FROM expected.tree_version
        OR result->>'content_fingerprint'
          IS DISTINCT FROM expected.result_fingerprint
      THEN
        RAISE EXCEPTION 'attributed region tuple is wrong for %: %',
          expected.contact_id, result;
      END IF;
    END IF;

    FOR key_name IN SELECT jsonb_object_keys(result)
    LOOP
      IF key_name NOT IN (
        'attribution_contract_id', 'view_mode', 'result_status',
        'reason_code', 'region_id', 'tree_version', 'content_fingerprint'
      ) THEN
        RAISE EXCEPTION 'attribution result leaked uncontracted key % for %',
          key_name, expected.contact_id;
      END IF;
    END LOOP;
    IF result ?| ARRAY[
      'source_id', 'contact_id', 'revision_number', 'canonical_name',
      'place_name', 'latitude', 'longitude', 'location_kind',
      'evidence_kind', 'region_path', 'project_id', 'app_user_id'
    ] THEN
      RAISE EXCEPTION 'attribution result leaked sensitive evidence for %: %',
        expected.contact_id, result;
    END IF;
  END LOOP;

  -- Simulate a corrupted legacy source after its normal success case has been
  -- checked. The append-only trigger is disabled only for this synthetic row
  -- inside the rollback-only fixture; the resolver must reject the drifted
  -- source fingerprint instead of fabricating an original attribution.
  SELECT sources.source_id
    INTO STRICT source_id_value
  FROM attribution_sources AS sources
  WHERE sources.contact_id = 'attr-region-only-same';

  EXECUTE
    'ALTER TABLE app_data.contact_location_provenance '
    'DISABLE TRIGGER contact_location_provenance_append_only';
  UPDATE app_data.contact_location_provenance
  SET region_tree_content_fingerprint = repeat('f', 64)
  WHERE source_id = source_id_value;
  EXECUTE
    'ALTER TABLE app_data.contact_location_provenance '
    'ENABLE TRIGGER contact_location_provenance_append_only';

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'original', NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION
      'original attribution accepted a drifted source fingerprint';
  END IF;

  result := app_private.resolve_management_region_attribution_v1(
    '00000000-0000-4000-8000-000000000054'::uuid,
    'current',
    'fixture-attribution-target-v1',
    target_fingerprint
  );
  IF result->>'attribution_contract_id'
      IS DISTINCT FROM 'management-region-attribution:v1'
    OR result->>'view_mode' IS DISTINCT FROM 'current'
    OR result->>'result_status' IS DISTINCT FROM 'not_reportable'
    OR result->>'reason_code' IS DISTINCT FROM 'source_unavailable'
    OR result ?| ARRAY['region_id', 'tree_version', 'content_fingerprint']
  THEN
    RAISE EXCEPTION 'missing attribution source did not fail closed: %', result;
  END IF;

  -- The first pass above proves that no mapping is the unmapped case. Add a
  -- valid mapping to a target node without a city ancestor and ensure the
  -- resolver does not turn that structurally unreportable node into data.
  PERFORM app_private.register_canonical_region_version_mapping_v1(
    '54a00000-0000-4000-8000-000000000002'::uuid,
    'fixture-attribution-source-v1',
    'fixture-attribution-source-region-2',
    source_fingerprint,
    'fixture-attribution-target-v1',
    'fixture-attribution-target-country',
    target_fingerprint,
    repeat('b', 64)
  );

  SELECT sources.source_id
    INTO STRICT source_id_value
  FROM attribution_sources AS sources
  WHERE sources.contact_id = 'attr-region-only-missing';

  result := app_private.resolve_management_region_attribution_v1(
    source_id_value,
    'current',
    'fixture-attribution-target-v1',
    target_fingerprint
  );
  IF result->>'attribution_contract_id'
      IS DISTINCT FROM 'management-region-attribution:v1'
    OR result->>'view_mode' IS DISTINCT FROM 'current'
    OR result->>'result_status' IS DISTINCT FROM 'unmapped'
    OR result->>'reason_code' IS DISTINCT FROM 'target_region_not_reportable'
    OR result ?| ARRAY['region_id', 'tree_version', 'content_fingerprint']
  THEN
    RAISE EXCEPTION 'unreportable mapped target did not fail closed: %', result;
  END IF;

  -- The resolver must not infer a target tree or accept an untrusted target.
  SELECT sources.source_id
    INTO STRICT source_id_value
  FROM attribution_sources AS sources
  WHERE sources.contact_id = 'attr-coordinate-unique';

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'current', NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current attribution accepted a missing target';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'current',
      'fixture-attribution-target-v1', repeat('0', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current attribution accepted a drifted fingerprint';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'current', 'fixture-attribution-draft-v1', repeat('0', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current attribution accepted a draft target';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'current', 'fixture-attribution-unknown-v1', repeat('0', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'current attribution accepted an unknown target';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'latest', NULL, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'attribution accepted an unknown view';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_management_region_attribution_v1(
      source_id_value, 'original',
      'fixture-attribution-target-v1', target_fingerprint
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'original attribution accepted a target override';
  END IF;
END
$fixture$;

ROLLBACK;
