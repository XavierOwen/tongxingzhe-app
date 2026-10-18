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
  [[ "$result" == t ]] || { echo "0130 $1 invariant failed: $result" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7es-resolution-confirmation.example.test/auth/v1'
subject="7es-owner-$run_token"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$context"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0130 missing personal context。' >&2; exit 1; }
done
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
business_state() { run_psql --tuples-only --no-align --command="$state_query"; }
submit_contact() {
  local key="$1"
  assert_true submit "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
    '$app_user_id','$key-submit',1,'contact.submit.v1','7es-device','$key',0,
    jsonb_build_object('contactId','$key','workspaceId','$workspace_id','projectId','$project_id',
      'questionnaireVersionId','$questionnaire_version_id','reason','0130 original contact','occurredAtUtc',clock_timestamp(),
      'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
}
ordinary_revision() {
  local key="$1" revision="$2" command="$3" interest_level="${4:-3}"
  printf '%s' "SELECT * FROM app_data.apply_contact_revise_v3(
    '$app_user_id','$command',1,'contact.revise.v1','7es-device','$key',$revision,
    (SELECT snapshot || jsonb_build_object('reason','0130 ordinary revision','interestLevel',$interest_level)
      FROM app_data.contact_revisions WHERE contact_id='$key' AND revision_number=$revision))"
}
stage_contact() {
  printf '%s' "SELECT app_private.stage_unassigned_personal_merge_contact_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$1',$2,$3,'unknown',false,true);"
}
new_generation() {
  local label="$1" key preview_id fingerprints
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0130 first $label $run_token','+1 312 555 0130',NULL,'7es-$label-$run_token-first');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0130 second $label $run_token','+1 312 555 0130',NULL,'7es-$label-$run_token-second');")"
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
    '$issuer','$subject','$project_id','$first_target','$second_target');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$first_target','$first_target','$first_target','$second_target');")"
  request_id="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
  contact_id="7es-$label-$run_token-a"
  other_contact_id="7es-$label-$run_token-z"
  for key in "$contact_id" "$other_contact_id"; do
    submit_contact "$key"
    run_psql --quiet --command="$(stage_contact "$key" 1 2)" >/dev/null
    assert_true revise "SELECT result_code='accepted' FROM ($(ordinary_revision "$key" 1 "$key-revise-1")) result;"
    run_psql --quiet --command="$(stage_contact "$key" 2 4)" >/dev/null
    assert_true revise "SELECT result_code='accepted' FROM ($(ordinary_revision "$key" 2 "$key-revise-2")) result;"
  done
  fingerprints="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT
    plan->'known_source_plan'->>'fact_fingerprint',plan->>'pending_fingerprint' FROM
    (SELECT app_private.read_personal_merge_unassigned_contact_plan_v1('$app_user_id','$workspace_id','$project_id','$generation_id') plan) read_plan;")"
  IFS='|' read -r known_fingerprint pending_fingerprint <<<"$fingerprints"
  assignments="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'pending_fact_id',pending_fact_id,'source_target_id','$second_target') ORDER BY pending_fact_id)
    FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE generation_id='$generation_id';")"
  plan_sql="SELECT app_private.plan_unassigned_personal_merge_contact_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id','$known_fingerprint','$pending_fingerprint','$assignments'::jsonb)"
  resolution_plan="$(run_psql --tuples-only --no-align --command="$plan_sql;")"
  resolution_fingerprint="$(run_psql --tuples-only --no-align --command="SELECT '$resolution_plan'::jsonb->>'resolution_fingerprint';")"
  current_choices="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'contact_id',slot->>'contact_id','source_target_id',slot->>'source_target_id',
    'candidate_kind','pending','pending_fact_id',slot->'pending_fact_ids'->0)
    ORDER BY slot->>'contact_id' COLLATE \"C\",slot->>'source_target_id')
    FROM jsonb_array_elements('$resolution_plan'::jsonb->'source_slots') slot;")"
  for fingerprint in "$known_fingerprint" "$pending_fingerprint" "$resolution_fingerprint"; do
    [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || { echo '0130 missing fingerprint。' >&2; exit 1; }
  done
  confirm_sql="SELECT app_private.confirm_personal_merge_contact_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$request_id','$generation_id',
    '$known_fingerprint','$pending_fingerprint','$resolution_fingerprint','$assignments'::jsonb,'$current_choices'::jsonb);"
  revise_query="$(ordinary_revision "$contact_id" 3 "$contact_id-overlap" 4)"
  expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id');"
  due_sql="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years'
    WHERE promotion_target_id IN ('$first_target','$second_target');"
  child_keys_query="SELECT 'personal-merge-contact-resolve-v1:$request_id:pending:'||pending_fact_id AS key
    FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE generation_id='$generation_id'
    UNION ALL SELECT 'personal-merge-contact-resolve-v1:$request_id:current:'||octet_length(contact_id)||':'||contact_id
    FROM (SELECT DISTINCT contact_id FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE generation_id='$generation_id') contacts"
}
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('$1',0))
      THEN NOT pg_advisory_unlock(hashtextextended('$1',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    sleep 0.05
  done
  echo '0130 holder not ready。' >&2
  sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local waiter_app="$1" holder_app="$2" key="$3" pair lock_predicate
  lock_predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid"
  if [[ -n "$key" ]]; then
    lock_predicate="locks.locktype='advisory' AND locks.objsubid=1
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
    [[ "$pair" == *'|'* ]] && { echo "0130 $waiter_app exact waiter/holder PID and lock: $pair"; return; }
    sleep 0.05
  done
  echo '0130 exact blocker or requested lock missing。' >&2
  sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
  exit 1
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_sqlstate="$4" key="${5:-}" after_wait_sql="${6:-}" prelock_check="${7:-false}"
  local holder_app="7es-holder-$label-$run_token" waiter_app="7es-waiter-$label-$run_token"
  local ready_key="7es-ready-$label-$run_token" status=0 expected_state
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
  if [[ "$prelock_check" == true ]]; then
    assert_true all-child-and-contact-prelocks "SELECT count(*)=8 AND bool_and(EXISTS(
      SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
      WHERE activity.application_name='$waiter_app' AND locks.granted AND locks.locktype='advisory' AND locks.objsubid=1
        AND locks.classid=((hashtextextended(expected.key,0)>>32)&4294967295)::oid
        AND locks.objid=(hashtextextended(expected.key,0)&4294967295)::oid))
      FROM (SELECT '$app_user_id:'||key AS key FROM ($child_keys_query) children
        UNION ALL SELECT 'contact:$contact_id' UNION ALL SELECT 'contact:$other_contact_id') expected;"
  fi
  printf '%s %s COMMIT;\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_state="$(sed -n '/^{/p' "$temporary_directory/holder.out")"
  [[ -n "$expected_state" ]] || { echo '0130 missing holder snapshot。' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_sqlstate" == unchanged ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2; exit 1; }
  elif [[ "$status" -eq 0 ]] || ! grep -q "ERROR:  $expected_sqlstate:" "$temporary_directory/waiter.out"; then
    echo "0130 $label expected $expected_sqlstate, status $status。" >&2
    sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
    exit 1
  fi
  [[ "$expected_state" == "$(business_state)" ]] || { echo "0130 $label waiter changed persistent state。" >&2; exit 1; }
}

new_generation ordinary-first
run_race ordinary-first "$revise_query;" "$confirm_sql" 23505 "contact:$contact_id"
assert_true resolution-only-drift "SELECT newer->>'resolution_fingerprint'<>older->>'resolution_fingerprint'
  AND newer->>'pending_fingerprint'=older->>'pending_fingerprint' AND newer->'known_source_plan'=older->'known_source_plan'
  FROM ($plan_sql) newer_plan(newer) CROSS JOIN (SELECT '$resolution_plan'::jsonb older) old_plan;"

new_generation confirm-first
ordinary_merge="BEGIN; DO \$test\$ DECLARE result_value text; BEGIN
  SELECT result_code INTO result_value FROM ($revise_query) result;
  IF result_value IS DISTINCT FROM 'accepted'
    OR NOT EXISTS (SELECT 1 FROM app_data.contacts WHERE contact_id='$contact_id' AND current_revision=7 AND interest_level=4)
    OR (SELECT count(*) FROM app_data.contact_target_links WHERE contact_id='$contact_id'
      AND revision_number=7 AND promotion_target_id='$second_target')<>1
    THEN RAISE EXCEPTION 'ordinary revision must retain confirmed source'; END IF;
  END \$test\$; ROLLBACK;"
run_race confirm-first "$confirm_sql" "$ordinary_merge" unchanged "contact:$contact_id"
assert_true all-six-children "SELECT count(*)=6 AND bool_and(result_code='accepted') FROM app_data.processed_commands
  WHERE app_user_id='$app_user_id' AND command_id IN (SELECT key FROM ($child_keys_query) children);"
assert_true both-current-heads "SELECT count(*)=2 AND bool_and(current_revision=6) FROM app_data.contacts
  WHERE contact_id IN ('$contact_id','$other_contact_id');"

new_generation added-same-contact-pending
run_race added-same-contact-pending 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$confirm_sql" 23505 '' "$(stage_contact "$contact_id" 3 1)" true
assert_true same-contact-new-child "SELECT count(*)=5 FROM app_private.personal_merge_unassigned_contact_requests_v1
  WHERE generation_id='$generation_id';"

new_generation added-contact
late_contact="$contact_id-late"
submit_contact "$late_contact"
run_race added-contact 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$confirm_sql" 23505 '' "$(stage_contact "$late_contact" 1 1)" true

new_generation late-stage
late_contact="$contact_id-late"
submit_contact "$late_contact"
run_race late-stage "$confirm_sql" "$(stage_contact "$late_contact" 1 1)" 42501

new_generation expiry-first
run_race expiry-first "$due_sql $expiry_sql" "$confirm_sql" 42501
assert_true expiry-no-confirmation "SELECT NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1
  WHERE generation_id='$generation_id' AND request_id='$request_id');"

