#!/usr/bin/env bash

set -euo pipefail

: "${DATABASE_URL:?请设置 synthetic PostgreSQL DATABASE_URL}"
psql_command="${PSQL_COMMAND:-psql}"
export PGOPTIONS="${PGOPTIONS:-} -c timezone=UTC -c statement_timeout=120000 -c lock_timeout=30000"
psql_base=("${psql_command}" "${DATABASE_URL}" --no-psqlrc --set=ON_ERROR_STOP=1 --set=VERBOSITY=verbose)
run_psql() { "${psql_base[@]}" "$@"; }
temporary_directory="$(mktemp -d)"
holder_pid=''
waiter_pid=''
cleanup() {
  local pid
  exec 3>&- 2>/dev/null || true
  for pid in "$holder_pid" "$waiter_pid"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" >/dev/null 2>&1; then kill "$pid" >/dev/null 2>&1 || true; fi
    wait "$pid" >/dev/null 2>&1 || true
  done
  rm -f "$temporary_directory/holder.fifo" "$temporary_directory/holder.out" "$temporary_directory/waiter.out" "$temporary_directory/isolation.out"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
assert_true() {
  local result
  result="$(run_psql --tuples-only --no-align --command="$2" | tr -d '[:space:]')"
  [[ "$result" == t ]] || { echo "0143 $1 invariant failed: $result" >&2; exit 1; }
}
run_token="$(date -u +%Y%m%d%H%M%S)-$$"
issuer='https://7ff-resolution-confirmation.example.test/auth/v1'
subject="7ff-owner-$run_token"
run_psql --quiet --command="SELECT * FROM app_data.bootstrap_personal_context('$issuer','$subject');" >/dev/null
context="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT app_user_id,workspace_id,project_id,questionnaire_version_id
  FROM app_data.list_personal_project_contexts('$issuer','$subject') WHERE is_current;" | tr -d '[:space:]')"
IFS='|' read -r app_user_id workspace_id project_id questionnaire_version_id <<<"$context"
for context_id in "$app_user_id" "$workspace_id" "$project_id" "$questionnaire_version_id"; do
  [[ "$context_id" =~ ^[0-9a-f-]{36}$ ]] || { echo '0143 missing personal context。' >&2; exit 1; }
done
state_query="$(run_psql --tuples-only --no-align --command="SELECT
  'SELECT jsonb_object_agg(table_name,rows ORDER BY table_name) FROM (' || string_agg(format(
    'SELECT %L AS table_name,coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) AS rows FROM %I.%I t',
    schemaname||'.'||tablename,schemaname,tablename),' UNION ALL ' ORDER BY schemaname,tablename)||') state;'
  FROM pg_catalog.pg_tables WHERE schemaname IN ('app_data','app_private');")"
business_state() { run_psql --tuples-only --no-align --command="$state_query"; }

other_project_id="$(run_psql --tuples-only --no-align --command="SELECT project_id FROM app_data.create_personal_project_context('$issuer','$subject','0143 other project');")"
run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('$issuer','$subject','$project_id');" >/dev/null
stage_project_sql() {
  printf '%s' "SELECT * FROM app_private.stage_unassigned_personal_merge_project_relationship_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id',2,'paused',
    '0143 raw pending note','progress_update',NULL);"
}
stage_contact_sql() {
  printf '%s' "SELECT app_private.stage_unassigned_personal_merge_contact_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id','$1',$2,2,'yes',false,true);"
}
ordinary_project_sql() {
  printf '%s' "SELECT * FROM app_data.update_promotion_target_relationship(
    '$app_user_id','$workspace_id','$project_id','${4:-$first_target}',$1,$3,'active',
    '0143 ordinary note','progress_update',NULL,'$2',NULL)"
}
ordinary_contact_sql() {
  printf '%s' "SELECT result_code FROM app_data.apply_contact_revise_v3('$app_user_id','$2',1,'contact.revise.v1',
    '7ff-device','$contact_id',$1,(SELECT snapshot||jsonb_build_object('reason','0143 ordinary revision','interestLevel',4)
      FROM app_data.contact_revisions WHERE contact_id='$contact_id' AND revision_number=$1))"
}
ordinary_entry_sql() {
  local key="7ff-$run_token-entry-$request_id"
  printf '%s' "SELECT * FROM app_data.apply_contact_submit_v3('$app_user_id','$key-submit',1,'contact.submit.v1','7ff-device','$key',0,
    jsonb_build_object('contactId','$key','workspaceId','$workspace_id','projectId','$project_id','questionnaireVersionId','$questionnaire_version_id',
      'reason','0143 real ordinary entry race','occurredAtUtc','2020-01-02T00:00:00Z','occurredTimeZone','UTC','channel','video_call',
      'location',jsonb_build_object('kind','not_applicable'),'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,
      'targetLinks',jsonb_build_array(jsonb_build_object('targetId','$first_target','targetType','person','responseLevel',NULL,
        'followUpConsent','unknown','institutionRepresentativeConfirmed',false,'confirmStageZero',true))))"
}
new_generation() {
  local label="$1" source key preview_id fingerprints
  first_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0143 first $label $run_token','+1 312 555 0143',NULL,'7ff-$label-$run_token-first');")"
  second_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0143 second $label $run_token','+1 312 555 0143',NULL,'7ff-$label-$run_token-second');")"
  nonpair_target="$(run_psql --tuples-only --no-align --command="SELECT target->>'target_id' FROM app_data.create_promotion_target(
    '$app_user_id','$workspace_id','$project_id','person','0143 nonpair $label $run_token',NULL,NULL,'7ff-$label-$run_token-nonpair');")"
  for source in "$second_target" "$nonpair_target"; do
    key="7ff-entry-$label-$run_token-$source"
    assert_true real-project-entry "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
      '$app_user_id','$key-submit',1,'contact.submit.v1','7ff-device','$key',0,
      jsonb_build_object('contactId','$key','workspaceId','$workspace_id','projectId','$project_id',
        'questionnaireVersionId','$questionnaire_version_id','reason','0143 real entry','occurredAtUtc','2020-01-01T00:00:00Z',
        'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
        'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(jsonb_build_object(
          'targetId','$source','targetType','person','responseLevel',NULL,'followUpConsent','unknown',
          'institutionRepresentativeConfirmed',false,'confirmStageZero',true))));"
  done
  preview_id="$(run_psql --tuples-only --no-align --command="SELECT preview_id FROM app_data.preview_personal_target_pair_v1(
    '$issuer','$subject','$project_id','$first_target','$second_target');")"
  generation_id="$(run_psql --tuples-only --no-align --command="SELECT app_private.activate_personal_target_merge_generation_v2(
    '$app_user_id','$project_id',gen_random_uuid(),'$preview_id','$first_target','$first_target','$first_target','$second_target');")"
  contact_id="7ff-contact-$label-$run_token"
  late_contact_id="$contact_id-late"
  for key in "$contact_id" "$late_contact_id"; do
    assert_true contact-submit "SELECT result_code='accepted' FROM app_data.apply_contact_submit_v3(
      '$app_user_id','$key-submit',1,'contact.submit.v1','7ff-device','$key',0,
      jsonb_build_object('contactId','$key','workspaceId','$workspace_id','projectId','$project_id',
        'questionnaireVersionId','$questionnaire_version_id','reason','0143 original contact','occurredAtUtc','2025-01-02T03:04:05Z',
        'occurredTimeZone','UTC','channel','video_call','location',jsonb_build_object('kind','not_applicable'),
        'reachCount',1,'interestLevel',2,'answers','[]'::jsonb,'targetLinks',jsonb_build_array(jsonb_build_object(
          'targetId','$nonpair_target','targetType','person','responseLevel',1,'followUpConsent','no',
          'institutionRepresentativeConfirmed',false,'confirmStageZero',true))));"
  done
  run_psql --quiet --command="$(stage_contact_sql "$contact_id" 1)" >/dev/null
  assert_true contact-revise "SELECT result_code='accepted' FROM app_data.apply_contact_revise_v3(
    '$app_user_id','$contact_id-revise',1,'contact.revise.v1','7ff-device','$contact_id',1,
    (SELECT snapshot||jsonb_build_object('reason','0143 current contact','interestLevel',3,
      'targetLinks',jsonb_build_array(jsonb_build_object('targetId','$nonpair_target','targetType','person',
        'responseLevel',3,'followUpConsent','no','institutionRepresentativeConfirmed',false,'confirmStageZero',true)))
    FROM app_data.contact_revisions WHERE contact_id='$contact_id' AND revision_number=1));"
  run_psql --quiet --command="$(stage_contact_sql "$contact_id" 2) $(stage_project_sql) $(stage_project_sql)" >/dev/null
  request_id="$(run_psql --tuples-only --no-align --command='SELECT gen_random_uuid();')"
  fingerprints="$(run_psql --tuples-only --no-align --field-separator='|' --command="SELECT
    contact->'known_source_plan'->>'fact_fingerprint',contact->>'pending_fingerprint',project->>'pending_fingerprint'
    FROM (SELECT app_private.read_personal_merge_unassigned_contact_plan_v1(
      '$app_user_id','$workspace_id','$project_id','$generation_id') contact,
      app_private.read_personal_merge_unassigned_project_relationship_plan_v1(
      '$app_user_id','$workspace_id','$project_id','$generation_id') project) inventories;")"
  IFS='|' read -r known_fingerprint contact_pending_fingerprint project_pending_fingerprint <<<"$fingerprints"
  contact_assignments="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'pending_fact_id',pending_fact_id,'source_target_id','$first_target') ORDER BY pending_fact_id)
    FROM app_private.personal_merge_unassigned_contact_requests_v1 WHERE generation_id='$generation_id';")"
  project_assignments="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'pending_fact_id',pending_fact_id,'source_target_id','$first_target') ORDER BY pending_fact_id)
    FROM app_private.personal_merge_unassigned_project_relationship_requests_v1 WHERE generation_id='$generation_id';")"
  plan_sql="SELECT app_private.plan_personal_merge_mixed_resolutions_v1(
    '$app_user_id','$workspace_id','$project_id','$generation_id',
    '$known_fingerprint','$contact_pending_fingerprint','$project_pending_fingerprint',
    '$contact_assignments'::jsonb,'$project_assignments'::jsonb)"
  resolution_plan="$(run_psql --tuples-only --no-align --command="$plan_sql;")"
  resolution_fingerprint="$(run_psql --tuples-only --no-align --command="SELECT '$resolution_plan'::jsonb->>'resolution_fingerprint';")"
  contact_choices="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'contact_id',slot->>'contact_id','source_target_id',slot->>'source_target_id','candidate_kind','pending',
    'pending_fact_id',slot->'pending_fact_ids'->0))
    FROM jsonb_array_elements('$resolution_plan'::jsonb->'contact_resolution_plan'->'source_slots') slot;")"
  project_choices="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(jsonb_build_object(
    'project_id',slot->>'project_id','source_target_id',slot->>'source_target_id','candidate_kind','pending',
    'pending_fact_id',slot->'pending_fact_ids'->0))
    FROM jsonb_array_elements('$resolution_plan'::jsonb->'project_relationship_resolution_plan'->'source_slots') slot;")"
  acknowledgements="$(run_psql --tuples-only --no-align --command="SELECT coalesce(jsonb_agg(jsonb_build_object(
    'project_id',choice->>'project_id','source_target_id',choice->>'source_target_id','pending_fact_id',choice->>'pending_fact_id')),'[]'::jsonb)
    FROM jsonb_array_elements('$project_choices'::jsonb) choice
    JOIN jsonb_array_elements('$resolution_plan'::jsonb->'project_relationship_resolution_plan'->'source_slots') slot
      ON slot->>'project_id'=choice->>'project_id' AND slot->>'source_target_id'=choice->>'source_target_id'
    WHERE slot->'current_relationship'='null'::jsonb;")"
  confirm_sql="SELECT app_private.confirm_personal_merge_mixed_resolutions_v2(
    '$app_user_id','$workspace_id','$project_id','$request_id','$generation_id',
    '$known_fingerprint','$contact_pending_fingerprint','$project_pending_fingerprint','$resolution_fingerprint',
    '$contact_assignments'::jsonb,'$contact_choices'::jsonb,'$project_assignments'::jsonb,'$project_choices'::jsonb,'$acknowledgements'::jsonb);"
  rollback_confirm_sql="BEGIN; $confirm_sql DO \$proof\$ BEGIN
    IF NOT app_private.personal_merge_mixed_resolution_proof_v1('$app_user_id','$request_id')
      OR NOT app_private.personal_merge_mixed_project_entry_resolution_proof_v1('$app_user_id','$request_id') THEN
      RAISE EXCEPTION '0143 rolled-back confirmation lacks complete proof';
    END IF; END \$proof\$; ROLLBACK;"
  due_sql="UPDATE app_data.promotion_targets SET created_at=clock_timestamp()-interval '2 years'
    WHERE promotion_target_id IN ('$first_target','$second_target');"
  expiry_sql="SELECT app_private.expire_known_source_personal_target_merge_generation_v1(
    '$app_user_id','$workspace_id','$project_id',gen_random_uuid(),'$generation_id');"
}
wait_for_holder() {
  local ready
  for _ in $(seq 1 100); do
    ready="$(run_psql --tuples-only --no-align --command="SELECT CASE WHEN pg_try_advisory_lock(hashtextextended('$1',0))
      THEN NOT pg_advisory_unlock(hashtextextended('$1',0)) ELSE true END;" | tr -d '[:space:]')"
    [[ "$ready" == t ]] && return
    sleep 0.05
  done
  echo '0143 holder not ready。' >&2
  sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2
  exit 1
}
wait_for_exact_blocker() {
  local waiter_app="$1" holder_app="$2" key="$3" pair lock_predicate
  lock_predicate="locks.locktype='transactionid' AND locks.transactionid=holder.backend_xid"
  if [[ "$key" == row:* ]]; then
    lock_predicate="$lock_predicate AND EXISTS(SELECT 1 FROM pg_locks tuple_lock WHERE tuple_lock.pid=waiter.pid
      AND tuple_lock.locktype='tuple' AND tuple_lock.relation='${key#row:}'::regclass)"
  elif [[ -n "$key" ]]; then
    lock_predicate="locks.locktype='advisory' AND locks.objsubid=1 AND locks.database=(SELECT oid FROM pg_database WHERE datname=current_database())
      AND locks.classid=((hashtextextended('$key',0)>>32)&4294967295)::oid
      AND locks.objid=(hashtextextended('$key',0)&4294967295)::oid"
  fi
  for _ in $(seq 1 300); do
    pair="$(run_psql --tuples-only --no-align --command="SELECT waiter.pid||'|'||holder.pid||'|'||locks.locktype||'|'||
      coalesce(locks.transactionid::text,locks.classid::text||':'||locks.objid::text)
      FROM pg_stat_activity waiter JOIN LATERAL unnest(pg_blocking_pids(waiter.pid)) blocked(pid) ON true
      JOIN pg_stat_activity holder ON holder.pid=blocked.pid JOIN pg_locks locks ON locks.pid=waiter.pid AND NOT locks.granted
      WHERE waiter.application_name='$waiter_app' AND holder.application_name='$holder_app'
        AND waiter.wait_event_type='Lock' AND $lock_predicate;" | tr -d '[:space:]')"
    [[ "$pair" == *'|'* ]] && { echo "0143 $waiter_app exact waiter/holder PID and lock: $pair"; return; }
    sleep 0.05
  done
  echo '0143 exact blocker or requested lock missing.' >&2
  run_psql --command="SELECT activity.pid,activity.application_name,pg_blocking_pids(activity.pid),locks.locktype,locks.mode,locks.granted,
    locks.relation::regclass,locks.transactionid,locks.classid,locks.objid,locks.objsubid FROM pg_stat_activity activity
    LEFT JOIN pg_locks locks ON locks.pid=activity.pid WHERE activity.application_name IN ('$waiter_app','$holder_app')
    ORDER BY activity.pid,locks.granted,locks.locktype;" >&2
  sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
  exit 1
}
run_race() {
  local label="$1" holder_sql="$2" waiter_sql="$3" expected_sqlstate="$4" key="${5:-}" after_wait_sql="${6:-}"
  local holder_app="7ff-holder-$label-$run_token" waiter_app="7ff-waiter-$label-$run_token"
  local ready_key="7ff-ready-$label-$run_token" status=0 expected_state probe_sql="${7:-}"
  mkfifo "$temporary_directory/holder.fifo"
  PGAPPNAME="$holder_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    <"$temporary_directory/holder.fifo" >"$temporary_directory/holder.out" 2>&1 &
  holder_pid=$!
  exec 3>"$temporary_directory/holder.fifo"
  printf "BEGIN; %s SELECT pg_advisory_lock(hashtextextended('%s',0));\n" "$holder_sql" "$ready_key" >&3
  wait_for_holder "$ready_key"
  PGAPPNAME="$waiter_app" "${psql_base[@]}" --quiet --tuples-only --no-align \
    --command="$waiter_sql" >"$temporary_directory/waiter.out" 2>&1 &
  waiter_pid=$!
  wait_for_exact_blocker "$waiter_app" "$holder_app" "$key"
  if [[ -n "$probe_sql" ]]; then
    probe_sql="${probe_sql//__MIXED_WAITER__/$waiter_app}"
    assert_true "$label-prelock" "$probe_sql"
  fi
  printf '%s %s COMMIT;\\q\n' "$after_wait_sql" "$state_query" >&3
  exec 3>&-
  wait "$holder_pid" || { sed -n '/ERROR:/p' "$temporary_directory/holder.out" >&2; exit 1; }
  holder_pid=''
  rm -f "$temporary_directory/holder.fifo"
  expected_state="$(sed -n '/^{"app_data\./p' "$temporary_directory/holder.out")"
  [[ -n "$expected_state" ]] || { echo '0143 missing holder snapshot。' >&2; exit 1; }
  wait "$waiter_pid" || status=$?
  waiter_pid=''
  if [[ "$expected_sqlstate" == unchanged ]]; then
    [[ "$status" -eq 0 ]] || { sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2; exit 1; }
  elif [[ "$status" -eq 0 ]] || ! grep -q "ERROR:  $expected_sqlstate:" "$temporary_directory/waiter.out"; then
    echo "0143 $label expected $expected_sqlstate, status $status。" >&2
    sed -n '/ERROR:/p' "$temporary_directory/waiter.out" >&2
    exit 1
  fi
  [[ "$expected_state" == "$(business_state)" ]] || { echo "0143 $label waiter changed persistent state。" >&2; exit 1; }
}

