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
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    "$@"
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

  for _ in $(seq 1 150); do
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
  echo "没有观察到 6BR 并发 ready lock：${lock_name}" >&2
  exit 1
}

wait_for_waiting_lock() {
  local lock_name="$1"
  local pid="$2"
  local output="$3"
  local waiting

  for _ in $(seq 1 150); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      wait "${pid}" >/dev/null 2>&1 || true
      sed -n '1,160p' "${output}" >&2
      echo "没有观察到 6BR read 等待授权锁：${lock_name}" >&2
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
  echo "没有观察到 6BR read 等待授权锁：${lock_name}" >&2
  exit 1
}

# This namespace is committed on purpose: the independent psql sessions need
# one shared snapshot and the dump/restore runner preserves committed rows.
# It is separate from the rollback 6BQ fixture and every earlier concurrency
# namespace. The release attempt, claim, and snapshot are all created through
# the 0075 consent-ratio release contract.
run_psql <<'SQL'
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE fixture_6br_clock ON COMMIT DROP AS
SELECT clock_value AS fixture_now_utc,
       clock_value - interval '365 days' AS hierarchy_start_utc,
       date_trunc('week', clock_value) - interval '14 days'
         AS previous_period_start_utc,
       date_trunc('week', clock_value) - interval '7 days'
         AS current_period_start_utc
FROM (SELECT transaction_timestamp() AS clock_value) AS stable_clock;

INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('6b76c100-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6b76c100-0000-4000-8000-000000000002'::uuid, 'active'),
  ('6b76c100-0000-4000-8000-000000000003'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
)
VALUES (
  '6b76c200-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6BR consent-ratio read concurrency workspace',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
)
VALUES (
  '6b76c300-0000-4000-8000-000000000001'::uuid,
  '6b76c200-0000-4000-8000-000000000001'::uuid,
  '6BR consent-ratio read concurrency project',
  'active',
  false
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id, project_id, version_number, status, is_current
)
VALUES (
  '6b76c350-0000-4000-8000-000000000001'::uuid,
  '6b76c300-0000-4000-8000-000000000001'::uuid,
  1,
  'published',
  true
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.membership_id,
       '6b76c200-0000-4000-8000-000000000001'::uuid,
       membership.app_user_id,
       clock.hierarchy_start_utc,
       NULL
FROM (
  VALUES
    (
      '6b76c400-0000-4000-8000-000000000001'::uuid,
      '6b76c100-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b76c400-0000-4000-8000-000000000002'::uuid,
      '6b76c100-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b76c400-0000-4000-8000-000000000003'::uuid,
      '6b76c100-0000-4000-8000-000000000003'::uuid
    )
) AS membership(membership_id, app_user_id)
CROSS JOIN fixture_6br_clock AS clock;

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
)
VALUES (
  '6b76ca00-0000-4000-8000-000000000001'::uuid,
  '6b76c400-0000-4000-8000-000000000001'::uuid,
  transaction_timestamp(),
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
)
SELECT membership.membership_id,
       membership.organization_membership_id,
       '6b76c300-0000-4000-8000-000000000001'::uuid,
       clock.hierarchy_start_utc,
       NULL
FROM (
  VALUES
    (
      '6b76c500-0000-4000-8000-000000000001'::uuid,
      '6b76c400-0000-4000-8000-000000000001'::uuid
    ),
    (
      '6b76c500-0000-4000-8000-000000000002'::uuid,
      '6b76c400-0000-4000-8000-000000000002'::uuid
    ),
    (
      '6b76c500-0000-4000-8000-000000000003'::uuid,
      '6b76c400-0000-4000-8000-000000000003'::uuid
    )
) AS membership(membership_id, organization_membership_id)
CROSS JOIN fixture_6br_clock AS clock;

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
)
SELECT grant_row.grant_id,
       grant_row.project_membership_id,
       grant_row.capability_id,
       clock.hierarchy_start_utc,
       NULL
FROM (
  VALUES
    (
      '6b76c600-0000-4000-8000-000000000001'::uuid,
      '6b76c500-0000-4000-8000-000000000001'::uuid,
      'release_management_reports'::text
    ),
    (
      '6b76c600-0000-4000-8000-000000000002'::uuid,
      '6b76c500-0000-4000-8000-000000000002'::uuid,
      'view_anonymous_analytics'::text
    ),
    (
      '6b76c600-0000-4000-8000-000000000003'::uuid,
      '6b76c500-0000-4000-8000-000000000003'::uuid,
      'view_anonymous_analytics'::text
    )
) AS grant_row(grant_id, project_membership_id, capability_id)
CROSS JOIN fixture_6br_clock AS clock;

