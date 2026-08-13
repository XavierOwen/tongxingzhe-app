#!/usr/bin/env bash

set -euo pipefail

# Two independent runtime sessions submit the same expected version. The first
# holds the project lock before configuring; the second must wait and then fail
# closed with a version conflict rather than create a second version 1.
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
    "${temporary_directory}/second.out" \
    "${temporary_directory}/archive.out" \
    "${temporary_directory}/revoked-configure.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

issuer='https://synthetic-follow-up-consent-opt-in-concurrency.example.test/auth/v1'
subject='follow-up-consent-opt-in-concurrency-owner'
project_id="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT project_id
  FROM app_data.bootstrap_personal_context(
    '${issuer}',
    '${subject}'
  );
")"
project_id="$(printf '%s' "${project_id}" | tr -d '[:space:]')"
if [[ ! "${project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "并发 fixture 没有得到合法个人项目：${project_id}" >&2
  exit 1
fi

project_lock="project-follow-up-consent-opt-in:${project_id}"
ready_signal_lock="project-follow-up-consent-opt-in-concurrency-ready:${project_id}"

"${psql_base[@]}" --command="
  SELECT app_data.read_project_follow_up_consent_opt_in_v1(
    '${issuer}',
    '${subject}',
    '${project_id}'::uuid,
    'follow_up_consent_ratio@1'
  );
" >/dev/null

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${project_lock}', 0)
  );
  SELECT pg_advisory_lock(
    hashtextextended('${ready_signal_lock}', 0)
  );
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
    '${issuer}',
    '${subject}',
    '${project_id}'::uuid,
    'follow_up_consent_ratio@1',
    'e4b00000-0000-4000-8000-000000000001'::uuid,
    0,
    true
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
        RAISE EXCEPTION 'second project opt-in request did not wait';
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
  ready_probe="$(${psql_base[@]} \
    --tuples-only \
    --no-align \
    --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(
          hashtextextended('${ready_signal_lock}', 0)
        ) THEN 'not-ready'
        ELSE 'ready'
      END;
    ")"
  if [[ "${ready_probe}" == *ready* && "${ready_probe}" != *not-ready* ]]; then
    first_ready=1
    break
  fi
  sleep 0.1
done

if [[ "${first_ready}" -ne 1 ]]; then
  echo '首个项目同意占比配置会话没有进入持锁状态。' >&2
  wait "${first_pid}" || true
  sed -n '1,120p' "${temporary_directory}/first.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
    '${issuer}',
    '${subject}',
    '${project_id}'::uuid,
    'follow_up_consent_ratio@1',
    'e4b00000-0000-4000-8000-000000000002'::uuid,
    0,
    false
  );
" >"${temporary_directory}/second.out" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?

if [[ "${first_status}" -ne 0 || "${second_status}" -eq 0 ]]; then
  echo "项目同意占比并发结果错误：first=${first_status}, second=${second_status}" >&2
  sed -n '1,120p' "${temporary_directory}/first.out" >&2
  sed -n '1,120p' "${temporary_directory}/second.out" >&2
  exit 1
fi

if ! grep -q \
  'project follow-up consent opt-in version conflict' \
  "${temporary_directory}/second.out"; then
  echo '并发失败不是期望版本冲突。' >&2
  sed -n '1,120p' "${temporary_directory}/second.out" >&2
  exit 1
fi

result="$(${psql_base[@]} \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      count(*),
      count(*) FILTER (WHERE version_number = 1),
      count(*) FILTER (WHERE enabled),
      count(*) FILTER (WHERE NOT enabled)
    FROM app_private.project_follow_up_consent_opt_in_versions
    WHERE project_id = '${project_id}'::uuid;
  ")"
IFS='|' read -r version_count first_version_count enabled_count disabled_count <<< "${result}"
if [[ "${version_count}" -ne 1 \
  || "${first_version_count}" -ne 1 \
  || "${enabled_count}" -ne 1 \
  || "${disabled_count}" -ne 0 ]]; then
  echo "项目同意占比并发不变量失败：versions=${version_count}, first=${first_version_count}, enabled=${enabled_count}, disabled=${disabled_count}" >&2
  exit 1
