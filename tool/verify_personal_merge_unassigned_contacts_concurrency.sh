#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
holder_pid=''
waiter_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${holder_pid}" "${waiter_pid}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}/holder.fifo" "${temporary_directory}/holder.out" "${temporary_directory}/waiter.out" "${temporary_directory}/isolation.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT
assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || { echo "0127 ${label} invariant failed: ${result}" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7eoc-unassigned-contact.example.test/auth/v1'
subject="7eoc-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"${context}"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0127 无法取得 personal context。' >&2; exit 1; }
done
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name, coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname || '.' || tablename,schemaname,tablename), ' UNION ALL ' ORDER BY schemaname,tablename) || ') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
business_state() { run_psql --tuples-only --no-align --command="${state_query}"; }

new_generation() {
  local label="$1" preview_id
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('$app_user_id','$workspace_id','$project_id',
      'person','0127 first $label $run_token','+1 312 555 0127',NULL,'7eoc-$label-$run_token-first');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('$app_user_id','$workspace_id','$project_id',
      'person','0127 second $label $run_token','+1 312 555 0127',NULL,'7eoc-$label-$run_token-second');")"
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id
    FROM app_data.preview_personal_target_pair_v1('$issuer','$subject','$project_id','$first_target','$second_target');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$first_target','$first_target','$first_target','$second_target');")"
  contact_id="7eoc-$label-$run_token-contact"
  request_id="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
  end_request_id="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
  for fixture_id in "$first_target" "$second_target" "$generation_id" "$request_id" "$end_request_id"; do
    [[ "$fixture_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0127 无法建立 generation。' >&2; exit 1; }
  done
  run_psql --quiet --command="SELECT result_code FROM app_data.apply_contact_submit_v3(
    '$app_user_id','7eoc-$label-$run_token-submit',1,'contact.submit.v1','7eoc-device','$contact_id',0,
    jsonb_build_object('contactId','$contact_id','workspaceId','$workspace_id','projectId','$project_id',
      'questionnaireVersionId','$questionnaire_version_id','reason','0127 synthetic contact',
      'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
      'answers','[]'::jsonb,'targetLinks','[]'::jsonb));" >/dev/null
  stage_sql="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
    '$app_user_id','$workspace_id','$project_id','$request_id','$generation_id','$contact_id',1,2,'unknown',false,true);"
  end_sql="SELECT app_private.end_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id','$end_request_id','$generation_id',
    (SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('$generation_id')));"
  expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id','$end_request_id','$generation_id');"
  due_sql="UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '2 years'
    WHERE promotion_target_id IN ('$first_target','$second_target');"
}

wait_for_holder() {
  local key="$1" ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('$key',0))
        THEN NOT pg_advisory_unlock(hashtextextended('$key',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == 't' ]] && return
    sleep 0.05
  done
  echo '0127 holder 未就绪。' >&2
  exit 1
}
wait_for_exact_blocker() {
  local waiter_app="$1" holder_app="$2" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid || '|' || holder.pid || '|' || waiter.wait_event
      FROM pg_catalog.pg_stat_activity waiter
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_catalog.pg_stat_activity holder ON holder.pid = blocked.pid
      WHERE waiter.application_name = '$waiter_app' AND holder.application_name = '$holder_app'
        AND waiter.wait_event_type = 'Lock';" | tr -d '[:space:]')"
    if [[ "$pair" == *'|'* ]]; then echo "0127 ${waiter_app}: exact waiter/holder PID and lock ${pair}"; return; fi
    sleep 0.05
  done
  echo '0127 未观察到精确 blocker。' >&2
  sed -n '/ERROR:/p' "${temporary_directory}/waiter.out" >&2
  exit 1
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_sqlstate="$4"
  local holder_app="7eoc-holder-$label-$run_token" waiter_app="7eoc-waiter-$label-$run_token"
  local ready_key="7eoc-ready-$label-$run_token" status=0 expected_state
  mkfifo "${temporary_directory}/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"${temporary_directory}/holder.fifo" >"${temporary_directory}/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"${temporary_directory}/holder.fifo"
  printf "BEGIN; %s %s SELECT pg_advisory_lock(hashtextextended('%s',0));\n" \
    "$holder_sql" "$state_query" "$ready_key" >&3
  wait_for_holder "$ready_key"
  PGAPPNAME="$waiter_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="$waiter_sql" >"${temporary_directory}/waiter.out" 2>&1 &
  waiter_pid=$!
  wait_for_exact_blocker "$waiter_app" "$holder_app"
  expected_state="$(sed -n '/^{/p' "${temporary_directory}/holder.out")"
  [[ -n "$expected_state" ]] || { echo '0127 missing holder snapshot。' >&2; exit 1; }
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "$holder_pid"
  holder_pid=''
  rm -f "${temporary_directory}/holder.fifo"
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_sqlstate" == 'success' ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '/ERROR:/p' "${temporary_directory}/waiter.out" >&2; exit 1; }
  else
    if [[ "$status" -eq 0 ]] || ! grep -q "ERROR:  ${expected_sqlstate}:" "${temporary_directory}/waiter.out"; then
      echo "0127 ${label} expected ${expected_sqlstate}, status ${status}。" >&2
      sed -n '/ERROR:/p' "${temporary_directory}/waiter.out" >&2
      exit 1
    fi
    [[ "$expected_state" == "$(business_state)" ]] \
      || { echo "0127 ${label} rejected waiter left partial state。" >&2; exit 1; }
  fi
}

