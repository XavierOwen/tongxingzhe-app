#!/usr/bin/env bash

set -euo pipefail

# Two independent sessions exercise the 6BN original-region lineage lock and
# the authorization/revocation lock order.  The setup deliberately commits
# synthetic, value-free snapshots because the ordinary fixture rolls back
# before the concurrency runner starts.  The committed namespace is unique to
# this script and is retained for dump/restore verification.
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
race_first_pid=''
race_second_pid=''
replacement_first_pid=''
replacement_revoke_pid=''
revoke_first_pid=''
revoke_replacement_pid=''

cleanup() {
  for pid in \
    "${race_first_pid}" "${race_second_pid}" \
    "${replacement_first_pid}" "${replacement_revoke_pid}" \
    "${revoke_first_pid}" "${revoke_replacement_pid}"; do
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

wait_for_lock_holder() {
  local lock_name="$1"
  local first_pid="$2"
  local first_output="$3"
  local probe

  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      WITH lock_probe AS (
        SELECT pg_try_advisory_lock(
          hashtextextended('${lock_name}', 0)
        ) AS acquired
      )
      SELECT CASE
        WHEN acquired THEN NOT pg_advisory_unlock(
          hashtextextended('${lock_name}', 0)
        )
        ELSE true
      END
      FROM lock_probe;
    " | tr -d '[:space:]')"
    if [[ "${probe}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done

  kill "${first_pid}" >/dev/null 2>&1 || true
  wait "${first_pid}" >/dev/null 2>&1 || true
  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${first_output}" >&2
  exit 1
}

wait_for_lock_waiter() {
  local lock_name="$1"
  local waiting_pid="$2"
  local waiting_output="$3"
  local waiting

  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32)
            & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0)
            & 4294967295)::bigint AS objid
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        CROSS JOIN lock_key
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
          AND lock_row.classid::bigint = lock_key.classid
          AND lock_row.objid::bigint = lock_key.objid
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiting_pid}" >/dev/null 2>&1; then
      echo '并发等待会话过早退出。' >&2
      sed -n '1,160p' "${waiting_output}" >&2
      exit 1
    fi
    sleep 0.1
  done

  kill "${waiting_pid}" >/dev/null 2>&1 || true
  wait "${waiting_pid}" >/dev/null 2>&1 || true
  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiting_output}" >&2
  exit 1
}

lineage_prefix='management-original-region-snapshot-replacement-lineage'
replacement_project='6bce3000-0000-4000-8000-000000000001'
replacement_workspace='6bce2000-0000-4000-8000-000000000001'
replacement_user_one='6bce1000-0000-4000-8000-000000000001'
replacement_user_two='6bce1000-0000-4000-8000-000000000002'
replacement_capability_one='6bce6000-0000-4000-8000-000000000001'
replacement_capability_two='6bce6000-0000-4000-8000-000000000002'
lineage_lock_name="${lineage_prefix}:${replacement_project}:management-original-region-report:contact_sessions_by_original_region_two_periods"

organization_lock_one="organization-membership:${replacement_workspace}:${replacement_user_one}"
project_lock_one="project-membership:${replacement_project}:${replacement_user_one}"
capability_lock_one="management-report-capability:${replacement_project}:${replacement_user_one}:release_management_reports"
organization_lock_two="organization-membership:${replacement_workspace}:${replacement_user_two}"
project_lock_two="project-membership:${replacement_project}:${replacement_user_two}"
capability_lock_two="management-report-capability:${replacement_project}:${replacement_user_two}:release_management_reports"

echo '建立 6BN-concurrency synthetic original-region snapshots。'
run_psql <<'SQL'
BEGIN;

