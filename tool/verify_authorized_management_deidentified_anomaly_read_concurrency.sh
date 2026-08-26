#!/usr/bin/env bash

set -euo pipefail

# Slice 6CC concurrency evidence is intentionally committed.  The rollback
# fixture owns the 6cc* namespace; this independent script uses 6ccc* IDs so
# its psql sessions and dump/restore rows never overlap with the fixture.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
background_pids=()
cleanup() {
  for pid in "${background_pids[@]:-}"; do
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

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

run_psql() {
  "${psql_base[@]}" "$@"
}

lock_key_sql() {
  local lock_name="$1"
  cat <<SQL
WITH lock_key AS (
  SELECT (hashtextextended('${lock_name}', 0) >> 32)
    & 4294967295 AS classid,
    hashtextextended('${lock_name}', 0) & 4294967295 AS objid
)
SQL
}

wait_for_ready_lock() {
  local ready_lock="$1"
  local pid="$2"
  local output="$3"
  local held

  for _ in $(seq 1 150); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      wait "${pid}" >/dev/null 2>&1 || true
      sed -n '1,160p' "${output}" >&2
      echo "没有观察到 6CC ready lock：${ready_lock}" >&2
      exit 1
    fi
    held="$(run_psql --tuples-only --no-align --command="
      $(lock_key_sql "${ready_lock}")
      SELECT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND lock_row.granted
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
  echo "6CC concurrency session did not hold ready lock: ${ready_lock}" >&2
  exit 1
}

workspace_id='6ccc2000-0000-4000-8000-000000000001'
project_id='6ccc3000-0000-4000-8000-000000000001'
questionnaire_version_id='6ccc3500-0000-4000-8000-000000000001'
contact_id='6ccc-pending-location-contact'

directory_user_id='6ccc1000-0000-4000-8000-000000000001'
directory_revoke_user_id='6ccc1000-0000-4000-8000-000000000002'
detail_user_id='6ccc1000-0000-4000-8000-000000000003'
detail_revoke_user_id='6ccc1000-0000-4000-8000-000000000004'

directory_capability_id='6ccc6000-0000-4000-8000-000000000001'
directory_revoke_capability_id='6ccc6000-0000-4000-8000-000000000002'
detail_capability_id='6ccc6000-0000-4000-8000-000000000003'
detail_revoke_capability_id='6ccc6000-0000-4000-8000-000000000004'

run_psql --command="
  BEGIN;
  SET LOCAL TIME ZONE 'UTC';
  CREATE TEMP TABLE fixture_6ccc_clock ON COMMIT DROP AS
  SELECT transaction_timestamp() AS fixture_now_utc;

  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('${directory_user_id}'::uuid, 'active'),
    ('${directory_revoke_user_id}'::uuid, 'active'),
    ('${detail_user_id}'::uuid, 'active'),
    ('${detail_revoke_user_id}'::uuid, 'active');

  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name, personal_owner_app_user_id
  ) VALUES (
    '${workspace_id}'::uuid,
    'organization',
    '6CC deidentified anomaly read concurrency workspace',
    NULL
  );

  INSERT INTO app_data.projects (
    project_id, workspace_id, display_name, status, is_personal_default
  ) VALUES (
    '${project_id}'::uuid,
    '${workspace_id}'::uuid,
    '6CC deidentified anomaly read concurrency project',
    'active',
    false
  );

  INSERT INTO app_data.questionnaire_versions (
    questionnaire_version_id, project_id, version_number, status, is_current
  ) VALUES (
    '${questionnaire_version_id}'::uuid,
    '${project_id}'::uuid,
    1,
    'published',
    true
  );

  INSERT INTO app_data.organization_memberships (
    organization_membership_id, organization_workspace_id, app_user_id,
    active_from_utc, inactive_from_utc
  )
  SELECT membership.membership_id,
         '${workspace_id}'::uuid,
         membership.app_user_id,
         clock.fixture_now_utc - interval '365 days',
         NULL
  FROM (
    VALUES
      ('6ccc4000-0000-4000-8000-000000000001'::uuid, '${directory_user_id}'::uuid),
      ('6ccc4000-0000-4000-8000-000000000002'::uuid, '${directory_revoke_user_id}'::uuid),
      ('6ccc4000-0000-4000-8000-000000000003'::uuid, '${detail_user_id}'::uuid),
      ('6ccc4000-0000-4000-8000-000000000004'::uuid, '${detail_revoke_user_id}'::uuid)
  ) AS membership(membership_id, app_user_id)
  CROSS JOIN fixture_6ccc_clock AS clock;

  INSERT INTO app_data.project_memberships (
    project_membership_id, organization_membership_id, project_id,
    active_from_utc, inactive_from_utc
  )
  SELECT membership.membership_id,
         membership.organization_membership_id,
         '${project_id}'::uuid,
         clock.fixture_now_utc - interval '365 days',
         NULL
  FROM (
    VALUES
      ('6ccc5000-0000-4000-8000-000000000001'::uuid, '6ccc4000-0000-4000-8000-000000000001'::uuid),
      ('6ccc5000-0000-4000-8000-000000000002'::uuid, '6ccc4000-0000-4000-8000-000000000002'::uuid),
      ('6ccc5000-0000-4000-8000-000000000003'::uuid, '6ccc4000-0000-4000-8000-000000000003'::uuid),
      ('6ccc5000-0000-4000-8000-000000000004'::uuid, '6ccc4000-0000-4000-8000-000000000004'::uuid)
  ) AS membership(membership_id, organization_membership_id)
  CROSS JOIN fixture_6ccc_clock AS clock;

  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id,
    active_from_utc, inactive_from_utc
  )
  SELECT grant_row.grant_id,
         grant_row.project_membership_id,
         'view_deidentified_anomalies',
         clock.fixture_now_utc - interval '365 days',
         NULL
  FROM (
    VALUES
      ('${directory_capability_id}'::uuid, '6ccc5000-0000-4000-8000-000000000001'::uuid),
      ('${directory_revoke_capability_id}'::uuid, '6ccc5000-0000-4000-8000-000000000002'::uuid),
      ('${detail_capability_id}'::uuid, '6ccc5000-0000-4000-8000-000000000003'::uuid),
      ('${detail_revoke_capability_id}'::uuid, '6ccc5000-0000-4000-8000-000000000004'::uuid)
  ) AS grant_row(grant_id, project_membership_id)
  CROSS JOIN fixture_6ccc_clock AS clock;

  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    first_submitted_at_utc, channel, location_kind, latitude, longitude,
    location_accuracy_meters, reach_count, interest_level, current_revision,
    lifecycle_status
  )
  SELECT '${contact_id}',
         '${directory_user_id}'::uuid,
         '${workspace_id}'::uuid,
         '${project_id}'::uuid,
         '${questionnaire_version_id}'::uuid,
         clock.fixture_now_utc - interval '1 hour',
         'UTC',
         clock.fixture_now_utc - interval '1 hour',
         'face_to_face',
         'pending_resolution',
         41.881832,
         -87.623177,
         8.0,
         1,
         2,
         1,
         'active'
  FROM fixture_6ccc_clock AS clock;

  INSERT INTO app_data.contact_revisions (
    contact_id, revision_number, revised_by_app_user_id, revision_kind,
    reason, snapshot
  ) VALUES (
    '${contact_id}',
    1,
    '${directory_user_id}'::uuid,
    'submitted',
    NULL,
    jsonb_build_object(
      'location', jsonb_build_object(
        'kind', 'pending_resolution',
        'latitude', 41.881832,
        'longitude', -87.623177,
        'accuracyMeters', 8.0
      )
    )
  );
  COMMIT;
