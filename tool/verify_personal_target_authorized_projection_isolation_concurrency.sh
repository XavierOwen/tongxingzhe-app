#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 clone synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
reader_pid=''
cleanup() {
  exec 3>&- 2>/dev/null || true
  if [[ -n "${reader_pid}" ]] && kill -0 "${reader_pid}" >/dev/null 2>&1; then
    kill "${reader_pid}" >/dev/null 2>&1 || true
    wait "${reader_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

baseline_mode="${PERSONAL_TARGET_PROJECTION_EXPECT_BASELINE:-0}"
latest_version="$(run_psql --tuples-only --no-align --command='SELECT max(version) FROM app_migrations.schema_migrations;' | tr -d '[:space:]')"
if [[ "${baseline_mode}" == '1' && "${latest_version}" != '0150_personal_merge_unassigned_contact_stage_isolation' ]]; then
  echo "RED mode requires official 0150 baseline, found ${latest_version}." >&2
  exit 1
fi

run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer="https://0151-authorized-projection-${run_token}.example.test/auth/v1"
subject="owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}','${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id,workspace_id,project_id FROM app_data.list_personal_project_contexts('${issuer}','${subject}') WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id <<<"${context}"
for context_id in "${app_user_id}" "${workspace_id}" "${project_id}"; do
  [[ "${context_id}" =~ ^[0-9a-f-]{36}$ ]] || { echo '0151 failed to create original personal context.' >&2; exit 1; }
done

# The supported context API creates and selects a second project; select the original again.
other_project_id="$(run_psql --tuples-only --no-align --command="
  SELECT project_id FROM app_data.create_personal_project_context('${issuer}','${subject}','0151 alternate project');
" | tr -d '[:space:]')"
[[ "${other_project_id}" =~ ^[0-9a-f-]{36}$ && "${other_project_id}" != "${project_id}" ]] \
  || { echo '0151 failed to create an alternate project.' >&2; exit 1; }
run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('${issuer}','${subject}','${project_id}');" >/dev/null

first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
  FROM app_data.create_promotion_target('${app_user_id}','${workspace_id}','${project_id}',
    'person','0151 projection first ${run_token}','+1 312 555 0151','projection-${run_token}@example.test','0151-${run_token}-first');")"
second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
  FROM app_data.create_promotion_target('${app_user_id}','${workspace_id}','${project_id}',
    'person','0151 projection second ${run_token}','+1 312 555 0151','projection-${run_token}@example.test','0151-${run_token}-second');")"
preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id
  FROM app_data.preview_personal_target_pair_v1('${issuer}','${subject}','${project_id}','${first_target}','${second_target}');")"
generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
  '${app_user_id}','${project_id}',gen_random_uuid(),'${preview_id}',
  '${first_target}','${second_target}','${first_target}','${first_target}');")"
for fixture_id in "${first_target}" "${second_target}" "${preview_id}" "${generation_id}"; do
  [[ "${fixture_id}" =~ ^[0-9a-f-]{36}$ ]] || { echo '0151 failed to activate a real two-source generation.' >&2; exit 1; }
done

read_sql="SELECT app_data.read_personal_known_source_merge_projection_v1('${issuer}','${subject}','${project_id}','${generation_id}');"
runtime_read_sql="SET ROLE tongxingzhe_runtime; ${read_sql}"
expected_document="$(run_psql --tuples-only --no-align --command="SELECT app_private.read_known_source_personal_target_merge_projection_v1(
  '${app_user_id}','${workspace_id}','${project_id}','${generation_id}');")"
expected_sources="$(run_psql --tuples-only --no-align --command="SELECT jsonb_array_length('${expected_document}'::jsonb->'sources');" | tr -d '[:space:]')"
[[ "${expected_sources}" == '2' ]] || { echo '0151 synthetic projection does not contain both sources.' >&2; exit 1; }

