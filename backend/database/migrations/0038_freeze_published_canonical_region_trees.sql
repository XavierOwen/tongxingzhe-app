-- 0038_freeze_published_canonical_region_trees.sql
--
-- 规范区域树先作为草稿编辑，再由私有函数校验、生成内容指纹并冻结发布。
-- current 只是解析投影；每次选择追加历史，不能改写已发布内容。

DO $publisher_role$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'tongxingzhe_region_publisher'
  ) THEN
    CREATE ROLE tongxingzhe_region_publisher
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOINHERIT
      NOREPLICATION
      NOBYPASSRLS;
  END IF;
END
$publisher_role$;

ALTER ROLE tongxingzhe_region_publisher
  NOLOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  NOBYPASSRLS;

-- migration 在任何 ALTER 前按 release、节点、边界的仓库写入顺序
-- 取得写冲突锁，先等待既有事务结束，再同时封住历史回填窗口。
LOCK TABLE
  app_data.canonical_region_tree_releases,
  app_data.canonical_region_versions,
  app_data.canonical_region_boundaries
IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE app_data.canonical_region_tree_releases
  ALTER COLUMN published_at_utc DROP NOT NULL,
  ADD COLUMN lifecycle_state text,
  ADD COLUMN content_fingerprint text;

CREATE TABLE app_data.canonical_region_tree_current_selections (
  selection_sequence bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  selected_tree_version text NOT NULL
    REFERENCES app_data.canonical_region_tree_releases (tree_version)
    ON DELETE RESTRICT,
  previous_tree_version text
    REFERENCES app_data.canonical_region_tree_releases (tree_version)
    ON DELETE RESTRICT,
  selected_at_utc timestamptz,
  recorded_at_utc timestamptz NOT NULL,
  selection_source text NOT NULL CHECK (
    selection_source IN ('migration_baseline', 'publication')
  ),
  content_fingerprint text NOT NULL
    CHECK (content_fingerprint ~ '^[0-9a-f]{64}$'),
  CHECK (
    (
      selection_source = 'migration_baseline'
      AND selected_at_utc IS NULL
      AND previous_tree_version IS NULL
    ) OR (
      selection_source = 'publication'
      AND selected_at_utc IS NOT NULL
    )
  ),
  CHECK (
    previous_tree_version IS NULL
    OR previous_tree_version <> selected_tree_version
  )
);

REVOKE ALL PRIVILEGES
  ON app_data.canonical_region_tree_current_selections
  FROM tongxingzhe_runtime;

REVOKE ALL PRIVILEGES
  ON SEQUENCE app_data.canonical_region_tree_current_selections_selection_sequence_seq
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_private.canonical_region_tree_content_fingerprint_v1(
  requested_tree_version text
)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = pg_catalog, app_data
SET extra_float_digits = 3
AS $function$
  SELECT encode(
    sha256(
      convert_to(
        jsonb_build_object(
          'fingerprint_version',
          'canonical-region-tree-content:v1',
          'tree_version',
          requested_tree_version,
          'nodes',
          COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'region_id', node.region_id,
                  'parent_region_id', node.parent_region_id,
                  'canonical_name', node.canonical_name,
                  'kind', node.kind,
                  'attributes', node.attributes
                )
                ORDER BY node.region_id COLLATE "C"
              )
              FROM app_data.canonical_region_versions AS node
              WHERE node.tree_version = requested_tree_version
            ),
            '[]'::jsonb
          ),
          'boundaries',
          COALESCE(
            (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'boundary_id', boundary_row.boundary_id,
                  'region_id', boundary_row.region_id,
                  'boundary', boundary_row.boundary::text
                )
                ORDER BY boundary_row.boundary_id COLLATE "C"
              )
              FROM app_data.canonical_region_boundaries AS boundary_row
              WHERE boundary_row.tree_version = requested_tree_version
            ),
            '[]'::jsonb
          )
        )::text,
        'UTF8'
      )
    ),
    'hex'
  );
