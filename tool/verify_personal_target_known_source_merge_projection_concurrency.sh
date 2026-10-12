#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }

temporary_directory="$(mktemp -d)"
child_pids=()
holder_pid=''
waiter_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_ready() {
  local ready_name="$1" ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="
      SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('${ready_name}',0))
        THEN NOT pg_advisory_unlock(hashtextextended('${ready_name}',0))
        ELSE true END;
    " | tr -d '[:space:]')"
    [[ "${ready}" == 't' ]] && return
    sleep 0.05
  done
  echo "0121 holder 未完成指定语句：${ready_name}" >&2
  sed -n '1,120p' "${temporary_directory}/holder.out" >&2
  exit 1
}

start_holder() {
  local app_name="$1" ready_name="$2" statement="$3"
  mkfifo "${temporary_directory}/holder.fifo"
  PGAPPNAME="${app_name}" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"${temporary_directory}/holder.fifo" >"${temporary_directory}/holder.out" 2>&1 &
  holder_pid=$!
  child_pids+=("${holder_pid}")
  exec 3>"${temporary_directory}/holder.fifo"
  printf 'BEGIN; %s SELECT pg_advisory_lock(hashtextextended(\047%s\047,0));\n' \
    "${statement}" "${ready_name}" >&3
  wait_for_ready "${ready_name}"
}

release_holder() {
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "${holder_pid}"
  rm -f "${temporary_directory}/holder.fifo"
  holder_pid=''
}

start_waiter() {
  local app_name="$1" statement="$2"
  PGAPPNAME="${app_name}" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="${statement}" >"${temporary_directory}/waiter.out" 2>&1 &
  waiter_pid=$!
  child_pids+=("${waiter_pid}")
}

wait_for_exact_blocker() {
  local waiter_app="$1" blocker_app="$2" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="
      SELECT waiting.pid || '|' || blocker.pid || '|' || waiting.wait_event
      FROM pg_catalog.pg_stat_activity waiting
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiting.pid)) blocked(pid) ON true
      JOIN pg_catalog.pg_stat_activity blocker ON blocker.pid = blocked.pid
      WHERE waiting.application_name = '${waiter_app}' AND waiting.wait_event_type = 'Lock'
        AND blocker.application_name = '${blocker_app}' LIMIT 1;
    " | tr -d '[:space:]')"
    if [[ "${pair}" == *'|'* ]]; then
      echo "${waiter_app}: exact waiter/blocker PID and lock ${pair}"
      return
    fi
    sleep 0.05
  done
  echo "0121 未观察到精确 blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
  sed -n '1,120p' "${temporary_directory}/waiter.out" >&2
  exit 1
}

collect_waiter() {
  local label="$1" expected_state="$2" status=0
  wait "${waiter_pid}" || status=$?
  if [[ "${expected_state}" == 'success' ]]; then
    [[ "${status}" -eq 0 ]] && return
  elif [[ "${status}" -ne 0 ]] && grep -q "ERROR:  ${expected_state}:" "${temporary_directory}/waiter.out"; then
    return
  fi
  echo "0121 ${label}: exit=${status}, expected=${expected_state}" >&2
  sed -n '1,120p' "${temporary_directory}/waiter.out" >&2
  exit 1
}

assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  if [[ "${result}" != 't' ]]; then
    echo "0121 ${label} invariant failed: ${result}" >&2
    exit 1
  fi
}

new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]'; }
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7egc-known-source-projection-concurrency.example.test/auth/v1'
subject="7egc-known-source-projection-owner-$run_token"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$context"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0121 无法取得 personal context。' >&2; exit 1; }
done

# Snapshot every persistent table in both schemas, including context and audits.
state_query="$(run_psql --tuples-only --no-align --command="
  SELECT 'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' ||
    string_agg(format(
      'SELECT %L AS table_name, coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) AS rows FROM %I.%I t',
      schemaname || '.' || tablename,schemaname,tablename
    ), ' UNION ALL ' ORDER BY schemaname,tablename) || ') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
