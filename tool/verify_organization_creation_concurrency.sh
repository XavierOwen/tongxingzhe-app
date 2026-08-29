#!/usr/bin/env bash

set -euo pipefail

# Independent sessions exercise the 0084 request and actor locks.  The
# synthetic rows are intentionally committed: the Docker runner dumps this
# database and repeats the assertions after restore.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"

run_psql() {
  "${psql_command}" "${DATABASE_URL}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    "$@"
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
      echo '并发等待会话过早退出。' >&2
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

wait_for_actor_waiter() {
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
              AND lock_row.relation =
                'app_data.app_users'::regclass
            )
          )
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo '同 actor 并发会话过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  kill "${waiter_pid}" >/dev/null 2>&1 || true
  wait "${waiter_pid}" >/dev/null 2>&1 || true
  echo '没有观察到同 actor 的 app_users 行锁等待。' >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

result_from() {
  local output_file="$1"
  awk '/^organization-creation:v1\|/ { print; exit }' "${output_file}"
}

assert_result_row() {
  local result_row="$1"
  local label="$2"
  local contract_id
  local workspace_id
  local membership_id
  local owner_assignment_id
  local created_at_utc

  if [[ -z "${result_row}" ]]; then
    echo "${label} 没有返回 creation result row。" >&2
    exit 1
  fi

  IFS='|' read -r contract_id workspace_id membership_id \
    owner_assignment_id created_at_utc <<<"${result_row}"
  if [[ "${contract_id}" != 'organization-creation:v1' \
    || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
    || ! "${membership_id}" =~ ^[0-9a-f-]{36}$ \
    || ! "${owner_assignment_id}" =~ ^[0-9a-f-]{36}$ \
    || -z "${created_at_utc}" ]]
  then
    echo "${label} 返回列或值不符合五字段合同：${result_row}" >&2
    exit 1
  fi
}

expect_failure() {
  local label="$1"
  local expected_sqlstate="$2"
  local expected_message="$3"
  local statement="$4"
  local output_file="${temporary_directory}/${label}.out"
  local status=0

  run_psql --set=VERBOSITY=verbose --command="${statement}" \
    >"${output_file}" 2>&1 || status=$?
  if [[ "${status}" -eq 0 ]] \
    || ! grep -q "${expected_sqlstate}" "${output_file}" \
    || ! grep -q "${expected_message}" "${output_file}"
  then
    echo "${label} 没有返回预期的数据库失败。" >&2
    sed -n '1,160p' "${output_file}" >&2
    exit 1
  fi
}

actor_id='84000000-0084-4000-8000-000000000001'
same_request_id='84000000-0084-5000-8000-000000000001'
drift_request_id='84000000-0084-5000-8000-000000000002'
serial_request_one='84000000-0084-5000-8000-000000000011'
serial_request_two='84000000-0084-5000-8000-000000000012'

same_request_lock="organization-creation-request:${same_request_id}"
drift_request_lock="organization-creation-request:${drift_request_id}"
same_request_ready='organization-creation-concurrency:ready:same-request'
drift_request_ready='organization-creation-concurrency:ready:drift'
actor_ready='organization-creation-concurrency:ready:actor'

run_psql --quiet <<SQL
SET TIME ZONE 'UTC';
INSERT INTO app_data.app_users (app_user_id, status)
VALUES ('${actor_id}'::uuid, 'active');
SQL

echo '验证同 request、actor、canonical name 并发只提交一套事实。'
same_first_output="${temporary_directory}/same-first.out"
same_second_output="${temporary_directory}/same-second.out"
run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.create_organization_v1(
      '${actor_id}'::uuid,
      '${same_request_id}'::uuid,
      '84C same request organization'
    );
    SELECT 'ready' WHERE pg_advisory_lock(
      hashtextextended('${same_request_ready}', 0)
    ) IS NULL;
    SELECT pg_sleep(2);
    COMMIT;
  " >"${same_first_output}" 2>&1 &
same_first_pid=$!
child_pids+=("${same_first_pid}")
wait_for_lock_holder "${same_request_ready}" "${same_first_pid}" \
  "${same_first_output}"

run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.create_organization_v1(
      '${actor_id}'::uuid,
      '${same_request_id}'::uuid,
      '84C same request organization'
    );
    COMMIT;
  " >"${same_second_output}" 2>&1 &
same_second_pid=$!
child_pids+=("${same_second_pid}")
wait_for_advisory_waiter "${same_request_lock}" "${same_second_pid}" \
  "${same_second_output}"

