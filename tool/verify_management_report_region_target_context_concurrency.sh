#!/usr/bin/env bash

set -euo pipefail

# Prove that report-cutoff target selection and canonical-tree publication
# share one transaction lock. The two orders below must produce committed,
# repeatable history rather than a mutable is_current projection.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:+${PGOPTIONS} }-c statement_timeout=30000 -c lock_timeout=15000"

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

temporary_directory="$(mktemp -d)"
cleanup() {
  local child_pid
  for child_pid in \
    "${publication_first_pid:-}" \
    "${resolver_first_pid:-}" \
    "${publication_second_pid:-}"
  do
    if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" >/dev/null 2>&1; then
      kill "${child_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${child_pid}" ]]; then
      wait "${child_pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_ready_lock() {
  local ready_lock="$1"
  local process_pid="$2"
  local process_output="$3"
  local lock_held='f'

  for _ in $(seq 1 100); do
    lock_held="$("${psql_base[@]}" --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          (hashtextextended('${ready_lock}', 0) >> 32)
            & 4294967295 AS classid,
          hashtextextended('${ready_lock}', 0)
            & 4294967295 AS objid
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND lock_row.granted
          AND lock_row.pid <> pg_backend_pid()
      );
    " | tr -d '[:space:]')"
    if [[ "${lock_held}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${process_pid}" >/dev/null 2>&1 || true
  wait "${process_pid}" >/dev/null 2>&1 || true
  echo '区域目标上下文并发会话没有进入持锁状态。' >&2
  sed -n '1,160p' "${process_output}" >&2
  exit 1
}

"${psql_base[@]}" --command="
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES
    ('concurrent-target-context-base', 'draft', false),
    ('concurrent-target-context-a', 'draft', false),
    ('concurrent-target-context-b', 'draft', false);

  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('target-context-base-country', 'concurrent-target-context-base', NULL, 'Base Country', 'country'),
    ('target-context-base-city', 'concurrent-target-context-base', 'target-context-base-country', 'Base City', 'city'),
    ('target-context-base-venue', 'concurrent-target-context-base', 'target-context-base-city', 'Base Venue', 'venue'),
    ('target-context-a-country', 'concurrent-target-context-a', NULL, 'A Country', 'country'),
    ('target-context-a-city', 'concurrent-target-context-a', 'target-context-a-country', 'A City', 'city'),
    ('target-context-a-venue', 'concurrent-target-context-a', 'target-context-a-city', 'A Venue', 'venue'),
    ('target-context-b-country', 'concurrent-target-context-b', NULL, 'B Country', 'country'),
    ('target-context-b-city', 'concurrent-target-context-b', 'target-context-b-country', 'B City', 'city'),
    ('target-context-b-venue', 'concurrent-target-context-b', 'target-context-b-city', 'B Venue', 'venue');

  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES
    (
      'target-context-base-boundary', 'target-context-base-venue',
      'concurrent-target-context-base',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    ),
    (
      'target-context-a-boundary', 'target-context-a-venue',
      'concurrent-target-context-a',
      polygon '((-87.62,41.77),(-87.57,41.77),(-87.57,41.81),(-87.62,41.81))'
    ),
    (
      'target-context-b-boundary', 'target-context-b-venue',
      'concurrent-target-context-b',
      polygon '((-87.63,41.76),(-87.56,41.76),(-87.56,41.82),(-87.63,41.82))'
    );

  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-target-context-base', true
  );
" >/dev/null

publication_first_output="${temporary_directory}/publication-first.out"
publication_first_ready='management-region-target-publication-first-ready-v1'

