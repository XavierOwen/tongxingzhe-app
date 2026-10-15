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
trigger_installed=0
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${holder_pid}" "${reader_pid}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  if [[ "${trigger_installed}" -eq 1 ]]; then
    run_psql --quiet --command='DROP TRIGGER fixture_0126_snapshot_gate ON app_data.promotion_target_access_events;
      DROP FUNCTION public.fixture_0126_snapshot_gate();' >/dev/null
  fi
  rm -f "${temporary_directory}/holder.fifo" "${temporary_directory}/holder.out" \
    "${temporary_directory}/reader.out" "${temporary_directory}/writer.out" "${temporary_directory}/fresh.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT
assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || { echo "0126 ${label} invariant failed: ${result}" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7enc-directory.example.test/auth/v1'
subject="7enc-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id <<<"${context}"
for context_id in "$app_user_id" "$workspace_id" "$project_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0126 无法取得 personal context。' >&2; exit 1; }
done
first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
  FROM app_data.create_promotion_target('$app_user_id','$workspace_id','$project_id',
    'person','0126 first $run_token','+1 312 555 0126',NULL,'7enc-$run_token-first');")"
second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
  FROM app_data.create_promotion_target('$app_user_id','$workspace_id','$project_id',
    'person','0126 second $run_token','+1 312 555 0126',NULL,'7enc-$run_token-second');")"
preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id
  FROM app_data.preview_personal_target_pair_v1('$issuer','$subject','$project_id','$first_target','$second_target');")"
generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
  '$app_user_id','$project_id',gen_random_uuid(),'$preview_id',
  '$first_target','$first_target','$first_target','$second_target');")"
for fixture_id in "$first_target" "$second_target" "$generation_id"; do
  [[ "$fixture_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0126 无法建立 generation。' >&2; exit 1; }
done
read_sql="SELECT app_data.read_personal_merge_directory_v1('$issuer','$subject','$project_id',NULL);"
expected_directory() {
  run_psql --tuples-only --no-align --command="SELECT jsonb_build_object(
    'workspace_id','$workspace_id'::uuid,'project_id','$project_id'::uuid,
    'items',jsonb_build_array(jsonb_build_object(
      'generation_id','$generation_id'::uuid,'target_type','person','retained_target_id','$first_target'::uuid,
      'member_target_ids',(SELECT jsonb_agg(target_id ORDER BY target_id) FROM
        (VALUES ('$first_target'::uuid),('$second_target'::uuid)) member(target_id)),
      'review_due_at_utc',to_char(least(
        app_data.promotion_target_review_due_at('$first_target'),
        app_data.promotion_target_review_due_at('$second_target')) AT TIME ZONE 'UTC',
        'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))),'next_cursor',NULL);"
}
audit_count() {
  run_psql --tuples-only --no-align --command="SELECT count(*) FROM app_data.promotion_target_access_events
    WHERE workspace_id = '$workspace_id';" | tr -d '[:space:]'
}
# Pause only this synthetic reader's first audit, after the directory page is materialized.
run_psql --quiet <<'SQL'
CREATE FUNCTION public.fixture_0126_snapshot_gate() RETURNS trigger
LANGUAGE plpgsql AS $body$
BEGIN
  IF current_setting('application_name') LIKE '7enc-reader-%' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(current_setting('application_name'),0));
  END IF;
  RETURN NEW;
END
$body$;
CREATE TRIGGER fixture_0126_snapshot_gate BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION public.fixture_0126_snapshot_gate();
SQL
trigger_installed=1
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name, coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname || '.' || tablename,schemaname,tablename), ' UNION ALL ' ORDER BY schemaname,tablename) || ') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private')
    AND NOT (schemaname = 'app_data' AND tablename = 'promotion_target_access_events');")"
business_state() { run_psql --tuples-only --no-align --command="${state_query}"; }
wait_for_holder() {
  local key="$1" ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('$key',0))
        THEN NOT pg_advisory_unlock(hashtextextended('$key',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == 't' ]] && return
    sleep 0.05
  done
  echo '0126 holder 未就绪。' >&2
  exit 1
}
wait_for_exact_blocker() {
  local reader_app="$1" holder_app="$2" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT reader.pid || '|' || holder.pid || '|' || reader.wait_event
      FROM pg_catalog.pg_stat_activity reader
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(reader.pid)) blocked(pid) ON true
      JOIN pg_catalog.pg_stat_activity holder ON holder.pid = blocked.pid
      WHERE reader.application_name = '$reader_app' AND holder.application_name = '$holder_app'
        AND reader.wait_event_type = 'Lock';" | tr -d '[:space:]')"
    if [[ "$pair" == *'|'* ]]; then echo "0126 ${reader_app}: exact reader/holder PID and lock ${pair}"; return; fi
    sleep 0.05
  done
  echo '0126 未观察到精确 audit gate blocker。' >&2
  sed -n '1,100p' "${temporary_directory}/reader.out" >&2
  exit 1
}
run_snapshot_race() {
  local label="$1" writer_sql="$2" reader_app holder_app ready_key after_writer_state before_audits first_views second_views status=0
  reader_app="7enc-reader-$label-$run_token"
  holder_app="7enc-holder-$label-$run_token"
  ready_key="7enc-ready-$label-$run_token"
  before_document="$(expected_directory)"
  mkfifo "${temporary_directory}/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet <"${temporary_directory}/holder.fifo" \
    >"${temporary_directory}/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"${temporary_directory}/holder.fifo"
  printf "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('%s',0)); SELECT pg_advisory_lock(hashtextextended('%s',0));\n" \
    "$reader_app" "$ready_key" >&3
  wait_for_holder "$ready_key"
  PGAPPNAME="$reader_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="SET ROLE tongxingzhe_runtime; ${read_sql}" >"${temporary_directory}/reader.out" 2>&1 &
  reader_pid=$!
  wait_for_exact_blocker "$reader_app" "$holder_app"
  run_psql --quiet --command="BEGIN; ${writer_sql} COMMIT;" >"${temporary_directory}/writer.out" 2>&1
  wait_for_exact_blocker "$reader_app" "$holder_app"
  after_writer_state="$(business_state)"
  before_audits="$(audit_count)"
  first_views="$(run_psql --tuples-only --no-align --command="SELECT count(*) FROM app_data.promotion_target_access_events
    WHERE workspace_id = '$workspace_id' AND promotion_target_id = '$first_target' AND action = 'viewed';")"
  second_views="$(run_psql --tuples-only --no-align --command="SELECT count(*) FROM app_data.promotion_target_access_events
    WHERE workspace_id = '$workspace_id' AND promotion_target_id = '$second_target' AND action = 'viewed';")"
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "$holder_pid"
  holder_pid=''
  rm -f "${temporary_directory}/holder.fifo"
  wait "$reader_pid" || status=$?
  reader_pid=''
  if [[ "$status" -ne 0 ]]; then sed -n '1,100p' "${temporary_directory}/reader.out" >&2; exit 1; fi
  [[ "$(sed -n '/^{/p' "${temporary_directory}/reader.out")" == "$before_document" ]] \
    || { echo "0126 ${label} mixed directory snapshot。" >&2; exit 1; }
  [[ "$after_writer_state" == "$(business_state)" && "$(audit_count)" -eq $((before_audits + 2)) ]] \
    || { echo "0126 ${label} non-access write or audit count drift。" >&2; exit 1; }
  assert_true "$label-member-audits" "SELECT count(*) = $first_views + $second_views + 2
    AND count(*) FILTER (WHERE promotion_target_id = '$first_target') = $first_views + 1
    AND count(*) FILTER (WHERE promotion_target_id = '$second_target') = $second_views + 1
    AND bool_and(actor_app_user_id = '$app_user_id')
    FROM app_data.promotion_target_access_events WHERE workspace_id = '$workspace_id'
      AND promotion_target_id IN ('$first_target','$second_target') AND action = 'viewed';"
}

