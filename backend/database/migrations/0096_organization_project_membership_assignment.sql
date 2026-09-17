-- Ordinary project membership only; no management capability is granted.
CREATE TABLE app_private.organization_project_membership_assignment_request_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid REFERENCES app_data.app_users(app_user_id) ON DELETE SET NULL,
  organization_workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  organization_membership_id uuid NOT NULL,
  project_membership_id uuid NOT NULL,
  active_from_utc timestamptz NOT NULL,
  inactive_from_utc timestamptz,
  CHECK (isfinite(active_from_utc)),
  CHECK (inactive_from_utc IS NULL OR
    (isfinite(inactive_from_utc) AND inactive_from_utc > active_from_utc))
);
CREATE TABLE app_private.organization_project_membership_assignment_request_tombstones (
  claim_family text NOT NULL CHECK (claim_family = 'organization-project-membership-assignment:v1'),
  request_id uuid NOT NULL,
  PRIMARY KEY (claim_family, request_id)
);
CREATE TABLE app_private.organization_project_membership_assignment_audit_events (
  project_membership_assignment_audit_event_id uuid PRIMARY KEY,
  project_membership_assignment_contract_id text NOT NULL
    CHECK (project_membership_assignment_contract_id = 'organization-project-membership-assignment:v1'),
  request_id uuid NOT NULL UNIQUE,
  organization_workspace_id uuid NOT NULL,
  project_id uuid NOT NULL,
  project_membership_id uuid NOT NULL,
  active_from_utc timestamptz NOT NULL,
  inactive_from_utc timestamptz,
  CHECK (isfinite(active_from_utc)),
  CHECK (inactive_from_utc IS NULL OR
    (isfinite(inactive_from_utc) AND inactive_from_utc > active_from_utc))
);

CREATE FUNCTION app_private.protect_organization_project_membership_assignment_claim_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.actor_app_user_id IS NOT NULL AND NEW.actor_app_user_id IS NULL
      AND to_jsonb(OLD) - 'actor_app_user_id' = to_jsonb(NEW) - 'actor_app_user_id'
    THEN RETURN NEW; END IF;
  END IF;
  RAISE EXCEPTION USING ERRCODE = '55000',
    MESSAGE = 'organization project membership assignment claim is immutable';
END
$function$;
CREATE FUNCTION app_private.protect_organization_project_membership_assignment_terminal_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '55000',
    MESSAGE = 'organization project membership assignment terminal fact is immutable';
END
$function$;
CREATE TRIGGER organization_project_membership_assignment_claims_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_project_membership_assignment_request_claims
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_project_membership_assignment_claim_v1();
CREATE TRIGGER organization_project_membership_assignment_tombstones_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_project_membership_assignment_request_tombstones
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_project_membership_assignment_terminal_v1();
CREATE TRIGGER organization_project_membership_assignment_audit_immutable
BEFORE UPDATE OR DELETE ON app_private.organization_project_membership_assignment_audit_events
FOR EACH ROW EXECUTE FUNCTION app_private.protect_organization_project_membership_assignment_terminal_v1();

