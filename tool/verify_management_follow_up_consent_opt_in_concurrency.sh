#!/usr/bin/env bash

set -euo pipefail

# 6BO is DB-only.  The rollback fixture uses 6b0f identifiers; this script
# uses 6b0c identifiers because its setup is intentionally committed and must
# survive pg_dump/restore.  Both archive orders use the same project lock as
# the migration's status trigger and configure function.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -f \
    "${temporary_directory}/archive-first.out" \
    "${temporary_directory}/configure-after-archive.out" \
    "${temporary_directory}/configure-first.out" \
    "${temporary_directory}/archive-after-configure.out" \
    "${temporary_directory}/version-first.out" \
    "${temporary_directory}/version-second.out" \
    "${temporary_directory}/idempotent-first.out" \
    "${temporary_directory}/idempotent-second.out" \
    "${temporary_directory}/revoke-first.out" \
    "${temporary_directory}/configure-after-revoke.out" \
    "${temporary_directory}/read-first.out" \
    "${temporary_directory}/revoke-after-read.out" \
    "${temporary_directory}/read-after-revoke.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

config_role='tongxingzhe_management_follow_up_consent_config_writer'
actor_id='6b0c1000-0000-4000-8000-000000000001'
workspace_id='6b0c2000-0000-4000-8000-000000000001'
archive_project_id='6b0c3000-0000-4000-8000-000000000001'
configure_first_project_id='6b0c3000-0000-4000-8000-000000000002'
version_race_project_id='6b0c3000-0000-4000-8000-000000000003'
idempotent_project_id='6b0c3000-0000-4000-8000-000000000004'
revoke_first_project_id='6b0c3000-0000-4000-8000-000000000005'
read_first_project_id='6b0c3000-0000-4000-8000-000000000006'
organization_membership_id='6b0c4000-0000-4000-8000-000000000001'
archive_project_membership_id='6b0c5000-0000-4000-8000-000000000001'
configure_first_project_membership_id='6b0c5000-0000-4000-8000-000000000002'
version_race_project_membership_id='6b0c5000-0000-4000-8000-000000000003'
idempotent_project_membership_id='6b0c5000-0000-4000-8000-000000000004'
revoke_first_project_membership_id='6b0c5000-0000-4000-8000-000000000005'
read_first_project_membership_id='6b0c5000-0000-4000-8000-000000000006'
archive_capability_grant_id='6b0c6000-0000-4000-8000-000000000001'
configure_first_capability_grant_id='6b0c6000-0000-4000-8000-000000000002'
version_race_capability_grant_id='6b0c6000-0000-4000-8000-000000000003'
idempotent_capability_grant_id='6b0c6000-0000-4000-8000-000000000004'
revoke_first_capability_grant_id='6b0c6000-0000-4000-8000-000000000005'
read_first_capability_grant_id='6b0c6000-0000-4000-8000-000000000006'
archive_request_id='6b0c7000-0000-4000-8000-000000000001'
configure_first_request_id='6b0c7000-0000-4000-8000-000000000002'
version_race_request_a='6b0c7000-0000-4000-8000-000000000003'
version_race_request_b='6b0c7000-0000-4000-8000-000000000004'
idempotent_request_id='6b0c7000-0000-4000-8000-000000000005'
revoke_first_request_id='6b0c7000-0000-4000-8000-000000000006'
read_first_request_id='6b0c7000-0000-4000-8000-000000000007'

version_race_project_lock="management-follow-up-consent-opt-in:${version_race_project_id}"
archive_ready_lock="6bo-archive-first-ready:${archive_project_id}"
configure_first_ready_lock="6bo-configure-first-ready:${configure_first_project_id}"
version_race_ready_lock="6bo-version-race-ready:${version_race_project_id}"
idempotent_project_lock="management-follow-up-consent-opt-in:${idempotent_project_id}"
idempotent_ready_lock="6bo-idempotent-ready:${idempotent_project_id}"
revoke_first_ready_lock="6bo-revoke-first-ready:${revoke_first_project_id}"
read_first_ready_lock="6bo-read-first-ready:${read_first_project_id}"

