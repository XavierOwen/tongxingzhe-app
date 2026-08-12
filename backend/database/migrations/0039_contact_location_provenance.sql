-- 0039_contact_location_provenance.sql
--
-- 把每个已接受 contact revision 的地点保存为追加式来源证据。
-- contact_region_assignments 继续是当前投影，不再被当作历史来源。

DO $writer_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_contact_provenance_writer'
  ) THEN
    CREATE ROLE tongxingzhe_contact_provenance_writer
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$writer_role$;

ALTER ROLE tongxingzhe_contact_provenance_writer
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

-- 先等待已进入 revision 写入的事务结束，再一次回填并安装
-- AFTER INSERT trigger，避免 migration 窗口丢失证据。
LOCK TABLE app_data.contact_revisions
IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE app_data.contact_location_provenance (
  source_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id text NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  revision_kind text NOT NULL CHECK (
    revision_kind IN ('submitted', 'corrected', 'voided')
  ),
  location_kind text NOT NULL CHECK (
    location_kind IN (
      'resolved',
      'pending_resolution',
      'not_applicable',
      'unknown'
    )
  ),
  evidence_kind text NOT NULL CHECK (
    evidence_kind IN (
      'resolved_from_coordinates',
      'resolved_region_only',
      'pending_coordinates',
      'not_applicable',
      'legacy_incomplete'
    )
  ),
  place_name text CHECK (
    place_name IS NULL OR length(btrim(place_name)) > 0
  ),
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  smallest_region_id text,
  region_tree_version text,
  region_tree_content_fingerprint text,
  resolver_contract_version text,
  recorded_at_utc timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT contact_location_provenance_revision_unique
    UNIQUE (contact_id, revision_number),
  CONSTRAINT contact_location_provenance_revision_fk
    FOREIGN KEY (contact_id, revision_number)
    REFERENCES app_data.contact_revisions (contact_id, revision_number)
    ON DELETE RESTRICT,
  CONSTRAINT contact_location_provenance_region_fk
    FOREIGN KEY (smallest_region_id, region_tree_version)
    REFERENCES app_data.canonical_region_versions (region_id, tree_version)
    ON DELETE RESTRICT,
  CONSTRAINT contact_location_provenance_release_fk
    FOREIGN KEY (region_tree_version)
    REFERENCES app_data.canonical_region_tree_releases (tree_version)
    ON DELETE RESTRICT,
  CONSTRAINT contact_location_provenance_shape CHECK (
    (
      location_kind = 'resolved'
      AND evidence_kind = 'resolved_from_coordinates'
      AND smallest_region_id IS NOT NULL
      AND region_tree_version IS NOT NULL
      AND region_tree_content_fingerprint IS NOT NULL
      AND region_tree_content_fingerprint ~ '^[0-9a-f]{64}$'
      AND resolver_contract_version IS NOT NULL
      AND resolver_contract_version = 'canonical-region-resolution:v1'
      AND latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
      AND (accuracy_meters IS NULL OR accuracy_meters >= 0)
    ) OR (
      location_kind = 'resolved'
      AND evidence_kind = 'resolved_region_only'
      AND smallest_region_id IS NOT NULL
      AND region_tree_version IS NOT NULL
      AND region_tree_content_fingerprint IS NOT NULL
      AND region_tree_content_fingerprint ~ '^[0-9a-f]{64}$'
      AND resolver_contract_version IS NULL
      AND latitude IS NULL
      AND longitude IS NULL
      AND accuracy_meters IS NULL
    ) OR (
      location_kind = 'pending_resolution'
      AND evidence_kind = 'pending_coordinates'
      AND place_name IS NULL
      AND latitude IS NOT NULL
      AND longitude IS NOT NULL
      AND latitude BETWEEN -90 AND 90
      AND longitude BETWEEN -180 AND 180
      AND (accuracy_meters IS NULL OR accuracy_meters >= 0)
      AND smallest_region_id IS NULL
      AND region_tree_version IS NULL
      AND region_tree_content_fingerprint IS NULL
      AND resolver_contract_version IS NULL
    ) OR (
      location_kind = 'not_applicable'
      AND evidence_kind = 'not_applicable'
      AND place_name IS NULL
      AND latitude IS NULL
      AND longitude IS NULL
      AND accuracy_meters IS NULL
      AND smallest_region_id IS NULL
      AND region_tree_version IS NULL
      AND region_tree_content_fingerprint IS NULL
      AND resolver_contract_version IS NULL
    ) OR (
      location_kind = 'unknown'
      AND evidence_kind = 'legacy_incomplete'
      AND place_name IS NULL
      AND latitude IS NULL
      AND longitude IS NULL
      AND accuracy_meters IS NULL
      AND smallest_region_id IS NULL
      AND region_tree_version IS NULL
      AND region_tree_content_fingerprint IS NULL
      AND resolver_contract_version IS NULL
    )
  )
);

