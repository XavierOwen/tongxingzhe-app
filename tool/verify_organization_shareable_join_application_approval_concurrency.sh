#!/usr/bin/env bash

set -euo pipefail

# Independent sessions verify approval serialization, submit interoperability,
# and every state change that must be re-read after its prescribed lock.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"
psql_base=(
  "${psql_command}" "${DATABASE_URL}" --no-psqlrc
  --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose
)
run_psql() { "${psql_base[@]}" "$@"; }

temporary_directory="$(mktemp -d)"
child_pids=()
cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    [[ -z "${pid}" ]] || wait "${pid}" >/dev/null 2>&1 || true
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
        WHERE lock_row.locktype = 'advisory' AND NOT lock_row.granted
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
      echo 'approval 会话在 app-user 锁前过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done
  echo '没有观察到 approval 的 app_users 行锁等待。' >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

approval_result_from() {
  awk -F'|' '/^organization-shareable-join-application:v1\|/ && NF == 5 { print; exit }' "$1"
}

run_pair() {
  local label="$1" first_sql="$2" second_sql="$3" wait_lock="$4"
  local expected_state="$5" expected_message="$6" equal_receipts="$7"
  local first_output="${temporary_directory}/${label}-first.out"
  local second_output="${temporary_directory}/${label}-second.out"
  local ready_lock="0094-ready:${label}"
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
    first_row="$(approval_result_from "${first_output}")"
    second_row="$(approval_result_from "${second_output}")"
    if [[ -z "${first_row}" || "${first_row}" != "${second_row}" ]]; then
      echo "${label} 未精确重放五字段 approval receipt。" >&2
      exit 1
    fi
  fi
}

application_prefix='organization-shareable-join-application-request:'
governance_prefix='organization-governance:'
issuer='0094-concurrency'

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status)
  SELECT ('94020000-0094-0000-8000-' || lpad(n::text, 12, '0'))::uuid,
    'active' FROM generate_series(1, 21) AS n;
  INSERT INTO app_data.external_identities (issuer, subject, app_user_id)
  SELECT '${issuer}', 'user-' || n,
    ('94020000-0094-0000-8000-' || lpad(n::text, 12, '0'))::uuid
  FROM unnest(ARRAY[1,2,3,5,7,12,13]) AS selected(n);
  INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
  SELECT ('94020000-0094-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    'organization', '0094 concurrent organization ' || n
  FROM generate_series(1, 12) AS generated_workspace(n);
  WITH owner_matrix(workspace_n, app_user_n, slot_n) AS (
    SELECT workspace_n, app_user_n, slot_n
    FROM generate_series(1, 9) AS workspace_n
    CROSS JOIN (VALUES (1, 1), (2, 2)) AS owner(app_user_n, slot_n)
    UNION ALL VALUES
      (10, 3, 1), (10, 4, 2),
      (11, 5, 1), (11, 6, 2),
      (12, 7, 1), (12, 8, 2)
  )
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  )
  SELECT
    format('94020000-0094-3000-8000-%s',
      lpad((workspace_n * 10 + slot_n)::text, 12, '0'))::uuid,
    format('94020000-0094-4000-8000-%s',
      lpad(workspace_n::text, 12, '0'))::uuid,
    format('94020000-0094-0000-8000-%s',
      lpad(app_user_n::text, 12, '0'))::uuid,
    transaction_timestamp() - interval '1 hour', NULL
  FROM owner_matrix;
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id, organization_membership_id,
    active_from_utc, inactive_from_utc
  )
  SELECT
    format('94020000-0094-7000-8000-%s',
      split_part(organization_membership_id::text, '-', 5))::uuid,
    organization_membership_id, transaction_timestamp(), NULL
  FROM app_data.organization_memberships
  WHERE organization_membership_id::text LIKE '94020000-0094-%';
  COMMIT;
"

