-- synthetic fixture：证明个人项目可创建、列出和选择，且不能跨用户选择。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE initial_context AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-projects.supabase.co/auth/v1',
  'synthetic-project-owner'
);

CREATE TEMP TABLE created_context AS
SELECT *
FROM app_data.create_personal_project_context(
  'https://synthetic-projects.supabase.co/auth/v1',
  'synthetic-project-owner',
  '校园推广'
);

CREATE TEMP TABLE listed_contexts AS
SELECT *
FROM app_data.list_personal_project_contexts(
  'https://synthetic-projects.supabase.co/auth/v1',
  'synthetic-project-owner'
);

CREATE TEMP TABLE selected_default AS
SELECT selected_row.*
FROM initial_context AS initial_row
CROSS JOIN LATERAL app_data.select_personal_project_context(
  'https://synthetic-projects.supabase.co/auth/v1',
  'synthetic-project-owner',
  initial_row.project_id
) AS selected_row;

DO $fixture$
BEGIN
  IF (SELECT count(*) FROM listed_contexts) <> 2 THEN
    RAISE EXCEPTION 'created personal project was not listed';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM listed_contexts
    WHERE project_name = '校园推广'
      AND is_current
  ) THEN
    RAISE EXCEPTION 'created personal project was not selected';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM selected_default AS selected_row
    JOIN initial_context AS initial_row USING (project_id)
  ) THEN
    RAISE EXCEPTION 'default personal project could not be selected again';
  END IF;

  BEGIN
    PERFORM app_data.select_personal_project_context(
      'https://synthetic-other.supabase.co/auth/v1',
      'synthetic-other-owner',
      (SELECT project_id FROM created_context)
    );
    RAISE EXCEPTION 'another identity selected the owner project';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    INSERT INTO app_data.user_current_projects (app_user_id, project_id)
    SELECT app_user_id, project_id FROM created_context;
    RAISE EXCEPTION 'runtime role changed project selection directly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
END
$fixture$;

ROLLBACK;
