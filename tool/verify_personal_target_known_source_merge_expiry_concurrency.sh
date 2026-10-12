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
  echo "0120 holder 未完成指定语句：${ready_name}" >&2
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
  printf 'BEGIN; %s SELECT \047epoch|\047 || epoch FROM app_private.personal_target_merge_generation_fence_v1; SELECT pg_advisory_lock(hashtextextended(\047%s\047,0));\n' \
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
  echo "0120 未观察到精确 blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
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
  echo "0120 ${label}: exit=${status}, expected=${expected_state}" >&2
  sed -n '1,120p' "${temporary_directory}/waiter.out" >&2
  exit 1
}

assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  if [[ "${result}" != 't' ]]; then
    echo "0120 ${label} invariant failed: ${result}" >&2
    exit 1
  fi
}

new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]'; }
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7efc-known-source-expiry-concurrency.example.test/auth/v1'
subject="7efc-known-source-expiry-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}','${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('${issuer}','${subject}') WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"${context}"
for context_id in "${app_user_id}" "${workspace_id}" "${project_id}" "${questionnaire_version_id}"; do
  [[ "${context_id}" =~ ^[0-9a-f-]{36}$ ]] || { echo '0120 无法取得 personal context。' >&2; exit 1; }
done

create_pair() {
  local label="$1" pair_ids
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}','${workspace_id}','${project_id}','person',
      '0120 ${label} first ${run_token}','+1 773 555 0120',NULL,'7efc-${run_token}-${label}-a');
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}','${workspace_id}','${project_id}','person',
      '0120 ${label} second ${run_token}','+1 773 555 0120',NULL,'7efc-${run_token}-${label}-b');
  " >/dev/null
  pair_ids="$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT (array_agg(promotion_target_id ORDER BY promotion_target_id))[1],
           (array_agg(promotion_target_id ORDER BY promotion_target_id))[2]
    FROM app_data.promotion_targets WHERE workspace_id = '${workspace_id}'
      AND display_name IN ('0120 ${label} first ${run_token}','0120 ${label} second ${run_token}');
  " | tr -d '[:space:]')"
  IFS='|' read -r first_target second_target <<<"${pair_ids}"
  [[ "${first_target}" =~ ^[0-9a-f-]{36}$ && "${second_target}" =~ ^[0-9a-f-]{36}$ ]] || {
    echo "0120 ${label} 未能创建目标对。" >&2; exit 1;
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
  activation_request="$(new_uuid)"
  expiry_request="$(new_uuid)"
}

