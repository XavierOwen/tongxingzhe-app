#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
child_pids=()
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
  echo "未观察到真实 fence blocker：${waiter_app} 应被 ${blocker_app} 阻塞。" >&2
  sed -n '1,100p' "${output_path}" >&2
  exit 1
}

start_gate() {
  local gate="$1" gate_app="$2"
  mkfifo "${temporary_directory}/gate.fifo"
  PGAPPNAME="${gate_app}" "${psql_base[@]}" <"${temporary_directory}/gate.fifo" \
    >"${temporary_directory}/gate.out" 2>&1 &
  gate_pid=$!
  child_pids+=("${gate_pid}")
  exec 3>"${temporary_directory}/gate.fifo"
  printf "SELECT pg_advisory_lock(hashtextextended('%s', 0));\n" "${gate}" >&3
  for _ in $(seq 1 100); do
    local held
    held="$(run_psql --tuples-only --no-align --command="
      SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('${gate}', 0))
        THEN NOT pg_advisory_unlock(hashtextextended('${gate}', 0))
        ELSE true END;
    " | tr -d '[:space:]')"
    [[ "${held}" == 't' ]] && return
    sleep 0.05
  done
  echo "无法取得 race gate：${gate}" >&2
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
issuer='https://0115-relationship-generation.example.test/auth/v1'
subject="0115-relationship-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
  WHERE is_current;
" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id <<<"${context}"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo '0115 race 无法取得个人项目上下文。' >&2
  exit 1
fi

create_pair() {
  local label="$1" suffix="$2" first second institution preview_id
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0115 ${label} first ${run_token}',
      '+1 312 555 0115', 'same-0115@example.test',
      '0115-${run_token}-${suffix}a'
    );
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '0115 ${label} second ${run_token}',
      '+1 312 555 0115', 'same-0115@example.test',
      '0115-${run_token}-${suffix}b'
    );
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'institution', '0115 ${label} institution ${run_token}', NULL, NULL,
      '0115-${run_token}-${suffix}i'
    );
  " >/dev/null
  IFS='|' read -r first second institution <<<"$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT first_target.promotion_target_id,
           second_target.promotion_target_id,
           institution_target.promotion_target_id
    FROM app_data.promotion_targets AS first_target
    JOIN app_data.promotion_targets AS second_target
      ON second_target.workspace_id = first_target.workspace_id
     AND second_target.display_name = '0115 ${label} second ${run_token}'
    JOIN app_data.promotion_targets AS institution_target
      ON institution_target.workspace_id = first_target.workspace_id
     AND institution_target.display_name = '0115 ${label} institution ${run_token}'
    WHERE first_target.workspace_id = '${workspace_id}'::uuid
      AND first_target.display_name = '0115 ${label} first ${run_token}';
  " | tr -d '[:space:]')"
  preview_id="$(run_psql --tuples-only --no-align --command="
    SELECT preview.preview_id
    FROM app_data.preview_personal_target_pair_v1(
      '${issuer}', '${subject}', '${project_id}'::uuid,
      '${first}'::uuid, '${second}'::uuid
    ) AS preview;
  " | tr -d '[:space:]')"
  printf '%s|%s|%s|%s\n' "${first}" "${second}" "${institution}" "${preview_id}"
}

create_relation() {
  local person_id="$1" institution_id="$2" mutation_id="$3"
  run_psql --quiet --command="
    SET ROLE tongxingzhe_runtime;
    SELECT result FROM app_data.create_target_institution_relationship(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      '${person_id}'::uuid, '${institution_id}'::uuid,
      'membership_affiliation', '0115 concurrency', '${mutation_id}'
    );
    RESET ROLE;
  " >/dev/null
}

activate_sql() {
  local preview_id="$1"
  printf "SELECT app_private.activate_personal_target_merge_generation_v1('%s'::uuid, '%s'::uuid, '%s'::uuid);" \
    "${app_user_id}" "${project_id}" "${preview_id}"
}

