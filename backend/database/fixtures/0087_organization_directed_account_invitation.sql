-- Synthetic rollback fixture for the 0087 directed account invitation.
-- Every identity and business row is synthetic; the whole fixture rolls back.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

-- Seed active accounts first.  The two accounts used for the deletion cases
-- are changed after their valid invitations have been issued.
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-8701-0000-0000-000000000001'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000002'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000003'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000004'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000005'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000006'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000007'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000008'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000009'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000010'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000011'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000012'::uuid, 'active'),
  ('00000000-8701-0000-0000-000000000013'::uuid, 'active');

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
VALUES
  (
    '00000000-8701-1000-0000-000000000001'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'main-owner',
    '00000000-8701-0000-0000-000000000001'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000002'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'main-target',
    '00000000-8701-0000-0000-000000000002'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000003'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'main-non-owner',
    '00000000-8701-0000-0000-000000000003'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000004'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'current-member',
    '00000000-8701-0000-0000-000000000004'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000005'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'history-target',
    '00000000-8701-0000-0000-000000000005'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000006'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'deletion-pending-target',
    '00000000-8701-0000-0000-000000000006'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000007'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'deleted-target',
    '00000000-8701-0000-0000-000000000007'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000008'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'recovery-target',
    '00000000-8701-0000-0000-000000000008'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000009'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'recovery-owner',
    '00000000-8701-0000-0000-000000000009'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000010'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'other-owner',
    '00000000-8701-0000-0000-000000000010'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000011'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'expired-target',
    '00000000-8701-0000-0000-000000000011'::uuid
  ),
  (
    '00000000-8701-1000-0000-000000000012'::uuid,
    'https://synthetic-8701.example/auth/v1',
    'race-target',
    '00000000-8701-0000-0000-000000000012'::uuid
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
    '00000000-8701-2000-0000-000000000001'::uuid,
    'organization',
    '8701 live organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  ),
  (
    '00000000-8701-2000-0000-000000000002'::uuid,
    'organization',
    '8701 recovery organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  ),
  (
    '00000000-8701-2000-0000-000000000003'::uuid,
    'organization',
    '8701 other organization',
    NULL,
    NULL,
    transaction_timestamp() - interval '1 hour'
  ),
  (
    '00000000-8701-2000-0000-000000000004'::uuid,
    'personal',
    '8701 personal workspace',
    '00000000-8701-0000-0000-000000000001'::uuid,
    NULL,
    transaction_timestamp() - interval '1 hour'
  );

-- History is legal membership data: it is closed before the fixture begins,
-- while every current membership is an older row with an open end.
INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-8701-3100-0000-000000000001'::uuid,
    '00000000-8701-2000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-8701-3100-0000-000000000003'::uuid,
    '00000000-8701-2000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000003'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-8701-3100-0000-000000000004'::uuid,
    '00000000-8701-2000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000004'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-8701-3100-0000-000000000005'::uuid,
    '00000000-8701-2000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000005'::uuid,
    transaction_timestamp() - interval '3 hours',
    transaction_timestamp() - interval '2 hours'
  ),
  (
    '00000000-8701-3100-0000-000000000009'::uuid,
    '00000000-8701-2000-0000-000000000002'::uuid,
    '00000000-8701-0000-0000-000000000009'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-8701-3100-0000-000000000008'::uuid,
    '00000000-8701-2000-0000-000000000002'::uuid,
    '00000000-8701-0000-0000-000000000008'::uuid,
    transaction_timestamp() - interval '171 hours',
    NULL
  ),
  (
    '00000000-8701-3100-0000-000000000010'::uuid,
    '00000000-8701-2000-0000-000000000003'::uuid,
    '00000000-8701-0000-0000-000000000010'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  );

-- Owner assignments must be current at insert time.  The existing 0085
-- validator accepts these rows directly and keeps the fixture on production
-- governance/temporal paths without disabling triggers.
INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES
  (
    '00000000-8701-3200-0000-000000000001'::uuid,
    '00000000-8701-3100-0000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  ),
  (
    '00000000-8701-3200-0000-000000000009'::uuid,
    '00000000-8701-3100-0000-000000000009'::uuid,
    transaction_timestamp(),
    NULL
  ),
  (
    '00000000-8701-3200-0000-000000000010'::uuid,
    '00000000-8701-3100-0000-000000000010'::uuid,
    transaction_timestamp(),
    NULL
  );

-- Protected project facts prove that accepting an invitation does not grant
-- project access or capabilities.
INSERT INTO app_data.projects (
  project_id,
  workspace_id,
  display_name,
  status,
  is_personal_default,
  created_at
)
VALUES (
  '00000000-8701-3300-0000-000000000001'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '8701 protected project',
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
    '00000000-8701-3400-0000-000000000003'::uuid,
    '00000000-8701-3100-0000-000000000003'::uuid,
    '00000000-8701-3300-0000-000000000001'::uuid,
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-8701-3400-0000-000000000004'::uuid,
    '00000000-8701-3100-0000-000000000004'::uuid,
    '00000000-8701-3300-0000-000000000001'::uuid,
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
    '00000000-8701-3500-0000-000000000003'::uuid,
    '00000000-8701-3400-0000-000000000003'::uuid,
    'view_anonymous_analytics',
    transaction_timestamp() - interval '1 hour',
    NULL
  ),
  (
    '00000000-8701-3500-0000-000000000004'::uuid,
    '00000000-8701-3400-0000-000000000004'::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '1 hour',
    NULL
  );

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

CREATE TEMP TABLE fixture_0087_create (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0087_create_replay (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0087_accept (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0087_accept_replay (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0087_history_accept (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0087_recovery_create_replay (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  issued_at_utc timestamptz,
  expires_at_utc timestamptz
) ON COMMIT DROP;

CREATE TEMP TABLE fixture_0087_recovery_accept_replay (
  organization_invitation_contract_id text,
  invitation_id uuid,
  organization_workspace_id uuid,
  organization_membership_id uuid,
  accepted_at_utc timestamptz
) ON COMMIT DROP;

GRANT ALL ON
  fixture_0087_create,
  fixture_0087_create_replay,
  fixture_0087_accept,
  fixture_0087_accept_replay,
  fixture_0087_history_accept,
  fixture_0087_recovery_create_replay,
  fixture_0087_recovery_accept_replay
TO tongxingzhe_runtime;

-- First create/accept use the runtime role's only two allowed entry points.
SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0087_create
SELECT *
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000001'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000002'::uuid
);

INSERT INTO fixture_0087_accept
SELECT *
FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-target',
  '00000000-8701-3000-0000-000000000001'::uuid
);

INSERT INTO fixture_0087_accept_replay
SELECT *
FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-target',
  '00000000-8701-3000-0000-000000000001'::uuid
);

-- Create replay remains valid after acceptance and after the target became a
-- current member; it must not re-check target membership or append audit.
INSERT INTO fixture_0087_create_replay
SELECT *
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000001'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000002'::uuid
);

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000005'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000005'::uuid
);

INSERT INTO fixture_0087_history_accept
SELECT *
FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'history-target',
  '00000000-8701-3000-0000-000000000005'::uuid
);

RESET ROLE;

-- An accepted claim tied to the disposable account exercises ON DELETE SET
-- NULL on an inviter reference during an exact replay.
INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
VALUES (
  '00000000-8701-3000-0000-000000000019'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000013'::uuid,
  '00000000-8701-0000-0000-000000000002'::uuid,
  transaction_timestamp() - interval '338 hours',
  transaction_timestamp() - interval '170 hours',
  transaction_timestamp() - interval '171 hours',
  (SELECT organization_membership_id FROM fixture_0087_accept)
);

DO $valid_results$
DECLARE
  create_row fixture_0087_create%ROWTYPE;
  create_replay_row fixture_0087_create_replay%ROWTYPE;
  accept_row fixture_0087_accept%ROWTYPE;
  accept_replay_row fixture_0087_accept_replay%ROWTYPE;
  history_row fixture_0087_history_accept%ROWTYPE;
  audit_column text;
BEGIN
  SELECT * INTO STRICT create_row FROM fixture_0087_create;
  SELECT * INTO STRICT create_replay_row FROM fixture_0087_create_replay;
  SELECT * INTO STRICT accept_row FROM fixture_0087_accept;
  SELECT * INTO STRICT accept_replay_row FROM fixture_0087_accept_replay;
  SELECT * INTO STRICT history_row FROM fixture_0087_history_accept;

  IF create_row.organization_invitation_contract_id <>
      'organization-directed-account-invitation:v1'
    OR create_row.invitation_id <>
      '00000000-8701-3000-0000-000000000001'::uuid
    OR create_row.organization_workspace_id <>
      '00000000-8701-2000-0000-000000000001'::uuid
    OR create_row.issued_at_utc IS NULL
    OR create_row.expires_at_utc IS NULL
    OR NOT isfinite(create_row.issued_at_utc)
    OR NOT isfinite(create_row.expires_at_utc)
    OR create_row.issued_at_utc IS DISTINCT FROM transaction_timestamp()
    OR create_row.expires_at_utc - create_row.issued_at_utc <>
      interval '168 hours'
  THEN
    RAISE EXCEPTION '0087 first create returned an invalid receipt';
  END IF;

  IF ROW(
      create_replay_row.organization_invitation_contract_id,
      create_replay_row.invitation_id,
      create_replay_row.organization_workspace_id,
      create_replay_row.issued_at_utc,
      create_replay_row.expires_at_utc
    ) IS DISTINCT FROM ROW(
      create_row.organization_invitation_contract_id,
      create_row.invitation_id,
      create_row.organization_workspace_id,
      create_row.issued_at_utc,
      create_row.expires_at_utc
    )
  THEN
    RAISE EXCEPTION '0087 exact create replay changed the invitation receipt';
  END IF;

  IF accept_row.organization_invitation_contract_id <>
      'organization-directed-account-invitation:v1'
    OR accept_row.invitation_id <> create_row.invitation_id
    OR accept_row.organization_workspace_id <>
      create_row.organization_workspace_id
    OR accept_row.organization_membership_id IS NULL
    OR accept_row.accepted_at_utc IS NULL
    OR NOT isfinite(accept_row.accepted_at_utc)
    OR accept_row.accepted_at_utc IS DISTINCT FROM transaction_timestamp()
  THEN
    RAISE EXCEPTION '0087 first accept returned an invalid receipt';
  END IF;

  IF ROW(
      accept_replay_row.organization_invitation_contract_id,
      accept_replay_row.invitation_id,
      accept_replay_row.organization_workspace_id,
      accept_replay_row.organization_membership_id,
      accept_replay_row.accepted_at_utc
    ) IS DISTINCT FROM ROW(
      accept_row.organization_invitation_contract_id,
      accept_row.invitation_id,
      accept_row.organization_workspace_id,
      accept_row.organization_membership_id,
      accept_row.accepted_at_utc
    )
  THEN
    RAISE EXCEPTION '0087 exact accept replay changed the membership receipt';
  END IF;

  IF history_row.organization_membership_id IS NULL
    OR history_row.invitation_id <>
      '00000000-8701-3000-0000-000000000005'::uuid
  THEN
    RAISE EXCEPTION '0087 history invitation did not accept';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'app_private'
      AND column_row.table_name =
        'organization_directed_account_invitation_audit_events'
      AND column_row.column_name NOT IN (
        'organization_invitation_audit_event_id',
        'organization_invitation_contract_id',
        'invitation_id',
        'organization_workspace_id',
        'event_kind',
        'organization_membership_id',
        'occurred_at_utc'
      )
  ) THEN
    SELECT column_row.column_name INTO audit_column
    FROM information_schema.columns AS column_row
    WHERE column_row.table_schema = 'app_private'
      AND column_row.table_name =
        'organization_directed_account_invitation_audit_events'
      AND column_row.column_name NOT IN (
        'organization_invitation_audit_event_id',
        'organization_invitation_contract_id',
        'invitation_id',
        'organization_workspace_id',
        'event_kind',
        'organization_membership_id',
        'occurred_at_utc'
      )
    ORDER BY column_row.ordinal_position
    LIMIT 1;
    RAISE EXCEPTION '0087 audit has an uncontracted column: %', audit_column;
  END IF;
