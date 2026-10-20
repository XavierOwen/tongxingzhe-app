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
  for pid in "$holder_pid" "$waiter_pid"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then kill "$pid" >/dev/null 2>&1 || true; fi
    wait "$pid" >/dev/null 2>&1 || true
  done
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" "$temporary_directory/waiter.out" "$temporary_directory/isolation.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0138 $1 invariant failed: $result" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7fa-resolution-confirmation.example.test/auth/v1'
subject="7fa-owner-$run_token"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$context"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0138 missing personal context。' >&2; exit 1; }
done
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
business_state() { run_psql --tuples-only --no-align --command="$state_query"; }

other_project_id="$(run_psql --tuples-only --no-align --command="SELECT project_id FROM app_data.create_personal_project_context('$issuer','$subject','0138 other project');")"
run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('$issuer','$subject','$project_id');" >/dev/null
stage_sql() {
  printf '%s' "SELECT * FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id',2,'paused','0138 pending raw note','progress_update',NULL);"
}
ordinary_sql() {
  printf '%s' "SELECT * FROM app_data.update_promotion_target_relationship(
    '$app_user_id','$workspace_id','$project_id','$first_target',$1,$3,'active','0138 ordinary note','progress_update',NULL,'$2',NULL)"
}
new_generation() {
  local label="$1" source key preview_id inventory
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0138 first $label $run_token','+1 312 555 0138',NULL,'7fa-$label-$run_token-first');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0138 second $label $run_token','+1 312 555 0138',NULL,'7fa-$label-$run_token-second');")"
  for source in "$first_target" "$second_target"; do
    key="7fa-$label-$run_token-$source"
    assert_true real-project-entry "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
      '$app_user_id','$key-submit',1,'contact.submit.v1','7fa-device','$key',0,
      jsonb_build_object('contactId','$key','workspaceId','$workspace_id','projectId','$project_id',
        'questionnaireVersionId','$questionnaire_version_id','reason','0138 real entry','occurredAtUtc','2020-01-01T00:00:00Z',
        'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
        'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(jsonb_build_object(
          'targetId','$source','targetType','person','responseLevel',NULL,'followUpConsent','unknown',
          'institutionRepresentativeConfirmed',false,'confirmStageZero',true))));"
  done
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
    '$issuer','$subject','$project_id','$first_target','$second_target');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$first_target','$first_target','$first_target','$second_target');")"
  request_id="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
  run_psql --quiet --command="$(stage_sql) $(stage_sql)" >/dev/null
  inventory="$(run_psql --tuples-only --no-align --command="SELECT app_private.read_personal_merge_unassigned_project_relationship_plan_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id');")"
  known_fingerprint="$(run_psql --tuples-only --no-align --command="SELECT '$inventory'::jsonb->'known_source_plan'->>'fact_fingerprint';")"
  pending_fingerprint="$(run_psql --tuples-only --no-align --command="SELECT '$inventory'::jsonb->>'pending_fingerprint';")"
  assignments="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'pending_fact_id',pending_fact_id,'source_target_id','$first_target') ORDER BY pending_fact_id)
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 WHERE generation_id='$generation_id';")"
  plan_sql="SELECT app_private.plan_personal_merge_project_relationship_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id','$known_fingerprint','$pending_fingerprint','$assignments'::jsonb)"
  resolution_plan="$(run_psql --tuples-only --no-align --command="$plan_sql;")"
  resolution_fingerprint="$(run_psql --tuples-only --no-align --command="SELECT '$resolution_plan'::jsonb->>'resolution_fingerprint';")"
  choices="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object('project_id',slot->>'project_id',
    'source_target_id',slot->>'source_target_id','candidate_kind','pending','pending_fact_id',slot->'pending_fact_ids'->0))
    FROM jsonb_array_elements('$resolution_plan'::jsonb->'source_slots') slot;")"
  confirm_sql="SELECT app_private.confirm_personal_merge_project_relationship_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$request_id','$generation_id',
    '$known_fingerprint','$pending_fingerprint','$resolution_fingerprint','$assignments'::jsonb,'$choices'::jsonb);"
  revise_query="$(ordinary_sql 1 "7fa-$label-$run_token-ordinary" 3)"
  due_sql="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years'
    WHERE promotion_target_id IN ('$first_target','$second_target');"
  expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id');"
}
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('$1',0))
      THEN NOT pg_advisory_unlock(hashtextextended('$1',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    sleep 0.05
  done
  echo '0138 holder not ready。' >&2
  sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local waiter_app="$1" holder_app="$2" key="$3" pair lock_predicate
  lock_predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid"
  if [[ "$key" == row:* ]]; then
    lock_predicate="$lock_predicate AND EXISTS(SELECT 1 FROM pg_locks tuple_lock WHERE tuple_lock.pid=waiter.pid
      AND tuple_lock.locktype='tuple' AND tuple_lock.relation='${key#row:}'::regclass)"
  elif [[ -n "$key" ]]; then
    lock_predicate="locks.locktype='advisory' AND locks.objsubid=1 AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
      AND locks.classid=((hashtextextended('$key',0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended('$key',0)&4294967295)::oid"
  fi
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid||'|'||holder.pid||'|'||locks.locktype||'|'||
      coalesce(locks.transactionid::text,locks.classid::text||':'||locks.objid::text)
      FROM pg_stat_activity waiter JOIN LATERAL unnest(pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_stat_activity holder ON holder.pid=blocked.pid JOIN pg_locks locks ON locks.pid=waiter.pid AND NOT locks.granted
      WHERE waiter.application_name='$waiter_app' AND holder.application_name='$holder_app'
        AND waiter.wait_event_type='Lock' AND $lock_predicate;" | tr -d '[:space:]')"
    [[ "$pair" == *'|'* ]] && { echo "0138 $waiter_app exact waiter/holder PID and lock: $pair"; return; }
    sleep 0.05
  done
  echo '0138 exact blocker or requested lock missing.' >&2
  run_psql --command="SELECT activity.pid,activity.application_name,pg_blocking_pids(activity.pid),locks.locktype,locks.mode,locks.granted,
    locks.relation::regclass,locks.transactionid,locks.classid,locks.objid,locks.objsubid FROM pg_stat_activity activity
    LEFT JOIN pg_locks locks ON locks.pid=activity.pid WHERE activity.application_name IN ('$waiter_app','$holder_app')
    ORDER BY activity.pid,locks.granted,locks.locktype;" >&2
  sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
  exit 1
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_sqlstate="$4" key="${5:-}" after_wait_sql="${6:-}"
  local holder_app="7fa-holder-$label-$run_token" waiter_app="7fa-waiter-$label-$run_token"
  local ready_key="7fa-ready-$label-$run_token" status=0 expected_state
  mkfifo "$temporary_directory/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"$temporary_directory/holder.fifo" >"$temporary_directory/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"$temporary_directory/holder.fifo"
  printf "BEGIN; %s SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$holder_sql" "$ready_key" >&3
  wait_for_holder "$ready_key"
  PGAPPNAME="$waiter_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="$waiter_sql" >"$temporary_directory/waiter.out" 2>&1 &
  waiter_pid=$!
  wait_for_exact_blocker "$waiter_app" "$holder_app" "$key"
  printf '%s %s COMMIT;\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_state="$(sed -n '/^{"app_data\./p' "$temporary_directory/holder.out")"
  [[ -n "$expected_state" ]] || { echo '0138 missing holder snapshot。' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_sqlstate" == unchanged ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2; exit 1; }
  elif [[ "$status" -eq 0 ]] || ! grep -q "ERROR:  $expected_sqlstate:" "$temporary_directory/waiter.out"; then
    echo "0138 $label expected $expected_sqlstate, status $status。" >&2
    sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
    exit 1
  fi
  [[ "$expected_state" == "$(business_state)" ]] || { echo "0138 $label waiter changed persistent state。" >&2; exit 1; }
}

fence_row='row:app_private.personal_target_merge_generation_fence_v1'
new_generation ordinary-first
run_race ordinary-first "$revise_query;" "$confirm_sql" 23505 "$fence_row"
assert_true ordinary-retained "SELECT current_revision=2 AND current_stage=3 FROM app_data.promotion_target_project_relationships
  WHERE promotion_target_id='$first_target' AND project_id='$project_id';"

new_generation confirm-first
ordinary_after="BEGIN; DO \$test\$ DECLARE result jsonb; BEGIN
  SELECT changed.result INTO STRICT result FROM ($(ordinary_sql 4 "7fa-after-confirm-$run_token" 3)) changed;
  IF result->>'status' IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0138 ordinary writer rejected the confirmed head'; END IF;
END \$test\$; ROLLBACK;"
run_race confirm-first "$confirm_sql" "$ordinary_after" unchanged "$fence_row"
assert_true final-head "SELECT current_revision=4 AND current_stage=2 FROM app_data.promotion_target_project_relationships
  WHERE promotion_target_id='$first_target' AND project_id='$project_id';"

new_generation stage-first
run_race stage-first "$(stage_sql)" "$confirm_sql" 23505 "$fence_row"
assert_true all-three-pending "SELECT count(*)=3 FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 WHERE generation_id='$generation_id';"

new_generation pending-growth-after-wait
run_race pending-growth-after-wait 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' "$confirm_sql" 23505 "$fence_row" "$(stage_sql)"

new_generation confirm-before-stage
run_race confirm-before-stage "$confirm_sql" "$(stage_sql)" 42501 "$fence_row"

new_generation expiry-first
run_race expiry-first "$due_sql $expiry_sql" "$confirm_sql" 42501 "$fence_row"

new_generation confirm-before-expiry
run_race confirm-before-expiry "$confirm_sql" "$expiry_sql" 23505 "$fence_row"

new_generation exact-replay
run_race exact-replay "$confirm_sql" "$confirm_sql" unchanged "$app_user_id:$request_id"
assert_true one-request "SELECT count(*)=1 FROM app_private.personal_merge_project_relationship_resolution_requests_v1
  WHERE actor_app_user_id='$app_user_id' AND request_id='$request_id';"

new_generation request-drift
drift_sql="$(printf '%s' "$confirm_sql" | sed "s/$first_target/$second_target/g")"
[[ "$drift_sql" != "$confirm_sql" ]]
run_race request-drift "$confirm_sql" "$drift_sql" 23505 "$app_user_id:$request_id"

new_generation actor-status
run_race actor-status "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';" \
  "$confirm_sql" 42501 'row:app_data.app_users'
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$app_user_id';"

new_generation scope-after-wait
run_race scope-after-wait 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' "$confirm_sql" 42501 "$fence_row" \
  "SELECT * FROM app_data.select_personal_project_context('$issuer','$subject','$other_project_id');"
run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('$issuer','$subject','$project_id');" >/dev/null

new_generation due-after-wait
run_race due-after-wait "SELECT 1 FROM app_data.promotion_targets WHERE promotion_target_id='$first_target' FOR UPDATE;" \
  "$confirm_sql" 42501 'row:app_data.promotion_targets' "$due_sql"

expect_isolation_rejection() {
  local label="$1" isolation="$2" before_state status=0 error_line
  before_state="$(business_state)"
  run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $confirm_sql COMMIT;" >"$temporary_directory/isolation.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/p' "$temporary_directory/isolation.out" | head -n 1)"
  [[ "$status" -ne 0 && "$error_line" == 'ERROR:  0A000: pending project relationship resolution confirmation requires read committed' ]] || {
    echo "0138 $label expected 0A000 isolation error; status $status: $error_line" >&2
    exit 1
  }
  [[ "$(business_state)" == "$before_state" ]] || { echo "0138 $label changed persistent state." >&2; exit 1; }
}
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  label="$(printf '%s' "$isolation" | tr ' ' '-')"
  new_generation "first-$label"
  expect_isolation_rejection first "$isolation"
done
new_generation terminal-replay
confirm_expression="$(printf '%s' "$confirm_sql" | sed 's/;$//')"
confirmed_at="$(run_psql --tuples-only --no-align --command="SELECT extract(epoch FROM ($confirm_expression));")"
assert_true exact-rc-replay "SELECT extract(epoch FROM ($confirm_expression))=$confirmed_at;"
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  expect_isolation_rejection terminal-replay "$isolation"
done
echo '0138 exact-PID request/fence/user/target races and six non-RC first/replay rejections passed.'

