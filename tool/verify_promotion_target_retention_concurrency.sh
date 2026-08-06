#!/usr/bin/env bash

set -euo pipefail

# 两个独立会话同时匿名化同一对象。只能有一个请求成功；最终只保留一个
# 匿名化审计事件，且对象资料和活动分配都已清除。
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -f \
    "${temporary_directory}/first.out" \
    "${temporary_directory}/second.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

issuer='https://retention-concurrency.example.test'
subject='retention-owner'
"${psql_base[@]}" \
  --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');" \
  >/dev/null

context="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT app_user_id, workspace_id, project_id
    FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
    WHERE is_current;
  ")"
IFS='|' read -r app_user_id workspace_id project_id <<< "${context}"
if [[ -z "${app_user_id}" || -z "${workspace_id}" \
  || -z "${project_id}" ]]; then
  echo "对象匿名化并发检查无法取得可信上下文。" >&2
  exit 1
fi

target_id="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --command="
    SELECT target->>'target_id'
    FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid,
      '${workspace_id}'::uuid,
      '${project_id}'::uuid,
      'person',
      '并发匿名化对象',
      '+1 312 555 0188',
      NULL,
      'retention-concurrency-target'
    );
  " | tr -d '[:space:]')"

anonymize_target() {
  local mutation_id="$1"
  "${psql_base[@]}" \
    --command="
      SELECT result
      FROM app_data.apply_promotion_target_retention_action(
        '${app_user_id}'::uuid,
        '${workspace_id}'::uuid,
        '${project_id}'::uuid,
        '${target_id}'::uuid,
        'anonymize',
        'withdrawal',
        '${mutation_id}'
      );
    "
}

anonymize_target 'retention-concurrency-first' \
  >"${temporary_directory}/first.out" 2>&1 &
first_pid=$!
anonymize_target 'retention-concurrency-second' \
  >"${temporary_directory}/second.out" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?

if [[ "${first_status}" -eq 0 && "${second_status}" -eq 0 ]] \
  || [[ "${first_status}" -ne 0 && "${second_status}" -ne 0 ]]; then
  echo "并发匿名化应当恰有一个成功：first=${first_status}, second=${second_status}" >&2
  cat "${temporary_directory}/first.out" >&2
  cat "${temporary_directory}/second.out" >&2
  exit 1
fi

result="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      (SELECT status
       FROM app_data.promotion_targets
       WHERE promotion_target_id = '${target_id}'::uuid),
      (SELECT count(*)
       FROM app_data.promotion_target_assignments
       WHERE promotion_target_id = '${target_id}'::uuid
         AND ended_at IS NULL),
      (SELECT count(*)
       FROM app_data.promotion_target_retention_events
       WHERE promotion_target_id = '${target_id}'::uuid
         AND event_type = 'anonymized');
  ")"
IFS='|' read -r target_status active_assignments event_count <<< "${result}"
if [[ "${target_status}" != 'anonymized' \
  || "${active_assignments}" -ne 0 \
  || "${event_count}" -ne 1 ]]; then
  echo "并发匿名化留下错误状态：status=${target_status}, assignments=${active_assignments}, events=${event_count}" >&2
  exit 1
fi

echo "对象匿名化并发检查通过：一个请求成功，且资料、分配和审计状态一致。"