run_race() {
  local label="$1" holder_kind="$2" preview_id="$3" writer_sql="$4"
  local result_sql="$5" expected_waiter_status="${6:-0}" error_text="${7:-}"
  local gate="0115-fence-${run_token}-${label}"
  local gate_app="0115-gate-${label}" holder_app="0115-holder-${label}" waiter_app="0115-waiter-${label}"
  local holder_output="${temporary_directory}/${label}-holder.out" waiter_output="${temporary_directory}/${label}-waiter.out"
  gate_name="${gate}"
  start_gate "${gate}" "${gate_app}"
  if [[ "${holder_kind}" == 'activation' ]]; then
    PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
      BEGIN;
      $(activate_sql "${preview_id}");
      SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
      COMMIT;
    " >"${holder_output}" 2>&1 &
  else
    PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
      BEGIN;
      ${writer_sql}
      SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
      COMMIT;
    " >"${holder_output}" 2>&1 &
  fi
  local holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_exact_blocker "${holder_app}" "${gate_app}" "${holder_output}"
  if [[ "${holder_kind}" == 'activation' ]]; then
    PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="${writer_sql}" \
      >"${waiter_output}" 2>&1 &
  else
    PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="$(activate_sql "${preview_id}")" \
      >"${waiter_output}" 2>&1 &
  fi
  local waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_exact_blocker "${waiter_app}" "${holder_app}" "${waiter_output}"
  release_gate

  local holder_status=0 waiter_status=0
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 || "${waiter_status}" -ne "${expected_waiter_status}" ]]; then
    echo "${label} race failed: holder=${holder_status}, waiter=${waiter_status}" >&2
    sed -n '1,100p' "${holder_output}" >&2
    sed -n '1,100p' "${waiter_output}" >&2
    exit 1
  fi
  if [[ -n "${error_text}" ]] && ! grep -q "${error_text}" "${waiter_output}"; then
    echo "${label} waiter failed for an unexpected reason." >&2
    sed -n '1,100p' "${waiter_output}" >&2
    exit 1
  fi
  local result
  result="$(run_psql --tuples-only --no-align --command="${result_sql}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || {
    echo "${label} ended in an incomplete binding or partial mutation: ${result}" >&2
    exit 1
  }
  echo "${label}: blocker, waiter, and full transaction result verified"
}

IFS='|' read -r create_activation_person create_activation_peer create_activation_institution create_activation_preview \
  <<<"$(create_pair create-activation-first 1)"
IFS='|' read -r create_writer_person create_writer_peer create_writer_institution create_writer_preview \
  <<<"$(create_pair create-writer-first 2)"
IFS='|' read -r end_activation_person end_activation_peer end_activation_institution end_activation_preview \
  <<<"$(create_pair end-activation-first 3)"
IFS='|' read -r end_writer_person end_writer_peer end_writer_institution end_writer_preview \
  <<<"$(create_pair end-writer-first 4)"
IFS='|' read -r anon_activation_person anon_activation_peer anon_activation_institution anon_activation_preview \
  <<<"$(create_pair anonymize-activation-first 5)"
IFS='|' read -r anon_writer_person anon_writer_peer anon_writer_institution anon_writer_preview \
  <<<"$(create_pair anonymize-writer-first 6)"

create_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.create_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${create_activation_person}'::uuid, '${create_activation_institution}'::uuid, 'membership_affiliation', '0115 race', '0115-${run_token}-create-activation'); RESET ROLE;"
run_race create-activation-first activation "${create_activation_preview}" "${create_writer_sql}" \
  "SELECT relation.person_merge_generation_id = active.generation_id AND relation.institution_merge_generation_id IS NULL AND revision.person_merge_generation_id = active.generation_id AND revision.institution_merge_generation_id IS NULL FROM app_data.promotion_target_institution_relationships relation JOIN app_private.personal_target_merge_active_members_v1 active ON active.promotion_target_id = relation.person_target_id JOIN app_data.promotion_target_institution_relation_revisions revision USING (relationship_id) WHERE relation.person_target_id = '${create_activation_person}'::uuid AND relation.institution_target_id = '${create_activation_institution}'::uuid AND revision.event_type = 'created';"

create_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.create_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${create_writer_person}'::uuid, '${create_writer_institution}'::uuid, 'membership_affiliation', '0115 race', '0115-${run_token}-create-writer'); RESET ROLE;"
run_race create-writer-first writer "${create_writer_preview}" "${create_writer_sql}" \
  "SELECT relation.person_merge_generation_id IS NULL AND relation.institution_merge_generation_id IS NULL AND revision.person_merge_generation_id IS NULL AND revision.institution_merge_generation_id IS NULL AND EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id = '${create_writer_person}'::uuid) FROM app_data.promotion_target_institution_relationships relation JOIN app_data.promotion_target_institution_relation_revisions revision USING (relationship_id) WHERE relation.person_target_id = '${create_writer_person}'::uuid AND relation.institution_target_id = '${create_writer_institution}'::uuid AND revision.event_type = 'created';"