fence_row='row:app_private.personal_target_merge_generation_fence_v1'
no_application_writes="SELECT NOT EXISTS (
  SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
  WHERE activity.application_name='__MIXED_WAITER__' AND locks.granted AND locks.mode='RowExclusiveLock'
    AND locks.relation IN ('app_data.contact_revisions'::regclass,
      'app_private.personal_merge_contact_history_applications_v1'::regclass,
      'app_private.personal_merge_project_relationship_history_applications_v1'::regclass,
      'app_private.personal_merge_mixed_resolution_requests_v1'::regclass,
      'app_private.personal_merge_mixed_project_entry_requests_v1'::regclass,
      'app_data.promotion_target_project_relationships'::regclass,
      'app_data.promotion_target_relationship_revisions'::regclass));"

new_generation child-prelock
child_id="$(run_psql --tuples-only --no-align --command="SELECT
  'personal-merge-contact-resolve-v1:$request_id:pending:'||pending_fact_id
  FROM app_private.personal_merge_unassigned_contact_requests_v1
  WHERE generation_id='$generation_id' ORDER BY pending_fact_id LIMIT 1;")"
child_probe="SELECT NOT EXISTS (
  SELECT 1 FROM pg_locks locks JOIN pg_stat_activity activity ON activity.pid=locks.pid
  WHERE activity.application_name='__MIXED_WAITER__' AND locks.granted AND locks.mode='RowExclusiveLock'
    AND locks.relation='app_private.personal_target_merge_generation_fence_v1'::regclass);"
