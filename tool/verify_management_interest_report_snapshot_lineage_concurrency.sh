#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo '请设置 DATABASE_URL。' >&2
  exit 1
fi

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c statement_timeout=30000 -c lock_timeout=15000"
run_psql() {
  "${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}

tmp_dir="$(mktemp -d)"
same_first_pid=''
same_second_pid=''
lineage_first_pid=''
lineage_second_pid=''

cleanup() {
  for pid in "${same_first_pid}" "${same_second_pid}" \
    "${lineage_first_pid}" "${lineage_second_pid}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${tmp_dir}"/*.out
  rmdir "${tmp_dir}"
}
trap cleanup EXIT

wait_ready() {
  local lock_name="$1"
  local pid="$2"
  local output="$3"
  local held
  for _ in $(seq 1 100); do
    held="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT (hashtextextended('${lock_name}', 0) >> 32)
          & 4294967295 AS classid,
          hashtextextended('${lock_name}', 0) & 4294967295 AS objid
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
    if [[ "${held}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done
  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
  sed -n '1,160p' "${output}" >&2
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  exit 1
}

# Keep this namespace separate from the rollback fixture and from other
# concurrency scripts.  Both projects have the same safe ten-cell report.
run_psql --command="
  BEGIN;

  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('6e110000-0000-4000-8000-000000000001'::uuid, 'active'),
    ('6e110000-0000-4000-8000-000000000002'::uuid, 'active'),
    ('6e110000-0000-4000-8000-000000000003'::uuid, 'active');
  INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
  VALUES ('6e120000-0000-4000-8000-000000000001'::uuid,
    'organization', '6AW interest release concurrency workspace');
  INSERT INTO app_data.projects (project_id, workspace_id, display_name)
  VALUES
    ('6e130000-0000-4000-8000-000000000001'::uuid,
      '6e120000-0000-4000-8000-000000000001'::uuid, '6AW same request'),
    ('6e130000-0000-4000-8000-000000000002'::uuid,
      '6e120000-0000-4000-8000-000000000001'::uuid, '6AW one baseline');
  INSERT INTO app_data.questionnaire_versions
    (questionnaire_version_id, project_id, version_number, status, is_current)
  VALUES
    ('6e140000-0000-4000-8000-000000000001'::uuid,
      '6e130000-0000-4000-8000-000000000001'::uuid, 1, 'published', true),
    ('6e140000-0000-4000-8000-000000000002'::uuid,
      '6e130000-0000-4000-8000-000000000002'::uuid, 1, 'published', true);
  INSERT INTO app_data.organization_memberships
    (organization_membership_id, organization_workspace_id, app_user_id,
      active_from_utc, inactive_from_utc)
  VALUES ('6e160000-0000-4000-8000-000000000001'::uuid,
    '6e120000-0000-4000-8000-000000000001'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL);
  INSERT INTO app_data.organization_owner_assignments
    (organization_owner_assignment_id, organization_membership_id,
      active_from_utc, inactive_from_utc)
  VALUES ('6e190000-0000-4000-8000-000000000001'::uuid,
    '6e160000-0000-4000-8000-000000000001'::uuid,
    transaction_timestamp(), NULL);
  INSERT INTO app_data.project_memberships
    (project_membership_id, organization_membership_id, project_id,
      active_from_utc, inactive_from_utc)
  VALUES
    ('6e170000-0000-4000-8000-000000000001'::uuid,
      '6e160000-0000-4000-8000-000000000001'::uuid,
      '6e130000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '30 days', NULL),
    ('6e170000-0000-4000-8000-000000000002'::uuid,
      '6e160000-0000-4000-8000-000000000001'::uuid,
      '6e130000-0000-4000-8000-000000000002'::uuid,
      clock_timestamp() - interval '30 days', NULL);
  INSERT INTO app_data.management_report_capability_grants
    (capability_grant_id, project_membership_id, capability_id,
      active_from_utc, inactive_from_utc)
  VALUES
    ('6e180000-0000-4000-8000-000000000001'::uuid,
      '6e170000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', clock_timestamp() - interval '30 days', NULL),
    ('6e180000-0000-4000-8000-000000000002'::uuid,
      '6e170000-0000-4000-8000-000000000002'::uuid,
      'release_management_reports', clock_timestamp() - interval '30 days', NULL);
  SELECT app_private.configure_project_reporting_time_zone_v1(
    '6e150000-0000-4000-8000-000000000001'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    '6e130000-0000-4000-8000-000000000001'::uuid, 0, 'UTC',
    clock_timestamp() - interval '30 days');
  SELECT app_private.configure_project_reporting_time_zone_v1(
    '6e150000-0000-4000-8000-000000000002'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    '6e130000-0000-4000-8000-000000000002'::uuid, 0, 'UTC',
    clock_timestamp() - interval '30 days');
  CREATE TEMP TABLE fixture_6aw_concurrency_periods AS
  SELECT app_private.resolve_management_report_periods_v1(
    'UTC', clock_timestamp()
  ) AS periods;
  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    first_submitted_at_utc, channel, location_kind, reach_count, interest_level
  )
  SELECT
    format('6aw-concurrent-%s-%s-%s-%s-%s', project_row.project_number,
      period_row.period_key, level_row, contributor_row.contributor_number,
      unit_row.unit_number),
    CASE contributor_row.contributor_number
      WHEN 1 THEN '6e110000-0000-4000-8000-000000000001'::uuid
      WHEN 2 THEN '6e110000-0000-4000-8000-000000000002'::uuid
      ELSE '6e110000-0000-4000-8000-000000000003'::uuid
    END,
    '6e120000-0000-4000-8000-000000000001'::uuid,
    project_row.project_id,
    project_row.questionnaire_version_id,
    period_row.period_start_utc + interval '1 minute',
    'UTC',
    period_row.period_start_utc + interval '1 minute',
    'voice_call', 'not_applicable', 1, level_row
  FROM (VALUES
    (1, '6e130000-0000-4000-8000-000000000001'::uuid,
      '6e140000-0000-4000-8000-000000000001'::uuid),
    (2, '6e130000-0000-4000-8000-000000000002'::uuid,
      '6e140000-0000-4000-8000-000000000002'::uuid)
  ) AS project_row(project_number, project_id, questionnaire_version_id)
  CROSS JOIN fixture_6aw_concurrency_periods AS context
  CROSS JOIN LATERAL (VALUES
    ('previous', (context.periods->'previous_period'->>'start_utc')::timestamptz),
    ('current', (context.periods->'current_period'->>'start_utc')::timestamptz)
  ) AS period_row(period_key, period_start_utc)
  CROSS JOIN generate_series(0, 4) AS level_row
  CROSS JOIN (VALUES (1, 5), (2, 3), (3, 2))
    AS contributor_row(contributor_number, unit_count)
  CROSS JOIN LATERAL generate_series(1, contributor_row.unit_count)
    AS unit_row(unit_number);
  INSERT INTO app_data.change_feed (
    app_user_id, workspace_id, project_id, aggregate_id, revision_number,
    change_type
  )
  VALUES
    ('6e110000-0000-4000-8000-000000000001'::uuid,
      '6e120000-0000-4000-8000-000000000001'::uuid,
      '6e130000-0000-4000-8000-000000000001'::uuid,
      '6aw-concurrent-watermark-one', 1, 'contact.submitted'),
    ('6e110000-0000-4000-8000-000000000001'::uuid,
      '6e120000-0000-4000-8000-000000000001'::uuid,
      '6e130000-0000-4000-8000-000000000002'::uuid,
      '6aw-concurrent-watermark-two', 1, 'contact.submitted');

  COMMIT;
" >/dev/null

same_first_output="${tmp_dir}/same-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.release_management_interest_report_snapshot_v1(
    '6e800000-0000-4000-8000-000000000001'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    '6e130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1);
  SELECT pg_advisory_lock(hashtextextended(
    'management-interest-release-same-request-6aw', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${same_first_output}" 2>&1 &
same_first_pid=$!
wait_ready 'management-interest-release-same-request-6aw' \
  "${same_first_pid}" "${same_first_output}"

same_second_output="${tmp_dir}/same-second.out"
run_psql --tuples-only --no-align --quiet --command="
  SELECT app_private.release_management_interest_report_snapshot_v1(
    '6e800000-0000-4000-8000-000000000001'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    '6e130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1)::text;
" >"${same_second_output}" 2>&1 &
same_second_pid=$!
first_status=0
second_status=0
wait "${same_first_pid}" || first_status=$?
wait "${same_second_pid}" || second_status=$?
if [[ "${first_status}" -ne 0 || "${second_status}" -ne 0 ]]; then
  cat "${same_first_output}" "${same_second_output}" >&2
  exit 1
fi

same_first_json="$(grep -E '^[{]' "${same_first_output}" | tail -n 1)"
same_second_json="$(grep -E '^[{]' "${same_second_output}" | tail -n 1)"
if [[ -z "${same_first_json}" || "${same_first_json}" != "${same_second_json}" ]]; then
  echo 'same-request concurrent interest releases did not return identical JSON.' >&2
  sed -n '1,100p' "${same_first_output}" >&2
  sed -n '1,100p' "${same_second_output}" >&2
  exit 1
fi

same_count="$(run_psql --tuples-only --no-align --command="
  SELECT (SELECT count(*) FROM app_private.management_report_snapshots
    WHERE project_id = '6e130000-0000-4000-8000-000000000001'::uuid
      AND release_lineage_id =
        'management-interest-report:contact_sessions_by_interest_level_two_periods')
    || '|' || (SELECT count(*) FROM
      app_private.management_interest_report_release_attempts
      WHERE project_id = '6e130000-0000-4000-8000-000000000001'::uuid);
" | tr -d '[:space:]')"
if [[ "${same_count}" != '1|1' ]]; then
  echo "same-request history 错误：${same_count}" >&2
  exit 1
fi

lineage_first_output="${tmp_dir}/lineage-first.out"
run_psql --command="
  BEGIN;
  SELECT app_private.release_management_interest_report_snapshot_v1(
    '6e800000-0000-4000-8000-000000000002'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    '6e130000-0000-4000-8000-000000000002'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1);
  SELECT pg_advisory_lock(hashtextextended(
    'management-interest-release-lineage-6aw', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${lineage_first_output}" 2>&1 &
lineage_first_pid=$!
wait_ready 'management-interest-release-lineage-6aw' \
  "${lineage_first_pid}" "${lineage_first_output}"

lineage_second_output="${tmp_dir}/lineage-second.out"
run_psql --command="
  SELECT app_private.release_management_interest_report_snapshot_v1(
    '6e800000-0000-4000-8000-000000000003'::uuid,
    '6e110000-0000-4000-8000-000000000001'::uuid,
    '6e130000-0000-4000-8000-000000000002'::uuid,
    'contact_sessions_by_interest_level_two_periods', 1);
" >"${lineage_second_output}" 2>&1 &
lineage_second_pid=$!
lineage_first_status=0
lineage_second_status=0
wait "${lineage_first_pid}" || lineage_first_status=$?
wait "${lineage_second_pid}" || lineage_second_status=$?
if [[ "${lineage_first_status}" -ne 0 || "${lineage_second_status}" -ne 0 ]]; then
  cat "${lineage_first_output}" "${lineage_second_output}" >&2
  exit 1
fi

lineage_check="$(run_psql --tuples-only --no-align --command="
  WITH attempts AS (
    SELECT release_request_id, result_status, compared_snapshot_id
    FROM app_private.management_interest_report_release_attempts
    WHERE project_id = '6e130000-0000-4000-8000-000000000002'::uuid
  ), snapshots AS (
    SELECT snapshot_id, release_request_id, previous_snapshot_id
    FROM app_private.management_report_snapshots
    WHERE project_id = '6e130000-0000-4000-8000-000000000002'::uuid
      AND release_lineage_id =
        'management-interest-report:contact_sessions_by_interest_level_two_periods'
  )
  SELECT (SELECT count(*) FROM attempts) || '|' || (SELECT count(*) FROM snapshots)
    || '|' || (SELECT count(*) FROM attempts WHERE result_status = 'approved_baseline')
    || '|' || (SELECT count(*) FROM attempts WHERE result_status = 'approved')
    || '|' || CASE WHEN
      (SELECT compared_snapshot_id FROM attempts WHERE release_request_id =
        '6e800000-0000-4000-8000-000000000003'::uuid) =
      (SELECT snapshot_id FROM snapshots WHERE release_request_id =
        '6e800000-0000-4000-8000-000000000002'::uuid)
      THEN 'previous-ok' ELSE 'previous-bad' END
    || '|' || CASE WHEN
      (SELECT previous_snapshot_id FROM snapshots WHERE release_request_id =
        '6e800000-0000-4000-8000-000000000003'::uuid) =
      (SELECT snapshot_id FROM snapshots WHERE release_request_id =
        '6e800000-0000-4000-8000-000000000002'::uuid)
      THEN 'pointer-ok' ELSE 'pointer-bad' END;
" | tr -d '[:space:]')"
if [[ "${lineage_check}" != '2|2|1|1|previous-ok|pointer-ok' ]]; then
  echo "interest lineage history 错误：${lineage_check}" >&2
  exit 1
fi

echo '6AW release concurrency check passed: same-request idempotency and single-baseline previous-pointer serialization hold.'
