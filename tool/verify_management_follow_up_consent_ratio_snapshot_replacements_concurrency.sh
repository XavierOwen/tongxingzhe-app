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
child_pids=()

cleanup() {
  local pid
  for pid in "${child_pids[@]}"; do
    if kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock_holder() {
  local lock_name="$1"
  local holder_pid="$2"
  local holder_output="$3"
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
    sleep 0.05
  done

  echo "没有观察到并发 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  kill "${holder_pid}" >/dev/null 2>&1 || true
  exit 1
}

wait_for_lock_waiter() {
  local lock_name="$1"
  local waiter_pid="$2"
  local waiter_output="$3"
  local waiting

  for _ in $(seq 1 100); do
    waiting="$(run_psql --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          ((hashtextextended('${lock_name}', 0) >> 32)
            & 4294967295)::bigint AS classid,
          (hashtextextended('${lock_name}', 0)
            & 4294967295)::bigint AS objid,
          (SELECT oid FROM pg_database
            WHERE datname = current_database()) AS database_id
      )
      SELECT EXISTS (
        SELECT 1
        FROM pg_locks AS lock_row
        CROSS JOIN lock_key
        WHERE lock_row.locktype = 'advisory'
          AND NOT lock_row.granted
          AND lock_row.database = lock_key.database_id
          AND lock_row.classid::bigint = lock_key.classid
          AND lock_row.objid::bigint = lock_key.objid
          AND lock_row.objsubid = 1
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo '并发等待会话过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  echo "没有观察到并发等待 lock：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  kill "${waiter_pid}" >/dev/null 2>&1 || true
  exit 1
}

project_id='83d30000-0000-4000-8000-000000000001'
workspace_id='83d20000-0000-4000-8000-000000000001'
user_one='83d10000-0000-4000-8000-000000000001'
user_two='83d10000-0000-4000-8000-000000000002'
capability_one='83d60000-0000-4000-8000-000000000001'
capability_two='83d60000-0000-4000-8000-000000000002'
report_id='contact_target_follow_up_consent_ratio_two_periods'
release_lineage="management-follow-up-consent-ratio-report:${report_id}"
lineage_lock="management-follow-up-consent-ratio-snapshot-replacement-lineage:${project_id}:${release_lineage}"
organization_lock_one="organization-membership:${workspace_id}:${user_one}"
project_lock_one="project-membership:${project_id}:${user_one}"
capability_lock_one="management-report-capability:${project_id}:${user_one}:release_management_reports"
organization_lock_two="organization-membership:${workspace_id}:${user_two}"
project_lock_two="project-membership:${project_id}:${user_two}"
capability_lock_two="management-report-capability:${project_id}:${user_two}:release_management_reports"

echo '建立 6CE concurrency consent-ratio snapshots。'
run_psql --quiet <<'SQL'
BEGIN;

INSERT INTO app_data.app_users (app_user_id, status) VALUES
  ('83d10000-0000-4000-8000-000000000001'::uuid, 'active'),
  ('83d10000-0000-4000-8000-000000000002'::uuid, 'active');

INSERT INTO app_data.workspaces (
  workspace_id, workspace_kind, display_name, personal_owner_app_user_id
) VALUES (
  '83d20000-0000-4000-8000-000000000001'::uuid,
  'organization',
  '6CE concurrency workspace',
  NULL
);

INSERT INTO app_data.projects (
  project_id, workspace_id, display_name, status, is_personal_default
) VALUES (
  '83d30000-0000-4000-8000-000000000001'::uuid,
  '83d20000-0000-4000-8000-000000000001'::uuid,
  '6CE concurrency project',
  'active',
  false
);

INSERT INTO app_data.organization_memberships (
  organization_membership_id,
  organization_workspace_id,
  app_user_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '83d40000-0000-4000-8000-000000000001'::uuid,
    '83d20000-0000-4000-8000-000000000001'::uuid,
    '83d10000-0000-4000-8000-000000000001'::uuid,
    '2025-01-01T00:00:00Z',
    NULL
  ),
  (
    '83d40000-0000-4000-8000-000000000002'::uuid,
    '83d20000-0000-4000-8000-000000000001'::uuid,
    '83d10000-0000-4000-8000-000000000002'::uuid,
    '2025-01-01T00:00:00Z',
    NULL
  );

