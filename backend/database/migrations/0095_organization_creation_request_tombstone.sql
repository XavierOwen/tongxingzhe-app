-- 0095_organization_creation_request_tombstone.sql
--
-- Slice 7AR adds only the creation family's terminal request fence.
-- It does not implement purge or authorize deletion of any live facts.

CREATE TABLE app_private.organization_creation_request_tombstones (
  claim_family text NOT NULL,
  request_id uuid NOT NULL,
  CONSTRAINT organization_creation_request_tombstones_pkey
    PRIMARY KEY (claim_family, request_id),
  CONSTRAINT organization_creation_request_tombstones_family_check
    CHECK (claim_family = 'organization-creation:v1')
);

REVOKE ALL PRIVILEGES ON TABLE
  app_private.organization_creation_request_tombstones
  FROM PUBLIC, tongxingzhe_runtime;

CREATE FUNCTION app_private.protect_organization_creation_request_tombstone_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'organization creation request tombstone is immutable';
END
$function$;

CREATE TRIGGER organization_creation_request_tombstones_immutable
BEFORE UPDATE OR DELETE
ON app_private.organization_creation_request_tombstones
FOR EACH ROW
EXECUTE FUNCTION
  app_private.protect_organization_creation_request_tombstone_v1();

REVOKE ALL PRIVILEGES ON FUNCTION
  app_private.protect_organization_creation_request_tombstone_v1()
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
    'ALTER TABLE app_private.organization_creation_request_tombstones OWNER TO %I',
    trusted_owner
  );
  EXECUTE format(
    'ALTER FUNCTION app_private.protect_organization_creation_request_tombstone_v1() OWNER TO %I',
    trusted_owner
  );
END
$owner$;

-- Replace the complete 0084 writer without changing its OID, owner or ACL.
-- The existing identity bridge remains the only runtime entry point.
CREATE OR REPLACE FUNCTION app_private.create_organization_v1(
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

  -- This is the global organization-creation namespace lock.  Tombstones and
  -- claims are checked before any actor or organization lock, so same-request
  -- retries have one deterministic serialization point.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(
      'organization-creation-request:' || requested_request_id::text,
      0
    )
  );

  PERFORM 1
  FROM app_private.organization_creation_request_tombstones AS tombstone
  WHERE tombstone.claim_family = 'organization-creation:v1'
    AND tombstone.request_id = requested_request_id;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'organization creation idempotency conflict';
  END IF;

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

COMMENT ON TABLE app_private.organization_creation_request_tombstones
IS 'Value-free terminal tombstones for the organization creation request family.';