new_generation confirm-before-expiry
run_race confirm-before-expiry "$confirm_sql" "$expiry_sql" 23505

new_generation exact-replay
run_race exact-replay "$confirm_sql" "$confirm_sql" unchanged "$app_user_id:$request_id"
assert_true one-end "SELECT count(*)=1 FROM app_private.personal_target_merge_end_events_v1
  WHERE generation_id='$generation_id' AND request_id='$request_id';"

new_generation request-drift
drift_sql="${confirm_sql//$second_target/$first_target}"
[[ "$drift_sql" != "$confirm_sql" ]]
run_race request-drift "$confirm_sql" "$drift_sql" 23505 "$app_user_id:$request_id"

new_generation choice-drift
drift_choices="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(choice || jsonb_build_object(
  'pending_fact_id',slot->'pending_fact_ids'->1) ORDER BY choice->>'contact_id' COLLATE \"C\")
  FROM jsonb_array_elements('$current_choices'::jsonb) choice JOIN jsonb_array_elements('$resolution_plan'::jsonb->'source_slots') slot
    ON choice->>'contact_id'=slot->>'contact_id' AND choice->>'source_target_id'=slot->>'source_target_id';")"
drift_sql="${confirm_sql/"$current_choices"/"$drift_choices"}"
[[ "$drift_sql" != "$confirm_sql" ]]
run_race choice-drift "$confirm_sql" "$drift_sql" 23505 "$app_user_id:$request_id"

