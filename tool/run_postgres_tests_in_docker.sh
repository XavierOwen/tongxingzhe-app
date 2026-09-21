#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"
postgres_image="${POSTGRES_TEST_IMAGE:-postgres:16}"
backend_image="${BACKEND_POSTGRES_TEST_IMAGE:-node:24-bookworm}"
container_name="${POSTGRES_TEST_CONTAINER:-tongxingzhe-postgres-test-$$}"
restore_container_name="${container_name}-restore"
keep_failed_container="${KEEP_POSTGRES_TEST_CONTAINER:-0}"
test_database='tongxingzhe_test'
restore_database='tongxingzhe_restore'
upgrade_database='tongxingzhe_region_upgrade'
ownerless_upgrade_database='tongxingzhe_ownerless_upgrade'
consent_replacement_upgrade_database='tongxingzhe_consent_replacement_upgrade'
current_city_replacement_upgrade_database='tongxingzhe_current_city_replacement_upgrade'
interest_replacement_upgrade_database='tongxingzhe_interest_replacement_upgrade'
owner_transfer_upgrade_database='tongxingzhe_owner_transfer_upgrade'
directed_invitation_upgrade_database='tongxingzhe_directed_invitation_upgrade'
owner_authorization_upgrade_database='tongxingzhe_owner_authorization_upgrade'
organization_directory_upgrade_database='tongxingzhe_organization_directory_upgrade'
membership_leave_upgrade_database='tongxingzhe_membership_leave_upgrade'
invitation_preview_upgrade_database='tongxingzhe_invitation_preview_upgrade'
shareable_link_creation_upgrade_database='tongxingzhe_shareable_link_creation_upgrade'
link_submit_upgrade_database='tongxingzhe_link_submit_upgrade'
application_approval_upgrade_database='tongxingzhe_application_approval_upgrade'
project_assignment_upgrade_database='tongxingzhe_project_assignment_upgrade'
directory_upgrade_database='tongxingzhe_application_directory_upgrade'
database_url="postgresql://postgres:postgres@127.0.0.1:5432/${test_database}"
upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${upgrade_database}"
ownerless_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${ownerless_upgrade_database}"
consent_replacement_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${consent_replacement_upgrade_database}"
current_city_replacement_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${current_city_replacement_upgrade_database}"
interest_replacement_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${interest_replacement_upgrade_database}"
owner_transfer_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${owner_transfer_upgrade_database}"
directed_invitation_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${directed_invitation_upgrade_database}"
owner_authorization_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${owner_authorization_upgrade_database}"
organization_directory_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${organization_directory_upgrade_database}"
membership_leave_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${membership_leave_upgrade_database}"
invitation_preview_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${invitation_preview_upgrade_database}"
shareable_link_creation_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${shareable_link_creation_upgrade_database}"
link_submit_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${link_submit_upgrade_database}"
application_approval_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${application_approval_upgrade_database}"
project_assignment_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${project_assignment_upgrade_database}"
directory_upgrade_url="postgresql://postgres:postgres@127.0.0.1:5432/${directory_upgrade_database}"
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

# 先单独应用 0038，再模拟一个已能携带冻结 release 指纹、但尚未安装
# 0039 provenance 表的 revision。这样升级测试同时覆盖有、无 source metadata。
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/region-freeze-only && \
   cp /workspace/backend/database/migrations/0038_*.sql \
     /tmp/region-freeze-only/"
docker exec \
  --env DATABASE_URL="${upgrade_url}" \
  --env MIGRATION_DIR=/tmp/region-freeze-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, place_name, smallest_region_id,
      region_tree_version, reach_count, interest_level
    )
    SELECT
      'upgrade-coordinate-provenance-contact',
      app_user_id,
      workspace_id,
      project_id,
      questionnaire_version_id,
      occurred_at_utc,
      occurred_time_zone,
      channel,
      location_kind,
      place_name,
      smallest_region_id,
      region_tree_version,
      reach_count,
      interest_level
    FROM app_data.contacts
    WHERE contact_id = 'upgrade-provenance-contact';
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    )
    SELECT
      'upgrade-coordinate-provenance-contact',
      1,
      'submitted',
      revised_by_app_user_id,
      jsonb_build_object(
        'location', jsonb_build_object(
          'kind', 'resolved',
          'placeName', 'Upgrade Venue',
          'smallestRegionId', 'upgrade-venue',
          'regionTreeVersion', 'upgrade-existing-v1'
        ),
        'locationSource', jsonb_build_object(
          'kind', 'captured_coordinates',
          'latitude', 41.7897,
          'longitude', -87.5997,
          'accuracyMeters', 8.5,
          'resolverContractVersion', 'canonical-region-resolution:v1',
          'regionTreeContentFingerprint', (
            SELECT content_fingerprint
            FROM app_data.canonical_region_tree_releases
            WHERE tree_version = 'upgrade-existing-v1'
          )
        )
      )
    FROM app_data.contact_revisions
    WHERE contact_id = 'upgrade-provenance-contact'
      AND revision_number = 1;
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, place_name, smallest_region_id,
      region_tree_version, reach_count, interest_level
    )
    SELECT
      'upgrade-malformed-provenance-contact',
      app_user_id,
      workspace_id,
      project_id,
      questionnaire_version_id,
      occurred_at_utc,
      occurred_time_zone,
      channel,
      location_kind,
      place_name,
      smallest_region_id,
      region_tree_version,
      reach_count,
      interest_level
    FROM app_data.contacts
    WHERE contact_id = 'upgrade-provenance-contact';
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind, revised_by_app_user_id,
      snapshot
    )
    SELECT
      'upgrade-malformed-provenance-contact',
      1,
      'submitted',
      revised_by_app_user_id,
      jsonb_build_object(
        'location', jsonb_build_object(
          'kind', 'pending_resolution',
          'latitude', 1e400::numeric,
          'longitude', -87.5997
        ),
        'locationSource', jsonb_build_object(
          'kind', 'captured_coordinates',
          'latitude', 41.7897,
          'longitude', -87.5997,
          'resolverContractVersion', 'canonical-region-resolution:v1',
          'regionTreeContentFingerprint', (
            SELECT content_fingerprint
            FROM app_data.canonical_region_tree_releases
            WHERE tree_version = 'upgrade-existing-v1'
          )
        )
      )
    FROM app_data.contact_revisions
    WHERE contact_id = 'upgrade-provenance-contact'
      AND revision_number = 1;
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
      ) <> 1 OR NOT EXISTS (
        SELECT 1
        FROM app_data.contact_location_provenance AS provenance
        JOIN app_data.canonical_region_tree_releases AS release_row
          ON release_row.tree_version = provenance.region_tree_version
        WHERE provenance.contact_id = 'upgrade-coordinate-provenance-contact'
          AND provenance.revision_number = 1
          AND provenance.revision_kind = 'submitted'
          AND provenance.location_kind = 'resolved'
          AND provenance.evidence_kind = 'resolved_from_coordinates'
          AND provenance.smallest_region_id = 'upgrade-venue'
          AND provenance.region_tree_version = 'upgrade-existing-v1'
          AND provenance.region_tree_content_fingerprint = release_row.content_fingerprint
          AND provenance.resolver_contract_version = 'canonical-region-resolution:v1'
          AND provenance.latitude = 41.7897
          AND provenance.longitude = -87.5997
          AND provenance.accuracy_meters = 8.5
      ) OR (
        SELECT count(*)
        FROM app_data.contact_location_provenance AS provenance
        WHERE provenance.contact_id = 'upgrade-coordinate-provenance-contact'
          AND provenance.revision_number = 1
      ) <> 1 OR NOT EXISTS (
        SELECT 1
        FROM app_data.contact_location_provenance AS provenance
        WHERE provenance.contact_id = 'upgrade-malformed-provenance-contact'
          AND provenance.revision_number = 1
          AND provenance.location_kind = 'unknown'
          AND provenance.evidence_kind = 'legacy_incomplete'
          AND provenance.latitude IS NULL
          AND provenance.longitude IS NULL
          AND provenance.smallest_region_id IS NULL
          AND provenance.region_tree_version IS NULL
      ) OR (
        SELECT count(*)
        FROM app_data.contact_location_provenance AS provenance
        WHERE provenance.contact_id = 'upgrade-malformed-provenance-contact'
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

echo '验证 0079→0080 升级保留旧批准 current-city 快照，并可登记替代。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${current_city_replacement_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/current-city-replacement-baseline-migrations \
      /tmp/current-city-replacement-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \) \
     -exec cp {} /tmp/current-city-replacement-baseline-migrations/ \; && \
   test \"\$(find /tmp/current-city-replacement-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 78 && \
   cp /workspace/backend/database/migrations/0080_*.sql \
     /tmp/current-city-replacement-upgrade-only/ && \
   test \"\$(find /tmp/current-city-replacement-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${current_city_replacement_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/current-city-replacement-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${current_city_replacement_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 78
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM
            '0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory'
        OR to_regclass(
          'app_private.management_current_city_report_snapshot_replacements'
        ) IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.pg_policies
          WHERE schemaname = 'app_private'
            AND tablename = 'management_report_snapshots'
            AND policyname =
              'management_current_city_snapshot_replacement_read_scope'
        )
        OR to_regprocedure(
          'app_private.current_city_snapshot_replacement_provenance_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.management_current_city_snapshot_has_trusted_provenance_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.validate_management_current_city_snapshot_replacement_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.declare_management_current_city_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.read_management_current_city_report_snapshot_lifecycle_v1(uuid,uuid)'
        ) IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.pg_constraint AS constraint_row
          WHERE constraint_row.conrelid =
            'app_private.management_report_release_request_claims'::regclass
            AND constraint_row.contype = 'c'
            AND pg_catalog.pg_get_constraintdef(constraint_row.oid) LIKE
              '%current_city_management_report_snapshot_replacement%'
        )
      THEN
        RAISE EXCEPTION '0079 current-city replacement upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
current_city_replacement_release_receipts="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${current_city_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0079_management_current_city_report_snapshot_replacement_live.sql
)"
if [[ "$(printf '%s\n' "${current_city_replacement_release_receipts}" \
  | awk '/^\{.*\}$/ { count++ } END { print count+0 }')" -ne 2 ]] \
  || [[ "${current_city_replacement_release_receipts}" != \
    *'"result_status": "approved_baseline"'* ]] \
  || [[ "${current_city_replacement_release_receipts}" != \
    *'"result_status": "approved"'* ]]; then
  echo '0079 旧 writer 没有返回两份 approved value-free release receipts。' >&2
  printf '%s\n' "${current_city_replacement_release_receipts}" >&2
  exit 1
fi
current_city_replacement_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${current_city_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.management_current_city_report_snapshot_replacements \
    --restrict-key=7979797979797979797979797979797979797979797979797979797979797979
)"
docker exec \
  --env DATABASE_URL="${current_city_replacement_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/current-city-replacement-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
current_city_replacement_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${current_city_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.management_current_city_report_snapshot_replacements \
    --restrict-key=7979797979797979797979797979797979797979797979797979797979797979
)"
if [[ "${current_city_replacement_before_upgrade}" != \
  "${current_city_replacement_after_upgrade}" ]]; then
  echo '0080 升级改写了旧 current-city 发布历史或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${current_city_replacement_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.management_current_city_report_snapshot_replacements) <> 0
      THEN
        RAISE EXCEPTION '0080 replacement table is not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
current_city_replacement_first_write="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${current_city_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE current_city_replacement_input AS
      SELECT
        (SELECT released_snapshot_id
         FROM app_private.management_current_city_report_release_attempts
         WHERE release_request_id =
           '79d90000-0000-4000-8000-000000000001'::uuid)
          AS first_snapshot_id,
        (SELECT released_snapshot_id
         FROM app_private.management_current_city_report_release_attempts
         WHERE release_request_id =
           '79d90000-0000-4000-8000-000000000002'::uuid)
          AS second_snapshot_id;
      CREATE TEMP TABLE current_city_replacement_history_bytes AS
      SELECT 'snapshot'::text AS entity_kind,
        snapshot_id AS entity_id,
        to_jsonb(snapshot.*) AS entity_bytes
      FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot_id IN (
        SELECT first_snapshot_id FROM current_city_replacement_input
        UNION ALL
        SELECT second_snapshot_id FROM current_city_replacement_input
      )
      UNION ALL
      SELECT 'attempt', release_request_id, to_jsonb(attempt.*)
      FROM app_private.management_current_city_report_release_attempts
        AS attempt
      WHERE release_request_id IN (
        '79d90000-0000-4000-8000-000000000001',
        '79d90000-0000-4000-8000-000000000002'
      )
      UNION ALL
      SELECT 'claim', release_request_id, to_jsonb(claim.*)
      FROM app_private.management_report_release_request_claims AS claim
      WHERE release_request_id IN (
        '79d90000-0000-4000-8000-000000000001',
        '79d90000-0000-4000-8000-000000000002'
      );
      CREATE TEMP TABLE current_city_replacement_receipt (receipt jsonb NOT NULL);
      GRANT SELECT ON current_city_replacement_input
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
      GRANT ALL ON current_city_replacement_receipt
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
    " \
    --command="
      SET ROLE tongxingzhe_management_report_snapshot_lifecycle_writer;
      INSERT INTO current_city_replacement_receipt
      SELECT app_private.declare_management_current_city_snapshot_replacement_v1(
        '79da0000-0000-4000-8000-000000000001',
        '79d10000-0000-4000-8000-000000000001',
        '79d30000-0000-4000-8000-000000000001',
        first_snapshot_id,
        second_snapshot_id,
        'late_accepted_data'
      )
      FROM current_city_replacement_input;
      RESET ROLE;
      DO \$written\$
      DECLARE
        receipt jsonb := (
          SELECT current_city_replacement_receipt.receipt
          FROM current_city_replacement_receipt
        );
        replacement_row
          app_private.management_current_city_report_snapshot_replacements%ROWTYPE;
        first_lifecycle jsonb;
        second_lifecycle jsonb;
      BEGIN
        SELECT * INTO STRICT replacement_row
        FROM app_private.management_current_city_report_snapshot_replacements
        WHERE replacement_request_id =
          '79da0000-0000-4000-8000-000000000001'::uuid;
        first_lifecycle :=
          app_private.read_management_current_city_report_snapshot_lifecycle_v1(
            '79d30000-0000-4000-8000-000000000001',
            replacement_row.superseded_snapshot_id
          );
        second_lifecycle :=
          app_private.read_management_current_city_report_snapshot_lifecycle_v1(
            '79d30000-0000-4000-8000-000000000001',
            replacement_row.replacement_snapshot_id
          );

        IF (SELECT count(*) FROM current_city_replacement_receipt) <> 1
          OR receipt - ARRAY[
            'replacement_contract_id', 'replacement_request_id',
            'project_id', 'release_lineage_id', 'report_id', 'report_version',
            'superseded_snapshot_id', 'replacement_snapshot_id',
            'replacement_reason_code', 'declared_at_utc', 'result_status'
          ] <> '{}'::jsonb
          OR NOT receipt ?& ARRAY[
            'replacement_contract_id', 'replacement_request_id',
            'project_id', 'release_lineage_id', 'report_id', 'report_version',
            'superseded_snapshot_id', 'replacement_snapshot_id',
            'replacement_reason_code', 'declared_at_utc', 'result_status'
          ]
          OR receipt->>'replacement_contract_id' IS DISTINCT FROM
            'current_city_management_report_snapshot_replacement_v1'
          OR receipt->>'replacement_request_id' IS DISTINCT FROM
            '79da0000-0000-4000-8000-000000000001'
          OR receipt->>'project_id' IS DISTINCT FROM
            '79d30000-0000-4000-8000-000000000001'
          OR receipt->>'release_lineage_id' IS DISTINCT FROM
            'management-region-report:contact_sessions_by_current_city_two_periods'
          OR receipt->>'report_id' IS DISTINCT FROM
            'contact_sessions_by_current_city_two_periods'
          OR receipt->>'report_version' IS DISTINCT FROM '1'
          OR receipt->>'replacement_reason_code' IS DISTINCT FROM
            'late_accepted_data'
          OR receipt->>'result_status' IS DISTINCT FROM 'completed'
          OR receipt->>'superseded_snapshot_id' IS DISTINCT FROM (
            SELECT first_snapshot_id::text FROM current_city_replacement_input
          )
          OR receipt->>'replacement_snapshot_id' IS DISTINCT FROM (
            SELECT second_snapshot_id::text FROM current_city_replacement_input
          )
          OR receipt::text ~*
            '\"(protected_report|period_results|cells|value_count|contact_id|contributor|phone|email|raw_answer)\"[[:space:]]*:'
          OR replacement_row.requested_by_app_user_id IS DISTINCT FROM
            '79d10000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.organization_workspace_id IS DISTINCT FROM
            '79d20000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.organization_membership_id IS DISTINCT FROM
            '79d40000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.project_membership_id IS DISTINCT FROM
            '79d50000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.capability_grant_id IS DISTINCT FROM
            '79d60000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.capability_id IS DISTINCT FROM
            'release_management_reports'
          OR replacement_row.project_id::text IS DISTINCT FROM
            receipt->>'project_id'
          OR replacement_row.release_lineage_id IS DISTINCT FROM
            receipt->>'release_lineage_id'
          OR replacement_row.report_id IS DISTINCT FROM receipt->>'report_id'
          OR replacement_row.report_version::text IS DISTINCT FROM
            receipt->>'report_version'
          OR replacement_row.superseded_snapshot_id::text IS DISTINCT FROM
            receipt->>'superseded_snapshot_id'
          OR replacement_row.replacement_snapshot_id::text IS DISTINCT FROM
            receipt->>'replacement_snapshot_id'
          OR replacement_row.replacement_reason_code IS DISTINCT FROM
            receipt->>'replacement_reason_code'
          OR to_char(
            replacement_row.declared_at_utc AT TIME ZONE 'UTC',
            'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'
          ) IS DISTINCT FROM receipt->>'declared_at_utc'
          OR replacement_row.authorization_reference_at_utc IS DISTINCT FROM
            replacement_row.declared_at_utc
          OR NOT isfinite(replacement_row.declared_at_utc)
          OR replacement_row.result_document IS DISTINCT FROM receipt
          OR (SELECT count(*)
              FROM app_private.management_report_release_request_claims
              WHERE release_request_id =
                  '79da0000-0000-4000-8000-000000000001'::uuid
                AND release_family_id =
                  'current_city_management_report_snapshot_replacement') <> 1
          OR (SELECT count(*)
              FROM app_private.management_current_city_report_snapshot_replacements) <> 1
          OR first_lifecycle - ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ] <> '{}'::jsonb
          OR second_lifecycle - ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ] <> '{}'::jsonb
          OR NOT first_lifecycle ?& ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ]
          OR NOT second_lifecycle ?& ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ]
          OR first_lifecycle->>'lifecycle_contract_id' IS DISTINCT FROM
            'current_city_management_report_snapshot_lifecycle_v1'
          OR second_lifecycle->>'lifecycle_contract_id' IS DISTINCT FROM
            first_lifecycle->>'lifecycle_contract_id'
          OR first_lifecycle->>'project_id' IS DISTINCT FROM
            '79d30000-0000-4000-8000-000000000001'
          OR second_lifecycle->>'project_id' IS DISTINCT FROM
            first_lifecycle->>'project_id'
          OR first_lifecycle->>'snapshot_id' IS DISTINCT FROM
            replacement_row.superseded_snapshot_id::text
          OR second_lifecycle->>'snapshot_id' IS DISTINCT FROM
            replacement_row.replacement_snapshot_id::text
          OR first_lifecycle->>'lifecycle_status' IS DISTINCT FROM 'superseded'
          OR first_lifecycle->>'replacement_snapshot_id' IS DISTINCT FROM
            replacement_row.replacement_snapshot_id::text
          OR second_lifecycle->>'lifecycle_status' IS DISTINCT FROM 'active'
          OR second_lifecycle->'replacement_snapshot_id' <> 'null'::jsonb
          OR (first_lifecycle::text || second_lifecycle::text) ~*
            '\"(protected_report|period_results|cells|value_count|contact_id|contributor|phone|email|raw_answer)\"[[:space:]]*:'
          OR (SELECT count(*) FROM app_private.management_report_snapshots) <> 2
          OR (SELECT count(*)
              FROM app_private.management_current_city_report_release_attempts) <> 2
          OR (SELECT count(*) FROM current_city_replacement_history_bytes) <> 6
          OR EXISTS (
            SELECT 1
            FROM current_city_replacement_history_bytes AS saved
            LEFT JOIN LATERAL (
              SELECT to_jsonb(snapshot.*) AS current_bytes
              FROM app_private.management_report_snapshots AS snapshot
              WHERE saved.entity_kind = 'snapshot'
                AND snapshot.snapshot_id = saved.entity_id
              UNION ALL
              SELECT to_jsonb(attempt.*)
              FROM app_private.management_current_city_report_release_attempts
                AS attempt
              WHERE saved.entity_kind = 'attempt'
                AND attempt.release_request_id = saved.entity_id
              UNION ALL
              SELECT to_jsonb(claim.*)
              FROM app_private.management_report_release_request_claims AS claim
              WHERE saved.entity_kind = 'claim'
                AND claim.release_request_id = saved.entity_id
            ) AS current_row ON true
            WHERE current_row.current_bytes IS DISTINCT FROM saved.entity_bytes
          )
        THEN
          RAISE EXCEPTION '0080 current-city replacement receipt drift';
        END IF;
      END
      \$written\$;
      SELECT receipt::text FROM current_city_replacement_receipt;
    "
)"
if [[ "$(printf '%s\n' "${current_city_replacement_first_write}" \
  | awk '/^\{.*\}$/ { count++ } END { print count+0 }')" -ne 1 ]] \
  || [[ "${current_city_replacement_first_write}" != \
    *'"result_status": "completed"'* ]]; then
  echo '0080 replacement writer 没有返回唯一完整十一字段 receipt。' >&2
  printf '%s\n' "${current_city_replacement_first_write}" >&2
  exit 1
