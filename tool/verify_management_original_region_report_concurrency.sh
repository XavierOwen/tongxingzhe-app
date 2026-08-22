#!/usr/bin/env bash

set -euo pipefail

# Two original reads must observe one complete source-tree document while a
# source contact/revision/provenance transaction remains uncommitted. After
# commit, all three source facts appear together. A concurrent target-tree
# publication must not alter the original tuple.
: "${DATABASE_URL:?请设置 DATABASE_URL，例如 postgresql://user:password@host/database}"
psql_command="${PSQL_COMMAND:-psql}"
if ! command -v "${psql_command}" >/dev/null 2>&1; then
  echo '找不到 psql；请安装 PostgreSQL client 或设置 PSQL_COMMAND。' >&2
  exit 1
fi
export PGOPTIONS="${PGOPTIONS:+${PGOPTIONS} }-c statement_timeout=30000 -c lock_timeout=15000"
psql_base=(
  "${psql_command}" "${DATABASE_URL}"
  --no-psqlrc --set=ON_ERROR_STOP=1
)
temporary_reader_role="tongxingzhe_6bd_concurrency_caller_$$"
temporary_reader_created=0

temporary_directory="$(mktemp -d)"
cleanup() {
  local child_pid
  for child_pid in \
    "${report_one_pid:-}" \
    "${report_two_pid:-}" \
    "${publication_pid:-}" \
    "${source_writer_pid:-}" \
    "${revocation_blocker_pid:-}" \
    "${revocation_reader_pid:-}"
  do
    if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" >/dev/null 2>&1; then
      kill "${child_pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${child_pid}" ]]; then
      wait "${child_pid}" >/dev/null 2>&1 || true
    fi
  done
  if [[ "${temporary_reader_created}" -eq 1 ]]; then
    "${psql_base[@]}" --command="
      DROP ROLE IF EXISTS ${temporary_reader_role};
    " >/dev/null 2>&1 || true
  fi
  rm -f "${temporary_directory}"/*.out
  rmdir "${temporary_directory}"
}
trap cleanup EXIT

project_id='6bdc3000-0000-4000-8000-000000000001'
workspace_id='6bdc2000-0000-4000-8000-000000000001'
questionnaire_version_id='6bdc4000-0000-4000-8000-000000000001'
user_one='6bdc1000-0000-4000-8000-000000000001'
user_two='6bdc1000-0000-4000-8000-000000000002'
user_three='6bdc1000-0000-4000-8000-000000000003'
source_tree='concurrent-original-region-report-source-v1'
target_tree='concurrent-original-region-report-target-v1'
cutoff='2030-04-17T12:00:00Z'

# These committed synthetic rows use a namespace disjoint from rollback
# fixtures and are intentionally included in dump/restore checks.
"${psql_base[@]}" --command="
  INSERT INTO app_data.app_users (app_user_id, status)
  VALUES
    ('${user_one}'::uuid, 'active'),
    ('${user_two}'::uuid, 'active'),
    ('${user_three}'::uuid, 'active');
  INSERT INTO app_data.workspaces (
    workspace_id, workspace_kind, display_name
  ) VALUES (
    '${workspace_id}'::uuid, 'organization',
    'Concurrent 6BD original-region workspace'
  );
  INSERT INTO app_data.projects (project_id, workspace_id, display_name)
  VALUES (
    '${project_id}'::uuid, '${workspace_id}'::uuid,
    'Concurrent 6BD original-region project'
  );
  INSERT INTO app_data.questionnaire_versions (
    questionnaire_version_id, project_id, version_number, status, is_current
  ) VALUES (
    '${questionnaire_version_id}'::uuid, '${project_id}'::uuid, 1,
    'published', true
  );
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES
    ('${source_tree}', 'draft', false),
    ('${target_tree}', 'draft', false);
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('concurrent-6bd-source-country', '${source_tree}', NULL,
      'Concurrent Source Country', 'country'),
    ('concurrent-6bd-source-city', '${source_tree}',
      'concurrent-6bd-source-country', 'Concurrent Source City', 'city'),
    ('concurrent-6bd-source-venue', '${source_tree}',
      'concurrent-6bd-source-city', 'Concurrent Source Venue', 'venue'),
    ('concurrent-6bd-target-country', '${target_tree}', NULL,
      'Concurrent Target Country', 'country'),
    ('concurrent-6bd-target-city', '${target_tree}',
      'concurrent-6bd-target-country', 'Concurrent Target City', 'city'),
    ('concurrent-6bd-target-venue', '${target_tree}',
      'concurrent-6bd-target-city', 'Concurrent Target Venue', 'venue');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES
    ('concurrent-6bd-source-city-boundary',
      'concurrent-6bd-source-city', '${source_tree}',
      polygon '((-88.00,41.60),(-87.90,41.60),(-87.90,41.70),(-88.00,41.70))'),
    ('concurrent-6bd-target-city-boundary',
      'concurrent-6bd-target-city', '${target_tree}',
      polygon '((-87.90,41.60),(-87.80,41.60),(-87.80,41.70),(-87.90,41.70))');
  SELECT app_private.publish_canonical_region_tree_v1(
    '${source_tree}', true
  );
  DO \$setup\$
  DECLARE
    period_key text;
    occurred_at timestamptz;
    contributor_number integer;
    contributor_id uuid;
    contributor_units integer;
    unit_number integer;
    contact_key text;
  BEGIN
    FOR period_key, occurred_at IN
      SELECT 'previous', '2030-04-02T12:00:00Z'::timestamptz
      UNION ALL SELECT 'current', '2030-04-09T12:00:00Z'::timestamptz
    LOOP
      FOR contributor_number, contributor_id, contributor_units IN
        SELECT 1, '${user_one}'::uuid, 4
        UNION ALL SELECT 2, '${user_two}'::uuid, 3
        UNION ALL SELECT 3, '${user_three}'::uuid, 3
      LOOP
        FOR unit_number IN 1..contributor_units LOOP
          contact_key = format(
            'concurrent-6bd-%s-c%s-u%s',
            period_key, contributor_number, unit_number
          );
          INSERT INTO app_data.contacts (
            contact_id, app_user_id, workspace_id, project_id,
            questionnaire_version_id, occurred_at_utc, occurred_time_zone,
            first_submitted_at_utc, channel, location_kind, place_name,
            smallest_region_id, region_tree_version, reach_count,
            interest_level
          ) VALUES (
            contact_key, contributor_id, '${workspace_id}'::uuid,
            '${project_id}'::uuid, '${questionnaire_version_id}'::uuid,
            occurred_at, 'UTC', occurred_at, 'face_to_face', 'resolved',
            'Concurrent source venue', 'concurrent-6bd-source-venue',
            '${source_tree}', 1, 2
          );
          INSERT INTO app_data.contact_revisions (
            contact_id, revision_number, revision_kind,
            revised_by_app_user_id, snapshot
          ) VALUES (
            contact_key, 1, 'submitted', contributor_id,
            jsonb_build_object(
              'contactId', contact_key,
              'location', jsonb_build_object(
                'kind', 'resolved',
                'placeName', 'Concurrent source venue',
                'smallestRegionId', 'concurrent-6bd-source-venue',
                'regionTreeVersion', '${source_tree}'
              )
            )
          );
        END LOOP;
      END LOOP;
    END LOOP;
  END
  \$setup\$;
  INSERT INTO app_data.change_feed (
    app_user_id, workspace_id, project_id, aggregate_id,
    revision_number, change_type
  ) VALUES (
    '${user_one}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
    'concurrent-6bd-watermark', 1, 'contact.submitted'
  );
" >/dev/null

run_report() {
  "${psql_base[@]}" --tuples-only --no-align --command="
    SELECT app_private.execute_management_original_region_contact_session_report_v1(
      '${project_id}'::uuid, 'UTC', '${cutoff}'::timestamptz
    )::text;
  " | tr -d '\r\n'
}

run_source_write() {
  "${psql_base[@]}" --command="
    BEGIN;
    SELECT pg_advisory_xact_lock(66, 193);
    INSERT INTO app_data.contacts (
      contact_id, app_user_id, workspace_id, project_id,
      questionnaire_version_id, occurred_at_utc, occurred_time_zone,
      first_submitted_at_utc, channel, location_kind, place_name,
      smallest_region_id, region_tree_version, reach_count, interest_level
    ) VALUES (
      'concurrent-6bd-source-write', '${user_three}'::uuid,
      '${workspace_id}'::uuid, '${project_id}'::uuid,
      '${questionnaire_version_id}'::uuid,
      '2030-04-10T12:00:00Z', 'UTC', '2030-04-10T12:00:00Z',
      'face_to_face', 'resolved', 'Concurrent source venue',
      'concurrent-6bd-source-venue', '${source_tree}', 1, 2
    );
    INSERT INTO app_data.contact_revisions (
      contact_id, revision_number, revision_kind,
      revised_by_app_user_id, snapshot
    ) VALUES (
      'concurrent-6bd-source-write', 1, 'submitted', '${user_three}'::uuid,
      jsonb_build_object(
        'contactId', 'concurrent-6bd-source-write',
        'location', jsonb_build_object(
          'kind', 'resolved',
          'placeName', 'Concurrent source venue',
          'smallestRegionId', 'concurrent-6bd-source-venue',
          'regionTreeVersion', '${source_tree}'
        )
      )
    );
    INSERT INTO app_data.change_feed (
      app_user_id, workspace_id, project_id, aggregate_id,
      revision_number, change_type
    ) VALUES (
      '${user_three}'::uuid, '${workspace_id}'::uuid, '${project_id}'::uuid,
      'concurrent-6bd-source-write', 1, 'contact.submitted'
    );
    SELECT pg_sleep(5);
    COMMIT;
  "
}

report_one_output="${temporary_directory}/report-one.out"
report_two_output="${temporary_directory}/report-two.out"
publication_output="${temporary_directory}/publication.out"
source_writer_output="${temporary_directory}/source-writer.out"

source_fingerprint="$(
  "${psql_base[@]}" --tuples-only --no-align --command="
    SELECT content_fingerprint
    FROM app_data.canonical_region_tree_releases
    WHERE tree_version = '${source_tree}'
      AND lifecycle_state = 'published';
  " | tr -d '\r\n'
)"
if [[ ! "${source_fingerprint}" =~ ^[0-9a-f]{64}$ ]]; then
  echo '6BD source tree fingerprint is unavailable before concurrency test.' >&2
  exit 1
fi

run_source_write >"${source_writer_output}" 2>&1 &
source_writer_pid=$!

source_writer_ready=0
for _ in $(seq 1 50); do
  source_lock_held="$(
    "${psql_base[@]}" --tuples-only --no-align --command="
      SELECT NOT pg_try_advisory_lock(66, 193);
    " | tr -d '\r\n'
  )"
  if [[ "${source_lock_held}" == 't' ]]; then
    source_writer_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${source_writer_ready}" -ne 1 ]]; then
  echo '6BD source transaction did not reach its concurrency barrier.' >&2
  sed -n '1,160p' "${source_writer_output}" >&2
  exit 1
fi

run_report >"${report_one_output}" 2>&1 &
report_one_pid=$!
run_report >"${report_two_output}" 2>&1 &
report_two_pid=$!

# The target is published concurrently. Original reports must stay bound to
# the source tuple and must not read current selection.
"${psql_base[@]}" --command="
  SELECT app_private.publish_canonical_region_tree_v1(
    '${target_tree}', true
  );
" >"${publication_output}" 2>&1 &
publication_pid=$!

report_one_status=0
report_two_status=0
publication_status=0
source_writer_status=0
wait "${report_one_pid}" || report_one_status=$?
wait "${report_two_pid}" || report_two_status=$?
source_write_overlapped=0
if kill -0 "${source_writer_pid}" >/dev/null 2>&1; then
  source_write_overlapped=1
fi
wait "${publication_pid}" || publication_status=$?
wait "${source_writer_pid}" || source_writer_status=$?

if [[ "${report_one_status}" -ne 0 || "${report_two_status}" -ne 0 ]]; then
  echo '6BD 并发 original report 会话失败。' >&2
  sed -n '1,160p' "${report_one_output}" >&2
  sed -n '1,160p' "${report_two_output}" >&2
  exit 1
fi
if [[ "${publication_status}" -ne 0 ]]; then
  echo '6BD 并发 target publication 会话失败。' >&2
  sed -n '1,160p' "${publication_output}" >&2
  exit 1
fi
if [[ "${source_writer_status}" -ne 0 ]]; then
  echo '6BD 并发 source transaction 会话失败。' >&2
  sed -n '1,160p' "${source_writer_output}" >&2
  exit 1
fi
if [[ "${source_write_overlapped}" -ne 1 ]]; then
  echo '6BD reports did not finish while the source transaction was open.' >&2
  exit 1
fi

if ! cmp -s "${report_one_output}" "${report_two_output}"; then
  echo '6BD simultaneous reports did not return the same document.' >&2
  diff -u "${report_one_output}" "${report_two_output}" >&2 || true
  exit 1
fi

report_document="$(tr -d '\r\n' <"${report_one_output}")"
after_source_document="$(run_report)"
shape="$(
  "${psql_base[@]}" --tuples-only --no-align \
    --variable="document=${report_document}" \
    --variable="after_source_document=${after_source_document}" \
    --variable="source_tree=${source_tree}" \
    --variable="source_fingerprint=${source_fingerprint}" --file=- <<'SQL'
    SELECT CASE
      WHEN document->>'report_id' =
          'contact_sessions_by_original_region_two_periods'
        AND document->>'view_mode' = 'original'
        AND document->>'dimension' = 'original_region'
        AND document->>'result_status' = 'completed'
        AND document->'source_tree_context'->>'source_tree_version' =
          :'source_tree'
        AND document->'source_tree_context'->>'source_content_fingerprint' =
          :'source_fingerprint'
        AND document->'source_tree_context'->>'result_status' = 'selected'
        AND jsonb_array_length(document->'cells') = 2
        AND (
          SELECT array_agg(
            (cell.item->>'value_count')::integer
            ORDER BY (cell.item->>'cell_order')::integer
          )
          FROM jsonb_array_elements(document->'cells') AS cell(item)
          WHERE cell.item->>'privacy_status' = 'displayed'
        ) = ARRAY[10, 10]
        AND NOT document::text LIKE '%concurrent-original-region-report-target-v1%'
        AND after_source_document->>'result_status' = 'completed'
        AND after_source_document->'source_tree_context'->>'source_tree_version' =
          :'source_tree'
        AND after_source_document->'source_tree_context'->>
          'source_content_fingerprint' = :'source_fingerprint'
        AND jsonb_array_length(after_source_document->'cells') = 2
        AND (
          SELECT array_agg(
            (cell.item->>'value_count')::integer
            ORDER BY (cell.item->>'cell_order')::integer
          )
          FROM jsonb_array_elements(after_source_document->'cells') AS cell(item)
          WHERE cell.item->>'privacy_status' = 'displayed'
        ) = ARRAY[10, 11]
        AND NOT after_source_document::text LIKE
          '%concurrent-original-region-report-target-v1%'
      THEN 'ok'
      ELSE jsonb_build_object(
        'during_source_transaction', document,
        'after_source_commit', after_source_document
      )::text
    END
    FROM (
      SELECT
        :'document'::jsonb AS document,
        :'after_source_document'::jsonb AS after_source_document
    ) AS report;
SQL
)"
shape="${shape//$'\r'/}"
shape="${shape//$'\n'/}"

if [[ "${shape}" != 'ok' ]]; then
  echo "6BD original report concurrency shape is wrong: ${shape}" >&2
  exit 1
fi

# A temporary caller inherits the private reader role.  Hold its report inside
# the SECURITY DEFINER body on a source-table lock, revoke the membership, and
# then release the report.  The in-flight statement must return one complete
# pre-revocation document; a new statement must fail at the private boundary.
temporary_reader_created=1
"${psql_base[@]}" --command="
  CREATE ROLE ${temporary_reader_role}
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT
    NOREPLICATION NOBYPASSRLS;
  GRANT tongxingzhe_management_original_region_report_reader
    TO ${temporary_reader_role};
" >/dev/null

revocation_blocker_output="${temporary_directory}/revocation-blocker.out"
"${psql_base[@]}" --command="
  BEGIN;
  LOCK TABLE app_data.contacts IN ACCESS EXCLUSIVE MODE;
  SELECT pg_advisory_xact_lock(66, 194);
  SELECT pg_sleep(8);
  COMMIT;
" >"${revocation_blocker_output}" 2>&1 &
revocation_blocker_pid=$!

revocation_blocker_ready=0
for _ in $(seq 1 50); do
  revocation_lock_held="$(
    "${psql_base[@]}" --tuples-only --no-align --command="
      SELECT NOT pg_try_advisory_lock(66, 194);
    " | tr -d '\r\n'
  )"
  if [[ "${revocation_lock_held}" == 't' ]]; then
    revocation_blocker_ready=1
    break
  fi
  sleep 0.1
done
if [[ "${revocation_blocker_ready}" -ne 1 ]]; then
  echo '6BD revocation blocker did not reach its concurrency barrier.' >&2
  sed -n '1,160p' "${revocation_blocker_output}" >&2
  exit 1
fi

revocation_reader_output="${temporary_directory}/revocation-reader.out"
"${psql_base[@]}" --tuples-only --no-align --quiet --command="
  SET application_name = 'tongxingzhe-6bd-revocation-reader';
  SET ROLE ${temporary_reader_role};
  SELECT app_private.execute_management_original_region_contact_session_report_v1(
    '${project_id}'::uuid, 'UTC', '${cutoff}'::timestamptz
  )::text;
  RESET ROLE;
" >"${revocation_reader_output}" 2>&1 &
revocation_reader_pid=$!

revocation_reader_waiting=0
for _ in $(seq 1 50); do
  reader_wait_state="$(
    "${psql_base[@]}" --tuples-only --no-align --command="
      SELECT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_stat_activity AS activity
        WHERE activity.application_name =
            'tongxingzhe-6bd-revocation-reader'
          AND activity.wait_event_type = 'Lock'
      );
    " | tr -d '\r\n'
  )"
  if [[ "${reader_wait_state}" == 't' ]]; then
    revocation_reader_waiting=1
    break
  fi
  if ! kill -0 "${revocation_reader_pid}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
if [[ "${revocation_reader_waiting}" -ne 1 ]]; then
  echo '6BD reader did not wait inside the report before revocation.' >&2
  sed -n '1,160p' "${revocation_reader_output}" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  REVOKE tongxingzhe_management_original_region_report_reader
    FROM ${temporary_reader_role};
" >/dev/null

revocation_blocker_status=0
revocation_reader_status=0
wait "${revocation_blocker_pid}" || revocation_blocker_status=$?
wait "${revocation_reader_pid}" || revocation_reader_status=$?
if [[ "${revocation_blocker_status}" -ne 0 \
  || "${revocation_reader_status}" -ne 0 ]]; then
  echo '6BD in-flight report/revocation concurrency failed.' >&2
  sed -n '1,160p' "${revocation_blocker_output}" >&2
  sed -n '1,160p' "${revocation_reader_output}" >&2
  exit 1
fi

revocation_document="$(tr -d '\r\n' <"${revocation_reader_output}")"
revocation_shape="$(
  "${psql_base[@]}" --tuples-only --no-align \
    --variable="document=${revocation_document}" \
    --variable="source_tree=${source_tree}" \
    --variable="source_fingerprint=${source_fingerprint}" --file=- <<'SQL'
    SELECT CASE
      WHEN document->>'result_status' = 'completed'
        AND document->'source_tree_context'->>'source_tree_version' =
          :'source_tree'
        AND document->'source_tree_context'->>'source_content_fingerprint' =
          :'source_fingerprint'
        AND jsonb_array_length(document->'cells') = 2
      THEN 'ok'
      ELSE document::text
    END
    FROM (SELECT :'document'::jsonb AS document) AS report;
SQL
)"
revocation_shape="${revocation_shape//$'\r'/}"
revocation_shape="${revocation_shape//$'\n'/}"
if [[ "${revocation_shape}" != 'ok' ]]; then
  echo "6BD in-flight revocation returned a partial document: ${revocation_shape}" >&2
  exit 1
fi

post_revocation_output="${temporary_directory}/post-revocation.out"
post_revocation_status=0
"${psql_base[@]}" --quiet --command="
  SET ROLE ${temporary_reader_role};
  SELECT app_private.execute_management_original_region_contact_session_report_v1(
    '${project_id}'::uuid, 'UTC', '${cutoff}'::timestamptz
  );
" >"${post_revocation_output}" 2>&1 || post_revocation_status=$?
if [[ "${post_revocation_status}" -eq 0 ]] \
  || ! grep -q 'permission denied' "${post_revocation_output}"; then
  echo '6BD new report did not fail closed after reader revocation.' >&2
  sed -n '1,160p' "${post_revocation_output}" >&2
  exit 1
fi

"${psql_base[@]}" --command="
  DROP ROLE ${temporary_reader_role};
" >/dev/null
temporary_reader_created=0

echo '6BD 并发检查通过：未提交来源不可见、提交后整份生效、target publication 隔离，且撤权中的读取完整、撤权后的新读取失败关闭。'