activation_sql() {
  printf "SELECT app_private.activate_personal_target_merge_generation_v2('%s','%s','%s','%s','%s','%s','%s','%s');" \
    "${app_user_id}" "${project_id}" "$1" "${preview_id}" \
    "${first_target}" "${first_target}" "${second_target}" "${first_target}"
}
activate_pair() {
  generation_id="$(run_psql --quiet --tuples-only --no-align --command="$(activation_sql "${activation_request}")" | tr -d '[:space:]')"
  refresh_manifest
  fact_count="$(run_psql --tuples-only --no-align --command="SELECT fact_count FROM app_private.personal_target_merge_known_source_manifest_v1('${generation_id}');" | tr -d '[:space:]')"
}
refresh_manifest() {
  fingerprint="$(run_psql --tuples-only --no-align --command="
    SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('${generation_id}');
  " | tr -d '[:space:]')"
  [[ "${generation_id}" =~ ^[0-9a-f-]{36}$ && "${fingerprint}" =~ ^[0-9a-f]{64}$ ]] || {
    echo '0120 无法取得 generation/manifest。' >&2; exit 1;
  }
}
ordinary_end_sql() {
  printf "SELECT app_private.end_known_source_personal_target_merge_generation_v1('%s','%s','%s','%s','%s','%s');" \
    "${app_user_id}" "${workspace_id}" "${project_id}" "${expiry_request}" "${generation_id}" "${fingerprint}"
}
fact_sql() {
  local contact_id="$1"
  printf "%s" "SET ROLE tongxingzhe_runtime; SELECT result_code FROM app_data.apply_contact_submit_v3(
    '${app_user_id}','${contact_id}-submit',1,'contact.submit.v1','7efc-device','${contact_id}',0,
    jsonb_build_object('contactId','${contact_id}','workspaceId','${workspace_id}','projectId','${project_id}',
      'questionnaireVersionId','${questionnaire_version_id}','occurredAtUtc',clock_timestamp(),
      'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(
        jsonb_build_object('targetId','${first_target}','targetType','person','responseLevel',2,
          'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))); RESET ROLE;"
}

run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_state="$4"
  local holder_app="7efc-holder-${label}-${run_token}" waiter_app="7efc-waiter-${label}-${run_token}"
  start_holder "${holder_app}" "7efc-ready-${label}-${run_token}" "${holder_sql}"
  start_waiter "${waiter_app}" "${waiter_sql}"
  wait_for_exact_blocker "${waiter_app}" "${holder_app}"
  release_holder
  collect_waiter "${label}" "${expected_state}"
  [[ "${expected_state}" == 'success' ]] || assert_waiter_rollback
}
expiry_sql() {
  printf "SELECT app_private.expire_known_source_personal_target_merge_generation_v1('%s','%s','%s','%s','%s');" \
    "$app_user_id" "$workspace_id" "$project_id" "$expiry_request" "$generation_id"
}
renewal_sql() {
  printf "SELECT result FROM app_data.apply_promotion_target_retention_action('%s','%s','%s','%s','renew','purpose_confirmed','%s');" \
    "$app_user_id" "$workspace_id" "$project_id" "$first_target" "$renewal_mutation"
}
policy_sql() {
  printf "SELECT app_data.configure_promotion_target_retention_policy('%s','%s','%s',%s);" \
    "$app_user_id" "$workspace_id" "$project_id" "$1"
}
make_due() {
  run_psql --quiet --command="UPDATE app_data.promotion_targets
    SET created_at = clock_timestamp() - interval '13 months'
    WHERE promotion_target_id = '$first_target';" >/dev/null
  assert_true only-first-due "SELECT
    app_data.promotion_target_review_due_at('$first_target') <= clock_timestamp()
    AND app_data.promotion_target_review_due_at('$second_target') > clock_timestamp();"
}
assert_waiter_rollback() {
  local epoch
  epoch="$(sed -n 's/^epoch|//p' "$temporary_directory/holder.out")"
  [[ "$epoch" =~ ^[0-9]+$ ]] || { echo '0120 未记录 holder fence epoch。' >&2; exit 1; }
  assert_true failed-waiter-fence-rollback "SELECT epoch = $epoch
    FROM app_private.personal_target_merge_generation_fence_v1 WHERE fence_key;"
}
assert_expired() {
  assert_true "$1" "SELECT
    (SELECT count(*) = 1 FROM app_private.personal_target_merge_end_events_v1
      WHERE generation_id = '$generation_id' AND request_id = '$expiry_request'
        AND actor_app_user_id = '$app_user_id' AND workspace_id = '$workspace_id' AND project_id = '$project_id'
        AND operation = 'personal_target_known_source_merge_expire' AND reason = 'retention_expired'
        AND outcome = 'ended' AND target_count = 2 AND fact_count = $fact_count
        AND fact_fingerprint = '$fingerprint')
    AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '$generation_id')
    AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id = '$generation_id')
    AND (SELECT count(*) = 1 FROM app_private.personal_target_merge_activation_requests_v1
      WHERE actor_app_user_id = '$app_user_id' AND request_id = '$activation_request' AND generation_id = '$generation_id')
    AND (SELECT count(*) = 2 AND bool_and(target.status = 'anonymized' AND target.display_name = '已匿名化对象'
      AND target.phone IS NULL AND target.email IS NULL AND target.anonymization_reason = 'retention_expired'
      AND target.anonymized_at = event.ended_at_utc)
      FROM app_data.promotion_targets target CROSS JOIN app_private.personal_target_merge_end_events_v1 event
      WHERE target.promotion_target_id IN ('$first_target','$second_target') AND event.generation_id = '$generation_id')
    AND (SELECT count(*) = 2 AND bool_and(assignment.ended_at = event.ended_at_utc AND assignment.end_reason = 'target_anonymized')
      FROM app_data.promotion_target_assignments assignment CROSS JOIN app_private.personal_target_merge_end_events_v1 event
      WHERE assignment.promotion_target_id IN ('$first_target','$second_target')
        AND assignment.app_user_id = '$app_user_id' AND event.generation_id = '$generation_id')
    AND (SELECT count(*) = 2 AND bool_and(retention.event_type = 'anonymized' AND retention.reason = 'retention_expired'
      AND retention.actor_app_user_id = '$app_user_id' AND retention.occurred_at = event.ended_at_utc
      AND retention.review_due_at IS NULL)
      FROM app_data.promotion_target_retention_events retention CROSS JOIN app_private.personal_target_merge_end_events_v1 event
      WHERE retention.promotion_target_id IN ('$first_target','$second_target') AND event.generation_id = '$generation_id');"
}
assert_open() {
  assert_true "$1" "SELECT
    NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = '$generation_id')
    AND (SELECT count(*) = 2 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '$generation_id')
    AND (SELECT count(*) = 2 AND bool_and(status = 'active' AND phone = '+1 773 555 0120' AND anonymized_at IS NULL)
      FROM app_data.promotion_targets WHERE promotion_target_id IN ('$first_target','$second_target'))
    AND (SELECT count(*) = 2 AND bool_and(ended_at IS NULL)
      FROM app_data.promotion_target_assignments WHERE promotion_target_id IN ('$first_target','$second_target')
        AND app_user_id = '$app_user_id')
    AND NOT EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events
      WHERE promotion_target_id IN ('$first_target','$second_target') AND event_type = 'anonymized');"
}

