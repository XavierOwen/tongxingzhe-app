#!/usr/bin/env bash

set -euo pipefail

# Independent sessions verify submit serialization and lock-after re-reads.
# Rows are committed for dump/restore checks in a namespace distinct from the
# rollback fixture.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --set=VERBOSITY=verbose
)

run_psql() {
  "${psql_base[@]}" "$@"
}

temporary_directory="$(mktemp -d)"
child_pids=()

cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock_holder() {
  local lock_name="$1" holder_pid="$2" holder_output="$3" probe
  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      WITH probe AS (
        SELECT pg_try_advisory_lock(hashtextextended('${lock_name}', 0)) AS acquired
      )
      SELECT CASE WHEN acquired
        THEN NOT pg_advisory_unlock(hashtextextended('${lock_name}', 0))
        ELSE true END
      FROM probe;
    " | tr -d '[:space:]')"
    if [[ "${probe}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then
      echo "并发持锁会话过早退出：${lock_name}" >&2
      sed -n '1,160p' "${holder_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_advisory_waiter() {
  local lock_name="$1" waiter_pid="$2" waiter_output="$3" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32) & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0) & 4294967295)::bigint AS objid,
          (SELECT oid FROM pg_database WHERE datname = current_database()) AS database_id
      )
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row CROSS JOIN lock_key
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
          AND lock_row.database = lock_key.database_id
          AND lock_row.classid::bigint = lock_key.classid
          AND lock_row.objid::bigint = lock_key.objid
          AND lock_row.objsubid = 1
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo "并发等待会话过早退出：${lock_name}" >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

wait_for_app_user_waiter() {
  local waiter_pid="$1" waiter_output="$2" waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row
        WHERE NOT lock_row.granted
          AND (lock_row.locktype = 'transactionid'
            OR (lock_row.locktype = 'tuple'
              AND lock_row.relation = 'app_data.app_users'::regclass))
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo 'application submit 会话在 app-user 锁前过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo '没有观察到 application submit 的 app_users 行锁等待。' >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

result_from() {
  awk '/^organization-shareable-join-application:v1\|/ { print; exit }' "$1"
}

run_pair() {
  local label="$1" first_sql="$2" second_sql="$3" wait_lock="$4"
  local expected_state="$5" expected_message="$6" equal_receipts="$7"
  local first_output="${temporary_directory}/${label}-first.out"
  local second_output="${temporary_directory}/${label}-second.out"
  local ready_lock="0093-ready:${label}"
  local first_pid second_pid first_status=0 second_status=0 first_row second_row

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    ${first_sql}
    SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
    SELECT pg_sleep(2);
    COMMIT;
  " >"${first_output}" 2>&1 &
  first_pid=$!
  child_pids+=("${first_pid}")
  wait_for_lock_holder "${ready_lock}" "${first_pid}" "${first_output}"

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    ${second_sql}
    COMMIT;
  " >"${second_output}" 2>&1 &
  second_pid=$!
  child_pids+=("${second_pid}")
  if [[ "${wait_lock}" == 'app_users' ]]; then
    wait_for_app_user_waiter "${second_pid}" "${second_output}"
  else
    wait_for_advisory_waiter "${wait_lock}" "${second_pid}" "${second_output}"
  fi

  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?
  if [[ "${first_status}" -ne 0 ]]; then
    sed -n '1,160p' "${first_output}" >&2
    exit 1
  fi
  if [[ -n "${expected_state}" ]]; then
    if [[ "${second_status}" -eq 0 ]] \
      || ! grep -Fq "${expected_state}: ${expected_message}" "${second_output}"; then
      echo "${label} 未返回预期的固定失败。" >&2
      sed -n '1,160p' "${second_output}" >&2
      exit 1
    fi
  elif [[ "${second_status}" -ne 0 ]]; then
    sed -n '1,160p' "${second_output}" >&2
    exit 1
  fi
  if [[ "${equal_receipts}" == 'yes' ]]; then
    first_row="$(result_from "${first_output}")"
    second_row="$(result_from "${second_output}")"
    if [[ -z "${first_row}" || "${first_row}" != "${second_row}" ]] \
      || [[ "$(awk -F'|' '{ print NF }' <<<"${first_row}")" -ne 6 ]]; then
      echo "${label} 未精确重放六字段 receipt。" >&2
      exit 1
    fi
  fi
}

owner='93020000-0093-0000-8000-000000000001'
replay_applicant='93020000-0093-0000-8000-000000000002'
status_applicant='93020000-0093-0000-8000-000000000003'
recovery_applicant='93020000-0093-0000-8000-000000000004'
membership_applicant='93020000-0093-0000-8000-000000000005'
expiry_applicant='93020000-0093-0000-8000-000000000006'
create_applicant='93020000-0093-0000-8000-000000000007'
main_workspace='93020000-0093-4000-8000-000000000001'
recovery_workspace='93020000-0093-4000-8000-000000000002'
exact_link='93020000-0093-5000-8000-000000000001'
alternate_link='93020000-0093-5000-8000-000000000002'
create_link='93020000-0093-5000-8000-000000000003'
status_link='93020000-0093-5000-8000-000000000004'
recovery_link='93020000-0093-5000-8000-000000000005'
membership_link='93020000-0093-5000-8000-000000000006'
expiry_link='93020000-0093-5000-8000-000000000007'
link_request_prefix='organization-shareable-join-link-request:'
governance_prefix='organization-governance:'

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status)
  SELECT ('93020000-0093-0000-8000-' || lpad(n::text, 12, '0'))::uuid,
    'active' FROM generate_series(1, 7) AS n;
  INSERT INTO app_data.external_identities (issuer, subject, app_user_id)
  VALUES
    ('0093-concurrency', 'replay', '${replay_applicant}'),
    ('0093-concurrency', 'status', '${status_applicant}'),
    ('0093-concurrency', 'recovery', '${recovery_applicant}'),
    ('0093-concurrency', 'membership', '${membership_applicant}'),
    ('0093-concurrency', 'expiry', '${expiry_applicant}'),
    ('0093-concurrency', 'create', '${create_applicant}');
  INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
  VALUES
    ('${main_workspace}', 'organization', '0093 concurrent main'),
    ('${recovery_workspace}', 'organization', '0093 concurrent recovery');
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('93020000-0093-3000-8000-000000000001', '${main_workspace}',
      '${owner}', transaction_timestamp(), NULL),
    ('93020000-0093-3000-8000-000000000002', '${recovery_workspace}',
      '${owner}', transaction_timestamp(), NULL);
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id, organization_membership_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('93020000-0093-7000-8000-000000000001',
      '93020000-0093-3000-8000-000000000001', transaction_timestamp(), NULL),
    ('93020000-0093-7000-8000-000000000002',
      '93020000-0093-3000-8000-000000000002', transaction_timestamp(), NULL);
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '${owner}', '${exact_link}', '${main_workspace}');
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '${owner}', '${alternate_link}', '${main_workspace}');
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '${owner}', '${status_link}', '${main_workspace}');
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '${owner}', '${recovery_link}', '${recovery_workspace}');
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '${owner}', '${membership_link}', '${main_workspace}');
  COMMIT;