CREATE FUNCTION app_private.assign_organization_project_member_v1(
  trusted_actor_app_user_id uuid,
  requested_request_id uuid,
  requested_organization_workspace_id uuid,
  requested_project_id uuid,
  requested_target_organization_membership_id uuid
)
RETURNS TABLE (
  project_membership_assignment_contract_id text,
  organization_workspace_id uuid,
  project_id uuid,
  organization_membership_id uuid,
  project_membership_id uuid,
  active_from_utc timestamptz,
  inactive_from_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE
  claim_row app_private.organization_project_membership_assignment_request_claims%ROWTYPE;
  target_parent app_data.organization_memberships%ROWTYPE;
  target_user_id uuid;
  locked_user_id uuid;
  assignment_time timestamptz;
  new_membership_id uuid;
BEGIN
  -- Waiting in a transaction-wide snapshot cannot safely observe status commits.
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'organization project membership assignment requires read committed';
  END IF;
  IF requested_request_id IS NULL OR requested_organization_workspace_id IS NULL
    OR requested_project_id IS NULL OR requested_target_organization_membership_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization project membership assignment request';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'organization-project-membership-assignment-request:' || requested_request_id::text, 0));
  PERFORM 1 FROM app_private.organization_project_membership_assignment_request_tombstones AS tombstone
  WHERE tombstone.claim_family = 'organization-project-membership-assignment:v1'
    AND tombstone.request_id = requested_request_id;
  IF FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'organization project membership assignment idempotency conflict';
  END IF;
  SELECT claim.* INTO claim_row
  FROM app_private.organization_project_membership_assignment_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  IF FOUND THEN
    -- Historical replay takes no target, governance, hierarchy or status lock.
    PERFORM 1 FROM app_data.app_users AS actor
    WHERE actor.app_user_id = trusted_actor_app_user_id FOR UPDATE;
    SELECT claim.* INTO claim_row
    FROM app_private.organization_project_membership_assignment_request_claims AS claim
    WHERE claim.request_id = requested_request_id;
    IF NOT FOUND OR claim_row.actor_app_user_id IS DISTINCT FROM trusted_actor_app_user_id
      OR trusted_actor_app_user_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM app_data.app_users AS actor
        WHERE actor.app_user_id = trusted_actor_app_user_id AND actor.status = 'active')
    THEN
      RAISE EXCEPTION USING ERRCODE = '42501',
        MESSAGE = 'organization project membership assignment forbidden';
    END IF;
    IF claim_row.organization_workspace_id IS DISTINCT FROM requested_organization_workspace_id
      OR claim_row.project_id IS DISTINCT FROM requested_project_id
      OR claim_row.organization_membership_id IS DISTINCT FROM requested_target_organization_membership_id
    THEN
      RAISE EXCEPTION USING ERRCODE = '22023',
        MESSAGE = 'organization project membership assignment idempotency conflict';
    END IF;
    RETURN QUERY SELECT 'organization-project-membership-assignment:v1'::text,
      claim_row.organization_workspace_id, claim_row.project_id,
      claim_row.organization_membership_id, claim_row.project_membership_id,
      claim_row.active_from_utc, claim_row.inactive_from_utc;
    RETURN;
  END IF;

  -- This immutable parent selector only resolves the UUID lock set. All
  -- eligibility facts are read again after the complete prescribed lock set.
  SELECT parent.app_user_id INTO target_user_id
  FROM app_data.organization_memberships AS parent
  WHERE parent.organization_membership_id = requested_target_organization_membership_id;
  FOR locked_user_id IN SELECT DISTINCT user_id FROM
    (VALUES (trusted_actor_app_user_id), (target_user_id)) AS users(user_id)
    WHERE user_id IS NOT NULL ORDER BY user_id
  LOOP
    PERFORM 1 FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = locked_user_id FOR UPDATE;
  END LOOP;
  PERFORM app_private.lock_organization_governance_v1(requested_organization_workspace_id);
  FOR locked_user_id IN SELECT DISTINCT user_id FROM
    (VALUES (trusted_actor_app_user_id), (target_user_id)) AS users(user_id)
    WHERE user_id IS NOT NULL ORDER BY user_id
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'organization-membership:' || requested_organization_workspace_id::text
        || ':' || locked_user_id::text, 0));
  END LOOP;
  IF target_user_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'project-membership:' || requested_project_id::text || ':' || target_user_id::text, 0));
  END IF;
  -- Do not take project row locks: a status UPDATE holds its row before this fence.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'management-follow-up-consent-opt-in:' || requested_project_id::text, 0));

  PERFORM 1 FROM app_private.organization_project_membership_assignment_request_tombstones AS tombstone
  WHERE tombstone.claim_family = 'organization-project-membership-assignment:v1'
    AND tombstone.request_id = requested_request_id;
  IF FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'organization project membership assignment idempotency conflict';
  END IF;
  PERFORM 1 FROM app_private.organization_project_membership_assignment_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  IF FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization project membership assignment forbidden';
  END IF;
  assignment_time := clock_timestamp();
  SELECT parent.* INTO target_parent FROM app_data.organization_memberships AS parent
  WHERE parent.organization_membership_id = requested_target_organization_membership_id;
  IF NOT FOUND OR target_parent.organization_workspace_id IS DISTINCT FROM requested_organization_workspace_id
    OR target_parent.app_user_id IS DISTINCT FROM target_user_id
    OR NOT (tstzrange(target_parent.active_from_utc, target_parent.inactive_from_utc, '[)') @> assignment_time)
    OR NOT EXISTS (SELECT 1 FROM app_data.app_users AS app_user
      WHERE app_user.app_user_id = target_user_id AND app_user.status = 'active')
    OR NOT EXISTS (SELECT 1 FROM app_data.app_users AS app_user
      WHERE app_user.app_user_id = trusted_actor_app_user_id AND app_user.status = 'active')
    OR NOT EXISTS (SELECT 1 FROM app_data.projects AS project
      JOIN app_data.workspaces AS workspace ON workspace.workspace_id = project.workspace_id
      WHERE project.project_id = requested_project_id
        AND project.workspace_id = requested_organization_workspace_id AND project.status = 'active'
        AND workspace.workspace_kind = 'organization' AND workspace.deleted_at IS NULL)
    OR NOT EXISTS (SELECT 1 FROM app_data.organization_memberships AS actor_parent
      JOIN app_data.organization_owner_assignments AS owner_assignment
        ON owner_assignment.organization_membership_id = actor_parent.organization_membership_id
      WHERE actor_parent.organization_workspace_id = requested_organization_workspace_id
        AND actor_parent.app_user_id = trusted_actor_app_user_id
        AND tstzrange(actor_parent.active_from_utc, actor_parent.inactive_from_utc, '[)') @> assignment_time
        AND tstzrange(owner_assignment.active_from_utc, owner_assignment.inactive_from_utc, '[)') @> assignment_time)
    OR EXISTS (SELECT 1 FROM app_data.project_memberships AS existing_child
      JOIN app_data.organization_memberships AS existing_parent
        ON existing_parent.organization_membership_id = existing_child.organization_membership_id
      WHERE existing_child.project_id = requested_project_id AND existing_parent.app_user_id = target_user_id
        AND tstzrange(existing_child.active_from_utc, existing_child.inactive_from_utc, '[)')
          && tstzrange(assignment_time, target_parent.inactive_from_utc, '[)'))
  THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization project membership assignment forbidden';
  END IF;
  new_membership_id := gen_random_uuid();
  INSERT INTO app_data.project_memberships VALUES
    (new_membership_id, requested_target_organization_membership_id, requested_project_id,
     assignment_time, target_parent.inactive_from_utc);
  INSERT INTO app_private.organization_project_membership_assignment_request_claims VALUES
    (requested_request_id, trusted_actor_app_user_id, requested_organization_workspace_id,
     requested_project_id, requested_target_organization_membership_id, new_membership_id,
     assignment_time, target_parent.inactive_from_utc);
  INSERT INTO app_private.organization_project_membership_assignment_audit_events VALUES
    (gen_random_uuid(), 'organization-project-membership-assignment:v1', requested_request_id,
     requested_organization_workspace_id, requested_project_id, new_membership_id,
     assignment_time, target_parent.inactive_from_utc);
  RETURN QUERY SELECT 'organization-project-membership-assignment:v1'::text,
    requested_organization_workspace_id, requested_project_id,
    requested_target_organization_membership_id, new_membership_id,
    assignment_time, target_parent.inactive_from_utc;