create_relation "${end_activation_person}" "${end_activation_institution}" "0115-${run_token}-end-activation-create"
end_relationship_id="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${end_activation_person}'::uuid AND institution_target_id='${end_activation_institution}'::uuid;" | tr -d '[:space:]')"
end_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.end_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_relationship_id}'::uuid, 1, '0115-${run_token}-end-activation'); RESET ROLE;"
run_race end-activation-first activation "${end_activation_preview}" "${end_writer_sql}" \
  "SELECT relation.person_merge_generation_id IS NULL AND revision_one.person_merge_generation_id IS NULL AND revision_two.person_merge_generation_id = active.generation_id AND revision_two.institution_merge_generation_id IS NULL FROM app_data.promotion_target_institution_relationships relation JOIN app_private.personal_target_merge_active_members_v1 active ON active.promotion_target_id = relation.person_target_id JOIN app_data.promotion_target_institution_relation_revisions revision_one ON revision_one.relationship_id = relation.relationship_id AND revision_one.revision_number = 1 JOIN app_data.promotion_target_institution_relation_revisions revision_two ON revision_two.relationship_id = relation.relationship_id AND revision_two.revision_number = 2 WHERE relation.relationship_id = '${end_relationship_id}'::uuid;"

create_relation "${end_writer_person}" "${end_writer_institution}" "0115-${run_token}-end-writer-create"
end_relationship_id="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${end_writer_person}'::uuid AND institution_target_id='${end_writer_institution}'::uuid;" | tr -d '[:space:]')"
end_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.end_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_relationship_id}'::uuid, 1, '0115-${run_token}-end-writer'); RESET ROLE;"
run_race end-writer-first writer "${end_writer_preview}" "${end_writer_sql}" \
  "SELECT relation.person_merge_generation_id IS NULL AND revision_one.person_merge_generation_id IS NULL AND revision_two.person_merge_generation_id IS NULL AND EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id = relation.person_target_id) FROM app_data.promotion_target_institution_relationships relation JOIN app_data.promotion_target_institution_relation_revisions revision_one ON revision_one.relationship_id = relation.relationship_id AND revision_one.revision_number = 1 JOIN app_data.promotion_target_institution_relation_revisions revision_two ON revision_two.relationship_id = relation.relationship_id AND revision_two.revision_number = 2 WHERE relation.relationship_id = '${end_relationship_id}'::uuid;"

