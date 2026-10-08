#!/usr/bin/env bash

set -euo pipefail

# Two PostgreSQL sessions prove that export and anonymization linearize on the
# target-first lock order. Synthetic rows remain for dump/restore verification.
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
  local status=$?
  local pid
  for pid in "${child_pids[@]}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
  exit "${status}"
}
trap cleanup EXIT

wait_for_ready_lock() {
  local lock_name="$1"
  local holder_pid="$2"
  local holder_output="$3"
  local probe

  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(hashtextextended('${lock_name}', 0))
          THEN NOT pg_advisory_unlock(hashtextextended('${lock_name}', 0))
        ELSE true
      END;
    " | tr -d '[:space:]')"
    if [[ "${probe}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then
      echo "并发会话未持有 ready lock：${lock_name}" >&2
      sed -n '1,160p' "${holder_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  echo "没有观察到 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_blocked_session() {
  local application_name="$1"
  local waiter_pid="$2"
  local waiter_output="$3"
  local blocked

  for _ in $(seq 1 100); do
    blocked="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1
        FROM pg_stat_activity AS activity
        WHERE activity.application_name = '${application_name}'
          AND cardinality(pg_blocking_pids(activity.pid)) > 0
      );
    " | tr -d '[:space:]')"
    if [[ "${blocked}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo "${application_name} 没有等待行锁。" >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  echo "没有观察到 ${application_name} 的真实阻塞。" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

issuer='https://personal-target-pii-export-concurrency.example.test/auth/v1'
subject='personal-target-pii-export-concurrency-owner'

run_psql --quiet --command="
  SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');
" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
  WHERE is_current
    AND 'export_target_pii' = ANY(capabilities)
    AND 'view_assigned_target_pii' = ANY(capabilities);
")"
IFS='|' read -r app_user_id workspace_id project_id <<<"$(tr -d '[:space:]' <<<"${context}")"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo 'PII 导出并发 fixture 没有取得可信 personal project context。' >&2
  exit 1
fi

first_target='7d500000-0112-4000-8000-000000000001'
second_target='7d500000-0112-4000-8000-000000000002'
run_psql --quiet --command="
  INSERT INTO app_data.promotion_targets (
    promotion_target_id, workspace_id, target_type, display_name,
    phone, email, created_by_app_user_id
  ) VALUES (
    '${first_target}'::uuid, '${workspace_id}'::uuid, 'person',
    'EXPORT_CONCURRENCY_FIRST', '+1 312 555 0121', NULL,
    '${app_user_id}'::uuid
  );
  INSERT INTO app_data.promotion_target_assignments (
    assignment_id, promotion_target_id, app_user_id, assigned_by_app_user_id
  ) VALUES (
    '7d510000-0112-4000-8000-000000000001'::uuid,
    '${first_target}'::uuid, '${app_user_id}'::uuid, '${app_user_id}'::uuid
  );
" >/dev/null

export_first_output="${temporary_directory}/export-first.out"
anonymize_second_output="${temporary_directory}/anonymize-second.out"
export_first_ready='0112-export-first-ready'

PGAPPNAME='0112-export-first' run_psql --quiet --command="
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT octet_length(app_data.prepare_personal_target_pii_export_v1(
    '${issuer}', '${subject}', '${project_id}'::uuid, transaction_timestamp()
  ));
  RESET ROLE;
  SELECT pg_advisory_lock(hashtextextended('${export_first_ready}', 0));
  SELECT pg_sleep(1.5);
  COMMIT;
" >"${export_first_output}" 2>&1 &
export_first_pid=$!
child_pids+=("${export_first_pid}")
wait_for_ready_lock "${export_first_ready}" "${export_first_pid}" "${export_first_output}"

PGAPPNAME='0112-anonymize-second' run_psql --quiet --command="
  BEGIN;
  SELECT * FROM app_data.apply_promotion_target_retention_action(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${first_target}'::uuid, 'anonymize', 'withdrawal',
    '0112-export-first-anonymize-second'
  );
  COMMIT;
" >"${anonymize_second_output}" 2>&1 &
anonymize_second_pid=$!
child_pids+=("${anonymize_second_pid}")
wait_for_blocked_session \
  '0112-anonymize-second' "${anonymize_second_pid}" "${anonymize_second_output}"

export_first_status=0
anonymize_second_status=0
wait "${export_first_pid}" || export_first_status=$?
wait "${anonymize_second_pid}" || anonymize_second_status=$?
if [[ "${export_first_status}" -ne 0 || "${anonymize_second_status}" -ne 0 ]]; then
  echo "导出先行并发失败：export=${export_first_status}, anonymize=${anonymize_second_status}" >&2
  sed -n '1,160p' "${export_first_output}" >&2
  sed -n '1,160p' "${anonymize_second_output}" >&2
  exit 1
fi

first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    (SELECT count(*) FROM app_private.personal_target_pii_export_events
      WHERE actor_app_user_id = '${app_user_id}'::uuid AND target_count = 1),
    (SELECT status FROM app_data.promotion_targets
      WHERE promotion_target_id = '${first_target}'::uuid),
    (SELECT ended_at IS NOT NULL FROM app_data.promotion_target_assignments
      WHERE promotion_target_id = '${first_target}'::uuid);
" | tr -d '[:space:]')"
if [[ "${first_state}" != '1|anonymized|t' ]]; then
  echo "导出先行没有完整导出后再匿名化：${first_state}" >&2
  exit 1
fi

run_psql --quiet --command="
  INSERT INTO app_data.promotion_targets (
    promotion_target_id, workspace_id, target_type, display_name,
    phone, email, created_by_app_user_id
  ) VALUES (
    '${second_target}'::uuid, '${workspace_id}'::uuid, 'person',
    'EXPORT_CONCURRENCY_SECOND', '+1 312 555 0122', NULL,
    '${app_user_id}'::uuid
  );
  INSERT INTO app_data.promotion_target_assignments (
    assignment_id, promotion_target_id, app_user_id, assigned_by_app_user_id
  ) VALUES (
    '7d510000-0112-4000-8000-000000000002'::uuid,
    '${second_target}'::uuid, '${app_user_id}'::uuid, '${app_user_id}'::uuid
  );
" >/dev/null

anonymize_first_output="${temporary_directory}/anonymize-first.out"
export_second_output="${temporary_directory}/export-second.out"
anonymize_first_ready='0112-anonymize-first-ready'

PGAPPNAME='0112-anonymize-first' run_psql --quiet --command="
  BEGIN;
  SELECT * FROM app_data.apply_promotion_target_retention_action(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${second_target}'::uuid, 'anonymize', 'withdrawal',
    '0112-anonymize-first-export-second'
  );
  SELECT pg_advisory_lock(hashtextextended('${anonymize_first_ready}', 0));
  SELECT pg_sleep(1.5);
  COMMIT;
" >"${anonymize_first_output}" 2>&1 &
anonymize_first_pid=$!
child_pids+=("${anonymize_first_pid}")
wait_for_ready_lock "${anonymize_first_ready}" "${anonymize_first_pid}" "${anonymize_first_output}"

PGAPPNAME='0112-export-second' run_psql --quiet --command="
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT octet_length(app_data.prepare_personal_target_pii_export_v1(
    '${issuer}', '${subject}', '${project_id}'::uuid, transaction_timestamp()
  ));
  COMMIT;
" >"${export_second_output}" 2>&1 &
export_second_pid=$!
child_pids+=("${export_second_pid}")
wait_for_blocked_session \
  '0112-export-second' "${export_second_pid}" "${export_second_output}"

anonymize_first_status=0
export_second_status=0
wait "${anonymize_first_pid}" || anonymize_first_status=$?
wait "${export_second_pid}" || export_second_status=$?
if [[ "${anonymize_first_status}" -ne 0 || "${export_second_status}" -ne 0 ]]; then
  echo "匿名化先行并发失败：anonymize=${anonymize_first_status}, export=${export_second_status}" >&2
  sed -n '1,160p' "${anonymize_first_output}" >&2
  sed -n '1,160p' "${export_second_output}" >&2
  exit 1
fi

final_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    count(*),
    count(*) FILTER (WHERE target_count = 1),
    count(*) FILTER (WHERE target_count = 0),
    bool_and(result = 'prepared' AND byte_count > 0)
  FROM app_private.personal_target_pii_export_events
  WHERE actor_app_user_id = '${app_user_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${final_state}" != '2|1|1|t' ]]; then
  echo "匿名化先行没有得到空文件及原子审计：${final_state}" >&2
  exit 1
fi

workspace_subject='personal-target-pii-export-concurrency-workspace-owner'
run_psql --quiet --command="
  SELECT * FROM app_data.bootstrap_personal_context(
    '${issuer}', '${workspace_subject}'
  );
" >/dev/null
workspace_context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${workspace_subject}')
  WHERE is_current;
")"
IFS='|' read -r workspace_app_user_id revoked_workspace_id workspace_project_id \
  <<<"$(tr -d '[:space:]' <<<"${workspace_context}")"
for context_id in \
  "${workspace_app_user_id}" "${revoked_workspace_id}" "${workspace_project_id}"; do
  if [[ ! "${context_id}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo 'workspace 失效并发 fixture 没有取得可信上下文。' >&2
    exit 1
  fi
done

workspace_export_output="${temporary_directory}/workspace-export-first.out"
workspace_delete_output="${temporary_directory}/workspace-delete-second.out"
workspace_export_ready='0112-workspace-export-first-ready'
PGAPPNAME='0112-workspace-export-first' run_psql --quiet --command="
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT octet_length(app_data.prepare_personal_target_pii_export_v1(
    '${issuer}', '${workspace_subject}', '${workspace_project_id}'::uuid,
    transaction_timestamp()
  ));
  RESET ROLE;
  SELECT pg_advisory_lock(hashtextextended('${workspace_export_ready}', 0));
  SELECT pg_sleep(1.5);
  COMMIT;
" >"${workspace_export_output}" 2>&1 &
workspace_export_pid=$!
child_pids+=("${workspace_export_pid}")
wait_for_ready_lock \
  "${workspace_export_ready}" "${workspace_export_pid}" "${workspace_export_output}"

PGAPPNAME='0112-workspace-delete-second' run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.workspaces
  SET deleted_at = transaction_timestamp()
  WHERE workspace_id = '${revoked_workspace_id}'::uuid;
  COMMIT;
" >"${workspace_delete_output}" 2>&1 &
workspace_delete_pid=$!
child_pids+=("${workspace_delete_pid}")
wait_for_blocked_session \
  '0112-workspace-delete-second' "${workspace_delete_pid}" "${workspace_delete_output}"

workspace_export_status=0
workspace_delete_status=0
wait "${workspace_export_pid}" || workspace_export_status=$?
wait "${workspace_delete_pid}" || workspace_delete_status=$?
workspace_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    deleted_at IS NOT NULL,
    (SELECT count(*)
     FROM app_private.personal_target_pii_export_events
     WHERE actor_app_user_id = '${workspace_app_user_id}'::uuid
       AND workspace_id = '${revoked_workspace_id}'::uuid
       AND target_count = 0)
  FROM app_data.workspaces
  WHERE workspace_id = '${revoked_workspace_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${workspace_export_status}" -ne 0 || "${workspace_delete_status}" -ne 0 \
  || "${workspace_state}" != 't|1' ]]; then
  echo "导出先行没有在完整空文件后线性化 workspace 失效：${workspace_state}" >&2
  sed -n '1,160p' "${workspace_export_output}" >&2
  sed -n '1,160p' "${workspace_delete_output}" >&2
  exit 1
fi

inactive_subject='personal-target-pii-export-concurrency-inactive-owner'
run_psql --quiet --command="
  SELECT * FROM app_data.bootstrap_personal_context(
    '${issuer}', '${inactive_subject}'
  );
" >/dev/null
inactive_context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${inactive_subject}')
  WHERE is_current;
")"
IFS='|' read -r inactive_app_user_id inactive_workspace_id inactive_project_id \
  <<<"$(tr -d '[:space:]' <<<"${inactive_context}")"
for context_id in \
  "${inactive_app_user_id}" "${inactive_workspace_id}" "${inactive_project_id}"; do
  if [[ ! "${context_id}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo 'app user 失效并发 fixture 没有取得可信上下文。' >&2
    exit 1
  fi
done

user_status_output="${temporary_directory}/user-status-first.out"
user_export_output="${temporary_directory}/user-export-second.out"
user_status_ready='0112-user-status-first-ready'
PGAPPNAME='0112-user-status-first' run_psql --quiet --command="
  BEGIN;
  UPDATE app_data.app_users
  SET status = 'deletion_pending'
  WHERE app_user_id = '${inactive_app_user_id}'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${user_status_ready}', 0));
  SELECT pg_sleep(1.5);
  COMMIT;
" >"${user_status_output}" 2>&1 &
user_status_pid=$!
child_pids+=("${user_status_pid}")
wait_for_ready_lock \
  "${user_status_ready}" "${user_status_pid}" "${user_status_output}"

PGAPPNAME='0112-user-export-second' run_psql --set=VERBOSITY=verbose --command="
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.prepare_personal_target_pii_export_v1(
    '${issuer}', '${inactive_subject}', '${inactive_project_id}'::uuid,
    transaction_timestamp()
  );
" >"${user_export_output}" 2>&1 &
user_export_pid=$!
child_pids+=("${user_export_pid}")
wait_for_blocked_session \
  '0112-user-export-second' "${user_export_pid}" "${user_export_output}"

user_status_status=0
user_export_status=0
wait "${user_status_pid}" || user_status_status=$?
wait "${user_export_pid}" || user_export_status=$?
inactive_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    status,
    (SELECT count(*)
     FROM app_private.personal_target_pii_export_events
     WHERE actor_app_user_id = '${inactive_app_user_id}'::uuid)
  FROM app_data.app_users
  WHERE app_user_id = '${inactive_app_user_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${user_status_status}" -ne 0 || "${user_export_status}" -eq 0 \
  || "${inactive_state}" != 'deletion_pending|0' ]] \
  || ! grep -Fq '42501: personal target PII export scope is forbidden' \
    "${user_export_output}"; then
  echo "app user 失效先行后导出未失败关闭：${inactive_state}" >&2
  sed -n '1,160p' "${user_status_output}" >&2
  sed -n '1,160p' "${user_export_output}" >&2
  exit 1
fi

echo '个人空间 PII 导出并发检查通过：target→assignment 锁序及身份/workspace 失效均已线性化。'