"

submit_exact="
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'replay',
    '93020000-0093-6000-8000-000000000001', '${exact_link}');
"
run_pair same-exact "${submit_exact}" "${submit_exact}" \
  "${link_request_prefix}${exact_link}" '' '' yes

run_pair alternate-application "
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'replay',
    '93020000-0093-6000-8000-000000000002', '${alternate_link}');
" "
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'replay',
    '93020000-0093-6000-8000-000000000003', '${alternate_link}');
" "${link_request_prefix}${alternate_link}" '22023' \
  'organization shareable join idempotency conflict' no

run_pair link-create-submit "
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '${owner}', '${create_link}', '${main_workspace}');
" "
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'create',
    '93020000-0093-6000-8000-000000000004', '${create_link}');
" "${link_request_prefix}${create_link}" '' '' no

run_pair account-inactive "
  UPDATE app_data.app_users SET status = 'deletion_pending'
  WHERE app_user_id = '${status_applicant}';
" "
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'status',
    '93020000-0093-6000-8000-000000000005', '${status_link}');
" app_users '42501' 'organization shareable join forbidden' no

run_pair recovery "
  UPDATE app_data.workspaces SET deleted_at = clock_timestamp() + interval '30 days'
  WHERE workspace_id = '${recovery_workspace}';
" "
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'recovery',
    '93020000-0093-6000-8000-000000000006', '${recovery_link}');
" "${governance_prefix}${recovery_workspace}" '42501' \
  'organization shareable join forbidden' no

# The membership trigger holds the applicant row, governance fence, and exact
# membership lock. Submit must wait, then materialize the new membership.
run_pair membership-created "
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    '93020000-0093-3000-8000-000000000003', '${main_workspace}',
    '${membership_applicant}', clock_timestamp(), NULL);
