#!/usr/bin/env bash

set -euo pipefail

# 6BP exercises the candidate through its public SQL executor seam. The
# committed setup uses the legal-hex 6bfc encoding of the 6bpc mnemonic, so it
# survives pg_dump/restore. The rollback fixture uses the separate 6bf prefix. No contact data is
# needed: an enabled empty candidate must complete with protected periods
# suppressed.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
background_pids=()
cleanup() {
  local pid
  for pid in "${background_pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
    fi
    wait "${pid}" 2>/dev/null || true
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

candidate_role='tongxingzhe_management_follow_up_consent_ratio_reader'
config_role='tongxingzhe_management_follow_up_consent_config_writer'
actor_id='6bfc1000-0000-4000-8000-000000000001'
workspace_id='6bfc2000-0000-4000-8000-000000000001'
disable_first_project_id='6bfc3000-0000-4000-8000-000000000001'
candidate_first_disable_project_id='6bfc3000-0000-4000-8000-000000000002'
archive_project_id='6bfc3000-0000-4000-8000-000000000003'
revoke_first_project_id='6bfc3000-0000-4000-8000-000000000004'
membership_revoke_project_id='6bfc3000-0000-4000-8000-000000000005'
candidate_first_capability_revoke_project_id='6bfc3000-0000-4000-8000-000000000006'
archive_first_project_id='6bfc3000-0000-4000-8000-000000000007'
organization_membership_id='6bfc4000-0000-4000-8000-000000000001'
disable_first_project_membership_id='6bfc5000-0000-4000-8000-000000000001'
candidate_first_disable_project_membership_id='6bfc5000-0000-4000-8000-000000000002'
archive_project_membership_id='6bfc5000-0000-4000-8000-000000000003'
revoke_first_project_membership_id='6bfc5000-0000-4000-8000-000000000004'
membership_revoke_project_membership_id='6bfc5000-0000-4000-8000-000000000005'
candidate_first_capability_revoke_project_membership_id='6bfc5000-0000-4000-8000-000000000006'
archive_first_project_membership_id='6bfc5000-0000-4000-8000-000000000007'
disable_first_capability_grant_id='6bfc6000-0000-4000-8000-000000000001'
candidate_first_disable_capability_grant_id='6bfc6000-0000-4000-8000-000000000002'
archive_capability_grant_id='6bfc6000-0000-4000-8000-000000000003'
revoke_first_capability_grant_id='6bfc6000-0000-4000-8000-000000000004'
membership_revoke_capability_grant_id='6bfc6000-0000-4000-8000-000000000005'
candidate_first_capability_revoke_capability_grant_id='6bfc6000-0000-4000-8000-000000000006'
archive_first_capability_grant_id='6bfc6000-0000-4000-8000-000000000007'
enable_disable_first_request_id='6bfc7000-0000-4000-8000-000000000001'
enable_candidate_first_disable_request_id='6bfc7000-0000-4000-8000-000000000002'
enable_archive_request_id='6bfc7000-0000-4000-8000-000000000003'
enable_revoke_first_request_id='6bfc7000-0000-4000-8000-000000000004'
enable_membership_revoke_request_id='6bfc7000-0000-4000-8000-000000000005'
enable_candidate_first_capability_revoke_request_id='6bfc7000-0000-4000-8000-000000000008'
enable_archive_first_request_id='6bfc7000-0000-4000-8000-000000000009'
disable_first_request_id='6bfc7000-0000-4000-8000-000000000006'
candidate_first_disable_disable_request_id='6bfc7000-0000-4000-8000-000000000007'

candidate_first_disable_ready_lock="6bp-candidate-first-disable-ready:${candidate_first_disable_project_id}"
disable_first_ready_lock="6bp-disable-first-ready:${disable_first_project_id}"
revoke_first_ready_lock="6bp-revoke-first-ready:${revoke_first_project_id}"
archive_ready_lock="6bp-candidate-first-archive-ready:${archive_project_id}"
membership_revoke_ready_lock="6bp-candidate-first-membership-revoke-ready:${membership_revoke_project_id}"
candidate_first_capability_revoke_ready_lock="6bp-candidate-first-capability-revoke-ready:${candidate_first_capability_revoke_project_id}"
archive_first_ready_lock="6bp-archive-first-ready:${archive_first_project_id}"

assert_json_status() {
  local file_path="$1"
  local expected_status="$2"
  if ! grep -Eq "\"status\"[[:space:]]*:[[:space:]]*\"${expected_status}\"" \
    "${file_path}"; then
    echo "未在 ${file_path} 中观察到 status=${expected_status}。" >&2
    sed -n '1,160p' "${file_path}" >&2
    exit 1
  fi
}

assert_waiter_observed() {
  local file_path="$1"
  if ! grep -q 'waiter observed' "${file_path}"; then
    echo "${file_path} 未记录实际 advisory waiter。" >&2
    sed -n '1,160p' "${file_path}" >&2
    exit 1
  fi
}

probe_session_lock() {
  local lock_name="$1"
  local result
  result="$("${psql_base[@]}" --tuples-only --no-align --command="
    SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('${lock_name}', 0))
        THEN 'not-ready'
      ELSE 'ready'
    END;
  ")"
  [[ "${result}" == *ready* && "${result}" != *not-ready* ]]
}

