#!/usr/bin/env bash

set -euo pipefail

# Independent PostgreSQL sessions prove request replay, receipt consumption,
# cleanup ordering, and the existing generation-fence writer ordering.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }

temporary_directory="$(mktemp -d)"
child_pids=()
gate_name=''
gate_pid=''
started_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  if [[ -n "${app_user_id:-}" ]]; then
    run_psql --quiet --command="
      UPDATE app_data.app_users SET status = 'active'
      WHERE app_user_id = '${app_user_id}'::uuid;
    " >/dev/null 2>&1 || true
  fi
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
      echo "${waiter_app}: exact waiter/blocker PID ${pair}"
      return
    fi
    sleep 0.05
  done
  echo "未观察到精确 blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
  sed -n '1,120p' "${output_path}" >&2
  exit 1
}

start_gate() {
  gate_name="$1"
  local gate_app="$2"
  mkfifo "${temporary_directory}/gate.fifo"
  PGAPPNAME="${gate_app}" "${psql_base[@]}" <"${temporary_directory}/gate.fifo" \
    >"${temporary_directory}/gate.out" 2>&1 &
  gate_pid=$!
  child_pids+=("${gate_pid}")
  exec 3>"${temporary_directory}/gate.fifo"
  printf "SELECT pg_advisory_lock(hashtextextended('%s', 0));\n" "${gate_name}" >&3
  for _ in $(seq 1 100); do
    local held
    held="$(run_psql --tuples-only --no-align --command="
      SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('${gate_name}', 0))
        THEN NOT pg_advisory_unlock(hashtextextended('${gate_name}', 0))
        ELSE true END;
    " | tr -d '[:space:]')"
    [[ "${held}" == 't' ]] && return
    sleep 0.05
  done
  echo "无法取得 0117 concurrency gate：${gate_name}" >&2
  exit 1
}

release_gate() {
  printf "SELECT pg_advisory_unlock(hashtextextended('%s', 0));\n\\q\n" \
    "${gate_name}" >&3
  exec 3>&-
  wait "${gate_pid}"
  rm -f "${temporary_directory}/gate.fifo"
  gate_name=''
  gate_pid=''
}

new_uuid() {
  run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]'
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
issuer='https://7d560000-0117-merge-receipt.example.test/auth/v1'
subject="7d570000-0117-merge-receipt-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
  WHERE is_current;
")"
IFS='|' read -r app_user_id workspace_id project_id \
  <<<"$(tr -d '[:space:]' <<<"${context}")"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo '0117 fixture 无法取得 personal project context。' >&2
  exit 1
fi