run_race child-prelock "SELECT pg_advisory_xact_lock(hashtextextended('$app_user_id:$child_id',0));" \
  "$rollback_confirm_sql" unchanged "$app_user_id:$child_id" '' "$child_probe"

new_generation ordinary-contact-first
run_race ordinary-contact-first "$(ordinary_contact_sql 2 "7ff-contact-first-$run_token");" \
  "$confirm_sql" 23505 "contact:$contact_id"
assert_true ordinary-contact-retained "SELECT current_revision=3 AND interest_level=4
  FROM app_data.contacts WHERE contact_id='$contact_id';"

new_generation ordinary-project-first
run_race ordinary-project-first "$(ordinary_project_sql 1 "7ff-project-first-$run_token" 3 "$second_target");" \
  "$confirm_sql" 23505 "$fence_row"
assert_true ordinary-project-retained "SELECT current_revision=2 AND current_stage=3
  FROM app_data.promotion_target_project_relationships WHERE promotion_target_id='$second_target' AND project_id='$project_id';"

new_generation mixed-before-contact
ordinary_after="BEGIN; DO \$test\$ DECLARE code text; BEGIN
  SELECT changed.result_code INTO STRICT code FROM ($(ordinary_contact_sql 2 "7ff-contact-after-$run_token")) changed;
  IF code IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0143 ordinary contact writer rejected a compatible revision'; END IF;
