#!/usr/bin/env bash

set -euo pipefail

# The selection function consumes the 0030 resolver in its own transaction.
# Independent sessions prove that selection and capability revocation share the
# same linearization locks in both transaction orders.
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
  local process_pid="$2"
  local process_output="$3"
  local acquired='f'

  for _ in $(seq 1 80); do
    acquired="$("${psql_base[@]}" --tuples-only --no-align --command="
      WITH probe AS (
        SELECT pg_try_advisory_lock(hashtextextended('${ready_lock}', 0))
          AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${ready_lock}', 0)
        )
        ELSE true
      END
      FROM probe;
    " | tr -d '[:space:]')"
    if [[ "${acquired}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${process_pid}" >/dev/null 2>&1 || true
  wait "${process_pid}" >/dev/null 2>&1 || true
  echo '管理上下文并发会话没有进入持锁状态。' >&2
  sed -n '1,160p' "${process_output}" >&2
  exit 1
}

"${psql_base[@]}" --command="
  INSERT INTO app_data.app_users (app_user_id, status) VALUES
    ('f4100000-0000-4000-8000-000000000001'::uuid, 'active'),
    ('f4100000-0000-4000-8000-000000000002'::uuid, 'active');

  INSERT INTO app_data.external_identities (
    external_identity_id, issuer, subject, app_user_id
  ) VALUES
    (
      'f4e00000-0000-4000-8000-000000000001'::uuid,
      'https://management-context-concurrency.synthetic/auth/v1',
      'selection-first',
      'f4100000-0000-4000-8000-000000000001'::uuid
    ),
    (
      'f4e00000-0000-4000-8000-000000000002'::uuid,
      'https://management-context-concurrency.synthetic/auth/v1',
      'revocation-first',
      'f4100000-0000-4000-8000-000000000002'::uuid
    );

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    'f4200000-0000-4000-8000-000000000001'::uuid,
    'organization',
    'Concurrent management context organization'
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name
  ) VALUES (
    'f4300000-0000-4000-8000-000000000001'::uuid,
    'f4200000-0000-4000-8000-000000000001'::uuid,
    'Concurrent management context project'
  );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id,
    app_user_id, active_from_utc
  ) VALUES
    (
      'f4400000-0000-4000-8000-000000000001'::uuid,
      'f4200000-0000-4000-8000-000000000001'::uuid,
      'f4100000-0000-4000-8000-000000000001'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'f4400000-0000-4000-8000-000000000002'::uuid,
      'f4200000-0000-4000-8000-000000000001'::uuid,
      'f4100000-0000-4000-8000-000000000002'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    );

  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id,
    project_id, active_from_utc
  ) VALUES
    (
      'f4500000-0000-4000-8000-000000000001'::uuid,
      'f4400000-0000-4000-8000-000000000001'::uuid,
      'f4300000-0000-4000-8000-000000000001'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'f4500000-0000-4000-8000-000000000002'::uuid,
      'f4400000-0000-4000-8000-000000000002'::uuid,
      'f4300000-0000-4000-8000-000000000001'::uuid,
      '2026-01-01 00:00:00+00'::timestamptz
    );

  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id,
    capability_id, active_from_utc
  ) VALUES
    (
      'f4600000-0000-4000-8000-000000000001'::uuid,
      'f4500000-0000-4000-8000-000000000001'::uuid,
      'view_anonymous_analytics',
      '2026-01-01 00:00:00+00'::timestamptz
    ),
    (
      'f4600000-0000-4000-8000-000000000002'::uuid,
      'f4500000-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics',
      '2026-01-01 00:00:00+00'::timestamptz
    );
" >/dev/null

selection_first_output="${temporary_directory}/selection-first.out"
revocation_second_output="${temporary_directory}/revocation-second.out"
selection_ready_lock='management-analysis-context-ready:selection-first'

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT * FROM app_data.select_management_analysis_context_v1(
    'https://management-context-concurrency.synthetic/auth/v1',
    'selection-first',
    'f4300000-0000-4000-8000-000000000001'::uuid
  );
  SELECT pg_advisory_lock(hashtextextended('${selection_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'revocation did not wait for context selection';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${selection_first_output}" 2>&1 &
selection_first_pid=$!

wait_for_ready \
  "${selection_ready_lock}" \
  "${selection_first_pid}" \
  "${selection_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    'f4600000-0000-4000-8000-000000000001'::uuid;
" >"${revocation_second_output}" 2>&1 &
revocation_second_pid=$!

selection_first_status=0
revocation_second_status=0
wait "${selection_first_pid}" || selection_first_status=$?
wait "${revocation_second_pid}" || revocation_second_status=$?
if [[ "${selection_first_status}" -ne 0 || "${revocation_second_status}" -ne 0 ]]; then
  echo "选择先行并发结果错误：selection=${selection_first_status}, revocation=${revocation_second_status}" >&2
  sed -n '1,160p' "${selection_first_output}" >&2
  sed -n '1,160p' "${revocation_second_output}" >&2
  exit 1
fi

selection_after_revocation="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT count(*) FROM app_data.list_management_analysis_contexts_v1(
    'https://management-context-concurrency.synthetic/auth/v1',
    'selection-first'
  ) WHERE is_current;
" | tr -d '[:space:]')"
if [[ "${selection_after_revocation}" -ne 0 ]]; then
  echo '撤权提交后，旧管理上下文仍被返回为 current。' >&2
  exit 1
fi

revocation_first_output="${temporary_directory}/revocation-first.out"
selection_second_output="${temporary_directory}/selection-second.out"
revocation_ready_lock='management-analysis-context-ready:revocation-first'

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    'f4600000-0000-4000-8000-000000000002'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revocation_ready_lock}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        SELECT 1 FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'selection did not wait for revocation';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${revocation_first_output}" 2>&1 &
revocation_first_pid=$!

wait_for_ready \
  "${revocation_ready_lock}" \
  "${revocation_first_pid}" \
  "${revocation_first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT * FROM app_data.select_management_analysis_context_v1(
    'https://management-context-concurrency.synthetic/auth/v1',
    'revocation-first',
    'f4300000-0000-4000-8000-000000000001'::uuid
  );
" >"${selection_second_output}" 2>&1 &
selection_second_pid=$!

revocation_first_status=0
selection_second_status=0
wait "${revocation_first_pid}" || revocation_first_status=$?
wait "${selection_second_pid}" || selection_second_status=$?
if [[ "${revocation_first_status}" -ne 0 || "${selection_second_status}" -eq 0 ]]; then
  echo "撤权先行并发结果错误：revocation=${revocation_first_status}, selection=${selection_second_status}" >&2
  sed -n '1,160p' "${revocation_first_output}" >&2
  sed -n '1,160p' "${selection_second_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${selection_second_output}"; then
  echo '等待撤权的管理上下文选择没有按预期失败。' >&2
  sed -n '1,160p' "${selection_second_output}" >&2
  exit 1
fi

unexpected_selection="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_data.management_analysis_current_contexts
  WHERE app_user_id = 'f4100000-0000-4000-8000-000000000002'::uuid;
" | tr -d '[:space:]')"
if [[ "${unexpected_selection}" -ne 0 ]]; then
  echo '撤权先行后仍保存了管理上下文选择。' >&2
  exit 1
fi

echo '管理分析上下文并发检查通过：选择与查看能力撤权按共享授权锁顺序完成。'
