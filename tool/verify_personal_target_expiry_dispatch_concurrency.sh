#!/usr/bin/env bash

set -euo pipefail
: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("$psql_command" "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
holder_pid='' waiter_pid='' auxiliary_pid=''
cleanup() {
  local pid
  exec 3>&- 4>&- 2>/dev/null || true
  for pid in "$holder_pid" "$waiter_pid" "$auxiliary_pid"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then kill "$pid" >/dev/null 2>&1 || true; fi
    wait "$pid" >/dev/null 2>&1 || true
  done
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" \
    "$temporary_directory/waiter.out" "$temporary_directory/auxiliary.fifo" "$temporary_directory/auxiliary.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0131 $1 invariant failed: $result" >&2; exit 1; }
}
new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();'; }
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7et-expiry-dispatch.example.test/auth/v1'
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM ('||string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
business_state() { run_psql --tuples-only --no-align --command="$state_query"; }
create_target() {
  run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0131 $1 $run_token','+1 312 555 0131',NULL,'7et-$1-$run_token');"
}
build_request() {
  dispatch_sql="SELECT * FROM app_private.dispatch_assigned_personal_target_expiry_v1(
    '$app_user_id','$workspace_id','$project_id','$request_id');"
  child_ids_query="SELECT unit_kind,unit_id,md5('personal-target-expiry-v1:'||'$app_user_id'||':'||'$request_id'||':'||unit_kind||':'||unit_id::text)::uuid child_id
    FROM ($units_query) units"
  child_keys_query="SELECT '$app_user_id:'||CASE unit_kind WHEN 'target' THEN 'owner-expiry-v1:'||child_id::text ELSE child_id::text END key
    FROM ($child_ids_query) children"
}
build_confirmation() {
  local fingerprints
  fingerprints="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT
    plan->'known_source_plan'->>'fact_fingerprint',plan->>'pending_fingerprint' FROM
    (SELECT app_private.read_personal_merge_unassigned_contact_plan_v1('$app_user_id','$workspace_id','$project_id','$generation_id') plan) p;")"
  IFS='|' read -r known_fingerprint pending_fingerprint <<<"$fingerprints"
  assignments="[{\"pending_fact_id\":\"$pending_id\",\"source_target_id\":\"$pair_second\"}]"
  resolution_fingerprint="$(run_psql --tuples-only --no-align --command="SELECT app_private.plan_unassigned_personal_merge_contact_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id','$known_fingerprint','$pending_fingerprint','$assignments'::jsonb)->>'resolution_fingerprint';")"
  confirm_sql="SELECT app_private.confirm_personal_merge_contact_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$confirmation_request','$generation_id','$known_fingerprint','$pending_fingerprint','$resolution_fingerprint',
    '$assignments'::jsonb,'[{\"contact_id\":\"$contact_id\",\"source_target_id\":\"$pair_second\",\"candidate_kind\":\"pending\",\"pending_fact_id\":\"$pending_id\"}]'::jsonb);"
}
new_case() {
  local label="$1" mode="${2:-targets}" context preview_id
  subject="7et-$label-$run_token"
  run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
  context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
    FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
  IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$context"
  for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
    [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0131 missing personal context。' >&2; exit 1; }
  done
  first_target="$(create_target "$label-first")"
  second_target="$(create_target "$label-second")"
  request_id="$(new_uuid)"
  units_query="SELECT 'target'::text unit_kind,'$first_target'::uuid unit_id UNION ALL SELECT 'target','$second_target'::uuid"
  target_units_query="SELECT '$first_target'::uuid target_id,'target'::text unit_kind,'$first_target'::uuid unit_id
    UNION ALL SELECT '$second_target'::uuid,'target','$second_target'::uuid"
  if [[ "$mode" == pair ]]; then
    pair_first="$(create_target "$label-pair-first")"
    pair_second="$(create_target "$label-pair-second")"
    preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
      '$issuer','$subject','$project_id','$pair_first','$pair_second');")"
    generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
      '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$pair_first','$pair_first','$pair_first','$pair_second');")"
    contact_id="7et-$label-$run_token-contact"
    assert_true submit "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
      '$app_user_id','$contact_id-submit',1,'contact.submit.v1','7et-device','$contact_id',0,
      jsonb_build_object('contactId','$contact_id','workspaceId','$workspace_id','projectId','$project_id',
        'questionnaireVersionId','$questionnaire_version_id','reason','0131 pending contact','occurredAtUtc',clock_timestamp(),
        'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
        'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
    pending_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
      '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$contact_id',1,2,'unknown',false,true);")"
    confirmation_request="$(new_uuid)"
    build_confirmation
    units_query="$units_query UNION ALL SELECT 'generation','$generation_id'::uuid"
    target_units_query="$target_units_query UNION ALL SELECT '$pair_first'::uuid,'generation','$generation_id'::uuid
      UNION ALL SELECT '$pair_second'::uuid,'generation','$generation_id'::uuid"
    expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
      '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id');"
  fi
  run_psql --quiet --command="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '13 months'
    WHERE promotion_target_id IN (SELECT target_id FROM ($target_units_query) targets);" >/dev/null
  assignment_id="$(run_psql --tuples-only --no-align --command="SELECT assignment_id FROM app_data.promotion_target_assignments
    WHERE promotion_target_id='$first_target' AND app_user_id='$app_user_id' AND ended_at IS NULL;")"
  assignment_sql="SELECT app_data.end_personal_target_assignment_v1('$app_user_id','$workspace_id','$project_id','$assignment_id');"
  build_request
  race_assertion='none'
  wait_deadline=''
}
checked_dispatch() {
  local expectation="$1"
  printf '%s' "BEGIN; DO \$test\$ DECLARE observed jsonb; expected jsonb; BEGIN
    SELECT coalesce(jsonb_agg(to_jsonb(result)),'[]'::jsonb) INTO observed FROM
      app_private.dispatch_assigned_personal_target_expiry_v1('$app_user_id','$workspace_id','$project_id','$request_id') result;
    SELECT jsonb_agg(jsonb_build_object('unit_kind',unit_kind,'unit_id',unit_id,'outcome',outcome) ORDER BY unit_kind COLLATE \"C\",unit_id)
      INTO expected FROM ($expectation) units;
    IF (SELECT jsonb_agg(jsonb_build_object('unit_kind',unit->>'unit_kind','unit_id',unit->>'unit_id','outcome',unit->>'outcome')
      ORDER BY unit->>'unit_kind' COLLATE \"C\",(unit->>'unit_id')::uuid) FROM jsonb_array_elements(observed) unit) IS DISTINCT FROM expected
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(observed) unit WHERE (unit->>'outcome'='expired')<>(unit->>'processed_at_utc' IS NOT NULL))
      THEN RAISE EXCEPTION 'dispatch outcomes or timestamps changed: %',observed; END IF;
    IF EXISTS (SELECT 1 FROM ($expectation) expected JOIN ($target_units_query) targets USING(unit_kind,unit_id)
      JOIN app_data.promotion_targets target ON target.promotion_target_id=targets.target_id
      WHERE expected.outcome='expired' AND (target.status<>'anonymized' OR target.phone IS NOT NULL OR target.email IS NOT NULL
        OR EXISTS (SELECT 1 FROM app_data.promotion_target_assignments assigned
          WHERE assigned.promotion_target_id=targets.target_id AND assigned.ended_at IS NULL)))
      THEN RAISE EXCEPTION 'expired unit retained target data or an active assignment'; END IF;
  END \$test\$; ROLLBACK;"
}
all_outcomes() { printf '%s' "SELECT unit_kind,unit_id,'$1'::text outcome FROM ($units_query) units"; }
mixed_outcomes() { printf '%s' "SELECT unit_kind,unit_id,CASE WHEN unit_id='$1'::uuid THEN '$2' ELSE '$3' END outcome FROM ($units_query) units"; }
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('$1',0))
      THEN NOT pg_advisory_unlock(hashtextextended('$1',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    sleep 0.05
  done
  echo '0131 holder not ready。' >&2
  sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local waiter_app="$1" holder_app="$2" key="$3" pair predicate
  predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid"
  if [[ -n "$key" ]]; then
    predicate="locks.locktype='advisory' AND locks.objsubid=1
      AND locks.classid=((hashtextextended('$key',0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended('$key',0)&4294967295)::oid"
  fi
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid||'|'||holder.pid||'|'||locks.locktype||'|'||
      coalesce(locks.transactionid::text,locks.classid::text||':'||locks.objid::text)
      FROM pg_stat_activity waiter JOIN LATERAL unnest(pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_stat_activity holder ON holder.pid=blocked.pid JOIN pg_locks locks ON locks.pid=waiter.pid AND NOT locks.granted
      WHERE waiter.application_name='$waiter_app' AND holder.application_name='$holder_app' AND waiter.wait_event_type='Lock' AND $predicate;" | tr -d '[:space:]')"
    [[ "$pair" == *'|'* ]] && { echo "0131 $waiter_app exact waiter/holder PID and lock: $pair"; return; }
    sleep 0.05
  done
  echo '0131 exact blocker or requested lock missing。' >&2
  sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
  exit 1
}
assert_child_locks() {
  local app="$1" missing="$2"
  assert_true child-prelocks "SELECT count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM pg_locks locks
    JOIN pg_stat_activity activity ON activity.pid=locks.pid WHERE activity.application_name='$app'
      AND locks.granted AND locks.locktype='advisory' AND locks.objsubid=1
      AND locks.classid=((hashtextextended(expected.key,0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended(expected.key,0)&4294967295)::oid))=$missing FROM ($child_keys_query) expected;"
}
start_holder() {
  local sql="$1"
  holder_app="7et-h-$case_label-$run_token"
  ready_key="7et-ready-$case_label-$run_token"
  mkfifo "$temporary_directory/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"$temporary_directory/holder.fifo" >"$temporary_directory/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"$temporary_directory/holder.fifo"
  printf "BEGIN; %s SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$sql" "$ready_key" >&3
}
start_waiter() {
  waiter_app="7et-w-$case_label-$run_token"
  PGAPPNAME="$waiter_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="$1" >"$temporary_directory/waiter.out" 2>&1 &
  waiter_pid=$!
}
release_holder() {
  printf '%s %s COMMIT;\\q\n' "${1:-}" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_state="$(sed -n '/^{/p' "$temporary_directory/holder.out" | tail -n 1)"
  [[ -n "$expected_state" ]] || { echo '0131 missing holder snapshot。' >&2; exit 1; }
}
collect_waiter() {
  local expected="$1" status="${2:-}"
  if [[ -z "$status" ]]; then status=0; wait "$waiter_pid" || status=$?; fi
  waiter_pid=''
  if [[ "$expected" == unchanged ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2; exit 1; }
  elif [[ "$status" -eq 0 ]] || ! grep -q "ERROR:  $expected:" "$temporary_directory/waiter.out"; then
    echo "0131 $case_label expected $expected, status $status。" >&2
    sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
    exit 1
  fi
  [[ "$expected_state" == "$(business_state)" ]] || { echo "0131 $case_label waiter changed persistent state。" >&2; exit 1; }
}
run_race() {
  case_label="$1"
  local holder_sql="$2" waiter_sql="$3" expected="$4" key="${5:-}" after_wait="${6:-}" timeout_waiter="${7:-false}" status=0 due
  start_holder "$holder_sql"
  wait_for_holder "$ready_key"
  if [[ -n "$wait_deadline" ]]; then
    for _ in $(seq 1 300); do
      due="$(run_psql --tuples-only --no-align --command="SELECT clock_timestamp()>='$wait_deadline'::timestamptz;" | tr -d '[:space:]')"
      [[ "$due" == t ]] && break
      sleep 0.05
    done
    [[ "$due" == t ]] || { echo '0131 original deadline not reached。' >&2; exit 1; }
  fi
  start_waiter "$waiter_sql"
  wait_for_exact_blocker "$waiter_app" "$holder_app" "$key"
  if [[ "$race_assertion" == all-children ]]; then assert_child_locks "$waiter_app" 0; fi
  if [[ "$race_assertion" == before-fence ]]; then
    assert_child_locks "$waiter_app" 1
    assert_true child-before-fence "SELECT NOT EXISTS (SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
      WHERE activity.application_name='$waiter_app' AND locks.granted
        AND locks.relation='app_private.personal_target_merge_generation_fence_v1'::regclass AND locks.mode<>'AccessShareLock');"
  fi
  if [[ "$timeout_waiter" == true ]]; then wait "$waiter_pid" || status=$?; fi
  release_holder "$after_wait"
  if [[ "$timeout_waiter" == true ]]; then collect_waiter "$expected" "$status"; else collect_waiter "$expected"; fi
}

new_case child-before-fence pair
last_child_key="$(run_psql --tuples-only --no-align --command="SELECT key FROM ($child_keys_query) children ORDER BY key COLLATE \"C\" DESC LIMIT 1;")"
race_assertion=before-fence
run_race child-before-fence "SELECT pg_advisory_xact_lock(hashtextextended('$last_child_key',0));" \
  "$(checked_dispatch "$(all_outcomes expired)")" unchanged "$last_child_key"

new_case all-children pair
race_assertion=all-children
run_race all-children 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$(checked_dispatch "$(all_outcomes expired)")" unchanged

new_case overlapping-batches pair
first_dispatch="$dispatch_sql"
request_id="$(new_uuid)"
build_request
race_assertion=all-children
run_race overlapping-batches "$first_dispatch" "$(checked_dispatch "$(all_outcomes skipped)")" unchanged

new_case same-request pair
run_race same-request "$dispatch_sql" "$(checked_dispatch "$(all_outcomes expired)")" unchanged "$app_user_id:$request_id"

new_case child-single-first
ordinary_child="$(run_psql --tuples-only --no-align --command="SELECT child_id FROM ($child_ids_query) children WHERE unit_id='$first_target';")"
single_sql="SELECT result FROM app_data.apply_promotion_target_retention_action('$app_user_id','$workspace_id','$project_id',
  '$first_target','anonymize','retention_expired','owner-expiry-v1:$ordinary_child');"
run_race child-single-first "$single_sql" "$(checked_dispatch "$(mixed_outcomes "$first_target" skipped expired)")" unchanged "$app_user_id:owner-expiry-v1:$ordinary_child"

new_case dispatch-single-first
ordinary_child="$(run_psql --tuples-only --no-align --command="SELECT child_id FROM ($child_ids_query) children WHERE unit_id='$first_target';")"
single_sql="BEGIN; DO \$test\$ DECLARE duplicate_value boolean; BEGIN
  SELECT (result->>'duplicate')::boolean INTO duplicate_value FROM app_data.apply_promotion_target_retention_action(
    '$app_user_id','$workspace_id','$project_id','$first_target','anonymize','retention_expired','owner-expiry-v1:$ordinary_child');
  IF duplicate_value IS DISTINCT FROM true THEN RAISE EXCEPTION 'single child must replay'; END IF;
  END \$test\$; ROLLBACK;"
run_race dispatch-single-first "$dispatch_sql" "$single_sql" unchanged "$app_user_id:owner-expiry-v1:$ordinary_child"

new_case pair-child-first pair
pair_child="$(run_psql --tuples-only --no-align --command="SELECT child_id FROM ($child_ids_query) children WHERE unit_kind='generation';")"
single_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1('$app_user_id','$workspace_id','$project_id','$pair_child','$generation_id');"
run_race pair-child-first "$single_sql" "$(checked_dispatch "$(mixed_outcomes "$generation_id" skipped expired)")" unchanged "$app_user_id:$pair_child"

new_case dispatch-pair-first pair
pair_child="$(run_psql --tuples-only --no-align --command="SELECT child_id FROM ($child_ids_query) children WHERE unit_kind='generation';")"
single_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1('$app_user_id','$workspace_id','$project_id','$pair_child','$generation_id');"
run_race dispatch-pair-first "$dispatch_sql" "$single_sql" unchanged "$app_user_id:$pair_child"

new_case legacy-batch
case_label=legacy-batch
old_child_key="$(run_psql --tuples-only --no-align --command="SELECT '$app_user_id:retention-expired:'||promotion_target_id||':'||
  extract(epoch FROM app_data.promotion_target_review_due_at(promotion_target_id))::bigint FROM app_data.promotion_targets
  WHERE promotion_target_id IN ('$first_target','$second_target') ORDER BY promotion_target_id DESC LIMIT 1;")"
auxiliary_app="7et-a-$case_label-$run_token"
auxiliary_ready="7et-aux-ready-$run_token"
mkfifo "$temporary_directory/auxiliary.fifo"
PGAPPNAME="$auxiliary_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
  <"$temporary_directory/auxiliary.fifo" >"$temporary_directory/auxiliary.out" 2>&1 &
auxiliary_pid=$!
exec 4>"$temporary_directory/auxiliary.fifo"
printf "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('%s',0)); SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$old_child_key" "$auxiliary_ready" >&4
wait_for_holder "$auxiliary_ready"
start_holder "SELECT app_data.expire_assigned_promotion_targets('$app_user_id','$workspace_id','$project_id');"
wait_for_exact_blocker "$holder_app" "$auxiliary_app" "$old_child_key"
start_waiter "$(checked_dispatch "$(all_outcomes skipped)")"
wait_for_exact_blocker "$waiter_app" "$holder_app" ''
assert_child_locks "$waiter_app" 0
printf 'COMMIT;\\q\n' >&4
exec 4>&-
wait "$auxiliary_pid"
auxiliary_pid=''
rm -f "$temporary_directory/auxiliary.fifo"
wait_for_holder "$ready_key"
release_holder
collect_waiter unchanged

new_case renewal-first
run_psql --quiet --command="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()+interval '3 seconds'-interval '12 months'
  WHERE promotion_target_id='$first_target';" >/dev/null
wait_deadline="$(run_psql --tuples-only --no-align --command="SELECT app_data.promotion_target_review_due_at('$first_target');")"
renewal_sql="SELECT result FROM app_data.apply_promotion_target_retention_action('$app_user_id','$workspace_id','$project_id',
  '$first_target','renew','purpose_confirmed','7et-renew-$run_token');"
race_assertion=all-children
run_race renewal-first "$renewal_sql" "$(checked_dispatch "$(mixed_outcomes "$first_target" skipped expired)")" unchanged

new_case expiry-before-renewal
renewal_sql="SELECT result FROM app_data.apply_promotion_target_retention_action('$app_user_id','$workspace_id','$project_id',
  '$first_target','renew','purpose_confirmed','7et-renew-after-$run_token');"
run_race expiry-before-renewal "$dispatch_sql" "$renewal_sql" 42501

new_case policy-first
run_psql --quiet --command="SELECT app_data.configure_promotion_target_retention_policy('$app_user_id','$workspace_id','$project_id',1);
  UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 months'
  WHERE promotion_target_id IN ('$first_target','$second_target');" >/dev/null
race_assertion=all-children
run_race policy-first "SELECT app_data.configure_promotion_target_retention_policy('$app_user_id','$workspace_id','$project_id',12);" \
  "$(checked_dispatch "$(all_outcomes skipped)")" unchanged

new_case expiry-before-policy
policy_sql="BEGIN; SELECT app_data.configure_promotion_target_retention_policy('$app_user_id','$workspace_id','$project_id',1); ROLLBACK;"
run_race expiry-before-policy "$dispatch_sql" "$policy_sql" unchanged

new_case assignment-first
race_assertion=all-children
run_race assignment-first "$assignment_sql" "$(checked_dispatch "$(mixed_outcomes "$first_target" skipped expired)")" unchanged

new_case expiry-before-assignment
run_race expiry-before-assignment "$dispatch_sql" "$assignment_sql" 42501

new_case confirmation-first pair
run_psql --quiet --command="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '1 day'
  WHERE promotion_target_id IN ('$pair_first','$pair_second');
  UPDATE app_data.promotion_targets SET created_at=clock_timestamp()+interval '3 seconds'-interval '12 months'
  WHERE promotion_target_id='$pair_first';" >/dev/null
wait_deadline="$(run_psql --tuples-only --no-align --command="SELECT app_data.promotion_target_review_due_at('$pair_first');")"
build_confirmation
race_assertion=all-children
run_race confirmation-first "$confirm_sql" "$(checked_dispatch "$(mixed_outcomes "$generation_id" skipped expired)")" unchanged

new_case expiry-before-confirmation pair
run_race expiry-before-confirmation "$dispatch_sql" "$confirm_sql" 42501

new_case external-expiry-first pair
race_assertion=all-children
run_race external-expiry-first "$expiry_sql" "$(checked_dispatch "$(mixed_outcomes "$generation_id" skipped expired)")" unchanged

new_case dispatch-before-external-expiry pair
run_race dispatch-before-external-expiry "$dispatch_sql" "$expiry_sql" 23505

new_case actor-revoked pair
race_assertion=all-children
run_race actor-revoked "SELECT 1 FROM app_data.promotion_targets WHERE promotion_target_id='$first_target' FOR UPDATE;" \
  "$dispatch_sql" 42501 '' "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';"

new_case infrastructure-lock-timeout
late_target="$(run_psql --tuples-only --no-align --command="SELECT unit_id FROM ($units_query) units ORDER BY unit_id DESC LIMIT 1;")"
run_psql --quiet --command="INSERT INTO app_data.promotion_target_project_relationships(promotion_target_id,project_id,current_stage,established_by_app_user_id)
  VALUES('$late_target','$project_id',0,'$app_user_id');" >/dev/null
race_assertion=all-children
run_race infrastructure-lock-timeout "SELECT 1 FROM app_data.promotion_target_project_relationships
  WHERE promotion_target_id='$late_target' AND project_id='$project_id' FOR UPDATE;" \
  "BEGIN; SET LOCAL lock_timeout='3000ms'; $dispatch_sql COMMIT;" 55P03 '' '' true

echo '0131 concurrency passed: fixed prelocks, overlapping batches, legacy keys, writer ordering, locked revocation and infrastructure rollback.'
