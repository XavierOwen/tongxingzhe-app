-- A live link committed by the shipped 0092 runtime writer.
\set ON_ERROR_STOP on
\set QUIET on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
SET CONSTRAINTS ALL DEFERRED;

DO $check$
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 91
    OR (SELECT max(version) FROM app_migrations.schema_migrations)
      IS DISTINCT FROM '0092_organization_shareable_join_link'
    OR to_regclass(
      'app_private.organization_shareable_join_application_request_claims'
    ) IS NOT NULL
    OR to_regclass(
      'app_private.organization_shareable_join_application_request_tombstones'
    ) IS NOT NULL
    OR to_regclass(
      'app_private.organization_shareable_join_application_audit_events'
    ) IS NOT NULL
    OR to_regprocedure(
      'app_private.submit_organization_shareable_join_application_v1(uuid,uuid,uuid)'
    ) IS NOT NULL
    OR to_regprocedure(
      'app_data.submit_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)'
    ) IS NOT NULL
  THEN
    RAISE EXCEPTION '0092 link-submit upgrade baseline drift';
  END IF;
END
$check$;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('00000000-0092-0000-0000-000000000701', 'active'),
  ('00000000-0092-0000-0000-000000000702', 'active');

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
)
VALUES
  ('00000000-0092-1000-0000-000000000701',
    'https://synthetic-link-submit-upgrade.example/auth/v1', 'owner',
    '00000000-0092-0000-0000-000000000701'),
  ('00000000-0092-1000-0000-000000000702',
    'https://synthetic-link-submit-upgrade.example/auth/v1', 'applicant',
    '00000000-0092-0000-0000-000000000702');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name,
  personal_owner_app_user_id, deleted_at, created_at
)
VALUES (
  '00000000-0092-2000-0000-000000000701', 'organization',
  '0092 link submit upgrade organization', NULL, NULL,
  transaction_timestamp()
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0092-3000-0000-000000000701',
  '00000000-0092-2000-0000-000000000701',
  '00000000-0092-0000-0000-000000000701',
  transaction_timestamp(), NULL
);

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id, organization_membership_id,
  active_from_utc, inactive_from_utc
)
VALUES (
  '00000000-0092-4000-0000-000000000701',
  '00000000-0092-3000-0000-000000000701',
  transaction_timestamp(), NULL
);

SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL ROLE tongxingzhe_runtime;
SELECT *
FROM app_data.create_organization_shareable_join_link_for_identity_v1(
  'https://synthetic-link-submit-upgrade.example/auth/v1',
  'owner',
  '00000000-0092-6000-0000-000000000701',
  '00000000-0092-2000-0000-000000000701'
);
RESET ROLE;
COMMIT;