"${psql_base[@]}" --command="
  BEGIN;
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-target-context-a', true
  );
  SELECT pg_advisory_lock(hashtextextended('${publication_first_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${publication_first_output}" 2>&1 &
publication_first_pid=$!

wait_for_ready_lock \
  "${publication_first_ready}" \
  "${publication_first_pid}" \
  "${publication_first_output}"

# The request cutoff is captured after A wrote its still-uncommitted selection.
# The resolver must wait, refresh its read after the lock, and return committed A.
publication_first_result="$("${psql_base[@]}" --tuples-only --no-align --command="
  WITH request AS (
    SELECT clock_timestamp() AS data_cutoff_utc
  ), resolved AS (
    SELECT app_private.resolve_management_report_region_target_context_v1(
      request.data_cutoff_utc
    ) AS document
    FROM request
  )
  SELECT document->>'target_tree_version'
  FROM resolved;
" | tr -d '[:space:]')"

publication_first_status=0
wait "${publication_first_pid}" || publication_first_status=$?
if [[ "${publication_first_status}" -ne 0 ]]; then
  echo 'publication-first 会话失败。' >&2
  sed -n '1,160p' "${publication_first_output}" >&2
  exit 1
fi
if [[ "${publication_first_result}" != 'concurrent-target-context-a' ]]; then
  echo "resolver 等待 publication 后没有读取 A：${publication_first_result}" >&2
  exit 1
fi

resolver_first_output="${temporary_directory}/resolver-first.out"
resolver_first_ready='management-region-target-resolver-first-ready-v1'

# The resolver obtains the shared publication lock and keeps it until COMMIT.
# Its cutoff and selected A context are written to stdout for the repeat check.
"${psql_base[@]}" --tuples-only --no-align --command="
  BEGIN;
  WITH request AS (
    SELECT clock_timestamp() AS data_cutoff_utc
  ), resolved AS (
    SELECT
      request.data_cutoff_utc,
      app_private.resolve_management_report_region_target_context_v1(
        request.data_cutoff_utc
      ) AS document
    FROM request
  )
  SELECT
    (document->>'target_tree_version')
      || '|'
      || (document->>'data_cutoff_utc')
  FROM resolved;
  SELECT pg_advisory_lock(hashtextextended('${resolver_first_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${resolver_first_output}" 2>&1 &
resolver_first_pid=$!

wait_for_ready_lock \
  "${resolver_first_ready}" \
  "${resolver_first_pid}" \
  "${resolver_first_output}"

publication_second_output="${temporary_directory}/publication-second.out"
"${psql_base[@]}" --command="
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-target-context-b', true
  );
" >"${publication_second_output}" 2>&1 &
publication_second_pid=$!

sleep 0.3
if ! kill -0 "${publication_second_pid}" >/dev/null 2>&1; then
  wait "${publication_second_pid}" >/dev/null 2>&1 || true
  echo 'publisher 没有等待 resolver-first 的 publication lock。' >&2
  sed -n '1,160p' "${publication_second_output}" >&2
  exit 1
fi

resolver_first_status=0
publication_second_status=0
wait "${resolver_first_pid}" || resolver_first_status=$?
wait "${publication_second_pid}" || publication_second_status=$?
if [[ "${resolver_first_status}" -ne 0 ]]; then
  echo 'resolver-first 会话失败。' >&2
  sed -n '1,160p' "${resolver_first_output}" >&2
  exit 1
fi
if [[ "${publication_second_status}" -ne 0 ]]; then
  echo '等待 resolver 的 publisher 会话失败。' >&2
  sed -n '1,160p' "${publication_second_output}" >&2
  exit 1
fi

resolver_first_line="$(
  sed -n '/^concurrent-target-context-a|/p' "${resolver_first_output}" \
    | tail -n 1
)"
if [[ -z "${resolver_first_line}" ]]; then
  echo 'resolver-first 没有返回 A 和固定 cutoff。' >&2
  sed -n '1,160p' "${resolver_first_output}" >&2
  exit 1
fi
old_cutoff="${resolver_first_line#*|}"

old_context="$("${psql_base[@]}" --tuples-only --no-align --command="
  SELECT document->>'target_tree_version'
  FROM (
    SELECT app_private.resolve_management_report_region_target_context_v1(
      '${old_cutoff}'::timestamptz
    ) AS document
  ) AS resolved;
" | tr -d '[:space:]')"
new_context="$("${psql_base[@]}" --tuples-only --no-align --command="
  WITH request AS (
    SELECT clock_timestamp() AS data_cutoff_utc
  )
  SELECT document->>'target_tree_version'
  FROM request
  CROSS JOIN LATERAL (
    SELECT app_private.resolve_management_report_region_target_context_v1(
      request.data_cutoff_utc
    ) AS document
  ) AS resolved;
" | tr -d '[:space:]')"

if [[ "${old_context}" != 'concurrent-target-context-a' ]]; then
  echo "旧 cutoff 在 B 发布后发生漂移：${old_context}" >&2
  exit 1
fi
if [[ "${new_context}" != 'concurrent-target-context-b' ]]; then
  echo "新 cutoff 没有读取已提交 B：${new_context}" >&2
  exit 1
fi

echo '管理区域目标上下文并发检查通过：publication-first 与 resolver-first 均按共享锁线性化，旧 cutoff 不漂移。'
