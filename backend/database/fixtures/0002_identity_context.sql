-- synthetic fixture：证明身份映射和个人上下文稳定、隔离并可重复执行。
BEGIN;

SET LOCAL ROLE tongxingzhe_runtime;

CREATE TEMP TABLE first_bootstrap AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-a.supabase.co/auth/v1',
  'synthetic-subject-1'
);

CREATE TEMP TABLE repeated_bootstrap AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-a.supabase.co/auth/v1',
  'synthetic-subject-1'
);

CREATE TEMP TABLE other_issuer_bootstrap AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-b.supabase.co/auth/v1',
  'synthetic-subject-1'
);

CREATE TEMP TABLE opaque_subject_bootstrap AS
SELECT *
FROM app_data.bootstrap_personal_context(
  'https://synthetic-a.supabase.co/auth/v1',
  ' synthetic-subject-1 '
);

DO $fixture$
BEGIN
  IF (
    SELECT count(*)
    FROM first_bootstrap AS first_row
    JOIN repeated_bootstrap AS repeated_row
      USING (
        app_user_id,
        workspace_id,
        project_id,
        questionnaire_version_id
      )
  ) <> 1 THEN
    RAISE EXCEPTION 'repeated bootstrap changed stable context IDs';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM first_bootstrap AS first_row
    JOIN other_issuer_bootstrap AS other_row
      USING (app_user_id)
  ) THEN
    RAISE EXCEPTION 'same subject from different issuers shared an app user';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM first_bootstrap AS first_row
    JOIN opaque_subject_bootstrap AS opaque_row
      USING (app_user_id)
  ) THEN
    RAISE EXCEPTION 'opaque subject was normalized before mapping';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM first_bootstrap
    WHERE workspace_kind <> 'personal'
      OR workspace_name <> '个人空间'
      OR project_name <> '我的推广项目'
      OR questionnaire_version_number <> 1
      OR capabilities <> ARRAY['record_contact']::text[]
  ) THEN
    RAISE EXCEPTION 'bootstrap returned an invalid personal context';
  END IF;

  BEGIN
    INSERT INTO app_data.external_identities (
      issuer,
      subject,
      app_user_id
    )
    SELECT
      'https://forged.example.test',
      'forged-subject',
      app_user_id
    FROM first_bootstrap;

    RAISE EXCEPTION 'runtime role inserted a forged identity mapping';
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;

  BEGIN
    PERFORM app_data.bootstrap_personal_context('', 'synthetic-subject');
    RAISE EXCEPTION 'empty trusted issuer was accepted';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      NULL;
  END;
END
$fixture$;

ROLLBACK;
