-- Keep merge generations private and bind every new contact/project fact to
-- the active generation while serializing activation with the fact writers.

CREATE TABLE app_private.personal_target_merge_generation_fence_v1 (
  fence_key boolean PRIMARY KEY DEFAULT true CHECK (fence_key),
  epoch bigint NOT NULL DEFAULT 0 CHECK (epoch >= 0)
);

INSERT INTO app_private.personal_target_merge_generation_fence_v1 (fence_key)
VALUES (true);

CREATE TABLE app_private.personal_target_merge_generations_v1 (
  generation_id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  target_type text NOT NULL CHECK (target_type IN ('person', 'institution')),
  created_by_app_user_id uuid NOT NULL,
  activated_at_utc timestamptz NOT NULL CHECK (isfinite(activated_at_utc)),
  UNIQUE (generation_id, workspace_id, target_type)
);

CREATE TABLE app_private.personal_target_merge_generation_members_v1 (
  generation_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  target_type text NOT NULL,
  promotion_target_id uuid NOT NULL,
  PRIMARY KEY (generation_id, promotion_target_id),
  UNIQUE (generation_id, workspace_id, target_type, promotion_target_id),
  FOREIGN KEY (generation_id, workspace_id, target_type)
    REFERENCES app_private.personal_target_merge_generations_v1 (
      generation_id, workspace_id, target_type
    ) ON DELETE RESTRICT
);

