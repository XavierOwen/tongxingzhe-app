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
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" \
    "$temporary_directory/waiter.out" "$temporary_directory/isolation.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0135 $1 invariant failed: $result" >&2; exit 1; }
}
new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();'; }
issuer='https://7ex-unlink-concurrency.example.test'
owner="$(run_psql --tuples-only --no-align --command="SELECT app_user_id
  FROM app_data.bootstrap_personal_context('$issuer','owner-$run_token');")"
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM ('||string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN('app_data','app_private');")"
database_state() { run_psql --tuples-only --no-align --command="$state_query"; }
unlink_sql() { printf "SELECT * FROM app_private.unlink_due_account_history_contributions_v1('%s','%s');" "$actor" "$cycle"; }
confirm_sql() { printf "SELECT * FROM app_private.confirm_personal_history_contribution_v1('%s','%s','%s');" "$actor" "$1" "$2"; }
preview_sql() { printf "SELECT * FROM app_private.preview_personal_history_contribution_v1('%s','%s','%s')" "$actor" "$source_late" "$1"; }
create_target() {
  local invitation membership
  next_org="$(run_psql --tuples-only --no-align --command="SELECT organization_workspace_id
    FROM app_private.create_organization_v1('$owner',gen_random_uuid(),'0135 $case_label $run_token');")"
  next_project="$(new_uuid)"
  run_psql --quiet --command="INSERT INTO app_data.projects(project_id,workspace_id,display_name)
    VALUES('$next_project','$next_org','0135 target');" >/dev/null
  invitation="$(run_psql --tuples-only --no-align --command="SELECT invitation_id FROM
    app_private.create_organization_directed_account_invitation_v1('$owner',gen_random_uuid(),'$next_org','$actor');")"
  membership="$(run_psql --tuples-only --no-align --command="SELECT organization_membership_id FROM
    app_private.accept_organization_directed_account_invitation_v1('$actor','$invitation');")"
  run_psql --quiet --command="SELECT * FROM app_private.assign_organization_project_member_v1(
    '$owner',gen_random_uuid(),'$next_org','$next_project','$membership');" >/dev/null
}
due_sql() {
  printf "SET LOCAL session_replication_role=replica;
    UPDATE app_private.account_deletion_current SET effective_at_utc=boundary.at-interval '720 hours',purge_after_utc=boundary.at
      FROM(SELECT clock_timestamp()+interval '%s seconds' AS at) boundary WHERE app_user_id='%s';
    UPDATE app_private.account_deletion_request_claims claim SET effective_at_utc=attempt.effective_at_utc,purge_after_utc=attempt.purge_after_utc
      FROM app_private.account_deletion_current attempt WHERE claim.request_id=attempt.deletion_request_id AND attempt.app_user_id='%s';
    SET LOCAL session_replication_role=origin;" "${1:--1}" "$actor" "$actor"
}
begin_pending_sql() {
  printf "SELECT * FROM app_private.request_account_deletion_v1('%s','%s'); %s" "$actor" "$cycle" "$(due_sql)"
}
new_case() {
  local context id source defer_cycle="${2:-no}"
  case_label="$1"
  context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
    FROM app_data.bootstrap_personal_context('$issuer','$case_label-$run_token');")"
  IFS='|' read -r actor personal_workspace personal_project questionnaire <<<"$context"
  cycle="$(new_uuid)"; request="$(new_uuid)"; source_main="7ex-$case_label-$run_token"; source_late="$source_main-late"
  create_target; organization="$next_org"; target_project="$next_project"
  for source in "$source_main" "$source_late"; do
    assert_true "$case_label-submit" "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
      '$actor','$source-submit',1,'contact.submit.v1','7ex-device','$source',0,
      jsonb_build_object('contactId','$source','workspaceId','$personal_workspace','projectId','$personal_project',
        'questionnaireVersionId','$questionnaire','reason','0135 retained source','occurredAtUtc','2025-06-07T08:09:10Z',
        'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
        'reachCount',2,'interestLevel',3,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
  done
  preview="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM
    app_private.preview_personal_history_contribution_v1('$actor','$source_main','$target_project');")"
  run_psql --quiet --command="$(confirm_sql "$request" "$preview")" >/dev/null
  if [[ "$defer_cycle" == no ]]; then
    run_psql --quiet --command="BEGIN; $(begin_pending_sql) COMMIT;" >/dev/null
  fi
  for id in "$actor" "$organization" "$target_project" "$preview"; do
    [[ "$id" =~ ^[0-9a-f-]{36}$ ]] || { echo "0135 $case_label missing seed UUID" >&2; exit 1; }
  done
}
prepare_org_purge() {
  organization_cycle="$(new_uuid)"
  run_psql --quiet --command="BEGIN;
    SELECT * FROM app_private.request_organization_deletion_v1('$owner','$organization_cycle','$organization');
    SET LOCAL session_replication_role=replica;
    UPDATE app_private.organization_deletion_current SET effective_at_utc=transaction_timestamp()-interval '721 hours',purge_after_utc=transaction_timestamp()-interval '1 hour'
      WHERE organization_workspace_id='$organization';
    UPDATE app_private.organization_deletion_request_claims claim SET effective_at_utc=attempt.effective_at_utc,purge_after_utc=attempt.purge_after_utc
      FROM app_private.organization_deletion_current attempt WHERE claim.request_id=attempt.deletion_request_id AND attempt.organization_workspace_id='$organization';
    UPDATE app_private.organization_deletion_audit_events audit SET occurred_at_utc=attempt.effective_at_utc
      FROM app_private.organization_deletion_current attempt WHERE audit.request_id=attempt.deletion_request_id AND attempt.organization_workspace_id='$organization';
    UPDATE app_data.workspaces SET deleted_at=(SELECT effective_at_utc FROM app_private.organization_deletion_current WHERE organization_workspace_id='$organization')
      WHERE workspace_id='$organization';
    SET LOCAL session_replication_role=origin; COMMIT;" >/dev/null
  purge_sql="SELECT * FROM app_private.finalize_organization_purge_v1('$organization','$organization_cycle');"
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
  echo '0135 holder did not acquire its ready lock' >&2
  sed -n '1,120p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local key="$1" predicate pair
  predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid"
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
    [[ "$pair" == *'|'* ]] && { echo "0135 exact waiter/holder PID and lock: $pair"; return; }
    if ! kill -0 "$waiter_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo "0135 expected blocker PID or lock was not observed: $key" >&2
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
  local ready_key="7ex-ready-$label-$run_token"
  holder_app="7ex-h-$label-$run_token"; waiter_app="7ex-w-$label-$run_token"
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
    assert_true waited-before-deadline "SELECT clock_timestamp()<purge_after_utc FROM app_private.account_deletion_current WHERE app_user_id='$actor';"
    due=f
    for _ in $(seq 1 300); do
      due="$(run_psql --tuples-only --no-align --command="SELECT clock_timestamp()>=purge_after_utc
        FROM app_private.account_deletion_current WHERE app_user_id='$actor';" | tr -d '[:space:]')"
      [[ "$due" == t ]] && break
      sleep 0.05
    done
    [[ "$due" == t ]] || { echo '0135 synthetic deadline did not pass' >&2; exit 1; }
  fi
  printf '%s %s COMMIT;\n\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '1,120p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_snapshot="$(sed -n '/^{/p' "$temporary_directory/holder.out")"
  [[ -n "$expected_snapshot" ]] || { echo '0135 holder snapshot missing' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_state" == success ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '1,120p' "$temporary_directory/waiter.out" >&2; exit 1; }
  else
    if [[ "$status" -eq 0 ]] || ! grep -Fq "ERROR:  $expected_state: $expected_message" "$temporary_directory/waiter.out"; then
      echo "0135 $label expected $expected_state / $expected_message, status $status" >&2
      sed -n '1,120p' "$temporary_directory/waiter.out" >&2; exit 1
    fi
    [[ "$expected_snapshot" == "$(database_state)" ]] || { echo "0135 $label rejection changed database facts" >&2; exit 1; }
  fi
}

echo '0135 same cycle and confirmation requests serialize in their exact namespaces'
new_case same-cycle
replay_actor="$actor"; replay_cycle="$cycle"
run_race same-cycle "$(unlink_sql)" "$(unlink_sql)" success '' "account-history-contribution-unlink:$cycle"
first="$(awk '/^account-history-contribution-unlink:v1\|/ {print;exit}' "$temporary_directory/holder.out")"
second="$(awk '/^account-history-contribution-unlink:v1\|/ {print;exit}' "$temporary_directory/waiter.out")"
[[ -n "$first" && "$first" == "$second" && "$(awk -F'|' '{print NF}' <<<"$first")" -eq 3 ]] \
  || { echo '0135 exact three-field replay failed' >&2; exit 1; }
new_case unlink-first
run_race unlink-first "$(unlink_sql)" "$(confirm_sql "$request" "$preview")" \
  22023 'personal history contribution idempotency conflict' "personal-history-contribution-confirmation:$request"
new_case confirm-first yes
run_race confirm-first "$(confirm_sql "$request" "$preview")" "$(unlink_sql)" success '' \
  "personal-history-contribution-confirmation:$request" "$(begin_pending_sql)" "account-history-contribution-unlink:$cycle"

echo '0135 user wait rechecks status and wall-clock deadline'
new_case status-first
run_race status-first "UPDATE app_data.app_users SET status='active' WHERE app_user_id='$actor';" \
  "$(unlink_sql)" 55000 'account history contribution unlink unavailable' '' '' "personal-history-contribution-confirmation:$request"
run_psql --quiet --command="UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$actor';" >/dev/null
new_case deadline
run_psql --quiet --command="BEGIN; $(due_sql 8) COMMIT;" >/dev/null
run_race deadline "SELECT app_user_id FROM app_data.app_users WHERE app_user_id='$actor' FOR NO KEY UPDATE;" \
  "$(unlink_sql)" success '' '' '' "personal-history-contribution-confirmation:$request" yes

echo '0135 governance UUID order and both organization purge orders'
new_case governance-order yes
create_target; extra_org="$next_org"; extra_project="$next_project"; extra_request="$(new_uuid)"
extra_preview="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM ($(preview_sql "$extra_project")) receipt;")"
run_psql --quiet --command="BEGIN; $(confirm_sql "$extra_request" "$extra_preview") $(begin_pending_sql) COMMIT;" >/dev/null
ordered_orgs="$(printf '%s\n%s\n' "$organization" "$extra_org" | LC_ALL=C sort)"
small_org="$(sed -n '1p' <<<"$ordered_orgs")"; large_org="$(sed -n '2p' <<<"$ordered_orgs")"
run_race governance-order "SELECT app_private.lock_organization_governance_v1('$large_org');" "$(unlink_sql)" \
  success '' "organization-governance:$large_org" '' "organization-governance:$small_org"
new_case unlink-before-purge
prepare_org_purge
run_race unlink-before-purge "$(unlink_sql)" "$purge_sql" success '' "personal-history-contribution-confirmation:$request"
assert_true unlinked-purge-preserved-source "SELECT NOT EXISTS(SELECT 1 FROM app_data.workspaces WHERE workspace_id='$organization')
  AND EXISTS(SELECT 1 FROM app_data.contacts WHERE contact_id='$source_main')
  AND EXISTS(SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1 WHERE deletion_request_id='$cycle');"
new_case purge-before-unlink
prepare_org_purge
run_race purge-before-unlink "$purge_sql" "$(unlink_sql)" success '' "personal-history-contribution-confirmation:$request"
assert_true shrunk-selection-completed "SELECT NOT EXISTS(SELECT 1 FROM app_data.workspaces WHERE workspace_id='$organization')
  AND EXISTS(SELECT 1 FROM app_private.account_history_contribution_unlink_completions_v1 WHERE deletion_request_id='$cycle');"

echo '0135 late request or organization requires retry; an unused preview in a locked organization may join'
new_case late-request yes
late_preview="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM ($(preview_sql "$target_project")) receipt;")"
late_request="$(new_uuid)"
run_race late-request "SELECT app_user_id FROM app_data.app_users WHERE app_user_id='$actor' FOR NO KEY UPDATE;" \
  "$(unlink_sql)" 55000 'account history contribution unlink retry required' '' \
  "$(confirm_sql "$late_request" "$late_preview") $(begin_pending_sql)" "personal-history-contribution-confirmation:$request"