fi
current_city_replacement_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${current_city_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7979797979797979797979797979797979797979797979797979797979797979
)"
current_city_replacement_exact_replay="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${current_city_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE current_city_replacement_replay_input AS
      SELECT
        (SELECT released_snapshot_id
         FROM app_private.management_current_city_report_release_attempts
         WHERE release_request_id =
           '79d90000-0000-4000-8000-000000000001'::uuid)
          AS first_snapshot_id,
        (SELECT released_snapshot_id
         FROM app_private.management_current_city_report_release_attempts
         WHERE release_request_id =
           '79d90000-0000-4000-8000-000000000002'::uuid)
          AS second_snapshot_id;
      GRANT SELECT ON current_city_replacement_replay_input
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
      SET ROLE tongxingzhe_management_report_snapshot_lifecycle_writer;
      SELECT app_private.declare_management_current_city_snapshot_replacement_v1(
        '79da0000-0000-4000-8000-000000000001',
        '79d10000-0000-4000-8000-000000000001',
        '79d30000-0000-4000-8000-000000000001',
        first_snapshot_id,
        second_snapshot_id,
        'late_accepted_data'
      )::text
      FROM current_city_replacement_replay_input;
      RESET ROLE;
    "
)"
if [[ "${current_city_replacement_exact_replay}" != \
  "${current_city_replacement_first_write}" ]]; then
  echo '0080 current-city replacement exact replay 未返回原 receipt。' >&2
  exit 1
fi
current_city_replacement_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${current_city_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7979797979797979797979797979797979797979797979797979797979797979
)"
if [[ "${current_city_replacement_after_first_write}" != \
  "${current_city_replacement_after_exact_replay}" ]]; then
  echo '0080 current-city replacement exact replay 改写了业务数据。' >&2
  exit 1
fi
current_city_replacement_baseline_replay="$(
  docker exec \
    --env DATABASE_URL="${current_city_replacement_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/current-city-replacement-baseline-migrations \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh \
    2>&1
)"
current_city_replacement_baseline_verified_count="$(
  printf '%s\n' "${current_city_replacement_baseline_replay}" \
    | awk '/^已验证 .*（无需重复执行）$/ { count++ } END { print count+0 }'
)"
if [[ "${current_city_replacement_baseline_verified_count}" -ne 78 ]] \
  || [[ "${current_city_replacement_baseline_replay}" == *'已执行 '* ]]; then
  echo '0001..0079 重复 migrations 没有全部命中 checksum skip。' >&2
  printf '%s\n' "${current_city_replacement_baseline_replay}" >&2
  exit 1
fi
printf '%s\n' "${current_city_replacement_baseline_replay}"
current_city_replacement_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${current_city_replacement_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/current-city-replacement-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${current_city_replacement_migration_replay}" != \
  *'已验证 0080_management_current_city_report_snapshot_replacements（无需重复执行）'* ]] \
  || [[ "${current_city_replacement_migration_replay}" == *'已执行 '* ]]; then
  echo '0080 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${current_city_replacement_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${current_city_replacement_migration_replay}"
current_city_replacement_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${current_city_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7979797979797979797979797979797979797979797979797979797979797979
)"
if [[ "${current_city_replacement_after_exact_replay}" != \
  "${current_city_replacement_after_migration_replay}" ]]; then
  echo '重复 0080 migration 改写 current-city replacement 业务快照。' >&2
  exit 1
fi
echo '0079→0080 旧 current-city 快照替代、exact replay 与 checksum 幂等：通过。'


echo '验证 0081→0082 升级保留旧批准 interest 快照，并可登记替代。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${interest_replacement_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/interest-replacement-baseline-migrations \
      /tmp/interest-replacement-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-1]_*.sql' \) \
     -exec cp {} /tmp/interest-replacement-baseline-migrations/ \; && \
   test \"\$(find /tmp/interest-replacement-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 80 && \
   cp /workspace/backend/database/migrations/0082_*.sql \
     /tmp/interest-replacement-upgrade-only/ && \
   test \"\$(find /tmp/interest-replacement-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${interest_replacement_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/interest-replacement-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${interest_replacement_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 80
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM
            '0081_authorized_management_deidentified_location_anomaly_read'
        OR to_regclass(
          'app_private.management_interest_report_snapshot_replacements'
        ) IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.pg_policies
          WHERE schemaname = 'app_private'
            AND tablename = 'management_report_snapshots'
            AND policyname =
              'management_interest_snapshot_replacement_read_scope'
        )
        OR to_regprocedure(
          'app_private.interest_snapshot_replacement_provenance_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.management_interest_snapshot_has_trusted_provenance_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.validate_management_interest_snapshot_replacement_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.declare_management_interest_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.read_management_interest_report_snapshot_lifecycle_v1(uuid,uuid)'
        ) IS NOT NULL
        OR EXISTS (
          SELECT 1
          FROM pg_catalog.pg_constraint AS constraint_row
          WHERE constraint_row.conrelid =
            'app_private.management_report_release_request_claims'::regclass
            AND constraint_row.contype = 'c'
            AND pg_catalog.pg_get_constraintdef(constraint_row.oid) LIKE
              '%interest_management_report_snapshot_replacement%'
        )
      THEN
        RAISE EXCEPTION '0081 interest replacement upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
interest_replacement_release_receipts="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${interest_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0081_management_interest_report_snapshot_replacement_live.sql
)"
if [[ "$(printf '%s\n' "${interest_replacement_release_receipts}" \
  | awk '/^\{.*\}$/ { count++ } END { print count+0 }')" -ne 2 ]] \
  || [[ "${interest_replacement_release_receipts}" != \
    *'"result_status": "approved_baseline"'* ]] \
  || [[ "${interest_replacement_release_receipts}" != \
    *'"result_status": "approved"'* ]]; then
  echo '0081 旧 writer 没有返回两份 approved value-free release receipts。' >&2
  printf '%s\n' "${interest_replacement_release_receipts}" >&2
  exit 1
fi
interest_replacement_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${interest_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.management_interest_report_snapshot_replacements \
    --restrict-key=8181818181818181818181818181818181818181818181818181818181818181
)"
docker exec \
  --env DATABASE_URL="${interest_replacement_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/interest-replacement-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
interest_replacement_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${interest_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.management_interest_report_snapshot_replacements \
    --restrict-key=8181818181818181818181818181818181818181818181818181818181818181
)"
if [[ "${interest_replacement_before_upgrade}" != \
  "${interest_replacement_after_upgrade}" ]]; then
  echo '0082 升级改写了旧 interest 发布历史或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${interest_replacement_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.management_interest_report_snapshot_replacements) <> 0
      THEN
        RAISE EXCEPTION '0082 replacement table is not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
interest_replacement_first_write="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${interest_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE interest_replacement_input AS
      SELECT
        (SELECT released_snapshot_id
         FROM app_private.management_interest_report_release_attempts
         WHERE release_request_id =
           '81d90000-0000-4000-8000-000000000001'::uuid)
          AS first_snapshot_id,
        (SELECT released_snapshot_id
         FROM app_private.management_interest_report_release_attempts
         WHERE release_request_id =
           '81d90000-0000-4000-8000-000000000002'::uuid)
          AS second_snapshot_id;
      CREATE TEMP TABLE interest_replacement_history_bytes AS
      SELECT 'snapshot'::text AS entity_kind,
        snapshot_id AS entity_id,
        to_jsonb(snapshot.*) AS entity_bytes
      FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot_id IN (
        SELECT first_snapshot_id FROM interest_replacement_input
        UNION ALL
        SELECT second_snapshot_id FROM interest_replacement_input
      )
      UNION ALL
      SELECT 'attempt', release_request_id, to_jsonb(attempt.*)
      FROM app_private.management_interest_report_release_attempts
        AS attempt
      WHERE release_request_id IN (
        '81d90000-0000-4000-8000-000000000001',
        '81d90000-0000-4000-8000-000000000002'
      )
      UNION ALL
      SELECT 'claim', release_request_id, to_jsonb(claim.*)
      FROM app_private.management_report_release_request_claims AS claim
      WHERE release_request_id IN (
        '81d90000-0000-4000-8000-000000000001',
        '81d90000-0000-4000-8000-000000000002'
      );
      CREATE TEMP TABLE interest_replacement_receipt (receipt jsonb NOT NULL);
      GRANT SELECT ON interest_replacement_input
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
      GRANT ALL ON interest_replacement_receipt
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
    " \
    --command="
      SET ROLE tongxingzhe_management_report_snapshot_lifecycle_writer;
      INSERT INTO interest_replacement_receipt
      SELECT app_private.declare_management_interest_snapshot_replacement_v1(
        '81da0000-0000-4000-8000-000000000001',
        '81d10000-0000-4000-8000-000000000001',
        '81d30000-0000-4000-8000-000000000001',
        first_snapshot_id,
        second_snapshot_id,
        'late_accepted_data'
      )
      FROM interest_replacement_input;
      RESET ROLE;
      DO \$written\$
      DECLARE
        receipt jsonb := (
          SELECT interest_replacement_receipt.receipt
          FROM interest_replacement_receipt
        );
        replacement_row
          app_private.management_interest_report_snapshot_replacements%ROWTYPE;
        first_lifecycle jsonb;
        second_lifecycle jsonb;
      BEGIN
        SELECT * INTO STRICT replacement_row
        FROM app_private.management_interest_report_snapshot_replacements
        WHERE replacement_request_id =
          '81da0000-0000-4000-8000-000000000001'::uuid;
        first_lifecycle :=
          app_private.read_management_interest_report_snapshot_lifecycle_v1(
            '81d30000-0000-4000-8000-000000000001',
            replacement_row.superseded_snapshot_id
          );
        second_lifecycle :=
          app_private.read_management_interest_report_snapshot_lifecycle_v1(
            '81d30000-0000-4000-8000-000000000001',
            replacement_row.replacement_snapshot_id
          );

        IF (SELECT count(*) FROM interest_replacement_receipt) <> 1
          OR receipt - ARRAY[
            'replacement_contract_id', 'replacement_request_id',
            'project_id', 'release_lineage_id', 'report_id', 'report_version',
            'superseded_snapshot_id', 'replacement_snapshot_id',
            'replacement_reason_code', 'declared_at_utc', 'result_status'
          ] <> '{}'::jsonb
          OR NOT receipt ?& ARRAY[
            'replacement_contract_id', 'replacement_request_id',
            'project_id', 'release_lineage_id', 'report_id', 'report_version',
            'superseded_snapshot_id', 'replacement_snapshot_id',
            'replacement_reason_code', 'declared_at_utc', 'result_status'
          ]
          OR receipt->>'replacement_contract_id' IS DISTINCT FROM
            'interest_management_report_snapshot_replacement_v1'
          OR receipt->>'replacement_request_id' IS DISTINCT FROM
            '81da0000-0000-4000-8000-000000000001'
          OR receipt->>'project_id' IS DISTINCT FROM
            '81d30000-0000-4000-8000-000000000001'
          OR receipt->>'release_lineage_id' IS DISTINCT FROM
            'management-interest-report:contact_sessions_by_interest_level_two_periods'
          OR receipt->>'report_id' IS DISTINCT FROM
            'contact_sessions_by_interest_level_two_periods'
          OR receipt->>'report_version' IS DISTINCT FROM '1'
          OR receipt->>'replacement_reason_code' IS DISTINCT FROM
            'late_accepted_data'
          OR receipt->>'result_status' IS DISTINCT FROM 'completed'
          OR receipt->>'superseded_snapshot_id' IS DISTINCT FROM (
            SELECT first_snapshot_id::text FROM interest_replacement_input
          )
          OR receipt->>'replacement_snapshot_id' IS DISTINCT FROM (
            SELECT second_snapshot_id::text FROM interest_replacement_input
          )
          OR receipt::text ~*
            '\"(protected_report|period_results|ratio|coverage|contact_id|promotion_target_id|contributor|phone|email|raw_answer)\"[[:space:]]*:'
          OR replacement_row.requested_by_app_user_id IS DISTINCT FROM
            '81d10000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.organization_workspace_id IS DISTINCT FROM
            '81d20000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.organization_membership_id IS DISTINCT FROM
            '81d40000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.project_membership_id IS DISTINCT FROM
            '81d50000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.capability_grant_id IS DISTINCT FROM
            '81d60000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.capability_id IS DISTINCT FROM
            'release_management_reports'
          OR replacement_row.project_id::text IS DISTINCT FROM
            receipt->>'project_id'
          OR replacement_row.release_lineage_id IS DISTINCT FROM
            receipt->>'release_lineage_id'
          OR replacement_row.report_id IS DISTINCT FROM receipt->>'report_id'
          OR replacement_row.report_version::text IS DISTINCT FROM
            receipt->>'report_version'
          OR replacement_row.superseded_snapshot_id::text IS DISTINCT FROM
            receipt->>'superseded_snapshot_id'
          OR replacement_row.replacement_snapshot_id::text IS DISTINCT FROM
            receipt->>'replacement_snapshot_id'
          OR replacement_row.replacement_reason_code IS DISTINCT FROM
            receipt->>'replacement_reason_code'
          OR to_char(
            replacement_row.declared_at_utc AT TIME ZONE 'UTC',
            'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'
          ) IS DISTINCT FROM receipt->>'declared_at_utc'
          OR replacement_row.authorization_reference_at_utc IS DISTINCT FROM
            replacement_row.declared_at_utc
          OR NOT isfinite(replacement_row.declared_at_utc)
          OR replacement_row.result_document IS DISTINCT FROM receipt
          OR (SELECT count(*)
              FROM app_private.management_report_release_request_claims
              WHERE release_request_id =
                  '81da0000-0000-4000-8000-000000000001'::uuid
                AND release_family_id =
                  'interest_management_report_snapshot_replacement') <> 1
          OR (SELECT count(*)
              FROM app_private.management_interest_report_snapshot_replacements) <> 1
          OR first_lifecycle - ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ] <> '{}'::jsonb
          OR second_lifecycle - ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ] <> '{}'::jsonb
          OR NOT first_lifecycle ?& ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ]
          OR NOT second_lifecycle ?& ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ]
          OR first_lifecycle->>'lifecycle_contract_id' IS DISTINCT FROM
            'interest_management_report_snapshot_lifecycle_v1'
          OR second_lifecycle->>'lifecycle_contract_id' IS DISTINCT FROM
            first_lifecycle->>'lifecycle_contract_id'
          OR first_lifecycle->>'project_id' IS DISTINCT FROM
            '81d30000-0000-4000-8000-000000000001'
          OR second_lifecycle->>'project_id' IS DISTINCT FROM
            first_lifecycle->>'project_id'
          OR first_lifecycle->>'snapshot_id' IS DISTINCT FROM
            replacement_row.superseded_snapshot_id::text
          OR second_lifecycle->>'snapshot_id' IS DISTINCT FROM
            replacement_row.replacement_snapshot_id::text
          OR first_lifecycle->>'lifecycle_status' IS DISTINCT FROM 'superseded'
          OR first_lifecycle->>'replacement_snapshot_id' IS DISTINCT FROM
            replacement_row.replacement_snapshot_id::text
          OR second_lifecycle->>'lifecycle_status' IS DISTINCT FROM 'active'
          OR second_lifecycle->'replacement_snapshot_id' <> 'null'::jsonb
          OR (first_lifecycle::text || second_lifecycle::text) ~*
            '\"(protected_report|period_results|ratio|coverage|contact_id|promotion_target_id|contributor|phone|email|raw_answer)\"[[:space:]]*:'
          OR (SELECT count(*) FROM app_private.management_report_snapshots) <> 2
          OR (SELECT count(*)
              FROM app_private.management_interest_report_release_attempts) <> 2
          OR (SELECT count(*) FROM interest_replacement_history_bytes) <> 6
          OR EXISTS (
            SELECT 1
            FROM interest_replacement_history_bytes AS saved
            LEFT JOIN LATERAL (
              SELECT to_jsonb(snapshot.*) AS current_bytes
              FROM app_private.management_report_snapshots AS snapshot
              WHERE saved.entity_kind = 'snapshot'
                AND snapshot.snapshot_id = saved.entity_id
              UNION ALL
              SELECT to_jsonb(attempt.*)
              FROM app_private.management_interest_report_release_attempts
                AS attempt
              WHERE saved.entity_kind = 'attempt'
                AND attempt.release_request_id = saved.entity_id
              UNION ALL
              SELECT to_jsonb(claim.*)
              FROM app_private.management_report_release_request_claims AS claim
              WHERE saved.entity_kind = 'claim'
                AND claim.release_request_id = saved.entity_id
            ) AS current_row ON true
            WHERE current_row.current_bytes IS DISTINCT FROM saved.entity_bytes
          )
        THEN
          RAISE EXCEPTION '0082 interest replacement receipt drift';
        END IF;
      END
      \$written\$;
      SELECT receipt::text FROM interest_replacement_receipt;
    "
)"
if [[ "$(printf '%s\n' "${interest_replacement_first_write}" \
  | awk '/^\{.*\}$/ { count++ } END { print count+0 }')" -ne 1 ]] \
  || [[ "${interest_replacement_first_write}" != \
    *'"result_status": "completed"'* ]]; then
  echo '0082 replacement writer 没有返回唯一完整十一字段 receipt。' >&2
  printf '%s\n' "${interest_replacement_first_write}" >&2
  exit 1
fi
interest_replacement_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${interest_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8181818181818181818181818181818181818181818181818181818181818181
)"
interest_replacement_exact_replay="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${interest_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE interest_replacement_replay_input AS
      SELECT
        (SELECT released_snapshot_id
         FROM app_private.management_interest_report_release_attempts
         WHERE release_request_id =
           '81d90000-0000-4000-8000-000000000001'::uuid)
          AS first_snapshot_id,
        (SELECT released_snapshot_id
         FROM app_private.management_interest_report_release_attempts
         WHERE release_request_id =
           '81d90000-0000-4000-8000-000000000002'::uuid)
          AS second_snapshot_id;
      GRANT SELECT ON interest_replacement_replay_input
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
      SET ROLE tongxingzhe_management_report_snapshot_lifecycle_writer;
      SELECT app_private.declare_management_interest_snapshot_replacement_v1(
        '81da0000-0000-4000-8000-000000000001',
        '81d10000-0000-4000-8000-000000000001',
        '81d30000-0000-4000-8000-000000000001',
        first_snapshot_id,
        second_snapshot_id,
        'late_accepted_data'
      )::text
      FROM interest_replacement_replay_input;
      RESET ROLE;
    "
)"
if [[ "${interest_replacement_exact_replay}" != \
  "${interest_replacement_first_write}" ]]; then
  echo '0082 interest replacement exact replay 未返回原 receipt。' >&2
  exit 1
fi
interest_replacement_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${interest_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8181818181818181818181818181818181818181818181818181818181818181
)"
if [[ "${interest_replacement_after_first_write}" != \
  "${interest_replacement_after_exact_replay}" ]]; then
  echo '0082 interest replacement exact replay 改写了业务数据。' >&2
  exit 1
fi
interest_replacement_baseline_replay="$(
  docker exec \
    --env DATABASE_URL="${interest_replacement_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/interest-replacement-baseline-migrations \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh \
    2>&1
)"
interest_replacement_baseline_verified_count="$(
  printf '%s\n' "${interest_replacement_baseline_replay}" \
    | awk '/^已验证 .*（无需重复执行）$/ { count++ } END { print count+0 }'
)"
if [[ "${interest_replacement_baseline_verified_count}" -ne 80 ]] \
  || [[ "${interest_replacement_baseline_replay}" == *'已执行 '* ]]; then
  echo '0001..0081 重复 migrations 没有全部命中 checksum skip。' >&2
  printf '%s\n' "${interest_replacement_baseline_replay}" >&2
  exit 1