same_first_status=0
same_second_status=0
wait "${same_first_pid}" || same_first_status=$?
wait "${same_second_pid}" || same_second_status=$?
if [[ "${same_first_status}" -ne 0 || "${same_second_status}" -ne 0 ]]; then
  echo "同 request 并发调用失败：first=${same_first_status}, second=${same_second_status}" >&2
  sed -n '1,160p' "${same_first_output}" >&2
  sed -n '1,160p' "${same_second_output}" >&2
  exit 1
fi

same_first_result="$(result_from "${same_first_output}")"
same_second_result="$(result_from "${same_second_output}")"
assert_result_row "${same_first_result}" '同 request 首次调用'
assert_result_row "${same_second_result}" '同 request 重放调用'
if [[ "${same_first_result}" != "${same_second_result}" ]]; then
  echo "同 request 并发没有返回完全相同的五字段结果。" >&2
  echo "first=${same_first_result}" >&2
  echo "second=${same_second_result}" >&2
  exit 1
fi

same_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*) FROM app_private.organization_creation_request_claims
       WHERE request_id = '${same_request_id}'::uuid),
      (SELECT count(*) FROM app_private.organization_creation_audit_events
       WHERE request_id = '${same_request_id}'::uuid),
      (SELECT count(*) FROM app_data.workspaces
       WHERE workspace_id = split_part('${same_first_result}', '|', 2)::uuid),
      (SELECT count(*) FROM app_data.organization_memberships
       WHERE organization_membership_id = split_part('${same_first_result}', '|', 3)::uuid),
      (SELECT count(*) FROM app_data.organization_owner_assignments
       WHERE organization_owner_assignment_id = split_part('${same_first_result}', '|', 4)::uuid);
  " | tr -d '[:space:]')"
if [[ "${same_fact_counts}" != '1|1|1|1|1' ]]; then
  echo "同 request 并发留下的事实集合错误：${same_fact_counts}" >&2
  exit 1
fi

echo '验证持有 request lock 时的 payload drift 在释放后固定 conflict。'
drift_first_output="${temporary_directory}/drift-first.out"
drift_second_output="${temporary_directory}/drift-second.out"
run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.create_organization_v1(
      '${actor_id}'::uuid,
      '${drift_request_id}'::uuid,
      '84C drift organization'
    );
    SELECT 'ready' WHERE pg_advisory_lock(
      hashtextextended('${drift_request_ready}', 0)
    ) IS NULL;
    SELECT pg_sleep(2);
    COMMIT;
  " >"${drift_first_output}" 2>&1 &
drift_first_pid=$!
child_pids+=("${drift_first_pid}")
wait_for_lock_holder "${drift_request_ready}" "${drift_first_pid}" \
  "${drift_first_output}"

run_psql --quiet --set=VERBOSITY=verbose --command="
    SELECT * FROM app_private.create_organization_v1(
      '${actor_id}'::uuid,
      '${drift_request_id}'::uuid,
      '84C drift organization changed'
    );
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
  echo "drift 并发结果错误：first=${drift_first_status}, second=${drift_second_status}" >&2
  sed -n '1,160p' "${drift_first_output}" >&2
  sed -n '1,160p' "${drift_second_output}" >&2
  exit 1
fi
if ! grep -q '22023' "${drift_second_output}" \
  || ! grep -q 'organization creation idempotency conflict' \
    "${drift_second_output}"; then
  echo 'drift 没有返回固定 SQLSTATE/message。' >&2
  sed -n '1,160p' "${drift_second_output}" >&2
  exit 1
fi

drift_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*) FROM app_private.organization_creation_request_claims
       WHERE request_id = '${drift_request_id}'::uuid),
      (SELECT count(*) FROM app_private.organization_creation_audit_events
       WHERE request_id = '${drift_request_id}'::uuid);
  " | tr -d '[:space:]')"
if [[ "${drift_fact_counts}" != '1|1' ]]; then
  echo "drift 修改了已提交事实：${drift_fact_counts}" >&2
  exit 1
fi

echo '验证同 actor、不同 request 在 actor row lock 上串行并各自成功。'
actor_first_output="${temporary_directory}/actor-first.out"
actor_second_output="${temporary_directory}/actor-second.out"
run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.create_organization_v1(
      '${actor_id}'::uuid,
      '${serial_request_one}'::uuid,
      '84C serial organization one'
    );
    SELECT 'ready' WHERE pg_advisory_lock(
      hashtextextended('${actor_ready}', 0)
    ) IS NULL;
    SELECT pg_sleep(2);
    COMMIT;
  " >"${actor_first_output}" 2>&1 &
