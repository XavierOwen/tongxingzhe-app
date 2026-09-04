#!/usr/bin/env bash

set -euo pipefail

# Independent sessions exercise the 0086 transfer request, actor/target,
# governance and membership lock order.  Synthetic rows are intentionally
# committed so the Docker runner can include them in its dump/restore checks.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --set=VERBOSITY=verbose
)

run_psql() {
  "${psql_base[@]}" "$@"
}

temporary_directory="$(mktemp -d)"
child_pids=()

cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock_holder() {
  local lock_name="$1"
  local holder_pid="$2"
  local holder_output="$3"
  local probe

  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      WITH lock_probe AS (
        SELECT pg_try_advisory_lock(
          hashtextextended('${lock_name}', 0)
        ) AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${lock_name}', 0)
        )
        ELSE true
      END
      FROM lock_probe;
    " | tr -d '[:space:]')"
    if [[ "${probe}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then
      echo "并发持锁会话过早退出：${lock_name}" >&2
      sed -n '1,160p' "${holder_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  kill "${holder_pid}" >/dev/null 2>&1 || true
  wait "${holder_pid}" >/dev/null 2>&1 || true
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_advisory_waiter() {
  local lock_name="$1"
  local waiter_pid="$2"
  local waiter_output="$3"
  local waiting

  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32)
            & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0)
            & 4294967295)::bigint AS objid,
          (SELECT oid FROM pg_database
            WHERE datname = current_database()) AS database_id
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        CROSS JOIN lock_key
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
          AND lock_row.database = lock_key.database_id
          AND lock_row.classid::bigint = lock_key.classid
          AND lock_row.objid::bigint = lock_key.objid
          AND lock_row.objsubid = 1
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo "并发等待会话过早退出：${lock_name}" >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  kill "${waiter_pid}" >/dev/null 2>&1 || true
  wait "${waiter_pid}" >/dev/null 2>&1 || true
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

wait_for_app_user_waiter() {
  local waiter_pid="$1"
  local waiter_output="$2"
  local waiting

  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        WHERE NOT lock_row.granted
          AND (
            lock_row.locktype = 'transactionid'
            OR (
              lock_row.locktype = 'tuple'
              AND lock_row.relation = 'app_data.app_users'::regclass
            )
          )
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo 'app_users 状态竞态会话过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  kill "${waiter_pid}" >/dev/null 2>&1 || true
  wait "${waiter_pid}" >/dev/null 2>&1 || true
  echo '没有观察到 app_users 行锁等待。' >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

result_from() {
  local output_file="$1"
  awk '/^organization-owner-transfer:v1\|/ { print; exit }' "${output_file}"
}

assert_result_row() {
  local result_row="$1"
  local label="$2"
  local contract_id
  local workspace_id
  local previous_owner_assignment_id
  local owner_assignment_id
  local effective_at_utc

  if [[ -z "${result_row}" ]]; then
    echo "${label} 没有返回 owner-transfer result row。" >&2
    exit 1
  fi

  IFS='|' read -r contract_id workspace_id previous_owner_assignment_id \
    owner_assignment_id effective_at_utc <<<"${result_row}"
  if [[ "${contract_id}" != 'organization-owner-transfer:v1' \
    || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
    || ! "${previous_owner_assignment_id}" =~ ^[0-9a-f-]{36}$ \
    || ! "${owner_assignment_id}" =~ ^[0-9a-f-]{36}$ \
    || -z "${effective_at_utc}" ]]
  then
    echo "${label} 返回列或值不符合五字段合同：${result_row}" >&2
    exit 1
  fi
}

assert_failure() {
  local output_file="$1"
  local label="$2"
  local expected_sqlstate="$3"
  local expected_message="$4"

  if ! grep -q "${expected_sqlstate}" "${output_file}" \
    || ! grep -q "${expected_message}" "${output_file}"; then
    echo "${label} 没有返回预期的固定数据库失败。" >&2
    sed -n '1,160p' "${output_file}" >&2
    exit 1
  fi
}

replay_workspace_id='86000000-0086-4000-8000-000000000001'
replay_actor_id='86000000-0086-0000-8000-000000000001'
replay_target_id='86000000-0086-0000-8000-000000000002'
replay_actor_membership_id='86000000-0086-3000-8000-000000000001'
replay_target_membership_id='86000000-0086-3000-8000-000000000002'
replay_owner_assignment_id='86000000-0086-5000-8000-000000000001'
replay_request_id='86000000-0086-6000-8000-000000000001'

drift_workspace_id='86000000-0086-4000-8000-000000000002'
drift_actor_id='86000000-0086-0000-8000-000000000003'
drift_target_id='86000000-0086-0000-8000-000000000004'
drift_other_target_id='86000000-0086-0000-8000-000000000005'
drift_actor_membership_id='86000000-0086-3000-8000-000000000003'
drift_target_membership_id='86000000-0086-3000-8000-000000000004'
drift_other_target_membership_id='86000000-0086-3000-8000-000000000005'
drift_owner_assignment_id='86000000-0086-5000-8000-000000000002'
drift_request_id='86000000-0086-6000-8000-000000000002'

governance_workspace_id='86000000-0086-4000-8000-000000000003'
governance_actor_one_id='86000000-0086-0000-8000-000000000006'
governance_target_one_id='86000000-0086-0000-8000-000000000007'
governance_actor_two_id='86000000-0086-0000-8000-000000000008'
governance_target_two_id='86000000-0086-0000-8000-000000000009'
governance_actor_one_membership_id='86000000-0086-3000-8000-000000000006'
governance_target_one_membership_id='86000000-0086-3000-8000-000000000007'
governance_actor_two_membership_id='86000000-0086-3000-8000-000000000008'
governance_target_two_membership_id='86000000-0086-3000-8000-000000000009'
governance_owner_one_assignment_id='86000000-0086-5000-8000-000000000003'
governance_owner_two_assignment_id='86000000-0086-5000-8000-000000000004'
governance_request_one_id='86000000-0086-6000-8000-000000000003'
governance_request_two_id='86000000-0086-6000-8000-000000000004'

race_workspace_id='86000000-0086-4000-8000-000000000004'
race_actor_id='86000000-0086-0000-8000-000000000010'
race_target_id='86000000-0086-0000-8000-000000000011'
race_actor_membership_id='86000000-0086-3000-8000-000000000010'
race_target_membership_id='86000000-0086-3000-8000-000000000011'
race_owner_assignment_id='86000000-0086-5000-8000-000000000005'
race_request_id='86000000-0086-6000-8000-000000000005'

replay_request_lock="organization-owner-transfer-request:${replay_request_id}"
drift_request_lock="organization-owner-transfer-request:${drift_request_id}"
governance_lock="organization-governance:${governance_workspace_id}"
race_request_lock="organization-owner-transfer-request:${race_request_id}"
replay_ready_lock='86-owner-transfer-replay-ready'
drift_ready_lock='86-owner-transfer-drift-ready'
governance_ready_lock='86-owner-transfer-governance-ready'
race_ready_lock='86-owner-transfer-race-ready'

echo '建立 0086 owner-transfer synthetic 并发基线。'
run_psql --quiet --command="
  BEGIN;
  SET TIME ZONE 'UTC';
  SET CONSTRAINTS ALL DEFERRED;

  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('${replay_actor_id}'::uuid, 'active'),
    ('${replay_target_id}'::uuid, 'active'),
    ('${drift_actor_id}'::uuid, 'active'),
    ('${drift_target_id}'::uuid, 'active'),
    ('${drift_other_target_id}'::uuid, 'active'),
    ('${governance_actor_one_id}'::uuid, 'active'),
    ('${governance_target_one_id}'::uuid, 'active'),
    ('${governance_actor_two_id}'::uuid, 'active'),
    ('${governance_target_two_id}'::uuid, 'active'),
    ('${race_actor_id}'::uuid, 'active'),
    ('${race_target_id}'::uuid, 'active');

  INSERT INTO app_data.workspaces (
    workspace_id,
    workspace_kind,
    display_name,
    personal_owner_app_user_id,
    created_at
  )
  VALUES
    (
      '${replay_workspace_id}'::uuid,
      'organization',
      '0086 replay organization',
      NULL,
      transaction_timestamp()
    ),
    (
      '${drift_workspace_id}'::uuid,
      'organization',
      '0086 drift organization',
      NULL,
      transaction_timestamp()
    ),
    (
      '${governance_workspace_id}'::uuid,
      'organization',
      '0086 governance organization',
      NULL,
      transaction_timestamp()
    ),
    (
      '${race_workspace_id}'::uuid,
      'organization',
      '0086 status-race organization',
      NULL,
      transaction_timestamp()
    );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  )
  VALUES
    (
      '${replay_actor_membership_id}'::uuid,
      '${replay_workspace_id}'::uuid,
      '${replay_actor_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${replay_target_membership_id}'::uuid,
      '${replay_workspace_id}'::uuid,
      '${replay_target_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${drift_actor_membership_id}'::uuid,
      '${drift_workspace_id}'::uuid,
      '${drift_actor_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${drift_target_membership_id}'::uuid,
      '${drift_workspace_id}'::uuid,
      '${drift_target_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${drift_other_target_membership_id}'::uuid,
      '${drift_workspace_id}'::uuid,
      '${drift_other_target_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${governance_actor_one_membership_id}'::uuid,
      '${governance_workspace_id}'::uuid,
      '${governance_actor_one_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${governance_target_one_membership_id}'::uuid,
      '${governance_workspace_id}'::uuid,
      '${governance_target_one_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${governance_actor_two_membership_id}'::uuid,
      '${governance_workspace_id}'::uuid,
      '${governance_actor_two_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${governance_target_two_membership_id}'::uuid,
      '${governance_workspace_id}'::uuid,
      '${governance_target_two_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${race_actor_membership_id}'::uuid,
      '${race_workspace_id}'::uuid,
      '${race_actor_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${race_target_membership_id}'::uuid,
      '${race_workspace_id}'::uuid,
      '${race_target_id}'::uuid,
      transaction_timestamp(),
      NULL
    );

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  )
  VALUES
    (
      '${replay_owner_assignment_id}'::uuid,
      '${replay_actor_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${drift_owner_assignment_id}'::uuid,
      '${drift_actor_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${governance_owner_one_assignment_id}'::uuid,
      '${governance_actor_one_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${governance_owner_two_assignment_id}'::uuid,
      '${governance_actor_two_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${race_owner_assignment_id}'::uuid,
      '${race_actor_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    );
  COMMIT;
"

echo '验证同 request 并发只产生一套事实，并精确重放五字段 receipt。'
replay_first_output="${temporary_directory}/replay-first.out"
replay_second_output="${temporary_directory}/replay-second.out"
run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.transfer_organization_owner_v1(
      '${replay_actor_id}'::uuid,
      '${replay_request_id}'::uuid,
      '${replay_workspace_id}'::uuid,
      '${replay_target_membership_id}'::uuid
    );
    SELECT 'ready' WHERE pg_advisory_lock(
      hashtextextended('${replay_ready_lock}', 0)
    ) IS NULL;
    SELECT pg_sleep(2);
    COMMIT;
  " >"${replay_first_output}" 2>&1 &
replay_first_pid=$!
child_pids+=("${replay_first_pid}")
wait_for_lock_holder "${replay_ready_lock}" "${replay_first_pid}" \
  "${replay_first_output}"

run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.transfer_organization_owner_v1(
      '${replay_actor_id}'::uuid,
      '${replay_request_id}'::uuid,
      '${replay_workspace_id}'::uuid,
      '${replay_target_membership_id}'::uuid
    );
    COMMIT;
  " >"${replay_second_output}" 2>&1 &
replay_second_pid=$!
child_pids+=("${replay_second_pid}")
wait_for_advisory_waiter "${replay_request_lock}" "${replay_second_pid}" \
  "${replay_second_output}"

replay_first_status=0
replay_second_status=0
wait "${replay_first_pid}" || replay_first_status=$?
wait "${replay_second_pid}" || replay_second_status=$?
if [[ "${replay_first_status}" -ne 0 || "${replay_second_status}" -ne 0 ]]; then
  echo "同 request 并发 transfer 失败：first=${replay_first_status}, second=${replay_second_status}" >&2
  sed -n '1,160p' "${replay_first_output}" >&2
  sed -n '1,160p' "${replay_second_output}" >&2
  exit 1
fi

replay_first_result="$(result_from "${replay_first_output}")"
replay_second_result="$(result_from "${replay_second_output}")"
assert_result_row "${replay_first_result}" '同 request 首次 transfer'
assert_result_row "${replay_second_result}" '同 request exact replay'
if [[ "${replay_first_result}" != "${replay_second_result}" ]]; then
  echo '同 request exact replay 没有返回完全相同的五字段 receipt。' >&2
  echo "first=${replay_first_result}" >&2
  echo "second=${replay_second_result}" >&2
  exit 1
fi

replay_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_request_claims
       WHERE request_id = '${replay_request_id}'::uuid),
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_audit_events
       WHERE request_id = '${replay_request_id}'::uuid),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       WHERE membership_row.organization_workspace_id =
         '${replay_workspace_id}'::uuid),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       WHERE membership_row.organization_workspace_id =
         '${replay_workspace_id}'::uuid
         AND owner_row.inactive_from_utc IS NULL);
  " | tr -d '[:space:]')"