fi
printf '%s\n' "${interest_replacement_baseline_replay}"
interest_replacement_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${interest_replacement_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/interest-replacement-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${interest_replacement_migration_replay}" != \
  *'已验证 0082_management_interest_report_snapshot_replacements（无需重复执行）'* ]] \
  || [[ "${interest_replacement_migration_replay}" == *'已执行 '* ]]; then
  echo '0082 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${interest_replacement_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${interest_replacement_migration_replay}"
interest_replacement_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${interest_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8181818181818181818181818181818181818181818181818181818181818181
)"
if [[ "${interest_replacement_after_exact_replay}" != \
  "${interest_replacement_after_migration_replay}" ]]; then
  echo '重复 0082 migration 改写 interest replacement 业务快照。' >&2
  exit 1
fi
echo '0081→0082 旧 interest 快照替代、exact replay 与 checksum 幂等：通过。'

echo '验证 0082→0083 升级保留旧批准同意占比快照，并可在停用后登记替代。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${consent_replacement_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/consent-replacement-baseline-migrations \
      /tmp/consent-replacement-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-2]_*.sql' \) \
     -exec cp {} /tmp/consent-replacement-baseline-migrations/ \; && \
   test \"\$(find /tmp/consent-replacement-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 81 && \
   cp /workspace/backend/database/migrations/0083_*.sql \
     /tmp/consent-replacement-upgrade-only/ && \
   test \"\$(find /tmp/consent-replacement-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${consent_replacement_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/consent-replacement-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${consent_replacement_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 81
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM
            '0082_management_interest_report_snapshot_replacements'
        OR to_regclass(
          'app_private.management_follow_up_consent_ratio_report_snapshot_replacements'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.follow_up_consent_ratio_snapshot_replacement_provenance_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.management_follow_up_consent_snapshot_has_trusted_provenance_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.validate_management_follow_up_consent_snapshot_replacement_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.declare_management_follow_up_consent_snapshot_replacement_v1(uuid,uuid,uuid,uuid,uuid,text)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(uuid,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0082 consent replacement upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
consent_replacement_release_receipts="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${consent_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0082_management_follow_up_consent_ratio_snapshot_replacement_live.sql
)"
if [[ "$(printf '%s\n' "${consent_replacement_release_receipts}" \
  | awk '/^\{.*\}$/ { count++ } END { print count+0 }')" -ne 2 ]] \
  || [[ "${consent_replacement_release_receipts}" != \
    *'"result_status": "approved_baseline"'* ]] \
  || [[ "${consent_replacement_release_receipts}" != \
    *'"result_status": "approved"'* ]]; then
  echo '0082 旧 writer 没有返回两份 approved value-free release receipts。' >&2
  printf '%s\n' "${consent_replacement_release_receipts}" >&2
  exit 1
fi
consent_replacement_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${consent_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.management_follow_up_consent_ratio_report_snapshot_replacements \
    --restrict-key=8282828282828282828282828282828282828282828282828282828282828282
)"
docker exec \
  --env DATABASE_URL="${consent_replacement_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/consent-replacement-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
consent_replacement_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${consent_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.management_follow_up_consent_ratio_report_snapshot_replacements \
    --restrict-key=8282828282828282828282828282828282828282828282828282828282828282
)"
if [[ "${consent_replacement_before_upgrade}" != \
  "${consent_replacement_after_upgrade}" ]]; then
  echo '0083 升级改写了旧 consent-ratio 发布历史或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${consent_replacement_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements) <> 0
      THEN
        RAISE EXCEPTION '0083 replacement table is not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
consent_replacement_first_write="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${consent_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE consent_replacement_input AS
      SELECT
        (SELECT released_snapshot_id
         FROM app_private.management_follow_up_consent_report_release_attempts
         WHERE release_request_id =
           '82d90000-0000-4000-8000-000000000001'::uuid)
          AS first_snapshot_id,
        (SELECT released_snapshot_id
         FROM app_private.management_follow_up_consent_report_release_attempts
         WHERE release_request_id =
           '82d90000-0000-4000-8000-000000000002'::uuid)
          AS second_snapshot_id;
      CREATE TEMP TABLE consent_replacement_history_bytes AS
      SELECT 'snapshot'::text AS entity_kind,
        snapshot_id AS entity_id,
        to_jsonb(snapshot.*) AS entity_bytes
      FROM app_private.management_report_snapshots AS snapshot
      WHERE snapshot_id IN (
        SELECT first_snapshot_id FROM consent_replacement_input
        UNION ALL
        SELECT second_snapshot_id FROM consent_replacement_input
      )
      UNION ALL
      SELECT 'attempt', release_request_id, to_jsonb(attempt.*)
      FROM app_private.management_follow_up_consent_report_release_attempts
        AS attempt
      WHERE release_request_id IN (
        '82d90000-0000-4000-8000-000000000001',
        '82d90000-0000-4000-8000-000000000002'
      )
      UNION ALL
      SELECT 'claim', release_request_id, to_jsonb(claim.*)
      FROM app_private.management_report_release_request_claims AS claim
      WHERE release_request_id IN (
        '82d90000-0000-4000-8000-000000000001',
        '82d90000-0000-4000-8000-000000000002'
      );
      CREATE TEMP TABLE consent_replacement_receipt (receipt jsonb NOT NULL);
      GRANT SELECT ON consent_replacement_input
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
      GRANT ALL ON consent_replacement_receipt
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
    " \
    --command="
      SET ROLE tongxingzhe_management_report_snapshot_lifecycle_writer;
      INSERT INTO consent_replacement_receipt
      SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
        '82da0000-0000-4000-8000-000000000001',
        '82d10000-0000-4000-8000-000000000001',
        '82d30000-0000-4000-8000-000000000001',
        first_snapshot_id,
        second_snapshot_id,
        'late_accepted_data'
      )
      FROM consent_replacement_input;
      RESET ROLE;
      DO \$written\$
      DECLARE
        receipt jsonb := (
          SELECT consent_replacement_receipt.receipt
          FROM consent_replacement_receipt
        );
        replacement_row
          app_private.management_follow_up_consent_ratio_report_snapshot_replacements%ROWTYPE;
        first_lifecycle jsonb;
        second_lifecycle jsonb;
      BEGIN
        SELECT * INTO STRICT replacement_row
        FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements
        WHERE replacement_request_id =
          '82da0000-0000-4000-8000-000000000001'::uuid;
        first_lifecycle :=
          app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(
            '82d30000-0000-4000-8000-000000000001',
            replacement_row.superseded_snapshot_id
          );
        second_lifecycle :=
          app_private.read_management_follow_up_consent_snapshot_lifecycle_v1(
            '82d30000-0000-4000-8000-000000000001',
            replacement_row.replacement_snapshot_id
          );

        IF (SELECT count(*) FROM consent_replacement_receipt) <> 1
          OR receipt - ARRAY[
            'replacement_contract_id', 'replacement_request_id',
            'project_id', 'release_lineage_id', 'report_id', 'report_version',
            'superseded_snapshot_id', 'replacement_snapshot_id',
            'replacement_reason_code', 'declared_at_utc', 'result_status'
          ] <> '{}'::jsonb
          OR NOT receipt ?& ARRAY[
            'replacement_contract_id', 'replacement_request_id',
            'project_id', 'release_lineage_id', 'report_id', 'report_version',
            'superseded_snapshot_id', 'replacement_snapshot_id',
            'replacement_reason_code', 'declared_at_utc', 'result_status'
          ]
          OR receipt->>'replacement_contract_id' IS DISTINCT FROM
            'follow_up_consent_ratio_management_report_snapshot_replacement_v1'
          OR receipt->>'replacement_request_id' IS DISTINCT FROM
            '82da0000-0000-4000-8000-000000000001'
          OR receipt->>'project_id' IS DISTINCT FROM
            '82d30000-0000-4000-8000-000000000001'
          OR receipt->>'release_lineage_id' IS DISTINCT FROM
            'management-follow-up-consent-ratio-report:contact_target_follow_up_consent_ratio_two_periods'
          OR receipt->>'report_id' IS DISTINCT FROM
            'contact_target_follow_up_consent_ratio_two_periods'
          OR receipt->>'report_version' IS DISTINCT FROM '1'
          OR receipt->>'replacement_reason_code' IS DISTINCT FROM
            'late_accepted_data'
          OR receipt->>'result_status' IS DISTINCT FROM 'completed'
          OR receipt->>'superseded_snapshot_id' IS DISTINCT FROM (
            SELECT first_snapshot_id::text FROM consent_replacement_input
          )
          OR receipt->>'replacement_snapshot_id' IS DISTINCT FROM (
            SELECT second_snapshot_id::text FROM consent_replacement_input
          )
          OR receipt::text ~*
            '\"(protected_report|period_results|ratio|coverage|contact_id|promotion_target_id|contributor|phone|email|raw_answer)\"[[:space:]]*:'
          OR replacement_row.requested_by_app_user_id IS DISTINCT FROM
            '82d10000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.organization_workspace_id IS DISTINCT FROM
            '82d20000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.organization_membership_id IS DISTINCT FROM
            '82d40000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.project_membership_id IS DISTINCT FROM
            '82d50000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.capability_grant_id IS DISTINCT FROM
            '82d60000-0000-4000-8000-000000000001'::uuid
          OR replacement_row.capability_id IS DISTINCT FROM
            'release_management_reports'
          OR replacement_row.project_id::text IS DISTINCT FROM
            receipt->>'project_id'
          OR replacement_row.release_lineage_id IS DISTINCT FROM
            receipt->>'release_lineage_id'
          OR replacement_row.report_id IS DISTINCT FROM receipt->>'report_id'
          OR replacement_row.report_version::text IS DISTINCT FROM
            receipt->>'report_version'
          OR replacement_row.superseded_snapshot_id::text IS DISTINCT FROM
            receipt->>'superseded_snapshot_id'
          OR replacement_row.replacement_snapshot_id::text IS DISTINCT FROM
            receipt->>'replacement_snapshot_id'
          OR replacement_row.replacement_reason_code IS DISTINCT FROM
            receipt->>'replacement_reason_code'
          OR to_char(
            replacement_row.declared_at_utc AT TIME ZONE 'UTC',
            'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"'
          ) IS DISTINCT FROM receipt->>'declared_at_utc'
          OR replacement_row.authorization_reference_at_utc IS DISTINCT FROM
            replacement_row.declared_at_utc
          OR NOT isfinite(replacement_row.declared_at_utc)
          OR replacement_row.result_document IS DISTINCT FROM receipt
          OR (SELECT count(*)
              FROM app_private.management_report_release_request_claims
              WHERE release_request_id =
                  '82da0000-0000-4000-8000-000000000001'::uuid
                AND release_family_id =
                  'follow_up_consent_ratio_management_report_snapshot_replacement') <> 1
          OR (SELECT count(*)
              FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements) <> 1
          OR first_lifecycle - ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ] <> '{}'::jsonb
          OR second_lifecycle - ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ] <> '{}'::jsonb
          OR NOT first_lifecycle ?& ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ]
          OR NOT second_lifecycle ?& ARRAY[
            'lifecycle_contract_id', 'project_id', 'snapshot_id',
            'lifecycle_status', 'replacement_snapshot_id'
          ]
          OR first_lifecycle->>'lifecycle_contract_id' IS DISTINCT FROM
            'follow_up_consent_ratio_management_report_snapshot_lifecycle_v1'
          OR second_lifecycle->>'lifecycle_contract_id' IS DISTINCT FROM
            first_lifecycle->>'lifecycle_contract_id'
          OR first_lifecycle->>'project_id' IS DISTINCT FROM
            '82d30000-0000-4000-8000-000000000001'
          OR second_lifecycle->>'project_id' IS DISTINCT FROM
            first_lifecycle->>'project_id'
          OR first_lifecycle->>'snapshot_id' IS DISTINCT FROM
            replacement_row.superseded_snapshot_id::text
          OR second_lifecycle->>'snapshot_id' IS DISTINCT FROM
            replacement_row.replacement_snapshot_id::text
          OR first_lifecycle->>'lifecycle_status' IS DISTINCT FROM 'superseded'
          OR first_lifecycle->>'replacement_snapshot_id' IS DISTINCT FROM
            replacement_row.replacement_snapshot_id::text
          OR second_lifecycle->>'lifecycle_status' IS DISTINCT FROM 'active'
          OR second_lifecycle->'replacement_snapshot_id' <> 'null'::jsonb
          OR (first_lifecycle::text || second_lifecycle::text) ~*
            '\"(protected_report|period_results|ratio|coverage|contact_id|promotion_target_id|contributor|phone|email|raw_answer)\"[[:space:]]*:'
          OR (SELECT count(*) FROM app_private.management_report_snapshots) <> 2
          OR (SELECT count(*)
              FROM app_private.management_follow_up_consent_report_release_attempts) <> 2
          OR (SELECT count(*) FROM consent_replacement_history_bytes) <> 6
          OR EXISTS (
            SELECT 1
            FROM consent_replacement_history_bytes AS saved
            LEFT JOIN LATERAL (
              SELECT to_jsonb(snapshot.*) AS current_bytes
              FROM app_private.management_report_snapshots AS snapshot
              WHERE saved.entity_kind = 'snapshot'
                AND snapshot.snapshot_id = saved.entity_id
              UNION ALL
              SELECT to_jsonb(attempt.*)
              FROM app_private.management_follow_up_consent_report_release_attempts
                AS attempt
              WHERE saved.entity_kind = 'attempt'
                AND attempt.release_request_id = saved.entity_id
              UNION ALL
              SELECT to_jsonb(claim.*)
              FROM app_private.management_report_release_request_claims AS claim
              WHERE saved.entity_kind = 'claim'
                AND claim.release_request_id = saved.entity_id
            ) AS current_row ON true
            WHERE current_row.current_bytes IS DISTINCT FROM saved.entity_bytes
          )
        THEN
          RAISE EXCEPTION '0083 consent replacement receipt drift';
        END IF;
      END
      \$written\$;
      SELECT receipt::text FROM consent_replacement_receipt;
    "
)"
if [[ "$(printf '%s\n' "${consent_replacement_first_write}" \
  | awk '/^\{.*\}$/ { count++ } END { print count+0 }')" -ne 1 ]] \
  || [[ "${consent_replacement_first_write}" != \
    *'"result_status": "completed"'* ]]; then
  echo '0083 replacement writer 没有返回唯一完整十一字段 receipt。' >&2
  printf '%s\n' "${consent_replacement_first_write}" >&2
  exit 1
fi
consent_replacement_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${consent_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8282828282828282828282828282828282828282828282828282828282828282
)"
consent_replacement_exact_replay="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${consent_replacement_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE consent_replacement_replay_input AS
      SELECT
        (SELECT released_snapshot_id
         FROM app_private.management_follow_up_consent_report_release_attempts
         WHERE release_request_id =
           '82d90000-0000-4000-8000-000000000001'::uuid)
          AS first_snapshot_id,
        (SELECT released_snapshot_id
         FROM app_private.management_follow_up_consent_report_release_attempts
         WHERE release_request_id =
           '82d90000-0000-4000-8000-000000000002'::uuid)
          AS second_snapshot_id;
      GRANT SELECT ON consent_replacement_replay_input
        TO tongxingzhe_management_report_snapshot_lifecycle_writer;
      SET ROLE tongxingzhe_management_report_snapshot_lifecycle_writer;
      SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
        '82da0000-0000-4000-8000-000000000001',
        '82d10000-0000-4000-8000-000000000001',
        '82d30000-0000-4000-8000-000000000001',
        first_snapshot_id,
        second_snapshot_id,
        'late_accepted_data'
      )::text
      FROM consent_replacement_replay_input;
      RESET ROLE;
    "
)"
if [[ "${consent_replacement_exact_replay}" != \
  "${consent_replacement_first_write}" ]]; then
  echo '0083 consent replacement exact replay 未返回原 receipt。' >&2
  exit 1
fi
consent_replacement_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${consent_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8282828282828282828282828282828282828282828282828282828282828282
)"
if [[ "${consent_replacement_after_first_write}" != \
  "${consent_replacement_after_exact_replay}" ]]; then
  echo '0083 consent replacement exact replay 改写了业务数据。' >&2
  exit 1
fi
consent_replacement_baseline_replay="$(
  docker exec \
    --env DATABASE_URL="${consent_replacement_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/consent-replacement-baseline-migrations \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh \
    2>&1
)"
consent_replacement_baseline_verified_count="$(
  printf '%s\n' "${consent_replacement_baseline_replay}" \
    | awk '/^已验证 .*（无需重复执行）$/ { count++ } END { print count+0 }'
)"
if [[ "${consent_replacement_baseline_verified_count}" -ne 81 ]] \
  || [[ "${consent_replacement_baseline_replay}" == *'已执行 '* ]]; then
  echo '0001..0082 重复 migrations 没有全部命中 checksum skip。' >&2
  printf '%s\n' "${consent_replacement_baseline_replay}" >&2
  exit 1
fi
printf '%s\n' "${consent_replacement_baseline_replay}"
consent_replacement_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${consent_replacement_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/consent-replacement-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${consent_replacement_migration_replay}" != \
  *'已验证 0083_management_follow_up_consent_ratio_snapshot_replacements（无需重复执行）'* ]] \
  || [[ "${consent_replacement_migration_replay}" == *'已执行 '* ]]; then
  echo '0083 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${consent_replacement_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${consent_replacement_migration_replay}"
consent_replacement_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${consent_replacement_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8282828282828282828282828282828282828282828282828282828282828282
)"
if [[ "${consent_replacement_after_exact_replay}" != \
  "${consent_replacement_after_migration_replay}" ]]; then
  echo '重复 0083 migration 改写 consent replacement 业务快照。' >&2
  exit 1
fi
echo '0082→0083 旧快照、停用后替代、exact replay 与 checksum 幂等：通过。'

echo '验证 0085 拒绝无 owner 历史组织，并完整回滚 migration。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${ownerless_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "source_migration_count=\"\$(find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-4]_*.sql' \) \
     | wc -l | tr -d ' ')\" && \
   mkdir /tmp/ownerless-upgrade-migrations && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-4]_*.sql' \) \
     -exec cp {} /tmp/ownerless-upgrade-migrations/ \; && \
   test \"\$(find /tmp/ownerless-upgrade-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" \
     -eq \"\${source_migration_count}\" && \
   test -f /tmp/ownerless-upgrade-migrations/0084_*.sql"
docker exec \
  --env DATABASE_URL="${ownerless_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/ownerless-upgrade-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${ownerless_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    SET TIME ZONE 'UTC';
    INSERT INTO app_data.app_users (app_user_id, status)
    VALUES ('00000000-0085-0000-0000-000000000901'::uuid, 'active');
    INSERT INTO app_data.workspaces (
      workspace_id,
      workspace_kind,
      display_name,
      personal_owner_app_user_id,
      deleted_at
    ) VALUES (
      '00000000-0085-1000-0000-000000000901'::uuid,
      'organization',
      '0085 ownerless upgrade organization',
      NULL,
      NULL
    );
    INSERT INTO app_data.organization_memberships (
      organization_membership_id,
      organization_workspace_id,
      app_user_id,
      active_from_utc,
      inactive_from_utc
    ) VALUES (
      '00000000-0085-1100-0000-000000000901'::uuid,
      '00000000-0085-1000-0000-000000000901'::uuid,
      '00000000-0085-0000-0000-000000000901'::uuid,
      clock_timestamp() - interval '1 hour',
      NULL
    );
  " \
  >/dev/null
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/ownerless-upgrade-only && \
   cp /workspace/backend/database/migrations/0085_*.sql \
     /tmp/ownerless-upgrade-only/ && \
   test \"\$(find /tmp/ownerless-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
ownerless_upgrade_output=''
ownerless_upgrade_status=0
ownerless_upgrade_output="$(
  docker exec \
    --env DATABASE_URL="${ownerless_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/ownerless-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh \
    2>&1
)" || ownerless_upgrade_status=$?
if [[ "${ownerless_upgrade_status}" -eq 0 ]] \
  || [[ "${ownerless_upgrade_output}" != *'organization must retain an active owner'* ]]
then
  echo '0085 无 owner 升级没有按预期失败，或缺少固定错误 message。' >&2
  printf '%s\n' "${ownerless_upgrade_output}" >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${ownerless_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$check\$
    DECLARE
      trigger_count integer;
      function_count integer;
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM app_migrations.schema_migrations
        WHERE version = '0085_organization_owner_invariant'
      ) THEN
        RAISE EXCEPTION '0085 migration record survived failed upgrade';
      END IF;

      SELECT count(*)
      INTO function_count
      FROM (
        VALUES
          (to_regprocedure(
            'app_private.lock_organization_governance_v1(uuid)'
          )),
          (to_regprocedure(
            'app_private.lock_organization_governance_for_mutation_v1()'
          )),
          (to_regprocedure(
            'app_private.require_organization_active_owner_v1(uuid)'
          )),
          (to_regprocedure(
            'app_private.enforce_organization_active_owner_v1()'
          ))
      ) AS expected_functions(function_identity)
      WHERE function_identity IS NOT NULL;
      IF function_count <> 0 THEN
        RAISE EXCEPTION
          '0085 functions survived failed upgrade: %', function_count;
      END IF;

      SELECT count(*)
      INTO trigger_count
      FROM pg_catalog.pg_trigger AS trigger_row
      JOIN pg_catalog.pg_class AS relation_row
        ON relation_row.oid = trigger_row.tgrelid
      JOIN pg_catalog.pg_namespace AS namespace_row
        ON namespace_row.oid = relation_row.relnamespace
      WHERE namespace_row.nspname = 'app_data'
        AND trigger_row.tgname IN (
          'workspaces_governance_fence',
          'organization_memberships_governance_fence',
          'organization_owner_assignments_governance_fence',
          'app_users_governance_fence',
          'workspaces_active_owner_invariant',
          'organization_memberships_active_owner_invariant',
          'organization_owner_assignments_active_owner_invariant',
          'app_users_active_owner_invariant'
        );
      IF trigger_count <> 0 THEN
        RAISE EXCEPTION
          '0085 triggers survived failed upgrade: %', trigger_count;
      END IF;
    END
    \$check\$;
  " \
  >/dev/null
echo '0085 无 owner 升级失败且事务完整回滚：通过。'

