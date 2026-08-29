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

temporary_directory="$(mktemp -d)"
read_first_pid=''
revoke_first_pid=''
revoke_second_pid=''
read_second_pid=''

cleanup() {
  for pid in \
    "${read_first_pid}" \
    "${revoke_first_pid}" \
    "${revoke_second_pid}" \
    "${read_second_pid}"; do
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
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  exit 1
}

# All rows are committed on purpose: independent psql sessions must observe
# the same approved current-city snapshot.  The ae* namespace is unique to
# this script and does not depend on rollback fixtures.
run_psql <<'SQL'
BEGIN;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('ae110000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('ae110000-0000-4000-8000-000000000002'::uuid, 'active');

INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
VALUES (
  'ae120000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6AP read concurrency workspace'
);

INSERT INTO app_data.projects (project_id, workspace_id, display_name)
VALUES (
  'ae130000-0000-4000-8000-000000000001'::uuid,
  'ae120000-0000-4000-8000-000000000001'::uuid,
  '6AP read concurrency project'
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES (
  'ae140000-0000-4000-8000-000000000001'::uuid,
  'ae130000-0000-4000-8000-000000000001'::uuid,
  1, 'published', true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    'ae160000-0000-4000-8000-000000000001'::uuid,
    'ae120000-0000-4000-8000-000000000001'::uuid,
    'ae110000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ae160000-0000-4000-8000-000000000002'::uuid,
    'ae120000-0000-4000-8000-000000000001'::uuid,
    'ae110000-0000-4000-8000-000000000002'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  'ae1a0000-0000-4000-8000-000000000001'::uuid,
  'ae160000-0000-4000-8000-000000000001'::uuid,
  transaction_timestamp(),
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    'ae170000-0000-4000-8000-000000000001'::uuid,
    'ae160000-0000-4000-8000-000000000001'::uuid,
    'ae130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ae170000-0000-4000-8000-000000000002'::uuid,
    'ae160000-0000-4000-8000-000000000002'::uuid,
    'ae130000-0000-4000-8000-000000000001'::uuid,
    clock_timestamp() - interval '30 days', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
)
VALUES
  (
    'ae180000-0000-4000-8000-000000000001'::uuid,
    'ae170000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    clock_timestamp() - interval '30 days', NULL
  ),
  (
    'ae180000-0000-4000-8000-000000000002'::uuid,
    'ae170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics',
    clock_timestamp() - interval '30 days', NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  'ae150000-0000-4000-8000-000000000001'::uuid,
  'ae110000-0000-4000-8000-000000000001'::uuid,
  'ae130000-0000-4000-8000-000000000001'::uuid,
  0, 'UTC', clock_timestamp() - interval '30 days'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current
) VALUES ('fixture-6ap-concurrency-v1', 'draft', false);

INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
)
VALUES
  ('fixture-6ap-concurrency-country', 'fixture-6ap-concurrency-v1', NULL,
    '6AP Concurrency Country', 'country'),
  ('fixture-6ap-concurrency-city', 'fixture-6ap-concurrency-v1',
    'fixture-6ap-concurrency-country', '6AP Concurrency City', 'city'),
  ('fixture-6ap-concurrency-venue', 'fixture-6ap-concurrency-v1',
    'fixture-6ap-concurrency-city', '6AP Concurrency Venue', 'venue');

INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
)
VALUES (
  'fixture-6ap-concurrency-boundary',
  'fixture-6ap-concurrency-venue',
  'fixture-6ap-concurrency-v1',
  polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
);

SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6ap-concurrency-v1', true
);

CREATE TEMP TABLE fixture_6ap_concurrency_context AS
WITH captured AS (
  SELECT clock_timestamp() AS data_cutoff_utc
)
SELECT
  captured.data_cutoff_utc,
  app_private.resolve_management_report_periods_v1(
    'UTC', captured.data_cutoff_utc
  ) AS periods
FROM captured;