COMMENT ON TABLE app_data.contact_location_provenance
IS 'Append-only location evidence for one accepted contact revision; not a current-region projection.';

REVOKE ALL PRIVILEGES
  ON app_data.contact_location_provenance
  FROM PUBLIC, tongxingzhe_runtime;

-- 历史回填只读各 revision 自己的 snapshot。该路径发生在 INSERT
-- guard 安装之前，且 migration 已锁定 revision 写入窗口。
WITH revision_evidence AS (
  SELECT
    revision_row.contact_id,
    revision_row.revision_number,
    revision_row.revision_kind,
    revision_row.snapshot->'location' AS location_value
  FROM app_data.contact_revisions AS revision_row
), classified AS (
  SELECT
    evidence.*,
    release_row.content_fingerprint,
    CASE
      WHEN jsonb_typeof(evidence.location_value) = 'object'
        AND evidence.location_value->>'kind' = 'not_applicable'
        AND NOT EXISTS (
          SELECT 1
          FROM jsonb_object_keys(evidence.location_value)
            AS key_row(key_name)
          WHERE key_name <> 'kind'
        )
      THEN 'not_applicable'
      WHEN jsonb_typeof(evidence.location_value) = 'object'
        AND evidence.location_value->>'kind' = 'pending_resolution'
        AND jsonb_typeof(evidence.location_value->'latitude') = 'number'
        AND jsonb_typeof(evidence.location_value->'longitude') = 'number'
        AND (evidence.location_value->>'latitude')::double precision
          BETWEEN -90 AND 90
        AND (evidence.location_value->>'longitude')::double precision
          BETWEEN -180 AND 180
        AND (
          evidence.location_value->'accuracyMeters' IS NULL
          OR evidence.location_value->'accuracyMeters' = 'null'::jsonb
          OR (
            jsonb_typeof(evidence.location_value->'accuracyMeters') = 'number'
            AND (evidence.location_value->>'accuracyMeters')::double precision
              >= 0
          )
        )
        AND NOT EXISTS (
          SELECT 1
          FROM jsonb_object_keys(evidence.location_value)
            AS key_row(key_name)
          WHERE key_name NOT IN (
            'kind', 'latitude', 'longitude', 'accuracyMeters'
          )
        )
      THEN 'pending_coordinates'
      WHEN jsonb_typeof(evidence.location_value) = 'object'
        AND evidence.location_value->>'kind' = 'resolved'
        AND NULLIF(btrim(
          evidence.location_value->>'smallestRegionId'
        ), '') IS NOT NULL
        AND NULLIF(btrim(
          evidence.location_value->>'regionTreeVersion'
        ), '') IS NOT NULL
        AND release_row.lifecycle_state = 'published'
        AND release_row.content_fingerprint ~ '^[0-9a-f]{64}$'
        AND NOT EXISTS (
          SELECT 1
          FROM jsonb_object_keys(evidence.location_value)
            AS key_row(key_name)
          WHERE key_name NOT IN (
            'kind', 'placeName', 'smallestRegionId', 'regionTreeVersion'
          )
        )
        AND EXISTS (
          WITH RECURSIVE ancestors AS (
            SELECT
              node.region_id,
              node.parent_region_id,
              node.kind
            FROM app_data.canonical_region_versions AS node
            WHERE node.region_id =
                evidence.location_value->>'smallestRegionId'
              AND node.tree_version =
                evidence.location_value->>'regionTreeVersion'
            UNION ALL
            SELECT parent.region_id, parent.parent_region_id, parent.kind
            FROM app_data.canonical_region_versions AS parent
            JOIN ancestors AS child
              ON parent.region_id = child.parent_region_id
            WHERE parent.tree_version =
              evidence.location_value->>'regionTreeVersion'
          )
          SELECT 1 FROM ancestors WHERE kind = 'city'
        )
      THEN 'resolved_region_only'
      ELSE 'legacy_incomplete'
    END AS classified_kind
  FROM revision_evidence AS evidence
  LEFT JOIN app_data.canonical_region_tree_releases AS release_row
    ON release_row.tree_version =
      evidence.location_value->>'regionTreeVersion'
)
INSERT INTO app_data.contact_location_provenance (
  contact_id,
  revision_number,
  revision_kind,
  location_kind,
  evidence_kind,
  place_name,
  latitude,
  longitude,
  accuracy_meters,
  smallest_region_id,
  region_tree_version,
  region_tree_content_fingerprint
)
SELECT
  classified.contact_id,
  classified.revision_number,
  classified.revision_kind,
  CASE classified.classified_kind
    WHEN 'resolved_region_only' THEN 'resolved'
    WHEN 'pending_coordinates' THEN 'pending_resolution'
    WHEN 'not_applicable' THEN 'not_applicable'
    ELSE 'unknown'
  END,
  classified.classified_kind,
  CASE WHEN classified.classified_kind = 'resolved_region_only'
    THEN NULLIF(btrim(classified.location_value->>'placeName'), '')
    ELSE NULL
  END,
  CASE WHEN classified.classified_kind = 'pending_coordinates'
    THEN (classified.location_value->>'latitude')::double precision
    ELSE NULL
  END,
  CASE WHEN classified.classified_kind = 'pending_coordinates'
    THEN (classified.location_value->>'longitude')::double precision
    ELSE NULL
  END,
  CASE WHEN classified.classified_kind = 'pending_coordinates'
      AND classified.location_value->'accuracyMeters' IS NOT NULL
      AND classified.location_value->'accuracyMeters' <> 'null'::jsonb
    THEN (classified.location_value->>'accuracyMeters')::double precision
    ELSE NULL
  END,
  CASE WHEN classified.classified_kind = 'resolved_region_only'
    THEN classified.location_value->>'smallestRegionId'
    ELSE NULL
  END,
  CASE WHEN classified.classified_kind = 'resolved_region_only'
    THEN classified.location_value->>'regionTreeVersion'
    ELSE NULL
  END,
  CASE WHEN classified.classified_kind = 'resolved_region_only'
    THEN classified.content_fingerprint
    ELSE NULL
  END