create_pair() {
  local label="$1" suffix="$2" first_request second_request pair_ids first second preview_id
  first_request="0117-${run_token}-${suffix}a"
  second_request="0117-${run_token}-${suffix}b"
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0117 ${label} first ${run_token}',
      '+1 773 555 0117', 'merge-0117@example.test', '${first_request}'
    );
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0117 ${label} second ${run_token}',
      '+1 773 555 0117', 'merge-0117@example.test', '${second_request}'
    );
  " >/dev/null
  pair_ids="$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT (array_agg(promotion_target_id ORDER BY promotion_target_id))[1],
           (array_agg(promotion_target_id ORDER BY promotion_target_id))[2]
    FROM app_data.promotion_targets
    WHERE workspace_id = '${workspace_id}'::uuid
      AND display_name IN (
        '0117 ${label} first ${run_token}',
        '0117 ${label} second ${run_token}'
      );
  " | tr -d '[:space:]')"
  IFS='|' read -r first second <<<"${pair_ids}"
  if [[ ! "${first}" =~ ^[0-9a-f-]{36}$ || ! "${second}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "0117 ${label} fixture 未能创建两个目标。" >&2
    exit 1
  fi
  preview_id="$(run_psql --tuples-only --no-align --command="
    SELECT preview.preview_id
    FROM app_data.preview_personal_target_pair_v1(
      '${issuer}', '${subject}', '${project_id}'::uuid,
      '${first}'::uuid, '${second}'::uuid
    ) AS preview;
  " | tr -d '[:space:]')"
  if [[ ! "${preview_id}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "0117 ${label} fixture 未能创建 preview receipt。" >&2
    exit 1
  fi
  printf '%s|%s|%s\n' "${first}" "${second}" "${preview_id}"
}

activation_sql() {
  local request_id="$1" preview_id="$2" first="$3" second="$4"
  printf "SELECT app_private.activate_personal_target_merge_generation_v2(\n  '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid,\n  '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid\n);" \
    "${app_user_id}" "${project_id}" "${request_id}" "${preview_id}" \
    "${first}" "${first}" "${second}" "${first}"
}

assert_activated() {
  local label="$1" request_id="$2" preview_id="$3" first="$4" second="$5"
  assert_true "${label}" "
    SELECT
      (SELECT count(DISTINCT generation.generation_id) = 1 FROM app_private.personal_target_merge_generations_v1 AS generation
       JOIN app_private.personal_target_merge_generation_members_v1 AS member USING (generation_id)
       WHERE member.promotion_target_id IN ('${first}'::uuid, '${second}'::uuid))
      AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_generation_members_v1
           WHERE promotion_target_id IN ('${first}'::uuid, '${second}'::uuid))
      AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_active_members_v1
           WHERE promotion_target_id IN ('${first}'::uuid, '${second}'::uuid))
      AND (SELECT count(*) = 1 FROM app_private.personal_target_merge_activation_requests_v1
           WHERE actor_app_user_id = '${app_user_id}'::uuid
             AND request_id = '${request_id}'::uuid
             AND preview_id = '${preview_id}'::uuid)
      AND (SELECT count(*) = 1 FROM app_private.personal_target_merge_activation_audit_v1
           WHERE actor_app_user_id = '${app_user_id}'::uuid
             AND request_id = '${request_id}'::uuid);
  "
}

assert_not_activated() {
  local label="$1" request_id="$2" preview_id="$3" first="$4" second="$5"
  assert_true "${label}" "
    SELECT NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_generations_v1 AS generation
      JOIN app_private.personal_target_merge_generation_members_v1 AS member USING (generation_id)
      WHERE member.promotion_target_id IN ('${first}'::uuid, '${second}'::uuid))
    AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1
      WHERE promotion_target_id IN ('${first}'::uuid, '${second}'::uuid))
    AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1
      WHERE actor_app_user_id = '${app_user_id}'::uuid
        AND request_id = '${request_id}'::uuid)
    AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_audit_v1
      WHERE actor_app_user_id = '${app_user_id}'::uuid
        AND request_id = '${request_id}'::uuid);
  "
}

assert_request_absent() {
  local label="$1" request_id="$2"
  assert_true "${label}" "
    SELECT NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1
      WHERE actor_app_user_id = '${app_user_id}'::uuid
        AND request_id = '${request_id}'::uuid)
    AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_audit_v1
      WHERE actor_app_user_id = '${app_user_id}'::uuid
        AND request_id = '${request_id}'::uuid);
  "
}

create_receipt_with_expiry() {
  local source_preview_id="$1" expiry_expression="$2"
  run_psql --quiet --tuples-only --no-align --command="
    WITH source AS MATERIALIZED (
      SELECT * FROM app_private.personal_target_pair_preview_receipts
      WHERE preview_id = '${source_preview_id}'::uuid
    ), timing AS MATERIALIZED (
    SELECT ${expiry_expression} AS expires_at_utc
    )
    INSERT INTO app_private.personal_target_pair_preview_receipts (
      preview_id, actor_app_user_id, workspace_id, first_target_id,
      second_target_id, first_profile_revision, second_profile_revision,
      first_assignment_id, second_assignment_id, first_retention_due_at_utc,
      second_retention_due_at_utc, merge_deadline_at_utc, phone_match,
      email_match, previewed_at_utc, expires_at_utc
    )
    SELECT gen_random_uuid(), source.actor_app_user_id, source.workspace_id,
      source.first_target_id, source.second_target_id,
      source.first_profile_revision, source.second_profile_revision,
      source.first_assignment_id, source.second_assignment_id,
      source.first_retention_due_at_utc, source.second_retention_due_at_utc,
      source.merge_deadline_at_utc, source.phone_match, source.email_match,
      timing.expires_at_utc - interval '15 minutes', timing.expires_at_utc
    FROM source CROSS JOIN timing
    RETURNING preview_id;
  " | tr -d '[:space:]'
}

start_gated_transaction() {
  local label="$1" app_name="$2" transaction_sql="$3" output_path="$4"
  PGAPPNAME="${app_name}" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="BEGIN; ${transaction_sql}; SELECT pg_advisory_xact_lock(hashtextextended('${gate_name}', 0)); COMMIT;" \
    >"${output_path}" 2>&1 &
  started_pid=$!
  child_pids+=("${started_pid}")
  wait_for_exact_blocker "${app_name}" "0117-gate-${label}" "${output_path}"
}