END
$function$;

CREATE FUNCTION app_data.assign_organization_project_member_for_identity_v1(
  trusted_issuer text, trusted_subject text, requested_request_id uuid,
  requested_organization_workspace_id uuid, requested_project_id uuid,
  requested_target_organization_membership_id uuid
)
RETURNS TABLE (
  project_membership_assignment_contract_id text, organization_workspace_id uuid,
  project_id uuid, organization_membership_id uuid, project_membership_id uuid,
  active_from_utc timestamptz, inactive_from_utc timestamptz
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog
AS $function$
DECLARE resolved_app_user_id uuid;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '0A000',
      MESSAGE = 'organization project membership assignment requires read committed';
  END IF;
  IF trusted_issuer IS NULL OR btrim(trusted_issuer) = '' OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL OR btrim(trusted_subject) = '' OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'invalid organization project membership assignment identity';
  END IF;
  SELECT identity_row.app_user_id INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';
  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501',
      MESSAGE = 'organization project membership assignment forbidden';
  END IF;
  RETURN QUERY SELECT result.* FROM app_private.assign_organization_project_member_v1(
    resolved_app_user_id, requested_request_id, requested_organization_workspace_id,
    requested_project_id, requested_target_organization_membership_id) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_project_membership_assignment_request_claims,
  app_private.organization_project_membership_assignment_request_tombstones,
  app_private.organization_project_membership_assignment_audit_events
FROM PUBLIC, tongxingzhe_runtime;
REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_project_membership_assignment_claim_v1(),
  app_private.protect_organization_project_membership_assignment_terminal_v1(),
  app_private.assign_organization_project_member_v1(uuid,uuid,uuid,uuid,uuid),
  app_data.assign_organization_project_member_for_identity_v1(text,text,uuid,uuid,uuid,uuid)
FROM PUBLIC, tongxingzhe_runtime;
GRANT EXECUTE ON FUNCTION
  app_data.assign_organization_project_member_for_identity_v1(text,text,uuid,uuid,uuid,uuid)
TO tongxingzhe_runtime;
DO $owner$
DECLARE trusted_owner text; object_name text;
BEGIN
  SELECT pg_get_userbyid(proowner) INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.organization_project_membership_assignment_request_claims',
    'app_private.organization_project_membership_assignment_request_tombstones',
    'app_private.organization_project_membership_assignment_audit_events']
  LOOP EXECUTE format('ALTER TABLE %s OWNER TO %I', object_name, trusted_owner); END LOOP;
  FOREACH object_name IN ARRAY ARRAY[
    'app_private.protect_organization_project_membership_assignment_claim_v1()',
    'app_private.protect_organization_project_membership_assignment_terminal_v1()',
    'app_private.assign_organization_project_member_v1(uuid,uuid,uuid,uuid,uuid)',
    'app_data.assign_organization_project_member_for_identity_v1(text,text,uuid,uuid,uuid,uuid)']
  LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO %I', object_name, trusted_owner); END LOOP;
END
$owner$;
