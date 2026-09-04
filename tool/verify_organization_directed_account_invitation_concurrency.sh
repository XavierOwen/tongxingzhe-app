#!/usr/bin/env bash

set -euo pipefail

# Independent sessions exercise invitation create/accept request, account,
# governance and membership lock order.  Synthetic rows are intentionally
# committed so the Docker runner can include them in its dump/restore checks.
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
  local lock_name="$1"
  local holder_pid="$2"
  local holder_output="$3"
  local probe

  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      WITH lock_probe AS (
        SELECT pg_try_advisory_lock(
          hashtextextended('${lock_name}', 0)
        ) AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${lock_name}', 0)
        )
        ELSE true
      END
      FROM lock_probe;
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

  kill "${holder_pid}" >/dev/null 2>&1 || true
  wait "${holder_pid}" >/dev/null 2>&1 || true
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_advisory_waiter() {
  local lock_name="$1"
  local waiter_pid="$2"
  local waiter_output="$3"
  local waiting

  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32)
            & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0)
            & 4294967295)::bigint AS objid,
          (SELECT oid FROM pg_database
            WHERE datname = current_database()) AS database_id
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        CROSS JOIN lock_key
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

  kill "${waiter_pid}" >/dev/null 2>&1 || true
  wait "${waiter_pid}" >/dev/null 2>&1 || true
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

wait_for_app_user_waiter() {
  local waiter_pid="$1"
  local waiter_output="$2"
  local waiting

  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        WHERE NOT lock_row.granted
          AND (
            lock_row.locktype = 'transactionid'
            OR (
              lock_row.locktype = 'tuple'
              AND lock_row.relation = 'app_data.app_users'::regclass
            )
          )
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo 'app_users 状态竞态会话过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  kill "${waiter_pid}" >/dev/null 2>&1 || true
  wait "${waiter_pid}" >/dev/null 2>&1 || true
  echo '没有观察到 app_users 行锁等待。' >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}


result_from() {
  awk '/^organization-directed-account-invitation:v1\|/ { print; exit }' "$1"
}

# Both sessions commit. A ready lock proves the first operation has completed
# before the second starts; pg_locks proves the waiter reached the intended fence.
run_pair() {
  local label="$1" first_sql="$2" second_sql="$3" wait_lock="$4"
  local expected_state="$5" expected_message="$6" equal_receipts="$7"
  local first_after_wait_sql="${8:-}"
  local first_output="$temporary_directory/$label-first.out"
  local second_output="$temporary_directory/$label-second.out"
  local ready_lock="0087-ready:$label"
  local first_pid second_pid first_status=0 second_status=0 first_row second_row

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    $first_sql
    SELECT pg_advisory_lock(hashtextextended('$ready_lock', 0));
    SELECT pg_sleep(2);
    $first_after_wait_sql
    COMMIT;
  " >"$first_output" 2>&1 &
  first_pid=$!
  child_pids+=("$first_pid")
  wait_for_lock_holder "$ready_lock" "$first_pid" "$first_output"

  run_psql --quiet --tuples-only --no-align --field-separator='|' --command="
    BEGIN;
    $second_sql
    COMMIT;
  " >"$second_output" 2>&1 &
  second_pid=$!
  child_pids+=("$second_pid")
  if [[ "$wait_lock" == 'app_users' ]]; then
    wait_for_app_user_waiter "$second_pid" "$second_output"
  else
    wait_for_advisory_waiter "$wait_lock" "$second_pid" "$second_output"
  fi
  wait "$first_pid" || first_status=$?
  wait "$second_pid" || second_status=$?
  if [[ "$first_status" -ne 0 ]]; then
    sed -n '1,160p' "$first_output" >&2
    exit 1
  fi
  if [[ -n "$expected_state" ]]; then
    if [[ "$second_status" -eq 0 ]] \
      || ! grep -Fq "$expected_state: $expected_message" "$second_output"; then
      echo "$label 未返回固定失败。" >&2
      sed -n '1,160p' "$second_output" >&2
      exit 1
    fi
  elif [[ "$second_status" -ne 0 ]]; then
    sed -n '1,160p' "$second_output" >&2
    exit 1
  fi
  if [[ "$equal_receipts" == 'yes' ]]; then
    first_row="$(result_from "$first_output")"
    second_row="$(result_from "$second_output")"
    if [[ -z "$first_row" || "$first_row" != "$second_row" ]] \
      || [[ "$(awk -F'|' '{ print NF }' <<<"$first_row")" -ne 5 ]]; then
      echo "$label 未精确重放五字段 receipt。" >&2
      exit 1
    fi
  fi
}

