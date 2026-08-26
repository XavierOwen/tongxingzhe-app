#!/usr/bin/env bash

set -euo pipefail

# pg_dump 不包含 cluster roles。把 schema archive 恢复到新 PostgreSQL cluster
# 前，先以 cluster 管理身份幂等建立 archive ACL 和函数 owner 依赖的角色。
: "${DATABASE_URL:?请设置目标 PostgreSQL cluster 的 DATABASE_URL}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

"${psql_command}" \
  "${DATABASE_URL}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  <<'SQL'
DO $roles$
DECLARE
  role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_original_region_report_reader',
    'tongxingzhe_management_interest_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer',
    'tongxingzhe_management_interest_snapshot_release_writer',
    'tongxingzhe_management_original_region_snapshot_release_writer',
    'tongxingzhe_management_report_snapshot_lifecycle_writer',
    'tongxingzhe_management_follow_up_consent_config_writer',
    'tongxingzhe_management_follow_up_consent_ratio_reader'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = role_name
    ) THEN
      EXECUTE format(
        'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
          || 'NOINHERIT NOREPLICATION NOBYPASSRLS',
        role_name
      );
    END IF;
    EXECUTE format(
      'ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE '
        || 'NOINHERIT NOREPLICATION NOBYPASSRLS',
      role_name
    );
  END LOOP;
END
$roles$;

ALTER ROLE tongxingzhe_runtime SET search_path = app_data, pg_catalog;

DO $publisher_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS publisher_role
      ON publisher_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE publisher_role.rolname = 'tongxingzhe_region_publisher'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_region_publisher FROM %I',
      member_name
    );
  END LOOP;
END
$publisher_membership$;

DO $provenance_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname = 'tongxingzhe_contact_provenance_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_contact_provenance_writer FROM %I',
      member_name
    );
  END LOOP;
END
$provenance_writer_membership$;

DO $mapping_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname = 'tongxingzhe_region_mapping_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_region_mapping_writer FROM %I',
      member_name
    );
  END LOOP;
END
$mapping_writer_membership$;

DO $attribution_reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname = 'tongxingzhe_region_attribution_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_region_attribution_reader FROM %I',
      member_name
    );
  END LOOP;
END
$attribution_reader_membership$;

DO $management_region_report_reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname =
      'tongxingzhe_management_region_report_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_region_report_reader FROM %I',
      member_name
    );
  END LOOP;
END
$management_region_report_reader_membership$;

DO $management_original_region_report_reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname =
      'tongxingzhe_management_original_region_report_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_original_region_report_reader FROM %I',
      member_name
    );
  END LOOP;
END
$management_original_region_report_reader_membership$;

DO $management_interest_report_reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname =
      'tongxingzhe_management_interest_report_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_interest_report_reader FROM %I',
      member_name
    );
  END LOOP;
END
$management_interest_report_reader_membership$;

DO $management_current_city_snapshot_release_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname =
      'tongxingzhe_management_current_city_snapshot_release_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_current_city_snapshot_release_writer FROM %I',
      member_name
    );
  END LOOP;
END
$management_current_city_snapshot_release_writer_membership$;

DO $management_interest_snapshot_release_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname =
      'tongxingzhe_management_interest_snapshot_release_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_interest_snapshot_release_writer FROM %I',
      member_name
    );
  END LOOP;
END
$management_interest_snapshot_release_writer_membership$;

DO $management_original_region_snapshot_release_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname =
      'tongxingzhe_management_original_region_snapshot_release_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_original_region_snapshot_release_writer FROM %I',
      member_name
    );
  END LOOP;
END
$management_original_region_snapshot_release_writer_membership$;

DO $management_report_snapshot_lifecycle_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname =
      'tongxingzhe_management_report_snapshot_lifecycle_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_report_snapshot_lifecycle_writer FROM %I',
      member_name
    );
  END LOOP;
END
$management_report_snapshot_lifecycle_writer_membership$;

DO $management_follow_up_consent_config_writer_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS writer_role
      ON writer_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE writer_role.rolname =
      'tongxingzhe_management_follow_up_consent_config_writer'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_follow_up_consent_config_writer FROM %I',
      member_name
    );
  END LOOP;
END
$management_follow_up_consent_config_writer_membership$;

DO $management_follow_up_consent_ratio_reader_membership$
DECLARE
  member_name text;
BEGIN
  FOR member_name IN
    SELECT member_role.rolname
    FROM pg_catalog.pg_auth_members AS membership
    JOIN pg_catalog.pg_roles AS reader_role
      ON reader_role.oid = membership.roleid
    JOIN pg_catalog.pg_roles AS member_role
      ON member_role.oid = membership.member
    WHERE reader_role.rolname =
      'tongxingzhe_management_follow_up_consent_ratio_reader'
  LOOP
    EXECUTE format(
      'REVOKE tongxingzhe_management_follow_up_consent_ratio_reader FROM %I',
      member_name
    );
  END LOOP;
END
$management_follow_up_consent_ratio_reader_membership$;
SQL

echo 'PostgreSQL restore 所需 cluster roles 已准备。'