INSERT INTO app_data.app_users (app_user_id, status) VALUES
  ('6bce1000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('6bce1000-0000-4000-8000-000000000002'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, deleted_at
) VALUES (
  '6bce2000-0000-4000-8000-000000000001'::uuid,
  'organization', '6BN concurrency organization', NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '6bce3000-0000-4000-8000-000000000001'::uuid,
  '6bce2000-0000-4000-8000-000000000001'::uuid,
  '6BN concurrency project', 'active', false
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id, organization_workspace_id, app_user_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6bce4000-0000-4000-8000-000000000001'::uuid,
    '6bce2000-0000-4000-8000-000000000001'::uuid,
    '6bce1000-0000-4000-8000-000000000001'::uuid,
    '2025-01-01T00:00:00Z', NULL
  ),
  (
    '6bce4000-0000-4000-8000-000000000002'::uuid,
    '6bce2000-0000-4000-8000-000000000001'::uuid,
    '6bce1000-0000-4000-8000-000000000002'::uuid,
    '2025-01-01T00:00:00Z', NULL
  );

INSERT INTO app_data.project_memberships (
  project_membership_id, organization_membership_id, project_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6bce5000-0000-4000-8000-000000000001'::uuid,
    '6bce4000-0000-4000-8000-000000000001'::uuid,
    '6bce3000-0000-4000-8000-000000000001'::uuid,
    '2025-01-01T00:00:00Z', NULL
  ),
  (
    '6bce5000-0000-4000-8000-000000000002'::uuid,
    '6bce4000-0000-4000-8000-000000000002'::uuid,
    '6bce3000-0000-4000-8000-000000000001'::uuid,
    '2025-01-01T00:00:00Z', NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id, project_membership_id, capability_id,
  active_from_utc, inactive_from_utc
) VALUES
  (
    '6bce6000-0000-4000-8000-000000000001'::uuid,
    '6bce5000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports', '2025-01-01T00:00:00Z', NULL
  ),
  (
    '6bce6000-0000-4000-8000-000000000002'::uuid,
    '6bce5000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports', '2025-01-01T00:00:00Z', NULL
  );

INSERT INTO app_private.project_reporting_time_zone_versions (
  project_id, version_number, expected_version, change_request_id,
  requested_by_app_user_id, reporting_time_zone, period_boundary_id,
  effective_from_utc, requested_at_utc
) VALUES (
  '6bce3000-0000-4000-8000-000000000001'::uuid,
  1, 0, '6bce8000-0000-4000-8000-000000000001'::uuid,
  '6bce1000-0000-4000-8000-000000000001'::uuid, 'UTC',
  'iso_week_monday_v1', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z'
);

INSERT INTO app_data.canonical_region_tree_releases (
  tree_version, lifecycle_state, is_current, published_at_utc, content_fingerprint
) VALUES ('fixture-6bn-concurrency-v1', 'draft', false, NULL, NULL);
INSERT INTO app_data.canonical_region_versions (
  region_id, tree_version, parent_region_id, canonical_name, kind
) VALUES
  ('fixture-6bnc-country', 'fixture-6bn-concurrency-v1', NULL,
    '6BNC Country', 'country'),
  ('fixture-6bnc-city', 'fixture-6bn-concurrency-v1', 'fixture-6bnc-country',
    '6BNC City', 'city');
INSERT INTO app_data.canonical_region_boundaries (
  boundary_id, region_id, tree_version, boundary
) VALUES (
  'fixture-6bnc-city-boundary', 'fixture-6bnc-city',
  'fixture-6bn-concurrency-v1',
  polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'
);
SELECT app_private.publish_canonical_region_tree_v1(
  'fixture-6bn-concurrency-v1', false
);

