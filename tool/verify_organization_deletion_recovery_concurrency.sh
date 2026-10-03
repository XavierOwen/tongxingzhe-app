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

wait_for_ready() {
  local name="$1" pid="$2" output="$3" held
  for _ in $(seq 1 100); do
    held="$(run_psql --tuples-only --no-align --command="
      WITH probe AS (SELECT pg_try_advisory_lock(hashtextextended('${name}', 0)) AS acquired)
      SELECT CASE WHEN acquired THEN NOT pg_advisory_unlock(hashtextextended('${name}', 0))
        ELSE true END FROM probe" | tr -d '[:space:]')"
    if [[ "${held}" == t ]]; then return; fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo "持锁会话未就绪：${name}" >&2
  sed -n '1,100p' "${output}" >&2
  exit 1
}

wait_for_lock() {
  local name="$1" pid="$2" output="$3" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH key AS (SELECT
        ((hashtextextended('${name}', 0) >> 32) & 4294967295)::bigint AS classid,
        (hashtextextended('${name}', 0) & 4294967295)::bigint AS objid,
        (SELECT oid FROM pg_database WHERE datname = current_database()) AS database_id)
      SELECT EXISTS (SELECT 1 FROM pg_locks AS lock_row CROSS JOIN key
        WHERE lock_row.locktype = 'advisory' AND NOT lock_row.granted
          AND lock_row.database = key.database_id
          AND lock_row.classid::bigint = key.classid
          AND lock_row.objid::bigint = key.objid AND lock_row.objsubid = 1)" \
      | tr -d '[:space:]')"
    if [[ "${waiting}" == t ]]; then return; fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo "未观察到锁等待：${name}" >&2
  sed -n '1,100p' "${output}" >&2
  exit 1
}

wait_for_actor_lock() {
  local pid="$1" output="$2" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (SELECT 1 FROM pg_locks AS lock_row
        WHERE NOT lock_row.granted AND
          (lock_row.locktype = 'transactionid'
            OR (lock_row.locktype = 'tuple'
              AND lock_row.relation = 'app_data.app_users'::regclass)))" \
      | tr -d '[:space:]')"
    if [[ "${waiting}" == t ]]; then return; fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo '未观察到 actor 行锁等待。' >&2
  sed -n '1,100p' "${output}" >&2
  exit 1
}

assert_failure() {
  local file="$1" state="$2" message="$3"
  if ! grep -q "${state}" "${file}" || ! grep -q "${message}" "${file}"; then
    echo "并发失败不符合 ${state} / ${message}" >&2
    sed -n '1,100p' "${file}" >&2
    exit 1
  fi
}

actor_one='10000000-0100-0000-8000-000000000001'
actor_two='10000000-0100-0000-8000-000000000002'
actor_three='10000000-0100-0000-8000-000000000003'
same_request='10000000-0100-4000-8000-000000000001'
other_request='10000000-0100-4000-8000-000000000002'
restore_request='10000000-0100-5000-8000-000000000001'
status_request='10000000-0100-4000-8000-000000000003'
other_first_request='10000000-0100-4000-8000-000000000004'

run_psql --quiet <<SQL
BEGIN;
INSERT INTO app_data.app_users(app_user_id, status) VALUES
  ('${actor_one}', 'active'), ('${actor_two}', 'active'),
  ('${actor_three}', 'active');
SELECT organization_workspace_id FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '10000000-0100-1000-8000-000000000001'::uuid,
  '0100 concurrent organization');
SELECT organization_workspace_id FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '10000000-0100-1000-8000-000000000002'::uuid,
  '0100 different request organization');
SELECT organization_workspace_id FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '10000000-0100-1000-8000-000000000003'::uuid,
  '0100 actor status organization');
SELECT organization_workspace_id FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '10000000-0100-1000-8000-000000000004'::uuid,
  '0100 transfer before request organization');
SELECT organization_workspace_id FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '10000000-0100-1000-8000-000000000005'::uuid,
  '0100 restore before transfer organization');
SELECT organization_workspace_id FROM app_private.create_organization_v1(
  '${actor_one}'::uuid, '10000000-0100-1000-8000-000000000006'::uuid,
  '0100 status before restore organization');