# Direct pending facts keep this script focused on approval. Applications 4
# and 5 are submitted through 0093 below because their replay lock order is
# part of the test.
run_psql --quiet --command="
  INSERT INTO app_private.organization_shareable_join_application_request_claims (
    application_id, link_id, organization_workspace_id,
    applicant_app_user_id, submitted_at_utc, expires_at_utc,
    approved_at_utc, approved_organization_membership_id
  )
  SELECT
    format('94020000-0094-6000-8000-%s', lpad(application_n::text, 12, '0'))::uuid,
    format('94020000-0094-5000-8000-%s', lpad(application_n::text, 12, '0'))::uuid,
    format('94020000-0094-4000-8000-%s', lpad(workspace_n::text, 12, '0'))::uuid,
    format('94020000-0094-0000-8000-%s', lpad(applicant_n::text, 12, '0'))::uuid,
    transaction_timestamp(), transaction_timestamp() + interval '168 hours',
    NULL, NULL
  FROM (VALUES
    (1, 1, 10), (2, 2, 11), (3, 2, 11),
    (7, 6, 15), (8, 7, 16), (9, 8, 17),
    (10, 9, 18), (11, 10, 19)
  ) AS pending(application_n, workspace_n, applicant_n);
  INSERT INTO app_private.organization_shareable_join_application_audit_events (
    organization_shareable_join_application_audit_event_id,
    organization_shareable_join_application_contract_id,
    application_id, link_id, organization_workspace_id, event_kind,
    organization_membership_id, occurred_at_utc
  )
  SELECT gen_random_uuid(), 'organization-shareable-join-application:v1',
    application_id, link_id, organization_workspace_id,
    'application_submitted', NULL, submitted_at_utc
  FROM app_private.organization_shareable_join_application_request_claims
  WHERE application_id::text LIKE '94020000-0094-%';

  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '94020000-0094-0000-8000-000000000001',
    '94020000-0094-5000-8000-000000000004',
    '94020000-0094-4000-8000-000000000003');
  SELECT count(*) FROM app_private.create_organization_shareable_join_link_v1(
    '94020000-0094-0000-8000-000000000001',
    '94020000-0094-5000-8000-000000000005',
    '94020000-0094-4000-8000-000000000004');
  SELECT count(*) FROM app_private.submit_organization_shareable_join_application_v1(
    '94020000-0094-0000-8000-000000000012',
    '94020000-0094-6000-8000-000000000004',
    '94020000-0094-5000-8000-000000000004');
  SELECT count(*) FROM app_private.submit_organization_shareable_join_application_v1(
    '94020000-0094-0000-8000-000000000013',
    '94020000-0094-6000-8000-000000000005',
    '94020000-0094-5000-8000-000000000005');

  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('94020000-0094-3000-8000-000000000120',
      '94020000-0094-4000-8000-000000000011',
      '94020000-0094-0000-8000-000000000020',
      transaction_timestamp() - interval '1 hour', NULL),
    ('94020000-0094-3000-8000-000000000130',
      '94020000-0094-4000-8000-000000000012',
      '94020000-0094-0000-8000-000000000021',
      transaction_timestamp() - interval '1 hour', NULL);
  INSERT INTO app_private.organization_shareable_join_application_request_claims (
    application_id, link_id, organization_workspace_id,
    applicant_app_user_id, submitted_at_utc, expires_at_utc,
    approved_at_utc, approved_organization_membership_id
  ) VALUES
    ('94020000-0094-6000-8000-000000000012',
      '94020000-0094-5000-8000-000000000012',
      '94020000-0094-4000-8000-000000000011',
      '94020000-0094-0000-8000-000000000020',
      transaction_timestamp() - interval '2 hours',
      transaction_timestamp() + interval '166 hours',
      (SELECT active_from_utc FROM app_data.organization_memberships
       WHERE organization_membership_id =
         '94020000-0094-3000-8000-000000000120'),
      '94020000-0094-3000-8000-000000000120'),
    ('94020000-0094-6000-8000-000000000013',
      '94020000-0094-5000-8000-000000000013',
      '94020000-0094-4000-8000-000000000012',
      '94020000-0094-0000-8000-000000000021',
      transaction_timestamp() - interval '2 hours',
      transaction_timestamp() + interval '166 hours',
      (SELECT active_from_utc FROM app_data.organization_memberships
       WHERE organization_membership_id =
         '94020000-0094-3000-8000-000000000130'),
      '94020000-0094-3000-8000-000000000130');
  INSERT INTO app_private.organization_shareable_join_application_audit_events (
    organization_shareable_join_application_audit_event_id,
    organization_shareable_join_application_contract_id,
    application_id, link_id, organization_workspace_id, event_kind,
    organization_membership_id, occurred_at_utc
  )
  SELECT gen_random_uuid(), 'organization-shareable-join-application:v1',
    claim.application_id, claim.link_id, claim.organization_workspace_id,
    event.event_kind,
    CASE WHEN event.event_kind = 'application_approved'
      THEN claim.approved_organization_membership_id END,
    CASE WHEN event.event_kind = 'application_approved'
      THEN claim.approved_at_utc ELSE claim.submitted_at_utc END
  FROM app_private.organization_shareable_join_application_request_claims AS claim
  CROSS JOIN (VALUES ('application_submitted'), ('application_approved'))
    AS event(event_kind)
  WHERE claim.application_id IN (
    '94020000-0094-6000-8000-000000000012',
    '94020000-0094-6000-8000-000000000013'
  );
"

