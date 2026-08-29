#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
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

wait_for_ready() {
  local ready_lock="$1"
  local first_pid="$2"
  local first_output="$3"
  local probe

  for _ in $(seq 1 80); do
    probe="$(${psql_base[@]} --tuples-only --no-align --command="
      WITH lock_probe AS (
        SELECT pg_try_advisory_lock(
          hashtextextended('${ready_lock}', 0)
        ) AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${ready_lock}', 0)
        )
        ELSE true
      END
      FROM lock_probe;
    " | tr -d '[:space:]')"
    if [[ "${probe}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${first_pid}" >/dev/null 2>&1 || true
  wait "${first_pid}" >/dev/null 2>&1 || true
  echo 'follow-up consent directory concurrency session did not hold its ready lock.' >&2
  sed -n '1,160p' "${first_output}" >&2
  exit 1
}

# These committed rows use a namespace distinct from the rollback fixture.
# They deliberately contain no snapshot rows: the race proves only that the
# directory and capability revocation share the resolver's lock order.
"${psql_base[@]}" --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status) VALUES
    ('a6f10000-0000-4000-8000-000000000001'::uuid, 'active'),
    ('a6f10000-0000-4000-8000-000000000002'::uuid, 'active');

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    'a6f20000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Follow-up consent directory concurrency organization'
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status
  ) VALUES (
    'a6f30000-0000-4000-8000-000000000001'::uuid,
    'a6f20000-0000-4000-8000-000000000001'::uuid,
    'Follow-up consent directory concurrency project',
    'active'
  );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id,
    app_user_id, active_from_utc
  ) VALUES
    (
      'a6f40000-0000-4000-8000-000000000001'::uuid,
      'a6f20000-0000-4000-8000-000000000001'::uuid,
      'a6f10000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp() - interval '1 day'
    ),
    (
      'a6f40000-0000-4000-8000-000000000002'::uuid,
      'a6f20000-0000-4000-8000-000000000001'::uuid,
      'a6f10000-0000-4000-8000-000000000002'::uuid,
      transaction_timestamp() - interval '1 day'
    );

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    'a6fa0000-0000-4000-8000-000000000001'::uuid,
    'a6f40000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  );

  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id,
    project_id, active_from_utc
  ) VALUES
    (
      'a6f50000-0000-4000-8000-000000000001'::uuid,
      'a6f40000-0000-4000-8000-000000000001'::uuid,
      'a6f30000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp() - interval '1 day'
    ),
    (
      'a6f50000-0000-4000-8000-000000000002'::uuid,
      'a6f40000-0000-4000-8000-000000000002'::uuid,
      'a6f30000-0000-4000-8000-000000000001'::uuid,
      transaction_timestamp() - interval '1 day'
    );

  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id,
    capability_id, active_from_utc
  ) VALUES
    (
      'a6f60000-0000-4000-8000-000000000001'::uuid,
      'a6f50000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics',
      transaction_timestamp() - interval '1 day'
    ),
    (
      'a6f60000-0000-4000-8000-000000000002'::uuid,
      'a6f50000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics',
      transaction_timestamp() - interval '1 day'
    );
  COMMIT;
"

directory_first_output="${temporary_directory}/directory-first.out"
revocation_second_output="${temporary_directory}/revocation-second.out"
directory_first_ready='follow-up-consent-directory-ready:directory-first'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.list_authorized_management_follow_up_consent_snapshots_v1(
    'a6f10000-0000-4000-8000-000000000001'::uuid,
    'a6f30000-0000-4000-8000-000000000001'::uuid
  );
  SELECT pg_advisory_lock(hashtextextended('${directory_first_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'capability revocation did not wait for directory read';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${directory_first_output}" 2>&1 &
directory_first_pid=$!

wait_for_ready "${directory_first_ready}" "${directory_first_pid}" "${directory_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:a6f20000-0000-4000-8000-000000000001:a6f10000-0000-4000-8000-000000000001',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:a6f30000-0000-4000-8000-000000000001:a6f10000-0000-4000-8000-000000000001',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:a6f30000-0000-4000-8000-000000000001:a6f10000-0000-4000-8000-000000000001:view_anonymous_analytics',
    0
  ));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = 'a6f60000-0000-4000-8000-000000000001'::uuid;
  COMMIT;