workspace_id='87022000-0000-4000-8000-000000000001'
owner_one='87020000-0000-4000-8000-000000000001'
owner_two='87020000-0000-4000-8000-000000000002'
replay_target='87020000-0000-4000-8000-000000000003'
drift_target='87020000-0000-4000-8000-000000000004'
governance_target_one='87020000-0000-4000-8000-000000000005'
governance_target_two='87020000-0000-4000-8000-000000000006'
status_target='87020000-0000-4000-8000-000000000007'
cross_target='87020000-0000-4000-8000-000000000008'
create_status_target='87020000-0000-4000-8000-000000000009'
expiry_target='87020000-0000-4000-8000-000000000010'
owner_race_target='87020000-0000-4000-8000-000000000011'
replay_id='87026000-0000-4000-8000-000000000001'
drift_id='87026000-0000-4000-8000-000000000002'
governance_id_one='87026000-0000-4000-8000-000000000003'
governance_id_two='87026000-0000-4000-8000-000000000004'
status_id='87026000-0000-4000-8000-000000000005'
cross_id='87026000-0000-4000-8000-000000000006'
create_status_id='87026000-0000-4000-8000-000000000007'
expiry_id='87026000-0000-4000-8000-000000000008'
owner_race_id='87026000-0000-4000-8000-000000000009'
request_prefix='organization-directed-account-invitation-request:'

