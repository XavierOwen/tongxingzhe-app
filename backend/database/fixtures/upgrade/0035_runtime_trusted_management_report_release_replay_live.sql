\set ON_ERROR_STOP on

BEGIN;

INSERT INTO app_data.external_identities (
  external_identity_id, issuer, subject, app_user_id
) VALUES (
  '00000000-0000-4000-8000-000000007c13',
  'https://upgrade-release.synthetic/auth/v1',
  '7cn-publisher',
  '00000000-0000-4000-8000-000000007c01'
);

COMMIT;