create_pair same-request
activate_pair
make_due
run_race same-request "$(expiry_sql)" "$(expiry_sql)" success
first_time="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "$temporary_directory/holder.out")"
replay_time="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "$temporary_directory/waiter.out")"
[[ -n "$first_time" && "$first_time" == "$replay_time" ]] || {
  echo '0120 same-request timestamps differ。' >&2; exit 1;
}
assert_expired same-request
assert_waiter_rollback
assert_true same-request-time "SELECT ended_at_utc = '$first_time'::timestamptz
  FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = '$generation_id';"

create_pair different-request
activate_pair
make_due
first_request="$expiry_request"
holder_sql="$(expiry_sql)"
expiry_request="$(new_uuid)"
losing_request="$expiry_request"
waiter_sql="$(expiry_sql)"
expiry_request="$first_request"
run_race different-request "$holder_sql" "$waiter_sql" 23505
assert_expired different-request
assert_true different-request-zero-writes "SELECT NOT EXISTS (
  SELECT 1 FROM app_private.personal_target_merge_end_events_v1
  WHERE actor_app_user_id = '$app_user_id' AND request_id = '$losing_request');"

# Hold a successful renewal past the original deadline; expiry must re-read it.
create_pair renewal-first
activate_pair
run_psql --quiet --command="UPDATE app_data.promotion_targets
  SET created_at = (clock_timestamp() + interval '5 seconds') - interval '12 months'
  WHERE promotion_target_id = '$first_target';" >/dev/null
original_due="$(run_psql --tuples-only --no-align --command="
  SELECT app_data.promotion_target_review_due_at('$first_target');")"
renewal_mutation="7efc-$run_token-renewal-first"
holder_app="7efc-holder-renewal-first-$run_token"
waiter_app="7efc-waiter-renewal-first-$run_token"
start_holder "$holder_app" "7efc-ready-renewal-first-$run_token" "$(renewal_sql)"
start_waiter "$waiter_app" "$(expiry_sql)"
wait_for_exact_blocker "$waiter_app" "$holder_app"
deadline_passed='f'
for _ in $(seq 1 300); do
  deadline_passed="$(run_psql --tuples-only --no-align --command="
    SELECT clock_timestamp() >= '$original_due'::timestamptz;" | tr -d '[:space:]')"
  [[ "$deadline_passed" == 't' ]] && break
  sleep 0.05