END
$valid_results$;

-- The same UUID is independent in the creation, invitation, and owner
-- transfer claim families.
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
  '00000000-8701-3000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000001'::uuid,
  '8701 shared creation claim',
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-3100-0000-000000000001'::uuid,
  '00000000-8701-3200-0000-000000000001'::uuid,
  transaction_timestamp()
);

INSERT INTO app_private.organization_owner_transfer_request_claims (
  request_id,
  actor_app_user_id,
  organization_workspace_id,
  target_organization_membership_id,
  previous_owner_assignment_id,
  organization_owner_assignment_id,
  effective_at_utc
)
VALUES (
  '00000000-8701-3000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000001'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-3100-0000-000000000004'::uuid,
  '00000000-8701-3200-0000-000000000001'::uuid,
  '00000000-8701-3200-0000-000000000001'::uuid,
  transaction_timestamp()
);

-- An already-accepted, already-expired claim is used later to prove that an
-- exact target replay remains read-only even after expiry and recovery.
INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
VALUES (
  '00000000-8701-3000-0000-000000000014'::uuid,
  '00000000-8701-2000-0000-000000000002'::uuid,
  '00000000-8701-0000-0000-000000000009'::uuid,
  '00000000-8701-0000-0000-000000000008'::uuid,
  transaction_timestamp() - interval '338 hours',
  transaction_timestamp() - interval '170 hours',
  transaction_timestamp() - interval '171 hours',
  '00000000-8701-3100-0000-000000000008'::uuid
);