FROM classified;

CREATE FUNCTION app_private.reject_contact_location_provenance_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'contact location provenance is append-only';
END
$function$;

CREATE TRIGGER contact_location_provenance_append_only
BEFORE UPDATE OR DELETE
ON app_data.contact_location_provenance
FOR EACH ROW
EXECUTE FUNCTION app_private.reject_contact_location_provenance_mutation_v1();

CREATE FUNCTION app_private.require_contact_location_provenance_writer_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF current_user <> 'tongxingzhe_contact_provenance_writer' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'contact location provenance must follow the revision seam';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER contact_location_provenance_insert_guard
BEFORE INSERT
ON app_data.contact_location_provenance
FOR EACH ROW
EXECUTE FUNCTION app_private.require_contact_location_provenance_writer_v1();

CREATE FUNCTION app_private.capture_contact_location_provenance_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  location_value jsonb := NEW.snapshot->'location';
  source_value jsonb := NEW.snapshot->'locationSource';
  location_kind_value text;
  evidence_kind_value text;
  place_name_value text;
  latitude_value double precision;
  longitude_value double precision;
  accuracy_value double precision;
  region_id_value text;
  tree_version_value text;
  release_fingerprint text;
  resolver_contract_value text;
BEGIN
  IF jsonb_typeof(location_value) IS DISTINCT FROM 'object' THEN
    -- 早期 migration／fixture 曾直接追加没有 location 的 revision。
    -- 它们是已接受历史；只能显式标成不完整，不能据当前投影补猜。
    location_kind_value := 'unknown';
    evidence_kind_value := 'legacy_incomplete';
  ELSE
    location_kind_value := location_value->>'kind';
    IF location_kind_value = 'not_applicable' THEN
    IF source_value IS NOT NULL
      OR EXISTS (
        SELECT 1
        FROM jsonb_object_keys(location_value) AS key_row(key_name)
        WHERE key_name <> 'kind'
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'not applicable location cannot carry source facts';
    END IF;
    evidence_kind_value := 'not_applicable';
    ELSIF location_kind_value = 'pending_resolution' THEN
    IF source_value IS NOT NULL
      OR jsonb_typeof(location_value->'latitude') <> 'number'
      OR jsonb_typeof(location_value->'longitude') <> 'number'
      OR EXISTS (
        SELECT 1
        FROM jsonb_object_keys(location_value) AS key_row(key_name)
        WHERE key_name NOT IN (
          'kind', 'latitude', 'longitude', 'accuracyMeters'
        )
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'pending location requires coordinates only';
    END IF;
    latitude_value := (location_value->>'latitude')::double precision;
    longitude_value := (location_value->>'longitude')::double precision;
    IF location_value->'accuracyMeters' IS NOT NULL
      AND location_value->'accuracyMeters' <> 'null'::jsonb
    THEN
      IF jsonb_typeof(location_value->'accuracyMeters') <> 'number' THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'location accuracy must be numeric';
      END IF;
      accuracy_value :=
        (location_value->>'accuracyMeters')::double precision;
    END IF;
    IF latitude_value NOT BETWEEN -90 AND 90
      OR longitude_value NOT BETWEEN -180 AND 180
      OR (accuracy_value IS NOT NULL AND accuracy_value < 0)
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'pending location coordinates are invalid';
    END IF;
    evidence_kind_value := 'pending_coordinates';
    ELSIF location_kind_value = 'resolved' THEN
    region_id_value := NULLIF(btrim(
      location_value->>'smallestRegionId'
    ), '');
    tree_version_value := NULLIF(btrim(
      location_value->>'regionTreeVersion'
    ), '');
    place_name_value := NULLIF(btrim(location_value->>'placeName'), '');
    IF region_id_value IS NULL
      OR tree_version_value IS NULL
      OR EXISTS (
        SELECT 1
        FROM jsonb_object_keys(location_value) AS key_row(key_name)
        WHERE key_name NOT IN (
          'kind', 'placeName', 'smallestRegionId', 'regionTreeVersion'
        )
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'resolved location requires a versioned region';
    END IF;

    SELECT release_row.content_fingerprint
      INTO release_fingerprint
    FROM app_data.canonical_region_tree_releases AS release_row
    WHERE release_row.tree_version = tree_version_value
      AND release_row.lifecycle_state = 'published';

    IF release_fingerprint IS NULL
      OR NOT EXISTS (
        WITH RECURSIVE ancestors AS (
          SELECT node.region_id, node.parent_region_id, node.kind
          FROM app_data.canonical_region_versions AS node
          WHERE node.region_id = region_id_value
            AND node.tree_version = tree_version_value
          UNION ALL
          SELECT parent.region_id, parent.parent_region_id, parent.kind
          FROM app_data.canonical_region_versions AS parent
          JOIN ancestors AS child
            ON parent.region_id = child.parent_region_id
          WHERE parent.tree_version = tree_version_value
        )
        SELECT 1 FROM ancestors WHERE kind = 'city'
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'resolved location requires a published city region';
    END IF;

    IF source_value IS NULL THEN
      evidence_kind_value := 'resolved_region_only';
    ELSE
      IF jsonb_typeof(source_value) <> 'object'
        OR source_value->>'kind' <> 'captured_coordinates'
        OR jsonb_typeof(source_value->'latitude') <> 'number'
        OR jsonb_typeof(source_value->'longitude') <> 'number'
        OR source_value->>'resolverContractVersion'
          <> 'canonical-region-resolution:v1'
        OR source_value->>'regionTreeContentFingerprint'
          IS DISTINCT FROM release_fingerprint
        OR EXISTS (
          SELECT 1
          FROM jsonb_object_keys(source_value) AS key_row(key_name)
          WHERE key_name NOT IN (
            'kind', 'latitude', 'longitude', 'accuracyMeters',
            'resolverContractVersion', 'regionTreeContentFingerprint'
          )
        )
      THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'resolved location source does not match the release';
      END IF;
      latitude_value := (source_value->>'latitude')::double precision;
      longitude_value := (source_value->>'longitude')::double precision;
      IF source_value->'accuracyMeters' IS NOT NULL
        AND source_value->'accuracyMeters' <> 'null'::jsonb
      THEN
        IF jsonb_typeof(source_value->'accuracyMeters') <> 'number' THEN
          RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'location source accuracy must be numeric';
        END IF;
        accuracy_value :=
          (source_value->>'accuracyMeters')::double precision;
      END IF;
      IF latitude_value NOT BETWEEN -90 AND 90
        OR longitude_value NOT BETWEEN -180 AND 180
        OR (accuracy_value IS NOT NULL AND accuracy_value < 0)
      THEN
        RAISE EXCEPTION USING
          ERRCODE = '23514',
          MESSAGE = 'resolved location source coordinates are invalid';
      END IF;
      resolver_contract_value := 'canonical-region-resolution:v1';
      evidence_kind_value := 'resolved_from_coordinates';
    END IF;
    ELSE
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'contact revision location kind is invalid';
    END IF;
  END IF;

  INSERT INTO app_data.contact_location_provenance (
    contact_id,
    revision_number,
    revision_kind,
    location_kind,
    evidence_kind,
    place_name,
    latitude,
    longitude,
    accuracy_meters,
    smallest_region_id,
    region_tree_version,
    region_tree_content_fingerprint,
    resolver_contract_version
  ) VALUES (
    NEW.contact_id,
    NEW.revision_number,
    NEW.revision_kind,
    location_kind_value,
    evidence_kind_value,
    place_name_value,
    latitude_value,
    longitude_value,
    accuracy_value,
    region_id_value,
    tree_version_value,
    release_fingerprint,
    resolver_contract_value
  );

  RETURN NEW;
END
$function$;

REVOKE ALL
  ON FUNCTION
    app_private.reject_contact_location_provenance_mutation_v1(),
    app_private.require_contact_location_provenance_writer_v1(),
    app_private.capture_contact_location_provenance_v1()
  FROM PUBLIC, tongxingzhe_runtime;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_contact_provenance_writer;
GRANT SELECT
  ON app_data.canonical_region_tree_releases,
     app_data.canonical_region_versions
  TO tongxingzhe_contact_provenance_writer;
GRANT INSERT
  ON app_data.contact_location_provenance
  TO tongxingzhe_contact_provenance_writer;

-- ALTER FUNCTION OWNER 要求 migration owner 暂时成为目标 role 成员。
-- owner 转移后立即撤销；最后再清理该 NOLOGIN role 的任何意外成员。
GRANT tongxingzhe_contact_provenance_writer TO CURRENT_USER;
ALTER FUNCTION app_private.capture_contact_location_provenance_v1()
  OWNER TO tongxingzhe_contact_provenance_writer;
REVOKE tongxingzhe_contact_provenance_writer FROM CURRENT_USER;

DO $writer_membership$
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
    WHERE writer_role.rolname = 'tongxingzhe_contact_provenance_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_contact_provenance_writer FROM %I',
      member_name
    );
  END LOOP;
END
$writer_membership$;

CREATE TRIGGER contact_revision_location_provenance
AFTER INSERT
ON app_data.contact_revisions
FOR EACH ROW
EXECUTE FUNCTION app_private.capture_contact_location_provenance_v1();

COMMENT ON FUNCTION app_private.capture_contact_location_provenance_v1()
IS 'Trusted trigger seam that appends one immutable location source with its accepted contact revision.';
