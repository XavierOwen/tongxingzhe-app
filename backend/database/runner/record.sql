-- 并发 migration 即使同时看到“尚未执行”，最终也必须得到相同 checksum。
-- checksum 不同时故意写入不符合 CHECK 的值，让整个事务失败并回滚。
INSERT INTO app_migrations.schema_migrations (
  version,
  checksum_sha256
)
VALUES (
  :'migration_version',
  :'migration_checksum'
)
ON CONFLICT (version) DO UPDATE
SET checksum_sha256 = CASE
  WHEN app_migrations.schema_migrations.checksum_sha256 = EXCLUDED.checksum_sha256
    THEN app_migrations.schema_migrations.checksum_sha256
  ELSE 'migration_checksum_mismatch'
END;
