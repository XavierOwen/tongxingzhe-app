#!/usr/bin/env bash

set -euo pipefail

# Verify that the stage-change summary bridge serializes with the same
# user_current_projects row that select_personal_project_context updates.  A
# reader that acquires the row first must return the old project while the
# switch waits; a switch that acquires it first must make a waiting reader see
# the new project.  Both cases use independent psql sessions.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -f \
    "${temporary_directory}/reader-first.out" \
    "${temporary_directory}/switch-first.out" \
    "${temporary_directory}/switch-writer.out" \
    "${temporary_directory}/waiting-reader.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

issuer='https://synthetic-stage-change-summary-concurrency.example.test/auth/v1'
subject='stage-change-summary-concurrency-owner'
primary_project_id=''
secondary_project_id=''
app_user_id=''
workspace_id=''

context_line="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT app_user_id::text || '|' || workspace_id::text || '|' || project_id::text
  FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');
")"
context_line="$(printf '%s' "${context_line}" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id primary_project_id <<< "${context_line}"

if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${primary_project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "阶段变更并发 fixture 没有得到合法个人上下文：${context_line}" >&2
  exit 1
fi

secondary_project_id="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT project_id
  FROM app_data.create_personal_project_context(
    '${issuer}',
    '${subject}',
    '阶段变更并发其他项目'
  );
")"
secondary_project_id="$(printf '%s' "${secondary_project_id}" | tr -d '[:space:]')"
if [[ ! "${secondary_project_id}" =~ ^[0-9a-f-]{36}$ \
  || "${secondary_project_id}" == "${primary_project_id}" ]]; then
  echo "阶段变更并发 fixture 没有得到独立项目：${secondary_project_id}" >&2
  exit 1
fi

# Establish the primary pointer after create_personal_project_context moved it
# to the secondary project.  The writes below run as deployment owner; runtime
# only reaches the data through the summary and project-selection bridges.
"${psql_base[@]}" --command="
  SET ROLE tongxingzhe_runtime;
  SELECT count(*)
  FROM app_data.select_personal_project_context(
    '${issuer}', '${subject}', '${primary_project_id}'::uuid
  );
  RESET ROLE;

  INSERT INTO app_data.promotion_targets (
    promotion_target_id, workspace_id, target_type, display_name,
    created_by_app_user_id
  ) VALUES
    ('b5200000-0000-4000-8000-000000000001'::uuid,
     '${workspace_id}'::uuid, 'person', '并发阶段变更 primary',
     '${app_user_id}'::uuid),
    ('b5200000-0000-4000-8000-000000000002'::uuid,
     '${workspace_id}'::uuid, 'person', '并发阶段变更 secondary',
     '${app_user_id}'::uuid);

  INSERT INTO app_data.promotion_target_assignments (
    promotion_target_id, app_user_id, assigned_by_app_user_id
  ) VALUES
    ('b5200000-0000-4000-8000-000000000001'::uuid,
     '${app_user_id}'::uuid, '${app_user_id}'::uuid),
    ('b5200000-0000-4000-8000-000000000002'::uuid,
     '${app_user_id}'::uuid, '${app_user_id}'::uuid);

  INSERT INTO app_data.promotion_target_project_relationships (
    promotion_target_id, project_id, current_stage,
    established_by_app_user_id, established_at
  ) VALUES
    ('b5200000-0000-4000-8000-000000000001'::uuid,
     '${primary_project_id}'::uuid, 1, '${app_user_id}'::uuid,
     '2030-01-01T00:00:00Z'::timestamptz),
    ('b5200000-0000-4000-8000-000000000002'::uuid,
     '${secondary_project_id}'::uuid, 1, '${app_user_id}'::uuid,
     '2030-01-01T00:00:00Z'::timestamptz);

  INSERT INTO app_data.promotion_target_relationship_revisions (
    promotion_target_id, project_id, revision_number,
    old_stage, new_stage, old_lifecycle_status, new_lifecycle_status,
    changed_fields, reason_code, changed_by_app_user_id, changed_at
  ) VALUES
    ('b5200000-0000-4000-8000-000000000001'::uuid,
     '${primary_project_id}'::uuid, 2, 1, 2, 'active', 'active',
     ARRAY['stage']::text[], 'progress_update', '${app_user_id}'::uuid,
     '2030-01-02T00:00:00Z'::timestamptz),
    ('b5200000-0000-4000-8000-000000000002'::uuid,
     '${secondary_project_id}'::uuid, 2, 1, 3, 'active', 'active',
     ARRAY['stage']::text[], 'progress_update', '${app_user_id}'::uuid,
     '2030-01-02T00:00:00Z'::timestamptz);
" >/dev/null

project_pointer_lock_relation="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT oid
  FROM pg_catalog.pg_class
  WHERE relnamespace = 'app_data'::regnamespace
    AND relname = 'user_current_projects';
")"
project_pointer_lock_relation="$(printf '%s' "${project_pointer_lock_relation}" | tr -d '[:space:]')"
if [[ ! "${project_pointer_lock_relation}" =~ ^[0-9]+$ ]]; then
  echo "无法解析 user_current_projects relation oid。" >&2
  exit 1
fi

reader_ready_lock="stage-change-summary-concurrency-reader-ready:${primary_project_id}"
switch_ready_lock="stage-change-summary-concurrency-switch-ready:${primary_project_id}"

# The first transaction reads the primary project and holds its pointer row
# lock after the bridge returns.  The project switch must wait for this lock.
"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  WITH result AS (
    SELECT app_data.read_personal_relationship_stage_change_summary_v1(
      '${issuer}', '${subject}',
      '2030-01-01T00:00:00Z'::timestamptz,
      '2030-01-08T00:00:00Z'::timestamptz
    ) AS summary
  )
  SELECT 'STAGE_RESULT|' || (summary->>'project_id') || '|'
    || (summary#>>'{value,event_count}')
  FROM result;
  RESET ROLE;
  SELECT pg_advisory_lock(
    hashtextextended('${reader_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks AS pointer_lock
        JOIN pg_catalog.pg_stat_activity AS waiting_activity
          ON waiting_activity.pid = pointer_lock.pid
        WHERE pointer_lock.locktype = 'tuple'
          AND pointer_lock.relation = ${project_pointer_lock_relation}
          AND waiting_activity.pid <> pg_backend_pid()
          AND waiting_activity.datname = current_database()
          AND waiting_activity.wait_event_type = 'Lock'
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'project switch did not wait for the reader pointer lock';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${temporary_directory}/reader-first.out" 2>&1 &
reader_pid=$!

reader_ready=0
for _ in $(seq 1 100); do
  ready_probe="$(${psql_base[@]} --tuples-only --no-align --command="
    SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('${reader_ready_lock}', 0))
      THEN 'not-ready'
      ELSE 'ready'
    END;
  ")"
  ready_probe="$(printf '%s' "${ready_probe}" | tr -d '[:space:]')"
  if [[ "${ready_probe}" == 'ready' ]]; then
    reader_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${reader_ready}" -ne 1 ]]; then
  echo '读先行会话没有进入 current-project 持锁状态。' >&2
  wait "${reader_pid}" || true
  sed -n '1,120p' "${temporary_directory}/reader-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT count(*)
  FROM app_data.select_personal_project_context(
    '${issuer}', '${subject}', '${secondary_project_id}'::uuid
  );
  RESET ROLE;
" >"${temporary_directory}/switch-writer.out" 2>&1 &
switch_pid=$!

reader_status=0
switch_status=0
wait "${reader_pid}" || reader_status=$?
wait "${switch_pid}" || switch_status=$?
if [[ "${reader_status}" -ne 0 || "${switch_status}" -ne 0 ]]; then
  echo "读先行并发结果错误：reader=${reader_status}, switch=${switch_status}" >&2
  sed -n '1,120p' "${temporary_directory}/reader-first.out" >&2
  sed -n '1,120p' "${temporary_directory}/switch-writer.out" >&2
  exit 1
fi

if ! grep -q "STAGE_RESULT|${primary_project_id}|1" \
  "${temporary_directory}/reader-first.out"; then
  echo '读先行没有返回完整旧项目结果。' >&2
  sed -n '1,120p' "${temporary_directory}/reader-first.out" >&2
  exit 1
fi

current_project="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT project_id
  FROM app_data.user_current_projects
  WHERE app_user_id = '${app_user_id}'::uuid;
")"
current_project="$(printf '%s' "${current_project}" | tr -d '[:space:]')"
if [[ "${current_project}" != "${secondary_project_id}" ]]; then
  echo "读先行之后 current project 错误：${current_project}" >&2
  exit 1
fi

# Restore the primary pointer before the reverse ordering case.
"${psql_base[@]}" --command="
  SET ROLE tongxingzhe_runtime;
  SELECT count(*)
  FROM app_data.select_personal_project_context(
    '${issuer}', '${subject}', '${primary_project_id}'::uuid
  );
  RESET ROLE;
" >/dev/null

# The writer acquires and holds the pointer row lock first.  A reader started
# during that transaction must wait and then return only the newly selected
# secondary project.
"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT count(*)
  FROM app_data.select_personal_project_context(
    '${issuer}', '${subject}', '${secondary_project_id}'::uuid
  );
  RESET ROLE;
  SELECT pg_advisory_lock(
    hashtextextended('${switch_ready_lock}', 0)
  );
  DO \$wait\$
  DECLARE
    wait_deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks AS pointer_lock
        JOIN pg_catalog.pg_stat_activity AS waiting_activity
          ON waiting_activity.pid = pointer_lock.pid
        WHERE pointer_lock.locktype = 'tuple'
          AND pointer_lock.relation = ${project_pointer_lock_relation}
          AND waiting_activity.pid <> pg_backend_pid()
          AND waiting_activity.datname = current_database()
          AND waiting_activity.wait_event_type = 'Lock'
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'summary reader did not wait for the switch pointer lock';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${temporary_directory}/switch-first.out" 2>&1 &
switch_first_pid=$!

switch_ready=0
for _ in $(seq 1 100); do
  ready_probe="$(${psql_base[@]} --tuples-only --no-align --command="
    SELECT CASE
      WHEN pg_try_advisory_lock(hashtextextended('${switch_ready_lock}', 0))
      THEN 'not-ready'
      ELSE 'ready'
    END;
  ")"
  ready_probe="$(printf '%s' "${ready_probe}" | tr -d '[:space:]')"
  if [[ "${ready_probe}" == 'ready' ]]; then
    switch_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${switch_ready}" -ne 1 ]]; then
  echo '切换先行会话没有进入 current-project 持锁状态。' >&2
  wait "${switch_first_pid}" || true
  sed -n '1,120p' "${temporary_directory}/switch-first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  WITH result AS (
    SELECT app_data.read_personal_relationship_stage_change_summary_v1(
      '${issuer}', '${subject}',
      '2030-01-01T00:00:00Z'::timestamptz,
      '2030-01-08T00:00:00Z'::timestamptz
    ) AS summary
  )
  SELECT 'STAGE_RESULT|' || (summary->>'project_id') || '|'
    || (summary#>>'{value,event_count}')
  FROM result;
  RESET ROLE;
" >"${temporary_directory}/waiting-reader.out" 2>&1 &
waiting_reader_pid=$!

switch_first_status=0
waiting_reader_status=0
wait "${switch_first_pid}" || switch_first_status=$?
wait "${waiting_reader_pid}" || waiting_reader_status=$?
if [[ "${switch_first_status}" -ne 0 || "${waiting_reader_status}" -ne 0 ]]; then
  echo "切换先行并发结果错误：switch=${switch_first_status}, reader=${waiting_reader_status}" >&2
  sed -n '1,120p' "${temporary_directory}/switch-first.out" >&2
  sed -n '1,120p' "${temporary_directory}/waiting-reader.out" >&2
  exit 1
fi

if ! grep -q "STAGE_RESULT|${secondary_project_id}|1" \
  "${temporary_directory}/waiting-reader.out"; then
  echo '切换先行没有让等待 reader 返回完整新项目结果。' >&2
  sed -n '1,120p' "${temporary_directory}/waiting-reader.out" >&2
  exit 1
fi

# Leave the committed synthetic pointer in a stable primary state for any
# later manually invoked checks. The committed rows use a private UUID prefix.
"${psql_base[@]}" --command="
  SET ROLE tongxingzhe_runtime;
  SELECT count(*)
  FROM app_data.select_personal_project_context(
    '${issuer}', '${subject}', '${primary_project_id}'::uuid
  );
  RESET ROLE;
" >/dev/null

echo '个人阶段变更汇总并发检查通过：读先行与切换先行均按 current-project 行锁返回完整 snapshot。'
