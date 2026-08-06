#!/usr/bin/env bash

set -euo pipefail

# 在两个独立数据库会话中同时发布同一项目的不同草稿。串行 fixture 无法证明
# 项目级事务锁有效，因此 CI 另行运行本检查。
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo "找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。" >&2
  exit 1
fi

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
)

issuer='https://questionnaire-concurrency.example.test'
subject='manager'
definition='[{"question_id":"concurrent-consent","position":1,"prompt":"Continue?","type":"boolean","required":true,"allow_unknown":false,"allow_refused":true,"allow_not_applicable":false}]'

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
if [[ -z "${app_user_id}" || -z "${workspace_id}" || -z "${project_id}" ]]; then
  echo "并发发布检查无法取得可信个人项目上下文。" >&2
  exit 1
fi

baseline_version_count="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --command="
    SELECT count(*)
    FROM app_data.questionnaire_versions
    WHERE project_id = '${project_id}'::uuid;
  " | tr -d '[:space:]')"

create_draft() {
  "${psql_base[@]}" \
    --tuples-only \
    --no-align \
    --command="
      SELECT draft->>'draft_id'
      FROM app_data.create_questionnaire_draft(
        '${app_user_id}'::uuid,
        '${workspace_id}'::uuid,
        '${project_id}'::uuid,
        NULL
      );
    " | tr -d '[:space:]'
}

prepare_draft() {
  local draft_id="$1"
  "${psql_base[@]}" \
    --command="
      SELECT draft
      FROM app_data.update_questionnaire_draft(
        '${app_user_id}'::uuid,
        '${workspace_id}'::uuid,
        '${project_id}'::uuid,
        '${draft_id}'::uuid,
        1,
        '${definition}'::jsonb
      );
    " >/dev/null
}

publish_draft() {
  local draft_id="$1"
  local request_id="concurrency-${draft_id}"
  "${psql_base[@]}" \
    --command="
      SELECT publication
      FROM app_data.publish_questionnaire_draft(
        '${app_user_id}'::uuid,
        '${workspace_id}'::uuid,
        '${project_id}'::uuid,
        '${draft_id}'::uuid,
        2,
        '${request_id}',
        'Concurrent publication check'
      );
    " >/dev/null
}

first_draft_id="$(create_draft)"
second_draft_id="$(create_draft)"
prepare_draft "${first_draft_id}"
prepare_draft "${second_draft_id}"

publish_draft "${first_draft_id}" &
first_pid=$!
publish_draft "${second_draft_id}" &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
if [[ "${first_status}" -ne 0 || "${second_status}" -ne 0 ]]; then
  echo "并发发布会话失败：first=${first_status}, second=${second_status}" >&2
  exit 1
fi

result="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_data.questionnaire_versions
       WHERE project_id = '${project_id}'::uuid),
      (SELECT count(*)
       FROM app_data.questionnaire_versions
       WHERE project_id = '${project_id}'::uuid AND is_current),
      (SELECT count(DISTINCT published_questionnaire_version_id)
       FROM app_data.questionnaire_drafts
       WHERE questionnaire_draft_id IN (
         '${first_draft_id}'::uuid,
         '${second_draft_id}'::uuid
       ) AND status = 'published'),
      (SELECT count(*)
       FROM app_data.questionnaire_publish_requests
       WHERE app_user_id = '${app_user_id}'::uuid
         AND request_id IN (
           'concurrency-${first_draft_id}',
           'concurrency-${second_draft_id}'
         ));
  ")"
IFS='|' read -r version_count current_count published_draft_count request_count \
  <<< "${result}"
expected_version_count=$((baseline_version_count + 2))
if [[ "${version_count}" -ne "${expected_version_count}" \
  || "${current_count}" -ne 1 \
  || "${published_draft_count}" -ne 2 \
  || "${request_count}" -ne 2 ]]; then
  echo "并发发布不变量失败：versions=${version_count}/${expected_version_count}, current=${current_count}, drafts=${published_draft_count}, requests=${request_count}" >&2
  exit 1
fi

echo "并发发布通过：两个草稿产生两个不可变版本，且项目仅有一个当前版本。"