END \$test\$; ROLLBACK;"
run_race mixed-before-contact "$confirm_sql" "$ordinary_after" unchanged "contact:$contact_id"
assert_true contact-final-head "SELECT current_revision=5 FROM app_data.contacts WHERE contact_id='$contact_id';"

new_generation mixed-before-project
# The ordinary updater checks existence before locking, so use a visible relation.
ordinary_after="BEGIN; DO \$test\$ DECLARE result jsonb; BEGIN
  SELECT changed.result INTO STRICT result FROM ($(ordinary_project_sql 1 "7ff-project-after-$run_token" 3 "$second_target")) changed;
  IF result->>'status' IS DISTINCT FROM 'accepted' THEN RAISE EXCEPTION '0143 ordinary project writer rejected the existing relation'; END IF;
END \$test\$; ROLLBACK;"
run_race mixed-before-project "$confirm_sql" "$ordinary_after" unchanged "$fence_row"
assert_true project-final-head "SELECT current_revision=4 AND current_stage=2
  FROM app_data.promotion_target_project_relationships WHERE promotion_target_id='$first_target' AND project_id='$project_id';"

new_generation ordinary-entry-first
run_race ordinary-entry-first "$(ordinary_entry_sql);" "$confirm_sql" 23505 "$fence_row"
assert_true real-entry-not-reinitialized "SELECT current_revision=1 AND current_stage=0 FROM app_data.promotion_target_project_relationships
  WHERE promotion_target_id='$first_target' AND project_id='$project_id';"