wait_for_barrier() {
  local lock_name="$1"
  local label="$2"
  local attempt
  for attempt in $(seq 1 200); do
    if probe_session_lock "${lock_name}"; then
      return 0
    fi
    sleep 0.1
  done
  echo "6BP ${label} session did not reach its barrier." >&2
  return 1
}

# All hierarchy rows derive their boundaries from one transaction timestamp.
# This keeps the parent/child containment triggers deterministic on restore.
"${psql_base[@]}" --command="
  BEGIN;
  CREATE TEMP TABLE fixture_6bpc_clock ON COMMIT DROP AS
  SELECT transaction_timestamp() AS fixture_now_utc;
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('${actor_id}'::uuid, 'active');
  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name, personal_owner_app_user_id
  ) VALUES (
    '${workspace_id}'::uuid, 'organization',
    '6BP committed concurrency organization', NULL
  );
  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status, is_personal_default
  ) VALUES
    (
      '${disable_first_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP disable-first project', 'active', false
    ),
    (
      '${candidate_first_disable_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP candidate-first disable project', 'active', false
    ),
    (
      '${archive_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP candidate-first archive project', 'active', false
    ),
    (
      '${revoke_first_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP revoke-first project', 'active', false
    ),
    (
      '${membership_revoke_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP candidate-first membership revoke project', 'active', false
    ),
    (
      '${candidate_first_capability_revoke_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP candidate-first capability revoke project', 'active', false
    ),
    (
      '${archive_first_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BP archive-first project', 'active', false
    );
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  )
  SELECT
    '${organization_membership_id}'::uuid,
    '${workspace_id}'::uuid,
    '${actor_id}'::uuid,
    fixture_now_utc - interval '365 days',
    NULL
  FROM fixture_6bpc_clock;
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    '6bfc8000-0000-4000-8000-000000000001'::uuid,
    '${organization_membership_id}'::uuid,
    transaction_timestamp(),
    NULL
  );
  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id, project_id,
    active_from_utc, inactive_from_utc
  )
  SELECT membership_id, '${organization_membership_id}'::uuid, project_id,
         fixture_now_utc - interval '365 days', NULL
  FROM (
    VALUES
      ('${disable_first_project_membership_id}'::uuid, '${disable_first_project_id}'::uuid),
      ('${candidate_first_disable_project_membership_id}'::uuid, '${candidate_first_disable_project_id}'::uuid),
      ('${archive_project_membership_id}'::uuid, '${archive_project_id}'::uuid),
      ('${revoke_first_project_membership_id}'::uuid, '${revoke_first_project_id}'::uuid),
      ('${membership_revoke_project_membership_id}'::uuid, '${membership_revoke_project_id}'::uuid),
      ('${candidate_first_capability_revoke_project_membership_id}'::uuid, '${candidate_first_capability_revoke_project_id}'::uuid),
      ('${archive_first_project_membership_id}'::uuid, '${archive_first_project_id}'::uuid)
  ) AS membership_rows(membership_id, project_id)
  CROSS JOIN fixture_6bpc_clock;
  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id,
    active_from_utc, inactive_from_utc
  )
  SELECT grant_id, project_membership_id, 'release_management_reports',
         fixture_now_utc - interval '365 days', NULL
  FROM (
    VALUES
      ('${disable_first_capability_grant_id}'::uuid, '${disable_first_project_membership_id}'::uuid),
      ('${candidate_first_disable_capability_grant_id}'::uuid, '${candidate_first_disable_project_membership_id}'::uuid),
      ('${archive_capability_grant_id}'::uuid, '${archive_project_membership_id}'::uuid),
      ('${revoke_first_capability_grant_id}'::uuid, '${revoke_first_project_membership_id}'::uuid),
      ('${membership_revoke_capability_grant_id}'::uuid, '${membership_revoke_project_membership_id}'::uuid),
      ('${candidate_first_capability_revoke_capability_grant_id}'::uuid, '${candidate_first_capability_revoke_project_membership_id}'::uuid),
      ('${archive_first_capability_grant_id}'::uuid, '${archive_first_project_membership_id}'::uuid)
  ) AS grant_rows(grant_id, project_membership_id)
  CROSS JOIN fixture_6bpc_clock;
  COMMIT;
