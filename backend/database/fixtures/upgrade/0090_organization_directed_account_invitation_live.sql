-- A pending invitation committed by the shipped 0087 runtime writer.
\set ON_ERROR_STOP on
\set QUIET on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

DO $check$
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 89
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0090_organization_membership_self_leave'
    OR to_regprocedure(
      'app_data.preview_organization_directed_invitation_for_identity_v1(text,text,uuid)'
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION '0090 invitation-preview upgrade baseline drift';
  END IF;
END
$check$;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0090-0000-0000-000000000801', 'active'),
  ('00000000-0090-0000-0000-000000000802', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  ('00000000-0090-1000-0000-000000000801',
    'https://synthetic-invitation-preview-upgrade.example/auth/v1', 'owner',
    '00000000-0090-0000-0000-000000000801'),
  ('00000000-0090-1000-0000-000000000802',
    'https://synthetic-invitation-preview-upgrade.example/auth/v1', 'target',
    '00000000-0090-0000-0000-000000000802');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name,
  personal_owner_app_user_id, deleted_at, created_at
)
VALUES (
  '00000000-0090-2000-0000-000000000801', 'organization',
  ' 0090 Original invitation organization ', NULL, NULL,
  transaction_timestamp()
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0090-3000-0000-000000000801',
  '00000000-0090-2000-0000-000000000801',
  '00000000-0090-0000-0000-000000000801',
  transaction_timestamp(), NULL
);

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0090-4000-0000-000000000801',
  '00000000-0090-3000-0000-000000000801',
  transaction_timestamp(), NULL
);

SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL ROLE tongxingzhe_runtime;
SELECT *
FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
  'https://synthetic-invitation-preview-upgrade.example/auth/v1',
  'owner',
  '00000000-0090-6000-0000-000000000801',
  '00000000-0090-2000-0000-000000000801',
  '00000000-0090-0000-0000-000000000802'
);
RESET ROLE;
COMMIT;
