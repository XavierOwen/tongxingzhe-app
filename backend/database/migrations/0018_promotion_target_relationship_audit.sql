-- 0018_promotion_target_relationship_audit.sql
--
-- 项目关系保留一个当前投影和追加修订历史。共享跟进备注只存在于这个
-- 受分配保护的数据面，不进入接触、同步日志、通知或 warehouse payload。

ALTER TABLE app_data.promotion_target_project_relationships
  ADD COLUMN current_lifecycle_status text NOT NULL DEFAULT 'active'
    CHECK (current_lifecycle_status IN ('active', 'paused', 'ended')),
  ADD COLUMN current_follow_up_note text
    CHECK (
      current_follow_up_note IS NULL
      OR length(btrim(current_follow_up_note)) BETWEEN 1 AND 4000
    ),
  ADD COLUMN current_revision integer NOT NULL DEFAULT 1
    CHECK (current_revision > 0),
  ADD COLUMN updated_by_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  ADD COLUMN updated_at timestamptz;

UPDATE app_data.promotion_target_project_relationships
SET updated_by_app_user_id = established_by_app_user_id,
    updated_at = established_at;

ALTER TABLE app_data.promotion_target_project_relationships
  ALTER COLUMN updated_by_app_user_id SET NOT NULL,
  ALTER COLUMN updated_at SET NOT NULL;

CREATE TABLE app_data.promotion_target_relationship_revisions (
  promotion_target_id uuid NOT NULL,
  project_id uuid NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  old_stage integer CHECK (old_stage BETWEEN 0 AND 4),
  new_stage integer NOT NULL CHECK (new_stage BETWEEN 0 AND 4),
  old_lifecycle_status text CHECK (
    old_lifecycle_status IN ('active', 'paused', 'ended')
  ),
  new_lifecycle_status text NOT NULL CHECK (
    new_lifecycle_status IN ('active', 'paused', 'ended')
  ),
  follow_up_note text CHECK (
    follow_up_note IS NULL
    OR length(btrim(follow_up_note)) BETWEEN 1 AND 4000
  ),
  changed_fields text[] NOT NULL CHECK (cardinality(changed_fields) > 0),
  reason_code text NOT NULL CHECK (
    reason_code IN (
      'project_entry',
      'progress_update',
      'contact_lost',
      'timing_changed',
      'requirements_changed',
      'target_request',
      'project_change',
      'correction',
      'other'
    )
  ),
  reason_detail text CHECK (
    reason_detail IS NULL
    OR length(btrim(reason_detail)) BETWEEN 1 AND 1000
  ),
  changed_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  mutation_id text CHECK (
    mutation_id IS NULL
    OR length(btrim(mutation_id)) BETWEEN 1 AND 120
  ),
  requested_base_revision integer CHECK (requested_base_revision > 0),
  requested_stage integer CHECK (requested_stage BETWEEN 0 AND 4),
  requested_lifecycle_status text CHECK (
    requested_lifecycle_status IN ('active', 'paused', 'ended')
  ),
  requested_follow_up_note text CHECK (
    requested_follow_up_note IS NULL
    OR length(btrim(requested_follow_up_note)) BETWEEN 1 AND 4000
  ),
  PRIMARY KEY (promotion_target_id, project_id, revision_number),
  FOREIGN KEY (promotion_target_id, project_id)
    REFERENCES app_data.promotion_target_project_relationships (
      promotion_target_id,
      project_id
    ) ON DELETE RESTRICT,
  CHECK (
    old_stage IS NOT NULL
    OR (revision_number = 1 AND reason_code = 'project_entry')
  ),
  CHECK (reason_code <> 'other' OR reason_detail IS NOT NULL),
  CHECK (
    (mutation_id IS NULL
      AND requested_base_revision IS NULL
      AND requested_stage IS NULL
      AND requested_lifecycle_status IS NULL)
    OR
    (mutation_id IS NOT NULL
      AND requested_base_revision IS NOT NULL
      AND requested_stage IS NOT NULL
      AND requested_lifecycle_status IS NOT NULL)
  )
);

CREATE UNIQUE INDEX promotion_target_relationship_mutation_once
  ON app_data.promotion_target_relationship_revisions (
    changed_by_app_user_id,
    mutation_id
  )
  WHERE mutation_id IS NOT NULL;

CREATE INDEX promotion_target_relationship_revision_history
  ON app_data.promotion_target_relationship_revisions (
    promotion_target_id,
    project_id,
    revision_number DESC
  );

