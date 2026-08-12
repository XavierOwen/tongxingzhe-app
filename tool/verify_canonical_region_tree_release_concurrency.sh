#!/usr/bin/env bash

set -euo pipefail

# 两个独立会话竞争发布 current 区域树。第一个事务在发布后短暂保持未提交，
# 读解析会话必须仍然看到上一个已提交版本；第二个发布随后接管 current，且
# 不产生双 current 或交叉指纹。
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
  for child_pid in \
    "${first_pid:-}" "${second_pid:-}" "${editor_pid:-}"
  do
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

ready_lock='canonical-region-release-ready-v1'

wait_for_ready() {
  local process_pid="$1"
  local process_output="$2"
  local lock_held='f'

  for _ in $(seq 1 100); do
    # The first publisher holds a unique session advisory lock while its
    # publication is still uncommitted. Inspect the matching bigint advisory
    # lock in pg_locks directly; stdout from a redirected psql process may be
    # block-buffered until the session exits.
    lock_held="$("${psql_base[@]}" --tuples-only --no-align --command="
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
  echo '区域树并发发布会话没有进入持锁状态。' >&2
  sed -n '1,160p' "${process_output}" >&2
  exit 1
}

"${psql_base[@]}" --command="
  -- Base is a committed current version visible before either contender.
  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES ('concurrent-region-base', 'draft', false);
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('concurrent-base-country', 'concurrent-region-base', NULL, 'Base Country', 'country'),
    ('concurrent-base-city', 'concurrent-region-base', 'concurrent-base-country', 'Base City', 'city'),
    ('concurrent-base-venue', 'concurrent-region-base', 'concurrent-base-city', 'Base Venue', 'venue');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES (
    'concurrent-base-boundary', 'concurrent-base-venue',
    'concurrent-region-base',
    polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
  );
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-region-base', true
  );

  INSERT INTO app_data.canonical_region_tree_releases (
    tree_version, lifecycle_state, is_current
  ) VALUES
    ('concurrent-region-a', 'draft', false),
    ('concurrent-region-b', 'draft', false);
  INSERT INTO app_data.canonical_region_versions (
    region_id, tree_version, parent_region_id, canonical_name, kind
  ) VALUES
    ('concurrent-a-country', 'concurrent-region-a', NULL, 'A Country', 'country'),
    ('concurrent-a-city', 'concurrent-region-a', 'concurrent-a-country', 'A City', 'city'),
    ('concurrent-a-venue', 'concurrent-region-a', 'concurrent-a-city', 'A Venue', 'venue'),
    ('concurrent-b-country', 'concurrent-region-b', NULL, 'B Country', 'country'),
    ('concurrent-b-city', 'concurrent-region-b', 'concurrent-b-country', 'B City', 'city'),
    ('concurrent-b-venue', 'concurrent-region-b', 'concurrent-b-city', 'B Venue', 'venue');
  INSERT INTO app_data.canonical_region_boundaries (
    boundary_id, region_id, tree_version, boundary
  ) VALUES
    (
      'concurrent-a-boundary', 'concurrent-a-venue', 'concurrent-region-a',
      polygon '((-87.61,41.78),(-87.58,41.78),(-87.58,41.80),(-87.61,41.80))'
    ),
    (
      'concurrent-b-boundary', 'concurrent-b-venue', 'concurrent-region-b',
      polygon '((-87.62,41.78),(-87.57,41.78),(-87.57,41.81),(-87.62,41.81))'
    );
" >/dev/null

first_output="${temporary_directory}/first.out"
second_output="${temporary_directory}/second.out"
editor_output="${temporary_directory}/editor.out"

# Hold the first publication uncommitted long enough for the resolver read. The
# sleep is bounded; it is only a deterministic transaction-order probe.
"${psql_base[@]}" --command="
  BEGIN;
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-region-a', true
  );
  SELECT pg_advisory_lock(hashtextextended('${ready_lock}', 0));
  SELECT 'ready';
  SELECT pg_sleep(2);
  COMMIT;
" --tuples-only --no-align >"${first_output}" 2>&1 &
first_pid=$!

wait_for_ready "${first_pid}" "${first_output}"

reader_version="$(${psql_base[@]} --tuples-only --no-align --command="
  SELECT tree_version
  FROM app_data.resolve_canonical_region(41.7897, -87.5997);
" | tr -d '[:space:]')"
if [[ "${reader_version}" != 'concurrent-region-base' ]]; then
  echo "解析读到了未提交区域树：${reader_version}" >&2
  exit 1
fi