if [[ "${replay_fact_counts}" != '1|1|2|1' ]]; then
  echo "同 request replay 事实计数错误：${replay_fact_counts}" >&2
  exit 1
fi

echo '验证同 request 的 target drift 在 request lock 释放后固定 conflict。'
drift_first_output="${temporary_directory}/drift-first.out"
drift_second_output="${temporary_directory}/drift-second.out"
run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.transfer_organization_owner_v1(
      '${drift_actor_id}'::uuid,
      '${drift_request_id}'::uuid,
      '${drift_workspace_id}'::uuid,
      '${drift_target_membership_id}'::uuid
    );
    SELECT 'ready' WHERE pg_advisory_lock(
      hashtextextended('${drift_ready_lock}', 0)
    ) IS NULL;
    SELECT pg_sleep(2);
    COMMIT;
  " >"${drift_first_output}" 2>&1 &
drift_first_pid=$!
child_pids+=("${drift_first_pid}")
wait_for_lock_holder "${drift_ready_lock}" "${drift_first_pid}" \
  "${drift_first_output}"

run_psql --quiet --set=VERBOSITY=verbose --command="
    BEGIN;
    SELECT * FROM app_private.transfer_organization_owner_v1(
      '${drift_actor_id}'::uuid,
      '${drift_request_id}'::uuid,
      '${drift_workspace_id}'::uuid,
      '${drift_other_target_membership_id}'::uuid
    );
    COMMIT;
  " >"${drift_second_output}" 2>&1 &