INSERT INTO app_private.organization_directed_account_invitation_audit_events (
  organization_invitation_audit_event_id,
  organization_invitation_contract_id,
  invitation_id,
  organization_workspace_id,
  event_kind,
  organization_membership_id,
  occurred_at_utc
)
VALUES (
  '00000000-8701-4000-0000-000000000014'::uuid,
  'organization-directed-account-invitation:v1',
  '00000000-8701-3000-0000-000000000014'::uuid,
  '00000000-8701-2000-0000-000000000002'::uuid,
  'invitation_accepted',
  '00000000-8701-3100-0000-000000000008'::uuid,
  transaction_timestamp() - interval '171 hours'
);

-- These two pending claims let the fixture exercise the actual FK
-- ON DELETE SET NULL action without touching an account that owns a
-- membership or workspace.
INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
VALUES
  (
    '00000000-8701-3000-0000-000000000017'::uuid,
    '00000000-8701-2000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000013'::uuid,
    '00000000-8701-0000-0000-000000000002'::uuid,
    transaction_timestamp(),
    transaction_timestamp() + interval '168 hours',
    NULL,
    NULL
  ),
  (
    '00000000-8701-3000-0000-000000000018'::uuid,
    '00000000-8701-2000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000013'::uuid,
    transaction_timestamp(),
    transaction_timestamp() + interval '168 hours',
    NULL,
    NULL
  );

-- Issue valid invitations for later state-transition and failure cases while
-- the target accounts and recovery workspace are still usable.
SET LOCAL ROLE tongxingzhe_runtime;

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000006'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000012'::uuid
);

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000008'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000006'::uuid
);

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000009'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000007'::uuid
);

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'recovery-owner',
  '00000000-8701-3000-0000-000000000010'::uuid,
  '00000000-8701-2000-0000-000000000002'::uuid,
  '00000000-8701-0000-0000-000000000011'::uuid
);

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000015'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000011'::uuid
);

SELECT count(*)
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'main-owner',
  '00000000-8701-3000-0000-000000000016'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000008'::uuid
);

RESET ROLE;

-- A live claim whose expiry is already in the past exercises acceptance
-- expiry without mutating a writer-created timestamp.
INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
VALUES (
  '00000000-8701-3000-0000-000000000011'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000011'::uuid,
  transaction_timestamp() - interval '169 hours',
  transaction_timestamp() - interval '1 hour',
  NULL,
  NULL
);

INSERT INTO app_private.organization_directed_account_invitation_request_tombstones (
  claim_family,
  invitation_id
)
VALUES
  (
    'organization-directed-account-invitation:v1',
    '00000000-8701-3000-0000-000000000012'::uuid
  ),
  (
    'organization-directed-account-invitation:v1',
    '00000000-8701-3000-0000-000000000013'::uuid
  );

-- The status and recovery transitions happen after claims exist, so the
-- failures prove lock-after re-read rather than an early pre-check only.
UPDATE app_data.app_users
SET status = 'deletion_pending'
WHERE app_user_id = '00000000-8701-0000-0000-000000000006'::uuid;

UPDATE app_data.app_users
SET status = 'deleted'
WHERE app_user_id = '00000000-8701-0000-0000-000000000007'::uuid;

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '00000000-8701-3100-0000-000000000012'::uuid,
  '00000000-8701-2000-0000-000000000001'::uuid,
  '00000000-8701-0000-0000-000000000012'::uuid,
  transaction_timestamp() - interval '1 minute',
  NULL
);

UPDATE app_data.workspaces
SET deleted_at = transaction_timestamp()
WHERE workspace_id = '00000000-8701-2000-0000-000000000002'::uuid;