echo '验证 0085→0086 升级后旧组织可交接负责人。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${owner_transfer_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/owner-transfer-baseline-migrations \
      /tmp/owner-transfer-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-5]_*.sql' \) \
     -exec cp {} /tmp/owner-transfer-baseline-migrations/ \; && \
   test \"\$(find /tmp/owner-transfer-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 84 && \
   cp /workspace/backend/database/migrations/0086_*.sql \
     /tmp/owner-transfer-upgrade-only/ && \
   test \"\$(find /tmp/owner-transfer-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${owner_transfer_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/owner-transfer-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${owner_transfer_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 84
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM '0085_organization_owner_invariant'
        OR to_regclass(
          'app_private.organization_owner_transfer_request_claims'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_owner_transfer_request_tombstones'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_owner_transfer_audit_events'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_owner_transfer_request_claim_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_owner_transfer_request_tombstone_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_owner_transfer_audit_event_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.transfer_organization_owner_for_identity_v1(text,text,uuid,uuid,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0085 owner-transfer upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
owner_transfer_creation_receipt="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${owner_transfer_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0085_organization_owner_transfer_live.sql
)"
if [[ "${owner_transfer_creation_receipt}" != organization-creation:v1\|* ]] \
  || [[ "$(printf '%s\n' "${owner_transfer_creation_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0085 旧 writer 没有返回单行完整五字段 creation receipt。' >&2
  exit 1
fi
owner_transfer_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${owner_transfer_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_owner_transfer_request_claims \
    --exclude-table-data=app_private.organization_owner_transfer_request_tombstones \
    --exclude-table-data=app_private.organization_owner_transfer_audit_events \
    --restrict-key=8585858585858585858585858585858585858585858585858585858585858585
)"
docker exec \
  --env DATABASE_URL="${owner_transfer_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/owner-transfer-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
owner_transfer_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${owner_transfer_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_owner_transfer_request_claims \
    --exclude-table-data=app_private.organization_owner_transfer_request_tombstones \
    --exclude-table-data=app_private.organization_owner_transfer_audit_events \
    --restrict-key=8585858585858585858585858585858585858585858585858585858585858585
)"
if [[ "${owner_transfer_before_upgrade}" != \
  "${owner_transfer_after_upgrade}" ]]; then
  echo '0086 升级改变了旧组织、owner 或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${owner_transfer_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.organization_owner_transfer_request_claims) <> 0
        OR (SELECT count(*)
            FROM app_private.organization_owner_transfer_request_tombstones) <> 0
        OR (SELECT count(*)
            FROM app_private.organization_owner_transfer_audit_events) <> 0
      THEN
        RAISE EXCEPTION '0086 owner-transfer tables are not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
owner_transfer_first_write="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${owner_transfer_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE owner_transfer_receipt (
        owner_transfer_contract_id text,
        organization_workspace_id uuid,
        previous_owner_assignment_id uuid,
        organization_owner_assignment_id uuid,
        effective_at_utc timestamptz
      );
      CREATE TEMP TABLE owner_transfer_input AS
      SELECT organization_workspace_id,
        '00000000-0085-3000-0000-000000000502'::uuid
          AS target_organization_membership_id
      FROM app_private.organization_creation_request_claims
      WHERE request_id =
        '00000000-0085-5000-0000-000000000501'::uuid;
      GRANT ALL ON owner_transfer_receipt TO tongxingzhe_runtime;
      GRANT SELECT ON owner_transfer_input TO tongxingzhe_runtime;
    " \
    --command="
      CREATE TEMP TABLE owner_transfer_clock_bounds AS
      SELECT clock_timestamp() AS observed_before,
        NULL::timestamptz AS observed_after;
    " \
    --command="
      SET ROLE tongxingzhe_runtime;
      INSERT INTO owner_transfer_receipt
      SELECT *
      FROM app_data.transfer_organization_owner_for_identity_v1(
        'https://synthetic-owner-transfer-upgrade.example/auth/v1',
        'owner',
        '00000000-0086-6000-0000-000000000501',
        (SELECT organization_workspace_id FROM owner_transfer_input),
        (SELECT target_organization_membership_id FROM owner_transfer_input)
      );
      RESET ROLE;
      UPDATE owner_transfer_clock_bounds
      SET observed_after = clock_timestamp();
      TABLE owner_transfer_receipt;
      DO \$written\$
      DECLARE
        receipt owner_transfer_receipt%ROWTYPE;
        bounds owner_transfer_clock_bounds%ROWTYPE;
        creation app_private.organization_creation_request_claims%ROWTYPE;
        transfer app_private.organization_owner_transfer_request_claims%ROWTYPE;
      BEGIN
        SELECT * INTO STRICT receipt FROM owner_transfer_receipt;
        SELECT * INTO STRICT bounds FROM owner_transfer_clock_bounds;
        SELECT * INTO STRICT creation
        FROM app_private.organization_creation_request_claims
        WHERE request_id =
          '00000000-0085-5000-0000-000000000501'::uuid;
        SELECT * INTO STRICT transfer
        FROM app_private.organization_owner_transfer_request_claims
        WHERE request_id =
          '00000000-0086-6000-0000-000000000501'::uuid;

        IF (SELECT count(*) FROM owner_transfer_receipt) <> 1
          OR receipt.owner_transfer_contract_id IS DISTINCT FROM
            'organization-owner-transfer:v1'
          OR receipt.organization_workspace_id IS DISTINCT FROM
            creation.organization_workspace_id
          OR receipt.previous_owner_assignment_id IS DISTINCT FROM
            creation.organization_owner_assignment_id
          OR receipt.organization_owner_assignment_id IS NULL
          OR receipt.organization_owner_assignment_id =
            receipt.previous_owner_assignment_id
          OR receipt.effective_at_utc IS NULL
          OR NOT isfinite(receipt.effective_at_utc)
          OR receipt.effective_at_utc < bounds.observed_before
          OR receipt.effective_at_utc > bounds.observed_after
          OR transfer.actor_app_user_id IS DISTINCT FROM
            '00000000-0085-0000-0000-000000000501'::uuid
          OR transfer.organization_workspace_id IS DISTINCT FROM
            receipt.organization_workspace_id
          OR transfer.target_organization_membership_id IS DISTINCT FROM
            '00000000-0085-3000-0000-000000000502'::uuid
          OR transfer.previous_owner_assignment_id IS DISTINCT FROM
            receipt.previous_owner_assignment_id
          OR transfer.organization_owner_assignment_id IS DISTINCT FROM
            receipt.organization_owner_assignment_id
          OR transfer.effective_at_utc IS DISTINCT FROM
            receipt.effective_at_utc
          OR (SELECT count(*)
              FROM app_private.organization_owner_transfer_request_claims) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_owner_transfer_request_tombstones) <> 0
          OR (SELECT count(*)
              FROM app_private.organization_owner_transfer_audit_events) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_owner_transfer_audit_events
              WHERE owner_transfer_contract_id =
                  receipt.owner_transfer_contract_id
                AND request_id =
                  '00000000-0086-6000-0000-000000000501'::uuid
                AND organization_workspace_id =
                  receipt.organization_workspace_id
                AND previous_owner_assignment_id =
                  receipt.previous_owner_assignment_id
                AND organization_owner_assignment_id =
                  receipt.organization_owner_assignment_id
                AND effective_at_utc = receipt.effective_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments
              WHERE organization_owner_assignment_id =
                  receipt.previous_owner_assignment_id
                AND organization_membership_id =
                  creation.organization_membership_id
                AND active_from_utc = creation.created_at_utc
                AND inactive_from_utc = receipt.effective_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments
              WHERE organization_owner_assignment_id =
                  receipt.organization_owner_assignment_id
                AND organization_membership_id =
                  '00000000-0085-3000-0000-000000000502'::uuid
                AND active_from_utc = receipt.effective_at_utc
                AND inactive_from_utc IS NULL) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments) <> 2
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments
              WHERE inactive_from_utc IS NULL) <> 1
          OR EXISTS (
            SELECT 1
            FROM app_data.organization_owner_assignments
            WHERE organization_membership_id =
                creation.organization_membership_id
              AND inactive_from_utc IS NULL
          )
          OR (SELECT count(*)
              FROM app_data.organization_memberships
              WHERE organization_workspace_id =
                  receipt.organization_workspace_id
                AND inactive_from_utc IS NULL) <> 2
          OR (SELECT count(*) FROM app_data.organization_memberships) <> 2
          OR (SELECT count(*)
              FROM app_private.organization_creation_request_claims) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_creation_audit_events) <> 1
          OR (SELECT count(*) FROM app_data.projects) <> 0
          OR (SELECT count(*) FROM app_data.project_memberships) <> 0
          OR (SELECT count(*)
              FROM app_data.management_report_capability_grants) <> 0
          OR (SELECT count(*)
              FROM app_data.promotion_target_assignments) <> 0
        THEN
          RAISE EXCEPTION '0086 owner-transfer receipt drift';
        END IF;
      END
      \$written\$;
    "
)"
if [[ "${owner_transfer_first_write}" != organization-owner-transfer:v1\|* ]] \
  || [[ "$(printf '%s\n' "${owner_transfer_first_write}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0086 owner-transfer writer 没有返回单行完整五字段 receipt。' >&2
  exit 1
fi
owner_transfer_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${owner_transfer_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8585858585858585858585858585858585858585858585858585858585858585
)"
owner_transfer_exact_replay="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${owner_transfer_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE owner_transfer_replay_input AS
      SELECT organization_workspace_id
      FROM app_private.organization_creation_request_claims
      WHERE request_id =
        '00000000-0085-5000-0000-000000000501'::uuid;
      GRANT SELECT ON owner_transfer_replay_input TO tongxingzhe_runtime;
    " \
    --command="
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.transfer_organization_owner_for_identity_v1(
        'https://synthetic-owner-transfer-upgrade.example/auth/v1',
        'owner',
        '00000000-0086-6000-0000-000000000501',
        (SELECT organization_workspace_id
         FROM owner_transfer_replay_input),
        '00000000-0085-3000-0000-000000000502'
      );
      RESET ROLE;
    "
)"
if [[ "${owner_transfer_exact_replay}" != \
  "${owner_transfer_first_write}" ]]; then
  echo '原 actor 失去 owner 身份后 exact replay 未返回原 receipt。' >&2
  exit 1
fi
owner_transfer_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${owner_transfer_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8585858585858585858585858585858585858585858585858585858585858585
)"
if [[ "${owner_transfer_after_first_write}" != \
  "${owner_transfer_after_exact_replay}" ]]; then
  echo '0086 owner-transfer exact replay 改变了业务数据。' >&2
  exit 1
fi
owner_transfer_baseline_replay="$(
  docker exec \
    --env DATABASE_URL="${owner_transfer_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/owner-transfer-baseline-migrations \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh \
    2>&1
)"
owner_transfer_baseline_verified_count="$(
  printf '%s\n' "${owner_transfer_baseline_replay}" \
    | awk '/^已验证 .*（无需重复执行）$/ { count++ } END { print count+0 }'
)"
if [[ "${owner_transfer_baseline_verified_count}" -ne 84 ]] \
  || [[ "${owner_transfer_baseline_replay}" == *'已执行 '* ]]; then
  echo '0001..0085 重复 migrations 没有全部命中 checksum skip。' >&2
  printf '%s\n' "${owner_transfer_baseline_replay}" >&2
  exit 1
fi
printf '%s\n' "${owner_transfer_baseline_replay}"
owner_transfer_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${owner_transfer_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/owner-transfer-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${owner_transfer_migration_replay}" != \
  *'已验证 0086_organization_owner_transfer（无需重复执行）'* ]] \
  || [[ "${owner_transfer_migration_replay}" == *'已执行 '* ]]; then
  echo '0086 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${owner_transfer_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${owner_transfer_migration_replay}"
owner_transfer_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${owner_transfer_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8585858585858585858585858585858585858585858585858585858585858585
)"
if [[ "${owner_transfer_after_exact_replay}" != \
  "${owner_transfer_after_migration_replay}" ]]; then
  echo '重复 0086 migration 改变 owner-transfer 业务快照。' >&2
  exit 1
fi
echo '0085→0086 旧组织、五字段 owner-transfer、exact replay 与 checksum 幂等：通过。'

echo '验证 0086→0087 升级后旧组织可签发并接受定向邀请。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${directed_invitation_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/directed-invitation-baseline-migrations \
      /tmp/directed-invitation-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-6]_*.sql' \) \
     -exec cp {} /tmp/directed-invitation-baseline-migrations/ \; && \
   test \"\$(find /tmp/directed-invitation-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 85 && \
   cp /workspace/backend/database/migrations/0087_*.sql \
     /tmp/directed-invitation-upgrade-only/ && \
   test \"\$(find /tmp/directed-invitation-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${directed_invitation_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/directed-invitation-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${directed_invitation_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 85
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM '0086_organization_owner_transfer'
        OR to_regclass(
          'app_private.organization_directed_account_invitation_request_claims'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_directed_account_invitation_request_tombstones'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_directed_account_invitation_audit_events'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_directed_invitation_claim_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_directed_invitation_tombstone_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_directed_invitation_audit_event_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.create_organization_directed_account_invitation_v1(uuid,uuid,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.accept_organization_directed_account_invitation_v1(uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.create_organization_directed_account_invitation_for_identity_v1(text,text,uuid,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.accept_organization_directed_account_invitation_for_identity_v1(text,text,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0086 directed-invitation upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
directed_invitation_creation_receipt="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${directed_invitation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0086_organization_directed_account_invitation_live.sql
)"
if [[ "${directed_invitation_creation_receipt}" != organization-creation:v1\|* ]] \
  || [[ "$(printf '%s\n' "${directed_invitation_creation_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0086 旧 writer 没有返回单行完整五字段 creation receipt。' >&2
  exit 1
fi
directed_invitation_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${directed_invitation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_directed_account_invitation_request_claims \
    --exclude-table-data=app_private.organization_directed_account_invitation_request_tombstones \
    --exclude-table-data=app_private.organization_directed_account_invitation_audit_events \
    --restrict-key=8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d
)"
docker exec \
  --env DATABASE_URL="${directed_invitation_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/directed-invitation-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
directed_invitation_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${directed_invitation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_directed_account_invitation_request_claims \
    --exclude-table-data=app_private.organization_directed_account_invitation_request_tombstones \
    --exclude-table-data=app_private.organization_directed_account_invitation_audit_events \
    --restrict-key=8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d
)"
if [[ "${directed_invitation_before_upgrade}" != \
  "${directed_invitation_after_upgrade}" ]]; then
  echo '0087 升级改变了旧组织、owner 或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${directed_invitation_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.organization_directed_account_invitation_request_claims)
            <> 0
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_request_tombstones)
              <> 0
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_audit_events)
              <> 0
      THEN
        RAISE EXCEPTION '0087 directed-invitation tables are not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
directed_invitation_first_write="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${directed_invitation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE directed_invitation_create_receipt (
        organization_invitation_contract_id text,
        invitation_id uuid,
        organization_workspace_id uuid,
        issued_at_utc timestamptz,
        expires_at_utc timestamptz
      );
      CREATE TEMP TABLE directed_invitation_accept_receipt (
        organization_invitation_contract_id text,
        invitation_id uuid,
        organization_workspace_id uuid,
        organization_membership_id uuid,
        accepted_at_utc timestamptz
      );
      CREATE TEMP TABLE directed_invitation_clock_bounds AS
      SELECT clock_timestamp() AS observed_before,
        NULL::timestamptz AS observed_after;
      CREATE TEMP TABLE directed_invitation_input AS
      SELECT organization_workspace_id
      FROM app_private.organization_creation_request_claims
      WHERE request_id =
        '00000000-0086-5000-0000-000000000601'::uuid;
      GRANT ALL ON directed_invitation_create_receipt,
        directed_invitation_accept_receipt TO tongxingzhe_runtime;
      GRANT SELECT ON directed_invitation_input TO tongxingzhe_runtime;
    " \
    --command="
      SET ROLE tongxingzhe_runtime;
      INSERT INTO directed_invitation_create_receipt
      SELECT *
      FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
        'https://synthetic-directed-invitation-upgrade.example/auth/v1',
        'owner',
        '00000000-0087-6000-0000-000000000601',
        (SELECT organization_workspace_id FROM directed_invitation_input),
        '00000000-0086-0000-0000-000000000602'
      );
      RESET ROLE;
      UPDATE directed_invitation_clock_bounds
      SET observed_after = clock_timestamp();
      SET ROLE tongxingzhe_runtime;
      INSERT INTO directed_invitation_accept_receipt
      SELECT *
      FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
        'https://synthetic-directed-invitation-upgrade.example/auth/v1',
        'target',
        '00000000-0087-6000-0000-000000000601'
      );
      RESET ROLE;
      TABLE directed_invitation_create_receipt;
      TABLE directed_invitation_accept_receipt;
      DO \$written\$
      DECLARE
        created directed_invitation_create_receipt%ROWTYPE;
        accepted directed_invitation_accept_receipt%ROWTYPE;
        bounds directed_invitation_clock_bounds%ROWTYPE;
        creation app_private.organization_creation_request_claims%ROWTYPE;
        invitation
          app_private.organization_directed_account_invitation_request_claims%ROWTYPE;
      BEGIN
        SELECT * INTO STRICT created FROM directed_invitation_create_receipt;
        SELECT * INTO STRICT accepted FROM directed_invitation_accept_receipt;
        SELECT * INTO STRICT bounds FROM directed_invitation_clock_bounds;
        SELECT * INTO STRICT creation
        FROM app_private.organization_creation_request_claims
        WHERE request_id =
          '00000000-0086-5000-0000-000000000601'::uuid;
        SELECT * INTO STRICT invitation
        FROM app_private.organization_directed_account_invitation_request_claims
        WHERE invitation_id = created.invitation_id;

        IF (SELECT count(*) FROM directed_invitation_create_receipt) <> 1
          OR (SELECT count(*) FROM directed_invitation_accept_receipt) <> 1
          OR created.organization_invitation_contract_id IS DISTINCT FROM
            'organization-directed-account-invitation:v1'
          OR created.invitation_id IS DISTINCT FROM
            '00000000-0087-6000-0000-000000000601'::uuid
          OR created.organization_workspace_id IS DISTINCT FROM
            creation.organization_workspace_id
          OR created.issued_at_utc IS NULL
          OR NOT isfinite(created.issued_at_utc)
          OR created.issued_at_utc < bounds.observed_before
          OR created.issued_at_utc > bounds.observed_after
          OR created.expires_at_utc IS DISTINCT FROM
            created.issued_at_utc + interval '168 hours'
          OR ROW(
            accepted.organization_invitation_contract_id,
            accepted.invitation_id,
            accepted.organization_workspace_id
          ) IS DISTINCT FROM ROW(
            created.organization_invitation_contract_id,
            created.invitation_id,
            created.organization_workspace_id
          )
          OR accepted.organization_membership_id IS NULL
          OR accepted.accepted_at_utc IS NULL
          OR NOT isfinite(accepted.accepted_at_utc)
          OR invitation.organization_workspace_id IS DISTINCT FROM
            created.organization_workspace_id
          OR invitation.inviter_app_user_id IS DISTINCT FROM
            '00000000-0086-0000-0000-000000000601'::uuid
          OR invitation.target_app_user_id IS DISTINCT FROM
            '00000000-0086-0000-0000-000000000602'::uuid
          OR invitation.issued_at_utc IS DISTINCT FROM created.issued_at_utc
          OR invitation.expires_at_utc IS DISTINCT FROM created.expires_at_utc
          OR invitation.accepted_at_utc IS DISTINCT FROM
            accepted.accepted_at_utc
          OR invitation.accepted_organization_membership_id IS DISTINCT FROM
            accepted.organization_membership_id
          OR (SELECT count(*)
              FROM app_private.organization_directed_account_invitation_request_claims)
            <> 1
          OR (SELECT count(*)
              FROM app_private.organization_directed_account_invitation_request_tombstones)
            <> 0
          OR (SELECT count(*)
              FROM app_private.organization_directed_account_invitation_audit_events)
            <> 2
          OR (SELECT count(*)
              FROM app_private.organization_directed_account_invitation_audit_events
              WHERE organization_invitation_contract_id =
                  created.organization_invitation_contract_id
                AND invitation_id = created.invitation_id
                AND organization_workspace_id =
                  created.organization_workspace_id
                AND event_kind = 'invitation_issued'
                AND organization_membership_id IS NULL
                AND occurred_at_utc = created.issued_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_directed_account_invitation_audit_events
              WHERE organization_invitation_contract_id =
                  accepted.organization_invitation_contract_id
                AND invitation_id = accepted.invitation_id
                AND organization_workspace_id =
                  accepted.organization_workspace_id
                AND event_kind = 'invitation_accepted'
                AND organization_membership_id =
                  accepted.organization_membership_id
                AND occurred_at_utc = accepted.accepted_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_memberships
              WHERE organization_membership_id =
                  accepted.organization_membership_id
                AND organization_workspace_id =
                  accepted.organization_workspace_id
                AND app_user_id =
                  '00000000-0086-0000-0000-000000000602'::uuid
                AND active_from_utc = accepted.accepted_at_utc
                AND inactive_from_utc IS NULL) <> 1
          OR (SELECT count(*) FROM app_data.organization_memberships) <> 2
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments AS assignment
              JOIN app_data.organization_memberships AS membership
                ON membership.organization_membership_id =
                  assignment.organization_membership_id
              WHERE assignment.organization_owner_assignment_id =
                  creation.organization_owner_assignment_id
                AND assignment.organization_membership_id =
                  creation.organization_membership_id
                AND assignment.active_from_utc = creation.created_at_utc
                AND assignment.inactive_from_utc IS NULL
                AND membership.organization_membership_id =
                  creation.organization_membership_id
                AND membership.organization_workspace_id =
                  created.organization_workspace_id
                AND membership.app_user_id = creation.actor_app_user_id
                AND membership.active_from_utc = creation.created_at_utc
                AND membership.inactive_from_utc IS NULL) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_creation_request_claims) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_creation_audit_events) <> 1
          OR (SELECT count(*) FROM app_data.projects) <> 0
          OR (SELECT count(*) FROM app_data.project_memberships) <> 0
          OR (SELECT count(*)
              FROM app_data.management_report_capability_grants) <> 0
          OR (SELECT count(*)
              FROM app_data.promotion_target_assignments) <> 0
        THEN
          RAISE EXCEPTION '0087 directed-invitation receipt drift';
        END IF;
      END
      \$written\$;
    "
)"
if [[ "$(printf '%s\n' "${directed_invitation_first_write}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 2 ]]; then
  echo '0087 runtime writers 没有各返回一行完整五字段 receipt。' >&2
  exit 1
fi
directed_invitation_create_receipt="$(
  printf '%s\n' "${directed_invitation_first_write}" | sed -n '1p'
)"
directed_invitation_accept_receipt="$(
  printf '%s\n' "${directed_invitation_first_write}" | sed -n '2p'
)"
directed_invitation_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${directed_invitation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d
)"
directed_invitation_replay="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${directed_invitation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE directed_invitation_replay_input AS
      SELECT organization_workspace_id
      FROM app_private.organization_creation_request_claims
      WHERE request_id =
        '00000000-0086-5000-0000-000000000601'::uuid;
      GRANT SELECT ON directed_invitation_replay_input TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
        'https://synthetic-directed-invitation-upgrade.example/auth/v1',
        'target',
        '00000000-0087-6000-0000-000000000601'
      );
      SELECT *
      FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
        'https://synthetic-directed-invitation-upgrade.example/auth/v1',
        'owner',
        '00000000-0087-6000-0000-000000000601',
        (SELECT organization_workspace_id
         FROM directed_invitation_replay_input),
        '00000000-0086-0000-0000-000000000602'
      );
      RESET ROLE;
    "
)"
if [[ "$(printf '%s\n' "${directed_invitation_replay}" | sed -n '1p')" != \
  "${directed_invitation_accept_receipt}" ]] \
  || [[ "$(printf '%s\n' "${directed_invitation_replay}" | sed -n '2p')" != \
    "${directed_invitation_create_receipt}" ]]; then
  echo '0087 accept/create 反序 exact replay 没有返回原五字段 receipts。' >&2
  exit 1
fi
directed_invitation_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${directed_invitation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d
)"
if [[ "${directed_invitation_after_first_write}" != \
  "${directed_invitation_after_exact_replay}" ]]; then
  echo '0087 反序 exact replay 改变了 invitation 或其他业务数据。' >&2
  exit 1
fi
directed_invitation_baseline_replay="$(
  docker exec \
    --env DATABASE_URL="${directed_invitation_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/directed-invitation-baseline-migrations \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
directed_invitation_baseline_verified_count="$(
  printf '%s\n' "${directed_invitation_baseline_replay}" \
    | awk '/^已验证 .*（无需重复执行）$/ { count++ } END { print count+0 }'
)"
if [[ "${directed_invitation_baseline_verified_count}" -ne 85 ]] \
  || [[ "${directed_invitation_baseline_replay}" == *'已执行 '* ]]; then
  echo '0001..0086 重复 migrations 没有全部命中 checksum skip。' >&2
  printf '%s\n' "${directed_invitation_baseline_replay}" >&2
  exit 1
fi
printf '%s\n' "${directed_invitation_baseline_replay}"
directed_invitation_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${directed_invitation_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/directed-invitation-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${directed_invitation_migration_replay}" != \
  *'已验证 0087_organization_directed_account_invitation（无需重复执行）'* ]] \
  || [[ "${directed_invitation_migration_replay}" == *'已执行 '* ]]; then
  echo '0087 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${directed_invitation_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${directed_invitation_migration_replay}"
directed_invitation_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${directed_invitation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d8d
)"
if [[ "${directed_invitation_after_exact_replay}" != \
  "${directed_invitation_after_migration_replay}" ]]; then
  echo '重复 0087 migration 改变 directed invitation 业务快照。' >&2
  exit 1
fi
echo '0086→0087 旧组织、五字段 create/accept、反序 exact replay 与 checksum 幂等：通过。'

echo '验证 0087→0088 保留原 0086 writer 已提交的 owner-transfer claim。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${owner_authorization_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/owner-authorization-baseline-migrations \
      /tmp/owner-authorization-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-7]_*.sql' \) \
     -exec cp {} /tmp/owner-authorization-baseline-migrations/ \; && \
   test \"\$(find /tmp/owner-authorization-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 86 && \
   cp /workspace/backend/database/migrations/0088_*.sql \
     /tmp/owner-authorization-upgrade-only/ && \
   test \"\$(find /tmp/owner-authorization-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${owner_authorization_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/owner-authorization-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
