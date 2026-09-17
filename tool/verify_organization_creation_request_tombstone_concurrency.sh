#!/usr/bin/env bash
set -euo pipefail

# Dedicated synthetic test database only. These committed terminal facts do
# not represent purge: no live claim, audit, owner or organization is deleted.
: "${DATABASE_URL:?请设置专用 synthetic 测试库 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"

run_psql() {
  "${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}

temporary_directory="$(mktemp -d)"
child_pids=()
cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_request_lock() {
  local application_name="$1" granted="$2" pid="$3" output_file="$4"
  local observed
  for _ in $(seq 1 100); do
    observed="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT hashtextextended('${request_lock}', 0) AS key
      )
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row
        JOIN pg_stat_activity AS activity ON activity.pid = lock_row.pid
        CROSS JOIN lock_key
        WHERE activity.application_name = '${application_name}'
          AND lock_row.locktype = 'advisory'
          AND lock_row.granted = ${granted}
          AND lock_row.classid::bigint = ((lock_key.key >> 32) & 4294967295)
          AND lock_row.objid::bigint = (lock_key.key & 4294967295)
          AND lock_row.objsubid = 1
      );" | tr -d '[:space:]')"
    if [[ "${observed}" == 't' ]]; then return; fi
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      echo "并发会话过早退出：${application_name}" >&2
      sed -n '1,160p' "${output_file}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo "未观察到 request lock：${application_name} / granted=${granted}" >&2
  sed -n '1,160p' "${output_file}" >&2
  exit 1
}

actor_id='95000000-0095-4000-8000-000000000001'
run_psql --quiet --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('${actor_id}', 'active');"

for phase in tombstone-first create-first; do
  if [[ "${phase}" == 'tombstone-first' ]]; then
    request_id='95000000-0095-5000-8000-000000000001'
  else
    request_id='95000000-0095-5000-8000-000000000002'
  fi
  request_lock="organization-creation-request:${request_id}"
  create_statement="SELECT * FROM app_private.create_organization_v1(
    '${actor_id}', '${request_id}', '0095 concurrency ${phase}');"
  tombstone_statement="SELECT pg_advisory_xact_lock(hashtextextended('${request_lock}', 0));
    INSERT INTO app_private.organization_creation_request_tombstones
    VALUES ('organization-creation:v1', '${request_id}');"
  if [[ "${phase}" == 'tombstone-first' ]]; then
    holder_statement="${tombstone_statement}"
    waiter_statement="${create_statement}"
  else
    holder_statement="${create_statement}"
    waiter_statement="${tombstone_statement}"
  fi
  holder_output="${temporary_directory}/${phase}-holder.out"
  waiter_output="${temporary_directory}/${phase}-waiter.out"
  PGAPPNAME="0095-${phase}-holder" run_psql --quiet --command="
    BEGIN; ${holder_statement} SELECT pg_sleep(3); COMMIT;" \
    >"${holder_output}" 2>&1 &
  holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_request_lock "0095-${phase}-holder" true "${holder_pid}" "${holder_output}"

  PGAPPNAME="0095-${phase}-waiter" run_psql --quiet --set=VERBOSITY=verbose \
    --command="BEGIN; ${waiter_statement} COMMIT;" >"${waiter_output}" 2>&1 &
  waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_request_lock "0095-${phase}-waiter" false "${waiter_pid}" "${waiter_output}"
  holder_status=0
  waiter_status=0
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 ]] \
    || [[ "${phase}" == 'create-first' && "${waiter_status}" -ne 0 ]] \
    || [[ "${phase}" == 'tombstone-first' && "${waiter_status}" -eq 0 ]]; then
    echo "0095 request lock 串行结果错误：${phase}" >&2
    sed -n '1,160p' "${holder_output}" "${waiter_output}" >&2
    exit 1
  fi
  if [[ "${phase}" == 'tombstone-first' ]] \
    && { ! grep -q '22023' "${waiter_output}" \
      || ! grep -q 'organization creation idempotency conflict' "${waiter_output}"; }; then
    echo '0095 fence 没有返回固定 SQLSTATE/message。' >&2
    sed -n '1,160p' "${waiter_output}" >&2
    exit 1
  fi

  # After either serial order commits, the terminal fence also blocks replay.
  run_psql --quiet --command="
    DO \$check\$
    BEGIN
      BEGIN
        ${create_statement/SELECT/PERFORM}
      EXCEPTION WHEN SQLSTATE '22023' THEN
        IF SQLERRM = 'organization creation idempotency conflict' THEN RETURN; END IF;
        RAISE;
      END;
      RAISE EXCEPTION '0095 terminal request was accepted';
    END
    \$check\$;"
done

run_psql --quiet <<'SQL'
DO $check$
BEGIN
  IF (SELECT count(*) FROM app_private.organization_creation_request_tombstones
      WHERE request_id IN ('95000000-0095-5000-8000-000000000001',
                          '95000000-0095-5000-8000-000000000002')) <> 2
    OR EXISTS (SELECT 1 FROM app_private.organization_creation_request_claims
      WHERE request_id = '95000000-0095-5000-8000-000000000001')
    OR EXISTS (SELECT 1 FROM app_private.organization_creation_audit_events
      WHERE request_id = '95000000-0095-5000-8000-000000000001')
    OR (SELECT count(*) FROM app_private.organization_creation_request_claims
      WHERE request_id = '95000000-0095-5000-8000-000000000002') <> 1
    OR (SELECT count(*) FROM app_private.organization_creation_audit_events
      WHERE request_id = '95000000-0095-5000-8000-000000000002') <> 1
    OR (SELECT count(*) FROM app_data.organization_memberships
      WHERE app_user_id = '95000000-0095-4000-8000-000000000001') <> 1
    OR (SELECT count(*) FROM app_data.organization_owner_assignments AS assignment
      JOIN app_data.organization_memberships AS membership USING (organization_membership_id)
      WHERE membership.app_user_id = '95000000-0095-4000-8000-000000000001') <> 1 THEN
    RAISE EXCEPTION '0095 concurrency changed the expected live / terminal facts';
  END IF;
END
$check$;
SQL
echo '0095 creation tombstone request-lock 并发验证通过（synthetic；未清除live事实）。'
