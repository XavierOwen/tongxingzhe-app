#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
postgres_image="${POSTGRES_TEST_IMAGE:-postgres:16}"
container_name="${POSTGRES_TEST_CONTAINER:-tongxingzhe-postgres-test-$$}"
restore_container_name="${container_name}-restore"
keep_failed_container="${KEEP_POSTGRES_TEST_CONTAINER:-0}"
test_database='tongxingzhe_test'
restore_database='tongxingzhe_restore'
upgrade_database='tongxingzhe_region_upgrade'
database_url="postgresql://postgres:postgres@127.0.0.1:5432/${test_database}"
upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${upgrade_database}"
container_started=0
restore_container_started=0
restore_temporary_directory=''

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${restore_container_started}" -eq 1 ]]; then
    if [[ "${status}" -ne 0 && "${keep_failed_container}" == '1' ]]; then
      echo "恢复测试失败；保留独立容器：${restore_container_name}" >&2
    else
      docker rm --force "${restore_container_name}" >/dev/null 2>&1 || true
      echo "已删除恢复 PostgreSQL 容器：${restore_container_name}"
    fi
  fi
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
  if [[ -n "${restore_temporary_directory}" ]]; then
    rm -f "${restore_temporary_directory}/tongxingzhe.dump"
    rmdir "${restore_temporary_directory}"
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
if docker container inspect "${restore_container_name}" >/dev/null 2>&1; then
  echo "恢复容器名已存在，测试没有开始：${restore_container_name}" >&2
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
docker cp \
  "${repository_root}/tool/postgres_prepare_restore_roles.sh" \
  "${container_name}:/workspace/tool/postgres_prepare_restore_roles.sh"
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
  run_migrations_for_url "${database_url}"
}

run_migrations_for_url() {
  local target_database_url="$1"
  docker exec \
    --env DATABASE_URL="${target_database_url}" \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
}

run_sql_files() {
  local target_container="$1"
  local database_name="$2"
  local local_directory="$3"
  local container_directory="$4"
  local file_pattern="$5"
  local label="$6"
  local file_count=0
  local source_file
  local file_name

  while IFS= read -r source_file; do
    file_name="$(basename "${source_file}")"
    echo "${label}：${file_name}"
    docker exec \
      --workdir /workspace \
      "${target_container}" \
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

echo '验证 0038 会把已有 current 区域树迁移为冻结发布版本。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/pre-region-freeze-migrations && \
   cp /workspace/backend/database/migrations/00{01..37}_*.sql \
     /tmp/pre-region-freeze-migrations/ && \
   test \"\$(find /tmp/pre-region-freeze-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 37"
docker exec \
  --env DATABASE_URL="${upgrade_url}" \
  --env MIGRATION_DIR=/tmp/pre-region-freeze-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    INSERT INTO app_data.canonical_region_versions (
      region_id, tree_version, parent_region_id, canonical_name, kind
    ) VALUES
      ('upgrade-country', 'upgrade-existing-v1', NULL, 'Country', 'country'),
      ('upgrade-city', 'upgrade-existing-v1', 'upgrade-country', 'City', 'city'),
      ('upgrade-venue', 'upgrade-existing-v1', 'upgrade-city', 'Venue', 'venue');
    INSERT INTO app_data.canonical_region_tree_releases (
      tree_version, published_at_utc, is_current
    ) VALUES ('upgrade-existing-v1', '2029-01-02T03:04:05Z', true);
    INSERT INTO app_data.canonical_region_boundaries (
      boundary_id, region_id, tree_version, boundary
    ) VALUES (
      'upgrade-boundary', 'upgrade-venue', 'upgrade-existing-v1',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    );
    -- 在 0038/0039 之前写入一个真实的 resolved revision。0039 必须把
    -- 这种没有 source metadata 的历史事实回填为 resolved_region_only，
    -- 且沿用冻结版本的内容指纹，而不能伪造坐标或重新猜 current。
    SET ROLE tongxingzhe_runtime;
    CREATE TEMP TABLE upgrade_contact_context AS
    SELECT *
    FROM app_data.bootstrap_personal_context(
      'https://synthetic-region-upgrade.supabase.co/auth/v1',
      'synthetic-region-upgrade-owner'
    );
    RESET ROLE;
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, place_name, smallest_region_id,
      region_tree_version, reach_count, interest_level
    )
    SELECT
      'upgrade-provenance-contact',
      app_user_id,
      workspace_id,
      project_id,
      questionnaire_version_id,
      '2029-01-02T03:05:00Z',
      'America/Chicago',
      'face_to_face',
      'resolved',
      'Upgrade Venue',
      'upgrade-venue',
      'upgrade-existing-v1',
      1,
      2
    FROM upgrade_contact_context;
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    )
    SELECT
      'upgrade-provenance-contact',
      1,
      'submitted',
      app_user_id,
      jsonb_build_object(
        'location', jsonb_build_object(
          'kind', 'resolved',
          'placeName', 'Upgrade Venue',
          'smallestRegionId', 'upgrade-venue',
          'regionTreeVersion', 'upgrade-existing-v1'
        )
      )
    FROM upgrade_contact_context;
  " \
  >/dev/null
