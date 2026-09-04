-- Synthetic rollback fixture for the 0086 organization owner transfer.
-- Every identity and business row is synthetic; the whole fixture rolls back.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

-- Seed all users as active first.  Membership creation intentionally requires
-- an active account; deletion_pending/deleted states are applied after the
-- valid membership rows have been installed.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0086-0000-0000-000000000001'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000002'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000003'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000004'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000005'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000006'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000007'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000008'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000009'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000010'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000011'::uuid, 'active'),
  ('00000000-0086-0000-0000-000000000012'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
VALUES
  (
    '00000000-0086-1000-0000-000000000001'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'sole-owner',
    '00000000-0086-0000-0000-000000000001'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000002'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'sole-target',
    '00000000-0086-0000-0000-000000000002'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000003'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'multi-owner',
    '00000000-0086-0000-0000-000000000003'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000004'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'multi-target',
    '00000000-0086-0000-0000-000000000004'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000005'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'multi-other-owner',
    '00000000-0086-0000-0000-000000000005'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000006'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'multi-non-owner',
    '00000000-0086-0000-0000-000000000006'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000008'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'deletion-pending-actor',
    '00000000-0086-0000-0000-000000000008'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000009'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'deleted-actor',
    '00000000-0086-0000-0000-000000000009'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000010'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'recovery-owner',
    '00000000-0086-0000-0000-000000000010'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000011'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'other-workspace-owner',
    '00000000-0086-0000-0000-000000000011'::uuid
  ),
  (
    '00000000-0086-1000-0000-000000000012'::uuid,
    'https://synthetic-0086.example/auth/v1',
    'recovery-target',
    '00000000-0086-0000-0000-000000000012'::uuid
  );

INSERT INTO app_data.workspaces (
  workspace_id,
  workspace_kind,
  display_name,
  personal_owner_app_user_id,
  deleted_at,
  created_at
)
VALUES
  (
    '00000000-0086-2000-0000-000000000001'::uuid,
    'organization',
    '0086 sole-owner organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  ),
  (
    '00000000-0086-2000-0000-000000000002'::uuid,
    'organization',
    '0086 multi-owner organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  ),
  (
    '00000000-0086-2000-0000-000000000003'::uuid,
    'organization',
    '0086 recovery organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  ),
  (
    '00000000-0086-2000-0000-000000000004'::uuid,
    'organization',
    '0086 other organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  );

-- The existing 0085 INSERT trigger requires a newly inserted assignment to
-- start at transaction_timestamp().  Seed legal, older current assignments
-- under replication role so this fixture can later prove a real close at the
-- current transaction timestamp.  Production triggers are restored before
-- any transfer call is made.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-0086-2100-0000-000000000001'::uuid,
    '00000000-0086-2000-0000-000000000001'::uuid,
    '00000000-0086-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000002'::uuid,
    '00000000-0086-2000-0000-000000000001'::uuid,
    '00000000-0086-0000-0000-000000000002'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000003'::uuid,
    '00000000-0086-2000-0000-000000000002'::uuid,
    '00000000-0086-0000-0000-000000000003'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000004'::uuid,
    '00000000-0086-2000-0000-000000000002'::uuid,
    '00000000-0086-0000-0000-000000000004'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000005'::uuid,
    '00000000-0086-2000-0000-000000000002'::uuid,
    '00000000-0086-0000-0000-000000000005'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000006'::uuid,
    '00000000-0086-2000-0000-000000000002'::uuid,
    '00000000-0086-0000-0000-000000000006'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000007'::uuid,
    '00000000-0086-2000-0000-000000000002'::uuid,
    '00000000-0086-0000-0000-000000000007'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000008'::uuid,
    '00000000-0086-2000-0000-000000000002'::uuid,
    '00000000-0086-0000-0000-000000000008'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000009'::uuid,
    '00000000-0086-2000-0000-000000000003'::uuid,
    '00000000-0086-0000-0000-000000000012'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000010'::uuid,
    '00000000-0086-2000-0000-000000000003'::uuid,
    '00000000-0086-0000-0000-000000000010'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2100-0000-000000000011'::uuid,
    '00000000-0086-2000-0000-000000000004'::uuid,
    '00000000-0086-0000-0000-000000000011'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  );

DO $seed_owner_assignments$
BEGIN
  PERFORM set_config('session_replication_role', 'replica', true);

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  )
  VALUES
    (
      '00000000-0086-2200-0000-000000000001'::uuid,
      '00000000-0086-2100-0000-000000000001'::uuid,
      transaction_timestamp() - interval '1 hour',
      NULL
    ),
    (
      '00000000-0086-2200-0000-000000000003'::uuid,
      '00000000-0086-2100-0000-000000000003'::uuid,
      transaction_timestamp() - interval '1 hour',
      NULL
    ),
    (
      '00000000-0086-2200-0000-000000000005'::uuid,
      '00000000-0086-2100-0000-000000000005'::uuid,
      transaction_timestamp() - interval '1 hour',
      NULL
    ),
    (
      '00000000-0086-2200-0000-000000000010'::uuid,
      '00000000-0086-2100-0000-000000000010'::uuid,
      transaction_timestamp() - interval '1 hour',
      NULL
    ),
    (
      '00000000-0086-2200-0000-000000000011'::uuid,
      '00000000-0086-2100-0000-000000000011'::uuid,
      transaction_timestamp() - interval '1 hour',
      NULL
    );

  PERFORM set_config('session_replication_role', 'origin', true);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('session_replication_role', 'origin', true);
  RAISE;
END
$seed_owner_assignments$;

-- These rows are valid memberships but not owners.  The transfer writer must
-- never create or alter project membership or capability facts.
INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default,
  created_at
)
VALUES (
  '00000000-0086-2300-0000-000000000002'::uuid,
  '00000000-0086-2000-0000-000000000002'::uuid,
  '0086 protected project',
  'active',
  false,
  transaction_timestamp() - interval '1 hour'
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-0086-2400-0000-000000000003'::uuid,
    '00000000-0086-2100-0000-000000000003'::uuid,
    '00000000-0086-2300-0000-000000000002'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2400-0000-000000000004'::uuid,
    '00000000-0086-2100-0000-000000000004'::uuid,
    '00000000-0086-2300-0000-000000000002'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-0086-2500-0000-000000000003'::uuid,
    '00000000-0086-2400-0000-000000000003'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-0086-2500-0000-000000000004'::uuid,
    '00000000-0086-2400-0000-000000000004'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '1 hour',
    NULL
  );

-- Apply the account/workspace states used by forbidden and recovery cases.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-0086-0000-0000-000000000008'::uuid;

UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '00000000-0086-0000-0000-000000000009'::uuid;

UPDATE app_data.organization_memberships
SET inactive_from_utc = transaction_timestamp() - interval '1 minute'
WHERE organization_membership_id =
  '00000000-0086-2100-0000-000000000007'::uuid;

UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp()
WHERE workspace_id = '00000000-0086-2000-0000-000000000003'::uuid;

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

CREATE TEMP TABLE fixture_0086_first (
  owner_transfer_contract_id text,
  organization_workspace_id uuid,
  previous_owner_assignment_id uuid,
  organization_owner_assignment_id uuid,
  effective_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0086_replay (
  owner_transfer_contract_id text,
  organization_workspace_id uuid,
  previous_owner_assignment_id uuid,
  organization_owner_assignment_id uuid,
  effective_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0086_multi (
  owner_transfer_contract_id text,
  organization_workspace_id uuid,
  previous_owner_assignment_id uuid,
  organization_owner_assignment_id uuid,
  effective_at_utc timestamptz
) ON COMMIT DROP;

GRANT ALL ON fixture_0086_first, fixture_0086_replay, fixture_0086_multi
  TO tongxingzhe_runtime;

-- Request identifiers are scoped by contract family.  Keep this creation
-- claim alive while the same request id is used by the transfer writer.
INSERT INTO app_private.organization_creation_request_claims (
  request_id,
  actor_app_user_id,
  canonical_display_name,
  organization_workspace_id,
  organization_membership_id,
  organization_owner_assignment_id,
  created_at_utc
)
VALUES (
  '00000000-0086-3000-0000-000000000001'::uuid,
  '00000000-0086-0000-0000-000000000001'::uuid,
  '0086 pre-existing creation claim',
  '00000000-0086-2000-0000-000000000001'::uuid,
  '00000000-0086-2100-0000-000000000001'::uuid,
  '00000000-0086-2200-0000-000000000001'::uuid,
  transaction_timestamp() - interval '30 minutes'
);

-- First execution and exact replay use the runtime identity bridge.  The
-- replay intentionally occurs after the actor has ceased to be owner.
SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0086_first
SELECT *
FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0086.example/auth/v1',
  'sole-owner',
  '00000000-0086-3000-0000-000000000001'::uuid,
  '00000000-0086-2000-0000-000000000001'::uuid,
  '00000000-0086-2100-0000-000000000002'::uuid
);

RESET ROLE;

CREATE TEMP TABLE fixture_0086_before_replay ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM app_data.organization_owner_assignments)
    AS owner_assignment_count,
  (SELECT count(*)
   FROM app_private.organization_owner_transfer_request_claims)
    AS claim_count,
  (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events)
    AS audit_count;

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0086_replay
SELECT *
FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0086.example/auth/v1',
  'sole-owner',
  '00000000-0086-3000-0000-000000000001'::uuid,
  '00000000-0086-2000-0000-000000000001'::uuid,
  '00000000-0086-2100-0000-000000000002'::uuid
);

RESET ROLE;

DO $first_transfer$
DECLARE
  first_row fixture_0086_first%ROWTYPE;
  replay_row fixture_0086_replay%ROWTYPE;
  before_replay record;
  after_owner_assignment_count bigint;
  after_claim_count bigint;
  after_audit_count bigint;
  current_owner_count bigint;
  old_inactive_at timestamptz;
  target_active_at timestamptz;
  stored_previous_assignment uuid;
  stored_new_assignment uuid;
  stored_effective_at timestamptz;
BEGIN
  SELECT * INTO STRICT first_row FROM fixture_0086_first;
  SELECT * INTO STRICT replay_row FROM fixture_0086_replay;

  IF (SELECT count(*)
      FROM app_private.organization_creation_request_claims AS creation_claim
      WHERE creation_claim.request_id =
        '00000000-0086-3000-0000-000000000001'::uuid) <> 1
  THEN
    RAISE EXCEPTION
      '0086 transfer did not coexist with the creation request family';
  END IF;

  IF first_row.owner_transfer_contract_id <>
      'organization-owner-transfer:v1'
    OR first_row.organization_workspace_id <>
      '00000000-0086-2000-0000-000000000001'::uuid
    OR first_row.previous_owner_assignment_id <>
      '00000000-0086-2200-0000-000000000001'::uuid
    OR first_row.organization_owner_assignment_id IS NULL
    OR first_row.effective_at_utc IS NULL
    OR NOT isfinite(first_row.effective_at_utc)
  THEN
    RAISE EXCEPTION '0086 first transfer returned an invalid receipt';
  END IF;

  IF ROW(
      replay_row.owner_transfer_contract_id,
      replay_row.organization_workspace_id,
      replay_row.previous_owner_assignment_id,
      replay_row.organization_owner_assignment_id,
      replay_row.effective_at_utc
    ) IS DISTINCT FROM ROW(
      first_row.owner_transfer_contract_id,
      first_row.organization_workspace_id,
      first_row.previous_owner_assignment_id,
      first_row.organization_owner_assignment_id,
      first_row.effective_at_utc
    )
  THEN
    RAISE EXCEPTION '0086 exact replay changed the transfer receipt';
  END IF;

  SELECT * INTO STRICT before_replay FROM fixture_0086_before_replay;
  SELECT count(*) INTO after_owner_assignment_count
  FROM app_data.organization_owner_assignments;
  SELECT count(*) INTO after_claim_count
  FROM app_private.organization_owner_transfer_request_claims;
  SELECT count(*) INTO after_audit_count
  FROM app_private.organization_owner_transfer_audit_events;
  IF after_owner_assignment_count <> before_replay.owner_assignment_count
    OR after_claim_count <> before_replay.claim_count
    OR after_audit_count <> before_replay.audit_count
  THEN
    RAISE EXCEPTION '0086 exact replay appended transfer facts';
  END IF;

  SELECT count(*) INTO current_owner_count
  FROM app_data.organization_owner_assignments AS owner_row
  JOIN app_data.organization_memberships AS membership_row
    ON membership_row.organization_membership_id =
      owner_row.organization_membership_id
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = membership_row.app_user_id
  WHERE membership_row.organization_workspace_id =
      first_row.organization_workspace_id
    AND tstzrange(
      membership_row.active_from_utc,
      membership_row.inactive_from_utc,
      '[)'
    ) @> first_row.effective_at_utc
    AND tstzrange(
      owner_row.active_from_utc,
      owner_row.inactive_from_utc,
      '[)'
    ) @> first_row.effective_at_utc
    AND user_row.status = 'active';
  IF current_owner_count <> 1 THEN
    RAISE EXCEPTION '0086 sole-owner transfer left % current owners',
      current_owner_count;
  END IF;

  SELECT inactive_from_utc INTO STRICT old_inactive_at
  FROM app_data.organization_owner_assignments
  WHERE organization_owner_assignment_id =
    first_row.previous_owner_assignment_id;
  IF old_inactive_at IS DISTINCT FROM first_row.effective_at_utc THEN
    RAISE EXCEPTION '0086 previous owner assignment was not closed';
  END IF;

  SELECT active_from_utc INTO STRICT target_active_at
  FROM app_data.organization_owner_assignments
  WHERE organization_owner_assignment_id =
    first_row.organization_owner_assignment_id;
  IF target_active_at IS DISTINCT FROM first_row.effective_at_utc THEN
    RAISE EXCEPTION '0086 target owner assignment has the wrong start time';
  END IF;

  SELECT
    claim_row.previous_owner_assignment_id,
    claim_row.organization_owner_assignment_id,
    claim_row.effective_at_utc
  INTO STRICT stored_previous_assignment, stored_new_assignment,
    stored_effective_at
  FROM app_private.organization_owner_transfer_request_claims AS claim_row
  WHERE claim_row.request_id =
    '00000000-0086-3000-0000-000000000001'::uuid;
  IF stored_previous_assignment <> first_row.previous_owner_assignment_id
    OR stored_new_assignment <> first_row.organization_owner_assignment_id
    OR stored_effective_at <> first_row.effective_at_utc
  THEN
    RAISE EXCEPTION '0086 transfer claim does not match the receipt';
  END IF;

  IF (SELECT count(*)
      FROM app_private.organization_owner_transfer_audit_events AS audit_row
      WHERE audit_row.request_id =
        '00000000-0086-3000-0000-000000000001'::uuid) <> 1
  THEN
    RAISE EXCEPTION '0086 first transfer did not append one audit event';
  END IF;
END
$first_transfer$;

-- Snapshot organization membership and project capability facts before the
-- multi-owner handoff.  The transfer may change owner assignments only.
CREATE TEMP TABLE fixture_0086_memberships_before ON COMMIT DROP AS
SELECT organization_membership_id, organization_workspace_id, app_user_id,
       active_from_utc, inactive_from_utc
FROM app_data.organization_memberships
WHERE organization_workspace_id =
  '00000000-0086-2000-0000-000000000002'::uuid;

CREATE TEMP TABLE fixture_0086_project_memberships_before ON COMMIT DROP AS
SELECT project_membership_id, organization_membership_id, project_id,
       active_from_utc, inactive_from_utc
FROM app_data.project_memberships
WHERE project_id = '00000000-0086-2300-0000-000000000002'::uuid;

CREATE TEMP TABLE fixture_0086_capabilities_before ON COMMIT DROP AS
SELECT capability_grant_id, project_membership_id, capability_id,
       active_from_utc, inactive_from_utc
FROM app_data.management_report_capability_grants
WHERE project_membership_id IN (
  '00000000-0086-2400-0000-000000000003'::uuid,
  '00000000-0086-2400-0000-000000000004'::uuid
);

SET LOCAL ROLE tongxingzhe_runtime;
INSERT INTO fixture_0086_multi
SELECT *
FROM app_data.transfer_organization_owner_for_identity_v1(
  'https://synthetic-0086.example/auth/v1',
  'multi-owner',
  '00000000-0086-3000-0000-000000000002'::uuid,
  '00000000-0086-2000-0000-000000000002'::uuid,
  '00000000-0086-2100-0000-000000000004'::uuid
);
RESET ROLE;

DO $multi_transfer$
DECLARE
  transfer_row fixture_0086_multi%ROWTYPE;
  current_owner_count bigint;
  other_owner_inactive_at timestamptz;
BEGIN
  SELECT * INTO STRICT transfer_row FROM fixture_0086_multi;
  IF transfer_row.owner_transfer_contract_id <>
      'organization-owner-transfer:v1'
    OR transfer_row.organization_workspace_id <>
      '00000000-0086-2000-0000-000000000002'::uuid
    OR transfer_row.previous_owner_assignment_id <>
      '00000000-0086-2200-0000-000000000003'::uuid
    OR transfer_row.organization_owner_assignment_id IS NULL
  THEN
    RAISE EXCEPTION '0086 multi-owner transfer returned an invalid receipt';
  END IF;

  SELECT count(*) INTO current_owner_count
  FROM app_data.organization_owner_assignments AS owner_row
  JOIN app_data.organization_memberships AS membership_row
    ON membership_row.organization_membership_id =
      owner_row.organization_membership_id
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = membership_row.app_user_id
  WHERE membership_row.organization_workspace_id =
      transfer_row.organization_workspace_id
    AND tstzrange(
      membership_row.active_from_utc,
      membership_row.inactive_from_utc,
      '[)'
    ) @> transfer_row.effective_at_utc
    AND tstzrange(
      owner_row.active_from_utc,
      owner_row.inactive_from_utc,
      '[)'
    ) @> transfer_row.effective_at_utc
    AND user_row.status = 'active';
  IF current_owner_count <> 2 THEN
    RAISE EXCEPTION '0086 multi-owner transfer left % current owners',
      current_owner_count;
  END IF;

  SELECT inactive_from_utc INTO STRICT other_owner_inactive_at
  FROM app_data.organization_owner_assignments
  WHERE organization_owner_assignment_id =
    '00000000-0086-2200-0000-000000000005'::uuid;
  IF other_owner_inactive_at IS NOT NULL THEN
    RAISE EXCEPTION '0086 transfer closed an unrelated current owner';
  END IF;

  IF EXISTS (
    SELECT * FROM fixture_0086_memberships_before
    EXCEPT ALL
    SELECT organization_membership_id, organization_workspace_id, app_user_id,
           active_from_utc, inactive_from_utc
    FROM app_data.organization_memberships
    WHERE organization_workspace_id =
      '00000000-0086-2000-0000-000000000002'::uuid
  ) OR EXISTS (
    SELECT organization_membership_id, organization_workspace_id, app_user_id,
           active_from_utc, inactive_from_utc
    FROM app_data.organization_memberships
    WHERE organization_workspace_id =
      '00000000-0086-2000-0000-000000000002'::uuid
    EXCEPT ALL
    SELECT * FROM fixture_0086_memberships_before
  ) THEN
    RAISE EXCEPTION '0086 transfer changed organization membership facts';
  END IF;

  IF EXISTS (
    SELECT * FROM fixture_0086_project_memberships_before
    EXCEPT ALL
    SELECT project_membership_id, organization_membership_id, project_id,
           active_from_utc, inactive_from_utc
    FROM app_data.project_memberships
    WHERE project_id = '00000000-0086-2300-0000-000000000002'::uuid
  ) OR EXISTS (
    SELECT project_membership_id, organization_membership_id, project_id,
           active_from_utc, inactive_from_utc
    FROM app_data.project_memberships
    WHERE project_id = '00000000-0086-2300-0000-000000000002'::uuid
    EXCEPT ALL
    SELECT * FROM fixture_0086_project_memberships_before
  ) THEN
    RAISE EXCEPTION '0086 transfer changed project membership facts';
  END IF;

  IF EXISTS (
    SELECT * FROM fixture_0086_capabilities_before
    EXCEPT ALL
    SELECT capability_grant_id, project_membership_id, capability_id,
           active_from_utc, inactive_from_utc
    FROM app_data.management_report_capability_grants
    WHERE project_membership_id IN (
      '00000000-0086-2400-0000-000000000003'::uuid,
      '00000000-0086-2400-0000-000000000004'::uuid
    )
  ) OR EXISTS (
    SELECT capability_grant_id, project_membership_id, capability_id,
           active_from_utc, inactive_from_utc
    FROM app_data.management_report_capability_grants
    WHERE project_membership_id IN (
      '00000000-0086-2400-0000-000000000003'::uuid,
      '00000000-0086-2400-0000-000000000004'::uuid
    )
    EXCEPT ALL
    SELECT * FROM fixture_0086_capabilities_before
  ) THEN
    RAISE EXCEPTION '0086 transfer changed capability facts';
  END IF;
END
$multi_transfer$;

CREATE OR REPLACE FUNCTION pg_temp.expect_0086_failure(
  case_name text,
  expected_sqlstate text,
  expected_message text,
  statement text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
  actual_sqlstate text;
  actual_message text;
BEGIN
  BEGIN
    EXECUTE statement;
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      actual_sqlstate = RETURNED_SQLSTATE,
      actual_message = MESSAGE_TEXT;
    SET CONSTRAINTS ALL DEFERRED;

    IF actual_sqlstate IS DISTINCT FROM expected_sqlstate
      OR (
        expected_message IS NOT NULL
        AND actual_message IS DISTINCT FROM expected_message
      )
    THEN
      RAISE EXCEPTION
        '0086 % expected SQLSTATE/message %, % but got %, %',
        case_name,
        expected_sqlstate,
        expected_message,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0086 % unexpectedly succeeded', case_name;
END
$function$;

-- A request tombstone blocks a new transfer intent, including for an actor
-- who is no longer the owner.  This request is in the transfer namespace and
-- is independent from the 0084 organization-creation namespace.
INSERT INTO app_private.organization_owner_transfer_request_tombstones (
  claim_family,
  request_id
)
VALUES (
  'organization-owner-transfer:v1',
  '00000000-0086-3000-0000-000000000013'::uuid
);

-- All rejected requests below must leave every transfer fact set unchanged.
CREATE TEMP TABLE fixture_0086_failure_counts AS
SELECT
  (SELECT count(*) FROM app_data.organization_owner_assignments)
    AS owner_assignment_count,
  (SELECT count(*)
   FROM app_private.organization_owner_transfer_request_claims)
    AS claim_count,
  (SELECT count(*)
   FROM app_private.organization_owner_transfer_request_tombstones)
    AS tombstone_count,
  (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events)
    AS audit_count,
  (SELECT count(*) FROM app_data.organization_memberships)
    AS membership_count,
  (SELECT count(*) FROM app_data.project_memberships)
    AS project_membership_count,
  (SELECT count(*) FROM app_data.management_report_capability_grants)
    AS capability_count;

SELECT pg_temp.expect_0086_failure(
  'actor drift',
  '22023',
  'organization owner transfer idempotency conflict',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000002') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'target drift',
  '22023',
  'organization owner transfer idempotency conflict',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000001') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'workspace drift',
  '22023',
  'organization owner transfer idempotency conflict',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'NULL request id',
  '22023',
  'invalid organization owner transfer request',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000005') || '::uuid, '
    || 'NULL::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'NULL workspace id',
  '22023',
  'invalid organization owner transfer request',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000003') || '::uuid, '
    || 'NULL::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'NULL target membership id',
  '22023',
  'invalid organization owner transfer request',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || 'NULL::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'non-owner actor',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000006') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'cross-organization target',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000006') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'inactive target membership',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000007') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000007') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'deletion_pending actor',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000008') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000008') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'deleted actor',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000009') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000009') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'organization recovery period',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000010') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000010') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000003') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000009') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'target already owner',
  '22023',
  'organization owner transfer target already owner',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000005') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'actor equals target',
  '22023',
  'organization owner transfer target already owner',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000012') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'transfer tombstone',
  '22023',
  'organization owner transfer idempotency conflict',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000013') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000002') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'unknown exact identity',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_data.transfer_organization_owner_for_identity_v1('
    || quote_literal('https://synthetic-0086.example/auth/v1') || ', '
    || quote_literal('unknown-exact') || ', '
    || quote_literal('00000000-0086-3000-0000-000000000014') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000011') || '::uuid)'
);

SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0086_failure(
  'inactive exact identity',
  '42501',
  'organization owner transfer forbidden',
  'SELECT count(*) FROM app_data.transfer_organization_owner_for_identity_v1('
    || quote_literal('https://synthetic-0086.example/auth/v1') || ', '
    || quote_literal('deletion-pending-actor') || ', '
    || quote_literal('00000000-0086-3000-0000-000000000019') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000004') || '::uuid)'
);

RESET ROLE;

SELECT pg_temp.expect_0086_failure(
  'NULL identity issuer',
  '22023',
  'invalid organization owner transfer identity',
  'SELECT count(*) FROM app_data.transfer_organization_owner_for_identity_v1('
    || 'NULL::text, '
    || quote_literal('other-workspace-owner') || ', '
    || quote_literal('00000000-0086-3000-0000-000000000015') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'blank identity subject',
  '22023',
  'invalid organization owner transfer identity',
  'SELECT count(*) FROM app_data.transfer_organization_owner_for_identity_v1('
    || quote_literal('https://synthetic-0086.example/auth/v1') || ', '
    || quote_literal('   ') || ', '
    || quote_literal('00000000-0086-3000-0000-000000000016') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000011') || '::uuid)'
);

DO $failure_counts$
DECLARE
  before_counts fixture_0086_failure_counts%ROWTYPE;
  after_counts fixture_0086_failure_counts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0086_failure_counts;
  SELECT
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*)
     FROM app_private.organization_owner_transfer_request_claims),
    (SELECT count(*)
     FROM app_private.organization_owner_transfer_request_tombstones),
    (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.project_memberships),
    (SELECT count(*) FROM app_data.management_report_capability_grants)
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts THEN
    RAISE EXCEPTION
      '0086 failed transfer wrote partial facts: before %, after %',
      before_counts,
      after_counts;
  END IF;