-- Exact create replay remains a receipt-only read after recovery, and exact
-- accepted replay remains valid after expiry and recovery deletion.
SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO fixture_0087_recovery_create_replay
SELECT *
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'recovery-owner',
  '00000000-8701-3000-0000-000000000010'::uuid,
  '00000000-8701-2000-0000-000000000002'::uuid,
  '00000000-8701-0000-0000-000000000011'::uuid
);

INSERT INTO fixture_0087_recovery_accept_replay
SELECT *
FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-8701.example/auth/v1',
  'recovery-target',
  '00000000-8701-3000-0000-000000000014'::uuid
);

RESET ROLE;

DO $recovery_replays$
DECLARE
  create_replay_row fixture_0087_recovery_create_replay%ROWTYPE;
  accept_replay_row fixture_0087_recovery_accept_replay%ROWTYPE;
BEGIN
  SELECT * INTO STRICT create_replay_row
  FROM fixture_0087_recovery_create_replay;
  IF ROW(
      create_replay_row.organization_invitation_contract_id,
      create_replay_row.invitation_id,
      create_replay_row.organization_workspace_id,
      create_replay_row.issued_at_utc,
      create_replay_row.expires_at_utc
    ) IS DISTINCT FROM ROW(
      'organization-directed-account-invitation:v1'::text,
      '00000000-8701-3000-0000-000000000010'::uuid,
      '00000000-8701-2000-0000-000000000002'::uuid,
      (SELECT issued_at_utc
       FROM app_private.organization_directed_account_invitation_request_claims
       WHERE invitation_id =
         '00000000-8701-3000-0000-000000000010'::uuid),
      (SELECT expires_at_utc
       FROM app_private.organization_directed_account_invitation_request_claims
       WHERE invitation_id =
         '00000000-8701-3000-0000-000000000010'::uuid)
    )
  THEN
    RAISE EXCEPTION '0087 recovery create replay changed the receipt';
  END IF;

  SELECT * INTO STRICT accept_replay_row
  FROM fixture_0087_recovery_accept_replay;
  IF ROW(
      accept_replay_row.organization_invitation_contract_id,
      accept_replay_row.invitation_id,
      accept_replay_row.organization_workspace_id,
      accept_replay_row.organization_membership_id,
      accept_replay_row.accepted_at_utc
    ) IS DISTINCT FROM ROW(
      'organization-directed-account-invitation:v1'::text,
      '00000000-8701-3000-0000-000000000014'::uuid,
      '00000000-8701-2000-0000-000000000002'::uuid,
      '00000000-8701-3100-0000-000000000008'::uuid,
      (SELECT accepted_at_utc
       FROM app_private.organization_directed_account_invitation_request_claims
       WHERE invitation_id =
         '00000000-8701-3000-0000-000000000014'::uuid)
    )
  THEN
    RAISE EXCEPTION '0087 recovery accepted replay changed the receipt';
  END IF;
END
$recovery_replays$;

-- Private acceptance also rejects a pending claim whose workspace is either
-- personal or unknown; neither selector is an organization invitation target.
INSERT INTO app_private.organization_directed_account_invitation_request_claims (
  invitation_id,
  organization_workspace_id,
  inviter_app_user_id,
  target_app_user_id,
  issued_at_utc,
  expires_at_utc,
  accepted_at_utc,
  accepted_organization_membership_id
)
VALUES
  (
    '00000000-8701-3000-0000-000000000028'::uuid,
    '00000000-8701-2000-0000-000000000004'::uuid,
    '00000000-8701-0000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000011'::uuid,
    transaction_timestamp(),
    transaction_timestamp() + interval '168 hours',
    NULL,
    NULL
  ),
  (
    '00000000-8701-3000-0000-000000000029'::uuid,
    '00000000-8701-2000-0000-000000009999'::uuid,
    '00000000-8701-0000-0000-000000000001'::uuid,
    '00000000-8701-0000-0000-000000000011'::uuid,
    transaction_timestamp(),
    transaction_timestamp() + interval '168 hours',
    NULL,
    NULL
  );

-- The FK action itself may detach either side, but it cannot make a claim
-- acceptable again.
DELETE FROM app_data.app_users
WHERE app_user_id = '00000000-8701-0000-0000-000000000013'::uuid;

DO $fk_deassociation$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_request_claims
    WHERE invitation_id IN (
        '00000000-8701-3000-0000-000000000017'::uuid,
        '00000000-8701-3000-0000-000000000019'::uuid
      )
      AND inviter_app_user_id IS NOT NULL
  ) OR EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_request_claims
    WHERE invitation_id = '00000000-8701-3000-0000-000000000018'::uuid
      AND target_app_user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION '0087 ON DELETE SET NULL did not detach invitation identity';
  END IF;
END
$fk_deassociation$;

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