" >"${revocation_second_output}" 2>&1 &
revocation_second_pid=$!

directory_first_status=0
revocation_second_status=0
wait "${directory_first_pid}" || directory_first_status=$?
wait "${revocation_second_pid}" || revocation_second_status=$?
if [[ "${directory_first_status}" -ne 0 || "${revocation_second_status}" -ne 0 ]]; then
  echo "directory-first race failed: directory=${directory_first_status}, revocation=${revocation_second_status}" >&2
  sed -n '1,160p' "${directory_first_output}" >&2
  sed -n '1,160p' "${revocation_second_output}" >&2
  exit 1
fi

directory_first_state="$("${psql_base[@]}" --tuples-only --no-align --field-separator='|' --command="
  SELECT count(*), min(event.result_status), min(event.returned_snapshot_count),
    bool_and(capability_grant.inactive_from_utc IS NOT NULL)
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events AS event
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.capability_grant_id = event.capability_grant_id
  WHERE event.requested_by_app_user_id =
    'a6f10000-0000-4000-8000-000000000001'::uuid;
" | tr -d '[:space:]')"
if [[ "${directory_first_state}" != '1|completed|0|t' ]]; then
  echo "directory-first did not commit its empty audited read before revocation: ${directory_first_state}" >&2
  exit 1
fi

revocation_first_output="${temporary_directory}/revocation-first.out"
directory_second_output="${temporary_directory}/directory-second.out"
revocation_first_ready='follow-up-consent-directory-ready:revocation-first'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:a6f20000-0000-4000-8000-000000000001:a6f10000-0000-4000-8000-000000000002',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:a6f30000-0000-4000-8000-000000000001:a6f10000-0000-4000-8000-000000000002',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:a6f30000-0000-4000-8000-000000000001:a6f10000-0000-4000-8000-000000000002:view_anonymous_analytics',
    0
  ));
  SELECT pg_advisory_lock(hashtextextended('${revocation_first_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'directory read did not wait for capability revocation';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = 'a6f60000-0000-4000-8000-000000000002'::uuid;
  COMMIT;
" >"${revocation_first_output}" 2>&1 &
revocation_first_pid=$!

wait_for_ready "${revocation_first_ready}" "${revocation_first_pid}" "${revocation_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.list_authorized_management_follow_up_consent_snapshots_v1(
    'a6f10000-0000-4000-8000-000000000002'::uuid,
    'a6f30000-0000-4000-8000-000000000001'::uuid
  );
" >"${directory_second_output}" 2>&1 &
directory_second_pid=$!

revocation_first_status=0
directory_second_status=0
wait "${revocation_first_pid}" || revocation_first_status=$?
wait "${directory_second_pid}" || directory_second_status=$?
if [[ "${revocation_first_status}" -ne 0 || "${directory_second_status}" -eq 0 ]]; then
  echo "revocation-first race failed: revocation=${revocation_first_status}, directory=${directory_second_status}" >&2
  sed -n '1,160p' "${revocation_first_output}" >&2
  sed -n '1,160p' "${directory_second_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' "${directory_second_output}"; then
  echo 'directory read after revocation did not fail closed.' >&2
  sed -n '1,160p' "${directory_second_output}" >&2
  exit 1
fi

directory_second_count="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_follow_up_consent_snapshot_directory_access_events
  WHERE requested_by_app_user_id =
    'a6f10000-0000-4000-8000-000000000002'::uuid;
" | tr -d '[:space:]')"
if [[ "${directory_second_count}" -ne 0 ]]; then
  echo "revocation-first directory read left an audit row: ${directory_second_count}" >&2
  exit 1
fi

echo 'follow-up consent snapshot directory concurrency check passed: read and revocation linearized on shared authorization locks.'