owner_authorization_function_before="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${owner_authorization_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      DO \$baseline\$
      DECLARE
        definition text;
      BEGIN
        SELECT pg_get_functiondef(
          'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure
        ) INTO STRICT definition;
        IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 86
          OR (SELECT max(version) FROM app_migrations.schema_migrations)
            IS DISTINCT FROM '0087_organization_directed_account_invitation'
          OR position('authorization_time' IN definition) > 0
          OR regexp_count(definition, '@>[[:space:]]*effective_time') <> 4
        THEN
          RAISE EXCEPTION '0087 owner authorization upgrade baseline drift';
        END IF;
      END
      \$baseline\$;
      SELECT jsonb_build_object(
        'oid', procedure_row.oid::text,
        'owner', pg_get_userbyid(procedure_row.proowner),
        'acl', procedure_row.proacl::text
      )
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid =
        'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure;
    "
)"
owner_authorization_legacy_receipt="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${owner_authorization_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0087_organization_owner_transfer_claim.sql
)"
if [[ "${owner_authorization_legacy_receipt}" != \
  organization-owner-transfer:v1\|* ]] \
  || [[ "$(printf '%s\n' "${owner_authorization_legacy_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0087 原 0086 writer 没有返回单行完整五字段 receipt。' >&2
  exit 1
fi
owner_authorization_workspace_id="$(
  printf '%s\n' "${owner_authorization_legacy_receipt}" | awk -F '|' '{ print $2 }'
)"
owner_authorization_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${owner_authorization_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d
)"
docker exec \
  --env DATABASE_URL="${owner_authorization_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/owner-authorization-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
owner_authorization_function_after="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${owner_authorization_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      DO \$upgrade\$
      DECLARE
        definition text;
      BEGIN
        SELECT pg_get_functiondef(
          'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure
        ) INTO STRICT definition;
        IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 87
          OR (SELECT max(version) FROM app_migrations.schema_migrations)
            IS DISTINCT FROM '0088_organization_owner_transfer_authorization_time'
          OR regexp_count(
            definition,
            'authorization_time[[:space:]]*:[=][[:space:]]*clock_timestamp[[:space:]]*[(][)]'
          ) <> 1
          OR regexp_count(definition, '@>[[:space:]]*authorization_time') <> 4
          OR regexp_count(definition, '@>[[:space:]]*effective_time') <> 0
        THEN
          RAISE EXCEPTION '0088 owner authorization upgrade drift';
        END IF;
      END
      \$upgrade\$;
      SELECT jsonb_build_object(
        'oid', procedure_row.oid::text,
        'owner', pg_get_userbyid(procedure_row.proowner),
        'acl', procedure_row.proacl::text
      )
      FROM pg_catalog.pg_proc AS procedure_row
      WHERE procedure_row.oid =
        'app_private.transfer_organization_owner_v1(uuid,uuid,uuid,uuid)'::regprocedure;
    "
)"
if [[ -z "${owner_authorization_function_before}" ]] \
  || [[ "${owner_authorization_function_before}" != \
    "${owner_authorization_function_after}" ]]; then
  echo '0088 没有保留 private owner-transfer writer 的 OID、owner 或 ACL。' >&2
  exit 1
fi
owner_authorization_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${owner_authorization_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d
)"
if [[ "${owner_authorization_before_upgrade}" != \
  "${owner_authorization_after_upgrade}" ]]; then
  echo '0088 升级改变旧 owner-transfer claim 或其他业务数据。' >&2
  exit 1
fi
owner_authorization_replayed_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${owner_authorization_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.transfer_organization_owner_for_identity_v1(
        'https://synthetic-owner-authorization-upgrade.example/auth/v1',
        'original-actor',
        '00000000-0087-6000-0000-000000000702',
        '${owner_authorization_workspace_id}',
        '00000000-0087-3000-0000-000000000702'
      );
      RESET ROLE;
    "
)"
if [[ "${owner_authorization_legacy_receipt}" != \
  "${owner_authorization_replayed_receipt}" ]]; then
  echo '0088 升级后旧 owner-transfer request 的 exact replay 改变原 receipt。' >&2
  exit 1
fi
owner_authorization_after_replay="$(
  docker exec "${container_name}" pg_dump \
    "${owner_authorization_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d
)"
if [[ "${owner_authorization_after_upgrade}" != \
  "${owner_authorization_after_replay}" ]]; then
  echo '0088 exact replay 改变 owner、membership、claim、audit 或其他业务行。' >&2
  exit 1
fi
owner_authorization_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL="${owner_authorization_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/owner-authorization-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${owner_authorization_upgrade_replay}" != \
  *'已验证 0088_organization_owner_transfer_authorization_time（无需重复执行）'* ]] \
  || [[ "${owner_authorization_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0088 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${owner_authorization_upgrade_replay}" >&2
  exit 1
fi
owner_authorization_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${owner_authorization_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d
)"
if [[ "${owner_authorization_after_replay}" != \
  "${owner_authorization_after_migration_replay}" ]]; then
  echo '重复 0088 migration 改变 owner-transfer 业务快照。' >&2
  exit 1
fi
echo '0087→0088 旧 claim、函数身份、完整 receipt、exact replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0088→0089 旧 projectless organization 可由新 directory reader 读取。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${organization_directory_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/organization-directory-upgrade-baseline-migrations \
      /tmp/organization-directory-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-7][0-9]_*.sql' \
        -o -name '008[0-8]_*.sql' \) \
     -exec cp {} /tmp/organization-directory-upgrade-baseline-migrations/ \; && \
   test \"\$(find /tmp/organization-directory-upgrade-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 87 && \
   cp /workspace/backend/database/migrations/0089_*.sql \
     /tmp/organization-directory-upgrade-only/ && \
   test \"\$(find /tmp/organization-directory-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${organization_directory_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/organization-directory-upgrade-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
organization_directory_upgrade_legacy_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${organization_directory_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0088_organization_directory_live.sql
)"
if [[ "${organization_directory_upgrade_legacy_receipt}" != \
  organization-creation:v1\|* ]] \
  || [[ "$(printf '%s\n' "${organization_directory_upgrade_legacy_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0088 旧 writer 没有返回单行完整五字段 creation receipt。' >&2
  exit 1
fi
organization_directory_upgrade_workspace_id="$(
  printf '%s\n' "${organization_directory_upgrade_legacy_receipt}" \
    | awk -F '|' '{ print $2 }'
)"
organization_directory_upgrade_before="$(
  docker exec "${container_name}" pg_dump \
    "${organization_directory_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
docker exec \
  --env DATABASE_URL="${organization_directory_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/organization-directory-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
organization_directory_upgrade_after_migration="$(
  docker exec "${container_name}" pg_dump \
    "${organization_directory_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
if [[ "${organization_directory_upgrade_before}" != \
  "${organization_directory_upgrade_after_migration}" ]]; then
  echo '0089 升级改变了 0088 已有 organization 或其他业务数据。' >&2
  exit 1
fi
organization_directory_upgrade_result="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${organization_directory_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.list_organizations_for_identity_v1(
        'https://synthetic-organization-directory-upgrade.example/auth/v1',
        'owner'
      );
      RESET ROLE;
    "
)"
if [[ "${organization_directory_upgrade_result}" != \
  "${organization_directory_upgrade_workspace_id}|0088 Directory upgrade organization" ]] \
  || [[ "$(printf '%s\n' "${organization_directory_upgrade_result}" \
    | awk -F '|' 'NF == 2 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0089 directory 没有返回旧 organization 的单行两字段结果。' >&2
  exit 1
fi
organization_directory_upgrade_after_reader="$(
  docker exec "${container_name}" pg_dump \
    "${organization_directory_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
if [[ "${organization_directory_upgrade_after_migration}" != \
  "${organization_directory_upgrade_after_reader}" ]]; then
  echo '0089 directory read 改变了 organization、membership、owner 或其他业务数据。' >&2
  exit 1
fi
organization_directory_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL="${organization_directory_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/organization-directory-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${organization_directory_upgrade_replay}" != \
  *'已验证 0089_organization_directory（无需重复执行）'* ]] \
  || [[ "${organization_directory_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0089 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${organization_directory_upgrade_replay}" >&2
  exit 1
fi
printf '%s\n' "${organization_directory_upgrade_replay}"
organization_directory_upgrade_after_replay="$(
  docker exec "${container_name}" pg_dump \
    "${organization_directory_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
if [[ "${organization_directory_upgrade_after_reader}" != \
  "${organization_directory_upgrade_after_replay}" ]]; then
  echo '重复 0089 migration 改变 organization directory 业务快照。' >&2
  exit 1
fi
echo '0088→0089 旧 organization、两字段 directory、checksum 幂等与业务数据不变：通过。'

echo '验证 0089→0090 旧邀请普通成员可由新 self-leave writer 退出。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${membership_leave_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/membership-leave-upgrade-baseline-migrations \
      /tmp/membership-leave-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \) \
     -exec cp {} /tmp/membership-leave-upgrade-baseline-migrations/ \; && \
   test \"\$(find /tmp/membership-leave-upgrade-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 88 && \
   cp /workspace/backend/database/migrations/0090_*.sql \
     /tmp/membership-leave-upgrade-only/ && \
   test \"\$(find /tmp/membership-leave-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${membership_leave_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/membership-leave-upgrade-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
membership_leave_upgrade_accept_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${membership_leave_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0089_organization_membership_self_leave_live.sql
)"
if [[ "${membership_leave_upgrade_accept_receipt}" != \
  organization-directed-account-invitation:v1\|00000000-0089-6000-0000-000000000901\|* ]] \
  || [[ "$(printf '%s\n' "${membership_leave_upgrade_accept_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0089 旧 invitation accept writer 没有返回单行完整五字段 receipt。' >&2
  exit 1
fi
membership_leave_upgrade_workspace_id="$(
  printf '%s\n' "${membership_leave_upgrade_accept_receipt}" \
    | awk -F '|' '{ print $3 }'
)"
membership_leave_upgrade_membership_id="$(
  printf '%s\n' "${membership_leave_upgrade_accept_receipt}" \
    | awk -F '|' '{ print $4 }'
)"
membership_leave_upgrade_before="$(
  docker exec "${container_name}" pg_dump \
    "${membership_leave_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_membership_self_leave_request_claims \
    --exclude-table-data=app_private.organization_membership_self_leave_request_tombstones \
    --exclude-table-data=app_private.organization_membership_self_leave_audit_events \
    --restrict-key=3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c
)"
docker exec \
  --env DATABASE_URL="${membership_leave_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/membership-leave-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
membership_leave_upgrade_after_migration="$(
  docker exec "${container_name}" pg_dump \
    "${membership_leave_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_membership_self_leave_request_claims \
    --exclude-table-data=app_private.organization_membership_self_leave_request_tombstones \
    --exclude-table-data=app_private.organization_membership_self_leave_audit_events \
    --restrict-key=3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c
)"
if [[ "${membership_leave_upgrade_before}" != \
  "${membership_leave_upgrade_after_migration}" ]]; then
  echo '0090 升级改变了 0089 已有 organization、invitation 或 membership。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${membership_leave_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --quiet \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.organization_membership_self_leave_request_claims)
          <> 0
        OR (SELECT count(*)
            FROM app_private.organization_membership_self_leave_request_tombstones)
          <> 0
        OR (SELECT count(*)
            FROM app_private.organization_membership_self_leave_audit_events)
          <> 0
      THEN
        RAISE EXCEPTION '0090 self-leave tables are not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
membership_leave_upgrade_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${membership_leave_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.leave_organization_membership_for_identity_v1(
        'https://synthetic-membership-leave-upgrade.example/auth/v1',
        'target',
        '00000000-0089-7000-0000-000000000901',
        '${membership_leave_upgrade_workspace_id}'
      );
      RESET ROLE;
    "
)"
if [[ "${membership_leave_upgrade_receipt}" != \
  "organization-membership-self-leave:v1|${membership_leave_upgrade_workspace_id}|${membership_leave_upgrade_membership_id}|"* ]] \
  || [[ "$(printf '%s\n' "${membership_leave_upgrade_receipt}" \
    | awk -F '|' 'NF == 4 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0090 self-leave bridge 没有返回旧 membership 的单行四字段 receipt。' >&2
  exit 1
fi
membership_leave_upgrade_effective_at_utc="$(
  printf '%s\n' "${membership_leave_upgrade_receipt}" \
    | awk -F '|' '{ print $4 }'
)"
docker exec "${container_name}" psql \
  -U postgres \
  -d "${membership_leave_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --quiet \
  --command="
    DO \$left\$
    DECLARE
      leave_claim
        app_private.organization_membership_self_leave_request_claims%ROWTYPE;
      invitation_claim
        app_private.organization_directed_account_invitation_request_claims%ROWTYPE;
      creation_claim app_private.organization_creation_request_claims%ROWTYPE;
    BEGIN
      SELECT * INTO STRICT leave_claim
      FROM app_private.organization_membership_self_leave_request_claims
      WHERE request_id = '00000000-0089-7000-0000-000000000901'::uuid;
      SELECT * INTO STRICT invitation_claim
      FROM app_private.organization_directed_account_invitation_request_claims
      WHERE invitation_id = '00000000-0089-6000-0000-000000000901'::uuid;
      SELECT * INTO STRICT creation_claim
      FROM app_private.organization_creation_request_claims
      WHERE request_id = '00000000-0089-5000-0000-000000000901'::uuid;

      IF leave_claim.actor_app_user_id IS DISTINCT FROM
          '00000000-0089-0000-0000-000000000902'::uuid
        OR leave_claim.organization_workspace_id IS DISTINCT FROM
          '${membership_leave_upgrade_workspace_id}'::uuid
        OR leave_claim.organization_membership_id IS DISTINCT FROM
          '${membership_leave_upgrade_membership_id}'::uuid
        OR leave_claim.effective_at_utc IS DISTINCT FROM
          '${membership_leave_upgrade_effective_at_utc}'::timestamptz
        OR NOT EXISTS (
          SELECT 1
          FROM app_data.organization_memberships AS membership
          WHERE membership.organization_membership_id =
              leave_claim.organization_membership_id
            AND membership.organization_workspace_id =
              leave_claim.organization_workspace_id
            AND membership.app_user_id = leave_claim.actor_app_user_id
            AND membership.active_from_utc = invitation_claim.accepted_at_utc
            AND membership.inactive_from_utc = leave_claim.effective_at_utc
        )
        OR (SELECT count(*)
            FROM app_private.organization_membership_self_leave_request_claims)
          <> 1
        OR (SELECT count(*)
            FROM app_private.organization_membership_self_leave_request_tombstones)
          <> 0
        OR (SELECT count(*)
            FROM app_private.organization_membership_self_leave_audit_events)
          <> 1
        OR (SELECT count(*)
            FROM app_private.organization_membership_self_leave_audit_events
            WHERE membership_self_leave_contract_id =
                'organization-membership-self-leave:v1'
              AND request_id = leave_claim.request_id
              AND organization_workspace_id =
                leave_claim.organization_workspace_id
              AND organization_membership_id =
                leave_claim.organization_membership_id
              AND effective_at_utc = leave_claim.effective_at_utc) <> 1
        OR invitation_claim.inviter_app_user_id IS DISTINCT FROM
          '00000000-0089-0000-0000-000000000901'::uuid
        OR invitation_claim.target_app_user_id IS DISTINCT FROM
          '00000000-0089-0000-0000-000000000902'::uuid
        OR invitation_claim.organization_workspace_id IS DISTINCT FROM
          leave_claim.organization_workspace_id
        OR invitation_claim.accepted_organization_membership_id IS DISTINCT FROM
          leave_claim.organization_membership_id
        OR invitation_claim.accepted_at_utc IS NULL
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_request_claims)
          <> 1
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_request_tombstones)
          <> 0
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_audit_events)
          <> 2
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_audit_events
            WHERE invitation_id = invitation_claim.invitation_id
              AND event_kind = 'invitation_issued'
              AND organization_membership_id IS NULL
              AND occurred_at_utc = invitation_claim.issued_at_utc) <> 1
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_audit_events
            WHERE invitation_id = invitation_claim.invitation_id
              AND event_kind = 'invitation_accepted'
              AND organization_membership_id =
                invitation_claim.accepted_organization_membership_id
              AND occurred_at_utc = invitation_claim.accepted_at_utc) <> 1
        OR (SELECT count(*)
            FROM app_data.organization_memberships
            WHERE organization_workspace_id =
              leave_claim.organization_workspace_id) <> 2
        OR NOT EXISTS (
          SELECT 1
          FROM app_data.organization_memberships AS owner_membership
          WHERE owner_membership.organization_membership_id =
              creation_claim.organization_membership_id
            AND owner_membership.organization_workspace_id =
              leave_claim.organization_workspace_id
            AND owner_membership.app_user_id =
              '00000000-0089-0000-0000-000000000901'::uuid
            AND owner_membership.active_from_utc = creation_claim.created_at_utc
            AND owner_membership.inactive_from_utc IS NULL
        )
        OR NOT EXISTS (
          SELECT 1
          FROM app_data.organization_owner_assignments AS owner_assignment
          WHERE owner_assignment.organization_owner_assignment_id =
              creation_claim.organization_owner_assignment_id
            AND owner_assignment.organization_membership_id =
              creation_claim.organization_membership_id
            AND owner_assignment.active_from_utc = creation_claim.created_at_utc
            AND owner_assignment.inactive_from_utc IS NULL
        )
        OR (SELECT count(*)
            FROM app_data.organization_owner_assignments AS owner_assignment
            JOIN app_data.organization_memberships AS owner_membership
              ON owner_membership.organization_membership_id =
                owner_assignment.organization_membership_id
            WHERE owner_membership.organization_workspace_id =
              leave_claim.organization_workspace_id) <> 1
        OR EXISTS (
          SELECT 1
          FROM app_data.organization_owner_assignments AS owner_assignment
          WHERE owner_assignment.organization_membership_id =
            leave_claim.organization_membership_id
        )
        OR EXISTS (
          SELECT 1
          FROM app_data.project_memberships AS project_membership
          WHERE project_membership.organization_membership_id =
            leave_claim.organization_membership_id
        )
        OR EXISTS (
          SELECT 1
          FROM app_data.management_report_capability_grants AS capability
          JOIN app_data.project_memberships AS project_membership
            ON project_membership.project_membership_id =
              capability.project_membership_id
          WHERE project_membership.organization_membership_id =
            leave_claim.organization_membership_id
        )
        OR EXISTS (
          SELECT 1
          FROM app_data.promotion_target_assignments AS assignment
          JOIN app_data.promotion_targets AS target
            ON target.promotion_target_id = assignment.promotion_target_id
          WHERE assignment.app_user_id = leave_claim.actor_app_user_id
            AND target.workspace_id = leave_claim.organization_workspace_id
        )
      THEN
        RAISE EXCEPTION '0089→0090 membership self-leave drift';
      END IF;
    END
    \$left\$;
  " \
  >/dev/null
membership_leave_upgrade_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${membership_leave_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c
)"
membership_leave_upgrade_replayed_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${membership_leave_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.leave_organization_membership_for_identity_v1(
        'https://synthetic-membership-leave-upgrade.example/auth/v1',
        'target',
        '00000000-0089-7000-0000-000000000901',
        '${membership_leave_upgrade_workspace_id}'
      );
      RESET ROLE;
    "
)"
if [[ "${membership_leave_upgrade_receipt}" != \
  "${membership_leave_upgrade_replayed_receipt}" ]]; then
  echo '0090 self-leave exact replay 改变原四字段 receipt。' >&2
  exit 1
fi
membership_leave_upgrade_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${membership_leave_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c
)"
if [[ "${membership_leave_upgrade_after_first_write}" != \
  "${membership_leave_upgrade_after_exact_replay}" ]]; then
  echo '0090 self-leave exact replay 改变 membership、claim 或 audit。' >&2
  exit 1
fi
membership_leave_upgrade_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${membership_leave_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/membership-leave-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${membership_leave_upgrade_migration_replay}" != \
  *'已验证 0090_organization_membership_self_leave（无需重复执行）'* ]] \
  || [[ "${membership_leave_upgrade_migration_replay}" == *'已执行 '* ]]; then
  echo '0090 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${membership_leave_upgrade_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${membership_leave_upgrade_migration_replay}"
membership_leave_upgrade_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${membership_leave_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c
)"
if [[ "${membership_leave_upgrade_after_exact_replay}" != \
  "${membership_leave_upgrade_after_migration_replay}" ]]; then
  echo '重复 0090 migration 改变 membership self-leave 业务快照。' >&2
  exit 1
fi
echo '0089→0090 旧邀请成员、四字段 self-leave、exact replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0090→0091 旧 directed invitation 可由新 preview reader 读取。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${invitation_preview_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/invitation-preview-upgrade-baseline-migrations \
      /tmp/invitation-preview-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \
        -o -name '0090_*.sql' \) \
     -exec cp {} /tmp/invitation-preview-upgrade-baseline-migrations/ \; && \
   test \"\$(find /tmp/invitation-preview-upgrade-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 89 && \
   cp /workspace/backend/database/migrations/0091_*.sql \
     /tmp/invitation-preview-upgrade-only/ && \
   test \"\$(find /tmp/invitation-preview-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${invitation_preview_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/invitation-preview-upgrade-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
invitation_preview_upgrade_legacy_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${invitation_preview_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0090_organization_directed_account_invitation_live.sql
)"
if [[ "${invitation_preview_upgrade_legacy_receipt}" != \
  organization-directed-account-invitation:v1\|00000000-0090-6000-0000-000000000801\|00000000-0090-2000-0000-000000000801\|* ]] \
  || [[ "$(printf '%s\n' "${invitation_preview_upgrade_legacy_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0090 旧 writer 没有返回单行完整五字段 invitation receipt。' >&2
  exit 1
fi
invitation_preview_upgrade_claim_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${invitation_preview_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SELECT
        'organization-directed-account-invitation:v1',
        invitation_id,
        organization_workspace_id,
        issued_at_utc,
        expires_at_utc
      FROM app_private.organization_directed_account_invitation_request_claims;
    "
)"
if [[ "${invitation_preview_upgrade_legacy_receipt}" != \
  "${invitation_preview_upgrade_claim_receipt}" ]]; then
  echo '0090 旧 writer 的 receipt 与 invitation claim 不一致。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${invitation_preview_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$legacy\$
    DECLARE
      claim
        app_private.organization_directed_account_invitation_request_claims%ROWTYPE;
    BEGIN
      SELECT * INTO STRICT claim
      FROM app_private.organization_directed_account_invitation_request_claims
      WHERE invitation_id =
        '00000000-0090-6000-0000-000000000801'::uuid;

      IF claim.organization_workspace_id IS DISTINCT FROM
          '00000000-0090-2000-0000-000000000801'::uuid
        OR claim.inviter_app_user_id IS DISTINCT FROM
          '00000000-0090-0000-0000-000000000801'::uuid
        OR claim.target_app_user_id IS DISTINCT FROM
          '00000000-0090-0000-0000-000000000802'::uuid
        OR claim.expires_at_utc IS DISTINCT FROM
          claim.issued_at_utc + interval '168 hours'
        OR claim.accepted_at_utc IS NOT NULL
        OR claim.accepted_organization_membership_id IS NOT NULL
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_request_claims) <> 1
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_request_tombstones) <> 0
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_audit_events) <> 1
        OR (SELECT count(*)
            FROM app_private.organization_directed_account_invitation_audit_events
            WHERE organization_invitation_contract_id =
                'organization-directed-account-invitation:v1'
              AND invitation_id = claim.invitation_id
              AND organization_workspace_id = claim.organization_workspace_id
              AND event_kind = 'invitation_issued'
              AND organization_membership_id IS NULL
              AND occurred_at_utc = claim.issued_at_utc) <> 1
        OR EXISTS (
          SELECT 1
          FROM app_data.organization_memberships
          WHERE organization_workspace_id = claim.organization_workspace_id
            AND app_user_id = claim.target_app_user_id
        )
      THEN
        RAISE EXCEPTION '0090 legacy invitation drift';
      END IF;
    END
    \$legacy\$;
  " \
  >/dev/null
invitation_preview_upgrade_before="$(
  docker exec "${container_name}" pg_dump \
    "${invitation_preview_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e
)"
docker exec \
  --env DATABASE_URL="${invitation_preview_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/invitation-preview-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
