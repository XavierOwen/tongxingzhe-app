#!/usr/bin/env bash

set -euo pipefail

# Independent PostgreSQL sessions prove activation and fact writers serialize
# on the 0114 merge-generation fence, in both transaction orderings.
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
gate_name=''
gate_pid=''
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

wait_for_exact_blocker() {
  local waiter_app="$1" blocker_app="$2" output_path="$3" pair
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="
      SELECT waiting.pid || '|' || blocker.pid
      FROM pg_catalog.pg_stat_activity AS waiting
      JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiting.pid)) AS blocked(pid)
        ON true
      JOIN pg_catalog.pg_stat_activity AS blocker ON blocker.pid = blocked.pid
      WHERE waiting.application_name = '${waiter_app}'
        AND waiting.wait_event_type = 'Lock'
        AND blocker.application_name = '${blocker_app}'
      LIMIT 1;
    " | tr -d '[:space:]')"
    if [[ "${pair}" == *'|'* ]]; then
      echo "${waiter_app}: waiter/blocker PID ${pair}"
      return
    fi
    sleep 0.05
  done
  echo "未观察到精确的 PostgreSQL blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
  sed -n '1,120p' "${output_path}" >&2
  exit 1
}

start_gate() {
  gate_name="$1" gate_app="$2"
  mkfifo "${temporary_directory}/gate.fifo"
  PGAPPNAME="${gate_app}" "${psql_base[@]}" <"${temporary_directory}/gate.fifo" \
    >"${temporary_directory}/gate.out" 2>&1 &
  gate_pid=$!
  child_pids+=("${gate_pid}")
  exec 3>"${temporary_directory}/gate.fifo"
  printf "SELECT pg_advisory_lock(hashtextextended('%s', 0));\n" "${gate_name}" >&3
  for _ in $(seq 1 100); do
    local held
    held="$(run_psql --tuples-only --no-align --command="
      SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('${gate_name}', 0))
        THEN NOT pg_advisory_unlock(hashtextextended('${gate_name}', 0))
        ELSE true END;
    " | tr -d '[:space:]')"
    [[ "${held}" == 't' ]] && return
    sleep 0.05
  done
  echo "无法取得 0114 race gate：${gate_name}" >&2
  exit 1
}

release_gate() {
  printf "SELECT pg_advisory_unlock(hashtextextended('%s', 0));\n\\q\n" \
    "${gate_name}" >&3
  exec 3>&-
  wait "${gate_pid}"
  rm -f "${temporary_directory}/gate.fifo"
  gate_name=''
  gate_pid=''
}

run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7d540000-0114-generation-fence.example.test/auth/v1'
subject="7d550000-0114-generation-fence-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id, questionnaire_version_id
  FROM app_data.list_personal_project_contexts(
    '${issuer}', '${subject}'
  )
  WHERE is_current;