" "
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'membership',
    '93020000-0093-6000-8000-000000000007', '${membership_link}');
" app_users '42501' 'organization shareable join forbidden' no

# The waiter starts before expiry but reaches the wall-clock check only after
# the link request lock is released.
run_pair expiry-after-wait "
  SELECT pg_advisory_xact_lock(hashtextextended(
    '${link_request_prefix}${expiry_link}', 0));
  INSERT INTO app_private.organization_shareable_join_link_request_claims (
    link_id, organization_workspace_id, creator_app_user_id,
    issued_at_utc, expires_at_utc
  ) VALUES (
    '${expiry_link}', '${main_workspace}', '${owner}',
    transaction_timestamp() - interval '168 hours' + interval '1 second',
    transaction_timestamp() + interval '1 second');
  INSERT INTO app_private.organization_shareable_join_link_audit_events (
    organization_shareable_join_link_audit_event_id,
    organization_shareable_join_link_contract_id, link_id,
    organization_workspace_id, event_kind, issued_at_utc, expires_at_utc
  ) VALUES (
    '93020000-0093-9000-8000-000000000007',
    'organization-shareable-join-link:v1', '${expiry_link}',
    '${main_workspace}', 'link_created',
    transaction_timestamp() - interval '168 hours' + interval '1 second',
    transaction_timestamp() + interval '1 second');
" "
  SELECT 'submit-start|' || transaction_timestamp()::text;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '0093-concurrency', 'expiry',
    '93020000-0093-6000-8000-000000000008', '${expiry_link}');
" "${link_request_prefix}${expiry_link}" '42501' \
  'organization shareable join forbidden' no

expiry_waiter_started="$(awk -F'|' '/^submit-start\|/ { print $2; exit }' \
  "${temporary_directory}/expiry-after-wait-second.out")"
if [[ -z "${expiry_waiter_started}" ]] || [[ "$(run_psql --tuples-only --no-align --command="
  SELECT '${expiry_waiter_started}'::timestamptz < expires_at_utc
  FROM app_private.organization_shareable_join_link_request_claims
  WHERE link_id = '${expiry_link}';
")" != 't' ]]; then
  echo 'expiry 等待者未在 link 到期前开始，不能证明锁后时间重验。' >&2
  exit 1
fi

run_psql --quiet <<SQL
DO \$verify\$
BEGIN
  IF (SELECT count(*)
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id IN (
        '93020000-0093-6000-8000-000000000001',
        '93020000-0093-6000-8000-000000000002',
        '93020000-0093-6000-8000-000000000004'
      )) <> 3
    OR EXISTS (
      SELECT 1
      FROM app_private.organization_shareable_join_application_request_claims AS claim
      LEFT JOIN app_private.organization_shareable_join_application_audit_events AS audit
        ON audit.application_id = claim.application_id
        AND audit.event_kind = 'application_submitted'
      WHERE split_part(claim.application_id::text, '-', 1) = '93020000'
        AND (claim.expires_at_utc <> claim.submitted_at_utc + interval '168 hours'
          OR audit.occurred_at_utc IS DISTINCT FROM claim.submitted_at_utc)
    )
    OR EXISTS (
      SELECT 1
      FROM app_private.organization_shareable_join_application_request_claims
      WHERE application_id IN (
        '93020000-0093-6000-8000-000000000003',
        '93020000-0093-6000-8000-000000000005',
        '93020000-0093-6000-8000-000000000006',
        '93020000-0093-6000-8000-000000000007',
        '93020000-0093-6000-8000-000000000008'
      )
    )
    OR (SELECT count(*)
        FROM app_private.organization_shareable_join_application_audit_events
        WHERE split_part(application_id::text, '-', 1) = '93020000') <> 3
    OR (SELECT count(*)
        FROM app_data.organization_memberships
        WHERE split_part(organization_membership_id::text, '-', 1) = '93020000') <> 3
    OR (SELECT count(*)
        FROM app_data.organization_owner_assignments
        WHERE split_part(organization_owner_assignment_id::text, '-', 1) = '93020000') <> 2
    OR EXISTS (
      SELECT 1 FROM app_data.project_memberships AS project_membership
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE split_part(membership.organization_membership_id::text, '-', 1) =
        '93020000'
    )
  THEN
    RAISE EXCEPTION '0093 application submit concurrency facts mismatch';
  END IF;
END
\$verify\$;
SQL

echo '0093 application submit replay, conflict, link, expiry, account, recovery and membership races passed.'