new_generation assignment-revoked
run_race assignment-revoked "SELECT 1 FROM app_data.promotion_target_assignments
  WHERE promotion_target_id='$first_target' AND app_user_id='$app_user_id' AND ended_at IS NULL FOR UPDATE;" \
  "$confirm_sql" 42501 '' "UPDATE app_data.promotion_target_assignments SET ended_at=clock_timestamp(),end_reason='0130 synthetic revocation'
    WHERE promotion_target_id='$first_target' AND app_user_id='$app_user_id' AND ended_at IS NULL;"

new_generation actor-revoked
run_race actor-revoked "SELECT 1 FROM app_data.promotion_targets WHERE promotion_target_id='$first_target' FOR UPDATE;" "$confirm_sql" 42501 '' \
  "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';" true
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$app_user_id';"

for child_kind in pending current; do
  new_generation "occupied-$child_kind-child"
  occupied_child="$(run_psql --tuples-only --no-align --command="SELECT key FROM ($child_keys_query) children
    WHERE key LIKE '%:$child_kind:%' ORDER BY key COLLATE \"C\" LIMIT 1;")"
  run_race "occupied-$child_kind-child" "SELECT pg_advisory_xact_lock(hashtextextended('$app_user_id:$occupied_child',0));
    INSERT INTO app_data.processed_commands(app_user_id,command_id,protocol_version,command_type,device_id,aggregate_id,result_code,failure_code)
    VALUES('$app_user_id','$occupied_child',1,'contact.revise.v1','7es-device','$contact_id','rejected','synthetic_preoccupied');" \
    "$confirm_sql" 23505 "$app_user_id:$occupied_child"
done

expect_isolation_rejection() {
  local label="$1" isolation="$2" before_state status=0 error_line
  before_state="$(business_state)"
  set +e
  run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $confirm_sql COMMIT;" >"$temporary_directory/isolation.out" 2>&1
  status=$?
  set -e
  error_line="$(sed -n '/^ERROR:/p' "$temporary_directory/isolation.out" | head -n 1)"
  [[ "$status" -ne 0 && "$error_line" == 'ERROR:  0A000: pending contact resolution confirmation requires read committed' ]] || {
    echo "0132 $label expected exact 0A000 isolation error; status $status: $error_line" >&2
    sed -n '/^ERROR:/p' "$temporary_directory/isolation.out" >&2
    exit 1
  }
  [[ "$(business_state)" == "$before_state" ]] || { echo "0132 $label changed app_data/app_private state." >&2; exit 1; }
}

for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  label="first-${isolation// /-}"
  new_generation "$label"
  expect_isolation_rejection "$label" "$isolation"
done

new_generation isolation-rc-history
rc_confirmed_at="$(run_psql --tuples-only --no-align --command="SELECT extract(epoch FROM (${confirm_sql%;}));" | tr -d '[:space:]')"
[[ -n "$rc_confirmed_at" ]] || { echo '0132 read committed history confirmation returned no receipt.' >&2; exit 1; }
rc_state="$(business_state)"
assert_true read-committed-exact-replay "SELECT extract(epoch FROM app_private.confirm_personal_merge_contact_resolutions_v1(
  '$app_user_id','$workspace_id','$project_id','$request_id','$generation_id',
  '$known_fingerprint','$pending_fingerprint','$resolution_fingerprint','$assignments'::jsonb,'$current_choices'::jsonb))=$rc_confirmed_at;"
[[ "$(business_state)" == "$rc_state" ]] || { echo '0132 read committed exact replay changed app_data/app_private state.' >&2; exit 1; }

for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  expect_isolation_rejection "terminal-replay-${isolation// /-}" "$isolation"
done

echo '0130 concurrency passed; 0132 non-RC first calls and terminal replays reject exactly with 0A000 and no app_data/app_private changes; RC confirmation/replay passed.'
