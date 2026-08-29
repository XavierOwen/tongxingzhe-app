#!/usr/bin/env bash

set -euo pipefail

# Two independent sessions use the same expected version. The first session
# holds the project lock after it is ready, so the second request must wait for
# the first commit and then fail with a version conflict.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -f \
    "${temporary_directory}/first.out" \
    "${temporary_directory}/second.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

"${psql_base[@]}" --command="
  BEGIN;

  INSERT INTO app_data.app_users (app_user_id)
  VALUES ('a1000000-0000-4000-8000-000000000001'::uuid);

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    'a2000000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Concurrent reporting time zone workspace'
  );

  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('a5000000-0000-4000-8000-000000000001'::uuid, 'active');

  -- Keep the dedicated active owner separate from the time-zone actor.  It
  -- has no project membership or capability grant.
  INSERT INTO app_data.organization_memberships (
    organization_membership_id,
    organization_workspace_id,
    app_user_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    'a6000000-0000-4000-8000-000000000001'::uuid,
    'a2000000-0000-4000-8000-000000000001'::uuid,
    'a5000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  );

  INSERT INTO app_data.organization_owner_assignments (
    organization_owner_assignment_id,
    organization_membership_id,
    active_from_utc,
    inactive_from_utc
  ) VALUES (
    'a7000000-0000-4000-8000-000000000001'::uuid,
    'a6000000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp(),
    NULL
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name
  ) VALUES (
    'a3000000-0000-4000-8000-000000000001'::uuid,
    'a2000000-0000-4000-8000-000000000001'::uuid,
    'Concurrent reporting time zone project'
  );

  SELECT app_private.configure_project_reporting_time_zone_v1(
    'a4000000-0000-4000-8000-000000000001'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'a3000000-0000-4000-8000-000000000001'::uuid,
    0,
    'UTC',
    '2026-04-01 12:00:00+00'::timestamptz
  );

  COMMIT;
" >/dev/null

project_lock='project-reporting-time-zone:a3000000-0000-4000-8000-000000000001'
ready_signal_lock='project-reporting-time-zone-concurrency-ready:a3000000-0000-4000-8000-000000000001'

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${project_lock}', 0));
  SELECT pg_advisory_lock(hashtextextended('${ready_signal_lock}', 0));
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'a4000000-0000-4000-8000-000000000002'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'a3000000-0000-4000-8000-000000000001'::uuid,
    1,
    'America/Chicago',
    '2026-04-02 12:00:00+00'::timestamptz
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_locks AS held_lock
        WHERE held_lock.locktype = 'advisory'
          AND NOT held_lock.granted
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'second reporting time zone request did not wait';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${temporary_directory}/first.out" 2>&1 &
first_pid=$!

first_ready=0
for _ in $(seq 1 50); do
  ready_probe="$("${psql_base[@]}" \
    --tuples-only \
    --no-align \
    --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(hashtextextended('${ready_signal_lock}', 0))
        THEN 'not-ready'
        ELSE 'ready'
      END;
    ")"
  if [[ "${ready_probe}" == 'ready' ]]; then
    first_ready=1
    break
  fi
  sleep 0.1
done

if [[ "${first_ready}" -ne 1 ]]; then
  echo '首个报告时区配置会话没有进入持锁状态。' >&2
  wait "${first_pid}" || true
  sed -n '1,100p' "${temporary_directory}/first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'a4000000-0000-4000-8000-000000000003'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'a3000000-0000-4000-8000-000000000001'::uuid,
    1,
    'Asia/Shanghai',
    '2026-04-02 12:00:00+00'::timestamptz
  );
" >"${temporary_directory}/second.out" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?

if [[ "${first_status}" -ne 0 || "${second_status}" -eq 0 ]]; then
  echo "报告时区并发结果错误：first=${first_status}, second=${second_status}" >&2
  sed -n '1,100p' "${temporary_directory}/first.out" >&2
  sed -n '1,100p' "${temporary_directory}/second.out" >&2
  exit 1
fi

if ! grep -q \
  'project reporting time zone version conflict' \
  "${temporary_directory}/second.out"; then
  echo '并发失败不是期望版本冲突。' >&2
  sed -n '1,100p' "${temporary_directory}/second.out" >&2
  exit 1
fi

result="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      count(*),
      count(*) FILTER (WHERE version_number = 2),
      count(DISTINCT effective_from_utc)
    FROM app_private.project_reporting_time_zone_versions
    WHERE project_id =
      'a3000000-0000-4000-8000-000000000001'::uuid;
  ")"
IFS='|' read -r version_count next_version_count boundary_count <<< "${result}"
if [[ "${version_count}" -ne 2 \
  || "${next_version_count}" -ne 1 \
  || "${boundary_count}" -ne 2 ]]; then
  echo "项目报告时区并发不变量失败：versions=${version_count}, next=${next_version_count}, boundaries=${boundary_count}" >&2
  exit 1
fi

echo '项目报告时区并发检查通过：相同期望版本只有一个请求追加下一版本。'