CREATE OR REPLACE FUNCTION pg_temp.expect_0087_failure(
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
        '0087 % expected SQLSTATE/message %, % but got %, %',
        case_name,
        expected_sqlstate,
        expected_message,
        actual_sqlstate,
        actual_message;
    END IF;
    RETURN;
  END;

  RAISE EXCEPTION '0087 % unexpectedly succeeded', case_name;
END
$function$;

CREATE TEMP TABLE fixture_0087_failure_counts AS
SELECT
  (SELECT count(*)
   FROM app_data.workspaces
   WHERE split_part(workspace_id::text, '-', 2) = '8701') AS workspace_count,
  (SELECT count(*)
   FROM app_data.organization_memberships
   WHERE split_part(organization_workspace_id::text, '-', 2) = '8701')
    AS membership_count,
  (SELECT count(*)
   FROM app_data.organization_owner_assignments
   WHERE split_part(organization_owner_assignment_id::text, '-', 2) =
     '8701')
    AS owner_assignment_count,
  (SELECT count(*)
   FROM app_data.project_memberships
   WHERE split_part(project_membership_id::text, '-', 2) = '8701')
    AS project_membership_count,
  (SELECT count(*)
   FROM app_data.management_report_capability_grants
   WHERE split_part(capability_grant_id::text, '-', 2) = '8701')
    AS capability_count,
  (SELECT count(*)
   FROM app_private.organization_directed_account_invitation_request_claims
   WHERE split_part(invitation_id::text, '-', 2) = '8701')
    AS claim_count,
  (SELECT count(*)
   FROM app_private.organization_directed_account_invitation_request_tombstones
   WHERE split_part(invitation_id::text, '-', 2) = '8701')
    AS tombstone_count,
  (SELECT count(*)
   FROM app_private.organization_directed_account_invitation_audit_events
   WHERE split_part(invitation_id::text, '-', 2) = '8701')
    AS audit_count;

CREATE TEMP TABLE fixture_0087_failure_claims_before ON COMMIT DROP AS
SELECT invitation_id,
       organization_workspace_id,
       inviter_app_user_id,
       target_app_user_id,
       issued_at_utc,
       expires_at_utc,
       accepted_at_utc,
       accepted_organization_membership_id
FROM app_private.organization_directed_account_invitation_request_claims
WHERE split_part(invitation_id::text, '-', 2) = '8701'
ORDER BY invitation_id;

-- Create-side authorization, selector and lifecycle failures.
SELECT pg_temp.expect_0087_failure(
  'non-owner create',
  '42501',
  'organization invitation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1(%L, %L, %L::uuid, %L::uuid, %L::uuid)',
    'https://synthetic-8701.example/auth/v1',
    'main-non-owner',
    '00000000-8701-3000-0000-000000000020',
    '00000000-8701-2000-0000-000000000001',
    '00000000-8701-0000-0000-000000000011'
  )
);

SELECT pg_temp.expect_0087_failure(
  'self target create',
  '42501',
  'organization invitation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1(%L, %L, %L::uuid, %L::uuid, %L::uuid)',
    'https://synthetic-8701.example/auth/v1',
    'main-owner',
    '00000000-8701-3000-0000-000000000021',
    '00000000-8701-2000-0000-000000000001',
    '00000000-8701-0000-0000-000000000001'
  )
);

SELECT pg_temp.expect_0087_failure(
  'unknown target create',
  '42501',
  'organization invitation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1(%L, %L, %L::uuid, %L::uuid, %L::uuid)',
    'https://synthetic-8701.example/auth/v1',
    'main-owner',
    '00000000-8701-3000-0000-000000000022',
    '00000000-8701-2000-0000-000000000001',
    '00000000-8701-0000-0000-000000009999'
  )
);

SELECT pg_temp.expect_0087_failure(
  'current member create',
  '42501',
  'organization invitation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1(%L, %L, %L::uuid, %L::uuid, %L::uuid)',
    'https://synthetic-8701.example/auth/v1',
    'main-owner',
    '00000000-8701-3000-0000-000000000023',
    '00000000-8701-2000-0000-000000000001',
    '00000000-8701-0000-0000-000000000004'
  )
);

SELECT pg_temp.expect_0087_failure(
  'recovery create',
  '42501',
  'organization invitation forbidden',
  format(
    'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1(%L, %L, %L::uuid, %L::uuid, %L::uuid)',
    'https://synthetic-8701.example/auth/v1',
    'recovery-owner',
    '00000000-8701-3000-0000-000000000024',
    '00000000-8701-2000-0000-000000000002',
    '00000000-8701-0000-0000-000000000008'
  )
);

SELECT pg_temp.expect_0087_failure(
  'unknown workspace create',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000024') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000009999') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'personal workspace create',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000025') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000004') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'deletion pending create',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000026') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000006') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'deleted target create',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000027') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000007') || '::uuid)'
);

-- Existing claims reject any create replay whose actor, workspace or target
-- differs from the original idempotency tuple.
SELECT pg_temp.expect_0087_failure(
  'create actor drift',
  '22023',
  'organization invitation idempotency conflict',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000003') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'create workspace drift',
  '22023',
  'organization invitation idempotency conflict',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000003') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'create target drift',
  '22023',
  'organization invitation idempotency conflict',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000004') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'create tombstone',
  '22023',
  'organization invitation idempotency conflict',
  format(
    'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1(%L, %L, %L::uuid, %L::uuid, %L::uuid)',
    'https://synthetic-8701.example/auth/v1',
    'main-owner',
    '00000000-8701-3000-0000-000000000012',
    '00000000-8701-2000-0000-000000000001',
    '00000000-8701-0000-0000-000000000011'
  )
);

SELECT pg_temp.expect_0087_failure(
  'NULL create invitation',
  '22023',
  'invalid organization invitation request',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, NULL::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'NULL create workspace',
  '22023',
  'invalid organization invitation request',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000025') || '::uuid, NULL::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'NULL create target',
  '22023',
  'invalid organization invitation request',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000026') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, NULL::uuid)'
);

-- Accept-side actor, invitation, membership and lifecycle failures.
SELECT pg_temp.expect_0087_failure(
  'wrong actor accepted invitation',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000003') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'unknown accept invitation',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000027') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'personal workspace accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000028') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'unknown workspace accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000029') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'accept tombstone',
  '22023',
  'organization invitation idempotency conflict',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000013') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'current membership accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000012') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000006') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'deletion pending accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000006') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000008') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'deleted accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000007') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000009') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'recovery accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000010') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'expired accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'NULL accept invitation',
  '22023',
  'invalid organization invitation request',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, NULL::uuid)'
);