")"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id \
  <<<"$(tr -d '[:space:]' <<<"${context}")"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${project_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${questionnaire_version_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo '0114 merge-generation fixture 无法取得 personal project context。' >&2
  exit 1
fi

create_pair() {
  local label="$1" suffix="$2" first second preview_id
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0114 ${label} first ${run_token}',
      '+1 312 555 0114', 'generation-fence@example.test',
      '7d560000-0114-${run_token}-${suffix}a'
    );
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0114 ${label} second ${run_token}',
      '+1 312 555 0114', 'generation-fence@example.test',
      '7d560000-0114-${run_token}-${suffix}b'
    );
  " >/dev/null
  IFS='|' read -r first second <<<"$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT first_target.promotion_target_id, second_target.promotion_target_id
    FROM app_data.promotion_targets AS first_target
    JOIN app_data.promotion_targets AS second_target
      ON second_target.workspace_id = first_target.workspace_id
    WHERE first_target.workspace_id = '${workspace_id}'::uuid
      AND first_target.display_name = '0114 ${label} first ${run_token}'
      AND second_target.display_name = '0114 ${label} second ${run_token}';
  " | tr -d '[:space:]')"
  if [[ ! "${first}" =~ ^[0-9a-f-]{36}$ || ! "${second}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "0114 ${label} fixture 未能创建目标 pair。" >&2
    exit 1
  fi
  preview_id="$(run_psql --tuples-only --no-align --command="
    SELECT preview.preview_id
    FROM app_data.preview_personal_target_pair_v1(
      '${issuer}', '${subject}', '${project_id}'::uuid,
      '${first}'::uuid, '${second}'::uuid
    ) AS preview;
  " | tr -d '[:space:]')"
  if [[ ! "${preview_id}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "0114 ${label} fixture 未能取得有效 preview receipt。" >&2
    exit 1
  fi
  printf '%s|%s|%s\n' "${first}" "${second}" "${preview_id}"
}

IFS='|' read -r contact_activation_first contact_activation_second contact_activation_preview \
  <<<"$(create_pair contact-activation-first 1)"
IFS='|' read -r contact_writer_first contact_writer_second contact_writer_preview \
  <<<"$(create_pair contact-writer-first 2)"
IFS='|' read -r relation_activation_first relation_activation_second relation_activation_preview \
  <<<"$(create_pair relation-activation-first 3)"
IFS='|' read -r relation_writer_first relation_writer_second relation_writer_preview \
  <<<"$(create_pair relation-writer-first 4)"

create_contact_revision() {
  local suffix="$1" contact_id="0114-fence-${run_token}-${1}"
  run_psql --quiet --command="
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      channel, location_kind, reach_count, interest_level
    ) VALUES (
      '${contact_id}', '${app_user_id}'::uuid, '${workspace_id}'::uuid,
      '${project_id}'::uuid, '${questionnaire_version_id}'::uuid,
      clock_timestamp(), 'UTC', 'instant_text', 'not_applicable', 1, 0
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revised_by_app_user_id, snapshot
    ) VALUES (
      '${contact_id}', 1, '${app_user_id}'::uuid, '{}'::jsonb
    );
  " >/dev/null
  printf '%s' "${contact_id}"
}

insert_contact_link_sql() {
  local contact_id="$1" target_id="$2"
  printf "INSERT INTO app_data.contact_target_links (\n  contact_id, revision_number, promotion_target_id, follow_up_consent,\n  institution_representative_confirmed, confirmed_project_entry\n) VALUES ('%s', 1, '%s'::uuid, 'unknown', false, false);" \
    "${contact_id}" "${target_id}"
}

create_relation() {
  local target_id="$1"
  run_psql --quiet --command="
    INSERT INTO app_data.promotion_target_project_relationships (
      promotion_target_id, project_id, current_stage, established_by_app_user_id
    ) VALUES (
      '${target_id}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid
    );
  " >/dev/null
}

activate_sql() {
  local preview_id="$1"
  printf "SELECT app_private.activate_personal_target_merge_generation_v1(\n  '%s'::uuid, '%s'::uuid, '%s'::uuid\n);" \
    "${app_user_id}" "${project_id}" "${preview_id}"
}

run_race() {
  local label="$1" holder_kind="$2" preview_id="$3" writer_sql="$4" result_sql="$5"
  local expected_waiter_status="${6:-0}" revocation_sql="${7:-}" holder_finish=COMMIT
  local gate="0114-fence-${run_token}-${label}"
  local gate_app="0114-gate-${label}" holder_app="0114-holder-${label}" waiter_app="0114-waiter-${label}"
  local holder_output="${temporary_directory}/${label}-holder.out" waiter_output="${temporary_directory}/${label}-waiter.out"

  start_gate "${gate}" "${gate_app}"
  if [[ "${holder_kind}" == 'activation' ]]; then
    PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
      BEGIN ISOLATION LEVEL READ COMMITTED;
      $(activate_sql "${preview_id}");
      SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
      COMMIT;
    " >"${holder_output}" 2>&1 &
  else
    if [[ -n "${revocation_sql}" ]]; then holder_finish=ROLLBACK; fi
    PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
      BEGIN ISOLATION LEVEL READ COMMITTED;
      ${writer_sql}
      SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
      ${holder_finish};
    " >"${holder_output}" 2>&1 &
  fi
  local holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_exact_blocker "${holder_app}" "${gate_app}" "${holder_output}"

  if [[ "${holder_kind}" == 'activation' ]]; then
    PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="${writer_sql}" \
      >"${waiter_output}" 2>&1 &
  else
    PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="
      BEGIN ISOLATION LEVEL READ COMMITTED;
      $(activate_sql "${preview_id}")
      COMMIT;
    " >"${waiter_output}" 2>&1 &
  fi
  local waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_exact_blocker "${waiter_app}" "${holder_app}" "${waiter_output}"
  if [[ -n "${revocation_sql}" ]]; then
    run_psql --quiet --command="${revocation_sql}" >/dev/null
  fi
  release_gate

  local holder_status=0 waiter_status=0
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 \
    || "${waiter_status}" -ne "${expected_waiter_status}" ]]; then
    echo "${label} race failed: holder=${holder_status}, waiter=${waiter_status}" >&2
    sed -n '1,120p' "${holder_output}" >&2
    sed -n '1,120p' "${waiter_output}" >&2
    exit 1
  fi
  if [[ "${expected_waiter_status}" -ne 0 ]] \
    && ! grep -q '^ERROR:  42501: personal target merge generation activation is forbidden$' \
      "${waiter_output}"; then
    echo "${label} waiter failed for an unexpected reason." >&2
    sed -n '1,120p' "${waiter_output}" >&2
    exit 1
  fi

  local result
  result="$(run_psql --tuples-only --no-align --command="${result_sql}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || {
    echo "${label} ended in partial or unbound-after-activation state: ${result}" >&2
    exit 1
  }
  echo "${label}: complete transaction ordering verified"
}

contact_activation_contact="$(create_contact_revision activation-first)"
contact_writer_contact="$(create_contact_revision writer-first)"
contact_activation_writer="$(insert_contact_link_sql "${contact_activation_contact}" "${contact_activation_first}")"
contact_writer_writer="$(insert_contact_link_sql "${contact_writer_contact}" "${contact_writer_first}")"

run_race contact-activation-first activation "${contact_activation_preview}" \
  "BEGIN; ${contact_activation_writer}; COMMIT;" \
  "SELECT count(*) = 1 AND bool_and(link.merge_generation_id = active.generation_id) FROM app_data.contact_target_links link JOIN app_private.personal_target_merge_active_members_v1 active USING (promotion_target_id) WHERE link.contact_id = '${contact_activation_contact}';"

# The committed link advances retention time, so its earlier receipt is stale.
run_race contact-writer-first writer "${contact_writer_preview}" \
  "${contact_writer_writer}" \
  "SELECT (SELECT count(*) = 1 AND bool_and(link.merge_generation_id IS NULL) FROM app_data.contact_target_links link WHERE link.contact_id = '${contact_writer_contact}') AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 active WHERE active.promotion_target_id IN ('${contact_writer_first}'::uuid, '${contact_writer_second}'::uuid));" \
  1

create_relation "${relation_activation_first}"
create_relation "${relation_writer_first}"
relation_activation_writer="$(printf "SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship('%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid, 1, 2, 'active', NULL, 'progress_update', NULL, '0114-%s-activation', NULL); RESET ROLE;" \
  "${app_user_id}" "${workspace_id}" "${project_id}" "${relation_activation_first}" "${run_token}")"
relation_writer_writer="$(printf "SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship('%s'::uuid, '%s'::uuid, '%s'::uuid, '%s'::uuid, 1, 2, 'active', NULL, 'progress_update', NULL, '0114-%s-writer', NULL); RESET ROLE;" \
  "${app_user_id}" "${workspace_id}" "${project_id}" "${relation_writer_first}" "${run_token}")"

run_race relationship-activation-first activation "${relation_activation_preview}" \
  "BEGIN; ${relation_activation_writer}; COMMIT;" \
  "SELECT relation_row.current_revision = 2 AND revision_one.merge_generation_id IS NULL AND revision_two.merge_generation_id = active.generation_id FROM app_data.promotion_target_project_relationships relation_row JOIN app_data.promotion_target_relationship_revisions revision_one ON revision_one.promotion_target_id = relation_row.promotion_target_id AND revision_one.project_id = relation_row.project_id AND revision_one.revision_number = 1 JOIN app_data.promotion_target_relationship_revisions revision_two ON revision_two.promotion_target_id = relation_row.promotion_target_id AND revision_two.project_id = relation_row.project_id AND revision_two.revision_number = 2 JOIN app_private.personal_target_merge_active_members_v1 active ON active.promotion_target_id = relation_row.promotion_target_id WHERE relation_row.promotion_target_id = '${relation_activation_first}'::uuid AND relation_row.merge_generation_id IS NULL;"

run_race relationship-writer-first writer "${relation_writer_preview}" \
  "${relation_writer_writer}" \
  "SELECT relation_row.current_revision = 2 AND bool_and(revision_row.merge_generation_id IS NULL) FROM app_data.promotion_target_project_relationships relation_row JOIN app_data.promotion_target_relationship_revisions revision_row USING (promotion_target_id, project_id) JOIN app_private.personal_target_merge_active_members_v1 active ON active.promotion_target_id = relation_row.promotion_target_id WHERE relation_row.promotion_target_id = '${relation_writer_first}'::uuid AND relation_row.merge_generation_id IS NULL GROUP BY relation_row.current_revision;"

echo '0114 activation/contact/project relationship fence races passed.'

snapshot_definition="$(cat "$(dirname "${BASH_SOURCE[0]}")/../backend/database/fixtures/shared/database_state.sql")"
business_state() {
  run_psql --quiet --tuples-only --no-align \
    --command="${snapshot_definition} SELECT pg_temp.fixture_database_state();"
}

IFS='|' read -r isolation_first isolation_second isolation_preview <<<"$(create_pair isolation 5)"
statement="$(activate_sql "${isolation_preview}")"
before_state="$(business_state)"
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  status=0
  run_psql --quiet --command="BEGIN ISOLATION LEVEL ${isolation}; ${statement} COMMIT;" \
    >"${temporary_directory}/isolation.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/{p;q;}' "${temporary_directory}/isolation.out")"
  if [[ "${status}" -eq 0 || "${error_line}" != 'ERROR:  0A000: legacy personal target merge generation activation requires read committed' ]]; then
    printf '0148 first activation in %s expected exact 0A000, got exit %s\n' "${isolation}" "${status}" >&2
    cat "${temporary_directory}/isolation.out" >&2
    exit 1
  fi
  if [[ "$(business_state)" != "${before_state}" ]]; then
    printf '0148 first activation in %s changed business state\n' "${isolation}" >&2
    exit 1
  fi
done

generation="$(run_psql --quiet --tuples-only --no-align \
  --command="BEGIN ISOLATION LEVEL READ COMMITTED; ${statement} COMMIT;")"
[[ "${generation}" =~ ^[0-9a-f-]{36}$ ]]
[[ "$(run_psql --quiet --tuples-only --no-align --command="
  SELECT EXISTS (SELECT 1 FROM app_private.personal_target_merge_generations_v1
    WHERE generation_id='${generation}' AND created_by_app_user_id='${app_user_id}' AND workspace_id='${workspace_id}')
  AND (SELECT count(*)=2 FROM app_private.personal_target_merge_active_members_v1
    WHERE generation_id='${generation}' AND promotion_target_id IN ('${isolation_first}','${isolation_second}'));
")" == 't' ]] || { echo '0148 READ COMMITTED did not activate the same pair.' >&2; exit 1; }

IFS='|' read -r revoked_first revoked_second revoked_preview <<<"$(create_pair account-revocation 6)"
revoked_assignment="$(run_psql --quiet --tuples-only --no-align --command="
  SELECT first_assignment_id FROM app_private.personal_target_pair_preview_receipts WHERE preview_id='${revoked_preview}';
")"
[[ "${revoked_assignment}" =~ ^[0-9a-f-]{36}$ ]]
deletion_request="$(run_psql --quiet --tuples-only --no-align --command='SELECT gen_random_uuid();')"
generation_count="$(run_psql --quiet --tuples-only --no-align --command="
  SELECT count(*) FROM app_private.personal_target_merge_generations_v1 WHERE created_by_app_user_id='${app_user_id}';
")"

# The assignment end holds the actual fence but rolls back its update. Account
# deletion commits independently before activation can proceed on that fence.
run_race account-revocation writer "${revoked_preview}" \
  "SELECT app_data.end_personal_target_assignment_v1('${app_user_id}','${workspace_id}','${project_id}','${revoked_assignment}');" \
  "SELECT EXISTS (
    SELECT 1 FROM app_data.app_users u
    JOIN app_private.account_deletion_current c USING (app_user_id)
    JOIN app_private.account_deletion_request_claims r ON r.request_id=c.deletion_request_id
    JOIN app_private.account_deletion_audit_events a ON a.request_id=r.request_id AND a.deletion_request_id=c.deletion_request_id
    WHERE u.app_user_id='${app_user_id}' AND u.status='deletion_pending' AND c.status='deletion_pending'
      AND r.request_id='${deletion_request}' AND r.actor_app_user_id=u.app_user_id
      AND r.deletion_request_id=c.deletion_request_id AND r.effective_at_utc=c.effective_at_utc
      AND r.purge_after_utc=c.purge_after_utc
      AND a.operation='account-deletion-request:v1' AND a.occurred_at_utc=c.effective_at_utc
  ) AND (SELECT count(*)=${generation_count} FROM app_private.personal_target_merge_generations_v1 WHERE created_by_app_user_id='${app_user_id}')
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_generation_members_v1 WHERE promotion_target_id IN ('${revoked_first}','${revoked_second}'))
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id IN ('${revoked_first}','${revoked_second}'))
  AND EXISTS (SELECT 1 FROM app_data.promotion_target_assignments WHERE assignment_id='${revoked_assignment}' AND ended_at IS NULL)
  AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_assignment_end_events_v1 WHERE assignment_id='${revoked_assignment}');" \
  1 "BEGIN ISOLATION LEVEL READ COMMITTED; SELECT * FROM app_private.request_account_deletion_v1('${app_user_id}','${deletion_request}'); COMMIT;"

echo '0148 legacy activation passed three first-call isolation cases, READ COMMITTED activation, and the real account revocation race.'
