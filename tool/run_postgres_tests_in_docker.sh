#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
postgres_image="${POSTGRES_TEST_IMAGE:-postgres:16}"
container_name="${POSTGRES_TEST_CONTAINER:-tongxingzhe-postgres-test-$$}"
keep_failed_container="${KEEP_POSTGRES_TEST_CONTAINER:-0}"
test_database='tongxingzhe_test'
restore_database='tongxingzhe_restore'
database_url="postgresql://postgres:postgres@127.0.0.1:5432/${test_database}"
restore_url="postgresql://postgres:postgres@127.0.0.1:5432/${restore_database}"
container_started=0

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${container_started}" -eq 1 ]]; then
    if [[ "${status}" -ne 0 && "${keep_failed_container}" == '1' ]]; then
      echo "PostgreSQL 测试失败；保留容器：${container_name}" >&2
      echo "查看日志：docker logs ${container_name}" >&2
      echo "进入 psql：docker exec -it ${container_name} psql -U postgres -d ${test_database}" >&2
      echo "完成检查后删除：docker rm --force ${container_name}" >&2
    else
      docker rm --force "${container_name}" >/dev/null 2>&1 || true
      echo "已删除临时 PostgreSQL 容器：${container_name}"
    fi
  fi
  exit "${status}"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "找不到 docker。请先安装并启动 Docker Desktop 或 Docker Engine。" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker 已安装，但 daemon 不可用。请启动 Docker 后重试。" >&2
  exit 1
fi

if docker container inspect "${container_name}" >/dev/null 2>&1; then
  echo "容器名已存在，测试没有开始：${container_name}" >&2
  exit 1
fi

echo "启动临时 PostgreSQL 容器：${container_name}（${postgres_image}）"
docker run \
  --detach \
  --rm \
  --name "${container_name}" \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD=postgres \
  --env POSTGRES_DB="${test_database}" \
  --health-cmd="pg_isready -U postgres -d ${test_database}" \
  --health-interval=1s \
  --health-timeout=5s \
  --health-retries=30 \
  "${postgres_image}" >/dev/null
container_started=1

for _ in $(seq 1 45); do
  health_status="$(
    docker container inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' \
      "${container_name}"
  )"
  if [[ "${health_status}" == 'healthy' ]]; then
    break
  fi
  if [[ "${health_status}" == 'unhealthy' ]]; then
    echo "PostgreSQL 容器健康检查失败。" >&2
    docker logs "${container_name}" >&2
    exit 1
  fi
  sleep 1
done

if [[ "${health_status}" != 'healthy' ]]; then
  echo "等待 PostgreSQL 就绪超时。" >&2
  docker logs "${container_name}" >&2
  exit 1
fi

echo '复制只读测试输入和正式 migration runner。'
docker exec "${container_name}" mkdir -p /workspace/backend /workspace/tool
docker cp \
  "${repository_root}/backend/database" \
  "${container_name}:/workspace/backend/database"
docker cp \
  "${repository_root}/tool/postgres_migrate.sh" \
  "${container_name}:/workspace/tool/postgres_migrate.sh"
concurrency_script_count=0
while IFS= read -r concurrency_script; do
  tool_file="$(basename "${concurrency_script}")"
  docker cp \
    "${concurrency_script}" \
    "${container_name}:/workspace/tool/${tool_file}"
  concurrency_script_count=$((concurrency_script_count + 1))
done < <(
  find "${repository_root}/tool" \
    -maxdepth 1 \
    -type f \
    -name 'verify_*_concurrency.sh' \
    -print \
    | LC_ALL=C sort
)
if [[ "${concurrency_script_count}" -eq 0 ]]; then
  echo '没有找到独立会话并发检查脚本。' >&2
  exit 1
fi

run_migrations() {
  docker exec \
    --env DATABASE_URL="${database_url}" \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
}

run_sql_files() {
  local database_name="$1"
  local local_directory="$2"
  local container_directory="$3"
  local file_pattern="$4"
  local label="$5"
  local file_count=0
  local source_file
  local file_name

  while IFS= read -r source_file; do
    file_name="$(basename "${source_file}")"
    echo "${label}：${file_name}"
    docker exec \
      --workdir /workspace \
      "${container_name}" \
      psql \
      -U postgres \
      -d "${database_name}" \
      --no-psqlrc \
      --set=ON_ERROR_STOP=1 \
      --file "${container_directory}/${file_name}" \
      >/dev/null
    file_count=$((file_count + 1))
  done < <(
    find "${local_directory}" \
      -maxdepth 1 \
      -type f \
      -name "${file_pattern}" \
      -print \
      | LC_ALL=C sort
  )

  if [[ "${file_count}" -eq 0 ]]; then
    echo "没有找到 ${label} 文件：${local_directory}/${file_pattern}" >&2
    exit 1
  fi
}

echo '第一次执行 migration：从空库建立全部 schema。'
run_migrations

echo '第二次执行 migration：验证历史 checksum，禁止重复执行。'
run_migrations

echo '验证 schema、函数与最小权限。'
run_sql_files \
  "${test_database}" \
  "${repository_root}/backend/database/checks" \
  '/workspace/backend/database/checks' \
  'verify_*.sql' \
  'check'

echo '运行可回滚 synthetic fixture。'
run_sql_files \
  "${test_database}" \
  "${repository_root}/backend/database/fixtures" \
  '/workspace/backend/database/fixtures' \
  '[0-9][0-9][0-9][0-9]_*.sql' \
  'fixture'

echo '用独立数据库会话验证并发不变量。'
while IFS= read -r concurrency_script; do
  tool_file="$(basename "${concurrency_script}")"
  docker exec \
    --env DATABASE_URL="${database_url}" \
    "${container_name}" \
    bash "/workspace/tool/${tool_file}"
done < <(
  find "${repository_root}/tool" \
    -maxdepth 1 \
    -type f \
    -name 'verify_*_concurrency.sh' \
    -print \
    | LC_ALL=C sort
)

echo '确认 migration runner 会拒绝被改写的历史文件。'
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/edited-migrations && \
   cp /workspace/backend/database/migrations/*.sql /tmp/edited-migrations/ && \
   printf '\n-- synthetic checksum drift\n' >> \
     /tmp/edited-migrations/0001_bootstrap.sql"
if docker exec \
  --env DATABASE_URL="${database_url}" \
  --env MIGRATION_DIR=/tmp/edited-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null 2>&1; then
  echo 'migration runner 错误接受了被修改的历史文件。' >&2
  exit 1
fi
echo 'checksum 漂移已按预期被拒绝。'

echo '导出 schema，恢复到第二个空库，再重跑检查与 fixture。'
docker exec "${container_name}" pg_dump \
  "${database_url}" \
  --format=custom \
  --schema=app_data \
  --schema=app_private \
  --schema=app_migrations \
  --file=/tmp/tongxingzhe.dump
docker exec "${container_name}" createdb \
  -U postgres \
  "${restore_database}"
docker exec "${container_name}" pg_restore \
  --dbname="${restore_url}" \
  --exit-on-error \
  /tmp/tongxingzhe.dump

run_sql_files \
  "${restore_database}" \
  "${repository_root}/backend/database/checks" \
  '/workspace/backend/database/checks' \
  'verify_*.sql' \
  'restore check'
run_sql_files \
  "${restore_database}" \
  "${repository_root}/backend/database/fixtures" \
  '/workspace/backend/database/fixtures' \
  '[0-9][0-9][0-9][0-9]_*.sql' \
  'restore fixture'

echo 'PostgreSQL Docker 测试全部通过。'