END
$failure_counts$;

-- The live claim permits only the one account-deletion detachment exception;
-- all other fields remain immutable.  History tables are append-only.
UPDATE app_private.organization_owner_transfer_request_claims
SET actor_app_user_id = NULL
WHERE request_id = '00000000-0086-3000-0000-000000000001'::uuid;

CREATE TEMP TABLE fixture_0086_detached_replay_counts AS
SELECT * FROM fixture_0086_failure_counts;

SELECT pg_temp.expect_0086_failure(
  'detached claim replay',
  '22023',
  'organization owner transfer idempotency conflict',
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000002') || '::uuid)'
);

DO $detached_replay_counts$
DECLARE
  before_counts fixture_0086_failure_counts%ROWTYPE;
  after_counts fixture_0086_failure_counts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0086_detached_replay_counts;
  SELECT
    (SELECT count(*) FROM app_data.organization_owner_assignments),
    (SELECT count(*)
     FROM app_private.organization_owner_transfer_request_claims),
    (SELECT count(*)
     FROM app_private.organization_owner_transfer_request_tombstones),
    (SELECT count(*) FROM app_private.organization_owner_transfer_audit_events),
    (SELECT count(*) FROM app_data.organization_memberships),
    (SELECT count(*) FROM app_data.project_memberships),
    (SELECT count(*) FROM app_data.management_report_capability_grants)
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts THEN
    RAISE EXCEPTION '0086 detached replay wrote transfer facts';
  END IF;
