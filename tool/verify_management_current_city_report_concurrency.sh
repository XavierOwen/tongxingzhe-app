#!/usr/bin/env bash

set -euo pipefail

# Independent sessions prove that the current-city report executor and
# canonical-region publication share one transaction boundary.  A report that
# starts while a publication is uncommitted must wait and then use the
# committed tree.  A report-first transaction must block a later publication,
# and the cutoff captured by that report must remain bound to the old tree.
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
    "${report_first_pid:-}" \
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
    # stdout from a redirected psql process may be block-buffered.  Inspect the
    # matching advisory lock directly instead of relying on its "ready" row.
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
  echo 'current 城市报告并发会话没有进入持锁状态。' >&2
  sed -n '1,160p' "${process_output}" >&2
  exit 1
}

project_id='6a300000-0000-4000-8000-000000000001'
app_user_id='6a100000-0000-4000-8000-000000000001'
workspace_id='6a200000-0000-4000-8000-000000000001'
questionnaire_version_id='6a700000-0000-4000-8000-000000000001'
base_tree_version='concurrent-current-city-report-base-v1'
first_tree_version='concurrent-current-city-report-a-v1'
second_tree_version='concurrent-current-city-report-b-v1'
report_id='contact_sessions_by_current_city_two_periods'

"${psql_base[@]}" --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('${app_user_id}'::uuid, 'active');

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    '${workspace_id}'::uuid,
    'organization',
    'Concurrent current city report workspace'
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name
  ) VALUES (
    '${project_id}'::uuid,
    '${workspace_id}'::uuid,
    'Concurrent current city report project'
  );

  INSERT INTO app_data.questionnaire_versions (
    questionnaire_version_id,
    project_id,
    version_number,
    status,
    is_current
  ) VALUES (
    '${questionnaire_version_id}'::uuid,
    '${project_id}'::uuid,
    1,
    'published',
    true
  );

  SELECT app_private.configure_project_reporting_time_zone_v1(
    '6a900000-0000-4000-8000-000000000001'::uuid,
    '${app_user_id}'::uuid,
    '${project_id}'::uuid,
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );

  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES
    ('${base_tree_version}', 'draft', false),
    ('${first_tree_version}', 'draft', false),
    ('${second_tree_version}', 'draft', false);

  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('concurrent-current-city-report-base-country', '${base_tree_version}', NULL, 'Base Country', 'country'),
    ('concurrent-current-city-report-base-city', '${base_tree_version}', 'concurrent-current-city-report-base-country', 'Base City', 'city'),
    ('concurrent-current-city-report-base-venue', '${base_tree_version}', 'concurrent-current-city-report-base-city', 'Base Venue', 'venue'),
    ('concurrent-current-city-report-a-country', '${first_tree_version}', NULL, 'A Country', 'country'),
    ('concurrent-current-city-report-a-city', '${first_tree_version}', 'concurrent-current-city-report-a-country', 'A City', 'city'),
    ('concurrent-current-city-report-a-venue', '${first_tree_version}', 'concurrent-current-city-report-a-city', 'A Venue', 'venue'),
    ('concurrent-current-city-report-b-country', '${second_tree_version}', NULL, 'B Country', 'country'),
    ('concurrent-current-city-report-b-city', '${second_tree_version}', 'concurrent-current-city-report-b-country', 'B City', 'city'),
    ('concurrent-current-city-report-b-venue', '${second_tree_version}', 'concurrent-current-city-report-b-city', 'B Venue', 'venue');

  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES
    (
      'concurrent-current-city-report-base-boundary',
      'concurrent-current-city-report-base-venue',
      '${base_tree_version}',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    ),
    (
      'concurrent-current-city-report-a-boundary',
      'concurrent-current-city-report-a-venue',
      '${first_tree_version}',
      polygon '((-87.62,41.77),(-87.57,41.77),(-87.57,41.81),(-87.62,41.81))'
    ),
    (
      'concurrent-current-city-report-b-boundary',
      'concurrent-current-city-report-b-venue',
      '${second_tree_version}',
      polygon '((-87.63,41.76),(-87.56,41.76),(-87.56,41.82),(-87.63,41.82))'
    );

  SELECT app_private.publish_canonical_region_tree_v1(
    '${base_tree_version}', true
  );
" >/dev/null

assert_report_shape() {
  local expected_tree_version="$1"
  local document="$2"
  local shape

  shape="$("${psql_base[@]}" --tuples-only --no-align --command="
    SELECT
      CASE
        WHEN document->>'report_id' = '${report_id}'
         AND document->>'report_version' = '1'
         AND document->>'metric_id' = 'contact_sessions'
         AND document->>'metric_version' = '1'
         AND document->>'dimension' = 'current_city'
         AND document->>'query_fingerprint' =
           'management-report:contact_sessions_by_current_city_two_periods:v1'
         AND document->>'privacy_policy' =
           'management_current_city_contact_session_privacy_v1'
         AND document->>'source_scope' =
           'backend_accepted_active_contacts_current_revision'
         AND document->>'result_status' = 'completed'
         AND jsonb_typeof(document->'periods') = 'object'
         AND document->'target_context'->>'target_tree_version' =
           '${expected_tree_version}'
         AND document->>'data_cutoff_utc' IS NOT NULL
         AND document->>'source_change_sequence' IS NOT NULL
        THEN 'ok'
        ELSE document::text
      END
    FROM (
      SELECT '${document}'::jsonb AS document
    ) AS report;
  " | tr -d '\n')"
  if [[ "${shape}" != 'ok' ]]; then
    echo "current 城市报告合同或目标树错误（期望 ${expected_tree_version}）：${shape}" >&2
    exit 1
  fi
}

