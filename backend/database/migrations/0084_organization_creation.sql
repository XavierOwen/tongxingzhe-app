-- 0084_organization_creation.sql
--
-- Slice 7C adds the database-only organization creation write seam.  This
-- migration deliberately does not add organization lifecycle, owner transfer,
-- tombstone, purge, or the later global zero-owner constraint triggers.

CREATE TABLE app_data.organization_owner_assignments (
  organization_owner_assignment_id uuid PRIMARY KEY,
  organization_membership_id uuid NOT NULL
    REFERENCES app_data.organization_memberships (
      organization_membership_id
    ) ON DELETE RESTRICT,
  active_from_utc timestamptz NOT NULL,
  inactive_from_utc timestamptz,
  CHECK (isfinite(active_from_utc)),
  CHECK (
    inactive_from_utc IS NULL
    OR (
      isfinite(inactive_from_utc)
      AND inactive_from_utc > active_from_utc
    )
  )
);

CREATE INDEX organization_owner_assignments_membership_active_idx
ON app_data.organization_owner_assignments (
  organization_membership_id,
  active_from_utc DESC
);

CREATE TABLE app_private.organization_creation_request_claims (
  request_id uuid PRIMARY KEY,
  actor_app_user_id uuid
    REFERENCES app_data.app_users (app_user_id) ON DELETE SET NULL,
  canonical_display_name text NOT NULL CHECK (
    char_length(canonical_display_name) BETWEEN 1 AND 120
  ),
  organization_workspace_id uuid NOT NULL,
  organization_membership_id uuid NOT NULL,
  organization_owner_assignment_id uuid NOT NULL,
  created_at_utc timestamptz NOT NULL,
  CHECK (isfinite(created_at_utc))
);

CREATE TABLE app_private.organization_creation_audit_events (
  organization_creation_audit_event_id uuid PRIMARY KEY,
  creation_contract_id text NOT NULL CHECK (
    creation_contract_id = 'organization-creation:v1'
  ),
  request_id uuid NOT NULL UNIQUE,
  organization_workspace_id uuid NOT NULL,
  organization_membership_id uuid NOT NULL,
  organization_owner_assignment_id uuid NOT NULL,
  created_at_utc timestamptz NOT NULL,
  CHECK (isfinite(created_at_utc))
);

-- app_data has a runtime default privilege from 0001; close that privilege
-- explicitly for the new owner table.  app_private is closed at the schema
-- boundary as well, but the table ACL remains explicit for restored clusters.
REVOKE ALL PRIVILEGES ON TABLE
  app_data.organization_owner_assignments
  FROM PUBLIC, tongxingzhe_runtime;

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_creation_request_claims,
  app_private.organization_creation_audit_events
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_organization_owner_assignment_history_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization owner assignment history cannot be deleted';
  END IF;

  IF NEW.organization_owner_assignment_id IS DISTINCT FROM
      OLD.organization_owner_assignment_id
    OR NEW.organization_membership_id IS DISTINCT FROM
      OLD.organization_membership_id
    OR NEW.active_from_utc IS DISTINCT FROM OLD.active_from_utc
    OR OLD.inactive_from_utc IS NOT NULL
    OR NEW.inactive_from_utc IS NULL
    OR NEW.inactive_from_utc <= OLD.active_from_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization owner assignment history is append-only';
  END IF;

  RETURN NEW;
END
$function$;

CREATE FUNCTION app_private.validate_organization_owner_assignment_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  membership_row app_data.organization_memberships%ROWTYPE;
  requested_period tstzrange;
  membership_period tstzrange;
  member_status text;
