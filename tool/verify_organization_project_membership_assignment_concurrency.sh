#!/usr/bin/env bash
set -euo pipefail

# Commits synthetic facts. Run once in a fresh, dedicated test database.
: "${DATABASE_URL:?请设置专用 synthetic 测试库 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"
run_psql() { "${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 "$@"; }
temporary_directory="$(mktemp -d)"
child_pids=()
cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*.out "${temporary_directory}"/*.fifo
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock() {
  local application_name="$1" granted="$2" child_pid="$3" output_file="$4" lock_name="$5"
  local observed
  for _ in $(seq 1 100); do
    observed="$(run_psql --tuples-only --no-align --command="
      WITH key AS (SELECT hashtextextended('${lock_name}',0) AS value)
      SELECT activity.pid FROM pg_stat_activity AS activity
      JOIN pg_locks AS lock_row ON lock_row.pid = activity.pid CROSS JOIN key
      WHERE activity.application_name = '${application_name}'
        AND lock_row.locktype = 'advisory' AND lock_row.granted = ${granted}
        AND lock_row.classid::bigint = ((key.value >> 32) & 4294967295)
        AND lock_row.objid::bigint = (key.value & 4294967295) AND lock_row.objsubid = 1;")"
    if [[ "${observed}" =~ ^[0-9]+$ ]]; then
      echo "${application_name}: PostgreSQL PID ${observed}, exact advisory granted=${granted}"
      return
    fi
    if ! kill -0 "${child_pid}" >/dev/null 2>&1; then
      sed -n '1,160p' "${output_file}" >&2
      echo "并发会话过早退出：${application_name}" >&2; exit 1
    fi
    # Polling interval only. Holder COMMIT is sent only after the exact wait.
    sleep 0.05
  done
  sed -n '1,160p' "${output_file}" >&2
  echo "未观察到精确 advisory lock：${application_name} / ${lock_name}" >&2; exit 1
}

wait_for_user_row() {
  local phase="$1" child_pid="$2" output_file="$3" observed
  for _ in $(seq 1 100); do
    observed="$(run_psql --tuples-only --no-align --command="
      SELECT holder.pid || ' -> ' || waiter.pid FROM pg_stat_activity AS holder
      JOIN pg_locks AS held ON held.pid = holder.pid AND held.locktype = 'transactionid'
        AND held.mode = 'ExclusiveLock' AND held.granted
      JOIN pg_locks AS waiting ON waiting.transactionid = held.transactionid
        AND waiting.locktype = 'transactionid' AND waiting.mode = 'ShareLock' AND NOT waiting.granted
      JOIN pg_stat_activity AS waiter ON waiter.pid = waiting.pid
      WHERE holder.application_name = '0096-${phase}-holder'
        AND waiter.application_name = '0096-${phase}-waiter'
        AND holder.pid = ANY(pg_blocking_pids(waiter.pid));")"
    if [[ "${observed}" =~ ^[0-9]+\ \-\>\ [0-9]+$ ]]; then
      echo "0096-${phase}: row-first linearization; exact transactionid blocker/waiter PID ${observed}"
      return
    fi
    if ! kill -0 "${child_pid}" >/dev/null 2>&1; then
      sed -n '1,160p' "${output_file}" >&2; exit 1
    fi
    sleep 0.05
  done
  sed -n '1,160p' "${output_file}" >&2
  echo "未观察到精确 user-row transactionid 等待：${phase}" >&2; exit 1
}

race() {
  local phase="$1" holder_sql="$2" waiter_sql="$3" lock_name="$4"
  local expected_state="${5:-}" expected_message="${6:-}"
  local wait_resource="${7:-advisory}"
  local holder_output="${temporary_directory}/${phase}-holder.out"
  local waiter_output="${temporary_directory}/${phase}-waiter.out"
  local holder_pid waiter_pid holder_fd holder_status=0 waiter_status=0
  mkfifo "${temporary_directory}/${phase}.fifo"
  PGAPPNAME="0096-${phase}-holder" run_psql --quiet --set=VERBOSITY=verbose \
    <"${temporary_directory}/${phase}.fifo" >"${holder_output}" 2>&1 &
  holder_pid=$!; child_pids+=("${holder_pid}")
  exec {holder_fd}>"${temporary_directory}/${phase}.fifo"
  printf 'BEGIN; %s\n' "${holder_sql}" >&"${holder_fd}"
  wait_for_lock "0096-${phase}-holder" true "${holder_pid}" "${holder_output}" "${lock_name}"
  PGAPPNAME="0096-${phase}-waiter" run_psql --quiet --set=VERBOSITY=verbose \
    --command="BEGIN; ${waiter_sql} COMMIT;" >"${waiter_output}" 2>&1 &
  waiter_pid=$!; child_pids+=("${waiter_pid}")
  if [[ "${wait_resource}" == 'user-row' ]]; then
    wait_for_user_row "${phase}" "${waiter_pid}" "${waiter_output}"
  else
    wait_for_lock "0096-${phase}-waiter" false "${waiter_pid}" "${waiter_output}" "${lock_name}"
  fi
  printf 'COMMIT;\n' >&"${holder_fd}"
  exec {holder_fd}>&-
  wait "${holder_pid}" || holder_status=$?
  wait "${waiter_pid}" || waiter_status=$?
  if [[ "${holder_status}" -ne 0 ]] \
    || [[ -z "${expected_state}" && "${waiter_status}" -ne 0 ]] \
    || [[ -n "${expected_state}" && "${waiter_status}" -eq 0 ]]; then
    sed -n '1,160p' "${holder_output}" "${waiter_output}" >&2
    echo "0096 错误串行结果：${phase}" >&2; exit 1
  fi
  if [[ -n "${expected_state}" ]] && {
    ! grep -Fq "${expected_state}" "${waiter_output}" \
      || ! grep -Fq "${expected_message}" "${waiter_output}"; }; then
    sed -n '1,160p' "${waiter_output}" >&2
    echo "0096 错误 SQLSTATE/message：${phase}" >&2; exit 1
  fi
}

owner_id='96000000-0096-4000-8000-000000000001'
target_low='96000000-0096-4000-8000-000000000000'
target_high='96000000-0096-4000-8000-000000000002'
run_psql --quiet --command="INSERT INTO app_data.app_users(app_user_id,status) VALUES
  ('${owner_id}','active'),('${target_low}','active'),('${target_high}','active');"

index=0
for phase in archive-first-empty assignment-first-empty \
  archive-first-history-low assignment-first-history-low \
  archive-first-history-high assignment-first-history-high \
  parent-first assignment-first-parent replay other-actor tombstone-first assignment-first-tombstone; do
  index=$((index + 1))
  suffix="$(printf '%012d' "${index}")"
  request_id="96000000-0096-5000-8000-${suffix}"
  project_id="96000000-0096-4300-8000-${suffix}"
  parent_id="96000000-0096-4200-8000-${suffix}"
  target_id="${target_high}"
  if [[ "${phase}" == *-low ]]; then target_id="${target_low}"; fi
  workspace_id="$(run_psql --tuples-only --no-align --command="
    SELECT organization_workspace_id FROM app_private.create_organization_v1(
      '${owner_id}',gen_random_uuid(),'0096 concurrency ${phase}');")"
  run_psql --quiet --command="
    INSERT INTO app_data.organization_memberships VALUES
      ('${parent_id}','${workspace_id}','${target_id}',clock_timestamp()-interval '1 year',NULL);
    INSERT INTO app_data.projects(project_id,workspace_id,display_name)
      VALUES ('${project_id}','${workspace_id}','0096 concurrency ${phase}');"
  assignment_sql="SELECT * FROM app_private.assign_organization_project_member_v1(
    '${owner_id}','${request_id}','${workspace_id}','${project_id}','${parent_id}');"
  archive_sql="UPDATE app_data.projects SET status = 'archived' WHERE project_id = '${project_id}';"
  parent_sql="UPDATE app_data.organization_memberships SET inactive_from_utc = clock_timestamp()
    WHERE organization_membership_id = '${parent_id}';"
  request_lock="organization-project-membership-assignment-request:${request_id}"
  status_lock="management-follow-up-consent-opt-in:${project_id}"
  governance_lock="organization-governance:${workspace_id}"
  expected_children=1
  if [[ "${phase}" == *history* ]]; then
    # The status trigger must discover BOTH owner and target in both UUID
    # orders, including ended project history; neither history is resurrected.
    run_psql --quiet --command="
      INSERT INTO app_data.project_memberships
      SELECT gen_random_uuid(),organization_membership_id,'${project_id}',active_from_utc,clock_timestamp()
      FROM app_data.organization_memberships
      WHERE organization_workspace_id = '${workspace_id}';"
    first_user="${owner_id}"
    if [[ "${target_id}" < "${owner_id}" ]]; then first_user="${target_id}"; fi
    status_lock="organization-membership:${workspace_id}:${first_user}"
  fi
  case "${phase}" in
    archive-first-*)
      race "${phase}" "${archive_sql}" "${assignment_sql}" "${status_lock}" \
        42501 'organization project membership assignment forbidden'
      expected_children=0 ;;
    assignment-first-empty|assignment-first-history-*)
      race "${phase}" "${assignment_sql}" "${archive_sql}" "${status_lock}" ;;
    parent-first)
      # 0085's parent mutation trigger locks target user before governance.
      # The actual first wait is a row/XID fence, not an advisory lock.
      race "${phase}" "${parent_sql}" "${assignment_sql}" "${governance_lock}" \
        42501 'organization project membership assignment forbidden' user-row
      expected_children=0 ;;
    assignment-first-parent)
      race "${phase}" "${assignment_sql}" "${parent_sql}" "${governance_lock}" \
        55000 'close project memberships before organization membership' user-row ;;
    replay)
      race "${phase}" "${assignment_sql}" "${assignment_sql}" "${request_lock}"
      # Byte-for-byte typed historical values, no second success audit.
      run_psql --quiet --command="DO \$check\$
        DECLARE receipt record; claim record;
        BEGIN
          SELECT * INTO receipt FROM app_private.assign_organization_project_member_v1(
            '${owner_id}','${request_id}','${workspace_id}','${project_id}','${parent_id}');
          SELECT * INTO claim FROM app_private.organization_project_membership_assignment_request_claims
            WHERE request_id = '${request_id}';
          IF receipt.project_membership_id IS DISTINCT FROM claim.project_membership_id
            OR receipt.active_from_utc IS DISTINCT FROM claim.active_from_utc
            OR receipt.inactive_from_utc IS DISTINCT FROM claim.inactive_from_utc
          THEN RAISE EXCEPTION '0096 concurrent replay receipt changed'; END IF;
        END \$check\$;" ;;
    other-actor)
      race "${phase}" "${assignment_sql}" "${assignment_sql//${owner_id}/${target_id}}" "${request_lock}" \
        42501 'organization project membership assignment forbidden' ;;
    tombstone-first|assignment-first-tombstone)
      tombstone_sql="SELECT pg_advisory_xact_lock(hashtextextended('${request_lock}',0));
        INSERT INTO app_private.organization_project_membership_assignment_request_tombstones
        VALUES ('organization-project-membership-assignment:v1','${request_id}');"
      if [[ "${phase}" == 'tombstone-first' ]]; then
        race "${phase}" "${tombstone_sql}" "${assignment_sql}" "${request_lock}" \
          22023 'organization project membership assignment idempotency conflict'
        expected_children=0
      else
        race "${phase}" "${assignment_sql}" "${tombstone_sql}" "${request_lock}"
      fi ;;
  esac
  run_psql --quiet --command="DO \$check\$
    BEGIN
      IF (SELECT count(*) FROM app_private.organization_project_membership_assignment_request_claims
            WHERE request_id = '${request_id}') <> ${expected_children}
        OR (SELECT count(*) FROM app_private.organization_project_membership_assignment_audit_events
            WHERE request_id = '${request_id}') <> ${expected_children}
        OR (SELECT count(*) FROM app_data.project_memberships
            WHERE project_id = '${project_id}' AND inactive_from_utc IS NULL) <> ${expected_children}
        OR EXISTS (SELECT 1 FROM app_data.management_report_capability_grants AS g
          JOIN app_data.project_memberships AS m USING(project_membership_id)
          WHERE m.project_id = '${project_id}')
      THEN RAISE EXCEPTION '0096 unexpected member/claim/audit/grant facts: ${phase}'; END IF;
      IF '${phase}' LIKE '%history%' AND
        (SELECT count(*) FROM app_data.project_memberships WHERE project_id = '${project_id}'
          AND inactive_from_utc IS NOT NULL) <> 2
      THEN RAISE EXCEPTION '0096 ended history changed: ${phase}'; END IF;
      IF '${phase}' LIKE 'archive-first-%' OR '${phase}' LIKE 'assignment-first-history-%'
        OR '${phase}' = 'assignment-first-empty' THEN
        IF (SELECT status FROM app_data.projects WHERE project_id = '${project_id}') <> 'archived'
        THEN RAISE EXCEPTION '0096 archive did not commit: ${phase}'; END IF;
      END IF;
    END \$check\$;"
done

# Transfer preserves the existing active-owner invariant. Recovery and the
# original actor's ownership loss do not invalidate its historical receipt.
run_psql --quiet <<'SQL'
DO $check$
DECLARE claim app_private.organization_project_membership_assignment_request_claims%ROWTYPE;
BEGIN
  SELECT * INTO STRICT claim FROM app_private.organization_project_membership_assignment_request_claims
  WHERE request_id = '96000000-0096-5000-8000-000000000009';
  PERFORM * FROM app_private.transfer_organization_owner_v1(claim.actor_app_user_id,
    gen_random_uuid(),claim.organization_workspace_id,claim.organization_membership_id);
  UPDATE app_data.workspaces SET deleted_at = clock_timestamp() WHERE workspace_id = claim.organization_workspace_id;
END
$check$;
SQL
run_psql --quiet <<'SQL'
DO $check$
DECLARE claim app_private.organization_project_membership_assignment_request_claims%ROWTYPE; receipt record;
BEGIN
  SELECT * INTO STRICT claim FROM app_private.organization_project_membership_assignment_request_claims
  WHERE request_id = '96000000-0096-5000-8000-000000000009';
  SELECT * INTO STRICT receipt FROM app_private.assign_organization_project_member_v1(
    claim.actor_app_user_id,claim.request_id,claim.organization_workspace_id,claim.project_id,claim.organization_membership_id);
  IF receipt.project_membership_id IS DISTINCT FROM claim.project_membership_id
    OR receipt.active_from_utc IS DISTINCT FROM claim.active_from_utc
    OR EXISTS (SELECT 1 FROM pg_locks WHERE pid = pg_backend_pid() AND locktype = 'advisory'
      AND (classid::bigint,objid::bigint) IS DISTINCT FROM (
        (hashtextextended('organization-project-membership-assignment-request:'||claim.request_id::text,0)>>32)&4294967295,
        hashtextextended('organization-project-membership-assignment-request:'||claim.request_id::text,0)&4294967295))
  THEN RAISE EXCEPTION '0096 replay changed history or took write hierarchy locks'; END IF;
END
$check$;
SQL
echo '0096 ordinary project membership exact advisory/PID races passed (synthetic only).'