COMMIT;
SQL

workspace_one="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id FROM app_private.organization_creation_request_claims
  WHERE request_id = '10000000-0100-1000-8000-000000000001'::uuid" | tr -d '[:space:]')"
workspace_two="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id FROM app_private.organization_creation_request_claims
  WHERE request_id = '10000000-0100-1000-8000-000000000002'::uuid" | tr -d '[:space:]')"
workspace_three="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id FROM app_private.organization_creation_request_claims
  WHERE request_id = '10000000-0100-1000-8000-000000000003'::uuid" | tr -d '[:space:]')"
workspace_four="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id FROM app_private.organization_creation_request_claims
  WHERE request_id = '10000000-0100-1000-8000-000000000004'::uuid" | tr -d '[:space:]')"
workspace_five="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id FROM app_private.organization_creation_request_claims
  WHERE request_id = '10000000-0100-1000-8000-000000000005'::uuid" | tr -d '[:space:]')"
workspace_six="$(run_psql --tuples-only --no-align --command="
  SELECT organization_workspace_id FROM app_private.organization_creation_request_claims
  WHERE request_id = '10000000-0100-1000-8000-000000000006'::uuid" | tr -d '[:space:]')"

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.organization_memberships VALUES
    ('10000000-0100-2000-8000-000000000001', '${workspace_one}'::uuid,
      '${actor_two}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000002', '${workspace_two}'::uuid,
      '${actor_two}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000003', '${workspace_three}'::uuid,
      '${actor_two}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000004', '${workspace_four}'::uuid,
      '${actor_two}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000005', '${workspace_five}'::uuid,
      '${actor_two}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000006', '${workspace_six}'::uuid,
      '${actor_two}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000014', '${workspace_four}'::uuid,
      '${actor_three}'::uuid, transaction_timestamp(), NULL),
    ('10000000-0100-2000-8000-000000000015', '${workspace_five}'::uuid,
      '${actor_three}'::uuid, transaction_timestamp(), NULL);
  INSERT INTO app_data.organization_owner_assignments VALUES
    ('10000000-0100-3000-8000-000000000001',
      '10000000-0100-2000-8000-000000000001', transaction_timestamp(), NULL),
    ('10000000-0100-3000-8000-000000000002',
      '10000000-0100-2000-8000-000000000002', transaction_timestamp(), NULL),
    ('10000000-0100-3000-8000-000000000003',
      '10000000-0100-2000-8000-000000000003', transaction_timestamp(), NULL),
    ('10000000-0100-3000-8000-000000000004',
      '10000000-0100-2000-8000-000000000004', transaction_timestamp(), NULL),
    ('10000000-0100-3000-8000-000000000005',
      '10000000-0100-2000-8000-000000000005', transaction_timestamp(), NULL),
    ('10000000-0100-3000-8000-000000000006',
      '10000000-0100-2000-8000-000000000006', transaction_timestamp(), NULL);
  COMMIT;" >/dev/null