INSERT INTO app_data.organization_owner_assignments (
  organization_owner_assignment_id,
  organization_membership_id,
  active_from_utc,
  inactive_from_utc
) VALUES (
  '83dc0000-0000-4000-8000-000000000001'::uuid,
  '83d40000-0000-4000-8000-000000000001'::uuid,
  transaction_timestamp(),
  NULL
);

INSERT INTO app_data.project_memberships (
  project_membership_id,
  organization_membership_id,
  project_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '83d50000-0000-4000-8000-000000000001'::uuid,
    '83d40000-0000-4000-8000-000000000001'::uuid,
    '83d30000-0000-4000-8000-000000000001'::uuid,
    '2025-01-01T00:00:00Z',
    NULL
  ),
  (
    '83d50000-0000-4000-8000-000000000002'::uuid,
    '83d40000-0000-4000-8000-000000000002'::uuid,
    '83d30000-0000-4000-8000-000000000001'::uuid,
    '2025-01-01T00:00:00Z',
    NULL
  );

INSERT INTO app_data.management_report_capability_grants (
  capability_grant_id,
  project_membership_id,
  capability_id,
  active_from_utc,
  inactive_from_utc
) VALUES
  (
    '83d60000-0000-4000-8000-000000000001'::uuid,
    '83d50000-0000-4000-8000-000000000001'::uuid,
    'release_management_reports',
    '2025-01-01T00:00:00Z',
    NULL
  ),
  (
    '83d60000-0000-4000-8000-000000000002'::uuid,
    '83d50000-0000-4000-8000-000000000002'::uuid,
    'release_management_reports',
    '2025-01-01T00:00:00Z',
    NULL
  );

SELECT app_private.configure_project_reporting_time_zone_v1(
  '83d70000-0000-4000-8000-000000000001'::uuid,
  '83d10000-0000-4000-8000-000000000001'::uuid,
  '83d30000-0000-4000-8000-000000000001'::uuid,
  0,
  'UTC',
  '2025-01-01T00:00:00Z'
);

SET LOCAL ROLE tongxingzhe_management_follow_up_consent_config_writer;
SELECT app_private.configure_management_follow_up_consent_opt_in_v1(
  '83d10000-0000-4000-8000-000000000001'::uuid,
  '83d30000-0000-4000-8000-000000000001'::uuid,
  'follow_up_consent_ratio@1',
  '83d80000-0000-4000-8000-000000000001'::uuid,
  0,
  true
);
RESET ROLE;

DO $release$
DECLARE
  request_number integer;
BEGIN
  FOR request_number IN 1..9 LOOP
    PERFORM app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
      format(
        '83d90000-0000-4000-8000-%s',
        lpad(request_number::text, 12, '0')
      )::uuid,
      '83d10000-0000-4000-8000-000000000001'::uuid,
      '83d30000-0000-4000-8000-000000000001'::uuid,
      'contact_target_follow_up_consent_ratio_two_periods',
      1
    );
    PERFORM pg_sleep(0.002);
  END LOOP;
END
$release$;

COMMIT;
SQL

snapshot_ids=()
while IFS= read -r snapshot_id; do
  snapshot_ids+=("${snapshot_id}")
done < <(
  run_psql --tuples-only --no-align --command="
    SELECT released_snapshot_id
    FROM app_private.management_follow_up_consent_report_release_attempts
    WHERE project_id = '${project_id}'::uuid
      AND release_request_id::text LIKE '83d90000-0000-4000-8000-%'
      AND result_status IN ('approved_baseline', 'approved')
    ORDER BY release_request_id;
  "
)
if [[ "${#snapshot_ids[@]}" -ne 9 ]]; then
  echo "6CE concurrency 需要 9 份 approved snapshot，实际为 ${#snapshot_ids[@]}。" >&2
  exit 1
fi

first_snapshot="${snapshot_ids[0]}"
second_snapshot="${snapshot_ids[1]}"
third_snapshot="${snapshot_ids[2]}"
fourth_snapshot="${snapshot_ids[3]}"
fifth_snapshot="${snapshot_ids[4]}"
sixth_snapshot="${snapshot_ids[5]}"
seventh_snapshot="${snapshot_ids[6]}"
eighth_snapshot="${snapshot_ids[7]}"
ninth_snapshot="${snapshot_ids[8]}"

