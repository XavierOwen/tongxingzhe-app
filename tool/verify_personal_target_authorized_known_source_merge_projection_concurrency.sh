#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
child_pids=()
holder_pid=''
reader_pid=''
trigger_installed=0
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  if [[ "${trigger_installed}" -eq 1 ]]; then
    run_psql --quiet --command='DROP TRIGGER fixture_0122_snapshot_gate ON app_data.promotion_target_access_events;
      DROP FUNCTION public.fixture_0122_snapshot_gate();' >/dev/null
  fi
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT
new_uuid() { run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();' | tr -d '[:space:]'; }
assert_true() {
  local label="$1" statement="$2" result
  result="$(run_psql --tuples-only --no-align --command="${statement}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || { echo "0122 ${label} invariant failed: ${result}" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7ehc-authorized-projection.example.test/auth/v1'
subject="7ehc-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}','${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id FROM app_data.list_personal_project_contexts(
    '${issuer}','${subject}') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id <<<"${context}"
for context_id in "${app_user_id}" "${workspace_id}" "${project_id}"; do
  [[ "${context_id}" =~ ^[0-9a-f-]{36}$ ]] || { echo '0122 未取得个人上下文。' >&2; exit 1; }
done

# Pause only the synthetic reader's first audit, after its projection is ready.
run_psql --quiet <<'SQL'
CREATE FUNCTION public.fixture_0122_snapshot_gate() RETURNS trigger
LANGUAGE plpgsql AS $body$
BEGIN
  IF current_setting('application_name') LIKE '7ehc-reader-%' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(current_setting('application_name'),0));
  END IF;
  RETURN NEW;
END
$body$;
CREATE TRIGGER fixture_0122_snapshot_gate BEFORE INSERT ON app_data.promotion_target_access_events
FOR EACH ROW EXECUTE FUNCTION public.fixture_0122_snapshot_gate();
SQL
trigger_installed=1

state_query="$(run_psql --tuples-only --no-align --command="
  SELECT 'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name, coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), ''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname || '.' || tablename,schemaname,tablename), ' UNION ALL ' ORDER BY schemaname,tablename) || ') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private')
    AND NOT (schemaname = 'app_data' AND tablename = 'promotion_target_access_events');")"
