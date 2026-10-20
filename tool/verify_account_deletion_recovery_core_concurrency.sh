#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("$psql_command" "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
holder_pid=''
waiter_pid=''
holder_app=''
waiter_app=''
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
      WHERE application_name IN ('$holder_app','$waiter_app') AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
  fi
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" \
    "$temporary_directory/waiter.out" "$temporary_directory/isolation.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0133 $1 invariant failed: $result" >&2; exit 1; }
}
state_query="SELECT jsonb_build_object(
  'users',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY app_user_id),'[]') FROM app_data.app_users t),
  'current',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY app_user_id),'[]') FROM app_private.account_deletion_current t),
  'request',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY request_id),'[]') FROM app_private.account_deletion_request_claims t),
  'restore',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY request_id),'[]') FROM app_private.account_deletion_restore_claims t),
  'audit',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY audit_event_id),'[]') FROM app_private.account_deletion_audit_events t));"
lifecycle_state() { run_psql --tuples-only --no-align --command="$state_query"; }
new_actor() {
  run_psql --quiet --tuples-only --no-align --command="INSERT INTO app_data.app_users(status) VALUES('active') RETURNING app_user_id;"
}
new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();'; }
request_sql() { printf "SELECT * FROM app_private.request_account_deletion_v1('%s','%s');" "$1" "$2"; }
restore_sql() { printf "SELECT * FROM app_private.restore_account_v1('%s','%s','%s');" "$1" "$2" "$3"; }
new_organization() {
  organization_id="$(run_psql --tuples-only --no-align --command="SELECT organization_workspace_id
    FROM app_private.create_organization_v1('$1',gen_random_uuid(),'0133 concurrency $run_token');")"
  [[ "$organization_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0133 missing organization UUID' >&2; exit 1; }
}
add_owner() {
  local member_id
  member_id="$(new_uuid)"
  run_psql --quiet --command="BEGIN;
    INSERT INTO app_data.organization_memberships(organization_membership_id,organization_workspace_id,
      app_user_id,active_from_utc,inactive_from_utc) VALUES('$member_id','$1','$2',transaction_timestamp(),NULL);
    INSERT INTO app_data.organization_owner_assignments(organization_owner_assignment_id,organization_membership_id,
      active_from_utc,inactive_from_utc) VALUES(gen_random_uuid(),'$member_id',transaction_timestamp(),NULL);
    COMMIT;" >/dev/null
  second_membership_id="$member_id"
}
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT EXISTS(
      SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
      WHERE activity.application_name='$holder_app' AND locks.granted AND locks.locktype='advisory'
        AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database()) AND locks.objsubid=1
        AND locks.classid=((hashtextextended('$1',0)>>32)&4294967295)::oid
        AND locks.objid=(hashtextextended('$1',0)&4294967295)::oid);" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    if ! kill -0 "$holder_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo '0133 holder did not acquire its ready lock' >&2
  sed -n '1,120p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local key="$1" pair lock_predicate
  lock_predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid"
  if [[ -n "$key" ]]; then
    lock_predicate="locks.locktype='advisory' AND locks.objsubid=1
      AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
      AND locks.classid=((hashtextextended('$key',0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended('$key',0)&4294967295)::oid"
  fi
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid||'|'||holder.pid||'|'||locks.locktype||'|'||
      coalesce(locks.transactionid::text,locks.classid::text||':'||locks.objid::text)
      FROM pg_stat_activity waiter JOIN LATERAL unnest(pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_stat_activity holder ON holder.pid=blocked.pid
      JOIN pg_locks locks ON locks.pid=waiter.pid AND NOT locks.granted
      WHERE waiter.application_name='$waiter_app' AND holder.application_name='$holder_app'
        AND waiter.datid=(SELECT oid FROM pg_database WHERE datname=current_database())
        AND waiter.wait_event_type='Lock' AND $lock_predicate;" | tr -d '[:space:]')"
    [[ "$pair" == *'|'* ]] && { echo "0133 exact waiter/holder PID and lock: $pair"; return; }
    if ! kill -0 "$waiter_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo '0133 expected blocker PID or lock was not observed' >&2
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
wait_until_due() {
  local due
  for _ in $(seq 1 300); do
    due="$(run_psql --tuples-only --no-align --command="SELECT clock_timestamp()>=purge_after_utc
      FROM app_private.account_deletion_current WHERE app_user_id='$1';" | tr -d '[:space:]')"
    [[ "$due" == t ]] && return
    sleep 0.05
  done
  echo '0133 synthetic deadline did not pass' >&2
  exit 1
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_state="$4" expected_message="$5"
  local wait_key="${6:-}" prelock_key="${7:-}" deadline_actor="${8:-}" after_wait_sql="${9:-}"
  local ready_key="0133-ready-$label-$run_token" status=0 expected_snapshot
  holder_app="0133-holder-$label-$run_token"
  waiter_app="0133-waiter-$label-$run_token"
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
  wait_for_exact_blocker "$wait_key"
  [[ -z "$prelock_key" ]] || assert_waiter_lock "$label-prelock" "$prelock_key"
  if [[ -n "$deadline_actor" ]]; then
    assert_true "$label-waited-before-deadline" "SELECT clock_timestamp()<purge_after_utc
      FROM app_private.account_deletion_current WHERE app_user_id='$deadline_actor';"
    wait_until_due "$deadline_actor"
  fi
  printf '%s %s COMMIT;\n\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '1,120p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_snapshot="$(sed -n '/^{/p' "$temporary_directory/holder.out")"
  [[ -n "$expected_snapshot" ]] || { echo '0133 holder snapshot missing' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_state" == success ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '1,120p' "$temporary_directory/waiter.out" >&2; exit 1; }
  else
    if [[ "$status" -eq 0 ]] || ! grep -Fq "ERROR:  $expected_state: $expected_message" "$temporary_directory/waiter.out"; then
      echo "0133 $label expected $expected_state / $expected_message, status $status" >&2
      sed -n '1,120p' "$temporary_directory/waiter.out" >&2
      exit 1
    fi
    [[ "$expected_snapshot" == "$(lifecycle_state)" ]] || { echo "0133 $label failure changed lifecycle facts" >&2; exit 1; }
  fi
}
assert_equal_receipts() {
  local first second
  first="$(awk -v contract="$1" 'index($0,contract"|")==1 {print;exit}' "$temporary_directory/holder.out")"
  second="$(awk -v contract="$1" 'index($0,contract"|")==1 {print;exit}' "$temporary_directory/waiter.out")"
  [[ -n "$first" && "$first" == "$second" && "$(awk -F'|' '{print NF}' <<<"$first")" -eq "$2" ]] \
    || { echo "0133 $1 exact receipt replay failed" >&2; exit 1; }
}
set_short_deadline() {
  run_psql --quiet --command="BEGIN;
    SET LOCAL session_replication_role=replica;
    UPDATE app_private.account_deletion_current SET effective_at_utc=boundary.at-interval '720 hours',purge_after_utc=boundary.at
      FROM (SELECT clock_timestamp()+interval '4 seconds' AS at) boundary WHERE app_user_id='$1';
    UPDATE app_private.account_deletion_request_claims claim SET effective_at_utc=attempt.effective_at_utc,purge_after_utc=attempt.purge_after_utc
      FROM app_private.account_deletion_current attempt WHERE claim.request_id=attempt.deletion_request_id AND attempt.app_user_id='$1';
    COMMIT;" >/dev/null
}

echo '0133 same request and same user serialize before writing'
actor="$(new_actor)"; cycle="$(new_uuid)"; other_request="$(new_uuid)"; restoration="$(new_uuid)"
run_race same-request "$(request_sql "$actor" "$cycle")" "$(request_sql "$actor" "$cycle")" success '' "account-deletion-request:$cycle"
assert_equal_receipts account-deletion-request:v1 4
assert_true same-request-single-facts "SELECT (SELECT count(*) FROM app_private.account_deletion_request_claims WHERE request_id='$cycle')=1
  AND (SELECT count(*) FROM app_private.account_deletion_audit_events WHERE request_id='$cycle')=1;"
run_race same-user "SELECT app_user_id FROM app_data.app_users WHERE app_user_id='$actor' FOR UPDATE;" \
  "$(request_sql "$actor" "$other_request")" 22023 'account deletion idempotency conflict' '' "account-deletion-request:$other_request"
run_race same-restore "$(restore_sql "$actor" "$restoration" "$cycle")" "$(restore_sql "$actor" "$restoration" "$cycle")" \
  success '' "account-deletion-restore-request:$restoration"
assert_equal_receipts account-deletion-restore:v1 3
assert_true same-restore-single-facts "SELECT (SELECT count(*) FROM app_private.account_deletion_restore_claims WHERE request_id='$restoration')=1
  AND (SELECT count(*) FROM app_private.account_deletion_audit_events WHERE request_id='$restoration')=1;"

echo '0133 two active owners cannot both enter recovery'
owner_one="$(new_actor)"; owner_two="$(new_actor)"
new_organization "$owner_one"; shared_org="$organization_id"; add_owner "$shared_org" "$owner_two"
cycle_one="$(new_uuid)"; cycle_two="$(new_uuid)"
run_race two-owners "$(request_sql "$owner_one" "$cycle_one")" "$(request_sql "$owner_two" "$cycle_two")" \
  42501 'account deletion forbidden' "organization-governance:$shared_org" "account-deletion-request:$cycle_two"
assert_true one-active-owner "SELECT count(*)=2 AND count(*) FILTER(WHERE status='active')=1
  AND count(*) FILTER(WHERE status='deletion_pending')=1 FROM app_data.app_users WHERE app_user_id IN('$owner_one','$owner_two');"
assert_true rejected-owner-no-claim "SELECT NOT EXISTS(SELECT 1 FROM app_private.account_deletion_request_claims WHERE request_id='$cycle_two');"

echo '0133 owner handoff, membership close, and owner status are checked after waiting'
previous_owner="$(new_actor)"; next_owner="$(new_actor)"
new_organization "$previous_owner"; transfer_org="$organization_id"; recipient_membership="$(new_uuid)"
run_psql --quiet --command="INSERT INTO app_data.organization_memberships(organization_membership_id,organization_workspace_id,
  app_user_id,active_from_utc,inactive_from_utc) VALUES('$recipient_membership','$transfer_org','$next_owner',clock_timestamp(),NULL);" >/dev/null
transfer_request="$(new_uuid)"; next_owner_request="$(new_uuid)"
run_race owner-handoff "SELECT * FROM app_private.transfer_organization_owner_v1('$previous_owner','$transfer_request','$transfer_org','$recipient_membership');" \
  "$(request_sql "$next_owner" "$next_owner_request")" 42501 'account deletion forbidden' '' "account-deletion-request:$next_owner_request"

member_owner="$(new_actor)"; closing_owner="$(new_actor)"
new_organization "$member_owner"; membership_org="$organization_id"; add_owner "$membership_org" "$closing_owner"
member_request="$(new_uuid)"
run_race membership-close "UPDATE app_data.organization_owner_assignments SET inactive_from_utc=transaction_timestamp()
    WHERE organization_membership_id='$second_membership_id' AND inactive_from_utc IS NULL;
  UPDATE app_data.organization_memberships SET inactive_from_utc=transaction_timestamp() WHERE organization_membership_id='$second_membership_id';" \
  "$(request_sql "$member_owner" "$member_request")" 42501 'account deletion forbidden' "organization-governance:$membership_org"

status_owner="$(new_actor)"; other_owner="$(new_actor)"
new_organization "$status_owner"; status_org="$organization_id"; add_owner "$status_org" "$other_owner"
status_request="$(new_uuid)"
run_race owner-status "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$other_owner';" \
  "$(request_sql "$status_owner" "$status_request")" 42501 'account deletion forbidden' "organization-governance:$status_org"
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$other_owner';" >/dev/null
own_actor="$(new_actor)"; own_request="$(new_uuid)"
run_race own-status "UPDATE app_data.app_users SET status='deleted' WHERE app_user_id='$own_actor';" \
  "$(request_sql "$own_actor" "$own_request")" 42501 'account deletion forbidden' '' "account-deletion-request:$own_request"

echo '0133 historical organizations use governance UUID order'
history_actor="$(new_actor)"; history_owner="$(new_actor)"
new_organization "$history_owner"; history_org_one="$organization_id"
new_organization "$history_owner"; history_org_two="$organization_id"
history_sorted="$(printf '%s\n%s\n' "$history_org_one" "$history_org_two" | LC_ALL=C sort)"
small_org="$(sed -n '1p' <<<"$history_sorted")"; large_org="$(sed -n '2p' <<<"$history_sorted")"
run_psql --quiet --command="INSERT INTO app_data.organization_memberships(organization_membership_id,organization_workspace_id,
  app_user_id,active_from_utc,inactive_from_utc) SELECT gen_random_uuid(),workspace_id,'$history_actor',
  clock_timestamp()-interval '2 hours',clock_timestamp()-interval '1 hour'
  FROM app_data.workspaces WHERE workspace_id IN('$small_org','$large_org');" >/dev/null
history_request="$(new_uuid)"
run_race history-order "SELECT app_private.lock_organization_governance_v1('$large_org');" \
  "$(request_sql "$history_actor" "$history_request")" success '' "organization-governance:$large_org" "organization-governance:$small_org"
assert_true history-request-pending "SELECT status='deletion_pending' FROM app_data.app_users WHERE app_user_id='$history_actor';"

echo '0133 restore and replay use the clock after their last wait'
deadline_actor="$(new_actor)"; deadline_cycle="$(new_uuid)"; deadline_restore="$(new_uuid)"
run_psql --quiet --command="$(request_sql "$deadline_actor" "$deadline_cycle")" >/dev/null
set_short_deadline "$deadline_actor"
run_race restore-deadline "SELECT app_user_id FROM app_data.app_users WHERE app_user_id='$deadline_actor' FOR UPDATE;" \
  "$(restore_sql "$deadline_actor" "$deadline_restore" "$deadline_cycle")" 22023 'account restoration idempotency conflict' \
  '' "account-deletion-restore-request:$deadline_restore" "$deadline_actor"
replay_actor="$(new_actor)"; replay_cycle="$(new_uuid)"
run_psql --quiet --command="$(request_sql "$replay_actor" "$replay_cycle")" >/dev/null
set_short_deadline "$replay_actor"
run_race replay-deadline "SELECT pg_advisory_xact_lock(hashtextextended('account-deletion-request:$replay_cycle',0));" \
  "$(request_sql "$replay_actor" "$replay_cycle")" 22023 'account deletion idempotency conflict' \
  "account-deletion-request:$replay_cycle" '' "$replay_actor"

echo '0133 first calls and exact replay reject every other isolation mode'
isolation_actor="$(new_actor)"; pending_actor="$(new_actor)"; restored_actor="$(new_actor)"
pending_cycle="$(new_uuid)"; restored_cycle="$(new_uuid)"; restored_request="$(new_uuid)"
run_psql --quiet --command="$(request_sql "$pending_actor" "$pending_cycle")
  $(request_sql "$restored_actor" "$restored_cycle") $(restore_sql "$restored_actor" "$restored_request" "$restored_cycle")" >/dev/null
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  for operation in request-first request-replay restore-first restore-replay; do
    case "$operation" in
      request-first) statement="$(request_sql "$isolation_actor" "$(new_uuid)")"; message='account deletion requires read committed' ;;
      request-replay) statement="$(request_sql "$pending_actor" "$pending_cycle")"; message='account deletion requires read committed' ;;
      restore-first) statement="$(restore_sql "$pending_actor" "$(new_uuid)" "$pending_cycle")"; message='account restoration requires read committed' ;;
      restore-replay) statement="$(restore_sql "$restored_actor" "$restored_request" "$restored_cycle")"; message='account restoration requires read committed' ;;
    esac
    before_state="$(lifecycle_state)"
    if run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $statement COMMIT;" >"$temporary_directory/isolation.out" 2>&1; then
      echo "0133 $isolation $operation unexpectedly succeeded" >&2; exit 1
    fi
    grep -Fq "ERROR:  0A000: $message" "$temporary_directory/isolation.out" \
      || { sed -n '1,120p' "$temporary_directory/isolation.out" >&2; exit 1; }
    [[ "$before_state" == "$(lifecycle_state)" ]] || { echo "0133 $isolation $operation changed lifecycle facts" >&2; exit 1; }
  done
done

echo '0133 account deletion/recovery concurrency passed.'
