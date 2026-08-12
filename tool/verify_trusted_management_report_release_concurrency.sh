#!/usr/bin/env bash

set -euo pipefail

# Independent sessions prove that the v2 release rechecks authorization after
# every wait and serializes with project reporting-time-zone configuration.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
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
  local ready=0
  local probe

  for _ in $(seq 1 80); do
    probe="$("${psql_base[@]}" \
      --tuples-only \
      --no-align \
      --command="
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
      ready=1
      break
    fi
    sleep 0.1
  done

  if [[ "${ready}" -ne 1 ]]; then
    kill "${first_pid}" >/dev/null 2>&1 || true
    wait "${first_pid}" >/dev/null 2>&1 || true
    echo '可信报告发布并发会话没有进入持锁状态。' >&2
    sed -n '1,160p' "${first_output}" >&2
    exit 1
  fi
}

"${psql_base[@]}" --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('f1000000-0000-4000-8000-000000000001'::uuid, 'active'),
    ('f1000000-0000-4000-8000-000000000002'::uuid, 'active'),
    ('f1000000-0000-4000-8000-000000000003'::uuid, 'active'),
    ('f1000000-0000-4000-8000-000000000004'::uuid, 'active'),
    ('f1000000-0000-4000-8000-000000000005'::uuid, 'active');

  INSERT INTO app_data.external_identities (
    external_identity_id,
    issuer,
    subject,
    app_user_id
  ) VALUES
    (
      'f0e00000-0000-4000-8000-000000000001'::uuid,
      'https://concurrent-runtime-release.synthetic/auth/v1',
      'member-1',
      'f1000000-0000-4000-8000-000000000001'::uuid
    ),
    (
      'f0e00000-0000-4000-8000-000000000002'::uuid,
      'https://concurrent-runtime-release.synthetic/auth/v1',
      'member-2',
      'f1000000-0000-4000-8000-000000000002'::uuid
    ),
    (
      'f0e00000-0000-4000-8000-000000000003'::uuid,
      'https://concurrent-runtime-release.synthetic/auth/v1',
      'member-3',
      'f1000000-0000-4000-8000-000000000003'::uuid
    ),
    (
      'f0e00000-0000-4000-8000-000000000004'::uuid,
      'https://concurrent-runtime-release.synthetic/auth/v1',
      'member-4',
      'f1000000-0000-4000-8000-000000000004'::uuid
    ),
    (
      'f0e00000-0000-4000-8000-000000000005'::uuid,
      'https://concurrent-runtime-release.synthetic/auth/v1',
      'member-5',
      'f1000000-0000-4000-8000-000000000005'::uuid
    );

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    'f2000000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Concurrent trusted release workspace'
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name
  ) VALUES
    (
      'f3000000-0000-4000-8000-000000000001'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'Release authorization expiry project'
    ),
    (
      'f3000000-0000-4000-8000-000000000002'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'Release-first time-zone project'
    ),
    (
      'f3000000-0000-4000-8000-000000000003'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'Configuration-first time-zone project'
    ),
    (
      'f3000000-0000-4000-8000-000000000004'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'Release-first revocation project'
    ),
    (
      'f3000000-0000-4000-8000-000000000005'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'Revocation-first release project'
    );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES
    (
      'f4000000-0000-4000-8000-000000000001'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'f1000000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f4000000-0000-4000-8000-000000000002'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'f1000000-0000-4000-8000-000000000002'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f4000000-0000-4000-8000-000000000003'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'f1000000-0000-4000-8000-000000000003'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f4000000-0000-4000-8000-000000000004'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'f1000000-0000-4000-8000-000000000004'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f4000000-0000-4000-8000-000000000005'::uuid,
      'f2000000-0000-4000-8000-000000000001'::uuid,
      'f1000000-0000-4000-8000-000000000005'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    );

  INSERT INTO app_data.project_memberships (
    project_membership_id,
    organization_membership_id,
    project_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES
    (
      'f5000000-0000-4000-8000-000000000001'::uuid,
      'f4000000-0000-4000-8000-000000000001'::uuid,
      'f3000000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f5000000-0000-4000-8000-000000000002'::uuid,
      'f4000000-0000-4000-8000-000000000002'::uuid,
      'f3000000-0000-4000-8000-000000000002'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f5000000-0000-4000-8000-000000000003'::uuid,
      'f4000000-0000-4000-8000-000000000003'::uuid,
      'f3000000-0000-4000-8000-000000000003'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f5000000-0000-4000-8000-000000000004'::uuid,
      'f4000000-0000-4000-8000-000000000004'::uuid,
      'f3000000-0000-4000-8000-000000000004'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f5000000-0000-4000-8000-000000000005'::uuid,
      'f4000000-0000-4000-8000-000000000005'::uuid,
      'f3000000-0000-4000-8000-000000000005'::uuid,
      clock_timestamp() - interval '1 day',
      NULL
    );

  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id,
    project_membership_id,
    capability_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES
    (
      'f6000000-0000-4000-8000-000000000001'::uuid,
      'f5000000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports',
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f6000000-0000-4000-8000-000000000002'::uuid,
      'f5000000-0000-4000-8000-000000000002'::uuid,
      'release_management_reports',
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f6000000-0000-4000-8000-000000000003'::uuid,
      'f5000000-0000-4000-8000-000000000003'::uuid,
      'release_management_reports',
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f6000000-0000-4000-8000-000000000004'::uuid,
      'f5000000-0000-4000-8000-000000000004'::uuid,
      'release_management_reports',
      clock_timestamp() - interval '1 day',
      NULL
    ),
    (
      'f6000000-0000-4000-8000-000000000005'::uuid,
      'f5000000-0000-4000-8000-000000000005'::uuid,
      'release_management_reports',
      clock_timestamp() - interval '1 day',
      NULL
    );

  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000001'::uuid,
    'f1000000-0000-4000-8000-000000000001'::uuid,
    'f3000000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    clock_timestamp() - interval '30 days'
  );
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000002'::uuid,
    'f1000000-0000-4000-8000-000000000002'::uuid,
    'f3000000-0000-4000-8000-000000000002'::uuid,
    0,
    'UTC',
    clock_timestamp() - interval '30 days'
  );
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000003'::uuid,
    'f1000000-0000-4000-8000-000000000003'::uuid,
    'f3000000-0000-4000-8000-000000000003'::uuid,
    0,
    'UTC',
    clock_timestamp() - interval '30 days'
  );
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000006'::uuid,
    'f1000000-0000-4000-8000-000000000004'::uuid,
    'f3000000-0000-4000-8000-000000000004'::uuid,
    0,
    'UTC',
    clock_timestamp() - interval '30 days'
  );
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000007'::uuid,
    'f1000000-0000-4000-8000-000000000005'::uuid,
    'f3000000-0000-4000-8000-000000000005'::uuid,
    0,
    'UTC',
    clock_timestamp() - interval '30 days'
  );