approve() {
  local owner_n="$1" application_n="$2" workspace_n="$3"
  printf '%s' "
    SET LOCAL ROLE tongxingzhe_runtime;
    SELECT * FROM app_data.approve_organization_shareable_join_application_for_identity_v1(
      '${issuer}', 'user-${owner_n}',
      '94020000-0094-6000-8000-$(printf '%012d' "${application_n}")',
      '94020000-0094-4000-8000-$(printf '%012d' "${workspace_n}")');
  "
}

run_pair same-application-two-owners \
  "$(approve 1 1 1)" "$(approve 2 1 1)" \
  "${application_prefix}94020000-0094-6000-8000-000000000001" '' '' yes

run_pair same-applicant-two-applications \
  "$(approve 1 2 2)" "$(approve 2 3 2)" app_users \
  '42501' 'organization shareable join forbidden' no

submit_four="
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '${issuer}', 'user-12',
    '94020000-0094-6000-8000-000000000004',
    '94020000-0094-5000-8000-000000000004');
"
run_pair submit-before-approval "${submit_four}" "$(approve 1 4 3)" \
  "${application_prefix}94020000-0094-6000-8000-000000000004" '' '' no

submit_five="
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.submit_organization_shareable_join_application_for_identity_v1(
    '${issuer}', 'user-13',
    '94020000-0094-6000-8000-000000000005',
    '94020000-0094-5000-8000-000000000005');
"
run_pair approval-before-submit "$(approve 1 5 4)" "${submit_five}" \
  "${application_prefix}94020000-0094-6000-8000-000000000005" '' '' no

# Create the one-second application immediately before its waiter starts.
run_psql --quiet --command="
  WITH captured AS MATERIALIZED (SELECT clock_timestamp() AS now_at)
  INSERT INTO app_private.organization_shareable_join_application_request_claims (
    application_id, link_id, organization_workspace_id,
    applicant_app_user_id, submitted_at_utc, expires_at_utc,
    approved_at_utc, approved_organization_membership_id
  ) SELECT
    '94020000-0094-6000-8000-000000000006',
    '94020000-0094-5000-8000-000000000006',
    '94020000-0094-4000-8000-000000000005',
    '94020000-0094-0000-8000-000000000014',
    now_at - interval '168 hours' + interval '1 second',
    now_at + interval '1 second', NULL, NULL
  FROM captured;
  INSERT INTO app_private.organization_shareable_join_application_audit_events (
    organization_shareable_join_application_audit_event_id,
    organization_shareable_join_application_contract_id,
    application_id, link_id, organization_workspace_id, event_kind,
    organization_membership_id, occurred_at_utc
  ) SELECT gen_random_uuid(), 'organization-shareable-join-application:v1',
    application_id, link_id, organization_workspace_id,
    'application_submitted', NULL, submitted_at_utc
  FROM app_private.organization_shareable_join_application_request_claims
  WHERE application_id = '94020000-0094-6000-8000-000000000006';
"
run_pair expiry-after-wait "
  SELECT pg_advisory_xact_lock(hashtextextended(
    '${application_prefix}94020000-0094-6000-8000-000000000006', 0));
" "
  SELECT 'approval-start|' || transaction_timestamp()::text;
  $(approve 1 6 5)
" "${application_prefix}94020000-0094-6000-8000-000000000006" \
  '42501' 'organization shareable join forbidden' no

expiry_waiter_started="$(awk -F'|' '/^approval-start\|/ { print $2; exit }' \
  "${temporary_directory}/expiry-after-wait-second.out")"
if [[ -z "${expiry_waiter_started}" ]] || [[ "$(run_psql --tuples-only --no-align --command="
  SELECT '${expiry_waiter_started}'::timestamptz < expires_at_utc
  FROM app_private.organization_shareable_join_application_request_claims
  WHERE application_id = '94020000-0094-6000-8000-000000000006';
")" != 't' ]]; then
  echo 'expiry 等待者未在 application 到期前开始。' >&2
  exit 1
fi

run_pair recovery-after-wait "
  UPDATE app_data.workspaces
  SET deleted_at = clock_timestamp() + interval '30 days'
  WHERE workspace_id = '94020000-0094-4000-8000-000000000006';
" "$(approve 1 7 6)" \
  "${governance_prefix}94020000-0094-4000-8000-000000000006" \
  '42501' 'organization shareable join forbidden' no

run_pair applicant-inactive "
  UPDATE app_data.app_users SET status = 'deletion_pending'
  WHERE app_user_id = '94020000-0094-0000-8000-000000000016';
" "$(approve 1 8 7)" app_users \
  '42501' 'organization shareable join forbidden' no

run_pair applicant-deassociated "
  SELECT pg_advisory_xact_lock(hashtextextended(
    '${application_prefix}94020000-0094-6000-8000-000000000009', 0));
  UPDATE app_private.organization_shareable_join_application_request_claims
  SET applicant_app_user_id = NULL
  WHERE application_id = '94020000-0094-6000-8000-000000000009';