business_state() { run_psql --tuples-only --no-align --command="${state_query}"; }
audit_count() {
  run_psql --tuples-only --no-align --command="SELECT count(*) FROM app_data.promotion_target_access_events
    WHERE workspace_id = '${workspace_id}';" | tr -d '[:space:]'
}
read_sql() {
  printf "SELECT app_private.read_authorized_known_source_personal_merge_projection_v1('%s','%s','%s','%s');" \
    "${issuer}" "${subject}" "${project_id}" "${generation_id}"
}
direct_document() {
  run_psql --tuples-only --no-align --command="SELECT app_private.read_known_source_personal_target_merge_projection_v1(
    '${app_user_id}','${workspace_id}','${project_id}','${generation_id}');"
}
create_pair() {
  local label="$1" preview_id
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('${app_user_id}','${workspace_id}','${project_id}',
      'person','0122 ${label} first ${run_token}','+1 773 555 0122',NULL,'7ehc-${run_token}-${label}-a');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('${app_user_id}','${workspace_id}','${project_id}',
      'person','0122 ${label} second ${run_token}','+1 773 555 0122',NULL,'7ehc-${run_token}-${label}-b');")"
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
    '${issuer}','${subject}','${project_id}','${first_target}','${second_target}');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '${app_user_id}','${project_id}','$(new_uuid)','${preview_id}',
    '${first_target}','${first_target}','${second_target}','${first_target}');")"
  [[ "${generation_id}" =~ ^[0-9a-f-]{36}$ ]] || { echo '0122 未取得已激活代次。' >&2; exit 1; }
  before_document="$(direct_document)"
}
wait_for_holder() {
  local key="$1" ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('${key}',0))
        THEN NOT pg_advisory_unlock(hashtextextended('${key}',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "${ready}" == 't' ]] && return
    sleep 0.05
  done
  echo '0122 holder 未就绪。' >&2
  exit 1
}
wait_for_exact_blocker() {
  local reader_app="$1" holder_app="$2" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT reader.pid || '|' || holder.pid || '|' || reader.wait_event
      FROM pg_catalog.pg_stat_activity reader
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(reader.pid)) blocked(pid) ON true
      JOIN pg_catalog.pg_stat_activity holder ON holder.pid = blocked.pid
      WHERE reader.application_name = '${reader_app}' AND holder.application_name = '${holder_app}'
        AND reader.wait_event_type = 'Lock';" | tr -d '[:space:]')"
    if [[ "${pair}" == *'|'* ]]; then
      echo "${reader_app}: exact reader/holder PID and lock ${pair}"
      return
    fi
    sleep 0.05
  done
  echo '0122 未观察到精确 audit gate blocker。' >&2
  sed -n '1,100p' "${temporary_directory}/reader.out" >&2
  exit 1
}
run_snapshot_race() {
  local label="$1" writer_sql="$2" reader_app holder_app ready_key after_writer_state before_audits first_audits second_audits status=0 old_document
  reader_app="7ehc-reader-${label}-${run_token}"
  holder_app="7ehc-holder-${label}-${run_token}"
  ready_key="7ehc-ready-${label}-${run_token}"
  mkfifo "${temporary_directory}/holder.fifo"
  PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet <"${temporary_directory}/holder.fifo" \
    >"${temporary_directory}/holder.out" 2>&1 &
  holder_pid=$!
  child_pids+=("${holder_pid}")
  exec 3>"${temporary_directory}/holder.fifo"
  printf "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('%s',0)); SELECT pg_advisory_lock(hashtextextended('%s',0));\n" \
    "${reader_app}" "${ready_key}" >&3
  wait_for_holder "${ready_key}"
  PGAPPNAME="${reader_app}" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="$(read_sql)" >"${temporary_directory}/reader.out" 2>&1 &
  reader_pid=$!
  child_pids+=("${reader_pid}")
  wait_for_exact_blocker "${reader_app}" "${holder_app}"
  run_psql --quiet --command="BEGIN; ${writer_sql} COMMIT;" >"${temporary_directory}/writer.out" 2>&1
  wait_for_exact_blocker "${reader_app}" "${holder_app}"
  after_writer_state="$(business_state)"
  before_audits="$(audit_count)"
  first_audits="$(run_psql --tuples-only --no-align --command="SELECT count(*) FROM app_data.promotion_target_access_events
    WHERE promotion_target_id = '${first_target}' AND action = 'viewed';")"
  second_audits="$(run_psql --tuples-only --no-align --command="SELECT count(*) FROM app_data.promotion_target_access_events
    WHERE promotion_target_id = '${second_target}' AND action = 'viewed';")"
  printf 'COMMIT;\\q\n' >&3
  exec 3>&-
  wait "${holder_pid}"
  holder_pid=''
  rm -f "${temporary_directory}/holder.fifo"
  wait "${reader_pid}" || status=$?
  reader_pid=''
  if [[ "${status}" -ne 0 ]]; then
    sed -n '1,100p' "${temporary_directory}/reader.out" >&2
    exit 1
  fi
  old_document="$(sed -n '/^{/p' "${temporary_directory}/reader.out")"
  [[ "${old_document}" == "${before_document}" ]] || { echo "0122 ${label} mixed projection snapshot。" >&2; exit 1; }
  [[ "${after_writer_state}" == "$(business_state)" ]] || { echo "0122 ${label} changed non-access state。" >&2; exit 1; }
  [[ "$(audit_count)" -eq $((before_audits + 2)) ]] || { echo '0122 成功读取没有恰好两条查看审计。' >&2; exit 1; }
  assert_true "${label}-source-audits" "SELECT count(*) = ${first_audits} + ${second_audits} + 2
    AND count(*) FILTER (WHERE promotion_target_id = '${first_target}') = ${first_audits} + 1
    AND count(*) FILTER (WHERE promotion_target_id = '${second_target}') = ${second_audits} + 1
    AND bool_and(actor_app_user_id = '${app_user_id}' AND action = 'viewed')
    FROM app_data.promotion_target_access_events WHERE workspace_id = '${workspace_id}'
      AND promotion_target_id IN ('${first_target}','${second_target}') AND action = 'viewed';"
}
expect_fresh_forbidden() {
  local before_state before_audits status=0
  before_state="$(business_state)"
  before_audits="$(audit_count)"
  run_psql --quiet --command="$(read_sql)" >"${temporary_directory}/fresh.out" 2>&1 || status=$?
  if [[ "${status}" -eq 0 ]] || ! grep -q 'ERROR:  42501:' "${temporary_directory}/fresh.out"; then
    echo '0122 fresh read 未稳定拒绝已失效授权或代次。' >&2
    sed -n '1,100p' "${temporary_directory}/fresh.out" >&2
    exit 1
  fi
  [[ "${before_state}" == "$(business_state)" && "${before_audits}" == "$(audit_count)" ]] \
    || { echo '0122 被拒绝的读取留下写入。' >&2; exit 1; }
}