snapshot_definition="$(cat "$(dirname "${BASH_SOURCE[0]}")/../backend/database/fixtures/shared/database_state.sql")"
full_state() {
  run_psql --quiet --tuples-only --no-align --command="${snapshot_definition} SELECT pg_temp.fixture_database_state();" | tail -n 1
}
business_state() {
  run_psql --quiet --tuples-only --no-align --command="${snapshot_definition}
    SELECT pg_temp.fixture_database_state() - 'app_data.promotion_target_access_events';" | tail -n 1
}
workspace_audit_state() {
  run_psql --tuples-only --no-align --command="SELECT coalesce(jsonb_agg(to_jsonb(event) ORDER BY event.event_id),'[]'::jsonb)
    FROM app_data.promotion_target_access_events event WHERE event.workspace_id='${workspace_id}'::uuid;" | tail -n 1
}
assert_only_two_source_views() {
  local before="$1" after="$2" label="$3" result
  result="$(run_psql --tuples-only --no-align --command="
    WITH snapshots AS (SELECT '${before}'::jsonb AS before_events,'${after}'::jsonb AS after_events),
    added AS (
      SELECT event.value FROM snapshots s CROSS JOIN LATERAL jsonb_array_elements(s.after_events) event(value)
      WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(s.before_events) old(value)
        WHERE old.value->'event_id'=event.value->'event_id')
    )
    SELECT s.after_events @> s.before_events
      AND (SELECT count(*) FROM added)=2
      AND (SELECT count(*) FILTER (WHERE value->>'promotion_target_id'='${first_target}') FROM added)=1
      AND (SELECT count(*) FILTER (WHERE value->>'promotion_target_id'='${second_target}') FROM added)=1
      AND (SELECT bool_and(value->>'workspace_id'='${workspace_id}'
        AND value->>'actor_app_user_id'='${app_user_id}' AND value->>'action'='viewed'
        AND (SELECT count(*) FROM jsonb_object_keys(value))=6) FROM added)
    FROM snapshots s;" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || { echo "0151 ${label} changed or added access rows beyond the two source views." >&2; exit 1; }
}

# A normal READ COMMITTED runtime read returns both sources and writes exactly two audits.
before_state="$(business_state)"
before_audits="$(workspace_audit_state)"
rc_document="$(run_psql --tuples-only --no-align --command="${runtime_read_sql}" | tail -n 1)"
[[ "${rc_document}" == "${expected_document}" ]] || {
  echo '0151 READ COMMITTED runtime read changed the two-source document.' >&2
  printf 'expected: %s\nactual: %s\n' "${expected_document}" "${rc_document}" >&2
  exit 1
}
[[ "${before_state}" == "$(business_state)" ]] || { echo '0151 READ COMMITTED read changed non-access business state.' >&2; exit 1; }
assert_only_two_source_views "${before_audits}" "$(workspace_audit_state)" 'READ COMMITTED read'

expect_isolation_rejection() {
  local isolation="$1" before status=0 error_line
  before="$(full_state)"
  run_psql --quiet --command="BEGIN ISOLATION LEVEL ${isolation}; ${runtime_read_sql} COMMIT;" \
    >"${temporary_directory}/isolation.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/p' "${temporary_directory}/isolation.out" | head -n 1)"
  if [[ "${status}" -eq 0 || "${error_line}" != 'ERROR:  0A000: authorized personal target merge projection requires read committed' ]]; then
    echo "0151 ${isolation} projection expected exact 0A000, status ${status}: ${error_line}" >&2
    sed -n '/^ERROR:/p' "${temporary_directory}/isolation.out" >&2
    exit 1
  fi
  [[ "${before}" == "$(full_state)" ]] \
    || { echo "0151 rejected ${isolation} projection changed business state or access audits." >&2; exit 1; }
}

if [[ "${baseline_mode}" != '1' ]]; then
  for isolation in 'READ UNCOMMITTED' 'REPEATABLE READ' SERIALIZABLE; do
    expect_isolation_rejection "${isolation}"
  done
  # Shape validation remains first, even in an unsupported transaction mode.
  invalid_before="$(full_state)"
  invalid_status=0
  run_psql --quiet --command="BEGIN ISOLATION LEVEL REPEATABLE READ; SET ROLE tongxingzhe_runtime;
    SELECT app_data.read_personal_known_source_merge_projection_v1('', '${subject}', '${project_id}', '${generation_id}'); COMMIT;" \
    >"${temporary_directory}/invalid-shape.out" 2>&1 || invalid_status=$?
  if [[ "${invalid_status}" -eq 0 ]] || ! grep -q 'ERROR:  22023:' "${temporary_directory}/invalid-shape.out"; then
    echo '0151 malformed request must be validated before the isolation guard.' >&2
    sed -n '/^ERROR:/p' "${temporary_directory}/invalid-shape.out" >&2
    exit 1
  fi
  [[ "${invalid_before}" == "$(full_state)" ]] \
    || { echo '0151 invalid-shape rejection changed business state or access audits.' >&2; exit 1; }
fi

# Establish the pre-switch RR snapshot, then switch projects through the normal API.
mkfifo "${temporary_directory}/reader.fifo"
"${psql_base[@]}" --quiet --tuples-only --no-align <"${temporary_directory}/reader.fifo" \
  >"${temporary_directory}/reader.out" 2>&1 &
