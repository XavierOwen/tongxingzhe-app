\set ON_ERROR_STOP on

DO $check$
DECLARE
  trusted_owner oid;
  helper oid;
  function_definition text;
  table_name text;
  object_oid oid;
BEGIN
  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0102_organization_report_write_fence') <> 1 THEN
    RAISE EXCEPTION '0102 migration is not recorded exactly once';
  END IF;

  helper := to_regprocedure(
    'app_private.require_active_organization_report_write_v1()'
  );
  SELECT proowner INTO STRICT trusted_owner FROM pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;
  IF helper IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE oid = helper AND proowner = trusted_owner
      AND prosecdef AND provolatile = 'v'
      AND proconfig = ARRAY['search_path=pg_catalog']::text[]
  ) OR has_function_privilege('tongxingzhe_runtime', helper, 'EXECUTE')
    OR EXISTS (
      SELECT 1 FROM pg_proc AS procedure
      CROSS JOIN LATERAL aclexplode(coalesce(
        procedure.proacl, acldefault('f', procedure.proowner))) AS acl
      WHERE procedure.oid = helper AND acl.grantee = 0
    )
  THEN
    RAISE EXCEPTION '0102 helper owner, security, or ACL drift';
  END IF;

  SELECT pg_get_functiondef(helper) INTO function_definition;
  IF strpos(function_definition, 'NEW.project_id') = 0
    OR strpos(function_definition, 'FOR KEY SHARE OF workspace') = 0
    OR strpos(function_definition, 'workspace_kind') = 0
    OR strpos(function_definition, 'workspace_deleted_at') = 0
    OR strpos(function_definition, 'organization report write unavailable') = 0
  THEN
    RAISE EXCEPTION '0102 workspace write-fence contract drift';
  END IF;

  FOREACH table_name IN ARRAY ARRAY[
    'management_report_snapshots',
    'management_report_release_attempts',
    'management_report_release_v2_attempts',
    'management_current_city_report_release_attempts',
    'management_interest_report_release_attempts',
    'management_original_region_report_release_attempts',
    'management_follow_up_consent_report_release_attempts',
    'management_report_snapshot_export_events',
    'management_report_snapshot_replacements',
    'management_original_region_report_snapshot_replacements',
    'management_current_city_report_snapshot_replacements',
    'management_interest_report_snapshot_replacements',
    'management_follow_up_consent_ratio_report_snapshot_replacements',
    'management_follow_up_consent_opt_in_versions'
  ] LOOP
    object_oid := to_regclass('app_private.' || table_name);
    IF object_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = object_oid AND attname = 'project_id'
        AND atttypid = 'uuid'::regtype AND attnum > 0 AND NOT attisdropped
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = object_oid
        AND tgname = 'a_org_report_write_fence'
        AND tgfoid = helper AND tgtype = 7 AND tgenabled = 'O'
    ) OR has_table_privilege('tongxingzhe_runtime', object_oid, 'INSERT')
      OR EXISTS (
        SELECT 1 FROM pg_class AS relation
        CROSS JOIN LATERAL aclexplode(coalesce(
          relation.relacl, acldefault('r', relation.relowner))) AS acl
        WHERE relation.oid = object_oid AND acl.grantee = 0
      )
    THEN
      RAISE EXCEPTION '0102 table fence, project_id, or ACL drift: %', table_name;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM pg_trigger
      WHERE tgfoid = helper AND NOT tgisinternal) <> 14 THEN
    RAISE EXCEPTION '0102 trigger count drift';
  END IF;

  IF NOT has_table_privilege(
      'tongxingzhe_management_consent_ratio_snapshot_release_writer',
      'app_private.management_report_snapshots', 'INSERT')
    OR NOT has_table_privilege(
      'tongxingzhe_management_current_city_snapshot_release_writer',
      'app_private.management_report_snapshots', 'INSERT')
    OR NOT has_table_privilege(
      'tongxingzhe_management_interest_snapshot_release_writer',
      'app_private.management_report_snapshots', 'INSERT')
    OR NOT has_table_privilege(
      'tongxingzhe_management_original_region_snapshot_release_writer',
      'app_private.management_report_snapshots', 'INSERT')
  THEN
    RAISE EXCEPTION '0102 changed a trusted snapshot writer INSERT grant';
  END IF;
END
$check$;
