SELECT checksum_sha256
FROM app_migrations.schema_migrations
WHERE version = :'migration_version';