"${psql_base[@]}" --command="
  BEGIN;
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('${actor_id}'::uuid, 'active');
  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name, personal_owner_app_user_id
  ) VALUES (
    '${workspace_id}'::uuid, 'organization',
    '6BO committed concurrency organization', NULL
  );
  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status, is_personal_default
  ) VALUES
    (
      '${archive_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BO archive-first project', 'active', false
    ),
    (
      '${configure_first_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BO configure-first project', 'active', false
    ),
    (
      '${version_race_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BO version-race project', 'active', false
    ),
    (
      '${idempotent_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BO idempotent-replay project', 'active', false
    ),
    (
      '${revoke_first_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BO revoke-first project', 'active', false
    ),
    (
      '${read_first_project_id}'::uuid, '${workspace_id}'::uuid,
      '6BO read-first project', 'active', false
    );
  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    '${organization_membership_id}'::uuid, '${workspace_id}'::uuid,
    '${actor_id}'::uuid, clock_timestamp() - interval '1 day', NULL
  );
  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    '6b0c8000-0000-4000-8000-000000000001'::uuid,
    '${organization_membership_id}'::uuid,
    transaction_timestamp(),
    NULL
  );
  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id, project_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    (
      '${archive_project_membership_id}'::uuid,
      '${organization_membership_id}'::uuid, '${archive_project_id}'::uuid,
      clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${configure_first_project_membership_id}'::uuid,
      '${organization_membership_id}'::uuid,
      '${configure_first_project_id}'::uuid,
      clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${version_race_project_membership_id}'::uuid,
      '${organization_membership_id}'::uuid,
      '${version_race_project_id}'::uuid,
      clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${idempotent_project_membership_id}'::uuid,
      '${organization_membership_id}'::uuid,
      '${idempotent_project_id}'::uuid,
      clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${revoke_first_project_membership_id}'::uuid,
      '${organization_membership_id}'::uuid,
      '${revoke_first_project_id}'::uuid,
      clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${read_first_project_membership_id}'::uuid,
      '${organization_membership_id}'::uuid,
      '${read_first_project_id}'::uuid,
      clock_timestamp() - interval '1 day', NULL
    );
  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    (
      '${archive_capability_grant_id}'::uuid,
      '${archive_project_membership_id}'::uuid,
      'release_management_reports', clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${configure_first_capability_grant_id}'::uuid,
      '${configure_first_project_membership_id}'::uuid,
      'release_management_reports', clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${version_race_capability_grant_id}'::uuid,
      '${version_race_project_membership_id}'::uuid,
      'release_management_reports', clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${idempotent_capability_grant_id}'::uuid,
      '${idempotent_project_membership_id}'::uuid,
      'release_management_reports', clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${revoke_first_capability_grant_id}'::uuid,
      '${revoke_first_project_membership_id}'::uuid,
      'release_management_reports', clock_timestamp() - interval '1 day', NULL
    ),
    (
      '${read_first_capability_grant_id}'::uuid,
      '${read_first_project_membership_id}'::uuid,
      'release_management_reports', clock_timestamp() - interval '1 day', NULL
    );
  COMMIT;
"

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${read_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${read_first_request_id}'::uuid, 0, true
  );
" >/dev/null

probe_session_lock() {
  local lock_name="$1"
  local result
  result="$(${psql_base[@]} --tuples-only --no-align --command="
    SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('${lock_name}', 0))
        THEN 'not-ready'
      ELSE 'ready'
    END;
  ")"
  [[ "${result}" == *ready* && "${result}" != *not-ready* ]]
}

