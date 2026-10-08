#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?请设置 DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
command -v "${psql_command}" >/dev/null 2>&1 || {
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
}
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=20000 -c lock_timeout=10000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1)
temporary_directory="$(mktemp -d)"
child_pids=()
cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

# Core sessions A and B use real private writers and their existing receipt.
# Coordinator probes observe A's request lock and B's wait before A continues.
wait_for_state() {
  local condition="$1" output="$2" observed
  for _ in $(seq 1 120); do
    observed="$("${psql_base[@]}" --tuples-only --no-align --command="
      SELECT EXISTS (${condition})" | tr -d '[:space:]')"
    if [[ "${observed}" == t ]]; then return; fi
    sleep 0.05
  done
  echo '0107 未观察到预期的 request 持锁／等待状态。' >&2
  cat "${output}" >&2
  exit 1
}

"${psql_base[@]}" --quiet <<'SQL'
BEGIN;
INSERT INTO app_data.app_users (app_user_id, status)
VALUES
  ('81070000-0107-4000-8000-000000000001', 'active'),
  ('81070000-0107-4000-8000-000000000008', 'active'),
  ('81070000-0107-4000-8000-000000000009', 'active');
SELECT app_private.create_organization_v1(
  '81070000-0107-4000-8000-000000000001',
  '81070000-0107-4000-8000-000000000002',
  '0107 recovery report read fixture'
);
INSERT INTO app_data.external_identities (issuer, subject, app_user_id)
VALUES (
  'https://synthetic-0107.example/issuer',
  'report-reader',
  '81070000-0107-4000-8000-000000000001'
);
INSERT INTO app_data.projects (project_id, workspace_id, display_name)
SELECT
  '81070000-0107-4000-8000-000000000003',
  claim.organization_workspace_id,
  '0107 recovery report read project'
FROM app_private.organization_creation_request_claims AS claim
WHERE claim.request_id = '81070000-0107-4000-8000-000000000002';
INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc
)
SELECT
  '81070000-0107-4000-8000-000000000004',
  membership.organization_membership_id,
  '81070000-0107-4000-8000-000000000003',
  membership.active_from_utc
FROM app_data.organization_memberships AS membership
JOIN app_private.organization_creation_request_claims AS claim
  ON claim.organization_workspace_id = membership.organization_workspace_id
WHERE claim.request_id = '81070000-0107-4000-8000-000000000002'
  AND membership.app_user_id = '81070000-0107-4000-8000-000000000001';
INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc
)
VALUES (
  '81070000-0107-4000-8000-000000000005',
  '81070000-0107-4000-8000-000000000004',
  'view_anonymous_analytics',
  (SELECT active_from_utc FROM app_data.project_memberships
   WHERE project_membership_id = '81070000-0107-4000-8000-000000000004')
);
INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc
)
VALUES (
  '81070000-0107-4000-8000-000000000010',
  '81070000-0107-4000-8000-000000000004',
  'release_management_reports',
  (SELECT active_from_utc FROM app_data.project_memberships
   WHERE project_membership_id = '81070000-0107-4000-8000-000000000004')
);

INSERT INTO app_data.questionnaire_versions (
  questionnaire_version_id,
  project_id,
  version_number,
  status,
  is_current
)
VALUES (
  '81070000-0107-4000-8000-000000000011',
  '81070000-0107-4000-8000-000000000003',
  1,
  'published',
  true
);
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
  interest_level
)
SELECT
  'request-lock-order-' || period_row.period_key || '-' || series_row::text,
  CASE
    WHEN series_row <= 5
      THEN '81070000-0107-4000-8000-000000000001'::uuid
    WHEN series_row <= 8
      THEN '81070000-0107-4000-8000-000000000008'::uuid
    ELSE '81070000-0107-4000-8000-000000000009'::uuid
  END,
  claim.organization_workspace_id,
  '81070000-0107-4000-8000-000000000003',
  '81070000-0107-4000-8000-000000000011',
  period_row.occurred_at_utc,
  'UTC',
  period_row.occurred_at_utc + interval '1 hour',
  'voice_call',
  'not_applicable',
  1,
  2
FROM app_private.organization_creation_request_claims AS claim
CROSS JOIN (
  SELECT
    'previous'::text AS period_key,
    (date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
      - interval '12 days') AT TIME ZONE 'UTC' AS occurred_at_utc
  UNION ALL
  SELECT
    'current'::text,
    (date_trunc('week', transaction_timestamp() AT TIME ZONE 'UTC')
      - interval '5 days') AT TIME ZONE 'UTC'
) AS period_row
CROSS JOIN generate_series(1, 10) AS series_row
WHERE claim.request_id = '81070000-0107-4000-8000-000000000002';

DO $published_snapshot$
BEGIN
  PERFORM app_private.configure_project_reporting_time_zone_v1(
    '81070000-0107-4000-8000-000000000012',
    '81070000-0107-4000-8000-000000000001',
    '81070000-0107-4000-8000-000000000003',
    0,
    'UTC',
    transaction_timestamp() - interval '30 days'
  );
  PERFORM app_private.release_management_report_snapshot_v2(
    '81070000-0107-4000-8000-000000000013',
    '81070000-0107-4000-8000-000000000001',
    '81070000-0107-4000-8000-000000000003',
    'contact_sessions_by_channel_two_periods',
    1
  );
END
$published_snapshot$;

