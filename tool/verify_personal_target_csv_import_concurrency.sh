#!/usr/bin/env bash

set -euo pipefail

# Independent PostgreSQL sessions prove exact request replay, single-preview
# consumption, and that distinct confirmed previews may create duplicate PII.
# Rows are synthetic and remain in the disposable database for dump/restore.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=30000 -c lock_timeout=15000"

psql_base=(
  "${psql_command}"
  "${DATABASE_URL}"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --set=VERBOSITY=verbose
)

run_psql() {
  "${psql_base[@]}" "$@"
}

temporary_directory="$(mktemp -d)"
child_pids=()
gate_pid=''
gate_name=''

cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_session_lock() {
  local lock_name="$1"
  local holder_pid="$2"
  local holder_output="$3"
  local probe

  for _ in $(seq 1 100); do
    probe="$(run_psql --tuples-only --no-align --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(hashtextextended('${lock_name}', 0))
        THEN NOT pg_advisory_unlock(hashtextextended('${lock_name}', 0))
        ELSE true
      END;
    " | tr -d '[:space:]')"
    if [[ "${probe}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${holder_pid}" >/dev/null 2>&1; then
      echo "并发会话未持有 ready lock：${lock_name}" >&2
      sed -n '1,160p' "${holder_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  echo "没有观察到 ready lock：${lock_name}" >&2
  sed -n '1,160p' "${holder_output}" >&2
  exit 1
}

wait_for_request_lock_waiter() {
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
        FROM pg_locks AS waiting_lock
        JOIN pg_locks AS held_lock
          ON held_lock.locktype = waiting_lock.locktype
         AND held_lock.database = waiting_lock.database
         AND held_lock.classid = waiting_lock.classid
         AND held_lock.objid = waiting_lock.objid
         AND held_lock.objsubid = waiting_lock.objsubid
        CROSS JOIN lock_key
        WHERE waiting_lock.locktype = 'advisory'
          AND waiting_lock.database = lock_key.database_id
          AND waiting_lock.classid::bigint = lock_key.classid
          AND waiting_lock.objid::bigint = lock_key.objid
          AND waiting_lock.objsubid = 1
          AND NOT waiting_lock.granted
          AND held_lock.granted
          AND waiting_lock.pid <> held_lock.pid
      );
    " | tr -d '[:space:]')"
    if [[ "${waiting}" == 't' ]]; then
      return
    fi
    if ! kill -0 "${waiter_pid}" >/dev/null 2>&1; then
      echo 'request replay 会话过早退出。' >&2
      sed -n '1,160p' "${waiter_output}" >&2
      exit 1
    fi
    sleep 0.05
  done

  echo "没有观察到 request advisory lock 的真实等待：${lock_name}" >&2
  sed -n '1,160p' "${waiter_output}" >&2
  exit 1
}

start_release_gate() {
  gate_name="$1"
  local fifo_path="${temporary_directory}/release.fifo"
  local output_path="${temporary_directory}/release-gate.out"

  mkfifo "${fifo_path}"
  "${psql_base[@]}" <"${fifo_path}" >"${output_path}" 2>&1 &
  gate_pid=$!
  child_pids+=("${gate_pid}")
  exec 3>"${fifo_path}"
  printf "SELECT pg_advisory_lock(hashtextextended('%s', 0));\n" \
    "${gate_name}" >&3
  wait_for_session_lock "${gate_name}" "${gate_pid}" "${output_path}"
}

release_gate() {
  local output_path="${temporary_directory}/release-gate.out"
  printf "SELECT pg_advisory_unlock(hashtextextended('%s', 0));\n\\q\n" \
    "${gate_name}" >&3
  exec 3>&-
  wait "${gate_pid}"
  rm -f "${temporary_directory}/release.fifo"
  gate_pid=''
  gate_name=''
  if [[ ! -s "${output_path}" ]]; then
    echo 'release gate 没有留下可检查的会话输出。' >&2
    exit 1
  fi
}

preview() {
  local label="$1"
  local rows_json="$2"
  local expected_hints="$3"
  local output_path="${temporary_directory}/${label}-preview.out"

  run_psql --quiet --tuples-only --no-align --command="
    SET ROLE tongxingzhe_runtime;
    SELECT 'PREVIEW|' || row_to_json(receipt)::text
    FROM app_data.preview_personal_target_csv_import_v1(
      '${issuer}', '${subject}', '${project_id}'::uuid,
      '${rows_json}'::jsonb
    ) AS receipt;
    RESET ROLE;
  " >"${output_path}" 2>&1

  local receipt preview_id
  receipt="$(awk -F'|' '/^PREVIEW\|/ { sub(/^[^|]*\|/, ""); print; exit }' \
    "${output_path}")"
  preview_id="$(sed -E 's/.*"preview_id":"([^"]+)".*/\1/' <<<"${receipt}")"
  if [[ ! "${preview_id}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "${label} 没有返回合法 preview receipt。" >&2
    sed -n '1,160p' "${output_path}" >&2
    exit 1
  fi
  if ! grep -Fq "\"hinted_rows\":${expected_hints}" <<<"${receipt}"; then
    echo "${label} 的 preview 行提示与并发 fixture 不符。" >&2
    sed -n '1,160p' "${output_path}" >&2
    exit 1
  fi
  printf '%s\n' "${preview_id}"
}

confirm_sql() {
  local preview_id="$1"
  local request_id="$2"
  local rows_json="$3"
  local actions_json="$4"
  cat <<SQL
SET ROLE tongxingzhe_runtime;
SELECT 'CONFIRM|' || row_to_json(receipt)::text
FROM app_data.confirm_personal_target_csv_import_v1(
  '${issuer}', '${subject}', '${project_id}'::uuid,
  '${preview_id}'::uuid, '${request_id}'::uuid,
  '${rows_json}'::jsonb, '${actions_json}'::jsonb
) AS receipt;
RESET ROLE;
SQL
}

expect_failure() {
  local label="$1"
  local expected_sqlstate="$2"
  local expected_message="$3"
  local statement="$4"
  local output_path="${temporary_directory}/${label}.out"
  local status=0

  run_psql --set=VERBOSITY=verbose --command="${statement}" \
    >"${output_path}" 2>&1 || status=$?
  if [[ "${status}" -eq 0 ]] \
    || ! grep -Fq "${expected_sqlstate}" "${output_path}" \
    || ! grep -Fq "${expected_message}" "${output_path}"; then
    echo "${label} 没有返回预期的数据库失败。" >&2
    sed -n '1,160p' "${output_path}" >&2
    exit 1
  fi
}

assert_no_pii_in_output() {
  local label="$1"
  shift
  local value output_path

  for output_path in "$@"; do
    for value in 'CSV concurrency replay target' '+1 312 555 0901' \
      'csv-replay-529@example.test' 'CSV parallel target one' \
      'CSV parallel target two' '+1 312 555 0902' \
      'csv-parallel-529@example.test'; do
      if grep -Fq "${value}" "${output_path}"; then
        echo "${label} 把 synthetic 字段值返回到了 receipt/error。" >&2
        sed -n '1,120p' "${output_path}" >&2
        exit 1
      fi
    done
  done
}

issuer='https://personal-target-csv-import-concurrency.example.test/auth/v1'
subject='personal-target-csv-import-concurrency-owner'
app_user_id=''
workspace_id=''
project_id=''

run_psql --quiet --command="
  SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');
" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
  WHERE is_current AND 'import_target_pii' = ANY(capabilities);
")"
IFS='|' read -r app_user_id workspace_id project_id <<<"$(tr -d '[:space:]' \
  <<<"${context}")"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ \
  || ! "${project_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo 'CSV 导入并发 fixture 没有取得可信 personal project context。' >&2
  exit 1
fi

replay_rows='[{"target_type":"person","display_name":"CSV concurrency replay target","phone":"+1 312 555 0901","email":"csv-replay-529@example.test"}]'
replay_actions='["create"]'
replay_request_id='52900000-0000-4000-8000-000000000001'
other_request_id='52900000-0000-4000-8000-000000000002'
replay_preview_id="$(preview replay "${replay_rows}" '[]')"
replay_lock="personal-target-csv-import-confirm:v1:${app_user_id}:${replay_request_id}"
replay_ready_lock="0111-ready:${replay_request_id}"
replay_release_lock="0111-release:${replay_request_id}"
start_release_gate "${replay_release_lock}"

run_psql --quiet --tuples-only --no-align --command="
  BEGIN;
  $(confirm_sql "${replay_preview_id}" "${replay_request_id}" \
    "${replay_rows}" "${replay_actions}")
  SELECT pg_advisory_lock(hashtextextended('${replay_ready_lock}', 0));
  SELECT pg_advisory_lock(hashtextextended('${replay_release_lock}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${replay_release_lock}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${replay_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/replay-first.out" 2>&1 &
first_pid=$!
child_pids+=("${first_pid}")
wait_for_session_lock "${replay_ready_lock}" "${first_pid}" \
  "${temporary_directory}/replay-first.out"

PGAPPNAME='csv-import-exact-replay-waiter' run_psql \
  --quiet --tuples-only --no-align --command="
    BEGIN;
    $(confirm_sql "${replay_preview_id}" "${replay_request_id}" \
      "${replay_rows}" "${replay_actions}")
    COMMIT;
  " >"${temporary_directory}/replay-second.out" 2>&1 &
second_pid=$!
child_pids+=("${second_pid}")
wait_for_request_lock_waiter "${replay_lock}" "${second_pid}" \
  "${temporary_directory}/replay-second.out"
release_gate

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
if [[ "${first_status}" -ne 0 || "${second_status}" -ne 0 ]]; then
  echo "相同 request 并发确认失败：first=${first_status}, second=${second_status}" >&2
  sed -n '1,160p' "${temporary_directory}/replay-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/replay-second.out" >&2
  exit 1
fi
first_receipt="$(awk -F'|' '/^CONFIRM\|/ { sub(/^[^|]*\|/, ""); print; exit }' \
  "${temporary_directory}/replay-first.out")"
second_receipt="$(awk -F'|' '/^CONFIRM\|/ { sub(/^[^|]*\|/, ""); print; exit }' \
  "${temporary_directory}/replay-second.out")"
if [[ -z "${first_receipt}" || "${first_receipt}" != "${second_receipt}" ]] \
  || ! grep -Fq '"outcome":"confirmed"' <<<"${first_receipt}" \
  || ! grep -Fq '"created_count":1' <<<"${first_receipt}"; then
  echo '相同 actor/request 的并发 exact replay 没有返回完全相同的一次性 receipt。' >&2
  sed -n '1,160p' "${temporary_directory}/replay-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/replay-second.out" >&2
  exit 1
fi

expect_failure same-preview-new-request '23505' \
  'personal target CSV import request conflict' "
    BEGIN;
    $(confirm_sql "${replay_preview_id}" "${other_request_id}" \
      "${replay_rows}" "${replay_actions}")
    COMMIT;
  "

replay_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*) FROM app_data.promotion_targets AS target_row
       WHERE target_row.workspace_id = '${workspace_id}'::uuid
         AND target_row.display_name = 'CSV concurrency replay target'
         AND target_row.phone = '+1 312 555 0901'),
      (SELECT count(*) FROM app_data.promotion_target_assignments AS assignment_row
       JOIN app_data.promotion_targets AS target_row USING (promotion_target_id)
       WHERE target_row.workspace_id = '${workspace_id}'::uuid
         AND target_row.display_name = 'CSV concurrency replay target'
         AND assignment_row.ended_at IS NULL),
      (SELECT count(*) FROM app_data.promotion_target_access_events AS event_row
       JOIN app_data.promotion_targets AS target_row USING (promotion_target_id)
       WHERE target_row.workspace_id = '${workspace_id}'::uuid
         AND target_row.display_name = 'CSV concurrency replay target'
         AND event_row.action = 'created'),
      (SELECT count(*) FROM app_private.personal_target_csv_import_request_claims AS claim
       WHERE claim.actor_app_user_id = '${app_user_id}'::uuid
         AND claim.workspace_id = '${workspace_id}'::uuid
         AND claim.request_id = '${replay_request_id}'::uuid),
      (SELECT count(*) FROM app_private.personal_target_csv_import_audit_events AS event_row
       WHERE event_row.actor_app_user_id = '${app_user_id}'::uuid
         AND event_row.request_id = '${replay_request_id}'::uuid
         AND event_row.phase = 'confirm');
  ")"
IFS='|' read -r replay_objects replay_assignments replay_created_events \
  replay_claims replay_audits <<<"$(tr -d '[:space:]' <<<"${replay_counts}")"
if [[ "${replay_objects}" -ne 1 || "${replay_assignments}" -ne 1 \
  || "${replay_created_events}" -ne 1 || "${replay_claims}" -ne 1 \
  || "${replay_audits}" -ne 1 ]]; then
  echo "exact replay 或同 preview 冲突留下重复事实：${replay_counts}" >&2
  exit 1
fi

# A pre-existing matching object makes both independent previews show the same
# generic row hint.  Two distinct requests can then explicitly create separate
# objects even while their confirmations overlap; there is no global PII lock.
run_psql --quiet --command="
  SET ROLE tongxingzhe_runtime;
  SELECT target
  FROM app_data.create_promotion_target(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    'person', 'CSV parallel baseline', '+1 312 555 0902',
    'csv-parallel-529@example.test', 'csv-import-concurrency-seed-529'
  );
  RESET ROLE;
" >/dev/null
parallel_rows_one='[{"target_type":"person","display_name":"CSV parallel target one","phone":"+1 312 555 0902","email":"csv-parallel-529@example.test"}]'
parallel_rows_two='[{"target_type":"person","display_name":"CSV parallel target two","phone":"+1 312 555 0902","email":"csv-parallel-529@example.test"}]'
parallel_actions='["create_separate"]'
parallel_preview_one="$(preview parallel-one "${parallel_rows_one}" '[1]')"
parallel_preview_two="$(preview parallel-two "${parallel_rows_two}" '[1]')"
parallel_request_one='52900000-0000-4000-8000-000000000003'
parallel_request_two='52900000-0000-4000-8000-000000000004'
parallel_ready_lock='0111-ready:parallel-first'
parallel_release_lock='0111-release:parallel-first'
start_release_gate "${parallel_release_lock}"

run_psql --quiet --tuples-only --no-align --command="
  BEGIN;
  $(confirm_sql "${parallel_preview_one}" "${parallel_request_one}" \
    "${parallel_rows_one}" "${parallel_actions}")
  SELECT pg_advisory_lock(hashtextextended('${parallel_ready_lock}', 0));
  SELECT pg_advisory_lock(hashtextextended('${parallel_release_lock}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${parallel_release_lock}', 0));
  SELECT pg_advisory_unlock(hashtextextended('${parallel_ready_lock}', 0));
  COMMIT;
" >"${temporary_directory}/parallel-first.out" 2>&1 &
parallel_first_pid=$!
child_pids+=("${parallel_first_pid}")
wait_for_session_lock "${parallel_ready_lock}" "${parallel_first_pid}" \
  "${temporary_directory}/parallel-first.out"

run_psql --quiet --tuples-only --no-align --command="
  BEGIN;
  $(confirm_sql "${parallel_preview_two}" "${parallel_request_two}" \
    "${parallel_rows_two}" "${parallel_actions}")
  COMMIT;
" >"${temporary_directory}/parallel-second.out" 2>&1 &
parallel_second_pid=$!
child_pids+=("${parallel_second_pid}")
parallel_second_status=0
wait "${parallel_second_pid}" || parallel_second_status=$?
if [[ "${parallel_second_status}" -ne 0 ]] \
  || ! grep -Fq '"outcome":"confirmed"' "${temporary_directory}/parallel-second.out" \
  || ! grep -Fq '"created_count":1' "${temporary_directory}/parallel-second.out"; then
  release_gate
  wait "${parallel_first_pid}" || true
  echo '不同 preview/request 的同 PII 并发确认未独立成功。' >&2
  sed -n '1,160p' "${temporary_directory}/parallel-first.out" >&2
  sed -n '1,160p' "${temporary_directory}/parallel-second.out" >&2
  exit 1
fi
release_gate
parallel_first_status=0
wait "${parallel_first_pid}" || parallel_first_status=$?
if [[ "${parallel_first_status}" -ne 0 ]] \
  || ! grep -Fq '"outcome":"confirmed"' "${temporary_directory}/parallel-first.out" \
  || ! grep -Fq '"created_count":1' "${temporary_directory}/parallel-first.out"; then
  echo '并发的第一个独立重复对象写入失败。' >&2
  sed -n '1,160p' "${temporary_directory}/parallel-first.out" >&2
  exit 1
fi

parallel_counts="$(run_psql --tuples-only --no-align --field-separator='|' \
  --command="
    SELECT
      (SELECT count(*) FROM app_data.promotion_targets AS target_row
       WHERE target_row.workspace_id = '${workspace_id}'::uuid
         AND target_row.phone = '+1 312 555 0902'),
      (SELECT count(*) FROM app_data.promotion_target_assignments AS assignment_row
       JOIN app_data.promotion_targets AS target_row USING (promotion_target_id)
       WHERE target_row.workspace_id = '${workspace_id}'::uuid
         AND target_row.phone = '+1 312 555 0902'
         AND assignment_row.ended_at IS NULL),
      (SELECT count(*) FROM app_data.promotion_target_access_events AS event_row
       JOIN app_data.promotion_targets AS target_row USING (promotion_target_id)
       WHERE target_row.workspace_id = '${workspace_id}'::uuid
         AND target_row.phone = '+1 312 555 0902'
         AND event_row.action = 'created'),
      (SELECT count(*) FROM app_private.personal_target_csv_import_request_claims AS claim
       WHERE claim.actor_app_user_id = '${app_user_id}'::uuid
         AND claim.request_id IN ('${parallel_request_one}'::uuid,
                                  '${parallel_request_two}'::uuid)),
      (SELECT count(*) FROM app_private.personal_target_csv_import_audit_events AS event_row
       WHERE event_row.actor_app_user_id = '${app_user_id}'::uuid
         AND event_row.request_id IN ('${parallel_request_one}'::uuid,
                                      '${parallel_request_two}'::uuid)
         AND event_row.phase = 'confirm');
  ")"
IFS='|' read -r parallel_objects parallel_assignments parallel_created_events \
  parallel_claims parallel_audits <<<"$(tr -d '[:space:]' <<<"${parallel_counts}")"
if [[ "${parallel_objects}" -ne 3 || "${parallel_assignments}" -ne 3 \
  || "${parallel_created_events}" -ne 3 || "${parallel_claims}" -ne 2 \
  || "${parallel_audits}" -ne 2 ]]; then
  echo "独立重复导入的原子结果错误：${parallel_counts}" >&2
  exit 1
fi

assert_no_pii_in_output 'CSV 导入并发检查' \
  "${temporary_directory}/replay-preview.out" \
  "${temporary_directory}/replay-first.out" \
  "${temporary_directory}/replay-second.out" \
  "${temporary_directory}/same-preview-new-request.out" \
  "${temporary_directory}/parallel-one-preview.out" \
  "${temporary_directory}/parallel-two-preview.out" \
  "${temporary_directory}/parallel-first.out" \
  "${temporary_directory}/parallel-second.out"

echo '个人空间 CSV 导入并发检查通过：同 request 只写一次、preview 只消费一次，独立重复导入均成功。'