run_migrations_for_url "${upgrade_url}" >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$upgrade\$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM app_data.canonical_region_tree_releases
        WHERE tree_version = 'upgrade-existing-v1'
          AND lifecycle_state = 'published'
          AND published_at_utc = '2029-01-02T03:04:05Z'
          AND is_current
          AND content_fingerprint ~ '^[0-9a-f]{64}\$'
      ) OR NOT EXISTS (
        SELECT 1
        FROM app_data.canonical_region_tree_current_selections
        WHERE selected_tree_version = 'upgrade-existing-v1'
          AND previous_tree_version IS NULL
          AND selected_at_utc IS NULL
          AND recorded_at_utc IS NOT NULL
          AND selection_source = 'migration_baseline'
      ) OR NOT EXISTS (
        SELECT 1
        FROM app_data.resolve_canonical_region(41.7897, -87.5997)
        WHERE tree_version = 'upgrade-existing-v1'
          AND region_id = 'upgrade-venue'
      ) OR NOT EXISTS (
        SELECT 1
        FROM app_data.contact_location_provenance AS provenance
        JOIN app_data.canonical_region_tree_releases AS release_row
          ON release_row.tree_version = provenance.region_tree_version
        WHERE provenance.contact_id = 'upgrade-provenance-contact'
          AND provenance.revision_number = 1
          AND provenance.revision_kind = 'submitted'
          AND provenance.location_kind = 'resolved'
          AND provenance.evidence_kind = 'resolved_region_only'
          AND provenance.smallest_region_id = 'upgrade-venue'
          AND provenance.region_tree_version = 'upgrade-existing-v1'
          AND provenance.region_tree_content_fingerprint = release_row.content_fingerprint
          AND provenance.latitude IS NULL
          AND provenance.longitude IS NULL
          AND provenance.accuracy_meters IS NULL
      ) OR (
        SELECT count(*)
        FROM app_data.contact_location_provenance AS provenance
        WHERE provenance.contact_id = 'upgrade-provenance-contact'
          AND provenance.revision_number = 1
      ) <> 1 THEN
        RAISE EXCEPTION '0039 did not preserve historical resolved provenance';
      END IF;
    END
    \$upgrade\$;
  " \
  >/dev/null
echo '0038→0039 历史 resolved provenance 回填：通过。'
echo '已有区域树升级为冻结发布版本：通过。'

echo '第一次执行 migration：从空库建立全部 schema。'
run_migrations

echo '第二次执行 migration：验证历史 checksum，禁止重复执行。'
run_migrations

echo '验证 schema、函数与最小权限。'
run_sql_files \
  "${container_name}" \
  "${test_database}" \
  "${repository_root}/backend/database/checks" \
  '/workspace/backend/database/checks' \
  'verify_*.sql' \
  'check'

echo '运行可回滚 synthetic fixture。'
run_sql_files \
  "${container_name}" \
  "${test_database}" \
  "${repository_root}/backend/database/fixtures" \
  '/workspace/backend/database/fixtures' \
  '[0-9][0-9][0-9][0-9]_*.sql' \
  'fixture'

echo '用独立数据库会话验证并发不变量。'
# Concurrency scripts commit their synthetic rows, and the later pg_dump keeps
# them. Fixture files run again after restore, so concurrency and rollback
# fixtures must use non-overlapping synthetic primary-key namespaces.
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

echo '导出 schema，恢复到没有源 cluster roles 的独立 PostgreSQL 容器。'
docker exec "${container_name}" pg_dump \
  "${database_url}" \
  --format=custom \
  --schema=app_data \
  --schema=app_private \
  --schema=app_migrations \
  --file=/tmp/tongxingzhe.dump
restore_temporary_directory="$(mktemp -d)"
docker cp \
  "${container_name}:/tmp/tongxingzhe.dump" \
  "${restore_temporary_directory}/tongxingzhe.dump"
docker run \
  --detach \
  --rm \
  --name "${restore_container_name}" \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD=postgres \
  --env POSTGRES_DB="${restore_database}" \
  --health-cmd="pg_isready -U postgres -d ${restore_database}" \
  --health-interval=1s \
  --health-timeout=5s \
  --health-retries=30 \
  "${postgres_image}" >/dev/null
restore_container_started=1
restore_health_status='starting'
for _ in $(seq 1 45); do
  restore_health_status="$(
    docker container inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' \
      "${restore_container_name}"
  )"
  if [[ "${restore_health_status}" == 'healthy' ]]; then
    break
  fi
  if [[ "${restore_health_status}" == 'unhealthy' ]]; then
    echo '恢复 PostgreSQL 容器健康检查失败。' >&2
    docker logs "${restore_container_name}" >&2
    exit 1
  fi
  sleep 1
done
if [[ "${restore_health_status}" != 'healthy' ]]; then
  echo '等待恢复 PostgreSQL 容器就绪超时。' >&2
  docker logs "${restore_container_name}" >&2
  exit 1
fi
docker exec "${restore_container_name}" mkdir -p /workspace/backend /workspace/tool
docker cp \
  "${repository_root}/backend/database" \
  "${restore_container_name}:/workspace/backend/database"
docker cp \
  "${repository_root}/tool/postgres_prepare_restore_roles.sh" \
  "${restore_container_name}:/workspace/tool/postgres_prepare_restore_roles.sh"
docker cp \
  "${restore_temporary_directory}/tongxingzhe.dump" \
  "${restore_container_name}:/tmp/tongxingzhe.dump"
docker exec \
  --env DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5432/${restore_database}" \
  "${restore_container_name}" \
  bash /workspace/tool/postgres_prepare_restore_roles.sh
docker exec "${restore_container_name}" pg_restore \
  --username=postgres \
  --dbname="${restore_database}" \
  --exit-on-error \
  /tmp/tongxingzhe.dump

run_sql_files \
  "${restore_container_name}" \
  "${restore_database}" \
  "${repository_root}/backend/database/checks" \
  '/workspace/backend/database/checks' \
  'verify_*.sql' \
  'restore check'
run_sql_files \
  "${restore_container_name}" \
  "${restore_database}" \
  "${repository_root}/backend/database/fixtures" \
  '/workspace/backend/database/fixtures' \
  '[0-9][0-9][0-9][0-9]_*.sql' \
  'restore fixture'

echo 'PostgreSQL Docker 测试全部通过。'