" >/dev/null

release_before_revocation_output="${temporary_directory}/release-before-revocation.out"
revocation_after_release_output="${temporary_directory}/revocation-after-release.out"
release_before_revocation_ready='trusted-release-ready:release-before-revocation'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT app_data.release_management_report_snapshot_v1(
    'https://concurrent-runtime-release.synthetic/auth/v1',
    'member-4',
    'f8000000-0000-4000-8000-000000000004'::uuid,
    'f3000000-0000-4000-8000-000000000004'::uuid
  );
  SELECT pg_advisory_lock(
    hashtextextended('${release_before_revocation_ready}', 0)
  );
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
        RAISE EXCEPTION 'revocation did not wait for trusted release';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${release_before_revocation_output}" 2>&1 &
release_before_revocation_pid=$!

wait_for_ready \
  "${release_before_revocation_ready}" \
  "${release_before_revocation_pid}" \
  "${release_before_revocation_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:f2000000-0000-4000-8000-000000000001:f1000000-0000-4000-8000-000000000004',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:f3000000-0000-4000-8000-000000000004:f1000000-0000-4000-8000-000000000004',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:f3000000-0000-4000-8000-000000000004:f1000000-0000-4000-8000-000000000004:release_management_reports',
    0
  ));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    'f6000000-0000-4000-8000-000000000004'::uuid;
  UPDATE app_data.project_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'f6000000-0000-4000-8000-000000000004'::uuid
  )
  WHERE project_membership_id =
    'f5000000-0000-4000-8000-000000000004'::uuid;
  UPDATE app_data.organization_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.project_memberships
    WHERE project_membership_id =
      'f5000000-0000-4000-8000-000000000004'::uuid
  )
  WHERE organization_membership_id =
    'f4000000-0000-4000-8000-000000000004'::uuid;
  COMMIT;
