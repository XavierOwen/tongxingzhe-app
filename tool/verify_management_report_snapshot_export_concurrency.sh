#!/usr/bin/env bash

set -euo pipefail

# Independent sessions prove that a fixed snapshot export and capability
# revocation linearize on the shared Slice 6I authorization locks. The export
# operation must hold both capability locks before its audit event commits.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  local status=$?
  for process_id in "${operation_first_pid:-}" \
    "${revocation_second_pid:-}" "${revocation_first_pid:-}" \
    "${operation_second_pid:-}"; do
    if [[ -n "${process_id}" ]]; then
      kill "${process_id}" >/dev/null 2>&1 || true
      wait "${process_id}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
  exit "${status}"
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
      return 0
    fi
    sleep 0.1
  done

  kill "${first_pid}" >/dev/null 2>&1 || true
  wait "${first_pid}" >/dev/null 2>&1 || true
  echo '管理报告导出并发会话没有进入持锁状态。' >&2
  sed -n '1,160p' "${first_output}" >&2
  exit 1
}

"${psql_base[@]}" --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('8b100000-0000-4000-8000-000000000001'::uuid, 'active'),
    ('8b100000-0000-4000-8000-000000000002'::uuid, 'active'),
    ('8b100000-0000-4000-8000-000000000003'::uuid, 'active');

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    '8b200000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Concurrent report export workspace'
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status, is_personal_default
  ) VALUES (
    '8b300000-0000-4000-8000-000000000001'::uuid,
    '8b200000-0000-4000-8000-000000000001'::uuid,
    'Concurrent report export project',
    'active',
    false
  );

  INSERT INTO app_data.questionnaire_versions (
    questionnaire_version_id,
    project_id,
    version_number,
    status,
    is_current
  ) VALUES (
    '8b700000-0000-4000-8000-000000000001'::uuid,
    '8b300000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  );

  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    first_submitted_at_utc, channel, location_kind, reach_count, interest_level
  )
  SELECT
    'concurrent-report-export-' || period_row.period_key || '-' || series_row::text,
    CASE
      WHEN series_row <= 5
        THEN '8b100000-0000-4000-8000-000000000001'::uuid
      WHEN series_row <= 8
        THEN '8b100000-0000-4000-8000-000000000002'::uuid
      ELSE '8b100000-0000-4000-8000-000000000003'::uuid
    END,
    '8b200000-0000-4000-8000-000000000001'::uuid,
    '8b300000-0000-4000-8000-000000000001'::uuid,
    '8b700000-0000-4000-8000-000000000001'::uuid,
    period_row.occurred_at_utc,
    'UTC',
    period_row.occurred_at_utc + interval '1 hour',
    'voice_call',
    'not_applicable',
    1,
    2
  FROM (
    SELECT
      'previous'::text AS period_key,
      (
        date_trunc('week', clock_timestamp() AT TIME ZONE 'UTC')
          - interval '12 days'
      ) AT TIME ZONE 'UTC' AS occurred_at_utc
    UNION ALL
    SELECT
      'current'::text,
      (
        date_trunc('week', clock_timestamp() AT TIME ZONE 'UTC')
          - interval '5 days'
      ) AT TIME ZONE 'UTC'
  ) AS period_row
  CROSS JOIN generate_series(1, 10) AS series_row;

  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc
  ) VALUES
    (
      '8b400000-0000-4000-8000-000000000001'::uuid,
      '8b200000-0000-4000-8000-000000000001'::uuid,
      '8b100000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b400000-0000-4000-8000-000000000002'::uuid,
      '8b200000-0000-4000-8000-000000000001'::uuid,
      '8b100000-0000-4000-8000-000000000002'::uuid,
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b400000-0000-4000-8000-000000000003'::uuid,
      '8b200000-0000-4000-8000-000000000001'::uuid,
      '8b100000-0000-4000-8000-000000000003'::uuid,
      clock_timestamp() - interval '1 day'
    );

  INSERT INTO app_data.project_memberships (
    project_membership_id,
    organization_membership_id,
    project_id,
    active_from_utc
  ) VALUES
    (
      '8b500000-0000-4000-8000-000000000001'::uuid,
      '8b400000-0000-4000-8000-000000000001'::uuid,
      '8b300000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b500000-0000-4000-8000-000000000002'::uuid,
      '8b400000-0000-4000-8000-000000000002'::uuid,
      '8b300000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b500000-0000-4000-8000-000000000003'::uuid,
      '8b400000-0000-4000-8000-000000000003'::uuid,
      '8b300000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '1 day'
    );

  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id, active_from_utc
  ) VALUES
    (
      '8b600000-0000-4000-8000-000000000001'::uuid,
      '8b500000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics',
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b600000-0000-4000-8000-000000000002'::uuid,
      '8b500000-0000-4000-8000-000000000001'::uuid,
      'export_management_reports',
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b600000-0000-4000-8000-000000000003'::uuid,
      '8b500000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics',
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b600000-0000-4000-8000-000000000004'::uuid,
      '8b500000-0000-4000-8000-000000000002'::uuid,
      'export_management_reports',
      clock_timestamp() - interval '1 day'
    ),
    (
      '8b600000-0000-4000-8000-000000000005'::uuid,
      '8b500000-0000-4000-8000-000000000003'::uuid,
      'release_management_reports',
      clock_timestamp() - interval '1 day'
    );

  SELECT app_private.configure_project_reporting_time_zone_v1(
    '8b900000-0000-4000-8000-000000000001'::uuid,
    '8b100000-0000-4000-8000-000000000003'::uuid,
    '8b300000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    clock_timestamp() - interval '30 days'
  );

  SELECT app_private.release_management_report_snapshot_v2(
    '8b800000-0000-4000-8000-000000000001'::uuid,
    '8b100000-0000-4000-8000-000000000003'::uuid,
    '8b300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1
  );