drift_second_pid=$!
child_pids+=("${drift_second_pid}")
wait_for_advisory_waiter "${drift_request_lock}" "${drift_second_pid}" \
  "${drift_second_output}"

drift_first_status=0
drift_second_status=0
wait "${drift_first_pid}" || drift_first_status=$?
wait "${drift_second_pid}" || drift_second_status=$?
if [[ "${drift_first_status}" -ne 0 || "${drift_second_status}" -eq 0 ]]; then
  echo "target drift 并发结果错误：first=${drift_first_status}, second=${drift_second_status}" >&2
  sed -n '1,160p' "${drift_first_output}" >&2
  sed -n '1,160p' "${drift_second_output}" >&2
  exit 1
fi
assert_failure "${drift_second_output}" '同 request target drift' \
  '22023' 'organization owner transfer idempotency conflict'

drift_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_request_claims
       WHERE request_id = '${drift_request_id}'::uuid),
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_audit_events
       WHERE request_id = '${drift_request_id}'::uuid),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       WHERE membership_row.organization_workspace_id =
         '${drift_workspace_id}'::uuid);
  " | tr -d '[:space:]')"
if [[ "${drift_fact_counts}" != '1|1|2' ]]; then
  echo "target drift 修改了已提交事实：${drift_fact_counts}" >&2
  exit 1
