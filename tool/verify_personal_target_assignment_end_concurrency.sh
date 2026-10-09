#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
run_psql_as() { PGAPPNAME="$1" "${psql_base[@]}" "${@:2}"; }

temporary_directory="$(mktemp -d)"
child_pids=()
gate_pid=''
gate_name=''
cleanup() {
  exec 3>&- 2>/dev/null || true
  exec 4>&- 2>/dev/null || true
  local pid
  for pid in "${child_pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_exact_blocker() {
  local waiter_app="$1" blocker_app="$2" output_path="$3" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="
      SELECT waiting.pid || '|' || blocker.pid
      FROM pg_catalog.pg_stat_activity AS waiting
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiting.pid)) AS blocked(pid)
        ON true
      JOIN pg_catalog.pg_stat_activity AS blocker ON blocker.pid = blocked.pid
      WHERE waiting.application_name = '${waiter_app}'
        AND waiting.wait_event_type = 'Lock'
        AND blocker.application_name = '${blocker_app}'
      LIMIT 1;
    " | tr -d '[:space:]')"
    if [[ "${pair}" == *'|'* ]]; then
      return
    fi
    sleep 0.05
  done
  echo "未观察到精确 blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
  sed -n '1,120p' "${output_path}" >&2
  exit 1
}

start_holder() {
  local app_name="$1" ready_name="$2" lock_sql="$3"
  gate_name="${ready_name}"
  mkfifo "${temporary_directory}/gate.fifo"
  PGAPPNAME="${app_name}" "${psql_base[@]}" \
    <"${temporary_directory}/gate.fifo" \
    >"${temporary_directory}/gate.out" 2>&1 &
  gate_pid=$!
  child_pids+=("${gate_pid}")
  exec 3>"${temporary_directory}/gate.fifo"
  printf 'BEGIN; %s SELECT pg_advisory_lock(hashtextextended(\047%s\047, 0));\n' \
    "${lock_sql}" "${ready_name}" >&3
  for _ in $(seq 1 100); do
    local ready
    ready="$(run_psql --tuples-only --no-align --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(hashtextextended('${ready_name}', 0))
        THEN NOT pg_advisory_unlock(hashtextextended('${ready_name}', 0))
        ELSE true
      END;
    " | tr -d '[:space:]')"
    [[ "${ready}" == 't' ]] && return
    sleep 0.05
  done
  echo "无法启动 assignment end concurrency holder：${app_name}" >&2
  exit 1
}

release_holder() {
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "${gate_pid}"
  rm -f "${temporary_directory}/gate.fifo"
  gate_pid=''
  gate_name=''
}

assert_true() {
  local label="$1" sql="$2" result
  result="$(run_psql --tuples-only --no-align --command="${sql}" | tr -d '[:space:]')"
  if [[ "${result}" != 't' ]]; then
    echo "${label} invariant failed: ${result}" >&2
    exit 1
  fi
}

run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7ed-assignment-end-concurrency.example.test/auth/v1'
subject="7ed-assignment-end-owner-${run_token}"
run_psql --quiet --command="
  SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');
" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
  WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id <<<"${context}"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo '0118 fixture 无法取得 personal project context。' >&2
  exit 1
fi

