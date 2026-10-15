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
  rm -f "${temporary_directory}/holder.fifo" "${temporary_directory}/holder.out" "${temporary_directory}/waiter.out"
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

echo '0127 concurrency passed: exact request/fence PIDs, stage/end/expiry ordering, canonical drift rejection, locked reauthorization, full rollback and generation-scoped purge.'
