#!/usr/bin/env bash

set -euo pipefail

# Independent sessions prove two properties that a serial fixture cannot:
# overlapping authorization periods have one winner, and a protected operation
# cannot continue after a concurrent hierarchy revocation commits.
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

  for _ in $(seq 1 50); do
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
    echo '首个授权并发会话没有进入持锁状态。' >&2
    sed -n '1,120p' "${first_output}" >&2
    exit 1
  fi
}

run_overlap_case() {
  local case_id="$1"
  local hierarchy_locks_sql="$2"
  local ready_lock="$3"
  local first_insert_sql="$4"
  local second_insert_sql="$5"
  local expected_error="$6"
  local count_sql="$7"
  local first_output="${temporary_directory}/${case_id}-first.out"
  local second_output="${temporary_directory}/${case_id}-second.out"

  "${psql_base[@]}" --command="
    SET lock_timeout = '10s';
    SET statement_timeout = '20s';
    BEGIN;
    ${hierarchy_locks_sql}
    SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
    ${first_insert_sql}
    DO \$wait\$
    DECLARE
      wait_deadline timestamp with time zone :=
        clock_timestamp() + interval '10 seconds';
    BEGIN
      LOOP
        EXIT WHEN EXISTS (
          SELECT 1
          FROM pg_locks AS waiting_lock
          WHERE waiting_lock.locktype = 'advisory'
            AND NOT waiting_lock.granted
        );
        IF clock_timestamp() >= wait_deadline THEN
          RAISE EXCEPTION 'second authorization write did not wait';
        END IF;
        PERFORM pg_sleep(0.05);
      END LOOP;
    END
    \$wait\$;
    COMMIT;
  " >"${first_output}" 2>&1 &
  local first_pid=$!

  wait_for_ready "${ready_lock}" "${first_pid}" "${first_output}"

  "${psql_base[@]}" --command="
    SET lock_timeout = '10s';
    SET statement_timeout = '20s';
    ${second_insert_sql}
  " >"${second_output}" 2>&1 &
  local second_pid=$!

  local first_status=0
  local second_status=0
  wait "${first_pid}" || first_status=$?
  wait "${second_pid}" || second_status=$?

  if [[ "${first_status}" -ne 0 || "${second_status}" -eq 0 ]]; then
    echo "授权重叠并发结果错误：case=${case_id}, first=${first_status}, second=${second_status}" >&2
    sed -n '1,120p' "${first_output}" >&2
    sed -n '1,120p' "${second_output}" >&2
    exit 1
  fi

  if ! grep -q "${expected_error}" "${second_output}"; then
    echo "授权重叠并发没有返回预期错误：case=${case_id}" >&2
    sed -n '1,120p' "${second_output}" >&2
    exit 1
  fi

  local row_count
  row_count="$("${psql_base[@]}" \
    --tuples-only \
    --no-align \
    --command="${count_sql}" | tr -d '[:space:]')"
  if [[ "${row_count}" -ne 1 ]]; then
    echo "授权重叠并发保留了错误行数：case=${case_id}, rows=${row_count}" >&2
    exit 1
  fi
}