actor_first_pid=$!
child_pids+=("${actor_first_pid}")
wait_for_lock_holder "${actor_ready}" "${actor_first_pid}" \
  "${actor_first_output}"

run_psql --quiet --tuples-only --no-align --field-separator='|' \
  --command="
    BEGIN;
    SET TIME ZONE 'UTC';
    SELECT * FROM app_private.create_organization_v1(
      '${actor_id}'::uuid,
      '${serial_request_two}'::uuid,
      '84C serial organization two'
    );
    COMMIT;
  " >"${actor_second_output}" 2>&1 &
actor_second_pid=$!
child_pids+=("${actor_second_pid}")
wait_for_actor_waiter "${actor_second_pid}" "${actor_second_output}"

actor_first_status=0
actor_second_status=0
wait "${actor_first_pid}" || actor_first_status=$?
wait "${actor_second_pid}" || actor_second_status=$?
if [[ "${actor_first_status}" -ne 0 || "${actor_second_status}" -ne 0 ]]; then
  echo "同 actor 并发创建失败：first=${actor_first_status}, second=${actor_second_status}" >&2
  sed -n '1,160p' "${actor_first_output}" >&2
  sed -n '1,160p' "${actor_second_output}" >&2
  exit 1
fi

actor_first_result="$(result_from "${actor_first_output}")"
actor_second_result="$(result_from "${actor_second_output}")"
assert_result_row "${actor_first_result}" '同 actor 首次请求'
assert_result_row "${actor_second_result}" '同 actor 第二请求'
if [[ "${actor_first_result}" == "${actor_second_result}" ]]; then
  echo '不同 request 意外返回了同一 creation result。' >&2
  exit 1
fi

serial_fact_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*) FROM app_private.organization_creation_request_claims
       WHERE request_id IN (
         '${serial_request_one}'::uuid,
         '${serial_request_two}'::uuid
       )),
      (SELECT count(*) FROM app_private.organization_creation_audit_events
       WHERE request_id IN (
         '${serial_request_one}'::uuid,
         '${serial_request_two}'::uuid
       )),
      (SELECT count(DISTINCT organization_workspace_id)
       FROM app_private.organization_creation_request_claims
       WHERE request_id IN (
         '${serial_request_one}'::uuid,
         '${serial_request_two}'::uuid
       ));
  " | tr -d '[:space:]')"
if [[ "${serial_fact_counts}" != '2|2|2' ]]; then
  echo "同 actor 串行事实集合错误：${serial_fact_counts}" >&2
  exit 1
fi

serial_owner_assignment_id="$(echo "${actor_first_result}" | cut -d'|' -f4)"

echo '验证已提交 owner assignment 可合法 close 一次，随后不可改写或删除。'
run_psql --quiet --command="
  BEGIN;
  DO \$close\$
  DECLARE
    changed_count integer;
    closed_at timestamptz;
  BEGIN
    UPDATE app_data.organization_owner_assignments
    SET inactive_from_utc = transaction_timestamp()
    WHERE organization_owner_assignment_id =
      '${serial_owner_assignment_id}'::uuid
    RETURNING inactive_from_utc INTO closed_at;

    GET DIAGNOSTICS changed_count = ROW_COUNT;
    IF changed_count <> 1 OR closed_at <> transaction_timestamp()
    THEN
      RAISE EXCEPTION 'owner assignment close did not use one transaction timestamp';
    END IF;
  END
  \$close\$;
  COMMIT;
" >/dev/null

closed_assignment="$(run_psql --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_data.organization_owner_assignments
  WHERE organization_owner_assignment_id =
    '${serial_owner_assignment_id}'::uuid
    AND inactive_from_utc IS NOT NULL;
" | tr -d '[:space:]')"
if [[ "${closed_assignment}" != '1' ]]; then
  echo 'owner assignment legal close 没有保留一条已结束记录。' >&2
  exit 1
fi

expect_failure \
  'closed-owner-update' \
  '55000' \
  'organization owner assignment history is append-only' \
  "UPDATE app_data.organization_owner_assignments
   SET active_from_utc = active_from_utc + interval '1 second'
   WHERE organization_owner_assignment_id =
     '${serial_owner_assignment_id}'::uuid;"

expect_failure \
  'closed-owner-delete' \
  '55000' \
  'organization owner assignment history cannot be deleted' \
  "DELETE FROM app_data.organization_owner_assignments
   WHERE organization_owner_assignment_id =
     '${serial_owner_assignment_id}'::uuid;"

echo '0084 organization creation concurrency checks passed; synthetic rows committed for dump/restore.'
