#!/usr/bin/env bash

set -euo pipefail

# Independent sessions prove request, actor, governance, and membership lock
# behavior. Rows are committed so the parent Docker runner can dump/restore them.
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
        SELECT pg_try_advisory_lock(hashtextextended('${lock_name}', 0))
          AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${lock_name}', 0)
        )
        ELSE true
      END
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
  exit 1
}

wait_for_advisory_waiter() {
  local lock_name="$1" waiter_pid="$2" waiter_output="$3" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32)
            & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0)
            & 4294967295)::bigint AS objid,
          (SELECT oid FROM pg_database WHERE datname = current_database())
            AS database_id
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
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  exit 1
}

wait_for_app_user_waiter() {
  local waiter_pid="$1" waiter_output="$2" waiting
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
      echo '并发 app_users 等待会话过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo '没有观察到 app_users 行锁等待。' >&2
  exit 1
}

result_from() {
  awk '/^organization-membership-self-leave:v1\|/ { print; exit }' "$1"
}

marker_value() {
  local marker="$1" output_file="$2"
  awk -F'|' -v marker="${marker}" \
    '$1 == marker { print substr($0, index($0, "|") + 1); exit }' \
    "${output_file}"
}

assert_failure() {
  local output_file="$1" label="$2" sqlstate="$3" message="$4"
  if ! grep -Fq "${sqlstate}: ${message}" "${output_file}"; then
    echo "${label} 没有返回固定数据库失败。" >&2
    sed -n '1,160p' "${output_file}" >&2
    exit 1
  fi
}

run_pair() {
  local label="$1" first_sql="$2" second_sql="$3" wait_lock="$4"
  local expected_state="$5" expected_message="$6" equal_receipts="$7"
  local first_after_wait_sql="${8:-}"
  local first_output="${temporary_directory}/${label}-first.out"
  local second_output="${temporary_directory}/${label}-second.out"
  local ready_lock="0090-ready:${label}"
  local first_pid second_pid first_status=0 second_status=0
  local first_row second_row

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    ${first_sql}
    SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
    SELECT pg_sleep(2);
    ${first_after_wait_sql}
    COMMIT;
  " >"${first_output}" 2>&1 &
  first_pid=$!
  child_pids+=("${first_pid}")
  wait_for_lock_holder "${ready_lock}" "${first_pid}" "${first_output}"

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    ${second_sql}
    COMMIT;
  " >"${second_output}" 2>&1 &
  second_pid=$!
  child_pids+=("${second_pid}")
  if [[ "${wait_lock}" == 'app_users' ]]; then
    wait_for_app_user_waiter "${second_pid}" "${second_output}"
  else
    wait_for_advisory_waiter "${wait_lock}" "${second_pid}" \
      "${second_output}"
  fi

  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?
  if [[ "${first_status}" -ne 0 ]]; then
    sed -n '1,160p' "${first_output}" >&2
    exit 1
  fi
  if [[ -n "${expected_state}" ]]; then
    if [[ "${second_status}" -eq 0 ]]; then
      echo "${label} 意外成功。" >&2
      exit 1
    fi
    assert_failure "${second_output}" "${label}" \
      "${expected_state}" "${expected_message}"
  elif [[ "${second_status}" -ne 0 ]]; then
    sed -n '1,160p' "${second_output}" >&2
    exit 1
  fi

  if [[ "${equal_receipts}" == 'yes' ]]; then
    first_row="$(result_from "${first_output}")"
    second_row="$(result_from "${second_output}")"
    if [[ -z "${first_row}" || "${first_row}" != "${second_row}" ]] \
      || [[ "$(awk -F'|' '{print NF}' <<<"${first_row}")" -ne 4 ]]
    then
      echo "${label} 未精确重放四字段 receipt。" >&2
      exit 1
    fi
  fi
}

request_prefix='organization-membership-self-leave-request:'
membership_prefix='organization-membership:'
owner_id='90000000-0090-4000-8000-000000000001'
other_actor_id='90000000-0090-4000-8000-000000000002'

same_workspace='90000000-0090-4100-8000-000000000001'
same_actor='90000000-0090-4000-8000-000000000011'
same_membership='90000000-0090-4200-8000-000000000011'
same_request='90000000-0090-4300-8000-000000000011'

different_workspace='90000000-0090-4100-8000-000000000002'
different_actor='90000000-0090-4000-8000-000000000012'
different_membership='90000000-0090-4200-8000-000000000012'
different_request_one='90000000-0090-4300-8000-000000000012'
different_request_two='90000000-0090-4300-8000-000000000013'

future_workspace='90000000-0090-4100-8000-000000000003'
future_actor='90000000-0090-4000-8000-000000000013'
future_membership='90000000-0090-4200-8000-000000000013'
future_request='90000000-0090-4300-8000-000000000014'

loss_workspace='90000000-0090-4100-8000-000000000004'
loss_actor='90000000-0090-4000-8000-000000000014'
loss_membership='90000000-0090-4200-8000-000000000014'
loss_request='90000000-0090-4300-8000-000000000015'