run_psql --quiet --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status)
  SELECT ('87020000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    'active' FROM generate_series(1, 11) AS n;
  INSERT INTO app_data.external_identities (issuer, subject, app_user_id)
  VALUES
    ('0087-concurrency', 'owner', '$owner_one'),
    ('0087-concurrency', 'target', '$replay_target');
  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES ('$workspace_id', 'organization', '0087 concurrency organization');
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('87023000-0000-4000-8000-000000000001', '$workspace_id',
      '$owner_one', transaction_timestamp(), NULL),
    ('87023000-0000-4000-8000-000000000002', '$workspace_id',
      '$owner_two', transaction_timestamp(), NULL);
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id, organization_membership_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    ('87024000-0000-4000-8000-000000000001',
      '87023000-0000-4000-8000-000000000001', transaction_timestamp(), NULL),
    ('87024000-0000-4000-8000-000000000002',
      '87023000-0000-4000-8000-000000000002', transaction_timestamp(), NULL);
  COMMIT;
"

create_replay_sql="
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.create_organization_directed_account_invitation_for_identity_v1(
    '0087-concurrency', 'owner', '$replay_id', '$workspace_id', '$replay_target');
"
run_pair create-replay "$create_replay_sql" "$create_replay_sql" \
  "$request_prefix$replay_id" '' '' yes

accept_replay_sql="
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT * FROM app_data.accept_organization_directed_account_invitation_for_identity_v1(
    '0087-concurrency', 'target', '$replay_id');
"
run_pair accept-replay "$accept_replay_sql" "$accept_replay_sql" \
  "$request_prefix$replay_id" '' '' yes

run_pair create-drift "
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$drift_id', '$workspace_id', '$drift_target');
" "
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$drift_id', '$workspace_id', '$governance_target_one');
" "$request_prefix$drift_id" '22023' \
  'organization invitation idempotency conflict' no

run_psql --quiet --command="
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$governance_id_one', '$workspace_id', '$governance_target_one');
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_two', '$governance_id_two', '$workspace_id', '$governance_target_two');
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$status_id', '$workspace_id', '$status_target');
"

# Distinct inviters and targets keep this race off shared account rows, so
# the observed wait is specifically the organization governance fence.
run_pair governance "
  SELECT * FROM app_private.accept_organization_directed_account_invitation_v1(
    '$governance_target_one', '$governance_id_one');
" "
  SELECT * FROM app_private.accept_organization_directed_account_invitation_v1(
    '$governance_target_two', '$governance_id_two');
" "organization-governance:$workspace_id" '' '' no

run_pair accept-status "
  UPDATE app_data.app_users SET status = 'deletion_pending'
  WHERE app_user_id = '$status_target';
" "
  SELECT * FROM app_private.accept_organization_directed_account_invitation_v1(
    '$status_target', '$status_id');
" 'app_users' '42501' 'organization invitation forbidden' no

run_pair create-status "
  UPDATE app_data.app_users SET status = 'deletion_pending'
  WHERE app_user_id = '$create_status_target';
" "
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$create_status_id', '$workspace_id', '$create_status_target');
" 'app_users' '42501' 'organization invitation forbidden' no

run_pair create-accept "
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$cross_id', '$workspace_id', '$cross_target');
" "
  SELECT * FROM app_private.accept_organization_directed_account_invitation_v1(
    '$cross_target', '$cross_id');
" "$request_prefix$cross_id" '' '' no

# Expiry elapses while accept waits. transaction_timestamp() predates expiry
# in the waiter, so only a lock-after wall-clock check can reject it.
run_pair expiry-after-wait "
  SELECT pg_advisory_xact_lock(hashtextextended('$request_prefix$expiry_id', 0));
  INSERT INTO app_private.organization_directed_account_invitation_request_claims (
    invitation_id, organization_workspace_id, inviter_app_user_id,
    target_app_user_id, issued_at_utc, expires_at_utc
  ) VALUES (
    '$expiry_id', '$workspace_id', '$owner_one', '$expiry_target',
    transaction_timestamp() - interval '168 hours' + interval '1 second',
    transaction_timestamp() + interval '1 second'
  );
  INSERT INTO app_private.organization_directed_account_invitation_audit_events (
    organization_invitation_audit_event_id, organization_invitation_contract_id,
    invitation_id, organization_workspace_id, event_kind,
    organization_membership_id, occurred_at_utc
  ) VALUES (
    '87027000-0000-4000-8000-000000000008',
    'organization-directed-account-invitation:v1', '$expiry_id', '$workspace_id',
    'invitation_issued', NULL,
    transaction_timestamp() - interval '168 hours' + interval '1 second'
  );
" "
  SELECT 'accept-start|' || transaction_timestamp()::text;
  SELECT * FROM app_private.accept_organization_directed_account_invitation_v1(
    '$expiry_target', '$expiry_id');
" "$request_prefix$expiry_id" '42501' 'organization invitation forbidden' no
expiry_waiter_started="$(awk -F'|' '/^accept-start\|/ { print $2; exit }' \
  "$temporary_directory/expiry-after-wait-second.out")"
if [[ -z "$expiry_waiter_started" ]] || [[ "$(run_psql --tuples-only --no-align --command="
  SELECT '$expiry_waiter_started'::timestamptz < expires_at_utc
  FROM app_private.organization_directed_account_invitation_request_claims
  WHERE invitation_id = '$expiry_id';
")" != 't' ]]; then
  echo 'expiry 等待者未在到期前开始，不能证明锁后时间重验。' >&2
  exit 1
fi

# Hold governance outside a transaction, then close the owner in a new
# transaction after the waiting create has begun. Its transaction timestamp
# still sees the old owner period, but the lock-after authorization must not.
run_pair owner-close "
  COMMIT;
  SELECT pg_advisory_lock(hashtextextended('organization-governance:$workspace_id', 0));
" "
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$owner_race_id', '$workspace_id', '$owner_race_target');
" "organization-governance:$workspace_id" '42501' \
  'organization invitation forbidden' no "
  BEGIN;
  UPDATE app_data.organization_owner_assignments
  SET inactive_from_utc = transaction_timestamp()
  WHERE organization_owner_assignment_id = '87024000-0000-4000-8000-000000000001';
"

# Losing ownership does not revoke an existing invitation or exact replay.
run_psql --quiet --command="
  SELECT * FROM app_private.create_organization_directed_account_invitation_v1(
    '$owner_one', '$replay_id', '$workspace_id', '$replay_target');
  SELECT * FROM app_private.accept_organization_directed_account_invitation_v1(
    '$drift_target', '$drift_id');
"

# Successful acceptance adds only membership. All other counts are frozen;
# failed status/drift paths leave no membership, acceptance, or extra audit.
run_psql --quiet <<SQL
DO \$verify\$
DECLARE
  expected record;
BEGIN
  FOR expected IN
    SELECT * FROM (VALUES
      ('$replay_id'::uuid, '$replay_target'::uuid, true),
      ('$drift_id'::uuid, '$drift_target'::uuid, true),
      ('$governance_id_one'::uuid, '$governance_target_one'::uuid, true),
      ('$governance_id_two'::uuid, '$governance_target_two'::uuid, true),
      ('$status_id'::uuid, '$status_target'::uuid, false),
      ('$cross_id'::uuid, '$cross_target'::uuid, true),
      ('$expiry_id'::uuid, '$expiry_target'::uuid, false)
    ) AS expected_rows(invitation_id, target_id, accepted)
  LOOP
    IF (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_request_claims AS c
        WHERE c.invitation_id = expected.invitation_id
          AND c.organization_workspace_id = '$workspace_id'
          AND c.target_app_user_id = expected.target_id
          AND c.expires_at_utc = c.issued_at_utc + interval '168 hours'
          AND (c.accepted_at_utc IS NOT NULL) = expected.accepted
          AND (c.accepted_organization_membership_id IS NOT NULL) = expected.accepted
       ) <> 1
      OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_audit_events AS a
        WHERE a.invitation_id = expected.invitation_id
          AND a.event_kind = 'invitation_issued'
          AND a.organization_membership_id IS NULL) <> 1
      OR (SELECT count(*)
        FROM app_private.organization_directed_account_invitation_audit_events AS a
        WHERE a.invitation_id = expected.invitation_id) <>
          (CASE WHEN expected.accepted THEN 2 ELSE 1 END)
      OR (SELECT count(*) FROM app_data.organization_memberships AS m
        WHERE m.organization_workspace_id = '$workspace_id'
          AND m.app_user_id = expected.target_id) <>
          (CASE WHEN expected.accepted THEN 1 ELSE 0 END)
    THEN
      RAISE EXCEPTION '0087 invitation concurrency facts mismatch';
    END IF;
    IF expected.accepted AND NOT EXISTS (
      SELECT 1
      FROM app_private.organization_directed_account_invitation_request_claims AS c
      JOIN app_data.organization_memberships AS m
        ON m.organization_membership_id = c.accepted_organization_membership_id
      JOIN app_private.organization_directed_account_invitation_audit_events AS a
        ON a.invitation_id = c.invitation_id AND a.event_kind = 'invitation_accepted'
      WHERE c.invitation_id = expected.invitation_id
        AND m.organization_workspace_id = '$workspace_id'
        AND m.app_user_id = expected.target_id
        AND m.active_from_utc = c.accepted_at_utc
        AND m.inactive_from_utc IS NULL
        AND a.organization_membership_id = m.organization_membership_id
        AND a.occurred_at_utc = c.accepted_at_utc
    ) THEN
      RAISE EXCEPTION '0087 accepted membership lineage mismatch';
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM app_private.organization_directed_account_invitation_request_claims
    WHERE invitation_id IN ('$create_status_id', '$owner_race_id')
  ) OR EXISTS (
    SELECT 1 FROM app_private.organization_directed_account_invitation_audit_events
    WHERE invitation_id IN ('$create_status_id', '$owner_race_id')
  ) OR EXISTS (
    SELECT 1 FROM app_data.organization_memberships
    WHERE organization_workspace_id = '$workspace_id'
      AND app_user_id IN ('$create_status_target', '$owner_race_target')
  ) OR (SELECT count(*) FROM app_data.organization_owner_assignments AS o
    JOIN app_data.organization_memberships AS m USING (organization_membership_id)
    WHERE m.organization_workspace_id = '$workspace_id') <> 2
  OR EXISTS (
    SELECT 1 FROM app_data.project_memberships AS p
    JOIN app_data.organization_memberships AS m USING (organization_membership_id)
    WHERE m.organization_workspace_id = '$workspace_id'
  ) OR EXISTS (
    SELECT 1 FROM app_data.management_report_capability_grants AS g
    JOIN app_data.project_memberships AS p USING (project_membership_id)
    JOIN app_data.organization_memberships AS m USING (organization_membership_id)
    WHERE m.organization_workspace_id = '$workspace_id'
  ) THEN
    RAISE EXCEPTION '0087 failed paths or implicit authorization changed facts';
  END IF;
END
\$verify\$;
SQL

echo '0087 invitation create/accept replay, drift, governance and status races passed.'
