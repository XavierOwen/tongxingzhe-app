#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 DATABASE_URL。}"
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
same_first_pid=''
same_second_pid=''
lineage_first_pid=''
lineage_second_pid=''
auth_release_pid=''
auth_revoke_pid=''
revoke_first_pid=''
revoke_release_pid=''

cleanup() {
  local child_pid
  for child_pid in \
    "${same_first_pid}" "${same_second_pid}" \
    "${lineage_first_pid}" "${lineage_second_pid}" \
    "${auth_release_pid}" "${auth_revoke_pid}" \
    "${revoke_first_pid}" "${revoke_release_pid}"
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

wait_for_lock_holder() {
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
        SELECT 1 FROM pg_locks AS lock_row JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory' AND lock_row.granted
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

wait_for_lock_waiter() {
  local lock_name="$1"
  local output="$2"
  local waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT (hashtextextended('${lock_name}', 0) >> 32)
          & 4294967295 AS classid,
          hashtextextended('${lock_name}', 0) & 4294967295 AS objid
      )
      SELECT EXISTS (
        SELECT 1 FROM pg_locks AS lock_row JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory' AND NOT lock_row.granted
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done
  sed -n '1,160p' "${output}" >&2
  echo "没有观察到并发 waiter：${lock_name}" >&2
  exit 1
}

wait_for_query_waiter() {
  local query_fragment="$1"
  local output="$2"
  local waiting
  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1
        FROM pg_stat_activity AS activity
        WHERE activity.pid <> pg_backend_pid()
          AND activity.state = 'active'
          AND activity.wait_event_type = 'Lock'
          AND position('${query_fragment}' IN activity.query) > 0
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done
  sed -n '1,160p' "${output}" >&2
  echo "没有观察到并发 SQL waiter：${query_fragment}" >&2
  exit 1
}

workspace_id='6bc20000-0000-4000-8000-000000000001'
user_one='6bc10000-0000-4000-8000-000000000001'
user_two='6bc10000-0000-4000-8000-000000000002'
user_three='6bc10000-0000-4000-8000-000000000003'
project_one='6bc30000-0000-4000-8000-000000000001'
project_two='6bc30000-0000-4000-8000-000000000002'
questionnaire_one='6bc40000-0000-4000-8000-000000000001'
questionnaire_two='6bc40000-0000-4000-8000-000000000002'
membership_id='6bc60000-0000-4000-8000-000000000001'
project_membership_one='6bc70000-0000-4000-8000-000000000001'
project_membership_two='6bc70000-0000-4000-8000-000000000002'
capability_one='6bc80000-0000-4000-8000-000000000001'
capability_two='6bc80000-0000-4000-8000-000000000002'
time_zone_one='6bc50000-0000-4000-8000-000000000001'
time_zone_two='6bc50000-0000-4000-8000-000000000002'
report_id='contact_sessions_by_original_region_two_periods'
lineage_id='management-original-region-report:contact_sessions_by_original_region_two_periods'

echo '建立 6BG concurrency synthetic original-region projects。'
run_psql --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('${user_one}'::uuid, 'active'),
    ('${user_two}'::uuid, 'active'),
    ('${user_three}'::uuid, 'active');
  INSERT INTO app_data.workspaces (workspace_id, workspace_kind, display_name)
  VALUES ('${workspace_id}'::uuid, 'organization',
    '6BG original-region release concurrency workspace');
  INSERT INTO app_data.projects (project_id, workspace_id, display_name)
  VALUES
    ('${project_one}'::uuid, '${workspace_id}'::uuid, '6BG same request'),
    ('${project_two}'::uuid, '${workspace_id}'::uuid, '6BG successor chain');
  INSERT INTO app_data.questionnaire_versions
    (questionnaire_version_id, project_id, version_number, status, is_current)
  VALUES
    ('${questionnaire_one}'::uuid, '${project_one}'::uuid, 1, 'published', true),
    ('${questionnaire_two}'::uuid, '${project_two}'::uuid, 1, 'published', true);
  INSERT INTO app_data.organization_memberships
    (organization_membership_id, organization_workspace_id, app_user_id,
     active_from_utc, inactive_from_utc)
  VALUES ('${membership_id}'::uuid, '${workspace_id}'::uuid,
    '${user_one}'::uuid, clock_timestamp() - interval '30 days', NULL);
  INSERT INTO app_data.project_memberships
    (project_membership_id, organization_membership_id, project_id,
     active_from_utc, inactive_from_utc)
  VALUES
    ('${project_membership_one}'::uuid, '${membership_id}'::uuid,
      '${project_one}'::uuid, clock_timestamp() - interval '30 days', NULL),
    ('${project_membership_two}'::uuid, '${membership_id}'::uuid,
      '${project_two}'::uuid, clock_timestamp() - interval '30 days', NULL);
  INSERT INTO app_data.management_report_capability_grants
    (capability_grant_id, project_membership_id, capability_id,
     active_from_utc, inactive_from_utc)
  VALUES
    ('${capability_one}'::uuid, '${project_membership_one}'::uuid,
      'release_management_reports', clock_timestamp() - interval '30 days', NULL),
    ('${capability_two}'::uuid, '${project_membership_two}'::uuid,
      'release_management_reports', clock_timestamp() - interval '30 days', NULL);
  SELECT app_private.configure_project_reporting_time_zone_v1(
    '${time_zone_one}'::uuid, '${user_one}'::uuid, '${project_one}'::uuid,
    0, 'UTC', clock_timestamp() - interval '30 days');
  SELECT app_private.configure_project_reporting_time_zone_v1(
    '${time_zone_two}'::uuid, '${user_one}'::uuid, '${project_two}'::uuid,
    0, 'UTC', clock_timestamp() - interval '30 days');
  INSERT INTO app_data.canonical_region_tree_releases
    (tree_version, lifecycle_state, is_current)
  VALUES ('concurrent-6bg-original-v1', 'draft', false);
  INSERT INTO app_data.canonical_region_versions
    (region_id, tree_version, parent_region_id, canonical_name, kind)
  VALUES
    ('concurrent-6bg-original-country', 'concurrent-6bg-original-v1', NULL,
      '6BG Country', 'country'),
    ('concurrent-6bg-original-city', 'concurrent-6bg-original-v1',
      'concurrent-6bg-original-country', '6BG City', 'city'),
    ('concurrent-6bg-original-venue', 'concurrent-6bg-original-v1',
      'concurrent-6bg-original-city', '6BG Venue', 'venue');
  INSERT INTO app_data.canonical_region_boundaries
    (boundary_id, region_id, tree_version, boundary)
  VALUES (
    'concurrent-6bg-original-boundary', 'concurrent-6bg-original-venue',
    'concurrent-6bg-original-v1',
    polygon '((-87.81,41.69),(-87.79,41.69),(-87.79,41.71),(-87.81,41.71))'
  );
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-6bg-original-v1', true);
  DO \$setup\$
  DECLARE
    periods jsonb;
    project_row record;
    period_row record;
    contributor_row record;
    unit_number integer;
    contact_key text;
  BEGIN
    periods := app_private.resolve_management_report_periods_v1(
      'UTC', clock_timestamp());
    FOR project_row IN
      SELECT * FROM (VALUES
        (1, '${project_one}'::uuid, '${questionnaire_one}'::uuid),
        (2, '${project_two}'::uuid, '${questionnaire_two}'::uuid)
      ) AS projects(project_number, project_id, questionnaire_id)
    LOOP
      FOR period_row IN
        SELECT * FROM (VALUES
          ('previous', (periods->'previous_period'->>'start_utc')::timestamptz),
          ('current', (periods->'current_period'->>'start_utc')::timestamptz)
        ) AS periods(period_key, period_start)
      LOOP
        FOR contributor_row IN
          SELECT * FROM (VALUES
            (1, '${user_one}'::uuid, 5),
            (2, '${user_two}'::uuid, 3),
            (3, '${user_three}'::uuid, 2)
          ) AS contributors(contributor_number, app_user_id, unit_count)
        LOOP
          FOR unit_number IN 1..contributor_row.unit_count LOOP
            contact_key := format(
              'concurrent-6bg-p%s-%s-c%s-u%s',
              project_row.project_number, period_row.period_key,
              contributor_row.contributor_number, unit_number);
            INSERT INTO app_data.contacts (
              contact_id, app_user_id, workspace_id, project_id,
              questionnaire_version_id, occurred_at_utc, occurred_time_zone,
              first_submitted_at_utc, channel, location_kind, place_name,
              smallest_region_id, region_tree_version, reach_count,
              interest_level
            ) VALUES (
              contact_key, contributor_row.app_user_id,
              '${workspace_id}'::uuid, project_row.project_id,
              project_row.questionnaire_id,
              period_row.period_start + interval '1 day', 'UTC',
              period_row.period_start + interval '1 day',
              'face_to_face', 'resolved', '6BG concurrent venue',
              'concurrent-6bg-original-venue', 'concurrent-6bg-original-v1',
              1, 2);
            INSERT INTO app_data.contact_revisions (
              contact_id, revision_number, revision_kind,
              revised_by_app_user_id, snapshot
            ) VALUES (
              contact_key, 1, 'submitted', contributor_row.app_user_id,
              jsonb_build_object(
                'contactId', contact_key,
                'location', jsonb_build_object(
                  'kind', 'resolved', 'placeName', '6BG concurrent venue',
                  'smallestRegionId', 'concurrent-6bg-original-venue',
                  'regionTreeVersion', 'concurrent-6bg-original-v1')));
          END LOOP;
        END LOOP;
      END LOOP;
      INSERT INTO app_data.change_feed (
        app_user_id, workspace_id, project_id, aggregate_id,
        revision_number, change_type
      ) VALUES (
        '${user_one}'::uuid, '${workspace_id}'::uuid,
        project_row.project_id,
        format('concurrent-6bg-watermark-%s', project_row.project_number),
        1, 'contact.submitted');
    END LOOP;
  END
  \$setup\$;
" >/dev/null

same_first_output="${temporary_directory}/same-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.release_management_original_region_report_snapshot_v1(
    '6bc80000-0000-4000-8000-000000000001'::uuid,
    '${user_one}'::uuid, '${project_one}'::uuid, '${report_id}', 1);
  SELECT pg_advisory_lock(hashtextextended(
    'management-original-region-release-same-request-6bg', 0));
  SELECT pg_sleep(2);
  SELECT pg_advisory_unlock(hashtextextended(
    'management-original-region-release-same-request-6bg', 0));
  COMMIT;
" >"${same_first_output}" 2>&1 &
same_first_pid=$!
wait_for_lock_holder \
  'management-original-region-release-same-request-6bg' \
  "${same_first_pid}" "${same_first_output}"

same_second_output="${temporary_directory}/same-second.out"
run_psql --tuples-only --no-align --quiet --command="
  SELECT app_private.release_management_original_region_report_snapshot_v1(
    '6bc80000-0000-4000-8000-000000000001'::uuid,
    '${user_one}'::uuid, '${project_one}'::uuid, '${report_id}', 1)::text;
" >"${same_second_output}" 2>&1 &
same_second_pid=$!
same_first_status=0
same_second_status=0
wait "${same_first_pid}" || same_first_status=$?
wait "${same_second_pid}" || same_second_status=$?
if [[ "${same_first_status}" -ne 0 || "${same_second_status}" -ne 0 ]]; then
  cat "${same_first_output}" "${same_second_output}" >&2
  exit 1
fi
same_first_json="$(grep -E '^[{]' "${same_first_output}" | tail -n 1)"
same_second_json="$(grep -E '^[{]' "${same_second_output}" | tail -n 1)"
if [[ -z "${same_first_json}" || "${same_first_json}" != "${same_second_json}" ]]; then
  echo '6BG same-request concurrent releases did not return identical JSON.' >&2
  exit 1
fi
same_count="$(run_psql --tuples-only --no-align --command="
  SELECT (SELECT count(*) FROM app_private.management_report_snapshots
    WHERE project_id = '${project_one}'::uuid
      AND release_lineage_id = '${lineage_id}')
    || '|' || (SELECT count(*) FROM
      app_private.management_original_region_report_release_attempts
      WHERE project_id = '${project_one}'::uuid);
" | tr -d '[:space:]')"
if [[ "${same_count}" != '1|1' ]]; then
  echo "6BG same-request history error: ${same_count}" >&2
  exit 1
fi

lineage_first_output="${temporary_directory}/lineage-first.out"
run_psql --command="
  BEGIN;
  SELECT app_private.release_management_original_region_report_snapshot_v1(
    '6bc80000-0000-4000-8000-000000000002'::uuid,
    '${user_one}'::uuid, '${project_two}'::uuid, '${report_id}', 1);
  SELECT pg_advisory_lock(hashtextextended(
    'management-original-region-release-lineage-6bg', 0));
  SELECT pg_sleep(2);
  SELECT pg_advisory_unlock(hashtextextended(
    'management-original-region-release-lineage-6bg', 0));
  COMMIT;
" >"${lineage_first_output}" 2>&1 &
lineage_first_pid=$!
wait_for_lock_holder \
  'management-original-region-release-lineage-6bg' \
  "${lineage_first_pid}" "${lineage_first_output}"

lineage_second_output="${temporary_directory}/lineage-second.out"
run_psql --command="
  SELECT app_private.release_management_original_region_report_snapshot_v1(
    '6bc80000-0000-4000-8000-000000000003'::uuid,
    '${user_one}'::uuid, '${project_two}'::uuid, '${report_id}', 1);
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
    FROM app_private.management_original_region_report_release_attempts
    WHERE project_id = '${project_two}'::uuid
  ), snapshots AS (
    SELECT snapshot_id, release_request_id, previous_snapshot_id
    FROM app_private.management_report_snapshots
    WHERE project_id = '${project_two}'::uuid
      AND release_lineage_id = '${lineage_id}'
  )
  SELECT (SELECT count(*) FROM attempts) || '|' || (SELECT count(*) FROM snapshots)
    || '|' || (SELECT count(*) FROM attempts WHERE result_status = 'approved_baseline')
    || '|' || (SELECT count(*) FROM attempts WHERE result_status = 'approved')
    || '|' || CASE WHEN
      (SELECT compared_snapshot_id FROM attempts WHERE release_request_id =
        '6bc80000-0000-4000-8000-000000000003'::uuid) =
      (SELECT snapshot_id FROM snapshots WHERE release_request_id =
        '6bc80000-0000-4000-8000-000000000002'::uuid)
      THEN 'previous-ok' ELSE 'previous-bad' END
    || '|' || CASE WHEN
      (SELECT previous_snapshot_id FROM snapshots WHERE release_request_id =
        '6bc80000-0000-4000-8000-000000000003'::uuid) =
      (SELECT snapshot_id FROM snapshots WHERE release_request_id =
        '6bc80000-0000-4000-8000-000000000002'::uuid)
      THEN 'pointer-ok' ELSE 'pointer-bad' END;
