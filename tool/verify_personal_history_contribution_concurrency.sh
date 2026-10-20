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
      WHERE application_name IN ('$holder_app','$waiter_app') AND pid<>pg_backend_pid();" >/dev/null 2>&1 || true
  fi
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" \
    "$temporary_directory/waiter.out" "$temporary_directory/isolation.out" "$temporary_directory/rejected.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0134 $1 invariant failed: $result" >&2; exit 1; }
}
state_query="SELECT jsonb_build_object(
  'previews',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY preview_id),'[]') FROM app_private.personal_history_contribution_previews_v1 t),
  'copies',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY copy_id),'[]') FROM app_private.organization_historical_contact_copies_v1 t),
  'confirmations',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY request_id),'[]') FROM app_private.personal_history_contribution_confirmations_v1 t));"
contribution_state() { run_psql --tuples-only --no-align --command="$state_query"; }
new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();'; }
confirm_sql() { printf "SELECT * FROM app_private.confirm_personal_history_contribution_v1('%s','%s','%s');" "$actor" "$1" "$2"; }
preview_sql() { printf "SELECT * FROM app_private.preview_personal_history_contribution_v1('%s','%s','%s')" "$actor" "$source_contact" "$target_project"; }
issuer='https://7ew-history-concurrency.example.test'
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.bootstrap_personal_context('$issuer','contributor-$run_token');")"
IFS='|' read -r actor personal_workspace personal_project questionnaire <<<"$context"
owner="$(run_psql --tuples-only --no-align --command="SELECT app_user_id
  FROM app_data.bootstrap_personal_context('$issuer','owner-$run_token');")"
