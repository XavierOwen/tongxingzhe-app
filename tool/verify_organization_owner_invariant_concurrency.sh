#!/usr/bin/env bash

set -euo pipefail

# Independent sessions prove the governance lock is taken before the existing
# membership lock and that owner grants serialize with account-status changes.
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

  echo "没有观察到并发持锁：${lock_name}" >&2
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

  echo "没有观察到并发等待：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

assert_fixed_owner_error() {
  local output_file="$1"
  local label="$2"

  if ! grep -q '23514: organization must retain an active owner' "${output_file}"; then
    echo "${label} 没有返回固定 owner invariant 错误。" >&2
    sed -n '1,160p' "${output_file}" >&2
    exit 1
  fi
}

lock_order_workspace_id='85120000-0000-4000-8000-000000000001'
lock_order_user_id='85110000-0000-4000-8000-000000000001'
lock_order_membership_id='85140000-0000-4000-8000-000000000001'
lock_order_owner_id='85150000-0000-4000-8000-000000000001'
lock_order_membership_lock="organization-membership:${lock_order_workspace_id}:${lock_order_user_id}"
lock_order_governance_lock="organization-governance:${lock_order_workspace_id}"
lock_order_ready_lock='85-owner-invariant-membership-holder-ready'

status_workspace_id='85220000-0000-4000-8000-000000000001'
status_original_user_id='85210000-0000-4000-8000-000000000001'
status_replacement_user_id='85210000-0000-4000-8000-000000000002'
status_original_membership_id='85240000-0000-4000-8000-000000000001'
status_replacement_membership_id='85240000-0000-4000-8000-000000000002'
status_original_owner_id='85250000-0000-4000-8000-000000000001'
status_replacement_owner_id='85250000-0000-4000-8000-000000000002'
status_governance_lock="organization-governance:${status_workspace_id}"
status_ready_lock='85-owner-invariant-grant-ready'

