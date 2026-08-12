\set ON_ERROR_STOP on

DO $check$
DECLARE
  list_contexts regprocedure := to_regprocedure(
    'app_data.list_management_analysis_contexts_v1(text,text)'
  );
  select_context regprocedure := to_regprocedure(
    'app_data.select_management_analysis_context_v1(text,text,uuid)'
  );
BEGIN
  IF to_regclass('app_data.management_analysis_current_contexts') IS NULL
    OR list_contexts IS NULL
    OR select_context IS NULL
  THEN
    RAISE EXCEPTION 'management analysis context contract is incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM information_schema.columns
    WHERE table_schema = 'app_data'
      AND table_name = 'management_analysis_current_contexts'
      AND column_name IN (
        'app_user_id',
        'organization_workspace_id',
        'organization_membership_id',
        'project_id',
        'project_membership_id',
        'capability_grant_id',
        'selected_at_utc'
      )
  ) <> 7 OR (
    SELECT count(*)
    FROM pg_constraint
    WHERE conrelid =
      'app_data.management_analysis_current_contexts'::regclass
      AND contype = 'f'
  ) <> 6 THEN
    RAISE EXCEPTION 'management analysis context evidence is incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_proc AS function_row
    WHERE function_row.oid IN (list_contexts, select_context)
      AND function_row.prosecdef
      AND function_row.provolatile = 'v'
      AND function_row.proconfig = ARRAY['search_path=pg_catalog']::text[]
  ) <> 2 THEN
    RAISE EXCEPTION 'management analysis context functions are not protected';
  END IF;

  IF NOT has_function_privilege(
      'tongxingzhe_runtime', list_contexts, 'EXECUTE'
    ) OR NOT has_function_privilege(
      'tongxingzhe_runtime', select_context, 'EXECUTE'
    ) OR EXISTS (
      SELECT 1
      FROM information_schema.routine_privileges
      WHERE specific_schema = 'app_data'
        AND routine_name IN (
          'list_management_analysis_contexts_v1',
          'select_management_analysis_context_v1'
        )
        AND grantee = 'PUBLIC'
    )
  THEN
    RAISE EXCEPTION 'management analysis context function ACL is incorrect';
  END IF;

  IF has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.management_analysis_current_contexts',
      'SELECT,INSERT,UPDATE,DELETE'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.organization_memberships',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.project_memberships',
      'SELECT'
    ) OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.management_report_capability_grants',
      'SELECT'
    ) OR has_schema_privilege(
      'tongxingzhe_runtime', 'app_private', 'USAGE'
    ) OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.resolve_management_report_authorization_v1(uuid,uuid,text)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime received general management context access';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0034_management_analysis_contexts'
  ) <> 1 THEN
    RAISE EXCEPTION 'management analysis context migration was not recorded once';
  END IF;
END
$check$;
