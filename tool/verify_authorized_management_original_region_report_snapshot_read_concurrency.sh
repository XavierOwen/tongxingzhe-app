#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c statement_timeout=30000 -c lock_timeout=15000"
run_psql() {
  "${psql_command}" "${DATABASE_URL}" \
    --no-psqlrc --set=ON_ERROR_STOP=1 "$@"
}

temporary_directory="$(mktemp -d)"
read_first_pid=''
revoke_first_pid=''
read_second_pid=''
revoke_second_pid=''

cleanup() {
  for pid in \
    "${read_first_pid}" "${revoke_first_pid}" \
    "${read_second_pid}" "${revoke_second_pid}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_ready_lock() {
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
  echo "没有观察到 6BH 并发 ready lock：${lock_name}" >&2
  exit 1
}

wait_for_waiting_lock() {
  local lock_name="$1"
  local pid="$2"
  local output="$3"
  local waiting

  for _ in $(seq 1 100); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      wait "${pid}" >/dev/null 2>&1 || true
      sed -n '1,160p' "${output}" >&2
      echo "没有观察到 6BH read 等待授权锁：${lock_name}" >&2
      exit 1
    fi
    waiting="$(run_psql --tuples-only --no-align --command="
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
          AND NOT lock_row.granted
          AND lock_row.pid <> pg_backend_pid()
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
  sed -n '1,160p' "${output}" >&2
  echo "没有观察到 6BH read 等待授权锁：${lock_name}" >&2
  exit 1
}

# This namespace is committed on purpose: the two independent psql sessions
# need to observe one common snapshot.  It is separate from the 6BH rollback
# fixture and from all earlier 6AP/6AX/6AO concurrency namespaces.
run_psql <<'SQL'
BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6fc10000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6fc10000-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6fc10000-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
VALUES (
  '6fc20000-0000-4000-8000-000000000001'::uuid,
  'organization', '6BH original-region read concurrency workspace'
);
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES (
  '6fc30000-0000-4000-8000-000000000001'::uuid,
  '6fc20000-0000-4000-8000-000000000001'::uuid,
  '6BH original-region read concurrency project'
);
INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
) VALUES (
  '6fc40000-0000-4000-8000-000000000001'::uuid,
  '6fc30000-0000-4000-8000-000000000001'::uuid,
  1, 'published', true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6fc60000-0000-4000-8000-000000000001'::uuid,
    '6fc20000-0000-4000-8000-000000000001'::uuid,
    '6fc10000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6fc60000-0000-4000-8000-000000000002'::uuid,
    '6fc20000-0000-4000-8000-000000000001'::uuid,
    '6fc10000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6fc60000-0000-4000-8000-000000000003'::uuid,
    '6fc20000-0000-4000-8000-000000000001'::uuid,
    '6fc10000-0000-4000-8000-000000000003'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '6fca0000-0000-4000-8000-000000000001'::uuid,
  '6fc60000-0000-4000-8000-000000000001'::uuid,
  transaction_timestamp(),
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6fc70000-0000-4000-8000-000000000001'::uuid,
    '6fc60000-0000-4000-8000-000000000001'::uuid,
    '6fc30000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6fc70000-0000-4000-8000-000000000002'::uuid,
    '6fc60000-0000-4000-8000-000000000002'::uuid,
    '6fc30000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6fc70000-0000-4000-8000-000000000003'::uuid,
    '6fc60000-0000-4000-8000-000000000003'::uuid,
    '6fc30000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );
INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    '6fc80000-0000-4000-8000-000000000001'::uuid,
    '6fc70000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6fc80000-0000-4000-8000-000000000002'::uuid,
    '6fc70000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days', NULL
  ),
  (
    '6fc80000-0000-4000-8000-000000000003'::uuid,
    '6fc70000-0000-4000-8000-000000000003'::uuid,
    'view_anonymous_analytics', clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6fc50000-0000-4000-8000-000000000001'::uuid,
  '6fc10000-0000-4000-8000-000000000001'::uuid,
  '6fc30000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('fixture-6bhc-original-v1', 'draft', false);
INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6bhc-country', 'fixture-6bhc-original-v1', NULL,
    '6BH Concurrency Country', 'country'),
  ('fixture-6bhc-city-a', 'fixture-6bhc-original-v1',
    'fixture-6bhc-country', '6BH Concurrency City A', 'city'),
  ('fixture-6bhc-city-b', 'fixture-6bhc-original-v1',
    'fixture-6bhc-country', '6BH Concurrency City B', 'city'),
  ('fixture-6bhc-city-c', 'fixture-6bhc-original-v1',
    'fixture-6bhc-country', '6BH Concurrency City C', 'city'),
  ('fixture-6bhc-venue-a', 'fixture-6bhc-original-v1',
    'fixture-6bhc-city-a', '6BH Concurrency Venue A', 'venue'),
  ('fixture-6bhc-venue-b', 'fixture-6bhc-original-v1',
    'fixture-6bhc-city-b', '6BH Concurrency Venue B', 'venue'),
  ('fixture-6bhc-venue-c', 'fixture-6bhc-original-v1',
    'fixture-6bhc-city-c', '6BH Concurrency Venue C', 'venue');
INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES
  ('fixture-6bhc-boundary-a', 'fixture-6bhc-venue-a',
    'fixture-6bhc-original-v1', polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'),
  ('fixture-6bhc-boundary-b', 'fixture-6bhc-venue-b',
    'fixture-6bhc-original-v1', polygon '((-87.90,41.60),(-87.80,41.60),(-87.80,41.70),(-87.90,41.70))'),
  ('fixture-6bhc-boundary-c', 'fixture-6bhc-venue-c',
    'fixture-6bhc-original-v1', polygon '((-87.80,41.60),(-87.70,41.60),(-87.70,41.70),(-87.80,41.70))');
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bhc-original-v1', false
);

CREATE TEMP TABLE fixture_6bhc_context AS
WITH captured AS (SELECT clock_timestamp() AS data_cutoff_utc)
SELECT captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, place_name,
  smallest_region_id, region_tree_version, reach_count, interest_level
)
SELECT
  format('fixture-6bhc-%s-%s-%s', period_row.period_key, city_row.city_key, number),
  CASE WHEN number <= 5
    THEN '6fc10000-0000-4000-8000-000000000001'::uuid
    WHEN number <= 8
    THEN '6fc10000-0000-4000-8000-000000000002'::uuid
    ELSE '6fc10000-0000-4000-8000-000000000003'::uuid END,
  '6fc20000-0000-4000-8000-000000000001'::uuid,
  '6fc30000-0000-4000-8000-000000000001'::uuid,
  '6fc40000-0000-4000-8000-000000000001'::uuid,
  CASE period_row.period_key WHEN 'previous'
    THEN (context.periods->'previous_period'->>'start_utc')::timestamptz
      + interval '1 minute'
    ELSE (context.periods->'current_period'->>'start_utc')::timestamptz
      + interval '1 minute' END,
  'UTC', clock_timestamp(), 'face_to_face', 'resolved',
  '6BH concurrency venue',
  format('fixture-6bhc-venue-%s', city_row.city_key),
  'fixture-6bhc-original-v1', 1, 2
FROM fixture_6bhc_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN (VALUES ('a'), ('b'), ('c')) AS city_row(city_key)
CROSS JOIN generate_series(1, 10) AS series(number);

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
)
SELECT
  contact.contact_id, 1, 'submitted', contact.app_user_id,
  jsonb_build_object(
    'contactId', contact.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved', 'placeName', '6BH concurrency venue',
      'smallestRegionId', contact.smallest_region_id,
      'regionTreeVersion', 'fixture-6bhc-original-v1'
    )
  )
FROM app_data.contacts AS contact
WHERE contact.contact_id LIKE 'fixture-6bhc-%';
INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
) VALUES (
  '6fc10000-0000-4000-8000-000000000001'::uuid,
  '6fc20000-0000-4000-8000-000000000001'::uuid,
  '6fc30000-0000-4000-8000-000000000001'::uuid,
  'fixture-6bhc-original-watermark', 1, 'contact.submitted'
);
COMMIT;
SQL

snapshot_id="$(run_psql --tuples-only --no-align --command="
  SELECT (app_private.release_management_original_region_report_snapshot_v1(
    '6fc90000-0000-4000-8000-000000000001'::uuid,
    '6fc10000-0000-4000-8000-000000000001'::uuid,
    '6fc30000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_original_region_two_periods', 1
  )->>'released_snapshot_id');