"

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${disable_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_disable_first_request_id}'::uuid,
    0, true
  );
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${candidate_first_disable_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_candidate_first_disable_request_id}'::uuid,
    0, true
  );
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${archive_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_archive_request_id}'::uuid,
    0, true
  );
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${revoke_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_revoke_first_request_id}'::uuid,
    0, true
  );
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${membership_revoke_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_membership_revoke_request_id}'::uuid,
    0, true
  );
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${candidate_first_capability_revoke_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_candidate_first_capability_revoke_request_id}'::uuid,
    0, true
  );
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${archive_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${enable_archive_first_request_id}'::uuid,
    0, true
  );
" >/dev/null

# Candidate-first -> disable. The completed candidate keeps the authorization
# and opt-in locks until its transaction commits. The disable request must
# wait, then a new candidate observes the committed disabled version.

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${candidate_first_disable_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
  SELECT pg_advisory_lock(
    hashtextextended('${candidate_first_disable_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'candidate-first disable waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: candidate-first disable';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${candidate_first_disable_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/candidate-first-disable.out" 2>&1 &
candidate_first_disable_pid=$!
background_pids+=( "${candidate_first_disable_pid}" )
wait_for_barrier "${candidate_first_disable_ready_lock}" 'candidate-first disable'

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${candidate_first_disable_project_id}'::uuid,
    'follow_up_consent_ratio@1',
    '${candidate_first_disable_disable_request_id}'::uuid,
    1, false
  );
" >"${temporary_directory}/disable-after-candidate.out" 2>&1 &
candidate_first_disable_disable_pid=$!
background_pids+=( "${candidate_first_disable_disable_pid}" )

candidate_first_disable_status=0
candidate_first_disable_disable_status=0
wait "${candidate_first_disable_pid}" || candidate_first_disable_status=$?
wait "${candidate_first_disable_disable_pid}" || candidate_first_disable_disable_status=$?
assert_waiter_observed "${temporary_directory}/candidate-first-disable.out"
if [[ "${candidate_first_disable_status}" -ne 0 \
  || "${candidate_first_disable_disable_status}" -ne 0 ]]; then
  echo "6BP candidate-first disable result unexpected: candidate=${candidate_first_disable_status}, disable=${candidate_first_disable_disable_status}" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-first-disable.out" >&2
  sed -n '1,160p' "${temporary_directory}/disable-after-candidate.out" >&2
  exit 1
fi
assert_json_status "${temporary_directory}/candidate-first-disable.out" 'completed'
if ! grep -q '"privacy_status": "suppressed"' \
  "${temporary_directory}/candidate-first-disable.out"; then
  echo '6BP enabled empty candidate did not return suppressed protected periods.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-first-disable.out" >&2
  exit 1
fi

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${candidate_first_disable_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-disable.out" 2>&1
assert_json_status "${temporary_directory}/candidate-after-disable.out" 'not_enabled'
if grep -q '"periods"' "${temporary_directory}/candidate-after-disable.out"; then
  echo '6BP candidate after disable returned periods.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-disable.out" >&2
  exit 1
fi
echo '6BP candidate-first disable passed: completed candidate preceded a waiting disable and later not_enabled.'

# Disable-first -> candidate. The disable transaction commits only after the
# candidate has been observed waiting on its authorization/opt-in locks.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${disable_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${disable_first_request_id}'::uuid,
    1, false
  );
  SELECT pg_advisory_lock(
    hashtextextended('${disable_first_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'disable-first candidate waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: disable-first candidate';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${disable_first_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/disable-first.out" 2>&1 &
disable_first_pid=$!
background_pids+=( "${disable_first_pid}" )
wait_for_barrier "${disable_first_ready_lock}" 'disable-first'

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${disable_first_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-disable-first.out" 2>&1 &
disable_first_candidate_pid=$!
background_pids+=( "${disable_first_candidate_pid}" )

disable_first_status=0
disable_first_candidate_status=0
wait "${disable_first_pid}" || disable_first_status=$?
wait "${disable_first_candidate_pid}" || disable_first_candidate_status=$?
assert_waiter_observed "${temporary_directory}/disable-first.out"
if [[ "${disable_first_status}" -ne 0 \
  || "${disable_first_candidate_status}" -ne 0 ]]; then
  echo "6BP disable-first result unexpected: disable=${disable_first_status}, candidate=${disable_first_candidate_status}" >&2
  sed -n '1,160p' "${temporary_directory}/disable-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-disable-first.out" >&2
  exit 1
fi
assert_json_status "${temporary_directory}/candidate-after-disable-first.out" 'not_enabled'
if grep -q '"periods"' "${temporary_directory}/candidate-after-disable-first.out"; then
  echo '6BP disable-first candidate returned periods.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-disable-first.out" >&2
  exit 1
fi
echo '6BP disable-first passed: candidate waited and observed committed not_enabled.'


# Revoke-first -> candidate. The capability trigger holds the same
# authorization hierarchy locks as the resolver. Once the revoke commits, the
# candidate must fail closed instead of returning a stale completed document.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${revoke_first_capability_grant_id}'::uuid;
  SELECT pg_advisory_lock(
    hashtextextended('${revoke_first_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'revoke-first candidate waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: revoke-first candidate';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${revoke_first_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/revoke-first.out" 2>&1 &
revoke_first_pid=$!
background_pids+=( "${revoke_first_pid}" )
wait_for_barrier "${revoke_first_ready_lock}" 'revoke-first'

set +e
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${revoke_first_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-revoke.out" 2>&1 &
revoke_first_candidate_pid=$!
background_pids+=( "${revoke_first_candidate_pid}" )
revoke_first_status=0
revoke_first_candidate_status=0
wait "${revoke_first_pid}" || revoke_first_status=$?
wait "${revoke_first_candidate_pid}" || revoke_first_candidate_status=$?
set -e
assert_waiter_observed "${temporary_directory}/revoke-first.out"
if [[ "${revoke_first_status}" -ne 0 \
  || "${revoke_first_candidate_status}" -eq 0 ]]; then
  echo "6BP revoke-first result unexpected: revoke=${revoke_first_status}, candidate=${revoke_first_candidate_status}" >&2
  sed -n '1,160p' "${temporary_directory}/revoke-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-revoke.out" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${temporary_directory}/candidate-after-revoke.out"; then
  echo '6BP candidate after capability revoke did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-revoke.out" >&2
  exit 1
fi
echo '6BP revoke-first passed: candidate waited and failed closed after capability revocation.'

# Candidate-first -> project archive. The project status trigger waits on the
# candidate authorization locks. A subsequent candidate is forbidden after the
# archive commits.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${archive_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
  SELECT pg_advisory_lock(
    hashtextextended('${archive_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'candidate-first archive waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: candidate-first archive';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${archive_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/candidate-first-archive.out" 2>&1 &
candidate_first_archive_pid=$!
background_pids+=( "${candidate_first_archive_pid}" )
wait_for_barrier "${archive_ready_lock}" 'candidate-first archive'

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = '${archive_project_id}'::uuid;
" >"${temporary_directory}/archive-after-candidate.out" 2>&1 &
candidate_first_archive_update_pid=$!
background_pids+=( "${candidate_first_archive_update_pid}" )

set +e
candidate_first_archive_status=0
candidate_first_archive_update_status=0
wait "${candidate_first_archive_pid}" || candidate_first_archive_status=$?
wait "${candidate_first_archive_update_pid}" || candidate_first_archive_update_status=$?
set -e
assert_waiter_observed "${temporary_directory}/candidate-first-archive.out"
if [[ "${candidate_first_archive_status}" -ne 0 \
  || "${candidate_first_archive_update_status}" -ne 0 ]]; then
  echo "6BP candidate-first archive result unexpected: candidate=${candidate_first_archive_status}, archive=${candidate_first_archive_update_status}" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-first-archive.out" >&2
  sed -n '1,160p' "${temporary_directory}/archive-after-candidate.out" >&2
  exit 1
fi
assert_json_status "${temporary_directory}/candidate-first-archive.out" 'completed'

set +e
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${archive_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-archive.out" 2>&1
candidate_after_archive_status=$?
set -e
if [[ "${candidate_after_archive_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' \
    "${temporary_directory}/candidate-after-archive.out"; then
  echo '6BP candidate after project archive did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-archive.out" >&2
  exit 1
fi
echo '6BP candidate-first archive passed: archive waited and later candidate was forbidden.'

# Candidate-first -> membership revoke. The capability is closed before its
# parent project membership in one transaction, as required by the hierarchy
# trigger. The candidate keeps the shared authorization locks, so the revoke
# transaction waits before either closure commits.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${membership_revoke_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
  SELECT pg_advisory_lock(
    hashtextextended('${membership_revoke_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'candidate-first membership revoke waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: candidate-first membership revoke';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${membership_revoke_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/candidate-first-membership-revoke.out" 2>&1 &
candidate_first_membership_revoke_pid=$!
background_pids+=( "${candidate_first_membership_revoke_pid}" )
wait_for_barrier "${membership_revoke_ready_lock}" 'candidate-first membership revoke'

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${membership_revoke_capability_grant_id}'::uuid;
  UPDATE app_data.project_memberships
  SET inactive_from_utc = (
    SELECT capability_grant.inactive_from_utc
    FROM app_data.management_report_capability_grants AS capability_grant
    WHERE capability_grant.capability_grant_id =
      '${membership_revoke_capability_grant_id}'::uuid
  )
  WHERE project_membership_id = '${membership_revoke_project_membership_id}'::uuid;
  COMMIT;
" >"${temporary_directory}/membership-revoke-after-candidate.out" 2>&1 &
candidate_first_membership_revoke_update_pid=$!
background_pids+=( "${candidate_first_membership_revoke_update_pid}" )

candidate_first_membership_revoke_status=0
candidate_first_membership_revoke_update_status=0
wait "${candidate_first_membership_revoke_pid}" \
  || candidate_first_membership_revoke_status=$?
wait "${candidate_first_membership_revoke_update_pid}" \
  || candidate_first_membership_revoke_update_status=$?
assert_waiter_observed "${temporary_directory}/candidate-first-membership-revoke.out"
if [[ "${candidate_first_membership_revoke_status}" -ne 0 \
  || "${candidate_first_membership_revoke_update_status}" -ne 0 ]]; then
  echo "6BP candidate-first membership revoke result unexpected: candidate=${candidate_first_membership_revoke_status}, revoke=${candidate_first_membership_revoke_update_status}" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-first-membership-revoke.out" >&2
  sed -n '1,160p' "${temporary_directory}/membership-revoke-after-candidate.out" >&2
  exit 1
fi
assert_json_status "${temporary_directory}/candidate-first-membership-revoke.out" 'completed'

membership_revoke_state="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT
    (SELECT count(*) FROM app_data.project_memberships
     WHERE project_membership_id = '${membership_revoke_project_membership_id}'::uuid
       AND inactive_from_utc IS NOT NULL),
    (SELECT count(*) FROM app_data.management_report_capability_grants
     WHERE capability_grant_id = '${membership_revoke_capability_grant_id}'::uuid
       AND inactive_from_utc IS NOT NULL);
")"
membership_revoke_state="$(printf '%s' "${membership_revoke_state}" | tr -d '[:space:]')"
if [[ "${membership_revoke_state}" != '1|1' ]]; then
  echo "6BP membership revoke did not close both hierarchy rows: ${membership_revoke_state}" >&2
  exit 1
fi

set +e
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${membership_revoke_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-membership-revoke.out" 2>&1
candidate_after_membership_revoke_status=$?
set -e
if [[ "${candidate_after_membership_revoke_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' \
    "${temporary_directory}/candidate-after-membership-revoke.out"; then
  echo '6BP candidate after project membership revoke did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-membership-revoke.out" >&2
  exit 1
fi
echo '6BP candidate-first membership revoke passed: hierarchy closure waited and later candidate was forbidden.'


# Candidate-first -> capability revoke. The completed candidate holds the
# authorization hierarchy locks; the capability update must wait and then
# commit. A new candidate after the revoke must fail closed.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${candidate_first_capability_revoke_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
  SELECT pg_advisory_lock(
    hashtextextended('${candidate_first_capability_revoke_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'candidate-first capability revoke waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: candidate-first capability revoke';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${candidate_first_capability_revoke_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/candidate-first-capability-revoke.out" 2>&1 &
candidate_first_capability_revoke_pid=$!
background_pids+=( "${candidate_first_capability_revoke_pid}" )
wait_for_barrier "${candidate_first_capability_revoke_ready_lock}" 'candidate-first capability revoke'

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '${candidate_first_capability_revoke_capability_grant_id}'::uuid;
  COMMIT;
" >"${temporary_directory}/capability-revoke-after-candidate.out" 2>&1 &
candidate_first_capability_revoke_update_pid=$!
background_pids+=( "${candidate_first_capability_revoke_update_pid}" )

candidate_first_capability_revoke_status=0
candidate_first_capability_revoke_update_status=0
wait "${candidate_first_capability_revoke_pid}" \
  || candidate_first_capability_revoke_status=$?
wait "${candidate_first_capability_revoke_update_pid}" \
  || candidate_first_capability_revoke_update_status=$?
assert_waiter_observed "${temporary_directory}/candidate-first-capability-revoke.out"
if [[ "${candidate_first_capability_revoke_status}" -ne 0 \
  || "${candidate_first_capability_revoke_update_status}" -ne 0 ]]; then
  echo "6BP candidate-first capability revoke result unexpected: candidate=${candidate_first_capability_revoke_status}, revoke=${candidate_first_capability_revoke_update_status}" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-first-capability-revoke.out" >&2
  sed -n '1,160p' "${temporary_directory}/capability-revoke-after-candidate.out" >&2
  exit 1
fi
assert_json_status "${temporary_directory}/candidate-first-capability-revoke.out" 'completed'

capability_revoke_state="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_data.management_report_capability_grants
  WHERE capability_grant_id =
    '${candidate_first_capability_revoke_capability_grant_id}'::uuid
    AND inactive_from_utc IS NOT NULL;
")"
capability_revoke_state="$(printf '%s' "${capability_revoke_state}" | tr -d '[:space:]')"
if [[ "${capability_revoke_state}" != '1' ]]; then
  echo "6BP capability revoke did not commit: ${capability_revoke_state}" >&2
  exit 1
fi

set +e
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${candidate_first_capability_revoke_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-capability-revoke.out" 2>&1
candidate_after_capability_revoke_status=$?
set -e
if [[ "${candidate_after_capability_revoke_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' \
    "${temporary_directory}/candidate-after-capability-revoke.out"; then
  echo '6BP candidate after capability revoke did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-capability-revoke.out" >&2
  exit 1
fi
echo '6BP candidate-first capability revoke passed: revoke waited and later candidate was forbidden.'

# Archive-first -> candidate. The project status trigger acquires the shared
# authorization locks before its commit; the candidate waits, then observes
# the committed archive and fails closed.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = '${archive_first_project_id}'::uuid;
  SELECT pg_advisory_lock(
    hashtextextended('${archive_first_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'archive-first candidate waiter was not observed';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
    RAISE NOTICE 'waiter observed: archive-first candidate';
  END
  \$wait\$;
  SELECT pg_advisory_unlock(
    hashtextextended('${archive_first_ready_lock}', 0)
  );
  COMMIT;
" >"${temporary_directory}/archive-first.out" 2>&1 &
archive_first_pid=$!
background_pids+=( "${archive_first_pid}" )
wait_for_barrier "${archive_first_ready_lock}" 'archive-first'

set +e
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  SET ROLE ${candidate_role};
  SELECT app_private.execute_management_follow_up_consent_ratio_report_v1(
    '${actor_id}'::uuid, '${archive_first_project_id}'::uuid,
    'UTC', clock_timestamp()
  );
" >"${temporary_directory}/candidate-after-archive-first.out" 2>&1 &
archive_first_candidate_pid=$!
background_pids+=( "${archive_first_candidate_pid}" )
archive_first_status=0
archive_first_candidate_status=0
wait "${archive_first_pid}" || archive_first_status=$?
wait "${archive_first_candidate_pid}" || archive_first_candidate_status=$?
set -e
assert_waiter_observed "${temporary_directory}/archive-first.out"
if [[ "${archive_first_status}" -ne 0 \
  || "${archive_first_candidate_status}" -eq 0 ]]; then
  echo "6BP archive-first result unexpected: archive=${archive_first_status}, candidate=${archive_first_candidate_status}" >&2
  sed -n '1,160p' "${temporary_directory}/archive-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-archive-first.out" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${temporary_directory}/candidate-after-archive-first.out"; then
  echo '6BP archive-first candidate did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/candidate-after-archive-first.out" >&2
  exit 1
fi
echo '6BP archive-first passed: candidate waited and failed closed after archive.'




echo 'management follow-up consent ratio concurrency check passed.'
