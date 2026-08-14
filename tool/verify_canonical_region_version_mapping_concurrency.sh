#!/usr/bin/env bash

set -euo pipefail

# Two independent sessions register the same source node in one published tree
# against different target nodes in one published target tree.  The first
# registration remains uncommitted while the second request starts; the unique
# source/target-version invariant must make the second request wait and then
# fail without leaving a second mapping or any partial row.
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

source_tree_version='concurrent-region-mapping-source-v1'
target_tree_version='concurrent-region-mapping-target-v1'
source_country_id='concurrent-region-mapping-source-country'
source_city_id='concurrent-region-mapping-source-city'
source_region_id='concurrent-region-mapping-source-region'
target_country_id='concurrent-region-mapping-target-country'
target_city_id='concurrent-region-mapping-target-city'
target_region_a_id='concurrent-region-mapping-target-region-a'
target_region_b_id='concurrent-region-mapping-target-region-b'
first_request_id='6a000000-0000-4000-8000-000000000001'
second_request_id='6a000000-0000-4000-8000-000000000002'
first_evidence_digest='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
second_evidence_digest='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
ready_lock='canonical-region-version-mapping-concurrency-ready-v1'
second_marker_lock='canonical-region-version-mapping-concurrency-second-v1'
publication_lock='canonical-region-tree-publication:v1'

"${psql_base[@]}" --command="
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES
    ('${source_tree_version}', 'draft', false),
    ('${target_tree_version}', 'draft', false);

  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    (
      '${source_country_id}', '${source_tree_version}', NULL,
      'Concurrent Mapping Source Country', 'country'
    ),
    (
      '${source_city_id}', '${source_tree_version}', '${source_country_id}',
      'Concurrent Mapping Source City', 'city'
    ),
    (
      '${source_region_id}', '${source_tree_version}', '${source_city_id}',
      'Concurrent Mapping Source Region', 'venue'
    ),
    (
      '${target_country_id}', '${target_tree_version}', NULL,
      'Concurrent Mapping Target Country', 'country'
    ),
    (
      '${target_city_id}', '${target_tree_version}', '${target_country_id}',
      'Concurrent Mapping Target City', 'city'
    ),
    (
      '${target_region_a_id}', '${target_tree_version}', '${target_city_id}',
      'Concurrent Mapping Target Region A', 'venue'
    ),
    (
      '${target_region_b_id}', '${target_tree_version}', '${target_city_id}',
      'Concurrent Mapping Target Region B', 'venue'
    );

  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES
    (
      'concurrent-region-mapping-source-boundary',
      '${source_region_id}', '${source_tree_version}',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    ),
    (
      'concurrent-region-mapping-target-boundary-a',
      '${target_region_a_id}', '${target_tree_version}',
      polygon '((-87.62,41.78),(-87.57,41.78),(-87.57,41.81),(-87.62,41.81))'
    ),
    (
      'concurrent-region-mapping-target-boundary-b',
      '${target_region_b_id}', '${target_tree_version}',
      polygon '((-87.63,41.77),(-87.56,41.77),(-87.56,41.82),(-87.63,41.82))'
    );

  SELECT app_private.publish_canonical_region_tree_v1(
    '${source_tree_version}', true
  );
  SELECT app_private.publish_canonical_region_tree_v1(
    '${target_tree_version}', true
  );
" >/dev/null

source_fingerprint="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT content_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = '${source_tree_version}';
" | tr -d '[:space:]')"
target_fingerprint="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT content_fingerprint
  FROM app_data.canonical_region_tree_releases
  WHERE tree_version = '${target_tree_version}';