new_generation mixed-before-ordinary-entry
ordinary_entry_after="BEGIN; DO \$test\$ DECLARE code text; BEGIN
  SELECT result_code INTO STRICT code FROM ($(ordinary_entry_sql)) submitted;
  IF code IS DISTINCT FROM 'accepted' OR NOT EXISTS(SELECT 1 FROM app_data.promotion_target_project_relationships
    WHERE promotion_target_id='$first_target' AND project_id='$project_id' AND current_revision=4 AND current_stage=2)
    THEN RAISE EXCEPTION '0143 ordinary entry did not retain mixed confirmed head'; END IF;
END \$test\$; ROLLBACK;"
run_race mixed-before-ordinary-entry "$confirm_sql" "$ordinary_entry_after" unchanged "$fence_row"

new_generation project-growth
run_race project-growth 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$confirm_sql" 23505 "$fence_row" "$(stage_project_sql)"

new_generation contact-growth
run_race contact-growth 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$confirm_sql" 23505 "$fence_row" "$(stage_contact_sql "$late_contact_id" 1)"

new_generation mixed-before-project-stage
run_race mixed-before-project-stage "$confirm_sql" "$(stage_project_sql)" 42501 "$fence_row"

new_generation mixed-before-contact-stage
run_race mixed-before-contact-stage "$confirm_sql" "$(stage_contact_sql "$late_contact_id" 1)" 42501 "$fence_row"