" "$(approve 1 9 8)" \
  "${application_prefix}94020000-0094-6000-8000-000000000009" \
  '42501' 'organization shareable join forbidden' no

run_pair applicant-became-member "
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    '94020000-0094-3000-8000-000000000180',
    '94020000-0094-4000-8000-000000000009',
    '94020000-0094-0000-8000-000000000018', clock_timestamp(), NULL);
" "$(approve 1 10 9)" app_users \
  '42501' 'organization shareable join forbidden' no

run_pair owner-inactive "
  UPDATE app_data.app_users SET status = 'deletion_pending'
  WHERE app_user_id = '94020000-0094-0000-8000-000000000003';
" "$(approve 3 11 10)" app_users \
  '42501' 'organization shareable join forbidden' no

run_pair replay-before-owner-revoke "$(approve 5 12 11)" "
  UPDATE app_data.organization_owner_assignments
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_owner_assignment_id =
    '94020000-0094-7000-8000-000000000111';
" "${governance_prefix}94020000-0094-4000-8000-000000000011" '' '' no

run_pair owner-revoke-before-replay "
  UPDATE app_data.organization_owner_assignments
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_owner_assignment_id =
    '94020000-0094-7000-8000-000000000121';
" "$(approve 7 13 12)" \
  "${governance_prefix}94020000-0094-4000-8000-000000000012" \
  '42501' 'organization shareable join forbidden' no

run_psql --quiet <<'SQL'
DO $verify$
DECLARE
  expected record;
BEGIN
  FOR expected IN
    SELECT * FROM (VALUES
      (1, true), (2, true), (3, false), (4, true), (5, true),
      (6, false), (7, false), (8, false), (9, false),
      (10, false), (11, false), (12, true), (13, true)
    ) AS expected_rows(application_n, approved)
  LOOP
    IF (SELECT count(*)
        FROM app_private.organization_shareable_join_application_request_claims
        WHERE application_id = format(
          '94020000-0094-6000-8000-%s',
          lpad(expected.application_n::text, 12, '0'))::uuid
          AND (approved_at_utc IS NOT NULL) = expected.approved
          AND (approved_organization_membership_id IS NOT NULL) =
            expected.approved) <> 1
      OR (SELECT count(*)
          FROM app_private.organization_shareable_join_application_audit_events
          WHERE application_id = format(
            '94020000-0094-6000-8000-%s',
            lpad(expected.application_n::text, 12, '0'))::uuid) <>
        (CASE WHEN expected.approved THEN 2 ELSE 1 END)
    THEN
      RAISE EXCEPTION '0094 concurrency application % facts mismatch',
        expected.application_n;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM app_private.organization_shareable_join_application_request_claims AS claim
    JOIN app_private.organization_shareable_join_application_audit_events AS audit
      ON audit.application_id = claim.application_id
      AND audit.event_kind = 'application_approved'
    JOIN app_data.organization_memberships AS membership
      ON membership.organization_membership_id =
        claim.approved_organization_membership_id
    WHERE claim.application_id::text LIKE '94020000-0094-%'
      AND (audit.organization_membership_id IS DISTINCT FROM
            claim.approved_organization_membership_id
        OR audit.occurred_at_utc IS DISTINCT FROM claim.approved_at_utc
        OR membership.active_from_utc IS DISTINCT FROM claim.approved_at_utc
        OR membership.organization_workspace_id IS DISTINCT FROM
          claim.organization_workspace_id)
  )
    OR (SELECT count(*) FROM app_data.organization_memberships
        WHERE organization_workspace_id::text LIKE
          '94020000-0094-%') <> 31
    OR (SELECT count(*) FROM app_data.organization_owner_assignments
        WHERE organization_owner_assignment_id::text LIKE
          '94020000-0094-%') <> 24
    OR EXISTS (
      SELECT 1 FROM app_data.organization_owner_assignments AS owner_assignment
      JOIN app_private.organization_shareable_join_application_request_claims AS claim
        ON claim.approved_organization_membership_id =
          owner_assignment.organization_membership_id
      WHERE claim.application_id::text LIKE '94020000-0094-%'
    )
    OR EXISTS (
      SELECT 1 FROM app_data.project_memberships AS project_membership
      JOIN app_data.organization_memberships AS membership
        USING (organization_membership_id)
      WHERE membership.organization_workspace_id::text LIKE
        '94020000-0094-%'
    )
  THEN
    RAISE EXCEPTION '0094 concurrency membership or audit lineage mismatch';
  END IF;
END
$verify$;
SQL

echo '0094 approval replay, submit interop and lock-after lifecycle races passed.'
