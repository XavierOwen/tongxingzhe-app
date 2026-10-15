#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请显式设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
holder_pid=''
reader_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${holder_pid}" "${reader_pid}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}/holder.fifo" "${temporary_directory}/holder.out" \
    "${temporary_directory}/reader.out" "${temporary_directory}/confirm.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7ekc-known-source-split-plan.example.test/auth/v1'
subject="7ekc-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"${context}"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0124 无法取得 personal context。' >&2; exit 1; }
done
first_target="$(run_psql --tuples-only --no-align --command="
  SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0124 first $run_token',
    '+1 312 555 0124',NULL,'7ekc-$run_token-first');")"
second_target="$(run_psql --tuples-only --no-align --command="
  SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0124 second $run_token',
    '+1 312 555 0124',NULL,'7ekc-$run_token-second');")"
preview_id="$(run_psql --tuples-only --no-align --command="
  SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
    '$issuer','$subject','$project_id','$first_target','$second_target');")"
generation_id="$(run_psql --tuples-only --no-align --command="
  SELECT app_private.activate_personal_target_merge_generation_v2(
    '$app_user_id','$project_id',gen_random_uuid(),'$preview_id',
    '$first_target','$first_target','$first_target','$second_target');")"
for fixture_id in "$first_target" "$second_target" "$preview_id" "$generation_id"; do
  [[ "$fixture_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0124 无法建立 generation。' >&2; exit 1; }
done

submit_contact() {
  local contact_id="7ekc-$run_token-$1" result
  result="$(run_psql --tuples-only --no-align --command="
    SELECT result_code FROM app_data.apply_contact_submit_v3(
      '$app_user_id','$contact_id-submit',1,'contact.submit.v1','7ekc-device','$contact_id',0,
      jsonb_build_object('contactId','$contact_id','workspaceId','$workspace_id','projectId','$project_id',
        'questionnaireVersionId','$questionnaire_version_id','reason','0124 synthetic contact',
        'occurredAtUtc',clock_timestamp(),'occurredTimeZone','UTC','channel','video_call',
        'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,
        'answers','[]'::jsonb,'targetLinks',jsonb_build_array(jsonb_build_object(
          'targetId','$first_target','targetType','person','responseLevel',2,'followUpConsent','unknown',
          'institutionRepresentativeConfirmed',false,'confirmStageZero',true))));")"
  [[ "${result}" == 'accepted' ]] || { echo "0124 contact submit failed: ${result}" >&2; exit 1; }
}
read_sql="SELECT app_private.read_known_source_personal_merge_split_plan_v1(
  '$app_user_id','$workspace_id','$project_id','$generation_id');"
read_plan() {
  run_psql --quiet --tuples-only --no-align --command="BEGIN READ ONLY; ${read_sql} COMMIT;" | sed -n '/^{/p'
}
assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || { echo "0124 ${label}: ${result}" >&2; exit 1; }
}
submit_contact before
before_document="$(read_plan)"
[[ -n "${before_document}" ]] || { echo '0124 READ ONLY returned no plan。' >&2; exit 1; }
old_fingerprint="$(run_psql --tuples-only --no-align --command="
  SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('$generation_id');")"
before_audits="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_data.promotion_target_access_events WHERE workspace_id = '$workspace_id';")"

gate_key="7ekc-gate-$run_token"
ready_key="7ekc-ready-$run_token"
holder_app="7ekc-holder-$run_token"
reader_app="7ekc-reader-$run_token"
mkfifo "${temporary_directory}/holder.fifo"
PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
  <"${temporary_directory}/holder.fifo" >"${temporary_directory}/holder.out" 2>&1 &
holder_pid=$!
exec 3>"${temporary_directory}/holder.fifo"
printf "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('%s',0)); SELECT pg_advisory_lock(hashtextextended('%s',0));\n" \
  "${gate_key}" "${ready_key}" >&3
ready='f'
for _ in $(seq 1 100); do
  ready="$(run_psql --tuples-only --no-align --command="
    SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('$ready_key',0))
      THEN NOT pg_advisory_unlock(hashtextextended('$ready_key',0)) ELSE true END;" | tr -d '[:space:]')"
  [[ "${ready}" == 't' ]] && break
  sleep 0.05
done
[[ "${ready}" == 't' ]] || { echo '0124 holder 未就绪。' >&2; exit 1; }

# The test gate pauses this command after PostgreSQL has acquired its snapshot.
PGAPPNAME="$reader_app" "${psql_base[@]}" --quiet --tuples-only --no-align --command="
  BEGIN READ ONLY;
  SELECT 'transaction|' || current_setting('transaction_read_only') || '|' || current_setting('transaction_isolation');
  WITH snapshot_gate AS MATERIALIZED (SELECT pg_advisory_xact_lock(hashtextextended('$gate_key',0)))
  SELECT app_private.read_known_source_personal_merge_split_plan_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id') FROM snapshot_gate;
  COMMIT;" >"${temporary_directory}/reader.out" 2>&1 &