create_relation "${anon_activation_person}" "${anon_activation_institution}" "0115-${run_token}-anon-activation-create"
anon_relationship_id="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${anon_activation_person}'::uuid AND institution_target_id='${anon_activation_institution}'::uuid;" | tr -d '[:space:]')"
run_psql --quiet --command="INSERT INTO app_data.promotion_target_project_relationships (promotion_target_id, project_id, current_stage, established_by_app_user_id) VALUES ('${anon_activation_person}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid); SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${anon_activation_person}'::uuid, 1, 2, 'active', 'keep this note', 'progress_update', NULL, '0115-${run_token}-anon-note', NULL); RESET ROLE;" >/dev/null
anon_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${anon_activation_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-anon-activation'); RESET ROLE;"
run_race anonymize-activation-first activation "${anon_activation_preview}" "${anon_writer_sql}" \
  "SELECT target.status = 'active' AND target.anonymized_at IS NULL AND assignment.ended_at IS NULL AND project_relation.current_follow_up_note = 'keep this note' AND institution_relation.ended_at IS NULL AND NOT EXISTS (SELECT 1 FROM app_data.promotion_target_retention_events WHERE mutation_id = '0115-${run_token}-anon-activation') FROM app_data.promotion_targets target JOIN app_data.promotion_target_assignments assignment USING (promotion_target_id) JOIN app_data.promotion_target_project_relationships project_relation USING (promotion_target_id) JOIN app_data.promotion_target_institution_relationships institution_relation ON institution_relation.relationship_id = '${anon_relationship_id}'::uuid JOIN app_private.personal_target_merge_active_members_v1 active USING (promotion_target_id) WHERE target.promotion_target_id = '${anon_activation_person}'::uuid;" \
  1 'active merge member cannot be anonymized'

create_relation "${anon_writer_person}" "${anon_writer_institution}" "0115-${run_token}-anon-writer-create"
anon_relationship_id="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${anon_writer_person}'::uuid AND institution_target_id='${anon_writer_institution}'::uuid;" | tr -d '[:space:]')"
run_psql --quiet --command="INSERT INTO app_data.promotion_target_project_relationships (promotion_target_id, project_id, current_stage, established_by_app_user_id) VALUES ('${anon_writer_person}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid); SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${anon_writer_person}'::uuid, 1, 2, 'active', 'keep this note', 'progress_update', NULL, '0115-${run_token}-anon-writer-note', NULL); RESET ROLE;" >/dev/null
anon_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${anon_writer_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-anon-writer'); RESET ROLE;"
run_race anonymize-writer-first writer "${anon_writer_preview}" "${anon_writer_sql}" \
  "SELECT target.status = 'anonymized' AND target.anonymized_at IS NOT NULL AND assignment.ended_at IS NOT NULL AND project_relation.current_follow_up_note IS NULL AND institution_relation.ended_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM app_private.personal_target_merge_active_members_v1 WHERE promotion_target_id = target.promotion_target_id) AND (SELECT count(*) FROM app_data.promotion_target_retention_events WHERE mutation_id = '0115-${run_token}-anon-writer') = 1 FROM app_data.promotion_targets target JOIN app_data.promotion_target_assignments assignment USING (promotion_target_id) JOIN app_data.promotion_target_project_relationships project_relation USING (promotion_target_id) JOIN app_data.promotion_target_institution_relationships institution_relation ON institution_relation.relationship_id = '${anon_relationship_id}'::uuid WHERE target.promotion_target_id = '${anon_writer_person}'::uuid;" \
  1 'personal target merge generation activation is forbidden'

run_api_first_anonymize_race() {
  local label="$1" writer_sql="$2" result_sql="$3" anon_sql="$4"
  local gate="0115-api-first-${run_token}-${label}"
  local gate_app="0115-gate-${label}" holder_app="0115-holder-${label}" waiter_app="0115-waiter-${label}"
  local holder_output="${temporary_directory}/${label}-holder.out" waiter_output="${temporary_directory}/${label}-waiter.out"
  gate_name="${gate}"
  start_gate "${gate}" "${gate_app}"
  PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
    BEGIN;
    ${writer_sql}
    SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
    COMMIT;
  " >"${holder_output}" 2>&1 &
  local holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_exact_blocker "${holder_app}" "${gate_app}" "${holder_output}"
  PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="${anon_sql}" \
    >"${waiter_output}" 2>&1 &
  local waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_exact_blocker "${waiter_app}" "${holder_app}" "${waiter_output}"
  release_gate

  local holder_status=0 waiter_status=0 result
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 || "${waiter_status}" -ne 0 ]]; then
    echo "${label} relation/anonymize race failed: holder=${holder_status}, waiter=${waiter_status}" >&2
    sed -n '1,100p' "${holder_output}" >&2
    sed -n '1,100p' "${waiter_output}" >&2
    exit 1
  fi
  result="$(run_psql --tuples-only --no-align --command="${result_sql}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || {
    echo "${label} did not linearize completely: ${result}" >&2
    exit 1
  }
  echo "${label}: API writer acquired the fence first and linearized before anonymization"
}

