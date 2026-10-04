#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=60000 -c lock_timeout=45000"

psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
child_pids=()
cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then kill -TERM "${pid}" >/dev/null 2>&1 || true; fi
  done
  for pid in "${child_pids[@]}"; do wait "${pid}" >/dev/null 2>&1 || true; done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock_holder() {
  local lock_name="$1" holder_pid="$2" holder_output="$3" found
  for _ in $(seq 1 100); do
    found="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row
        WHERE lock_row.locktype = 'advisory' AND lock_row.granted
          AND lock_row.database = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND lock_row.classid::bigint = ((hashtextextended('${lock_name}', 0) >> 32) & 4294967295)
          AND lock_row.objid::bigint = (hashtextextended('${lock_name}', 0) & 4294967295)
          AND lock_row.objsubid = 1
      );
    " | tr -d '[:space:]')"
    [[ "${found}" == 't' ]] && return
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then sed -n '1,120p' "${holder_output}" >&2; exit 1; fi
    sleep 0.05
  done
  sed -n '1,120p' "${holder_output}" >&2
  echo "没有观察到 ready lock：${lock_name}" >&2
  exit 1
}

wait_for_governance_waiter() {
  local workspace_id="$1" waiter_pid="$2" waiter_output="$3" lock_name="organization-governance:$1" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row
        WHERE lock_row.locktype = 'advisory' AND NOT lock_row.granted
          AND lock_row.database = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND lock_row.classid::bigint = ((hashtextextended('${lock_name}', 0) >> 32) & 4294967295)
          AND lock_row.objid::bigint = (hashtextextended('${lock_name}', 0) & 4294967295)
          AND lock_row.objsubid = 1
      );
    " | tr -d '[:space:]')"
    [[ "${waiting}" == 't' ]] && return
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then sed -n '1,120p' "${waiter_output}" >&2; exit 1; fi
    sleep 0.05
  done
  sed -n '1,120p' "${waiter_output}" >&2
  echo "没有观察到治理锁等待：${workspace_id}" >&2
  exit 1
}

run_race() {
  local label="$1" workspace_id="$2" first_sql="$3" second_sql="$4"
  local expected_state="$5" expected_message="$6" hold_seconds="$7"
  local ready_lock="0105-ready:${label}" first_output="${temporary_directory}/${label}-first.out"
  local second_output="${temporary_directory}/${label}-second.out" first_pid second_pid first_status=0 second_status=0
  run_psql --quiet --command="BEGIN; ${first_sql}; SELECT pg_advisory_lock(hashtextextended('${ready_lock}',0)); SELECT pg_sleep(${hold_seconds}); COMMIT;" >"${first_output}" 2>&1 &
  first_pid=$!; child_pids+=("${first_pid}")
  wait_for_lock_holder "${ready_lock}" "${first_pid}" "${first_output}"
  run_psql --quiet --command="BEGIN; ${second_sql}; COMMIT;" >"${second_output}" 2>&1 &
  second_pid=$!; child_pids+=("${second_pid}")
  wait_for_governance_waiter "${workspace_id}" "${second_pid}" "${second_output}"
  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?
  if [[ "${first_status}" -ne 0 || "${second_status}" -eq 0 ]] \
    || ! grep -Fq "${expected_state}: ${expected_message}" "${second_output}"; then
    echo "${label} 并发结果不符合预期。" >&2
    sed -n '1,160p' "${first_output}" "${second_output}" >&2
    exit 1
  fi
}