new_generation expiry-first
run_race expiry-first "$due_sql $expiry_sql" "$confirm_sql" 42501 "$fence_row"

new_generation mixed-before-expiry
run_race mixed-before-expiry "$confirm_sql" "$expiry_sql" 23505 "$fence_row"

new_generation exact-replay
run_race exact-replay "$confirm_sql" "$confirm_sql" unchanged "$app_user_id:$request_id"
assert_true one-common-request "SELECT count(*)=1 FROM app_private.personal_merge_mixed_resolution_requests_v1
  WHERE actor_app_user_id='$app_user_id' AND request_id='$request_id';"

assert_true one-outer-entry "SELECT
  (SELECT count(*)=1 FROM app_private.personal_merge_mixed_project_entry_requests_v1 WHERE actor_app_user_id='$app_user_id' AND request_id='$request_id')
  AND (SELECT count(*)=1 FROM app_private.personal_merge_mixed_project_entry_origins_v1 WHERE actor_app_user_id='$app_user_id' AND request_id='$request_id')
  AND (SELECT count(*)=1 FROM app_data.promotion_target_relationship_revisions
    WHERE promotion_target_id='$first_target' AND project_id='$project_id' AND reason_code='project_entry');"

new_generation request-drift
drift_sql="$(printf '%s' "$confirm_sql" | sed "s/$resolution_fingerprint/$(printf '%064d' 0)/")"
[[ "$drift_sql" != "$confirm_sql" ]]
run_race request-drift "$confirm_sql" "$drift_sql" 23505 "$app_user_id:$request_id"