-- Identity bridges must reject invalid input before lookup, and must retain
-- exact issuer/subject matching (no trim, normalization, or bootstrap).
SELECT pg_temp.expect_0087_failure(
  'NULL create identity issuer',
  '22023',
  'invalid organization invitation identity',
  'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1('
    || 'NULL::text, ' || quote_literal('main-owner') || ', '
    || quote_literal('00000000-8701-3000-0000-000000000030') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'blank create identity subject',
  '22023',
  'invalid organization invitation identity',
  'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1('
    || quote_literal('https://synthetic-8701.example/auth/v1') || ', '
    || quote_literal('   ') || ', '
    || quote_literal('00000000-8701-3000-0000-000000000031') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'overlength create identity issuer',
  '22023',
  'invalid organization invitation identity',
  'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1('
    || 'repeat(''i'', 2049), ' || quote_literal('main-owner') || ', '
    || quote_literal('00000000-8701-3000-0000-000000000032') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'overlength accept identity subject',
  '22023',
  'invalid organization invitation identity',
  'SELECT count(*) FROM app_data.accept_organization_directed_account_invitation_for_identity_v1('
    || quote_literal('https://synthetic-8701.example/auth/v1') || ', '
    || 'repeat(''s'', 513), ' || quote_literal('00000000-8701-3000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'exact identity issuer whitespace drift',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1('
    || quote_literal(' https://synthetic-8701.example/auth/v1') || ', '
    || quote_literal('main-owner') || ', '
    || quote_literal('00000000-8701-3000-0000-000000000033') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'unknown exact create identity',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_data.create_organization_directed_account_invitation_for_identity_v1('
    || quote_literal('https://synthetic-8701.example/auth/v1') || ', '
    || quote_literal('unknown-exact') || ', '
    || quote_literal('00000000-8701-3000-0000-000000000034') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'inactive exact accept identity',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_data.accept_organization_directed_account_invitation_for_identity_v1('
    || quote_literal('https://synthetic-8701.example/auth/v1') || ', '
    || quote_literal('deletion-pending-target') || ', '
    || quote_literal('00000000-8701-3000-0000-000000000008') || '::uuid)'
);

-- All failures above must leave every business, claim, tombstone and audit
-- fact unchanged.  Comparing claim payloads catches a half-consumed claim
-- even when row counts stay constant.
DO $failure_counts$
DECLARE
  before_counts fixture_0087_failure_counts%ROWTYPE;
  after_counts fixture_0087_failure_counts%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_counts FROM fixture_0087_failure_counts;
  SELECT
    (SELECT count(*)
     FROM app_data.workspaces
     WHERE split_part(workspace_id::text, '-', 2) = '8701'),
    (SELECT count(*)
     FROM app_data.organization_memberships
     WHERE split_part(organization_workspace_id::text, '-', 2) = '8701'),
    (SELECT count(*)
     FROM app_data.organization_owner_assignments
     WHERE split_part(organization_owner_assignment_id::text, '-', 2) =
       '8701'),
    (SELECT count(*)
     FROM app_data.project_memberships
     WHERE split_part(project_membership_id::text, '-', 2) = '8701'),
    (SELECT count(*)
     FROM app_data.management_report_capability_grants
     WHERE split_part(capability_grant_id::text, '-', 2) = '8701'),
    (SELECT count(*)
     FROM app_private.organization_directed_account_invitation_request_claims
     WHERE split_part(invitation_id::text, '-', 2) = '8701'),
    (SELECT count(*)
     FROM app_private.organization_directed_account_invitation_request_tombstones
     WHERE split_part(invitation_id::text, '-', 2) = '8701'),
    (SELECT count(*)
     FROM app_private.organization_directed_account_invitation_audit_events
     WHERE split_part(invitation_id::text, '-', 2) = '8701')
  INTO after_counts;

  IF after_counts IS DISTINCT FROM before_counts THEN
    RAISE EXCEPTION
      '0087 failed invitation operation wrote partial facts: before %, after %',
      before_counts,
      after_counts;
  END IF;

  IF EXISTS (
    SELECT invitation_id,
           organization_workspace_id,
           inviter_app_user_id,
           target_app_user_id,
           issued_at_utc,
           expires_at_utc,
           accepted_at_utc,
           accepted_organization_membership_id
    FROM app_private.organization_directed_account_invitation_request_claims
    WHERE split_part(invitation_id::text, '-', 2) = '8701'
    EXCEPT ALL
    SELECT invitation_id,
           organization_workspace_id,
           inviter_app_user_id,
           target_app_user_id,
           issued_at_utc,
           expires_at_utc,
           accepted_at_utc,
           accepted_organization_membership_id
    FROM fixture_0087_failure_claims_before
  ) OR EXISTS (
    SELECT invitation_id,
           organization_workspace_id,
           inviter_app_user_id,
           target_app_user_id,
           issued_at_utc,
           expires_at_utc,
           accepted_at_utc,
           accepted_organization_membership_id
    FROM fixture_0087_failure_claims_before
    EXCEPT ALL
    SELECT invitation_id,
           organization_workspace_id,
           inviter_app_user_id,
           target_app_user_id,
           issued_at_utc,
           expires_at_utc,
           accepted_at_utc,
           accepted_organization_membership_id
    FROM app_private.organization_directed_account_invitation_request_claims
    WHERE split_part(invitation_id::text, '-', 2) = '8701'
  ) THEN
    RAISE EXCEPTION '0087 failed invitation operation changed claim payload';
  END IF;
END
$failure_counts$;

-- Acceptance has exactly one paired update, and history is never revived or
-- rewritten.  The acceptance audit names the membership as requested.
DO $facts$
DECLARE
  accepted_membership_id uuid;
  history_active_from timestamptz;
  history_inactive_from timestamptz;
  owner_count bigint;
  project_membership_count bigint;
  capability_count bigint;
  issued_count bigint;
  accepted_audit_count bigint;
BEGIN
  SELECT organization_membership_id INTO STRICT accepted_membership_id
  FROM fixture_0087_accept;

  SELECT active_from_utc, inactive_from_utc
  INTO STRICT history_active_from, history_inactive_from
  FROM app_data.organization_memberships
  WHERE organization_membership_id =
    '00000000-8701-3100-0000-000000000005'::uuid;

  IF EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_request_claims AS claim_row
    WHERE split_part(claim_row.invitation_id::text, '-', 2) = '8701'
      AND (claim_row.accepted_at_utc IS NULL)
      <> (claim_row.accepted_organization_membership_id IS NULL)
  ) THEN
    RAISE EXCEPTION '0087 claim acceptance fields are not paired';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_request_claims AS claim_row
    WHERE claim_row.invitation_id =
        '00000000-8701-3000-0000-000000000001'::uuid
      AND claim_row.accepted_at_utc =
        (SELECT accepted_at_utc FROM fixture_0087_accept)
      AND claim_row.accepted_organization_membership_id = accepted_membership_id
  ) THEN
    RAISE EXCEPTION '0087 accepted claim does not match membership receipt';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_request_claims AS claim_row
    WHERE claim_row.invitation_id =
        '00000000-8701-3000-0000-000000000005'::uuid
      AND claim_row.accepted_at_utc IS NOT NULL
      AND claim_row.accepted_organization_membership_id =
        (SELECT organization_membership_id FROM fixture_0087_history_accept)
  ) THEN
    RAISE EXCEPTION '0087 history claim was not consumed as a new membership';
  END IF;

  SELECT active_from_utc, inactive_from_utc
  INTO STRICT history_active_from, history_inactive_from
  FROM app_data.organization_memberships
  WHERE organization_membership_id =
    '00000000-8701-3100-0000-000000000005'::uuid;
  IF history_active_from IS DISTINCT FROM
      transaction_timestamp() - interval '3 hours'
    OR history_inactive_from IS DISTINCT FROM
      transaction_timestamp() - interval '2 hours'
  THEN
    RAISE EXCEPTION '0087 acceptance rewrote historical membership';
  END IF;

  SELECT count(*) INTO owner_count
  FROM app_data.organization_owner_assignments
  WHERE split_part(organization_owner_assignment_id::text, '-', 2) =
    '8701';
  SELECT count(*) INTO project_membership_count
  FROM app_data.project_memberships
  WHERE split_part(project_membership_id::text, '-', 2) = '8701';
  SELECT count(*) INTO capability_count
  FROM app_data.management_report_capability_grants
  WHERE split_part(capability_grant_id::text, '-', 2) = '8701';
  IF owner_count <> 3
    OR project_membership_count <> 2
    OR capability_count <> 2
  THEN
    RAISE EXCEPTION '0087 acceptance changed owner/project/capability facts';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_data.organization_owner_assignments AS owner_row
    WHERE owner_row.organization_membership_id IN (
      accepted_membership_id,
      (SELECT organization_membership_id FROM fixture_0087_history_accept)
    )
  ) OR EXISTS (
    SELECT 1
    FROM app_data.project_memberships AS project_row
    WHERE project_row.organization_membership_id IN (
      accepted_membership_id,
      (SELECT organization_membership_id FROM fixture_0087_history_accept)
    )
  ) THEN
    RAISE EXCEPTION '0087 acceptance provisioned owner or project facts';
  END IF;

  SELECT count(*) INTO issued_count
    FROM app_private.organization_directed_account_invitation_audit_events
    WHERE split_part(invitation_id::text, '-', 2) = '8701'
      AND event_kind = 'invitation_issued';
  SELECT count(*) INTO accepted_audit_count
  FROM app_private.organization_directed_account_invitation_audit_events
  WHERE split_part(invitation_id::text, '-', 2) = '8701'
    AND event_kind = 'invitation_accepted';
  IF issued_count <> 8 OR accepted_audit_count <> 3 THEN
    RAISE EXCEPTION
      '0087 audit count is issued %, accepted %, expected 8 and 3',
      issued_count,
      accepted_audit_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_audit_events
    WHERE split_part(invitation_id::text, '-', 2) = '8701'
      AND event_kind = 'invitation_issued'
      AND organization_membership_id IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1
    FROM app_private.organization_directed_account_invitation_audit_events
    WHERE split_part(invitation_id::text, '-', 2) = '8701'
      AND event_kind = 'invitation_accepted'
      AND invitation_id = '00000000-8701-3000-0000-000000000001'::uuid
      AND organization_membership_id = accepted_membership_id
  ) THEN
    RAISE EXCEPTION '0087 audit membership column is invalid';
  END IF;
