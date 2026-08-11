-- 0030_management_report_authorization.sql
--
-- 固定管理分析的私有授权链：活动账号、组织成员、项目成员和明确的
-- 项目能力必须同时有效。成员管理和生产授权入口留给 Slice 7。

CREATE TABLE app_data.organization_memberships (
  organization_membership_id uuid PRIMARY KEY,
  organization_workspace_id uuid NOT NULL
    REFERENCES app_data.workspaces (workspace_id) ON DELETE RESTRICT,
  app_user_id uuid NOT NULL
    REFERENCES app_data.app_users (app_user_id) ON DELETE RESTRICT,
  active_from_utc timestamp with time zone NOT NULL,
  inactive_from_utc timestamp with time zone,
  CHECK (isfinite(active_from_utc)),
  CHECK (
    inactive_from_utc IS NULL
    OR (
      isfinite(inactive_from_utc)
      AND inactive_from_utc > active_from_utc
    )
  )
);

CREATE INDEX organization_memberships_authorization_idx
ON app_data.organization_memberships (
  organization_workspace_id,
  app_user_id,
  active_from_utc DESC
);

CREATE TABLE app_data.project_memberships (
  project_membership_id uuid PRIMARY KEY,
  organization_membership_id uuid NOT NULL
    REFERENCES app_data.organization_memberships (
      organization_membership_id
    ) ON DELETE RESTRICT,
  project_id uuid NOT NULL
    REFERENCES app_data.projects (project_id) ON DELETE RESTRICT,
  active_from_utc timestamp with time zone NOT NULL,
  inactive_from_utc timestamp with time zone,
  CHECK (isfinite(active_from_utc)),
  CHECK (
    inactive_from_utc IS NULL
    OR (
      isfinite(inactive_from_utc)
      AND inactive_from_utc > active_from_utc
    )
  )
);

CREATE INDEX project_memberships_authorization_idx
ON app_data.project_memberships (
  project_id,
  organization_membership_id,
  active_from_utc DESC
);

CREATE TABLE app_data.management_report_capability_grants (
  capability_grant_id uuid PRIMARY KEY,
  project_membership_id uuid NOT NULL
    REFERENCES app_data.project_memberships (project_membership_id)
    ON DELETE RESTRICT,
  capability_id text NOT NULL CHECK (
    capability_id IN (
      'view_anonymous_analytics',
      'release_management_reports'
    )
  ),
  active_from_utc timestamp with time zone NOT NULL,
  inactive_from_utc timestamp with time zone,
  CHECK (isfinite(active_from_utc)),
  CHECK (
    inactive_from_utc IS NULL
    OR (
      isfinite(inactive_from_utc)
      AND inactive_from_utc > active_from_utc
    )
  )
);

CREATE INDEX management_report_capability_grants_authorization_idx
ON app_data.management_report_capability_grants (
  project_membership_id,
  capability_id,
  active_from_utc DESC
);

REVOKE ALL PRIVILEGES ON TABLE
  app_data.organization_memberships,
  app_data.project_memberships,
  app_data.management_report_capability_grants
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_membership_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'membership authorization history cannot be deleted';
  END IF;

  IF to_jsonb(NEW) - 'inactive_from_utc'
      <> to_jsonb(OLD) - 'inactive_from_utc'
    OR OLD.inactive_from_utc IS NOT NULL
    OR NEW.inactive_from_utc IS NULL
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'membership authorization history is append-only';
  END IF;

  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.validate_organization_membership_v1()
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

CREATE FUNCTION app_private.validate_project_membership_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  parent_membership app_data.organization_memberships%ROWTYPE;
  requested_period tstzrange := tstzrange(
    NEW.active_from_utc,
    NEW.inactive_from_utc,
    '[)'
  );