new_generation request-ack-drift
drift_acknowledgements="$(run_psql --tuples-only --no-align --command="SELECT jsonb_agg(value||jsonb_build_object('pending_fact_id',gen_random_uuid()))
  FROM jsonb_array_elements('$acknowledgements'::jsonb) value;")"
drift_sql="${confirm_sql/"$acknowledgements"/"$drift_acknowledgements"}"
[[ "$drift_sql" != "$confirm_sql" ]]
run_race request-ack-drift "$confirm_sql" "$drift_sql" 23505 "$app_user_id:$request_id"

new_generation actor-status
run_race actor-status "UPDATE app_data.app_users SET status='deletion_pending' WHERE app_user_id='$app_user_id';" \
  "$confirm_sql" 42501 'row:app_data.app_users'
run_psql --quiet --command="UPDATE app_data.app_users SET status='active' WHERE app_user_id='$app_user_id';"

new_generation scope-after-wait
run_race scope-after-wait 'SELECT app_private.acquire_personal_target_merge_generation_fence_v1();' \
  "$confirm_sql" 42501 "$fence_row" \
  "SELECT * FROM app_data.select_personal_project_context('$issuer','$subject','$other_project_id');"
run_psql --quiet --command="SELECT * FROM app_data.select_personal_project_context('$issuer','$subject','$project_id');" >/dev/null

new_generation due-after-wait
run_race due-after-wait "SELECT 1 FROM app_data.promotion_targets WHERE promotion_target_id='$first_target' FOR UPDATE;" \
  "$confirm_sql" 42501 'row:app_data.promotion_targets' "$due_sql"

new_generation nonpair-target
run_race nonpair-target "SELECT 1 FROM app_data.promotion_targets WHERE promotion_target_id='$nonpair_target' FOR UPDATE;" \
  "$rollback_confirm_sql" unchanged 'row:app_data.promotion_targets' '' "$no_application_writes"

new_generation nonpair-relation
run_race nonpair-relation "SELECT 1 FROM app_data.promotion_target_project_relationships
  WHERE promotion_target_id='$nonpair_target' AND project_id='$project_id' FOR UPDATE;" \
  "$rollback_confirm_sql" unchanged 'row:app_data.promotion_target_project_relationships' '' "$no_application_writes"

expect_isolation_rejection() {
  local label="$1" isolation="$2" before_state status=0 error_line
  before_state="$(business_state)"
  run_psql --quiet --command="BEGIN ISOLATION LEVEL $isolation; $confirm_sql COMMIT;" \
    >"$temporary_directory/isolation.out" 2>&1 || status=$?
  error_line="$(sed -n '/^ERROR:/p' "$temporary_directory/isolation.out" | head -n 1)"
  [[ "$status" -ne 0 && "$error_line" == 'ERROR:  0A000: pending mixed project entry confirmation requires read committed' ]] || {
    echo "0143 $label expected 0A000; status $status: $error_line" >&2
    exit 1
  }
  [[ "$(business_state)" == "$before_state" ]] || { echo "0143 $label changed persistent state." >&2; exit 1; }
}
new_generation non-rc-first
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  expect_isolation_rejection first "$isolation"
done
new_generation terminal-replay
confirm_expression="$(printf '%s' "$confirm_sql" | sed 's/;$//')"
confirmed_at="$(run_psql --tuples-only --no-align --command="SELECT extract(epoch FROM ($confirm_expression));")"
assert_true exact-rc-replay "SELECT extract(epoch FROM ($confirm_expression))=$confirmed_at;"
for isolation in 'REPEATABLE READ' SERIALIZABLE 'READ UNCOMMITTED'; do
  expect_isolation_rejection terminal-replay "$isolation"
done
echo '0143 exact-PID mixed entry, ordinary writers, request, contact, fence, actor, target and relationship races plus six non-RC rejections passed.'
