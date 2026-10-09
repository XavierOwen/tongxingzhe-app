#!/usr/bin/env bash

set -euo pipefail

# Independent PostgreSQL sessions prove that a pair preview is one coherent
# snapshot, becomes stale after concurrent facts commit, and cannot cross its
# retention deadline. Synthetic rows are retained for dump/restore reruns.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"

psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi

export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }

temporary_directory="$(mktemp -d)"
child_pids=()
gate_name=''
gate_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" >/dev/null 2>&1; then kill "${pid}" >/dev/null 2>&1 || true; fi
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -f "${temporary_directory}"/*
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

wait_for_lock_waiter() {
  local app_name="$1" output_path="$2" waiting
  for _ in $(seq 1 200); do
    waiting="$(run_psql --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1 FROM pg_stat_activity AS activity
        WHERE activity.application_name = '${app_name}'
          AND activity.wait_event_type = 'Lock'
          AND cardinality(pg_blocking_pids(activity.pid)) > 0
      );
    " | tr -d '[:space:]')"
    [[ "${waiting}" == 't' ]] && return
    sleep 0.05
  done
  echo "未观察到独立会话的 PostgreSQL lock wait：${app_name}" >&2
  sed -n '1,120p' "${output_path}" >&2
  exit 1
}

start_gate() {
  gate_name="$1"
  mkfifo "${temporary_directory}/gate.fifo"
  "${psql_base[@]}" <"${temporary_directory}/gate.fifo" \
    >"${temporary_directory}/gate.out" 2>&1 &
  gate_pid=$!
  child_pids+=("${gate_pid}")
  exec 3>"${temporary_directory}/gate.fifo"
  printf "SELECT pg_advisory_lock(hashtextextended('%s', 0));\n" \
    "${gate_name}" >&3
  for _ in $(seq 1 100); do
    local held
    held="$(run_psql --tuples-only --no-align --command="
      SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('${gate_name}', 0))
        THEN NOT pg_advisory_unlock(hashtextextended('${gate_name}', 0))
        ELSE true END;
    " | tr -d '[:space:]')"
    [[ "${held}" == 't' ]] && return
    sleep 0.05
  done
  echo "无法取得 preview trigger gate：${gate_name}" >&2
  exit 1
}

release_gate() {
  printf "SELECT pg_advisory_unlock(hashtextextended('%s', 0));\n\\q\n" \
    "${gate_name}" >&3
  exec 3>&-
  wait "${gate_pid}"
  rm -f "${temporary_directory}/gate.fifo"
  gate_name=''
  gate_pid=''
}

run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7d520000-0113-pair-preview.example.test/auth/v1'
subject="7d530000-0113-pair-preview-owner-${run_token}"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('${issuer}', '${subject}');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT app_user_id, workspace_id, project_id, questionnaire_version_id
  FROM app_data.list_personal_project_contexts('${issuer}', '${subject}')
  WHERE is_current;
")"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$(tr -d '[:space:]' <<<"${context}")"
if [[ ! "${app_user_id}" =~ ^[0-9a-f-]{36}$ || ! "${workspace_id}" =~ ^[0-9a-f-]{36}$ || ! "${project_id}" =~ ^[0-9a-f-]{36}$ || ! "${questionnaire_version_id}" =~ ^[0-9a-f-]{36}$ ]]; then
  echo 'pair preview 并发 fixture 无法取得 personal project context。' >&2
  exit 1
fi

create_target() {
  local name="$1" request_id="$2" phone="$3"
  run_psql --quiet --command="
    SELECT target FROM app_data.create_promotion_target(
      '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'person', '${name}', '${phone}', 'pair-0113@example.test', '${request_id}'
    );
  " >/dev/null
}
for pair in contact renewal assignment cutoff; do
  case "${pair}" in
    contact) n=1;; renewal) n=2;; assignment) n=3;; cutoff) n=4;;
  esac
  create_target "Pair preview 0113 ${pair} first" "7d520000-0113-${run_token}-000${n}a" '+1 773 555 0113'
  create_target "Pair preview 0113 ${pair} second" "7d520000-0113-${run_token}-000${n}b" '+1 773 555 0113'
  pair_ids="$(run_psql --tuples-only --no-align --field-separator='|' --command="
    SELECT ordered_ids[1]::text, ordered_ids[2]::text
    FROM (
      SELECT array_agg(promotion_target_id ORDER BY promotion_target_id) AS ordered_ids
      FROM app_data.promotion_targets
      WHERE workspace_id = '${workspace_id}'::uuid
        AND display_name IN (
          'Pair preview 0113 ${pair} first',
          'Pair preview 0113 ${pair} second'
        )
    ) AS pair;
  ")"
  IFS='|' read -r pair_first pair_second <<<"$(tr -d '[:space:]' <<<"${pair_ids}")"
  if [[ ! "${pair_first}" =~ ^[0-9a-f-]{36}$ || ! "${pair_second}" =~ ^[0-9a-f-]{36}$ ]]; then
    echo "pair preview ${pair} fixture 未能稳定创建两个目标。" >&2
    exit 1
  fi
  case "${pair}" in
    contact) contact_first="${pair_first}"; contact_second="${pair_second}";;
    renewal) renewal_first="${pair_first}"; renewal_second="${pair_second}";;
    assignment) assignment_first="${pair_first}"; assignment_second="${pair_second}";;
    cutoff) cutoff_first="${pair_first}"; cutoff_second="${pair_second}";;
  esac
done
run_psql --quiet --command="
  SELECT app_data.configure_promotion_target_retention_policy(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, 12
  );
" >/dev/null

# The first pair's deadline is based on a real current-revision contact link.
# Revision 2 moves the current link to the sibling, changing retention facts.
contact_id="7d520000-0113-contact-${run_token}"
run_psql --quiet --command="
  INSERT INTO app_data.contacts (
    contact_id, app_user_id, workspace_id, project_id,
    questionnaire_version_id, occurred_at_utc, occurred_time_zone,
    channel, location_kind, reach_count, interest_level
  ) VALUES (
    '${contact_id}', '${app_user_id}'::uuid, '${workspace_id}'::uuid,
    '${project_id}'::uuid, '${questionnaire_version_id}'::uuid,
    clock_timestamp() + interval '2 days', 'UTC', 'instant_text',
    'not_applicable', 1, 0
  );
  INSERT INTO app_data.contact_revisions (
    contact_id, revision_number, revised_by_app_user_id, snapshot
  ) VALUES ('${contact_id}', 1, '${app_user_id}'::uuid, '{}'::jsonb);
  INSERT INTO app_data.contact_target_links (
    contact_id, revision_number, promotion_target_id, response_level,
    follow_up_consent, institution_representative_confirmed,
    confirmed_project_entry
  ) VALUES (
    '${contact_id}', 1, '${contact_first}'::uuid, NULL, 'unknown', false, false
  );
" >/dev/null

preview_sql() {
  local label="$1" gate="$2"
  cat <<SQL
SET app_data.personal_target_pair_preview_test_gate = '${gate}';
SELECT 'PREVIEW|' || row_to_json(receipt)::text
FROM app_data.preview_personal_target_pair_v1(
  '${issuer}', '${subject}', '${project_id}'::uuid,
  '${first_target_id}'::uuid, '${second_target_id}'::uuid
) AS receipt;
SQL
}

run_stale_race() {
  local label="$1" first_target_id="$2" second_target_id="$3" mutation_sql="$4" gate="7d520000-0113-${1}"
  local app_name="0113-pair-preview-${label}" output="${temporary_directory}/${label}.out"
  local expected_facts
  expected_facts="$(run_psql --tuples-only --no-align --command="
    SELECT jsonb_build_object(
      'first_target_id', first_target.promotion_target_id,
      'second_target_id', second_target.promotion_target_id,
      'first_profile_revision', first_target.profile_revision,
      'second_profile_revision', second_target.profile_revision,
      'first_assignment_id', first_assignment.assignment_id,
      'second_assignment_id', second_assignment.assignment_id,
      'first_retention_due_at_utc',
        app_data.promotion_target_review_due_at(first_target.promotion_target_id),
      'second_retention_due_at_utc',
        app_data.promotion_target_review_due_at(second_target.promotion_target_id),
      'phone_match', true,
      'email_match', true
    )
    FROM app_data.promotion_targets AS first_target
    JOIN app_data.promotion_targets AS second_target
      ON second_target.promotion_target_id = '${second_target_id}'::uuid
    JOIN app_data.promotion_target_assignments AS first_assignment
      ON first_assignment.promotion_target_id = first_target.promotion_target_id
     AND first_assignment.app_user_id = '${app_user_id}'::uuid
     AND first_assignment.ended_at IS NULL
    JOIN app_data.promotion_target_assignments AS second_assignment
      ON second_assignment.promotion_target_id = second_target.promotion_target_id
     AND second_assignment.app_user_id = '${app_user_id}'::uuid
     AND second_assignment.ended_at IS NULL
    WHERE first_target.promotion_target_id = '${first_target_id}'::uuid;
  ")"
  start_gate "${gate}"
  PGAPPNAME="${app_name}" run_psql --quiet --tuples-only --no-align \
    --command="$(preview_sql "${label}" "${gate}")" >"${output}" 2>&1 &
  local preview_pid=$!
  child_pids+=("${preview_pid}")
  wait_for_lock_waiter "${app_name}" "${output}"
  run_psql --quiet --command="${mutation_sql}" >/dev/null
  release_gate
  local status=0
  wait "${preview_pid}" || status=$?
  if [[ "${status}" -ne 0 ]]; then
    echo "${label} preview 应返回 mutation 提交前的一致快照：status=${status}" >&2
    sed -n '1,120p' "${output}" >&2
    exit 1
  fi
  local receipt preview_id preview_time expiry_time
  receipt="$(awk -F'|' '/^PREVIEW\|/ { sub(/^[^|]*\|/, ""); print; exit }' "${output}")"
  preview_id="$(sed -E 's/.*"preview_id":"([^"]+)".*/\1/' <<<"${receipt}")"
  preview_time="$(sed -E 's/.*"previewed_at_utc":"([^"]+)".*/\1/' <<<"${receipt}")"
  expiry_time="$(sed -E 's/.*"expires_at_utc":"([^"]+)".*/\1/' <<<"${receipt}")"
  if [[ ! "${preview_id}" =~ ^[0-9a-f-]{36}$ || -z "${preview_time}" || -z "${expiry_time}" ]]; then
    echo "${label} 未返回完整 preview receipt。" >&2
    sed -n '1,120p' "${output}" >&2
    exit 1
  fi
  local actual_facts
  actual_facts="$(run_psql --tuples-only --no-align --command="
    SELECT jsonb_build_object(
      'first_target_id', first_target_id,
      'second_target_id', second_target_id,
      'first_profile_revision', first_profile_revision,
      'second_profile_revision', second_profile_revision,
      'first_assignment_id', first_assignment_id,
      'second_assignment_id', second_assignment_id,
      'first_retention_due_at_utc', first_retention_due_at_utc,
      'second_retention_due_at_utc', second_retention_due_at_utc,
      'phone_match', phone_match,
      'email_match', email_match
    )
    FROM app_private.personal_target_pair_preview_receipts
    WHERE preview_id = '${preview_id}'::uuid;
  ")"
  if [[ "${actual_facts}" != "${expected_facts}" ]]; then
    echo "${label} receipt 混合了 mutation 前后的 facts。" >&2
    printf 'expected: %s\nactual:   %s\n' "${expected_facts}" "${actual_facts}" >&2
    exit 1
  fi
  local validation_count
  validation_count="$(run_psql --tuples-only --no-align --command="
    SELECT count(*) FROM app_private.validate_personal_target_pair_preview_v1(
      '${app_user_id}'::uuid, '${project_id}'::uuid, '${preview_id}'::uuid,
      clock_timestamp()
    );
  " | tr -d '[:space:]')"
  if [[ "${validation_count}" != '0' ]]; then
    echo "${label} 变更提交后的 receipt 未被 validator 判 stale/forbidden。" >&2
    exit 1
  fi
}

# Hold receipt insertion after facts have been materialized. Each independent
# mutation commits before the preview continues, so it must return one coherent
# old snapshot whose validator is stale.
run_psql --quiet --command="
  CREATE FUNCTION app_private.personal_target_pair_preview_test_gate_v1()
  RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS \$function\$
  DECLARE gate text := current_setting('app_data.personal_target_pair_preview_test_gate', true);
  BEGIN
    IF gate IS NOT NULL AND gate <> '' THEN
      PERFORM pg_advisory_xact_lock(hashtextextended(gate, 0));
    END IF;
    RETURN NEW;
  END
  \$function\$;
  CREATE TRIGGER personal_target_pair_preview_test_gate
  BEFORE INSERT ON app_private.personal_target_pair_preview_receipts
  FOR EACH ROW EXECUTE FUNCTION app_private.personal_target_pair_preview_test_gate_v1();
" >/dev/null

run_stale_race 'contact-current-revision' "${contact_first}" "${contact_second}" "
  BEGIN;
  INSERT INTO app_data.contact_revisions (
    contact_id, revision_number, revised_by_app_user_id, snapshot,
    revision_kind, reason
  ) VALUES (
    '${contact_id}', 2, '${app_user_id}'::uuid, '{}'::jsonb,
    'corrected', '0113 concurrency fixture'
  );
  INSERT INTO app_data.contact_target_links (
    contact_id, revision_number, promotion_target_id, response_level,
    follow_up_consent, institution_representative_confirmed,
    confirmed_project_entry
  ) VALUES (
    '${contact_id}', 2, '${contact_second}'::uuid, NULL, 'unknown', false, false
  );
  UPDATE app_data.contacts SET current_revision = 2
  WHERE contact_id = '${contact_id}';
  COMMIT;
"

run_stale_race 'renewal-event' "${renewal_first}" "${renewal_second}" "
  SELECT app_data.apply_promotion_target_retention_action(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    '${renewal_first}'::uuid, 'renew', 'purpose_confirmed',
    '7d530000-0113-${run_token}-renew'
  );
"
run_stale_race 'assignment-end' "${assignment_first}" "${assignment_second}" "
  UPDATE app_data.promotion_target_assignments
  SET ended_at = clock_timestamp(), end_reason = '0113 concurrency fixture'
  WHERE promotion_target_id = '${assignment_first}'::uuid
    AND app_user_id = '${app_user_id}'::uuid AND ended_at IS NULL;
"

run_psql --quiet --command="
  DROP TRIGGER personal_target_pair_preview_test_gate
    ON app_private.personal_target_pair_preview_receipts;
  DROP FUNCTION app_private.personal_target_pair_preview_test_gate_v1();
  SELECT app_data.configure_promotion_target_retention_policy(
    '${app_user_id}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid, 1
  );
  UPDATE app_data.promotion_targets
  SET created_at = clock_timestamp() - interval '1 month' + interval '4 seconds'
  WHERE promotion_target_id IN ('${cutoff_first}'::uuid, '${cutoff_second}'::uuid);
" >/dev/null

# Four seconds after creation-relative one-month retention expiry is enough for
# a deterministic relation-lock wait without making the runner sleep minutes.
mkfifo "${temporary_directory}/cutoff-gate.fifo"
"${psql_base[@]}" <"${temporary_directory}/cutoff-gate.fifo" \
  >"${temporary_directory}/cutoff-gate.out" 2>&1 &
cutoff_gate_pid=$!
child_pids+=("${cutoff_gate_pid}")
exec 4>"${temporary_directory}/cutoff-gate.fifo"
printf 'BEGIN; LOCK TABLE app_data.promotion_target_retention_events IN ACCESS EXCLUSIVE MODE;\n' >&4
for _ in $(seq 1 100); do
  [[ "$(run_psql --tuples-only --no-align --command="SELECT EXISTS (SELECT 1 FROM pg_locks WHERE relation = 'app_data.promotion_target_retention_events'::regclass AND mode = 'AccessExclusiveLock' AND granted)" | tr -d '[:space:]')" == 't' ]] && break
  sleep 0.05
done
PGAPPNAME='0113-pair-preview-retention-cutoff' run_psql --quiet --tuples-only --no-align \
  --command="SELECT 'PREVIEW|' || row_to_json(receipt)::text FROM app_data.preview_personal_target_pair_v1('${issuer}', '${subject}', '${project_id}'::uuid, '${cutoff_first}'::uuid, '${cutoff_second}'::uuid) AS receipt;" \
  >"${temporary_directory}/cutoff-preview.out" 2>&1 &
cutoff_preview_pid=$!
child_pids+=("${cutoff_preview_pid}")
wait_for_lock_waiter '0113-pair-preview-retention-cutoff' "${temporary_directory}/cutoff-preview.out"
sleep 5
printf 'COMMIT;\\q\n' >&4
exec 4>&-
rm -f "${temporary_directory}/cutoff-gate.fifo"
cutoff_status=0
wait "${cutoff_gate_pid}" || cutoff_status=$?
wait "${cutoff_preview_pid}" || cutoff_status=$?
if [[ "${cutoff_status}" -eq 0 ]] \
  || ! grep -Fq '42501' "${temporary_directory}/cutoff-preview.out" \
  || ! grep -Fq 'personal target pair preview is forbidden' "${temporary_directory}/cutoff-preview.out"; then
  echo '跨过 retention cutoff 后必须 generic forbidden 且不生成 preview。' >&2
  sed -n '1,120p' "${temporary_directory}/cutoff-preview.out" >&2
  exit 1
fi
for private_value in 'Pair preview 0113 cutoff first' 'Pair preview 0113 cutoff second' \
  '+1 773 555 0113' 'pair-0113@example.test'; do
  if grep -Fq "${private_value}" "${temporary_directory}/cutoff-preview.out"; then
    echo 'retention cutoff failure 将 target PII 返回到了错误输出。' >&2
    sed -n '1,120p' "${temporary_directory}/cutoff-preview.out" >&2
    exit 1
  fi
done

cutoff_counts="$(run_psql --tuples-only --no-align --field-separator='|' --command="
  SELECT
    (SELECT count(*) FROM app_private.personal_target_pair_preview_receipts WHERE actor_app_user_id = '${app_user_id}'::uuid),
    (SELECT count(*) FROM app_data.promotion_target_access_events WHERE actor_app_user_id = '${app_user_id}'::uuid AND action = 'viewed'),
    (SELECT count(*) FROM app_private.personal_target_pair_preview_audit_events WHERE actor_app_user_id = '${app_user_id}'::uuid),
    (SELECT count(*) FROM app_data.promotion_targets WHERE promotion_target_id IN ('${cutoff_first}'::uuid, '${cutoff_second}'::uuid) AND (display_name NOT LIKE 'Pair preview 0113 cutoff %' OR phone <> '+1 773 555 0113' OR email <> 'pair-0113@example.test' OR status <> 'active'));
")"
IFS='|' read -r receipt_count access_count audit_count altered_pii_count <<<"$(tr -d '[:space:]' <<<"${cutoff_counts}")"
if [[ "${receipt_count}" -ne 3 || "${access_count}" -ne 6 || "${audit_count}" -ne 3 || "${altered_pii_count}" -ne 0 ]]; then
  echo "retention cutoff failure 留下非原子写入或更改 PII：${cutoff_counts}" >&2
  exit 1
fi

expiry_ok="$(run_psql --tuples-only --no-align --command="
  SELECT count(*) = 3 AND bool_and(expires_at_utc = previewed_at_utc + interval '15 minutes')
  FROM app_private.personal_target_pair_preview_receipts
  WHERE actor_app_user_id = '${app_user_id}'::uuid;
" | tr -d '[:space:]')"
if [[ "${expiry_ok}" != 't' ]]; then
  echo 'preview receipt expiry 不是精确 15 分钟。' >&2
  exit 1
fi

echo '个人目标 pair preview 并发检查通过：三类并发提交均产生一致但 stale 的 preview；retention cutoff 后 generic failure 且没有副作用，expiry 精确 15 分钟。'
