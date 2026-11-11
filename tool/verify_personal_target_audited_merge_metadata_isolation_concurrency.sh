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

baseline_mode="${PERSONAL_TARGET_AUDITED_METADATA_EXPECT_BASELINE:-0}"
latest_version="$(run_psql --tuples-only --no-align --command='SELECT max(version) FROM app_migrations.schema_migrations;' | tr -d '[:space:]')"
if [[ "${baseline_mode}" == '1' && "${latest_version}" != '0151_personal_target_authorized_projection_isolation' ]]; then
  echo "RED mode requires official 0151 baseline, found ${latest_version}." >&2
  exit 1
fi

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
    FROM app_data.promotion_target_access_events event WHERE event.workspace_id='${1}'::uuid;" | tail -n 1
}
assert_only_two_source_views() {
  local before="$1" after="$2" workspace="$3" actor="$4" first="$5" second="$6" label="$7" result
  result="$(run_psql --tuples-only --no-align --command="
    WITH snapshots AS (SELECT '${before}'::jsonb AS before_events,'${after}'::jsonb AS after_events),
    added AS (
      SELECT event.value FROM snapshots s CROSS JOIN LATERAL jsonb_array_elements(s.after_events) event(value)
      WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(s.before_events) old(value)
        WHERE old.value->'event_id'=event.value->'event_id')
    )
    SELECT s.after_events @> s.before_events
      AND (SELECT count(*) FROM added)=2
      AND (SELECT count(*) FILTER (WHERE value->>'promotion_target_id'='${first}') FROM added)=1
      AND (SELECT count(*) FILTER (WHERE value->>'promotion_target_id'='${second}') FROM added)=1
      AND (SELECT bool_and(value->>'workspace_id'='${workspace}' AND value->>'actor_app_user_id'='${actor}'
        AND value->>'action'='viewed' AND (SELECT count(*) FROM jsonb_object_keys(value))=6) FROM added)
    FROM snapshots s;" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || { echo "${label}: access events were not exactly one viewed per source." >&2; exit 1; }
}

expect_rejection() {
  local isolation="$1" expected_state="$2" expected_message="$3" query="$4" before status=0 error_line
  before="$(full_state)"
  run_psql --quiet --command="BEGIN ISOLATION LEVEL ${isolation}; SET ROLE tongxingzhe_runtime; ${query} COMMIT;" \
    >"${temporary_directory}/rejection.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/p' "${temporary_directory}/rejection.out" | head -n 1)"
  if [[ "${status}" -eq 0 || "${error_line}" != "ERROR:  ${expected_state}: ${expected_message}" ]]; then
    echo "${isolation} expected ${expected_state} ${expected_message}, status ${status}: ${error_line}" >&2
    sed -n '/^ERROR:/p' "${temporary_directory}/rejection.out" >&2
    exit 1
  fi
  [[ "${before}" == "$(full_state)" ]] || { echo "${isolation} rejection changed database state or access audits." >&2; exit 1; }
}