run_create_vs_anonymize_race() {
  local person_id="$1" institution_id="$2"
  local gate="0115-create-anonymize-${run_token}"
  local gate_app='0115-gate-create-anonymize'
  local holder_app='0115-holder-create-anonymize'
  local waiter_app='0115-waiter-create-anonymize'
  local holder_output="${temporary_directory}/create-anonymize-holder.out"
  local waiter_output="${temporary_directory}/create-anonymize-waiter.out"
  local relation_id holder_status=0 waiter_status=0
  gate_name="${gate}"
  start_gate "${gate}" "${gate_app}"
  PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
    BEGIN;
    SELECT pg_advisory_xact_lock(hashtextextended(
      '${app_user_id}:0115-${run_token}-create-anonymize-create', 0
    ));
    SELECT pg_advisory_xact_lock(hashtextextended(
      '${workspace_id}:${person_id}:${institution_id}:membership_affiliation', 0
    ));
    UPDATE app_private.personal_target_merge_generation_fence_v1
    SET epoch = epoch + 1 WHERE fence_key;
    SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
    SET ROLE tongxingzhe_runtime;
    SELECT result FROM app_data.create_target_institution_relationship(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      '${person_id}'::uuid, '${institution_id}'::uuid,
      'membership_affiliation', '0115 create/anonymize race',
      '0115-${run_token}-create-anonymize-create'
    );
    RESET ROLE;
    COMMIT;
  " >"${holder_output}" 2>&1 &
  local holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_exact_blocker "${holder_app}" "${gate_app}" "${holder_output}"

  PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="
    SET ROLE tongxingzhe_runtime;
    SELECT result FROM app_data.apply_promotion_target_retention_action(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      '${person_id}'::uuid, 'anonymize', 'withdrawal',
      '0115-${run_token}-create-anonymize-anon'
    );
    RESET ROLE;
  " >"${waiter_output}" 2>&1 &
  local waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_exact_blocker "${waiter_app}" "${holder_app}" "${waiter_output}"
  release_gate
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?

  if [[ "${holder_status}" -ne 0 || "${waiter_status}" -ne 0 ]]; then
    echo "create/anonymize fence-first race failed: holder=${holder_status}, waiter=${waiter_status}" >&2
    sed -n '1,100p' "${holder_output}" >&2
    sed -n '1,100p' "${waiter_output}" >&2
    exit 1
  fi
  relation_id="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${person_id}'::uuid AND institution_target_id='${institution_id}'::uuid;" | tr -d '[:space:]')"
  local result
  result="$(run_psql --tuples-only --no-align --command="
    SELECT target.status = 'anonymized'
      AND relation.ended_at IS NOT NULL
      AND relation.role_description = '[已匿名化]'
      AND revision_count = 2
    FROM app_data.promotion_targets AS target
    JOIN app_data.promotion_target_institution_relationships AS relation
      ON relation.relationship_id = '${relation_id}'::uuid
    CROSS JOIN LATERAL (
      SELECT count(*) AS revision_count
      FROM app_data.promotion_target_institution_relation_revisions
      WHERE relationship_id = relation.relationship_id
    ) AS revisions
    WHERE target.promotion_target_id = '${person_id}'::uuid;
  " | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || {
    echo "create/anonymize did not linearize completely: ${result}" >&2
    exit 1
  }
  echo 'create/anonymize: fence-first writer and anonymization linearized without deadlock'
}

run_anonymize_first_writer_race() {
  local label="$1" anon_sql="$2" writer_sql="$3" result_sql="$4" expected_error="$5"
  local gate="0115-anon-first-${run_token}-${label}"
  local gate_app="0115-gate-${label}" holder_app="0115-holder-${label}" waiter_app="0115-waiter-${label}"
  local holder_output="${temporary_directory}/${label}-holder.out" waiter_output="${temporary_directory}/${label}-waiter.out"
  gate_name="${gate}"
  start_gate "${gate}" "${gate_app}"
  PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
    BEGIN;
    ${anon_sql}
    SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
    COMMIT;
  " >"${holder_output}" 2>&1 &
  local holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_exact_blocker "${holder_app}" "${gate_app}" "${holder_output}"
  PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="${writer_sql}" \
    >"${waiter_output}" 2>&1 &
  local waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_exact_blocker "${waiter_app}" "${holder_app}" "${waiter_output}"
  release_gate

  local holder_status=0 waiter_status=0 result
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 || "${waiter_status}" -eq 0 ]] \
    || ! grep -q "${expected_error}" "${waiter_output}"; then
    echo "${label} reauthorization race failed: holder=${holder_status}, waiter=${waiter_status}" >&2
    sed -n '1,100p' "${holder_output}" >&2
    sed -n '1,100p' "${waiter_output}" >&2
    exit 1
  fi
  result="$(run_psql --tuples-only --no-align --command="${result_sql}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || {
    echo "${label} left a partial write after anonymization: ${result}" >&2
    exit 1
  }
  echo "${label}: post-fence authorization rejected stale writer without partial history"
}

