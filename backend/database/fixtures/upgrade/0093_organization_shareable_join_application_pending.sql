-- Persistent 0093 state for staged application upgrade tests.

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0093-0000-0000-000000000001', 'active'),
  ('00000000-0093-0000-0000-000000000002', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  ('00000000-0093-1000-0000-000000000001',
    'https://synthetic-0093.example/auth/v1', 'owner',
    '00000000-0093-0000-0000-000000000001'),
  ('00000000-0093-1000-0000-000000000002',
    'https://synthetic-0093.example/auth/v1', 'pending-applicant',
    '00000000-0093-0000-0000-000000000002');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name,
  personal_owner_app_user_id, deleted_at, created_at
)
VALUES (
  '00000000-0093-2000-0000-000000000001', 'organization',
  '0093 directory upgrade organization', NULL, NULL,
  transaction_timestamp() - interval '1 day'
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0093-3000-0000-000000000001',
  '00000000-0093-2000-0000-000000000001',
  '00000000-0093-0000-0000-000000000001',
  transaction_timestamp() - interval '1 hour', NULL
);

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0093-4000-0000-000000000001',
  '00000000-0093-3000-0000-000000000001',
  transaction_timestamp(), NULL
);

SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL ROLE tongxingzhe_runtime;

SELECT count(*)
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-0093.example/auth/v1',
  'owner',
  '00000000-0093-6000-0000-000000000001',
  '00000000-0093-2000-0000-000000000001'
);

SELECT count(*)
FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
  'https://synthetic-0093.example/auth/v1',
  'pending-applicant',
  '00000000-0093-5000-0000-000000000001',
  '00000000-0093-6000-0000-000000000001'
);

COMMIT;
