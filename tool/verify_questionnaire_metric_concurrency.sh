#!/usr/bin/env bash

set -euo pipefail

# 两个独立会话同时确认或撤销同一候选问题。检查项目级指标锁和唯一约束
# 共同保证只有一个当前关系，同时失败请求不会留下半个审计事件。
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

issuer='https://questionnaire-metric-concurrency.example.test'
subject='manager'
metric_id='77777777-7777-4777-8777-777777777777'
source_definition='[{"question_id":"interest","position":1,"prompt":"Interest","type":"boolean","required":true,"allow_unknown":true,"allow_refused":true,"allow_not_applicable":false}]'
candidate_definition='[{"question_id":"interest-v2","position":1,"prompt":"Interest updated","type":"boolean","required":true,"allow_unknown":true,"allow_refused":true,"allow_not_applicable":false}]'

"${psql_base[@]}" --command="
  SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');
" >/dev/null
context="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT app_user_id, workspace_id, project_id, questionnaire_version_id
    FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
    WHERE is_current;
  ")"
IFS='|' read -r app_user_id workspace_id project_id source_version_id \
  <<< "${context}"
if [[ -z "${source_version_id}" ]]; then
  echo "并发兼容检查无法取得可信问卷上下文。" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  INSERT INTO app_data.questionnaire_questions (
    questionnaire_version_id, question_id, position, prompt, question_type,
    is_required, allow_unknown, allow_refused, allow_not_applicable
  ) VALUES (
    '${source_version_id}'::uuid, 'interest', 1, 'Interest', 'boolean',
    true, true, true, false
  );
" >/dev/null

draft_id="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --command="
    SELECT draft->>'draft_id'
    FROM app_data.create_questionnaire_draft(
      '${app_user_id}'::uuid,
      '${workspace_id}'::uuid,
      '${project_id}'::uuid,
      '${source_version_id}'::uuid
    );
  " | tr -d '[:space:]')"
"${psql_base[@]}" --command="
  SELECT draft FROM app_data.update_questionnaire_draft(
    '${app_user_id}'::uuid,
    '${workspace_id}'::uuid,
    '${project_id}'::uuid,
    '${draft_id}'::uuid,
    1,
    '${candidate_definition}'::jsonb
  );
" >/dev/null
candidate_version_id="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --command="
    SELECT publication->'summary'->>'questionnaire_version_id'
    FROM app_data.publish_questionnaire_draft(
      '${app_user_id}'::uuid,
      '${workspace_id}'::uuid,
      '${project_id}'::uuid,
      '${draft_id}'::uuid,
      2,
      'metric-concurrency-publication',
      'Metric concurrency candidate'
    );
  " | tr -d '[:space:]')"

record_decision() {
  local request_id="$1"
  "${psql_base[@]}" --command="
    SELECT event FROM app_data.record_questionnaire_metric_compatibility(
      '${app_user_id}'::uuid,
      '${workspace_id}'::uuid,
      '${project_id}'::uuid,
      '${metric_id}'::uuid,
      'Interest',
      'proportion',
      '${source_version_id}'::uuid,
      'interest',
      '${candidate_version_id}'::uuid,
      'interest-v2',
      'compatible',
      'Definitions match after explicit review',
      '${request_id}'
    );
  " >/dev/null 2>&1
}

record_decision 'metric-concurrent-confirm-a' &
first_pid=$!
record_decision 'metric-concurrent-confirm-b' &
second_pid=$!
first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
if [[ "${first_status}" -eq "${second_status}" ]]; then
  echo "并发兼容确认没有产生唯一胜者：first=${first_status}, second=${second_status}" >&2
  exit 1
fi

event_id="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --command="
    SELECT event_id
    FROM app_data.questionnaire_metric_compatibility_events
    WHERE questionnaire_metric_id = '${metric_id}'::uuid
      AND action = 'decided'
      AND decision = 'compatible';
  " | tr -d '[:space:]')"

revoke_decision() {
  local request_id="$1"
  "${psql_base[@]}" --command="
    SELECT event FROM app_data.revoke_questionnaire_metric_compatibility(
      '${app_user_id}'::uuid,
      '${workspace_id}'::uuid,
      '${project_id}'::uuid,
      '${event_id}'::uuid,
      'Concurrent revocation review',
      '${request_id}'
    );
  " >/dev/null 2>&1
}

revoke_decision 'metric-concurrent-revoke-a' &
first_pid=$!
revoke_decision 'metric-concurrent-revoke-b' &
second_pid=$!
first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
if [[ "${first_status}" -eq "${second_status}" ]]; then
  echo "并发兼容撤销没有产生唯一胜者：first=${first_status}, second=${second_status}" >&2
  exit 1
fi

result="$("${psql_base[@]}" \
  --tuples-only \
  --no-align \
  --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*)
       FROM app_data.questionnaire_metric_compatibility_events
       WHERE questionnaire_metric_id = '${metric_id}'::uuid
         AND action = 'decided'),
      (SELECT count(*)
       FROM app_data.questionnaire_metric_compatibility_events
       WHERE questionnaire_metric_id = '${metric_id}'::uuid
         AND action = 'revoked'),
      (SELECT count(*)
       FROM app_data.questionnaire_metric_members
       WHERE questionnaire_metric_id = '${metric_id}'::uuid);
  ")"
IFS='|' read -r decision_count revocation_count member_count <<< "${result}"
if [[ "${decision_count}" -ne 1 \
  || "${revocation_count}" -ne 1 \
  || "${member_count}" -ne 1 ]]; then
  echo "并发兼容不变量失败：decisions=${decision_count}, revocations=${revocation_count}, members=${member_count}" >&2
  exit 1
fi

echo "并发兼容通过：确认和撤销各有一个胜者，当前指标已重新分开。"