" | tr -d '[:space:]')"
if [[ ! "${source_fingerprint}" =~ ^[0-9a-f]{64}$ \
  || ! "${target_fingerprint}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "并发测试的区域树 fingerprint 无效：source=${source_fingerprint}, target=${target_fingerprint}" >&2
  exit 1
fi

wait_for_ready() {
  local process_pid="$1"
  local process_output="$2"
  local first_ready=0
  local ready_probe

  for _ in $(seq 1 100); do
    ready_probe="$(${psql_base[@]} --tuples-only --no-align --command="
      SELECT CASE
        WHEN pg_try_advisory_lock(hashtextextended('${ready_lock}', 0))
        THEN 'not-ready'
        ELSE 'ready'
      END;
    " | tr -d '[:space:]')"
    if [[ "${ready_probe}" == 'ready' ]]; then
      first_ready=1
      break
    fi
    sleep 0.1
  done

  if [[ "${first_ready}" -ne 1 ]]; then
    kill "${process_pid}" >/dev/null 2>&1 || true
    wait "${process_pid}" >/dev/null 2>&1 || true
    echo '区域映射并发首个登记会话没有进入持锁状态。' >&2
    sed -n '1,160p' "${process_output}" >&2
    exit 1
  fi
}

first_output="${temporary_directory}/first.out"
second_output="${temporary_directory}/second.out"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  BEGIN;
  SELECT app_private.register_canonical_region_version_mapping_v1(
    '${first_request_id}'::uuid,
    '${source_tree_version}',
    '${source_region_id}',
    '${source_fingerprint}',
    '${target_tree_version}',
    '${target_region_a_id}',
    '${target_fingerprint}',
    '${first_evidence_digest}'
  );
  SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
  DO \$wait\$
  DECLARE
    wait_deadline timestamp with time zone :=
      clock_timestamp() + interval '10 seconds';
  BEGIN
    LOOP
      EXIT WHEN EXISTS (
        WITH lock_keys AS (
          SELECT
            (
              (hashtextextended('${second_marker_lock}', 0) >> 32)
                & 4294967295
            )::oid AS marker_classid,
            (
              hashtextextended('${second_marker_lock}', 0)
                & 4294967295
            )::oid AS marker_objid,
            (
              (hashtextextended('${publication_lock}', 0) >> 32)
                & 4294967295
            )::oid AS publication_classid,
            (
              hashtextextended('${publication_lock}', 0)
                & 4294967295
            )::oid AS publication_objid
        )
        SELECT 1
        FROM pg_locks AS marker_lock
        JOIN pg_locks AS waiting_lock
          ON waiting_lock.pid = marker_lock.pid
        CROSS JOIN lock_keys
        WHERE marker_lock.locktype = 'advisory'
          AND marker_lock.granted
          AND marker_lock.classid = lock_keys.marker_classid
          AND marker_lock.objid = lock_keys.marker_objid
          AND waiting_lock.locktype = 'advisory'
          AND NOT waiting_lock.granted
          AND waiting_lock.classid = lock_keys.publication_classid
          AND waiting_lock.objid = lock_keys.publication_objid
      );
      IF clock_timestamp() >= wait_deadline THEN
        RAISE EXCEPTION 'second region mapping request did not wait';
      END IF;
      PERFORM pg_sleep(0.05);
    END LOOP;
  END
  \$wait\$;
  COMMIT;
" >"${first_output}" 2>&1 &
first_pid=$!

wait_for_ready "${first_pid}" "${first_output}"

"${psql_base[@]}" --command="
  SET lock_timeout = '10s';
  SET statement_timeout = '20s';
  SELECT pg_advisory_lock(hashtextextended('${second_marker_lock}', 0));
  DO \$second\$
  BEGIN
    BEGIN
      PERFORM app_private.register_canonical_region_version_mapping_v1(
        '${second_request_id}'::uuid,
        '${source_tree_version}',
        '${source_region_id}',
        '${source_fingerprint}',
        '${target_tree_version}',
        '${target_region_b_id}',
        '${target_fingerprint}',
        '${second_evidence_digest}'
      );
      RAISE EXCEPTION 'second region mapping unexpectedly succeeded';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      IF SQLERRM IS DISTINCT FROM
        'canonical region version mapping is not one to one'
      THEN
        RAISE;
      END IF;
      RAISE NOTICE 'expected canonical region mapping conflict';
    END;
  END
  \$second\$;
" >"${second_output}" 2>&1 &
second_pid=$!

first_status=0
second_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
if [[ "${first_status}" -ne 0 || "${second_status}" -ne 0 ]] \
  || ! grep -q 'expected canonical region mapping conflict' "${second_output}";
then
  echo "区域映射并发结果错误：first=${first_status}, second=${second_status}" >&2
  sed -n '1,160p' "${first_output}" >&2
  sed -n '1,160p' "${second_output}" >&2
  exit 1
fi

# Keep the table private in the contract, but inspect it as the test database
# superuser through row_to_json so this check does not couple to incidental
# column additions.  Exactly one row may mention this source; its target must
# be one of the two contenders, never both and never neither.
result="$(${psql_base[@]} --tuples-only --no-align --field-separator='|' --command="
  SELECT
    count(*) FILTER (
      WHERE to_jsonb(mapping_row)::text LIKE '%${source_tree_version}%'
        AND to_jsonb(mapping_row)::text LIKE '%${source_region_id}%'
        AND to_jsonb(mapping_row)::text LIKE '%${target_tree_version}%'
    ),
    count(*) FILTER (
      WHERE to_jsonb(mapping_row)::text LIKE '%${target_region_a_id}%'
    ),
    count(*) FILTER (
      WHERE to_jsonb(mapping_row)::text LIKE '%${target_region_b_id}%'
    ),
    count(*) FILTER (
      WHERE to_jsonb(mapping_row)::text LIKE '%${first_request_id}%'
    ),
    count(*) FILTER (
      WHERE to_jsonb(mapping_row)::text LIKE '%${second_request_id}%'
    )
  FROM app_data.canonical_region_version_mappings AS mapping_row
  WHERE to_jsonb(mapping_row)::text LIKE '%${source_region_id}%';
")"
IFS='|' read -r mapping_count target_a_count target_b_count first_request_count \
  second_request_count <<< "${result}"
if [[ "${mapping_count}" -ne 1 \
  || $((target_a_count + target_b_count)) -ne 1 \
  || "${first_request_count}" -ne 1 \
  || "${second_request_count}" -ne 0 ]]; then
  echo "区域映射并发不变量失败：mappings=${mapping_count}, target_a=${target_a_count}, target_b=${target_b_count}, first_request=${first_request_count}, second_request=${second_request_count}" >&2
  exit 1
fi

# The resolver accepts source tree/region/fingerprint followed by target tree
# and fingerprint; target region is selected only from the unique mapping.
resolver_result="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT to_jsonb(resolved_row)
  FROM app_private.resolve_canonical_region_version_mapping_v1(
    '${source_tree_version}',
    '${source_region_id}',
    '${source_fingerprint}',
    '${target_tree_version}',
    '${target_fingerprint}'
  ) AS resolved_row;
" | tr -d '\n')"
if [[ "${resolver_result}" != *mapped* \
  || ( "${resolver_result}" != *"${target_region_a_id}"* \
    && "${resolver_result}" != *"${target_region_b_id}"* ) ]]; then
  echo "区域映射解析没有返回唯一已登记目标：${resolver_result}" >&2
  exit 1
fi

if [[ "${target_a_count}" -eq 1 \
  && "${resolver_result}" != *"${target_region_a_id}"* ]]; then
  echo "区域映射解析偏离已提交目标 A：${resolver_result}" >&2
  exit 1
fi
if [[ "${target_b_count}" -eq 1 \
  && "${resolver_result}" != *"${target_region_b_id}"* ]]; then
  echo "区域映射解析偏离已提交目标 B：${resolver_result}" >&2
  exit 1
fi

echo '区域映射并发检查通过：同一来源到同一目标树只有一个登记，败者无部分状态，解析返回唯一目标。'