run_report_for_cutoff() {
  local cutoff="$1"
  "${psql_base[@]}" --tuples-only --no-align --command="
    SELECT app_private.execute_management_current_city_contact_session_report_v1(
      '${project_id}'::uuid,
      'UTC',
      '${cutoff}'::timestamptz
    )::text;
  " | tr -d '\r\n'
}

publication_first_output="${temporary_directory}/publication-first.out"
publication_first_ready='management-current-city-report-publication-first-ready-v1'

# Publication-first: A owns the shared transaction lock while uncommitted. The
# report starts after that point and must wait before choosing its target.
"${psql_base[@]}" --command="
  BEGIN;
  SELECT app_private.publish_canonical_region_tree_v1(
    '${first_tree_version}', true
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

publication_first_document="$(run_report_for_cutoff "$(
  "${psql_base[@]}" --tuples-only --no-align \
    --command="SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',
      'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"');"
)")"
assert_report_shape "${first_tree_version}" "${publication_first_document}"

publication_first_status=0
wait "${publication_first_pid}" || publication_first_status=$?
if [[ "${publication_first_status}" -ne 0 ]]; then
  echo 'publication-first 会话失败。' >&2
  sed -n '1,160p' "${publication_first_output}" >&2
  exit 1
fi

report_first_output="${temporary_directory}/report-first.out"
report_first_ready='management-current-city-report-report-first-ready-v1'

# Report-first: the executor keeps the shared publication lock until COMMIT.
# The cutoff and selected A target are emitted for the old-cutoff replay check.
"${psql_base[@]}" --tuples-only --no-align --command="
  BEGIN;
  WITH request AS (
    SELECT clock_timestamp() AS data_cutoff_utc
  ), report AS (
    SELECT
      request.data_cutoff_utc,
      app_private.execute_management_current_city_contact_session_report_v1(
        '${project_id}'::uuid,
        'UTC',
        request.data_cutoff_utc
      ) AS document
    FROM request
  )
  SELECT
    (document->'target_context'->>'target_tree_version')
      || '|' || (document->>'data_cutoff_utc')
  FROM report;
  SELECT pg_advisory_lock(hashtextextended('${report_first_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${report_first_output}" 2>&1 &
report_first_pid=$!

wait_for_ready_lock \
  "${report_first_ready}" \
  "${report_first_pid}" \
  "${report_first_output}"

publication_second_output="${temporary_directory}/publication-second.out"
"${psql_base[@]}" --command="
  SELECT app_private.publish_canonical_region_tree_v1(
    '${second_tree_version}', true
  );
" >"${publication_second_output}" 2>&1 &
publication_second_pid=$!

sleep 0.3
if ! kill -0 "${publication_second_pid}" >/dev/null 2>&1; then
  wait "${publication_second_pid}" >/dev/null 2>&1 || true
  echo 'publisher 没有等待 report-first 的 publication lock。' >&2
  sed -n '1,160p' "${publication_second_output}" >&2
  exit 1
fi

report_first_status=0
publication_second_status=0
wait "${report_first_pid}" || report_first_status=$?
wait "${publication_second_pid}" || publication_second_status=$?
if [[ "${report_first_status}" -ne 0 ]]; then
  echo 'report-first 会话失败。' >&2
  sed -n '1,160p' "${report_first_output}" >&2
  exit 1
fi
if [[ "${publication_second_status}" -ne 0 ]]; then
  echo '等待 report-first 的 publisher 会话失败。' >&2
  sed -n '1,160p' "${publication_second_output}" >&2
  exit 1
fi

report_first_line="$(
  sed -n "/^${first_tree_version}|/p" "${report_first_output}" \
    | tail -n 1
)"
if [[ -z "${report_first_line}" ]]; then
  echo 'report-first 没有返回 A 和固定 cutoff。' >&2
  sed -n '1,160p' "${report_first_output}" >&2
  exit 1
fi
old_cutoff="${report_first_line#*|}"

old_report_document="$(run_report_for_cutoff "${old_cutoff}")"
assert_report_shape "${first_tree_version}" "${old_report_document}"

new_report_document="$(
  run_report_for_cutoff "$(
    "${psql_base[@]}" --tuples-only --no-align \
      --command="SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',
        'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"');"
  )"
)"
assert_report_shape "${second_tree_version}" "${new_report_document}"

echo 'current 城市报告并发检查通过：publication-first 与 report-first 均按共享锁线性化，旧 cutoff 不漂移。'
