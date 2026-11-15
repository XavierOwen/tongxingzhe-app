#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
reader_pid=''
cleanup() {
  exec 3>&- 2>/dev/null || true
  if [[ -n "${reader_pid}" ]]; then
    if kill -0 "${reader_pid}" >/dev/null 2>&1; then kill "${reader_pid}" >/dev/null 2>&1 || true; fi
    wait "${reader_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

baseline_mode="${MANAGEMENT_OPT_IN_READ_ISOLATION_EXPECT_BASELINE:-0}"
latest_version="$(run_psql --tuples-only --no-align --command='SELECT max(version) FROM app_migrations.schema_migrations;' | tr -d '[:space:]')"
if [[ "${baseline_mode}" == '1' && "${latest_version}" != '0155_management_follow_up_consent_opt_in_isolation' ]]; then
  echo "RED mode requires official 0155 baseline, found ${latest_version}." >&2
  exit 1
fi
snapshot_definition="$(cat "$(dirname "${BASH_SOURCE[0]}")/../backend/database/fixtures/shared/database_state.sql")"
full_state() {
  run_psql --quiet --tuples-only --no-align --command="${snapshot_definition} SELECT pg_temp.fixture_database_state();" | tail -n 1
}
config_role='tongxingzhe_management_follow_up_consent_config_writer'
candidate_role='tongxingzhe_management_follow_up_consent_ratio_reader'
gate_message='management follow-up consent opt-in read requires read committed'
configure_sql() {
  printf "SELECT app_private.configure_management_follow_up_consent_opt_in_v1('%s','%s','follow_up_consent_ratio@1','%s',%s,%s);\n" \
    "${actor_id}" "${project_id}" "$1" "$2" "$3"
}
expect_rejection() {
  local isolation="$1" expected_state="$2" expected_message="$3" query="$4" role="${5:-${config_role}}" before status=0 error_line
  before="$(full_state)"
  run_psql --quiet --command="BEGIN ISOLATION LEVEL ${isolation}; SET ROLE ${role}; ${query} COMMIT;" \
    >"${temporary_directory}/rejection.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/p' "${temporary_directory}/rejection.out" | head -n 1)"
  if [[ "${status}" -eq 0 || "${error_line}" != "ERROR:  ${expected_state}: ${expected_message}" ]]; then
    echo "${isolation}: expected ${expected_state} ${expected_message}, status ${status}: ${error_line}" >&2
    sed -n '1,80p' "${temporary_directory}/rejection.out" >&2
    exit 1
  fi
  [[ "${before}" == "$(full_state)" ]] || { echo "${isolation}: rejected read changed database state." >&2; exit 1; }
}
expect_rc_state() {
  local expected_status="$1" version="$2" before document bridge expected
  before="$(full_state)"
  document="$(run_psql --quiet --tuples-only --no-align --command="BEGIN ISOLATION LEVEL READ COMMITTED; SET ROLE ${config_role}; ${read_sql} COMMIT;")"
  bridge="$(run_psql --quiet --tuples-only --no-align --command="BEGIN ISOLATION LEVEL READ COMMITTED; SET ROLE ${candidate_role}; ${bridge_sql} COMMIT;")"
  expected="$(run_psql --quiet --tuples-only --no-align --command="SELECT jsonb_build_object(
    'state_contract_id','management_follow_up_consent_opt_in_state_v1','metric_id','follow_up_consent_ratio@1',
    'project_id','${project_id}'::uuid,'status','${expected_status}',
    'configuration',CASE WHEN ${version}=0 THEN NULL::jsonb ELSE app_private.management_follow_up_consent_opt_in_document_v1('${project_id}',${version}) END);")"
  if [[ "${document}" != "${expected}" || "${bridge}" != "${document}" || "${before}" != "$(full_state)" ]]; then
    echo "RC reader/candidate bridge did not preserve ${expected_status} v${version} and zero writes." >&2
    exit 1
  fi
}

# Preserve normal organization writers and all grant constraints and triggers.
run_token="$(date -u +%Y%m%d%H%M%S)-$$-${RANDOM}"
issuer="https://management-opt-in-read-isolation-${run_token}.example.test/auth/v1"
subject="owner-${run_token}"
actor_id="$(run_psql --quiet --tuples-only --no-align --command="SELECT app_user_id FROM app_data.bootstrap_personal_context('${issuer}','${subject}');")"
organization="$(run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
  SELECT organization_workspace_id,organization_membership_id FROM app_data.create_organization_for_identity_v1(
    '${issuer}','${subject}',gen_random_uuid(),'Opt-in read isolation ${run_token}');")"
IFS='|' read -r workspace_id organization_membership_id <<<"${organization}"
project_id="$(run_psql --quiet --tuples-only --no-align --command="
  INSERT INTO app_data.projects(workspace_id,display_name) VALUES('${workspace_id}','Opt-in read isolation project ${run_token}') RETURNING project_id;")"
project_membership_id="$(run_psql --quiet --tuples-only --no-align --command="
  SELECT project_membership_id FROM app_data.assign_organization_project_member_for_identity_v1(
    '${issuer}','${subject}',gen_random_uuid(),'${workspace_id}','${project_id}','${organization_membership_id}');")"
grant_id="$(run_psql --quiet --tuples-only --no-align --command="
  INSERT INTO app_data.management_report_capability_grants(capability_grant_id,project_membership_id,capability_id,active_from_utc)
  VALUES(gen_random_uuid(),'${project_membership_id}','release_management_reports',clock_timestamp()) RETURNING capability_grant_id;")"
request_ids="$(run_psql --quiet --tuples-only --no-align --field-separator='|' --command='SELECT gen_random_uuid(),gen_random_uuid(),gen_random_uuid();')"
IFS='|' read -r first_request second_request third_request <<<"${request_ids}"
for id in "${actor_id}" "${workspace_id}" "${organization_membership_id}" "${project_id}" "${project_membership_id}" "${grant_id}" "${first_request}" "${second_request}" "${third_request}"; do
  [[ "${id}" =~ ^[0-9a-f-]{36}$ ]] || { echo 'Normal opt-in read isolation fixture setup returned an invalid UUID.' >&2; exit 1; }
done
read_sql="SELECT app_private.read_management_follow_up_consent_opt_in_v1('${actor_id}','${project_id}','follow_up_consent_ratio@1');"
bridge_sql="SELECT app_private.read_management_follow_up_consent_opt_in_for_candidate_v1('${actor_id}','${project_id}','follow_up_consent_ratio@1');"
bridge_acl="$(run_psql --quiet --tuples-only --no-align --command="SELECT
  has_function_privilege('${candidate_role}','app_private.read_management_follow_up_consent_opt_in_for_candidate_v1(uuid,uuid,text)','EXECUTE')
  AND NOT has_function_privilege('${candidate_role}','app_private.read_management_follow_up_consent_opt_in_v1(uuid,uuid,text)','EXECUTE');")"
[[ "${bridge_acl}" == 't' ]] || { echo 'Candidate bridge lost its existing narrow ACL.' >&2; exit 1; }
expect_rc_state not_enabled 0
first_receipt="$(run_psql --quiet --tuples-only --no-align --command="BEGIN ISOLATION LEVEL READ COMMITTED; SET ROLE ${config_role}; $(configure_sql "${first_request}" 0 true) COMMIT;")"
expect_rc_state enabled 1
second_receipt="$(run_psql --quiet --tuples-only --no-align --command="BEGIN ISOLATION LEVEL READ COMMITTED; SET ROLE ${config_role}; $(configure_sql "${second_request}" 1 false) COMMIT;")"
expect_rc_state not_enabled 2
third_receipt="$(run_psql --quiet --tuples-only --no-align --command="BEGIN ISOLATION LEVEL READ COMMITTED; SET ROLE ${config_role}; $(configure_sql "${third_request}" 2 true) COMMIT;")"
expect_rc_state enabled 3
if [[ "${first_receipt}" != *'"version_number": 1'* || "${first_receipt}" != *'"enabled": true'* \
  || "${second_receipt}" != *'"version_number": 2'* || "${second_receipt}" != *'"enabled": false'* \
  || "${third_receipt}" != *'"version_number": 3'* || "${third_receipt}" != *'"enabled": true'* ]]; then
  echo 'Normal RC writers did not create the expected enabled/disabled/enabled receipts.' >&2
  exit 1
fi
before_replay="$(full_state)"
replayed_receipt="$(run_psql --quiet --tuples-only --no-align --command="BEGIN ISOLATION LEVEL READ COMMITTED; SET ROLE ${config_role}; $(configure_sql "${first_request}" 0 true) COMMIT;")"
[[ "${replayed_receipt}" == "${first_receipt}" && "${before_replay}" == "$(full_state)" ]] \
  || { echo 'RC exact writer replay changed its original receipt or business state.' >&2; exit 1; }
enabled_document="$(run_psql --quiet --tuples-only --no-align --command="SET ROLE ${config_role}; ${read_sql}")"

for isolation in 'READ UNCOMMITTED' 'REPEATABLE READ' SERIALIZABLE; do
  if [[ "${baseline_mode}" != '1' ]]; then
    expect_rejection "${isolation}" 0A000 "${gate_message}" "${read_sql}"
    expect_rejection "${isolation}" 0A000 "${gate_message}" "${bridge_sql}" "${candidate_role}"
  fi
  expect_rejection "${isolation}" 22023 'invalid management follow-up consent opt-in read' \
    "SELECT app_private.read_management_follow_up_consent_opt_in_v1(NULL,'${project_id}','follow_up_consent_ratio@1');"
  expect_rejection "${isolation}" 22023 'invalid management follow-up consent opt-in read' \
    "SELECT app_private.read_management_follow_up_consent_opt_in_v1('${actor_id}','${project_id}','unsupported_metric');"
done

# Pin a plain RR snapshot before the first read and every authorization lock.
mkfifo "${temporary_directory}/reader.fifo"
"${psql_base[@]}" --quiet --tuples-only --no-align <"${temporary_directory}/reader.fifo" \
  >"${temporary_directory}/reader.out" 2>&1 &
reader_pid=$!
exec 3>"${temporary_directory}/reader.fifo"
printf '%s\n%s\n' \
  "SET ROLE ${config_role}; BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT 'PINNED|' || count(*) FROM app_data.management_report_capability_grants WHERE capability_grant_id='${grant_id}' AND inactive_from_utc IS NULL;" \
  '\echo SNAPSHOT_READY' >&3
for _ in $(seq 1 200); do
  grep -q '^SNAPSHOT_READY$' "${temporary_directory}/reader.out" && break
  sleep 0.05
done
if ! grep -q '^SNAPSHOT_READY$' "${temporary_directory}/reader.out" || ! grep -q '^PINNED|1$' "${temporary_directory}/reader.out"; then
  echo 'Failed to establish the old RR grant snapshot.' >&2
  sed -n '1,80p' "${temporary_directory}/reader.out" >&2
  exit 1
fi
revoked_at="$(run_psql --quiet --tuples-only --no-align --command="
  UPDATE app_data.management_report_capability_grants SET inactive_from_utc=clock_timestamp()
  WHERE capability_grant_id='${grant_id}' AND inactive_from_utc IS NULL RETURNING inactive_from_utc;")"
[[ -n "${revoked_at}" ]] || { echo 'Normal grant revocation did not commit.' >&2; exit 1; }
revoked_state="$(full_state)"
printf '%s\nCOMMIT;\n\\q\n' "${read_sql}" >&3
exec 3>&-
reader_status=0
wait "${reader_pid}" || reader_status=$?
reader_pid=''
error_line="$(sed -n '/^ERROR:/p' "${temporary_directory}/reader.out" | head -n 1)"
after_reader="$(full_state)"
expect_rejection 'READ COMMITTED' 42501 'management report authorization forbidden' "${read_sql}"
expect_rejection 'READ COMMITTED' 42501 'management report authorization forbidden' "${bridge_sql}" "${candidate_role}"

if [[ "${reader_status}" -eq 0 ]]; then
  returned_document="$(sed -n '/^{/p' "${temporary_directory}/reader.out")"
  if [[ "${returned_document}" != "${enabled_document}" || "${revoked_state}" != "${after_reader}" ]]; then
    echo 'Old RR read did not preserve the original enabled JSON and business state.' >&2
    cat "${temporary_directory}/reader.out" >&2
    exit 1
  fi
  echo "RED: old RR read returned the original enabled configuration after committed grant revocation at ${revoked_at}." >&2
  cat "${temporary_directory}/reader.out" >&2
  exit 1
fi
if [[ "${baseline_mode}" == '1' || "${error_line}" != "ERROR:  0A000: ${gate_message}" || "${revoked_state}" != "${after_reader}" ]]; then
  echo "Old RR read did not reject with exact 0A000 and zero writes: ${error_line}" >&2
  cat "${temporary_directory}/reader.out" >&2
  exit 1
fi
echo 'Management opt-in read isolation passed: RC states/candidate bridge, input precedence, non-RC gates, and committed-revocation RR/fresh-RC denials with zero writes.'