DO $receipt$
BEGIN
  IF (SELECT count(*) FROM app_private.management_report_release_v2_attempts
    WHERE release_request_id = '81070000-0107-4000-8000-000000000013'
      AND result_status = 'approved_baseline' AND released_snapshot_id IS NOT NULL) <> 1
  THEN RAISE EXCEPTION '0107 did not seed a real channel-v2 receipt'; END IF;
END
$receipt$;
COMMIT;
SQL

evidence() {
  "${psql_base[@]}" --tuples-only --no-align --command="
    SELECT jsonb_build_object(
      'v2', (SELECT jsonb_agg(to_jsonb(row))
        FROM app_private.management_report_release_v2_attempts AS row
        WHERE row.project_id = '81070000-0107-4000-8000-000000000003'),
      'v1', (SELECT jsonb_agg(to_jsonb(row))
        FROM app_private.management_report_release_attempts AS row
        WHERE row.project_id = '81070000-0107-4000-8000-000000000003'),
      'snapshots', (SELECT jsonb_agg(to_jsonb(row))
        FROM app_private.management_report_snapshots AS row
        WHERE row.project_id = '81070000-0107-4000-8000-000000000003'),
      'claims', (SELECT jsonb_agg(to_jsonb(row))
        FROM app_private.management_report_release_request_claims AS row
        WHERE row.release_request_id = '81070000-0107-4000-8000-000000000013'),
      'detail_audit', (SELECT jsonb_agg(to_jsonb(row))
        FROM app_private.management_report_snapshot_access_events AS row
        WHERE row.project_id = '81070000-0107-4000-8000-000000000003'),
      'directory_audit', (SELECT jsonb_agg(to_jsonb(row))
        FROM app_private.management_report_snapshot_directory_access_events AS row
        WHERE row.project_id = '81070000-0107-4000-8000-000000000003'))"
}
evidence_before="$(evidence)"
first_output="${temporary_directory}/request-holder.out"
replay_output="${temporary_directory}/replay.out"

PGAPPNAME='0107-request-holder' "${psql_base[@]}" --quiet <<'SQL' >"${first_output}" 2>&1 &
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended(
  'management-report-release-request:81070000-0107-4000-8000-000000000013', 0));
SELECT pg_sleep(2);
-- This is the required finalizer order. B must not own hierarchy locks while
-- waiting for the request, so A can revoke before handing the request to B.
SELECT app_private.lock_organization_governance_v1(workspace_id)
FROM app_data.projects
WHERE project_id = '81070000-0107-4000-8000-000000000003';
SELECT 1 FROM app_data.workspaces
WHERE workspace_id = (SELECT workspace_id FROM app_data.projects
  WHERE project_id = '81070000-0107-4000-8000-000000000003') FOR KEY SHARE;
SELECT app_private.resolve_management_report_authorization_v1(
  '81070000-0107-4000-8000-000000000001',
  '81070000-0107-4000-8000-000000000003', 'release_management_reports');
UPDATE app_data.management_report_capability_grants
SET inactive_from_utc = clock_timestamp()
WHERE capability_grant_id = '81070000-0107-4000-8000-000000000010';
COMMIT;
SQL
first_pid=$!; child_pids+=("${first_pid}")
wait_for_state "SELECT 1 FROM pg_stat_activity
  WHERE application_name = '0107-request-holder'
    AND state = 'active' AND query LIKE '%pg_sleep%'" "${first_output}"

PGAPPNAME='0107-exact-replay' "${psql_base[@]}" --quiet <<'SQL' >"${replay_output}" 2>&1 &
DO $replay$
BEGIN
  BEGIN
    PERFORM app_private.release_management_report_snapshot_v2(
      '81070000-0107-4000-8000-000000000013',
      '81070000-0107-4000-8000-000000000001',
      '81070000-0107-4000-8000-000000000003',
      'contact_sessions_by_channel_two_periods', 1);
    RAISE EXCEPTION '0107 exact replay returned a receipt after revocation';
  EXCEPTION WHEN insufficient_privilege THEN
    IF SQLERRM IS DISTINCT FROM 'management report authorization forbidden' THEN
      RAISE EXCEPTION '0107 replay error changed: %', SQLERRM;
    END IF;
  END;
END
$replay$;
SQL
replay_pid=$!; child_pids+=("${replay_pid}")
wait_for_state "SELECT 1 FROM pg_stat_activity AS waiting
  WHERE waiting.application_name = '0107-exact-replay'
    AND EXISTS (SELECT 1 FROM pg_stat_activity AS blocker
      WHERE blocker.application_name = '0107-request-holder'
        AND blocker.pid = ANY(pg_blocking_pids(waiting.pid)))" "${replay_output}"

if ! wait "${first_pid}"; then cat "${first_output}" >&2; exit 1; fi
if ! wait "${replay_pid}"; then cat "${replay_output}" >&2; exit 1; fi
if [[ "${evidence_before}" != "$(evidence)" ]]; then
  echo '0107 撤权后 exact replay 改写／新增了 receipt、快照、claim 或 audit。' >&2
  exit 1
fi
"${psql_base[@]}" --quiet --command="
  DO \$revoked\$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM app_data.management_report_capability_grants
      WHERE capability_grant_id = '81070000-0107-4000-8000-000000000010'
        AND inactive_from_utc IS NOT NULL)
    THEN RAISE EXCEPTION '0107 request holder did not commit revocation'; END IF;
  END
  \$revoked\$;"
echo '0107 request→governance/workspace→hierarchy 与撤权后 exact replay 42501、无新增 receipt/audit：通过。'