fi

echo '验证同组织不同 request 只在 governance lock 上串行，两个 current owners 都完成 handoff。'
governance_first_output="${temporary_directory}/governance-first.out"
governance_second_output="${temporary_directory}/governance-second.out"
run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.transfer_organization_owner_v1(
      '${governance_actor_one_id}'::uuid,
      '${governance_request_one_id}'::uuid,
      '${governance_workspace_id}'::uuid,
      '${governance_target_one_membership_id}'::uuid
    );
    SELECT 'ready' WHERE pg_advisory_lock(
      hashtextextended('${governance_ready_lock}', 0)
    ) IS NULL;
    SELECT pg_sleep(2);
    COMMIT;
  " >"${governance_first_output}" 2>&1 &
governance_first_pid=$!
child_pids+=("${governance_first_pid}")
wait_for_lock_holder "${governance_ready_lock}" "${governance_first_pid}" \
  "${governance_first_output}"

run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.transfer_organization_owner_v1(
      '${governance_actor_two_id}'::uuid,
      '${governance_request_two_id}'::uuid,
      '${governance_workspace_id}'::uuid,
      '${governance_target_two_membership_id}'::uuid
    );
    COMMIT;
  " >"${governance_second_output}" 2>&1 &
governance_second_pid=$!
child_pids+=("${governance_second_pid}")
wait_for_advisory_waiter "${governance_lock}" "${governance_second_pid}" \
  "${governance_second_output}"

