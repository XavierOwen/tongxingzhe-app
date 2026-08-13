DO $check$
DECLARE
  ratios_bridge regprocedure := to_regprocedure(
    'app_data.read_personal_interest_level_ratios(uuid,uuid,uuid,timestamptz,timestamptz)'
  );
BEGIN
  IF ratios_bridge IS NULL THEN
    RAISE EXCEPTION 'personal interest level ratios function is missing';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    'app_data.read_personal_interest_level_ratios(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute personal interest level ratios';
  END IF;

  IF has_function_privilege(
    'public',
    'app_data.read_personal_interest_level_ratios(uuid,uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC can execute personal interest level ratios';
  END IF;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.contacts',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime role can read contact rows directly';
  END IF;

  IF (
    SELECT NOT procedure_row.prosecdef
      OR (
        SELECT count(*)
        FROM unnest(coalesce(
          procedure_row.proconfig, ARRAY[]::text[]
        )) AS config_row(setting)
        WHERE config_row.setting ILIKE 'search_path=%'
      ) <> 1
      OR NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(
          procedure_row.proconfig, ARRAY[]::text[]
        )) AS config_row(setting)
        WHERE replace(config_row.setting, ' ', '') =
          'search_path=pg_catalog,app_data'
      )
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = ratios_bridge
  ) THEN
    RAISE EXCEPTION 'personal interest level ratios security boundary is open';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0042_personal_interest_level_ratios'
  ) <> 1 THEN
    RAISE EXCEPTION 'personal interest level ratios migration was not recorded once';
  END IF;
END
$check$;