"

anomaly_id="$(run_psql --tuples-only --no-align --command="
  SELECT mapping.anomaly_id
  FROM app_private.deidentified_location_anomaly_ids AS mapping
  JOIN app_data.contact_location_provenance AS source
    ON source.source_id = mapping.source_id
  WHERE source.contact_id = '${contact_id}'
    AND source.revision_number = 1;
" | tr -d '[:space:]')"
if [[ ! "${anomaly_id}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "6CC 并发夹具未生成有效 opaque anomaly_id：${anomaly_id}" >&2
  exit 1
fi

directory_org_lock="organization-membership:${workspace_id}:${directory_user_id}"
directory_project_lock="project-membership:${project_id}:${directory_user_id}"
directory_capability_lock="management-report-capability:${project_id}:${directory_user_id}:view_deidentified_anomalies"
directory_revoke_org_lock="organization-membership:${workspace_id}:${directory_revoke_user_id}"
directory_revoke_project_lock="project-membership:${project_id}:${directory_revoke_user_id}"
directory_revoke_capability_lock="management-report-capability:${project_id}:${directory_revoke_user_id}:view_deidentified_anomalies"
detail_org_lock="organization-membership:${workspace_id}:${detail_user_id}"
detail_project_lock="project-membership:${project_id}:${detail_user_id}"
detail_capability_lock="management-report-capability:${project_id}:${detail_user_id}:view_deidentified_anomalies"
detail_revoke_org_lock="organization-membership:${workspace_id}:${detail_revoke_user_id}"
detail_revoke_project_lock="project-membership:${project_id}:${detail_revoke_user_id}"
detail_revoke_capability_lock="management-report-capability:${project_id}:${detail_revoke_user_id}:view_deidentified_anomalies"

# Directory-first: the completed read keeps all resolver locks while the
# revocation session waits.  The read commits only after it observes that wait.
directory_first_output="${temporary_directory}/directory-first.out"
directory_first_revocation_output="${temporary_directory}/directory-first-revocation.out"
directory_first_ready='6ccc-ready:directory-first'

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.list_authorized_deidentified_location_anomalies_v1(
    '${directory_user_id}'::uuid,
    '${project_id}'::uuid
  );
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_first_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        $(lock_key_sql "${directory_org_lock}")
        SELECT 1
        FROM pg_catalog.pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'directory-first revocation did not wait for read';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${directory_first_output}" 2>&1 &
directory_first_pid=$!
background_pids+=("${directory_first_pid}")
wait_for_ready_lock "${directory_first_ready}" "${directory_first_pid}" "${directory_first_output}"

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_org_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_project_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_capability_lock}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${directory_capability_id}'::uuid;
  COMMIT;
" >"${directory_first_revocation_output}" 2>&1 &
directory_first_revocation_pid=$!
background_pids+=("${directory_first_revocation_pid}")

directory_first_status=0
directory_first_revocation_status=0
wait "${directory_first_pid}" || directory_first_status=$?
wait "${directory_first_revocation_pid}" || directory_first_revocation_status=$?
if [[ "${directory_first_status}" -ne 0 \
  || "${directory_first_revocation_status}" -ne 0 ]]; then
  echo "6CC directory-first race failed: read=${directory_first_status}, revocation=${directory_first_revocation_status}" >&2
  sed -n '1,160p' "${directory_first_output}" >&2
  sed -n '1,160p' "${directory_first_revocation_output}" >&2
  exit 1
fi
if ! grep -q 'authorized_deidentified_location_anomaly_directory_v1' \
  "${directory_first_output}"; then
  echo '6CC directory-first read did not return its contract.' >&2
  sed -n '1,160p' "${directory_first_output}" >&2
  exit 1
fi
directory_first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT count(*), min(event.access_kind), min(event.result_status),
    min(event.returned_anomaly_count),
    bool_and(capability_grant.inactive_from_utc IS NOT NULL)
  FROM app_private.deidentified_location_anomaly_access_events AS event
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.capability_grant_id = event.capability_grant_id
  WHERE event.requested_by_app_user_id = '${directory_user_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${directory_first_state}" != '1|directory|completed|1|t' ]]; then
  echo "6CC directory-first read was not audited before revocation: ${directory_first_state}" >&2
  exit 1
fi

# Revoke-first directory: the revocation owns the resolver locks before the
# read begins.  After the read is observed waiting, revocation commits and the
# resolver must reject the request without creating an audit row.
directory_revoke_first_output="${temporary_directory}/directory-revoke-first.out"
directory_revoke_first_revocation_output="${temporary_directory}/directory-revoke-first-revocation.out"
directory_revoke_first_ready='6ccc-ready:directory-revoke-first'

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_revoke_org_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_revoke_project_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_revoke_capability_lock}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${directory_revoke_capability_id}'::uuid;
  SELECT pg_advisory_xact_lock(hashtextextended('${directory_revoke_first_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        $(lock_key_sql "${directory_revoke_org_lock}")
        SELECT 1
        FROM pg_catalog.pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'directory read did not wait for revoke-first transaction';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${directory_revoke_first_revocation_output}" 2>&1 &
directory_revoke_first_pid=$!
background_pids+=("${directory_revoke_first_pid}")
wait_for_ready_lock "${directory_revoke_first_ready}" \
  "${directory_revoke_first_pid}" "${directory_revoke_first_revocation_output}"

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.list_authorized_deidentified_location_anomalies_v1(
    '${directory_revoke_user_id}'::uuid,
    '${project_id}'::uuid
  );
" >"${directory_revoke_first_output}" 2>&1 &
directory_revoke_first_read_pid=$!
background_pids+=("${directory_revoke_first_read_pid}")

directory_revoke_first_status=0
directory_revoke_first_revocation_status=0
wait "${directory_revoke_first_pid}" || directory_revoke_first_revocation_status=$?
wait "${directory_revoke_first_read_pid}" || directory_revoke_first_status=$?
if [[ "${directory_revoke_first_revocation_status}" -ne 0 \
  || "${directory_revoke_first_status}" -eq 0 ]]; then
  echo "6CC revoke-first directory race failed: revocation=${directory_revoke_first_revocation_status}, read=${directory_revoke_first_status}" >&2
  sed -n '1,160p' "${directory_revoke_first_revocation_output}" >&2
  sed -n '1,160p' "${directory_revoke_first_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${directory_revoke_first_output}"; then
  echo '6CC directory read after revocation did not fail closed.' >&2
  sed -n '1,160p' "${directory_revoke_first_output}" >&2
  exit 1
fi
directory_revoke_first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT count(event.access_event_id),
    capability_grant.inactive_from_utc IS NOT NULL
  FROM app_data.management_report_capability_grants AS capability_grant
  LEFT JOIN app_private.deidentified_location_anomaly_access_events AS event
    ON event.capability_grant_id = capability_grant.capability_grant_id
   AND event.requested_by_app_user_id = '${directory_revoke_user_id}'::uuid
  WHERE capability_grant.capability_grant_id =
    '${directory_revoke_capability_id}'::uuid
  GROUP BY capability_grant.inactive_from_utc;
" | tr -d '[:space:]')"
if [[ "${directory_revoke_first_state}" != '0|t' ]]; then
  echo "6CC revoke-first directory left an audit row or did not revoke: ${directory_revoke_first_state}" >&2
  exit 1
fi

# Detail-first uses the same authorization locks. This scenario proves that
# the detail contact lock does not let a revocation overtake a completed read.
detail_first_output="${temporary_directory}/detail-first.out"
detail_first_revocation_output="${temporary_directory}/detail-first-revocation.out"
detail_first_ready='6ccc-ready:detail-first'

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.read_authorized_deidentified_location_anomaly_v1(
    '${detail_user_id}'::uuid,
    '${project_id}'::uuid,
    '${anomaly_id}'::uuid
  );
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_first_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        $(lock_key_sql "${detail_org_lock}")
        SELECT 1
        FROM pg_catalog.pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'detail-first revocation did not wait for read';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${detail_first_output}" 2>&1 &
detail_first_pid=$!
background_pids+=("${detail_first_pid}")
wait_for_ready_lock "${detail_first_ready}" "${detail_first_pid}" "${detail_first_output}"

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_org_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_project_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_capability_lock}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${detail_capability_id}'::uuid;
  COMMIT;
" >"${detail_first_revocation_output}" 2>&1 &
detail_first_revocation_pid=$!
background_pids+=("${detail_first_revocation_pid}")

detail_first_status=0
detail_first_revocation_status=0
wait "${detail_first_pid}" || detail_first_status=$?
wait "${detail_first_revocation_pid}" || detail_first_revocation_status=$?
if [[ "${detail_first_status}" -ne 0 \
  || "${detail_first_revocation_status}" -ne 0 ]]; then
  echo "6CC detail-first race failed: read=${detail_first_status}, revocation=${detail_first_revocation_status}" >&2
  sed -n '1,160p' "${detail_first_output}" >&2
  sed -n '1,160p' "${detail_first_revocation_output}" >&2
  exit 1
fi
if ! grep -q 'authorized_deidentified_location_anomaly_detail_v1' \
  "${detail_first_output}" \
  || ! grep -Eq '"result_status"[[:space:]]*:[[:space:]]*"completed"' \
    "${detail_first_output}" \
  || ! grep -q "${anomaly_id}" "${detail_first_output}"; then
  echo '6CC detail-first read did not return the completed opaque detail.' >&2
  sed -n '1,200p' "${detail_first_output}" >&2
  exit 1
fi
detail_first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT count(*), min(event.access_kind), min(event.result_status),
    bool_and(capability_grant.inactive_from_utc IS NOT NULL)
  FROM app_private.deidentified_location_anomaly_access_events AS event
  JOIN app_data.management_report_capability_grants AS capability_grant
    ON capability_grant.capability_grant_id = event.capability_grant_id
  WHERE event.requested_by_app_user_id = '${detail_user_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${detail_first_state}" != '1|detail|completed|t' ]]; then
  echo "6CC detail-first read was not audited before revocation: ${detail_first_state}" >&2
  exit 1
fi

# Revoke-first detail: once the detail session is observed waiting on the
# resolver lock, revocation commits and the detail call fails before it can
# create either a success or a not_found audit row.
detail_revoke_first_output="${temporary_directory}/detail-revoke-first.out"
detail_revoke_first_revocation_output="${temporary_directory}/detail-revoke-first-revocation.out"
detail_revoke_first_ready='6ccc-ready:detail-revoke-first'

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_revoke_org_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_revoke_project_lock}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_revoke_capability_lock}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${detail_revoke_capability_id}'::uuid;
  SELECT pg_advisory_xact_lock(hashtextextended('${detail_revoke_first_ready}', 0));
  DO \$wait\$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        $(lock_key_sql "${detail_revoke_org_lock}")
        SELECT 1
        FROM pg_catalog.pg_locks AS lock_row
        JOIN lock_key
          ON lock_row.classid::bigint = lock_key.classid
         AND lock_row.objid::bigint = lock_key.objid
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
      );
      IF clock_timestamp() >= deadline THEN
        RAISE EXCEPTION 'detail read did not wait for revoke-first transaction';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${detail_revoke_first_revocation_output}" 2>&1 &
