-- migration runner 自己的状态不属于业务 schema，只允许部署身份访问。
CREATE SCHEMA IF NOT EXISTS app_migrations;
REVOKE ALL ON SCHEMA app_migrations FROM PUBLIC;

CREATE TABLE IF NOT EXISTS app_migrations.schema_migrations (
  version text PRIMARY KEY,
  checksum_sha256 text NOT NULL CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  applied_at timestamptz NOT NULL DEFAULT transaction_timestamp()
);

REVOKE ALL ON TABLE app_migrations.schema_migrations FROM PUBLIC;