dependency_workspace='90000000-0090-4100-8000-000000000005'
dependency_actor='90000000-0090-4000-8000-000000000015'
dependency_membership='90000000-0090-4200-8000-000000000015'
dependency_project='90000000-0090-4400-8000-000000000001'
dependency_request='90000000-0090-4300-8000-000000000016'

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('${owner_id}', 'active'),
    ('${other_actor_id}', 'active'),
    ('${same_actor}', 'active'),
    ('${different_actor}', 'active'),
    ('${future_actor}', 'active'),
    ('${loss_actor}', 'active'),
    ('${dependency_actor}', 'active');

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES
    ('${same_workspace}', 'organization', '0090 same-request race'),
    ('${different_workspace}', 'organization', '0090 different-request race'),
    ('${future_workspace}', 'organization', '0090 future membership race'),
    ('${loss_workspace}', 'organization', '0090 membership loss race'),
    ('${dependency_workspace}', 'organization', '0090 dependency race');

  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('90000000-0090-4200-8000-000000000001', '${same_workspace}',
      '${owner_id}', transaction_timestamp(), NULL),
    ('${same_membership}', '${same_workspace}', '${same_actor}',
      transaction_timestamp(), NULL),
    ('90000000-0090-4200-8000-000000000002', '${different_workspace}',
      '${owner_id}', transaction_timestamp(), NULL),
    ('${different_membership}', '${different_workspace}', '${different_actor}',
      transaction_timestamp(), NULL),
    ('90000000-0090-4200-8000-000000000003', '${future_workspace}',
      '${owner_id}', transaction_timestamp(), NULL),
    ('90000000-0090-4200-8000-000000000004', '${loss_workspace}',
      '${owner_id}', transaction_timestamp(), NULL),
    ('${loss_membership}', '${loss_workspace}', '${loss_actor}',
      transaction_timestamp(), NULL),
    ('90000000-0090-4200-8000-000000000005', '${dependency_workspace}',
      '${owner_id}', transaction_timestamp(), NULL),
    ('${dependency_membership}', '${dependency_workspace}',
      '${dependency_actor}', transaction_timestamp(), NULL);

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id, organization_membership_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('90000000-0090-4500-8000-000000000001',
      '90000000-0090-4200-8000-000000000001', transaction_timestamp(), NULL),
    ('90000000-0090-4500-8000-000000000002',
      '90000000-0090-4200-8000-000000000002', transaction_timestamp(), NULL),
    ('90000000-0090-4500-8000-000000000003',
      '90000000-0090-4200-8000-000000000003', transaction_timestamp(), NULL),
    ('90000000-0090-4500-8000-000000000004',
      '90000000-0090-4200-8000-000000000004', transaction_timestamp(), NULL),
    ('90000000-0090-4500-8000-000000000005',
      '90000000-0090-4200-8000-000000000005', transaction_timestamp(), NULL);

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status, is_personal_default
  ) VALUES (
    '${dependency_project}', '${dependency_workspace}',
    '0090 dependency project', 'active', false
  );
  COMMIT;
"

same_sql="
  SELECT * FROM app_private.leave_organization_membership_v1(
    '${same_actor}', '${same_request}', '${same_workspace}');
"
run_pair same-request "${same_sql}" "${same_sql}" \
  "${request_prefix}${same_request}" '' '' yes

run_pair different-request "
  SELECT * FROM app_private.leave_organization_membership_v1(
    '${different_actor}', '${different_request_one}', '${different_workspace}');
" "
  SELECT * FROM app_private.leave_organization_membership_v1(
    '${different_actor}', '${different_request_two}', '${different_workspace}');
" app_users '42501' 'organization membership self-leave forbidden' no

# This direct INSERT is the database fact produced by accepted invitation 0087.
# The acceptance writer has its own fixture; here the separate transaction and
# post-start active_from_utc isolate self-leave's wall-clock regression.
run_pair membership-begins-after-start "
  SELECT app_user_id FROM app_data.app_users
  WHERE app_user_id = '${future_actor}' FOR UPDATE;
" "
  SELECT 'waiter_start|' || transaction_timestamp();
  SELECT * FROM app_private.leave_organization_membership_v1(
    '${future_actor}', '${future_request}', '${future_workspace}');
" app_users '' '' no "
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    '${future_membership}', '${future_workspace}', '${future_actor}',
    clock_timestamp(), NULL
  );
  SELECT 'membership_inserted|' || active_from_utc
  FROM app_data.organization_memberships
  WHERE organization_membership_id = '${future_membership}';
"

future_output="${temporary_directory}/membership-begins-after-start-second.out"
future_insert_output="${temporary_directory}/membership-begins-after-start-first.out"
future_waiter_start="$(marker_value waiter_start "${future_output}")"
future_inserted_at="$(marker_value membership_inserted "${future_insert_output}")"
future_receipt="$(result_from "${future_output}")"
if [[ -z "${future_waiter_start}" || -z "${future_inserted_at}" \
  || -z "${future_receipt}" ]] \
  || [[ "$(run_psql --tuples-only --no-align --command="
    SELECT
      '${future_waiter_start}'::timestamptz < '${future_inserted_at}'::timestamptz
      AND '${future_inserted_at}'::timestamptz = membership.active_from_utc
      AND split_part('${future_receipt}', '|', 4)::timestamptz >=
        membership.active_from_utc
      AND membership.inactive_from_utc =
        split_part('${future_receipt}', '|', 4)::timestamptz
    FROM app_data.organization_memberships AS membership
    WHERE membership.organization_membership_id = '${future_membership}';
  " | tr -d '[:space:]')" != 't' ]]
