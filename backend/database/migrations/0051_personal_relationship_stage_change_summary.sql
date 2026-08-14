-- 0051_personal_relationship_stage_change_summary.sql
--
-- Backend-only personal stage-change history.  The bridge resolves the
-- external identity itself, serializes with the current-project pointer, and
-- then evaluates one statement snapshot of the append-only revision history.

CREATE INDEX promotion_target_relationship_stage_change_actor_project_time
  ON app_data.promotion_target_relationship_revisions (
    changed_by_app_user_id,
    project_id,
    changed_at
  )
  WHERE old_stage IS NOT NULL
    AND old_stage <> new_stage
    AND reason_code <> 'project_entry'
    AND 'stage' = ANY (changed_fields);

CREATE FUNCTION app_data.read_personal_relationship_stage_change_summary_v1(
  trusted_issuer text,
  trusted_subject text,
  from_utc timestamptz,
  until_utc timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, app_data
AS $function$
DECLARE
  resolved_app_user_id uuid;
  resolved_workspace_id uuid;
  resolved_project_id uuid;
  summary jsonb;
BEGIN
  IF trusted_issuer IS NULL
    OR trusted_subject IS NULL
    OR from_utc IS NULL
    OR until_utc IS NULL
    OR length(btrim(trusted_issuer)) NOT BETWEEN 1 AND 2048
    OR length(btrim(trusted_subject)) NOT BETWEEN 1 AND 512
    OR NOT isfinite(from_utc)
    OR NOT isfinite(until_utc)
    OR from_utc >= until_utc
  THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'invalid personal relationship stage change summary request';
  END IF;

  -- Resolve and lock the identity before looking up the user pointer.  The
  -- caller supplies no app_user, workspace, or project UUID that could widen
  -- the result scope.
  SELECT identity_row.app_user_id
    INTO resolved_app_user_id
  FROM app_data.external_identities AS identity_row
  JOIN app_data.app_users AS user_row
    ON user_row.app_user_id = identity_row.app_user_id
   AND user_row.status = 'active'
  WHERE identity_row.issuer = trusted_issuer
    AND identity_row.subject = trusted_subject
  FOR SHARE OF identity_row, user_row;

  IF resolved_app_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal relationship stage change summary identity is forbidden';
  END IF;

  -- select_personal_project_context updates this same row through its
  -- ON CONFLICT UPDATE path.  FOR UPDATE therefore makes a summary observe
  -- either the complete pointer before a switch or the complete pointer after
  -- the switch; it cannot authorize one project and aggregate another.
  SELECT current_row.project_id
    INTO resolved_project_id
  FROM app_data.user_current_projects AS current_row
  WHERE current_row.app_user_id = resolved_app_user_id
  FOR UPDATE;

  IF resolved_project_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal relationship stage change summary current project is forbidden';
  END IF;

  SELECT workspace_row.workspace_id
    INTO resolved_workspace_id
  FROM app_data.workspaces AS workspace_row
  WHERE workspace_row.workspace_kind = 'personal'
    AND workspace_row.personal_owner_app_user_id = resolved_app_user_id
    AND workspace_row.deleted_at IS NULL
  FOR SHARE OF workspace_row;

  IF resolved_workspace_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal relationship stage change summary workspace is forbidden';
  END IF;

  -- Lock the rows whose status and ownership establish the authorization.  A
  -- concurrent archive or workspace deletion waits here and is observed as a
  -- complete old authorization or a forbidden current scope.
  PERFORM 1
  FROM app_data.projects AS project_row
  WHERE project_row.project_id = resolved_project_id
    AND project_row.workspace_id = resolved_workspace_id
    AND project_row.status = 'active'
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'personal relationship stage change summary project is forbidden';
  END IF;

  -- Keep the history aggregate as one SQL statement.  statement_timestamp()
  -- is stable for that statement, so both metadata fields describe the same
  -- trusted UTC snapshot rather than a client receipt time or historical
  -- as-of value.  Target status, assignment, lifecycle, and current relation
  -- state are deliberately not predicates: prior events remain evidence after
  -- an assignment ends or an object is anonymized.
  WITH snapshot_clock AS (
    SELECT statement_timestamp() AS snapshot_utc
  ), eligible_events AS (
    SELECT
      revision_row.promotion_target_id,
      revision_row.project_id,
      revision_row.old_stage,
      revision_row.new_stage
    FROM app_data.promotion_target_relationship_revisions AS revision_row
    JOIN app_data.promotion_targets AS target_row
      ON target_row.promotion_target_id = revision_row.promotion_target_id
     AND target_row.workspace_id = resolved_workspace_id
    WHERE revision_row.changed_by_app_user_id = resolved_app_user_id
      AND revision_row.project_id = resolved_project_id
      AND revision_row.changed_at >= from_utc
      AND revision_row.changed_at < until_utc
      AND revision_row.old_stage IS NOT NULL
      AND revision_row.old_stage <> revision_row.new_stage
      AND 'stage' = ANY (revision_row.changed_fields)
      AND revision_row.reason_code <> 'project_entry'
  ), totals AS (
    SELECT
      count(*)::bigint AS event_count,
      count(DISTINCT (
        eligible.promotion_target_id,
        eligible.project_id
      ))::bigint AS distinct_relationship_count,
      count(*) FILTER (
        WHERE eligible.new_stage > eligible.old_stage
      )::bigint AS upward_count,
      count(*) FILTER (
        WHERE eligible.new_stage < eligible.old_stage
      )::bigint AS downward_count
    FROM eligible_events AS eligible
  )
  SELECT jsonb_build_object(
    'contract_id', 'personal_relationship_stage_change_summary_result_v1',
    'project_id', resolved_project_id,
    'time_basis', 'relationshipChangedAtUtc',
    'period', jsonb_build_object(
      'from_utc', to_char(
        from_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      ),
      'until_utc', to_char(
        until_utc AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )
    ),
    'data_cutoff_utc', to_char(
      snapshot_clock.snapshot_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'authorized_at_utc', to_char(
      snapshot_clock.snapshot_utc AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'value', jsonb_build_object(
      'event_count', totals.event_count,
      'distinct_relationship_count', totals.distinct_relationship_count,
      'upward_count', totals.upward_count,
      'downward_count', totals.downward_count
    )
  )
    INTO summary
  FROM snapshot_clock
  CROSS JOIN totals;

  RETURN summary;
END
$function$;

COMMENT ON FUNCTION app_data.read_personal_relationship_stage_change_summary_v1(
  text, text, timestamptz, timestamptz
) IS
  'Backend-only personal relationship stage-change summary. The bridge resolves the verified issuer and subject, locks the current project pointer, validates the active personal scope, and aggregates append-only revisions in one UTC statement snapshot without assignment, lifecycle, or target-status filters.';

REVOKE ALL PRIVILEGES ON FUNCTION
  app_data.read_personal_relationship_stage_change_summary_v1(
    text, text, timestamptz, timestamptz
  )
  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  app_data.read_personal_relationship_stage_change_summary_v1(
    text, text, timestamptz, timestamptz
  )
  TO tongxingzhe_runtime;