run_token_gate() {
  printf '0117-%s-%s' "${run_token}" "$1"
}

collect_pid() {
  local label="$1" pid="$2" expected_status="$3" output_path="$4" status=0
  wait "${pid}" || status=$?
  if [[ "${status}" -ne "${expected_status}" ]]; then
    echo "${label}: exit=${status}, expected=${expected_status}" >&2
    sed -n '1,120p' "${output_path}" >&2
    exit 1
  fi
}

# Same request id serializes before the generation fence and returns one exact
# result; a different request cannot consume that receipt a second time.
IFS='|' read -r same_first same_second same_preview <<<"$(create_pair same-request same)"
same_request="$(new_uuid)"
same_gate="$(run_token_gate same-request)"
start_gate "${same_gate}" "0117-gate-same-request"
same_holder_output="${temporary_directory}/same-holder.out"
start_gated_transaction same-request 0117-holder-same-request \
  "$(activation_sql "${same_request}" "${same_preview}" "${same_first}" "${same_second}")" \
  "${same_holder_output}"
same_holder="${started_pid}"
same_waiter_output="${temporary_directory}/same-waiter.out"
PGAPPNAME='0117-waiter-same-request' "${psql_base[@]}" --quiet --tuples-only --no-align \
  --command="$(activation_sql "${same_request}" "${same_preview}" "${same_first}" "${same_second}")" \
  >"${same_waiter_output}" 2>&1 &
same_waiter=$!
child_pids+=("${same_waiter}")
wait_for_exact_blocker '0117-waiter-same-request' '0117-holder-same-request' "${same_waiter_output}"
release_gate
collect_pid same-request-holder "${same_holder}" 0 "${same_holder_output}"
collect_pid same-request-waiter "${same_waiter}" 0 "${same_waiter_output}"
same_generation="$(tr -d '[:space:]' <"${same_holder_output}")"
same_replay="$(tr -d '[:space:]' <"${same_waiter_output}")"
[[ "${same_generation}" == "${same_replay}" ]] || {
  echo 'same request exact replay returned a different generation.' >&2; exit 1;
}
assert_activated same-request "${same_request}" "${same_preview}" "${same_first}" "${same_second}"

# Exact replay waits on the request key; revoke the actor while it waits, then
# require the post-lock authorization check to reject the replay without writes.
auth_race_gate="$(run_token_gate auth-race-replay)"
start_gate "${auth_race_gate}" '0117-gate-auth-race-replay'
auth_race_holder_output="${temporary_directory}/auth-race-holder.out"
start_gated_transaction auth-race-replay 0117-holder-auth-race-replay \
  "SELECT pg_advisory_xact_lock(hashtextextended('${app_user_id}'::uuid::text || ':' || '${same_request}'::uuid::text, 0));" \
  "${auth_race_holder_output}"
auth_race_holder="${started_pid}"
auth_race_waiter_output="${temporary_directory}/auth-race-waiter.out"
PGAPPNAME='0117-waiter-auth-race-replay' "${psql_base[@]}" --quiet --tuples-only --no-align \
  --command="$(activation_sql "${same_request}" "${same_preview}" "${same_first}" "${same_second}")" \
  >"${auth_race_waiter_output}" 2>&1 &
auth_race_waiter=$!
child_pids+=("${auth_race_waiter}")
wait_for_exact_blocker '0117-waiter-auth-race-replay' '0117-holder-auth-race-replay' "${auth_race_waiter_output}"
run_psql --quiet --command="
  UPDATE app_data.app_users SET status = 'deletion_pending'
  WHERE app_user_id = '${app_user_id}'::uuid;
" >/dev/null
assert_true auth-race-actor-revoked "
  SELECT status = 'deletion_pending' FROM app_data.app_users
  WHERE app_user_id = '${app_user_id}'::uuid;
"
release_gate
collect_pid auth-race-holder "${auth_race_holder}" 0 "${auth_race_holder_output}"
collect_pid auth-race-replay "${auth_race_waiter}" 1 "${auth_race_waiter_output}"
grep -q '42501: personal target merge generation activation is forbidden' "${auth_race_waiter_output}" || {
  echo 'replay after actor revocation returned an unexpected error.' >&2
  sed -n '1,100p' "${auth_race_waiter_output}" >&2
  exit 1
}
run_psql --quiet --command="
  UPDATE app_data.app_users SET status = 'active'
  WHERE app_user_id = '${app_user_id}'::uuid;