echo '验证同 request 并发只写一套删除事实并精确重放。'
same_first="${temporary_directory}/same-first.out"
same_second="${temporary_directory}/same-second.out"
same_ready='organization-deletion-concurrency:ready:same'
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  BEGIN;
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${same_request}'::uuid, '${workspace_one}'::uuid);
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${same_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${same_first}" 2>&1 &
same_first_pid=$!; child_pids+=("${same_first_pid}")
wait_for_ready "${same_ready}" "${same_first_pid}" "${same_first}"
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${same_request}'::uuid, '${workspace_one}'::uuid)" \
  >"${same_second}" 2>&1 &
same_second_pid=$!; child_pids+=("${same_second_pid}")
wait_for_lock "organization-deletion-request:${same_request}" "${same_second_pid}" "${same_second}"
same_first_status=0; same_second_status=0
wait "${same_first_pid}" || same_first_status=$?
wait "${same_second_pid}" || same_second_status=$?
if [[ "${same_first_status}" -ne 0 || "${same_second_status}" -ne 0 ]]; then
  echo '同 request 并发会话失败。' >&2
  sed -n '1,100p' "${same_first}" >&2
  sed -n '1,100p' "${same_second}" >&2
  exit 1
fi
first_receipt="$(awk '/^organization-deletion-request:v1\|/ {print; exit}' "${same_first}")"
second_receipt="$(awk '/^organization-deletion-request:v1\|/ {print; exit}' "${same_second}")"
if [[ -z "${first_receipt}" || "${first_receipt}" != "${second_receipt}" ]]; then
  echo '同 request 并发没有返回相同的五字段回执。' >&2
  exit 1
fi
same_counts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT (SELECT count(*) FROM app_private.organization_deletion_request_claims
    WHERE request_id = '${same_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_audit_events
    WHERE request_id = '${same_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_current
    WHERE organization_workspace_id = '${workspace_one}'::uuid
      AND deletion_request_id = '${same_request}'::uuid)" | tr -d '[:space:]')"
[[ "${same_counts}" == '1|1|1' ]] || { echo "同 request 事实数错误：${same_counts}" >&2; exit 1; }

echo '验证不同 request 经 governance 锁串行，后到者不能替换 attempt。'
different_first="${temporary_directory}/different-first.out"
different_second="${temporary_directory}/different-second.out"
different_ready='organization-deletion-concurrency:ready:different'
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  BEGIN;
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${other_first_request}'::uuid, '${workspace_two}'::uuid);
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${different_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${different_first}" 2>&1 &
different_first_pid=$!; child_pids+=("${different_first_pid}")
wait_for_ready "${different_ready}" "${different_first_pid}" "${different_first}"
run_psql --set=VERBOSITY=verbose --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_two}'::uuid, '${other_request}'::uuid, '${workspace_two}'::uuid)" \
  >"${different_second}" 2>&1 &
different_second_pid=$!; child_pids+=("${different_second_pid}")
wait_for_lock "organization-governance:${workspace_two}" \
  "${different_second_pid}" "${different_second}"
if ! wait "${different_first_pid}"; then
  echo '不同 request 首次申请失败。' >&2
  sed -n '1,100p' "${different_first}" >&2
  exit 1
fi
if wait "${different_second_pid}"; then
  echo 'pending 组织接受了第二 request。' >&2
  exit 1
fi
assert_failure "${different_second}" '22023' 'organization deletion idempotency conflict'
different_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.organization_deletion_request_claims
  WHERE request_id = '${other_request}'::uuid" | tr -d '[:space:]')"
[[ "${different_count}" == 0 ]] || { echo '不同 request 写入了 claim。' >&2; exit 1; }

echo '验证同 restore request 并发只恢复一次。'
restore_first="${temporary_directory}/restore-first.out"
restore_second="${temporary_directory}/restore-second.out"
restore_ready='organization-deletion-concurrency:ready:restore'
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  BEGIN;
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_two}'::uuid, '${restore_request}'::uuid,
    '${workspace_one}'::uuid, '${same_request}'::uuid);
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${restore_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${restore_first}" 2>&1 &
restore_first_pid=$!; child_pids+=("${restore_first_pid}")
wait_for_ready "${restore_ready}" "${restore_first_pid}" "${restore_first}"
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_two}'::uuid, '${restore_request}'::uuid,
    '${workspace_one}'::uuid, '${same_request}'::uuid)" \
  >"${restore_second}" 2>&1 &
restore_second_pid=$!; child_pids+=("${restore_second_pid}")
wait_for_lock "organization-deletion-restore-request:${restore_request}" \
  "${restore_second_pid}" "${restore_second}"
restore_first_status=0; restore_second_status=0
wait "${restore_first_pid}" || restore_first_status=$?
wait "${restore_second_pid}" || restore_second_status=$?
if [[ "${restore_first_status}" -ne 0 || "${restore_second_status}" -ne 0 ]]; then
  echo '同 restore request 并发会话失败。' >&2
  sed -n '1,100p' "${restore_first}" >&2
  sed -n '1,100p' "${restore_second}" >&2
  exit 1
fi
first_restore="$(awk '/^organization-deletion-restore:v1\|/ {print; exit}' "${restore_first}")"
second_restore="$(awk '/^organization-deletion-restore:v1\|/ {print; exit}' "${restore_second}")"
if [[ -z "${first_restore}" || "${first_restore}" != "${second_restore}" ]]; then
  echo '同 restore request 并发没有返回相同的四字段回执。' >&2
  exit 1