governance_first_status=0
governance_second_status=0
wait "${governance_first_pid}" || governance_first_status=$?
wait "${governance_second_pid}" || governance_second_status=$?
if [[ "${governance_first_status}" -ne 0 \
  || "${governance_second_status}" -ne 0 ]]; then
  echo "同组织不同 request transfer 失败：first=${governance_first_status}, second=${governance_second_status}" >&2
  sed -n '1,160p' "${governance_first_output}" >&2
  sed -n '1,160p' "${governance_second_output}" >&2
  exit 1
fi

governance_first_result="$(result_from "${governance_first_output}")"
governance_second_result="$(result_from "${governance_second_output}")"
assert_result_row "${governance_first_result}" 'governance 第一请求'
assert_result_row "${governance_second_result}" 'governance 第二请求'
if [[ "${governance_first_result}" == "${governance_second_result}" ]]; then
  echo '同组织不同 request 意外返回了同一 transfer receipt。' >&2
  exit 1
fi

governance_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_request_claims
       WHERE request_id IN (
         '${governance_request_one_id}'::uuid,
         '${governance_request_two_id}'::uuid
       )),
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_audit_events
       WHERE request_id IN (
         '${governance_request_one_id}'::uuid,
         '${governance_request_two_id}'::uuid
       )),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       WHERE membership_row.organization_workspace_id =
         '${governance_workspace_id}'::uuid),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       WHERE membership_row.organization_workspace_id =
         '${governance_workspace_id}'::uuid
         AND owner_row.inactive_from_utc IS NULL),
      (SELECT string_agg(app_user.app_user_id::text, '|' ORDER BY app_user.app_user_id)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       JOIN app_data.app_users AS app_user
         ON app_user.app_user_id = membership_row.app_user_id
       WHERE membership_row.organization_workspace_id =
         '${governance_workspace_id}'::uuid
         AND owner_row.inactive_from_utc IS NULL);
  " | tr -d '[:space:]')"