" >/dev/null
[[ "$(run_psql --tuples-only --no-align --command="$(activation_sql \
  "${same_request}" "${same_preview}" "${same_first}" "${same_second}")" | tr -d '[:space:]')" == "${same_generation}" ]] || {
  echo 'restored actor did not retain the original exact request result.' >&2; exit 1;
}
assert_activated same-request-after-auth-race "${same_request}" "${same_preview}" "${same_first}" "${same_second}"

IFS='|' read -r contest_first contest_second contest_preview <<<"$(create_pair receipt-contest contest)"
contest_winner_request="$(new_uuid)"
contest_loser_request="$(new_uuid)"
contest_gate="$(run_token_gate receipt-contest)"
start_gate "${contest_gate}" '0117-gate-receipt-contest'
contest_holder_output="${temporary_directory}/contest-holder.out"
start_gated_transaction receipt-contest 0117-holder-receipt-contest \
  "$(activation_sql "${contest_winner_request}" "${contest_preview}" "${contest_first}" "${contest_second}")" \
  "${contest_holder_output}"
contest_holder="${started_pid}"
contest_waiter_output="${temporary_directory}/contest-waiter.out"
PGAPPNAME='0117-waiter-receipt-contest' "${psql_base[@]}" --quiet --tuples-only --no-align \
  --command="$(activation_sql "${contest_loser_request}" "${contest_preview}" "${contest_first}" "${contest_second}")" \
  >"${contest_waiter_output}" 2>&1 &
contest_waiter=$!
child_pids+=("${contest_waiter}")
wait_for_exact_blocker '0117-waiter-receipt-contest' '0117-holder-receipt-contest' "${contest_waiter_output}"
release_gate
collect_pid receipt-contest-holder "${contest_holder}" 0 "${contest_holder_output}"
collect_pid receipt-contest-waiter "${contest_waiter}" 1 "${contest_waiter_output}"
grep -q '23505: personal target merge preview receipt was already consumed' "${contest_waiter_output}" || {
  echo 'different request receipt loser returned an unexpected error.' >&2
  sed -n '1,100p' "${contest_waiter_output}" >&2
  exit 1
}
assert_activated receipt-contest "${contest_winner_request}" "${contest_preview}" "${contest_first}" "${contest_second}"
assert_request_absent receipt-contest-loser "${contest_loser_request}"

# Cleanup wins: it deletes an expired receipt but holds the transaction open;
# activation must wait for that exact delete and then fail without partial rows.
IFS='|' read -r cleanup_first cleanup_second cleanup_source_preview <<<"$(create_pair cleanup-first cleanup-first)"
cleanup_preview="$(create_receipt_with_expiry "${cleanup_source_preview}" "clock_timestamp() - interval '1 minute'")"
cleanup_request="$(new_uuid)"
cleanup_gate="$(run_token_gate cleanup-first)"
start_gate "${cleanup_gate}" '0117-gate-cleanup-first'
cleanup_holder_output="${temporary_directory}/cleanup-holder.out"
start_gated_transaction cleanup-first 0117-holder-cleanup-first \
  "SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1();" \
  "${cleanup_holder_output}"
cleanup_holder="${started_pid}"
cleanup_waiter_output="${temporary_directory}/cleanup-waiter.out"
PGAPPNAME='0117-waiter-cleanup-first' "${psql_base[@]}" --quiet --tuples-only --no-align \
  --command="$(activation_sql "${cleanup_request}" "${cleanup_preview}" "${cleanup_first}" "${cleanup_second}")" \
  >"${cleanup_waiter_output}" 2>&1 &
cleanup_waiter=$!
child_pids+=("${cleanup_waiter}")
wait_for_exact_blocker '0117-waiter-cleanup-first' '0117-holder-cleanup-first' "${cleanup_waiter_output}"
release_gate
collect_pid cleanup-first-holder "${cleanup_holder}" 0 "${cleanup_holder_output}"
cleanup_holder_count="$(tr -d '[:space:]' <"${cleanup_holder_output}")"
[[ "${cleanup_holder_count}" =~ ^[0-9]+$ ]] && (( cleanup_holder_count >= 1 )) || {
  echo 'cleanup-first fixture did not delete an expired receipt.' >&2; exit 1;
}
collect_pid cleanup-first-activation "${cleanup_waiter}" 1 "${cleanup_waiter_output}"
grep -q '42501: personal target merge generation activation is forbidden' "${cleanup_waiter_output}" || {
  echo 'activation after cleanup returned an unexpected error.' >&2
  sed -n '1,100p' "${cleanup_waiter_output}" >&2
  exit 1
}
assert_not_activated cleanup-first "${cleanup_request}" "${cleanup_preview}" "${cleanup_first}" "${cleanup_second}"