for id in "$actor" "$personal_workspace" "$personal_project" "$questionnaire" "$owner"; do
  [[ "$id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0134 missing bootstrap context' >&2; exit 1; }
done
new_case() {
  local label="$1" invitation
  source_contact="7ew-$label-$run_token"
  target_project="$(new_uuid)"
  organization="$(run_psql --tuples-only --no-align --command="SELECT organization_workspace_id
    FROM app_private.create_organization_v1('$owner',gen_random_uuid(),'0134 $label $run_token');")"
  invitation="$(run_psql --tuples-only --no-align --command="SELECT invitation_id FROM
    app_private.create_organization_directed_account_invitation_v1('$owner',gen_random_uuid(),'$organization','$actor');")"
  organization_membership="$(run_psql --tuples-only --no-align --command="SELECT organization_membership_id FROM
    app_private.accept_organization_directed_account_invitation_v1('$actor','$invitation');")"
  run_psql --quiet --command="INSERT INTO app_data.projects(project_id,workspace_id,display_name)
    VALUES('$target_project','$organization','0134 target $label');" >/dev/null
  project_membership="$(run_psql --tuples-only --no-align --command="SELECT project_membership_id FROM
    app_private.assign_organization_project_member_v1('$owner',gen_random_uuid(),'$organization','$target_project','$organization_membership');")"
  assert_true "$label-submit" "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
    '$actor','$source_contact-submit',1,'contact.submit.v1','7ew-device','$source_contact',0,
    jsonb_build_object('contactId','$source_contact','workspaceId','$personal_workspace','projectId','$personal_project',
      'questionnaireVersionId','$questionnaire','reason','0134 source','occurredAtUtc','2025-04-05T06:07:08.123456Z',
      'occurredTimeZone','America/Chicago','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
      'reachCount',3,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
  preview="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM ($(preview_sql)) receipt;")"
  request="$(new_uuid)"
  for id in "$organization" "$organization_membership" "$project_membership" "$preview"; do
    [[ "$id" =~ ^[0-9a-f-]{36}$ ]] || { echo "0134 $label missing seeded UUID" >&2; exit 1; }
  done
}
revise_sql() {
  printf "SELECT * FROM app_data.apply_contact_revise_v3('%s','%s-revise',1,'contact.revise.v1','7ew-device','%s',
    (SELECT current_revision FROM app_data.contacts WHERE contact_id='%s'),
    (SELECT revision.snapshot||jsonb_build_object('reason','0134 revised source','interestLevel',4,'reachCount',5)
      FROM app_data.contacts contact JOIN app_data.contact_revisions revision
        ON revision.contact_id=contact.contact_id AND revision.revision_number=contact.current_revision
      WHERE contact.contact_id='%s'));" "$actor" "$source_contact" "$source_contact" "$source_contact" "$source_contact"
}
void_sql() {
  printf "SELECT * FROM app_data.apply_contact_void_v3('%s','%s-void',1,'contact.void.v1','7ew-device','%s',
    (SELECT current_revision FROM app_data.contacts WHERE contact_id='%s'),
    jsonb_build_object('contactId','%s','workspaceId','%s','projectId','%s','reason','0134 void source'));" \
    "$actor" "$source_contact" "$source_contact" "$source_contact" "$source_contact" "$personal_workspace" "$personal_project"
}
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT EXISTS(
      SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
      WHERE activity.application_name='$holder_app' AND locks.granted AND locks.locktype='advisory' AND locks.objsubid=1
        AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
        AND locks.classid=((hashtextextended('$1',0)>>32)&4294967295)::oid
        AND locks.objid=(hashtextextended('$1',0)&4294967295)::oid);" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    if ! kill -0 "$holder_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo '0134 holder did not acquire its ready lock' >&2
  sed -n '1,120p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local key="$1" pair predicate
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
    [[ "$pair" == *'|'* ]] && { echo "0134 exact waiter/holder PID and lock: $pair"; return; }
    if ! kill -0 "$waiter_pid" >/dev/null 2>&1; then break; fi
    sleep 0.05
  done
  echo "0134 expected blocker PID or lock was not observed: $key" >&2
  run_psql --pset=pager=off --command="SELECT activity.application_name,activity.pid,activity.backend_xid,
    activity.wait_event_type,activity.wait_event,pg_blocking_pids(activity.pid) AS blocking_pids,
    locks.locktype,locks.mode,locks.granted,locks.relation::regclass AS relation,
    locks.transactionid,locks.database,locks.classid,locks.objid,locks.objsubid
    FROM pg_stat_activity activity LEFT JOIN pg_locks locks ON locks.pid=activity.pid
    WHERE activity.application_name IN ('$holder_app','$waiter_app')
    ORDER BY activity.application_name,locks.granted,locks.locktype,locks.relation,locks.classid,locks.objid;" >&2
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
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_state="$4" expected_message="$5"
  local key="${6:-}" deadline_preview="${7:-}" status=0 expected_snapshot due ready_key="7ew-ready-$run_token-$1"
  holder_app="7ew-h-$label-$run_token"; waiter_app="7ew-w-$label-$run_token"
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
  if [[ -n "$deadline_preview" ]]; then
    assert_true deadline-wait-before-expiry "SELECT clock_timestamp()<expires_at_utc
      FROM app_private.personal_history_contribution_previews_v1 WHERE preview_id='$deadline_preview';"
    assert_waiter_lock deadline-status-fence "management-follow-up-consent-opt-in:$target_project"
    due=f
    for _ in $(seq 1 300); do
      due="$(run_psql --tuples-only --no-align --command="SELECT clock_timestamp()>=expires_at_utc
        FROM app_private.personal_history_contribution_previews_v1 WHERE preview_id='$deadline_preview';" | tr -d '[:space:]')"
      [[ "$due" == t ]] && break
      sleep 0.05
    done
    [[ "$due" == t ]] || { echo '0134 synthetic preview did not expire' >&2; exit 1; }
  fi
  printf '%s COMMIT;\n\\q\n' "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '1,120p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_snapshot="$(sed -n '/^{/p' "$temporary_directory/holder.out")"
  [[ -n "$expected_snapshot" ]] || { echo '0134 holder snapshot missing' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_state" == success ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '1,120p' "$temporary_directory/waiter.out" >&2; exit 1; }
  else
    if [[ "$status" -eq 0 ]] || ! grep -Fq "ERROR:  $expected_state: $expected_message" "$temporary_directory/waiter.out"; then
      echo "0134 $label expected $expected_state / $expected_message, status $status" >&2
      sed -n '1,120p' "$temporary_directory/waiter.out" >&2
      exit 1
    fi
    [[ "$expected_snapshot" == "$(contribution_state)" ]] || { echo "0134 $label failure changed contribution facts" >&2; exit 1; }
  fi
}
expect_rejected() {
  local before
  before="$(contribution_state)"
  if run_psql --quiet --command="$1" >"$temporary_directory/rejected.out" 2>&1; then
    echo '0134 rejected call unexpectedly succeeded' >&2; exit 1
  fi
  grep -Fq "ERROR:  $2: $3" "$temporary_directory/rejected.out" \
    || { sed -n '1,120p' "$temporary_directory/rejected.out" >&2; exit 1; }
  [[ "$before" == "$(contribution_state)" ]] || { echo '0134 rejected call changed contribution facts' >&2; exit 1; }
}

echo '0134 same request replay and two previews for one source'
new_case same-request
run_race same-request "$(confirm_sql "$request" "$preview")" "$(confirm_sql "$request" "$preview")" success '' \
  "personal-history-contribution-confirmation:$request"
first="$(awk '/^personal-history-contribution-confirmation:v1\|/ {print;exit}' "$temporary_directory/holder.out")"
second="$(awk '/^personal-history-contribution-confirmation:v1\|/ {print;exit}' "$temporary_directory/waiter.out")"
[[ -n "$first" && "$first" == "$second" && "$(awk -F'|' '{print NF}' <<<"$first")" -eq 4 ]] \
  || { echo '0134 exact four-field replay failed' >&2; exit 1; }
new_case two-previews
other_preview="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM ($(preview_sql)) receipt;")"
other_request="$(new_uuid)"
run_race two-previews "$(confirm_sql "$request" "$preview")" "$(confirm_sql "$other_request" "$other_preview")" \
  22023 'personal history contribution idempotency conflict'
