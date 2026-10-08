#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?请设置 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
command -v "${psql_command}" >/dev/null
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seed_file="${script_dir}/../backend/database/fixtures/shared/organization_purge_finalizer_seed.sql"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=60000 -c lock_timeout=45000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
databases=()
child_pids=()
cleanup() {
  local status=$? pid database
  trap - EXIT
  for pid in "${child_pids[@]}"; do kill -TERM "${pid}" >/dev/null 2>&1 || true; done
  for pid in "${child_pids[@]}"; do wait "${pid}" >/dev/null 2>&1 || true; done
  for database in "${databases[@]}"; do
    if ! "${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 \
      --quiet --command="DROP DATABASE IF EXISTS ${database} WITH (FORCE);"; then status=1; fi
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
  exit "${status}"
}
trap cleanup EXIT

# A committed synthetic database allows genuine outer ROLLBACK, separately
# committed failure state and races. Exact databases are removed even on failure.
source_database="$(run_psql --tuples-only --no-align --command='SELECT current_database();')"
[[ "${source_database}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
seed_database="organization_0109_seed_$$"
databases+=("${seed_database}")
run_psql --quiet --command="CREATE DATABASE ${seed_database} TEMPLATE ${source_database};"
database_url_prefix="${DATABASE_URL%/*}"
seed_url="${database_url_prefix}/${seed_database}"
"${psql_command}" "${seed_url}" --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
  --command='BEGIN;' --file="${seed_file}" --command='COMMIT;' >"${temporary_directory}/seed.out" 2>&1 || {
  sed -n '1,180p' "${temporary_directory}/seed.out" >&2; exit 1;
}

wait_for_lock() {
  local application="$1" child_pid="$2" output="$3" waiting="$4" observed
  for _ in $(seq 1 100); do
    observed="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (SELECT 1 FROM pg_stat_activity a
        WHERE a.application_name='${application}' AND a.datname=current_database()
          AND ${waiting});" | tr -d '[:space:]')"
    [[ "${observed}" == t ]] && return
    if ! kill -0 "${child_pid}" >/dev/null 2>&1; then sed -n '1,140p' "${output}" >&2; exit 1; fi
    sleep 0.05
  done
  sed -n '1,140p' "${output}" >&2
  echo "0109 未观察到 ${application} 的锁状态。" >&2
  exit 1
}

select_roots() {
  workspace="$(run_psql --tuples-only --no-align --command="SELECT workspace_id FROM app_data.workspaces WHERE display_name='0109 enriched organization';")"
  cycle="$(run_psql --tuples-only --no-align --command="SELECT deletion_request_id FROM app_private.organization_deletion_current WHERE organization_workspace_id='${workspace}';")"
  owner="$(run_psql --tuples-only --no-align --command="SELECT app_user_id FROM app_data.external_identities WHERE issuer='https://synthetic-0109.example' AND subject='actor-4';")"
  reader="$(run_psql --tuples-only --no-align --command="SELECT app_user_id FROM app_data.external_identities WHERE issuer='https://synthetic-0109.example' AND subject='actor-1';")"
  target_member="$(run_psql --tuples-only --no-align --command="SELECT organization_membership_id FROM app_data.organization_memberships WHERE organization_workspace_id='${workspace}' AND app_user_id='${reader}' AND inactive_from_utc IS NULL;")"
  snapshot="$(run_psql --tuples-only --no-align --command="SELECT snapshot_id FROM app_private.management_report_snapshots WHERE project_id='00000109-0000-4000-8000-000000000001' AND report_id='contact_sessions_by_channel_two_periods' ORDER BY released_at_utc DESC LIMIT 1;")"
}

future_deadline() {
  run_psql --quiet --command="BEGIN;
    SET LOCAL session_replication_role=replica;
    UPDATE app_private.organization_deletion_current SET effective_at_utc=transaction_timestamp()+interval '3 seconds'-interval '720 hours',
      purge_after_utc=transaction_timestamp()+interval '3 seconds' WHERE organization_workspace_id='${workspace}';
    UPDATE app_private.organization_deletion_request_claims c SET effective_at_utc=a.effective_at_utc,purge_after_utc=a.purge_after_utc
      FROM app_private.organization_deletion_current a WHERE c.request_id=a.deletion_request_id AND a.organization_workspace_id='${workspace}';
    UPDATE app_private.organization_deletion_audit_events e SET occurred_at_utc=a.effective_at_utc
      FROM app_private.organization_deletion_current a WHERE e.request_id=a.deletion_request_id AND a.organization_workspace_id='${workspace}';
    UPDATE app_data.workspaces w SET deleted_at=a.effective_at_utc FROM app_private.organization_deletion_current a
      WHERE w.workspace_id=a.organization_workspace_id AND w.workspace_id='${workspace}';
    COMMIT;"
}

run_race() {
  local label="$1" direction="$2" expected_state="$3" setup="$4"
  local database="organization_0109_${label}_$$" first_sql second_sql first_pid second_pid first_status=0 second_status=0
  local first_output="${temporary_directory}/${label}-first.out" second_output="${temporary_directory}/${label}-second.out"
  databases+=("${database}")
  "${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --quiet \
    --command="CREATE DATABASE ${database} TEMPLATE ${seed_database};"
  psql_base=("${psql_command}" "${database_url_prefix}/${database}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
  select_roots
  if [[ "${setup}" == future ]]; then future_deadline; fi
  if [[ "${setup}" == restored ]]; then
    future_deadline
    run_psql --quiet --command="SELECT * FROM app_private.restore_organization_v1('${owner}',gen_random_uuid(),'${workspace}','${cycle}');" >/dev/null
  fi
  case "${label}" in
    restore_*) second_sql="SELECT * FROM app_private.restore_organization_v1('${owner}',gen_random_uuid(),'${workspace}','${cycle}');" ;;
    governance_*) second_sql="SELECT * FROM app_private.transfer_organization_owner_v1('${owner}',gen_random_uuid(),'${workspace}','${target_member}');" ;;
    replay_*) second_sql="SELECT * FROM app_private.request_organization_deletion_v1('${owner}','${cycle}','${workspace}');" ;;
    read_*) second_sql="SELECT app_private.read_authorized_management_report_snapshot_v1('${reader}','00000109-0000-4000-8000-000000000001','${snapshot}');" ;;
  esac
  first_sql="SELECT * FROM app_private.finalize_organization_purge_v1('${workspace}','${cycle}');"
  if [[ "${direction}" == other_first ]]; then
    local swap_sql="${first_sql}"; first_sql="${second_sql}"; second_sql="${swap_sql}"
  fi
  # The first session's transaction owns production locks; the session ready
  # advisory lock only makes that fact observable without a timing assumption.
  run_psql --quiet --command="SET application_name='0109-${label}-first'; BEGIN; ${first_sql}
    SELECT pg_advisory_lock(hashtextextended('0109-ready:${label}',0)); SELECT pg_sleep(4); COMMIT;" >"${first_output}" 2>&1 &
  first_pid=$!; child_pids+=("${first_pid}")
  wait_for_lock "0109-${label}-first" "${first_pid}" "${first_output}" \
    "EXISTS (SELECT 1 FROM pg_locks l WHERE l.pid=a.pid AND l.locktype='advisory' AND l.granted AND l.objsubid=1
      AND l.classid::bigint=((hashtextextended('0109-ready:${label}',0)>>32)&4294967295)
      AND l.objid::bigint=(hashtextextended('0109-ready:${label}',0)&4294967295))"
  run_psql --quiet --command="SET application_name='0109-${label}-second'; BEGIN; ${second_sql} COMMIT;" >"${second_output}" 2>&1 &
  second_pid=$!; child_pids+=("${second_pid}")
  wait_for_lock "0109-${label}-second" "${second_pid}" "${second_output}" "a.wait_event_type='Lock'"
  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?
  if [[ "${first_status}" -ne 0 ]] \
    || { [[ "${expected_state}" == success ]] && [[ "${second_status}" -ne 0 ]]; } \
    || { [[ "${expected_state}" != success ]] && { [[ "${second_status}" -eq 0 ]] || ! grep -Fq "${expected_state}:" "${second_output}"; }; }; then
    sed -n '1,180p' "${first_output}" "${second_output}" >&2
    echo "0109 ${label} 结果错误。" >&2; exit 1
  fi
  run_psql --quiet --command="DO \$state\$ BEGIN
    IF EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations)
      OR EXISTS (SELECT 1 FROM app_private.organization_deletion_current WHERE status='purging') THEN
      RAISE EXCEPTION '0109 concurrent transient state survived'; END IF;
    IF '${expected_state}'='55000' AND NOT EXISTS (SELECT 1 FROM app_data.workspaces WHERE workspace_id='${workspace}') THEN
      RAISE EXCEPTION '0109 restored/governance organization was purged'; END IF;
    IF '${expected_state}'<>'55000' AND EXISTS (SELECT 1 FROM app_data.workspaces WHERE workspace_id='${workspace}') THEN
      RAISE EXCEPTION '0109 finalizer race left business root'; END IF;
  END \$state\$;"
  echo "0109 ${label}：锁等待及提交后重验通过。"
}