expected_governance_owners="${governance_target_one_id}|${governance_target_two_id}"
if [[ "${governance_fact_counts}" != "2|2|4|2|${expected_governance_owners}" ]]; then
  echo "governance 串行事实计数错误：${governance_fact_counts}" >&2
  exit 1
fi

echo '验证 target app_user 状态先变为 deletion_pending 时，transfer 锁后重读并失败关闭。'
race_status_output="${temporary_directory}/race-status.out"
race_transfer_output="${temporary_directory}/race-transfer.out"
run_psql --quiet --command="
  BEGIN;
  SET TIME ZONE 'UTC';
  SELECT app_user_id
  FROM app_data.app_users
  WHERE app_user_id = '${race_target_id}'::uuid
  FOR UPDATE;
  SELECT 'ready' WHERE pg_advisory_lock(
    hashtextextended('${race_ready_lock}', 0)
  ) IS NULL;
  SELECT pg_sleep(2);
  UPDATE app_data.app_users
  SET status = 'deletion_pending'
  WHERE app_user_id = '${race_target_id}'::uuid;
  COMMIT;
" >"${race_status_output}" 2>&1 &
race_status_pid=$!
child_pids+=("${race_status_pid}")
wait_for_lock_holder "${race_ready_lock}" "${race_status_pid}" \
  "${race_status_output}"

run_psql --quiet --set=VERBOSITY=verbose --command="
  BEGIN;
  SELECT * FROM app_private.transfer_organization_owner_v1(
    '${race_actor_id}'::uuid,
    '${race_request_id}'::uuid,
    '${race_workspace_id}'::uuid,
    '${race_target_membership_id}'::uuid
  );
  COMMIT;
" >"${race_transfer_output}" 2>&1 &
race_transfer_pid=$!
child_pids+=("${race_transfer_pid}")
wait_for_app_user_waiter "${race_transfer_pid}" "${race_transfer_output}"

race_status_status=0
race_transfer_status=0
wait "${race_status_pid}" || race_status_status=$?
wait "${race_transfer_pid}" || race_transfer_status=$?
if [[ "${race_status_status}" -ne 0 || "${race_transfer_status}" -eq 0 ]]; then
  echo "target 状态竞态结果错误：status=${race_status_status}, transfer=${race_transfer_status}" >&2
  sed -n '1,160p' "${race_status_output}" >&2
  sed -n '1,160p' "${race_transfer_output}" >&2
  exit 1
fi
assert_failure "${race_transfer_output}" 'target deletion_pending 竞态' \
  '42501' 'organization owner transfer forbidden'

race_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT status
       FROM app_data.app_users
       WHERE app_user_id = '${race_target_id}'::uuid),
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_request_claims
       WHERE request_id = '${race_request_id}'::uuid),
      (SELECT count(*)
       FROM app_private.organization_owner_transfer_audit_events
       WHERE request_id = '${race_request_id}'::uuid),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       JOIN app_data.organization_memberships AS membership_row
         ON membership_row.organization_membership_id =
           owner_row.organization_membership_id
       WHERE membership_row.organization_workspace_id =
         '${race_workspace_id}'::uuid),
      (SELECT count(*)
       FROM app_data.organization_owner_assignments AS owner_row
       WHERE owner_row.organization_owner_assignment_id =
         '${race_owner_assignment_id}'::uuid
         AND owner_row.inactive_from_utc IS NULL);
  " | tr -d '[:space:]')"
if [[ "${race_fact_counts}" != 'deletion_pending|0|0|1|1' ]]; then
  echo "target 状态竞态留下错误事实：${race_fact_counts}" >&2
  exit 1
fi

echo '0086 organization owner transfer concurrency checks passed; synthetic rows committed for dump/restore.'