echo '验证同一 active head 的 competing replacements。'
race_ready_lock='6ce-concurrency-race-ready'
race_first_output="${temporary_directory}/race-first.out"
race_second_output="${temporary_directory}/race-second.out"
run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_lock(hashtextextended('${lineage_lock}', 0));
  SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '83da0000-0000-4000-8000-000000000001'::uuid,
    '${user_one}'::uuid, '${project_id}'::uuid,
    '${first_snapshot}'::uuid, '${second_snapshot}'::uuid,
    'late_accepted_data'
  );
  SELECT pg_advisory_lock(hashtextextended('${race_ready_lock}', 0));
  SELECT pg_sleep(0.4);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${lineage_lock}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${race_ready_lock}', 0));
" >"${race_first_output}" 2>&1 &
race_first_pid=$!
child_pids+=("${race_first_pid}")
wait_for_lock_holder "${race_ready_lock}" "${race_first_pid}" "${race_first_output}"

run_psql --quiet --command="
  SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '83da0000-0000-4000-8000-000000000002'::uuid,
    '${user_two}'::uuid, '${project_id}'::uuid,
    '${first_snapshot}'::uuid, '${third_snapshot}'::uuid,
    'contact_revision'
  );
" >"${race_second_output}" 2>&1 &
race_second_pid=$!
child_pids+=("${race_second_pid}")
wait_for_lock_waiter "${lineage_lock}" "${race_second_pid}" "${race_second_output}"

race_first_status=0
race_second_status=0
wait "${race_first_pid}" || race_first_status=$?
wait "${race_second_pid}" || race_second_status=$?
if [[ "${race_first_status}" -ne 0 || "${race_second_status}" -eq 0 ]]; then
  echo "6CE competing replacements 结果错误：first=${race_first_status}, second=${race_second_status}" >&2
  sed -n '1,160p' "${race_first_output}" >&2
  sed -n '1,160p' "${race_second_output}" >&2
  exit 1
fi
if ! grep -Eqi 'active head|stale|already.*replacement' "${race_second_output}"; then
  echo '第二个 6CE replacement 没有以 stale active head 失败关闭。' >&2
  sed -n '1,160p' "${race_second_output}" >&2
  exit 1
fi

echo '验证 replacement-first 后撤权按锁顺序提交。'
replacement_ready_lock='6ce-concurrency-replacement-first-ready'
replacement_output="${temporary_directory}/replacement-first.out"
replacement_revoke_output="${temporary_directory}/replacement-revoke.out"
run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_lock(hashtextextended('${lineage_lock}', 0));
  SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '83da0000-0000-4000-8000-000000000003'::uuid,
    '${user_one}'::uuid, '${project_id}'::uuid,
    '${fourth_snapshot}'::uuid, '${fifth_snapshot}'::uuid,
    'contact_revision'
  );
  SELECT pg_advisory_lock(hashtextextended('${replacement_ready_lock}', 0));
  SELECT pg_sleep(0.4);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${lineage_lock}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${replacement_ready_lock}', 0));
" >"${replacement_output}" 2>&1 &
replacement_pid=$!
child_pids+=("${replacement_pid}")
wait_for_lock_holder \
  "${replacement_ready_lock}" "${replacement_pid}" "${replacement_output}"

run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${organization_lock_one}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${project_lock_one}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${capability_lock_one}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${capability_one}'::uuid;
  COMMIT;
" >"${replacement_revoke_output}" 2>&1 &
replacement_revoke_pid=$!
child_pids+=("${replacement_revoke_pid}")
wait_for_lock_waiter \
  "${organization_lock_one}" "${replacement_revoke_pid}" \
  "${replacement_revoke_output}"

replacement_status=0
replacement_revoke_status=0
wait "${replacement_pid}" || replacement_status=$?
wait "${replacement_revoke_pid}" || replacement_revoke_status=$?
if [[ "${replacement_status}" -ne 0 || "${replacement_revoke_status}" -ne 0 ]]; then
  echo "6CE replacement-first 锁顺序错误：replacement=${replacement_status}, revoke=${replacement_revoke_status}" >&2
  sed -n '1,160p' "${replacement_output}" >&2
  sed -n '1,160p' "${replacement_revoke_output}" >&2
  exit 1
fi

echo '验证 revoke-first 后 replacement 失败关闭。'
revoke_ready_lock='6ce-concurrency-revoke-first-ready'
revoke_output="${temporary_directory}/revoke-first.out"
revoke_replacement_output="${temporary_directory}/revoke-replacement.out"
run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${organization_lock_two}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${project_lock_two}', 0));
  SELECT pg_advisory_xact_lock(hashtextextended('${capability_lock_two}', 0));
  UPDATE app_data.management_report_capability_grants
  SET inactive_from_utc = clock_timestamp()
  WHERE capability_grant_id = '${capability_two}'::uuid;
  SELECT pg_advisory_lock(hashtextextended('${revoke_ready_lock}', 0));
  SELECT pg_sleep(0.4);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${revoke_ready_lock}', 0));
