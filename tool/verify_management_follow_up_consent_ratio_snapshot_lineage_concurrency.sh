#!/usr/bin/env bash

set -euo pipefail

# 6BQ committed rows use the 6b75c000 namespace. Rollback fixtures use 6bf.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "$psql_command" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:-} -c statement_timeout=30000 -c lock_timeout=15000"
run_psql() {
  "$psql_command" "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}

temporary_directory="$(mktemp -d)"
background_pids=''
started_pid=''
mutation_first_release_status=''
cleanup() {
  local child_pid
  for child_pid in $background_pids; do
    if kill -0 "$child_pid" >/dev/null 2>&1; then
      kill "$child_pid" >/dev/null 2>&1 || true
    fi
    wait "$child_pid" >/dev/null 2>&1 || true
  done
  rm -f "$temporary_directory"/*.out
  rmdir "$temporary_directory"
}
trap cleanup EXIT

release_role="${CONSENT_RATIO_SNAPSHOT_RELEASE_ROLE:-tongxingzhe_management_consent_ratio_snapshot_release_writer}"
config_role='tongxingzhe_management_follow_up_consent_config_writer'
report_id='contact_target_follow_up_consent_ratio_two_periods'
attempt_table='app_private.management_follow_up_consent_report_release_attempts'

actor_id='6b75c100-0000-4000-8000-000000000001'
workspace_id='6b75c200-0000-4000-8000-000000000001'
project_one='6b75c300-0000-4000-8000-000000000001'
project_two='6b75c300-0000-4000-8000-000000000002'
project_three='6b75c300-0000-4000-8000-000000000003'
project_four='6b75c300-0000-4000-8000-000000000004'
project_five='6b75c300-0000-4000-8000-000000000005'
project_six='6b75c300-0000-4000-8000-000000000006'
project_seven='6b75c300-0000-4000-8000-000000000007'
project_eight='6b75c300-0000-4000-8000-000000000008'
project_array="'$project_one'::uuid,'$project_two'::uuid,'$project_three'::uuid,'$project_four'::uuid,'$project_five'::uuid,'$project_six'::uuid,'$project_seven'::uuid,'$project_eight'::uuid"

same_request='6b75c900-0000-4000-8000-000000000001'
lineage_first='6b75c900-0000-4000-8000-000000000002'
lineage_second='6b75c900-0000-4000-8000-000000000003'
release_first_optin='6b75c900-0000-4000-8000-000000000004'
disable_first_optin='6b75c900-0000-4000-8000-000000000005'
release_first_cap='6b75c900-0000-4000-8000-000000000006'
revoke_first_cap='6b75c900-0000-4000-8000-000000000007'
release_first_archive='6b75c900-0000-4000-8000-000000000008'
archive_first='6b75c900-0000-4000-8000-000000000009'
release_first_disable_config='6b75cb00-0000-4000-8000-000000000001'
disable_first_disable_config='6b75cb00-0000-4000-8000-000000000002'

same_request_lock='6bq-same-request-6b75c'
lineage_lock='6bq-same-lineage-6b75c'
release_first_optin_lock='6bq-release-first-optin-6b75c'
disable_first_optin_lock='6bq-disable-first-optin-6b75c'
release_first_cap_lock='6bq-release-first-cap-6b75c'
revoke_first_cap_lock='6bq-revoke-first-cap-6b75c'
release_first_archive_lock='6bq-release-first-archive-6b75c'
archive_first_lock='6bq-archive-first-6b75c'

wait_for_barrier() {
  local lock_name="$1"
  local label="$2"
  local result
  for _ in $(seq 1 200); do
    result="$(run_psql --tuples-only --no-align --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(hashtextextended('$lock_name', 0))
          THEN 'not-ready' ELSE 'ready' END;
    ")"
    if [[ "$result" == *ready* && "$result" != *not-ready* ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "6BQ $label session did not reach its barrier." >&2
  return 1
}

wait_for_query_waiter() {
  local query_fragment="$1"
  local label="$2"
  local waiting
  for _ in $(seq 1 200); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_stat_activity AS activity
        WHERE activity.pid <> pg_backend_pid()
          AND activity.state = 'active'
          AND activity.wait_event_type = 'Lock'
          AND position('$query_fragment' IN activity.query) > 0
      );
    " | tr -d '[:space:]')"
    if [[ "$waiting" == 't' ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "6BQ $label did not observe a lock waiter." >&2
  return 1
}

assert_value_free_result() {
  local output_file="$1"
  if grep -Eq '"(protected_report|period_results|ratio|coverage|cells|value_count|contributor_key|contact_id|promotion_target_id|follow_up_consent|unit_count)"' "$output_file"; then
    echo "release result leaked candidate/source values: $output_file" >&2
    sed -n '1,160p' "$output_file" >&2
    exit 1
  fi
}

assert_snapshot_value_free() {
  local project_id="$1"
  local result
  result="$(run_psql --tuples-only --no-align --command="
    SELECT count(*) FROM app_private.management_report_snapshots AS snapshot
    WHERE snapshot.project_id = '$project_id'::uuid
      AND snapshot.report_id = '$report_id'
      AND (
        snapshot.protected_report::text ~
          '\"(contact_id|promotion_target_id|contributor_key|app_user_id|organization_membership_id|project_membership_id|capability_grant_id|follow_up_consent|unit_count)\"[[:space:]]*:'
      );
  " | tr -d '[:space:]')"
  if [[ "$result" != '0' ]]; then
    echo "protected snapshot leaked source/provenance keys: $project_id" >&2
    exit 1
  fi
}

assert_attempt_value_free() {
  local project_id="$1"
  local result
  result="$(run_psql --tuples-only --no-align --command="
    SELECT count(*) FROM $attempt_table AS attempt
    WHERE attempt.project_id = '$project_id'::uuid
      AND attempt.result_document::text ~
        '\"(protected_report|period_results|ratio|coverage|cells|value_count|contributor_key|contact_id|promotion_target_id|follow_up_consent|unit_count)\"[[:space:]]*:';
  " | tr -d '[:space:]')"
  if [[ "$result" != '0' ]]; then
    echo "attempt document leaked candidate values: $project_id" >&2
    exit 1
  fi
}

assert_blocked_attempt() {
  local request_id="$1"
  local project_id="$2"
  local reason_code="$3"
  local result
  result="$(run_psql --tuples-only --no-align --command="
    SELECT count(*) FROM $attempt_table AS attempt
    WHERE attempt.release_request_id = '$request_id'::uuid
      AND attempt.project_id = '$project_id'::uuid
      AND attempt.result_status = 'blocked'
      AND attempt.reason_codes = jsonb_build_array('$reason_code')
      AND attempt.released_snapshot_id IS NULL;
  " | tr -d '[:space:]')"
  if [[ "$result" != '1' ]]; then
    echo "blocked attempt contract mismatch: $request_id ($result)" >&2
    exit 1
  fi
}

assert_authorization_rejection() {
  local output_file="$1"
  if ! grep -Fq 'management report authorization forbidden' "$output_file"; then
    echo "release did not fail with the authorization contract: $output_file" >&2
    sed -n '1,160p' "$output_file" >&2
    exit 1
  fi
}

assert_no_attempt() {
  local request_id="$1"
  local result
  result="$(run_psql --tuples-only --no-align --command="
    SELECT count(*) FROM $attempt_table
    WHERE release_request_id = '$request_id'::uuid;
  " | tr -d '[:space:]')"
  if [[ "$result" != '0' ]]; then
    echo "authorization rejection wrote release history: $request_id" >&2
    exit 1
  fi
}

release_call() {
  local request_id="$1"
  local project_id="$2"
  local output_file="$3"
  run_psql --tuples-only --no-align --quiet --command="
    SET statement_timeout = '20s';
    SET ROLE $release_role;
    SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      '$request_id'::uuid, '$actor_id'::uuid, '$project_id'::uuid,
      '$report_id', 1
    )::text;
  " >"$output_file" 2>&1
}

start_release() {
  local request_id="$1"
  local project_id="$2"
  local ready_lock="$3"
  local output_file="$4"
  (
    run_psql --tuples-only --no-align --quiet --command="
      BEGIN;
      SET LOCAL ROLE $release_role;
      SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
        '$request_id'::uuid, '$actor_id'::uuid, '$project_id'::uuid,
        '$report_id', 1
      )::text;
      SELECT pg_advisory_lock(hashtextextended('$ready_lock', 0));
      SELECT pg_sleep(2);
      SELECT pg_advisory_unlock(hashtextextended('$ready_lock', 0));
      COMMIT;
    "
  ) >"$output_file" 2>&1 &
  started_pid=$!
}

start_mutation() {
  local kind="$1"
  local project_id="$2"
  local ready_lock="$3"
  local output_file="$4"
  local request_id="$5"
  local grant_id="$6"
  (
    if [[ "$kind" == 'disable' ]]; then
      run_psql --tuples-only --no-align --quiet --command="
        BEGIN;
        SET LOCAL ROLE $config_role;
        SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
          '$actor_id'::uuid, '$project_id'::uuid,
          'follow_up_consent_ratio@1', '$request_id'::uuid, 1, false
        );
        SELECT pg_advisory_lock(hashtextextended('$ready_lock', 0));
        SELECT pg_sleep(2);
        SELECT pg_advisory_unlock(hashtextextended('$ready_lock', 0));
        COMMIT;
      "
    elif [[ "$kind" == 'revoke' ]]; then
      run_psql --tuples-only --no-align --quiet --command="
        BEGIN;
        UPDATE app_data.management_report_capability_grants
        SET inactive_from_utc = clock_timestamp()
        WHERE capability_grant_id = '$grant_id'::uuid;
        SELECT pg_advisory_lock(hashtextextended('$ready_lock', 0));
        SELECT pg_sleep(2);
        SELECT pg_advisory_unlock(hashtextextended('$ready_lock', 0));
        COMMIT;
      "
    else
      run_psql --tuples-only --no-align --quiet --command="
        BEGIN;
        UPDATE app_data.projects SET status = 'archived'
        WHERE project_id = '$project_id'::uuid;
        SELECT pg_advisory_lock(hashtextextended('$ready_lock', 0));
        SELECT pg_sleep(2);
        SELECT pg_advisory_unlock(hashtextextended('$ready_lock', 0));
        COMMIT;
      "
    fi
  ) >"$output_file" 2>&1 &
  started_pid=$!
}

echo '建立 6BQ committed concurrency synthetic hierarchy。'
run_psql --command="
  BEGIN;
  SET LOCAL TIME ZONE 'UTC';
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('$actor_id'::uuid, 'active');
  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name, personal_owner_app_user_id
  ) VALUES (
    '$workspace_id'::uuid, 'organization',
    '6BQ consent ratio snapshot concurrency organization', NULL
  );
  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status, is_personal_default
  )
  SELECT project_id, '$workspace_id'::uuid, format('6BQ project %s', number),
    'active', false
  FROM unnest(ARRAY[$project_array]) WITH ORDINALITY
    AS project_rows(project_id, number);
  INSERT INTO app_data.questionnaire_versions (
    questionnaire_version_id, project_id, version_number, status, is_current
  )
  SELECT format('6b75c400-0000-4000-8000-%s', lpad(number::text, 12, '0'))::uuid,
    project_id, 1, 'published', true
  FROM unnest(ARRAY[$project_array]) WITH ORDINALITY
    AS project_rows(project_id, number);
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    '6b75c600-0000-4000-8000-000000000001'::uuid, '$workspace_id'::uuid,
    '$actor_id'::uuid, transaction_timestamp() - interval '365 days', NULL
  );
  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id, project_id,
    active_from_utc, inactive_from_utc
  )
  SELECT format('6b75c700-0000-4000-8000-%s', lpad(number::text, 12, '0'))::uuid,
    '6b75c600-0000-4000-8000-000000000001'::uuid, project_id,
    transaction_timestamp() - interval '365 days', NULL
  FROM unnest(ARRAY[$project_array]) WITH ORDINALITY
    AS project_rows(project_id, number);
  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id,
    active_from_utc, inactive_from_utc
  )
  SELECT format('6b75c800-0000-4000-8000-%s', lpad(number::text, 12, '0'))::uuid,
    format('6b75c700-0000-4000-8000-%s', lpad(number::text, 12, '0'))::uuid,
    'release_management_reports',
    transaction_timestamp() - interval '365 days', NULL
  FROM generate_series(1, 8) AS numbers(number);
  COMMIT;
" >/dev/null

run_psql --command="
  BEGIN;
  SET LOCAL TIME ZONE 'UTC';
  SELECT app_private.configure_project_reporting_time_zone_v1(
    format('6b75c500-0000-4000-8000-%s', lpad(number::text, 12, '0'))::uuid,
    '$actor_id'::uuid, project_id, 0, 'UTC',
    transaction_timestamp() - interval '365 days'
  )
  FROM unnest(ARRAY[$project_array]) WITH ORDINALITY
    AS project_rows(project_id, number);
  COMMIT;
" >/dev/null

run_psql --command="
  INSERT INTO app_data.change_feed (
    app_user_id, workspace_id, project_id, aggregate_id, revision_number,
    change_type
  )
  SELECT '$actor_id'::uuid, '$workspace_id'::uuid, project_id,
    format('6b75c-watermark-%s', number), 1, 'contact.submitted'
  FROM unnest(ARRAY[$project_array]) WITH ORDINALITY
    AS project_rows(project_id, number);
" >/dev/null

run_psql --tuples-only --no-align --quiet --command="
  SET ROLE $config_role;
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '$actor_id'::uuid, project_id, 'follow_up_consent_ratio@1',
    format('6b75cc00-0000-4000-8000-%s', lpad(number::text, 12, '0'))::uuid,
    0, true
  )
  FROM unnest(ARRAY[$project_array]) WITH ORDINALITY
    AS project_rows(project_id, number);
" >/dev/null

# Same request: both callers return the same value-free metadata document.
echo '6BQ same-request。'
same_first="$temporary_directory/same-first.out"
start_release "$same_request" "$project_one" "$same_request_lock" "$same_first"
same_pid=$started_pid
background_pids="$background_pids $same_pid"
wait_for_barrier "$same_request_lock" 'same-request'
same_second="$temporary_directory/same-second.out"
release_call "$same_request" "$project_one" "$same_second" &
same_second_pid=$!
background_pids="$background_pids $same_second_pid"
same_status=0
same_second_status=0
wait "$same_pid" || same_status=$?
wait "$same_second_pid" || same_second_status=$?
if [[ "$same_status" -ne 0 || "$same_second_status" -ne 0 ]]; then
  cat "$same_first" "$same_second" >&2
  exit 1
fi
assert_value_free_result "$same_first"
assert_value_free_result "$same_second"
same_json_one="$(grep -E '^\{' "$same_first" | tail -n 1 | tr -d '[:space:]')"
same_json_two="$(grep -E '^\{' "$same_second" | tail -n 1 | tr -d '[:space:]')"
if [[ -z "$same_json_one" || "$same_json_one" != "$same_json_two" ]]; then
  echo '6BQ same-request JSON mismatch.' >&2
  exit 1
fi
same_history="$(run_psql --tuples-only --no-align --command="
  SELECT (SELECT count(*) FROM $attempt_table
          WHERE project_id = '$project_one'::uuid
            AND report_id = '$report_id')
    || '|' || (SELECT count(*) FROM app_private.management_report_snapshots
          WHERE project_id = '$project_one'::uuid
            AND report_id = '$report_id');
" | tr -d '[:space:]')"
if [[ "$same_history" != '1|1' ]]; then
  echo "6BQ same-request history error: $same_history" >&2
  exit 1
fi
assert_snapshot_value_free "$project_one"

# Same lineage: request two must compare/pointer to request one.
echo '6BQ same-lineage。'
lineage_first_file="$temporary_directory/lineage-first.out"
start_release "$lineage_first" "$project_two" "$lineage_lock" "$lineage_first_file"
lineage_first_pid=$started_pid
background_pids="$background_pids $lineage_first_pid"
wait_for_barrier "$lineage_lock" 'same-lineage'
lineage_second_file="$temporary_directory/lineage-second.out"
release_call "$lineage_second" "$project_two" "$lineage_second_file" &
lineage_second_pid=$!
background_pids="$background_pids $lineage_second_pid"
lineage_first_status=0
lineage_second_status=0
wait "$lineage_first_pid" || lineage_first_status=$?
wait "$lineage_second_pid" || lineage_second_status=$?
if [[ "$lineage_first_status" -ne 0 || "$lineage_second_status" -ne 0 ]]; then
  cat "$lineage_first_file" "$lineage_second_file" >&2
  exit 1
fi
assert_value_free_result "$lineage_first_file"
assert_value_free_result "$lineage_second_file"
lineage_history="$(run_psql --tuples-only --no-align --command="
  WITH attempts AS (
    SELECT release_request_id, compared_snapshot_id
    FROM $attempt_table
    WHERE project_id = '$project_two'::uuid AND report_id = '$report_id'
  ), snapshots AS (
    SELECT snapshot_id, release_request_id, previous_snapshot_id
    FROM app_private.management_report_snapshots
    WHERE project_id = '$project_two'::uuid AND report_id = '$report_id'
  )
  SELECT (SELECT count(*) FROM attempts)
    || '|' || (SELECT count(*) FROM snapshots)
    || '|' || CASE WHEN
      (SELECT compared_snapshot_id FROM attempts
       WHERE release_request_id = '$lineage_second'::uuid) =
      (SELECT snapshot_id FROM snapshots
       WHERE release_request_id = '$lineage_first'::uuid)
      THEN 'previous-ok' ELSE 'previous-bad' END
    || '|' || CASE WHEN
      (SELECT previous_snapshot_id FROM snapshots
       WHERE release_request_id = '$lineage_second'::uuid) =
      (SELECT snapshot_id FROM snapshots
       WHERE release_request_id = '$lineage_first'::uuid)
      THEN 'pointer-ok' ELSE 'pointer-bad' END;
" | tr -d '[:space:]')"
if [[ "$lineage_history" != '2|2|previous-ok|pointer-ok' ]]; then
  echo "6BQ same-lineage history error: $lineage_history" >&2
  exit 1
fi
assert_snapshot_value_free "$project_two"

run_release_first() {
  local label="$1"
  local request_id="$2"
  local project_id="$3"
  local ready_lock="$4"
  local output_file="$5"
  local kind="$6"
  local mutation_request="$7"
  local grant_id="$8"
  local mutation_file="$temporary_directory/$label-mutation.out"
  local release_pid mutation_pid release_status mutation_status
  start_release "$request_id" "$project_id" "$ready_lock" "$output_file"
  release_pid=$started_pid
  background_pids="$background_pids $release_pid"
  wait_for_barrier "$ready_lock" "$label release-first"
  start_mutation "$kind" "$project_id" "$ready_lock-mutation" "$mutation_file" "$mutation_request" "$grant_id"
  mutation_pid=$started_pid
  background_pids="$background_pids $mutation_pid"
  waiter_fragment="$mutation_request"
  if [[ -z "$waiter_fragment" && -n "$grant_id" ]]; then
    waiter_fragment="$grant_id"
  elif [[ -z "$waiter_fragment" ]]; then
    waiter_fragment="$project_id"
  fi
  wait_for_query_waiter "$waiter_fragment" "$label release-first mutation"
  release_status=0
  mutation_status=0
  wait "$release_pid" || release_status=$?
  wait "$mutation_pid" || mutation_status=$?
  if [[ "$release_status" -ne 0 || "$mutation_status" -ne 0 ]]; then
    cat "$output_file" "$mutation_file" >&2
    exit 1
  fi
  assert_value_free_result "$output_file"
}

run_mutation_first() {
  local label="$1"
  local request_id="$2"
  local project_id="$3"
  local ready_lock="$4"
  local output_file="$5"
  local kind="$6"
  local mutation_request="$7"
  local grant_id="$8"
  local mutation_file="$temporary_directory/$label-mutation.out"
  local mutation_pid release_pid mutation_status release_status
  start_mutation "$kind" "$project_id" "$ready_lock" "$mutation_file" "$mutation_request" "$grant_id"
  mutation_pid=$started_pid
  background_pids="$background_pids $mutation_pid"
  wait_for_barrier "$ready_lock" "$label mutation-first"
  release_call "$request_id" "$project_id" "$output_file" &
  release_pid=$!
  background_pids="$background_pids $release_pid"
  wait_for_query_waiter "$request_id" "$label mutation-first release"
  set +e
  wait "$release_pid"
  release_status=$?
  wait "$mutation_pid"
  mutation_status=$?
  set -e
  if [[ "$mutation_status" -ne 0 ]]; then
    cat "$mutation_file" >&2
    exit 1
  fi
  assert_value_free_result "$output_file"
  mutation_first_release_status=$release_status
}

echo '6BQ release↔opt-in disable。'
release_first_optin_file="$temporary_directory/release-first-optin.out"
run_release_first 'release-first-optin' "$release_first_optin" "$project_three" "$release_first_optin_lock" "$release_first_optin_file" 'disable' "$release_first_disable_config" ''
optin_first_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.management_report_snapshots
  WHERE project_id = '$project_three'::uuid AND report_id = '$report_id';
" | tr -d '[:space:]')"
if [[ "$optin_first_count" != '1' ]]; then
  echo "6BQ release-first opt-in snapshot error: $optin_first_count" >&2
  exit 1
fi
optin_disabled="$(run_psql --tuples-only --no-align --command="
  SELECT enabled::text
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '$project_three'::uuid
  ORDER BY version_number DESC
  LIMIT 1;
" | tr -d '[:space:]')"
if [[ "$optin_disabled" != 'false' ]]; then
  echo "6BQ release-first opt-in mutation did not commit: $optin_disabled" >&2
  exit 1
fi
assert_snapshot_value_free "$project_three"

disable_first_file="$temporary_directory/disable-first-optin-release.out"
run_mutation_first 'disable-first-optin' "$disable_first_optin" "$project_four" "$disable_first_optin_lock" "$disable_first_file" 'disable' "$disable_first_disable_config" ''
disable_first_status=$mutation_first_release_status
if [[ "$disable_first_status" != '0' ]]; then
  echo "6BQ disable-first opt-in release error: $disable_first_status" >&2
  sed -n '1,160p' "$disable_first_file" >&2
  exit 1
fi
optin_disable_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.management_report_snapshots
  WHERE project_id = '$project_four'::uuid AND report_id = '$report_id';
" | tr -d '[:space:]')"
if [[ "$optin_disable_count" != '0' ]]; then
  echo "6BQ disable-first opt-in leaked snapshot: $optin_disable_count" >&2
  exit 1
fi
assert_blocked_attempt "$disable_first_optin" "$project_four" \
  'release_opt_in_not_enabled'
assert_attempt_value_free "$project_four"

echo '6BQ release↔capability revoke。'
release_first_cap_file="$temporary_directory/release-first-cap.out"
run_release_first 'release-first-capability' "$release_first_cap" "$project_five" "$release_first_cap_lock" "$release_first_cap_file" 'revoke' '' '6b75c800-0000-4000-8000-000000000005'
cap_first_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.management_report_snapshots
  WHERE project_id = '$project_five'::uuid AND report_id = '$report_id';
" | tr -d '[:space:]')"
if [[ "$cap_first_count" != '1' ]]; then
  echo "6BQ release-first capability snapshot error: $cap_first_count" >&2
  exit 1
fi
capability_revoked="$(run_psql --tuples-only --no-align --command="
  SELECT (inactive_from_utc IS NOT NULL)::text
  FROM app_data.management_report_capability_grants
  WHERE capability_grant_id =
    '6b75c800-0000-4000-8000-000000000005'::uuid;
" | tr -d '[:space:]')"
if [[ "$capability_revoked" != 'true' ]]; then
  echo '6BQ release-first capability mutation did not commit.' >&2
  exit 1
fi
assert_snapshot_value_free "$project_five"

revoke_first_file="$temporary_directory/revoke-first-cap-release.out"
run_mutation_first 'revoke-first-capability' "$revoke_first_cap" "$project_six" "$revoke_first_cap_lock" "$revoke_first_file" 'revoke' '' '6b75c800-0000-4000-8000-000000000006'
revoke_first_status=$mutation_first_release_status
if [[ "$revoke_first_status" == '0' ]]; then
  echo '6BQ revoke-first capability release was not rejected.' >&2
  sed -n '1,160p' "$revoke_first_file" >&2
  exit 1
fi
assert_authorization_rejection "$revoke_first_file"
assert_no_attempt "$revoke_first_cap"
cap_revoke_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.management_report_snapshots
  WHERE project_id = '$project_six'::uuid AND report_id = '$report_id';
" | tr -d '[:space:]')"
if [[ "$cap_revoke_count" != '0' ]]; then
  echo "6BQ revoke-first capability leaked snapshot: $cap_revoke_count" >&2
  exit 1
fi
assert_attempt_value_free "$project_six"

echo '6BQ release↔archive。'
release_first_archive_file="$temporary_directory/release-first-archive.out"
run_release_first 'release-first-archive' "$release_first_archive" "$project_seven" "$release_first_archive_lock" "$release_first_archive_file" 'archive' '' ''
archive_first_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.management_report_snapshots
  WHERE project_id = '$project_seven'::uuid AND report_id = '$report_id';
" | tr -d '[:space:]')"
if [[ "$archive_first_count" != '1' ]]; then
  echo "6BQ release-first archive snapshot error: $archive_first_count" >&2
  exit 1
fi
archive_committed="$(run_psql --tuples-only --no-align --command="
  SELECT status FROM app_data.projects
  WHERE project_id = '$project_seven'::uuid;
" | tr -d '[:space:]')"
if [[ "$archive_committed" != 'archived' ]]; then
  echo "6BQ release-first archive mutation did not commit: $archive_committed" >&2
  exit 1
fi
assert_snapshot_value_free "$project_seven"

archive_first_file="$temporary_directory/archive-first-release.out"
run_mutation_first 'archive-first' "$archive_first" "$project_eight" "$archive_first_lock" "$archive_first_file" 'archive' '' ''
archive_first_status=$mutation_first_release_status
if [[ "$archive_first_status" == '0' ]]; then
  echo '6BQ archive-first release was not rejected.' >&2
  sed -n '1,160p' "$archive_first_file" >&2
  exit 1
fi
assert_authorization_rejection "$archive_first_file"
assert_no_attempt "$archive_first"
archive_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.management_report_snapshots
  WHERE project_id = '$project_eight'::uuid AND report_id = '$report_id';
" | tr -d '[:space:]')"
if [[ "$archive_count" != '0' ]]; then
  echo "6BQ archive-first leaked snapshot: $archive_count" >&2
  exit 1
fi
assert_attempt_value_free "$project_eight"

echo '6BQ same-request, same-lineage, opt-in, capability and archive concurrency checks passed.'
