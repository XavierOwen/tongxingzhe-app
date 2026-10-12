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

temporary_directory="$(mktemp -d)"
child_pids=()
holder_pid=''
waiter_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_ready() {
  local ready_name="$1" ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="
      SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('${ready_name}',0))
        THEN NOT pg_advisory_unlock(hashtextextended('${ready_name}',0))
        ELSE true END;
    " | tr -d '[:space:]')"
    [[ "${ready}" == 't' ]] && return
    sleep 0.05
  done
  echo "0119 holder 未完成指定语句：${ready_name}" >&2
  sed -n '1,120p' "${temporary_directory}/holder.out" >&2
  exit 1
}

start_holder() {
  local app_name="$1" ready_name="$2" statement="$3"
  mkfifo "${temporary_directory}/holder.fifo"
  PGAPPNAME="${app_name}" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"${temporary_directory}/holder.fifo" >"${temporary_directory}/holder.out" 2>&1 &
  holder_pid=$!
  child_pids+=("${holder_pid}")
  exec 3>"${temporary_directory}/holder.fifo"
  printf 'BEGIN; %s SELECT pg_advisory_lock(hashtextextended(\047%s\047,0));\n' \
    "${statement}" "${ready_name}" >&3
  wait_for_ready "${ready_name}"
}

release_holder() {
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "${holder_pid}"
  rm -f "${temporary_directory}/holder.fifo"
  holder_pid=''
}

start_waiter() {
  local app_name="$1" statement="$2"
  PGAPPNAME="${app_name}" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="${statement}" >"${temporary_directory}/waiter.out" 2>&1 &
  waiter_pid=$!
  child_pids+=("${waiter_pid}")
}

wait_for_exact_blocker() {
  local waiter_app="$1" blocker_app="$2" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="
      SELECT waiting.pid || '|' || blocker.pid || '|' || waiting.wait_event
      FROM pg_catalog.pg_stat_activity waiting
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiting.pid)) blocked(pid) ON true
      JOIN pg_catalog.pg_stat_activity blocker ON blocker.pid = blocked.pid
      WHERE waiting.application_name = '${waiter_app}' AND waiting.wait_event_type = 'Lock'
        AND blocker.application_name = '${blocker_app}' LIMIT 1;
    " | tr -d '[:space:]')"
    if [[ "${pair}" == *'|'* ]]; then
      echo "${waiter_app}: exact waiter/blocker PID and lock ${pair}"
      return
    fi
    sleep 0.05
  done
  echo "0119 未观察到精确 blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
  sed -n '1,120p' "${temporary_directory}/waiter.out" >&2
  exit 1
}

collect_waiter() {
  local label="$1" expected_state="$2" status=0
  wait "${waiter_pid}" || status=$?
  if [[ "${expected_state}" == 'success' ]]; then
    [[ "${status}" -eq 0 ]] && return
  elif [[ "${status}" -ne 0 ]] && grep -q "ERROR:  ${expected_state}:" "${temporary_directory}/waiter.out"; then
    return
  fi
  echo "0119 ${label}: exit=${status}, expected=${expected_state}" >&2
  sed -n '1,120p' "${temporary_directory}/waiter.out" >&2
  exit 1
}

assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  if [[ "${result}" != 't' ]]; then
    echo "0119 ${label} invariant failed: ${result}" >&2
    exit 1
  fi
}

new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]'; }
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7eec-known-source-end-concurrency.example.test/auth/v1'
subject="7eec-known-source-end-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}','${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('${issuer}','${subject}') WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"${context}"
for context_id in "${app_user_id}" "${workspace_id}" "${project_id}" "${questionnaire_version_id}"; do
  [[ "${context_id}" =~ ^[0-9a-f-]{36}$ ]] || { echo '0119 无法取得 personal context。' >&2; exit 1; }
done