run_mutation_advisory_activation_time_race() {
  local label="$1" preview_id="$2" mutation_id="$3" writer_sql="$4" result_sql="$5"
  local gate="0115-activation-time-${run_token}-${label}"
  local gate_app="0115-gate-${label}" holder_app="0115-holder-${label}" waiter_app="0115-waiter-${label}"
  local holder_output="${temporary_directory}/${label}-holder.out" waiter_output="${temporary_directory}/${label}-waiter.out"
  gate_name="${gate}"
  start_gate "${gate}" "${gate_app}"
  PGAPPNAME="${holder_app}" "${psql_base[@]}" --quiet --command="
    BEGIN;
    SELECT pg_advisory_xact_lock(hashtextextended(
      '${app_user_id}:${mutation_id}', 0
    ));
    SELECT pg_advisory_xact_lock(hashtextextended('${gate}', 0));
    COMMIT;
  " >"${holder_output}" 2>&1 &
  local holder_pid=$!
  child_pids+=("${holder_pid}")
  wait_for_exact_blocker "${holder_app}" "${gate_app}" "${holder_output}"
  PGAPPNAME="${waiter_app}" "${psql_base[@]}" --quiet --command="${writer_sql}" \
    >"${waiter_output}" 2>&1 &
  local waiter_pid=$!
  child_pids+=("${waiter_pid}")
  wait_for_exact_blocker "${waiter_app}" "${holder_app}" "${waiter_output}"

  # The API call is still blocked on its matching mutation advisory. Activate
  # the person pair in a separate committed transaction before releasing it.
  run_psql --quiet --command="$(activate_sql "${preview_id}")" >/dev/null
  release_gate

  local holder_status=0 waiter_status=0 result
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 || "${waiter_status}" -ne 0 ]]; then
    echo "${label} activation-time race failed: holder=${holder_status}, waiter=${waiter_status}" >&2
    sed -n '1,100p' "${holder_output}" >&2
    sed -n '1,100p' "${waiter_output}" >&2
    exit 1
  fi
  result="$(run_psql --tuples-only --no-align --command="${result_sql}" | tr -d '[:space:]')"
  [[ "${result}" == 't' ]] || {
    echo "${label} timestamps predate activation: ${result}" >&2
    exit 1
  }
  echo "${label}: API waited on mutation advisory through activation; event timestamps follow generation activation"
}

IFS='|' read -r end_row_first_person end_row_first_peer end_row_first_institution _ \
  <<<"$(create_pair end-row-first 7)"
create_relation "${end_row_first_person}" "${end_row_first_institution}" "0115-${run_token}-end-row-first-create"
end_row_first_relationship="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${end_row_first_person}'::uuid AND institution_target_id='${end_row_first_institution}'::uuid;" | tr -d '[:space:]')"
end_row_first_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.end_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_row_first_relationship}'::uuid, 1, '0115-${run_token}-end-row-first'); RESET ROLE;"
end_row_first_anon_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_row_first_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-end-row-first-anon'); RESET ROLE;"
run_api_first_anonymize_race end-api-first \
  "${end_row_first_sql}" \
  "SELECT target.status = 'anonymized' AND relation.ended_at IS NOT NULL AND relation.role_description = '[已匿名化]' AND revision_count = 2 FROM app_data.promotion_targets target JOIN app_data.promotion_target_institution_relationships relation ON relation.relationship_id = '${end_row_first_relationship}'::uuid CROSS JOIN LATERAL (SELECT count(*) AS revision_count FROM app_data.promotion_target_institution_relation_revisions WHERE relationship_id = relation.relationship_id) counts WHERE target.promotion_target_id = '${end_row_first_person}'::uuid;" \
  "${end_row_first_anon_sql}"

IFS='|' read -r project_row_first_person project_row_first_peer project_row_first_institution _ \
  <<<"$(create_pair project-row-first 8)"