CREATE TEMP TABLE fixture_6ap_concurrency_contacts AS
SELECT
  format('fixture-6ap-concurrency-%s-%s', period_row.period_key, number) AS contact_id,
  period_row.period_key,
  CASE WHEN number <= 5 THEN 1 WHEN number <= 8 THEN 2 ELSE 3 END AS contributor_number,
  CASE period_row.period_key
    WHEN 'previous' THEN
      (context.periods->'previous_period'->>'start_utc')::timestamptz
        + interval '1 day'
    ELSE
      (context.periods->'current_period'->>'start_utc')::timestamptz
        + interval '1 day'
  END AS occurred_at_utc
FROM fixture_6ap_concurrency_context AS context
CROSS JOIN (VALUES ('previous'), ('current')) AS period_row(period_key)
CROSS JOIN generate_series(1, 10) AS series(number);

INSERT INTO app_data.contacts (
  contact_id, app_user_id, workspace_id, project_id,
  questionnaire_version_id, occurred_at_utc, occurred_time_zone,
  first_submitted_at_utc, channel, location_kind, place_name,
  smallest_region_id, region_tree_version, reach_count, interest_level
)
SELECT
  contact.contact_id,
  CASE contact.contributor_number
    WHEN 1 THEN 'ae110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN 'ae110000-0000-4000-8000-000000000002'::uuid
    ELSE 'ae110000-0000-4000-8000-000000000001'::uuid
  END,
  'ae120000-0000-4000-8000-000000000001'::uuid,
  'ae130000-0000-4000-8000-000000000001'::uuid,
  'ae140000-0000-4000-8000-000000000001'::uuid,
  contact.occurred_at_utc, 'UTC', contact.occurred_at_utc,
  'face_to_face', 'resolved', '6AP concurrency venue',
  'fixture-6ap-concurrency-venue', 'fixture-6ap-concurrency-v1', 1, 2
FROM fixture_6ap_concurrency_contacts AS contact;

INSERT INTO app_data.contact_revisions (
  contact_id, revision_number, revision_kind, revised_by_app_user_id, snapshot
)
SELECT
  contact.contact_id, 1, 'submitted',
  CASE contact.contributor_number
    WHEN 1 THEN 'ae110000-0000-4000-8000-000000000001'::uuid
    WHEN 2 THEN 'ae110000-0000-4000-8000-000000000002'::uuid
    ELSE 'ae110000-0000-4000-8000-000000000001'::uuid
  END,
  jsonb_build_object(
    'contactId', contact.contact_id,
    'location', jsonb_build_object(
      'kind', 'resolved', 'placeName', '6AP concurrency venue',
      'smallestRegionId', 'fixture-6ap-concurrency-venue',
      'regionTreeVersion', 'fixture-6ap-concurrency-v1'
    )
  )
FROM fixture_6ap_concurrency_contacts AS contact;

INSERT INTO app_data.change_feed (
  app_user_id, workspace_id, project_id, aggregate_id, revision_number,
  change_type
)
VALUES (
  'ae110000-0000-4000-8000-000000000001'::uuid,
  'ae120000-0000-4000-8000-000000000001'::uuid,
  'ae130000-0000-4000-8000-000000000001'::uuid,
  'fixture-6ap-concurrency-watermark', 1, 'contact.submitted'
);
COMMIT;
SQL

snapshot_id="$(run_psql --tuples-only --no-align --command="
  SELECT (app_private.release_management_current_city_report_snapshot_v1(
    'ae190000-0000-4000-8000-000000000001'::uuid,
    'ae110000-0000-4000-8000-000000000001'::uuid,
    'ae130000-0000-4000-8000-000000000001'::uuid,
    'contact_sessions_by_current_city_two_periods', 1
  )->>'released_snapshot_id');
" | tr -d '[:space:]')"