run_snapshot_race assignment "UPDATE app_data.promotion_target_assignments
  SET ended_at = clock_timestamp(), end_reason = 'synthetic concurrency revocation'
  WHERE promotion_target_id = '$first_target' AND app_user_id = '$app_user_id' AND ended_at IS NULL;"
before_state="$(business_state)"
before_audits="$(audit_count)"
fresh_document="$(run_psql --quiet --tuples-only --no-align --command="SET ROLE tongxingzhe_runtime; ${read_sql}")"
empty_document="$(run_psql --tuples-only --no-align --command="SELECT jsonb_build_object(
  'workspace_id','$workspace_id'::uuid,'project_id','$project_id'::uuid,'items','[]'::jsonb,'next_cursor',NULL);")"
[[ "$fresh_document" == "$empty_document" && "$before_state" == "$(business_state)" && "$before_audits" == "$(audit_count)" ]] \
  || { echo '0126 fresh directory did not omit the revoked assignment without writes。' >&2; exit 1; }
run_psql --quiet --command="UPDATE app_data.promotion_target_assignments
  SET ended_at = NULL, end_reason = NULL WHERE promotion_target_id = '$first_target' AND app_user_id = '$app_user_id';"

run_snapshot_race actor "UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = '$app_user_id';"
before_state="$(business_state)"
before_audits="$(audit_count)"
status=0
run_psql --quiet --command="SET ROLE tongxingzhe_runtime; ${read_sql}" >"${temporary_directory}/fresh.out" 2>&1 || status=$?
if [[ "$status" -eq 0 ]] || ! grep -q 'ERROR:  42501:' "${temporary_directory}/fresh.out"; then
  echo '0126 fresh directory 未稳定拒绝已撤权 actor。' >&2
  sed -n '1,100p' "${temporary_directory}/fresh.out" >&2
  exit 1
fi
[[ "$before_state" == "$(business_state)" && "$before_audits" == "$(audit_count)" ]] \
  || { echo '0126 被拒绝的目录读取留下写入。' >&2; exit 1; }
run_psql --quiet --command="UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = '$app_user_id';"
echo '0126 concurrency passed: exact audit-gate PIDs, coherent one-item directory across assignment/actor commits, two member audits, fresh empty/rejection, no non-access read writes.'