"${psql_base[@]}" --command="
  BEGIN;

  INSERT INTO app_data.app_users (app_user_id)
  VALUES
    ('d1000000-0000-4000-8000-000000000001'::uuid),
    ('d1000000-0000-4000-8000-000000000002'::uuid),
    ('d1000000-0000-4000-8000-000000000003'::uuid),
    ('d1000000-0000-4000-8000-000000000004'::uuid),
    ('d1000000-0000-4000-8000-000000000005'::uuid);

  INSERT INTO app_data.workspaces (
    workspace_id,
    workspace_kind,
    display_name
  ) VALUES (
    'd2000000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Concurrent management authorization workspace'
  );

  INSERT INTO app_data.projects (
    project_id,
    workspace_id,
    display_name
  ) VALUES (
    'd3000000-0000-4000-8000-000000000001'::uuid,
    'd2000000-0000-4000-8000-000000000001'::uuid,
    'Concurrent management authorization project'
  );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc
  ) VALUES
    (
      'd4000000-0000-4000-8000-000000000002'::uuid,
      'd2000000-0000-4000-8000-000000000001'::uuid,
      'd1000000-0000-4000-8000-000000000002'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'd4000000-0000-4000-8000-000000000003'::uuid,
      'd2000000-0000-4000-8000-000000000001'::uuid,
      'd1000000-0000-4000-8000-000000000003'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'd4000000-0000-4000-8000-000000000004'::uuid,
      'd2000000-0000-4000-8000-000000000001'::uuid,
      'd1000000-0000-4000-8000-000000000004'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'd4000000-0000-4000-8000-000000000005'::uuid,
      'd2000000-0000-4000-8000-000000000001'::uuid,
      'd1000000-0000-4000-8000-000000000005'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    );

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    'd7000000-0000-4000-8000-000000000001'::uuid,
    'd4000000-0000-4000-8000-000000000002'::uuid,
    transaction_timestamp(),
    NULL
  );

  INSERT INTO app_data.project_memberships (
    project_membership_id,
    organization_membership_id,
    project_id,
    active_from_utc
  ) VALUES
    (
      'd5000000-0000-4000-8000-000000000003'::uuid,
      'd4000000-0000-4000-8000-000000000003'::uuid,
      'd3000000-0000-4000-8000-000000000001'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'd5000000-0000-4000-8000-000000000004'::uuid,
      'd4000000-0000-4000-8000-000000000004'::uuid,
      'd3000000-0000-4000-8000-000000000001'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'd5000000-0000-4000-8000-000000000005'::uuid,
      'd4000000-0000-4000-8000-000000000005'::uuid,
      'd3000000-0000-4000-8000-000000000001'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    );

  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id,
    project_membership_id,
    capability_id,
    active_from_utc
  ) VALUES (
    'd6000000-0000-4000-8000-000000000004'::uuid,
    'd5000000-0000-4000-8000-000000000004'::uuid,
    'view_anonymous_analytics',
    '2026-01-01 00:00:00+00'::timestamptz
  ), (
    'd6000000-0000-4000-8000-000000000005'::uuid,
    'd5000000-0000-4000-8000-000000000005'::uuid,
    'view_anonymous_analytics',
    '2026-01-01 00:00:00+00'::timestamptz
  );
  COMMIT;
" >/dev/null

run_overlap_case \
  'organization' \
  "SELECT pg_advisory_xact_lock(hashtextextended('organization-membership:d2000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000001', 0));" \
  'management-authorization-ready:organization' \
  "INSERT INTO app_data.organization_memberships (
     organization_membership_id, organization_workspace_id,
     app_user_id, active_from_utc
   ) VALUES (
     'd4000000-0000-4000-8000-000000000011'::uuid,
     'd2000000-0000-4000-8000-000000000001'::uuid,
     'd1000000-0000-4000-8000-000000000001'::uuid,
     '2026-01-01 00:00:00+00'::timestamptz
   );" \
  "INSERT INTO app_data.organization_memberships (
     organization_membership_id, organization_workspace_id,
     app_user_id, active_from_utc
   ) VALUES (
     'd4000000-0000-4000-8000-000000000012'::uuid,
     'd2000000-0000-4000-8000-000000000001'::uuid,
     'd1000000-0000-4000-8000-000000000001'::uuid,
     '2026-02-01 00:00:00+00'::timestamptz
   );" \
  'organization membership periods overlap' \
  "SELECT count(*) FROM app_data.organization_memberships
   WHERE organization_workspace_id =
       'd2000000-0000-4000-8000-000000000001'::uuid
     AND app_user_id =
       'd1000000-0000-4000-8000-000000000001'::uuid;"

run_overlap_case \
  'project' \
  "SELECT pg_advisory_xact_lock(hashtextextended('organization-membership:d2000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000002', 0));
   SELECT pg_advisory_xact_lock(hashtextextended('project-membership:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000002', 0));" \
  'management-authorization-ready:project' \
  "INSERT INTO app_data.project_memberships (
     project_membership_id, organization_membership_id,
     project_id, active_from_utc
   ) VALUES (
     'd5000000-0000-4000-8000-000000000021'::uuid,
     'd4000000-0000-4000-8000-000000000002'::uuid,
     'd3000000-0000-4000-8000-000000000001'::uuid,
     '2026-01-01 00:00:00+00'::timestamptz
   );" \
  "INSERT INTO app_data.project_memberships (
     project_membership_id, organization_membership_id,
     project_id, active_from_utc
   ) VALUES (
     'd5000000-0000-4000-8000-000000000022'::uuid,
     'd4000000-0000-4000-8000-000000000002'::uuid,
     'd3000000-0000-4000-8000-000000000001'::uuid,
     '2026-02-01 00:00:00+00'::timestamptz
   );" \
  'project membership periods overlap' \
  "SELECT count(*)
   FROM app_data.project_memberships AS project_membership
   JOIN app_data.organization_memberships AS organization_membership
     ON organization_membership.organization_membership_id =
       project_membership.organization_membership_id
   WHERE project_membership.project_id =
       'd3000000-0000-4000-8000-000000000001'::uuid
     AND organization_membership.app_user_id =
       'd1000000-0000-4000-8000-000000000002'::uuid;"