# Archive-and-revoke first. The status trigger must acquire the authorization
# hierarchy before the project lock. A later capability revocation in the same
# transaction must not reverse that order or deadlock with configure.
"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = '${archive_project_id}'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${archive_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'archive-first configure did not wait';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${archive_capability_grant_id}'::uuid;
  SELECT pg_advisory_unlock(hashtextextended('${archive_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/archive-first.out" 2>&1 &
archive_first_pid=$!

archive_first_ready=0
for _ in $(seq 1 100); do
  if probe_session_lock "${archive_ready_lock}"; then
    archive_first_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${archive_first_ready}" -ne 1 ]]; then
  echo '6BO archive-first session did not reach its barrier.' >&2
  wait "${archive_first_pid}" || true
  sed -n '1,160p' "${temporary_directory}/archive-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${archive_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${archive_request_id}'::uuid, 0, true
  );
" >"${temporary_directory}/configure-after-archive.out" 2>&1 &
archive_first_configure_pid=$!

archive_first_status=0
archive_first_configure_status=0
wait "${archive_first_pid}" || archive_first_status=$?
wait "${archive_first_configure_pid}" || archive_first_configure_status=$?
if [[ "${archive_first_status}" -ne 0 \
  || "${archive_first_configure_status}" -eq 0 ]]; then
  echo "6BO archive-first result unexpected: archive=${archive_first_status}, configure=${archive_first_configure_status}" >&2
  sed -n '1,160p' "${temporary_directory}/archive-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/configure-after-archive.out" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${temporary_directory}/configure-after-archive.out"; then
  echo '6BO archive-first configure did not fail closed after reauthorization.' >&2
  sed -n '1,160p' "${temporary_directory}/configure-after-archive.out" >&2
  exit 1
fi

archive_first_history="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '${archive_project_id}'::uuid;
")"
archive_first_history="$(printf '%s' "${archive_first_history}" | tr -d '[:space:]')"
archive_first_state="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT status FROM app_data.projects
  WHERE project_id = '${archive_project_id}'::uuid;
")"
archive_first_state="$(printf '%s' "${archive_first_state}" | tr -d '[:space:]')"
if [[ "${archive_first_history}" -ne 0 \
  || "${archive_first_state}" != 'archived' ]]; then
  echo "6BO archive-first invariant failed: history=${archive_first_history}, status=${archive_first_state}" >&2
  exit 1
fi
echo '6BO archive-and-revoke first passed without lock-order reversal.'

# Version race: two different requests target one project at expected_version
# zero.  The first transaction holds the project lock while the second waits;
# exactly one append is allowed and the waiter receives a version conflict.
"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${version_race_project_lock}', 0)
  );
  SELECT pg_advisory_lock(hashtextextended('${version_race_ready_lock}', 0));
  SET LOCAL ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${version_race_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${version_race_request_a}'::uuid, 0, true
  );
  RESET ROLE;
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'version-race waiter did not wait';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  SELECT pg_advisory_unlock(hashtextextended('${version_race_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/version-first.out" 2>&1 &
version_first_pid=$!

version_first_ready=0
for _ in $(seq 1 100); do
  if probe_session_lock "${version_race_ready_lock}"; then
    version_first_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${version_first_ready}" -ne 1 ]]; then
  echo '6BO version-race first session did not reach its barrier.' >&2
  wait "${version_first_pid}" || true
  sed -n '1,160p' "${temporary_directory}/version-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${version_race_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${version_race_request_b}'::uuid, 0, false
  );
" >"${temporary_directory}/version-second.out" 2>&1 &
version_second_pid=$!

version_first_status=0
version_second_status=0
wait "${version_first_pid}" || version_first_status=$?
wait "${version_second_pid}" || version_second_status=$?
if [[ "${version_first_status}" -ne 0 \
  || "${version_second_status}" -eq 0 ]]; then
  echo "6BO version-race result unexpected: first=${version_first_status}, second=${version_second_status}" >&2
  sed -n '1,160p' "${temporary_directory}/version-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/version-second.out" >&2
  exit 1
fi
if ! grep -q 'management follow-up consent opt-in version conflict' \
  "${temporary_directory}/version-second.out"; then
  echo '6BO version-race waiter did not fail with a version conflict.' >&2
  sed -n '1,160p' "${temporary_directory}/version-second.out" >&2
  exit 1
fi

version_race_result="$(${psql_base[@]} --tuples-only --no-align --field-separator='|' --command="
  SELECT
    count(*),
    count(*) FILTER (WHERE enabled),
    count(*) FILTER (WHERE NOT enabled)
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '${version_race_project_id}'::uuid;
")"
IFS='|' read -r version_count version_enabled version_disabled <<< "${version_race_result}"
version_count="$(printf '%s' "${version_count}" | tr -d '[:space:]')"
version_enabled="$(printf '%s' "${version_enabled}" | tr -d '[:space:]')"
version_disabled="$(printf '%s' "${version_disabled}" | tr -d '[:space:]')"
if [[ "${version_count}" -ne 1 \
  || "${version_enabled}" -ne 1 \
  || "${version_disabled}" -ne 0 ]]; then
  echo "6BO version-race invariant failed: rows=${version_count}, enabled=${version_enabled}, disabled=${version_disabled}" >&2
  exit 1
fi
echo '6BO version-race passed: different requests produced one version 1.'

# Idempotent race: the same request UUID and canonical payload are submitted
# by two independent config-role sessions.  One waits on the project lock and
# then replays the exact stored document; no duplicate row is possible.
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${idempotent_project_lock}', 0)
  );
  SELECT pg_advisory_lock(hashtextextended('${idempotent_ready_lock}', 0));
  SET LOCAL ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${idempotent_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${idempotent_request_id}'::uuid, 0, true
  );
  RESET ROLE;
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'idempotent waiter did not wait';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  DO \$unlock\$
  BEGIN
    PERFORM pg_advisory_unlock(hashtextextended('${idempotent_ready_lock}', 0));
  END
  \$unlock\$;
  COMMIT;
