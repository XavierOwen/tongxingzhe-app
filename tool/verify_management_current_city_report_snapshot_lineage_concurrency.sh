#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo '请设置 DATABASE_URL。' >&2
  exit 1
fi

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "$psql_command" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c statement_timeout=30000 -c lock_timeout=15000"
run_psql() {
  "$psql_command" "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}
tmp_dir="$(mktemp -d)"
same_first_pid=''
same_second_pid=''
lineage_first_pid=''
lineage_second_pid=''

cleanup() {
  for pid in "$same_first_pid" "$same_second_pid" "$lineage_first_pid" "$lineage_second_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "$pid" ]]; then
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done
  rm -f "$tmp_dir"/*.out
  rmdir "$tmp_dir"
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
        SELECT (hashtextextended('$lock_name', 0) >> 32)
          & 4294967295 AS classid,
          hashtextextended('$lock_name', 0) & 4294967295 AS objid
      )
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND lock_row.granted
          AND lock_row.pid <> pg_backend_pid()
      );
    " | tr -d '[:space:]')"
    if [[ "$held" == t ]]; then
      return
    fi
    sleep 0.1
  done
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  sed -n '1,160p' "$output" >&2
  echo "没有观察到并发 ready lock：$lock_name" >&2
  exit 1
}

# ac* is reserved here for the committed setup. The two projects avoid
# turning the second pair of requests into a replay of the first baseline.
run_psql --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES ('ac100000-0000-4000-8000-000000000001'::uuid, 'active');
  INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
  VALUES ('ac200000-0000-4000-8000-000000000001'::uuid, 'organization',
    '6AO release concurrency workspace');
  INSERT INTO app_data.projects (project_id, workspace_id, display_name)
  VALUES
    ('ac300000-0000-4000-8000-000000000001'::uuid,
      'ac200000-0000-4000-8000-000000000001'::uuid, '6AO same request'),
    ('ac300000-0000-4000-8000-000000000002'::uuid,
      'ac200000-0000-4000-8000-000000000001'::uuid, '6AO double baseline');
  INSERT INTO app_data.questionnaire_versions
    (questionnaire_version_id, project_id, version_number, status, is_current)
  VALUES
    ('ac700000-0000-4000-8000-000000000001'::uuid,
      'ac300000-0000-4000-8000-000000000001'::uuid, 1, 'published', true),
    ('ac700000-0000-4000-8000-000000000002'::uuid,
      'ac300000-0000-4000-8000-000000000002'::uuid, 1, 'published', true);
  INSERT INTO app_data.organization_memberships
    (organization_membership_id, organization_workspace_id, app_user_id,
      active_from_utc, inactive_from_utc)
  VALUES ('ac400000-0000-4000-8000-000000000001'::uuid,
    'ac200000-0000-4000-8000-000000000001'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL);
  INSERT INTO app_data.project_memberships
    (project_membership_id, organization_membership_id, project_id,
      active_from_utc, inactive_from_utc)
  VALUES
    ('ac500000-0000-4000-8000-000000000001'::uuid,
      'ac400000-0000-4000-8000-000000000001'::uuid,
      'ac300000-0000-4000-8000-000000000001'::uuid,
      clock_timestamp() - interval '30 days', NULL),
    ('ac500000-0000-4000-8000-000000000002'::uuid,
      'ac400000-0000-4000-8000-000000000001'::uuid,
      'ac300000-0000-4000-8000-000000000002'::uuid,
      clock_timestamp() - interval '30 days', NULL);
  INSERT INTO app_data.management_report_capability_grants
    (capability_grant_id, project_membership_id, capability_id,
      active_from_utc, inactive_from_utc)
  VALUES
    ('ac600000-0000-4000-8000-000000000001'::uuid,
      'ac500000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports', clock_timestamp() - interval '30 days', NULL),
    ('ac600000-0000-4000-8000-000000000002'::uuid,
      'ac500000-0000-4000-8000-000000000002'::uuid,
      'release_management_reports', clock_timestamp() - interval '30 days', NULL);
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'ac900000-0000-4000-8000-000000000001'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    'ac300000-0000-4000-8000-000000000001'::uuid, 0, 'UTC',
    clock_timestamp() - interval '30 days');
  SELECT app_private.configure_project_reporting_time_zone_v1(
    'ac900000-0000-4000-8000-000000000002'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    'ac300000-0000-4000-8000-000000000002'::uuid, 0, 'UTC',
    clock_timestamp() - interval '30 days');
  INSERT INTO app_data.canonical_region_tree_releases
    (tree_version, lifecycle_state, is_current)
  VALUES ('concurrent-6ao-current-city-v1', 'draft', false);
  INSERT INTO app_data.canonical_region_versions
    (region_id, tree_version, parent_region_id, canonical_name, kind)
  VALUES
    ('concurrent-6ao-country', 'concurrent-6ao-current-city-v1', NULL,
      '6AO Country', 'country'),
    ('concurrent-6ao-city', 'concurrent-6ao-current-city-v1',
      'concurrent-6ao-country', '6AO City', 'city'),
    ('concurrent-6ao-venue', 'concurrent-6ao-current-city-v1',
      'concurrent-6ao-city', '6AO Venue', 'venue');
  INSERT INTO app_data.canonical_region_boundaries
    (boundary_id, region_id, tree_version, boundary)
  VALUES (
    'concurrent-6ao-boundary', 'concurrent-6ao-venue',
    'concurrent-6ao-current-city-v1',
    polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'
  );
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-6ao-current-city-v1', true);
" >/dev/null

same_first_output="$tmp_dir/same-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.release_management_current_city_report_snapshot_v1(
    'ac800000-0000-4000-8000-000000000001'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    'ac300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods', 1);
  SELECT pg_advisory_lock(hashtextextended(
    'management-current-city-release-same-request-6ao', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"$same_first_output" 2>&1 &
same_first_pid=$!
wait_ready 'management-current-city-release-same-request-6ao' \
  "$same_first_pid" "$same_first_output"

same_second_output="$tmp_dir/same-second.out"
run_psql --tuples-only --no-align --quiet --command="
  SELECT app_private.release_management_current_city_report_snapshot_v1(
    'ac800000-0000-4000-8000-000000000001'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    'ac300000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods', 1)::text;
" >"$same_second_output" 2>&1 &
same_second_pid=$!
first_status=0
second_status=0
wait "$same_first_pid" || first_status=$?
wait "$same_second_pid" || second_status=$?
if [[ "$first_status" -ne 0 || "$second_status" -ne 0 ]]; then
  cat "$same_first_output" "$same_second_output" >&2
  exit 1
fi

same_first_json="$(grep -E '^[{]' "$same_first_output" | tail -n 1)"
same_second_json="$(grep -E '^[{]' "$same_second_output" | tail -n 1)"
if [[ -z "$same_first_json" || "$same_first_json" != "$same_second_json" ]]; then
  echo 'same-request concurrent releases did not return identical JSON.' >&2
  sed -n '1,80p' "$same_first_output" >&2
  sed -n '1,80p' "$same_second_output" >&2
  exit 1
fi

same_count="$(run_psql --tuples-only --no-align --command="
  SELECT (SELECT count(*) FROM app_private.management_report_snapshots
    WHERE project_id = 'ac300000-0000-4000-8000-000000000001'::uuid)
    || '|' || (SELECT count(*) FROM
      app_private.management_current_city_report_release_attempts
      WHERE project_id = 'ac300000-0000-4000-8000-000000000001'::uuid);
" | tr -d '[:space:]')"
if [[ "$same_count" != '1|1' ]]; then
  echo "same-request history 错误：$same_count" >&2
  exit 1
fi

lineage_first_output="$tmp_dir/lineage-first.out"
run_psql --command="
  BEGIN;
  SELECT app_private.release_management_current_city_report_snapshot_v1(
    'ac800000-0000-4000-8000-000000000002'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    'ac300000-0000-4000-8000-000000000002'::uuid,
    'contact_sessions_by_current_city_two_periods', 1);
  SELECT pg_advisory_lock(hashtextextended(
    'management-current-city-release-lineage-6ao', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"$lineage_first_output" 2>&1 &
lineage_first_pid=$!
wait_ready 'management-current-city-release-lineage-6ao' \
  "$lineage_first_pid" "$lineage_first_output"

lineage_second_output="$tmp_dir/lineage-second.out"
run_psql --command="
  SELECT app_private.release_management_current_city_report_snapshot_v1(
    'ac800000-0000-4000-8000-000000000003'::uuid,
    'ac100000-0000-4000-8000-000000000001'::uuid,
    'ac300000-0000-4000-8000-000000000002'::uuid,
    'contact_sessions_by_current_city_two_periods', 1);
" >"$lineage_second_output" 2>&1 &
lineage_second_pid=$!
lineage_first_status=0
lineage_second_status=0
wait "$lineage_first_pid" || lineage_first_status=$?
wait "$lineage_second_pid" || lineage_second_status=$?
if [[ "$lineage_first_status" -ne 0 || "$lineage_second_status" -ne 0 ]]; then
  cat "$lineage_first_output" "$lineage_second_output" >&2
  exit 1
fi

lineage_check="$(run_psql --tuples-only --no-align --command="
  WITH a AS (
    SELECT release_request_id, result_status, compared_snapshot_id
    FROM app_private.management_current_city_report_release_attempts
    WHERE project_id = 'ac300000-0000-4000-8000-000000000002'::uuid
  ), s AS (
    SELECT snapshot_id, release_request_id, previous_snapshot_id
    FROM app_private.management_report_snapshots
    WHERE project_id = 'ac300000-0000-4000-8000-000000000002'::uuid
  )
  SELECT (SELECT count(*) FROM a) || '|' || (SELECT count(*) FROM s)
    || '|' || (SELECT count(*) FROM a WHERE result_status = 'approved_baseline')
    || '|' || (SELECT count(*) FROM a WHERE result_status = 'approved')
    || '|' || CASE WHEN
      (SELECT compared_snapshot_id FROM a WHERE release_request_id =
        'ac800000-0000-4000-8000-000000000003'::uuid) =
      (SELECT snapshot_id FROM s WHERE release_request_id =
        'ac800000-0000-4000-8000-000000000002'::uuid)
      THEN 'previous-ok' ELSE 'previous-bad' END
    || '|' || CASE WHEN
      (SELECT previous_snapshot_id FROM s WHERE release_request_id =
        'ac800000-0000-4000-8000-000000000003'::uuid) =
      (SELECT snapshot_id FROM s WHERE release_request_id =
        'ac800000-0000-4000-8000-000000000002'::uuid)
      THEN 'pointer-ok' ELSE 'pointer-bad' END;
" | tr -d '[:space:]')"
if [[ "$lineage_check" != '2|2|1|1|previous-ok|pointer-ok' ]]; then
  echo "lineage history 错误：$lineage_check" >&2
  exit 1
fi

echo '6AO release concurrency check passed: same-request idempotency and single-baseline previous-pointer serialization hold.'
