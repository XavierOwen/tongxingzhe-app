-- 0019_person_institution_relationships.sql
--
-- 个人与机构的关系属于 workspace，不属于推广项目。关系只连接明确选择的
-- 两个对象；它不授予对象访问权，不建立 App 成员资格，也不自动关联接触。

CREATE TABLE app_data.promotion_target_institution_relationships (
  relationship_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  person_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  institution_target_id uuid NOT NULL
    REFERENCES app_data.promotion_targets (promotion_target_id)
    ON DELETE RESTRICT,
  relationship_kind text NOT NULL CHECK (
    relationship_kind IN (
      'employment_representative',
      'ownership_governance',
      'learning_participation',
      'membership_affiliation',
      'partnership_service',
      'other'
    )
  ),
  role_description text CHECK (
    role_description IS NULL
    OR length(btrim(role_description)) BETWEEN 1 AND 500
  ),
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  current_revision integer NOT NULL DEFAULT 1
    CHECK (current_revision > 0),
  created_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (person_target_id <> institution_target_id),
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  CHECK (relationship_kind <> 'other' OR role_description IS NOT NULL)
);

CREATE UNIQUE INDEX promotion_target_one_active_institution_relation_kind
  ON app_data.promotion_target_institution_relationships (
    workspace_id,
    person_target_id,
    institution_target_id,
    relationship_kind
  ) WHERE ended_at IS NULL;

CREATE INDEX promotion_target_institution_relations_person
  ON app_data.promotion_target_institution_relationships (
    workspace_id,
    person_target_id,
    started_at DESC
  );

CREATE INDEX promotion_target_institution_relations_institution
  ON app_data.promotion_target_institution_relationships (
    workspace_id,
    institution_target_id,
    started_at DESC
  );

CREATE TABLE app_data.promotion_target_institution_relation_revisions (
  relationship_id uuid NOT NULL
    REFERENCES app_data.promotion_target_institution_relationships (
      relationship_id
    ) ON DELETE RESTRICT,
  revision_number integer NOT NULL CHECK (revision_number > 0),
  event_type text NOT NULL CHECK (event_type IN ('created', 'ended')),
  old_status text CHECK (old_status IN ('active', 'ended')),
  new_status text NOT NULL CHECK (new_status IN ('active', 'ended')),
  ended_at timestamptz,
  changed_by_app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  mutation_id text NOT NULL CHECK (
    length(btrim(mutation_id)) BETWEEN 1 AND 120
  ),
  requested_base_revision integer CHECK (requested_base_revision > 0),
  PRIMARY KEY (relationship_id, revision_number),
  CHECK (
    (revision_number = 1
      AND event_type = 'created'
      AND old_status IS NULL
      AND new_status = 'active'
      AND ended_at IS NULL
      AND requested_base_revision IS NULL)
    OR
    (revision_number > 1
      AND event_type = 'ended'
      AND old_status = 'active'
      AND new_status = 'ended'
      AND ended_at IS NOT NULL
      AND requested_base_revision IS NOT NULL)
  )
);

CREATE UNIQUE INDEX promotion_target_institution_relation_mutation_once
  ON app_data.promotion_target_institution_relation_revisions (
    changed_by_app_user_id,
    mutation_id
  );

REVOKE ALL PRIVILEGES
  ON app_data.promotion_target_institution_relationships,
     app_data.promotion_target_institution_relation_revisions
  FROM tongxingzhe_runtime;