END
$detached_replay_counts$;

SELECT pg_temp.expect_0086_failure(
  'detached claim actor reattachment',
  '55000',
  'organization owner transfer request claim is immutable',
  'UPDATE app_private.organization_owner_transfer_request_claims '
    || 'SET actor_app_user_id = '
    || quote_literal('00000000-0086-0000-0000-000000000002') || '::uuid '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid'
);

SELECT pg_temp.expect_0086_failure(
  'transfer claim payload update',
  '55000',
  'organization owner transfer request claim is immutable',
  'UPDATE app_private.organization_owner_transfer_request_claims '
    || 'SET target_organization_membership_id = '
    || quote_literal('00000000-0086-2100-0000-000000000001') || '::uuid '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000002') || '::uuid'
);

SELECT pg_temp.expect_0086_failure(
  'transfer claim delete',
  '55000',
  'organization owner transfer request claim cannot be deleted',
  'DELETE FROM app_private.organization_owner_transfer_request_claims '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000002') || '::uuid'
);

SELECT pg_temp.expect_0086_failure(
  'transfer tombstone update',
  '55000',
  'organization owner transfer request tombstone is immutable',
  'UPDATE app_private.organization_owner_transfer_request_tombstones '
    || 'SET request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000017') || '::uuid '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000013') || '::uuid'
);