END
$facts$;

-- Only the account-deletion transaction may detach inviter/target references;
-- the public writer cannot use a detached claim, and the reference cannot be
-- rebound to another account.
UPDATE app_private.organization_directed_account_invitation_request_claims
SET inviter_app_user_id = NULL
WHERE invitation_id = '00000000-8701-3000-0000-000000000006'::uuid;

UPDATE app_private.organization_directed_account_invitation_request_claims
SET target_app_user_id = NULL
WHERE invitation_id = '00000000-8701-3000-0000-000000000009'::uuid;

-- Directly legal deassociation is forbidden for both first acceptance and
-- exact accepted replay, regardless of which side was detached.
UPDATE app_private.organization_directed_account_invitation_request_claims
SET inviter_app_user_id = NULL
WHERE invitation_id = '00000000-8701-3000-0000-000000000015'::uuid;

UPDATE app_private.organization_directed_account_invitation_request_claims
SET target_app_user_id = NULL
WHERE invitation_id = '00000000-8701-3000-0000-000000000016'::uuid;

UPDATE app_private.organization_directed_account_invitation_request_claims
SET inviter_app_user_id = NULL
WHERE invitation_id = '00000000-8701-3000-0000-000000000001'::uuid;

UPDATE app_private.organization_directed_account_invitation_request_claims
SET target_app_user_id = NULL
WHERE invitation_id = '00000000-8701-3000-0000-000000000005'::uuid;