assert_true source-copied-once "SELECT count(*)=1 FROM app_private.personal_history_contribution_confirmations_v1
  WHERE target_project_id='$target_project' AND source_contact_id='$source_contact';"

echo '0134 accepted revision changes serialize on the source contact'
new_case revision-first
run_race revision-first "$(revise_sql)" "$(confirm_sql "$request" "$preview")" \
  22023 'personal history contribution idempotency conflict' "contact:$source_contact"
new_case void-first
run_race void-first "$(void_sql)" "$(confirm_sql "$request" "$preview")" \
  22023 'personal history contribution idempotency conflict' "contact:$source_contact"
new_case confirm-first
run_race confirm-first "$(confirm_sql "$request" "$preview")" "$(void_sql)" success '' "contact:$source_contact"
assert_true source-void-copy-frozen "SELECT source.lifecycle_status='voided' AND copy.reach_count=3 AND copy.interest_level=2
  FROM app_data.contacts source JOIN app_private.personal_history_contribution_confirmations_v1 receipt
    ON receipt.source_contact_id=source.contact_id JOIN app_private.organization_historical_contact_copies_v1 copy USING(copy_id)
  WHERE receipt.request_id='$request';"
run_psql --quiet --command="$(confirm_sql "$request" "$preview")" >/dev/null

echo '0134 current membership, actor, project, and organization are checked after waits'
new_case member-close
run_race member-close "UPDATE app_data.project_memberships SET inactive_from_utc=clock_timestamp()
  WHERE project_membership_id='$project_membership';" "$(confirm_sql "$request" "$preview")" \
  42501 'personal history contribution forbidden' "organization-membership:$organization:$actor"
new_case actor-status
run_race actor-status "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$actor';" \
  "$(confirm_sql "$request" "$preview")" 42501 'personal history contribution forbidden'
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$actor';" >/dev/null
new_case project-status
run_race project-status "UPDATE app_data.projects SET status='archived' WHERE project_id='$target_project';" \
  "$(confirm_sql "$request" "$preview")" 42501 'personal history contribution forbidden' "organization-membership:$organization:$actor"
new_case organization-delete
deletion_request="$(new_uuid)"
run_race organization-delete "SELECT * FROM app_private.request_organization_deletion_v1('$owner','$deletion_request','$organization');" \
  "$(confirm_sql "$request" "$preview")" 42501 'personal history contribution forbidden' "organization-governance:$organization"
new_case confirm-before-delete
deletion_request="$(new_uuid)"
run_race confirm-before-delete "$(confirm_sql "$request" "$preview")" \
  "SELECT * FROM app_private.request_organization_deletion_v1('$owner','$deletion_request','$organization');" \
  success '' "organization-governance:$organization"
expect_rejected "$(confirm_sql "$request" "$preview")" 42501 'personal history contribution forbidden'

echo '0134 request locks precede authorization and the deadline follows the last wait'
new_case request-lock
run_race request-lock "SELECT pg_advisory_xact_lock(hashtextextended('personal-history-contribution-confirmation:$request',0));" \
  "$(confirm_sql "$request" "$preview")" success '' "personal-history-contribution-confirmation:$request"
new_case deadline
run_psql --quiet --command="BEGIN; SET LOCAL session_replication_role=replica;
  UPDATE app_private.personal_history_contribution_previews_v1 SET issued_at_utc=boundary.at-interval '15 minutes',expires_at_utc=boundary.at
    FROM (SELECT clock_timestamp()+interval '8 seconds' AS at) boundary WHERE preview_id='$preview'; COMMIT;" >/dev/null
run_race deadline "SELECT pg_advisory_xact_lock(hashtextextended('contact:$source_contact',0));" \
  "$(confirm_sql "$request" "$preview")" 22023 'personal history contribution idempotency conflict' "contact:$source_contact" "$preview"

echo '0134 preview, first confirmation, and replay reject other isolation modes'
new_case isolation-first
first_confirm="$(confirm_sql "$request" "$preview")"
first_preview="$(preview_sql)"
new_case isolation-replay
run_psql --quiet --command="$(confirm_sql "$request" "$preview")" >/dev/null
replay_confirm="$(confirm_sql "$request" "$preview")"
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  for operation in preview confirmation replay; do
    case "$operation" in
      preview) statement="$first_preview;" ;;
      confirmation) statement="$first_confirm" ;;
      replay) statement="$replay_confirm" ;;
    esac
    before="$(contribution_state)"
    if run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $statement COMMIT;" >"$temporary_directory/isolation.out" 2>&1; then
      echo "0134 $isolation $operation unexpectedly succeeded" >&2; exit 1
    fi
    grep -Fq 'ERROR:  0A000: personal history contribution requires read committed' "$temporary_directory/isolation.out" \
      || { sed -n '1,120p' "$temporary_directory/isolation.out" >&2; exit 1; }
    [[ "$before" == "$(contribution_state)" ]] || { echo "0134 $isolation $operation changed contribution facts" >&2; exit 1; }
  done
done
echo '0134 personal history contribution concurrency passed.'