CREATE TABLE app_data.promotion_target_relationship_conflicts (
  conflict_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_target_id uuid NOT NULL,
  project_id uuid NOT NULL,
  base_revision integer NOT NULL CHECK (base_revision > 0),
  current_revision integer NOT NULL CHECK (current_revision > base_revision),
  proposed_stage integer NOT NULL CHECK (proposed_stage BETWEEN 0 AND 4),
  proposed_lifecycle_status text NOT NULL CHECK (
    proposed_lifecycle_status IN ('active', 'paused', 'ended')
  ),
  proposed_follow_up_note text CHECK (
    proposed_follow_up_note IS NULL
    OR length(btrim(proposed_follow_up_note)) BETWEEN 1 AND 4000
  ),
  proposed_reason_code text NOT NULL,
  proposed_reason_detail text,
  conflicting_fields text[] NOT NULL CHECK (
    cardinality(conflicting_fields) > 0
  ),
  created_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  mutation_id text NOT NULL CHECK (
    length(btrim(mutation_id)) BETWEEN 1 AND 120
  ),
  FOREIGN KEY (promotion_target_id, project_id)
    REFERENCES app_data.promotion_target_project_relationships (
      promotion_target_id,
      project_id
    ) ON DELETE RESTRICT,
  UNIQUE (created_by_app_user_id, mutation_id)
);

CREATE TABLE app_data.promotion_target_relationship_conflict_resolutions (
  conflict_id uuid PRIMARY KEY
    REFERENCES app_data.promotion_target_relationship_conflicts (conflict_id)
    ON DELETE RESTRICT,
  resolved_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  resolved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  resolved_revision integer NOT NULL CHECK (resolved_revision > 0),
  resolution_choice text NOT NULL CHECK (
    resolution_choice IN ('keep_current', 'apply_proposed', 'custom')
  )
);

ALTER TABLE app_data.promotion_target_relationship_revisions
  ADD COLUMN resolved_conflict_id uuid
    REFERENCES app_data.promotion_target_relationship_conflicts (conflict_id)
    ON DELETE RESTRICT;

CREATE TABLE app_data.promotion_target_stage_aliases (
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  stage integer NOT NULL CHECK (stage BETWEEN 0 AND 4),
  display_name text NOT NULL CHECK (
    length(btrim(display_name)) BETWEEN 1 AND 80
  ),
  updated_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (project_id, stage)
);

REVOKE ALL PRIVILEGES
  ON app_data.promotion_target_relationship_revisions,
     app_data.promotion_target_relationship_conflicts,
     app_data.promotion_target_relationship_conflict_resolutions,
     app_data.promotion_target_stage_aliases
  FROM tongxingzhe_runtime;

INSERT INTO app_data.promotion_target_relationship_revisions (
  promotion_target_id,
  project_id,
  revision_number,
  old_stage,
  new_stage,
  old_lifecycle_status,
  new_lifecycle_status,
  follow_up_note,
  changed_fields,
  reason_code,
  changed_by_app_user_id,
  changed_at
)
SELECT
  relationship_row.promotion_target_id,
  relationship_row.project_id,
  1,
  NULL,
  relationship_row.current_stage,
  NULL,
  'active',
  NULL,
  ARRAY['stage', 'lifecycle_status']::text[],
  'project_entry',
  relationship_row.established_by_app_user_id,
  relationship_row.established_at
FROM app_data.promotion_target_project_relationships AS relationship_row;

CREATE FUNCTION app_data.prepare_initial_promotion_target_relationship()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  NEW.current_lifecycle_status := COALESCE(
    NEW.current_lifecycle_status,
    'active'
  );
  NEW.current_revision := COALESCE(NEW.current_revision, 1);
  NEW.updated_by_app_user_id := COALESCE(
    NEW.updated_by_app_user_id,
    NEW.established_by_app_user_id
  );
  NEW.updated_at := COALESCE(
    NEW.updated_at,
    NEW.established_at,
    clock_timestamp()
  );
  RETURN NEW;
END
$function$;

CREATE TRIGGER promotion_target_relationship_prepare_initial
BEFORE INSERT ON app_data.promotion_target_project_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_data.prepare_initial_promotion_target_relationship();

CREATE FUNCTION app_data.install_initial_promotion_target_relationship_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  INSERT INTO app_data.promotion_target_relationship_revisions (
    promotion_target_id,
    project_id,
    revision_number,
    old_stage,
    new_stage,
    old_lifecycle_status,
    new_lifecycle_status,
    follow_up_note,
    changed_fields,
    reason_code,
    changed_by_app_user_id,
    changed_at
  ) VALUES (
    NEW.promotion_target_id,
    NEW.project_id,
    NEW.current_revision,
    NULL,
    NEW.current_stage,
    NULL,
    NEW.current_lifecycle_status,
    NEW.current_follow_up_note,
    ARRAY['stage', 'lifecycle_status']::text[],
    'project_entry',
    NEW.established_by_app_user_id,
    NEW.established_at
  );
  RETURN NEW;