done
[[ "$deadline_passed" == 't' ]] || { echo '0120 原保留截止未到达。' >&2; exit 1; }
release_holder
collect_waiter renewal-first 22023
assert_waiter_rollback
assert_open renewal-first-zero-expiry
assert_true renewal-first-latest-reference "SELECT
  (SELECT count(*) = 1 FROM app_data.promotion_target_retention_events
    WHERE promotion_target_id = '$first_target' AND event_type = 'renewed'
      AND mutation_id = '$renewal_mutation' AND occurred_at < '$original_due'::timestamptz)
  AND app_data.promotion_target_review_due_at('$first_target') > clock_timestamp();"

create_pair expiry-first-renewal
activate_pair
make_due
renewal_mutation="7efc-$run_token-expiry-first-renewal"
run_race expiry-first-renewal "$(expiry_sql)" "$(renewal_sql)" 42501
assert_expired expiry-first-renewal
assert_true expiry-first-no-renewal "SELECT NOT EXISTS (
  SELECT 1 FROM app_data.promotion_target_retention_events WHERE mutation_id = '$renewal_mutation');"

create_pair policy-first
activate_pair
run_psql --quiet --command="UPDATE app_data.promotion_targets
  SET created_at = clock_timestamp() - interval '2 months'
  WHERE promotion_target_id = '$first_target';" >/dev/null
assert_true policy-first-initial-future "SELECT app_data.promotion_target_review_due_at('$first_target') > clock_timestamp();"
run_race policy-first "$(policy_sql 1)" "$(expiry_sql)" success
assert_expired policy-first
assert_true policy-first-current-policy "SELECT retention_months = 1
  FROM app_data.promotion_target_retention_policies WHERE workspace_id = '$workspace_id';"
run_psql --quiet --command="$(policy_sql 12)" >/dev/null

create_pair expiry-first-policy
activate_pair
make_due
run_race expiry-first-policy "$(expiry_sql)" "$(policy_sql 1)" success
first_time="$(sed -n '/^[0-9][0-9][0-9][0-9]-/p' "$temporary_directory/holder.out")"
assert_expired expiry-first-policy
assert_true expiry-first-policy-history "SELECT
  (SELECT ended_at_utc = '$first_time'::timestamptz FROM app_private.personal_target_merge_end_events_v1
    WHERE generation_id = '$generation_id')
  AND (SELECT retention_months = 1 FROM app_data.promotion_target_retention_policies WHERE workspace_id = '$workspace_id');"
replay_time="$(run_psql --tuples-only --no-align --command="$(expiry_sql)")"
[[ "$replay_time" == "$first_time" ]] || { echo '0120 policy 改动后的 replay 时间变化。' >&2; exit 1; }
run_psql --quiet --command="$(policy_sql 12)" >/dev/null

create_pair known-source-end-first
activate_pair
run_race known-source-end-first "$(ordinary_end_sql)" "$(expiry_sql)" 23505
assert_true known-source-end-first-zero-expiry "SELECT
  (SELECT count(*) = 1 FROM app_private.personal_target_merge_end_events_v1
    WHERE generation_id = '$generation_id' AND request_id = '$expiry_request'
      AND operation = 'personal_target_known_source_merge_end' AND reason = 'known_source_split')
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '$generation_id')
  AND (SELECT count(*) = 2 AND bool_and(status = 'active' AND phone = '+1 773 555 0120' AND anonymized_at IS NULL)
    FROM app_data.promotion_targets WHERE promotion_target_id IN ('$first_target','$second_target'))
  AND (SELECT count(*) = 2 AND bool_and(ended_at IS NULL) FROM app_data.promotion_target_assignments
    WHERE promotion_target_id IN ('$first_target','$second_target') AND app_user_id = '$app_user_id')
  AND NOT EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events
    WHERE promotion_target_id IN ('$first_target','$second_target'));"