-- Build complete, value-free original report documents.  Every candidate is
-- in the same project/report/version/privacy/source/period/tree contract;
-- only cutoff, publication time and source watermark advance.
WITH source AS (
  SELECT content_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'fixture-6bn-concurrency-v1'
), snapshots(
  snapshot_id, release_request_id, created_by_app_user_id,
  data_cutoff_utc, released_at_utc, previous_snapshot_id, source_change_sequence
) AS (
  VALUES
    (
      '6bcea000-0000-4000-8000-000000000001'::uuid,
      '6bceb000-0000-4000-8000-000000000001'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-02-05T12:00:00Z'::timestamptz,
      '2099-02-05T13:00:00Z'::timestamptz, NULL::uuid, 1
    ),
    (
      '6bcea000-0000-4000-8000-000000000002'::uuid,
      '6bceb000-0000-4000-8000-000000000002'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-02-06T12:00:00Z'::timestamptz,
      '2099-02-06T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000001'::uuid, 2
    ),
    (
      '6bcea000-0000-4000-8000-000000000003'::uuid,
      '6bceb000-0000-4000-8000-000000000003'::uuid,
      '6bce1000-0000-4000-8000-000000000002'::uuid,
      '2099-02-07T12:00:00Z'::timestamptz,
      '2099-02-07T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000001'::uuid, 2
    ),
    (
      '6bcea000-0000-4000-8000-000000000004'::uuid,
      '6bceb000-0000-4000-8000-000000000004'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-03-05T12:00:00Z'::timestamptz,
      '2099-03-05T13:00:00Z'::timestamptz, NULL::uuid, 1
    ),
    (
      '6bcea000-0000-4000-8000-000000000005'::uuid,
      '6bceb000-0000-4000-8000-000000000005'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-03-06T12:00:00Z'::timestamptz,
      '2099-03-06T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000004'::uuid, 2
    ),
    (
      '6bcea000-0000-4000-8000-000000000006'::uuid,
      '6bceb000-0000-4000-8000-000000000006'::uuid,
      '6bce1000-0000-4000-8000-000000000002'::uuid,
      '2099-04-05T12:00:00Z'::timestamptz,
      '2099-04-05T13:00:00Z'::timestamptz, NULL::uuid, 1
    ),
    (
      '6bcea000-0000-4000-8000-000000000007'::uuid,
      '6bceb000-0000-4000-8000-000000000007'::uuid,
      '6bce1000-0000-4000-8000-000000000002'::uuid,
      '2099-04-06T12:00:00Z'::timestamptz,
      '2099-04-06T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000006'::uuid, 2
    )
), reports AS (
  SELECT
    snapshot.*,
    jsonb_build_object(
      'report_id', 'contact_sessions_by_original_region_two_periods',
      'report_version', 1,
      'metric_id', 'contact_sessions',
      'metric_version', 1,
      'dimension', 'original_region',
      'view_mode', 'original',
      'region_granularity', 'city',
      'query_fingerprint',
        'management-report:contact_sessions_by_original_region_two_periods:v1',
      'privacy_policy', 'management_original_region_contact_session_privacy_v1',
      'source_scope', 'backend_accepted_active_contacts_original_current_revision',
      'project_id', '6bce3000-0000-4000-8000-000000000001',
      'periods', app_private.resolve_management_report_periods_v1(
        'UTC', snapshot.data_cutoff_utc
      ),
      'data_cutoff_utc', to_char(
        snapshot.data_cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'source_change_sequence', snapshot.source_change_sequence,
      'source_tree_context', jsonb_build_object(
        'source_tree_context_contract_id', 'management-original-region-source-tree:v1',
        'result_status', 'selected',
        'reason_code', 'single_original_source_tree',
        'source_tree_version', 'fixture-6bn-concurrency-v1',
        'source_content_fingerprint', source.content_fingerprint
      ),
      'result_status', 'completed',
      'cells', jsonb_build_array(
        jsonb_build_object(
          'period_key', 'previous', 'city_id', 'fixture-6bnc-city',
          'cell_order', 0, 'value_count', 10, 'privacy_status', 'displayed'
        ),
        jsonb_build_object(
          'period_key', 'current', 'city_id', 'fixture-6bnc-city',
          'cell_order', 1, 'value_count', 10, 'privacy_status', 'displayed'
        )
      )
    ) AS protected_report
  FROM snapshots AS snapshot
  CROSS JOIN source
)
SELECT set_config('session_replication_role', 'replica', true);

WITH source AS (
  SELECT content_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'fixture-6bn-concurrency-v1'
), snapshots(
  snapshot_id, release_request_id, created_by_app_user_id,
  data_cutoff_utc, released_at_utc, previous_snapshot_id, source_change_sequence
) AS (
  VALUES
    ('6bcea000-0000-4000-8000-000000000001'::uuid,
      '6bceb000-0000-4000-8000-000000000001'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-02-05T12:00:00Z'::timestamptz, '2099-02-05T13:00:00Z'::timestamptz,
      NULL::uuid, 1),
    ('6bcea000-0000-4000-8000-000000000002'::uuid,
      '6bceb000-0000-4000-8000-000000000002'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-02-06T12:00:00Z'::timestamptz, '2099-02-06T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000001'::uuid, 2),
    ('6bcea000-0000-4000-8000-000000000003'::uuid,
      '6bceb000-0000-4000-8000-000000000003'::uuid,
      '6bce1000-0000-4000-8000-000000000002'::uuid,
      '2099-02-07T12:00:00Z'::timestamptz, '2099-02-07T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000001'::uuid, 2),
    ('6bcea000-0000-4000-8000-000000000004'::uuid,
      '6bceb000-0000-4000-8000-000000000004'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-03-05T12:00:00Z'::timestamptz, '2099-03-05T13:00:00Z'::timestamptz,
      NULL::uuid, 1),
    ('6bcea000-0000-4000-8000-000000000005'::uuid,
      '6bceb000-0000-4000-8000-000000000005'::uuid,
      '6bce1000-0000-4000-8000-000000000001'::uuid,
      '2099-03-06T12:00:00Z'::timestamptz, '2099-03-06T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000004'::uuid, 2),
    ('6bcea000-0000-4000-8000-000000000006'::uuid,
      '6bceb000-0000-4000-8000-000000000006'::uuid,
      '6bce1000-0000-4000-8000-000000000002'::uuid,
      '2099-04-05T12:00:00Z'::timestamptz, '2099-04-05T13:00:00Z'::timestamptz,
      NULL::uuid, 1),
    ('6bcea000-0000-4000-8000-000000000007'::uuid,
      '6bceb000-0000-4000-8000-000000000007'::uuid,
      '6bce1000-0000-4000-8000-000000000002'::uuid,
      '2099-04-06T12:00:00Z'::timestamptz, '2099-04-06T13:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000006'::uuid, 2)
), reports AS (
  SELECT
    snapshot.*,
    jsonb_build_object(
      'report_id', 'contact_sessions_by_original_region_two_periods',
      'report_version', 1, 'metric_id', 'contact_sessions',
      'metric_version', 1, 'dimension', 'original_region',
      'view_mode', 'original', 'region_granularity', 'city',
      'query_fingerprint',
        'management-report:contact_sessions_by_original_region_two_periods:v1',
      'privacy_policy', 'management_original_region_contact_session_privacy_v1',
      'source_scope', 'backend_accepted_active_contacts_original_current_revision',
      'project_id', '6bce3000-0000-4000-8000-000000000001',
      'periods', app_private.resolve_management_report_periods_v1(
        'UTC', snapshot.data_cutoff_utc
      ),
      'data_cutoff_utc', to_char(snapshot.data_cutoff_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'source_change_sequence', snapshot.source_change_sequence,
      'source_tree_context', jsonb_build_object(
        'source_tree_context_contract_id', 'management-original-region-source-tree:v1',
        'result_status', 'selected', 'reason_code', 'single_original_source_tree',
        'source_tree_version', 'fixture-6bn-concurrency-v1',
        'source_content_fingerprint', source.content_fingerprint
      ),
      'result_status', 'completed',
      'cells', jsonb_build_array(
        jsonb_build_object('period_key', 'previous', 'city_id', 'fixture-6bnc-city',
          'cell_order', 0, 'value_count', 10, 'privacy_status', 'displayed'),
        jsonb_build_object('period_key', 'current', 'city_id', 'fixture-6bnc-city',
          'cell_order', 1, 'value_count', 10, 'privacy_status', 'displayed')
      )
    ) AS protected_report
  FROM snapshots AS snapshot
  CROSS JOIN source
)
INSERT INTO app_private.management_report_snapshots (
  snapshot_id, release_request_id, created_by_app_user_id, project_id,
  release_lineage_id, report_id, report_version, query_fingerprint,
  reporting_time_zone, data_cutoff_utc, released_at_utc,
  previous_snapshot_id, source_change_sequence, protected_report
)
SELECT
  snapshot_id, release_request_id, created_by_app_user_id,
  '6bce3000-0000-4000-8000-000000000001'::uuid,
  'management-original-region-report:contact_sessions_by_original_region_two_periods',
  'contact_sessions_by_original_region_two_periods', 1,
  'management-report:contact_sessions_by_original_region_two_periods:v1', 'UTC',
  data_cutoff_utc, released_at_utc, previous_snapshot_id,
  source_change_sequence, protected_report
FROM reports;

-- The approved 6BG attempts are enough for the trusted-provenance helper;
-- their result documents stay value-free because this is a concurrency seam.
INSERT INTO app_private.management_report_release_request_claims (
  release_request_id, release_family_id
)
SELECT format('6bceb000-0000-4000-8000-00000000000%s', n)::uuid,
  'original_region_management_report_snapshot_release'
FROM generate_series(1, 7) AS row(n);

INSERT INTO app_private.management_original_region_report_release_attempts (
  release_request_id, requested_by_app_user_id,
  organization_workspace_id, organization_membership_id,
  project_membership_id, capability_grant_id, capability_id,
  authorization_reference_at_utc, project_id,
  reporting_time_zone_version_number, reporting_time_zone,
  reporting_time_zone_effective_from_utc, data_cutoff_utc,
  release_lineage_id, report_id, report_version, query_fingerprint,
  source_tree_version, source_content_fingerprint, source_change_sequence,
  compared_snapshot_id, released_snapshot_id, shared_period_count,
  assessed_cell_count, result_status, reason_codes, result_document
)
SELECT
  snapshot.release_request_id,
  CASE WHEN snapshot.release_request_id IN (
    '6bceb000-0000-4000-8000-000000000003'::uuid,
    '6bceb000-0000-4000-8000-000000000006'::uuid,
    '6bceb000-0000-4000-8000-000000000007'::uuid
  ) THEN '6bce1000-0000-4000-8000-000000000002'::uuid
  ELSE '6bce1000-0000-4000-8000-000000000001'::uuid END,
  '6bce2000-0000-4000-8000-000000000001'::uuid,
  CASE WHEN snapshot.release_request_id IN (
    '6bceb000-0000-4000-8000-000000000003'::uuid,
    '6bceb000-0000-4000-8000-000000000006'::uuid,
    '6bceb000-0000-4000-8000-000000000007'::uuid
  ) THEN '6bce4000-0000-4000-8000-000000000002'::uuid
  ELSE '6bce4000-0000-4000-8000-000000000001'::uuid END,
  CASE WHEN snapshot.release_request_id IN (
    '6bceb000-0000-4000-8000-000000000003'::uuid,
    '6bceb000-0000-4000-8000-000000000006'::uuid,
    '6bceb000-0000-4000-8000-000000000007'::uuid
  ) THEN '6bce5000-0000-4000-8000-000000000002'::uuid
  ELSE '6bce5000-0000-4000-8000-000000000001'::uuid END,
  CASE WHEN snapshot.release_request_id IN (
    '6bceb000-0000-4000-8000-000000000003'::uuid,
    '6bceb000-0000-4000-8000-000000000006'::uuid,
    '6bceb000-0000-4000-8000-000000000007'::uuid
  ) THEN '6bce6000-0000-4000-8000-000000000002'::uuid
  ELSE '6bce6000-0000-4000-8000-000000000001'::uuid END,
  'release_management_reports', snapshot.data_cutoff_utc,
  '6bce3000-0000-4000-8000-000000000001'::uuid, 1, 'UTC',
  '2025-01-01T00:00:00Z', snapshot.data_cutoff_utc,
  'management-original-region-report:contact_sessions_by_original_region_two_periods',
  'contact_sessions_by_original_region_two_periods', 1,
  'management-report:contact_sessions_by_original_region_two_periods:v1',
  'fixture-6bn-concurrency-v1',
  (SELECT content_fingerprint
   FROM app_data.canonical_region_tree_releases
   WHERE tree_version = 'fixture-6bn-concurrency-v1'),
  CASE WHEN snapshot.previous_snapshot_id IS NULL THEN 1 ELSE 2 END,
  snapshot.previous_snapshot_id, snapshot.snapshot_id,
  CASE WHEN snapshot.previous_snapshot_id IS NULL THEN 0 ELSE 2 END,
  CASE WHEN snapshot.previous_snapshot_id IS NULL THEN 0 ELSE 4 END,
  CASE WHEN snapshot.previous_snapshot_id IS NULL THEN 'approved_baseline'
    ELSE 'approved' END,
  '[]'::jsonb, '{}'::jsonb
FROM (
  VALUES
    ('6bceb000-0000-4000-8000-000000000001'::uuid,
      '2099-02-05T12:00:00Z'::timestamptz, NULL::uuid,
      '6bcea000-0000-4000-8000-000000000001'::uuid),
    ('6bceb000-0000-4000-8000-000000000002'::uuid,
      '2099-02-06T12:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000001'::uuid,
      '6bcea000-0000-4000-8000-000000000002'::uuid),
    ('6bceb000-0000-4000-8000-000000000003'::uuid,
      '2099-02-07T12:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000001'::uuid,
      '6bcea000-0000-4000-8000-000000000003'::uuid),
    ('6bceb000-0000-4000-8000-000000000004'::uuid,
      '2099-03-05T12:00:00Z'::timestamptz, NULL::uuid,
      '6bcea000-0000-4000-8000-000000000004'::uuid),
    ('6bceb000-0000-4000-8000-000000000005'::uuid,
      '2099-03-06T12:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000004'::uuid,
      '6bcea000-0000-4000-8000-000000000005'::uuid),
    ('6bceb000-0000-4000-8000-000000000006'::uuid,
      '2099-04-05T12:00:00Z'::timestamptz, NULL::uuid,
      '6bcea000-0000-4000-8000-000000000006'::uuid),
    ('6bceb000-0000-4000-8000-000000000007'::uuid,
      '2099-04-06T12:00:00Z'::timestamptz,
      '6bcea000-0000-4000-8000-000000000006'::uuid,
      '6bcea000-0000-4000-8000-000000000007'::uuid)
) AS snapshot(release_request_id, data_cutoff_utc,
  previous_snapshot_id, snapshot_id);

SELECT set_config('session_replication_role', 'origin', true);
COMMIT;
SQL

race_first_output="${temporary_directory}/race-first.out"
race_second_output="${temporary_directory}/race-second.out"
race_ready_lock='6bn-concurrency-race-ready'

echo '验证同一 active head 的两个 replacement 请求只提交一个。'
run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_lock(hashtextextended('${lineage_lock_name}', 0));
  SELECT app_private.declare_management_original_region_snapshot_replacement_v1(
    '6bced000-0000-4000-8000-000000000001'::uuid,
    '${replacement_user_one}'::uuid, '${replacement_project}'::uuid,
    '6bcea000-0000-4000-8000-000000000001'::uuid,
    '6bcea000-0000-4000-8000-000000000002'::uuid, 'contact_revision'
  );
  SELECT pg_advisory_lock(hashtextextended('${race_ready_lock}', 0));
  SELECT pg_sleep(3);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${lineage_lock_name}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${race_ready_lock}', 0));
" >"${race_first_output}" 2>&1 &
race_first_pid=$!
wait_for_lock_holder "${race_ready_lock}" "${race_first_pid}" "${race_first_output}"

run_psql --quiet --command="
  SELECT app_private.declare_management_original_region_snapshot_replacement_v1(
    '6bced000-0000-4000-8000-000000000002'::uuid,
    '${replacement_user_two}'::uuid, '${replacement_project}'::uuid,
    '6bcea000-0000-4000-8000-000000000001'::uuid,
    '6bcea000-0000-4000-8000-000000000003'::uuid, 'late_accepted_data'
  );
" >"${race_second_output}" 2>&1 &
race_second_pid=$!
wait_for_lock_waiter "${lineage_lock_name}" "${race_second_pid}" "${race_second_output}"

race_first_status=0
race_second_status=0
wait "${race_first_pid}" || race_first_status=$?
wait "${race_second_pid}" || race_second_status=$?
if [[ "${race_first_status}" -ne 0 || "${race_second_status}" -eq 0 ]]; then
  echo "同一 original active head 并发 replacement 结果错误：first=${race_first_status}, second=${race_second_status}" >&2
  sed -n '1,160p' "${race_first_output}" >&2
  sed -n '1,160p' "${race_second_output}" >&2
  exit 1
fi
if ! grep -Eqi 'active head|stale|already.*replacement' "${race_second_output}"; then
  echo '第二个 original replacement 没有以 stale active head 失败关闭。' >&2
  sed -n '1,160p' "${race_second_output}" >&2
  exit 1
fi

race_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT count(*)::text,
    count(*) FILTER (WHERE replacement_request_id =
      '6bced000-0000-4000-8000-000000000001'::uuid)::text,
    count(*) FILTER (WHERE replacement_request_id =
      '6bced000-0000-4000-8000-000000000002'::uuid)::text,
    count(*) FILTER (WHERE superseded_snapshot_id =
      '6bcea000-0000-4000-8000-000000000001'::uuid
      AND replacement_snapshot_id = '6bcea000-0000-4000-8000-000000000002'::uuid)::text
  FROM app_private.management_original_region_report_snapshot_replacements
  WHERE project_id = '${replacement_project}'::uuid;
" | tr -d '[:space:]')"
if [[ "${race_state}" != '1|1|0|1' ]]; then
  echo "original active head 并发 replacement 不变量失败：${race_state}" >&2
  exit 1
fi

echo '验证 replacement-first：登记完成后撤权仍能按锁顺序提交。'
replacement_first_output="${temporary_directory}/replacement-first.out"
replacement_revoke_output="${temporary_directory}/replacement-revoke.out"
replacement_ready_lock='6bn-concurrency-replacement-first-ready'
replacement_lineage_two="${lineage_lock_name}"

run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_lock(hashtextextended('${replacement_lineage_two}', 0));
  SELECT app_private.declare_management_original_region_snapshot_replacement_v1(
    '6bced000-0000-4000-8000-000000000004'::uuid,
    '${replacement_user_one}'::uuid, '${replacement_project}'::uuid,
    '6bcea000-0000-4000-8000-000000000004'::uuid,
    '6bcea000-0000-4000-8000-000000000005'::uuid, 'contact_revision'
  );
  SELECT pg_advisory_lock(hashtextextended('${replacement_ready_lock}', 0));
  SELECT pg_sleep(3);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${replacement_lineage_two}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${replacement_ready_lock}', 0));
" >"${replacement_first_output}" 2>&1 &
replacement_first_pid=$!
wait_for_lock_holder "${replacement_ready_lock}" "${replacement_first_pid}" "${replacement_first_output}"

run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${organization_lock_one}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${project_lock_one}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${capability_lock_one}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${replacement_capability_one}'::uuid;
  COMMIT;
" >"${replacement_revoke_output}" 2>&1 &
replacement_revoke_pid=$!
wait_for_lock_waiter "${organization_lock_one}" "${replacement_revoke_pid}" "${replacement_revoke_output}"

replacement_first_status=0
replacement_revoke_status=0
wait "${replacement_first_pid}" || replacement_first_status=$?
wait "${replacement_revoke_pid}" || replacement_revoke_status=$?
if [[ "${replacement_first_status}" -ne 0 || "${replacement_revoke_status}" -ne 0 ]]; then
  echo "original replacement-first 锁顺序失败：replacement=${replacement_first_status}, revoke=${replacement_revoke_status}" >&2
  sed -n '1,160p' "${replacement_first_output}" >&2
  sed -n '1,160p' "${replacement_revoke_output}" >&2
  exit 1
fi

replacement_first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    (SELECT count(*) FROM app_private.management_original_region_report_snapshot_replacements
      WHERE superseded_snapshot_id = '6bcea000-0000-4000-8000-000000000004'::uuid),
    (SELECT CASE WHEN inactive_from_utc IS NULL THEN 0 ELSE 1 END
      FROM app_data.management_report_capability_grants
      WHERE capability_grant_id = '${replacement_capability_one}'::uuid);
" | tr -d '[:space:]')"
if [[ "${replacement_first_state}" != '1|1' ]]; then
  echo "original replacement-first 最终状态错误：${replacement_first_state}" >&2
  exit 1
fi

echo '验证 revoke-first：提交撤权后 replacement 必须 fail closed。'
revoke_first_output="${temporary_directory}/revoke-first.out"
revoke_replacement_output="${temporary_directory}/revoke-replacement.out"
revoke_ready_lock='6bn-concurrency-revoke-first-ready'

run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${organization_lock_two}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${project_lock_two}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${capability_lock_two}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${replacement_capability_two}'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revoke_ready_lock}', 0));
  SELECT pg_sleep(3);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${revoke_ready_lock}', 0));
" >"${revoke_first_output}" 2>&1 &
revoke_first_pid=$!
wait_for_lock_holder "${revoke_ready_lock}" "${revoke_first_pid}" "${revoke_first_output}"

run_psql --quiet --command="
  SELECT app_private.declare_management_original_region_snapshot_replacement_v1(
    '6bced000-0000-4000-8000-000000000006'::uuid,
    '${replacement_user_two}'::uuid, '${replacement_project}'::uuid,
    '6bcea000-0000-4000-8000-000000000006'::uuid,
    '6bcea000-0000-4000-8000-000000000007'::uuid, 'late_accepted_data'
  );
" >"${revoke_replacement_output}" 2>&1 &
revoke_replacement_pid=$!
wait_for_lock_waiter "${organization_lock_two}" "${revoke_replacement_pid}" "${revoke_replacement_output}"

revoke_first_status=0
revoke_replacement_status=0
wait "${revoke_first_pid}" || revoke_first_status=$?
wait "${revoke_replacement_pid}" || revoke_replacement_status=$?
if [[ "${revoke_first_status}" -ne 0 || "${revoke_replacement_status}" -eq 0 ]]; then
  echo "original revoke-first 锁顺序失败：revoke=${revoke_first_status}, replacement=${revoke_replacement_status}" >&2
  sed -n '1,160p' "${revoke_first_output}" >&2
  sed -n '1,160p' "${revoke_replacement_output}" >&2
  exit 1
fi
if ! grep -Eqi 'authorization forbidden|authorization.*denied|capability' "${revoke_replacement_output}"; then
  echo '撤权先提交后 original replacement 没有 fail closed。' >&2
  sed -n '1,160p' "${revoke_replacement_output}" >&2
  exit 1
fi

revoke_first_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    (SELECT count(*) FROM app_private.management_original_region_report_snapshot_replacements
      WHERE superseded_snapshot_id = '6bcea000-0000-4000-8000-000000000006'::uuid),
    (SELECT CASE WHEN inactive_from_utc IS NULL THEN 0 ELSE 1 END
      FROM app_data.management_report_capability_grants
      WHERE capability_grant_id = '${replacement_capability_two}'::uuid);
" | tr -d '[:space:]')"
if [[ "${revoke_first_state}" != '0|1' ]]; then
  echo "original revoke-first 最终状态错误：${revoke_first_state}" >&2
  exit 1
fi

echo '6BN original-region replacement concurrency check passed: same-head serialization and replacement/revocation lock ordering hold.'