fi

echo '项目同意占比并发检查通过：相同期望版本只有一个配置提交。'

# A second project proves that authorization is checked after waiting for the
# project lock. The maintenance transaction archives the project while holding
# that lock. The runtime request starts with an otherwise valid identity, waits,
# then must observe the committed archive and fail without appending history.
archive_project_id="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT project_id
  FROM app_data.create_personal_project_context(
    '${issuer}',
    '${subject}',
    'Concurrent archived consent project'
  );
")"
archive_project_id="$(printf '%s' "${archive_project_id}" | tr -d '[:space:]')"
if [[ ! "${archive_project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "归档并发 fixture 没有得到合法个人项目：${archive_project_id}" >&2
  exit 1
fi

archive_project_lock="project-follow-up-consent-opt-in:${archive_project_id}"
archive_ready_lock="project-follow-up-consent-opt-in-archive-ready:${archive_project_id}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(
    hashtextextended('${archive_project_lock}', 0)
  );
  SELECT pg_advisory_lock(
    hashtextextended('${archive_ready_lock}', 0)
  );
  UPDATE app_data.projects
  SET status = 'archived'
  WHERE project_id = '${archive_project_id}'::uuid;
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
        RAISE EXCEPTION 'revoked project opt-in request did not wait';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${temporary_directory}/archive.out" 2>&1 &
archive_pid=$!

archive_ready=0
for _ in $(seq 1 50); do
  ready_probe="$(${psql_base[@]} \
    --tuples-only \
    --no-align \
    --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(
          hashtextextended('${archive_ready_lock}', 0)
        ) THEN 'not-ready'
        ELSE 'ready'
      END;
    ")"
  if [[ "${ready_probe}" == *ready* && "${ready_probe}" != *not-ready* ]]; then
    archive_ready=1
    break
  fi
  sleep 0.1
done

if [[ "${archive_ready}" -ne 1 ]]; then
  echo '项目归档会话没有进入持锁状态。' >&2
  wait "${archive_pid}" || true
  sed -n '1,120p' "${temporary_directory}/archive.out" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SET ROLE tongxingzhe_runtime;
  SELECT app_data.configure_project_follow_up_consent_opt_in_v1(
    '${issuer}',
    '${subject}',
    '${archive_project_id}'::uuid,
    'follow_up_consent_ratio@1',
    'e4b00000-0000-4000-8000-000000000003'::uuid,
    0,
    true
  );
" >"${temporary_directory}/revoked-configure.out" 2>&1 &
revoked_pid=$!

archive_status=0
revoked_status=0
wait "${archive_pid}" || archive_status=$?
wait "${revoked_pid}" || revoked_status=$?

if [[ "${archive_status}" -ne 0 || "${revoked_status}" -eq 0 ]]; then
  echo "项目归档竞争结果错误：archive=${archive_status}, configure=${revoked_status}" >&2
  sed -n '1,120p' "${temporary_directory}/archive.out" >&2
  sed -n '1,120p' "${temporary_directory}/revoked-configure.out" >&2
  exit 1
fi

if ! grep -q \
  'project follow-up consent opt-in scope is forbidden' \
  "${temporary_directory}/revoked-configure.out"; then
  echo '归档后的配置失败不是重新授权拒绝。' >&2
  sed -n '1,120p' "${temporary_directory}/revoked-configure.out" >&2
  exit 1
fi

revoked_history_count="$(${psql_base[@]} \
  --tuples-only \
  --no-align \
  --command="
    SELECT count(*)
    FROM app_private.project_follow_up_consent_opt_in_versions
    WHERE project_id = '${archive_project_id}'::uuid;
  ")"
revoked_history_count="$(printf '%s' "${revoked_history_count}" | tr -d '[:space:]')"
if [[ "${revoked_history_count}" -ne 0 ]]; then
  echo "归档项目留下了配置历史：${revoked_history_count}" >&2
  exit 1
fi

echo '项目同意占比撤权竞争检查通过：锁等待后重新授权，归档项目没有写入历史。'
