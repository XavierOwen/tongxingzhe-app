\set ON_ERROR_STOP on

-- An empty migration-check database has no realistic cost distribution and
-- can prefer its zero-cost sequential scan. Disable it only to prove that the
-- production predicate is structurally usable by the intended partial index.
-- This does not predict a deployed cost plan; production still needs ANALYZE
-- and query-plan monitoring as history grows.
SET enable_seqscan = off;

DO $check$
DECLARE
  summary_bridge regprocedure := to_regprocedure(
    'app_data.read_personal_relationship_stage_change_summary_v1(text,text,timestamptz,timestamptz)'
  );
  summary_definition text;
  summary_owner text;
  summary_result text;
  summary_is_security_definer boolean;
  summary_search_path text;
  summary_search_path_count integer;
  stage_change_index regclass := to_regclass(
    'app_data.promotion_target_relationship_stage_change_actor_project_time'
  );
  stage_change_index_definition text;
  stage_change_index_predicate text;
  explain_line text;
  explain_plan text := '';
  pointer_lock_position integer;
  aggregate_position integer;
BEGIN
  IF summary_bridge IS NULL OR stage_change_index IS NULL THEN
    RAISE EXCEPTION 'personal relationship stage change summary seam is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    summary_bridge,
    'EXECUTE'
  ) OR has_function_privilege('public', summary_bridge, 'EXECUTE') THEN
    RAISE EXCEPTION 'personal relationship stage change summary bridge ACL is unsafe';
  END IF;

  IF has_schema_privilege('tongxingzhe_runtime', 'app_private', 'USAGE')
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.external_identities',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.app_users',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.workspaces',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.projects',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.user_current_projects',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.promotion_targets',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.promotion_target_assignments',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.promotion_target_project_relationships',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.promotion_target_relationship_revisions',
      'SELECT'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass personal relationship stage change summary seam';
  END IF;

  SELECT
    pg_get_function_result(procedure_row.oid),
    pg_get_functiondef(procedure_row.oid),
    owner_role.rolname,
    procedure_row.prosecdef,
    (
      SELECT count(*)::integer
      FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
    ),
    (
      SELECT config_row.setting
      FROM unnest(coalesce(procedure_row.proconfig, ARRAY[]::text[]))
        AS config_row(setting)
      WHERE config_row.setting ILIKE 'search_path=%'
      LIMIT 1
    )
  INTO summary_result,
    summary_definition,
    summary_owner,
    summary_is_security_definer,
    summary_search_path_count,
    summary_search_path
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = summary_bridge;

  IF summary_result IS DISTINCT FROM 'jsonb'
    OR summary_owner = 'tongxingzhe_runtime'
    OR NOT summary_is_security_definer
    OR summary_search_path_count <> 1
    OR replace(summary_search_path, ' ', '') <>
      'search_path=pg_catalog,app_data'
  THEN
    RAISE EXCEPTION 'personal relationship stage change summary security contract drifted';
  END IF;

  IF summary_definition !~* 'trusted_issuer'
    OR summary_definition !~* 'trusted_subject'
    OR summary_definition !~* 'external_identities'
    OR summary_definition !~* 'app_users'
    OR summary_definition !~* 'user_current_projects'
    OR summary_definition !~* 'FOR UPDATE'
    OR summary_definition !~* 'workspace_kind = ''personal'''
    OR summary_definition !~* 'deleted_at IS NULL'
    OR summary_definition !~* 'status = ''active'''
    OR summary_definition !~* 'statement_timestamp'
    OR summary_definition !~* 'data_cutoff_utc'
    OR summary_definition !~* 'authorized_at_utc'
    OR summary_definition !~* 'changed_by_app_user_id'
    OR summary_definition !~* 'old_stage'
    OR summary_definition !~* 'changed_fields'
    OR summary_definition !~* 'reason_code'
    OR summary_definition !~* 'promotion_targets'
    OR summary_definition ~* 'promotion_target_assignments'
    OR summary_definition ~* 'current_lifecycle_status'
    OR summary_definition ~* 'target_row\.status'
  THEN
    RAISE EXCEPTION 'personal relationship stage change summary scope or metadata drifted';
  END IF;

  pointer_lock_position := position('FOR UPDATE' IN upper(summary_definition));
  aggregate_position := position('statement_timestamp' IN lower(summary_definition));
  IF pointer_lock_position = 0
    OR aggregate_position = 0
    OR pointer_lock_position >= aggregate_position
  THEN
    RAISE EXCEPTION 'current project pointer is not locked before the snapshot aggregate';
  END IF;

  SELECT pg_get_indexdef(index_row.indexrelid),
         pg_get_expr(index_row.indpred, index_row.indrelid)
    INTO stage_change_index_definition, stage_change_index_predicate
  FROM pg_catalog.pg_index AS index_row
  WHERE index_row.indexrelid = stage_change_index;

  IF stage_change_index_definition !~* '\(changed_by_app_user_id, project_id, changed_at\)'
    OR stage_change_index_predicate !~* 'old_stage IS NOT NULL'
    OR stage_change_index_predicate !~* 'old_stage <> new_stage'
    OR stage_change_index_predicate !~* 'reason_code <> ''project_entry'''
    OR stage_change_index_predicate !~* 'stage'
  THEN
    RAISE EXCEPTION 'stage-change actor/project/time partial index drifted';
  END IF;

  FOR explain_line IN EXECUTE $explain$
    EXPLAIN (COSTS OFF)
    SELECT revision_row.promotion_target_id
    FROM app_data.promotion_target_relationship_revisions AS revision_row
    JOIN app_data.promotion_targets AS target_row
      ON target_row.promotion_target_id = revision_row.promotion_target_id
     AND target_row.workspace_id = '00000000-0000-4000-8000-000000000001'::uuid
    WHERE revision_row.changed_by_app_user_id =
        '00000000-0000-4000-8000-000000000002'::uuid
      AND revision_row.project_id =
        '00000000-0000-4000-8000-000000000003'::uuid
      AND revision_row.changed_at >= '2030-01-01T00:00:00Z'::timestamptz
      AND revision_row.changed_at < '2030-01-08T00:00:00Z'::timestamptz
      AND revision_row.old_stage IS NOT NULL
      AND revision_row.old_stage <> revision_row.new_stage
      AND 'stage' = ANY (revision_row.changed_fields)
      AND revision_row.reason_code <> 'project_entry'
  $explain$ LOOP
    explain_plan := explain_plan || explain_line || E'\n';
  END LOOP;

  IF explain_plan !~* 'promotion_target_relationship_stage_change_actor_project_time' THEN
    RAISE EXCEPTION
      'stage-change history query does not use the actor/project/time partial index: %',
      explain_plan;
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0051_personal_relationship_stage_change_summary'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal relationship stage change summary migration was not recorded once';
  END IF;
END
$check$;