" >"${revoke_output}" 2>&1 &
revoke_pid=$!
child_pids+=("${revoke_pid}")
wait_for_lock_holder "${revoke_ready_lock}" "${revoke_pid}" "${revoke_output}"

run_psql --quiet --command="
  SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '83da0000-0000-4000-8000-000000000004'::uuid,
    '${user_two}'::uuid, '${project_id}'::uuid,
    '${sixth_snapshot}'::uuid, '${seventh_snapshot}'::uuid,
    'contact_void'
  );
" >"${revoke_replacement_output}" 2>&1 &
revoke_replacement_pid=$!
child_pids+=("${revoke_replacement_pid}")
wait_for_lock_waiter \
  "${organization_lock_two}" "${revoke_replacement_pid}" \
  "${revoke_replacement_output}"

revoke_status=0
revoke_replacement_status=0
wait "${revoke_pid}" || revoke_status=$?
wait "${revoke_replacement_pid}" || revoke_replacement_status=$?
if [[ "${revoke_status}" -ne 0 || "${revoke_replacement_status}" -eq 0 ]]; then
  echo "6CE revoke-first 锁顺序错误：revoke=${revoke_status}, replacement=${revoke_replacement_status}" >&2
  sed -n '1,160p' "${revoke_output}" >&2
  sed -n '1,160p' "${revoke_replacement_output}" >&2
  exit 1
fi
if ! grep -Eqi 'authorization forbidden|authorization.*denied|capability' \
  "${revoke_replacement_output}"; then
  echo '撤权先提交后 6CE replacement 没有失败关闭。' >&2
  sed -n '1,160p' "${revoke_replacement_output}" >&2
  exit 1
fi

echo '恢复 capability 并验证 release-first request family claim。'
run_psql --quiet --command="
  INSERT INTO app_data.management_report_capability_grants (
    capability_grant_id, project_membership_id, capability_id,
    active_from_utc, inactive_from_utc
  ) VALUES
    (
      '83d60000-0000-4000-8000-000000000003'::uuid,
      '83d50000-0000-4000-8000-000000000001'::uuid,
      'release_management_reports',
      clock_timestamp(),
      NULL
    ),
    (
      '83d60000-0000-4000-8000-000000000004'::uuid,
      '83d50000-0000-4000-8000-000000000002'::uuid,
      'release_management_reports',
      clock_timestamp(),
      NULL
    );
"

release_claim_request='83dd0000-0000-4000-8000-000000000001'
release_claim_lock="management-report-release-request:${release_claim_request}"
release_claim_ready='6ce-concurrency-release-claim-ready'
release_claim_output="${temporary_directory}/release-claim.out"
release_claim_replacement_output="${temporary_directory}/release-claim-replacement.out"
run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${release_claim_lock}', 0));
  SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '${release_claim_request}'::uuid,
    '${user_one}'::uuid, '${project_id}'::uuid,
    '${report_id}', 1
  );
  SELECT pg_advisory_lock(hashtextextended('${release_claim_ready}', 0));
  SELECT pg_sleep(0.4);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${release_claim_ready}', 0));
" >"${release_claim_output}" 2>&1 &
release_claim_pid=$!
child_pids+=("${release_claim_pid}")
wait_for_lock_holder \
  "${release_claim_ready}" "${release_claim_pid}" "${release_claim_output}"

run_psql --quiet --command="
  SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '${release_claim_request}'::uuid,
    '${user_two}'::uuid, '${project_id}'::uuid,
    '${sixth_snapshot}'::uuid, '${seventh_snapshot}'::uuid,
    'contact_void'
  );
" >"${release_claim_replacement_output}" 2>&1 &
release_claim_replacement_pid=$!
child_pids+=("${release_claim_replacement_pid}")
wait_for_lock_waiter \
  "${release_claim_lock}" "${release_claim_replacement_pid}" \
  "${release_claim_replacement_output}"