" | tr -d '[:space:]')"
if [[ ! "${snapshot_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "6BH original-region concurrency fixture did not create a snapshot: ${snapshot_id}" >&2
  exit 1
fi

project_id='6fc30000-0000-4000-8000-000000000001'
viewer_two='6fc10000-0000-4000-8000-000000000002'
viewer_three='6fc10000-0000-4000-8000-000000000003'
capability_lock_two="management-report-capability:${project_id}:${viewer_two}:view_anonymous_analytics"
capability_lock_three="management-report-capability:${project_id}:${viewer_three}:view_anonymous_analytics"
organization_lock_two="organization-membership:6fc20000-0000-4000-8000-000000000001:${viewer_two}"
organization_lock_three="organization-membership:6fc20000-0000-4000-8000-000000000001:${viewer_three}"

# Read-first: the completed read owns all authorization locks until commit;
# revocation must wait and therefore occurs after this valid observation.
read_first_ready='management-original-region-read-first-6bh'
read_first_output="${temporary_directory}/read-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.read_authorized_management_original_region_report_snapshot_v1(
    '${viewer_two}'::uuid, '${project_id}'::uuid, '${snapshot_id}'::uuid
  );
  SELECT pg_advisory_lock(hashtextextended('${read_first_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${read_first_output}" 2>&1 &
read_first_pid=$!
wait_for_ready_lock "${read_first_ready}" "${read_first_pid}" "${read_first_output}"

revoke_first_output="${temporary_directory}/revoke-first.out"
run_psql --command="
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '6fc80000-0000-4000-8000-000000000002'::uuid;
  COMMIT;
" >"${revoke_first_output}" 2>&1 &
revoke_first_pid=$!
wait_for_waiting_lock "${organization_lock_two}" \
  "${revoke_first_pid}" "${revoke_first_output}"

read_first_status=0
revoke_first_status=0
wait "${read_first_pid}" || read_first_status=$?
wait "${revoke_first_pid}" || revoke_first_status=$?
if [[ "${read_first_status}" -ne 0 || "${revoke_first_status}" -ne 0 ]] \
  || ! grep -Eq '"result_status"[[:space:]]*:[[:space:]]*"completed"' \
    "${read_first_output}"; then
  echo '6BH read-first/revoke-first concurrency failed.' >&2
  sed -n '1,160p' "${read_first_output}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  exit 1
fi

# Revoke-first: hold the exact resolver lock before changing the capability.
# The reader must wait, then observe the committed inactive boundary and fail
# closed without appending an access audit.
revoke_second_ready='management-original-region-revoke-first-6bh'
revoke_second_output="${temporary_directory}/revoke-second.out"
run_psql --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    'organization-membership:6fc20000-0000-4000-8000-000000000001:${viewer_three}', 0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    'project-membership:${project_id}:${viewer_three}', 0
  ));
  SELECT pg_advisory_xact_lock(hashtextextended(
    '${capability_lock_three}', 0
  ));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    '6fc80000-0000-4000-8000-000000000003'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revoke_second_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${revoke_second_output}" 2>&1 &
revoke_second_pid=$!
wait_for_ready_lock "${revoke_second_ready}" \
  "${revoke_second_pid}" "${revoke_second_output}"

read_second_output="${temporary_directory}/read-second.out"
run_psql --command="
  SELECT app_private.read_authorized_management_original_region_report_snapshot_v1(
    '${viewer_three}'::uuid, '${project_id}'::uuid, '${snapshot_id}'::uuid
  );
" >"${read_second_output}" 2>&1 &
read_second_pid=$!
wait_for_waiting_lock "${organization_lock_three}" \
  "${read_second_pid}" "${read_second_output}"

revoke_second_status=0
read_second_status=0
wait "${revoke_second_pid}" || revoke_second_status=$?
wait "${read_second_pid}" || read_second_status=$?
if [[ "${revoke_second_status}" -ne 0 || "${read_second_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' "${read_second_output}"; then
  echo '6BH revoke-first/read-second concurrency failed.' >&2
  sed -n '1,160p' "${revoke_second_output}" >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi

audit_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_original_region_report_snapshot_access_events
  WHERE project_id = '${project_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${audit_count}" != '1' ]]; then
  echo "6BH revoke-first must not append an audit event: ${audit_count}" >&2
  exit 1
fi

echo '6BH original-region snapshot read concurrency passed: read/revocation ordering is linearized by the authorization locks.'