# Activation wins: hold its transaction after the function returns, let the
# receipt expire, and prove cleanup skips the locked row before replaying after
# cleanup has removed it.
IFS='|' read -r activation_first activation_second activation_source_preview <<<"$(create_pair activation-first activation-first)"
activation_preview="$(create_receipt_with_expiry "${activation_source_preview}" "clock_timestamp() + interval '20 seconds'")"
activation_request="$(new_uuid)"
activation_gate="$(run_token_gate activation-first)"
start_gate "${activation_gate}" '0117-gate-activation-first'
activation_holder_output="${temporary_directory}/activation-holder.out"
start_gated_transaction activation-first 0117-holder-activation-first \
  "$(activation_sql "${activation_request}" "${activation_preview}" "${activation_first}" "${activation_second}")" \
  "${activation_holder_output}"
activation_holder="${started_pid}"
sleep 21
cleanup_count="$(run_psql --tuples-only --no-align --command="
  SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1();
" | tr -d '[:space:]')"
[[ "${cleanup_count}" =~ ^[0-9]+$ ]] || {
  echo "cleanup returned a non-count result: ${cleanup_count}" >&2; exit 1;
}
assert_true activation-first-receipt-still-locked "
  SELECT EXISTS (SELECT 1 FROM app_private.personal_target_pair_preview_receipts
    WHERE preview_id = '${activation_preview}'::uuid);
"
release_gate
collect_pid activation-first-holder "${activation_holder}" 0 "${activation_holder_output}"
activation_generation="$(tr -d '[:space:]' <"${activation_holder_output}")"
[[ "${activation_generation}" =~ ^[0-9a-f-]{36}$ ]] || {
  echo 'activation-first holder did not create a generation.' >&2; exit 1;
}
assert_activated activation-first "${activation_request}" "${activation_preview}" "${activation_first}" "${activation_second}"
replayed_generation="$(run_psql --tuples-only --no-align --quiet --command="$(activation_sql \
  "${activation_request}" "${activation_preview}" "${activation_first}" "${activation_second}")" | tr -d '[:space:]')"
[[ "${replayed_generation}" == "${activation_generation}" ]] || {
  echo 'exact replay after receipt expiry returned a different generation.' >&2; exit 1;
}
post_activation_cleanup="$(run_psql --tuples-only --no-align --command="
  SELECT app_private.cleanup_personal_target_pair_preview_receipts_v1();
" | tr -d '[:space:]')"
[[ "${post_activation_cleanup}" =~ ^[0-9]+$ ]] || {
  echo "cleanup returned a non-count result: ${post_activation_cleanup}" >&2; exit 1;
}
assert_true activation-first-cleanup-removes-receipt "
  SELECT NOT EXISTS (SELECT 1 FROM app_private.personal_target_pair_preview_receipts
    WHERE preview_id = '${activation_preview}'::uuid);
"
replayed_after_cleanup="$(run_psql --tuples-only --no-align --quiet --command="$(activation_sql \
  "${activation_request}" "${activation_preview}" "${activation_first}" "${activation_second}")" | tr -d '[:space:]')"
[[ "${replayed_after_cleanup}" == "${activation_generation}" ]] || {
  echo 'exact replay after cleanup returned a different generation.' >&2; exit 1;
}
assert_activated activation-replay-after-cleanup "${activation_request}" "${activation_preview}" "${activation_first}" "${activation_second}"