" >"${temporary_directory}/idempotent-first.out" 2>&1 &
idempotent_first_pid=$!

idempotent_first_ready=0
for _ in $(seq 1 100); do
  if probe_session_lock "${idempotent_ready_lock}"; then
    idempotent_first_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${idempotent_first_ready}" -ne 1 ]]; then
  echo '6BO idempotent first session did not reach its barrier.' >&2
  wait "${idempotent_first_pid}" || true
  sed -n '1,160p' "${temporary_directory}/idempotent-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${idempotent_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${idempotent_request_id}'::uuid, 0, true
  );
" >"${temporary_directory}/idempotent-second.out" 2>&1 &
idempotent_second_pid=$!

idempotent_first_status=0
idempotent_second_status=0
wait "${idempotent_first_pid}" || idempotent_first_status=$?
wait "${idempotent_second_pid}" || idempotent_second_status=$?
if [[ "${idempotent_first_status}" -ne 0 \
  || "${idempotent_second_status}" -ne 0 ]]; then
  echo "6BO idempotent race result unexpected: first=${idempotent_first_status}, second=${idempotent_second_status}" >&2
  sed -n '1,160p' "${temporary_directory}/idempotent-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/idempotent-second.out" >&2
  exit 1
fi

idempotent_first_document="$(tr -d '[:space:]' <"${temporary_directory}/idempotent-first.out")"
idempotent_second_document="$(tr -d '[:space:]' <"${temporary_directory}/idempotent-second.out")"
if [[ -z "${idempotent_first_document}" \
  || "${idempotent_first_document}" != "${idempotent_second_document}" ]]; then
  echo '6BO idempotent race returned different configuration documents.' >&2
  sed -n '1,160p' "${temporary_directory}/idempotent-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/idempotent-second.out" >&2
  exit 1
fi
idempotent_count="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '${idempotent_project_id}'::uuid;
")"
idempotent_count="$(printf '%s' "${idempotent_count}" | tr -d '[:space:]')"
if [[ "${idempotent_count}" -ne 1 ]]; then
  echo "6BO idempotent race appended ${idempotent_count} rows instead of one." >&2
  exit 1
fi
echo '6BO idempotent race passed: same request returned one exact document.'

# Revoke-first configuration.  The capability UPDATE takes the authorization
# hierarchy locks through the 0030 trigger.  Configure waits in the resolver,
# observes the committed revocation, and must not append a version.
"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${revoke_first_capability_grant_id}'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revoke_first_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'revoke-first configure did not wait';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  SELECT pg_advisory_unlock(hashtextextended('${revoke_first_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/revoke-first.out" 2>&1 &
revoke_first_pid=$!

revoke_first_ready=0
for _ in $(seq 1 100); do
  if probe_session_lock "${revoke_first_ready_lock}"; then
    revoke_first_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${revoke_first_ready}" -ne 1 ]]; then
  echo '6BO revoke-first session did not reach its barrier.' >&2
  wait "${revoke_first_pid}" || true
  sed -n '1,160p' "${temporary_directory}/revoke-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  SET ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${revoke_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${revoke_first_request_id}'::uuid, 0, true
  );
