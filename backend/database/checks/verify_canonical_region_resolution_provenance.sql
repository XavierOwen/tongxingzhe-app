-- 验证 6T 的窄 resolver bridge、冻结 release 事实和最小权限。
DO $check$
DECLARE
  function_oid oid;
  function_definition text;
  function_owner text;
  acl_row record;
BEGIN
  function_oid := to_regprocedure(
    'app_data.resolve_canonical_region_with_provenance(double precision,double precision)'
  );
  IF function_oid IS NULL THEN
    RAISE EXCEPTION 'canonical region provenance resolver is missing';
  END IF;

  SELECT
    pg_get_functiondef(procedure_row.oid),
    owner_role.rolname
  INTO function_definition, function_owner
  FROM pg_catalog.pg_proc AS procedure_row
  JOIN pg_catalog.pg_roles AS owner_role
    ON owner_role.oid = procedure_row.proowner
  WHERE procedure_row.oid = function_oid
    AND procedure_row.prosecdef;
  IF function_definition IS NULL THEN
    RAISE EXCEPTION 'canonical region provenance resolver is not SECURITY DEFINER';
  END IF;
  IF function_owner IN (
    'tongxingzhe_runtime',
    'tongxingzhe_region_publisher'
  ) THEN
    RAISE EXCEPTION 'canonical region provenance resolver owner is over-privileged: %',
      function_owner;
  END IF;

  IF function_definition NOT LIKE '%resolve_canonical_region(%'
    OR function_definition NOT LIKE '%lifecycle_state = ''published''%'
    OR function_definition NOT LIKE '%content_fingerprint ~ ''^[0-9a-f]{64}$''%'
    OR function_definition NOT LIKE '%canonical-region-resolution:v1%'
  THEN
    RAISE EXCEPTION 'canonical region provenance resolver is not fail-closed';
  END IF;
  IF function_definition ILIKE '%contact_revisions%'
    OR function_definition ILIKE '%contact_location_provenance%'
    OR function_definition ILIKE '%locationSource%'
  THEN
    RAISE EXCEPTION 'canonical region provenance resolver reads location history';
  END IF;

  IF NOT has_function_privilege(
    'tongxingzhe_runtime',
    function_oid,
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute the provenance resolver';
  END IF;
  IF has_function_privilege(
    'tongxingzhe_region_publisher',
    function_oid,
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'region publisher can execute the runtime provenance resolver';
  END IF;

  -- aclexplode uses grantee 0 for PUBLIC.  Check both the public ACL and all
  -- explicit grants so a later migration cannot silently widen this bridge.
  FOR acl_row IN
    SELECT exploded.grantee, exploded.privilege_type
    FROM aclexplode(
      COALESCE(
        (
          SELECT procedure_row.proacl
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = function_oid
        ),
        acldefault('f', (
          SELECT procedure_row.proowner
          FROM pg_catalog.pg_proc AS procedure_row
          WHERE procedure_row.oid = function_oid
        ))
      )
    ) AS exploded
    WHERE exploded.privilege_type = 'EXECUTE'
  LOOP
    IF acl_row.grantee = 0 THEN
      RAISE EXCEPTION 'PUBLIC can execute the provenance resolver';
    END IF;
    IF acl_row.grantee <> (
      SELECT oid
      FROM pg_catalog.pg_roles
      WHERE rolname = 'tongxingzhe_runtime'
    ) AND acl_row.grantee <> (
      SELECT proowner
      FROM pg_catalog.pg_proc
      WHERE oid = function_oid
    ) THEN
      RAISE EXCEPTION 'unexpected provenance resolver EXECUTE grant: %',
        acl_row.grantee;
    END IF;
  END LOOP;

  IF has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.canonical_region_tree_releases',
    'SELECT'
  ) OR has_table_privilege(
    'tongxingzhe_runtime',
    'app_data.canonical_region_boundaries',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'runtime can bypass the provenance resolver through region tables';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0040_canonical_region_resolution_provenance'
  ) <> 1 THEN
    RAISE EXCEPTION 'canonical region provenance migration was not recorded once';
  END IF;
END
$check$;