check_endpoint() {
  local kind="$1" run_token issuer subject context app_user_id workspace_id project_id other_project first_target second_target preview_id generation_id
  run_token="$(date -u +%Y%m%d%H%M%S)-$$-${kind}"
  issuer="https://audited-metadata-${kind}-${run_token}.example.test/auth/v1"
  subject="owner-${run_token}"
  run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}','${subject}');" >/dev/null
  context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT app_user_id,workspace_id,project_id FROM app_data.list_personal_project_contexts('${issuer}','${subject}') WHERE is_current;
  " | tr -d '[:space:]')"
  IFS='|' read -r app_user_id workspace_id project_id <<<"${context}"
  other_project="$(run_psql --tuples-only --no-align --command="
    SELECT project_id FROM app_data.create_personal_project_context('${issuer}','${subject}','alternate ${kind}');
  " | tr -d '[:space:]')"
  run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('${issuer}','${subject}','${project_id}');" >/dev/null
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('${app_user_id}','${workspace_id}','${project_id}','person',
      'audited ${kind} first ${run_token}','+1 312 555 0152','${run_token}-first@example.test','audited-${run_token}-first');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id'
    FROM app_data.create_promotion_target('${app_user_id}','${workspace_id}','${project_id}','person',
      'audited ${kind} second ${run_token}','+1 312 555 0152','${run_token}-second@example.test','audited-${run_token}-second');")"
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id
    FROM app_data.preview_personal_target_pair_v1('${issuer}','${subject}','${project_id}','${first_target}','${second_target}');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '${app_user_id}','${project_id}',gen_random_uuid(),'${preview_id}',
    '${first_target}','${second_target}','${first_target}','${second_target}');")"
  for id in "${app_user_id}" "${workspace_id}" "${project_id}" "${other_project}" "${first_target}" "${second_target}" "${preview_id}" "${generation_id}"; do
    [[ "${id}" =~ ^[0-9a-f-]{36}$ ]] || { echo "${kind}: real project/generation seed failed." >&2; exit 1; }
  done

  local query expected_message
  if [[ "${kind}" == 'split' ]]; then
    query="SELECT app_data.read_personal_known_source_merge_split_plan_v1('${issuer}','${subject}','${project_id}','${generation_id}');"
    expected_message='authorized personal merge split plan requires read committed'
  else
    query="SELECT app_data.read_personal_merge_directory_v1('${issuer}','${subject}','${project_id}',NULL);"
    expected_message='authorized personal merge directory requires read committed'
  fi
  local runtime_query="SET ROLE tongxingzhe_runtime; ${query}"
  local expected_document
  if [[ "${kind}" == 'split' ]]; then
    expected_document="$(run_psql --tuples-only --no-align --command="SELECT app_private.read_known_source_personal_merge_split_plan_v1(
      '${app_user_id}','${workspace_id}','${project_id}','${generation_id}');")"
  else
    expected_document="$(run_psql --tuples-only --no-align --command="
      WITH members AS (SELECT array_agg(promotion_target_id ORDER BY promotion_target_id) ids FROM app_private.personal_target_merge_generation_members_v1 WHERE generation_id='${generation_id}'::uuid)
      SELECT jsonb_build_object('workspace_id','${workspace_id}'::uuid,'project_id','${project_id}'::uuid,
        'items',jsonb_build_array(jsonb_build_object('generation_id','${generation_id}'::uuid,'target_type','person',
          'retained_target_id','${first_target}'::uuid,'member_target_ids',members.ids,
          'review_due_at_utc',to_char(least(app_data.promotion_target_review_due_at(members.ids[1]),
            app_data.promotion_target_review_due_at(members.ids[2])) AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'))),
        'next_cursor',NULL) FROM members;")"
  fi
  if [[ "${kind}" == 'split' ]]; then
    expected_sources="$(run_psql --tuples-only --no-align --command="SELECT jsonb_array_length('${expected_document}'::jsonb->'member_target_ids');" | tr -d '[:space:]')"
    [[ "${expected_sources}" == '2' ]] || { echo 'split plan missing two real sources.' >&2; exit 1; }
  fi

  if [[ "${baseline_mode}" != '1' ]]; then
    for isolation in 'READ UNCOMMITTED' 'REPEATABLE READ' SERIALIZABLE; do
      expect_rejection "${isolation}" 0A000 "${expected_message}" "${query}"
    done
    # Split's explicit NULL-generation validation precedes the isolation guard.
    if [[ "${kind}" == 'split' ]]; then
      null_generation_query="SELECT app_data.read_personal_known_source_merge_split_plan_v1('${issuer}','${subject}','${project_id}',NULL);"
      expect_rejection 'REPEATABLE READ' 22023 'invalid authorized known-source merge split plan request' "${null_generation_query}"
    fi
    # Context argument-shape validation remains intact on RC; on non-RC the gate precedes the nested context reader.
    if [[ "${kind}" == 'split' ]]; then
      bad_issuer_query="SELECT app_data.read_personal_known_source_merge_split_plan_v1('','${subject}','${project_id}','${generation_id}');"
    else
      bad_issuer_query="SELECT app_data.read_personal_merge_directory_v1('','${subject}','${project_id}',NULL);"
    fi
    expect_rejection 'READ COMMITTED' 22023 'invalid personal merge projection context request' "${bad_issuer_query}"
    for isolation in 'READ UNCOMMITTED' 'REPEATABLE READ' SERIALIZABLE; do
      expect_rejection "${isolation}" 0A000 "${expected_message}" "${bad_issuer_query}"
    done
  fi

  # A legal RC read returns the original exact document and adds one viewed row for each source.
  local before_business before_audits document
  before_business="$(business_state)"
  before_audits="$(workspace_audit_state "${workspace_id}")"
  document="$(run_psql --tuples-only --no-align --command="${runtime_query}" | tail -n 1)"
  [[ "${document}" == "${expected_document}" ]] || {
    echo "${kind}: RC wrapper returned a changed document." >&2
    printf 'expected: %s\nactual: %s\n' "${expected_document}" "${document}" >&2
    exit 1
  }
  [[ "${before_business}" == "$(business_state)" ]] || { echo "${kind}: RC read changed non-audit business state." >&2; exit 1; }
  assert_only_two_source_views "${before_audits}" "$(workspace_audit_state "${workspace_id}")" "${workspace_id}" "${app_user_id}" "${first_target}" "${second_target}" "${kind} RC"

  # Establish an old RR snapshot, commit a real project switch, then read through the runtime API.
  mkfifo "${temporary_directory}/${kind}.fifo"
  "${psql_base[@]}" --quiet --tuples-only --no-align <"${temporary_directory}/${kind}.fifo" \
    >"${temporary_directory}/${kind}.out" 2>&1 &
  reader_pid=$!
  exec 3>"${temporary_directory}/${kind}.fifo"
  printf '%s\n%s\n' \
    "BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT 'SNAPSHOT|' || project_id FROM app_data.user_current_projects WHERE app_user_id='${app_user_id}'::uuid;" \
    '\echo SNAPSHOT_READY' >&3
  for _ in $(seq 1 200); do
    grep -q '^SNAPSHOT_READY$' "${temporary_directory}/${kind}.out" && break
    sleep 0.05
  done
  if ! grep -q '^SNAPSHOT_READY$' "${temporary_directory}/${kind}.out" || ! grep -q "^SNAPSHOT|${project_id}$" "${temporary_directory}/${kind}.out"; then
    echo "${kind}: failed to establish old project RR snapshot." >&2
    sed -n '1,80p' "${temporary_directory}/${kind}.out" >&2
    exit 1
  fi
  run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('${issuer}','${subject}','${other_project}');" >/dev/null
  selected_project="$(run_psql --tuples-only --no-align --command="SELECT project_id FROM app_data.user_current_projects WHERE app_user_id='${app_user_id}'::uuid;" | tr -d '[:space:]')"
  [[ "${selected_project}" == "${other_project}" ]] || { echo "${kind}: normal API did not commit project switch." >&2; exit 1; }
  local switched_full_state switched_business_state switched_events
  switched_full_state="$(full_state)"
  switched_business_state="$(business_state)"
  switched_events="$(workspace_audit_state "${workspace_id}")"
  printf 'SET ROLE tongxingzhe_runtime;\n%s\nCOMMIT;\n\\q\n' "${query}" >&3
  exec 3>&-
  local reader_status=0 error_line stale_document
  wait "${reader_pid}" || reader_status=$?
  reader_pid=''
  error_line="$(sed -n '/^ERROR:/p' "${temporary_directory}/${kind}.out" | head -n 1)"
  if [[ "${baseline_mode}" == '1' ]]; then
    stale_document="$(sed -n '/^{/p' "${temporary_directory}/${kind}.out" | tail -n 1)"
    if [[ "${reader_status}" -ne 0 || "${stale_document}" != "${expected_document}" ]]; then
      echo "${kind}: baseline RR did not return original stale document." >&2
      sed -n '1,100p' "${temporary_directory}/${kind}.out" >&2
      exit 1
    fi
    [[ "${switched_business_state}" == "$(business_state)" ]] || { echo "${kind}: baseline RR changed non-audit state." >&2; exit 1; }
    assert_only_two_source_views "${switched_events}" "$(workspace_audit_state "${workspace_id}")" "${workspace_id}" "${app_user_id}" "${first_target}" "${second_target}" "${kind} baseline RR"
    echo "RED 0151 ${kind}: old RR snapshot returned original document after normal committed project switch and added exactly two source viewed audits."
  else
    if [[ "${reader_status}" -eq 0 || "${error_line}" != "ERROR:  0A000: ${expected_message}" ]]; then
      echo "${kind}: stale RR expected exact 0A000 before audit, status ${reader_status}: ${error_line}" >&2
      sed -n '1,100p' "${temporary_directory}/${kind}.out" >&2
      exit 1
    fi
    [[ "${switched_full_state}" == "$(full_state)" ]] || { echo "${kind}: rejected stale RR changed database state or audits." >&2; exit 1; }
    echo "GREEN 0152 ${kind}: stale RR after normal project switch rejected with exact 0A000 and no state/audit change."
  fi

  # A fresh RC request for the former project must be denied without state changes.
  local fresh_before fresh_status=0 fresh_error
  fresh_before="$(full_state)"
  run_psql --quiet --command="${runtime_query}" >"${temporary_directory}/${kind}-fresh.out" 2>&1 || fresh_status=$?
  fresh_error="$(sed -n '/^ERROR:/p' "${temporary_directory}/${kind}-fresh.out" | head -n 1)"
  if [[ "${fresh_status}" -eq 0 || "${fresh_error}" != 'ERROR:  42501: personal merge projection context is forbidden' ]]; then
    echo "${kind}: fresh RC expected exact 42501, status ${fresh_status}: ${fresh_error}" >&2
    sed -n '/^ERROR:/p' "${temporary_directory}/${kind}-fresh.out" >&2
    exit 1
  fi
  [[ "${fresh_before}" == "$(full_state)" ]] || { echo "${kind}: fresh RC denial changed state/audits." >&2; exit 1; }
  echo "CONTROL ${kind}: fresh RC old-project request returned exact 42501 with full state unchanged."
}

check_endpoint split
check_endpoint directory
if [[ "${baseline_mode}" == '1' ]]; then
  echo 'Baseline RED complete; run only against 0151 clone.'
else
  echo '0152 audited split-plan and directory isolation checks passed.'
fi
