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
  [[ "${result}" == 't' ]] || { echo "0128 ${label} invariant failed: ${result}" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7eq-confirmation.example.test/auth/v1'
subject="7eq-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"${context}"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0128 无法取得 personal context。' >&2; exit 1; }
done
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name, coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname || '.' || tablename,schemaname,tablename), ' UNION ALL ' ORDER BY schemaname,tablename) || ') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
business_state() { run_psql --tuples-only --no-align --command="${state_query}"; }
submit_contact() {
  local contact_key="$1"
  assert_true submit-contact "SELECT result_code = 'accepted' FROM app_data.apply_contact_submit_v3(
    '$app_user_id','$contact_key-submit',1,'contact.submit.v1','7eq-device','$contact_key',0,
    jsonb_build_object('contactId','$contact_key','workspaceId','$workspace_id','projectId','$project_id',
      'questionnaireVersionId','$questionnaire_version_id','reason','0128 synthetic contact',
      'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
      'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
}
new_generation() {
  local label="$1" preview_id fingerprints
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('$app_user_id','$workspace_id','$project_id',
      'person','0128 first $label $run_token','+1 312 555 0128',NULL,'7eq-$label-$run_token-first');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('$app_user_id','$workspace_id','$project_id',
      'person','0128 second $label $run_token','+1 312 555 0128',NULL,'7eq-$label-$run_token-second');")"
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id
    FROM app_data.preview_personal_target_pair_v1('$issuer','$subject','$project_id','$first_target','$second_target');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$first_target','$first_target','$first_target','$second_target');")"
  contact_id="7eq-$label-$run_token-contact"
  request_id="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
  submit_contact "$contact_id"
  pending_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$contact_id',1,2,'unknown',false,true);")"
  for fixture_id in "$first_target" "$second_target" "$generation_id" "$request_id" "$pending_id"; do
    [[ "$fixture_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0128 无法建立 generation。' >&2; exit 1; }
  done
  fingerprints="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT
    plan->'known_source_plan'->>'fact_fingerprint',plan->>'pending_fingerprint'
    FROM (SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(
      '$app_user_id','$workspace_id','$project_id','$generation_id') plan) read_plan;")"
  IFS='|' read -r known_fingerprint pending_fingerprint <<<"${fingerprints}"
  [[ "$known_fingerprint" =~ ^[0-9a-f]{64}$ && "$pending_fingerprint" =~ ^[0-9a-f]{64}$ ]]
  confirm_sql="SELECT app_private.confirm_unassigned_personal_merge_contacts_v1(
    '$app_user_id','$workspace_id','$project_id','$request_id','$generation_id',
    '$known_fingerprint','$pending_fingerprint',
    '[{\"pending_fact_id\":\"$pending_id\",\"source_target_id\":\"$second_target\"}]'::jsonb);"
  revise_query="SELECT * FROM app_data.apply_contact_revise_v3(
    '$app_user_id','7eq-$label-$run_token-revise',1,'contact.revise.v1','7eq-device','$contact_id',1,
    (SELECT snapshot || jsonb_build_object('reason','0128 ordinary revision','interestLevel',3)
      FROM app_data.contact_revisions WHERE contact_id='$contact_id' AND revision_number=1))"
  expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id');"
  due_sql="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years'
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
  echo '0128 holder 未就绪。' >&2
  sed -n '/ERROR:/p' "${temporary_directory}/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local waiter_app="$1" holder_app="$2" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid || '|' || holder.pid || '|' || waiter.wait_event
      FROM pg_catalog.pg_stat_activity waiter
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_catalog.pg_stat_activity holder ON holder.pid=blocked.pid
      WHERE waiter.application_name='$waiter_app' AND holder.application_name='$holder_app'
        AND waiter.wait_event_type='Lock';" | tr -d '[:space:]')"
    if [[ "$pair" == *'|'* ]]; then echo "0128 ${waiter_app}: exact waiter/holder PID and lock ${pair}"; return; fi
    sleep 0.05
  done
  echo '0128 未观察到精确 blocker。' >&2
  sed -n '/ERROR:/p' "${temporary_directory}/waiter.out" >&2
  exit 1
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_sqlstate="$4" after_wait_sql="${5:-}"
  local holder_app="7eq-holder-$label-$run_token" waiter_app="7eq-waiter-$label-$run_token"
  local ready_key="7eq-ready-$label-$run_token" status=0 expected_state
  mkfifo "${temporary_directory}/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"${temporary_directory}/holder.fifo" >"${temporary_directory}/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"${temporary_directory}/holder.fifo"
  printf "BEGIN; %s SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$holder_sql" "$ready_key" >&3
  wait_for_holder "$ready_key"
  PGAPPNAME="$waiter_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="$waiter_sql" >"${temporary_directory}/waiter.out" 2>&1 &
  waiter_pid=$!
  wait_for_exact_blocker "$waiter_app" "$holder_app"
  printf '%s %s COMMIT;\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid"
  holder_pid=''
  rm -f "${temporary_directory}/holder.fifo"
  expected_state="$(sed -n '/^{/p' "${temporary_directory}/holder.out")"
  [[ -n "$expected_state" ]] || { echo '0128 missing holder snapshot。' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_sqlstate" == 'unchanged' ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '/ERROR:/p' "${temporary_directory}/waiter.out" >&2; exit 1; }
  elif [[ "$status" -eq 0 ]] || ! grep -q "ERROR:  ${expected_sqlstate}:" "${temporary_directory}/waiter.out"; then
    echo "0128 ${label} expected ${expected_sqlstate}, status ${status}。" >&2
    sed -n '/ERROR:/p' "${temporary_directory}/waiter.out" >&2
    exit 1
  fi
  [[ "$expected_state" == "$(business_state)" ]] \
    || { echo "0128 ${label} waiter left unexpected business state。" >&2; exit 1; }
}

new_generation ordinary-first
run_race ordinary-first "$revise_query;" "$confirm_sql" 23505
assert_true stale-pending "SELECT count(*)=1 FROM app_data.personal_merge_unassigned_contact_facts_v1
  WHERE pending_fact_id='$pending_id';"

new_generation confirm-first
overlap_query="SELECT * FROM app_data.apply_contact_revise_v3(
  '$app_user_id','7eq-overlap-$run_token',1,'contact.revise.v1','7eq-device','$contact_id',1,
  (SELECT snapshot || jsonb_build_object('reason','0128 competing source',
    'targetLinks',jsonb_build_array(jsonb_build_object('targetId','$first_target','targetType','person',
      'responseLevel',3,'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
    FROM app_data.contact_revisions WHERE contact_id='$contact_id' AND revision_number=1))"
# Roll back ordinary-protocol diagnostics after checking their normal conflict or merge result.
ordinary_conflict="BEGIN; DO \$test\$ BEGIN
  IF (SELECT result_code FROM ($overlap_query) result) IS DISTINCT FROM 'conflict'
    THEN RAISE EXCEPTION 'ordinary revision must conflict'; END IF;
  END \$test\$; ROLLBACK;"
run_race confirm-first "$confirm_sql" "$ordinary_conflict" unchanged
assert_true applied-nonretained "SELECT count(*)=1 FROM app_private.personal_merge_contact_applications_v1
  WHERE pending_fact_id='$pending_id' AND source_target_id='$second_target' AND to_revision_number=2;"

new_generation disjoint-revise
ordinary_merge="BEGIN; DO \$test\$ DECLARE result_value text; BEGIN
  SELECT result_code INTO result_value FROM ($revise_query) result;
  IF result_value IS DISTINCT FROM 'accepted'
    OR NOT EXISTS (SELECT 1 FROM app_data.contacts WHERE contact_id='$contact_id' AND current_revision=3 AND interest_level=3)
    OR (SELECT count(*) FROM app_data.contact_target_links WHERE contact_id='$contact_id'
      AND revision_number=3 AND promotion_target_id='$second_target') <> 1
    THEN RAISE EXCEPTION 'ordinary disjoint revision must retain confirmed source'; END IF;
  END \$test\$; ROLLBACK;"
run_race disjoint-revise "$confirm_sql" "$ordinary_merge" unchanged

new_generation late-stage
late_contact="$contact_id-late"
submit_contact "$late_contact"
stage_sql="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
  '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$late_contact',1,3,'unknown',false,true);"
run_race late-stage "$confirm_sql" "$stage_sql" 42501

new_generation added-pending
late_contact="$contact_id-late"
submit_contact "$late_contact"
stage_sql="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
  '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$late_contact',1,3,'unknown',false,true);"
run_race added-pending 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$confirm_sql" 23505 "$stage_sql"
assert_true complete-pending "SELECT count(*)=2 FROM app_data.personal_merge_unassigned_contact_facts_v1 payload
  JOIN app_private.personal_merge_unassigned_contact_requests_v1 header USING(pending_fact_id)
  WHERE header.generation_id='$generation_id';"

new_generation expiry-first
run_race expiry-first "$due_sql $expiry_sql" "$confirm_sql" 42501
assert_true expiry-not-confirmation "SELECT NOT EXISTS (SELECT 1 FROM app_private.personal_merge_contact_confirmation_requests_v1
  WHERE generation_id='$generation_id');"

new_generation confirm-before-expiry
run_race confirm-before-expiry "$confirm_sql" "$expiry_sql" 23505

new_generation exact-replay
run_race exact-replay "$confirm_sql" "$confirm_sql" unchanged
assert_true one-confirmation "SELECT count(*)=1 FROM app_private.personal_merge_contact_confirmation_requests_v1
  WHERE generation_id='$generation_id';"

new_generation request-drift
drift_sql="${confirm_sql//$second_target/$first_target}"
[[ "$drift_sql" != "$confirm_sql" ]]
run_race request-drift "$confirm_sql" "$drift_sql" 23505

new_generation actor-revoked
run_race actor-revoked "SELECT app_private.acquire_personal_target_merge_generation_fence_v1();
  UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';" "$confirm_sql" 42501
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$app_user_id';"

echo '0128 concurrency passed: exact PIDs, ordinary revisions, post-prelock pending growth, stage/expiry, terminal replay/drift, locked reauthorization and full-state rollback.'