" | tr -d '[:space:]')"
if [[ "${lineage_check}" != '2|2|1|1|previous-ok|pointer-ok' ]]; then
  echo "6BG lineage history error: ${lineage_check}" >&2
  exit 1
fi

auth_release_lock='management-original-region-auth-release-first-6bg'
auth_revoke_lock='management-original-region-auth-revoke-first-6bg'

# Release-first linearization: the release owns the capability lock, then
# pauses before commit. A concurrent revoke must wait and commit after the
# approved release, never make the already-linearized release disappear.
auth_release_output="${temporary_directory}/auth-release-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.release_management_original_region_report_snapshot_v1(
    '6bc80000-0000-4000-8000-000000000004'::uuid,
    '${user_one}'::uuid, '${project_one}'::uuid, '${report_id}', 1);
  SELECT pg_advisory_lock(hashtextextended(
    '${auth_release_lock}', 0));
  SELECT pg_sleep(5);
  SELECT pg_advisory_unlock(hashtextextended(
    '${auth_release_lock}', 0));
  COMMIT;
" >"${auth_release_output}" 2>&1 &
auth_release_pid=$!
wait_for_lock_holder \
  "${auth_release_lock}" \
  "${auth_release_pid}" "${auth_release_output}"

auth_revoke_output="${temporary_directory}/auth-revoke-after-release.out"
run_psql --command="
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${capability_one}'::uuid;
" >"${auth_revoke_output}" 2>&1 &
auth_revoke_pid=$!
wait_for_query_waiter \
  "${capability_one}" \
  "${auth_revoke_output}"