END
$function$;

CREATE TRIGGER promotion_target_relationship_initial_revision
AFTER INSERT ON app_data.promotion_target_project_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_data.install_initial_promotion_target_relationship_revision();

CREATE FUNCTION app_data.reject_promotion_target_relationship_revision_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'promotion target relationship revisions are append-only';
END
$function$;

CREATE TRIGGER promotion_target_relationship_revisions_immutable
BEFORE UPDATE OR DELETE
ON app_data.promotion_target_relationship_revisions
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_relationship_revision_mutation();

CREATE TRIGGER promotion_target_relationship_conflicts_immutable
BEFORE UPDATE OR DELETE
ON app_data.promotion_target_relationship_conflicts
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_relationship_revision_mutation();

CREATE TRIGGER promotion_target_relationship_conflict_resolutions_immutable
BEFORE UPDATE OR DELETE
ON app_data.promotion_target_relationship_conflict_resolutions
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_relationship_revision_mutation();

CREATE FUNCTION app_data.promotion_target_stage_aliases_document(
  requested_project_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_agg(
    jsonb_build_object(
      'stage', stage_value,
      'display_stage', stage_value * 2,
      'display_name', alias_row.display_name
    )
    ORDER BY stage_value
  )
  FROM generate_series(0, 4) AS stage_value
  LEFT JOIN app_data.promotion_target_stage_aliases AS alias_row
    ON alias_row.project_id = requested_project_id
   AND alias_row.stage = stage_value;
$function$;

CREATE FUNCTION app_data.promotion_target_relationship_document(
  requested_target_id uuid,
  requested_project_id uuid,
  include_history boolean
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'target_id', relationship_row.promotion_target_id,
    'project_id', relationship_row.project_id,
    'stage', relationship_row.current_stage,
    'display_stage', relationship_row.current_stage * 2,
    'lifecycle_status', relationship_row.current_lifecycle_status,
    'follow_up_note', relationship_row.current_follow_up_note,
    'revision_number', relationship_row.current_revision,
    'updated_at', relationship_row.updated_at,
    'stage_aliases', app_data.promotion_target_stage_aliases_document(
      relationship_row.project_id
    ),
    'history', CASE
      WHEN include_history THEN COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'revision_number', revision_row.revision_number,
            'old_stage', revision_row.old_stage,
            'new_stage', revision_row.new_stage,
            'old_lifecycle_status', revision_row.old_lifecycle_status,
            'new_lifecycle_status', revision_row.new_lifecycle_status,
            'follow_up_note', revision_row.follow_up_note,
            'changed_fields', revision_row.changed_fields,
            'reason_code', revision_row.reason_code,
            'reason_detail', revision_row.reason_detail,
            'changed_by_app_user_id',
              revision_row.changed_by_app_user_id,
            'changed_at', revision_row.changed_at
          ) ORDER BY revision_row.revision_number DESC
        )
        FROM app_data.promotion_target_relationship_revisions AS revision_row
        WHERE revision_row.promotion_target_id =
            relationship_row.promotion_target_id
          AND revision_row.project_id = relationship_row.project_id
      ), '[]'::jsonb)
      ELSE '[]'::jsonb
    END
  )
  FROM app_data.promotion_target_project_relationships AS relationship_row
  WHERE relationship_row.promotion_target_id = requested_target_id
    AND relationship_row.project_id = requested_project_id;
$function$;