SELECT app_private.configure_project_reporting_time_zone_v1(
  '6b76c700-0000-4000-8000-000000000001'::uuid,
  '6b76c100-0000-4000-8000-000000000001'::uuid,
  '6b76c300-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  clock.hierarchy_start_utc
)
FROM fixture_6br_clock AS clock;

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '6b76c100-0000-4000-8000-000000000001'::uuid,
  '6b76c300-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '6b76c710-0000-4000-8000-000000000001'::uuid,
  0,
  true
);
RESET ROLE;

CREATE TEMP TABLE fixture_6br_source (
  contact_id text PRIMARY KEY,
  occurred_at_utc timestamptz NOT NULL,
  first_submitted_at_utc timestamptz NOT NULL,
  promotion_target_id uuid NOT NULL,
  follow_up_consent text NOT NULL
) ON COMMIT DROP;

INSERT INTO fixture_6br_source (
  contact_id,
  occurred_at_utc,
  first_submitted_at_utc,
  promotion_target_id,
  follow_up_consent
)
SELECT format(
         '6br-concurrency-%s-%s-%s',
         period.period_key,
         state.consent_state,
         n
       ),
       period.period_start_utc + interval '1 day'
         + (state.sort_order * 20 + n) * interval '1 minute',
       period.period_start_utc + interval '1 day'
         + (state.sort_order * 20 + n) * interval '1 minute'
         + interval '1 minute',
       format(
         '6b76c800-0000-4000-8000-%s',
         lpad((((state.sort_order * 20) + n)::integer)::text, 12, '0')
       )::uuid,
       state.consent_state
FROM (
  SELECT 'previous'::text AS period_key,
         clock.previous_period_start_utc AS period_start_utc
  FROM fixture_6br_clock AS clock
  UNION ALL
  SELECT 'current'::text,
         clock.current_period_start_utc
  FROM fixture_6br_clock AS clock
) AS period
CROSS JOIN (
  VALUES ('yes'::text, 0), ('no'::text, 1)
) AS state(consent_state, sort_order)
CROSS JOIN generate_series(1, 10) AS n;

INSERT INTO app_data.promotion_targets (
  promotion_target_id,
  workspace_id,
  target_type,
  display_name,
  phone,
  email,
  created_by_app_user_id
)
SELECT DISTINCT source.promotion_target_id,
       '6b76c200-0000-4000-8000-000000000001'::uuid,
       'person',
       '6BR synthetic target ' || source.promotion_target_id::text,
       NULL,
       NULL,
       '6b76c100-0000-4000-8000-000000000001'::uuid
FROM fixture_6br_source AS source;

INSERT INTO app_data.contacts (
  contact_id,
  app_user_id,
  workspace_id,
  project_id,
  questionnaire_version_id,
  occurred_at_utc,
  occurred_time_zone,
  first_submitted_at_utc,
  channel,
  location_kind,
  reach_count,
  interest_level,
  current_revision,
  lifecycle_status
)
SELECT source.contact_id,
       '6b76c100-0000-4000-8000-000000000001'::uuid,
       '6b76c200-0000-4000-8000-000000000001'::uuid,
       '6b76c300-0000-4000-8000-000000000001'::uuid,
       '6b76c350-0000-4000-8000-000000000001'::uuid,
       source.occurred_at_utc,
       'UTC',
       source.first_submitted_at_utc,
       'video_call',
       'not_applicable',
       1,
       2,
       1,
       'active'
FROM fixture_6br_source AS source;

INSERT INTO app_data.contact_revisions (
  contact_id,
  revision_number,
  revised_by_app_user_id,
  revision_kind,
  reason,
  snapshot
)
SELECT source.contact_id,
       1,
       '6b76c100-0000-4000-8000-000000000001'::uuid,
       'submitted',
       NULL,
       '{}'::jsonb
FROM fixture_6br_source AS source;

INSERT INTO app_data.contact_target_links (
  contact_id,
  revision_number,
  promotion_target_id,
  response_level,
  follow_up_consent,
  institution_representative_confirmed,
  confirmed_project_entry
)
SELECT source.contact_id,
       1,
       source.promotion_target_id,
       NULL,
       source.follow_up_consent,
       false,
       true
