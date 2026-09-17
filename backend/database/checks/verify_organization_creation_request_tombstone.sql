\set ON_ERROR_STOP on

DO $check$
DECLARE
  tombstones_table regclass :=
    to_regclass('app_private.organization_creation_request_tombstones');
  tombstone_guard regprocedure :=
    to_regprocedure('app_private.protect_organization_creation_request_tombstone_v1()');
  private_writer regprocedure :=
    'app_private.create_organization_v1(uuid,uuid,text)'::regprocedure;
  runtime_bridge regprocedure :=
    'app_data.create_organization_for_identity_v1(text,text,uuid,text)'::regprocedure;
  trusted_owner oid;
  column_names text[];
  column_types text[];
  column_not_null boolean[];
  writer_definition text;
  function_oid oid;
BEGIN
  IF tombstones_table IS NULL OR tombstone_guard IS NULL THEN
    RAISE EXCEPTION 'organization creation tombstone objects are incomplete';
  END IF;

  IF (SELECT count(*) FROM app_migrations.schema_migrations
      WHERE version = '0095_organization_creation_request_tombstone') <> 1 THEN
    RAISE EXCEPTION 'organization creation tombstone migration was not recorded once';
  END IF;

  SELECT proowner INTO STRICT trusted_owner FROM pg_catalog.pg_proc
  WHERE oid = 'app_private.validate_organization_membership_v1()'::regprocedure;

  SELECT array_agg(attname::text ORDER BY attnum),
         array_agg(pg_catalog.format_type(atttypid, atttypmod) ORDER BY attnum),
         array_agg(attnotnull ORDER BY attnum)
  INTO column_names, column_types, column_not_null
  FROM pg_catalog.pg_attribute
  WHERE attrelid = tombstones_table AND attnum > 0 AND NOT attisdropped;
  IF column_names IS DISTINCT FROM ARRAY['claim_family', 'request_id']::text[]
    OR column_types IS DISTINCT FROM ARRAY['text', 'uuid']::text[]
    OR column_not_null IS DISTINCT FROM ARRAY[true, true]::boolean[] THEN
    RAISE EXCEPTION 'organization creation tombstone value-free columns drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = tombstones_table AND contype = 'p'
      AND conkey = ARRAY[1, 2]::smallint[]
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = tombstones_table AND contype = 'c' AND convalidated
      AND pg_catalog.pg_get_constraintdef(oid) =
        'CHECK ((claim_family = ''organization-creation:v1''::text))'
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = tombstones_table AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'organization creation tombstone constraints drifted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger
    WHERE tgrelid = tombstones_table AND tgfoid = tombstone_guard
      AND tgname = 'organization_creation_request_tombstones_immutable'
      AND tgtype = 27 AND tgenabled = 'O' AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'organization creation tombstone immutable guard drifted';
  END IF;

  IF (SELECT relowner FROM pg_catalog.pg_class WHERE oid = tombstones_table)
      IS DISTINCT FROM trusted_owner
    OR pg_catalog.pg_get_userbyid(trusted_owner) = 'tongxingzhe_runtime'
    OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_class AS relation_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(relation_row.relacl, pg_catalog.acldefault('r', relation_row.relowner))
      ) AS privilege_row
      WHERE relation_row.oid = tombstones_table AND privilege_row.grantee = 0
    ) OR has_table_privilege('tongxingzhe_runtime', tombstones_table,
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') THEN
    RAISE EXCEPTION 'organization creation tombstone table ACL drifted';
  END IF;

  FOREACH function_oid IN ARRAY ARRAY[tombstone_guard::oid, private_writer::oid,
                                    runtime_bridge::oid] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc
      WHERE oid = function_oid AND proowner = trusted_owner AND prosecdef
        AND provolatile = 'v' AND proconfig = ARRAY['search_path=pg_catalog']::text[]
    ) OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc AS function_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        coalesce(function_row.proacl, pg_catalog.acldefault('f', function_row.proowner))
      ) AS privilege_row
      WHERE function_row.oid = function_oid AND privilege_row.grantee = 0
    ) THEN
      RAISE EXCEPTION 'organization creation tombstone function boundary drifted';
    END IF;
  END LOOP;
  IF has_function_privilege('tongxingzhe_runtime', private_writer, 'EXECUTE')
    OR has_function_privilege('tongxingzhe_runtime', tombstone_guard, 'EXECUTE')
    OR NOT has_function_privilege('tongxingzhe_runtime', runtime_bridge, 'EXECUTE') THEN
    RAISE EXCEPTION 'organization creation runtime bridge ACL drifted';
  END IF;

  writer_definition := pg_catalog.pg_get_functiondef(private_writer);
  IF strpos(writer_definition, 'organization-creation-request:') = 0
    OR strpos(writer_definition, 'organization_creation_request_tombstones AS tombstone')
      <= strpos(writer_definition, 'organization-creation-request:')
    OR strpos(writer_definition, 'organization_creation_request_claims AS claim')
      <= strpos(writer_definition, 'organization_creation_request_tombstones AS tombstone')
    OR strpos(writer_definition, 'SELECT app_user.status')
      <= strpos(writer_definition, 'organization_creation_request_claims AS claim')
    OR strpos(writer_definition,
      'tombstone.claim_family = ''organization-creation:v1''') = 0
    OR strpos(writer_definition,
      'tombstone.request_id = requested_request_id') = 0
    OR strpos(pg_catalog.pg_get_functiondef(runtime_bridge),
      'FROM app_private.create_organization_v1(') = 0 THEN
    RAISE EXCEPTION 'organization creation request-lock tombstone fence drifted';
  END IF;
END
$check$;