CREATE TABLE app_private.personal_target_merge_active_members_v1 (
  promotion_target_id uuid PRIMARY KEY,
  generation_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  target_type text NOT NULL,
  FOREIGN KEY (
    generation_id, workspace_id, target_type, promotion_target_id
  ) REFERENCES app_private.personal_target_merge_generation_members_v1 (
    generation_id, workspace_id, target_type, promotion_target_id
  ) ON DELETE RESTRICT
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.personal_target_merge_generation_fence_v1,
  app_private.personal_target_merge_generations_v1,
  app_private.personal_target_merge_generation_members_v1,
  app_private.personal_target_merge_active_members_v1
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.reject_personal_target_merge_history_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'personal target merge generation history is append-only';
END
$function$;

CREATE TRIGGER personal_target_merge_generations_immutable
BEFORE UPDATE OR DELETE ON app_private.personal_target_merge_generations_v1
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_history_mutation_v1();

CREATE TRIGGER personal_target_merge_generation_members_immutable
BEFORE UPDATE OR DELETE
ON app_private.personal_target_merge_generation_members_v1
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_history_mutation_v1();

CREATE FUNCTION app_private.resolve_personal_target_merge_generation_v1(
  requested_target_id uuid,
  requested_workspace_id uuid,
  requested_target_type text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_private
AS $function$
DECLARE
  active_member app_private.personal_target_merge_active_members_v1%ROWTYPE;
  active_member_count integer;
BEGIN
  -- ponytail: one global fence serializes these writers; split by workspace
  -- only if measured contention makes this row a throughput limit.
  UPDATE app_private.personal_target_merge_generation_fence_v1
  SET epoch = epoch + 1
  WHERE fence_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation fence is unavailable';
  END IF;

  SELECT active_row.* INTO active_member
  FROM app_private.personal_target_merge_active_members_v1 AS active_row
  WHERE active_row.promotion_target_id = requested_target_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF active_member.workspace_id <> requested_workspace_id
    OR active_member.target_type <> requested_target_type
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'personal target merge generation is inconsistent';
  END IF;

  SELECT count(*) INTO active_member_count
  FROM app_private.personal_target_merge_active_members_v1 AS active_row
  WHERE active_row.generation_id = active_member.generation_id;
  IF active_member_count <> 2 THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'personal target merge generation is incomplete';
  END IF;

  RETURN active_member.generation_id;
END
$function$;

CREATE FUNCTION app_private.bind_personal_target_merge_generation_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  target_workspace_id uuid;
  target_type_value text;
BEGIN
  IF NEW.merge_generation_id IS NOT NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'merge generation is database assigned';
  END IF;

  SELECT target_row.workspace_id, target_row.target_type
    INTO target_workspace_id, target_type_value
  FROM app_data.promotion_targets AS target_row
  WHERE target_row.promotion_target_id = NEW.promotion_target_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  NEW.merge_generation_id :=
    app_private.resolve_personal_target_merge_generation_v1(
      NEW.promotion_target_id,
      target_workspace_id,
      target_type_value
    );
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.reject_personal_target_merge_generation_change_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NEW.merge_generation_id IS DISTINCT FROM OLD.merge_generation_id THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'merge generation is database assigned';
  END IF;
  RETURN NEW;
END
$function$;

ALTER TABLE app_data.contact_target_links
  ADD COLUMN merge_generation_id uuid,
  ADD CONSTRAINT contact_target_links_merge_generation_member_fk
    FOREIGN KEY (merge_generation_id, promotion_target_id)
    REFERENCES app_private.personal_target_merge_generation_members_v1 (
      generation_id, promotion_target_id
    ) ON DELETE RESTRICT;

ALTER TABLE app_data.promotion_target_project_relationships
  ADD COLUMN merge_generation_id uuid,
  ADD CONSTRAINT pt_rel_merge_gen_member_fk
    FOREIGN KEY (merge_generation_id, promotion_target_id)
    REFERENCES app_private.personal_target_merge_generation_members_v1 (
      generation_id, promotion_target_id
    ) ON DELETE RESTRICT;

ALTER TABLE app_data.promotion_target_relationship_revisions
  ADD COLUMN merge_generation_id uuid,
  ADD CONSTRAINT ptr_rev_merge_gen_member_fk
    FOREIGN KEY (merge_generation_id, promotion_target_id)
    REFERENCES app_private.personal_target_merge_generation_members_v1 (
      generation_id, promotion_target_id
    ) ON DELETE RESTRICT;

CREATE TRIGGER contact_target_links_bind_merge_generation
BEFORE INSERT ON app_data.contact_target_links
FOR EACH ROW EXECUTE FUNCTION
  app_private.bind_personal_target_merge_generation_v1();

CREATE TRIGGER promotion_target_project_relationships_bind_merge_generation
BEFORE INSERT ON app_data.promotion_target_project_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_private.bind_personal_target_merge_generation_v1();

CREATE TRIGGER promotion_target_relationship_revisions_bind_merge_generation
BEFORE INSERT ON app_data.promotion_target_relationship_revisions
FOR EACH ROW EXECUTE FUNCTION
  app_private.bind_personal_target_merge_generation_v1();

CREATE TRIGGER contact_target_links_merge_generation_immutable
BEFORE UPDATE OF merge_generation_id ON app_data.contact_target_links
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_generation_change_v1();

CREATE TRIGGER pt_rel_merge_gen_immutable
BEFORE UPDATE OF merge_generation_id
ON app_data.promotion_target_project_relationships
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_generation_change_v1();

CREATE TRIGGER ptr_rev_merge_gen_immutable
BEFORE UPDATE OF merge_generation_id
ON app_data.promotion_target_relationship_revisions
FOR EACH ROW EXECUTE FUNCTION
  app_private.reject_personal_target_merge_generation_change_v1();

CREATE FUNCTION app_private.activate_personal_target_merge_generation_v1(
  trusted_app_user_id uuid,
  requested_project_id uuid,
  requested_preview_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data, app_private
AS $function$
DECLARE
  created_generation_id uuid;
BEGIN
  -- The same row is updated by all three fact-binding triggers. Under
  -- REPEATABLE READ, a stale waiter fails with serialization error instead
  -- of committing a fact from an obsolete snapshot without a generation.
  UPDATE app_private.personal_target_merge_generation_fence_v1
  SET epoch = epoch + 1
  WHERE fence_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'personal target merge generation fence is unavailable';
  END IF;

  PERFORM 1
  FROM app_private.personal_target_pair_preview_receipts AS receipt
  WHERE receipt.preview_id = requested_preview_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target merge generation activation is forbidden';
  END IF;

  WITH timing AS MATERIALIZED (
    SELECT pg_catalog.clock_timestamp() AS activated_at_utc
  ),
  validated AS MATERIALIZED (
    SELECT
      receipt.*,
      first_target.target_type,
      timing.activated_at_utc
    FROM timing
    CROSS JOIN LATERAL
      app_private.validate_personal_target_pair_preview_v1(
        trusted_app_user_id,
        requested_project_id,
        requested_preview_id,
        timing.activated_at_utc
      ) AS receipt
    JOIN app_data.promotion_targets AS first_target
      ON first_target.promotion_target_id = receipt.first_target_id
     AND first_target.workspace_id = receipt.workspace_id
    JOIN app_data.promotion_targets AS second_target
      ON second_target.promotion_target_id = receipt.second_target_id
     AND second_target.workspace_id = receipt.workspace_id
     AND second_target.target_type = first_target.target_type
  ),
  eligible AS MATERIALIZED (
    SELECT validated.*
    FROM validated
    WHERE NOT EXISTS (
      SELECT 1
      FROM app_private.personal_target_merge_active_members_v1 AS active_row
      WHERE active_row.promotion_target_id IN (
        validated.first_target_id,
        validated.second_target_id
      )
    )
  ),
  created AS (
    INSERT INTO app_private.personal_target_merge_generations_v1 (
      generation_id,
      workspace_id,
      target_type,
      created_by_app_user_id,
      activated_at_utc
    )
    SELECT
      pg_catalog.gen_random_uuid(),
      eligible.workspace_id,
      eligible.target_type,
      trusted_app_user_id,
      eligible.activated_at_utc
    FROM eligible
    RETURNING generation_id, workspace_id, target_type
  ),
  members AS (
    INSERT INTO app_private.personal_target_merge_generation_members_v1 (
      generation_id,
      workspace_id,
      target_type,
      promotion_target_id
    )
    SELECT
      created.generation_id,
      created.workspace_id,
      created.target_type,
      target_id.promotion_target_id
    FROM created
    JOIN eligible USING (workspace_id, target_type)
    CROSS JOIN LATERAL (
      VALUES (eligible.first_target_id), (eligible.second_target_id)
    ) AS target_id(promotion_target_id)
    RETURNING generation_id, workspace_id, target_type, promotion_target_id
  ),
  active_members AS (
    INSERT INTO app_private.personal_target_merge_active_members_v1 (
      promotion_target_id,
      generation_id,
      workspace_id,
      target_type
    )
    SELECT
      promotion_target_id,
      generation_id,
      workspace_id,
      target_type
    FROM members
    RETURNING promotion_target_id
  )
  SELECT created.generation_id INTO created_generation_id
  FROM created
  CROSS JOIN (SELECT count(*) AS member_count FROM members) AS member_count
  CROSS JOIN (
    SELECT count(*) AS active_member_count FROM active_members
  ) AS active_member_count
  WHERE member_count.member_count = 2
    AND active_member_count.active_member_count = 2;

  IF created_generation_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal target merge generation activation is forbidden';
  END IF;
  RETURN created_generation_id;
END
$function$;

REVOKE ALL ON FUNCTION
  app_private.reject_personal_target_merge_history_mutation_v1(),
  app_private.resolve_personal_target_merge_generation_v1(uuid, uuid, text),
  app_private.bind_personal_target_merge_generation_v1(),
  app_private.reject_personal_target_merge_generation_change_v1(),
  app_private.activate_personal_target_merge_generation_v1(uuid, uuid, uuid)
  FROM PUBLIC, tongxingzhe_runtime;

DO $owner$
DECLARE
  trusted_owner text;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(function_row.proowner)
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS function_row
  WHERE function_row.oid =
    'app_private.validate_organization_membership_v1()'::regprocedure;

  EXECUTE format(
    'ALTER TABLE app_private.personal_target_merge_generation_fence_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_merge_generations_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_merge_generation_members_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.personal_target_merge_active_members_v1 OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.reject_personal_target_merge_history_mutation_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.resolve_personal_target_merge_generation_v1(uuid,uuid,text) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.bind_personal_target_merge_generation_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.reject_personal_target_merge_generation_change_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.activate_personal_target_merge_generation_v1(uuid,uuid,uuid) OWNER TO %I',
    trusted_owner
  );
END
$owner$;