# The v2 activation and the established relationship writer serialize both
# ways on the 0114 global fence.
create_relationship() {
  run_psql --quiet --command="
    INSERT INTO app_data.promotion_target_project_relationships (
      promotion_target_id, project_id, current_stage, established_by_app_user_id
    ) VALUES ('${1}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid);
  " >/dev/null
}
relationship_writer_sql() {
  printf "SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship(\n  '%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid, 1, 2, 'active', NULL, 'progress_update', NULL, '%s', NULL\n); RESET ROLE;" \
    "${app_user_id}" "${workspace_id}" "${project_id}" "$1" "$2"
}

IFS='|' read -r merge_first merge_second merge_preview <<<"$(create_pair activation-writer-first merge-writer-first)"
merge_request="$(new_uuid)"
create_relationship "${merge_first}"
merge_gate="$(run_token_gate activation-writer-first)"
start_gate "${merge_gate}" '0117-gate-activation-writer-first'
merge_holder_output="${temporary_directory}/activation-writer-holder.out"
start_gated_transaction activation-writer-first 0117-holder-activation-writer-first \
  "$(activation_sql "${merge_request}" "${merge_preview}" "${merge_first}" "${merge_second}")" \
  "${merge_holder_output}"
merge_holder="${started_pid}"
merge_writer_output="${temporary_directory}/activation-writer-waiter.out"
PGAPPNAME='0117-waiter-activation-writer-first' "${psql_base[@]}" --quiet \
  --command="$(relationship_writer_sql "${merge_first}" "0117-${run_token}-activation-first")" \
  >"${merge_writer_output}" 2>&1 &
merge_writer=$!
child_pids+=("${merge_writer}")
wait_for_exact_blocker '0117-waiter-activation-writer-first' '0117-holder-activation-writer-first' "${merge_writer_output}"
release_gate
collect_pid activation-writer-first-holder "${merge_holder}" 0 "${merge_holder_output}"
collect_pid activation-writer-first-writer "${merge_writer}" 0 "${merge_writer_output}"
assert_activated activation-writer-first "${merge_request}" "${merge_preview}" "${merge_first}" "${merge_second}"
assert_true activation-writer-first-binding "
  SELECT relation.current_revision = 2
    AND revision.merge_generation_id = active.generation_id
  FROM app_data.promotion_target_project_relationships AS relation
  JOIN app_data.promotion_target_relationship_revisions AS revision
    ON revision.promotion_target_id = relation.promotion_target_id
   AND revision.project_id = relation.project_id
   AND revision.revision_number = 2
  JOIN app_private.personal_target_merge_active_members_v1 AS active
    ON active.promotion_target_id = relation.promotion_target_id
  WHERE relation.promotion_target_id = '${merge_first}'::uuid;
"

IFS='|' read -r writer_first writer_second writer_preview <<<"$(create_pair writer-activation-first writer-activation-first)"
writer_request="$(new_uuid)"
create_relationship "${writer_first}"
writer_gate="$(run_token_gate writer-activation-first)"
start_gate "${writer_gate}" '0117-gate-writer-activation-first'
writer_holder_output="${temporary_directory}/writer-activation-holder.out"
start_gated_transaction writer-activation-first 0117-holder-writer-activation-first \
  "$(relationship_writer_sql "${writer_first}" "0117-${run_token}-writer-first")" \
  "${writer_holder_output}"
writer_holder="${started_pid}"
writer_activation_output="${temporary_directory}/writer-activation-waiter.out"
PGAPPNAME='0117-waiter-writer-activation-first' "${psql_base[@]}" --quiet --tuples-only --no-align \
  --command="$(activation_sql "${writer_request}" "${writer_preview}" "${writer_first}" "${writer_second}")" \
  >"${writer_activation_output}" 2>&1 &
writer_activation=$!
child_pids+=("${writer_activation}")
wait_for_exact_blocker '0117-waiter-writer-activation-first' '0117-holder-writer-activation-first' "${writer_activation_output}"
release_gate
collect_pid writer-activation-first-holder "${writer_holder}" 0 "${writer_holder_output}"
collect_pid writer-activation-first-activation "${writer_activation}" 0 "${writer_activation_output}"
assert_activated writer-activation-first "${writer_request}" "${writer_preview}" "${writer_first}" "${writer_second}"
assert_true writer-activation-first-history "
  SELECT relation.current_revision = 2
    AND revision.merge_generation_id IS NULL
  FROM app_data.promotion_target_project_relationships AS relation
  JOIN app_data.promotion_target_relationship_revisions AS revision
    ON revision.promotion_target_id = relation.promotion_target_id
   AND revision.project_id = relation.project_id
   AND revision.revision_number = 2
  JOIN app_private.personal_target_merge_active_members_v1 AS active
    ON active.promotion_target_id = relation.promotion_target_id
  WHERE relation.promotion_target_id = '${writer_first}'::uuid;
"

echo '0117 request, receipt/cleanup, and fenced-writer concurrency races passed.'
