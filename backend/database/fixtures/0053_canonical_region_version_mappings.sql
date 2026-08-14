\set ON_ERROR_STOP on

-- Synthetic evidence for the private, explicit one-to-one mapping boundary.
-- The fixture rolls back; the separate concurrency script owns committed rows.
BEGIN;

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version,
  lifecycle_state,
  is_current
) VALUES
  ('fixture-region-mapping-source-v1', 'draft', false),
  ('fixture-region-mapping-target-v1', 'draft', false),
  ('fixture-region-mapping-draft-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
) VALUES
  (
    'fixture-region-mapping-source-country',
    'fixture-region-mapping-source-v1',
    NULL,
    'Fixture Mapping Source Country',
    'country'
  ),
  (
    'fixture-region-mapping-source-city',
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-country',
    'Fixture Mapping Source City',
    'city'
  ),
  (
    'fixture-region-mapping-source-region',
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-city',
    'Fixture Mapping Source Region',
    'venue'
  ),
  (
    'fixture-region-mapping-source-region-2',
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-city',
    'Fixture Mapping Source Region 2',
    'venue'
  ),
  (
    'fixture-region-mapping-target-country',
    'fixture-region-mapping-target-v1',
    NULL,
    'Fixture Mapping Target Country',
    'country'
  ),
  (
    'fixture-region-mapping-target-city',
    'fixture-region-mapping-target-v1',
    'fixture-region-mapping-target-country',
    'Fixture Mapping Target City',
    'city'
  ),
  (
    'fixture-region-mapping-target-region',
    'fixture-region-mapping-target-v1',
    'fixture-region-mapping-target-city',
    'Fixture Mapping Target Region',
    'venue'
  ),
  (
    'fixture-region-mapping-target-region-2',
    'fixture-region-mapping-target-v1',
    'fixture-region-mapping-target-city',
    'Fixture Mapping Target Region 2',
    'venue'
  ),
  (
    'fixture-region-mapping-target-region-3',
    'fixture-region-mapping-target-v1',
    'fixture-region-mapping-target-city',
    'Fixture Mapping Target Region 3',
    'venue'
  );

INSERT INTO app_data.canonical_region_versions (
  region_id,
  tree_version,
  parent_region_id,
  canonical_name,
  kind
) VALUES
  (
    'fixture-region-mapping-draft-country',
    'fixture-region-mapping-draft-v1',
    NULL,
    'Fixture Mapping Draft Country',
    'country'
  ),
  (
    'fixture-region-mapping-draft-city',
    'fixture-region-mapping-draft-v1',
    'fixture-region-mapping-draft-country',
    'Fixture Mapping Draft City',
    'city'
  );

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id,
  region_id,
  tree_version,
  boundary
) VALUES
  (
    'fixture-region-mapping-source-boundary',
    'fixture-region-mapping-source-region',
    'fixture-region-mapping-source-v1',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  ),
  (
    'fixture-region-mapping-source-boundary-2',
    'fixture-region-mapping-source-region-2',
    'fixture-region-mapping-source-v1',
    polygon '((-87.63,41.77),(-87.56,41.77),(-87.56,41.82),(-87.63,41.82))'
  ),
  (
    'fixture-region-mapping-target-boundary',
    'fixture-region-mapping-target-region',
    'fixture-region-mapping-target-v1',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  ),
  (
    'fixture-region-mapping-target-boundary-2',
    'fixture-region-mapping-target-region-2',
    'fixture-region-mapping-target-v1',
    polygon '((-87.63,41.77),(-87.56,41.77),(-87.56,41.82),(-87.63,41.82))'
  ),
  (
    'fixture-region-mapping-target-boundary-3',
    'fixture-region-mapping-target-region-3',
    'fixture-region-mapping-target-v1',
    polygon '((-87.64,41.76),(-87.55,41.76),(-87.55,41.83),(-87.64,41.83))'
  );

-- Both trees are published and then treated as immutable release facts. The
-- draft remains intentionally unpublished for the fail-closed case below.
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-region-mapping-source-v1',
  false
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-region-mapping-target-v1',
  false
);

CREATE TEMP TABLE fixture_region_mapping_fingerprints (
  source_fingerprint text NOT NULL,
  target_fingerprint text NOT NULL
);