invitation_preview_upgrade_after_migration="$(
  docker exec "${container_name}" pg_dump \
    "${invitation_preview_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e
)"
if [[ "${invitation_preview_upgrade_before}" != \
  "${invitation_preview_upgrade_after_migration}" ]]; then
  echo '0091 升级改变了 0090 已有 invitation 或其他业务数据。' >&2
  exit 1
fi
invitation_preview_upgrade_expires_at="$(
  printf '%s\n' "${invitation_preview_upgrade_legacy_receipt}" \
    | awk -F '|' '{ print $5 }'
)"
invitation_preview_upgrade_result="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${invitation_preview_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.preview_organization_directed_invitation_for_identity_v1(
        'https://synthetic-invitation-preview-upgrade.example/auth/v1',
        'target',
        '00000000-0090-6000-0000-000000000801'
      );
      RESET ROLE;
    "
)"
if [[ "${invitation_preview_upgrade_result}" != \
  "organization-directed-account-invitation-preview:v1|00000000-0090-6000-0000-000000000801| 0090 Original invitation organization |${invitation_preview_upgrade_expires_at}" ]] \
  || [[ "$(printf '%s\n' "${invitation_preview_upgrade_result}" \
    | awk -F '|' 'NF == 4 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0091 preview 没有返回与旧 invitation 一致的单行四字段结果。' >&2
  exit 1
fi
invitation_preview_upgrade_after_preview="$(
  docker exec "${container_name}" pg_dump \
    "${invitation_preview_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e
)"
if [[ "${invitation_preview_upgrade_after_migration}" != \
  "${invitation_preview_upgrade_after_preview}" ]]; then
  echo '0091 preview 改变了 claim、tombstone、audit、membership 或其他业务数据。' >&2
  exit 1
fi
invitation_preview_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL="${invitation_preview_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/invitation-preview-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${invitation_preview_upgrade_replay}" != \
  *'已验证 0091_organization_directed_account_invitation_preview（无需重复执行）'* ]] \
  || [[ "${invitation_preview_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0091 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${invitation_preview_upgrade_replay}" >&2
  exit 1
fi
printf '%s\n' "${invitation_preview_upgrade_replay}"
invitation_preview_upgrade_after_replay="$(
  docker exec "${container_name}" pg_dump \
    "${invitation_preview_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e
)"
if [[ "${invitation_preview_upgrade_after_preview}" != \
  "${invitation_preview_upgrade_after_replay}" ]]; then
  echo '重复 0091 migration 改变 invitation preview 业务快照。' >&2
  exit 1
fi
echo '0090→0091 旧 invitation、四字段 preview、checksum 幂等与业务数据不变：通过。'

echo '验证 0091→0092 升级后旧组织可创建并预览分享链接。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${shareable_link_creation_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/shareable-link-creation-baseline-migrations \
      /tmp/shareable-link-creation-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \
        -o -name '009[0-1]_*.sql' \) \
     -exec cp {} /tmp/shareable-link-creation-baseline-migrations/ \; && \
   test \"\$(find /tmp/shareable-link-creation-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 90 && \
   cp /workspace/backend/database/migrations/0092_*.sql \
     /tmp/shareable-link-creation-upgrade-only/ && \
   test \"\$(find /tmp/shareable-link-creation-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${shareable_link_creation_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/shareable-link-creation-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${shareable_link_creation_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 90
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM
            '0091_organization_directed_account_invitation_preview'
        OR to_regclass(
          'app_private.organization_shareable_join_link_request_claims'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_shareable_join_link_request_tombstones'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_shareable_join_link_audit_events'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_shareable_join_link_claim_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_shareable_join_link_tombstone_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_shareable_join_link_audit_event_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.create_organization_shareable_join_link_v1(uuid,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.create_organization_shareable_join_link_for_identity_v1(text,text,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.preview_organization_shareable_join_link_for_identity_v1(text,text,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0091 shareable-link creation upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
shareable_link_creation_receipt="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${shareable_link_creation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0091_organization_shareable_join_link_creation.sql
)"
if [[ "${shareable_link_creation_receipt}" != organization-creation:v1\|* ]] \
  || [[ "$(printf '%s\n' "${shareable_link_creation_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0091 旧 writer 没有返回单行完整五字段 creation receipt。' >&2
  exit 1
fi
shareable_link_creation_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_shareable_join_link_request_claims \
    --exclude-table-data=app_private.organization_shareable_join_link_request_tombstones \
    --exclude-table-data=app_private.organization_shareable_join_link_audit_events \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
docker exec \
  --env DATABASE_URL="${shareable_link_creation_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/shareable-link-creation-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
shareable_link_creation_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_shareable_join_link_request_claims \
    --exclude-table-data=app_private.organization_shareable_join_link_request_tombstones \
    --exclude-table-data=app_private.organization_shareable_join_link_audit_events \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
if [[ "${shareable_link_creation_before_upgrade}" != \
  "${shareable_link_creation_after_upgrade}" ]]; then
  echo '0092 升级改变了旧组织、owner 或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${shareable_link_creation_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.organization_shareable_join_link_request_claims)
            <> 0
        OR (SELECT count(*)
            FROM app_private.organization_shareable_join_link_request_tombstones)
              <> 0
        OR (SELECT count(*)
            FROM app_private.organization_shareable_join_link_audit_events)
              <> 0
      THEN
        RAISE EXCEPTION '0092 link tables are not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
shareable_link_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${shareable_link_creation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE shareable_link_receipt (
        organization_shareable_join_link_contract_id text,
        link_id uuid,
        organization_workspace_id uuid,
        issued_at_utc timestamptz,
        expires_at_utc timestamptz
      );
      CREATE TEMP TABLE shareable_link_clock_bounds AS
      SELECT clock_timestamp() AS observed_before,
        NULL::timestamptz AS observed_after;
      CREATE TEMP TABLE shareable_link_creation_input AS
      SELECT organization_workspace_id
      FROM app_private.organization_creation_request_claims
      WHERE request_id = '00000000-0091-5000-0000-000000000901'::uuid;
      GRANT ALL ON shareable_link_receipt TO tongxingzhe_runtime;
      GRANT SELECT ON shareable_link_creation_input TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      INSERT INTO shareable_link_receipt
      SELECT *
      FROM app_data.create_organization_shareable_join_link_for_identity_v1(
        'https://synthetic-shareable-link-upgrade.example/auth/v1',
        'owner',
        '00000000-0092-6000-0000-000000000901',
        (SELECT organization_workspace_id
         FROM shareable_link_creation_input)
      );
      RESET ROLE;
      UPDATE shareable_link_clock_bounds
      SET observed_after = clock_timestamp();
      TABLE shareable_link_receipt;
      DO \$created\$
      DECLARE
        receipt shareable_link_receipt%ROWTYPE;
        bounds shareable_link_clock_bounds%ROWTYPE;
        creation app_private.organization_creation_request_claims%ROWTYPE;
      BEGIN
        SELECT * INTO STRICT receipt FROM shareable_link_receipt;
        SELECT * INTO STRICT bounds FROM shareable_link_clock_bounds;
        SELECT * INTO STRICT creation
        FROM app_private.organization_creation_request_claims
        WHERE request_id =
          '00000000-0091-5000-0000-000000000901'::uuid;

        IF (SELECT count(*) FROM shareable_link_receipt) <> 1
          OR receipt.organization_shareable_join_link_contract_id
            IS DISTINCT FROM 'organization-shareable-join-link:v1'
          OR receipt.link_id IS DISTINCT FROM
            '00000000-0092-6000-0000-000000000901'::uuid
          OR receipt.organization_workspace_id IS DISTINCT FROM
            creation.organization_workspace_id
          OR receipt.issued_at_utc IS NULL
          OR NOT isfinite(receipt.issued_at_utc)
          OR receipt.issued_at_utc < bounds.observed_before
          OR receipt.issued_at_utc > bounds.observed_after
          OR receipt.expires_at_utc IS DISTINCT FROM
            receipt.issued_at_utc + interval '168 hours'
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_link_request_claims
              WHERE link_id = receipt.link_id
                AND organization_workspace_id =
                  receipt.organization_workspace_id
                AND creator_app_user_id =
                  '00000000-0091-0000-0000-000000000901'::uuid
                AND issued_at_utc = receipt.issued_at_utc
                AND expires_at_utc = receipt.expires_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_link_audit_events
              WHERE organization_shareable_join_link_audit_event_id
                  IS NOT NULL
                AND organization_shareable_join_link_contract_id =
                  receipt.organization_shareable_join_link_contract_id
                AND link_id = receipt.link_id
                AND organization_workspace_id =
                  receipt.organization_workspace_id
                AND event_kind = 'link_created'
                AND issued_at_utc = receipt.issued_at_utc
                AND expires_at_utc = receipt.expires_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_link_request_claims)
            <> 1
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_link_request_tombstones)
            <> 0
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_link_audit_events)
            <> 1
          OR (SELECT count(*) FROM app_data.organization_memberships) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments) <> 1
          OR (SELECT count(*) FROM app_data.projects) <> 0
          OR (SELECT count(*) FROM app_data.project_memberships) <> 0
          OR (SELECT count(*)
              FROM app_data.management_report_capability_grants) <> 0
          OR (SELECT count(*)
              FROM app_data.promotion_target_assignments) <> 0
        THEN
          RAISE EXCEPTION '0092 shareable-link receipt drift';
        END IF;
      END
      \$created\$;
    "
)"
if [[ "${shareable_link_receipt}" != \
  organization-shareable-join-link:v1\|00000000-0092-6000-0000-000000000901\|* ]] \
  || [[ "$(printf '%s\n' "${shareable_link_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0092 runtime writer 没有返回单行完整五字段 link receipt。' >&2
  exit 1
fi
shareable_link_legacy_after_create="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_shareable_join_link_request_claims \
    --exclude-table-data=app_private.organization_shareable_join_link_request_tombstones \
    --exclude-table-data=app_private.organization_shareable_join_link_audit_events \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
if [[ "${shareable_link_creation_after_upgrade}" != \
  "${shareable_link_legacy_after_create}" ]]; then
  echo '0092 link create 改变了旧组织、owner 或其他既有业务数据。' >&2
  exit 1
fi
shareable_link_expires_at="$(
  printf '%s\n' "${shareable_link_receipt}" | awk -F '|' '{ print $5 }'
)"
shareable_link_after_create="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
shareable_link_preview="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${shareable_link_creation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.preview_organization_shareable_join_link_for_identity_v1(
        'https://synthetic-shareable-link-upgrade.example/auth/v1',
        'owner',
        '00000000-0092-6000-0000-000000000901'
      );
      RESET ROLE;
    "
)"
if [[ "${shareable_link_preview}" != \
  "organization-shareable-join-link-preview:v1|00000000-0092-6000-0000-000000000901|0091 Shareable link upgrade organization|${shareable_link_expires_at}" ]] \
  || [[ "$(printf '%s\n' "${shareable_link_preview}" \
    | awk -F '|' 'NF == 4 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0092 preview 没有返回原组织名称与 link expiry 的单行四字段结果。' >&2
  exit 1
fi
shareable_link_after_preview="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
if [[ "${shareable_link_after_create}" != \
  "${shareable_link_after_preview}" ]]; then
  echo '0092 preview 改变了分享链接或其他业务数据。' >&2
  exit 1
fi
shareable_link_replay="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${shareable_link_creation_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET TIME ZONE 'UTC';
      CREATE TEMP TABLE shareable_link_replay_input AS
      SELECT organization_workspace_id
      FROM app_private.organization_creation_request_claims
      WHERE request_id =
        '00000000-0091-5000-0000-000000000901'::uuid;
      GRANT SELECT ON shareable_link_replay_input TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.create_organization_shareable_join_link_for_identity_v1(
        'https://synthetic-shareable-link-upgrade.example/auth/v1',
        'owner',
        '00000000-0092-6000-0000-000000000901',
        (SELECT organization_workspace_id
         FROM shareable_link_replay_input)
      );
      RESET ROLE;
    "
)"
if [[ "${shareable_link_receipt}" != "${shareable_link_replay}" ]]; then
  echo '0092 exact replay 没有返回原五字段 link receipt。' >&2
  exit 1
fi
shareable_link_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
if [[ "${shareable_link_after_preview}" != \
  "${shareable_link_after_exact_replay}" ]]; then
  echo '0092 exact replay 改变了分享链接或其他业务数据。' >&2
  exit 1
fi
shareable_link_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${shareable_link_creation_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/shareable-link-creation-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${shareable_link_migration_replay}" != \
  *'已验证 0092_organization_shareable_join_link（无需重复执行）'* ]] \
  || [[ "${shareable_link_migration_replay}" == *'已执行 '* ]]; then
  echo '0092 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${shareable_link_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${shareable_link_migration_replay}"
shareable_link_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${shareable_link_creation_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c7c
)"
if [[ "${shareable_link_after_exact_replay}" != \
  "${shareable_link_after_migration_replay}" ]]; then
  echo '重复 0092 migration 改变分享链接业务快照。' >&2
  exit 1
fi
echo '0091→0092 旧组织、五字段 create、四字段 preview、exact replay 与 checksum 幂等：通过。'

echo '验证 0092→0093 保留旧 link，并可通过新 submit writer 提交申请。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${link_submit_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/link-submit-upgrade-baseline-migrations \
      /tmp/link-submit-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \
        -o -name '009[0-2]_*.sql' \) \
     -exec cp {} /tmp/link-submit-upgrade-baseline-migrations/ \; && \
   test \"\$(find /tmp/link-submit-upgrade-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 91 && \
   cp /workspace/backend/database/migrations/0093_*.sql \
     /tmp/link-submit-upgrade-only/ && \
   test \"\$(find /tmp/link-submit-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${link_submit_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/link-submit-upgrade-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
link_submit_upgrade_link_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0092_organization_shareable_join_link_live.sql
)"
if [[ "${link_submit_upgrade_link_receipt}" != \
  organization-shareable-join-link:v1\|00000000-0092-6000-0000-000000000701\|00000000-0092-2000-0000-000000000701\|* ]] \
  || [[ "$(printf '%s\n' "${link_submit_upgrade_link_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0092 runtime writer 没有返回单行完整五字段 link receipt。' >&2
  exit 1
fi
link_submit_upgrade_link_state_before="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SELECT jsonb_build_object(
        'claim', (
          SELECT jsonb_build_object(
            'link_id', link_id,
            'organization_workspace_id', organization_workspace_id,
            'creator_app_user_id', creator_app_user_id,
            'issued_at_utc', issued_at_utc,
            'expires_at_utc', expires_at_utc
          )
          FROM app_private.organization_shareable_join_link_request_claims
          WHERE link_id = '00000000-0092-6000-0000-000000000701'
        ),
        'audit', (
          SELECT jsonb_agg(to_jsonb(audit_row))
          FROM app_private.organization_shareable_join_link_audit_events AS audit_row
          WHERE link_id = '00000000-0092-6000-0000-000000000701'
        )
      )
      WHERE (SELECT count(*)
             FROM app_private.organization_shareable_join_link_request_claims
             WHERE link_id = '00000000-0092-6000-0000-000000000701') = 1
        AND (SELECT count(*)
             FROM app_private.organization_shareable_join_link_audit_events
             WHERE link_id = '00000000-0092-6000-0000-000000000701'
               AND event_kind = 'link_created') = 1;
    "
)"
if [[ -z "${link_submit_upgrade_link_state_before}" ]]; then
  echo '0092 live link 的 claim 或唯一 link_created audit 缺失。' >&2
  exit 1
fi
link_submit_upgrade_relationship_counts_before="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SELECT concat_ws('|',
        (SELECT count(*) FROM app_data.organization_memberships),
        (SELECT count(*) FROM app_data.organization_owner_assignments),
        (SELECT count(*) FROM app_data.project_memberships),
        (SELECT count(*) FROM app_data.management_report_capability_grants)
      );
    "
)"
if [[ "${link_submit_upgrade_relationship_counts_before}" != '1|1|0|0' ]]; then
  echo '0092 link-submit 基线关系计数漂移。' >&2
  exit 1
fi
link_submit_upgrade_before_migration="$(
  docker exec "${container_name}" pg_dump \
    "${link_submit_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --exclude-table=app_private.organization_shareable_join_application_request_claims \
    --exclude-table=app_private.organization_shareable_join_application_request_tombstones \
    --exclude-table=app_private.organization_shareable_join_application_audit_events \
    --no-owner \
    --no-privileges \
    --restrict-key=6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a
)"
docker exec \
  --env DATABASE_URL="${link_submit_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/link-submit-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
link_submit_upgrade_after_migration="$(
  docker exec "${container_name}" pg_dump \
    "${link_submit_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --exclude-table=app_private.organization_shareable_join_application_request_claims \
    --exclude-table=app_private.organization_shareable_join_application_request_tombstones \
    --exclude-table=app_private.organization_shareable_join_application_audit_events \
    --no-owner \
    --no-privileges \
    --restrict-key=6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a
)"
if [[ "${link_submit_upgrade_before_migration}" != \
  "${link_submit_upgrade_after_migration}" ]]; then
  echo '0093 升级改变了 0092 已有业务表。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${link_submit_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.organization_shareable_join_application_request_claims) <> 0
        OR (SELECT count(*)
            FROM app_private.organization_shareable_join_application_request_tombstones) <> 0
        OR (SELECT count(*)
            FROM app_private.organization_shareable_join_application_audit_events) <> 0
      THEN
        RAISE EXCEPTION '0093 upgrade did not create empty application tables';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
link_submit_upgrade_link_state_after="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SELECT jsonb_build_object(
        'claim', (
          SELECT jsonb_build_object(
            'link_id', link_id,
            'organization_workspace_id', organization_workspace_id,
            'creator_app_user_id', creator_app_user_id,
            'issued_at_utc', issued_at_utc,
            'expires_at_utc', expires_at_utc
          )
          FROM app_private.organization_shareable_join_link_request_claims
          WHERE link_id = '00000000-0092-6000-0000-000000000701'
        ),
        'audit', (
          SELECT jsonb_agg(to_jsonb(audit_row))
          FROM app_private.organization_shareable_join_link_audit_events AS audit_row
          WHERE link_id = '00000000-0092-6000-0000-000000000701'
        )
      );
    "
)"
if [[ "${link_submit_upgrade_link_state_before}" != \
  "${link_submit_upgrade_link_state_after}" ]]; then
  echo '0093 升级改变了旧 link claim 或 link_created audit 字段。' >&2
  exit 1
fi
link_submit_upgrade_replayed_link_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.create_organization_shareable_join_link_for_identity_v1(
        'https://synthetic-link-submit-upgrade.example/auth/v1',
        'owner',
        '00000000-0092-6000-0000-000000000701',
        '00000000-0092-2000-0000-000000000701'
      );
      RESET ROLE;
    "
)"
if [[ "${link_submit_upgrade_link_receipt}" != \
  "${link_submit_upgrade_replayed_link_receipt}" ]]; then
  echo '0093 升级后旧 link replay 改变原五字段 receipt。' >&2
  exit 1