fi

echo '验证账号状态在 actor 行锁等待后重新检查。'
status_holder="${temporary_directory}/status-holder.out"
status_writer="${temporary_directory}/status-writer.out"
status_ready='organization-deletion-concurrency:ready:status'
run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.app_users SET status = 'deletion_pending'
    WHERE app_user_id = '${actor_one}'::uuid;
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${status_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${status_holder}" 2>&1 &
status_holder_pid=$!; child_pids+=("${status_holder_pid}")
wait_for_ready "${status_ready}" "${status_holder_pid}" "${status_holder}"
run_psql --set=VERBOSITY=verbose --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${status_request}'::uuid, '${workspace_three}'::uuid)" \
  >"${status_writer}" 2>&1 &
status_writer_pid=$!; child_pids+=("${status_writer_pid}")
wait_for_actor_lock "${status_writer_pid}" "${status_writer}"
wait "${status_holder_pid}"
if wait "${status_writer_pid}"; then
  echo '账号状态改变后，等待中的首次申请意外成功。' >&2
  exit 1
fi
assert_failure "${status_writer}" '42501' 'organization deletion forbidden'
status_counts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT (SELECT count(*) FROM app_private.organization_deletion_request_claims
    WHERE request_id = '${status_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_audit_events
    WHERE request_id = '${status_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_current
    WHERE organization_workspace_id = '${workspace_three}'::uuid),
    (SELECT count(*) FROM app_data.workspaces
    WHERE workspace_id = '${workspace_three}'::uuid AND deleted_at IS NULL)" \
  | tr -d '[:space:]')"
[[ "${status_counts}" == '0|0|0|1' ]] || {
  echo "账号状态竞态留下部分事实：${status_counts}" >&2
  exit 1
}
run_psql --quiet --command="
  UPDATE app_data.app_users SET status = 'active'
  WHERE app_user_id = '${actor_one}'::uuid" >/dev/null

echo '验证 owner 转让先提交时，等待中的删除申请重验 owner 资格。'
transfer_first="${temporary_directory}/transfer-first.out"
transfer_request="${temporary_directory}/transfer-request.out"
transfer_ready='organization-deletion-concurrency:ready:transfer'
transfer_one_request='10000000-0100-7000-8000-000000000001'
transfer_deletion_request='10000000-0100-4000-8000-000000000005'
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  BEGIN;
  SELECT * FROM app_private.transfer_organization_owner_v1(
    '${actor_one}'::uuid, '${transfer_one_request}'::uuid,
    '${workspace_four}'::uuid,
    '10000000-0100-2000-8000-000000000014'::uuid);
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${transfer_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${transfer_first}" 2>&1 &
transfer_first_pid=$!; child_pids+=("${transfer_first_pid}")
wait_for_ready "${transfer_ready}" "${transfer_first_pid}" "${transfer_first}"
run_psql --set=VERBOSITY=verbose --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${transfer_deletion_request}'::uuid,
    '${workspace_four}'::uuid)" >"${transfer_request}" 2>&1 &
transfer_request_pid=$!; child_pids+=("${transfer_request_pid}")
wait_for_actor_lock "${transfer_request_pid}" "${transfer_request}"
if ! wait "${transfer_first_pid}"; then
  echo 'owner 转让首次会话失败。' >&2
  sed -n '1,100p' "${transfer_first}" >&2
  exit 1
fi
if wait "${transfer_request_pid}"; then
  echo 'owner 转让后旧 owner 的删除申请意外成功。' >&2
  exit 1
fi
assert_failure "${transfer_request}" '42501' 'organization deletion forbidden'
transfer_counts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT (SELECT count(*) FROM app_private.organization_owner_transfer_request_claims
      WHERE request_id = '${transfer_one_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_request_claims
      WHERE request_id = '${transfer_deletion_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_current
      WHERE organization_workspace_id = '${workspace_four}'::uuid),
    (SELECT count(*) FROM app_data.workspaces
      WHERE workspace_id = '${workspace_four}'::uuid AND deleted_at IS NULL),
    (SELECT count(*) FROM app_data.organization_owner_assignments AS assignment
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE membership.organization_workspace_id = '${workspace_four}'::uuid
        AND membership.app_user_id = '${actor_three}'::uuid
        AND assignment.inactive_from_utc IS NULL)" | tr -d '[:space:]')"
[[ "${transfer_counts}" == '1|0|0|1|1' ]] || {
  echo "owner 转让与申请竞态留下错误事实：${transfer_counts}" >&2
  exit 1
}

echo '验证恢复先提交时，等待中的 owner 转让依据恢复后状态成功。'
restore_race_deletion='10000000-0100-4000-8000-000000000006'
restore_race_request='10000000-0100-5000-8000-000000000002'
transfer_two_request='10000000-0100-7000-8000-000000000002'
run_psql --quiet --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${restore_race_deletion}'::uuid,
    '${workspace_five}'::uuid)" >/dev/null
