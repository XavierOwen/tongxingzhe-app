#!/usr/bin/env bash

set -euo pipefail
: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
holder_pid=''
reader_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "$holder_pid" "$reader_pid"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then kill "$pid" >/dev/null 2>&1 || true; fi
    wait "$pid" >/dev/null 2>&1 || true
  done
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" "$temporary_directory/reader.out" "$temporary_directory/fresh.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0141 $1 invariant failed: $result" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7fd-resolution-plan.example.test/auth/v1'
subject="7fd-owner-$run_token"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$context"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0141 missing personal context。' >&2; exit 1; }
done
first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
  '$app_user_id','$workspace_id','$project_id','person','0141 first $run_token','+1 312 555 0141',NULL,'7fd-first-$run_token');")"
second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
  '$app_user_id','$workspace_id','$project_id','person','0141 second $run_token','+1 312 555 0141',NULL,'7fd-second-$run_token');")"
preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
  '$issuer','$subject','$project_id','$first_target','$second_target');")"
generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
  '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$first_target','$first_target','$first_target','$second_target');")"
contact_id="7fd-contact-$run_token"
assert_true submit "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
  '$app_user_id','$contact_id-submit',1,'contact.submit.v1','7fd-device','$contact_id',0,
  jsonb_build_object('contactId','$contact_id','workspaceId','$workspace_id','projectId','$project_id',
    'questionnaireVersionId','$questionnaire_version_id','reason','0141 snapshot contact','occurredAtUtc',clock_timestamp(),
    'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
    'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
run_psql --quiet --command="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
  '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$contact_id',1,2,'unknown',false,true);" >/dev/null
revise_sql() {
  printf "%s" "SELECT result_code FROM app_data.apply_contact_revise_v3('$app_user_id','$contact_id-revise-$1',1,
    'contact.revise.v1','7fd-device','$contact_id',$1,(SELECT snapshot || jsonb_build_object('reason','0141 ordinary revision','interestLevel',3)
      FROM app_data.contact_revisions WHERE contact_id='$contact_id' AND revision_number=$1));"
}
run_psql --quiet --command="$(revise_sql 1)" >/dev/null
run_psql --quiet --command="SELECT app_private.stage_unassigned_personal_merge_contact_v1(
  '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$contact_id',2,NULL,'refused',false,true);" >/dev/null

late_contact_id="$contact_id-late"
assert_true late-submit "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
  '$app_user_id','$late_contact_id-submit',1,'contact.submit.v1','7fd-device','$late_contact_id',0,
  jsonb_build_object('contactId','$late_contact_id','workspaceId','$workspace_id','projectId','$project_id',
    'questionnaireVersionId','$questionnaire_version_id','reason','0141 late snapshot contact','occurredAtUtc',clock_timestamp(),
    'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
    'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks','[]'::jsonb));"
project_stage_sql="SELECT * FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
  '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id',2,'paused','0141 raw project note','progress_update','0141 raw reason');"