run_psql --quiet --command="$(unlink_sql)" >/dev/null
new_case late-organization yes
create_target; extra_project="$next_project"
run_race late-organization "SELECT app_user_id FROM app_data.app_users WHERE app_user_id='$actor' FOR NO KEY UPDATE;" \
  "$(unlink_sql)" 55000 'account history contribution unlink retry required' '' \
  "$(preview_sql "$extra_project"); $(begin_pending_sql)" "personal-history-contribution-confirmation:$request"
run_psql --quiet --command="$(unlink_sql)" >/dev/null
new_case late-unused-preview yes
run_race late-unused-preview "SELECT app_user_id FROM app_data.app_users WHERE app_user_id='$actor' FOR NO KEY UPDATE;" \
  "$(unlink_sql)" success '' '' "$(preview_sql "$target_project"); $(begin_pending_sql)" "personal-history-contribution-confirmation:$request"
assert_true new-preview-unlinked "SELECT count(*)=2 AND bool_and(actor_app_user_id IS NULL AND source_contact_id IS NULL)
  FROM app_private.personal_history_contribution_previews_v1 WHERE target_project_id='$target_project';"

echo '0135 first unlink and exact replay reject each non-RC mode without writes'
new_case isolation
first_unlink="$(unlink_sql)"
replay_unlink="SELECT * FROM app_private.unlink_due_account_history_contributions_v1('$replay_actor','$replay_cycle');"
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  for operation in first replay; do
    if [[ "$operation" == first ]]; then statement="$first_unlink"; else statement="$replay_unlink"; fi
    before="$(database_state)"
    if run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $statement COMMIT;" >"$temporary_directory/isolation.out" 2>&1; then
      echo "0135 $isolation $operation unexpectedly succeeded" >&2; exit 1
    fi
    grep -Fq 'ERROR:  0A000: account history contribution unlink requires read committed' "$temporary_directory/isolation.out" \
      || { sed -n '1,120p' "$temporary_directory/isolation.out" >&2; exit 1; }
    [[ "$before" == "$(database_state)" ]] || { echo "0135 $isolation $operation changed database facts" >&2; exit 1; }
  done
done
echo '0135 account history contribution unlink concurrency passed.'
