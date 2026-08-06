DO $check$
DECLARE
  runtime_can_mutate boolean;
BEGIN
  SELECT has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.user_current_projects',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  INTO runtime_can_mutate;

  IF runtime_can_mutate THEN
    RAISE EXCEPTION 'runtime role can mutate saved project selections directly';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.list_personal_project_contexts(text,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.select_personal_project_context(text,text,uuid)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.create_personal_project_context(text,text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role lacks a controlled project context function';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0004_personal_project_contexts'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal project context migration was not recorded once';
  END IF;
END
$check$;