CREATE FUNCTION app_data.promotion_target_relationship_authorized(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_target_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT app_data.promotion_target_context_authorized(
      trusted_app_user_id,
      trusted_workspace_id,
      trusted_project_id
    )
    AND EXISTS (
      SELECT 1
      FROM app_data.promotion_targets AS target_row
      JOIN app_data.promotion_target_assignments AS assignment_row
        ON assignment_row.promotion_target_id =
          target_row.promotion_target_id
       AND assignment_row.app_user_id = trusted_app_user_id
       AND assignment_row.ended_at IS NULL
      JOIN app_data.promotion_target_project_relationships AS relationship_row
        ON relationship_row.promotion_target_id =
          target_row.promotion_target_id
       AND relationship_row.project_id = trusted_project_id
      WHERE target_row.promotion_target_id = requested_target_id
        AND target_row.workspace_id = trusted_workspace_id
        AND target_row.status = 'active'
    );
$function$;

CREATE FUNCTION app_data.update_promotion_target_relationship(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_target_id uuid,
  expected_revision integer,
  requested_stage integer,
  requested_lifecycle_status text,
  requested_follow_up_note text,
  requested_reason_code text,
  requested_reason_detail text,
  requested_mutation_id text,
  requested_resolved_conflict_id uuid
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  current_row app_data.promotion_target_project_relationships%ROWTYPE;
  base_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  replay_row app_data.promotion_target_relationship_revisions%ROWTYPE;
  replay_conflict app_data.promotion_target_relationship_conflicts%ROWTYPE;
  resolved_conflict app_data.promotion_target_relationship_conflicts%ROWTYPE;
  normalized_note text := CASE
    WHEN requested_follow_up_note IS NULL
      OR btrim(requested_follow_up_note) = '' THEN NULL
    ELSE btrim(requested_follow_up_note)
  END;
  normalized_detail text := CASE
    WHEN requested_reason_detail IS NULL
      OR btrim(requested_reason_detail) = '' THEN NULL
    ELSE btrim(requested_reason_detail)
  END;
  normalized_mutation_id text := btrim(requested_mutation_id);
  proposed_fields text[] := ARRAY[]::text[];
  server_fields text[] := ARRAY[]::text[];
  conflicting_fields_value text[] := ARRAY[]::text[];
  changed_fields_value text[] := ARRAY[]::text[];
  effective_stage integer;
  effective_lifecycle_status text;
  effective_note text;
  conflict_id_value uuid;
  resolution_choice_value text;
  next_revision integer;
BEGIN
  IF requested_target_id IS NULL
    OR expected_revision IS NULL OR expected_revision < 1
    OR requested_stage IS NULL OR requested_stage NOT BETWEEN 0 AND 4
    OR requested_lifecycle_status IS NULL
    OR requested_lifecycle_status NOT IN ('active', 'paused', 'ended')
    OR requested_reason_code IS NULL
    OR requested_reason_code NOT IN (
      'progress_update',
      'contact_lost',
      'timing_changed',
      'requirements_changed',
      'target_request',
      'project_change',
      'correction',
      'other'
    )
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
    OR (normalized_note IS NOT NULL AND length(normalized_note) > 4000)
    OR (normalized_detail IS NOT NULL AND length(normalized_detail) > 1000)
    OR (requested_reason_code = 'other' AND normalized_detail IS NULL)
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid promotion target relationship update';
  END IF;

  IF NOT app_data.promotion_target_relationship_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    requested_target_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target relationship access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      requested_target_id::text || ':' || trusted_project_id::text,
      0
    )
  );

  SELECT revision_row.* INTO replay_row
  FROM app_data.promotion_target_relationship_revisions AS revision_row
  WHERE revision_row.changed_by_app_user_id = trusted_app_user_id
    AND revision_row.mutation_id = normalized_mutation_id;

  IF FOUND THEN
    IF replay_row.promotion_target_id <> requested_target_id
      OR replay_row.project_id <> trusted_project_id
      OR replay_row.requested_base_revision <> expected_revision
      OR replay_row.requested_stage <> requested_stage
      OR replay_row.requested_lifecycle_status <>
        requested_lifecycle_status
      OR replay_row.requested_follow_up_note IS DISTINCT FROM normalized_note
      OR replay_row.reason_code <> requested_reason_code
      OR replay_row.reason_detail IS DISTINCT FROM normalized_detail
      OR replay_row.resolved_conflict_id IS DISTINCT FROM
        requested_resolved_conflict_id
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'relationship mutation id was reused with different input';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'status', 'accepted',
      'duplicate', true,
      'accepted_revision', replay_row.revision_number,
      'relationship', app_data.promotion_target_relationship_document(
        requested_target_id,
        trusted_project_id,
        true
      )
    );
    RETURN;
  END IF;

  SELECT conflict_row.* INTO replay_conflict
  FROM app_data.promotion_target_relationship_conflicts AS conflict_row
  WHERE conflict_row.created_by_app_user_id = trusted_app_user_id
    AND conflict_row.mutation_id = normalized_mutation_id;

  IF FOUND THEN
    IF replay_conflict.promotion_target_id <> requested_target_id
      OR replay_conflict.project_id <> trusted_project_id
      OR replay_conflict.base_revision <> expected_revision
      OR replay_conflict.proposed_stage <> requested_stage
      OR replay_conflict.proposed_lifecycle_status <>
        requested_lifecycle_status
      OR replay_conflict.proposed_follow_up_note IS DISTINCT FROM
        normalized_note
      OR replay_conflict.proposed_reason_code <> requested_reason_code
      OR replay_conflict.proposed_reason_detail IS DISTINCT FROM
        normalized_detail
      OR requested_resolved_conflict_id IS NOT NULL
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'relationship mutation id was reused with different input';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'status', 'conflict',
      'conflict_id', replay_conflict.conflict_id,
      'conflicting_fields', replay_conflict.conflicting_fields,
      'current', app_data.promotion_target_relationship_document(
        requested_target_id,
        trusted_project_id,
        true
      ),
      'proposed', jsonb_build_object(
        'expected_revision', replay_conflict.base_revision,
        'stage', replay_conflict.proposed_stage,
        'display_stage', replay_conflict.proposed_stage * 2,
        'lifecycle_status', replay_conflict.proposed_lifecycle_status,
        'follow_up_note', replay_conflict.proposed_follow_up_note,
        'reason_code', replay_conflict.proposed_reason_code,
        'reason_detail', replay_conflict.proposed_reason_detail
      )
    );
    RETURN;
  END IF;

  SELECT relationship_row.* INTO STRICT current_row
  FROM app_data.promotion_target_project_relationships AS relationship_row
  WHERE relationship_row.promotion_target_id = requested_target_id
    AND relationship_row.project_id = trusted_project_id
  FOR UPDATE;

  IF requested_resolved_conflict_id IS NOT NULL THEN
    SELECT conflict_row.* INTO resolved_conflict
    FROM app_data.promotion_target_relationship_conflicts AS conflict_row
    WHERE conflict_row.conflict_id = requested_resolved_conflict_id
      AND conflict_row.promotion_target_id = requested_target_id
      AND conflict_row.project_id = trusted_project_id
      AND NOT EXISTS (
        SELECT 1
        FROM app_data.promotion_target_relationship_conflict_resolutions
          AS resolution_row
        WHERE resolution_row.conflict_id = conflict_row.conflict_id
      );
    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'relationship conflict is missing or already resolved';
    END IF;
  END IF;

  IF expected_revision > current_row.current_revision THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'relationship expected revision is ahead of current';
  END IF;

  IF expected_revision < current_row.current_revision THEN
    SELECT revision_row.* INTO base_row
    FROM app_data.promotion_target_relationship_revisions AS revision_row
    WHERE revision_row.promotion_target_id = requested_target_id
      AND revision_row.project_id = trusted_project_id
      AND revision_row.revision_number = expected_revision;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'relationship base revision is unavailable';
    END IF;

    IF requested_stage < base_row.new_stage
      AND requested_reason_code NOT IN (
        'contact_lost',
        'timing_changed',
        'requirements_changed',
        'target_request',
        'project_change',
        'correction',
        'other'
      )
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'relationship stage decrease requires a structured reason';
    END IF;

    IF base_row.new_stage <> requested_stage THEN
      proposed_fields := array_append(proposed_fields, 'stage');
    END IF;
    IF base_row.new_lifecycle_status <> requested_lifecycle_status THEN
      proposed_fields := array_append(proposed_fields, 'lifecycle_status');
    END IF;
    IF base_row.follow_up_note IS DISTINCT FROM normalized_note THEN
      proposed_fields := array_append(proposed_fields, 'follow_up_note');
    END IF;
    IF base_row.new_stage <> current_row.current_stage THEN
      server_fields := array_append(server_fields, 'stage');
    END IF;
    IF base_row.new_lifecycle_status <>
      current_row.current_lifecycle_status
    THEN
      server_fields := array_append(server_fields, 'lifecycle_status');
    END IF;
    IF base_row.follow_up_note IS DISTINCT FROM
      current_row.current_follow_up_note
    THEN
      server_fields := array_append(server_fields, 'follow_up_note');
    END IF;
    SELECT COALESCE(array_agg(field_name), ARRAY[]::text[])
      INTO conflicting_fields_value
    FROM unnest(proposed_fields) AS proposed(field_name)
    WHERE field_name = ANY(server_fields);

    IF cardinality(conflicting_fields_value) > 0 THEN
      INSERT INTO app_data.promotion_target_relationship_conflicts (
        promotion_target_id,
        project_id,
        base_revision,
        current_revision,
        proposed_stage,
        proposed_lifecycle_status,
        proposed_follow_up_note,
        proposed_reason_code,
        proposed_reason_detail,
        conflicting_fields,
        created_by_app_user_id,
        mutation_id
      ) VALUES (
        requested_target_id,
        trusted_project_id,
        expected_revision,
        current_row.current_revision,
        requested_stage,
        requested_lifecycle_status,
        normalized_note,
        requested_reason_code,
        normalized_detail,
        conflicting_fields_value,
        trusted_app_user_id,
        normalized_mutation_id
      ) RETURNING conflict_id INTO conflict_id_value;
      RETURN QUERY SELECT jsonb_build_object(
        'status', 'conflict',
        'conflict_id', conflict_id_value,
        'conflicting_fields', conflicting_fields_value,
        'current', app_data.promotion_target_relationship_document(
          requested_target_id,
          trusted_project_id,
          true
        ),
        'proposed', jsonb_build_object(
          'expected_revision', expected_revision,
          'stage', requested_stage,
          'display_stage', requested_stage * 2,
          'lifecycle_status', requested_lifecycle_status,
          'follow_up_note', normalized_note,
          'reason_code', requested_reason_code,
          'reason_detail', normalized_detail
        )
      );
      RETURN;
    END IF;

    effective_stage := CASE WHEN 'stage' = ANY(proposed_fields)
      THEN requested_stage ELSE current_row.current_stage END;
    effective_lifecycle_status := CASE
      WHEN 'lifecycle_status' = ANY(proposed_fields)
      THEN requested_lifecycle_status
      ELSE current_row.current_lifecycle_status
    END;
    effective_note := CASE WHEN 'follow_up_note' = ANY(proposed_fields)
      THEN normalized_note ELSE current_row.current_follow_up_note END;
  ELSE
    effective_stage := requested_stage;
    effective_lifecycle_status := requested_lifecycle_status;
    effective_note := normalized_note;
  END IF;

  IF current_row.current_stage <> effective_stage THEN
    changed_fields_value := array_append(changed_fields_value, 'stage');
  END IF;
  IF current_row.current_lifecycle_status <> effective_lifecycle_status THEN
    changed_fields_value := array_append(
      changed_fields_value,
      'lifecycle_status'
    );
  END IF;
  IF current_row.current_follow_up_note IS DISTINCT FROM effective_note THEN
    changed_fields_value := array_append(
      changed_fields_value,
      'follow_up_note'
    );
  END IF;

  IF requested_resolved_conflict_id IS NOT NULL THEN
    changed_fields_value := array_append(
      changed_fields_value,
      'conflict_resolution'
    );
  ELSIF cardinality(changed_fields_value) = 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'promotion target relationship update has no changes';
  END IF;

  IF effective_stage < current_row.current_stage
    AND requested_reason_code NOT IN (
      'contact_lost',
      'timing_changed',
      'requirements_changed',
      'target_request',
      'project_change',
      'correction',
      'other'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'relationship stage decrease requires a structured reason';
  END IF;

  next_revision := current_row.current_revision + 1;
  UPDATE app_data.promotion_target_project_relationships
  SET current_stage = effective_stage,
      current_lifecycle_status = effective_lifecycle_status,
      current_follow_up_note = effective_note,
      current_revision = next_revision,
      updated_by_app_user_id = trusted_app_user_id,
      updated_at = clock_timestamp()
  WHERE promotion_target_id = requested_target_id
    AND project_id = trusted_project_id;

  INSERT INTO app_data.promotion_target_relationship_revisions (
    promotion_target_id,
    project_id,
    revision_number,
    old_stage,
    new_stage,
    old_lifecycle_status,
    new_lifecycle_status,
    follow_up_note,
    changed_fields,
    reason_code,
    reason_detail,
    changed_by_app_user_id,
    mutation_id,
    requested_base_revision,
    requested_stage,
    requested_lifecycle_status,
    requested_follow_up_note,
    resolved_conflict_id
  ) VALUES (
    requested_target_id,
    trusted_project_id,
    next_revision,
    current_row.current_stage,
    effective_stage,
    current_row.current_lifecycle_status,
    effective_lifecycle_status,
    effective_note,
    changed_fields_value,
    requested_reason_code,
    normalized_detail,
    trusted_app_user_id,
    normalized_mutation_id,
    expected_revision,
    requested_stage,
    requested_lifecycle_status,
    normalized_note,
    requested_resolved_conflict_id
  );

  IF requested_resolved_conflict_id IS NOT NULL THEN
    resolution_choice_value := CASE
      WHEN effective_stage = current_row.current_stage
        AND effective_lifecycle_status = current_row.current_lifecycle_status
        AND effective_note IS NOT DISTINCT FROM
          current_row.current_follow_up_note
        THEN 'keep_current'
      WHEN effective_stage = resolved_conflict.proposed_stage
        AND effective_lifecycle_status =
          resolved_conflict.proposed_lifecycle_status
        AND effective_note IS NOT DISTINCT FROM
          resolved_conflict.proposed_follow_up_note
        THEN 'apply_proposed'
      ELSE 'custom'
    END;
    INSERT INTO app_data.promotion_target_relationship_conflict_resolutions (
      conflict_id,
      resolved_by_app_user_id,
      resolved_revision,
      resolution_choice
    ) VALUES (
      requested_resolved_conflict_id,
      trusted_app_user_id,
      next_revision,
      resolution_choice_value
    );
  END IF;

  RETURN QUERY SELECT jsonb_build_object(
    'status', 'accepted',
    'duplicate', false,
    'accepted_revision', next_revision,
    'relationship', app_data.promotion_target_relationship_document(
      requested_target_id,
      trusted_project_id,
      true
    )
  );
END
$function$;

CREATE FUNCTION app_data.configure_promotion_target_stage_aliases(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_aliases jsonb
)
RETURNS TABLE (aliases jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  alias_entry jsonb;
  stage_value integer;
  display_name_value text;
  seen_stages integer[] := ARRAY[]::integer[];
BEGIN
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target stage alias access is forbidden';
  END IF;
  IF jsonb_typeof(requested_aliases) <> 'array'
    OR jsonb_array_length(requested_aliases) <> 5
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'stage aliases must contain stages 0 through 4';
  END IF;

  FOR alias_entry IN SELECT value FROM jsonb_array_elements(requested_aliases)
  LOOP
    IF jsonb_typeof(alias_entry) <> 'object'
      OR NOT (alias_entry ? 'stage')
      OR NOT (alias_entry ? 'display_name')
      OR (SELECT count(*) FROM jsonb_object_keys(alias_entry)) <> 2
      OR (alias_entry->>'stage') !~ '^[0-4]$'
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid stage alias';
    END IF;
    stage_value := (alias_entry->>'stage')::integer;
    IF stage_value = ANY(seen_stages) THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'duplicate stage alias';
    END IF;
    seen_stages := array_append(seen_stages, stage_value);
    display_name_value := CASE
      WHEN jsonb_typeof(alias_entry->'display_name') = 'null' THEN NULL
      ELSE btrim(alias_entry->>'display_name')
    END;
    IF display_name_value IS NOT NULL
      AND length(display_name_value) NOT BETWEEN 1 AND 80
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid stage alias display name';
    END IF;

    IF display_name_value IS NULL THEN
      DELETE FROM app_data.promotion_target_stage_aliases
      WHERE project_id = trusted_project_id AND stage = stage_value;
    ELSE
      INSERT INTO app_data.promotion_target_stage_aliases (
        project_id,
        stage,
        display_name,
        updated_by_app_user_id
      ) VALUES (
        trusted_project_id,
        stage_value,
        display_name_value,
        trusted_app_user_id
      )
      ON CONFLICT (project_id, stage) DO UPDATE
      SET display_name = EXCLUDED.display_name,
          updated_by_app_user_id = EXCLUDED.updated_by_app_user_id,
          updated_at = clock_timestamp();
    END IF;
  END LOOP;

  RETURN QUERY SELECT app_data.promotion_target_stage_aliases_document(
    trusted_project_id
  );
END
$function$;

-- 修改跟进关系是独立能力；查看分配对象并不自动授予写权限。
CREATE OR REPLACE FUNCTION app_data.list_personal_project_contexts(
  trusted_issuer text,
  trusted_subject text
)
RETURNS TABLE (
  app_user_id uuid,
  workspace_id uuid,
  workspace_kind text,
  workspace_name text,
  project_id uuid,
  project_name text,
  questionnaire_version_id uuid,
  questionnaire_version_number integer,
  capabilities text[],
  is_current boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  resolved_project_id uuid;
BEGIN
  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = identity_row.app_user_id
   AND user_row.status = 'active'
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject;
  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'trusted identity is not mapped to an active app user';
  END IF;
  SELECT workspace_row.workspace_id INTO STRICT resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = resolved_app_user_id
    AND workspace_row.deleted_at IS NULL;
  SELECT current_row.project_id INTO resolved_project_id
  FROM app_data.user_current_projects AS current_row
  JOIN app_data.projects AS project_row
    ON project_row.project_id = current_row.project_id
   AND project_row.workspace_id = resolved_workspace_id
   AND project_row.status = 'active'
  WHERE current_row.app_user_id = resolved_app_user_id;
  IF resolved_project_id IS NULL THEN
    SELECT project_row.project_id INTO STRICT resolved_project_id
    FROM app_data.projects AS project_row
    WHERE project_row.workspace_id = resolved_workspace_id
      AND project_row.is_personal_default
      AND project_row.status = 'active';
    INSERT INTO app_data.user_current_projects (app_user_id, project_id)
    VALUES (resolved_app_user_id, resolved_project_id)
    ON CONFLICT ON CONSTRAINT user_current_projects_pkey DO UPDATE
      SET project_id = EXCLUDED.project_id,
          updated_at = clock_timestamp();
  END IF;
  RETURN QUERY
  SELECT
    resolved_app_user_id,
    workspace_row.workspace_id,
    workspace_row.workspace_kind,
    workspace_row.display_name,
    project_row.project_id,
    project_row.display_name,
    version_row.questionnaire_version_id,
    version_row.version_number,
    ARRAY[
      'record_contact',
      'manage_analysis_definitions',
      'create_target',
      'view_assigned_target_pii',
      'manage_assigned_target_follow_up'
    ]::text[],
    project_row.project_id = resolved_project_id
  FROM app_data.workspaces AS workspace_row
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
   AND project_row.status = 'active'
  JOIN app_data.questionnaire_versions AS version_row
    ON version_row.project_id = project_row.project_id
   AND version_row.is_current
   AND version_row.status = 'published'
  WHERE workspace_row.workspace_id = resolved_workspace_id
  ORDER BY
    (project_row.project_id = resolved_project_id) DESC,
    project_row.is_personal_default DESC,
    project_row.created_at,
    project_row.project_id;
END
$function$;

CREATE OR REPLACE FUNCTION app_data.list_assigned_promotion_targets(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (target jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
BEGIN
  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'promotion target access is forbidden';
  END IF;
  INSERT INTO app_data.promotion_target_access_events (
    workspace_id, promotion_target_id, actor_app_user_id, action
  )
  SELECT
    trusted_workspace_id,
    target_row.promotion_target_id,
    trusted_app_user_id,
    'viewed'
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active';
  RETURN QUERY
  SELECT app_data.promotion_target_document(target_row.promotion_target_id)
    || jsonb_build_object(
      'has_current_project_relationship',
        relationship_row.promotion_target_id IS NOT NULL,
      'project_relationship', CASE
        WHEN relationship_row.promotion_target_id IS NULL THEN NULL
        ELSE app_data.promotion_target_relationship_document(
          target_row.promotion_target_id,
          trusted_project_id,
          true
        )
      END
    )
  FROM app_data.promotion_targets AS target_row
  JOIN app_data.promotion_target_assignments AS assignment_row
    ON assignment_row.promotion_target_id = target_row.promotion_target_id
   AND assignment_row.app_user_id = trusted_app_user_id
   AND assignment_row.ended_at IS NULL
  LEFT JOIN app_data.promotion_target_project_relationships AS relationship_row
    ON relationship_row.promotion_target_id = target_row.promotion_target_id
   AND relationship_row.project_id = trusted_project_id
  WHERE target_row.workspace_id = trusted_workspace_id
    AND target_row.status = 'active'
  ORDER BY target_row.created_at DESC, target_row.promotion_target_id;
END
$function$;

REVOKE ALL ON FUNCTION
  app_data.prepare_initial_promotion_target_relationship(),
  app_data.install_initial_promotion_target_relationship_revision(),
  app_data.reject_promotion_target_relationship_revision_mutation(),
  app_data.promotion_target_stage_aliases_document(uuid),
  app_data.promotion_target_relationship_document(uuid, uuid, boolean),
  app_data.promotion_target_relationship_authorized(uuid, uuid, uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL ON FUNCTION
  app_data.update_promotion_target_relationship(
    uuid, uuid, uuid, uuid, integer, integer, text, text, text, text, text,
    uuid
  ),
  app_data.configure_promotion_target_stage_aliases(uuid, uuid, uuid, jsonb)
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.update_promotion_target_relationship(
    uuid, uuid, uuid, uuid, integer, integer, text, text, text, text, text,
    uuid
  ),
  app_data.configure_promotion_target_stage_aliases(uuid, uuid, uuid, jsonb)
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.promotion_target_relationship_revisions IS
  'Append-only relationship stage, lifecycle, and shared follow-up note history.';
COMMENT ON TABLE app_data.promotion_target_relationship_conflicts IS
  'Sensitive same-field proposals retained for explicit assignee resolution.';
COMMENT ON TABLE app_data.promotion_target_stage_aliases IS
  'Project display aliases only; stored stage semantics and ordering stay fixed.';