due_workspace='00000000-0507-5000-8000-000000000001'
restore_workspace='00000000-0507-5000-8000-000000000002'
owner_one='00000000-0507-0000-8000-000000000001'
owner_two='00000000-0507-0000-8000-000000000002'
due_request='00000000-0507-4000-8000-000000000001'
restore_request='00000000-0507-4000-8000-000000000002'

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.app_users(app_user_id,status) VALUES ('$owner_one','active'),('$owner_two','active');
  INSERT INTO app_data.workspaces(workspace_id,workspace_kind,display_name,deleted_at)
  VALUES ('$due_workspace','organization','0105 due-first race',NULL),
    ('$restore_workspace','organization','0105 restore-first race',NULL);
  INSERT INTO app_data.organization_memberships(organization_membership_id,organization_workspace_id,app_user_id,active_from_utc,inactive_from_utc)
  VALUES ('00000000-0507-2000-8000-000000000001','$due_workspace','$owner_one',transaction_timestamp(),NULL),
    ('00000000-0507-2000-8000-000000000002','$restore_workspace','$owner_two',transaction_timestamp(),NULL);
  INSERT INTO app_data.organization_owner_assignments(organization_owner_assignment_id,organization_membership_id,active_from_utc,inactive_from_utc)
  VALUES ('00000000-0507-3000-8000-000000000001','00000000-0507-2000-8000-000000000001',transaction_timestamp(),NULL),
    ('00000000-0507-3000-8000-000000000002','00000000-0507-2000-8000-000000000002',transaction_timestamp(),NULL);
  UPDATE app_data.workspaces SET deleted_at=transaction_timestamp()-interval '721 hours'
  WHERE workspace_id='$due_workspace';
  INSERT INTO app_private.organization_deletion_current(organization_workspace_id,deletion_request_id,effective_at_utc,purge_after_utc,status,restored_at_utc)
  SELECT '$due_workspace','$due_request',workspace.deleted_at,workspace.deleted_at+interval '720 hours','deletion_pending',NULL
  FROM app_data.workspaces AS workspace WHERE workspace.workspace_id='$due_workspace';
  UPDATE app_private.organization_deletion_current SET effective_at_utc=transaction_timestamp()-interval '721 hours',
    purge_after_utc=transaction_timestamp()-interval '1 hour' WHERE organization_workspace_id='$due_workspace';
  UPDATE app_data.workspaces AS workspace SET deleted_at=attempt.effective_at_utc
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id='$due_workspace' AND workspace.workspace_id=attempt.organization_workspace_id;
  UPDATE app_data.workspaces SET deleted_at=transaction_timestamp()+interval '30 seconds'-interval '720 hours'
  WHERE workspace_id='$restore_workspace';
  INSERT INTO app_private.organization_deletion_current(organization_workspace_id,deletion_request_id,effective_at_utc,purge_after_utc,status,restored_at_utc)
  SELECT '$restore_workspace','$restore_request',workspace.deleted_at,workspace.deleted_at+interval '720 hours','deletion_pending',NULL
  FROM app_data.workspaces AS workspace WHERE workspace.workspace_id='$restore_workspace';
  UPDATE app_data.workspaces AS workspace SET deleted_at=attempt.effective_at_utc
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id='$restore_workspace' AND workspace.workspace_id=attempt.organization_workspace_id;
  INSERT INTO app_private.organization_deletion_request_claims(
    request_id,actor_app_user_id,organization_workspace_id,deletion_request_id,
    effective_at_utc,purge_after_utc)
  SELECT attempt.deletion_request_id,
    CASE attempt.organization_workspace_id
      WHEN '$due_workspace'::uuid THEN '$owner_one'::uuid
      ELSE '$owner_two'::uuid END,
    attempt.organization_workspace_id,attempt.deletion_request_id,
    attempt.effective_at_utc,attempt.purge_after_utc
  FROM app_private.organization_deletion_current AS attempt
  WHERE attempt.organization_workspace_id IN ('$due_workspace','$restore_workspace');
  COMMIT;
"

run_race due-first "${due_workspace}" \
  "SELECT app_private.mark_organization_deletion_purge_due_v1('${due_workspace}');" \
  "SELECT * FROM app_private.restore_organization_v1('${owner_one}','00000000-0507-5000-8000-000000000011','${due_workspace}','${due_request}');" \
  22023 'organization restoration idempotency conflict' 1

run_race restore-first "${restore_workspace}" \
  "SELECT * FROM app_private.restore_organization_v1('${owner_two}','00000000-0507-5000-8000-000000000012','${restore_workspace}','${restore_request}'); DO \$restored_check\$ BEGIN IF NOT EXISTS (SELECT 1 FROM app_private.organization_deletion_current AS attempt JOIN app_private.organization_deletion_request_claims AS claim ON claim.request_id=attempt.deletion_request_id AND claim.deletion_request_id=attempt.deletion_request_id AND claim.organization_workspace_id=attempt.organization_workspace_id AND claim.effective_at_utc=attempt.effective_at_utc AND claim.purge_after_utc=attempt.purge_after_utc JOIN app_data.workspaces AS workspace ON workspace.workspace_id=attempt.organization_workspace_id WHERE attempt.organization_workspace_id='${restore_workspace}' AND attempt.status='restored' AND workspace.deleted_at IS NULL) THEN RAISE EXCEPTION 'restore-first precondition drift'; END IF; END \$restored_check\$;" \
  "SELECT app_private.mark_organization_deletion_purge_due_v1('${restore_workspace}');" \
  55000 'organization purge due unavailable' 35

echo '0105 restore/due governance-lock races：通过。'
