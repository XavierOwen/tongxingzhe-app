#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
command -v "${psql_command}" >/dev/null 2>&1 || {
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
}
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"

psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1)
run_psql() { "${psql_base[@]}" "$@"; }
run_named_psql() {
  local application_name="$1"
  shift
  PGAPPNAME="${application_name}" "${psql_base[@]}" "$@"
}

temporary_directory="$(mktemp -d)"
child_pids=()
cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  run_psql --quiet --command='DROP TABLE IF EXISTS app_private.organization_report_write_fence_probe_0102' >/dev/null 2>&1 || true
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_query() {
  local application_name="$1" output="$2" found
  for _ in $(seq 1 200); do
    found="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (SELECT 1 FROM pg_stat_activity
        WHERE application_name = '${application_name}'
          AND state = 'active' AND query LIKE '%pg_sleep%')" | tr -d '[:space:]')"
    if [[ "${found}" == t ]]; then return; fi
    if [[ -n "${output}" ]] && ! kill -0 "$3" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo "会话未进入预期等待点：${application_name}" >&2
  [[ -z "${output}" ]] || sed -n '1,100p' "${output}" >&2
  exit 1
}

wait_for_blocker() {
  local waiting_app="$1" blocker_app="$2" output="$3" blocked
  for _ in $(seq 1 200); do
    blocked="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_stat_activity AS waiting
        WHERE waiting.application_name = '${waiting_app}'
          AND EXISTS (
            SELECT 1 FROM pg_stat_activity AS blocker
            WHERE blocker.pid = ANY(pg_blocking_pids(waiting.pid))
              AND blocker.application_name = '${blocker_app}'
          )
      )" | tr -d '[:space:]')"
    if [[ "${blocked}" == t ]]; then return; fi
    sleep 0.05
  done
  echo "未观察到 ${waiting_app} 被 ${blocker_app} 阻塞。" >&2
  sed -n '1,100p' "${output}" >&2
  exit 1
}

actor='10000000-0102-0000-8000-000000000001'
organization_request_one='10000000-0102-4000-8000-000000000001'
restore_request_one='10000000-0102-5000-8000-000000000001'
organization_request_two='10000000-0102-4000-8000-000000000002'
restore_request_two='10000000-0102-5000-8000-000000000002'
project='10000000-0102-6000-8000-000000000001'

run_psql --quiet <<SQL
BEGIN;
INSERT INTO app_data.app_users(app_user_id, status) VALUES ('${actor}', 'active');
SELECT * FROM app_private.create_organization_v1(
  '${actor}'::uuid, '10000000-0102-3000-8000-000000000001'::uuid,
  '0102 fence concurrency organization');
INSERT INTO app_data.projects(project_id, workspace_id, display_name)
SELECT '${project}'::uuid, organization_workspace_id, '0102 fence concurrency project'
FROM app_private.organization_creation_request_claims
WHERE request_id = '10000000-0102-3000-8000-000000000001'::uuid;
COMMIT;

CREATE TABLE app_private.organization_report_write_fence_probe_0102 (
  probe_id text PRIMARY KEY,
  project_id uuid NOT NULL
);
CREATE TRIGGER organization_report_write_fence_probe_0102
BEFORE INSERT ON app_private.organization_report_write_fence_probe_0102
FOR EACH ROW EXECUTE FUNCTION
  app_private.require_active_organization_report_write_v1();
SQL

workspace="$(run_psql --tuples-only --no-align --command="
  SELECT workspace_id FROM app_data.projects WHERE project_id = '${project}'::uuid" \
  | tr -d '[:space:]')"

echo '验证报告写入先取得 KEY SHARE，删除事务等待后再完成。'
writer_first='0102-fence-writer-first'
delete_second='0102-fence-delete-second'
writer_first_output="${temporary_directory}/writer-first.out"
delete_second_output="${temporary_directory}/delete-second.out"
run_named_psql "${writer_first}" --quiet --command="
  BEGIN;
  INSERT INTO app_private.organization_report_write_fence_probe_0102
    (probe_id, project_id) VALUES ('writer-first', '${project}'::uuid);
  SELECT pg_sleep(2);
  COMMIT;" >"${writer_first_output}" 2>&1 &
writer_first_pid=$!; child_pids+=("${writer_first_pid}")
wait_for_query "${writer_first}" "${writer_first_output}" "${writer_first_pid}"
run_named_psql "${delete_second}" --quiet --command="
  BEGIN;
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor}'::uuid, '${organization_request_one}'::uuid, '${workspace}'::uuid);
  SELECT pg_sleep(1);
  COMMIT;" >"${delete_second_output}" 2>&1 &