new_generation stage-first
run_race stage-first "$stage_sql" "$end_sql" 55000
assert_true stage-first-pending "SELECT count(*) = 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
  JOIN app_private.personal_merge_unassigned_contact_requests_v1 header USING (pending_fact_id)
  WHERE header.generation_id = '$generation_id';"
assert_true stage-first-active "SELECT count(*) = 2 FROM app_private.personal_target_merge_active_members_v1
  WHERE generation_id = '$generation_id';"
preserved_generation="$generation_id"

new_generation end-first
run_race end-first "$end_sql" "$stage_sql" 42501

new_generation request-drift
drift_sql="${stage_sql/,1,2,\'unknown\'/,1,3,\'unknown\'}"
[[ "$drift_sql" != "$stage_sql" ]] || { echo '0127 drift fixture unchanged。' >&2; exit 1; }
run_race request-drift "$stage_sql" "$drift_sql" 23505

new_generation stage-expiry
contact_before="$(run_psql --tuples-only --no-align --command="SELECT to_jsonb(row) FROM app_data.contacts row WHERE contact_id='$contact_id';")"
run_race stage-expiry "$stage_sql $due_sql" "$expiry_sql" success
assert_true expiry-purged "SELECT count(*) = 1 FROM app_private.personal_merge_unassigned_contact_purges_v1
  WHERE generation_id = '$generation_id';"
assert_true expiry-no-payload "SELECT NOT EXISTS (SELECT 1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
  JOIN app_private.personal_merge_unassigned_contact_requests_v1 header USING (pending_fact_id)
  WHERE header.generation_id = '$generation_id');"
assert_true expiry-two-anonymized "SELECT count(*)=2 AND bool_and(status='anonymized') FROM app_data.promotion_targets
  WHERE promotion_target_id IN ('$first_target','$second_target');"
[[ "$contact_before" == "$(run_psql --tuples-only --no-align --command="SELECT to_jsonb(row) FROM app_data.contacts row WHERE contact_id='$contact_id';")" ]] \
  || { echo '0127 expiry changed anonymous contact。' >&2; exit 1; }
assert_true expiry-other-generation "SELECT count(*)=1 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
  JOIN app_private.personal_merge_unassigned_contact_requests_v1 header USING (pending_fact_id)
  WHERE header.generation_id='$preserved_generation';"

new_generation expiry-first
run_race expiry-first "$due_sql $expiry_sql" "$stage_sql" 42501

new_generation actor-revoked
run_race actor-revoked "SELECT app_private.acquire_personal_target_merge_generation_fence_v1();
  UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';" "$stage_sql" 42501
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$app_user_id';"

# Isolation and lifecycle replay checks use a new actor with no prior state.
issuer="https://7eoc-unassigned-contact-isolation.example.test/auth/v1"
subject="7eoc-isolation-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"${context}"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0150 无法取得 isolation actor context。' >&2; exit 1; }
done
new_generation isolation-lifecycle

expect_stage_isolation_rejection() {
  local phase="$1" isolation="$2" before_state status=0 error_line
  before_state="$(business_state)"
  run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $stage_sql COMMIT;" \
    >"${temporary_directory}/isolation.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/p' "${temporary_directory}/isolation.out" | head -n 1)"
  if [[ "$status" -eq 0 || "$error_line" != 'ERROR:  0A000: unassigned contact staging requires read committed' ]]; then
    echo "0150 ${phase} in ${isolation} expected exact 0A000, status ${status}: ${error_line}" >&2
    sed -n '/^ERROR:/p' "${temporary_directory}/isolation.out" >&2
    exit 1
  fi
  [[ "$(business_state)" == "$before_state" ]] || { echo "0150 ${phase} in ${isolation} changed business state." >&2; exit 1; }
}

for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  expect_stage_isolation_rejection first "$isolation"
done

