-- 0053_canonical_region_version_mappings.sql
--
-- Old region-only provenance may enter another published tree version only
-- through explicit one-to-one evidence. The registry never guesses from
-- names, parent chains, geometry, or the current-tree selection.

DO $mapping_writer_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_region_mapping_writer'
  ) THEN
    CREATE ROLE tongxingzhe_region_mapping_writer
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$mapping_writer_role$;

ALTER ROLE tongxingzhe_region_mapping_writer
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

CREATE TABLE app_data.canonical_region_version_mappings (
  mapping_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE,
  source_tree_version text NOT NULL,
  source_region_id text NOT NULL,
  source_content_fingerprint text NOT NULL CHECK (
    source_content_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  target_tree_version text NOT NULL,
  target_region_id text NOT NULL,
  target_content_fingerprint text NOT NULL CHECK (
    target_content_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  evidence_contract text NOT NULL DEFAULT
    'canonical-region-version-mapping-evidence:v1' CHECK (
      evidence_contract =
        'canonical-region-version-mapping-evidence:v1'
    ),
  evidence_digest text NOT NULL CHECK (
    evidence_digest ~ '^[0-9a-f]{64}$'
  ),
  recorded_at_utc timestamptz NOT NULL DEFAULT clock_timestamp() CHECK (
    isfinite(recorded_at_utc)
  ),
  CONSTRAINT canonical_region_version_mapping_distinct_versions CHECK (
    source_tree_version <> target_tree_version
  ),
  CONSTRAINT canonical_region_version_mapping_source_release_fk
    FOREIGN KEY (source_tree_version)
    REFERENCES app_data.canonical_region_tree_releases (tree_version)
    ON DELETE RESTRICT,
  CONSTRAINT canonical_region_version_mapping_target_release_fk
    FOREIGN KEY (target_tree_version)
    REFERENCES app_data.canonical_region_tree_releases (tree_version)
    ON DELETE RESTRICT,
  CONSTRAINT canonical_region_version_mapping_source_node_fk
    FOREIGN KEY (source_region_id, source_tree_version)
    REFERENCES app_data.canonical_region_versions (region_id, tree_version)
    ON DELETE RESTRICT,
  CONSTRAINT canonical_region_version_mapping_target_node_fk
    FOREIGN KEY (target_region_id, target_tree_version)
    REFERENCES app_data.canonical_region_versions (region_id, tree_version)
    ON DELETE RESTRICT,
  -- v1 is truly one-to-one for a specific ordered pair of tree versions.
  -- The first key rejects a split; the second rejects a merge.
  CONSTRAINT canonical_region_version_mapping_no_split UNIQUE (
    source_tree_version,
    source_region_id,
    target_tree_version
  ),
  CONSTRAINT canonical_region_version_mapping_no_merge UNIQUE (
    source_tree_version,
    target_tree_version,
    target_region_id
  )
);

REVOKE ALL PRIVILEGES
  ON app_data.canonical_region_version_mappings
  FROM PUBLIC, tongxingzhe_runtime, tongxingzhe_region_publisher;

CREATE FUNCTION app_data.guard_canonical_region_version_mapping_write_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'INSERT'
    AND current_user = 'tongxingzhe_region_mapping_writer'
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'canonical region version mappings are append only';
END
$function$;

CREATE TRIGGER canonical_region_version_mapping_write_guard
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.canonical_region_version_mappings
FOR EACH ROW
EXECUTE FUNCTION app_data.guard_canonical_region_version_mapping_write_v1();

CREATE TRIGGER canonical_region_version_mapping_truncate_guard
BEFORE TRUNCATE
ON app_data.canonical_region_version_mappings
FOR EACH STATEMENT
EXECUTE FUNCTION app_data.guard_canonical_region_version_mapping_write_v1();

REVOKE ALL
  ON FUNCTION app_data.guard_canonical_region_version_mapping_write_v1()
  FROM PUBLIC;

CREATE FUNCTION app_private.canonical_region_version_mapping_document_v1(
  requested_mapping_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'mapping_contract_id', 'canonical-region-version-mapping:v1',
    'mapping_id', mapping.mapping_id,
    'request_id', mapping.request_id,
    'source_tree_version', mapping.source_tree_version,
    'source_region_id', mapping.source_region_id,
    'source_content_fingerprint', mapping.source_content_fingerprint,
    'target_tree_version', mapping.target_tree_version,
    'target_region_id', mapping.target_region_id,
    'target_content_fingerprint', mapping.target_content_fingerprint,
    'evidence_contract', mapping.evidence_contract,
    'evidence_digest', mapping.evidence_digest,
    'recorded_at_utc', mapping.recorded_at_utc
  )
  FROM app_data.canonical_region_version_mappings AS mapping
  WHERE mapping.mapping_id = requested_mapping_id;
$function$;

REVOKE ALL
  ON FUNCTION app_private.canonical_region_version_mapping_document_v1(uuid)
  FROM PUBLIC;

CREATE FUNCTION app_private.register_canonical_region_version_mapping_v1(
  requested_request_id uuid,
  requested_source_tree_version text,
  requested_source_region_id text,
  requested_source_content_fingerprint text,
  requested_target_tree_version text,
  requested_target_region_id text,
  requested_target_content_fingerprint text,
  requested_evidence_digest text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  normalized_source_tree_version text :=
    btrim(requested_source_tree_version);
  normalized_source_region_id text := btrim(requested_source_region_id);
  normalized_source_fingerprint text :=
    btrim(requested_source_content_fingerprint);
  normalized_target_tree_version text :=
    btrim(requested_target_tree_version);
  normalized_target_region_id text := btrim(requested_target_region_id);
  normalized_target_fingerprint text :=
    btrim(requested_target_content_fingerprint);
  normalized_evidence_digest text := btrim(requested_evidence_digest);
  existing_mapping app_data.canonical_region_version_mappings%ROWTYPE;
  source_release app_data.canonical_region_tree_releases%ROWTYPE;
  target_release app_data.canonical_region_tree_releases%ROWTYPE;
  inserted_mapping_id uuid;
BEGIN
  IF requested_request_id IS NULL
    OR normalized_source_tree_version IS NULL
    OR length(normalized_source_tree_version) = 0
    OR normalized_source_region_id IS NULL
    OR length(normalized_source_region_id) = 0
    OR normalized_source_fingerprint IS NULL
    OR normalized_source_fingerprint !~ '^[0-9a-f]{64}$'
    OR normalized_target_tree_version IS NULL
    OR length(normalized_target_tree_version) = 0
    OR normalized_target_region_id IS NULL
    OR length(normalized_target_region_id) = 0
    OR normalized_target_fingerprint IS NULL
    OR normalized_target_fingerprint !~ '^[0-9a-f]{64}$'
    OR normalized_evidence_digest IS NULL
    OR normalized_evidence_digest !~ '^[0-9a-f]{64}$'
    OR normalized_source_tree_version = normalized_target_tree_version
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid canonical region version mapping request';
  END IF;

  -- Tree publication and mapping registration share this lock. A mapping can
  -- never observe half-published content or cross a fingerprint freeze.
  PERFORM pg_advisory_xact_lock(
    hashtextextended('canonical-region-tree-publication:v1', 0)
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'canonical-region-version-mapping-request:'
        || requested_request_id::text,
      0
    )
  );

  SELECT * INTO existing_mapping
  FROM app_data.canonical_region_version_mappings AS mapping
  WHERE mapping.request_id = requested_request_id
  FOR UPDATE;

  IF FOUND THEN
    IF existing_mapping.source_tree_version
        IS DISTINCT FROM normalized_source_tree_version
      OR existing_mapping.source_region_id
        IS DISTINCT FROM normalized_source_region_id
      OR existing_mapping.source_content_fingerprint
        IS DISTINCT FROM normalized_source_fingerprint
      OR existing_mapping.target_tree_version
        IS DISTINCT FROM normalized_target_tree_version
      OR existing_mapping.target_region_id
        IS DISTINCT FROM normalized_target_region_id
      OR existing_mapping.target_content_fingerprint
        IS DISTINCT FROM normalized_target_fingerprint
      OR existing_mapping.evidence_contract
        IS DISTINCT FROM
          'canonical-region-version-mapping-evidence:v1'
      OR existing_mapping.evidence_digest
        IS DISTINCT FROM normalized_evidence_digest
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'canonical region version mapping request conflict';
    END IF;

    RETURN app_private.canonical_region_version_mapping_document_v1(
      existing_mapping.mapping_id
    );
  END IF;

  SELECT * INTO source_release
  FROM app_data.canonical_region_tree_releases AS release_row
  WHERE release_row.tree_version = normalized_source_tree_version;

  SELECT * INTO target_release
  FROM app_data.canonical_region_tree_releases AS release_row
  WHERE release_row.tree_version = normalized_target_tree_version;

  IF source_release.tree_version IS NULL
    OR target_release.tree_version IS NULL
    OR source_release.lifecycle_state <> 'published'
    OR target_release.lifecycle_state <> 'published'
    OR source_release.content_fingerprint
      IS DISTINCT FROM normalized_source_fingerprint
    OR target_release.content_fingerprint
      IS DISTINCT FROM normalized_target_fingerprint
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE =
        'canonical region mapping requires matching published fingerprints';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_versions AS node
    WHERE node.tree_version = normalized_source_tree_version
      AND node.region_id = normalized_source_region_id
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_versions AS node
    WHERE node.tree_version = normalized_target_tree_version
      AND node.region_id = normalized_target_region_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region mapping node is unavailable';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.canonical_region_version_mappings AS mapping
    WHERE mapping.source_tree_version = normalized_source_tree_version
      AND mapping.source_region_id = normalized_source_region_id
      AND mapping.target_tree_version = normalized_target_tree_version
  ) OR EXISTS (
    SELECT 1
    FROM app_data.canonical_region_version_mappings AS mapping
    WHERE mapping.source_tree_version = normalized_source_tree_version
      AND mapping.target_tree_version = normalized_target_tree_version
      AND mapping.target_region_id = normalized_target_region_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region version mapping is not one to one';
  END IF;

  INSERT INTO app_data.canonical_region_version_mappings (
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
    requested_request_id,
    normalized_source_tree_version,
    normalized_source_region_id,
    normalized_source_fingerprint,
    normalized_target_tree_version,
    normalized_target_region_id,
    normalized_target_fingerprint,
    'canonical-region-version-mapping-evidence:v1',
    normalized_evidence_digest
  )
  RETURNING mapping_id INTO inserted_mapping_id;

  RETURN app_private.canonical_region_version_mapping_document_v1(
    inserted_mapping_id
  );
END
$function$;

CREATE FUNCTION app_private.resolve_canonical_region_version_mapping_v1(
  requested_source_tree_version text,
  requested_source_region_id text,
  requested_source_content_fingerprint text,
  requested_target_tree_version text,
  requested_target_content_fingerprint text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  normalized_source_tree_version text :=
    btrim(requested_source_tree_version);
  normalized_source_region_id text := btrim(requested_source_region_id);
  normalized_source_fingerprint text :=
    btrim(requested_source_content_fingerprint);
  normalized_target_tree_version text :=
    btrim(requested_target_tree_version);
  normalized_target_fingerprint text :=
    btrim(requested_target_content_fingerprint);
  source_release app_data.canonical_region_tree_releases%ROWTYPE;
  target_release app_data.canonical_region_tree_releases%ROWTYPE;
  resolved_mapping app_data.canonical_region_version_mappings%ROWTYPE;
BEGIN
  IF normalized_source_tree_version IS NULL
    OR length(normalized_source_tree_version) = 0
    OR normalized_source_region_id IS NULL
    OR length(normalized_source_region_id) = 0
    OR normalized_source_fingerprint IS NULL
    OR normalized_source_fingerprint !~ '^[0-9a-f]{64}$'
    OR normalized_target_tree_version IS NULL
    OR length(normalized_target_tree_version) = 0
    OR normalized_target_fingerprint IS NULL
    OR normalized_target_fingerprint !~ '^[0-9a-f]{64}$'
    OR normalized_source_tree_version = normalized_target_tree_version
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid canonical region version mapping resolution';
  END IF;

  SELECT * INTO source_release
  FROM app_data.canonical_region_tree_releases AS release_row
  WHERE release_row.tree_version = normalized_source_tree_version;

  SELECT * INTO target_release
  FROM app_data.canonical_region_tree_releases AS release_row
  WHERE release_row.tree_version = normalized_target_tree_version;

  IF source_release.tree_version IS NULL
    OR target_release.tree_version IS NULL
    OR source_release.lifecycle_state <> 'published'
    OR target_release.lifecycle_state <> 'published'
    OR source_release.content_fingerprint
      IS DISTINCT FROM normalized_source_fingerprint
    OR target_release.content_fingerprint
      IS DISTINCT FROM normalized_target_fingerprint
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.canonical_region_versions AS node
      WHERE node.tree_version = normalized_source_tree_version
        AND node.region_id = normalized_source_region_id
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE =
        'canonical region mapping resolution provenance is unavailable';
  END IF;

  SELECT * INTO resolved_mapping
  FROM app_data.canonical_region_version_mappings AS mapping
  WHERE mapping.source_tree_version = normalized_source_tree_version
    AND mapping.source_region_id = normalized_source_region_id
    AND mapping.source_content_fingerprint = normalized_source_fingerprint
    AND mapping.target_tree_version = normalized_target_tree_version
    AND mapping.target_content_fingerprint = normalized_target_fingerprint;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'resolution_contract_id',
      'canonical-region-version-mapping-resolution:v1',
      'mapping_status', 'unmapped',
      'source_tree_version', normalized_source_tree_version,
      'source_region_id', normalized_source_region_id,
      'source_content_fingerprint', normalized_source_fingerprint,
      'target_tree_version', normalized_target_tree_version,
      'target_content_fingerprint', normalized_target_fingerprint
    );
  END IF;

  RETURN jsonb_build_object(
    'resolution_contract_id',
    'canonical-region-version-mapping-resolution:v1',
    'mapping_status', 'mapped'
  ) || app_private.canonical_region_version_mapping_document_v1(
    resolved_mapping.mapping_id
  );
END
$function$;

REVOKE ALL
  ON FUNCTION app_private.register_canonical_region_version_mapping_v1(
    uuid, text, text, text, text, text, text, text
  )
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL
  ON FUNCTION app_private.resolve_canonical_region_version_mapping_v1(
    text, text, text, text, text
  )
  FROM PUBLIC, tongxingzhe_runtime;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_region_mapping_writer;
GRANT SELECT ON
  app_data.canonical_region_tree_releases,
  app_data.canonical_region_versions
  TO tongxingzhe_region_mapping_writer;
GRANT SELECT, INSERT ON app_data.canonical_region_version_mappings
  TO tongxingzhe_region_mapping_writer;

GRANT EXECUTE ON FUNCTION
  app_private.register_canonical_region_version_mapping_v1(
    uuid, text, text, text, text, text, text, text
  ),
  app_private.resolve_canonical_region_version_mapping_v1(
    text, text, text, text, text
  )
  TO tongxingzhe_region_publisher;

-- Keep the migration identity able to run maintenance fixtures without
-- retaining membership in the internal writer role.
GRANT EXECUTE ON FUNCTION
  app_private.register_canonical_region_version_mapping_v1(
    uuid, text, text, text, text, text, text, text
  ),
  app_private.resolve_canonical_region_version_mapping_v1(
    text, text, text, text, text
  )
  TO CURRENT_USER;

GRANT tongxingzhe_region_mapping_writer TO CURRENT_USER;
ALTER TABLE app_data.canonical_region_version_mappings
  OWNER TO tongxingzhe_region_mapping_writer;
ALTER FUNCTION app_private.canonical_region_version_mapping_document_v1(uuid)
  OWNER TO tongxingzhe_region_mapping_writer;
ALTER FUNCTION app_private.register_canonical_region_version_mapping_v1(
  uuid, text, text, text, text, text, text, text
) OWNER TO tongxingzhe_region_mapping_writer;
ALTER FUNCTION app_private.resolve_canonical_region_version_mapping_v1(
  text, text, text, text, text
) OWNER TO tongxingzhe_region_mapping_writer;
REVOKE tongxingzhe_region_mapping_writer FROM CURRENT_USER;

DO $mapping_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname = 'tongxingzhe_region_mapping_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_region_mapping_writer FROM %I',
      member_name
    );
  END LOOP;
END
$mapping_writer_membership$;

COMMENT ON TABLE app_data.canonical_region_version_mappings
  IS 'Append-only explicit one-to-one evidence between two published canonical region tree versions.';
COMMENT ON FUNCTION app_private.register_canonical_region_version_mapping_v1(
  uuid, text, text, text, text, text, text, text
) IS 'Registers one immutable evidence-bound mapping without guessing names, parent chains, or geometry.';
COMMENT ON FUNCTION app_private.resolve_canonical_region_version_mapping_v1(
  text, text, text, text, text
) IS 'Returns mapped or unmapped only after exact source and target release fingerprint validation.';