BEGIN
  IF NEW.organization_membership_id IS NULL
    OR NEW.active_from_utc IS NULL
    OR NOT isfinite(NEW.active_from_utc)
    OR (
      TG_OP = 'INSERT'
      AND NEW.active_from_utc IS DISTINCT FROM transaction_timestamp()
    )
    OR (
      TG_OP = 'INSERT'
      AND NEW.inactive_from_utc IS NOT NULL
    )
    OR (
      NEW.inactive_from_utc IS NOT NULL
      AND (
        NOT isfinite(NEW.inactive_from_utc)
        OR NEW.inactive_from_utc <= NEW.active_from_utc
        OR (
          TG_OP = 'UPDATE'
          AND NEW.inactive_from_utc IS DISTINCT FROM transaction_timestamp()
        )
      )
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization owner assignment';
  END IF;

  SELECT membership.*
  INTO membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    NEW.organization_membership_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization owner assignment';
  END IF;

  -- Governance is the outer lock.  The existing membership validator uses
  -- the second lock, so owner assignment never introduces a reverse order.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-governance:'
        || membership_row.organization_workspace_id::text,
      0
    )
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:'
        || membership_row.organization_workspace_id::text
        || ':' || membership_row.app_user_id::text,
      0
    )
  );

  -- Re-read after the locks so a concurrent membership close cannot be
  -- hidden by the first, unlocked lookup.
  SELECT membership.*
  INTO STRICT membership_row
  FROM app_data.organization_memberships AS membership
  WHERE membership.organization_membership_id =
    NEW.organization_membership_id;

  membership_period := tstzrange(
    membership_row.active_from_utc,
    membership_row.inactive_from_utc,
    '[)'
  );
  requested_period := tstzrange(
    NEW.active_from_utc,
    NEW.inactive_from_utc,
    '[)'
  );

  IF NOT requested_period <@ membership_period THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization owner assignment exceeds membership';
  END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT app_user.status
    INTO member_status
    FROM app_data.app_users AS app_user
    WHERE app_user.app_user_id = membership_row.app_user_id;

    IF member_status IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'organization owner assignment is forbidden';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.organization_owner_assignments AS existing_assignment
    WHERE existing_assignment.organization_membership_id =
        NEW.organization_membership_id
      AND existing_assignment.organization_owner_assignment_id <>
        NEW.organization_owner_assignment_id
      AND tstzrange(
        existing_assignment.active_from_utc,
        existing_assignment.inactive_from_utc,
        '[)'
      ) && requested_period
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23P01',
      MESSAGE = 'organization owner assignment periods overlap';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_owner_assignments_protect_history
BEFORE UPDATE OR DELETE
ON app_data.organization_owner_assignments
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_owner_assignment_history_v1();

CREATE TRIGGER organization_owner_assignments_validate
BEFORE INSERT OR UPDATE
ON app_data.organization_owner_assignments
FOR EACH ROW
EXECUTE FUNCTION
  app_private.validate_organization_owner_assignment_v1();

CREATE FUNCTION app_private.protect_organization_creation_request_claim_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization creation request claim cannot be deleted';
  END IF;

  IF OLD.request_id IS DISTINCT FROM NEW.request_id
    OR OLD.canonical_display_name IS DISTINCT FROM
      NEW.canonical_display_name
    OR OLD.organization_workspace_id IS DISTINCT FROM
      NEW.organization_workspace_id
    OR OLD.organization_membership_id IS DISTINCT FROM
      NEW.organization_membership_id
    OR OLD.organization_owner_assignment_id IS DISTINCT FROM
      NEW.organization_owner_assignment_id
    OR OLD.created_at_utc IS DISTINCT FROM NEW.created_at_utc
    OR NOT (
      OLD.actor_app_user_id IS NOT NULL
      AND NEW.actor_app_user_id IS NULL
    )
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'organization creation request claim is immutable';
  END IF;

  RETURN NEW;
END
$function$;

CREATE TRIGGER organization_creation_request_claims_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_creation_request_claims
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_creation_request_claim_v1();

CREATE FUNCTION app_private.protect_organization_creation_audit_event_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization creation audit is append-only';
END
$function$;

CREATE TRIGGER organization_creation_audit_events_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_creation_audit_events
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_creation_audit_event_v1();