" >"${temporary_directory}/configure-after-revoke.out" 2>&1 &
configure_after_revoke_pid=$!

revoke_first_status=0
configure_after_revoke_status=0
wait "${revoke_first_pid}" || revoke_first_status=$?
wait "${configure_after_revoke_pid}" || configure_after_revoke_status=$?
if [[ "${revoke_first_status}" -ne 0 \
  || "${configure_after_revoke_status}" -eq 0 ]]; then
  echo "6BO revoke-first result unexpected: revoke=${revoke_first_status}, configure=${configure_after_revoke_status}" >&2
  sed -n '1,160p' "${temporary_directory}/revoke-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/configure-after-revoke.out" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${temporary_directory}/configure-after-revoke.out"; then
  echo '6BO revoke-first configure did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/configure-after-revoke.out" >&2
  exit 1
fi

revoke_first_history="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '${revoke_first_project_id}'::uuid;
")"
revoke_first_history="$(printf '%s' "${revoke_first_history}" | tr -d '[:space:]')"
if [[ "${revoke_first_history}" -ne 0 ]]; then
  echo "6BO revoke-first appended ${revoke_first_history} rows." >&2
  exit 1
fi
echo '6BO revoke-first passed: configure reauthorized and wrote no row.'

# Read-first revocation.  The authorized read keeps the resolver locks until
# its transaction commits.  Closing the capability and its parent project
# membership must wait; afterward a new read fails closed while history stays
# intact.
"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${config_role};
  SELECT app_private.read_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${read_first_project_id}'::uuid,
    'follow_up_consent_ratio@1'
  );
  RESET ROLE;
  SELECT pg_advisory_lock(hashtextextended('${read_first_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'read-first authorization revoke did not wait';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  SELECT pg_advisory_unlock(hashtextextended('${read_first_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/read-first.out" 2>&1 &
read_first_pid=$!

read_first_ready=0
for _ in $(seq 1 100); do
  if probe_session_lock "${read_first_ready_lock}"; then
    read_first_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${read_first_ready}" -ne 1 ]]; then
  echo '6BO read-first session did not reach its barrier.' >&2
  wait "${read_first_pid}" || true
  sed -n '1,160p' "${temporary_directory}/read-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${read_first_capability_grant_id}'::uuid;
  UPDATE app_data.project_memberships
  SET inactive_from_utc = (
    SELECT capability_grant.inactive_from_utc
    FROM app_data.management_report_capability_grants AS capability_grant
    WHERE capability_grant.capability_grant_id =
      '${read_first_capability_grant_id}'::uuid
  )
  WHERE project_membership_id = '${read_first_project_membership_id}'::uuid;
  COMMIT;
" >"${temporary_directory}/revoke-after-read.out" 2>&1 &
revoke_after_read_pid=$!

read_first_status=0
revoke_after_read_status=0
wait "${read_first_pid}" || read_first_status=$?
wait "${revoke_after_read_pid}" || revoke_after_read_status=$?
if [[ "${read_first_status}" -ne 0 \
  || "${revoke_after_read_status}" -ne 0 ]]; then
  echo "6BO read-first result unexpected: read=${read_first_status}, revoke=${revoke_after_read_status}" >&2
  sed -n '1,160p' "${temporary_directory}/read-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/revoke-after-read.out" >&2
  exit 1
fi
if ! grep -q '"status": "enabled"' \
  "${temporary_directory}/read-first.out"; then
  echo '6BO read-first transaction did not return the enabled state.' >&2
  sed -n '1,160p' "${temporary_directory}/read-first.out" >&2
  exit 1
fi

set +e
"${psql_base[@]}" --command="
  SET ROLE ${config_role};
  SELECT app_private.read_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${read_first_project_id}'::uuid,
    'follow_up_consent_ratio@1'
  );
" >"${temporary_directory}/read-after-revoke.out" 2>&1
read_after_revoke_status=$?
set -e
if [[ "${read_after_revoke_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' \
    "${temporary_directory}/read-after-revoke.out"; then
  echo '6BO read after membership revocation did not fail closed.' >&2
  sed -n '1,160p' "${temporary_directory}/read-after-revoke.out" >&2
  exit 1
fi

read_first_history="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_follow_up_consent_opt_in_versions
  WHERE project_id = '${read_first_project_id}'::uuid;
")"
read_first_history="$(printf '%s' "${read_first_history}" | tr -d '[:space:]')"
if [[ "${read_first_history}" -ne 1 ]]; then
  echo "6BO read-first history drifted to ${read_first_history} rows." >&2
  exit 1
fi
echo '6BO read-first passed: membership revoke waited and later reads failed.'

# Configure-first. A real status UPDATE must wait on the hierarchy or project
# lock held by configure. If the trigger skips either lock family, this bounded
# waiter assertion fails.
"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE ${config_role};
  SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${configure_first_project_id}'::uuid,
    'follow_up_consent_ratio@1', '${configure_first_request_id}'::uuid, 0, true
  );
  RESET ROLE;
  SELECT pg_advisory_lock(hashtextextended('${configure_first_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_catalog.pg_locks
        WHERE locktype = 'advisory'
          AND NOT granted
          AND pid <> pg_backend_pid()
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'configure-first archive UPDATE did not wait';
      END IF;
      PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  SELECT pg_advisory_unlock(hashtextextended('${configure_first_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/configure-first.out" 2>&1 &
configure_first_pid=$!

configure_first_ready=0
for _ in $(seq 1 100); do
  if probe_session_lock "${configure_first_ready_lock}"; then
    configure_first_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${configure_first_ready}" -ne 1 ]]; then
  echo '6BO configure-first session did not reach its barrier.' >&2
  wait "${configure_first_pid}" || true
  sed -n '1,160p' "${temporary_directory}/configure-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = '${configure_first_project_id}'::uuid;
" >"${temporary_directory}/archive-after-configure.out" 2>&1 &
configure_first_archive_pid=$!

configure_first_status=0
configure_first_archive_status=0
wait "${configure_first_pid}" || configure_first_status=$?
wait "${configure_first_archive_pid}" || configure_first_archive_status=$?
if [[ "${configure_first_status}" -ne 0 \
  || "${configure_first_archive_status}" -ne 0 ]]; then
  echo "6BO configure-first result unexpected: configure=${configure_first_status}, archive=${configure_first_archive_status}" >&2
  sed -n '1,160p' "${temporary_directory}/configure-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/archive-after-configure.out" >&2
  exit 1
fi

configure_first_result="$(${psql_base[@]} --tuples-only --no-align --field-separator='|' --command="
  SELECT project_row.status, count(version_row.*)
  FROM app_data.projects AS project_row
  LEFT JOIN app_private.management_follow_up_consent_opt_in_versions AS version_row
    ON version_row.project_id = project_row.project_id
  WHERE project_row.project_id = '${configure_first_project_id}'::uuid
  GROUP BY project_row.status;
")"
IFS='|' read -r configure_first_state configure_first_history <<< "${configure_first_result}"
configure_first_state="$(printf '%s' "${configure_first_state}" | tr -d '[:space:]')"
configure_first_history="$(printf '%s' "${configure_first_history}" | tr -d '[:space:]')"
if [[ "${configure_first_state}" != 'archived' \
  || "${configure_first_history}" -ne 1 ]]; then
  echo "6BO configure-first invariant failed: status=${configure_first_state}, history=${configure_first_history}" >&2
  exit 1
fi

set +e
"${psql_base[@]}" --command="
  SET ROLE ${config_role};
  SELECT app_private.read_management_follow_up_consent_opt_in_v1(
    '${actor_id}'::uuid, '${configure_first_project_id}'::uuid,
    'follow_up_consent_ratio@1'
  );
" >"${temporary_directory}/archive-after-configure.out" 2>&1
read_after_archive_status=$?
set -e
if [[ "${read_after_archive_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' \
    "${temporary_directory}/archive-after-configure.out"; then
  echo '6BO configure-first read did not fail closed after archive.' >&2
  sed -n '1,160p' "${temporary_directory}/archive-after-configure.out" >&2
  exit 1
fi

echo '6BO configure-first passed: archive UPDATE waited on the shared project lock.'
echo 'management follow-up consent opt-in concurrency check passed.'
