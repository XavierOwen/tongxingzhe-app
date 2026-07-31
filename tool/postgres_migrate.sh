#!/usr/bin/env bash

set -euo pipefail

# 部署者必须显式提供目标；脚本永远不猜本机或 production 数据库。
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
migration_dir="${MIGRATION_DIR:-${repository_root}/backend/database/migrations}"
runner_dir="${repository_root}/backend/database/runner"
psql_command="${PSQL_COMMAND:-psql}"

if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

if [[ ! -d "${migration_dir}" ]]; then
  echo "migration 目录不存在：${migration_dir}" >&2
  exit 1
fi

sha256_of() {
  local source_file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${source_file}" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${source_file}" | awk '{print $1}'
    return
  fi
  echo "找不到 shasum 或 sha256sum，无法保护 migration 历史。" >&2
  exit 1
}

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

"${psql_base[@]}" --file="${runner_dir}/bootstrap.sql"

migration_count=0
while IFS= read -r migration_file; do
  migration_count=$((migration_count + 1))
  migration_filename="$(basename "${migration_file}")"

  if [[ ! "${migration_filename}" =~ ^[0-9]{4}_[a-z0-9_]+\.sql$ ]]; then
    echo "migration 文件名不合法：${migration_filename}" >&2
    exit 1
  fi

  migration_version="${migration_filename%.sql}"
  migration_checksum="$(sha256_of "${migration_file}")"
  applied_checksum="$(
    "${psql_base[@]}" \
      --tuples-only \
      --no-align \
      --set="migration_version=${migration_version}" \
      --file="${runner_dir}/read_checksum.sql" \
      | tr -d '[:space:]'
  )"

  if [[ -n "${applied_checksum}" ]]; then
    if [[ "${applied_checksum}" != "${migration_checksum}" ]]; then
      echo "已执行 migration 被修改：${migration_version}" >&2
      echo "数据库 checksum：${applied_checksum}" >&2
      echo "文件 checksum：${migration_checksum}" >&2
      exit 1
    fi
    echo "已验证 ${migration_version}（无需重复执行）"
    continue
  fi

  "${psql_base[@]}" \
    --single-transaction \
    --set="migration_version=${migration_version}" \
    --set="migration_checksum=${migration_checksum}" \
    --file="${runner_dir}/lock.sql" \
    --file="${migration_file}" \
    --file="${runner_dir}/record.sql"
  echo "已执行 ${migration_version}"
done < <(find "${migration_dir}" -maxdepth 1 -type f -name '*.sql' -print | LC_ALL=C sort)

if [[ "${migration_count}" -eq 0 ]]; then
  echo "没有找到 migration：${migration_dir}" >&2
  exit 1
fi