" >"${revocation_after_release_output}" 2>&1 &
revocation_after_release_pid=$!

release_before_revocation_status=0
revocation_after_release_status=0
wait "${release_before_revocation_pid}" || release_before_revocation_status=$?
wait "${revocation_after_release_pid}" || revocation_after_release_status=$?

if [[ "${release_before_revocation_status}" -ne 0 \
  || "${revocation_after_release_status}" -ne 0 ]]; then
  echo "发布先行撤权并发错误：release=${release_before_revocation_status}, revocation=${revocation_after_release_status}" >&2
  sed -n '1,160p' "${release_before_revocation_output}" >&2
  sed -n '1,160p' "${revocation_after_release_output}" >&2
  exit 1
fi

release_before_revocation_state="$("${psql_base[@]}" \
  --tuples-only --no-align --field-separator='|' --command="
    SELECT
      attempt.result_status,
      capability_grant.inactive_from_utc IS NOT NULL,
      project_membership.inactive_from_utc IS NOT NULL,
      organization_membership.inactive_from_utc IS NOT NULL
    FROM app_private.management_report_release_v2_attempts AS attempt
    JOIN app_data.management_report_capability_grants AS capability_grant
      ON capability_grant.capability_grant_id = attempt.capability_grant_id
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.project_membership_id =
        attempt.project_membership_id
    JOIN app_data.organization_memberships AS organization_membership
      ON organization_membership.organization_membership_id =
        attempt.organization_membership_id
    WHERE attempt.release_request_id =
      'f8000000-0000-4000-8000-000000000004'::uuid;
  " | tr -d '[:space:]')"
if [[ "${release_before_revocation_state}" != 'approved_baseline|t|t|t' ]]; then
  echo "发布先行没有在线性化后完成撤权：${release_before_revocation_state}" >&2
  exit 1
fi

revocation_before_release_output="${temporary_directory}/revocation-before-release.out"
release_after_revocation_output="${temporary_directory}/release-after-revocation.out"
revocation_before_release_ready='trusted-release-ready:revocation-before-release'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:f2000000-0000-4000-8000-000000000001:f1000000-0000-4000-8000-000000000005',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:f3000000-0000-4000-8000-000000000005:f1000000-0000-4000-8000-000000000005',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:f3000000-0000-4000-8000-000000000005:f1000000-0000-4000-8000-000000000005:release_management_reports',
    0
  ));
  SELECT pg_advisory_lock(
    hashtextextended('${revocation_before_release_ready}', 0)
  );
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
        RAISE EXCEPTION 'trusted release did not wait for revocation';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    'f6000000-0000-4000-8000-000000000005'::uuid;
  UPDATE app_data.project_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'f6000000-0000-4000-8000-000000000005'::uuid
  )
  WHERE project_membership_id =
    'f5000000-0000-4000-8000-000000000005'::uuid;
  UPDATE app_data.organization_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.project_memberships
    WHERE project_membership_id =
      'f5000000-0000-4000-8000-000000000005'::uuid
  )
  WHERE organization_membership_id =
    'f4000000-0000-4000-8000-000000000005'::uuid;
  COMMIT;
" >"${revocation_before_release_output}" 2>&1 &
revocation_before_release_pid=$!

wait_for_ready \
  "${revocation_before_release_ready}" \
  "${revocation_before_release_pid}" \
  "${revocation_before_release_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.release_management_report_snapshot_v1(
    'https://concurrent-runtime-release.synthetic/auth/v1',
    'member-5',
    'f8000000-0000-4000-8000-000000000005'::uuid,
    'f3000000-0000-4000-8000-000000000005'::uuid
  );
  RESET ROLE;
" >"${release_after_revocation_output}" 2>&1 &
release_after_revocation_pid=$!