pending_id="$(run_psql --tuples-only --no-align --command="$stage_sql" | tr -d '[:space:]')"
[[ "$pending_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0150 READ COMMITTED stage returned no pending ID.' >&2; exit 1; }
replay_state_sql="SELECT snapshot.state - 'app_private.personal_target_merge_generation_fence_v1'
  FROM (${state_query%;}) AS snapshot(state);"
epoch_sql='SELECT epoch FROM app_private.personal_target_merge_generation_fence_v1 WHERE fence_key;'
before_replay="$(run_psql --tuples-only --no-align --command="$replay_state_sql")"
before_epoch="$(run_psql --tuples-only --no-align --command="$epoch_sql")"
replay_id="$(run_psql --tuples-only --no-align --command="$stage_sql" | tr -d '[:space:]')"
[[ "$replay_id" == "$pending_id" ]] || { echo '0150 READ COMMITTED replay did not preserve pending ID.' >&2; exit 1; }
if [[ "$(run_psql --tuples-only --no-align --command="$replay_state_sql")" != "$before_replay" \
  || "$(run_psql --tuples-only --no-align --command="$epoch_sql")" != "$((before_epoch + 1))" ]]; then
  echo '0150 READ COMMITTED replay did not preserve all state except one fence increment.' >&2
  exit 1
fi

for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  expect_stage_isolation_rejection replay "$isolation"
done

# Hold the actor's active/pending replay snapshot while real account deletion
# commits. The stale RR replay must hit the guard; a fresh RC replay must see
# the lifecycle revocation and leave the valid deletion state unchanged.
deletion_request="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]')"
mkfifo "${temporary_directory}/holder.fifo"
"${psql_base[@]}" --quiet --tuples-only --no-align \
  <"${temporary_directory}/holder.fifo" >"${temporary_directory}/holder.out" 2>&1 &
holder_pid=$!
exec 3>"${temporary_directory}/holder.fifo"
printf '%s\n%s\n' \
  "BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT 'SNAPSHOT|' || (SELECT status FROM app_data.app_users WHERE app_user_id='$app_user_id') || '|' || (SELECT count(*) FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE request_id='$request_id'::uuid AND pending_fact_id='$pending_id'::uuid);" \
  '\echo SNAPSHOT_READY' >&3
for _ in $(seq 1 200); do
  grep -q '^SNAPSHOT_READY$' "${temporary_directory}/holder.out" && break
  sleep 0.05
done
if ! grep -q '^SNAPSHOT_READY$' "${temporary_directory}/holder.out" \
  || ! grep -q '^SNAPSHOT|active|1$' "${temporary_directory}/holder.out"; then
  echo '0150 could not establish old active-actor pending replay snapshot.' >&2
  sed -n '1,80p' "${temporary_directory}/holder.out" >&2
  exit 1
fi
run_psql --quiet --command="SELECT * FROM app_private.request_account_deletion_v1('$app_user_id','$deletion_request');" >/dev/null
deletion_state="$(business_state)"
deletion_valid="$(run_psql --tuples-only --no-align --command="
  SELECT actor.status='deletion_pending'
    AND deletion.status='deletion_pending'
    AND deletion.deletion_request_id='$deletion_request'::uuid
    AND EXISTS (SELECT 1 FROM app_private.account_deletion_request_claims claim
      WHERE claim.request_id='$deletion_request'::uuid AND claim.actor_app_user_id='$app_user_id'::uuid)
    AND EXISTS (SELECT 1 FROM app_private.account_deletion_audit_events audit
      WHERE audit.request_id='$deletion_request'::uuid AND audit.operation='account-deletion-request:v1')
  FROM app_data.app_users actor JOIN app_private.account_deletion_current deletion USING(app_user_id)
  WHERE actor.app_user_id='$app_user_id'::uuid;" | tr -d '[:space:]')"
[[ "$deletion_valid" == 't' ]] || { echo '0150 real account deletion did not commit valid lifecycle state.' >&2; exit 1; }
printf '%s\nCOMMIT;\n\\q\n' "$stage_sql" >&3
exec 3>&-
holder_status=0
wait "$holder_pid" || holder_status=$?
holder_pid=''
stale_error="$(sed -n '/^ERROR:/p' "${temporary_directory}/holder.out" | head -n 1)"
if [[ "$holder_status" -eq 0 || "$stale_error" != 'ERROR:  0A000: unassigned contact staging requires read committed' ]]; then
  echo "0150 stale RR replay expected exact isolation guard, status ${holder_status}: ${stale_error}" >&2
  sed -n '/^ERROR:/p' "${temporary_directory}/holder.out" >&2
  exit 1
fi
rm -f "${temporary_directory}/holder.fifo"
rc_status=0
run_psql --quiet --command="$stage_sql" >"${temporary_directory}/waiter.out" 2>&1 || rc_status=$?
rc_error="$(sed -n '/^ERROR:/p' "${temporary_directory}/waiter.out" | head -n 1)"
if [[ "$rc_status" -eq 0 || "$rc_error" != 'ERROR:  42501: known-source personal merge split plan is forbidden' ]]; then
  echo "0150 fresh RC replay after deletion expected exact 42501, status ${rc_status}: ${rc_error}" >&2
  sed -n '/^ERROR:/p' "${temporary_directory}/waiter.out" >&2
  exit 1
fi
[[ "$(business_state)" == "$deletion_state" ]] || { echo '0150 stale RR or forbidden fresh RC replay changed state after account deletion.' >&2; exit 1; }

echo '0127 concurrency and 0150 isolation checks passed: first/replay all-isolation guards, READ COMMITTED idempotency, and lifecycle-revocation replay ordering.'