run_race restore_first other_first 55000 future
run_race restore_after purge_first 42501 expired
run_race governance_first other_first 55000 restored
run_race governance_after purge_first 42501 expired
run_race replay_first other_first success future
run_race replay_after purge_first 22023 expired
run_race read_first other_first success future
run_race read_after purge_first 42501 expired

# Independent full transaction failure, explicit outer ROLLBACK, then a NEW
# transaction records the minimum failure state. Retry has ordinary triggers.
psql_base=("${psql_command}" "${seed_url}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
select_roots
run_psql --quiet --command="
  CREATE TABLE public.fixture_0109_before(relation_name text,row_data jsonb);
  DO \$snapshot\$ DECLARE relation_name text; BEGIN
    FOR relation_name IN SELECT format('%I.%I',n.nspname,c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' LOOP
      EXECUTE format('INSERT INTO public.fixture_0109_before SELECT %L,to_jsonb(t) FROM %s t',relation_name,relation_name);
    END LOOP; END \$snapshot\$;
  CREATE FUNCTION public.fixture_0109_delete_failure() RETURNS trigger LANGUAGE plpgsql AS \$guard\$
    BEGIN IF OLD.workspace_id='${workspace}'::uuid THEN RAISE EXCEPTION '0109 injected outer transaction failure'; END IF; RETURN OLD; END \$guard\$;
  CREATE TRIGGER fixture_0109_delete_failure AFTER DELETE ON app_data.workspaces FOR EACH ROW EXECUTE FUNCTION public.fixture_0109_delete_failure();"
cat >"${temporary_directory}/outer-failure.sql" <<SQL
\set ON_ERROR_STOP off
BEGIN;
SELECT * FROM app_private.finalize_organization_purge_v1('${workspace}','${cycle}');
ROLLBACK;
\set ON_ERROR_STOP on
DO \$unchanged\$
DECLARE checked_relation text; actual_rows jsonb; expected_rows jsonb;
BEGIN
  FOR checked_relation IN SELECT DISTINCT relation_name FROM public.fixture_0109_before LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %s t',checked_relation) INTO actual_rows;
    SELECT coalesce(jsonb_agg(row_data ORDER BY row_data::text),'[]'::jsonb) INTO expected_rows FROM public.fixture_0109_before WHERE relation_name=checked_relation;
    IF actual_rows IS DISTINCT FROM expected_rows THEN RAISE EXCEPTION '0109 outer rollback changed %',checked_relation; END IF;
  END LOOP;
END \$unchanged\$;
BEGIN;
DO \$failure\$ BEGIN
  IF NOT app_private.record_organization_purge_failed_v1('${workspace}','${cycle}') THEN RAISE EXCEPTION '0109 valid separate failure marker refused'; END IF;
END \$failure\$;
COMMIT;
DO \$minimum\$ DECLARE saved jsonb; actual jsonb; checked_relation text; actual_rows jsonb; expected_rows jsonb; BEGIN
  SELECT row_data INTO STRICT saved FROM public.fixture_0109_before WHERE relation_name='app_private.organization_deletion_current' AND row_data->>'organization_workspace_id'='${workspace}';
  SELECT to_jsonb(a) INTO STRICT actual FROM app_private.organization_deletion_current a WHERE organization_workspace_id='${workspace}';
  IF actual-'status' IS DISTINCT FROM saved-'status' OR actual->>'status'<>'purge_failed'
    OR EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations)
    OR EXISTS (SELECT 1 FROM app_private.organization_purge_request_tombstones WHERE request_uuid='${cycle}') THEN
    RAISE EXCEPTION '0109 independent failure marker stored more than minimal state'; END IF;
  FOR checked_relation IN SELECT format('%I.%I',n.nspname,c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('app_data','app_private') AND c.relkind='r' LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %s t',checked_relation) INTO actual_rows;
    SELECT coalesce(jsonb_agg(CASE WHEN relation_name='app_private.organization_deletion_current' AND row_data->>'organization_workspace_id'='${workspace}'
      THEN jsonb_set(row_data,'{status}','"purge_failed"'::jsonb) ELSE row_data END ORDER BY (CASE WHEN relation_name='app_private.organization_deletion_current' AND row_data->>'organization_workspace_id'='${workspace}'
      THEN jsonb_set(row_data,'{status}','"purge_failed"'::jsonb) ELSE row_data END)::text),'[]'::jsonb) INTO expected_rows
      FROM public.fixture_0109_before WHERE relation_name=checked_relation;
    IF actual_rows IS DISTINCT FROM expected_rows THEN RAISE EXCEPTION '0109 failure marker changed business/ledger row in %',checked_relation; END IF;
  END LOOP;
END \$minimum\$;
DROP TRIGGER fixture_0109_delete_failure ON app_data.workspaces;
BEGIN;
SELECT * FROM app_private.finalize_organization_purge_v1('${workspace}','${cycle}');
COMMIT;
SQL
run_psql --quiet --file="${temporary_directory}/outer-failure.sql" >"${temporary_directory}/outer-failure.out" 2>&1 || {
  sed -n '1,200p' "${temporary_directory}/outer-failure.out" >&2; exit 1;
}
grep -Fq 'P0001: 0109 injected outer transaction failure' "${temporary_directory}/outer-failure.out"
run_psql --quiet --command="DO \$complete\$ BEGIN
  IF EXISTS (SELECT 1 FROM app_data.workspaces WHERE workspace_id='${workspace}')
    OR EXISTS (SELECT 1 FROM app_private.organization_deletion_current WHERE organization_workspace_id='${workspace}')
    OR EXISTS (SELECT 1 FROM app_private.organization_purge_delete_authorizations)
    OR NOT EXISTS (SELECT 1 FROM app_private.organization_purge_request_tombstones WHERE claim_family='organization-deletion-request' AND request_uuid='${cycle}') THEN
    RAISE EXCEPTION '0109 failed retry did not complete'; END IF;
END \$complete\$;"
echo '0109 outer ROLLBACK→independent purge_failed→retry completion：通过。'