FROM fixture_6br_source AS source;

INSERT INTO app_data.change_feed (
  app_user_id,
  workspace_id,
  project_id,
  aggregate_id,
  revision_number,
  change_type
)
VALUES (
  '6b76c100-0000-4000-8000-000000000001'::uuid,
  '6b76c200-0000-4000-8000-000000000001'::uuid,
  '6b76c300-0000-4000-8000-000000000001'::uuid,
  '6br-concurrency-source',
  1,
  'contact.submitted'
);

SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
  '6b76c900-0000-4000-8000-000000000001'::uuid,
  '6b76c100-0000-4000-8000-000000000001'::uuid,
  '6b76c300-0000-4000-8000-000000000001'::uuid,
  'contact_target_follow_up_consent_ratio_two_periods',
  1
);
COMMIT;
SQL

snapshot_id="$(run_psql --tuples-only --no-align --command="
  SELECT released_snapshot_id
  FROM app_private.management_follow_up_consent_report_release_attempts
  WHERE release_request_id =
    '6b76c900-0000-4000-8000-000000000001'::uuid;
" | tr -d '[:space:]')"
if [[ ! "${snapshot_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo "6BR consent-ratio concurrency fixture did not create a snapshot: ${snapshot_id}" >&2
  exit 1
fi

project_id='6b76c300-0000-4000-8000-000000000001'
workspace_id='6b76c200-0000-4000-8000-000000000001'
viewer_two='6b76c100-0000-4000-8000-000000000002'
viewer_three='6b76c100-0000-4000-8000-000000000003'
capability_lock_two="management-report-capability:${project_id}:${viewer_two}:view_anonymous_analytics"
capability_lock_three="management-report-capability:${project_id}:${viewer_three}:view_anonymous_analytics"
organization_lock_two="organization-membership:${workspace_id}:${viewer_two}"
organization_lock_three="organization-membership:${workspace_id}:${viewer_three}"

# Read-first: the completed read keeps the authorization locks until commit;
# the capability revocation therefore waits and occurs after one valid audit.
read_first_ready='management-follow-up-consent-read-first-6br'
read_first_output="${temporary_directory}/read-first.out"
run_psql --tuples-only --no-align --quiet --command="
  BEGIN;
  SELECT app_private.read_authorized_management_follow_up_consent_report_snapshot_v1(
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
    '6b76c600-0000-4000-8000-000000000002'::uuid;
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
  echo '6BR read-first/revoke-first concurrency failed.' >&2
  sed -n '1,160p' "${read_first_output}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  exit 1
fi

# Revoke-first: hold the exact hierarchy locks, commit an inactive boundary,
# and keep the locks held until the ready signal. The reader must wait, then
# observe the committed revocation and fail closed without appending an audit.
revoke_second_ready='management-follow-up-consent-revoke-first-6br'
revoke_second_output="${temporary_directory}/revoke-second.out"
run_psql --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended(
    '${organization_lock_three}', 0
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
    '6b76c600-0000-4000-8000-000000000003'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revoke_second_ready}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${revoke_second_output}" 2>&1 &
revoke_second_pid=$!
wait_for_ready_lock "${revoke_second_ready}" \
  "${revoke_second_pid}" "${revoke_second_output}"

read_second_output="${temporary_directory}/read-second.out"
run_psql --set=VERBOSITY=verbose --command="
  SELECT app_private.read_authorized_management_follow_up_consent_report_snapshot_v1(
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
  || ! grep -q '42501' "${read_second_output}" \
  || ! grep -q 'management report authorization forbidden' \
    "${read_second_output}"; then
  echo '6BR revoke-first/read-second concurrency failed.' >&2
  sed -n '1,160p' "${revoke_second_output}" >&2
  sed -n '1,160p' "${read_second_output}" >&2
  exit 1
fi

audit_count="$(run_psql --tuples-only --no-align --command="
  SELECT count(*)
  FROM app_private.management_follow_up_consent_report_snapshot_access_events
  WHERE project_id = '${project_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${audit_count}" != '1' ]]; then
  echo "6BR revoke-first must not append an access audit: ${audit_count}" >&2
  exit 1
fi

echo '6BR consent-ratio snapshot read concurrency passed: read/revocation ordering is linearized by the authorization locks.'