revocation_before_release_status=0
release_after_revocation_status=0
wait "${revocation_before_release_pid}" || revocation_before_release_status=$?
wait "${release_after_revocation_pid}" || release_after_revocation_status=$?

if [[ "${revocation_before_release_status}" -ne 0 \
  || "${release_after_revocation_status}" -eq 0 ]]; then
  echo "撤权先行发布并发错误：revocation=${revocation_before_release_status}, release=${release_after_revocation_status}" >&2
  sed -n '1,160p' "${revocation_before_release_output}" >&2
  sed -n '1,160p' "${release_after_revocation_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${release_after_revocation_output}"; then
  echo '等待撤权的可信发布没有按授权失败关闭。' >&2
  sed -n '1,160p' "${release_after_revocation_output}" >&2
  exit 1
fi

release_after_revocation_count="$("${psql_base[@]}" \
  --tuples-only --no-align --command="
    SELECT
      (SELECT count(*) FROM app_private.management_report_release_v2_attempts
       WHERE project_id = 'f3000000-0000-4000-8000-000000000005'::uuid)
      +
      (SELECT count(*) FROM app_private.management_report_release_attempts
       WHERE project_id = 'f3000000-0000-4000-8000-000000000005'::uuid)
      +
      (SELECT count(*) FROM app_private.management_report_snapshots
       WHERE project_id = 'f3000000-0000-4000-8000-000000000005'::uuid);
  " | tr -d '[:space:]')"
if [[ "${release_after_revocation_count}" -ne 0 ]]; then
  echo "撤权先行的发布留下了发布数据：${release_after_revocation_count}" >&2
  exit 1
fi

expiry_holder_output="${temporary_directory}/expiry-holder.out"
expiry_release_output="${temporary_directory}/expiry-release.out"
expiry_ready='trusted-release-ready:authorization-expiry'
expiry_lineage='management-report-release-lineage:f3000000-0000-4000-8000-000000000001:management-report:contact_sessions_by_channel_two_periods'

"${psql_base[@]}" --command="
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp() + interval '8 seconds'
  WHERE capability_grant_id =
    'f6000000-0000-4000-8000-000000000001'::uuid;
" >/dev/null

"${psql_base[@]}" --command="
  SET statement_timeout = '30s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${expiry_lineage}', 0));
  SELECT pg_advisory_lock(hashtextextended('${expiry_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
    expires_at timestamptz;
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'release did not wait on lineage';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
    SELECT inactive_from_utc INTO STRICT expires_at
    FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'f6000000-0000-4000-8000-000000000001'::uuid;
    PERFORM pg_sleep(
      GREATEST(
        0,
        EXTRACT(EPOCH FROM (expires_at - clock_timestamp()))
      ) + 0.2
    );
  END
  \$wait\$;
  COMMIT;
" >"${expiry_holder_output}" 2>&1 &
expiry_holder_pid=$!

wait_for_ready "${expiry_ready}" "${expiry_holder_pid}" "${expiry_holder_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.release_management_report_snapshot_v1(
    'https://concurrent-runtime-release.synthetic/auth/v1',
    'member-1',
    'f8000000-0000-4000-8000-000000000001'::uuid,
    'f3000000-0000-4000-8000-000000000001'::uuid
  );
  RESET ROLE;
" >"${expiry_release_output}" 2>&1 &
expiry_release_pid=$!

expiry_holder_status=0
expiry_release_status=0
wait "${expiry_holder_pid}" || expiry_holder_status=$?
wait "${expiry_release_pid}" || expiry_release_status=$?

if [[ "${expiry_holder_status}" -ne 0 || "${expiry_release_status}" -eq 0 ]]; then
  echo "等待期间授权到期测试错误：holder=${expiry_holder_status}, release=${expiry_release_status}" >&2
  sed -n '1,160p' "${expiry_holder_output}" >&2
  sed -n '1,160p' "${expiry_release_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${expiry_release_output}"; then
  echo '等待期间到期的发布没有按授权失败关闭。' >&2
  sed -n '1,160p' "${expiry_release_output}" >&2
  exit 1
fi

expiry_count="$("${psql_base[@]}" \
  --tuples-only --no-align --command="
    SELECT
      (SELECT count(*) FROM app_private.management_report_release_v2_attempts
       WHERE project_id = 'f3000000-0000-4000-8000-000000000001'::uuid)
      +
      (SELECT count(*) FROM app_private.management_report_release_attempts
       WHERE project_id = 'f3000000-0000-4000-8000-000000000001'::uuid)
      +
      (SELECT count(*) FROM app_private.management_report_snapshots
       WHERE project_id = 'f3000000-0000-4000-8000-000000000001'::uuid);
  " | tr -d '[:space:]')"
if [[ "${expiry_count}" -ne 0 ]]; then
  echo "到期授权留下了发布数据：${expiry_count}" >&2
  exit 1
fi

release_first_output="${temporary_directory}/release-first.out"
configuration_second_output="${temporary_directory}/configuration-second.out"
release_first_ready='trusted-release-ready:release-first'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT app_data.release_management_report_snapshot_v1(
    'https://concurrent-runtime-release.synthetic/auth/v1',
    'member-2',
    'f8000000-0000-4000-8000-000000000002'::uuid,
    'f3000000-0000-4000-8000-000000000002'::uuid
  );
  SELECT pg_advisory_lock(hashtextextended('${release_first_ready}', 0));
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
        RAISE EXCEPTION 'time-zone configuration did not wait for release';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${release_first_output}" 2>&1 &
release_first_pid=$!

wait_for_ready \
  "${release_first_ready}" \
  "${release_first_pid}" \
  "${release_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000004'::uuid,
    'f1000000-0000-4000-8000-000000000002'::uuid,
    'f3000000-0000-4000-8000-000000000002'::uuid,
    1,
    'America/Chicago',
    clock_timestamp() - interval '20 days'
  );
