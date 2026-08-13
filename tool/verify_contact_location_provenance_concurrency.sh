#!/usr/bin/env bash

set -euo pipefail

# 两个独立会话提交同一 contact.submit.v1。第一个事务在来源行写入后保持
# 未提交，第二个会话必须等待同一个 command lock，最后返回 duplicate，且
# contact revision 与 provenance 都只能有一行。随后第二个会话发布新区域树，
# 证明 current 切换不会改写来源记录引用的已提交旧 fingerprint。
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:+${PGOPTIONS} }-c statement_timeout=30000 -c lock_timeout=15000"

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

temporary_directory="$(mktemp -d)"
cleanup() {
  local child_pid
  for child_pid in "${first_pid:-}" "${second_pid:-}"; do
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

context_result="$(${psql_base[@]} --quiet --tuples-only --no-align \
  --field-separator='|' --command="
    BEGIN;
    SET LOCAL ROLE tongxingzhe_runtime;
    SELECT app_user_id, workspace_id, project_id, questionnaire_version_id
    FROM app_data.bootstrap_personal_context(
      'https://synthetic-location-provenance-concurrency.supabase.co/auth/v1',
      'synthetic-location-provenance-concurrency-owner'
    );
    COMMIT;
  ")"
context_result="$(printf '%s\n' "${context_result}" | awk -F'|' 'NF == 4 { row=$0 } END { print row }')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id \
  <<< "${context_result}"
if [[ -z "${app_user_id}" || -z "${workspace_id}" || -z "${project_id}" \
  || -z "${questionnaire_version_id}" ]]; then
  echo '无法建立地点来源并发测试的 synthetic context。' >&2
  exit 1
fi

"${psql_base[@]}" --command="
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES
    ('concurrent-provenance-v1', 'draft', false),
    ('concurrent-provenance-v2', 'draft', false);
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('concurrent-provenance-v1-country', 'concurrent-provenance-v1', NULL, 'Concurrent Country', 'country'),
    ('concurrent-provenance-v1-city', 'concurrent-provenance-v1', 'concurrent-provenance-v1-country', 'Concurrent City', 'city'),
    ('concurrent-provenance-v1-venue', 'concurrent-provenance-v1', 'concurrent-provenance-v1-city', 'Concurrent Venue', 'venue'),
    ('concurrent-provenance-v2-country', 'concurrent-provenance-v2', NULL, 'Concurrent Country', 'country'),
    ('concurrent-provenance-v2-city', 'concurrent-provenance-v2', 'concurrent-provenance-v2-country', 'Concurrent City', 'city'),
    ('concurrent-provenance-v2-venue', 'concurrent-provenance-v2', 'concurrent-provenance-v2-city', 'Concurrent Venue', 'venue');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES
    (
      'concurrent-provenance-v1-boundary',
      'concurrent-provenance-v1-venue',
      'concurrent-provenance-v1',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    ),
    (
      'concurrent-provenance-v2-boundary',
      'concurrent-provenance-v2-venue',
      'concurrent-provenance-v2',
      polygon '((-87.62,41.78),(-87.57,41.78),(-87.57,41.81),(-87.62,41.81))'
    );
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-provenance-v1', true
  );
" >/dev/null