CREATE FUNCTION app_data.validate_promotion_target_institution_relation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  person_row app_data.promotion_targets%ROWTYPE;
  institution_row app_data.promotion_targets%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'promotion target institution relationships are historical';
  END IF;

  SELECT target_row.* INTO person_row
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.person_target_id;
  SELECT target_row.* INTO institution_row
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.institution_target_id;

  IF person_row.promotion_target_id IS NULL
    OR person_row.workspace_id <> NEW.workspace_id
    OR person_row.target_type <> 'person'
    OR person_row.status <> 'active'
    OR institution_row.promotion_target_id IS NULL
    OR institution_row.workspace_id <> NEW.workspace_id
    OR institution_row.target_type <> 'institution'
    OR institution_row.status <> 'active'
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'institution relationship endpoints are invalid';
  END IF;

  IF TG_OP = 'UPDATE' AND (
    OLD.workspace_id <> NEW.workspace_id
    OR OLD.person_target_id <> NEW.person_target_id
    OR OLD.institution_target_id <> NEW.institution_target_id
    OR OLD.relationship_kind <> NEW.relationship_kind
    OR OLD.role_description IS DISTINCT FROM NEW.role_description
    OR OLD.started_at <> NEW.started_at
    OR OLD.created_by_app_user_id <> NEW.created_by_app_user_id
    OR OLD.created_at <> NEW.created_at
    OR OLD.ended_at IS NOT NULL
    OR NEW.ended_at IS NULL
    OR NEW.current_revision <> OLD.current_revision + 1
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'institution relationship history cannot be rewritten';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER promotion_target_institution_relation_valid
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.promotion_target_institution_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_data.validate_promotion_target_institution_relation();

CREATE TRIGGER promotion_target_institution_relation_revisions_immutable
BEFORE UPDATE OR DELETE
ON app_data.promotion_target_institution_relation_revisions
FOR EACH ROW EXECUTE FUNCTION
  app_data.reject_promotion_target_relationship_revision_mutation();

CREATE FUNCTION app_data.promotion_target_pair_authorized(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_person_target_id uuid,
  requested_institution_target_id uuid
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
      FROM app_data.promotion_targets AS person_row
      JOIN app_data.promotion_target_assignments AS person_assignment
        ON person_assignment.promotion_target_id =
          person_row.promotion_target_id
       AND person_assignment.app_user_id = trusted_app_user_id
       AND person_assignment.ended_at IS NULL
      JOIN app_data.promotion_targets AS institution_row
        ON institution_row.promotion_target_id =
          requested_institution_target_id
       AND institution_row.workspace_id = trusted_workspace_id
       AND institution_row.target_type = 'institution'
       AND institution_row.status = 'active'
      JOIN app_data.promotion_target_assignments AS institution_assignment
        ON institution_assignment.promotion_target_id =
          institution_row.promotion_target_id
       AND institution_assignment.app_user_id = trusted_app_user_id
       AND institution_assignment.ended_at IS NULL
      WHERE person_row.promotion_target_id = requested_person_target_id
        AND person_row.workspace_id = trusted_workspace_id
        AND person_row.target_type = 'person'
        AND person_row.status = 'active'
    );
$function$;

CREATE FUNCTION app_data.promotion_target_institution_relation_document(
  requested_relationship_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
  SELECT jsonb_build_object(
    'relationship_id', relationship_row.relationship_id,
    'person_target_id', relationship_row.person_target_id,
    'institution_target_id', relationship_row.institution_target_id,
    'relationship_kind', relationship_row.relationship_kind,
    'role_description', relationship_row.role_description,
    'started_at', relationship_row.started_at,
    'ended_at', relationship_row.ended_at,
    'status', CASE WHEN relationship_row.ended_at IS NULL
      THEN 'active' ELSE 'ended' END,
    'revision_number', relationship_row.current_revision,
    'history', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'revision_number', revision_row.revision_number,
          'event_type', revision_row.event_type,
          'old_status', revision_row.old_status,
          'new_status', revision_row.new_status,
          'ended_at', revision_row.ended_at,
          'changed_by_app_user_id', revision_row.changed_by_app_user_id,
          'changed_at', revision_row.changed_at
        ) ORDER BY revision_row.revision_number DESC
      )
      FROM app_data.promotion_target_institution_relation_revisions
        AS revision_row
      WHERE revision_row.relationship_id = relationship_row.relationship_id
    ), '[]'::jsonb)
  )
  FROM app_data.promotion_target_institution_relationships AS relationship_row
  WHERE relationship_row.relationship_id = requested_relationship_id;
$function$;

CREATE FUNCTION app_data.list_assigned_target_institution_relationships(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid
)
RETURNS TABLE (relationship jsonb)
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
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  RETURN QUERY
  SELECT app_data.promotion_target_institution_relation_document(
    relationship_row.relationship_id
  )
  FROM app_data.promotion_target_institution_relationships
    AS relationship_row
  JOIN app_data.promotion_target_assignments AS person_assignment
    ON person_assignment.promotion_target_id =
      relationship_row.person_target_id
   AND person_assignment.app_user_id = trusted_app_user_id
   AND person_assignment.ended_at IS NULL
  JOIN app_data.promotion_target_assignments AS institution_assignment
    ON institution_assignment.promotion_target_id =
      relationship_row.institution_target_id
   AND institution_assignment.app_user_id = trusted_app_user_id
   AND institution_assignment.ended_at IS NULL
  JOIN app_data.promotion_targets AS person_row
    ON person_row.promotion_target_id = relationship_row.person_target_id
   AND person_row.status = 'active'
  JOIN app_data.promotion_targets AS institution_row
    ON institution_row.promotion_target_id =
      relationship_row.institution_target_id
   AND institution_row.status = 'active'
  WHERE relationship_row.workspace_id = trusted_workspace_id
  ORDER BY
    (relationship_row.ended_at IS NULL) DESC,
    relationship_row.started_at DESC,
    relationship_row.relationship_id;
END
$function$;