detail_revoke_first_pid=$!
background_pids+=("${detail_revoke_first_pid}")
wait_for_ready_lock "${detail_revoke_first_ready}" \
  "${detail_revoke_first_pid}" "${detail_revoke_first_revocation_output}"

run_psql --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT app_private.read_authorized_deidentified_location_anomaly_v1(
    '${detail_revoke_user_id}'::uuid,
    '${project_id}'::uuid,
    '${anomaly_id}'::uuid
  );
" >"${detail_revoke_first_output}" 2>&1 &
detail_revoke_first_read_pid=$!
background_pids+=("${detail_revoke_first_read_pid}")

detail_revoke_first_status=0
detail_revoke_first_revocation_status=0
wait "${detail_revoke_first_pid}" || detail_revoke_first_revocation_status=$?
wait "${detail_revoke_first_read_pid}" || detail_revoke_first_status=$?
if [[ "${detail_revoke_first_revocation_status}" -ne 0 \
  || "${detail_revoke_first_status}" -eq 0 ]]; then
  echo "6CC revoke-first detail race failed: revocation=${detail_revoke_first_revocation_status}, read=${detail_revoke_first_status}" >&2
  sed -n '1,160p' "${detail_revoke_first_revocation_output}" >&2
  sed -n '1,160p' "${detail_revoke_first_output}" >&2
  exit 1
fi
if ! grep -q 'management report authorization forbidden' \
  "${detail_revoke_first_output}"; then
  echo '6CC detail read after revocation did not fail closed.' >&2
  sed -n '1,160p' "${detail_revoke_first_output}" >&2
  exit 1
fi
detail_revoke_first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT count(event.access_event_id),
    capability_grant.inactive_from_utc IS NOT NULL
  FROM app_data.management_report_capability_grants AS capability_grant
  LEFT JOIN app_private.deidentified_location_anomaly_access_events AS event
    ON event.capability_grant_id = capability_grant.capability_grant_id
   AND event.requested_by_app_user_id = '${detail_revoke_user_id}'::uuid
  WHERE capability_grant.capability_grant_id =
    '${detail_revoke_capability_id}'::uuid
  GROUP BY capability_grant.inactive_from_utc;
" | tr -d '[:space:]')"
if [[ "${detail_revoke_first_state}" != '0|t' ]]; then
  echo "6CC revoke-first detail left an audit row or did not revoke: ${detail_revoke_first_state}" >&2
  exit 1
fi

echo '6CC deidentified anomaly concurrency check passed: directory/detail reads and revocations linearized on shared authorization locks.'
