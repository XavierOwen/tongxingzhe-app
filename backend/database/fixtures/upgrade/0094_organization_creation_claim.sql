-- A real committed creation claim from the 0094 baseline; rerunning the
-- fixture after 0095 exercises the same request through the replaced writer.
\set ON_ERROR_STOP on

BEGIN;
SET LOCAL TIME ZONE 'UTC';
DO $check$
DECLARE
  migration_version text;
BEGIN
  SELECT max(version)
  INTO migration_version
  FROM app_migrations.schema_migrations;

  IF migration_version NOT IN (
    '0094_organization_shareable_join_application_approval',
    '0095_organization_creation_request_tombstone'
  ) THEN
    RAISE EXCEPTION 'creation claim fixture requires the 0094 or 0095 writer';
  END IF;
END
$check$;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('00000000-0094-0000-0000-000000000701', 'active')
ON CONFLICT DO NOTHING;

INSERT INTO app_data.external_identities (
  external_identity_id,
  issuer,
  subject,
  app_user_id
)
VALUES (
  '00000000-0094-1000-0000-000000000701',
  'https://synthetic-creation-claim-upgrade.example/auth/v1',
  'original-actor',
  '00000000-0094-0000-0000-000000000701'
)
ON CONFLICT DO NOTHING;

SET LOCAL ROLE tongxingzhe_runtime;
SELECT * FROM app_data.create_organization_for_identity_v1(
  'https://synthetic-creation-claim-upgrade.example/auth/v1',
  'original-actor',
  '00000000-0094-6000-0000-000000000701',
  '0094 creation claim upgrade organization'
);
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
