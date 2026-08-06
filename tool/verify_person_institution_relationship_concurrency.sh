#!/usr/bin/env bash

set -euo pipefail

# 两个独立数据库会话同时建立同一对对象的同一种活动关系。只有一个请求可以
# 成功；失败请求不能留下第二条关系或 revision。
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -f \
    "${temporary_directory}/first.out" \
    "${temporary_directory}/second.out"
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

issuer='https://institution-relation-concurrency.example.test'
subject='relationship-owner'

"${psql_base[@]}" \
  --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');" \
  >/dev/null

context="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT app_user_id, workspace_id, project_id
    FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
    WHERE is_current;
  ")"
IFS='|' read -r app_user_id workspace_id project_id <<< "${context}"
if [[ -z "${app_user_id}" || -z "${workspace_id}" \
  || -z "${project_id}" ]]; then
  echo "个人—机构关系并发检查无法取得可信上下文。" >&2
  exit 1
fi

create_target() {
  local target_type="$1"
  local display_name="$2"
  local request_id="$3"
  "${psql_base[@]}" \
    --tuples-only \
    --no-align \
    --command="
      SELECT target->>'target_id'
      FROM app_data.create_promotion_target(
        '${app_user_id}'::uuid,
        '${workspace_id}'::uuid,
        '${project_id}'::uuid,
        '${target_type}',
        '${display_name}',
        NULL,
        NULL,
        '${request_id}'
      );
    " | tr -d '[:space:]'
}

person_target_id="$(create_target \
  'person' '并发关系个人' 'institution-concurrency-person')"
institution_target_id="$(create_target \
  'institution' '并发关系机构' 'institution-concurrency-institution')"

create_relationship() {
  local mutation_id="$1"
  "${psql_base[@]}" \
    --command="
      SELECT result
      FROM app_data.create_target_institution_relationship(
        '${app_user_id}'::uuid,
        '${workspace_id}'::uuid,
        '${project_id}'::uuid,
        '${person_target_id}'::uuid,
        '${institution_target_id}'::uuid,
        'membership_affiliation',
        '并发检查',
        '${mutation_id}'
      );
    "
}

create_relationship 'institution-concurrency-first' \
  >"${temporary_directory}/first.out" 2>&1 &
first_pid=$!
create_relationship 'institution-concurrency-second' \
  >"${temporary_directory}/second.out" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?

if [[ "${first_status}" -eq 0 && "${second_status}" -eq 0 ]] \
  || [[ "${first_status}" -ne 0 && "${second_status}" -ne 0 ]]; then
  echo "并发建立应当恰有一个成功：first=${first_status}, second=${second_status}" >&2
  cat "${temporary_directory}/first.out" >&2
  cat "${temporary_directory}/second.out" >&2
  exit 1
fi

result="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_data.promotion_target_institution_relationships
       WHERE workspace_id = '${workspace_id}'::uuid
         AND person_target_id = '${person_target_id}'::uuid
         AND institution_target_id = '${institution_target_id}'::uuid
         AND relationship_kind = 'membership_affiliation'
         AND ended_at IS NULL),
      (SELECT count(*)
       FROM app_data.promotion_target_institution_relation_revisions
       WHERE relationship_id IN (
         SELECT relationship_id
         FROM app_data.promotion_target_institution_relationships
         WHERE workspace_id = '${workspace_id}'::uuid
           AND person_target_id = '${person_target_id}'::uuid
           AND institution_target_id = '${institution_target_id}'::uuid
           AND relationship_kind = 'membership_affiliation'
       ));
  ")"
IFS='|' read -r relationship_count revision_count <<< "${result}"
if [[ "${relationship_count}" -ne 1 || "${revision_count}" -ne 1 ]]; then
  echo "并发建立留下错误状态：relationships=${relationship_count}, revisions=${revision_count}" >&2
  exit 1
fi

echo "个人—机构关系并发检查通过：一个请求成功，且只保留一条活动关系和一个 revision。"