echo '建立 0085 owner invariant 并发基线。'
run_psql --quiet --command="
  BEGIN;

  INSERT INTO app_data.app_users (app_user_id, status) VALUES
    ('${lock_order_user_id}'::uuid, 'active'),
    ('${status_original_user_id}'::uuid, 'active'),
    ('${status_replacement_user_id}'::uuid, 'active');

  INSERT INTO app_data.workspaces (
    workspace_id,
    workspace_kind,
    display_name,
    personal_owner_app_user_id,
    created_at
  ) VALUES
    (
      '${lock_order_workspace_id}'::uuid,
      'organization',
      '0085 lock-order organization',
      NULL,
      transaction_timestamp()
    ),
    (
      '${status_workspace_id}'::uuid,
      'organization',
      '0085 status organization',
      NULL,
      transaction_timestamp()
    );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES
    (
      '${lock_order_membership_id}'::uuid,
      '${lock_order_workspace_id}'::uuid,
      '${lock_order_user_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${status_original_membership_id}'::uuid,
      '${status_workspace_id}'::uuid,
      '${status_original_user_id}'::uuid,
      transaction_timestamp(),
      NULL
    );

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES
    (
      '${lock_order_owner_id}'::uuid,
      '${lock_order_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    ),
    (
      '${status_original_owner_id}'::uuid,
      '${status_original_membership_id}'::uuid,
      transaction_timestamp(),
      NULL
    );

  COMMIT;
" >/dev/null

echo '验证 membership 路径先持有 governance lock，再等待 membership lock。'
lock_holder_output="${temporary_directory}/membership-lock-holder.out"
membership_close_output="${temporary_directory}/membership-close.out"
owner_close_output="${temporary_directory}/owner-close.out"

run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${lock_order_membership_lock}', 0)
  );
  SELECT pg_advisory_lock(
    hashtextextended('${lock_order_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamptz := clock_timestamp() + interval '15 seconds';
    membership_waiting boolean;
    governance_waiting boolean;
  BEGIN
    LOOP
      SELECT
        EXISTS (
          SELECT 1
          FROM pg_locks AS waiting_lock
          WHERE waiting_lock.locktype = 'advisory'
            AND NOT waiting_lock.granted
            AND waiting_lock.classid::bigint =
              ((hashtextextended('${lock_order_membership_lock}', 0) >> 32)
                & 4294967295)::bigint
            AND waiting_lock.objid::bigint =
              (hashtextextended('${lock_order_membership_lock}', 0)
                & 4294967295)::bigint
        ),
        EXISTS (
          SELECT 1
          FROM pg_locks AS waiting_lock
          WHERE waiting_lock.locktype = 'advisory'
            AND NOT waiting_lock.granted
            AND waiting_lock.classid::bigint =
              ((hashtextextended('${lock_order_governance_lock}', 0) >> 32)
                & 4294967295)::bigint
            AND waiting_lock.objid::bigint =
              (hashtextextended('${lock_order_governance_lock}', 0)
                & 4294967295)::bigint
        )
      INTO membership_waiting, governance_waiting;

      EXIT WHEN membership_waiting AND governance_waiting;
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION '0085 lock-order waiters were not observed';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${lock_holder_output}" 2>&1 &
lock_holder_pid=$!
child_pids+=("${lock_holder_pid}")
wait_for_lock_holder \
  "${lock_order_ready_lock}" \
  "${lock_holder_pid}" \
  "${lock_holder_output}"

run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.organization_memberships
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_membership_id = '${lock_order_membership_id}'::uuid;
  COMMIT;
" >"${membership_close_output}" 2>&1 &
membership_close_pid=$!
child_pids+=("${membership_close_pid}")
wait_for_advisory_waiter \
  "${lock_order_membership_lock}" \
  "${membership_close_pid}" \
  "${membership_close_output}"

run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.organization_owner_assignments
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_owner_assignment_id = '${lock_order_owner_id}'::uuid;
  COMMIT;
" >"${owner_close_output}" 2>&1 &
owner_close_pid=$!
child_pids+=("${owner_close_pid}")

lock_holder_status=0
membership_close_status=0
owner_close_status=0
wait "${lock_holder_pid}" || lock_holder_status=$?
wait "${membership_close_pid}" || membership_close_status=$?
wait "${owner_close_pid}" || owner_close_status=$?

if [[ "${lock_holder_status}" -ne 0 \
  || "${membership_close_status}" -eq 0 \
  || "${owner_close_status}" -eq 0 ]]; then
  echo "0085 lock-order 结果错误：holder=${lock_holder_status}, membership=${membership_close_status}, owner=${owner_close_status}" >&2
  sed -n '1,160p' "${lock_holder_output}" >&2
  sed -n '1,160p' "${membership_close_output}" >&2
  sed -n '1,160p' "${owner_close_output}" >&2
  exit 1
fi
assert_fixed_owner_error "${membership_close_output}" '唯一 owner membership close'
assert_fixed_owner_error "${owner_close_output}" '唯一 owner assignment close'

lock_order_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    membership.inactive_from_utc IS NULL,
    owner_assignment.inactive_from_utc IS NULL,
    app_user.status
  FROM app_data.organization_memberships AS membership
  JOIN app_data.organization_owner_assignments AS owner_assignment
    ON owner_assignment.organization_membership_id =
      membership.organization_membership_id
  JOIN app_data.app_users AS app_user
    ON app_user.app_user_id = membership.app_user_id
  WHERE membership.organization_membership_id =
    '${lock_order_membership_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${lock_order_state}" != 't|t|active' ]]; then
  echo "失败的 last-owner 事务留下了部分状态：${lock_order_state}" >&2
  exit 1
fi

echo '验证 membership grant 先锁 user row，再等待 governance lock。'
status_holder_output="${temporary_directory}/status-governance-holder.out"
grant_output="${temporary_directory}/replacement-grant.out"
status_output="${temporary_directory}/status-update.out"

run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${status_governance_lock}', 0)
  );
  SELECT pg_advisory_lock(hashtextextended('${status_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    wait_deadline timestamptz := clock_timestamp() + interval '15 seconds';
    governance_waiting boolean;
    user_row_waiting boolean;
  BEGIN
    LOOP
      SELECT
        EXISTS (
          SELECT 1
          FROM pg_locks AS waiting_lock
          WHERE waiting_lock.locktype = 'advisory'
            AND NOT waiting_lock.granted
            AND waiting_lock.classid::bigint =
              ((hashtextextended('${status_governance_lock}', 0) >> 32)
                & 4294967295)::bigint
            AND waiting_lock.objid::bigint =
              (hashtextextended('${status_governance_lock}', 0)
                & 4294967295)::bigint
        ),
        EXISTS (
          SELECT 1
          FROM pg_locks AS waiting_lock
          WHERE NOT waiting_lock.granted
            AND (
              waiting_lock.locktype = 'transactionid'
              OR (
                waiting_lock.locktype = 'tuple'
                AND waiting_lock.relation = 'app_data.app_users'::regclass
              )
            )
        )
      INTO governance_waiting, user_row_waiting;

      EXIT WHEN governance_waiting AND user_row_waiting;
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION '0085 user-before-governance waiters were not observed';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${status_holder_output}" 2>&1 &
status_holder_pid=$!
child_pids+=("${status_holder_pid}")
wait_for_lock_holder \
  "${status_ready_lock}" \
  "${status_holder_pid}" \
  "${status_holder_output}"

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    '${status_replacement_membership_id}'::uuid,
    '${status_workspace_id}'::uuid,
    '${status_replacement_user_id}'::uuid,
    transaction_timestamp(),
    NULL
  );
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    '${status_replacement_owner_id}'::uuid,
    '${status_replacement_membership_id}'::uuid,
    transaction_timestamp(),
    NULL
  );
  COMMIT;
" >"${grant_output}" 2>&1 &
grant_pid=$!
child_pids+=("${grant_pid}")
wait_for_advisory_waiter \
  "${status_governance_lock}" \
  "${grant_pid}" \
  "${grant_output}"

run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.app_users
  SET status = 'deletion_pending'
  WHERE app_user_id = '${status_replacement_user_id}'::uuid;
  COMMIT;
" >"${status_output}" 2>&1 &
status_pid=$!
child_pids+=("${status_pid}")

status_holder_status=0
grant_status=0
status_status=0
wait "${status_holder_pid}" || status_holder_status=$?
wait "${grant_pid}" || grant_status=$?
wait "${status_pid}" || status_status=$?
if [[ "${status_holder_status}" -ne 0 \
  || "${grant_status}" -ne 0 \
  || "${status_status}" -ne 0 ]]; then
  echo "membership/status 锁序失败：holder=${status_holder_status}, grant=${grant_status}, status=${status_status}" >&2
  sed -n '1,160p' "${status_holder_output}" >&2
  sed -n '1,160p' "${grant_output}" >&2
  sed -n '1,160p' "${status_output}" >&2
  exit 1
fi

status_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    replacement_user.status,
    count(*) FILTER (
      WHERE current_user_row.status = 'active'
        AND transaction_timestamp() <@ tstzrange(
          membership.active_from_utc,
          membership.inactive_from_utc,
          '[)'
        )
        AND transaction_timestamp() <@ tstzrange(
          owner_assignment.active_from_utc,
          owner_assignment.inactive_from_utc,
          '[)'
        )
    )
  FROM app_data.app_users AS replacement_user
  CROSS JOIN app_data.organization_memberships AS membership
  JOIN app_data.organization_owner_assignments AS owner_assignment
    ON owner_assignment.organization_membership_id =
      membership.organization_membership_id
  JOIN app_data.app_users AS current_user_row
    ON current_user_row.app_user_id = membership.app_user_id
  WHERE replacement_user.app_user_id = '${status_replacement_user_id}'::uuid
    AND membership.organization_workspace_id = '${status_workspace_id}'::uuid
  GROUP BY replacement_user.status;
" | tr -d '[:space:]')"
if [[ "${status_state}" != 'deletion_pending|1' ]]; then
  echo "membership/status 最终状态错误：${status_state}" >&2
  exit 1
fi

echo '0085 organization active-owner invariant concurrency checks passed.'
