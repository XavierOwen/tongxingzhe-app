\set ON_ERROR_STOP on

DO $check$
DECLARE
  protected_table text;
  protected_function text;
BEGIN
  FOREACH protected_table IN ARRAY ARRAY[
    'organization_memberships',
    'project_memberships',
    'management_report_capability_grants'
  ] LOOP
    IF to_regclass('app_data.' || protected_table) IS NULL THEN
      RAISE EXCEPTION 'management authorization table is missing: %',
        protected_table;
    END IF;

    IF has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.' || protected_table,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    ) THEN
      RAISE EXCEPTION 'runtime can access management authorization table: %',
        protected_table;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_data'
      AND table_name IN (
        'organization_memberships',
        'project_memberships',
        'management_report_capability_grants'
      )
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime')
  ) THEN
    RAISE EXCEPTION 'management authorization table privilege matrix is open';
  END IF;

  FOREACH protected_function IN ARRAY ARRAY[
    'app_private.resolve_management_report_authorization_v1(uuid,uuid,text)',
    'app_private.validate_organization_membership_v1()',
    'app_private.validate_project_membership_v1()',
    'app_private.validate_management_report_capability_grant_v1()',
    'app_private.protect_membership_history_v1()'
  ] LOOP
    IF to_regprocedure(protected_function) IS NULL THEN
      RAISE EXCEPTION 'management authorization function is missing: %',
        protected_function;
    END IF;

    IF has_function_privilege(
      'tongxingzhe_runtime',
      protected_function,
      'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'runtime can execute management authorization function: %',
        protected_function;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.routine_privileges
    WHERE specific_schema = 'app_private'
      AND routine_name IN (
        'resolve_management_report_authorization_v1',
        'validate_organization_membership_v1',
        'validate_project_membership_v1',
        'validate_management_report_capability_grant_v1',
        'protect_membership_history_v1'
      )
      AND grantee IN ('PUBLIC', 'tongxingzhe_runtime')
  ) THEN
    RAISE EXCEPTION 'management authorization function privilege matrix is open';
  END IF;

  IF has_schema_privilege(
    'tongxingzhe_runtime',
    'app_private',
    'USAGE'
  ) THEN
    RAISE EXCEPTION 'runtime can use private authorization schema';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_indexes
    WHERE schemaname = 'app_data'
      AND indexname IN (
        'organization_memberships_authorization_idx',
        'project_memberships_authorization_idx',
        'management_report_capability_grants_authorization_idx'
      )
  ) <> 3 THEN
    RAISE EXCEPTION 'management authorization indexes are incomplete';
  END IF;

  IF (
    SELECT function_row.provolatile
    FROM pg_proc AS function_row
    WHERE function_row.oid =
      'app_private.resolve_management_report_authorization_v1(uuid,uuid,text)'::regprocedure
  ) <> 'v' THEN
    RAISE EXCEPTION 'management authorization resolver must hold transaction locks';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'app_data.organization_memberships'::regclass
      AND tgname = 'organization_memberships_validate'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid = 'app_data.project_memberships'::regclass
      AND tgname = 'project_memberships_validate'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
      'app_data.management_report_capability_grants'::regclass
      AND tgname = 'management_report_capability_grants_validate'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'management authorization validation triggers are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_trigger
    WHERE tgrelid IN (
      'app_data.organization_memberships'::regclass,
      'app_data.project_memberships'::regclass,
      'app_data.management_report_capability_grants'::regclass
    )
      AND tgname LIKE '%_protect_history'
      AND NOT tgisinternal
  ) <> 3 THEN
    RAISE EXCEPTION 'management authorization history is not protected';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0030_management_report_authorization'
  ) <> 1 THEN
    RAISE EXCEPTION 'management authorization migration was not recorded once';
  END IF;
END
$check$;