run_psql --quiet --command="$project_stage_sql $project_stage_sql" >/dev/null
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
database_state() { run_psql --tuples-only --no-align --command="$state_query"; }
refresh_plan() {
  local fingerprints
  fingerprints="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT
    contact->'known_source_plan'->>'fact_fingerprint',contact->>'pending_fingerprint',project->>'pending_fingerprint' FROM
    (SELECT app_private.read_personal_merge_unassigned_contact_plan_v1('$app_user_id','$workspace_id','$project_id','$generation_id') contact,
      app_private.read_personal_merge_unassigned_project_relationship_plan_v1('$app_user_id','$workspace_id','$project_id','$generation_id') project) inventories;")"
  IFS='|' read -r known_fingerprint contact_pending_fingerprint project_pending_fingerprint <<<"$fingerprints"
  contact_assignments="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'pending_fact_id',pending_fact_id,'source_target_id','$first_target') ORDER BY pending_fact_id)
    FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE generation_id='$generation_id';")"
  project_assignments="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'pending_fact_id',pending_fact_id,'source_target_id','$second_target') ORDER BY pending_fact_id)
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 WHERE generation_id='$generation_id';")"
  read_sql="SELECT app_private.plan_personal_merge_mixed_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id','$known_fingerprint','$contact_pending_fingerprint','$project_pending_fingerprint',
    '$contact_assignments'::jsonb,'$project_assignments'::jsonb)"
}
read_document() { run_psql --quiet --tuples-only --no-align --command="BEGIN READ ONLY; $read_sql; COMMIT;"; }
refresh_plan
before_document="$(read_document)"
run_snapshot_race() {
  local label="$1" writer_sql="$2" key="7fd-gate-$1-$run_token" ready_key="7fd-ready-$1-$run_token"
  local holder_app="7fd-holder-$1-$run_token" reader_app="7fd-reader-$1-$run_token" ready pair after_state document
  mkfifo "$temporary_directory/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"$temporary_directory/holder.fifo" >"$temporary_directory/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"$temporary_directory/holder.fifo"
  printf "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('%s',0)); SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$key" "$ready_key" >&3
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('$ready_key',0))
      THEN NOT pg_advisory_unlock(hashtextextended('$ready_key',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && break
    sleep 0.05
  done
  [[ "$ready" == t ]] || { echo '0141 holder not ready。' >&2; exit 1; }
  # The command snapshot starts before the test gate; the production reader takes no gate or row lock.
  PGAPPNAME="$reader_app" "${psql_base[@]}" --quiet --tuples-only --no-align --command="BEGIN READ ONLY;
    SELECT 'mode|'||current_setting('transaction_read_only')||'|'||current_setting('transaction_isolation');
    WITH gate AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended('$key',0))) $read_sql FROM gate; COMMIT;" \
    >"$temporary_directory/reader.out" 2>&1 &
  reader_pid=$!
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT reader.pid||'|'||holder.pid||'|'||reader.wait_event
      FROM pg_stat_activity reader JOIN LATERAL unnest(pg_blocking_pids(reader.pid)) blocker(pid) ON true
      JOIN pg_stat_activity holder ON holder.pid=blocker.pid
      JOIN pg_locks locks ON locks.pid=reader.pid AND NOT locks.granted AND locks.locktype='advisory' AND locks.objsubid=1
        AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
        AND locks.classid=((hashtextextended('$key',0)>>32)&4294967295)::oid
        AND locks.objid=(hashtextextended('$key',0)&4294967295)::oid
      WHERE reader.application_name='$reader_app' AND holder.application_name='$holder_app' AND reader.wait_event_type='Lock';" | tr -d '[:space:]')"
    [[ "$pair" == *'|'* ]] && break
    sleep 0.05
  done
  [[ "$pair" == *'|'* ]] || {
    echo '0141 exact reader/holder PID or advisory gate missing.' >&2
    run_psql --command="SELECT activity.pid,activity.application_name,pg_blocking_pids(activity.pid),locks.locktype,locks.mode,locks.granted,
      locks.relation::regclass,locks.transactionid,locks.classid,locks.objid,locks.objsubid FROM pg_stat_activity activity LEFT JOIN pg_locks locks ON locks.pid=activity.pid
      WHERE activity.application_name IN ('$reader_app','$holder_app') ORDER BY activity.pid,locks.granted,locks.locktype;" >&2
    sed -n '/ERROR:/p' "$temporary_directory/reader.out" >&2
    exit 1
  }
  echo "0141 $label exact reader/holder PID and test gate $key: $pair"
  assert_true reader-no-row-locks "SELECT NOT EXISTS (SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
    WHERE activity.application_name='$reader_app' AND locks.granted AND locks.locktype IN ('relation','tuple')
    AND locks.mode IN ('RowShareLock','RowExclusiveLock','ShareRowExclusiveLock','ExclusiveLock','AccessExclusiveLock'));"
  run_psql --quiet --command="BEGIN; $writer_sql COMMIT;" >/dev/null
  after_state="$(database_state)"
  assert_true writer-committed-before-gate-release "SELECT EXISTS(SELECT 1 FROM pg_stat_activity reader JOIN pg_stat_activity holder ON holder.pid=ANY(pg_blocking_pids(reader.pid))
    WHERE reader.application_name='$reader_app' AND holder.application_name='$holder_app' AND reader.wait_event_type='Lock');"
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "$holder_pid"
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  wait "$reader_pid" || { sed -n '/ERROR:/p' "$temporary_directory/reader.out" >&2; exit 1; }
  reader_pid=''
  grep -q '^mode|on|read committed$' "$temporary_directory/reader.out"
  document="$(sed -n '/^{/p' "$temporary_directory/reader.out")"
  [[ "$document" == "$before_document" ]] || { echo "0141 $label mixed command snapshot。" >&2; exit 1; }
  [[ "$after_state" == "$(database_state)" ]] || { echo '0141 reader changed persistent state。' >&2; exit 1; }
}

expect_fresh_rejection() {
  local expected="$1" status=0 after_state
  after_state="$(database_state)"
  read_document >"$temporary_directory/fresh.out" 2>&1 || status=$?
  [[ "$status" -ne 0 ]] && grep -q "ERROR:  $expected:" "$temporary_directory/fresh.out" || {
    echo "0141 fresh command expected $expected; status $status." >&2
    sed -n '/ERROR:/p' "$temporary_directory/fresh.out" >&2
    exit 1
  }
  [[ "$after_state" == "$(database_state)" ]] || { echo '0141 rejected fresh reader changed persistent state.' >&2; exit 1; }
}
run_snapshot_race contact-stage-growth "SELECT app_private.stage_unassigned_personal_merge_contact_v1(
  '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$late_contact_id',1,2,'unknown',false,true);"
expect_fresh_rejection 23505
refresh_plan
fresh_document="$(read_document)"
assert_true contact-growth-only "SELECT newer->'contact_resolution_plan'<>older->'contact_resolution_plan'
  AND newer->'project_relationship_resolution_plan'=older->'project_relationship_resolution_plan'
  AND newer->>'resolution_fingerprint'<>older->>'resolution_fingerprint'
  FROM(SELECT '$fresh_document'::jsonb newer,'$before_document'::jsonb older) documents;"
before_document="$fresh_document"

run_snapshot_race project-stage-growth "$project_stage_sql"
expect_fresh_rejection 23505
refresh_plan
fresh_document="$(read_document)"
assert_true project-growth-only "SELECT newer->'contact_resolution_plan'=older->'contact_resolution_plan'
  AND newer->'project_relationship_resolution_plan'<>older->'project_relationship_resolution_plan'
  AND newer->>'resolution_fingerprint'<>older->>'resolution_fingerprint'
  FROM(SELECT '$fresh_document'::jsonb newer,'$before_document'::jsonb older) documents;"
before_document="$fresh_document"

run_snapshot_race actor-revocation "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';"
expect_fresh_rejection 42501
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$app_user_id';"
echo '0141 three exact-PID READ ONLY command snapshots passed; writers committed before gate release and fresh commands refreshed or rejected.'

