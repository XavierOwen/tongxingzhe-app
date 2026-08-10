#!/usr/bin/env bash

set -euo pipefail

# Hold the first release transaction open after it creates the baseline. A
# concurrent rolling release must wait for the lineage lock, then compare with
# that committed baseline instead of creating a second baseline.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -f \
    "${temporary_directory}/baseline.out" \
    "${temporary_directory}/rolling.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

release_lineage_lock='management-report-release-lineage:93000000-0000-4000-8000-000000000001:management-report:contact_sessions_by_channel_two_periods'
ready_signal_lock='management-report-release-concurrency-ready:93000000-0000-4000-8000-000000000001'

"${psql_base[@]}" --command="
  INSERT INTO app_data.app_users (app_user_id)
  VALUES
    ('91000000-0000-4000-8000-000000000001'::uuid),
    ('91000000-0000-4000-8000-000000000002'::uuid),
    ('91000000-0000-4000-8000-000000000003'::uuid);

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    '92000000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Concurrent report release workspace'
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name
  ) VALUES (
    '93000000-0000-4000-8000-000000000001'::uuid,
    '92000000-0000-4000-8000-000000000001'::uuid,
    'Concurrent report release project'
  );

  INSERT INTO app_data.questionnaire_versions (
    questionnaire_version_id,
    project_id,
    version_number,
    status,
    is_current
  ) VALUES (
    '94000000-0000-4000-8000-000000000001'::uuid,
    '93000000-0000-4000-8000-000000000001'::uuid,
    1,
    'published',
    true
  );

  INSERT INTO app_data.contacts (
    contact_id,
    app_user_id,
    workspace_id,
    project_id,
    questionnaire_version_id,
    occurred_at_utc,
    occurred_time_zone,
    first_submitted_at_utc,
    channel,
    location_kind,
    reach_count,
    interest_level
  )
  SELECT
    'concurrent-report-' || period_row.period_key
      || '-' || series_row::text,
    CASE
      WHEN series_row <= 5
        THEN '91000000-0000-4000-8000-000000000001'::uuid
      WHEN series_row <= 8
        THEN '91000000-0000-4000-8000-000000000002'::uuid
      ELSE '91000000-0000-4000-8000-000000000003'::uuid
    END,
    '92000000-0000-4000-8000-000000000001'::uuid,
    '93000000-0000-4000-8000-000000000001'::uuid,
    '94000000-0000-4000-8000-000000000001'::uuid,
    period_row.occurred_at_utc,
    'UTC',
    period_row.occurred_at_utc + interval '1 hour',
    'voice_call',
    'not_applicable',
    1,
    2
  FROM (
    VALUES
      ('week_a'::text, '2026-06-03 12:00:00+00'::timestamptz),
      ('week_b'::text, '2026-06-10 12:00:00+00'::timestamptz),
      ('week_c'::text, '2026-06-17 12:00:00+00'::timestamptz)
  ) AS period_row(period_key, occurred_at_utc)
  CROSS JOIN generate_series(1, 10) AS series_row;
" >/dev/null

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${release_lineage_lock}', 0)
  );
  SELECT pg_advisory_lock(
    hashtextextended('${ready_signal_lock}', 0)
  );
  SELECT app_private.release_management_report_snapshot_v1(
    '95000000-0000-4000-8000-000000000001'::uuid,
    '91000000-0000-4000-8000-000000000001'::uuid,
    '93000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-17 12:34:56+00'::timestamptz,
    '2026-06-17 12:35:00+00'::timestamptz
  );
  SELECT pg_sleep(2);
  COMMIT;
" >"${temporary_directory}/baseline.out" 2>&1 &
baseline_pid=$!

baseline_ready=0
for _ in $(seq 1 50); do
  lock_is_held="$("${psql_base[@]}" \
    --tuples-only \
    --no-align \
    --command="
      WITH probe AS (
        SELECT pg_try_advisory_lock(
          hashtextextended('${ready_signal_lock}', 0)
        ) AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${ready_signal_lock}', 0)
        )
        ELSE true
      END
      FROM probe;
    " | tr -d '[:space:]')"
  if [[ "${lock_is_held}" == 't' ]]; then
    baseline_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${baseline_ready}" -ne 1 ]]; then
  kill "${baseline_pid}" >/dev/null 2>&1 || true
  wait "${baseline_pid}" >/dev/null 2>&1 || true
  echo '基线发布未在五秒内取得 lineage 锁。' >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.release_management_report_snapshot_v1(
    '95000000-0000-4000-8000-000000000002'::uuid,
    '91000000-0000-4000-8000-000000000001'::uuid,
    '93000000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_channel_two_periods',
    1,
    'UTC',
    '2026-06-24 12:34:56+00'::timestamptz,
    '2026-06-24 12:35:00+00'::timestamptz
  );
" >"${temporary_directory}/rolling.out" 2>&1 &
rolling_pid=$!

baseline_status=0
rolling_status=0
wait "${baseline_pid}" || baseline_status=$?
wait "${rolling_pid}" || rolling_status=$?
if [[ "${baseline_status}" -ne 0 || "${rolling_status}" -ne 0 ]]; then
  echo "管理报告并发发布失败：baseline=${baseline_status}, rolling=${rolling_status}" >&2
  sed -n '1,120p' "${temporary_directory}/baseline.out" >&2
  sed -n '1,120p' "${temporary_directory}/rolling.out" >&2
  exit 1
fi

result="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      count(*),
      count(*) FILTER (WHERE result_status = 'approved_baseline'),
      count(*) FILTER (WHERE result_status = 'approved'),
      count(*) FILTER (
        WHERE release_request_id =
          '95000000-0000-4000-8000-000000000002'::uuid
          AND compared_snapshot_id = (
            SELECT released_snapshot_id
            FROM app_private.management_report_release_attempts
            WHERE release_request_id =
              '95000000-0000-4000-8000-000000000001'::uuid
          )
      )
    FROM app_private.management_report_release_attempts
    WHERE project_id =
      '93000000-0000-4000-8000-000000000001'::uuid;
  ")"
IFS='|' read -r attempt_count baseline_count approved_count linked_count \
  <<< "${result}"
if [[ "${attempt_count}" -ne 2 \
  || "${baseline_count}" -ne 1 \
  || "${approved_count}" -ne 1 \
  || "${linked_count}" -ne 1 ]]; then
  echo "报告 lineage 锁未串行化发布：attempts=${attempt_count}, baseline=${baseline_count}, approved=${approved_count}, linked=${linked_count}" >&2
  exit 1
fi

echo "管理报告并发发布通过：滚动发布等待基线提交，并链接到唯一既有快照。"
