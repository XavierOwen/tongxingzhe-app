#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

run_psql() {
  "${psql_command}" "${DATABASE_URL}" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    "$@"
}

temporary_directory="$(mktemp -d)"
read_first_pid=''
revoke_first_pid=''
read_second_pid=''
release_gate_pid=''

cleanup() {
  for pid in "${read_first_pid}" "${revoke_first_pid}" "${read_second_pid}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  if [[ -n "${release_gate_pid}" ]] \
    && kill -0 "${release_gate_pid}" >/dev/null 2>&1; then
    kill "${release_gate_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${release_gate_pid}" ]]; then
    wait "${release_gate_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_ready_lock() {
  local lock_name="$1"
  local pid="$2"
  local output="$3"
  local held

  for _ in $(seq 1 100); do
    held="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT (hashtextextended('${lock_name}', 0) >> 32)
          & 4294967295 AS classid,
          hashtextextended('${lock_name}', 0) & 4294967295 AS objid
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND lock_row.granted
          AND lock_row.pid <> pg_backend_pid()
      );
    " | tr -d '[:space:]')"
    if [[ "${held}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
  sed -n '1,160p' "${output}" >&2
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  exit 1
}

wait_for_waiting_lock() {
  local lock_name="$1"
  local pid="$2"
  local output="$3"
  local waiting

  for _ in $(seq 1 100); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      wait "${pid}" >/dev/null 2>&1 || true
      sed -n '1,160p' "${output}" >&2
      echo "没有观察到读取等待的 capability lock：${lock_name}" >&2
      exit 1
    fi
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT (hashtextextended('${lock_name}', 0) >> 32)
          & 4294967295 AS classid,
          hashtextextended('${lock_name}', 0) & 4294967295 AS objid
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
          AND lock_row.pid <> pg_backend_pid()
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
  sed -n '1,160p' "${output}" >&2
  echo "没有观察到读取等待的 capability lock：${lock_name}" >&2
  exit 1
}

# The 6dx namespace is committed on purpose.  The Docker runner removes the
# source container afterwards; a direct invocation must use a dedicated test
# database.  The 6ax fixture uses 6c* identifiers and cannot collide with it.
run_psql <<'SQL'
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6d110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6d110000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6d110000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
VALUES (
  '6d120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AX interest read concurrency workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES (
  '6d130000-0000-4000-8000-000000000001'::uuid,
  '6d120000-0000-4000-8000-000000000001'::uuid,
  '6AX interest read concurrency project'
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES (
  '6d140000-0000-4000-8000-000000000001'::uuid,
  '6d130000-0000-4000-8000-000000000001'::uuid,
  1, 'published', true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6d160000-0000-4000-8000-000000000001'::uuid,
    '6d120000-0000-4000-8000-000000000001'::uuid,
    '6d110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6d160000-0000-4000-8000-000000000002'::uuid,
    '6d120000-0000-4000-8000-000000000001'::uuid,
    '6d110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6d160000-0000-4000-8000-000000000003'::uuid,
    '6d120000-0000-4000-8000-000000000001'::uuid,
    '6d110000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6d170000-0000-4000-8000-000000000001'::uuid,
    '6d160000-0000-4000-8000-000000000001'::uuid,
    '6d130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6d170000-0000-4000-8000-000000000002'::uuid,
    '6d160000-0000-4000-8000-000000000002'::uuid,
    '6d130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6d170000-0000-4000-8000-000000000003'::uuid,
    '6d160000-0000-4000-8000-000000000003'::uuid,
    '6d130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6d180000-0000-4000-8000-000000000001'::uuid,
    '6d170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6d180000-0000-4000-8000-000000000002'::uuid,
    '6d170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6d180000-0000-4000-8000-000000000003'::uuid,
    '6d170000-0000-4000-8000-000000000003'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6d150000-0000-4000-8000-000000000001'::uuid,
  '6d110000-0000-4000-8000-000000000001'::uuid,
  '6d130000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

CREATE TEMP TABLE fixture_6dx_report_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, reach_count, interest_level
)
SELECT
  format('6dx-interest-%s-%s-%s-%s', period_row.period_key, level_row,
    contributor_row.contributor_number, unit_row.unit_number),
  CASE contributor_row.contributor_number
    WHEN 1 THEN '6d110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN '6d110000-0000-4000-8000-000000000002'::uuid
    ELSE '6d110000-0000-4000-8000-000000000003'::uuid
  END,
  '6d120000-0000-4000-8000-000000000001'::uuid,
  '6d130000-0000-4000-8000-000000000001'::uuid,
  '6d140000-0000-4000-8000-000000000001'::uuid,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 minute'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 minute'
  END,
  'UTC', clock_timestamp(), 'voice_call', 'not_applicable', 1, level_row
FROM fixture_6dx_report_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN generate_series(0, 4) AS level_row
CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
  AS contributor_row(contributor_number, unit_count)
CROSS JOIN LATERAL generate_series(1, contributor_row.unit_count)
  AS unit_row(unit_number);

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
) VALUES (
  '6d110000-0000-4000-8000-000000000001'::uuid,
  '6d120000-0000-4000-8000-000000000001'::uuid,
  '6d130000-0000-4000-8000-000000000001'::uuid,
  '6dx-interest-watermark', 1, 'contact.submitted'
);

SELECT app_private.release_management_interest_report_snapshot_v1(
  '6d800000-0000-4000-8000-000000000001'::uuid,
  '6d110000-0000-4000-8000-000000000001'::uuid,
  '6d130000-0000-4000-8000-000000000001'::uuid,
  'contact_sessions_by_interest_level_two_periods', 1
);
SQL

snapshot_id="$(run_psql --tuples-only --no-align --command="
  SELECT released_snapshot_id
  FROM app_private.management_interest_report_release_attempts
  WHERE release_request_id =
    '6d800000-0000-4000-8000-000000000001'::uuid;
" | tr -d '[:space:]')"
if [[ ! "${snapshot_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "6AX interest read concurrency fixture did not create a snapshot: ${snapshot_id}" >&2
  exit 1
fi

capability_lock_user2='management-report-capability:6d130000-0000-4000-8000-000000000001:6d110000-0000-4000-8000-000000000002:view_anonymous_analytics'
capability_lock_user3='management-report-capability:6d130000-0000-4000-8000-000000000001:6d110000-0000-4000-8000-000000000003:view_anonymous_analytics'
organization_lock_user3='organization-membership:6d120000-0000-4000-8000-000000000001:6d110000-0000-4000-8000-000000000003'

# Read-first: the read owns the authorization locks until commit.  Revocation
# must wait, so this read is a valid completed pre-revocation observation.
read_first_ready='management-interest-read-first-6ax'
read_first_output="${temporary_directory}/read-first.out"
run_psql --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.read_authorized_management_interest_report_snapshot_v1(
    '6d110000-0000-4000-8000-000000000002'::uuid,
    '6d130000-0000-4000-8000-000000000001'::uuid,
    '${snapshot_id}'::uuid
  );
  SELECT pg_advisory_lock(hashtextextended('${read_first_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${read_first_output}" 2>&1 &
read_first_pid=$!
wait_for_ready_lock "${read_first_ready}" "${read_first_pid}" "${read_first_output}"

revoke_first_output="${temporary_directory}/revoke-first.out"
run_psql --command="
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '6d180000-0000-4000-8000-000000000002'::uuid;
  COMMIT;
" >"${revoke_first_output}" 2>&1 &
revoke_first_pid=$!
sleep 0.3
if ! kill -0 "${revoke_first_pid}" >/dev/null 2>&1; then
  wait "${revoke_first_pid}" >/dev/null 2>&1 || true
  echo "revoke-first 没有等待 read-first 的 capability lock：${capability_lock_user2}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  exit 1
fi

read_first_status=0
revoke_first_status=0
wait "${read_first_pid}" || read_first_status=$?
wait "${revoke_first_pid}" || revoke_first_status=$?
if [[ "${read_first_status}" -ne 0 || "${revoke_first_status}" -ne 0 ]] \
  || ! grep -Eq '"result_status"[[:space:]]*:[[:space:]]*"completed"' \
    "${read_first_output}"; then
  echo '6AX read-first / revoke-first 并发合同失败。' >&2
  sed -n '1,160p' "${read_first_output}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  exit 1
fi

# Revoke-first uses the independent active grant for user 3.  The reader must
# wait for the capability lock and fail closed after the revoke commits.
revoke_second_ready='management-interest-revoke-first-6ax'
release_gate='management-interest-revoke-commit-gate-6ax'
release_gate_output="${temporary_directory}/release-gate.out"
run_psql --command="
  SELECT pg_advisory_lock(hashtextextended('${release_gate}', 0));
  SELECT pg_sleep(20);
" >"${release_gate_output}" 2>&1 &
release_gate_pid=$!
wait_for_ready_lock "${release_gate}" \
  "${release_gate_pid}" "${release_gate_output}"

revoke_second_output="${temporary_directory}/revoke-second.out"
run_psql --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:6d120000-0000-4000-8000-000000000001:6d110000-0000-4000-8000-000000000003',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:6d130000-0000-4000-8000-000000000001:6d110000-0000-4000-8000-000000000003',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    '${capability_lock_user3}', 0
  ));
  SELECT pg_advisory_lock(hashtextextended('${revoke_second_ready}', 0));
  SELECT pg_advisory_lock(hashtextextended('${release_gate}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '6d180000-0000-4000-8000-000000000003'::uuid;
  COMMIT;
" >"${revoke_second_output}" 2>&1 &
revoke_first_pid=$!
wait_for_ready_lock "${revoke_second_ready}" "${revoke_first_pid}" "${revoke_second_output}"

read_second_output="${temporary_directory}/read-second.out"
run_psql --command="
  SET statement_timeout = '20s';
  SELECT app_private.read_authorized_management_interest_report_snapshot_v1(
    '6d110000-0000-4000-8000-000000000003'::uuid,
    '6d130000-0000-4000-8000-000000000001'::uuid,
    '${snapshot_id}'::uuid
  );
" >"${read_second_output}" 2>&1 &
read_second_pid=$!
wait_for_waiting_lock "${organization_lock_user3}" \
  "${read_second_pid}" "${read_second_output}"

# The read is now demonstrably blocked on the exact authorization lock. End the
# exact PostgreSQL backend that owns the release gate. Killing the shell job is
# insufficient because psql can continue as its child and retain the session
# advisory lock.
gate_terminated="$(run_psql --tuples-only --no-align --command="
  WITH lock_key AS (
    SELECT (hashtextextended('${release_gate}', 0) >> 32)
      & 4294967295 AS classid,
      hashtextextended('${release_gate}', 0) & 4294967295 AS objid
  )
  SELECT pg_terminate_backend(lock_row.pid)
  FROM pg_locks AS lock_row
  JOIN lock_key
    ON lock_row.classid::bigint = lock_key.classid
   AND lock_row.objid::bigint = lock_key.objid
  WHERE lock_row.locktype = 'advisory'
    AND lock_row.granted
    AND lock_row.pid <> pg_backend_pid();
" | tr -d '[:space:]')"
if [[ "${gate_terminated}" != 't' ]]; then
  echo "6AX 无法释放 revoke-first gate：${gate_terminated}" >&2
  exit 1
fi
wait "${release_gate_pid}" >/dev/null 2>&1 || true
release_gate_pid=''

revoke_second_status=0
read_second_status=0
wait "${revoke_first_pid}" || revoke_second_status=$?
wait "${read_second_pid}" || read_second_status=$?
if [[ "${revoke_second_status}" -ne 0 || "${read_second_status}" -eq 0 ]]; then
  echo "6AX revoke-first / read-second 并发合同失败：revoke=${revoke_second_status}, read=${read_second_status}" >&2
  sed -n '1,160p' "${revoke_second_output}" >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' "${read_second_output}"; then
  echo '6AX read-second 没有因撤权失败关闭。' >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi

audit_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_interest_report_snapshot_access_events
  WHERE project_id = '6d130000-0000-4000-8000-000000000001'::uuid;
" | tr -d '[:space:]')"
if [[ "${audit_count}" != '1' ]]; then
  echo "6AX 撤权后不应追加访问审计：${audit_count}" >&2
  exit 1
fi

echo '6AX interest snapshot read concurrency passed: read/revocation ordering fails closed after authorization lock linearization.'
