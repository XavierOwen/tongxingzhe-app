#!/usr/bin/env bash

set -euo pipefail

# Independent sessions verify link-request serialization and the shared
# app-user -> governance -> membership order used by owner/member mutations.
# Rows are committed for dump/restore checks and use a namespace distinct from
# the rollback fixture.
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

holder_fd=''
run_psql() (
  if [[ -n "${holder_fd}" ]]; then exec {holder_fd}>&-; fi
  "${psql_base[@]}" "$@"
)

run_psql_background() {
  if [[ -n "${holder_fd}" ]]; then exec {holder_fd}>&-; fi
  exec "${psql_base[@]}" "$@"
}

temporary_directory="$(mktemp -d)"
child_pids=()
application_prefix="0092-$$-${temporary_directory##*/}"
replay_holder_application="${application_prefix}-replay-holder"
replay_waiter_application="${application_prefix}-replay-waiter"
transfer_holder_application="${application_prefix}-transfer-holder"
transfer_waiter_application="${application_prefix}-transfer-waiter"
membership_holder_application="${application_prefix}-membership-holder"
membership_waiter_application="${application_prefix}-membership-waiter"
observed_pg_pid=''

stop_psql_job() {
  local pid="$1" child_pid
  if ! kill -0 "${pid}" >/dev/null 2>&1; then return; fi
  kill -STOP "${pid}" >/dev/null 2>&1 || true
  for child_pid in $(ps -eo pid=,ppid= | awk -v parent="${pid}" '$2 == parent { print $1 }'); do
    stop_psql_job "${child_pid}"
  done
  kill -TERM "${pid}" >/dev/null 2>&1 || true
  kill -CONT "${pid}" >/dev/null 2>&1 || true
}