database_state() { run_psql --tuples-only --no-align --command="$state_query"; }
assert_state_unchanged() {
  [[ "$1" == "$(database_state)" ]] || { echo "0121 $2 changed persistent state。" >&2; exit 1; }
}
read_sql() {
  printf "SELECT app_private.read_known_source_personal_target_merge_projection_v1('%s','%s','%s','%s');" \
    "$app_user_id" "$workspace_id" "$project_id" "$generation_id"
}
read_only_sql() {
  printf "BEGIN READ ONLY; SELECT 'transaction|' || current_setting('transaction_read_only') || '|' || current_setting('transaction_isolation'); %s COMMIT;" "$1"
}
read_projection() {
  local before_state document
  before_state="$(database_state)"
  run_psql --quiet --tuples-only --no-align --command="$(read_only_sql "$(read_sql)")" >"$temporary_directory/direct.out"
  grep -q '^transaction|on|read committed$' "$temporary_directory/direct.out"
  document="$(sed -n '/^{/p' "$temporary_directory/direct.out")"
  [[ -n "$document" ]] || { echo '0121 READ ONLY 没有返回投影。' >&2; exit 1; }
  assert_state_unchanged "$before_state" 'READ ONLY projection'
  printf '%s\n' "$document"
}
assert_document() {
  local label="$1" document="$2" condition="$3" result
  result="$(run_psql --tuples-only --no-align --set=document="$document" <<SQL
SELECT $condition FROM (SELECT :'document'::jsonb AS document) projection;
SQL
)"
  [[ "$result" == 't' ]] || { echo "0121 $label document invariant failed: $result" >&2; exit 1; }
}
expect_fresh_forbidden() {
  local before_state status=0
  before_state="$(database_state)"
  run_psql --quiet --tuples-only --no-align --command="$(read_only_sql "$(read_sql)")" \
    >"$temporary_directory/fresh.out" 2>&1 || status=$?
  if [[ "$status" -eq 0 ]] || ! grep -q 'ERROR:  42501:' "$temporary_directory/fresh.out"; then
    echo "0121 fresh read expected 42501, exit=$status" >&2
    sed -n '1,120p' "$temporary_directory/fresh.out" >&2
    exit 1
  fi
  assert_state_unchanged "$before_state" 'rejected fresh projection'
}
contact_payload_sql() {
  local links="$1"
  printf "%s" "jsonb_build_object('contactId','$contact_id','workspaceId','$workspace_id','projectId','$project_id',
    'questionnaireVersionId','$questionnaire_version_id','reason','0121 synthetic revision',
    'occurredAtUtc',clock_timestamp() - interval '14 months','occurredTimeZone','UTC','channel','video_call',
    'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
    'targetLinks',$links)"
}
revise_empty_sql() {
  printf "%s" "SELECT result_code FROM app_data.apply_contact_revise_v3(
    '$app_user_id','$contact_id-revise',1,'contact.revise.v1','7egc-device','$contact_id',1,
    $(contact_payload_sql "'[]'::jsonb"));"
}
create_pair() {
  local label="$1" links
  first_target="$(run_psql --tuples-only --no-align --command="
    SELECT target->>'target_id' FROM app_data.create_promotion_target(
      '$app_user_id','$workspace_id','$project_id','person',
      '0121 $label first $run_token','+1 773 555 0121',NULL,'7egc-$run_token-$label-a');")"
  second_target="$(run_psql --tuples-only --no-align --command="
    SELECT target->>'target_id' FROM app_data.create_promotion_target(
      '$app_user_id','$workspace_id','$project_id','person',
      '0121 $label second $run_token','+1 773 555 0121',NULL,'7egc-$run_token-$label-b');")"
  for target_id in "$first_target" "$second_target"; do
    [[ "$target_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0121 未能创建目标对。' >&2; exit 1; }
  done
  preview_id="$(run_psql --tuples-only --no-align --command="
    SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
      '$issuer','$subject','$project_id','$first_target','$second_target');")"
  activation_request="$(new_uuid)"
  generation_id="$(run_psql --tuples-only --no-align --command="
    SELECT app_private.activate_personal_target_merge_generation_v2(
      '$app_user_id','$project_id','$activation_request','$preview_id',
      '$first_target','$first_target','$second_target','$first_target');")"
  run_psql --quiet --command="UPDATE app_data.promotion_targets SET phone = NULL
    WHERE promotion_target_id = '$second_target';" >/dev/null
  contact_id="7egc-$run_token-$label"
  links="jsonb_build_array(jsonb_build_object('targetId','$first_target','targetType','person','responseLevel',2,
    'followUpConsent','yes','institutionRepresentativeConfirmed',false,'confirmStageZero',true))"
  result="$(run_psql --tuples-only --no-align --command="
    SELECT result_code FROM app_data.apply_contact_submit_v3(
      '$app_user_id','$contact_id-submit',1,'contact.submit.v1','7egc-device','$contact_id',0,
      $(contact_payload_sql "$links"));")"
  [[ "$result" == 'accepted' ]] || { echo "0121 seed contact rejected: $result" >&2; exit 1; }
  before_document="$(read_projection)"
  assert_document "$label-seed" "$before_document" "document->>'generation_id' = '$generation_id'
    AND document->>'retained_target_id' = '$first_target' AND document->'phone' = 'null'::jsonb
    AND document->>'phone_source_target_id' = '$second_target'
    AND jsonb_array_length(document->'sources') = 2
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(document->'sources') source
      WHERE source->>'target_id' = '$first_target'
        AND source->'project_relationship'->>'stage' = '0'
        AND source->'project_relationship'->>'revision_number' = '1'
        AND jsonb_array_length(source->'contact_links') = 1
        AND source->'contact_links'->0->>'merge_generation_id' = '$generation_id')"
}
run_snapshot_race() {
  local label="$1" writer_sql="$2" gate_key holder_app reader_app after_writer_document_state old_document
  gate_key="7egc-snapshot-$label-$run_token"
  holder_app="7egc-holder-$label-$run_token"
  reader_app="7egc-reader-$label-$run_token"
  start_holder "$holder_app" "7egc-ready-$label-$run_token" \
    "SELECT pg_advisory_xact_lock(hashtextextended('$gate_key',0));"
  # At READ COMMITTED, this SQL command's snapshot precedes its gate wait.
  start_waiter "$reader_app" "$(read_only_sql "WITH snapshot_gate AS MATERIALIZED (
    SELECT pg_advisory_xact_lock(hashtextextended('$gate_key',0))
  ) SELECT app_private.read_known_source_personal_target_merge_projection_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id') FROM snapshot_gate;")"
  wait_for_exact_blocker "$reader_app" "$holder_app"
  assert_true reader-no-row-locks "SELECT NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_locks lock
    JOIN pg_catalog.pg_stat_activity activity ON activity.pid = lock.pid
    WHERE activity.application_name = '$reader_app' AND lock.granted
      AND lock.locktype IN ('relation','tuple') AND lock.mode IN (
        'RowShareLock','RowExclusiveLock','ShareRowExclusiveLock','ExclusiveLock','AccessExclusiveLock'));"
  # This writer must complete while the reader is still waiting on our gate.
  run_psql --quiet --tuples-only --no-align --command="BEGIN; $writer_sql COMMIT;" \
    >"$temporary_directory/writer.out" 2>&1
  wait_for_exact_blocker "$reader_app" "$holder_app"
  after_writer_document_state="$(database_state)"
  release_holder
  collect_waiter "$label" success
  grep -q '^transaction|on|read committed$' "$temporary_directory/waiter.out"
  old_document="$(sed -n '/^{/p' "$temporary_directory/waiter.out")"
  [[ "$old_document" == "$before_document" ]] || {
    echo "0121 $label returned a mixed or refreshed command snapshot。" >&2; exit 1;
  }
  assert_state_unchanged "$after_writer_document_state" "$label old-snapshot read"
}