$function$;

REVOKE ALL
  ON FUNCTION app_private.canonical_region_tree_content_fingerprint_v1(text)
  FROM PUBLIC;

-- 历史 release 已在旧 migration 中明确发布。迁移保留原时间、current 和内容，
-- 只补生命周期、确定性指纹和 current 选择基线。
UPDATE app_data.canonical_region_tree_releases AS release_row
SET lifecycle_state = 'published',
    content_fingerprint =
      app_private.canonical_region_tree_content_fingerprint_v1(
        release_row.tree_version
      )
WHERE release_row.published_at_utc IS NOT NULL;

-- 约束必须在历史 release 回填后建立。否则 ALTER TABLE 会先把历史行视为
-- draft，再立即用 draft 约束验证其非空发布时间，导致真实升级失败。
ALTER TABLE app_data.canonical_region_tree_releases
  ALTER COLUMN lifecycle_state SET DEFAULT 'draft',
  ALTER COLUMN lifecycle_state SET NOT NULL,
  ADD CONSTRAINT canonical_region_release_lifecycle CHECK (
    lifecycle_state IN ('draft', 'published')
  ),
  ADD CONSTRAINT canonical_region_release_facts CHECK (
    (
      lifecycle_state = 'draft'
      AND published_at_utc IS NULL
      AND content_fingerprint IS NULL
      AND NOT is_current
    ) OR (
      lifecycle_state = 'published'
      AND published_at_utc IS NOT NULL
      AND content_fingerprint ~ '^[0-9a-f]{64}$'
    )
  );

INSERT INTO app_data.canonical_region_tree_current_selections (
  selected_tree_version,
  previous_tree_version,
  selected_at_utc,
  recorded_at_utc,
  selection_source,
  content_fingerprint
)
SELECT
  release_row.tree_version,
  NULL,
  NULL,
  clock_timestamp(),
  'migration_baseline',
  release_row.content_fingerprint
FROM app_data.canonical_region_tree_releases AS release_row
WHERE release_row.lifecycle_state = 'published'
  AND release_row.is_current;

CREATE FUNCTION app_data.guard_canonical_region_release_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  internal_publish boolean :=
    current_user = 'tongxingzhe_region_publisher';
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtextextended('canonical-region-tree-publication:v1', 0)
  );

  IF TG_OP = 'INSERT' THEN
    IF NEW.lifecycle_state <> 'draft'
      OR NEW.published_at_utc IS NOT NULL
      OR NEW.content_fingerprint IS NOT NULL
      OR NEW.is_current
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'canonical region release must begin as a draft';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region releases are append only';
  END IF;

  IF NOT internal_publish THEN
    IF OLD.lifecycle_state = 'published'
      OR NEW.lifecycle_state <> OLD.lifecycle_state
      OR NEW.published_at_utc IS DISTINCT FROM OLD.published_at_utc
      OR NEW.content_fingerprint IS DISTINCT FROM OLD.content_fingerprint
      OR NEW.is_current IS DISTINCT FROM OLD.is_current
      OR NEW.tree_version IS DISTINCT FROM OLD.tree_version
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'canonical region release facts are immutable';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER canonical_region_release_write_guard
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.canonical_region_tree_releases
FOR EACH ROW
EXECUTE FUNCTION app_data.guard_canonical_region_release_write();

REVOKE ALL
  ON FUNCTION app_data.guard_canonical_region_release_write()
  FROM PUBLIC;

CREATE FUNCTION app_data.guard_published_canonical_region_content()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  affected_tree_version text := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.tree_version
    ELSE NEW.tree_version
  END;