run_overlap_case \
  'capability' \
  "SELECT pg_advisory_xact_lock(hashtextextended('organization-membership:d2000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000003', 0));
   SELECT pg_advisory_xact_lock(hashtextextended('project-membership:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000003', 0));
   SELECT pg_advisory_xact_lock(hashtextextended('management-report-capability:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000003:view_anonymous_analytics', 0));" \
  'management-authorization-ready:capability' \
  "INSERT INTO app_data.management_report_capability_grants (
     capability_grant_id, project_membership_id,
     capability_id, active_from_utc
   ) VALUES (
     'd6000000-0000-4000-8000-000000000031'::uuid,
     'd5000000-0000-4000-8000-000000000003'::uuid,
     'view_anonymous_analytics',
     '2026-01-01 00:00:00+00'::timestamptz
   );" \
  "INSERT INTO app_data.management_report_capability_grants (
     capability_grant_id, project_membership_id,
     capability_id, active_from_utc
   ) VALUES (
     'd6000000-0000-4000-8000-000000000032'::uuid,
     'd5000000-0000-4000-8000-000000000003'::uuid,
     'view_anonymous_analytics',
     '2026-02-01 00:00:00+00'::timestamptz
   );" \
  'management report capability periods overlap' \
  "SELECT count(*)
   FROM app_data.management_report_capability_grants
   WHERE project_membership_id =
       'd5000000-0000-4000-8000-000000000003'::uuid
     AND capability_id = 'view_anonymous_analytics';"

authorization_output="${temporary_directory}/authorization.out"
revocation_output="${temporary_directory}/revocation.out"
forbidden_output="${temporary_directory}/forbidden.out"
authorization_ready_lock='management-authorization-ready:revocation'

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.resolve_management_report_authorization_v1(
    'd1000000-0000-4000-8000-000000000004'::uuid,
    'd3000000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics'
  );
  SELECT pg_advisory_lock(
    hashtextextended('${authorization_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_locks AS waiting_lock
        WHERE waiting_lock.locktype = 'advisory'
          AND NOT waiting_lock.granted
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'authorization revocation did not wait';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  SELECT app_private.resolve_management_report_authorization_v1(
    'd1000000-0000-4000-8000-000000000004'::uuid,
    'd3000000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics'
  );
  COMMIT;
" >"${authorization_output}" 2>&1 &
authorization_pid=$!

wait_for_ready \
  "${authorization_ready_lock}" \
  "${authorization_pid}" \
  "${authorization_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:d2000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000004',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000004',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000004:view_anonymous_analytics',
    0
  ));

  -- A future private revocation command must lock before it chooses the
  -- service time. Direct table updates remain unavailable to runtime.
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = statement_timestamp()
  WHERE capability_grant_id =
    'd6000000-0000-4000-8000-000000000004'::uuid;

  UPDATE app_data.project_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'd6000000-0000-4000-8000-000000000004'::uuid
  )
  WHERE project_membership_id =
    'd5000000-0000-4000-8000-000000000004'::uuid;

  UPDATE app_data.organization_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.project_memberships
    WHERE project_membership_id =
      'd5000000-0000-4000-8000-000000000004'::uuid
  )
  WHERE organization_membership_id =
    'd4000000-0000-4000-8000-000000000004'::uuid;
  COMMIT;
" >"${revocation_output}" 2>&1 &
revocation_pid=$!

authorization_status=0
revocation_status=0
wait "${authorization_pid}" || authorization_status=$?
wait "${revocation_pid}" || revocation_status=$?

if [[ "${authorization_status}" -ne 0 || "${revocation_status}" -ne 0 ]]; then
  echo "授权与撤权并发失败：authorization=${authorization_status}, revocation=${revocation_status}" >&2
  sed -n '1,160p' "${authorization_output}" >&2
  sed -n '1,160p' "${revocation_output}" >&2
  exit 1
fi