auth_release_status=0
auth_revoke_status=0
wait "${auth_release_pid}" || auth_release_status=$?
wait "${auth_revoke_pid}" || auth_revoke_status=$?
if [[ "${auth_release_status}" -ne 0 || "${auth_revoke_status}" -ne 0 ]]; then
  cat "${auth_release_output}" "${auth_revoke_output}" >&2
  exit 1
fi
auth_release_result="$(run_psql --tuples-only --no-align --command="
  SELECT result_status || '|' || (released_snapshot_id IS NOT NULL)::text
  FROM app_private.management_original_region_report_release_attempts
  WHERE release_request_id = '6bc80000-0000-4000-8000-000000000004'::uuid;
" | tr -d '[:space:]')"
if [[ "${auth_release_result}" != 'approved|true' ]]; then
  cat "${auth_release_output}" >&2
  echo "6BG release-first result error: ${auth_release_result}" >&2
  exit 1
fi
auth_release_state="$(run_psql --tuples-only --no-align --command="
  SELECT CASE WHEN inactive_from_utc IS NULL THEN 'active' ELSE 'revoked' END
  FROM app_data.management_report_capability_grants
  WHERE capability_grant_id = '${capability_one}'::uuid;
" | tr -d '[:space:]')"
if [[ "${auth_release_state}" != 'revoked' ]]; then
  echo "6BG release-first authorization state error: ${auth_release_state}" >&2
  exit 1