INSERT INTO fixture_region_mapping_fingerprints (
  source_fingerprint,
  target_fingerprint
)
SELECT
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-region-mapping-source-v1'
  ),
  max(content_fingerprint) FILTER (
    WHERE tree_version = 'fixture-region-mapping-target-v1'
  )
FROM app_data.canonical_region_tree_releases;

DO $fixture$
DECLARE
  source_fingerprint text;
  target_fingerprint text;
  first_document jsonb;
  replay_document jsonb;
  persisted_document jsonb;
  mapped_document jsonb;
  unmapped_document jsonb;
  failed boolean;
BEGIN
  SELECT
    fingerprints.source_fingerprint,
    fingerprints.target_fingerprint
  INTO source_fingerprint, target_fingerprint
  FROM fixture_region_mapping_fingerprints AS fingerprints;

  IF source_fingerprint !~ '^[0-9a-f]{64}$'
    OR target_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'published fixture trees did not receive SHA-256 fingerprints';
  END IF;

  -- Success and exact request idempotency. The second call must return the
  -- same document, including the original mapping ID and recorded timestamp.
  first_document := app_private.register_canonical_region_version_mapping_v1(
    '53a00000-0000-4000-8000-000000000001'::uuid,
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-region',
    source_fingerprint,
    'fixture-region-mapping-target-v1',
    'fixture-region-mapping-target-region',
    target_fingerprint,
    repeat('a', 64)
  );
  replay_document := app_private.register_canonical_region_version_mapping_v1(
    '53a00000-0000-4000-8000-000000000001'::uuid,
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-region',
    source_fingerprint,
    'fixture-region-mapping-target-v1',
    'fixture-region-mapping-target-region',
    target_fingerprint,
    repeat('a', 64)
  );

  IF first_document IS NULL
    OR first_document IS DISTINCT FROM replay_document
    OR first_document->>'mapping_contract_id'
      IS DISTINCT FROM 'canonical-region-version-mapping:v1'
    OR first_document->>'request_id'
      IS DISTINCT FROM '53a00000-0000-4000-8000-000000000001'
    OR first_document->>'evidence_contract'
      IS DISTINCT FROM 'canonical-region-version-mapping-evidence:v1'
    OR first_document->>'evidence_digest' <> repeat('a', 64)
  THEN
    RAISE EXCEPTION 'mapping success or exact idempotency contract failed';
  END IF;

  SELECT to_jsonb(mapping_row)
  INTO persisted_document
  FROM app_data.canonical_region_version_mappings AS mapping_row
  WHERE mapping_row.request_id =
    '53a00000-0000-4000-8000-000000000001'::uuid;
  IF persisted_document IS NULL
    OR persisted_document->>'source_tree_version'
      IS DISTINCT FROM 'fixture-region-mapping-source-v1'
    OR persisted_document->>'source_region_id'
      IS DISTINCT FROM 'fixture-region-mapping-source-region'
    OR persisted_document->>'target_tree_version'
      IS DISTINCT FROM 'fixture-region-mapping-target-v1'
    OR persisted_document->>'target_region_id'
      IS DISTINCT FROM 'fixture-region-mapping-target-region'
    OR persisted_document->>'source_content_fingerprint'
      IS DISTINCT FROM source_fingerprint
    OR persisted_document->>'target_content_fingerprint'
      IS DISTINCT FROM target_fingerprint
    OR persisted_document->>'recorded_at_utc' IS NULL
  THEN
    RAISE EXCEPTION 'persisted mapping facts are incomplete';
  END IF;

  -- A request ID is an idempotency key, not a mutable alias.
  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000001'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region',
      target_fingerprint,
      repeat('b', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'request payload drift was accepted';
  END IF;

  -- Registration requires the exact frozen fingerprints of both releases.
  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000002'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      repeat('0', 64),
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region-2',
      target_fingerprint,
      repeat('c', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'bad source fingerprint was accepted';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000009'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region-2',
      repeat('0', 64),
      repeat('c', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'bad target fingerprint was accepted';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000003'::uuid,
      'fixture-region-mapping-draft-v1',
      'fixture-region-mapping-draft-city',
      repeat('0', 64),
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region-2',
      target_fingerprint,
      repeat('d', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'draft source tree was accepted';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000004'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-unknown-region',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region-2',
      target_fingerprint,
      repeat('e', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'unknown source node was accepted';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-00000000000a'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-unknown-region',
      target_fingerprint,
      repeat('e', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'unknown target node was accepted';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000005'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      source_fingerprint,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      source_fingerprint,
      repeat('f', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'same-version mapping was accepted';
  END IF;

  -- One source node cannot be split into two target nodes in the same target
  -- tree, and two source nodes cannot merge into one target node.
  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000006'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region-2',
      target_fingerprint,
      repeat('1', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'split mapping was accepted';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.register_canonical_region_version_mapping_v1(
      '53a00000-0000-4000-8000-000000000007'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region',
      target_fingerprint,
      repeat('2', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'merge mapping was accepted';
  END IF;

  mapped_document := app_private.resolve_canonical_region_version_mapping_v1(
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-region',
    source_fingerprint,
    'fixture-region-mapping-target-v1',
    target_fingerprint
  );
  IF mapped_document->>'mapping_status' IS DISTINCT FROM 'mapped'
    OR mapped_document->>'target_tree_version'
      IS DISTINCT FROM 'fixture-region-mapping-target-v1'
    OR mapped_document->>'target_region_id'
      IS DISTINCT FROM 'fixture-region-mapping-target-region'
  THEN
    RAISE EXCEPTION 'mapped resolver result is incomplete: %', mapped_document;
  END IF;

  unmapped_document := app_private.resolve_canonical_region_version_mapping_v1(
    'fixture-region-mapping-source-v1',
    'fixture-region-mapping-source-region-2',
    source_fingerprint,
    'fixture-region-mapping-target-v1',
    target_fingerprint
  );
  IF unmapped_document->>'mapping_status' IS DISTINCT FROM 'unmapped'
    OR unmapped_document ? 'target_region_id'
  THEN
    RAISE EXCEPTION 'unmapped resolver result was not fail-closed: %',
      unmapped_document;
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_canonical_region_version_mapping_v1(
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region',
      repeat('0', 64),
      'fixture-region-mapping-target-v1',
      target_fingerprint
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'resolver accepted an incorrect fingerprint';
  END IF;

  failed := false;
  BEGIN
    PERFORM app_private.resolve_canonical_region_version_mapping_v1(
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      repeat('0', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'resolver accepted an incorrect target fingerprint';
  END IF;

  -- The table is not an alternate writer surface. Trigger-protected direct
  -- INSERT, UPDATE, DELETE and TRUNCATE must all fail, even for the superuser
  -- test session; only the SECURITY DEFINER registration function may append.
  failed := false;
  BEGIN
    INSERT INTO app_data.canonical_region_version_mappings (
      mapping_id,
      request_id,
      source_tree_version,
      source_region_id,
      source_content_fingerprint,
      target_tree_version,
      target_region_id,
      target_content_fingerprint,
      evidence_contract,
      evidence_digest
    ) VALUES (
      '53a00000-0000-4000-8000-000000000008'::uuid,
      '53a00000-0000-4000-8000-000000000008'::uuid,
      'fixture-region-mapping-source-v1',
      'fixture-region-mapping-source-region-2',
      source_fingerprint,
      'fixture-region-mapping-target-v1',
      'fixture-region-mapping-target-region-2',
      target_fingerprint,
      'canonical-region-version-mapping-evidence:v1',
      repeat('3', 64)
    );
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'direct mapping INSERT bypassed the writer function';
  END IF;

  failed := false;
  BEGIN
    UPDATE app_data.canonical_region_version_mappings
    SET evidence_digest = evidence_digest
    WHERE request_id =
      '53a00000-0000-4000-8000-000000000001'::uuid;
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'direct mapping UPDATE bypassed append-only protection';
  END IF;

  failed := false;
  BEGIN
    DELETE FROM app_data.canonical_region_version_mappings
    WHERE request_id =
      '53a00000-0000-4000-8000-000000000001'::uuid;
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'direct mapping DELETE bypassed append-only protection';
  END IF;

  failed := false;
  BEGIN
    TRUNCATE TABLE app_data.canonical_region_version_mappings;
  EXCEPTION WHEN OTHERS THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'mapping TRUNCATE bypassed append-only protection';
  END IF;

  IF (
    SELECT count(*)
    FROM app_data.canonical_region_version_mappings
    WHERE request_id =
      '53a00000-0000-4000-8000-000000000001'::uuid
  ) <> 1 THEN
    RAISE EXCEPTION 'direct table mutation changed the registered mapping';
  END IF;
END
$fixture$;

ROLLBACK;
