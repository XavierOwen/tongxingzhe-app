\set ON_ERROR_STOP on

-- 6AP 的结构检查先于 fixture 执行：它只确认私有读取合同和权限边界，
-- 不把 0057 的区域 provenance 误当成渠道 v2 provenance。
DO $check$
DECLARE
  protected_function text;
  forbidden_role text;
BEGIN
  IF to_regclass(
      'app_private.management_current_city_report_snapshot_access_events'
    ) IS NULL
    OR to_regprocedure(
      'app_private.read_authorized_management_current_city_report_snapshot_v1(uuid,uuid,uuid)'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'authorized current-city snapshot read contract is incomplete';
  END IF;

  FOREACH forbidden_role IN ARRAY ARRAY[
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher',
    'tongxingzhe_region_mapping_writer',
    'tongxingzhe_contact_provenance_writer',
    'tongxingzhe_region_attribution_reader',
    'tongxingzhe_management_region_report_reader',
    'tongxingzhe_management_current_city_snapshot_release_writer'
  ] LOOP
    IF has_table_privilege(
        forbidden_role,
        'app_private.management_current_city_report_snapshot_access_events',
        'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
      )
    THEN
      RAISE EXCEPTION 'forbidden role can access current-city read audit: %',
        forbidden_role;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.table_privileges
    WHERE table_schema = 'app_private'
      AND table_name =
        'management_current_city_report_snapshot_access_events'
      AND grantee IN (
        'PUBLIC',
        'tongxingzhe_runtime',
        'tongxingzhe_region_publisher',
        'tongxingzhe_region_mapping_writer',
        'tongxingzhe_contact_provenance_writer',
        'tongxingzhe_region_attribution_reader',
        'tongxingzhe_management_region_report_reader',
        'tongxingzhe_management_current_city_snapshot_release_writer'
      )
  ) THEN
    RAISE EXCEPTION 'current-city read audit privilege matrix is open';
  END IF;

  FOREACH protected_function IN ARRAY ARRAY[
    'app_private.read_authorized_management_current_city_report_snapshot_v1(uuid,uuid,uuid)',
    'app_private.validate_current_city_snapshot_access_insert_v1()'
  ] LOOP
    IF to_regprocedure(protected_function) IS NULL THEN
      RAISE EXCEPTION 'current-city read function is missing: %',
        protected_function;
    END IF;

    FOREACH forbidden_role IN ARRAY ARRAY[
      'tongxingzhe_runtime',
      'tongxingzhe_region_publisher',
      'tongxingzhe_region_mapping_writer',
      'tongxingzhe_contact_provenance_writer',
      'tongxingzhe_region_attribution_reader',
      'tongxingzhe_management_region_report_reader',
      'tongxingzhe_management_current_city_snapshot_release_writer'
    ] LOOP
      IF has_function_privilege(
          forbidden_role,
          protected_function,
          'EXECUTE'
        )
      THEN
        RAISE EXCEPTION 'forbidden role can execute current-city read function: % / %',
          forbidden_role,
          protected_function;
      END IF;
    END LOOP;
  END LOOP;

  IF EXISTS (
    SELECT 1
    FROM information_schema.routine_privileges
    WHERE specific_schema = 'app_private'
      AND routine_name IN (
        'read_authorized_management_current_city_report_snapshot_v1',
        'validate_current_city_snapshot_access_insert_v1'
      )
      AND grantee IN (
        'PUBLIC',
        'tongxingzhe_runtime',
        'tongxingzhe_region_publisher',
        'tongxingzhe_region_mapping_writer',
        'tongxingzhe_contact_provenance_writer',
        'tongxingzhe_region_attribution_reader',
        'tongxingzhe_management_region_report_reader',
        'tongxingzhe_management_current_city_snapshot_release_writer'
      )
  ) THEN
    RAISE EXCEPTION 'current-city read function privilege matrix is open';
  END IF;

  IF (
    SELECT function_row.provolatile
    FROM pg_proc AS function_row
    WHERE function_row.oid =
      'app_private.read_authorized_management_current_city_report_snapshot_v1(uuid,uuid,uuid)'::regprocedure
  ) <> 'v' THEN
    RAISE EXCEPTION 'current-city snapshot read must append access history';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.management_current_city_report_snapshot_access_events'::regclass
      AND tgname =
        'current_city_snapshot_access_events_immutable'
      AND NOT tgisinternal
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgrelid =
        'app_private.management_current_city_report_snapshot_access_events'::regclass
      AND tgname =
        'current_city_snapshot_access_events_validate'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'current-city read audit history is not protected';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'app_private'
      AND indexname =
        'current_city_snapshot_access_events_project_idx'
  ) THEN
    RAISE EXCEPTION 'current-city read audit index is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_current_city_report_snapshot_access_events'::regclass
      AND confrelid =
        'app_data.management_report_capability_grants'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_current_city_report_snapshot_access_events'::regclass
      AND confrelid =
        'app_private.management_report_snapshots'::regclass
      AND contype = 'f'
  ) OR NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid =
        'app_private.management_current_city_report_snapshot_access_events'::regclass
      AND confrelid =
        'app_private.management_current_city_report_release_attempts'::regclass
      AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'current-city read audit lineage foreign keys are incomplete';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0058_authorized_management_current_city_report_snapshot_read'
  ) <> 1 THEN
    RAISE EXCEPTION 'current-city snapshot read migration was not recorded once';
  END IF;
END
$check$;