CREATE FUNCTION app_data.create_target_institution_relationship(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_person_target_id uuid,
  requested_institution_target_id uuid,
  requested_relationship_kind text,
  requested_role_description text,
  requested_mutation_id text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_role text := CASE
    WHEN requested_role_description IS NULL
      OR btrim(requested_role_description) = '' THEN NULL
    ELSE btrim(requested_role_description)
  END;
  normalized_mutation_id text := btrim(requested_mutation_id);
  replay_revision app_data.promotion_target_institution_relation_revisions%ROWTYPE;
  replay_relationship app_data.promotion_target_institution_relationships%ROWTYPE;
  new_relationship_id uuid := gen_random_uuid();
  event_time timestamptz := clock_timestamp();
BEGIN
  IF requested_person_target_id IS NULL
    OR requested_institution_target_id IS NULL
    OR requested_relationship_kind IS NULL
    OR requested_mutation_id IS NULL
    OR requested_relationship_kind NOT IN (
      'employment_representative',
      'ownership_governance',
      'learning_participation',
      'membership_affiliation',
      'partnership_service',
      'other'
    )
    OR (normalized_role IS NOT NULL AND length(normalized_role) > 500)
    OR (requested_relationship_kind = 'other' AND normalized_role IS NULL)
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid institution relationship';
  END IF;

  IF NOT app_data.promotion_target_pair_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    requested_person_target_id,
    requested_institution_target_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || normalized_mutation_id,
    0
  ));

  SELECT revision_row.* INTO replay_revision
  FROM app_data.promotion_target_institution_relation_revisions
    AS revision_row
  WHERE revision_row.changed_by_app_user_id = trusted_app_user_id
    AND revision_row.mutation_id = normalized_mutation_id;

  IF FOUND THEN
    SELECT relationship_row.* INTO STRICT replay_relationship
    FROM app_data.promotion_target_institution_relationships
      AS relationship_row
    WHERE relationship_row.relationship_id =
      replay_revision.relationship_id;
    IF replay_revision.event_type <> 'created'
      OR replay_relationship.workspace_id <> trusted_workspace_id
      OR replay_relationship.person_target_id <>
        requested_person_target_id
      OR replay_relationship.institution_target_id <>
        requested_institution_target_id
      OR replay_relationship.relationship_kind <>
        requested_relationship_kind
      OR replay_relationship.role_description IS DISTINCT FROM normalized_role
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'institution relationship mutation was reused';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'duplicate', true,
      'relationship',
        app_data.promotion_target_institution_relation_document(
          replay_relationship.relationship_id
        )
    );
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_workspace_id::text || ':'
      || requested_person_target_id::text || ':'
      || requested_institution_target_id::text || ':'
      || requested_relationship_kind,
    0
  ));

  IF EXISTS (
    SELECT 1
    FROM app_data.promotion_target_institution_relationships
      AS relationship_row
    WHERE relationship_row.workspace_id = trusted_workspace_id
      AND relationship_row.person_target_id = requested_person_target_id
      AND relationship_row.institution_target_id =
        requested_institution_target_id
      AND relationship_row.relationship_kind =
        requested_relationship_kind
      AND relationship_row.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'active institution relationship already exists';
  END IF;

  INSERT INTO app_data.promotion_target_institution_relationships (
    relationship_id,
    workspace_id,
    person_target_id,
    institution_target_id,
    relationship_kind,
    role_description,
    started_at,
    created_by_app_user_id,
    created_at,
    updated_by_app_user_id,
    updated_at
  ) VALUES (
    new_relationship_id,
    trusted_workspace_id,
    requested_person_target_id,
    requested_institution_target_id,
    requested_relationship_kind,
    normalized_role,
    event_time,
    trusted_app_user_id,
    event_time,
    trusted_app_user_id,
    event_time
  );

  INSERT INTO app_data.promotion_target_institution_relation_revisions (
    relationship_id,
    revision_number,
    event_type,
    old_status,
    new_status,
    changed_by_app_user_id,
    changed_at,
    mutation_id
  ) VALUES (
    new_relationship_id,
    1,
    'created',
    NULL,
    'active',
    trusted_app_user_id,
    event_time,
    normalized_mutation_id
  );

  RETURN QUERY SELECT jsonb_build_object(
    'duplicate', false,
    'relationship',
      app_data.promotion_target_institution_relation_document(
        new_relationship_id
      )
  );
END
$function$;

CREATE FUNCTION app_data.end_target_institution_relationship(
  trusted_app_user_id uuid,
  trusted_workspace_id uuid,
  trusted_project_id uuid,
  requested_relationship_id uuid,
  requested_expected_revision integer,
  requested_mutation_id text
)
RETURNS TABLE (result jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  normalized_mutation_id text := btrim(requested_mutation_id);
  replay_revision app_data.promotion_target_institution_relation_revisions%ROWTYPE;
  replay_relationship app_data.promotion_target_institution_relationships%ROWTYPE;
  current_relationship app_data.promotion_target_institution_relationships%ROWTYPE;
  next_revision integer;
  event_time timestamptz := clock_timestamp();
BEGIN
  IF requested_relationship_id IS NULL
    OR requested_expected_revision IS NULL
    OR requested_expected_revision < 1
    OR requested_mutation_id IS NULL
    OR length(normalized_mutation_id) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid institution relationship end';
  END IF;

  IF NOT app_data.promotion_target_context_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  SELECT relationship_row.* INTO current_relationship
  FROM app_data.promotion_target_institution_relationships
    AS relationship_row
  WHERE relationship_row.relationship_id = requested_relationship_id
    AND relationship_row.workspace_id = trusted_workspace_id;
  IF NOT FOUND OR NOT app_data.promotion_target_pair_authorized(
    trusted_app_user_id,
    trusted_workspace_id,
    trusted_project_id,
    current_relationship.person_target_id,
    current_relationship.institution_target_id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'institution relationship access is forbidden';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    trusted_app_user_id::text || ':' || normalized_mutation_id,
    0
  ));

  SELECT revision_row.* INTO replay_revision
  FROM app_data.promotion_target_institution_relation_revisions
    AS revision_row
  WHERE revision_row.changed_by_app_user_id = trusted_app_user_id
    AND revision_row.mutation_id = normalized_mutation_id;
  IF FOUND THEN
    SELECT relationship_row.* INTO STRICT replay_relationship
    FROM app_data.promotion_target_institution_relationships
      AS relationship_row
    WHERE relationship_row.relationship_id =
      replay_revision.relationship_id;
    IF replay_revision.event_type <> 'ended'
      OR replay_relationship.relationship_id <>
        requested_relationship_id
      OR replay_revision.requested_base_revision <>
        requested_expected_revision
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'institution relationship mutation was reused';
    END IF;
    RETURN QUERY SELECT jsonb_build_object(
      'duplicate', true,
      'relationship',
        app_data.promotion_target_institution_relation_document(
          requested_relationship_id
        )
    );
    RETURN;
  END IF;

  SELECT relationship_row.* INTO STRICT current_relationship
  FROM app_data.promotion_target_institution_relationships
    AS relationship_row
  WHERE relationship_row.relationship_id = requested_relationship_id
    AND relationship_row.workspace_id = trusted_workspace_id
  FOR UPDATE;

  IF current_relationship.ended_at IS NOT NULL
    OR current_relationship.current_revision <>
      requested_expected_revision
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'institution relationship revision conflict';
  END IF;

  next_revision := current_relationship.current_revision + 1;
  UPDATE app_data.promotion_target_institution_relationships
  SET ended_at = event_time,
      current_revision = next_revision,
      updated_by_app_user_id = trusted_app_user_id,
      updated_at = event_time
  WHERE relationship_id = requested_relationship_id;

  INSERT INTO app_data.promotion_target_institution_relation_revisions (
    relationship_id,
    revision_number,
    event_type,
    old_status,
    new_status,
    ended_at,
    changed_by_app_user_id,
    changed_at,
    mutation_id,
    requested_base_revision
  ) VALUES (
    requested_relationship_id,
    next_revision,
    'ended',
    'active',
    'ended',
    event_time,
    trusted_app_user_id,
    event_time,
    normalized_mutation_id,
    requested_expected_revision
  );

  RETURN QUERY SELECT jsonb_build_object(
    'duplicate', false,
    'relationship',
      app_data.promotion_target_institution_relation_document(
        requested_relationship_id
      )
  );
END
$function$;

-- 个人空间当前提供关系管理能力；读取能力仍只取决于对象分配。
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
      'manage_assigned_target_follow_up',
      'manage_assigned_target_relations'
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

REVOKE ALL ON FUNCTION
  app_data.validate_promotion_target_institution_relation(),
  app_data.promotion_target_pair_authorized(uuid, uuid, uuid, uuid, uuid),
  app_data.promotion_target_institution_relation_document(uuid)
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL ON FUNCTION
  app_data.list_assigned_target_institution_relationships(uuid, uuid, uuid),
  app_data.create_target_institution_relationship(
    uuid, uuid, uuid, uuid, uuid, text, text, text
  ),
  app_data.end_target_institution_relationship(
    uuid, uuid, uuid, uuid, integer, text
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.list_assigned_target_institution_relationships(uuid, uuid, uuid),
  app_data.create_target_institution_relationship(
    uuid, uuid, uuid, uuid, uuid, text, text, text
  ),
  app_data.end_target_institution_relationship(
    uuid, uuid, uuid, uuid, integer, text
  )
  TO tongxingzhe_runtime;

COMMENT ON TABLE app_data.promotion_target_institution_relationships IS
  'Explicit workspace-scoped person-to-institution relationships.';
COMMENT ON TABLE app_data.promotion_target_institution_relation_revisions IS
  'Append-only creation and end history; it grants no target access.';