create_pair() {
  local label="$1" request_base="$2" target_ids first_target second_target preview_id
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0118 ${label} first ${run_token}',
      '+1 773 555 0118', 'first-0118-${run_token}@example.test',
      '${request_base}-first'
    );
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0118 ${label} second ${run_token}',
      '+1 773 555 0118', 'second-0118-${run_token}@example.test',
      '${request_base}-second'
    );
  " >/dev/null
  target_ids="$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT
      (SELECT promotion_target_id FROM app_data.promotion_targets
       WHERE workspace_id = '${workspace_id}'::uuid
         AND display_name = '0118 ${label} first ${run_token}'),
      (SELECT promotion_target_id FROM app_data.promotion_targets
       WHERE workspace_id = '${workspace_id}'::uuid
         AND display_name = '0118 ${label} second ${run_token}');
  " | tr -d '[:space:]')"
  IFS='|' read -r first_target second_target <<<"${target_ids}"
  if [[ ! "${first_target}" =~ ^[0-9a-f-]{36}$ \
    || ! "${second_target}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "0118 ${label} fixture 未能创建目标对。" >&2
    exit 1
  fi
  preview_id="$(run_psql --tuples-only --no-align --command="
    SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
      '${issuer}', '${subject}', '${project_id}'::uuid,
      '${first_target}'::uuid, '${second_target}'::uuid
    );
  " | tr -d '[:space:]')"
  if [[ ! "${preview_id}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "0118 ${label} fixture 未能创建 preview receipt。" >&2
    exit 1
  fi
  printf '%s|%s|%s\n' "${first_target}" "${second_target}" "${preview_id}"
}

assignment_for() {
  run_psql --tuples-only --no-align --command="
    SELECT assignment_id
    FROM app_data.promotion_target_assignments
    WHERE promotion_target_id = '$1'::uuid
      AND app_user_id = '${app_user_id}'::uuid
      AND ended_at IS NULL;
  " | tr -d '[:space:]'
}

activate_sql() {
  local request_id="$1" preview_id="$2" first_target="$3" second_target="$4"
  printf "SELECT app_private.activate_personal_target_merge_generation_v2(\n  '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid,\n  '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid\n);" \
    "${app_user_id}" "${project_id}" "${request_id}" "${preview_id}" \
    "${first_target}" "${first_target}" "${second_target}" "${first_target}"
}

plain_target="$(run_psql --quiet --tuples-only --no-align --command="
  SELECT target FROM app_data.create_promotion_target(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    'person', '0118 duplicate end ${run_token}', NULL, NULL,
    '0118-${run_token}-duplicate'
  );
" >/dev/null
run_psql --tuples-only --no-align --command="
  SELECT promotion_target_id FROM app_data.promotion_targets
  WHERE workspace_id = '${workspace_id}'::uuid
    AND display_name = '0118 duplicate end ${run_token}';
" | tr -d '[:space:]')"
plain_assignment="$(assignment_for "${plain_target}")"
first_holder="assignment-end-same-holder-${run_token}"
first_app="assignment-end-same-first-${run_token}"
second_app="assignment-end-same-second-${run_token}"
start_holder "${first_holder}" "assignment-end-same-ready-${run_token}" \
  "SELECT fence_key FROM app_private.personal_target_merge_generation_fence_v1 WHERE fence_key FOR UPDATE;"
run_psql_as "${first_app}" --tuples-only --no-align --quiet --command="
  SELECT app_data.end_personal_target_assignment_v1(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${plain_assignment}'::uuid
  );
" >"${temporary_directory}/same-first.out" 2>&1 &
first_pid=$!
child_pids+=("${first_pid}")
wait_for_exact_blocker "${first_app}" "${first_holder}" "${temporary_directory}/same-first.out"
run_psql_as "${second_app}" --tuples-only --no-align --quiet --command="
  SELECT app_data.end_personal_target_assignment_v1(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${plain_assignment}'::uuid
  );
" >"${temporary_directory}/same-second.out" 2>&1 &
second_pid=$!
child_pids+=("${second_pid}")
wait_for_exact_blocker "${second_app}" "${first_app}" "${temporary_directory}/same-second.out"
release_holder
wait "${first_pid}"
wait "${second_pid}"
first_result="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "${temporary_directory}/same-first.out")"
second_result="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "${temporary_directory}/same-second.out")"
if [[ "${first_result}" != "${second_result}" ]]; then
  echo "同 assignment 并发结束返回时间不一致：${first_result} vs ${second_result}" >&2
  exit 1
fi
assert_true 'same assignment end replay' "
  SELECT (SELECT count(*) = 1
          FROM app_private.personal_target_assignment_end_events_v1
          WHERE assignment_id = '${plain_assignment}'::uuid
            AND actor_app_user_id = '${app_user_id}'::uuid
            AND workspace_id = '${workspace_id}'::uuid
            AND project_id = '${project_id}'::uuid
            AND ended_at_utc = '${first_result}'::timestamptz)
     AND (SELECT ended_at = '${first_result}'::timestamptz
          FROM app_data.promotion_target_assignments
          WHERE assignment_id = '${plain_assignment}'::uuid);
"

IFS='|' read -r end_first_target end_first_other end_first_preview \
  <<<"$(create_pair end-first 0118-${run_token}-endfirst)"
end_first_assignment="$(assignment_for "${end_first_target}")"
end_first_request="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]')"
target_holder="assignment-end-target-holder-${run_token}"
end_first_app="assignment-end-first-writer-${run_token}"
activation_after_app="assignment-end-first-activation-${run_token}"
start_holder "${target_holder}" "assignment-end-target-ready-${run_token}" \
  "SELECT promotion_target_id FROM app_data.promotion_targets WHERE promotion_target_id = '${end_first_target}'::uuid FOR UPDATE;"
run_psql_as "${end_first_app}" --tuples-only --no-align --quiet --command="
  SELECT app_data.end_personal_target_assignment_v1(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${end_first_assignment}'::uuid
  );
" >"${temporary_directory}/end-first.out" 2>&1 &
end_first_pid=$!
child_pids+=("${end_first_pid}")
wait_for_exact_blocker "${end_first_app}" "${target_holder}" "${temporary_directory}/end-first.out"
run_psql_as "${activation_after_app}" --tuples-only --no-align --quiet --command="$(activate_sql \
  "${end_first_request}" "${end_first_preview}" \
  "${end_first_target}" "${end_first_other}")" \
  >"${temporary_directory}/activation-after-end.out" 2>&1 &
activation_after_pid=$!
child_pids+=("${activation_after_pid}")
wait_for_exact_blocker "${activation_after_app}" "${end_first_app}" \
  "${temporary_directory}/activation-after-end.out"
release_holder
wait "${end_first_pid}"
end_first_status=0
wait "${activation_after_pid}" || end_first_status=$?
if [[ "${end_first_status}" -eq 0 ]] \
  || ! grep -q 'personal target merge generation activation is forbidden' \
    "${temporary_directory}/activation-after-end.out"; then
  echo 'end-first activation did not fail closed as expected.' >&2
  sed -n '1,120p' "${temporary_directory}/activation-after-end.out" >&2
  exit 1
fi
assert_true 'end-first activation has no side effects' "
  SELECT NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_generations_v1 AS generation
    JOIN app_private.personal_target_merge_generation_members_v1 AS member
      USING (generation_id)
    WHERE member.promotion_target_id IN (
      '${end_first_target}'::uuid, '${end_first_other}'::uuid
    )
  )
  AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1
    WHERE actor_app_user_id = '${app_user_id}'::uuid
      AND request_id = '${end_first_request}'::uuid
  )
  AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_activation_audit_v1
    WHERE actor_app_user_id = '${app_user_id}'::uuid
      AND request_id = '${end_first_request}'::uuid
  )
  AND (SELECT count(*) = 1
       FROM app_private.personal_target_assignment_end_events_v1
       WHERE assignment_id = '${end_first_assignment}'::uuid);