" >"${configuration_second_output}" 2>&1 &
configuration_second_pid=$!

release_first_status=0
configuration_second_status=0
wait "${release_first_pid}" || release_first_status=$?
wait "${configuration_second_pid}" || configuration_second_status=$?

if [[ "${release_first_status}" -ne 0 \
  || "${configuration_second_status}" -ne 0 ]]; then
  echo "发布先行时区并发错误：release=${release_first_status}, configuration=${configuration_second_status}" >&2
  sed -n '1,160p' "${release_first_output}" >&2
  sed -n '1,160p' "${configuration_second_output}" >&2
  exit 1
fi

release_first_state="$("${psql_base[@]}" \
  --tuples-only --no-align --field-separator='|' --command="
    SELECT
      attempt.reporting_time_zone_version_number,
      attempt.reporting_time_zone,
      attempt.result_status,
      (SELECT max(version_number)
       FROM app_private.project_reporting_time_zone_versions AS version_row
       WHERE version_row.project_id = attempt.project_id)
    FROM app_private.management_report_release_v2_attempts AS attempt
    WHERE attempt.release_request_id =
      'f8000000-0000-4000-8000-000000000002'::uuid;
  " | tr -d '[:space:]')"
if [[ "${release_first_state}" != '1|UTC|approved_baseline|2' ]]; then
  echo "发布先行没有固定旧 revision：${release_first_state}" >&2
  exit 1
fi

replay_holder_output="${temporary_directory}/replay-holder.out"
replay_release_output="${temporary_directory}/replay-release.out"
replay_ready='trusted-release-ready:replay-authorization-expiry'
replay_request_lock='management-report-release-request:f8000000-0000-4000-8000-000000000002'

"${psql_base[@]}" --command="
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp() + interval '8 seconds'
  WHERE capability_grant_id =
    'f6000000-0000-4000-8000-000000000002'::uuid;
" >/dev/null