fi
link_submit_upgrade_application_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE link_submit_upgrade_application_receipt (
        organization_shareable_join_application_contract_id text,
        application_id uuid,
        link_id uuid,
        organization_workspace_id uuid,
        submitted_at_utc timestamptz,
        expires_at_utc timestamptz
      );
      CREATE TEMP TABLE link_submit_upgrade_clock_bounds AS
      SELECT clock_timestamp() AS observed_before,
        NULL::timestamptz AS observed_after;
      GRANT ALL ON link_submit_upgrade_application_receipt
        TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      INSERT INTO link_submit_upgrade_application_receipt
      SELECT *
      FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
        'https://synthetic-link-submit-upgrade.example/auth/v1',
        'applicant',
        '00000000-0092-5000-0000-000000000702',
        '00000000-0092-6000-0000-000000000701'
      );
      RESET ROLE;
      UPDATE link_submit_upgrade_clock_bounds
      SET observed_after = clock_timestamp();
      TABLE link_submit_upgrade_application_receipt;
      DO \$submitted\$
      DECLARE
        receipt link_submit_upgrade_application_receipt%ROWTYPE;
        claim
          app_private.organization_shareable_join_application_request_claims%ROWTYPE;
        bounds link_submit_upgrade_clock_bounds%ROWTYPE;
      BEGIN
        SELECT * INTO STRICT receipt
        FROM link_submit_upgrade_application_receipt;
        SELECT * INTO STRICT claim
        FROM app_private.organization_shareable_join_application_request_claims
        WHERE application_id =
          '00000000-0092-5000-0000-000000000702'::uuid;
        SELECT * INTO STRICT bounds FROM link_submit_upgrade_clock_bounds;

        IF receipt.organization_shareable_join_application_contract_id
              IS DISTINCT FROM 'organization-shareable-join-application:v1'
          OR receipt.application_id IS DISTINCT FROM
            '00000000-0092-5000-0000-000000000702'::uuid
          OR receipt.link_id IS DISTINCT FROM
            '00000000-0092-6000-0000-000000000701'::uuid
          OR receipt.organization_workspace_id IS DISTINCT FROM
            '00000000-0092-2000-0000-000000000701'::uuid
          OR receipt.submitted_at_utc IS NULL
          OR receipt.expires_at_utc IS NULL
          OR receipt.submitted_at_utc < bounds.observed_before
          OR receipt.submitted_at_utc > bounds.observed_after
          OR receipt.expires_at_utc IS DISTINCT FROM
            receipt.submitted_at_utc + interval '168 hours'
          OR claim.link_id IS DISTINCT FROM receipt.link_id
          OR claim.organization_workspace_id IS DISTINCT FROM
            receipt.organization_workspace_id
          OR claim.applicant_app_user_id IS DISTINCT FROM
            '00000000-0092-0000-0000-000000000702'::uuid
          OR claim.submitted_at_utc IS DISTINCT FROM receipt.submitted_at_utc
          OR claim.expires_at_utc IS DISTINCT FROM receipt.expires_at_utc
          OR claim.approved_at_utc IS NOT NULL
          OR claim.approved_organization_membership_id IS NOT NULL
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_request_claims) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_request_tombstones) <> 0
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_audit_events) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_audit_events
              WHERE organization_shareable_join_application_contract_id =
                  'organization-shareable-join-application:v1'
                AND application_id = receipt.application_id
                AND link_id = receipt.link_id
                AND organization_workspace_id =
                  receipt.organization_workspace_id
                AND event_kind = 'application_submitted'
                AND organization_membership_id IS NULL
                AND occurred_at_utc = receipt.submitted_at_utc) <> 1
        THEN
          RAISE EXCEPTION '0092→0093 application submit drift';
        END IF;
      END
      \$submitted\$;
    "
)"
if [[ "${link_submit_upgrade_application_receipt}" != \
  organization-shareable-join-application:v1\|00000000-0092-5000-0000-000000000702\|00000000-0092-6000-0000-000000000701\|00000000-0092-2000-0000-000000000701\|* ]] \
  || [[ "$(printf '%s\n' "${link_submit_upgrade_application_receipt}" \
    | awk -F '|' 'NF == 6 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0093 runtime bridge 没有返回单行完整六字段 receipt。' >&2
  exit 1
fi
link_submit_upgrade_relationship_counts_after="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SELECT concat_ws('|',
        (SELECT count(*) FROM app_data.organization_memberships),
        (SELECT count(*) FROM app_data.organization_owner_assignments),
        (SELECT count(*) FROM app_data.project_memberships),
        (SELECT count(*) FROM app_data.management_report_capability_grants)
      );
    "
)"
if [[ "${link_submit_upgrade_relationship_counts_before}" != \
  "${link_submit_upgrade_relationship_counts_after}" ]]; then
  echo '0093 submit 改变了 organization/owner/project membership 或 capability 数量。' >&2
  exit 1
fi
link_submit_upgrade_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${link_submit_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a
)"
link_submit_upgrade_replayed_application_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${link_submit_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
        'https://synthetic-link-submit-upgrade.example/auth/v1',
        'applicant',
        '00000000-0092-5000-0000-000000000702',
        '00000000-0092-6000-0000-000000000701'
      );
      RESET ROLE;
    "
)"
if [[ "${link_submit_upgrade_application_receipt}" != \
  "${link_submit_upgrade_replayed_application_receipt}" ]]; then
  echo '0093 exact replay 改变原六字段 receipt。' >&2
  exit 1
fi
link_submit_upgrade_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${link_submit_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a
)"
if [[ "${link_submit_upgrade_after_first_write}" != \
  "${link_submit_upgrade_after_exact_replay}" ]]; then
  echo '0093 exact replay 增加 claim 或 audit。' >&2
  exit 1
fi
link_submit_upgrade_migration_replay="$(
  docker exec \
    --env DATABASE_URL="${link_submit_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/link-submit-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${link_submit_upgrade_migration_replay}" != \
  *'已验证 0093_organization_shareable_join_application_submit（无需重复执行）'* ]] \
  || [[ "${link_submit_upgrade_migration_replay}" == *'已执行 '* ]]; then
  echo '0093 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${link_submit_upgrade_migration_replay}" >&2
  exit 1
fi
printf '%s\n' "${link_submit_upgrade_migration_replay}"
link_submit_upgrade_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${link_submit_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a
)"
if [[ "${link_submit_upgrade_after_exact_replay}" != \
  "${link_submit_upgrade_after_migration_replay}" ]]; then
  echo '重复 0093 migration 改变申请提交后的业务快照。' >&2
  exit 1
fi
echo '0092→0093 旧 link、submit receipt、关系计数、exact replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0093→0094 升级后可批准旧 writer 已提交的待审申请。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${application_approval_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/application-approval-baseline-migrations \
      /tmp/application-approval-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \
        -o -name '009[0-3]_*.sql' \) \
     -exec cp {} /tmp/application-approval-baseline-migrations/ \; && \
   test \"\$(find /tmp/application-approval-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 92 && \
   cp /workspace/backend/database/migrations/0094_*.sql \
     /tmp/application-approval-upgrade-only/ && \
   test \"\$(find /tmp/application-approval-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${application_approval_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/application-approval-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${application_approval_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 92
        OR (SELECT max(left(version, 4)) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM '0093'
        OR to_regprocedure(
          'app_private.approve_organization_shareable_join_application_v1(uuid,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.approve_organization_shareable_join_application_for_identity_v1(text,text,uuid,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0093 application approval upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
docker exec \
  --workdir /workspace \
  "${container_name}" \
  psql \
  -U postgres \
  -d "${application_approval_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --file /workspace/backend/database/fixtures/upgrade/0093_organization_shareable_join_application_pending.sql \
  >/dev/null
application_approval_original_claim="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${application_approval_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SELECT jsonb_build_object(
        'link_id', link_id::text,
        'applicant_app_user_id', applicant_app_user_id::text,
        'submitted_at_utc', to_char(
          submitted_at_utc AT TIME ZONE 'UTC',
          'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'
        ),
        'expires_at_utc', to_char(
          expires_at_utc AT TIME ZONE 'UTC',
          'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'
        )
      )
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id =
        '00000000-0093-5000-0000-000000000001'::uuid
        AND approved_at_utc IS NULL
        AND approved_organization_membership_id IS NULL;
    "
)"
if [[ -z "${application_approval_original_claim}" ]]; then
  echo '0093 writer 没有提交待审批 application。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${application_approval_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$pending\$
    BEGIN
      IF (SELECT count(*)
          FROM app_data.organization_memberships
          WHERE organization_workspace_id =
            '00000000-0093-2000-0000-000000000001'::uuid) <> 1
        OR (SELECT count(*)
            FROM app_data.organization_owner_assignments) <> 1
        OR (SELECT count(*) FROM app_data.project_memberships) <> 0
        OR (SELECT count(*)
            FROM app_data.management_report_capability_grants) <> 0
        OR (SELECT count(*)
            FROM app_private.organization_shareable_join_application_audit_events
            WHERE application_id =
              '00000000-0093-5000-0000-000000000001'::uuid
              AND event_kind = 'application_submitted'
              AND organization_membership_id IS NULL) <> 1
      THEN
        RAISE EXCEPTION '0093 pending application baseline data drift';
      END IF;
    END
    \$pending\$;
  " \
  >/dev/null
application_approval_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${application_approval_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c
)"
docker exec \
  --env DATABASE_URL="${application_approval_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/application-approval-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
application_approval_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${application_approval_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c
)"
if [[ "${application_approval_before_upgrade}" != \
  "${application_approval_after_upgrade}" ]]; then
  echo '0094 升级改变旧 application 或其他 app_data／app_private 业务数据。' >&2
  exit 1
fi
application_approval_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${application_approval_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE application_approval_receipt (
        organization_shareable_join_application_contract_id text,
        application_id uuid,
        organization_workspace_id uuid,
        organization_membership_id uuid,
        approved_at_utc timestamptz
      );
      GRANT ALL ON application_approval_receipt TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      INSERT INTO application_approval_receipt
      SELECT *
      FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
        'https://synthetic-0093.example/auth/v1',
        'owner',
        '00000000-0093-5000-0000-000000000001',
        '00000000-0093-2000-0000-000000000001'
      );
      RESET ROLE;
      TABLE application_approval_receipt;
      DO \$approved\$
      DECLARE
        receipt application_approval_receipt%ROWTYPE;
        claim
          app_private.organization_shareable_join_application_request_claims%ROWTYPE;
      BEGIN
        SELECT * INTO STRICT receipt FROM application_approval_receipt;
        SELECT * INTO STRICT claim
        FROM app_private.organization_shareable_join_application_request_claims
        WHERE application_id =
          '00000000-0093-5000-0000-000000000001'::uuid;

        IF receipt.organization_shareable_join_application_contract_id
              IS DISTINCT FROM 'organization-shareable-join-application:v1'
          OR receipt.application_id IS DISTINCT FROM
            '00000000-0093-5000-0000-000000000001'::uuid
          OR receipt.organization_workspace_id IS DISTINCT FROM
            '00000000-0093-2000-0000-000000000001'::uuid
          OR receipt.organization_membership_id IS NULL
          OR receipt.approved_at_utc IS NULL
          OR jsonb_build_object(
            'link_id', claim.link_id::text,
            'applicant_app_user_id', claim.applicant_app_user_id::text,
            'submitted_at_utc', to_char(
              claim.submitted_at_utc AT TIME ZONE 'UTC',
              'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'
            ),
            'expires_at_utc', to_char(
              claim.expires_at_utc AT TIME ZONE 'UTC',
              'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'
            )
          ) IS DISTINCT FROM '${application_approval_original_claim}'::jsonb
          OR claim.approved_organization_membership_id IS DISTINCT FROM
            receipt.organization_membership_id
          OR claim.approved_at_utc IS DISTINCT FROM receipt.approved_at_utc
          OR (SELECT count(*)
              FROM app_data.organization_memberships
              WHERE organization_workspace_id = receipt.organization_workspace_id)
            <> 2
          OR NOT EXISTS (
            SELECT 1
            FROM app_data.organization_memberships AS membership
            WHERE membership.organization_membership_id =
                receipt.organization_membership_id
              AND membership.organization_workspace_id =
                receipt.organization_workspace_id
              AND membership.app_user_id =
                '00000000-0093-0000-0000-000000000002'::uuid
              AND membership.active_from_utc = receipt.approved_at_utc
              AND membership.inactive_from_utc IS NULL
          )
          OR (SELECT count(*)
              FROM app_data.organization_owner_assignments) <> 1
          OR (SELECT count(*) FROM app_data.project_memberships) <> 0
          OR (SELECT count(*)
              FROM app_data.management_report_capability_grants) <> 0
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_audit_events
              WHERE application_id = receipt.application_id) <> 2
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_audit_events
              WHERE application_id = receipt.application_id
                AND event_kind = 'application_submitted'
                AND link_id = claim.link_id
                AND organization_workspace_id =
                  claim.organization_workspace_id
                AND organization_membership_id IS NULL
                AND occurred_at_utc = claim.submitted_at_utc) <> 1
          OR (SELECT count(*)
              FROM app_private.organization_shareable_join_application_audit_events
              WHERE application_id = receipt.application_id
                AND event_kind = 'application_approved'
                AND link_id = claim.link_id
                AND organization_workspace_id =
                  claim.organization_workspace_id
                AND organization_membership_id =
                  receipt.organization_membership_id
                AND occurred_at_utc = receipt.approved_at_utc) <> 1
        THEN
          RAISE EXCEPTION '0093→0094 legacy application approval drift';
        END IF;
      END
      \$approved\$;
    "
)"
if [[ "${application_approval_receipt}" != \
  organization-shareable-join-application:v1\|* ]] \
  || [[ "$(printf '%s\n' "${application_approval_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0094 runtime bridge 没有返回单行完整五字段 receipt。' >&2
  exit 1
fi
application_approval_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${application_approval_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c
)"
application_approval_replayed_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${application_approval_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
        'https://synthetic-0093.example/auth/v1',
        'owner',
        '00000000-0093-5000-0000-000000000001',
        '00000000-0093-2000-0000-000000000001'
      );
      RESET ROLE;
    "
)"
if [[ "${application_approval_receipt}" != \
  "${application_approval_replayed_receipt}" ]]; then
  echo '0094 升级后旧 application 的 exact replay 改变原五字段 receipt。' >&2
  exit 1
fi
application_approval_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${application_approval_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c
)"
if [[ "${application_approval_after_first_write}" != \
  "${application_approval_after_exact_replay}" ]]; then
  echo '0094 exact replay 增加 membership 或 audit。' >&2
  exit 1
fi
application_approval_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL="${application_approval_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/application-approval-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${application_approval_upgrade_replay}" != \
  *'已验证 0094_organization_shareable_join_application_approval（无需重复执行）'* ]] \
  || [[ "${application_approval_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0094 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${application_approval_upgrade_replay}" >&2
  exit 1
fi
printf '%s\n' "${application_approval_upgrade_replay}"
application_approval_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${application_approval_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c8c
)"
if [[ "${application_approval_after_exact_replay}" != \
  "${application_approval_after_migration_replay}" ]]; then
  echo '重复 0094 migration 改变已批准 application 的业务快照。' >&2
  exit 1
fi
echo '0093→0094 旧申请批准、单一 membership、完整 receipt、exact replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0094→0095 保留旧 writer 的已提交 organization-creation claim。'
docker exec "${container_name}" createdb -U postgres tongxingzhe_creation_claim_upgrade
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/creation-claim-baseline-migrations /tmp/creation-claim-upgrade-only && \
   find /workspace/backend/database/migrations -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' -o -name '00[1-8][0-9]_*.sql' -o -name '009[0-4]_*.sql' \) \
     -exec cp {} /tmp/creation-claim-baseline-migrations/ \; && \
   test \"\$(find /tmp/creation-claim-baseline-migrations -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 93 && \
   cp /workspace/backend/database/migrations/0095_*.sql /tmp/creation-claim-upgrade-only/ && \
   test \"\$(find /tmp/creation-claim-upgrade-only -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
  --env MIGRATION_DIR=/tmp/creation-claim-baseline-migrations \
  "${container_name}" bash /workspace/tool/postgres_migrate.sh >/dev/null
creation_claim_legacy_receipt="$(
  docker exec "${container_name}" psql -U postgres -d tongxingzhe_creation_claim_upgrade \
    --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0094_organization_creation_claim.sql
)"
if [[ "${creation_claim_legacy_receipt}" != organization-creation:v1\|* ]] \
  || [[ "$(printf '%s\n' "${creation_claim_legacy_receipt}" | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0094 旧 writer 没有返回单行完整五字段 receipt。' >&2
  exit 1
fi
creation_claim_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --exclude-table-data=app_private.organization_creation_request_tombstones \
    --restrict-key=6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a
)"
docker exec \
  --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
  --env MIGRATION_DIR=/tmp/creation-claim-upgrade-only \
  "${container_name}" bash /workspace/tool/postgres_migrate.sh
creation_claim_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --exclude-table-data=app_private.organization_creation_request_tombstones \
    --restrict-key=6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a
)"
if [[ "${creation_claim_before_upgrade}" != "${creation_claim_after_upgrade}" ]]; then
  echo '0095 升级改变旧 claim 或其他 app_data／app_private 业务数据。' >&2
  exit 1
fi
creation_claim_replayed_receipt="$(
  docker exec "${container_name}" psql -U postgres -d tongxingzhe_creation_claim_upgrade \
    --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0094_organization_creation_claim.sql
)"
if [[ "${creation_claim_legacy_receipt}" != "${creation_claim_replayed_receipt}" ]]; then
  echo '0095 升级后旧 organization-creation request 的 exact replay 改变原五字段 receipt。' >&2
  exit 1
fi
creation_claim_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --exclude-table-data=app_private.organization_creation_request_tombstones \
    --restrict-key=6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a
)"
if [[ "${creation_claim_after_upgrade}" != "${creation_claim_after_exact_replay}" ]]; then
  echo '0095 exact replay 改变 organization-creation 业务行。' >&2
  exit 1
fi
creation_claim_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
    --env MIGRATION_DIR=/tmp/creation-claim-upgrade-only \
    "${container_name}" bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${creation_claim_upgrade_replay}" != *'已验证 0095_organization_creation_request_tombstone（无需重复执行）'* ]] \
  || [[ "${creation_claim_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0095 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${creation_claim_upgrade_replay}" >&2
  exit 1
fi
creation_claim_after_replay="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_creation_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --exclude-table-data=app_private.organization_creation_request_tombstones \
    --restrict-key=6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a
)"
if [[ "${creation_claim_after_exact_replay}" != "${creation_claim_after_replay}" ]]; then
  echo '重复 migration 改变 organization-creation 业务行。' >&2
  exit 1