"

IFS='|' read -r activation_first_target activation_first_other activation_first_preview \
  <<<"$(create_pair activation-first 0118-${run_token}-activationfirst)"
activation_first_assignment="$(assignment_for "${activation_first_target}")"
activation_first_request="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]')"
activation_holder="assignment-activation-first-holder-${run_token}"
activation_ready="assignment-activation-first-ready-${run_token}"
mkfifo "${temporary_directory}/activation.fifo"
PGAPPNAME="${activation_holder}" "${psql_base[@]}" \
  <"${temporary_directory}/activation.fifo" \
  >"${temporary_directory}/activation-holder.out" 2>&1 &
activation_holder_pid=$!
child_pids+=("${activation_holder_pid}")
exec 4>"${temporary_directory}/activation.fifo"
printf 'BEGIN; %s SELECT pg_advisory_lock(hashtextextended(\047%s\047, 0));\n' \
  "$(activate_sql "${activation_first_request}" "${activation_first_preview}" \
    "${activation_first_target}" "${activation_first_other}")" \
  "${activation_ready}" >&4
activation_is_ready=0
for _ in $(seq 1 100); do
  ready="$(run_psql --tuples-only --no-align --command="
    SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('${activation_ready}', 0))
      THEN NOT pg_advisory_unlock(hashtextextended('${activation_ready}', 0))
      ELSE true
    END;
  " | tr -d '[:space:]')"
  if [[ "${ready}" == 't' ]]; then activation_is_ready=1; break; fi
  sleep 0.05
done
if [[ "${activation_is_ready}" -ne 1 ]]; then
  echo 'activation-first session did not finish activation while retaining its transaction.' >&2
  sed -n '1,120p' "${temporary_directory}/activation-holder.out" >&2
  exit 1
fi
end_after_activation_app="assignment-end-after-activation-${run_token}"
run_psql_as "${end_after_activation_app}" --tuples-only --no-align --quiet --command="
  SELECT app_data.end_personal_target_assignment_v1(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${activation_first_assignment}'::uuid
  );
" >"${temporary_directory}/end-after-activation.out" 2>&1 &
end_after_activation_pid=$!
child_pids+=("${end_after_activation_pid}")
wait_for_exact_blocker "${end_after_activation_app}" "${activation_holder}" \
  "${temporary_directory}/end-after-activation.out"
printf 'COMMIT;\\q\n' >&4
exec 4>&-
wait "${activation_holder_pid}"
rm -f "${temporary_directory}/activation.fifo"
activation_holder_pid=''
end_after_activation_status=0
wait "${end_after_activation_pid}" || end_after_activation_status=$?
if [[ "${end_after_activation_status}" -eq 0 ]] \
  || ! grep -q 'personal target merge must be split before ending assignment' \
    "${temporary_directory}/end-after-activation.out"; then
  echo 'activation-first last assignment end did not fail closed as expected.' >&2
  sed -n '1,120p' "${temporary_directory}/end-after-activation.out" >&2
  exit 1
fi
assert_true 'activation-first end has no side effects' "
  SELECT EXISTS (
    SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1
    WHERE actor_app_user_id = '${app_user_id}'::uuid
      AND request_id = '${activation_first_request}'::uuid
      AND preview_id = '${activation_first_preview}'::uuid
  )
  AND NOT EXISTS (
    SELECT 1 FROM app_private.personal_target_assignment_end_events_v1
    WHERE assignment_id = '${activation_first_assignment}'::uuid
  )
  AND (SELECT ended_at IS NULL FROM app_data.promotion_target_assignments
       WHERE assignment_id = '${activation_first_assignment}'::uuid);
"

echo 'assignment end concurrency passed: exact replay and both activation orderings.'
