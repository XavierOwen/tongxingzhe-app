#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "用法：$0 <现有最新 PostgreSQL 测试容器>" >&2
  exit 1
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
current_container="$1"
legacy_image='postgres@sha256:95206741a5b214807675e14165369d05b93a9cf692223b616d07cca227e74b0b'
current_name="$(docker inspect --format '{{.Name}}' "${current_container}")"
legacy_container="${current_name#/}-frozen-legacy-$$"
database_name="frozen_periods_upgrade_$$"
container_workspace="/tmp/frozen-periods-upgrade-$$"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/frozen-periods-upgrade.XXXXXX")"
legacy_volumes=''
current_workspace_created=0

cleanup() {
  local status=$?
  local cleanup_failed=0
  trap - EXIT
  if [[ -s "${temporary_directory}/legacy.cid" ]]; then
    if docker rm --force --volumes "$(cat "${temporary_directory}/legacy.cid")" >/dev/null; then
      echo "已删除旧规则测试容器及匿名 volumes：${legacy_container} ${legacy_volumes}"
      for volume in ${legacy_volumes}; do
        if docker volume inspect "${volume}" >/dev/null 2>&1; then
          echo "旧规则测试 volume 仍存在：${volume}" >&2
          cleanup_failed=1
        fi
      done
    else
      echo "未能删除旧规则测试容器：${legacy_container}" >&2
      cleanup_failed=1
    fi
  fi
  if [[ "${current_workspace_created}" -eq 1 ]]; then
    if ! docker exec "${current_container}" rm -rf -- "${container_workspace}"; then
      echo "未能删除本脚本的最新镜像临时输入：${container_workspace}" >&2
      cleanup_failed=1
    fi
  fi
  rm -rf "${temporary_directory}"
  if [[ "${status}" -eq 0 && "${cleanup_failed}" -ne 0 ]]; then status=1; fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if docker container inspect "${legacy_container}" >/dev/null 2>&1; then
  echo "旧规则测试容器名已存在：${legacy_container}" >&2
  exit 1
fi

echo "拉取固定官方 PostgreSQL 16.14：${legacy_image}"
docker pull "${legacy_image}"
docker run --detach --name "${legacy_container}" \
  --cidfile "${temporary_directory}/legacy.cid" \
  --env POSTGRES_PASSWORD=postgres --env POSTGRES_DB="${database_name}" \
  "${legacy_image}" >/dev/null
legacy_volumes="$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "${legacy_container}")"
echo "旧规则容器 ID：$(cat "${temporary_directory}/legacy.cid")；volumes：${legacy_volumes}"
ready=0
for _ in {1..45}; do
  if docker exec "${legacy_container}" pg_isready --host=127.0.0.1 -U postgres -d "${database_name}" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [[ "${ready}" -ne 1 ]]; then docker logs "${legacy_container}" >&2; exit 1; fi

docker exec -i "${legacy_container}" psql -U postgres -d "${database_name}" -X --set=ON_ERROR_STOP=1 <<'SQL'
SELECT version();
DO $image_contract$
BEGIN
  IF current_setting('server_version_num') <> '160014'
    OR timestamp '2026-11-16 00:00' AT TIME ZONE 'America/Havana'
      <> timestamptz '2026-11-16 05:00Z' THEN
    RAISE EXCEPTION 'fixed legacy image does not have PostgreSQL 16.14 and the expected old Havana rules';
  END IF;
END
$image_contract$;
SQL

workspace="${temporary_directory}/workspace"
mkdir -p "${workspace}/tool" "${workspace}/backend/database/migrations"
cp "${repository_root}/tool/postgres_migrate.sh" "${workspace}/tool/"
cp -R "${repository_root}/backend/database/runner" "${workspace}/backend/database/"
cp -R "${repository_root}/backend/database/fixtures" "${workspace}/backend/database/"
migration_count=0
latest_migration_version=''
for migration in "${repository_root}"/backend/database/migrations/*.sql; do
  filename="$(basename "${migration}")"
  version="${filename%%_*}"
  if (( 10#${version} <= 163 )); then
    cp "${migration}" "${workspace}/backend/database/migrations/"
    migration_count=$((migration_count+1))
    latest_migration_version="${version}"
  fi
done
if [[ "${migration_count}" -eq 0 || "${latest_migration_version}" != '0163' ]]; then
  echo "旧规则 baseline 必须保留 source 的 published migrations，并以 0163 结束。" >&2
  exit 1
fi
echo "旧规则 baseline：${migration_count} 份 source migrations，最高版本 ${latest_migration_version}。"
docker cp "${workspace}" "${legacy_container}:/workspace"
echo '在固定旧镜像应用正式 0001–0163，正常发布并读取旧快照。'
docker exec --env DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/${database_name}" \
  "${legacy_container}" bash /workspace/tool/postgres_migrate.sh
docker exec "${legacy_container}" psql -U postgres -d "${database_name}" -X --set=ON_ERROR_STOP=1 \
  --file=/workspace/backend/database/fixtures/upgrade/0163_management_report_frozen_periods_live.sql

echo '真实 pg_dump/restore 到现有最新镜像中的独立数据库。'
docker exec "${legacy_container}" pg_dump -U postgres -d "${database_name}" --format=custom > "${temporary_directory}/legacy.dump"
docker exec "${current_container}" createdb -U postgres "${database_name}"
docker exec "${current_container}" psql -U postgres -d "${database_name}" -X --set=ON_ERROR_STOP=1 --command='SELECT version();'
docker exec "${current_container}" mkdir -p "${container_workspace}"
current_workspace_created=1
docker exec -i "${current_container}" pg_restore -U postgres -d "${database_name}" --exit-on-error < "${temporary_directory}/legacy.dump"

# Keep the old migration set intact; the official runner applies only 0164 next.
cp "${repository_root}/backend/database/migrations/0164_management_report_frozen_periods.sql" "${workspace}/backend/database/migrations/"
mkdir -p "${workspace}/backend/database/checks"
cp "${repository_root}/backend/database/checks/verify_management_report_frozen_periods.sql" "${workspace}/backend/database/checks/"
docker cp "${workspace}" "${current_container}:${container_workspace}/workspace"
echo '先验证 restore 原业务状态和旧 SQL 的实际日历结果，再冻结当前 OID catalog。'
docker exec -i "${current_container}" psql -U postgres -d "${database_name}" -X --set=ON_ERROR_STOP=1 \
  --set=fixture_0164_definitions_only=true \
  --file="${container_workspace}/workspace/backend/database/fixtures/0164_management_report_frozen_periods.sql" \
  --file=- <<'SQL'
BEGIN;
SELECT public.fixture_0163_frozen_assert_restored_calendar();
ROLLBACK;
SELECT public.fixture_0163_frozen_capture_restored_catalog();
SQL

echo '仅应用正式 0164，验证私有结构、旧业务与函数 catalog、读取和精确重放。'
docker exec --env DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/${database_name}" \
  "${current_container}" bash "${container_workspace}/workspace/tool/postgres_migrate.sh"
docker exec "${current_container}" psql -U postgres -d "${database_name}" -X --set=ON_ERROR_STOP=1 \
  --file="${container_workspace}/workspace/backend/database/checks/verify_management_report_frozen_periods.sql" \
  --set=fixture_0164_definitions_only=true \
  --file="${container_workspace}/workspace/backend/database/fixtures/0164_management_report_frozen_periods.sql" \
  --command='BEGIN; SELECT public.fixture_0163_frozen_assert_upgrade(); ROLLBACK;'
echo '正式 runner checksum replay。'
docker exec --env DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/${database_name}" \
  "${current_container}" bash "${container_workspace}/workspace/tool/postgres_migrate.sh"
echo "冻结报告周期真实镜像升级验证通过：${database_name}"