BEGIN
  SELECT membership.* INTO STRICT parent_membership
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    NEW.organization_membership_id;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || parent_membership.organization_workspace_id::text
        || ':' || parent_membership.app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'project-membership:' || NEW.project_id::text
        || ':' || parent_membership.app_user_id::text,
      0
    )
  );

  -- Re-read after both hierarchy locks. A concurrent organization revocation
  -- either commits first and becomes visible here, or waits for this insert.
  SELECT membership.* INTO STRICT parent_membership
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    NEW.organization_membership_id;

  IF TG_OP = 'INSERT' AND NOT EXISTS (
    SELECT 1
    FROM app_data.projects AS project_row
    JOIN app_data.workspaces AS workspace_row
      ON workspace_row.workspace_id = project_row.workspace_id
    JOIN app_data.app_users AS app_user
      ON app_user.app_user_id = parent_membership.app_user_id
    WHERE project_row.project_id = NEW.project_id
      AND project_row.workspace_id =
        parent_membership.organization_workspace_id
      AND project_row.status = 'active'
      AND workspace_row.workspace_kind = 'organization'
      AND workspace_row.deleted_at IS NULL
      AND app_user.status = 'active'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid project membership scope';
  END IF;

  IF NOT requested_period <@ tstzrange(
      parent_membership.active_from_utc,
      parent_membership.inactive_from_utc,
      '[)'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'project membership exceeds organization membership';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.project_memberships AS existing_project_membership
    JOIN app_data.organization_memberships AS existing_parent
      ON existing_parent.organization_membership_id =
        existing_project_membership.organization_membership_id
    WHERE existing_project_membership.project_id = NEW.project_id
      AND existing_parent.app_user_id = parent_membership.app_user_id
      AND existing_project_membership.project_membership_id <>
        NEW.project_membership_id
      AND tstzrange(
        existing_project_membership.active_from_utc,
        existing_project_membership.inactive_from_utc,
        '[)'
      ) && requested_period
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23P01',
      MESSAGE = 'project membership periods overlap';
  END IF;

  IF TG_OP = 'UPDATE' AND EXISTS (
    SELECT 1
    FROM app_data.management_report_capability_grants AS capability_grant
    WHERE capability_grant.project_membership_id =
        NEW.project_membership_id
      AND NOT tstzrange(
        capability_grant.active_from_utc,
        capability_grant.inactive_from_utc,
        '[)'
      ) <@ requested_period
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'close capability grants before project membership';
  END IF;

  RETURN NEW;
END
$function$;

CREATE FUNCTION
  app_private.validate_management_report_capability_grant_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  parent_membership app_data.project_memberships%ROWTYPE;
  parent_organization_membership
    app_data.organization_memberships%ROWTYPE;
  requested_period tstzrange := tstzrange(
    NEW.active_from_utc,
    NEW.inactive_from_utc,
    '[)'
  );
BEGIN
  SELECT membership.* INTO STRICT parent_membership
  FROM app_data.project_memberships AS membership
  WHERE membership.project_membership_id = NEW.project_membership_id;

  SELECT membership.* INTO STRICT parent_organization_membership
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    parent_membership.organization_membership_id;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || parent_organization_membership.organization_workspace_id::text
        || ':' || parent_organization_membership.app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'project-membership:' || parent_membership.project_id::text
        || ':' || parent_organization_membership.app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'management-report-capability:'
        || parent_membership.project_id::text
        || ':' || parent_organization_membership.app_user_id::text
        || ':' || NEW.capability_id,
      0
    )
  );

  -- Re-read the parent after the hierarchy locks for the same reason as the
  -- project-membership validator above.
  SELECT membership.* INTO STRICT parent_membership
  FROM app_data.project_memberships AS membership
  WHERE membership.project_membership_id = NEW.project_membership_id;

  IF NOT requested_period <@ tstzrange(
      parent_membership.active_from_utc,
      parent_membership.inactive_from_utc,
      '[)'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'capability grant exceeds project membership';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.management_report_capability_grants AS existing_grant
    WHERE existing_grant.project_membership_id =
        NEW.project_membership_id
      AND existing_grant.capability_id = NEW.capability_id
      AND existing_grant.capability_grant_id <> NEW.capability_grant_id
      AND tstzrange(
        existing_grant.active_from_utc,
        existing_grant.inactive_from_utc,
        '[)'
      ) && requested_period
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23P01',
      MESSAGE = 'management report capability periods overlap';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_memberships_validate
BEFORE INSERT OR UPDATE
ON app_data.organization_memberships
FOR EACH ROW
EXECUTE FUNCTION app_private.validate_organization_membership_v1();

CREATE TRIGGER organization_memberships_protect_history
BEFORE UPDATE OR DELETE
ON app_data.organization_memberships
FOR EACH ROW
EXECUTE FUNCTION app_private.protect_membership_history_v1();

CREATE TRIGGER project_memberships_validate
BEFORE INSERT OR UPDATE
ON app_data.project_memberships
FOR EACH ROW
EXECUTE FUNCTION app_private.validate_project_membership_v1();

CREATE TRIGGER project_memberships_protect_history
BEFORE UPDATE OR DELETE
ON app_data.project_memberships
FOR EACH ROW
EXECUTE FUNCTION app_private.protect_membership_history_v1();

CREATE TRIGGER management_report_capability_grants_validate
BEFORE INSERT OR UPDATE
ON app_data.management_report_capability_grants
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_management_report_capability_grant_v1();

CREATE TRIGGER management_report_capability_grants_protect_history
BEFORE UPDATE OR DELETE
ON app_data.management_report_capability_grants
FOR EACH ROW
EXECUTE FUNCTION app_private.protect_membership_history_v1();

CREATE FUNCTION app_private.resolve_management_report_authorization_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_capability_id text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $function$
DECLARE
  authorization_record record;
  authorization_workspace_id uuid;
  reference_at_utc timestamp with time zone;
BEGIN
  IF requested_app_user_id IS NULL
    OR requested_project_id IS NULL
    OR requested_capability_id IS NULL
    OR requested_capability_id NOT IN (
      'view_anonymous_analytics',
      'release_management_reports'
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid management report authorization request';
  END IF;

  SELECT project_row.workspace_id INTO authorization_workspace_id
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = requested_project_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  -- These transaction locks are also taken by membership and capability
  -- mutation triggers. The resolver result is therefore safe to consume only
  -- in this same transaction: either the operation precedes revocation, or it
  -- observes the committed revocation and fails closed.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:' || authorization_workspace_id::text
        || ':' || requested_app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'project-membership:' || requested_project_id::text
        || ':' || requested_app_user_id::text,
      0
    )
  );

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'management-report-capability:' || requested_project_id::text
        || ':' || requested_app_user_id::text
        || ':' || requested_capability_id,
      0
    )
  );

  -- Choose the authorization time after the hierarchy locks. A revocation
  -- that already holds a lock must set its boundary and commit first, so this
  -- resolver cannot reuse the earlier statement start time to pass afterward.
  reference_at_utc = clock_timestamp();

  SELECT
    workspace_row.workspace_id,
    organization_membership.organization_membership_id,
    project_membership.project_membership_id,
    capability_grant.capability_grant_id,
    capability_grant.active_from_utc AS capability_active_from_utc,
    capability_grant.inactive_from_utc AS capability_inactive_from_utc
  INTO authorization_record
  FROM app_data.app_users AS app_user
  JOIN app_data.organization_memberships AS organization_membership
    ON organization_membership.app_user_id = app_user.app_user_id
  JOIN app_data.workspaces AS workspace_row
    ON workspace_row.workspace_id =
      organization_membership.organization_workspace_id
  JOIN app_data.projects AS project_row
    ON project_row.workspace_id = workspace_row.workspace_id
  JOIN app_data.project_memberships AS project_membership
    ON project_membership.organization_membership_id =
      organization_membership.organization_membership_id
   AND project_membership.project_id = project_row.project_id
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.project_membership_id =
      project_membership.project_membership_id
  WHERE app_user.app_user_id = requested_app_user_id
    AND app_user.status = 'active'
    AND workspace_row.workspace_kind = 'organization'
    AND workspace_row.deleted_at IS NULL
    AND project_row.project_id = requested_project_id
    AND project_row.status = 'active'
    AND tstzrange(
      organization_membership.active_from_utc,
      organization_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND tstzrange(
      project_membership.active_from_utc,
      project_membership.inactive_from_utc,
      '[)'
    ) @> reference_at_utc
    AND capability_grant.capability_id = requested_capability_id
    AND tstzrange(
      capability_grant.active_from_utc,
      capability_grant.inactive_from_utc,
      '[)'
    ) @> reference_at_utc;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'management report authorization forbidden';
  END IF;

  RETURN jsonb_build_object(
    'authorization_contract_id',
      'management_report_authorization_v1',
    'app_user_id', requested_app_user_id,
    'organization_workspace_id', authorization_record.workspace_id,
    'project_id', requested_project_id,
    'organization_membership_id',
      authorization_record.organization_membership_id,
    'project_membership_id', authorization_record.project_membership_id,
    'capability_grant_id', authorization_record.capability_grant_id,
    'capability_id', requested_capability_id,
    'capability_active_from_utc', to_char(
      authorization_record.capability_active_from_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'capability_inactive_from_utc', CASE
      WHEN authorization_record.capability_inactive_from_utc IS NULL
        THEN NULL
      ELSE to_char(
        authorization_record.capability_inactive_from_utc
          AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    END,
    'reference_at_utc', to_char(
      reference_at_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    )
  );
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.resolve_management_report_authorization_v1(
    uuid,
    uuid,
    text
  ),
  app_private.validate_organization_membership_v1(),
  app_private.validate_project_membership_v1(),
  app_private.validate_management_report_capability_grant_v1(),
  app_private.protect_membership_history_v1()
  FROM PUBLIC, tongxingzhe_runtime;

COMMENT ON TABLE app_data.organization_memberships
IS 'Organization membership periods used by trusted application authorization.';

COMMENT ON TABLE app_data.project_memberships
IS 'Explicit project membership periods subordinate to organization membership.';

COMMENT ON TABLE app_data.management_report_capability_grants
IS 'Separate project grants for viewing analytics or releasing reports.';

COMMENT ON FUNCTION
  app_private.resolve_management_report_authorization_v1(
    uuid,
    uuid,
    text
  )
IS 'Resolves one private management-report capability at a trusted post-lock database time; consume the evidence in the same transaction.';