fi

# Revoke-first linearization: hold the capability mutation lock and commit the
# revocation before the release can resolve its post-lock authorization. The
# release must fail closed and must not leave an attempt row behind.
revoke_first_output="${temporary_directory}/auth-revoke-first.out"
run_psql --command="
  BEGIN;
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${capability_two}'::uuid;
  SELECT pg_advisory_lock(hashtextextended(
    '${auth_revoke_lock}', 0));
  SELECT pg_sleep(5);
  SELECT pg_advisory_unlock(hashtextextended(
    '${auth_revoke_lock}', 0));
  COMMIT;
" >"${revoke_first_output}" 2>&1 &
revoke_first_pid=$!
wait_for_lock_holder \
  "${auth_revoke_lock}" \
  "${revoke_first_pid}" "${revoke_first_output}"

revoke_release_output="${temporary_directory}/auth-release-after-revoke.out"
run_psql --command="
  SELECT app_private.release_management_original_region_report_snapshot_v1(
    '6bc80000-0000-4000-8000-000000000005'::uuid,
    '${user_one}'::uuid, '${project_two}'::uuid, '${report_id}', 1);
" >"${revoke_release_output}" 2>&1 &
revoke_release_pid=$!
wait_for_query_waiter \
  '6bc80000-0000-4000-8000-000000000005' \
  "${revoke_release_output}"
revoke_first_status=0
revoke_release_status=0
wait "${revoke_first_pid}" || revoke_first_status=$?
wait "${revoke_release_pid}" || revoke_release_status=$?
if [[ "${revoke_first_status}" -ne 0 ]]; then
  cat "${revoke_first_output}" >&2
  exit 1
fi
if [[ "${revoke_release_status}" -eq 0 ]] \
  || ! grep -q 'management report authorization forbidden' \
    "${revoke_release_output}"; then
  cat "${revoke_release_output}" >&2
  echo '6BG revoke-first release did not fail closed.' >&2
  exit 1
fi
revoke_first_attempt_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_original_region_report_release_attempts
  WHERE release_request_id = '6bc80000-0000-4000-8000-000000000005'::uuid;
" | tr -d '[:space:]')"
if [[ "${revoke_first_attempt_count}" != '0' ]]; then
  echo "6BG revoke-first release wrote an attempt: ${revoke_first_attempt_count}" >&2
  exit 1
fi

echo '6BG same-request, successor-lineage and authorization concurrency checks passed.'
