\set ON_ERROR_STOP on

DO $check$
BEGIN
  IF to_regclass('app_private.management_report_snapshots') IS NULL
    OR to_regclass(
      'app_private.management_report_release_attempts'
    ) IS NULL
    OR to_regprocedure(
      'app_private.release_management_report_snapshot_v1(uuid,uuid,uuid,text,integer,text,timestamp with time zone,timestamp with time zone)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.read_management_report_snapshot_v1(uuid)'
    ) IS NULL
    OR to_regprocedure(
      'app_private.validate_management_report_release_attempt_insert_v1()'
    ) IS NULL
  THEN
    RAISE EXCEPTION 'management report snapshot contract is incomplete';
  END IF;

  IF has_schema_privilege(
      'tongxingzhe_runtime',
      'app_private',
      'USAGE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'INSERT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'UPDATE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'DELETE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_snapshots',
      'TRUNCATE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_attempts',
      'SELECT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_attempts',
      'INSERT'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_attempts',
      'UPDATE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_attempts',
      'DELETE'
    )
    OR has_table_privilege(
      'tongxingzhe_runtime',
      'app_private.management_report_release_attempts',
      'TRUNCATE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.release_management_report_snapshot_v1(uuid,uuid,uuid,text,integer,text,timestamp with time zone,timestamp with time zone)',
      'EXECUTE'
    )
    OR has_function_privilege(
      'tongxingzhe_runtime',
      'app_private.read_management_report_snapshot_v1(uuid)',
      'EXECUTE'
    )
  THEN
    RAISE EXCEPTION 'runtime can bypass report snapshot authorization';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0028_management_report_snapshots'
  ) <> 1 THEN
    RAISE EXCEPTION 'management report snapshot migration was not recorded once';
  END IF;
END
$check$;