if "${psql_base[@]}" --command="
  SELECT app_private.resolve_management_report_authorization_v1(
    'd1000000-0000-4000-8000-000000000004'::uuid,
    'd3000000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics'
  );
" >"${forbidden_output}" 2>&1; then
  echo '撤权提交后仍然解析出管理报告授权。' >&2
  exit 1
fi

if ! grep -q \
  'management report authorization forbidden' \
  "${forbidden_output}"; then
  echo '撤权后的授权失败不是预期拒绝。' >&2
  sed -n '1,120p' "${forbidden_output}" >&2
  exit 1
fi

revocation_state="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      capability_grant.inactive_from_utc IS NOT NULL,
      project_membership.inactive_from_utc IS NOT NULL,
      organization_membership.inactive_from_utc IS NOT NULL,
      capability_grant.inactive_from_utc =
        project_membership.inactive_from_utc
        AND project_membership.inactive_from_utc =
          organization_membership.inactive_from_utc
    FROM app_data.management_report_capability_grants AS capability_grant
    JOIN app_data.project_memberships AS project_membership
      ON project_membership.project_membership_id =
        capability_grant.project_membership_id
    JOIN app_data.organization_memberships AS organization_membership
      ON organization_membership.organization_membership_id =
        project_membership.organization_membership_id
    WHERE capability_grant.capability_grant_id =
      'd6000000-0000-4000-8000-000000000004'::uuid;
  " | tr -d '[:space:]')"

if [[ "${revocation_state}" != 't|t|t|t' ]]; then
  echo "授权层级没有在同一边界关闭：${revocation_state}" >&2
  exit 1
fi

revocation_first_output="${temporary_directory}/revocation-first.out"
authorization_second_output="${temporary_directory}/authorization-second.out"
revocation_first_ready_lock='management-authorization-ready:revocation-first'

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:d2000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000005',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000005',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:d3000000-0000-4000-8000-000000000001:d1000000-0000-4000-8000-000000000005:view_anonymous_analytics',
    0
  ));

  SELECT pg_advisory_lock(
    hashtextextended('${revocation_first_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_locks AS waiting_lock
        WHERE waiting_lock.locktype = 'advisory'
          AND NOT waiting_lock.granted
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'authorization request did not wait for revocation';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;

  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    'd6000000-0000-4000-8000-000000000005'::uuid;

  UPDATE app_data.project_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.management_report_capability_grants
    WHERE capability_grant_id =
      'd6000000-0000-4000-8000-000000000005'::uuid
  )
  WHERE project_membership_id =
    'd5000000-0000-4000-8000-000000000005'::uuid;

  UPDATE app_data.organization_memberships
  SET inactive_from_utc = (
    SELECT inactive_from_utc
    FROM app_data.project_memberships
    WHERE project_membership_id =
      'd5000000-0000-4000-8000-000000000005'::uuid
  )
  WHERE organization_membership_id =
    'd4000000-0000-4000-8000-000000000005'::uuid;
  COMMIT;
" >"${revocation_first_output}" 2>&1 &
revocation_first_pid=$!

wait_for_ready \
  "${revocation_first_ready_lock}" \
  "${revocation_first_pid}" \
  "${revocation_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.resolve_management_report_authorization_v1(
    'd1000000-0000-4000-8000-000000000005'::uuid,
    'd3000000-0000-4000-8000-000000000001'::uuid,
    'view_anonymous_analytics'
  );
" >"${authorization_second_output}" 2>&1 &
authorization_second_pid=$!

revocation_first_status=0
authorization_second_status=0
wait "${revocation_first_pid}" || revocation_first_status=$?
wait "${authorization_second_pid}" || authorization_second_status=$?

if [[ "${revocation_first_status}" -ne 0 \
  || "${authorization_second_status}" -eq 0 ]]; then
  echo "撤权先行并发结果错误：revocation=${revocation_first_status}, authorization=${authorization_second_status}" >&2
  sed -n '1,160p' "${revocation_first_output}" >&2
  sed -n '1,160p' "${authorization_second_output}" >&2
  exit 1
fi

if ! grep -q \
  'management report authorization forbidden' \
  "${authorization_second_output}"; then
  echo '等待撤权的授权请求没有按预期失败。' >&2
  sed -n '1,120p' "${authorization_second_output}" >&2
  exit 1
fi

echo '管理报告授权并发检查通过：重叠写入各有一个胜者，撤权与授权消费按事务顺序完成。'