create_pair() {
  local label="$1" pair_ids
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}','${workspace_id}','${project_id}','person',
      '0119 ${label} first ${run_token}','+1 773 555 0119',NULL,'7eec-${run_token}-${label}-a');
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}','${workspace_id}','${project_id}','person',
      '0119 ${label} second ${run_token}','+1 773 555 0119',NULL,'7eec-${run_token}-${label}-b');
  " >/dev/null
  pair_ids="$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT (array_agg(promotion_target_id ORDER BY promotion_target_id))[1],
           (array_agg(promotion_target_id ORDER BY promotion_target_id))[2]
    FROM app_data.promotion_targets WHERE workspace_id = '${workspace_id}'
      AND display_name IN ('0119 ${label} first ${run_token}','0119 ${label} second ${run_token}');
  " | tr -d '[:space:]')"
  IFS='|' read -r first_target second_target <<<"${pair_ids}"
  [[ "${first_target}" =~ ^[0-9a-f-]{36}$ && "${second_target}" =~ ^[0-9a-f-]{36}$ ]] || {
    echo "0119 ${label} 未能创建目标对。" >&2; exit 1;
  }
  # UUID order is deliberately opposite to the export's creation-time order.
  run_psql --quiet --command="UPDATE app_data.promotion_targets
    SET created_at = clock_timestamp() - CASE WHEN promotion_target_id = '${second_target}'::uuid
      THEN interval '2 days' ELSE interval '1 day' END
    WHERE promotion_target_id IN ('${first_target}','${second_target}');" >/dev/null
  preview_id="$(run_psql --tuples-only --no-align --command="
    SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
      '${issuer}','${subject}','${project_id}','${first_target}','${second_target}');
  " | tr -d '[:space:]')"
  assignment_id="$(run_psql --tuples-only --no-align --command="
    SELECT assignment_id FROM app_data.promotion_target_assignments
    WHERE promotion_target_id = '${first_target}' AND app_user_id = '${app_user_id}' AND ended_at IS NULL;
  " | tr -d '[:space:]')"
  activation_request="$(new_uuid)"
  end_request="$(new_uuid)"
}

activation_sql() {
  printf "SELECT app_private.activate_personal_target_merge_generation_v2('%s','%s','%s','%s','%s','%s','%s','%s');" \
    "${app_user_id}" "${project_id}" "$1" "${preview_id}" \
    "${first_target}" "${first_target}" "${second_target}" "${first_target}"
}
activate_pair() {
  generation_id="$(run_psql --quiet --tuples-only --no-align --command="$(activation_sql "${activation_request}")" | tr -d '[:space:]')"
  refresh_manifest
}
refresh_manifest() {
  fingerprint="$(run_psql --tuples-only --no-align --command="
    SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('${generation_id}');
  " | tr -d '[:space:]')"
  [[ "${generation_id}" =~ ^[0-9a-f-]{36}$ && "${fingerprint}" =~ ^[0-9a-f]{64}$ ]] || {
    echo '0119 无法取得 generation/manifest。' >&2; exit 1;
  }
}
end_sql() {
  printf "SELECT app_private.end_known_source_personal_target_merge_generation_v1('%s','%s','%s','%s','%s','%s');" \
    "${app_user_id}" "${workspace_id}" "${project_id}" "${end_request}" "${generation_id}" "${fingerprint}"
}
assignment_sql() {
  printf "SELECT app_data.end_personal_target_assignment_v1('%s','%s','%s','%s');" \
    "${app_user_id}" "${workspace_id}" "${project_id}" "${assignment_id}"
}
fact_sql() {
  local contact_id="$1"
  printf "%s" "SET ROLE tongxingzhe_runtime; SELECT result_code FROM app_data.apply_contact_submit_v3(
    '${app_user_id}','${contact_id}-submit',1,'contact.submit.v1','7eec-device','${contact_id}',0,
    jsonb_build_object('contactId','${contact_id}','workspaceId','${workspace_id}','projectId','${project_id}',
      'questionnaireVersionId','${questionnaire_version_id}','occurredAtUtc',clock_timestamp(),
      'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(
        jsonb_build_object('targetId','${first_target}','targetType','person','responseLevel',2,
          'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))); RESET ROLE;"
}

run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_state="$4"
  local holder_app="7eec-holder-${label}-${run_token}" waiter_app="7eec-waiter-${label}-${run_token}"
  start_holder "${holder_app}" "7eec-ready-${label}-${run_token}" "${holder_sql}"
  start_waiter "${waiter_app}" "${waiter_sql}"
  wait_for_exact_blocker "${waiter_app}" "${holder_app}"
  release_holder
  collect_waiter "${label}" "${expected_state}"
}
assert_ended() {
  assert_true "$1" "SELECT
    (SELECT count(*) = 1 FROM app_private.personal_target_merge_end_events_v1
      WHERE generation_id = '${generation_id}' AND request_id = '${end_request}' AND target_count = 2)
    AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '${generation_id}')
    AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id = '${generation_id}');"
}
assert_open() {
  assert_true "$1" "SELECT
    NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = '${generation_id}')
    AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '${generation_id}');"
}

