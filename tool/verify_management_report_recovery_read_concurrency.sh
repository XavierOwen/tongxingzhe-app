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
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_query() {
  local application_name="$1" output="$2" found
  for _ in $(seq 1 160); do
    found="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (SELECT 1 FROM pg_stat_activity
        WHERE application_name = '${application_name}'
          AND state = 'active' AND query LIKE '%pg_sleep%')" | tr -d '[:space:]')"
    if [[ "${found}" == t ]]; then return; fi
    sleep 0.05
  done
  echo "会话未进入持锁点：${application_name}" >&2
  sed -n '1,100p' "${output}" >&2
  exit 1
}

wait_for_blocker() {
  local waiting_app="$1" blocker_app="$2" output="$3" blocked
  for _ in $(seq 1 160); do
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

actor_one='81030000-0103-4000-8000-000000000001'
actor_two='81030000-0103-4000-8000-000000000002'
organization_create_request='81030000-0103-4000-8000-000000000003'
organization_request_one='81030000-0103-4000-8000-000000000004'
restore_request_one='81030000-0103-4000-8000-000000000005'
organization_request_two='81030000-0103-4000-8000-000000000006'
restore_request_two='81030000-0103-4000-8000-000000000007'
project='81030000-0103-4000-8000-000000000010'
member_one='81030000-0103-4000-8000-000000000011'
member_two='81030000-0103-4000-8000-000000000012'
grant_one='81030000-0103-4000-8000-000000000013'
grant_two='81030000-0103-4000-8000-000000000014'
missing_snapshot='81030000-0103-4000-8000-000000000015'

run_psql --quiet <<SQL
BEGIN;
INSERT INTO app_data.app_users (app_user_id, status) VALUES
  ('${actor_one}', 'active'), ('${actor_two}', 'active');
SELECT * FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '${organization_create_request}'::uuid,
  '0103 report recovery concurrency organization');
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
SELECT '${project}'::uuid, claim.organization_workspace_id,
  '0103 report recovery concurrency project'
FROM app_private.organization_creation_request_claims AS claim
WHERE claim.request_id = '${organization_create_request}'::uuid;
INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
SELECT '${member_two}'::uuid, claim.organization_workspace_id,
  '${actor_two}'::uuid, transaction_timestamp(), NULL
FROM app_private.organization_creation_request_claims AS claim
WHERE claim.request_id = '${organization_create_request}'::uuid;
INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id, active_from_utc
)
SELECT '81030000-0103-4000-8000-000000000020'::uuid,
  membership.organization_membership_id, '${project}'::uuid,
  membership.active_from_utc
FROM app_data.organization_memberships AS membership
WHERE membership.app_user_id = '${actor_one}'::uuid
  AND membership.organization_workspace_id = (
    SELECT organization_workspace_id
    FROM app_private.organization_creation_request_claims
    WHERE request_id = '${organization_create_request}'::uuid
  );
INSERT INTO app_data.project_memberships VALUES
  ('81030000-0103-4000-8000-000000000021'::uuid, '${member_two}'::uuid,
   '${project}'::uuid, transaction_timestamp(), NULL);
INSERT INTO app_data.management_report_capability_grants VALUES
  ('${grant_one}'::uuid, '81030000-0103-4000-8000-000000000020'::uuid,
   'view_anonymous_analytics', transaction_timestamp(), NULL),
  ('${grant_two}'::uuid, '81030000-0103-4000-8000-000000000021'::uuid,
   'view_anonymous_analytics', transaction_timestamp(), NULL);
COMMIT;
SQL

workspace="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id
  FROM app_private.organization_creation_request_claims
  WHERE request_id = '${organization_create_request}'::uuid" | tr -d '[:space:]')"

read_report() {
  local actor="$1"
  run_psql --quiet --tuples-only --no-align --command="
    SELECT app_private.read_authorized_management_report_snapshot_v1(
      '${actor}'::uuid, '${project}'::uuid, '${missing_snapshot}'::uuid
    )->>'result_status'"
}

echo '验证读取先发生时，删除等待治理锁后再线性化。'
read_first_output="${temporary_directory}/read-first-delete.out"
delete_second_output="${temporary_directory}/delete-second.out"
run_named_psql '0103-read-first-delete' --quiet --command="
  BEGIN;
  SELECT app_private.read_authorized_management_report_snapshot_v1(
    '${actor_one}'::uuid, '${project}'::uuid, '${missing_snapshot}'::uuid);
  SELECT pg_sleep(2);
  COMMIT;" >"${read_first_output}" 2>&1 &
read_first_pid=$!; child_pids+=("${read_first_pid}")
wait_for_query '0103-read-first-delete' "${read_first_output}"
run_named_psql '0103-delete-second' --quiet --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${organization_request_one}'::uuid,
    '${workspace}'::uuid);" >"${delete_second_output}" 2>&1 &