fi
if [[ "$(
  docker exec "${container_name}" psql -U postgres -d tongxingzhe_creation_claim_upgrade \
    --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --command 'SELECT count(*) FROM app_private.organization_creation_request_tombstones'
)" -ne 0 ]]; then
  echo '0095 升级或 exact replay 意外写入 organization-creation tombstone。' >&2
  exit 1
fi
echo '0094→0095 旧 claim、完整 receipt、exact replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0095→0096 升级后可将旧批准成员安排进组织项目。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${project_assignment_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/project-assignment-baseline-migrations \
      /tmp/project-assignment-upgrade-only && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \
        -o -name '009[0-5]_*.sql' \) \
     -exec cp {} /tmp/project-assignment-baseline-migrations/ \; && \
   test \"\$(find /tmp/project-assignment-baseline-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 94 && \
   cp /workspace/backend/database/migrations/0096_*.sql \
     /tmp/project-assignment-upgrade-only/ && \
   test \"\$(find /tmp/project-assignment-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${project_assignment_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/project-assignment-baseline-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${project_assignment_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 94
        OR (SELECT max(version) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM '0095_organization_creation_request_tombstone'
        OR to_regclass(
          'app_private.organization_project_membership_assignment_request_claims'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_project_membership_assignment_request_tombstones'
        ) IS NOT NULL
        OR to_regclass(
          'app_private.organization_project_membership_assignment_audit_events'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.assign_organization_project_member_v1(uuid,uuid,uuid,uuid,uuid)'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_project_membership_assignment_claim_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_private.protect_organization_project_membership_assignment_terminal_v1()'
        ) IS NOT NULL
        OR to_regprocedure(
          'app_data.assign_organization_project_member_for_identity_v1(text,text,uuid,uuid,uuid,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0095 project assignment upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
project_assignment_approval_receipt="$(
  docker exec \
    --workdir /workspace \
    "${container_name}" \
    psql \
    -U postgres \
    -d "${project_assignment_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0095_organization_project_membership_assignment_live.sql
)"
if [[ "${project_assignment_approval_receipt}" != \
  organization-shareable-join-application:v1\|* ]] \
  || [[ "$(printf '%s\n' "${project_assignment_approval_receipt}" \
    | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0095 旧 writer 链没有返回单行完整五字段 approval receipt。' >&2
  exit 1
fi
project_assignment_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_claims \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_tombstones \
    --exclude-table-data=app_private.organization_project_membership_assignment_audit_events \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
docker exec \
  --env DATABASE_URL="${project_assignment_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/project-assignment-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
project_assignment_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_claims \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_tombstones \
    --exclude-table-data=app_private.organization_project_membership_assignment_audit_events \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
if [[ "${project_assignment_before_upgrade}" != \
  "${project_assignment_after_upgrade}" ]]; then
  echo '0096 升级改变旧批准、membership 或其他业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql \
  -U postgres \
  -d "${project_assignment_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$empty\$
    BEGIN
      IF (SELECT count(*)
          FROM app_private.organization_project_membership_assignment_request_claims)
            <> 0
        OR (SELECT count(*)
            FROM app_private.organization_project_membership_assignment_request_tombstones)
              <> 0
        OR (SELECT count(*)
            FROM app_private.organization_project_membership_assignment_audit_events)
              <> 0
      THEN
        RAISE EXCEPTION '0096 assignment tables are not empty after upgrade';
      END IF;
    END
    \$empty\$;
  " \
  >/dev/null
project_assignment_legacy_before_write="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_data.project_memberships \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_claims \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_tombstones \
    --exclude-table-data=app_private.organization_project_membership_assignment_audit_events \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
project_assignment_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${project_assignment_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE project_assignment_receipt (
        project_membership_assignment_contract_id text,
        organization_workspace_id uuid,
        project_id uuid,
        organization_membership_id uuid,
        project_membership_id uuid,
        active_from_utc timestamptz,
        inactive_from_utc timestamptz
      );
      CREATE TEMP TABLE project_assignment_input AS
      SELECT
        organization_workspace_id,
        approved_organization_membership_id AS organization_membership_id
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id =
        '00000000-0095-7000-0000-000000000901'::uuid;
      GRANT ALL ON project_assignment_receipt TO tongxingzhe_runtime;
      GRANT SELECT ON project_assignment_input TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      INSERT INTO project_assignment_receipt
      SELECT *
      FROM app_data.assign_organization_project_member_for_identity_v1(
        'https://synthetic-project-assignment-upgrade.example/auth/v1',
        'owner',
        '00000000-0096-9000-0000-000000000901',
        (
          SELECT organization_workspace_id
          FROM project_assignment_input
        ),
        '00000000-0095-8000-0000-000000000901',
        (
          SELECT organization_membership_id
          FROM project_assignment_input
        )
      );
      RESET ROLE;
      TABLE project_assignment_receipt;
      DO \$assigned\$
      DECLARE
        receipt project_assignment_receipt%ROWTYPE;
        approval
          app_private.organization_shareable_join_application_request_claims%ROWTYPE;
        creation app_private.organization_creation_request_claims%ROWTYPE;
      BEGIN
        SELECT * INTO STRICT receipt FROM project_assignment_receipt;
        SELECT * INTO STRICT approval
        FROM app_private.organization_shareable_join_application_request_claims
        WHERE application_id =
          '00000000-0095-7000-0000-000000000901'::uuid;
        SELECT * INTO STRICT creation
        FROM app_private.organization_creation_request_claims
        WHERE request_id = '00000000-0095-5000-0000-000000000901'::uuid;

        IF (SELECT count(*) FROM project_assignment_receipt) <> 1
          OR receipt.project_membership_assignment_contract_id
            IS DISTINCT FROM 'organization-project-membership-assignment:v1'
          OR receipt.organization_workspace_id IS DISTINCT FROM
            approval.organization_workspace_id
          OR receipt.project_id IS DISTINCT FROM
            '00000000-0095-8000-0000-000000000901'::uuid
          OR receipt.organization_membership_id IS DISTINCT FROM
            approval.approved_organization_membership_id
          OR receipt.project_membership_id IS NULL
          OR receipt.active_from_utc IS NULL
          OR receipt.inactive_from_utc IS NOT NULL
          OR NOT EXISTS (
            SELECT 1
            FROM app_data.project_memberships AS child
            WHERE child.project_membership_id = receipt.project_membership_id
              AND child.organization_membership_id =
                receipt.organization_membership_id
              AND child.project_id = receipt.project_id
              AND child.active_from_utc = receipt.active_from_utc
              AND child.inactive_from_utc IS NOT DISTINCT FROM
                receipt.inactive_from_utc
          )
          OR NOT EXISTS (
            SELECT 1
            FROM app_private.organization_project_membership_assignment_request_claims
              AS claim
            WHERE claim.request_id =
                '00000000-0096-9000-0000-000000000901'::uuid
              AND claim.actor_app_user_id =
                '00000000-0095-0000-0000-000000000901'::uuid
              AND claim.organization_workspace_id =
                receipt.organization_workspace_id
              AND claim.project_id = receipt.project_id
              AND claim.organization_membership_id =
                receipt.organization_membership_id
              AND claim.project_membership_id = receipt.project_membership_id
              AND claim.active_from_utc = receipt.active_from_utc
              AND claim.inactive_from_utc IS NOT DISTINCT FROM
                receipt.inactive_from_utc
          )
          OR NOT EXISTS (
            SELECT 1
            FROM app_private.organization_project_membership_assignment_audit_events
              AS audit
            WHERE audit.project_membership_assignment_audit_event_id IS NOT NULL
              AND audit.project_membership_assignment_contract_id =
                receipt.project_membership_assignment_contract_id
              AND audit.request_id =
                '00000000-0096-9000-0000-000000000901'::uuid
              AND audit.organization_workspace_id =
                receipt.organization_workspace_id
              AND audit.project_id = receipt.project_id
              AND audit.project_membership_id = receipt.project_membership_id
              AND audit.active_from_utc = receipt.active_from_utc
              AND audit.inactive_from_utc IS NOT DISTINCT FROM
                receipt.inactive_from_utc
          )
          OR (SELECT count(*)
              FROM app_private.organization_project_membership_assignment_request_claims)
            <> 1
          OR (SELECT count(*)
              FROM app_private.organization_project_membership_assignment_request_tombstones)
            <> 0
          OR (SELECT count(*)
              FROM app_private.organization_project_membership_assignment_audit_events)
            <> 1
          OR NOT EXISTS (
            SELECT 1
            FROM app_data.organization_memberships AS membership
            WHERE membership.organization_membership_id =
                approval.approved_organization_membership_id
              AND membership.organization_workspace_id =
                approval.organization_workspace_id
              AND membership.app_user_id =
                '00000000-0095-0000-0000-000000000902'::uuid
              AND membership.active_from_utc = approval.approved_at_utc
              AND membership.inactive_from_utc IS NULL
          )
          OR NOT EXISTS (
            SELECT 1
            FROM app_data.organization_memberships AS membership
            JOIN app_data.organization_owner_assignments AS owner
              ON owner.organization_membership_id =
                membership.organization_membership_id
            WHERE membership.organization_membership_id =
                creation.organization_membership_id
              AND membership.organization_workspace_id =
                creation.organization_workspace_id
              AND membership.app_user_id =
                '00000000-0095-0000-0000-000000000901'::uuid
              AND membership.active_from_utc = creation.created_at_utc
              AND membership.inactive_from_utc IS NULL
              AND owner.organization_owner_assignment_id =
                creation.organization_owner_assignment_id
              AND owner.active_from_utc = creation.created_at_utc
              AND owner.inactive_from_utc IS NULL
          )
          OR (SELECT count(*) FROM app_data.organization_owner_assignments) <> 1
          OR (SELECT count(*)
              FROM app_data.organization_memberships
              WHERE organization_workspace_id = receipt.organization_workspace_id)
            <> 2
          OR (SELECT count(*) FROM app_data.project_memberships) <> 1
          OR (SELECT count(*)
              FROM app_data.management_report_capability_grants) <> 0
          OR (SELECT count(*) FROM app_data.promotion_target_assignments) <> 0
        THEN
          RAISE EXCEPTION '0095→0096 project membership assignment drift';
        END IF;
      END
      \$assigned\$;
    "
)"
if [[ "${project_assignment_receipt}" != \
  organization-project-membership-assignment:v1\|* ]] \
  || [[ "$(printf '%s\n' "${project_assignment_receipt}" \
    | awk -F '|' 'NF == 7 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0096 runtime bridge 没有返回单行完整七字段 receipt。' >&2
  exit 1
fi
project_assignment_legacy_after_write="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --exclude-table-data=app_data.project_memberships \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_claims \
    --exclude-table-data=app_private.organization_project_membership_assignment_request_tombstones \
    --exclude-table-data=app_private.organization_project_membership_assignment_audit_events \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
if [[ "${project_assignment_legacy_before_write}" != \
  "${project_assignment_legacy_after_write}" ]]; then
  echo '0096 assignment 改变旧 link、application、membership 或 owner lineage。' >&2
  exit 1
fi
project_assignment_after_first_write="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
project_assignment_replayed_receipt="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${project_assignment_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --quiet \
    --tuples-only \
    --no-align \
    --command="
      CREATE TEMP TABLE project_assignment_input AS
      SELECT
        organization_workspace_id,
        approved_organization_membership_id AS organization_membership_id
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id =
        '00000000-0095-7000-0000-000000000901'::uuid;
      GRANT SELECT ON project_assignment_input TO tongxingzhe_runtime;
      SET ROLE tongxingzhe_runtime;
      SELECT *
      FROM app_data.assign_organization_project_member_for_identity_v1(
        'https://synthetic-project-assignment-upgrade.example/auth/v1',
        'owner',
        '00000000-0096-9000-0000-000000000901',
        (
          SELECT organization_workspace_id
          FROM project_assignment_input
        ),
        '00000000-0095-8000-0000-000000000901',
        (
          SELECT organization_membership_id
          FROM project_assignment_input
        )
      );
      RESET ROLE;
    "
)"
if [[ "${project_assignment_receipt}" != \
  "${project_assignment_replayed_receipt}" ]]; then
  echo '0096 exact replay 改变原七字段 assignment receipt。' >&2
  exit 1
fi
project_assignment_after_exact_replay="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
if [[ "${project_assignment_after_first_write}" != \
  "${project_assignment_after_exact_replay}" ]]; then
  echo '0096 exact replay 增加 project membership、claim 或 audit。' >&2
  exit 1
fi
project_assignment_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL="${project_assignment_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/project-assignment-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${project_assignment_upgrade_replay}" != \
  *'已验证 0096_organization_project_membership_assignment（无需重复执行）'* ]] \
  || [[ "${project_assignment_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0096 重复 migration 没有命中 checksum skip。' >&2
  printf '%s\n' "${project_assignment_upgrade_replay}" >&2
  exit 1
fi
printf '%s\n' "${project_assignment_upgrade_replay}"
project_assignment_after_migration_replay="$(
  docker exec "${container_name}" pg_dump \
    "${project_assignment_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d
)"
if [[ "${project_assignment_after_exact_replay}" != \
  "${project_assignment_after_migration_replay}" ]]; then
  echo '重复 0096 migration 改变 assignment 最终业务快照。' >&2
  exit 1
fi
echo '0095→0096 旧批准成员、七字段 assignment、exact replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0096→0097／0098 保留旧 writer 的已提交 owner-transfer claim。'
docker exec "${container_name}" createdb -U postgres tongxingzhe_owner_claim_upgrade
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/owner-claim-baseline-migrations /tmp/owner-claim-upgrade-only && \
   find /workspace/backend/database/migrations -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' -o -name '00[1-8][0-9]_*.sql' -o -name '009[0-6]_*.sql' \) \
     -exec cp {} /tmp/owner-claim-baseline-migrations/ \; && \
   test \"\$(find /tmp/owner-claim-baseline-migrations -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 95 && \
   cp /workspace/backend/database/migrations/009[78]_*.sql /tmp/owner-claim-upgrade-only/ && \
   test \"\$(find /tmp/owner-claim-upgrade-only -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 2"
docker exec \
  --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
  --env MIGRATION_DIR=/tmp/owner-claim-baseline-migrations \
  "${container_name}" bash /workspace/tool/postgres_migrate.sh >/dev/null
owner_claim_legacy_receipt="$(
  docker exec "${container_name}" psql -U postgres -d tongxingzhe_owner_claim_upgrade \
    --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0096_organization_owner_transfer_claim.sql
)"
if [[ "${owner_claim_legacy_receipt}" != organization-owner-transfer:v1\|* ]] \
  || [[ "$(printf '%s\n' "${owner_claim_legacy_receipt}" | awk -F '|' 'NF == 5 { count++ } END { print count+0 }')" -ne 1 ]]; then
  echo '0096 旧 writer 没有返回单行完整五字段 receipt。' >&2
  exit 1
fi
owner_claim_before_upgrade="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
docker exec \
  --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
  --env MIGRATION_DIR=/tmp/owner-claim-upgrade-only \
  "${container_name}" bash /workspace/tool/postgres_migrate.sh
owner_claim_after_upgrade="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
if [[ "${owner_claim_before_upgrade}" != "${owner_claim_after_upgrade}" ]]; then
  echo '0097／0098 升级改变旧 claim 或其他 app_data／app_private 业务数据。' >&2
  exit 1
fi
docker exec "${container_name}" psql -U postgres -d tongxingzhe_owner_claim_upgrade \
  --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file /workspace/backend/database/fixtures/upgrade/0098_organization_owner_transfer_end_relationships.sql >/dev/null
owner_claim_before_replay="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
owner_claim_replayed_receipt="$(
  docker exec "${container_name}" psql -U postgres -d tongxingzhe_owner_claim_upgrade \
    --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
    --file /workspace/backend/database/fixtures/upgrade/0098_organization_owner_transfer_legacy_replay.sql
)"
if [[ "${owner_claim_legacy_receipt}" != "${owner_claim_replayed_receipt}" ]]; then
  echo '0097／0098 旧 request 的 historical replay 改变原五字段 receipt。' >&2
  exit 1
fi
docker exec \
  --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
  --env MIGRATION_DIR=/tmp/owner-claim-baseline-migrations \
  "${container_name}" bash /workspace/tool/postgres_migrate.sh >/dev/null
docker exec \
  --env DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
  --env MIGRATION_DIR=/tmp/owner-claim-upgrade-only \
  "${container_name}" bash /workspace/tool/postgres_migrate.sh
owner_claim_after_replay="$(
  docker exec "${container_name}" pg_dump \
    postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_owner_claim_upgrade \
    --data-only --schema=app_data --schema=app_private --no-owner --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
if [[ "${owner_claim_before_replay}" != "${owner_claim_after_replay}" ]]; then
  echo '历史 replay 或重复 migration 改变 owner／membership／claim／audit 等业务行。' >&2
  exit 1
fi
echo '0096→0097／0098 旧 claim、完整 receipt、结束关系后的 replay、checksum 幂等与业务数据不变：通过。'

echo '验证 0098→0099 在真实 0093 待审批记录上只新增 reader。'
docker exec "${container_name}" createdb \
  -U postgres \
  "${directory_upgrade_database}"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/application-directory-upgrade-migrations && \
   find /workspace/backend/database/migrations \
     -maxdepth 1 -type f \
     \( -name '000[1-9]_*.sql' \
        -o -name '00[1-8][0-9]_*.sql' \
        -o -name '009[0-8]_*.sql' \) \
     -exec cp {} /tmp/application-directory-upgrade-migrations/ \; && \
   test \"\$(find /tmp/application-directory-upgrade-migrations \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 97"
docker exec \
  --env DATABASE_URL="${directory_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/application-directory-upgrade-migrations \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh \
  >/dev/null
docker exec "${container_name}" psql \
  -U postgres \
  -d "${directory_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    DO \$baseline\$
    BEGIN
      IF (SELECT count(*) FROM app_migrations.schema_migrations) <> 97
        OR (SELECT max(left(version, 4)) FROM app_migrations.schema_migrations)
          IS DISTINCT FROM '0098'
        OR to_regprocedure(
          'app_data.list_org_join_applications_for_identity_v1(text,text,uuid)'
        ) IS NOT NULL
      THEN
        RAISE EXCEPTION '0098 directory upgrade baseline drift';
      END IF;
    END
    \$baseline\$;
  " \
  >/dev/null
docker exec \
  --workdir /workspace \
  "${container_name}" \
  psql \
  -U postgres \
  -d "${directory_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --file /workspace/backend/database/fixtures/upgrade/0093_organization_shareable_join_application_pending.sql \
  >/dev/null
directory_upgrade_original_item="$(
  docker exec "${container_name}" psql \
    -U postgres \
    -d "${directory_upgrade_database}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --tuples-only \
    --no-align \
    --command="
      SELECT jsonb_build_object(
        'application_id', application_id::text,
        'link_id', link_id::text,
        'submitted_at_utc', to_char(submitted_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'),
        'expires_at_utc', to_char(expires_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')
      )
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id = '00000000-0093-5000-0000-000000000001'
        AND approved_at_utc IS NULL
        AND approved_organization_membership_id IS NULL;
    "
)"
if [[ -z "${directory_upgrade_original_item}" ]]; then
  echo '0093 writer did not commit the old pending application.' >&2
  exit 1
fi
directory_upgrade_before="$(
  docker exec "${container_name}" pg_dump \
    "${directory_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
docker exec "${container_name}" bash -lc \
  "mkdir /tmp/application-directory-upgrade-only && \
   cp /workspace/backend/database/migrations/0099_*.sql \
     /tmp/application-directory-upgrade-only/ && \
   test \"\$(find /tmp/application-directory-upgrade-only \
     -maxdepth 1 -type f -name '*.sql' | wc -l | tr -d ' ')\" -eq 1"
docker exec \
  --env DATABASE_URL="${directory_upgrade_url}" \
  --env MIGRATION_DIR=/tmp/application-directory-upgrade-only \
  "${container_name}" \
  bash /workspace/tool/postgres_migrate.sh
directory_upgrade_replay="$(
  docker exec \
    --env DATABASE_URL="${directory_upgrade_url}" \
    --env MIGRATION_DIR=/tmp/application-directory-upgrade-only \
    "${container_name}" \
    bash /workspace/tool/postgres_migrate.sh
)"
if [[ "${directory_upgrade_replay}" != *'已验证 0099_organization_shareable_join_application_directory（无需重复执行）'* ]] \
  || [[ "${directory_upgrade_replay}" == *'已执行 '* ]]; then
  echo '0099 directory migration did not skip its checksum-verified replay.' >&2
  printf '%s\n' "${directory_upgrade_replay}" >&2
  exit 1
fi
printf '%s\n' "${directory_upgrade_replay}"
docker exec "${container_name}" psql \
  -U postgres \
  -d "${directory_upgrade_database}" \
  --no-psqlrc \
  --set=ON_ERROR_STOP=1 \
  --command="
    SET ROLE tongxingzhe_runtime;
    DO \$upgrade\$
    DECLARE
      receipt record;
      item jsonb;
      actual_state text;
      actual_message text;
    BEGIN
      SELECT * INTO STRICT receipt
      FROM app_data.list_org_join_applications_for_identity_v1(
        'https://synthetic-0093.example/auth/v1',
        'owner',
        '00000000-0093-2000-0000-000000000001'
      );
      IF receipt.organization_shareable_join_application_directory_contract_id
          IS DISTINCT FROM 'organization-shareable-join-application-directory:v1'
        OR receipt.organization_workspace_id IS DISTINCT FROM
          '00000000-0093-2000-0000-000000000001'::uuid
        OR receipt.observed_at_utc IS NULL
        OR jsonb_array_length(receipt.applications) <> 1
      THEN
        RAISE EXCEPTION '0098→0099 old pending application directory metadata drift';
      END IF;
      item := receipt.applications->0;
      IF item IS DISTINCT FROM '${directory_upgrade_original_item}'::jsonb
      THEN
        RAISE EXCEPTION '0098→0099 old pending application item drift';
      END IF;

      BEGIN
        PERFORM *
        FROM app_data.list_org_join_applications_for_identity_v1(
          'https://synthetic-0093.example/auth/v1',
          'pending-applicant',
          '00000000-0093-2000-0000-000000000001'
        );
        RAISE EXCEPTION '0099 non-owner directory read was accepted';
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
          actual_state = RETURNED_SQLSTATE,
          actual_message = MESSAGE_TEXT;
        IF actual_state IS DISTINCT FROM '42501'
          OR actual_message IS DISTINCT FROM
            'organization shareable join application directory forbidden'
        THEN
          RAISE EXCEPTION '0099 non-owner directory read drift: % / %',
            actual_state, actual_message;
        END IF;
      END;
    END
    \$upgrade\$;
    RESET ROLE;
  " \
  >/dev/null
directory_upgrade_after="$(
  docker exec "${container_name}" pg_dump \
    "${directory_upgrade_url}" \
    --data-only \
    --schema=app_data \
    --schema=app_private \
    --no-owner \
    --no-privileges \
    --restrict-key=7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
)"
if [[ "${directory_upgrade_before}" != "${directory_upgrade_after}" ]]; then
  echo '0098→0099 directory migration changed app_data/app_private business data.' >&2
  exit 1
fi
echo '0098→0099 旧 0093 待审批记录可读、授权与业务数据不变、checksum 幂等：通过。'

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

echo "用真实 Backend adapter 对账 PostgreSQL（${backend_image}）。"
docker run \
  --rm \
  --network "container:${container_name}" \
  --mount "type=bind,src=${repository_root},dst=/source,readonly" \
  --mount 'type=volume,dst=/work' \
  --workdir /work \
  --env DATABASE_URL="${database_url}" \
  --env CURRENT_CITY_RUNTIME_FIXTURE=/source/backend/database/fixtures/0059_runtime_authorized_management_current_city_report_snapshot_read.sql \
  --env INTEREST_RUNTIME_FIXTURE=/source/backend/database/fixtures/0064_runtime_authorized_management_interest_report_snapshot_read.sql \
  --env ORIGINAL_REGION_RUNTIME_FIXTURE=/source/backend/database/fixtures/0070_runtime_authorized_management_original_region_report_snapshot_read.sql \
  --env FOLLOW_UP_CONSENT_RATIO_RUNTIME_FIXTURE=/source/backend/database/fixtures/0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql \
  --env INTEREST_DIRECTORY_FIXTURE=/source/backend/database/fixtures/0065_authorized_management_interest_report_snapshot_directory.sql \
  --env ORIGINAL_REGION_DIRECTORY_FIXTURE=/source/backend/database/fixtures/0071_authorized_management_original_region_report_snapshot_directory.sql \
  --env FOLLOW_UP_CONSENT_RATIO_DIRECTORY_FIXTURE=/source/backend/database/fixtures/0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql \
  --env ORGANIZATION_CREATION_FIXTURE=/source/backend/database/fixtures/0084_organization_creation.sql \
  --env OWNER_TRANSFER_FIXTURE=/source/backend/database/fixtures/0086_organization_owner_transfer.sql \
  --env ORGANIZATION_DIRECTED_ACCOUNT_INVITATION_FIXTURE=/source/backend/database/fixtures/0087_organization_directed_account_invitation.sql \
  --env ORGANIZATION_DIRECTORY_FIXTURE=/source/backend/database/fixtures/0089_organization_directory.sql \
  --env ORGANIZATION_MEMBERSHIP_SELF_LEAVE_FIXTURE=/source/backend/database/fixtures/0090_organization_membership_self_leave.sql \
  --env ORGANIZATION_SHAREABLE_JOIN_LINK_FIXTURE=/source/backend/database/fixtures/0092_organization_shareable_join_link.sql \
  --env ORGANIZATION_SHAREABLE_JOIN_APPLICATION_SUBMIT_FIXTURE=/source/backend/database/fixtures/0093_organization_shareable_join_application_submit.sql \
  --env ORGANIZATION_SHAREABLE_JOIN_APPLICATION_APPROVAL_FIXTURE=/source/backend/database/fixtures/0094_organization_shareable_join_application_approval.sql \
  --env ORGANIZATION_SHAREABLE_JOIN_APPLICATION_DIRECTORY_FIXTURE=/source/backend/database/fixtures/0099_organization_shareable_join_application_directory.sql \
  --env ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE=/source/backend/database/fixtures/0096_organization_project_membership_assignment.sql \
  "${backend_image}" \
  bash -lc \
    'mkdir -p backend/server backend/database/fixtures &&
     cp /source/backend/server/package.json \
        /source/backend/server/package-lock.json \
        /source/backend/server/tsconfig.json \
        backend/server/ &&
     cp -R /source/backend/server/src /source/backend/server/test \
        backend/server/ &&
     cp -R /source/backend/database/fixtures/shared \
        backend/database/fixtures/ &&
     cd backend/server &&
     npm ci --ignore-scripts &&
     npm run build &&
     node --enable-source-maps --test \
       dist/test/contact-location-evidence.integration.js \
       dist/test/organization-creation.integration.js \
       dist/test/organization-directory.integration.js \
       dist/test/organization-directed-account-invitations.integration.js \
       dist/test/organization-membership-self-leave.integration.js \
       dist/test/organization-shareable-join-links.integration.js \
       dist/test/organization-shareable-join-applications.integration.js \
       dist/test/organization-shareable-join-application-directory.integration.js \
       dist/test/organization-owner-transfer.integration.js \
       dist/test/organization-project-membership-assignment.integration.js \
       dist/test/organization-project-membership-assignment-http.integration.js \
       dist/test/organization-join-project-assignment-http.integration.js \
       dist/test/personal-current-relationship-stage.integration.js \
       dist/test/personal-relationship-stage-change-summary.integration.js \
       dist/test/personal-follow-up-consent-ratio.integration.js \
       dist/test/personal-follow-up-consent-opt-in.integration.js \
       dist/test/management-current-city-report-snapshots.integration.js \
       dist/test/management-current-city-report-snapshot-directory.integration.js \
       dist/test/management-interest-report-snapshots.integration.js \
       dist/test/management-interest-report-snapshot-directory.integration.js \
       dist/test/management-original-region-report-snapshots.integration.js \
       dist/test/management-original-region-report-snapshot-directory.integration.js \
       dist/test/management-follow-up-consent-ratio-report-snapshots.integration.js \
       dist/test/management-follow-up-consent-ratio-snapshot-directory.integration.js'

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