CREATE FUNCTION app_private.create_organization_v1(
  trusted_app_user_id uuid,
  requested_request_id uuid,
  requested_display_name text
)
RETURNS TABLE (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  canonical_name text;
  creation_time timestamptz;
  actor_status text;
  replay_claim app_private.organization_creation_request_claims%ROWTYPE;
  workspace_id uuid;
  membership_id uuid;
  owner_assignment_id uuid;
  audit_event_id uuid;
  character_index integer;
  character_codepoint integer;
  has_visible_character boolean := false;
  claim_found boolean := false;
BEGIN
  canonical_name := btrim(requested_display_name);

  IF requested_request_id IS NULL
    OR canonical_name IS NULL
    OR char_length(canonical_name) NOT BETWEEN 1 AND 120
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization creation request';
  END IF;

  -- PostgreSQL regex has no portable Unicode White_Space property.  The
  -- explicit code-point scan keeps the canonical-name contract independent of
  -- database collation and does not normalize or case-fold the submitted text.
  FOR character_index IN 1..char_length(canonical_name) LOOP
    character_codepoint := ascii(
      substr(canonical_name, character_index, 1)
    );

    IF character_codepoint BETWEEN 0 AND 31
      OR character_codepoint BETWEEN 127 AND 159
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'invalid organization creation request';
    END IF;

    IF NOT (
      character_codepoint BETWEEN 9 AND 13
      OR character_codepoint = 32
      OR character_codepoint = 133
      OR character_codepoint = 160
      OR character_codepoint = 5760
      OR character_codepoint BETWEEN 8192 AND 8202
      OR character_codepoint = 8232
      OR character_codepoint = 8233
      OR character_codepoint = 8239
      OR character_codepoint = 8287
      OR character_codepoint = 12288
    ) AND character_codepoint NOT IN (8203, 8204, 8205, 8288, 65279) THEN
      has_visible_character := true;
    END IF;
  END LOOP;

  IF NOT has_visible_character THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization creation request';
  END IF;

  -- This is the global organization-creation namespace lock.  The claim is
  -- checked before taking any actor or organization lock, so same-request
  -- retries have one deterministic serialization point.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-creation-request:' || requested_request_id::text,
      0
    )
  );

  SELECT claim.*
  INTO replay_claim
  FROM app_private.organization_creation_request_claims AS claim
  WHERE claim.request_id = requested_request_id;
  claim_found := FOUND;

  -- Both first attempts and replays lock and re-read the requested actor after
  -- the request lock.  This closes the bridge's active-identity lookup race.
  SELECT app_user.status
  INTO actor_status
  FROM app_data.app_users AS app_user
  WHERE app_user.app_user_id = trusted_app_user_id
  FOR UPDATE;

  IF NOT FOUND OR actor_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization creation forbidden';
  END IF;

  IF claim_found THEN
    IF replay_claim.actor_app_user_id IS DISTINCT FROM trusted_app_user_id
      OR replay_claim.canonical_display_name IS DISTINCT FROM canonical_name
    THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023',
        MESSAGE = 'organization creation idempotency conflict';
    END IF;

    RETURN QUERY
    SELECT
      'organization-creation:v1'::text,
      replay_claim.organization_workspace_id,
      replay_claim.organization_membership_id,
      replay_claim.organization_owner_assignment_id,
      replay_claim.created_at_utc;
    RETURN;
  END IF;

  creation_time := transaction_timestamp();
  workspace_id := gen_random_uuid();

  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-governance:' || workspace_id::text,
      0
    )
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-membership:' || workspace_id::text
        || ':' || trusted_app_user_id::text,
      0
    )
  );

  membership_id := gen_random_uuid();
  owner_assignment_id := gen_random_uuid();
  audit_event_id := gen_random_uuid();

  INSERT INTO app_data.workspaces (
    workspace_id,
    workspace_kind,
    display_name,
    personal_owner_app_user_id,
    created_at
  ) VALUES (
    workspace_id,
    'organization',
    canonical_name,
    NULL,
    creation_time
  );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    membership_id,
    workspace_id,
    trusted_app_user_id,
    creation_time,
    NULL
  );

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    owner_assignment_id,
    membership_id,
    creation_time,
    NULL
  );

  INSERT INTO app_private.organization_creation_request_claims (
    request_id,
    actor_app_user_id,
    canonical_display_name,
    organization_workspace_id,
    organization_membership_id,
    organization_owner_assignment_id,
    created_at_utc
  ) VALUES (
    requested_request_id,
    trusted_app_user_id,
    canonical_name,
    workspace_id,
    membership_id,
    owner_assignment_id,
    creation_time
  );

  INSERT INTO app_private.organization_creation_audit_events (
    organization_creation_audit_event_id,
    creation_contract_id,
    request_id,
    organization_workspace_id,
    organization_membership_id,
    organization_owner_assignment_id,
    created_at_utc
  ) VALUES (
    audit_event_id,
    'organization-creation:v1',
    requested_request_id,
    workspace_id,
    membership_id,
    owner_assignment_id,
    creation_time
  );

  RETURN QUERY
  SELECT
    'organization-creation:v1'::text,
    workspace_id,
    membership_id,
    owner_assignment_id,
    creation_time;