create_pair same-request
activate_pair
run_race same-request "$(end_sql)" "$(end_sql)" success
first_time="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "${temporary_directory}/holder.out")"
replay_time="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "${temporary_directory}/waiter.out")"
[[ -n "${first_time}" && "${first_time}" == "${replay_time}" ]] || {
  echo '0119 same-request timestamps differ。' >&2; exit 1;
}
assert_ended same-request
assert_true same-request-time "SELECT ended_at_utc = '${first_time}'::timestamptz
  FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = '${generation_id}';"

create_pair different-request
activate_pair
first_request="${end_request}"
holder_sql="$(end_sql)"
end_request="$(new_uuid)"
losing_request="${end_request}"
waiter_sql="$(end_sql)"
end_request="${first_request}"
run_race different-request "${holder_sql}" "${waiter_sql}" 23505
assert_ended different-request
assert_true different-request-zero-writes "SELECT NOT EXISTS (
  SELECT 1 FROM app_private.personal_target_merge_end_events_v1
  WHERE actor_app_user_id = '${app_user_id}' AND request_id = '${losing_request}');"

create_pair fact-first
activate_pair
contact_id="7eec-${run_token}-fact-first"
run_race fact-first "$(fact_sql "${contact_id}")" "$(end_sql)" 23505
grep -q '^accepted$' "${temporary_directory}/holder.out"
assert_open fact-first-zero-end-writes
assert_true fact-first-binding "SELECT count(*) = 1 AND bool_and(merge_generation_id = '${generation_id}'::uuid)
  FROM app_data.contact_target_links WHERE contact_id = '${contact_id}';"

create_pair end-first-fact
activate_pair
contact_id="7eec-${run_token}-end-first-fact"
holder_app="7eec-holder-end-first-fact-${run_token}"
waiter_app="7eec-waiter-end-first-fact-${run_token}"
start_holder "${holder_app}" "7eec-ready-end-first-fact-${run_token}" "$(end_sql)"
start_waiter "${waiter_app}" "$(fact_sql "${contact_id}")"
wait_for_exact_blocker "${waiter_app}" "${holder_app}"
assert_true end-holds-no-contact-lock "SELECT NOT EXISTS (
  SELECT 1 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
  WHERE a.application_name = '${holder_app}' AND l.granted AND l.mode <> 'AccessShareLock' AND l.relation IN (
    'app_data.contacts'::regclass,'app_data.contact_revisions'::regclass));"
release_holder
collect_waiter end-first-fact success
grep -q '^accepted$' "${temporary_directory}/waiter.out"
assert_ended end-first-fact
assert_true end-first-fact-null-binding "SELECT count(*) = 1 AND bool_and(merge_generation_id IS NULL)
  FROM app_data.contact_target_links WHERE contact_id = '${contact_id}';"

# Read the uncommitted activation's actual returned generation ID; the empty
# metadata manifest is calculable before that generation becomes visible.
create_pair activation-first
holder_app="7eec-holder-activation-first-${run_token}"
waiter_app="7eec-waiter-activation-first-${run_token}"
start_holder "${holder_app}" "7eec-ready-activation-first-${run_token}" "$(activation_sql "${activation_request}")"
generation_id="$(sed -n '/^[0-9a-f-]\{36\}$/p' "${temporary_directory}/holder.out")"
refresh_manifest
start_waiter "${waiter_app}" "$(end_sql)"
wait_for_exact_blocker "${waiter_app}" "${holder_app}"
release_holder
collect_waiter activation-first success
assert_ended activation-first
assert_true activation-first-history "SELECT count(*) = 1 FROM app_private.personal_target_merge_activation_requests_v1
  WHERE actor_app_user_id = '${app_user_id}' AND request_id = '${activation_request}' AND generation_id = '${generation_id}';"