if [[ ! "${snapshot_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "current-city 并发 fixture 没有生成 snapshot：${snapshot_id}" >&2
  exit 1
fi

capability_lock="management-report-capability:ae130000-0000-4000-8000-000000000001:ae110000-0000-4000-8000-000000000002:view_anonymous_analytics"

# Read-first: the read owns the capability lock until commit, so revocation
# waits and the completed read is a valid pre-revocation observation.
read_first_ready='management-current-city-read-first-6ap'
read_first_output="${temporary_directory}/read-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.read_authorized_management_current_city_report_snapshot_v1(
    'ae110000-0000-4000-8000-000000000002'::uuid,
    'ae130000-0000-4000-8000-000000000001'::uuid,
    '${snapshot_id}'::uuid
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
    'ae180000-0000-4000-8000-000000000002'::uuid;
  COMMIT;
" >"${revoke_first_output}" 2>&1 &
revoke_first_pid=$!
sleep 0.3
if ! kill -0 "${revoke_first_pid}" >/dev/null 2>&1; then
  wait "${revoke_first_pid}" >/dev/null 2>&1 || true
  echo "revoke-first 没有等待 read-first 的 capability lock：${capability_lock}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  exit 1
fi

read_first_status=0
revoke_first_status=0
wait "${read_first_pid}" || read_first_status=$?
wait "${revoke_first_pid}" || revoke_first_status=$?
if [[ "${read_first_status}" -ne 0 || "${revoke_first_status}" -ne 0 ]] \
  || ! grep -Eq '"result_status"[[:space:]]*:[[:space:]]*"completed"' \
    "${read_first_output}"; then
  echo 'read-first / revoke-first 并发合同失败。' >&2
  sed -n '1,160p' "${read_first_output}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  exit 1
fi

# A new grant makes the reverse ordering independent from the first round.
run_psql --command="
  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id,
    active_from_utc, inactive_from_utc
  ) VALUES (
    'ae180000-0000-4000-8000-000000000003'::uuid,
    'ae170000-0000-4000-8000-000000000002'::uuid,
    'view_anonymous_analytics', clock_timestamp(), NULL
  );
" >/dev/null

# Revoke-first: the revocation owns the capability lock before the reader
# starts.  The reader must wait, then fail closed after the revocation commit.
revoke_second_ready='management-current-city-revoke-first-6ap'
revoke_second_output="${temporary_directory}/revoke-second.out"
run_psql --command="
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id =
    'ae180000-0000-4000-8000-000000000003'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revoke_second_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${revoke_second_output}" 2>&1 &
revoke_second_pid=$!
wait_for_ready_lock "${revoke_second_ready}" \
  "${revoke_second_pid}" "${revoke_second_output}"

read_second_output="${temporary_directory}/read-second.out"
run_psql --command="
  SELECT app_private.read_authorized_management_current_city_report_snapshot_v1(
    'ae110000-0000-4000-8000-000000000002'::uuid,
    'ae130000-0000-4000-8000-000000000001'::uuid,
    '${snapshot_id}'::uuid
  );
" >"${read_second_output}" 2>&1 &
read_second_pid=$!
sleep 0.3
if ! kill -0 "${read_second_pid}" >/dev/null 2>&1; then
  wait "${read_second_pid}" >/dev/null 2>&1 || true
  echo 'read-second 没有等待 revoke-first 的 capability lock。' >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi

revoke_second_status=0
read_second_status=0
wait "${revoke_second_pid}" || revoke_second_status=$?
wait "${read_second_pid}" || read_second_status=$?
if [[ "${revoke_second_status}" -ne 0 \
  || "${read_second_status}" -eq 0 ]]; then
  echo 'revoke-first / read-second 并发合同失败。' >&2
  sed -n '1,160p' "${revoke_second_output}" >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${read_second_output}"; then
  echo 'read-second 没有因撤权失败关闭。' >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi

audit_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_current_city_report_snapshot_access_events
  WHERE project_id =
    'ae130000-0000-4000-8000-000000000001'::uuid;
" | tr -d '[:space:]')"
if [[ "${audit_count}" != '1' ]]; then
  echo "撤权后不应追加访问审计：${audit_count}" >&2
  exit 1
fi

echo '6AP current-city snapshot read concurrency passed: read/revocation ordering fails closed after the lock linearization point.'