# A draft editor that started after publication acquired the lock must wait for
# the publisher, then observe the committed published state and fail closed.
"${psql_base[@]}" --command="
  DO \$editor\$
  BEGIN
    BEGIN
      UPDATE app_data.canonical_region_versions
      SET canonical_name = 'A Venue edited during publish'
      WHERE region_id = 'concurrent-a-venue'
        AND tree_version = 'concurrent-region-a';
      RAISE EXCEPTION 'draft edit crossed the publication boundary';
    EXCEPTION
      WHEN SQLSTATE '55000' THEN
        NULL;
    END;
  END
  \$editor\$;
" >"${editor_output}" 2>&1 &
editor_pid=$!

# The second publisher starts while A is still uncommitted and must serialize
# with the current selection. It will complete after A commits.
"${psql_base[@]}" --command="
  SELECT app_private.publish_canonical_region_tree_v1(
    'concurrent-region-b', true
  );
" >"${second_output}" 2>&1 &
second_pid=$!

first_status=0
second_status=0
editor_status=0
wait "${first_pid}" || first_status=$?
wait "${second_pid}" || second_status=$?
wait "${editor_pid}" || editor_status=$?
if [[ "${first_status}" -ne 0 \
  || "${second_status}" -ne 0 \
  || "${editor_status}" -ne 0 ]]; then
  echo "并发区域树发布失败：first=${first_status}, second=${second_status}, editor=${editor_status}" >&2
  sed -n '1,160p' "${first_output}" >&2
  sed -n '1,160p' "${second_output}" >&2
  sed -n '1,160p' "${editor_output}" >&2
  exit 1
fi

result="$(${psql_base[@]} --tuples-only --no-align --field-separator='|' --command="
  SELECT
    (SELECT count(*)
     FROM app_data.canonical_region_tree_releases
     WHERE lifecycle_state = 'published' AND is_current),
    (SELECT count(*)
     FROM app_data.canonical_region_tree_releases
     WHERE tree_version IN (
       'concurrent-region-base', 'concurrent-region-a', 'concurrent-region-b'
     ) AND lifecycle_state = 'published'),
    (SELECT count(*)
     FROM app_data.canonical_region_tree_current_selections
     WHERE selected_tree_version IN (
       'concurrent-region-base', 'concurrent-region-a', 'concurrent-region-b'
     )),
    (SELECT count(*)
     FROM app_data.canonical_region_tree_releases
     WHERE tree_version IN (
       'concurrent-region-base', 'concurrent-region-a', 'concurrent-region-b'
     ) AND content_fingerprint IS NOT NULL),
    (SELECT count(*)
     FROM (
       SELECT selected_at_utc, lag(selected_at_utc) OVER (
         ORDER BY selection_sequence
       ) AS prior_selected_at_utc
       FROM app_data.canonical_region_tree_current_selections
       WHERE selected_tree_version IN (
         'concurrent-region-base', 'concurrent-region-a', 'concurrent-region-b'
       )
     ) AS ordered_selection
     WHERE prior_selected_at_utc > selected_at_utc),
    (SELECT count(*)
     FROM app_data.canonical_region_tree_current_selections AS selection_row
     JOIN app_data.canonical_region_tree_releases AS release_row
       ON release_row.tree_version = selection_row.selected_tree_version
     WHERE selection_row.selected_tree_version IN (
       'concurrent-region-base', 'concurrent-region-a', 'concurrent-region-b'
     )
       AND selection_row.content_fingerprint
         IS DISTINCT FROM release_row.content_fingerprint),
    (SELECT tree_version
     FROM app_data.canonical_region_tree_releases
     WHERE lifecycle_state = 'published' AND is_current);
" | tr -d '\n')"
IFS='|' read -r current_count published_count selection_count fingerprint_count reversed_time_count crossed_fingerprint_count current_version <<< "${result}"
if [[ "${current_count}" -ne 1 \
  || "${published_count}" -ne 3 \
  || "${selection_count}" -ne 3 \
  || "${fingerprint_count}" -ne 3 \
  || "${reversed_time_count}" -ne 0 \
  || "${crossed_fingerprint_count}" -ne 0 \
  || "${current_version}" != 'concurrent-region-b' ]]; then
  echo "并发区域树不变量失败：current=${current_count}, published=${published_count}, selections=${selection_count}, fingerprints=${fingerprint_count}, reversed_times=${reversed_time_count}, crossed_fingerprints=${crossed_fingerprint_count}, current_version=${current_version}" >&2
  exit 1
fi

echo '区域树并发发布通过：解析只见已提交版本，current 单一且选择历史追加。'