SELECT pg_temp.expect_0086_failure(
  'transfer tombstone delete',
  '55000',
  'organization owner transfer request tombstone is immutable',
  'DELETE FROM app_private.organization_owner_transfer_request_tombstones '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000013') || '::uuid'
);

SELECT pg_temp.expect_0086_failure(
  'transfer audit update',
  '55000',
  'organization owner transfer audit is append-only',
  'UPDATE app_private.organization_owner_transfer_audit_events '
    || 'SET request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000017') || '::uuid '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid'
);

SELECT pg_temp.expect_0086_failure(
  'transfer audit delete',
  '55000',
  'organization owner transfer audit is append-only',
  'DELETE FROM app_private.organization_owner_transfer_audit_events '
    || 'WHERE request_id = '
    || quote_literal('00000000-0086-3000-0000-000000000001') || '::uuid'
);

-- Runtime receives only the exact identity bridge; it cannot invoke the
-- private writer, inspect transfer storage, or inspect owner assignment data.
SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0086_failure(
  'runtime private writer ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.transfer_organization_owner_v1('
    || quote_literal('00000000-0086-0000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-0086-3000-0000-000000000018') || '::uuid, '
    || quote_literal('00000000-0086-2000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-0086-2100-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0086_failure(
  'runtime transfer claims table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_owner_transfer_request_claims'
);

SELECT pg_temp.expect_0086_failure(
  'runtime transfer tombstones table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_owner_transfer_request_tombstones'
);

SELECT pg_temp.expect_0086_failure(
  'runtime transfer audit table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_owner_transfer_audit_events'
);

SELECT pg_temp.expect_0086_failure(
  'runtime owner assignment table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.organization_owner_assignments'
);

RESET ROLE;

DO $acl$
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.transfer_organization_owner_for_identity_v1(text,text,uuid,uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '0086 runtime identity bridge EXECUTE privilege is missing';
  END IF;

  IF has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)',
      'EXECUTE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.organization_owner_transfer_request_claims',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.organization_owner_transfer_request_tombstones',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.organization_owner_transfer_audit_events',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.organization_owner_assignments',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION '0086 runtime received a private function/table privilege';
  END IF;

  IF has_function_privilege(
      'public',
      'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)',
      'EXECUTE'
    ) OR has_function_privilege(
      'public',
      'app_data.transfer_organization_owner_for_identity_v1(text,text,uuid,uuid,uuid)',
      'EXECUTE'
    ) OR has_table_privilege(
      'public',
      'app_private.organization_owner_transfer_request_claims',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION '0086 PUBLIC received an owner-transfer privilege';
  END IF;
END
$acl$;

ROLLBACK;