create_pair expiry-first-known-source-end
activate_pair
make_due
run_race expiry-first-known-source-end "$(expiry_sql)" "$(ordinary_end_sql)" 23505
assert_expired expiry-first-known-source-end

create_pair fact-first
activate_pair
make_due
contact_id="7efc-$run_token-fact-first"
run_race fact-first "$(fact_sql "$contact_id")" "$(expiry_sql)" 22023
grep -q '^accepted$' "$temporary_directory/holder.out"
assert_open fact-first-zero-expiry
assert_true fact-first-current-reference "SELECT
  (SELECT count(*) = 1 AND bool_and(merge_generation_id = '$generation_id'::uuid)
    FROM app_data.contact_target_links WHERE contact_id = '$contact_id')
  AND app_data.promotion_target_review_due_at('$first_target') > clock_timestamp()
  AND app_data.promotion_target_review_due_at('$second_target') > clock_timestamp();"

create_pair expiry-first-fact
activate_pair
make_due
contact_id="7efc-$run_token-expiry-first-fact"
holder_app="7efc-holder-expiry-first-fact-$run_token"
waiter_app="7efc-waiter-expiry-first-fact-$run_token"
start_holder "$holder_app" "7efc-ready-expiry-first-fact-$run_token" "$(expiry_sql)"
start_waiter "$waiter_app" "$(fact_sql "$contact_id")"
wait_for_exact_blocker "$waiter_app" "$holder_app"
assert_true expiry-holds-no-contact-lock "SELECT NOT EXISTS (
  SELECT 1 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
  WHERE a.application_name = '$holder_app' AND l.granted AND l.mode <> 'AccessShareLock' AND l.relation IN (
    'app_data.contacts'::regclass,'app_data.contact_revisions'::regclass));"
release_holder
collect_waiter expiry-first-fact 22023
assert_waiter_rollback
assert_expired expiry-first-fact
assert_true expiry-first-fact-zero-writes "SELECT
  NOT EXISTS (SELECT 1 FROM app_data.contact_target_links WHERE contact_id = '$contact_id')
  AND NOT EXISTS (SELECT 1 FROM app_data.contacts WHERE contact_id = '$contact_id')
  AND NOT EXISTS (SELECT 1 FROM app_data.contact_revisions WHERE contact_id = '$contact_id');"

# Follow export's creation-time SHARE order, deliberately opposite UUID order.
create_pair export-order
activate_pair
run_psql --quiet --command="UPDATE app_data.promotion_targets
  SET created_at = clock_timestamp() - interval '13 months'
  WHERE promotion_target_id = '$second_target';" >/dev/null
assert_true reversed-export-order "SELECT a.promotion_target_id < b.promotion_target_id AND a.created_at > b.created_at
  FROM app_data.promotion_targets a CROSS JOIN app_data.promotion_targets b
  WHERE a.promotion_target_id = '$first_target' AND b.promotion_target_id = '$second_target';"
holder_app="7efc-holder-export-$run_token"
waiter_app="7efc-waiter-export-expiry-$run_token"
start_holder "$holder_app" "7efc-ready-export-first-$run_token" \
  "SELECT promotion_target_id FROM app_data.promotion_targets WHERE promotion_target_id = '$second_target' FOR SHARE;"
start_waiter "$waiter_app" "$(expiry_sql)"
wait_for_exact_blocker "$waiter_app" "$holder_app"
printf "SELECT promotion_target_id FROM app_data.promotion_targets WHERE promotion_target_id = '%s' ORDER BY created_at,promotion_target_id FOR SHARE; SELECT pg_advisory_lock(hashtextextended('%s',0));\n" \
  "$first_target" "7efc-ready-export-second-$run_token" >&3
wait_for_ready "7efc-ready-export-second-$run_token"
wait_for_exact_blocker "$waiter_app" "$holder_app"
release_holder
collect_waiter export-order success
assert_expired export-order

echo '0120 concurrency passed: exact expiry replay/request contest, renewal/policy/end/fact orderings, rollback, and export SHARE order.'