restore_race_first="${temporary_directory}/restore-race-first.out"
restore_race_transfer="${temporary_directory}/restore-race-transfer.out"
restore_race_ready='organization-deletion-concurrency:ready:restore-transfer'
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  BEGIN;
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_two}'::uuid, '${restore_race_request}'::uuid,
    '${workspace_five}'::uuid, '${restore_race_deletion}'::uuid);
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${restore_race_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${restore_race_first}" 2>&1 &
restore_race_first_pid=$!; child_pids+=("${restore_race_first_pid}")
wait_for_ready "${restore_race_ready}" "${restore_race_first_pid}" "${restore_race_first}"
run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  SELECT * FROM app_private.transfer_organization_owner_v1(
    '${actor_one}'::uuid, '${transfer_two_request}'::uuid,
    '${workspace_five}'::uuid,
    '10000000-0100-2000-8000-000000000015'::uuid)" \
  >"${restore_race_transfer}" 2>&1 &
restore_race_transfer_pid=$!; child_pids+=("${restore_race_transfer_pid}")
wait_for_lock "organization-governance:${workspace_five}" \
  "${restore_race_transfer_pid}" "${restore_race_transfer}"
restore_race_first_status=0; restore_race_transfer_status=0
wait "${restore_race_first_pid}" || restore_race_first_status=$?
wait "${restore_race_transfer_pid}" || restore_race_transfer_status=$?
if [[ "${restore_race_first_status}" -ne 0 || "${restore_race_transfer_status}" -ne 0 ]]; then
  echo '恢复与 owner 转让竞态会话失败。' >&2
  sed -n '1,100p' "${restore_race_first}" >&2
  sed -n '1,100p' "${restore_race_transfer}" >&2
  exit 1
fi
restore_transfer_counts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT (SELECT count(*) FROM app_private.organization_deletion_current
      WHERE organization_workspace_id = '${workspace_five}'::uuid
        AND status = 'restored'),
    (SELECT count(*) FROM app_data.workspaces
      WHERE workspace_id = '${workspace_five}'::uuid AND deleted_at IS NULL),
    (SELECT count(*) FROM app_private.organization_deletion_restore_claims
      WHERE request_id = '${restore_race_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = '${workspace_five}'::uuid),
    (SELECT count(*) FROM app_private.organization_owner_transfer_request_claims
      WHERE request_id = '${transfer_two_request}'::uuid),
    (SELECT count(*) FROM app_data.organization_owner_assignments AS assignment
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE membership.organization_workspace_id = '${workspace_five}'::uuid
        AND membership.app_user_id = '${actor_three}'::uuid
        AND assignment.inactive_from_utc IS NULL)" | tr -d '[:space:]')"
[[ "${restore_transfer_counts}" == '1|1|1|2|1|1' ]] || {
  echo "恢复与 owner 转让竞态留下错误事实：${restore_transfer_counts}" >&2
  exit 1
}

echo '验证账号状态先提交时，等待中的恢复拒绝且保留删除期。'
status_restore_deletion='10000000-0100-4000-8000-000000000007'
status_restore_request='10000000-0100-5000-8000-000000000003'
run_psql --quiet --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, '${status_restore_deletion}'::uuid,
    '${workspace_six}'::uuid)" >/dev/null
status_restore_holder="${temporary_directory}/status-restore-holder.out"
status_restore_writer="${temporary_directory}/status-restore-writer.out"
status_restore_ready='organization-deletion-concurrency:ready:status-restore'
run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.app_users SET status = 'deletion_pending'
    WHERE app_user_id = '${actor_two}'::uuid;
  SELECT 'ready' WHERE pg_advisory_lock(hashtextextended('${status_restore_ready}', 0)) IS NULL;
  SELECT pg_sleep(2);
  COMMIT;" >"${status_restore_holder}" 2>&1 &
status_restore_holder_pid=$!; child_pids+=("${status_restore_holder_pid}")
wait_for_ready "${status_restore_ready}" "${status_restore_holder_pid}" \
  "${status_restore_holder}"
run_psql --set=VERBOSITY=verbose --command="
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_two}'::uuid, '${status_restore_request}'::uuid,
    '${workspace_six}'::uuid, '${status_restore_deletion}'::uuid)" \
  >"${status_restore_writer}" 2>&1 &