create_pair end-first-activation
activate_pair
stale_activation_request="$(new_uuid)"
run_race end-first-activation "$(end_sql)" "$(activation_sql "${stale_activation_request}")" 23505
assert_ended end-first-activation
assert_true stale-preview-no-new-generation "SELECT
  NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_requests_v1
    WHERE actor_app_user_id = '${app_user_id}' AND request_id = '${stale_activation_request}')
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_activation_audit_v1
    WHERE actor_app_user_id = '${app_user_id}' AND request_id = '${stale_activation_request}')
  AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_generation_members_v1
    WHERE promotion_target_id IN ('${first_target}','${second_target}'));"

create_pair end-first-assignment
activate_pair
run_race end-first-assignment "$(end_sql)" "$(assignment_sql)" success
assert_ended end-first-assignment
assert_true end-first-assignment-completed "SELECT
  (SELECT ended_at IS NOT NULL FROM app_data.promotion_target_assignments WHERE assignment_id = '${assignment_id}')
  AND (SELECT count(*) = 1 FROM app_private.personal_target_assignment_end_events_v1 WHERE assignment_id = '${assignment_id}');"

# Keep the outer fence while catching the last-assignment rejection so its
# failed function transaction is ordered before the waiting generation end.
create_pair assignment-first
activate_pair
holder_sql="SELECT app_private.acquire_personal_target_merge_generation_fence_v1();
  DO \$assignment\$ BEGIN
    BEGIN
      PERFORM app_data.end_personal_target_assignment_v1('${app_user_id}','${workspace_id}','${project_id}','${assignment_id}');
      RAISE EXCEPTION 'last assignment end unexpectedly succeeded';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      IF SQLERRM <> 'personal target merge must be split before ending assignment' THEN RAISE; END IF;
    END;
  END \$assignment\$;"
run_race assignment-first "${holder_sql}" "$(end_sql)" success
assert_ended assignment-first
assert_true assignment-first-zero-writes "SELECT
  (SELECT ended_at IS NULL FROM app_data.promotion_target_assignments WHERE assignment_id = '${assignment_id}')
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_assignment_end_events_v1 WHERE assignment_id = '${assignment_id}');"

# Advance the export cursor one row at a time in its real (created_at, UUID)
# SHARE order; the end must wait on the first row without owning the second.
create_pair export-order
activate_pair
holder_app="7eec-holder-export-${run_token}"
waiter_app="7eec-waiter-export-end-${run_token}"
assert_true reversed-export-order "SELECT a.promotion_target_id < b.promotion_target_id AND a.created_at > b.created_at
  FROM app_data.promotion_targets a CROSS JOIN app_data.promotion_targets b
  WHERE a.promotion_target_id = '${first_target}' AND b.promotion_target_id = '${second_target}';"
start_holder "${holder_app}" "7eec-ready-export-first-${run_token}" \
  "SELECT promotion_target_id FROM app_data.promotion_targets WHERE promotion_target_id = '${second_target}' FOR SHARE;"
start_waiter "${waiter_app}" "$(end_sql)"
wait_for_exact_blocker "${waiter_app}" "${holder_app}"
printf "SELECT promotion_target_id FROM app_data.promotion_targets WHERE promotion_target_id = '%s' ORDER BY created_at,promotion_target_id FOR SHARE; SELECT pg_advisory_lock(hashtextextended('%s',0));\n" \
  "${first_target}" "7eec-ready-export-second-${run_token}" >&3
wait_for_ready "7eec-ready-export-second-${run_token}"
wait_for_exact_blocker "${waiter_app}" "${holder_app}"
release_holder
collect_waiter export-order success
assert_ended export-order

create_pair closed-map-guard
activate_pair
run_race closed-map-guard "$(end_sql)" "INSERT INTO app_private.personal_target_merge_active_members_v1(
  promotion_target_id,generation_id,workspace_id,target_type)
  VALUES ('${first_target}','${generation_id}','${workspace_id}','person');" 55000
assert_ended closed-map-guard

echo '0119 concurrency passed: exact replay/request contest, fact/activation/assignment orderings, export SHARE order, and closed-map guard.'
