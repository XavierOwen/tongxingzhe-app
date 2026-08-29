-- 0085_organization_owner_invariant.sql
--
-- Slice 7D7 closes the database owner invariant around the existing
-- organization workspace, membership, owner-assignment, and app-user rows.
-- It adds no business table and leaves physical purge as the only exception.

-- Do not guess an owner for data that predates this invariant.  This is the
-- first statement that can fail, so the migration runner rolls back without
-- leaving any 0085 object or migration record behind.
DO $preflight$
DECLARE
  reference_at_utc timestamp with time zone := pg_catalog.clock_timestamp();
BEGIN
  IF EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    WHERE workspace_row.workspace_kind = 'organization'
      AND NOT EXISTS (
        SELECT 1
        FROM app_data.organization_owner_assignments AS owner_assignment
        JOIN app_data.organization_memberships AS organization_membership
          ON organization_membership.organization_membership_id =
            owner_assignment.organization_membership_id
        JOIN app_data.app_users AS app_user
          ON app_user.app_user_id = organization_membership.app_user_id
        WHERE organization_membership.organization_workspace_id =
            workspace_row.workspace_id
          AND app_user.status = 'active'
          AND pg_catalog.tstzrange(
            organization_membership.active_from_utc,
            organization_membership.inactive_from_utc,
            '[)'
          ) @> reference_at_utc
          AND pg_catalog.tstzrange(
            owner_assignment.active_from_utc,
            owner_assignment.inactive_from_utc,
            '[)'
          ) @> reference_at_utc
      )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'organization must retain an active owner';
  END IF;
END
$preflight$;

CREATE FUNCTION app_private.lock_organization_governance_v1(
  requested_workspace_id uuid
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF requested_workspace_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-governance:' || requested_workspace_id::text,
      0
    )
  );
END
$function$;

CREATE FUNCTION app_private.lock_organization_governance_for_mutation_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  workspace_id uuid;
  new_workspace_id uuid;
  old_workspace_id uuid;
  new_app_user_id uuid;
  old_app_user_id uuid;
  new_membership_id uuid;
  old_membership_id uuid;
  affected_app_user_id uuid;