reader_pid=$!
exec 3>"${temporary_directory}/reader.fifo"
printf '%s\n%s\n' \
  "BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT 'SNAPSHOT|' || project_id FROM app_data.user_current_projects WHERE app_user_id='${app_user_id}'::uuid;" \
  '\echo SNAPSHOT_READY' >&3
for _ in $(seq 1 200); do
  grep -q '^SNAPSHOT_READY$' "${temporary_directory}/reader.out" && break
  sleep 0.05
done
if ! grep -q '^SNAPSHOT_READY$' "${temporary_directory}/reader.out" \
  || ! grep -q "^SNAPSHOT|${project_id}$" "${temporary_directory}/reader.out"; then
  echo '0151 failed to establish the original-project RR snapshot.' >&2
  sed -n '1,80p' "${temporary_directory}/reader.out" >&2
  exit 1
fi
run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('${issuer}','${subject}','${other_project_id}');" >/dev/null
selected_project="$(run_psql --tuples-only --no-align --command="SELECT project_id FROM app_data.user_current_projects WHERE app_user_id='${app_user_id}'::uuid;" | tr -d '[:space:]')"
[[ "${selected_project}" == "${other_project_id}" ]] || { echo '0151 real project-selection API did not commit the alternate project.' >&2; exit 1; }
after_switch_full_state="$(full_state)"
after_switch_business_state="$(business_state)"
before_stale_audits="$(workspace_audit_state)"
printf '%s\nCOMMIT;\n\\q\n' "${runtime_read_sql}" >&3
exec 3>&-
reader_status=0
wait "${reader_pid}" || reader_status=$?
reader_pid=''
stale_error="$(sed -n '/^ERROR:/p' "${temporary_directory}/reader.out" | head -n 1)"

if [[ "${baseline_mode}" == '1' ]]; then
  if [[ "${reader_status}" -ne 0 || "$(sed -n '/^{/p' "${temporary_directory}/reader.out" | tail -n 1)" != "${expected_document}" ]]; then
    echo '0151 baseline RED did not return the old projection in the RR transaction.' >&2
    sed -n '1,100p' "${temporary_directory}/reader.out" >&2
    exit 1
  fi
  [[ "${after_switch_business_state}" == "$(business_state)" ]] || { echo '0151 baseline stale read changed non-access business state.' >&2; exit 1; }
  assert_only_two_source_views "${before_stale_audits}" "$(workspace_audit_state)" 'baseline stale read'
  echo "RED 0150 baseline: RR snapshot on ${project_id}, committed normal switch to ${other_project_id}, then runtime wrapper returned original two-source document and added exactly two viewed audits."
else
  if [[ "${reader_status}" -eq 0 || "${stale_error}" != 'ERROR:  0A000: authorized personal target merge projection requires read committed' ]]; then
    echo "0151 stale RR projection expected exact 0A000 before audit, status ${reader_status}: ${stale_error}" >&2
    sed -n '1,100p' "${temporary_directory}/reader.out" >&2
    exit 1
  fi
  [[ "${after_switch_full_state}" == "$(full_state)" ]] || { echo '0151 rejected stale RR projection changed database state after project switch.' >&2; exit 1; }
fi

# A fresh READ COMMITTED attempt for the former project must be denied without a new audit.
fresh_before="$(full_state)"
fresh_status=0
run_psql --quiet --command="${runtime_read_sql}" >"${temporary_directory}/fresh.out" 2>&1 || fresh_status=$?
fresh_error="$(sed -n '/^ERROR:/p' "${temporary_directory}/fresh.out" | head -n 1)"
if [[ "${fresh_status}" -eq 0 || "${fresh_error}" != 'ERROR:  42501: authorized known-source personal target merge projection is forbidden' ]]; then
  echo "0151 fresh RC old-project read expected exact 42501, status ${fresh_status}: ${fresh_error}" >&2
  sed -n '/^ERROR:/p' "${temporary_directory}/fresh.out" >&2
  exit 1
fi
[[ "${fresh_before}" == "$(full_state)" ]] || { echo '0151 fresh forbidden read changed business state or access audits.' >&2; exit 1; }

if [[ "${baseline_mode}" == '1' ]]; then
  echo 'Baseline RED complete; fresh RC old-project denial was 42501 with no state change.'
else
  echo '0151 authorized projection isolation passed: non-RC 0A000 after validation, current RC two-source audit, stale RR pre-switch snapshot rejected before audit, and fresh RC 42501 after normal project switch.'
fi