"${psql_base[@]}" --command="
  SET statement_timeout = '30s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${replay_request_lock}', 0));
  SELECT pg_advisory_lock(hashtextextended('${replay_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
    expires_at timestamptz;
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'release replay did not wait on request';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
    SELECT inactive_from_utc INTO STRICT expires_at
    FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'f6000000-0000-4000-8000-000000000002'::uuid;
    PERFORM pg_sleep(
      GREATEST(
        0,
        EXTRACT(EPOCH FROM (expires_at - clock_timestamp()))
      ) + 0.2
    );
  END
  \$wait\$;
  COMMIT;
" >"${replay_holder_output}" 2>&1 &
replay_holder_pid=$!

wait_for_ready "${replay_ready}" "${replay_holder_pid}" "${replay_holder_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.release_management_report_snapshot_v1(
    'https://concurrent-runtime-release.synthetic/auth/v1',
    'member-2',
    'f8000000-0000-4000-8000-000000000002'::uuid,
    'f3000000-0000-4000-8000-000000000002'::uuid
  );
  RESET ROLE;
" >"${replay_release_output}" 2>&1 &
replay_release_pid=$!

replay_holder_status=0
replay_release_status=0
wait "${replay_holder_pid}" || replay_holder_status=$?
wait "${replay_release_pid}" || replay_release_status=$?

if [[ "${replay_holder_status}" -ne 0 || "${replay_release_status}" -eq 0 ]]; then
  echo "重试等待期间授权到期测试错误：holder=${replay_holder_status}, release=${replay_release_status}" >&2
  sed -n '1,160p' "${replay_holder_output}" >&2
  sed -n '1,160p' "${replay_release_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${replay_release_output}"; then
  echo '重试等待期间到期的授权没有失败关闭。' >&2
  sed -n '1,160p' "${replay_release_output}" >&2
  exit 1
fi

replay_count="$("${psql_base[@]}" \
  --tuples-only --no-align --command="
    SELECT count(*)
    FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id =
      'f8000000-0000-4000-8000-000000000002'::uuid;
  " | tr -d '[:space:]')"
if [[ "${replay_count}" -ne 1 ]]; then
  echo "失败关闭的重试改变了既有证据数量：${replay_count}" >&2
  exit 1
fi

configuration_first_output="${temporary_directory}/configuration-first.out"
release_second_output="${temporary_directory}/release-second.out"
configuration_first_ready='trusted-release-ready:configuration-first'
configuration_project_lock='project-reporting-time-zone:f3000000-0000-4000-8000-000000000003'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${configuration_project_lock}', 0)
  );
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'f9000000-0000-4000-8000-000000000005'::uuid,
    'f1000000-0000-4000-8000-000000000003'::uuid,
    'f3000000-0000-4000-8000-000000000003'::uuid,
    1,
    'Asia/Shanghai',
    clock_timestamp() - interval '20 days'
  );
  SELECT pg_advisory_lock(hashtextextended('${configuration_first_ready}', 0));
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
        RAISE EXCEPTION 'release did not wait for time-zone configuration';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${configuration_first_output}" 2>&1 &
configuration_first_pid=$!

wait_for_ready \
  "${configuration_first_ready}" \
  "${configuration_first_pid}" \
  "${configuration_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.release_management_report_snapshot_v1(
    'https://concurrent-runtime-release.synthetic/auth/v1',
    'member-3',
    'f8000000-0000-4000-8000-000000000003'::uuid,
    'f3000000-0000-4000-8000-000000000003'::uuid
  );
  RESET ROLE;
" >"${release_second_output}" 2>&1 &
release_second_pid=$!

configuration_first_status=0
release_second_status=0
wait "${configuration_first_pid}" || configuration_first_status=$?
wait "${release_second_pid}" || release_second_status=$?

if [[ "${configuration_first_status}" -ne 0 \
  || "${release_second_status}" -ne 0 ]]; then
  echo "配置先行时区并发错误：configuration=${configuration_first_status}, release=${release_second_status}" >&2
  sed -n '1,160p' "${configuration_first_output}" >&2
  sed -n '1,160p' "${release_second_output}" >&2
  exit 1
fi

configuration_first_state="$("${psql_base[@]}" \
  --tuples-only --no-align --field-separator='|' --command="
    SELECT
      reporting_time_zone_version_number,
      reporting_time_zone,
      result_status
    FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id =
      'f8000000-0000-4000-8000-000000000003'::uuid;
  " | tr -d '[:space:]')"
if [[ "${configuration_first_state}" != '2|Asia/Shanghai|approved_baseline' ]]; then
  echo "配置先行发布没有读取新 revision：${configuration_first_state}" >&2
  exit 1
fi

echo 'runtime bridge 可信报告发布并发检查通过：发布、重试、撤权和时区配置均按事务顺序完成。'