BEGIN
  IF TG_RELID = 'app_data.workspaces'::regclass THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.workspace_kind = 'organization' THEN
        PERFORM app_private.lock_organization_governance_v1(
          NEW.workspace_id
        );
      END IF;
    ELSIF TG_OP = 'UPDATE' THEN
      IF NEW.workspace_kind = 'organization'
        OR OLD.workspace_kind = 'organization'
      THEN
        PERFORM app_private.lock_organization_governance_v1(
          NEW.workspace_id
        );
      END IF;
    ELSE
      IF OLD.workspace_kind = 'organization' THEN
        PERFORM app_private.lock_organization_governance_v1(
          OLD.workspace_id
        );
      END IF;
    END IF;
  ELSIF TG_RELID = 'app_data.organization_memberships'::regclass THEN
    IF TG_OP = 'INSERT' THEN
      new_workspace_id := NEW.organization_workspace_id;
      new_app_user_id := NEW.app_user_id;
    ELSIF TG_OP = 'UPDATE' THEN
      new_workspace_id := NEW.organization_workspace_id;
      old_workspace_id := OLD.organization_workspace_id;
      new_app_user_id := NEW.app_user_id;
      old_app_user_id := OLD.app_user_id;
    ELSE
      old_workspace_id := OLD.organization_workspace_id;
      old_app_user_id := OLD.app_user_id;
    END IF;

    FOR affected_app_user_id IN
      SELECT DISTINCT app_user_key
      FROM (
        VALUES (new_app_user_id), (old_app_user_id)
      ) AS affected_app_users(app_user_key)
      WHERE app_user_key IS NOT NULL
      ORDER BY app_user_key
    LOOP
      PERFORM 1
      FROM app_data.app_users AS app_user
      WHERE app_user.app_user_id = affected_app_user_id
      FOR UPDATE;
    END LOOP;

    FOR workspace_id IN
      SELECT DISTINCT workspace_key
      FROM (
        VALUES (new_workspace_id), (old_workspace_id)
      ) AS affected_workspaces(workspace_key)
      WHERE workspace_key IS NOT NULL
      ORDER BY workspace_key
    LOOP
      PERFORM app_private.lock_organization_governance_v1(workspace_id);
    END LOOP;
  ELSIF TG_RELID = 'app_data.organization_owner_assignments'::regclass THEN
    IF TG_OP = 'INSERT' THEN
      new_membership_id := NEW.organization_membership_id;
    ELSIF TG_OP = 'UPDATE' THEN
      new_membership_id := NEW.organization_membership_id;
      old_membership_id := OLD.organization_membership_id;
    ELSE
      old_membership_id := OLD.organization_membership_id;
    END IF;

    FOR workspace_id IN
      SELECT DISTINCT organization_membership.organization_workspace_id
      FROM app_data.organization_memberships AS organization_membership
      WHERE organization_membership.organization_membership_id IN (
        new_membership_id,
        old_membership_id
      )
      ORDER BY organization_membership.organization_workspace_id
    LOOP
      PERFORM app_private.lock_organization_governance_v1(workspace_id);
    END LOOP;
  ELSIF TG_RELID = 'app_data.app_users'::regclass THEN
    IF TG_OP = 'UPDATE' THEN
      IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
      END IF;
      affected_app_user_id := NEW.app_user_id;
    ELSE
      affected_app_user_id := OLD.app_user_id;
    END IF;

    -- The row lock comes before any organization governance lock.  Every
    -- affected organization is then locked in UUID order.
    PERFORM 1
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = affected_app_user_id
    FOR UPDATE;

    FOR workspace_id IN
      SELECT DISTINCT organization_membership.organization_workspace_id
      FROM app_data.organization_memberships AS organization_membership
      WHERE organization_membership.app_user_id = affected_app_user_id
      ORDER BY organization_membership.organization_workspace_id
    LOOP
      PERFORM app_private.lock_organization_governance_v1(workspace_id);
    END LOOP;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.require_organization_active_owner_v1(
  requested_workspace_id uuid
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  reference_at_utc timestamp with time zone := pg_catalog.clock_timestamp();
BEGIN
  -- A physically purged workspace and a personal workspace are outside this
  -- invariant.  Soft-deleted organization workspaces remain in this branch.
  IF NOT EXISTS (
    SELECT 1
    FROM app_data.workspaces AS workspace_row
    WHERE workspace_row.workspace_id = requested_workspace_id
      AND workspace_row.workspace_kind = 'organization'
  ) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_data.organization_owner_assignments AS owner_assignment
    JOIN app_data.organization_memberships AS organization_membership
      ON organization_membership.organization_membership_id =
        owner_assignment.organization_membership_id
    JOIN app_data.app_users AS app_user
      ON app_user.app_user_id = organization_membership.app_user_id
    WHERE organization_membership.organization_workspace_id =
        requested_workspace_id
      AND app_user.status = 'active'
      AND pg_catalog.tstzrange(
        organization_membership.active_from_utc,
        organization_membership.inactive_from_utc,
        '[)'
      ) @> reference_at_utc
      AND pg_catalog.tstzrange(
        owner_assignment.active_from_utc,
        owner_assignment.inactive_from_utc,
        '[)'
      ) @> reference_at_utc
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'organization must retain an active owner';
  END IF;
END
$function$;

CREATE FUNCTION app_private.enforce_organization_active_owner_v1()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  workspace_id uuid;
  new_membership_id uuid;
  old_membership_id uuid;
  affected_app_user_id uuid;
BEGIN
  IF TG_RELID = 'app_data.workspaces'::regclass THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.workspace_kind = 'organization' THEN
        PERFORM app_private.require_organization_active_owner_v1(
          NEW.workspace_id
        );
      END IF;
    ELSIF TG_OP = 'UPDATE' THEN
      IF NEW.workspace_kind = 'organization'
        OR OLD.workspace_kind = 'organization'
      THEN
        PERFORM app_private.require_organization_active_owner_v1(
          NEW.workspace_id
        );
      END IF;
    ELSE
      PERFORM app_private.require_organization_active_owner_v1(
        OLD.workspace_id
      );
    END IF;
  ELSIF TG_RELID = 'app_data.organization_memberships'::regclass THEN
    IF TG_OP = 'INSERT' THEN
      PERFORM app_private.require_organization_active_owner_v1(
        NEW.organization_workspace_id
      );
    ELSIF TG_OP = 'UPDATE' THEN
      PERFORM app_private.require_organization_active_owner_v1(
        NEW.organization_workspace_id
      );
      IF NEW.organization_workspace_id IS DISTINCT FROM
          OLD.organization_workspace_id
      THEN
        PERFORM app_private.require_organization_active_owner_v1(
          OLD.organization_workspace_id
        );
      END IF;
    ELSE
      PERFORM app_private.require_organization_active_owner_v1(
        OLD.organization_workspace_id
      );
    END IF;
  ELSIF TG_RELID = 'app_data.organization_owner_assignments'::regclass THEN
    IF TG_OP = 'INSERT' THEN
      new_membership_id := NEW.organization_membership_id;
    ELSIF TG_OP = 'UPDATE' THEN
      new_membership_id := NEW.organization_membership_id;
      old_membership_id := OLD.organization_membership_id;
    ELSE
      old_membership_id := OLD.organization_membership_id;
    END IF;

    FOR workspace_id IN
      SELECT DISTINCT organization_membership.organization_workspace_id
      FROM app_data.organization_memberships AS organization_membership
      WHERE organization_membership.organization_membership_id IN (
        new_membership_id,
        old_membership_id
      )
      ORDER BY organization_membership.organization_workspace_id
    LOOP
      PERFORM app_private.require_organization_active_owner_v1(workspace_id);
    END LOOP;
  ELSIF TG_RELID = 'app_data.app_users'::regclass THEN
    IF TG_OP = 'UPDATE' THEN
      IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
      END IF;
      affected_app_user_id := NEW.app_user_id;
    ELSE
      affected_app_user_id := OLD.app_user_id;
    END IF;

    FOR workspace_id IN
      SELECT DISTINCT organization_membership.organization_workspace_id
      FROM app_data.organization_memberships AS organization_membership
      WHERE organization_membership.app_user_id = affected_app_user_id
      ORDER BY organization_membership.organization_workspace_id
    LOOP
      PERFORM app_private.require_organization_active_owner_v1(workspace_id);
    END LOOP;
  END IF;

  RETURN NULL;
END
$function$;

-- Membership writes acquire the governance fence before the existing
-- organization-membership:<workspace>:<user> lock.  The remaining validator
-- checks and error messages intentionally stay byte-for-byte equivalent.
CREATE OR REPLACE FUNCTION app_private.validate_organization_membership_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  requested_period tstzrange := tstzrange(
    NEW.active_from_utc,
    NEW.inactive_from_utc,
    '[)'
  );
BEGIN
  PERFORM app_private.lock_organization_governance_v1(
    NEW.organization_workspace_id
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || NEW.organization_workspace_id::text
        || ':' || NEW.app_user_id::text,
      0
    )
  );

  IF TG_OP = 'INSERT' AND (
    NOT EXISTS (
      SELECT 1
      FROM app_data.workspaces AS workspace_row
      WHERE workspace_row.workspace_id =
          NEW.organization_workspace_id
        AND workspace_row.workspace_kind = 'organization'
        AND workspace_row.deleted_at IS NULL
    )
    OR NOT EXISTS (
      SELECT 1
      FROM app_data.app_users AS app_user
      WHERE app_user.app_user_id = NEW.app_user_id
        AND app_user.status = 'active'
    )
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization membership scope';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.organization_memberships AS existing_membership
    WHERE existing_membership.organization_workspace_id =
        NEW.organization_workspace_id
      AND existing_membership.app_user_id = NEW.app_user_id
      AND existing_membership.organization_membership_id <>
        NEW.organization_membership_id
      AND tstzrange(
        existing_membership.active_from_utc,
        existing_membership.inactive_from_utc,
        '[)'
      ) && requested_period
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23P01',
      MESSAGE = 'organization membership periods overlap';
  END IF;

  IF TG_OP = 'UPDATE' AND EXISTS (
    SELECT 1
    FROM app_data.project_memberships AS project_membership
    WHERE project_membership.organization_membership_id =
        NEW.organization_membership_id
      AND NOT tstzrange(
        project_membership.active_from_utc,
        project_membership.inactive_from_utc,
        '[)'
      ) <@ requested_period
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'close project memberships before organization membership';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER workspaces_governance_fence
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.workspaces
FOR EACH ROW
EXECUTE FUNCTION app_private.lock_organization_governance_for_mutation_v1();

CREATE TRIGGER organization_memberships_governance_fence
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.organization_memberships
FOR EACH ROW
EXECUTE FUNCTION app_private.lock_organization_governance_for_mutation_v1();

CREATE TRIGGER organization_owner_assignments_governance_fence
BEFORE INSERT OR UPDATE OR DELETE
ON app_data.organization_owner_assignments
FOR EACH ROW
EXECUTE FUNCTION app_private.lock_organization_governance_for_mutation_v1();

CREATE TRIGGER app_users_governance_fence
BEFORE UPDATE OF status
ON app_data.app_users
FOR EACH ROW
EXECUTE FUNCTION app_private.lock_organization_governance_for_mutation_v1();

CREATE CONSTRAINT TRIGGER workspaces_active_owner_invariant
AFTER INSERT OR UPDATE OR DELETE
ON app_data.workspaces
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION app_private.enforce_organization_active_owner_v1();

CREATE CONSTRAINT TRIGGER organization_memberships_active_owner_invariant
AFTER INSERT OR UPDATE OR DELETE
ON app_data.organization_memberships
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION app_private.enforce_organization_active_owner_v1();

CREATE CONSTRAINT TRIGGER organization_owner_assignments_active_owner_invariant
AFTER INSERT OR UPDATE OR DELETE
ON app_data.organization_owner_assignments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION app_private.enforce_organization_active_owner_v1();

CREATE CONSTRAINT TRIGGER app_users_active_owner_invariant
AFTER UPDATE OF status
ON app_data.app_users
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION app_private.enforce_organization_active_owner_v1();

-- Keep all four owner-invariant tables closed for direct writes while leaving
-- their existing reader SELECT grants intact.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE
    app_data.workspaces,
    app_data.organization_memberships,
    app_data.organization_owner_assignments,
    app_data.app_users
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.lock_organization_governance_v1(uuid),
  app_private.lock_organization_governance_for_mutation_v1(),
  app_private.require_organization_active_owner_v1(uuid),
  app_private.enforce_organization_active_owner_v1(),
  app_private.validate_organization_membership_v1()
  FROM PUBLIC, tongxingzhe_runtime;

-- Resolve the existing private validator owner instead of introducing a new
-- role.  The same trusted owner owns every new SECURITY DEFINER function.
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
    'ALTER FUNCTION app_private.lock_organization_governance_v1(uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.lock_organization_governance_for_mutation_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.require_organization_active_owner_v1(uuid) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.enforce_organization_active_owner_v1() OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON FUNCTION app_private.lock_organization_governance_v1(uuid)
IS 'Acquires the transaction governance lock for one organization workspace.';

COMMENT ON FUNCTION
  app_private.lock_organization_governance_for_mutation_v1()
IS 'Locks every organization governance key affected by a direct row mutation.';

COMMENT ON FUNCTION app_private.require_organization_active_owner_v1(uuid)
IS 'Requires every physical organization workspace to retain one current active owner.';

COMMENT ON FUNCTION app_private.enforce_organization_active_owner_v1()
IS 'Deferred invariant trigger for organization workspace owner validity.';

COMMENT ON TRIGGER workspaces_governance_fence ON app_data.workspaces
IS 'Locks organization governance before workspace mutations.';

COMMENT ON TRIGGER organization_memberships_governance_fence
  ON app_data.organization_memberships
IS 'Locks organization governance before membership mutations.';

COMMENT ON TRIGGER organization_owner_assignments_governance_fence
  ON app_data.organization_owner_assignments
IS 'Locks organization governance before owner-assignment mutations.';

COMMENT ON TRIGGER app_users_governance_fence ON app_data.app_users
IS 'Locks affected organization governance before app-user status changes.';

COMMENT ON TRIGGER workspaces_active_owner_invariant ON app_data.workspaces
IS 'Deferred active-owner invariant for physical organization workspaces.';

COMMENT ON TRIGGER organization_memberships_active_owner_invariant
  ON app_data.organization_memberships
IS 'Deferred active-owner invariant for organization membership changes.';

COMMENT ON TRIGGER organization_owner_assignments_active_owner_invariant
  ON app_data.organization_owner_assignments
IS 'Deferred active-owner invariant for owner-assignment changes.';

COMMENT ON TRIGGER app_users_active_owner_invariant ON app_data.app_users
IS 'Deferred active-owner invariant for app-user status changes.';