release_claim_status=0
release_claim_replacement_status=0
wait "${release_claim_pid}" || release_claim_status=$?
wait "${release_claim_replacement_pid}" || release_claim_replacement_status=$?
if [[ "${release_claim_status}" -ne 0 \
  || "${release_claim_replacement_status}" -eq 0 ]]; then
  echo "6CE release-first family claim 错误：release=${release_claim_status}, replacement=${release_claim_replacement_status}" >&2
  sed -n '1,160p' "${release_claim_output}" >&2
  sed -n '1,160p' "${release_claim_replacement_output}" >&2
  exit 1
fi
if ! grep -Eqi 'another report contract|claim|already.*used' \
  "${release_claim_replacement_output}"; then
  echo 'release-first 后 6CE replacement 没有因 family claim 失败关闭。' >&2
  sed -n '1,160p' "${release_claim_replacement_output}" >&2
  exit 1
fi

echo '验证 replacement-first request family claim。'
replacement_claim_request='83dd0000-0000-4000-8000-000000000002'
replacement_claim_lock="management-report-release-request:${replacement_claim_request}"
replacement_claim_ready='6ce-concurrency-replacement-claim-ready'
replacement_claim_output="${temporary_directory}/replacement-claim.out"
replacement_claim_release_output="${temporary_directory}/replacement-claim-release.out"
run_psql --quiet --command="
  BEGIN;
  SELECT pg_advisory_xact_lock(hashtextextended('${replacement_claim_lock}', 0));
  SELECT app_private.declare_management_follow_up_consent_snapshot_replacement_v1(
    '${replacement_claim_request}'::uuid,
    '${user_one}'::uuid, '${project_id}'::uuid,
    '${eighth_snapshot}'::uuid, '${ninth_snapshot}'::uuid,
    'late_accepted_data'
  );
  SELECT pg_advisory_lock(hashtextextended('${replacement_claim_ready}', 0));
  SELECT pg_sleep(0.4);
  COMMIT;
  SELECT pg_advisory_unlock(hashtextextended('${replacement_claim_ready}', 0));
" >"${replacement_claim_output}" 2>&1 &
replacement_claim_pid=$!
child_pids+=("${replacement_claim_pid}")
wait_for_lock_holder \
  "${replacement_claim_ready}" "${replacement_claim_pid}" \
  "${replacement_claim_output}"

run_psql --quiet --command="
  SELECT app_private.release_management_follow_up_consent_ratio_report_snapshot_v1(
    '${replacement_claim_request}'::uuid,
    '${user_two}'::uuid, '${project_id}'::uuid,
    '${report_id}', 1
  );
" >"${replacement_claim_release_output}" 2>&1 &
replacement_claim_release_pid=$!
child_pids+=("${replacement_claim_release_pid}")
wait_for_lock_waiter \
  "${replacement_claim_lock}" "${replacement_claim_release_pid}" \
  "${replacement_claim_release_output}"

replacement_claim_status=0
replacement_claim_release_status=0
wait "${replacement_claim_pid}" || replacement_claim_status=$?
wait "${replacement_claim_release_pid}" || replacement_claim_release_status=$?
if [[ "${replacement_claim_status}" -ne 0 \
  || "${replacement_claim_release_status}" -eq 0 ]]; then
  echo "6CE replacement-first family claim 错误：replacement=${replacement_claim_status}, release=${replacement_claim_release_status}" >&2
  sed -n '1,160p' "${replacement_claim_output}" >&2
  sed -n '1,160p' "${replacement_claim_release_output}" >&2
  exit 1
fi
if ! grep -Eqi 'another report contract|claim|already.*used' \
  "${replacement_claim_release_output}"; then
  echo 'replacement-first 后 6CE release 没有因 family claim 失败关闭。' >&2
  sed -n '1,160p' "${replacement_claim_release_output}" >&2
  exit 1
fi

final_state="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    count(*) FILTER (WHERE superseded_snapshot_id = '${first_snapshot}'::uuid),
    count(*) FILTER (WHERE superseded_snapshot_id = '${fourth_snapshot}'::uuid),
    count(*) FILTER (WHERE superseded_snapshot_id = '${sixth_snapshot}'::uuid),
    count(*) FILTER (WHERE superseded_snapshot_id = '${eighth_snapshot}'::uuid)
  FROM app_private.management_follow_up_consent_ratio_report_snapshot_replacements
  WHERE project_id = '${project_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${final_state}" != '1|1|0|1' ]]; then
  echo "6CE concurrency 最终 lineage 状态错误：${final_state}" >&2
  exit 1
fi

echo '6CE consent-ratio replacement concurrency check passed: same-head, replacement/revocation and release/replacement request-claim ordering hold.'