v1_fingerprint="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT content_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = 'concurrent-provenance-v1';
" | tr -d '[:space:]')"
if [[ ! "${v1_fingerprint}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "并发测试的 v1 release fingerprint 无效：${v1_fingerprint}" >&2
  exit 1
fi

ready_lock='contact-location-provenance-submit-ready-v1'
first_output="${temporary_directory}/first.out"
second_output="${temporary_directory}/second.out"

submit_payload="jsonb_build_object(
  'contactId', 'concurrent-provenance-contact',
  'workspaceId', '${workspace_id}',
  'projectId', '${project_id}',
  'questionnaireVersionId', '${questionnaire_version_id}',
  'occurredAtUtc', '2030-02-02T12:00:00Z',
  'occurredTimeZone', 'America/Chicago',
  'channel', 'face_to_face',
  'location', jsonb_build_object(
    'kind', 'resolved',
    'placeName', 'Concurrent Venue',
    'smallestRegionId', 'concurrent-provenance-v1-venue',
    'regionTreeVersion', 'concurrent-provenance-v1'
  ),
  'locationSource', jsonb_build_object(
    'kind', 'captured_coordinates',
    'latitude', 41.7897,
    'longitude', -87.5997,
    'accuracyMeters', 8.5,
    'resolverContractVersion', 'canonical-region-resolution:v1',
    'regionTreeContentFingerprint', '${v1_fingerprint}'
  ),
  'reachCount', 1,
  'interestLevel', 2,
  'answers', '[]'::jsonb,
  'targetLinks', '[]'::jsonb
)"

wait_for_ready() {
  local process_pid="$1"
  local lock_held='f'
  for _ in $(seq 1 100); do
    lock_held="$(${psql_base[@]} --tuples-only --no-align --command="
      WITH lock_key AS (
        SELECT
          (hashtextextended('${ready_lock}', 0) >> 32)
            & 4294967295 AS classid,
          hashtextextended('${ready_lock}', 0)
            & 4294967295 AS objid
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
    if [[ "${lock_held}" == 't' ]]; then
      return
    fi
    sleep 0.1
  done
  kill "${process_pid}" >/dev/null 2>&1 || true
  wait "${process_pid}" >/dev/null 2>&1 || true
  echo '地点来源并发首个提交会话没有进入持锁状态。' >&2
  exit 1
}

"${psql_base[@]}" --command="
  BEGIN;
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT *
  FROM app_data.apply_contact_submit_v3(
    '${app_user_id}'::uuid,
    'concurrent-provenance-command',
    1,
    'contact.submit.v1',
    'synthetic-provenance-device-a',
    'concurrent-provenance-contact',
    0,
    ${submit_payload}
  );
  SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
  SELECT pg_sleep(2);
  COMMIT;
" >"${first_output}" 2>&1 &
first_pid=$!

wait_for_ready "${first_pid}"

"${psql_base[@]}" --command="
  SET LOCAL ROLE tongxingzhe_runtime;
  SELECT *
  FROM app_data.apply_contact_submit_v3(
    '${app_user_id}'::uuid,
    'concurrent-provenance-command',
    1,
    'contact.submit.v1',
    'synthetic-provenance-device-b',
    'concurrent-provenance-contact',
    0,
    ${submit_payload}
  );
" >"${second_output}" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
if [[ "${first_status}" -ne 0 || "${second_status}" -ne 0 ]]; then
  echo "地点来源幂等并发失败：first=${first_status}, second=${second_status}" >&2
  sed -n '1,160p' "${first_output}" >&2
  sed -n '1,160p' "${second_output}" >&2
  exit 1
fi

result="$(${psql_base[@]} --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_data.contacts
       WHERE contact_id = 'concurrent-provenance-contact'),
      (SELECT count(*)
       FROM app_data.contact_revisions
       WHERE contact_id = 'concurrent-provenance-contact'),
      (SELECT count(*)
       FROM app_data.contact_location_provenance
       WHERE contact_id = 'concurrent-provenance-contact'),
      (SELECT count(*)
       FROM app_data.processed_commands
       WHERE command_id = 'concurrent-provenance-command'
         AND result_code = 'accepted'),
      (SELECT count(*)
       FROM app_data.contact_location_provenance
       WHERE contact_id = 'concurrent-provenance-contact'
         AND evidence_kind = 'resolved_from_coordinates'
         AND region_tree_content_fingerprint = '${v1_fingerprint}');
  ")"
IFS='|' read -r contact_count revision_count source_count accepted_count \
  fingerprint_count <<< "${result}"
if [[ "${contact_count}" -ne 1 || "${revision_count}" -ne 1 \
  || "${source_count}" -ne 1 || "${accepted_count}" -ne 1 \
  || "${fingerprint_count}" -ne 1 ]]; then
  echo "来源并发幂等不变量失败：contacts=${contact_count}, revisions=${revision_count}, sources=${source_count}, accepted=${accepted_count}, fingerprint=${fingerprint_count}" >&2
  sed -n '1,160p' "${first_output}" >&2
  sed -n '1,160p' "${second_output}" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-provenance-v2', true
  );
" >/dev/null

result="$(${psql_base[@]} --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT tree_version
       FROM app_data.canonical_region_tree_releases
       WHERE lifecycle_state = 'published' AND is_current),
      (SELECT region_tree_version
       FROM app_data.contact_location_provenance
       WHERE contact_id = 'concurrent-provenance-contact'
         AND revision_number = 1),
      (SELECT region_tree_content_fingerprint
       FROM app_data.contact_location_provenance
       WHERE contact_id = 'concurrent-provenance-contact'
         AND revision_number = 1);
  ")"
IFS='|' read -r current_tree source_tree source_fingerprint <<< "${result}"
if [[ "${current_tree}" != 'concurrent-provenance-v2' \
  || "${source_tree}" != 'concurrent-provenance-v1' \
  || "${source_fingerprint}" != "${v1_fingerprint}" ]]; then
  echo "current tree publication rewrote source evidence: current=${current_tree}, source_tree=${source_tree}, source_fingerprint=${source_fingerprint}" >&2
  exit 1
fi

echo '地点来源并发通过：重复提交只产生一条 revision/source，current 切换不改写旧 fingerprint。'