create_pair facts
writer_sql="SELECT result FROM app_data.update_promotion_target_relationship(
  '$app_user_id','$workspace_id','$project_id','$first_target',1,3,'active','0121 changed note',
  'progress_update',NULL,'7egc-$run_token-facts-stage',NULL);
  $(revise_empty_sql)"
run_snapshot_race facts "$writer_sql"
grep -q '^accepted$' "$temporary_directory/writer.out"
fresh_document="$(read_projection)"
[[ "$fresh_document" != "$before_document" ]] || { echo '0121 fresh facts 没有变化。' >&2; exit 1; }
assert_document fresh-facts "$fresh_document" "EXISTS (
  SELECT 1 FROM jsonb_array_elements(document->'sources') source
  WHERE source->>'target_id' = '$first_target'
    AND source->'project_relationship'->>'stage' = '3'
    AND source->'project_relationship'->>'revision_number' = '2'
    AND source->'project_relationship'->>'follow_up_note' = '0121 changed note'
    AND source->'contact_links' = '[]'::jsonb)"

create_pair current-project
other_project_id="$(new_uuid)"
run_psql --quiet --command="INSERT INTO app_data.projects(project_id,workspace_id,display_name)
  VALUES ('$other_project_id','$workspace_id','0121 next project $run_token');" >/dev/null
run_snapshot_race current-project "UPDATE app_data.user_current_projects SET project_id = '$other_project_id'
  WHERE app_user_id = '$app_user_id';"
expect_fresh_forbidden
run_psql --quiet --command="UPDATE app_data.user_current_projects SET project_id = '$project_id'
  WHERE app_user_id = '$app_user_id';" >/dev/null

create_pair actor
run_snapshot_race actor "UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = '$app_user_id';"
expect_fresh_forbidden
run_psql --quiet --command="UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = '$app_user_id';" >/dev/null

create_pair end
fingerprint="$(run_psql --tuples-only --no-align --command="
  SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('$generation_id');")"
end_request="$(new_uuid)"
run_snapshot_race end "SELECT app_private.end_known_source_personal_target_merge_generation_v1(
  '$app_user_id','$workspace_id','$project_id','$end_request','$generation_id','$fingerprint');"
expect_fresh_forbidden

create_pair expiry
expiry_request="$(new_uuid)"
run_snapshot_race expiry "UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '13 months'
  WHERE promotion_target_id = '$first_target';
  SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id','$expiry_request','$generation_id');"
expect_fresh_forbidden
assert_true expiry-current-state "SELECT
  (SELECT count(*) = 2 AND bool_and(status = 'anonymized') FROM app_data.promotion_targets
    WHERE promotion_target_id IN ('$first_target','$second_target'))
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '$generation_id')
  AND (SELECT count(*) = 1 FROM app_private.personal_target_merge_end_events_v1
    WHERE generation_id = '$generation_id' AND operation = 'personal_target_known_source_merge_expire')
  AND (SELECT count(*) = 2 FROM app_data.promotion_target_retention_events
    WHERE promotion_target_id IN ('$first_target','$second_target') AND event_type = 'anonymized' AND reason = 'retention_expired');"

echo '0121 concurrency passed: real READ ONLY/READ COMMITTED, coherent command snapshots across fact/context/end/expiry commits, fresh results, and zero read writes.'