cleanup() {
  local pid
  # EOF closes the holder's transaction first. Children never inherit this FD.
  if [[ -n "${holder_fd}" ]]; then exec {holder_fd}>&-; holder_fd=''; fi
  # A PSQL_COMMAND wrapper may leave a server session after its process exits.
  # Terminate only this invocation's uniquely named sessions in this database.
  run_psql --quiet --command="
    SELECT pg_terminate_backend(pid) FROM pg_stat_activity
    WHERE datname = current_database() AND pid <> pg_backend_pid()
      AND application_name IN ('${replay_holder_application}', '${replay_waiter_application}',
        '${transfer_holder_application}', '${transfer_waiter_application}',
        '${membership_holder_application}', '${membership_waiter_application}');
  " >/dev/null 2>&1 || true
  for pid in "${child_pids[@]:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      stop_psql_job "${pid}"
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*.out "${temporary_directory}"/*.fifo
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock_holder() {
  local lock_name="$1" holder_pid="$2" holder_output="$3" application_name="$4" probe
  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      SELECT activity.pid FROM pg_stat_activity AS activity
      JOIN pg_locks AS lock_row ON lock_row.pid = activity.pid
      WHERE activity.datname = current_database() AND activity.application_name = '${application_name}'
        AND lock_row.locktype = 'advisory' AND lock_row.granted
        AND lock_row.database = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND lock_row.classid::bigint = ((hashtextextended('${lock_name}', 0) >> 32) & 4294967295)
        AND lock_row.objid::bigint = (hashtextextended('${lock_name}', 0) & 4294967295)
        AND lock_row.objsubid = 1;
    " | tr -d '[:space:]')"
    if [[ "${probe}" =~ ^[0-9]+$ ]]; then
      observed_pg_pid="${probe}"
      echo "${application_name}: PostgreSQL PID ${probe}, exact ready lock ${lock_name}"
      return
    fi
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then
      echo "并发持锁会话过早退出：${lock_name}" >&2
      sed -n '1,160p' "${holder_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_session() {
  local application_name="$1" process_pid="$2" output="$3" probe
  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      SELECT pid FROM pg_stat_activity
      WHERE datname = current_database() AND application_name = '${application_name}';
    " | tr -d '[:space:]')"
    if [[ "${probe}" =~ ^[0-9]+$ ]]; then observed_pg_pid="${probe}"; return; fi
    if ! kill -0 "${process_pid}" >/dev/null 2>&1; then
      echo "并发等待会话过早退出：${application_name}" >&2
      sed -n '1,160p' "${output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo "没有观察到指定 PostgreSQL 会话：${application_name}" >&2
  sed -n '1,160p' "${output}" >&2
  exit 1
}

wait_for_advisory_waiter() {
  local lock_name="$1" waiter_pid="$2" waiter_output="$3" application_name="$4" waiter_pg_pid="$5" holder_pg_pid="$6" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32) & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0) & 4294967295)::bigint AS objid,
          (SELECT oid FROM pg_database WHERE datname = current_database()) AS database_id
      )
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row CROSS JOIN lock_key
        JOIN pg_stat_activity AS activity ON activity.pid = lock_row.pid
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
          AND lock_row.database = lock_key.database_id
          AND lock_row.classid::bigint = lock_key.classid
          AND lock_row.objid::bigint = lock_key.objid
          AND lock_row.objsubid = 1
          AND activity.application_name = '${application_name}' AND activity.pid = ${waiter_pg_pid}
          AND ${holder_pg_pid} = ANY(pg_blocking_pids(activity.pid))
          AND EXISTS (SELECT 1 FROM pg_locks AS held
            WHERE held.pid = ${holder_pg_pid} AND held.granted AND held.locktype = 'advisory'
              AND held.database = lock_row.database AND held.classid = lock_row.classid
              AND held.objid = lock_row.objid AND held.objsubid = lock_row.objsubid)
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      echo "${application_name}: PostgreSQL PID ${waiter_pg_pid}, exact ${lock_name}, blocker PID ${holder_pg_pid}"
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo "并发等待会话过早退出：${lock_name}" >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

wait_for_app_user_waiter() {
  local waiter_pid="$1" waiter_output="$2" application_name="$3" waiter_pg_pid="$4" holder_pg_pid="$5" app_user_id="$6" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS waiting
        JOIN pg_stat_activity AS waiter ON waiter.pid = waiting.pid
        JOIN pg_stat_activity AS holder ON holder.pid = ${holder_pg_pid}
        JOIN app_data.app_users AS locked_user ON locked_user.app_user_id = '${app_user_id}'::uuid
        JOIN pg_locks AS held ON held.pid = holder.pid AND held.locktype = 'transactionid'
          AND held.granted AND held.transactionid = waiting.transactionid
        WHERE waiter.application_name = '${application_name}' AND waiter.pid = ${waiter_pg_pid}
          AND waiter.datname = current_database() AND holder.datname = current_database()
          AND waiting.locktype = 'transactionid' AND NOT waiting.granted
          AND waiting.transactionid = holder.backend_xid
          AND locked_user.xmax::text = holder.backend_xid::text
          AND holder.pid = ANY(pg_blocking_pids(waiter.pid))
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      echo "${application_name}: PostgreSQL PID ${waiter_pg_pid}, app-user ${app_user_id} transactionid, blocker PID ${holder_pg_pid}"
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo 'join-link create 会话在 app-user 锁前过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo '没有观察到 join-link create 的 app_users 行锁等待。' >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

result_from() {
  awk '/^organization-shareable-join-link:v1\|/ { print; exit }' "$1"
}

run_create_replay_pair() {
  local first_output="${temporary_directory}/create-replay-first.out"
  local second_output="${temporary_directory}/create-replay-second.out"
  local ready_lock='0092-ready:create-replay'
  local request_lock="organization-shareable-join-link-request:${replay_link}"
  local first_pid second_pid first_status=0 second_status=0 first_row second_row
  local holder_pg_pid waiter_pg_pid

  mkfifo "${temporary_directory}/create-replay.fifo"
  PGAPPNAME="${replay_holder_application}" run_psql_background --quiet --tuples-only --no-align --field-separator='|' \
    <"${temporary_directory}/create-replay.fifo" >"${first_output}" 2>&1 &
  first_pid=$!
  child_pids+=("${first_pid}")
  exec {holder_fd}>"${temporary_directory}/create-replay.fifo"
  printf '%s\n' "
    BEGIN;
    SET LOCAL ROLE tongxingzhe_runtime;
    SELECT * FROM app_data.create_organization_shareable_join_link_for_identity_v1(
      '0092-concurrency', 'replay-owner', '${replay_link}', '${replay_workspace}');
    RESET ROLE;
    SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
  " >&"${holder_fd}"
  wait_for_lock_holder "${ready_lock}" "${first_pid}" "${first_output}" "${replay_holder_application}"
  holder_pg_pid="${observed_pg_pid}"

  PGAPPNAME="${replay_waiter_application}" run_psql_background --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    SET LOCAL ROLE tongxingzhe_runtime;
    SELECT * FROM app_data.create_organization_shareable_join_link_for_identity_v1(
      '0092-concurrency', 'replay-owner', '${replay_link}', '${replay_workspace}');
    COMMIT;
  " >"${second_output}" 2>&1 &
  second_pid=$!
  child_pids+=("${second_pid}")
  wait_for_session "${replay_waiter_application}" "${second_pid}" "${second_output}"
  waiter_pg_pid="${observed_pg_pid}"
  wait_for_advisory_waiter "${request_lock}" "${second_pid}" "${second_output}" "${replay_waiter_application}" "${waiter_pg_pid}" "${holder_pg_pid}"
  printf '%s\n' "COMMIT; SELECT pg_advisory_unlock(hashtextextended('${ready_lock}', 0));" >&"${holder_fd}"
  exec {holder_fd}>&-
  holder_fd=''
  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?
  child_pids=()
  if [[ "${first_status}" -ne 0 || "${second_status}" -ne 0 ]]; then
    sed -n '1,160p' "${first_output}" >&2
    sed -n '1,160p' "${second_output}" >&2
    exit 1
  fi
  first_row="$(result_from "${first_output}")"
  second_row="$(result_from "${second_output}")"
  if [[ -z "${first_row}" || "${first_row}" != "${second_row}" ]] \
    || [[ "$(awk -F'|' '{ print NF }' <<<"${first_row}")" -ne 5 ]]; then
    echo '0092 concurrent create 未精确重放五字段 receipt。' >&2
    exit 1
  fi
}

assert_forbidden() {
  local label="$1" output="$2" status="$3"
  if [[ "${status}" -eq 0 ]] \
    || ! grep -Fq '42501: organization shareable join forbidden' "${output}"; then
    echo "${label} 未在治理变化后返回固定 forbidden。" >&2
    sed -n '1,160p' "${output}" >&2
    exit 1
  fi
}

replay_workspace='92020000-0092-4000-8000-000000000001'
transfer_workspace='92020000-0092-4000-8000-000000000002'
membership_workspace='92020000-0092-4000-8000-000000000003'
replay_owner='92020000-0092-0000-8000-000000000001'
transfer_owner='92020000-0092-0000-8000-000000000002'
transfer_target='92020000-0092-0000-8000-000000000003'
membership_owner='92020000-0092-0000-8000-000000000004'
replay_link='92020000-0092-5000-8000-000000000001'
transfer_race_link='92020000-0092-5000-8000-000000000002'
membership_race_link='92020000-0092-5000-8000-000000000003'
transfer_request='92020000-0092-6000-8000-000000000001'

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status) VALUES
    ('${replay_owner}', 'active'),
    ('${transfer_owner}', 'active'),
    ('${transfer_target}', 'active'),
    ('${membership_owner}', 'active');
  INSERT INTO app_data.external_identities (issuer, subject, app_user_id)
  VALUES ('0092-concurrency', 'replay-owner', '${replay_owner}');
  INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
  VALUES
    ('${replay_workspace}', 'organization', '0092 concurrent replay'),
    ('${transfer_workspace}', 'organization', '0092 concurrent owner transfer'),
    ('${membership_workspace}', 'organization', '0092 concurrent membership close');
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('92020000-0092-3000-8000-000000000001', '${replay_workspace}',
      '${replay_owner}', transaction_timestamp(), NULL),
    ('92020000-0092-3000-8000-000000000002', '${transfer_workspace}',
      '${transfer_owner}', transaction_timestamp(), NULL),
    ('92020000-0092-3000-8000-000000000003', '${transfer_workspace}',
      '${transfer_target}', transaction_timestamp(), NULL),
    ('92020000-0092-3000-8000-000000000004', '${membership_workspace}',
      '${membership_owner}', transaction_timestamp(), NULL),
    ('92020000-0092-3000-8000-000000000005', '${membership_workspace}',
      '${transfer_target}', transaction_timestamp(), NULL);
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id, organization_membership_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('92020000-0092-7000-8000-000000000001',
      '92020000-0092-3000-8000-000000000001', transaction_timestamp(), NULL),
    ('92020000-0092-7000-8000-000000000002',
      '92020000-0092-3000-8000-000000000002', transaction_timestamp(), NULL),
    ('92020000-0092-7000-8000-000000000003',
      '92020000-0092-3000-8000-000000000004', transaction_timestamp(), NULL),
    ('92020000-0092-7000-8000-000000000004',
      '92020000-0092-3000-8000-000000000005', transaction_timestamp(), NULL);
  COMMIT;
"

run_create_replay_pair

# The production owner-transfer writer holds actor/target rows before the
# governance and membership locks. A correct create waits on its creator row,
# then re-reads and rejects the former owner after transfer commits.
transfer_output="${temporary_directory}/owner-transfer.out"
transfer_create_output="${temporary_directory}/owner-transfer-create.out"
transfer_ready='0092-ready:owner-transfer'
mkfifo "${temporary_directory}/owner-transfer.fifo"
PGAPPNAME="${transfer_holder_application}" run_psql_background --quiet \
  <"${temporary_directory}/owner-transfer.fifo" >"${transfer_output}" 2>&1 &
transfer_pid=$!
child_pids+=("${transfer_pid}")
exec {holder_fd}>"${temporary_directory}/owner-transfer.fifo"
printf '%s\n' "
  BEGIN;
  SELECT * FROM app_private.transfer_organization_owner_v1(
    '${transfer_owner}', '${transfer_request}', '${transfer_workspace}',
    '92020000-0092-3000-8000-000000000003');
  SELECT pg_advisory_lock(hashtextextended('${transfer_ready}', 0));
" >&"${holder_fd}"
wait_for_lock_holder "${transfer_ready}" "${transfer_pid}" "${transfer_output}" "${transfer_holder_application}"
transfer_holder_pg_pid="${observed_pg_pid}"

PGAPPNAME="${transfer_waiter_application}" run_psql_background --quiet --command="
  BEGIN;
  SELECT * FROM app_private.create_organization_shareable_join_link_v1(
    '${transfer_owner}', '${transfer_race_link}', '${transfer_workspace}');
  COMMIT;
" >"${transfer_create_output}" 2>&1 &
transfer_create_pid=$!
child_pids+=("${transfer_create_pid}")
wait_for_session "${transfer_waiter_application}" "${transfer_create_pid}" "${transfer_create_output}"
transfer_waiter_pg_pid="${observed_pg_pid}"
wait_for_app_user_waiter "${transfer_create_pid}" "${transfer_create_output}" "${transfer_waiter_application}" "${transfer_waiter_pg_pid}" "${transfer_holder_pg_pid}" "${transfer_owner}"
printf '%s\n' "COMMIT; SELECT pg_advisory_unlock(hashtextextended('${transfer_ready}', 0));" >&"${holder_fd}"
exec {holder_fd}>&-
holder_fd=''
transfer_status=0
transfer_create_status=0
wait "${transfer_pid}" || transfer_status=$?
wait "${transfer_create_pid}" || transfer_create_status=$?
child_pids=()
if [[ "${transfer_status}" -ne 0 ]]; then
  sed -n '1,160p' "${transfer_output}" >&2
  exit 1
fi
assert_forbidden 'owner transfer/create race' \
  "${transfer_create_output}" "${transfer_create_status}"

# A membership-governance transaction takes the same three shared locks in
# the documented order. The create must wait at the creator row, not hold a
# later governance lock, and must reject the closed membership after commit.
membership_output="${temporary_directory}/membership-close.out"
membership_create_output="${temporary_directory}/membership-close-create.out"
membership_ready='0092-ready:membership-close'
membership_lock="organization-membership:${membership_workspace}:${membership_owner}"
mkfifo "${temporary_directory}/membership-close.fifo"
PGAPPNAME="${membership_holder_application}" run_psql_background --quiet \
  <"${temporary_directory}/membership-close.fifo" >"${membership_output}" 2>&1 &
membership_pid=$!
child_pids+=("${membership_pid}")
exec {holder_fd}>"${temporary_directory}/membership-close.fifo"
printf '%s\n' "
  BEGIN;
  SELECT 1 FROM app_data.app_users
  WHERE app_user_id = '${membership_owner}' FOR UPDATE;
  SELECT app_private.lock_organization_governance_v1('${membership_workspace}');
  SELECT pg_advisory_xact_lock(hashtextextended('${membership_lock}', 0));
  UPDATE app_data.organization_owner_assignments
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_owner_assignment_id =
    '92020000-0092-7000-8000-000000000003';
  UPDATE app_data.organization_memberships
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_membership_id =
    '92020000-0092-3000-8000-000000000004';
  SELECT pg_advisory_lock(hashtextextended('${membership_ready}', 0));
" >&"${holder_fd}"
wait_for_lock_holder "${membership_ready}" "${membership_pid}" "${membership_output}" "${membership_holder_application}"
membership_holder_pg_pid="${observed_pg_pid}"

PGAPPNAME="${membership_waiter_application}" run_psql_background --quiet --command="
  BEGIN;
  SELECT * FROM app_private.create_organization_shareable_join_link_v1(
    '${membership_owner}', '${membership_race_link}', '${membership_workspace}');
  COMMIT;
" >"${membership_create_output}" 2>&1 &
membership_create_pid=$!
child_pids+=("${membership_create_pid}")
wait_for_session "${membership_waiter_application}" "${membership_create_pid}" "${membership_create_output}"
membership_waiter_pg_pid="${observed_pg_pid}"
wait_for_app_user_waiter "${membership_create_pid}" "${membership_create_output}" "${membership_waiter_application}" "${membership_waiter_pg_pid}" "${membership_holder_pg_pid}" "${membership_owner}"
printf '%s\n' "COMMIT; SELECT pg_advisory_unlock(hashtextextended('${membership_ready}', 0));" >&"${holder_fd}"
exec {holder_fd}>&-
holder_fd=''
membership_status=0
membership_create_status=0
wait "${membership_pid}" || membership_status=$?
wait "${membership_create_pid}" || membership_create_status=$?
child_pids=()
if [[ "${membership_status}" -ne 0 ]]; then
  sed -n '1,160p' "${membership_output}" >&2
  exit 1
fi
assert_forbidden 'membership close/create race' \
  "${membership_create_output}" "${membership_create_status}"

facts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    (SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims
      WHERE link_id = '${replay_link}'),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events
      WHERE link_id = '${replay_link}'),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_request_claims
      WHERE link_id IN ('${transfer_race_link}', '${membership_race_link}')),
    (SELECT count(*) FROM app_private.organization_shareable_join_link_audit_events
      WHERE link_id IN ('${transfer_race_link}', '${membership_race_link}')),
    (SELECT count(*) FROM app_data.organization_owner_assignments AS owner_row
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE membership.organization_workspace_id = '${transfer_workspace}'
        AND owner_row.inactive_from_utc IS NULL),
    (SELECT count(*) FROM app_data.organization_memberships
      WHERE organization_membership_id =
        '92020000-0092-3000-8000-000000000004'
        AND inactive_from_utc IS NOT NULL);
")"
if [[ "${facts}" != '1|1|0|0|1|1' ]]; then
  echo "0092 并发最终事实不匹配：${facts}" >&2
  exit 1
fi

echo '0092 join-link create replay and owner/membership governance races passed.'