delete_second_pid=$!; child_pids+=("${delete_second_pid}")
wait_for_blocker '0103-delete-second' '0103-read-first-delete' "${delete_second_output}"
wait "${read_first_pid}"
wait "${delete_second_pid}"
run_psql --quiet --command="
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_one}'::uuid, '${restore_request_one}'::uuid,
    '${workspace}'::uuid, '${organization_request_one}'::uuid);" >/dev/null

echo '验证删除先发生时，等待中的既有报告读取在 pending 下通过。'
delete_first_output="${temporary_directory}/delete-first-read.out"
read_second_output="${temporary_directory}/delete-first-read-second.out"
run_named_psql '0103-delete-first' --quiet --command="
  BEGIN;
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${organization_request_two}'::uuid,
    '${workspace}'::uuid);
  SELECT pg_sleep(2);
  COMMIT;" >"${delete_first_output}" 2>&1 &
delete_first_pid=$!; child_pids+=("${delete_first_pid}")
wait_for_query '0103-delete-first' "${delete_first_output}"
run_named_psql '0103-read-after-delete' --quiet --command="
  SELECT app_private.read_authorized_management_report_snapshot_v1(
    '${actor_one}'::uuid, '${project}'::uuid, '${missing_snapshot}'::uuid);" \
  >"${read_second_output}" 2>&1 &
read_second_pid=$!; child_pids+=("${read_second_pid}")
wait_for_blocker '0103-read-after-delete' '0103-delete-first' "${read_second_output}"
wait "${delete_first_pid}"
wait "${read_second_pid}"
if ! grep -q 'not_found' "${read_second_output}"; then
  echo '删除先提交后，等待中的既有报告读取没有返回原 not_found 合同。' >&2
  sed -n '1,100p' "${read_second_output}" >&2
  exit 1
fi

echo '验证读取先发生时，恢复等待治理锁后完成。'
restore_first_output="${temporary_directory}/restore-first-read.out"
restore_second_output="${temporary_directory}/read-first-restore.out"
run_named_psql '0103-read-first-restore' --quiet --command="
  BEGIN;
  SELECT app_private.read_authorized_management_report_snapshot_v1(
    '${actor_one}'::uuid, '${project}'::uuid, '${missing_snapshot}'::uuid);
  SELECT pg_sleep(2);
  COMMIT;" >"${restore_second_output}" 2>&1 &
restore_second_pid=$!; child_pids+=("${restore_second_pid}")
wait_for_query '0103-read-first-restore' "${restore_second_output}"
run_named_psql '0103-restore-after-read' --quiet --command="
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_one}'::uuid, '${restore_request_two}'::uuid,
    '${workspace}'::uuid, '${organization_request_two}'::uuid);" \
  >"${restore_first_output}" 2>&1 &
restore_first_pid=$!; child_pids+=("${restore_first_pid}")
wait_for_blocker '0103-restore-after-read' '0103-read-first-restore' "${restore_first_output}"
wait "${restore_second_pid}"
wait "${restore_first_pid}"

echo '验证读取先发生时，capability 撤权等待对应 authorization lock。'
capability_read_output="${temporary_directory}/capability-read-first.out"
capability_revoke_output="${temporary_directory}/capability-revoke-second.out"
run_named_psql '0103-read-first-revoke' --quiet --command="
  BEGIN;
  SELECT app_private.read_authorized_management_report_snapshot_v1(
    '${actor_one}'::uuid, '${project}'::uuid, '${missing_snapshot}'::uuid);
  SELECT pg_sleep(2);
  COMMIT;" >"${capability_read_output}" 2>&1 &
capability_read_pid=$!; child_pids+=("${capability_read_pid}")
wait_for_query '0103-read-first-revoke' "${capability_read_output}"
run_named_psql '0103-revoke-after-read' --quiet --command="
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${grant_one}'::uuid;" \
  >"${capability_revoke_output}" 2>&1 &
capability_revoke_pid=$!; child_pids+=("${capability_revoke_pid}")
wait_for_blocker '0103-revoke-after-read' '0103-read-first-revoke' "${capability_revoke_output}"
wait "${capability_read_pid}"
wait "${capability_revoke_pid}"

echo '验证撤权先发生时，后续既有报告读取失败关闭。'
if read_report "${actor_one}" >/dev/null 2>&1; then
  echo '撤权提交后仍能读取管理报告。' >&2
  exit 1
fi

echo '验证恢复先完成后，active 行仍按原报告权限读取。'
if [[ "$(read_report "${actor_two}" | tr -d '[:space:]')" != 'not_found' ]]; then
  echo '恢复后的 active 组织未保留既有报告读取合同。' >&2
  exit 1
fi

echo 'Slice 7CX report recovery read concurrency checks passed.'