run_psql --quiet --command="INSERT INTO app_data.promotion_target_project_relationships (promotion_target_id, project_id, current_stage, established_by_app_user_id) VALUES ('${project_row_first_person}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid);" >/dev/null
project_update_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${project_row_first_person}'::uuid, 1, 2, 'active', 'race note', 'progress_update', NULL, '0115-${run_token}-project-row-first', NULL); RESET ROLE;"
project_row_first_anon_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${project_row_first_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-project-row-first-anon'); RESET ROLE;"
run_api_first_anonymize_race project-api-first \
  "${project_update_sql}" \
  "SELECT target.status = 'anonymized' AND relation.current_lifecycle_status = 'ended' AND relation.current_follow_up_note IS NULL AND revision_count = 3 FROM app_data.promotion_targets target JOIN app_data.promotion_target_project_relationships relation USING (promotion_target_id) CROSS JOIN LATERAL (SELECT count(*) AS revision_count FROM app_data.promotion_target_relationship_revisions WHERE promotion_target_id = relation.promotion_target_id AND project_id = relation.project_id) counts WHERE target.promotion_target_id = '${project_row_first_person}'::uuid;" \
  "${project_row_first_anon_sql}"

IFS='|' read -r create_anonymize_person create_anonymize_peer create_anonymize_institution _ \
  <<<"$(create_pair create-anonymize 9)"
run_create_vs_anonymize_race "${create_anonymize_person}" "${create_anonymize_institution}"

IFS='|' read -r end_anon_first_person end_anon_first_peer end_anon_first_institution _ \
  <<<"$(create_pair end-anonymize-first 10)"
create_relation "${end_anon_first_person}" "${end_anon_first_institution}" "0115-${run_token}-end-anon-first-create"
end_anon_first_relationship="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${end_anon_first_person}'::uuid AND institution_target_id='${end_anon_first_institution}'::uuid;" | tr -d '[:space:]')"
end_anon_first_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.end_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_anon_first_relationship}'::uuid, 1, '0115-${run_token}-end-anon-first-writer'); RESET ROLE;"
end_anon_first_anon_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_anon_first_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-end-anon-first-anon'); RESET ROLE;"
run_anonymize_first_writer_race end-anonymize-first \
  "${end_anon_first_anon_sql}" "${end_anon_first_sql}" \
  "SELECT target.status = 'anonymized' AND relation.ended_at IS NOT NULL AND relation.role_description = '[已匿名化]' AND relation.current_revision = 2 AND (SELECT count(*) FROM app_data.promotion_target_institution_relation_revisions WHERE relationship_id = relation.relationship_id) = 2 FROM app_data.promotion_targets target JOIN app_data.promotion_target_institution_relationships relation ON relation.relationship_id = '${end_anon_first_relationship}'::uuid WHERE target.promotion_target_id = '${end_anon_first_person}'::uuid;" \
  '42501'

IFS='|' read -r project_anon_first_person project_anon_first_peer project_anon_first_institution _ \
  <<<"$(create_pair project-anonymize-first 11)"