reader_pid=$!
pair=''
for _ in $(seq 1 300); do
  pair="$(run_psql --tuples-only --no-align --command="
    SELECT waiting.pid || '|' || blocker.pid || '|' || waiting.wait_event
    FROM pg_catalog.pg_stat_activity waiting
    JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiting.pid)) blocked(pid) ON true
    JOIN pg_catalog.pg_stat_activity blocker ON blocker.pid = blocked.pid
    WHERE waiting.application_name = '$reader_app' AND waiting.wait_event_type = 'Lock'
      AND blocker.application_name = '$holder_app';" | tr -d '[:space:]')"
  [[ "${pair}" == *'|'* ]] && break
  sleep 0.05
done
[[ "${pair}" == *'|'* ]] || { echo '0124 未观察到精确 reader/blocker PID。' >&2; exit 1; }
echo "0124 command snapshot: exact reader/blocker PID and lock ${pair}"
assert_true no-reader-row-locks "SELECT NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_locks lock
  JOIN pg_catalog.pg_stat_activity activity ON activity.pid = lock.pid
  WHERE activity.application_name = '$reader_app' AND lock.granted
    AND lock.locktype IN ('relation','tuple') AND lock.mode IN (
      'RowShareLock','RowExclusiveLock','ShareRowExclusiveLock','ExclusiveLock','AccessExclusiveLock'));"

submit_contact after
printf 'COMMIT;\\q\n' >&3
exec 3>&-
wait "${holder_pid}"
holder_pid=''
wait "${reader_pid}"
reader_pid=''
grep -q '^transaction|on|read committed$' "${temporary_directory}/reader.out"
old_document="$(sed -n '/^{/p' "${temporary_directory}/reader.out")"
[[ "${old_document}" == "${before_document}" ]] || { echo '0124 mixed command snapshot。' >&2; exit 1; }
fresh_document="$(read_plan)"
[[ "${fresh_document}" != "${before_document}" ]] || { echo '0124 fresh plan did not see new facts。' >&2; exit 1; }
assert_true fresh-fact-catalog "SELECT
  (plan->>'fact_count')::bigint = jsonb_array_length(plan->'facts')
  AND plan->>'fact_fingerprint' <> '$old_fingerprint'
  AND EXISTS (SELECT 1 FROM jsonb_array_elements(plan->'facts') fact
    WHERE fact->>'source_target_id' = '$first_target'
      AND fact->'metadata' = jsonb_build_array('contact_link','7ekc-$run_token-after',1,'$first_target'))
  FROM (SELECT app_private.read_known_source_personal_merge_split_plan_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id') AS plan) current_plan;"

confirm_request="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
status=0
run_psql --quiet --tuples-only --no-align --command="
  SELECT app_private.end_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id','$confirm_request','$generation_id','$old_fingerprint');" \
  >"${temporary_directory}/confirm.out" 2>&1 || status=$?
if [[ "${status}" -eq 0 ]] || ! grep -q 'ERROR:  23505:' "${temporary_directory}/confirm.out"; then
  echo "0124 stale confirmation expected 23505, exit=${status}" >&2
  sed -n '1,100p' "${temporary_directory}/confirm.out" >&2
  exit 1
fi
assert_true stale-confirmation-zero-change "SELECT
  (SELECT count(*) = 2 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '$generation_id')
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_end_events_v1 WHERE generation_id = '$generation_id')
  AND (SELECT count(*) FROM app_data.promotion_target_access_events WHERE workspace_id = '$workspace_id') = $before_audits;"
fresh_fingerprint="$(run_psql --tuples-only --no-align --command="
  SELECT fact_fingerprint FROM app_private.personal_target_merge_known_source_manifest_v1('$generation_id');")"
run_psql --quiet --command="SELECT app_private.end_known_source_personal_target_merge_generation_v1(
  '$app_user_id','$workspace_id','$project_id','$confirm_request','$generation_id','$fresh_fingerprint');" >/dev/null
assert_true fresh-confirmation "SELECT
  NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE generation_id = '$generation_id')
  AND (SELECT count(*) = 1 FROM app_private.personal_target_merge_end_events_v1
    WHERE generation_id = '$generation_id' AND request_id = '$confirm_request' AND fact_fingerprint = '$fresh_fingerprint');"
echo '0124 concurrency passed: READ ONLY coherent snapshot, fresh complete facts, stale confirmation rejected, fresh confirmation accepted.'
