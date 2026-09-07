\set ON_ERROR_STOP on

DO $check$
DECLARE
  directory_reader regprocedure := pg_catalog.to_regprocedure(
    'app_data.list_organizations_for_identity_v1(text,text)'
  );
  membership_validator regprocedure := pg_catalog.to_regprocedure(
    'app_private.validate_organization_membership_v1()'
  );
  trusted_owner oid;
  runtime_role oid;
  actual_input_names text[];
  actual_output_names text[];
  actual_output_types text[];
  function_definition text;
BEGIN
  IF directory_reader IS NULL OR membership_validator IS NULL THEN
    RAISE EXCEPTION 'organization directory objects are incomplete';
  END IF;

  SELECT procedure_row.proowner
  INTO STRICT trusted_owner
  FROM pg_catalog.pg_proc AS procedure_row
  WHERE procedure_row.oid = membership_validator;

  SELECT role_row.oid
  INTO STRICT runtime_role
  FROM pg_catalog.pg_roles AS role_row
  WHERE role_row.rolname = 'tongxingzhe_runtime';

  IF trusted_owner = runtime_role THEN
    RAISE EXCEPTION 'organization directory owner cannot be runtime';
  END IF;

  SELECT
    procedure_row.proargnames[1:2],
    array_agg(argument_row.argument_name ORDER BY argument_row.ordinality)
      FILTER (WHERE argument_row.argument_mode = 't'),
    array_agg(
      pg_catalog.format_type(argument_row.argument_type, NULL)
      ORDER BY argument_row.ordinality
    ) FILTER (WHERE argument_row.argument_mode = 't')
  INTO actual_input_names, actual_output_names, actual_output_types
  FROM pg_catalog.pg_proc AS procedure_row
  CROSS JOIN LATERAL unnest(
    procedure_row.proallargtypes,
    procedure_row.proargmodes,
    procedure_row.proargnames
  ) WITH ORDINALITY AS argument_row(
    argument_type,
    argument_mode,
    argument_name,
    ordinality
  )
  WHERE procedure_row.oid = directory_reader
  GROUP BY procedure_row.proargnames;

  IF actual_input_names IS DISTINCT FROM
      ARRAY['trusted_issuer', 'trusted_subject']::text[]
    OR actual_output_names IS DISTINCT FROM ARRAY[
      'organization_workspace_id',
      'organization_name'
    ]::text[]
    OR actual_output_types IS DISTINCT FROM ARRAY['uuid', 'text']::text[]
  THEN
    RAISE EXCEPTION 'organization directory function signature drifted';
  END IF;

  IF (
    SELECT
      procedure_row.proowner <> trusted_owner
      OR NOT procedure_row.proretset
      OR NOT procedure_row.prosecdef
      OR procedure_row.provolatile <> 'v'
      OR procedure_row.proconfig IS DISTINCT FROM
        ARRAY['search_path=pg_catalog']::text[]
    FROM pg_catalog.pg_proc AS procedure_row
    WHERE procedure_row.oid = directory_reader
  ) THEN
    RAISE EXCEPTION 'organization directory function boundary drifted';
  END IF;

  -- PUBLIC 不可执行；runtime 只获得这一个 reader 的 EXECUTE。
  IF NOT pg_catalog.has_function_privilege(
      'tongxingzhe_runtime', directory_reader, 'EXECUTE'
    )
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_proc AS procedure_row
      CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(
          procedure_row.proacl,
          pg_catalog.acldefault('f', procedure_row.proowner)
        )
      ) AS privilege_row
      WHERE procedure_row.oid = directory_reader
        AND (
          privilege_row.grantee = 0
          OR privilege_row.grantee NOT IN (trusted_owner, runtime_role)
          OR privilege_row.privilege_type <> 'EXECUTE'
        )
    )
  THEN
    RAISE EXCEPTION 'organization directory function ACL is incorrect';
  END IF;

  IF pg_catalog.has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.external_identities'::regclass,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.app_users'::regclass,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.organization_memberships'::regclass,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
    OR pg_catalog.has_table_privilege(
      'tongxingzhe_runtime',
      'app_data.workspaces'::regclass,
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
    )
  THEN
    RAISE EXCEPTION 'organization directory granted runtime table access';
  END IF;

  function_definition := pg_catalog.pg_get_functiondef(directory_reader);

  IF (
    char_length(function_definition)
      - char_length(replace(function_definition, 'clock_timestamp()', ''))
  ) / char_length('clock_timestamp()') <> 1
    OR function_definition !~ 'app_data\.external_identities'
    OR function_definition !~ 'app_data\.app_users'
    OR function_definition !~ 'app_data\.organization_memberships'
    OR function_definition !~ 'app_data\.workspaces'
    OR function_definition ~* '\m(insert|update|delete|merge|truncate)\M'
    OR function_definition ~* 'app_data\.(projects|project_memberships|management_report_capability_grants|organization_owner_assignments)'
    OR function_definition ~* 'app_private\.'
  THEN
    RAISE EXCEPTION 'organization directory query scope drifted';
  END IF;

  IF (
    SELECT count(*)
    FROM app_migrations.schema_migrations
    WHERE version = '0089_organization_directory'
  ) <> 1 THEN
    RAISE EXCEPTION 'organization directory migration was not recorded once';
  END IF;
END
$check$;