SELECT pg_temp.expect_0087_failure(
  'detached inviter replay',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000006') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000012') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'detached target accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000007') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000009') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'detached inviter first accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000015') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'detached target first accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000008') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000016') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'detached inviter accepted replay',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'detached target accepted replay',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000005') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000005') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'ON DELETE SET NULL inviter first accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000017') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'ON DELETE SET NULL target first accept',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000018') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'ON DELETE SET NULL inviter accepted replay',
  '42501',
  'organization invitation forbidden',
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000019') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'detached inviter reattachment',
  '55000',
  'organization invitation request claim is immutable',
  'UPDATE app_private.organization_directed_account_invitation_request_claims '
    || 'SET inviter_app_user_id = '
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000006') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'detached target reattachment',
  '55000',
  'organization invitation request claim is immutable',
  'UPDATE app_private.organization_directed_account_invitation_request_claims '
    || 'SET target_app_user_id = '
    || quote_literal('00000000-8701-0000-0000-000000000008') || '::uuid '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000016') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'half acceptance update',
  '55000',
  'organization invitation request claim is immutable',
  'UPDATE app_private.organization_directed_account_invitation_request_claims '
    || 'SET accepted_at_utc = transaction_timestamp() '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000008') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'claim payload update',
  '55000',
  'organization invitation request claim is immutable',
  'UPDATE app_private.organization_directed_account_invitation_request_claims '
    || 'SET organization_workspace_id = '
    || quote_literal('00000000-8701-2000-0000-000000000003') || '::uuid '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000008') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'claim delete',
  '55000',
  'organization invitation request claim cannot be deleted',
  'DELETE FROM app_private.organization_directed_account_invitation_request_claims '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000008') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'tombstone update',
  '55000',
  'organization invitation request tombstone is immutable',
  'UPDATE app_private.organization_directed_account_invitation_request_tombstones '
    || 'SET invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000014') || '::uuid '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000012') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'tombstone delete',
  '55000',
  'organization invitation request tombstone is immutable',
  'DELETE FROM app_private.organization_directed_account_invitation_request_tombstones '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000012') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'audit update',
  '55000',
  'organization invitation audit is append-only',
  'UPDATE app_private.organization_directed_account_invitation_audit_events '
    || 'SET invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000014') || '::uuid '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid'
);

SELECT pg_temp.expect_0087_failure(
  'audit delete',
  '55000',
  'organization invitation audit is append-only',
  'DELETE FROM app_private.organization_directed_account_invitation_audit_events '
    || 'WHERE invitation_id = '
    || quote_literal('00000000-8701-3000-0000-000000000001') || '::uuid'
);

-- Runtime can execute only the exact identity bridges and cannot inspect or
-- call the private writer/storage.  The bridge calls above already prove the
-- positive path under this role.
SET LOCAL ROLE tongxingzhe_runtime;

SELECT pg_temp.expect_0087_failure(
  'runtime private create ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.create_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000040') || '::uuid, '
    || quote_literal('00000000-8701-2000-0000-000000000001') || '::uuid, '
    || quote_literal('00000000-8701-0000-0000-000000000011') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'runtime private accept ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.accept_organization_directed_account_invitation_v1('
    || quote_literal('00000000-8701-0000-0000-000000000002') || '::uuid, '
    || quote_literal('00000000-8701-3000-0000-000000000040') || '::uuid)'
);

SELECT pg_temp.expect_0087_failure(
  'runtime invitation claims table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_directed_account_invitation_request_claims'
);

SELECT pg_temp.expect_0087_failure(
  'runtime invitation tombstones table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_directed_account_invitation_request_tombstones'
);

SELECT pg_temp.expect_0087_failure(
  'runtime invitation audit table ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_private.organization_directed_account_invitation_audit_events'
);

SELECT pg_temp.expect_0087_failure(
  'runtime organization membership ACL',
  '42501',
  NULL,
  'SELECT count(*) FROM app_data.organization_memberships'
);

RESET ROLE;

DO $acl$
DECLARE
  validator_owner oid;
  invitation_owner oid;
BEGIN
  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.create_organization_directed_account_invitation_for_identity_v1(text,text,uuid,uuid,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.accept_organization_directed_account_invitation_for_identity_v1(text,text,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '0087 runtime identity bridge EXECUTE privilege is missing';
  END IF;

  IF has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.create_organization_directed_account_invitation_v1(uuid,uuid,uuid,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'tongxingzhe_runtime',
    'app_private.accept_organization_directed_account_invitation_v1(uuid,uuid)',
    'EXECUTE'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_private.organization_directed_account_invitation_request_claims',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_private.organization_directed_account_invitation_request_tombstones',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_private.organization_directed_account_invitation_audit_events',
    'SELECT'
  ) THEN
    RAISE EXCEPTION '0087 runtime received a private invitation privilege';
  END IF;

  IF has_function_privilege(
    'public',
    'app_data.create_organization_directed_account_invitation_for_identity_v1(text,text,uuid,uuid,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'public',
    'app_private.create_organization_directed_account_invitation_v1(uuid,uuid,uuid,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'public',
    'app_data.accept_organization_directed_account_invitation_for_identity_v1(text,text,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'public',
    'app_private.accept_organization_directed_account_invitation_v1(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION '0087 PUBLIC received an invitation function privilege';
  END IF;

  SELECT proowner INTO STRICT validator_owner
  FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  SELECT proowner INTO STRICT invitation_owner
  FROM pg_catalog.pg_proc
  WHERE oid =
    'app_private.create_organization_directed_account_invitation_v1(uuid,uuid,uuid,uuid)'::regprocedure;
  IF invitation_owner <> validator_owner
    OR pg_catalog.pg_get_userbyid(invitation_owner) = 'tongxingzhe_runtime'
  THEN
    RAISE EXCEPTION '0087 invitation writer has the wrong owner';
  END IF;
END
$acl$;

ROLLBACK;