BEGIN
  -- 草稿编辑和发布共用一把事务锁。发布验证开始后，新编辑只能等待；
  -- 发布提交后它会看到 published 并失败，不能落在指纹计算与冻结之间。
  PERFORM pg_advisory_xact_lock(
    hashtextextended('canonical-region-tree-publication:v1', 0)
  );

  IF EXISTS (
    SELECT 1
    FROM app_data.canonical_region_tree_releases AS release_row
    WHERE release_row.tree_version = affected_tree_version
      AND release_row.lifecycle_state = 'published'
  ) OR (
    TG_OP = 'UPDATE'
    AND OLD.tree_version IS DISTINCT FROM NEW.tree_version
    AND EXISTS (
      SELECT 1
      FROM app_data.canonical_region_tree_releases AS release_row
      WHERE release_row.tree_version = OLD.tree_version
        AND release_row.lifecycle_state = 'published'
    )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'published canonical region content is immutable';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER canonical_region_node_publish_guard
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.canonical_region_versions
FOR EACH ROW
EXECUTE FUNCTION app_data.guard_published_canonical_region_content();

CREATE TRIGGER canonical_region_boundary_publish_guard
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.canonical_region_boundaries
FOR EACH ROW
EXECUTE FUNCTION app_data.guard_published_canonical_region_content();

REVOKE ALL
  ON FUNCTION app_data.guard_published_canonical_region_content()
  FROM PUBLIC;

CREATE FUNCTION app_data.guard_canonical_region_selection_history()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'INSERT'
    AND current_user = 'tongxingzhe_region_publisher'
  THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'canonical region current selection history is append only';
END
$function$;

CREATE TRIGGER canonical_region_selection_history_guard
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.canonical_region_tree_current_selections
FOR EACH ROW
EXECUTE FUNCTION app_data.guard_canonical_region_selection_history();

REVOKE ALL
  ON FUNCTION app_data.guard_canonical_region_selection_history()
  FROM PUBLIC;

CREATE FUNCTION app_private.publish_canonical_region_tree_v1(
  requested_tree_version text,
  make_current boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  release_row app_data.canonical_region_tree_releases%ROWTYPE;
  current_tree_version text;
  published_at timestamptz;
  fingerprint text;
BEGIN
  IF requested_tree_version IS NULL
    OR length(btrim(requested_tree_version)) = 0
    OR make_current IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid canonical region publication request';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('canonical-region-tree-publication:v1', 0)
  );
  published_at = clock_timestamp();

  SELECT * INTO release_row
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = requested_tree_version
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'unknown canonical region tree draft';
  END IF;
  IF release_row.lifecycle_state <> 'draft' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'canonical region tree is already published';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_versions
    WHERE tree_version = requested_tree_version
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'canonical region tree has no nodes';
  END IF;

  IF EXISTS (
    WITH RECURSIVE walk AS (
      SELECT
        node.region_id AS origin_region_id,
        node.region_id,
        node.parent_region_id,
        ARRAY[node.region_id]::text[] AS path,
        false AS cycle
      FROM app_data.canonical_region_versions AS node
      WHERE node.tree_version = requested_tree_version
      UNION ALL
      SELECT
        walk.origin_region_id,
        parent.region_id,
        parent.parent_region_id,
        walk.path || parent.region_id,
        parent.region_id = ANY(walk.path)
      FROM walk
      JOIN app_data.canonical_region_versions AS parent
        ON parent.region_id = walk.parent_region_id
       AND parent.tree_version = requested_tree_version
      WHERE NOT walk.cycle
    )
    SELECT 1 FROM walk WHERE cycle
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'canonical region tree cannot contain a cycle';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.canonical_region_boundaries
    WHERE tree_version = requested_tree_version
      AND npoints(boundary) >= 3
      AND area(boundary::path) > 0
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'canonical region tree requires a resolvable boundary';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.canonical_region_boundaries AS boundary_row
    WHERE boundary_row.tree_version = requested_tree_version
      AND NOT EXISTS (
        WITH RECURSIVE ancestors AS (
          SELECT node.region_id, node.parent_region_id, node.kind
          FROM app_data.canonical_region_versions AS node
          WHERE node.region_id = boundary_row.region_id
            AND node.tree_version = requested_tree_version
          UNION ALL
          SELECT parent.region_id, parent.parent_region_id, parent.kind
          FROM app_data.canonical_region_versions AS parent
          JOIN ancestors AS child
            ON parent.region_id = child.parent_region_id
          WHERE parent.tree_version = requested_tree_version
        )
        SELECT 1 FROM ancestors WHERE kind = 'city'
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'canonical region boundary requires a city ancestor';
  END IF;

  fingerprint = app_private.canonical_region_tree_content_fingerprint_v1(
    requested_tree_version
  );
  IF fingerprint IS NULL OR fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'canonical region tree fingerprint could not be computed';
  END IF;

  SELECT tree_version INTO current_tree_version
  FROM app_data.canonical_region_tree_releases
  WHERE is_current
  FOR UPDATE;

  IF make_current AND current_tree_version IS NOT NULL THEN
    UPDATE app_data.canonical_region_tree_releases
    SET is_current = false
    WHERE tree_version = current_tree_version;
  END IF;

  UPDATE app_data.canonical_region_tree_releases
  SET lifecycle_state = 'published',
      published_at_utc = published_at,
      content_fingerprint = fingerprint,
      is_current = make_current
  WHERE tree_version = requested_tree_version;

  IF make_current THEN
    INSERT INTO app_data.canonical_region_tree_current_selections (
      selected_tree_version,
      previous_tree_version,
      selected_at_utc,
      recorded_at_utc,
      selection_source,
      content_fingerprint
    ) VALUES (
      requested_tree_version,
      current_tree_version,
      published_at,
      published_at,
      'publication',
      fingerprint
    );
  END IF;

  RETURN jsonb_build_object(
    'tree_version', requested_tree_version,
    'lifecycle_state', 'published',
    'is_current', make_current,
    'content_fingerprint', fingerprint,
    'published_at_utc', published_at
  );
END
$function$;

REVOKE ALL
  ON FUNCTION app_private.publish_canonical_region_tree_v1(text, boolean)
  FROM PUBLIC;

GRANT USAGE ON SCHEMA app_data, app_private
  TO tongxingzhe_region_publisher;
GRANT SELECT ON
  app_data.canonical_region_versions,
  app_data.canonical_region_boundaries
  TO tongxingzhe_region_publisher;
GRANT SELECT, UPDATE ON app_data.canonical_region_tree_releases
  TO tongxingzhe_region_publisher;
GRANT SELECT, INSERT ON app_data.canonical_region_tree_current_selections
  TO tongxingzhe_region_publisher;
GRANT USAGE, SELECT ON SEQUENCE
  app_data.canonical_region_tree_current_selections_selection_sequence_seq
  TO tongxingzhe_region_publisher;
GRANT EXECUTE ON FUNCTION
  app_private.canonical_region_tree_content_fingerprint_v1(text)
  TO tongxingzhe_region_publisher;

-- SECURITY DEFINER 让 trigger 看到不可由普通维护会话伪造的 current_user。
-- migration 身份保留显式调用权，但不保留 SET ROLE 能力。
GRANT tongxingzhe_region_publisher TO CURRENT_USER;
GRANT EXECUTE ON FUNCTION
  app_private.publish_canonical_region_tree_v1(text, boolean)
  TO CURRENT_USER;
ALTER FUNCTION app_private.publish_canonical_region_tree_v1(text, boolean)
  OWNER TO tongxingzhe_region_publisher;
REVOKE tongxingzhe_region_publisher FROM CURRENT_USER;

DO $publisher_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS publisher_role
      ON publisher_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE publisher_role.rolname = 'tongxingzhe_region_publisher'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_region_publisher FROM %I',
      member_name
    );
  END LOOP;
END
$publisher_membership$;

COMMENT ON FUNCTION app_private.publish_canonical_region_tree_v1(text, boolean)
  IS 'Validates, fingerprints, freezes, and optionally selects one canonical region tree draft.';
