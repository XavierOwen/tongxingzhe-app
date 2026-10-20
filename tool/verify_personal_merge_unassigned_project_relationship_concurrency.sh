#!/usr/bin/env bash

set -euo pipefail
: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("$psql_command" "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
holder_pid=''; waiter_pid=''; holder_app=''; waiter_app=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "$holder_pid" "$waiter_pid"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then kill "$pid" >/dev/null 2>&1 || true; fi
    wait "$pid" >/dev/null 2>&1 || true
  done
  if [[ -n "$holder_app" || -n "$waiter_app" ]]; then
    run_psql --quiet --command="SELECT pg_terminate_backend(pid) FROM pg_stat_activity
      WHERE application_name IN('$holder_app','$waiter_app') AND pid<>pg_backend_pid();" >/dev/null 2>&1 || true
  fi
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" "$temporary_directory/waiter.out" "$temporary_directory/isolation.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --quiet --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0136 $1 invariant failed: $result" >&2; exit 1; }
}
new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();'; }
issuer='https://7ey-project-facts.example.test'
subject="owner-$run_token"
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.bootstrap_personal_context('$issuer','$subject');")"
IFS='|' read -r actor workspace project questionnaire <<<"$context"
run_psql --quiet --command="SELECT count(*) FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" >/dev/null
for id in "$actor" "$workspace" "$project"; do
  [[ "$id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0136 missing personal context' >&2; exit 1; }
done
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM ('||string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN('app_data','app_private');")"
database_state() { run_psql --tuples-only --no-align --command="$state_query"; }
stage_sql() {
  printf "SELECT * FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
    '%s','%s','%s','%s','%s',2,'paused','0136 private note','progress_update','0136 detail');" "$actor" "$workspace" "$project" "$request" "$generation"
}
new_pair() {
  local label="$1" preview
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$actor','$workspace','$project','person','0136 first $label $run_token','+1 312 555 0136',NULL,'7ey-first-$label-$run_token');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$actor','$workspace','$project','person','0136 second $label $run_token','+1 312 555 0136',NULL,'7ey-second-$label-$run_token');")"
  assert_true ordinary-project-entry "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
    '$actor','7ey-entry-$label-$run_token-submit',1,'contact.submit.v1','7ey-device','7ey-entry-$label-$run_token',0,
    jsonb_build_object('contactId','7ey-entry-$label-$run_token','workspaceId','$workspace','projectId','$project',
      'questionnaireVersionId','$questionnaire','reason','0136 project entry','occurredAtUtc','2024-01-01T00:00:00Z',
      'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(jsonb_build_object(
        'targetId','$first_target','targetType','person','responseLevel',NULL,'followUpConsent','unknown',
        'institutionRepresentativeConfirmed',false,'confirmStageZero',true))));"
  run_psql --quiet --command="SELECT * FROM app_data.update_promotion_target_relationship(
    '$actor','$workspace','$project','$first_target',1,1,'active','0136 existing known source','progress_update',NULL,'7ey-known-$label-$run_token',NULL);" >/dev/null
  assert_true ordinary-relationship-seed "SELECT current_revision=2 AND current_stage=1 FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id='$first_target' AND project_id='$project';"
  preview="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
    '$issuer','$subject','$project','$first_target','$second_target');")"
  generation="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '$actor','$project',gen_random_uuid(),'$preview','$first_target','$second_target','$first_target','$second_target');")"
  request="$(new_uuid)"
  fingerprint="$(run_psql --tuples-only --no-align --command="SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('$generation');")"
  split_sql="SELECT app_private.end_known_source_personal_target_merge_generation_v1('$actor','$workspace','$project',gen_random_uuid(),'$generation','$fingerprint');"
  expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1('$actor','$workspace','$project',gen_random_uuid(),'$generation');"
  due_sql="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '14 months' WHERE promotion_target_id IN('$first_target','$second_target');"
  request_key="personal-merge-unassigned-project-relationship:$actor:$request"
}
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT EXISTS(SELECT 1 FROM pg_locks locks
      JOIN pg_stat_activity activity ON activity.pid=locks.pid WHERE activity.application_name='$holder_app'
        AND locks.granted AND locks.locktype='advisory' AND locks.objsubid=1
        AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
        AND locks.classid=((hashtextextended('$1',0)>>32)&4294967295)::oid
        AND locks.objid=(hashtextextended('$1',0)&4294967295)::oid);" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    if ! kill -0 "$holder_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo '0136 holder did not acquire its ready lock' >&2
  sed -n '1,120p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local key="$1" predicate pair
  predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid
    AND EXISTS(SELECT 1 FROM pg_locks tuple_lock WHERE tuple_lock.pid=waiter.pid
      AND tuple_lock.locktype='tuple' AND tuple_lock.relation='app_private.personal_target_merge_generation_fence_v1'::regclass)"
  if [[ -n "$key" ]]; then
    predicate="locks.locktype='advisory' AND locks.objsubid=1
      AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
      AND locks.classid=((hashtextextended('$key',0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended('$key',0)&4294967295)::oid"
  fi
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid||'|'||holder.pid||'|'||locks.locktype||'|'||
      coalesce(locks.transactionid::text,locks.classid::text||':'||locks.objid::text)
      FROM pg_stat_activity waiter JOIN LATERAL unnest(pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_stat_activity holder ON holder.pid=blocked.pid JOIN pg_locks locks ON locks.pid=waiter.pid AND NOT locks.granted
      WHERE waiter.application_name='$waiter_app' AND holder.application_name='$holder_app'
        AND waiter.datid=(SELECT oid FROM pg_database WHERE datname=current_database())
        AND waiter.wait_event_type='Lock' AND $predicate;" | tr -d '[:space:]')"
    [[ "$pair" == *'|'* ]] && { echo "0136 exact waiter/holder PID and lock: $pair"; return; }
    if ! kill -0 "$waiter_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo "0136 expected blocker PID or lock was not observed: $key" >&2
  run_psql --pset=pager=off --command="SELECT activity.application_name,activity.pid,activity.backend_xid,
    activity.wait_event_type,activity.wait_event,pg_blocking_pids(activity.pid),locks.locktype,locks.mode,
    locks.granted,locks.relation::regclass,locks.transactionid,locks.classid,locks.objid
    FROM pg_stat_activity activity LEFT JOIN pg_locks locks ON locks.pid=activity.pid
    WHERE activity.application_name IN('$holder_app','$waiter_app') AND locks.locktype IN('advisory','transactionid','tuple')
    ORDER BY activity.application_name,locks.granted,locks.locktype;" >&2
  sed -n '1,120p' "$temporary_directory/holder.out" >&2
  sed -n '1,120p' "$temporary_directory/waiter.out" >&2
  exit 1
}
assert_waiter_lock() {
  assert_true "$1" "SELECT EXISTS(SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
    WHERE activity.application_name='$waiter_app' AND locks.granted AND locks.locktype='advisory' AND locks.objsubid=1
      AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
      AND locks.classid=((hashtextextended('$2',0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended('$2',0)&4294967295)::oid);"
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_state="$4" expected_message="$5" key="${6:-}"
  local after_wait_sql="${7:-}" prelock_key="${8:-}" wait_deadline="${9:-no}" status=0 expected_snapshot due
  local ready_key="7ey-ready-$label-$run_token"
  holder_app="7ey-h-$label-$run_token"; waiter_app="7ey-w-$label-$run_token"
  mkfifo "$temporary_directory/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align --field-separator='|' \
    <"$temporary_directory/holder.fifo" >"$temporary_directory/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"$temporary_directory/holder.fifo"
  printf "BEGIN; %s SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$holder_sql" "$ready_key" >&3
  wait_for_holder "$ready_key"
  PGAPPNAME="$waiter_app" "${psql_base[@]}" --quiet --tuples-only --no-align --field-separator='|' \
    --command="BEGIN; $waiter_sql COMMIT;" >"$temporary_directory/waiter.out" 2>&1 &
  waiter_pid=$!
  wait_for_exact_blocker "$key"
  [[ -z "$prelock_key" ]] || assert_waiter_lock "$label-prelock" "$prelock_key"
  if [[ "$wait_deadline" == yes ]]; then
    assert_true waited-before-deadline "SELECT min(app_data.promotion_target_review_due_at(promotion_target_id))>clock_timestamp() FROM app_data.promotion_targets WHERE promotion_target_id IN('$first_target','$second_target');"
    due=f
    for _ in $(seq 1 300); do
      due="$(run_psql --tuples-only --no-align --command="SELECT min(app_data.promotion_target_review_due_at(promotion_target_id))<=clock_timestamp()
        FROM app_data.promotion_targets WHERE promotion_target_id IN('$first_target','$second_target');" | tr -d '[:space:]')"
      [[ "$due" == t ]] && break
      sleep 0.05
    done
    [[ "$due" == t ]] || { echo '0136 synthetic deadline did not pass' >&2; exit 1; }
  fi
  printf '%s %s COMMIT;\n\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '1,120p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_snapshot="$(sed -n '/^{/p' "$temporary_directory/holder.out")"
  [[ -n "$expected_snapshot" ]] || { echo '0136 holder snapshot missing' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_state" == success ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '1,120p' "$temporary_directory/waiter.out" >&2; exit 1; }
  else
    if [[ "$status" -eq 0 ]] || ! grep -Fq "ERROR:  $expected_state: $expected_message" "$temporary_directory/waiter.out"; then
      echo "0136 $label expected $expected_state / $expected_message, status $status" >&2
      sed -n '1,120p' "$temporary_directory/waiter.out" >&2; exit 1
    fi
    [[ "$expected_snapshot" == "$(database_state)" ]] || { echo "0136 $label rejection changed database facts" >&2; exit 1; }
  fi
}


echo '0136 exact request replay and request-before-generation-fence ordering'
new_pair same-request
replay_generation="$generation"; replay_request="$request"
run_race same-request "$(stage_sql)" "$(stage_sql)" success '' "$request_key"
first="$(awk 'index($0,"personal-merge-unassigned-project-relationship:v1|")==1 {print;exit}' "$temporary_directory/holder.out")"
second="$(awk 'index($0,"personal-merge-unassigned-project-relationship:v1|")==1 {print;exit}' "$temporary_directory/waiter.out")"
[[ -n "$first" && "$first" == "$second" && "$(awk -F'|' '{print NF}' <<<"$first")" -eq 3 ]] \
  || { echo '0136 exact three-field stage replay failed' >&2; exit 1; }
new_pair fence
run_race fence 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' "$(stage_sql)" success '' '' '' "$request_key"

echo '0136 stage and known-source split enforce both commit orders'
new_pair stage-before-split
run_race stage-before-split "$(stage_sql)" "$split_sql" 55000 'unassigned project relationship facts prevent known-source split'
new_pair split-before-stage
run_race split-before-stage "$split_sql" "$(stage_sql)" 42501 'known-source personal merge split plan is forbidden' '' '' "$request_key"

echo '0136 stage and retention expiry preserve the end receipt and purge every payload'
new_pair stage-before-expiry
run_race stage-before-expiry "$(stage_sql)" "$expiry_sql" success '' '' "$due_sql"
assert_true stage-then-expiry "SELECT count(*)=1 AND bool_and(purge.purged_at_utc=receipt.ended_at_utc)
  FROM app_private.personal_merge_unassigned_project_relationship_purges_v1 purge
  JOIN app_private.personal_target_merge_end_events_v1 receipt USING(generation_id)
  WHERE purge.generation_id='$generation';"
assert_true stage-payload-purged "SELECT NOT EXISTS(SELECT 1 FROM app_data.personal_merge_unassigned_project_relationship_facts_v1 fact
  JOIN app_private.personal_merge_unassigned_project_relationship_requests_v1 header USING(pending_fact_id) WHERE header.generation_id='$generation');"
new_pair expiry-before-stage
run_psql --quiet --command="$(stage_sql) $due_sql" >/dev/null
run_race expiry-before-stage "$expiry_sql" "$(stage_sql)" 42501 'known-source personal merge split plan is forbidden' '' '' "$request_key"

echo '0136 qualification and wall-clock retention are rechecked after waiting'
new_pair assignment-ended
run_race assignment-ended "SELECT app_private.acquire_personal_target_merge_generation_fence_v1();
  UPDATE app_data.promotion_target_assignments SET ended_at=clock_timestamp(),end_reason='0136 ended while waiting'
  WHERE promotion_target_id='$second_target' AND app_user_id='$actor' AND ended_at IS NULL;" \
  "$(stage_sql)" 42501 'known-source personal merge split plan is forbidden' '' '' "$request_key"
new_pair deadline
run_psql --quiet --command="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '12 months'+interval '8 seconds'
  WHERE promotion_target_id IN('$first_target','$second_target');" >/dev/null
run_race deadline 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' "$(stage_sql)" \
  42501 'unassigned project relationship generation is due' '' '' "$request_key" yes

echo '0136 first stage and live replay reject every non-RC mode without writes'
new_pair isolation-first
first_stage="$(stage_sql)"
request="$replay_request"; generation="$replay_generation"
replay_stage="$(stage_sql)"
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  for operation in first replay; do
    if [[ "$operation" == first ]]; then statement="$first_stage"; else statement="$replay_stage"; fi
    before="$(database_state)"
    if run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $statement COMMIT;" >"$temporary_directory/isolation.out" 2>&1; then
      echo "0136 $isolation $operation unexpectedly succeeded" >&2; exit 1
    fi
    grep -Fq 'ERROR:  0A000: unassigned project relationship requires read committed' "$temporary_directory/isolation.out" \
      || { sed -n '1,120p' "$temporary_directory/isolation.out" >&2; exit 1; }
    [[ "$before" == "$(database_state)" ]] || { echo "0136 $isolation $operation changed database facts" >&2; exit 1; }
  done
done
before="$(database_state)"
assert_true reader-real-read-only "BEGIN READ ONLY;
  SELECT current_setting('transaction_read_only')='on' AND plan->>'pending_count'='1' FROM
    (SELECT app_private.read_personal_merge_unassigned_project_relationship_plan_v1('$actor','$workspace','$project','$replay_generation') plan) document;
  COMMIT;"
[[ "$before" == "$(database_state)" ]] || { echo '0136 READ ONLY reader changed persisted state' >&2; exit 1; }
echo '0136 unassigned project relationship concurrency passed.'