delete_second_pid=$!; child_pids+=("${delete_second_pid}")
wait_for_blocker "${delete_second}" "${writer_first}" "${delete_second_output}"
wait "${writer_first_pid}"
wait "${delete_second_pid}"
if [[ "$(run_psql --tuples-only --no-align --command="
  SELECT (SELECT count(*) FROM app_private.organization_report_write_fence_probe_0102
    WHERE probe_id = 'writer-first') = 1
    AND (SELECT deleted_at IS NOT NULL FROM app_data.workspaces
      WHERE workspace_id = '${workspace}'::uuid)" | tr -d '[:space:]')" != t ]]; then
  echo '写事务先完成后，删除状态或已提交 fence probe 不符合预期。' >&2
  exit 1
fi

run_psql --quiet --command="
  SELECT * FROM app_private.restore_organization_v1(
    '${actor}'::uuid, '${restore_request_one}'::uuid, '${workspace}'::uuid,
    '${organization_request_one}'::uuid)" >/dev/null

echo '验证删除事务先取得 FOR UPDATE，新写等待后失败且不留记录。'
delete_first='0102-fence-delete-first'
writer_second='0102-fence-writer-second'
delete_first_output="${temporary_directory}/delete-first.out"
writer_second_output="${temporary_directory}/writer-second.out"
run_named_psql "${delete_first}" --quiet --command="
  BEGIN;
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor}'::uuid, '${organization_request_two}'::uuid, '${workspace}'::uuid);
  SELECT pg_sleep(2);
  COMMIT;" >"${delete_first_output}" 2>&1 &
delete_first_pid=$!; child_pids+=("${delete_first_pid}")
wait_for_query "${delete_first}" "${delete_first_output}" "${delete_first_pid}"
run_named_psql "${writer_second}" --quiet --command="
  BEGIN;
  INSERT INTO app_private.organization_report_write_fence_probe_0102
    (probe_id, project_id) VALUES ('writer-second', '${project}'::uuid);
  COMMIT;" >"${writer_second_output}" 2>&1 &
writer_second_pid=$!; child_pids+=("${writer_second_pid}")
wait_for_blocker "${writer_second}" "${delete_first}" "${writer_second_output}"
delete_first_status=0; writer_second_status=0
wait "${delete_first_pid}" || delete_first_status=$?
wait "${writer_second_pid}" || writer_second_status=$?
if [[ "${delete_first_status}" -ne 0 || "${writer_second_status}" -eq 0 ]] \
  || ! grep -q 'organization report write unavailable' "${writer_second_output}"; then
  echo '删除先完成时，等待中的新写入没有按 fence 失败。' >&2
  sed -n '1,100p' "${writer_second_output}" >&2
  exit 1
fi

if [[ "$(run_psql --tuples-only --no-align --command="
  SELECT (SELECT count(*) FROM app_private.organization_report_write_fence_probe_0102
    WHERE probe_id = 'writer-second') = 0
    AND (SELECT deleted_at IS NOT NULL FROM app_data.workspaces
      WHERE workspace_id = '${workspace}'::uuid)
    AND (SELECT count(*) FROM app_private.management_report_snapshots
      WHERE project_id = '${project}'::uuid) = 0
    AND (SELECT count(*) FROM app_private.management_report_release_attempts
      WHERE project_id = '${project}'::uuid) = 0
    AND (SELECT count(*) FROM app_private.management_report_snapshot_export_events
      WHERE project_id = '${project}'::uuid) = 0
    AND (SELECT count(*) FROM app_private.management_follow_up_consent_opt_in_versions
      WHERE project_id = '${project}'::uuid) = 0" | tr -d '[:space:]')" != t ]]; then
  echo '删除先完成时留下了写入或部分报告/config 事实。' >&2
  exit 1
fi

run_psql --quiet --command="
  SELECT * FROM app_private.restore_organization_v1(
    '${actor}'::uuid, '${restore_request_two}'::uuid, '${workspace}'::uuid,
    '${organization_request_two}'::uuid)" >/dev/null
run_psql --quiet --command='DROP TABLE app_private.organization_report_write_fence_probe_0102' >/dev/null
echo '组织报告写入 fence 的双向真实会话锁顺序：通过。'