run_psql --quiet --command="INSERT INTO app_data.promotion_target_project_relationships (promotion_target_id, project_id, current_stage, established_by_app_user_id) VALUES ('${project_anon_first_person}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid);" >/dev/null
project_anon_first_writer_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.update_promotion_target_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${project_anon_first_person}'::uuid, 1, 2, 'active', 'stale note', 'progress_update', NULL, '0115-${run_token}-project-anon-first-writer', NULL); RESET ROLE;"
project_anon_first_anon_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${project_anon_first_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-project-anon-first-anon'); RESET ROLE;"
run_anonymize_first_writer_race project-anonymize-first \
  "${project_anon_first_anon_sql}" "${project_anon_first_writer_sql}" \
  "SELECT target.status = 'anonymized' AND relation.current_follow_up_note IS NULL AND relation.current_revision = 2 AND (SELECT count(*) FROM app_data.promotion_target_relationship_revisions WHERE promotion_target_id = relation.promotion_target_id AND project_id = relation.project_id) = 2 FROM app_data.promotion_targets target JOIN app_data.promotion_target_project_relationships relation USING (promotion_target_id) WHERE target.promotion_target_id = '${project_anon_first_person}'::uuid;" \
  '42501'

IFS='|' read -r generic_anon_first_person generic_anon_first_peer generic_anon_first_institution _ \
  <<<"$(create_pair generic-fact-anonymize-first 12)"
generic_fact_anon_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.apply_promotion_target_retention_action('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${generic_anon_first_person}'::uuid, 'anonymize', 'withdrawal', '0115-${run_token}-generic-fact-anon-first-anon'); RESET ROLE;"
generic_fact_writer_sql="INSERT INTO app_data.promotion_target_project_relationships (promotion_target_id, project_id, current_stage, established_by_app_user_id) VALUES ('${generic_anon_first_person}'::uuid, '${project_id}'::uuid, 1, '${app_user_id}'::uuid);"
run_anonymize_first_writer_race generic-fact-anonymize-first \
  "${generic_fact_anon_sql}" "${generic_fact_writer_sql}" \
  "SELECT target.status = 'anonymized' AND NOT EXISTS (SELECT 1 FROM app_data.promotion_target_project_relationships WHERE promotion_target_id = target.promotion_target_id AND project_id = '${project_id}'::uuid) AND NOT EXISTS (SELECT 1 FROM app_data.promotion_target_relationship_revisions WHERE promotion_target_id = target.promotion_target_id AND project_id = '${project_id}'::uuid) FROM app_data.promotion_targets target WHERE target.promotion_target_id = '${generic_anon_first_person}'::uuid;" \
  '22023'

IFS='|' read -r create_activation_time_person create_activation_time_peer create_activation_time_institution create_activation_time_preview \
  <<<"$(create_pair create-activation-time 13)"
create_activation_time_mutation="0115-${run_token}-create-activation-time"
create_activation_time_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.create_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${create_activation_time_person}'::uuid, '${create_activation_time_institution}'::uuid, 'membership_affiliation', 'activation timestamp race', '${create_activation_time_mutation}'); RESET ROLE;"
run_mutation_advisory_activation_time_race create-activation-time \
  "${create_activation_time_preview}" "${create_activation_time_mutation}" \
  "${create_activation_time_sql}" \
  "SELECT relation.started_at >= generation.activated_at_utc AND created_revision.changed_at >= generation.activated_at_utc AND relation.person_merge_generation_id = generation.generation_id AND created_revision.person_merge_generation_id = generation.generation_id FROM app_data.promotion_target_institution_relationships relation JOIN app_private.personal_target_merge_active_members_v1 active_member ON active_member.promotion_target_id = relation.person_target_id JOIN app_private.personal_target_merge_generations_v1 generation USING (generation_id) JOIN app_data.promotion_target_institution_relation_revisions created_revision USING (relationship_id) WHERE relation.person_target_id = '${create_activation_time_person}'::uuid AND relation.institution_target_id = '${create_activation_time_institution}'::uuid AND created_revision.event_type = 'created';"

IFS='|' read -r end_activation_time_person end_activation_time_peer end_activation_time_institution end_activation_time_preview \
  <<<"$(create_pair end-activation-time 14)"
create_relation "${end_activation_time_person}" "${end_activation_time_institution}" "0115-${run_token}-end-activation-time-create"
end_activation_time_relationship="$(run_psql --tuples-only --no-align --command="SELECT relationship_id FROM app_data.promotion_target_institution_relationships WHERE person_target_id='${end_activation_time_person}'::uuid AND institution_target_id='${end_activation_time_institution}'::uuid;" | tr -d '[:space:]')"
end_activation_time_mutation="0115-${run_token}-end-activation-time"
end_activation_time_sql="SET ROLE tongxingzhe_runtime; SELECT result FROM app_data.end_target_institution_relationship('${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, '${end_activation_time_relationship}'::uuid, 1, '${end_activation_time_mutation}'); RESET ROLE;"
run_mutation_advisory_activation_time_race end-activation-time \
  "${end_activation_time_preview}" "${end_activation_time_mutation}" \
  "${end_activation_time_sql}" \
  "SELECT relation.ended_at >= generation.activated_at_utc AND ended_revision.changed_at >= generation.activated_at_utc AND ended_revision.person_merge_generation_id = generation.generation_id FROM app_data.promotion_target_institution_relationships relation JOIN app_private.personal_target_merge_active_members_v1 active_member ON active_member.promotion_target_id = relation.person_target_id JOIN app_private.personal_target_merge_generations_v1 generation USING (generation_id) JOIN app_data.promotion_target_institution_relation_revisions ended_revision USING (relationship_id) WHERE relation.relationship_id = '${end_activation_time_relationship}'::uuid AND ended_revision.event_type = 'ended';"

echo '0115 relationship create/end/anonymize activation and row-lock ordering races passed.'