" >/dev/null

snapshot_id="$("${psql_base[@]}" \
  --tuples-only --no-align --command="
    SELECT released_snapshot_id
    FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id =
      '8b800000-0000-4000-8000-000000000001'::uuid;
  " | tr -d '[:space:]')"
if [[ -z "${snapshot_id}" ]]; then
  echo '并发导出夹具没有建立可信快照。' >&2
  exit 1
fi

operation_first_output="${temporary_directory}/operation-first.out"
revocation_second_output="${temporary_directory}/revocation-second.out"
operation_first_ready='authorized-report-export-ready:operation-first'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.export_authorized_management_report_snapshot_v1(
    '8b100000-0000-4000-8000-000000000001'::uuid,
    '8b300000-0000-4000-8000-000000000001'::uuid,
    '${snapshot_id}'::uuid
  );
  SELECT pg_advisory_lock(hashtextextended('${operation_first_ready}', 0));
  SELECT pg_sleep(1);
  COMMIT;
" >"${operation_first_output}" 2>&1 &
operation_first_pid=$!

wait_for_ready "${operation_first_ready}" "${operation_first_pid}" "${operation_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:8b200000-0000-4000-8000-000000000001:8b100000-0000-4000-8000-000000000001',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:8b300000-0000-4000-8000-000000000001:8b100000-0000-4000-8000-000000000001',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:8b300000-0000-4000-8000-000000000001:8b100000-0000-4000-8000-000000000001:export_management_reports',
    0
  ));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '8b600000-0000-4000-8000-000000000002'::uuid;
  COMMIT;
" >"${revocation_second_output}" 2>&1 &
revocation_second_pid=$!

operation_first_status=0
revocation_second_status=0
wait "${operation_first_pid}" || operation_first_status=$?
wait "${revocation_second_pid}" || revocation_second_status=$?
if [[ "${operation_first_status}" -ne 0 || "${revocation_second_status}" -ne 0 ]]; then
  echo "导出先行撤权并发错误：export=${operation_first_status}, revocation=${revocation_second_status}" >&2
  sed -n '1,160p' "${operation_first_output}" >&2
  sed -n '1,160p' "${revocation_second_output}" >&2
  exit 1
fi

operation_first_state="$("${psql_base[@]}" \
  --tuples-only --no-align --field-separator='|' --command="
    SELECT
      count(*),
      min(result_status),
      bool_and(export_grant.inactive_from_utc IS NOT NULL)
    FROM app_private.management_report_snapshot_export_events AS event
    JOIN app_data.management_report_capability_grants AS export_grant
      ON export_grant.capability_grant_id = event.export_capability_grant_id
    WHERE event.requested_by_app_user_id =
      '8b100000-0000-4000-8000-000000000001'::uuid;
  " | tr -d '[:space:]')"
if [[ "${operation_first_state}" != '1|completed|t' ]]; then
  echo "导出先行没有在撤权前完成：${operation_first_state}" >&2
  exit 1
fi

revocation_first_output="${temporary_directory}/revocation-first.out"
operation_second_output="${temporary_directory}/operation-second.out"
revocation_first_ready='authorized-report-export-ready:revocation-first'

"${psql_base[@]}" --command="
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:8b200000-0000-4000-8000-000000000001:8b100000-0000-4000-8000-000000000002',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:8b300000-0000-4000-8000-000000000001:8b100000-0000-4000-8000-000000000002',
    0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'management-report-capability:8b300000-0000-4000-8000-000000000001:8b100000-0000-4000-8000-000000000002:view_anonymous_analytics',
    0
  ));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '8b600000-0000-4000-8000-000000000003'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revocation_first_ready}', 0));
  SELECT pg_sleep(1);
  COMMIT;
" >"${revocation_first_output}" 2>&1 &
revocation_first_pid=$!

wait_for_ready "${revocation_first_ready}" "${revocation_first_pid}" "${revocation_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.export_authorized_management_report_snapshot_v1(
    '8b100000-0000-4000-8000-000000000002'::uuid,
    '8b300000-0000-4000-8000-000000000001'::uuid,
    '${snapshot_id}'::uuid
  );
" >"${operation_second_output}" 2>&1 &
operation_second_pid=$!

revocation_first_status=0
operation_second_status=0
wait "${revocation_first_pid}" || revocation_first_status=$?
wait "${operation_second_pid}" || operation_second_status=$?
if [[ "${revocation_first_status}" -ne 0 || "${operation_second_status}" -eq 0 ]]; then
  echo "撤权先行导出并发错误：revocation=${revocation_first_status}, export=${operation_second_status}" >&2
  sed -n '1,160p' "${revocation_first_output}" >&2
  sed -n '1,160p' "${operation_second_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${operation_second_output}"; then
  echo '等待撤权的报告导出没有按授权失败关闭。' >&2
  sed -n '1,160p' "${operation_second_output}" >&2
  exit 1
fi

operation_second_count="$("${psql_base[@]}" \
  --tuples-only --no-align --command="
    SELECT count(*)
    FROM app_private.management_report_snapshot_export_events
    WHERE requested_by_app_user_id =
      '8b100000-0000-4000-8000-000000000002'::uuid;
  " | tr -d '[:space:]')"
if [[ "${operation_second_count}" -ne 0 ]]; then
  echo "撤权先行的导出留下了审计：${operation_second_count}" >&2
  exit 1
fi

echo '固定匿名管理报告导出并发检查通过：导出与撤权按双 capability 锁顺序完成。'
