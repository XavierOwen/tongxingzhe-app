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
  local lock_name="$1" holder_pid="$2" holder_output="$3" probe
  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      WITH probe AS (
        SELECT pg_try_advisory_lock(hashtextextended('${lock_name}', 0)) AS acquired
      )
      SELECT CASE WHEN acquired
        THEN NOT pg_advisory_unlock(hashtextextended('${lock_name}', 0))
        ELSE true END
      FROM probe;
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
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_advisory_waiter() {
  local lock_name="$1" waiter_pid="$2" waiter_output="$3" waiting
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
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

wait_for_app_user_waiter() {
  local waiter_pid="$1" waiter_output="$2" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row
        WHERE NOT lock_row.granted
          AND (lock_row.locktype = 'transactionid'
            OR (lock_row.locktype = 'tuple'
              AND lock_row.relation = 'app_data.app_users'::regclass))
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
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

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    SET LOCAL ROLE tongxingzhe_runtime;
    SELECT * FROM app_data.create_organization_shareable_join_link_for_identity_v1(
      '0092-concurrency', 'replay-owner', '${replay_link}', '${replay_workspace}');
    RESET ROLE;
    SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
    SELECT pg_sleep(2);
    COMMIT;
  " >"${first_output}" 2>&1 &
  first_pid=$!
  child_pids+=("${first_pid}")
  wait_for_lock_holder "${ready_lock}" "${first_pid}" "${first_output}"

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    SET LOCAL ROLE tongxingzhe_runtime;
    SELECT * FROM app_data.create_organization_shareable_join_link_for_identity_v1(
      '0092-concurrency', 'replay-owner', '${replay_link}', '${replay_workspace}');
    COMMIT;
  " >"${second_output}" 2>&1 &
  second_pid=$!
  child_pids+=("${second_pid}")
  wait_for_advisory_waiter "${request_lock}" "${second_pid}" "${second_output}"
  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?
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
run_psql --quiet --command="
  BEGIN;
  SELECT * FROM app_private.transfer_organization_owner_v1(
    '${transfer_owner}', '${transfer_request}', '${transfer_workspace}',
    '92020000-0092-3000-8000-000000000003');
  SELECT pg_advisory_lock(hashtextextended('${transfer_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${transfer_output}" 2>&1 &
transfer_pid=$!
child_pids+=("${transfer_pid}")
wait_for_lock_holder "${transfer_ready}" "${transfer_pid}" "${transfer_output}"

run_psql --quiet --command="
  BEGIN;
  SELECT * FROM app_private.create_organization_shareable_join_link_v1(
    '${transfer_owner}', '${transfer_race_link}', '${transfer_workspace}');
  COMMIT;
" >"${transfer_create_output}" 2>&1 &
transfer_create_pid=$!
child_pids+=("${transfer_create_pid}")
wait_for_app_user_waiter "${transfer_create_pid}" "${transfer_create_output}"
transfer_status=0
transfer_create_status=0
wait "${transfer_pid}" || transfer_status=$?
wait "${transfer_create_pid}" || transfer_create_status=$?
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
run_psql --quiet --command="
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
  SELECT pg_sleep(2);
  COMMIT;
" >"${membership_output}" 2>&1 &
membership_pid=$!
child_pids+=("${membership_pid}")
wait_for_lock_holder "${membership_ready}" "${membership_pid}" "${membership_output}"

run_psql --quiet --command="
  BEGIN;
  SELECT * FROM app_private.create_organization_shareable_join_link_v1(
    '${membership_owner}', '${membership_race_link}', '${membership_workspace}');
  COMMIT;
" >"${membership_create_output}" 2>&1 &
membership_create_pid=$!
child_pids+=("${membership_create_pid}")
wait_for_app_user_waiter "${membership_create_pid}" "${membership_create_output}"
membership_status=0
membership_create_status=0
wait "${membership_pid}" || membership_status=$?
wait "${membership_create_pid}" || membership_create_status=$?
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