then
  echo '锁等待后新开始的 membership 未使用 post-lock wall-clock 成功退出。' >&2
  exit 1
fi

run_pair membership-lost-during-wait "
  SELECT app_user_id FROM app_data.app_users
  WHERE app_user_id = '${loss_actor}' FOR UPDATE;
" "
  SELECT 'waiter_start|' || transaction_timestamp();
  SELECT * FROM app_private.leave_organization_membership_v1(
    '${loss_actor}', '${loss_request}', '${loss_workspace}');
" app_users '42501' 'organization membership self-leave forbidden' no "
  UPDATE app_data.organization_memberships
  SET inactive_from_utc = clock_timestamp()
  WHERE organization_membership_id = '${loss_membership}';
"

run_pair project-dependency-guard "
  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id, project_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    '90000000-0090-4600-8000-000000000001',
    '${dependency_membership}', '${dependency_project}',
    transaction_timestamp(), NULL
  );
" "
  SELECT * FROM app_private.leave_organization_membership_v1(
    '${dependency_actor}', '${dependency_request}', '${dependency_workspace}');
" "${membership_prefix}${dependency_workspace}:${dependency_actor}" \
  '42501' 'organization membership self-leave forbidden' no

# Request drift, a deassociated claim, and a family tombstone remain conflict
# outcomes independent of current membership state.
run_psql --quiet --command="
  INSERT INTO app_private.organization_membership_self_leave_request_claims (
    request_id, actor_app_user_id, organization_workspace_id,
    organization_membership_id, effective_at_utc
  ) VALUES (
    '90000000-0090-4300-8000-000000000017', '${other_actor_id}',
    '${same_workspace}', '90000000-0090-4200-8000-000000000099',
    clock_timestamp()
  );
  UPDATE app_private.organization_membership_self_leave_request_claims
  SET actor_app_user_id = NULL
  WHERE request_id = '90000000-0090-4300-8000-000000000017';
  INSERT INTO app_private.organization_membership_self_leave_request_tombstones (
    claim_family, request_id
  ) VALUES (
    'organization-membership-self-leave:v1',
    '90000000-0090-4300-8000-000000000018'
  );
"

for conflict_case in drift deassociated tombstone; do
  output_file="${temporary_directory}/${conflict_case}.out"
  status=0
  case "${conflict_case}" in
    drift)
      conflict_sql="SELECT * FROM app_private.leave_organization_membership_v1(
        '${other_actor_id}', '${same_request}', '${same_workspace}');"
      ;;
    deassociated)
      conflict_sql="SELECT * FROM app_private.leave_organization_membership_v1(
        '${other_actor_id}', '90000000-0090-4300-8000-000000000017',
        '${same_workspace}');"
      ;;
    tombstone)
      conflict_sql="SELECT * FROM app_private.leave_organization_membership_v1(
        '${other_actor_id}', '90000000-0090-4300-8000-000000000018',
        '${same_workspace}');"
      ;;
  esac
  run_psql --quiet --command="${conflict_sql}" >"${output_file}" 2>&1 \
    || status=$?
  if [[ "${status}" -eq 0 ]]; then
    echo "${conflict_case} conflict 意外成功。" >&2
    exit 1
  fi
  assert_failure "${output_file}" "${conflict_case} conflict" \
    '22023' 'organization membership self-leave idempotency conflict'
done

fact_shape="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_private.organization_membership_self_leave_request_claims
       WHERE request_id = '${same_request}'),
      (SELECT count(*)
       FROM app_private.organization_membership_self_leave_audit_events
       WHERE request_id = '${same_request}'),
      (SELECT count(*)
       FROM app_private.organization_membership_self_leave_request_claims
       WHERE request_id = '${different_request_two}'),
      (SELECT count(*)
       FROM app_private.organization_membership_self_leave_request_claims
       WHERE request_id IN ('${loss_request}', '${dependency_request}')),
      (SELECT count(*)
       FROM app_private.organization_membership_self_leave_audit_events
       WHERE request_id IN ('${loss_request}', '${dependency_request}')),
      (SELECT count(*)
       FROM app_data.project_memberships
       WHERE organization_membership_id = '${dependency_membership}'),
      (SELECT inactive_from_utc IS NULL
       FROM app_data.organization_memberships
       WHERE organization_membership_id = '${dependency_membership}');
  " | tr -d '[:space:]')"

if [[ "${fact_shape}" != '1|1|0|0|0|1|t' ]]; then
  echo "0090 并发事实错误：${fact_shape}" >&2
  exit 1
fi

echo '0090 organization membership self-leave concurrency checks passed.'