status_restore_writer_pid=$!; child_pids+=("${status_restore_writer_pid}")
wait_for_actor_lock "${status_restore_writer_pid}" "${status_restore_writer}"
if ! wait "${status_restore_holder_pid}"; then
  echo '恢复前账号状态更新失败。' >&2
  sed -n '1,100p' "${status_restore_holder}" >&2
  exit 1
fi
if wait "${status_restore_writer_pid}"; then
  echo '账号状态变化后恢复意外成功。' >&2
  exit 1
fi
assert_failure "${status_restore_writer}" '42501' 'organization restoration forbidden'
status_restore_counts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT (SELECT count(*) FROM app_private.organization_deletion_current
      WHERE organization_workspace_id = '${workspace_six}'::uuid
        AND status = 'deletion_pending'),
    (SELECT count(*) FROM app_data.workspaces
      WHERE workspace_id = '${workspace_six}'::uuid AND deleted_at IS NOT NULL),
    (SELECT count(*) FROM app_private.organization_deletion_restore_claims
      WHERE request_id = '${status_restore_request}'::uuid),
    (SELECT count(*) FROM app_private.organization_deletion_audit_events
      WHERE organization_workspace_id = '${workspace_six}'::uuid)" | tr -d '[:space:]')"
[[ "${status_restore_counts}" == '1|1|0|1' ]] || {
  echo "账号状态与恢复竞态留下错误事实：${status_restore_counts}" >&2
  exit 1
}

echo '验证隔离级别与未知组织的固定拒绝。'
isolation_request="${temporary_directory}/isolation-request.out"
isolation_restore="${temporary_directory}/isolation-restore.out"
unknown_workspace="${temporary_directory}/unknown-workspace.out"
run_psql --set=VERBOSITY=verbose --command="
  BEGIN ISOLATION LEVEL REPEATABLE READ;
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, gen_random_uuid(), '${workspace_three}'::uuid)" \
  >"${isolation_request}" 2>&1 && {
    echo '非 READ COMMITTED 删除申请意外成功。' >&2; exit 1;
  }
assert_failure "${isolation_request}" '55000' 'organization deletion unavailable'
run_psql --set=VERBOSITY=verbose --command="
  BEGIN ISOLATION LEVEL REPEATABLE READ;
  SELECT * FROM app_private.restore_organization_v1(
    '${actor_one}'::uuid, gen_random_uuid(), '${workspace_six}'::uuid,
    '${status_restore_deletion}'::uuid)" >"${isolation_restore}" 2>&1 && {
    echo '非 READ COMMITTED 恢复意外成功。' >&2; exit 1;
  }
assert_failure "${isolation_restore}" '55000' 'organization restoration unavailable'
run_psql --set=VERBOSITY=verbose --command="
  SELECT * FROM app_private.request_organization_deletion_v1(
    '${actor_one}'::uuid, gen_random_uuid(),
    '10000000-0100-4000-8000-000000009999'::uuid)" \
  >"${unknown_workspace}" 2>&1 && {
    echo '未知 workspace 删除申请意外成功。' >&2; exit 1;
  }
assert_failure "${unknown_workspace}" '42501' 'organization deletion forbidden'

echo '0100 organization deletion/recovery concurrency passed.'