create_pair identity
run_snapshot_race identity "UPDATE app_data.external_identities SET subject = '${subject}-moved'
  WHERE issuer = '${issuer}' AND subject = '${subject}';"
expect_fresh_forbidden
run_psql --quiet --command="UPDATE app_data.external_identities SET subject = '${subject}'
  WHERE issuer = '${issuer}' AND subject = '${subject}-moved';" >/dev/null

create_pair actor
run_snapshot_race actor "UPDATE app_data.app_users SET status = 'deletion_pending' WHERE app_user_id = '${app_user_id}';"
expect_fresh_forbidden
run_psql --quiet --command="UPDATE app_data.app_users SET status = 'active' WHERE app_user_id = '${app_user_id}';" >/dev/null

create_pair current-project
other_project_id="$(new_uuid)"
run_psql --quiet --command="INSERT INTO app_data.projects(project_id,workspace_id,display_name)
  VALUES ('${other_project_id}','${workspace_id}','0122 next project');" >/dev/null
run_snapshot_race current-project "UPDATE app_data.user_current_projects SET project_id = '${other_project_id}'
  WHERE app_user_id = '${app_user_id}';"
expect_fresh_forbidden
run_psql --quiet --command="UPDATE app_data.user_current_projects SET project_id = '${project_id}'
  WHERE app_user_id = '${app_user_id}';" >/dev/null

create_pair facts
run_snapshot_race facts "UPDATE app_data.promotion_targets SET phone = NULL WHERE promotion_target_id = '${second_target}';"
fresh_document="$(run_psql --tuples-only --no-align --command="$(read_sql)")"
[[ "${fresh_document}" == "$(direct_document)" && "${fresh_document}" != "${before_document}" ]] \
  || { echo '0122 fresh facts 没有返回新的完整投影。' >&2; exit 1; }

create_pair end
fingerprint="$(run_psql --tuples-only --no-align --command="SELECT fact_fingerprint
  FROM app_private.personal_target_merge_known_source_manifest_v1('${generation_id}');")"
run_snapshot_race end "SELECT app_private.end_known_source_personal_target_merge_generation_v1(
  '${app_user_id}','${workspace_id}','${project_id}','$(new_uuid)','${generation_id}','${fingerprint}');"
expect_fresh_forbidden

create_pair expiry
run_snapshot_race expiry "UPDATE app_data.promotion_targets SET created_at = clock_timestamp() - interval '13 months'
  WHERE promotion_target_id = '${first_target}'; SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
  '${app_user_id}','${workspace_id}','${project_id}','$(new_uuid)','${generation_id}');"
expect_fresh_forbidden

echo '0122 concurrency passed: coherent authorized projection across identity/context/facts/end/expiry commits, atomic source audits, fresh rejection, and no non-access read writes.'