END
$function$;

CREATE FUNCTION app_data.create_organization_for_identity_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_request_id uuid,
  requested_display_name text
)
RETURNS TABLE (
  creation_contract_id text,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  organization_owner_assignment_id uuid,
  created_at_utc timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  resolved_app_user_id uuid;
BEGIN
  IF trusted_issuer IS NULL
    OR btrim(trusted_issuer) = ''
    OR char_length(trusted_issuer) > 2048
    OR trusted_subject IS NULL
    OR btrim(trusted_subject) = ''
    OR char_length(trusted_subject) > 512
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid organization creation identity';
  END IF;

  -- btrim above is only a non-empty input guard.  Identity lookup remains
  -- byte-for-byte exact and accepts only an existing active internal user.
  SELECT identity_row.app_user_id
  INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = identity_row.app_user_id
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
    AND app_user.status = 'active';

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'organization creation forbidden';
  END IF;

  RETURN QUERY
  SELECT result.creation_contract_id,
         result.organization_workspace_id,
         result.organization_membership_id,
         result.organization_owner_assignment_id,
         result.created_at_utc
  FROM app_private.create_organization_v1(
    resolved_app_user_id,
    requested_request_id,
    requested_display_name
  ) AS result;
END
$function$;

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_owner_assignment_history_v1(),
  app_private.validate_organization_owner_assignment_v1(),
  app_private.protect_organization_creation_request_claim_v1(),
  app_private.protect_organization_creation_audit_event_v1(),
  app_private.create_organization_v1(uuid, uuid, text),
  app_data.create_organization_for_identity_v1(text, text, uuid, text)
  FROM PUBLIC, tongxingzhe_runtime;

GRANT EXECUTE ON FUNCTION
  app_data.create_organization_for_identity_v1(text, text, uuid, text)
  TO tongxingzhe_runtime;

-- Keep both callable seams and their storage owned by the same non-runtime
-- role as the existing private organization membership validator.  Resolving
-- the role from pg_proc avoids introducing another restore-time role.
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
    'ALTER TABLE app_data.organization_owner_assignments OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_creation_request_claims OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER TABLE app_private.organization_creation_audit_events OWNER TO %I',
    trusted_owner
  );

  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_owner_assignment_history_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.validate_organization_owner_assignment_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_creation_request_claim_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_creation_audit_event_v1() OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.create_organization_v1(uuid,uuid,text) OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_data.create_organization_for_identity_v1(text,text,uuid,text) OWNER TO %I',
    trusted_owner
  );
END
$owner$;

COMMENT ON TABLE app_data.organization_owner_assignments
IS 'Append-only temporal organization owner assignments; owner is independent of project capability.';

COMMENT ON TABLE app_private.organization_creation_request_claims
IS 'Global live organization-creation request claims with exact replay payload and result IDs.';

COMMENT ON TABLE app_private.organization_creation_audit_events
IS 'PII-free organization creation success audit; one event per first successful request.';

COMMENT ON FUNCTION app_private.create_organization_v1(uuid, uuid, text)
IS 'Atomically creates one organization workspace, creator membership, first owner assignment, live request claim and PII-free audit.';

COMMENT ON FUNCTION
  app_data.create_organization_for_identity_v1(text, text, uuid, text)
IS 'Maps one exact active external identity to the private organization creation writer.';
